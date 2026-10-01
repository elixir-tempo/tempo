defmodule Tempo.Enumeration.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  test "Enumeration of basic double" do
    assert Enum.map(~o"2022Y{1,2}M{1..2}D", & &1) == [
             %Tempo{
               time: [year: 2022, month: 1, day: 1],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2022, month: 1, day: 2],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2022, month: 2, day: 1],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2022, month: 2, day: 2],
               shift: nil,
               calendar: Calendrical.Gregorian
             }
           ]
  end

  test "Enumeration of basic triple" do
    assert Enum.map(~o"{2021,2022}Y{1,2}M{1..2}D", & &1) == [
             %Tempo{
               time: [year: 2021, month: 1, day: 1],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2021, month: 1, day: 2],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2021, month: 2, day: 1],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2021, month: 2, day: 2],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2022, month: 1, day: 1],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2022, month: 1, day: 2],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2022, month: 2, day: 1],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [year: 2022, month: 2, day: 2],
               shift: nil,
               calendar: Calendrical.Gregorian
             }
           ]
  end

  test "Enumeration with a constant after a range" do
    assert Enum.map(~o"{1,2}M23D", & &1) == [
             %Tempo{
               time: [month: 1, day: 23],
               shift: nil,
               calendar: Calendrical.Gregorian
             },
             %Tempo{
               time: [month: 2, day: 23],
               shift: nil,
               calendar: Calendrical.Gregorian
             }
           ]
  end

  test "Enumeration with a range, then constant, then range" do
    assert Enum.map(~o"{1,2}M23DT{3,4}H", & &1) ==
             [
               %Tempo{
                 time: [month: 1, day: 23, hour: 3],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               },
               %Tempo{
                 time: [month: 1, day: 23, hour: 4],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               },
               %Tempo{
                 time: [month: 2, day: 23, hour: 3],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               },
               %Tempo{
                 time: [month: 2, day: 23, hour: 4],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               }
             ]
  end

  test "Enumeration with negative range and cascading ranges" do
    assert Enum.map(~o"2022Y{1,2}M{1..-28}D", & &1) ==
             [
               %Tempo{
                 time: [year: 2022, month: 1, day: 1],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               },
               %Tempo{
                 time: [year: 2022, month: 1, day: 2],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               },
               %Tempo{
                 time: [year: 2022, month: 1, day: 3],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               },
               %Tempo{
                 time: [year: 2022, month: 1, day: 4],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               },
               %Tempo{
                 time: [year: 2022, month: 2, day: 1],
                 shift: nil,
                 calendar: Calendrical.Gregorian
               }
             ]
  end

  test "Implicit Enumeration" do
    assert Enum.map(~o"2022", & &1) ==
             [
               ~o"2022Y1M",
               ~o"2022Y2M",
               ~o"2022Y3M",
               ~o"2022Y4M",
               ~o"2022Y5M",
               ~o"2022Y6M",
               ~o"2022Y7M",
               ~o"2022Y8M",
               ~o"2022Y9M",
               ~o"2022Y10M",
               ~o"2022Y11M",
               ~o"2022Y12M"
             ]

    assert Enum.map(~o"2022Y2M", & &1) ==
             [
               ~o"2022Y2M1D",
               ~o"2022Y2M2D",
               ~o"2022Y2M3D",
               ~o"2022Y2M4D",
               ~o"2022Y2M5D",
               ~o"2022Y2M6D",
               ~o"2022Y2M7D",
               ~o"2022Y2M8D",
               ~o"2022Y2M9D",
               ~o"2022Y2M10D",
               ~o"2022Y2M11D",
               ~o"2022Y2M12D",
               ~o"2022Y2M13D",
               ~o"2022Y2M14D",
               ~o"2022Y2M15D",
               ~o"2022Y2M16D",
               ~o"2022Y2M17D",
               ~o"2022Y2M18D",
               ~o"2022Y2M19D",
               ~o"2022Y2M20D",
               ~o"2022Y2M21D",
               ~o"2022Y2M22D",
               ~o"2022Y2M23D",
               ~o"2022Y2M24D",
               ~o"2022Y2M25D",
               ~o"2022Y2M26D",
               ~o"2022Y2M27D",
               ~o"2022Y2M28D"
             ]

    assert Enum.map(~o"2020Y2M", & &1) ==
             [
               ~o"2020Y2M1D",
               ~o"2020Y2M2D",
               ~o"2020Y2M3D",
               ~o"2020Y2M4D",
               ~o"2020Y2M5D",
               ~o"2020Y2M6D",
               ~o"2020Y2M7D",
               ~o"2020Y2M8D",
               ~o"2020Y2M9D",
               ~o"2020Y2M10D",
               ~o"2020Y2M11D",
               ~o"2020Y2M12D",
               ~o"2020Y2M13D",
               ~o"2020Y2M14D",
               ~o"2020Y2M15D",
               ~o"2020Y2M16D",
               ~o"2020Y2M17D",
               ~o"2020Y2M18D",
               ~o"2020Y2M19D",
               ~o"2020Y2M20D",
               ~o"2020Y2M21D",
               ~o"2020Y2M22D",
               ~o"2020Y2M23D",
               ~o"2020Y2M24D",
               ~o"2020Y2M25D",
               ~o"2020Y2M26D",
               ~o"2020Y2M27D",
               ~o"2020Y2M28D",
               ~o"2020Y2M29D"
             ]
  end

  test "when a set has a range followed by a range" do
    assert Enum.to_list(~o"{1..2,5..6}Y") == [~o"1Y", ~o"2Y", ~o"5Y", ~o"6Y"]
    assert Enum.to_list(~o"{1..2,4,6..7}Y") == [~o"1Y", ~o"2Y", ~o"4Y", ~o"6Y", ~o"7Y"]
  end

  test "Enumerating a set" do
    assert Enum.to_list(~o"{1970,1980,1990}") == [~o"1970", ~o"1980", ~o"1990"]
  end

  test "Enumeration in the negative direction" do
    assert Enum.to_list(~o"{5..1}M") == [~o"5M", ~o"4M", ~o"3M", ~o"2M", ~o"1M"]

    assert Enum.to_list(~o"{5..1}M{4..1}D") ==
             [
               ~o"5M4D",
               ~o"5M3D",
               ~o"5M2D",
               ~o"5M1D",
               ~o"4M4D",
               ~o"4M3D",
               ~o"4M2D",
               ~o"4M1D",
               ~o"3M4D",
               ~o"3M3D",
               ~o"3M2D",
               ~o"3M1D",
               ~o"2M4D",
               ~o"2M3D",
               ~o"2M2D",
               ~o"2M1D",
               ~o"1M4D",
               ~o"1M3D",
               ~o"1M2D",
               ~o"1M1D"
             ]

    assert Enum.to_list(~o"{5..1}M{1..4}D") ==
             [
               ~o"5M1D",
               ~o"5M2D",
               ~o"5M3D",
               ~o"5M4D",
               ~o"4M1D",
               ~o"4M2D",
               ~o"4M3D",
               ~o"4M4D",
               ~o"3M1D",
               ~o"3M2D",
               ~o"3M3D",
               ~o"3M4D",
               ~o"2M1D",
               ~o"2M2D",
               ~o"2M3D",
               ~o"2M4D",
               ~o"1M1D",
               ~o"1M2D",
               ~o"1M3D",
               ~o"1M4D"
             ]
  end

  test "Enumerating with a step != 1" do
    assert Enum.to_list(~o"2023Y{1..12//2}M") ==
             [~o"2023Y1M", ~o"2023Y3M", ~o"2023Y5M", ~o"2023Y7M", ~o"2023Y9M", ~o"2023Y11M"]
  end

  describe "Enumerable count/member?/slice (fast paths)" do
    # These delegate to the materialised interval's O(1) Steps-backed
    # implementations and must agree with the reduce-based walk.
    test "count matches the walk across resolutions" do
      assert Enum.count(~o"2022Y") == 12
      assert Enum.count(~o"2022-06") == 30
      assert Enum.count(~o"2022-06-15") == 24
      assert Enum.count(~o"2022-06-15T10") == 60

      for t <- [~o"2022Y", ~o"2022-06", ~o"2022-06-15", ~o"2022-06-15T10"] do
        assert Enum.count(t) == length(Enum.to_list(t))
      end
    end

    test "member? agrees with the walk" do
      year = ~o"2022Y"
      assert Enum.member?(year, ~o"2022Y6M")
      refute Enum.member?(year, ~o"2023Y6M")
      assert Enum.all?(Enum.to_list(year), &Enum.member?(year, &1))
    end

    test "slice (Enum.at / Enum.slice) agrees with the walk" do
      month = ~o"2022-06"
      list = Enum.to_list(month)
      assert Enum.at(month, 0) == Enum.at(list, 0)
      assert Enum.at(month, 14) == Enum.at(list, 14)
      assert Enum.slice(month, 5, 3) == Enum.slice(list, 5, 3)
    end

    test "group/range values fall back to the reduce walk" do
      # Multi-valued shapes don't materialise to a single interval;
      # Enum still works via the reduce-based traversal.
      assert Enum.count(~o"2022Y{1..3}M") == 3
    end
  end

  describe "Enumerable count/member?/slice under DST" do
    setup do
      Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
      :ok
    end

    test "spring-forward day counts 23 hours; skipped hour is not a member" do
      day = ~o"2022-03-13[America/New_York]"
      assert Enum.count(day) == 23
      assert Enum.count(day) == length(Enum.to_list(day))
      refute Enum.member?(day, ~o"2022-03-13T02[America/New_York]")
    end

    test "fall-back day counts 25 hours and count matches the walk" do
      day = ~o"2022-11-06[America/New_York]"
      assert Enum.count(day) == 25
      assert Enum.count(day) == length(Enum.to_list(day))
      assert Enum.all?(Enum.to_list(day), &Enum.member?(day, &1))
    end

    test "the materialised interval's walk is DST-aware and agrees with its count" do
      for {str, hours} <- [{"2022-03-13", 23}, {"2022-11-06", 25}, {"2022-06-15", 24}] do
        {:ok, day} = Tempo.from_iso8601(str <> "[America/New_York]")
        {:ok, interval} = Tempo.to_interval(day)
        assert Enum.count(interval) == hours
        assert length(Enum.to_list(interval)) == hours
      end
    end

    test "fall-back hour is emitted twice with its two offsets" do
      {:ok, interval} = Tempo.to_interval(~o"2022-11-06[America/New_York]")

      shifts =
        interval |> Enum.to_list() |> Enum.filter(&(&1.time[:hour] == 1)) |> Enum.map(& &1.shift)

      assert shifts == [[hour: -4], [hour: -5]]
    end

    test "the slice fast path matches the walk across a DST transition" do
      for str <- ["2022-03-13", "2022-11-06", "2022-06-15"] do
        {:ok, day} = Tempo.from_iso8601(str <> "[America/New_York]")
        {:ok, interval} = Tempo.to_interval(day)
        walk = Enum.to_list(interval)
        # Enum.at / Enum.slice use the Steps slice path; must match.
        assert Enum.map(0..(length(walk) - 1), &Enum.at(interval, &1)) == walk
        assert Enum.slice(interval, 1, 3) == Enum.slice(walk, 1, 3)
      end
    end

    test "slice disambiguates the folded hour by offset" do
      {:ok, day} = Tempo.from_iso8601("2022-11-06[America/New_York]")
      {:ok, interval} = Tempo.to_interval(day)
      # Steps step 1 and 2 are both 01:00, with the EDT then EST offset.
      assert Enum.at(interval, 1).shift == [hour: -4]
      assert Enum.at(interval, 2).shift == [hour: -5]
    end
  end

  describe "enumeration honours the value's calendar" do
    # The implicit `1..-1` range must resolve against the value's own
    # calendar, not default to Gregorian. Both the reduce walk and the
    # count fast path must agree, and agree with the calendar.
    test "13-month calendars enumerate 13 months" do
      for {cal, year, months} <- [
            {Calendrical.Coptic, "1740", 13},
            {Calendrical.Ethiopic, "2015", 13},
            {Calendrical.Hebrew, "5784", 13},
            {Calendrical.Hebrew, "5783", 12}
          ] do
        {:ok, y} = Tempo.from_iso8601(year, cal)
        assert length(Enum.to_list(y)) == months
        assert Enum.count(y) == months
      end
    end

    test "a 30-day Coptic month enumerates 30 days, not 31" do
      {:ok, month} = Tempo.from_iso8601("1740-01", Calendrical.Coptic)
      days = Enum.map(Enum.to_list(month), & &1.time[:day])
      assert days == Enum.to_list(1..30)
      assert Enum.count(month) == 30
    end
  end

  describe "recurring intervals" do
    # A bounded recurring interval enumerates exactly as its
    # materialised occurrences do — the sub-points of every
    # occurrence, delegated to the IntervalSet walk. Unbounded and
    # unexpandable shapes are refused like the crisp API refuses
    # them (`relation/2`, `duration/1`).

    test "a bounded recurrence enumerates the sub-points of every occurrence" do
      {:ok, r5} = Tempo.from_iso8601("R5/2022-01-01/P1M")

      # Jan 31 + Feb 28 + Mar 31 + Apr 30 + May 31 days.
      assert Enum.count(r5) == 151
      assert Enum.at(r5, 0) == ~o"2022-01-01"
      assert Enum.at(r5, 150) == ~o"2022-05-31"
    end

    test "enumeration agrees with the materialised set" do
      {:ok, r5} = Tempo.from_iso8601("R5/2022-01-01/P1M")
      {:ok, set} = Tempo.to_interval(r5)

      assert Enum.count(r5) == Enum.count(set)
      assert Enum.take(r5, 5) == Enum.take(set, 5)
    end

    test "an unbounded recurrence raises with the :within direction" do
      {:ok, r} = Tempo.from_iso8601("R/2022-01-01/P1M")

      assert_raise Tempo.UnboundedRecurrenceError, ~r/:within/, fn ->
        Enum.take(r, 3)
      end
    end

    test "an Rn/from/to repetition walks its occurrences, not a single span" do
      {:ok, r3} = Tempo.from_iso8601("R3/2022-01-01/2022-01-08")
      {:ok, set} = Tempo.to_interval(r3)

      assert Enum.count(r3) == 21
      assert Enum.at(r3, 0) == ~o"2022-01-01"
      assert Enum.at(r3, 20) == ~o"2022-01-21"
      assert Enum.to_list(r3) == Enum.to_list(set)
    end

    test "a plain interval (recurrence 1) is unaffected" do
      {:ok, january} = Tempo.from_iso8601("2022-01-01/2022-02-01")
      assert Enum.count(january) == 31
    end
  end
end
