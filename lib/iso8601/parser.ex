defmodule Tempo.Iso8601.Parser do
  @moduledoc false

  alias Tempo.Duration
  alias Tempo.Iso8601.AST
  alias Tempo.Iso8601.Unit

  def parse(tokens, calendar) do
    # A top-level qualifier's position carries its ISO 8601-2 §8
    # meaning: at the rightmost end it is *complete* (§8.2.1); at the
    # leftmost end, left of the first component, it is *individual*
    # qualification of that component (§8.2.3).
    {leading, tokens} = pop_leading_qualification(tokens)
    {trailing, tokens} = pop_trailing_qualification(tokens)

    tokens
    |> parse()
    |> put_calendar(calendar)
    |> apply_complete_qualification(trailing)
    |> apply_leading_qualification(leading)
    |> wrap(:ok)
  rescue
    e in Tempo.ParseError ->
      {:error, e}
  end

  # Date/time components in resolution order (coarsest → finest); the
  # leftmost component a leading qualifier individually qualifies is
  # the coarsest one present.
  @resolution_order [:year, :month, :day, :hour, :minute, :second]

  defp pop_leading_qualification([{:qualification, q} | rest]), do: {q, rest}
  defp pop_leading_qualification(tokens), do: {nil, tokens}

  defp pop_trailing_qualification(tokens) when is_list(tokens) do
    case List.last(tokens) do
      {:qualification, q} -> {q, Enum.drop(tokens, -1)}
      _ -> {nil, tokens}
    end
  end

  defp pop_trailing_qualification(tokens), do: {nil, tokens}

  # Complete qualification (§8.2.1) — the whole expression. For an
  # interval it attaches to both endpoints so every sub-value carries
  # it; callers can read the aggregate off either endpoint.
  defp apply_complete_qualification(result, nil), do: result

  defp apply_complete_qualification(%Tempo{} = tempo, qualification) do
    %{tempo | qualification: combine_qualification(tempo.qualification, qualification)}
  end

  defp apply_complete_qualification(%Tempo.Interval{} = interval, qualification) do
    %{
      interval
      | from: apply_complete_qualification(interval.from, qualification),
        to: apply_complete_qualification(interval.to, qualification)
    }
  end

  defp apply_complete_qualification(%Tempo.Set{set: set} = s, qualification) do
    %{s | set: Enum.map(set, &apply_complete_qualification(&1, qualification))}
  end

  defp apply_complete_qualification(%Tempo.Duration{} = duration, _qualification), do: duration

  defp apply_complete_qualification(other, _qualification), do: other

  # Individual qualification of the leftmost (coarsest) component
  # present (§8.2.3). Only a single date/time value carries components;
  # for intervals and sets the leading qualifier falls back to the
  # whole-expression behaviour.
  defp apply_leading_qualification(result, nil), do: result

  defp apply_leading_qualification(%Tempo{time: time} = tempo, qualification)
       when is_list(time) do
    case Enum.find(@resolution_order, &Keyword.has_key?(time, &1)) do
      nil ->
        apply_complete_qualification(tempo, qualification)

      unit ->
        qualifications =
          Map.update(
            tempo.qualifications || %{},
            unit,
            qualification,
            &combine_qualification(&1, qualification)
          )

        %{tempo | qualifications: qualifications}
    end
  end

  defp apply_leading_qualification(other, qualification) do
    apply_complete_qualification(other, qualification)
  end

  defp combine_qualification(nil, qualification), do: qualification
  defp combine_qualification(qualification, qualification), do: qualification
  defp combine_qualification(_a, _b), do: :uncertain_and_approximate

  def parse([{type, tokens}]) when type in [:date, :time_of_day, :datetime] do
    if has_one_of_component?(tokens) do
      # A component-level one-of (`[1,2,3]M`) distributes across the
      # whole value: each alternative becomes a member of a one-of
      # `Tempo.Set` (`[1,2,3]M` → one of `1M`, `2M`, `3M`).
      tokens
      |> distribute_one_of()
      |> Enum.map(&parse_date/1)
      |> Tempo.Set.new(:one)
    else
      AST.build(parse_date(tokens))
    end
  end

  def parse(interval: tokens) do
    if interval_has_one_of?(tokens) do
      # A one-of in an endpoint (`2020Y[1,2]M/2021Y`) distributes to a
      # one-of set of intervals (one of `2020Y1M/2021Y`, `2020Y2M/2021Y`).
      tokens
      |> distribute_interval_one_of()
      |> Enum.map(&{:interval, &1})
      |> then(&parse(one_of: &1))
    else
      AST.build_interval(parse_date(tokens))
    end
  end

  def parse(duration: tokens) do
    tokens
    |> parse_date()
    |> adjust_for_direction()
    |> Duration.build()
  end

  def parse(all_of: tokens) do
    tokens
    |> parse_set
    |> Tempo.Set.new(:all)
  end

  def parse(one_of: tokens) do
    tokens
    |> parse_set
    |> Tempo.Set.new(:one)
  end

  defp has_one_of_component?(tokens) when is_list(tokens) do
    Enum.any?(tokens, &match?({_component, {:one_of, _choices}}, &1))
  end

  defp has_one_of_component?(_tokens), do: false

  # Cartesian product of every component's choices. A `{:one_of, …}`
  # component contributes its alternatives (ranges expanded to their
  # members); every other component is carried unchanged. Returns a
  # list of concrete token lists, one per combination.
  defp distribute_one_of(tokens) do
    Enum.reduce(tokens, [[]], fn
      {component, {:one_of, choices}}, combos ->
        values = Enum.flat_map(choices, &expand_one_of_choice/1)
        for combo <- combos, value <- values, do: combo ++ [{component, value}]

      entry, combos ->
        for combo <- combos, do: combo ++ [entry]
    end)
  end

  defp expand_one_of_choice(%Range{} = range), do: Enum.to_list(range)
  defp expand_one_of_choice(value), do: [value]

  defp interval_has_one_of?(tokens) do
    Enum.any?(tokens, fn
      {_kind, components} when is_list(components) -> has_one_of_component?(components)
      _other -> false
    end)
  end

  # Distribute a one-of within any endpoint across the whole interval:
  # the cartesian product of each endpoint's combinations, yielding a
  # list of concrete interval token lists.
  defp distribute_interval_one_of(tokens) do
    Enum.reduce(tokens, [[]], fn
      {kind, components}, combos when is_list(components) ->
        endpoints = distribute_one_of(components)
        for combo <- combos, endpoint <- endpoints, do: combo ++ [{kind, endpoint}]

      entry, combos ->
        for combo <- combos, do: combo ++ [entry]
    end)
  end

  def parse_set(set) do
    Enum.map(set, &parse_set_member/1)
  end

  # An excluded member (`^…` in the set syntax) keeps its `:except` tag through
  # to `Tempo.Set.new/3`, which routes it to the set's `:except`; its inner
  # member parses exactly as a plain one.
  defp parse_set_member({:except, [member]}) do
    {:except, parse_set_member(member)}
  end

  defp parse_set_member({:range, [{_, from}, {_, to}]}) do
    from = parse_date(from)
    to = parse_date(to)
    validate_range(from, to)
  end

  defp parse_set_member({:range, [from, :undefined]}) do
    {:range, [parse_date(from), :undefined]}
  end

  defp parse_set_member({:range, [:undefined, to]}) do
    {:range, [:undefined, parse_date(to)]}
  end

  defp parse_set_member({unit, %Range{first: first, last: last}}) do
    {:range, [[{unit, first}], [{unit, last}]]}
  end

  # An interval member keeps its tag so `Tempo.Set.new/3` builds it with
  # `build_interval/1` rather than as a plain `Tempo`.
  defp parse_set_member({:interval, tokens}) do
    {:interval, parse_date(tokens)}
  end

  defp parse_set_member(tempo) do
    tempo
    |> elem(1)
    |> parse_date()
  end

  # Split a `{:filter, …}` year-filter token (from `{…}e`/`o`/`l`) off the
  # domain's members, returning `{filter, plain_members}`.
  defp extract_domain_filter(members) do
    case Enum.split_with(members, &match?({:filter, _}, &1)) do
      {[{:filter, filter}], plain} -> {filter, plain}
      {[], plain} -> {nil, plain}
    end
  end

  # Date and time parsing

  def parse_date([{:date, date} | rest]) do
    [{:date, parse_date(date)} | parse_date(rest)]
  end

  def parse_date([{:repeat_rule, date} | rest]) do
    [{:repeat_rule, parse_date(date)} | parse_date(rest)]
  end

  def parse_date([{:century, century} | rest]) do
    parse_date([{:year, {:group, round(century * 100)..round((century + 1) * 100 - 1)}} | rest])
  end

  def parse_date([{:decade, century} | rest]) do
    parse_date([{:year, {:group, round(century * 10)..round((century + 1) * 10 - 1)}} | rest])
  end

  def parse_date([{:group, group_1}, {:group, group_2} | rest]) do
    {_min_1, max_1} = group_min_max(group_1)
    {min_2, _max} = group_min_max(group_2)

    if Unit.compare(max_1, min_2) == :lt do
      raise Tempo.ParseError,
            "Group max of #{inspect(group_1)} is less than the group min of #{inspect(group_2)}"
    else
      [{:group, parse_date(group_1)} | parse_date([{:group, group_2} | rest])]
    end
  end

  # A selection adjacent to a group (in either order). The generic
  # unit/group and unit/selection clauses below would bind the
  # `:selection`/`:group` tag as a unit and pass it to
  # `Unit.compare/2`, which has no sort key for it and raises a
  # `KeyError`. Validate the resolution ordering from each wrapper's
  # own units instead, mirroring the group/group clause above.
  def parse_date([{:selection, selection}, {:group, group} | rest]) do
    unless Unit.ordered?(selection) do
      raise Tempo.ParseError,
            "Selection time units must be in decreasing time scale order. Found #{inspect(selection)}."
    end

    {_min_1, max_1} = selection_min_max(selection)
    {min_2, _max} = group_min_max(group)

    if Unit.compare(max_1, min_2) == :lt do
      raise Tempo.ParseError,
            "selection #{inspect(selection)} is finer than the following group #{inspect(group)}"
    else
      selection = parse_date(selection) |> reduce_list()
      [{:selection, selection} | parse_date([{:group, group} | rest])]
    end
  end

  def parse_date([{:group, group}, {:selection, selection} | rest]) do
    {_min_1, max_1} = group_min_max(group)
    {min_2, _max} = selection_min_max(selection)

    if Unit.compare(max_1, min_2) == :lt do
      raise Tempo.ParseError,
            "group #{inspect(group)} is finer than the following selection #{inspect(selection)}"
    else
      [{:group, parse_date(group)} | parse_date([{:selection, selection} | rest])]
    end
  end

  def parse_date([{unit_1, value_1}, {:group, group} | rest]) do
    {min, _max} = group_min_max(group)

    if Unit.compare(unit_1, min) == :lt do
      raise Tempo.ParseError, "#{inspect(unit_1)} is less than the group min of #{inspect(min)}"
    else
      [parse_date({unit_1, value_1}) | parse_date([{:group, group} | rest])]
    end
  end

  # A group followed by a selection or another group is handled by
  # the dedicated clauses above; this clause covers a plain unit.
  def parse_date([{:group, group}, {unit_2, value_2} | rest]) do
    {_min, max} = group_min_max(group)

    if Unit.compare(max, unit_2) == :lt do
      raise Tempo.ParseError,
            "#{inspect(unit_2)} is greater than the group max of #{inspect(max)}"
    else
      [{:group, parse_date(group)} | parse_date([{unit_2, value_2} | rest])]
    end
  end

  def parse_date([{unit_1, value_1}, {:selection, selection} | rest]) do
    {min, _max} = selection_min_max(selection)

    if Unit.compare(unit_1, min) == :lt do
      raise Tempo.ParseError,
            "#{inspect(unit_1)} is less than the selection min of #{inspect(min)}"
    else
      [parse_date({unit_1, value_1}) | parse_date([{:selection, selection} | rest])]
    end
  end

  def parse_date([{:selection, selection}, {unit_2, value_2} | rest]) do
    {_min, max} = selection_min_max(selection)

    unless Unit.ordered?(selection) do
      raise Tempo.ParseError,
            "Selection time units must be in decreasing time scale order. Found #{inspect(selection)}."
    end

    if Unit.compare(max, unit_2) == :lt do
      raise Tempo.ParseError,
            "#{inspect(unit_2)} is greater than the selection max of #{inspect(max)}"
    else
      selection = parse_date(selection) |> reduce_list()
      [{:selection, selection} | parse_date([{unit_2, value_2} | rest])]
    end
  end

  def parse_date([{:selection, selection} | rest]) do
    unless Unit.ordered?(selection) do
      raise Tempo.ParseError,
            "Selection time units must be in decreasing time scale order. Found #{inspect(selection)}."
    end

    selection = parse_date(selection) |> reduce_list()
    [{:selection, selection} | parse_date(rest)]
  end

  def parse_date([{:interval, interval} | rest]) do
    interval = parse([{:interval, interval}])
    [{:interval, interval} | parse_date(rest)]
  end

  def parse_date([{:duration, duration} | rest]) do
    duration = adjust_for_direction(duration)
    [{:duration, duration} | parse_date(rest)]
  end

  def parse_date([{:group, group} | rest]) do
    [{:group, parse_date(group)} | parse_date(rest)]
  end

  # A recurrence domain — the `{…}` start of `R/{2020Y..2030Y,^2026Y}/P1Y`,
  # tokenised as `:domain_set` — is built here into a `%Tempo.Set{}` (with its
  # `^` exclusions) and tagged `:domain`, so `Tempo.Interval.build/1` lands it in
  # `:from` as the recurrence's window. Building it in the parser keeps set
  # construction out of `Tempo.Interval`, avoiding a module cycle.
  def parse_date([{:domain_set, members} | rest]) do
    {filter, plain} = extract_domain_filter(members)
    domain = plain |> parse_set() |> Tempo.Set.new(:all)
    [{:domain, %{domain | filter: filter}} | parse_date(rest)]
  end

  def parse_date([{component, {:all_of, list}} | rest]) do
    [{component, reduce_list(list)} | parse_date(rest)]
  end

  def parse_date([{component, list} | rest]) when is_list(list) do
    [{component, reduce_list(list)} | parse_date(rest)]
  end

  def parse_date([{component, {:mask, :"X*"}} | rest]) do
    [{component, :any} | parse_date(rest)]
  end

  def parse_date([{component, {:mask, list}} | rest]) when is_list(list) do
    [{component, {:mask, reduce_sublists(list)}} | parse_date(rest)]
  end

  def parse_date([h | t]) do
    [h | parse_date(t)]
  end

  def parse_date([]) do
    []
  end

  def parse_date({unit, value}) do
    [{unit, value}]
    |> parse_date()
    |> hd()
  end

  # Time

  def parse_time([h | t]) do
    [h | parse_time(t)]
  end

  def parse_time([]) do
    []
  end

  # Datetime

  def parse_datetime([h | t]) do
    [h | parse_datetime(t)]
  end

  def parse_datetime([]) do
    []
  end

  # Interval

  def parse_interval([{:date, date} | t]) do
    [{:date, parse_date(date)} | parse_interval(t)]
  end

  def parse_interval([h | t]) do
    [h | parse_interval(t)]
  end

  def parse_interval([]) do
    []
  end

  # Duration

  def parse_duration(datetime: tokens) do
    parse_duration(tokens)
  end

  def parse_duration(date: tokens) do
    parse_duration(tokens)
  end

  def parse_duration([h | t]) do
    [h | parse_duration(t)]
  end

  def parse_duration([]) do
    []
  end

  # Helpers

  def reduce_sublists(list) do
    Enum.map(list, fn
      list when is_list(list) -> reduce_list(list)
      other -> other
    end)
  end

  def group_min_max(group) do
    group = Keyword.delete(group, :nth) |> Keyword.delete(:all_of) |> Keyword.delete(:one_of)
    sorted = Unit.sort(group)
    Tempo.unit_min_max(sorted)
  end

  def selection_min_max(selection) do
    Tempo.unit_min_max(selection)
  end

  # Keyword list
  def reduce_list([{key, _value} | _rest] = list) when is_atom(key) do
    list
  end

  def reduce_list([%module{} | _rest] = list) when module != Range do
    list
  end

  # The list has a set in it, we need to reduce
  # the set
  def reduce_list([first | rest]) when is_list(first) do
    [reduce_list(first) | reduce_list(rest)]
  end

  # Number or range list. Sort ascending before consolidating so consecutive
  # values merge into ranges — but only when every member is non-negative. A
  # negative member is a sentinel (`BYMONTHDAY=1,-1` = the first and *last* day)
  # or a BCE year, where position carries meaning, so the list is left in source
  # order; sorting it would reorder occurrences and break round-tripping.
  def reduce_list(list) when is_list(list) do
    list
    |> sort_unless_signed()
    |> consolidate_ranges()
  end

  def reduce_list(other) do
    other
  end

  defp sort_unless_signed(list) do
    if Enum.any?(list, &signed_member?/1) do
      list
    else
      Enum.sort_by(list, fn
        a when is_integer(a) -> a
        %Range{} = a -> a.first
      end)
    end
  end

  defp signed_member?(member) when is_integer(member), do: member < 0
  defp signed_member?(%Range{first: first, last: last}), do: first < 0 or last < 0
  defp signed_member?(_other), do: false

  # A repeat-rule selection built from RRULE/cron `BY…` parts holds raw integer
  # lists (`BYDAY=MO,TU,WE,TH,FR` → `[1, 2, 3, 4, 5]`). Parsing the same
  # selection back from ISO 8601 consolidates consecutive runs into ranges
  # (`[1..5]`) as a readability aid, so a builder must apply the same
  # consolidation for a value to round-trip. Only integer-list values are
  # touched; `:byday` ordinal pairs and scalar filters are left as-is.
  def consolidate_selection(selection) when is_list(selection) do
    Enum.map(selection, fn
      {unit, value} when is_list(value) -> {unit, consolidate_list_value(value)}
      other -> other
    end)
  end

  # Merge already-ascending consecutive runs (`[1, 2, 3, 4, 5]` → `[1..5]`)
  # without sorting: an RRULE `BYMONTHDAY=1,-1` keeps its order (a leading `-1`
  # is a "last day" sentinel, not a value to reorder), and the common weekday
  # and month lists are written ascending already.
  defp consolidate_list_value(value) do
    if Enum.all?(value, &is_integer/1),
      do: consolidate_ranges(value),
      else: value
  end

  # Consolidate overlapping, adjacent and enclosing
  # ranges. Remove integers that fit within or are
  # adjacent to ranges. Collapse sequences of integers
  # into a range.

  def consolidate_ranges([]) do
    []
  end

  def consolidate_ranges([h]) do
    [h]
  end

  def consolidate_ranges([a, a | rest]) do
    consolidate_ranges([a | rest])
  end

  def consolidate_ranges([a, b | rest]) when a + 1 == b do
    consolidate_ranges([a..b | rest])
  end

  def consolidate_ranges([a, b | rest]) when is_integer(a) and is_integer(b) do
    [a | consolidate_ranges([b | rest])]
  end

  def consolidate_ranges([a, %Range{first: first, last: last} = range | rest])
      when is_integer(a) do
    cond do
      a >= first && a <= last ->
        consolidate_ranges([range | rest])

      a + 1 == first ->
        consolidate_ranges([%{range | first: a} | rest])

      true ->
        [a | consolidate_ranges([range | rest])]
    end
  end

  def consolidate_ranges([%Range{last: last} = range, b | rest]) when is_integer(b) do
    cond do
      b <= last ->
        consolidate_ranges([range | rest])

      last + 1 == b ->
        consolidate_ranges([%{range | last: b} | rest])

      true ->
        [range | consolidate_ranges([b | rest])]
    end
  end

  def consolidate_ranges([%Range{step: step} = r1, %Range{step: step} = r2 | rest]) do
    cond do
      # Overlapping
      r1.last >= r2.first && r1.last <= r2.last ->
        consolidate_ranges([%{r1 | last: r2.last} | rest])

      # Adjacent
      r1.last + 1 == r2.first ->
        consolidate_ranges([%{r1 | last: r2.last} | rest])

      # Enclosing
      r1.last >= r2.last ->
        [r1 | consolidate_ranges(rest)]

      true ->
        [r1 | consolidate_ranges([r2 | rest])]
    end
  end

  def consolidate_ranges([struct | rest]) when is_struct(struct) do
    [struct | consolidate_ranges(rest)]
  end

  # Ranges must have the same keys. Assumption
  # is that ranges can be in either direction
  # (ie increasing or decreasing)

  defp validate_range(from, to) do
    if Keyword.keys(from) == Keyword.keys(to) do
      {:range, [from, to]}
    else
      raise Tempo.ParseError,
            "Time ranges must have the same time units on both sides. Found #{inspect(from)}..#{inspect(to)}"
    end
  end

  # If the duration direction is negative, negate all the units —
  # shape-aware, since a fractional second reduces to a
  # `{:signed_fraction, sign, second, fraction}` tuple and a lifted
  # microsecond is a `{value, precision}` pair.

  def adjust_for_direction([{:direction, :negative} | rest]) do
    Enum.map(rest, &negate_duration_component/1)
  end

  def adjust_for_direction(other) do
    other
  end

  defp negate_duration_component({:second, {:signed_fraction, sign, second, fraction}}),
    do: {:second, {:signed_fraction, -sign, second, fraction}}

  defp negate_duration_component({:microsecond, {value, precision}}),
    do: {:microsecond, {-value, precision}}

  defp negate_duration_component({unit, value}) when is_number(value), do: {unit, -value}

  defp put_calendar(%Tempo{} = tempo, calendar) do
    %{tempo | calendar: calendar}
  end

  defp put_calendar(
         %Tempo.Interval{from: from, to: to, repeat_rule: repeat_rule} = interval,
         calendar
       ) do
    # A recurrence's selection lives in `repeat_rule` (a `%Tempo{}`), not in
    # `from`/`to`, so the effective calendar — an IXDTF `[u-ca=…]` suffix on the
    # whole expression — must reach it there for the selection to resolve in
    # that calendar. `nil`/`:undefined` endpoints fall through unchanged.
    %{
      interval
      | from: put_calendar(from, calendar),
        to: put_calendar(to, calendar),
        repeat_rule: put_calendar(repeat_rule, calendar)
    }
  end

  defp put_calendar(other, _calendar) do
    other
  end

  def wrap(term, atom) do
    {atom, term}
  end
end
