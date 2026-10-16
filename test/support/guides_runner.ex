defmodule Tempo.GuidesRunner do
  @moduledoc false
  # Runs the Elixir in one guide, as a reader working down the page would:
  # bindings carry from block to block. See `Tempo.GuidesTest`.

  alias ExUnit.CaptureIO
  alias Tempo.Clock.Test, as: TestClock
  alias Tempo.GuidesCalls

  @doc "Every example of a guide that raises, or answers other than the guide says."
  @spec failures(Path.t()) :: [String.t()]
  def failures(path) do
    blocks = path |> File.read!() |> String.split("\n") |> blocks()
    preamble = preamble(blocks)

    {_binding, failures} =
      blocks
      |> Enum.reject(& &1.skip)
      |> Enum.reduce({[], []}, fn block, acc -> run(kind(block), block, acc, preamble) end)

    Enum.reverse(failures)
  end

  # The instant the clock is pinned at while a guide's calls are recorded,
  # so that what reads the clock answers the same on every run.
  @pinned ~U[2026-06-15 12:00:00Z]

  @doc """
  The calls a guide's examples make into Tempo, `Enum` and `Stream`, each
  with the example it is made in and what it answered, run with the clock
  pinned. An example the page has raise is not run.
  """
  @spec calls(Path.t()) :: [map()]
  def calls(path) do
    blocks = path |> File.read!() |> String.split("\n") |> blocks()
    preamble = preamble(blocks)
    :ok = TestClock.put(@pinned)

    {_binding, calls, _count} =
      blocks
      |> Enum.reject(& &1.skip)
      |> Enum.reduce({[], [], 0}, fn block, acc -> recorded(kind(block), block, acc, preamble) end)

    TestClock.reset()
    Enum.reverse(calls)
  end

  defp recorded(:illustration, _block, acc, _preamble) do
    acc
  end

  defp recorded(:plain, %{lines: lines}, acc, preamble) do
    recorded_example(Enum.join(lines, "\n"), acc, preamble)
  end

  defp recorded(:iex, %{lines: lines}, acc, preamble) do
    lines
    |> examples()
    |> Enum.reject(&String.starts_with?(&1.expected, "** ("))
    |> Enum.reduce(acc, &recorded_example(&1.code, &2, preamble))
  end

  defp recorded_example(code, {binding, calls, count}, preamble) do
    {_result, binding, made} = GuidesCalls.eval(code, binding, preamble)
    example = count + 1
    made = Enum.map(made, &Map.merge(%{example: example, code: code}, call_of(&1)))
    {binding, Enum.reverse(made) ++ calls, example}
  end

  defp call_of({module, function, arguments, answer}) do
    %{module: module, function: function, arguments: arguments, answer: answer}
  end

  # Each `import` and `alias` a guide writes is in force for every block
  # after it, as it is for a reader in iex.
  defp preamble(blocks) do
    blocks
    |> Enum.flat_map(& &1.lines)
    |> Enum.map(&(&1 |> String.trim() |> String.replace_prefix("iex> ", "")))
    |> Enum.filter(&String.starts_with?(&1, ["import ", "alias "]))
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  # ── Blocks ────────────────────────────────────────────────────────────

  defp blocks(lines), do: collect(lines, [], nil, %{skip: false, run: false})

  defp collect([], blocks, _open, _markers), do: Enum.reverse(blocks)

  defp collect([line | rest], blocks, nil, markers) do
    case String.trim(line) do
      "<!-- guides:skip -->" -> collect(rest, blocks, nil, %{markers | skip: true})
      "<!-- guides:run -->" -> collect(rest, blocks, nil, %{markers | run: true})
      "```elixir" -> collect(rest, blocks, [], markers)
      "" -> collect(rest, blocks, nil, markers)
      _prose -> collect(rest, blocks, nil, %{skip: false, run: false})
    end
  end

  defp collect([line | rest], blocks, open, markers) do
    if String.trim(line) == "```" do
      block = Map.put(markers, :lines, Enum.reverse(open))
      collect(rest, [block | blocks], nil, %{skip: false, run: false})
    else
      collect(rest, blocks, [line | open], markers)
    end
  end

  defp kind(%{lines: lines, run: run}) do
    cond do
      Enum.any?(lines, &iex?/1) -> :iex
      run or Enum.any?(lines, &String.contains?(&1, "#=>")) -> :plain
      true -> :illustration
    end
  end

  defp iex?(line), do: String.starts_with?(String.trim_leading(line), "iex>")

  # ── Running ───────────────────────────────────────────────────────────

  defp run(:illustration, _block, acc, _preamble), do: acc

  defp run(:plain, %{lines: lines}, {binding, failures}, preamble) do
    code = Enum.join(lines, "\n")

    case eval(code, binding, preamble) do
      {:ok, _result, binding} -> {binding, failures}
      {:raised, message} -> {binding, [failure(code, "raised: " <> message) | failures]}
    end
  end

  defp run(:iex, %{lines: lines}, acc, preamble) do
    lines |> examples() |> Enum.reduce(acc, &example(&1, &2, preamble))
  end

  defp example(%{code: code, expected: expected}, {binding, failures}, preamble) do
    case {eval(code, binding, preamble), String.starts_with?(expected, "** (")} do
      {{:ok, result, binding}, false} ->
        {binding, answered(code, expected, result, failures)}

      {{:ok, _result, binding}, true} ->
        {binding, [failure(code, "expected to raise, and did not") | failures]}

      {{:raised, _message}, true} ->
        {binding, failures}

      {{:raised, message}, false} ->
        {binding, [failure(code, "raised: " <> message) | failures]}
    end
  end

  defp answered(_code, "", _result, failures), do: failures

  defp answered(code, expected, result, failures) do
    got = inspect(result, limit: :infinity, printable_limit: :infinity)

    if squeezed(got) == squeezed(expected),
      do: failures,
      else: [failure(code, "expected #{expected}\n      got #{got}") | failures]
  end

  defp squeezed(text), do: String.replace(text, ~r/\s+/, "")

  defp failure(code, what), do: "    " <> String.replace(code, "\n", "\n    ") <> "\n  " <> what

  # An example is its `iex>` and `...>` lines, and the expected lines that
  # follow them at once, to the first blank line or comment.
  defp examples(lines) do
    {done, current, _open?} =
      Enum.reduce(lines, {[], nil, false}, fn line, {done, current, open?} ->
        trimmed = String.trim_leading(line)

        cond do
          String.starts_with?(trimmed, "iex>") ->
            {pushed(done, current), %{code: stripped(trimmed, "iex>"), expected: ""}, true}

          String.starts_with?(trimmed, "...>") and current != nil ->
            {done, %{current | code: current.code <> "\n" <> stripped(trimmed, "...>")}, true}

          current == nil or not open? ->
            {done, current, open?}

          trimmed == "" or String.starts_with?(trimmed, "#") ->
            {done, current, false}

          true ->
            expected = Regex.replace(~r/\s+#\s.*$/, trimmed, "")
            {done, %{current | expected: String.trim(current.expected <> "\n" <> expected)}, true}
        end
      end)

    Enum.reverse(pushed(done, current))
  end

  defp pushed(done, nil), do: done
  defp pushed(done, current), do: [current | done]

  defp stripped(line, prefix),
    do: line |> String.replace_prefix(prefix, "") |> String.trim_leading()

  # A guide's code runs as a reader's would; a raise is an answer to report.
  defp eval(code, binding, preamble) do
    {{result, binding}, _output} =
      CaptureIO.with_io(fn ->
        Code.eval_string("import Tempo.Sigils\n" <> preamble <> "\n" <> code, binding)
      end)

    {:ok, result, binding}
  rescue
    exception -> {:raised, Exception.message(exception)}
  catch
    kind, value -> {:raised, inspect({kind, value})}
  end
end
