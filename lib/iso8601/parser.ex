defmodule Tempo.Iso8601.Parser do
  @moduledoc false

  alias Tempo.Duration
  alias Tempo.Iso8601.AST
  alias Tempo.Iso8601.Unit
  alias Tempo.ParseError
  alias Tempo.Qualification

  def parse(tokens, calendar) do
    case refused(tokens) do
      nil -> parse_tokens(tokens, calendar)
      reason -> {:error, ParseError.exception(reason: reason)}
    end
  end

  # What the tokens say that is no value, wherever it is written: the reason
  # it is refused, or `nil`.
  defp refused(tokens) do
    case backwards_range(tokens) do
      nil -> short_window(tokens)
      range -> backwards_reason(range)
    end
  end

  # A range runs from its first value up to its last, as an interval does.
  # One written backwards (`{20..15}D`, `{2026-06-20..2026-06-15}`) is
  # refused here, wherever it is written: in a value, a set, a group, a
  # selection or a rule. The tokenizer gives a range whose first is after
  # its last a step of -1, and a range that counts from the start to the end
  # (`{1..-1}D`) is not backwards: its ends are counted from different ends,
  # and are compared once they are counted (`Tempo.UnitValues.resolve/2`).
  defp backwards_range(%Range{} = range), do: if(backwards?(range), do: range)

  defp backwards_range({:range, [{_from_tag, from}, {_to_tag, to}]} = range)
       when is_list(from) and is_list(to) do
    if backwards_values?(from, to), do: range, else: backwards_range([from, to])
  end

  defp backwards_range(tokens) when is_list(tokens),
    do: Enum.find_value(tokens, &backwards_range/1)

  defp backwards_range(token) when is_tuple(token),
    do: token |> Tuple.to_list() |> backwards_range()

  defp backwards_range(_token), do: nil

  defp backwards?(%Range{step: step}) when step < 0, do: true
  defp backwards?(%Range{first: first, last: last}), do: first > last and first < 0 == last < 0

  # Two values of the same units, each one whole number, are compared unit
  # by unit from the coarsest.
  defp backwards_values?(from, to) do
    Keyword.keyword?(from) and Keyword.keyword?(to) and Keyword.keys(from) == Keyword.keys(to) and
      Enum.all?(Keyword.values(from) ++ Keyword.values(to), &is_integer/1) and
      Keyword.values(from) > Keyword.values(to)
  end

  defp backwards_reason(%Range{first: first, last: last}) when first > last do
    "The range #{first}..#{last} is written backwards: a range runs from its first value " <>
      "up to its last"
  end

  defp backwards_reason(%Range{first: first, last: last, step: step}) do
    "The range #{first}..#{last}//#{step} counts down: a range runs from its first value " <>
      "up to its last"
  end

  defp backwards_reason({:range, [{_from_tag, from}, {_to_tag, to}]}) do
    "The range #{inspect(from)}..#{inspect(to)} is written backwards: a range runs from " <>
      "its first value up to its last"
  end

  # A selection with a time interval (ISO 8601-2 §12.10) makes each date it
  # selects the start of an interval of the window's duration, and selectors
  # written after the window pick within it. A window of no length is no
  # interval, and one shorter than a unit selected within it holds none of
  # them whole: twelve hours hold no day, so `LLL1K1IN/PT12HN1K1IN` selects a
  # Monday in a window that has none. Both are refused here, where the value
  # is read, in a value and in a rule. A window of twelve hours that selects
  # hours is read.
  #
  # A window is held to the units a duration measures exactly: a week is
  # seven days, a day twenty-four hours. One written in months or years is as
  # long as the calendar makes it where it starts, and is not judged here.
  defp short_window({:selection, parts}) when is_list(parts),
    do: window_reason(parts) || short_window(parts)

  defp short_window(tokens) when is_list(tokens), do: Enum.find_value(tokens, &short_window/1)

  defp short_window(token) when is_tuple(token),
    do: token |> Tuple.to_list() |> short_window()

  defp short_window(_token), do: nil

  defp window_reason(parts) do
    case Enum.split_while(parts, &(not match?({:interval, _window}, &1))) do
      {_before, [{:interval, window} | within]} when is_list(window) ->
        window |> List.keyfind(:duration, 0) |> window_shortfall(within)

      _no_window ->
        nil
    end
  end

  defp window_shortfall({:duration, time}, within) when is_list(time) do
    amounts = for {unit, amount} <- time, unit != :direction, do: {unit, amount}

    if Enum.all?(amounts, fn {_unit, amount} -> amount == 0 end),
      do: no_length_reason(amounts),
      else: shorter_reason(amounts, measured_seconds(amounts), within)
  end

  defp window_shortfall(_no_duration, _within), do: nil

  @measured_seconds %{week: 604_800, day: 86_400, hour: 3_600, minute: 60, second: 1}

  # The units a selector within a window picks by, as the unit one of them
  # is as long as.
  @selected_by %{
    week: :week,
    calendar_week: :week,
    day: :day,
    day_of_week: :day,
    day_of_year: :day,
    hour: :hour,
    minute: :minute,
    second: :second
  }

  # A duration's length in seconds where every unit it is written in is
  # measured exactly, and `nil` where one is not.
  defp measured_seconds(amounts) do
    Enum.reduce_while(amounts, 0, fn {unit, amount}, seconds ->
      case Map.fetch(@measured_seconds, unit) do
        {:ok, each} when is_number(amount) -> {:cont, seconds + amount * each}
        _not_measured -> {:halt, nil}
      end
    end)
  end

  defp shorter_reason(_amounts, nil, _within), do: nil

  defp shorter_reason(amounts, seconds, within) do
    Enum.find_value(within, fn
      {unit, _value} -> shorter_than(amounts, seconds, Map.get(@selected_by, unit))
      _no_unit -> nil
    end)
  end

  defp shorter_than(_amounts, _seconds, nil), do: nil

  # A window that runs backward is as long as one that runs forward, however
  # its direction is written (`-P7D`, `P-7D`).
  defp shorter_than(amounts, seconds, unit) do
    if abs(seconds) < Map.fetch!(@measured_seconds, unit) do
      "A selection's window of #{duration_words(amounts)} is shorter than #{one(unit)}, and " <>
        "#{one(unit)} is selected within it: a window holds what is selected in it whole " <>
        "(ISO 8601-2 §12.10)"
    end
  end

  defp one(:hour), do: "an hour"
  defp one(unit), do: "a #{unit}"

  defp no_length_reason(amounts) do
    "A selection's window of #{duration_words(amounts)} has no length: each date selected " <>
      "starts an interval of the window's duration (ISO 8601-2 §12.10), and an interval of " <>
      "no length is none"
  end

  defp duration_words(amounts) do
    Enum.map_join(amounts, " ", fn
      {unit, 1} -> "1 #{unit}"
      {unit, amount} -> "#{amount} #{unit}s"
    end)
  end

  defp parse_tokens(tokens, calendar) do
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
    e in ParseError ->
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

  # Complete qualification (§8.2.1) — the whole expression, which is each
  # of its components. For an interval it attaches to both endpoints so
  # every sub-value carries it.
  defp apply_complete_qualification(result, nil), do: result

  defp apply_complete_qualification(%Tempo{} = tempo, qualification),
    do: Qualification.with_complete(tempo, qualification)

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

  # A range member of a set is qualified at both ends, as an interval is.
  defp apply_complete_qualification(%Tempo.Range{first: first, last: last} = range, qualification) do
    %{
      range
      | first: apply_complete_qualification(first, qualification),
        last: apply_complete_qualification(last, qualification)
    }
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
            &Qualification.combine(&1, qualification)
          )

        %{tempo | qualifications: qualifications}
    end
  end

  defp apply_leading_qualification(other, qualification) do
    apply_complete_qualification(other, qualification)
  end

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
    |> alternative_format_components()
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

  # Split a `{:filter, …}` year-filter token (from `{…}e`/`o`/`l`/`c`) off the
  # domain's members, returning `{filter, plain_members}`.
  defp extract_domain_filter(members) do
    case Enum.split_with(members, &match?({:filter, _}, &1)) do
      {[{:filter, filter}], plain} -> {filter, plain}
      {[], plain} -> {nil, plain}
    end
  end

  # Date and time parsing

  # An end of an interval, as the form the tokenizer gave it: a date, a date
  # with a time of day, or a time of day. Each is read as a value written
  # alone is, so a set, an unspecified unit or a mask in it is the same
  # under a time of day as without one. An end with a time of day was passed
  # by, and kept the tokenizer's `{:all_of, …}` and `{:mask, :"X*"}`, which
  # nothing reads.
  def parse_date([{form, tokens} | rest])
      when form in [:date, :datetime, :time_of_day] and is_list(tokens) do
    [{form, parse_date(tokens)} | parse_date(rest)]
  end

  def parse_date([{:repeat_rule, date} | rest]) do
    [{:repeat_rule, parse_date(date)} | parse_date(rest)]
  end

  def parse_date([{:century, century} | rest]) when is_integer(century) do
    parse_date([{:year, {:group, (century * 100)..((century + 1) * 100 - 1)}} | rest])
  end

  def parse_date([{:decade, decade} | rest]) when is_integer(decade) do
    parse_date([{:year, {:group, (decade * 10)..((decade + 1) * 10 - 1)}} | rest])
  end

  # A century or a decade is the hundred or the ten years its whole number
  # names. One written with a fraction (`20.5C`: ISO 8601 gives a decimal
  # fraction to an hour, a minute or a second alone), unspecified digits
  # (`1XC`, `X*J`), as a set or a range (`{19,20}C`) or with a margin of error
  # or significant digits (`20±1C`) names no one run of years, so it is not a
  # value.
  def parse_date([{unit, _not_one_number} | _rest]) when unit in [:century, :decade] do
    raise ParseError,
          "A #{unit} is written as one whole number (`20C`, `201J`), which names its years. " <>
            "One with a fraction, unspecified digits, a set, a range, a margin of error or " <>
            "significant digits names no one run of years; unspecified digits are written on " <>
            "the year (`19XX`)."
  end

  def parse_date([{:group, group_1}, {:group, group_2} | rest]) do
    {_min_1, max_1} = group_min_max(group_1)
    {min_2, _max} = group_min_max(group_2)

    if Unit.compare(max_1, min_2) == :lt do
      raise ParseError,
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
      raise ParseError,
            "Selection time units must be in decreasing time scale order. Found #{inspect(selection)}."
    end

    {_min_1, max_1} = selection_min_max(selection)
    {min_2, _max} = group_min_max(group)

    if Unit.compare(max_1, min_2) == :lt do
      raise ParseError,
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
      raise ParseError,
            "group #{inspect(group)} is finer than the following selection #{inspect(selection)}"
    else
      [{:group, parse_date(group)} | parse_date([{:selection, selection} | rest])]
    end
  end

  # What precedes a group may be no unit at all (the qualification of
  # `6~M2G10DU` is an entry of its own), and is then not held to the group's
  # order.
  def parse_date([{unit_1, value_1}, {:group, group} | rest]) do
    {min, _max} = group_min_max(group)

    if Unit.fetch_sort_key(unit_1) != :error and Unit.compare(unit_1, min) == :lt do
      raise ParseError, "#{inspect(unit_1)} is less than the group min of #{inspect(min)}"
    else
      [parse_date({unit_1, value_1}) | parse_date([{:group, group} | rest])]
    end
  end

  # A group followed by a selection or another group is handled by
  # the dedicated clauses above; this clause covers a plain unit. What
  # follows a group may be no unit at all (the `Z` of `2GT6HUZ` is a time
  # shift), and is then not held to the group's order.
  def parse_date([{:group, group}, {unit_2, value_2} | rest]) do
    {_min, max} = group_min_max(group)

    if Unit.fetch_sort_key(unit_2) != :error and Unit.compare(max, unit_2) == :lt do
      raise ParseError,
            "#{inspect(unit_2)} is greater than the group max of #{inspect(max)}"
    else
      [{:group, parse_date(group)} | parse_date([{unit_2, value_2} | rest])]
    end
  end

  def parse_date([{unit_1, value_1}, {:selection, selection} | rest]) do
    {min, _max} = selection_min_max(selection)

    if Unit.compare(unit_1, min) == :lt do
      raise ParseError,
            "#{inspect(unit_1)} is less than the selection min of #{inspect(min)}"
    else
      [parse_date({unit_1, value_1}) | parse_date([{:selection, selection} | rest])]
    end
  end

  def parse_date([{:selection, selection}, {unit_2, value_2} | rest]) do
    {_min, max} = selection_min_max(selection)

    unless Unit.ordered?(selection) do
      raise ParseError,
            "Selection time units must be in decreasing time scale order. Found #{inspect(selection)}."
    end

    if Unit.compare(max, unit_2) == :lt do
      raise ParseError,
            "#{inspect(unit_2)} is greater than the selection max of #{inspect(max)}"
    else
      selection = parse_date(selection) |> reduce_list()
      [{:selection, selection} | parse_date([{unit_2, value_2} | rest])]
    end
  end

  def parse_date([{:selection, selection} | rest]) do
    unless Unit.ordered?(selection) do
      raise ParseError,
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

  # The fractions of a second written as a set (`45.{0..9}S`) are digits
  # and how many were written, which the reading of the value turns into
  # microseconds: they are no set of numbers to put in order here.
  def parse_date([{:fractions, fractions} | rest]) when is_list(fractions) do
    [{:fractions, fractions} | parse_date(rest)]
  end

  def parse_date([{component, {:all_of, list}} | rest]) do
    [{component, reduce_members(component, list)} | parse_date(rest)]
  end

  def parse_date([{component, list} | rest]) when is_list(list) do
    [{component, reduce_members(component, list)} | parse_date(rest)]
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

  # ISO 8601-1 §5.5.2.4 lets a duration be written in the alternative
  # format, as a calendar or ordinal date and a time of day
  # (`P0002-01-10T22:33:55` is `P2Y1M10DT22H33M55S`); its components are
  # the duration's. A week date, a day of the week or an unspecified digit
  # is no duration.
  defp alternative_format_components(tokens) do
    Enum.flat_map(tokens, fn
      {form, components} when form in [:datetime, :date, :time_of_day] ->
        alternative_format_duration(components)

      token ->
        [token]
    end)
  end

  defp alternative_format_duration(components) do
    components = Enum.map(components, &duration_days/1)

    if Enum.all?(components, &alternative_format_component?/1) do
      second_with_fraction(components)
    else
      raise ParseError,
            "#{inspect(components)} is not a duration in the alternative format, " <>
              "which is a calendar or ordinal date and a time of day"
    end
  end

  defp alternative_format_component?({unit, value})
       when unit in [:year, :month, :day, :hour, :minute, :second] and is_integer(value),
       do: true

  defp alternative_format_component?({:fraction, {digits, precision}})
       when is_integer(digits) and is_integer(precision),
       do: true

  defp alternative_format_component?(_component), do: false

  # An ordinal date's day of the year is a number of days in a duration
  # (`P0002-178T22:33:55` is `P2Y178DT22H33M55S`).
  defp duration_days({:day_of_year, days}), do: {:day, days}
  defp duration_days(component), do: component

  # A fractional second is the second the designator form writes
  # (`PT55.5S`), so both forms build the same duration.
  defp second_with_fraction(components) do
    case Keyword.pop(components, :fraction) do
      {nil, components} ->
        components

      {fraction, components} ->
        second = Keyword.fetch!(components, :second)
        Keyword.replace!(components, :second, {:signed_fraction, 1, second, fraction})
    end
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
  # negative member counts from the end (`{1,-1}D`, the first and the *last*
  # day), and where it falls among the others is not known until it is
  # counted, so the list is left in the order it is written: the reading of
  # the value puts it in order once the count is taken
  # (`Tempo.Validation.conform/2`). A year below zero is a year and not a
  # count, so a set of years is put in order here (`reduce_members/2`).
  def reduce_list(list) when is_list(list) do
    list
    |> sort_unless_signed()
    |> consolidate_ranges()
  end

  def reduce_list(other) do
    other
  end

  # The members of a unit's set. A set of years is in order whatever the
  # signs of its years; any other is `reduce_list/1`'s to order.
  defp reduce_members(:year, [first | _rest] = years)
       when is_integer(first) or is_struct(first, Range) do
    if Enum.all?(years, &number_or_range?/1),
      do: years |> Enum.sort_by(&first_value/1) |> consolidate_ranges(),
      else: reduce_list(years)
  end

  defp reduce_members(_component, members), do: reduce_list(members)

  defp number_or_range?(member), do: is_integer(member) or is_struct(member, Range)

  defp first_value(%Range{first: first}), do: first
  defp first_value(number), do: number

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

  # Consolidate a list of whole numbers and ranges: a member another holds
  # is dropped, and neighbours that run on from one another become one range.
  #
  # Two members are joined only when both count from the start or both from
  # the end, and both count up by one. A negative member counts from the end
  # (`-1`, the last), so `-1` and `0` are the last and the first and not
  # neighbours, where `-2` and `-1` are the last two; and `{1..9//2}` does not
  # run on into 10. A list with a negative member is left in the order it is
  # written (`sort_unless_signed/1`), so nothing here takes its members to be
  # in ascending order: one is held by another only when both its ends are.
  #
  # One pass joins each member with the one after it, so a member written
  # out of order may leave two that run on from one another side by side
  # (`{0,2,1..7,-1}` is `0` and `1..7` after one pass): the passes are
  # repeated until one joins nothing.
  def consolidate_ranges(members) do
    case join_neighbours(members) do
      ^members -> members
      joined -> consolidate_ranges(joined)
    end
  end

  defp join_neighbours([]), do: []
  defp join_neighbours([member]), do: [member]

  defp join_neighbours([first, second | rest]) do
    case joined(first, second) do
      {:ok, one} -> join_neighbours([one | rest])
      :apart -> [first | join_neighbours([second | rest])]
    end
  end

  defp joined(member, member), do: {:ok, member}

  defp joined(first, second) when is_integer(first) and is_integer(second) do
    if first + 1 == second and same_end?(first, second),
      do: {:ok, first..second},
      else: :apart
  end

  defp joined(number, %Range{first: first} = range) when is_integer(number) do
    cond do
      held?(number, range) -> {:ok, range}
      runs_on?(number, first) and by_ones?(range) -> {:ok, %{range | first: number}}
      true -> :apart
    end
  end

  defp joined(%Range{last: last} = range, number) when is_integer(number) do
    cond do
      held?(number, range) -> {:ok, range}
      runs_on?(last, number) and by_ones?(range) -> {:ok, %{range | last: number}}
      true -> :apart
    end
  end

  defp joined(%Range{} = first, %Range{} = second) do
    if by_ones?(first) and by_ones?(second) and same_end?(first.first, second.first),
      do: joined_ranges(first, second),
      else: :apart
  end

  defp joined(_first, _second), do: :apart

  # Two ranges that count up by one from the same end: one that holds the
  # other, or the second beginning within the first or just after it.
  defp joined_ranges(first, second) do
    cond do
      second.first >= first.first and second.last <= first.last ->
        {:ok, first}

      first.first >= second.first and first.last <= second.last ->
        {:ok, second}

      second.first >= first.first and second.first <= first.last + 1 ->
        {:ok, %{first | last: second.last}}

      true ->
        :apart
    end
  end

  # A range holds a number when both its ends and the number count from one
  # end: a range from the start to the end (`{1..-1}`) holds values only
  # once it is counted. A range that counts down names nothing
  # (`Tempo.UnitValues.named/2`), and so holds nothing.
  defp held?(number, %Range{first: first, last: last, step: step} = range),
    do: step > 0 and same_end?(first, last) and same_end?(number, first) and number in range

  # The second is the value after the first, counted from the same end.
  defp runs_on?(first, second), do: first + 1 == second and same_end?(first, second)

  # Both count from the start, or both from the end.
  defp same_end?(first, second), do: first < 0 == second < 0

  # A range from one value up to another by ones, both counted from one end.
  defp by_ones?(%Range{first: first, last: last, step: step}),
    do: step == 1 and first <= last and same_end?(first, last)

  # Ranges must have the same units. One written backwards never reaches
  # here (`backwards_range/1`). A qualifier of an end is no unit of it:
  # `{2020Y?..2030Y}` runs from an uncertain 2020 to 2030.
  @qualifiers [:qualification, :individual_qualification, :group_qualification]

  defp validate_range(from, to) do
    if units_written(from) == units_written(to) do
      {:range, [from, to]}
    else
      raise ParseError,
            "Time ranges must have the same time units on both sides. Found #{inspect(from)}..#{inspect(to)}"
    end
  end

  defp units_written(tokens), do: Keyword.keys(tokens) -- @qualifiers

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

  # A recurrence's domain counts Gregorian years, as a holiday's year gates do,
  # whatever calendar its selection is in: the years gate the occurrences that
  # fall in them. The domain keeps its own calendar.
  defp put_calendar(
         %Tempo.Interval{from: %Tempo.Set{}, to: to, repeat_rule: repeat_rule} = interval,
         calendar
       ) do
    %{interval | to: put_calendar(to, calendar), repeat_rule: put_calendar(repeat_rule, calendar)}
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

  # A set has no calendar of its own: each member, each end of a range and
  # each excluded member is a value in the calendar the set is written for.
  defp put_calendar(%Tempo.Set{set: members, except: except} = set, calendar) do
    %{
      set
      | set: Enum.map(members, &put_calendar(&1, calendar)),
        except: Enum.map(except, &put_calendar(&1, calendar))
    }
  end

  defp put_calendar(%Tempo.Range{first: first, last: last} = range, calendar) do
    %{range | first: put_calendar(first, calendar), last: put_calendar(last, calendar)}
  end

  defp put_calendar(other, _calendar) do
    other
  end

  def wrap(term, atom) do
    {atom, term}
  end
end
