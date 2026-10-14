unless Code.ensure_loaded?(Kino.DataTable) do
  defmodule Kino.DataTable do
    @moduledoc false
    # Livebook's own package is not a dependency: a table is given its rows.
    def new(rows, _options \\ []), do: Enum.to_list(rows)
  end
end

defmodule Tempo.LivebooksRunner do
  @moduledoc false
  # Runs a livebook's Elixir cells in order, as Livebook runs them: bindings,
  # imports and aliases carry from cell to cell. The setup cell, which
  # installs the packages, is not run; its imports and aliases are.

  @doc "The cells of a livebook that raise, each with its first line and the error."
  @spec failures(Path.t()) :: [String.t()]
  def failures(path) do
    cells = cells(path)
    env = setup(Enum.find(cells, "", &setup?/1))

    {failures, _binding, _env} =
      cells
      |> Enum.reject(&setup?/1)
      |> Enum.with_index(1)
      |> Enum.reduce({[], [], env}, &run/2)

    Enum.reverse(failures)
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
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> Enum.map(&hd/1)
  end

  defp setup?(cell), do: String.contains?(cell, "Mix.install")

  defp setup(cell) do
    imports =
      ~r/^\s*(import|alias) [^\n]+/m
      |> Regex.scan(cell)
      |> Enum.map_join("\n", &hd/1)

    {_value, _binding, env} =
      Code.eval_quoted_with_env(
        Code.string_to_quoted!(imports <> "\n:ok"),
        [],
        Code.env_for_eval([])
      )

    env
  end

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
  an earlier Tempo (the September 2026 talk, on 1.6.3) is a record of that
  version and is not run.

  Runs with the guides: `mix test --only guides`.
  """
  use ExUnit.Case, async: false

  alias Tempo.LivebooksRunner

  @moduletag :guides

  for livebook <- Path.wildcard("livebook/*.livemd"),
      LivebooksRunner.for_this_version?(livebook) do
    test "the cells of #{livebook} run" do
      assert LivebooksRunner.failures(unquote(livebook)) == []
    end
  end
end
