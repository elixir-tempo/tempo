defmodule Tempo.LeapSeconds do
  @moduledoc """
  The leap seconds the International Earth Rotation and Reference Systems
  Service (IERS) has announced since UTC began in 1972, and which of them an
  expression spans.

  A leap second is inserted as `23:59:60` at the end of the 30th of June or
  the 31st of December UTC. There have been 27, all inserted and none
  removed. Tempo reads no second numbered 60, as Elixir's own types read
  none: a leap second is a fact about a span of time, not a value. `spanned/1`
  lists the ones a span holds, and `Tempo.duration/2` with `leap_seconds:
  true` counts them into its length.

  The list is fixed when Tempo is released. The IERS announces a leap second
  about six months ahead, and the General Conference on Weights and Measures
  resolved in 2022 to stop inserting them by 2035.

  """

  alias Tempo.Calendar, as: Calendars
  alias Tempo.ConversionError
  alias Tempo.Measure
  alias Tempo.Scale

  # Dates at whose end a second was inserted: the second after 23:59:59 UTC
  # was numbered 23:59:60.
  @insertions [
    {1972, 6, 30},
    {1972, 12, 31},
    {1973, 12, 31},
    {1974, 12, 31},
    {1975, 12, 31},
    {1976, 12, 31},
    {1977, 12, 31},
    {1978, 12, 31},
    {1979, 12, 31},
    {1981, 6, 30},
    {1982, 6, 30},
    {1983, 6, 30},
    {1985, 6, 30},
    {1987, 12, 31},
    {1989, 12, 31},
    {1990, 12, 31},
    {1992, 6, 30},
    {1993, 6, 30},
    {1994, 6, 30},
    {1995, 12, 31},
    {1997, 6, 30},
    {1998, 12, 31},
    {2005, 12, 31},
    {2008, 12, 31},
    {2012, 6, 30},
    {2015, 6, 30},
    {2016, 12, 31}
  ]

  # Dates at whose end a second was removed; none has been.
  @removals []

  @day Scale.ticks_per_day()

  @typedoc "A UTC date at whose end a leap second falls."
  @type date :: {year :: integer(), month :: 1..12, day :: 1..31}

  @doc """
  The UTC dates at whose end a leap second was inserted, in order.

  ### Returns

  * A list of `{year, month, day}`.

  ### Examples

      iex> {2016, 12, 31} in Tempo.LeapSeconds.dates()
      true

      iex> length(Tempo.LeapSeconds.dates())
      27

  """
  @spec dates() :: [date()]
  def dates, do: Enum.sort(@insertions)

  @doc """
  The UTC dates at whose end a leap second was removed: the second numbered
  59 left out. None has been, and the list is empty until one is announced.

  ### Returns

  * A list of `{year, month, day}`.

  ### Examples

      iex> Tempo.LeapSeconds.removals()
      []

  """
  @spec removals() :: [date()]
  def removals, do: Enum.sort(@removals)

  @doc """
  Whether a leap second was inserted at the end of a UTC date.

  ### Arguments

  * `year`, `month` and `day` are the integers of a Gregorian date.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.LeapSeconds.on_date?(2016, 12, 31)
      true

      iex> Tempo.LeapSeconds.on_date?(2026, 12, 31)
      false

  """
  @spec on_date?(integer(), integer(), integer()) :: boolean()
  def on_date?(year, month, day), do: {year, month, day} in @insertions

  @doc """
  The most recent UTC date at whose end a leap second was inserted.

  ### Returns

  * `{year, month, day}`.

  ### Examples

      iex> Tempo.LeapSeconds.latest()
      {2016, 12, 31}

  """
  @spec latest() :: date()
  def latest, do: List.last(@insertions)

  @doc """
  The leap seconds an expression spans: those that fall within the time it
  covers, each as the UTC date it ends.

  A leap second lies between `23:59:59` and the midnight after it, so a span
  holds one when it begins before that midnight and runs to it or past it.
  An expression with no zone is read on UTC's clock.

  ### Arguments

  * `expression` is a `t:Tempo.t/0` with a year: a value, an interval, a
    set or a bounded recurrence.

  ### Returns

  * `{:ok, dates}`, a list of `{year, month, day}` in order, empty when it
    spans none.

  * `{:error, %Tempo.ConversionError{}}` for an expression with no year
    (`:needs_a_year`) or with no end (`:unbounded`).

  ### Examples

      iex> Tempo.LeapSeconds.spanned(~o"2015/2017")
      {:ok, [{2015, 6, 30}, {2016, 12, 31}]}

      iex> Tempo.LeapSeconds.spanned(~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z")
      {:ok, [{2016, 12, 31}]}

      iex> Tempo.LeapSeconds.spanned(~o"2026-06-15")
      {:ok, []}

  """
  @spec spanned(Tempo.t()) :: {:ok, [date()]} | {:error, Exception.t()}
  def spanned(%Tempo{} = expression) do
    case Measure.measure(expression) do
      {:ok, :infinity} -> {:error, conversion(expression, :unbounded)}
      {:ok, {_ticks, _start, frame, covered}} -> within(frame.frame, covered, expression)
      {:error, _} = error -> error
    end
  end

  defp within({:cycle, _unit}, _covered, expression),
    do: {:error, conversion(expression, :needs_a_year)}

  defp within(_line, covered, _expression) do
    {:ok, Enum.filter(@insertions ++ @removals, &held?(&1, covered)) |> Enum.sort()}
  end

  defp held?(date, covered) do
    midnight = midnight_after(date)
    Enum.any?(covered, fn {start, stop} -> start < midnight and stop >= midnight end)
  end

  defp midnight_after({year, month, day}),
    do: (Calendars.iso_days(Calendrical.Gregorian, year, month, day) + 1) * @day

  @doc """
  The seconds an expression's leap seconds add to its length: one for each
  inserted, less one for each removed.

  ### Arguments

  * `expression` is a `t:Tempo.t/0`, as for `spanned/1`.

  ### Returns

  * `{:ok, seconds}`, or `{:error, exception}` as `spanned/1` returns it.

  ### Examples

      iex> Tempo.LeapSeconds.count(~o"2015/2017")
      {:ok, 2}

  """
  @spec count(Tempo.t()) :: {:ok, integer()} | {:error, Exception.t()}
  def count(%Tempo{} = expression) do
    with {:ok, dates} <- spanned(expression) do
      {:ok, Enum.count(dates, &(&1 in @insertions)) - Enum.count(dates, &(&1 in @removals))}
    end
  end

  defp conversion(expression, reason),
    do: ConversionError.exception(value: expression, reason: reason)
end
