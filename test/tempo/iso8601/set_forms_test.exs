defmodule Tempo.Iso8601.SetFormsTest do
  @moduledoc """
  Sets the parser did not read, or read as another value: a member written
  with a qualifier or with a suffix of its own, a set of one value in a unit,
  a set of days of the year
  after its year in the extended and the basic format, one of several years
  before the year designator, a range of a year's divisions, a fraction before the comma
  or the brace that follows a member, a fraction after a set of seconds, and
  the fractions of a second as a set, the form `Tempo.extend/2` gives a second
  and `inspect/1` writes.

  A member is measured against its own text read alone, and the fractions
  against the microseconds counted here from the digits written.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.ParseError

  defp read(text), do: Tempo.from_iso8601!(text)

  # A set written from its members' texts, and those members read alone.
  defp set_of(members, {open, close}), do: read(open <> Enum.join(members, ",") <> close)

  defp reads_back?(value), do: read(Tempo.to_iso8601!(value)) == value

  # The spans a value names, each as the instants it starts and ends at.
  defp spans(value) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{} = span} -> [bounds(span)]
      {:ok, %IntervalSet{} = set} -> Enum.map(IntervalSet.members(set), &bounds/1)
    end
  end

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  @braces [{"{", "}"}, {"[", "]"}]

  describe "a member of a set written with a qualifier" do
    # ISO 8601-2 §8 qualifies a date and time expression, and a set's members
    # are such expressions (§6.1): each member with a `?`, `~` or `%` was no
    # member the parser read.
    @qualified [
      ["2026-06-15?", "2026-06~"],
      ["?2026-06-15", "~2026-06"],
      ["2026%", "2027"],
      ["2026", "2027%"],
      ["2026Y6M15D?", "2026Y6M~"],
      ["2026-06-15T10:30?", "2026-06~"],
      ["T10:30?", "T11:00"],
      ["2026-W25?", "2026-W26"],
      ["2026-166~", "2026-167"],
      ["?2026-06-15?", "2026-06"],
      ["2026-06-15?", "2026-06-16?", "2026-06-17?"]
    ]

    test "is the member its text reads as alone" do
      for members <- @qualified, {_open, _close} = braces <- @braces do
        assert %Tempo.Set{set: read_members} = set_of(members, braces)
        assert {members, read_members} == {members, Enum.map(members, &read/1)}
      end
    end

    test "is all of its members or one of them, as the braces say" do
      for members <- @qualified do
        assert %Tempo.Set{type: :all} = set_of(members, {"{", "}"})
        assert %Tempo.Set{type: :one} = set_of(members, {"[", "]"})
      end
    end

    test "reads back from its own text" do
      for members <- @qualified, braces <- @braces do
        set = set_of(members, braces)
        assert {members, reads_back?(set)} == {members, true}
      end
    end

    test "qualifies the end of a range it is written on" do
      for {text, first, last} <- [
            {"{2020?..2030}", "2020?", "2030"},
            {"{2020..2030~}", "2020", "2030~"},
            {"{2020?..2030%}", "2020?", "2030%"},
            {"{2020-06?..2030-06}", "2020-06?", "2030-06"},
            {"{2020Y?..2030Y}", "2020Y?", "2030Y"}
          ] do
        assert %Tempo.Set{set: [%Tempo.Range{} = range]} = read(text)
        assert {text, range.first, range.last} == {text, read(first), read(last)}
        assert {text, reads_back?(read(text))} == {text, true}
      end
    end

    test "qualifies the one end of a range that is open" do
      assert %Tempo.Set{set: [%Tempo.Range{first: first, last: :undefined}]} = read("[2020?..]")
      assert first == read("2020?")

      assert %Tempo.Set{set: [%Tempo.Range{first: :undefined, last: last}]} = read("[..2030~]")
      assert last == read("2030~")
    end

    test "leaves a range's ends to be of the same units" do
      assert {:error, %ParseError{} = error} = Tempo.from_iso8601("{2020?..2030-06}")
      assert Exception.message(error) =~ "same time units on both sides"
    end

    test "is read in a recurrence's domain" do
      assert {:ok, recurrence} = Tempo.from_iso8601("R/{2020Y..2030Y,^2026Y?}/P1Y")
      assert reads_back?(recurrence)
    end
  end

  describe "a member of a set with a suffix of its own" do
    # RFC 9557's suffix (a zone, a calendar, a tag) is written after a date
    # or a time, and a member of a set is one. A set of values in two zones
    # is written with each member's zone after it, and that text was a parse
    # error: an end of an interval took a suffix and a member did not.
    @suffixed [
      ["2026-06-15T10:30[Europe/Paris]", "2026-06-15T10:30[America/New_York]"],
      ["2026-06-15T10:30[Europe/Paris]", "2026-06-15T11:00[Europe/Paris]"],
      ["2026-06-15[Europe/Paris]", "2026-06-16"],
      ["2026-06-15T10:30:00Z[Europe/Paris]", "2026-06-16T10:30:00+02:00[Europe/Paris]"],
      ["5786-06-15[u-ca=hebrew]", "2026-06-16"],
      ["2026-06-15?[Europe/Paris]", "2026-06-16"],
      ["T10:30[Europe/Paris]", "T11:00"],
      ["2026-06-15[foo=bar]", "2026-06-16"]
    ]

    test "is the member its text reads as alone" do
      for members <- @suffixed, {_open, _close} = braces <- @braces do
        assert %Tempo.Set{set: read_members} = set_of(members, braces)
        assert {members, read_members} == {members, Enum.map(members, &read/1)}
      end
    end

    test "reads back from its own text" do
      for members <- @suffixed, braces <- @braces do
        set = set_of(members, braces)
        assert {members, reads_back?(set)} == {members, true}
      end
    end

    test "takes the set's suffix where it has none of its own" do
      assert read("{2026-06-15[Europe/Paris],2026-06-16}[America/New_York]") ==
               %Tempo.Set{
                 type: :all,
                 set: [read("2026-06-15[Europe/Paris]"), read("2026-06-16[America/New_York]")]
               }
    end

    test "is each end of a range" do
      first = read("2026-06-15[Europe/Paris]")
      last = read("2026-06-20[Europe/Paris]")

      assert %Tempo.Set{set: [%Tempo.Range{first: ^first, last: ^last}]} =
               read("{2026-06-15[Europe/Paris]..2026-06-20[Europe/Paris]}")

      assert %Tempo.Set{set: [%Tempo.Range{first: :undefined, last: ^first}]} =
               read("[..2026-06-15[Europe/Paris]]")

      assert %Tempo.Set{set: [%Tempo.Range{first: ^first, last: :undefined}]} =
               read("[2026-06-15[Europe/Paris]..]")
    end

    test "is held to its zone and its calendar, as a value written alone is" do
      assert {:error, %Tempo.UnknownZoneError{}} =
               Tempo.from_iso8601("{2026-06-15[!Nowhere/Land],2026-06-16}")

      assert {:error, %Tempo.ZoneGapError{}} =
               Tempo.from_iso8601("{2011-12-29[Pacific/Apia],2011-12-30[Pacific/Apia]}")

      # The sixth month of a Hebrew year has twenty-nine days.
      assert {:error, %Tempo.InvalidDateError{}} =
               Tempo.from_iso8601("{5786-06-30[u-ca=hebrew],2026-06-16}")
    end

    test "is how a set of values in two zones is written" do
      set = %Tempo.Set{
        type: :all,
        set: [read("2026-06-15T10:30[Europe/Paris]"), read("2026-06-15T10:30[America/New_York]")]
      }

      assert Tempo.to_iso8601!(set) ==
               "{2026Y6M15DT10H30M[Europe/Paris],2026Y6M15DT10H30M[America/New_York]}"

      assert reads_back?(set)
    end
  end

  describe "a set of one value in a unit" do
    # A set with one member names what its member names. It was made the
    # member after the value was read, so a week and the one day of it in a
    # set stayed a week and a day, where the two alone are the date they
    # name, and the value written back was read as another. A set of one
    # masked year stayed a set, which no span was read from.
    @single [
      {"2026Y25W{1}K", "2026Y25W1K"},
      {"2026-W25-{1}", "2026-W25-1"},
      {"2026W25{1}", "2026W251"},
      {"2026Y{1}O", "2026Y1O"},
      {"2026Y{166}O", "2026Y166O"},
      {"2026Y{6}M", "2026Y6M"},
      {"2026-{06}-15", "2026-06-15"},
      {"T{9}H", "T9H"},
      {"{198X}", "198X"},
      {"{1950S2}", "1950S2"},
      {"{1950±2}", "1950±2"},
      {"{2026}", "2026"},
      {"2026Y{12..12}M", "2026Y12M"},
      {"2026Y6M{-1..-1}D", "2026Y6M30D"}
    ]

    test "is the value its member is alone" do
      for {set, member} <- @single do
        assert {set, read(set)} == {set, read(member)}
      end
    end

    test "reads back from its own text" do
      for {set, _member} <- @single do
        assert {set, reads_back?(read(set))} == {set, true}
      end
    end

    test "has the span its member has" do
      for {set, member} <- [{"{198X}", "198X"}, {"{1950S2}", "1950S2"}] do
        assert {:ok, span} = Tempo.to_interval(read(set))
        assert {set, {:ok, span}} == {set, Tempo.to_interval(read(member))}
      end
    end
  end

  describe "a set in a unit below the year that holds unspecified digits" do
    # A value with unspecified digits is some one of several, a value of its
    # own: a set of whole values holds it, and a set of years does. In a unit
    # below the year it was refused in the terms of the parser's own tokens.
    test "is refused, and the error says how it is written" do
      for text <- ["2026-{0X,1X}", "2026Y{0X,1X}M", "2026Y6M{1X,2X}D", "T{0X,1X}H"] do
        assert {^text, {:error, %Tempo.InvalidDateError{reason: reason}}} =
                 {text, Tempo.from_iso8601(text)}

        assert reason =~ "has unspecified digits"
        refute reason =~ ":mask"
      end
    end

    test "is read as values of their own, and in a set of years" do
      assert %Tempo.Set{set: [first, second]} = read("{2026-0X,2026-1X}")
      assert {first, second} == {read("2026-0X"), read("2026-1X")}
      assert %Tempo{} = read("{198X,199X}")
    end
  end

  describe "a set of days of the year in the extended and the basic format" do
    # A day of the year is three digits after its year (`2026-166`,
    # `2026166`). A set written there was read as the year's months whatever
    # the width of its members, so `2026-{001}` was January and
    # `2026-{001,166}` an error that named the months.
    @days_of_the_year [
      {"2026-{001,166}", ["2026-001", "2026-166"]},
      {"2026-{166,001}", ["2026-001", "2026-166"]},
      {"2026-{001,166,365}", ["2026-001", "2026-166", "2026-365"]},
      {"2026-{001..003}", ["2026-001", "2026-002", "2026-003"]},
      {"2026-{001,166..168}", ["2026-001", "2026-166", "2026-167", "2026-168"]},
      {"2026{001,166}", ["2026001", "2026166"]},
      {"2026{001..003}", ["2026001", "2026002", "2026003"]},
      {"2026-{100,200}T10", ["2026-100T10", "2026-200T10"]}
    ]

    test "is each day as it is read alone" do
      for {set, days} <- @days_of_the_year do
        assert {set, spans(read(set))} == {set, Enum.flat_map(days, &spans(read(&1)))}
      end
    end

    test "of one day is that day" do
      assert read("2026-{001}") == read("2026-001")
      assert read("2026{001}") == read("2026001")
      assert read("2026-{001}") == ~o"2026-01-01"
    end

    test "is the year's months where its members are not three digits each" do
      assert read("2026-{01,03}") == read("2026Y{1,3}M")
      assert read("2026-{6,7}-15") == read("2026Y{6,7}M15D")
      assert read("2026{01,03}15") == read("2026Y{1,3}M15D")
    end

    test "is held to the days its year has" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026-{001,366}")
      assert {:ok, _days} = Tempo.from_iso8601("2028-{001,366}")
    end

    test "reads back from its own text" do
      for {set, _days} <- @days_of_the_year do
        assert {set, reads_back?(read(set))} == {set, true}
      end
    end
  end

  describe "one of several years before the year designator" do
    # ISO 8601-2 §6.6: a set of whole numbers, all of them or one of them,
    # is written where a whole number is. One of several months was read
    # (`2026Y[1,3]M`) and one of several years was a parse error.
    @one_of_years [
      {"[2025,2026]Y", ["2025Y", "2026Y"]},
      {"[2025,2026]Y6M", ["2025Y6M", "2026Y6M"]},
      {"[2025,2026]Y6M15D", ["2025Y6M15D", "2026Y6M15D"]},
      {"[2025..2027]Y", ["2025Y", "2026Y", "2027Y"]},
      {"[2025,2026]Y25W", ["2025Y25W", "2026Y25W"]},
      {"[2025,2026]Y6M15DT10H", ["2025Y6M15DT10H", "2026Y6M15DT10H"]},
      {"[2025,2026]Y[1,3]M", ["2025Y1M", "2025Y3M", "2026Y1M", "2026Y3M"]},
      {"[2025]Y6M", ["2025Y6M"]}
    ]

    test "is one of the values its members are alone" do
      for {set, members} <- @one_of_years do
        assert {set, read(set)} ==
                 {set, %Tempo.Set{type: :one, set: Enum.map(members, &read/1)}}
      end
    end

    test "reads back from its own text" do
      for {set, _members} <- @one_of_years do
        assert {set, reads_back?(read(set))} == {set, true}
      end
    end

    test "leaves a set of whole values as it was" do
      assert read("[2025,2026]") == read("[2025Y,2026Y]")
      assert %Tempo{} = read("{2025,2026}Y6M")
    end
  end

  describe "a range of a year's divisions in a set" do
    # A season, a quarter, a quadrimester and a semester (ISO 8601-2 Table 2)
    # are each a span of dates, and a range from one to another is every one
    # of them between (§6.3 c). It was read as a range whose ends were
    # intervals: nothing walked it, and its own text was not read back.
    @divisions [
      {"{2026-21..2026-23}", ["2026-21", "2026-22", "2026-23"]},
      {"[2026-21..2026-22]", ["2026-21", "2026-22"]},
      {"{2026-33..2026-36}", ["2026-33", "2026-34", "2026-35", "2026-36"]},
      {"{2026-35..2027-34}", ["2026-35", "2026-36", "2027-33", "2027-34"]},
      {"{2026-37..2026-39}", ["2026-37", "2026-38", "2026-39"]},
      {"{2026-40..2027-41}", ["2026-40", "2026-41", "2027-40", "2027-41"]},
      {"{2026-25..2027-26}", ["2026-25", "2026-26", "2026-27", "2026-28", "2027-25", "2027-26"]},
      {"{2026-21,2026-22..2026-23}", ["2026-21", "2026-22", "2026-23"]},
      {"{2026-21..2026-21}", ["2026-21"]},
      {"{2026Y21M..2026Y23M}", ["2026-21", "2026-22", "2026-23"]}
    ]

    test "is each division between them, as it is read alone" do
      for {set, members} <- @divisions do
        assert %Tempo.Set{set: read_members} = read(set)
        assert {set, read_members} == {set, Enum.map(members, &read/1)}
      end
    end

    test "is a run in time, each division beginning where the one before it ends" do
      for {set, _members} <- @divisions do
        %Tempo.Set{set: members} = read(set)
        spans = Enum.flat_map(members, &spans/1)

        for {{_from, ends}, {begins, _to}} <- Enum.zip(spans, Enum.drop(spans, 1)) do
          assert {set, ends} == {set, begins}
        end
      end
    end

    test "reads back from its own text" do
      for {set, _members} <- @divisions do
        assert {set, reads_back?(read(set))} == {set, true}
      end
    end

    test "is refused where its divisions are no run in time" do
      # The winter of a year begins in the December before it, and a
      # southern autumn and winter come before that year's spring.
      for text <- [
            "{2026-21..2026-24}",
            "{2025-23..2026-22}",
            "{2026-24..2027-21}",
            "{2026-29..2026-32}"
          ] do
        assert {^text, {:error, %Tempo.InvalidDateError{reason: reason}}} =
                 {text, Tempo.from_iso8601(text)}

        assert reason =~ "do not run on from one another"
      end
    end

    test "is refused from one kind to another, open at an end, and beyond a thousand" do
      for text <- ["{2026-21..2026-33}", "{..2026-22}", "{2026-21..}", "{0001-21..9999-24}"] do
        assert {^text, {:error, %Tempo.InvalidDateError{}}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "leaves a range of months, and the divisions written one by one" do
      assert %Tempo.Set{set: [%Tempo.Range{}]} = read("{2026-06..2026-08}")

      assert read("{2026-21,2026-24}") == %Tempo.Set{
               type: :all,
               set: [read("2026-21"), read("2026-24")]
             }
    end
  end

  describe "a fraction before the comma or the brace that follows a member" do
    # The digits of a fraction were taken to run on to the end of the text,
    # so one inside a set took the comma or the brace for more of the number.
    @with_fractions [
      ["T10:30:45.5", "T11:00"],
      ["T11:00", "T10:30:45.5"],
      ["2021-06-15T10:30:45.5", "2021-06-16"],
      ["T10:30:45.25"],
      ["T10:30:45.5", "T10:30:46.5", "T10:30:47.5"],
      ["T10.5", "T11"],
      ["T10:30.5", "T11:00"],
      ["2021-06-15.5"],
      ["2021.5", "2022"]
    ]

    test "is the fraction of the member it is written in" do
      for members <- @with_fractions, braces <- @braces do
        assert %Tempo.Set{set: read_members} = set_of(members, braces)
        assert {members, read_members} == {members, Enum.map(members, &read/1)}
      end
    end

    test "reads back from its own text" do
      for members <- @with_fractions, braces <- @braces do
        set = set_of(members, braces)
        assert {members, reads_back?(set)} == {members, true}
      end
    end

    test "is the fraction of each end of a range" do
      assert %Tempo.Set{set: [%Tempo.Range{first: first, last: last}]} =
               read("{T10:30:45.5..T10:30:46.5}")

      assert {first, last} == {read("T10:30:45.5"), read("T10:30:46.5")}
    end

    test "is still one fraction, with one decimal sign" do
      for text <- [
            "T10:30:45.5.5",
            "T10.5.5",
            "2026Y6M15DT10H30M45.5.5S",
            "{T10:30:45.5.5,T11:00}"
          ] do
        assert {^text, {:error, %ParseError{}}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "is never written with a comma, which separates the members" do
      assert {:error, %ParseError{}} = Tempo.from_iso8601("{T10:30:45,5,T11:00}")
    end
  end

  describe "a fraction after a set of seconds" do
    # `{45,50}.5S` kept the fraction as it was tokenized, which nothing after
    # the parser reads, and `inspect/1` raised.
    test "is the fraction of each second" do
      assert Enum.to_list(~o"2026Y6M15DT10H30M{45,50}.5S") ==
               [~o"2026Y6M15DT10H30M45.5S", ~o"2026Y6M15DT10H30M50.5S"]

      assert Enum.to_list(~o"T10H30M{45..47}.25S") ==
               [~o"T10H30M45.25S", ~o"T10H30M46.25S", ~o"T10H30M47.25S"]
    end

    test "is written with either decimal sign and in the extended format" do
      expected = ~o"2026Y6M15DT10H30M{45,50}.5S"

      assert read("2026Y6M15DT10H30M{45,50},5S") == expected
      assert read("2026-06-15T10:30:{45,50}.5") == expected
    end

    test "reads back from its own text" do
      for text <- ["2026Y6M15DT10H30M{45,50}.5S", "T10H30M{45..47}.25S", "T{45,50}.125S"] do
        assert {text, Tempo.to_iso8601!(read(text))} == {text, text}
      end
    end
  end

  describe "the fractions of a second written as a set" do
    # The fractions a range of digits names, each held to the digits written:
    # `.{50..59}` is the hundredths from 0.50 to 0.59.
    defp microseconds(range, digits),
      do: for(fraction <- range, do: {fraction * Integer.pow(10, 6 - digits), digits})

    defp digits_of(fraction, digits),
      do: fraction |> Integer.to_string() |> String.pad_leading(digits, "0")

    defp fractions_of(%Tempo{time: time}), do: Keyword.fetch!(time, :microsecond)

    test "are the microseconds its digits count, from a first to a last" do
      for digits <- 1..6,
          first.._//_ = range <- [0..9, 3..7, 5..5, 0..(min(Integer.pow(10, digits), 1000) - 1)],
          range.last < Integer.pow(10, digits) do
        text = "T10H30M45.{#{digits_of(first, digits)}..#{digits_of(range.last, digits)}}S"

        assert {text, fractions_of(read(text))} == {text, microseconds(range, digits)}
      end
    end

    test "are the microseconds its digits count, one by one" do
      assert fractions_of(read("T10H30M45.{0,5}S")) == [{0, 1}, {500_000, 1}]
      assert fractions_of(read("T10H30M45.{00,25,75}S")) == [{0, 2}, {250_000, 2}, {750_000, 2}]
      assert fractions_of(read("T10H30M45.{5}S")) == [{500_000, 1}]
    end

    test "are in order and none twice, however they are written" do
      assert read("T10H30M45.{5,0}S") == read("T10H30M45.{0,5}S")
      assert read("T10H30M45.{5,5}S") == read("T10H30M45.{5}S")
      assert read("T10H30M45.{5..5}S") == read("T10H30M45.{5}S")
    end

    test "is each fraction of the second when it is walked" do
      assert Enum.to_list(~o"2026Y6M15DT10H30M45.{0,5}S") ==
               [~o"2026Y6M15DT10H30M45.0S", ~o"2026Y6M15DT10H30M45.5S"]

      assert Enum.to_list(~o"2026Y6M15DT10H30M{45,50}.{0,5}S") ==
               [
                 ~o"2026Y6M15DT10H30M45.0S",
                 ~o"2026Y6M15DT10H30M45.5S",
                 ~o"2026Y6M15DT10H30M50.0S",
                 ~o"2026Y6M15DT10H30M50.5S"
               ]
    end

    test "is what extend/2 gives a second, read back from what is written" do
      for text <- [
            "T10H30M45S",
            "2026Y6M15DT10H30M45S",
            "2026Y6M15DT10H30M45SZ",
            "2026Y6M15DT10H30M45S[Europe/Paris]",
            "2026Y6M15DT10H30M{45,50}S",
            "2026Y6M15DT10H30M45.5S",
            "2026Y6M15DT10H30M45.12S",
            "2026Y6M15DT10H30M45.123S",
            "2026Y6M15DT10H30M45.1234S",
            "2026Y6M15DT10H30M45.12345S"
          ] do
        {:ok, extended} = Tempo.extend(read(text))
        written = Tempo.to_iso8601!(extended)

        assert {text, written =~ ".{"} == {text, true}
        assert {text, Tempo.from_iso8601(written)} == {text, {:ok, extended}}
        assert {text, inspect(extended)} == {text, ~s(~o"#{written}")}
      end
    end

    test "is what extend/2 gives down to the thousandths of a second" do
      {:ok, tenths} = Tempo.extend(~o"2026Y6M15DT10H30M45S")
      {:ok, hundredths} = Tempo.extend(tenths)
      {:ok, thousandths} = Tempo.extend(hundredths)

      for extended <- [tenths, hundredths, thousandths] do
        assert reads_back?(extended)
      end

      assert Tempo.to_iso8601!(thousandths) == "2026Y6M15DT10H30M45.{000..999}S"
    end

    test "takes either decimal sign" do
      assert read("T10H30M45,{0..9}S") == read("T10H30M45.{0..9}S")
    end

    test "keeps what follows the second" do
      assert read("2026Y6M15DT10H30M45.{0..9}SZ").shift == [hour: 0]
      assert read("2026Y6M15DT10H30M45.{0..9}S?") |> reads_back?()

      assert %Tempo.Interval{from: from} = read("2026Y6M15DT10H30M45.{0..9}S/P1D")
      assert from == read("2026Y6M15DT10H30M45.{0..9}S")
    end

    test "is refused where the fractions are not of one precision" do
      for text <- ["T10H30M45.{1,25}S", "T10H30M45.{0..10}S", "T10H30M45.{00,5}S"] do
        assert {^text, {:error, %ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert Exception.message(error) =~ "not written with as many digits as each other"
      end
    end

    test "is refused where a range runs back" do
      assert {:error, %ParseError{} = error} = Tempo.from_iso8601("T10H30M45.{9..0}S")
      assert Exception.message(error) =~ "run back from the first to the last"
    end

    test "is refused where the fractions are finer than a microsecond" do
      for text <- ["T10H30M45.{0000000..0000009}S", "T10H30M45.{1234567,1234568}S"] do
        assert {^text, {:error, %ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert Exception.message(error) =~ "finer than a microsecond"
      end
    end

    # A value holds each fraction it names, so a range is listed as it is
    # read. A thousand is each millisecond of a second: with no bound a text
    # of twenty characters would list a million.
    test "is refused where a range names more than a thousand" do
      assert Enum.count(fractions_of(read("T10H30M45.{000000..000999}S"))) == 1000

      for text <- [
            "T10H30M45.{0000..9999}S",
            "T10H30M45.{000000..001000}S",
            "T10H30M45.{000000..999999}S"
          ] do
        assert {^text, {:error, %ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert Exception.message(error) =~ "more than a thousand in one range"
      end
    end

    test "is not read in a form that is no set of fractions" do
      for text <- [
            "T10H30M45.{}S",
            "T10H30M45.{0..3,7}S",
            "T10H30M45.{-1..3}S",
            "T10H30M45.{0, 5}S",
            "T10H30M45.[0,5]S",
            "T10H30M45.{0..9}",
            "T10H30M45.{0..9}M",
            "T10:30:45.{0..9}",
            "PT45.{0..9}S"
          ] do
        assert {^text, {:error, %ParseError{}}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "is held to the seconds a minute has" do
      assert {:error, _not_a_second} = Tempo.from_iso8601("2026Y6M15DT10H30M61.{0..9}S")
    end
  end

  describe "the basic format with unspecified digits or a set where a number goes on" do
    # A number of the basic format goes on into the next with no separator,
    # and the next may be unspecified digits or a set. An hour alone and a
    # week written with its designator were each read as far as the number,
    # with the rest left over, where a digit after them was not.
    for {basic, extended} <- [
          {"T10XX", "T10:XX"},
          {"T10X5", "T10:X5"},
          {"T10{30,45}", "T10:{30,45}"},
          {"T10{30..45}", "T10:{30..45}"},
          {"T10XX15", "T10:XX:15"},
          {"T10{30,45}15", "T10:{30,45}:15"},
          {"2026WXX", "2026-WXX"},
          {"2026WXX1", "2026-WXX-1"},
          {"2026W{25,26}", "2026-W{25,26}"},
          {"2026W{25,26}1", "2026-W{25,26}-1"},
          {"2026W{25..27}1", "2026-W{25..27}-1"}
        ] do
      test "#{basic} is read as #{extended} is" do
        assert {:ok, value} = Tempo.from_iso8601(unquote(basic))
        assert Tempo.from_iso8601(unquote(extended)) == {:ok, value}
      end
    end

    test "what was read is read as it was" do
      assert Tempo.from_iso8601("T1030") == Tempo.from_iso8601("T10:30")
      assert Tempo.from_iso8601("T10") == Tempo.from_iso8601("T10H")
      assert Tempo.from_iso8601("2026W251") == Tempo.from_iso8601("2026-W25-1")
      assert Tempo.from_iso8601("2026W25") == Tempo.from_iso8601("2026-W25")

      # A week alone in the explicit form, and with a set of its days.
      assert {:ok, week} = Tempo.from_iso8601("25W")
      assert week.time == [week: 25]
      assert {:ok, days} = Tempo.from_iso8601("25W{1,3}K")
      assert days.time == [week: 25, day_of_week: [1, 3]]
    end
  end
end
