defmodule Tempo.Reference.Test do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Calendrical.ISOWeek
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Extent
  alias Tempo.Matrix.Generators
  alias Tempo.Matrix.Reference
  alias Tempo.Matrix.Spellings

  # The core held to an independent reference (`plans/validated-core.md`).
  # A value is generated as data, written in each form ISO 8601 gives it and
  # read back, and what `Tempo` answers of it is compared with what
  # `Tempo.Matrix.Reference` computes from the data with `Date`,
  # `NaiveDateTime`, `DateTime` and a calendar's own functions.

  # Each spelling of a point, read.
  defp readings(point) do
    for {form, text} <- Spellings.texts(point) do
      case Tempo.from_iso8601(text) do
        {:ok, value} -> {form, text, value}
        {:error, exception} -> flunk("#{text} is not read: #{Exception.message(exception)}")
      end
    end
  end

  # What a value covers, as `Tempo.to_interval/1` gives it.
  defp covered(value) do
    case Tempo.to_interval(value) do
      {:ok, spans} -> Extent.of(spans)
      {:error, exception} -> flunk("#{inspect(value)}: #{Exception.message(exception)}")
    end
  end

  defp point_generators do
    [
      {"a date", Generators.date()},
      {"a time of day", Generators.time_of_day()},
      {"a date and time", Generators.datetime()},
      {"a date and time in a zone", Generators.zoned_datetime()},
      {"a date in another calendar", Generators.other_calendar_date()}
    ]
  end

  describe "every spelling" do
    for {name, index} <- Enum.with_index(["a date", "a time of day", "a date and time"]) do
      property "of #{name} reads as one value" do
        {_name, generator} = Enum.at(point_generators(), unquote(index))

        check all(point <- generator) do
          [{_form, first_text, first} | rest] = readings(point)

          for {_form, text, value} <- rest do
            assert value == first, "#{text} and #{first_text} read as two values"
          end
        end
      end
    end

    # An offset is written with or without its minutes, and a value keeps
    # the precision it was written with (ISO 8601-2 §7.4), so two spellings
    # of a zoned value are one moment and may be two values.
    property "of a date and time in a zone reads as one moment" do
      check all(point <- Generators.zoned_datetime()) do
        [{_form, first_text, first} | rest] = readings(point)

        for {_form, text, value} <- rest do
          assert value.time == first.time, "#{text} and #{first_text} read as two times"
          assert covered(value) == covered(first), "#{text} and #{first_text} are two moments"
        end
      end
    end

    property "of a date in another calendar reads as one value" do
      check all(point <- Generators.other_calendar_date()) do
        [{_form, first_text, first} | rest] = readings(point)

        assert first.calendar == point.calendar

        for {_form, text, value} <- rest do
          assert value == first, "#{text} and #{first_text} read as two values"
        end
      end
    end
  end

  describe "to_interval/1" do
    for {name, index} <- Enum.with_index(Enum.map(1..5, &"generator #{&1}")) do
      property "covers the span the numbers give (#{name})" do
        {_name, generator} = Enum.at(point_generators(), unquote(index))

        check all(point <- generator) do
          {:ok, expected} = Reference.span(point)

          for {_form, text, value} <- readings(point) do
            assert covered(value) == {:ok, expected}, "#{text} covers another span"
          end
        end
      end
    end
  end

  describe "the walk" do
    for {name, index} <- Enum.with_index(Enum.map(1..5, &"generator #{&1}")) do
      property "yields the values of the next unit, in order (#{name})" do
        {_name, generator} = Enum.at(point_generators(), unquote(index))

        check all(point <- generator, walkable?(point), max_runs: 40) do
          expected = Reference.parts(point)
          [{_form, text, value} | _rest] = readings(point)

          if expected != :none do
            {:ok, parts} = expected
            walked = Enum.map(value, &covered/1)

            assert walked == Enum.map(parts, &{:ok, &1}), "#{text} is walked another way"
            assert Enum.count(value) == length(parts)
          end
        end
      end
    end
  end

  # A microsecond has no finer unit to walk by.
  defp walkable?(%{fraction: {_value, 6}}), do: false
  defp walkable?(_point), do: true

  # The first spelling of a point, read.
  defp reading(point) do
    [{_form, _text, value} | _rest] = readings(point)
    value
  end

  describe "the constructor" do
    property "builds the value the spellings read as" do
      check all(
              point <-
                one_of([Generators.date(), Generators.time_of_day(), Generators.datetime()])
            ) do
        assert Tempo.new(point.date ++ point.time ++ fraction(point)) == {:ok, reading(point)}
      end
    end

    property "builds a value in a zone or in another calendar as it is read" do
      generators = one_of([Generators.named_zone_datetime(), Generators.other_calendar_date()])

      check all(point <- generators) do
        {:ok, built} = Tempo.new(point.date ++ point.time ++ fraction(point) ++ options(point))
        read = reading(point)

        assert {built.time, built.calendar} == {read.time, read.calendar}
        assert covered(built) == covered(read)
      end
    end
  end

  defp fraction(%{fraction: nil}), do: []

  defp fraction(%{fraction: {value, digits}}),
    do: [microsecond: {value * Integer.pow(10, 6 - digits), digits}]

  defp options(%{zone: {:zone, name}}), do: [zone: name]
  defp options(%{calendar: calendar}), do: [calendar: calendar]

  describe "the accessors" do
    property "read a day's units as Date gives them" do
      check all(point <- Generators.dated_day()) do
        value = reading(point)
        date = Reference.first_date(point)

        assert {Tempo.year(value), Tempo.month(value), Tempo.day(value)} ==
                 {date.year, date.month, date.day}

        assert Tempo.day_of_week(value) == Date.day_of_week(date)
        assert Tempo.day_of_year(value) == Date.day_of_year(date)
        assert Tempo.quarter_of_year(value) == Date.quarter_of_year(date)
        assert Tempo.days_in_month(value) == Date.days_in_month(date)
        assert Tempo.leap_year?(value) == Date.leap_year?(date)
      end
    end

    property "read a time of day's units as they were written" do
      check all(point <- one_of([Generators.time_of_day(), Generators.datetime()])) do
        value = reading(point)

        assert {Tempo.hour(value), Tempo.minute(value), Tempo.second(value)} ==
                 {point.time[:hour], point.time[:minute], point.time[:second]}
      end
    end

    property "read a year, a month and a week as they were written" do
      check all(point <- Generators.coarse_date()) do
        value = reading(point)

        assert Tempo.year(value) == point.date[:year]
        assert Tempo.month(value) == point.date[:month]
        assert Tempo.week(value) == point.date[:week]
        assert Tempo.day(value) == nil
      end
    end

    property "resolution/1 is the last unit written" do
      check all(point <- Generators.dated(), point.fraction == nil) do
        {unit, _value} = List.last(point.date ++ point.time)
        expected = if unit in [:day_of_week, :day_of_year], do: :day, else: unit

        assert Tempo.resolution(reading(point)) == {expected, 1}
      end
    end
  end

  describe "the conversions" do
    property "give the Elixir value the numbers are" do
      generators =
        one_of([
          Generators.date(),
          Generators.time_of_day(),
          Generators.datetime(),
          Generators.zoned_datetime(),
          Generators.other_calendar_date()
        ])

      check all(point <- generators) do
        value = reading(point)

        case Reference.elixir(point) do
          {:ok, expected} -> assert_elixir(value, expected)
          :none -> assert {:error, %Tempo.ConversionError{}} = Tempo.to_elixir(value)
        end
      end
    end

    property "from_elixir/1 gives back the value read" do
      generators =
        one_of([
          Generators.calendar_day(),
          Generators.time_to_the_second(),
          Generators.datetime_to_the_second()
        ])

      check all(point <- generators) do
        {:ok, elixir} = Reference.elixir(point)

        assert Tempo.from_elixir(elixir) == reading(point)
      end
    end

    property "from_elixir/1 of a DateTime is the moment it is, in its zone" do
      check all(point <- Generators.named_zone_datetime()) do
        {:ok, datetime} = Reference.datetime(point)
        value = Tempo.from_elixir(datetime)

        assert value.time == reading(point).time
        assert covered(value) == covered(reading(point))
        assert Tempo.to_datetime(value) == {:ok, datetime}
      end
    end
  end

  defp assert_elixir(value, %Date{} = date) do
    assert Tempo.to_date(value) == {:ok, date}
    assert Tempo.to_elixir(value) == {:ok, date}
  end

  defp assert_elixir(value, %Time{} = time) do
    assert Tempo.to_time(value) == {:ok, time}
    assert Tempo.to_elixir(value) == {:ok, time}
  end

  defp assert_elixir(value, %NaiveDateTime{} = naive) do
    assert Tempo.to_naive_datetime(value) == {:ok, naive}
    assert Tempo.to_elixir(value) == {:ok, naive}
  end

  # A value in a zone gives its wall clock as a `NaiveDateTime` and its
  # moment as a `DateTime`.
  defp assert_elixir(value, %DateTime{} = datetime) do
    assert Tempo.to_datetime(value) == {:ok, datetime}
    assert Tempo.to_elixir(value) == {:ok, datetime}
  end

  # Two related points, read, with the spans the numbers give them.
  defp pair({a, b}) do
    {:ok, a_span} = Reference.span(a)
    {:ok, b_span} = Reference.span(b)
    {reading(a), reading(b), a_span, b_span}
  end

  describe "two values" do
    property "compare/2 orders them by where they start" do
      check all(points <- Generators.related()) do
        {a, b, %{spans: [{a_start, _}]}, %{spans: [{b_start, _}]}} = pair(points)

        assert Tempo.compare(a, b) == Extent.compare(a_start, b_start)
      end
    end

    property "relation/2 is the Allen relation of their spans" do
      check all(points <- Generators.related()) do
        {a, b, a_span, b_span} = pair(points)

        assert Tempo.relation(a, b) == Extent.relation(a_span, b_span)
      end
    end

    property "the predicates follow the relation of their spans" do
      check all(points <- Generators.related()) do
        {a, b, a_span, b_span} = pair(points)
        relation = Extent.relation(a_span, b_span)
        shared = Extent.intersection(a_span, b_span).spans

        assert Tempo.before?(a, b) == relation in [:precedes, :meets]
        assert Tempo.after?(a, b) == relation in [:preceded_by, :met_by]
        assert Tempo.adjacent?(a, b) == relation in [:meets, :met_by]
        assert Tempo.overlaps?(a, b) == (shared != [])
        assert Tempo.disjoint?(a, b) == (shared == [])
        assert Tempo.within?(a, b) == (Extent.difference(a_span, b_span).spans == [])
        assert Tempo.contains?(a, b) == (Extent.difference(b_span, a_span).spans == [])
        assert Tempo.equal?(a, b) == (a_span.spans == b_span.spans)
      end
    end

    property "the set operations cover what the spans do" do
      check all(points <- Generators.related()) do
        {a, b, a_span, b_span} = pair(points)

        assert combined(&Tempo.union/2, a, b) == Extent.union(a_span, b_span).spans
        assert combined(&Tempo.intersection/2, a, b) == Extent.intersection(a_span, b_span).spans
        assert combined(&Tempo.difference/2, a, b) == Extent.difference(a_span, b_span).spans

        assert combined(&Tempo.symmetric_difference/2, a, b) ==
                 Extent.union(
                   Extent.difference(a_span, b_span),
                   Extent.difference(b_span, a_span)
                 ).spans
      end
    end

    property "every relation is met" do
      relations =
        Generators.related()
        |> Enum.take(2_000)
        |> Enum.map(fn points ->
          {_a, _b, a_span, b_span} = pair(points)
          Extent.relation(a_span, b_span)
        end)
        |> Enum.uniq()
        |> Enum.sort()

      assert relations ==
               Enum.sort([
                 :precedes,
                 :meets,
                 :overlaps,
                 :finished_by,
                 :contains,
                 :starts,
                 :equals,
                 :started_by,
                 :during,
                 :finishes,
                 :overlapped_by,
                 :met_by,
                 :preceded_by
               ])
    end
  end

  # The spans a set operation's result covers.
  defp combined(operation, a, b) do
    {:ok, set} = operation.(a, b)
    {:ok, %{spans: spans}} = Extent.of(set)
    spans
  end

  describe "shift/2" do
    property "moves a day as Date.shift/2 moves it" do
      check all(
              point <- Generators.calendar_day(),
              unit <- member_of([:year, :month, :week, :day]),
              count <- integer(-40..40)
            ) do
        {:ok, date} = Reference.elixir_date(point)
        expected = Date.shift(date, [{unit, count}])

        assert Tempo.to_date(Tempo.shift(reading(point), [{unit, count}])) == {:ok, expected}
      end
    end

    property "moves a day by several units at once as Date.shift/2 does" do
      check all(
              point <- Generators.calendar_day(),
              years <- integer(-3..3),
              months <- integer(-14..14),
              days <- integer(-40..40)
            ) do
        {:ok, date} = Reference.elixir_date(point)
        units = [year: years, month: months, day: days]

        assert Tempo.to_date(Tempo.shift(reading(point), units)) == {:ok, Date.shift(date, units)}
      end
    end

    property "moves a date and time as NaiveDateTime.shift/2 moves it" do
      check all(
              point <- Generators.datetime_to_the_second(),
              unit <- member_of([:month, :day, :hour, :minute, :second]),
              count <- integer(-100..100)
            ) do
        {:ok, naive} = Reference.naive(point)
        expected = NaiveDateTime.shift(naive, [{unit, count}])

        assert Tempo.to_naive_datetime(Tempo.shift(reading(point), [{unit, count}])) ==
                 {:ok, expected}
      end
    end

    # A unit of the clock is elapsed time in a zone, as `DateTime.shift/2`
    # counts it: an hour after 01:30 on the night the clocks go forward is
    # 03:30.
    property "moves a time in a zone by elapsed time as DateTime.shift/2 does" do
      check all(
              point <- Generators.named_zone_datetime(),
              unit <- member_of([:hour, :minute, :second]),
              count <- integer(-100..100)
            ) do
        {:ok, datetime} = Reference.datetime(point)
        expected = DateTime.shift(datetime, [{unit, count}])

        assert Tempo.to_datetime(Tempo.shift(reading(point), [{unit, count}])) == {:ok, expected}
      end
    end

    # A unit of the calendar keeps the wall clock in a zone: a day after
    # noon is noon, whatever the clocks did in between.
    property "moves a time in a zone by days on its wall clock" do
      check all(
              point <- Generators.named_zone_datetime(),
              unit <- member_of([:month, :week, :day]),
              count <- integer(-40..40)
            ) do
        {:ok, naive} = Reference.naive(point)
        {:zone, zone} = point.zone
        wall = NaiveDateTime.shift(naive, [{unit, count}])
        shifted = Tempo.shift(reading(point), [{unit, count}])

        # A wall time the zone skips or shows twice is no one moment to hold
        # the answer to.
        case DateTime.from_naive(wall, zone) do
          {:ok, expected} -> assert Tempo.to_datetime(shifted) == {:ok, expected}
          _gap_or_ambiguous -> assert %Tempo{} = shifted
        end
      end
    end

    property "moves a year, a month and a week by their own units" do
      check all(point <- Generators.coarse_date(), count <- integer(-40..40)) do
        {unit, _value} = List.last(point.date)
        from = Reference.first_date(point)
        shifted = Tempo.shift(reading(point), [{unit, count}])

        # The first day of the unit a count of them on, by `Date`.
        {:ok, %{spans: [{start, _end}]}} = covered(shifted)
        expected = Date.shift(from, [{unit, count}])

        assert start == Date.to_gregorian_days(expected) * 86_400 * 1_000_000
      end
    end

    property "moves a time of day round the clock as Time.shift/2 does" do
      check all(
              point <- Generators.time_to_the_second(),
              unit <- member_of([:hour, :minute, :second]),
              count <- integer(-200..200)
            ) do
        {:ok, time} = Reference.elixir(point)

        assert Tempo.to_time(Tempo.shift(reading(point), [{unit, count}])) ==
                 {:ok, Time.shift(time, [{unit, count}])}
      end
    end
  end

  describe "trunc/2 and round/2" do
    @units [:year, :month, :day, :hour, :minute, :second]

    property "trunc/2 is the value written to the unit and no further" do
      check all(point <- Generators.datetime(), unit <- member_of(@units)) do
        value = reading(point)
        written = Keyword.keys(point.date ++ point.time)

        if unit in written and month_axis?(point) do
          assert Tempo.trunc(value, unit) == reading(truncated(point, unit))
        end
      end
    end

    property "round/2 is the nearer of the unit's start and the next unit's, halves up" do
      check all(point <- Generators.datetime(), unit <- member_of(@units)) do
        value = reading(point)
        written = Keyword.keys(point.date ++ point.time)

        if unit in written and month_axis?(point) and unit != List.last(written) do
          {:ok, %{spans: [{from, to}]}} = Reference.span(truncated(point, unit))
          {:ok, _line, at} = Reference.start(point)
          expected = if 2 * (at - from) >= to - from, do: to, else: from

          {:ok, %{spans: [{rounded, _end}]}} = covered(Tempo.round(value, unit))

          assert rounded == expected
        end
      end
    end
  end

  defp month_axis?(%{date: [year: _, month: _, day: _]}), do: true
  defp month_axis?(_point), do: false

  # A point with the units after `unit` left out.
  defp truncated(point, unit) do
    {date, time} = {point.date, point.time}

    cond do
      Keyword.has_key?(date, unit) ->
        %{point | date: through(date, unit), time: [], fraction: nil}

      unit == :second ->
        %{point | fraction: nil}

      true ->
        %{point | time: through(time, unit), fraction: nil}
    end
  end

  defp through(units, unit) do
    {before, [last | _rest]} =
      Enum.split_while(units, fn {present, _value} -> present != unit end)

    before ++ [last]
  end

  describe "split/1 and at/2" do
    property "the date and the time of day a value splits into are the value, placed" do
      generators =
        one_of([
          Generators.datetime(),
          Generators.zoned_datetime(),
          Generators.other_calendar_day()
        ])

      check all(point <- generators) do
        value = reading(point)
        {date, time} = Tempo.split(value)

        assert_parts(point, date, time)

        if time != nil do
          assert Tempo.at(date, time) == {:ok, value}
          assert Tempo.on(time, date) == {:ok, value}
        end
      end
    end
  end

  # The date is the day the numbers give, in the value's zone, and the time
  # the time of day.
  defp assert_parts(%{time: []} = point, date, time) do
    assert time == nil
    assert covered(date) == Reference.span(point)
  end

  defp assert_parts(point, date, time) do
    assert covered(date) == Reference.span(%{point | time: [], fraction: nil})

    assert {Tempo.hour(time), Tempo.minute(time), Tempo.second(time)} ==
             {point.time[:hour], point.time[:minute], point.time[:second]}
  end

  describe "an interval" do
    property "is one value in every spelling, and covers from its start to its end" do
      check all({from, to, count} <- Generators.interval()) do
        {:ok, expected} = Reference.between(from, to)
        texts = Spellings.interval_texts(from, to, count)

        for {form, text} <- texts do
          interval = read!(text)

          assert covered(interval) == {:ok, expected},
                 "#{text} (#{form}) covers another span than #{inspect(texts)}"
        end
      end
    end

    property "is walked by its ends' unit, a value for each" do
      check all({from, to, count} <- Generators.interval()) do
        interval = read!(Spellings.text(from, :explicit) <> "/" <> Spellings.text(to, :explicit))

        assert Enum.count(interval) == count
        assert covered(hd(Enum.take(interval, 1))) == Reference.span(from)
      end
    end

    property "lasts the count of its unit" do
      check all({from, to, count} <- Generators.interval()) do
        interval = read!(Spellings.text(from, :explicit) <> "/" <> Spellings.text(to, :explicit))
        {unit, _value} = List.last(from.date ++ from.time)
        unit = if unit in [:day_of_week, :day_of_year], do: :day, else: unit

        assert Tempo.duration(interval) == read!(Spellings.duration([{unit, count}]))
      end
    end
  end

  describe "a duration" do
    property "is one value in every spelling, and the Duration Elixir holds" do
      check all(units <- Generators.duration()) do
        [{_form, first_text} | _rest] = texts = Spellings.duration_texts(units)
        first = read!(first_text)

        for {_form, text} <- texts do
          assert Tempo.to_elixir(read!(text)) == {:ok, Duration.new!(units)},
                 "#{text} is another duration than #{first_text}"
        end

        assert Tempo.from_elixir(Duration.new!(units)) == first
        assert Tempo.to_iso8601(first) == {:ok, first_text}
      end
    end

    property "moves a day as Date.shift/2 moves it by the same units" do
      check all(point <- Generators.calendar_day(), units <- Generators.duration()) do
        date_units = Keyword.take(units, [:year, :month, :week, :day])
        {:ok, date} = Reference.elixir_date(point)

        if date_units != [] do
          duration = read!(Spellings.duration(date_units))

          assert Tempo.to_date(Tempo.shift(reading(point), duration)) ==
                   {:ok, Date.shift(date, date_units)}
        end
      end
    end
  end

  describe "a recurrence" do
    # ISO 8601-1 §3.1.1.11: a series of consecutive time intervals of
    # identical duration, each counted from the start.
    property "of a count is that many consecutive spans, each a duration on from the start" do
      check all(
              point <- Generators.calendar_day(),
              unit <- member_of([:year, :month, :week, :day]),
              amount <- integer(1..5),
              count <- integer(2..6)
            ) do
        {:ok, date} = Reference.elixir_date(point)

        text =
          "R#{count}/#{Spellings.text(point, :extended)}/" <> Spellings.duration([{unit, amount}])

        edges = for k <- 0..count, do: gregorian(Date.shift(date, [{unit, amount * k}]))
        expected = edges |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&List.to_tuple/1)

        {:ok, occurrences} = Tempo.to_interval(read!(text))

        assert occurrences |> IntervalSet.members() |> Enum.map(&one_span/1) == expected
      end
    end

    property "of a time of day is counted on the clock" do
      check all(
              point <- Generators.datetime_to_the_minute(),
              unit <- member_of([:hour, :minute]),
              amount <- integer(1..90),
              count <- integer(2..5)
            ) do
        {from, _to} = Reference.wall_span(point)

        text =
          "R#{count}/#{Spellings.text(point, :extended)}/" <> Spellings.duration([{unit, amount}])

        edges =
          for k <- 0..count do
            {seconds, 0} =
              from
              |> NaiveDateTime.shift([{unit, amount * k}])
              |> NaiveDateTime.to_gregorian_seconds()

            seconds * 1_000_000
          end

        expected = edges |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&List.to_tuple/1)
        {:ok, occurrences} = Tempo.to_interval(read!(text))

        assert occurrences |> IntervalSet.members() |> Enum.map(&one_span/1) == expected
      end
    end
  end

  defp gregorian(%Date{} = date), do: Date.to_gregorian_days(date) * 86_400 * 1_000_000

  defp one_span(interval) do
    {:ok, %{spans: [span]}} = Extent.of(interval)
    span
  end

  describe "a set" do
    property "of values is the span of each, in order" do
      check all(points <- uniq_list_of(Generators.date(), min_length: 1, max_length: 5)) do
        text = "{" <> Enum.map_join(points, ",", &Spellings.text(&1, :extended)) <> "}"

        expected =
          points
          |> Enum.map(fn point ->
            {:ok, %{spans: [span]}} = Reference.span(point)
            span
          end)
          |> Enum.sort()

        {:ok, spans} = Tempo.to_interval(read!(text))

        assert spans |> members() |> Enum.map(&one_span/1) |> Enum.sort() == expected
      end
    end

    property "of a range is each value from its first to its last" do
      check all({from, to, count} <- Generators.interval(), from.time == []) do
        text = "{#{Spellings.text(from, :explicit)}..#{Spellings.text(to, :explicit)}}"

        expected =
          for step <- 0..count do
            {:ok, %{spans: [span]}} = Reference.span(Reference.stepped(from, step))
            span
          end

        {:ok, spans} = Tempo.to_interval(read!(text))

        assert spans |> members() |> Enum.map(&one_span/1) == expected
      end
    end
  end

  defp members(%Tempo.Interval{} = interval), do: [interval]
  defp members(%IntervalSet{} = set), do: IntervalSet.members(set)

  describe "a calendar" do
    property "to_calendar/2 is the day Date.convert/2 gives" do
      check all(point <- Generators.other_calendar_day()) do
        {:ok, date} = Reference.elixir_date(point)
        {:ok, gregorian} = Tempo.to_calendar(reading(point), Calendrical.Gregorian)

        assert Tempo.to_date(gregorian) == {:ok, Date.convert!(date, Calendar.ISO)}

        {:ok, back} = Tempo.to_calendar(gregorian, point.calendar)

        assert Tempo.to_date(back) == {:ok, date}
        assert covered(back) == covered(gregorian)
      end
    end
  end

  describe "a zone" do
    property "shift_zone/2 is the same moment on another zone's clock" do
      zones = ["Europe/Paris", "America/New_York", "Australia/Sydney", "Asia/Kolkata", "Etc/UTC"]

      check all(point <- Generators.named_zone_datetime(), zone <- member_of(zones)) do
        {:ok, datetime} = Reference.datetime(point)
        {:ok, shifted} = Tempo.shift_zone(reading(point), zone)

        assert Tempo.to_datetime(shifted) == {:ok, DateTime.shift_zone!(datetime, zone)}
        assert covered(shifted) == covered(reading(point))
      end
    end

    property "in_zone/2 is the wall clock read in the zone" do
      zones = ["Europe/Paris", "America/New_York", "Australia/Sydney", "Asia/Kolkata"]

      check all(point <- Generators.datetime_to_the_second(), zone <- member_of(zones)) do
        {:ok, naive} = Reference.naive(point)
        {:ok, placed} = Tempo.in_zone(reading(point), zone)

        # A wall time the zone skips or shows twice is no one moment.
        case DateTime.from_naive(naive, zone) do
          {:ok, datetime} -> assert Tempo.to_datetime(placed) == {:ok, datetime}
          _gap_or_ambiguous -> assert %Tempo{} = placed
        end
      end
    end
  end

  defp read!(text) do
    case Tempo.from_iso8601(text) do
      {:ok, value} -> value
      {:error, exception} -> flunk("#{text} is not read: #{Exception.message(exception)}")
    end
  end

  # A calendar of weeks counts its year in weeks and its week in days, and
  # `Date` in that calendar is the reference: its month is the week and its
  # day the day of the week.
  describe "a calendar of weeks" do
    property "reads a week date as the day Date gives" do
      check all({year, week, day} <- week_date()) do
        value = week_value([year, "Y", week, "W", day, "K"])
        date = Date.new!(year, week, day, ISOWeek)

        assert Tempo.to_date(value) == {:ok, date}
        assert covered(value) == covered(Tempo.from_date(Date.convert!(date, Calendar.ISO)))
      end
    end

    property "moves a day by days and weeks as Date moves it" do
      check all(
              {year, week, day} <- week_date(),
              {weeks, days} <- tuple({integer(-60..60), integer(-20..20)})
            ) do
        value = week_value([year, "Y", week, "W", day, "K"])
        moved = add_days(Date.new!(year, week, day, ISOWeek), weeks * 7 + days)

        assert Tempo.shift(value, week: weeks, day: days) ==
                 week_value([moved.year, "Y", moved.month, "W", moved.day, "K"])
      end
    end

    property "moves a year and a week by weeks, and to the day by days" do
      check all({year, week, _day} <- week_date(), count <- integer(1..120)) do
        first = Date.new!(year, 1, 1, ISOWeek)
        weeks_on = add_days(first, count * 7)
        days_on = add_days(Date.new!(year, week, 1, ISOWeek), count)

        assert Tempo.shift(week_value([year, "Y"]), week: count) ==
                 week_value([weeks_on.year, "Y", weeks_on.month, "W"])

        assert Tempo.shift(week_value([year, "Y", week, "W"]), day: count) ==
                 week_value([days_on.year, "Y", days_on.month, "W", days_on.day, "K"])
      end
    end

    property "a year is as long as its weeks" do
      check all(year <- integer(1990..2060)) do
        days = Date.diff(Date.new!(year + 1, 1, 1, ISOWeek), Date.new!(year, 1, 1, ISOWeek))
        value = week_value([year, "Y"])

        assert Tempo.exactly?(value, read!("P#{days}D"))
        assert Tempo.exactly?(value, read!("P#{div(days, 7)}W"))
        assert Enum.count(value) == div(days, 7)
      end
    end

    property "truncates and rounds a time to its day" do
      check all({year, week, day} <- week_date(), hour <- integer(0..23)) do
        value = week_value([year, "Y", week, "W", day, "K", "T", hour, "H"])
        today = Date.new!(year, week, day, ISOWeek)
        nearest = if hour < 12, do: today, else: add_days(today, 1)

        assert Tempo.trunc(value, :day) == week_value([year, "Y", week, "W", day, "K"])

        assert Tempo.round(value, :day) ==
                 week_value([nearest.year, "Y", nearest.month, "W", nearest.day, "K"])
      end
    end
  end

  defp week_date do
    gen all(year <- integer(1990..2060), week <- integer(1..52), day <- integer(1..7)) do
      {year, week, day}
    end
  end

  defp week_value(parts), do: Tempo.from_iso8601!(Enum.join(parts), ISOWeek)

  # A day of a calendar of weeks a count of days on: counted on the
  # Gregorian date it is.
  defp add_days(%Date{} = date, days) do
    date |> Date.convert!(Calendar.ISO) |> Date.add(days) |> Date.convert!(ISOWeek)
  end

  describe "the text an interval is shown as" do
    # A span is shown from its first value to its last, the end being
    # excluded. Localize writes the two; which two they are is Tempo's.
    property "names its first day and its last, as Localize writes them" do
      check all(first <- day_as_date(), days <- integer(1..800)) do
        last = Date.add(first, days - 1)
        interval = read!("#{Date.to_iso8601(first)}/#{Date.to_iso8601(Date.add(last, 1))}")

        expected =
          if first == last,
            do: Localize.Date.to_string(first),
            else: Localize.Interval.to_string(first, last)

        assert Tempo.to_string(interval) == expected
      end
    end

    property "is that of the same span with both ends written to the finer unit" do
      units = [:year, :month, :day, :hour]

      check all(
              first <- day_as_date(),
              days <- integer(1..800),
              {from_hour, to_hour} <- tuple({integer(0..23), integer(0..23)}),
              {from_unit, to_unit} <- tuple({member_of(units), member_of(units)}),
              from_unit != to_unit
            ) do
        from = unit_start(first, from_hour, from_unit)
        to = unit_start(Date.add(first, days), to_hour, to_unit)

        finer =
          Enum.max_by([from_unit, to_unit], &Enum.find_index(units, fn unit -> unit == &1 end))

        if NaiveDateTime.before?(from, to) do
          as_written = read!("#{written(from, from_unit)}/#{written(to, to_unit)}")
          to_the_finer = read!("#{written(from, finer)}/#{written(to, finer)}")

          assert Tempo.to_string(as_written) == Tempo.to_string(to_the_finer)
        end
      end
    end
  end

  defp day_as_date do
    gen all(year <- integer(1900..2100), month <- integer(1..12), day <- integer(1..28)) do
      Date.new!(year, month, day)
    end
  end

  # Where the unit a day and an hour lie in starts.
  defp unit_start(date, _hour, :year), do: NaiveDateTime.new!(date.year, 1, 1, 0, 0, 0)
  defp unit_start(date, _hour, :month), do: NaiveDateTime.new!(date.year, date.month, 1, 0, 0, 0)
  defp unit_start(date, _hour, :day), do: NaiveDateTime.new!(date, ~T[00:00:00])
  defp unit_start(date, hour, :hour), do: NaiveDateTime.new!(date, Time.new!(hour, 0, 0))

  defp written(moment, :year), do: Calendar.strftime(moment, "%Y")
  defp written(moment, :month), do: Calendar.strftime(moment, "%Y-%m")
  defp written(moment, :day), do: Calendar.strftime(moment, "%Y-%m-%d")
  defp written(moment, :hour), do: Calendar.strftime(moment, "%Y-%m-%dT%H")

  describe "an IntervalSet of one value" do
    property "to_interval_set/1 gives the one span" do
      check all(point <- Generators.dated()) do
        {:ok, expected} = Reference.span(point)
        [{_form, _text, value} | _rest] = readings(point)
        {:ok, set} = Tempo.to_interval_set(value)

        assert IntervalSet.count(set) == 1
        assert Extent.of(set) == {:ok, expected}
      end
    end
  end
end
