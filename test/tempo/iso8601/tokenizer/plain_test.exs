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

  describe "the scan of an interval and of a duration gives what the grammar gives" do
    # Ends in each plain form, with a field at the edge of what it takes and
    # past it, an end left open, an end written short and one in another
    # form.
    @ends [
      "2026",
      "2028",
      "0000",
      "2026-06",
      "2026-13",
      "2026-06-15",
      "2026-06-20",
      "2026-06-32",
      "2026-06-15T09",
      "2026-06-15T24",
      "2026-06-15T09:00",
      "2026-06-15T17:30:00",
      "2026-06-15T17:30:60",
      "2026-06-15T09:00:00Z",
      "2026-06-15T09:00:00.5+02:00",
      "..",
      "20",
      "06-20",
      "T17:00",
      "17:00",
      "2026-W25",
      "2026-166",
      "20260615",
      "2026Y6M15D",
      "P1D",
      "PT1H",
      "P1Y2M3DT4H5M6S",
      "-P1D",
      "P0.5D",
      ""
    ]

    # Each designator of a duration, left out or with one of a few numbers.
    @years ["", "1Y", "10Y", "0Y"]
    @months ["", "2M", "18M"]
    @weeks ["", "3W"]
    @days_designated ["", "4D", "400D", "007D"]
    @hours_designated ["", "5H", "36H"]
    @minutes_designated ["", "6M", "90M"]
    @seconds_designated ["", "7S", "0S"]

    defp spans_scanned(texts), do: Enum.count(texts, &match?({:ok, _tokens}, Plain.span(&1)))

    # Every duration those write, with a `T` before a time of day.
    defp durations do
      for year <- @years,
          month <- @months,
          week <- @weeks,
          day <- @days_designated,
          hour <- @hours_designated,
          minute <- @minutes_designated,
          second <- @seconds_designated do
        time = hour <> minute <> second
        "P" <> year <> month <> week <> day <> if(time == "", do: "", else: "T" <> time)
      end
    end

    test "for an interval of two ends, each in every form" do
      intervals = for from <- @ends, to <- @ends, do: from <> "/" <> to

      # Eleven ends are plain dates and times the scan reads, and each makes
      # an interval with another, with an end left open, with one of three
      # plain durations and with a time of day alone, at either end.
      assert differences(intervals) == []
      assert spans_scanned(intervals) == 11 * 11 + 2 * 11 + 2 * 11 * 3 + 2 * 11
    end

    test "for an interval with a byte of it changed, something about it, or a suffix" do
      plain = [
        "2026/2028",
        "2026-06-15/2026-06-20",
        "2026-06-15T09:00/2026-06-15T17:00",
        "2026-06-15T09:00:00Z/2026-06-15T17:00:00+02:00",
        "2026-06-15/..",
        "../2026-06-15",
        "2026-06-15/P1D",
        "PT36H/2026-06-15T09:00",
        "P1D",
        "PT1H30M",
        "P1Y2M3DT4H5M6S"
      ]

      changed =
        for text <- plain,
            at <- 0..(byte_size(text) - 1),
            byte <- ~c"0X?~/-T:+. {PM,",
            do:
              binary_part(text, 0, at) <>
                <<byte>> <> binary_part(text, at + 1, byte_size(text) - at - 1)

      about =
        for text <- plain,
            {before_it, after_it} <- [
              {"R/", ""},
              {"R5/", ""},
              {"", "/P1D"},
              {"", "/2030"},
              {"", "/F1KN"},
              {"", "?"},
              {"", "~"},
              {"-", ""},
              {"+", ""},
              {"{", "}"},
              {"", "[Europe/Paris]"},
              {"", "[u-ca=hebrew]"},
              {" ", ""},
              {"", " "},
              {"", "Z"}
            ],
            do: before_it <> text <> after_it

      assert differences(changed ++ about) == []
    end

    test "for a recurrence of an interval, with and without a count" do
      bodies = [
        "2026-06-15/P1D",
        "2026-06-15T09:00/PT1H",
        "2026-06-15/2026-06-20",
        "P1D/2026-06-15",
        "2026-06-15/..",
        "../2026-06-15",
        "../P1D",
        "2026-06-15/20",
        "2026-13-15/P1D",
        "2026-06-15/P1D/F1KN",
        "2026-06-15/PT1.5S"
      ]

      prefixes = [
        "R",
        "R5",
        "R0",
        "R1",
        "R007",
        "R12",
        "R123456789",
        "R1234567890",
        "R-1",
        "R1.5",
        "RR",
        "r",
        "R5 ",
        "5"
      ]

      recurrences = for prefix <- prefixes, body <- bodies, do: prefix <> "/" <> body

      # Seven prefixes are `R` alone or with a whole number of nine digits
      # or fewer, and six bodies are an interval the scan reads.
      assert spans_scanned(recurrences) == 7 * 6
      assert differences(recurrences) == []
    end

    test "for a time of day alone, to the hour, the minute, the second and its shift" do
      to_the_hour = for hour <- @two_digits, do: "T#{hour}"

      to_the_minute =
        for hour <- @hours, minute <- @minutes, shift <- @shifts, do: "T#{hour}:#{minute}#{shift}"

      to_the_second =
        for hour <- ~w(00 23 24),
            minute <- ~w(00 59 60),
            second <- @seconds,
            fraction <- @fractions,
            shift <- @shifts,
            do: "T#{hour}:#{minute}:#{second}#{fraction}#{shift}"

      others =
        for text <- ["T10", "T10:30", "T10:30:00", "T10:30:00Z"],
            {before_it, after_it} <- [
              {"", "[Europe/Paris]"},
              {"", "[u-ca=hebrew]"},
              {"", "/T17:00"},
              {"", "/PT1H"},
              {"", "?"},
              {"2026-06-15/", ""},
              {"-", ""},
              {" ", ""},
              {"", " "},
              {"T", ""},
              {"t", ""}
            ],
            do: before_it <> text <> after_it

      assert scanned(to_the_hour) == 24
      assert differences(to_the_hour ++ to_the_minute ++ to_the_second ++ others) == []
    end

    test "for a duration of whole numbers, each designator written or left out" do
      durations = durations()

      # Every one that holds a unit is scanned: the year, the month, the
      # week and the day each in four, three, two and four ways, and the
      # hour, the minute and the second in three each, less the one with
      # none of them.
      assert Enum.count(durations) == 4 * 3 * 2 * 4 * 3 * 3 * 3
      assert spans_scanned(durations) == Enum.count(durations) - 1
      assert differences(durations) == []
    end

    test "for a duration in another order, with a sign, a fraction or a number too long" do
      others = [
        "P",
        "PT",
        "P1DT",
        "P1M1Y",
        "P1D1W",
        "PT1M1H",
        "PT1S1M",
        "P1H",
        "PT1D",
        "P1Y1Y",
        "-P1D",
        "+P1D",
        "P-1D",
        "PT1.5S",
        "P0.5D",
        "P1,5D",
        "P1234567890D",
        "P123456789D",
        "PT123456789S",
        "P0D",
        "PT0S",
        "P00D",
        "p1d",
        "P1d",
        "P1D ",
        " P1D",
        "P1D/",
        "/P1D",
        "P1D/P2D",
        "P1D/..",
        "../P1D",
        "../..",
        "P2026-01-10T22:33:55",
        "P1W",
        "P1Y2W",
        "P1W2D",
        "P1WT1H"
      ]

      assert differences(others) == []
    end

    test "is the tokens the grammar gives, for the forms events and steps are written in" do
      assert Plain.span("2026-06-15/2026-06-20") ==
               {:ok,
                [
                  interval: [
                    date: [year: 2026, month: 6, day: 15],
                    date: [year: 2026, month: 6, day: 20]
                  ]
                ]}

      assert Plain.span("2026-06-15T09:00/..") ==
               {:ok,
                [
                  interval: [
                    {:datetime, [year: 2026, month: 6, day: 15, hour: 9, minute: 0]},
                    :undefined
                  ]
                ]}

      assert Plain.span("PT1H30M") == {:ok, [duration: [hour: 1, minute: 30]]}

      assert Plain.span("P1Y2M3DT4H5M6S") ==
               {:ok, [duration: [year: 1, month: 2, day: 3, hour: 4, minute: 5, second: 6]]}

      assert Plain.span("R5/2026-06-15/P1D") ==
               {:ok,
                [
                  interval: [
                    recurrence: 5,
                    date: [year: 2026, month: 6, day: 15],
                    duration: [day: 1]
                  ]
                ]}

      for text <- [
            "2026-06-15",
            "R/2026-06-15/P1D/F1KN",
            "2026-06-15/20",
            "PT1.5S",
            "-P1D",
            "P1D/P2D"
          ] do
        assert {text, Plain.span(text)} == {text, :general}
      end
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
