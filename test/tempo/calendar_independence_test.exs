defmodule Tempo.CalendarIndependenceTest do
  @moduledoc """
  Operations must be calendar-independent. Comparison and duration route each
  value through its calendar's date→absolute-day conversion, so cross-calendar
  relations, `within?`, and non-Gregorian durations are as accurate as
  single-calendar ones — while the Gregorian fast path is unchanged.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Network
  alias Tempo.Network.Solver

  # Build a value in the named calendar via its IXDTF `u-ca` tag.
  defp cal(string, calendar), do: Tempo.from_iso8601!("#{string}[u-ca=#{calendar}]")

  # The real elapsed length of a value's enclosing span, in whole days.
  defp span_days(value) do
    {:ok, interval} = Tempo.to_interval(value)
    seconds = Compare.to_utc_seconds(interval.to) - Compare.to_utc_seconds(interval.from)
    round(seconds / 86_400)
  end

  describe "cross-calendar comparison routes through the shared absolute frame" do
    test "equivalent dates in different calendars compare as :equals" do
      # Tishri 1, 5786 AM = 2025-09-23; Nowruz 1404 = 2025-03-21;
      # Muharram 1, 1447 AH = 2025-06-27.
      assert Tempo.relation(~o"2025-09-23", cal("5786-01-01", "hebrew")) == :equals
      assert Tempo.relation(~o"2025-03-21", cal("1404-01-01", "persian")) == :equals
      assert Tempo.relation(~o"2025-06-27", cal("1447-01-01", "islamic-civil")) == :equals
    end

    test "a Hebrew date falls within its Gregorian year" do
      assert Tempo.within?(cal("5786-01-01", "hebrew"), ~o"2025")
    end

    test "ordering is correct across calendars" do
      assert Tempo.before?(cal("5786-01-01", "hebrew"), ~o"2025-12-31")
      assert Tempo.after?(cal("1447-06-01", "islamic-civil"), ~o"2025-06-27")
    end

    test "the Gregorian fast path is preserved" do
      assert Tempo.relation(~o"2025-01-01", ~o"2025-06-01") == :precedes
      assert Tempo.within?(~o"2025-06-15", ~o"2025")
    end
  end

  describe "the ~o sigil honours an in-string u-ca calendar" do
    # Regression: with no calendar modifier the value-context sigil must
    # defer to the string's own `[u-ca=NAME]` suffix, not force Gregorian.
    # Previously `~o"5786-01-01[u-ca=hebrew]"` silently parsed as a
    # Gregorian year 5786, so the documented `:equals` was `:precedes`.
    test "resolves the calendar named by the u-ca suffix" do
      assert ~o"5786-01-01[u-ca=hebrew]".calendar == Calendrical.Hebrew
      assert ~o"1404-01-01[u-ca=persian]".calendar == Calendrical.Persian
    end

    test "the sigil form matches the from_iso8601 form" do
      assert ~o"5786-01-01[u-ca=hebrew]" == cal("5786-01-01", "hebrew")
    end

    test "sigil-built cross-calendar values compare through the shared frame" do
      assert Tempo.relation(~o"2025-09-23", ~o"5786-01-01[u-ca=hebrew]") == :equals
      assert Tempo.relation(~o"5786-09-30[u-ca=hebrew]", ~o"2026-06-15") == :equals
    end

    test "a sigil with no u-ca suffix is still Gregorian" do
      assert ~o"2026-06-15".calendar == Calendrical.Gregorian
    end
  end

  describe "a bare %Tempo{} with a nil calendar (the struct default)" do
    # Regression: a directly-constructed value carries `calendar: nil`
    # (the defstruct default) rather than the parsed Gregorian default.
    # Calendar projection must treat `nil` as Gregorian, not pass it to
    # `Date.new/4`, which raises `nil.valid_date?/3`.
    test "comparison and Interval.new tolerate a nil calendar" do
      partial = %Tempo{time: [year: 2026]}
      assert partial.calendar == nil

      assert {:ok, _interval} = Interval.new(from: partial, to: ~o"2027")
      assert Tempo.relation(partial, ~o"2026") == :equals
      assert Tempo.within?(%Tempo{time: [year: 2026, month: 6]}, ~o"2026")
    end

    test "a nil-calendar bound is placed correctly in a network" do
      network =
        Network.new()
        |> Network.add_period(:a, start: %Tempo{time: [year: 2026]}, end: ~o"2026-06")
        |> Network.add_period(:b, start: ~o"2026-07", end: ~o"2027")

      assert Solver.relation(network, :a, :b) == :precedes
    end
  end

  describe "durations are calendar-correct" do
    test "a Hebrew common year is 354 days, not a Gregorian 365" do
      assert span_days(cal("5786", "hebrew")) == 354
    end

    test "an Islamic year is 354 or 355 days" do
      assert span_days(cal("1447", "islamic-civil")) in [354, 355]
    end

    test "a Gregorian year is unchanged at 365 days" do
      assert span_days(~o"2021") == 365
      assert Interval.duration(elem(Tempo.to_interval(~o"2021"), 1)) == ~o"PT31536000S"
    end
  end

  describe "u-ca round-trip" do
    test "multi-word calendar identifiers round-trip through to_iso8601" do
      for calendar <- ["islamic-civil", "islamic-umalqura", "hebrew", "persian", "japanese"] do
        value = cal("1447-01-15", calendar)
        serialised = Tempo.to_iso8601(value)
        assert String.contains?(serialised, "[u-ca=#{calendar}]")
        assert {:ok, reparsed} = Tempo.from_iso8601(serialised)
        assert reparsed.calendar == value.calendar
      end
    end
  end

  describe "a month that does not exist in a calendar year" do
    test "a Hebrew 13th month in an ordinary year is a clear error, not a crash" do
      # A 13th month exists only in leap years; 2026 AM is ordinary.
      assert {:error, %Tempo.InvalidDateError{reason: reason}} =
               Tempo.from_iso8601("2026-13-15[u-ca=hebrew]")

      assert reason =~ "valid values are 1..12"
    end

    test "Adar I in an ordinary year is a clear error, not a crash" do
      # Adar I is the leap month following traditional month 5.
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026Y5+m15D[u-ca=hebrew]")
    end

    test "the months of an ordinary year resolve" do
      # In an ordinary year Adar is month 6 and Elul month 12.
      assert {:ok, _} = Tempo.from_iso8601("2026-06-15[u-ca=hebrew]")
      assert {:ok, _} = Tempo.from_iso8601("2026-12-15[u-ca=hebrew]")
    end
  end

  describe "the network solver and coalescing are calendar-independent" do
    test "a network relation across calendars reads true instants" do
      network =
        Network.new()
        |> Network.add_period(:gregorian, start: ~o"2025-09-01", end: ~o"2025-10-01")
        |> Network.add_period(:hebrew,
          start: cal("5786-01-01", "hebrew"),
          end: cal("5786-02-01", "hebrew")
        )

      # Hebrew Tishri 5786 (Sep 23 – Oct 22, 2025) overlaps Gregorian September.
      assert Solver.relation(network, :gregorian, :hebrew) == :overlaps
    end

    test "coalescing merges overlapping intervals across calendars" do
      {:ok, set} = Tempo.union(~o"2025-09", cal("5786-01", "hebrew"))

      # By default an IntervalSet keeps distinct members…
      assert IntervalSet.count(set) == 2
      # …but the opt-in coalesce merges them by their true instants.
      assert IntervalSet.count(IntervalSet.coalesce(set)) == 1
    end
  end
end
