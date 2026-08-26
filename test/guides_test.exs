defmodule Tempo.GuidesRunner do
  @moduledoc false
  # Extracts and executes the Elixir in a single guide. See
  # `Tempo.GuidesTest` for the contract.

  import ExUnit.Assertions

  alias ExUnit.CaptureIO

  @doc "Run every executable code block in `path`, raising with context on the first failure."
  def check!(path) do
    all_blocks = path |> File.read!() |> blocks()

    # `Code.eval_string/3` threads bindings but not aliases/imports, while
    # guides alias a module once (`alias Tempo.Network`) and use the short
    # name down the page. Re-establish every guide `import`/`alias` on each
    # eval so a later block sees names an earlier block introduced.
    Process.put(:guides_preamble, preamble(all_blocks))

    _final_binding =
      all_blocks
      |> Enum.reject(& &1.skip)
      |> Enum.map(&classify/1)
      |> Enum.reduce([], fn block, binding -> run(block, binding, path) end)

    :ok
  end

  defp preamble(blocks) do
    blocks
    |> Enum.flat_map(& &1.lines)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.starts_with?(&1, "import ") or String.starts_with?(&1, "alias ")))
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  # --- Fenced-block extraction, tracking preceding `guides:skip` / `guides:run` markers ---

  defp blocks(content) do
    content
    |> String.split("\n")
    |> collect([], :outside, [], %{skip: false, run: false})
  end

  defp collect([], acc, _state, _current, _markers), do: Enum.reverse(acc)

  defp collect([line | rest], acc, :outside, _current, markers) do
    case String.trim(line) do
      "<!-- guides:skip -->" -> collect(rest, acc, :outside, [], %{markers | skip: true})
      "<!-- guides:run -->" -> collect(rest, acc, :outside, [], %{markers | run: true})
      "```elixir" -> collect(rest, acc, :inside, [], markers)
      "" -> collect(rest, acc, :outside, [], markers)
      _ -> collect(rest, acc, :outside, [], %{skip: false, run: false})
    end
  end

  defp collect([line | rest], acc, :inside, current, markers) do
    if String.trim(line) == "```" do
      block = %{lines: Enum.reverse(current), skip: markers.skip, run: markers.run}
      collect(rest, [block | acc], :outside, [], %{skip: false, run: false})
    else
      collect(rest, acc, :inside, [line | current], markers)
    end
  end

  # --- Classification: iex-doctest, plain runnable, or prose illustration ---

  defp classify(%{lines: lines} = block) do
    kind =
      cond do
        Enum.any?(lines, &iex_line?/1) -> :iex
        Enum.any?(lines, &String.contains?(&1, "#=>")) -> :plain
        block.run -> :plain
        true -> :illustration
      end

    Map.put(block, :kind, kind)
  end

  defp iex_line?(line), do: String.starts_with?(String.trim_leading(line), "iex>")

  # --- Running ---

  # No result markers and not force-run: prose illustration, skipped.
  defp run(%{kind: :illustration}, binding, _path), do: binding

  defp run(%{kind: :plain, lines: lines}, binding, path) do
    {_result, binding} = eval(Enum.join(lines, "\n"), binding, path)
    binding
  end

  defp run(%{kind: :iex, lines: lines}, binding, path) do
    lines
    |> examples()
    |> Enum.reduce(binding, fn example, binding -> run_example(example, binding, path) end)
  end

  defp run_example(%{code: code, raises: true}, binding, path) do
    assert_raises(code, binding, path)
    binding
  end

  defp run_example(%{code: code}, binding, path) do
    {_result, binding} = eval(code, binding, path)
    binding
  end

  # --- `iex>` / `...>` example parsing ---

  defp examples(lines) do
    lines
    |> Enum.reduce([], &parse_line/2)
    |> Enum.reverse()
    |> Enum.map(&flag_raises/1)
  end

  defp parse_line(line, examples) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, "iex>") ->
        [%{code: strip(trimmed, "iex>"), expected: ""} | examples]

      String.starts_with?(trimmed, "...>") ->
        append_code(examples, strip(trimmed, "...>"))

      examples == [] ->
        examples

      true ->
        append_expected(examples, line)
    end
  end

  defp append_code([current | rest], code),
    do: [%{current | code: current.code <> "\n" <> code} | rest]

  defp append_code([], _code), do: []

  defp append_expected([current | rest], line),
    do: [%{current | expected: current.expected <> line <> "\n"} | rest]

  defp append_expected([], _line), do: []

  defp flag_raises(%{expected: expected} = example) do
    Map.put(example, :raises, String.starts_with?(String.trim_leading(expected), "** ("))
  end

  defp strip(line, prefix), do: line |> String.replace_prefix(prefix, "") |> String.trim_leading()

  # --- Evaluation: bindings thread through, stdout suppressed, failures annotated ---

  defp wrap(code) do
    "import Tempo.Sigils\n" <> Process.get(:guides_preamble, "") <> "\n" <> code
  end

  defp eval(code, binding, path) do
    {result, _output} =
      CaptureIO.with_io(fn ->
        Code.eval_string(wrap(code), binding, file: path)
      end)

    result
  rescue
    error ->
      reraise "Guide code failed in #{path}:\n\n" <>
                indent(code) <>
                "\n\n" <>
                Exception.message(error) <>
                "\n\n(If this block is not meant to run, precede it with `<!-- guides:skip -->`.)",
              __STACKTRACE__
  end

  defp assert_raises(code, binding, path) do
    raised? =
      try do
        eval_quietly(code, binding, path)
        false
      rescue
        _exception -> true
      catch
        _kind, _value -> true
      end

    assert raised?,
           "Expected this guide example to raise, but it succeeded:\n\n" <> indent(code)
  end

  # Like `eval/3` but without the annotating rescue, so the caller can
  # inspect the raise (used only where a raise is the expected outcome).
  defp eval_quietly(code, binding, path) do
    {result, _output} =
      CaptureIO.with_io(fn ->
        Code.eval_string(wrap(code), binding, file: path)
      end)

    result
  end

  defp indent(code), do: "    " <> String.replace(code, "\n", "\n    ")
