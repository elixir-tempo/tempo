defmodule Tempo.Iso8601.Tokenizer.PlainTest do
  use ExUnit.Case, async: true

  # The plain forms of a date and a time of day are read by a scan of their
  # bytes (`Tempo.Iso8601.Tokenizer.Plain`), which must give what the grammar
  # gives for every string, or leave the string to it. The measure is the
  # grammar's own reading (`Tempo.Iso8601.Tokenizer.tokenize_by_grammar/1`):
  # texts of the shapes the scan reads, with each field at the edges of what
  # it takes and past them, and each text with a byte of it changed or
  # something written after it. Every value two digits can write in each
  # field, a hundred thousand texts, runs with `mix test --include
  # exhaustive`.

  alias Tempo.Iso8601.Tokenizer
  alias Tempo.Iso8601.Tokenizer.Plain

  @two_digits for tens <- ?0..?9, units <- ?0..?9, do: <<tens, units>>

  # Values at the edges of what each field takes, and past them.
  @months ~w(00 01 02 06 09 10 12 13 19 20 99)
  @days ~w(00 01 09 10 19 20 28 29 30 31 32 39 40 99)
  @hours ~w(00 09 10 23 24 25 99)
  @minutes ~w(00 30 59 60 99)
  @seconds ~w(00 30 59 60 61 99)
  @fractions ["", ".5", ".123", ".123456", ".1234567", ".000", ",5", "."]
  @shifts [
    "",
    "Z",
    "z",
    "+00:00",
    "-00:00",
    "-00:30",
    "+02:00",
    "-05:30",
    "+14:00",
    "-23:59",
    "+24:00",
    "+02:60",
    "+02",
    "+0200",
    "+2:00",
    "+02:00:00"
  ]

  # Where the two readings of a text differ, in a task for each batch.
  defp differences(texts) do
    texts
    |> Enum.chunk_every(500)
    |> Task.async_stream(
      fn batch ->
        for text <- batch,
            scanned = Tokenizer.tokenize(text),
            by_grammar = Tokenizer.tokenize_by_grammar(text),
            scanned != by_grammar,
            do: {text, scanned, by_grammar}
      end,
      timeout: 120_000
    )
    |> Enum.flat_map(fn {:ok, different} -> different end)
  end

  defp scanned(texts), do: Enum.count(texts, &match?({:ok, _tokens}, Plain.tokens(&1)))

  describe "the scan of a plain form gives what the grammar gives" do
    test "for four digits, and four bytes that are not" do
      years =
        for year <- 0..9999//37, do: year |> Integer.to_string() |> String.pad_leading(4, "0")

      others = ["202X", "20-6", "T102", "-026", "+026", "2026 ", " 2026", "２０２６"]

      assert scanned(years) == Enum.count(years)
      assert differences(years ++ others) == []
    end

    test "for a year and a month, and a day of it" do
      months = for year <- ~w(0000 2026 9999), month <- @two_digits, do: "#{year}-#{month}"

      dates =
        for year <- ~w(0000 2024 2026),
            month <- @months,
            day <- @days,
            do: "#{year}-#{month}-#{day}"

      assert scanned(months) == 3 * 12
      assert scanned(dates) == 3 * 6 * 9
      assert differences(months ++ dates) == []
    end

    test "for a date and a time of day to the hour and to the minute" do
      to_the_hour = for hour <- @two_digits, do: "2026-06-15T#{hour}"

      to_the_minute =
        for hour <- @hours,
            minute <- @minutes,
            shift <- @shifts,
            do: "2026-06-15T#{hour}:#{minute}#{shift}"

      assert scanned(to_the_hour) == 24
      assert differences(to_the_hour ++ to_the_minute) == []
    end

    test "for a date and a time of day to the second, its fraction and its shift" do
      texts =
        for hour <- ~w(00 23 24),
            minute <- ~w(00 59 60),
            second <- @seconds,
            fraction <- @fractions,
            shift <- @shifts,
            do: "2026-06-15T#{hour}:#{minute}:#{second}#{fraction}#{shift}"

      # Two hours, two minutes, three seconds, five fractions and seven
      # shifts are in their usual ranges.
      assert scanned(texts) == 2 * 2 * 3 * 5 * 7
      assert differences(texts) == []
    end

    test "for a shift of hours and minutes" do
      texts =
        for sign <- ["+", "-"],
            hour <- @two_digits,
            minute <- @minutes,
            do: "2026-06-15T10:30:00#{sign}#{hour}:#{minute}"

      assert differences(texts) == []
    end

    test "for a plain form with a byte of it changed, or something written after it" do
      plain = [
        "2026",
        "2026-06",
        "2026-06-15",
        "2026-06-15T10",
        "2026-06-15T10:30",
        "2026-06-15T10:30:00",
        "2026-06-15T10:30:00.123",
        "2026-06-15T10:30:00Z",
        "2026-06-15T10:30:00.123+02:00"
      ]

      changed =
        for text <- plain,
            at <- 0..(byte_size(text) - 1),
            byte <- ~c"0X?~/-T:+. {",
            do:
              binary_part(text, 0, at) <>
                <<byte>> <> binary_part(text, at + 1, byte_size(text) - at - 1)

      followed =
        for text <- plain,
            after_it <- [
              "?",
              "~",
              "%",
              "/P1D",
              "/2027",
              "[u-ca=hebrew]",
              "[Europe/Paris]",
              "Z",
              "T",
              "-",
              " "
            ],
            do: text <> after_it

      before =
        for text <- plain, before_it <- ["-", "+", "?", "R/", "{", " "], do: before_it <> text

      assert differences(changed ++ followed ++ before) == []
    end

    test "for a plain form before an IXDTF suffix" do
      texts =
        for text <- [
              "2026",
              "2026-06",
              "2026-06-15",
              "2026-06-15T10:30",
              "2026-06-15T10:30:00",
              "2026-06-15T10:30:00Z",
              "2026-06-15T10:30:00.123+02:00",
              "2026-13-15",
              "2026-06-15T10:30:60"
            ],
            suffix <- [
              "[Europe/Paris]",
              "[America/Argentina/Buenos_Aires]",
              "[u-ca=hebrew]",
              "[!u-ca=hebrew]",
              "[Europe/Paris][u-ca=gregory]",
              "[u-ca=hebrew][Europe/Paris]",
              "[+02:00]",
              "[Etc/UTC]",
              "[key=value]",
              "[!key=value]",
              "[Not/AZone]",
              "[u-ca=nosuch]",
              "[]",
              "[Europe/Paris",
              "[Europe/Paris]]",
              "[Europe/Paris]Z",
              "[[Europe/Paris]]"
            ],
            do: text <> suffix

      assert Tokenizer.tokenize("2026-06-15T10:30:00[Europe/Paris]") ==
               Tokenizer.tokenize_by_grammar("2026-06-15T10:30:00[Europe/Paris]")

      assert differences(texts) == []
    end
  end

  describe "every value two digits can write in each field" do
    @describetag :exhaustive
    @describetag timeout: 600_000

    test "of a year, a month and a day" do
      years = for a <- @two_digits, b <- @two_digits, do: a <> b

      dates =
        for year <- ~w(0000 2024 2026),
            month <- @two_digits,
            day <- @two_digits,
            do: "#{year}-#{month}-#{day}"

      assert scanned(years) == 10_000
      assert scanned(dates) == 3 * 12 * 31
      assert differences(years ++ dates) == []
    end

    test "of a time of day and a shift" do
      to_the_minute =
        for hour <- @hours,
            minute <- @two_digits,
            shift <- @shifts,
            do: "2026-06-15T#{hour}:#{minute}#{shift}"

      to_the_second =
        for hour <- @hours,
            minute <- @minutes,
            second <- @seconds,
            fraction <- @fractions,
            shift <- @shifts,
            do: "2026-06-15T#{hour}:#{minute}:#{second}#{fraction}#{shift}"

      shifts =
        for sign <- ["+", "-"],
            hour <- @two_digits,
            minute <- @two_digits,
            do: "2026-06-15T10:30:00#{sign}#{hour}:#{minute}"

      assert differences(to_the_minute ++ to_the_second ++ shifts) == []
    end
  end

  describe "what the scan reads" do
    test "is a value as the grammar reads it" do
      for text <- [
            "2026",
            "2026-06",
            "2026-06-15",
            "2026-06-15T10:30",
            "2026-06-15T10:30:00Z",
            "2026-06-15T10:30:00.123-05:30"
          ] do
        {:ok, {tokens, nil}} = Tokenizer.tokenize(text)

        assert {text, Plain.tokens(text)} == {text, {:ok, tokens}}
      end
    end

    test "leaves a field out of its usual range, and every other form, to the grammar" do
      for text <- [
            "2026-13-15",
            "2026-06-32",
            "2026-06-15T24:00:00",
            "2026-06-15T10:30:60",
            "2026-06-15T10:30:00-00:30",
            "2026-06-15T10:30:00.1234567",
            "2026-06-15T10:30:00+02",
            "20260615",
            "2026Y6M15D",
            "2026-W25-3",
            "2026-06-15/2026-06-20",
            "2026-06-15[u-ca=hebrew]"
          ] do
        assert {text, Plain.tokens(text)} == {text, :general}
      end
    end
  end
end
