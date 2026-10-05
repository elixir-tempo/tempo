defmodule Tempo.Parser.DatesTimes.Test do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Tokenizer

  test "Date Parsing" do
    assert Tokenizer.tokenize("2018-08-01") ==
             {:ok, {[date: [year: 2018, month: 8, day: 1]], nil}}

    assert Tokenizer.tokenize("1985") == {:ok, {[date: [year: 1985]], nil}}
    assert Tokenizer.tokenize("12Y") == {:ok, {[date: [year: 12]], nil}}
    assert Tokenizer.tokenize("8M") == {:ok, {[date: [month: 8]], nil}}
    assert Tokenizer.tokenize("25D") == {:ok, {[date: [day: 25]], nil}}
    assert Tokenizer.tokenize("10W") == {:ok, {[date: [week: 10]], nil}}
    assert Tokenizer.tokenize("19850412") == {:ok, {[date: [year: 1985, month: 4, day: 12]], nil}}

    assert Tokenizer.tokenize("1985-04-12") ==
             {:ok, {[date: [year: 1985, month: 4, day: 12]], nil}}

    assert Tokenizer.tokenize("1985-04") == {:ok, {[date: [year: 1985, month: 4]], nil}}
    assert Tokenizer.tokenize("1985") == {:ok, {[date: [year: 1985]], nil}}
    assert Tokenizer.tokenize("1985102") == {:ok, {[date: [year: 1985, day_of_year: 102]], nil}}

    assert Tokenizer.tokenize("1985W155") ==
             {:ok, {[date: [year: 1985, week: 15, day_of_week: 5]], nil}}

    assert Tokenizer.tokenize("1985W15") == {:ok, {[date: [year: 1985, week: 15]], nil}}
    assert Tokenizer.tokenize("19") == {:ok, {[date: [century: 19]], nil}}
    assert Tokenizer.tokenize("198") == {:ok, {[date: [decade: 198]], nil}}

    assert Tokenizer.tokenize("1985-W15-1") ==
             {:ok, {[date: [year: 1985, week: 15, day_of_week: 1]], nil}}

    assert Tokenizer.tokenize("1985-W15") == {:ok, {[date: [year: 1985, week: 15]], nil}}
    assert Tokenizer.tokenize("1985-102") == {:ok, {[date: [year: 1985, day_of_year: 102]], nil}}
    assert Tokenizer.tokenize("W03") == {:ok, {[date: [week: 3]], nil}}
  end

  test "Additional Explicit Forms section 4.3" do
    assert Tokenizer.tokenize("01M") == {:ok, {[date: [month: 1]], nil}}
    assert Tokenizer.tokenize("0001M") == {:ok, {[date: [month: 1]], nil}}
    assert Tokenizer.tokenize("1K") == {:ok, {[date: [day_of_week: 1]], nil}}
    assert Tokenizer.tokenize("350O") == {:ok, {[date: [day_of_year: 350]], nil}}
    assert Tokenizer.tokenize("16C") == {:ok, {[date: [century: 16]], nil}}
    assert Tokenizer.tokenize("-1985Y") == {:ok, {[date: [year: -1985]], nil}}
    assert Tokenizer.tokenize("1YB") == {:ok, {[date: [year: 0]], nil}}
    assert Tokenizer.tokenize("12YB") == {:ok, {[date: [year: -11]], nil}}
    assert Tokenizer.tokenize("-5D") == {:ok, {[date: [day: -5]], nil}}
    assert Tokenizer.tokenize("-3W") == {:ok, {[date: [week: -3]], nil}}
    assert Tokenizer.tokenize("-7O") == {:ok, {[date: [day_of_year: -7]], nil}}
    assert Tokenizer.tokenize("-306O") == {:ok, {[date: [day_of_year: -306]], nil}}
    assert Tokenizer.tokenize("-1985") == {:ok, {[date: [year: -1985]], nil}}

    # A decade or a century before year one keeps its sign apart from its
    # number, so that `-00` is told from `00` (ISO 8601-2 §4.4.1.7, §4.4.1.8).
    assert Tokenizer.tokenize("-019") == {:ok, {[date: [decade: {:before_year_one, 19}]], nil}}
    assert Tokenizer.tokenize("-12J") == {:ok, {[date: [decade: {:before_year_one, 12}]], nil}}
    assert Tokenizer.tokenize("-19") == {:ok, {[date: [century: {:before_year_one, 19}]], nil}}
    assert Tokenizer.tokenize("-12C") == {:ok, {[date: [century: {:before_year_one, 12}]], nil}}
    assert Tokenizer.tokenize("-00") == {:ok, {[date: [century: {:before_year_one, 0}]], nil}}
    assert Tokenizer.tokenize("00") == {:ok, {[date: [century: 0]], nil}}
  end

  test "Exponential values section 4.4.2" do
    assert Tokenizer.tokenize("1230S2") ==
             {:ok, {[date: [year: {1230, significant_digits: 2}]], nil}}

    assert Tokenizer.tokenize("3E3Y") == {:ok, {[date: [year: 3000]], nil}}
  end

  test "Unspecified digits section 4.6.2" do
    assert Tokenizer.tokenize("1390YXXM") ==
             {:ok, {[date: [year: 1390, month: {:mask, [:X, :X]}]], nil}}

    assert Tokenizer.tokenize("13{00..90}YXXM") ==
             {:ok, {[date: [year: {:mask, [1, 3, [0..90]]}, month: {:mask, [:X, :X]}]], nil}}

    assert Tokenizer.tokenize("13X{0..9}YXXM") ==
             {:ok, {[date: [year: {:mask, [1, 3, :X, [0..9]]}, month: {:mask, [:X, :X]}]], nil}}
  end

  test "Time Without Zone Parsing" do
    assert Tokenizer.tokenize("T23:20:50") ==
             {:ok, {[time_of_day: [hour: 23, minute: 20, second: 50]], nil}}

    assert Tokenizer.tokenize("T23:20") == {:ok, {[time_of_day: [hour: 23, minute: 20]], nil}}
    assert Tokenizer.tokenize("T23") == {:ok, {[time_of_day: [hour: 23]], nil}}
    assert Tokenizer.tokenize("T23.3") == {:ok, {[time_of_day: [hour: 23.3]], nil}}

    assert Tokenizer.tokenize("T00:00:00") ==
             {:ok, {[time_of_day: [hour: 0, minute: 0, second: 0]], nil}}

    assert Tokenizer.tokenize("23:20") == {:ok, {[time_of_day: [hour: 23, minute: 20]], nil}}
    assert Tokenizer.tokenize("6H") == {:ok, {[time_of_day: [hour: 6]], nil}}

    assert Tokenizer.tokenize("T232050") ==
             {:ok, {[time_of_day: [hour: 23, minute: 20, second: 50]], nil}}

    assert Tokenizer.tokenize("T2320") == {:ok, {[time_of_day: [hour: 23, minute: 20]], nil}}
  end

  test "Time with fractions" do
    assert Tokenizer.tokenize("T232030,5") ==
             {:ok, {[time_of_day: [hour: 23, minute: 20, second: 30, fraction: {5, 1}]], nil}}

    assert Tokenizer.tokenize("T232030.5") ==
             {:ok, {[time_of_day: [hour: 23, minute: 20, second: 30, fraction: {5, 1}]], nil}}

    assert Tokenizer.tokenize("23:20:30.5") ==
             {:ok, {[time_of_day: [hour: 23, minute: 20, second: 30, fraction: {5, 1}]], nil}}

    assert Tokenizer.tokenize("T2320,8") == {:ok, {[time_of_day: [hour: 23, minute: 20.8]], nil}}
    assert Tokenizer.tokenize("T2320.8") == {:ok, {[time_of_day: [hour: 23, minute: 20.8]], nil}}

    assert Tokenizer.tokenize("T000000") ==
             {:ok, {[time_of_day: [hour: 0, minute: 0, second: 0]], nil}}
  end

  # This is not valid in ISO8601 but it makes quarter handling
  # easier to understand

  test "Quarters in the month position" do
    assert Tokenizer.tokenize("13X{0..9}Y1Q") ==
             {:ok, {[date: [year: {:mask, [1, 3, :X, [0..9]]}, month: 33]], nil}}
  end

  test "Time With Zone Parsing" do
    assert Tokenizer.tokenize("T23:20:30Z") ==
             {:ok,
              {[time_of_day: [hour: 23, minute: 20, second: 30, time_shift: [hour: 0]]], nil}}

    assert Tokenizer.tokenize("T232030Z") ==
             {:ok,
              {[
                 time_of_day: [
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("T152746+0100") ==
             {:ok,
              {[
                 time_of_day: [
                   hour: 15,
                   minute: 27,
                   second: 46,
                   time_shift: [hour: 1, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("T152746-0500") ==
             {:ok,
              {[
                 time_of_day: [
                   hour: 15,
                   minute: 27,
                   second: 46,
                   time_shift: [hour: -5, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("T152746-05") ==
             {:ok,
              {[
                 time_of_day: [
                   hour: 15,
                   minute: 27,
                   second: 46,
                   time_shift: [hour: -5]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("15:27:46+01:00") ==
             {:ok,
              {[
                 time_of_day: [
                   hour: 15,
                   minute: 27,
                   second: 46,
                   time_shift: [hour: 1, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("15:27:46+01") ==
             {:ok,
              {[
                 time_of_day: [
                   hour: 15,
                   minute: 27,
                   second: 46,
                   time_shift: [hour: 1]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("15:27:46-05") ==
             {:ok,
              {[
                 time_of_day: [
                   hour: 15,
                   minute: 27,
                   second: 46,
                   time_shift: [hour: -5]
                 ]
               ], nil}}
  end

  test "Date Time parsing" do
    assert Tokenizer.tokenize("19850412T232030") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   month: 4,
                   day: 12,
                   hour: 23,
                   minute: 20,
                   second: 30
                 ]
               ], nil}}

    assert Tokenizer.tokenize("19850412T232030Z") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   month: 4,
                   day: 12,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("19850412T232030+0400") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   month: 4,
                   day: 12,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 4, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-04-12T23:20:30") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   month: 4,
                   day: 12,
                   hour: 23,
                   minute: 20,
                   second: 30
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-04-12T23:20:30Z") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   month: 4,
                   day: 12,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-04-12T23:20:30+04:00") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   month: 4,
                   day: 12,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 4, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-04-12T23:20:30+04") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   month: 4,
                   day: 12,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 4]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985102T232030") ==
             {:ok,
              {[datetime: [year: 1985, day_of_year: 102, hour: 23, minute: 20, second: 30]], nil}}

    assert Tokenizer.tokenize("1985102T232030Z") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   day_of_year: 102,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-102T23:20:30+04:00") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   day_of_year: 102,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 4, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-102T23:20:30+04") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   day_of_year: 102,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 4]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985W155T232030") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 23,
                   minute: 20,
                   second: 30
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985W155T232030Z") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985W155T232030+0400") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 4, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-W15-5T23:20:30") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 23,
                   minute: 20,
                   second: 30
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-W15-5T23:20:30Z") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-W15-5T23:20:30+04:00") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 4, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-W15-5T23:20:30+04") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 23,
                   minute: 20,
                   second: 30,
                   time_shift: [hour: 4]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("19850412T1015") ==
             {:ok, {[datetime: [year: 1985, month: 4, day: 12, hour: 10, minute: 15]], nil}}

    assert Tokenizer.tokenize("1985-04-12T10:15") ==
             {:ok, {[datetime: [year: 1985, month: 4, day: 12, hour: 10, minute: 15]], nil}}

    assert Tokenizer.tokenize("1985102T1015Z") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   day_of_year: 102,
                   hour: 10,
                   minute: 15,
                   time_shift: [hour: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-102T10:15Z") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   day_of_year: 102,
                   hour: 10,
                   minute: 15,
                   time_shift: [hour: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985W155T1015+0400") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 10,
                   minute: 15,
                   time_shift: [hour: 4, minute: 0]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("1985-W15-5T10:15+04") ==
             {:ok,
              {[
                 datetime: [
                   year: 1985,
                   week: 15,
                   day_of_week: 5,
                   hour: 10,
                   minute: 15,
                   time_shift: [hour: 4]
                 ]
               ], nil}}
  end

  test "Date with timezone (but no time)" do
    assert Tokenizer.tokenize("2018Y3G60DU6DZ8H") ==
             {:ok,
              {[date: [year: 2018, group: [nth: 3, day: 60], day: 6, time_shift: [hour: 8]]], nil}}

    assert Tokenizer.tokenize("2018Y1G60DUZ-5H") ==
             {:ok, {[date: [year: 2018, group: [nth: 1, day: 60], time_shift: [hour: -5]]], nil}}
  end

  test "Date with margin of error" do
    assert Tokenizer.tokenize("-13.787E9±20E6Y") ==
             {:ok, {[date: [year: {-13_787_000_000, [margin_of_error: 20_000_000]}]], nil}}

    assert Tokenizer.tokenize("-13.787E9S4±20E6Y") ==
             {:ok,
              {[
                 date: [
                   year: {-13_787_000_000, [significant_digits: 4, margin_of_error: 20_000_000]}
                 ]
               ], nil}}
  end

  # A year written with a sign and five digits or more is an expanded year
  # (ISO 8601-1 §4.4), whatever follows it. These six asserted nothing: each
  # was `assert Tokenizer.tokenize(text)`, which a parse error passes too.
  test "an expanded year, written with a sign and five digits or more" do
    assert Tokenizer.tokenize("+0019850412") == {:ok, {[date: [year: 19_850_412]], nil}}

    assert Tokenizer.tokenize("+001985-04-12") ==
             {:ok, {[date: [year: 1985, month: 4, day: 12]], nil}}

    assert Tokenizer.tokenize("+001985-04") == {:ok, {[date: [year: 1985, month: 4]], nil}}
    assert Tokenizer.tokenize("+001985") == {:ok, {[date: [year: 1985]], nil}}
    assert Tokenizer.tokenize("+00198") == {:ok, {[date: [year: 198]], nil}}
  end

  test "a year of four digits with a plus sign is not an expanded year" do
    assert {:error, %Tempo.ParseError{}} = Tokenizer.tokenize("+0019")
  end
end
