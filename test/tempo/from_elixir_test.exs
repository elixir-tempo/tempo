defmodule Tempo.FromElixir.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Calendrical.FiscalYear
  alias Tempo.Interval
  alias Tempo.IntervalSet

  # `Tempo.from_elixir/2` unifies Date, Time, NaiveDateTime, and
  # DateTime into `%Tempo{}`. The intended resolution is inferred
  # from the input (or overridden by `:resolution`), then applied
  # via `at_resolution/2`.
  #
  # These tests also cover the two primitives `from_elixir` builds
  # on: `extend_resolution/2` (pad with minimums) and
  # `at_resolution/2` (dispatcher between trunc and extend).

  setup_all do
    # DateTime construction with IANA zones needs a time zone DB.
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    :ok
  end

  describe "from_elixir/2 — Date.t" do
    test "default resolution is :day" do
      assert Tempo.from_elixir(~D[2022-06-15]) == ~o"2022Y6M15D"
    end

    test "explicit :resolution :hour pads with hour: 0" do
      tempo = Tempo.from_elixir(~D[2022-06-15], resolution: :hour)
      assert tempo.time == [year: 2022, month: 6, day: 15, hour: 0]
    end

    test "explicit :resolution :second pads all the way" do
      tempo = Tempo.from_elixir(~D[2022-06-15], resolution: :second)

      assert tempo.time == [
               year: 2022,
               month: 6,
               day: 15,
               hour: 0,
               minute: 0,
               second: 0
             ]
    end

    test "explicit :resolution :year truncates to year" do
      tempo = Tempo.from_elixir(~D[2022-06-15], resolution: :year)
      assert tempo.time == [year: 2022]
    end
  end

  describe "from_elixir/2 — Time.t (resolution inference)" do
    # A `Time` is second-granular by type; resolution follows the
    # declared precision, not the magnitude of the components. A zero
    # second/minute is a fully specified zero, not an absent unit.
    test "~T[10:30:00] → :second (zero second is still specified)" do
      assert Tempo.from_elixir(~T[10:30:00]).time == [hour: 10, minute: 30, second: 0]
    end

    test "~T[10:30:45] → :second (all non-zero to second)" do
      assert Tempo.from_elixir(~T[10:30:45]).time == [hour: 10, minute: 30, second: 45]
    end

    test "~T[10:00:00] → :second (zero minute and second still specified)" do
      assert Tempo.from_elixir(~T[10:00:00]).time == [hour: 10, minute: 0, second: 0]
    end

    test "~T[00:00:00] → :second (midnight is a fully specified second)" do
      assert Tempo.from_elixir(~T[00:00:00]).time == [hour: 0, minute: 0, second: 0]
    end

    test "microsecond is preserved as a :microsecond component" do
      # `~T[10:30:45.123]` carries microsecond precision 3; it is
      # threaded into a `:microsecond {value, precision}` component.
      assert Tempo.from_elixir(~T[10:30:45.123]).time ==
               [hour: 10, minute: 30, second: 45, microsecond: {123_000, 3}]
    end
  end

  describe "from_elixir/2 — NaiveDateTime.t (resolution inference)" do
    # A `NaiveDateTime` is second-granular by type, so even an all-zero
    # time is second resolution — not coarsened to day/hour/minute by
    # the magnitude of its components. Pass `:resolution` to widen.
    test "midnight is second resolution (not coarsened to :day)" do
      assert Tempo.from_elixir(~N[2022-06-15 00:00:00]).time ==
               [year: 2022, month: 6, day: 15, hour: 0, minute: 0, second: 0]
    end

    test "zero minute and second stay specified" do
      assert Tempo.from_elixir(~N[2022-06-15 10:00:00]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 0, second: 0]
    end

    test "zero second stays specified" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:00]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 30, second: 0]
    end

    test "second resolution" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:45]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 30, second: 45]
    end

    test "microsecond is preserved as a :microsecond component" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:45.123]).time ==
               [
                 year: 2022,
                 month: 6,
                 day: 15,
                 hour: 10,
                 minute: 30,
                 second: 45,
                 microsecond: {123_000, 3}
               ]
    end

    test "explicit :resolution overrides inference" do
      # Source is minute resolution; we ask for day.
      tempo = Tempo.from_elixir(~N[2022-06-15 10:30:00], resolution: :day)
      assert tempo.time == [year: 2022, month: 6, day: 15]
    end
  end

  describe "from_elixir/2 — DateTime.t" do
    test "UTC datetime is second resolution" do
      tempo = Tempo.from_elixir(~U[2022-06-15 10:30:00Z])
      assert tempo.time == [year: 2022, month: 6, day: 15, hour: 10, minute: 30, second: 0]
      assert tempo.shift == [hour: 0]
      assert tempo.extended.zone_id == "Etc/UTC"
    end

    test "zoned datetime carries zone_id and offset" do
      dt = DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris")
      tempo = Tempo.from_elixir(dt)
      assert tempo.extended.zone_id == "Europe/Paris"
      # June is summer time (CEST = UTC+2).
      assert tempo.shift == [hour: 2]
      assert tempo.extended.zone_offset == 120
    end

    test "negative offset (America/New_York winter)" do
      dt = DateTime.new!(~D[2022-12-25], ~T[14:00:00], "America/New_York")
      tempo = Tempo.from_elixir(dt)
      # EST = UTC-5.
      assert tempo.shift == [hour: -5]
      assert tempo.extended.zone_offset == -300
    end

    test "midnight UTC is second resolution (not coarsened to :day)" do
      tempo = Tempo.from_elixir(~U[2022-06-15 00:00:00Z])
      assert tempo.time == [year: 2022, month: 6, day: 15, hour: 0, minute: 0, second: 0]
    end
  end

  describe "extend_resolution/2" do
    test "year → day" do
      assert Tempo.extend_resolution(~o"2020Y", :day) == ~o"2020Y1M1D"
    end

    test "year-month → hour" do
      assert Tempo.extend_resolution(~o"2020Y6M", :hour) == ~o"2020Y6M1DT0H"
    end

    test "year-month-day → second" do
      tempo = Tempo.extend_resolution(~o"2020Y6M15D", :second)
      assert tempo.time == [year: 2020, month: 6, day: 15, hour: 0, minute: 0, second: 0]
    end

    test "idempotent at the current resolution" do
      source = ~o"2020Y6M15D"
      assert Tempo.extend_resolution(source, :day) == source
    end

    test "coarser target returns an error" do
      assert {:error, message} = Tempo.extend_resolution(~o"2020Y6M15D", :year)
      assert Exception.message(message) =~ ":year is coarser"
      assert Exception.message(message) =~ "Tempo.trunc/2"
    end
  end

  describe "at_resolution/2" do
    test "finer target calls extend_resolution" do
      assert Tempo.at_resolution(~o"2020Y", :day) == ~o"2020Y1M1D"
    end

    test "coarser target calls trunc" do
      assert Tempo.at_resolution(~o"2020Y6M15DT10H", :day) == ~o"2020Y6M15D"
    end

    test "equal target is idempotent" do
      source = ~o"2020Y6M15D"
      assert Tempo.at_resolution(source, :day) == source
    end

    test "invalid unit atom returns error" do
      assert {:error, _} = Tempo.at_resolution(~o"2020Y", :nonsense)
    end
  end

  describe "round-trip via from_elixir/2 and to_*/1" do
    test "Date round-trip at :day" do
      date = ~D[2022-06-15]
      tempo = Tempo.from_elixir(date)
      assert {:ok, ^date} = Tempo.to_date(tempo)
    end

    test "NaiveDateTime round-trips at the default (second) resolution" do
      # Previously this required an explicit `resolution: :second`
      # because `from_elixir/1` coarsened `10:30:00` to minute
      # resolution and `to_naive_date_time/1` then failed. The default
      # is now second resolution, so the round-trip succeeds with no
      # override. NaiveDateTime's microsecond field defaults to
      # `{0, 0}` for sigil literals and to `{0, 6}` for
      # `to_naive_date_time/1` output, so compare component-wise
      # rather than structurally.
      naive = ~N[2022-06-15 10:30:00]
      tempo = Tempo.from_elixir(naive)
      assert {:ok, round_tripped} = Tempo.to_naive_date_time(tempo)
      assert NaiveDateTime.compare(round_tripped, naive) == :eq
    end

    test "zoned DateTime → to_naive_date_time keeps wall-clock, drops zone" do
      # Paris is UTC+2 in June; the wall reading is 10:30, not 08:30.
      paris = DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris")
      tempo = Tempo.from_elixir(paris)
      assert {:ok, ~N[2022-06-15 10:30:00.000000]} = Tempo.to_naive_date_time(tempo)
    end

    test "zoned DateTime → to_date_time preserves the zone and instant" do
      paris = DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris")
      tempo = Tempo.from_elixir(paris)
      assert {:ok, round_tripped} = Tempo.to_date_time(tempo)
      assert round_tripped.time_zone == "Europe/Paris"
      assert DateTime.compare(round_tripped, paris) == :eq
    end
  end

  describe "from_elixir/2 and to_elixir/1 — Duration" do
    # `Duration` here is Elixir's stdlib struct (this module does not
    # alias `Tempo.Duration`).

    test "from_elixir maps an Elixir Duration to a Tempo.Duration" do
      assert Tempo.from_elixir(Duration.new!(hour: 8)).time == [hour: 8]
      assert Tempo.from_elixir(Duration.new!(year: 1, month: 6)).time == [year: 1, month: 6]
    end

    test "from_elixir drops zero components, keeps present ones" do
      assert Tempo.from_elixir(Duration.new!(day: 3, second: 30)).time == [day: 3, second: 30]
    end

    test "to_elixir maps a Tempo.Duration to an Elixir Duration" do
      assert Tempo.to_elixir(~o"PT8H") == {:ok, Duration.new!(hour: 8)}

      assert Tempo.to_elixir(~o"P1Y2M3DT4H5M6S") ==
               {:ok, Duration.new!(year: 1, month: 2, day: 3, hour: 4, minute: 5, second: 6)}
    end

    test "microsecond precision survives the round-trip" do
      elixir = Duration.new!(microsecond: {123_456, 6})
      assert {:ok, ^elixir} = Tempo.to_elixir(Tempo.from_elixir(elixir))
    end

    test "round-trips every ISO 8601 duration form" do
      for iso <- ["PT8H", "P1Y6M", "PT0.5S", "PT0.123456S", "P1W", "P1Y2M3DT4H5M6S"] do
        {:ok, tempo} = Tempo.from_iso8601(iso)
        {:ok, elixir} = Tempo.to_elixir(tempo)
        round_tripped = Tempo.from_elixir(elixir)

        assert Tempo.to_iso8601(round_tripped) == Tempo.to_iso8601(tempo),
               "round-trip failed for #{iso}"
      end
    end

    test "to_elixir of a Tempo value returns its best-fit native calendar type" do
      assert Tempo.to_elixir(~o"2026-06-15") == {:ok, ~D[2026-06-15]}
    end

    test "to_elixir maps a Gregorian value to Calendar.ISO at the boundary" do
      {:ok, date} = Tempo.to_elixir(~o"2026-06-15")
      assert date.calendar == Calendar.ISO
    end

    test "to_elixir preserves a non-Gregorian value's calendar at the boundary" do
      {:ok, hebrew_tempo} = Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)
      {:ok, hebrew_date} = Tempo.to_elixir(hebrew_tempo)

      assert hebrew_date.calendar == Calendrical.Hebrew
      assert {hebrew_date.year, hebrew_date.month, hebrew_date.day} == {5786, 10, 30}
    end

    test "to_elixir errors on a Tempo-only duration component" do
      weekday_duration = %Tempo.Duration{time: [day_of_week: 3]}
      assert {:error, %Tempo.ConversionError{}} = Tempo.to_elixir(weekday_duration)
    end
  end

  describe "to_calendar/2 — cross-calendar conversion" do
    test "an interval converts both endpoints" do
      {:ok, converted} =
        Tempo.to_calendar(~o"2026-06-15/2026-06-16", Calendrical.Hebrew)

      assert Tempo.to_iso8601(converted) == "5786Y10M30D/5786Y11M1D"
    end

    test "a fiscal quarter reads back as the Gregorian dates it covers" do
      {:ok, calendar} = FiscalYear.calendar_for(:AU)
      {:ok, quarter} = Tempo.from_elixir(calendar.quarter(2027, 1))

      {:ok, gregorian} = Tempo.to_calendar(quarter, Calendrical.Gregorian)

      assert Tempo.to_iso8601(gregorian) == "2026Y7M1D/2026Y10M1D"
    end

    test "an interval keeps what it was carrying" do
      # A rebuilt interval loses these, which is the reason for taking
      # the whole value rather than its endpoints.
      original = %Interval{
        from: ~o"2026-06-15",
        to: ~o"2026-06-16",
        recurrence: 3,
        unit: :day,
        metadata: %{summary: "Standup"}
      }

      {:ok, converted} = Tempo.to_calendar(original, Calendrical.Hebrew)

      assert converted.recurrence == 3
      assert converted.unit == :day
      assert converted.metadata == %{summary: "Standup"}
    end

    test "an unbounded end stays unbounded" do
      {:ok, converted} = Tempo.to_calendar(~o"2026-06-15/..", Calendrical.Hebrew)

      assert Tempo.to_iso8601(Interval.from(converted)) == "5786Y10M30D"
      assert Interval.to(converted) in [nil, :undefined]
    end

    test "an interval whose endpoints are not days is refused" do
      assert {:error, %Tempo.ConversionError{}} =
               Tempo.to_calendar(
                 ~o"2026-06-15T09:00:00/2026-06-15T17:00:00",
                 Calendrical.Hebrew
               )
    end

    test "an interval set converts every member" do
      {:ok, set} =
        IntervalSet.new([~o"2026-06-15/2026-06-16", ~o"2026-07-01/2026-07-02"])

      {:ok, converted} = Tempo.to_calendar(set, Calendrical.Hebrew)

      assert IntervalSet.count(converted) == 2
      assert [first, _second] = IntervalSet.members(converted)
      assert Tempo.to_iso8601(first) == "5786Y10M30D/5786Y11M1D"
    end

    test "one unconvertible member fails the whole set" do
      {:ok, set} =
        IntervalSet.new([
          ~o"2026-06-15/2026-06-16",
          ~o"2026-07-01T09:00:00/2026-07-01T17:00:00"
        ])

      assert {:error, %Tempo.ConversionError{}} =
               Tempo.to_calendar(set, Calendrical.Hebrew)
    end

    test "an empty set converts to an empty set" do
      {:ok, converted} = Tempo.to_calendar(IntervalSet.new!([]), Calendrical.Hebrew)

      assert IntervalSet.count(converted) == 0
    end

    test "a converted interval round-trips" do
      {:ok, hebrew} = Tempo.to_calendar(~o"2026-06-15/2026-06-16", Calendrical.Hebrew)
      {:ok, back} = Tempo.to_calendar(hebrew, Calendrical.Gregorian)

      assert Tempo.to_iso8601(back) == "2026Y6M15D/2026Y6M16D"
    end

    test "converts a value into another calendar, preserving the day" do
      {:ok, hebrew} = Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)

      assert hebrew.calendar == Calendrical.Hebrew
      assert {Tempo.year(hebrew), Tempo.month(hebrew), Tempo.day(hebrew)} == {5786, 10, 30}
    end

    test "round-trips back to the Gregorian day" do
      {:ok, hebrew} = Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)
      {:ok, gregorian} = Tempo.to_calendar(hebrew, Calendar.ISO)

      assert {Tempo.year(gregorian), Tempo.month(gregorian), Tempo.day(gregorian)} ==
               {2026, 6, 15}
    end

    test "refuses a value that is not a plain day" do
      assert {:error, %Tempo.ConversionError{}} =
               Tempo.to_calendar(~o"2026", Calendrical.Hebrew)

      assert {:error, %Tempo.ConversionError{}} =
               Tempo.to_calendar(~o"2026-06-15T10:30:00", Calendrical.Hebrew)
    end
  end
end
