defmodule Tempo.ChangeOfTheClock do
  @moduledoc false

  # Days on which a zone's clock changes, what Elixir's own `DateTime` says
  # the clock showed on each, and what Tempo gives for the same day.
  #
  # The measure is worked out apart from the library. Each minute of the
  # day is asked of `DateTime`, from the moment the clock first shows a
  # reading of the day to the moment it first shows one of the next, and
  # the minutes are gathered into the hours the clock showed: an hour is
  # the minutes, one after another, at which the clock reads within it,
  # and a new occurrence of the hour starts where the clock shows its
  # first reading again. That is how Tempo holds an hour: once for each
  # time the clock comes to its start, and once where a gap skips the
  # start and leaves part of the hour.
  #
  # The days are chosen for the shape of the change, since a change by a
  # whole hour on the hour is the one every implementation is written for:
  # by half an hour (Lord Howe Island), at a quarter to the hour (the
  # Chatham Islands), half an hour before midnight (Pyongyang), a quarter
  # of an hour at midnight (Kathmandu), by two hours (Troll), and at
  # midnight (Cairo, Havana).

  alias Tempo.Compare
  alias Tempo.Interval

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
  @minute 60

  @gaps [
    {"America/New_York", ~D[2024-03-10], "02:00 to 03:00"},
    {"Europe/Paris", ~D[2026-03-29], "02:00 to 03:00"},
    {"Australia/Lord_Howe", ~D[2026-10-04], "02:00 to 02:30"},
    {"Pacific/Chatham", ~D[2026-09-27], "02:45 to 03:45"},
    {"Asia/Pyongyang", ~D[2018-05-04], "23:30 to midnight"},
    {"America/Caracas", ~D[2016-05-01], "02:30 to 03:00"},
    {"Asia/Kathmandu", ~D[1986-01-01], "midnight to 00:15"},
    {"Africa/Cairo", ~D[2023-04-28], "midnight to 01:00"},
    {"America/Havana", ~D[2024-03-10], "midnight to 01:00"},
    {"Antarctica/Troll", ~D[2024-03-31], "01:00 to 03:00"},
    {"Pacific/Apia", ~D[2011-12-29], "the day before the day left out"},
    {"Pacific/Apia", ~D[2011-12-31], "the day after the day left out"}
  ]

  @folds [
    {"America/New_York", ~D[2024-11-03], "02:00 back to 01:00"},
    {"Europe/Paris", ~D[2026-10-25], "03:00 back to 02:00"},
    {"Africa/Cairo", ~D[2023-10-26], "midnight back to 23:00"},
    {"America/Havana", ~D[2024-11-03], "01:00 back to midnight"},
    {"Australia/Lord_Howe", ~D[2026-04-05], "02:00 back to 01:30"},
    {"Asia/Pyongyang", ~D[2015-08-14], "midnight back to 23:30"},
    {"America/Caracas", ~D[2007-12-09], "03:00 back to 02:30"},
    {"Asia/Colombo", ~D[2006-04-15], "00:30 back to midnight"}
  ]

  @doc """
  The days on which a clock goes forward, as `{zone, date, change}`.
  """
  @spec gaps() :: [{String.t(), Date.t(), String.t()}]
  def gaps, do: @gaps

  @doc """
  The days on which a clock goes back, as `{zone, date, change}`.
  """
  @spec folds() :: [{String.t(), Date.t(), String.t()}]
  def folds, do: @folds

  @doc """
  The day as a Tempo value in its zone.
  """
  @spec day(String.t(), Date.t()) :: Tempo.t()
  def day(zone, %Date{} = date),
    do: Tempo.from_iso8601!(Date.to_iso8601(date) <> "[" <> zone <> "]")

  @doc """
  The moment a value starts at, in seconds since 1970.
  """
  @spec moment(Tempo.t()) :: integer()
  def moment(%Tempo{} = value), do: trunc(Compare.to_utc_seconds(value)) - @unix_epoch

  ## What Elixir says the clock showed

  @doc """
  The first moment the clock shows a reading of the day, and the first it
  shows one of the day after, by `DateTime`.
  """
  @spec day_shown(String.t(), Date.t()) :: {integer(), integer()}
  def day_shown(zone, %Date{} = date),
    do: {first_shown(date, zone), first_shown(Date.add(date, 1), zone)}

  defp first_shown(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, shown} -> DateTime.to_unix(shown)
      {:ambiguous, first, _second} -> DateTime.to_unix(first)
      {:gap, _just_before, shown} -> DateTime.to_unix(shown)
    end
  end

  @doc """
  The hours the clock showed on a day, in order of time, each as
  `{hour, from, to}`: the hour of the day and the moments it was shown
  from and to.
  """
  @spec hours_shown(String.t(), Date.t()) :: [{0..23, integer(), integer()}]
  def hours_shown(zone, %Date{} = date) do
    {from, to} = day_shown(zone, date)

    from..(to - @minute)//@minute
    |> Enum.map(&reading_at(&1, zone))
    |> occurrences([])
  end

  defp reading_at(moment, zone) do
    shown = moment |> DateTime.from_unix!() |> DateTime.shift_zone!(zone)
    {moment, shown.hour, shown.minute}
  end

  # A minute goes on the occurrence before it where it is the same hour,
  # the next minute in time, and not the hour's first reading come again.
  defp occurrences([{moment, hour, minute} | readings], [{hour, from, moment} | shown])
       when minute != 0,
       do: occurrences(readings, [{hour, from, moment + @minute} | shown])

  defp occurrences([{moment, hour, _minute} | readings], shown),
    do: occurrences(readings, [{hour, moment, moment + @minute} | shown])

  defp occurrences([], shown), do: Enum.reverse(shown)

  ## What Tempo gives

  @doc """
  The hours a walk of the day gives, each as `{hour, from, to}`: the hour
  of the day and the moments its span runs from and to.
  """
  @spec hours_listed(String.t(), Date.t()) :: [{0..23, integer(), integer()}]
  def hours_listed(zone, %Date{} = date) do
    for hour <- Enum.to_list(day(zone, date)) do
      {from, to} = span(hour)
      {Keyword.fetch!(hour.time, :hour), from, to}
    end
  end

  @doc """
  The moments a value's span runs from and to.
  """
  @spec span(Tempo.t()) :: {integer(), integer()}
  def span(%Tempo{} = value) do
    {:ok, %Interval{} = span} = Tempo.to_interval(value)
    {moment(Interval.from(span)), moment(Interval.to(span))}
  end

  @doc """
  Where the walk of a value, or of its span, and the answers `Enum` takes
  without a walk disagree: its count, the value at each place, and whether
  each value listed is a member. Empty where they agree.
  """
  @spec walk_against_enum(Enumerable.t()) :: [tuple()]
  def walk_against_enum(walked) do
    listed = Enum.to_list(walked)

    counted(walked, listed) ++ placed(walked, listed) ++ members(walked, listed)
  end

  defp counted(walked, listed) do
    case {Enum.count(walked), Enum.count(listed)} do
      {same, same} -> []
      {count, listed} -> [{:count, count, :listed, listed}]
    end
  end

  defp placed(walked, listed) do
    for {value, place} <- Enum.with_index(listed),
        at = Enum.at(walked, place),
        at != value,
        do: {:at, place, inspect(at), :listed, inspect(value)}
  end

  defp members(walked, listed) do
    for value <- listed, not Enum.member?(walked, value), do: {:not_a_member, inspect(value)}
  end
end
