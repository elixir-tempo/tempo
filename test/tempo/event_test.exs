defmodule Tempo.EventTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Calendrical.Lunisolar
  alias Tempo.Event
  alias Tempo.EventError
  alias Tempo.Interval
  alias Tempo.IntervalSet

  doctest Tempo.Event

  describe "Tempo.Event.date/2" do
    test "resolves Easter and the astronomical events for 2026" do
      assert Event.date("easter", 2026) == {:ok, ~D[2026-04-05]}
      assert Event.date("march-equinox", 2026) == {:ok, ~D[2026-03-20]}
      assert Event.date("june-solstice", 2026) == {:ok, ~D[2026-06-21]}
      assert Event.date("september-equinox", 2026) == {:ok, ~D[2026-09-23]}
      assert Event.date("december-solstice", 2026) == {:ok, ~D[2026-12-21]}
    end

    test "resolves the 24 solar terms via Calendrical (Chinese meridian)" do
      assert Event.date("qingming", 2026) == {:ok, ~D[2026-04-05]}
      assert Event.date("lichun", 2026) == {:ok, ~D[2026-02-04]}
      assert Event.date("dongzhi", 2026) == {:ok, ~D[2026-12-22]}
      # The cardinal terms coincide with the equinoxes and solstices.
      assert Event.date("chunfen", 2026) == {:ok, ~D[2026-03-20]}
      assert Event.date("chunfen", 2026) == Event.date("march-equinox", 2026)
    end

    # A solar term is the day the sun reaches a longitude, at a meridian, so
    # its day differs between the calendars that observe it. The measure is
    # Calendrical's own answer for each calendar's own place: Tempo holds
    # neither the longitudes nor the meridians (it held a table of the
    # first, and named three of the calendars).
    test "a solar term is the day the value's own calendar observes it on" do
      calendars =
        [Calendrical.Chinese, Calendrical.Korean, Calendrical.Vietnamese] ++
          [Calendrical.LunarJapanese]

      names =
        for number <- 1..24,
            {:ok, name} = Lunisolar.solar_term_name(number),
            do: {name, number}

      for calendar <- calendars, year <- [1999, 2002, 2026], {name, number} <- names do
        {:ok, observed} = Lunisolar.solar_term(number, year, &calendar.location/1)

        assert {calendar, year, name, Event.date(name, year, calendar)} ==
                 {calendar, year, name, Date.convert(observed, Calendar.ISO)}
      end

      # The seventh term of 2002 is a day earlier at the Vietnamese meridian.
      {:ok, lixia} = Lunisolar.solar_term_name(7)

      assert Enum.map(calendars, &Event.date(lixia, 2002, &1)) ==
               [{:ok, ~D[2002-05-06]}, {:ok, ~D[2002-05-06]}, {:ok, ~D[2002-05-05]}] ++
                 [{:ok, ~D[2002-05-06]}]
    end

    test "the solar terms Tempo knows are the ones Calendrical names" do
      names =
        for number <- 1..24, {:ok, name} = Lunisolar.solar_term_name(number), do: name

      assert Enum.filter(Event.known(), &Event.solar_term?/1) == Enum.sort(names)
      assert Lunisolar.solar_term_name(25) == {:error, {:invalid_solar_term, 25}}
    end

    test "a solar term can be computed for another lunisolar meridian" do
      # `date/3` picks the meridian; Chinese is the default. The four resolve
      # (they coincide for Qingming 2026, differing only when a term falls near
      # local midnight).
      assert Event.date("qingming", 2026, Calendrical.Chinese) == Event.date("qingming", 2026)
      assert {:ok, %Date{}} = Event.date("qingming", 2026, Calendrical.Vietnamese)
      assert {:ok, %Date{}} = Event.date("qingming", 2026, Calendrical.Korean)
      assert {:ok, %Date{}} = Event.date("qingming", 2026, Calendrical.LunarJapanese)
    end

    test "resolves the first new moon of the year via Astro" do
      assert Event.date("new-moon", 2026) == {:ok, ~D[2026-01-18]}
    end

    test "known/0 lists Easter (Western + Orthodox), the astronomical events, and the 24 solar terms" do
      assert Enum.count(Event.known()) == 31
      assert "orthodox-easter" in Event.known()
      assert "new-moon" in Event.known()
      assert Event.solar_term?("qingming")
      refute Event.solar_term?("easter")
    end

    test "an unknown event is a clean error, not a crash" do
      assert Event.date("brigadoon", 2026) == {:error, {:unknown_event, "brigadoon"}}
    end

    test "an astronomical event outside Astro's range is an error" do
      assert Event.date("march-equinox", 500) == {:error, :year_out_of_range}
    end

    test "an equinox or solstice takes its date in a named zone" do
      # The 2002 March equinox was at 19:16 UTC on the 20th, 04:16 on the 21st
      # in Tokyo; the 2021 June solstice at 03:32 UTC on the 21st, 23:32 on the
      # 20th in Santiago.
      assert Event.date("march-equinox@+09:00", 2002) == {:ok, ~D[2002-03-21]}
      assert Event.date("march-equinox", 2002) == {:ok, ~D[2002-03-20]}
      assert Event.date("june-solstice@America/Santiago", 2021) == {:ok, ~D[2021-06-20]}
      assert Event.date("june-solstice", 2021) == {:ok, ~D[2021-06-21]}
    end

    test "a zone on an event with no instant, or a zone that is not one, is an error" do
      assert Event.date("easter@+09:00", 2026) == {:error, {:unzoned_event, "easter"}}
      assert Event.date("march-equinox@+9:00", 2026) == {:error, {:invalid_zone, "+9:00"}}

      assert Event.date("march-equinox@Nowhere/City", 2026) ==
               {:error, {:invalid_zone, "Nowhere/City"}}
    end
  end

  describe "computed-event selection — parsing and round-trip" do
    test "the (name)e form parses to an :event selection token" do
      assert {:ok, value} = Tempo.from_iso8601("R/../P1Y/FL(easter)eN")
      assert value.repeat_rule.time == [selection: [event: "easter"]]
    end

    test "an event in a zone parses and round-trips" do
      for iso <- [
            "R/../P1Y/FL(march-equinox@+09:00)eN",
            "R/../P1Y/FL(june-solstice@America/Santiago)eN"
          ] do
        {:ok, value} = Tempo.from_iso8601(iso)
        assert Tempo.to_iso8601!(value) == iso
      end
    end

    test "an event's name is a letter, then letters, digits and hyphens" do
      for iso <- ["R/../P1Y/FL(fiscal-q3)eN", "2026YL(fiscal-q3)eN", "R/../P1Y/FL(q)eN"] do
        {:ok, value} = Tempo.from_iso8601(iso)
        assert Tempo.to_iso8601!(value) == iso
      end

      {:ok, value} = Tempo.from_iso8601("R/../P1Y/FL(fiscal-q3)eN")
      assert value.repeat_rule.time == [selection: [event: "fiscal-q3"]]

      for iso <- ["R/../P1Y/FL(3q)eN", "R/../P1Y/FL(-q)eN", "R/../P1Y/FL()eN"] do
        assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601(iso)
      end
    end

    test "a hyphenated event name round-trips through to_iso8601/1 and inspect/1" do
      {:ok, value} = Tempo.from_iso8601("R/../P1Y/FL(march-equinox)eN")

      assert Tempo.to_iso8601!(value) == "R/../P1Y/FL(march-equinox)eN"
      assert inspect(value) == ~s|~o"R/../P1Y/FL(march-equinox)eN"|
      assert Tempo.from_iso8601(Tempo.to_iso8601!(value)) == {:ok, value}
    end
  end

  describe "computed-event recurrence — materialisation" do
    test "each event resolves to its date within the bound" do
      assert event_dates("R/../P1Y/FL(easter)eN") == ["2026-04-05"]
      assert event_dates("R/../P1Y/FL(march-equinox)eN") == ["2026-03-20"]
      assert event_dates("R/../P1Y/FL(june-solstice)eN") == ["2026-06-21"]
      assert event_dates("R/../P1Y/FL(september-equinox)eN") == ["2026-09-23"]
      assert event_dates("R/../P1Y/FL(december-solstice)eN") == ["2026-12-21"]
    end

    test "a multi-year bound yields one occurrence per year" do
      {:ok, rule} = Tempo.from_iso8601("R/../P1Y/FL(easter)eN")
      {:ok, set} = Tempo.to_interval(rule, within: ~o"{2026..2028}Y")

      dates =
        set
        |> IntervalSet.members()
        |> Enum.map(fn interval ->
          {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
          Date.to_iso8601(date)
        end)

      # Easter moves each year: 2026-04-05, 2027-03-28, 2028-04-16.
      assert dates == ["2026-04-05", "2027-03-28", "2028-04-16"]
    end

    test "an event in a zone lands on its date there" do
      assert event_dates("R/../P1Y/FL(march-equinox@+09:00)eN", ~o"2002Y") == ["2002-03-21"]

      assert event_dates("R/../P1Y/FL(june-solstice@America/Santiago)eN", ~o"2021Y") ==
               ["2021-06-20"]
    end
  end

  describe "a computed event that has no date where it is asked for" do
    # No occurrence would say that the event did not happen, so each is an
    # error that names the event and the year.
    defp no_date(iso, options) do
      {:ok, rule} = Tempo.from_iso8601(iso)
      Tempo.to_interval(rule, options)
    end

    test "is an error for a name no resolver knows" do
      unknown = %EventError{event: "brigadoon", reason: :unknown_event}

      assert no_date("R/../P1Y/FL(brigadoon)eN", within: ~o"2026Y") == {:error, unknown}
      assert no_date("R/../P1M/FL(brigadoon)eN", within: ~o"2026Y") == {:error, unknown}
      assert no_date("R/../P1D/FL(brigadoon)eN", within: ~o"2026Y4M") == {:error, unknown}
      assert no_date("2026YL(brigadoon)eN", []) == {:error, unknown}
      assert Tempo.select(~o"2026Y", ~o"L(brigadoon)eN") == {:error, unknown}
      assert Tempo.select(~o"2026-04-05", ~o"L(brigadoon)eN") == {:error, unknown}

      # A window on the event has no start.
      assert no_date("R/../P1Y/FLLL(brigadoon)eN/-P7DN5K-1IN", within: ~o"2026Y") ==
               {:error, unknown}

      assert Exception.message(unknown) =~ ~s(No computed event is named "brigadoon")
    end

    test "is an error for a year the event is not computed for" do
      # Astro computes an equinox from 1000 CE to 3000 CE.
      out_of_range = fn year ->
        %EventError{event: "march-equinox", year: year, reason: :year_out_of_range}
      end

      assert no_date("R/../P1Y/FL(march-equinox)eN", within: ~o"0500Y") ==
               {:error, out_of_range.(500)}

      assert no_date("R2/0500Y/P1Y/FL(march-equinox)eN", []) == {:error, out_of_range.(500)}
      assert no_date("0500YL(march-equinox)eN", []) == {:error, out_of_range.(500)}
      assert Tempo.select(~o"0500Y", ~o"L(march-equinox)eN") == {:error, out_of_range.(500)}

      # A window that reaches a year with no date has no answer.
      assert no_date("R/../P1Y/FL(march-equinox)eN", within: ~o"0999Y/1002Y") ==
               {:error, out_of_range.(999)}

      assert no_date("R5/2998Y/P1Y/FL(march-equinox)eN", []) == {:error, out_of_range.(3001)}

      assert Exception.message(out_of_range.(500)) =~
               ~s(The event "march-equinox" cannot be computed for the year 500)
    end

    test "is no error in the first and the last year the event is computed for" do
      assert event_dates("R/../P1Y/FL(march-equinox)eN", ~o"1000Y") == ["1000-03-20"]
      assert event_dates("R/../P1Y/FL(march-equinox)eN", ~o"3000Y") == ["3000-03-20"]

      # A counted recurrence that ends in range never asks for the year after.
      {:ok, set} = no_date("R3/2998Y/P1Y/FL(march-equinox)eN", [])
      assert IntervalSet.count(set) == 3
    end

    test "is an error for a zone the event cannot take a date in" do
      assert no_date("R/../P1Y/FL(easter@+09:00)eN", within: ~o"2026Y") ==
               {:error, %EventError{event: "easter@+09:00", reason: :unzoned_event}}

      assert no_date("R/../P1Y/FL(march-equinox@Nowhere/City)eN", within: ~o"2026Y") ==
               {:error,
                %EventError{
                  event: "march-equinox@Nowhere/City",
                  year: 2026,
                  reason: {:invalid_zone, "Nowhere/City"}
                }}
    end

    test "is raised by a walk" do
      assert_raise EventError, ~r/cannot be computed for the year 500/, fn ->
        Enum.to_list(~o"R2/0500Y/P1Y/FL(march-equinox)eN")
      end
    end

    test "is raised by a walk with no end when it reaches the year, and not before" do
      for cadence <- ["P1Y", "P1D"] do
        {:ok, equinoxes} = no_date("R/../#{cadence}/FL(march-equinox)eN", within: ~o"2996Y/..")
        years = fn occurrences -> Enum.map(occurrences, &Tempo.year(Interval.from(&1))) end

        # Every equinox to the last year one is computed for.
        assert equinoxes |> IntervalSet.walk() |> Enum.take(5) |> years.() ==
                 [2996, 2997, 2998, 2999, 3000]

        assert_raise EventError, ~r/cannot be computed for the year 3001/, fn ->
          equinoxes |> IntervalSet.walk() |> Enum.take(6)
        end
      end
    end
  end

  describe "a weekday limit on a computed event" do
    test "parses and round-trips rather than raising" do
      assert {:ok, value} = Tempo.from_iso8601("R/../P1Y/FL(qingming)e7KN")
      assert Tempo.to_iso8601!(value) == "R/../P1Y/FL(qingming)e7KN"
    end

    test "keeps the event only in the years it falls on the weekday" do
      # Qingming falls on 2021-04-04 and 2026-04-05, both Sundays; 2022–2025 and
      # 2027 fall on other weekdays.
      assert event_dates("R/../P1Y/FL(qingming)e7KN", ~o"{2021..2027}Y") ==
               ["2021-04-04", "2026-04-05"]
    end

    test "limits the event's day rather than expanding to every such weekday" do
      # Easter is always a Sunday: a Sunday limit keeps each Easter, a Monday
      # limit none — neither expands to the year's other Sundays or Mondays.
      assert event_dates("R/../P1Y/FL(easter)e7KN", ~o"{2026..2028}Y") ==
               ["2026-04-05", "2027-03-28", "2028-04-16"]

      assert event_dates("R/../P1Y/FL(easter)e1KN", ~o"{2026..2028}Y") == []
    end

    test "a weekday set limits to any of its weekdays" do
      assert event_dates("R/../P1Y/FL(qingming)e{6,7}KN", ~o"{2021..2027}Y") ==
               ["2021-04-04", "2026-04-05"]
    end

    test "a day of month after an event is an ordering error, not a raise" do
      assert {:error, _reason} = Tempo.from_iso8601("R/../P1Y/FL(easter)e5DN")
    end
  end

  describe "a computed event in a period" do
    # An event is each of its days that falls in the period: a year, a month
    # or a week. The measure is the event's date in each year, from
    # `Tempo.Event.date/2`, placed in its month by its own fields and in its
    # ISO 8601 week by `:calendar.iso_week_number/1`.
    @in_periods ~w(easter orthodox-easter new-moon december-solstice qingming)

    defp selected(span, event) do
      {:ok, set} = Tempo.select(span, Tempo.from_iso8601!("L(#{event})eN"))

      for interval <- IntervalSet.members(set) do
        {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
        date
      end
    end

    test "is selected from the month it falls in, and from no other" do
      for event <- @in_periods, year <- 2024..2030, month <- 1..12 do
        {:ok, date} = Event.date(event, year)
        in_the_month = if date.month == month, do: [date], else: []

        assert {event, year, month, selected(Tempo.from_iso8601!("#{year}Y#{month}M"), event)} ==
                 {event, year, month, in_the_month}
      end
    end

    test "is selected from the week it falls in, and from neither week beside it" do
      for event <- @in_periods, year <- 2024..2030 do
        {:ok, date} = Event.date(event, year)
        {week_year, week} = :calendar.iso_week_number(Date.to_erl(date))
        its_week = Tempo.from_iso8601!("#{week_year}Y#{week}W")

        assert {event, year, selected(its_week, event)} == {event, year, [date]}

        for beside <- [Tempo.shift(its_week, week: -1), Tempo.shift(its_week, week: 1)] do
          assert {event, year, selected(beside, event)} == {event, year, []}
        end
      end
    end

    test "is listed by a recurrence that steps by months or by weeks" do
      for event <- @in_periods, cadence <- ["P1M", "P1W"] do
        expected = for year <- 2024..2030, {:ok, date} <- [Event.date(event, year)], do: date

        assert {event, cadence, event_dates("R/../#{cadence}/FL(#{event})eN", ~o"2024Y/2031Y")} ==
                 {event, cadence, Enum.map(expected, &Date.to_iso8601/1)}
      end
    end

    test "is the Easter of each month that has one, counted from a start" do
      {:ok, set} = Tempo.to_interval(~o"R2/2026-01-05/P1M/FL(easter)eN")

      assert Enum.map(IntervalSet.members(set), &Interval.from/1) ==
               [~o"2026-04-05", ~o"2027-03-28"]
    end

    test "is limited by a weekday beside it" do
      assert event_dates("R/../P1M/FL(easter)e7KN", ~o"2026Y/2029Y") ==
               ["2026-04-05", "2027-03-28", "2028-04-16"]

      assert event_dates("R/../P1M/FL(easter)e1KN", ~o"2026Y/2029Y") == []
      assert event_dates("R/../P1W/FL(easter)e7KN", ~o"2026Y") == ["2026-04-05"]
      assert event_dates("R/../P1W/FL(easter)e1KN", ~o"2026Y") == []
    end

    test "keeps a day that is its day, and a period finer than a day on it" do
      assert selected(~o"2026-04-05", "easter") == [~D[2026-04-05]]
      assert selected(~o"2026-04-06", "easter") == []
      assert event_dates("R/../P1D/FL(easter)eN", ~o"2026Y") == ["2026-04-05"]
    end
  end

  describe "computed-event recurrence — explain/1" do
    test "reads the event as prose" do
      assert Tempo.explain(~o"R/../P1Y/FL(easter)eN") =~ "on Easter"
      assert Tempo.explain(~o"R/../P1Y/FL(march-equinox)eN") =~ "on the March equinox"
      assert Tempo.explain(~o"R/../P1Y/FL(december-solstice)eN") =~ "on the December solstice"

      assert Tempo.explain(~o"R/../P1Y/FL(march-equinox@+09:00)eN") =~
               "on the March equinox in +09:00"
    end
  end

  # Materialise a computed-event recurrence into a bound (2026 by default) and
  # list the ISO dates.
  defp event_dates(iso, bound \\ ~o"2026Y") do
    {:ok, rule} = Tempo.from_iso8601(iso)
    {:ok, set} = Tempo.to_interval(rule, within: bound)

    set
    |> IntervalSet.members()
    |> Enum.map(fn interval ->
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      Date.to_iso8601(date)
    end)
  end
end
