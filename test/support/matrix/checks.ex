defmodule Tempo.Matrix.Checks do
  @moduledoc """
  The consistency checks of the matrix: that every operation agrees with
  what `Tempo.to_interval/2` covers (see `plans/validated-core.md`).

  A check takes a value, or two, and answers `:ok`, `:skip` when the
  question does not arise for them (the value has no span, the operation
  refuses it by name), or `{:fail, detail}`. What a value covers is its
  extent (`Tempo.Matrix.Extent`), measured apart from the code under
  test, so a check that passes says the operation and the conversion read
  the value one way.

  A check may raise: an operation allowed to raise on purpose ends the
  cell, and the census counts that as the question not arising.

  """

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.Duration
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Corpus
  alias Tempo.Matrix.Extent
  alias Tempo.Matrix.Runner

  @microseconds 1_000_000
  @hour 3_600 * @microseconds
  @day 24 * @hour

  @type answer :: :ok | :skip | {:fail, String.t()}
  @type of_one :: {String.t(), (Corpus.entry(), term() -> answer())}
  @type of_two :: {String.t(), (term(), term() -> answer())}

  @doc """
  The checks of one value.

  ### Returns

  * A list of `{name, function}`, the function taking the corpus entry and
    the value it reads as.

  """
  @spec unary() :: [of_one()]
  def unary do
    [
      {"the walk covers what to_interval/2 does", fn _entry, value -> walk(value) end},
      {"to_interval_set/2 covers what to_interval/2 does",
       fn _entry, value -> interval_set(value) end},
      {"to_interval/2 of its result is the result", fn _entry, value -> idempotent(value) end},
      {"to_iso8601/1 reads back as the value", &round_trip/2},
      {"inspect/1 reads back as the value", &inspect_round_trip/2},
      {"duration/1 measures what to_interval/2 covers", fn _entry, value -> measure(value) end},
      {"empty?/1 and bounded?/1 agree with to_interval/2",
       fn _entry, value -> empty_and_bounded(value) end},
      {"the length predicates agree with to_interval/2", fn _entry, value -> lengths(value) end}
    ] ++ bangs()
  end

  @doc """
  The checks of two values.

  ### Returns

  * A list of `{name, function}`.

  """
  @spec binary() :: [of_two()]
  def binary do
    [
      {"compare/2 orders the starts to_interval/2 gives", &compare/2},
      {"relation/2 is the relation of the spans", &relation/2},
      {"before?/2, after?/2 and adjacent?/2 follow the spans", &allen_predicates/2},
      {"overlaps?/2 and its kin follow the spans", &set_predicates/2},
      {"the certainty of two crisp values is its crisp answer", &certainty/2},
      {"union/2 covers both", &union/2},
      {"intersection/2 covers what both do", &intersection/2},
      {"difference/2 covers the first without the second", &difference/2},
      {"symmetric_difference/2 covers what one does", &symmetric_difference/2},
      {"complement/2 covers the window without the value", &complement/2},
      {"members_overlapping/2 keeps the members that overlap", &members_overlapping/2},
      {"members_outside/2 keeps the members that do not", &members_outside/2},
      {"duration/2 measures from one start to the other", &duration_between/2}
    ]
  end

  ## One value

  defp walk(value) do
    case Tempo.to_interval(value) do
      {:ok, converted} -> converted |> Extent.of() |> walk_covers(converted, value)
      {:error, _exception} -> :skip
    end
  end

  defp walk_covers({:ok, covered}, _converted, value),
    do: walk_against(value, covered, Extent.of_walk(value))

  # A span with both its ends, neither of which can be placed, where the
  # walk yields values that can: the conversion and the walk read the value
  # two ways. A span with an end left open has no extent to compare.
  defp walk_covers(:none, %Interval{from: %Tempo{}, to: %Tempo{}} = converted, value) do
    case Extent.of_walk(value) do
      {:ok, %{spans: [_ | _]}} ->
        {:fail,
         "to_interval/2 gives #{short(converted)}, whose ends have no place, and the walk " <>
           "yields values that do"}

      _no_walk ->
        :skip
    end
  end

  defp walk_covers(:none, _converted, _value), do: :skip

  # The walk of a value is its span, unit by unit, and the walk of an interval
  # is the interval by the finer of its ends' units: neither covers more than
  # `to_interval/2` does, nor less.
  defp walk_against(_value, covered, {:ok, walked}),
    do: same(measured_part(covered, walked), walked, "to_interval/2", "the walk")

  defp walk_against(_value, _covered, :none), do: :skip

  # A walk measured as far as it was taken is compared with what
  # `to_interval/2` covers up to where it stopped.
  defp measured_part(covered, %{whole?: true}), do: covered

  defp measured_part(covered, %{spans: spans}) do
    {_from, limit} = List.last(spans)
    Extent.up_to(covered, limit)
  end

  defp interval_set(value) do
    with {:ok, converted} <- Tempo.to_interval(value),
         {:ok, covered} <- Extent.of(converted),
         {:ok, set} <- Tempo.to_interval_set(value),
         {:ok, set_covered} <- Extent.of(set) do
      same(covered, set_covered, "to_interval/2", "to_interval_set/2")
    else
      _refused_or_unmeasured -> :skip
    end
  end

  defp idempotent(value) do
    with {:ok, converted} <- Tempo.to_interval(value),
         {:ok, covered} <- Extent.of(converted) do
      case Tempo.to_interval(converted) do
        {:ok, again} ->
          again |> Extent.of() |> same_or_unmeasured(covered, "its result")

        {:error, exception} ->
          {:fail, "to_interval/2 refuses its own result: #{message(exception)}"}
      end
    else
      _refused_or_unmeasured -> :skip
    end
  end

  defp same_or_unmeasured({:ok, again}, covered, name),
    do: same(covered, again, "to_interval/2", name)

  defp same_or_unmeasured(:none, _covered, name), do: {:fail, "#{name} cannot be measured"}

  defp round_trip(entry, value) do
    case Tempo.to_iso8601(value) do
      {:ok, text} -> reads_back(text, entry, value, "to_iso8601/1")
      {:error, _exception} -> :skip
    end
  end

  # A value's inspected form is the sigil that builds it. One written with
  # more than the sigil (an interval's unit, a set's members) is not text to
  # read back.
  defp inspect_round_trip(entry, value) do
    case Regex.run(~r/\A~o"([^"]*)"\z/, inspect(value)) do
      [_whole, text] -> reads_back(text, entry, value, "inspect/1")
      _another_form -> :skip
    end
  end

  defp reads_back(text, entry, value, name) do
    case Corpus.read(%{entry | text: text}) do
      {:ok, again} ->
        same_value(value, again, text, name)

      {:error, exception} ->
        {:fail, "#{name} writes #{text}, which is not read: #{message(exception)}"}
    end
  end

  # The value read back writes the same text and holds the same calendar,
  # zone and tags in every value it is made of: a calendar is recorded as its
  # module alone, so one a suffix names and one given as a module are the
  # same. It is not yet `again == value`: a qualification on every component
  # is held on each and written, and read back, as the value's (`2026?Y` is
  # `2026Y?`), an item of its own in `TODO.md`.
  defp same_value(value, again, text, name) do
    cond do
      Tempo.to_iso8601(again) != Tempo.to_iso8601(value) ->
        {:fail, "#{name} writes #{text}, which reads as #{inspect(again)}"}

      frames(again) != frames(value) ->
        {:fail, "#{name} writes #{text}, which reads back with another calendar, zone or tags"}

      true ->
        same_cover_of(value, again, "the value", "#{text} read back")
    end
  end

  defp frames(%Tempo{calendar: calendar, extended: extended, shift: shift}),
    do: [{calendar, extended, shift}]

  defp frames(%Interval{from: from, to: to, repeat_rule: rule}),
    do: frames(from) ++ frames(to) ++ frames(rule)

  defp frames(%Tempo.Set{set: members, except: except}),
    do: Enum.flat_map(members ++ except, &frames/1)

  defp frames(%Tempo.Range{first: first, last: last}), do: frames(first) ++ frames(last)
  defp frames(_other), do: []

  defp same_cover_of(a, b, a_name, b_name) do
    with {:ok, a_extent} <- cover(a),
         {:ok, b_extent} <- cover(b) do
      same(a_extent, b_extent, a_name, b_name)
    else
      _refused_or_unmeasured -> :ok
    end
  end

  defp measure(value) do
    with %Duration{} = duration <- Tempo.duration(value),
         {:ok, %Interval{} = span} <- Tempo.to_interval(value) do
      measured(duration, span)
    else
      _no_duration_or_several_spans -> :skip
    end
  end

  # A length in date units is counted on the wall calendar, and one in clock
  # units is elapsed time.
  defp measured(%Duration{time: time} = duration, %Interval{from: from, to: to}) do
    case duration_kind(time) do
      :clock -> elapsed(duration, from, to)
      :date -> on_the_wall(duration, from, to)
      :mixed -> :skip
    end
  end

  defp elapsed(%Duration{time: time} = duration, from, to) do
    with {:ok, line, from_position} <- Extent.position(from),
         {:ok, ^line, to_position} <- Extent.position(to) do
      if to_position - from_position == clock_microseconds(time),
        do: :ok,
        else:
          {:fail,
           "#{inspect(duration)} is not the #{to_position - from_position} microseconds " <>
             "from #{inspect(from)} to #{inspect(to)}"}
    else
      _unmeasured -> :skip
    end
  end

  defp on_the_wall(%Duration{time: time} = duration, from, to) do
    with {:ok, from_wall} <- wall(from),
         {:ok, to_wall} <- wall(to) do
      if NaiveDateTime.shift(from_wall, date_shift(time)) == to_wall,
        do: :ok,
        else:
          {:fail,
           "#{inspect(duration)} from #{inspect(from)} is " <>
             "#{NaiveDateTime.shift(from_wall, date_shift(time))}, not #{inspect(to)}"}
    else
      _no_wall_reading -> :skip
    end
  end

  defp duration_kind(time) do
    units = Keyword.keys(time)

    cond do
      Enum.all?(units, &(&1 in [:hour, :minute, :second, :microsecond])) -> :clock
      Enum.all?(units, &(&1 in [:year, :month, :week, :day])) -> :date
      true -> :mixed
    end
  end

  defp clock_microseconds(time) do
    Enum.reduce(time, 0, fn
      {:hour, hours}, sum -> sum + hours * @hour
      {:minute, minutes}, sum -> sum + minutes * 60 * @microseconds
      {:second, seconds}, sum -> sum + round(seconds * @microseconds)
      {:microsecond, {value, _precision}}, sum -> sum + value
      {:microsecond, value}, sum -> sum + value
    end)
  end

  defp date_shift(time), do: Keyword.take(time, [:year, :month, :week, :day])

  # The wall reading of a Gregorian point: its date and time as written,
  # with what is absent the first.
  defp wall(%Tempo{time: time, calendar: calendar})
       when calendar in [Calendrical.Gregorian, Calendar.ISO, nil] do
    with true <- Enum.all?(time, fn {_unit, value} -> is_integer(value) end),
         true <- Keyword.keys(time) -- [:year, :month, :day, :hour, :minute, :second] == [],
         {:ok, year} <- Keyword.fetch(time, :year),
         {:ok, naive} <-
           NaiveDateTime.new(
             year,
             time[:month] || 1,
             time[:day] || 1,
             time[:hour] || 0,
             time[:minute] || 0,
             time[:second] || 0
           ) do
      if Keyword.has_key?(time, :day) and not Keyword.has_key?(time, :month),
        do: :none,
        else: {:ok, naive}
    else
      _no_wall_reading -> :none
    end
  end

  defp wall(_point), do: :none

  defp empty_and_bounded(value) do
    with {:ok, converted} <- Tempo.to_interval(value),
         {:ok, covered} <- Extent.of(converted) do
      cond do
        Tempo.bounded?(value) != true -> {:fail, "bounded?/1 is false of a span with two ends"}
        Tempo.empty?(value) != (covered.spans == []) -> {:fail, emptiness(value, covered)}
        true -> :ok
      end
    else
      _refused_or_unmeasured -> :skip
    end
  end

  defp emptiness(value, covered) do
    "empty?/1 is #{Tempo.empty?(value)} of a value that covers #{Extent.microseconds(covered)} " <>
      "microseconds"
  end

  # `at_least?/2`, `at_most?/2` and `exactly?/2` against a day, and
  # `longer_than?/2` and `shorter_than?/2` against an hour, of a value that
  # is one span. A day is counted on the wall calendar where the span has
  # one, and is a turn of the clock where it has none.
  defp lengths(value) do
    with {:ok, %Interval{from: from, to: to} = span} <- Tempo.to_interval(value),
         {:ok, %{spans: [_one]} = covered} <- Extent.of(span) do
      elapsed = Extent.microseconds(covered)

      first_failure([
        expect("longer_than?/2", Tempo.longer_than?(value, ~o"PT1H"), elapsed > @hour),
        expect("shorter_than?/2", Tempo.shorter_than?(value, ~o"PT1H"), elapsed < @hour)
        | against_a_day(value, covered, wall(from), wall(to))
      ])
    else
      _refused_or_several_spans -> :skip
    end
  end

  defp against_a_day(value, _covered, {:ok, from_wall}, {:ok, to_wall}) do
    order = NaiveDateTime.compare(NaiveDateTime.shift(from_wall, day: 1), to_wall)
    day_predicates(value, order)
  end

  defp against_a_day(value, %{line: {:cycle, _unit}} = covered, _from, _to),
    do: day_predicates(value, Extent.compare(@day, Extent.microseconds(covered)))

  defp against_a_day(_value, _covered, _from, _to), do: []

  # `order` is how a day from the start compares with the end.
  defp day_predicates(value, order) do
    [
      expect("at_least?/2", Tempo.at_least?(value, ~o"P1D"), order in [:lt, :eq]),
      expect("at_most?/2", Tempo.at_most?(value, ~o"P1D"), order in [:gt, :eq]),
      expect("exactly?/2", Tempo.exactly?(value, ~o"P1D"), order == :eq)
    ]
  end

  # A function and its bang form: the bang returns what the plain form
  # wraps in `:ok`, and raises the error it returns.
  defp bangs do
    [
      {"to_interval/1", &Tempo.to_interval/1, &Tempo.to_interval!/1},
      {"to_interval_set/1", &Tempo.to_interval_set/1, &Tempo.to_interval_set!/1},
      {"to_calendar/2", &Tempo.to_calendar(&1, Hebrew), &Tempo.to_calendar!(&1, Hebrew)},
      {"extend/1", &Tempo.extend/1, &Tempo.extend!/1},
      {"at/2", &Tempo.at(&1, ~o"T17"), &Tempo.at!(&1, ~o"T17")},
      {"on/2", &Tempo.on(&1, ~o"2026-06-15"), &Tempo.on!(&1, ~o"2026-06-15")},
      {"select/2", &Tempo.select(&1, [1, 15]), &Tempo.select!(&1, [1, 15])},
      {"to_iso8601/1", &Tempo.to_iso8601/1, &Tempo.to_iso8601!/1},
      {"to_string/1", &Tempo.to_string/1, &Tempo.to_string!/1},
      {"to_relative_string/2", &Tempo.to_relative_string(&1, from: ~o"2026-10-03"),
       &Tempo.to_relative_string!(&1, from: ~o"2026-10-03")},
      {"duration/2", &Tempo.duration(~o"2020-01-01", &1), &Tempo.duration!(~o"2020-01-01", &1)}
    ]
    |> Enum.map(fn {name, plain, bang} ->
      {"#{name} and its bang form agree", fn _entry, value -> bang(name, plain, bang, value) end}
    end)
  end

  defp bang(name, plain, bang, value) do
    case {plain.(value), Runner.attempt(fn -> bang.(value) end)} do
      {{:ok, returned}, {:returned, banged}} ->
        same_term(name, returned, banged)

      {{:error, %{__struct__: module}}, {:raised, module}} ->
        :ok

      {{:error, exception}, {:raised, module}} ->
        {:fail, raised_another(name, exception, module)}

      {{:ok, _returned}, {:raised, module}} ->
        {:fail, "#{name} answers and its bang form raises #{inspect(module)}"}

      {{:error, exception}, {:returned, _banged}} ->
        {:fail, "#{name} refuses (#{message(exception)}) and its bang form answers"}

      {_another_shape, _banged} ->
        :skip
    end
  end

  # A lazy set holds the functions that generate it, which are never equal.
  defp same_term(_name, %IntervalSet{} = returned, %IntervalSet{} = banged) do
    if IntervalSet.bounded?(returned) and IntervalSet.bounded?(banged),
      do: same_term(:members, IntervalSet.members(returned), IntervalSet.members(banged)),
      else: :ok
  end

  defp same_term(_name, same, same), do: :ok

  defp same_term(name, returned, banged),
    do: {:fail, "#{name} answers #{short(returned)} and its bang form #{short(banged)}"}

  defp raised_another(name, exception, module) do
    "#{name} returns a #{inspect(exception.__struct__)} and its bang form raises " <>
      "#{inspect(module)}"
  end

  ## Two values

  defp compare(%Tempo{} = a, %Tempo{} = b) do
    with {:ok, %{spans: [{a_start, _} | _]} = a_cover} <- cover(a),
         {:ok, %{spans: [{b_start, _} | _]} = b_cover} <- cover(b),
         true <- Extent.same_line?(a_cover, b_cover) do
      expect("compare/2", Tempo.compare(a, b), Extent.compare(a_start, b_start))
    else
      false -> no_order(a, b)
      _refused_or_unmeasured -> :skip
    end
  end

  defp compare(_a, _b), do: :skip

  # Two values on different lines have no order, and `compare/2` raises.
  defp no_order(a, b),
    do:
      {:fail,
       "compare/2 orders #{inspect(a)} and #{inspect(b)} as #{Tempo.compare(a, b)}, and they share no line"}

  # A relation is of two spans, so a value that converts to several members
  # has none, whether or not they touch: `relation/2` refuses it.
  defp relation(a, b) do
    with {:ok, a_span} <- one_member(a),
         {:ok, b_span} <- one_member(b) do
      related(Tempo.relation(a, b), a_span, b_span)
    else
      _refused_or_unmeasured -> :skip
    end
  end

  defp related(answer, a_span, b_span) do
    case {answer, expected_relation(a_span, b_span)} do
      {same, same} when is_atom(same) ->
        :ok

      {{:error, _exception}, unrelated} when unrelated in [:apart, :none] ->
        :ok

      {{:error, exception}, expected} ->
        {:fail, "relation/2 refuses (#{message(exception)}), and the spans are #{expected}"}

      {answer, :apart} ->
        {:fail, "relation/2 is #{inspect(answer)} of values that share no line"}

      {answer, :none} ->
        {:fail, "relation/2 is #{inspect(answer)} of a value that is not one span"}

      {answer, expected} ->
        {:fail, "relation/2 is #{inspect(answer)}, and the spans are #{expected}"}
    end
  end

  defp expected_relation(:several, _b_span), do: :none
  defp expected_relation(_a_span, :several), do: :none

  defp expected_relation(a_span, b_span) do
    if Extent.same_line?(a_span, b_span), do: Extent.relation(a_span, b_span), else: :apart
  end

  # The extent of the one member a value converts to, or `:several`.
  defp one_member(value) do
    with {:ok, converted} <- Tempo.to_interval(value),
         {:ok, members} <- Extent.members(converted) do
      case members do
        [member] -> {:ok, member}
        _none_or_several -> {:ok, :several}
      end
    else
      _refused_or_unmeasured -> :none
    end
  end

  defp allen_predicates(a, b) do
    with {:ok, %{spans: [_]} = a_span} <- one_member(a),
         {:ok, %{spans: [_]} = b_span} <- one_member(b),
         true <- Extent.same_line?(a_span, b_span) do
      relation = Extent.relation(a_span, b_span)

      first_failure([
        expect("before?/2", Tempo.before?(a, b), relation in [:precedes, :meets]),
        expect("after?/2", Tempo.after?(a, b), relation in [:preceded_by, :met_by]),
        expect("adjacent?/2", Tempo.adjacent?(a, b), relation in [:meets, :met_by])
      ])
    else
      _refused_or_not_one_span -> :skip
    end
  end

  defp set_predicates(a, b) do
    with {:ok, a_cover, b_cover} <- covers(a, b) do
      shared = Extent.intersection(a_cover, b_cover).spans

      first_failure([
        expect("overlaps?/2", Tempo.overlaps?(a, b), shared != []),
        expect("disjoint?/2", Tempo.disjoint?(a, b), shared == []),
        expect("within?/2", Tempo.within?(a, b), Extent.difference(a_cover, b_cover).spans == []),
        expect(
          "contains?/2",
          Tempo.contains?(a, b),
          Extent.difference(b_cover, a_cover).spans == []
        ),
        expect("equal?/2", Tempo.equal?(a, b), a_cover.spans == b_cover.spans)
      ])
    end
  end

  # A value with no margin, mask or choice of members is crisp: every
  # question of what is possible or certain has its plain answer.
  defp certainty(a, b) do
    with true <- crisp?(a) and crisp?(b),
         {:ok, a_cover, b_cover} <- covers(a, b) do
      overlap? = Extent.intersection(a_cover, b_cover).spans != []
      within? = Extent.difference(a_cover, b_cover).spans == []

      first_failure([
        expect("overlap_certainty/2", Tempo.overlap_certainty(a, b), certain(overlap?)),
        expect("within_certainty/2", Tempo.within_certainty(a, b), certain(within?)),
        expect("possibly_overlaps?/2", Tempo.possibly_overlaps?(a, b), overlap?),
        expect("certainly_overlaps?/2", Tempo.certainly_overlaps?(a, b), overlap?),
        expect("possibly_within?/2", Tempo.possibly_within?(a, b), within?),
        expect("certainly_within?/2", Tempo.certainly_within?(a, b), within?)
      ])
    else
      _not_crisp_or_unmeasured -> :skip
    end
  end

  defp certain(true), do: :certain
  defp certain(false), do: :impossible

  defp crisp?(%Tempo{time: time}) do
    Enum.all?(time, fn
      {:microsecond, {value, precision}} -> is_integer(value) and is_integer(precision)
      {_unit, value} -> is_integer(value)
      _other -> false
    end)
  end

  defp crisp?(%Interval{from: %Tempo{} = from, to: %Tempo{} = to, recurrence: 1}),
    do: crisp?(from) and crisp?(to)

  defp crisp?(_other), do: false

  defp union(a, b), do: combined("union/2", Tempo.union(a, b), a, b, &Extent.union/2)

  defp intersection(a, b),
    do: combined("intersection/2", Tempo.intersection(a, b), a, b, &Extent.intersection/2)

  defp difference(a, b),
    do: combined("difference/2", Tempo.difference(a, b), a, b, &Extent.difference/2)

  defp symmetric_difference(a, b) do
    combined("symmetric_difference/2", Tempo.symmetric_difference(a, b), a, b, fn a_cover,
                                                                                  b_cover ->
      Extent.union(Extent.difference(a_cover, b_cover), Extent.difference(b_cover, a_cover))
    end)
  end

  # The window places a time of day on each of its days, so 09:00 to 17:00
  # within June is each working day's hours, and the complement is the rest
  # of June.
  defp complement(a, b) do
    case {Tempo.complement(a, within: b), daily(a), cover(b)} do
      # A window with no zone: its days are those the reference counts. In a
      # zone the days are the zone's, which the reference does not place.
      {{:ok, set}, {:ok, daily}, {:ok, %{line: :floating} = window}} ->
        expected = Extent.difference(window, Extent.on_each_day(daily, window))
        set |> Extent.of() |> covers_as(expected, "complement/2")

      {_answer, {:ok, _daily}, _b_cover} ->
        :skip

      {answer, _daily, _b_cover} ->
        combined("complement/2", answer, a, b, fn a_cover, b_cover ->
          Extent.difference(b_cover, a_cover)
        end)
    end
  end

  # The spans a value of times of day is written as, on the cycle of the day.
  defp daily(value) do
    with {:ok, converted} <- Tempo.to_interval(value),
         {:ok, {:cycle, :hour}, spans} <- Extent.written(converted) do
      {:ok, spans}
    else
      _refused_or_another_line -> :none
    end
  end

  defp combined(name, answer, a, b, expected) do
    case {answer, cover(a), cover(b)} do
      {{:ok, set}, {:ok, a_cover}, {:ok, b_cover}} ->
        if Extent.same_line?(a_cover, b_cover),
          do: set |> Extent.of() |> covers_as(expected.(a_cover, b_cover), name),
          else: {:fail, "#{name} combines values that share no line"}

      _refused_or_unmeasured ->
        :skip
    end
  end

  defp covers_as({:ok, covered}, expected, name), do: same(expected, covered, "the spans", name)

  defp covers_as(:none, _expected, name),
    do: {:fail, "#{name} gives a set that cannot be measured"}

  defp members_overlapping(a, b),
    do: kept_members("members_overlapping/2", Tempo.members_overlapping(a, b), a, b, true)

  defp members_outside(a, b),
    do: kept_members("members_outside/2", Tempo.members_outside(a, b), a, b, false)

  defp kept_members(name, answer, a, b, overlapping?) do
    with {:ok, set} <- answer,
         {:ok, a_set} <- Tempo.to_interval_set(a),
         {:ok, members} <- Extent.members(a_set),
         {:ok, b_cover} <- cover(b),
         true <- Enum.all?(members, &Extent.same_line?(&1, b_cover)) do
      kept =
        Enum.filter(members, &(Extent.intersection(&1, b_cover).spans != [] == overlapping?))

      expected =
        Enum.reduce(kept, %{line: :empty, spans: [], whole?: true}, &Extent.union(&2, &1))

      set |> Extent.of() |> covers_as(expected, name)
    else
      _refused_or_unmeasured -> :skip
    end
  end

  defp duration_between(%Tempo{} = a, %Tempo{} = b) do
    with {:ok, %Duration{} = duration} <- Tempo.duration(a, b),
         {:ok, a_start} <- start(a),
         {:ok, b_start} <- start(b) do
      measured(duration, %Interval{from: a_start, to: b_start})
    else
      _refused_or_no_start -> :skip
    end
  end

  defp duration_between(_a, _b), do: :skip

  defp start(value) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{from: %Tempo{} = start}} -> {:ok, start}
      _several_or_refused -> :none
    end
  end

  ## Extents and answers

  defp cover(value) do
    with {:ok, converted} <- Tempo.to_interval(value), do: Extent.of(converted)
  end

  defp covers(a, b) do
    with {:ok, a_cover} <- cover(a),
         {:ok, b_cover} <- cover(b),
         true <- Extent.same_line?(a_cover, b_cover) do
      {:ok, a_cover, b_cover}
    else
      _refused_unmeasured_or_apart -> :skip
    end
  end

  defp same(%{spans: spans} = a, %{spans: spans} = b, a_name, b_name) do
    if Extent.same_line?(a, b),
      do: :ok,
      else: {:fail, "#{a_name} and #{b_name} are on different lines"}
  end

  defp same(a, b, a_name, b_name),
    do: {:fail, "#{a_name} covers #{spans(a)}, and #{b_name} #{spans(b)}"}

  defp expect(_name, answer, answer), do: :ok

  defp expect(name, answer, expected),
    do: {:fail, "#{name} is #{inspect(answer)}, and the spans give #{inspect(expected)}"}

  defp first_failure(answers), do: Enum.find(answers, :ok, &(&1 != :ok))

  # Up to three spans as they are placed, for a failure's detail.
  defp spans(%{line: line, spans: spans}) do
    shown = spans |> Enum.take(3) |> Enum.map_join(", ", &span(line, &1))
    more = if length(spans) > 3, do: " and #{length(spans) - 3} more", else: ""
    "[#{shown}]#{more}"
  end

  defp span(line, {from, to}) when line in [:time, :floating],
    do: "#{moment(from)}/#{moment(to)}"

  defp span(_cycle, {from, to}), do: "#{from / @microseconds}s/#{to / @microseconds}s"

  defp moment(position) do
    seconds = Integer.floor_div(position, @microseconds)
    fraction = Integer.mod(position, @microseconds)

    if seconds >= 0 and seconds < 315_537_897_600,
      do: "#{NaiveDateTime.from_gregorian_seconds(seconds, {fraction, 6})}",
      else: "#{seconds}s"
  end

  defp message(exception) when is_exception(exception),
    do: exception |> Exception.message() |> String.replace(~r/\s+/, " ") |> String.slice(0, 120)

  defp message(other), do: short(other)

  defp short(term), do: term |> inspect(limit: 6) |> String.slice(0, 80)
end
