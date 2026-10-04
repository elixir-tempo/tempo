defmodule Tempo.Parser.Set.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Iso8601.Tokenizer

  test "Set expressions: all of" do
    assert Tokenizer.tokenize("{1960,1961,1962}") ==
             {:ok, {[date: [year: {:all_of, [1960, 1961, 1962]}]], nil}}

    assert Tokenizer.tokenize("{1960,1961-12}") ==
             {:ok, {[all_of: [date: [year: 1960], date: [year: 1961, month: 12]]], nil}}

    assert Tokenizer.tokenize("{1M2S}")
    {:ok, [all_of: [datetime: [month: 1, second: 2]]]}

    assert Tokenizer.tokenize("{T1M2S,T1M3S}") ==
             {:ok,
              {[
                 all_of: [
                   time_of_day: [minute: 1, second: 2],
                   time_of_day: [minute: 1, second: 3]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("{PT1M2S..PT1M5S}")

    {:ok,
     [
       all_of: [
         [duration: [minute: 1, second: 2], duration: [minute: 1, second: 5]]
       ]
     ]}
  end

  test "Set expressions: one of" do
    assert Tokenizer.tokenize("[1984,1986,1988]") ==
             {:ok, {[one_of: [date: [year: 1984], date: [year: 1986], date: [year: 1988]]], nil}}

    assert Tokenizer.tokenize("[1667,1760-12]") ==
             {:ok, {[one_of: [date: [year: 1667], date: [year: 1760, month: 12]]], nil}}
  end

  test "Set expressions: range" do
    assert Tokenizer.tokenize("[1900..2000]") ==
             {:ok, {[one_of: [{:year, 1900..2000}]], nil}}

    assert Tokenizer.tokenize("[..2000]") ==
             {:ok, {[one_of: [{:range, [:undefined, [year: 2000]]}]], nil}}

    assert Tokenizer.tokenize("[..1984-10]") ==
             {:ok, {[one_of: [{:range, [:undefined, [year: 1984, month: 10]]}]], nil}}

    assert Tokenizer.tokenize("[..1760-12-03]") ==
             {:ok, {[one_of: [{:range, [:undefined, [year: 1760, month: 12, day: 3]]}]], nil}}

    assert Tokenizer.tokenize("[1984..]") ==
             {:ok, {[one_of: [{:range, [[year: 1984], :undefined]}]], nil}}

    assert Tokenizer.tokenize("[1760-12..]") ==
             {:ok, {[one_of: [{:range, [[year: 1760, month: 12], :undefined]}]], nil}}

    assert Tokenizer.tokenize("[1984-10-10..]") ==
             {:ok, {[one_of: [{:range, [[year: 1984, month: 10, day: 10], :undefined]}]], nil}}

    assert Tokenizer.tokenize("[1670..1673]") ==
             {:ok, {[one_of: [{:year, 1670..1673}]], nil}}

    assert Tokenizer.tokenize("[1984-10-10..1984-11-01]") ==
             {:ok,
              {[
                 one_of: [
                   {:range,
                    [
                      date: [year: 1984, month: 10, day: 10],
                      date: [year: 1984, month: 11, day: 1]
                    ]}
                 ]
               ], nil}}

    assert Tokenizer.tokenize("{..1983-12-31,1984-10-10..1984-11-01,1984-11-05..}") ==
             {:ok,
              {[
                 all_of: [
                   {:range, [:undefined, [year: 1983, month: 12, day: 31]]},
                   {:range,
                    [
                      date: [year: 1984, month: 10, day: 10],
                      date: [year: 1984, month: 11, day: 1]
                    ]},
                   {:range, [[year: 1984, month: 11, day: 5], :undefined]}
                 ]
               ], nil}}

    assert Tokenizer.tokenize("[1760-01,1760-02,1760-12..]") ==
             {:ok,
              {[
                 one_of: [
                   {:date, [year: 1760, month: 1]},
                   {:date, [year: 1760, month: 2]},
                   {:range, [[year: 1760, month: 12], :undefined]}
                 ]
               ], nil}}

    assert Tokenizer.tokenize("{1M2S..1M5S}") ==
             {:ok,
              {[
                 all_of: [
                   {:range,
                    [time_of_day: [minute: 1, second: 2], time_of_day: [minute: 1, second: 5]]}
                 ]
               ], nil}}
  end

  test "Group sets" do
    assert Tokenizer.tokenize("2018-{1,3,5}G2MU") ==
             {:ok, {[date: [year: 2018, group: [all_of: [1, 3, 5], month: 2]]], nil}}

    assert Tokenizer.tokenize("2018-[2,4]G3MU") ==
             {:ok, {[date: [year: 2018, group: [one_of: [2, 4], month: 3]]], nil}}
  end

  test "Set ranges of single time unit" do
    assert ~o"[2020..2030]" == %Tempo.Set{
             set: [%Tempo.Range{first: ~o"2020", last: ~o"2030"}],
             type: :one
           }
  end

  # A set's members are separated by commas, so within one a comma is never
  # a decimal sign. Read as one, `2023,2020` was a number, and the set one
  # interval from part way through 2023.
  describe "a comma between a set's members" do
    test "is not a decimal sign before an interval" do
      assert Tempo.from_iso8601("{2023,2020/2021}") == {:ok, ~o"{2023Y,2020Y/2021Y}"}
      assert Tempo.from_iso8601("[2020,2021/2022]") == {:ok, ~o"[2020Y,2021Y/2022Y]"}
      assert Tempo.from_iso8601("{2020-06,2021/2022}") == {:ok, ~o"{2020Y6M,2021Y/2022Y}"}

      assert Tempo.from_iso8601("{1985,1990/1995,2000}") ==
               {:ok, ~o"{1985Y,1990Y/1995Y,2000Y}"}
    end

    test "separates intervals written without designators" do
      assert Tempo.from_iso8601("{2020/2021,2023/2024}") ==
               Tempo.from_iso8601("{2020Y/2021Y,2023Y/2024Y}")

      assert Tempo.from_iso8601("[2020/2021,2023/2024]") ==
               Tempo.from_iso8601("[2020Y/2021Y,2023Y/2024Y]")

      assert {:ok, %Tempo.Set{set: [_week, %Tempo.Interval{}]}} =
               Tempo.from_iso8601("{2020W05,2021W05/2021W07}")

      assert {:ok, %Tempo.Set{set: [%Tempo.Range{}, %Tempo.Interval{}]}} =
               Tempo.from_iso8601("{2020..2022,2025/2026}")
    end

    test "separates the years of a recurrence's domain" do
      assert Tempo.from_iso8601("R/{2020,2022/2024}/P1Y") ==
               Tempo.from_iso8601("R/{2020Y,2022Y/2024Y}/P1Y")
    end

    test "is a decimal sign outside a set, and never inside one" do
      assert Tempo.from_iso8601("PT1,5H") == Tempo.from_iso8601("PT1.5H")
      assert Tempo.from_iso8601("T10:30:45,5") == Tempo.from_iso8601("T10:30:45.5")
      assert Tempo.from_iso8601("2023,5/2024") == Tempo.from_iso8601("2023.5/2024")

      assert {:ok, _durations} = Tempo.from_iso8601("{P1.5Y,P2Y}")
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("{P1,5Y}")
    end
  end
end
