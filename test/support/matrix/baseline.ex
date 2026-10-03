defmodule Tempo.Matrix.Baseline do
  @moduledoc """
  The cells of the matrix known to fail, kept in
  `test/support/matrix/baseline.exs`.

  The matrix test fails when a cell fails that is not listed, and when a
  listed cell passes, so the list can only shrink. It is rewritten only on
  purpose, by running the test with `MATRIX_BASELINE=write`.

  """

  @path "test/support/matrix/baseline.exs"

  @type failure :: {operation :: String.t(), arguments :: String.t(), outcome :: String.t()}

  @doc """
  The failures the baseline lists.

  ### Returns

  * A sorted list of `t:failure/0`, empty when there is no baseline file.

  """
  @spec read() :: [failure()]
  def read do
    if File.exists?(@path) do
      {failures, _bindings} = Code.eval_file(@path)
      Enum.sort(failures)
    else
      []
    end
  end

  @doc """
  Writes `failures` as the baseline.

  ### Arguments

  * `failures` is a list of `t:failure/0`.

  ### Returns

  * `:ok`.

  """
  @spec write([failure()]) :: :ok
  def write(failures) do
    lines = failures |> Enum.sort() |> Enum.map_join(",\n", &("  " <> inspect(&1)))

    File.write!(@path, """
    # The cells of the matrix known to fail: the operation, its arguments and
    # what it did. Written by `MATRIX_BASELINE=write mix test
    # test/tempo/matrix_test.exs`, and never by hand. See
    # `plans/validated-core.md`.
    [
    #{lines}
    ]
    """)
  end

  @doc """
  Compares the matrix's failures with the baseline.

  ### Arguments

  * `failures` is the sorted list `Tempo.Matrix.Census.failures/1` gives.

  * `listed` is the part of the baseline to compare them with. The default
    is all of it, `read/0`.

  ### Returns

  * `%{new: failures, fixed: failures}` — the cells that fail and are not
    listed, and the listed cells that no longer fail.

  """
  @spec compare([failure()], [failure()]) :: %{new: [failure()], fixed: [failure()]}
  def compare(failures, listed \\ read()) do
    listed = MapSet.new(listed)
    found = MapSet.new(failures)

    %{
      new: found |> MapSet.difference(listed) |> Enum.sort(),
      fixed: listed |> MapSet.difference(found) |> Enum.sort()
    }
  end
end
