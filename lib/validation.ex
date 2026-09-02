defmodule Tempo.Validation do
  @moduledoc false

  alias Calendrical.ISOWeek
  alias Localize.Utils.Math
  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.InvalidDateError
  alias Tempo.InvalidTimeError
  alias Tempo.Microsecond
  alias Tempo.ParseError
  alias Tempo.TimeZoneDatabase
  alias Tempo.ZoneGapError

  # This function performs two roles (and maybe should be split):
  #
  # 1. Expand groups into basic time units where there is enough information to do so and
  # 2. Ensures that basic units are valid (days in months, months in year etc)

  # There is ample room to refactor into a more generalised solution for much of
  # the resolution task. For now, being completely explicit aids implementation and
  # debugging. Refactoring to a generalised case will come later.

  @hours_per_day 24
  @minutes_per_hour 60
  @rounding_precision 10

  def validate(tempo, calendar \\ Calendrical.Gregorian)

  def validate(%Tempo{time: units} = tempo, calendar) do
    with :ok <- validate_leap_second(units, tempo),
         :ok <- validate_time_shift(tempo.shift) do
      case resolve(units, calendar) do
        {:error, reason} -> {:error, reason}
        other -> {:ok, %{tempo | time: other}}
      end
    end
  end

  # Endpoints carrying different time shifts (`...+05:00/...+02:00`)
  # need no adjustment: `Tempo.Compare` projects both to a common UTC
  # frame for ordering and duration, so the difference is already
  # accounted for.

  def validate(%Tempo.Interval{} = tempo, calendar) do
    with {:ok, from} <- validate(tempo.from, endpoint_calendar(tempo.from, calendar)),
         {:ok, to} <- validate(tempo.to, endpoint_calendar(tempo.to, calendar)),
         {:ok, duration} <- validate(tempo.duration, calendar),
         :ok <- validate_endpoint_order(from, to) do
      {:ok, %{tempo | from: from, to: to, duration: duration}}
    end
  end

  def validate(%Tempo.Duration{} = duration, _calendar) do
    {:ok, duration}
  end

  def validate(%Tempo.Set{set: set} = tempo, calendar) do
    validated =
      Enum.reduce_while(set, [], fn elem, acc ->
        case resolve(elem, calendar) do
          {:error, reason} -> {:halt, {:error, reason}}
          units -> {:cont, [units | acc]}
        end
      end)

    case validated do
      {:error, reason} -> {:error, reason}
      resolved -> {:ok, %{tempo | set: Enum.reverse(resolved)}}
    end
  end

  def validate(nil, _calendar) do
    {:ok, nil}
  end

  def validate(:undefined, _calendar) do
    {:ok, :undefined}
  end

  # An endpoint validates against its own calendar when it carries one —
  # a per-endpoint IXDTF `u-ca` suffix can make one endpoint of an
  # interval calendar-distinct from the other — falling back to the
  # interval-level calendar otherwise.
  defp endpoint_calendar(%Tempo{calendar: calendar}, _default) when not is_nil(calendar) do
    calendar
  end

  defp endpoint_calendar(_endpoint, default), do: default

  # ISO 8601 expects an interval's end to follow its start, so reject
  # a genuinely inverted interval such as `2026/2025`. The check is
  # deliberately narrow — it only fires when both endpoints are
  # anchored (a year is present) and fully concrete (no mask, group,
  # range, or set). This leaves two legitimate shapes untouched:
  #
  #   * Non-anchored time-of-day intervals, where `from > to` is the
  #     representation of a midnight-crossing span (`T22/T02`).
  #
  #   * EDTF reduced-precision and masked intervals
  #     (`1111-01-01/1111`, `0000/0000`, `1919-XX-02/1919-XX-01`),
  #     whose end is a coarser or unknown span, not a real inversion.
  #
  # Inversion is judged against `to`'s *exclusive upper bound* (the
  # end of its own span), not its start. That is what keeps
  # `1111-01-01/1111` valid (the year 1111 ends in 1112, after the
  # start) while still rejecting `2026/2025` (the year 2025 ends
  # exactly where 2026 begins).
  defp validate_endpoint_order(%Tempo{} = from, %Tempo{} = to) do
    with true <- orderable?(from) and orderable?(to),
         {:ok, {_lower, to_upper}, _unit} <- Interval.next_unit_boundary(to),
         order when order != :earlier <- Compare.compare_endpoints(from, to_upper) do
      {:error,
       IntervalEndpointsError.exception(
         interval: %Tempo.Interval{from: from, to: to},
         operation: :validate,
         reason: "interval :from endpoint is not earlier than its :to endpoint"
       )}
    else
      _ -> :ok
    end
  end

  defp validate_endpoint_order(_from, _to), do: :ok

  # Orderable: anchored (has a year, so a UTC start exists) and fully
  # concrete (every component is a plain integer or a microsecond
  # `{value, precision}` pair — no mask, group, range, or set).
  defp orderable?(%Tempo{time: time}) do
    Keyword.has_key?(time, :year) and Enum.all?(time, fn {_unit, value} -> concrete?(value) end)
  end

  defp concrete?(value) when is_integer(value), do: true
  defp concrete?({value, precision}) when is_integer(value) and is_integer(precision), do: true
  defp concrete?(_value), do: false

  # Resolution is the process of pre-calculating concrete
  # time units from groups whereever possible.

  def resolve([{:day_of_week, day} | rest], calendar) when is_integer(day) do
    days_in_week = calendar.days_in_week()

    with {:ok, day} <- conform(day, 1..days_in_week) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:day_of_week, day} | resolved]
      end
    end
  end

  # When a group of years succeeds a century or decade
  # Here we merge into a set.

  def resolve(
        [{unit, {:group, %Range{} = range1}}, {unit, {:group, %Range{} = range2}} | rest],
        calendar
      ) do
    first = range1.first + range2.first - 1

    if first in 1..range1.last//1 do
      last = min(range1.last, first + range2.last - range2.first)
      resolve([{unit, [first..last//1]} | rest], calendar)
    else
      {:error,
       InvalidDateError.exception(
         unit: unit,
         value: first,
         valid_range: range1,
         calendar: calendar
       )}
    end
  end

  def resolve([{:year, {:group, %Range{} = years}}, {:month, month} | rest], calendar)
      when is_integer(month) do
    months_in_group =
      years
      |> Enum.map(&calendar.months_in_year/1)
      |> Enum.sum()

    with {:ok, month} <- conform(month, 1..months_in_group) do
      {:ok, year, month} = year_and_month(years, month, calendar)
      resolve([{:year, year}, {:month, month} | rest], calendar)
    end
  end

  def resolve(
        [{:year, year}, {:month, {:group, %Range{} = months}}, {:day, day} | rest],
        calendar
      )
      when is_integer(year) and is_integer(day) do
    days_in_group =
      months
      |> Enum.map(&calendar.days_in_month(year, &1))
      |> Enum.sum()

    with {:ok, day} <- conform(day, 1..days_in_group) do
      {:ok, month, day} = month_and_day(year, months, day, calendar)
      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    end
  end

  # Week numbering is inherently ISO-week semantics regardless of
  # the caller's declared calendar. `Calendrical.Gregorian.weeks_in_year/1`
  # always reports 52 weeks because Gregorian doesn't define week
  # numbering — that's ISO-8601's job. Validating via
  # `Calendrical.ISOWeek.weeks_in_year/1` gives the correct answer
  # for every year (including 53-week years like 2004, 2009, 2015,
  # 2020, 2026).
  #
  # Resolution of (year, week, day) to a concrete calendar date
  # depends on the caller's calendar base:
  #
  #   * `:month`-based (Gregorian and the other civil calendars) —
  #     resolve the week-date under ISOWeek, then `Date.convert/2`
  #     into the caller's calendar, yielding a Gregorian-shaped
  #     `[year, month, day]` value. This is the common path and the
  #     one that picks up the W01-after-a-53-week-year rollover
  #     correctly.
  #
  #   * `:week`-based (`Calendrical.ISOWeek` itself) — keep the
  #     native `[year, week, day]` shape; the caller asked for ISO
  #     week calendar so preserve it.
  def resolve([{:year, year}, {:week, week}, {:day_of_week, day} | rest], calendar)
      when is_integer(year) and is_integer(week) and is_integer(day) do
    {weeks_in_year, _days_in_last_week} = ISOWeek.weeks_in_year(year)

    with {:ok, week} <- conform(week, 1..weeks_in_year),
         [day_of_week: day] <- resolve([day_of_week: day], Calendrical.ISOWeek) do
      year_week_day(year, week, day, rest, calendar.calendar_base(), calendar)
    end
  end

  def resolve([{:year, year}, {:day, day_of_year} | rest], calendar)
      when is_integer(year) and is_integer(day_of_year) do
    days_in_year = calendar.days_in_year(year)

    with {:ok, day_of_year} <- conform(day_of_year, 1..days_in_year) do
      %{year: year, month: month, day: day} =
        Calendrical.date_from_day_of_year(year, day_of_year, calendar)

      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    end
  end

  def resolve(
        [{:year, year}, {:day, {:group, %Range{} = days_of_year}}, {:day, day} | rest],
        calendar
      )
      when is_integer(year) and is_integer(day) do
    %{first: first, last: last} = days_of_year
    days_in_year = calendar.days_in_year(year)
    last = min(last, days_in_year)
    day = if day < 0, do: last + day + 1, else: first + day - 1

    if first in 1..days_in_year and day <= last do
      %{year: year, month: month, day: day} =
        Calendrical.date_from_day_of_year(year, day, calendar)

      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    else
      {:error,
       InvalidDateError.exception(
         unit: :day_of_year,
         value: abs(day),
         valid_range: days_of_year,
         year: year,
         calendar: calendar
       )}
    end
  end

  def resolve(
        [{:year, year}, {:hour, {:group, %Range{} = hours_of_year}}, {:hour, hour} | rest],
        calendar
      )
      when is_integer(year) and is_integer(hour) do
    %{first: first, last: last} = hours_of_year
    hours_in_year = calendar.days_in_year(year) * @hours_per_day
    last = min(last, hours_in_year)
    hour = if hour < 0, do: last + hour + 1, else: first + hour - 1

    with {:ok, _first} <- conform(first, 1..hours_in_year) do
      day = div(hour, @hours_per_day) + 1
      hour = rem(hour, @hours_per_day)

      %{year: year, month: month, day: day} =
        Calendrical.date_from_day_of_year(year, day, calendar)

      resolve([{:year, year}, {:month, month}, {:day, day}, {:hour, hour} | rest], calendar)
    end
  end

  def resolve(
        [{:year, year}, {:month, month}, {:day, {:group, %Range{} = days}} | rest],
        calendar
      )
      when is_integer(year) and is_integer(month) do
    months_in_year = calendar.months_in_year(year)

    with {:ok, month} <- conform(month, 1..months_in_year) do
      max_days = calendar.days_in_month(year, month)

      case resolve([{:day, {:group, %{days | last: min(max_days, days.last)}}} | rest], calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:year, year}, {:month, month} | resolved]
      end
    end
  end

  # days needs to start at 1
  def resolve([{:day, {:group, %Range{} = range}}, {:hour, hours} | rest], calendar)
      when is_integer(hours) do
    first = (range.first - 1) * @hours_per_day
    last = range.last * @hours_per_day - 1
    hours = hours + first

    with {:ok, hours} <- conform(hours, first..last) do
      days = div(hours, @hours_per_day)
      hours = rem(hours, @hours_per_day)
      resolve([{:day, days + 1}, {:hour, hours} | rest], calendar)
    end
  end

  # hours start at 0
  def resolve([{:hour, {:group, %Range{} = range}}, {:minute, minutes} | rest], calendar)
      when is_integer(minutes) do
    first = (range.first - 1) * @minutes_per_hour
    last = range.last * @minutes_per_hour - 1
    minutes = minutes + first

    with {:ok, minutes} <- conform(minutes, first..last) do
      hours = div(minutes, @minutes_per_hour)
      minutes = rem(minutes, @minutes_per_hour)

      resolve([{:hour, hours}, {:minute, minutes} | rest], calendar)
    end
  end

  # minutes start at 0
  def resolve([{:minute, {:group, %Range{} = range}}, {:second, seconds} | rest], calendar)
      when is_integer(seconds) do
    first = (range.first - 1) * @minutes_per_hour
    last = range.last * @minutes_per_hour - 1
    seconds = seconds + first

    with {:ok, seconds} <- conform(seconds, first..last) do
      minutes = div(seconds, @minutes_per_hour)
      seconds = rem(seconds, @minutes_per_hour)

      resolve([{:minute, minutes}, {:second, seconds} | rest], calendar)
    end
  end

  def resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
      when is_integer(year) and is_integer(month) and
             (is_number(day) or is_struct(day, Range) or is_list(day)) do
    with [{:year, year}, {:month, month}] <- resolve([{:year, year}, {:month, month}], calendar),
         {:ok, days_in_month} <- month_length(calendar, year, month),
         {:ok, day} <- conform(day, 1..days_in_month) do
      prepend_year_month(year, month, resolve([{:day, day} | rest], calendar))
    end
  end

  def resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
      when (is_integer(year) and is_integer(month)) or is_list(month) do
    with [{:year, year}, {:month, month}] <- resolve([{:year, year}, {:month, month}], calendar) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:year, year}, {:month, month}, {:day, day} | resolved]
      end
    end
  end

  def resolve([{:year, year}, {:month, months}], calendar)
      when is_integer(year) and
             (is_list(months) or is_integer(months) or is_struct(months, Range)) do
    months_in_year = calendar.months_in_year(year)

    with {:ok, month} <- conform(months, 1..months_in_year) do
      [{:year, year}, {:month, month}]
    end
  end

  def resolve([{:year, year}, {:week, weeks}], calendar)
      when is_integer(year) and (is_list(weeks) or is_integer(weeks)) do
    {weeks_in_year, _} = calendar.weeks_in_year(year)

    with {:ok, weeks} <- conform(weeks, 1..weeks_in_year) do
      [{:year, year}, {:week, weeks}]
    end
  end

  def resolve([{:year, year}, {:day, days}], calendar)
      when is_integer(year) and (is_list(days) or is_integer(days)) do
    days_in_year = calendar.days_in_year(year)

    with {:ok, day} <- conform(days, 1..days_in_year) do
      [{:year, year}, {:day, day}]
    end
  end

  # A day *set* under a month whose length is not yet known — because
  # the year is absent, or set-valued and still to be expanded — is
  # bounded by the month's maximum length across years, exactly as a
  # single day is above: `2M{1..-1}D` is possible (February has a 29th
  # in some year) while `2M{30..31}D` is not. Which days actually
  # exist is settled per member during expansion, where the year is
  # concrete — so this must bound rather than refuse, or
  # `{2020,2021}Y2M{1..-1}D` could never resolve at all.
  def resolve([{:month, month}, {:day, days} | rest], calendar)
      when is_integer(month) and (is_list(days) or is_struct(days, Range)) do
    case max_day_in_month(calendar, month) do
      {:ok, max_day} ->
        with {:ok, days} <- conform(days, 1..max_day),
             rest when is_list(rest) <- resolve(rest, calendar) do
          [{:month, month}, {:day, days} | rest]
        end

      :unknown ->
        with rest when is_list(rest) <- resolve(rest, calendar) do
          [{:month, month}, {:day, days} | rest]
        end
    end
  end

  # A bare (yearless) month + integer day is a partial date — a
  # first-class Tempo value, but only when it could occur in *some*
  # year. `~o"3M2D"` is fine; `~o"2M30D"` (February 30th) happens in
  # no year and is rejected. The bound is the month's maximum length
  # across all years (see `max_day_in_month/2`); a month whose length
  # cannot be bounded without a year is left as-is, since Tempo cannot
  # prove it impossible.
  def resolve([{:month, month}, {:day, day} | rest], calendar)
      when is_integer(month) and is_integer(day) do
    case max_day_in_month(calendar, month) do
      {:ok, max_day} ->
        with {:ok, day} <- conform(day, 1..max_day),
             rest when is_list(rest) <- resolve(rest, calendar) do
          [{:month, month}, {:day, day} | rest]
        end

      :unknown ->
        with rest when is_list(rest) <- resolve(rest, calendar) do
          [{:month, month}, {:day, day} | rest]
        end
    end
  end

  # Calculating the result of fractional time units
  # TODO Support negative time fractions

  def resolve([{:year, year}], calendar) when is_float(year) and year > 0 do
    int_year = trunc(year)
    fraction_of_year = year - int_year
    days_in_year = calendar.days_in_year(int_year)

    if fraction_of_year == 0 do
      resolve([{:year, int_year}], calendar)
    else
      days = Math.round(days_in_year * fraction_of_year, @rounding_precision)
      days = if trunc(days) == days, do: trunc(days), else: days
      resolve([{:year, int_year}, {:day, days}], calendar)
    end
  end

  def resolve([{:year, year}, {:month, month}], calendar)
      when is_integer(year) and is_float(month) and month > 0 do
    int_month = trunc(month)
    fraction_of_month = month - int_month
    days_in_month = calendar.days_in_month(year, int_month)

    if fraction_of_month == 0 do
      resolve([{:year, year}, {:month, int_month}], calendar)
    else
      days = Math.round(days_in_month * fraction_of_month, @rounding_precision)
      days = if trunc(days) == days, do: trunc(days), else: days
      resolve([{:year, year}, {:month, int_month}, {:day, days}], calendar)
    end
  end

  def resolve([{:year, year}, {:day, day}], calendar)
      when is_integer(year) and is_float(day) and day > 0 do
    int_day = trunc(day)
    fraction_of_day = day - int_day

    if fraction_of_day == 0 do
      resolve([{:year, year}, {:day, int_day}], calendar)
    else
      hours = Math.round(@hours_per_day * fraction_of_day, @rounding_precision)
      hours = if trunc(hours) == hours, do: trunc(hours), else: hours
      resolve([{:year, year}, {:day, int_day}, {:hour, hours}], calendar)
    end
  end

  def resolve([{:day, day}], calendar) when is_float(day) and day > 0 do
    int_day = trunc(day)
    fraction_of_day = day - int_day

    if fraction_of_day == 0 do
      [{:day, int_day}]
    else
      hours = Math.round(@hours_per_day * fraction_of_day, @rounding_precision)
      hours = if trunc(hours) == hours, do: trunc(hours), else: hours
      resolve([{:day, int_day}, {:hour, hours}], calendar)
    end
  end

  def resolve([{:hour, hour}], _calendar) when is_float(hour) and hour > 0 do
    int_hour = trunc(hour)
    fraction_of_hour = hour - int_hour

    if fraction_of_hour == 0 do
      [{:hour, int_hour}]
    else
      minutes = Math.round(60 * fraction_of_hour, @rounding_precision)
      minutes = if trunc(minutes) == minutes, do: trunc(minutes), else: minutes
      [{:hour, int_hour}, {:minute, minutes}]
    end
  end

  def resolve([{:minute, minute}], _calendar) when is_float(minute) do
    int_minute = trunc(minute)
    fraction_of_minute = minute - int_minute

    if fraction_of_minute == 0 do
      [{:minute, int_minute}]
    else
      seconds = Math.round(60 * fraction_of_minute, @rounding_precision)
      seconds = if trunc(seconds) == seconds, do: trunc(seconds), else: seconds
      [{:minute, int_minute}, {:second, seconds}]
    end
  end

  # Fill in the blanks with default unit values
  def resolve([{unit_1, value_1}, {:minute, minute} | rest], calendar) when unit_1 != :hour do
    resolve([{unit_1, value_1}, {:hour, 0}, {:minute, minute} | rest], calendar)
  end

  def resolve([{unit_1, value_1}, {:second, second} | rest], calendar) when unit_1 != :minute do
    resolve([{unit_1, value_1}, {:minute, 0}, {:second, second} | rest], calendar)
  end

  # Make sure only the last element is a fraction

  def resolve([{_unit, fraction}, {_unit_2, _value} | _rest], _calendar)
      when is_float(fraction) do
    {:error,
     ParseError.exception(
       reason:
         "A fractional unit can only be used for the highest resolution unit (smallest time unit)"
     )}
  end

  def resolve([{:hour, hour} | rest], calendar) when is_integer(hour) do
    with {:ok, hour} <- conform(hour, 0..(@hours_per_day - 1)) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:hour, hour} | resolved]
      end
    end
  end

  def resolve([{:hour, %Range{first: first, last: last, step: step}} | rest], calendar)
      when first > 0 and last < 0 do
    with {:ok, last} <- conform(last, 0..(@hours_per_day - 1)) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:hour, first..last//abs(step)} | resolved]
      end
    end
  end

  def resolve([{:minute, requested} | rest], calendar) when is_integer(requested) do
    with {:ok, part} <- conform(requested, 0..(@minutes_per_hour - 1)) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:minute, part} | resolved]
      end
    end
  end

  # A fractional second arrives as a sibling `{:fraction, {digits,
  # count}}` token — the seconds parser keeps it separate rather than
  # folding it into a float. Lift it into a `:microsecond {value,
  # precision}` component so the digit count (and therefore the
  # resolution / interval width) is preserved; `.120` and `.12` differ.
  def resolve([{:second, second}, {:fraction, {digits, digit_count}} | rest], calendar)
      when is_integer(second) and is_integer(digits) do
    microsecond = Microsecond.from_fraction(digits, digit_count)
    resolve([{:second, second}, {:microsecond, microsecond} | rest], calendar)
  end

  # Negative seconds wrap using a 0..59 range (the end-of-minute
  # reference is 59, not 60 — `-1` means "one before the end",
  # which is 59, not the leap-second 60).
  def resolve([{:second, requested} | rest], calendar)
      when is_integer(requested) and requested < 0 do
    with {:ok, part} <- conform(requested, 0..(@minutes_per_hour - 1)) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:second, part} | resolved]
      end
    end
  end

  # Positive seconds may take the value 60 for a leap second. The
  # context (hour = 23, minute = 59, and — if present — the calendar
  # date) is checked by `validate_leap_second/2` before we get here.
  def resolve([{:second, requested} | rest], calendar) when is_integer(requested) do
    with {:ok, part} <- conform(requested, 0..@minutes_per_hour) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:second, part} | resolved]
      end
    end
  end

  # Sub-second component: a `{value, precision}` microsecond tuple that
  # rides immediately after the second. Range-validate it and pass it
  # through unchanged. A *list* of microsecond tuples is the enumeration
  # form produced by `Tempo.Enumeration.add_implicit_enumeration/1`
  # when a sub-second value is iterated — validate each element.
  def resolve([{:microsecond, list} | rest], calendar) when is_list(list) do
    if Enum.all?(list, &Microsecond.valid?/1) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:microsecond, list} | resolved]
      end
    else
      {:error, ParseError.exception(reason: "Invalid microsecond enumeration #{inspect(list)}")}
    end
  end

  # Guard the value pattern as `{integer, integer}` so the
  # continuation-wrapped form `{{value, precision}, function}` produced
  # by `Enumeration.do_next/3` falls through to the generic clause and
  # passes through unchanged.
  def resolve([{:microsecond, {value, precision}} | rest], calendar)
      when is_integer(value) and is_integer(precision) do
    if Microsecond.valid?({value, precision}) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:microsecond, {value, precision}} | resolved]
      end
    else
      {:error,
       ParseError.exception(
         reason: "Invalid microsecond component #{inspect({value, precision})}"
       )}
    end
  end

  def resolve([{unit, _value} = first | rest], calendar) do
    with {^unit, _} = first <- resolve(first, calendar),
         rest when is_list(rest) <- resolve(rest, calendar) do
      [first | rest]
    end
  end

  def resolve(other, _calendar) do
    other
  end

  ### Helpers

  defp prepend_year_month(_year, _month, {:error, reason}), do: {:error, reason}

  defp prepend_year_month(year, month, resolved),
    do: [{:year, year}, {:month, month} | resolved]

  # A calendar may report a month as having no days — e.g. the Hebrew Adar I
  # (month 6) does not exist in an ordinary year. Report the missing month
  # clearly rather than building a confusing `1..0` empty day range.
  defp month_length(calendar, year, month) do
    case calendar.days_in_month(year, month) do
      days when is_integer(days) and days > 0 ->
        {:ok, days}

      _no_such_month ->
        {:error,
         InvalidDateError.exception(
           year: year,
           month: month,
           reason: "month #{month} does not exist in #{inspect(calendar)} year #{year}"
         )}
    end
  end

  # The maximum day number a month can hold across all years — the
  # bound for validating a yearless partial. `days_in_month/1` returns
  # an integer for a fixed-length month, `{:ambiguous, lo..hi}` for one
  # that varies (February's `28..29`, whose leap-year `hi` is the
  # maximum), or an error when the length can't be bounded without a
  # year (many lunisolar months), in which case the day is not checked.
  defp max_day_in_month(calendar, month) do
    case calendar.days_in_month(month) do
      days when is_integer(days) and days > 0 -> {:ok, days}
      {:ambiguous, first..last//_step} -> {:ok, max(first, last)}
      _unbounded -> :unknown
    end
  end

  def year_week_day(year, week, day, rest, :month, calendar) do
    # The week → date lookup must happen under ISOWeek semantics
    # regardless of the caller's month-based calendar. Under
    # `Calendrical.Gregorian.week/2`, `week(2020, 53)` returns
    # `{:error, :invalid_date}` (Gregorian doesn't model week 53);
    # and the `(week - 1) * 7` arithmetic fails across the W01-
    # starts-Jan-4 rollover after a 53-week year (2016, 2021, …).
    # `Calendrical.ISOWeek` handles both correctly, and
    # `Date.convert/2` brings the result into the caller's calendar.
    {weeks_in_year, days_in_last_week} = ISOWeek.weeks_in_year(year)

    if day <= days_in_last_week do
      with {:ok, isoweek_date} <- Date.new(year, week, day, Calendrical.ISOWeek),
           {:ok, out_date} <- Date.convert(isoweek_date, calendar) do
        prepend_year(
          out_date.year,
          resolve([{:month, out_date.month}, {:day, out_date.day} | rest], calendar)
        )
      end
    else
      {:error,
       InvalidDateError.exception(
         reason:
           "Day of week #{inspect(day)} is not valid. " <>
             "There are #{inspect(days_in_last_week)} days in #{inspect(year)}-W#{inspect(weeks_in_year)}."
       )}
    end
  end

  def year_week_day(year, week, day, rest, :week, calendar) do
    prepend_year(year, resolve([{:week, week}, {:day, day} | rest], calendar))
  end

  defp prepend_year(_year, {:error, reason}), do: {:error, reason}
  defp prepend_year(year, resolved), do: [{:year, year} | resolved]

  def year_and_month(years, month, calendar) do
    return =
      Enum.reduce_while(years, {calendar.months_in_year(years.first), month}, fn year,
                                                                                 {acc, to_go} ->
        months_in_year = calendar.months_in_year(year)

        if to_go <= months_in_year do
          {:halt, {:ok, year, to_go}}
        else
          {:cont, {acc + months_in_year, to_go - months_in_year}}
        end
      end)

    case return do
      {:ok, year, month} -> {:ok, year, month}
      _other -> {:error, :invalid_date}
    end
  end

  def month_and_day(year, months, day, calendar) do
    return =
      Enum.reduce_while(months, {calendar.days_in_month(year, months.first), day}, fn month,
                                                                                      {acc, to_go} ->
        days_in_month = calendar.days_in_month(year, month)

        if to_go <= days_in_month do
          {:halt, {:ok, month, to_go}}
        else
          {:cont, {acc + days_in_month, to_go - days_in_month}}
        end
      end)

    case return do
      {:ok, month, day} -> {:ok, month, day}
      _other -> {:error, :invalid_date}
    end
  end

  def conform(integer, %Range{first: first, last: last})
      when is_integer(integer) and integer in first..last//1 do
    {:ok, integer}
  end

  def conform(float, %Range{first: first, last: last})
      when is_float(float) and float >= first and float <= last do
    {:ok, float}
  end

  def conform(integer, %Range{last: last} = range) when is_integer(integer) and integer < 0 do
    value = last + integer + 1

    case value >= 0 && conform(value, range) do
      {:ok, value} ->
        {:ok, value}

      {:error, _} ->
        normalized_error(integer, value, range)

      false ->
        normalized_error(integer, value, range)
    end
  end

  def conform(%Range{first: f1, last: t1} = from, %Range{first: f2, last: t2})
      when f1 in f2..t2//1 and t1 in f2..t2//1 do
    {:ok, from}
  end

  def conform(%Range{first: f1, last: t1, step: step}, %Range{} = to) do
    with {:ok, from} <- conform(f1, to),
         {:ok, to} <- conform(t1, to) do
      {:ok, from..to//abs(step)}
    end
  end

  def conform(from, to) when is_list(from) do
    conformed =
      Enum.reduce_while(from, {:ok, []}, fn unit, {:ok, acc} ->
        case conform(unit, to) do
          {:ok, conformed} -> {:cont, {:ok, [conformed | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case conformed do
      {:error, reason} -> {:error, reason}
      {:ok, other} -> {:ok, Enum.reverse(other)}
    end
  end

  def conform(from, to) do
    range =
      case to do
        %Range{} = r -> r
        _other -> nil
      end

    {:error,
     InvalidDateError.exception(
       value: from,
       valid_range: range,
       reason: "#{inspect(from)} is not valid. The valid values are #{inspect(to)}"
     )}
  end

  defp normalized_error(value, normalized, range) do
    {:error,
     InvalidDateError.exception(
       value: value,
       valid_range: range,
       reason:
         "#{inspect(value)} is not valid. The normalized value of " <>
           "#{inspect(normalized)} is outside the range #{inspect(range)}"
     )}
  end

  ## Leap-second validation

  # A `second = 60` is the ISO 8601 leap-second value. It is only valid
  # when:
  #
  # * The minute is 59 and the hour is 23 (immediately before the UTC
  #   day boundary).
  #
  # * If the calendar date is known, it must be 30 June or 31 December
  #   (the only two dates on which UTC announces leap seconds).
  #
  # * If a time-zone offset is present, it must resolve to the UTC
  #   instant at the day boundary. In practice we require the offset
  #   to be zero when the date is specified; without a date we accept
  #   any offset because the caller is describing a repeating local
  #   time.
  # Leap seconds — policy decision.
  #
  # ISO 8601 permits `:second = 60` as a positive leap second.
  # Tempo used to accept it on the 27 IERS-announced dates. That
  # put Tempo out of step with the rest of the Elixir/OTP
  # ecosystem — `Calendar.ISO.valid_time?/4`, `Time.new/4`,
  # `DateTime.new/3`, and `:calendar.datetime_to_gregorian_seconds/1`
  # all reject or silently collide on `:60`.
  #
  # Aligning with the ecosystem means rejecting `:60` at parse
  # regardless of date. Leap-second information remains available
  # as an **interval-level concern**:
  #
  # * `Tempo.LeapSeconds.dates/0` — the 27 historical insertions.
  # * `Tempo.Interval.spans_leap_second?/1` — does `[from, to)`
  #   contain an IERS leap-second boundary?
  # * `Tempo.Interval.leap_seconds_spanned/1` — list of the dates.
  # * `Tempo.Interval.duration(iv, leap_seconds: true)` — include
  #   spanned leap seconds in the returned duration.
  #
  # Scientific callers who need exact elapsed time across leap
  # seconds use those APIs; everyone else gets stdlib-compatible
  # behaviour for free.

  defp validate_leap_second(units, _tempo) when is_list(units) do
    case List.keyfind(units, :second, 0) do
      {:second, 60} ->
        {:error,
         InvalidTimeError.exception(
           unit: :second,
           value: 60,
           valid_range: 0..59,
           reason:
             "A second value of 60 (leap second) is not accepted as a Tempo value. " <>
               "Elixir's `Calendar.ISO` and `DateTime` reject it too. Use " <>
               "`Tempo.LeapSeconds.dates/0` for the historical list, or " <>
               "`Tempo.Interval.spans_leap_second?/1` to detect leap seconds in " <>
               "an interval."
         )}

      _ ->
        :ok
    end
  end

  defp validate_leap_second(_units, _tempo), do: :ok

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: Integer.to_string(n)

  defp fetch_unit(units, unit) do
    case List.keyfind(units, unit, 0) do
      {^unit, value} -> value
      _ -> nil
    end
  end

  # Bounds-check an ISO 8601 / RFC 3339 time-zone offset. The
  # tokenizer accepts any signed 2-4 digit magnitude; real zones
  # are bounded to ±24h wall-clock. The IANA data carries historical
  # offsets that never exceed about +14 (Pacific/Kiritimati) or
  # −12 (Pacific/Midway pre-2011), so ±24h is permissive.
  @max_offset_minutes 24 * 60

  defp validate_time_shift(nil), do: :ok

  defp validate_time_shift(shift) when is_list(shift) do
    hour = fetch_unit(shift, :hour) || 0
    minute = fetch_unit(shift, :minute) || 0
    second = fetch_unit(shift, :second) || 0
    magnitude = abs(hour) * 3600 + abs(minute) * 60 + abs(second)

    if magnitude > @max_offset_minutes * 60 do
      {:error,
       ParseError.exception(
         reason:
           "Time-zone offset out of range. Offsets must be within ±24h; " <>
             "got #{inspect(shift)}."
       )}
    else
      :ok
    end
  end

  defp validate_time_shift(_), do: :ok

  @doc """
  Validate an IXDTF numeric offset (minutes) for the `[+HH:MM]`
  form. Called from the tokenizer when the offset lands on
  `extended.zone_offset`.
  """
  @spec validate_ixdtf_offset_minutes(integer()) :: :ok | {:error, Exception.t()}
  def validate_ixdtf_offset_minutes(minutes) when is_integer(minutes) do
    if abs(minutes) > @max_offset_minutes do
      {:error,
       ParseError.exception(
         reason:
           "Numeric zone offset out of range. Offsets must be within ±24h; " <>
             "got #{format_offset(minutes)}."
       )}
    else
      :ok
    end
  end

  defp format_offset(minutes) do
    sign = if minutes < 0, do: "-", else: "+"
    m = abs(minutes)
    "#{sign}#{div(m, 60)}:#{pad2(rem(m, 60))}"
  end

  @doc """
  Check that an anchored, zoned Tempo value refers to a wall
  time that actually exists in its IANA time zone.

  During a DST spring-forward transition, an hour of local time
  ceases to exist — `02:30 America/New_York` on 2024-03-10 does
  not refer to any real UTC instant. ISO 8601 permits the
  syntax; Tempo rejects the semantics at parse time so downstream
  set operations, comparisons, and durations never encounter a
  phantom value.

  The check applies only when all of these hold:

  * The value is a bare `%Tempo{}` (Interval/Set values are
    composed of Tempos and checked via recursion).

  * The value has year, month, day, hour, minute (fully anchored
    at least to the minute — coarser values like "2024-03" can
    never land in a gap because the gap is minute-scale).

  * The value carries an IANA zone id on `extended.zone_id`.

  Returns `:ok` when the wall time is valid, or `{:error, ...}`
  when it falls in a DST (or other) gap.

  Ambiguous wall times (e.g. the doubled hour during a DST
  fall-back) are accepted — the caller can disambiguate via an
  explicit zone offset in the IXDTF suffix.

  """
  @spec validate_zone_existence(Tempo.t() | Tempo.Interval.t() | Tempo.Set.t() | term()) ::
          :ok | {:error, Exception.t()}
  def validate_zone_existence(%Tempo.Interval{from: from, to: to}) do
    with :ok <- validate_zone_existence(from) do
      validate_zone_existence(to)
    end
  end

  def validate_zone_existence(%Tempo.Set{set: values}) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case validate_zone_existence(value) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  def validate_zone_existence(%Tempo{} = tempo) do
    case zone_id(tempo) do
      nil -> :ok
      zone -> check_wall_time_in_zone(tempo, zone)
    end
  end

  def validate_zone_existence(_other), do: :ok

  defp zone_id(%Tempo{extended: %{zone_id: zone}}) when is_binary(zone) and zone != "",
    do: zone

  defp zone_id(_), do: nil

  defp check_wall_time_in_zone(%Tempo{time: time}, zone) do
    case fully_anchored_datetime(time) do
      # Pre-common-era wall times cannot fall into a zone-transition
      # gap — standardised time (and every IANA rule) begins many
      # centuries later, so local mean time applies throughout. The
      # guard also matters mechanically: the zone database feeds the year to
      # `:calendar.last_day_of_the_month/2`, whose OTP ≤ 28 guards
      # reject negative years with a `FunctionClauseError`. A value
      # like `~o"2022-06-15T10:00[Europe/Paris][u-ca=hebrew]"` — the
      # units read as Hebrew year 2022, ≈ 1739 BCE Gregorian — must
      # validate cleanly, not crash.
      {:ok, {{year, _month, _day}, _time}} when year < 1 ->
        :ok

      {:ok, {{year, month, day}, {hour, minute, second}} = datetime} ->
        wall = :calendar.datetime_to_gregorian_seconds(datetime)

        case TimeZoneDatabase.period_at_wall(zone, wall) do
          {:gap, _before, _after} ->
            {:error,
             ZoneGapError.exception(
               wall_time:
                 "#{year}-#{pad2(month)}-#{pad2(day)}T#{pad2(hour)}:#{pad2(minute)}:#{pad2(second)}",
               zone_id: zone,
               reason: :dst_gap,
               detail: "it falls inside a daylight-saving or zone-transition gap"
             )}

          _ok_ambiguous_or_no_database ->
            # `{:ok, _}` = unambiguous. `{:ambiguous, _, _}` = fall-back
            # ambiguity, accepted silently (the caller can disambiguate
            # with an explicit offset). `{:error, _}` = no configured
            # database or unknown zone — nothing to check against.
            :ok
        end

      :not_fully_anchored ->
        :ok
    end
  end

  # The zone-existence check only fires when the value is fully
  # anchored down to the minute — coarser resolutions ("2024-03",
  # "2024-03-10", "2024-03-10T02") can't land in a gap because the
  # gap is smaller than the value's resolution.
  defp fully_anchored_datetime(time) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         hour when is_integer(hour) <- Keyword.get(time, :hour),
         minute when is_integer(minute) <- Keyword.get(time, :minute) do
      second = integer_second(Keyword.get(time, :second, 0))
      {:ok, {{year, month, day}, {hour, minute, second}}}
    else
      _ -> :not_fully_anchored
    end
  end

  defp integer_second(s) when is_integer(s), do: s
  defp integer_second(s) when is_float(s), do: trunc(s)
  defp integer_second(_), do: 0
end
