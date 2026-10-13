defmodule Tempo.GuidesRunner do
  @moduledoc false
  # Runs the Elixir in one guide, as a reader working down the page would:
  # bindings carry from block to block. See `Tempo.GuidesTest`.

  alias ExUnit.CaptureIO

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

defmodule Tempo.GuidesTest do
  @moduledoc """
  Runs the Elixir in the README and every guide, so that an example the
  documentation presents as working cannot rot: each `iex>` example runs
  and answers what the page says, an example whose answer begins `** (`
  raises, and a block with `#=>` comments runs whole.

  Bindings carry down each page. A block is skipped when
  `<!-- guides:skip -->` is written before it (pseudo-code, a file the
  reader supplies), and a block with no result markers is run when
  `<!-- guides:run -->` is written before it (a setup the blocks after it
  use); any other block with no markers is an illustration and is not run.

  Runs with `mix test --only guides`.
  """
  use ExUnit.Case, async: false

  alias Tempo.GuidesRunner

  @moduletag :guides

  @pages ["README.md" | Path.wildcard("guides/*.md")]

  for page <- @pages do
    test "the code in #{page} runs and answers as written" do
      assert GuidesRunner.failures(unquote(page)) == []
    end
  end
end
