defmodule Tempo.SteppingTest do
  # A step counts from one whole number. A value that does not track the unit
  # a step carries into, or that holds several values at a unit a step would
  # count from, gives a value or an error, and never raises.
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.UnanchoredError

  defp span(value) do
    {:ok, %Interval{} = interval} = Tempo.to_interval(value)
    {Interval.from(interval), Interval.to(interval)}
  end

  defp spans(value) do
    {:ok, %IntervalSet{} = set} = Tempo.to_interval(value)
    set |> IntervalSet.members() |> Enum.map(&{Interval.from(&1), Interval.to(&1)})
  end

  describe "a day of the week that names no week" do
    test "spans to the next day of the week, and the last day to the first" do
      assert span(~o"7K") == {~o"7K", ~o"1K"}
      assert span(~o"7KT23H") == {~o"7KT23H", ~o"1KT0H"}
      assert spans(~o"{6,7}K") == [{~o"6K", ~o"7K"}, {~o"7K", ~o"1K"}]
    end

    test "steps by a day, and is the same day a week on" do
      assert Tempo.shift(~o"7K", day: 1) == ~o"1K"
      assert Tempo.shift(~o"1K", day: -1) == ~o"7K"
      assert Tempo.shift(~o"3K", day: 2) == ~o"5K"
      assert Tempo.shift(~o"7K", week: 1) == ~o"7K"
      assert Tempo.shift(~o"7KT23H", hour: 1) == ~o"1KT0H"
      assert Tempo.shift(~o"1KT0H", hour: -1) == ~o"7KT23H"
    end

    # The day of the week a month or a year on falls on depends on the date,
    # which a day of the week alone has none of; it was left as it was.
    test "has no day of the week a month or a year on" do
      for shift <- [[month: 1], [year: 1], [month: -1]] do
        assert {:error, %UnanchoredError{}} = Tempo.shift(~o"7K", shift)
      end

      assert {:error, %UnanchoredError{}} = Tempo.shift(~o"7KT10H", month: 1)
      assert {:error, %UnanchoredError{}} = Tempo.to_interval(Tempo.from_iso8601!("R3/7K/P1M"))
    end

    test "starts or ends the span a duration gives" do
      assert span(Tempo.from_iso8601!("7K/P1D")) == {~o"7K", ~o"1K"}
      assert span(Tempo.from_iso8601!("P1D/1K")) == {~o"7K", ~o"1K"}
    end

    test "is explained, and has no date to be written as" do
      assert Tempo.explain(~o"7K") =~ "Sunday of any week"
      assert {:error, %UnanchoredError{}} = Tempo.to_string(~o"7K")
    end
  end

  describe "a step back from a value with no year" do
    test "borrows from the unit above it" do
      assert Tempo.shift(~o"T0H", hour: -1) == ~o"T23H"
      assert Tempo.shift(~o"T0H0M", minute: -1) == ~o"T23H59M"
      assert Tempo.shift(~o"T0H0M0S", second: -1) == ~o"T23H59M59S"
      assert Tempo.shift(~o"25W", week: -1) == ~o"24W"
      assert Tempo.shift(~o"25W1K", day: -1) == ~o"24W7K"
    end

    test "is an error where the unit above depends on the year" do
      # The week before week 1 is the 52nd or the 53rd of the year before.
      assert {:error, %UnanchoredError{}} = Tempo.shift(~o"1W", week: -1)
      assert {:error, %UnanchoredError{}} = Tempo.shift(~o"1W1K", day: -1)
    end
  end

  # A Hebrew year has twelve months or thirteen, and its thirteenth has 29
  # days in every year that has one.
  describe "the last month a year can have, with no year" do
    defp hebrew(text), do: Tempo.from_iso8601!(text, Hebrew)

    test "is followed by the first month, as it is in every year that has it" do
      assert span(hebrew("13M")) == {hebrew("13M"), hebrew("1M")}
      assert span(hebrew("13M29D")) == {hebrew("13M29D"), hebrew("1M1D")}
      assert Tempo.shift(hebrew("13M"), month: 1) == hebrew("1M")
      assert Tempo.shift(hebrew("13M15D"), month: 1) == hebrew("1M15D")
      assert Tempo.shift(hebrew("13M29D"), day: 1) == hebrew("1M1D")
      assert Tempo.shift(hebrew("13M28D"), week: 1) == hebrew("1M6D")
    end

    test "is what each year that has a thirteenth month gives" do
      leap_years = Enum.filter(5770..5830, &(Hebrew.months_in_year(&1) == 13))
      assert length(leap_years) > 20

      for year <- leap_years do
        last_day = Date.new!(year, 13, 29, Hebrew)
        assert Date.add(last_day, 1) == Date.new!(year + 1, 1, 1, Hebrew)

        assert span(hebrew("#{year}Y13M")) == {hebrew("#{year}Y13M"), hebrew("#{year + 1}Y1M")}
      end
    end

    test "is spanned and walked alike" do
      assert Enum.count(hebrew("13M")) == 29
      assert Enum.to_list(hebrew("13M")) == Enum.map(1..29, &hebrew("13M#{&1}D"))
    end

    test "leaves the month only some years end on to the year" do
      # The twelfth month is followed by the thirteenth in a leap year and
      # by the first of the next year in any other.
      assert {:error, %UnanchoredError{}} = Tempo.to_interval(hebrew("12M"))
      assert {:error, %UnanchoredError{}} = Tempo.shift(hebrew("12M"), month: 1)
      assert Tempo.shift(hebrew("11M"), month: 1) == hebrew("12M")
    end

    test "is not stepped back to from the first month" do
      assert {:error, %UnanchoredError{}} = Tempo.shift(hebrew("1M"), month: -1)
    end
  end

  describe "a unit that holds several values" do
    test "is not counted from, and its set is never collapsed" do
      for {value, shift} <- [
            {~o"2026Y6M{1,15}D", [day: 1]},
            {~o"2026Y6M{1,15}D", [day: -1]},
            {~o"2026Y{6,7}M15D", [month: 1]},
            {~o"2026Y{6,7}M", [month: -1]},
            {~o"{2026,2027}Y", [year: 1]},
            {~o"2026Y6M15DT{9,17}H", [hour: 1]},
            {~o"2026Y6M15DT{9,17}H", [hour: -1]},
            {~o"2026Y25W{6,7}K"W, [day: 1]},
            {~o"2026Y6M3G4DU", [day: 1]},
            {~o"2026Y3G4MU", [month: 1]}
          ] do
        assert {:error, %ConversionError{value: ^value, reason: :grouped_component} = error} =
                 Tempo.shift(value, shift),
               "#{inspect(value)} by #{inspect(shift)}"

        assert Exception.message(error) =~ "holds several values"
      end
    end

    test "is passed by where every value it names steps alike" do
      assert Tempo.shift(~o"2026Y{6,7}M15D", day: 1) == ~o"2026Y{6,7}M16D"
      assert Tempo.shift(~o"2026Y{6,7}M15D", day: -1) == ~o"2026Y{6,7}M14D"
      assert Tempo.shift(~o"2026Y{6,7}M15D", year: 1) == ~o"2027Y{6,7}M15D"

      # The day after the 30th is not the same day in June and in July, nor
      # the day before the 1st.
      assert {:error, %ConversionError{reason: :grouped_component}} =
               Tempo.shift(~o"2026Y{6,7}M30D", day: 1)

      assert {:error, %ConversionError{reason: :grouped_component}} =
               Tempo.shift(~o"2026Y{6,7}M1D", day: -1)
    end

    test "keeps its days a month on only where the month has them all" do
      assert Tempo.shift(~o"2026Y6M{1,15}D", month: 1) == ~o"2026Y7M{1,15}D"

      # February has no 30th or 31st, and each day would be clamped to its own.
      assert {:error, %ConversionError{reason: :grouped_component}} =
               Tempo.shift(~o"2026Y1M{30,31}D", month: 1)
    end

    test "has no one year to carry into" do
      assert Tempo.shift(~o"{2026,2027}Y6M15D", day: 1) == ~o"{2026,2027}Y6M16D"

      assert {:error, %ConversionError{reason: :grouped_component}} =
               Tempo.shift(~o"{2026,2027}Y12M31D", day: 1)
    end
  end

  describe "a value no step can count from" do
    test "has no span, and to_interval/2 returns why" do
      # A count from the end with no year cannot be counted until the value
      # is placed on one.
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.to_interval(Tempo.from_iso8601!("-1D"))
    end

    test "is shifted where the step passes the unit by" do
      assert Tempo.shift(Tempo.from_iso8601!("2026Y{1,2}G3MU15D"), day: 1) ==
               Tempo.from_iso8601!("2026Y{1,2}G3MU16D")

      # A year on, the 15th is in whichever month the mask stands for.
      assert Tempo.shift(~o"2026YXXM15D", year: 1) == ~o"2027YXXM15D"
    end
  end

  describe "an end a duration cannot be counted to" do
    test "is the interval's error, not its end" do
      for {text, error} <- [
            {"2M28D/P1D", UnanchoredError},
            {"P1D/3M1D", UnanchoredError},
            {"2026Y6M{1,15}D/P1D", ConversionError}
          ] do
        assert {:error, %^error{}} = Tempo.to_interval(Tempo.from_iso8601!(text)), text
      end
    end

    # A start that names a span is the point the span starts at, as it is in
    # an interval written with two ends, and the duration is counted from it.
    # The mask could not be stepped, and the interval was refused.
    test "is counted from the point a start that names one span starts at" do
      assert Tempo.to_interval(Tempo.from_iso8601!("202XY/P1D")) == {:ok, ~o"2020Y/2020Y1M2D"}
      assert Tempo.to_interval(Tempo.from_iso8601!("202XY/P1Y")) == {:ok, ~o"2020Y/2021Y"}

      # A day of the year is no month to add a month to: the span was empty.
      assert Tempo.to_interval(Tempo.from_iso8601!("2026YXXO/P1M")) ==
               {:ok, ~o"2026Y1M1D/2026Y2M1D"}

      assert Tempo.to_interval(Tempo.from_iso8601!("P1M/2026YXXO")) ==
               {:ok, ~o"2025Y12M1D/2026Y1M1D"}
    end

    test "ends a recurrence's walk with the step it could not take" do
      for {text, error} <- [
            # The second month after 31 December is a 31 February.
            {"R3/12M31D/P1M", UnanchoredError},
            # The second occurrence would end the day after 28 February.
            {"R2/2M27D/P1D", UnanchoredError}
          ] do
        assert {:error, %^error{}} = Tempo.to_interval(Tempo.from_iso8601!(text)), text
      end

      # A walk that has its occurrences before such a step never meets it:
      # the day after the 28th depends on the month, and the 28th ends the third.
      assert spans(Tempo.from_iso8601!("R3/25D/P1D")) ==
               [{~o"25D", ~o"26D"}, {~o"26D", ~o"27D"}, {~o"27D", ~o"28D"}]
    end

    test "is raised by an enumeration, which has no error to return" do
      days = Tempo.from_iso8601!("2026Y6M{1,15}D/2026Y7M1D")

      assert_raise ConversionError, ~r/holds several values/, fn -> Enum.take(days, 3) end
    end
  end

  # The floor at a recurrence's start dropped an occurrence that came round
  # past the end of the axis, so the walk went round again and repeated the
  # first; a cadence of a whole turn gave occurrences of no length.
  describe "a recurrence with no year that wraps its axis" do
    test "goes on round the axis" do
      assert spans(Tempo.from_iso8601!("R3/T22H/PT1H")) ==
               [{~o"T0H", ~o"T1H"}, {~o"T22H", ~o"T23H"}, {~o"T23H", ~o"T0H"}]

      assert spans(Tempo.from_iso8601!("R3/6K/P1D")) ==
               [{~o"1K", ~o"2K"}, {~o"6K", ~o"7K"}, {~o"7K", ~o"1K"}]

      assert spans(Tempo.from_iso8601!("R3/6K/P2D")) ==
               [{~o"1K", ~o"3K"}, {~o"3K", ~o"5K"}, {~o"6K", ~o"1K"}]

      assert spans(Tempo.from_iso8601!("R3/11M/P1M")) ==
               [{~o"1M", ~o"2M"}, {~o"11M", ~o"12M"}, {~o"12M", ~o"1M"}]

      assert spans(Tempo.from_iso8601!("R3/12M30D/P1D")) ==
               [{~o"1M1D", ~o"1M2D"}, {~o"12M30D", ~o"12M31D"}, {~o"12M31D", ~o"1M1D"}]
    end

    test "a cadence of a whole turn is an error" do
      for text <- ["R3/7K/P1W", "R3/T22H/P1D", "R3/12M31D/P1Y", "R3/6K/P7D"] do
        assert {:error, %ConversionError{} = error} = Tempo.to_interval(Tempo.from_iso8601!(text))
        assert Exception.message(error) =~ "whole turn", text
      end
    end

    test "a start with a year is floored as before" do
      assert spans(Tempo.from_iso8601!("R3/2026-06-15T22/PT1H")) == [
               {~o"2026-06-15T22", ~o"2026-06-15T23"},
               {~o"2026-06-15T23", ~o"2026-06-16T00"},
               {~o"2026-06-16T00", ~o"2026-06-16T01"}
             ]
    end
  end

  # A recurrence from a start that holds a set stepped the set as one value,
  # so each occurrence's ends held it, or refused a step its values could not
  # all take alike.
  describe "a recurrence from a start that holds a set" do
    test "is a recurrence from each of its values" do
      assert spans(Tempo.from_iso8601!("R3/2026Y6M{1,15}D/P1M")) == [
               {~o"2026-06-01", ~o"2026-07-01"},
               {~o"2026-06-15", ~o"2026-07-15"},
               {~o"2026-07-01", ~o"2026-08-01"},
               {~o"2026-07-15", ~o"2026-08-15"},
               {~o"2026-08-01", ~o"2026-09-01"},
               {~o"2026-08-15", ~o"2026-09-15"}
             ]

      assert length(spans(Tempo.from_iso8601!("R2/2026Y6M{1..3}D/P1W"))) == 6
      assert length(spans(Tempo.from_iso8601!("R3/2026Y{6,7}M15D/P1Y"))) == 6
    end

    test "steps each value as far as its own month lets it" do
      assert spans(Tempo.from_iso8601!("R2/2026Y12M{30,31}D/P1M")) == [
               {~o"2026-12-30", ~o"2027-01-30"},
               {~o"2026-12-31", ~o"2027-01-31"},
               {~o"2027-01-30", ~o"2027-02-28"},
               {~o"2027-01-31", ~o"2027-02-28"}
             ]
    end

    test "within a window" do
      {:ok, set} =
        Tempo.to_interval(Tempo.from_iso8601!("R/2026Y6M{1,15}D/P1M"),
          within: ~o"2026-06/2026-08"
        )

      assert IntervalSet.count(set) == 4
    end

    test "a start that holds a mask is still one start: the point its span starts at" do
      assert spans(Tempo.from_iso8601!("R3/202XY/P1Y")) ==
               [{~o"2020Y", ~o"2021Y"}, {~o"2021Y", ~o"2022Y"}, {~o"2022Y", ~o"2023Y"}]
    end

    test "a start that holds a group of a set is no one start" do
      assert {:error, %ConversionError{reason: :grouped_component}} =
               Tempo.to_interval(Tempo.from_iso8601!("R3/2026Y{1,2}G3MU15D/P1D"))
    end
  end

  # A recurrence whose start has no year walked on its own axis and was
  # compared with a dated window, so it gave nothing in one.
  describe "a recurrence with no year in a dated window" do
    defp starts_within(text, window) do
      {:ok, set} =
        Tempo.to_interval(Tempo.from_iso8601!(text), within: Tempo.from_iso8601!(window))

      set |> IntervalSet.members() |> Enum.map(&Interval.from/1)
    end

    test "starts on the window's day, month or year" do
      assert starts_within("R/T22H/PT1H", "2026-06-15/2026-06-16") ==
               [~o"2026-06-15T22", ~o"2026-06-15T23"]

      assert starts_within("R3/T22H/PT1H", "2026-06-15/2026-06-16") ==
               [~o"2026-06-15T22", ~o"2026-06-15T23"]

      assert starts_within("R/T09H/P1D", "2026-06-15/2026-06-18") ==
               [~o"2026-06-15T09", ~o"2026-06-16T09", ~o"2026-06-17T09"]

      assert starts_within("R/12M31D/P1D", "2026") == [~o"2026-12-31"]
      assert starts_within("R/15D/P1M", "2026-06/2026-08") == [~o"2026-06-15", ~o"2026-07-15"]
    end

    test "a day of the week starts on the first one in the window" do
      assert starts_within("R/6K/P1W", "2026-06/2026-07") ==
               [~o"2026-06-06", ~o"2026-06-13", ~o"2026-06-20", ~o"2026-06-27"]

      assert hd(starts_within("R/6KT10H/P1W", "2026-06/2026-07")) == ~o"2026-06-06T10"
    end

    test "a window with no year is the start's own axis" do
      assert starts_within("R/T22H/PT1H", "T20H/T23H") == [~o"T22H"]
    end
  end

  # An unspecified unit (`X*`) was stepped as its last value, so a day after
  # any day of June was 1 July, and a step back was refused.
  describe "a shift that reaches an unspecified unit" do
    test "moves the block of values the unit stands for" do
      assert Tempo.shift(~o"2026Y6MX*D", day: 1) == Tempo.from_iso8601!("[2026Y6M2D..2026Y7M1D]")

      assert Tempo.shift(~o"2026Y6MX*D", day: -1) ==
               Tempo.from_iso8601!("[2026Y5M31D..2026Y6M29D]")

      assert Tempo.shift(~o"2026Y6M15DTX*H", hour: 1) ==
               Tempo.from_iso8601!("[2026Y6M15DT1H..2026Y6M16DT0H]")
    end

    test "under a concrete unit after it is the span of each value" do
      assert %IntervalSet{} = set = Tempo.shift(~o"2026YX*M15D", month: 1)

      starts = set |> IntervalSet.members() |> Enum.map(&Interval.from/1)
      assert length(starts) == 12
      assert hd(starts) == ~o"2026-02-15"
      assert List.last(starts) == ~o"2027-01-15"
    end

    test "a shift coarser than the unit keeps it unspecified" do
      assert Tempo.shift(~o"2026Y6MX*D", month: 1) == ~o"2026Y7MX*D"
    end
  end
end
