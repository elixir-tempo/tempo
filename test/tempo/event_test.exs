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
      assert length(Event.known()) == 31
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
  end

  describe "computed-event selection — parsing and round-trip" do
    test "the (name)E form parses to an :event selection token" do
      assert {:ok, value} = Tempo.from_iso8601("R/../P1Y/FL(easter)EN")
      assert value.repeat_rule.time == [selection: [event: "easter"]]
    end

    test "a hyphenated event name round-trips through to_iso8601/1 and inspect/1" do
      {:ok, value} = Tempo.from_iso8601("R/../P1Y/FL(march-equinox)EN")

      assert Tempo.to_iso8601(value) == "R/../P1Y/FL(march-equinox)EN"
      assert inspect(value) == ~s|~o"R/../P1Y/FL(march-equinox)EN"|
      assert Tempo.from_iso8601(Tempo.to_iso8601(value)) == {:ok, value}
    end
  end

  describe "computed-event recurrence — materialisation" do
    test "each event resolves to its date within the bound" do
      assert event_dates("R/../P1Y/FL(easter)EN") == ["2026-04-05"]
      assert event_dates("R/../P1Y/FL(march-equinox)EN") == ["2026-03-20"]
      assert event_dates("R/../P1Y/FL(june-solstice)EN") == ["2026-06-21"]
      assert event_dates("R/../P1Y/FL(september-equinox)EN") == ["2026-09-23"]
      assert event_dates("R/../P1Y/FL(december-solstice)EN") == ["2026-12-21"]
    end

    test "a multi-year bound yields one occurrence per year" do
      {:ok, rule} = Tempo.from_iso8601("R/../P1Y/FL(easter)EN")
      {:ok, set} = Tempo.to_interval(rule, bound: ~o"{2026..2028}Y")

      dates =
        set
        |> IntervalSet.to_list()
        |> Enum.map(fn interval ->
          {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
          Date.to_iso8601(date)
        end)

      # Easter moves each year: 2026-04-05, 2027-03-28, 2028-04-16.
      assert dates == ["2026-04-05", "2027-03-28", "2028-04-16"]
    end

    test "an unknown event materialises to no occurrences rather than raising" do
      assert event_dates("R/../P1Y/FL(brigadoon)EN") == []
    end
  end

  describe "computed-event recurrence — explain/1" do
    test "reads the event as prose" do
      assert Tempo.explain(~o"R/../P1Y/FL(easter)EN") =~ "on Easter"
      assert Tempo.explain(~o"R/../P1Y/FL(march-equinox)EN") =~ "on the March equinox"
      assert Tempo.explain(~o"R/../P1Y/FL(december-solstice)EN") =~ "on the December solstice"
    end
  end

  # Materialise a computed-event recurrence into 2026 and list the ISO dates.
  defp event_dates(iso) do
    {:ok, rule} = Tempo.from_iso8601(iso)
    {:ok, set} = Tempo.to_interval(rule, bound: ~o"2026Y")

    set
    |> IntervalSet.to_list()
    |> Enum.map(fn interval ->
      {:ok, date} = interval |> Interval.from() |> Tempo.to_date()
      Date.to_iso8601(date)
    end)
  end
end
