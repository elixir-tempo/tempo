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
  # Two are left. The first is in every calendar but the Gregorian: an RRULE
  # that steps or selects by a month, a year, a week of the year or a day of
  # one, which RFC 5545 counts in the Gregorian calendar. The second is in
  # every calendar: a rule that holds a §12.10 window, on a recurrence
  # written to its end, whose occurrences run back from it.
  #
  # Five were of a year that does not begin with its first month (a month, a
  # selection, a season, a step and a week of a month in Calendrical's Julian
  # `March25`, `March1`, `Sept1` and `Dec25`, and in
  # `Calendrical.Reform.England` to 1750). Those calendars count their months
  # from the day the year begins since 2026-10-10, and each area is answered.
  # A week of a month that the merge of a selector cannot place is refused by
  # the same name (`week_of_month/2`), and a week of the calendar's own
  # numbering (`w`) under a month for good
  # (`Tempo.RRule.Selection.calendar_week_in_its_year/2`).

  alias Tempo.{Calendars, ConversionError, Duration, Interval}

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
  # A week selected from a month that the merge cannot place. A week after a
  # month is a week of the month, which `Tempo.select/2` gives as the span of
  # its dates where it is a whole number selected from a month, each of a
  # set of them or each a mask matches, with a day or a time under it or
  # none. `selector` is what was to be merged onto `from`. A week selected
  # from a day or a time of day is as coarse as its period or coarser, and
  # is a filter by the week of its month.
  @spec week_of_month(list(), Tempo.t()) :: {:error, ConversionError.t()}
  def week_of_month(selector, %Tempo{calendar: calendar} = from) when is_list(selector) do
    asked = "the selection of #{inspect(selector)} from #{inspect(from)}"
    {:error, error(asked, :week_of_month, Calendars.effective(calendar))}
  end

  @doc false
  # A rule on a recurrence written with a duration and an end is asked of
  # each period back from the end, and is answered (`R3/P1D/2019-01-08/FL7KN`
  # is the three Sundays before 8 January). What is left is such a rule that
  # holds a §12.10 window, which can place an occurrence outside the period
  # that selects it: the walk back does not reach for those. A rule with a
  # count, no start and an end it runs until, which only a struct built by
  # hand is, is refused by the same name.
  @spec rule_to_an_end(Interval.t()) :: ConversionError.t()
  def rule_to_an_end(%Interval{to: %Tempo{calendar: calendar}} = recurrence),
    do: error(recurrence, :rule_to_an_end, Calendars.effective(calendar))
end
