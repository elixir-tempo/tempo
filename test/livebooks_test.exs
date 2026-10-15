unless Code.ensure_loaded?(Kino.DataTable) do
  defmodule Kino.DataTable do
    @moduledoc false
    # Livebook's own package is not a dependency. Like Kino, a table takes
    # columns, or rows that are maps or keyword lists, and refuses others.
    def new(tabular, options \\ [])

    def new(%{} = columns, _options) when not is_struct(columns), do: columns

    def new(tabular, _options) do
      rows = Enum.to_list(tabular)

      if Enum.all?(rows, &row?/1) do
        rows
      else
        raise ArgumentError, "expected valid tabular data, but got: #{inspect(tabular)}"
      end
    end

    defp row?(row) when is_map(row), do: true
    defp row?(row), do: row != [] and Keyword.keyword?(row)
  end
end

defmodule Tempo.LivebooksRunner do
  @moduledoc false
  # Runs a livebook's Elixir cells in order, as Livebook runs them: bindings,
  # imports and aliases carry from cell to cell. The setup cell, which
  # installs the packages, is not run. A block marked `force_markdown` is
  # shown by Livebook, not run, so it is not run here either.

  @doc "The cells of a livebook that raise, each with its first line and the error."
  @spec failures(Path.t()) :: [String.t()]
  def failures(path) do
    {failures, _binding, _env} =
      path
      |> cells()
      |> Enum.reject(&setup?/1)
      |> Enum.with_index(1)
      |> Enum.reduce({[], [], Code.env_for_eval([])}, &run/2)

    Enum.reverse(failures)
  end

  @doc """
  The `import`, `alias` and `require` lines of a livebook's setup cell.

  Livebook compiles a whole cell before running it, so a setup cell cannot
  name a module that its own `Mix.install/2` has yet to fetch.
  """
  @spec setup_directives(Path.t()) :: [String.t()]
  def setup_directives(path) do
    setup = path |> cells() |> Enum.find("", &setup?/1)

    ~r/^\s*(?:import|alias|require) [^\n]+/m
    |> Regex.scan(setup)
    |> Enum.map(&(&1 |> hd() |> String.trim()))
  end

  @doc "Whether a livebook is written for this version: its setup installs a Tempo this version satisfies."
  @spec for_this_version?(Path.t()) :: boolean()
  def for_this_version?(path) do
    case Regex.run(~r/\{:ex_tempo, "([^"]+)"/, File.read!(path)) do
      [_, requirement] -> Version.match?(version(), requirement)
      nil -> true
    end
  end

  defp version,
    do: :ex_tempo |> Application.spec(:vsn) |> to_string() |> String.replace("-dev", "")

  defp cells(path) do
    ~r/(<!-- livebook:\{"force_markdown":true\} -->\s*)?```elixir\n(.*?)```/s
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> Enum.flat_map(&code_cell/1)
  end

  defp code_cell(["", code]), do: [code]
  defp code_cell([_force_markdown, _code]), do: []

  defp setup?(cell), do: String.contains?(cell, "Mix.install")

  defp run({cell, index}, {failures, binding, env}) do
    {_value, binding, env} = Code.eval_quoted_with_env(Code.string_to_quoted!(cell), binding, env)
    {failures, binding, env}
  rescue
    exception -> {[failure(index, cell, exception) | failures], binding, env}
  end

  defp failure(index, cell, exception) do
    first = cell |> String.split("\n") |> Enum.find(&(String.trim(&1) != ""))

    "cell #{index} (#{first}): " <>
      (exception |> Exception.message() |> String.split("\n") |> hd())
  end
end

defmodule Tempo.LivebooksTest do
  @moduledoc """
  Runs the cells of every livebook written for this version, so that a
  livebook the README offers cannot rot. A livebook whose setup installs
  another version of Tempo is not run.

  Runs with the guides: `mix test --only guides`.
  """
  use ExUnit.Case, async: false

  alias Tempo.LivebooksRunner

  @moduletag :guides

  for livebook <- Path.wildcard("livebook/*.livemd"),
      LivebooksRunner.for_this_version?(livebook) do
    test "the setup cell of #{livebook} names no module" do
      assert LivebooksRunner.setup_directives(unquote(livebook)) == []
    end

    test "the cells of #{livebook} run" do
      assert LivebooksRunner.failures(unquote(livebook)) == []
    end
  end
end
