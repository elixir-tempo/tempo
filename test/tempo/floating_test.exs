defmodule Tempo.FloatingTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Allen

  doctest Tempo, only: [floating?: 1, grounded?: 1, in_zone: 2]

  describe "floating?/1 and grounded?/1" do
    test "a value with no zone or offset is floating" do
      assert Tempo.floating?(~o"2024-01-01")
      refute Tempo.grounded?(~o"2024-01-01")
    end

    test "a value with an IANA zone is grounded" do
      refute Tempo.floating?(~o"2024-01-01[Australia/Sydney]")
      assert Tempo.grounded?(~o"2024-01-01[Australia/Sydney]")
    end

    test "a value with a Z offset is grounded" do
      refute Tempo.floating?(~o"2024-01-01T00:00:00Z")
      assert Tempo.grounded?(~o"2024-01-01T00:00:00Z")
    end

    test "a value with a numeric offset is grounded" do
      refute Tempo.floating?(~o"2024-01-01T00:00:00+11:00")
      assert Tempo.grounded?(~o"2024-01-01T00:00:00+11:00")
    end
  end

  describe "in_zone/2 grounds a floating value" do
    test "attaches the zone without changing the wall clock" do
      floating = ~o"2024-01-01T09:00"
      assert {:ok, grounded} = Tempo.in_zone(floating, "Australia/Sydney")

      assert grounded.extended.zone_id == "Australia/Sydney"
      assert Keyword.take(grounded.time, [:hour, :minute]) == [hour: 9, minute: 0]
      assert Tempo.grounded?(grounded)
    end

    test "the grounded result compares equal to the parsed zoned literal" do
      {:ok, grounded} = Tempo.in_zone(~o"2024-01-01", "Australia/Sydney")
      assert Tempo.relation(grounded, ~o"2024-01-01[Australia/Sydney]") == :equals
    end

    test "rejects an already-grounded value — use shift_zone/2 to move it" do
      assert {:error, %Tempo.GroundedTempoError{}} =
               Tempo.in_zone(~o"2024-01-01[Australia/Sydney]", "Europe/Paris")
    end

    test "rejects an unknown zone" do
      assert {:error, %Tempo.UnknownZoneError{}} =
               Tempo.in_zone(~o"2024-01-01", "Not/AZone")
    end
  end

  describe "comparing a floating value with a grounded one raises" do
    setup do
      %{floating: ~o"2024-01-01", grounded: ~o"2024-01-01[Australia/Sydney]"}
    end

    test "relation/2 raises", %{floating: f, grounded: g} do
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.relation(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.relation(g, f) end
    end

    test "the relation predicates raise", %{floating: f, grounded: g} do
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.before?(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.after?(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Allen.during?(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Allen.meets?(f, g) end
    end

    test "the set-theoretic predicates raise", %{floating: f, grounded: g} do
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.overlaps?(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.disjoint?(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.contains?(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.within?(f, g) end
    end

    test "the certainty API raises", %{floating: f, grounded: g} do
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.overlap_certainty(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.within_certainty(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.certainly_overlaps?(f, g) end
      assert_raise Tempo.FloatingTempoError, fn -> Tempo.possibly_overlaps?(f, g) end
    end
  end

  describe "fixed-offset comparison honours the offset (regression)" do
    test "same wall clock, different offsets are different instants" do
      a = ~o"2026-04-15T10:30:00+05:30"
      b = ~o"2026-04-15T10:30:00+09:00"
      # b is 3.5h earlier in UTC, so it precedes a.
      assert Tempo.relation(a, b) == :preceded_by
      assert Tempo.relation(b, a) == :precedes
    end

    test "same wall clock and same offset are equal" do
      assert Tempo.relation(~o"2026-04-15T10:30:00+05:30", ~o"2026-04-15T10:30:00+05:30") ==
               :equals
    end

    test "Z and +00:00 name the same instant" do
      assert Tempo.relation(~o"2026-04-15T10:30:00Z", ~o"2026-04-15T10:30:00+00:00") == :equals
    end
  end

  describe "comparisons within a single frame are unaffected" do
    test "two floating values compare structurally" do
      assert Tempo.relation(~o"2024-01-01", ~o"2024-06-01") == :precedes
      assert Tempo.before?(~o"2024-01-01", ~o"2024-06-01")
    end

    test "two grounded values compare via their instants" do
      a = ~o"2024-01-01[Australia/Sydney]"
      b = ~o"2024-06-01[Australia/Sydney]"
      assert Tempo.relation(a, b) == :precedes
    end

    test "grounding a floating value makes it comparable again" do
      {:ok, grounded} = Tempo.in_zone(~o"2024-01-01", "Australia/Sydney")
      assert Tempo.relation(grounded, ~o"2024-06-01[Australia/Sydney]") == :precedes
    end
  end
end
