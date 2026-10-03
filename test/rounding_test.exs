defmodule Tempo.Iso8601.RoundingTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.InvalidUnitError
  alias Tempo.RoundingError

  # The user's decision of 2026-10-03: a value rounds to the nearest boundary
  # of the unit, by where it starts in the unit as the unit is there, and half
  # way rounds up.
  describe "rounding to year" do
    test "a date in the first half of the year rounds down" do
      assert Tempo.round(~o"2022Y3M10D", :year) == ~o"2022Y"
    end

    test "a date in the second half of the year rounds up" do
      assert Tempo.round(~o"2022Y11M21D", :year) == ~o"2023Y"
    end

    test "the half is the year's own: 183 days into 365, or into 366" do
      assert Tempo.round(~o"2026-07-02", :year) == ~o"2026Y"
      assert Tempo.round(~o"2026-07-03", :year) == ~o"2027Y"
      assert Tempo.round(~o"2024-07-01", :year) == ~o"2024Y"
      assert Tempo.round(~o"2024-07-02", :year) == ~o"2025Y"
    end

    # Rounded to the month and then to the year, 16 June went to July and
    # from there to 2027.
    test "a day is rounded once, not month by month" do
      assert Tempo.round(~o"2026-06-16", :year) == ~o"2026Y"
    end

    test "a month rounds by where it starts" do
      assert Tempo.round(~o"2026-06", :year) == ~o"2026Y"
      assert Tempo.round(~o"2026-07", :year) == ~o"2026Y"
      assert Tempo.round(~o"2026-08", :year) == ~o"2027Y"
    end

    test "a year-resolution value is unchanged" do
      assert Tempo.round(~o"2022Y", :year) == ~o"2022Y"
    end

    test "a week rounds in the year its weeks are counted in" do
      assert Tempo.round(~o"2026-W27", :year) == ~o"2026Y"
      assert Tempo.round(~o"2026-W28", :year) == ~o"2027Y"
    end
  end

  describe "rounding to month" do
    test "the first half of the month rounds down" do
      assert Tempo.round(~o"2023Y8M1D", :month) == ~o"2023Y8M"
    end

    test "the second half of the month rounds up" do
      assert Tempo.round(~o"2023Y8M20D", :month) == ~o"2023Y9M"
      assert Tempo.round(~o"2022Y11M21D", :month) == ~o"2022Y12M"
    end

    test "the half is the month's own" do
      # 15 days into 31, and 16.
      assert Tempo.round(~o"2026-01-16", :month) == ~o"2026Y1M"
      assert Tempo.round(~o"2026-01-17", :month) == ~o"2026Y2M"

      # 14 days into 28 is half way, which rounds up.
      assert Tempo.round(~o"2026-02-15", :month) == ~o"2026Y3M"
      assert Tempo.round(~o"2024-02-15", :month) == ~o"2024Y2M"
    end

    test "the last month rounds up into the next year" do
      assert Tempo.round(~o"2026-12-20", :month) == ~o"2027Y1M"
    end

    test "a month-resolution value is unchanged" do
      assert Tempo.round(~o"2022Y11M", :month) == ~o"2022Y11M"
    end

    test "in another calendar the month is that calendar's" do
      hebrew = Tempo.from_iso8601!("5786-06-20[u-ca=hebrew]")

      assert Tempo.round(hebrew, :month) == Tempo.from_iso8601!("5786-07[u-ca=hebrew]")
    end
  end

  describe "rounding to week" do
    test "a date rounds to the day its week or the next begins on" do
      assert Tempo.round(~o"2026-06-17", :week) == ~o"2026Y6M15D"
      assert Tempo.round(~o"2026-06-19", :week) == ~o"2026Y6M22D"
    end

    test "half way through the week is Thursday noon" do
      assert Tempo.round(~o"2026-06-18T11:59", :week) == ~o"2026Y6M15D"
      assert Tempo.round(~o"2026-06-18T12:00", :week) == ~o"2026Y6M22D"
    end
  end

  describe "rounding to day" do
    test "a time before noon rounds down and noon rounds up" do
      assert Tempo.round(~o"2026-06-15T11:59", :day) == ~o"2026Y6M15D"
      assert Tempo.round(~o"2026-06-15T12:00", :day) == ~o"2026Y6M16D"
      assert Tempo.round(~o"2026-06-15T10:30") == ~o"2026Y6M15D"
    end

    test "the last day rounds up into the next year" do
      assert Tempo.round(~o"2026-12-31T18:00", :day) == ~o"2027Y1M1D"
    end

    test "a day in a zone is as long as the zone makes it" do
      # The clocks go forward on 29 March 2026 in Paris, a day of 23 hours:
      # half past twelve is half way through it.
      assert Tempo.round(~o"2026-03-29T12:29[Europe/Paris]", :day) ==
               ~o"2026-03-29[Europe/Paris]"

      assert Tempo.round(~o"2026-03-29T12:30[Europe/Paris]", :day) ==
               ~o"2026-03-30[Europe/Paris]"
    end
  end

  describe "rounding to hour" do
    test "the first half of the hour rounds down" do
      assert Tempo.round(~o"T10H10M", :hour) == ~o"T10H"
      assert Tempo.round(~o"T10H29M", :hour) == ~o"T10H"
    end

    test "half past and the second half of the hour round up" do
      assert Tempo.round(~o"T10H30M", :hour) == ~o"T11H"
      assert Tempo.round(~o"T10H50M", :hour) == ~o"T11H"
    end

    # It was the value `1DT0H`.
    test "the last hour of the day rounds up to midnight" do
      assert Tempo.round(~o"T23H45M", :hour) == ~o"T0H"
    end

    test "a date and time rounds, into the next day when it must" do
      assert Tempo.round(~o"2026-06-15T10:30", :hour) == ~o"2026Y6M15DT11H"
      assert Tempo.round(~o"2026-06-15T23:30", :hour) == ~o"2026Y6M16DT0H"
      assert Tempo.round(~o"2026-06-15T10:29:59", :hour) == ~o"2026Y6M15DT10H"
    end

    test "a value in a zone keeps its zone" do
      assert Tempo.round(~o"2026-06-15T10:30:45Z", :minute) == ~o"2026Y6M15DT10H31MZ"
    end
  end

  describe "rounding to minute" do
    test "the first half of the minute rounds down" do
      assert Tempo.round(~o"T10H10M20S", :minute) == ~o"T10H10M"
    end

    test "half and the second half of the minute round up" do
      assert Tempo.round(~o"T10H10M30S", :minute) == ~o"T10H11M"
      assert Tempo.round(~o"T10H10M50S", :minute) == ~o"T10H11M"
      assert Tempo.round(~o"T23H59M30S", :minute) == ~o"T0H0M"
    end
  end

  describe "rounding to second" do
    test "a fraction of a second rounds by its half" do
      assert Tempo.round(~o"T10:10:29.4", :second) == ~o"T10H10M29S"
      assert Tempo.round(~o"T10:10:29.5", :second) == ~o"T10H10M30S"
      assert Tempo.round(~o"2026-06-15T23:59:59.999999", :second) == ~o"2026Y6M16DT0H0M0S"
    end
  end

  describe "a value with no year" do
    test "rounds to a month whose length is the same in every year" do
      assert Tempo.round(~o"06-15", :month) == ~o"6M"
      assert Tempo.round(~o"06-16", :month) == ~o"7M"
    end

    test "is refused where the answer is the missing year's" do
      # 14 days into February is half of 28 and less than half of 29.
      assert {:error, %Tempo.UnanchoredError{}} = Tempo.round(~o"02-15", :month)
      assert Tempo.round(~o"02-16", :month) == ~o"3M"
    end

    test "rounds a time of day on its date" do
      assert Tempo.round(~o"06-15T12:00", :day) == ~o"6M16D"
    end
  end

  describe "values already at the target resolution are returned unchanged" do
    test "day" do
      assert Tempo.round(~o"2022Y11M21D", :day) == ~o"2022Y11M21D"
    end

    test "hour" do
      assert Tempo.round(~o"T10H", :hour) == ~o"T10H"
    end

    test "minute" do
      assert Tempo.round(~o"T10H10M", :minute) == ~o"T10H10M"
    end

    test "second" do
      assert Tempo.round(~o"T10H10M20S", :second) == ~o"T10H10M20S"
    end
  end

  describe "errors" do
    test "rounding to a resolution finer than the value is a RoundingError" do
      assert {:error, %RoundingError{unit: :second}} = Tempo.round(~o"2022Y", :second)
    end

    test "an unknown unit is an InvalidUnitError" do
      assert {:error, %InvalidUnitError{unit: :fortnight}} =
               Tempo.round(~o"2022Y11M21D", :fortnight)
    end

    test "a unit the value's axis does not have is a ResolutionError" do
      assert {:error, %Tempo.ResolutionError{}} = Tempo.round(~o"2026-W25", :month)
      assert {:error, %Tempo.ResolutionError{}} = Tempo.round(~o"T10:30", :day)
    end

    test "a value that holds several is a RoundingError" do
      assert {:error, %RoundingError{}} = Tempo.round(~o"2026-06-{15,16}", :month)
    end
  end
end
