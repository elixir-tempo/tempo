defmodule Tempo.NotBuilt do
  @moduledoc false

  # What Tempo does not yet work out and is known to answer wrongly. For
  # 2.0 each such area is refused, with a `Tempo.ConversionError` whose
  # reason is `:not_built` and which names the calendar, until it is built
  # (decided 2026-10-05). An area is one function here, called where a value
  # is read and where an answer would leave the library, so building an area
  # is the removal of its function and of the calls to it.
  # `guides/operation-matrix.md` lists the areas.
  #
  # Three of them are in a calendar whose year does not begin with its first
  # month (Calendrical's Julian `March25`, `March1`, `Sept1` and `Dec25`, and
  # `Calendrical.Reform.England` until 1751): a selection that counts days
  # within a month or a year, which the resolver counts as `1..n` of the
  # month a date names; a season, which is placed by the year it starts in;
  # and a step from several months of a year whose months the calendar does
  # not count, which the walk cannot list. The
  # fourth is a month of a year whose months the calendar numbers as its
  # dates do, and not from the day the year begins (a year of
  # `Calendrical.Reform.England` before 1751): no one span of the year. The
  # fifth is in every calendar but the Gregorian: an RRULE that steps or
  # selects by a month, a year, a week of the year or a day of one, which
  # RFC 5545 counts in the Gregorian calendar. The sixth is what is left of a
  # week of a month, which the calendar numbers and is otherwise answered: one
  # in a year that does not begin with its first month, one selected from a
  # month that is no whole number, and one a rule names in a month as a week
  # of the calendar's own.

  alias Tempo.{Compare, ConversionError, Duration, Interval, UnitValues}

  # The units a selection is resolved within when the period it is given is
  # finer than a month.
  @finer_than_a_month [:week, :day, :day_of_year, :day_of_week, :hour, :minute, :second]

  # The calendars nearly every value is in, whose years begin with their
  # first month: a value in one is answered before anything is asked of it,
  # since these functions are called for every value read and every step.
  @first_month_first [Calendrical.Gregorian, Calendar.ISO]

  # The calendar RFC 5545 writes a rule in, as a value holds it.
  @gregorian [Calendrical.Gregorian, Calendar.ISO, nil]

  # The units of a cadence that an RRULE counts in its calendar,
  # `FREQ=YEARLY` and `FREQ=MONTHLY`, and the tokens of a selection that it
  # does: `BYMONTH`, `BYMONTHDAY`, `BYYEARDAY` and `BYWEEKNO`.
  @stepped_by_rrule_calendar [:year, :month]
  @selected_by_rrule_calendar [:month, :day, :day_of_year, :week]

  @doc false
  # The refusal of `target` for `value`, naming `calendar`.
  @spec error(term(), atom(), module()) :: ConversionError.t()
  def error(value, target, calendar) do
    ConversionError.exception(
      value: value,
      target: target,
      reason: :not_built,
      calendar: calendar
    )
  end

  @doc false
  # A value that holds a month and no day of it, in a year whose months its
  # calendar does not count from the day the year begins. A value being read
  # is asked in the calendar it is read in, as it is written: a time of day
  # under a month is placed on a day of it once it is read.
  @spec month(term(), module() | nil) :: :ok | {:error, ConversionError.t()}
  def month(value, calendar \\ nil)

  def month(_value, calendar) when calendar in @first_month_first, do: :ok

  def month(%Tempo{calendar: calendar}, nil) when calendar in [nil | @first_month_first],
    do: :ok

  def month(%Tempo{time: time} = tempo, calendar) when is_list(time) do
    calendar = Compare.effective_calendar(calendar || tempo.calendar)

    if month_alone?(time) and not months_counted?(year_of(time), calendar),
      do: {:error, error(tempo, :month, calendar)},
      else: :ok
  end

  def month(_no_one_value, _calendar), do: :ok

  @doc false
  # An answer as it is, or the refusal of the month it is.
  @spec result(answer) :: answer | {:error, ConversionError.t()} when answer: term()
  def result(%Tempo{calendar: calendar} = tempo) when calendar in [nil | @first_month_first],
    do: tempo

  def result(%Tempo{} = tempo), do: refused(month(tempo), tempo)
  def result({:ok, %Tempo{} = tempo} = answer), do: refused(month(tempo), answer)
  def result(answer), do: answer

  defp refused(:ok, answer), do: answer
  defp refused({:error, _not_built} = error, _answer), do: error

  @doc false
  # A season of a year that does not begin with its first month. A season is
  # placed by the year it starts in, and in such a year that is another
  # season than the one of the same number in the calendar its months are
  # taken from: the spring that starts in a `March25` year 1750 is the
  # Julian spring of 1751.
  @spec season(integer(), pos_integer(), module()) :: :ok | {:error, ConversionError.t()}
  def season(year, code, calendar) do
    if UnitValues.year_begins_with_first_month?(year, calendar),
      do: :ok,
      else: {:error, error("season #{code} of the year #{year}", :season, calendar)}
  end

  @doc false
  # An RRULE (RFC 5545) is a rule of the Gregorian calendar: its months, its
  # years, its weeks of the year and its days of a month or of a year are
  # that calendar's, and RFC 7529's `RSCALE`, which names another, is not
  # written. So a recurrence of another calendar that steps or selects by
  # one of them has no RRULE yet: a Hebrew rule of months was written as one
  # of Gregorian months. One that steps by weeks, by days or by the units of
  # a time of day, and selects by weekday and time of day, is the same rule
  # in every calendar, and is written.
  @spec rrule(Interval.t()) :: :ok | {:error, ConversionError.t()}
  def rrule(%Interval{} = recurrence) do
    case rule_calendar(recurrence) do
      nil -> :ok
      calendar -> rrule_in(recurrence, calendar)
    end
  end

  defp rrule_in(%Interval{duration: duration, repeat_rule: rule} = recurrence, calendar) do
    if stepped_by_rrule_calendar?(duration) or selected_by_rrule_calendar?(rule),
      do: {:error, error(recurrence, :rrule, calendar)},
      else: :ok
  end

  # The calendar a recurrence is in where that is not the Gregorian: its
  # rule's, or its start's.
  defp rule_calendar(%Interval{from: from, repeat_rule: rule}) do
    [rule, from]
    |> Enum.flat_map(fn
      %Tempo{calendar: calendar} when calendar not in @gregorian -> [calendar]
      _gregorian_or_absent -> []
    end)
    |> List.first()
  end

  defp stepped_by_rrule_calendar?(%Duration{time: time}) when is_list(time),
    do: Enum.any?(time, &(is_tuple(&1) and elem(&1, 0) in @stepped_by_rrule_calendar))

  defp stepped_by_rrule_calendar?(_no_cadence), do: false

  defp selected_by_rrule_calendar?(%Tempo{time: time}) when is_list(time),
    do: selected_by_rrule_calendar?(time)

  defp selected_by_rrule_calendar?(units) when is_list(units) do
    Enum.any?(units, fn
      {:selection, selection} -> selected_by_rrule_calendar?(selection)
      entry when is_tuple(entry) -> elem(entry, 0) in @selected_by_rrule_calendar
      _other -> false
    end)
  end

  defp selected_by_rrule_calendar?(_no_rule), do: false

  @doc false
  # A selection (ISO 8601-2 §12.11), in a value or as the rule of a
  # recurrence, in a year that does not begin with its first month. `value`
  # is the value that holds the selection, or the recurrence the selection
  # is the rule of.
  #
  # A day of a month selected without its month, a weekday and an ordinal
  # are counted within the period the selection is given, and where that is
  # a month or a year the count is of the month a date names. A month alone
  # is the month the calendar counts, a month with a day is the date they
  # name, and a day of the year, a week and the units of a time of day are
  # counted from the year's or the day's own start: each is answered. A day
  # with no month, selected in a year, is a day of the year by the time it is
  # asked here (`Tempo.RRule.Selection.read_in_its_period/1`).
  @spec selection(list(), Tempo.t() | Interval.t(), module()) ::
          :ok | {:error, ConversionError.t()}
  def selection(selection, value, calendar) when is_list(selection) do
    years = years_of(value)

    cond do
      UnitValues.years_begin_with_first_month?(years, calendar) ->
        :ok

      counts_days?(selection) and within_a_month_or_year?(value) ->
        {:error, error(value, :selection, calendar)}

      month_alone?(selection) and not months_counted?(years, calendar) ->
        {:error, error(value, :month, calendar)}

      true ->
        :ok
    end
  end

  @doc false
  # A selector of `Tempo.select/2`, or the unit and the numbers of one given
  # as numbers, that is merged onto `from`, the start of the span it selects
  # from, in a year that does not begin with its first month: a day of a
  # month without its month, selected from a month, and a month alone in a
  # year whose months are not counted from its start. A weekday is selected
  # among the span's own days, and is answered; so is a day with no month
  # selected from a year, which is merged as the day of the year it is.
  @spec selector(list(), Tempo.t()) :: :ok | {:error, ConversionError.t()}
  def selector(selector, %Tempo{time: time, calendar: calendar} = from)
      when is_list(selector) and is_list(time) do
    calendar = Compare.effective_calendar(calendar)
    years = year_of(time)
    asked = "the selection of #{inspect(selector)} from #{inspect(from)}"

    cond do
      UnitValues.years_begin_with_first_month?(years, calendar) ->
        :ok

      day_alone?(selector) and not finer_than_a_month?(time) ->
        {:error, error(asked, :selection, calendar)}

      month_alone?(selector) and not months_counted?(years, calendar) ->
        {:error, error(asked, :month, calendar)}

      true ->
        :ok
    end
  end

  def selector(_selector, _base), do: :ok

  @doc false
  # A week selected from a month that is not built. A week after a month is
  # a week of the month, which `Tempo.select/2` gives as the span of its
  # dates where it is one whole number selected from a month, or each of a
  # set of them. What is refused here is one that is neither (a mask), and
  # one a selection names as a week of the calendar's own (`w`).
  # `selector` is what was to be merged onto `from`. A week selected from a
  # day or a time of day is as coarse as its period or coarser, and is a
  # filter by the week of the year.
  @spec week_of_month(list(), Tempo.t()) :: {:error, ConversionError.t()}
  def week_of_month(selector, %Tempo{calendar: calendar} = from) when is_list(selector) do
    asked = "the selection of #{inspect(selector)} from #{inspect(from)}"
    {:error, error(asked, :week_of_month, Compare.effective_calendar(calendar))}
  end

  @doc false
  # A selection that names a week and is resolved in a month: in a value
  # whose selection follows a month (`2026Y6ML2WN`), and as the rule of a
  # recurrence that steps by months from a month, a year or no start. A week
  # under a month is a week of the month (`W`, decided 2026-10-07), which
  # the resolver gives as the span of the dates the calendar numbers in it,
  # or as those dates to the parts beside it that pick within it
  # (`Tempo.RRule.Selection.read_in_its_period/1`). What is still refused is
  # a week of the calendar's own numbering (`w`), which is a week of its
  # year: what the resolver gave for it was the whole month where its first
  # day was in the week of that number.
  @spec week_in_month(list(), Tempo.t() | Interval.t(), module()) ::
          :ok | {:error, ConversionError.t()}
  def week_in_month(selection, value, calendar) when is_list(selection) do
    if :calendar_week in selected_units(selection) and resolved_in_a_month?(value),
      do: {:error, error(value, :week_of_month, calendar)},
      else: :ok
  end

  defp resolved_in_a_month?(%Tempo{time: time}) when is_list(time) do
    context = Enum.take_while(time, &(not match?({:selection, _selection}, &1)))
    match?({:month, _month}, List.last(context))
  end

  defp resolved_in_a_month?(%Interval{
         duration: %Duration{time: [{:month, _amount} | _finer]},
         from: from
       }),
       do: no_finer_than_a_month?(from)

  defp resolved_in_a_month?(_another), do: false

  defp no_finer_than_a_month?(%Tempo{time: time}) when is_list(time),
    do: not finer_than_a_month?(time)

  defp no_finer_than_a_month?(no_start), do: no_start in [nil, :undefined]

  @doc false
  # A step from a value that holds several months (a set, a range, a mask or
  # an unspecified one) in a year whose months its calendar does not count
  # from the day the year begins: a year of `Calendrical.Reform.England`
  # before 1751. The values such a unit stands for are listed by the
  # calendar's count of its months, which that year has none of, so the step
  # has no values to reach. Every other step in a calendar whose year does
  # not begin with its first month is each value stepped by its calendar.
  @spec shift(Tempo.t(), list()) :: :ok | {:error, ConversionError.t()}
  def shift(%Tempo{calendar: calendar}, _duration_time)
      when calendar in [nil | @first_month_first],
      do: :ok

  def shift(%Tempo{time: time, calendar: calendar} = tempo, duration_time)
      when is_list(time) and is_list(duration_time) do
    calendar = Compare.effective_calendar(calendar)

    if months_not_listed?(time, year_of(time), calendar),
      do: {:error, error(tempo, :shift, calendar)},
      else: :ok
  end

  def shift(_value, _duration_time), do: :ok

  defp months_not_listed?(time, years, calendar) do
    several_months?(value_of(time, :month)) and
      not UnitValues.years_begin_with_first_month?(years, calendar) and
      not months_counted?(years, calendar)
  end

  defp several_months?(nil), do: false
  defp several_months?(month) when is_integer(month), do: false
  defp several_months?(_a_set_a_mask_or_any), do: true

  # The years a value, or the start of a recurrence, names.
  defp years_of(%Tempo{time: time}) when is_list(time), do: year_of(time)
  defp years_of(%Interval{from: %Tempo{time: time}}) when is_list(time), do: year_of(time)
  defp years_of(_no_one_start), do: nil

  defp year_of(time), do: value_of(time, :year)

  # A unit's value in a time list, whose entries are not all pairs: a group
  # of a set is a 3-tuple.
  defp value_of(time, unit) do
    case List.keyfind(time, unit, 0) do
      nil -> nil
      entry -> elem(entry, 1)
    end
  end

  defp months_counted?(year, calendar) when is_integer(year),
    do: UnitValues.months_counted_from_year_start?(year, calendar)

  defp months_counted?(years, calendar) do
    years
    |> UnitValues.whole_years()
    |> Enum.all?(&UnitValues.months_counted_from_year_start?(&1, calendar))
  end

  defp month_alone?(time),
    do: List.keymember?(time, :month, 0) and not List.keymember?(time, :day, 0)

  defp day_alone?(time),
    do: List.keymember?(time, :day, 0) and not List.keymember?(time, :month, 0)

  # Whether a selection counts days within the period it is given: a day of
  # a month with no month beside it, a weekday with no week beside it, or an
  # ordinal. A selection within the selection is counted as it is.
  defp counts_days?(selection) do
    units = selected_units(selection)

    (:day in units and :month not in units) or
      (:day_of_week in units and :week not in units) or
      :instance in units
  end

  defp selected_units(selection) when is_list(selection),
    do: Enum.flat_map(selection, &selected_unit/1)

  defp selected_unit({:selection, nested}), do: selected_units(nested)
  defp selected_unit(entry) when is_tuple(entry), do: [elem(entry, 0)]
  defp selected_unit(_other), do: []

  # Whether the period a selection is resolved in is a month, a year or
  # longer: the units a value holds beside its selection, or the unit a
  # recurrence steps by. A recurrence written with no cadence resolves its
  # rule in the span it names, which is taken to be one.
  defp within_a_month_or_year?(%Tempo{time: time}), do: not finer_than_a_month?(time)

  defp within_a_month_or_year?(%Interval{duration: %Duration{time: [{unit, _amount} | _rest]}}),
    do: unit not in @finer_than_a_month

  defp within_a_month_or_year?(_no_cadence), do: true

  defp finer_than_a_month?(time),
    do: Enum.any?(time, &(is_tuple(&1) and elem(&1, 0) in @finer_than_a_month))
end
