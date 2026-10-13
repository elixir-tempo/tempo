defmodule Tempo.GoldenTest do
  use ExUnit.Case, async: false

  alias Tempo.Golden

  # The library's answers against the golden files of `test/golden/` (see
  # `plans/architecture-redesign.md`, section 11.1). Runs with
  # `mix test --include golden`. A difference a decision of section 10
  # accounts for is reported, not failed; one no decision accounts for fails.

  @moduletag :golden

  test "the library answers as the golden files record, but for the decisions" do
    differences = Golden.check()
    {decided, undecided} = Enum.split_with(differences, &(&1.decision != nil))

    if decided != [] do
      IO.puts("\n#{length(decided)} golden cells differ by decision:")

      decided
      |> Enum.group_by(& &1.decision)
      |> Enum.each(fn {decision, cells} ->
        IO.puts("  #{decision}: #{length(cells)}")

        for %{was: was, is: is} <- Enum.take(cells, 6) do
          IO.puts("    #{was.input}  was #{inspect(was.out)}  is #{inspect(is.out)}")
        end
      end)
    end

    assert undecided == [], described(undecided)
  end

  defp described([]), do: ""

  defp described(differences) do
    shown =
      differences
      |> Enum.take(40)
      |> Enum.map_join("\n", fn %{was: was, is: is} ->
        "  #{was.input}  was #{inspect(was.out)}  is #{inspect(is.out)}"
      end)

    "#{length(differences)} cells differ with no decision to account for them:\n#{shown}"
  end
end
