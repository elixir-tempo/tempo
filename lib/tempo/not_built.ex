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
  # and a step by days from a value that holds several months or years,
  # which is counted through the values and not asked of the calendar. The
  # fourth is a month of a year whose months the calendar numbers as its
  # dates do, and not from the day the year begins (a year of
  # `Calendrical.Reform.England` before 1751): no one span of the year.

  alias Tempo.{Compare, ConversionError, Duration, Interval, UnitValues}

  # The units a selection is resolved within when the period it is given is
  # finer than a month.
  @finer_than_a_month [:week, :day, :day_of_year, :day_of_week, :hour, :minute, :second]

  # The units of a duration that do not reach a day.
  @coarser_than_a_day [:year, :month]

  # The calendars nearly every value is in, whose years begin with their
  # first month: a value in one is answered before anything is asked of it,
  # since these functions are called for every value read and every step.
  @first_month_first [Calendrical.Gregorian, Calendar.ISO]

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
  # counted from the year's or the day's own start: each is answered.
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
  # month without its month, selected from a month or a year, and a month
  # alone in a year whose months are not counted from its start. A weekday
  # is selected among the span's own days, and is answered.
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
  # A step that reaches the day, from a value that holds several years or
  # months, or an unspecified day of the month its year begins within, in a
  # year that does not begin with its first month. Such a step is counted
  # through the values the units hold, where the days of that year are not
  # in the order of their numbers; one whole date is stepped by its
  # calendar, and so is each date a mask stands for.
  @spec shift(Tempo.t(), list()) :: :ok | {:error, ConversionError.t()}
  def shift(%Tempo{calendar: calendar}, _duration_time)
      when calendar in [nil | @first_month_first],
      do: :ok

  def shift(%Tempo{time: time, calendar: calendar} = tempo, duration_time)
      when is_list(time) and is_list(duration_time) do
    calendar = Compare.effective_calendar(calendar)

    if counted_where_the_year_turns?(time, duration_time, calendar),
      do: {:error, error(tempo, :shift, calendar)},
      else: :ok
  end

  def shift(_value, _duration_time), do: :ok

  defp counted_where_the_year_turns?(time, duration_time, calendar) do
    years = year_of(time)

    not UnitValues.years_begin_with_first_month?(years, calendar) and
      reaches_the_day?(duration_time) and counted_through_the_values?(time, years, calendar)
  end

  defp counted_through_the_values?(time, years, calendar) do
    several?(years) or several?(value_of(time, :month)) or
      unspecified_day_of_turning_month?(time, years, calendar)
  end

  defp unspecified_day_of_turning_month?(time, year, calendar) when is_integer(year) do
    case {value_of(time, :month), value_of(time, :day)} do
      {month, day} when is_integer(month) and not is_integer(day) and not is_nil(day) ->
        UnitValues.month_year_begins_within(year, calendar) == month

      _one_day_or_none ->
        false
    end
  end

  defp unspecified_day_of_turning_month?(_time, _years, _calendar), do: false

  defp reaches_the_day?(duration_time) do
    Enum.any?(duration_time, fn {unit, amount} ->
      unit not in @coarser_than_a_day and amount != 0
    end)
  end

  # A set of values, or a range of them: what a step counts through.
  defp several?(values), do: is_list(values) or is_struct(values, Range)

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
