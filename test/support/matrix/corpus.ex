defmodule Tempo.Matrix.Corpus do
  @moduledoc """
  The values the matrix runs every operation against, grouped into classes
  of shape and levels of guarantee (see `plans/validated-core.md`).

  Each class is a short list of ISO 8601 texts. The values are read with
  `Tempo.from_iso8601/2`, so a text that stops parsing is the matrix's
  first failure.

  """

  alias Calendrical.ISOWeek
  alias Tempo.Matrix.Selections
  alias Tempo.Matrix.Shapes

  @type level :: :core | :extended | :open | :generated | :exhaustive

  @type entry :: %{
          class: atom() | String.t(),
          level: level(),
          text: String.t(),
          calendar: module() | nil
        }

  # Dates and times, each one whole value on the time line.
  @core [
    year: ["2026", "2026Y", "2024Y"],
    year_month: ["2026-06", "2026Y6M", "2024Y2M", "2026Y12M"],
    date: ["2026-06-15", "20260615", "2026Y6M15D", "2024-02-29", "2026-12-31"],
    week: ["2026-W25", "2026W25", "2026Y25W", "2026Y53W"],
    week_date: ["2026-W25-3", "2026W253", "2026Y25W3K"],
    ordinal_date: ["2026-166", "2026166", "2026Y166O", "2024Y366O"],
    date_hour: ["2026-06-15T10", "2026Y6M15DT10H", "2026-06-15T00", "2026-06-15T23"],
    date_minute: ["2026-06-15T10:30", "20260615T1030", "2026Y6M15DT10H30M"],
    date_second: ["2026-06-15T10:30:45", "2026Y6M15DT10H30M45S", "2026-12-31T23:59:59"],
    date_fraction: ["2026-06-15T10:30:45.5", "2026-06-15T10:30:45.123"],
    # A second written to six digits has nothing finer to walk.
    date_microsecond: ["2026-06-15T10:30:45.123456"],
    utc: ["2026-06-15T10:30:45Z", "2026-06-15T10Z"],
    offset: ["2026-06-15T10:30:45+02:00", "2026-06-15T10:30-05"],
    zoned: ["2026-06-15T10:30:45[Europe/Paris]", "2026-06-15T10:30:45+02:00[Europe/Paris]"],
    zoned_date: ["2026-06-15[Europe/Paris]"],
    expanded_year: ["-2026Y", "Y12026", "-0044"],
    time_of_day: ["T10:30:45", "T10H", "T10H30M", "T10H30M45S"],
    month_day: ["6M15D", "12M25D", "6M", "2M"],
    weekday: ["3K", "7K"],
    # The last of its cycle: the span ends where the day, the year or the
    # week does.
    cycle_end: ["T23H", "T23:59", "T23:59:59", "12M", "12M31D", "T00", "1M1D"],
    interval_closed: [
      "2026-06-01/2026-07-01",
      "2026/2027",
      "2026-06-15T09/2026-06-15T17",
      "2026Y/2026Y6M15D"
    ],
    interval_start_duration: ["2026-06-01/P1M", "2026-06-15T09/PT8H"],
    interval_duration_end: ["P1M/2026-07-01"],
    interval_open_end: ["2026-06-01/..", "2026/.."],
    interval_open_start: ["../2026-06-01"],
    interval_open: ["../.."],
    interval_no_year: ["T22H/T2H", "12M/2M", "T9H/T17H", "T23H/T0H", "6K/2K", "T22:30/T23"],
    interval_no_year_open: ["T10H/..", "6M/.."],
    interval_two_resolutions: [
      "2026/2026-03",
      "1985/1986-06",
      "2026-06-15T10/2026-06-16",
      "2026-06-01/2026-06-03T12",
      "2026-06-15/PT36H"
    ],
    interval_two_axes: ["2026-W25/2026-07-01", "2026-166/2026-07-01", "2026-06-15/2026-W27"],
    interval_zoned: [
      "2026-06-15T09:00[Europe/Paris]/2026-06-15T17:00[Europe/Paris]",
      "2026-03-28T12:00[Europe/Paris]/2026-03-30T12:00[Europe/Paris]",
      "2026-06-15T09:00Z/2026-06-15T17:00Z",
      "2026-06-15[Europe/Paris]/2026-06-17[Europe/Paris]"
    ],
    interval_two_zones: [
      "2026-06-15T10:00+02:00/2026-06-15T12:00Z",
      "2026-06-15T10:00[Europe/Paris]/2026-06-15T12:00[Europe/London]"
    ],
    duration: ["P1D", "P1M", "P1Y2M3D", "PT1H30M", "P1W", "PT0.5S", "-P1D", "P1Y2M3DT4H5M6S"],
    # Durations, all of them or one of them (ISO 8601-2 §6.5): lengths of
    # time, and no time.
    duration_set: ["{P1D,P2D}", "[PT30M,PT1H]", "{P1M2S..P1M5S}"],
    recurrence_count: [
      "R3/2026-06-01/P1D",
      "R5/2026-01-01/P1M",
      "R3/2026-06-01/2026-06-08",
      "R3/P1W/2026-06-22"
    ],
    recurrence_unending: ["R/2026-01-01/P1Y", "R/2026-06-01/P1D"],
    recurrence_selection: [
      "R3/2026-01-01/P1Y/FL7M4DN",
      "R/../P1Y/FL12M25DN",
      "R/../P1M/FL5K-1IN",
      "R3/2026-01-01/P1Y/FL-1M-1DN"
    ],
    component_set: ["2026Y{6,7}M", "2026Y6M{1,15}D", "{2026,2027}Y", "2026Y6M{1,15}DT10H30M0S"],
    component_range: ["2026Y{1..3}M", "2026Y6M{1..-1}D", "{2020..2022}Y6M"],
    value_set_all: ["{2026-06-15,2026-07-01}", "{2026Y,2027Y}", "{2026,2027}"],
    value_set_one: ["[2026,2027]", "[2026-06-15,2026-07-01]"],
    set_range: ["{2020Y..2022Y}", "[2020Y..2022Y]"],
    calendar_hebrew: ["5786Y6M15D[u-ca=hebrew]", "5786Y6M[u-ca=hebrew]", "5786Y[u-ca=hebrew]"]
  ]

  # A week calendar's values are written without a suffix, so they carry
  # their calendar beside the text.
  @core_in_calendar [
    calendar_weeks: [{"2026Y25W3K", ISOWeek}, {"2026Y25W", ISOWeek}, {"2026Y", ISOWeek}]
  ]

  # Shapes whose meaning is the values their walk yields.
  @extended [
    year_mask: ["202X", "20XX", "-10XX"],
    mask_partial: ["2026-06-1X", "2026-1X", "2026-06-15T1X", "2026Y3XD", "2026Y3XO", "2026-W2X"],
    mask_full: ["2026-06-XX", "1985-XX-XX", "2026-XX"],
    mask_tail: ["1985-XX-15", "2026-XX-1X", "2026Y6MXXDT10H", "2026Y6MXXDT10H30M0S"],
    unspecified: ["2026Y6MX*D", "2026YX*M", "2026YX*M15D", "2026Y6M15DTX*H"],
    qualified: ["2026-06-15?", "2026-06~", "2026?-06-15", "2004-06~-11", "2026-06-15%"],
    margin: ["2018±2Y"],
    significant_digits: ["1950S2", "1950S2Y6M", "1950S4"],
    group: ["2026Y1G3MU", "20C", "201J", "2026Y2G3MU", "2018Y1G6MU"],
    count_from_end: ["2026Y6M-1D", "2026Y-1M", "2026Y{1..12}M-1D"],
    # The last two count from the end of the period they are selected in.
    value_selection: ["2026Y4ML1K1IN", "2026Y6ML2KN", "2026YL-1M-1DN", "2026Y6M15DLT-1HN"],
    # A season of a hemisphere (25 to 32) is its dates. A set of seasons
    # that have none is walked by its members, as any set is.
    season: ["2026-25", "2026-30", "2026Y27M"],
    season_set: ["{2026-21,2026-23}", "{2026-21..2026-24}"],
    # A week after a month is a week of the month, read as the span of the
    # dates the calendar numbers in it, and with a day of the week as a date.
    week_of_month: ["2026Y6M2W", "2026Y7M1W", "2026Y6M-1W", "2026Y6M2W3K"],
    zone_transition: ["2026-10-25T02:30[Europe/Paris]", "2026-03-29[Europe/Paris]"],
    mask_from_end: ["2026Y-XM", "2026Y6M-1XD", "2026Y-XM15D"],
    mask_narrow: ["2026YXM", "2026Y6MXD", "2026YXXD"],
    # A time of day under a date with its month or its day left out, which
    # is read at the first of what is left out.
    date_gap: [
      "2026YT17H",
      "2026-06T17",
      "2026YT23H",
      "2026Y25WT17H",
      "6MT10H",
      "2026Y{6,7}MT10H"
    ],
    recurrence_exotic_start: ["R3/2026Y6MXXD/P1M", "R3/2026Y6M{1,15}D/P1M", "R3/T22H/PT1H"],
    # A set drops the values its context cannot hold, here 31 February. One
    # none of whose values exists (`{2,6}M31D`) names no date, and is not a
    # value to measure.
    set_exotic: ["{1,2}M31D", "{1,2}M"],
    group_of_set: ["2026Y{1,2}G3MU", "2026Y{1..-1}G3MU", "2026Y6M{1,2}G10DU", "2026Y{1,2}G3MU15D"]
  ]

  # Shapes the walk or the conversion has no answer for yet, in at least one
  # of their values: a named error is their answer until the walk defines
  # one, and the matrix test holds the list to that.
  #
  # A season of 21 to 24 is here by design and not for the time being: it
  # has no dates until it is given a hemisphere, so it is converted in the
  # hemisphere of the territory in force and is not walked, and whatever
  # else needs its dates says so by name (`Tempo.AbstractSeasonError`).
  @open [
    season_with_no_hemisphere: ["2026-21", "2026Y22M", "2026Y24M", "2026-21?"],
    season_interval: ["2026-21/2026-23", "2026-22/2027-21", "2026-21/2026-10-15"],
    unspecified_year: ["X*Y", "X*Y12M31D", "X*Y6MX*D"],
    interval_exotic_end: ["2026Y6MXXD/P1M", "2026Y6MX*D/2026Y8M", "20C/21C", "202X/2040"],
    no_year_masked: ["2MXXD", "XXM", "X*K", "6MX*D"]
  ]

  @doc """
  Every entry of the corpus: those written by hand and those generated,
  with no text twice.

  ### Returns

  * A list of `t:entry/0`.

  """
  @spec entries() :: [entry()]
  def entries, do: Enum.uniq_by(written() ++ generated(), &{&1.text, &1.calendar})

  @doc """
  The entries written by hand: each has its class, its level, its text and
  the calendar it is read in when the text does not name one. Every one of
  them is a value, so a text here that does not parse is a failure.

  ### Returns

  * A list of `t:entry/0`.

  """
  @spec written() :: [entry()]
  def written do
    plain(@core, :core) ++
      in_calendar(@core_in_calendar, :core) ++
      plain(@extended, :extended) ++ plain(@open, :open)
  end

  @doc """
  The entries `Tempo.Matrix.Shapes` generates, each shape in each position
  of each form, and the selections `Tempo.Matrix.Selections` generates,
  each part written each way in each period. A text the parser refuses is
  no value and is left out when the corpus is read.

  ### Returns

  * A list of `t:entry/0`.

  """
  @spec generated() :: [entry()]
  def generated do
    shapes =
      for {shape, text} <- Shapes.texts() ++ Shapes.zoned() ++ Shapes.in_calendar() do
        %{class: shape, level: :generated, text: text, calendar: nil}
      end

    shapes ++ Selections.entries()
  end

  @doc """
  The entries of the exhaustive run, beside those of every run: a shaped
  value at each end of an interval, and two shapes in one value. There are
  thousands, so they run when asked for (`mix test --include exhaustive`).

  ### Returns

  * A list of `t:entry/0`.

  """
  @spec exhaustive() :: [entry()]
  def exhaustive do
    intervals =
      for {shape, text} <- Shapes.intervals() do
        %{class: shape, level: :exhaustive, text: text, calendar: nil}
      end

    pairs =
      for {{first, second}, text} <- Shapes.pairs() do
        %{class: "#{first} and #{second}", level: :exhaustive, text: text, calendar: nil}
      end

    Enum.uniq_by(intervals ++ pairs, & &1.text)
  end

  @doc """
  Reads an entry's text into the value it names.

  ### Arguments

  * `entry` is a `t:entry/0`.

  ### Returns

  * `{:ok, value}` or `{:error, exception}`, as `Tempo.from_iso8601/2` gives.

  """
  @spec read(entry()) :: {:ok, term()} | {:error, Exception.t()}
  def read(%{text: text, calendar: nil}), do: Tempo.from_iso8601(text)
  def read(%{text: text, calendar: calendar}), do: Tempo.from_iso8601(text, calendar)

  @doc """
  The few plain values each two-value operation is run against, in both
  orders, beside the value itself.

  ### Returns

  * A list of `{text, value}` pairs.

  """
  @spec partners() :: [{String.t(), term()}]
  def partners do
    for text <- [
          "2026-06-15",
          "2026",
          "2026-06-01/2026-07-01",
          "2025-01-01T10:00",
          "2026-06-15T10:00Z",
          "2026-06-15[Europe/Paris]"
        ] do
      {text, Tempo.from_iso8601!(text)}
    end
  end

  defp plain(classes, level) do
    for {class, texts} <- classes, text <- texts do
      %{class: class, level: level, text: text, calendar: nil}
    end
  end

  defp in_calendar(classes, level) do
    for {class, texts} <- classes, {text, calendar} <- texts do
      %{class: class, level: level, text: text, calendar: calendar}
    end
  end
end
