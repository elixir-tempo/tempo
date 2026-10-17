defmodule Tempo.Matrix.CalendarCensus do
  @moduledoc """
  The calendar census: a value in each full form, and a selection of each
  kind, in each calendar module Calendrical ships, with what each covers
  and what its walk yields worked out from the calendar alone (see
  `plans/enumeration-and-selection.md`).

  Nothing here calls `Tempo`. A span is counted from the calendar's
  `valid_date?/3`, `months_in_year/1`, `weeks_in_year/1`, `week/2`,
  `month/2` and `year/1`, and from `Date`, in microseconds of the count of
  days `Date.to_gregorian_days/1` keeps, which is what
  `Tempo.Matrix.Extent` reads a value as.

  The readings it holds:

  * **A month with days missing** — a month's days are those the calendar
    says are dates (`valid_date?/3`), so the September of 1752 in
    `Calendrical.Reform.England` is the days 1, 2 and 14 to 30.

  * **A year that starts within its months** — in a Julian calendar whose
    year begins on 25 March, a year is the dates of the calendar's `year/1`
    and a month with no day is the nth month it counts, the dates of its
    `month/2`; a date keeps the month it names (decided 2026-10-04).

  * **A calendar of weeks** — a week is the dates of the calendar's own
    `week/2`, and a day of the week the nth of them, whatever day the
    calendar's week begins on (decided 2026-10-05).

  * **A value with no year** — a month or a day of one with no year is on
    the cycle of the longest year, in which every date has a place: the
    most months a year has, each as long as it gets, counted from the
    calendar's `months_in_year/0` and `days_in_month/1`. What follows a
    value is the next where every year has it, and the first of the next
    period after the last value the longest period has; between the two it
    depends on the year, and the value's span needs one.

  The observational Islamic calendars work each date out from the moon, and
  the calendar's own answer for one of their years takes half a minute, so
  they are apart (`observed/0`) and their full forms alone are asked, when
  asked for. A selection in a year that starts within its months is not
  here: it is not built.

  """

  alias Calendrical.FiscalYear
  alias Tempo.Matrix.Selections

  @anchors [~D[2026-06-15], ~D[2024-02-29], ~D[2025-08-01]]

  @second 1_000_000
  @day 86_400 * @second

  # The zone a value is written in, to measure a zone beside each calendar.
  @zone "Europe/Paris"

  @calendars [
    Calendrical.Gregorian,
    Calendrical.Julian,
    Calendrical.Buddhist,
    Calendrical.Roc,
    Calendrical.Japanese,
    Calendrical.Indian,
    Calendrical.Persian,
    Calendrical.Coptic,
    Calendrical.Ethiopic,
    Calendrical.Ethiopic.AmeteAlem,
    Calendrical.Islamic.Civil,
    Calendrical.Islamic.Tbla,
    Calendrical.Islamic.UmmAlQura,
    Calendrical.Hebrew,
    Calendrical.Chinese,
    Calendrical.Korean,
    Calendrical.Vietnamese,
    Calendrical.LunarJapanese,
    Calendrical.Reform.England,
    Calendrical.Reform.Sweden,
    Calendrical.Julian.March25,
    Calendrical.Julian.March1,
    Calendrical.Julian.Sept1,
    Calendrical.Julian.Dec25,
    Calendrical.ISOWeek,
    Calendrical.NRF
  ]

  @typedoc "A span, from its first microsecond to the one after its last."
  @type span :: {integer(), integer()}

  @typedoc """
  A value as its parts, for the census's reader to build in the calendar
  asked: a value's units (`Tempo.new/1`), an interval of two values
  (`Tempo.Interval.new/1`), or a recurrence of a count, a start's units and
  a cadence's units (`Tempo.every/2`).
  """
  @type parts ::
          {:value, keyword()}
          | {:span, keyword(), keyword()}
          | {:every, pos_integer(), keyword(), keyword()}

  @doc """
  The calendars of the census.

  ### Returns

  * A list of calendar modules.

  """
  @spec calendars() :: [module()]
  def calendars do
    @calendars ++ [fiscal_calendar()]
  end

  # A fiscal calendar is made for a territory when it is asked for: the
  # Australian fiscal year begins in July.
  defp fiscal_calendar do
    {:ok, calendar} = FiscalYear.calendar_for(:AU)
    calendar
  end

  @doc """
  The calendars whose dates are worked out from an observation of the
  moon, which take seconds to answer for a month and are asked apart.

  ### Returns

  * A list of calendar modules.

  """
  @spec observed() :: [module()]
  def observed do
    [Calendrical.Islamic.Observational, Calendrical.Islamic.Rgsa]
  end

  @doc """
  A value in each full form, on each of the census's dates.

  ### Arguments

  * `calendar` is a calendar module.

  ### Returns

  * A list of `%{form: name, parts: parts, expect: what}`, where `parts`
    is a `t:parts/0` and `what` is given to `expected/2`.

  """
  @spec forms(module()) :: [%{form: String.t(), parts: parts(), expect: tuple()}]
  def forms(calendar) do
    for date <- anchors(calendar),
        {form, parts, expect} <- forms_on(date) ++ week_forms_on(date, calendar) do
      %{form: form, parts: parts, expect: expect}
    end
  end

  # The census's dates in the calendar, and for a reform calendar a date in
  # the month the reform cut short.
  defp anchors(Calendrical.Reform.England = calendar) do
    Enum.map(@anchors ++ [~D[1752-09-20]], &Date.convert!(&1, calendar))
  end

  defp anchors(calendar) do
    Enum.map(@anchors, &Date.convert!(&1, calendar))
  end

  # The calendars of weeks, which are asked a week, a day of one and a
  # selection in one beside what every calendar is asked. Their dates are a
  # year, a month and a day, as every calendar's are, and the week a date is
  # in is the calendar's to say (`week_date_from_date/3`).
  @of_weeks [Calendrical.ISOWeek, Calendrical.NRF]

  defp week_forms_on(%Date{} = date, calendar) when calendar in @of_weeks do
    {y, w, k} = week_date(date, calendar)

    [
      {"Y-W", {:value, [year: y, week: w]}, {:week, y, w}},
      {"Y-W-K", {:value, [year: y, week: w, day_of_week: k]}, {:week_day, y, w, k, []}},
      {"Y-W-K T H", {:value, [year: y, week: w, day_of_week: k, hour: 10]},
       {:week_day, y, w, k, [hour: 10]}},
      {"Y-W-K T H zone", {:value, [year: y, week: w, day_of_week: k, hour: 10, zone: @zone]},
       {:week_day_in_zone, y, w, k, 10}}
    ]
  end

  defp week_forms_on(_date, _calendar) do
    []
  end

  defp week_date(%Date{year: year, month: month, day: day}, calendar) do
    {_week_year, _week, _day_of_week} = calendar.week_date_from_date(year, month, day)
  end

  defp forms_on(%Date{year: y, month: m, day: d} = date) do
    [
      {"Y", {:value, [year: y]}, {:year, y}},
      {"Y-M", {:value, [year: y, month: m]}, {:month, y, m}},
      {"Y-M-D", {:value, [year: y, month: m, day: d]}, {:day, y, m, d, []}},
      {"Y-M-D T H", {:value, [year: y, month: m, day: d, hour: 10]}, {:day, y, m, d, [hour: 10]}},
      {"Y-M-D T H:M", {:value, [year: y, month: m, day: d, hour: 10, minute: 30]},
       {:day, y, m, d, [hour: 10, minute: 30]}},
      {"Y-M-D T H:M:S", {:value, [year: y, month: m, day: d, hour: 10, minute: 30, second: 45]},
       {:day, y, m, d, [hour: 10, minute: 30, second: 45]}},
      {"Y-O", {:value, [year: y, day_of_year: Date.day_of_year(date)]}, {:day, y, m, d, []}},
      {"Y-M-D T H zone", {:value, [year: y, month: m, day: d, hour: 10, zone: @zone]},
       {:day_in_zone, y, m, d, 10}},
      {"Y-M-D T H:M:S.s",
       {:value,
        [year: y, month: m, day: d, hour: 10, minute: 30, second: 45, microsecond: {500_000, 1}]},
       {:tenth, y, m, d, {10, 30, 45, 5}}}
    ]
  end

  @doc """
  What a form covers and what its walk yields, from the calendar alone.

  ### Arguments

  * `expect` is the `:expect` of an entry of `forms/1`.

  * `calendar` is the calendar module the form is written in.

  ### Returns

  * `{span, walk}`, where `walk` is the spans the value's walk yields, in
    order, or `:unchecked` for a second, which has nothing finer to walk.

  """
  @spec expected(tuple(), module()) :: {span(), [span()] | :unchecked}
  def expected({:year, y}, calendar) do
    months = for m <- 1..calendar.months_in_year(y), do: month_span(y, m, calendar)
    {{elem(hd(months), 0), elem(List.last(months), 1)}, months}
  end

  def expected({:month, y, m}, calendar) do
    {month_span(y, m, calendar), Enum.map(month_dates(y, m, calendar), &day_span/1)}
  end

  def expected({:day, y, m, d, time}, calendar) do
    clock(iso(y, m, d, calendar), time)
  end

  def expected({:first_day, y, m, time}, calendar) do
    clock(hd(month_dates(y, m || 1, calendar)), time)
  end

  def expected({:week, y, w}, calendar) do
    {week_span(y, w, calendar), Enum.map(week_dates(y, w, calendar), &day_span/1)}
  end

  def expected({:week_day, y, w, k, time}, calendar) do
    clock(Enum.at(week_dates(y, w, calendar), k - 1), time)
  end

  def expected({:day_in_zone, y, m, d, hour}, calendar) do
    hour_in_zone(iso(y, m, d, calendar), hour)
  end

  def expected({:week_day_in_zone, y, w, k, hour}, calendar) do
    hour_in_zone(Enum.at(week_dates(y, w, calendar), k - 1), hour)
  end

  # A second written to a tenth is a tenth of a second long.
  def expected({:tenth, y, m, d, {hour, minute, second, tenth}}, calendar) do
    from = at(iso(y, m, d, calendar)) + (hour * 3600 + minute * 60 + second) * @second
    {{from + tenth * 100_000, from + (tenth + 1) * 100_000}, :unchecked}
  end

  # The dates of a month, as `Calendar.ISO` dates: those the calendar says
  # are dates of it, or, in a year that starts within its months, the dates
  # of the nth month the calendar counts.
  defp month_dates(y, m, calendar) do
    if starts_within_its_months?(y, calendar) do
      Enum.map(calendar.month(y, m), &Date.convert!(&1, Calendar.ISO))
    else
      for(d <- 1..40, calendar.valid_date?(y, m, d), do: iso(y, m, d, calendar))
    end
  end

  defp month_span(y, m, calendar) do
    dates = month_dates(y, m, calendar)
    {at(hd(dates)), at(List.last(dates)) + @day}
  end

  # A year starts within its months where its first date is not the first
  # day of its first month.
  defp starts_within_its_months?(y, calendar) do
    case calendar.year(y) do
      %Date.Range{first: %Date{month: 1, day: 1}} -> false
      %Date.Range{} -> true
    end
  end

  defp week_dates(y, w, calendar) do
    Enum.map(calendar.week(y, w), &Date.convert!(&1, Calendar.ISO))
  end

  defp week_span(y, w, calendar) do
    dates = week_dates(y, w, calendar)
    {at(hd(dates)), at(List.last(dates)) + @day}
  end

  defp weeks_in_year(y, calendar) do
    calendar.weeks_in_year(y)
  end

  defp iso(y, m, d, calendar) do
    y
    |> Date.new!(m, d, calendar)
    |> Date.convert!(Calendar.ISO)
  end

  defp day_span(%Date{} = day) do
    {at(day), at(day) + @day}
  end

  defp clock(day, []) do
    {day_span(day), for(h <- 0..23, do: unit_span(day, h * 3600, 3600))}
  end

  defp clock(day, hour: h) do
    {unit_span(day, h * 3600, 3600), for(mi <- 0..59, do: unit_span(day, h * 3600 + mi * 60, 60))}
  end

  defp clock(day, hour: h, minute: mi) do
    from = h * 3600 + mi * 60
    {unit_span(day, from, 60), for(s <- 0..59, do: unit_span(day, from + s, 1))}
  end

  defp clock(day, hour: h, minute: mi, second: s) do
    {unit_span(day, h * 3600 + mi * 60 + s, 1), :unchecked}
  end

  defp unit_span(day, seconds, length) do
    {at(day) + seconds * @second, at(day) + (seconds + length) * @second}
  end

  defp at(%Date{} = date) do
    Date.to_gregorian_days(date) * @day
  end

  # An hour on a day's own clock in the zone, as the moments it is: Elixir's
  # `DateTime` says when that wall time is.
  defp hour_in_zone(%Date{} = day, hour) do
    moment = DateTime.new!(day, Time.new!(hour, 0, 0), @zone)

    from =
      DateTime.to_gregorian_seconds(moment)
      |> elem(0)
      |> Kernel.*(@second)

    {{from, from + 3600 * @second},
     for(minute <- 0..59, do: {from + minute * 60 * @second, from + (minute + 1) * 60 * @second})}
  end

  ## A value with no year

  @typedoc """
  What a value with no year covers: a span of its cycle, or that it needs a
  year to say, or that no year has such a value.
  """
  @type covers :: {:ok, span()} | :needs_a_year | :no_such_value

  @typedoc """
  What a walk of a value with no year yields: where each value starts on
  the cycle, how many values, that it needs a year, or nothing asked.
  """
  @type walk :: {:ok, [integer()]} | {:count, pos_integer()} | :needs_a_year | :unchecked

  @doc """
  The values with no year a calendar's own counts answer: every month and
  every day of each, in a calendar of months, and every day of the week.

  A reform calendar counts nothing with no year, so each of a few months
  and days of it needs a year. A year that starts within its months is left
  out: with no year a month there is the one a date names, and with a year
  the nth the calendar counts.

  ### Arguments

  * `calendar` is a calendar module.

  ### Returns

  * A list of `%{parts: parts, covers: covers, walk: walk}`, where `parts`
    is a `t:parts/0`.

  """
  @spec no_year(module()) :: [%{parts: parts(), covers: covers(), walk: walk()}]
  def no_year(calendar) do
    if starts_within_its_months?(hd(anchors(calendar)).year, calendar) do
      []
    else
      months_no_year(calendar, calendar.months_in_year()) ++ weekdays_no_year()
    end
  end

  defp weekdays_no_year do
    days =
      for k <- 1..7 do
        from = (k - 1) * @day

        %{
          parts: {:value, [day_of_week: k]},
          covers: {:ok, {from, from + @day}},
          walk: {:ok, hours_from(from)}
        }
      end

    days ++ [%{parts: {:value, [day_of_week: 8]}, covers: :no_such_value, walk: :unchecked}]
  end

  defp hours_from(from) do
    for(h <- 0..23, do: from + h * 3600 * @second)
  end

  # A calendar whose years are not alike enough for `months_in_year/0` to
  # answer may still count the same months in every year, which its bounds
  # say (`months_in_year_bounds/0`, the redesign's contract); one that counts
  # nothing with no year needs a year for each of a few months and days.
  defp months_no_year(calendar, {:error, _undefined}) do
    case calendar.months_in_year_bounds() do
      {months, months} ->
        months_no_year(calendar, months)

      _unalike ->
        for m <- [1, 6, 12],
            cell <- [
              %{parts: {:value, [month: m]}, walk: :needs_a_year},
              %{parts: {:value, [month: m, day: 15]}, walk: {:count, 24}}
            ] do
          Map.put(cell, :covers, :needs_a_year)
        end
    end
  end

  defp months_no_year(calendar, months) do
    {least, most} = fewest_and_most(months)
    counts = %{least_months: least, most_months: most, calendar: calendar}

    Enum.flat_map(1..most, &month_no_year(&1, counts)) ++
      [%{parts: {:value, [month: most + 1]}, covers: :no_such_value, walk: :unchecked}]
  end

  defp month_no_year(m, %{calendar: calendar} = counts) do
    {fewest, most} = day_bounds(calendar, m)
    from = days_before(m, calendar) * @day
    followed? = followed_in_every_year?(m, counts)

    month = %{
      parts: {:value, [month: m]},
      covers:
        if followed? do
          {:ok, {from, from + most * @day}}
        else
          :needs_a_year
        end,
      walk:
        if fewest == most do
          {:ok, for(d <- 1..most, do: from + (d - 1) * @day)}
        else
          :needs_a_year
        end
    }

    days =
      for d <- 1..(most + 1) do
        day_from = from + (d - 1) * @day

        %{
          parts: {:value, [month: m, day: d]},
          covers: day_covers(d, {fewest, most}, followed?, day_from),
          walk:
            if d in [1, fewest, most] do
              {:ok, hours_from(day_from)}
            else
              :unchecked
            end
        }
      end

    [month | days]
  end

  # A day below the last every year has is followed by the next. The last
  # day the longest month has is followed by the first of the next month,
  # where that is the same month in every year. Between the two, and where
  # the month after depends on the year, the day's span needs a year.
  defp day_covers(d, {_fewest, most}, _followed?, _from) when d > most do
    :no_such_value
  end

  defp day_covers(d, {fewest, _most}, _followed?, from) when d < fewest do
    {:ok, {from, from + @day}}
  end

  defp day_covers(most, {_fewest, most}, true, from) do
    {:ok, {from, from + @day}}
  end

  defp day_covers(_d, _days, _followed?, _from) do
    :needs_a_year
  end

  # A month every year has is followed by the next, and the last month of
  # the year that has the most by the first of the next year. A month
  # between the two is followed by one or the other by the year.
  defp followed_in_every_year?(m, %{least_months: least, most_months: most}) do
    m < least or m == most
  end

  defp days_before(m, calendar) do
    Enum.sum(for earlier <- 1..(m - 1)//1, do: elem(day_bounds(calendar, earlier), 1))
  end

  # The fewest and the most days a month has in any year, from the calendar's
  # own count or, where its years are not alike enough for one, its bounds.
  defp day_bounds(calendar, month) do
    case calendar.days_in_month(month) do
      {:error, _undefined} -> calendar.days_in_month_bounds(month)
      counts -> fewest_and_most(counts)
    end
  end

  defp fewest_and_most(count) when is_integer(count) do
    {count, count}
  end

  defp fewest_and_most({:ambiguous, %Range{first: first, last: last}}) do
    {min(first, last), max(first, last)}
  end

  # A month of a calendar of weeks has one of two counts, which are not a run.
  defp fewest_and_most({:ambiguous, [_ | _] = counts}) do
    {Enum.min(counts), Enum.max(counts)}
  end

  ## Shapes, intervals and recurrences

  @doc """
  A value in each shape, an interval and a recurrence, on the census's
  first date: a set, a range, a count from the end, a mask and an
  unspecified unit; an interval of days and one of months or weeks; a
  recurrence that steps by days, by months or weeks, and by years.

  ### Arguments

  * `calendar` is a calendar module.

  ### Returns

  * A list of `%{shape: name, parts: parts, members: spans, walk: walk}`,
    where `spans` is a list with the spans of each member the value
    converts to, and `walk` is `{:ok, starts}`, where each value the walk
    yields starts, or `:unchecked`. It is empty for a calendar whose year
    starts within its months.

  """
  @spec shapes(module()) :: [map()]
  def shapes(calendar) do
    date = hd(anchors(calendar))

    if starts_within_its_months?(date.year, calendar) do
      []
    else
      month_shapes(date, calendar) ++ week_shapes(date, calendar)
    end
  end

  defp month_shapes(%Date{} = date, calendar) do
    shaped_months(date, calendar) ++
      spanned_months(date, calendar) ++ repeated_months(date, calendar)
  end

  # A set, a range, a count from the end, a mask and an unspecified unit.
  defp shaped_months(%Date{year: y, month: m}, calendar) do
    months = calendar.months_in_year(y)
    dates = month_dates(y, m, calendar)
    last_month = month_dates(y, months, calendar)

    [
      shape("a set of months", {:value, [year: y, month: [1, 3]]}, [
        month_span(y, 1, calendar),
        month_span(y, 3, calendar)
      ]),
      shape(
        "a range of days",
        {:value, [year: y, month: m, day: [1..3]]},
        dates
        |> Enum.take(3)
        |> Enum.map(&day_span/1)
      ),
      shape("a set of days", {:value, [year: y, month: m, day: [1, 3]]}, [
        day_span(hd(dates)),
        day_span(Enum.at(dates, 2))
      ]),
      whole(
        "the last month",
        {:value, [year: y, month: -1]},
        month_span(y, months, calendar),
        Enum.map(last_month, &at/1)
      ),
      whole(
        "the last day of a month",
        {:value, [year: y, month: m, day: -1]},
        day_span(List.last(dates)),
        hours(List.last(dates))
      ),
      whole(
        "the last day of the last month",
        {:value, [year: y, month: -1, day: -1]},
        day_span(List.last(last_month)),
        :unchecked
      ),
      # A mask or an unspecified unit names each value its digits allow, and
      # each is a member of its own (law 6 of the redesign).
      each(
        "a masked day",
        {:value, [year: y, month: m, day: {:mask, [:x, :x]}]},
        Enum.map(dates, &day_span/1)
      ),
      each(
        "an unspecified day",
        {:value, [year: y, month: m, day: :any]},
        Enum.map(dates, &day_span/1)
      ),
      each(
        "an unspecified month",
        {:value, [year: y, month: :any]},
        Enum.map(1..months, &month_span(y, &1, calendar))
      )
    ]
  end

  # An interval of days that runs into the next month, and one of months.
  defp spanned_months(%Date{year: y, month: m, day: d}, calendar) do
    day = iso(y, m, d, calendar)
    later = Date.convert!(Date.add(day, 40), calendar)
    {after_y, after_m} = months_on(y, m, 2, calendar)
    from = elem(month_span(y, m, calendar), 0)

    # A written date end is the date the interval runs through (law 9 of the
    # redesign): forty-one days, and the months from the first through the third.
    [
      whole(
        "an interval of days",
        {:span, [year: y, month: m, day: d],
         [year: later.year, month: later.month, day: later.day]},
        {at(day), at(day) + 41 * @day},
        Enum.map(0..40, &(at(day) + &1 * @day))
      ),
      whole(
        "an interval of months",
        {:span, [year: y, month: m], [year: after_y, month: after_m]},
        {from, elem(month_span(after_y, after_m, calendar), 1)},
        month_starts(y, m, 3, calendar)
      )
    ]
  end

  # A recurrence by days, by months and by years, each occurrence as long as
  # its step.
  defp repeated_months(%Date{year: y, month: m, day: d}, calendar) do
    day = at(iso(y, m, d, calendar))

    [
      shape(
        "a recurrence by days",
        {:every, 4, [year: y, month: m, day: d], [day: 10]},
        Enum.map(0..3, &{day + 10 * &1 * @day, day + 10 * (&1 + 1) * @day})
      ),
      shape(
        "a recurrence by months",
        {:every, 4, [year: y, month: m], [month: 1]},
        Enum.map(0..3, &counted_month_span(y, m, &1, calendar))
      ),
      shape(
        "a recurrence by years",
        {:every, 3, [year: y], [year: 1]},
        Enum.map(0..2, &year_span(y + &1, calendar))
      )
    ]
  end

  # Where each of so many months starts, from a month on.
  defp month_starts(y, m, count, calendar) do
    Enum.map(0..(count - 1), &elem(counted_month_span(y, m, &1, calendar), 0))
  end

  defp week_shapes(%Date{} = date, calendar) when calendar in @of_weeks do
    {y, w, _day_of_week} = week_date(date, calendar)
    weeks = weeks_in_year(y, calendar)
    dates = week_dates(y, w, calendar)
    week = week_span(y, w, calendar)

    [
      shape(
        "a set of weeks",
        {:value, [year: y, week: [1, 3]]},
        for(n <- [1, 3], do: week_span(y, n, calendar))
      ),
      whole(
        "the last week",
        {:value, [year: y, week: -1]},
        week_span(y, weeks, calendar),
        Enum.map(week_dates(y, weeks, calendar), &at/1)
      ),
      shape(
        "a range of days",
        {:value, [year: y, week: w, day_of_week: [1..3]]},
        dates
        |> Enum.take(3)
        |> Enum.map(&day_span/1)
      ),
      whole(
        "the last day of a week",
        {:value, [year: y, week: w, day_of_week: -1]},
        day_span(List.last(dates)),
        hours(List.last(dates))
      ),
      # A written week end is the week the interval runs through (law 9).
      whole(
        "an interval of weeks",
        {:span, [year: y, week: w], [year: y, week: w + 2]},
        {elem(week, 0), elem(week_span(y, w + 2, calendar), 1)},
        for(n <- 0..2, do: elem(week_span(y, w + n, calendar), 0))
      ),
      shape(
        "a recurrence by weeks",
        {:every, 3, [year: y, week: w], [week: 1]},
        for(n <- 0..2, do: week_span(y, w + n, calendar))
      )
    ]
  end

  defp week_shapes(_date, _calendar) do
    []
  end

  # A value of several members, each its own span, whose walk is not asked.
  defp shape(name, parts, spans) do
    %{shape: name, parts: parts, members: Enum.map(spans, &[&1]), walk: :unchecked}
  end

  # A value whose members are each one span, and whose walk yields them.
  defp each(name, parts, spans) do
    %{
      shape: name,
      parts: parts,
      members: Enum.map(spans, &[&1]),
      walk: {:ok, Enum.map(spans, &elem(&1, 0))}
    }
  end

  # A value of one span, and where each value its walk yields starts.
  defp whole(name, parts, span, starts) when is_list(starts) do
    %{shape: name, parts: parts, members: [[span]], walk: {:ok, starts}}
  end

  defp whole(name, parts, span, :unchecked) do
    %{shape: name, parts: parts, members: [[span]], walk: :unchecked}
  end

  defp hours(%Date{} = day) do
    hours_from(at(day))
  end

  defp year_span(y, calendar) do
    elem(expected({:year, y}, calendar), 0)
  end

  # The month so many months on, counted through the months each year has.
  defp months_on(y, m, 0, _calendar) do
    {y, m}
  end

  defp months_on(y, m, count, calendar) do
    if m < calendar.months_in_year(y) do
      months_on(y, m + 1, count - 1, calendar)
    else
      months_on(y + 1, 1, count - 1, calendar)
    end
  end

  defp counted_month_span(y, m, count, calendar) do
    {on_y, on_m} = months_on(y, m, count, calendar)
    month_span(on_y, on_m, calendar)
  end

  ## Selections

  @doc """
  A selection of each kind, each written five ways, with what it selects.

  They are a month, a month and a day, a day of the year, a day, a weekday
  and a position, and in a calendar of weeks a week, a week and a weekday,
  a year's weekdays and a week's besides. Each is written as a
  number, a count from the end, a range that reaches the end, the first
  and the last, and a value the period lacks.

  ### Arguments

  * `calendar` is a calendar module.

  ### Returns

  * A list of `%{scenario: name, datum: datum, selected: spans}`, where
    `datum` is a `t:Tempo.Matrix.Selections.datum/0`, built with
    `Tempo.Matrix.Selections.value/1`, and `spans` is a list with the spans
    of each occurrence, in the order of time, or `:no_such_value` for a
    selection of a value no period has, which is refused (decision 79). The
    list is empty for a calendar whose year starts within its months.

  """
  @spec selections(module()) :: [map()]
  def selections(calendar) do
    date = hd(anchors(calendar))

    if starts_within_its_months?(date.year, calendar) do
      []
    else
      month_selections(date, calendar) ++ week_selections(date, calendar)
    end
  end

  # One value, the last, from the second to the last, the first and the
  # last, and one no period has.
  defp ways(plain, absent) do
    [one: [plain], from_end: [-1], range_to_end: [{2, -1}], both_ends: [1, -1], absent: [absent]]
  end

  defp month_selections(%Date{year: y, month: m, day: d} = date, calendar) do
    year = [year: y]
    month = [year: y, month: m]

    for {way, x} <- ways(m, 40),
        {scenario, period, parts} <- [
          {"year: month", year, [month: x]},
          {"year: month, day", year, [month: [m], day: day(x, d)]},
          {"year: day of year", year, [day_of_year: day(x, Date.day_of_year(date))]},
          {"month: day", month, [day: day(x, d)]},
          {"month: weekday", month, [day_of_week: weekday(x)]},
          {"month: position", month, [day_of_week: [1], instance: weekday(x)]},
          {"day: hour", [year: y, month: m, day: d], [hour: hour(way)]}
        ] do
      datum = %{calendar: calendar, period: period, parts: parts}
      selected = Enum.map(Selections.extents(datum), & &1.spans)

      selection("#{scenario} #{way}", datum, selected)
    end
  end

  # A selection of a value no period has (a month, a day, a day of the
  # week or a week past every calendar's last, the hour 25) is refused by
  # name, as the value is (decision 79). A position or a day of the year
  # past the period's last selects nothing.
  @refused_when_absent [
    "year: month",
    "year: month, day",
    "month: day",
    "month: weekday",
    "day: hour",
    "year: week",
    "year: week, weekday",
    "year: weekday",
    "week: weekday"
  ]

  defp selection(scenario, datum, selected) do
    %{scenario: scenario, datum: datum, selected: refused_or(scenario, selected)}
  end

  defp refused_or(scenario, selected) do
    {kind, way} = String.split_at(scenario, -String.length(" absent"))

    if way == " absent" and kind in @refused_when_absent do
      :no_such_value
    else
      selected
    end
  end

  defp day([value], plain) when value > 0 and value < 40 and value != plain do
    [plain]
  end

  defp day(written, _plain) do
    written
  end

  defp weekday([value]) when value > 0 and value < 40 do
    [3]
  end

  defp weekday(written) do
    written
  end

  # The hours of a day, each of the five ways.
  defp hour(:one) do
    [10]
  end

  defp hour(:from_end) do
    [-1]
  end

  defp hour(:range_to_end) do
    [{22, -1}]
  end

  defp hour(:both_ends) do
    [0, -1]
  end

  defp hour(:absent) do
    [25]
  end

  # The selections of a calendar of weeks, whose answers are worked out from
  # the calendar's own weeks: the matrix's selections count a week as ISO
  # 8601 does.
  defp week_selections(%Date{} = date, calendar) when calendar in @of_weeks do
    {y, w, _day_of_week} = week_date(date, calendar)
    weeks = 1..weeks_in_year(y, calendar)//1

    for {way, x} <- ways(w, 60),
        {scenario, period, parts, selected} <- [
          {"year: week", [year: y], [week: x],
           for(week <- named(x, weeks), do: [week_span(y, week, calendar)])},
          {"year: week, weekday", [year: y], [week: [w], day_of_week: weekday(x)],
           days_of_weeks([w], weekday(x), y, calendar)},
          {"year: weekday", [year: y], [day_of_week: weekday(x)],
           days_of_weeks(weeks, weekday(x), y, calendar)},
          {"week: weekday", [year: y, week: w], [day_of_week: weekday(x)],
           days_of_weeks([w], weekday(x), y, calendar)}
        ] do
      selection(
        "#{scenario} #{way}",
        %{calendar: calendar, period: period, parts: parts},
        selected
      )
    end
  end

  defp week_selections(_date, _calendar) do
    []
  end

  defp days_of_weeks(weeks, written, y, calendar) do
    for week <- weeks, k <- named(written, 1..7//1) do
      [day_span(Enum.at(week_dates(y, week, calendar), k - 1))]
    end
  end

  # The values a part names among those its unit takes: a negative number is
  # counted back from the last, a range is every value from one of its ends
  # to the other, and a value the unit does not take is passed over.
  defp named(written, %Range{} = valid) do
    written
    |> Enum.flat_map(&each_named(&1, valid))
    |> Enum.filter(&(&1 in valid))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp each_named({first, last}, valid) do
    Enum.filter(valid, &(&1 >= counted(first, valid) and &1 <= counted(last, valid)))
  end

  defp each_named(value, valid) do
    [counted(value, valid)]
  end

  defp counted(value, %Range{last: last}) when value < 0 do
    last + 1 + value
  end

  defp counted(value, _valid) do
    value
  end
end
