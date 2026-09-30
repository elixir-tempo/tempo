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
    test ":unit hour counts the hours between" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-17T12:00:00Z", from: now, unit: :hour) ==
               "in 48 hours"
    end

    test ":unit minute for a short delta" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert Tempo.to_relative_string(~o"2026-06-15T13:00:00Z", from: now, unit: :minute) ==
               "in 60 minutes"
    end

    test ":unit counts the unit's calendar periods" do
      from = Tempo.from_iso8601!("2026-07-01T00:00:00Z")

      # August is the month after July, whichever day of it
      assert Tempo.to_relative_string(~o"2026-08-20T00:00:00Z", from: from, unit: :month) ==
               "next month"

      assert Tempo.to_relative_string(~o"2028-01-01T00:00:00Z", from: from, unit: :year) ==
               "in 2 years"

      assert Tempo.to_relative_string(~o"2026-02-01", from: ~o"2026-01-31", unit: :month) ==
               "next month"
    end

    test "without :unit, the largest unit of which a whole one lies between" do
      from = Tempo.from_iso8601!("2026-07-01T00:00:00Z")

      assert Tempo.to_relative_string(~o"2026-08-20T00:00:00Z", from: from) == "next month"
      assert Tempo.to_relative_string(~o"2028-01-01T00:00:00Z", from: from) == "in 2 years"
      assert Tempo.to_relative_string(~o"2026-02-01", from: ~o"2026-01-31") == "tomorrow"
    end

    test "quarters and weekdays are calendar periods" do
      assert Tempo.to_relative_string(~o"2026-07-01", from: ~o"2026-06-30", unit: :quarter) ==
               "next quarter"

      assert Tempo.to_relative_string(~o"2026-06-01", from: ~o"2026-06-30", unit: :quarter) ==
               "this quarter"

      # 17 June 2026 is a Wednesday, and 22 June the Monday after
      assert Tempo.to_relative_string(~o"2026-06-22", from: ~o"2026-06-17", unit: :mon) ==
               "next Monday"
    end
  end

  describe "the value's own calendar" do
    test "a Hebrew date counts Hebrew months and years" do
      # 1 Tishri 5787 is 12 September 2026, the day after 29 Elul 5786
      new_year = Tempo.from_iso8601!("5787-01-01[u-ca=hebrew]")

      assert Tempo.to_relative_string(new_year, from: ~o"2026-09-11", unit: :month) ==
               "next month"

      assert Tempo.to_relative_string(new_year, from: ~o"2026-09-11", unit: :year) ==
               "next year"

      assert Tempo.to_relative_string(new_year, from: ~o"2026-09-11") == "tomorrow"

      assert Tempo.to_relative_string(~o"2026-09-12", from: ~o"2026-09-11", unit: :month) ==
               "this month"
    end
  end

  describe "the value's own wall clock" do
    test "a zoned value counts days on its own clock" do
      sydney = Tempo.from_iso8601!("2026-06-16T01:00[Australia/Sydney]")

      # 13:00 UTC is 23:00 the day before in Sydney
      from = Tempo.from_iso8601!("2026-06-15T13:00:00Z")

      assert Tempo.to_relative_string(sydney, from: from, unit: :day) == "tomorrow"
      assert Tempo.to_relative_string(sydney, from: from) == "in 2 hours"
    end

    test "a value with an offset counts days at its offset" do
      value = Tempo.from_iso8601!("2026-06-16T01:00+10:00")
      from = Tempo.from_iso8601!("2026-06-15T13:00:00Z")

      assert Tempo.to_relative_string(value, from: from, unit: :day) == "tomorrow"
    end

    test "a zoned day is the day its own clock shows" do
      # 15:00 UTC on 15 June is 01:00 on 16 June in Sydney
      sydney = Tempo.from_iso8601!("2026-06-16[Australia/Sydney]")
      from = Tempo.from_iso8601!("2026-06-15T15:00:00Z")

      assert Tempo.to_relative_string(sydney, from: from) == "today"
    end

    test "hours across a change of offset are the hours that pass" do
      # New York's clocks go from 02:00 to 03:00 on 8 March 2026
      value = Tempo.from_iso8601!("2026-03-08T04:00[America/New_York]")
      from = Tempo.from_iso8601!("2026-03-08T01:00[America/New_York]")

      assert Tempo.to_relative_string(value, from: from, unit: :hour) == "in 2 hours"
    end

    test "a floating value is read on the baseline's wall clock" do
      from = Tempo.from_iso8601!("2026-06-15T12:00[Australia/Sydney]")

      assert Tempo.to_relative_string(~o"2026-06-15T15:00", from: from) == "in 3 hours"
    end

    test "a zoned day is counted from a floating one" do
      sydney = Tempo.from_iso8601!("2026-06-16[Australia/Sydney]")

      assert Tempo.to_relative_string(sydney, from: ~o"2026-06-15") == "tomorrow"
    end
  end

  describe "a value is where its span starts" do
    test "a year, a week and a quarter" do
      assert Tempo.to_relative_string(~o"2027", from: ~o"2026-07-01", unit: :year) == "next year"

      assert Tempo.to_relative_string(~o"2026-W26", from: ~o"2026-06-17", unit: :week) ==
               "next week"

      # The first quarter of 2026
      first_quarter = Tempo.from_iso8601!("2026-33")

      assert Tempo.to_relative_string(first_quarter, from: ~o"2026-06-15", unit: :quarter) ==
               "last quarter"
    end

    test "a day counted in hours starts at midnight" do
      assert Tempo.to_relative_string(~o"2026-06-16", from: ~o"2026-06-15T23:00", unit: :hour) ==
               "in 1 hour"

      assert Tempo.to_relative_string(~o"2026-06-16", from: ~o"2026-06-15T23:00") ==
               "tomorrow"
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

  describe "without :unit, never a unit finer than the value's own" do
    test "a year, a month and a week nearest the baseline count in their own unit" do
      assert Tempo.to_relative_string(~o"2027", from: ~o"2026-07-01") == "next year"
      assert Tempo.to_relative_string(~o"2026", from: ~o"2026-07-01") == "this year"
      assert Tempo.to_relative_string(~o"2026-08", from: ~o"2026-07-15") == "next month"
      assert Tempo.to_relative_string(~o"2026-W26", from: ~o"2026-06-17") == "next week"
    end

    test "an hour and a minute count in their own unit" do
      from = Tempo.from_iso8601!("2026-06-15T12:30")
      assert Tempo.to_relative_string(~o"2026-06-15T12", from: from) == "this hour"

      from = Tempo.from_iso8601!("2026-06-15T12:00:30")
      assert Tempo.to_relative_string(~o"2026-06-15T12:01", from: from) == "in 1 minute"
    end

    test "a larger unit Localize chooses stands" do
      assert Tempo.to_relative_string(~o"2024-03", from: ~o"2026-07-15") == "2 years ago"
      assert Tempo.to_relative_string(~o"2026-W40", from: ~o"2026-06-17") == "in 3 months"

      from = Tempo.from_iso8601!("2026-06-15T12:00")
      assert Tempo.to_relative_string(~o"2026-06-15T15:00", from: from) == "in 3 hours"
    end

    test "a :unit given is counted in as it is, and :numeric is kept" do
      assert Tempo.to_relative_string(~o"2027", from: ~o"2026-07-01", unit: :month) ==
               "in 6 months"

      assert Tempo.to_relative_string(~o"2027", from: ~o"2026-07-01", numeric: :always) ==
               "in 1 year"
    end
  end

  describe "error cases" do
    test "unanchored Tempo raises" do
      now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")

      assert_raise Tempo.UnanchoredError, fn ->
        Tempo.to_relative_string(~o"T10:30:00", from: now)
      end
    end

    test "an unanchored :from raises" do
      assert_raise Tempo.UnanchoredError, fn ->
        Tempo.to_relative_string(~o"2026-06-16", from: ~o"T10:00")
      end
    end

    test "a :from that is not a Tempo raises" do
      assert_raise ArgumentError, ~r/must be a Tempo/, fn ->
        Tempo.to_relative_string(~o"2026-06-16", from: ~D[2026-06-15])
      end
    end

    test "a zoned value finer than a day from a floating :from raises" do
      sydney = Tempo.from_iso8601!("2026-06-15T15:00[Australia/Sydney]")

      assert_raise Tempo.FloatingTempoError, fn ->
        Tempo.to_relative_string(sydney, from: ~o"2026-06-15T12:00")
      end

      offset = Tempo.from_iso8601!("2026-06-15T15:00+10:00")

      assert_raise Tempo.FloatingTempoError, fn ->
        Tempo.to_relative_string(offset, from: ~o"2026-06-15T12:00")
      end
    end

    test "a value naming several spans raises" do
      assert_raise ArgumentError, ~r/several spans/, fn ->
        Tempo.to_relative_string(Tempo.from_iso8601!("{2026,2027}Y"), from: ~o"2026-07-01")
      end
    end
  end
end
