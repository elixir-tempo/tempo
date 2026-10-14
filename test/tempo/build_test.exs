defmodule Tempo.BuildTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Interval, IntervalSet, RRule}

  # An expression built from parts is the expression its text reads to: the
  # builder and the reader make one form, checked by one pass. A program
  # that holds the parts never writes text to have it read back.

  @built [
    {"R/2025-01-01/P1M/FL1K2IN",
     quote(do: Tempo.every(~o"P1M", from: ~o"2025-01-01", select: [day_of_week: 1, instance: 2]))},
    {"R5/2025-01-01/P1M", quote(do: Tempo.every([month: 1], from: ~o"2025-01-01", count: 5))},
    {"R/2025-01-01/P1D/2026-01-01",
     quote(do: Tempo.every(~o"P1D", from: ~o"2025-01-01", until: ~o"2026-01-01"))},
    {"R/../P1Y/FL12M25DN", quote(do: Tempo.every(~o"P1Y", select: [month: 12, day: 25]))},
    {"R/../P1Y/FL12M25DN", quote(do: Tempo.every(~o"P1Y", select: [day: 25, month: 12]))},
    {"R/../P1Y/FL12M25DN",
     quote(do: Tempo.every(~o"P1Y", select: Tempo.selection!(month: 12, day: 25)))},
    {"R/{2026Y..2030Y}/P1Y/FL7M4DN",
     quote(do: Tempo.every(~o"P1Y", from: ~o"{2026Y..2030Y}", select: [month: 7, day: 4]))},
    {"R/../P1Y/FL(easter)eN", quote(do: Tempo.every(~o"P1Y", select: [event: "easter"]))},
    {"R/..e/P1Y/FL12M25DN",
     quote(do: Tempo.every(~o"P1Y", select: [month: 12, day: 25], years: :even))},
    {"R/../P1Y/FL7M1DN[u-ca=hebrew]",
     quote(do: Tempo.every(~o"P1Y", select: [month: 7, day: 1], calendar: Calendrical.Hebrew))},
    {"R/{2017Y..}l/P1Y/FL2M29DN",
     quote(
       do:
         Tempo.every(~o"P1Y",
           from:
             IntervalSet.new!([
               Interval.new!(from: Tempo.new!(year: 2017), to: :open)
             ]),
           select: [month: 2, day: 29],
           years: :leap
         )
     )},
    {"{2020Y..2024Y,^2022Y}",
     quote(do: IntervalSet.new([Tempo.new!(year: 2020..2024)], except: [Tempo.new!(year: 2022)]))},
    {"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN",
     quote(
       do:
         Tempo.every(~o"P1Y",
           select: [
             selection: [selection: [event: "easter"], window: ~o"-P7D"],
             day_of_week: 5,
             instance: -1
           ]
         )
     )},
    {"R/../P1Y/FLL7KN/PT1HN",
     quote(do: Tempo.every(~o"P1Y", select: [selection: [day_of_week: 7], window: ~o"PT1H"]))},
    {"R/2025-01-01/P1M/FL-1DT17HN",
     quote(do: Tempo.every(~o"P1M", from: ~o"2025-01-01", select: [day: -1, hour: 17]))},
    {"R/2025-01-01/P1M/FL{1..5}K-1IN",
     quote(
       do: Tempo.every(~o"P1M", from: ~o"2025-01-01", select: [day_of_week: 1..5, instance: -1])
     )},
    {"R/2025-01-01T00:00/P1M/FLL{1..5}K-1INT{9,10}HN",
     quote(
       do:
         Tempo.every(~o"P1M",
           from: ~o"2025-01-01T00:00",
           select: [selection: [day_of_week: 1..5, instance: -1], hour: [9, 10]]
         )
     )},
    {"R/../P1Y/FL11MLL1K1IN/P1DN2KN",
     quote(
       do:
         Tempo.every(~o"P1Y",
           select: [
             month: 11,
             selection: [selection: [day_of_week: 1, instance: 1], window: ~o"P1D"],
             day_of_week: 2
           ]
         )
     )},
    {"R/2026-06-15T10:00/P1W[Europe/Paris]",
     quote(do: Tempo.every(~o"P1W", from: ~o"2026-06-15T10:00[Europe/Paris]"))},
    {"L1K2IN", quote(do: Tempo.selection(day_of_week: 1, instance: 2))},
    {"L12M25DN", quote(do: Tempo.selection(month: 12, day: 25))},
    {"L{1K2I,3K2I}T9HN",
     quote(
       do:
         Tempo.selection(
           hour: 9,
           all: [[instance: 2, day_of_week: 1], [day_of_week: 3, instance: 2]]
         )
     )},
    {"L6M{1K1I,2K}-1IN",
     quote(
       do:
         Tempo.selection(
           month: 6,
           all: [[day_of_week: 1, instance: 1], [day_of_week: 2]],
           instance: -1
         )
     )},
    {"[2026-06-15,2026-06-17]", quote(do: Tempo.one_of([~o"2026-06-15", ~o"2026-06-17"]))}
  ]

  for {{text, built}, index} <- Enum.with_index(@built) do
    test "#{index}: #{text} is built as it is read" do
      assert unquote(built) == Tempo.from_iso8601(unquote(text))
    end
  end

  describe "what cannot be built" do
    test "is refused as the text would be" do
      assert {:error, %ArgumentError{message: message}} = Tempo.selection(fortnight: 1)
      assert message =~ ":fortnight is not a part of a selection"

      assert {:error, %Tempo.InvalidDateError{reason: {:unknown_event, "nonsense"}}} =
               Tempo.selection(event: "nonsense")

      assert {:error, %ArgumentError{}} = Tempo.selection(window: ~o"P1D")
      assert {:error, %ArgumentError{}} = Tempo.selection([])
      assert {:error, %ArgumentError{}} = Tempo.selection(day: "15")

      assert {:error, %ArgumentError{message: "a recurrence ends by :count or by :until" <> _}} =
               Tempo.every(~o"P1M", count: 1, until: ~o"2026")

      assert {:error, %ArgumentError{}} = Tempo.every(~o"P1M", count: 0)
      assert {:error, %ArgumentError{}} = Tempo.every(~o"P1M", strat: ~o"2026")
      assert {:error, %ArgumentError{}} = Tempo.every(~o"P1Y", from: ~o"2026", years: :even)
      assert {:error, %ArgumentError{}} = Tempo.every(~o"P1Y", years: :fortnightly)

      assert {:error, %ArgumentError{}} =
               Tempo.every(~o"P1Y", from: ~o"2026", calendar: Calendrical.Hebrew)

      assert {:error, %Tempo.InvalidCalendarError{}} = Tempo.every(~o"P1Y", calendar: Date)
      assert {:error, %ArgumentError{}} = IntervalSet.new([~o"2026"], except: ["2027"])
      assert {:error, %ArgumentError{}} = Tempo.every("P1M")
      assert {:error, %ArgumentError{}} = Tempo.every(~o"P1M", from: ~o"2026/2027")

      assert {:error, %ArgumentError{}} = Tempo.one_of([])
      assert {:error, %ArgumentError{}} = Tempo.one_of([~o"2026", ~o"5786[u-ca=hebrew]"])
    end
  end

  describe "what is built" do
    test "is used as what is read is" do
      {:ok, thanksgiving} =
        Tempo.every(~o"P1Y", select: [month: 11, day_of_week: 4, instance: 4])

      assert thanksgiving
             |> Tempo.to_interval!(within: ~o"2026/2027")
             |> IntervalSet.map(&Interval.from/1) == [~o"2026-11-26", ~o"2027-11-25"]

      assert RRule.to_string(Tempo.every!(~o"P1M", select: [day_of_week: 1, instance: 2])) ==
               {:ok, "FREQ=MONTHLY;BYDAY=2MO"}
    end
  end
end
