defmodule Tempo.Allen.Classifier do
  @moduledoc false

  # The relation of two spans from four comparisons: start against start, end
  # against end, the first's end against the second's start, the first's start
  # against the second's end. Apart from `Tempo.Allen` so that the composition
  # table there can be derived from it when that module compiles.

  alias Tempo.Scale

  @doc false
  @type relation ::
          :precedes
          | :meets
          | :overlaps
          | :finished_by
          | :contains
          | :starts
          | :equals
          | :started_by
          | :during
          | :finishes
          | :overlapped_by
          | :met_by
          | :preceded_by

  @spec relation({Scale.position(), Scale.position()}, {Scale.position(), Scale.position()}) ::
          relation()
  def relation({a_from, a_to}, {b_from, b_to}) do
    classify(
      Scale.compare(a_from, b_from),
      Scale.compare(a_to, b_to),
      Scale.compare(a_to, b_from),
      Scale.compare(a_from, b_to)
    )
  end

  defp classify(_, _, :lt, _), do: :precedes
  defp classify(_, _, :eq, _), do: :meets
  defp classify(_, _, _, :gt), do: :preceded_by
  defp classify(_, _, _, :eq), do: :met_by
  defp classify(:lt, :lt, _, _), do: :overlaps
  defp classify(:lt, :eq, _, _), do: :finished_by
  defp classify(:lt, :gt, _, _), do: :contains
  defp classify(:eq, :lt, _, _), do: :starts
  defp classify(:eq, :eq, _, _), do: :equals
  defp classify(:eq, :gt, _, _), do: :started_by
  defp classify(:gt, :lt, _, _), do: :during
  defp classify(:gt, :eq, _, _), do: :finishes
  defp classify(:gt, :gt, _, _), do: :overlapped_by
end
