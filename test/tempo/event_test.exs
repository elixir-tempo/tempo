defmodule Tempo.EventTest do
  # A resolver is registered in the application's environment, so these
  # tests do not run beside one another.
  use ExUnit.Case, async: false

  import Tempo.Sigils

  alias Tempo.{Event, Interval, IntervalSet, InvalidDateError, ZoneError}

  defmodule FiscalEvents do
    @behaviour Tempo.Event.Resolver

    @impl true
    def known, do: ["fiscal-year-start", "not-a-date", "refused"]

    @impl true
    def date("fiscal-year-start", year, _calendar), do: Date.new(year, 4, 1)
    def date("not-a-date", _year, _calendar), do: :tomorrow
    def date("refused", _year, _calendar), do: {:error, :closed}
  end

  # Dates of the computus and of the sky, from published tables.

  describe "the feasts" do
    test "Easter, by the Gregorian and by the Julian reckoning" do
      assert Event.date("easter", 2024) == {:ok, ~D[2024-03-31]}
      assert Event.date("easter", 2025) == {:ok, ~D[2025-04-20]}
      assert Event.date("easter", 2026) == {:ok, ~D[2026-04-05]}

      assert Event.date("orthodox-easter", 2024) == {:ok, ~D[2024-05-05]}
      assert Event.date("orthodox-easter", 2025) == {:ok, ~D[2025-04-20]}
      assert Event.date("orthodox-easter", 2026) == {:ok, ~D[2026-04-12]}
    end
  end

  describe "the sky" do
    test "the equinoxes and the solstices, on their date in UTC" do
      assert Event.date("march-equinox", 2026) == {:ok, ~D[2026-03-20]}
      assert Event.date("june-solstice", 2026) == {:ok, ~D[2026-06-21]}
      assert Event.date("september-equinox", 2026) == {:ok, ~D[2026-09-23]}
      assert Event.date("december-solstice", 2026) == {:ok, ~D[2026-12-21]}
    end

    test "an instant falls on the date of the zone it is asked in" do
      # The September equinox of 2026 is at 00:05 UTC on the 23rd.
      assert Event.date("september-equinox@Pacific/Auckland", 2026) == {:ok, ~D[2026-09-23]}
      assert Event.date("september-equinox@America/Los_Angeles", 2026) == {:ok, ~D[2026-09-22]}
      assert Event.date("september-equinox@-08:00", 2026) == {:ok, ~D[2026-09-22]}
      assert Event.date("march-equinox@+09:00", 2002) == {:ok, ~D[2002-03-21]}
    end

    test "the first new moon of a year" do
      assert Event.date("new-moon", 2026) == {:ok, ~D[2026-01-18]}
    end

    test "what has no instant, a zone that is none and a year out of reach are errors" do
      assert {:error, %InvalidDateError{unit: :event, reason: {:no_instant, "easter"}}} =
               Event.date("easter@+09:00", 2026)

      assert {:error, %InvalidDateError{reason: {:unknown_event, "brigadoon"}}} =
               Event.date("brigadoon@+09:00", 2026)

      assert {:error, %ZoneError{zone: "Mars/Olympus", reason: :unknown}} =
               Event.date("march-equinox@Mars/Olympus", 2026)

      assert {:error, %ZoneError{zone: "+99:00"}} = Event.date("march-equinox@+99:00", 2026)

      assert {:error, %InvalidDateError{reason: :year_out_of_range} = error} =
               Event.date("march-equinox", 99_999)

      assert Exception.message(error) =~ "astronomy does not reach"
    end
  end

  describe "the solar terms" do
    test "there are twenty-four, and each is one" do
      terms = Enum.filter(Event.known(), &Event.solar_term?/1)
      assert Enum.count_until(terms, 25) == 24
      assert "qingming" in terms
      refute Event.solar_term?("easter")
    end

    test "a term is the day a calendar reckons it" do
      assert Event.date("qingming", 2026) == {:ok, ~D[2026-04-05]}
      assert Event.date("qingming", 2026, Calendrical.Chinese) == {:ok, ~D[2026-04-05]}
      assert Event.date("dongzhi", 2026) == {:ok, ~D[2026-12-22]}
    end

    test "a module that is no calendar reckons none" do
      assert {:error, %InvalidDateError{reason: {:no_solar_terms, String}}} =
               Event.date("qingming", 2026, String)
    end
  end

  describe "an event in an expression" do
    test "is selected in each year, and recurs" do
      assert Tempo.select(~o"2026", Tempo.selection!(event: "june-solstice")) ==
               {:ok, ~o"{2026-06-21}"}

      {:ok, easters} =
        ~o"P1Y"
        |> Tempo.every!(select: [event: "easter"])
        |> Tempo.to_interval(within: ~o"2024/2026")

      assert IntervalSet.map(easters, &Interval.from/1) ==
               [~o"2024-03-31", ~o"2025-04-20", ~o"2026-04-05"]
    end

    test "a name no resolver knows is refused when it is read" do
      assert {:error, %Tempo.InvalidDateError{reason: {:unknown_event, "brigadoon"}}} =
               Tempo.from_iso8601("R/../P1Y/FL(brigadoon)eN")
    end
  end

  describe "a resolver of the application's own events" do
    setup do
      Application.put_env(:ex_tempo, :event_resolvers, [FiscalEvents])
      on_exit(fn -> Application.delete_env(:ex_tempo, :event_resolvers) end)
    end

    test "computes the names it knows" do
      assert Event.date("fiscal-year-start", 2026) == {:ok, ~D[2026-04-01]}
    end

    test "its own error is returned, and an answer that is no date is one" do
      assert {:error, %InvalidDateError{value: "refused", reason: :closed}} =
               Event.date("refused", 2026)

      assert {:error, %InvalidDateError{reason: {:not_a_date, :tomorrow}}} =
               Event.date("not-a-date", 2026)
    end

    test "a name it does not know is still unknown" do
      assert {:error, %InvalidDateError{reason: {:unknown_event, "brigadoon"}}} =
               Event.date("brigadoon", 2026)
    end
  end
end
