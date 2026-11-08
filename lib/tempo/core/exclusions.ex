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
  alias Tempo.Unit

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
  is cut around it, each piece written to the finer of the member's
  resolution and the exclusions' (`{2017Y..,^2020Y}` is 2017 to 2019, and
  2021 on; `{2026-06,^2026-06-15}` the 1st to the 14th and the 16th to
  the 30th).
  """
  @spec excluded_spans(Tempo.t(), [Tempo.t()], [Tempo.t()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, Exception.t()}
  def excluded_spans(set, members, excluded, options) do
    with {:ok, kept} <- Spans.placed(%{set | form: {:all, members}}, options),
         {:ok, out} <- out_of(set, excluded, options) do
      {:ok, Stream.flat_map(kept, &cut_around(&1, out))}
    end
  end

  @doc """
  The members of a set with exclusions (decision 105): a member no
  exclusion touches, as it is written; and of one an exclusion touches,
  each of its own members (law 6) as it is written, left out where an
  exclusion covers it and cut into the pieces either side where one falls
  inside it. `{2017Y..2022Y,^2020Y}` is the five years, and
  `{2026-06,^2026-06-15}` the 1st to the 14th and the 16th to the 30th.
  """
  @spec members(Tempo.t(), [Tempo.t()], [Tempo.t()], keyword()) ::
          {:ok, [Tempo.t()]} | {:error, Exception.t()}
  def members(set, members, excluded, options) do
    with {:ok, out} <- out_of(set, excluded, options) do
      each_member(members, &member_less(&1, set, out, options))
    end
  end

  defp member_less(member, set, out, options) do
    with {:ok, placed} <- placed_in(member, set, options) do
      if untouched?(placed, out) do
        {:ok, [member]}
      else
        touched(member, set, out, options)
      end
    end
  end

  defp touched(member, set, out, options) do
    with {:ok, own} <- Spans.members(member, options),
         {:ok, own} <- Limit.take(own, set) do
      each_member(own, &own_member_less(&1, set, out, options))
    end
  end

  defp own_member_less(member, set, out, options) do
    with {:ok, placed} <- placed_in(member, set, options) do
      if untouched?(placed, out) do
        {:ok, [member]}
      else
        {:ok,
         Enum.flat_map(placed, &(&1 |> cut_around(out) |> Enum.map(fn piece -> piece.span end)))}
      end
    end
  end

  # A member placed as the set places it, in the set's calendar and zone.
  defp placed_in(member, set, options) do
    with {:ok, placed} <- Spans.placed(%{set | form: {:all, [member]}}, options) do
      Limit.take(placed, set)
    end
  end

  defp untouched?(placed, {extents, _finest}) do
    Enum.all?(placed, fn
      %Placed{start: start, stop: stop} when is_integer(start) ->
        left_after({start, stop}, extents) == [{start, stop}]

      _open_start ->
        true
    end)
  end

  defp each_member(members, fun) do
    Enum.reduce_while(members, {:ok, []}, fn member, {:ok, kept} ->
      case fun.(member) do
        {:ok, more} -> {:cont, {:ok, kept ++ more}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
  end

  # What the excluded members cover, as sorted extents, with the finest
  # value they are written to, which a piece cut by them is written to.
  defp out_of(set, excluded, options) do
    with {:ok, out} <- Spans.placed(%{set | form: {:all, excluded}}, options),
         {:ok, out} <- Limit.take(out, set) do
      extents = out |> Enum.flat_map(&bounded_extent/1) |> Enum.sort()
      {:ok, {extents, finest_model(out)}}
    end
  end

  defp finest_model(placed) do
    placed
    |> Enum.map(&model_of(&1.span))
    |> Enum.max_by(&rank_of/1, fn -> nil end)
  end

  defp model_of(%Tempo{form: {:span, from, to}}), do: Spans.first_value([from, to])
  defp model_of(value), do: value

  defp rank_of(%Tempo{form: {:value, [_ | _] = units}}) do
    units
    |> Unit.resolution()
    |> Unit.grain()
    |> Unit.rank()
  end

  defp rank_of(_model), do: -1

  defp bounded_extent(%Placed{start: start, stop: stop})
       when is_integer(start) and is_integer(stop),
       do: [{start, stop}]

  defp bounded_extent(_open), do: []

  defp cut_around(%Placed{start: start, stop: stop} = placed, out) when is_integer(start),
    do: pieces(placed, {start, stop}, out)

  defp cut_around(placed, _out), do: [placed]

  defp pieces(%Placed{span: span} = placed, whole, {extents, finest}) do
    case left_after(whole, extents) do
      [^whole] -> [placed]
      left -> Enum.map(left, &Placed.new(piece(span, &1, finest), &1))
    end
  end

  # What of a stretch no excluded stretch covers; a stop of nil has no end.
  defp left_after({start, stop}, out) do
    {left, from} =
      Enum.reduce(out, {[], start}, fn {s, e}, {left, from} ->
        cond do
          e <= from or (not is_nil(stop) and s >= stop) -> {left, from}
          s > from -> {[{from, s} | left], e}
          true -> {left, max(from, e)}
        end
      end)

    if is_nil(stop) or from < stop do
      Enum.reverse([{from, stop} | left])
    else
      Enum.reverse(left)
    end
  end

  defp piece(%Tempo{form: {:span, from, to}} = span, {start, stop}, finest) do
    model = finer(if(match?(%Tempo{form: {:value, _}}, from), do: from, else: to), finest)
    first = Spans.at_position(start, model, :start, span.calendar, span.zone)

    last =
      if is_nil(stop) do
        to
      else
        Spans.at_position(stop, model, :end, span.calendar, span.zone)
      end

    %{span | form: {:span, first, last}}
  end

  # The finer of a member's model and the exclusions', so that a piece
  # cut at a day of a month is written to the day.
  defp finer(model, finest) do
    if rank_of(finest) > rank_of(model), do: %{finest | metadata: model.metadata}, else: model
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
