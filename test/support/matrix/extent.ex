defmodule Tempo.Matrix.Extent do
  @moduledoc """
  What a value, an interval or a set covers, measured apart from the code
  under test (see `plans/validated-core.md`).

  An extent is the half-open spans a value covers on a line, as pairs of
  whole microseconds, sorted, with touching and overlapping spans merged. A
  value with a year and a zone or an offset lies on the time line, where a
  position is counted from the proleptic Gregorian epoch in UTC. A value
  with a year and no zone is floating: it lies on a wall clock that is
  nowhere in particular, a line of its own, counted the same way. A value
  with no year lies on a cycle (the day for a time of day, the year for a
  month and a day, the week for a day of the week), where a position is
  counted from the cycle's start and a span that runs through the cycle's
  end is cut there.

  Positions are read from the units of a point with `Date`,
  `NaiveDateTime`, `DateTime` and Calendrical, and never with
  `Tempo.Compare`, so that an extent agreeing with an operation's answer
  is evidence about the operation.

  """

  alias Tempo.Interval
  alias Tempo.IntervalSet

  @microseconds 1_000_000
  @seconds_per_day 86_400
  @day @seconds_per_day * @microseconds

  # A walk longer than this is measured as far as it was taken.
  @walk_limit 3_000

  @type position :: integer()
  @type span :: {position(), position()}
  @type line :: :time | :floating | {:cycle, atom()}
  @type t :: %{line: line(), spans: [span()], whole?: boolean()}

  @doc """
  The extent an interval or an interval set covers.

  ### Arguments

  * `spans` is a `t:Tempo.Interval.t/0` or a `t:Tempo.IntervalSet.t/0`.

  ### Returns

  * `{:ok, extent}`, or `:none` for what has no extent to measure: an end
    that is absent or is not one point, a set without end, a position the
    standard library cannot give.

  """
  @spec of(term()) :: {:ok, t()} | :none
  def of(%Interval{} = interval), do: of_members([interval])

  def of(%IntervalSet{} = set) do
    if IntervalSet.bounded?(set), do: of_members(IntervalSet.members(set)), else: :none
  end

  def of(_other), do: :none

  @doc """
  The spans of each member of an interval or a set, unmerged, in the
  members' order.

  ### Arguments

  * `spans` is a `t:Tempo.Interval.t/0` or a `t:Tempo.IntervalSet.t/0`.

  ### Returns

  * `{:ok, line, [extent]}` with an extent for each member, or `:none`.

  """
  @spec members(term()) :: {:ok, [t()]} | :none
  def members(%Interval{} = interval), do: members_of([interval])

  def members(%IntervalSet{} = set) do
    if IntervalSet.bounded?(set), do: members_of(IntervalSet.members(set)), else: :none
  end

  def members(_other), do: :none

  defp members_of(intervals) do
    Enum.reduce_while(intervals, {:ok, []}, fn interval, {:ok, extents} ->
      case of_members([interval]) do
        {:ok, extent} -> {:cont, {:ok, [extent | extents]}}
        :none -> {:halt, :none}
      end
    end)
    |> case do
      {:ok, extents} -> {:ok, Enum.reverse(extents)}
      :none -> :none
    end
  end

  defp of_members([]), do: {:ok, %{line: :empty, spans: [], whole?: true}}

  defp of_members(intervals) do
    Enum.reduce_while(intervals, {:ok, nil, []}, fn interval, {:ok, line, spans} ->
      case interval_spans(interval) do
        {:ok, member_line, member_spans} when line in [nil, member_line] ->
          {:cont, {:ok, member_line, member_spans ++ spans}}

        _none_or_another_line ->
          {:halt, :none}
      end
    end)
    |> case do
      {:ok, line, spans} -> {:ok, %{line: line, spans: merge(spans), whole?: true}}
      :none -> :none
    end
  end

  defp interval_spans(%Interval{from: %Tempo{} = from, to: %Tempo{} = to}) do
    with {:ok, line, from_position} <- position(from),
         {:ok, ^line, to_position} <- position(to) do
      {:ok, line, on_line(line, from_position, to_position, from)}
    else
      _no_position -> :none
    end
  end

  defp interval_spans(_interval), do: :none

  # On the time line a span runs from its start to its end. On a cycle an
  # end that is not after the start is in the next turn, so the span runs to
  # the cycle's end and on from its start: one that ends where it starts is
  # once round.
  defp on_line(line, from, to, _point) when line in [:time, :floating], do: [{from, to}]

  defp on_line({:cycle, _unit}, from, to, _point) when from < to, do: [{from, to}]

  defp on_line({:cycle, unit}, from, to, point) do
    case cycle_length(unit, calendar_of(point)) do
      {:ok, length} -> [{from, length}, {0, to}]
      :none -> [{from, to}]
    end
  end

  @doc """
  The extent a value's walk covers: each value the walk yields is the span
  of its finest unit, and the extent is their union.

  ### Arguments

  * `value` is anything `Enum` walks.

  ### Returns

  * `{:ok, extent}`, whose `:whole?` is false when the walk was longer than
    the limit and was measured as far as it was taken, or `:none`.

  """
  @spec of_walk(term()) :: {:ok, t()} | :none
  def of_walk(value) do
    yielded = Enum.take(value, @walk_limit + 1)
    whole? = length(yielded) <= @walk_limit

    yielded
    |> Enum.take(@walk_limit)
    |> Enum.reduce_while({:ok, nil, []}, fn element, {:ok, line, spans} ->
      case element_span(element) do
        {:ok, element_line, element_spans} when line in [nil, element_line] ->
          {:cont, {:ok, element_line, element_spans ++ spans}}

        _none_or_another_line ->
          {:halt, :none}
      end
    end)
    |> case do
      {:ok, nil, []} -> {:ok, %{line: :empty, spans: [], whole?: whole?}}
      {:ok, line, spans} -> {:ok, %{line: line, spans: merge(spans), whole?: whole?}}
      :none -> :none
    end
  end

  defp element_span(%Tempo{} = point) do
    with {:ok, line, from} <- position(point),
         {:ok, to} <- unit_end(line, point, from) do
      {:ok, line, [{from, to}]}
    else
      _no_span -> :none
    end
  end

  defp element_span(%Interval{} = interval), do: interval_spans(interval)
  defp element_span(_other), do: :none

  ## Set algebra and relations on extents

  @doc """
  The union of two extents on one line.
  """
  @spec union(t(), t()) :: t()
  def union(a, b), do: %{a | line: line(a, b), spans: merge(a.spans ++ b.spans)}

  @doc """
  The spans both extents cover.
  """
  @spec intersection(t(), t()) :: t()
  def intersection(a, b), do: %{a | line: line(a, b), spans: shared(a.spans, b.spans, [])}

  # An extent's spans are in order and apart, so two extents are swept
  # together: the span that ends first is done with.
  defp shared([{a_from, a_to} | a_rest] = a, [{b_from, b_to} | b_rest] = b, spans) do
    spans = overlap(max(a_from, b_from), min(a_to, b_to), spans)

    if a_to <= b_to,
      do: shared(a_rest, b, spans),
      else: shared(a, b_rest, spans)
  end

  defp shared(_a, _b, spans), do: Enum.reverse(spans)

  defp overlap(from, to, spans) when from < to, do: [{from, to} | spans]
  defp overlap(_from, _to, spans), do: spans

  @doc """
  The spans of `a` that `b` does not cover.
  """
  @spec difference(t(), t()) :: t()
  def difference(a, b), do: %{a | line: line(a, b), spans: without(a.spans, b.spans, [])}

  # A cut that ends before the span starts is done with, one that starts
  # after it ends leaves the span whole, and any other takes its part of it.
  defp without([{from, _to} | _rest] = a, [{_cut_from, cut_to} | cuts], kept)
       when cut_to <= from,
       do: without(a, cuts, kept)

  defp without([{_from, to} = span | rest], [{cut_from, _cut_to} | _cuts] = b, kept)
       when cut_from >= to,
       do: without(rest, b, [span | kept])

  defp without([{from, to} | rest], [{cut_from, cut_to} | cuts] = b, kept) do
    kept = overlap(from, cut_from, kept)

    if cut_to < to,
      do: without([{cut_to, to} | rest], cuts, kept),
      else: without(rest, b, kept)
  end

  defp without(a, [], kept), do: Enum.reverse(kept, a)
  defp without([], _b, kept), do: Enum.reverse(kept)

  @doc """
  Whether two extents lie on one line, and so can be combined or compared.
  An extent of no spans lies on any.
  """
  @spec same_line?(t(), t()) :: boolean()
  def same_line?(%{line: :empty}, _b), do: true
  def same_line?(_a, %{line: :empty}), do: true
  def same_line?(%{line: line}, %{line: line}), do: true
  def same_line?(_a, _b), do: false

  defp line(%{line: :empty}, %{line: line}), do: line
  defp line(%{line: line}, _b), do: line

  @doc """
  The Allen relation of two extents that are each one span.

  ### Returns

  * One of the thirteen relation atoms, or `:none` when either extent is
    not one span.

  """
  @spec relation(t(), t()) :: atom()
  def relation(%{spans: [{a_from, a_to}]}, %{spans: [{b_from, b_to}]}) do
    cond do
      a_to < b_from -> :precedes
      a_to == b_from -> :meets
      a_from > b_to -> :preceded_by
      a_from == b_to -> :met_by
      true -> overlapping(compare(a_from, b_from), compare(a_to, b_to))
    end
  end

  def relation(_a, _b), do: :none

  defp overlapping(:lt, :lt), do: :overlaps
  defp overlapping(:lt, :eq), do: :finished_by
  defp overlapping(:lt, :gt), do: :contains
  defp overlapping(:eq, :lt), do: :starts
  defp overlapping(:eq, :eq), do: :equals
  defp overlapping(:eq, :gt), do: :started_by
  defp overlapping(:gt, :lt), do: :during
  defp overlapping(:gt, :eq), do: :finishes
  defp overlapping(:gt, :gt), do: :overlapped_by

  @doc """
  The order of two positions: `:lt`, `:eq` or `:gt`.
  """
  @spec compare(position(), position()) :: :lt | :eq | :gt
  def compare(a, b) when a < b, do: :lt
  def compare(a, b) when a > b, do: :gt
  def compare(_a, _b), do: :eq

  @doc """
  The microseconds an extent covers.
  """
  @spec microseconds(t()) :: non_neg_integer()
  def microseconds(%{spans: spans}),
    do: spans |> Enum.map(fn {from, to} -> to - from end) |> Enum.sum()

  @doc """
  The start and end of each member of an interval or a set as they are
  written on their line, an end that is not after its start left where it
  is written and not cut at the cycle's end.

  ### Arguments

  * `spans` is a `t:Tempo.Interval.t/0` or a `t:Tempo.IntervalSet.t/0`.

  ### Returns

  * `{:ok, line, spans}` or `:none`.

  """
  @spec written(term()) :: {:ok, line(), [span()]} | :none
  def written(%Interval{} = interval), do: written_members([interval])

  def written(%IntervalSet{} = set) do
    if IntervalSet.bounded?(set), do: written_members(IntervalSet.members(set)), else: :none
  end

  def written(_other), do: :none

  defp written_members(intervals) do
    Enum.reduce_while(intervals, {:ok, nil, []}, fn interval, {:ok, line, spans} ->
      with %Interval{from: %Tempo{} = from, to: %Tempo{} = to} <- interval,
           {:ok, member_line, from_position} when line in [nil, member_line] <- position(from),
           {:ok, ^member_line, to_position} <- position(to) do
        {:cont, {:ok, member_line, [{from_position, to_position} | spans]}}
      else
        _no_position -> {:halt, :none}
      end
    end)
  end

  @doc """
  Times of day placed on each day a window on the time line touches, as
  the set operations place them with `:within`: a span starts on the day
  it is placed on, and one whose end is not after its start (`T22H/T2H`)
  runs into the next.

  ### Arguments

  * `daily` is the spans of times of day, as `written/1` gives them.

  * `window` is an extent on the time line.

  ### Returns

  * An extent on the time line. The days are UTC's, so it is the placing
    of a value with no zone on a window with none.

  """
  @spec on_each_day([span()], t()) :: t()
  def on_each_day(daily, %{line: line, spans: window}) when line in [:time, :floating] do
    placed =
      for {window_from, window_to} <- window,
          day <- Integer.floor_div(window_from, @day)..Integer.floor_div(window_to - 1, @day)//1,
          {from, to} <- daily do
        if to > from,
          do: {day * @day + from, day * @day + to},
          else: {day * @day + from, (day + 1) * @day + to}
      end

    %{line: line, spans: merge(placed), whole?: true}
  end

  @doc """
  An extent kept up to a position, for comparing with a walk that was not
  taken to its end.
  """
  @spec up_to(t(), position()) :: t()
  def up_to(%{spans: spans} = extent, limit) do
    kept = for {from, to} <- spans, from < limit, do: {from, min(to, limit)}
    %{extent | spans: kept}
  end

  ## Positions

  @doc """
  The position of a point on its line.

  ### Arguments

  * `point` is a `t:Tempo.t/0` each of whose units is one whole number.

  ### Returns

  * `{:ok, line, position}` or `:none`.

  """
  @spec position(Tempo.t()) :: {:ok, line(), position()} | :none
  def position(%Tempo{time: [{:year, :any} | rest]} = point),
    do: cycle_position(%{point | time: rest})

  def position(%Tempo{time: [{:year, year} | _rest] = time} = point) when is_integer(year) do
    with true <- whole?(time),
         {:ok, date} <- date_of(time, calendar_of(point)),
         {:ok, offset} <- offset_of(point, date, clock_seconds(time)) do
      seconds = Date.to_gregorian_days(date) * @seconds_per_day + clock_seconds(time) - offset
      {:ok, frame(point), seconds * @microseconds + fraction(time)}
    else
      _no_position -> :none
    end
  end

  def position(%Tempo{} = point), do: cycle_position(point)

  # A value with a zone or an offset is on the time line, and one with
  # neither on the wall clock of nowhere in particular.
  defp frame(%Tempo{shift: shift}) when is_list(shift), do: :time

  defp frame(%Tempo{extended: %{zone_id: zone}}) when is_binary(zone) and zone != "", do: :time
  defp frame(%Tempo{extended: %{zone_offset: offset}}) when is_integer(offset), do: :time
  defp frame(%Tempo{}), do: :floating

  defp whole?(time) do
    Enum.all?(time, fn
      {:year, value} -> is_integer(value)
      {:microsecond, {value, precision}} -> is_integer(value) and is_integer(precision)
      {_unit, value} -> is_integer(value) and value >= 0
      _other -> false
    end)
  end

  defp calendar_of(%Tempo{calendar: nil}), do: Calendrical.Gregorian
  defp calendar_of(%Tempo{calendar: Calendar.ISO}), do: Calendrical.Gregorian
  defp calendar_of(%Tempo{calendar: calendar}), do: calendar

  # The date a time list names, in `Calendar.ISO`: a month and a day, a week
  # and a day of the week, or a day of the year, with what is absent the
  # first.
  defp date_of(time, calendar), do: date_on(axis(Keyword.keys(time)), time, calendar)

  defp axis(units) do
    Enum.find(
      [:month_and_week, :month, :week, :day_of_year, :day, :day_of_week],
      :year,
      &on_axis?(&1, units)
    )
  end

  defp on_axis?(:month_and_week, units), do: :month in units and :week in units
  defp on_axis?(unit, units), do: unit in units

  # A month with a day is the date. A month with no day is its first date,
  # which in a year that starts within its months is the first date of the
  # nth month the calendar counts.
  defp date_on(:month, time, calendar) do
    case time[:day] do
      nil -> first_of_month(time[:year], time[:month], calendar)
      day -> calendar_date(time[:year], time[:month], day, calendar)
    end
  end

  defp date_on(:week, time, calendar),
    do: week_date(time[:year], time[:week], time[:day_of_week] || time[:day] || 1, calendar)

  defp date_on(:day_of_year, time, calendar),
    do: day_of_year(time[:year], time[:day_of_year], calendar)

  defp date_on(:day, time, calendar), do: day_of_year(time[:year], time[:day], calendar)
  defp date_on(:year, time, calendar), do: first_of_year(time[:year], calendar)

  # A week of a month, or a day of the week with no week, is no date here.
  defp date_on(_another_axis, _time, _calendar), do: :none

  # In a calendar whose year starts within its months (a Julian year from
  # 25 March), a year begins on the first date the calendar's `year/1`
  # gives, and a month with no day is the nth month it counts, the dates of
  # its `month/2`; a date keeps the month it names (decided 2026-10-04).
  defp first_of_year(year, calendar) do
    case year_within_its_months(year, calendar) do
      %Date.Range{first: first} -> converted(first)
      nil -> calendar_date(year, 1, 1, calendar)
    end
  end

  defp first_of_month(year, month, calendar) do
    case year_within_its_months(year, calendar) do
      %Date.Range{} -> first_of_counted_month(calendar.month(year, month))
      nil -> calendar_date(year, month, 1, calendar)
    end
  end

  defp first_of_counted_month(%Date.Range{first: first}), do: converted(first)
  defp first_of_counted_month(_no_month), do: :none

  # The dates of a year that does not begin on the first day of its first
  # month, and `nil` for a year that does.
  defp year_within_its_months(_year, Calendrical.Gregorian), do: nil

  defp year_within_its_months(year, calendar) do
    with true <- function_exported?(calendar, :year, 1),
         %Date.Range{first: %Date{month: month, day: day}} = dates <- calendar.year(year),
         true <- {month, day} != {1, 1} do
      dates
    else
      _a_year_from_its_first_month -> nil
    end
  end

  defp calendar_date(year, month, day, calendar) do
    with {:ok, date} <- Date.new(year, month, day, calendar),
         {:ok, iso} <- Date.convert(date, Calendar.ISO) do
      {:ok, iso}
    else
      _no_date -> :none
    end
  end

  # A calendar of weeks holds the week where a date holds its month. In a
  # calendar of months the week is ISO 8601's: weeks from Monday, the first
  # the one that holds 4 January.
  defp week_date(year, week, day, calendar) do
    if calendar.calendar_base() == :week do
      calendar_date(year, week, day, calendar)
    else
      with Calendrical.Gregorian <- calendar,
           {:ok, fourth} <- Date.new(year, 1, 4) do
        {:ok, fourth |> Date.beginning_of_week(:monday) |> Date.add((week - 1) * 7 + day - 1)}
      else
        _no_date -> :none
      end
    end
  end

  defp day_of_year(year, day, Calendrical.Gregorian) do
    case Date.new(year, 1, 1) do
      {:ok, first} -> {:ok, Date.add(first, day - 1)}
      _no_date -> :none
    end
  end

  defp day_of_year(year, day, calendar) do
    case Calendrical.date_from_day_of_year(year, day, calendar) do
      %Date{} = date -> converted(date)
      {:ok, %Date{} = date} -> converted(date)
      _no_date -> :none
    end
  end

  defp converted(date) do
    case Date.convert(date, Calendar.ISO) do
      {:ok, iso} -> {:ok, iso}
      _no_date -> :none
    end
  end

  defp clock_seconds(time),
    do: (time[:hour] || 0) * 3_600 + (time[:minute] || 0) * 60 + (time[:second] || 0)

  defp fraction(time) do
    case List.keyfind(time, :microsecond, 0) do
      {:microsecond, {value, _precision}} -> value
      nil -> 0
    end
  end

  # The seconds a point's wall time is ahead of UTC: its zone's offset at
  # that wall time, or the offset it is written with, or none.
  defp offset_of(%Tempo{extended: %{zone_id: zone} = extended, shift: shift}, date, seconds)
       when is_binary(zone) and zone != "" do
    zone_offset(zone, date, seconds, stated_offset(extended, shift))
  end

  defp offset_of(%Tempo{extended: extended, shift: shift}, _date, _seconds),
    do: {:ok, stated_offset(extended, shift) || 0}

  defp stated_offset(%{zone_offset: minutes}, _shift) when is_integer(minutes), do: minutes * 60
  defp stated_offset(_extended, shift) when is_list(shift), do: shift_seconds(shift)
  defp stated_offset(_extended, _shift), do: nil

  # A shift's sign is on its first unit that is not zero: `-05:30` is
  # `[hour: -5, minute: 30]`.
  defp shift_seconds(shift) do
    parts = [shift[:hour] || 0, shift[:minute] || 0, shift[:second] || 0]
    sign = if Enum.find(parts, 0, &(&1 != 0)) < 0, do: -1, else: 1
    [hour, minute, second] = Enum.map(parts, &abs/1)
    sign * (hour * 3_600 + minute * 60 + second)
  end

  # Before the common era no zone has a rule, and a wall time is UTC's.
  defp zone_offset(_zone, %Date{year: year}, _seconds, _stated) when year < 1, do: {:ok, 0}

  defp zone_offset(zone, date, seconds, stated) do
    naive = NaiveDateTime.add(NaiveDateTime.new!(date, ~T[00:00:00]), seconds)

    case DateTime.from_naive(naive, zone) do
      {:ok, datetime} -> {:ok, total_offset(datetime)}
      {:ambiguous, first, second} -> {:ok, ambiguous_offset(first, second, stated)}
      {:gap, before, _later} -> {:ok, total_offset(before)}
      {:error, _reason} -> :none
    end
  end

  # A wall time a clock skips when it goes forward is read with the offset in
  # force before the skip, which places it at the moment the clock went
  # forward. One a clock shows twice when it goes back is the first, unless
  # the offset written with it is the second's.
  defp ambiguous_offset(first, second, stated) do
    if total_offset(second) == stated, do: total_offset(second), else: total_offset(first)
  end

  defp total_offset(%DateTime{utc_offset: utc, std_offset: std}), do: utc + std

  ## The end of the unit a point is written to

  # On the time line the unit after a point's finest is counted on the wall
  # clock and placed in the point's zone: the day a clock goes forward has
  # twenty-three hours.
  defp unit_end(line, %Tempo{time: time} = point, from) when line in [:time, :floating] do
    case List.last(time) do
      {:microsecond, {_value, precision}} -> {:ok, from + Integer.pow(10, 6 - precision)}
      {unit, _value} -> next_wall(unit, point)
    end
  end

  defp unit_end({:cycle, _unit}, %Tempo{time: time} = point, from) do
    {_year, time} = without_unspecified_year(time)

    case List.last(time) do
      {:microsecond, {_value, precision}} -> {:ok, from + Integer.pow(10, 6 - precision)}
      {:hour, _value} -> {:ok, from + 3_600 * @microseconds}
      {:minute, _value} -> {:ok, from + 60 * @microseconds}
      {:second, _value} -> {:ok, from + @microseconds}
      {:month, month} -> month_length(month, calendar_of(point), from)
      {unit, _value} when unit in [:day, :day_of_week] -> {:ok, from + @day}
      _other -> :none
    end
  end

  defp month_length(month, calendar, from) do
    case longest_month(month, calendar) do
      {:ok, days} -> {:ok, from + days * @day}
      :none -> :none
    end
  end

  defp next_wall(unit, %Tempo{time: time} = point) when unit in [:hour, :minute, :second] do
    step = %{hour: 3_600, minute: 60, second: 1}[unit]

    with {:ok, date} <- date_of(time, calendar_of(point)) do
      seconds = clock_seconds(time) + step

      placed(
        point,
        Date.add(date, div(seconds, @seconds_per_day)),
        rem(seconds, @seconds_per_day)
      )
    end
  end

  defp next_wall(:year, %Tempo{time: time} = point) do
    with {:ok, date} <- calendar_date(time[:year] + 1, 1, 1, calendar_of(point)),
         do: placed(point, date, 0)
  end

  defp next_wall(:month, %Tempo{time: time} = point) do
    calendar = calendar_of(point)
    {year, month} = {time[:year], time[:month]}

    next =
      if month >= calendar.months_in_year(year),
        do: calendar_date(year + 1, 1, 1, calendar),
        else: calendar_date(year, month + 1, 1, calendar)

    with {:ok, date} <- next, do: placed(point, date, 0)
  end

  defp next_wall(:week, %Tempo{time: time} = point) do
    with {:ok, date} <- date_of(time, calendar_of(point)), do: placed(point, Date.add(date, 7), 0)
  end

  defp next_wall(unit, %Tempo{time: time} = point)
       when unit in [:day, :day_of_week, :day_of_year] do
    with {:ok, date} <- date_of(time, calendar_of(point)), do: placed(point, Date.add(date, 1), 0)
  end

  defp next_wall(_unit, _point), do: :none

  defp placed(point, date, seconds) do
    case offset_of(point, date, seconds) do
      {:ok, offset} ->
        {:ok,
         (Date.to_gregorian_days(date) * @seconds_per_day + seconds - offset) * @microseconds}

      :none ->
        :none
    end
  end

  ## Positions on a cycle

  # A point with no year is counted from the start of the cycle its leading
  # unit turns in: an hour from midnight, a month from the year's first day,
  # a day of the week from the week's first. A month's days are counted in
  # the longest year, so that every date a year can hold has a place.
  defp cycle_position(%Tempo{time: [{unit, _value} | _rest] = time} = point) do
    with true <- whole?(time),
         {:ok, days} <- cycle_days(time, calendar_of(point)) do
      {:ok, {:cycle, unit},
       (days * @seconds_per_day + clock_seconds(time)) * @microseconds + fraction(time)}
    else
      _no_position -> :none
    end
  end

  defp cycle_position(_point), do: :none

  defp cycle_days([{unit, _value} | _rest], _calendar) when unit in [:hour, :minute, :second],
    do: {:ok, 0}

  defp cycle_days([{:day_of_week, day} | _rest], _calendar), do: {:ok, day - 1}

  defp cycle_days([{:month, month} | rest], calendar) do
    day = rest[:day] || 1

    with {:ok, before} <- days_before(month, calendar), do: {:ok, before + day - 1}
  end

  defp cycle_days(_time, _calendar), do: :none

  defp days_before(month, calendar) do
    Enum.reduce_while(1..(month - 1)//1, {:ok, 0}, fn earlier, {:ok, days} ->
      case longest_month(earlier, calendar) do
        {:ok, more} -> {:cont, {:ok, days + more}}
        :none -> {:halt, :none}
      end
    end)
  end

  defp longest_month(month, calendar) do
    case calendar.days_in_month(month) do
      days when is_integer(days) -> {:ok, days}
      {:ambiguous, %Range{first: first, last: last}} -> {:ok, max(first, last)}
      _undefined -> :none
    end
  end

  defp cycle_length(:hour, _calendar), do: {:ok, @day}
  defp cycle_length(:minute, _calendar), do: {:ok, 3_600 * @microseconds}
  defp cycle_length(:second, _calendar), do: {:ok, 60 * @microseconds}
  defp cycle_length(:day_of_week, calendar), do: {:ok, calendar.days_in_week() * @day}

  defp cycle_length(:month, calendar) do
    case calendar.months_in_year() do
      months when is_integer(months) ->
        with {:ok, days} <- days_before(months + 1, calendar), do: {:ok, days * @day}

      _varies ->
        :none
    end
  end

  defp cycle_length(_unit, _calendar), do: :none

  defp without_unspecified_year([{:year, :any} = year | rest]), do: {[year], rest}
  defp without_unspecified_year(time), do: {[], time}

  ## Merging

  # Spans in order, with none empty and none touching or overlapping the
  # next.
  defp merge(spans) do
    spans
    |> Enum.filter(fn {from, to} -> from < to end)
    |> Enum.sort()
    |> Enum.reduce([], fn
      {from, to}, [{last_from, last_to} | merged] when from <= last_to ->
        [{last_from, max(to, last_to)} | merged]

      span, merged ->
        [span | merged]
    end)
    |> Enum.reverse()
  end
end
