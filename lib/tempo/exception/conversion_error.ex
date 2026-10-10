defmodule Tempo.ConversionError do
  @moduledoc """
  Exception returned, or raised by a bang function, when a value
  cannot be converted to what was asked for: a standard-library
  `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or
  `t:DateTime.t/0`, an ISO 8601 or RRULE string, or — from
  `Tempo.to_interval/2` and `Tempo.to_interval_set/2` — the interval
  or occurrences a value spans.

  A value with no interval of its own says why in `:reason`:

  * `:bare_duration` — a duration has no place on the time line.

  * `:one_of_set` — a one-of set is an epistemic disjunction, not a
    list of intervals.

  * `:finest_resolution` — no finer unit exists to bound the span.

  * `:unanchored_group` — a group with no year or month to bound it,
    such as `5G10DU`, days 41 to 50 of no particular year.

  * `:open_range` — one end of the range is unbounded.

  * `:grouped_component` — a step would count from a unit that holds
    several values and names none of them to step one by one, such as the
    day after `~o"2026Y6M3G4DU"`, the third group of four days of June.
    Returned by `Tempo.shift/3` too, for a shift that steps such a unit.

  * `:counted_in_group` — a unit after a group counts from the group's
    start (ISO 8601-2 §5.4.2: `~o"2018Y2G3MU50D"` is the fiftieth day of
    the second quarter), which takes one whole number and the units the
    group is counted in. `~o"2G3MU15D"` has no year to count the group's
    days in, and `~o"2026Y2G3MU{1,15}D"` counts a set.

  * `:recurring_interval` and `:recurring_duration` — a recurrence
    is a rule for its occurrences, not one span.

  * `:too_many_values` — the value names more than 10,000 values, the
    most that are listed or converted at once, as a recurrence gives at
    most 10,000 occurrences: `~o"2026Y{1..12}M{1..28}DT{0..23}H{0..59}M"`
    is 483,840 minutes. A period of a rule gives at most as many
    occurrences, whatever the rule's count or window, and a position (`I`)
    picks among at most as many candidates of one. Returned by
    `Tempo.shift/3` and
    `Tempo.select/2` too. `Enum` and `Stream` take such a value's values
    one at a time. The most is the application's `:max_values_at_once`,
    10,000 unless it is set, and is read when Tempo is compiled:
    `config :ex_tempo, max_values_at_once: 100_000`.

  * `:recurrence_set_member` and `:conditional_member` — a
    `Tempo.RecurrenceSet` member of a shape it cannot hold.

  * `:not_built` — the answer is one Tempo does not yet work out in the
    calendar named in `:calendar`, where it is known that it would be
    wrong, so it is refused: `:target` says what was asked for.
    `:rrule` is an RRULE that steps or selects by a month, a year, a
    week of the year or a day of one, for a recurrence of another
    calendar than the Gregorian; `:week_of_month` is a week selected
    from a month where the selection cannot be placed in it; and
    `:rule_to_an_end` is a rule that holds a window (ISO 8601-2 §12.10)
    on a recurrence written with a duration and an end, whose occurrences
    run back from it, in every calendar.
    The [operation matrix](operation-matrix.html) describes the first and
    the last.

  * `:calendar_week_in_month` — a week of the calendar's own numbering
    (`w`) selected in a month, as `~o"2026Y6ML2wN"` is. Such a week is a
    week of the calendar's year and is selected in a year
    (`~o"2026YL2wN"`); a week of a month is written `W`
    (`~o"2026Y6ML2WN"`).

  """

  alias Tempo.Enumeration

  defexception [:value, :target, :reason, :calendar]

  @type t :: %__MODULE__{
          value: any() | nil,
          target: atom() | module() | String.t() | nil,
          reason: atom() | String.t() | nil,
          calendar: module() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{reason: :bare_duration}) do
    "Cannot convert a Tempo.Duration to an interval — a duration has no " <>
      "place on the time line."
  end

  def message(%__MODULE__{reason: :one_of_set}) do
    "Cannot convert a one-of Tempo.Set to an interval — epistemic " <>
      "disjunction is not an interval list. Pick one member, handle the " <>
      "disjunction explicitly, or ask a certainty question " <>
      "(`Tempo.relation_certainty/3`, `Tempo.possibly_before?/2`, …)."
  end

  def message(%__MODULE__{reason: :recurrence_set_member, value: value}) do
    "Cannot read #{inspect(value)} as a Tempo.RecurrenceSet member — a " <>
      "member is a Tempo.Interval (a recurrence or a concrete interval), a Tempo value, " <>
      "a nested Tempo.RecurrenceSet, or a conditional member from " <>
      "Tempo.RecurrenceSet.keep_when/2 or move_when/2."
  end

  def message(%__MODULE__{reason: :conditional_member, value: value}) do
    "Cannot resolve #{inspect(value)} as a conditional Tempo.RecurrenceSet member — it " <>
      "needs :falls_on, a metadata map or a recurrence set, and either :at, a list of durations " <>
      "(Tempo.RecurrenceSet.keep_when/2), or :to_next, a selector " <>
      "(Tempo.RecurrenceSet.move_when/2)."
  end

  def message(%__MODULE__{reason: :too_many_values, value: value}) do
    most = Enumeration.listed_at_once()

    "#{inspect(value)} names more than #{most} values, and #{most} are the most listed or " <>
      "converted at once. Convert a narrower value, or take its values one at a time " <>
      "with `Enum` or `Stream`."
  end

  def message(%__MODULE__{reason: :recurring_interval}) do
    "A recurring interval is a rule generating occurrences, not a single span. " <>
      "Convert it to its occurrences with `Tempo.to_interval/2` (pass `:within` for an " <>
      "unbounded recurrence) and use the set-level API (`Tempo.overlaps?/2`, " <>
      "`Tempo.IntervalSet.relation_matrix/2`)."
  end

  def message(%__MODULE__{reason: :recurring_duration}) do
    "The duration of a finite recurring interval is the total across its " <>
      "occurrences — convert it with `Tempo.to_interval/1` and use " <>
      "`Tempo.IntervalSet.duration/1`."
  end

  def message(%__MODULE__{reason: :finest_resolution, value: value}) when not is_nil(value) do
    "Cannot convert #{inspect(value)} at its finest resolution to an " <>
      "explicit interval — no finer unit exists to bound the span."
  end

  def message(%__MODULE__{reason: :finest_resolution}) do
    "Cannot convert a Tempo at its finest resolution to an explicit interval."
  end

  def message(%__MODULE__{reason: :unanchored_group, value: value}) when not is_nil(value) do
    "Cannot convert the group #{inspect(value)} to an interval — its unit " <>
      "needs coarser calendar context (year/month) to bound the span, which an " <>
      "unanchored or ordinal-day group does not supply."
  end

  def message(%__MODULE__{reason: :unanchored_group}) do
    "Cannot convert an unanchored group to an interval — no coarser " <>
      "calendar context to bound the span."
  end

  def message(%__MODULE__{reason: :open_range, value: value}) when not is_nil(value) do
    "Cannot convert the open-ended range #{inspect(value)} to an interval — " <>
      "one endpoint is unbounded, so it spans no finite set of occurrences."
  end

  def message(%__MODULE__{reason: :open_range}) do
    "Cannot convert an open-ended range to an interval — one endpoint is unbounded."
  end

  def message(%__MODULE__{reason: :grouped_component, value: value}) when not is_nil(value) do
    "Cannot step #{inspect(value)} — the step counts from a unit that holds several " <>
      "values (a set, a range, a group or unspecified digits), which is no one value " <>
      "to count from. Step each value it names instead."
  end

  def message(%__MODULE__{reason: :grouped_component}) do
    "Cannot step a value from a unit that holds several values."
  end

  def message(%__MODULE__{reason: :counted_in_group, value: value}) when not is_nil(value) do
    "Cannot convert #{inspect(value)} — the unit after its group counts from the " <>
      "group's start (ISO 8601-2 §5.4.2), which takes one whole number and the units " <>
      "the group is counted in: a year, for a day counted in a group of months."
  end

  def message(%__MODULE__{reason: :counted_in_group}) do
    "Cannot convert a value whose unit after a group is not one whole number counted " <>
      "from the group's start."
  end

  def message(%__MODULE__{reason: :calendar_week_in_month} = error) do
    "#{not_built_subject(error)} — a week of the calendar's own numbering (`w`) is a week of " <>
      "its year, and a month has none to select. It is selected in a year (`2026YL2wN`), and " <>
      "a week of a month is written `W` (`2026Y6ML2WN`)."
  end

  def message(%__MODULE__{reason: :not_built, target: target, calendar: calendar} = error) do
    "#{not_built_subject(error)} — #{not_built(target)} is not built for #{inspect(calendar)}, " <>
      "#{not_built_calendar(target)}, and is refused where it would be answered wrongly."
  end

  def message(%__MODULE__{value: value, target: target})
      when not is_nil(value) and not is_nil(target) do
    "Cannot convert #{inspect(value)} to #{describe_target(target)}"
  end

  def message(%__MODULE__{target: target}) when not is_nil(target) do
    "Invalid #{describe_target(target)}"
  end

  def message(%__MODULE__{}), do: "Conversion failed"

  # What a refusal of something not built says of the value, of what was
  # asked for and of the calendar it was asked in.
  defp not_built_subject(%__MODULE__{value: nil}), do: "Cannot answer"

  defp not_built_subject(%__MODULE__{value: value}) when is_binary(value),
    do: "Cannot answer #{value}"

  defp not_built_subject(%__MODULE__{value: value}), do: "Cannot answer #{inspect(value)}"

  defp not_built(:selection), do: "a selection that counts days within a month or a year"
  defp not_built(:season), do: "a season"
  defp not_built(:shift), do: "a step by days from a value that holds several months or years"
  defp not_built(:month), do: "a month of a year that begins within one"

  defp not_built(:rrule),
    do: "an RRULE that steps or selects by a month, a year, a week of the year or a day of one"

  defp not_built(:week_of_month), do: "a week of a month"

  defp not_built(:rule_to_an_end),
    do:
      "a rule that holds a window, on a recurrence written to its end, whose occurrences " <>
        "run back from it,"

  defp not_built(other), do: "#{other}"

  defp not_built_calendar(:month),
    do: "which does not count that year's months from the day it begins"

  defp not_built_calendar(:rrule),
    do:
      "since RFC 5545 counts them in the Gregorian calendar and RFC 7529's RSCALE is not written"

  # A day or a time under a masked week of a month is refused in every
  # calendar, so what is said of the calendar is said of the two cases.
  defp not_built_calendar(:week_of_month),
    do: "in a year that does not begin with its first month"

  defp not_built_calendar(:rule_to_an_end), do: "as for every calendar"

  defp not_built_calendar(_target), do: "whose year does not begin with its first month"

  # A module target reads as the module (`Date`), a plain atom as its
  # name (`rrule`).
  defp describe_target(atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> module -> module
      name -> name
    end
  end

  defp describe_target(other), do: inspect(other)
end
