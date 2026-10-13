defmodule Tempo.ShiftTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ConversionError

  # Shifting: one arithmetic over values, spans, sets and masks, with and
  # without a year, and through free time (`plans/architecture-redesign.md`,
  # section 7.5 and section 17).

  defp shifted(value, by), do: Tempo.shift(value, by) |> ok()
  defp ok({:ok, value}), do: value

  describe "a value" do
    test "is moved at its resolution, extended to the duration's finest unit" do
      assert shifted(~o"2026-06-15", day: 1) == ~o"2026-06-16"
      assert shifted(~o"2026", day: 1) == ~o"2026-01-02"
      assert shifted(~o"2026", hour: 1) == ~o"2026-01-01T01"
      assert shifted(~o"2026-06-15T10:30", hour: 1) == ~o"2026-06-15T11:30"
    end

    test "counts years and months through the calendar, with the day clamped" do
      assert shifted(~o"2026-01-31", month: 1) == ~o"2026-02-28"
      assert shifted(~o"2024-02-29", year: 1) == ~o"2025-02-28"
      assert shifted(~o"2026-06-15T10:30", month: 1) == ~o"2026-07-15T10:30"
    end

    test "stays on its own axis" do
      assert shifted(~o"2026-W25", day: 1) == ~o"2026Y25W2K"
      assert shifted(~o"2026Y25W3K", day: 1) == ~o"2026Y25W4K"
      assert shifted(~o"2026Y25W7K", day: 1) == ~o"2026Y26W1K"
      assert shifted(~o"2026Y100O", day: 1) == ~o"2026Y101O"
      assert shifted(~o"2026Y-1M15D", day: 1) == ~o"2026Y12M16D"
    end

    test "moves the clock as elapsed time in its zone" do
      assert shifted(~o"2026-03-29T01:30[Europe/Paris]", hour: 1) ==
               ~o"2026-03-29T03:30[Europe/Paris]"

      assert shifted(~o"2026-03-28T10:00[Europe/Paris]", day: 1) ==
               ~o"2026-03-29T10:00[Europe/Paris]"

      assert shifted(~o"2026-06-15T10Z", hour: 1) == ~o"2026-06-15T11Z"
    end

    test "carries its annotations and qualifications" do
      assert shifted(~o"2018±2Y6M15D", day: 1) == ~o"2018±2Y6M16D"
      assert shifted(~o"1950S2Y6M", month: 1) == ~o"1950S2Y7M"
      assert shifted(~o"2026Y6~M15DT10H", day: 1) == ~o"2026Y6~M16DT10H"
    end

    test "is shifted by a duration, its text or its units alike" do
      by_units = shifted(~o"2026-06-15T10:30", day: 1)
      assert shifted(~o"2026-06-15T10:30", ~o"P1D") == by_units
      assert shifted(~o"2026-06-15T10:30", "P1D") == by_units
    end

    test "ending in a group is not counted from" do
      assert {:error, %ConversionError{reason: :group}} = Tempo.shift(~o"2026Y2G3MU", day: 1)
    end
  end

  describe "a value with no year" do
    test "is shifted when every year agrees" do
      assert shifted(~o"1M31D", day: 1) == ~o"2M1D"
      assert shifted(~o"6M", day: 1) == ~o"6M2D"
      assert shifted(~o"15D", day: 1) == ~o"16D"
      assert shifted(~o"1M31D", year: 1) == ~o"1M31D"
      assert shifted(~o"T23:00", hour: 2) == ~o"T01:00"
      assert shifted(~o"T10", minute: 30) == ~o"T10:30"
      assert shifted(~o"7K", day: 1) == ~o"1K"
      assert shifted(~o"X*Y6M15D", day: 1) == ~o"X*Y6M16D"
    end

    test "is an error when the answer depends on the year" do
      assert {:error, %ConversionError{reason: :needs_a_year}} = Tempo.shift(~o"1M31D", month: 1)
      assert {:error, %ConversionError{reason: :needs_a_year}} = Tempo.shift(~o"2M28D", day: 1)
    end
  end

  describe "a value that names several" do
    test "is one value where its units hold them all" do
      assert shifted(~o"2026Y6M{1,15}D", day: 1) == ~o"2026Y6M{2,16}D"
      assert shifted(~o"2026Y6M{1..5}D", day: 1) == ~o"2026Y6M{2..6}D"
      assert shifted(~o"2026Y{6,7}M15D", month: 1) == ~o"2026Y{7,8}M15D"
      assert shifted(~o"2026Y{6,7}M", month: 1) == ~o"2026Y{7,8}M"
      assert shifted(~o"{2026,2027}Y", year: 1) == ~o"{2027,2028}Y"
      assert shifted(~o"{2026,2027}Y12M31D", day: 1) == ~o"{2027,2028}Y1M1D"
      assert shifted(~o"2026Y{6,7}M{1,15}D", day: 1) == ~o"2026Y{6,7}M{2,16}D"
      assert shifted(~o"2026Y6M15DT{9,17}H", hour: 1) == ~o"2026Y6M15DT{10,18}H"
      assert shifted(~o"2026Y{6,7}M30D", day: 1) == ~o"2026Y7M{1,31}D"
      assert shifted(~o"2026Y{1..-1}M15DT10HZ", day: 1) == ~o"2026Y{1..-1}M16DT10HZ"
    end

    test "is one value once where several land on it" do
      assert shifted(~o"2026Y1M{28..31}D", month: 1) == ~o"2026Y2M28D"
      assert shifted(~o"2024Y2M{28,29}D", year: 1) == ~o"2025Y2M28D"
    end

    test "is a set of the values where no one value holds them" do
      assert shifted(~o"2026Y6M{15,30}D", day: 1) == ~o"{2026-06-16,2026-07-01}"
      assert shifted(~o"2026Y{11,12}M", month: 1) == ~o"{2026-12,2027-01}"
    end

    test "carries a margin of error and significant digits" do
      assert shifted(~o"2018±2Y6M{1,15}D", day: 1) == ~o"2018±2Y6M{2,16}D"
      assert shifted(~o"2018±2Y6M{1,15}D", month: 1) == ~o"2018±2Y7M{1,15}D"
      assert shifted(~o"1950S2Y6M{1,15}D", day: 1) == ~o"1950S2Y6M{2,16}D"
    end
  end

  describe "a mask" do
    test "stays where the shift passes it by" do
      assert shifted(~o"2026Y6MX*D", hour: 1) == ~o"2026Y6MX*DT1H"
      assert shifted(~o"2026Y6M1XD", hour: 1) == ~o"2026Y6M1XDT1H"
      assert shifted(~o"2026YXXM", day: 1) == ~o"2026YXXM2D"
      assert shifted(~o"2026YXXM15D", day: 1) == ~o"2026YXXM16D"
      assert shifted(~o"202XY", month: 1) == ~o"202XY2M"
      assert shifted(~o"202XY6M15D", day: 1) == ~o"202XY6M16D"
      assert shifted(~o"2026Y6M15DTX*H", minute: 1) == ~o"2026Y6M15DTX*H1M"
      assert shifted(~o"2026Y25WX*K", hour: 1) == ~o"2026Y25WX*KT1H"
    end

    test "is one of the values it lands on where the shift carries it" do
      assert shifted(~o"2026Y6M1XD", day: 1) == ~o"[2026Y6M11D..2026Y6M20D]"
      assert shifted(~o"202XY", year: 1) == ~o"[2021Y..2030Y]"
      assert shifted(~o"2026Y2XW", week: 1) == ~o"[2026Y21W..2026Y30W]"
      assert %Tempo{form: {:one, members}} = shifted(~o"2026Y6MX*D", day: 1)
      assert Enum.count(members) == 30
    end
  end

  describe "a span" do
    test "has both its ends moved" do
      assert shifted(~o"2026-01/2026-03", month: 1) == ~o"2026-02/2026-04"
      assert shifted(~o"2026/2028", year: -1) == ~o"2025/2027"
      assert shifted(~o"2026-06-15T10/2026-06-16", day: 2) == ~o"2026-06-17T10/2026-06-18"

      assert shifted(~o"2026-06-15T10:30/2026-06-15T12:45", day: 1) ==
               ~o"2026-06-16T10:30/2026-06-16T12:45"
    end

    test "keeps its length in days a month or a year on" do
      assert shifted(~o"2026-01-29/2026-01-31", month: 1) == ~o"2026-02-28/2026-03-02"
    end

    test "keeps a duration end, an open end and a count" do
      assert shifted(~o"2026-06-01/P1M", month: 1) == ~o"2026-07-01/P1M"
      assert shifted(~o"P1M/2026-07-01", day: 1) == ~o"P1M/2026-07-02"
      assert shifted(~o"2026-06-01/..", day: 1) == ~o"2026-06-02/.."
      assert shifted(~o"../2026-06-01", day: 1) == ~o"../2026-06-02"
      assert shifted(~o"R3/2026-06-01/P1D", day: 1) == ~o"R3/2026-06-02/P1D"
    end

    test "and a set are moved member by member" do
      assert shifted(~o"{2026-01,2026-03}", month: 1) == ~o"{2026-02,2026-04}"
    end
  end

  describe "skipping a busy set" do
    @meeting ~o"2026-06-15T10:00/2026-06-15T11:00"

    test "a clear path is a plain shift" do
      assert shifted(~o"2026-06-15T07:00", hour: 1, skipping: @meeting) == ~o"2026-06-15T08:00"
    end

    test "a busy span in the path costs nothing to cross" do
      assert shifted(~o"2026-06-15T09:30", hour: 1, skipping: @meeting) == ~o"2026-06-15T11:30"
    end

    test "consuming exactly the free run lands on the busy start" do
      assert shifted(~o"2026-06-15T09:00", hour: 1, skipping: @meeting) == ~o"2026-06-15T10:00"
    end

    test "an origin inside a busy span first moves to its end" do
      assert shifted(~o"2026-06-15T10:30", minute: 30, skipping: @meeting) == ~o"2026-06-15T11:30"

      assert shifted(~o"2026-06-15T10:30", second: 0, skipping: @meeting) ==
               ~o"2026-06-15T11:00:00"
    end

    test "the exclusive end of a busy span is free" do
      assert shifted(~o"2026-06-15T11:00", minute: 15, skipping: @meeting) == ~o"2026-06-15T11:15"
    end

    test "a negative duration walks backward through free time" do
      assert shifted(~o"2026-06-15T11:30", hour: -1, skipping: @meeting) == ~o"2026-06-15T09:30"

      assert shifted(~o"2026-06-15T10:30", minute: -15, skipping: @meeting) ==
               ~o"2026-06-15T09:45"

      arrived = shifted(~o"2026-06-15T09:30", hour: 1, skipping: @meeting)
      assert shifted(arrived, hour: -1, skipping: @meeting) == ~o"2026-06-15T09:30"
    end

    test "a day of free time jumps whole busy days" do
      busy_days = [~o"2026-06-16", ~o"2026-06-17"]
      assert shifted(~o"2026-06-15T20:00", day: 1, skipping: busy_days) == ~o"2026-06-18T20:00"
    end

    test "a date steps from free day to free day" do
      weekend = ~o"{2026-06-13,2026-06-14,2026-06-15}"
      assert shifted(~o"2026-06-12", day: 1, skipping: weekend) == ~o"2026-06-16"
      assert shifted(~o"2026-06-12", week: 1, skipping: weekend) == ~o"2026-06-22"
    end

    test "a bounded recurrence is a busy set" do
      busy = ~o"R2/2026-01-04T23:00/PT1H"
      assert shifted(~o"2026-01-04T22:00", hour: 4, skipping: busy) == ~o"2026-01-05T04:00"
    end

    test "a month or a year of free time has no fixed length" do
      assert {:error, %ConversionError{reason: {:inexact, :month}}} =
               Tempo.shift(~o"2026-06-15T09:30", month: 1, skipping: @meeting)
    end
  end

  describe "trunc, round, extend, at_resolution and split" do
    test "truncate to a unit the value is written in or lies within" do
      assert Tempo.trunc(~o"2022-11-21T09:30:00", :year) == {:ok, ~o"2022"}
      assert Tempo.trunc(~o"2026Y25W3K", :month) == {:ok, ~o"2026-06"}
      assert Tempo.trunc(~o"2026", :month) == {:ok, ~o"2026"}
      assert Tempo.trunc(~o"6M15D", :month) == {:ok, ~o"6M"}

      assert Tempo.trunc(~o"2026-06-15T10/2026-06-15T17", :day) ==
               {:ok, ~o"2026-06-15/2026-06-15"}

      assert {:error, %ConversionError{reason: :needs_a_year}} = Tempo.trunc(~o"6M15D", :week)
    end

    test "round to the nearer period" do
      assert Tempo.round(~o"2022-11-21T09:30:00") == {:ok, ~o"2022-11-21"}
      assert Tempo.round(~o"2022-11-21", :year) == {:ok, ~o"2023"}
      assert Tempo.round(~o"2026-01-16", :month) == {:ok, ~o"2026-01"}
      assert Tempo.round(~o"2026-08-16T10:00:00", :week) == {:ok, ~o"2026-W34"}

      assert {:error, %ConversionError{reason: {:finer_than_written, :day}}} =
               Tempo.round(~o"2026", :day)

      assert {:error, %ConversionError{reason: :several}} = Tempo.round(~o"2026Y6MXD", :month)
    end

    test "extend to the next unit, or down to one" do
      assert Tempo.extend(~o"2026-W25") == {:ok, ~o"2026Y25W{1..7}K"}
      assert Tempo.extend(~o"T10") == {:ok, ~o"T10H{0..59}M"}
      assert Tempo.extend(~o"2026-06-15", :hour) == {:ok, ~o"2026Y6M15DT{0..23}H"}

      assert {:error, %ConversionError{reason: :no_finer_unit}} =
               Tempo.extend(~o"2026-06-15T10:30:45")
    end

    test "split keeps what each part carries" do
      assert Tempo.split(~o"2026-06~-15") == {~o"2026-06~-15", nil}
      assert {:error, %ConversionError{}} = Tempo.split(~o"2026-06-15/2026-06-16")
    end
  end

  describe "a change of the clock" do
    test "the clock part of a duration is elapsed time, the date part the wall clock's" do
      noon = ~o"2024-03-09T12:00[America/New_York]"

      assert Tempo.shift(noon, ~o"P1D") == {:ok, ~o"2024-03-10T12:00[America/New_York]"}
      assert Tempo.shift(noon, ~o"PT24H") == {:ok, ~o"2024-03-10T13:00[America/New_York]"}
      assert Tempo.shift(noon, hour: 24) == {:ok, ~o"2024-03-10T13:00[America/New_York]"}
      assert Tempo.shift(noon, ~o"P1DT1H") == {:ok, ~o"2024-03-10T13:00[America/New_York]"}

      assert Tempo.shift(~o"2024-03-10T13:00[America/New_York]", ~o"-PT24H") == {:ok, noon}

      assert Tempo.shift(~o"2024-11-02T12:00[America/New_York]", ~o"PT24H") ==
               {:ok, ~o"2024-11-03T11:00[America/New_York]"}
    end

    test "a floating value has no change of the clock to cross" do
      assert Tempo.shift(~o"2024-03-09T12:00", ~o"PT24H") == {:ok, ~o"2024-03-10T12:00"}
    end
  end

  describe "a recurring interval (ISO 8601-1 3.1.1.11)" do
    test "its occurrences are consecutive across the end of a short month" do
      assert Tempo.to_interval(~o"R3/2026-01-31/P1M") ==
               {:ok, ~o"{2026-01-31/2026-02-27,2026-02-28/2026-03-30,2026-03-31/2026-04-29}"}

      assert Tempo.to_interval(~o"R3/2026-01-31T10/P1M") ==
               {:ok,
                ~o"{2026-01-31T10/2026-02-28T10,2026-02-28T10/2026-03-31T10,2026-03-31T10/2026-04-30T10}"}
    end

    test "counted back from its end" do
      assert Tempo.to_interval(~o"R3/P1M/2026-05-31") ==
               {:ok, ~o"{2026-03-01/2026-03-31,2026-04-01/2026-04-30,2026-05-01/2026-05-31}"}
    end

    test "each is a day long on the clock of a zone that changes" do
      assert Tempo.to_interval(~o"R2/2026-03-07T10/P1D[America/New_York]") ==
               {:ok,
                ~o"{2026-03-07T10/2026-03-08T10,2026-03-08T10/2026-03-09T10}[America/New_York]"}
    end
  end

  describe "a value with a gap or several groups" do
    test "is shifted member by member, and written as it was where that says the same" do
      assert Tempo.shift(~o"2026-06T17", month: 1) == {:ok, ~o"2026Y7M{1..30}DT17H"}
      assert Tempo.shift(~o"2026-07T17", month: 1) == {:ok, ~o"2026-08T17"}
      assert Tempo.shift(~o"2026-06T17", hour: 1) == {:ok, ~o"2026-06T18"}
      assert Tempo.shift(~o"2026YT17H", year: 1) == {:ok, ~o"2027YT17H"}

      assert {:ok, moved} = Tempo.shift(~o"2026-06T17", day: 1)
      assert {:ok, members} = Tempo.members(moved)
      assert Enum.count(members) == 30
      assert hd(members) == ~o"2026-06-02T17"
      assert List.last(members) == ~o"2026-07-01T17"
    end

    test "several groups are extended each, as a set" do
      assert Tempo.extend(~o"2026Y{1,2}G3MU") ==
               {:ok, %{~o"2026Y{1,2}G3MU" | form: {:all, [~o"2026Y{1..3}M", ~o"2026Y{4..6}M"]}}}

      assert {:error, %ConversionError{reason: :several}} = Tempo.extend(~o"{1,2}G3MU")
    end
  end
end
