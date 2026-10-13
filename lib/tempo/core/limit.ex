defmodule Tempo.Limit do
  @moduledoc false

  # The one place every bound on work is set.
  #
  # Tempo walks lazily, one value at a time, and converts eagerly, all at
  # once; the bounds here say how far either goes before it stops with a
  # `Tempo.ConversionError` whose reason is `:too_many_values`, rather than
  # running without end. A short text can ask for a great deal:
  # `2026Y{1..12}M{1..28}DT{0..23}H{0..59}M{0..59}S` names 29 million seconds.
  #
  # The bound is 10,000 unless the application sets another:
  #
  #     config :ex_tempo, max_values_at_once: 100_000

  alias Tempo.ConversionError

  @default 10_000

  @doc """
  The most spans an expression is converted to at once, and the most
  members an enumeration yields before it stops.

  ### Examples

      iex> Tempo.Limit.values()
      10000

  """
  @spec values() :: pos_integer()
  def values, do: Application.get_env(:ex_tempo, :max_values_at_once, @default)

  @doc """
  Every value of a sequence, when it has no more than the bound: the list,
  or the error that says there are more. A sequence is never cut short to
  the bound, which would answer for part of what was asked.
  """
  @spec take(Enumerable.t(), term()) :: {:ok, list()} | {:error, Exception.t()}
  def take(enumerable, expression) do
    limit = values()

    case Enum.take(enumerable, limit + 1) do
      taken when length(taken) > limit ->
        {:error, ConversionError.exception(value: expression, reason: :too_many_values)}

      taken ->
        {:ok, taken}
    end
  end
end
