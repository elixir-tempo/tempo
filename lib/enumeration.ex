defmodule Tempo.Enumeration do
  @moduledoc false

  alias Tempo.Clock
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.InvalidDateError
  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Unit
  alias Tempo.Mask
  alias Tempo.UnanchoredError
  alias Tempo.Validation

  # The walk of a value.
  #
  # A value's components are read coarse to fine. Each names one value or
  # several (a set, a range, a mask, an unspecified unit, a group), and what
  # it names is worked out against the concrete values of the components
  # before it: by `Tempo.Validation`, the resolver a literal goes through, and
  # by `Tempo.Mask` for unspecified digits. So `1..-1` days is 28, 29, 30 or 31
  # according to the month it lands in, `1..-1` months is 13 in a Hebrew leap
  # year, `3X` days is the 30th alone in June and no day in February, and no
  # unit's length is ever assumed.
  #
  # The walk is a depth-first traversal held as a stack of frames, one for
  # each component being walked: the concrete components before it, the
  # values it has still to take, and the components after it. It is lazy, so
  # `Enum.take/2` of `XXXX-XX-XX` reads three values and stops. It returns an
  # error rather than raising one, so `Tempo.to_interval/2` lists a value's
  # members with it, and `Enumerable.reduce/3`, which has no error to return,
  # is the only place that raises.

  # A frame holds the concrete components before its own (finest first), its
  # unit, the values it has still to take, and the components after it.
  @typep frame ::
           {ancestors :: list(), unit :: atom(), values :: list(), rest :: list()}
           | {:start, list()}
           | {:error, Exception.t()}

  # `:status` is `:empty` until the walk yields a value, and holds the first
  # reason a component had no value until then.
  @type walk :: %{
          tempo: Tempo.t(),
          calendar: module(),
          stack: [frame()],
          status: :empty | :yielded | {:unmatched, term()}
        }

  # The most values a significant-digits block is walked through.
  @significant_digits_limit 10_000

  # The most values `next/1` reads at once, so a walk stays lazy over a
  # component with many (`XXXX`, nine thousand years) and a walk of a few
  # costs what a list of them does.
  @read_ahead 64

  # The units whose extent no date changes: those of a time of day, and the
  # day of the week (`Tempo.Iso8601.Unit.value_range/2`).
  @fixed_extent_units [:day_of_week, :hour, :minute, :second, :microsecond]

  @doc false
  # The walk of a value as it is written. A value with no set, range, mask or
  # group in it is walked as the one value it is.
  @spec walk(Tempo.t()) :: walk()
  def walk(%Tempo{calendar: calendar} = tempo) do
    calendar = Compare.effective_calendar(calendar)
    start(tempo, walked_as_written(tempo, calendar), calendar)
  end

  @doc false
  # The walk `Enum` takes: a value that names one span is walked by the unit
  # below its own, a year by its months and a day by its hours. Raises the
  # `ArgumentError` of `add_implicit_enumeration/1` for a value with no finer
  # unit to walk by.
  @spec implicit_walk(Tempo.t()) :: walk()
  def implicit_walk(%Tempo{calendar: calendar} = tempo) do
    calendar = Compare.effective_calendar(calendar)

    if explicitly_enumerable?(tempo),
      do: start(tempo, walked_as_written(tempo, calendar), calendar),
      else: start(tempo, walked_by_finer_unit(tempo, calendar), calendar)
  end

  # A value of whole numbers, sets and ranges alone is read as it stands:
  # each was resolved, or left for the walk, when the value was read. Any
  # other is validated whole first, in its own calendar, which finishes what
  # reading it can leave half done — `2026Y2G2MU2G5DUT10H`, an hour of a
  # group of days of a group of months, is read to its day, and here to its
  # month — and makes a value that is not one the walk's error.
  defp walked_as_written(%Tempo{time: time} = tempo, calendar) do
    if expandable?(time) do
      {:start, settled(time, true)}
    else
      case Validation.validate(tempo, calendar) do
        {:ok, %Tempo{time: validated}} -> {:start, settled(validated, true)}
        {:error, exception} -> {:error, exception}
      end
    end
  end

  # The value is validated whole with the unit it is walked by, in its own
  # calendar. That resolves the unit's values (the days of the month the
  # value names), so they are read as they stand, and a value that is not one
  # (a struct built with a thirteenth month) is the walk's error rather than
  # an empty walk.
  defp walked_by_finer_unit(tempo, calendar) do
    case tempo |> add_implicit_enumeration() |> Validation.validate(calendar) do
      {:ok, %Tempo{time: time}} ->
        [{finer, _settled?} | before] = time |> settled(true) |> Enum.reverse()
        {:start, Enum.reverse(before, [{finer, :resolved}])}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp start(tempo, first, calendar),
    do: %{tempo: tempo, calendar: calendar, stack: [first], status: :empty}

  # Pairs each component with whether every component before it names one
  # resolved value. A whole number after them was resolved when the value was
  # read, and is taken as it stands.
  defp settled([], _settled?), do: []

  defp settled([component | rest], settled?),
    do: [{component, settled?} | settled(rest, settled? and single?(component))]

  defp single?({:selection, _selection}), do: true

  defp single?({:microsecond, {value, precision}}),
    do: is_integer(value) and is_integer(precision)

  defp single?({_unit, value}) when is_integer(value), do: value >= 0

  defp single?({_unit, {value, [{key, _} | _]}}) when is_integer(value),
    do: value >= 0 and key != :significant_digits

  defp single?(_component), do: false

  @doc false
  # The next values of a walk, at least one, and the walk after them; `:done`
  # when it has no more; or the error that stops it. The values are those of
  # the walk's finest component, read no more than `@read_ahead` at a time.
  @spec next(walk()) :: {:ok, [Tempo.t(), ...], walk()} | :done | {:error, Exception.t()}
  def next(%{stack: [{:start, components}]} = walk),
    do: descend(%{walk | stack: []}, [], components)

  def next(%{stack: [{:error, exception}]}), do: {:error, exception}
  def next(%{stack: []} = walk), do: finished(walk)

  # Each value of the last component is a value of the walk.
  def next(%{stack: [{ancestors, unit, values, []} | stack]} = walk),
    do: read(walk, stack, ancestors, unit, values)

  # A component's last value leaves no frame behind it.
  def next(%{stack: [{ancestors, unit, [value], rest} | stack]} = walk),
    do: descend(%{walk | stack: stack}, [{unit, value} | ancestors], rest)

  def next(%{stack: [{ancestors, unit, [value | values], rest} | stack]} = walk) do
    walk = %{walk | stack: [{ancestors, unit, values, rest} | stack]}
    descend(walk, [{unit, value} | ancestors], rest)
  end

  # The walk's values for the first of a last component's values, at least
  # one, on the frames in `stack`. Those still to read are a frame.
  defp read(%{tempo: tempo} = walk, stack, ancestors, unit, values) do
    case read_ahead(values, @read_ahead, ancestors, unit, tempo, []) do
      {read, []} ->
        {:ok, read, %{walk | stack: stack, status: :yielded}}

      {read, left} ->
        {:ok, read, %{walk | stack: [{ancestors, unit, left, []} | stack], status: :yielded}}
    end
  end

  defp read_ahead([value | values], count, ancestors, unit, tempo, read) when count > 0 do
    value = %{tempo | time: :lists.reverse(ancestors, [{unit, value}])}
    read_ahead(values, count - 1, ancestors, unit, tempo, [value | read])
  end

  defp read_ahead(left, _count, _ancestors, _unit, _tempo, read),
    do: {:lists.reverse(read), left}

  # With no component left to read, the components read are a value of the
  # walk; a value with no components has no values.
  defp descend(walk, [], []), do: next(walk)

  defp descend(%{tempo: tempo} = walk, ancestors, []),
    do: {:ok, [%{tempo | time: :lists.reverse(ancestors)}], %{walk | status: :yielded}}

  # Whole numbers are read together. After components that each name one
  # resolved value they were resolved when the value was read, and stand as
  # they are. After a component with several values (the `6M15D` of
  # `XXXX-06-15`) they are read once for each value before them: they are a
  # date there or they are not.
  defp descend(walk, ancestors, [{{_unit, value}, settled?} | _] = components)
       when is_integer(value) and value >= 0 do
    {literals, rest} = whole_numbers(components, [])

    if settled? != false or valid_after?(literals, ancestors, walk.calendar),
      do: descend(walk, literals ++ ancestors, rest),
      else: next(walk)
  end

  # With a component of any other kind, its values are a new frame: read at
  # once when it is the last component, and passed over when it has none.
  defp descend(%{calendar: calendar, stack: stack} = walk, ancestors, [
         {component, settled?} | rest
       ]) do
    case candidates(component, ancestors, calendar, settled?) do
      {:ok, _unit, []} -> next(walk)
      {:ok, unit, values} when rest == [] -> read(walk, stack, ancestors, unit, values)
      {:ok, unit, values} -> next(%{walk | stack: [{ancestors, unit, values, rest} | stack]})
      {:unmatched, reason} -> next(unmatched(walk, reason))
      {:error, reason} -> {:error, exception(walk.tempo, reason)}
    end
  end

  # The run of whole numbers a list of components starts with, finest first,
  # and the components after it.
  defp whole_numbers([{{_unit, value} = literal, _settled?} | rest], literals)
       when is_integer(value) and value >= 0,
       do: whole_numbers(rest, [literal | literals])

  defp whole_numbers(rest, literals), do: {literals, rest}

  defp valid_after?(literals, ancestors, calendar) do
    written = :lists.reverse(ancestors, :lists.reverse(literals))

    match?(
      {:ok, _valid},
      Validation.validate(%Tempo{time: written, calendar: calendar}, calendar)
    )
  end

  defp unmatched(%{status: :empty} = walk, reason), do: %{walk | status: {:unmatched, reason}}
  defp unmatched(walk, _reason), do: walk

  # A mask that matches nothing in one context, or a group that starts beyond
  # it, is passed over, as a set drops the values its context cannot hold
  # (`1985-XX-3X` has no February). A walk that ends having matched nothing
  # anywhere names no date (`1985-02-3X`), and the first reason is its error.
  defp finished(%{status: {:unmatched, reason}, tempo: tempo}),
    do: {:error, exception(tempo, reason)}

  defp finished(_walk), do: :done

  @doc false
  # Every value a walk names, in the order it names them, or the error that
  # stops it.
  @spec members(Tempo.t()) :: {:ok, [Tempo.t()]} | {:error, Exception.t()}
  def members(%Tempo{} = tempo), do: tempo |> walk() |> gather([])

  defp gather(walk, gathered) do
    case next(walk) do
      {:ok, values, walk} -> gather(walk, [values | gathered])
      :done -> {:ok, gathered |> Enum.reverse() |> Enum.concat()}
      {:error, _exception} = error -> error
    end
  end

  @doc false
  # The members of a value whose components are concrete integers, ranges, or
  # lists of either (`{2000..2010}Y{1..-1}M{1..-1}D` and any other combination
  # of sets in any position), or `:not_expandable` for a value that holds
  # anything else or no set at all.
  @spec expand(Tempo.t()) :: {:ok, [Tempo.t()]} | {:error, Exception.t()} | :not_expandable
  def expand(%Tempo{time: time} = tempo) do
    if expandable?(time), do: members(tempo), else: :not_expandable
  end

  # Expandable when every component is a plain integer, an annotated integer
  # (`{value, options}`, a margin of error), a range, or a list of those, and
  # at least one component is set-valued.
  defp expandable?(time), do: expandable?(time, false)

  defp expandable?([], set_valued?), do: set_valued?

  defp expandable?([{_unit, value} | rest], set_valued?) when is_integer(value),
    do: expandable?(rest, set_valued?)

  defp expandable?([{_unit, %Range{}} | rest], _set_valued?), do: expandable?(rest, true)

  defp expandable?([{_unit, values} | rest], _set_valued?) when is_list(values),
    do: finite_values?(values) and expandable?(rest, true)

  defp expandable?([{_unit, {value, options}} | rest], set_valued?)
       when is_integer(value) and is_list(options),
       do: expandable?(rest, set_valued?)

  # Anything else (a mask, an unspecified unit, a group, a fraction of a
  # second, a selection) is not expanded.
  defp expandable?(_time, _set_valued?), do: false

  defp finite_values?([]), do: true
  defp finite_values?([value | rest]), do: finite_value?(value) and finite_values?(rest)

  defp finite_value?(value) when is_integer(value), do: true
  defp finite_value?(%Range{}), do: true
  defp finite_value?({value, options}) when is_integer(value) and is_list(options), do: true
  defp finite_value?(values) when is_list(values), do: finite_values?(values)
  defp finite_value?(_other), do: false

  ## The values a component names

  # Each clause gives `{:ok, unit, values}`, the values the component takes
  # after `ancestors` (the concrete components before it, finest first);
  # `{:unmatched, reason}` for a mask or a group with no value there; or
  # `{:error, reason}` for a component whose values cannot be known.

  # The unit a value is walked by was resolved when the value was validated
  # with it. Where that left a count from the end, it is resolved here.
  defp candidates({unit, values} = component, ancestors, calendar, :resolved) do
    case flat_map_resolved(List.wrap(values), &resolved_values/1) do
      {:ok, values} -> {:ok, unit, values}
      :unresolved -> candidates(component, ancestors, calendar)
    end
  end

  defp candidates(component, ancestors, calendar, _settled?),
    do: candidates(component, ancestors, calendar)

  # A selection (`L…N`) is a constraint on the value it is in, not a
  # sequence, so it is kept as it is.
  defp candidates({:selection, selection}, _ancestors, _calendar),
    do: {:ok, :selection, [selection]}

  # A group of a set (`{1,2}G3MU`) names a span in each of its groups, and
  # nothing expands it to them, here or in `Tempo.to_interval/2`.
  defp candidates({_unit, {:group, _members}, _size}, _ancestors, _calendar),
    do: {:error, :grouped_component}

  # An unspecified year (`X*Y`) is the current year in the value's calendar,
  # by `Tempo.Clock`: the Hebrew year that holds today for `X*Y[u-ca=hebrew]`.
  defp candidates({:year, :any}, _ancestors, calendar) do
    today = Clock.utc_now() |> DateTime.to_date()

    case Date.convert(today, calendar) do
      {:ok, %Date{year: year}} -> {:ok, :year, [year]}
      {:error, _incompatible} -> {:error, no_current_year_error(today, calendar)}
    end
  end

  defp candidates({unit, :any}, ancestors, calendar) do
    with {:ok, range} <- Mask.unspecified(unit, Enum.reverse(ancestors), calendar) do
      {:ok, unit, Enum.to_list(range)}
    end
  end

  defp candidates({unit, {:mask, mask}}, ancestors, calendar) do
    case Mask.candidates(unit, mask, Enum.reverse(ancestors), calendar) do
      {:ok, []} -> {:unmatched, {:no_candidates, unit}}
      {:ok, values} -> {:ok, unit, values}
      {:error, _reason} = error -> error
    end
  end

  # A group (`2G3MU`, the second group of three months) is the values it
  # holds, as far as its container has them: the last group of eleven days in
  # February stops at the 28th. One that starts beyond its container has none.
  defp candidates({unit, {:group, %Range{} = range}}, ancestors, calendar) do
    prefix = Enum.reverse(ancestors)

    case Group.bound_groups(prefix ++ [{unit, {:group, range}}], calendar) do
      {:ok, bounded} -> {:ok, unit, bounded |> List.last() |> group_values()}
      {:error, exception} -> {:unmatched, exception}
    end
  end

  # ISO 8601-2 significant digits. A year tagged `{value, [significant_digits:
  # n]}` (`1950S2`, its first two digits significant) is any of the values
  # sharing those digits: `1950S2` is `1900..1999` and `Y3388E2S3` is
  # `338800..338899`. A block of more than `@significant_digits_limit` values
  # is not walked; the value can still be held and compared.
  defp candidates({unit, {value, [significant_digits: digits]}}, _ancestors, _calendar)
       when is_integer(value) and is_integer(digits) and digits > 0 do
    range = significant_digits_range(value, digits)

    case Range.size(range) do
      size when size > @significant_digits_limit ->
        {:error, {:significant_digits, value, digits, size}}

      _size ->
        {:ok, unit, Enum.to_list(range)}
    end
  end

  # Any other annotation on a value (a margin of error, `2018±2Y`) is not a
  # sequence. The value is walked as the span it names, which is how
  # `Tempo.to_interval/2` reads it and how `count/1` and `slice/1` walk it.
  defp candidates({unit, {value, options}}, ancestors, calendar)
       when is_integer(value) and is_list(options) do
    candidates({unit, value}, ancestors, calendar)
  end

  # A literal: a value, a set or a range of them. Each is resolved against
  # the components before it as a scalar literal is when it is parsed.
  defp candidates({unit, literal}, ancestors, calendar) do
    ancestors = Enum.reverse(ancestors)
    resolve = &resolve_candidate(unit, &1, ancestors, calendar)

    case flat_map_resolved(raw_candidates(literal), resolve) do
      {:ok, values} -> {:ok, unit, values}
      :unresolved -> {:error, {:unresolved, unit}}
    end
  end

  defp group_values({_unit, {:group, %Range{} = range}}), do: Enum.to_list(range)

  defp no_current_year_error(today, calendar) do
    ConversionError.exception(
      value: today,
      reason:
        "An unspecified year is the current year, and today (#{Date.to_iso8601(today)}) " <>
          "does not convert to #{inspect(calendar)}."
    )
  end

  # The values of a resolved literal: whole numbers from zero, ranges of them,
  # and the fractions of a second.
  defp resolved_values(value) when is_integer(value) and value >= 0, do: {:ok, [value]}

  defp resolved_values(%Range{first: first, last: last} = range) when first >= 0 and last >= 0,
    do: {:ok, Enum.to_list(range)}

  defp resolved_values({value, precision} = fraction)
       when is_integer(value) and is_integer(precision),
       do: {:ok, [fraction]}

  defp resolved_values(_unresolved), do: :unresolved

  defp raw_candidates(value) when is_list(value), do: Enum.flat_map(value, &raw_candidates/1)
  defp raw_candidates(value), do: [value]

  # `Enum.flat_map/2` over results: each `fun` gives `{:ok, list}`, and the
  # first `:unresolved` is the answer for them all.
  defp flat_map_resolved([item], fun), do: fun.(item)
  defp flat_map_resolved(items, fun), do: flat_map_resolved(items, fun, [])

  defp flat_map_resolved([], _fun, gathered),
    do: {:ok, gathered |> :lists.reverse() |> :lists.append()}

  defp flat_map_resolved([item | items], fun, gathered) do
    case fun.(item) do
      {:ok, list} -> flat_map_resolved(items, fun, [list | gathered])
      :unresolved -> :unresolved
    end
  end

  # A unit with the same extent whatever the date is read alone, which spares
  # resolving the date before it again for every hour, minute and second.
  # One that is not a value alone (a leap second, which its hour, minute and
  # date decide) is read after its ancestors.
  defp resolve_candidate(unit, raw, [_ | _] = ancestors, calendar)
       when unit in @fixed_extent_units do
    case resolve_candidate(unit, raw, [], calendar) do
      {:ok, [_ | _]} = resolved -> resolved
      _not_a_value_alone -> resolve_after(unit, raw, ancestors, calendar)
    end
  end

  defp resolve_candidate(unit, raw, ancestors, calendar),
    do: resolve_after(unit, raw, ancestors, calendar)

  # Resolve one candidate against its concrete ancestors. A range or a
  # negative resolves to this context's real values; a value the
  # context cannot hold is not an occurrence and drops out — the set
  # semantics ISO 8601-2 and RFC 5545 share ("invalid dates are
  # ignored"), so `{28..31}D` over January and February is 31 days
  # then 1, not four days then four invalid ones.
  defp resolve_after(unit, raw, ancestors, calendar) do
    written = ancestors ++ [{unit, raw}]

    case Validation.validate(%Tempo{time: written, calendar: calendar}, calendar) do
      {:ok, %Tempo{time: validated}} ->
        case validated_value(validated, written) do
          {:ok, value} -> integers(value)
          :restated -> restated_candidate(unit, raw, ancestors, calendar)
        end

      # The validator names the range this unit can hold in this
      # context (12 months in a common Hebrew year, 28 days in a
      # non-leap February). Clip an overflowing range to it rather
      # than discarding the whole range.
      {:error, %InvalidDateError{valid_range: %Range{} = valid}} when is_struct(raw, Range) ->
        clip_range(raw, valid)

      {:error, _reason} ->
        {:ok, []}
    end
  end

  # The candidate as validation left it, when validation left the value in
  # the units it was written in.
  defp validated_value([{unit, value}], [{unit, _written}]), do: {:ok, value}

  defp validated_value([{unit, _} | validated], [{unit, _} | written]),
    do: validated_value(validated, written)

  defp validated_value(_validated, _written), do: :restated

  # Validation restates some literals in other units — a week date or a day
  # of the year as the calendar date it names — and the candidate it accepted
  # then stands as written. One that counts from the end (`-1`, the last) is
  # read as a range of one, which validation resolves where it stands.
  defp restated_candidate(unit, raw, ancestors, calendar) when is_integer(raw) and raw < 0,
    do: resolve_after(unit, raw..raw//1, ancestors, calendar)

  defp restated_candidate(_unit, raw, _ancestors, _calendar), do: integers(raw)

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
    |> integers()
  end

  defp resolve_bound(bound, %Range{last: valid_last}) when bound < 0, do: valid_last + 1 + bound
  defp resolve_bound(bound, _valid), do: bound

  # A count from the end is resolved by the calendar for date units and by
  # the unit's fixed extent for clock units, both in `Tempo.Validation`. A
  # range that still counts from the end has no container to count in — the
  # weeks of no year, the days of no month — so it cannot be listed: not as
  # nothing, which would turn the question into an empty answer silently.
  defp integers(%Range{first: first, last: last}) when first < 0 or last < 0, do: :unresolved

  # `Enum.to_list/1` respects the range's step, so a descending range
  # enumerates descending and a range whose step cannot reach its end
  # is empty.
  defp integers(%Range{} = range), do: {:ok, Enum.to_list(range)}
  defp integers(value) when is_list(value), do: flat_map_resolved(value, &integers/1)
  defp integers(value), do: {:ok, [value]}

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

  ## The error that stops a walk

  # Each names the value being walked, as `Tempo.to_interval/2` names it.

  defp exception(_tempo, exception) when is_exception(exception), do: exception

  defp exception(tempo, :grouped_component),
    do: ConversionError.exception(value: tempo, reason: :grouped_component)

  # A mask or an unspecified unit whose values depend on a year the value
  # does not have.
  defp exception(tempo, :unanchored),
    do: UnanchoredError.exception(value: tempo, reason: :masked)

  # A count from the end of a unit the value does not bound: the weeks of no
  # year, the days of no month.
  defp exception(%Tempo{time: time} = tempo, {:unresolved, unit}) do
    if List.keymember?(time, :year, 0) do
      ConversionError.exception(
        value: tempo,
        reason:
          "Cannot list #{inspect(tempo)}: its #{unit} counts from the end of a span " <>
            "the units before it do not fix."
      )
    else
      UnanchoredError.exception(value: tempo)
    end
  end

  defp exception(_tempo, {:significant_digits, value, digits, size}) do
    ArgumentError.exception(
      "Cannot enumerate a significant-digits block of #{size} candidates " <>
        "(limit: #{@significant_digits_limit}). Source: #{inspect(value)}S#{digits}"
    )
  end

  defp exception(tempo, reason), do: Mask.error(tempo, reason)

  ## Implicit enumeration

  # Whether a value names several values of its own (a set, a range, a mask,
  # an unspecified unit, a group), which a walk yields, rather than one span,
  # which is walked by the unit below its own.
  def explicitly_enumerable?(%Tempo{time: time}), do: names_several?(time)

  # A selection is a constraint, not a sequence, so it does not make the
  # value enumerable on its own, though its inner keyword list is a list.
  defp names_several?([{:selection, _} | rest]), do: names_several?(rest)
  defp names_several?([{_unit, value} | _rest]) when is_list(value), do: true
  defp names_several?([{_unit, :any} | _rest]), do: true
  defp names_several?([{_unit, {:mask, _}} | _rest]), do: true
  defp names_several?([{_unit, {:group, _}} | _rest]), do: true
  # A group of a set (`{1,2}G3MU`) names several spans, though nothing walks
  # them.
  defp names_several?([{_unit, {:group, _members}, _size} | _rest]), do: true
  defp names_several?([_component | rest]), do: names_several?(rest)
  defp names_several?([]), do: false

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
