defmodule Tempo.IntervalSetTest do
  use ExUnit.Case, async: true

  # The functions of `Tempo.IntervalSet` over sets and over the other forms,
  # each answer held to `Date`.

  import Tempo.Sigils

  alias Tempo.{Interval, IntervalSet, RecurrenceSet}

  defp dates(set), do: IntervalSet.map(set, &{date(Interval.from(&1)), date(Interval.to(&1))})

  defp date(value) do
    {:ok, date} = Tempo.to_date(value)
    date
  end

  describe "members/1, count/1 and first/1" do
    test "of a recurrence are its occurrences" do
      weekly = ~o"R3/2026-06-01/P1W"

      assert IntervalSet.count(weekly) == 3
      assert Interval.from(IntervalSet.first(weekly)) == ~o"2026-06-01"

      assert weekly |> IntervalSet.members() |> Enum.map(&date(Interval.from(&1))) ==
               Enum.map(0..2, &Date.add(~D[2026-06-01], 7 * &1))
    end

    test "of a value that names several are the values it names" do
      assert IntervalSet.members(~o"2026Y{6,8}M") == [~o"2026-06", ~o"2026-08"]
    end

    test "of a singular expression is the expression" do
      assert IntervalSet.members(~o"2026-06") == [~o"2026-06"]
      assert IntervalSet.first(~o"2026-06-01/2026-06-30") == ~o"2026-06-01/2026-06-30"
    end

    test "of an expression with no end is refused, never cut short" do
      {:ok, mondays} = Tempo.select(~o"2026-06-01/..", ~o"1K")

      assert_raise Tempo.ConversionError, fn -> IntervalSet.members(mondays) end
      assert_raise Tempo.ConversionError, fn -> IntervalSet.count(~o"R/2026-06-01/P1W") end

      # The first member of a set read as it is walked is taken alone, as
      # is the first occurrence of a recurrence with no end.
      assert IntervalSet.first(mondays) == ~o"2026-06-01"
      assert date(Interval.from(IntervalSet.first(~o"R/2026-06-01/P1W"))) == ~D[2026-06-01]

      # One counted back from no end has no first.
      assert_raise Tempo.ConversionError, fn -> IntervalSet.first(~o"R/P1W/2026-06-01") end
    end

    test "of a recurrence carry its metadata, with a rule or without" do
      {:ok, daily} =
        Tempo.every(~o"P1D", from: ~o"2026-06-01", count: 2, metadata: %{title: "Standup"})

      {:ok, mondays} =
        Tempo.every(~o"P1W",
          from: ~o"2026-06-01",
          count: 2,
          select: [day_of_week: 1],
          metadata: %{title: "Review"}
        )

      assert Enum.map(IntervalSet.members(daily), &Tempo.metadata/1) == [
               %{title: "Standup"},
               %{title: "Standup"}
             ]

      assert Enum.map(IntervalSet.members(mondays), &Tempo.metadata/1) == [
               %{title: "Review"},
               %{title: "Review"}
             ]
    end

    test "of a recurrence set are its rules, a rule on its own the one" do
      rule = Tempo.every!(~o"P1Y", select: [month: 12, day: 25])

      assert RecurrenceSet.members(rule) == [rule]
      assert RecurrenceSet.members(RecurrenceSet.new!([rule])) == [rule]
    end
  end

  describe "slots/3" do
    test "of a week are whole weeks from the start" do
      {:ok, weeks} = IntervalSet.slots(~o"2026-06", ~o"P1W")

      assert dates(weeks) ==
               for(
                 n <- 0..3,
                 do: {Date.add(~D[2026-06-01], 7 * n), Date.add(~D[2026-06-07], 7 * n)}
               )
    end

    test "of what has no end is refused, never an empty set" do
      assert {:error, %Tempo.ConversionError{reason: :unbounded}} =
               IntervalSet.slots(~o"2026-06-01/..", ~o"P1D")
    end

    test "with no spacing is refused" do
      assert {:error, %ArgumentError{}} = IntervalSet.slots(~o"2026-06", ~o"P1D", every: ~o"PT0S")
    end
  end

  describe "new/2 and new!/2" do
    test "refuse what they leave out when it is no list of values" do
      assert {:error, %ArgumentError{}} = IntervalSet.new([~o"2026"], except: ~o"2026-06")

      assert_raise ArgumentError, fn -> IntervalSet.new!([~o"2026"], except: ["2026-06"]) end
    end
  end

  # Law 4 and decision 41: a set is of one frame. A floating member beside one
  # in a zone or at a time shift is refused by every way a set is made.
  describe "a set of one frame" do
    test "a floating member beside one at a time shift is refused, in either order" do
      assert {:error, %Tempo.FrameError{reason: :floating_and_zoned}} =
               IntervalSet.new([~o"2026-06-15", ~o"2026-06-16T10Z"])

      assert {:error, %Tempo.FrameError{reason: :floating_and_zoned}} =
               IntervalSet.new([~o"2026-06-16T10Z", ~o"2026-06-15"])

      assert_raise Tempo.FrameError, fn ->
        IntervalSet.new!([~o"2026-06-15", ~o"2026-06-16T10+02:00"])
      end
    end

    test "a floating member beside one in a named zone is refused" do
      assert {:error, %Tempo.FrameError{reason: :floating_and_zoned}} =
               IntervalSet.new([~o"2026-06-15", ~o"2026-06-17T10[Europe/Paris]"])
    end

    test "a floating exception from a zoned set is refused" do
      assert {:error, %Tempo.FrameError{reason: :floating_and_zoned}} =
               IntervalSet.new([~o"2026-06-15"], except: [~o"2026-06-16T10Z"])
    end

    test "a set written with members of two frames is refused by the reader" do
      assert {:error, %Tempo.FrameError{reason: :floating_and_zoned}} =
               Tempo.from_iso8601("{2026-06-15,2026-06-16T10Z}")
    end

    test "a one-of set and a set of rules of two frames are refused" do
      assert {:error, %Tempo.FrameError{reason: :floating_and_zoned}} =
               Tempo.one_of([~o"2026-06-15", ~o"2026-06-16T10Z"])

      daily_floating = Tempo.every!(~o"P1D", from: ~o"2026-06-15")
      daily_at_utc = Tempo.every!(~o"P1D", from: ~o"2026-06-16T10Z")

      assert {:error, %Tempo.FrameError{reason: :floating_and_zoned}} =
               RecurrenceSet.new([daily_floating, daily_at_utc])
    end

    test "members on the UTC line of different shifts and zones are one set" do
      assert {:ok, _set} = IntervalSet.new([~o"2026-06-16T10Z", ~o"2026-06-17T10[Europe/Paris]"])
      assert {:ok, _set} = Tempo.from_iso8601("{2026-06-15T09+02:00,2026-06-16T10Z}")
    end

    test "members a zone written after the set places are one set" do
      assert {:ok, _set} = Tempo.from_iso8601("{2026-06-15,2026-06-16T10}[Europe/Paris]")
    end

    test "a member with no year, or a rule with no start, lies beside either line" do
      assert {:ok, _set} = IntervalSet.new([~o"2026-06-15", ~o"12M25D"])
      assert {:ok, _set} = IntervalSet.new([~o"2026-06-16T10Z", ~o"12M25D"])
      assert {:ok, _set} = Tempo.from_iso8601("{R/../P1Y,2026-06-16T10Z}")
    end
  end
end
