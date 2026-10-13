defmodule Tempo.Duration do
  @moduledoc """
  A length of time with no place on the time line: `P1Y2M3DT4H5M6S`.

  A duration is the one companion of `Tempo`: it is not an expression and
  denotes no span, and it is what an interval is formed from once it is
  given a start (`2026-06-01/P1M`) and what a value is shifted by
  (`Tempo.shift`).

  """

  @units [:year, :month, :week, :day, :hour, :minute, :second, :microsecond]

  defstruct units: []

  @typedoc """
  The units of a duration, coarsest first, each a whole number, negative
  for a length in the reverse direction; a part of a second is
  `{microseconds, precision}` as Elixir's types hold one.
  """
  @type units :: [
          {:year | :month | :week | :day | :hour | :minute | :second, integer()}
          | {:microsecond, {integer(), 0..6}}
        ]

  @type t :: %__MODULE__{units: units()}

  @doc "The units a duration is written in, coarsest first."
  @spec units() :: [:year | :month | :week | :day | :hour | :minute | :second | :microsecond, ...]
  def units, do: @units

  @doc """
  Builds a duration from its units.

  ### Arguments

  * `components` is a keyword list of units (`:year`, `:month`, `:week`,
    `:day`, `:hour`, `:minute`, `:second`, `:microsecond`), in any order,
    each a whole number, negative for a length in the reverse direction; a
    `:microsecond` is `{microseconds, precision}`.

  ### Returns

  * `{:ok, duration}`, a `t:t/0` with its units ordered coarsest first.

  * `{:error, %ArgumentError{}}` when a key is not a unit of a duration, is
    given twice, or holds what is not a whole number.

  ### Examples

      iex> Tempo.Duration.new(month: 6, year: 1)
      {:ok, ~o"P1Y6M"}

      iex> Tempo.Duration.new(hour: 1, minute: 30)
      {:ok, ~o"PT1H30M"}

      iex> {:error, %ArgumentError{}} = Tempo.Duration.new(fortnight: 1)

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(components) when is_list(components) do
    keys = Keyword.keys(components)

    cond do
      Enum.any?(keys, &(&1 not in @units)) ->
        {:error,
         argument("#{inspect(Enum.reject(keys, &(&1 in @units)))} are not units of a duration")}

      keys != Enum.uniq(keys) ->
        {:error,
         argument("a unit is given once; #{inspect(keys -- Enum.uniq(keys))} are given twice")}

      not Enum.all?(components, &whole?/1) ->
        {:error,
         argument(
           "a duration's units hold whole numbers, and a microsecond {microseconds, precision}"
         )}

      true ->
        {:ok,
         %__MODULE__{
           units:
             Enum.sort_by(components, fn {unit, _} -> Enum.find_index(@units, &(&1 == unit)) end)
         }}
    end
  end

  def new(other),
    do:
      {:error,
       argument("a duration is built from a keyword list of units, not #{inspect(other)}")}

  @doc """
  Builds a duration as `new/1` does, returning it or raising.

  ### Examples

      iex> Tempo.Duration.new!(day: 1)
      ~o"P1D"

  """
  @spec new!(keyword()) :: t()
  def new!(components) do
    case new(components) do
      {:ok, duration} -> duration
      {:error, exception} -> raise exception
    end
  end

  defp whole?({:microsecond, {microseconds, precision}}),
    do: is_integer(microseconds) and is_integer(precision) and precision in 0..6

  defp whole?({_unit, value}), do: is_integer(value)

  defp argument(message), do: ArgumentError.exception(message)
end
