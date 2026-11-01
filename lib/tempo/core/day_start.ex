defmodule Tempo.DayStart do
  @moduledoc false

  # Days of a calendar whose day begins in the evening, placed on the UTC
  # line (decision 91, `plans/day-start.md`). The calendar names its
  # boundary and its place, and Calendrical computes the bounds
  # (`day_bounds/1`); Tempo writes each day, or each run of days, as the span
  # from the start of its first day to the stop of its last, in the zone of
  # the calendar's place and in the calendar itself. An expression is in one
  # calendar (law 5), so its days are all of one day start: an expression of
  # a calendar whose day begins at midnight is returned as it is.

  alias Tempo.Calendar
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Spans

  @doc "An expression with each of its days placed by its calendar's day start."
  @spec project(Tempo.t() | Tempo.Duration.t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def project(%Tempo.Duration{} = duration) do
    {:error, ConversionError.exception(value: duration, reason: :not_days)}
  end

  def project(%Tempo{calendar: calendar} = expression) do
    case Calendar.day_zone(calendar) do
      {:ok, zone} -> placed(expression, zone)
      :midnight -> {:ok, expression}
    end
  end

  # One span is placed; a bounded expression of several is the set of its
  # spans, each placed; one with no end is the stream of them.
  defp placed(expression, zone) do
    cond do
      Spans.singular?(expression) -> span_placed(expression, zone)
      Tempo.bounded?(expression) -> spans_placed(expression, zone)
      true -> stream_placed(expression, zone)
    end
  end

  defp spans_placed(expression, zone) do
    with {:ok, spans} <- Tempo.to_interval(expression),
         {:ok, placed} <- each_placed(IntervalSet.members(spans), zone) do
      IntervalSet.new(placed, metadata: Tempo.metadata(expression))
    end
  end

  defp each_placed(spans, zone) do
    spans
    |> Enum.reduce_while({:ok, []}, fn span, {:ok, done} ->
      case span_placed(span, zone) do
        {:ok, placed} -> {:cont, {:ok, [placed | done]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> reversed()
  end

  defp reversed({:ok, placed}), do: {:ok, Enum.reverse(placed)}
  defp reversed(error), do: error

  # A set with no end is placed as it is walked; a span that cannot be
  # placed raises its error then, as a walk does. One with no start, a rule
  # not yet placed in a window, has no spans to walk, and is its error.
  defp stream_placed(expression, zone) do
    with {:ok, spans} <- Spans.spans(expression) do
      placed = Stream.map(spans, &span_placed!(&1, zone))
      {:ok, IntervalSet.from_stream(placed, metadata: Tempo.metadata(expression))}
    end
  end

  defp span_placed!(span, zone) do
    case span_placed(span, zone) do
      {:ok, placed} -> placed
      {:error, exception} -> raise exception
    end
  end

  # A day, or a run of days, is the span from the start of the first to the
  # stop of the last, keeping the span's metadata.
  defp span_placed(%Tempo{calendar: calendar} = span, zone) do
    with {:ok, first, last} <- days_of(span),
         {:ok, {start, _}} <- Calendar.day_bounds(calendar, first),
         {:ok, {_, stop}} <- Calendar.day_bounds(calendar, last),
         {:ok, from} <- on_clock(start, zone, calendar),
         {:ok, to} <- on_clock(stop, zone, calendar),
         {:ok, interval} <- Interval.new(from: from, to: to) do
      {:ok, Tempo.put_metadata(interval, Tempo.metadata(span))}
    end
  end

  # The first and last days a span holds: a day is both, an interval of days
  # runs from its first to its last. Anything else has no day start.
  defp days_of(span) do
    case Tempo.to_elixir(span) do
      {:ok, %Date{} = day} -> {:ok, day, day}
      {:ok, %Date.Range{first: first, last: last}} -> {:ok, first, last}
      _not_days -> {:error, ConversionError.exception(value: span, reason: :not_days)}
    end
  end

  # A UTC instant as a value on the zone's clock, in the calendar, to the
  # second: a day's stop and the next day's start are one instant, cut alike,
  # so the days still meet.
  defp on_clock(instant, zone, calendar) do
    second = DateTime.truncate(instant, :second)

    with {:ok, shown} <- DateTime.shift_zone(second, zone, Tempo.time_zone_database()),
         {:ok, value} <- Tempo.from_elixir(shown) do
      Tempo.to_calendar(value, calendar)
    end
  end
end
