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

  The astronomical calendars are not here: a cell of them takes seconds to
  minutes. Nor is a selection in a year that starts within its months,
  which is not built.

  """

  alias Tempo.Matrix.Selections

  @anchors [~D[2026-06-15], ~D[2024-02-29], ~D[2025-08-01]]

  @second 1_000_000
  @day 86_400 * @second

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

  @doc """
  The calendars of the census.

  ### Returns

  * A list of calendar modules.

  """
  @spec calendars() :: [module()]
  def calendars, do: @calendars

  @doc """
  A value in each full form, on each of the census's dates.

  ### Arguments

  * `calendar` is a calendar module.

  ### Returns

  * A list of `%{form: name, text: text, expect: what}`, where `what` is
    given to `expected/2`.

  """
  @spec forms(module()) :: [%{form: String.t(), text: String.t(), expect: tuple()}]
  def forms(calendar) do
    for date <- anchors(calendar), {form, text, expect} <- forms_on(date, week?(calendar)) do
      %{form: form, text: text, expect: expect}
    end
  end

  # The census's dates in the calendar, and for a reform calendar a date in
  # the month the reform cut short.
  defp anchors(Calendrical.Reform.England = calendar),
    do: Enum.map(@anchors ++ [~D[1752-09-20]], &Date.convert!(&1, calendar))

  defp anchors(calendar), do: Enum.map(@anchors, &Date.convert!(&1, calendar))

  defp week?(calendar), do: calendar.calendar_base() == :week

  # In a calendar of weeks a date's month is its week and its day the day of
  # that week.
  defp forms_on(%Date{year: y, month: w, day: k}, true) do
    [
      {"Y", "#{y}Y", {:week_year, y}},
      {"Y-W", "#{y}Y#{w}W", {:week, y, w}},
      {"Y-W-K", "#{y}Y#{w}W#{k}K", {:week_day, y, w, k, []}},
      {"Y-W-K T H", "#{y}Y#{w}W#{k}KT10H", {:week_day, y, w, k, [hour: 10]}},
      {"Y-W T H", "#{y}Y#{w}WT17H", {:week_day, y, w, 1, [hour: 17]}}
    ]
  end

  defp forms_on(%Date{year: y, month: m, day: d} = date, false) do
    [
      {"Y", "#{y}Y", {:year, y}},
      {"Y-M", "#{y}Y#{m}M", {:month, y, m}},
      {"Y-M-D", "#{y}Y#{m}M#{d}D", {:day, y, m, d, []}},
      {"Y-M-D T H", "#{y}Y#{m}M#{d}DT10H", {:day, y, m, d, [hour: 10]}},
      {"Y-M-D T H:M", "#{y}Y#{m}M#{d}DT10H30M", {:day, y, m, d, [hour: 10, minute: 30]}},
      {"Y-M-D T H:M:S", "#{y}Y#{m}M#{d}DT10H30M45S",
       {:day, y, m, d, [hour: 10, minute: 30, second: 45]}},
      {"Y-O", "#{y}Y#{Date.day_of_year(date)}O", {:day, y, m, d, []}},
      {"Y T H", "#{y}YT17H", {:first_day, y, nil, [hour: 17]}},
      {"Y-M T H", "#{y}Y#{m}MT17H", {:first_day, y, m, [hour: 17]}}
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

  def expected({:month, y, m}, calendar),
    do: {month_span(y, m, calendar), Enum.map(month_dates(y, m, calendar), &day_span/1)}

  def expected({:day, y, m, d, time}, calendar), do: clock(iso(y, m, d, calendar), time)

  def expected({:first_day, y, m, time}, calendar),
    do: clock(hd(month_dates(y, m || 1, calendar)), time)

  def expected({:week_year, y}, calendar) do
    weeks = for w <- 1..weeks_in_year(y, calendar), do: week_span(y, w, calendar)
    {{elem(hd(weeks), 0), elem(List.last(weeks), 1)}, weeks}
  end

  def expected({:week, y, w}, calendar),
    do: {week_span(y, w, calendar), Enum.map(week_dates(y, w, calendar), &day_span/1)}

  def expected({:week_day, y, w, k, time}, calendar),
    do: clock(Enum.at(week_dates(y, w, calendar), k - 1), time)

  # The dates of a month, as `Calendar.ISO` dates: those the calendar says
  # are dates of it, or, in a year that starts within its months, the dates
  # of the nth month the calendar counts.
  defp month_dates(y, m, calendar) do
    if starts_within_its_months?(y, calendar),
      do: Enum.map(calendar.month(y, m), &Date.convert!(&1, Calendar.ISO)),
      else: for(d <- 1..40, calendar.valid_date?(y, m, d), do: iso(y, m, d, calendar))
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

  defp week_dates(y, w, calendar),
    do: Enum.map(calendar.week(y, w), &Date.convert!(&1, Calendar.ISO))

  defp week_span(y, w, calendar) do
    dates = week_dates(y, w, calendar)
    {at(hd(dates)), at(List.last(dates)) + @day}
  end

  defp weeks_in_year(y, calendar) do
    {weeks, _days} = calendar.weeks_in_year(y)
    weeks
  end

  defp iso(y, m, d, calendar), do: y |> Date.new!(m, d, calendar) |> Date.convert!(Calendar.ISO)

  defp day_span(%Date{} = day), do: {at(day), at(day) + @day}

  defp clock(day, []), do: {day_span(day), for(h <- 0..23, do: unit_span(day, h * 3600, 3600))}

  defp clock(day, hour: h) do
    {unit_span(day, h * 3600, 3600), for(mi <- 0..59, do: unit_span(day, h * 3600 + mi * 60, 60))}
  end

  defp clock(day, hour: h, minute: mi) do
    from = h * 3600 + mi * 60
    {unit_span(day, from, 60), for(s <- 0..59, do: unit_span(day, from + s, 1))}
  end

  defp clock(day, hour: h, minute: mi, second: s),
    do: {unit_span(day, h * 3600 + mi * 60 + s, 1), :unchecked}

  defp unit_span(day, seconds, length),
    do: {at(day) + seconds * @second, at(day) + (seconds + length) * @second}

  defp at(%Date{} = date), do: Date.to_gregorian_days(date) * @day

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
  and days of it needs a year. A calendar of weeks has no month, and a year
  that starts within its months is left out: with no year a month there is
  the one a date names, and with a year the nth the calendar counts.

  ### Arguments

  * `calendar` is a calendar module.

  ### Returns

  * A list of `%{text: text, covers: covers, walk: walk}`.

  """
  @spec no_year(module()) :: [%{text: String.t(), covers: covers(), walk: walk()}]
  def no_year(calendar) do
    cond do
      week?(calendar) -> weekdays_no_year()
      starts_within_its_months?(hd(anchors(calendar)).year, calendar) -> []
      true -> months_no_year(calendar, calendar.months_in_year()) ++ weekdays_no_year()
    end
  end

  defp weekdays_no_year do
    days =
      for k <- 1..7 do
        from = (k - 1) * @day
        %{text: "#{k}K", covers: {:ok, {from, from + @day}}, walk: {:ok, hours_from(from)}}
      end

    days ++ [%{text: "8K", covers: :no_such_value, walk: :unchecked}]
  end

  defp hours_from(from), do: for(h <- 0..23, do: from + h * 3600 * @second)

  # A calendar that counts nothing with no year: its years are not alike
  # enough to say.
  defp months_no_year(_calendar, {:error, _undefined}) do
    for m <- [1, 6, 12],
        cell <- [%{text: "#{m}M", walk: :needs_a_year}, %{text: "#{m}M15D", walk: {:count, 24}}] do
      Map.put(cell, :covers, :needs_a_year)
    end
  end

  defp months_no_year(calendar, months) do
    {least, most} = fewest_and_most(months)
    counts = %{least_months: least, most_months: most, calendar: calendar}

    Enum.flat_map(1..most, &month_no_year(&1, counts)) ++
      [%{text: "#{most + 1}M", covers: :no_such_value, walk: :unchecked}]
  end

  defp month_no_year(m, %{calendar: calendar} = counts) do
    {fewest, most} = fewest_and_most(calendar.days_in_month(m))
    from = days_before(m, calendar) * @day
    followed? = followed_in_every_year?(m, counts)

    month = %{
      text: "#{m}M",
      covers: if(followed?, do: {:ok, {from, from + most * @day}}, else: :needs_a_year),
      walk:
        if(fewest == most,
          do: {:ok, for(d <- 1..most, do: from + (d - 1) * @day)},
          else: :needs_a_year
        )
    }

    days =
      for d <- 1..(most + 1) do
        day_from = from + (d - 1) * @day

        %{
          text: "#{m}M#{d}D",
          covers: day_covers(d, {fewest, most}, followed?, day_from),
          walk: if(d in [1, fewest, most], do: {:ok, hours_from(day_from)}, else: :unchecked)
        }
      end

    [month | days]
  end

  # A day below the last every year has is followed by the next. The last
  # day the longest month has is followed by the first of the next month,
  # where that is the same month in every year. Between the two, and where
  # the month after depends on the year, the day's span needs a year.
  defp day_covers(d, {_fewest, most}, _followed?, _from) when d > most, do: :no_such_value

  defp day_covers(d, {fewest, _most}, _followed?, from) when d < fewest,
    do: {:ok, {from, from + @day}}

  defp day_covers(most, {_fewest, most}, true, from), do: {:ok, {from, from + @day}}
  defp day_covers(_d, _days, _followed?, _from), do: :needs_a_year

  # A month every year has is followed by the next, and the last month of
  # the year that has the most by the first of the next year. A month
  # between the two is followed by one or the other by the year.
  defp followed_in_every_year?(m, %{least_months: least, most_months: most}),
    do: m < least or m == most

  defp days_before(m, calendar) do
    Enum.sum(
      for earlier <- 1..(m - 1)//1, do: elem(fewest_and_most(calendar.days_in_month(earlier)), 1)
    )
  end

  defp fewest_and_most(count) when is_integer(count), do: {count, count}

  defp fewest_and_most({:ambiguous, %Range{first: first, last: last}}),
    do: {min(first, last), max(first, last)}

  ## Shapes, intervals and recurrences

  @doc """
  A value in each shape, an interval and a recurrence, on the census's
  first date: a set, a range, a count from the end, a mask and an
  unspecified unit; an interval of days and one of months or weeks; a
  recurrence that steps by days, by months or weeks, and by years.

  ### Arguments

  * `calendar` is a calendar module.

  ### Returns

  * A list of `%{shape: name, text: text, members: spans, walk: walk}`,
    where `spans` is a list with the spans of each member the value
    converts to, and `walk` is `{:ok, starts}`, where each value the walk
    yields starts, or `:unchecked`. It is empty for a calendar whose year
    starts within its months.

  """
  @spec shapes(module()) :: [map()]
  def shapes(calendar) do
    date = hd(anchors(calendar))

    cond do
      week?(calendar) -> week_shapes(date, calendar)
      starts_within_its_months?(date.year, calendar) -> []
      true -> month_shapes(date, calendar)
    end
  end

  defp month_shapes(%Date{} = date, calendar),
    do:
      shaped_months(date, calendar) ++
        spanned_months(date, calendar) ++ repeated_months(date, calendar)

  # A set, a range, a count from the end, a mask and an unspecified unit.
  defp shaped_months(%Date{year: y, month: m}, calendar) do
    months = calendar.months_in_year(y)
    dates = month_dates(y, m, calendar)
    last_month = month_dates(y, months, calendar)
    month = month_span(y, m, calendar)

    [
      shape("a set of months", "#{y}Y{1,3}M", [
        month_span(y, 1, calendar),
        month_span(y, 3, calendar)
      ]),
      shape(
        "a range of days",
        "#{y}Y#{m}M{1..3}D",
        dates |> Enum.take(3) |> Enum.map(&day_span/1)
      ),
      shape("a set of days", "#{y}Y#{m}M{1,3}D", [
        day_span(hd(dates)),
        day_span(Enum.at(dates, 2))
      ]),
      whole(
        "the last month",
        "#{y}Y-1M",
        month_span(y, months, calendar),
        Enum.map(last_month, &at/1)
      ),
      whole(
        "the last day of a month",
        "#{y}Y#{m}M-1D",
        day_span(List.last(dates)),
        hours(List.last(dates))
      ),
      whole(
        "the last day of the last month",
        "#{y}Y-1M-1D",
        day_span(List.last(last_month)),
        :unchecked
      ),
      whole("a masked day", "#{y}Y#{m}MXXD", month, Enum.map(dates, &at/1)),
      whole("an unspecified day", "#{y}Y#{m}MX*D", month, Enum.map(dates, &at/1)),
      whole(
        "an unspecified month",
        "#{y}YX*M",
        year_span(y, calendar),
        month_starts(y, 1, months, calendar)
      )
    ]
  end

  # An interval of days that runs into the next month, and one of months.
  defp spanned_months(%Date{year: y, month: m, day: d}, calendar) do
    day = iso(y, m, d, calendar)
    later = Date.convert!(Date.add(day, 40), calendar)
    {after_y, after_m} = months_on(y, m, 2, calendar)
    from = elem(month_span(y, m, calendar), 0)

    [
      whole(
        "an interval of days",
        "#{y}Y#{m}M#{d}D/#{later.year}Y#{later.month}M#{later.day}D",
        {at(day), at(day) + 40 * @day},
        Enum.map(0..39, &(at(day) + &1 * @day))
      ),
      whole(
        "an interval of months",
        "#{y}Y#{m}M/#{after_y}Y#{after_m}M",
        {from, elem(month_span(after_y, after_m, calendar), 0)},
        month_starts(y, m, 2, calendar)
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
        "R4/#{y}Y#{m}M#{d}D/P10D",
        Enum.map(0..3, &{day + 10 * &1 * @day, day + 10 * (&1 + 1) * @day})
      ),
      shape(
        "a recurrence by months",
        "R4/#{y}Y#{m}M/P1M",
        Enum.map(0..3, &counted_month_span(y, m, &1, calendar))
      ),
      shape("a recurrence by years", "R3/#{y}Y/P1Y", Enum.map(0..2, &year_span(y + &1, calendar)))
    ]
  end

  # Where each of so many months starts, from a month on.
  defp month_starts(y, m, count, calendar),
    do: Enum.map(0..(count - 1), &elem(counted_month_span(y, m, &1, calendar), 0))

  defp week_shapes(%Date{year: y, month: w}, calendar) do
    weeks = weeks_in_year(y, calendar)
    dates = week_dates(y, w, calendar)
    week = week_span(y, w, calendar)

    [
      shape("a set of weeks", "#{y}Y{1,3}W", for(n <- [1, 3], do: week_span(y, n, calendar))),
      whole(
        "the last week",
        "#{y}Y-1W",
        week_span(y, weeks, calendar),
        Enum.map(week_dates(y, weeks, calendar), &at/1)
      ),
      shape(
        "a range of days",
        "#{y}Y#{w}W{1..3}K",
        dates |> Enum.take(3) |> Enum.map(&day_span/1)
      ),
      whole(
        "the last day of a week",
        "#{y}Y#{w}W-1K",
        day_span(List.last(dates)),
        hours(List.last(dates))
      ),
      whole(
        "an interval of weeks",
        "#{y}Y#{w}W/#{y}Y#{w + 2}W",
        {elem(week, 0), elem(week_span(y, w + 2, calendar), 0)},
        for(n <- 0..1, do: elem(week_span(y, w + n, calendar), 0))
      ),
      shape(
        "a recurrence by weeks",
        "R3/#{y}Y#{w}W/P1W",
        for(n <- 0..2, do: week_span(y, w + n, calendar))
      ),
      shape(
        "a recurrence by years",
        "R3/#{y}Y/P1Y",
        for(n <- 0..2, do: elem(expected({:week_year, y + n}, calendar), 0))
      )
    ]
  end

  # A value of several members, each its own span, whose walk is not asked.
  defp shape(name, text, spans),
    do: %{shape: name, text: text, members: Enum.map(spans, &[&1]), walk: :unchecked}

  # A value of one span, and where each value its walk yields starts.
  defp whole(name, text, span, starts) when is_list(starts),
    do: %{shape: name, text: text, members: [[span]], walk: {:ok, starts}}

  defp whole(name, text, span, :unchecked),
    do: %{shape: name, text: text, members: [[span]], walk: :unchecked}

  defp hours(%Date{} = day), do: hours_from(at(day))

  defp year_span(y, calendar), do: elem(expected({:year, y}, calendar), 0)

  # The month so many months on, counted through the months each year has.
  defp months_on(y, m, 0, _calendar), do: {y, m}

  defp months_on(y, m, count, calendar) do
    if m < calendar.months_in_year(y),
      do: months_on(y, m + 1, count - 1, calendar),
      else: months_on(y + 1, 1, count - 1, calendar)
  end

  defp counted_month_span(y, m, count, calendar) do
    {on_y, on_m} = months_on(y, m, count, calendar)
    month_span(on_y, on_m, calendar)
  end

  ## Selections

  @doc """
  A selection of each kind, each written five ways, with what it selects.

  In a calendar of months they are a month, a month and a day, a day of the
  year, a day, a weekday and a position; in a calendar of weeks a week, a
  week and a weekday, a year's weekdays and a week's. Each is written as a
  number, a count from the end, a range that reaches the end, the first
  and the last, and a value the period lacks.

  ### Arguments

  * `calendar` is a calendar module.

  ### Returns

  * A list of `%{scenario: name, text: text, selected: spans, rule: rule,
    select: select}`, where `spans` is a list with the spans of each
    occurrence, in the order of time. `rule` is `{text, window}`, the same
    parts as the rule of a recurrence of the period and the period as its
    window, and `select` is `{base, selector}`, the period and the parts as
    `Tempo.select/2` takes them, or `nil` for a position, which is a
    selection's alone. The list is empty for a calendar whose year starts
    within its months.

  """
  @spec selections(module()) :: [map()]
  def selections(calendar) do
    date = hd(anchors(calendar))

    cond do
      week?(calendar) -> week_selections(date, calendar)
      starts_within_its_months?(date.year, calendar) -> []
      true -> month_selections(date, calendar)
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
          {"month: position", month, [day_of_week: [1], instance: weekday(x)]}
        ] do
      datum = %{calendar: calendar, period: period, parts: parts}
      selected = Enum.map(Selections.extents(datum), & &1.spans)

      selection("#{scenario} #{way}", datum, selected)
    end
  end

  defp selection(scenario, %{period: period, parts: parts} = datum, selected) do
    window = Selections.period_text(period)
    written = Selections.parts_text(parts)

    %{
      scenario: scenario,
      text: Selections.text(datum),
      selected: selected,
      rule: {"R/#{window}/#{cadence(period)}/FL#{written}N", window},
      select: if(Keyword.has_key?(parts, :instance), do: nil, else: {window, written})
    }
  end

  # A recurrence of a period steps by the period's own length.
  defp cadence(period) do
    case List.last(period) do
      {:year, _year} -> "P1Y"
      {:month, _month} -> "P1M"
      {:week, _week} -> "P1W"
    end
  end

  defp day([value], plain) when value > 0 and value < 40 and value != plain, do: [plain]
  defp day(written, _plain), do: written

  defp weekday([value]) when value > 0 and value < 40, do: [3]
  defp weekday(written), do: written

  # The selections of a calendar of weeks, whose answers are worked out from
  # the calendar's own weeks: the matrix's selections count a week as ISO
  # 8601 does.
  defp week_selections(%Date{year: y, month: w}, calendar) do
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

  defp each_named({first, last}, valid),
    do: Enum.filter(valid, &(&1 >= counted(first, valid) and &1 <= counted(last, valid)))

  defp each_named(value, valid), do: [counted(value, valid)]

  defp counted(value, %Range{last: last}) when value < 0, do: last + 1 + value
  defp counted(value, _valid), do: value
end
