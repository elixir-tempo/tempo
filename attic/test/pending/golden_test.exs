defmodule Tempo.GoldenTest do
  use ExUnit.Case, async: false

  alias Tempo.Golden

  # The library's answers against the golden files of `test/golden/` (see
  # `plans/architecture-redesign.md`, section 11.1). Runs with
  # `mix test --include golden`; `GOLDEN=write` rewrites the files first.

  @moduletag :golden

  setup_all do
    level = Logger.level()
    Logger.configure(level: :none)

    if System.get_env("GOLDEN") == "write" do
      Golden.write()
    end

    on_exit(fn -> Logger.configure(level: level) end)
    :ok
  end

  test "the library answers as the golden files record" do
    differences = Golden.check()

    assert differences == [], described(differences)
  end

  defp described([]), do: ""

  defp described([first | _] = differences) do
    "#{length(differences)} cells differ; the first: #{inspect(first, pretty: true)}"
  end
end
