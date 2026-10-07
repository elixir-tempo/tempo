defmodule Tempo.Explanation do
  @moduledoc """
  A structured explanation of a Tempo value.

  Produced by `Tempo.Explain.explain/1`. Consists of a `:kind`
  classifier and an ordered list of `{tag, text}` parts. The tag
  lets renderers (plain terminal, ANSI colour, HTML) style each
  part semantically without re-parsing the
  prose.

  ### Fields

  * `:kind` — a classifier atom (e.g. `:anchored`,
    `:masked`, `:duration`, `:interval_set`).

  * `:parts` — a list of `{tag :: atom(), text :: String.t()}`
    tuples. Common tags:

    * `:headline` — one-line description of what this value is.
    * `:span` — bounded interval in `[from, to)` form.
    * `:margin` — `±` uncertainty margin and the span its groundings cover.
    * `:qualification` — EDTF qualifier description.
    * `:extended` — IXDTF zone and offset.
    * `:calendar` — non-default calendar.
    * `:enumeration` — iteration granularity.
    * `:hint` — pointer to relevant function.
    * `:metadata` — user metadata on an interval.
    * `:member` — list-of-members preview for sets.

  """

  @type t :: %__MODULE__{
          kind: atom(),
          parts: [{atom(), String.t()}]
        }

  defstruct [:kind, parts: []]
end

