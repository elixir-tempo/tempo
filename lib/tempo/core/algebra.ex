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
    spans
    |> Enum.reduce_while({:ok, []}, fn span, {:ok, acc} ->
      case Spans.extent(span) do
        {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
          {:cont, {:ok, [%{start: start, stop: stop, span: span, side: side} | acc]}}

        {:ok, _open} ->
          {:halt, {:error, ConversionError.exception(value: span, reason: :open)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> in_order()
  end

  defp in_order({:ok, reversed}), do: {:ok, Enum.reverse(reversed)}
  defp in_order(error), do: error

  # An operand with no end, a recurrence or a set read from a stream, is
  # bounded by the window or by the other operand's whole stretch.
  defp window_for(expression, other, options) do
    if endless?(expression), do: options[:within] || stretch_of(other), else: options[:within]
  end

  # The stretch an operand covers, from its first span's start to its last
  # span's end: a set of appointments bounds a set of holidays by the days
  # from the first appointment to the last.
  defp stretch_of(%Tempo{form: {:all, members}} = set) when is_list(members) do
    case Spans.spans(set, []) do
      {:ok, spans} -> stretch_between(Enum.to_list(spans), set)
      {:error, _} -> set
    end
  end

  defp stretch_of(other), do: other

  defp stretch_between([%Tempo{form: {:span, from, _}} | _] = spans, set) do
    %Tempo{form: {:span, _, to}} = List.last(spans)
    %{set | form: {:span, from, to}}
  end

  defp stretch_between(_none, set), do: set

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

  defp one_frame(a, b, _pa, _pb, options), do: frames_agree(a, b, options)

  # Each operand is placed as its spans are: by the window, or one with no
  # end by the other operand's stretch.
  defp frames_agree(a, b, options) do
    a_placed = placed(a, window_for(a, b, options))
    b_placed = placed(b, window_for(b, a, options))
    agree(a, b, a_placed, b_placed)
  end

  # A rule with no start, or a set of such rules, has the frame of what it
  # is beside: the years of the other operand are its years.
  defp agree(a, b, a_placed, b_placed) do
    cond do
      placeless?(b_placed) and not placeless?(a_placed) -> frame_of(a_placed, a)
      placeless?(a_placed) and not placeless?(b_placed) -> frame_of(b_placed, b)
      true -> frames_of(a, b, framed(a_placed), framed(b_placed))
    end
  end

  # A set's frame is that of its members with a place of their own: those
  # with no start are placed by what they are beside.
  defp framed(%Tempo{form: {:all, [_ | _] = members}} = set) do
    case Enum.reject(members, &placeless_member?/1) do
      [] -> set
      placed -> %{set | form: {:all, placed}}
    end
  end

  defp framed(expression), do: expression

  defp placeless?(%Tempo{form: {:every, %Tempo{form: {:span, :open, _}}, _bound, _rule}}),
    do: true

  defp placeless?(%Tempo{form: {:all, [_ | _] = members}}),
    do: Enum.all?(members, &placeless_member?/1)

  defp placeless?(_expression), do: false

  defp placeless_member?(%Tempo{form: {:when, member, _conditions}}), do: placeless?(member)
  defp placeless_member?(member), do: placeless?(member)

  defp frames_of(a, b, a_placed, b_placed) do
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

  # ── Operands with no end ──────────────────────────────────────────────

  @doc "Whether an expression has no last span: a recurrence with no end, or a set read from a stream."
  @spec endless?(term()) :: boolean()
  def endless?(%Tempo{form: {:every, first, :infinity, _rule}}), do: not closed_domain?(first)

  # A set with a member that has no end has none: a territory's holidays,
  # rules that recur for ever.
  def endless?(%Tempo{form: {:all, members}}) when is_list(members),
    do: Enum.any?(members, &endless_member?/1)

  # A member with conditions, or a rule read in another calendar, ends where
  # its member does.
  def endless?(%Tempo{form: {:when, member, _conditions}}), do: endless?(member)
  def endless?(%Tempo{} = expression), do: Spans.lazy?(expression)
  def endless?(_other), do: false

  # A rule whose domain is years with a last (`R/{2015Y}/P1Y/F…`,
  # `{2020Y..2024Y}`) ends with them.
  defp closed_domain?(%Tempo{form: {:span, %Tempo{} = domain, _cadence}}), do: closed?(domain)
  defp closed_domain?(_first), do: false

  defp closed?(%Tempo{form: {:all, [_ | _] = members}}), do: Enum.all?(members, &closed_member?/1)
  defp closed?(%Tempo{form: {:when, inner, years: _filter}}), do: closed?(inner)
  defp closed?(_domain), do: false

  defp closed_member?({:except, _member}), do: true
  defp closed_member?(%Tempo{form: {:value, _units}}), do: true
  defp closed_member?(%Tempo{form: {:span, %Tempo{}, %Tempo{}}}), do: true
  defp closed_member?(_open), do: false

  defp endless_member?(%Tempo{form: {:when, member, _conditions}}), do: endless_member?(member)
  defp endless_member?(%Tempo{} = member), do: endless?(member)
  defp endless_member?(_exclusion), do: false

  @doc """
  How an operation is answered where an operand has no end and no window is
  given. A result is as bounded as the operation makes it: where it lies
  within a bounded operand (an intersection, and a difference from a bounded
  first operand) it is `:bounded`, and the operand with no end is taken
  within the other by `aligned/3`. Where it does not (a union, a symmetric
  difference, a difference from an operand with no end) the two operands
  are given as streams of positioned spans in the order of time, with their
  frame, for a result that has no end either. Of two operands with no end
  only the union is answered so: any other operation on them is an error,
  since two that never meet, or one that covers the other from some day on,
  are searched for ever for a result that is not there.
  """
  @spec streamed(atom(), Tempo.t(), Tempo.t(), keyword()) ::
          :bounded
          | {:ok, frame(), Enumerable.t(), Enumerable.t()}
          | {:error, Exception.t()}
  def streamed(operation, a, b, options) do
    with :ok <- operable(a, b) do
      if options[:within],
        do: :bounded,
        else: by_ends(operation, endless?(a), endless?(b), a, b)
    end
  end

  defp by_ends(_operation, false, false, _a, _b), do: :bounded

  # Two operands with no end are searched for ever where no result is come
  # to: two that never meet, or one that covers the other from some day on.
  # Only their union has a next member whatever they are.
  defp by_ends(operation, true, true, a, _b) when operation != :union,
    do: {:error, ConversionError.exception(value: a, reason: :unbounded)}

  defp by_ends(:intersection, _a_endless?, _b_endless?, _a, _b), do: :bounded
  defp by_ends(:difference, false, true, _a, _b), do: :bounded

  defp by_ends(_operation, _a_endless?, _b_endless?, a, b) do
    with {:ok, frame} <- frames_agree(a, b, []),
         {:ok, in_a} <- spans_in_order(a, :a),
         {:ok, in_b} <- spans_in_order(b, :b) do
      on_a_line(frame, in_a, in_b)
    end
  end

  # A cycle has an end to run through, and its operands are swept whole.
  defp on_a_line(%{length: nil} = frame, in_a, in_b), do: {:ok, frame, in_a, in_b}
  defp on_a_line(_cycle, _in_a, _in_b), do: :bounded

  # An operand's positioned spans in the order of time: a stream of them for
  # an operand with no end, whose spans come in that order, and the sorted
  # list for one that has an end.
  defp spans_in_order(expression, side) do
    if endless?(expression) do
      with {:ok, spans} <- Spans.spans(expression, []),
           do: {:ok, Stream.map(spans, &positioned!(&1, side))}
    else
      operand(expression, nil, side, [])
    end
  end

  defp positioned!(span, side) do
    case Spans.extent(span) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
        %{start: start, stop: stop, span: span, side: side}

      {:ok, _open} ->
        raise ConversionError.exception(value: span, reason: :open)

      {:error, exception} ->
        raise exception
    end
  end

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
       calendar: options[:calendar] || Tempo.Calendar.default(),
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

  @doc """
  A member brought to a frame's calendar and zone, for a set whose members
  are come to one at a time: what `gathered/2` does for each member of a
  list. A member that cannot be brought there raises its error.
  """
  @spec brought!(Tempo.t(), frame()) :: Tempo.t()
  def brought!(%Tempo{} = member, %{calendar: calendar, zone: zone}) do
    with {:ok, member} <- in_calendar(member, calendar) do
      in_zone(member, zone, {nil, member})
    end
    |> brought_or_raise()
  end

  defp brought_or_raise({:ok, member}), do: member
  defp brought_or_raise({:error, exception}), do: raise(exception)

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
  def union(a, b, frame), do: sweep(a, b, frame, fn da, db -> da > 0 or db > 0 end, :by_member)

  @doc "Every point in both operands."
  @spec intersection([positioned()], [positioned()], frame()) :: [result()]
  def intersection(a, b, frame),
    do: sweep(a, b, frame, fn da, db -> da > 0 and db > 0 end, :by_member)

  @doc "Every point in the first operand and not the second."
  @spec difference([positioned()], [positioned()], frame()) :: [result()]
  def difference(a, b, frame),
    do: sweep(a, b, frame, fn da, db -> da > 0 and db == 0 end, :by_member)

  @doc "Every point in exactly one operand."
  @spec symmetric_difference([positioned()], [positioned()], frame()) :: [result()]
  def symmetric_difference(a, b, frame),
    do: sweep(a, b, frame, fn da, db -> da > 0 != db > 0 end, :by_member)

  @doc "Every point covered by at least so many members of one operand."
  @spec covered([positioned()], pos_integer(), frame()) :: [result()]
  def covered(a, at_least, frame),
    do: sweep(a, [], frame, fn da, _db -> da >= at_least end, :joined)

  @doc "Positioned spans with the second half of a cut cycle span left out: one entry per member."
  @spec whole([positioned()]) :: [positioned()]
  def whole(positioned), do: Enum.reject(positioned, &(Map.get(&1, :half) == :second))

  @doc """
  The spans of positioned members sorted by position, each once. Equal
  members lie at the same position, so only the members at one position are
  compared: `Enum.uniq/1` over them all hashes every member whole, which was
  a quarter of a union's time.
  """
  @spec distinct([positioned()]) :: [Tempo.t()]
  def distinct(sorted) do
    sorted
    |> Enum.chunk_by(&{&1.start, &1.stop})
    |> Enum.flat_map(&distinct_at_one_position/1)
  end

  defp distinct_at_one_position([only]), do: [only.span]
  defp distinct_at_one_position(several), do: several |> Enum.map(& &1.span) |> Enum.uniq()

  @doc "The members of the first operand some point of which is in the second."
  @spec members_overlapping([positioned()], [positioned()]) :: [positioned()]
  def members_overlapping(a, b),
    do: Enum.filter(a, fn m -> Enum.any?(b, &overlapping?(m, &1)) end)

  @doc "The members of the first operand no point of which is in the second."
  @spec members_outside([positioned()], [positioned()]) :: [positioned()]
  def members_outside(a, b), do: Enum.reject(a, fn m -> Enum.any?(b, &overlapping?(m, &1)) end)

  defp overlapping?(x, y), do: Scale.overlap?({x.start, x.stop}, {y.start, y.stop})

  # The one sweep: the operands' edges position by position, every close and
  # open at a position applied before the point after it is judged, with the
  # members of each side covering it. A result is credited, on each side, to
  # the member covering its start that opened last. By member, it ends where
  # that member ends and the result goes on, so each keeps its own metadata
  # (decision 42); joined, it runs on, as the time covered does.
  defp sweep(a, b, frame, keep?, runs) do
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

        {%{} = open, true} when runs == :by_member ->
          {out, open} = recredited(out, open, covering, position, edges)
          {out, covering, open}

        _ ->
          {out, covering, open}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> joined(frame)
  end

  # A result whose member has ended while the result goes on is closed there,
  # and the rest credited to the members covering it now.
  defp recredited(out, open, covering, position, edges) do
    if member_ended?(open, covering) do
      closed = Map.merge(open, %{stop: position, closed: edge_model(edges, :close)})

      reopened = %{
        start: position,
        opened: edge_model(edges, :open),
        a: List.first(covering.a),
        b: List.first(covering.b)
      }

      {[closed | out], reopened}
    else
      {out, open}
    end
  end

  defp member_ended?(open, covering) do
    (open.a != nil and open.a not in covering.a) or (open.b != nil and open.b not in covering.b)
  end

  # ── The sweep, one result at a time ───────────────────────────────────

  @doc """
  The results of an operation over two operands given in the order of time,
  as a stream: the one sweep, taking each operand's next span as it is come
  to, for operands with no end. `:difference` and `:symmetric_difference`
  are swept; a result is given when it closes.
  """
  @spec swept(:difference | :symmetric_difference, Enumerable.t(), Enumerable.t()) ::
          Enumerable.t()
  def swept(operation, in_a, in_b) do
    keep? = kept(operation)

    Stream.resource(
      fn ->
        %{a: cursor(in_a), b: cursor(in_b), active: [], covering: %{a: [], b: []}, open: nil}
      end,
      &next_result(&1, keep?),
      &closed/1
    )
  end

  defp kept(:difference), do: fn in_a, in_b -> in_a > 0 and in_b == 0 end
  defp kept(:symmetric_difference), do: fn in_a, in_b -> in_a > 0 != in_b > 0 end

  @doc """
  The members of two operands given in the order of time, as one stream in
  that order; a member both hold, or one holds twice, is given once.
  """
  @spec merged(Enumerable.t(), Enumerable.t()) :: Enumerable.t()
  def merged(in_a, in_b) do
    fn -> %{a: cursor(in_a), b: cursor(in_b)} end
    |> Stream.resource(&next_member/1, &closed/1)
    |> Stream.transform({nil, []}, &once_at_its_place/2)
  end

  # Members that begin and end together are next to one another; of those,
  # one that is the same as one given before is not given again.
  defp once_at_its_place(%{start: start, stop: stop, span: span} = member, {{start, stop}, given}) do
    if span in given,
      do: {[], {{start, stop}, given}},
      else: {[member], {{start, stop}, [span | given]}}
  end

  defp once_at_its_place(%{start: start, stop: stop, span: span} = member, _elsewhere),
    do: {[member], {{start, stop}, [span]}}

  defp next_member(%{a: nil, b: nil} = state), do: {:halt, state}
  defp next_member(%{a: {member, _}, b: nil} = state), do: {[member], advanced(state, :a)}
  defp next_member(%{a: nil, b: {member, _}} = state), do: {[member], advanced(state, :b)}

  defp next_member(%{a: {from_a, _}, b: {from_b, _}} = state) do
    if {from_a.start, from_a.stop} <= {from_b.start, from_b.stop},
      do: {[from_a], advanced(state, :a)},
      else: {[from_b], advanced(state, :b)}
  end

  # The next position an edge stands at, the edges there applied, and the
  # result that closes there if one does.
  defp next_result(state, keep?) do
    case next_position(state) do
      nil -> {:halt, state}
      position -> at_position(state, position, keep?)
    end
  end

  defp next_position(%{a: a, b: b, active: active}) do
    [head_start(a), head_start(b) | Enum.map(active, & &1.stop)]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp head_start(nil), do: nil
  defp head_start({member, _continuation}), do: member.start

  # The closes at a position are applied and judged before its opens are,
  # so a result ends where the members covering it end, and a member that
  # begins there begins another. A sweep of operands that have an end joins
  # two such results into one span; here the join is not made, since members
  # that abut for ever (the weeks of a weekly rule) would be one span that
  # never closes.
  defp at_position(state, position, keep?) do
    {closing, active} = Enum.split_with(state.active, &(&1.stop == position))
    closes = for p <- closing, do: {position, :close, p.side, p}
    {ended, state} = edges_applied(%{state | active: active}, closes, keep?, position)

    {opening_a, state} = opening(state, :a, position, [])
    {opening_b, state} = opening(state, :b, position, [])
    opens = for p <- opening_a ++ opening_b, do: {position, :open, p.side, p}
    state = %{state | active: state.active ++ opening_a ++ opening_b}
    {ended_by_an_open, state} = edges_applied(state, opens, keep?, position)

    {ended ++ ended_by_an_open, state}
  end

  defp edges_applied(state, [], _keep?, _position), do: {[], state}

  defp edges_applied(state, edges, keep?, position) do
    covering =
      Enum.reduce(edges, state.covering, fn {_, kind, side, p}, acc ->
        step(acc, kind, side, p)
      end)

    state = %{state | covering: covering}
    turned(state, keep?.(length(covering.a), length(covering.b)), position, edges)
  end

  defp turned(%{open: nil} = state, true, position, edges) do
    opened = %{
      start: position,
      opened: edge_model(edges, :open),
      a: List.first(state.covering.a),
      b: List.first(state.covering.b)
    }

    {[], %{state | open: opened}}
  end

  # A result opened by a position's closes and closed by its opens has no
  # length, and is none.
  defp turned(%{open: %{start: position}} = state, false, position, _edges),
    do: {[], %{state | open: nil}}

  defp turned(%{open: %{} = open} = state, false, position, edges) do
    result = Map.merge(open, %{stop: position, closed: edge_model(edges, :close)})
    {[result], %{state | open: nil}}
  end

  defp turned(state, _as_before, _position, _edges), do: {[], state}

  # The spans of a side that begin at a position, taken from its stream.
  defp opening(state, side, position, taken) do
    case Map.fetch!(state, side) do
      {%{start: ^position} = member, _continuation} ->
        opening(advanced(state, side), side, position, [member | taken])

      _later_or_none ->
        {Enum.reverse(taken), state}
    end
  end

  # A stream held at its next member: the member and the rest, or nil at its end.
  defp cursor(enumerable) do
    advance(&Enumerable.reduce(enumerable, &1, fn member, _ -> {:suspend, member} end))
  end

  defp advance(continuation) do
    case continuation.({:cont, nil}) do
      {:suspended, member, continuation} -> {member, continuation}
      {_done_or_halted, _} -> nil
    end
  end

  defp advanced(state, side) do
    {_member, continuation} = Map.fetch!(state, side)
    Map.put(state, side, advance(continuation))
  end

  defp closed(state) do
    for {_member, continuation} <- [state.a, state.b], do: continuation.({:halt, nil})
    :ok
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

  @doc """
  What a predicate answers where an operand has no end and no window is
  given, without its being searched for: `{:ok, answer}` where the answer
  follows from the ends (what has no end is within nothing that has one,
  equals it never and is before it never; it is after it, or meets it,
  where it begins at or after the other's end), `:compare` where the answer
  lies within the operand that has an end and `holds?/4` gives it with the
  other taken there, and an error for two operands with no end.
  """
  @spec decided(atom(), Tempo.t(), Tempo.t(), keyword()) ::
          {:ok, boolean()} | :compare | {:error, Exception.t()}
  def decided(predicate, a, b, options) do
    with :ok <- operable(a, b) do
      if options[:within],
        do: :compare,
        else: by_end(predicate, endless?(a), endless?(b), a, b)
    end
  end

  defp by_end(_predicate, false, false, _a, _b), do: :compare

  defp by_end(_predicate, true, true, a, _b),
    do: {:error, ConversionError.exception(value: a, reason: :unbounded)}

  defp by_end(predicate, true, false, _a, _b) when predicate in [:within, :equal, :before],
    do: {:ok, false}

  defp by_end(predicate, false, true, _a, _b) when predicate in [:contains, :equal, :after],
    do: {:ok, false}

  defp by_end(:after, true, false, a, b), do: begins_after(a, b, &>=/2)
  defp by_end(:before, false, true, a, b), do: begins_after(b, a, &>=/2)
  defp by_end(:adjacent, true, false, a, b), do: begins_after(a, b, &==/2)
  defp by_end(:adjacent, false, true, a, b), do: begins_after(b, a, &==/2)
  defp by_end(_predicate, _a_endless?, _b_endless?, _a, _b), do: :compare

  # Whether what has no end begins where what has one ends, or after it.
  defp begins_after(endless, ended, compare) do
    with {:ok, _frame} <- frames_agree(endless, ended, []),
         {:ok, positioned} <- operand(ended, nil, :a, []),
         {:ok, spans} <- Spans.spans(endless, []) do
      {:ok, begins?(Enum.at(spans, 0), positioned, compare)}
    end
  end

  defp begins?(nil, _positioned, _compare), do: false
  defp begins?(_first, [], _compare), do: false

  defp begins?(%Tempo{} = first, positioned, compare),
    do: compare.(positioned!(first, :b).start, last_stop(positioned))

  defp extents(results), do: Enum.map(results, &{&1.start, &1.stop})
  defp last_stop(positioned), do: positioned |> Enum.map(& &1.stop) |> Enum.max()
  defp first_start(positioned), do: positioned |> Enum.map(& &1.start) |> Enum.min()

  @doc "The one extent of a singular operand, or the reason it has several or none."
  @spec single([positioned()], Tempo.t(), Tempo.t()) ::
          {:ok, {integer(), integer()}} | {:error, Exception.t()}
  def single([%{start: start, stop: stop}], _a, _b), do: {:ok, {start, stop}}
  def single(_several, a, b), do: {:error, FrameError.exception(a: a, b: b, reason: :several)}
end
