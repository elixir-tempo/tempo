defmodule Tempo.UnboundedSetError do
  @moduledoc """
  Exception raised when an aggregate operation needs every member of
  an interval set whose backend is unbounded (a lazy generator such as
  a selection across an open-ended span with `Tempo.select/2`).

  Unbounded sets support the walking operations — `Enum.take/2`,
  `Tempo.IntervalSet.walk/1`, `covered?/2`, `first/1`, and use as a
  `skipping:` busy set — but any operation whose answer requires the
  whole member list (`to_list/1`, `count/1`, `coalesce/1`, set
  algebra) refuses rather than walking forever. Bound the set first:
  intersect the walk with a finite span, or take the members you need.

  """

  defexception [:operation, :set]

  @type t :: %__MODULE__{
          operation: atom() | String.t() | nil,
          set: Tempo.IntervalSet.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{operation: operation}) do
    "#{operation_phrase(operation)} needs every member of the set, but its backend " <>
      "is unbounded and would walk forever. Take the members you need from " <>
      "`Tempo.IntervalSet.walk/1` (e.g. `Enum.take/2` or `Enum.take_while/2`) " <>
      "and build a bounded set from them."
  end

  defp operation_phrase(nil), do: "The operation"
  defp operation_phrase(operation), do: "`#{operation}`"
end
