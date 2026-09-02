defmodule Tempo.Enumeration do
  @moduledoc false
  alias Tempo.Iso8601.Unit
  alias Tempo.Mask
  alias Tempo.Validation

  defguard is_continuation(unit, fun) when is_atom(unit) and is_function(fun)
  defguard is_unit(unit, value) when (is_atom(unit) and is_list(value)) or is_number(value)

  @doc """
  Get the next "odomoter reading" list of integers and ranges
  or a list of time units

  """
  def next(%Tempo{time: units, calendar: calendar} = tempo) do
    case next(units, calendar) do
      nil -> nil
      other -> %{tempo | time: other}
    end
  end

  def next(list, calendar) when is_list(list) do
    case do_next(list, calendar, []) do
      {:rollover, _list} -> nil
      list -> list
    end
  end

  # A selection `{:selection, [unit: value, …]}` is a constraint
  # on the enclosing enumeration ("the Nth month", "the last
  # Friday"), not a sequence to iterate over. This clause must
  # come before the `is_unit` clause below, otherwise that clause
  # would match (the selection's inner keyword list is a list)
  # and the selection would be destructively iterated.
  #
  # Full selection resolution — actually filtering enumerated
  # values by the selection pattern — is future work.

  def do_next([{:selection, _} = sel | t], calendar, previous) do
    case do_next(t, calendar, [sel | previous]) do
      {:rollover, tail} -> {:rollover, [sel | tail]}
      tail -> [sel | tail]
    end
  end

  def do_next([{unit, value} | t], calendar, previous) when is_unit(unit, value) do
    cycle =
      case cycle(value, unit, calendar, previous) do
        {{:rollover, value}, continuation} when is_number(value) -> {value, continuation}
        other -> other
      end

    [{unit, cycle} | List.wrap(do_next(t, calendar, [{unit, value} | previous]))]
  end

  # When its a mask, fill in the unspecified digits with
  # acceptable candidate values.

  def do_next([{unit, {:mask, mask}} | t], calendar, previous) do
    value = Mask.fill_unspecified(unit, mask, calendar, previous)
    do_next([{unit, value} | t], calendar, previous)
  end

  def do_next([{unit, :any = mask} | t], calendar, previous) do
    value = Mask.fill_unspecified(unit, mask, calendar, previous)
    do_next([{unit, value} | t], calendar, previous)
  end

  # A group token `{:group, range}` (produced by expanded
  # `nGspanUNITU` constructs) wraps a range of candidate values.
  # Treat it as a single-element list holding the range so the
  # `is_unit` path picks it up via the existing cycle machinery.

  def do_next([{unit, {:group, %Range{} = range}} | t], calendar, previous) do
    do_next([{unit, [range]} | t], calendar, previous)
  end

  # ISO 8601-2 significant-digits annotation. A year value tagged
  # `{int, [significant_digits: n]}` (e.g. `1950S2` → first 2
  # digits are significant) enumerates over the block of values
  # sharing those leading digits: `1950S2` → `1900..1999`,
  # `Y3388E2S3` → `338800..338899`.
  #
  # The candidate-count guard refuses to enumerate blocks larger
  # than `@significant_digits_limit`. The user can still hold the
  # value as a parsed AST; they just can't iterate through it.

  @significant_digits_limit 10_000

  def do_next([{unit, {value, [significant_digits: n]}} | t], calendar, previous)
      when is_integer(value) and is_integer(n) and n > 0 do
    range = significant_digits_range(value, n)

    case Range.size(range) do
      size when size > @significant_digits_limit ->
        raise ArgumentError,
              "Cannot enumerate a significant-digits block of #{size} candidates " <>
                "(limit: #{@significant_digits_limit}). Source: #{inspect(value)}S#{n}"

      _ ->
        do_next([{unit, [range]} | t], calendar, previous)
    end
  end

  # We hit a continuation at the end of a list
  def do_next([{unit, {_current, fun}}], calendar, previous) when is_continuation(unit, fun) do
    case fun.(calendar, previous) do
      {{:rollover, acc}, fun} ->
        {:rollover, [{unit, {acc, fun}}]}

      {acc, fun} ->
        [{unit, {acc, fun}}]
    end
  end

  def do_next([], _calendar, _previous) do
    []
  end

  def do_next([{unit, {current, fun}} | t], calendar, previous) when is_continuation(unit, fun) do
    case do_next(t, calendar, [{unit, {current, fun}} | previous]) do
      {:rollover, list} ->
        case fun.(calendar, previous) do
          {{:rollover, current}, fun} ->
            {:rollover, [{unit, {current, fun}} | list]}

          {current, fun} ->
            [{unit, {current, fun}} | list]
        end

      tail ->
        [{unit, {current, fun}} | tail]
    end
  end

  @doc """
  Returns a function that when called will return
  the next cycle value in a sequence.

  When the sequence cycles back to the start
  it returns `{:rollover, value}` to signal
  the rollover.

  """
  def cycle(source, unit, calendar, previous) when is_number(source) do
    cycle([source], [], unit, calendar, previous)
  end

  def cycle(source, unit, calendar, previous) do
    cycle(List.wrap(source), List.wrap(source), unit, calendar, previous)
  end

  def cycle(source, [], unit, calendar, previous) do
    rollover(source, unit, calendar, previous)
  end

  def cycle(source, [%Range{first: first, last: last} = range | rest], unit, calendar, previous)
      when first > 0 and last < 0 do
    reset(source, range, unit, calendar, previous, rest)
  end

  def cycle(
        source,
        [%Range{first: first, last: last, step: step} = range | rest],
        unit,
        _calendar,
        _previous
      )
      when (first <= last and step > 0) or (first >= last and step < 0) do
    increment(source, range, unit, rest)
  end

  def cycle(source, [%Range{}], unit, calendar, previous) do
    rollover(source, unit, calendar, previous)
  end

  def cycle(source, [%Range{}, %Range{} = range | rest], unit, calendar, previous) do
    cycle(source, [range | rest], unit, calendar, previous)
  end

  def cycle(source, [%Range{}, next | rest], unit, _calendar, _previous) do
    {next, continuation(source, rest, unit)}
  end

  def cycle(source, [next | rest], unit, _calendar, _previous) do
    {next, continuation(source, rest, unit)}
  end

  def cycle(_source, value, _unit, _calendar, _previous) do
    value
  end

  defp increment(source, %Range{first: first, last: last, step: step}, unit, rest) do
    {first, continuation(source, [(first + step)..last//step | rest], unit)}
  end

  def continuation(source, rest, unit) do
    fn calendar, previous -> cycle(source, rest, unit, calendar, previous) end
  end

  def reset(source, range, unit, calendar, previous, rest) do
    range = adjusted_range(range, unit, calendar, backtrack(previous, calendar))
    increment(List.wrap(source), range, unit, rest)
  end

  defp rollover([h | t] = source, unit, calendar, previous) do
    case h do
      %Range{first: first, last: last} = range when first >= 0 and last < 0 ->
        {first, continuation} = reset(h, range, unit, calendar, previous, t)
        {{:rollover, first}, continuation}

      %Range{} = range ->
        %Range{first: first, last: last, step: step} =
          adjusted_range(range, unit, calendar, previous)

        {{:rollover, first}, continuation(source, [(first + step)..last//step | t], unit)}

      first ->
        {{:rollover, first}, continuation(source, t, unit)}
    end
  end

  def backtrack(previous, calendar) do
    previous
    |> reverse()
    |> do_next(calendar, previous)
    |> reverse()
  end

  defp reverse({:rollover, list}), do: Enum.reverse(list)
  defp reverse(list), do: Enum.reverse(list)

  @doc false
  def adjusted_range(%Range{first: first, last: last, step: step}, _unit, _calendar, _previous)
      when first >= 0 and last >= first and step > 0 do
    %Range{first: first, last: last, step: step}
  end

  def adjusted_range(range, unit, calendar, previous) do
    units = [{unit, range} | current_units(previous)] |> Enum.reverse()

    {_unit, range} =
      units
      |> Validation.resolve(calendar)
      |> Enum.reverse()
      |> hd

    range
  end

  def current_units(units) do
    Enum.map(units, fn
      {unit, list} when is_list(list) -> {unit, extract_first(list)}
      {unit, {current, _fun}} -> {unit, current}
      {unit, value} -> {unit, value}
    end)
  end

  def extract_first([%Range{first: first} | _rest]), do: first
  def extract_first([first | _rest]), do: first

  # Returns the range of integers sharing `value`'s first `n`
  # digits. Honours sign: for `value < 0` the range runs from
  # most-negative to least-negative so iteration surfaces
  # "larger magnitude first" (matches the parser's intuition
  # that `-1950S2` covers `-1999..-1900`).
  defp significant_digits_range(value, n) when is_integer(value) and is_integer(n) and n > 0 do
    digit_count = digit_count(value)

    cond do
      n >= digit_count ->
        value..value

      value >= 0 ->
        scale = integer_pow10(digit_count - n)
        prefix = div(value, scale) * scale
        prefix..(prefix + scale - 1)

      true ->
        scale = integer_pow10(digit_count - n)
        prefix = div(-value, scale) * scale
        -(prefix + scale - 1)..-prefix
    end
  end

  defp digit_count(0), do: 1
  defp digit_count(n) when n < 0, do: digit_count(-n)
  defp digit_count(n), do: length(Integer.digits(n))

  defp integer_pow10(0), do: 1
  defp integer_pow10(n) when n > 0, do: 10 * integer_pow10(n - 1)

  @doc """
  Strips the functions from return tuples to produce
  a clean structure to pass to functions

  """
  def collect(%Tempo{time: units} = tempo) do
    case collect(units) do
      nil -> nil
      other -> %{tempo | time: other}
    end
  end

  def collect([]) do
    []
  end

  def collect([{:no_cycles, list}]) do
    list
  end

  def collect([{value, fun} | t]) when is_function(fun) do
    [value | collect(t)]
  end

  def collect([{unit, {acc, fun}} | t]) when is_function(fun) do
    [{unit, acc} | collect(t)]
  end

  def collect([h | t]) do
    [h | collect(t)]
  end

  @doc false
  # Cartesian expansion of a value whose components are concrete
  # integers, ranges, or lists of either — `{2000..2010}Y{1..-1}M{1..-1}D`
  # and any other combination of ranges in any position or positions.
  #
  # The odometer in `next/1` walks one component at a time and resolves
  # an open range (`1..-1`) by backtracking into the previous reading;
  # with several such ranges nested that backtrack does not converge.
  # This expander sidesteps the question: it walks the components
  # coarse-to-fine, and because every coarser component is already
  # concrete at each step, each range or negative resolves against a
  # *known* context through `Validation.validate/2` — the same
  # calendar-aware resolver a scalar literal uses. So `1..-1` months is
  # 12 in a Gregorian year and 13 in a Hebrew leap year, `1..-1` days is
  # 28, 29, 30 or 31 according to the month it lands in, and no unit's
  # length is ever assumed.
  #
  # Returns `{:ok, members}` with one concrete `%Tempo{}` per
  # combination in time order, or `:not_expandable` for values the
  # odometer must still handle (masks, groups, `:any`, continuations,
  # selections).
  def expand(%Tempo{time: time, calendar: calendar} = tempo) do
    if expandable?(time) do
      {:ok, expand_components(time, [], tempo, calendar)}
    else
      :not_expandable
    end
  end

  # Expandable when every component is a plain integer, an annotated
  # integer (`{value, options}` — a margin of error), a range, or a
  # list of those, and at least one component is set-valued. A single
  # concrete value has nothing to expand and keeps the implicit
  # enumeration path.
  defp expandable?(time) do
    Enum.all?(time, &finite_component?/1) and Enum.any?(time, &set_valued?/1)
  end

  defp finite_component?({_unit, value}), do: finite_value?(value)

  defp finite_value?(value) when is_integer(value), do: true
  defp finite_value?(%Range{}), do: true
  defp finite_value?({value, options}) when is_integer(value) and is_list(options), do: true
  defp finite_value?(value) when is_list(value), do: Enum.all?(value, &finite_value?/1)
  defp finite_value?(_other), do: false

  defp set_valued?({_unit, %Range{}}), do: true
  defp set_valued?({_unit, value}) when is_list(value), do: true
  defp set_valued?(_component), do: false

  defp expand_components([], acc, tempo, _calendar) do
    [%{tempo | time: Enum.reverse(acc)}]
  end

  defp expand_components([{unit, value} | rest], acc, tempo, calendar) do
    ancestors = Enum.reverse(acc)

    value
    |> raw_candidates()
    |> Enum.flat_map(&resolve_candidate(unit, &1, ancestors, calendar))
    |> Enum.flat_map(&expand_components(rest, [{unit, &1} | acc], tempo, calendar))
  end

  defp raw_candidates(value) when is_list(value), do: Enum.flat_map(value, &raw_candidates/1)
  defp raw_candidates(value), do: [value]

  # Resolve one candidate against its concrete ancestors. A range or a
  # negative resolves to this context's real values; a value the
  # context cannot hold is not an occurrence and drops out — the set
  # semantics ISO 8601-2 and RFC 5545 share ("invalid dates are
  # ignored"), so `{28..31}D` over January and February is 31 days
  # then 1, not four days then four invalid ones.
  defp resolve_candidate(unit, raw, ancestors, calendar) do
    partial = %Tempo{time: ancestors ++ [{unit, raw}], calendar: calendar}

    case Validation.validate(partial, calendar) do
      {:ok, %Tempo{time: validated}} ->
        validated |> Keyword.fetch!(unit) |> flatten_integers()

      # The validator names the range this unit can hold in this
      # context (12 months in a common Hebrew year, 28 days in a
      # non-leap February). Clip an overflowing range to it rather
      # than discarding the whole range.
      {:error, %Tempo.InvalidDateError{valid_range: %Range{} = valid}} when is_struct(raw, Range) ->
        clip_range(raw, valid)

      {:error, _reason} ->
        []
    end
  end

  # Clip to the range the unit can hold in this context, honouring the
  # range's own direction: a descending range (`{5..1}`) clips at the
  # opposite ends from an ascending one, and either may be emptied by
  # the clip.
  defp clip_range(%Range{first: first, last: last, step: step}, %Range{} = valid) do
    first = resolve_bound(first, valid)
    last = resolve_bound(last, valid)

    if step > 0 do
      max(first, valid.first)..min(last, valid.last)//step
    else
      min(first, valid.last)..max(last, valid.first)//step
    end
    |> flatten_integers()
  end

  defp resolve_bound(bound, %Range{last: valid_last}) when bound < 0, do: valid_last + 1 + bound
  defp resolve_bound(bound, _valid), do: bound

  # A count-from-the-end bound must already have been resolved — by
  # the calendar for date units, by the unit's fixed extent for clock
  # units, both in `Tempo.Validation`. One surviving here would
  # enumerate to nothing, turning a wrong answer into an empty one
  # silently, so fail loudly instead.
  defp flatten_integers(%Range{first: first, last: last} = range)
       when first < 0 or last < 0 do
    raise ArgumentError,
          "Unresolved count-from-the-end bound #{inspect(range)} reached expansion. " <>
            "This is a bug in Tempo's resolution of set-valued values; please report it."
  end

  # `Enum.to_list/1` respects the range's step, so a descending range
  # enumerates descending and a range whose step cannot reach its end
  # is empty.
  defp flatten_integers(%Range{} = range), do: Enum.to_list(range)
  defp flatten_integers(value) when is_list(value), do: Enum.flat_map(value, &flatten_integers/1)
  defp flatten_integers(value), do: [value]

  def explicitly_enumerable?(%Tempo{time: time}) do
    Enum.any?(time, fn
      # A selection is a constraint, not a sequence — it doesn't
      # make the value enumerable on its own. Without this guard
      # the `is_list(value)` rule below would match a selection's
      # inner keyword list and skip implicit enumeration.
      {:selection, _} -> false
      {_unit, value} when is_list(value) -> true
      {_unit, :any} -> true
      {_unit, {:mask, _}} -> true
      {_unit, {:group, _}} -> true
      {_unit, {_value, continuation}} when is_function(continuation) -> true
      {_unit, continuation} when is_function(continuation) -> false
      _other -> false
    end)
  end

  def add_implicit_enumeration(%Tempo{time: time, calendar: calendar} = tempo) do
    {unit, _span} = Tempo.resolution(tempo)

    cond do
      # Sub-second value: subdivide its microsecond ulp into ten
      # sub-points at +1 precision. `~o"...45.5"` (precision 1) →
      # `[.50, .51, …, .59]` at precision 2. At microsecond precision
      # 6 there is no finer ulp, so we raise.
      unit == :microsecond ->
        {parent_value, parent_precision} = Keyword.fetch!(time, :microsecond)
        subdivide_microsecond(tempo, parent_value, parent_precision)

      # Second resolution now has a finer unit (microsecond at
      # precision 1 — decisecond). `~o"...10:00:00"` → ten sub-points
      # at decisecond resolution `[.0, .1, …, .9]`.
      unit == :second ->
        enum_values = sub_second_enumeration(0, 1)
        %{tempo | time: time ++ [{:microsecond, enum_values}]}

      true ->
        case Unit.implicit_enumerator(unit, calendar) do
          nil ->
            raise ArgumentError,
                  "Cannot enumerate a Tempo at #{inspect(unit)} resolution " <>
                    "— no finer unit is defined. Got: #{inspect(tempo)}"

          {enum_unit, range} ->
            %{tempo | time: time ++ [{enum_unit, [range]}]}
        end
    end
  end

  defp subdivide_microsecond(%Tempo{} = tempo, _parent_value, parent_precision)
       when parent_precision >= 6 do
    raise ArgumentError,
          "Cannot enumerate a Tempo at microsecond precision 6 " <>
            "— that is the finest representable ulp. Got: #{inspect(tempo)}"
  end

  defp subdivide_microsecond(%Tempo{time: time} = tempo, parent_value, parent_precision) do
    enum_values = sub_second_enumeration(parent_value, parent_precision + 1)
    %{tempo | time: Keyword.replace(time, :microsecond, enum_values)}
  end

  # Ten `{value, precision}` sub-points starting at `parent_value`,
  # stepping by `10^(6 - precision)` microseconds.
  defp sub_second_enumeration(parent_value, precision) do
    step = Integer.pow(10, 6 - precision)
    Enum.map(0..9, fn i -> {parent_value + i * step, precision} end)
  end

  def maybe_add_implicit_enumeration(%Tempo{} = tempo) do
    if explicitly_enumerable?(tempo) do
      tempo
    else
      add_implicit_enumeration(tempo)
    end
  end

  def merge(base, from) do
    Enum.reduce(from, base, fn {unit, value}, acc ->
      Keyword.update(acc, unit, value, fn _existing -> value end)
    end)
    |> Unit.sort(:desc)
  end
end
