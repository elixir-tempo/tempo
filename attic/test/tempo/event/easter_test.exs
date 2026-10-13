defmodule Tempo.Event.EasterTest do
  use ExUnit.Case

  alias Tempo.Event
  alias Tempo.GregorianEasterTest

  # Western Easter is resolved through `Calendrical.Ecclesiastical`; this
  # exercises it against the full table of known Gregorian Easter dates.
  for [year, month, day] <- GregorianEasterTest.data() do
    test "Western Easter for the year #{year}" do
      assert Event.date("easter", unquote(year)) ==
               {:ok, Date.new!(unquote(year), unquote(month), unquote(day))}
    end
  end

  test "Orthodox Easter is the same computus in the Julian calendar" do
    # 2026: Western Easter is April 5; Orthodox (Julian) falls on April 12.
    assert Event.date("orthodox-easter", 2026) == {:ok, ~D[2026-04-12]}

    # In some years the two coincide (2025: both April 20).
    assert Event.date("orthodox-easter", 2025) == Event.date("easter", 2025)
    assert Event.date("easter", 2025) == {:ok, ~D[2025-04-20]}
  end
end
