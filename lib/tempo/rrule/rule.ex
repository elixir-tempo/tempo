defmodule Tempo.RRule.Rule do
  @moduledoc """
  A canonical, typed representation of an RFC 5545 RRULE.

  This is the input to `Tempo.RRule.Expander.expand/3`. Every
  parser (`Tempo.RRule.parse/2`, the `ical` library's
  `%ICal.Recurrence{}`, hand-built rules for tests) converts to
  this shape before expansion runs. Keeping a single struct means
  the expander has one input vocabulary to match against, and all
  `BY*` fields carry their RFC-typed form: lists of integers with
  negative values permitted where the RFC allows.

  ### Fields

  * `:freq` — one of `:second`, `:minute`, `:hour`, `:day`,
    `:week`, `:month`, `:year`. Required.

  * `:interval` — positive integer multiplier for the frequency.
    Default `1`.

  * `:count` — terminate after this many occurrences. Mutually
    exclusive with `:until` per RFC 5545.

  * `:until` — terminate at or before this `t:Tempo.t/0`. Mutually
    exclusive with `:count`.

  * `:wkst` — week-start day as an integer 1–7 (Monday–Sunday, ISO
    convention). Default `1`. Affects `:byweekno` calculations.

  * `:skip` — what a monthly or a yearly rule does with a day of the month that a month lacks, its start's or one it writes (`BYMONTHDAY=31`), as RFC 7529's `SKIP` and JSCalendar's `skip` name it. `:omit`, the default and RFC 5545's rule, lists no occurrence there: the rule states its start's day (ISO 8601-2 Annex C.3), and a day a month lacks is passed over. `:backward` lists the month's last day, as an ISO 8601 recurrence does, and `:forward` the first day of the month after. A day counted from the end that a month lacks (`BYMONTHDAY=-31` in a month of thirty days) is the day before the month's first: `:forward` lists the first, and `:backward` the last day of the month before.

  * `:rscale` — the calendar module the rule is counted in, where RFC 7529's `RSCALE` or JSCalendar's `rscale` names one (`calendar_from_rscale/1`), and `nil` where the rule names none and is counted in the calendar of its start. A start in another calendar is brought into it (`start_in_rscale/2`), and a `:bymonth` is then the month RFC 7529 numbers: Nisan is the seventh month of every Hebrew year, where it is the eighth in order in a year with a leap month.

  * `:bymonth` — list of integers 1–12, and under an `:rscale` whose calendar has them, leap months, each as the month it follows: `{5, :leap}` is RFC 7529's `5L`, Adar I of a Hebrew year (`month_from_text/1`). Limit. In a year that has no such month it is passed over, or with `:skip` is the month before it (`:backward`) or after it (`:forward`).

  * `:bymonthday` — list of integers -31..31 (negatives count from
    the end of the month). Limit or expand per FREQ.

  * `:byyearday` — list of integers -366..366. Limit or expand
    per FREQ.

  * `:byweekno` — list of integers -53..53. Used only with
    `:yearly` FREQ. Limit or expand.

  * `:byday` — list of `{ordinal_or_nil, weekday_1_to_7}` tuples.
    With MONTHLY / YEARLY and no BYWEEKNO, ordinals select the
    Nth/-Nth weekday within the period. With other FREQs,
    ordinals are ignored (filter only).

  * `:byhour` / `:byminute` / `:bysecond` — lists of integers.
    Limit or expand per FREQ.

  * `:bysetpos` — list of integers; applied last to pick the Nth
    element of the per-period candidate set.

  * `:byyear` — list of absolute years. A non-standard extension
    (RFC 5545 has no `BYYEAR`); used by `Tempo.Cron` to honour a
    cron year field such as `2025,2027,2029`. It becomes a year in
    the selection, which keeps only the periods in a listed year.

  * `:bymonthday_nearest` — list of `pos_integer()` days or the
    atom `:last`. A non-standard extension carrying the cron `W`
    (nearest-weekday) modifier: `15W` becomes `[15]`, `LW` becomes
    `[:last]`. Each target snaps to the nearest weekday within the
    same month (Saturday → Friday, Sunday → Monday), never crossing
    a month boundary, so `1W` on a Saturday lands on the 3rd.

  * `:bymonthday_or_byday` — a `{monthdays, byday_entries}` tuple. A
    non-standard extension carrying POSIX cron's day-of-month **OR**
    day-of-week union: when both fields are restricted (`13 * 5` —
    "the 13th *or* any Friday"), a candidate is kept if its day is in
    `monthdays` **or** its weekday matches `byday_entries`. Unlike the
    AND-composing `:bymonthday` + `:byday`, which would select only
    Friday-the-13ths.

  """

  alias Tempo.Calendars
  alias Tempo.Iso8601.Parser
  alias Tempo.Iso8601.Unit
  alias Tempo.UnitValues
  alias Tempo.Validation

  @type frequency :: :second | :minute | :hour | :day | :week | :month | :year
  @type weekday :: 1..7

  @typedoc """
  A month a rule names: its number, or a leap month as the month it follows (`{5, :leap}`, RFC 7529's `5L`).
  """
  @type month :: integer() | {pos_integer(), :leap}
  @type byday_entry :: {integer() | nil, weekday()}

  @type t :: %__MODULE__{
          freq: frequency(),
          interval: pos_integer(),
          count: pos_integer() | nil,
          until: Tempo.t() | nil,
          wkst: weekday(),
          skip: :omit | :backward | :forward,
          rscale: module() | nil,
          bymonth: [month()] | nil,
          bymonthday: [integer()] | nil,
          byyearday: [integer()] | nil,
          byweekno: [integer()] | nil,
          byday: [byday_entry()] | nil,
          byhour: [non_neg_integer()] | nil,
          byminute: [non_neg_integer()] | nil,
          bysecond: [non_neg_integer()] | nil,
          bysetpos: [integer()] | nil,
          byyear: [integer()] | nil,
          bymonthday_nearest: [pos_integer() | :last] | nil,
          bymonthday_or_byday: {[integer()], [byday_entry()]} | nil
        }

  defstruct freq: nil,
            interval: 1,
            count: nil,
            until: nil,
            wkst: 1,
            skip: :omit,
            rscale: nil,
            bymonth: nil,
            bymonthday: nil,
            byyearday: nil,
            byweekno: nil,
            byday: nil,
            byhour: nil,
            byminute: nil,
            bysecond: nil,
            bysetpos: nil,
            byyear: nil,
            bymonthday_nearest: nil,
            bymonthday_or_byday: nil

  @doc false
  # An occurrence of a rule is as long as its start is precise: a day for a
  # date, an hour for a time written to the hour. A rule that makes points in
  # its period (a day it states, a time of day) is given their length where
  # it is resolved (`Tempo.RRule.Selection`). One that makes none, having no
  # part or only parts that keep or drop its periods, would run a whole
  # cadence, as an ISO 8601 recurrence's occurrences do. So where its start
  # is written finer than it steps, it is given the length here: a daily rule
  # from 10:00 is the hour from 10:00 each day (decided 2026-10-09, user). It
  # was a day long, where a weekly or a monthly rule from the same start,
  # which takes a part from it, was an hour.
  #
  # A start as coarse as the step, or coarser, is the step's own length: an
  # hourly rule from a date is an hour of it. One given a length by its
  # caller (`:duration`, `:base_to`) keeps that.
  @spec as_long_as_its_start(map(), frequency(), Tempo.t() | nil, boolean()) :: map()
  def as_long_as_its_start(metadata, frequency, %Tempo{} = start, false = _makes_points?)
      when not is_map_key(metadata, :occurrence_duration) and
             not is_map_key(metadata, :occurrence_base_to) do
    with {unit, _span} <- Tempo.resolution(start),
         {:ok, unit} <- unit_of_a_length(unit),
         :lt <- Unit.compare(unit, frequency) do
      Map.put(metadata, :occurrence_duration, %Tempo.Duration{time: [{unit, 1}]})
    else
      _as_long_as_it_steps -> metadata
    end
  end

  def as_long_as_its_start(metadata, _frequency, _start, _makes_points?), do: metadata

  # The unit a start is precise to, as the unit of a length: a day however
  # it is counted. A start precise to a fraction of a second, or to no unit
  # a length is counted in, leaves its rule's occurrences as long as it steps.
  defp unit_of_a_length(unit) when unit in [:year, :month, :week, :day, :hour, :minute, :second],
    do: {:ok, unit}

  defp unit_of_a_length(unit) when unit in [:day_of_week, :day_of_year], do: {:ok, :day}
  defp unit_of_a_length(_other), do: :error

  @doc """
  Reads a month as a rule writes it.

  RFC 7529 writes a leap month as the number of the month it follows and an `L`, and RFC 8984 as the same in a string: `5L` is the leap month after the fifth, Adar I of a Hebrew year.

  ### Arguments

  * `text` is the month as it is written, `"5"` or `"5L"`.

  ### Returns

  * `{:ok, month}`, the month's number, or `{number, :leap}` for a leap month.

  * `:error` for what is no month.

  ### Examples

      iex> Tempo.RRule.Rule.month_from_text("5")
      {:ok, 5}

      iex> Tempo.RRule.Rule.month_from_text("5L")
      {:ok, {5, :leap}}

      iex> Tempo.RRule.Rule.month_from_text("L5")
      :error

  """
  @spec month_from_text(String.t()) :: {:ok, month()} | :error
  def month_from_text(text) when is_binary(text) do
    case Integer.parse(text) do
      {number, ""} -> {:ok, number}
      {number, leap} when leap in ["L", "l"] and number > 0 -> {:ok, {number, :leap}}
      _no_month -> :error
    end
  end

  def month_from_text(_other), do: :error

  @doc """
  Returns whether the leap months a rule names are ones its calendar can have.

  A leap month is a month of the calendar an `RSCALE` names, so one in a rule that names no calendar, or a calendar whose years all have the same months, is reported and not read as a month it is not. With `:skip` `:forward` a leap month a year lacks is the month after it, and after a year's last month that is a month of the next year, which is not built.

  ### Arguments

  * `rule` is a `t:t/0`.

  ### Returns

  * `:ok` for a rule that names no leap month, and for one whose calendar has leap months.

  * `{:error, {:leap_month_without_rscale, month}}` for a leap month in a rule that names no calendar.

  * `{:error, {:calendar_has_no_leap_month, {month, calendar}}}` for one in a calendar whose years all have the same months.

  * `{:error, {:unsupported_skip, {:forward, [bymonth: months]}}}` for a leap month after the last month of a year, in a rule whose `:skip` is `:forward`.

  ### Examples

      iex> rule = %Tempo.RRule.Rule{freq: :year, rscale: Calendrical.Hebrew, bymonth: [{5, :leap}]}
      iex> Tempo.RRule.Rule.leap_months_built(rule)
      :ok

      iex> Tempo.RRule.Rule.leap_months_built(%Tempo.RRule.Rule{freq: :year, bymonth: [{5, :leap}]})
      {:error, {:leap_month_without_rscale, {5, :leap}}}

      iex> rule = %Tempo.RRule.Rule{freq: :year, rscale: Calendrical.Persian, bymonth: [{5, :leap}]}
      iex> Tempo.RRule.Rule.leap_months_built(rule)
      {:error, {:calendar_has_no_leap_month, {{5, :leap}, Calendrical.Persian}}}

  """
  @spec leap_months_built(t()) ::
          :ok
          | {:error, {:leap_month_without_rscale, month()}}
          | {:error, {:calendar_has_no_leap_month, {month(), module()}}}
          | {:error, {:unsupported_skip, {:forward, keyword()}}}
  def leap_months_built(%__MODULE__{bymonth: months, rscale: calendar, skip: skip}) do
    case Enum.filter(List.wrap(months), &leap_month?/1) do
      [] -> :ok
      [leap | _rest] = leap_months -> leap_months_in(calendar, leap, leap_months, skip)
    end
  end

  defp leap_month?({_month, :leap}), do: true
  defp leap_month?(_month), do: false

  defp leap_months_in(nil, leap, _leap_months, _skip),
    do: {:error, {:leap_month_without_rscale, leap}}

  defp leap_months_in(calendar, leap, leap_months, skip) do
    case UnitValues.in_any_year(:month, [], calendar) do
      {:ok, %Range{last: every_year}, %Range{last: most}} when most > every_year ->
        moved_within_the_year(leap_months, every_year, skip)

      _the_same_months_every_year ->
        {:error, {:calendar_has_no_leap_month, {leap, calendar}}}
    end
  end

  # The month after a leap month that follows a year's last is the first of
  # the next year, where the rule's period for the year has no month to give.
  defp moved_within_the_year(leap_months, last_month, :forward) do
    case Enum.filter(leap_months, fn {month, :leap} -> month >= last_month end) do
      [] -> :ok
      after_the_last -> {:error, {:unsupported_skip, {:forward, [bymonth: after_the_last]}}}
    end
  end

  defp moved_within_the_year(_leap_months, _last_month, _skip), do: :ok

  @doc """
  Returns the calendar a rule's `RSCALE` names.

  RFC 7529's `RSCALE`, and JSCalendar's `rscale` (RFC 8984 §4.3.3), name the calendar a rule counts its months and its days in by its CLDR calendar name, in any case: `HEBREW`, `islamic-civil`, `chinese`. It is one of the notations that carry a calendar's name by definition, and is resolved to the calendar module where the rule is read.

  ### Arguments

  * `name` is the calendar's name as the rule writes it, or `nil` for a rule that names none.

  ### Returns

  * `{:ok, calendar}`, a calendar module, and `{:ok, nil}` for no name: the rule is counted in the calendar of its start.

  * `{:error, {:unsupported_rscale, name}}` for a name that is no calendar's.

  ### Examples

      iex> Tempo.RRule.Rule.calendar_from_rscale("HEBREW")
      {:ok, Calendrical.Hebrew}

      iex> Tempo.RRule.Rule.calendar_from_rscale("islamic-civil")
      {:ok, Calendrical.Islamic.Civil}

      iex> Tempo.RRule.Rule.calendar_from_rscale(nil)
      {:ok, nil}

      iex> Tempo.RRule.Rule.calendar_from_rscale("KLINGON")
      {:error, {:unsupported_rscale, "KLINGON"}}

  """
  @spec calendar_from_rscale(String.t() | nil) ::
          {:ok, module() | nil} | {:error, {:unsupported_rscale, term()}}
  def calendar_from_rscale(nil), do: {:ok, nil}

  def calendar_from_rscale(name) when is_binary(name) do
    case Calendrical.calendar_from_cldr_calendar_type(String.downcase(name)) do
      {:ok, calendar} -> {:ok, calendar}
      {:error, _unknown_calendar} -> {:error, {:unsupported_rscale, name}}
    end
  end

  def calendar_from_rscale(other), do: {:error, {:unsupported_rscale, other}}

  @doc """
  Brings a rule's start into the calendar the rule is counted in.

  A rule that names a calendar (`:rscale`) counts its months and its days from its start's date in that calendar: a yearly rule in the Hebrew calendar from 2 April 2026 is from 15 Nisan 5786. A time of day and a zone stay as they are.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `start` is the rule's start, a `t:Tempo.t/0`, or `nil`.

  ### Returns

  * `{:ok, start}`, in the rule's calendar, or as it was for a rule that names none and for no start.

  * `{:error, {:from_is_no_date, start}}` for a start that is no date, a month or a time of day alone, which has no place in another calendar.

  ### Examples

      iex> rule = %Tempo.RRule.Rule{freq: :year, rscale: Calendrical.Hebrew}
      iex> {:ok, start} = Tempo.RRule.Rule.start_in_rscale(rule, ~o"2026-04-02")
      iex> Tempo.to_iso8601!(start)
      "5786Y7M15D[u-ca=hebrew]"

      iex> Tempo.RRule.Rule.start_in_rscale(%Tempo.RRule.Rule{freq: :year}, ~o"2026-04-02")
      {:ok, ~o"2026-04-02"}

  """
  @spec start_in_rscale(t(), Tempo.t() | nil) ::
          {:ok, Tempo.t() | nil} | {:error, {:from_is_no_date, Tempo.t()}}
  def start_in_rscale(%__MODULE__{rscale: nil}, start), do: {:ok, start}
  def start_in_rscale(%__MODULE__{}, nil), do: {:ok, nil}

  def start_in_rscale(%__MODULE__{rscale: calendar}, %Tempo{calendar: calendar} = start),
    do: {:ok, start}

  def start_in_rscale(%__MODULE__{rscale: calendar}, %Tempo{} = start) do
    case Tempo.to_calendar(start, calendar) do
      {:ok, %Tempo{} = in_calendar} -> {:ok, in_calendar}
      {:error, _no_date} -> {:error, {:from_is_no_date, start}}
    end
  end

  @doc """
  Does the rule include any `BY*` modifier?

  `true` when any `BY*` field is non-nil. Used by the expander to
  skip the BY-rule pipeline entirely for simple FREQ-only rules.

  ### Examples

      iex> Tempo.RRule.Rule.has_by_rules?(%Tempo.RRule.Rule{freq: :weekly})
      false

      iex> Tempo.RRule.Rule.has_by_rules?(%Tempo.RRule.Rule{freq: :weekly, byday: [{nil, 1}]})
      true

  """
  @spec has_by_rules?(t()) :: boolean()
  def has_by_rules?(%__MODULE__{} = rule) do
    Enum.any?(
      [
        rule.bymonth,
        rule.bymonthday,
        rule.byyearday,
        rule.byweekno,
        rule.byday,
        rule.byhour,
        rule.byminute,
        rule.bysecond,
        rule.bysetpos,
        rule.bymonthday_nearest,
        rule.bymonthday_or_byday,
        rule.byyear
      ],
      &(&1 != nil)
    )
  end

  @doc """
  Project a rule's `BY*` filters onto the `%Tempo{}` selection carried in a
  recurring interval's `:repeat_rule`.

  This is the single source of truth for the RRULE/cron → selection mapping:
  both `Tempo.RRule.parse/2` (over a parsed keyword list) and
  `Tempo.RRule.Expander` (over a `%Rule{}`) build their selection here, so the
  token vocabulary above cannot drift between the two paths.

  The `BY*` filters are pushed coarsest-to-finest and the list is consolidated
  (consecutive integers collapse to ranges) so the selection serialises to a
  re-parseable ISO 8601 form. `byday` precedes the time elements because a
  weekday after `T…H…M` is out of resolution order and will not round-trip.

  An ordinal weekday on one weekday (`BYDAY=2FR`) becomes a weekday and a position (`5K2I`), and a position applies last within a selection, so the hours, minutes and seconds the rule names follow the selection instead of joining it: `BYDAY=2FR;BYHOUR=9` is `L5K2INT9H`, as ISO 8601-2 §12.9 writes 09:00 on the second Tuesday. Beside a `BYSETPOS`, which takes the selection's one position, the ordinal stays an RRULE-only `:byday`, as it does where a position would count something else: beside a `BYMONTHDAY`, a `BYYEARDAY` or a `BYWEEKNO`, which narrow what a position counts, and in a yearly rule of several months, where an ordinal counts in each.

  A rule takes from its start what it does not say, and ISO 8601-2 (Annex C.3 and C.4) has a conversion state each part explicitly. With a start that is a calendar date, a WEEKLY rule with no `BYDAY` selects its start's weekday, a MONTHLY rule with no `BYMONTHDAY` and no `BYDAY` its start's day of the month, and a YEARLY rule with no `BYYEARDAY` its start's month and day of the month, or with `BYWEEKNO` its start's weekday. A day so stated is passed over in a month that lacks it, as RFC 5545 §3.3.10 passes over an instance with an invalid date: a MONTHLY rule from 31 January lists the months of 31 days. The month is stated for a start in the Gregorian calendar alone, since the step from year to year keeps a month that a leap month renumbers. A rule whose `:skip` is `:backward` states no day of the month and no month, and keeps the last day of a period that lacks its start's. One whose `:skip` moves a day it states, `:forward` or a day the rule writes, holds the skip in its selection (`:skip`), which has no ISO 8601 form. Without a start a rule states nothing: a `BYWEEKNO` rule keeps every day of its weeks.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `dtstart` is the rule's start as a `t:Tempo.t/0`, or `nil` when it has
    none. The default is `nil`.

  ### Returns

  * A `%Tempo{}` carrying `[selection: …]`, followed by an ordinal weekday's times when it has them, or `nil` when the rule has no `BY*` filter, takes none from its start and has a default `WKST` (the simple recurrence needs no repeat rule).

  ### Examples

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :month, byday: [{2, 1}]})
      ~o"L1K2IN"

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :day})
      nil

      iex> rule = %Tempo.RRule.Rule{freq: :year, byweekno: [20]}
      iex> Tempo.RRule.Rule.to_selection(rule, ~o"1997-05-12")
      ~o"L20W1KN"

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :month}, ~o"2026-01-31")
      ~o"L31DN"

      iex> Tempo.RRule.Rule.to_selection(%Tempo.RRule.Rule{freq: :year}, ~o"2026-03-10")
      ~o"L3M10DN"

  """
  @spec to_selection(t(), Tempo.t() | nil) :: Tempo.t() | nil
  def to_selection(%__MODULE__{} = rule, dtstart \\ nil) do
    rule = with_parts_of_start(rule, dtstart)

    if has_by_rules?(rule) or non_default_wkst?(rule) do
      selection =
        []
        |> push_by(rule.byyear, :year)
        |> push_by(rule.bymonth, month_unit(rule.rscale))
        |> push_by(rule.bymonthday, :day)
        |> push_by(rule.bymonthday_nearest, :nearest_weekday)
        |> push_or_day(rule.bymonthday_or_byday)
        |> push_by(rule.byyearday, :day_of_year)
        |> push_by(rule.byweekno, :week)
        |> push_byday(rule.byday, position_of_numbered_weekday(rule))
        |> push_times(rule, not times_after_selection?(rule))
        |> push_by(rule.bysetpos, :instance)
        |> push_skip(rule, rule.rscale || calendar_of_start(dtstart))
        |> push_wkst(rule.wkst)
        |> Enum.reverse()
        |> Parser.consolidate_selection()

      units =
        []
        |> push_times(rule, times_after_selection?(rule))
        |> Enum.reverse()
        |> Parser.consolidate_selection()

      %Tempo{
        time: [{:selection, selection} | units],
        calendar: Calendars.effective(rule.rscale)
      }
    end
  end

  # RFC 7529 numbers a month as its calendar names it, a leap month taking
  # the number of the month it follows: Nisan is month 7 of every Hebrew
  # year. That is the traditional month (`m`) in a calendar whose years
  # differ in their months, and the month in order (`M`) in every other,
  # where the two are one.
  defp month_unit(nil), do: :month

  defp month_unit(calendar) do
    case UnitValues.in_any_year(:month, [], calendar) do
      {:ok, %Range{last: every_year}, %Range{last: most}} when most > every_year ->
        :traditional_month

      _the_same_months_every_year ->
        :month
    end
  end

  # Whether an ordinal weekday's position picks the day before its times
  # refine it, so the times follow the selection.
  defp times_after_selection?(%__MODULE__{} = rule) do
    position_of_numbered_weekday(rule) != nil and
      Enum.any?([rule.byhour, rule.byminute, rule.bysecond], &(&1 not in [nil, []]))
  end

  defp push_times(acc, rule, true) do
    acc
    |> push_by(rule.byhour, :hour)
    |> push_by(rule.byminute, :minute)
    |> push_by(rule.bysecond, :second)
  end

  defp push_times(acc, _rule, false), do: acc

  defp non_default_wkst?(%__MODULE__{wkst: wkst}) when is_integer(wkst) and wkst != 1, do: true
  defp non_default_wkst?(_rule), do: false

  # ISO 8601-2 Annex C.3 lists what RFC 5545 takes from the start of a rule
  # that does not say it, and Annex C.4 has a conversion state each one: the
  # weekday of a WEEKLY rule with no BYDAY, the day of the month of a MONTHLY
  # rule with no BYMONTHDAY and no BYDAY, and for a YEARLY rule with no
  # BYYEARDAY its month, its day of the month and, with BYWEEKNO, its weekday.
  # A part so stated selects as one the rule wrote does, so a day of the
  # month that a month lacks is passed over, as RFC 5545 §3.3.10 passes over
  # an instance with an invalid date: FREQ=MONTHLY from 31 January lists the
  # months of 31 days. A start that is no one calendar date states nothing.
  defp with_parts_of_start(%__MODULE__{} = rule, %Tempo{time: time} = dtstart) do
    case Enum.map([:year, :month, :day], &Keyword.get(time, &1)) do
      [year, month, day] when is_integer(year) and is_integer(month) and is_integer(day) ->
        with_parts_of(rule, month, day, dtstart)

      _no_one_date ->
        rule
    end
  end

  defp with_parts_of_start(rule, _no_start), do: rule

  defp with_parts_of(%__MODULE__{freq: :week} = rule, _month, _day, dtstart) do
    if names_weekday?(rule), do: rule, else: with_weekday_of(rule, dtstart)
  end

  defp with_parts_of(%__MODULE__{freq: :month} = rule, _month, day, _dtstart) do
    if names_day_of_month?(rule) or names_weekday?(rule) or keeps_last_day?(rule),
      do: rule,
      else: %{rule | bymonthday: [day]}
  end

  defp with_parts_of(%__MODULE__{freq: :year, byyearday: days} = rule, month, day, dtstart)
       when days in [nil, []] do
    rule
    |> with_month_of_start(rule, month, dtstart)
    |> with_day_of_start(rule, day, dtstart)
  end

  defp with_parts_of(rule, _month, _day, _dtstart), do: rule

  # "If no BYMONTH or BYWEEKNO parameter is set: if the BYMONTHDAY parameter
  # is provided, then the BYMONTH selection is inherited from the calendar
  # month of year value from the initial start date; if the BYDAY parameter
  # is not set, then the BYMONTH selection is inherited" (Annex C.3). What
  # the rule wrote is asked of `written`, the rule before any part was added.
  #
  # The month is RFC 5545's, a month of the Gregorian calendar, and is
  # written for a start in that calendar alone. In another the step from year
  # to year keeps the start's month as the calendar does, and a BYMONTH,
  # which numbers a month by its place in the year, would not: Nisan is the
  # seventh month of a Hebrew year and the eighth of one with a leap month.
  #
  # A rule that names its calendar (RFC 7529's `RSCALE`) takes its start's
  # month as that calendar names it, and where the start is in a leap month
  # the month is the leap month (`5L`, Adar I): a year that has none has no
  # such date, and is passed over or takes the month the rule's `SKIP` moves
  # it to. The step from year to year gave that year the month in the leap
  # month's place, as `SKIP=FORWARD` does, whatever the rule's `SKIP`.
  defp with_month_of_start(rule, written, month, %Tempo{calendar: calendar})
       when calendar in [Calendrical.Gregorian, Calendar.ISO, nil] do
    if takes_month_of_start?(written) and not keeps_last_day?(written),
      do: %{rule | bymonth: [month]},
      else: rule
  end

  defp with_month_of_start(
         %__MODULE__{rscale: calendar} = rule,
         written,
         month,
         %Tempo{calendar: calendar, time: time}
       ) do
    with true <- takes_month_of_start?(written),
         {:ok, {_follows, :leap} = leap_month} <-
           Validation.traditional_month_from_ordinal(calendar, Keyword.get(time, :year), month) do
      %{rule | bymonth: [leap_month]}
    else
      _a_month_of_every_year_or_one_the_rule_states -> rule
    end
  end

  defp with_month_of_start(rule, _written, _month, _dtstart), do: rule

  defp takes_month_of_start?(written) do
    empty?(written.bymonth) and empty?(written.byweekno) and
      (names_day_of_month?(written) or not names_weekday?(written))
  end

  # "If no BYMONTHDAY, BYWEEKNO or BYDAY parameter is set, the BYMONTHDAY
  # selection is inherited from the calendar day of month of the initial start
  # date. If there is a BYWEEKNO parameter set but no BYMONTHDAY or BYDAY, the
  # BYDAY selection is inherited from the calendar day of week" (Annex C.3).
  defp with_day_of_start(rule, written, day, dtstart) do
    cond do
      names_day_of_month?(written) or names_weekday?(written) -> rule
      not empty?(written.byweekno) -> with_weekday_of(rule, dtstart)
      keeps_last_day?(written) -> rule
      true -> %{rule | bymonthday: [day]}
    end
  end

  # A rule that keeps the last day of a period without its start's day
  # (`skip: :backward`) leaves the day, and the month it is in, to the step
  # from its start, which the calendar's own arithmetic takes to that day.
  defp keeps_last_day?(%__MODULE__{skip: skip}), do: skip == :backward

  # The weekday is Monday 1 to Sunday 7, as BYDAY numbers it.
  defp with_weekday_of(rule, dtstart),
    do: %{rule | byday: [{nil, Tempo.day_of_week(dtstart, :monday)}]}

  # A cron day of the month that is the nearest weekday, or a day of the
  # month or of the week, names its day as BYMONTHDAY and BYDAY do.
  defp names_day_of_month?(%__MODULE__{} = rule) do
    not (empty?(rule.bymonthday) and empty?(rule.bymonthday_nearest) and
           empty?(rule.bymonthday_or_byday))
  end

  defp names_weekday?(%__MODULE__{} = rule),
    do: not (empty?(rule.byday) and empty?(rule.bymonthday_or_byday))

  defp empty?(part), do: part in [nil, []]

  defp push_by(acc, nil, _unit), do: acc
  defp push_by(acc, [], _unit), do: acc
  defp push_by(acc, [single], unit), do: [{unit, single} | acc]
  defp push_by(acc, list, unit) when is_list(list), do: [{unit, list} | acc]

  defp push_or_day(acc, nil), do: acc

  defp push_or_day(acc, {monthdays, byday_entries}) do
    [{:or_day, {List.wrap(monthdays), List.wrap(byday_entries)}} | acc]
  end

  # BYDAY lowers to ISO 8601-2 §12.9 selection where it can:
  #
  #   * every entry a bare weekday → `{:day_of_week, …}`;
  #   * ordinals all on ONE weekday (`2MO`, `1MO,3MO`) → `{:day_of_week, d}` +
  #     `{:instance, ords}` (weekday then position, the ISO order — `day_of_week`
  #     is prepended after `:instance` so it lands first once the list reverses),
  #     where the two say the same (`position_of_numbered_weekday/1`);
  #   * ordinals across DISTINCT weekdays (`2MO,2WE`, `1MO,-1FR`, mixed) have no
  #     single-position ISO form, so they stay `{:byday, entries}` (RRULE-only);
  #   * an ordinal beside a BYSETPOS, which takes the selection's one position,
  #     and one beside a part that narrows what a position counts, stay
  #     `{:byday, entries}` too.
  defp push_byday(acc, nil, _position), do: acc
  defp push_byday(acc, [], _position), do: acc

  defp push_byday(acc, entries, position) when is_list(entries) do
    cond do
      Enum.all?(entries, fn {ordinal, _day} -> is_nil(ordinal) end) ->
        push_day_of_week(acc, Enum.map(entries, fn {nil, day} -> day end))

      position != nil ->
        {day, ordinals} = position
        [{:instance, ordinals}, {:day_of_week, day} | acc]

      true ->
        [{:byday, entries} | acc]
    end
  end

  # The weekday and the positions a rule's numbered weekday is written as
  # (`2MO` as `1K2I`), or `nil` where the rule has none on one weekday, has a
  # BYSETPOS for the selection's one position, or would not say the same
  # (`numbered_weekday_is_position?/3`).
  defp position_of_numbered_weekday(%__MODULE__{byday: [_ | _] = byday, bysetpos: nil} = rule) do
    if numbered_weekday_is_position?(rule.freq, rule.bymonth, names_another_day?(rule)),
      do: single_weekday_ordinals(byday)
  end

  defp position_of_numbered_weekday(_rule), do: nil

  defp names_another_day?(%__MODULE__{} = rule) do
    names_day_of_month?(rule) or not (empty?(rule.byyearday) and empty?(rule.byweekno))
  end

  @doc false
  # Whether a numbered weekday (`BYDAY=2MO`) and the weekday with a position
  # (`1K2I`, `BYDAY=MO;BYSETPOS=2`) say the same in a rule. A number counts
  # the weekdays of a month, or of a year that names no month, and a position
  # counts what the rule's other parts leave of its period's set. So they
  # differ where the rule names another day — a day of the month or of the
  # year, a week — which narrows the set before the position counts (the
  # 15th that is a first Monday is no day, where the first of the 15ths that
  # are Mondays is one), and in a yearly rule of several months, where a
  # number counts in each month and a position across them all.
  @spec numbered_weekday_is_position?(frequency() | nil, term(), boolean()) :: boolean()
  def numbered_weekday_is_position?(frequency, months, names_another_day?) do
    not names_another_day? and not (frequency == :year and several?(months))
  end

  # Months as a rule lists them, or as a selection holds them: one number,
  # or a list of numbers and ranges.
  defp several?(months) do
    case months |> List.wrap() |> Enum.flat_map(&each_month/1) do
      [_first, _second | _rest] -> true
      _one_or_none -> false
    end
  end

  defp each_month(%Range{} = months), do: Enum.to_list(months)
  defp each_month(month), do: [month]

  # `{day, ordinals}` when every entry carries a non-nil ordinal on a single
  # distinct weekday; `nil` otherwise. One ordinal collapses to an integer.
  defp single_weekday_ordinals(entries) do
    days = entries |> Enum.map(fn {_ordinal, day} -> day end) |> Enum.uniq()
    ordinals = Enum.map(entries, fn {ordinal, _day} -> ordinal end)

    if match?([_], days) and Enum.all?(ordinals, &(not is_nil(&1))) do
      {hd(days), collapse_single(ordinals)}
    end
  end

  defp collapse_single([one]), do: one
  defp collapse_single(many), do: many

  defp push_day_of_week(acc, [single]), do: [{:day_of_week, single} | acc]
  defp push_day_of_week(acc, days), do: [{:day_of_week, days} | acc]

  # A rule's `:skip` is written into its selection where it moves a day: in
  # a monthly or a yearly rule that states a day of the month some month
  # lacks. Anywhere else it changes nothing, and the rule is the one without
  # it. `:backward` with no day stated keeps a month's last day by the step
  # from its start (`keeps_last_day?/1`), and holds no day here to move.
  #
  # It is written too where the rule names a leap month, which a year that
  # has none moves to the month before it or after it (RFC 7529 §4.1).
  defp push_skip(acc, %__MODULE__{skip: skip} = rule, calendar)
       when skip in [:backward, :forward] do
    if moves_a_day?(rule, calendar) or Enum.any?(List.wrap(rule.bymonth), &leap_month?/1),
      do: [{:skip, skip} | acc],
      else: acc
  end

  defp push_skip(acc, _rule, _calendar), do: acc

  # Whether a rule states a day of the month that some month of its calendar
  # may lack, counted from either end. In the Gregorian calendar that is a
  # day past the 28th. Twenty-eight was taken for every calendar's, so the
  # sixth day of an Ethiopic year's thirteenth month, which has five days or
  # six, was not moved. How many days every month of another calendar has is
  # that calendar's to say, and Calendrical has no one answer for it, so
  # there a skip is written beside any day of the month: each month is asked
  # its own days where the rule is resolved, and the skip changes nothing in
  # a month that has the day.
  defp moves_a_day?(%__MODULE__{freq: freq, bymonthday: days}, calendar)
       when freq in [:month, :year] and calendar in [Calendrical.Gregorian, Calendar.ISO],
       do: Enum.any?(List.wrap(days), &(abs(&1) > 28))

  defp moves_a_day?(%__MODULE__{freq: freq, bymonthday: days}, _another_calendar)
       when freq in [:month, :year],
       do: List.wrap(days) != []

  defp moves_a_day?(_rule, _calendar), do: false

  defp calendar_of_start(%Tempo{calendar: calendar}) when not is_nil(calendar), do: calendar
  defp calendar_of_start(_no_start), do: Calendars.default()

  # Only emit `{:wkst, n}` for a non-default week start (WKST=MO is 1); the
  # common case keeps the AST identical and the token signals intent.
  defp push_wkst(acc, wkst) when is_integer(wkst) and wkst in 2..7, do: [{:wkst, wkst} | acc]
  defp push_wkst(acc, _wkst), do: acc
end
