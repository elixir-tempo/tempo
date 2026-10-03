defmodule Tempo.Matrix.Test do
  use ExUnit.Case, async: false

  alias Tempo.Matrix.Baseline
  alias Tempo.Matrix.Census
  alias Tempo.Matrix.Checks
  alias Tempo.Matrix.Corpus
  alias Tempo.Matrix.Table

  # The matrix of `plans/validated-core.md`: every public operation against
  # every shape of value, and every consistency check on each. A cell that
  # breaks its contract fails the suite unless the baseline lists it, and a
  # listed cell that passes fails it too, so the baseline only shrinks.

  # The matrix runs once for the module. A cell that raises ends its process,
  # which the runtime logs: thousands of such reports say nothing the
  # outcomes do not.
  setup_all do
    level = Logger.level()
    Logger.configure(level: :none)
    cells = Census.run()
    Logger.configure(level: level)

    if System.get_env("MATRIX_BASELINE") == "write", do: Baseline.write(Census.failures(cells))

    %{cells: cells}
  end

  test "every text of the corpus is read" do
    assert Census.unread() == []
  end

  test "every operation on every value returns a value or a named error", %{cells: cells} do
    failures = cells |> Enum.reject(&(&1.group == :consistent)) |> Census.failures()
    listed = Enum.reject(Baseline.read(), &check?/1)

    assert %{new: [], fixed: []} = Baseline.compare(failures, listed), report(failures, listed)
  end

  test "every operation agrees with what to_interval/2 covers", %{cells: cells} do
    failures = cells |> Enum.filter(&(&1.group == :consistent)) |> Census.failures()
    listed = Enum.filter(Baseline.read(), &check?/1)

    assert %{new: [], fixed: []} = Baseline.compare(failures, listed), report(failures, listed)
  end

  test "the checks check: most cells of each are an answer and not a skip", %{cells: cells} do
    checked = Enum.filter(cells, &(&1.group == :consistent))

    assert Enum.count(checked, &(&1.outcome == :consistent)) > div(length(checked), 2)
  end

  # A class's level is a claim the corpus makes, and the published table
  # groups its rows by it: an extended shape's meaning is defined, so each of
  # its values converts and walks, and an open one has a value that does not.
  test "the levels are what they say", %{cells: cells} do
    refused =
      for %{operation: operation, outcome: outcome} = cell <- cells,
          operation in ["to_interval/1", "Enum.take/2"],
          outcome not in [:ok, :value],
          uniq: true,
          do: {cell.level, cell.class}

    classes = Corpus.written() |> Enum.map(&{&1.level, &1.class}) |> Enum.uniq()

    assert for({:extended, class} <- refused, do: class) == []
    assert for({:open, class} = open <- classes, open not in refused, do: class) == []
  end

  # The table `guides/operation-matrix.md` publishes is generated from this
  # run, so the guide cannot say what the code does not do. When an operation
  # starts to answer, or is added, rewrite it:
  # MATRIX_GUIDE=write mix test test/tempo/matrix_test.exs
  @guide "guides/operation-matrix.md"

  test "the published table is what the matrix gives", %{cells: cells} do
    table = Table.render(cells)

    if System.get_env("MATRIX_GUIDE") == "write",
      do: File.write!(@guide, Table.replace(File.read!(@guide), table))

    assert Table.published(File.read!(@guide)) == table,
           "#{@guide} is not what the matrix gives. Rewrite it with " <>
             "MATRIX_GUIDE=write mix test test/tempo/matrix_test.exs"
  end

  test "the guide says what each error the table names means", %{cells: cells} do
    guide = File.read!(@guide)
    [_table, said] = String.split(guide, "## The errors", parts: 2)

    unexplained =
      cells
      |> Table.render()
      |> Table.errors_named()
      |> Enum.reject(&String.contains?(said, "**`#{&1}`**"))

    assert unexplained == []
  end

  # The long run has no baseline: a cell of it that fails is a defect. Its
  # values hold tens of thousands of members (a century of days), which take
  # seconds to write out, so a cell is a hang only after a minute.
  @exhaustive_time_limit 60_000

  @tag :exhaustive
  @tag timeout: :infinity
  test "the exhaustive corpus: every cell keeps its contract and agrees with to_interval/2" do
    level = Logger.level()
    Logger.configure(level: :none)

    failures =
      Corpus.exhaustive()
      |> Census.run(time_limit: @exhaustive_time_limit)
      |> Census.failures()

    Logger.configure(level: level)

    assert failures == [], "#{length(failures)} cells fail:\n#{sample(failures)}"
  end

  # A baseline entry is a consistency cell's when its operation is a check.
  defp check?({operation, _arguments, _outcome}) do
    Enum.any?(Checks.unary() ++ Checks.binary(), fn {name, _check} -> name == operation end)
  end

  defp report(failures, listed) do
    %{new: new, fixed: fixed} = Baseline.compare(failures, listed)

    """
    The matrix and its baseline disagree.

    #{length(new)} cells fail that the baseline does not list:
    #{sample(new)}

    #{length(fixed)} cells the baseline lists no longer fail:
    #{sample(fixed)}

    A new failure is a defect to fix. When cells are fixed, rewrite the
    baseline: MATRIX_BASELINE=write mix test test/tempo/matrix_test.exs
    """
  end

  defp sample(failures) do
    failures
    |> Enum.take(25)
    |> Enum.map_join("\n", fn {operation, arguments, outcome} ->
      "  #{operation} of #{arguments}: #{outcome}"
    end)
  end
end
