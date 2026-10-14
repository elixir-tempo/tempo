defmodule Tempo.RRuleMeasure do
  @moduledoc false

  # The occurrences of an RRULE, worked out apart from the library.
  #
  # RFC 5545 section 3.3.10 says what a rule's parts do in two ways, by
  # whether each "expands" or "limits" the set at a frequency. For a rule of
  # days or coarser the two come to one test of each day: a day is an
  # occurrence when its period is a whole number of intervals from the
  # start's, and every part that names days admits it, the parts a rule
  # leaves to its start being taken from the start (the day of the month of
  # a monthly rule, the month and day of a yearly one, the weekday of a
  # weekly one). So every day from the start is tried, with every time of
  # day the rule names, and those that pass are the occurrences; `BYSETPOS`
  # then picks among those of each period, and `COUNT` and `UNTIL` end them.
  #
  # It takes a rule as the map `Tempo.RRule.from_rule/2` takes, or reads a
  # rule's text into one itself, with `String` and `Date`; it knows weeks
  # that begin on Monday and an `UNTIL` on the start's own clock.

  @weekdays %{"MO" => 1, "TU" => 2, "WE" => 3, "TH" => 4, "FR" => 5, "SA" => 6, "SU" => 7}
  # The days of the longest period a rule recurs by, a leap year.
  @longest_period 366

  @frequencies %{"YEARLY" => :year, "MONTHLY" => :month, "WEEKLY" => :week, "DAILY" => :day}

  @keys %{
    "FREQ" => :freq,
    "INTERVAL" => :interval,
    "COUNT" => :count,
    "UNTIL" => :until,
    "WKST" => :wkst,
    "BYMONTH" => :bymonth,
    "BYMONTHDAY" => :bymonthday,
    "BYYEARDAY" => :byyearday,
    "BYWEEKNO" => :byweekno,
    "BYDAY" => :byday,
    "BYHOUR" => :byhour,
    "BYMINUTE" => :byminute,
    "BYSECOND" => :bysecond,
    "BYSETPOS" => :bysetpos
  }

  @doc """
  The occurrences of a rule from a start, each a `NaiveDateTime`, that begin
  before a day: the first `COUNT` of them, or those to `UNTIL`. The start is
  a reading of the clock of the zone given as `:zone`, where an `UNTIL` at
  UTC (`19971224T000000Z`) is read.
  """
  @spec occurrences(String.t() | map(), NaiveDateTime.t(), Date.t(), keyword()) ::
          [NaiveDateTime.t()]
  def occurrences(rule, start, before, options \\ [])

  def occurrences(text, start, before, options) when is_binary(text),
    do: occurrences(read(text, Keyword.get(options, :zone)), start, before, options)

  def occurrences(%{freq: _} = rule, %NaiveDateTime{} = start, %Date{} = before, _options) do
    first = NaiveDateTime.to_date(start)

    # A period's days are all of them, those before the start among them:
    # a position counts among the whole period's, and the start's own period
    # is the first that counts.
    first
    |> Date.add(-@longest_period)
    |> Date.range(Date.add(before, -1))
    |> Enum.filter(&(in_step?(&1, first, rule) and admitted?(&1, first, rule)))
    |> Enum.flat_map(&times(&1, start, rule))
    |> positioned(first, rule)
    |> Enum.filter(&(NaiveDateTime.compare(&1, start) != :lt))
    |> bounded(rule)
  end

  ## The rule, read

  # A rule's text as the map `Tempo.RRule.from_rule/2` takes: RFC 5545's
  # keys, lower-cased, a weekday as `{ordinal, day}`.
  defp read(text, zone) do
    for part <- String.split(text, ";", trim: true), into: %{} do
      [key, value] = String.split(part, "=", parts: 2)
      {Map.fetch!(@keys, key), value(key, value, zone)}
    end
  end

  defp value("UNTIL", value, zone), do: until(value, zone)
  defp value(key, value, _zone), do: value(key, value)

  defp value("FREQ", value), do: Map.fetch!(@frequencies, value)
  defp value("BYDAY", value), do: value |> String.split(",") |> Enum.map(&weekday/1)
  # Weeks begin on Monday, and a rule may say so.
  defp value("WKST", "MO"), do: 1

  defp value(key, value) when key in ["INTERVAL", "COUNT"], do: String.to_integer(value)

  defp value(_by_part, value), do: value |> String.split(",") |> Enum.map(&String.to_integer/1)

  defp weekday(text) do
    {ordinal, code} = String.split_at(text, -2)
    {if(ordinal == "", do: nil, else: String.to_integer(ordinal)), Map.fetch!(@weekdays, code)}
  end

  defp until(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>>, _zone),
    do: NaiveDateTime.new!(Date.new!(int(y), int(m), int(d)), ~T[23:59:59])

  # A time at UTC is the reading the start's clock shows then.
  defp until(<<local::binary-size(15), "Z">>, zone) when is_binary(zone) do
    local
    |> until(nil)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(zone)
    |> DateTime.to_naive()
  end

  defp until(
         <<date::binary-size(8), "T", h::binary-size(2), mi::binary-size(2), s::binary-size(2)>>,
         _zone
       ) do
    %NaiveDateTime{} = day = until(date, nil)
    NaiveDateTime.new!(NaiveDateTime.to_date(day), Time.new!(int(h), int(mi), int(s)))
  end

  defp int(text), do: String.to_integer(text)

  ## A day's period, and whether it is a whole number of intervals on

  defp in_step?(day, first, rule) do
    periods = periods_between(first, day, rule[:freq])
    periods >= 0 and rem(periods, Map.get(rule, :interval, 1)) == 0
  end

  defp periods_between(first, day, :year), do: day.year - first.year

  defp periods_between(first, day, :month),
    do: (day.year - first.year) * 12 + day.month - first.month

  defp periods_between(first, day, :day), do: Date.diff(day, first)

  defp periods_between(first, day, :week),
    do: div(Date.diff(Date.beginning_of_week(day), Date.beginning_of_week(first)), 7)

  defp period(day, :year), do: day.year
  defp period(day, :month), do: {day.year, day.month}
  defp period(day, :week), do: Date.beginning_of_week(day)
  defp period(day, :day), do: day

  ## Whether the rule's parts admit a day

  defp admitted?(day, first, rule) do
    rule = with_start(rule, first)

    month?(day, rule[:bymonth]) and month_day?(day, rule[:bymonthday]) and
      year_day?(day, rule[:byyearday]) and week?(day, rule[:byweekno]) and
      weekday?(day, rule[:byday], rule)
  end

  # What a rule leaves to its start.
  defp with_start(%{freq: :week} = rule, first),
    do: Map.put_new(rule, :byday, [{nil, Date.day_of_week(first)}])

  defp with_start(%{freq: :month} = rule, first) do
    if names_a_day?(rule), do: rule, else: Map.put(rule, :bymonthday, [first.day])
  end

  defp with_start(%{freq: :year} = rule, first) do
    cond do
      Map.has_key?(rule, :byweekno) ->
        Map.put_new(rule, :byday, [{nil, Date.day_of_week(first)}])

      names_a_day?(rule) ->
        rule

      true ->
        rule |> Map.put_new(:bymonth, [first.month]) |> Map.put(:bymonthday, [first.day])
    end
  end

  defp with_start(rule, _first), do: rule

  defp names_a_day?(rule),
    do: Enum.any?([:bymonthday, :byday, :byyearday], &Map.has_key?(rule, &1))

  defp month?(_day, nil), do: true
  defp month?(day, months), do: day.month in months

  defp month_day?(_day, nil), do: true

  defp month_day?(day, days),
    do: day.day in days or (day.day - Date.days_in_month(day) - 1) in days

  defp year_day?(_day, nil), do: true

  defp year_day?(day, days) do
    of_year = Date.day_of_year(day)
    in_year = if Date.leap_year?(day), do: 366, else: 365
    of_year in days or (of_year - in_year - 1) in days
  end

  defp week?(_day, nil), do: true

  defp week?(day, weeks) do
    {week_year, week} = :calendar.iso_week_number(Date.to_erl(day))
    week_year == day.year and week in weeks
  end

  defp weekday?(_day, nil, _rule), do: true

  defp weekday?(day, weekdays, rule) do
    Enum.any?(weekdays, fn
      {nil, weekday} -> Date.day_of_week(day) == weekday
      {nth, weekday} -> Date.day_of_week(day) == weekday and nth?(day, nth, counted_in(rule))
    end)
  end

  # A numbered weekday is the nth of its month, or of its year in a yearly
  # rule that names no month.
  defp counted_in(%{freq: :year} = rule),
    do: if(Map.has_key?(rule, :bymonth), do: :month, else: :year)

  defp counted_in(_rule), do: :month

  defp nth?(day, nth, :month) when nth > 0, do: div(day.day - 1, 7) + 1 == nth

  defp nth?(day, nth, :month),
    do: div(Date.days_in_month(day) - day.day, 7) + 1 == -nth

  defp nth?(day, nth, :year) when nth > 0, do: div(Date.day_of_year(day) - 1, 7) + 1 == nth

  defp nth?(day, nth, :year) do
    in_year = if Date.leap_year?(day), do: 366, else: 365
    div(in_year - Date.day_of_year(day), 7) + 1 == -nth
  end

  ## The times of day on a day

  defp times(day, start, rule) do
    for hour <- Map.get(rule, :byhour, [start.hour]),
        minute <- Map.get(rule, :byminute, [start.minute]),
        second <- Map.get(rule, :bysecond, [start.second]),
        do: NaiveDateTime.new!(day, Time.new!(hour, minute, second))
  end

  ## Positions among a period's occurrences, and the end

  defp positioned(occurrences, _first, %{bysetpos: positions, freq: frequency}) do
    occurrences
    |> Enum.sort(NaiveDateTime)
    |> Enum.chunk_by(&period(NaiveDateTime.to_date(&1), frequency))
    |> Enum.flat_map(fn of_period ->
      positions
      |> Enum.map(&Enum.at(of_period, if(&1 > 0, do: &1 - 1, else: &1)))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort(NaiveDateTime)
    end)
  end

  defp positioned(occurrences, _first, _rule), do: Enum.sort(occurrences, NaiveDateTime)

  defp bounded(occurrences, %{count: count}), do: Enum.take(occurrences, count)

  defp bounded(occurrences, %{until: until}),
    do: Enum.take_while(occurrences, &(NaiveDateTime.compare(&1, until) != :gt))

  defp bounded(occurrences, _rule), do: occurrences
end
