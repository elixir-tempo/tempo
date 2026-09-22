defmodule Tempo.Event.ResolverTest do
  # async: false — the test registers a resolver in application env, which is
  # global; it is restored on exit.
  use ExUnit.Case, async: false

  import Tempo.Sigils

  alias Tempo.Event
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

  describe "a registered event as a (name)E selection" do
    test "materialises against a bound like a built-in event" do
      {:ok, recurrence} = Tempo.from_iso8601("R/../P1Y/FL(fiscal-year-start)EN")
      {:ok, set} = Tempo.to_interval(recurrence, bound: ~o"2026")

      assert [interval] = IntervalSet.to_list(set)
      assert Interval.from(interval) == ~o"2026Y4M1D"
    end

    test "yields zero occurrences for a year the resolver reports it cannot compute" do
      {:ok, recurrence} = Tempo.from_iso8601("R/../P1Y/FL(fiscal-year-start)EN")
      {:ok, set} = Tempo.to_interval(recurrence, bound: ~o"1999")

      assert IntervalSet.to_list(set) == []
    end
  end

  describe "an event no resolver claims" do
    test "is a clean unknown-event error" do
      assert Event.date("brigadoon", 2026) == {:error, {:unknown_event, "brigadoon"}}
    end

    test "yields zero occurrences rather than raising" do
      {:ok, recurrence} = Tempo.from_iso8601("R/../P1Y/FL(brigadoon)EN")
      assert {:ok, set} = Tempo.to_interval(recurrence, bound: ~o"2026")
      assert IntervalSet.to_list(set) == []
    end
  end
end
