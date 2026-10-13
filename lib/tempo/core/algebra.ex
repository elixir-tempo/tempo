defmodule Tempo.Algebra do
  @moduledoc false

  # The set operations as one sweep over positions (section 7.2 of the plan).
  #
  # An operand is read as its spans (`Tempo.Spans`), each placed on the frame
  # as two positions; two operands must lie on one frame (law 4), a value with
  # no year being placed on each period of the `:within` window first and a
  # recurrence with no end bounded by it. Every instant-level operation is the
  # one sweep over the operands' edges with a different question of how many
  # members of each cover a point; a result begins where the answer turns true
  # and ends where it turns false, so a result's ends are always operands'
  # ends and are written as those operands wrote them, in the first operand's
  # calendar and zone. The member-preserving companions ask of each member of
  # the first whether any point of it is covered by the second. A span on a
  # cycle that runs through the cycle's end is cut into two for the sweep and
  # joined after it.

  alias Tempo.ConversionError
  alias Tempo.FrameError
  alias Tempo.Limit
  alias Tempo.Scale
  alias Tempo.Spans

  @typedoc "A span placed on a frame: its two positions and the written span they came from."
  @type positioned :: %{start: integer(), stop: integer(), span: Tempo.t(), side: :a | :b}

  @typedoc "A result of the sweep: its positions, the operand ends it opened and closed at, and the members covering it."
  @type result :: %{
          start: integer(),
          stop: integer(),
          opened: {Tempo.t(), :from | :to},
          closed: {Tempo.t(), :from | :to},
          a: Tempo.t() | nil,
          b: Tempo.t() | nil
        }

  @type frame :: %{
          frame: Scale.frame(),
          calendar: module(),
          zone: Tempo.Zone.t() | nil,
          length: integer() | nil
        }

  # ── Operands ──────────────────────────────────────────────────────────

  @doc """
  Two expressions as positioned spans on one frame, with the frame: the first
  operand's calendar and zone, and the cycle's length on a cycle. A value with
  no year beside one with a year is placed by the `:within` window, and a
  recurrence with no end is bounded by it or by the other operand.
  """
  @spec aligned(Tempo.t(), Tempo.t(), keyword()) ::
          {:ok, frame(), [positioned()], [positioned()]} | {:error, Exception.t()}
  def aligned(a, b, options) do
    with :ok <- operable(a, b),
         {:ok, pa} <- operand(a, b, :a, options),
         {:ok, pb} <- operand(b, a, :b, options),
         {:ok, frame} <- one_frame(a, b, pa, pb, options) do
      {:ok, frame, cut(pa, frame), cut(pb, frame)}
    end
  end

  @doc "One expression as positioned spans, with its frame."
  @spec positioned(Tempo.t(), keyword()) ::
          {:ok, frame(), [positioned()]} | {:error, Exception.t()}
  def positioned(a, options) do
    with :ok <- operable(a, a),
         {:ok, pa} <- operand(a, nil, :a, options),
         {:ok, frame} <- frame_of(placed(a, options[:within]), a) do
      {:ok, frame, cut(pa, frame)}
    end
  end

  defp operable(a, b) do
    Enum.find_value([a, b], :ok, fn
      %Tempo.Duration{} = duration ->
        {:error, ConversionError.exception(value: duration, reason: :bare_duration)}

      %Tempo{form: {:one, _}} = one ->
        {:error, ConversionError.exception(value: one, reason: :one_of)}

      %Tempo{} ->
        nil

      other ->
        {:error, ConversionError.exception(value: other, reason: :not_an_expression)}
    end)
  end

  # The spans of an operand, each with its positions. A value with no year is
  # placed by the window; a recurrence with no end is bounded by the window or
  # by the other operand's whole stretch.
  defp operand(expression, other, side, options) do
    window = window_for(expression, other, options)
    placed = if window, do: Spans.placed_in(expression, window), else: expression

    with {:ok, spans} <- Spans.spans(placed, if(window, do: [within: window], else: [])),
         {:ok, spans} <- bounded(spans, expression),
         {:ok, positioned} <- placed_spans(spans, side) do
      {:ok, Enum.sort_by(positioned, &{&1.start, &1.stop})}
    end
  end

  defp placed_spans(spans, side) do
    Enum.reduce_while(spans, {:ok, []}, fn span, {:ok, acc} ->
      case Spans.extent(span) do
        {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
          {:cont, {:ok, acc ++ [%{start: start, stop: stop, span: span, side: side}]}}

        {:ok, _open} ->
          {:halt, {:error, ConversionError.exception(value: span, reason: :open)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp window_for(%Tempo{form: {:every, _, :infinity, _}}, other, options),
    do: options[:within] || other

  defp window_for(expression, other, options) do
    cond do
      options[:within] != nil -> options[:within]
      not anchored?(expression) and other != nil and anchored?(other) -> nil
      true -> nil
    end
  end

  defp bounded(spans, expression), do: Limit.take(spans, expression)

  defp anchored?(%Tempo{} = expression), do: not match?({:cycle, _}, Spans.frame(expression))

  # What an expression is once placed by a window, if it is.
  defp placed(%Tempo{} = expression, %Tempo{} = window) do
    if anchored?(expression), do: expression, else: Spans.placed_in(expression, window)
  end

  defp placed(expression, _window), do: expression

  # An operand with no spans has no frame of its own, and takes the other's.
  defp one_frame(_a, b, [], [_ | _], options), do: one_frame(b, b, [], [], options)
  defp one_frame(a, _b, [_ | _], [], options), do: one_frame(a, a, [], [], options)

  defp one_frame(a, b, _pa, _pb, options) do
    window = options[:within]
    a_placed = placed(a, window)
    b_placed = placed(b, window)

    case {Spans.frame(a_placed), Spans.frame(b_placed)} do
      {{:cycle, u}, {:cycle, u}} -> frame_of(a_placed, a)
      {{:cycle, _}, {:cycle, _}} -> {:error, FrameError.exception(a: a, b: b, reason: :cycles)}
      {{:cycle, _}, _} -> {:error, FrameError.exception(a: a, b: b, reason: :needs_a_year)}
      {_, {:cycle, _}} -> {:error, FrameError.exception(a: a, b: b, reason: :needs_a_year)}
      {same, same} -> frame_of(a_placed, a)
      {_, _} -> {:error, FrameError.exception(a: a, b: b, reason: :floating_and_zoned)}
    end
  end

  defp frame_of(placed, original) do
    frame = Spans.frame(placed)

    length =
      case frame do
        {:cycle, coarsest} ->
          case Scale.cycle_length(coarsest, original.calendar) do
            {:ok, length} -> length
            {:error, _} -> nil
          end

        _ ->
          nil
      end

    {:ok, %{frame: frame, calendar: original.calendar, zone: original.zone, length: length}}
  end

  # On a cycle a span that runs through the cycle's end is two for the sweep.
  defp cut(positioned, %{length: nil}), do: positioned

  defp cut(positioned, %{length: length}) do
    Enum.flat_map(positioned, fn
      %{stop: stop} = p when stop > length ->
        [
          Map.put(%{p | stop: length}, :half, :first),
          Map.put(%{p | start: 0, stop: stop - length}, :half, :second)
        ]

      p ->
        [p]
    end)
    |> Enum.sort_by(&{&1.start, &1.stop})
  end

  # ── The sweep ─────────────────────────────────────────────────────────

  # ── One set ───────────────────────────────────────────────────────────

  @doc """
  Members gathered into one set (law 5: one expression, one calendar, one
  zone). Each is brought to the set's calendar, the first member's unless one
  is given. Where a member is in a named zone the set is in one, the first
  named unless one is given, and each zoned member is moved to it; members
  that carry only shifts keep them. A member with no zone beside a zoned one
  is an error, or with `floating: :place` is read on the set's clock, as an
  event with no zone is in a calendar that has one. With `sorted: true` the
  members are put in order once they are in one frame.
  """
  @spec gathered([Tempo.t()], keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def gathered(members, options \\ [])

  def gathered([], options) do
    {:ok,
     %Tempo{
       form: {:all, []},
       calendar: options[:calendar] || Calendar.ISO,
       zone: options[:zone],
       metadata: options[:metadata] || %{}
     }}
  end

  def gathered([first | _] = members, options) do
    calendar = options[:calendar] || first.calendar
    zone = options[:zone] || named_zone(members) || placing_zone(members, options[:floating])

    zoned = Enum.find(members, &(Spans.frame(&1) == :utc))
    floating = {options[:floating], zoned}

    with {:ok, members} <- each_member(members, &in_calendar(&1, calendar)),
         {:ok, members} <- each_member(members, &in_zone(&1, zone, floating)) do
      {:ok,
       %Tempo{
         form: {:all, in_order(members, options[:sorted])},
         calendar: calendar,
         zone: zone,
         metadata: options[:metadata] || %{}
       }}
    end
  end

  # Members are sorted once they share a frame to be ordered on.
  defp in_order(members, true), do: Enum.sort(members, Tempo)
  defp in_order(members, _as_given), do: members

  defp named_zone(members) do
    Enum.find_value(members, fn
      %Tempo{zone: %Tempo.Zone{name: name} = zone} when is_binary(name) -> zone
      _ -> nil
    end)
  end

  # Members with shifts alone keep them, unless a member with no zone is to
  # be placed beside them: then all are read on UTC's clock.
  defp placing_zone(members, :place) do
    frames = Enum.map(members, &Spans.frame/1)

    if :utc in frames and :floating in frames,
      do: %Tempo.Zone{name: "Etc/UTC"},
      else: nil
  end

  defp placing_zone(_members, _floating), do: nil

  defp in_calendar(%Tempo{calendar: calendar} = member, calendar), do: {:ok, member}
  defp in_calendar(%Tempo{} = member, calendar), do: Tempo.to_calendar(member, calendar)

  defp in_zone(member, nil, _floating), do: {:ok, member}
  defp in_zone(%Tempo{zone: zone} = member, zone, _floating), do: {:ok, member}

  defp in_zone(%Tempo{} = member, %Tempo.Zone{name: name}, {floating, zoned}) do
    case {Spans.frame(member), floating} do
      {:utc, _} ->
        Tempo.shift_zone(member, name)

      {:floating, :place} ->
        Tempo.in_zone(member, name)

      {:floating, _} ->
        {:error, FrameError.exception(a: zoned, b: member, reason: :floating_and_zoned)}

      {_cycle, _} ->
        {:ok, member}
    end
  end

  defp each_member(members, fun) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, done} ->
      case fun.(member) do
        {:ok, member} -> {:cont, {:ok, [member | done]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> reversed()
  end

  defp reversed({:ok, members}), do: {:ok, Enum.reverse(members)}
  defp reversed(error), do: error

  @doc "Every point in either operand."
  @spec union([positioned()], [positioned()], frame()) :: [result()]
  def union(a, b, frame), do: sweep(a, b, frame, fn da, db -> da > 0 or db > 0 end)

  @doc "Every point in both operands."
  @spec intersection([positioned()], [positioned()], frame()) :: [result()]
  def intersection(a, b, frame), do: sweep(a, b, frame, fn da, db -> da > 0 and db > 0 end)

  @doc "Every point in the first operand and not the second."
  @spec difference([positioned()], [positioned()], frame()) :: [result()]
  def difference(a, b, frame), do: sweep(a, b, frame, fn da, db -> da > 0 and db == 0 end)

  @doc "Every point in exactly one operand."
  @spec symmetric_difference([positioned()], [positioned()], frame()) :: [result()]
  def symmetric_difference(a, b, frame), do: sweep(a, b, frame, fn da, db -> da > 0 != db > 0 end)

  @doc "Every point covered by at least so many members of one operand."
  @spec covered([positioned()], pos_integer(), frame()) :: [result()]
  def covered(a, at_least, frame), do: sweep(a, [], frame, fn da, _db -> da >= at_least end)

  @doc "Positioned spans with the second half of a cut cycle span left out: one entry per member."
  @spec whole([positioned()]) :: [positioned()]
  def whole(positioned), do: Enum.reject(positioned, &(Map.get(&1, :half) == :second))

  @doc "The members of the first operand some point of which is in the second."
  @spec members_overlapping([positioned()], [positioned()]) :: [positioned()]
  def members_overlapping(a, b),
    do: Enum.filter(a, fn m -> Enum.any?(b, &overlapping?(m, &1)) end)

  @doc "The members of the first operand no point of which is in the second."
  @spec members_outside([positioned()], [positioned()]) :: [positioned()]
  def members_outside(a, b), do: Enum.reject(a, fn m -> Enum.any?(b, &overlapping?(m, &1)) end)

  defp overlapping?(x, y), do: x.start < y.stop and y.start < x.stop

  # The one sweep: the operands' edges position by position, every close and
  # open at a position applied before the point after it is judged, with the
  # members of each side covering it.
  defp sweep(a, b, frame, keep?) do
    (edges(a, :a) ++ edges(b, :b))
    |> Enum.group_by(fn {position, _, _, _} -> position end)
    |> Enum.sort_by(fn {position, _} -> position end)
    |> Enum.reduce({[], %{a: [], b: []}, nil}, fn {position, edges}, {out, covering, open} ->
      covering =
        Enum.reduce(edges, covering, fn {_, kind, side, p}, acc -> step(acc, kind, side, p) end)

      now = keep?.(length(covering.a), length(covering.b))

      case {open, now} do
        {nil, true} ->
          opened = %{
            start: position,
            opened: edge_model(edges, :open),
            a: List.first(covering.a),
            b: List.first(covering.b)
          }

          {out, covering, opened}

        {%{} = open, false} ->
          {[Map.merge(open, %{stop: position, closed: edge_model(edges, :close)}) | out],
           covering, nil}

        _ ->
          {out, covering, open}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> joined(frame)
  end

  # The operand end a result's end is written as: a member's start where one
  # opens there, else a member's end; the reverse for a result's end.
  defp edge_model(edges, preferred) do
    {_, kind, _, p} = Enum.find(edges, hd(edges), fn {_, kind, _, _} -> kind == preferred end)
    {p.span, end_kind(kind)}
  end

  # An operand's edges, on the side its argument stands.
  defp edges(positioned, side) do
    Enum.flat_map(positioned, fn p ->
      [{p.start, :open, side, p}, {p.stop, :close, side, p}]
    end)
  end

  defp step(covering, :open, side, p), do: Map.update!(covering, side, &[p.span | &1])
  defp step(covering, :close, side, p), do: Map.update!(covering, side, &List.delete(&1, p.span))

  # An edge that opens a member is that member's start; one that closes it is its end.
  defp end_kind(:open), do: :from
  defp end_kind(:close), do: :to

  # On a cycle a result ending at the cycle's end and one beginning at its start are one span through the end.
  defp joined(results, %{length: nil}), do: results

  defp joined(results, %{length: length}) do
    case {Enum.find(results, &(&1.start == 0)), Enum.find(results, &(&1.stop == length))} do
      {%{} = first, %{} = last} when first != last ->
        wrapped = %{last | stop: first.stop + length, closed: first.closed}
        (results -- [first, last]) ++ [wrapped]

      _ ->
        results
    end
  end

  # ── Writing results ───────────────────────────────────────────────────

  @doc """
  A result as a written span in a calendar and zone: each end written as the
  operand end that stands there wrote it, at its resolution, and the metadata
  the `:metadata` option names (`:first`, the default, the first operand's
  member covering the result; `:second`; `:merge`; or a function of the two).
  """
  @spec written(result(), frame(), keyword()) :: Tempo.t()
  def written(
        %{start: start, stop: stop, opened: opened, closed: closed} = result,
        frame,
        options
      ) do
    from = Spans.at_position(start, model(opened), :start, frame.calendar, frame.zone)
    to = Spans.at_position(stop, model(closed), :end, frame.calendar, frame.zone)

    %Tempo{
      form: {:span, from, to},
      calendar: frame.calendar,
      zone: frame.zone,
      metadata: metadata(result, Keyword.get(options, :metadata, :first))
    }
  end

  # The operand end at a position: a span's from or to, itself a value.
  defp model({%Tempo{form: {:span, from, to}}, which}) do
    case {which, from, to} do
      {:from, %Tempo{} = value, _} -> value
      {:to, _, %Tempo{} = value} -> value
      {_, %Tempo{} = value, _} -> value
      {_, _, %Tempo{} = value} -> value
    end
  end

  defp model({%Tempo{form: {:value, _}} = value, _which}), do: value

  defp metadata(%{a: a, b: b}, :first), do: member_metadata(a) || member_metadata(b) || %{}
  defp metadata(%{a: a, b: b}, :second), do: member_metadata(b) || member_metadata(a) || %{}

  defp metadata(%{a: a, b: b}, :merge),
    do: Map.merge(member_metadata(a) || %{}, member_metadata(b) || %{})

  defp metadata(%{a: a, b: b}, fun) when is_function(fun, 2),
    do: fun.(member_metadata(a) || %{}, member_metadata(b) || %{})

  defp member_metadata(nil), do: nil
  defp member_metadata(%Tempo{metadata: metadata}), do: metadata

  # ── Predicates on covered time ────────────────────────────────────────

  @doc """
  Whether an everyday predicate holds between two operands on their covered
  time: `:within` when nothing of the first lies outside the second,
  `:overlaps` when something lies in both, `:before` when the first ends no
  later than the second begins, `:adjacent` when the two meet, `:equal` when
  they cover the same points.
  """
  @spec holds?(atom(), [positioned()], [positioned()], frame()) :: boolean()
  def holds?(:within, a, b, frame), do: difference(a, b, frame) == []
  def holds?(:contains, a, b, frame), do: holds?(:within, b, a, frame)
  def holds?(:overlaps, a, b, frame), do: intersection(a, b, frame) != []
  def holds?(:disjoint, a, b, frame), do: not holds?(:overlaps, a, b, frame)

  def holds?(:equal, a, b, frame),
    do: extents(covered(a, 1, frame)) == extents(covered(b, 1, frame))

  def holds?(:before, a, b, _frame), do: a != [] and b != [] and last_stop(a) <= first_start(b)
  def holds?(:after, a, b, frame), do: holds?(:before, b, a, frame)

  def holds?(:adjacent, a, b, frame) do
    ca = extents(covered(a, 1, frame))
    cb = extents(covered(b, 1, frame))

    ca != [] and cb != [] and
      (elem(List.last(ca), 1) == elem(hd(cb), 0) or elem(List.last(cb), 1) == elem(hd(ca), 0))
  end

  defp extents(results), do: Enum.map(results, &{&1.start, &1.stop})
  defp last_stop(positioned), do: positioned |> Enum.map(& &1.stop) |> Enum.max()
  defp first_start(positioned), do: positioned |> Enum.map(& &1.start) |> Enum.min()

  @doc "The one extent of a singular operand, or the reason it has several or none."
  @spec single([positioned()], Tempo.t(), Tempo.t()) ::
          {:ok, {integer(), integer()}} | {:error, Exception.t()}
  def single([%{start: start, stop: stop}], _a, _b), do: {:ok, {start, stop}}
  def single(_several, a, b), do: {:error, FrameError.exception(a: a, b: b, reason: :several)}
end
