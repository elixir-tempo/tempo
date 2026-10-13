defmodule Tempo.Limit do
  @moduledoc """
  The one place every bound on work is set.

  Tempo walks lazily, one value at a time, and converts eagerly, all at
  once; the bounds here say how far either goes before it stops with a
  `Tempo.ConversionError` whose reason is `:too_many_values`, rather than
  running without end.

  """

  @values 10_000

  @doc """
  The most spans an expression is converted to at once, and the most
  members an enumeration yields before it stops.

  ### Examples

      iex> Tempo.Limit.values()
      10000

  """
  @spec values() :: 10_000
  def values, do: @values
end
