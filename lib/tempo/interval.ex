defmodule Tempo.Interval do
  @moduledoc """
  Intervals: a span between two ends, `2026-06-01/2026-06-30`.

  An interval is the `{:span, from, to}` form of a `%Tempo{}`. Each end is a
  value, or one of the two is a duration (`2026-06-01/P1M`), or an end is
  open (`2026-06-01/..`). Both ends are in one calendar and one zone (law 5).

  A date end is the date the interval runs through, and a clock end is the
  reading it runs to, as the text is read (law 9); the span the interval
  denotes is half-open either way.

  """

  alias Tempo.Duration
  alias Tempo.IntervalEndpointsError
  alias Tempo.LeapSeconds
  alias Tempo.Options
  alias Tempo.Validate

  @type endpoint :: Tempo.t() | Duration.t() | :open

  @doc """
  Builds an interval from its ends.

  ### Arguments

  * `options` is a keyword list with the two ends.

  ### Options

  * `:from` is the start: a value, a duration (when `:to` is a value), or
    `:open`.

  * `:to` is the end: a value, a duration (when `:from` is a value), or
    `:open`. A date end is the date the interval runs through.

  * `:metadata` is a map the caller keeps on the interval. The default is `%{}`.

  ### Returns

  * `{:ok, interval}`, a `t:Tempo.t/0` of the `:span` form.

  * `{:error, %Tempo.IntervalEndpointsError{}}` when the ends are in two
    calendars or two zones, are both durations, both open, or out of order.

  ### Examples

      iex> Tempo.Interval.new(from: ~o"2026-06-01", to: ~o"2026-06-30")
      {:ok, ~o"2026-06-01/2026-06-30"}

      iex> Tempo.Interval.new(from: ~o"2026-06-01", to: ~o"P1M")
      {:ok, ~o"2026-06-01/P1M"}

      iex> Tempo.Interval.new(from: ~o"2026-06-01", to: :open)
      {:ok, ~o"2026-06-01/.."}

      iex> {:error, %Tempo.IntervalEndpointsError{reason: :order}} =
      ...>   Tempo.Interval.new(from: ~o"2026-06-30", to: ~o"2026-06-01")

      iex> {:error, %Tempo.IntervalEndpointsError{reason: :calendars}} =
      ...>   Tempo.Interval.new(from: ~o"2026-06-01", to: ~o"5786-03-15[u-ca=hebrew]")

  """
  @spec new(keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def new(options) when is_list(options) do
    with :ok <- Options.check(options, [:from, :to, :metadata], "Tempo.Interval.new/1") do
      new(
        Keyword.get(options, :from, :open),
        Keyword.get(options, :to, :open),
        Keyword.get(options, :metadata, %{})
      )
    end
  end

  @doc """
  Builds an interval from its two ends, as `new/1` does.

  ### Examples

      iex> Tempo.Interval.new(~o"2026-06-15T09", ~o"2026-06-15T17")
      {:ok, ~o"2026-06-15T09/2026-06-15T17"}

  """
  @spec new(endpoint(), endpoint(), map()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def new(from, to, metadata \\ %{})

  def new(%Duration{} = from, %Duration{} = to, _metadata),
    do: {:error, IntervalEndpointsError.exception(from: from, to: to, reason: :duration)}

  def new(:open, :open, _metadata),
    do: {:error, IntervalEndpointsError.exception(from: :open, to: :open, reason: :open)}

  def new(%Tempo{} = from, %Tempo{} = to, metadata) do
    cond do
      from.calendar != to.calendar ->
        {:error, IntervalEndpointsError.exception(from: from, to: to, reason: :calendars)}

      zone_name(from) != zone_name(to) ->
        {:error, IntervalEndpointsError.exception(from: from, to: to, reason: :zones)}

      true ->
        validated(from, to, from, metadata)
    end
  end

  def new(%Tempo{} = from, to, metadata) when is_struct(to, Duration) or to == :open,
    do: validated(from, to, from, metadata)

  def new(from, %Tempo{} = to, metadata) when is_struct(from, Duration) or from == :open,
    do: validated(from, to, to, metadata)

  def new(from, to, _metadata),
    do:
      {:error,
       IntervalEndpointsError.exception(
         from: from,
         to: to,
         reason: "has an end that is not a value, a duration or :open"
       )}

  @doc """
  Builds an interval as `new/1` does, returning it or raising.

  ### Examples

      iex> Tempo.Interval.new!(from: ~o"2026", to: ~o"2028")
      ~o"2026/2028"

  """
  @spec new!(keyword()) :: Tempo.t()
  def new!(options) do
    case new(options) do
      {:ok, interval} -> interval
      {:error, exception} -> raise exception
    end
  end

  @doc """
  The start of an interval.

  ### Examples

      iex> Tempo.Interval.from(~o"2026-06-01/2026-06-30")
      ~o"2026-06-01"

      iex> Tempo.Interval.from(~o"P1M/2026-06-30")
      ~o"P1M"

  """
  @spec from(Tempo.t()) :: endpoint()
  def from(%Tempo{form: {:span, from, _to}}), do: from

  @doc """
  The end of an interval, as written: a date end is the date the interval
  runs through.

  ### Examples

      iex> Tempo.Interval.to(~o"2026-06-01/2026-06-30")
      ~o"2026-06-30"

      iex> Tempo.Interval.to(~o"2026-06-01/..")
      :open

  """
  @spec to(Tempo.t()) :: endpoint()
  def to(%Tempo{form: {:span, _from, to}}), do: to

  @doc """
  Both ends of an interval.

  ### Examples

      iex> Tempo.Interval.endpoints(~o"2026-06-01/P1M")
      {~o"2026-06-01", ~o"P1M"}

  """
  @spec endpoints(Tempo.t()) :: {endpoint(), endpoint()}
  def endpoints(%Tempo{form: {:span, from, to}}), do: {from, to}

  @doc """
  The leap seconds an interval spans, each as the UTC date it ends:
  `Tempo.LeapSeconds.spanned/1`, returning the list or the error.

  ### Arguments

  * `interval` is a `t:Tempo.t/0` with a year and both its ends.

  ### Returns

  * A list of `{year, month, day}`, empty when it spans none.

  * `{:error, %Tempo.ConversionError{}}` for an interval with no year or
    with an open end.

  ### Examples

      iex> Tempo.Interval.leap_seconds_spanned(~o"2015-01-01/2017-12-31")
      [{2015, 6, 30}, {2016, 12, 31}]

  """
  @spec leap_seconds_spanned(Tempo.t()) :: [LeapSeconds.date()] | {:error, Exception.t()}
  def leap_seconds_spanned(%Tempo{} = interval) do
    case LeapSeconds.spanned(interval) do
      {:ok, dates} -> dates
      {:error, _} = error -> error
    end
  end

  @doc """
  Whether an interval spans a leap second, so that its length in elapsed
  seconds is not its length on the clock.

  ### Arguments

  * `interval` is a `t:Tempo.t/0` with a year and both its ends.

  ### Returns

  * `true` or `false`; raises a `Tempo.ConversionError` for an interval
    with no year or with an open end.

  ### Examples

      iex> Tempo.Interval.spans_leap_second?(~o"2016-12-31T23:00:00Z/2017-01-01T01:00:00Z")
      true

      iex> Tempo.Interval.spans_leap_second?(~o"2026-06-15/2026-06-16")
      false

  """
  @spec spans_leap_second?(Tempo.t()) :: boolean()
  def spans_leap_second?(%Tempo{} = interval) do
    case LeapSeconds.spanned(interval) do
      {:ok, dates} -> dates != []
      {:error, exception} -> raise exception
    end
  end

  defp validated(from, to, frame, metadata) do
    interval = %Tempo{
      form: {:span, from, to},
      calendar: frame.calendar,
      zone: frame.zone,
      shift: nil,
      metadata: metadata
    }

    Validate.run(interval)
  end

  defp zone_name(%Tempo{zone: nil}), do: nil
  defp zone_name(%Tempo{zone: %{name: name, offset: offset}}), do: name || offset
end
