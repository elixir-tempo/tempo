defmodule Tempo.Parser.Set.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Iso8601.Tokenizer

  test "Set expressions: all of" do
    assert Tokenizer.tokenize("{1960,1961,1962}") ==
             {:ok, {[date: [year: {:all_of, [1960, 1961, 1962]}]], nil}}

    assert Tokenizer.tokenize("{1960,1961-12}") ==
             {:ok, {[all_of: [date: [year: 1960], date: [year: 1961, month: 12]]], nil}}

    assert Tokenizer.tokenize("{1M2S}") ==
             {:ok, {[all_of: [time_of_day: [minute: 1, second: 2]]], nil}}

    assert Tokenizer.tokenize("{T1M2S,T1M3S}") ==
             {:ok,
              {[
                 all_of: [
                   time_of_day: [minute: 1, second: 2],
                   time_of_day: [minute: 1, second: 3]
                 ]
               ], nil}}

    assert Tokenizer.tokenize("{PT1M2S..PT1M5S}") ==
             {:ok,
              {[
                 all_of: [
                   range: [duration: [minute: 1, second: 2], duration: [minute: 1, second: 5]]
                 ]
               ], nil}}
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

      assert Tempo.from_iso8601("{T10H30.5M,T11H}") == {:ok, ~o"{T10H30M30S,T11H}"}
      assert {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("{T10H30,5M,T11H}")
    end
  end

  # A member was built from its units as a date is, whatever it was: a
  # duration's `[year: 1]` was the year 1, so `{P1Y,P2Y}` equalled `{1Y,2Y}`
  # and `{P1M2S,P1M3S}` was `{1M1DT2S,1M1DT3S}`. ISO 8601-2 §6.5 has sets of
  # durations, which are not built, so one is refused until it is.
  describe "a duration written in a set" do
    @reason "A duration is not read as a member of a set"

    test "is refused as a member, whatever is beside it" do
      for text <- [
            "{P1Y,P2Y}",
            "[P1M2S,P1M3S]",
            "{P1D}",
            "{P1D}?",
            "{P1D,2026-06-15}",
            "{2026-06-15,P1D}",
            "{PT1.5S,PT2S}",
            "{-P1D,P2D}",
            "{P0001-02-03,P2D}",
            "{P1D,P2D}[u-ca=hebrew]"
          ] do
        assert {^text, {:error, %Tempo.ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert Exception.message(error) =~ @reason
      end
    end

    test "is refused as an end of a range" do
      for text <- ["{PT1M2S..PT1M5S}", "{P1D..P5D}", "{2026..P1D}", "[P1D..]", "[..P1D]"] do
        assert {^text, {:error, %Tempo.ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert Exception.message(error) =~ @reason
      end
    end

    test "is refused as a member the set leaves out, and in a recurrence's domain" do
      for text <- [
            "{^P1D,2026}",
            "{2026,^P1D}",
            "R/{P1D,2026}/P1Y",
            "R/{2020Y..2030Y,^P1D}/P1Y"
          ] do
        assert {^text, {:error, %Tempo.ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert Exception.message(error) =~ @reason
      end
    end

    test "is the duration of an interval the set holds" do
      for {text, member} <- [
            {"{P1D/2026-06-15,2026-07}", "P1D/2026-06-15"},
            {"{2026-06-15/P1D,2026-07}", "2026-06-15/P1D"},
            {"{R/2026/P1D,2027}", "R/2026/P1D"}
          ] do
        assert %Tempo.Set{set: [first | _rest]} = Tempo.from_iso8601!(text)
        assert {text, first} == {text, Tempo.from_iso8601!(member)}
      end
    end

    test "is read where it is no member of a set" do
      assert Tempo.from_iso8601("P1Y") == {:ok, ~o"P1Y"}
      assert {:ok, %Tempo.Interval{duration: ~o"P1Y"}} = Tempo.from_iso8601("2026/P1Y")
      assert {:ok, _recurrence} = Tempo.from_iso8601("R/{2020Y..2030Y,^2026Y}/P1Y")
    end

    test "leaves units written without the designator the times they are" do
      assert %Tempo.Set{set: [%Tempo.Range{first: first, last: last}]} =
               Tempo.from_iso8601!("{1M2S..1M5S}")

      assert {first, last} == {~o"T1M2S", ~o"T1M5S"}

      assert %Tempo.Set{set: [~o"T1M2S", ~o"T1M3S"], type: :one} =
               Tempo.from_iso8601!("[1M2S,1M3S]")
    end
  end

  # A range runs from one date or time to another. Its end was built from
  # both ends of an interval as one value, which `inspect/1` raised on.
  describe "an interval written at an end of a range" do
    test "is refused" do
      for text <- [
            "{2020/2021..2023/2024}",
            "{2020/2021..2023}",
            "{2020..2021/2023}",
            "[2020/2021..]",
            "[..2020/2021]",
            "{^2020/2021..2023,2026}",
            "{R/2026/P1D..2027}",
            "R/{2020/2021..2023/2024}/P1Y"
          ] do
        assert {^text, {:error, %Tempo.ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert Exception.message(error) =~ "An interval is not an end of a range in a set"
      end
    end

    test "is a member of the set where it is written as one" do
      assert %Tempo.Set{set: [%Tempo.Interval{}, %Tempo.Interval{}]} =
               Tempo.from_iso8601!("{2020/2021,2023/2024}")
    end

    test "leaves a range of dates or of times as it was" do
      for {text, first, last} <- [
            {"{2020-06..2023-06}", "2020-06", "2023-06"},
            {"{T10:30..T11:30}", "T10:30", "T11:30"},
            {"{2026-06-15T10:30..2026-06-16T10:30}", "2026-06-15T10:30", "2026-06-16T10:30"}
          ] do
        assert %Tempo.Set{set: [%Tempo.Range{} = range]} = Tempo.from_iso8601!(text)

        assert {text, range.first, range.last} ==
                 {text, Tempo.from_iso8601!(first), Tempo.from_iso8601!(last)}
      end

      assert %Tempo.Set{set: [%Tempo.Range{first: first, last: :undefined}]} =
               Tempo.from_iso8601!("[2020..]")

      assert first == ~o"2020"
    end
  end
end