end

defmodule Tempo.GuidesTest do
  @moduledoc """
  Executes the Elixir in every `guides/*.md` file, so an example the
  guides present as working cannot silently rot — as a `Tempo.select/2`
  example did once the value became a span and `Tempo.month/1` began to
  raise on it.

  This is deliberately **not** a doctest. It asserts that the code runs
  (and that an example whose expected output begins with `** (` still
  raises), not that inspect output matches to the character — so ordinary
  formatting drift never creates churn, while genuinely broken code is
  caught. Recognised inside ` ```elixir ` fences:

    * `iex>` / `...>` — each example runs; a `** (...)` one must raise.
    * blocks with `#=>` result comments — run whole, must not raise.

  Bindings accumulate down each guide, mirroring a reader working the
  page top to bottom. Two HTML-comment markers steer a block that the
  heuristic gets wrong:

    * `<!-- guides:skip -->` before a fence skips it (pseudo-code, a
      `Mix.install` cell, or a snippet needing a file/module the reader
      supplies).

    * `<!-- guides:run -->` forces a marker-less setup block to run (one
      that binds names used further down but shows no result of its own).

  A block with neither result marker nor `guides:run` is treated as prose
  illustration and skipped.
  """
  use ExUnit.Case, async: false

  alias Tempo.GuidesRunner

  @moduletag :guides

  setup_all do
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    :ok
  end

  for guide <- Path.wildcard("guides/*.md") do
    test "the code in #{Path.relative_to_cwd(guide)} runs" do
      GuidesRunner.check!(unquote(guide))
    end
  end
end
