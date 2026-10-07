defmodule Tempo.BesideAGap do
  @moduledoc false

  # Values beside a reading their zone's clock skips, each given to the
  # operations that make values, and every value those give held to being
  # one the reader takes.
  #
  # A value written on a reading the clock skips the whole of is refused
  # when it is read: the hour a spring-forward skips, a minute inside it, a
  # day a zone leaves out. So an operation that gives one gives a value that
  # cannot be written and read again, and that is the property held here.
  # It asks nothing of what the right answer is, which the worked examples
  # of `Tempo.BesideAGapTest` hold against Elixir's own `DateTime`. It asks
  # that no answer, of any operation, is a value no one could have written.
  #
  # Each cell, a value and an operation, runs in a task of its own, so an
  # operation that raises is that task's exit and a finding, and nothing is
  # rescued.

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  # The gaps, and the values written beside each. The values are of every
  # shape a gap is met in: the day and the month that hold it, the hours on
  # each side of it, a set, a range and unspecified digits that name the
  # skipped reading among others, a week date and a day of the year.
  @beside [
    # New York, 10 March 2024: 02:00 to 03:00.
    {"America/New_York",
     ~w(2024-03-10 2024-03-09 2024-03 2024-03-10T01 2024-03-10T03 2024-03-10T01:30
        2024-03-09T02 2024-03-09T02:30 2024-03-11T02:30 2024-03-10T01:59:59
        2024-03-10T{01,02,03} 2024-03-10T{01..03} 2024-03-10T0X 2024-03-10TXX
        2024-03-{09,10}T02 2024-03-XXT02)},
    # Paris, 29 March 2026: 02:00 to 03:00.
    {"Europe/Paris", ~w(2026-03-29 2026-03-29T01 2026-03-28T02:30 2026-03-29T{01,02,03})},
    # Lord Howe Island, 4 October 2026: 02:00 to 02:30, half of an hour.
    {"Australia/Lord_Howe",
     ~w(2026-10-04 2026-10-04T01 2026-10-04T02 2026-10-04T02:30 2026-10-03T02:15
        2026-10-04T{01,02,03})},
    # Cairo, 28 April 2023: midnight to 01:00, the first hour of a day.
    {"Africa/Cairo", ~w(2023-04-28 2023-04-27 2023-04-27T23 2023-04 2023-04-{27,28})},
    # Samoa had no 30 December 2011.
    {"Pacific/Apia",
     ~w(2011-12-29 2011-12-31 2011-12 2011 2011-12-29T10 2011-12-{29,30} 2011-12-{29..31}
        2011-12-3X 2011-12-XX 2011-{11,12}-30 2011-W52 2011-363)}
  ]

  @doc """
  The texts of the values beside a gap, each with its zone.
  """
  @spec texts() :: [String.t()]
  def texts do
    for {zone, values} <- @beside, value <- values, do: value <> "[" <> zone <> "]"
  end

  @doc """
  The values beside a gap written in another calendar, each as
  `{text, twin, calendar}`: the Gregorian text, the text of the same day and
  time in the other calendar, and that calendar's name.

  A zone's clock is the same clock whichever calendar a date is written in,
  so an operation gives a value and its twin the same moments. A Buddhist
  year is the Gregorian one 543 on with the same months and days, so every
  value but a week date and a day of the year has a Buddhist twin. A date,
  and a date with a time of day, has a Hebrew one, whose month and day are
  others, and one in the calendar of ISO 8601's weeks, where it is a day of
  a week.
  """
  @spec twins() :: [{String.t(), String.t(), String.t()}]
  def twins do
    for {zone, values} <- @beside,
        value <- values,
        {calendar, twin} <- twins_of(value),
        do: {zoned(value, zone), zoned(twin, zone) <> "[u-ca=" <> calendar <> "]", calendar}
  end

  defp zoned(value, zone), do: value <> "[" <> zone <> "]"

  defp twins_of(value), do: buddhist_twin(value) ++ hebrew_twin(value) ++ week_twin(value)

  @buddhist_years_on 543

  defp buddhist_twin(<<year::binary-size(4), rest::binary>> = value) do
    if value =~ ~r/^\d{4}(-W|-\d{3}$)/,
      do: [],
      else: [
        {"buddhist", Integer.to_string(String.to_integer(year) + @buddhist_years_on) <> rest}
      ]
  end

  defp hebrew_twin(value) do
    case Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})(T[\d:]+)?$/, value) do
      [_all, year, month, day | time] ->
        {:ok, date} = Date.new(integer(year), integer(month), integer(day))
        {:ok, hebrew} = Date.convert(date, Calendrical.Hebrew)

        [{"hebrew", "#{hebrew.year}-#{two(hebrew.month)}-#{two(hebrew.day)}#{time}"}]

      nil ->
        []
    end
  end

  # The day of the week of ISO 8601 that a date is, as Erlang gives it.
  defp week_twin(value) do
    case Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})(T[\d:]+)?$/, value) do
      [_all, year, month, day | time] ->
        date = {integer(year), integer(month), integer(day)}
        {week_year, week} = :calendar.iso_week_number(date)

        [{"iso-week", "#{week_year}-W#{two(week)}-#{:calendar.day_of_the_week(date)}#{time}"}]

      nil ->
        []
    end
  end

  defp integer(digits), do: String.to_integer(digits)
  defp two(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  # The operations that give a Hebrew date or a day of a week what they give
  # its Gregorian twin: every one that does not count in months or years, or
  # pick a day by its number in a month, which are other months and other
  # numbers there, or none.
  defp of_any_calendar?(name),
    do: not (name =~ ~r/year|month|30D|29D\/31D|P1M|BYMONTHDAY/)

  # What a calendar of weeks is not yet given, each an open item of
  # `TODO.md` that is nothing of the zone's: a workday counted from a date
  # and time is refused there, and a time of day selected from the last day
  # of a week is nothing, which each day beside a change of the clock here
  # is, clocks being changed on a Sunday.
  defp built_for_weeks?(name), do: not (name =~ ~r/workday|^select T/)

  @doc """
  The operations each value is given to, by name.
  """
  @spec operations() :: [{String.t(), (Tempo.t() -> term())}]
  def operations, do: conversions() ++ steps() ++ selections() ++ spans() ++ sets() ++ walks()

  defp conversions do
    [
      {"to_interval", &Tempo.to_interval/1},
      {"to_interval_set", &Tempo.to_interval_set/1},
      {"extend", &Tempo.extend/1},
      {"extend_resolution :day", &Tempo.extend_resolution(&1, :day)},
      {"extend_resolution :hour", &Tempo.extend_resolution(&1, :hour)},
      {"extend_resolution :minute", &Tempo.extend_resolution(&1, :minute)},
      {"at_resolution :day", &Tempo.at_resolution(&1, :day)},
      {"at_resolution :hour", &Tempo.at_resolution(&1, :hour)},
      {"at_resolution :minute", &Tempo.at_resolution(&1, :minute)},
      {"round :day", &Tempo.round(&1, :day)},
      {"round :hour", &Tempo.round(&1, :hour)},
      {"trunc :month", &Tempo.trunc(&1, :month)},
      {"trunc :day", &Tempo.trunc(&1, :day)},
      {"trunc :hour", &Tempo.trunc(&1, :hour)},
      {"split", &split/1},
      {"shift_zone London", &Tempo.shift_zone(&1, "Europe/London")},
      {"shift_zone Apia", &Tempo.shift_zone(&1, "Pacific/Apia")},
      {"in_zone", &placed/1}
    ]
  end

  defp steps do
    [
      {"shift year: 1", &Tempo.shift(&1, year: 1)},
      {"shift month: 1", &Tempo.shift(&1, month: 1)},
      {"shift month: -1", &Tempo.shift(&1, month: -1)},
      {"shift week: 1", &Tempo.shift(&1, week: 1)},
      {"shift day: 1", &Tempo.shift(&1, day: 1)},
      {"shift day: 2", &Tempo.shift(&1, day: 2)},
      {"shift day: -1", &Tempo.shift(&1, day: -1)},
      {"shift hour: 1", &Tempo.shift(&1, hour: 1)},
      {"shift hour: 25", &Tempo.shift(&1, hour: 25)},
      {"shift hour: -1", &Tempo.shift(&1, hour: -1)},
      {"shift minute: 30", &Tempo.shift(&1, minute: 30)},
      {"shift minute: -30", &Tempo.shift(&1, minute: -30)},
      {"shift second: 1", &Tempo.shift(&1, second: 1)},
      {"shift minute: 30 skipping", &skipping(&1, [minute: 30], hour: 1)},
      {"shift hour: 1 skipping", &skipping(&1, [hour: 1], hour: 1)},
      {"shift day: 1 skipping", &skipping(&1, [day: 1], day: 1)},
      {"add_workdays 1", &Tempo.add_workdays(&1, 1, :US)},
      {"add_workdays -1", &Tempo.add_workdays(&1, -1, :US)},
      {"next_workday", &Tempo.next_workday(&1, :US)},
      {"previous_workday", &Tempo.previous_workday(&1, :US)},
      {"nearest_workday", &Tempo.nearest_workday(&1, :US)}
    ]
  end

  defp selections do
    [
      {"select T00", &Tempo.select(&1, Tempo.from_iso8601!("T00"))},
      {"select T02", &Tempo.select(&1, Tempo.from_iso8601!("T02"))},
      {"select T02:30", &Tempo.select(&1, Tempo.from_iso8601!("T02:30"))},
      {"select T{01,02,03}", &Tempo.select(&1, Tempo.from_iso8601!("T{01,02,03}"))},
      {"select T02/T04", &Tempo.select(&1, Tempo.from_iso8601!("T02/T04"))},
      {"select T01/T02:30", &Tempo.select(&1, Tempo.from_iso8601!("T01/T02:30"))},
      {"select T23/T02:30", &Tempo.select(&1, Tempo.from_iso8601!("T23/T02:30"))},
      {"select T22/T06", &Tempo.select(&1, Tempo.from_iso8601!("T22/T06"))},
      {"select T02/PT2H", &Tempo.select(&1, Tempo.from_iso8601!("T02/PT2H"))},
      {"select T02:15/PT30M", &Tempo.select(&1, Tempo.from_iso8601!("T02:15/PT30M"))},
      {"select T00/PT30M", &Tempo.select(&1, Tempo.from_iso8601!("T00/PT30M"))},
      {"select [2]", &Tempo.select(&1, [2])},
      {"select 30D", &Tempo.select(&1, in_its_calendar("30D", &1))},
      {"select 29D/31D", &Tempo.select(&1, in_its_calendar("29D/31D", &1))},
      {"select workdays", &Tempo.select(&1, Tempo.workdays(:US))},
      {"select weekends", &Tempo.select(&1, Tempo.weekends(:US))},
      {"at T02", &Tempo.at(&1, Tempo.from_iso8601!("T02"))},
      {"at T02:30", &Tempo.at(&1, Tempo.from_iso8601!("T02:30"))},
      {"rule BYHOUR=2", &rule(&1, "FREQ=DAILY;BYHOUR=2;COUNT=4")},
      {"rule BYHOUR=0", &rule(&1, "FREQ=DAILY;BYHOUR=0;COUNT=4")},
      {"rule BYHOUR=2;BYMINUTE=15,45", &rule(&1, "FREQ=DAILY;BYHOUR=2;BYMINUTE=15,45;COUNT=6")},
      {"rule BYMONTHDAY=30", &rule(&1, "FREQ=MONTHLY;BYMONTHDAY=30;COUNT=4")},
      {"rule BYDAY=FR", &rule(&1, "FREQ=WEEKLY;BYDAY=FR;COUNT=4")}
    ]
  end

  # A selector that names a day by its number is written in the calendar of
  # what it selects from, as a day is numbered by its calendar.
  defp in_its_calendar(selector, %Tempo{calendar: calendar}),
    do: Tempo.from_iso8601!(selector, calendar)

  # The occurrences of a rule that starts on the value.
  defp rule(value, parts) do
    with {:ok, recurrence} <- RRule.parse(parts, from: value),
         do: Tempo.to_interval(recurrence)
  end

  defp spans do
    [
      {"recurrence P1M", &recurrence(&1, "P1M")},
      {"recurrence P1W", &recurrence(&1, "P1W")},
      {"recurrence P1D", &recurrence(&1, "P1D")},
      {"recurrence PT1H", &recurrence(&1, "PT1H")},
      {"recurrence PT30M", &recurrence(&1, "PT30M")},
      {"interval to a day on", &interval_to(&1, day: 1)},
      {"interval to an hour on", &interval_to(&1, hour: 1)},
      {"interval for P1D", &interval_for(&1, "P1D")},
      {"interval for PT1H", &interval_for(&1, "PT1H")},
      {"interval ending P1D", &interval_ending(&1, "P1D")},
      {"interval ending PT1H", &interval_ending(&1, "PT1H")}
    ]
  end

  defp sets do
    [
      {"union with itself an hour on", &union/1},
      {"intersection with its month",
       &with_month(&1, fn value, month -> Tempo.intersection(value, month) end)},
      {"difference of its month",
       &with_month(&1, fn value, month -> Tempo.difference(month, value) end)},
      {"symmetric_difference with its month",
       &with_month(&1, fn value, month -> Tempo.symmetric_difference(value, month) end)},
      {"complement within its month",
       &with_month(&1, fn value, month -> Tempo.complement(value, within: month) end)}
    ]
  end

  defp walks do
    [
      {"Enum.take", &Enum.take(&1, 40)},
      {"Enum.at 0", &Enum.at(&1, 0)},
      {"Enum.at -1", &Enum.at(&1, -1)},
      {"Enum.slice", &Enum.slice(&1, 0, 3)},
      {"Enum.at 0 of its span", &of_its_span(&1, fn span -> Enum.at(span, 0) end)},
      {"Enum.at -1 of its span", &of_its_span(&1, fn span -> Enum.at(span, -1) end)},
      {"Enum.take of its span", &of_its_span(&1, fn span -> Enum.take(span, 40) end)}
    ]
  end

  defp split(value) do
    {date, time} = Tempo.split(value)
    [date, time]
  end

  # The value with no zone, placed in the zone it was read in.
  defp placed(%Tempo{extended: %{zone_id: zone}} = value),
    do: Tempo.in_zone(%{value | extended: nil, shift: nil}, zone)

  # A step that skips a busy span from the value to the value stepped.
  defp skipping(value, step, busy_for) do
    with %Tempo{} = later <- Tempo.shift(value, busy_for),
         {:ok, busy} <- Interval.new(from: value, to: later) do
      Tempo.shift(value, step, skipping: busy)
    end
  end

  defp recurrence(value, cadence) do
    with {:ok, text} <- Tempo.to_iso8601(value),
         {:ok, recurrence} <- Tempo.from_iso8601("R4/" <> text <> "/" <> cadence) do
      Tempo.to_interval(recurrence)
    end
  end

  # An interval written from the value to the value stepped, and one written
  # with a duration after or before the value: each as it is read, and as
  # the span it is.
  defp interval_to(value, step) do
    with %Tempo{} = later <- Tempo.shift(value, step),
         {:ok, from} <- Tempo.to_iso8601(value),
         {:ok, to} <- Tempo.to_iso8601(later) do
      read_and_converted(from <> "/" <> to)
    end
  end

  defp interval_for(value, duration) do
    with {:ok, from} <- Tempo.to_iso8601(value), do: read_and_converted(from <> "/" <> duration)
  end

  defp interval_ending(value, duration) do
    with {:ok, to} <- Tempo.to_iso8601(value), do: read_and_converted(duration <> "/" <> to)
  end

  defp read_and_converted(text) do
    with {:ok, interval} <- Tempo.from_iso8601(text), do: [interval, Tempo.to_interval(interval)]
  end

  defp union(value) do
    with %Tempo{} = later <- Tempo.shift(value, hour: 1), do: Tempo.union(value, later)
  end

  defp with_month(value, operation) do
    with %Tempo{} = month <- Tempo.trunc(value, :month), do: operation.(value, month)
  end

  defp of_its_span(value, walk) do
    with {:ok, %Interval{} = span} <- Tempo.to_interval(value), do: walk.(span)
  end

  @doc """
  Every cell run: how many there are, how many of each operation gave a
  value, and the findings.

  A finding is `{property, operation, text, detail}`, the property `:raises`
  for an operation that raised, `:not_read` for a value it gave that the
  reader does not take, or reads as another, and `:not_as_its_twin` for a
  value of another calendar that is given other dates and times than the
  Gregorian value of the same day is.
  """
  @spec harvest() :: %{cells: non_neg_integer(), gave: map(), findings: [tuple()]}
  def harvest do
    cells =
      for(text <- texts(), operation <- operations(), do: {text, operation}) ++
        for {text, twin, calendar} <- twins(),
            {name, _operation} = operation <- operations(),
            calendar == "buddhist" or of_any_calendar?(name),
            calendar != "iso-week" or built_for_weeks?(name),
            do: {twin, operation, {text, calendar}}

    {:ok, supervisor} = Task.Supervisor.start_link()

    results =
      supervisor
      |> Task.Supervisor.async_stream_nolink(cells, &cell/1,
        timeout: 30_000,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(cells)
      |> Enum.map(&reported/1)

    gave = for {name, :gave, _findings} <- results, do: name

    %{
      cells: Enum.count(cells),
      gave: Enum.frequencies(gave),
      findings: Enum.flat_map(results, fn {_name, _gave, findings} -> findings end)
    }
  end

  defp cell({text, {name, operation}}) do
    values = text |> Tempo.from_iso8601!() |> operation.() |> values_in()
    {name, values, not_read_among(values), []}
  end

  # A twin is given what its Gregorian value is, date for date.
  defp cell({twin, {name, operation}, {text, calendar}}) do
    values = twin |> Tempo.from_iso8601!() |> operation.() |> values_in()
    given = text |> Tempo.from_iso8601!() |> operation.() |> values_in()

    differs =
      case {Enum.map(given, &dated/1), Enum.map(values, &gregorian(&1, calendar))} do
        {same, same} -> []
        {gregorian, twin} -> [{inspect(gregorian, limit: 24), inspect(twin, limit: 24)}]
      end

    {name, values, not_read_among(values), differs}
  end

  defp not_read_among(values),
    do: for(value <- values, found = not_read(value), found != nil, do: {value, found})

  defp dated(%Tempo{time: time, shift: shift}), do: {time, shift}

  # A value of another calendar as the Gregorian units and offset it names,
  # worked out here: a Buddhist year is 543 on, and a Hebrew date is asked
  # of Elixir's `Date`.
  defp gregorian(%Tempo{time: [{:year, year} | rest], shift: shift}, "buddhist")
       when is_integer(year),
       do: {[{:year, year - @buddhist_years_on} | rest], shift}

  defp gregorian(
         %Tempo{time: [{:year, year}, {:month, month}, {:day, day} | clock], shift: shift},
         "hebrew"
       )
       when is_integer(year) and is_integer(month) and is_integer(day) do
    {:ok, date} = Date.new(year, month, day, Calendrical.Hebrew)
    {:ok, date} = Date.convert(date, Calendar.ISO)
    {[year: date.year, month: date.month, day: date.day] ++ clock, shift}
  end

  defp gregorian(
         %Tempo{time: [{:year, year}, {:week, week}, {:day_of_week, day} | clock], shift: shift},
         "iso-week"
       )
       when is_integer(year) and is_integer(week) and is_integer(day) do
    {:ok, date} = Date.new(year, week, day, Calendrical.ISOWeek)
    {:ok, date} = Date.convert(date, Calendar.ISO)
    {[year: date.year, month: date.month, day: date.day] ++ clock, shift}
  end

  defp gregorian(%Tempo{} = value, _calendar), do: dated(value)

  defp reported({{:ok, {name, values, not_read, differs}}, cell}) do
    text = elem(cell, 0)

    findings =
      for({value, found} <- not_read, do: {:not_read, name, text, {inspect(value), found}}) ++
        for detail <- differs, do: {:not_as_its_twin, name, text, detail}

    {name, if(values == [], do: :gave_none, else: :gave), findings}
  end

  defp reported({{:exit, reason}, cell}) do
    {name, _operation} = elem(cell, 1)
    {name, :gave_none, [{:raises, name, elem(cell, 0), raised(reason)}]}
  end

  # The exception and where it was raised, for a report a reader can act on.
  defp raised({%{__exception__: true} = exception, [_ | _] = stack}),
    do: {exception.__struct__, stack |> Enum.take(3) |> Enum.map(&frame/1)}

  defp raised(reason), do: reason

  defp frame({module, function, arity, location}) when is_list(arity),
    do: frame({module, function, Enum.count(arity), location})

  defp frame({module, function, arity, location}),
    do: "#{inspect(module)}.#{function}/#{arity}:#{location[:line]}"

  # Every Tempo value in what an operation gives: the ends of a span, the
  # members of a set, each value of a list. An error is an answer, and
  # holds none.
  defp values_in({:ok, given}), do: values_in(given)
  defp values_in(%Tempo{} = value), do: [value]
  defp values_in(%Interval{from: from, to: to}), do: values_in(from) ++ values_in(to)
  defp values_in(%Tempo.Set{set: members}), do: Enum.flat_map(members, &values_in/1)
  defp values_in(%Tempo.Range{first: first, last: last}), do: values_in(first) ++ values_in(last)
  defp values_in(list) when is_list(list), do: Enum.flat_map(list, &values_in/1)

  defp values_in(%IntervalSet{} = set) do
    if IntervalSet.bounded?(set),
      do: set |> IntervalSet.members() |> Enum.flat_map(&values_in/1),
      else: set |> IntervalSet.walk() |> Enum.take(20) |> Enum.flat_map(&values_in/1)
  end

  defp values_in(_an_error_or_no_value), do: []

  # A value the reader takes is written, and read as itself.
  defp not_read(%Tempo{} = value) do
    with {:ok, text} <- Tempo.to_iso8601(value),
         {:ok, ^value} <- Tempo.from_iso8601(text, value.calendar) do
      nil
    else
      {:ok, other} -> {:reads_as, inspect(other)}
      {:error, error} -> error.__struct__
    end
  end
end
