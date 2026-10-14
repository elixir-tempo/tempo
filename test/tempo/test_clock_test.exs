defmodule Tempo.TestClockTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Clock
  alias Tempo.Clock.System, as: SystemClock
  alias Tempo.Clock.Test, as: TestClock
  alias Tempo.ClockError

  test "the time pinned is the time the API reads, in any zone" do
    TestClock.put(DateTime.new!(~D[2026-06-15], ~T[14:00:00], "Europe/Paris"))

    assert TestClock.utc_now() == ~U[2026-06-15 12:00:00Z]
    assert Tempo.now("Australia/Sydney") == {:ok, ~o"2026-06-15T22:00:00[Australia/Sydney]"}
    assert Tempo.utc_today() == ~o"2026-06-15"
  end

  test "moved on across midnight, it is tomorrow" do
    TestClock.put(~U[2026-06-15 23:30:00Z])
    TestClock.advance(3600)

    assert Tempo.utc_today() == ~o"2026-06-16"
  end

  test "reset, the process reads the system's clock again" do
    TestClock.put(~U[1999-12-31 23:59:59Z])
    TestClock.reset()

    assert Clock.clock() == SystemClock
    assert Tempo.year(Tempo.utc_now()) > 2025
  end

  test "another process does not see the time pinned in this one" do
    TestClock.put(~U[1999-12-31 23:59:59Z])

    assert Task.await(Task.async(fn -> Clock.clock() end)) == SystemClock
  end

  test "a time asked or moved before one is pinned is a named error" do
    assert_raise ClockError, ~r/no time pinned/, fn -> TestClock.utc_now() end
    assert_raise ClockError, fn -> TestClock.advance(60) end
  end

  test "what is no time and no number of seconds is refused" do
    assert_raise ArgumentError, fn -> TestClock.put(~D[2026-06-15]) end
    assert_raise ArgumentError, fn -> TestClock.advance(1.5) end
  end
end
