defmodule Tempo.Exclusions do
  @moduledoc false

  # What a set or a rule leaves out: the members of a set with what an
  # excluded member covers taken out (`{2026, ^2026-06}`), the occurrences
  # a rule's domain of exclusions removes, and the years a domain filter
  # keeps (`R/..e/…`, the even years).

  alias Tempo.Calendar
  alias Tempo.Limit
  alias Tempo.Placed
  alias Tempo.Spans

  @doc """
  Whether a set is all exclusions: a domain that names only what a rule
  leaves out.
  """
  @spec only_exclusions?(Tempo.t()) :: boolean()
  def only_exclusions?(%Tempo{form: {:all, [_ | _] = members}}) when is_list(members),
    do: Enum.all?(members, &match?({:except, _}, &1))

  def only_exclusions?(_domain), do: false

  @doc "Every year (`R/..e/…`), the years a filter keeps of those a window gives."
  @spec every_year?(Tempo.t()) :: boolean()
  def every_year?(%Tempo{form: {:when, inner, [years: _filter]}}), do: every_year?(inner)
  def every_year?(%Tempo{form: {:span, :open, :open}}), do: true
  def every_year?(_domain), do: false

  @doc "The placed occurrences that no excluded extent covers."
  @spec left_out(Enumerable.t(), [{:ok, Spans.extent()}]) :: Enumerable.t()
  def left_out(stream, []), do: stream

  def left_out(stream, excluded),
    do: Stream.reject(stream, &excluded?({:ok, Placed.extent(&1)}, excluded))

  @doc """
  The extents a domain of exclusions alone leaves out. One that cannot be
  given its spans is the error, and no occurrence is answered as if
  nothing were left out.
  """
  @spec exclusions(Tempo.t(), keyword()) ::
          {:ok, [{:ok, Spans.extent()}]} | {:error, Exception.t()}
  def exclusions(%Tempo{form: {:all, members}} = domain, options) do
    if only_exclusions?(domain) do
      excluded = %{domain | form: {:all, Enum.map(members, &elem(&1, 1))}}

      with {:ok, spans} <- Spans.placed(excluded, options),
           {:ok, spans} <- Limit.take(spans, excluded),
           do: {:ok, Enum.map(spans, &{:ok, Placed.extent(&1)})}
    else
      {:ok, []}
    end
  end

  def exclusions(_domain, _options), do: {:ok, []}

  @doc """
  The members' spans with what an excluded member covers taken out: a
  member within one is left out, and one an excluded member falls inside
  is cut around it, each piece written to the member's own resolution
  (`{2017Y..,^2020Y}` is 2017 to 2019, and 2021 on).
  """
  @spec excluded_spans(Tempo.t(), [Tempo.t()], [Tempo.t()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def excluded_spans(set, members, excluded, options) do
    with {:ok, kept} <- Spans.placed(%{set | form: {:all, members}}, options),
         {:ok, out} <- Spans.placed(%{set | form: {:all, excluded}}, options),
         {:ok, out} <- Limit.take(out, set) do
      out = out |> Enum.flat_map(&bounded_extent/1) |> Enum.sort()
      {:ok, Stream.flat_map(kept, &cut_around(&1, out))}
    end
  end

  defp bounded_extent(%Placed{start: start, stop: stop})
       when is_integer(start) and is_integer(stop),
       do: [{start, stop}]

  defp bounded_extent(_open), do: []

  defp cut_around(%Placed{start: start, stop: stop} = placed, out) when is_integer(start),
    do: pieces(placed, {start, stop}, out)

  defp cut_around(placed, _out), do: [placed]

  defp pieces(%Placed{span: span} = placed, whole, out) do
    case left_after(whole, out) do
      [^whole] -> [placed]
      left -> Enum.map(left, &Placed.new(piece(span, &1), &1))
    end
  end

  # What of a stretch no excluded stretch covers; a stop of nil has no end.
  defp left_after({start, stop}, out) do
    {left, from} =
      Enum.reduce(out, {[], start}, fn {s, e}, {left, from} ->
        cond do
          e <= from or (stop != nil and s >= stop) -> {left, from}
          s > from -> {[{from, s} | left], e}
          true -> {left, max(from, e)}
        end
      end)

    if stop == nil or from < stop,
      do: Enum.reverse([{from, stop} | left]),
      else: Enum.reverse(left)
  end

  defp piece(%Tempo{form: {:span, from, to}} = span, {start, stop}) do
    model = if match?(%Tempo{form: {:value, _}}, from), do: from, else: to
    first = Spans.at_position(start, model, :start, span.calendar, span.zone)

    last =
      if stop == nil, do: to, else: Spans.at_position(stop, model, :end, span.calendar, span.zone)

    %{span | form: {:span, first, last}}
  end

  defp excluded?({:ok, {start, stop}}, out) when is_integer(start) and is_integer(stop) do
    Enum.any?(out, fn
      {:ok, {s, e}} when is_integer(s) and is_integer(e) -> s <= start and stop <= e
      _ -> false
    end)
  end

  defp excluded?(_extent, _out), do: false

  @doc """
  Whether a span starts in a year a domain filter keeps: an even or odd
  year, a leap or common year of the calendar.
  """
  @spec in_years?(Tempo.t(), :even | :odd | :leap | :common, module()) :: boolean()
  def in_years?(%Tempo{form: {:span, %Tempo{form: {:value, units}}, _}}, filter, calendar) do
    case Keyword.get(units, :year) do
      year when is_integer(year) -> year_in?(year, filter, calendar)
      _ -> false
    end
  end

  def in_years?(_span, _filter, _calendar), do: false

  defp year_in?(year, :even, _calendar), do: rem(year, 2) == 0
  defp year_in?(year, :odd, _calendar), do: rem(year, 2) != 0
  defp year_in?(year, :leap, calendar), do: Calendar.leap_year?(calendar, year)
  defp year_in?(year, :common, calendar), do: not Calendar.leap_year?(calendar, year)
end
