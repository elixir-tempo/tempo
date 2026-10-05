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

  # A set of whole numbers written with no designator was a set of years
  # whatever its numbers: `{20260615,20260616}` was the years 20260615 and
  # 20260616, and `{19,20}` the years 19 and 20. A year is written with four
  # digits, or with more after a sign (ISO 8601-1 §4.4), so a set whose
  # numbers are not written so is read member by member, as a set of one of
  # is: each member is what it is alone (decided 2026-10-06).
  describe "a set of whole numbers written with no designator" do
    defp read(text), do: Tempo.from_iso8601!(text)

    test "is its members, each as it is read alone, where they are no years" do
      for members <- [
            ["20260615", "20260616"],
            ["202606", "202607"],
            ["2026166", "2026167"],
            ["20260615", "2026"],
            ["2026", "20260615"]
          ] do
        text = "{" <> Enum.join(members, ",") <> "}"

        assert {text, read(text)} ==
                 {text, %Tempo.Set{type: :all, set: Enum.map(members, &read/1)}}
      end
    end

    test "has the members a set of one of has" do
      for members <- ["20260615,20260616", "202606,202607", "2026166,2026167"] do
        assert %Tempo.Set{type: :all, set: all} = read("{" <> members <> "}")
        assert %Tempo.Set{type: :one, set: one} = read("[" <> members <> "]")
        assert {members, all} == {members, one}
      end
    end

    test "is a range of dates where its ends are dates" do
      assert %Tempo.Set{set: [%Tempo.Range{first: first, last: last}]} =
               read("{20260615..20260620}")

      assert {first, last} == {read("20260615"), read("20260620")}
    end

    test "is a set of years where each has four digits, or more after a minus sign" do
      assert read("{1960,1961}") == ~o"{1960,1961}Y"
      assert read("{0019,0020}") == ~o"{19,20}Y"
      assert read("{-1640,1200}") == ~o"{-1640,1200}Y"
      assert read("{1960..1970//2}") == ~o"{1960..1970//2}Y"
      assert read("{-20260615,-20260616}") == ~o"{-20260616,-20260615}Y"
      assert read("{1960,1961}-06") == ~o"{1960,1961}Y6M"
    end

    test "is the centuries or the decades its members are alone" do
      for members <- [
            ["19", "20"],
            ["196", "197"],
            ["2020", "20"],
            ["19", "196", "1960"],
            ["-19", "-20"],
            ["19"]
          ] do
        text = "{" <> Enum.join(members, ",") <> "}"

        assert {text, read(text)} ==
                 {text, %Tempo.Set{type: :all, set: Enum.map(members, &read/1)}}

        assert %Tempo.Set{type: :one, set: one_of} = read("[" <> Enum.join(members, ",") <> "]")
        assert {text, one_of} == {text, Enum.map(members, &read/1)}
      end
    end

    test "is a range of centuries where its ends are centuries" do
      assert %Tempo.Set{set: [%Tempo.Range{first: first, last: last}]} = read("{19..20}")
      assert {first, last} == {read("19"), read("20")}
    end

    test "qualifies each of its members where it is qualified as a whole" do
      assert %Tempo.Set{set: [first, second]} = read("{19,20}?")
      assert {first, second} == {read("19?"), read("20?")}
    end

    test "is refused where a member is neither a year nor a value alone" do
      for text <- ["{12022,12023}", "{19999,2000}", "{12345}", "{1,2}", "{1}", "{1..2}"] do
        assert {^text, {:error, %Tempo.ParseError{}}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "is refused before a month where its members are no years" do
      for text <- ["{19,20}-06", "{19,20}-06-15", "{196,197}-06"] do
        assert {^text, {:error, _not_a_date}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "is a set of years of any digits where the designator says so" do
      assert read("{20260615,20260616}Y").time == [year: [20_260_615..20_260_616]]
      assert read("{12022,12023}Y").time == [year: [12_022..12_023]]
      assert read("{19,20}Y").time == [year: [19..20]]
      assert read("{1,2}Y").time == [year: [1..2]]
    end

    test "is no time of day, which is written after a T" do
      assert read("T{19,20}").time == [hour: [19..20]]
      assert read("T{19,20}:30").time == [hour: [19..20], minute: 30]
      assert read("2026-06-15T{10,11}").time == [year: 2026, month: 6, day: 15, hour: [10..11]]
    end
  end

  # Two digits are a century, and an hour where a fraction follows them
  # (`09,5`). In a set a comma separates the members and two full stops are
  # a range, so the first of `[19,20]` and of `[19..20]` was the hour 19
  # beside the century its second member is.
  describe "two digits before a comma or a range in a set" do
    test "are the century they are alone" do
      assert %Tempo.Set{type: :one, set: [nineteenth, twentieth]} = Tempo.from_iso8601!("[19,20]")
      assert {nineteenth, twentieth} == {Tempo.from_iso8601!("19"), Tempo.from_iso8601!("20")}

      assert %Tempo.Set{set: [%Tempo.Range{first: first, last: last}]} =
               Tempo.from_iso8601!("[19..20]")

      assert {first, last} == {Tempo.from_iso8601!("19"), Tempo.from_iso8601!("20")}
    end

    test "are an hour where a fraction follows them" do
      assert Tempo.from_iso8601!("09,5") == ~o"T9H30M"
      assert Tempo.from_iso8601!("19.5") == ~o"T19H30M"

      assert %Tempo.Set{set: [half_past, century]} = Tempo.from_iso8601!("[19.5,20]")
      assert {half_past, century} == {~o"T19H30M", Tempo.from_iso8601!("20")}
    end
  end

  # The ends of a range of one unit were held as they are tokenized, so a
  # century stayed `[century: 19]`, which nothing after the parser reads:
  # `inspect/1` raised on `{19C..20C}`.
  describe "a range of centuries or of decades in a set" do
    test "runs from the years of one to the years of the other" do
      for {text, first, last} <- [
            {"{19C..20C}", "19C", "20C"},
            {"[19C..20C]", "19C", "20C"},
            {"{196J..197J}", "196J", "197J"},
            {"[196..197]", "196", "197"}
          ] do
        assert %Tempo.Set{set: [%Tempo.Range{} = range]} = Tempo.from_iso8601!(text)

        assert {text, range.first, range.last} ==
                 {text, Tempo.from_iso8601!(first), Tempo.from_iso8601!(last)}
      end
    end

    test "is written, and reads back from its own text" do
      for text <- ["{19C..20C}", "{196J..197J}", "[196..197]"] do
        value = Tempo.from_iso8601!(text)
        assert {text, Tempo.from_iso8601(Tempo.to_iso8601!(value))} == {text, {:ok, value}}
      end

      assert inspect(Tempo.from_iso8601!("{19C..20C}")) == ~s(~o"{20G100YU..21G100YU}")
    end
  end

  # A range in a set of a unit's values runs from one whole number to
  # another. Between unspecified digits the tokenizer raised a
  # `FunctionClauseError`.
  describe "a range between unspecified digits in a set of a unit's values" do
    test "is refused" do
      for text <- ["2026Y{1X..2X}M", "{1X..2X}D", "T{1X..2X}H", "{1..2X}M", "2026-{1X..2X}"] do
        assert {^text, {:error, %Tempo.ParseError{}}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "is a range of masked years where each end is a year" do
      assert %Tempo.Set{set: [%Tempo.Range{first: first, last: last}]} =
               Tempo.from_iso8601!("{19XX..20XX}")

      assert {first, last} == {Tempo.from_iso8601!("19XX"), Tempo.from_iso8601!("20XX")}
    end

    test "leaves a range of whole numbers as it was" do
      assert Tempo.from_iso8601!("2026Y{1..5}M").time == [year: 2026, month: [1..5]]
      assert Tempo.from_iso8601!("2026Y{1..9//2}M").time == [year: 2026, month: [1..9//2]]
      assert Tempo.from_iso8601!("2026Y{1..-1}M").time == [year: 2026, month: [1..12]]
    end
  end

  # A set of a unit's values is put in order as it is read. One holding a
  # member with unspecified digits, significant digits or a margin of error
  # has no one order, and ordering it raised a `FunctionClauseError` unless
  # that member came first.
  describe "a set of a unit's values with a member that is no whole number" do
    test "is read as it is written" do
      assert Tempo.from_iso8601!("{2020,19XX}Y").time ==
               [year: [2020, {:mask, [1, 9, :X, :X]}]]

      assert Tempo.from_iso8601!("{1950S2,1960}Y").time ==
               [year: [{1950, [significant_digits: 2]}, 1960]]

      assert Tempo.from_iso8601!("{1960,1950±2}Y").time ==
               [year: [1960, {1950, [margin_of_error: 2]}]]
    end

    test "is each of its members when it is walked" do
      assert Enum.to_list(Tempo.from_iso8601!("{1950S2,1960}Y")) == [~o"1950S2Y", ~o"1960Y"]
      assert Enum.to_list(Tempo.from_iso8601!("{2020,19XX}Y")) == [~o"2020Y", ~o"19XXY"]
    end

    test "reads back from its own text" do
      for text <- ["{2020,19XX}Y", "{19XX,2020}Y", "{1950S2,1960}Y", "{1960,2020,19XX}Y"] do
        value = Tempo.from_iso8601!(text)
        assert {text, Tempo.from_iso8601(Tempo.to_iso8601!(value))} == {text, {:ok, value}}
      end
    end

    test "is refused where the unit takes no such member" do
      for text <- ["2026Y{1S1,2}M", "2026Y{2,1X}M", "T{10,1X}H"] do
        assert {^text, {:error, _not_a_value}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "leaves a set of whole numbers in order" do
      assert Tempo.from_iso8601!("{2,1,3}M") == ~o"{1..3}M"
      assert Tempo.from_iso8601!("{3,1..2}M") == ~o"{1..3}M"
    end
  end
end
