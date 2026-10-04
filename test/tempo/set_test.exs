defmodule Tempo.SetTest do
  # A set's members: each is read as a value is, checked and in the calendar
  # the set is written for.
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Calendrical.ISOWeek
  alias Calendrical.NRF
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError

  # The calendar of every value a set holds: its members, the ends of its
  # ranges and of its interval members, and the members it excludes.
  defp calendars(%Tempo.Set{set: members, except: except}),
    do: Enum.flat_map(members ++ except, &calendars/1)

  defp calendars(%Tempo{calendar: calendar}), do: [calendar]
  defp calendars(%Tempo.Range{first: first, last: last}), do: calendars(first) ++ calendars(last)
  defp calendars(%Interval{from: from, to: to}), do: calendars(from) ++ calendars(to)
  defp calendars(_open_end), do: []

  defp gregorian_dates(set) do
    {:ok, days} = Tempo.to_interval(set)

    for day <- IntervalSet.members(days) do
      {:ok, date} = day |> Interval.from() |> Tempo.to_date()
      Date.convert!(date, Calendar.ISO)
    end
  end

  describe "a member is checked as a value is" do
    test "a date its calendar lacks is an error, wherever it is in the set" do
      for text <- [
            "{2026-02-30,2026-04-30}",
            "[2026-02-30,2026-04-30]",
            "{2026-13-01}",
            "{2026-W54-1}",
            "{2026-366}",
            "{2026-06-15T25:00}",
            "{2026-06-01..2026-06-31}",
            "[..2026-02-30]",
            "{2026-06-15,^2026-06-31}",
            "2026Y[6,7]M31D"
          ] do
        assert {:error, %InvalidDateError{}} = Tempo.from_iso8601(text), text
      end

      assert {:ok, %Tempo.Set{}} = Tempo.from_iso8601("2026Y[5,7]M31D")
    end

    test "an interval member is checked as an interval is" do
      assert {:error, %IntervalEndpointsError{}} = Tempo.from_iso8601("{2021Y/2020Y}")
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("{2026-02-30/2026-03-01}")

      # A zone on one end is the other end's too, as it is outside a set.
      {:ok, zoned} = Tempo.from_iso8601("{2026-06-15T10:00/2026-06-15T12:00[Europe/Paris]}")
      assert [%Interval{from: from, to: to}] = zoned.set
      assert {from.extended.zone_id, to.extended.zone_id} == {"Europe/Paris", "Europe/Paris"}

      # A critical zone holds its offset to it, and a wall time the zone skips
      # is an error, in a member the set excludes too.
      assert {:error, %Tempo.ZoneOffsetMismatchError{}} =
               Tempo.from_iso8601(
                 "{2022-01-01T00:00:00+05:00[!America/New_York]/2022-01-02T00:00:00+05:00}"
               )

      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.from_iso8601(
                 "{2024-03-09,^2024-03-10T02:30[America/New_York]/2024-03-10T05:00}"
               )
    end

    test "a member is resolved as a value is" do
      assert Tempo.from_iso8601!("{2026Y2M-1D}") == ~o"{2026Y2M28D}"
      assert Tempo.from_iso8601!("{2026-166}") == ~o"{2026Y6M15D}"
    end

    test "a recurrence's domain is checked too" do
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("R/{2026Y13M}/P1M/FL1DN")
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("R/{2026Y2M30D}/P1D")
    end
  end

  describe "a set written for another calendar" do
    test "holds its members, its ranges' ends and the members it excludes in that calendar" do
      text = "{5786-06-15,5786-07-01..5786-07-03,^5786-07-02}"

      for set <- [
            Tempo.from_iso8601!(text, Hebrew),
            Tempo.from_iso8601!(text <> "[u-ca=hebrew]"),
            Tempo.from_iso8601!("[5786-06-15,5786-07-01]", Hebrew),
            Tempo.from_iso8601!("5786Y[6,7]M15D", Hebrew)
          ] do
        assert Enum.uniq(calendars(set)) == [Hebrew]
      end
    end

    test "names the days that calendar gives its dates" do
      # 15 Adar 5786 is 4 March 2026, and 1 Nisan the 19th.
      assert gregorian_dates(Tempo.from_iso8601!("{5786-06-15,5786-07-01}", Hebrew)) ==
               [~D[2026-03-04], ~D[2026-03-19]]

      # Week 20 of the NRF year 2026 starts on Sunday 14 June.
      assert gregorian_dates(Tempo.from_iso8601!("{2026-W20-2}", NRF)) == [~D[2026-06-15]]
    end

    test "is checked against that calendar" do
      # 5786 has twelve months and 5787, a leap year, thirteen.
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("{5786-13-01}", Hebrew)
      assert {:ok, %Tempo.Set{}} = Tempo.from_iso8601("{5787-13-01}", Hebrew)
    end

    test "converts a whole date written with a month for a calendar of weeks" do
      set = Tempo.from_iso8601!("{2026-06-15,2026-06-16..2026-06-18}", ISOWeek)

      assert Enum.uniq(calendars(set)) == [ISOWeek]
      assert [%Tempo{time: [year: 2026, week: 25, day_of_week: 1]}, %Tempo.Range{}] = set.set

      assert {:error, %ConversionError{target: ISOWeek}} =
               Tempo.from_iso8601("{2026-06}", ISOWeek)
    end
  end

  describe "a set operation" do
    test "takes a set whose member is a range" do
      {:ok, rest} = Tempo.difference(~o"{2026-06-15..2026-06-20}", ~o"2026-06-15")
      assert IntervalSet.count(rest) == 5

      {:ok, shared} = Tempo.intersection(~o"{2026-06-15..2026-06-20}", ~o"2026-06-18")
      assert shared |> IntervalSet.members() |> Enum.map(&Interval.from/1) == [~o"2026-06-18"]
    end

    test "meets a set in another calendar on the days it names" do
      adar = Tempo.from_iso8601!("{5786-06-15..5786-06-20}", Hebrew)

      {:ok, shared} = Tempo.intersection(adar, ~o"2026-03-05")
      assert [%Interval{from: %Tempo{calendar: Hebrew, time: time}}] = IntervalSet.members(shared)
      assert time == [year: 5786, month: 6, day: 16]
    end
  end

  # A set's `[zone]` and `[key=value]` suffix was parsed and dropped, leaving
  # its members floating; a suffix inside the braces does not parse.
  describe "a zone suffix on a set" do
    test "is each member's, and written once after the set" do
      for text <- [
            "{2026Y6M15DT10H0M,2026Y6M16DT10H0M}[Europe/Paris]",
            "{2026Y6M15DT10H0M,2026Y6M16DT10H0M}[+09:00]",
            "{2026Y6M15DT10H0M,2026Y6M16DT10H0M}[Europe/Paris][foo=bar]",
            "[2026Y6M15DT10H0M,2026Y6M16DT10H0M][Europe/Paris]",
            "{2026Y6M15DT10H0M..2026Y6M15DT12H0M}[Europe/Paris]",
            "R/{2026Y6M15D,2026Y6M16D}/P1Y[Europe/Paris]"
          ] do
        value = Tempo.from_iso8601!(text)

        assert Tempo.to_iso8601!(value) == text
        assert Tempo.from_iso8601(text) == {:ok, value}
      end
    end

    test "puts its members in the zone" do
      {:ok, set} =
        Tempo.to_interval(
          Tempo.from_iso8601!("{2026-06-15T10:00,2026-06-16T10:00}[Europe/Paris]")
        )

      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) == [
               Tempo.from_iso8601!("2026-06-15T10:00[Europe/Paris]"),
               Tempo.from_iso8601!("2026-06-16T10:00[Europe/Paris]")
             ]
    end
  end

  # A qualification written after a set qualifies each member, and was
  # written back on each member inside the braces, which does not parse; a
  # range member lost it.
  describe "a qualified set" do
    test "is written with its qualification once after the set, and read again" do
      for text <- [
            "{2026Y6M15D,2026Y6M16D}?",
            "{2026Y6M15D,2026Y6M16D}~",
            "{2026Y6M15D,2026Y6M16D}%",
            "[2026Y6M15D,2026Y6M16D]?",
            "{2026Y6M15D,2026Y6M16D}?[Europe/Paris]",
            "{2026Y6M15D..2026Y6M18D}~",
            "{2020Y/2021Y,2023Y/2024Y}?",
            "[..1984Y]?"
          ] do
        value = Tempo.from_iso8601!(text)

        assert Tempo.to_iso8601!(value) == text
        assert Tempo.from_iso8601(text) == {:ok, value}
      end
    end

    test "qualifies each member, a range at both ends" do
      %Tempo.Set{set: [%Tempo.Range{first: first, last: last}]} =
        Tempo.from_iso8601!("{2026-06-15..2026-06-18}~")

      assert Tempo.qualification(first) == :approximate
      assert Tempo.qualification(last) == :approximate
    end
  end
end