defmodule Tempo.Explain do
  import Kernel, except: [to_string: 1]

  @moduledoc """
  Plain-English explanations of Tempo values, in a form renderers
  can style.

  `Tempo.Explain.explain/1` returns a `t:Tempo.Explanation.t/0`
  with semantic part tags. Three formatters produce output for
  different surfaces:

  * `to_string/1` — plain multi-line text. Default for iex.
  * `to_ansi/1` — ANSI-coloured for terminals.
  * `to_iodata/1` — tagged iodata for HTML renderers.

  `Tempo.explain/1` delegates here with a `to_string/1` formatter —
  the most common case for interactive use.

  ## Example

      iex> Tempo.Explain.explain(~o"156X").kind
      :masked

      iex> Tempo.Explain.explain(~o"156X").parts
      ...> |> Enum.map(&elem(&1, 0))
      [:headline, :span, :enumeration, :hint]

  """

  alias Tempo.Enumeration
  alias Tempo.Event
  alias Tempo.Explanation
  alias Tempo.IntervalSet
  alias Tempo.Iso8601.Unit
  alias Tempo.Mask
  alias Tempo.Qualification
  alias Tempo.RecurrenceSet
  alias Tempo.RecurrenceSet.Conditional
  alias Tempo.RRule.Selection
  alias Tempo.UnitValues
  alias Tempo.Validation

  @doc """
  Return a structured `t:Tempo.Explanation.t/0` for any Tempo
  value. Unknown shapes produce a generic fallback rather than
  raising.
  """
  @spec explain(term()) :: Explanation.t()
  def explain(%Tempo{calendar: nil} = value), do: explain(Tempo.with_a_calendar(value))

  def explain(value) do
    value = as_resolved(value)
    %Explanation{kind: classify(value), parts: explain_parts(value)}
  end

  # A selection is worded as it is resolved: a day with no month, selected in
  # a year, is a day of the year. A selection alone has no period until it is
  # paired with one, and is worded as it is written.
  defp as_resolved(%Tempo{time: [{:selection, _selection} | _units]} = selection), do: selection
  defp as_resolved(value), do: Selection.read_in_its_period(value)

  @doc """
  Render an explanation as plain multi-line text.

  ### Examples

      iex> Tempo.Explain.explain(~o"2022Y") |> Tempo.Explain.to_string()
      "The year 2022.\\nSpan: [2022-01-01, 2023-01-01).\\nIterates at :month granularity.\\nConvert it to an interval with `Tempo.to_interval/1`."

  """
  @spec to_string(Explanation.t()) :: String.t()
  def to_string(%Explanation{parts: parts}) do
    Enum.map_join(parts, "\n", fn {_tag, text} -> text end)
  end

  @doc """
  Render an explanation with ANSI colour codes, suitable for a
  terminal that supports them.

  The colour mapping is deliberate: headlines are bright, spans
  are cyan (technical detail), qualifications and metadata are
  yellow (notable), hints are dim.
  """
  @spec to_ansi(Explanation.t()) :: String.t()
  def to_ansi(%Explanation{parts: parts}) do
    # `emit?` forced to true — callers that want unconditional
    # ANSI get it. For terminal-aware emission the caller should
    # gate on `IO.ANSI.enabled?/0` themselves.
    parts
    |> Enum.map(&ansi_for/1)
    |> Enum.intersperse("\n")
    |> IO.ANSI.format(true)
    |> IO.iodata_to_binary()
  end

  defp ansi_for({:headline, text}), do: [:bright, text, :reset]
  defp ansi_for({:span, text}), do: [:cyan, text, :reset]
  defp ansi_for({:margin, text}), do: [:yellow, text, :reset]
  defp ansi_for({:qualification, text}), do: [:yellow, text, :reset]
  defp ansi_for({:extended, text}), do: [:yellow, text, :reset]
  defp ansi_for({:calendar, text}), do: [:magenta, text, :reset]
  defp ansi_for({:enumeration, text}), do: [:green, text, :reset]
  defp ansi_for({:hint, text}), do: [:faint, text, :reset]
  defp ansi_for({:metadata, text}), do: [:yellow, text, :reset]
  defp ansi_for({:member, text}), do: [:cyan, text, :reset]
  defp ansi_for({_tag, text}), do: [text]

  @doc """
  Render as tagged iodata `[{tag, text}, ...]`, ready for an HTML
  renderer to style each part by its tag.

  Each element is a 2-tuple; no string concatenation happens here.
  Callers decide how to separate parts (newlines, `<div>`s, etc.).
  """
  @spec to_iodata(Explanation.t()) :: [{atom(), String.t()}]
  def to_iodata(%Explanation{parts: parts}), do: parts

  ## ------------------------------------------------------------
  ## Classification
  ## ------------------------------------------------------------

  defp classify(%Tempo{time: time}) do
    cond do
      has_mask?(time) -> :masked
      only_time_of_day?(time) -> :time_of_day
      Keyword.has_key?(time, :year) -> :anchored
      true -> :scalar_other
    end
  end

  defp classify(%Tempo.Interval{from: :undefined, to: :undefined}), do: :fully_open_interval

  # A duration and an end imply the start, so such an interval is not open.
  defp classify(%Tempo.Interval{
         from: :undefined,
         to: %Tempo{},
         duration: %Tempo.Duration{},
         recurrence: recurrence
       })
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1),
       do: :recurring_interval

  defp classify(%Tempo.Interval{from: :undefined, to: %Tempo{}, duration: %Tempo.Duration{}}),
    do: :closed_interval

  defp classify(%Tempo.Interval{from: :undefined}), do: :open_lower_interval
  defp classify(%Tempo.Interval{to: :undefined}), do: :open_upper_interval

  defp classify(%Tempo.Interval{recurrence: recurrence})
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1),
       do: :recurring_interval

  defp classify(%Tempo.Interval{}), do: :closed_interval

  defp classify(%Tempo.IntervalSet{} = set) do
    if IntervalSet.empty?(set), do: :empty_interval_set, else: :interval_set
  end

  defp classify(%Tempo.Set{type: :all}), do: :all_of_set
  defp classify(%Tempo.Set{type: :one}), do: :one_of_set
  defp classify(%RecurrenceSet{}), do: :recurrence_set
  defp classify(%Conditional{}), do: :conditional_member
  defp classify(%Tempo.Duration{}), do: :duration
  defp classify(_), do: :unknown

  ## ------------------------------------------------------------
  ## explain_parts — one clause per input shape
  ## ------------------------------------------------------------

  defp explain_parts(%Tempo{} = tempo), do: scalar_parts(tempo)
  defp explain_parts(%Tempo.Interval{} = iv), do: interval_parts(iv)
  defp explain_parts(%Tempo.IntervalSet{} = set), do: interval_set_parts(set)
  defp explain_parts(%Tempo.Set{} = set), do: set_parts(set)
  defp explain_parts(%Tempo.Duration{} = d), do: duration_parts(d)
  defp explain_parts(%RecurrenceSet{} = set), do: recurrence_set_parts(set)
  defp explain_parts(%Conditional{} = conditional), do: conditional_parts(conditional)

  defp explain_parts(other) do
    [{:headline, "A value Tempo doesn't know how to describe: #{inspect(other)}."}]
  end

  ## ------------------------------------------------------------
  ## Scalar Tempo
  ## ------------------------------------------------------------

  # A bare selection (`2018YL1K1IN`, "in 2018, the first Monday") is a
  # rule rather than a span: it names which occurrences are wanted, not an
  # extent. `selection_prose/1` already renders exactly this for
  # recurrences, so reuse it rather than asking for a span that does not
  # exist.
  defp scalar_parts(%Tempo{time: time} = tempo) do
    case find_unit(time, :selection) do
      nil -> scalar_value_parts(tempo)
      selection -> selection_parts(tempo, time, selection)
    end
  end

  # A grouped component is a 3-tuple, so the time list is not always a
  # valid keyword list and `Keyword.get/3` raises on it.
  defp find_unit(time, key) do
    Enum.find_value(time, fn
      {^key, value} -> value
      _entry -> nil
    end)
  end

  defp selection_parts(%Tempo{} = tempo, time, selection) do
    scope = selection_scope(tempo, time)

    [
      {:headline, "A selection — a rule naming which occurrences are wanted."},
      {:span, "#{scope} #{selection_prose(selection, naming(tempo))}."},
      {:calendar, calendar_text(tempo)},
      {:hint, "Pair it with a recurrence (`R/../P1Y/FL…N`) to list its occurrences."}
    ]
    |> Enum.reject(&is_nil/1)
  end

  # The period a selection selects in, which the units before it name: "In
  # 2026", "In June 2026", "On June 15, 2026". A value that is only a
  # selection selects in whatever it is paired with.
  defp selection_scope(%Tempo{} = tempo, time) do
    case Enum.take_while(time, &(not match?({:selection, _parts}, &1))) do
      [] -> "Selects"
      [{:year, year}] when is_integer(year) -> "In #{year}, selects"
      period -> period_scope(%{tempo | time: period}, period)
    end
  end

  # The period by the headline it has as a value, within a sentence. A
  # period the headline has no words for is its year alone.
  defp period_scope(%Tempo{} = period_value, period) do
    case scalar_headline(period_value) do
      "A Tempo " <> _no_words_for_it -> year_scope(period)
      headline -> "#{period_preposition(period)} #{within_a_sentence(headline)}, selects"
    end
  end

  defp year_scope(period) do
    case find_unit(period, :year) do
      year when is_integer(year) -> "In #{year}, selects"
      _no_one_year -> "Selects"
    end
  end

  defp period_preposition(period) do
    cond do
      Enum.any?(period, &unit_in?(&1, [:day, :day_of_week, :day_of_year])) -> "On"
      Enum.all?(period, &unit_in?(&1, [:hour, :minute, :second])) -> "At"
      true -> "In"
    end
  end

  defp unit_in?({unit, _value}, units), do: unit in units
  defp unit_in?(_group_of_a_set, _units), do: false

  # A headline as a phrase: with no full stop, no aside in brackets, and no
  # capital on a first word that is not a name.
  defp within_a_sentence(headline) do
    phrase = headline |> String.trim_trailing(".") |> String.replace(~r/ \([^)]*\)/, "")

    case String.split(phrase, " ", parts: 2) do
      [first, rest] when first in ~w(The Week Weeks Day Days Month Months) ->
        String.downcase(first) <> " " <> rest

      _starts_with_a_name ->
        phrase
    end
  end

  defp scalar_value_parts(%Tempo{} = tempo) do
    [
      {:headline, scalar_headline(tempo)},
      {:span, scalar_span(tempo)},
      {:margin, margin_text(tempo)},
      {:qualification, qualification_text(tempo)},
      {:shift, time_shift_text(tempo)},
      {:extended, extended_text(tempo)},
      {:calendar, calendar_text(tempo)},
      {:enumeration, enumeration_text(tempo)},
      {:hint, scalar_hint(tempo)}
    ]
    |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
  end

  # A value converts to its span; one whose span depends on the year it does
  # not have (a day of the year, the 29th of February) is placed in one first.
  defp scalar_hint(%Tempo{} = tempo) do
    case Tempo.to_interval(tempo) do
      {:error, %Tempo.UnanchoredError{}} ->
        "Place it in a year first with `Tempo.at/2` or `Tempo.on/2`."

      _converted_or_refused ->
        "Convert it to an interval with `Tempo.to_interval/1`."
    end
  end

  # The units a headline reads. A value is plain when each it holds is an
  # integer; one holding a set or a group names several values, or a span of
  # them, and is written unit by unit.
  @headline_units [
    :year,
    :month,
    :day,
    :week,
    :day_of_week,
    :day_of_year,
    :hour,
    :minute,
    :second
  ]
  @headline_date_units [:year, :month, :day, :week, :day_of_week, :day_of_year]

  defp scalar_headline(%Tempo{time: time} = tempo) do
    cond do
      has_mask?(time) -> mask_headline(tempo)
      not plain?(time) -> several_headline(tempo)
      only_time_of_day?(time) -> time_of_day_headline(time)
      true -> precision_headline(anchored_precision(time), tempo)
    end
  end

  defp plain?(time), do: Enum.all?(time, &plain_unit?/1)

  defp plain_unit?({unit, value}) when unit in @headline_units, do: is_integer(value)
  defp plain_unit?({_other_unit, _value}), do: true
  defp plain_unit?(_group_of_groups), do: false

  defp precision_headline(:datetime, %Tempo{time: time} = tempo),
    do: capitalised("#{date_phrase(tempo)} at #{clock_phrase(time)}.")

  defp precision_headline(:date, %Tempo{} = tempo), do: capitalised("#{date_phrase(tempo)}.")

  defp precision_headline(:month, %Tempo{} = tempo), do: capitalised("#{month_phrase(tempo)}.")

  defp precision_headline(:year, %Tempo{time: time}), do: "The year #{find_unit(time, :year)}."

  defp precision_headline(:week_datetime, %Tempo{time: time} = tempo),
    do: "#{week_date_phrase(tempo)} at #{clock_phrase(time)}."

  defp precision_headline(:week_date, %Tempo{} = tempo), do: "#{week_date_phrase(tempo)}."

  defp precision_headline(:week, %Tempo{time: time}),
    do: "Week #{find_unit(time, :week)} of #{find_unit(time, :year)}."

  defp precision_headline(yearless, %Tempo{} = tempo), do: yearless_headline(yearless, tempo)

  # "June 15, 2026", or "day 15 of month 6 of 5786" where the month has no name.
  defp date_phrase(%Tempo{time: time} = tempo) do
    day = find_unit(time, :day)
    year = find_unit(time, :year)

    case named_month(tempo) do
      {:ok, name} -> "#{name} #{day}, #{year}"
      :error -> "day #{day} of month #{find_unit(time, :month)} of #{year}"
    end
  end

  # A month is named, where its calendar names the months of a year as it
  # counts them. In a year that does not begin with its first month the
  # month counted is not the month named (the first of a
  # `Calendrical.Julian.March25` year is 25 to 31 March), so it is given by
  # its number.
  defp month_phrase(%Tempo{time: time} = tempo) do
    year = find_unit(time, :year)

    case counted_as_named?(year, calendar_of(tempo)) and named_month(tempo) do
      {:ok, name} -> "#{name} #{year}"
      _no_name -> "month #{find_unit(time, :month)} of #{year}"
    end
  end

  defp counted_as_named?(year, calendar) when is_integer(year),
    do: UnitValues.year_begins_with_first_month?(year, calendar)

  defp counted_as_named?(_no_one_year, _calendar), do: true

  # A clock time as it is written: the hour and the minute, the second where
  # the value is written to one, and the fraction of it where it has one. A
  # second was left out, so 10:30:15 was "10:30" and its span from 10:30 to
  # 10:30.
  defp clock_phrase(time) do
    hour = find_unit(time, :hour) || 0
    minute = find_unit(time, :minute) || 0

    "#{two_digit(hour)}:#{two_digit(minute)}#{seconds_text(time)}"
  end

  defp seconds_text(time) do
    case find_unit(time, :second) do
      second when is_integer(second) ->
        ":#{two_digit(second)}#{fraction_text(find_unit(time, :microsecond))}"

      _no_one_second ->
        ""
    end
  end

  # A fraction of a second is held in microseconds, with the number of
  # digits it was written to.
  defp fraction_text({microseconds, digits})
       when is_integer(microseconds) and is_integer(digits) and digits > 0 do
    written = microseconds |> Integer.to_string() |> String.pad_leading(6, "0")
    "." <> String.slice(written, 0, digits)
  end

  defp fraction_text(_no_fraction), do: ""

  # The name of a value's month, in its calendar and, when it has one, its year.
  defp named_month(%Tempo{time: time} = tempo),
    do: fetch_month_name(find_unit(time, :month), naming(tempo))

  # What names a month: its calendar and, when the value states one, its year.
  defp naming(%Tempo{time: time} = tempo) do
    case find_unit(time, :year) do
      year when is_integer(year) -> {calendar_of(tempo), year}
      _no_one_year -> {calendar_of(tempo), nil}
    end
  end

  # A week date in its own terms: its weekday, its week and its year.
  defp week_date_phrase(%Tempo{time: time} = tempo) do
    year = find_unit(time, :year)
    week = find_unit(time, :week)
    day = find_unit(time, :day_of_week)

    "#{weekday_of(year, week, day, calendar_of(tempo))} of week #{week} of #{year}"
  end

  # The weekday a week date names, asked of the date itself: a calendar of
  # weeks starts its week as its configuration says, so its day 2 need not be
  # a Tuesday.
  defp weekday_of(year, week, day, calendar) do
    case Validation.date_from_iso_week(year, week, day, calendar) do
      {:ok, %Date{} = date} -> weekday_name(Date.day_of_week(date, :monday))
      _no_such_date -> "Day #{day}"
    end
  end

  # No year at all: a recurring day-and-month (a birthday), a month, a bare
  # day, a week or a day of the week — values in their own right, not partial
  # anchored ones.
  # A value with no year keeps a count from the end as it is written where
  # what it counts in depends on the year (`2M-1D`, `-1M`), and it is worded
  # by its place from the end: "the last day of February", "the last month".
  defp yearless_headline(:yearless_date, %Tempo{time: time} = tempo) do
    day = find_unit(time, :day)
    month = find_unit(time, :month)

    date =
      case named_month(tempo) do
        {:ok, name} when day > 0 -> "#{name} #{day}"
        {:ok, name} -> "#{placed("day", day)} of #{name}"
        :error -> "#{placed("day", day)} of #{placed("month", month)}"
      end

    capitalised("#{date}, in any year (no year — it recurs).")
  end

  defp yearless_headline(:yearless_month, %Tempo{time: time} = tempo) do
    case named_month(tempo) do
      {:ok, name} ->
        "#{name}, in any year (no year — it recurs)."

      :error ->
        capitalised(
          "#{placed("month", find_unit(time, :month))}, in any year (no year — it recurs)."
        )
    end
  end

  defp yearless_headline(:day_only, %Tempo{time: time}) do
    capitalised(
      "#{placed("day", find_unit(time, :day))} of any month (no year or month — it recurs)."
    )
  end

  defp yearless_headline(:day_of_year_only, %Tempo{time: time}) do
    capitalised(
      "#{placed("day", find_unit(time, :day_of_year))} of any year (no year — it recurs)."
    )
  end

  defp yearless_headline(:yearless_week_date, %Tempo{time: time} = tempo) do
    "#{yearless_weekday(tempo)} of #{placed("week", find_unit(time, :week))}, " <>
      "in any year (no year — it recurs)."
  end

  defp yearless_headline(:yearless_week, %Tempo{time: time}) do
    capitalised("#{placed("week", find_unit(time, :week))} of any year (no year — it recurs).")
  end

  defp yearless_headline(:weekday_only, %Tempo{} = tempo),
    do: "#{yearless_weekday(tempo)} of any week (no year or week — it recurs)."

  defp yearless_headline(:none, %Tempo{} = tempo) do
    {unit, _scale} = Tempo.resolution(tempo)
    "A Tempo value at #{inspect(unit)} resolution."
  end

  # A unit by its number, or by its place from the end where it is counted
  # from there: "day 15", "the last day", "the 2nd-to-last month".
  defp placed(noun, value) when is_integer(value) and value < 0,
    do: "the #{ordinal(value)} #{noun}"

  defp placed(noun, value), do: "#{noun} #{value}"

  # Without a year there is no date to ask for its weekday. ISO 8601 numbers a
  # month-based calendar's days of the week from Monday; a calendar of weeks'
  # day is given by its number.
  defp yearless_weekday(%Tempo{time: time} = tempo) do
    day = find_unit(time, :day_of_week)

    if Tempo.week_based_calendar?(calendar_of(tempo)),
      do: "Day #{day}",
      else: weekday_name(day)
  end

  # A value built without a calendar is Gregorian, as it is everywhere else.
  defp calendar_of(%Tempo{calendar: nil}), do: Calendrical.Gregorian
  defp calendar_of(%Tempo{calendar: calendar}), do: calendar

  # The precision a value states, the first whose units it has. Those with no
  # year at all — a recurring day-and-month (a birthday), a month, a bare day,
  # a bare day of the year, a week or a day of the week — are values in their
  # own right, not partial anchored ones.
  @precisions [
    {[:year, :month, :day, :hour], :datetime},
    {[:year, :month, :day], :date},
    {[:year, :month], :month},
    {[:year, :week, :day_of_week, :hour], :week_datetime},
    {[:year, :week, :day_of_week], :week_date},
    {[:year, :week], :week},
    {[:year], :year},
    {[:month, :day], :yearless_date},
    {[:month], :yearless_month},
    {[:day], :day_only},
    {[:day_of_year], :day_of_year_only},
    {[:week, :day_of_week], :yearless_week_date},
    {[:week], :yearless_week},
    {[:day_of_week], :weekday_only}
  ]

  defp anchored_precision(time) do
    Enum.find_value(@precisions, :none, fn {units, precision} ->
      all_present?(time, units) && precision
    end)
  end

  defp all_present?(time, keys), do: Enum.all?(keys, &is_integer(find_unit(time, &1)))

  defp time_of_day_headline(time),
    do: "The time-of-day #{clock_phrase(time)} (unanchored — recurs every day)."

  # A value holding a set or a group names several values, or a span of them,
  # so its headline writes each unit out: "The 1st and 15th of June 2026",
  # "Weeks 25 and 27 of 2026", "January to March 2026". A unit that is neither
  # (a margin of error, a group of groups) leaves only the resolution to state.
  defp several_headline(%Tempo{time: time} = tempo) do
    with true <- Enum.all?(time, &writable_unit?/1),
         {:ok, phrase} <- shape_phrase(date_shape(time), tempo) do
      capitalised(phrase) <> "."
    else
      _unwritable -> yearless_headline(:none, tempo)
    end
  end

  # An hour or a minute is written as a clock time, which a group, a span of
  # them, is not.
  defp writable_unit?({unit, value}) when unit in [:hour, :minute],
    do: is_integer(value) or values?(unit, value)

  defp writable_unit?({unit, value}) when unit in @headline_units, do: writable?(unit, value)
  defp writable_unit?({_other_unit, _value}), do: true
  defp writable_unit?(_group_of_groups), do: false

  defp writable?(_unit, value) when is_integer(value), do: true
  defp writable?(_unit, {:group, %Range{}}), do: true
  defp writable?(unit, value), do: values?(unit, value)

  # A set whose every member is a value to name. A member counted from the
  # end of a span the value does not fix (`{1..-1}M`, the months of no year
  # in particular; `-1D`) is not one: only a year is written below zero.
  defp values?(unit, [_ | _] = set), do: Enum.all?(set, &named_value?(unit, &1))
  defp values?(_unit, _margin_or_other), do: false

  defp named_value?(:year, value) when is_integer(value), do: true
  defp named_value?(:year, %Range{} = range), do: Range.size(range) > 0
  defp named_value?(_unit, value) when is_integer(value), do: value >= 0

  defp named_value?(_unit, %Range{first: first, last: last} = range),
    do: first >= 0 and last >= 0 and Range.size(range) > 0

  defp named_value?(_unit, _other), do: false

  defp date_shape(time) do
    for {unit, _value} <- time, unit in @headline_date_units, do: unit
  end

  # A headline by the date units a value holds, each written as the values it
  # names. A day's clock times follow it; a value with no date at all is its
  # times of day.
  defp shape_phrase([], %Tempo{time: time}), do: {:ok, times_of_day_phrase(clock_times(time))}

  defp shape_phrase([:year], %Tempo{time: time}) do
    year = find_unit(time, :year)
    {:ok, "the #{noun("year", year)} #{years_phrase(year)}"}
  end

  defp shape_phrase([:year, :month], %Tempo{} = tempo), do: {:ok, months_of_years(tempo)}

  defp shape_phrase([:year, :month, :day], %Tempo{time: time} = tempo),
    do: {:ok, days_of_months(tempo) <> at_times(time)}

  defp shape_phrase([:year, :week], %Tempo{time: time}),
    do: {:ok, "#{weeks_phrase(find_unit(time, :week))} of #{years_of(time)}"}

  defp shape_phrase([:year, :week, :day_of_week], %Tempo{time: time} = tempo),
    do: {:ok, days_of_weeks(tempo) <> at_times(time)}

  defp shape_phrase([:year, :day_of_year], %Tempo{time: time}),
    do: {:ok, "#{numbered("day", find_unit(time, :day_of_year))} of #{years_of(time)}"}

  defp shape_phrase([:month], %Tempo{} = tempo),
    do: {:ok, "#{months_phrase(tempo)}, in any year (no year — it recurs)"}

  defp shape_phrase([:month, :day], %Tempo{time: time} = tempo) do
    {:ok,
     "#{days_phrase(find_unit(time, :day))} of #{months_phrase(tempo)}, " <>
       "in any year (no year — it recurs)"}
  end

  # A group of days with no month counts on past any month's end (`5G10DU` is
  # days 41 to 50), so it is not days of a month.
  defp shape_phrase([:day], %Tempo{time: time}) do
    case find_unit(time, :day) do
      {:group, _days} -> :error
      days -> {:ok, "#{days_phrase(days)} of any month (no year or month — it recurs)"}
    end
  end

  defp shape_phrase([:day_of_year], %Tempo{time: time}) do
    {:ok, "#{numbered("day", find_unit(time, :day_of_year))} of any year (no year — it recurs)"}
  end

  defp shape_phrase([:week], %Tempo{time: time}),
    do: {:ok, "#{weeks_phrase(find_unit(time, :week))} of any year (no year — it recurs)"}

  defp shape_phrase([:week, :day_of_week], %Tempo{time: time} = tempo) do
    {:ok,
     "#{weekdays_phrase(tempo)} of #{weeks_phrase(find_unit(time, :week))}, " <>
       "in any year (no year — it recurs)"}
  end

  defp shape_phrase([:day_of_week], %Tempo{} = tempo),
    do: {:ok, "#{weekdays_phrase(tempo)} of any week (no year or week — it recurs)"}

  defp shape_phrase(_another_shape, _tempo), do: :error

  # "June and July 2026", or "June of 2021 and 2022" when the years are several.
  defp months_of_years(%Tempo{time: time} = tempo) do
    case find_unit(time, :year) do
      year when is_integer(year) -> "#{months_phrase(tempo)} #{year}"
      years -> "#{months_phrase(tempo)} of #{years_phrase(years)}"
    end
  end

  # A date as it is always written, "June 15, 2026", when only its times are
  # several, and otherwise the days of its months: "the 1st and 15th of June
  # 2026".
  defp days_of_months(%Tempo{time: time} = tempo) do
    if all_present?(time, [:year, :month, :day]),
      do: date_phrase(tempo),
      else: "#{days_phrase(find_unit(time, :day))} of #{months_of_years(tempo)}"
  end

  defp days_of_weeks(%Tempo{time: time} = tempo) do
    if all_present?(time, [:year, :week, :day_of_week]) do
      week_date_phrase(tempo)
    else
      "#{weekdays_phrase(tempo)} of #{weeks_phrase(find_unit(time, :week))} of #{years_of(time)}"
    end
  end

  defp years_of(time), do: years_phrase(find_unit(time, :year))

  defp years_phrase(years), do: component_phrase(years, &Integer.to_string/1)

  defp months_phrase(%Tempo{time: time} = tempo),
    do: component_phrase(find_unit(time, :month), &month_name(&1, naming(tempo)))

  defp days_phrase(days), do: "the " <> component_phrase(days, &ordinal/1)

  defp weeks_phrase(weeks), do: numbered("week", weeks)

  # ISO 8601 numbers a month-based calendar's days of the week from Monday; a
  # calendar of weeks' days are given by their numbers.
  defp weekdays_phrase(%Tempo{time: time} = tempo) do
    days = find_unit(time, :day_of_week)

    if Tempo.week_based_calendar?(calendar_of(tempo)),
      do: numbered("day", days),
      else: component_phrase(days, &weekday_name/1)
  end

  defp numbered(word, values),
    do: "#{noun(word, values)} #{component_phrase(values, &Integer.to_string/1)}"

  defp noun(word, values), do: if(match?([_one], values_of(values)), do: word, else: word <> "s")

  # A unit's values by name: one alone, a run of more than two as its ends,
  # and otherwise each, joined with "and". A group is one span, from its first
  # value to its last.
  defp component_phrase(value, name) when is_integer(value), do: name.(value)

  defp component_phrase({:group, %Range{first: only, last: only}}, name), do: name.(only)

  defp component_phrase({:group, %Range{first: first, last: last}}, name),
    do: "#{name.(first)} to #{name.(last)}"

  defp component_phrase(set, name) do
    values = values_of(set)

    if run?(values),
      do: "#{name.(hd(values))}–#{name.(List.last(values))}",
      else: and_join(Enum.map(values, name))
  end

  defp run?([first | _] = values) do
    count = length(values)
    count > 2 and List.last(values) - first + 1 == count
  end

  defp values_of(value) when is_integer(value), do: [value]
  defp values_of({:group, %Range{} = range}), do: Enum.to_list(range)
  defp values_of(set), do: set |> Enum.flat_map(&expand_int/1) |> Enum.sort() |> Enum.dedup()

  # Each hour with each minute, as a clock time: "10:00" and "14:00", or
  # "10:00" and "10:30", and with each second where the value is written to
  # one: "10:30:15" and "10:30:45".
  defp clock_times(time) do
    for hour <- values_of(find_unit(time, :hour) || 0),
        minute <- values_of(find_unit(time, :minute) || 0),
        second <- seconds_written(find_unit(time, :second)),
        do: "#{two_digit(hour)}:#{two_digit(minute)}#{second}"
  end

  defp seconds_written(second) when is_integer(second), do: [":" <> two_digit(second)]

  defp seconds_written([_ | _] = seconds) do
    if values?(:second, seconds),
      do: for(second <- values_of(seconds), do: ":" <> two_digit(second)),
      else: [""]
  end

  defp seconds_written(_none_or_no_plain_seconds), do: [""]

  defp at_times(time) do
    if find_unit(time, :hour), do: " at " <> and_join(clock_times(time)), else: ""
  end

  defp times_of_day_phrase([one]), do: "the time-of-day #{one} (unanchored — recurs every day)"

  defp times_of_day_phrase(times),
    do: "the times of day #{and_join(times)} (unanchored — they recur every day)"

  defp mask_headline(%Tempo{time: time}) do
    case find_first_mask(time) do
      {:year, mask} ->
        {min, max} = mask_range(mask)
        sign_note = if :negative in mask, do: " BCE", else: ""
        "A masked year spanning #{decade_label(min, max)}#{sign_note}."

      {unit, _mask} ->
        "A Tempo with a masked #{unit} component."

      nil ->
        "A Tempo value."
    end
  end

  defp decade_label(min, max) when max - min == 9, do: "the #{min}s"
  defp decade_label(min, max) when max - min == 99, do: "the #{div(min, 100)}00s (century)"
  defp decade_label(min, max) when max - min == 999, do: "the #{div(min, 1000)}000s (millennium)"
  defp decade_label(min, max) when max - min == 9999, do: "all 4-digit years (#{min}–#{max})"
  defp decade_label(min, max), do: "#{min} through #{max} (#{max - min + 1} years)"

  defp scalar_span(%Tempo{} = tempo) do
    case Tempo.to_interval(tempo) do
      {:ok, %Tempo.Interval{from: from, to: to}} ->
        "Span: [#{render_endpoint(from)}, #{render_endpoint(to)})."

      {:ok, %Tempo.IntervalSet{} = set} ->
        "Converts to #{IntervalSet.count(set)} disjoint intervals."

      {:error, _} ->
        nil
    end
  end

  # A `±` margin means the value may ground anywhere within its
  # margin of error: `2000±1Y` is some year in 1999–2001. Surface the
  # margin and, for the single-margin case, the full span the
  # groundings cover (the same widening the certainty API applies).
  defp margin_text(%Tempo{time: time} = tempo) do
    case margin_entries(time) do
      [] -> nil
      entries -> describe_margins(entries, tempo)
    end
  end

  defp margin_entries(time) do
    Enum.flat_map(time, fn
      {unit, {_value, options}} when is_list(options) ->
        case Keyword.get(options, :margin_of_error) do
          nil -> []
          margin -> [{unit, margin}]
        end

      _other ->
        []
    end)
  end

  defp describe_margins([{unit, margin}] = entries, tempo) do
    nominal = strip_margins(tempo)

    with %Tempo{} = low <- Tempo.shift(nominal, [{unit, -margin}]),
         true <- Tempo.anchored?(low),
         %Tempo{} = high <- Tempo.shift(nominal, [{unit, margin}]),
         {:ok, %Tempo.Interval{from: from}} <- Tempo.to_interval(low),
         {:ok, %Tempo.Interval{to: to}} <- Tempo.to_interval(high) do
      "Margin: ±#{margin} #{unit_word(unit, margin)} — groundings span " <>
        "[#{render_endpoint(from)}, #{render_endpoint(to)})."
    else
      _other -> margin_list_text(entries)
    end
  end

  defp describe_margins(entries, _tempo), do: margin_list_text(entries)

  defp margin_list_text(entries) do
    rendered =
      Enum.map_join(entries, ", ", fn {unit, margin} ->
        "±#{margin} #{unit_word(unit, margin)}"
      end)

    "Margin: #{rendered}."
  end

  defp strip_margins(%Tempo{time: time} = tempo) do
    stripped =
      Enum.map(time, fn
        {unit, {value, options}} when is_list(options) ->
          case Keyword.delete(options, :margin_of_error) do
            [] -> {unit, value}
            rest -> {unit, {value, rest}}
          end

        other ->
          other
      end)

    %{tempo | time: stripped}
  end

  defp unit_word(unit, 1), do: "#{unit}"
  defp unit_word(unit, _margin), do: "#{unit}s"

  # A qualifier every component carries is the whole value's, which is how it
  # is written (ISO 8601-2 §8.2.1); otherwise each qualified component is
  # named.
  defp qualification_text(%Tempo{qualifications: nil}), do: nil

  defp qualification_text(%Tempo{qualifications: qualifications} = tempo) do
    case Qualification.whole(tempo) do
      nil ->
        "Per-component qualifications: #{components_qualified(qualifications)}."

      whole ->
        "Expression-level qualification: #{qualification_word(whole)} " <>
          "(EDTF #{qualification_symbol(whole)})."
    end
  end

  # Each qualifier with the components that carry it, the components in the
  # order a value is written in: "the year and the month approximate (EDTF
  # ~); the day uncertain (EDTF ?)".
  @written_order [:year, :month, :week, :day_of_year, :day, :day_of_week, :hour, :minute, :second]

  defp components_qualified(qualifications) do
    qualifications
    |> Enum.sort_by(fn {unit, _qualifier} -> Enum.find_index(@written_order, &(&1 == unit)) end)
    |> Enum.chunk_by(fn {_unit, qualifier} -> qualifier end)
    |> Enum.map_join("; ", fn [{_unit, qualifier} | _rest] = components ->
      units = Enum.map(components, fn {unit, _qualifier} -> "the #{unit_words(unit)}" end)

      "#{and_join(units)} #{qualification_word(qualifier)} (EDTF #{qualification_symbol(qualifier)})"
    end)
  end

  defp unit_words(unit), do: unit |> Atom.to_string() |> String.replace("_", " ")

  # A time shift is how far the value's clock is from UTC (ISO 8601-1
  # §3.1.1.25), and with it the value names a moment. It was not said.
  defp time_shift_text(%Tempo{shift: [hour: 0]}),
    do: "Time shift: none, the time is in UTC (`Z`)."

  defp time_shift_text(%Tempo{shift: [_ | _] = shift}),
    do: "Time shift: #{shift_text(shift)} from UTC."

  defp time_shift_text(_no_shift), do: nil

  defp extended_text(%Tempo{extended: nil}), do: nil

  defp extended_text(%Tempo{extended: extended}) do
    parts =
      [
        extended[:zone_id] && "Timezone: #{extended.zone_id}.",
        extended[:zone_offset] && "UTC offset: #{extended.zone_offset} minutes."
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    case parts do
      [] -> nil
      _ -> Enum.join(parts, " ")
    end
  end

  defp calendar_text(%Tempo{calendar: Calendrical.Gregorian}), do: nil
  defp calendar_text(%Tempo{calendar: cal}), do: "Calendar: #{inspect(cal)}."

  # A value with no components has no resolution to report — `resolution/1`
  # takes the last unit and there is none.
  defp enumeration_text(%Tempo{time: []}), do: nil

  defp enumeration_text(%Tempo{} = tempo) do
    {unit, _count} = Tempo.resolution(tempo)
    enumerator_text(unit, tempo.calendar)
  end

  # `Unit.implicit_enumerator/2` is defined only over the known time
  # units, so ask whether this is one rather than rescue the
  # `FunctionClauseError` for those that are not. `fetch_sort_key/1`
  # answers exactly that question: its map's keys *are* `@units`.
  defp enumerator_text(unit, calendar) do
    case Unit.fetch_sort_key(unit) do
      {:ok, _key} -> describe_enumerator(Unit.implicit_enumerator(unit, calendar), calendar)
      :error -> nil
    end
  end

  defp describe_enumerator(nil, _calendar),
    do: "At finest supported resolution — cannot be enumerated further."

  # The unit is the one the value's interval says it is walked by: a week
  # of a calendar of months by days, the dates its walk yields.
  defp describe_enumerator({next_unit, _range}, calendar),
    do: "Iterates at #{inspect(Unit.walked_by(next_unit, calendar))} granularity."

  ## ------------------------------------------------------------
  ## Tempo.Interval
  ## ------------------------------------------------------------

  defp interval_parts(%Tempo.Interval{from: :undefined, to: :undefined}) do
    [
      {:headline, "A fully open interval (`../..`)."},
      {:hint, "No start and no end — not enumerable, not usable in set operations."}
    ]
  end

  # `R5/P1D/2026-06-20` — a recurrence written with a duration and an end,
  # which are its last occurrence (ISO 8601-1 §5.6.1 c); the others precede it.
  defp interval_parts(%Tempo.Interval{
         recurrence: recurrence,
         from: :undefined,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{time: duration_time}
       })
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    [
      {:headline, recurrence_headline(recurrence)},
      {:span, "Ending: #{render_endpoint(to)} (exclusive — half-open `[from, to)`)."},
      {:span, "Cadence: #{duration_prose(duration_time)}."},
      {:hint, recurrence_hint(recurrence, to)}
    ]
  end

  # `P1D/2026-06-15` — a duration and an end. The lower bound is implied
  # by the duration, not absent, so this must be matched before the
  # open-lower clause below: that clause would call a bounded one-day
  # interval "open-lower", which is not merely vague but wrong.
  defp interval_parts(%Tempo.Interval{
         from: :undefined,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{time: duration_time}
       }) do
    [
      {:headline, "An interval given as a duration and an end."},
      {:span, "Ends: #{render_endpoint(to)} (exclusive — half-open `[from, to)`)."},
      {:span, "Duration: #{duration_prose(duration_time)}."},
      {:hint, "Resolve the implied start with `Tempo.to_interval/1`."}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: :undefined, to: %Tempo{} = to}) do
    [
      {:headline, "An open-lower interval (`../#{render_endpoint(to)}`)."},
      {:span, "Upper bound: #{render_endpoint(to)}."},
      {:hint, "Enumeration requires a lower bound; set operations need a `:within` window."}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: %Tempo{} = from, to: :undefined}) do
    [
      {:headline, "An open-upper interval (`#{render_endpoint(from)}/..`)."},
      {:span, "Lower bound: #{render_endpoint(from)}."},
      {:hint, "Enumerates forward forever — use `Enum.take/2` to halt."}
    ]
  end

  # An RRULE with an `UNTIL` (`FREQ=DAILY;UNTIL=20260620`) repeats until its
  # end: bounded, though it names no count.
  defp interval_parts(
         %Tempo.Interval{
           recurrence: :infinity,
           from: %Tempo{} = from,
           to: %Tempo{} = until,
           duration: %Tempo.Duration{time: dt}
         } = interval
       ) do
    selection = selection_of(interval.repeat_rule)

    [
      {:headline, "A recurrence until #{render_endpoint(until)}."},
      {:span, "Starting: #{render_endpoint(from)}."},
      selection && {:span, "Selects: #{selection_prose(selection, rule_naming(interval))}."},
      {:span, "Cadence: #{duration_prose(dt)}."},
      {:hint, "List its occurrences: `Tempo.to_interval(interval)`."}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp interval_parts(
         %Tempo.Interval{
           recurrence: recurrence,
           from: %Tempo{} = from,
           duration: %Tempo.Duration{time: dt}
         } = interval
       )
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    selection = selection_of(interval.repeat_rule)

    [
      {:headline, recurrence_headline(recurrence)},
      {:span, "Starting: #{render_endpoint(from)}."},
      selection && {:span, "Selects: #{selection_prose(selection, rule_naming(interval))}."},
      {:span, "Cadence: #{duration_prose(dt)}."},
      {:hint, recurrence_hint(recurrence, from)}
    ]
    |> Enum.reject(&is_nil/1)
  end

  # A recurrence with an open start — `R/../P1Y/FL11M4K4IN`, "every year, the
  # fourth Thursday of November", beginning nowhere. Two sentinels spell
  # "no endpoint": `:undefined` from the ISO 8601 parser and `nil` from
  # the RRULE parser, and the clauses above match only the first. The
  # rule itself is fully described, so explain the selection and name
  # what is missing rather than falling through to the generic shape.
  defp interval_parts(
         %Tempo.Interval{
           recurrence: recurrence,
           from: nil,
           duration: %Tempo.Duration{time: duration_time}
         } = interval
       )
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    selection = selection_of(interval.repeat_rule)

    [
      {:headline, recurrence_headline(recurrence)},
      {:span, "Starting: open — the rule names no start."},
      selection && {:span, "Selects: #{selection_prose(selection, rule_naming(interval))}."},
      {:span, "Cadence: #{duration_prose(duration_time)}."},
      {:hint, open_start_hint()}
    ]
    |> Enum.reject(&is_nil/1)
  end

  # A recurrence whose `from` is a `%Tempo.Set{}` domain — `R/{2020Y..2024Y,
  # ^2022Y}/P1Y/FL12M25DN`. The domain is the set of periods the recurrence may
  # occur in; a plain-member domain is its own window, an exclusions-only one
  # subtracts from a supplied bound. Describe the domain, then the selection.
  defp interval_parts(
         %Tempo.Interval{
           recurrence: recurrence,
           from: %Tempo.Set{} = domain,
           duration: %Tempo.Duration{time: dt}
         } = interval
       )
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    selection = selection_of(interval.repeat_rule)

    [
      {:headline, recurrence_headline(recurrence)},
      {:span, "Domain: #{domain_prose(domain)}."},
      selection && {:span, "Selects: #{selection_prose(selection, rule_naming(interval))}."},
      {:span, "Cadence: #{duration_prose(dt)}."},
      {:hint, domain_hint(domain)}
    ]
    |> Enum.reject(&is_nil/1)
  end

  # `2026-06-15/P1D`, `2026-06-15T09:00/PT8H` — a start and a duration,
  # the ordinary ISO 8601 spelling of "an 8-hour shift from 09:00". It
  # carries no `to`, so every clause above missed it and it reported an
  # unusual shape. Sits below the recurrence clause so a real recurrence
  # still matches there; what reaches here repeats once or not at all.
  defp interval_parts(%Tempo.Interval{
         from: %Tempo{} = from,
         to: nil,
         duration: %Tempo.Duration{time: duration_time}
       }) do
    [
      {:headline, "An interval given as a start and a duration."},
      {:span, "Starts: #{render_endpoint(from)}."},
      {:span, "Duration: #{duration_prose(duration_time)}."},
      {:hint, "Resolve the implied end with `Tempo.to_interval/1`."}
    ]
  end

  # `R5/2026-06-15/2026-06-20` — a recurrence written with a start and an end,
  # which are its first occurrence (ISO 8601-1 §5.6.1 a); each after it starts
  # where the one before ends and is as long.
  defp interval_parts(%Tempo.Interval{
         recurrence: recurrence,
         from: %Tempo{} = from,
         to: %Tempo{} = to,
         duration: nil
       })
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    [
      {:headline, recurrence_headline(recurrence)},
      {:span,
       "First occurrence: #{render_endpoint(from)} to #{render_endpoint(to)} (exclusive)."},
      {:span, "Each occurrence starts where the one before ends and is as long."},
      {:hint, recurrence_hint(recurrence, from)}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    [
      {:headline, closed_headline(from, to)},
      {:span, "From: #{render_endpoint(from)}."},
      {:span, "To:   #{render_endpoint(to)} (exclusive — half-open `[from, to)`)."},
      each_value_hint(from, to),
      metadata_part(interval.metadata)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp interval_parts(%Tempo.Interval{}) do
    [{:headline, "A Tempo.Interval with an unusual shape."}]
  end

  # An interval of two ends, one of which holds a set, is the span from each
  # of its values to the other end, or to each from it. It was worded as one
  # interval, from the first day of the month its set of days is in.
  defp closed_headline(from, to) do
    case {names_each_value?(from), names_each_value?(to)} do
      {true, false} -> "A span from each value of its start to its end."
      {false, true} -> "A span from its start to each value of its end."
      _one_span_or_a_set_at_each_end -> "A closed interval."
    end
  end

  defp each_value_hint(from, to) do
    if names_each_value?(from) != names_each_value?(to),
      do: {:hint, "List the spans with `Tempo.to_interval/1`."}
  end

  defp names_each_value?(%Tempo{} = endpoint), do: Enumeration.names_each_value?(endpoint)

  defp metadata_part(m) when m == %{} or is_nil(m), do: nil

  defp metadata_part(m) do
    text =
      case m[:summary] do
        nil ->
          "Metadata: #{map_size(m)} key(s)."

        s ->
          loc = m[:location]
          if is_binary(loc), do: "Event: #{s} @ #{loc}.", else: "Event: #{s}."
      end

    {:metadata, text}
  end

  ## ------------------------------------------------------------
  ## Tempo.IntervalSet
  ## ------------------------------------------------------------

  defp interval_set_parts(%Tempo.IntervalSet{metadata: metadata} = set) do
    if IntervalSet.empty?(set) do
      [
        {:headline, "An empty IntervalSet."},
        set_metadata_part(metadata)
      ]
      |> Enum.reject(&is_nil/1)
    else
      interval_set_member_parts(IntervalSet.members(set), metadata)
    end
  end

  defp interval_set_member_parts(intervals, metadata) do
    count = length(intervals)

    preview_parts =
      intervals
      |> Enum.take(3)
      |> Enum.with_index(1)
      |> Enum.map(fn {iv, i} ->
        summary = (iv.metadata || %{})[:summary] || "(no summary)"
        {:member, "#{i}. #{render_endpoint(iv.from)} → #{render_endpoint(iv.to)}  · #{summary}"}
      end)

    more =
      if count > 3, do: [{:member, "… and #{count - 3} more."}], else: []

    [
      {:headline, "An IntervalSet with #{count} interval#{if count == 1, do: "", else: "s"}."}
    ] ++ preview_parts ++ more ++ List.wrap(set_metadata_part(metadata))
  end

  defp set_metadata_part(nil), do: nil
  defp set_metadata_part(m) when m == %{}, do: nil

  defp set_metadata_part(%{name: name}) when is_binary(name),
    do: {:metadata, "Calendar name: #{name}."}

  defp set_metadata_part(%{prodid: prodid}) when is_binary(prodid),
    do: {:metadata, "Producer: #{prodid}."}

  defp set_metadata_part(m),
    do: {:metadata, "Set-level metadata: #{map_size(m)} key(s)."}

  ## ------------------------------------------------------------
  ## Tempo.Set
  ## ------------------------------------------------------------

  # A set of durations (ISO 8601-2 §6.5) names lengths of time, and no time.
  defp set_parts(%Tempo.Set{type: type, set: [%Tempo.Duration{} | _durations] = members}) do
    held =
      if type == :all, do: "each of these lengths of time", else: "one of these lengths of time"

    [
      {:headline, "A set of durations: #{held}, and no time on the time line."},
      {:member, "#{length(members)} duration(s): #{members_phrase(members)}."},
      {:hint, "A duration has no span of its own; count one from a date with `Tempo.shift/2`."}
    ]
  end

  defp set_parts(%Tempo.Set{type: :all, set: members, except: except, filter: filter}) do
    [
      {:headline, "An all-of set: every member happened."},
      {:member,
       "#{length(members)} member(s): #{members_phrase(members)}#{set_qualifiers(except, filter)}."},
      {:hint, "Convert it to an IntervalSet with `Tempo.to_interval/1`."}
    ]
  end

  defp set_parts(%Tempo.Set{type: :one, set: members}) do
    [
      {:headline,
       "A one-of set: exactly one of the members happened — we don't know which (epistemic disjunction)."},
      {:member, "#{length(members)} candidate(s): #{members_phrase(members)}."},
      {:hint, "Cannot be converted to an IntervalSet; pick a specific member first."}
    ]
  end

  # A trailing "(excluding …; even years only)" qualifier for a set or domain
  # carrying `^` exclusions or an `e`/`o`/`l`/`c` year filter; empty when it has
  # neither.
  defp set_qualifiers(except, filter) do
    case exclusion_phrase(except) ++ filter_phrase(filter) do
      [] -> ""
      parts -> " (" <> Enum.join(parts, "; ") <> ")"
    end
  end

  defp exclusion_phrase([]), do: []
  defp exclusion_phrase(except), do: ["excluding #{members_phrase(except)}"]

  defp members_phrase(members), do: Enum.map_join(members, ", ", &member_phrase/1)

  # A set/domain member as prose. A range renders `first..last`; anything else
  # falls back to `inspect/1` (the `~o"…"` sigil form).
  defp member_phrase(%Tempo.Range{first: first, last: last}),
    do: "#{inspect(first)}..#{inspect(last)}"

  defp member_phrase(other), do: inspect(other)

  defp filter_phrase(:even), do: ["even years only"]
  defp filter_phrase(:odd), do: ["odd years only"]
  defp filter_phrase(:leap), do: ["leap years only"]
  defp filter_phrase(:common), do: ["common (non-leap) years only"]
  defp filter_phrase(_none), do: []

  # A recurrence domain as an English phrase. An exclusions-only domain reads as
  # a subtraction from "every period"; a plain-member domain lists its members
  # (a range renders `2020Y..2024Y`), with any exclusions/filter appended.
  defp domain_prose(%Tempo.Set{set: [], except: except, filter: filter}) do
    "every period#{set_qualifiers(except, filter)}"
  end

  defp domain_prose(%Tempo.Set{set: members, except: except, filter: filter}) do
    "#{members_phrase(members)}#{set_qualifiers(except, filter)}"
  end

  # A plain-member domain is its own window; one that is only a filter or
  # only exclusions needs a `:within` window.
  defp domain_hint(%Tempo.Set{set: [], except: [], filter: filter}) when not is_nil(filter),
    do: "A filter only — supply a `:within` window; the periods of it the filter keeps are kept."

  defp domain_hint(%Tempo.Set{set: [], filter: nil}),
    do: "Exclusions only — supply a `:within` window; the excluded periods are removed from it."

  defp domain_hint(%Tempo.Set{set: []}) do
    "A filter and exclusions only — supply a `:within` window; the periods of it the filter " <>
      "keeps are kept, less those excluded."
  end

  defp domain_hint(%Tempo.Set{}),
    do:
      "The domain's members are the window, so `Tempo.to_interval/1` lists its occurrences with no `:within` window."

  ## ------------------------------------------------------------
  ## Tempo.RecurrenceSet
  ## ------------------------------------------------------------

  # A recurrence set is its members' rules, each led by its name when its
  # metadata gives one (a holiday's `:name`, an event's `:summary`).
  defp recurrence_set_parts(%RecurrenceSet{members: [], metadata: metadata}) do
    [{:headline, "An empty recurrence set."}, set_metadata_part(metadata)]
    |> Enum.reject(&is_nil/1)
  end

  defp recurrence_set_parts(%RecurrenceSet{members: members, metadata: metadata}) do
    count = length(members)

    previews =
      members
      |> Enum.take(3)
      |> Enum.with_index(1)
      |> Enum.map(fn {member, index} -> {:member, "#{index}. #{member_rule_phrase(member)}."} end)

    more = if count > 3, do: [{:member, "… and #{count - 3} more."}], else: []

    [{:headline, "A recurrence set of #{count} member#{if count == 1, do: "", else: "s"}."}] ++
      previews ++
      more ++
      List.wrap(set_metadata_part(metadata)) ++
      [{:hint, "List its occurrences in a window: `Tempo.to_interval(set, within: ~o\"2026\")`."}]
  end

  # A member that depends on the set's other members, explained on its own.
  defp conditional_parts(%Conditional{} = conditional) do
    [
      {:headline, "A recurrence-set member kept or moved by the set's other members."},
      {:member, "#{member_rule_phrase(conditional)}."},
      {:hint, "Add it to a `Tempo.RecurrenceSet`, which resolves it against its other members."}
    ]
  end

  defp member_rule_phrase(member) do
    case member_name(member) do
      nil -> member |> rule_phrase() |> capitalised()
      name -> "#{name}: #{rule_phrase(member)}"
    end
  end

  defp capitalised(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalised(text), do: text

  defp member_name(%Conditional{metadata: metadata, member: member}),
    do: name_in(metadata) || member_name(member)

  defp member_name(%{metadata: metadata}), do: name_in(metadata)
  defp member_name(_member), do: nil

  defp name_in(%{name: name}) when is_binary(name), do: name
  defp name_in(%{summary: summary}) when is_binary(summary), do: summary
  defp name_in(_metadata), do: nil

  # A recurrence written with a start and an end: its first occurrence, and the
  # rest back to back.
  defp rule_phrase(%Tempo.Interval{
         recurrence: recurrence,
         from: %Tempo{} = from,
         to: %Tempo{} = to,
         duration: nil
       })
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    "#{render_endpoint(from)} to #{render_endpoint(to)}, then back to back#{times_phrase(recurrence)}"
  end

  # A recurrence written with a duration and an end: its last occurrence ends
  # there.
  defp rule_phrase(%Tempo.Interval{
         recurrence: recurrence,
         from: :undefined,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{time: cadence}
       })
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    "#{cadence_phrase(cadence)}, ending #{render_endpoint(to)}#{times_phrase(recurrence)}"
  end

  defp rule_phrase(
         %Tempo.Interval{recurrence: recurrence, duration: %Tempo.Duration{time: cadence}} =
           interval
       )
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    selection = selection_of(interval.repeat_rule)

    [
      selection && selection_prose(selection, rule_naming(interval)),
      cadence_phrase(cadence),
      start_phrase(interval.from),
      until_phrase(interval)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> Kernel.<>(times_phrase(recurrence))
  end

  defp rule_phrase(%Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to}),
    do: "#{render_endpoint(from)} to #{render_endpoint(to)}"

  defp rule_phrase(%Tempo.Interval{} = interval),
    do: interval |> interval_parts() |> headline_phrase()

  defp rule_phrase(%Tempo{} = value), do: render_endpoint(value)

  defp rule_phrase(%RecurrenceSet{members: members}) do
    count = length(members)
    "a recurrence set of #{count} member#{if count == 1, do: "", else: "s"}"
  end

  defp rule_phrase(%Conditional{member: member, to_next: %Tempo{}}),
    do: "#{rule_phrase(member)}, moved when it falls on another member's occurrence"

  defp rule_phrase(%Conditional{member: member}),
    do:
      "#{rule_phrase(member)}, kept only when the days around it fall on other members' occurrences"

  defp rule_phrase(other), do: inspect(other)

  defp cadence_phrase([{unit, 1}]), do: "every #{unit}"
  defp cadence_phrase(cadence), do: "every #{duration_prose(cadence)}"

  defp start_phrase(%Tempo{} = from), do: "from #{render_endpoint(from)}"
  defp start_phrase(%Tempo.Set{} = domain), do: "in #{domain_prose(domain)}"
  defp start_phrase(_open), do: nil

  defp until_phrase(%Tempo.Interval{recurrence: :infinity, to: %Tempo{} = until}),
    do: "until #{render_endpoint(until)}"

  defp until_phrase(_interval), do: nil

  defp times_phrase(count) when is_integer(count), do: ", #{count} times"
  defp times_phrase(_unbounded), do: ""

  # An interval's own headline, as a phrase within a sentence.
  defp headline_phrase(parts) do
    {:headline, headline} = List.keyfind(parts, :headline, 0)
    headline = String.trim_trailing(headline, ".")
    String.downcase(String.first(headline)) <> String.slice(headline, 1..-1//1)
  end

  ## ------------------------------------------------------------
  ## Tempo.Duration
  ## ------------------------------------------------------------

  defp duration_parts(%Tempo.Duration{time: time}) do
    [
      {:headline, "A duration of #{duration_prose(time)}."},
      {:hint, "Has no place on the time line — shift a value by it with `Tempo.shift/2`."},
      {:hint, "Not directly usable in set operations."}
    ]
  end

  ## ------------------------------------------------------------
  ## Shared helpers
  ## ------------------------------------------------------------

  defp has_mask?(time) do
    Enum.any?(time, fn
      {_, {:mask, _}} -> true
      _ -> false
    end)
  end

  @date_units [:year, :month, :day, :week, :day_of_week, :day_of_year]

  defp only_time_of_day?(time) do
    units = Enum.map(time, &elem(&1, 0))

    not Enum.any?(units, &(&1 in @date_units)) and
      Enum.any?(units, &(&1 in [:hour, :minute, :second]))
  end

  defp find_first_mask(time) do
    Enum.find_value(time, fn
      {unit, {:mask, mask}} -> {unit, mask}
      _ -> nil
    end)
  end

  defp mask_range(mask) do
    mask
    |> Enum.reject(&(&1 == :negative))
    |> Mask.mask_bounds()
  end

  defp qualification_word(:uncertain), do: "uncertain"
  defp qualification_word(:approximate), do: "approximate"
  defp qualification_word(:uncertain_and_approximate), do: "both uncertain and approximate"
  defp qualification_word(other), do: to_string(other)

  defp qualification_symbol(:uncertain), do: "?"
  defp qualification_symbol(:approximate), do: "~"
  defp qualification_symbol(:uncertain_and_approximate), do: "%"
  defp qualification_symbol(_), do: "?"

  # Render an endpoint in a consistent `YYYY-MM-DDTHH:MM` shape,
  # padding missing trailing units with their minimum so the
  # output reads as a concrete moment rather than a span. A calendar
  # of weeks writes `YYYY-Www-D` for its date.
  #
  # An end that holds a set names several values and no one moment, and is
  # shown as it is written: `2026Y6M{20,25}D` was shown as the first day of
  # its month.
  defp render_endpoint(%Tempo{time: time} = tempo) do
    if names_each_value?(tempo),
      do: inspect(tempo),
      else: render_moment(tempo, time)
  end

  defp render_endpoint(other), do: inspect(other)

  defp render_moment(tempo, time) do
    case {render_date_part(tempo), render_time_part(time)} do
      # A mask (`198X`), a margin of error (`2018±2Y`) or a grouped
      # component has no plain calendar spelling, so show the value's own
      # rendering rather than `?`. `Inspect` is total — it falls back to a
      # labelled struct view for anything it cannot encode.
      {nil, nil} -> inspect(tempo)
      {date, nil} -> date
      {nil, time} -> "T#{time}#{render_shift(tempo)}"
      {date, time} -> "#{date}T#{time}#{render_shift(tempo)}"
    end
  end

  defp render_date_part(%Tempo{time: time} = tempo) do
    case find_unit(time, :year) do
      year when is_integer(year) -> anchored_date(year, time, calendar_of(tempo))
      _no_plain_year -> render_yearless_date(time)
    end
  end

  # The day an anchored endpoint starts on, by the units after its year.
  defp anchored_date(year, time, calendar) do
    month = find_unit(time, :month)
    week = find_unit(time, :week)

    cond do
      is_integer(month) -> month_start(year, month, find_unit(time, :day), calendar)
      is_integer(week) -> week_date(year, week, find_unit(time, :day_of_week), calendar)
      true -> year_start(year, calendar)
    end
  end

  # The day a month, or a day of one, starts on. A month's first day is
  # asked of the calendar, which counts the months of a year that does not
  # begin with its first month from the day it begins
  # (`Tempo.UnitValues.start_date/2`).
  defp month_start(year, month, day, _calendar) when is_integer(day),
    do: month_date(year, month, day)

  defp month_start(year, month, _no_plain_day, calendar) do
    case UnitValues.start_date([year: year, month: month], calendar) do
      {:ok, {year, month, day}} -> month_date(year, month, day)
      :error -> month_date(year, month, nil)
    end
  end

  defp month_date(year, month, day) when is_integer(day),
    do: "#{year_text(year)}-#{two_digit(month)}-#{two_digit(day)}"

  defp month_date(year, month, _no_plain_day), do: "#{year_text(year)}-#{two_digit(month)}-01"

  # A year as ISO 8601 writes it, to four digits, and with a minus before
  # the year 0: the year 44 BCE is `-0043` there, and was written `-43`.
  defp year_text(year) when is_integer(year) and year < 0,
    do: "-" <> String.pad_leading(Integer.to_string(-year), 4, "0")

  defp year_text(year) when is_integer(year),
    do: String.pad_leading(Integer.to_string(year), 4, "0")

  # A week's first day, or the day of it a week date names. A calendar of
  # weeks writes its own week date; a month-based calendar's week is the day
  # Calendrical finds for it, written as that calendar's date.
  defp week_date(year, week, day_of_week, calendar) do
    day = if is_integer(day_of_week), do: day_of_week, else: 1

    with false <- Tempo.week_based_calendar?(calendar),
         {:ok, %Date{} = date} <- Validation.date_from_iso_week(year, week, day, calendar) do
      month_date(date.year, date.month, date.day)
    else
      _a_calendar_of_weeks_or_no_such_week -> "#{year_text(year)}-W#{two_digit(week)}-#{day}"
    end
  end

  # A year's first day, which in a calendar of weeks is the first day of its
  # first week.
  defp year_start(year, calendar) do
    if Tempo.week_based_calendar?(calendar),
      do: "#{year_text(year)}-W01-1",
      else: first_day_of_year(year, calendar)
  end

  defp first_day_of_year(year, calendar) do
    case UnitValues.start_date([year: year], calendar) do
      {:ok, {year, month, day}} -> month_date(year, month, day)
      :error -> "#{year_text(year)}-01-01"
    end
  end

  # ISO 8601 writes a yearless date `--MM-DD`, a yearless month `--MM`,
  # and a bare day `---DD`. Use the standard's own spelling so a span
  # reads as a date rather than as `?`.
  defp render_yearless_date(time) do
    m = find_unit(time, :month)
    d = find_unit(time, :day)

    cond do
      is_integer(m) and is_integer(d) -> "--#{two_digit(m)}-#{two_digit(d)}"
      is_integer(m) -> "--#{two_digit(m)}"
      is_integer(d) -> "---#{two_digit(d)}"
      true -> render_alternate_axis(time)
    end
  end

  # The yearless week and ordinal axes have their own ISO spellings.
  defp render_alternate_axis(time) do
    case find_unit(time, :day_of_year) do
      day when is_integer(day) -> "day #{day} of the year"
      _no_plain_ordinal -> render_week_axis(find_unit(time, :week), find_unit(time, :day_of_week))
    end
  end

  # ISO 8601's yearless week spellings, by which parts the value carries.
  defp render_week_axis(week, day) when is_integer(week) and is_integer(day),
    do: "-W#{two_digit(week)}-#{day}"

  defp render_week_axis(week, _day) when is_integer(week), do: "-W#{two_digit(week)}"
  defp render_week_axis(_week, day) when is_integer(day), do: "day #{day} of the week"
  defp render_week_axis(_week, _day), do: nil

  defp render_time_part(time) do
    h = Keyword.get(time, :hour)
    mi = Keyword.get(time, :minute)

    cond do
      is_integer(h) and is_integer(mi) -> "#{two_digit(h)}:#{two_digit(mi)}#{seconds_text(time)}"
      is_integer(h) -> "#{two_digit(h)}:00"
      is_integer(mi) -> "00:#{two_digit(mi)}#{seconds_text(time)}"
      true -> nil
    end
  end

  # An endpoint written with a time shift is at that shift from UTC, which
  # is part of the moment it names: `Z`, or the hours and minutes.
  defp render_shift(%Tempo{shift: [hour: 0]}), do: "Z"
  defp render_shift(%Tempo{shift: [_ | _] = shift}), do: shift_text(shift)
  defp render_shift(_no_shift), do: ""

  defp shift_text(shift) do
    sign = if Enum.any?(shift, fn {_unit, amount} -> amount < 0 end), do: "-", else: "+"
    sign <> Enum.map_join(shift, ":", fn {_unit, amount} -> two_digit(abs(amount)) end)
  end

  defp duration_prose(time) do
    time |> seconds_with_their_fraction() |> Enum.map_join(", ", &duration_component/1)
  end

  # A fraction of a second is held beside its seconds, with the number of
  # digits it was written to: `PT1.5S` is `[second: 1, microsecond:
  # {500_000, 1}]`, which is one and a half seconds and was worded "1
  # second, 0.5 seconds".
  defp seconds_with_their_fraction([{:second, seconds}, {:microsecond, {micro, digits}} | rest])
       when is_integer(seconds) and seconds >= 0 and is_integer(micro) and micro >= 0,
       do: [{:second, {seconds, micro, digits}} | rest]

  defp seconds_with_their_fraction([component | rest]),
    do: [component | seconds_with_their_fraction(rest)]

  defp seconds_with_their_fraction([]), do: []

  defp duration_component({:second, {seconds, micro, digits}}),
    do: "#{seconds}#{fraction_text({micro, max(digits, 1)})} seconds"

  # A fraction alone is stored as `{value, precision}`, so it cannot be
  # interpolated directly. It is written at its own precision: 500000 µs at
  # precision 1 is "0.5 seconds".
  defp duration_component({:microsecond, {value, precision}}) do
    seconds = value / 1_000_000
    "#{:erlang.float_to_binary(seconds, decimals: max(precision, 1))} seconds"
  end

  defp duration_component({unit, n}), do: "#{n} #{pluralise(unit, n)}"

  defp pluralise(unit, one) when one in [1, -1], do: Atom.to_string(unit)
  defp pluralise(unit, _), do: Atom.to_string(unit) <> "s"

  @months ~w(January February March April May June July August September October November December)

  # A month by its name where it has one, and by its number where it has not.
  defp month_name(month, naming) do
    case fetch_month_name(month, naming) do
      {:ok, name} -> name
      :error -> "month #{inspect(month)}"
    end
  end

  # A month's name in English, for the calendar and the year, if any, that name
  # it. The Gregorian calendar's are listed here; another calendar's are asked
  # of Localize, with the year when there is one, since a lunisolar calendar's
  # sixth month is Adar in one year and Adar I in the next. Such a month has no
  # one name without a year.
  defp fetch_month_name(month, {calendar, year}) when is_integer(month) do
    if gregorian_names?(calendar),
      do: gregorian_month_name(month),
      else: localized_month_name(month, calendar, year)
  end

  defp fetch_month_name(_set_or_group, _naming), do: :error

  defp gregorian_month_name(month) when month in 1..12, do: {:ok, Enum.at(@months, month - 1)}
  defp gregorian_month_name(_month), do: :error

  # A calendar of weeks has no named months of its own, so a month written in
  # one keeps the name it was written with.
  defp gregorian_names?(Calendrical.Gregorian), do: true
  defp gregorian_names?(calendar), do: Tempo.week_based_calendar?(calendar)

  defp localized_month_name(month, calendar, year) do
    with %{} = fields <- month_fields(month, calendar, year),
         {:ok, name} <- Localize.Date.to_string(fields, format: "MMMM", locale: :en) do
      {:ok, name}
    else
      _no_one_name -> :error
    end
  end

  defp month_fields(month, calendar, year) when is_integer(year),
    do: %{year: year, month: month, calendar: calendar}

  defp month_fields(month, calendar, _no_year) do
    if same_months_every_year?(calendar),
      do: %{month: month, calendar: calendar},
      else: :no_one_name
  end

  defp same_months_every_year?(calendar),
    do: match?({:ok, months, months}, UnitValues.in_any_year(:month, [], calendar))

  # What names the months of a rule's selection: its calendar and no year,
  # since it selects in each.
  defp rule_naming(%Tempo.Interval{repeat_rule: %Tempo{} = rule}), do: {calendar_of(rule), nil}
  defp rule_naming(%Tempo.Interval{}), do: {Calendrical.Gregorian, nil}

  defp two_digit(n) when is_integer(n) and n >= 0 and n < 10, do: "0#{n}"
  defp two_digit(n) when is_integer(n), do: Integer.to_string(n)
  defp two_digit(_), do: "??"

  # ── Recurrence + selection prose ───────────────────────────────

  # The units after a selection (`L5K2INT9H`) read as part of it: "on the
  # 2nd Friday, at 09:00".
  defp selection_of(%Tempo{time: [{:selection, selection} | units]}), do: selection ++ units
  defp selection_of(_), do: nil

  defp recurrence_headline(:infinity), do: "An unbounded recurrence."
  defp recurrence_headline(n) when is_integer(n), do: "A recurrence of #{n} occurrences."

  defp open_start_hint do
    "The rule names no start of its own. List its occurrences within a window " <>
      "— `Tempo.to_interval(interval, within: ~o\"2026\")` " <>
      "lists the occurrences that fall inside it — or give the literal a " <>
      "start (`R/2026-01-01/…`) or re-parse with one " <>
      "(`Tempo.RRule.parse(rule, from: ~o\"2026-01-01\")`)."
  end

  defp recurrence_hint(:infinity, from),
    do:
      "List a window of occurrences: `Tempo.to_interval(interval, within: #{window_example(from)})`."

  defp recurrence_hint(n, _from) when is_integer(n),
    do: "List the #{n} occurrences: `Tempo.to_interval(interval)`."

  defp window_example(%Tempo{time: time}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> "~o\"#{year}\""
      _year -> "~o\"2026\""
    end
  end

  # Render a BY-rule selection as an English phrase — e.g.
  # `[month: 11, day: [2..8], day_of_week: 2]` becomes "in November, on
  # the 2nd–8th, on a Tuesday" (US Election Day).
  defp selection_prose(selection, naming) do
    case split_at_interval(selection) do
      {scope, window, within} -> windowed_prose(scope, window, within, naming)
      :none -> flat_selection_prose(selection, naming)
    end
  end

  defp flat_selection_prose(selection, naming) do
    selection
    |> Enum.reject(fn {key, _value} -> key == :origin_day end)
    |> fuse_ordinal_weekday()
    |> fuse_time_of_day()
    |> Enum.flat_map(fn entry -> List.wrap(selection_clause(entry, naming)) end)
    |> Enum.join(", ")
  end

  # Split a selection around a §12.10 window into `{scope, window, within}`.
  defp split_at_interval(selection) do
    case Enum.split_while(selection, fn {key, _value} -> key != :interval end) do
      {scope, [{:interval, %Tempo.Interval{} = window} | within]} -> {scope, window, within}
      _other -> :none
    end
  end

  # ISO 8601-2 §12.10: "the last Friday within the 7 days before Easter". The
  # window is `[duration] before|from [inner]`, and the outer selectors pick
  # within it; a terminal window (no outer selectors) is described on its own.
  defp windowed_prose(scope, %Tempo.Interval{from: inner, duration: duration}, within, naming) do
    window = window_phrase(duration, selection_noun(scope ++ inner_selection_of(inner), naming))

    case Enum.reject(within, fn {key, _value} -> key in [:origin_day, :wkst, :skip] end) do
      [] -> window
      selectors -> "#{flat_selection_prose(selectors, naming)} within #{window}"
    end
  end

  defp inner_selection_of(%Tempo{time: [selection: selection]}), do: selection
  defp inner_selection_of(%Tempo{time: time}), do: time

  # A window of hours, minutes or seconds is worded in them (`PT4H` from
  # 22:00 is "the 4 hours from 22:00"). It was worded in ISO 8601, "the PT4H
  # window", which the reader of an explanation is not asked to know.
  defp window_phrase(%Tempo.Duration{time: time}, inner_noun) do
    cond do
      not only_day_or_week?(time) and before?(time) ->
        "the #{duration_prose(lengths(time))} before #{inner_noun}"

      not only_day_or_week?(time) ->
        "the #{duration_prose(time)} from #{inner_noun}"

      offset_in_days(time) < 0 ->
        "the #{day_count(-offset_in_days(time))} before #{inner_noun}"

      offset_in_days(time) > 0 ->
        "the #{day_count(offset_in_days(time))} from #{inner_noun}"

      true ->
        inner_noun
    end
  end

  # A resolved inner selection as a bare noun phrase, for embedding in a window.
  defp selection_noun([{:event, name}], _naming), do: event_phrase(name)
  defp selection_noun([{:month, m}], naming), do: month_name(m, naming)

  defp selection_noun([{:month, m}, {:day, d}], naming) when is_integer(d),
    do: "#{month_name(m, naming)} #{d}"

  defp selection_noun([{:day_of_week, wd}, {:instance, i}], _naming)
       when is_integer(wd) and is_integer(i),
       do: "the #{ordinal(i)} #{weekday_name(wd)}"

  defp selection_noun([{:month, m}, {:day_of_week, wd}, {:instance, i}], naming)
       when is_integer(wd) and is_integer(i),
       do: "the #{ordinal(i)} #{weekday_name(wd)} of #{month_name(m, naming)}"

  # A time of day is "at 22:00" as a clause and "22:00" as what a window
  # runs from: "the 2 days from at 22:00" is "the 2 days from 22:00".
  defp selection_noun(other, naming) do
    case flat_selection_prose(other, naming) do
      "on " <> rest -> rest
      "in " <> rest -> rest
      "at " <> rest -> rest
      prose -> prose
    end
  end

  defp only_day_or_week?(time),
    do: Enum.all?(time, fn {unit, _value} -> unit in [:day, :week] end)

  # A window that runs back from its selection is written with each unit
  # negative, and worded by their lengths.
  defp before?(time),
    do: Enum.all?(time, fn {_unit, value} -> is_integer(value) and value < 0 end)

  defp lengths(time), do: Enum.map(time, fn {unit, value} -> {unit, abs(value)} end)

  defp offset_in_days(time) do
    Enum.reduce(time, 0, fn
      {:day, n}, acc when is_integer(n) -> acc + n
      {:week, n}, acc when is_integer(n) -> acc + Calendrical.weeks_to_days(n)
      _entry, acc -> acc
    end)
  end

  defp day_count(1), do: "1 day"
  defp day_count(n), do: "#{n} days"

  # A single-weekday `day_of_week` immediately followed by `instance` is the
  # ISO 8601-2 §12.9 position form of an ordinal weekday ("the 4th Thursday").
  # Fuse the pair back into a `:byday` clause so the prose reads "on the 4th
  # Thursday" rather than "on a Thursday, keeping the 4th occurrence". A
  # multi-weekday `day_of_week` is a genuine set-position over several weekdays
  # and is left as separate clauses.
  defp fuse_ordinal_weekday([{:day_of_week, weekday}, {:instance, positions} | rest])
       when is_integer(weekday) do
    [{:byday, ordinal_weekday_pairs(weekday, positions)} | fuse_ordinal_weekday(rest)]
  end

  defp fuse_ordinal_weekday([entry | rest]), do: [entry | fuse_ordinal_weekday(rest)]
  defp fuse_ordinal_weekday([]), do: []

  # Each position with the weekday. A range of positions that reaches the
  # end of its period ("the 2nd to the last Monday") is kept as it is: which
  # positions it names depends on the period.
  defp ordinal_weekday_pairs(weekday, positions) do
    positions |> List.wrap() |> Enum.flat_map(&positions_of/1) |> Enum.map(&{&1, weekday})
  end

  defp positions_of(%Range{} = range),
    do: if(reaches_the_end?(range), do: [range], else: Enum.to_list(range))

  defp positions_of(position), do: [position]

  # The hours, minutes and seconds of a selection are one time of day. One
  # written with unspecified digits is worded as it is written, on its own.
  defp fuse_time_of_day([{_unit, {:mask, _mask}} = entry | rest]),
    do: [entry | fuse_time_of_day(rest)]

  defp fuse_time_of_day([{unit, _value} = first | rest]) when unit in [:hour, :minute, :second] do
    {finer, rest} = Enum.split_while(rest, &unit_in?(&1, [:minute, :second]))
    [{:time_of_day, [first | finer]} | fuse_time_of_day(rest)]
  end

  defp fuse_time_of_day([entry | rest]), do: [entry | fuse_time_of_day(rest)]
  defp fuse_time_of_day([]), do: []

  # A part written with unspecified digits stands for each value of its unit
  # the digits match, which depend on the period, and is worded as written.
  defp selection_clause({unit, {:mask, mask}}, _naming),
    do: "#{masked_unit_phrase(unit)} written #{mask_text(mask)}"

  # A month is named in the selection's calendar, and a weekday and a time
  # of day are counted in it; no other clause needs it.
  defp selection_clause({:month, months}, naming), do: "in #{months_phrase(months, naming)}"

  defp selection_clause({:day_of_week, weekdays}, {calendar, _year}),
    do: "on a #{weekdays_phrase(weekdays, calendar)}"

  defp selection_clause({:byday, pairs}, {calendar, _year}),
    do: "on #{byday_phrase(pairs, calendar)}"

  defp selection_clause({:time_of_day, clock}, {calendar, _year}),
    do: "at #{time_of_day_phrase(clock, calendar)}"

  defp selection_clause(entry, _naming), do: selection_clause(entry)

  defp selection_clause({:traditional_month, {n, :leap}}),
    do: "in the leap month after traditional month #{n}"

  defp selection_clause({:traditional_month, m}) when is_integer(m),
    do: "in traditional month #{m}"

  defp selection_clause({:wkst, w}), do: "with weeks starting on #{weekday_name(w)}"

  defp selection_clause({:skip, :forward}),
    do: "on the first day of the month after where a month lacks the day"

  defp selection_clause({:skip, :backward}),
    do: "on the last day of a month that lacks the day"

  defp selection_clause({:day, d}), do: "on #{ordinals_phrase(d)}"
  defp selection_clause({:week, w}), do: "in #{ordinals_phrase(w)} ISO week"
  defp selection_clause({:calendar_week, w}), do: "in #{ordinals_phrase(w)} calendar week"

  defp selection_clause({:week_of_month, w}),
    do: "in #{ordinals_phrase(w)} week of the month"

  defp selection_clause({:day_of_year, d}), do: "on #{ordinals_phrase(d)} day of the year"
  defp selection_clause({:instance, p}), do: "keeping #{ordinals_phrase(p)} occurrence"
  defp selection_clause({:event, name}), do: "on #{event_phrase(name)}"
  defp selection_clause({_other, _value}), do: []

  # Humanise a computed-event name: `"easter"` → "Easter"; a hyphenated
  # astronomical event → "the March equinox", and one taking its date in a zone
  # → "the March equinox in +09:00". An unknown name still reads sensibly ("the
  # winter-fair event") so `explain/1` never fails on one.
  defp event_phrase("easter"), do: "Easter"
  defp event_phrase("orthodox-easter"), do: "Orthodox Easter"

  defp event_phrase(name) when is_binary(name) do
    case String.split(name, "@", parts: 2) do
      [event, zone] -> "#{event_phrase(event)} in #{zone}"
      [event] -> unzoned_event_phrase(event)
    end
  end

  defp unzoned_event_phrase(name) do
    cond do
      match?([_month, kind] when kind in ["equinox", "solstice"], String.split(name, "-")) ->
        [month, kind] = String.split(name, "-")
        "the #{String.capitalize(month)} #{kind}"

      Event.solar_term?(name) ->
        "the #{String.capitalize(name)} solar term"

      true ->
        "the #{String.replace(name, "-", " ")} event"
    end
  end

  defp byday_phrase(pairs, calendar) do
    pairs
    |> Enum.map(fn
      {nil, weekday} ->
        "a #{named_weekdays_phrase(weekday, calendar)}"

      {position, weekday} ->
        "the #{position_phrase(position)} #{named_weekdays_phrase(weekday, calendar)}"
    end)
    |> or_join()
  end

  defp position_phrase(%Range{first: first, last: last}),
    do: "#{ordinal(first)} to the #{ordinal(last)}"

  defp position_phrase(position), do: ordinal(position)

  # ── What a selection's values are called ──────────────────────
  #
  # A weekday, an hour, a minute and a second take the same values whatever
  # comes before them, so `Tempo.UnitValues` counts what is written: a count
  # from the end is the value it names (`-1K` is Sunday) and a range that
  # reaches the end is each of its values (`T{22..-1}H` is 22:00 and 23:00).
  # A month is counted where its year's months can be. A day, a week, a day
  # of the year and a position are counted in a period the selection alone
  # does not fix (a rule selects in each), so a count from the end is worded
  # as it is written: "the last", "the 28th to the last".

  # The values a written value names among those a unit always takes, or
  # `:as_written` where it names one the unit does not take.
  defp counted(written, unit, calendar) do
    case UnitValues.in_period(unit, [], calendar) do
      {:ok, values} -> counted_among(written, values)
      {:error, _depends_on_the_date} -> :as_written
    end
  end

  defp counted_among(written, values) do
    with {:ok, _each_is_taken} <- UnitValues.resolve(List.wrap(written), values),
         [_ | _] = named <- UnitValues.named(written, values) do
      {:ok, named}
    else
      _one_is_not_taken -> :as_written
    end
  end

  # A selection's days of the week by name: each is a day of the week of the
  # selection's calendar, and the weekday it names there is asked of
  # `Tempo.UnitValues` (the third day of a week that starts on Sunday is
  # Tuesday).
  defp weekdays_phrase(written, calendar) do
    case counted(written, :day_of_week, calendar) do
      {:ok, days} -> days |> Enum.map(&day_of_week_name(&1, calendar)) |> or_join()
      :as_written -> weekday_name(written)
    end
  end

  defp day_of_week_name(day, calendar),
    do: day |> UnitValues.iso_weekday_from_day_of_week(calendar) |> weekday_name()

  # An RRULE's BYDAY names its weekdays themselves, Monday the first, in
  # whatever calendar the rule is resolved.
  defp named_weekdays_phrase(written, calendar) do
    case counted(written, :day_of_week, calendar) do
      {:ok, weekdays} -> weekdays |> Enum.map(&weekday_name/1) |> or_join()
      :as_written -> weekday_name(written)
    end
  end

  # The months a selection names, by name where the calendar counts the
  # months of the selection's year, or of every year alike.
  defp months_phrase(written, {calendar, year} = naming) do
    with {:ok, months_of_year} <- months_of(calendar, year),
         {:ok, months} <- counted_among(written, months_of_year) do
      months |> Enum.map(&month_name(&1, naming)) |> or_join()
    else
      _counted_by_the_year ->
        written |> List.wrap() |> Enum.flat_map(&month_as_written(&1, naming)) |> or_join()
    end
  end

  defp months_of(calendar, year) when is_integer(year),
    do: UnitValues.in_period(:month, [year: year], calendar)

  defp months_of(calendar, _no_year) do
    case UnitValues.in_any_year(:month, [], calendar) do
      {:ok, months, months} -> {:ok, months}
      _by_the_year_or_cannot_say -> :error
    end
  end

  defp month_as_written(month, naming) when is_integer(month) and month > 0,
    do: [month_name(month, naming)]

  defp month_as_written(month, _naming) when is_integer(month),
    do: ["the #{ordinal(month)} month"]

  defp month_as_written(%Range{first: first, last: last, step: step} = range, naming) do
    cond do
      not reaches_the_end?(range) ->
        range |> Enum.to_list() |> Enum.flat_map(&month_as_written(&1, naming))

      step == 1 ->
        ["#{month_name(first, naming)} to the #{ordinal(last)} month"]

      true ->
        [
          "every #{ordinal(step)} month from #{month_name(first, naming)} to the #{ordinal(last)} month"
        ]
    end
  end

  defp month_as_written(other, naming), do: [month_name(other, naming)]

  # A time of day: each hour with each minute and second, "09:30 or 17:30".
  # A selection with no hour selects in each: "minute 30 of each hour".
  defp time_of_day_phrase(clock, calendar) do
    counted = Enum.map(clock, fn {unit, written} -> {unit, counted(written, unit, calendar)} end)

    if Enum.all?(counted, &match?({_unit, {:ok, _values}}, &1)),
      do:
        counted |> Enum.map(fn {unit, {:ok, values}} -> {unit, values} end) |> clock_phrase_of(),
      else:
        Enum.map_join(clock, ", ", fn {unit, written} -> "#{unit} #{written_phrase(written)}" end)
  end

  defp clock_phrase_of([{:hour, hours} | finer]) do
    times =
      for hour <- hours, rest <- finer_times(finer) do
        Enum.map_join([hour | rest], ":", &two_digit/1) <> if(rest == [], do: ":00", else: "")
      end

    times_phrase(times, "times of day")
  end

  defp clock_phrase_of([{:minute, minutes}]),
    do: "minute #{number_list(minutes)} of each hour"

  defp clock_phrase_of([{:minute, _minutes}, {:second, _seconds}] = finer) do
    times = for time <- finer_times(finer), do: Enum.map_join(time, ":", &two_digit/1)
    times_phrase(times, "times") <> " past each hour"
  end

  defp clock_phrase_of([{:second, seconds}]),
    do: "second #{number_list(seconds)} of each minute"

  # Each minute with each second, as the numbers that follow an hour.
  defp finer_times([]), do: [[]]

  defp finer_times([{_unit, values} | finer]),
    do: for(value <- values, rest <- finer_times(finer), do: [value | rest])

  # A handful of times are each named, and more are counted.
  defp times_phrase(times, noun), do: times_phrase(times, noun, length(times))

  defp times_phrase(times, _noun, count) when count <= 12, do: or_join(times)

  defp times_phrase(times, noun, count),
    do: "#{count} #{noun} from #{hd(times)} to #{List.last(times)}"

  defp number_list(numbers), do: numbers |> Enum.map(&Integer.to_string/1) |> or_join()

  defp written_phrase(written) when is_list(written),
    do: written |> Enum.map(&written_phrase/1) |> and_join()

  defp written_phrase(%Range{first: first, last: last, step: 1}), do: "#{first} to #{last}"

  defp written_phrase(%Range{first: first, last: last, step: step}),
    do: "#{first} to #{last} by #{step}"

  defp written_phrase(other), do: inspect(other)

  # Ordinal-list phrase — a contiguous run collapses to a range:
  defp masked_unit_phrase(:month), do: "in a month"
  defp masked_unit_phrase(:week), do: "in an ISO week"
  defp masked_unit_phrase(:calendar_week), do: "in a calendar week"
  defp masked_unit_phrase(:week_of_month), do: "in a week of the month"
  defp masked_unit_phrase(:day), do: "on a day"
  defp masked_unit_phrase(:day_of_year), do: "on a day of the year"
  defp masked_unit_phrase(:day_of_week), do: "on a day of the week"
  defp masked_unit_phrase(:hour), do: "at an hour"
  defp masked_unit_phrase(unit) when unit in [:minute, :second], do: "at a #{unit}"
  defp masked_unit_phrase(unit), do: "in a #{unit}"

  # A mask as it is written: its digits, an `X` for each left out, and a set
  # of digits in braces.
  defp mask_text(mask), do: Enum.map_join(mask, &mask_digit/1)

  defp mask_digit(:X), do: "X"
  defp mask_digit(:negative), do: "-"
  defp mask_digit(digit) when is_integer(digit), do: Integer.to_string(digit)
  defp mask_digit(digits) when is_list(digits), do: "{" <> Enum.join(digits, ",") <> "}"
  defp mask_digit(other), do: inspect(other)

  # `[2..8]` → "the 2nd–8th"; `[1, 15]` → "the 1st and 15th". Those counted
  # from the end follow those counted from the start ("the 1st, 15th, and
  # last"), and a range that reaches the end is worded by its ends ("the
  # 28th to the last").
  defp ordinals_phrase(value) do
    {reaching, plain} = value |> List.wrap() |> Enum.split_with(&reaches_the_end?/1)

    and_join(plain_ordinals(plain) ++ Enum.map(reaching, &reaching_ordinals/1))
  end

  defp plain_ordinals(members) do
    case members |> Enum.flat_map(&expand_int/1) |> Enum.sort_by(&{&1 < 0, &1}) do
      [] ->
        []

      [n] ->
        ["the #{ordinal(n)}"]

      [lo | _] = list ->
        hi = List.last(list)

        if match?([_, _, _ | _], list) and hi - lo + 1 == length(list),
          do: ["the #{ordinal(lo)}–#{ordinal(hi)}"],
          else: ["the " <> and_join(Enum.map(list, &ordinal/1))]
    end
  end

  # Whether a range runs from a value counted from the start to one counted
  # from the end, so that the values it names depend on the period.
  defp reaches_the_end?(%Range{first: first, last: last}), do: first >= 0 and last < 0
  defp reaches_the_end?(_member), do: false

  defp reaching_ordinals(%Range{first: first, last: last, step: 1}),
    do: "the #{ordinal(first)} to the #{ordinal(last)}"

  defp reaching_ordinals(%Range{first: first, last: last, step: step}),
    do: "every #{ordinal(step)} from the #{ordinal(first)} to the #{ordinal(last)}"

  defp expand_int(%Range{} = range), do: Enum.to_list(range)
  defp expand_int(n) when is_integer(n), do: [n]

  defp ordinal(-1), do: "last"
  defp ordinal(n) when is_integer(n) and n < 0, do: "#{ordinal(-n)}-to-last"

  defp ordinal(n) when is_integer(n) do
    suffix =
      cond do
        rem(n, 100) in 11..13 -> "th"
        rem(n, 10) == 1 -> "st"
        rem(n, 10) == 2 -> "nd"
        rem(n, 10) == 3 -> "rd"
        true -> "th"
      end

    "#{n}#{suffix}"
  end

  @weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  defp weekday_name(n) when is_integer(n) and n in 1..7, do: Enum.at(@weekdays, n - 1)
  defp weekday_name(other), do: "weekday #{inspect(other)}"

  defp or_join([]), do: "nothing"
  defp or_join([one]), do: one

  defp or_join(list) do
    {init, [last]} = Enum.split(list, -1)
    Enum.join(init, ", ") <> " or " <> last
  end

  defp and_join([]), do: "nothing"
  defp and_join([one]), do: one
  defp and_join([first, second]), do: "#{first} and #{second}"

  defp and_join(list) do
    {init, [last]} = Enum.split(list, -1)
    Enum.join(init, ", ") <> ", and " <> last
  end
end
