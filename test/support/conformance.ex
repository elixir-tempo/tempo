defmodule Tempo.Conformance do
  @moduledoc false

  # The conformance fixtures under test/fixtures/conformance/: the oracles
  # of test/support exported as JSON, which a port of Tempo runs from its
  # own test suite and Tempo's own tests read here, so that the two cannot
  # drift. `scripts/conformance_fixtures.exs` writes them.

  @dir Path.expand("../fixtures/conformance", __DIR__)

  @doc "A fixture by name, decoded: `fixture(\"allen\")` reads `allen.json`."
  @spec fixture(String.t()) :: map()
  # JSON's null is Elixir's nil, which Erlang's decoder would read as :null.
  def fixture(name) do
    {decoded, :ok, rest} =
      @dir |> Path.join(name <> ".json") |> File.read!() |> :json.decode(:ok, %{null: nil})

    "" = String.trim(rest)
    decoded
  end

  @doc "The path of the fixtures, for a message."
  @spec dir() :: String.t()
  def dir, do: @dir

  @doc """
  What a cell of the matrix answered, as the expressions fixture records
  it: `answer` for a value, an error by its name and reason, a raise by its
  name, or unread for text the grammar refuses.
  """
  @spec kind(map()) :: String.t()
  def kind(%{"ok" => _}), do: "answer"
  def kind(%{"value" => _}), do: "answer"
  def kind(%{"error" => module, "reason" => reason}), do: "error #{module} #{reason}"
  def kind(%{"raised" => module}), do: "raised #{module}"
  def kind(%{"unread" => module}), do: "unread #{module}"
end
