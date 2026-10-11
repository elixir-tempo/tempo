defmodule Tempo.BorderTest do
  use ExUnit.Case, async: true

  # The border replaces `Calendar.ISO` by the module Tempo works with, and
  # back, wherever a term holds it. It reads a value by the fields that can
  # hold a calendar and no others, so every shape of value is held here to
  # what a reading of the whole term finds: nothing of the one calendar
  # left on the way in, nothing of the other on the way out, and the value
  # as it was.

  import Tempo.Sigils

  alias Tempo.Border
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.Matrix.Corpus
  alias Tempo.Network
  alias Tempo.RRule

  # Whether a term holds a module anywhere in it, read whole: every element
  # of a list and of a tuple, every key and value of a map and of a struct.
  # A stream is what a value keeps to give later, and is not read.
  defp holds?(module, module), do: true
  defp holds?(%Stream{}, _module), do: false
  defp holds?([head | tail], module), do: holds?(head, module) or holds?(tail, module)
  defp holds?(term, module) when is_tuple(term), do: holds?(Tuple.to_list(term), module)
  defp holds?(term, module) when is_map(term), do: holds?(Map.to_list(term), module)
  defp holds?(_term, _module), do: false

  # What is wrong with a term's crossing, if anything.
  defp crossing(term) do
    entered = Border.enter(term)
    left = Border.leave(entered)

    cond do
      holds?(entered, Border.outside()) -> :the_outside_calendar_is_left_inside
      holds?(left, Border.inside()) -> :the_inside_calendar_is_left_outside
      left != term -> :the_term_is_not_as_it_was
      true -> :ok
    end
  end

  defp wrong(terms) do
    for {name, term} <- terms, crossing(term) != :ok, do: {name, crossing(term)}
  end

  describe "a value of every shape crosses whole" do
    test "each value of the corpus, and the interval it converts to" do
      values =
        for entry <- Corpus.entries(), {:ok, value} <- [Corpus.read(entry)] do
          {entry.text, value}
        end

      intervals =
        for {text, value} <- values, {:ok, interval} <- [Tempo.to_interval(value)] do
          {text <> " as an interval", interval}
        end

      assert Enum.count(values) > 500
      assert Enum.any?(values, fn {_text, value} -> holds?(value, Border.outside()) end)
      assert wrong(values) == []
      assert wrong(intervals) == []
    end

    test "a selection that holds an interval, in a value's units" do
      value = Tempo.from_iso8601!("XXX{0,2,4,6,8}Y11MLLL1K1IN/P9DN2K1IN")
      [selection: selection] = Keyword.take(value.time, [:selection])

      assert %Interval{from: %Tempo{calendar: Calendar.ISO}} = selection[:interval]
      assert crossing(value) == :ok
    end

    test "a value of another calendar, whose metadata holds a date" do
      {:ok, hebrew} = Tempo.from_iso8601("5786-06-15[u-ca=hebrew]")
      value = Tempo.put_metadata(hebrew, %{due: ~D[2026-06-15], calendar: Calendar.ISO})

      assert crossing(value) == :ok
      assert Border.enter(value).metadata.due.calendar == Border.inside()
      assert Border.enter(hebrew) == hebrew
    end

    test "an interval, a set, a rule and a network" do
      {:ok, rule} = RRule.parse("FREQ=WEEKLY;BYDAY=MO,WE;BYHOUR=9", from: ~o"2026-06-01")
      {:ok, set} = Tempo.union(~o"2026-01", ~o"2026-03")
      {:ok, weekends} = Tempo.select(~o"2026-06-15/..", Tempo.weekends(:US))

      network =
        Network.new()
        |> Network.add_period(:a, from: ~o"2026-01-01", duration: ~o"P1Y")
        |> Network.add_period(:b, duration: ~o"P1M")

      tagged =
        Interval.new!(
          from: ~o"2026-06-15",
          to: ~o"2026-06-20",
          metadata: %{on: ~D[2026-06-15]}
        )

      assert wrong(rule: rule, set: set, weekends: weekends, network: network, tagged: tagged) ==
               []
    end

    test "Elixir's dates and times, and plain terms that hold a calendar" do
      {:ok, zoned} = DateTime.new(~D[2026-06-15], ~T[09:30:00], "Etc/UTC")

      terms = [
        date: ~D[2026-06-15],
        time: ~T[09:30:00],
        naive: ~N[2026-06-15 09:30:00],
        zoned: zoned,
        range: Date.range(~D[2026-06-15], ~D[2026-06-20]),
        module: Calendar.ISO,
        options: [calendar: Calendar.ISO, within: ~o"2026"],
        answer: {:ok, [~o"2026-06-15", ~D[2026-06-15]]},
        map: %{Calendar.ISO => [~o"2026"], given: %{at: ~D[2026-06-15]}},
        duration: ~o"P1Y2M",
        nothing: nil
      ]

      assert wrong(terms) == []
    end

    test "a value written by hand with no calendar is read as Calendar.ISO" do
      by_hand = %Tempo{time: [year: 2026, month: 6, day: 15], calendar: nil}

      assert Border.enter(by_hand).calendar == Border.inside()
      assert Border.leave(Border.enter(by_hand)) == ~o"2026-06-15"
    end
  end

  describe "a message says of a term what a caller holds" do
    test "an argument of the wrong kind is echoed as it was given" do
      date = ~D[2026-06-15]

      messages = [
        message_of(Tempo.metadata(date)),
        message_of(Tempo.duration(date)),
        message_of(Tempo.select(date, ~o"1D")),
        message_of(Tempo.select(~o"2026", date)),
        message_of(Interval.new(from: date, to: ~o"2026")),
        message_of(Tempo.to_string(date)),
        message_of(Tempo.new({:calendar, Calendar.ISO})),
        message_of(Tempo.shift(~o"2026-06-15", calendar: Calendar.ISO))
      ]

      for message <- messages do
        refute message =~ "Localize"
        assert message =~ "~D[2026-06-15]" or message =~ "Calendar.ISO"
      end
    end

    # A message is written inside Tempo, of what Tempo holds, so every one
    # is written with `Tempo.Border.inspect/2`, which writes a term as the
    # caller holds it. The modules that write a value's own text define an
    # `inspect/1` of their own, and the border is where the plain one is
    # called.
    test "no module of the library calls the plain inspect/2" do
      own_writers = ["lib/tempo/border.ex", "lib/inspect.ex", "lib/protocol/inspect.ex"]

      plain =
        for path <- Path.wildcard("lib/**/*.ex"),
            path not in own_writers,
            {line, number} <- path |> File.read!() |> code_lines(),
            Regex.match?(~r/(?<![.\w])inspect\(|&inspect\//, line),
            do: "#{path}:#{number}"

      assert plain == []
    end
  end

  defp message_of({:error, exception}) when is_exception(exception),
    do: Exception.message(exception)

  # The lines of a source file that are code: no comment, and no line of a
  # `@doc`, a `@moduledoc` or a `@typedoc`.
  defp code_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, &code_line/2)
    |> elem(0)
  end

  defp code_line({line, number}, {lines, in_doc?}) do
    trimmed = String.trim(line)

    cond do
      in_doc? -> {lines, trimmed != ~s(""")}
      Regex.match?(~r/^@(doc|moduledoc|typedoc)\s+(~[sS])?"""/, trimmed) -> {lines, true}
      String.starts_with?(trimmed, "#") -> {lines, false}
      true -> {[{line, number} | lines], false}
    end
  end

  describe "an exception holds its values as a caller holds them" do
    test "from where it is built" do
      inside = Border.enter(~o"2026-06-15")

      error = ConversionError.exception(value: inside, target: Border.inside())

      refute holds?(error, Border.inside())
      assert error.value == ~o"2026-06-15"
      assert error.target == Calendar.ISO
    end

    test "and names a calendar as a caller knows it" do
      {:error, error} = Tempo.select(~o"2026[u-ca=gregory]", ~o"25W")

      assert Exception.message(error) =~ "written in Calendar.ISO"
      refute Exception.message(error) =~ "Localize"
    end
  end
end
