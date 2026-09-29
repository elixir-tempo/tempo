defmodule Tempo.CalendarAccessorsTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval

  describe "Tempo.day_of_week/1,2" do
    test "2026-06-15 is a Monday (default ordering)" do
      assert Tempo.day_of_week(~o"2026-06-15") == 1
    end

    test "2026-06-14 is a Sunday (default ordering returns 7)" do
      assert Tempo.day_of_week(~o"2026-06-14") == 7
    end

    test ":sunday starting_on renumbers" do
      # Monday under :sunday starting becomes 2.
      assert Tempo.day_of_week(~o"2026-06-15", :sunday) == 2
      # Sunday under :sunday starting becomes 1.
      assert Tempo.day_of_week(~o"2026-06-14", :sunday) == 1
    end

    test "raises when the Tempo has no year" do
      assert_raise ArgumentError, ~r/requires a year component/, fn ->
        Tempo.day_of_week(~o"6M15D")
      end
    end
  end

  describe "Tempo.day_of_year/1" do
    test "first day of year is 1" do
      assert Tempo.day_of_year(~o"2026-01-01") == 1
    end

    test "last day of a non-leap year is 365" do
      assert Tempo.day_of_year(~o"2025-12-31") == 365
    end

    test "last day of a leap year is 366" do
      assert Tempo.day_of_year(~o"2024-12-31") == 366
    end
  end

  describe "Tempo.quarter_of_year/1" do
    test "January is Q1" do
      assert Tempo.quarter_of_year(~o"2026-01-15") == 1
    end

    test "April is Q2" do
      assert Tempo.quarter_of_year(~o"2026-04-01") == 2
    end

    test "July is Q3" do
      assert Tempo.quarter_of_year(~o"2026-07-31") == 3
    end

    test "December is Q4" do
      assert Tempo.quarter_of_year(~o"2026-12-31") == 4
    end

    test "works on month-resolution Tempo (defaults day to 1)" do
      assert Tempo.quarter_of_year(~o"2026-11") == 4
    end
  end

  describe "Tempo.leap_year?/1" do
    test "2024 is a Gregorian leap year" do
      assert Tempo.leap_year?(~o"2024") == true
    end

    test "2025 is not" do
      assert Tempo.leap_year?(~o"2025") == false
    end

    test "2000 is a leap year (divisible by 400)" do
      assert Tempo.leap_year?(~o"2000") == true
    end

    test "1900 is not (divisible by 100 but not 400)" do
      assert Tempo.leap_year?(~o"1900") == false
    end

    test "raises when the Tempo has no year" do
      assert_raise ArgumentError, ~r/requires a year component/, fn ->
        Tempo.leap_year?(%Tempo{time: [month: 2]})
      end
    end
  end

  describe "Tempo.days_in_month/1" do
    test "Feb in a leap year has 29 days" do
      assert Tempo.days_in_month(~o"2024-02") == 29
    end

    test "Feb in a non-leap year has 28 days" do
      assert Tempo.days_in_month(~o"2025-02") == 28
    end

    test "April has 30 days" do
      assert Tempo.days_in_month(~o"2026-04") == 30
    end

    test "July has 31 days" do
      assert Tempo.days_in_month(~o"2026-07") == 31
    end

    test "accepts a day-resolution Tempo" do
      assert Tempo.days_in_month(~o"2026-04-15") == 30
    end

    test "raises when there's no month" do
      assert_raise ArgumentError, ~r/requires a month component/, fn ->
        Tempo.days_in_month(~o"2026")
      end
    end
  end

  describe "Tempo.weekend?/2 and workday?/2" do
    # 2026-06-12 Fri, -13 Sat, -14 Sun, -15 Mon.
    test "United States weekends on Saturday and Sunday" do
      assert Tempo.weekend?(~o"2026-06-13", :US)
      assert Tempo.weekend?(~o"2026-06-14", :US)
      refute Tempo.weekend?(~o"2026-06-15", :US)
      assert Tempo.workday?(~o"2026-06-15", :US)
      refute Tempo.workday?(~o"2026-06-13", :US)
    end

    test "the weekend varies by territory (same Friday, different verdict)" do
      friday = ~o"2026-06-12"
      assert Tempo.weekend?(friday, :SA)
      refute Tempo.weekend?(friday, :US)
      assert Tempo.workday?(friday, :US)
    end

    test "India weekends on Sunday only" do
      assert Tempo.weekend?(~o"2026-06-14", :IN)
      refute Tempo.weekend?(~o"2026-06-13", :IN)
    end

    test "weekend? and workday? partition the week" do
      for day <- 12..15, territory <- [:US, :SA, :IN] do
        value = Tempo.from_iso8601!("2026-06-#{day}")
        assert Tempo.weekend?(value, territory) != Tempo.workday?(value, territory)
      end
    end

    test "a datetime is classified by its day" do
      assert Tempo.weekend?(~o"2026-06-13T10:30:00", :US)
      assert Tempo.workday?(~o"2026-06-15T10:30:00", :US)
    end

    test "ordinal-date form is supported (day-of-year 166 is 2026-06-15, a Monday)" do
      assert Tempo.workday?(~o"2026-166", :US)
    end

    test "a territory string resolves the same as the atom" do
      assert Tempo.weekend?(~o"2026-06-13", "US")
    end

    test "raises on a value coarser than a day" do
      assert_raise Tempo.ResolutionError, ~r/denotes a day/, fn ->
        Tempo.weekend?(~o"2026", :US)
      end

      assert_raise Tempo.ResolutionError, ~r/`workday\?` needs a value that denotes a day/, fn ->
        Tempo.workday?(~o"2026-06", :US)
      end
    end

    test "raises on a value without a year" do
      assert_raise Tempo.UnanchoredError, fn -> Tempo.weekend?(~o"6M13D", :US) end
    end

    test "raises the resolver's error for a territory it does not recognise" do
      for territory <- [:"", "", 42, "not a territory", String.duplicate("x", 10_000)] do
        assert_raise ArgumentError, ~r/Tempo.Territory.resolve\/1 does not recognise/, fn ->
          Tempo.weekend?(~o"2026-06-13", territory)
        end
      end
    end

    @calendars [
      Calendrical.Gregorian,
      Calendrical.Hebrew,
      Calendrical.Islamic.Civil,
      Calendrical.Islamic.Observational,
      Calendrical.Japanese,
      Calendrical.Indian,
      Calendrical.Persian,
      Calendrical.Chinese,
      Calendrical.Coptic,
      Calendrical.Ethiopic
    ]

    test "the verdict is the same in every calendar (the weekday is absolute)" do
      # The same instant, expressed in a non-Gregorian calendar, carries
      # year/month/day in *that* calendar — so the day of week must be
      # read off a date built in the value's own calendar, not by
      # interpreting its components as Gregorian.
      saturday = ~D[2026-06-13]
      monday = ~D[2026-06-15]

      for calendar <- @calendars do
        sat = Tempo.from_date(Date.convert!(saturday, calendar))
        mon = Tempo.from_date(Date.convert!(monday, calendar))

        assert Tempo.weekend?(sat, :US), "#{inspect(calendar)} Saturday should be a US weekend"
        refute Tempo.weekend?(mon, :US), "#{inspect(calendar)} Monday should be a US workday"
        assert Tempo.workday?(mon, :US)
      end
    end

    test "territory weekend differences hold across calendars too" do
      friday = ~D[2026-06-12]

      for calendar <- @calendars do
        fri = Tempo.from_date(Date.convert!(friday, calendar))
        assert Tempo.weekend?(fri, :SA), "#{inspect(calendar)} Friday should be a Saudi weekend"
        refute Tempo.weekend?(fri, :US), "#{inspect(calendar)} Friday should be a US workday"
      end
    end
  end

  describe "Tempo.add_workdays/3 and friends" do
    test "adding one workday to a Friday lands on Monday" do
      assert Tempo.add_workdays(~o"2026-06-12", 1, :US) == ~o"2026-06-15"
    end

    test "subtracting crosses the weekend backward" do
      assert Tempo.add_workdays(~o"2026-06-15", -1, :US) == ~o"2026-06-12"
    end

    test "a multi-week span skips every weekend" do
      # 5 workdays on from Monday is the next Monday; 10 is the one after.
      assert Tempo.add_workdays(~o"2026-06-15", 5, :US) == ~o"2026-06-22"
      assert Tempo.add_workdays(~o"2026-06-15", 10, :US) == ~o"2026-06-29"
    end

    test "adding zero workdays returns the value unchanged" do
      assert Tempo.add_workdays(~o"2026-06-13", 0, :US) == ~o"2026-06-13"
    end

    test "the time of day is preserved" do
      assert Tempo.add_workdays(~o"2026-06-15T09:30:00", 1, :US) == ~o"2026-06-16T09:30:00"
    end

    test "the weekend that is skipped depends on the territory" do
      # Saudi Arabia weekends Friday/Saturday: Thursday + 1 workday is Sunday.
      assert Tempo.add_workdays(~o"2026-06-11", 1, :SA) == ~o"2026-06-14"
    end

    test "next_workday / previous_workday" do
      assert Tempo.next_workday(~o"2026-06-12", :US) == ~o"2026-06-15"
      assert Tempo.previous_workday(~o"2026-06-15", :US) == ~o"2026-06-12"
    end

    test "nearest_workday rolls a weekend to the closest workday" do
      # US Sat/Sun weekend — the observed-holiday rule.
      assert Tempo.nearest_workday(~o"2026-07-04", :US) == ~o"2026-07-03"
      assert Tempo.nearest_workday(~o"2027-07-04", :US) == ~o"2027-07-05"
      # Already a workday → unchanged.
      assert Tempo.nearest_workday(~o"2025-07-04", :US) == ~o"2025-07-04"
    end

    test "nearest_workday honours the territory's weekend" do
      # Saudi Arabia's weekend is Friday/Saturday.
      assert Tempo.nearest_workday(~o"2026-07-04", :SA) == ~o"2026-07-05"
      assert Tempo.nearest_workday(~o"2026-07-03", :SA) == ~o"2026-07-02"
    end

    test "count_workdays counts the workdays of a half-open span" do
      {:ok, june} = Interval.new(from: ~o"2026-06-01", to: ~o"2026-07-01")
      assert Tempo.count_workdays(june, :US) == 22
      # A single work week is five workdays.
      {:ok, week} = Interval.new(from: ~o"2026-06-15", to: ~o"2026-06-22")
      assert Tempo.count_workdays(week, :US) == 5
    end

    test "count_workdays counts any value select/2 selects from" do
      assert Tempo.count_workdays(~o"2026-06", :US) == 22
      assert Tempo.count_workdays(~o"2026-06-15/2026-06-22", :SA) == 5
      assert Tempo.count_workdays(~o"2026Y{6..7}M", :US) == 45
    end

    test "count_workdays counts whole days, not the hours of a finer span" do
      assert Tempo.count_workdays(~o"2026-06-15T10/2026-06-17T10", :US) == 2
    end

    test "count_workdays refuses a span with no end to count to" do
      assert {:error, %Tempo.UnboundedSetError{}} =
               Tempo.count_workdays(~o"2026-06-15/..", :US)

      assert {:error, %Tempo.IntervalEndpointsError{reason: :open_start}} =
               Tempo.count_workdays(~o"../2026-06-15", :US)
    end

    test "a value coarser than a day is an error, not a raise" do
      for function <- [
            &Tempo.add_workdays(&1, 1, :US),
            &Tempo.next_workday(&1, :US),
            &Tempo.previous_workday(&1, :US),
            &Tempo.nearest_workday(&1, :US)
          ],
          value <- [~o"2026", ~o"2026-06", ~o"2026-W24", ~o"2026Y6M{1..3}D"] do
        assert {:error, %Tempo.ResolutionError{} = error} = function.(value)
        assert Exception.message(error) =~ "needs a value that denotes a day"
      end
    end

    test "a value without a year is an unanchored error" do
      assert {:error, %Tempo.UnanchoredError{operation: :add_workdays}} =
               Tempo.add_workdays(~o"6M12D", 1, :US)

      assert {:error, %Tempo.UnanchoredError{operation: :nearest_workday}} =
               Tempo.nearest_workday(~o"T10", :US)
    end

    test "a territory that cannot be resolved is an error, not a raise" do
      for territory <- [:"", "", 42, "not a territory", String.duplicate("x", 10_000)] do
        assert {:error, %ArgumentError{}} = Tempo.add_workdays(~o"2026-06-12", 1, territory)
        assert {:error, %ArgumentError{}} = Tempo.next_workday(~o"2026-06-12", territory)
        assert {:error, %ArgumentError{}} = Tempo.previous_workday(~o"2026-06-12", territory)
        assert {:error, %ArgumentError{}} = Tempo.nearest_workday(~o"2026-06-13", territory)
        assert {:error, %ArgumentError{}} = Tempo.count_workdays(~o"2026-06", territory)
        assert {:error, %ArgumentError{}} = Tempo.workdays(territory)
        assert {:error, %ArgumentError{}} = Tempo.weekends(territory)
      end
    end

    test "wrong-type arguments are errors, not raises" do
      for value <- [nil, "", :"", "2026-06-12", 42, %{}, [1, 2]] do
        assert {:error, %ArgumentError{}} = Tempo.add_workdays(value, 1, :US)
        assert {:error, %ArgumentError{}} = Tempo.next_workday(value, :US)
        assert {:error, %ArgumentError{}} = Tempo.previous_workday(value, :US)
        assert {:error, %ArgumentError{}} = Tempo.nearest_workday(value, :US)
        assert {:error, _reason} = Tempo.count_workdays(value, :US)
      end

      for count <- [nil, 1.5, "1", :one] do
        assert {:error, %ArgumentError{} = error} = Tempo.add_workdays(~o"2026-06-12", count, :US)
        assert Exception.message(error) =~ "counts whole workdays"
      end
    end

    test "arithmetic is calendar-correct (steps land on the right absolute day)" do
      iso = fn t ->
        Date.convert!(
          Date.new!(t.time[:year], t.time[:month], t.time[:day], t.calendar),
          Calendar.ISO
        )
      end

      for calendar <- @calendars do
        # Friday 2026-06-12 in each calendar; +1 workday (US) is Monday 06-15.
        friday = Tempo.from_date(Date.convert!(~D[2026-06-12], calendar))
        result = Tempo.add_workdays(friday, 1, :US)
        assert iso.(result) == ~D[2026-06-15], "#{inspect(calendar)} Fri + 1 workday"
      end
    end
  end
end
