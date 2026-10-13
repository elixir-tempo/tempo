defmodule Tempo.Parser.Group.Test do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Tokenizer

  test "Group formation section 5" do
    assert Tokenizer.tokenize("2018-2G3MU") ==
             {:ok, {[date: [year: 2018, group: [nth: 2, month: 3]]], nil}}

    assert Tokenizer.tokenize("2018-02-2G14DU") ==
             {:ok, {[date: [year: 2018, month: 2, group: [nth: 2, day: 14]]], nil}}

    assert Tokenizer.tokenize("2018-03-3G10DU") ==
             {:ok, {[date: [year: 2018, month: 3, group: [nth: 3, day: 10]]], nil}}

    assert Tokenizer.tokenize("16:1GT15MU") ==
             {:ok, {[time_of_day: [hour: 16, group: [nth: 1, minute: 15]]], nil}}

    assert Tokenizer.tokenize("2018-1G6MU") ==
             {:ok, {[date: [year: 2018, group: [nth: 1, month: 6]]], nil}}

    assert Tokenizer.tokenize("2018Y1G6MU") ==
             {:ok, {[date: [year: 2018, group: [nth: 1, month: 6]]], nil}}

    assert Tokenizer.tokenize("1933Y1G80DU") ==
             {:ok, {[date: [year: 1933, group: [nth: 1, day: 80]]], nil}}

    assert Tokenizer.tokenize("1543Y1M3G5DU") ==
             {:ok, {[date: [year: 1543, month: 1, group: [nth: 3, day: 5]]], nil}}

    assert Tokenizer.tokenize("6GT2HU") ==
             {:ok, {[date: [group: [nth: 6, hour: 2]]], nil}}

    assert Tokenizer.tokenize("110Y2G3MU") ==
             {:ok, {[date: [year: 110, group: [nth: 2, month: 3]]], nil}}

    assert Tokenizer.tokenize("2018Y3G60DU6D") ==
             {:ok, {[date: [year: 2018, group: [nth: 3, day: 60], day: 6]], nil}}

    assert Tokenizer.tokenize("2018Y20GT12HU3H") ==
             {:ok, {[datetime: [year: 2018, group: [nth: 20, hour: 12], hour: 3]], nil}}

    assert Tokenizer.tokenize("2018Y1G2MU30D") ==
             {:ok, {[date: [year: 2018, group: [nth: 1, month: 2], day: 30]], nil}}

    assert Tokenizer.tokenize("2018Y1G2MU60D") ==
             {:ok, {[date: [year: 2018, group: [nth: 1, month: 2], day: 60]], nil}}

    assert Tokenizer.tokenize("2018Y9M4G8DU") ==
             {:ok, {[date: [year: 2018, month: 9, group: [nth: 4, day: 8]]], nil}}

    assert Tokenizer.tokenize("2018Y9M4G8DU") ==
             {:ok, {[date: [year: 2018, month: 9, group: [nth: 4, day: 8]]], nil}}
  end

  test "Group formation special tests" do
    assert Tokenizer.tokenize("5G10DU") ==
             {:ok, {[date: [group: [nth: 5, day: 10]]], nil}}

    assert Tokenizer.tokenize("1G2DT6HU") ==
             {:ok, {[date: [group: [nth: 1, day: 2, hour: 6]]], nil}}

    assert Tokenizer.tokenize("2018Y4G60DU6D") ==
             {:ok, {[date: [year: 2018, group: [{:nth, 4}, {:day, 60}], day: 6]], nil}}

    # Note that in section 5.4 Example 2 it shows
    # 2018Y9M2DT3GT8HU0H30M (Note the added 0H). In this implementation
    # the `H` is optional but there may not be any numbers between the
    # group and the `H`.

    assert Tokenizer.tokenize("2018Y9M2DT3GT8HU30M") ==
             {:ok,
              {[
                 datetime: [
                   year: 2018,
                   month: 9,
                   day: 2,
                   group: [nth: 3, hour: 8],
                   minute: 30
                 ]
               ], nil}}
  end
end
