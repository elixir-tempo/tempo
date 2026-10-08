defmodule Tempo.Iso8601.Tokenizer.BoundedWorkTest do
  # It measures time, so it runs alone: beside the suite's other tests, and
  # under `mix test --cover`, a read of milliseconds was once not done in its
  # two seconds.
  use ExUnit.Case, async: false

  # The work the tokenizer does for a text is bounded by the text's length.
  #
  # The grammar is an ordered choice with no memory, so it read a text from
  # the same place once for each alternative that came to that place. A
  # selection inside a selection was read some thirty-five times, and one
  # inside that as many times again: `LLLL` took over a minute to refuse and
  # eight would have taken years. A set inside a set was read three times and
  # a set of whole numbers twice, so six sets one inside the next took from
  # two to six seconds. A long number was read whole by every alternative
  # that reads a number, three quarters of a second for eight thousand
  # digits. And a text the tokenizer refused for its length was then read as
  # a locale's words, which took seconds.
  #
  # A selection and a set of whole numbers are now read once at each place
  # (`Tempo.Iso8601.Tokenizer.Memo`), a member of a set once, and how deep
  # selections go and how long a number is are bounded as the depth of sets
  # was.
  #
  # A slow text is one an attacker sends, so each text here is read in a task
  # that is stopped after `@patience`. The texts of the first two tests took
  # from four seconds to years and take milliseconds, so the bound holds on
  # a loaded machine and still tells the two apart.

  alias Tempo.GeneratedSets
  alias Tempo.Iso8601.Tokenizer
  alias Tempo.Iso8601.Tokenizer.Memo
  alias Tempo.ParseError

  @patience 2_000

  defp read(text, reader \\ &Tempo.from_iso8601/1) do
    task = Task.async(fn -> reader.(text) end)

    case Task.yield(task, @patience) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> :not_read_in_time
    end
  end

  defp reason(text, reader \\ &Tempo.from_iso8601/1) do
    case read(text, reader) do
      {:error, %ParseError{reason: reason}} -> reason
      other -> other
    end
  end

  defp refused_in_time?(text), do: match?({:error, %ParseError{}}, read(text))

  defp nested(opener, depth), do: String.duplicate(opener, depth)

  # A window in a window in a window: the third Friday in the ten days from
  # the first Saturday in the ten days from the second Thursday in the ten
  # days from the second Tuesday. Seven selections deep.
  @windows_three_deep "LLLLLLL2K2IN/P10DN4K2IN/P10DN6K1IN/P10DN5K3IN"

  describe "a selection inside a selection" do
    test "is refused in time where nothing closes it" do
      for text <- [
            "LLLL",
            nested("L", 8),
            nested("L", 16),
            "2026YLLLL",
            "TLLLL",
            "PLLLL",
            "R/LLLL",
            "{LLLL",
            "LLLL1KN/P1DN/P1DN",
            String.duplicate("L1K", 12)
          ] do
        assert {text, refused_in_time?(text)} == {text, true}
      end
    end

    test "is read in time where it is a window" do
      assert {:ok, _three_windows} = read(@windows_three_deep)
      assert {:ok, _election_day} = read("XXX{0,2,4,6,8}Y11MLLL1K1IN/P9DN2K1IN")
    end
  end

  describe "a set inside a set" do
    test "is refused in time where nothing closes it" do
      for text <- [
            "{{{{{{",
            "{{{{{{2026",
            "{{{{{{1,2",
            "{{{{{{2026-06-15T10:00:00Z,",
            "{2026,{2027,{2028,{2029,{2030,{2031",
            "{2026..{2027..{2028..{2029..{2030..{2031",
            "{{{{{{LLLLLL"
          ] do
        assert {text, refused_in_time?(text)} == {text, true}
      end
    end
  end

  describe "the bounds" do
    test "refuse selections more than sixteen deep" do
      refused = "Selection nesting exceeds the depth limit of 16"

      assert reason(nested("L", 17)) == refused
      assert reason(nested("L", 8_000)) == refused
      assert reason(String.duplicate("L1K", 2_600)) == refused

      # Sixteen deep is read by the grammar, which refuses it for what it is.
      refute reason(nested("L", 16)) == refused
    end

    test "count a selection as closed by its N, and by the bracket it is in" do
      # Each selection is closed before the next opens.
      assert {:ok, _set} = read("{" <> String.duplicate("2026YL1K1IN,", 40) <> "2026YL1K1IN}")

      # The `L` of a zone's name opens none.
      in_london = "2026-06-15T10:30[Europe/London]"
      assert {:ok, _set} = read("{" <> String.duplicate(in_london <> ",", 40) <> in_london <> "}")
    end

    test "refuse a number of more than 128 digits" do
      refused = "A number exceeds the limit of 128 digits"

      assert {:ok, _year} = read("Y" <> String.duplicate("7", 128))
      assert {:ok, _second} = read("2026-06-15T10:30:45." <> String.duplicate("1", 128))

      assert reason("Y" <> String.duplicate("7", 129)) == refused
      assert reason("2026-06-15T10:30:45." <> String.duplicate("1", 129)) == refused
      assert reason(String.duplicate("2", 8_000)) == refused
      assert reason(String.duplicate("X", 8_000)) == refused
      assert reason("P" <> String.duplicate("1", 129) <> "D", &Tempo.parse_duration/1) == refused
    end

    test "are every reader's" do
      for reader <- [
            &Tempo.from_iso8601/1,
            &Tempo.parse_date/1,
            &Tempo.parse_time/1,
            &Tempo.parse_datetime/1,
            &Tempo.parse_interval/1
          ] do
        assert {reader, reason(nested("L", 17), reader)} ==
                 {reader, "Selection nesting exceeds the depth limit of 16"}

        assert {reader, reason(nested("{", 7), reader)} ==
                 {reader, "Set/group nesting exceeds the depth limit of 6"}

        assert {reader, reason(String.duplicate("2", 129), reader)} ==
                 {reader, "A number exceeds the limit of 128 digits"}
      end
    end

    # A text too long for the tokenizer was then read as a locale's words.
    test "refuse a text over the length limit as words too" do
      for text <- [String.duplicate("June ", 2_000), String.duplicate("2026-06-15T10:00 ", 600)],
          reader <- [&Tempo.parse/1, &Tempo.parse_date/1, &Tempo.parse_datetime/1] do
        assert {reader, reason(text, reader)} ==
                 {reader, "Input of #{byte_size(text)} bytes exceeds the 8192-byte limit"}
      end
    end
  end

  describe "what is kept of a text while it is read" do
    # With no table started the grammar reads as it did, each place as many
    # times as it is come to, which is the measure.
    @selections [
      "L1KN",
      "L3K4IN/P5D",
      "LL3K4IN/P5DN",
      "LL1K{1,3}IN/P5DN",
      "LLL2K2IN/P10DN4K2IN",
      "2018Y3ML1K1IN",
      "{2018,2019,2020,2021,2022}YL2M29D1IN",
      "L5M7K2IN",
      "L11M4K4INT17HZ-5H",
      "L4M{19..26}D4K1IN",
      "LL4M4D/-P20DN7K-2IN",
      "XXX{0,2,4,6,8}Y11MLLL1K1IN/P9DN2K1IN",
      "2018YL1K1INT10H0M0S",
      "2018YL{1,2,5}KNT10H0M0S",
      "2018Y9ML1K1IN/P5D",
      "2018Y9ML{1,3}K1IN/P5D",
      "R/../P1Y/FLLL(easter)eN/P-3DN5K1IN",
      "2026YL11MLL1K1IN/PT12HN1K1IN",
      "1{2,4}XX",
      "{{2026,2027},2030}",
      "{2026Y{1,3}M,2027Y}",
      "{L1KN,L2KN}",
      "2026Y{1,2}G3MU15DT10H30M45.25S"
    ]

    test "changes nothing that is read, or refused" do
      generated = GeneratedSets.texts() |> Enum.take_every(40) |> Enum.map(& &1.text)
      texts = as_written_and_changed(@selections ++ generated)

      assert Enum.count(texts) > 300
      assert read_differently(texts) == []
    end

    @tag :exhaustive
    @tag timeout: :infinity
    test "changes nothing that is read, or refused, of any generated set" do
      texts = as_written_and_changed(Enum.map(GeneratedSets.texts(), & &1.text))

      assert Enum.count(texts) > 9_000
      assert read_differently(texts) == []
    end
  end

  # Each text as it is written, cut short, and inside one more selection or
  # set, which is as deep as the grammar reads in time with no table.
  defp as_written_and_changed(texts) do
    for text <- texts,
        written <-
          [text, String.slice(text, 0..-2//1), text <> "N", "{" <> text] ++ one_deeper(text),
        uniq: true,
        do: written
  end

  # The texts the grammar reads one way with its table and another without.
  # Each is read in a process of its own, as a text is: the table is the
  # process's.
  defp read_differently(texts) do
    texts
    |> Task.async_stream(
      fn text ->
        kept = Memo.reading(fn -> Tokenizer.iso8601(text) end)
        read_again = Tokenizer.iso8601(text)

        if what_is_read(kept) == what_is_read(read_again),
          do: nil,
          else: {text, what_is_read(kept), what_is_read(read_again)}
      end,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.flat_map(fn
      {:ok, nil} -> []
      {:ok, differing} -> [differing]
    end)
  end

  defp one_deeper(text), do: if(String.contains?(text, "LL"), do: [], else: ["L" <> text])

  # A reading less the line and the offset, which the grammar does not move
  # on by where a place is taken from the table.
  defp what_is_read({status, tokens_or_message, rest, context, _line, _offset}),
    do: {status, tokens_or_message, rest, context}
end
