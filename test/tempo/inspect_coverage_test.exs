defmodule Tempo.InspectCoverageTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  describe "masked years round-trip through inspect" do
    test "decade" do
      assert inspect(~o"201X") == ~s|~o"201XY"|
    end

    test "century" do
      assert inspect(~o"20XX") == ~s|~o"20XXY"|
    end

    test "all 4-digit years" do
      assert inspect(~o"XXXX") == ~s|~o"XXXXY"|
    end
  end

  describe "open-ended intervals" do
    test "open upper bound" do
      assert inspect(~o"2020Y/..") == ~s|~o"2020Y/.."|
    end

    test "open lower bound" do
      assert inspect(~o"../2020Y") == ~s|~o"../2020Y"|
    end
  end

  describe "durations and closed intervals" do
    test "a duration" do
      assert inspect(~o"P1Y2M3D") == ~s|~o"P1Y2M3D"|
    end

    test "a closed interval" do
      assert inspect(~o"2020Y/2021Y") == ~s|~o"2020Y/2021Y"|
    end

    test "a recurrence" do
      assert inspect(Tempo.from_iso8601!("R3/2020-01-01/P1D")) == ~s|~o"R3/2020Y1M1D/P1D"|
    end
  end

  describe "interval metadata tags" do
    defp meta(metadata) do
      inspect(%Tempo.Interval{from: ~o"2020Y", to: ~o"2021Y", metadata: metadata})
    end

    test "a summary with a location" do
      assert meta(%{summary: "Trip", location: "Paris"}) =~ "Trip @ Paris"
    end

    test "a summary alone" do
      tag = meta(%{summary: "Trip"})
      assert tag =~ "Trip"
      refute tag =~ "@"
    end

    test "a uid" do
      assert meta(%{uid: "evt-1"}) =~ "uid=evt-1"
    end

    test "other metadata falls back to a key count" do
      assert meta(%{foo: 1, bar: 2}) =~ "2 metadata key(s)"
    end
  end

  describe "grouped values, qualifiers, shifts and alternate calendars" do
    test "a range inside a group" do
      assert inspect(~o"{1..5}M") == ~s|~o"{1..5}M"|
    end

    test "an ordinal-day set" do
      assert inspect(Tempo.from_iso8601!("2020Y{100,200}O")) == ~s|~o"2020Y{100,200}O"|
    end

    test "a qualified second" do
      assert inspect(Tempo.from_iso8601!("2020Y1M1DT10H30S~")) == ~s|~o"2020Y1M1DT10H0M30S~"|
    end

    test "a UTC offset shift" do
      assert inspect(Tempo.from_iso8601!("2020-06-15T10:00:00+05:00")) =~ "Z+5H"
    end

    test "a fractional second" do
      assert inspect(~o"2020Y1M1DT10H30,5S") == ~s|~o"2020Y1M1DT10H0M30.5S"|
    end

    test "a non-ISO calendar value names its calendar" do
      assert inspect(Tempo.from_iso8601!("2020-06-15[u-ca=coptic]")) =~ "coptic"
    end
  end

  describe "group unit designators round-trip" do
    for {label, string} <- [
          {"day-of-week (K)", "{1,3,5}K"},
          {"week (W)", "{1..10}W"},
          {"second (S)", "T{30,45}S"},
          {"minute (M)", "T{15,30}M"},
          {"hour (H)", "2020Y1M1DT{10,12}H"}
        ] do
      test "#{label}" do
        string = unquote(string)
        assert inspect(Tempo.from_iso8601!(string)) == ~s|~o"#{string}"|
      end
    end
  end

  describe "UTC offset shifts" do
    test "negative offset" do
      assert inspect(Tempo.from_iso8601!("2020-06-15T10:00:00-05:00")) =~ "Z-5H"
    end

    test "offset with minutes" do
      assert inspect(Tempo.from_iso8601!("2020-06-15T10:00:00+05:30")) =~ "Z+5H30M"
    end

    test "zero offset" do
      assert inspect(Tempo.from_iso8601!("2020-06-15T10:00:00+00:00")) =~ "Z0H"
    end
  end

  # Component-level rendering reached when a unit holds a plain list
  # (the `unit_designator/1` table) or a number with EDTF precision
  # metadata. Built directly since the parser normalises most of
  # these away before they reach inspect.
  describe "component value rendering" do
    @cal Calendrical.Gregorian
    defp t(time), do: inspect(%Tempo{time: time, calendar: @cal})

    test "unit designators for each time unit" do
      assert t(year: 2020, day_of_year: [100, 200]) == ~s|~o"2020Y{100,200}O"|
      assert t(hour: [10, 12]) == ~s|~o"T{10,12}H"|
      assert t(minute: [15, 30]) == ~s|~o"T{15,30}M"|
      assert t(second: [30, 45]) == ~s|~o"T{30,45}S"|
      assert t(day_of_week: [1, 3]) == ~s|~o"{1,3}K"|
      assert t(week: [10, 20]) == ~s|~o"{10,20}W"|
    end

    test "significant digits and margin of error" do
      assert t(year: {2020, [significant_digits: 3]}) == ~s|~o"2020S3Y"|
      assert t(year: {2020, [margin_of_error: 5]}) =~ "±5"
      assert t(year: {2020, [significant_digits: 3, margin_of_error: 5]}) =~ "S3±5"
    end

    test "a range value" do
      assert t(year: 1..5) == ~s|~o"1..5Y"|
      assert t(year: %Tempo.Range{first: ~o"2020Y", last: :undefined}) == ~s|~o"2020Y..Y"|
      assert t(year: %Tempo.Range{first: :undefined, last: ~o"2020Y"}) =~ ".."
    end

    test "a wrapped recurrence interval with a repeat rule" do
      rule = %Tempo{time: [selection: [day: [1]]], calendar: @cal}
      rr = %Tempo.Interval{recurrence: 3, from: ~o"2020Y", to: ~o"2021Y", repeat_rule: rule}
      assert t(interval: rr) =~ "R3/"
    end

    test "a wrapped duration" do
      assert t(duration: ~o"P1Y") == ~s|~o"P1Y"|
    end

    test "qualified list values render the unit designator" do
      q = fn unit -> inspect(%Tempo{time: [{unit, {:q, [1, 2], :uncertain}}], calendar: @cal}) end
      assert q.(:hour) == ~s|~o"T{1,2}?H"|
      assert q.(:minute) == ~s|~o"T{1,2}?M"|
      assert q.(:second) == ~s|~o"T{1,2}?S"|
      assert q.(:day_of_week) == ~s|~o"{1,2}?K"|
      assert q.(:week) == ~s|~o"{1,2}?W"|
      assert q.(:day_of_year) == ~s|~o"{1,2}?O"|
    end

    test "wrapped recurrence interval shapes" do
      assert t(
               interval: %Tempo.Interval{
                 recurrence: 1,
                 from: ~o"2020Y",
                 to: nil,
                 duration: ~o"P1D"
               }
             ) =~
               "P1D"

      assert t(
               interval: %Tempo.Interval{
                 recurrence: 3,
                 from: ~o"2020Y",
                 to: :undefined,
                 duration: nil
               }
             ) =~
               "R3/"

      assert t(
               interval: %Tempo.Interval{
                 recurrence: 3,
                 from: :undefined,
                 to: ~o"2021Y",
                 duration: nil
               }
             ) =~
               "R3/"

      assert t(
               interval: %Tempo.Interval{
                 recurrence: 3,
                 from: ~o"2020Y",
                 to: ~o"2021Y",
                 duration: nil
               }
             ) =~
               "R3/"
    end

    test "a custom IXDTF tag" do
      assert inspect(Tempo.from_iso8601!("2020-06-15[foo=bar]")) =~ "[foo=bar]"
    end
  end
end
