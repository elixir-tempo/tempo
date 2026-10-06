defmodule Tempo.BesideAGapTest do
  @moduledoc """
  Values beside a reading their zone's clock skips.

  A value written on a reading the clock skips the whole of is refused when
  it is read: the hour a spring-forward skips, a minute inside it, a day a
  zone leaves out. An operation that gives one gives a value no one could
  have written, and several did: a set or unspecified digits that name one
  among others converted to a span that starts on it, a value extended to a
  finer unit started on it, a step of days from a week landed on it, and the
  first hour `Enum.at/2` gave of a day was it.

  `Tempo.BesideAGap` gives values beside five gaps (New York, Paris, Lord
  Howe Island, Cairo and Samoa) to every operation that makes values, some
  three thousand cells, and holds each value given to being written and
  read as itself. The worked examples here hold the answers themselves,
  each against Elixir's own `DateTime`.

  One class of cell is left to a decision and listed: a time of day the
  clock skips, selected on a day that has the gap.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.BesideAGap
  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet

  setup_all do
    {:ok, harvest: BesideAGap.harvest()}
  end

  defp found(%{findings: findings}, property) do
    for {^property, operation, text, detail} <- findings, do: {operation, text, detail}
  end

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  # The moment a value starts at, and the moment Elixir places a reading of
  # the wall clock at, each as seconds since 1970.
  defp moment(%Tempo{} = value), do: Compare.to_utc_seconds(value) - @unix_epoch

  defp moment(%NaiveDateTime{} = reading, zone),
    do: reading |> DateTime.from_naive!(zone) |> DateTime.to_unix()

  # The reading the clock shows at the moment it skips one.
  defp shown_instead(%NaiveDateTime{} = skipped, zone) do
    {:gap, _just_before, shown} = DateTime.from_naive(skipped, zone)
    DateTime.to_naive(shown)
  end

  defp spans(value) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{} = span} -> [bounds(span)]
      {:ok, %IntervalSet{} = set} -> set |> IntervalSet.members() |> Enum.map(&bounds/1)
    end
  end

  defp bounds(%Interval{} = span), do: {moment(Interval.from(span)), moment(Interval.to(span))}

  describe "a set in a unit that names a reading the clock skips" do
    test "names the hours the clock shows, the one before the gap ending after it" do
      zone = "America/New_York"
      assert {:gap, _before, _after} = DateTime.from_naive(~N[2024-03-10 02:00:00], zone)

      assert spans(~o"2024-03-10T{01,02,03}[America/New_York]") == [
               {moment(~N[2024-03-10 01:00:00], zone), moment(~N[2024-03-10 03:00:00], zone)},
               {moment(~N[2024-03-10 03:00:00], zone), moment(~N[2024-03-10 04:00:00], zone)}
             ]
    end

    test "names the days the zone has" do
      zone = "Pacific/Apia"
      assert {:gap, _before, _after} = DateTime.from_naive(~N[2011-12-30 12:00:00], zone)

      assert spans(~o"2011-12-{29,30}[Pacific/Apia]") == [
               {moment(~N[2011-12-29 00:00:00], zone), moment(~N[2011-12-31 00:00:00], zone)}
             ]
    end

    test "is refused where the reading is the only one it names" do
      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.from_iso8601("2024-03-10T{02}[America/New_York]")
    end
  end

  describe "unspecified digits that stand for a day the zone leaves out" do
    test "stand for the days it has" do
      zone = "Pacific/Apia"

      # The thirties of December 2011 in Samoa are the 31st alone.
      assert spans(~o"2011-12-3X[Pacific/Apia]") == [
               {moment(~N[2011-12-31 00:00:00], zone), moment(~N[2012-01-01 00:00:00], zone)}
             ]

      # The span starts on the 31st, where it started on the 30th, the same
      # moment written as a day no value is read from.
      {:ok, span} = Tempo.to_interval(~o"2011-12-3X[Pacific/Apia]")
      assert Interval.from(span) == ~o"2011Y12M31D[Pacific/Apia]"

      assert Enum.to_list(~o"2011-12-3X[Pacific/Apia]") == [~o"2011Y12M31D[Pacific/Apia]"]
    end
  end

  describe "a value extended to a finer unit" do
    test "starts on the reading the clock shows where it skips the first" do
      assert %NaiveDateTime{hour: 1, minute: 0} =
               shown_instead(~N[2023-04-28 00:00:00], "Africa/Cairo")

      assert Tempo.extend_resolution(~o"2023-04-28[Africa/Cairo]", :hour) ==
               ~o"2023Y4M28DT1H[Africa/Cairo]"

      assert Tempo.extend_resolution(~o"2023-04-28[Africa/Cairo]", :minute) ==
               ~o"2023Y4M28DT1H0M[Africa/Cairo]"

      assert %NaiveDateTime{hour: 2, minute: 30} =
               shown_instead(~N[2026-10-04 02:00:00], "Australia/Lord_Howe")

      assert Tempo.extend_resolution(~o"2026-10-04T02[Australia/Lord_Howe]", :minute) ==
               ~o"2026Y10M4DT2H30M[Australia/Lord_Howe]"
    end

    test "starts where it did where the clock shows its first reading" do
      assert Tempo.extend_resolution(~o"2023-04-27[Africa/Cairo]", :hour) ==
               ~o"2023Y4M27DT0H[Africa/Cairo]"

      assert Tempo.extend_resolution(~o"2023-04-28", :hour) == ~o"2023Y4M28DT0H"
    end

    test "starts at the moment the value does" do
      for {coarse, unit} <- [
            {~o"2023-04-28[Africa/Cairo]", :hour},
            {~o"2023-04-28[Africa/Cairo]", :minute},
            {~o"2026-10-04T02[Australia/Lord_Howe]", :minute},
            {~o"2026-10-04T02[Australia/Lord_Howe]", :second}
          ] do
        extended = Tempo.extend_resolution(coarse, unit)
        assert {coarse, unit, moment(extended)} == {coarse, unit, moment(coarse)}
      end
    end
  end

  describe "a step of days or hours from a value coarser than a day" do
    test "passes over the day its zone leaves out" do
      # The Monday of the last week of 2011 was 26 December, and four days
      # on from it the 30th, which Samoa did not have.
      assert :calendar.iso_week_number({2011, 12, 26}) == {2011, 52}
      assert Date.add(~D[2011-12-26], 4) == ~D[2011-12-30]

      assert Tempo.shift(~o"2011Y52W[Pacific/Apia]", day: 4) == ~o"2011Y12M31D[Pacific/Apia]"
      assert Tempo.shift(~o"2011-12[Pacific/Apia]", day: 29) == ~o"2011Y12M31D[Pacific/Apia]"
      assert Tempo.shift(~o"2011[Pacific/Apia]", day: 363) == ~o"2011Y12M31D[Pacific/Apia]"

      # A step back lands on the day before it.
      assert Tempo.shift(~o"2012-01[Pacific/Apia]", day: -2) == ~o"2011Y12M29D[Pacific/Apia]"
    end

    test "lands on the reading the clock shows" do
      zone = "America/New_York"

      landed =
        ~N[2024-03-01 00:00:00] |> DateTime.from_naive!(zone) |> DateTime.add(218, :hour)

      assert {landed.day, landed.hour} == {10, 3}

      assert Tempo.shift(~o"2024-03[America/New_York]", hour: 218) ==
               ~o"2024Y3M10DT3H[America/New_York]"
    end

    test "lands where it did where the zone has the day" do
      assert Tempo.shift(~o"2011Y52W[Pacific/Apia]", day: 3) == ~o"2011Y12M29D[Pacific/Apia]"
      assert Tempo.shift(~o"2026-06[Europe/Paris]", day: 3) == ~o"2026Y6M4D[Europe/Paris]"
      assert Tempo.shift(~o"2011-12[Pacific/Apia]", month: 1) == ~o"2012Y1M[Pacific/Apia]"
    end
  end

  describe "a week date or a day of the year stepped onto a day its zone leaves out" do
    test "is the day after it, and the day before it for a step back" do
      # Thursday of the last week of 2011 and the 363rd day of the year were
      # 29 December.
      assert Date.add(~D[2011-12-26], 3) == ~D[2011-12-29]
      assert Date.add(~D[2011-01-01], 362) == ~D[2011-12-29]

      assert Tempo.shift(~o"2011-W52-4[Pacific/Apia]", day: 1) == ~o"2011Y12M31D[Pacific/Apia]"
      assert Tempo.shift(~o"2011-363[Pacific/Apia]", day: 1) == ~o"2011Y12M31D[Pacific/Apia]"
      assert Tempo.shift(~o"2011-W52-6[Pacific/Apia]", day: -1) == ~o"2011Y12M29D[Pacific/Apia]"
      assert Tempo.shift(~o"2011-365[Pacific/Apia]", day: -1) == ~o"2011Y12M29D[Pacific/Apia]"
    end
  end

  describe "a recurrence of days from a week" do
    test "has no occurrence on the day its zone leaves out" do
      {:ok, occurrences} = Tempo.to_interval(~o"R6/2011Y52W[Pacific/Apia]/P1D")

      starts = occurrences |> IntervalSet.members() |> Enum.map(&Interval.from/1)

      assert starts == [
               ~o"2011Y52W[Pacific/Apia]",
               ~o"2011Y12M27D[Pacific/Apia]",
               ~o"2011Y12M28D[Pacific/Apia]",
               ~o"2011Y12M29D[Pacific/Apia]",
               ~o"2011Y12M31D[Pacific/Apia]",
               ~o"2012Y1M1D[Pacific/Apia]"
             ]
    end
  end

  describe "the hours of a day whose first the clock skips" do
    test "are counted from the first the clock shows" do
      zone = "Africa/Cairo"
      day = ~o"2023-04-28[Africa/Cairo]"
      first = ~o"2023Y4M28DT1H[Africa/Cairo]"
      shown = shown_instead(~N[2023-04-28 00:00:00], zone)

      assert moment(first) == moment(shown, zone)
      assert Enum.at(day, 0) == first
      assert Enum.at(day, 0) == day |> Enum.to_list() |> List.first()
      assert Enum.slice(day, 0, 2) == [first, ~o"2023Y4M28DT2H[Africa/Cairo]"]
      assert Enum.member?(day, first)

      # The day is as many hours as there are from that reading to midnight.
      hours = div(moment(~N[2023-04-29 00:00:00], zone) - moment(shown, zone), 3600)
      assert hours == 23
      assert Enum.count(day) == hours
      assert Enum.count(Enum.to_list(day)) == hours
    end

    test "are counted so in the span of the day" do
      {:ok, span} = Tempo.to_interval(~o"2023-04-28[Africa/Cairo]")

      assert Enum.at(span, 0) == ~o"2023Y4M28DT1H[Africa/Cairo]"
      assert Enum.member?(span, ~o"2023Y4M28DT1H[Africa/Cairo]")
      assert Enum.count(span) == 23
      assert Enum.to_list(span) == Enum.slice(span, 0, 23)
    end
  end

  describe "the days of a week in a zone that left one out" do
    test "are the days the zone had" do
      had = [
        ~o"2011Y12M26D[Pacific/Apia]",
        ~o"2011Y12M27D[Pacific/Apia]",
        ~o"2011Y12M28D[Pacific/Apia]",
        ~o"2011Y12M29D[Pacific/Apia]",
        ~o"2011Y12M31D[Pacific/Apia]",
        ~o"2012Y1M1D[Pacific/Apia]"
      ]

      # The week is the seven days from its Monday, less the one Elixir
      # places no time on.
      days = for day <- 0..6, do: Date.add(~D[2011-12-26], day)

      shown =
        Enum.reject(days, fn day ->
          {:ok, noon} = NaiveDateTime.new(day, ~T[12:00:00])
          match?({:gap, _before, _after}, DateTime.from_naive(noon, "Pacific/Apia"))
        end)

      assert Enum.map(had, &Tempo.to_date/1) == Enum.map(shown, &{:ok, &1})

      {:ok, span} = Tempo.to_interval(~o"2011-W52[Pacific/Apia]")

      assert Enum.to_list(~o"2011-W52[Pacific/Apia]") == had
      assert Enum.to_list(span) == had
      assert Enum.count(span) == 6
      assert Enum.at(span, 4) == ~o"2011Y12M31D[Pacific/Apia]"

      # In no zone the week has its seven days.
      {:ok, floating} = Tempo.to_interval(~o"2011-W52")
      assert Enum.count(floating) == 7
    end
  end

  describe "every operation, given a value beside a gap" do
    # A time of day the clock skips, selected on a day that has the gap, is
    # given as the skipped reading. Whether it is not selected, as a day the
    # zone leaves out is not, or is the reading that long after, as a
    # recurrence's occurrence is, is to be decided (`TODO.md`).
    @awaiting_a_decision [
      {"select T00", "2023-04-28[Africa/Cairo]"},
      {"select T00", "2023-04-{27,28}[Africa/Cairo]"},
      {"select T02", "2024-03-10[America/New_York]"},
      {"select T02", "2024-03-10TXX[America/New_York]"},
      {"select T02", "2026-03-29[Europe/Paris]"},
      {"select T02/T04", "2024-03-10[America/New_York]"},
      {"select T02/T04", "2024-03-10T01:59:59[America/New_York]"},
      {"select T02/T04", "2024-03-10T01[America/New_York]"},
      {"select T02/T04", "2024-03-10T0X[America/New_York]"},
      {"select T02/T04", "2024-03-10TXX[America/New_York]"},
      {"select T02/T04", "2024-03-10T{01,02,03}[America/New_York]"},
      {"select T02/T04", "2024-03-10T{01..03}[America/New_York]"},
      {"select T02/T04", "2026-03-29T01[Europe/Paris]"},
      {"select T02/T04", "2026-03-29T{01,02,03}[Europe/Paris]"},
      {"select T02/T04", "2026-03-29[Europe/Paris]"},
      {"select T02:30", "2024-03-10[America/New_York]"},
      {"select T02:30", "2024-03-10TXX[America/New_York]"},
      {"select T02:30", "2026-03-29[Europe/Paris]"},
      {"select [2]", "2024-03-10[America/New_York]"},
      {"select [2]", "2024-03-10TXX[America/New_York]"},
      {"select [2]", "2026-03-29[Europe/Paris]"},
      {"select [2]", "2026-10-04T02[Australia/Lord_Howe]"},
      {"select [2]", "2026-10-04T{01,02,03}[Australia/Lord_Howe]"}
    ]

    test "the cells are of every operation and gap", %{harvest: harvest} do
      # A harvest that runs nothing holds to every property.
      operations = Enum.map(BesideAGap.operations(), &elem(&1, 0))

      assert harvest.cells == Enum.count(BesideAGap.texts()) * Enum.count(operations)
      assert harvest.cells > 3_000
      assert Enum.uniq(operations) == operations

      for operation <- operations do
        assert {operation, Map.get(harvest.gave, operation, 0) > 0} == {operation, true}
      end
    end

    test "no operation raises", %{harvest: harvest} do
      assert found(harvest, :raises) == []
    end

    test "every value given is one the reader takes", %{harvest: harvest} do
      not_read =
        for {operation, text, detail} <- found(harvest, :not_read),
            {operation, text} not in @awaiting_a_decision,
            do: {operation, text, detail}

      assert not_read == []
    end

    test "a time the clock skips, selected, is still given", %{harvest: harvest} do
      given = for {operation, text, _detail} <- found(harvest, :not_read), do: {operation, text}

      assert Enum.sort(Enum.uniq(given)) == Enum.sort(@awaiting_a_decision)
    end
  end
end
