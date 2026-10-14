defmodule Tempo.Interval do
  @moduledoc """
  Intervals: a span between two ends, `2026-06-01/2026-06-30`.

  An interval is the `{:span, from, to}` form of a `%Tempo{}`. Each end is a
  value, or one of the two is a duration (`2026-06-01/P1M`), or an end is
  open (`2026-06-01/..`). Both ends are in one calendar and one zone (law 5).

  A date end is the date the interval runs through, and a clock end is the
  reading it runs to, as the text is read (law 9); the span the interval
  denotes is half-open either way.

  `new/1` builds one from its two ends, and `from/1`, `to/1` and
  `endpoints/1` read them back. `instants/1` gives the instants it begins
  and ends at, and `leap_seconds_spanned/1` and `spans_leap_second?/1`
  the leap seconds within it.

  """

  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Interop
  alias Tempo.IntervalEndpointsError
  alias Tempo.LeapSeconds
  alias Tempo.Options
  alias Tempo.Spans
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
    calendars or two zones, are both durations, both open, or out of order,
    or when an end is no value, duration or `:open` (an interval or a set
    is not an end).

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

  def new(other),
    do:
      {:error,
       ArgumentError.exception(
         "an interval is built from a keyword list of :from and :to, not #{inspect(other)}"
       )}

  @doc """
  Builds an interval from its two ends, as `new/1` does.

  ### Arguments

  * `from` is the start: a value, a duration (when `to` is a value), or
    `:open`.

  * `to` is the end: a value, a duration (when `from` is a value), or
    `:open`.

  * `metadata` is a map the caller keeps on the interval. The default is `%{}`.

  ### Returns

  * `{:ok, interval}` or `{:error, exception}`, as `new/1` returns.

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

  def new(%Tempo{form: {:value, _}} = from, %Tempo{form: {:value, _}} = to, metadata) do
    cond do
      from.calendar != to.calendar ->
        {:error, IntervalEndpointsError.exception(from: from, to: to, reason: :calendars)}

      zone_name(from) != zone_name(to) ->
        {:error, IntervalEndpointsError.exception(from: from, to: to, reason: :zones)}

      true ->
        validated(from, to, from, metadata)
    end
  end

  def new(%Tempo{form: {:value, _}} = from, to, metadata)
      when is_struct(to, Duration) or to == :open,
      do: validated(from, to, from, metadata)

  def new(from, %Tempo{form: {:value, _}} = to, metadata)
      when is_struct(from, Duration) or from == :open,
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

  ### Arguments

  * `options` is a keyword list with the two ends, as for `new/1`.

  ### Returns

  * The interval, a `t:Tempo.t/0`, or raises the error `new/1` returns.

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

  ### Arguments

  * `interval` is a `t:Tempo.t/0` interval.

  ### Returns

  * The start as written: a value, a duration or `:open`. An expression
    that is no interval raises a `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Interval.from(~o"2026-06-01/2026-06-30")
      ~o"2026-06-01"

      iex> Tempo.Interval.from(~o"P1M/2026-06-30")
      ~o"P1M"

  """
  @spec from(Tempo.t()) :: endpoint()
  def from(%Tempo{form: {:span, from, _to}}), do: from
  def from(other), do: no_interval!(other)

  @doc """
  The end of an interval, as written: a date end is the date the interval
  runs through.

  ### Arguments

  * `interval` is a `t:Tempo.t/0` interval.

  ### Returns

  * The end as written: a value, a duration or `:open`. An expression that
    is no interval raises a `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Interval.to(~o"2026-06-01/2026-06-30")
      ~o"2026-06-30"

      iex> Tempo.Interval.to(~o"2026-06-01/..")
      :open

  """
  @spec to(Tempo.t()) :: endpoint()
  def to(%Tempo{form: {:span, _from, to}}), do: to
  def to(other), do: no_interval!(other)

  @doc """
  Both ends of an interval.

  ### Arguments

  * `interval` is a `t:Tempo.t/0` interval.

  ### Returns

  * `{from, to}`, each as written. An expression that is no interval
    raises a `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Interval.endpoints(~o"2026-06-01/P1M")
      {~o"2026-06-01", ~o"P1M"}

  """
  @spec endpoints(Tempo.t()) :: {endpoint(), endpoint()}
  def endpoints(%Tempo{form: {:span, from, to}}), do: {from, to}
  def endpoints(other), do: no_interval!(other)

  # An accessor of an interval's ends raises, as decision 39 has the
  # functions that answer a bare value do.
  @spec no_interval!(term()) :: no_return()
  defp no_interval!(%Tempo{} = other),
    do: raise(ConversionError.exception(value: other, reason: :not_an_interval))

  defp no_interval!(other),
    do: raise(ConversionError.exception(value: other, reason: :not_an_expression))

  @doc """
  The instants an interval runs between: the one it begins at and the one
  it ends at, the end not in it. An end written to a date is read through
  (law 9), so `2026-06-15/2026-06-20` ends as the 21st begins. It is what a
  store of instants, a database's range of timestamps, holds of an
  interval.

  ### Arguments

  * `interval` is a `t:Tempo.t/0` interval with a year.

  ### Returns

  * `{:ok, {from, to}}`, each a `NaiveDateTime` for an interval with no
    zone, a `DateTime` for one in a zone or at a shift, or `nil` for an
    open end, so `{nil, nil}` for `../..`. The date-times are of the
    interval's calendar.

  * `{:error, exception}` for an interval with no year, as for
    `Tempo.to_interval/2`.

  ### Examples

      iex> Tempo.Interval.instants(~o"2026-06-15/2026-06-20")
      {:ok, {~N[2026-06-15 00:00:00], ~N[2026-06-21 00:00:00]}}

      iex> Tempo.Interval.instants(~o"2026-06-15T09:00Z/2026-06-15T17:00Z")
      {:ok, {~U[2026-06-15 09:00:00Z], ~U[2026-06-15 17:00:00Z]}}

      iex> Tempo.Interval.instants(~o"2026-06-15/..")
      {:ok, {~N[2026-06-15 00:00:00], nil}}

  """
  @spec instants(Tempo.t()) ::
          {:ok, {NaiveDateTime.t() | DateTime.t() | nil, NaiveDateTime.t() | DateTime.t() | nil}}
          | {:error, Exception.t()}
  def instants(%Tempo{form: {:span, :open, :open}}), do: {:ok, {nil, nil}}

  def instants(%Tempo{form: {:span, _from, _to}} = interval) do
    with :ok <- with_a_year(interval),
         {:ok, resolved} <- Tempo.to_interval(interval),
         {:ok, {start, stop}} <- Spans.extent(resolved),
         {:ok, from} <- instant(start, resolved),
         {:ok, to} <- instant(stop, resolved) do
      {:ok, {from, to}}
    end
  end

  def instants(%Tempo{} = other),
    do: {:error, ConversionError.exception(value: other, reason: :several)}

  def instants(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_expression)}

  defp with_a_year(interval) do
    if Tempo.anchored?(interval),
      do: :ok,
      else: {:error, ConversionError.exception(value: interval, reason: :needs_a_year)}
  end

  # A position as the instant it is: a reading of the interval's clock, at
  # UTC where it was written at a shift and has no zone to read it in.
  defp instant(nil, _interval), do: {:ok, nil}

  defp instant(position, %Tempo{calendar: calendar, zone: zone} = interval) do
    shift = if zone == nil and Spans.frame(interval) == :utc, do: [hour: 0]

    model = %Tempo{
      form:
        {:value, [year: 1, month: 1, day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}]},
      calendar: calendar,
      zone: zone,
      shift: shift
    }

    with {:ok, instant} <-
           position |> Spans.at_position(model, :start, calendar, zone) |> Interop.to(),
         do: {:ok, whole_seconds(instant)}
  end

  # A whole second is written with no fraction, as Elixir writes one.
  defp whole_seconds(%{microsecond: {0, _precision}} = instant),
    do: %{instant | microsecond: {0, 0}}

  defp whole_seconds(instant), do: instant

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
  def leap_seconds_spanned(interval) when not is_struct(interval, Tempo),
    do: {:error, ConversionError.exception(value: interval, reason: :not_an_expression)}

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
  def spans_leap_second?(interval) when not is_struct(interval, Tempo),
    do: raise(ConversionError.exception(value: interval, reason: :not_an_expression))

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
