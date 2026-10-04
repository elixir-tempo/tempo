defmodule Tempo.ValidatedCoreTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.ISOWeek
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet

  # What the reference and the exhaustive matrix of `plans/validated-core.md`
  # found, each pinned by the case that showed it. The properties of
  # `Tempo.Reference.Test` and the cells of `Tempo.Matrix.Test` hold the
  # same ground by generation; these say what was wrong.

  defp spans(value) do
    {:ok, set} = Tempo.to_interval(value)
    set |> IntervalSet.members() |> Enum.map(&{&1.from, &1.to})
  end

  describe "a fraction of a second before a time shift" do
    # A dash after a fraction was taken for something other than a shift's
    # sign, so the usual RFC 3339 timestamp west of Greenwich was not read.
    test "behind UTC is read, in each form" do
      for text <- [
            "2026-06-15T10:30:45.5-03:30",
            "2026-06-15T10:30:45,5-03:30",
            "20260615T103045.5-0330",
            "2026-06-15T10:30:45.5-03",
            "T10:30:45.5-03:30"
          ] do
        assert {:ok, value} = Tempo.from_iso8601(text), text
        assert value.time[:microsecond] == {500_000, 1}, text
        assert value.shift[:hour] == -3, text
      end
    end

    test "a comma before a date is still what separates the members of a set" do
      assert {:ok, %Tempo.Set{set: [_first, _second]}} =
               Tempo.from_iso8601("{2026-06-15T10:00,2026-06-16T10:00}")

      assert {:ok, %Tempo.Set{set: [_time, month]}} = Tempo.from_iso8601("{T10:00,2026-06}")
      assert month.time == [year: 2026, month: 6]
    end
  end

  describe "a duration's months" do
    # A date's month 21 is a season. A duration's is twenty-one months.
    test "are a count, however many" do
      assert Tempo.from_iso8601!("P1Y21M").time == [year: 1, month: 21]
      assert Tempo.from_iso8601!("P12Y30M").time == [year: 12, month: 30]

      assert Tempo.to_elixir(Tempo.from_iso8601!("P1Y21M")) ==
               {:ok, %Duration{year: 1, month: 21}}

      assert Tempo.shift(~o"2026-06-15", Tempo.from_iso8601!("P1Y21M")) == ~o"2029-03-15"
    end
  end

  describe "shift/3" do
    # An unknown unit was passed over, leaving the value where it was.
    test "returns an error for a unit a duration has none of" do
      for units <- [[fortnight: 1], [quarter: 1], [century: 1], [day_of_week: 1]] do
        assert {:error, %ArgumentError{}} = Tempo.shift(~o"2026-06-15", units)
      end
    end

    test "returns an error for a count that is no number, and for what is no keyword list" do
      assert {:error, %ArgumentError{}} = Tempo.shift(~o"2026-06-15", day: "1")
      assert {:error, %ArgumentError{}} = Tempo.shift(~o"2026-06-15", day: nil)
      assert {:error, %ArgumentError{}} = Tempo.shift(~o"2026-06-15", [1, 2])
      assert {:error, %ArgumentError{}} = Tempo.shift(~o"2026-06-15T10:30:45", microsecond: 5)
    end

    # The days were counted from the day the months landed on before it was
    # brought into its month: the 28th.
    test "brings the day into its month before it counts the days, as Date.shift/2 does" do
      units = [month: -5, day: -1]

      assert Tempo.shift(~o"2026-07-29", units) == ~o"2026-02-27"

      assert Tempo.to_date(Tempo.shift(~o"2026-07-29", units)) ==
               {:ok, Date.shift(~D[2026-07-29], units)}

      assert Tempo.shift(~o"2026-01-31", month: 1, day: 1) == ~o"2026-03-01"
    end

    test "takes a fraction of a second as the pair Elixir holds" do
      assert Tempo.shift(~o"2026-06-15T10:30:45", microsecond: {500_000, 1}) ==
               ~o"2026-06-15T10:30:45.5"
    end
  end

  describe "an explicit time shift" do
    # ISO 8601-2 §7.4: no sign ahead of UTC, a minus behind it.
    test "is written as the standard writes it, and read back" do
      for {text, written} <- [
            {"2026-06-15T10:00+05:30", "2026Y6M15DT10H0MZ5H30M"},
            {"2026-06-15T10:00+05", "2026Y6M15DT10H0MZ5H"},
            {"2026-06-15T10:00-05:30", "2026Y6M15DT10H0MZ-5H30M"},
            {"2026-06-15T10:00-00:30", "2026Y6M15DT10H0MZ-0H30M"},
            {"2026-06-15T10:00Z", "2026Y6M15DT10H0MZ"},
            {"2026Y6M15DT10HZ7H33M14S", "2026Y6M15DT10HZ7H33M14S"}
          ] do
        value = Tempo.from_iso8601!(text)

        assert Tempo.to_iso8601(value) == {:ok, written}
        assert Tempo.from_iso8601!(written) == value
      end
    end

    test "written with a plus sign is still read" do
      assert Tempo.from_iso8601!("2026Y6M15DT10HZ+2H") == Tempo.from_iso8601!("2026Y6M15DT10HZ2H")
    end
  end

  describe "a recurrence" do
    # ISO 8601-1 §3.1.1.11: consecutive time intervals. The second ended on
    # 28 March, three days before the third began.
    test "is consecutive across the end of a month" do
      assert spans(~o"R3/2026-01-31/P1M") == [
               {~o"2026-01-31", ~o"2026-02-28"},
               {~o"2026-02-28", ~o"2026-03-31"},
               {~o"2026-03-31", ~o"2026-04-30"}
             ]

      assert spans(~o"R3/2024-02-29/P1Y") == [
               {~o"2024-02-29", ~o"2025-02-28"},
               {~o"2025-02-28", ~o"2026-02-28"},
               {~o"2026-02-28", ~o"2027-02-28"}
             ]
    end

    test "counted back from its end is consecutive too" do
      assert spans(~o"R2/P1M/2026-03-31") == [
               {~o"2026-01-31", ~o"2026-02-28"},
               {~o"2026-02-28", ~o"2026-03-31"}
             ]
    end
  end

  describe "split/1 and at/2" do
    # The zone, the qualification and the metadata were dropped.
    test "split/1 keeps what the value carries on both parts" do
      value = Tempo.put_metadata(~o"2026-06-15T14:30?[Europe/Paris]", %{event: "launch"})
      {date, time} = Tempo.split(value)

      assert date == Tempo.put_metadata(~o"2026-06-15?[Europe/Paris]", %{event: "launch"})
      assert {time.extended.zone_id, Tempo.qualification(time)} == {"Europe/Paris", :uncertain}
      assert Tempo.at(date, time) == {:ok, value}
    end

    # A named zone on the time of day was dropped, where an offset was kept.
    test "at/2 gives its result the zone either value has" do
      in_paris = {:ok, ~o"2026-06-15T14:30[Europe/Paris]"}

      assert Tempo.at(~o"2026-06-15", ~o"T14:30[Europe/Paris]") == in_paris
      assert Tempo.at(~o"2026-06-15[Europe/Paris]", ~o"T14:30") == in_paris
      assert Tempo.at(~o"2026-06-15[Europe/Paris]", ~o"T14:30[Europe/Paris]") == in_paris
      assert Tempo.at(~o"2026-06-15", ~o"T14:30Z") == {:ok, ~o"2026-06-15T14:30Z"}
    end

    test "at/2 refuses two values in two zones" do
      assert {:error, %Tempo.ZonedTempoError{}} =
               Tempo.at(~o"2026-06-15[Europe/Paris]", ~o"T14:30[America/New_York]")

      assert {:error, %Tempo.ZonedTempoError{}} = Tempo.at(~o"2026-06-15+02:00", ~o"T14:30Z")
    end
  end

  describe "a group of a set" do
    # A mask after one reached the mask's reader, which took the group for a
    # keyword pair: every operation raised. Each group is read as a group
    # alone is, so a masked day counted in it is refused by name, and a
    # masked hour of a day counted in it is the hours it names.
    test "with a mask after it is read as each of its groups is" do
      for text <- ["2026Y{1,2}G3MUXD", "{1,2}G3MU1XD"] do
        assert {:error, %ConversionError{reason: :counted_in_group}} =
                 Tempo.to_interval(Tempo.from_iso8601!(text))
      end

      assert {:ok, hours} = Tempo.to_interval(Tempo.from_iso8601!("2026Y{1,2}G3MU15DTXH"))

      assert Enum.map(IntervalSet.members(hours), &Interval.from/1) ==
               [~o"2026-01-15T00", ~o"2026-04-15T00"]

      assert {:error, %ConversionError{reason: :counted_in_group}} =
               Tempo.overlap_certainty(Tempo.from_iso8601!("2026Y{1,2}G3MUXD"), ~o"2026-06-15")
    end

    test "at an end of an interval, or the start of a recurrence, is refused by name" do
      assert {:ok, interval} = Tempo.from_iso8601("2026Y{1,2}G3MU15D/2030Y")
      assert {:error, %ConversionError{reason: :grouped_component}} = Tempo.to_interval(interval)
      assert {:ok, _interval} = Tempo.from_iso8601("2020Y/2026Y6M{1,2}G10DU")

      assert {:error, %ConversionError{reason: :grouped_component}} =
               Tempo.to_interval(Tempo.from_iso8601!("R3/2026Y{1,2}G3MU15D/P1D"))
    end
  end

  describe "two groups in one value" do
    # The hours were resolved and the days left a group, a value its own
    # text does not read back as.
    test "resolve until both are one value" do
      assert Tempo.from_iso8601!("2026Y6M2G10DU2GT6HU30M") == ~o"2026-06-11T06:30"
      assert Tempo.from_iso8601!("2026Y2G3MU2G10DUT10H") == ~o"2026-04-11T10"
    end

    test "a qualified unit before a group is read" do
      assert {:ok, value} = Tempo.from_iso8601("2026Y6~M2G10DU")
      assert {:ok, second_ten_days} = Tempo.to_interval(value)

      assert {second_ten_days.from.time, second_ten_days.to.time} ==
               {[year: 2026, month: 6, day: 11], [year: 2026, month: 6, day: 21]}
    end
  end

  describe "a margin of error beside another shape" do
    # The margin stayed on the ends, which no operation could place, or the
    # count from the end was left uncounted.
    test "is dropped before the value is converted, as its walk yields it" do
      assert Tempo.to_interval(Tempo.from_iso8601!("2026±2Y2G3MU")) == {:ok, ~o"2026Y4M/7M"}

      assert {:ok, last_month} = Tempo.to_interval(Tempo.from_iso8601!("2026±2Y-1M15D"))
      assert {last_month.from, last_month.to} == {~o"2026-12-15", ~o"2026-12-16"}
    end

    test "significant digits before a masked unit are read in each year of the block" do
      {:ok, octobers} = Tempo.to_interval(Tempo.from_iso8601!("1950S2Y1XM"))

      assert IntervalSet.count(octobers) == 100
      assert IntervalSet.first(octobers) == ~o"1900Y10M/1901Y1M"
    end
  end

  describe "every week of several years" do
    test "is the weeks of each, not the calendar years" do
      assert spans(~o"202XYXXW") |> hd() == {~o"2020-W01", ~o"2021-W01"}
      assert Tempo.to_interval(~o"2026YXXW") == {:ok, ~o"2026Y1W/2027Y1W"}
    end
  end

  describe "a duration counted from a start that names a span" do
    # A month was no unit of a day of the year to add to, so the end was the
    # start and the interval empty.
    test "is counted from the point the span starts at" do
      assert Tempo.to_interval(Tempo.from_iso8601!("2026YXXO/P1M")) ==
               {:ok, ~o"2026Y1M1D/2026Y2M1D"}
    end

    test "that cannot be counted is the accessor's error, not a raise of another kind" do
      week_and_a_month = Tempo.from_iso8601!("2026Y25WXK/P1M")

      assert_raise Tempo.ResolutionError, fn -> Tempo.year(week_and_a_month) end
    end
  end

  @relations [
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
  ]

  describe "the candidates of two masked values" do
    # Each candidate was paired with each: 27 seconds for 1,440 of them.
    # Related along their runs, the answer is the one the pairs give.
    test "are related as every pair of them is" do
      for {a, b} <- [
            {~o"2026Y6MXXDT10H", ~o"2026Y6MXXDT10H"},
            {~o"2026Y6MXXDT10H", ~o"2026Y6MXXDT11H"},
            {~o"2026Y6MXXDT10H", ~o"2026Y6MXXDT10H30M"},
            {~o"2026Y6M1XDT10H", ~o"2026Y6MXXDT10H"},
            {~o"2026YXXM15D", ~o"2026YXXM20D"},
            {~o"TXXH30M", ~o"TXXH30M15S"}
          ] do
        expected = relations_of_every_pair(a, b)

        for relation <- @relations do
          assert Tempo.relation_certainty(a, b, relation) == certainty(expected, relation),
                 "#{inspect(a)} #{relation} #{inspect(b)}"
        end
      end
    end

    test "are related quickly" do
      day = ~o"TXXH{0..-1}M"

      {microseconds, :possible} = :timer.tc(fn -> Tempo.overlap_certainty(day, day) end)

      assert microseconds < 5_000_000
    end
  end

  describe "the text an interval is shown as" do
    # The last value an interval holds was taken as one of its start's units
    # before its end, so a year to a month ran backwards ("2026 – 2025").
    test "names the last value of the finer of its ends' units" do
      assert Tempo.to_string!(~o"2026/2026-03") == "Jan – Feb 2026"
      assert Tempo.to_string!(~o"1985/1986-06") == "Jan 1985 – May 1986"

      assert Tempo.to_string!(~o"2026-06-01/2026-06-03T12") ==
               "Jun 1, 2026, 12 AM – Jun 3, 2026, 11 AM"

      assert Tempo.to_string!(~o"2026-06-15/PT36H") ==
               Tempo.to_string!(~o"2026-06-15T00/2026-06-16T12")
    end

    # A week beside a date shares no unit with it, and the two were shown as
    # their years.
    test "of a week and a date is the days from the one to the other" do
      assert Tempo.to_string!(~o"2026-W25/2026-07-01") == "Jun 15 – 30, 2026"
      assert Tempo.to_string!(~o"2026-06-15/2026-W27") == "Jun 15 – 28, 2026"
    end

    # A year written to significant digits was given to Localize as a year
    # and a month it does not have.
    test "of significant digits is the block they name, as a mask is" do
      assert Tempo.to_string(~o"1950S2") == Tempo.to_string(~o"19XX")
      assert Tempo.to_string!(~o"1950S2") == "1900 – 1999"
    end
  end

  describe "to_relative_string/2 of an interval written to its end" do
    test "counts to where the interval starts" do
      from = ~o"2026-10-03"

      assert Tempo.to_relative_string(~o"P1M/2026-07-01", from: from) ==
               Tempo.to_relative_string(~o"2026-06-01/2026-07-01", from: from)

      assert Tempo.to_relative_string(~o"R3/P1W/2026-06-22", from: from) ==
               Tempo.to_relative_string(~o"2026-06-01", from: from)
    end

    test "is the error of an interval with no start, where it has none" do
      assert {:error, %IntervalEndpointsError{}} =
               Tempo.to_relative_string(~o"R/P1W/2026-06-22", from: ~o"2026-10-03")
    end
  end

  describe "a calendar of weeks" do
    setup do
      %{year: Tempo.from_iso8601!("2026Y", ISOWeek)}
    end

    # A year had no path to a day, so a day or a week could not be added to
    # it and it had no length in either.
    test "counts its year in weeks and days", %{year: year} do
      assert Tempo.shift(year, week: 1) == Tempo.from_iso8601!("2026Y2W", ISOWeek)
      assert Tempo.shift(year, day: 1) == Tempo.from_iso8601!("2026Y1W2K", ISOWeek)
      assert Tempo.shift(year, day: -1) == Tempo.from_iso8601!("2025Y52W7K", ISOWeek)

      assert Tempo.exactly?(year, ~o"P53W")
      assert Tempo.exactly?(year, ~o"P371D")
      assert Tempo.at_least?(year, ~o"P1D")
    end

    test "has the day of the week as its day, to truncate, round or extend to", %{year: year} do
      moment = Tempo.from_iso8601!("2026Y25W3KT10H30M", ISOWeek)
      day = Tempo.from_iso8601!("2026Y25W3K", ISOWeek)

      assert Tempo.trunc(moment) == day
      assert Tempo.trunc(moment, :day) == day
      assert Tempo.round(moment, :day) == day
      assert Tempo.at_resolution(moment, :day) == day
      assert Tempo.extend_resolution(year, :day) == Tempo.from_iso8601!("2026Y1W1K", ISOWeek)
    end

    test "a Gregorian week extends to its first day too" do
      assert Tempo.extend_resolution(~o"2026-W25", :day) ==
               Tempo.extend_resolution(~o"2026-W25", :day_of_week)
    end
  end

  describe "duration/1 of a set" do
    # A set written as its members was refused as no Tempo value, where the
    # same set written in one value was measured.
    test "written as its members is that of the set written in one value" do
      assert Tempo.duration(~o"{2026Y,2030Y}") == Tempo.duration(~o"{2026,2030}Y")
      assert Tempo.duration(~o"{2026-06-15,2026-07-01}") == ~o"P2D"
      assert Tempo.duration(~o"{2020Y..2022Y}") == ~o"P3Y"
    end

    test "of one of several is the conversion's error" do
      assert {:error, %ConversionError{reason: :one_of_set}} = Tempo.duration(~o"[2026,2027]")
    end
  end

  describe "significant digits" do
    # Every digit significant is the value itself, which the walk yielded
    # and the conversion refused.
    test "that cover every digit are the value" do
      assert Tempo.to_interval(~o"1950S4") == Tempo.to_interval(~o"1950")
      assert Tempo.to_interval(~o"1950S5") == Tempo.to_interval(~o"1950")
      assert Enum.take(~o"1950S4", 2) == Enum.take(~o"1950", 2)
      assert Tempo.duration(~o"1950S4") == ~o"P1Y"
    end

    # ISO 8601-2 §4.4.3: the count is a positive integer.
    test "of none are not a value" do
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("1950S0")
    end
  end

  defp relations_of_every_pair(a, b) do
    {:ok, a_set} = Tempo.to_interval(a)
    {:ok, b_set} = Tempo.to_interval(b)

    for one <- IntervalSet.members(a_set), other <- IntervalSet.members(b_set), uniq: true do
      Tempo.relation(one, other)
    end
  end

  defp certainty([only], only), do: :certain

  defp certainty(relations, relation),
    do: if(relation in relations, do: :possible, else: :impossible)
end
