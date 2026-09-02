defmodule Tempo.Iso8601.Parser.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Iso8601.AST

  test "Parsing centuries and decades resolves to a year group" do
    # The tokenizer emits group/range values as the component value;
    # these shapes go through the internal AST builder, not the
    # public `Tempo.new/1` (which validates for integer components).
    assert Tempo.from_iso8601("20C") ==
             {:ok, AST.build(year: {:group, 2000..2099})}

    assert Tempo.from_iso8601("200J") ==
             {:ok, AST.build(year: {:group, 2000..2009})}

    assert Tempo.from_iso8601("199J") ==
             {:ok, AST.build(year: {:group, 1990..1999})}

    assert Tempo.from_iso8601("{1990..1999}Y") ==
             {:ok, AST.build(year: [1990..1999])}
  end

  describe "ISO 8601-2 expanded year (±YYYYY)" do
    test "a signed year of five or more digits parses" do
      assert Tempo.from_iso8601("+12022") == {:ok, ~o"12022Y"}
      assert Tempo.from_iso8601("-12022") == {:ok, ~o"-12022Y"}
      # Leading zeros (the agreed expansion width) normalise to the value.
      assert Tempo.from_iso8601("+002022") == {:ok, ~o"2022Y"}
    end

    test "an expanded year carries a full date" do
      assert Tempo.from_iso8601("+12022-06-15") == {:ok, ~o"12022Y6M15D"}
    end

    test "a signed four-digit value is not expanded form and is rejected" do
      # The expanded form requires at least one digit beyond the basic
      # four; `+2006` is neither basic nor expanded (matches EDTF).
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("+2006")
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("+2022")
    end

    test "unsigned and basic-format parsing is unaffected" do
      assert Tempo.from_iso8601("2022") == {:ok, ~o"2022Y"}
      assert Tempo.from_iso8601("20220615") == {:ok, ~o"2022Y6M15D"}
      # A bare negative four-digit year still works.
      assert Tempo.from_iso8601("-0333") == {:ok, ~o"-333Y"}
    end
  end

  describe "selection adjacent to a group" do
    alias Tempo.Iso8601.Parser

    # Regression: a selection next to a group used to reach the
    # generic unit/group clauses, which passed the `:selection` /
    # `:group` tag to `Unit.compare/2` and raised `KeyError`. The
    # dedicated clauses now validate ordering from each wrapper's own
    # units, so the result is a clean parse or a clean `ParseError` —
    # never a crash.
    test "well-ordered selection/group pairs parse without crashing" do
      assert is_list(Parser.parse_date([{:selection, [month: [1, 3]]}, {:group, [day: 1]}]))
      assert is_list(Parser.parse_date([{:group, [month: 1]}, {:selection, [day: [1, 2]]}]))
    end

    test "a mis-ordered selection/group pair raises a clean ParseError, not KeyError" do
      assert_raise Tempo.ParseError, fn ->
        Parser.parse_date([{:selection, [day: [1, 3]]}, {:group, [month: 1]}])
      end
    end
  end

  test "Section 5: groups" do
    # 5.3 Example 1
    assert Tempo.from_iso8601("5G10DU") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [day: {:group, 41..50}]}}

    # 5.3 Example 2
    assert Tempo.from_iso8601("20GT30MU") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [minute: {:group, 571..600}]}}

    # 5.4.1 Example 1
    assert Tempo.from_iso8601("2018Y4G60DU6D") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: 2018, month: 7, day: 5]}}

    # 5.4.1 Example 3
    assert Tempo.from_iso8601("2018Y9M2DT3GT8HU30M")

    {:ok,
     %Tempo{
       calendar: Calendrical.Gregorian,
       time: [year: 2018, month: 9, day: 2, hour: 16, minute: 30]
     }}

    # 5.4.1 Example 4
    assert Tempo.from_iso8601("2018Y2M2G14DU") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 2, day: {:group, 15..28}]
              }}

    # 5.4.1 Example 5
    assert Tempo.from_iso8601("T16H1GT15MU") ==
             {:ok,
              %Tempo{calendar: Calendrical.Gregorian, time: [hour: 16, minute: {:group, 1..15}]}}

    # 5.4.1 Example 6
    assert Tempo.from_iso8601("2018Y1G6MU") ==
             {:ok,
              %Tempo{calendar: Calendrical.Gregorian, time: [year: 2018, month: {:group, 1..6}]}}

    # 5.4.2 Example 2
    assert Tempo.from_iso8601("10C5G20YU") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: [1080..1099]]}}

    # 5.4.2 Example 3
    assert Tempo.from_iso8601("1933Y1G80DU") ==
             {:ok,
              %Tempo{calendar: Calendrical.Gregorian, time: [year: 1933, day: {:group, 1..80}]}}

    # 5.4.2 Example 4
    assert Tempo.from_iso8601("1543Y1M3G5DU") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 1543, month: 1, day: {:group, 11..15}]
              }}

    # 5.4.2 Example 5
    assert Tempo.from_iso8601("110Y2G3MU") ==
             {:ok,
              %Tempo{calendar: Calendrical.Gregorian, time: [year: 110, month: {:group, 4..6}]}}

    # 5.4.2 Example 6
    assert Tempo.from_iso8601("6GT2HU") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [hour: {:group, 11..12}]}}

    # 5.4.2 Example 7
    assert Tempo.from_iso8601("2018Y2G3MU50D") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: 2018, month: 5, day: 20]}}

    # 5.4.2 Example 8
    assert Tempo.from_iso8601("201J2G5YU3DT10H0S") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: [2015..2019], day: 3, hour: 10, minute: 0, second: 0]
              }}

    # 5.4.2 Example 9
    assert Tempo.from_iso8601("2018Y3G60DU6D") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: 2018, month: 5, day: 6]}}

    # 5.4.2 Example 10
    assert Tempo.from_iso8601("2018Y20GT12HU3H") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 1, day: 10, hour: 15]
              }}

    # 5.4.3 Example 1
    assert Tempo.from_iso8601("2018Y1G2MU30D") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: 2018, month: 1, day: 30]}}

    # 5.4.3 Example 2
    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("2018Y1G2MU60D")
    assert Exception.message(e) =~ "60 is not valid"

    # 5.4.4 Example 1
    assert Tempo.from_iso8601("2018Y3G60DU6DZ-5H") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 5, day: 6],
                shift: [hour: -5]
              }}

    # 5.4.4 Example 2
    assert Tempo.from_iso8601("2018Y3G60DU6DZ8H") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 5, day: 6],
                shift: [hour: 8]
              }}

    # 5.4.5.2 Example
    assert Tempo.from_iso8601("2018Y9M4G8DU") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 9, day: {:group, 25..30}]
              }}
  end

  test "todo tests" do
    # 5.3 Example 3
    assert {:error, %Tempo.ParseError{} = e} = Tempo.from_iso8601("2G2DT6HU")
    assert Exception.message(e) =~ "Complex groupings not yet supported"
  end

  test "Section 6 Sets" do
    # Section 6.1 Example 1
    assert Tempo.from_iso8601("{1960,1961,1962,1963}") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: [1960..1963]]}}

    # Section 6.1 Example 2
    assert Tempo.from_iso8601("{1960,1961-12}") ==
             {:ok, %Tempo.Set{set: [~o"1960Y", ~o"1961Y12M"], type: :all}}

    # Section 6.2 Example 1
    assert Tempo.from_iso8601("[1984,1986,1988]") ==
             {:ok, %Tempo.Set{set: [~o"1984Y", ~o"1986Y", ~o"1988Y"], type: :one}}

    # Section 6.2 Example 2
    assert Tempo.from_iso8601("[1667,1760-12]") ==
             {:ok, %Tempo.Set{set: [~o"1667Y", ~o"1760Y12M"], type: :one}}

    # Section 6.4 Example 1
    assert Tempo.from_iso8601("{1667,1668,1670..1672}") ==
             {:ok, ~o"{1667..1668,1670..1672}Y"}

    # Section 6.4 Example 2
    assert Tempo.from_iso8601("[1760-01,1760-02,1760-12..]") ==
             {:ok,
              %Tempo.Set{
                set: [
                  ~o"1760Y1M",
                  ~o"1760Y2M",
                  %Tempo.Range{first: ~o"1760Y12M", last: :undefined}
                ],
                type: :one
              }}

    assert Tempo.from_iso8601("[1760-01,1760-02,..1760-12]") ==
             {:ok, ~o"[1760Y1M,1760Y2M,..1760Y12M]"}

    assert Tempo.from_iso8601("[1760-01,1760-02,1760-10..1760-12]") ==
             {:ok, ~o"[1760Y1M,1760Y2M,1760Y10M..1760Y12M]"}

    # Section 6.4 Example 3
    assert Tempo.from_iso8601("{1M2S..1M5S}") ==
             {:ok, %Tempo.Set{set: [%Tempo.Range{first: ~o"T1M2S", last: ~o"T1M5S"}], type: :all}}

    # Section 6.4 Example 4
    assert Tempo.from_iso8601("[1M2S,1M3S]") ==
             {:ok, %Tempo.Set{set: [~o"T1M2S", ~o"T1M3S"], type: :one}}

    # Section 6.6 Example 3
    assert Tempo.from_iso8601("2018-{1,3,5}G2MU") ==
             {
               :ok,
               %Tempo{
                 calendar: Calendrical.Gregorian,
                 shift: nil,
                 time: [{:year, 2018}, {:month, {:group, {:all, [1, 3, 5]}}, 2}]
               }
             }
  end

  test "Section 7 Dates" do
    # Section 7.2.3 Example 1
    assert Tempo.from_iso8601("1985Y102O") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: 1985, month: 4, day: 12]}}

    # Section 7.2.4 Example 1 with month based calendar
    assert Tempo.from_iso8601("1985Y15W7K") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: 1985, month: 4, day: 14]}}

    # Section 7.2.4 Example 1 with week based calendar
    assert Tempo.from_iso8601("1985Y15W7K", Calendrical.ISOWeek) ==
             {:ok, %Tempo{calendar: Calendrical.ISOWeek, time: [year: 1985, week: 15, day: 7]}}
  end

  test "Section 7.3 Time" do
    # Section 7.3.1 Example 1
    assert Tempo.from_iso8601("T23H20M50S") ==
             {:ok,
              %Tempo{calendar: Calendrical.Gregorian, time: [hour: 23, minute: 20, second: 50]}}

    # Section 7.3.1 Example 2
    assert Tempo.from_iso8601("T23H20M") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [hour: 23, minute: 20]}}

    # Section 7.3.2
    assert Tempo.from_iso8601("T0H0M0S") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [hour: 0, minute: 0, second: 0]}}

    # Section 7.4 Example 1
    assert Tempo.from_iso8601("Z-5H") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [], shift: [hour: -5]}}

    # Section 7.4 Example 2
    assert Tempo.from_iso8601("Z8H") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [], shift: [hour: 8]}}

    # Section 7.4 Example 3 — ISO 8601 shows `Z28H` as a syntactic
    # example, but a 28-hour UTC offset is not a real time zone.
    # Tempo rejects offsets outside ±24h at validation; the
    # tokenizer still accepts the grammar.
    assert {:error, message} = Tempo.from_iso8601("Z28H")
    assert Exception.message(message) =~ "out of range"

    # Section 7.4 Example 4
    assert Tempo.from_iso8601("Z6H0M") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [], shift: [hour: 6, minute: 0]}}

    # Section 7.4 Example 5
    assert Tempo.from_iso8601("Z7H33M14S") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [],
                shift: [hour: 7, minute: 33, second: 14]
              }}

    # Section 7.4 Example 6
    assert Tempo.from_iso8601("Z") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [], shift: [hour: 0]}}

    # Section 7.4 Example 7
    assert Tempo.from_iso8601("Z0H0M") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [], shift: [hour: 0, minute: 0]}}

    # Section 7.4 Example 8
    assert Tempo.from_iso8601("Z0S")
    {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [], shift: [second: 0]}}
  end

  test "Section 7.5 Date Shift" do
    # Section 7.5 Example 1
    assert Tempo.from_iso8601("1985Y4M12DZ-5H") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 1985, month: 4, day: 12],
                shift: [hour: -5]
              }}

    # Section 7.5 Example 2
    assert Tempo.from_iso8601("2018Y9M12DZ8H") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 9, day: 12],
                shift: [hour: 8]
              }}
  end

  test "Section 7.6 Time with Time Shift" do
    # Section 7.6 Example 1
    assert Tempo.from_iso8601("T23H20M50SZ")

    {:ok,
     %Tempo{
       calendar: Calendrical.Gregorian,
       time: [hour: 23, minute: 20, second: 50],
       shift: [hour: 0]
     }}

    # Section 7.6 Example 2
    assert Tempo.from_iso8601("T23H20M50SZ-5H0M") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [hour: 23, minute: 20, second: 50],
                shift: [hour: -5, minute: 0]
              }}

    # Section 7.6 Example 3
    assert Tempo.from_iso8601("T23H20M50SZ8H") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [hour: 23, minute: 20, second: 50],
                shift: [hour: 8]
              }}
  end

  test "Section 7.7 Date and Time of Day" do
    # Section 7.7.2 Example 1
    assert Tempo.from_iso8601("1985Y4M12DT23H20M30S")

    {:ok,
     %Tempo{
       calendar: Calendrical.Gregorian,
       time: [year: 1985, month: 4, day: 12, hour: 23, minute: 20, second: 30]
     }}

    # Section 7.7.3 Example 1
    assert Tempo.from_iso8601("1985Y4M12DT23H20M30SZ8H")

    {:ok,
     %Tempo{
       calendar: Calendrical.Gregorian,
       time: [
         year: 1985,
         month: 4,
         day: 12,
         hour: 23,
         minute: 20,
         second: 30
       ],
       shift: [hour: 8]
     }}
  end

  test "Section 7.8 Decades" do
    # Section 7.8 Example 1
    assert Tempo.from_iso8601("188J") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: {:group, 1880..1889}]}}

    # Section 7.8 Example 2
    assert Tempo.from_iso8601("18J") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: {:group, 180..189}]}}
  end

  test "Section 7.9 Centuries" do
    # Section 7.9 Example 1
    assert Tempo.from_iso8601("13C") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: {:group, 1300..1399}]}}

    # Section 7.9 Example 2
    assert Tempo.from_iso8601("3C") ==
             {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [year: {:group, 300..399}]}}
  end

  test "Section 7.12 Fractions for time" do
    # Section 7.12 Example 1
    assert Tempo.from_iso8601("2018Y8M8DT0,5H") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 8, day: 8, hour: 0, minute: 30]
              }}

    # Section 7.12 Example 2
    assert Tempo.from_iso8601("2018Y8M8DT10H30.5M") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [year: 2018, month: 8, day: 8, hour: 10, minute: 30, second: 30]
              }}

    # Section 7.12 Example 3 — a fractional second is preserved as a
    # `:microsecond {value, precision}` component (Elixir-aligned),
    # not folded into a float, so the digit count (resolution) survives.
    assert Tempo.from_iso8601("2018Y8M8DT10H30M15,3S") ==
             {:ok,
              %Tempo{
                calendar: Calendrical.Gregorian,
                time: [
                  year: 2018,
                  month: 8,
                  day: 8,
                  hour: 10,
                  minute: 30,
                  second: 15,
                  microsecond: {300_000, 1}
                ]
              }}
  end

  test "The universe - big bang to big crunch" do
    assert Tempo.from_iso8601("R/-13.787E9±20E6Y/..") ==
             {:ok,
              %Tempo.Interval{
                recurrence: :infinity,
                from: %Tempo{
                  calendar: Calendrical.Gregorian,
                  time: [year: {-13_787_000_000, [margin_of_error: 20_000_000]}]
                },
                to: :undefined,
                duration: nil
              }}
  end

  test "Fractional units can only be the last unit" do
    assert {:error, %Tempo.ParseError{} = e} = Tempo.from_iso8601("1985Y2.5M1D")
    assert Exception.message(e) =~ "fractional unit can only be used"

    assert Tempo.from_iso8601("1985Y1M5.5D") ==
             {:ok,
              %Tempo{
                time: [year: 1985, month: 1, day: 5, hour: 12],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("1985Y1M5.6D") ==
             {:ok,
              %Tempo{
                time: [year: 1985, month: 1, day: 5, hour: 14, minute: 24],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("1985.5Y") ==
             {:ok,
              %Tempo{
                time: [year: 1985, month: 7, day: 1, hour: 12],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("1985Y2.5M") ==
             {:ok,
              %Tempo{
                time: [year: 1985, month: 2, day: 14],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}
  end

  test "Negative seconds, minutes, hours, days and months" do
    import Tempo.Sigils

    assert ~o"1985Y-10M" ==
             %Tempo{
               time: [year: 1985, month: 3],
               shift: nil,
               calendar: Calendrical.Gregorian
             }

    assert ~o"1985Y-11M-1D" ==
             %Tempo{
               time: [year: 1985, month: 2, day: 28],
               shift: nil,
               calendar: Calendrical.Gregorian
             }

    assert ~o"2000Y-11M-1D" ==
             %Tempo{
               time: [year: 2000, month: 2, day: 29],
               shift: nil,
               calendar: Calendrical.Gregorian
             }

    assert Tempo.from_iso8601("T-1H") ==
             {:ok, %Tempo{time: [hour: 23], shift: nil, calendar: Calendrical.Gregorian}}

    assert Tempo.from_iso8601("T-1M") ==
             {:ok, %Tempo{time: [minute: 59], shift: nil, calendar: Calendrical.Gregorian}}

    assert Tempo.from_iso8601("T-1S") ==
             {:ok, %Tempo{time: [second: 59], shift: nil, calendar: Calendrical.Gregorian}}

    assert Tempo.from_iso8601("T-24H") ==
             {:ok, %Tempo{time: [hour: 0], shift: nil, calendar: Calendrical.Gregorian}}

    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("T-25H")
    assert Exception.message(e) =~ "-25 is not valid"

    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("2022Y-13M31D")
    assert Exception.message(e) =~ "-13 is not valid"

    assert {:error, %Tempo.InvalidDateError{} = e} = Tempo.from_iso8601("2022Y-13M")
    assert Exception.message(e) =~ "-13 is not valid"
  end

  test "Day of week adheres to calendar limit" do
    # ISO 8601: week 01 of 2022 contains the first Thursday of 2022
    # (Jan 6), so it starts Monday Jan 3. Day-of-week -7 is the
    # first day of the week (Monday) = Jan 3. Day-of-week 7 is the
    # last day (Sunday) = Jan 9.
    assert Tempo.from_iso8601("2022Y1W-7K") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: 1, day: 3],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y1W7K") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: 1, day: 9],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y1W7K", Calendrical.ISOWeek) ==
             {:ok,
              %Tempo{
                time: [year: 2022, week: 1, day: 7],
                shift: nil,
                calendar: Calendrical.ISOWeek
              }}

    assert {:error, %Tempo.InvalidDateError{} = e} =
             Tempo.from_iso8601("2022Y1W8K", Calendrical.ISOWeek)

    assert Exception.message(e) =~ "8 is not valid"
  end

  test "Quarters, Quadrimesters and Semestrals" do
    assert Tempo.from_iso8601("2022Y1Q") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 1..3}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y2Q") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 4..6}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y3Q") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 7..9}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y4Q") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 10..12}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y37M") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 1..4}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y38M") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 5..8}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y39M") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 9..12}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y1H") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 1..6}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y2H") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 7..12}],
                shift: nil,
                calendar: Calendrical.Gregorian
              }}
  end

  test "Selections" do
    assert Tempo.from_iso8601("2018YL1M2DNT2H") == {:ok, ~o"2018YL1M2DNT2H"}

    assert Tempo.from_iso8601("{2018,2019,2020,2021,2022}YL2M29D1IN") ==
             {:ok, ~o"{2018..2022}YL2M29D1IN"}
  end

  test "Groups" do
    assert Tempo.from_iso8601("{2018,2019,2020,2021,2022}Y1G20DU") ==
             {:ok, ~o"{2018..2022}Y1G20DU"}
  end

  test "Integer sets with negative bounds" do
    # An hour's extent is fixed, so a count-from-the-end bound resolves
    # at parse just as the scalar form does (`T-1M` is minute 59) —
    # `{-4..-1}H` is the last four hours of the day.
    assert Tempo.from_iso8601("T{-4..-1}H") ==
             {:ok, %Tempo{time: [hour: [20..23]], shift: nil, calendar: Calendrical.Gregorian}}
  end

  test "Ranges must have the same time unit keys" do
    assert {:error, %Tempo.ParseError{} = e} = Tempo.from_iso8601("[1760-12..1760]")
    assert Exception.message(e) =~ "Time ranges must have the same time units"
  end
end
