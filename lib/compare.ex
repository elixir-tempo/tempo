defmodule Tempo.Compare do
  @moduledoc """
  Shared comparison primitives for Tempo values.

  Set operations, enumeration, and IntervalSet construction all
  need to compare two time keyword lists as start-moments on the
  time line. This module is the single place that definition
  lives. The comparison treats missing trailing units as their
  unit minimum — so `[year: 2022]` (which means "start of 2022")
  compares correctly against `[year: 2022, month: 6]` (which
  means "start of June 2022") without ambiguity.

  For set operations that span timezones, `to_utc_seconds/1`
  projects a zoned `%Tempo{}` into gregorian-seconds-since-UTC
  epoch so operands in different zones can share a total order.
  The projection is computed on demand and never cached — that
  policy decision was made in the implicit-to-explicit plan and
  revisited in the set-operations plan.

  The same projection makes comparison calendar-independent:
  when two values are in different calendars, each is routed
  through its calendar's date→absolute-day conversion (the
  `date_to_iso_days` round-trip) before comparison, so a Hebrew
  and a Gregorian date order by their true instants rather than
  by their raw numeric components. Same-calendar comparison keeps
  the fast structural path on the `:time` lists.

  """

  alias Calendrical.Gregorian
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.FloatingTempoError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnanchoredError
  alias Tempo.UnitValues
  alias Tempo.Validation
  alias Tempo.ZoneOffsetMismatchError

  @doc """
  Compare two time keyword lists as start-moments on the time
  line.

  Missing trailing units are filled with their unit minimum
  (`:month` / `:day` / `:week` / `:day_of_year` / `:day_of_week`
  count from 1; everything else counts from 0). Both lists must
  be sorted descending-by-unit — the invariant the tokenizer and
  `Unit.sort/2` maintain.

  A unit one list has and the other skips is at its minimum in the
  list that skips it, as a unit left off the end is: `[year: 2026,
  hour: 17]` is 17:00 on the first day of the year's first month.

  Units of one level on two axes at the same position (`:week` and
  `:month`, a day of the month and a day of the week) fall through
  to `:eq` as a conservative bailout. A well-formed comparison has
  operands using the same unit vocabulary.

  ### Arguments

  * `a` and `b` are keyword lists like `[year: 2022, month: 6]`.

  ### Returns

  * `:lt` when `a` is earlier than `b`.

  * `:gt` when `a` is later than `b`.

  * `:eq` when they are the same start-moment, or when mismatched
    unit vocabularies prevent a meaningful order.

  ### Examples

      iex> Tempo.Compare.compare_time([year: 2022], [year: 2022, month: 6])
      :lt

      iex> Tempo.Compare.compare_time([year: 2022, month: 6, day: 15], [year: 2022, month: 6, day: 15])
      :eq

      iex> Tempo.Compare.compare_time([year: 2023], [year: 2022, month: 12])
      :gt

      iex> Tempo.Compare.compare_time([year: 2026, hour: 17], [year: 2026, month: 3, day: 1, hour: 17])
      :lt

  """
  @spec compare_time(keyword(), keyword()) :: :lt | :eq | :gt
  def compare_time([], []), do: :eq

  # Microseconds compare by VALUE only. Precision (digit count) sets
  # the interval width, not the instant ordering: `{120000, 2}` (.12)
  # and `{120000, 3}` (.120) denote the same start moment, so they
  # compare equal here. Generic tuple comparison would (wrongly) order
  # them by precision, so these clauses precede the generic ones.
  def compare_time([{:microsecond, {v1, _p1}} | t1], [{:microsecond, {v2, _p2}} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  def compare_time([{:microsecond, {v, _p}} | rest], []) do
    if v > 0, do: :gt, else: compare_time(rest, [])
  end

  def compare_time([], [{:microsecond, {v, _p}} | rest]) do
    if v > 0, do: :lt, else: compare_time([], rest)
  end

  def compare_time([{unit, v} | rest], []) do
    min = unit_minimum(unit)

    cond do
      v < min -> :lt
      v > min -> :gt
      true -> compare_time(rest, [])
    end
  end

  def compare_time([], [{unit, v} | rest]) do
    min = unit_minimum(unit)

    cond do
      min < v -> :lt
      min > v -> :gt
      true -> compare_time([], rest)
    end
  end

  def compare_time([{unit, v1} | t1], [{unit, v2} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  def compare_time([{unit_a, v1} | t1] = a, [{unit_b, v2} | t2] = b)
      when is_integer(v1) and is_integer(v2) do
    case skipped(unit_a, unit_b) do
      :by_second -> from_minimum(v1, unit_minimum(unit_a), t1, b)
      :by_first -> from_minimum(unit_minimum(unit_b), v2, a, t2)
      :by_neither -> :eq
    end
  end

  def compare_time(_, _), do: :eq

  defp from_minimum(v1, v2, _a, _b) when v1 < v2, do: :lt
  defp from_minimum(v1, v2, _a, _b) when v1 > v2, do: :gt
  defp from_minimum(_v1, _v2, a, b), do: compare_time(a, b)

  # How coarse a unit is, by level: the units of one level are the same
  # stretch of time on different axes, and no one of them is skipped where
  # another is written.
  @unit_levels %{
    year: 6,
    month: 5,
    week: 5,
    day: 4,
    day_of_year: 4,
    day_of_week: 4,
    hour: 3,
    minute: 2,
    second: 1
  }

  # Which of two lists skips the unit the other leads with: the one whose
  # own leading unit is finer.
  defp skipped(unit_a, unit_b) do
    case {@unit_levels[unit_a], @unit_levels[unit_b]} do
      {a, b} when is_integer(a) and is_integer(b) and a > b -> :by_second
      {a, b} when is_integer(a) and is_integer(b) and a < b -> :by_first
      _same_level_or_unknown -> :by_neither
    end
  end

  @doc """
  The start-of-unit minimum — 1 for `:month`, `:day`, `:week`,
  `:day_of_year`, `:day_of_week`; 0 for everything else.

  Exposed on `Tempo.Compare` and on the internal arithmetic module
  as the same definition (both re-export via delegation).

  """
  @spec unit_minimum(atom()) :: integer()
  def unit_minimum(:month), do: 1
  def unit_minimum(:day), do: 1
  def unit_minimum(:week), do: 1
  def unit_minimum(:day_of_year), do: 1
  def unit_minimum(:day_of_week), do: 1
  def unit_minimum(_), do: 0

  @doc false
  # Which of two dates is the earlier day, by the days their calendars count
  # (`Date.diff/2`), as Calendrical orders them. `Date.compare/2` orders two
  # dates of one calendar by their fields without asking the calendar, and
  # the fields are not in the order of the days where a year turns after its
  # first month: in `Calendrical.Julian.March25`, 1 January follows 31
  # December of the same year.
  @spec compare_days(Date.t(), Date.t()) :: :lt | :eq | :gt
  def compare_days(%Date{} = date, %Date{} = other) do
    case Date.diff(date, other) do
      0 -> :eq
      days when days < 0 -> :lt
      _days -> :gt
    end
  end

  @doc """
  Return `:earlier`, `:later`, or `:same` for two `%Tempo{}`
  endpoints comparing by their UTC-projected start-moments.

  When both Tempos share a zone (or both have `nil` zone info),
  this reduces to `compare_time/2` on their `:time` lists with a
  renamed return. When zones differ, both sides are projected to
  UTC via `to_utc_seconds/1` for a common reference frame.

  A value that is not one point (a mask, a group, a set, significant
  digits) compares as the point its span starts at, the start of what
  `Tempo.to_interval/1` gives it.

  ### Arguments

  * `a` and `b` are `%Tempo{}` structs, typically interval
    endpoints.

  ### Returns

  * `:earlier`, `:later`, or `:same`.

  * Raises a `Tempo.UnanchoredError` when the two share no line to be
    ordered on (one has a year and the other none, or neither has and
    they lead with different units), and the error `Tempo.to_interval/1`
    returns for a value whose span starts at no point. `order/2` returns
    the same errors.

  """
  @spec compare_endpoints(Tempo.t(), Tempo.t()) :: :earlier | :later | :same
  def compare_endpoints(%Tempo{time: a_time} = a, %Tempo{time: b_time} = b) do
    if whole?(a_time) and whole?(b_time) and same_line?(a_time, b_time) do
      order_points(a, b)
    else
      case order(a, b) do
        {:ok, order} -> order
        {:error, exception} -> raise exception
      end
    end
  end

  @doc false
  # `compare_endpoints/2` for a caller with an error to return: the order of
  # two values, or why they have none.
  @spec order(Tempo.t(), Tempo.t()) ::
          {:ok, :earlier | :later | :same} | {:error, Exception.t()}
  def order(%Tempo{time: a_time} = a, %Tempo{time: b_time} = b) do
    if whole?(a_time) and whole?(b_time) do
      order_on_one_line(a, b)
    else
      with {:ok, a} <- crisp_point(a),
           {:ok, b} <- crisp_point(b) do
        order_on_one_line(a, b)
      end
    end
  end

  @doc false
  # Whether two values have an order, for a caller about to sort by it:
  # `:ok`, or the error `order/2` returns. Two dated points are in order as
  # they stand, so they are passed without being compared.
  @spec orderable(Tempo.t(), Tempo.t()) :: :ok | {:error, Exception.t()}
  def orderable(
        %Tempo{time: [{:year, a_year} | a_rest]} = a,
        %Tempo{time: [{:year, b_year} | b_rest]} = b
      )
      when is_integer(a_year) and is_integer(b_year) do
    if whole_units?(a_rest) and whole_units?(b_rest), do: :ok, else: orderable_read(a, b)
  end

  def orderable(%Tempo{} = a, %Tempo{} = b), do: orderable_read(a, b)

  defp orderable_read(a, b) do
    with {:ok, _order} <- order(a, b), do: :ok
  end

  defp order_on_one_line(%Tempo{} = a, %Tempo{} = b) do
    with :ok <- one_line(a, b),
         :ok <- one_frame(a, b) do
      {:ok, order_points(a, b)}
    end
  end

  @doc false
  # The point a value's span starts at: the value when it is one point, and
  # otherwise the start of the span, or of the first of the spans,
  # `Tempo.to_interval/1` gives it. This is the one place a value that is not
  # a point (a mask, a group, a set, significant digits, a count from the end)
  # is read as a moment, so that comparing agrees with converting.
  @spec start_point(Tempo.t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def start_point(%Tempo{time: time} = value) do
    if point?(time), do: {:ok, value}, else: value |> Tempo.to_interval() |> span_start(value)
  end

  defp span_start({:ok, %Interval{from: %Tempo{time: time} = start}}, value) do
    if point?(time), do: {:ok, start}, else: {:error, no_start_error(value)}
  end

  defp span_start({:ok, %IntervalSet{} = set}, value) do
    case IntervalSet.first(set) do
      %Interval{} = span -> span_start({:ok, span}, value)
      _no_span -> {:error, no_start_error(value)}
    end
  end

  defp span_start({:ok, _no_start}, value), do: {:error, no_start_error(value)}
  defp span_start({:error, _exception} = error, _value), do: error

  defp no_start_error(value) do
    ConversionError.exception(
      value: value,
      reason:
        "#{inspect(value)} has no one moment its span starts at, so it has no place " <>
          "in an order."
    )
  end

  @doc false
  # Whether a time list names one point: each unit one whole number (a year of
  # either sign), with or without a margin of error. An unspecified year
  # (`X*Y`) is no year, so the units after it name a point as they do with no
  # year written.
  @spec point?(list()) :: boolean()
  def point?([{:year, :any} | rest]), do: point_units?(rest)
  def point?(time), do: point_units?(time)

  defp point_units?([{:year, year} | rest]) when is_integer(year), do: point_units?(rest)

  defp point_units?([{_unit, value} | rest]) when is_integer(value) and value >= 0,
    do: point_units?(rest)

  defp point_units?([{:microsecond, {value, precision}} | rest])
       when is_integer(value) and is_integer(precision),
       do: point_units?(rest)

  defp point_units?([{_unit, {value, [margin_of_error: _margin]}} | rest])
       when is_integer(value),
       do: point_units?(rest)

  defp point_units?([]), do: true
  defp point_units?(_time), do: false

  # A point as comparing reads it: its margin of error dropped, and an
  # unspecified year dropped with it, since `X*Y6M` is the June of no year in
  # particular, as `6M` is.
  defp crisp_point(%Tempo{} = value) do
    with {:ok, %Tempo{time: time} = point} <- start_point(value) do
      {:ok, %{point | time: time |> drop_margin_of_error() |> drop_unspecified_year()}}
    end
  end

  defp drop_unspecified_year([{:year, :any} | rest]), do: rest
  defp drop_unspecified_year(time), do: time

  # Whether each unit of a time list is a whole number as it stands, so that
  # the list needs no reading before it is compared. The year is the one
  # unit that may be below zero.
  defp whole?([{:year, year} | rest]) when is_integer(year), do: whole_units?(rest)
  defp whole?(time), do: whole_units?(time)

  defp whole_units?([{_unit, value} | rest]) when is_integer(value) and value >= 0,
    do: whole_units?(rest)

  defp whole_units?([{:microsecond, {value, precision}} | rest])
       when is_integer(value) and is_integer(precision),
       do: whole_units?(rest)

  defp whole_units?([]), do: true
  defp whole_units?(_time), do: false

  # Two values share a line to be ordered on when both have a year, or neither
  # has and they lead with the same unit: the rule the set operations and the
  # certainty functions hold their operands to. A month with no year and a
  # dated day have no order, and neither have a week and a month of no year.
  defp same_line?([{unit, _a} | _a_rest], [{unit, _b} | _b_rest]), do: true
  defp same_line?([], []), do: true
  defp same_line?(_a_time, _b_time), do: false

  defp one_line(%Tempo{time: a_time} = a, %Tempo{time: b_time} = b) do
    if same_line?(a_time, b_time), do: :ok, else: {:error, no_line_error(a, b)}
  end

  defp no_line_error(%Tempo{time: [{:year, _year} | _rest]}, %Tempo{} = unanchored),
    do: UnanchoredError.exception(value: unanchored, reason: :comparison)

  defp no_line_error(%Tempo{} = unanchored, %Tempo{time: [{:year, _year} | _rest]}),
    do: UnanchoredError.exception(value: unanchored, reason: :comparison)

  defp no_line_error(%Tempo{} = a, %Tempo{} = b) do
    UnanchoredError.exception(
      operation:
        "order values on different axes (#{inspect(a)} is led by #{inspect(leading_unit(a))} " <>
          "and #{inspect(b)} by #{inspect(leading_unit(b))}); give both the same leading unit",
      reason: :comparison
    )
  end

  defp leading_unit(%Tempo{time: [{unit, _value} | _rest]}), do: unit
  defp leading_unit(%Tempo{}), do: nil

  defp order_points(%Tempo{} = a, %Tempo{} = b) do
    if structural?(a, b) do
      case compare_time(a.time, b.time) do
        :lt -> :earlier
        :gt -> :later
        :eq -> :same
      end
    else
      compare_via_utc(a, b)
    end
  end

  # Structural comparison of the time lists is calendar-blind — `5786`
  # (Hebrew) would read as later than `2025` (Gregorian) — so it is only
  # valid within a single calendar. It is also axis-blind: a week-axis
  # list (`[year, week]`) and a month-axis list (`[year, month, day]`)
  # share only the `:year` head, so the structural walk degenerates to
  # comparing years alone and mixed-axis endpoints all read `:same`.
  # Values in different calendars, or anchored values on different
  # sub-year axes, are compared by projecting both to the shared
  # absolute UTC frame, which resolves each axis to a real date. So are
  # values in a calendar whose fields are not in the order of its days.
  @doc false
  @spec structural?(Tempo.t(), Tempo.t()) :: boolean()
  def structural?(%Tempo{} = a, %Tempo{} = b) do
    a.calendar == b.calendar and zones_compatible?(a, b) and
      comparable_axes?(a.time, b.time, a.calendar) and fields_in_day_order?(a)
  end

  # Two values with no year are ordered by their fields, and by nothing else:
  # in different zones or calendars they have no year to be projected through.
  defp one_frame(%Tempo{time: [{:year, _year} | _rest]}, %Tempo{}), do: :ok

  defp one_frame(%Tempo{} = a, %Tempo{} = b) do
    if structural?(a, b), do: :ok, else: {:error, no_frame_error(a, b)}
  end

  defp no_frame_error(%Tempo{} = a, %Tempo{} = b) do
    UnanchoredError.exception(
      operation:
        "order #{inspect(a)} and #{inspect(b)}, which differ in zone or calendar and " <>
          "have no year to be placed by",
      reason: :comparison
    )
  end

  # Whether a value's fields run in the order of its days: whether its year
  # begins on its first month's first day. A Julian calendar whose year turns
  # on 25 March numbers 1 January after 31 December of the same year, so its
  # values are compared by their days. A value with no year has no days to
  # count and is compared by its fields.
  defp fields_in_day_order?(%Tempo{calendar: calendar})
       when calendar in [Gregorian, Calendar.ISO],
       do: true

  defp fields_in_day_order?(%Tempo{calendar: calendar, time: time}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> UnitValues.year_begins_with_first_month?(year, calendar)
      _no_year -> true
    end
  end

  # Two anchored time lists on different sub-year axes (week vs month vs
  # ordinal day) cannot be compared structurally — route them through the
  # UTC projection instead. Unanchored lists stay on the structural
  # path: they have no year to project through, and the set-operations
  # layer already rejects cross-axis unanchored operands upstream.
  defp comparable_axes?(time_a, time_b, calendar) do
    if Keyword.has_key?(time_a, :year) and Keyword.has_key?(time_b, :year),
      do: same_axis?(date_axis(time_a), date_axis(time_b), calendar),
      else: true
  end

  # A value with no unit under its year starts where the year's first month
  # does, and its first day. It starts where the year's first week does only
  # in a calendar of weeks: ISO 8601's first week of 2027 starts on 4 January,
  # so `2027` and `2027-W01` are not one moment.
  defp same_axis?(axis, axis, _calendar), do: true
  defp same_axis?(:none, :week, calendar), do: week_based?(calendar)
  defp same_axis?(:week, :none, calendar), do: week_based?(calendar)
  defp same_axis?(:none, _axis, _calendar), do: true
  defp same_axis?(_axis, :none, _calendar), do: true
  defp same_axis?(_axis, _another_axis, _calendar), do: false

  defp week_based?(calendar), do: effective_calendar(calendar).calendar_base() == :week

  # `:week` marks the week-of-year axis only when no `:month` qualifies
  # it — `[year, month, week]` is a week *of the month*, which lives on
  # the month axis and compares structurally against month-axis dates.
  defp date_axis(time) do
    cond do
      Keyword.has_key?(time, :month) -> :month
      Keyword.has_key?(time, :week) -> :week
      Keyword.has_key?(time, :day) or Keyword.has_key?(time, :day_of_year) -> :ordinal
      true -> :none
    end
  end

  @doc """
  Compare two Tempo values, returning stdlib's ternary
  `:lt | :eq | :gt`.

  This is the sorter-module callback Elixir's `Enum` and `List`
  functions look for, so `Tempo` can be passed wherever `Date`,
  `Time`, or `DateTime` would be:

      Enum.sort_by(sessions, & &1.starts_at, Tempo)
      Enum.max_by(bookings, & &1.window.from, Tempo)

  Use `Tempo.relation/2` instead when the question is *how* two
  intervals relate — this function collapses Allen's 13 relations to
  a total order, which is what sorting needs and reasoning does not.

  A value that names more than one moment (a mask, a group, a set,
  significant digits) compares as the moment its span starts at, the
  start of what `Tempo.to_interval/1` gives it.

  ### Comparison is crisp

  A total order cannot express doubt, so uncertainty is dropped before
  comparing: `~o"1984?"` and `~o"1984"` compare `:eq`, and a margin of
  error is discarded the same way `compare_endpoints/2` discards it.
  When the uncertainty is the point, reach for `Tempo.certainly_before?/2`
  or `Tempo.possibly_before?/2` rather than this function.

  ### Arguments

  * `a` and `b` are two values of the same kind — both `t:Tempo.t/0`,
    both `t:Tempo.Duration.t/0`, or both `t:Tempo.Interval.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:relative_to` is a `t:Tempo.t/0` used to resolve
    calendar-dependent durations. `P1M` has no fixed length, so
    comparing it requires a date to measure that month against.

  ### Returns

  * `:lt`, `:eq`, or `:gt`.

  * Raises `ArgumentError` when the two values are of different kinds,
    or when a duration cannot be resolved to a fixed length and no
    `:relative_to` was given.

  * Raises `Tempo.FloatingTempoError` when one value has a zone or an
    offset and the other none, and `Tempo.UnanchoredError` when one has
    a year and the other none: neither pair has an order.

  ### Examples

  Tempo values compare as start-moments on the time line:

      iex> Tempo.compare(~o"2026-06-15", ~o"2026-06-16")
      :lt

      iex> Tempo.compare(~o"2026Y", ~o"2026-06")
      :lt

  Zones are resolved, so the same instant compares equal:

      iex> Tempo.compare(~o"2026-06-15T09:00:00Z", ~o"2026-06-15T10:00:00+01:00")
      :eq

  Which makes `Tempo` usable directly as a sorter:

      iex> [~o"2026-06-16", ~o"2026-06-15"]
      ...> |> Enum.sort(Tempo)
      [~o"2026Y6M15D", ~o"2026Y6M16D"]

  Durations compare by length:

      iex> Tempo.compare(~o"PT1H", ~o"PT90M")
      :lt

  Intervals compare by start, ties broken by end:

      iex> morning = Tempo.Interval.new!(from: ~o"2026-06-15T09:00", to: ~o"2026-06-15T10:00")
      iex> longer = Tempo.Interval.new!(from: ~o"2026-06-15T09:00", to: ~o"2026-06-15T11:00")
      iex> Tempo.compare(morning, longer)
      :lt

  """
  @spec compare(
          Tempo.t() | Tempo.Duration.t() | Tempo.Interval.t(),
          Tempo.t() | Tempo.Duration.t() | Tempo.Interval.t(),
          keyword()
        ) :: :lt | :eq | :gt
  def compare(a, b, options \\ [])

  def compare(%Tempo{} = a, %Tempo{} = b, _options) do
    one_frame!(a, b)
    a |> compare_endpoints(b) |> from_endpoint_order()
  end

  def compare(%Tempo.Duration{} = a, %Tempo.Duration{} = b, options) do
    with {:ok, a_seconds} <- Duration.to_unit(a, :second, options),
         {:ok, b_seconds} <- Duration.to_unit(b, :second, options) do
      from_magnitudes(a_seconds, b_seconds)
    else
      {:error, exception} -> raise exception
    end
  end

  def compare(%Interval{} = a, %Interval{} = b, options) do
    case compare_bound(a.from, b.from, :from, options) do
      :eq -> compare_bound(a.to, b.to, :to, options)
      order -> order
    end
  end

  def compare(a, b, _options) do
    raise ArgumentError,
          "cannot compare #{kind_of(a)} with #{kind_of(b)} — " <>
            "both values must be of the same kind"
  end

  # A value with no zone has no place on the universal time line, and so no
  # order with one that has: the pair `Tempo.relation/2` refuses.
  defp one_frame!(%Tempo{} = a, %Tempo{} = b) do
    if Tempo.floating?(a) != Tempo.floating?(b) do
      floating = if Tempo.floating?(a), do: a, else: b
      raise FloatingTempoError.exception(operation: :compare, value: floating)
    end

    :ok
  end

  defp from_endpoint_order(:earlier), do: :lt
  defp from_endpoint_order(:same), do: :eq
  defp from_endpoint_order(:later), do: :gt

  defp from_magnitudes(a, b) when a < b, do: :lt
  defp from_magnitudes(a, b) when a > b, do: :gt
  defp from_magnitudes(_a, _b), do: :eq

  # An unbounded `from` starts before every stated instant; an
  # unbounded `to` ends after every stated instant. Two unbounded
  # endpoints on the same side are indistinguishable.
  defp compare_bound(same, same, _side, _options), do: :eq
  defp compare_bound(:undefined, _b, :from, _options), do: :lt
  defp compare_bound(_a, :undefined, :from, _options), do: :gt
  defp compare_bound(:undefined, _b, :to, _options), do: :gt
  defp compare_bound(_a, :undefined, :to, _options), do: :lt
  defp compare_bound(nil, _b, :to, _options), do: :gt
  defp compare_bound(_a, nil, :to, _options), do: :lt
  defp compare_bound(a, b, _side, options), do: compare(a, b, options)

  defp kind_of(%Tempo{}), do: "a Tempo"
  defp kind_of(%Tempo.Duration{}), do: "a Tempo.Duration"
  defp kind_of(%Interval{}), do: "a Tempo.Interval"
  defp kind_of(%IntervalSet{}), do: "a Tempo.IntervalSet"
  defp kind_of(other), do: inspect(other)

  @doc """
  Drop the `margin_of_error` annotation from every component of a time
  keyword list.

  A margin of error (`2018±2`) is a crisp-inert uncertainty annotation
  stored as `{value, [margin_of_error: n]}`. Crisp comparison and
  materialisation operate on plain integers, so the annotation is dropped
  before those operations (leaving any other annotation, e.g.
  `significant_digits`, untouched). The margin is preserved on the caller's
  original value — only the comparison/materialisation copy is reduced to
  its crisp core. Graded, margin-aware relations are a future step.
  """
  def drop_margin_of_error(time) do
    Enum.map(time, fn
      {unit, {value, options}} when is_list(options) ->
        case Keyword.delete(options, :margin_of_error) do
          [] -> {unit, value}
          remaining -> {unit, {value, remaining}}
        end

      other ->
        other
    end)
  end

  # Two Tempos compare structurally (by wall clock) only when they share
  # the same frame — the same zone id AND the same numeric UTC offset. A
  # zoned value (`[Europe/Paris]`) resolves its offset on demand and
  # holds `shift: nil`, so two same-zone values stay structural. But two
  # fixed-offset values with different offsets (`+05:30` vs `+09:00`)
  # read one wall clock as two different instants, so they must project
  # to UTC; comparing their wall-clock lists directly would wrongly
  # report them equal.
  defp zones_compatible?(a, b), do: same_zone_id?(a, b) and same_offset?(a, b)

  defp same_zone_id?(%Tempo{extended: a}, %Tempo{extended: b}), do: zone_id(a) == zone_id(b)

  defp zone_id(nil), do: nil
  defp zone_id(%{zone_id: zone_id}), do: zone_id

  defp same_offset?(%Tempo{shift: a}, %Tempo{shift: b}),
    do: shift_seconds(a) == shift_seconds(b)

  defp shift_seconds(nil), do: nil
  defp shift_seconds(shift), do: shift_to_seconds(shift)

  defp compare_via_utc(%Tempo{time: [{:year, _year} | _rest]} = a, %Tempo{} = b) do
    a_secs = to_utc_seconds(a)
    b_secs = to_utc_seconds(b)

    cond do
      a_secs < b_secs -> :earlier
      a_secs > b_secs -> :later
      # Whole UTC seconds tie — break on the sub-second value. Zone
      # offsets are whole-minute, so the microsecond value is the same
      # in wall-clock and UTC frames; comparing the raw values is exact.
      true -> compare_microsecond_values(a, b)
    end
  end

  defp compare_via_utc(%Tempo{} = a, %Tempo{} = b), do: raise(no_frame_error(a, b))

  defp compare_microsecond_values(a, b) do
    case {microsecond_value(a), microsecond_value(b)} do
      {x, y} when x < y -> :earlier
      {x, y} when x > y -> :later
      _ -> :same
    end
  end

  defp microsecond_value(%Tempo{time: time}) do
    case Keyword.get(time, :microsecond) do
      {value, _precision} -> value
      nil -> 0
    end
  end

  @doc """
  Project a zoned `%Tempo{}` to UTC gregorian seconds since
  year 0 (matching Erlang's `:calendar.datetime_to_gregorian_seconds/1`
  epoch).

  The projection is per-call, never cached. When the configured
  time zone database is updated with new zone rules, the next call
  automatically uses them. Stored IntervalSet endpoints carry wall-clock + zone as
  authoritative — see `plans/set-operations.md` for the full
  rationale on why no UTC cache exists.

  ### Arguments

  * `tempo` is a `%Tempo{}` with at minimum year/month/day/hour/
    minute/second components. Missing components are padded with
    their unit minimum.

  ### Returns

  * `integer` — gregorian seconds since year 0 in UTC.

  A value that is not one point (a mask, a group, a set, significant
  digits) is projected from the point its span starts at, as
  `compare_endpoints/2` reads it.

  ### Raises

  * `ArgumentError` when the Tempo has no `:year` component, or an
    unspecified one (unanchored values can't be projected to a
    universal instant).

  * The error `Tempo.to_interval/1` returns for a value whose span
    starts at no point.

  """
  @spec to_utc_seconds(Tempo.t()) :: integer() | float()
  def to_utc_seconds(%Tempo{} = value) do
    %Tempo{time: [{:year, year} | _rest] = time, extended: extended, shift: shift} =
      point = dated_point!(value)

    wall = wall_seconds(time, year, effective_calendar(point.calendar))
    wall - resolve_offset_seconds(extended, shift, wall)
  end

  @doc false
  # The wall-clock reading of an anchored value as gregorian seconds,
  # before any offset: the reading a zone's periods are looked up by.
  @spec to_wall_seconds(Tempo.t()) :: integer() | float()
  def to_wall_seconds(%Tempo{} = value) do
    %Tempo{time: [{:year, year} | _rest] = time, calendar: calendar} = dated_point!(value)
    wall_seconds(time, year, effective_calendar(calendar))
  end

  # A value as the point with a year it is projected from. Most values given
  # to the projection are that already, so they are passed through unread.
  defp dated_point!(%Tempo{time: [{:year, year} | rest]} = value) when is_integer(year) do
    if whole_units?(rest), do: value, else: read_dated_point!(value)
  end

  defp dated_point!(%Tempo{} = value), do: read_dated_point!(value)

  defp read_dated_point!(%Tempo{} = value) do
    case crisp_point(value) do
      {:ok, %Tempo{time: [{:year, year} | _rest]} = point} when is_integer(year) ->
        point

      {:ok, _no_year} ->
        raise ArgumentError,
              "Cannot place an unanchored Tempo (one with no year) on the UTC time " <>
                "line. Place it on a date first with `Tempo.at/2` or `Tempo.on/2`, " <>
                "or give the calling operation a `within:` window."

      {:error, exception} ->
        raise exception
    end
  end

  # The wall-clock instant as gregorian seconds (before any offset is
  # applied). Shared by `to_utc_seconds/1` and `validate_zone_offset/1`.
  # A non-Gregorian value's calendar components are converted to the
  # proleptic Gregorian frame first, so the projection lands on a true
  # absolute instant (and cross-calendar comparisons and durations are
  # correct); Gregorian values take the fast path unchanged.
  defp wall_seconds(time, year, calendar) do
    {year, month, day} = resolve_ymd(time, year, calendar)
    hour = Keyword.get(time, :hour, 0)
    minute = Keyword.get(time, :minute, 0)
    second = Keyword.get(time, :second, 0)

    # `Calendrical.Gregorian.date_to_iso_days/3` counts from 0000-01-01
    # (day 0) and, unlike OTP ≤ 28's
    # `:calendar.datetime_to_gregorian_seconds/1`, accepts negative
    # (pre-common-era) years on every OTP — e.g. a value whose units
    # read as Hebrew year 2022 resolves to proleptic Gregorian −1738.
    Gregorian.date_to_iso_days(year, month, day) * 86_400 +
      hour * 3_600 + minute * 60 + second
  end

  @doc """
  Check that an IXDTF value's explicit numeric offset agrees with its
  IANA time zone at the value's wall instant.

  When a value carries both a numeric offset and a zone identifier (e.g.
  `2022-11-20T10:37:00+05:00[Europe/Paris]`), the offset is normally
  consulted only to disambiguate a DST fall-back — the zone otherwise
  wins. This check (RFC 9557 §4.2) flags the case where the stated
  offset matches no offset the zone actually uses at that instant.

  ### Arguments

  * `tempo` is a `t:Tempo.t/0`.

  ### Returns

  * `:ok` when the offset agrees with the zone, when there is nothing to
    check (no zone, or no explicit offset), or when the value is not
    anchored (no wall instant to evaluate against).

  * `{:error, t:Tempo.ZoneOffsetMismatchError.t/0}` when the stated
    offset disagrees with the zone.

  See `Tempo.validate_zone_offset/1`, which delegates here, for worked
  examples.

  """
  @spec validate_zone_offset(Tempo.t()) ::
          :ok | {:error, Tempo.ZoneOffsetMismatchError.t()}
  def validate_zone_offset(%Tempo{extended: extended, shift: shift} = tempo) do
    zone_id = extended && Map.get(extended, :zone_id)
    stated = explicit_offset_seconds(extended, shift)

    cond do
      is_nil(zone_id) or zone_id == "" -> :ok
      is_nil(stated) -> :ok
      not Tempo.anchored?(tempo) -> :ok
      true -> tempo |> span_starts() |> check_zone_offsets(zone_id, stated)
    end
  end

  # The moments a zoned value's offset is checked at: the value when it is one
  # point, and otherwise the start of each span it names (`2026-{01,07}-15`
  # at 10:00 in Paris is one offset in January and another in July). A value
  # with spans without number, or with none, has no moment to check.
  defp span_starts(%Tempo{time: time} = tempo) do
    if point?(time), do: [tempo], else: tempo |> Tempo.to_interval() |> starts_of()
  end

  defp starts_of({:ok, %Interval{from: %Tempo{} = start}}), do: [start]

  defp starts_of({:ok, %IntervalSet{} = set}) do
    if IntervalSet.bounded?(set),
      do: for(%Interval{from: %Tempo{} = start} <- IntervalSet.members(set), do: start),
      else: []
  end

  defp starts_of(_no_spans), do: []

  defp check_zone_offsets(starts, zone_id, stated) do
    Enum.reduce_while(starts, :ok, fn start, :ok ->
      case check_zone_offset(start, zone_id, stated) do
        :ok -> {:cont, :ok}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
  end

  # Wall seconds at 0001-01-01T00:00:00 — the floor below which no
  # IANA rule exists (local mean time era) and below which some databases'
  # internals crash on OTP ≤ 28 (`:calendar.last_day_of_the_month/2`
  # rejects negative years). Pre-common-era instants skip the database
  # lookups entirely.
  @gregorian_seconds_year_1 :calendar.datetime_to_gregorian_seconds({{1, 1, 1}, {0, 0, 0}})

  defp check_zone_offset(%Tempo{} = start, zone_id, stated) do
    case crisp_point(start) do
      {:ok, %Tempo{time: [{:year, year} | _rest] = time, calendar: calendar}}
      when is_integer(year) ->
        time |> wall_seconds(year, effective_calendar(calendar)) |> check_wall(zone_id, stated)

      _no_wall_instant ->
        :ok
    end
  end

  # Pre-common-era: the IANA data has no rules to confirm or refute
  # the stated offset, so accept it rather than consult the database.
  defp check_wall(wall, _zone_id, _stated) when wall < @gregorian_seconds_year_1, do: :ok
  defp check_wall(wall, zone_id, stated), do: do_check_zone_offset(wall, zone_id, stated)

  defp do_check_zone_offset(wall, zone_id, stated) do
    # A gap reading names no instant in the zone, so no offset can
    # agree with it — the empty candidate list falls through to the
    # mismatch error, preserving the pre-behaviour semantics.
    offsets =
      case TimeZoneDatabase.period_at_wall(zone_id, wall) do
        {:ok, period} ->
          [TimeZoneDatabase.total_offset(period)]

        {:ambiguous, first, second} ->
          [first, second] |> Enum.map(&TimeZoneDatabase.total_offset/1)

        _gap_or_error ->
          []
      end

    if stated in offsets do
      :ok
    else
      {:error,
       ZoneOffsetMismatchError.exception(
         zone_id: zone_id,
         stated_offset: stated,
         zone_offsets: offsets,
         wall_time: wall_seconds_to_iso(wall)
       )}
    end
  end

  defp wall_seconds_to_iso(wall) do
    {{y, mo, d}, {h, mi, s}} = :calendar.gregorian_seconds_to_datetime(wall)

    [y, mo, d, h, mi, s]
    |> then(&:io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", &1))
    |> IO.iodata_to_binary()
  end

  # Resolve the proleptic Gregorian `{year, month, day}` from the time
  # list, handling the three date representations Tempo stores:
  #
  #   * Week date — `[year, week, day_of_week]`, in ISO 8601 weeks or a
  #     week-based calendar's own (`Tempo.Validation.date_from_iso_week/4`).
  #   * Ordinal date — `[year, day]` with `:day` holding the
  #     day-of-year and no `:month` (the absence of `:month` is the
  #     disambiguator, matching `Tempo.to_date/1`).
  #   * Standard date — `[year, month, day]` (month/day default to 1).
  #
  # Without this, week and ordinal dates projected via the
  # month/day defaults (1, 1) and collapsed to Jan 1 — making every
  # week interval report a zero-second duration. The dates come from
  # Calendrical, never from arithmetic here.
  defp resolve_ymd(time, year, calendar) do
    calendar = calendar || Calendrical.Gregorian

    cond do
      Keyword.has_key?(time, :week) ->
        day = Keyword.get(time, :day_of_week, Keyword.get(time, :day, 1))

        year
        |> Validation.date_from_iso_week(Keyword.get(time, :week), day, calendar)
        |> gregorian_ymd(year)

      not Keyword.has_key?(time, :month) and Keyword.has_key?(time, :day) ->
        year
        |> Calendrical.date_from_day_of_year(Keyword.get(time, :day), calendar)
        |> gregorian_ymd(year)

      # A day of the year left as one: under a year with a margin of error,
      # which validation does not restate as a month and a day.
      Keyword.has_key?(time, :day_of_year) ->
        year
        |> Calendrical.date_from_day_of_year(Keyword.get(time, :day_of_year), calendar)
        |> gregorian_ymd(year)

      true ->
        time |> start_ymd(year, calendar) |> to_gregorian_ymd(calendar)
    end
  end

  # The date a year, a month or a day of one starts on: the day itself, the
  # month's first, or the first of the year's first month. Where the year
  # does not begin with its first month the calendar is asked for the first
  # date of the year or of the month (`Tempo.UnitValues.start_date/2`): the
  # first month of a `Calendrical.Julian.March25` year begins on 25 March.
  defp start_ymd(time, year, calendar) do
    case UnitValues.start_date(time, calendar) do
      {:ok, ymd} -> ymd
      :error -> {year, Keyword.get(time, :month, 1), Keyword.get(time, :day, 1)}
    end
  end

  # A date Calendrical computed, in the proleptic Gregorian frame, or the
  # year's start when it could compute none — the start-of-unit default
  # the standard-date branch uses.
  defp gregorian_ymd({:ok, %Date{} = date}, year), do: gregorian_ymd(date, year)

  defp gregorian_ymd(%Date{} = date, _year) do
    case Date.convert(date, Calendrical.Gregorian) do
      {:ok, iso} -> {iso.year, iso.month, iso.day}
      _error -> {date.year, date.month, date.day}
    end
  end

  defp gregorian_ymd(_error, year), do: {year, 1, 1}

  @doc false
  # A hand-built `%Tempo{}` may carry `calendar: nil` (the struct default)
  # rather than the resolved calendar a parsed or `Tempo.new/1`-built value
  # has. Calendar dispatch (`calendar.calendar_base/0`, `Date.new/4`, …)
  # assumes a real calendar module, so a boundary resolves `nil` to the
  # default Gregorian implementation — the internal form of `Calendar.ISO`,
  # which unlike `Calendar.ISO` carries the `Calendrical` behaviour callbacks
  # — before any dispatch. Applied at the comparison, materialisation, and
  # network-ingest choke points every public operation funnels through.
  def effective_calendar(nil), do: Calendrical.Gregorian
  def effective_calendar(calendar), do: calendar

  # Convert calendar-native `{year, month, day}` to the proleptic Gregorian
  # frame the projection assumes. Gregorian passes through untouched (fast
  # path); any other calendar is validated and located in one step by
  # `Calendrical.iso_days/4`. Falls back to the raw components rather
  # than raising if the date is not valid (a defensive best-effort). The
  # `nil` default is resolved to `Calendrical.Gregorian` at the boundary
  # (`to_utc_seconds/1`), so it never reaches here.
  defp to_gregorian_ymd(ymd, Calendrical.Gregorian), do: ymd

  defp to_gregorian_ymd({year, month, day}, calendar) do
    case Calendrical.iso_days(year, month, day, calendar) do
      {:ok, iso_days} ->
        %Date{year: year, month: month, day: day} = Date.from_gregorian_days(iso_days)
        {year, month, day}

      _error ->
        {year, month, day}
    end
  end

  # The offset to subtract from wall-clock to get UTC. Priority:
  #
  # 1. An IANA zone on `extended.zone_id` — look up via the configured
  #    time zone database at
  #    the given wall instant (DST-era-correct). When the database
  #    returns multiple periods (DST fall-back ambiguity), an
  #    explicit numeric offset from `extended.zone_offset` or
  #    from the ISO 8601 `shift` disambiguates — we pick the
  #    period whose total offset matches. This is the mechanism
  #    RFC 9557 §4.5 describes for resolving fall-back ambiguity
  #    in IXDTF strings like `01:30:00-04:00[America/New_York]`.
  # 2. A numeric offset on `extended.zone_offset` (minutes) — use
  #    directly.
  # 3. A `shift` keyword list (legacy-style) — convert to seconds.
  # 4. No info → 0 (treat as UTC).
  # Pre-common-era wall instants precede every IANA rule — local-mean-
  # time era, so treat as
  # UTC exactly like the no-info fallback below.
  defp resolve_offset_seconds(%{zone_id: zone_id}, _shift, wall_seconds)
       when is_binary(zone_id) and zone_id != "" and
              wall_seconds < @gregorian_seconds_year_1 do
    0
  end

  defp resolve_offset_seconds(%{zone_id: zone_id} = extended, shift, wall_seconds)
       when is_binary(zone_id) and zone_id != "" do
    case TimeZoneDatabase.period_at_wall(zone_id, wall_seconds) do
      {:ok, period} ->
        TimeZoneDatabase.total_offset(period)

      {:ambiguous, first, second} ->
        ambiguous_offset([first, second], explicit_offset_seconds(extended, shift))

      # A reading the clock skips (a spring-forward, a day a zone leaves
      # out) is read with the offset before the gap, as RFC 5545 §3.3.5
      # reads it, so it is the time that much after the clock changed:
      # 02:30 on the night Paris moves from 02:00 to 03:00 is 03:30. A value
      # the clock skips the whole of is refused when it is read
      # (`Tempo.Validation.validate_zone_existence/1`), and this is what a
      # value it skips part of reaches: the day or the month whose first
      # reading is skipped, which starts when the clock changes, and the
      # hour of a half-hour change.
      {:gap, {before, _gap_starts}, _after} ->
        TimeZoneDatabase.total_offset(before)

      # An unknown zone, or no configured database: read as UTC.
      {:error, _reason} ->
        0
    end
  end

  defp resolve_offset_seconds(%{zone_offset: minutes}, _shift, _wall)
       when is_integer(minutes) do
    minutes * 60
  end

  defp resolve_offset_seconds(_extended, shift, _wall) when is_list(shift) do
    shift_to_seconds(shift)
  end

  defp resolve_offset_seconds(_extended, _shift, _wall), do: 0

  # Ambiguous wall time (DST fall-back): prefer the period whose
  # offset matches the explicit disambiguator, else the first period.
  defp ambiguous_offset(periods, preferred) do
    case Enum.find(periods, &(TimeZoneDatabase.total_offset(&1) == preferred)) do
      nil -> TimeZoneDatabase.total_offset(hd(periods))
      period -> TimeZoneDatabase.total_offset(period)
    end
  end

  # Extract an explicit offset in seconds from either the extended
  # `zone_offset` (minutes) or the ISO 8601 `shift` (keyword list).
  # Returns `nil` when no explicit offset is supplied — the caller
  # then falls back to the database's unambiguous period.
  defp explicit_offset_seconds(%{zone_offset: minutes}, _shift) when is_integer(minutes) do
    minutes * 60
  end

  defp explicit_offset_seconds(_extended, shift) when is_list(shift) do
    shift_to_seconds(shift)
  end

  defp explicit_offset_seconds(_extended, _shift), do: nil

  @doc false
  # The signed offset in seconds denoted by a parsed ISO 8601 shift
  # list. Shared with `Tempo.to_datetime/1`'s conversion of a value
  # with an offset.
  def offset_seconds(shift) when is_list(shift), do: shift_to_seconds(shift)

  # A shift carries its sign on its first non-zero component (`-05:30`
  # is `[hour: -5, minute: 30]`, `-00:30` is `[hour: 0, minute: -30]`),
  # so the finer components inherit it: −05:30 is −(5 h 30 m), not
  # −5 h + 30 m — the difference is real for half-hour zones
  # (Newfoundland −03:30).
  defp shift_to_seconds(shift) do
    hour = shift_component(shift, :hour)
    minute = shift_component(shift, :minute)
    second = shift_component(shift, :second)
    shift_sign(hour, minute, second) * (abs(hour) * 3600 + abs(minute) * 60 + abs(second))
  end

  defp shift_sign(hour, _minute, _second) when hour < 0, do: -1
  defp shift_sign(0, minute, _second) when minute < 0, do: -1
  defp shift_sign(0, 0, second) when second < 0, do: -1
  defp shift_sign(_hour, _minute, _second), do: 1

  # `Keyword.get/3` returns `any()`, so any arithmetic on its result
  # widens to `number()` and propagates a stray `float()` into the
  # spec of `to_utc_seconds/1`. Narrowing through a guarded helper
  # pins the result to `integer()` for Dialyzer. No `@spec` — the
  # success typing inferred from call sites (`:hour | :minute |
  # :second`) is tighter than any spec we'd write, and a broader
  # spec triggers a supertype-contract warning.
  defp shift_component(shift, key) do
    case Keyword.get(shift, key, 0) do
      value when is_integer(value) -> value
    end
  end
end
