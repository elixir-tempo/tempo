defmodule Tempo.Iso8601.SetFormsTest do
  @moduledoc """
  Sets the parser did not read: a member written with a qualifier, a fraction
  before the comma or the brace that follows a member, a fraction after a set
  of seconds, and the fractions of a second as a set, the form
  `Tempo.extend/2` gives a second and `inspect/1` writes.

  A member is measured against its own text read alone, and the fractions
  against the microseconds counted here from the digits written.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ParseError

  defp read(text), do: Tempo.from_iso8601!(text)

  # A set written from its members' texts, and those members read alone.
  defp set_of(members, {open, close}), do: read(open <> Enum.join(members, ",") <> close)

  defp reads_back?(value), do: read(Tempo.to_iso8601!(value)) == value

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
end
