defmodule Tempo.Event.ResolverTest do
  # async: false — the test registers a resolver in application env, which is
  # global; it is restored on exit.
  use ExUnit.Case, async: false

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.Event
  alias Tempo.EventError
  alias Tempo.Interval
  alias Tempo.IntervalSet

  defmodule FiscalEvents do
    @moduledoc false
    @behaviour Tempo.Event.Resolver

    @impl true
    def known, do: ["fiscal-year-start", "fiscal-q3"]

    @impl true
    def date(_name, year, _calendar) when year < 2000, do: {:error, :before_fiscal_epoch}
    def date("fiscal-year-start", year, _calendar), do: Date.new(year, 4, 1)
    def date("fiscal-q3", year, _calendar), do: Date.new(year, 10, 1)
    def date(_name, _year, _calendar), do: {:error, :unknown_event}
  end

  setup do
    Application.put_env(:ex_tempo, :event_resolvers, [FiscalEvents])
    on_exit(fn -> Application.delete_env(:ex_tempo, :event_resolvers) end)
    :ok
  end

  describe "a registered Tempo.Event.Resolver" do
    test "resolves the events it claims" do
      assert Event.date("fiscal-year-start", 2026) == {:ok, ~D[2026-04-01]}
      assert Event.date("fiscal-q3", 2026) == {:ok, ~D[2026-10-01]}
    end

    test "adds its names to known/0 without displacing the built-ins" do
      assert "fiscal-year-start" in Event.known()
      assert "easter" in Event.known()
      assert "qingming" in Event.known()
    end

    test "leaves the built-in events unchanged" do
      assert Event.date("easter", 2026) == {:ok, ~D[2026-04-05]}
    end

    test "surfaces its own error for a year it cannot compute" do
      assert Event.date("fiscal-year-start", 1999) == {:error, :before_fiscal_epoch}
    end
  end

  describe "a registered event as a (name)e selection" do
    test "materialises against a bound like a built-in event" do
      {:ok, recurrence} = Tempo.from_iso8601("R/../P1Y/FL(fiscal-year-start)eN")
      {:ok, set} = Tempo.to_interval(recurrence, within: ~o"2026")

      assert [interval] = IntervalSet.members(set)
      assert Interval.from(interval) == ~o"2026Y4M1D"
    end

    test "returns the resolver's reason for a year it reports it cannot compute" do
      {:ok, recurrence} = Tempo.from_iso8601("R/../P1Y/FL(fiscal-year-start)eN")

      assert Tempo.to_interval(recurrence, within: ~o"1999") ==
               {:error,
                %EventError{event: "fiscal-year-start", year: 1999, reason: :before_fiscal_epoch}}
    end

    test "is read when its name holds a digit" do
      {:ok, recurrence} = Tempo.from_iso8601("R/../P1Y/FL(fiscal-q3)eN")
      {:ok, set} = Tempo.to_interval(recurrence, within: ~o"2026")

      assert [interval] = IntervalSet.members(set)
      assert Interval.from(interval) == ~o"2026Y10M1D"
    end

    test "is asked for the Gregorian years a year of another calendar runs through" do
      # The Hebrew year 5786 runs from 23 September 2025 to 11 September 2026:
      # the fiscal year that starts in it is 2026's, and its third quarter is
      # 2025's, which starts on 1 October.
      hebrew_year = Tempo.from_iso8601!("5786Y", Hebrew)

      for {event, date} <- [{"fiscal-year-start", ~D[2026-04-01]}, {"fiscal-q3", ~D[2025-10-01]}] do
        {:ok, recurrence} = Tempo.from_iso8601("R/../P1Y/FL(#{event})eN", Hebrew)
        {:ok, set} = Tempo.to_interval(recurrence, within: hebrew_year)

        assert [interval] = IntervalSet.members(set)
        assert Tempo.to_date(Interval.from(interval)) == {:ok, Date.convert!(date, Hebrew)}
      end
    end
  end

  describe "an event no resolver claims" do
    test "is a clean unknown-event error" do
      assert Event.date("brigadoon", 2026) == {:error, {:unknown_event, "brigadoon"}}
    end

    test "is an error where a recurrence asks for it" do
      {:ok, recurrence} = Tempo.from_iso8601("R/../P1Y/FL(brigadoon)eN")

      assert Tempo.to_interval(recurrence, within: ~o"2026") ==
               {:error, %EventError{event: "brigadoon", reason: :unknown_event}}
    end
  end
end
