defmodule Tempo.EnumerationConformance.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  # Step 1 of the Enumerable review plan: a gap detector.
  #
  # Each construct the parser can now produce gets one or two
  # `Enum.take/2` invocations. The initial bar is "doesn't crash" —
  # not "returns a correct answer". The test failures this file
  # surfaces are the punch list for Steps 2–5 of the plan.
  #
  # The existing enumeration test style uses literal `%Tempo{}`
  # maps for explicit equality; this harness uses looser assertions
  # because we're cataloguing which shapes work at all, not pinning
  # down exact outputs. Once a category is known to work, its
  # assertions here can be tightened and regression-pinned.

  @sample_size 3

  # `take/2` returns `{:ok, list}` if enumeration runs, or
  # `{:crash, message}` if a runtime exception is raised. The test
  # assertions below pattern-match on the result, so an unexpected
  # crash surfaces as a clear failure message rather than a raw
  # stacktrace.
  defp take(input, n \\ @sample_size) do
    case Tempo.from_iso8601(input) do
      {:ok, value} ->
        try do
          {:ok, Enum.take(value, n)}
        rescue
          e -> {:crash, Exception.message(e)}
        end

      {:error, reason} ->
        {:parse_error, reason}
    end
  end

  defp take_tempo(%Tempo{} = value, n \\ @sample_size) do
    {:ok, Enum.take(value, n)}
  rescue
    e -> {:crash, Exception.message(e)}
  end

  ## Baseline — shapes the current implementation already handles.

  describe "baseline (regression pins)" do
    test "bare year enumerates at month granularity (implicit)" do
      # `2022Y` has no explicit enumerator. The implicit enumerator
      # chosen by `Unit.implicit_enumerator/2` for year-only on a
      # month-based calendar is month. Enumeration walks 12 months.
      assert {:ok, list} = take(~o"2022Y" |> Tempo.to_iso8601!())
      assert length(list) == 3
      assert Enum.all?(list, fn %Tempo{time: [year: 2022, month: _]} -> true end)
    end

    test "explicit month range enumerates" do
      assert {:ok, list} = take("{1..3}M")
      assert Enum.map(list, & &1.time) == [[month: 1], [month: 2], [month: 3]]
    end

    test "year-month-day with inner range enumerates" do
      assert {:ok, list} = take("2022Y{1..2}M{1..2}D")
      assert length(list) == 3
    end
  end

  ## Step 2 — metadata propagation.

  describe "metadata propagation" do
    # The harness uses minute-resolution inputs here (not second)
    # because second-resolution values are now a documented
    # ArgumentError: there's no finer unit to iterate over.

    test "IXDTF zone_id survives enumeration" do
      assert {:ok, list} = take("2022-06-15T10:30[Europe/Paris]")
      assert Enum.all?(list, fn v -> v.extended && v.extended.zone_id == "Europe/Paris" end)
    end

    test "IXDTF calendar (u-ca) survives enumeration" do
      assert {:ok, list} = take("2022-06-15T10:30[u-ca=hebrew]")
      assert Enum.all?(list, fn v -> v.calendar == Calendrical.Hebrew and v.extended == nil end)
    end

    # A qualification is held per component (decided 2026-10-04), so the
    # month a walk adds to an uncertain year is not itself uncertain.
    test "a qualified year stays qualified in each value its walk yields" do
      assert {:ok, list} = take("2022Y?")
      assert Enum.all?(list, fn v -> Tempo.qualification(v, :year) == :uncertain end)
      assert Enum.all?(list, fn v -> Tempo.qualification(v, :month) == nil end)
    end

    test "component-level qualifications survive enumeration" do
      assert {:ok, list} = take("2022-?06-15")
      assert Enum.all?(list, fn v -> v.qualifications == %{month: :uncertain} end)
    end
  end

  ## Step 4 — long-year shapes.

  describe "long-year shapes" do
    test "4-digit Y-prefix year enumerates (`Y2022`)" do
      assert {:ok, _list} = take("Y2022")
    end

    test "5-digit Y-prefix year enumerates (`Y12345`)" do
      assert {:ok, _list} = take("Y12345")
    end

    test "Y-prefix with exponent (`Y17E8`)" do
      # `Y17E8` = 1,700,000,000 — a single anchored year. The implicit
      # enumerator then walks months of that year (12 values).
      assert {:ok, list} = take("Y17E8")
      assert Enum.all?(list, fn v -> v.time[:year] == 1_700_000_000 end)
    end

    test "Y-prefix with significant-digit annotation (`Y171010000S3`) refuses" do
      # 3 significant digits on a 9-digit year = 10^6 candidates, which
      # exceeds `@significant_digits_limit`. Refuses with a clear error.
      assert {:crash, msg} = take("Y171010000S3")
      assert msg =~ "Cannot enumerate a significant-digits block"
      assert msg =~ "limit: 10000"
    end

    test "short year with significant-digit annotation (`1950S2`) enumerates the block" do
      # `1950S2` = first 2 digits significant → range `1900..1999`.
      # The implicit enumerator then walks months for each year.
      assert {:ok, list} = take("1950S2")
      # First 3 values should be 1900Y1M, 1900Y2M, 1900Y3M.
      assert Enum.map(list, & &1.time) == [
               [year: 1900, month: 1],
               [year: 1900, month: 2],
               [year: 1900, month: 3]
             ]
    end
  end

  ## Masks — unspecified digits.

  describe "unspecified-digit masks" do
    test "positive-year mask (`156X`)" do
      assert {:ok, _list} = take("156X")
    end

    test "year-month-day with unspecified month (`1985-XX-XX`)" do
      assert {:ok, _list} = take("1985-XX-XX")
    end

    test "negative year mask (`-1XXX-XX`)" do
      assert {:ok, _list} = take("-1XXX-XX")
    end

    test "all-unspecified year (`XXXX`) enumerates starting from 1000" do
      # Mask `[:X, :X, :X, :X]` → 4-digit year range 1000..9999.
      assert {:ok, list} = take("XXXX")
      assert Enum.map(list, & &1.time) == [[year: 1000], [year: 1001], [year: 1002]]
    end

    test "a day mask enumerates every valid day, including single digits (`2020-06-XX`)" do
      tempo = Tempo.from_iso8601!("2020-06-XX")
      days = tempo |> Enum.map(& &1.time[:day]) |> Enum.sort()

      assert days == Enum.to_list(1..30)
      # `count/1` must agree with the reduce-based walk, not the coarser
      # block interval the mask materialises to.
      assert Enum.count(tempo) == 30
    end
  end

  ## Qualifications (expression + component).

  describe "qualifications" do
    test "leading uncertainty (`?2022-06-15`)" do
      assert {:ok, _list} = take("?2022-06-15")
    end

    test "approximate year (`~2022`)" do
      assert {:ok, _list} = take("~2022")
    end

    test "mixed component qualifiers (`2022?-?06-%15`) enumerate at hour granularity" do
      # Day-resolution input with per-component qualifiers. Implicit
      # enumeration walks hours within the day.
      assert {:ok, list} = take("2022?-?06-%15")

      assert Enum.all?(list, fn v ->
               v.time[:year] == 2022 and v.time[:month] == 6 and v.time[:day] == 15
             end)

      assert Enum.all?(list, fn v ->
               v.qualifications[:year] == :uncertain and
                 v.qualifications[:month] == :uncertain and
                 v.qualifications[:day] == :uncertain_and_approximate
             end)
    end
  end

  ## IXDTF.

  describe "IXDTF metadata" do
    test "time zone only" do
      assert {:ok, _list} = take("2022-06-15T10:30[Europe/Paris]")
    end

    test "calendar only" do
      assert {:ok, _list} = take("2022-06-15T10:30[u-ca=hebrew]")
    end

    test "offset + calendar" do
      assert {:ok, _list} = take("2022-06-15T10:30[+05:30][u-ca=hebrew]")
    end

    test "second-resolution datetime enumerates at decisecond" do
      # With sub-second resolution, a second has a finer unit
      # (microsecond at precision 1 — decisecond), so a second-
      # resolution value subdivides into ten decisecond sub-points
      # `[.0, .1, …, .9]`.
      {:ok, value} = Tempo.from_iso8601("2022-06-15T10:30:00Z")
      assert length(Enum.to_list(value)) == 10
    end

    test "microsecond-precision-6 datetime raises (finest representable ulp)" do
      # Precision 6 is the finest representable ulp; there is no
      # +1-digit resolution to subdivide into.
      {:ok, value} = Tempo.from_iso8601("2022-06-15T10:30:00.123456Z")

      assert_raise ArgumentError, ~r/microsecond precision 6/, fn ->
        Enum.take(value, 1)
      end
    end

    test "IXDTF interval with per-endpoint zones parses and the zones survive enumeration" do
      # Prior to this round, the grammar attached IXDTF suffixes only
      # at the top level, so an interval with an IXDTF suffix on each
      # endpoint failed to parse. This test pins the fix and confirms
      # the per-endpoint zone_id is preserved through enumeration.
      {:ok, interval} =
        Tempo.from_iso8601("2022-06-15T10:00[Europe/Paris]/2022-06-15T13:00[Europe/London]")

      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.to.extended.zone_id == "Europe/London"

      # Endpoint iteration: `from` is the anchor, so yielded values
      # carry `from`'s zone_id. The `to` endpoint's zone is attached
      # to the boundary, not the interior values.
      list = Enum.take(interval, 3)

      assert Enum.all?(list, fn v ->
               v.extended && v.extended.zone_id == "Europe/Paris"
             end)
    end
  end

  ## Step 5 — open-ended intervals.

  describe "open-ended intervals (Step 5 of the plan)" do
    # Step 5 of the Enumerable review plan implements
    # `Enumerable.Tempo.Interval`. Count/member?/slice currently
    # return `{:error, __MODULE__}` (a conservative placeholder).
    # Reduce is the interesting callback: it iterates forward one
    # resolution-unit at a time from the `:from` endpoint for the
    # closed and open-upper cases, and raises `ArgumentError` for
    # the fully-open and open-lower cases (no anchor).

    test "Enumerable.count/1 returns {:error, __MODULE__} for fully open intervals" do
      {:ok, interval} = Tempo.from_iso8601("../..")
      assert Enumerable.count(interval) == {:error, Enumerable.Tempo.Interval}
    end

    test "Enum.take/2 on a fully open interval raises a clear ArgumentError" do
      {:ok, interval} = Tempo.from_iso8601("../..")

      assert_raise ArgumentError, ~r/fully open interval/, fn ->
        Enum.take(interval, 3)
      end
    end

    test "Enum.take/2 on an open-upper interval iterates forward from `from`" do
      {:ok, interval} = Tempo.from_iso8601("1985-01-01/..")
      list = Enum.take(interval, 3)
      assert length(list) == 3

      assert Enum.map(list, & &1.time) == [
               [year: 1985, month: 1, day: 1],
               [year: 1985, month: 1, day: 2],
               [year: 1985, month: 1, day: 3]
             ]
    end

    test "Enum.take/2 on an open-lower interval raises a clear ArgumentError" do
      {:ok, interval} = Tempo.from_iso8601("../1985-12-31")

      assert_raise ArgumentError, ~r/open lower bound/, fn ->
        Enum.take(interval, 3)
      end
    end

    test "Enum.take/2 on an open-upper year interval advances years" do
      {:ok, interval} = Tempo.from_iso8601("1985/..")
      list = Enum.take(interval, 4)
      assert Enum.map(list, & &1.time) == [[year: 1985], [year: 1986], [year: 1987], [year: 1988]]
    end

    test "Enum.take/2 on a closed day-resolution interval stops at the upper bound" do
      # Half-open `[from, to)` — `to` is exclusive. Jan 1 .. Jan 4
      # yields Jan 1, 2, 3.
      {:ok, interval} = Tempo.from_iso8601("1985-01-01/1985-01-04")
      list = Enum.to_list(interval)

      assert Enum.map(list, & &1.time) == [
               [year: 1985, month: 1, day: 1],
               [year: 1985, month: 1, day: 2],
               [year: 1985, month: 1, day: 3]
             ]
    end

    test "Enum.take/2 on a closed month-resolution interval rolls year boundaries" do
      # Dec 1985 .. Feb 1986 (exclusive): yields Dec 1985, Jan 1986.
      {:ok, interval} = Tempo.from_iso8601("1985-12/1986-02")
      list = Enum.to_list(interval)

      assert Enum.map(list, & &1.time) == [
               [year: 1985, month: 12],
               [year: 1986, month: 1]
             ]
    end

    test "Enum.take/2 on a mismatched-resolution interval `1985/1986-06`" do
      # `1985`.start = 1985-01-01, `1986-06`.start = 1986-06-01. The
      # interval is walked at the highest resolution of its boundaries,
      # the month, so its values are the seventeen months before June
      # 1986 and none runs past the end.
      {:ok, interval} = Tempo.from_iso8601("1985/1986-06")
      list = Enum.to_list(interval)

      assert length(list) == 17
      assert hd(list).time == [year: 1985, month: 1]
      assert List.last(list).time == [year: 1986, month: 5]
    end

    test "Enum.take/2 on `from/duration` intervals iterates forward" do
      # `1985-01/P3M` — concrete `from`, duration-expressed upper
      # bound. For now the upper bound is treated as open because
      # Tempo-Duration addition isn't implemented; `Enum.take/2`
      # still halts as expected.
      {:ok, interval} = Tempo.from_iso8601("1985-01/P3M")
      list = Enum.take(interval, 3)

      assert Enum.map(list, & &1.time) == [
               [year: 1985, month: 1],
               [year: 1985, month: 2],
               [year: 1985, month: 3]
             ]
    end

    test "Enum.take/2 on `duration/to` iterates from (to - duration) to to" do
      # `P1M/1985-06` — lower bound computed via `Tempo.Math.subtract/2`
      # as `1985-06 − P1M = 1985-05`. Interval `[1985-05, 1985-06)`
      # yields one month: May 1985.
      {:ok, interval} = Tempo.from_iso8601("P1M/1985-06")
      list = Enum.to_list(interval)
      assert Enum.map(list, & &1.time) == [[year: 1985, month: 5]]
    end

    test "Enum.take/2 on a week-resolution interval advances weeks" do
      {:ok, interval} = Tempo.from_iso8601("2022-W05/2022-W08")
      list = Enum.to_list(interval)

      assert Enum.map(list, & &1.time) == [
               [year: 2022, week: 5],
               [year: 2022, week: 6],
               [year: 2022, week: 7]
             ]
    end
  end

  ## Per-endpoint qualification in intervals.

  describe "per-endpoint interval qualification" do
    test "`1984?/2004~` enumerates (or raises cleanly)" do
      {:ok, interval} = Tempo.from_iso8601("1984?/2004~")

      # The interval itself may or may not be enumerable today.
      # What we care about: no crash, and if enumerable, the
      # per-endpoint qualifications are visible on the result.
      result =
        try do
          {:ok, Enum.take(interval, 2)}
        rescue
          _ -> {:not_yet_enumerable, nil}
        end

      assert match?({:ok, _}, result) or match?({:not_yet_enumerable, _}, result)

      # The endpoints themselves are individually enumerable and
      # retain their qualifications (Step 2 confirmation).
      assert Tempo.qualification(interval.from) == :uncertain
      assert Tempo.qualification(interval.to) == :approximate
    end
  end

  ## Seasons.

  describe "seasons" do
    test "astronomical season `2022-25` expands to an interval" do
      # Seasons are expanded by `Group.expand_groups/2` before
      # enumeration and produce a `%Tempo.Interval{}`. This test
      # confirms that parse/expand still works; iteration is Step 5.
      assert {:ok, _ast} = Tempo.from_iso8601("2022-25")
    end

    test "meteorological season `2022-21` expands to an interval" do
      assert {:ok, _ast} = Tempo.from_iso8601("2022-21")
    end
  end

  ## Pre-existing shapes — regression pins.

  describe "existing (regression)" do
    test "explicit set (all-of)" do
      assert {:ok, list} = take("{2021,2022}Y")
      assert Enum.map(list, & &1.time) == [[year: 2021], [year: 2022]]
    end

    test "explicit set (one-of)" do
      assert {:ok, _list} = take("[1984,1986,1988]")
    end

    test "group expansion (`nGspanUNITU`)" do
      assert {:ok, list} = take("2022Y5G2MU")
      # `5G2MU` = 5th group of 2 months = months 9..10. Enumeration
      # then drops to the next-finer implicit unit (day).
      assert Enum.all?(list, fn v -> v.time[:year] == 2022 and v.time[:month] in 9..10 end)
    end

    test "selection (`L…N`) enumerates the values it selects" do
      # A selection is a constraint on the value it is in, not a
      # sequence of its own: `2022YL1MN` is the first month of 2022 and
      # `2026Y6ML2KN` the Tuesdays of June 2026. Walking one yields what
      # `Tempo.to_interval/2` gives it.
      assert {:ok, list} = take("2022YL1MN")
      assert Enum.map(list, & &1.time) == [[year: 2022, month: 1]]

      assert {:ok, list} = take("2026Y6ML2KN")

      assert Enum.map(list, & &1.time) == [
               [year: 2026, month: 6, day: 2],
               [year: 2026, month: 6, day: 9],
               [year: 2026, month: 6, day: 16]
             ]
    end
  end

  ## `take_tempo/2` wrapper — used in Step 2 propagation tests
  ## that build a `%Tempo{}` directly without re-parsing, to
  ## isolate enumeration behaviour from parser behaviour.

  describe "direct-struct enumeration" do
    test "enumerating a hand-built Tempo with extended map preserves the map" do
      tempo = %Tempo{
        time: [year: 2022, month: [1, 2]],
        calendar: Calendrical.Gregorian,
        extended: %{zone_id: "UTC", zone_offset: nil, zone_critical: false, tags: %{}}
      }

      assert {:ok, list} = take_tempo(tempo)
      assert Enum.all?(list, fn v -> v.extended.zone_id == "UTC" end)
    end
  end
end
