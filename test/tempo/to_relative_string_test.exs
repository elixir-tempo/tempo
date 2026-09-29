defmodule Tempo.ToRelativeStringTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Clock.Test

  # Install Tempo.Clock.Test for this test process only. Using
  # `Process.put` (not `Application.put_env`) keeps the swap
  # process-local so it doesn't leak into other async tests or
  # doctests in the same VM.
  setup do
    Process.put({Tempo.Clock, :clock}, Tempo.Clock.Test)
    :ok
  end

  describe "Tempo.to_relative_string/2 — past values" do
    test "yesterday" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-14T12:00:00Z", from: now) ==
               "yesterday"
    end

    test "N days ago" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-10T12:00:00Z", from: now) ==
               "5 days ago"
    end

    test "N hours ago" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-15T09:00:00Z", from: now) ==
               "3 hours ago"
    end

    test "months ago" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      string = Tempo.to_relative_string(~o"2026-03-15T12:00:00Z", from: now)
      assert string =~ "month"
    end
  end

  describe "Tempo.to_relative_string/2 — future values" do
    test "tomorrow" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-16T12:00:00Z", from: now) ==
               "tomorrow"
    end

    test "in N hours" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-15T15:00:00Z", from: now) ==
               "in 3 hours"
    end

    test "in N days" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-20T12:00:00Z", from: now) ==
               "in 5 days"
    end
  end

  describe "Tempo.to_relative_string/2 — the `now` case" do
    test "zero delta renders as 'now'" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-15T12:00:00Z", from: now) == "now"
    end
  end

  describe "locale and format options" do
    test "German locale" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-14T12:00:00Z", from: now, locale: :de) ==
               "gestern"
    end

    test "French locale" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-14T12:00:00Z", from: now, locale: :fr) ==
               "hier"
    end

    test ":format short abbreviates" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      string =
        Tempo.to_relative_string(~o"2026-06-15T15:00:00Z", from: now, format: :short)

      assert string =~ "hr"
    end
  end

  describe "unit override" do
    test ":unit forces the output unit (seconds converted correctly)" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-17T12:00:00Z", from: now, unit: :hour) ==
               "in 48 hours"
    end

    test ":unit minute for a short delta" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-15T13:00:00Z", from: now, unit: :minute) ==
               "in 60 minutes"
    end

    test ":unit scales as Localize does, rounding, as without a unit" do
      # 50 days is about 1.6 months
      from = Tempo.from_iso8601!("2026-07-01T00:00:00Z")
      value = ~o"2026-08-20T00:00:00Z"

      assert Tempo.to_relative_string(value, from: from, unit: :month) == "in 2 months"
      assert Tempo.to_relative_string(value, from: from) == "in 2 months"

      # 18 months is about 1.5 years
      assert Tempo.to_relative_string(~o"2028-01-01T00:00:00Z", from: from, unit: :year) ==
               "in 2 years"

      assert Tempo.to_relative_string(~o"2028-01-01T00:00:00Z", from: from) == "in 2 years"
    end
  end

  describe "default :from reads Tempo.Clock" do
    test "uses Tempo.Clock.Test when configured" do
      Test.put(~U[2026-06-15 12:00:00Z])

      # No :from supplied — uses Tempo.utc_now() which goes through
      # the configured clock.
      assert Tempo.to_relative_string(~o"2026-06-14T12:00:00Z") == "yesterday"
    end
  end

  describe "Tempo.Interval values" do
    test "an interval formats relative to its :from endpoint" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      iv = %Tempo.Interval{
        from: ~o"2026-06-16T12:00:00Z",
        to: ~o"2026-06-16T13:00:00Z"
      }

      assert Tempo.to_relative_string(iv, from: now) == "tomorrow"
    end

    test "an interval without concrete :from raises" do
      iv = %Tempo.Interval{from: :undefined, to: ~o"2026-06-16T13:00:00Z"}

      assert_raise Tempo.IntervalEndpointsError, fn ->
        Tempo.to_relative_string(iv, from: ~o"2026-06-15T12:00:00Z")
      end
    end
  end

  describe "error cases" do
    test "unanchored Tempo raises" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert_raise Tempo.UnanchoredError, fn ->
        Tempo.to_relative_string(~o"T10:30:00", from: now)
      end
    end
  end
end
