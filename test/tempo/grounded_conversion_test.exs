defmodule Tempo.GroundedConversionTest do
  @moduledoc """
  Converting grounded values to Elixir types: UTC offsets and `Z`
  produce DateTimes, zones keep their zone, floating values state why
  they cannot convert, `shift/2` accepts duration strings, and
  negative half-hour offsets project correctly.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  describe "to_elixir/1 on grounded values" do
    test "a UTC offset converts to the instant as a UTC DateTime" do
      # iCalendar DATE-TIMEs commonly carry offsets rather than Z.
      assert Tempo.to_elixir(~o"2026-06-15T09:00:00+10:00") ==
               {:ok, ~U[2026-06-14 23:00:00.000000Z]}
    end

    test "Z converts to the same instant" do
      assert Tempo.to_elixir(~o"2026-06-15T09:00:00Z") == {:ok, ~U[2026-06-15 09:00:00.000000Z]}
    end

    test "a negative half-hour offset projects with the hour's sign on the minutes" do
      # −03:30 is −(3 h 30 m): 09:00 in Newfoundland is 12:30 UTC.
      assert Tempo.to_elixir(~o"2026-06-15T09:00:00-03:30") ==
               {:ok, ~U[2026-06-15 12:30:00.000000Z]}
    end

    test "a zoned value keeps its zone instead of degrading to naive" do
      {:ok, %DateTime{} = date_time} = Tempo.to_elixir(~o"2026-06-15T09:00:00[Australia/Sydney]")

      assert date_time.time_zone == "Australia/Sydney"
      assert date_time.hour == 9
    end

    test "a floating value still converts to NaiveDateTime" do
      assert Tempo.to_elixir(~o"2026-06-15T09:00:00") == {:ok, ~N[2026-06-15 09:00:00.000000]}
    end

    test "to_date_time on a floating value names the problem" do
      {:error, %Tempo.ConversionError{reason: reason}} =
        Tempo.to_date_time(~o"2026-06-15T09:00:00")

      assert reason =~ "floating"
      assert reason =~ "in_zone"
    end
  end

  describe "shift/2 with a duration string" do
    test "an ISO 8601 duration string parses and shifts" do
      assert Tempo.shift(~o"2026Y6M15DT9H0M0SZ", "-PT30M") == ~o"2026Y6M15DT8H30M0SZ"
      assert Tempo.shift(~o"2026-06-15", "P3D") == ~o"2026-06-18"
    end

    test "a non-duration string is refused with direction" do
      assert {:error, %Tempo.ConversionError{reason: reason}} =
               Tempo.shift(~o"2026-06-15", "2027-01-01")

      assert reason =~ "not a duration"
    end

    test "an unparseable string returns the parse error" do
      assert {:error, _reason} = Tempo.shift(~o"2026-06-15", "NOT A DURATION")
    end
  end

  describe "cross-offset instant semantics" do
    test "the same instant at different offsets is equal" do
      assert Tempo.equal?(~o"2026-06-15T09:00:00+05:30", ~o"2026-06-15T03:30:00Z")
      assert Tempo.relation(~o"2026-06-15T09:00:00+05:30", ~o"2026-06-15T03:30:00Z") == :equals
    end

    test "different instants stay unequal" do
      refute Tempo.equal?(~o"2026-06-15T09:00:00+05:30", ~o"2026-06-15T04:30:00Z")
    end

    test "negative offsets with minutes compare on the projected instant" do
      assert Tempo.equal?(~o"2026-06-15T09:00:00-03:30", ~o"2026-06-15T12:30:00Z")
    end
  end
end
