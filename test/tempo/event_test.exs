defmodule Tempo.EventTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Event
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

    test "an unknown event materialises to no occurrences rather than raising" do
      assert event_dates("R/../P1Y/FL(brigadoon)eN") == []
    end

    test "an event in a zone lands on its date there" do
      assert event_dates("R/../P1Y/FL(march-equinox@+09:00)eN", ~o"2002Y") == ["2002-03-21"]

      assert event_dates("R/../P1Y/FL(june-solstice@America/Santiago)eN", ~o"2021Y") ==
               ["2021-06-20"]

      assert event_dates("R/../P1Y/FL(easter@+09:00)eN") == []
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
