defmodule Tempo.Select.Test do
  use ExUnit.Case, async: false
  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError

  doctest Tempo.Select

  # `Tempo.select/2` narrows a base span by a selector, returning
  # an `{:ok, %Tempo.IntervalSet{}}` tuple. The tests below cover
  # every selector shape, every base shape (Tempo / Interval /
  # IntervalSet), and every rung of the territory-resolution chain
  # inside `Tempo.workdays/1` / `Tempo.weekends/1`.
  #
  # This suite is `async: false` because a couple of tests mutate
  # `Application.put_env(:ex_tempo, :default_territory, _)` to exercise
  # the app-config rung of the territory chain.

  describe "integer-list selector" do
    test "on a month base, indices apply at day resolution" do
      {:ok, set} = Tempo.select(~o"2026-02", [1, 15])
      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
      assert days == [1, 15]
    end

    test "on a year base, indices apply at month resolution" do
      {:ok, set} = Tempo.select(~o"2026", [1, 4, 7, 10])
      months = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:month])
      assert months == [1, 4, 7, 10]
    end

    test "on a day base, indices apply at hour resolution" do
      {:ok, set} = Tempo.select(~o"2026-02-15", [9, 12, 17])
      hours = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:hour])
      assert hours == [9, 12, 17]
    end

    test "empty list returns an empty IntervalSet" do
      assert {:ok, %Tempo.IntervalSet{intervals: []}} = Tempo.select(~o"2026-02", [])
    end
  end

  describe "range selector" do
    test "a range expands to an integer list" do
      {:ok, set} = Tempo.select(~o"2026-02", 6..8)
      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
      assert days == [6, 7, 8]
    end

    test "a range on a year base selects months" do
      {:ok, set} = Tempo.select(~o"2026", 6..8)
      months = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:month])
      assert months == [6, 7, 8]
    end
  end

  describe "integer selector on an Interval base" do
    # An Interval's from-endpoint has been filled by `to_interval/1`
    # down to day resolution, but the SPAN's declared resolution is
    # the unit at which from and to differ. The selector must use
    # that span resolution — not the endpoint's filled resolution.

    test "derives next-finer unit from the span, not the from-endpoint" do
      {:ok, base} = Tempo.to_interval(~o"2026-02")
      {:ok, set} = Tempo.select(base, [1, 15])

      result =
        set
        |> IntervalSet.members()
        |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})

      assert result == [{2, 1}, {2, 15}]
    end

    test "year-resolution Interval projects indices as months" do
      {:ok, base} = Tempo.to_interval(~o"2026")
      {:ok, set} = Tempo.select(base, [3, 6, 9])

      months = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:month])
      assert months == [3, 6, 9]
    end
  end

  describe "Tempo.workdays/1 and Tempo.weekends/1 as selectors" do
    # The default Localize locale is `en` which resolves to `:US`,
    # where weekdays = [1..5] (Mon..Fri) and weekend = [6, 7] (Sat,
    # Sun). The test month (Feb 2026) starts on a Sunday.

    test "Tempo.workdays(:US) on Feb 2026 returns Monday..Friday" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      count = set |> IntervalSet.members() |> length()
      # Feb 2026 has 20 workdays (28 days – 8 weekend days).
      assert count == 20
    end

    test "Tempo.weekends(:US) on Feb 2026 returns Saturday..Sunday" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekends(:US))
      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
      # Sundays: 1, 8, 15, 22. Saturdays: 7, 14, 21, 28.
      assert days == [1, 7, 8, 14, 15, 21, 22, 28]
    end

    test "Tempo.workdays(:US) intervals are half-open day spans" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      [first | _] = set |> IntervalSet.members()

      # Feb 2 is the first Monday of Feb 2026.
      assert first.from.time == [year: 2026, month: 2, day: 2]
      assert first.to.time == [year: 2026, month: 2, day: 3]
    end

    test "workdays and weekend partition the seven days of the week" do
      assert Enum.sort(
               Tempo.workdays(:US).time[:day_of_week] ++
                 Tempo.weekends(:US).time[:day_of_week]
             ) == [1, 2, 3, 4, 5, 6, 7]

      assert Enum.sort(
               Tempo.workdays(:SA).time[:day_of_week] ++
                 Tempo.weekends(:SA).time[:day_of_week]
             ) == [1, 2, 3, 4, 5, 6, 7]
    end

    test "weekend selection over a week-axis base (regression: was silently empty)" do
      # Each ISO week contains exactly one Saturday and one Sunday,
      # so 13 weeks yield 26 weekend days.
      {:ok, set} = Tempo.select(~o"2026Y{1..13}W", Tempo.weekends(:US))

      days = IntervalSet.members(set)
      assert Enum.count(days) == 26

      # ISO week 1 of 2026 spans 2025-12-29..2026-01-05; its
      # weekend days are Sat Jan 3 and Sun Jan 4.
      [saturday, sunday | _rest] = days
      assert saturday.from.time == [year: 2026, month: 1, day: 3]
      assert sunday.from.time == [year: 2026, month: 1, day: 4]
    end

    test "weekend selection over a single week-resolution base" do
      {:ok, set} = Tempo.select(~o"2026Y1W", Tempo.weekends(:US))

      days = IntervalSet.members(set)
      assert Enum.map(days, & &1.from.time[:day]) == [3, 4]
    end
  end

  describe "territory resolution inside Tempo.workdays/1 and Tempo.weekends/1" do
    # Saudi Arabia has weekend = [5, 6] (Fri, Sat) vs US [6, 7]
    # (Sat, Sun). Feb 2026 Friday/Saturday pattern differs from
    # Saturday/Sunday, so a correctly-applied SA override produces
    # days [6, 7, 13, 14, 20, 21, 27, 28].

    @sa_feb_weekend [6, 7, 13, 14, 20, 21, 27, 28]
    @us_feb_weekend [1, 7, 8, 14, 15, 21, 22, 28]

    test "explicit territory argument" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekends(:SA))
      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
      assert days == @sa_feb_weekend
    end

    test "locale string resolves via Localize.Territory" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekends("ar-SA"))
      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
      assert days == @sa_feb_weekend
    end

    test "accepts string, atom, and LanguageTag forms" do
      {:ok, tag} = Localize.validate_locale("ar-SA")

      for value <- ["ar-SA", :"ar-SA", tag] do
        {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekends(value))
        days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend, "value=#{inspect(value)} did not resolve to SA"
      end
    end

    test "territory strings in 'XX', 'xx', 'xx-zzzz' forms all resolve" do
      for territory <- [:SA, "SA", "sa", "sazzzz"] do
        {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekends(territory))
        days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend, "territory=#{inspect(territory)} did not resolve to SA"
      end
    end

    test "app config is used when territory argument is nil" do
      Application.put_env(:ex_tempo, :default_territory, :SA)

      try do
        {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekends())
        days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend
      after
        Application.delete_env(:ex_tempo, :default_territory)
      end
    end

    test "default fallback uses the Localize locale (en → US)" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekends())
      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
      assert days == @us_feb_weekend
    end
  end

  describe "Tempo / Interval projection selector" do
    test "project a single Tempo onto a larger base" do
      {:ok, set} = Tempo.select(~o"2026", ~o"12-25")
      [xmas] = IntervalSet.members(set)

      assert xmas.from.time[:year] == 2026
      assert xmas.from.time[:month] == 12
      assert xmas.from.time[:day] == 25
    end

    test "project a list of Tempos onto a base" do
      {:ok, set} = Tempo.select(~o"2026", [~o"07-04", ~o"12-25"])

      pairs =
        set
        |> IntervalSet.members()
        |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})

      assert pairs == [{7, 4}, {12, 25}]
    end

    test "project an Interval (projects using its from-endpoint)" do
      vacation = %Tempo.Interval{from: ~o"2026-07-10", to: ~o"2026-07-20"}
      {:ok, set} = Tempo.select(~o"2026", vacation)

      [projected] = IntervalSet.members(set)
      assert projected.from.time[:month] == 7
      assert projected.from.time[:day] == 10
    end

    test "projection of a list of Intervals" do
      vacations = [
        %Tempo.Interval{from: ~o"2026-07-10", to: ~o"2026-07-20"},
        %Tempo.Interval{from: ~o"2026-12-20", to: ~o"2026-12-31"}
      ]

      {:ok, set} = Tempo.select(~o"2026", vacations)

      pairs =
        set
        |> IntervalSet.members()
        |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})

      assert pairs == [{7, 10}, {12, 20}]
    end

    test "day-of-week-only projection (`~o\"5K\"`) — every Friday in the base" do
      {:ok, set} = Tempo.select(~o"2026-06", ~o"5K")

      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
      assert days == [5, 12, 19, 26]
    end

    test "day-of-week projection in a whole-year base" do
      {:ok, set} = Tempo.select(~o"2026", ~o"5K")
      # 2026 has 52 Fridays.
      assert IntervalSet.count(set) == 52
    end

    test "day-of-week projection composes with quarter-shaped base" do
      {:ok, set} = Tempo.select(~o"2026Y3Q", ~o"5K")
      # Q3 2026: 13 Fridays.
      assert IntervalSet.count(set) == 13
    end

    test "ordinal-day projection (`~o\"10O\"`) — the 10th day of the year" do
      {:ok, set} = Tempo.select(~o"2026", ~o"10O")

      [iv] = IntervalSet.members(set)
      assert iv.from.time[:year] == 2026
      assert iv.from.time[:month] == 1
      assert iv.from.time[:day] == 10
    end

    test "ordinal-day projection produces a day-shaped span" do
      # The 10th day of 2026 is Jan 10 — the projection's span is
      # one day, not one hour.
      {:ok, set} = Tempo.select(~o"2026", ~o"10O")

      [iv] = IntervalSet.members(set)
      assert iv.to.time[:day] == 11
      assert iv.to.time[:month] == 1
    end

    test "month-day projection (`~o\"12-25\"`) produces a day-shaped span" do
      {:ok, set} = Tempo.select(~o"2026", ~o"12-25")

      [iv] = IntervalSet.members(set)
      assert iv.from.time[:day] == 25
      assert iv.to.time[:day] == 26
    end
  end

  describe "function selector" do
    test "the function receives the base and its result is recursed" do
      fun = fn _base -> [1, 15] end
      {:ok, set} = Tempo.select(~o"2026-02", fun)
      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])
      assert days == [1, 15]
    end

    test "the function can return a workdays selector" do
      fun = fn _base -> Tempo.workdays(:US) end
      {:ok, set} = Tempo.select(~o"2026-02", fun)
      count = set |> IntervalSet.members() |> length()
      assert count == 20
    end
  end

  describe "negative-component projection (ISO 8601-2 §4.4.1)" do
    # Negative integers count from the end of their containing time
    # scale unit. `~o"-1M"` means "last month of year"; `~o"-1D"`
    # means "last day of year" on a year base and "last day of month"
    # on a month base; `~o"-1W"` means "last week of year" or "last
    # week of month" depending on base resolution.

    test "`~o\"-1M\"` inspects without raising" do
      # Previously the parser interpreted `-1M` as a time-zone shift
      # of `-1 minute`, which then broke the inspect path.
      assert inspect(~o"-1M") == "~o\"-1M\""
    end

    test "`~o\"-1M\"` parses as a month, not a time shift" do
      t = ~o"-1M"
      assert t.time == [month: -1]
      assert t.shift == nil
    end

    test "`-1M` on a year base selects the last month (December for Gregorian)" do
      {:ok, set} = Tempo.select(~o"2026", ~o"-1M")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:year] == 2026
      assert iv.from.time[:month] == 12
      assert iv.to.time[:year] == 2027
      assert iv.to.time[:month] == 1
    end

    test "`-2M` on a year base selects the second-to-last month (November)" do
      {:ok, set} = Tempo.select(~o"2026", ~o"-2M")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:month] == 11
    end

    test "`-1D` on a year base selects the last day of the year (Dec 31)" do
      {:ok, set} = Tempo.select(~o"2026", ~o"-1D")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:year] == 2026
      assert iv.from.time[:month] == 12
      assert iv.from.time[:day] == 31
    end

    test "`-1D` on a month base selects the last day of that month" do
      {:ok, set} = Tempo.select(~o"2026-06", ~o"-1D")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:month] == 6
      assert iv.from.time[:day] == 30
    end

    test "`-1D` on February resolves to the correct last-day for leap-year context" do
      {:ok, feb_2024} = Tempo.select(~o"2024-02", ~o"-1D")
      [iv_24] = IntervalSet.members(feb_2024)
      assert iv_24.from.time[:day] == 29

      {:ok, feb_2026} = Tempo.select(~o"2026-02", ~o"-1D")
      [iv_26] = IntervalSet.members(feb_2026)
      assert iv_26.from.time[:day] == 28
    end

    test "`-1W` on a year base selects the last ISO week of the year" do
      {:ok, set_2026} = Tempo.select(~o"2026", ~o"-1W")
      [iv_2026] = IntervalSet.members(set_2026)
      # 2026 is a 53-week year in ISO 8601.
      assert iv_2026.from.time[:year] == 2026
      assert iv_2026.from.time[:week] == 53
      # No spurious `:month` — week-of-year is on its own axis.
      refute Keyword.has_key?(iv_2026.from.time, :month)

      {:ok, set_2028} = Tempo.select(~o"2028", ~o"-1W")
      [iv_2028] = IntervalSet.members(set_2028)
      assert iv_2028.from.time[:week] == 52
    end

    test "`1W` on a month base resolves as week-of-month" do
      # Week-of-month is non-standard in ISO 8601 but Tempo accepts
      # a `[year, month, week]` composite and materialises it as an
      # N-week span within the month.
      {:ok, set} = Tempo.select(~o"2026-06", ~o"1W")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:month] == 6
      assert iv.from.time[:week] == 1
    end

    test "`-1W` on a month base resolves as last week-of-month" do
      # Gregorian June has 30 days → 5 week-of-month slots.
      {:ok, set} = Tempo.select(~o"2026-06", ~o"-1W")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:month] == 6
      assert iv.from.time[:week] == 5
    end

    test "`-1W` on a February base resolves to week 4 (28-day month)" do
      {:ok, set} = Tempo.select(~o"2026-02", ~o"-1W")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:month] == 2
      assert iv.from.time[:week] == 4
    end

    test "`-1O` (ordinal-day) on a year base selects the last day of the year" do
      # `~o"-1O"` is a day of the year, which on a year base resolves
      # as `~o"-1D"` does — the last day of the year.
      {:ok, set} = Tempo.select(~o"2026", ~o"-1O")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:month] == 12
      assert iv.from.time[:day] == 31
    end

    test "`-1K` (day-of-week) parses as `day_of_week: 7` directly" do
      # `-1K` is resolved by the parser (not the selector) because
      # day-of-week is a fixed 7-day cycle with no calendar context.
      t = ~o"-1K"
      assert t.time[:day_of_week] == 7
    end

    test "`-1K` as a selector returns Sundays of the base" do
      {:ok, set} = Tempo.select(~o"2026-06", ~o"-1K")
      days = set |> IntervalSet.members() |> Enum.map(& &1.from.time[:day])

      # June 2026 Sundays: 7, 14, 21, 28.
      assert days == [7, 14, 21, 28]
    end

    test "negative components compose with set operations via select results" do
      # The whole point of selector composition — the negative
      # component flows through into an IntervalSet that plugs into
      # union/intersection/difference.
      {:ok, last_month} = Tempo.select(~o"2026", ~o"-1M")
      {:ok, first_month} = Tempo.select(~o"2026", ~o"1M")
      {:ok, union} = Tempo.union(first_month, last_month)

      assert IntervalSet.count(union) == 2
    end
  end

  describe "negative time-component projection" do
    # Time-of-day units (`:hour`, `:minute`, `:second`, `:day_of_week`)
    # have fixed ranges — 0..23, 0..59, 1..7 — so the parser resolves
    # their negatives directly at parse time rather than waiting for
    # calendar context. `~o"-1H"` parses as `hour: 23`, `~o"T-1M"`
    # parses as `minute: 59`, etc.

    test "`-1H` parses as hour 23" do
      t = ~o"-1H"
      assert t.time[:hour] == 23
      assert t.shift == nil
    end

    test "`T-1M` parses as minute 59 (T-prefix disambiguates from month)" do
      t = ~o"T-1M"
      assert t.time[:minute] == 59
      assert t.shift == nil
    end

    test "`T-1S` parses as second 59" do
      t = ~o"T-1S"
      assert t.time[:second] == 59
    end

    test "`-1H` on a day base selects the last hour of the day" do
      {:ok, set} = Tempo.select(~o"2026-06-15", ~o"-1H")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:day] == 15
      assert iv.from.time[:hour] == 23
    end

    test "`T-1M` on an hour base selects the last minute of the hour" do
      {:ok, set} = Tempo.select(~o"2026-06-15T14", ~o"T-1M")
      [iv] = IntervalSet.members(set)

      assert iv.from.time[:hour] == 14
      assert iv.from.time[:minute] == 59
    end

    test "bare signed-hour shifts no longer shadow time-component selectors" do
      # Previously `~o"-1H"` parsed as a UTC shift of -1 hour,
      # making `Tempo.select(..., ~o"-1H")` impossible. The parser
      # now reserves signed shifts for `Z`-prefixed forms (or the
      # 2-digit implicit form `-05`, `-0500`, `-05:30` — which are
      # unambiguous).
      valid_shifts = [
        {"Z", [hour: 0]},
        {"Z0H", [hour: 0]},
        {"Z+1H", [hour: 1]},
        {"2026T12+05:30", [hour: 5, minute: 30]},
        {"2026T12-05", [hour: -5]},
        {"2026T12Z", [hour: 0]}
      ]

      for {input, expected_shift} <- valid_shifts do
        t = Tempo.from_iso8601!(input)
        assert t.shift == expected_shift, "shift parse regression for #{input}"
      end
    end
  end

  describe "IntervalSet base" do
    test "selector flat-maps across every member interval" do
      {:ok, jan} = Tempo.to_interval(~o"2026Y1M")
      {:ok, mar} = Tempo.to_interval(~o"2026Y3M")
      {:ok, base} = IntervalSet.new([jan, mar])

      {:ok, set} = Tempo.select(base, [1, 15])

      triples =
        set
        |> IntervalSet.members()
        |> Enum.map(&{&1.from.time[:year], &1.from.time[:month], &1.from.time[:day]})

      assert triples == [{2026, 1, 1}, {2026, 1, 15}, {2026, 3, 1}, {2026, 3, 15}]
    end

    test "workdays flat-maps across non-touching months" do
      {:ok, jan} = Tempo.to_interval(~o"2026Y1M")
      {:ok, mar} = Tempo.to_interval(~o"2026Y3M")
      {:ok, base} = IntervalSet.new([jan, mar])

      {:ok, set} = Tempo.select(base, Tempo.workdays(:US))
      count = set |> IntervalSet.members() |> length()

      # Jan 2026: 22 workdays. Mar 2026: 22 workdays. Total 44.
      assert count == 44
    end
  end

  describe "grouped / ISO 8601-2 bases" do
    test "quarter (`3Q`) materialises and filters to quarter workdays" do
      # Q3 2026 — July, August, September. 66 Mon–Fri days in the
      # US territory.
      {:ok, set} = Tempo.select(~o"2026Y3Q", Tempo.workdays(:US))
      assert IntervalSet.count(set) == 66
    end

    test "season code 26 (Northern summer) filters to workdays inside it" do
      # Season 26 runs Jun 21 → Sep 23 (solstice-to-equinox). All
      # workdays inside that 94-day window.
      {:ok, set} = Tempo.select(~o"2026Y26M", Tempo.workdays(:US))
      count = IntervalSet.count(set)
      # Rough sanity: 94 days × 5/7 ≈ 67. Exact value depends on
      # which days of week the season boundaries land on.
      assert count in 65..70
    end

    test "month-range in a slot (`{6..8}M`) filters each member's workdays" do
      # Jun + Jul + Aug — three-month window of 66 workdays.
      {:ok, set} = Tempo.select(~o"2026Y{6..8}M", Tempo.workdays(:US))
      assert IntervalSet.count(set) == 66
    end

    test "masked year (`156X`) flows through — 1560s workdays count" do
      # Ten years × ~261 workdays/year ≈ 2600 workdays (coarse).
      # Historical Gregorian in the 1560s is well-defined.
      {:ok, set} = Tempo.select(~o"156X", Tempo.workdays(:US))
      count = IntervalSet.count(set)
      assert count > 2500 and count < 2700
    end

    test "stepped month range (`{1..-1//3}M`) returns workdays in each quarterly month" do
      # Jan, Apr, Jul, Oct — four months worth of workdays.
      {:ok, set} = Tempo.select(~o"2026Y{1..-1//3}M", Tempo.workdays(:US))
      count = IntervalSet.count(set)
      # 4 months × ~22 workdays ≈ 88. Exact value depends on which
      # days of week the month edges land on.
      assert count in 80..95
    end
  end

  describe "error cases" do
    test "an unrecognised selector returns an error tuple" do
      assert {:error, message} = Tempo.select(~o"2026-02", :banana)
      assert Exception.message(message) =~ "does not recognise selector :banana"
      assert Exception.message(message) =~ "selector vocabulary"
    end

    test "an unrecognised constraint in a list returns an error tuple" do
      assert {:error, %ArgumentError{} = error} = Tempo.select(~o"2026", [~o"12-25", 5])
      assert Exception.message(error) =~ "does not recognise selector 5"
    end

    test "a base select/2 cannot select from returns an error tuple" do
      for base <- [nil, "", :"", "2026-06", 42, %{}, [1, 2]] do
        assert {:error, %ArgumentError{} = error} = Tempo.select(base, Tempo.workdays(:US))
        assert Exception.message(error) =~ "cannot select from"
      end
    end

    test "an error selector is returned as it is" do
      assert {:error, %ArgumentError{}} = Tempo.select(~o"2026-02", Tempo.workdays(:""))
      assert {:error, %ArgumentError{}} = Tempo.select(~o"2026-02", Tempo.weekends(42))
      assert {:error, :reason} = Tempo.select(~o"2026-02", {:error, :reason})
    end

    test "a span with an open start has no first period to select from" do
      for base <- [~o"../2026-06-15", ~o"../.."] do
        assert {:error, %Tempo.IntervalEndpointsError{reason: :open_start} = error} =
                 Tempo.select(base, Tempo.workdays(:US))

        assert Exception.message(error) =~ "selects forward from a span's start"
      end

      assert {:error, %Tempo.IntervalEndpointsError{reason: :open_start}} =
               Tempo.select(~o"../2026", ~o"12-25")
    end
  end

  describe "a span is selected period by period" do
    test "every year of a span of years" do
      {:ok, set} = Tempo.select(~o"2026/2029", ~o"12-25")

      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) ==
               [~o"2026Y12M25D", ~o"2027Y12M25D", ~o"2028Y12M25D"]
    end

    test "every month of a span of months" do
      {:ok, set} = Tempo.select(~o"2026-06/2026-09", [1, 15])

      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) ==
               [
                 ~o"2026Y6M1D",
                 ~o"2026Y6M15D",
                 ~o"2026Y7M1D",
                 ~o"2026Y7M15D",
                 ~o"2026Y8M1D",
                 ~o"2026Y8M15D"
               ]
    end

    test "every day of a span of days" do
      {:ok, set} = Tempo.select(~o"2026-06-15/2026-06-18", ~o"T09/T17")
      assert IntervalSet.count(set) == 3
    end

    test "the last day of each month" do
      {:ok, set} = Tempo.select(~o"2026-06/2026-09", ~o"-1D")

      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) ==
               [~o"2026Y6M30D", ~o"2026Y7M31D", ~o"2026Y8M31D"]
    end

    test "a quarter is selected in each of its months" do
      {:ok, set} = Tempo.select(~o"2026Y3Q", [1, 15])
      assert IntervalSet.count(set) == 6
    end

    test "a span that ends mid-period keeps what starts before its end" do
      {:ok, set} = Tempo.select(~o"2026-06/2026-09-15", [1, 15])
      assert set |> IntervalSet.members() |> List.last() |> Interval.from() == ~o"2026Y9M1D"
    end

    test "a selection starts in its period, so nothing past the span's end is selected" do
      {:ok, set} = Tempo.select(~o"2026-06", ~o"07-01")
      assert IntervalSet.count(set) == 0

      {:ok, set} = Tempo.select(~o"2026-06", ~o"7M")
      assert IntervalSet.count(set) == 0
    end

    test "business hours land on every day of a coalesced run of workdays" do
      {:ok, workdays} = Tempo.select(~o"2026-06-15/2026-06-22", Tempo.workdays(:US))
      run = IntervalSet.coalesce(workdays)
      assert IntervalSet.count(run) == 1

      {:ok, open} = Tempo.select(run, ~o"T09/T17")
      assert IntervalSet.count(open) == 5
    end

    test "a duration-form interval and a recurrence are converted first" do
      {:ok, fortnight} = Tempo.select(~o"2026-06-15/P14D", Tempo.weekends(:US))
      assert IntervalSet.count(fortnight) == 4

      {:ok, weeks} = Tempo.select(~o"R3/2026-06-15/P1W", Tempo.weekends(:US))
      assert IntervalSet.count(weeks) == 6
    end
  end

  describe "an integer index the period does not have" do
    test "selects nothing there" do
      {:ok, set} = Tempo.select(~o"2026-02", [28, 29, 30, 31])
      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) == [~o"2026Y2M28D"]

      {:ok, set} = Tempo.select(~o"2026", [13])
      assert IntervalSet.count(set) == 0
    end

    test "is kept in the periods that have it" do
      {:ok, set} = Tempo.select(~o"2026-01/2026-05", [31])

      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) ==
               [~o"2026Y1M31D", ~o"2026Y3M31D"]
    end

    test "a negative index counts from the end" do
      {:ok, set} = Tempo.select(~o"2026", [-1])
      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) == [~o"2026Y12M"]
    end
  end

  describe "an open-ended span gives a lazy set" do
    defp first_days(set, count) do
      set
      |> IntervalSet.walk()
      |> Enum.take(count)
      |> Enum.map(&Tempo.day(Interval.from(&1)))
    end

    test "the weekend days from a date on" do
      {:ok, weekends} = Tempo.select(~o"2026-06-15/..", Tempo.weekends(:US))
      refute IntervalSet.bounded?(weekends)
      assert first_days(weekends, 4) == [20, 21, 27, 28]

      {:ok, saudi} = Tempo.select(~o"2026-06-15/..", Tempo.weekends(:SA))
      assert first_days(saudi, 4) == [19, 20, 26, 27]
    end

    test "the weekend days serve as a busy set for shift/3" do
      {:ok, weekends} = Tempo.select(~o"2026-06-18/..", Tempo.weekends(:US))

      assert Tempo.shift(~o"2026-06-18T16:00", ~o"P3D", skipping: weekends) ==
               ~o"2026-06-23T16:00:00"
    end

    test "a projection selects in each period as the walk reaches it" do
      {:ok, christmases} = Tempo.select(~o"2026-06-15/..", ~o"12-25")

      assert christmases |> IntervalSet.walk() |> Enum.take(3) |> Enum.map(&Interval.from/1) ==
               [~o"2026Y12M25D", ~o"2027Y12M25D", ~o"2028Y12M25D"]
    end

    test "indices and time windows apply to each period" do
      {:ok, fifteenths} = Tempo.select(~o"2026-06/..", [15])

      assert fifteenths |> IntervalSet.walk() |> Enum.take(3) |> Enum.map(&Interval.from/1) ==
               [~o"2026Y6M15D", ~o"2026Y7M15D", ~o"2026Y8M15D"]

      {:ok, hours} = Tempo.select(~o"2026-06-15/..", ~o"T09/T17")
      assert first_days(hours, 2) == [15, 16]
    end

    test "a selection across a lazy set is lazy too" do
      {:ok, workdays} = Tempo.select(~o"2026-06-19/..", Tempo.workdays(:US))
      {:ok, hours} = Tempo.select(workdays, ~o"T09/T17")
      refute IntervalSet.bounded?(hours)
      assert first_days(hours, 2) == [19, 22]
    end

    test "the walk ends after the last year a selector names" do
      {:ok, christmas} = Tempo.select(~o"2026-06-15/..", ~o"2026-12-25")

      assert christmas |> IntervalSet.walk() |> Enum.to_list() |> Enum.map(&Interval.from/1) ==
               [~o"2026Y12M25D"]
    end

    test "a selector that names no day of the week selects nothing" do
      no_days = %Tempo{time: [day_of_week: []], calendar: Calendrical.Gregorian}
      assert {:ok, set} = Tempo.select(~o"2026-06-15/..", no_days)
      assert IntervalSet.count(set) == 0
    end

    test "an empty selector selects nothing" do
      assert {:ok, set} = Tempo.select(~o"2026-06-15/..", [])
      assert IntervalSet.count(set) == 0
    end

    test "an unrecognised selector is the first period's error" do
      assert {:error, %ArgumentError{}} = Tempo.select(~o"2026-06-15/..", :banana)
    end
  end

  describe "return shape" do
    test "always returns {:ok, %Tempo.IntervalSet{}} on success" do
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026-02", [1, 15])
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026", ~o"12-25")
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026-02", fn _ -> [1] end)
    end

    test "selected day intervals are half-open single-day spans" do
      {:ok, set} = Tempo.select(~o"2026-02", [15])
      [day] = IntervalSet.members(set)

      # The span runs from day 15 to day 16 — half-open. `to_interval`
      # may additionally fill the endpoints with `hour: 0` etc., so
      # we compare only the year/month/day components.
      assert {day.from.time[:year], day.from.time[:month], day.from.time[:day]} ==
               {2026, 2, 15}

      assert {day.to.time[:year], day.to.time[:month], day.to.time[:day]} ==
               {2026, 2, 16}
    end
  end

  describe "Tempo.Set base" do
    test "a set-of-intervals sigil materialises and flat-maps the selector" do
      # Two one-week on-call stints; the weekend days within them.
      rota = ~o"{2025-12-29/2026-01-05,2026-01-19/2026-01-26}"

      {:ok, weekend_days} = Tempo.select(rota, Tempo.weekends(:US))

      days =
        weekend_days
        |> IntervalSet.members()
        |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})

      # Sat/Sun of 2026-W01 (Jan 3-4) and of 2026-W04 (Jan 24-25).
      assert days == [{1, 3}, {1, 4}, {1, 24}, {1, 25}]
    end

    test "an unmaterialisable set returns {:error, _} rather than raising" do
      assert {:error, _} = Tempo.select(~o"{2026-01-05/2026-01-12}", :nonsense)
    end
  end

  describe "a projection that cannot land is skipped" do
    # The merge builds its `%Tempo{}` field-by-field rather than through
    # the parser, so nothing had checked the result was a date that
    # exists. Every year got a 29 February.
    test "29 February selects only in leap years" do
      {:ok, set} = Tempo.select(~o"{2026..2029}Y", ~o"2M29D")

      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) ==
               [~o"2028Y2M29D"]
    end

    test "a single non-leap year selects nothing rather than a phantom date" do
      assert {:ok, empty} = Tempo.select(~o"2026", ~o"2M29D")
      assert IntervalSet.count(empty) == 0
    end

    test "a span either end of which cannot land is skipped too" do
      {:ok, from_leap_day} = Interval.new(from: ~o"2M29D", to: ~o"3M2D")
      {:ok, set} = Tempo.select(~o"{2026..2029}Y", from_leap_day)

      assert set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1) ==
               ["2028Y2M29D/3M2D"]

      {:ok, to_leap_day} = Interval.new(from: ~o"2M27D", to: ~o"2M29D")
      assert {:ok, empty} = Tempo.select(~o"2026", to_leap_day)
      assert IntervalSet.count(empty) == 0
    end

    test "on/2 reports the same impossible date, because it names one year" do
      # Selecting across a range skips what cannot exist; placing the day on
      # exactly one year has nothing to skip to, so it says so.
      assert {:error, %InvalidDateError{}} = Tempo.on(~o"2M29D", ~o"2026")
      assert Tempo.on(~o"2M29D", ~o"2028") == {:ok, ~o"2028Y2M29D"}
    end

    test "a date that always exists is unaffected" do
      {:ok, set} = Tempo.select(~o"{2026..2028}Y", ~o"4M3D")

      assert set |> IntervalSet.members() |> Enum.map(&Interval.from/1) ==
               [~o"2026Y4M3D", ~o"2027Y4M3D", ~o"2028Y4M3D"]
    end
  end

  describe "an ISO 8601-2 selection" do
    defp selected(base, selector) do
      {:ok, set} = Tempo.select(base, selector)
      set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
    end

    test "a computed event selects its day in each period" do
      assert selected(~o"2027", ~o"L(easter)eN") == ["2027Y3M28D/29D"]

      assert selected(~o"2026/2029", ~o"L(easter)eN") ==
               ["2026Y4M5D/6D", "2027Y3M28D/29D", "2028Y4M16D/17D"]
    end

    test "a §12.10 window selects within it, or nothing" do
      # The Friday that falls 7–13 April, and the Thursday that falls
      # 17–21 December, of which 2027 has none.
      assert selected(~o"2027", ~o"LLL4M7DN/P7DN5K1IN") == ["2027Y4M9D/10D"]
      assert selected(~o"2027", ~o"LLL12M17DN/P5DN4K1IN") == []

      # The five days from the fourth Wednesday.
      assert selected(~o"2026", ~o"LL3K4IN/P5DN") == ["2026Y1M28D/2M2D"]
    end

    test "a selection applies at the period's own cadence" do
      assert selected(~o"2027-04", ~o"L1K1IN") == ["2027Y4M5D/6D"]

      assert selected(~o"2027-04/2027-07", ~o"L1K1IN") ==
               ["2027Y4M5D/6D", "2027Y5M3D/4D", "2027Y6M7D/8D"]

      assert selected(~o"2027-04-09", ~o"LT22HN") == ["2027Y4M9DT22H/T23H"]
    end

    test "units before a selection narrow the period first" do
      assert selected(~o"2027", ~o"4ML1K1IN") == ["2027Y4M5D/6D"]
      assert selected(~o"2026/2028", ~o"4ML1K1IN") == ["2026Y4M6D/7D", "2027Y4M5D/6D"]
      assert selected(~o"2027", ~o"2027YL12M25DN") == ["2027Y12M25D/26D"]
      assert selected(~o"2026", ~o"2027YL12M25DN") == []
    end

    test "a list mixes selections with values" do
      assert selected(~o"2027", [~o"L(easter)eN", ~o"L12M25DN"]) ==
               ["2027Y3M28D/29D", "2027Y12M25D/26D"]
    end

    test "an open-ended span selects lazily" do
      {:ok, easters} = Tempo.select(~o"2026/..", ~o"L(easter)eN")

      assert easters |> IntervalSet.walk() |> Enum.take(2) |> Enum.map(&Tempo.to_iso8601!/1) ==
               ["2026Y4M5D/6D", "2027Y3M28D/29D"]
    end
  end

  # The weekdays a constraint names are read by `Tempo.UnitValues`, as every
  # count from the end is: a set held a count from the end as it was written
  # and a range as a range, neither of which is a weekday, and a time of day
  # after a weekday was dropped.
  describe "a set or a range of weekdays, and a weekday with a time of day" do
    defp starts(set),
      do: set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!(Interval.from(&1)))

    test "a range of weekdays that reaches the end of the week" do
      {:ok, weekend} = Tempo.select(~o"2026-06", ~o"{6..-1}K")

      assert starts(weekend) ==
               ~w(2026Y6M6D 2026Y6M7D 2026Y6M13D 2026Y6M14D 2026Y6M20D 2026Y6M21D 2026Y6M27D 2026Y6M28D)
    end

    test "a range of weekdays" do
      {:ok, days} = Tempo.select(~o"2026-06-01/2026-06-08", ~o"{1..3}K")
      assert starts(days) == ~w(2026Y6M1D 2026Y6M2D 2026Y6M3D)
    end

    test "the first and the last day of the week" do
      {:ok, days} = Tempo.select(~o"2026-06-01/2026-06-15", ~o"{1,-1}K")
      assert starts(days) == ~w(2026Y6M1D 2026Y6M7D 2026Y6M8D 2026Y6M14D)
    end

    test "in a span with no end" do
      {:ok, weekends} = Tempo.select(~o"2026-06-15/..", ~o"{6..-1}K")

      assert weekends
             |> IntervalSet.walk()
             |> Enum.take(2)
             |> Enum.map(&Tempo.day(Interval.from(&1))) ==
               [20, 21]
    end

    test "a weekday with a time of day is that time on each of the days" do
      {:ok, mondays_at_ten} = Tempo.select(~o"2026-06", ~o"1KT10H")

      assert starts(mondays_at_ten) ==
               ~w(2026Y6M1DT10H 2026Y6M8DT10H 2026Y6M15DT10H 2026Y6M22DT10H 2026Y6M29DT10H)
    end

    test "a weekday with the last hour of the day" do
      {:ok, last_hours} = Tempo.select(~o"2026-06-01/2026-06-09", ~o"1KT-1H")
      assert starts(last_hours) == ~w(2026Y6M1DT23H 2026Y6M8DT23H)
    end
  end

  describe "the metadata of what is selected" do
    defp metadata_of(set), do: set |> IntervalSet.members() |> Enum.map(&Tempo.metadata/1)

    test "each day selected from a base keeps the base's metadata" do
      {:ok, term} = Interval.new(from: ~o"2027-07-19", to: ~o"2027-07-24", metadata: %{term: 3})

      {:ok, workdays} = Tempo.select(term, Tempo.workdays(:AU))
      assert metadata_of(workdays) == List.duplicate(%{term: 3}, 5)

      {:ok, school_days} = Tempo.select(term, Tempo.workdays(:AU, except: ~o"2027-07-20"))
      assert metadata_of(school_days) == List.duplicate(%{term: 3}, 4)

      {:ok, fridays} = Tempo.select(term, ~o"5K")
      assert metadata_of(fridays) == [%{term: 3}]
    end

    test "each member of a set tags its own days, and the set keeps its own metadata" do
      {:ok, term_1} = Interval.new(from: ~o"2027-01-28", to: ~o"2027-01-30", metadata: %{term: 1})
      {:ok, term_2} = Interval.new(from: ~o"2027-04-27", to: ~o"2027-04-29", metadata: %{term: 2})
      {:ok, terms} = IntervalSet.new([term_1, term_2], metadata: %{division: :eastern})

      {:ok, days} = Tempo.select(terms, Tempo.workdays(:AU))

      assert Enum.map(metadata_of(days), & &1.term) == [1, 1, 2, 2]
      assert IntervalSet.metadata(days) == %{division: :eastern}
    end

    test "a value's metadata, through an ISO 8601-2 selection and a projection" do
      year = Tempo.put_metadata(~o"2027", %{calendar_year: true})

      {:ok, easter} = Tempo.select(year, ~o"L(easter)eN")
      assert metadata_of(easter) == [%{calendar_year: true}]

      {:ok, christmas} = Tempo.select(year, ~o"12-25")
      assert metadata_of(christmas) == [%{calendar_year: true}]
    end

    test "an open-ended span's days, as the walk reaches them" do
      {:ok, booking} = Interval.new(from: ~o"2027-06-15", metadata: %{booking: 42})
      {:ok, weekends} = Tempo.select(booking, Tempo.weekends(:AU))

      assert weekends |> IntervalSet.walk() |> Enum.take(3) |> Enum.map(&Tempo.metadata/1) ==
               List.duplicate(%{booking: 42}, 3)
    end

    test "a base without metadata selects days without it" do
      {:ok, days} = Tempo.select(~o"2027-07-19/2027-07-21", Tempo.workdays(:AU))
      assert metadata_of(days) == [%{}, %{}]
    end
  end
end
