defmodule Tempo.CoreCoverageTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Allen
  alias Tempo.ConversionError
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError

  describe "duration predicates (delegated to Tempo.Interval)" do
    @one_day ~o"2020Y1M1D/2D"

    test "at_most? / exactly?" do
      assert Tempo.at_most?(@one_day, ~o"P1D")
      assert Tempo.exactly?(@one_day, ~o"P1D")
    end

    test "longer_than? / shorter_than?" do
      assert Tempo.longer_than?(@one_day, ~o"PT1H")
      assert Tempo.shorter_than?(@one_day, ~o"P2D")
    end
  end

  describe "relation predicates" do
    test "before? / after? hold across a gap" do
      assert Tempo.before?(~o"2020Y", ~o"2022Y")
      assert Tempo.after?(~o"2022Y", ~o"2020Y")
    end

    test "before? / after? hold for adjacent spans, which share no instant" do
      assert Tempo.before?(~o"2020Y", ~o"2021Y")
      assert Tempo.after?(~o"2021Y", ~o"2020Y")
    end

    test "Allen.meets? holds for adjacent spans" do
      assert Allen.meets?(~o"2020Y/2021Y", ~o"2021Y/2022Y")
    end

    test "Allen.during? holds for a contained span" do
      assert Allen.during?(~o"2020Y6M", ~o"2020Y")
    end
  end

  describe "workday helpers in their default-territory form" do
    test "workdays/0 returns Monday–Friday" do
      assert inspect(Tempo.workdays()) == ~s|~o"{1,2,3,4,5}K"|
    end

    test "weekend? / workday?" do
      assert Tempo.weekend?(~o"2026-06-13")
      assert Tempo.workday?(~o"2026-06-15")
    end

    test "arithmetic skips the weekend" do
      assert Tempo.add_workdays(~o"2026-06-12", 1) == ~o"2026-06-15"
      assert Tempo.next_workday(~o"2026-06-12") == ~o"2026-06-15"
      assert Tempo.previous_workday(~o"2026-06-15") == ~o"2026-06-12"
      assert Tempo.nearest_workday(~o"2026-06-13") == ~o"2026-06-12"
    end

    test "count_workdays counts business days in an interval" do
      assert Tempo.count_workdays(~o"2026-06-15/2026-06-20") == 5
    end

    test "weekends/0 returns Saturday and Sunday" do
      assert inspect(Tempo.weekends()) == ~s|~o"{6,7}K"|
    end
  end

  describe "map/2 and try_map/2 collect into an IntervalSet" do
    @july4 [~o"2025-07-04", ~o"2026-07-04", ~o"2027-07-04"]

    defp member_dates(set) do
      set
      |> IntervalSet.members()
      |> Enum.map(fn iv -> {iv.from.time[:month], iv.from.time[:day]} end)
    end

    test "map returns an IntervalSet, one member per element" do
      observed = Tempo.map(@july4, &Tempo.nearest_workday(&1, :US))
      assert %IntervalSet{} = observed
      # July 4 stays (Fri), rolls to Fri 3 (from Sat), Mon 5 (from Sun).
      assert member_dates(observed) == [{7, 4}, {7, 3}, {7, 5}]
    end

    test "try_map returns {:ok, set} when every element resolves" do
      assert {:ok, set} = Tempo.try_map(@july4, &Tempo.nearest_workday(&1, :US))
      assert member_dates(set) == [{7, 4}, {7, 3}, {7, 5}]
    end

    test "try_map halts at the first un-materialisable value" do
      assert {:error, %ConversionError{reason: :bare_duration}} =
               Tempo.try_map([~o"2025-07-04", ~o"P1D"], & &1)
    end

    test "map raises on an un-materialisable value" do
      assert_raise ConversionError, fn -> Tempo.map([~o"P1D"], & &1) end
    end
  end

  describe "parse/2 maps the parsed fields onto Tempo's" do
    test "a UTC offset becomes the shift from_iso8601/1 gives it" do
      for input <- ["2026-05-23T14:30:00+05:00", "2026-05-23T14:30:00-03:30"] do
        assert Tempo.parse(input) == Tempo.from_iso8601(input)
      end
    end

    test "a localized GMT offset is the shift its ISO 8601 spelling gives" do
      assert Tempo.parse("May 23, 2026, 2:30 PM GMT+5", locale: :en) ==
               Tempo.from_iso8601("2026-05-23T14:30+05:00")

      assert Tempo.parse("May 23, 2026, 2:30 PM GMT-3:30", locale: :en) ==
               Tempo.from_iso8601("2026-05-23T14:30-03:30")
    end

    test "a standard-time name keeps its own offset when the zone keeps daylight time" do
      # New York keeps daylight time in May, and EST still names -05:00.
      assert Tempo.parse("May 23, 2026, 2:30 PM EST", locale: :en) ==
               Tempo.from_iso8601("2026-05-23T14:30-05:00")
    end

    test "a week of the year is the week from_iso8601/1 reads" do
      assert {:ok, week} = Tempo.parse("week 1 of 2026", locale: :en)
      assert {:ok, week} == Tempo.from_iso8601("2026-W01")
    end

    test "a weekday beside a full date is implied by the date" do
      assert Tempo.parse("Monday, May 25, 2026", locale: :en) == Tempo.from_iso8601("2026-05-25")
    end
  end

  describe "bang functions raise on invalid input" do
    test "new!/1 raises on an out-of-range component" do
      assert_raise InvalidDateError, fn -> Tempo.new!(year: 2020, month: 13) end
    end

    # The exception is the parser's: `Calendrical.ParseError` from
    # Calendrical 1.4, `Localize.DateTimeParseError` from 1.5, which
    # parses through Localize.
    test "parse!/2 raises on an unparseable string" do
      {:error, exception} = Tempo.parse("@@@")
      assert_raise exception.__struct__, fn -> Tempo.parse!("@@@") end
    end
  end
end
