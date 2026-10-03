defmodule Tempo.Matrix.Spellings do
  @moduledoc """
  A core value written in each form ISO 8601 gives it (see
  `plans/validated-core.md`).

  ISO 8601-1 writes a date and a time of day in a basic format, digits
  alone (`20260615T103045`), and an extended format, with separators
  (`2026-06-15T10:30:45`). ISO 8601-2 adds the explicit form, each unit
  with its designator (`2026Y6M15DT10H30M45S`). A datum of
  `Tempo.Matrix.Reference` is written here in each, with its zone in each
  form a zone takes and its calendar as an IXDTF suffix, so that every
  spelling can be read back and held to the one value the datum is.

  """

  alias Tempo.Matrix.Reference

  @type form :: :extended | :basic | :explicit

  @doc """
  The texts a point is written as.

  ### Arguments

  * `point` is a `t:Tempo.Matrix.Reference.point/0`.

  ### Returns

  * A list of `{form, text}` with no text twice. A form the standard has
    no spelling in is left out: a year and a month have no basic format,
    since `202606` would be read as a date with a two-digit year.

  """
  @spec texts(Reference.point()) :: [{form(), String.t()}]
  def texts(point) do
    for(
      form <- [:extended, :basic, :explicit],
      date = date(form, point.date),
      time <- times(form, point),
      zone <- zones(form, point.zone),
      do: {form, date <> time <> zone <> calendar(point.calendar)}
    )
    |> Enum.uniq_by(&elem(&1, 1))
  end

  @doc """
  One text a point is written as, in a form.

  ### Arguments

  * `point` is a `t:Tempo.Matrix.Reference.point/0`.

  * `form` is `:extended`, `:basic` or `:explicit`.

  ### Returns

  * The text, or `nil` when the form has no spelling of the point.

  """
  @spec text(Reference.point(), form()) :: String.t() | nil
  def text(point, form) do
    with date when is_binary(date) <- date(form, point.date),
         [time | _others] <- times(form, point),
         [zone | _others] <- zones(form, point.zone) do
      date <> time <> zone <> calendar(point.calendar)
    else
      _no_spelling -> nil
    end
  end

  @doc """
  A point's date in a form, with no time, zone or calendar.

  ### Arguments

  * `form` is `:extended`, `:basic` or `:explicit`.

  * `date` is the `:date` of a `t:Tempo.Matrix.Reference.point/0`.

  ### Returns

  * The text, `""` for no date, or `nil` when the form has no spelling.

  """
  @spec date(form(), keyword(integer())) :: String.t() | nil
  def date(_form, []), do: ""

  def date(:extended, year: year), do: year(year)
  def date(:extended, year: year, month: month), do: "#{year(year)}-#{pad(month, 2)}"

  def date(:extended, year: year, month: month, day: day),
    do: "#{year(year)}-#{pad(month, 2)}-#{pad(day, 2)}"

  def date(:extended, year: year, week: week), do: "#{year(year)}-W#{pad(week, 2)}"

  def date(:extended, year: year, week: week, day_of_week: day),
    do: "#{year(year)}-W#{pad(week, 2)}-#{day}"

  def date(:extended, year: year, day_of_year: day), do: "#{year(year)}-#{pad(day, 3)}"

  def date(:basic, year: year), do: year(year)
  def date(:basic, year: _year, month: _month), do: nil

  def date(:basic, year: year, month: month, day: day),
    do: "#{year(year)}#{pad(month, 2)}#{pad(day, 2)}"

  def date(:basic, year: year, week: week), do: "#{year(year)}W#{pad(week, 2)}"

  def date(:basic, year: year, week: week, day_of_week: day),
    do: "#{year(year)}W#{pad(week, 2)}#{day}"

  def date(:basic, year: year, day_of_year: day), do: "#{year(year)}#{pad(day, 3)}"

  def date(:explicit, units) do
    Enum.map_join(units, fn {unit, value} -> "#{value}#{designator(unit)}" end)
  end

  defp designator(:year), do: "Y"
  defp designator(:month), do: "M"
  defp designator(:day), do: "D"
  defp designator(:week), do: "W"
  defp designator(:day_of_week), do: "K"
  defp designator(:day_of_year), do: "O"

  # A time of day in a form: with its designator, in each decimal sign for
  # a fraction, and, in the extended format with no date, without the
  # designator too (ISO 8601-1 §5.3.5) where no other reading is at risk.
  defp times(_form, %{time: []}), do: [""]

  defp times(form, %{time: time, fraction: fraction, date: date}) do
    clock = clock(form, time)

    for fraction <- fractions(form, fraction),
        prefix <- prefixes(form, time, date) do
      prefix <> clock <> fraction <> second_designator(form, time)
    end
  end

  defp clock(:extended, hour: hour), do: pad(hour, 2)
  defp clock(:extended, hour: hour, minute: minute), do: "#{pad(hour, 2)}:#{pad(minute, 2)}"

  defp clock(:extended, hour: hour, minute: minute, second: second),
    do: "#{pad(hour, 2)}:#{pad(minute, 2)}:#{pad(second, 2)}"

  defp clock(:basic, time), do: Enum.map_join(time, fn {_unit, value} -> pad(value, 2) end)

  defp clock(:explicit, hour: hour), do: "#{hour}H"
  defp clock(:explicit, hour: hour, minute: minute), do: "#{hour}H#{minute}M"

  defp clock(:explicit, hour: hour, minute: minute, second: second),
    do: "#{hour}H#{minute}M#{second}"

  # The explicit form's second takes its designator after any fraction.
  defp second_designator(:explicit, hour: _, minute: _, second: _), do: "S"
  defp second_designator(_form, _time), do: ""

  defp fractions(_form, nil), do: [""]
  defp fractions(:explicit, {value, digits}), do: [".#{pad(value, digits)}"]

  defp fractions(_form, {value, digits}),
    do: [".#{pad(value, digits)}", ",#{pad(value, digits)}"]

  defp prefixes(:extended, [{:hour, _hour}, {:minute, _minute} | _rest], []), do: ["T", ""]
  defp prefixes(_form, _time, _date), do: ["T"]

  # A zone in a form: `Z`, an offset with and (when it is whole hours)
  # without its minutes, or a named zone as an IXDTF suffix. The explicit
  # form writes an offset after `Z`, with a sign only when it is behind
  # UTC (ISO 8601-2 §7.4).
  defp zones(_form, nil), do: [""]
  defp zones(_form, :utc), do: ["Z"]
  defp zones(_form, {:zone, name}), do: ["[#{name}]"]

  defp zones(form, {:offset, minutes}) do
    sign = if minutes < 0, do: "-", else: "+"
    {hours, minutes} = {div(abs(minutes), 60), rem(abs(minutes), 60)}
    whole = if minutes == 0, do: [offset(form, sign, hours)], else: []
    [offset(form, sign, hours, minutes) | whole]
  end

  defp offset(:explicit, "-", hours), do: "Z-#{hours}H"
  defp offset(:explicit, "+", hours), do: "Z#{hours}H"
  defp offset(_form, sign, hours), do: sign <> pad(hours, 2)

  defp offset(:explicit, "-", hours, minutes), do: "Z-#{hours}H#{minutes}M"
  defp offset(:explicit, "+", hours, minutes), do: "Z#{hours}H#{minutes}M"
  defp offset(:extended, sign, hours, minutes), do: "#{sign}#{pad(hours, 2)}:#{pad(minutes, 2)}"
  defp offset(:basic, sign, hours, minutes), do: "#{sign}#{pad(hours, 2)}#{pad(minutes, 2)}"

  defp calendar(Calendrical.Gregorian), do: ""
  # The calendar's BCP 47 name, which is its CLDR type with hyphens:
  # `islamic-civil`.
  defp calendar(calendar) do
    name = calendar.cldr_calendar_type() |> Atom.to_string() |> String.replace("_", "-")
    "[u-ca=#{name}]"
  end

  # A year from 0 to 9999 is four digits in the basic and extended formats.
  defp year(year) when year in 0..9999, do: pad(year, 4)

  defp pad(value, width), do: value |> Integer.to_string() |> String.pad_leading(width, "0")

  ## Intervals

  @doc """
  The texts an interval from one point to another is written as: both
  ends in each form, the end with the units it shares with the start left
  out (ISO 8601-1 §5.5.1), and the start or the end with the duration
  between them.

  ### Arguments

  * `from` and `to` are `t:Tempo.Matrix.Reference.point/0` written in the
    same units, `to` after `from`.

  * `count` is the units of their last unit from one to the other.

  ### Returns

  * A list of `{form, text}` with no text twice.

  """
  @spec interval_texts(Reference.point(), Reference.point(), pos_integer()) ::
          [{atom(), String.t()}]
  def interval_texts(from, to, count) do
    whole =
      for form <- [:extended, :basic, :explicit],
          from_text = text(from, form),
          to_text = text(to, form),
          do: {form, from_text <> "/" <> to_text}

    lasting = lasting(from, count)

    by_duration =
      for form <- [:extended, :explicit],
          from_text = text(from, form),
          to_text = text(to, form),
          spelling <- [
            {:"#{form}_start_and_duration", from_text <> "/" <> lasting},
            {:"#{form}_duration_and_end", lasting <> "/" <> to_text}
          ],
          do: spelling

    Enum.uniq_by(whole ++ abbreviated(from, to) ++ by_duration, &elem(&1, 1))
  end

  # The duration from one end to the other, in the unit they are written to.
  defp lasting(%{date: date, time: time}, count) do
    {unit, _value} = List.last(date ++ time)
    duration([{duration_unit(unit), count}])
  end

  defp duration_unit(unit) when unit in [:day_of_week, :day_of_year], do: :day
  defp duration_unit(unit), do: unit

  # The end with each run of the leading units it shares with the start
  # left out. Something of the end must be left, and what is left must be
  # read as what it is: a year's end is its whole year.
  defp abbreviated(%{date: from_date, time: from_time} = from, %{date: to_date} = to) do
    shared = shared_prefix(from_date ++ from_time, to_date ++ to.time)

    for omitted <- 1..length(shared)//1,
        omitted < length(to_date ++ to.time),
        form <- [:extended, :explicit],
        from_text = text(from, form),
        ending = ending(form, to, omitted),
        do: {:"#{form}_abbreviated", from_text <> "/" <> ending}
  end

  defp shared_prefix([unit | from], [unit | to]), do: [unit | shared_prefix(from, to)]
  defp shared_prefix(_from, _to), do: []

  # An end with its first `omitted` units left out, or `nil` for one the
  # form has no writing of.
  defp ending(:explicit, %{date: date, time: time}, omitted),
    do: explicit_ending(Enum.drop(date, omitted), kept_time(date, time, omitted))

  defp ending(:extended, %{date: date, time: time}, omitted),
    do: extended_ending(Enum.drop(date, omitted), kept_time(date, time, omitted), time)

  defp kept_time(date, time, omitted), do: Enum.drop(time, max(omitted - length(date), 0))

  defp explicit_ending(date, time) do
    date(:explicit, date) <> explicit_time(time)
  end

  defp explicit_time([]), do: ""

  defp explicit_time(time) do
    "T" <> Enum.map_join(time, fn {unit, value} -> "#{value}#{time_designator(unit)}" end)
  end

  defp time_designator(:hour), do: "H"
  defp time_designator(:minute), do: "M"
  defp time_designator(:second), do: "S"

  # A month and a day, a day, or a week and its day, then the time of day
  # in full or from the unit it is left with.
  defp extended_ending([month: month, day: day], time, _whole),
    do: "#{pad(month, 2)}-#{pad(day, 2)}" <> extended_time(time)

  defp extended_ending([month: month], [], _whole), do: pad(month, 2)
  defp extended_ending([day: day], time, _whole), do: pad(day, 2) <> extended_time(time)
  defp extended_ending([week: week], [], _whole), do: "W#{pad(week, 2)}"

  defp extended_ending([week: week, day_of_week: day], [], _whole),
    do: "W#{pad(week, 2)}-#{day}"

  defp extended_ending([day_of_week: day], [], _whole), do: Integer.to_string(day)
  defp extended_ending([day_of_year: day], [], _whole), do: pad(day, 3)

  # A time of day in full is written with or without its designator; one
  # with its hour left out is the bare number of what is left.
  defp extended_ending([], time, time) when time != [], do: "T" <> clock(:extended, time)

  defp extended_ending([], [{_unit, value}], _whole), do: pad(value, 2)

  # A minute and a second with their hour left out would be read as an hour
  # and a minute, so they are not written so.
  defp extended_ending(_date, _time, _whole), do: nil

  defp extended_time([]), do: ""
  defp extended_time(time), do: "T" <> clock(:extended, time)

  ## Durations

  @doc """
  The texts a duration is written as: with designators, and, when every
  unit fits the digits a date has, in the alternative format ISO 8601-1
  §5.5.2.4 writes as a date and time.

  ### Arguments

  * `units` is a keyword list of a duration's units in order, largest
    first, each a whole number that is not negative.

  ### Returns

  * A list of `{form, text}`.

  """
  @spec duration_texts(keyword(non_neg_integer())) :: [{atom(), String.t()}]
  def duration_texts(units) do
    [{:designators, duration(units)} | alternative(units)]
  end

  @doc """
  A duration written with designators.

  ### Arguments

  * `units` is a keyword list of a duration's units in order.

  ### Returns

  * The text, such as `P1Y2M3DT4H5M6S`.

  """
  @spec duration(keyword(integer())) :: String.t()
  def duration(units) do
    {date, time} =
      Enum.split_while(units, fn {unit, _value} -> unit in [:year, :month, :week, :day] end)

    "P" <> written(date) <> if(time == [], do: "", else: "T" <> written(time))
  end

  defp written(units) do
    Enum.map_join(units, fn {unit, value} -> "#{value}#{duration_designator(unit)}" end)
  end

  defp duration_designator(:year), do: "Y"
  defp duration_designator(:month), do: "M"
  defp duration_designator(:week), do: "W"
  defp duration_designator(:day), do: "D"
  defp duration_designator(:hour), do: "H"
  defp duration_designator(:minute), do: "M"
  defp duration_designator(:second), do: "S"

  # The alternative format writes a duration as a date and a time of day
  # (ISO 8601-1 §5.5.2.4), so it has every unit from the year to the second,
  # no weeks, and each unit within the digits and the range a date and time
  # give it.
  defp alternative(units) do
    if Keyword.has_key?(units, :week) or not written_as_date?(units) do
      []
    else
      [y, mo, d, h, mi, s] =
        for unit <- [:year, :month, :day, :hour, :minute, :second],
            do: Keyword.get(units, unit, 0)

      [
        {:alternative_extended,
         "P#{pad(y, 4)}-#{pad(mo, 2)}-#{pad(d, 2)}T#{pad(h, 2)}:#{pad(mi, 2)}:#{pad(s, 2)}"},
        {:alternative_basic,
         "P#{pad(y, 4)}#{pad(mo, 2)}#{pad(d, 2)}T#{pad(h, 2)}#{pad(mi, 2)}#{pad(s, 2)}"}
      ]
    end
  end

  defp written_as_date?(units) do
    limits = [year: 9999, month: 12, day: 30, hour: 23, minute: 59, second: 59]
    Enum.all?(units, fn {unit, value} -> value <= limits[unit] end)
  end
end
