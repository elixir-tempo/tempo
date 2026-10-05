defmodule Tempo do
  @moduledoc """
  Documentation for `Tempo`.

  ### Terminology

  The following terms, defined by ISO 8601, are used throughout
  Tempo. For further information consult:

  * [ISO Online browsing platform](https://www.iso.org/obp)
  * [IEC Electropedia](http://www.electropedia.org/)

  #### Date

  A [time](#time) on the the calendar time scale. Common forms of date include calendar date,
  ordinal date or week date.

  #### Time

  A mark attributed to an [instant](#instant) or a [time interval](#time_interval) on a specified
  [time scale](#time_scale).

  The term “time” is often used in common language. However, it should only be used if the
  meaning is clearly visible from the context.

  On a time scale consisting of successive time intervals, such as a clock or calendar,
  distinct instants may be expressed by the same time.

  This definition corresponds with the definition of the term “date” in
  IEC 60050-113:2011, 113-01-12.

  #### Instant

  A point on the [time axis](#time_axis). An instantaneous event occurs at a specific instant.

  #### Time axis

  A mathematical representation of the succession in time according to the space-time model
  of instantaneous events along a unique axis/

  According to the theory of special relativity, the time axis depends on the choice of a
  spatial reference frame.

  In IEC 60050-113:2011, 113-01-03, time according to the space-time model is defined to be
  the one-dimensional subspace of space-time, locally orthogonal to space.

  #### Time scale

  A system of ordered marks which can be attributed to [instants](#instant) on the
  [time axis](#time_axis), one instant being chosen as the origin.

  A time scale may amongst others be chosen as:

  * continuous, e.g. international atomic time (TAI) (see IEC 60050-713:1998, 713-05-18);

  * continuous with discontinuities, e.g. UTC due to leap seconds, standard time due
    to summer time and winter time;

  * successive steps, e.g. [calendars](#calendar), where the [time axis](#time_axis) is split
    up into a succession of consecutive time intervals and the same mark is attributed to all
    instants of each time interval;

  * discrete, e.g. in digital techniques.

  #### Time interval

  A part of the [time axis](#time_axis) limited by two [instants](#instant) *including, unless
  otherwise stated, the limiting instants themselves*.

  #### Time scale unit

  A unit of measurement of a [duration](#duration)

  For example:

  * Calendar year, calendar month and calendar day are time scale units
    of the Gregorian calendar.

  * Clock hour, clock minutes and clock seconds are time scale units of the 24-hour clock.

  In Tempo, time scale units are referred to by the shortened term "unit".  When a "unit" is
  combined with a value, the combination is referred to as a "component".

  #### Duration

  A non-negative quantity of time equal to the difference between the final and initial
  [instants](#instant) of a [time interval](#interval)

  The duration is one of the base quantities in the International System of Quantities (ISQ)
  on which the International System of Units (SI) is based. The term “time” instead of
  “duration” is often used in this context and also for an infinitesimal duration.

  For the term “duration”, expressions such as “time” or “time interval” are often used,
  but the term “time” is not recommended in this sense and the term “time interval” is
  deprecated in this sense to avoid confusion with the concept of “time interval”.

  The exact duration of a [time scale unit](#time_scale_unit) depends on the
  [time scale](#time_scale) used. For example, the durations of a year, month, week,
  day, hour or minute, may depend on when they occur (in a Gregorian calendar, a
  calendar month can have a duration of 28, 29, 30, or 31 days; in a 24-hour clock, a
  clock minute can have a duration of 59, 60, or 61 seconds, etc.). Therefore,
  the exact duration can only be evaluated if the exact duration of each is known.

  """

  alias Calendrical.Gregorian
  alias Calendrical.Kday
  alias Tempo.Clock
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Enumeration
  alias Tempo.Enumeration.Zone
  alias Tempo.EventError
  alias Tempo.Explain
  alias Tempo.FloatingTempoError
  alias Tempo.Interval
  alias Tempo.Interval.Steps
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.InvalidCalendarError
  alias Tempo.InvalidDateError
  alias Tempo.InvalidUnitError
  alias Tempo.Iso8601.AST
  alias Tempo.Iso8601.Group
  alias Tempo.Iso8601.Parser
  alias Tempo.Iso8601.Tokenizer
  alias Tempo.Iso8601.Unit
  alias Tempo.Iso8601EncodeError
  alias Tempo.Mask
  alias Tempo.Math
  alias Tempo.NotBuilt
  alias Tempo.ParseError
  alias Tempo.Qualification
  alias Tempo.RecurrenceSet.Conditional
  alias Tempo.ResolutionError
  alias Tempo.Rounding
  alias Tempo.RoundingError
  alias Tempo.RRule.Selection
  alias Tempo.Split
  alias Tempo.Territory
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnanchoredError
  alias Tempo.UnboundedRecurrenceError
  alias Tempo.UnboundedSetError
  alias Tempo.UnitValues
  alias Tempo.UnknownZoneError
  alias Tempo.Validation
  alias Tempo.ZonedTempoError

  defstruct [:time, :shift, :calendar, :extended, :qualifications, metadata: %{}]

  # TODO refine this to be more specific
  @type token :: integer() | list() | tuple()

  @type time_unit ::
          :year | :month | :week | :day | :hour | :minute | :second | :microsecond

  @type token_list :: [
          {:year, token}
          | {:month, token}
          | {:week, token}
          | {:day, token}
          | {:day_of_year, token}
          | {:day_of_week, token | [integer()]}
          | {:hour, token}
          | {:minute, token}
          | {:second, token}
          | {:microsecond, Tempo.Microsecond.t()}
        ]

  @type time_shift :: [{:hour, integer()} | {:minute, integer()}] | nil

  @typedoc """
  A value's zone and tags, as an IXDTF suffix writes them. `nil` for a value with no zone, offset or tag.

  A `[u-ca=NAME]` suffix names the value's calendar, which is its `:calendar` module: the name is not kept here.

  * `:zone_id` — IANA time zone name such as `"Europe/Paris"`.

  * `:zone_offset` — numeric offset in minutes from `[+HH:MM]`.

  * `:zone_critical` — whether the zone was written as critical (`[!Europe/Paris]`).

  * `:tags` — map of non-`u-ca` elective tagged suffixes.

  """
  @type extended_info :: %{
          zone_id: String.t() | nil,
          zone_offset: integer() | nil,
          zone_critical: boolean(),
          tags: %{optional(String.t()) => [String.t()]}
        }

  @typedoc """
  An ISO 8601-2 / EDTF qualifier of a component.

  * `:uncertain` — the component is uncertain (`?`).

  * `:approximate` — the component is approximate (`~`), e.g. "circa".

  * `:uncertain_and_approximate` — both (`%`).

  * `nil` when the component is not qualified.

  """
  @type qualification ::
          :uncertain | :approximate | :uncertain_and_approximate | nil

  @typedoc """
  A value's qualifications (ISO 8601-2 §8), held per component.

  A map from a component's unit (`:year`, `:month`, `:day`, …) to its
  qualifier, naming only units the value holds. A qualifier written
  after a whole value (`2026-06?`) qualifies each of its components,
  and is recorded for each. `nil` when no component is qualified. Read
  it with `qualification/1` and `qualification/2`.

  """
  @type qualifications :: %{optional(atom()) => qualification()} | nil

  @type t :: %__MODULE__{
          time: token_list(),
          shift: time_shift(),
          calendar: Calendar.calendar() | nil,
          extended: extended_info() | nil,
          qualifications: qualifications(),
          metadata: map()
        }
  @typedoc """
  The error payload returned inside `{:error, reason}` tuples.

  As of v0.21, every originating error site in Tempo returns an
  `Exception`-conforming struct (one of the types under
  `lib/tempo/exception/`), mirroring the convention in Localize
  and Calendrical. The `atom() | binary()` members are retained
  transiently for backward compatibility during the migration
  and will be removed once all callers are updated.
  """
  @type error_reason :: Exception.t()

  # Canonical coarse-to-fine order of time-scale units. Used by
  # `new/1` to reorder components before building, so callers can
  # pass them in any convenient order.
  @canonical_unit_order [
    :year,
    :quarter,
    :month,
    :week,
    :day,
    :day_of_year,
    :day_of_week,
    :hour,
    :minute,
    :second,
    :microsecond
  ]

  @week_axis_units [:week, :day_of_week]
  @gregorian_axis_units [:month, :day]

  @known_options [:calendar, :zone, :shift, :qualification, :metadata, :tags]
  @qualification_values [
    :uncertain,
    :approximate,
    :uncertain_and_approximate
  ]

  @doc """
  Construct a `t:Tempo.t/0` from a keyword list of time-scale
  components and options.

  The companion to `~o` sigils and `Tempo.from_iso8601/1`: where the
  sigil is ideal for literal values and `from_iso8601/1` for already-
  formatted strings, `new/1` is the right constructor when you have
  structured data at runtime — form inputs, database rows, API
  payloads, test fixtures.

  Components can be passed in any order; `new/1` reorders them
  coarse-to-fine (year → month → day → hour → minute → second)
  before building the struct.

  Axis coherence is enforced: the Gregorian axis (`:month`, `:day`),
  the week axis (`:week`, `:day_of_week`), the ordinal axis
  (`:day_of_year`) and `:quarter` are mutually exclusive.

  ### Arguments

  * `components` is a keyword list — or a map with the same atom
    keys — mixing time-scale components and options. At least one
    time-scale component must be present.

    Maps are convenient for interop with Elixir's standard date
    and time types: a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0`,
    or a bare `Calendrical.parse/2` `:map` result can be passed
    directly. `Calendar.ISO` (Elixir's default) is silently
    normalised to `Calendrical.Gregorian` so calendar-aware
    validation works.

  ### Time-scale components

  Every component value must be an integer, but for `:microsecond`.

  * `:year` is the calendar year.

  * `:quarter` is the quarter of the year, spanning the months the
    calendar's `quarter/2` gives it (the weeks, in a week-based calendar
    such as `Calendrical.ISOWeek`) — the value `2026-34` parses to. It
    requires `:year`.

  * `:month` is the calendar month (Gregorian axis).

  * `:week` is the ISO 8601 week of the year (week axis): weeks start
    on a Monday and week 1 is the one holding the year's fourth day,
    counted in the calendar's own year. A calendar's own weeks are
    written `w` in an ISO 8601 string (`~o"2026Y10w"`).

  * `:day` is the day of month (Gregorian axis).

  * `:day_of_year` is the ordinal day within the year (ordinal axis).
    The value is the calendar date it names, as the ordinal date
    `2026-166` parses to.

  * `:day_of_week` is the day of the week, `1..7` (week axis).

  * `:hour` is the clock hour `0..23`. A time of day given under a
    year, a month or a week with no day is on the first day of it, as
    `2026-06T17` is read, and one given with a minute or a second and
    no hour is in hour zero.

  * `:minute` is the clock minute `0..59`.

  * `:second` is the clock second `0..59` (or `60` on a leap-second date).

  * `:microsecond` is a decimal fraction of the second as Elixir's
    date and time types hold one: `{microseconds, digits}`, so that
    `{500_000, 1}` is `.5` and `{250_000, 3}` is `.250`. It requires
    `:second`. No digits (`{0, 0}`) is no fraction.

  ### Options

  * `:calendar` is the `Calendrical` calendar module used to
    interpret and validate the components. Defaults to
    `Calendrical.Gregorian`. A calendar of weeks, such as
    `Calendrical.ISOWeek`, has no months: a `:year`, `:month` and
    `:day`, or a `:year` and `:day_of_year`, given for one are the
    Gregorian day, converted into it.

  * `:zone` is an IANA time-zone name as a binary (e.g.
    `"Australia/Sydney"`). Sets `extended.zone_id`. A date with a
    zone and no time of day is that day in the zone.

  * `:shift` is a manual UTC offset expressed as `[hour: n]` or
    `[hour: n, minute: m]`.

  * `:qualification` marks the whole value with an EDTF qualifier,
    which qualifies each of its components. One of `:uncertain`,
    `:approximate`, or `:uncertain_and_approximate`.

  * `:metadata` is a map of the caller's own data carried with the
    value (a holiday name, a source), read with `metadata/1`. It is
    not part of the value's ISO 8601 form: `to_iso8601/1` leaves it
    out, and converting the value (`to_interval/2`) moves it to
    the interval or intervals it becomes.

  * `:tags` is a map of IXDTF (RFC 9557) elective suffix tags,
    written after the value as `[key=value]`. A key is a string of
    lowercase letters, digits, `_` and `-` starting with a letter or
    `_`; a value is letters and digits, several joined by `-` (or
    given as a list). The calendar is the `:calendar` option, not a
    `u-ca` tag.

  ### Returns

  * `{:ok, t()}` on success.

  * `{:error, reason}` when components are missing, have
    non-integer values, mix axes, or name a non-existent zone.

  ### Examples

      iex> {:ok, tempo} = Tempo.new(year: 2026, month: 6, day: 15)
      iex> tempo.time
      [year: 2026, month: 6, day: 15]

      iex> {:ok, tempo} = Tempo.new(day: 15, month: 6, year: 2026)
      iex> tempo.time
      [year: 2026, month: 6, day: 15]

      iex> {:ok, meeting} = Tempo.new(year: 2026, month: 6, day: 15, hour: 14, minute: 30)
      iex> meeting.time
      [year: 2026, month: 6, day: 15, hour: 14, minute: 30]

      iex> {:ok, week} = Tempo.new(year: 2026, week: 24)
      iex> week.time
      [year: 2026, week: 24]

      iex> Tempo.new(year: 2026, week: 24, day_of_week: 3)
      {:ok, ~o"2026-W24-3"}

      iex> Tempo.new(year: 2026, month: 6, day: 15, zone: "Europe/Paris")
      {:ok, ~o"2026-06-15[Europe/Paris]"}

      iex> Tempo.new(hour: 10, minute: 30, second: 45, microsecond: {500_000, 1})
      {:ok, ~o"T10:30:45.5"}

      iex> {:ok, second_quarter} = Tempo.new(year: 2026, quarter: 2)
      iex> Tempo.to_interval(second_quarter)
      {:ok, ~o"2026Y4M/7M"}

      iex> {:error, _} = Tempo.new(year: 2026, month: 13)

      iex> {:error, _} = Tempo.new(year: 2026, month: 6, week: 24)

      iex> {:ok, tempo} = Tempo.new(%{year: 2026, month: 6, day: 15})
      iex> tempo.time
      [year: 2026, month: 6, day: 15]

      iex> {:ok, tempo} = Tempo.new(Map.from_struct(~D[2026-06-15]))
      iex> tempo.time
      [year: 2026, month: 6, day: 15]

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, error_reason()}
  def new(components) when is_list(components) do
    with :ok <- ensure_keyword(components),
         components = Enum.map(components, &calendar_option_as_gregorian/1),
         {components, options} <- split_components_and_options(components),
         :ok <- validate_options(options),
         :ok <- validate_components(components),
         :ok <- validate_axis_coherence(components),
         {:ok, components} <- fraction_of_second(components),
         {:ok, components} <- quarter_to_group(components, options),
         {:ok, components} <- day_of_year_to_date(components, options),
         {:ok, tempo} <- build_tempo(components, options) do
      validate_against_calendar(tempo)
    end
  end

  def new(components) when is_map(components) do
    components
    |> Map.to_list()
    |> new()
  end

  defp calendar_option_as_gregorian({:calendar, calendar}),
    do: {:calendar, calendar_iso_as_gregorian(calendar)}

  defp calendar_option_as_gregorian(entry), do: entry

  # `Calendar.ISO`, Elixir's default calendar, enters Tempo as its
  # Calendrical equivalent, `Calendrical.Gregorian`, at the public API, so
  # nothing inside Tempo sees it; `to_date/1` and its kin give it back.
  defp calendar_iso_as_gregorian(Calendar.ISO), do: Calendrical.Gregorian
  defp calendar_iso_as_gregorian(calendar), do: calendar

  @doc """
  Bang variant of `new/1` — raises on invalid input.

  ### Examples

      iex> Tempo.new!(year: 2026, month: 6, day: 15).time
      [year: 2026, month: 6, day: 15]

  """
  @spec new!(keyword() | map()) :: t()
  def new!(components) when is_list(components) or is_map(components) do
    case new(components) do
      {:ok, tempo} -> tempo
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "Tempo.new!/1 failed: #{inspect(reason)}"
    end
  end

  defp ensure_keyword(components) do
    if Keyword.keyword?(components) do
      :ok
    else
      {:error,
       ArgumentError.exception(
         "Tempo.new/1 expects a keyword list of time-scale components " <>
           "and options. Got: #{inspect(components)}"
       )}
    end
  end

  defp split_components_and_options(kw) do
    {options, components} =
      Enum.split_with(kw, fn {key, _value} -> key in @known_options end)

    {components, options}
  end

  defp validate_options(options) do
    with :ok <- validate_qualification(Keyword.get(options, :qualification)),
         :ok <- validate_metadata(Keyword.get(options, :metadata, %{})) do
      validate_tags(Keyword.get(options, :tags, %{}))
    end
  end

  defp validate_qualification(nil), do: :ok
  defp validate_qualification(value) when value in @qualification_values, do: :ok

  defp validate_qualification(other) do
    {:error,
     ArgumentError.exception(
       ":qualification must be one of #{inspect(@qualification_values)}, got #{inspect(other)}"
     )}
  end

  defp validate_metadata(metadata) when is_map(metadata), do: :ok

  defp validate_metadata(other) do
    {:error, ArgumentError.exception(":metadata must be a map, got #{inspect(other)}")}
  end

  # IXDTF (RFC 9557) elective suffix tags, written `[key=value]`: a key of
  # lowercase letters, digits, `_` and `-` that starts with a letter or `_`, and
  # a value of letters and digits, several joined by `-`. The calendar has its
  # own option, so `u-ca` is not a tag here.
  defp validate_tags(tags) when is_map(tags) do
    Enum.find_value(tags, :ok, fn {key, value} ->
      if valid_tag?(key, value), do: nil, else: invalid_tag(key, value)
    end)
  end

  defp validate_tags(other) do
    {:error, ArgumentError.exception(":tags must be a map, got #{inspect(other)}")}
  end

  defp valid_tag?(key, value) when is_binary(key) and key != "u-ca" do
    Regex.match?(~r/\A[a-z_][a-z0-9_-]*\z/, key) and valid_tag_value?(tag_segments(value))
  end

  defp valid_tag?(_key, _value), do: false

  defp valid_tag_value?([_ | _] = segments) do
    Enum.all?(segments, &(is_binary(&1) and Regex.match?(~r/\A[A-Za-z0-9]+\z/, &1)))
  end

  defp valid_tag_value?(_segments), do: false

  defp tag_segments(value) when is_binary(value), do: String.split(value, "-")
  defp tag_segments(value), do: value

  defp invalid_tag(key, value) do
    {:error,
     ArgumentError.exception(
       "Invalid IXDTF tag #{inspect(key)} => #{inspect(value)}: a tag key is a string of " <>
         "lowercase letters, digits, `_` and `-` starting with a letter or `_` (and not " <>
         "`u-ca`, which is the :calendar option), and its value letters and digits, " <>
         "several joined by `-`"
     )}
  end

  defp validate_components([]) do
    {:error,
     ArgumentError.exception(
       "Tempo.new/1 requires at least one time-scale component — e.g. " <>
         "[year: 2026] or [hour: 14, minute: 30]. None were given."
     )}
  end

  defp validate_components(components) do
    Enum.reduce_while(components, :ok, fn {unit, value}, :ok ->
      cond do
        unit not in @canonical_unit_order ->
          {:halt,
           {:error,
            ArgumentError.exception(
              "Tempo.new/1 does not recognise the component #{inspect(unit)}. " <>
                "Valid components are #{inspect(@canonical_unit_order)}."
            )}}

        not component_value?(unit, value) ->
          {:halt, {:error, component_value_error(unit, value)}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # A fraction of a second is the pair Elixir's types hold: its microseconds
  # and the digits it is written to.
  defp component_value?(:microsecond, {value, precision}),
    do: value in 0..999_999 and precision in 0..6

  defp component_value?(:microsecond, _value), do: false
  defp component_value?(_unit, value), do: is_integer(value)

  defp component_value_error(:microsecond, value) do
    InvalidDateError.exception(
      unit: :microsecond,
      value: value,
      reason: "must be {microseconds, digits}, such as {500_000, 1}"
    )
  end

  defp component_value_error(unit, value),
    do: InvalidDateError.exception(unit: unit, value: value, reason: "must be an integer")

  # A fraction is of the second it follows, and one written to no digits is
  # none.
  defp fraction_of_second(components) do
    case Keyword.pop(components, :microsecond) do
      {nil, components} ->
        {:ok, components}

      {{_value, 0}, components} ->
        {:ok, components}

      {fraction, without_fraction} ->
        if Keyword.has_key?(without_fraction, :second),
          do: {:ok, without_fraction ++ [microsecond: fraction]},
          else:
            {:error, ArgumentError.exception("Tempo.new/1 needs a :second for a :microsecond.")}
    end
  end

  defp validate_axis_coherence(components) do
    keys = Keyword.keys(components)

    week_axis? = Enum.any?(keys, &(&1 in @week_axis_units))
    gregorian_axis? = Enum.any?(keys, &(&1 in @gregorian_axis_units))
    ordinal_axis? = :day_of_year in keys
    quarter_axis? = :quarter in keys

    mixed = Enum.count([week_axis?, gregorian_axis?, ordinal_axis?, quarter_axis?], & &1)

    if mixed > 1 do
      {:error,
       ArgumentError.exception(
         "Tempo.new/1 cannot mix calendar axes — choose one of: " <>
           ":month/:day (Gregorian), :week/:day_of_week (week), " <>
           ":day_of_year (ordinal), or :quarter. Got: #{inspect(keys)}"
       )}
    else
      :ok
    end
  end

  # A quarter is the span the calendar's `quarter/2` returns, held as the
  # group of months it covers (of weeks, in a week-based calendar), as the
  # ISO 8601-2 quarter `2026-34` is.
  defp quarter_to_group(components, options) do
    case Keyword.pop(components, :quarter) do
      {nil, components} ->
        {:ok, components}

      {quarter, components} ->
        quarter_group(
          components,
          quarter,
          Keyword.get(options, :calendar) || Calendrical.Gregorian
        )
    end
  end

  defp quarter_group(components, quarter, calendar) do
    case Keyword.fetch(components, :year) do
      {:ok, year} ->
        put_quarter_group(components, year, quarter, calendar)

      :error ->
        {:error,
         ArgumentError.exception("Tempo.new/1 needs a :year to place quarter #{quarter} in.")}
    end
  end

  # An ordinal day is the calendar date it names, as the ISO 8601 ordinal
  # date `2026-166` parses to, from Calendrical. One given for a calendar of
  # weeks is the Gregorian day of the year, as one parsed for it is, and is
  # left for the validation that converts it.
  defp day_of_year_to_date(components, options) do
    calendar = Keyword.get(options, :calendar) || Calendrical.Gregorian

    case Keyword.pop(components, :day_of_year) do
      {nil, _unchanged} ->
        {:ok, components}

      {day_of_year, without_day_of_year} ->
        if Validation.written_in_another_calendar?(components, calendar),
          do: {:ok, components},
          else: ordinal_date(without_day_of_year, day_of_year, calendar)
    end
  end

  defp ordinal_date(components, day_of_year, calendar) do
    with {:ok, year} <- Keyword.fetch(components, :year),
         %{month: month, day: day} <-
           Calendrical.date_from_day_of_year(year, day_of_year, calendar) do
      {:ok, components ++ [month: month, day: day]}
    else
      :error ->
        {:error,
         ArgumentError.exception("Tempo.new/1 needs a :year to place day #{day_of_year} in.")}

      {:error, _reason} ->
        {:error,
         InvalidDateError.exception(
           unit: :day_of_year,
           value: day_of_year,
           year: Keyword.get(components, :year),
           calendar: calendar
         )}
    end
  end

  defp put_quarter_group(components, year, quarter, calendar) do
    case Group.year_division_group(calendar, year, :quarter, quarter) do
      {:ok, {unit, group}} ->
        {:ok, Keyword.put(components, unit, group)}

      {:error, reason} ->
        {:error, Group.year_division_error(reason, year, :quarter, quarter, calendar)}
    end
  end

  defp build_tempo(components, options) do
    # A missing — or explicitly `nil` — calendar defaults to Gregorian, so a
    # value built through `new/1` never carries the bare-struct `nil`.
    calendar = Keyword.get(options, :calendar) || Calendrical.Gregorian
    zone = Keyword.get(options, :zone)
    shift = Keyword.get(options, :shift)
    qualification = Keyword.get(options, :qualification)

    tags =
      Map.new(Keyword.get(options, :tags, %{}), fn {key, value} -> {key, tag_segments(value)} end)

    ordered_time =
      components
      |> Enum.sort_by(fn {unit, _value} ->
        Enum.find_index(@canonical_unit_order, &(&1 == unit))
      end)

    {:ok,
     %__MODULE__{
       time: ordered_time,
       shift: shift,
       calendar: calendar,
       extended: new_extended(zone, tags),
       qualifications: Qualification.complete(ordered_time, qualification),
       metadata: Keyword.get(options, :metadata, %{})
     }}
  end

  # A value with neither a zone nor a tag carries no extended information.
  defp new_extended(nil, tags) when map_size(tags) == 0, do: nil

  defp new_extended(zone, tags) do
    %{zone_id: zone, zone_offset: nil, zone_critical: false, tags: tags}
  end

  # Defer to `Tempo.Validation.validate/2` for calendar-aware range
  # checks (month ≤ months_in_year, day ≤ days_in_month, leap-aware
  # Feb 29, etc.). Validation may return an `InvalidDateError` with
  # rich context. The value is the one the same components parse to, so a
  # value built and a value read are one value: a week and a day of it are
  # the calendar date they name (`2026-W25-3` is 17 June), and a month and a
  # day given for a calendar of weeks are the Gregorian day, converted.
  defp validate_against_calendar(%__MODULE__{calendar: calendar} = tempo),
    do: Validation.validate(tempo, calendar)

  @doc """
  Creates a `t:Tempo.t/0` struct from an ISO 8601 or IXDTF
  string.

  The parser supports the vast majority of [ISO 8601](https://www.iso.org/iso-8601-date-and-time-format.html)
  parts 1 and 2 as well as the Internet Extended Date/Time Format
  (IXDTF) defined in
  [draft-ietf-sedate-datetime-extended-09](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html).

  An IXDTF suffix follows the ISO 8601 production and consists of
  an optional time zone (`[Europe/Paris]` or `[+08:45]`) followed
  by zero or more tagged suffixes (`[u-ca=hebrew]`, `[_key=value]`).
  Any bracket may be prefixed with `!` to mark it critical —
  unrecognised critical suffixes cause the parse to fail; elective
  suffixes are retained verbatim under `extended.tags`. A critical
  flag on a time zone additionally enforces RFC 9557 §4.2 offset
  consistency: a numeric offset that disagrees with the critical
  zone is rejected with a `Tempo.ZoneOffsetMismatchError`. An
  elective zone leaves the offset authoritative; pass `strict: true`
  to reject an elective disagreement too.

  `parse/2` reads everything this function reads, and a locale's own
  words besides.

  ### Arguments

  * `string` is any ISO 8601 formatted string, optionally
    followed by an IXDTF suffix.

  * `calendar_or_options` (optional) is a calendar module or a
    keyword list of options. A calendar module always wins over any
    `[u-ca=NAME]` tag in the IXDTF suffix. When omitted, the
    `[u-ca=NAME]` tag names the calendar, and with no tag
    `Calendrical.Gregorian` is used. A calendar of weeks, such as
    `Calendrical.ISOWeek`, has no months, so a whole date written
    with a month and a day, or as a day of the year, is read as the
    Gregorian day and converted into it; a month alone is an error.
    Every member of a set is in the calendar; the years of a
    recurrence's domain (`R/{2026Y..2027Y}/…`) stay Gregorian.

  ### Options

  * `:calendar` is the calendar module, as above.

  * `:strict` when `true` rejects a value whose numeric offset
    disagrees with an elective IXDTF zone (RFC 9557 §4.2). Defaults
    to `false`.

  ### Returns

  * `{:ok, value}` — a `t:t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.Duration.t/0` or `t:Tempo.Set.t/0` — whose `:extended`
    field holds the zone and tags of an IXDTF suffix. The calendar a
    suffix names is the value's `:calendar`, so a value read from
    text is equal to the same value made with a calendar module.

  * `{:error, reason}` when the string cannot be parsed or a
    critical IXDTF suffix is unrecognised.

  ### Examples

      iex> Tempo.from_iso8601("2022-11-20")
      {:ok, ~o"2022Y11M20D"}

      iex> Tempo.from_iso8601("2022Y")
      {:ok, ~o"2022Y"}

      iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("invalid")

      iex> {:ok, tempo} = Tempo.from_iso8601("5786-09-30[u-ca=hebrew]")
      iex> tempo.calendar
      Calendrical.Hebrew

      iex> {:ok, tempo} = Tempo.from_iso8601("2022-11-20T10:30:00Z[Europe/Paris][u-ca=hebrew]")
      iex> {tempo.extended.zone_id, tempo.calendar}
      {"Europe/Paris", Calendrical.Hebrew}

      iex> Tempo.from_iso8601("5786-09-30[u-ca=hebrew]") == Tempo.from_iso8601("5786-09-30", Calendrical.Hebrew)
      true

      iex> {:error, %Tempo.UnknownZoneError{zone_id: "Continent/Imaginary"}} =
      ...>   Tempo.from_iso8601("2022-11-20T10:30:00Z[!Continent/Imaginary]")

      iex> Tempo.from_iso8601("2026-06-15", Calendrical.ISOWeek)
      {:ok, ~o"2026Y25W1K"W}

  """
  @spec from_iso8601(String.t(), Calendar.calendar() | keyword()) ::
          {:ok,
           t()
           | Tempo.Interval.t()
           | Tempo.Duration.t()
           | Tempo.Set.t()}
          | {:error, error_reason()}
  def from_iso8601(string, calendar_or_options \\ [])

  def from_iso8601(string, options) when is_binary(string) and is_list(options) do
    # Options form, and the default. `:calendar` selects the calendar
    # (default: the IXDTF `[u-ca=NAME]` suffix, else Gregorian);
    # `strict: true` rejects an IXDTF value whose numeric offset disagrees
    # with its zone (RFC 9557 §4.2), via `Tempo.Compare.validate_zone_offset/1`.
    # Strict only applies to a `%Tempo{}` result; intervals and durations
    # pass straight through.
    calendar = Keyword.get(options, :calendar, :from_ixdtf_or_default)

    with {:ok, %Tempo{} = tempo} <- do_from_iso8601(string, calendar) do
      enforce_strict(tempo, options)
    end
  end

  def from_iso8601(string, calendar) when is_binary(string) do
    # Explicit user calendar always wins — an IXDTF `[u-ca=NAME]` does
    # not override the user's choice. This keeps the existing
    # `Tempo.from_iso8601(string, Calendrical.Hebrew)` idiom
    # working unchanged.
    do_from_iso8601(string, calendar)
  end

  defp do_from_iso8601(string, requested_calendar) do
    with {:ok, {tokens, extended}} <- Tokenizer.tokenize(string) do
      from_tokens(tokens, extended, requested_calendar)
    end
  end

  # Everything after tokenization. Shared by `from_iso8601/1,2` and by
  # the profile parsers (`parse_date/1` and friends), which differ only
  # in which tokenizer entry point produced the tokens — the calendar,
  # group, validation and IXDTF stages are identical whatever shape the
  # value turned out to be.
  defp from_tokens(tokens, extended, requested_calendar) do
    with {:ok, effective_calendar} <- resolve_calendar(requested_calendar, extended),
         {:ok, parsed} <- Parser.parse(tokens, effective_calendar),
         # Endpoint calendars first: a group is expanded in its value's own
         # calendar, so a Hebrew endpoint's quarter holds Hebrew months.
         parsed = maybe_resolve_endpoint_calendars(parsed, requested_calendar),
         {:ok, expanded} <- Group.expand_groups(parsed, effective_calendar),
         # Propagate before validating. `2026-09-02T18:00/2026-09-02T20:00[Australia/Melbourne]`
         # binds the suffix to the `to` endpoint, so an unpropagated pair reaches
         # `validate_endpoint_order/2` as a floating `from` against a zoned `to` and
         # is rejected as out of order. Propagation never overwrites, so running it
         # again after `attach_extended/2` (which applies a *top-level* suffix) is a
         # no-op for the endpoints this pass already placed in a zone.
         expanded = propagate_endpoint_frame(expanded),
         {:ok, validated} <- Validation.validate(expanded, effective_calendar),
         attached = attach_extended(validated, extended),
         propagated = propagate_endpoint_frame(attached),
         :ok <- Validation.validate_zone_existence(propagated),
         :ok <- enforce_critical_zone_offset(propagated) do
      {:ok, without_calendar_names(propagated)}
    end
  end

  # A `[u-ca=NAME]` suffix names a calendar, and by here it has: the value's
  # `:calendar` is the module the name resolves to, each endpoint's is its
  # own, and a trailing suffix has reached the start it is also written for.
  # The name is dropped, so a value's calendar is recorded once, as its
  # module, and a value read from text is equal to the same value made with a
  # calendar module. What is left of a suffix is its zone and its tags, or
  # `nil` when it had neither.
  defp without_calendar_names(%__MODULE__{extended: %{} = extended} = tempo),
    do: %{tempo | extended: zone_and_tags(extended)}

  defp without_calendar_names(%Tempo.Interval{} = interval) do
    %{
      interval
      | from: without_calendar_names(interval.from),
        to: without_calendar_names(interval.to),
        repeat_rule: without_calendar_names(interval.repeat_rule)
    }
  end

  defp without_calendar_names(%Tempo.Set{} = set),
    do: map_members(set, &without_calendar_names/1)

  defp without_calendar_names(%Tempo.Range{first: first, last: last} = range),
    do: %{range | first: without_calendar_names(first), last: without_calendar_names(last)}

  defp without_calendar_names(other), do: other

  defp zone_and_tags(extended) do
    case Map.delete(extended, :calendar) do
      %{zone_id: nil, zone_offset: nil, tags: tags} when map_size(tags) == 0 -> nil
      kept -> kept
    end
  end

  # A zone or offset on either endpoint applies to a floating other: forward
  # as ISO 8601-1 §5.5.1 says, and backward from a `[zone]` suffix IXDTF writes
  # at the end. The pair-level rule (never overwriting) lives on
  # `Tempo.Interval` so the parser and `Interval.new/1` cannot disagree about
  # what the same endpoints mean.
  defp propagate_endpoint_frame(%Interval{from: from, to: to} = interval) do
    {from, to} = Interval.propagate_endpoint_frame(from, to)
    %{interval | from: from, to: to}
  end

  # A set's member that is an interval is read as an interval is.
  defp propagate_endpoint_frame(%Tempo.Set{} = set),
    do: map_members(set, &propagate_endpoint_frame/1)

  defp propagate_endpoint_frame(other), do: other

  defp map_members(%Tempo.Set{set: members, except: except} = set, fun),
    do: %{set | set: Enum.map(members, fun), except: Enum.map(except, fun)}

  # A per-endpoint IXDTF `u-ca` suffix (`1447Y9M1D[u-ca=islamic-civil]/…`,
  # the form `to_iso8601/1` emits for non-Gregorian interval endpoints)
  # determines that endpoint's calendar the same way a top-level suffix
  # does for a whole value — otherwise the endpoint's units would be
  # interpreted in the default calendar while its tag claims another,
  # breaking the serialise/re-parse round trip. Applies only when the
  # caller didn't choose a calendar explicitly: an explicit calendar
  # always wins.
  defp maybe_resolve_endpoint_calendars(%Tempo.Interval{} = interval, :from_ixdtf_or_default) do
    %{
      interval
      | from: resolve_endpoint_calendar(interval.from),
        to: resolve_endpoint_calendar(interval.to)
    }
  end

  defp maybe_resolve_endpoint_calendars(%Tempo.Set{} = set, :from_ixdtf_or_default),
    do: map_members(set, &maybe_resolve_endpoint_calendars(&1, :from_ixdtf_or_default))

  defp maybe_resolve_endpoint_calendars(other, _requested_calendar), do: other

  defp resolve_endpoint_calendar(%__MODULE__{extended: %{calendar: type}} = endpoint)
       when is_atom(type) and not is_nil(type) do
    case Calendrical.calendar_from_cldr_calendar_type(type) do
      {:ok, calendar} -> %{endpoint | calendar: calendar}
      {:error, _reason} -> endpoint
    end
  end

  defp resolve_endpoint_calendar(endpoint), do: endpoint

  # Resolve the effective calendar for a parse.
  #
  # * Explicit user calendar always wins.
  # * Otherwise, if the IXDTF `[u-ca=NAME]` suffix is present, its
  #   atom is resolved to a `Calendrical.*` module via
  #   `Calendrical.calendar_from_cldr_calendar_type/1`.
  # * Otherwise, fall back to `Calendrical.Gregorian`.
  defp resolve_calendar(:from_ixdtf_or_default, nil),
    do: {:ok, Calendrical.Gregorian}

  defp resolve_calendar(:from_ixdtf_or_default, %{calendar: nil}),
    do: {:ok, Calendrical.Gregorian}

  defp resolve_calendar(:from_ixdtf_or_default, %{calendar: name}) when is_atom(name),
    do: Calendrical.calendar_from_cldr_calendar_type(name)

  defp resolve_calendar(:from_ixdtf_or_default, _extended),
    do: {:ok, Calendrical.Gregorian}

  # An explicit calendar always wins — but validate it is a usable
  # calendar module first. Passing a namespace like `Calendrical.Islamic`
  # (whose concrete forms are `.Civil`, `.UmmAlQura`, …) must return a
  # clean error, not crash deep in validation with `UndefinedFunctionError`.
  defp resolve_calendar(calendar, _extended) when is_atom(calendar) do
    if Code.ensure_loaded?(calendar) and function_exported?(calendar, :months_in_year, 1) do
      {:ok, calendar_iso_as_gregorian(calendar)}
    else
      {:error, InvalidCalendarError.exception(calendar: calendar)}
    end
  end

  @doc false
  def attach_extended(result, nil), do: result

  def attach_extended(%__MODULE__{extended: existing} = tempo, extended) do
    # An endpoint-local `:extended` parsed from a per-endpoint IXDTF
    # suffix (`2022-06-15T10:00[Europe/Paris]/…`) takes precedence
    # over a top-level suffix. The top-level suffix is only used as
    # a default when the endpoint carries none of its own.
    case existing do
      nil -> %{tempo | extended: extended}
      _map -> tempo
    end
  end

  def attach_extended(%Tempo.Range{} = range, extended) do
    %{
      range
      | first: attach_extended(range.first, extended),
        last: attach_extended(range.last, extended)
    }
  end

  def attach_extended(%Tempo.Interval{} = interval, extended) do
    # A top-level suffix on an interval propagates to each endpoint
    # unless that endpoint carries its own IXDTF info (which the
    # parser has already attached to `endpoint.extended`).
    %{
      interval
      | from: attach_extended(interval.from, extended),
        to: attach_extended(interval.to, extended),
        repeat_rule: rule_extended(interval, extended)
    }
  end

  # A set's suffix is each member's that has none of its own, as an
  # interval's is each endpoint's: `{2026-06-15T10:00,2026-06-16T10:00}[Europe/Paris]`
  # is two times in Paris. Its calendar is already the members' calendar.
  def attach_extended(%Tempo.Set{} = set, extended),
    do: map_members(set, &attach_extended(&1, %{extended | calendar: nil}))

  def attach_extended(other, _extended), do: other

  # A recurrence with no start of its own (`R/../P1Y/FL3M20DN[+09:00]`) keeps
  # the suffix on its rule, which gives it to the start a window supplies, so
  # its occurrences are in the zone the suffix names.
  defp rule_extended(%Tempo.Interval{from: %__MODULE__{}, repeat_rule: rule}, _extended), do: rule

  # The calendar a suffix names is already the rule's calendar, so only the
  # zone and the tags are kept on it.
  defp rule_extended(%Tempo.Interval{from: from, repeat_rule: %__MODULE__{} = rule}, extended)
       when from in [nil, :undefined],
       do: attach_extended(rule, %{extended | calendar: nil})

  defp rule_extended(%Tempo.Interval{repeat_rule: rule}, _extended), do: rule

  @doc """
  Bang variant of `from_iso8601/2`: the parsed value, or a raised
  exception.

  ### Arguments

  * `string` is any ISO 8601 formatted string, optionally followed by
    an IXDTF suffix.

  * `calendar_or_options` (optional) is a calendar module or a
    keyword list of options, as for `from_iso8601/2`.

  ### Returns

  * The parsed value: a `t:t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.Duration.t/0` or `t:Tempo.Set.t/0`.

  ### Examples

      iex> Tempo.from_iso8601!("2022-11-20")
      ~o"2022Y11M20D"

      iex> Tempo.from_iso8601!("2022Y")
      ~o"2022Y"

      iex> Tempo.from_iso8601!("2026-06-15T14:30[Australia/Sydney]")
      ~o"2026Y6M15DT14H30M[Australia/Sydney]"

  """
  @spec from_iso8601!(String.t(), Calendar.calendar() | keyword()) ::
          t() | Tempo.Interval.t() | Tempo.Duration.t() | Tempo.Set.t() | no_return()
  def from_iso8601!(string, calendar_or_options \\ []) when is_binary(string) do
    case from_iso8601(string, calendar_or_options) do
      {:ok, value} -> value
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Parse a duration, written in ISO 8601.

  `parse/2` reads every shape and returns whichever type the string
  turned out to be. When the caller already knows the profile its value
  belongs to — an iCalendar `DURATION` property, a duration-form
  `TRIGGER` (RFC 5545 §3.3.6) — that is one guarantee short: a property
  holding a date-time parses *successfully as the wrong type*, and the
  mistake surfaces later, somewhere else. A duration is read in ISO 8601
  only; unlike a date, it has no locale text form to read.

  This function takes the profile as the caller's declaration. Only a
  duration is admitted, and the whole string must be one, so a
  duration carrying a qualifier (`P1D~`), a set of durations
  (`{P1D,P2D}`), and a value that merely begins with a duration
  (`P1D/2026-06-15`) are all rejected rather than silently truncated
  or stripped.

  Being a narrower grammar it is also a shorter path — the interval
  and set alternatives are never tried — though correctness, not
  speed, is the reason to prefer it.

  ### Arguments

  * `string` is the candidate ISO 8601 duration.

  ### Returns

  * `{:ok, duration}` where `duration` is a `t:Tempo.Duration.t/0`.

  * `{:error, %Tempo.ParseError{}}` when the string is not a duration,
    or is not *only* a duration.

  ### Examples

      iex> Tempo.parse_duration("PT1H")
      {:ok, ~o"PT1H"}

      iex> Tempo.parse_duration("P1Y2M3DT4H5M6S")
      {:ok, ~o"P1Y2M3DT4H5M6S"}

      iex> Tempo.parse_duration("-PT30M")
      {:ok, ~o"PT-30M"}

  A date-time is not a duration, and says so rather than succeeding as
  the wrong type:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_duration("2026-06-15")

  """
  @spec parse_duration(String.t()) :: {:ok, Duration.t()} | {:error, error_reason()}
  def parse_duration(string) when is_binary(string) do
    with {:ok, tokens} <- Tokenizer.tokenize_duration(string) do
      {:ok, Parser.parse(tokens)}
    end
  end

  @doc """
  Raising version of `parse_duration/1`.

  ### Arguments

  * `string` is the candidate ISO 8601 duration.

  ### Returns

  * The `t:Tempo.Duration.t/0`.

  ### Examples

      iex> Tempo.parse_duration!("PT1H30M")
      ~o"PT1H30M"

  """
  @spec parse_duration!(String.t()) :: Duration.t() | no_return()
  def parse_duration!(string) when is_binary(string) do
    case parse_duration(string) do
      {:ok, duration} -> duration
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  @doc """
  Parse a date, written in ISO 8601 or in a locale's own words.

  `parse_date/2` reads what `parse/2` reads and requires the value to
  be a date, saying so when it is not. A date at any resolution is
  accepted — a year (`"2026"`), a month (`"2026-06"`, `"June 2026"`), a
  week (`"2026-W12"`) or a day (`"2026-06-15"`, `"2026-166"`,
  `"15 June 2026"`). A date carrying a time of day is not.

  Prefer this over `parse/2` wherever the field is known to hold a
  date. A date, a datetime and a time all come back from `parse/2` as a
  `t:Tempo.t/0`, so a time of day arriving in a date field is not
  detected at the point of parsing — it is detected much later, or not
  at all.

  ### Arguments

  * `string` is the date to parse.

  ### Options

  * `:locale` is the locale whose words text is read in. Defaults to
    `Localize.get_locale/0`.

  * `:calendar` is the calendar module to parse against. Defaults to
    the calendar named by an IXDTF `[u-ca=NAME]` suffix, or
    `Calendrical.Gregorian`.

  * `:reference_date` is the "today" that two-digit years pivot on and
    partial dates inherit from, when the input is text.

  * `:strict` when `true` rejects a value whose numeric offset
    disagrees with its IXDTF zone (RFC 9557 §4.2). Defaults to `false`.

  ### Returns

  * `{:ok, t:Tempo.t/0}` when the string is a date.

  * `{:error, exception}` when it is not a date, or is a date followed
    by anything else.

  ### Examples

      iex> Tempo.parse_date("2026-06-15")
      {:ok, ~o"2026Y6M15D"}

      iex> Tempo.parse_date("2026-06")
      {:ok, ~o"2026Y6M"}

      iex> Tempo.parse_date("15 June 2026", locale: :en)
      {:ok, ~o"2026Y6M15D"}

  A datetime is not a date, and says so rather than succeeding as the
  wrong shape:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_date("2026-06-15T10:30")

  """
  @spec parse_date(String.t(), keyword()) :: {:ok, t()} | {:error, error_reason()}
  def parse_date(string, options \\ []) when is_binary(string) and is_list(options) do
    parse_kind(string, :date, options)
  end

  @doc """
  Raising version of `parse_date/2`.

  ### Arguments

  * `string` is the date to parse.

  ### Options

  See `parse_date/2`.

  ### Returns

  * The `t:Tempo.t/0`.

  ### Examples

      iex> Tempo.parse_date!("2026-06-15")
      ~o"2026Y6M15D"

  """
  @spec parse_date!(String.t(), keyword()) :: t() | no_return()
  def parse_date!(string, options \\ []) when is_binary(string) and is_list(options) do
    raise_on_error(parse_date(string, options))
  end

  @doc """
  Parse a datetime, written in ISO 8601 or in a locale's own words.

  `parse_datetime/2` reads what `parse/2` reads and requires the value
  to carry both a date and a time of day. A date alone is not a
  datetime — use `parse_date/2` for that — and neither is a time
  alone.

  ### Arguments

  * `string` is the datetime to parse.

  ### Options

  See `parse_date/2`.

  ### Returns

  * `{:ok, t:Tempo.t/0}` when the string is a datetime.

  * `{:error, exception}` when it is not.

  ### Examples

      iex> Tempo.parse_datetime("2026-06-15T10:30")
      {:ok, ~o"2026Y6M15DT10H30M"}

      iex> Tempo.parse_datetime("2026-06-15T10:30Z")
      {:ok, ~o"2026Y6M15DT10H30MZ"}

      iex> Tempo.parse_datetime("15 June 2026 14:30", locale: :en)
      {:ok, ~o"2026Y6M15DT14H30M"}

  A date with no time of day is not a datetime:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_datetime("2026-06-15")

  """
  @spec parse_datetime(String.t(), keyword()) :: {:ok, t()} | {:error, error_reason()}
  def parse_datetime(string, options \\ []) when is_binary(string) and is_list(options) do
    parse_kind(string, :datetime, options)
  end

  @doc """
  Raising version of `parse_datetime/2`.

  ### Arguments

  * `string` is the datetime to parse.

  ### Options

  See `parse_date/2`.

  ### Returns

  * The `t:Tempo.t/0`.

  ### Examples

      iex> Tempo.parse_datetime!("2026-06-15T10:30")
      ~o"2026Y6M15DT10H30M"

  """
  @spec parse_datetime!(String.t(), keyword()) :: t() | no_return()
  def parse_datetime!(string, options \\ []) when is_binary(string) and is_list(options) do
    raise_on_error(parse_datetime(string, options))
  end

  @doc """
  Parse a time of day, written in ISO 8601 or in a locale's own words.

  `parse_time/2` reads what `parse/2` reads and requires the value to
  be a time of day, with no date.

  ### Ambiguity is resolved in favour of the profile

  ISO 8601 basic format makes some strings both a valid year and a
  valid time of day: `"2026"` is the year 2026 and also 20:26. The
  general grammar resolves the ambiguity structurally, preferring the
  date reading, so `from_iso8601("2026")` is a year. A caller of
  `parse_time/2` has declared the field holds a time, and that
  declaration is what resolves the ambiguity here — the same string
  reads as 20:26.

      iex> Tempo.from_iso8601("2026")
      {:ok, ~o"2026Y"}

      iex> Tempo.parse_time("2026")
      {:ok, ~o"T20H26M"}

  This is the only profile whose *result* can differ from
  `from_iso8601/1` rather than only its acceptance. Reach for
  `parse_time/2` when the field genuinely holds a time; the ambiguity
  it resolves is in the format, not in the parser.

  ### Arguments

  * `string` is the time of day to parse.

  ### Options

  See `parse_date/2`.

  ### Returns

  * `{:ok, t:Tempo.t/0}` when the string is a time of day.

  * `{:error, exception}` when it is not.

  ### Examples

      iex> Tempo.parse_time("10:30")
      {:ok, ~o"T10H30M"}

      iex> Tempo.parse_time("T10:30")
      {:ok, ~o"T10H30M"}

      iex> Tempo.parse_time("2:30 PM", locale: :en)
      {:ok, ~o"T14H30M"}

  A datetime is not a time of day:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_time("2026-06-15T10:30")

  """
  @spec parse_time(String.t(), keyword()) :: {:ok, t()} | {:error, error_reason()}
  def parse_time(string, options \\ []) when is_binary(string) and is_list(options) do
    parse_kind(string, :time, options)
  end

  @doc """
  Raising version of `parse_time/2`.

  ### Arguments

  * `string` is the time of day to parse.

  ### Options

  See `parse_date/2`.

  ### Returns

  * The `t:Tempo.t/0`.

  ### Examples

      iex> Tempo.parse_time!("10:30")
      ~o"T10H30M"

  """
  @spec parse_time!(String.t(), keyword()) :: t() | no_return()
  def parse_time!(string, options \\ []) when is_binary(string) and is_list(options) do
    raise_on_error(parse_time(string, options))
  end

  @doc """
  Parse an interval, written in ISO 8601 or in a locale's own words.

  Every form ISO 8601 gives an interval is accepted — a pair of
  datetimes, a datetime and a duration in either order, an open-ended
  pair, and any of those carrying a repeat rule — and so is a range in
  the locale's words (`"May 5 – May 10, 2026"`).

  A `t:Tempo.Interval.t/0` is already distinguishable from the other
  shapes `parse/2` returns, so this adds a named error where a
  match would otherwise raise `MatchError`, rather than a type
  guarantee unavailable by other means.

  ### Arguments

  * `string` is the interval to parse.

  ### Options

  See `parse_date/2`.

  ### Returns

  * `{:ok, t:Tempo.Interval.t/0}` when the string is an interval.

  * `{:error, exception}` when it is not.

  ### Examples

      iex> Tempo.parse_interval("2026-06-15/2026-06-20")
      {:ok, ~o"2026Y6M15D/20D"}

      iex> Tempo.parse_interval("R5/2026-06-15/P1D")
      {:ok, ~o"R5/2026Y6M15D/P1D"}

      iex> Tempo.parse_interval("May 5 – May 10, 2026", locale: :en)
      {:ok, ~o"2026Y5M5D/10D"}

  A single date is not an interval, even though every Tempo value spans
  one — an implicit span is not written with a range operator:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_interval("2026-06-15")

  """
  @spec parse_interval(String.t(), keyword()) ::
          {:ok, Tempo.Interval.t()} | {:error, error_reason()}
  def parse_interval(string, options \\ []) when is_binary(string) and is_list(options) do
    parse_kind(string, :interval, options)
  end

  @doc """
  Raising version of `parse_interval/2`.

  ### Arguments

  * `string` is the interval to parse.

  ### Options

  See `parse_date/2`.

  ### Returns

  * The `t:Tempo.Interval.t/0`.

  ### Examples

      iex> Tempo.parse_interval!("2026-06-15/2026-06-20")
      ~o"2026Y6M15D/20D"

  """
  @spec parse_interval!(String.t(), keyword()) :: Tempo.Interval.t() | no_return()
  def parse_interval!(string, options \\ []) when is_binary(string) and is_list(options) do
    raise_on_error(parse_interval(string, options))
  end

  # The shared profile pipeline. Only the tokenizer entry point differs
  # from `from_iso8601/2` — everything downstream of tokenization is the
  # same, so a profile parse resolves calendars, expands groups and
  # validates exactly as the general one does.
  defp parse_profile(string, profile, options) do
    calendar = Keyword.get(options, :calendar, :from_ixdtf_or_default)

    with {:ok, {tokens, extended}} <- Tokenizer.tokenize(string, profile),
         {:ok, value} <- from_tokens(tokens, extended, calendar) do
      enforce_strict(value, options)
    end
  end

  # A typed parser reads its ISO 8601 profile first. A string the
  # profile does not describe is then read as the locale's text, as
  # `parse/2` reads it, and kept only when it is of the kind asked for.
  # ISO 8601 that names no real date (`2026-02-30`) stays that error
  # rather than being read again as text, and a string neither reads
  # keeps the profile's error.
  defp parse_kind(string, kind, options) do
    case parse_profile(string, kind, options) do
      {:error, %ParseError{} = iso_error} -> text_of_kind(string, kind, options, iso_error)
      result -> result
    end
  end

  defp text_of_kind(string, kind, options, iso_error) do
    case parse_text(string, options) do
      {:ok, value} -> of_kind(value, kind, string)
      {:error, _text_error} -> {:error, iso_error}
    end
  end

  defp of_kind(value, kind, string) do
    case value_kind(value) do
      ^kind ->
        {:ok, value}

      other ->
        {:error,
         ParseError.exception(
           input: string,
           reason: "it reads as #{kind_phrase(other)}, not #{kind_phrase(kind)}"
         )}
    end
  end

  defp value_kind(%Interval{}), do: :interval
  defp value_kind(%Duration{}), do: :duration

  defp value_kind(%__MODULE__{} = tempo) do
    case split(tempo) do
      {%__MODULE__{}, nil} -> :date
      {nil, %__MODULE__{}} -> :time
      {%__MODULE__{}, %__MODULE__{}} -> :datetime
    end
  end

  defp kind_phrase(:date), do: "a date"
  defp kind_phrase(:datetime), do: "a datetime"
  defp kind_phrase(:time), do: "a time of day"
  defp kind_phrase(:interval), do: "an interval"
  defp kind_phrase(:duration), do: "a duration"

  defp raise_on_error({:ok, value}), do: value
  defp raise_on_error({:error, exception}) when is_exception(exception), do: raise(exception)
  defp raise_on_error({:error, reason}), do: raise(ArgumentError, inspect(reason))

  # Apply the `strict: true` IXDTF offset/zone consistency check when
  # requested; otherwise the value passes through unchanged.
  # Intervals and sets carry no top-level zone/offset pair to check, so
  # `strict:` is a no-op for them.
  defp enforce_strict(%Tempo{} = tempo, options) do
    if Keyword.get(options, :strict, false) do
      case Compare.validate_zone_offset(tempo) do
        :ok -> {:ok, tempo}
        {:error, _exception} = error -> error
      end
    else
      {:ok, tempo}
    end
  end

  defp enforce_strict(other, _options), do: {:ok, other}

  # RFC 9557 §4.2: marking a zone critical (`[!Europe/Paris]`) makes
  # offset/zone consistency mandatory — a disagreeing offset is rejected
  # unconditionally, independent of the `strict:` option (which is the
  # stricter, opt-in superset that also rejects *elective* disagreement).
  # An elective (non-critical) zone leaves the offset authoritative and
  # the zone advisory, so nothing is enforced.
  defp enforce_critical_zone_offset(%__MODULE__{} = tempo) do
    if zone_critical?(tempo), do: Compare.validate_zone_offset(tempo), else: :ok
  end

  defp enforce_critical_zone_offset(%Interval{from: from, to: to}) do
    with :ok <- enforce_critical_zone_offset(from) do
      enforce_critical_zone_offset(to)
    end
  end

  # A set's interval members, and those it excludes, are held to it as an
  # interval on its own is.
  defp enforce_critical_zone_offset(%Tempo.Set{set: members, except: except}) do
    Enum.find_value(members ++ except, :ok, fn member ->
      with :ok <- enforce_critical_zone_offset(member), do: nil
    end)
  end

  defp enforce_critical_zone_offset(_other), do: :ok

  defp zone_critical?(%__MODULE__{extended: extended}) when is_map(extended),
    do: Map.get(extended, :zone_critical, false)

  defp zone_critical?(_other), do: false

  @doc """
  Parse a date, time, datetime, interval, duration or recurrence,
  written in ISO 8601 or in a locale's own words.

  ISO 8601 is read first, with the whole grammar `from_iso8601/2`
  reads — IXDTF suffixes, EDTF qualifiers, intervals, recurrences and
  durations included. A string ISO 8601 does not describe is then read
  as the locale's text by `Calendrical.parse/2` — `"May 16, 2026"`,
  `"2:30 PM"`, `"May 5 – May 10, 2026"` — so one text field can take
  either form.

  The typed parsers — `parse_date/2`, `parse_datetime/2`,
  `parse_time/2`, `parse_interval/2` and `parse_duration/1` — read the
  same input and return an error for a value of any other kind.

  ### Arguments

  * `input` is the string to parse.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is the locale whose month names, AM/PM markers and other
    words text is read in. Defaults to `Localize.get_locale/0`.

  * `:calendar` is the calendar module the input is read in, such as
    `Calendrical.Hebrew`. Defaults to the calendar an IXDTF
    `[u-ca=NAME]` suffix names, or `Calendrical.Gregorian`. A CLDR
    calendar name such as `:hebrew` is not a calendar and returns an
    error.

  * `:reference_date` is the "today" that two-digit years pivot on and
    partial dates inherit from, when the input is text.

  * `:strict` when `true` rejects a value whose numeric offset
    disagrees with its IXDTF zone (RFC 9557 §4.2). Defaults to `false`.

  In text, a UTC offset such as `"+05:00"` becomes the value's shift,
  as `from_iso8601/1` reads it, and a week of the year
  (`"week 1 of 2026"`) is the week `from_iso8601/1` reads in
  `2026-W01`.

  ### Returns

  * `{:ok, value}` — a `t:t/0` for a date, time or datetime, a
    `t:Tempo.Interval.t/0` for an interval or recurrence, a
    `t:Tempo.Duration.t/0` for a duration, or a `t:Tempo.Set.t/0` for
    a set.

  * `{:error, exception}` when the string is neither ISO 8601 nor text
    the locale reads, or is ISO 8601 that names no real date
    (`"2026-02-30"`).

  ### Examples

      iex> Tempo.parse("2026-06-15T10:30", locale: :en)
      {:ok, ~o"2026Y6M15DT10H30M"}

      iex> Tempo.parse("15 June 2026", locale: :en)
      {:ok, ~o"2026Y6M15D"}

      iex> Tempo.parse("2:30 PM", locale: :en)
      {:ok, ~o"T14H30M"}

      iex> Tempo.parse("May 5 – May 10, 2026", locale: :en)
      {:ok, ~o"2026Y5M5D/10D"}

      iex> Tempo.parse("P1DT12H")
      {:ok, ~o"P1DT12H"}

  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, t() | Tempo.Interval.t() | Duration.t() | Tempo.Set.t()}
          | {:error, error_reason()}
  def parse(input, options \\ []) when is_binary(input) do
    case from_iso8601(input, options) do
      {:error, %ParseError{}} -> parse_text(input, options)
      result -> result
    end
  end

  @doc """
  Bang variant of `parse/2`: the parsed value, or a raised exception.

  ### Arguments

  * `input` is the string to parse.

  * `options` is a keyword list of options; see `parse/2`.

  ### Returns

  * The parsed value, as `parse/2` returns it.

  ### Examples

      iex> Tempo.parse!("15 June 2026", locale: :en)
      ~o"2026Y6M15D"

  """
  @spec parse!(String.t(), Keyword.t()) ::
          t() | Tempo.Interval.t() | Duration.t() | Tempo.Set.t()
  def parse!(input, options \\ []) when is_binary(input) do
    case parse(input, options) do
      {:ok, value} -> value
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "Tempo.parse!/2 failed: #{inspect(reason)}"
    end
  end

  # Read a string as the locale's text: Calendrical parses it to a field
  # map (or a pair of them for a range), which `Tempo.new/1` rebuilds.
  defp parse_text(input, options) do
    with {:ok, value} <- Calendrical.parse(input, Keyword.put(options, :as, :map)),
         {:ok, parsed} <- parsed_to_tempo(value) do
      enforce_strict(parsed, options)
    end
  end

  defp parsed_to_tempo(%{} = map), do: new(sanitise_parsed_map(map))

  defp parsed_to_tempo({%{} = from_map, %{} = to_map}) do
    with {:ok, from} <- new(sanitise_parsed_map(from_map)),
         {:ok, to} <- new(sanitise_parsed_map(to_map)) do
      Interval.new(from: from, to: to)
    end
  end

  # Map Calendrical's parsed fields onto `Tempo.new/1`'s components and
  # options. `:microsecond` is dropped because Tempo is second-resolution.
  # An IANA zone becomes the `:zone` option, its offsets derivable from
  # it; a fixed offset, which Calendrical labels `Etc/UTC` beside a
  # non-zero offset, becomes the `:shift` `from_iso8601/1` gives it. A
  # week of a week-based year becomes Tempo's `:week` of that year, and
  # a weekday beside a full date is dropped, the date fixing it
  # (Calendrical drops one that disagrees with the date).
  defp sanitise_parsed_map(map) do
    {offset, map} = pop_offset(map)

    map
    |> Map.drop([:microsecond, :zone_abbr])
    |> put_zone_or_shift(offset)
    |> put_iso_week()
    |> drop_implied_weekday()
  end

  defp pop_offset(map) do
    {utc_offset, map} = Map.pop(map, :utc_offset, 0)
    {std_offset, map} = Map.pop(map, :std_offset, 0)
    {utc_offset + std_offset, map}
  end

  defp put_zone_or_shift(%{time_zone: "Etc/UTC"} = map, offset) when offset != 0 do
    map
    |> Map.delete(:time_zone)
    |> Map.put(:shift, iso_shift(offset))
  end

  defp put_zone_or_shift(map, _offset), do: rename_key(map, :time_zone, :zone)

  # The shift `from_iso8601/1` gives an offset written with minutes:
  # "+05:00" is `[hour: 5, minute: 0]`, "-03:30" `[hour: -3, minute: 30]`.
  defp iso_shift(offset) do
    case Zone.offset_to_shift(offset) do
      [hour: hour] -> [hour: hour, minute: 0]
      shift -> shift
    end
  end

  defp put_iso_week(%{week_of_year: week} = map) do
    {week_based_year, map} = Map.pop(map, :week_based_year)

    map
    |> Map.delete(:week_of_year)
    |> Map.put(:week, week)
    |> put_week_based_year(week_based_year)
  end

  defp put_iso_week(map), do: map

  defp put_week_based_year(map, nil), do: map
  defp put_week_based_year(map, year), do: Map.put(map, :year, year)

  defp drop_implied_weekday(%{year: _, month: _, day: _, day_of_week: _} = map),
    do: Map.delete(map, :day_of_week)

  defp drop_implied_weekday(map), do: map

  defp rename_key(map, from, to) do
    case Map.pop(map, from) do
      {nil, map} -> map
      {value, map} -> Map.put(map, to, value)
    end
  end

  @doc """
  Encode a Tempo value back into an ISO 8601-2 string.

  The output uses the explicit-suffix form (`2022Y11M20D`), which
  is a valid ISO 8601-2 / EDTF representation that round-trips
  cleanly through `from_iso8601/1`. Constructs that exist only
  in ISO 8601-2 Part 2 (seasons, groups, selections,
  uncertainty qualifiers, unspecified digits) are preserved in
  their explicit form.

  IXDTF suffixes follow the value they belong to: a zone
  (`2026Y6M15DT10H0M[Europe/Paris]`), a calendar
  (`2026Y6M15D[u-ca=hebrew]`) and tags (`2026Y6M15D[name=x]`), so
  a zoned or calendar-tagged value round-trips too. An interval's
  `:unit` and `:metadata` have no ISO 8601 form and are not written.

  A value in a calendar other than the Gregorian is written with the identifier that reads back as its calendar, however the value was made: parsed with one, converted with `to_calendar/2`, or built from an Elixir date.

  ### Arguments

  * `value` is a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.Duration.t/0`, or `t:Tempo.Set.t/0`.

  ### Returns

  * `{:ok, iso8601}` — an ISO 8601-2 binary that parses back to the
    same AST.

  * `{:error, %Tempo.Iso8601EncodeError{}}` for a value with no ISO 8601
    form: an interval set, a recurrence set, a conditional member, anything
    that is not a Tempo value, a value holding a cron nearest-weekday, a cron
    day-of-month OR day-of-week union or an ordinal BYDAY across distinct
    weekdays, a recurrence with an end (RFC 5545 `UNTIL`), or a value in a calendar IXDTF
    cannot name (a fiscal year, say) whose dates the Gregorian calendar
    numbers differently.

  ### Examples

      iex> Tempo.from_iso8601!("2022-11-20") |> Tempo.to_iso8601()
      {:ok, "2022Y11M20D"}

      iex> Tempo.from_iso8601!("R5/2022-01-01/P1M") |> Tempo.to_iso8601()
      {:ok, "R5/2022Y1M1D/P1M"}

      iex> {:ok, i} = Tempo.from_iso8601("1984?/2004~")
      iex> Tempo.to_iso8601(i)
      {:ok, "1984Y?/2004Y~"}

      iex> Tempo.to_calendar!(~o"2026-06-15", Calendrical.Hebrew) |> Tempo.to_iso8601()
      {:ok, "5786Y9M30D[u-ca=hebrew]"}

      iex> holidays = Tempo.RecurrenceSet.new!([~o"R/../P1Y/FL12M25DN", ~o"R/../P1Y/FL1M1DN"])
      iex> {:error, error} = Tempo.to_iso8601(holidays)
      iex> Exception.message(error) =~ "no form for a set of recurrences"
      true

  """
  @spec to_iso8601(term()) :: {:ok, String.t()} | {:error, Iso8601EncodeError.t()}
  def to_iso8601(%struct{} = value) when struct in [Tempo, Interval, Duration, Tempo.Set] do
    with nil <- Tempo.Inspect.unencodable(value),
         nil <- Tempo.Inspect.unnamed_calendar(value) do
      {:ok, value |> Tempo.Inspect.to_iodata() |> IO.iodata_to_binary()}
    else
      construct when construct in [:byday, :nearest_weekday, :or_day, :until] ->
        {:error, Iso8601EncodeError.exception(construct: construct, value: value)}

      calendar ->
        {:error,
         Iso8601EncodeError.exception(construct: :calendar, value: value, calendar: calendar)}
    end
  end

  def to_iso8601(value),
    do: {:error, Iso8601EncodeError.exception(construct: unencodable_type(value), value: value)}

  @doc """
  Encode a Tempo value back into an ISO 8601-2 string, raising for a value
  with no ISO 8601 form.

  ### Arguments

  * `value` is a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.Duration.t/0`, or `t:Tempo.Set.t/0`.

  ### Returns

  * An ISO 8601-2 binary that parses back to the same AST.

  ### Raises

  * `Tempo.Iso8601EncodeError` for a value `to_iso8601/1` returns it for.

  ### Examples

      iex> Tempo.to_iso8601!(~o"2022-11-20")
      "2022Y11M20D"

  """
  @spec to_iso8601!(Tempo.t() | Tempo.Interval.t() | Tempo.Duration.t() | Tempo.Set.t()) ::
          String.t()
  def to_iso8601!(value) do
    case to_iso8601(value) do
      {:ok, iso8601} -> iso8601
      {:error, exception} -> raise exception
    end
  end

  defp unencodable_type(%Tempo.RecurrenceSet{}), do: :recurrence_set
  defp unencodable_type(%IntervalSet{}), do: :interval_set
  defp unencodable_type(%Conditional{}), do: :conditional
  defp unencodable_type(_value), do: :value

  @doc """
  Creates a `t:Tempo.t/0` struct from a `t:Date.t/0`.

  ### Arguments

  * `date` is any `t:Date.t/0`.

  ### Returns

  * `t:t/0` or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.from_date ~D[2022-11-20]
      ~o"2022Y11M20D"

  """
  # `new/2` is multi-clause internally; dialyzer unions all return
  # types across clauses even though `from_date/1` always hits the
  # keyword-list clause. Suppress the resulting wide-return warning
  # rather than widen the spec, which would mislead human readers.
  @dialyzer {:nowarn_function, from_date: 1, from_time: 1, from_naive_datetime: 1}

  @spec from_date(date :: Date.t()) :: t()
  def from_date(%{year: year, month: month, day: day, calendar: Calendar.ISO}) do
    AST.build(year: year, month: month, day: day)
  end

  def from_date(%{year: year, month: month, day: day, calendar: Calendrical.Gregorian}) do
    AST.build(year: year, month: month, day: day)
  end

  def from_date(%{year: year, month: month, day: day, calendar: calendar}) do
    AST.build(date_units(year, month, day, calendar), calendar)
  end

  @doc false
  # A date's fields as a value's units: the month and day of a month-based
  # calendar, or the week and the day of the week a week-based calendar keeps
  # in them, so its values take ISO 8601's week date shape as a parsed one does.
  @spec date_units(integer(), integer(), integer(), module()) :: keyword()
  def date_units(year, month, day, Calendrical.Gregorian),
    do: [year: year, month: month, day: day]

  def date_units(year, month, day, calendar) do
    if week_based_calendar?(calendar),
      do: [year: year, week: month, day_of_week: day],
      else: [year: year, month: month, day: day]
  end

  @doc false
  # A calendar that numbers weeks within its year rather than months.
  @spec week_based_calendar?(module()) :: boolean()
  def week_based_calendar?(calendar) do
    Code.ensure_loaded?(calendar) and function_exported?(calendar, :calendar_base, 0) and
      calendar.calendar_base() == :week
  end

  # The unit of a day in a calendar's dates: the day of the week in a
  # week-based calendar.
  defp day_unit(calendar),
    do: if(week_based_calendar?(calendar), do: :day_of_week, else: :day)

  @doc """
  Create a `t:Tempo.Interval.t/0` from an Elixir `Date.Range`,
  converting the range's inclusive bounds to Tempo's half-open
  convention.

  A `Date.Range` enumerates its `last` day; a Tempo interval excludes
  its `to` endpoint. The conversion sets `to` to the day *after*
  `range.last`, so the interval covers exactly the days the range
  enumerates — doing the inclusive-to-half-open bridge once, here,
  instead of leaving an off-by-one for every caller. The range's
  calendar is preserved: a range of fiscal-calendar dates yields an
  interval in that calendar, which composes with Gregorian values
  through Tempo's cross-calendar comparison.

  A stepped range (`Date.range(a, b, 2)`) enumerates a set of days
  rather than a contiguous span, and a descending or empty range is
  not a calendar period — both are refused rather than guessed.

  ### Arguments

  * `range` is a `t:Date.Range.t/0` with step `1` and
    `first <= last`.

  * `options` is a keyword list of options.

  ### Options

  * `:resolution` is a time unit atom applied to both endpoints via
    `at_resolution/2`. The default is the day: `:day`, or
    `:day_of_week` in a week-based calendar.

  ### Returns

  * `{:ok, interval}` where `interval` is a `t:Tempo.Interval.t/0`
    covering exactly the range's days, or

  * `{:error, %Tempo.ConversionError{}}` for a stepped, descending,
    or empty range.

  ### Examples

      iex> {:ok, q3} = Tempo.from_date_range(Calendrical.Interval.quarter(2026, 3, Calendrical.Gregorian))
      iex> q3
      ~o"2026Y7M1D/10M1D"

      iex> {:error, %Tempo.ConversionError{}} =
      ...>   Tempo.from_date_range(Date.range(~D[2026-07-01], ~D[2026-07-31], 2))

  """
  @spec from_date_range(Date.Range.t(), Keyword.t()) ::
          {:ok, Tempo.Interval.t()} | {:error, error_reason()}
  def from_date_range(range, options \\ [])

  def from_date_range(%Date.Range{step: 1, first: first, last: last} = range, options) do
    if Compare.compare_days(first, last) == :gt do
      {:error,
       ConversionError.exception(
         value: range,
         target: Tempo.Interval,
         reason:
           "An empty Date.Range spans no days, so it cannot become an interval " <>
             "(Tempo intervals have positive extent)."
       )}
    else
      resolution = Keyword.get_lazy(options, :resolution, fn -> day_unit(first.calendar) end)

      with %Tempo{} = from <- at_resolution(from_date(first), resolution),
           %Tempo{} = to <- at_resolution(from_date(Calendrical.next(last, :day)), resolution) do
        Interval.new(from: from, to: to)
      end
    end
  end

  def from_date_range(%Date.Range{step: step} = range, _options) do
    {:error,
     ConversionError.exception(
       value: range,
       target: Tempo.Interval,
       reason:
         "A stepped or descending Date.Range (step #{step}) enumerates a set of days, " <>
           "not a contiguous span, so it cannot become a single interval. " <>
           "Express the selection with `Tempo.select/2` instead."
     )}
  end

  @doc """
  Raising version of `from_date_range/2`.

  ### Arguments

  * `range` is a `t:Date.Range.t/0` with step `1` and
    `first <= last`.

  * `options` is a keyword list of options — see
    `from_date_range/2`.

  ### Returns

  * The `t:Tempo.Interval.t/0` covering exactly the range's days.

  ### Examples

      iex> Tempo.from_date_range!(Date.range(~D[2026-07-01], ~D[2026-07-31]))
      ~o"2026Y7M1D/8M1D"

  """
  @spec from_date_range!(Date.Range.t(), Keyword.t()) :: Tempo.Interval.t()
  def from_date_range!(range, options \\ []) do
    case from_date_range(range, options) do
      {:ok, interval} -> interval
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from a `t:Time.t/0`.

  ### Arguments

  * `time` is any `t:Time.t/0`.

  ### Returns

  * `t:t/0` or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.from_time ~T[10:09:00]
      ~o"T10H9M0S"

  """
  @spec from_time(time :: Time.t()) :: t()
  def from_time(%{hour: hour, minute: minute, second: second} = time) do
    AST.build([hour: hour, minute: minute, second: second] ++ microsecond_component(time))
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from a `t:NaiveDateTime.t/0`.

  ### Arguments

  * `naive_datetime` is any `t:NaiveDateTime.t/0`.

  ### Returns

  * `t:t/0` or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.from_naive_datetime ~N[2022-11-20 10:37:00]
      ~o"2022Y11M20DT10H37M0S"

  """
  @spec from_naive_datetime(naive_datetime :: NaiveDateTime.t()) :: t()
  def from_naive_datetime(
        %{
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
          calendar: Calendar.ISO
        } = naive
      ) do
    AST.build(
      [year: year, month: month, day: day, hour: hour, minute: minute, second: second] ++
        microsecond_component(naive)
    )
  end

  def from_naive_datetime(
        %{
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
          calendar: Calendrical.Gregorian
        } = naive
      ) do
    AST.build(
      [year: year, month: month, day: day, hour: hour, minute: minute, second: second] ++
        microsecond_component(naive)
    )
  end

  def from_naive_datetime(
        %{
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
          calendar: calendar
        } = naive
      ) do
    AST.build(
      date_units(year, month, day, calendar) ++
        [hour: hour, minute: minute, second: second] ++ microsecond_component(naive),
      calendar
    )
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from a `t:DateTime.t/0`.

  The DateTime's time zone information is preserved on the Tempo:
  the total offset (`utc_offset + std_offset`) populates the
  `:shift` field, and the IANA zone identifier is stored on the
  `:extended` map under `:zone_id`. Iteration on the returned
  Tempo carries both pieces of metadata through.

  ### Arguments

  * `datetime` is any `t:DateTime.t/0`.

  ### Returns

  * `t:t/0`.

  ### Examples

      iex> Tempo.from_datetime(~U[2022-11-20 10:37:00Z]).time
      [year: 2022, month: 11, day: 20, hour: 10, minute: 37, second: 0]

      iex> Tempo.from_datetime(~U[2022-11-20 10:37:00Z]).shift
      [hour: 0]

      iex> Tempo.from_datetime(~U[2022-11-20 10:37:00Z]).extended.zone_id
      "Etc/UTC"

  """
  @spec from_datetime(DateTime.t()) :: t()
  def from_datetime(
        %DateTime{
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
          time_zone: time_zone,
          utc_offset: utc_offset,
          std_offset: std_offset,
          calendar: calendar
        } = dt
      ) do
    tempo_calendar = calendar_iso_as_gregorian(calendar)

    time =
      date_units(year, month, day, tempo_calendar) ++
        [hour: hour, minute: minute, second: second] ++ microsecond_component(dt)

    total_offset = utc_offset + std_offset

    %__MODULE__{
      time: time,
      shift: Zone.offset_to_shift(total_offset),
      calendar: tempo_calendar,
      extended: %{
        zone_id: time_zone,
        zone_offset: nil,
        zone_critical: false,
        tags: %{}
      }
    }
  end

  # Elixir's `Time`/`NaiveDateTime`/`DateTime` carry sub-second data in
  # a `microsecond: {value, precision}` field with the same shape as
  # Tempo's `:microsecond` component. Thread it through verbatim when
  # `precision > 0`; `{0, 0}` (no sub-second) adds nothing, keeping the
  # value at second resolution.
  defp microsecond_component(%{microsecond: {_value, 0}}), do: []

  defp microsecond_component(%{microsecond: {value, precision}}),
    do: [microsecond: {value, precision}]

  defp microsecond_component(_), do: []

  @doc """
  Returns the resolution of a `t:Tempo.t/0` struct.

  The resolution is the smallest time unit of the
  struct and an appropriate scale.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  ### Returns

  * `{time_unit, scale}`

  ### Examples

      iex> Tempo.resolution ~o"2022"
      {:year, 1}

      iex> Tempo.resolution ~o"2022-11"
      {:month, 1}

      iex> Tempo.resolution ~o"2022-11-20"
      {:day, 1}

      iex> Tempo.resolution ~o"2022Y1M2G3DU"
      {:day, 3}

  """
  @spec resolution(tempo :: t()) :: {atom(), atom() | non_neg_integer()}
  def resolution(%__MODULE__{time: []}), do: {:none, 0}

  def resolution(%__MODULE__{time: units}) when is_list(units) do
    units
    |> Enum.reverse()
    |> hd
    |> unit_resolution()
  end

  def resolution(value), do: raise(not_one_value("resolution/1", value))

  # The finest and coarsest units of a value, as `{finest, coarsest}`:
  # `2022Y1M2G3DU` is `{:day, :year}`. The ISO 8601 parser calls it.
  @doc false
  @spec unit_min_max(tempo :: t | token_list()) :: {time_unit(), time_unit()}
  def unit_min_max(%__MODULE__{time: units}) do
    unit_min_max(units)
  end

  def unit_min_max(units) when is_list(units) do
    {max, _} = unit_resolution(hd(units))
    {min, _} = unit_resolution(hd(Enum.reverse(units)))
    {min, max}
  end

  defp unit_resolution({:selection, selection}), do: unit_min_max(selection)

  # A computed event names a day, the week start (`q`) is context at the
  # scale of the day of the week, as `Tempo.Iso8601.Unit.ordered?/1` reads
  # them, and a §12.10 window runs from a day.
  defp unit_resolution({:event, _name}), do: {:day, 1}
  defp unit_resolution({:interval, _window}), do: {:day, 1}
  defp unit_resolution({:wkst, _day}), do: {:day_of_week, 1}
  defp unit_resolution({unit, {:group, first..last//_}}), do: {unit, last - first + 1}

  # A materialised group is `{unit, {:group, members}, size}` — the
  # third element is the group's own size, which is its resolution.
  defp unit_resolution({unit, {:group, _members}, size}) when is_integer(size), do: {unit, size}
  defp unit_resolution({unit, %Range{last: last}}), do: {unit, last}

  # A microsecond component is `{value, precision}`; the precision
  # (digit count) is its resolution scale — `{:microsecond, 3}` is
  # millisecond resolution.
  defp unit_resolution({:microsecond, {_value, precision}}) when is_integer(precision),
    do: {:microsecond, precision}

  defp unit_resolution({unit, {_value, meta}}) when is_list(meta),
    do: {unit, Keyword.get(meta, :margin_of_error, 1)}

  defp unit_resolution({unit, {_value, continuation}}) when is_function(continuation),
    do: {unit, 1}

  defp unit_resolution({unit, _value}), do: {unit, 1}

  # Order of units from coarsest to finest. Used by the component
  # accessors (`year/1`, `month/1`, `day/1`, `hour/1`, `minute/1`,
  # `second/1`) to decide whether a unit is unambiguous for a given
  # interval span — a unit U is unambiguous iff the interval's span
  # resolution is equal to or finer than U.
  @unit_order [:year, :month, :day, :hour, :minute, :second]

  for {unit, _idx} <- Enum.with_index(@unit_order) do
    @doc """
    Return the `#{unit}` component of a Tempo value, or `nil` if
    the value doesn't specify one.

    The accessors (`year/1`, `month/1`, `day/1`, `hour/1`,
    `minute/1`, `second/1`) are commodity component extractors so
    callers never have to reach into struct fields in user-facing
    code.

    ### Arguments

    * `value` is a `t:t/0` or `t:Tempo.Interval.t/0`.

    ### Returns

    * The component value as an integer when unambiguous.

    * `nil` when the value doesn't specify that unit (e.g.
      `Tempo.day(~o"2026")` returns `nil` — the year value has no
      day).

    * Raises `ArgumentError` when called on an interval whose span
      covers multiple values of that unit (e.g. `Tempo.day/1` on a
      month-spanning interval is ambiguous).

    ### Examples

        iex> Tempo.#{unit}(~o"2026-06-15T10:30:45")
        #{case unit do
      :year -> 2026
      :month -> 6
      :day -> 15
      :hour -> 10
      :minute -> 30
      :second -> 45
    end}

        iex> Tempo.#{unit}(~o"2026")
        #{if unit == :year, do: 2026, else: "nil"}

    """
    @spec unquote(unit)(t() | Tempo.Interval.t()) :: integer() | nil
    def unquote(unit)(value), do: component(value, unquote(unit))
  end

  @doc """
  Return the `week` component of a Tempo value, or `nil` if the
  value doesn't specify one.

  Completes the component-accessor family (`year/1` … `second/1`) for
  week-axis values — `~o"2026Y32W"`, a Hebrew or Islamic calendar
  week, or a retail-calendar week — so callers never reach into
  struct fields. `:week` lives on its own axis rather than in the
  linear year-to-second order, so its interval ambiguity rule is
  axis-aware instead of generated with the others: an interval
  answers when it spans exactly one week, or sits inside one.

  ### Arguments

  * `value` is a `t:t/0` or `t:Tempo.Interval.t/0`.

  ### Returns

  * The week number as an integer when unambiguous.

  * `nil` when the value doesn't specify a week (e.g.
    `Tempo.week(~o"2026-06-15")` — a month-axis date has no week
    component).

  * Raises `ArgumentError` when called on an interval spanning more
    than one week.

  ### Examples

      iex> Tempo.week(~o"2026Y32W")
      32

      iex> Tempo.week(~o"2026-06-15")
      nil

      iex> {:ok, hebrew_week} = Tempo.from_iso8601("5786-W03", Calendrical.Hebrew)
      iex> Tempo.week(hebrew_week)
      3

      iex> {:ok, interval} = Tempo.to_interval(~o"2026Y32W")
      iex> Tempo.week(interval)
      32

  """
  @spec week(t() | Tempo.Interval.t()) :: integer() | nil
  def week(%__MODULE__{time: time}) when is_list(time) do
    case List.keyfind(time, :week, 0) do
      {:week, value} when is_integer(value) -> value
      _absent_or_several -> nil
    end
  end

  def week(%Tempo.Interval{} = interval) do
    case read_span(interval) do
      %Tempo.Interval{from: %__MODULE__{}} = span -> span_week(span)
      _no_start -> raise no_component_error(:week, interval)
    end
  end

  def week(value), do: raise(no_component_error(:week, value))

  defp span_week(%Tempo.Interval{from: %__MODULE__{} = from, to: to}) do
    from_week = week(from)

    cond do
      from_week == nil ->
        nil

      not match?(%__MODULE__{}, to) ->
        from_week

      single_granule_unit(from, to) == :week ->
        from_week

      week(to) == from_week ->
        from_week

      true ->
        raise ArgumentError,
              "Tempo.week/1 is ambiguous for an interval spanning more than one week. " <>
                "Use `Tempo.Interval.endpoints/1` and extract the component from each " <>
                "endpoint explicitly."
    end
  end

  # Polymorphic component extraction. A Tempo value reads straight
  # from its time keyword list — nil if absent. An Interval checks
  # unambiguity via the span resolution and raises otherwise.
  defp component(%__MODULE__{time: time}, unit) when is_list(time) do
    # A group of a set is a three-element entry, which `Keyword.get/2` cannot
    # read: it is no one number, as a set is none.
    case List.keyfind(time, unit, 0) do
      {^unit, value} when is_integer(value) -> value
      _absent_or_several -> nil
    end
  end

  defp component(%Tempo.Interval{} = interval, unit) do
    case read_span(interval) do
      %Tempo.Interval{from: %__MODULE__{}} = span -> span_component(span, unit)
      _no_start -> raise no_component_error(unit, interval)
    end
  end

  defp component(value, unit), do: raise(no_component_error(unit, value))

  defp span_component(
         %Tempo.Interval{from: %__MODULE__{time: from_time} = from, to: to} = interval,
         unit
       ) do
    span_res = interval_component_resolution(from, to, interval)

    cond do
      span_res == :undefined ->
        component(%__MODULE__{time: from_time, calendar: nil}, unit)

      unit_finer_or_equal?(span_res, unit) ->
        component(%__MODULE__{time: from_time, calendar: nil}, unit)

      true ->
        raise ArgumentError,
              "Tempo.#{unit}/1 is ambiguous for an interval spanning at #{inspect(span_res)} resolution. " <>
                "Use `Tempo.Interval.endpoints/1` and extract the component from each endpoint explicitly."
    end
  end

  # The span an accessor reads an interval as: one written with a duration as
  # its two ends, and each end as the point it names (`20C/21C` is
  # `2000Y/2100Y`). A recurrence is many spans, and an end that names several
  # is none; each raises its error.
  defp read_span(%Tempo.Interval{recurrence: recurrence} = interval) when recurrence != 1,
    do: raise(ConversionError.exception(value: interval, reason: :recurring_interval))

  defp read_span(%Tempo.Interval{} = interval) do
    case interval |> Interval.resolve_duration_form() |> Interval.endpoints_as_points() do
      {:ok, %Tempo.Interval{to: nil, duration: %Duration{}}} -> raise uncounted_duration(interval)
      {:ok, span} -> span
      {:error, exception} -> raise exception
    end
  end

  # A start with a duration that cannot be counted from it (a month added to
  # a week date, `2026Y25WXK/P1M`) has no end to read a span to, and
  # `to_interval/1` says why.
  defp uncounted_duration(interval) do
    case to_interval(interval) do
      {:error, exception} -> exception
      {:ok, _span} -> ConversionError.exception(value: interval, target: Tempo.Interval)
    end
  end

  # A component is read from a date or time value, or from the start of an
  # interval that has one. Anything else has none to read.
  defp no_component_error(unit, %Tempo.Interval{} = interval) do
    ArgumentError.exception(
      "Tempo.#{unit}/1 reads an interval from its start, and #{inspect(interval)} has none."
    )
  end

  defp no_component_error(unit, value) do
    ArgumentError.exception(
      "Tempo.#{unit}/1 takes a date or time value or an interval, and #{inspect(value)} " <>
        "is neither."
    )
  end

  # An interval one granule wide at `from`'s own resolution — e.g.
  # `[2026Y12M, 2027Y1M)`, which is December 2026, exactly one month — is
  # unambiguous at that resolution. Its half-open upper bound rolls into
  # the next coarser unit (here the year), which `Interval.resolution/1`
  # reports as the span resolution and so masks the real one. Report
  # `from`'s resolution for such single-granule spans; a wider span keeps
  # the coarsest unit at which the endpoints genuinely differ.
  defp interval_component_resolution(from, to, interval) do
    case single_granule_unit(from, to) do
      nil -> Interval.resolution(interval)
      unit -> unit
    end
  end

  defp single_granule_unit(%__MODULE__{} = from, %__MODULE__{} = to) do
    {unit, _value} = resolution(from)
    stepped = Math.add(from, %Tempo.Duration{time: [{unit, 1}]})
    if Compare.compare_endpoints(stepped, to) == :same, do: unit
  end

  defp single_granule_unit(_from, _to), do: nil

  # `u_res` is finer-or-equal to `u_target` iff u_res's index in
  # @unit_order is >= u_target's index. (:year is coarsest at 0;
  # :second is finest at 5.)
  defp unit_finer_or_equal?(u_res, u_target) do
    Enum.find_index(@unit_order, &(&1 == u_res)) >=
      Enum.find_index(@unit_order, &(&1 == u_target))
  end

  @doc """
  Returns a boolean indicating if a `t:Tempo.t/0` struct
  is anchored to the timeline.

  Anchored means that the time representation contains
  enough information for it to be located in a single
  location on the timeline.  In practise this means the
  if the tempo struct has a `:year` value then
  it is anchored. An unspecified year (`X*Y`) is any year
  and so no place on the timeline: a value written with one
  is as unanchored as the same value with no year.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  ### Returns

  * `true` or `false`

  ### Examples

      iex> Tempo.anchored? ~o"2022"
      true

      iex> Tempo.anchored? ~o"2M"
      false

      iex> Tempo.anchored? ~o"X*Y2M"
      false

  """
  @spec anchored?(tempo :: t) :: boolean()
  def anchored?(%__MODULE__{time: [{:year, :any} | _rest]}) do
    false
  end

  def anchored?(%__MODULE__{time: [{:year, _year} | _rest]}) do
    true
  end

  def anchored?(%__MODULE__{}) do
    false
  end

  def anchored?(value), do: raise(not_one_value("anchored?/1", value))

  @doc """
  Check that an IXDTF value's explicit numeric offset agrees with its
  IANA time zone at the value's wall instant.

  A value such as `2022-11-20T10:37:00+05:00[Europe/Paris]` carries both
  a numeric offset and a zone; Paris is `+01:00` in November, so the
  stated `+05:00` is inconsistent. By default the zone wins and the
  offset is consulted only for DST disambiguation; this surfaces the
  disagreement instead (RFC 9557 §4.2). The same check backs the
  `strict: true` option of `from_iso8601/2`.

  ### Arguments

  * `tempo` is a `t:t/0`.

  ### Returns

  * `:ok` when the offset agrees, or when there is nothing to check (no
    zone, no explicit offset, or an unanchored value).

  * `{:error, t:Tempo.ZoneOffsetMismatchError.t/0}` on disagreement.

  ### Examples

      iex> {:ok, t} = Tempo.from_iso8601("2022-11-20T10:37:00+01:00[Europe/Paris]")
      iex> Tempo.validate_zone_offset(t)
      :ok

      iex> {:error, %Tempo.ZoneOffsetMismatchError{}} =
      ...>   Tempo.from_iso8601("2022-11-20T10:37:00+05:00[Europe/Paris]", strict: true)

  """
  @spec validate_zone_offset(t()) :: :ok | {:error, Tempo.ZoneOffsetMismatchError.t()}
  defdelegate validate_zone_offset(tempo), to: Tempo.Compare

  @doc """
  Truncates a tempo struct to the specified resolution.

  Truncation removes the time units that have a
  higher resolution than the specified `truncate_to`
  option.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  * `truncate_to` is any time unit. The default
    is `:day`.

  ### Returns

  * `truncated` is a tempo struct that is truncated or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.trunc ~o"2022-11-21T09:30:00"
      ~o"2022Y11M21D"

      iex> Tempo.trunc ~o"2022-11-21T09:30:00", :minute
      ~o"2022Y11M21DT9H30M"

      iex> Tempo.trunc ~o"2022-11-21T09:30:00", :year
      ~o"2022Y"

  ## Truncating to a week

  A Gregorian value has no week component, so `:week` does not coarsen
  it the way `:month` does — it names **the day that value's week
  begins on**, at day resolution:

      iex> Tempo.trunc(~o"2026-08-16T10:00:00", :week)
      ~o"2026Y8M10D"

  Which day that is comes from the value's own calendar, so a Sunday
  belongs to the preceding week under `Calendrical.Gregorian` and
  begins one of its own under a Sunday-start calendar. A value already
  on the week axis holds `:week` as a component and coarsens normally.

  Units belonging to another axis and naming nothing expressible —
  `:day_of_week`, `:day_of_year` against a Gregorian value — return a
  `t:Tempo.ResolutionError.t/0` rather than an unrelated coarser unit.

  A week numbers each of its days, so the day of a week date in a
  calendar of weeks is its day of the week: `:day` truncates such a
  value to it, as it extends and rounds one to it. A week of a calendar
  of months is extended to the date of its first day.

  """
  @spec trunc(tempo :: t, truncate_to :: time_unit()) :: t | {:error, error_reason()}
  def trunc(tempo, truncate_to \\ :day)

  def trunc(%__MODULE__{} = tempo, truncate_to) do
    with {:ok, truncate_to} <- validate_unit(truncate_to),
         :ok <- one_value(tempo) do
      tempo
      |> truncate(day_unit(truncate_to, tempo))
      |> qualified_as_it_stands()
      |> NotBuilt.result()
    end
  end

  def trunc(value, _truncate_to), do: {:error, not_one_value("trunc/2", value)}

  # A group of a set (`{1,2}G3MU`) is kept as a three-element entry that names
  # a span in each of its groups, so a value that holds one is no one value to
  # truncate, to place or to read a day from.
  defp one_value(%__MODULE__{time: time} = tempo) when is_list(time) do
    if Enum.any?(time, &match?({_unit, {:group, _members}, _size}, &1)),
      do: {:error, materialisation_error(tempo, :grouped_component)},
      else: :ok
  end

  defp one_value(_value), do: :ok

  # A value already on the week axis holds `:week` as a component, so
  # the ordinary rule applies.
  defp truncate(%__MODULE__{time: time} = tempo, :week) when is_list(time) do
    if Keyword.has_key?(time, :week) do
      take_units(tempo, :week)
    else
      week_of(tempo)
    end
  end

  # The month a date is in is the month it names in a year that begins with
  # its first month. In one that does not the calendar counts the year's
  # months from the day it begins, and is asked which holds the date: 10
  # March 1750 in `Calendrical.Julian.March25` is in its year's twelfth.
  defp truncate(
         %__MODULE__{time: [{:year, year}, {:month, month}, {:day, day} | _rest]} = tempo,
         :month
       )
       when is_integer(year) and is_integer(month) and is_integer(day) do
    calendar = calendar_of(tempo)

    with false <- UnitValues.year_begins_with_first_month?(year, calendar),
         {:ok, month_of_year} <- UnitValues.month_of_date(year, month, day, calendar) do
      take_units(%{tempo | time: [year: year, month: month_of_year]}, :month)
    else
      _the_month_it_names -> take_units(tempo, :month)
    end
  end

  defp truncate(%__MODULE__{time: time} = tempo, truncate_to) do
    with :ok <- same_axis(time, truncate_to, tempo) do
      take_units(tempo, truncate_to)
    end
  end

  # A Gregorian value cannot hold a week as a component, but the day
  # its week begins on is a perfectly good Gregorian value — and it is
  # what "the week containing this" means when the calendar has no week
  # granule to name. Day resolution, matching `trunc(tempo, :day)`.
  #
  # The week starts where the value's own calendar starts its weeks:
  # `Calendrical.Gregorian` begins on Monday, so a Sunday belongs to the
  # week before it, while a calendar configured to begin on Sunday puts
  # the same Sunday first in its week.
  defp week_of(%__MODULE__{} = tempo) do
    with %__MODULE__{} = day <- trunc(tempo, :day),
         {:ok, date} <- to_date(day) do
      date
      |> Date.beginning_of_week(:default)
      |> from_date()
      |> then(&%{&1 | shift: tempo.shift, extended: tempo.extended})
      |> take_units(:day)
    end
  end

  defp take_units(%__MODULE__{time: time} = tempo, truncate_to) do
    {dated, selection} = Enum.split_while(time, &(not match?({:selection, _selection}, &1)))

    case Enum.take_while(dated, &(Unit.compare(&1, truncate_to) in [:gt, :eq])) do
      [] ->
        {:error,
         ResolutionError.exception(
           operation: :trunc,
           target: truncate_to,
           current: resolution(tempo) |> elem(0),
           reason: :empty_resolution
         )}

      kept ->
        %{tempo | time: kept_with_selection(kept, dated, selection, truncate_to)}
    end
  end

  # A selection (`2026Y4ML1K1IN`, the first Monday of April) is finer than the
  # units before it. Truncating to one of them drops it (`2026Y4M`), and
  # truncating to a unit finer than them all leaves the value as it is.
  defp kept_with_selection(kept, _dated, [], _truncate_to), do: kept

  defp kept_with_selection(kept, dated, selection, truncate_to) do
    if kept == dated and Unit.compare(List.last(dated), truncate_to) == :gt,
      do: dated ++ selection,
      else: kept
  end

  # Units that belong to one calendar axis and no other. `:year`,
  # `:hour`, `:minute` and `:second` are shared by all three and so
  # constrain nothing.
  @gregorian_only [:month, :day]
  @week_only [:day_of_week]
  @ordinal_only [:day_of_year]

  # Truncating to a unit the value's axis does not have is a category
  # error rather than a coarsening: without a guard, `take_units/2`
  # walks past the units it cannot match and answers with whatever
  # coarser one it lands on — a plausible-looking value of the wrong
  # kind. `:week` is the exception and is handled above, because the
  # day a week begins on *is* expressible on every axis.
  defp same_axis(time, truncate_to, tempo) do
    with target when target != :any <- axis_of([truncate_to]),
         value when value != :any <- time |> Keyword.keys() |> value_axis(truncate_to),
         true <- target != value do
      {:error,
       ResolutionError.exception(
         operation: :trunc,
         target: truncate_to,
         current: resolution(tempo) |> elem(0),
         reason:
           "#{inspect(truncate_to)} is on the #{target} axis and this value is on the " <>
             "#{value} axis — truncating between axes is not a coarsening. Convert the " <>
             "value to the #{target} axis first."
       )}
    else
      _same_axis_or_unconstrained -> :ok
    end
  end

  # A week has no month, so a value written to the week (`2026-W25`) is on
  # the week axis when a month is asked of it, with or without a day of the
  # week. Asked for a day it is left as it is: it is coarser than one.
  defp value_axis(units, :month) do
    if :week in units, do: :week, else: axis_of(units)
  end

  defp value_axis(units, _truncate_to), do: axis_of(units)

  defp axis_of(units) do
    cond do
      Enum.any?(units, &(&1 in @week_only)) -> :week
      Enum.any?(units, &(&1 in @ordinal_only)) -> :ordinal
      Enum.any?(units, &(&1 in @gregorian_only)) -> :gregorian
      true -> :any
    end
  end

  @doc """
  Rounds a value to the nearest value of a unit.

  The value rounds to the start of the unit it is in, or to the start
  of the next, whichever its own start is nearer to: 21 November 2022
  rounds to December at month resolution and to 2023 at year
  resolution, where `trunc/2` would keep November and 2022. Half way
  rounds up, as `Kernel.round/1` rounds a half: half past ten is
  eleven o'clock, and noon is the next day.

  How far into a unit a value is, is measured in the unit as it is
  there: 16 January is 15 days into a month of 31, so it rounds to
  January, and 15 February is 14 days into a month of 28, so it
  rounds to March. A value in a zone is measured in the zone's days,
  one of which is 23 hours long when the clocks go forward.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0` that is one value: a date, a
    time of day, or a date and time.

  * `round_to` is any time unit. The default is `:day`.

  ### Returns

  * The rounded value, at the resolution of `round_to`.

  * `{:error, exception}` when `round_to` is finer than the value is
    written to (`t:Tempo.RoundingError.t/0`), is a unit the value's
    axis does not have (`t:Tempo.ResolutionError.t/0`), or is a month
    whose length depends on a year the value does not have
    (`t:Tempo.UnanchoredError.t/0`), and when the value holds several
    values or is not a date or time value.

  ### Examples

      iex> Tempo.round ~o"2022-11-21", :day
      ~o"2022Y11M21D"

      iex> Tempo.round ~o"2022-11-21", :month
      ~o"2022Y12M"

      iex> Tempo.round ~o"2022-11-21", :year
      ~o"2023Y"

      iex> Tempo.round ~o"2026-06-15T12:00", :day
      ~o"2026Y6M16D"

      iex> Tempo.round ~o"2026-06-15T10:29", :hour
      ~o"2026Y6M15DT10H"

      iex> Tempo.round ~o"T10:30", :hour
      ~o"T11H"

      iex> Tempo.round ~o"T23:45", :hour
      ~o"T0H"

  """
  @spec round(tempo :: t, round_to :: time_unit()) :: t | {:error, error_reason()}
  def round(tempo, round_to \\ :day)

  def round(%__MODULE__{} = tempo, round_to) do
    with {:ok, round_to} <- validate_unit(round_to),
         :ok <- one_to_round(tempo, round_to) do
      tempo |> Rounding.round(round_to) |> qualified_as_it_stands() |> NotBuilt.result()
    end
  end

  def round(value, _round_to), do: {:error, not_one_value("round/2", value)}

  # A value's qualifications name the units it holds, so one that has dropped
  # a unit has dropped its qualifier.
  defp qualified_as_it_stands(%__MODULE__{} = tempo), do: Qualification.only(tempo)
  defp qualified_as_it_stands(other), do: other

  # Rounding reads each unit as the one number it is, so a value that holds
  # several (a set, a mask, an unspecified unit, a group) is none to round.
  defp one_to_round(%__MODULE__{time: time} = tempo, round_to) do
    if is_list(time) and Steps.whole_units?(time) do
      :ok
    else
      {:error,
       RoundingError.exception(
         unit: round_to,
         value: tempo,
         reason:
           "Cannot round #{inspect(tempo)}: it holds several values (a set, a range, a " <>
             "group or unspecified digits), and one value is rounded."
       )}
    end
  end

  @doc """
  Splits a value into its date and its time of day.

  Each part keeps what the value carries: its calendar, its zone or
  offset, its qualification and its metadata. The date of a value in a
  zone is the date in that zone, and its time the time of day there, so
  `at/2` of the two parts is the value.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  ### Returns

  * `{date, time}`, where either is `nil` when the value has none.

  ### Examples

      iex> Tempo.split(~o"2026-06-15T14:30:00")
      {~o"2026Y6M15D", ~o"T14H30M0S"}

      iex> Tempo.split(~o"2026-06-15T14:30[Europe/Paris]")
      {~o"2026Y6M15D[Europe/Paris]", ~o"T14H30M[Europe/Paris]"}

      iex> Tempo.split(~o"2026-06-15")
      {~o"2026Y6M15D", nil}

  """
  @spec split(t()) :: {t() | nil, t() | nil}
  def split(%__MODULE__{time: time} = tempo) when is_list(time) do
    case Split.split(time) do
      {date, []} ->
        {%{tempo | time: date}, nil}

      {[], time} ->
        {nil, %{tempo | time: time}}

      {date, time} ->
        {Qualification.only(%{tempo | time: date}), Qualification.only(%{tempo | time: time})}
    end
  end

  def split(value), do: raise(not_one_value("split/1", value))

  # Merge `from`'s components into `base`, validated in `base`'s own
  # calendar — the engine of `at/2` and `on/2`, which are the public way to
  # combine two values. Passes through any non-`{:ok, _}` from
  # `Validation.validate/2`, which dialyzer widens beyond the spec.
  #
  # A month, a day of one or a day of the year is not placed on a value of a
  # calendar of weeks: its year is the calendar's own, not the Gregorian year
  # they belong to (the NRF year 2026 holds January 2027), so the day they
  # would name there is not one of that year's.
  @doc false
  @dialyzer {:nowarn_function, merge: 2}
  @spec merge(t(), t()) :: t() | {:error, error_reason()}
  def merge(%__MODULE__{} = base, %Tempo{} = from) do
    calendar = calendar_of(base)

    if Validation.written_in_another_calendar?(from.time, calendar),
      do: {:error, placed_by_month_error(base, from, calendar)},
      else: merge_in(base, from, calendar)
  end

  defp merge_in(base, from, calendar) do
    units = Enumeration.merge(base.time, from.time)
    qualifications = Qualification.merge(base.qualifications, from.qualifications)

    with {:ok, framed} <- in_one_frame(base, from) do
      placed = Qualification.only(%{framed | time: units, qualifications: qualifications})

      case Validation.validate(placed, calendar) do
        {:ok, tempo} -> tempo
        other -> other
      end
    end
  end

  # The zone or offset of a value placed on another. A value with none takes
  # the other's, whichever of the two it is: 14:30 in Paris placed on 15 June
  # is 14:30 in Paris on that day. Two that are each in a zone are in the same
  # one, or are no one value.
  defp in_one_frame(base, from) do
    case {frame(base), frame(from)} do
      {same, same} -> {:ok, base}
      {_frame, nil} -> {:ok, base}
      {nil, _frame} -> {:ok, in_frame_of(base, from)}
      _two_frames -> {:error, two_frames_error(from)}
    end
  end

  defp frame(%__MODULE__{shift: nil, extended: nil}), do: nil

  defp frame(%__MODULE__{shift: shift, extended: extended}) do
    zone = {shift, zone_field(extended, :zone_id), zone_field(extended, :zone_offset)}
    if zone == {nil, nil, nil}, do: nil, else: zone
  end

  defp zone_field(nil, _field), do: nil
  defp zone_field(extended, field), do: Map.get(extended, field)

  defp in_frame_of(base, %__MODULE__{shift: shift, extended: extended}) do
    %{base | shift: shift, extended: with_zone_of(base.extended, extended)}
  end

  defp with_zone_of(nil, extended), do: zone_alone(extended)

  defp with_zone_of(base_extended, extended),
    do:
      Map.merge(
        base_extended,
        Map.take(extended || %{}, [:zone_id, :zone_offset, :zone_critical])
      )

  # The zone of a value's annotations, without its tags, which stay its own.
  defp zone_alone(nil), do: nil

  defp zone_alone(%{zone_id: nil, zone_offset: nil}), do: nil

  defp zone_alone(extended) do
    Map.merge(
      %{tags: %{}, zone_id: nil, zone_offset: nil, zone_critical: false},
      Map.take(extended, [:zone_id, :zone_offset, :zone_critical])
    )
  end

  defp two_frames_error(from) do
    ZonedTempoError.exception(
      operation: "place a value in one zone on a value in another",
      value: from
    )
  end

  defp placed_by_month_error(base, from, calendar) do
    ConversionError.exception(
      value: from,
      target: calendar,
      reason:
        "#{inspect(calendar)} is a calendar of weeks, with no months, so #{inspect(from)} " <>
          "cannot be placed on #{inspect(base)}; place a week (W) and a day of the week (K) " <>
          "read in that calendar, or write the whole date, which is read as the Gregorian " <>
          "day and converted."
    )
  end

  @doc """
  Place one value on another: the value with a year keeps it, and the
  other supplies the finer components it lacks.

  `~o"2026-06-15" |> Tempo.at(~o"T17")` reads *"15 June **at** 17:00"*
  and `~o"T17" |> Tempo.on(~o"2026-06-15")` *"17:00 **on** 15 June"*;
  both are the same value. The finer side is taken whole, so
  `~o"2026-06-15T09:30" |> Tempo.at(~o"T17")` is 17:00, not 17:30.
  When neither value has a year the coarser keeps its components —
  `~o"3M" |> Tempo.on(~o"2D")` is `~o"3M2D"`, the 2nd of March in any
  year — and when both have one there is nothing to place. `at/2` and
  `on/2` are one function, so use the word that reads.

  A time of day is a time of one day, so placed on a year, a month or a
  week it is on the first day of it: `~o"2026-06" |> Tempo.at(~o"T17")`
  is 17:00 on 1 June, as `~o"2026-06T17"` is read. ISO 8601 wants the
  date of a date and time complete (ISO 8601-1 §5.4.1), so this reading
  is Tempo's own. That time on each day is written with the days named:
  `~o"2026Y6M{1..-1}DT17H"` is 17:00 on each day of June.

  A value with a year is checked against its calendar, so
  `~o"2026-02" |> Tempo.on(~o"29D")` is an error: 2026 is not a leap
  year. A month, a week and a day are numbered by their calendar, so
  two values that hold them are of one calendar: a Gregorian
  `~o"6M15D"` placed on a Hebrew year is an error and not the fifteenth
  of that year's sixth month, which is written by reading it in that
  calendar (`Tempo.from_iso8601("6M15D", Calendrical.Hebrew)`). A time
  of day is placed on a value of any calendar. A value of a calendar
  of weeks, such as `Calendrical.ISOWeek`, takes a week and a day of
  the week of that calendar.

  An interval is placed endpoint by endpoint, so nine to five on 15
  June, or 2–15 April in 2027, is one call; an open end, or one its
  duration gives, stays as it is.

  ### Arguments

  * `value` and `other` are `t:#{__MODULE__}.t/0` values, at most one
    of them with a year, or one of them a `t:Tempo.Interval.t/0` whose
    endpoints are placed on the other.

  ### Returns

  * `{:ok, tempo}` with the one value placed on the other, or
    `{:ok, interval}` with an interval's endpoints placed.

  * `{:error, reason}` when both values have a year, when the two hold
    date units of different calendars, when the result is not a date in
    its calendar or an interval whose start is before its end, or when
    either argument is not a Tempo value or interval.

  ### Examples

      iex> Tempo.at(~o"2026-06-15", ~o"T17")
      {:ok, ~o"2026Y6M15DT17H"}

      iex> Tempo.at(~o"T17", ~o"2026-06-15")
      {:ok, ~o"2026Y6M15DT17H"}

      iex> Tempo.at(~o"3M", ~o"2D")
      {:ok, ~o"3M2D"}

      iex> Tempo.at(~o"2026-06-15", ~o"T09/T17")
      {:ok, ~o"2026Y6M15DT9H/T17H"}

      iex> Tempo.at(~o"2026-06", ~o"T17")
      {:ok, ~o"2026Y6M1DT17H"}

  """
  @dialyzer {:nowarn_function, at: 2}

  @spec at(t() | Interval.t(), t() | Interval.t()) ::
          {:ok, t() | Interval.t()} | {:error, error_reason()}
  def at(%__MODULE__{} = value, %__MODULE__{} = other) do
    with :ok <- one_value(value),
         :ok <- one_value(other),
         :ok <- one_calendar(value, other) do
      value = without_unspecified_year(value)
      other = without_unspecified_year(other)
      place(value, other, anchored?(value), anchored?(other))
    end
  end

  def at(%Interval{} = interval, %__MODULE__{} = other), do: place_interval(interval, other)
  def at(%__MODULE__{} = value, %Interval{} = interval), do: place_interval(interval, value)

  def at(value, other) do
    {:error,
     ArgumentError.exception(
       "at/2 and on/2 place a Tempo value on a value or an interval, not " <>
         "#{inspect(value)} on #{inspect(other)}."
     )}
  end

  # A month, a week and a day are numbered by their calendar: the sixth month
  # of a Hebrew year is not June. So a value that holds a date unit is placed
  # only on a value of its own calendar, and its numbers are never read in
  # the other's. A time of day is the same in every calendar and is placed on
  # any.
  defp one_calendar(%__MODULE__{} = value, %__MODULE__{} = other) do
    if dated?(value) and dated?(other) and placing_calendar(value) != placing_calendar(other),
      do: {:error, two_calendars_error(value, other)},
      else: :ok
  end

  defp dated?(%__MODULE__{time: time}) when is_list(time),
    do: Enum.any?(time, &(elem(&1, 0) not in [:hour, :minute, :second, :microsecond]))

  defp dated?(%__MODULE__{}), do: false

  defp placing_calendar(%__MODULE__{calendar: Calendar.ISO}), do: Calendrical.Gregorian
  defp placing_calendar(%__MODULE__{} = value), do: calendar_of(value)

  # A month or a day placed on a value of a calendar of weeks keeps the error
  # that says what such a calendar takes.
  defp two_calendars_error(value, other) do
    cond do
      by_month_on_weeks?(value, other) ->
        placed_by_month_error(other, value, placing_calendar(other))

      by_month_on_weeks?(other, value) ->
        placed_by_month_error(value, other, placing_calendar(value))

      true ->
        ConversionError.exception(
          value: value,
          target: placing_calendar(other),
          reason:
            "#{inspect(value)} is a value of #{inspect(placing_calendar(value))} and " <>
              "#{inspect(other)} one of #{inspect(placing_calendar(other))}, and a month, a " <>
              "week and a day are numbered by their calendar: read both in one calendar to " <>
              "place one on the other."
        )
    end
  end

  defp by_month_on_weeks?(%__MODULE__{time: time}, %__MODULE__{} = base),
    do: Validation.written_in_another_calendar?(time, placing_calendar(base))

  # An interval is placed endpoint by endpoint; an open end, or one its
  # duration gives, has nothing to place.
  defp place_interval(%Interval{from: from, to: to} = interval, other) do
    with {:ok, placed_from} <- place_endpoint(from, other),
         {:ok, placed_to} <- place_endpoint(to, other),
         :ok <- in_order(placed_from, placed_to) do
      {:ok, %{interval | from: placed_from, to: placed_to}}
    end
  end

  defp place_endpoint(%__MODULE__{} = endpoint, other), do: at(endpoint, other)
  defp place_endpoint(open_or_derived, _other), do: {:ok, open_or_derived}

  defp in_order(%__MODULE__{} = from, %__MODULE__{} = to) do
    with {:ok, _interval} <- Interval.new(from, to), do: :ok
  end

  defp in_order(_from, _to), do: :ok

  # A value that is an unspecified year and nothing else (`X*Y`) names no
  # unit to place, so the other value is where it was.
  defp place(value, %__MODULE__{time: [{:year, :any}]}, _year, _other_year), do: {:ok, value}
  defp place(%__MODULE__{time: [{:year, :any}]}, other, _year, _other_year), do: {:ok, other}

  defp place(value, other, true = _year, true = _other_year) do
    {:error,
     ArgumentError.exception(
       "at/2 and on/2 place a value without a year on one with a year, and both " <>
         "#{inspect(value)} and #{inspect(other)} have one."
     )}
  end

  defp place(value, other, false = _year, true = _other_year), do: placed(graft(other, value))
  defp place(value, other, true = _year, false = _other_year), do: placed(graft(value, other))

  defp place(value, other, false = _year, false = _other_year) do
    if leading_key(value) >= leading_key(other),
      do: placed(graft(value, other)),
      else: placed(graft(other, value))
  end

  defp placed(%__MODULE__{} = tempo), do: {:ok, tempo}
  defp placed(error), do: error

  # An unspecified year (`X*Y6M`) is no year, so it is where the year of the
  # value it is placed on goes.
  defp without_unspecified_year(%__MODULE__{time: [{:year, :any} | [_ | _] = rest]} = value),
    do: %{value | time: rest}

  defp without_unspecified_year(%__MODULE__{} = value), do: value

  # How coarse a value's leading unit is; a value with none is the finest.
  defp leading_key(%__MODULE__{time: [{unit, _value} | _rest]}) do
    case Unit.fetch_sort_key(unit) do
      {:ok, key} -> key
      :error -> -1
    end
  end

  defp leading_key(%__MODULE__{}), do: -1

  @doc """
  Bang variant of `at/2` — returns the placed value or raises.

  ### Examples

      iex> Tempo.at!(~o"2026-06-15", ~o"T17")
      ~o"2026Y6M15DT17H"

  """
  @spec at!(t() | Interval.t(), t() | Interval.t()) :: t() | Interval.t()
  def at!(value, other) do
    case at(value, other) do
      {:ok, tempo} -> tempo
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "at!/2 failed: #{inspect(reason)}"
    end
  end

  @doc """
  Place one value on another — `at/2`, spelled for how English reads
  a date.

  `at/2` reads for a time of day (*"15 June **at** 17:00"*) and `on/2`
  for a day (*"17:00 **on** 15 June"*, *"March, **on** the 2nd"*).
  They are the same function: the value with a year keeps it, and the
  other supplies what it lacks.

  ### Arguments

  * `value` and `other` are `t:#{__MODULE__}.t/0` values, at most one
    of them with a year.

  ### Returns

  * `{:ok, tempo}` or `{:error, reason}` — see `at/2`.

  ### Examples

      iex> Tempo.on(~o"T17", ~o"2026-06-15")
      {:ok, ~o"2026Y6M15DT17H"}

      iex> Tempo.on(~o"3M", ~o"2D")
      {:ok, ~o"3M2D"}

      iex> Tempo.on(~o"4M2D/4M16D", ~o"2027")
      {:ok, ~o"2027Y4M2D/16D"}

  """
  @spec on(t() | Interval.t(), t() | Interval.t()) ::
          {:ok, t() | Interval.t()} | {:error, error_reason()}
  def on(value, other), do: at(value, other)

  @doc """
  Bang variant of `on/2` — returns the placed value or raises. See
  `on/2`.

  ### Examples

      iex> Tempo.on!(~o"3M", ~o"2D")
      ~o"3M2D"

  """
  @spec on!(t() | Interval.t(), t() | Interval.t()) :: t() | Interval.t()
  def on!(value, other), do: at!(value, other)

  # Compose two values along the resolution axis: keep `high_source`'s
  # components strictly coarser than `low_value`'s coarsest, then graft
  # `low_value` on. The engine of `at/2`, whose value with a year (or
  # coarser value) is the high source. Reusing `merge/2` keeps a single
  # validated path; pre-trimming `high_source` is what makes it a clean
  # replace rather than a leaky overlay.
  #
  # A selection is not a unit to place: it stays after the units it selects
  # in (ISO 8601-2 §12.11). The first Monday of April placed on 2027 is
  # `2027Y4ML1K1IN`, and 09:00 placed on that is each Monday it selects at
  # 09:00, `2027Y4ML1K1INT9H`.
  defp graft(%__MODULE__{} = high_source, %__MODULE__{} = low_value) do
    case {split_at_selection(high_source.time), split_at_selection(low_value.time)} do
      {{_units, []}, {_low_units, []}} ->
        graft_units(high_source, low_value)

      {{_units, []}, {low_units, selection}} ->
        high_source |> graft_units(%{low_value | time: low_units}) |> with_units_after(selection)

      {{_units, _selection}, {low_units, []}} ->
        with_units_after(high_source, low_units)

      _both_select ->
        {:error,
         ArgumentError.exception(
           "at/2 and on/2 place one selection, and #{inspect(high_source)} and " <>
             "#{inspect(low_value)} both hold one."
         )}
    end
  end

  defp graft_units(%__MODULE__{} = high_source, %__MODULE__{time: []} = low_value),
    do: merge(high_source, low_value)

  defp graft_units(
         %__MODULE__{} = high_source,
         %__MODULE__{time: [{unit, _value} | _]} = low_value
       ) do
    cutoff = Unit.sort_key(unit)
    trimmed = Enum.filter(high_source.time, fn {other, _v} -> Unit.sort_key(other) > cutoff end)
    merge(%{high_source | time: trimmed}, low_value)
  end

  defp split_at_selection(time), do: Enum.split_while(time, &(not match?({:selection, _}, &1)))

  defp with_units_after(%__MODULE__{time: time} = tempo, units) do
    case Validation.validate(%{tempo | time: time ++ units}, calendar_of(tempo)) do
      {:ok, placed} -> placed
      other -> other
    end
  end

  defp with_units_after(error, _units), do: error

  @doc """
  Write a value as an enumeration of its next finer unit, covering the
  same span.

  `~o"2020"` becomes `~o"2020Y{1..12}M"` — the same year, written as its
  twelve months — so the value's resolution rises while its span stays
  the same.

  The months of a year and the days of a month depend on which year or month it is. Under a value naming several, they are written from the first to the last (`{1..-1}`), and each year or month is walked by its own.

  A second is written as its ten tenths and a fraction of a second as its next decimal place, down to a microsecond, which has no finer unit. Such a value inspects with the fractions as a set after the decimal sign (`45.{0..9}S`), a notation `from_iso8601/1` does not read.

  A value that ends in a group is written as the values the group names, in the group's own unit: the second group of three months of 2026 is its April to June. A group stops where its container does (the third ten days of a February are its 21st to its 28th or 29th), so one under several years or months is written only where it names the same values in each.

  ### Arguments

  * `tempo` is a `t:t/0`.

  * `unit` is reserved and must be `nil`.

  ### Returns

  * `{:ok, tempo}` with the finer enumeration added.

  * `{:error, exception}` — a `Tempo.ResolutionError` for a value with no finer unit to be written in (a fraction of a second at microsecond precision), a `Tempo.ConversionError` for a group that names other values in each of the years or months it is under, an `ArgumentError` for a value that is not a `t:t/0` or a `unit` that is not `nil`, and the validation error when the result fails validation.

  ### Examples

      iex> Tempo.extend(~o"2020")
      {:ok, ~o"2020Y{1..12}M"}

      iex> Tempo.extend(~o"2026-06")
      {:ok, ~o"2026Y6M{1..30}D"}

      iex> Tempo.extend(~o"2026Y{6,7}M")
      {:ok, ~o"2026Y{6..7}M{1..-1}D"}

      iex> Tempo.extend(~o"2026Y2G3MU")
      {:ok, ~o"2026Y{4..6}M"}

      iex> {:error, %Tempo.ResolutionError{}} = Tempo.extend(~o"2026-06-15T10:30:45.123456")

  """

  @spec extend(t(), nil) :: {:ok, t()} | {:error, error_reason()}
  def extend(tempo, unit \\ nil)

  def extend(%Tempo{time: time} = tempo, nil) when is_list(time) do
    extended =
      if Enumeration.ends_in_group?(tempo),
        do: extend_group(tempo),
        else: extend_by_finer_unit(tempo)

    NotBuilt.result(extended)
  end

  def extend(%Tempo{time: time}, unit) when is_list(time) do
    {:error,
     ArgumentError.exception(
       "Tempo.extend/2 writes a value by the unit below its own: its second argument is " <>
         "reserved and must be nil, got #{inspect(unit)}."
     )}
  end

  def extend(value, _unit) do
    {:error,
     ArgumentError.exception(
       "Tempo.extend/2 writes one date or time value by its next finer unit, and " <>
         "#{inspect(value)} is not one."
     )}
  end

  # A month is written by its days. In a year that begins with its first
  # month they are counted from one; in one that does not, the calendar
  # lists the month's dates, which are in another month than the one
  # counted, and in two where the year turns within a month.
  defp extend_by_finer_unit(%Tempo{time: [{:year, year}, {:month, month}]} = tempo)
       when is_integer(year) and is_integer(month) do
    calendar = calendar_of(tempo)

    with false <- UnitValues.year_begins_with_first_month?(year, calendar),
         {:ok, runs} <- UnitValues.dates_of_month(year, month, calendar) do
      month_by_its_dates(tempo, runs, calendar)
    else
      _counted_from_one -> extend_by_enumeration(tempo)
    end
  end

  defp extend_by_finer_unit(tempo), do: extend_by_enumeration(tempo)

  defp extend_by_enumeration(tempo) do
    case Enumeration.implicit_enumeration(tempo) do
      {:ok, enumerated} -> Validation.validate(enumerated, calendar_of(tempo))
      {:finest, unit} -> {:error, no_finer_unit_error(tempo, unit)}
    end
  end

  defp month_by_its_dates(tempo, [{year, month, _days} | _rest] = runs, calendar) do
    if Enum.all?(runs, &match?({^year, ^month, _days}, &1)) do
      days = Enum.map(runs, fn {_year, _month, days} -> days end)
      Validation.validate(%{tempo | time: [year: year, month: month, day: days]}, calendar)
    else
      {:error,
       ConversionError.exception(
         value: tempo,
         reason:
           "Cannot write #{inspect(tempo)} by its days: they are in two months of " <>
             "#{inspect(calendar)}, whose year does not begin with its first month, and " <>
             "one value names the days of one."
       )}
    end
  end

  # A group names values of its own unit, the ones its walk yields, and is
  # written as them: a unit below a group is counted from the group's start
  # (ISO 8601-2 §5.4.2), so an enumeration of one would be read as no value
  # of the group is.
  defp extend_group(tempo) do
    with {:ok, written} <- Enumeration.group_as_set(tempo),
         do: Validation.validate(written, calendar_of(tempo))
  end

  defp no_finer_unit_error(tempo, unit) do
    ResolutionError.exception(
      operation: :extend,
      current: unit,
      calendar: calendar_of(tempo),
      reason: no_finer_unit(tempo, unit)
    )
  end

  defp no_finer_unit(tempo, :none), do: "Cannot extend #{inspect(tempo)}: it names no unit."

  defp no_finer_unit(tempo, :microsecond) do
    "Cannot extend #{inspect(tempo)}: a microsecond is the finest unit there is, so it has " <>
      "no finer one to be written in."
  end

  defp no_finer_unit(tempo, unit),
    do: "Cannot extend #{inspect(tempo)}: no unit finer than its #{unit} is defined."

  @doc """
  Bang variant of `extend/2`: the extended value, or a raised exception.

  ### Arguments

  * `tempo` is a `t:t/0`.

  * `unit` is reserved and must be `nil`.

  ### Returns

  * The extended `t:t/0`.

  ### Raises

  * The exception `extend/2` returns.

  ### Examples

      iex> Tempo.extend!(~o"2020")
      ~o"2020Y{1..12}M"

  """
  @spec extend!(t(), nil) :: t()
  def extend!(tempo, unit \\ nil) do
    case extend(tempo, unit) do
      {:ok, zoomed} -> zoomed
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a `t:Tempo.t/0` from any Elixir date/time type.

  Unifies `Date.t`, `Time.t`, `NaiveDateTime.t`, and `DateTime.t`
  into the single `Tempo.t` representation under the principle
  that every date/time value is a bounded interval on the time
  line at some resolution. See the
  [interop guide](interop.html) for what the resulting value
  spans once converted with `to_interval/1`.

  The intended resolution is either given explicitly via the
  `:resolution` option or inferred from the input:

  * `Date.t` → `:day` (Date has no time components).

  * `Time.t`, `NaiveDateTime.t`, `DateTime.t` → `:second`, or
    `:microsecond` when the value carries a declared sub-second
    precision. These types are second-granular by construction, so
    the resolution follows the type's declared precision rather than
    the magnitude of the components — `09:00:00` is a fully
    specified second, not an under-specified hour. Pass an explicit
    `:resolution` to widen to a coarser span (e.g. `:day` for a
    midnight value you want to treat as a whole day).

  * `Date.Range` → a half-open `t:Tempo.Interval.t/0` covering
    exactly the days the range enumerates (the inclusive `last`
    becomes an exclusive day-after `to`), in the range's own
    calendar. Returned as `{:ok, interval}` / `{:error, reason}`
    because a stepped, descending, or empty range is refused — see
    `from_date_range/2`.

  When an explicit `:resolution` is given, the resulting Tempo is
  passed through `at_resolution/2` to either truncate or pad to
  that resolution.

  ### Arguments

  * `value` is any `t:Date.t/0`, `t:Time.t/0`,
    `t:NaiveDateTime.t/0`, or `t:DateTime.t/0`.

  ### Options

  * `:resolution` is a time unit atom (`:year`, `:month`, `:day`,
    `:hour`, `:minute`, `:second`) overriding the inferred
    resolution.

  ### Returns

  * The `t:t/0` at the chosen resolution, or

  * `{:error, reason}` if `:resolution` is incompatible with the
    input.

  ### Examples

      iex> Tempo.from_elixir(~D[2022-06-15])
      ~o"2022Y6M15D"

      iex> Tempo.from_elixir(~T[10:30:00])
      ~o"T10H30M0S"

      iex> Tempo.from_elixir(~N[2022-06-15 10:30:00])
      ~o"2022Y6M15DT10H30M0S"

      iex> Tempo.from_elixir(~N[2022-06-15 00:00:00])
      ~o"2022Y6M15DT0H0M0S"

      iex> {:ok, july} = Tempo.from_elixir(Date.range(~D[2026-07-01], ~D[2026-07-31]))
      iex> july
      ~o"2026Y7M1D/8M1D"

      iex> Tempo.from_elixir(~D[2022-06-15], resolution: :hour)
      ~o"2022Y6M15DT0H"

      iex> Tempo.from_elixir(~N[2022-06-15 10:30:00], resolution: :day)
      ~o"2022Y6M15D"

  """
  @spec from_elixir(
          value :: Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t() | Date.Range.t(),
          options :: Keyword.t()
        ) :: t() | Duration.t() | {:ok, Tempo.Interval.t()} | {:error, error_reason()}
  def from_elixir(value, options \\ [])

  def from_elixir(%Date{} = date, options) do
    resolution = Keyword.get_lazy(options, :resolution, fn -> day_unit(date.calendar) end)

    date
    |> from_date()
    |> at_resolution(resolution)
  end

  # A `Date.Range` describes a span, so it converts to an interval —
  # the inclusive-to-half-open bridge lives in `from_date_range/2`,
  # and the result is tagged (`{:ok, interval}`) because a stepped,
  # descending, or empty range is refused.
  def from_elixir(%Date.Range{} = range, options) do
    from_date_range(range, options)
  end

  def from_elixir(%Time{} = time, options) do
    resolution = Keyword.get(options, :resolution) || infer_time_resolution(time)

    time
    |> from_time()
    |> at_resolution(resolution)
  end

  def from_elixir(%NaiveDateTime{} = naive, options) do
    resolution = Keyword.get(options, :resolution) || infer_datetime_resolution(naive)

    naive
    |> from_naive_datetime()
    |> at_resolution(resolution)
  end

  def from_elixir(%DateTime{} = dt, options) do
    resolution = Keyword.get(options, :resolution) || infer_datetime_resolution(dt)

    dt
    |> from_datetime()
    |> at_resolution(resolution)
  end

  # Elixir's `Duration` (`~> 1.17`) carries the same units as Tempo's,
  # under the same atoms, with the identical `{value, precision}`
  # microsecond tuple — so the mapping is the present (non-zero)
  # components. `:options` is accepted for signature parity with the
  # date/time clauses but has no meaning for a duration.
  def from_elixir(%Elixir.Duration{} = duration, _options) do
    duration
    |> elixir_duration_components()
    |> Duration.new!()
  end

  # Elixir's `Time`, `NaiveDateTime`, and `DateTime` are
  # second-granular by type: a component value of zero (`09:00:00`)
  # is a fully specified second, not an under-specified hour. So
  # resolution follows the type's *declared precision*, never the
  # magnitude of the components — `:microsecond` when a sub-second
  # precision is present, otherwise `:second`. Inferring a coarser
  # resolution from a zero value would conflate "this component is
  # zero" with "this unit was not specified", the very instant/span
  # confusion Tempo exists to remove. It also silently broke
  # round-tripping: `from_elixir(~N[2022-06-15 09:00:00])` used to
  # coarsen to hour resolution, and `to_naive_datetime/1` then
  # failed to reconstitute the second-granular value. Callers that
  # genuinely want a coarser span pass `:resolution`.
  defp infer_time_resolution(%Time{microsecond: {_v, p}}) when p > 0, do: :microsecond
  defp infer_time_resolution(%Time{}), do: :second

  defp infer_datetime_resolution(%{microsecond: {_v, p}}) when p > 0, do: :microsecond
  defp infer_datetime_resolution(%{microsecond: {_v, _p}}), do: :second

  @doc """
  Extend a Tempo's resolution by padding finer units with their
  start-of-unit minimum values.

  `extend_resolution/2` is the scalar counterpart to `extend/2`:
  where `extend/2` adds an implicit enumeration (turning `~o"2020Y"`
  into `~o"2020Y{1..12}M"` — a range), `extend_resolution/2` fills
  in concrete minimums (turning `~o"2020Y"` into `~o"2020Y1M1D"`
  when extended to `:day`). This is the operation needed to align
  resolutions before interval comparison.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  * `target_unit` is the finer resolution to pad to. Must be
    finer than or equal to `tempo`'s current resolution.

  ### Returns

  * The padded `t:t/0`, or

  * `{:error, reason}` when `target_unit` is coarser than the
    current resolution (use `trunc/2` for that direction) or when
    no path exists from the current unit to `target_unit` under
    the tempo's calendar.

  ### Examples

      iex> Tempo.extend_resolution(~o"2020Y", :day)
      ~o"2020Y1M1D"

      iex> Tempo.extend_resolution(~o"2020Y6M", :hour)
      ~o"2020Y6M1DT0H"

  A week of a calendar of months is extended to the date of its first
  day, and a week of a calendar of weeks to its first day of the week:

      iex> Tempo.extend_resolution(~o"2026-W25", :day)
      ~o"2026Y6M15D"

  """
  @spec extend_resolution(tempo :: t, target_unit :: time_unit()) ::
          t | {:error, error_reason()}
  def extend_resolution(%Tempo{} = tempo, target_unit) do
    with %Tempo{} = extended <- extend_resolution_as_written(tempo, target_unit),
         do: extended |> as_calendar_date() |> NotBuilt.result()
  end

  def extend_resolution(value, _target_unit),
    do: {:error, not_one_value("extend_resolution/2", value)}

  @doc false
  # `extend_resolution/2` in the units the value is written in: a week is
  # extended to a day of it in every calendar, the unit a step of days is
  # counted on (`Tempo.Math`), where `extend_resolution/2` gives the date that
  # day is in a calendar of months.
  @spec extend_resolution_as_written(tempo :: t, target_unit :: time_unit()) ::
          t | {:error, error_reason()}
  def extend_resolution_as_written(%Tempo{time: time, calendar: calendar} = tempo, target_unit) do
    with {:ok, target_unit} <- validate_unit(target_unit),
         :ok <- one_value(tempo) do
      target_unit = day_unit(target_unit, tempo)
      {current_unit, _span} = resolution(tempo)

      case Unit.compare(target_unit, current_unit) do
        :eq ->
          tempo

        :gt ->
          {:error,
           ResolutionError.exception(
             operation: :extend,
             current: current_unit,
             target: target_unit
           )}

        :lt ->
          apply_filled_time(tempo, fill_to_resolution(time, current_unit, target_unit, calendar))
      end
    end
  end

  defp apply_filled_time(tempo, {:ok, new_time}), do: %{tempo | time: new_time}
  defp apply_filled_time(_tempo, {:error, _} = err), do: err

  # Walk the standard unit-successor chain, appending one
  # `{next_unit, unit_minimum}` at each step until `target_unit` is
  # reached. If the chain runs out before `target_unit` (no
  # `implicit_enumerator` for the current unit), return an error.
  defp fill_to_resolution(time, current_unit, target_unit, _calendar)
       when current_unit == target_unit do
    {:ok, time}
  end

  # `:microsecond` is deliberately absent from the unit-successor chain
  # (a second is never enumerated into its million microseconds), so the
  # generic walk below cannot reach it. Extension is still well-defined:
  # the start-of-unit minimum is zero microseconds, declared at full
  # (6-digit) precision — the same precision `Tempo.Math` uses when
  # sub-second arithmetic introduces a fraction onto a whole second.
  defp fill_to_resolution(time, :second, :microsecond, _calendar) do
    {:ok, time ++ [microsecond: {0, 6}]}
  end

  # A year is extended below its months from its first day, which the
  # calendar is asked for where the year does not begin with its first
  # month (`Tempo.UnitValues.start_date/2`).
  defp fill_to_resolution([{:year, year}] = time, :year, target_unit, calendar)
       when is_integer(year) and target_unit not in [:year, :month, :week] do
    with false <- UnitValues.year_begins_with_first_month?(year, calendar),
         {:ok, {year, month, day}} <- UnitValues.start_date(time, calendar) do
      fill_to_resolution([year: year, month: month, day: day], :day, target_unit, calendar)
    else
      _from_its_first_month -> fill_by_unit(time, :year, target_unit, calendar)
    end
  end

  defp fill_to_resolution(time, current_unit, target_unit, calendar),
    do: fill_by_unit(time, current_unit, target_unit, calendar)

  defp fill_by_unit(time, current_unit, target_unit, calendar) do
    case Unit.implicit_enumerator(current_unit, calendar) do
      nil ->
        {:error,
         ResolutionError.exception(
           operation: :extend,
           current: current_unit,
           target: target_unit,
           calendar: calendar,
           reason: :no_path
         )}

      {next_unit, range} ->
        new_time = with_first(time, next_unit, range_first(range), calendar)
        fill_to_resolution(new_time, next_unit, target_unit, calendar)
    end
  end

  defp range_first(%Range{first: first}), do: first

  # A unit is extended to the first value of the unit below it. A month's
  # first day is asked of the calendar: it is the first of the month, or in
  # a year that does not begin with its first month the first date of the
  # month the calendar counts (`Tempo.UnitValues.with_first_day/2`).
  defp with_first(time, :day, 1, calendar), do: UnitValues.with_first_day(time, calendar)
  defp with_first(time, unit, minimum, _calendar), do: time ++ [{unit, minimum}]

  @doc """
  Return a Tempo at the specified resolution, dispatching to
  `trunc/2` or `extend_resolution/2` based on whether `target_unit`
  is coarser or finer than the current resolution.

  This is the unified entry point for normalising resolution. It
  is idempotent when `target_unit` matches the current resolution.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  * `target_unit` is any time unit atom (`:year`, `:month`,
    `:day`, `:hour`, `:minute`, `:second`, …).

  ### Returns

  * The Tempo at the requested resolution, or

  * `{:error, reason}`.

  ### Examples

      iex> Tempo.at_resolution(~o"2020Y", :day)
      ~o"2020Y1M1D"

      iex> Tempo.at_resolution(~o"2020Y6M15DT10H", :day)
      ~o"2020Y6M15D"

      iex> Tempo.at_resolution(~o"2020Y6M15D", :day)
      ~o"2020Y6M15D"

  """
  @spec at_resolution(tempo :: t, target_unit :: time_unit()) ::
          t | {:error, error_reason()}
  def at_resolution(%Tempo{} = tempo, target_unit) do
    with {:ok, target_unit} <- validate_unit(target_unit) do
      target_unit = day_unit(target_unit, tempo)
      {current_unit, _span} = resolution(tempo)

      case Unit.compare(target_unit, current_unit) do
        :eq -> tempo
        :gt -> trunc(tempo, target_unit)
        :lt -> extend_resolution(tempo, target_unit)
      end
    end
  end

  def at_resolution(value, _target_unit), do: {:error, not_one_value("at_resolution/2", value)}

  # A value an operation wrote by its week or by its day of the year, as the
  # calendar date it names in a calendar of months: what reading it gives.
  defp as_calendar_date(%__MODULE__{} = value) do
    value
    |> Validation.calendar_date_from_week_date()
    |> Validation.calendar_date_from_ordinal_date()
  end

  # A week numbers each day within it, so the day of a value on the week
  # axis is its day of the week (`K`), in a calendar of weeks and for a
  # Gregorian week alike: a week date at day resolution is
  # `[year, week, day_of_week]`. A value that holds several days of the
  # year has its day there (`O`); one alone is read as its date.
  # Truncating, extending and rounding to `:day` all read the unit here. A
  # Gregorian week extended to it is then written as the date it names
  # (`extend_resolution/2`).
  defp day_unit(:day, %__MODULE__{time: time, calendar: calendar}) do
    cond do
      List.keymember?(time, :week, 0) or week_based_calendar?(calendar) -> :day_of_week
      List.keymember?(time, :day_of_year, 0) -> :day_of_year
      true -> :day
    end
  end

  defp day_unit(unit, _tempo), do: unit

  @doc """
  Convert a Tempo struct into a Date.

  Accepts the three single-day Tempo shapes:

  * Calendar date — `[year: Y, month: M, day: D]`.

  * Ordinal date — `[year: Y, day: DDD]`. When the Tempo carries
    only year and day (no month), the day is interpreted as
    day-of-year per ISO 8601-2 §4.3.4. `D` and `O` both parse to
    the same `:day` key, so `~o"2020-166"`, `~o"2020Y166O"`, and
    `~o"2020Y166D"` all convert correctly.

  * Week date — `[year: Y, week: W, day_of_week: K]`, an ISO 8601 week
    counted in the calendar's own year, or a week-based calendar's own
    week.

  ### Returns

  * `{:ok, %Date{}}` on success.

  * `{:error, reason}` when the Tempo covers a span rather than a
    single day, or the components don't form a valid date.

  ### Examples

      iex> {:ok, date} = Tempo.to_date(~o"2020-06-15")
      iex> date
      ~D[2020-06-15]

      iex> {:ok, date} = Tempo.to_date(~o"2020-166")
      iex> date
      ~D[2020-06-14]

      iex> {:ok, date} = Tempo.to_date(~o"2020-W24-3")
      iex> date
      ~D[2020-06-10]

  """
  @spec to_date(t()) :: {:ok, Date.t()} | {:error, error_reason()}
  def to_date(%Tempo{time: [year: year, month: month, day: day]} = tempo)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    Date.new(year, month, day, native_calendar(tempo))
  end

  # Ordinal date: year plus day-of-year. Both `~o"...O"` and the
  # bare `~o"YYYY-DDD"` form land here because Tempo's grammar
  # stores `D` and `O` under the same `:day` key; the absence of
  # `:month` is the disambiguator.
  def to_date(%Tempo{time: [year: year, day: day_of_year]} = tempo)
      when is_integer(year) and is_integer(day_of_year) do
    case Calendrical.date_from_day_of_year(year, day_of_year, calendar_of(tempo)) do
      %Date{} = date ->
        Date.convert(date, native_calendar(tempo))

      {:error, _reason} ->
        {:error,
         InvalidDateError.exception(
           unit: :day_of_year,
           value: day_of_year,
           year: year,
           reason: "out of range for year #{year}"
         )}
    end
  end

  # Week date: year plus ISO 8601 week plus day of the week, the week
  # counted by ISO 8601's rule over the calendar's own year.
  def to_date(%Tempo{time: [year: year, week: week, day_of_week: day]} = tempo)
      when is_integer(year) and is_integer(week) and is_integer(day) do
    with {:ok, date} <- Validation.date_from_iso_week(year, week, day, calendar_of(tempo)) do
      Date.convert(date, native_calendar(tempo))
    end
  end

  def to_date(value) do
    {:error, ConversionError.exception(value: value, target: Date)}
  end

  @doc """
  Convert a Tempo struct into a Time.

  ### Examples

      iex> Tempo.to_time(~o"T14:30:00")
      {:ok, ~T[14:30:00]}

      iex> Tempo.to_time(~o"T14:30:00.25")
      {:ok, ~T[14:30:00.25]}

  """
  # A zoned time-of-day projects to the wall-clock `Time`, dropping
  # the offset — the same lossy projection `Time` itself is (it has
  # no zone). Mirrors `to_date/1`, and `DateTime.to_time/1` in the
  # stdlib. Callers who need the offset should keep the Tempo.
  #
  # A second with no fraction has a precision of zero, as Elixir reads the
  # same text (`~T[14:30:00]`), and a fraction the digits it is written to,
  # so that `from_elixir/1` gives the value back.
  @spec to_time(t()) :: {:ok, Time.t()} | {:error, error_reason()}
  def to_time(%Tempo{time: [hour: hour, minute: minute, second: second]})
      when is_integer(hour) and is_integer(minute) and is_integer(second) do
    Time.new(hour, minute, second, {0, 0})
  end

  def to_time(%Tempo{
        time: [
          hour: hour,
          minute: minute,
          second: second,
          microsecond: {_value, _digits} = fraction
        ]
      })
      when is_integer(hour) and is_integer(minute) and is_integer(second) do
    Time.new(hour, minute, second, fraction)
  end

  def to_time(value) do
    {:error, ConversionError.exception(value: value, target: Time)}
  end

  @doc """
  Convert a Tempo struct into a `NaiveDateTime`.

  A `NaiveDateTime` is a zoneless wall-clock reading, so a zoned
  Tempo projects to its wall-clock components with the offset
  dropped — the same lossy projection `DateTime.to_naive/1`
  performs in the stdlib, and consistent with `to_date/1` /
  `to_time/1`. No time-zone math is involved: the wall-clock fields
  are read verbatim. To keep the zone, use `to_datetime/1`; to
  normalise to UTC wall time first, `shift_zone(tempo, "Etc/UTC")`.

  ### Arguments

  * `tempo` is a `t:t/0` resolved to at least second resolution
    (year through second, optionally microsecond). Coarser values
    cannot fill a `NaiveDateTime` and return an error.

  ### Returns

  * `{:ok, naive_datetime}`, or

  * `{:error, reason}` when the value is not resolved to a full
    datetime.

  ### Examples

      iex> Tempo.to_naive_datetime(~o"2022-11-19T01:02:03")
      {:ok, ~N[2022-11-19 01:02:03]}

      iex> Tempo.to_naive_datetime(~o"2022-11-19T01:02:03.5")
      {:ok, ~N[2022-11-19 01:02:03.5]}

      iex> {:error, _} = Tempo.to_naive_datetime(~o"2022-11")

  """
  @spec to_naive_datetime(t()) :: {:ok, NaiveDateTime.t()} | {:error, error_reason()}
  def to_naive_datetime(
        %Tempo{
          time: [
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second,
            microsecond: microsecond
          ]
        } = tempo
      )
      when is_integer(year) and is_integer(month) and is_integer(day) and is_integer(hour) and
             is_integer(minute) and is_integer(second) do
    NaiveDateTime.new(year, month, day, hour, minute, second, microsecond, native_calendar(tempo))
  end

  def to_naive_datetime(
        %Tempo{
          time: [year: year, month: month, day: day, hour: hour, minute: minute, second: second]
        } = tempo
      )
      when is_integer(year) and is_integer(month) and is_integer(day) and is_integer(hour) and
             is_integer(minute) and is_integer(second) do
    NaiveDateTime.new(year, month, day, hour, minute, second, {0, 0}, native_calendar(tempo))
  end

  def to_naive_datetime(
        %Tempo{
          time: [
            year: year,
            week: week,
            day_of_week: day,
            hour: hour,
            minute: minute,
            second: second,
            microsecond: microsecond
          ]
        } = tempo
      )
      when is_integer(year) and is_integer(week) and is_integer(day) do
    week_naive_datetime(tempo, {year, week, day}, {hour, minute, second, microsecond})
  end

  def to_naive_datetime(
        %Tempo{
          time: [
            year: year,
            week: week,
            day_of_week: day,
            hour: hour,
            minute: minute,
            second: second
          ]
        } = tempo
      )
      when is_integer(year) and is_integer(week) and is_integer(day) do
    week_naive_datetime(tempo, {year, week, day}, {hour, minute, second, {0, 0}})
  end

  def to_naive_datetime(value) do
    {:error, ConversionError.exception(value: value, target: NaiveDateTime)}
  end

  # A week date's day as its calendar numbers it — the calendar's own week
  # in a week-based calendar, ISO 8601's in any other — at its time of day.
  defp week_naive_datetime(tempo, {year, week, day}, {hour, minute, second, microsecond}) do
    with {:ok, date} <- Validation.date_from_iso_week(year, week, day, calendar_of(tempo)) do
      NaiveDateTime.new(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
        second,
        microsecond,
        native_calendar(tempo)
      )
    end
  end

  @doc """
  Convert a zoned Tempo into a `DateTime`.

  The lossless inverse of `from_elixir/2` on a `t:DateTime.t/0`:
  it preserves the named time zone, re-deriving the UTC offset from
  the time-zone database so the result is DST-correct. This is the
  conversion to reach for when the zone matters — unlike
  `to_naive_datetime/1`, which deliberately drops it.

  ### Arguments

  * `tempo` is a zoned `t:t/0` resolved to at least second resolution.
    A named IANA zone on `extended.zone_id` (every value built from a
    `DateTime` via `from_elixir/2` has one) is kept; a UTC offset
    (`Z` included) gives the instant in `Etc/UTC`. A floating value
    has no instant and returns an error — place it in a zone with
    `in_zone/2` first, or use `to_naive_datetime/1`.

  ### Returns

  * `{:ok, datetime}`, or

  * `{:error, reason}` when the value lacks a full datetime or a
    named zone, or when the wall-clock time falls in a
    spring-forward gap that does not exist in the zone.

  ### Examples

      iex> Tempo.to_datetime(~o"2022-11-19T01:02:03Z[Etc/UTC]")
      {:ok, ~U[2022-11-19 01:02:03Z]}

      iex> {:error, _} = Tempo.to_datetime(~o"2022-11-19T01:02:03")

  """
  @spec to_datetime(t()) :: {:ok, DateTime.t()} | {:error, error_reason()}
  def to_datetime(%Tempo{extended: %{zone_id: zone_id}} = tempo)
      when is_binary(zone_id) and zone_id != "" do
    with {:ok, naive} <- to_naive_datetime(tempo) do
      naive_to_zoned_datetime(naive, zone_id, tempo)
    end
  end

  # A value with a UTC offset (`+10:00`; `Z` is offset zero)
  # denotes an exact instant. Convert the wall clock to UTC and return
  # the instant as an `Etc/UTC` DateTime — the same normalisation
  # Elixir's `DateTime.from_iso8601/1` applies to offset strings.
  # iCalendar `DATE-TIME` values commonly carry offsets rather than
  # named zones, so this is the common third-party path.
  def to_datetime(%Tempo{shift: shift} = tempo) when is_list(shift) do
    with {:ok, naive} <- to_naive_datetime(tempo) do
      utc_naive = NaiveDateTime.add(naive, -Compare.offset_seconds(shift), :second)

      # `Etc/UTC` has no transitions, so `:ambiguous`/`:gap` cannot
      # occur — but they are in `from_naive/2`'s contract, so convert
      # any non-ok shape into the conversion error it would be.
      case DateTime.from_naive(utc_naive, "Etc/UTC") do
        {:ok, utc} ->
          {:ok, utc}

        _other ->
          {:error,
           ConversionError.exception(
             value: tempo,
             target: DateTime,
             reason: "could not project the value to UTC from its offset"
           )}
      end
    end
  end

  def to_datetime(%Tempo{} = value) do
    {:error,
     ConversionError.exception(
       value: value,
       target: DateTime,
       reason:
         "a floating value (no zone or offset) does not denote an instant — " <>
           "place it in a zone with `Tempo.in_zone/2`, or parse it with a zone, offset, or `Z`"
     )}
  end

  def to_datetime(value) do
    {:error, ConversionError.exception(value: value, target: DateTime)}
  end

  # Rebuild a `DateTime` from a wall-clock `NaiveDateTime` and a
  # named zone. `DateTime.from_naive/3` re-derives the offset from
  # the configured time zone database.
  # A DST fall-back (`:ambiguous`) is disambiguated by the offset
  # the Tempo already carries; a spring-forward `:gap` names a
  # wall-clock time that does not exist, so it is an error.
  defp naive_to_zoned_datetime(naive, zone_id, %Tempo{} = tempo) do
    case DateTime.from_naive(naive, zone_id, TimeZoneDatabase.database()) do
      {:ok, date_time} ->
        {:ok, date_time}

      {:ambiguous, first, second} ->
        {:ok, disambiguate_fold(first, second, tempo)}

      {:gap, _just_before, _just_after} ->
        {:error,
         ConversionError.exception(
           value: tempo,
           target: DateTime,
           reason:
             "wall-clock time #{NaiveDateTime.to_string(naive)} does not exist in " <>
               "#{zone_id} (spring-forward gap)"
         )}

      {:error, _reason} ->
        {:error, UnknownZoneError.exception(zone_id: zone_id)}
    end
  end

  # On a DST fall-back the same wall time occurs at two offsets;
  # pick the candidate whose total offset matches the offset the
  # Tempo recorded — an offset annotation (`extended.zone_offset`,
  # in minutes) or its UTC offset (`shift`). Falls back to the first
  # (pre-transition, higher-offset) candidate.
  defp disambiguate_fold(first, second, %Tempo{extended: %{zone_offset: minutes}})
       when is_integer(minutes),
       do: fold_at_offset(first, second, minutes * 60)

  defp disambiguate_fold(first, second, %Tempo{shift: shift}) when is_list(shift),
    do: fold_at_offset(first, second, Compare.offset_seconds(shift))

  defp disambiguate_fold(first, _second, _tempo), do: first

  defp fold_at_offset(first, second, offset_seconds) do
    Enum.find([first, second], first, fn dt ->
      dt.utc_offset + dt.std_offset == offset_seconds
    end)
  end

  @doc """
  Convert a day-resolution value from its current calendar into
  `calendar`, preserving the days it names.

  The value is read as a native `Date` in its own calendar, converted
  with `Date.convert/2`, and brought back as a `%Tempo{}` in `calendar`.
  A value that is not a plain day — a bare year or month, a time-of-day,
  or a zoned value — returns an error.

  An interval converts its endpoints and keeps everything else: its
  duration, recurrence, repeat rule, iteration unit and metadata are
  carried across untouched, and an unbounded end stays unbounded. An
  interval set converts each member. That saves the caller taking a
  span apart and putting it back together, which is the library's job
  and easy to get subtly wrong — a rebuilt interval loses whatever the
  original was carrying.

  ### Arguments

  * `value` is a day-resolution `t:t/0`, a `t:Tempo.Interval.t/0` whose
    endpoints are days, or a `t:Tempo.IntervalSet.t/0` of those.

  * `calendar` is a calendar module — a `Calendrical.*` calendar or any
    module implementing Elixir's `Calendar` behaviour.

  ### Returns

  * `{:ok, t:t/0}` — the value in `calendar`; or

  * `{:error, t:Tempo.ConversionError.t/0}`.

  ### Examples

      iex> {:ok, hebrew} = Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)
      iex> {Tempo.year(hebrew), Tempo.month(hebrew), Tempo.day(hebrew)}
      {5786, 9, 30}

  A whole span converts as one value. This is a fiscal quarter read back
  as the Gregorian dates it covers:

      iex> {:ok, calendar} = Calendrical.FiscalYear.calendar_for(:AU)
      iex> {:ok, quarter} = Tempo.from_elixir(calendar.quarter(2027, 1))
      iex> {:ok, gregorian} = Tempo.to_calendar(quarter, Calendrical.Gregorian)
      iex> Tempo.to_iso8601!(gregorian)
      "2026Y7M1D/10M1D"

  An interval set converts member by member:

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-06-15/2026-06-16"])
      iex> {:ok, hebrew} = Tempo.to_calendar(set, Calendrical.Hebrew)
      iex> hebrew |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
      ["5786Y9M30D/10M1D[u-ca=hebrew]"]

  """
  @spec to_calendar(t() | Interval.t() | IntervalSet.t(), module()) ::
          {:ok, t() | Interval.t() | IntervalSet.t()} | {:error, Tempo.ConversionError.t()}
  def to_calendar(value, calendar) do
    if calendar_module?(calendar),
      do: in_calendar(value, calendar),
      else: {:error, not_a_calendar_error(value, calendar)}
  end

  # A calendar is a module (`Calendrical.Hebrew`), never the name of one
  # (`:hebrew`), which would be called as a module and found to have no
  # functions.
  defp calendar_module?(calendar) do
    is_atom(calendar) and Code.ensure_loaded?(calendar) and
      function_exported?(calendar, :months_in_year, 1)
  end

  defp not_a_calendar_error(value, calendar) do
    ConversionError.exception(
      value: value,
      target: calendar,
      reason:
        "Cannot convert #{inspect(value)} to #{inspect(calendar)}, which is not a calendar " <>
          "module. A calendar is a module such as `Calendrical.Hebrew`."
    )
  end

  defp in_calendar(%Interval{} = interval, calendar) do
    with {:ok, from} <- convert_endpoint(interval.from, calendar),
         {:ok, to} <- convert_endpoint(interval.to, calendar) do
      {:ok, %{interval | from: from, to: to}}
    end
  end

  defp in_calendar(%IntervalSet{} = set, calendar) do
    set
    |> IntervalSet.members()
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case in_calendar(member, calendar) do
        {:ok, converted} -> {:cont, {:ok, [converted | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, members} -> IntervalSet.new(Enum.reverse(members))
      {:error, reason} -> {:error, reason}
    end
  end

  defp in_calendar(
         %Tempo{time: [year: year, month: month, day: day], shift: nil, calendar: source} = value,
         calendar
       )
       when is_integer(year) and is_integer(month) and is_integer(day) do
    convert_date(value, Date.new(year, month, day, source || Calendrical.Gregorian), calendar)
  end

  # A week date is the day of its week: the calendar's own week in a
  # week-based calendar, and ISO 8601's in any other.
  defp in_calendar(
         %Tempo{
           time: [year: year, week: week, day_of_week: day],
           shift: nil,
           calendar: source
         } = value,
         calendar
       )
       when is_atom(source) and not is_nil(source) and is_integer(year) and is_integer(week) and
              is_integer(day) do
    convert_date(value, Validation.date_from_iso_week(year, week, day, source), calendar)
  end

  defp in_calendar(%Tempo{} = value, calendar) do
    {:error,
     ConversionError.exception(
       value: value,
       target: calendar,
       reason: "only day-resolution, unzoned values convert between calendars"
     )}
  end

  defp in_calendar(value, calendar) do
    {:error,
     ConversionError.exception(
       value: value,
       target: calendar,
       reason:
         "Cannot convert #{inspect(value)} to #{inspect(calendar)}: a date, an interval of " <>
           "dates or an interval set converts."
     )}
  end

  defp convert_date(value, date_in_source, calendar) do
    with {:ok, in_source} <- date_in_source,
         {:ok, converted} <- Date.convert(in_source, calendar) do
      {:ok, carried_across(from_elixir(converted), value)}
    else
      {:error, reason} ->
        {:error, ConversionError.exception(value: value, target: calendar, reason: reason)}
    end
  end

  # A converted date keeps what its value says of it: its qualification, its
  # metadata, and its zone and tags (its calendar is now the one converted
  # to). Each unit of the converted date is worked out from all of the units
  # it was written with, so a qualified year, month or day qualifies every
  # unit of it, as a date written for a calendar of weeks converts.
  defp carried_across(%__MODULE__{time: time} = converted, %__MODULE__{} = value) do
    %{
      converted
      | qualifications: converted_qualifications(value.qualifications, time),
        metadata: value.metadata,
        extended: carried_extended(value.extended)
    }
  end

  # A zone and tags carry across; a value with neither has nothing to carry.
  defp carried_extended(%{} = extended) do
    if is_binary(extended[:zone_id]) or is_integer(extended[:zone_offset]) or
         map_size(extended[:tags] || %{}) > 0,
       do: extended
  end

  defp carried_extended(_none), do: nil

  defp converted_qualifications(%{} = qualifications, time) do
    case Map.values(qualifications) do
      [] ->
        nil

      [first | rest] ->
        qualification = Enum.reduce(rest, first, &Qualification.combine/2)
        Qualification.complete(time, qualification)
    end
  end

  defp converted_qualifications(_none, _time), do: nil

  @doc """
  Raising version of `to_calendar/2`.

  ### Arguments

  * `value` is a `t:t/0`, `t:Tempo.Interval.t/0`, or
    `t:Tempo.IntervalSet.t/0` — see `to_calendar/2`.

  * `calendar` is the target calendar module.

  ### Returns

  * The converted value in the target calendar.

  ### Examples

      iex> Tempo.to_calendar!(~o"2026-06-15", Calendrical.Hebrew)
      Tempo.from_iso8601!("5786Y9M30D", Calendrical.Hebrew)

  """
  @spec to_calendar!(t() | Tempo.Interval.t() | Tempo.IntervalSet.t(), module()) ::
          t() | Tempo.Interval.t() | Tempo.IntervalSet.t()
  def to_calendar!(value, calendar) do
    case to_calendar(value, calendar) do
      {:ok, converted} -> converted
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  # An endpoint that names no day — absent, or unbounded in either
  # direction — has nothing to convert and is carried across as it is.
  # Converting only what is there is what lets an open-ended span cross
  # calendars at all.
  defp convert_endpoint(nil, _calendar), do: {:ok, nil}
  defp convert_endpoint(:undefined, _calendar), do: {:ok, :undefined}
  defp convert_endpoint(%Tempo{} = endpoint, calendar), do: in_calendar(endpoint, calendar)

  @doc """
  Convert a Tempo value to its native Elixir equivalent — the
  outbound mirror of `from_elixir/2`.

  * A `t:Tempo.Duration.t/0` becomes an Elixir `Duration`: the units
    and the `{value, precision}` microsecond map one-to-one. Tempo-
    only components (`:day_of_year`, `:day_of_week`) have no Elixir
    `Duration` equivalent and return an error.

  * A `t:t/0` becomes its best-fit native calendar type by resolution —
    a `Date`, `Time`, or `NaiveDateTime`. For a specific target
    (including a zoned `DateTime`) use `to_date/1`, `to_time/1`,
    `to_datetime/1`, or `to_naive_datetime/1`. To change a value's
    *calendar* (e.g. Gregorian to Hebrew) use `to_calendar/2`.

  ### Arguments

  * `value` is a `t:t/0` or a `t:Tempo.Duration.t/0`.

  ### Returns

  * `{:ok, native}` where `native` is an Elixir `Duration`, `Date`,
    `Time`, `NaiveDateTime`, or — for a zoned value (a zone, an
    offset, or `Z`) — a `DateTime`.

  * `{:error, t:Tempo.ConversionError.t/0}` when the value cannot be
    represented by a single native type.

  ### Examples

      iex> Tempo.to_elixir(~o"PT8H")
      {:ok, Duration.new!(hour: 8)}

      iex> Tempo.to_elixir(~o"2026-06-15")
      {:ok, ~D[2026-06-15]}

  """
  @spec to_elixir(t() | Duration.t()) ::
          {:ok, Elixir.Duration.t() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t()}
          | {:error, Tempo.ConversionError.t()}
  def to_elixir(%Duration{time: time} = duration) do
    case Enum.find(time, fn {unit, _value} -> unit in [:day_of_year, :day_of_week] end) do
      nil ->
        {:ok, Elixir.Duration.new!(time)}

      {unit, _value} ->
        {:error,
         ConversionError.exception(
           value: duration,
           target: Elixir.Duration,
           reason: "duration component #{inspect(unit)} has no Elixir Duration equivalent"
         )}
    end
  end

  # A zoned value — a named zone, or a UTC offset (`Z` included) —
  # denotes an instant and converts to a `DateTime`; only floating
  # values fall through to the Date/Time/NaiveDateTime cascade.
  def to_elixir(%Tempo{extended: %{zone_id: zone_id}} = tempo)
      when is_binary(zone_id) and zone_id != "" do
    to_datetime(tempo)
  end

  def to_elixir(%Tempo{shift: shift} = tempo) when is_list(shift) do
    to_datetime(tempo)
  end

  def to_elixir(%Tempo{} = tempo) do
    with {:error, %Tempo.ConversionError{target: Date}} <- to_date(tempo),
         {:error, %Tempo.ConversionError{target: Time}} <- to_time(tempo) do
      to_naive_datetime(tempo)
    end
  end

  def to_elixir(value) do
    {:error,
     ConversionError.exception(
       value: value,
       reason:
         "Cannot convert #{inspect(value)} to a native Elixir value: only one date or " <>
           "time value, or a duration, has one."
     )}
  end

  # The present (non-zero) components of an Elixir `Duration`, as the
  # `{unit, value}` list Tempo's `Duration.new!/1` expects. Zero
  # components are dropped (Tempo carries only the units present); an
  # all-zero duration becomes `[second: 0]`.
  defp elixir_duration_components(%Elixir.Duration{} = d) do
    microsecond =
      case d.microsecond do
        {0, _precision} -> []
        {_value, _precision} = present -> [microsecond: present]
      end

    integers =
      [
        year: d.year,
        month: d.month,
        week: d.week,
        day: d.day,
        hour: d.hour,
        minute: d.minute,
        second: d.second
      ]
      |> Enum.reject(fn {_unit, value} -> value == 0 end)

    # `Tempo.Duration.new!/1` re-attaches `second: 0` when only a
    # microsecond is present, so we don't have to here.
    case integers ++ microsecond do
      [] -> [second: 0]
      components -> components
    end
  end

  ## ---------------------------------------------------------
  ## Current time — clock-backed "now" entry points
  ## ---------------------------------------------------------

  @doc """
  Return the current UTC time as a second-resolution `t:t/0`
  in `Etc/UTC`.

  Reads from the clock configured under `:ex_tempo, :clock`,
  defaulting to `Tempo.Clock.System`. Tests that need determinism
  should configure `Tempo.Clock.Test` — see its module doc.

  ### Returns

  * A `t:t/0` at second resolution with `shift: [hour: 0]` and
    `extended.zone_id: "Etc/UTC"`.

  ### Examples

      iex> tempo = Tempo.utc_now()
      iex> tempo.extended.zone_id
      "Etc/UTC"

      iex> Tempo.utc_now() |> Tempo.resolution()
      {:second, 1}

  """
  @spec utc_now() :: t()
  def utc_now do
    # Truncate the clock's microsecond so the result honours the
    # documented second resolution. For a sub-second reading, use
    # `Tempo.from_elixir(DateTime.utc_now())`.
    Clock.utc_now() |> DateTime.truncate(:second) |> from_datetime()
  end

  @doc """
  Return the current time in the given IANA time zone as a
  second-resolution `t:t/0`.

  Reads from the configured clock (as `utc_now/0` does) and shifts
  the result into `zone`. The returned Tempo's wall-clock time is
  the zone-local reading of the current UTC instant.

  ### Arguments

  * `zone` is an IANA time zone name (e.g. `"Europe/Paris"`,
    `"America/New_York"`). Defaults to `"Etc/UTC"`, in which case
    `now/1` is equivalent to `utc_now/0`.

  ### Returns

  * A `t:t/0` at second resolution with `extended.zone_id: zone`.

  * `{:error, %Tempo.UnknownZoneError{}}` when `zone` is not a zone
    the time zone database knows.

  ### Examples

      iex> tempo = Tempo.now("Europe/London")
      iex> tempo.extended.zone_id
      "Europe/London"

      iex> Tempo.now("Etc/UTC").extended.zone_id
      "Etc/UTC"

      iex> Tempo.now("Continent/Imaginary")
      {:error, %Tempo.UnknownZoneError{zone_id: "Continent/Imaginary"}}

  """
  @spec now(String.t()) :: t() | {:error, UnknownZoneError.t()}
  def now(zone \\ "Etc/UTC")

  def now(zone) when is_binary(zone) do
    # Second resolution per the contract — see `utc_now/0`.
    Clock.utc_now() |> DateTime.truncate(:second) |> zoned_now(zone)
  end

  def now(zone), do: {:error, UnknownZoneError.exception(zone_id: inspect(zone))}

  # The current UTC instant read in `zone`.
  defp zoned_now(utc, "Etc/UTC"), do: from_datetime(utc)

  defp zoned_now(utc, zone) do
    case DateTime.shift_zone(utc, zone, TimeZoneDatabase.database()) do
      {:ok, zoned} -> from_datetime(zoned)
      {:error, _reason} -> {:error, UnknownZoneError.exception(zone_id: zone)}
    end
  end

  @doc """
  Return today's date in UTC, as a floating day-resolution `t:t/0`.

  ### Returns

  * A floating `t:t/0` at day resolution: the calendar date in UTC,
    with no zone. `utc_now/0` returns the zoned instant.

  ### Examples

      iex> Tempo.utc_today() |> Tempo.resolution()
      {:day, 1}

      iex> Tempo.utc_today() |> Tempo.floating?()
      true

  """
  @spec utc_today() :: t() | {:error, error_reason()}
  def utc_today do
    today("Etc/UTC")
  end

  @doc """
  Return today's date in the given IANA time zone, as a floating
  day-resolution `t:t/0`.

  "Today" is zone-relative: at 11pm in New York on the 14th it is
  already the 15th in Paris. This function answers the zone-local
  question with the calendar date there, and no zone: a date has
  none, so it compares with a holiday, or any other date written
  without one. `now/1` returns the zoned instant.

  ### Arguments

  * `zone` is an IANA time zone name. Defaults to `"Etc/UTC"`.

  ### Returns

  * A floating `t:t/0` at day resolution: the date in `zone` at the
    current UTC instant.

  * `{:error, %Tempo.UnknownZoneError{}}` when `zone` is not a zone
    the time zone database knows.

  ### Examples

      iex> Tempo.today("Etc/UTC") |> Tempo.resolution()
      {:day, 1}

      iex> Tempo.today("Australia/Sydney") |> Tempo.floating?()
      true

  """
  @spec today(String.t()) :: t() | {:error, error_reason()}
  def today(zone \\ "Etc/UTC") do
    case now(zone) do
      %__MODULE__{} = now -> now |> trunc(:day) |> drop_zone()
      {:error, _reason} = error -> error
    end
  end

  # A zoned value's wall-clock reading with its zone and offset removed — its
  # floating form. Tags it carries stay.
  defp drop_zone(%__MODULE__{extended: %{tags: tags}} = tempo)
       when map_size(tags) == 0,
       do: %{tempo | shift: nil, extended: nil}

  defp drop_zone(%__MODULE__{extended: %{} = extended} = tempo) do
    %{
      tempo
      | shift: nil,
        extended: Map.merge(extended, %{zone_id: nil, zone_offset: nil, zone_critical: false})
    }
  end

  defp drop_zone(%__MODULE__{} = tempo), do: %{tempo | shift: nil}
  defp drop_zone({:error, _reason} = error), do: error

  ## ---------------------------------------------------------
  ## Zone placement — place a floating Tempo in a zone
  ## ---------------------------------------------------------

  @doc """
  Place a floating `Tempo` in an IANA time zone, keeping its
  wall-clock reading.

  A floating value (`~o"2024-01-01"`) names a civil reading but not
  *which* observer's — it has no position on the universal time line.
  `in_zone/2` interprets that reading as the local time in `zone`,
  producing a zoned value that projects to UTC. The wall-clock
  fields are unchanged; only the zone is attached. This is the runtime
  equivalent of writing the `[zone]` suffix in the source
  (`~o"2024-01-01[Australia/Sydney]"`).

  Use `in_zone/2` to *place* a floating value in a zone; use
  `shift_zone/2` to *move* a zoned value to a different zone (which re-computes the wall clock to preserve the instant).

  ### Arguments

  * `tempo` is a floating `t:t/0` (no zone and no offset — see
    `floating?/1`).

  * `zone` is an IANA zone name (`"Europe/Paris"`, `"Australia/Sydney"`,
    `"Etc/UTC"`, …).

  ### Returns

  * `{:ok, tempo}` in `zone`, with the same wall-clock fields.

  * `{:error, reason}` when `tempo` is already zoned (use
    `shift_zone/2` instead) or `zone` is unknown to the configured
    time zone database.

  ### Examples

      iex> {:ok, sydney} = Tempo.in_zone(Tempo.from_iso8601!("2024-01-01"), "Australia/Sydney")
      iex> sydney.extended.zone_id
      "Australia/Sydney"

      iex> {:error, _} = Tempo.in_zone(Tempo.from_iso8601!("2024-01-01[Australia/Sydney]"), "Europe/Paris")

  """
  @spec in_zone(t(), String.t()) :: {:ok, t()} | {:error, error_reason()}
  def in_zone(%Tempo{} = tempo, zone) when is_binary(zone) do
    cond do
      not floating?(tempo) ->
        {:error, ZonedTempoError.exception(operation: :in_zone, value: tempo)}

      not TimeZoneDatabase.zone_exists?(zone) ->
        {:error, UnknownZoneError.exception(zone_id: zone)}

      true ->
        {:ok, %{tempo | extended: put_zone_id(tempo.extended, zone)}}
    end
  end

  def in_zone(%Tempo{}, zone), do: {:error, UnknownZoneError.exception(zone_id: zone)}
  def in_zone(value, _zone), do: {:error, not_one_value("in_zone/2", value)}

  defp put_zone_id(nil, zone),
    do: %{zone_id: zone, zone_offset: nil, zone_critical: false, tags: %{}}

  defp put_zone_id(%{} = extended, zone), do: %{extended | zone_id: zone}

  ## ---------------------------------------------------------
  ## Zone shifting — project a zoned Tempo into another zone
  ## ---------------------------------------------------------

  @doc """
  Project a zoned Tempo — one with a zone or an offset — into
  another IANA time zone, preserving the span it names.

  The result names the same span of the time line, read on the wall
  clock an observer in `target_zone` would see. A value written to the
  second, or to a fraction of one, is the same second there. A coarser
  value keeps its resolution where its span is one unit on the other
  clock, as an hour is between two zones a whole number of hours apart,
  and is otherwise the interval it is there: a day in Paris is no one
  day in New York. Zone rules are read from the configured time zone
  database at call time.

  The value stays in its own calendar and keeps its calendar annotation, tags, metadata and qualification; only its zone and offset change.

  ### Arguments

  * `tempo` is a `t:t/0` that carries zone information — either an
    IANA zone on `extended.zone_id`, a numeric `zone_offset`, or a
    `shift` keyword list. A floating Tempo (no zone info) cannot be
    projected because its UTC instant is undefined.

  * `target_zone` is an IANA zone name (`"Europe/Paris"`,
    `"America/New_York"`, `"Etc/UTC"`, …).

  ### Returns

  * `{:ok, tempo}` in `target_zone`, at the resolution of `tempo`, when
    its span is one value there.

  * `{:ok, interval}` in `target_zone` when it is not.

  * `{:error, reason}` when `tempo` is not zoned, names several spans,
    or `target_zone` is unknown to the configured time zone database.

  ### Examples

      iex> paris = Tempo.from_iso8601!("2026-06-15T14:00:00[Europe/Paris]")
      iex> {:ok, new_york} = Tempo.shift_zone(paris, "America/New_York")
      iex> new_york.extended.zone_id
      "America/New_York"
      iex> Keyword.take(new_york.time, [:hour, :minute])
      [hour: 8, minute: 0]

  An hour in Paris is an hour in New York, half past the hour to half
  past in Kolkata, and a day in Paris is from six in the evening to six
  in New York:

      iex> hour = Tempo.from_iso8601!("2026-06-15T14[Europe/Paris]")
      iex> {:ok, new_york} = Tempo.shift_zone(hour, "America/New_York")
      iex> new_york.time
      [year: 2026, month: 6, day: 15, hour: 8]
      iex> {:ok, kolkata} = Tempo.shift_zone(hour, "Asia/Kolkata")
      iex> {kolkata.from.time, kolkata.to.time}
      {[year: 2026, month: 6, day: 15, hour: 17, minute: 30],
       [year: 2026, month: 6, day: 15, hour: 18, minute: 30]}

      iex> day = Tempo.from_iso8601!("2026-06-15[Europe/Paris]")
      iex> {:ok, new_york} = Tempo.shift_zone(day, "America/New_York")
      iex> {new_york.from.time, new_york.to.time}
      {[year: 2026, month: 6, day: 14, hour: 18, minute: 0],
       [year: 2026, month: 6, day: 15, hour: 18, minute: 0]}

  Rosh Hashanah 5787 at 10:00 in Jerusalem is 07:00 that day in UTC, in the Hebrew calendar:

      iex> jerusalem = Tempo.from_iso8601!("5787-01-01T10:00:00[Asia/Jerusalem][u-ca=hebrew]")
      iex> {:ok, utc} = Tempo.shift_zone(jerusalem, "Etc/UTC")
      iex> {Tempo.year(utc), Tempo.month(utc), Tempo.day(utc), Tempo.hour(utc)}
      {5787, 1, 1, 7}

  """
  @spec shift_zone(t(), String.t()) ::
          {:ok, t() | Tempo.Interval.t()} | {:error, error_reason()}
  def shift_zone(%Tempo{} = tempo, target_zone) when is_binary(target_zone) do
    cond do
      not anchored?(tempo) ->
        {:error, UnanchoredError.exception(operation: :shift_zone, value: tempo)}

      floating?(tempo) ->
        {:error, FloatingTempoError.exception(operation: :shift_zone, value: tempo)}

      not Compare.point?(tempo.time) ->
        {:error, several_moments_error(tempo)}

      true ->
        do_shift_zone(tempo, target_zone)
    end
  end

  def shift_zone(%Tempo{}, zone), do: {:error, UnknownZoneError.exception(zone_id: zone)}
  def shift_zone(value, _zone), do: {:error, not_one_value("shift_zone/2", value)}

  # A value that names several moments (a set, a mask, a group) has a wall
  # time in the other zone for each, and no one value there to return.
  defp several_moments_error(tempo) do
    ConversionError.exception(
      value: tempo,
      reason:
        "Cannot move #{inspect(tempo)} to another zone: it names more than one moment (a " <>
          "set, a mask or a group), and each has its own wall time there. Move each value " <>
          "it names."
    )
  end

  @doc """
  Return whether a `Tempo` value is *floating* — a wall-clock reading
  with no zone or offset, so it cannot be placed on the universal
  (UTC) time line.

  A floating value carries no `[IANA/Zone]` tag, no `Z`, and no numeric
  offset. `~o"2024-01-01"` is floating: it names a civil day but not
  *which* observer's civil day, so it has no single universal instant.
  Placing it in a zone with `in_zone/2` (or writing an offset such as
  `Z`) makes it zoned. The complement is `zoned?/1`.

  Floating and zoned values cannot be compared — a floating value
  has no universal position — so when only one operand is floating,
  `relation/2` and the certainty functions return a
  `Tempo.FloatingTempoError`, and the predicates, with only true and
  false to give, raise it.

  ### Arguments

  * `tempo` is a `%Tempo{}` value.

  ### Returns

  * `true` when the value has no zone and no offset.

  * `false` when the value carries a zone (`[IANA/Zone]`) or an offset
    (`Z` or `+HH:MM`).

  ### Examples

      iex> Tempo.floating?(Tempo.from_iso8601!("2024-01-01"))
      true

      iex> Tempo.floating?(Tempo.from_iso8601!("2024-01-01Z"))
      false

      iex> Tempo.floating?(Tempo.from_iso8601!("2024-01-01[Australia/Sydney]"))
      false

  """
  @spec floating?(t()) :: boolean()
  def floating?(%Tempo{shift: nil, extended: nil}), do: true
  def floating?(%Tempo{shift: nil, extended: %{zone_id: nil, zone_offset: nil}}), do: true
  def floating?(%Tempo{}), do: false
  def floating?(value), do: raise(not_one_value("floating?/1", value))

  @doc """
  Return whether a `Tempo` value is *zoned* — it carries a zone or an
  offset and so has a position on the universal (UTC) time line.

  Zoned is the exact complement of `floating?/1`: a value is zoned
  when it has an `[IANA/Zone]` tag, a `Z`, or a numeric offset.

  ### Arguments

  * `tempo` is a `%Tempo{}` value.

  ### Returns

  * `true` when the value carries a zone or offset.

  * `false` when the value is floating.

  ### Examples

      iex> Tempo.zoned?(Tempo.from_iso8601!("2024-01-01[Australia/Sydney]"))
      true

      iex> Tempo.zoned?(Tempo.from_iso8601!("2024-01-01"))
      false

  """
  @spec zoned?(t()) :: boolean()
  def zoned?(%Tempo{} = tempo), do: not floating?(tempo)
  def zoned?(value), do: raise(not_one_value("zoned?/1", value))

  # The same instant on `target_zone`'s wall clock, to the second and in the
  # value's own calendar. The value keeps everything else it carries — its
  # calendar annotation, tags, metadata and qualification — and the target
  # zone and its offset take the place of its own.
  # A value's span is read on the other zone's clock: where it starts and
  # where it ends there. One written to the second or finer is one such
  # value in any zone. A coarser one is a value there when its start is the
  # start of a unit of its own resolution and its end that unit's end, and
  # is otherwise the interval from the one to the other.
  defp do_shift_zone(%Tempo{time: time} = tempo, target_zone) do
    if written_to_the_second?(time),
      do: moment_in_zone(tempo, target_zone),
      else: span_in_zone(tempo, target_zone)
  end

  defp written_to_the_second?(time),
    do: List.keymember?(time, :second, 0) or List.keymember?(time, :microsecond, 0)

  defp span_in_zone(tempo, target_zone) do
    {unit, _span} = resolution(tempo)

    with {:ok, {lower, upper}, _walked_by} <- Interval.next_unit_boundary(tempo),
         {:ok, start} <- moment_in_zone(lower, target_zone),
         {:ok, finish} <- moment_in_zone(upper, target_zone) do
      case one_unit_there(start, finish, unit) do
        %Tempo{} = value -> {:ok, value}
        nil -> {:ok, interval_there(start, finish, tempo)}
      end
    end
  end

  # The value of `unit`'s resolution that starts at `start` and ends at
  # `finish` on the other zone's clock, or `nil` when there is none.
  defp one_unit_there(start, finish, unit) do
    with %Tempo{} = value <- trunc(start, unit),
         value = in_the_zone_alone(value, unit),
         {:ok, {lower, upper}, _walked_by} <- Interval.next_unit_boundary(value),
         true <- same_moment?(lower, start) and same_moment?(upper, finish) do
      value
    else
      _not_one_unit -> nil
    end
  end

  # A date in a zone is written with the zone and no offset: the offset is
  # the zone's wherever in the date it is asked for, and the day the clocks
  # change has two. An hour or a minute keeps the offset it is at, which says
  # which of the two it is when the clocks go back.
  defp in_the_zone_alone(value, unit) when unit in [:hour, :minute], do: value
  defp in_the_zone_alone(value, _unit), do: %{value | shift: nil}

  defp same_moment?(a, b), do: Compare.to_utc_seconds(a) == Compare.to_utc_seconds(b)

  # The interval carries the value's metadata, as the value there would.
  defp interval_there(start, finish, %Tempo{metadata: metadata}) do
    %Interval{
      from: to_the_minute(start, finish),
      to: to_the_minute(finish, start),
      metadata: metadata
    }
  end

  # An interval's ends are written to the minute, the finest unit two zones'
  # clocks differ by, unless either falls between minutes.
  defp to_the_minute(%Tempo{time: time} = endpoint, %Tempo{time: other}) do
    if Keyword.get(time, :second) == 0 and Keyword.get(other, :second) == 0,
      do: %{endpoint | time: Keyword.delete(time, :second)},
      else: endpoint
  end

  # The moment a value's span starts at, to the second or the fraction of
  # one it is written to, on the wall clock of another zone.
  defp moment_in_zone(%Tempo{time: time} = tempo, target_zone) do
    calendar = Compare.effective_calendar(tempo.calendar)
    {whole, fraction} = Enum.split_with(time, &(not match?({:microsecond, _fraction}, &1)))
    utc_seconds = Compare.to_utc_seconds(%{tempo | time: whole})

    with {:ok, offset} <- zone_offset_at(target_zone, utc_seconds),
         {:ok, wall} <- wall_components(utc_seconds + offset, calendar, tempo) do
      {:ok,
       %{
         tempo
         | time: wall ++ fraction,
           shift: Zone.offset_to_shift(offset),
           calendar: calendar,
           extended: in_zone_extended(tempo.extended, target_zone)
       }}
    end
  end

  defp zone_offset_at("Etc/UTC", _utc_seconds), do: {:ok, 0}

  defp zone_offset_at(zone, utc_seconds) do
    case TimeZoneDatabase.period_at_utc(zone, utc_seconds) do
      {:ok, period} -> {:ok, TimeZoneDatabase.total_offset(period)}
      {:error, _reason} -> {:error, UnknownZoneError.exception(zone_id: zone)}
    end
  end

  # A wall-clock reading in Gregorian seconds as a value's components in
  # `calendar`: the day as the calendar numbers it, and the time of day.
  defp wall_components(seconds, calendar, tempo) do
    time_of_day = Integer.mod(seconds, 86_400)

    with {:ok, {year, month, day}} <-
           day_in_calendar(Integer.floor_div(seconds, 86_400), calendar, tempo) do
      {:ok,
       date_units(year, month, day, calendar) ++
         [
           hour: div(time_of_day, 3_600),
           minute: time_of_day |> rem(3_600) |> div(60),
           second: rem(time_of_day, 60)
         ]}
    end
  end

  # The day `days` after 0000-01-01 as `calendar` numbers it. Both counts
  # from day 0 take negative (pre-common-era) days on every OTP, which OTP
  # ≤ 28's `:calendar.gregorian_seconds_to_datetime/1` does not.
  defp day_in_calendar(days, Gregorian, _tempo),
    do: {:ok, Gregorian.date_from_iso_days(days)}

  defp day_in_calendar(days, calendar, tempo) do
    case days |> Date.from_gregorian_days() |> Date.convert(calendar) do
      {:ok, %Date{year: year, month: month, day: day}} ->
        {:ok, {year, month, day}}

      {:error, reason} ->
        {:error, ConversionError.exception(value: tempo, target: calendar, reason: reason)}
    end
  end

  # The value's annotations with `zone` in place of its own zone or offset
  # annotation: RFC 9557 gives a value one, and its offset is its shift. A
  # critical flag belonged to the zone it replaces.
  defp in_zone_extended(extended, zone) do
    Map.merge(
      extended || %{tags: %{}},
      %{zone_id: zone, zone_offset: nil, zone_critical: false}
    )
  end

  ## ---------------------------------------------------------
  ## Metadata — the caller's own data on any value
  ## ---------------------------------------------------------

  @doc """
  The qualifier a whole value carries: uncertain, approximate or both.

  ISO 8601-2 §8 qualifies a value component by component, and a
  qualifier written after a whole value (`2004-06-11~`) qualifies each
  of its components. So a value is qualified as a whole when every
  component it holds carries the same qualifier, however that was
  written: `2026?` and `?2026` are the same uncertain year.

  ### Arguments

  * `value` is a `t:t/0`.

  ### Returns

  * `:uncertain`, `:approximate` or `:uncertain_and_approximate` when
    every component of the value carries that qualifier.

  * `nil` when no component is qualified, or when they are not all
    qualified alike: `qualification/2` reads one component.

  ### Examples

      iex> Tempo.qualification(~o"2004-06-11~")
      :approximate

      iex> Tempo.qualification(~o"2004-06~-11")
      nil

      iex> Tempo.qualification(~o"2004-06-11")
      nil

  """
  @spec qualification(t()) :: qualification()
  def qualification(%__MODULE__{} = value), do: Qualification.whole(value)

  @doc """
  The qualifier one component of a value carries.

  A qualifier to the right of a component qualifies it and each
  component before it (`2004-06~-11` is an approximate June of an
  approximate 2004, on the 11th), and one to its left that component
  alone (`2004-?06-11`).

  ### Arguments

  * `value` is a `t:t/0`.

  * `unit` is the component's unit, such as `:year`, `:month` or `:day`.

  ### Returns

  * `:uncertain`, `:approximate` or `:uncertain_and_approximate`, or
    `nil` when the component is not qualified or the value does not
    hold it.

  ### Examples

      iex> Tempo.qualification(~o"2004-06~-11", :month)
      :approximate

      iex> Tempo.qualification(~o"2004-06~-11", :day)
      nil

      iex> Tempo.qualification(~o"2004-?06-11", :year)
      nil

  """
  @spec qualification(t(), atom()) :: qualification()
  def qualification(%__MODULE__{qualifications: nil}, unit) when is_atom(unit), do: nil

  def qualification(%__MODULE__{qualifications: qualifications}, unit) when is_atom(unit),
    do: Map.get(qualifications, unit)

  @doc """
  Returns a value's metadata: the caller's own data carried with it (a holiday
  name, an event's summary).

  Every Tempo value carries a metadata map. It is not part of the value's
  ISO 8601 form, and conversion carries it along: a recurrence's metadata
  reaches every occurrence, and a recurrence set's tags each occurrence its
  members produce.

  ### Arguments

  * `value` is a `t:t/0`, `t:Tempo.Interval.t/0`, `t:Tempo.IntervalSet.t/0`,
    `t:Tempo.RecurrenceSet.t/0` or `t:Tempo.RecurrenceSet.Conditional.t/0`.

  ### Returns

  * The metadata map, `%{}` when none was given, or

  * `{:error, reason}` when `value` is not a Tempo value.

  ### Examples

      iex> Tempo.new!(year: 2026, month: 12, day: 25, metadata: %{name: "Christmas Day"})
      ...> |> Tempo.metadata()
      %{name: "Christmas Day"}

      iex> Tempo.metadata(~o"2026-12-25")
      %{}

  """
  @spec metadata(
          t()
          | Tempo.Interval.t()
          | IntervalSet.t()
          | Tempo.RecurrenceSet.t()
          | Conditional.t()
        ) ::
          map() | {:error, Exception.t()}
  def metadata(%module{metadata: metadata})
      when module in [__MODULE__, Tempo.Interval, IntervalSet, Tempo.RecurrenceSet, Conditional],
      do: metadata

  def metadata(value) do
    {:error,
     ArgumentError.exception("Tempo.metadata/1 takes a Tempo value, got #{inspect(value)}")}
  end

  @doc """
  Returns a value with its metadata replaced.

  ### Arguments

  * `value` is a `t:t/0`, `t:Tempo.Interval.t/0`, `t:Tempo.IntervalSet.t/0`,
    `t:Tempo.RecurrenceSet.t/0` or `t:Tempo.RecurrenceSet.Conditional.t/0`.

  * `metadata` is a map.

  ### Returns

  * The value carrying `metadata`, or

  * `{:error, reason}` when `metadata` is not a map or `value` is not a Tempo
    value.

  ### Examples

      iex> ~o"R/../P1Y/FL12M25DN"
      ...> |> Tempo.put_metadata(%{name: "Christmas Day"})
      ...> |> Tempo.metadata()
      %{name: "Christmas Day"}

  """
  @spec put_metadata(value, map()) :: value | {:error, Exception.t()}
        when value:
               t()
               | Tempo.Interval.t()
               | IntervalSet.t()
               | Tempo.RecurrenceSet.t()
               | Conditional.t()
  def put_metadata(%module{} = value, metadata)
      when module in [__MODULE__, Tempo.Interval, IntervalSet, Tempo.RecurrenceSet, Conditional] and
             is_map(metadata),
      do: %{value | metadata: metadata}

  def put_metadata(value, metadata) do
    {:error,
     ArgumentError.exception(
       "Tempo.put_metadata/2 takes a Tempo value and a map, got " <>
         "#{inspect(value)} and #{inspect(metadata)}"
     )}
  end

  ## ---------------------------------------------------------
  ## Calendar accessors — day_of_week, day_of_year, …
  ## ---------------------------------------------------------

  @doc """
  Return the day of the week as an integer (`1..7`) using the
  Tempo value's calendar.

  For the Gregorian calendar with `:default` ordering, `1` is
  Monday and `7` is Sunday — matching `Date.day_of_week/1`.

  ### Arguments

  * `tempo` is a `t:t/0` anchored with at least year/month/day
    components.

  * `starting_on` is a day-of-week atom controlling which day is
    numbered `1`. Accepts `:default` (calendar's default),
    `:monday`, `:tuesday`, `:wednesday`, `:thursday`, `:friday`,
    `:saturday`, or `:sunday`. Defaults to `:default`.

  ### Returns

  * Integer `1..7`.

  ### Raises

  * `ArgumentError` when `tempo` has no date components.

  ### Examples

      iex> Tempo.day_of_week(~o"2026-06-15")
      1

      iex> Tempo.day_of_week(~o"2026-06-15", :sunday)
      2

  """
  @spec day_of_week(t(), atom()) :: 1..7
  def day_of_week(tempo, starting_on \\ :default)

  def day_of_week(%Tempo{} = tempo, starting_on) do
    {year, month, day} = require_ymd!(tempo, :day_of_week)
    {dow, _first, _last} = calendar_of(tempo).day_of_week(year, month, day, starting_on)
    dow
  end

  def day_of_week(value, _starting_on), do: raise(not_one_value("day_of_week/2", value))

  @doc """
  Return the 1-based ordinal day of the year (`1..365` or `1..366`
  in a leap year) using the Tempo value's calendar.

  ### Arguments

  * `tempo` is a `t:t/0` anchored with at least year/month/day
    components.

  ### Returns

  * A positive integer.

  ### Raises

  * `ArgumentError` when `tempo` has no date components.

  ### Examples

      iex> Tempo.day_of_year(~o"2026-01-01")
      1

      iex> Tempo.day_of_year(~o"2024-12-31")
      366

  """
  @spec day_of_year(t()) :: pos_integer()
  def day_of_year(%Tempo{} = tempo) do
    {year, month, day} = require_ymd!(tempo, :day_of_year)
    calendar_of(tempo).day_of_year(year, month, day)
  end

  def day_of_year(value), do: raise(not_one_value("day_of_year/1", value))

  @doc """
  Return the 1-based quarter of the year (`1..4`) that the value's
  calendar puts its month in — a Hebrew leap year's Adar I is in the
  second quarter, a Coptic epagomenal month in the fourth.

  ### Arguments

  * `tempo` is a `t:t/0` anchored with at least year/month
    components.

  ### Returns

  * An integer `1..4`.

  ### Raises

  * `ArgumentError` when `tempo` has no year/month components.

  ### Examples

      iex> Tempo.quarter_of_year(~o"2026-01-15")
      1

      iex> Tempo.quarter_of_year(~o"2026-11-30")
      4

      iex> Tempo.quarter_of_year(Tempo.from_iso8601!("5787-06-15", Calendrical.Hebrew))
      2

  """
  @spec quarter_of_year(t()) :: 1..4
  def quarter_of_year(%Tempo{} = tempo) do
    {year, month, day} = require_ymd!(tempo, :quarter_of_year, default_day: 1)
    calendar_of(tempo).quarter_of_year(year, month, day)
  end

  def quarter_of_year(value), do: raise(not_one_value("quarter_of_year/1", value))

  @doc """
  Return `true` when the Tempo's year is a leap year under its
  calendar.

  ### Arguments

  * `tempo` is a `t:t/0` with at least a year component.

  ### Returns

  * `true` or `false`.

  ### Raises

  * `ArgumentError` when `tempo` has no year component.

  ### Examples

      iex> Tempo.leap_year?(~o"2024")
      true

      iex> Tempo.leap_year?(~o"2025")
      false

  """
  @spec leap_year?(t()) :: boolean()
  def leap_year?(%Tempo{} = tempo) do
    calendar_of(tempo).leap_year?(whole!(tempo, :year, "leap_year?"))
  end

  def leap_year?(value), do: raise(not_one_value("leap_year?/1", value))

  @doc """
  Return the number of days in the Tempo's month under its
  calendar.

  ### Arguments

  * `tempo` is a `t:t/0` with year and month components.

  ### Returns

  * A positive integer.

  ### Raises

  * `ArgumentError` when `tempo` has no year or no month
    component.

  ### Examples

      iex> Tempo.days_in_month(~o"2024-02-15")
      29

      iex> Tempo.days_in_month(~o"2025-02")
      28

      iex> Tempo.days_in_month(~o"2026-04")
      30

  """
  @spec days_in_month(t()) :: pos_integer()
  def days_in_month(%Tempo{time: time} = tempo) do
    year = whole!(tempo, :year, "days_in_month")
    month = whole!(tempo, :month, "days_in_month")
    calendar = calendar_of(tempo)

    if List.keymember?(time, :day, 0),
      do: calendar.days_in_month(year, month),
      else: UnitValues.days_in_counted_month(year, month, calendar)
  end

  def days_in_month(value), do: raise(not_one_value("days_in_month/1", value))

  # Return the calendar module for a Tempo, defaulting to
  # Calendrical.Gregorian when nil. Centralises the fallback so
  # every accessor uses the same rule.
  defp calendar_of(%Tempo{calendar: nil}), do: Calendrical.Gregorian
  defp calendar_of(%Tempo{calendar: calendar}), do: calendar

  # The native Elixir calendar for a value at the outbound boundary
  # (`to_date/1`, `to_naive_datetime/1`, `to_elixir/1`): Tempo's internal
  # `Calendrical.Gregorian` becomes Elixir's `Calendar.ISO`, while any other
  # calendar passes through — so a non-Gregorian value converts to a native
  # type in its own calendar rather than being mislabelled ISO.
  defp native_calendar(%Tempo{} = tempo) do
    case calendar_of(tempo) do
      Calendrical.Gregorian -> Calendar.ISO
      calendar -> calendar
    end
  end

  # Extract {year, month, day} from a Tempo or raise a uniform
  # error. Missing month or day default to 1 (start-of-unit) so
  # quarter-of-year on a year-resolution value still works. A value on the
  # week axis is read by its week and its day, and one that holds a day of
  # the year by that day: several of them are no one date to read.
  defp require_ymd!(%Tempo{time: time} = tempo, function, opts \\ []) do
    year = whole!(tempo, :year, function)

    cond do
      List.keymember?(time, :week, 0) ->
        week = whole!(tempo, :week, function)
        week_date_ymd!(tempo, function, {year, week, whole!(tempo, :day_of_week, function, 1)})

      List.keymember?(time, :day_of_year, 0) ->
        ordinal_date_ymd(year, whole!(tempo, :day_of_year, function), calendar_of(tempo))

      true ->
        month_date_ymd!(tempo, function, year, Keyword.get(opts, :default_day, 1))
    end
  end

  defp month_date_ymd!(%Tempo{time: time} = tempo, function, year, default_day) do
    month = whole!(tempo, :month, function, 1)
    day = whole!(tempo, :day, function, default_day)

    if List.keymember?(time, :day, 0),
      do: {year, month, day},
      else: first_ymd(time, {year, month, day}, calendar_of(tempo))
  end

  defp ordinal_date_ymd(year, day_of_year, calendar) do
    %{year: year, month: month, day: day} =
      Calendrical.date_from_day_of_year(year, day_of_year, calendar)

    {year, month, day}
  end

  # The first day of a year or a month written with no day is the first of
  # its first month, or of the month, and where the year does not begin with
  # its first month the first date the calendar gives it
  # (`Tempo.UnitValues.start_date/2`).
  defp first_ymd(time, default, calendar) do
    case UnitValues.start_date(time, calendar) do
      {:ok, ymd} -> ymd
      :error -> default
    end
  end

  # A unit an accessor reads, as the one whole number it is. A unit the
  # value lacks is the default when there is one, and otherwise the
  # accessor's `ArgumentError`, as is a unit that holds several values (a set,
  # a mask, a group), which is no one number to read.
  defp whole!(%Tempo{time: time} = tempo, unit, function, default \\ nil) when is_list(time) do
    case List.keyfind(time, unit, 0) do
      {^unit, value} when is_integer(value) ->
        value

      nil when is_integer(default) ->
        default

      nil ->
        raise ArgumentError,
              "Tempo.#{function}/1 requires a #{unit} component. Got: #{inspect(tempo)}"

      _several ->
        raise ArgumentError,
              "Tempo.#{function}/1 reads one #{unit}, and #{inspect(tempo)} holds several."
    end
  end

  # A week date's day as its calendar numbers it: the calendar's own week and
  # day in a week-based calendar, and the date of the ISO 8601 week's day in
  # any other.
  defp week_date_ymd!(tempo, function, {year, week, day}) do
    case Validation.date_from_iso_week(year, week, day, calendar_of(tempo)) do
      {:ok, date} ->
        {date.year, date.month, date.day}

      {:error, _reason} ->
        raise ArgumentError, "Tempo.#{function}/1 cannot place #{inspect(tempo)} on a day."
    end
  end

  ## ---------------------------------------------------------
  ## shift/2 — ergonomic keyword-list arithmetic
  ## ---------------------------------------------------------

  @doc """
  Shift a `t:t/0` by a duration, returning a new `t:t/0`.

  The shift amount may be given either as a `t:Tempo.Duration.t/0`
  (when you already have one, e.g. `~o"P1M"`) or as a keyword list of
  signed unit amounts (the ergonomic ad-hoc form). Both take the same
  path internally, so pass a `t:Tempo.Duration.t/0` when composing
  durations directly.

  Units are applied largest-to-smallest with the standard
  month-end clamping rule (e.g. `~o"2024-01-31" + 1 month` is
  `2024-02-29`, not `2024-03-02`).

  A fractional amount (ISO 8601-2 §11.4) becomes whole units of the
  next smaller unit, truncated toward zero: `P1.3D` is one day and
  seven hours, `P1.5W` ten days and `P1.5Y` a year and six months. A
  fraction of a month is that fraction of the days from the value to
  one month later (ISO 8601-2 D.4.4), so `2018-01-23` plus `P0.5M` is
  `2018-02-07`.

  A value in a named zone gives the reading its wall clock shows. Years,
  months, weeks and days step the calendar, so a day after noon is noon
  however long the day, and hours, minutes and seconds are time on the
  time line, so five hours after 23:00 is the reading the clock shows
  five hours later — 05:00 on the night it springs forward. Days are
  added before hours (RFC 5545 §3.3.6). A day that lands in the hour a
  spring-forward skips moves on by that hour, one that lands on a
  reading the fall-back repeats is its first occurrence (RFC 5545
  §3.3.5), and an hour that lands on a repeated reading carries its
  offset, so it names its own side of the fold.

  ### Arguments

  * `tempo` is any `t:t/0`.

  * `shift` is either a `t:Tempo.Duration.t/0`, or a keyword list of
    `{unit, amount}` pairs such as `[month: 1, day: -5]` or
    `[year: 2]`. Valid units: `:year`, `:month`, `:week`, `:day`,
    `:hour`, `:minute`, `:second`. Keyword amounts may be negative.

  * `options` is a keyword list of options.

  ### Options

  * `:skipping` is a busy set the shift jumps over: the duration is
    consumed from *free* time only. Accepts anything
    `Tempo.to_interval_set/1` accepts (an interval, an interval set, a
    `t:t/0`, a bounded recurrence), or a list of such values. The busy
    spans cost nothing to cross, and an origin already inside a busy
    span first moves to its edge (forward: the end; backward: the
    start) at no cost. The duration must be exact — built from
    `:week`/`:day`/`:hour`/`:minute`/`:second` — because a month or
    year of free time has no fixed length; `:year`/`:month` components
    return `{:error, %Tempo.InvalidUnitError{}}`. Busy spans must be
    anchored and bounded. In the keyword-units form `:skipping` may
    ride in the same list: `Tempo.shift(t, hour: -1, skipping: busy)`.
    A day shifted by days or weeks steps from free day to free day, a
    calendar day at a time, and lands on a day: one day of free time
    after a Friday before a long weekend is the Tuesday, and a week of
    it seven free days on.

  ### Returns

  * The shifted `t:t/0`.

  * `{:error, %Tempo.UnanchoredError{}}` when the value has no
    `:year` (an unanchored month/day, bare-day, or time-of-day value)
    and the shift's result would depend on the missing year. The rule:
    an unanchored shift is **computed when its result is invariant to
    the year, and errors when it isn't** (it never raises). So
    `~o"1M31D"` plus one day is `~o"2M1D"` (January always has 31 days)
    and a whole-year step is a no-op (`~o"1M31D"` plus `P1Y` is
    `~o"1M31D"`), but `~o"1M31D"` plus one month lands on an unresolvable
    "Feb 31" and `~o"2M28D"` plus one day (Feb 29 or Mar 1?) both error.

  * `{:error, %Tempo.ConversionError{reason: :grouped_component}}` when
    the shift would count from a unit that holds several values — a
    set, a range, a group or unspecified digits. A step every one of
    those values takes alike is computed, so `~o"2026Y{6,7}M15D"` plus
    one day is the 16th of both months; plus one month it is an error,
    since no one month follows both June and July.

  * `{:error, reason}` when the value holds a selection and the shift
    steps a unit it does not carry: a month on `~o"2027Y4ML1K1IN"`, the
    first Monday of April 2027, is the first Monday of May, but it has no
    day to add a day to. Also when the arguments are not a Tempo value
    and a shift, or a keyword unit is not a duration's unit and a number
    of it.

  ### Examples

      iex> Tempo.shift(~o"2026-06-15", month: 1, day: -5)
      ~o"2026Y7M10D"

      iex> Tempo.shift(~o"2026-01-31", month: 1)
      ~o"2026Y2M28D"

      iex> Tempo.shift(~o"2018-01-23", ~o"P0.5M")
      ~o"2018Y2M7D"

      iex> Tempo.shift(~o"2026-06-15T10:00:00", hour: -3)
      ~o"2026Y6M15DT7H0M0S"

      iex> Tempo.shift(~o"2026", ~o"P2Y")
      ~o"2028Y"

      iex> Tempo.shift(~o"1M31D", ~o"P1D")
      ~o"2M1D"

      iex> Tempo.shift(~o"1M31D", ~o"P1Y")
      ~o"1M31D"

      iex> match?({:error, %Tempo.UnanchoredError{}}, Tempo.shift(~o"1M31D", ~o"P1M"))
      true

  A week steps by weeks to a week, and by days or hours to the date it
  lands on, as a week date is read (`2026-W25-2` is 16 June):

      iex> Tempo.shift(~o"2026-W25", week: 1)
      ~o"2026Y26W"

      iex> Tempo.shift(~o"2026-W25", day: 1)
      ~o"2026Y6M16D"

  The 15th of June and of July, a day on and a month on:

      iex> Tempo.shift(~o"2026Y{6,7}M15D", day: 1)
      ~o"2026Y{6..7}M16D"

      iex> match?({:error, %Tempo.ConversionError{}}, Tempo.shift(~o"2026Y{6,7}M15D", month: 1))
      true

  On the night New York's clocks spring forward, five hours after 23:00
  is 05:00, and a day after noon is noon:

      iex> Tempo.shift(~o"2026-03-07T23[America/New_York]", hour: 5)
      ~o"2026Y3M8DT5H[America/New_York]"

      iex> Tempo.shift(~o"2026-03-07T12[America/New_York]", day: 1)
      ~o"2026Y3M8DT12H[America/New_York]"

  One hour of working time from 09:30, skipping a 10:00–11:00 meeting,
  ends at 11:30 — the meeting hour costs nothing:

      iex> meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"
      iex> Tempo.shift(~o"2026-06-15T09:30", ~o"PT1H", skipping: meeting)
      ~o"2026Y6M15DT11H30M0S"

      iex> meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"
      iex> Tempo.shift(~o"2026-06-15T10:30", ~o"PT0S", skipping: meeting)
      ~o"2026Y6M15DT11H0M"

  """
  @spec shift(t(), Tempo.Duration.t() | keyword(), keyword()) ::
          t() | Tempo.Set.t() | Tempo.IntervalSet.t() | {:error, error_reason()}
  def shift(tempo, shift, options \\ [])

  def shift(%Tempo{} = tempo, %Tempo.Duration{} = duration, []) do
    Math.add(tempo, duration)
  end

  def shift(%Tempo{} = tempo, %Tempo.Duration{} = duration, options) when is_list(options) do
    case Keyword.fetch(options, :skipping) do
      {:ok, busy} -> Math.shift_skipping(tempo, duration, busy)
      :error -> Math.add(tempo, duration)
    end
  end

  # Every ISO 8601 duration arriving from outside is a string —
  # iCalendar `DURATION`, `TRIGGER`, `REPEAT` — so accept the string
  # and parse it here rather than at every call site. `"-PT30M"`
  # (leading-sign form) parses to the negated duration.
  def shift(%Tempo{} = tempo, duration_string, options) when is_binary(duration_string) do
    case from_iso8601(duration_string) do
      {:ok, %Duration{} = duration} ->
        shift(tempo, duration, options)

      {:ok, other} ->
        {:error,
         ConversionError.exception(
           value: duration_string,
           target: Duration,
           reason:
             "the string parsed as #{inspect(other)}, not a duration — " <>
               "`Tempo.shift/2` takes an ISO 8601 duration such as \"PT30M\" or \"-P1D\""
         )}

      {:error, _} = error ->
        error
    end
  end

  def shift(%Tempo{} = tempo, units, options) when is_list(units) do
    # In the keyword form the options merge into the same list —
    # `shift(t, second: -3600, skipping: busy)` — so split them
    # out before the rest becomes a duration.
    with {:ok, units} <- shift_units(units) do
      {skip_options, units} = Keyword.split(units, [:skipping])
      shift(tempo, Duration.build(units), Keyword.merge(skip_options, options))
    end
  end

  def shift(tempo, shift, _options) do
    {:error,
     ArgumentError.exception(
       "Tempo.shift/3 shifts a Tempo value by a duration or by keyword units, not " <>
         "#{inspect(tempo)} by #{inspect(shift)}."
     )}
  end

  # The units a value is shifted by are a duration's: a number of each, and a
  # fraction of a second as `{microseconds, digits}`. A unit a duration has
  # none of was passed over, leaving the value where it was, and a value
  # that is no number reached the calendar's arithmetic.
  @shift_units [:year, :month, :week, :day, :hour, :minute, :second]

  defp shift_units(units) do
    case Enum.find(units, &(not shift_unit?(&1))) do
      nil -> {:ok, units}
      other -> {:error, shift_unit_error(other)}
    end
  end

  defp shift_unit?({:skipping, _busy}), do: true
  defp shift_unit?({unit, value}) when unit in @shift_units, do: is_number(value)

  defp shift_unit?({:microsecond, {value, digits}}),
    do: is_integer(value) and digits in 0..6

  defp shift_unit?(_other), do: false

  defp shift_unit_error(other) do
    ArgumentError.exception(
      "Tempo.shift/3 shifts by a number of #{inspect(@shift_units)}, or by " <>
        "`microsecond: {microseconds, digits}`, and #{inspect(other)} is neither."
    )
  end

  ## ---------------------------------------------------------
  ## Locale-aware formatting — to_string/1,2
  ## ---------------------------------------------------------

  @doc """
  Format a Tempo value as a locale-aware string.

  Routes through Localize so format patterns, month and weekday names, day periods, and punctuation all follow CLDR data for the chosen locale. The default format is keyed off the Tempo's resolution — a year renders as its first and last months, a month or a week as its first and last days, a day as that day, and so on. A week date is the day it names.

  A value that names something other than its own one span renders as the span or spans `Tempo.to_interval/2` gives it: a mask its span (`~o"202X"` is 2020 to 2029), and a recurrence, a selection or a set its spans as a list in the locale. A one-of set renders as its alternatives ("2026 or 2027").

  An interval renders from its first value to its last, the end being excluded, in the unit it is walked by: the finer of its two ends' units, so `~o"2026/2026-03"` is January to February 2026. A week beside a date is shown as the date its first day is.

  `Tempo.to_string/1,2` is the end-user display function. `inspect/1` remains the programmer-facing form and returns the `~o"…"` sigil representation unchanged. Interpolation renders a value as `to_string/1` does, and writes one it cannot render in its ISO 8601 form.

  ### Arguments

  * `value` is a `t:t/0`, `t:Tempo.Interval.t/0`, `t:Tempo.IntervalSet.t/0`, `t:Tempo.Set.t/0`, `t:Tempo.RecurrenceSet.t/0` or `t:Tempo.Duration.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a CLDR format atom (`:short | :medium | :long | :full`), a skeleton atom (`:yMMM`, `:yMMMd`, `:hm`, …), or a pattern string. Defaults to a resolution-appropriate choice (see the module doc of `Tempo.Format` for the table).

  * `:locale` is a CLDR locale identifier such as `"en"`, `"en-GB"`, or `"de"`. Defaults to Localize's configured default locale.

  * `:within` is the window for a value with no end of its own — a recurrence with no count or `UNTIL`, a selection in an unspecified year, a recurrence set — whose occurrences are shown, as `Tempo.to_interval/2` takes it.

  * Any other option accepted by `Localize.Date.to_string/2`, `Localize.Time.to_string/2`, `Localize.DateTime.to_string/2`, `Localize.Interval.to_string/3` or `Localize.Duration.to_string/2` is forwarded verbatim. A duration shows a fraction of a second as microseconds unless `:except` leaves them out.

  ### Returns

  * `{:ok, string}` with the formatted value.

  * `{:error, exception}` when the value cannot be rendered: a `Tempo.IntervalEndpointsError` for an interval without both ends, a `Tempo.UnboundedRecurrenceError` for a recurrence with no end and no `:within` window, a `Tempo.UnboundedSetError` for an interval set without an end, a `Tempo.UnanchoredError` for a week or a day of the week without a year, a `Tempo.InvalidDateError` for a mask that names no date, an `ArgumentError` for a value of another kind or options that are not a keyword list, and Localize's error for a locale or format it does not accept.

  ### Examples

      iex> Tempo.to_string(~o"2026")
      {:ok, "Jan\u2009\u2013\u2009Dec 2026"}

      iex> Tempo.to_string(~o"2026-06")
      {:ok, "Jun 1\u2009\u2013\u200930, 2026"}

      iex> Tempo.to_string(~o"2026-06-15")
      {:ok, "Jun 15, 2026"}

      iex> Tempo.to_string(~o"2026-W25")
      {:ok, "Jun 15\u2009\u2013\u200921, 2026"}

      iex> Tempo.to_string(~o"2026-06-15", format: :long)
      {:ok, "June 15, 2026"}

      iex> Tempo.to_string(~o"2026", format: :long)
      {:ok, "January\u2009\u2013\u2009December 2026"}

      iex> Tempo.to_string(~o"P1Y6M")
      {:ok, "1 year, 6 months"}

      iex> Tempo.to_string(~o"P3DT2H", format: :short)
      {:ok, "3 days, 2 hr"}

  An interval is shown from its first value to its last:

      iex> Tempo.to_string(~o"2026/2026-03")
      {:ok, "Jan\u2009\u2013\u2009Feb 2026"}

  A recurrence is its occurrences, as a list, and a one-of set its alternatives:

      iex> Tempo.to_string(~o"R3/2026-06-15/P1D")
      {:ok, "Jun 15, 2026, Jun 16, 2026, and Jun 17, 2026"}

      iex> Tempo.to_string(~o"[2026-06-15,2026-07-04]")
      {:ok, "Jun 15, 2026 or Jul 4, 2026"}

  An open interval has no last day to show, so it is an error, and interpolation writes it in ISO 8601:

      iex> {:error, %Tempo.IntervalEndpointsError{}} = Tempo.to_string(~o"2026-06-15/..")
      iex> "From \#{~o"2026-06-15/.."}"
      "From 2026Y6M15D/.."

  """
  @spec to_string(
          t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.RecurrenceSet.t()
          | Tempo.Duration.t(),
          keyword()
        ) :: {:ok, String.t()} | {:error, Exception.t()}
  defdelegate to_string(value, options \\ []), to: Tempo.Format

  @doc """
  Format a Tempo value as a locale-aware string, raising for a value it cannot render.

  ### Arguments

  * `value` is a `t:t/0`, `t:Tempo.Interval.t/0`, `t:Tempo.IntervalSet.t/0` or `t:Tempo.Duration.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * The options of `to_string/2`, `:within` included.

  ### Returns

  * A `t:String.t/0` like `"Jun 15, 2026"`.

  ### Raises

  * The exception `to_string/2` returns.

  ### Examples

      iex> Tempo.to_string!(~o"2026-06-15")
      "Jun 15, 2026"

  """
  @spec to_string!(
          t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.RecurrenceSet.t()
          | Tempo.Duration.t(),
          keyword()
        ) :: String.t()
  def to_string!(value, options \\ []) do
    case to_string(value, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Format a Tempo as a locale-aware relative time string like `"3 hours ago"` or `"in 2 days"`.

  Routes through Localize's CLDR `relativeTime` patterns. The reference point ("now") comes from `Tempo.utc_now/0` unless overridden with the `:from` option — which makes this safe to use in tests via `Tempo.Clock.Test`.

  The difference is counted in calendar periods of the value's own calendar, on the value's own wall clock: 1 February is "next month" from 31 January, and a Hebrew date counts Hebrew months. A value is where its span starts. A day or longer is a date, counted in days and longer periods; a finer value, or one counted in hours, minutes or seconds, is a moment of its day, in its time zone when it has one, so the hours across a change of offset are the hours that pass.

  For intervals, where the interval starts is used as the target — "the meeting starts in 2 hours" rather than "lasts 2 hours" (for duration phrasing, use `Tempo.to_string/2` on a `Tempo.Duration`). An interval written as a duration and an end starts where the duration is counted back to, and a counted recurrence where its first occurrence does.

  ### Arguments

  * `value` is a `t:t/0` or `t:Tempo.Interval.t/0`. The value must be anchored (have a year component); an unanchored one is an error.

  ### Options

  * `:from` is a `t:t/0` — the reference point the output is relative to, from where its span starts. When the value and `:from` are both zoned, `:from` is read on the value's clock, and otherwise on its own. A zoned value finer than a day needs a zoned `:from`; a floating one is an error. Defaults to `Tempo.utc_now/0`.

  * `:unit` is the unit to count in: `:year`, `:quarter`, `:month`, `:week`, `:day`, `:hour`, `:minute`, `:second`, or a weekday from `:mon` to `:sun`. The difference is the number of the unit's calendar periods from `:from` to the value, and weeks and weekdays start on the locale's first day of the week. When `:unit` is omitted, it is the largest unit of which a whole one lies between them, but never one finer than the value's own: 2027 is "next year" from July 2026, not "in 6 months".

  * `:format` is `:standard`, `:narrow`, or `:short`. Defaults to `:standard`.

  * `:locale` is a CLDR locale. Defaults to Localize's configured default.

  ### Returns

  * `{:ok, string}` — the relative time.

  * `{:error, exception}` — a `Tempo.UnanchoredError` for a value or `:from` without a year, a `Tempo.IntervalEndpointsError` for an interval without a start, a `Tempo.FloatingTempoError` for a zoned value finer than a day from a floating `:from`, an `ArgumentError` for a value naming several spans, a value or `:from` that is not a Tempo value, or options that are not a keyword list, and Localize's error for a locale, unit or format it does not accept.

  ### Examples

      iex> now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")
      iex> Tempo.to_relative_string(~o"2026-06-14T12:00:00Z", from: now)
      {:ok, "yesterday"}

      iex> now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")
      iex> Tempo.to_relative_string(~o"2026-06-15T15:00:00Z", from: now)
      {:ok, "in 3 hours"}

      iex> Tempo.to_relative_string(~o"2026-02-01", from: ~o"2026-01-31", unit: :month)
      {:ok, "next month"}

      iex> Tempo.to_relative_string(~o"2027", from: ~o"2026-07-01")
      {:ok, "next year"}

  Rosh Hashanah 5787 is the day after 11 September 2026, and in the Hebrew calendar it is next year:

      iex> new_year = Tempo.from_iso8601!("5787-01-01[u-ca=hebrew]")
      iex> Tempo.to_relative_string(new_year, from: ~o"2026-09-11", unit: :year)
      {:ok, "next year"}

  A time of day names no year to count from:

      iex> {:error, %Tempo.UnanchoredError{}} = Tempo.to_relative_string(~o"T10:30")

  """
  @spec to_relative_string(t() | Tempo.Interval.t(), keyword()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  defdelegate to_relative_string(value, options \\ []), to: Tempo.Format

  @doc """
  Format a Tempo as a locale-aware relative time string, raising for a value it cannot format.

  ### Arguments

  * `value` is a `t:t/0` or `t:Tempo.Interval.t/0`.

  ### Options

  * The options of `to_relative_string/2`.

  ### Returns

  * A `t:String.t/0` like `"3 hours ago"` or `"in 2 days"`.

  ### Raises

  * The exception `to_relative_string/2` returns.

  ### Examples

      iex> Tempo.to_relative_string!(~o"2027", from: ~o"2026-07-01")
      "next year"

  """
  @spec to_relative_string!(t() | Tempo.Interval.t(), keyword()) :: String.t()
  def to_relative_string!(value, options \\ []) do
    case to_relative_string(value, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Convert an implicit-span `t:#{__MODULE__}.t/0` into the
  equivalent explicit `t:Tempo.Interval.t/0` or
  `t:Tempo.IntervalSet.t/0`.

  Every Tempo value represents a bounded interval on the time
  line. `~o"2026-01"` *is* the interval `[2026-01-01, 2026-02-01)`
  — `to_interval/1` converts that implicit span to a pair of
  concrete endpoints under the half-open `[from, to)` convention
  (`from` inclusive, `to` exclusive). The span is one unit at the
  value's resolution: a day value becomes a one-day interval, a
  second value a one-second interval. This is the canonical
  representation used by the set-operations API (`union/2`,
  `intersection/2`, `coalesce/1`). See the
  [interop guide](interop.html) for the spans converted Elixir
  date and time values cover.

  When the input expands to multiple disjoint spans — a set of
  explicit values, a range over a time unit, a stepped range —
  the result is a `%Tempo.IntervalSet{}` with intervals sorted
  and coalesced. The conversion is idempotent on values that are
  already explicit.

  A value holding a selection (ISO 8601-2 §12.11) is the dates the
  selection picks in each period of the units before it:
  `~o"2018Y3ML1K1IN"` is the first Monday of March 2018, and a set or
  mask of years resolves one year at a time. A selection in an
  unspecified year (`~o"X*YL5M7K2IN"`) needs a `:within` window.

  A mask is the span its digits allow: `~o"156X"` is the 1560s and `~o"2026-06-1X"` the 10th to the 19th of June 2026. Candidates that are not consecutive (`~o"2026-06-X5"`), or a mask with a narrower unit after it (`~o"1985-XX-15"`), are a span each, and a candidate the calendar has no room for drops out. An unspecified month, week, day, hour, minute or second (`~o"2026Y6MX*D"`, any day of June 2026) is read as the mask of all its digits is: the month.

  A recurrence is its occurrences however ISO 8601-1 §5.6.1 writes it: a start and a duration, a start and an end that are its first occurrence (each one after it starts where the one before ends and is as long), or a duration and an end that are its last.

  ### Arguments

  * `value` is a `t:#{__MODULE__}.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.IntervalSet.t/0`, `t:Tempo.RecurrenceSet.t/0`, or
    `t:Tempo.Set.t/0`.

  ### Options

  * `:within` is the window whose occurrences you want — a Tempo
    value such as `~o"2026"`. Every recurrence keeps the occurrences
    that overlap the window: one already in progress when the
    window opens, and one that runs past its end. Required for a
    recurrence with no end (no count and no `UNTIL`), a recurrence
    with an open start (`R/../P1Y/…`) and a selection in an
    unspecified year; a single value or interval ignores it.

    A window with no zone bounds a value in a zone in that zone:
    `~o"2026-06"` is June in New York for a recurrence written in
    `[America/New_York]`. A window written with a zone or an offset
    is the moments it names.

    An open-ended window — `~o"2026-09-28/.."`, or
    `Tempo.Interval.new(from: today)` — keeps the occurrences from
    its start on. For a value with no end of its own they are a
    lazy `t:Tempo.IntervalSet.t/0`, walked as it is read, so
    `Tempo.IntervalSet.first/1` is the next occurrence; a walk that
    finds none in a thousand years ends.

  * `:coalesce` — `true` merges adjacent or overlapping
    occurrences into single spans; `false`, the default, keeps
    each occurrence as its own interval, as event identity needs
    (`Tempo.ICal`, the RRULE expander). An open-ended window's
    occurrences are never merged.

  ### Returns

  * `{:ok, interval}` when the value converts to a single
    contiguous span.

  * `{:ok, interval_set}` when the value expands to multiple
    disjoint spans.

  * `{:ok, interval_set}` on the lazy backend when an open-ended
    `:within` window walks a value with no end of its own. It
    answers `Tempo.IntervalSet.first/1` and the other walking
    questions; `Tempo.IntervalSet.count/1` and `members/1` raise
    `Tempo.UnboundedSetError`.

  * `{:error, reason}` when the input cannot be converted — a
    bare `Tempo.Duration` (no start), a `Tempo` at a resolution
    with no finer unit available to bound the span (a microsecond
    converts to a one-microsecond span; only exotic selector
    resolutions have no span), a one-of `Tempo.Set` (epistemic
    disjunction is not an interval list; the user must pick one or
    handle the disjunction themselves), a recurrence with no end and
    no `:within` window, or a leftover `:bound` option.

  * `{:error, %Tempo.UnanchoredError{}}` when the value has no
    concrete year and resolving the span would depend on the missing
    one — `~o"X*Y2M28D"` (February is 28 or 29 days), or a yearless
    masked month in a calendar whose month count varies by year. An
    interval's duration, or a recurrence's cadence, that cannot be
    counted from such a value is the same error: the second month
    after `~o"12M31D"` is a 31 February.

  * `{:error, %Tempo.ConversionError{reason: :grouped_component}}`
    when a span's end would be counted from a unit that holds several
    values — the day after `~o"2026Y6M{1,15}D"` in
    `2026Y6M{1,15}D/P1D`. The value on its own converts to a span for
    each value it names.

  * `{:error, %Tempo.InvalidDateError{}}` when a mask names no date —
    `~o"2026-02-3X"`, as February has no 30th or 31st — or a set none
    of whose values exists does, `~o"2026Y{2,6}M31D"`.

  * `{:error, %Tempo.EventError{}}` when a computed event has no date where the value asks for it: a year the event is not computed for (`~o"R2/0500Y/P1Y/FL(march-equinox)eN"`, an equinox being computed from 1000 CE), or a name no resolver knows. The error names the event and the year.

  ### Examples

      iex> {:ok, tempo} = Tempo.from_iso8601("2026-01")
      iex> {:ok, interval} = Tempo.to_interval(tempo)
      iex> interval.from.time
      [year: 2026, month: 1]
      iex> interval.to.time
      [year: 2026, month: 2]
      iex> interval.unit
      :day

      iex> {:ok, tempo} = Tempo.from_iso8601("156X")
      iex> {:ok, interval} = Tempo.to_interval(tempo)
      iex> {interval.from.time, interval.to.time}
      {[year: 1560], [year: 1570]}

      iex> {:ok, duration} = Tempo.from_iso8601("P3M")
      iex> {:error, %Tempo.ConversionError{reason: :bare_duration}} = Tempo.to_interval(duration)

      iex> {:ok, election_day} = Tempo.from_iso8601("2024Y11MLLL1K1IN/P9DN2K1IN")
      iex> {:ok, dates} = Tempo.to_interval(election_day)
      iex> Tempo.relation(dates, ~o"2024-11-05")
      :equals

      iex> {:ok, christmases} = Tempo.to_interval(~o"R/../P1Y/FL12M25DN", within: ~o"2026/2028")
      iex> Tempo.IntervalSet.count(christmases)
      2

      iex> {:ok, christmases} = Tempo.to_interval(~o"R/../P1Y/FL12M25DN", within: ~o"2026-12-26/..")
      iex> Tempo.IntervalSet.first(christmases)
      ~o"2027Y12M25D/26D"

  """
  @spec to_interval(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.RecurrenceSet.t()
          | Tempo.Duration.t(),
          keyword()
        ) ::
          {:ok, Tempo.Interval.t() | Tempo.IntervalSet.t()} | {:error, error_reason()}
  def to_interval(value, opts \\ []) do
    with :ok <- check_bound_option(opts, "Tempo.to_interval/2"),
         opts = window_in_value_frame(value, opts),
         :ok <- ends_expand(value),
         value = counted_from_points(value),
         {:ok, value} <- placed_on_window(value, Keyword.get(opts, :within)),
         :one_start <- recurrence_from_each_value(value, opts),
         :ok <- rule_has_a_date(value),
         :ok <- walkable(value) do
      case open_window_start(Keyword.get(opts, :within)) do
        {:ok, window_from} -> occurrences_from(value, window_from, opts)
        {:error, _reason} = error -> error
        :bounded -> value |> materialise(opts) |> spans_between_points(value)
      end
    end
  end

  # A recurrence's rule that selects a day of a month, a weekday, a week or a
  # month from the end counts it in the date of each occurrence, and a
  # recurrence that starts with no year (`R3/6M/P1M/FL15DN`) has no date to
  # count it in: which days a month has, and which is a Monday, depend on the
  # year. Months as they are written and the units of a time of day need none.
  defp rule_has_a_date(%Interval{
         from: %__MODULE__{time: time} = from,
         repeat_rule: %__MODULE__{time: [{:selection, selection} | _units]}
       })
       when is_list(time) do
    if Keyword.has_key?(time, :year) or not Selection.needs_a_date?(selection),
      do: :ok,
      else: {:error, UnanchoredError.exception(value: from)}
  end

  defp rule_has_a_date(_value), do: :ok

  # A group of a set at an end of an interval (`R3/2026Y{1,2}G3MU15D/P1D`) names
  # a span in each of its groups, which nothing expands, so the interval has
  # no one start to count from or end to count to.
  defp ends_expand(%Interval{from: from, to: to}) do
    case Enum.find([from, to], &group_of_set_end?/1) do
      nil -> :ok
      endpoint -> {:error, materialisation_error(endpoint, :grouped_component)}
    end
  end

  defp ends_expand(_value), do: :ok

  defp group_of_set_end?(%__MODULE__{time: time}) when is_list(time), do: group_of_set?(time)
  defp group_of_set_end?(_absent), do: false

  # A duration is counted from a point. A start or an end that names a span
  # (a mask, a group) is read as the point the span starts at before the
  # duration is counted, as it is in an interval written with two ends:
  # `2026YXXO/P1M` runs a month from 1 January. One that names several spans
  # is left to be walked, or refused, as it is written.
  defp counted_from_points(%Interval{duration: %Duration{}} = interval) do
    if Interval.points?(interval), do: interval, else: points_or_as_written(interval)
  end

  defp counted_from_points(value), do: value

  defp points_or_as_written(interval) do
    case Interval.endpoints_as_points(interval) do
      {:ok, counted_from} -> counted_from
      {:error, _several_spans} -> interval
    end
  end

  # A `:within` window with no zone bounds a value in a zone in that zone.
  defp window_in_value_frame(value, opts) do
    case Keyword.fetch(opts, :within) do
      {:ok, window} -> Keyword.put(opts, :within, Interval.window_in_frame_of(window, value))
      :error -> opts
    end
  end

  # An interval written with a duration, or a recurrence, steps from its
  # start as it is written, so a start that is no one point — a mask, a
  # group, an unspecified unit (`2026Y6MXXD/P1M`) — is still in the ends of
  # each span it gives. Each is then read as an interval written with two
  # ends is: from the point its start's span starts at to the point its
  # end's does.
  defp spans_between_points(
         {:ok, converted},
         %Interval{recurrence: recurrence, duration: duration} = written
       )
       when recurrence != 1 or not is_nil(duration) do
    if Interval.points?(written), do: {:ok, converted}, else: between_points(converted)
  end

  defp spans_between_points(result, _written), do: result

  defp between_points(%Interval{} = span), do: Interval.endpoints_as_points(span)

  defp between_points(%IntervalSet{} = set) do
    if IntervalSet.bounded?(set), do: members_between_points(set), else: {:ok, set}
  end

  defp members_between_points(set) do
    set
    |> IntervalSet.members()
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, spans} ->
      case Interval.endpoints_as_points(member) do
        {:ok, span} -> {:cont, {:ok, [span | spans]}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, spans} -> IntervalSet.new(Enum.reverse(spans), metadata: IntervalSet.metadata(set))
      {:error, _exception} = error -> error
    end
  end

  # A recurrence whose start has no year, given a dated window, starts on the
  # window's first day, month or year, whichever its start lacks — as
  # `at/2` places one value on another: `R/T22H/PT1H` within 15 June is from
  # 22:00 on 15 June, and `R/12M31D/P1D` within 2026 from 31 December 2026.
  defp placed_on_window(
         %Interval{
           recurrence: recurrence,
           from: %__MODULE__{time: [{unit, _} | _] = time} = start
         } =
           interval,
         within
       )
       when recurrence != 1 and not is_nil(within) do
    with false <- on_the_time_line?(time),
         %__MODULE__{time: window_time} = window_from <- bound_lower(within),
         true <- on_the_time_line?(window_time),
         {:ok, %__MODULE__{} = placed} <- placed_start(window_from, unit, start) do
      {:ok, %{interval | from: placed}}
    else
      {:error, _reason} = error -> error
      _not_placed -> {:ok, interval}
    end
  end

  defp placed_on_window(value, _within), do: {:ok, value}

  # A day of the week starts on the first such day on or after the window's
  # start, in its week when the window is a calendar of weeks.
  defp placed_start(
         window_from,
         :day_of_week,
         %__MODULE__{time: [{:day_of_week, weekday} | finer]} = start
       )
       when is_integer(weekday) do
    case at_resolution(window_from, :week) do
      %__MODULE__{} = week -> at(week, start)
      {:error, _no_week} -> weekday_on_or_after(window_from, weekday, finer)
    end
  end

  defp placed_start(window_from, unit, start) do
    with %__MODULE__{} = base <- at_resolution(window_from, placement_unit(unit)),
         do: at(base, start)
  end

  defp weekday_on_or_after(window_from, weekday, finer) do
    with %__MODULE__{} = day <- at_resolution(window_from, :day),
         {:ok, date} <- to_date(day) do
      first = date |> Kday.kday_on_or_after(weekday) |> from_date()
      if finer == [], do: {:ok, first}, else: at(first, %{first | time: finer})
    end
  end

  # The unit a start with no year is placed below: the window's day for a
  # time of day, its year for a month, and so on.
  defp placement_unit(:hour), do: :day
  defp placement_unit(:minute), do: :hour
  defp placement_unit(:second), do: :minute
  defp placement_unit(:day), do: :month
  defp placement_unit(:day_of_week), do: :week
  defp placement_unit(_unit), do: :year

  # A recurrence from a start that holds a set or a range
  # (`R3/2026Y6M{1,15}D/P1M`, from the 1st and the 15th of June) is a
  # recurrence from each of the start's values, as a set in a value is each of
  # its members: six occurrences here. A start that holds anything else (a
  # mask, a group) is walked, or refused, as one start.
  defp recurrence_from_each_value(
         %Interval{recurrence: recurrence, from: %__MODULE__{} = from} = interval,
         opts
       )
       when recurrence != 1 do
    case Enumeration.expand(from) do
      {:ok, starts} -> occurrences_from_each(starts, interval, opts, [])
      {:error, _exception} = error -> error
      :not_expandable -> :one_start
    end
  end

  defp recurrence_from_each_value(_value, _opts), do: :one_start

  defp occurrences_from_each([], _interval, opts, occurrences),
    do: IntervalSet.new(occurrences, coalesce: coalesce_opt(opts))

  defp occurrences_from_each([start | starts], interval, opts, occurrences) do
    case to_interval(%{interval | from: start}, opts) do
      {:ok, %Interval{} = occurrence} ->
        occurrences_from_each(starts, interval, opts, [occurrence | occurrences])

      {:ok, %IntervalSet{} = set} ->
        gathered_from_each(set, starts, interval, opts, occurrences)

      {:error, _exception} = error ->
        error
    end
  end

  # An open-ended window gives each start's occurrences lazily, and lazy sets
  # are not merged.
  defp gathered_from_each(set, starts, interval, opts, occurrences) do
    if IntervalSet.bounded?(set) do
      occurrences = Enum.reverse(IntervalSet.members(set), occurrences)
      occurrences_from_each(starts, interval, opts, occurrences)
    else
      {:error,
       ConversionError.exception(
         value: interval,
         reason:
           "A recurrence from a start that holds several values gathers the occurrences " <>
             "of each, which an open-ended `:within` window does not end. Give the window an end."
       )}
    end
  end

  # A recurrence is walked by stepping its start by its cadence and applying
  # its selection to each step. A cadence its start cannot be stepped by (a
  # month, from a week date) and a selection by a unit its calendar has none of
  # (a month, in a calendar of weeks) give nothing to walk, and are errors.
  defp walkable(
         %Tempo.Interval{
           recurrence: recurrence,
           from: %Tempo{time: from_time} = from,
           duration: %Tempo.Duration{} = cadence
         } = interval
       )
       when recurrence != 1 do
    dated? = on_the_time_line?(from_time)

    case Math.add(from, cadence) do
      # A cadence that brings a start with no year back to itself (`R3/7K/P1W`,
      # `R3/T22H/P1D`) makes every occurrence the same whole turn of its axis,
      # which no two endpoints on that axis can write.
      %Tempo{time: ^from_time} when not dated? -> {:error, whole_turn_error(from, cadence)}
      %Tempo{} -> selectable(interval.repeat_rule, interval)
      {:error, reason} -> {:error, step_error(from, reason)}
      # A start that holds unspecified digits steps to a set of candidates
      # (`202XY` and a month, some February of the 2020s), not to one next
      # occurrence.
      _several -> {:error, step_error(from, :grouped_component)}
    end
  end

  defp walkable(%Tempo.Interval{repeat_rule: %Tempo{} = rule} = interval),
    do: selectable(rule, interval)

  # A value holding a selection (ISO 8601-2 §12.11) selects as a rule does.
  defp walkable(%Tempo{time: time} = value) when is_list(time) do
    case List.keyfind(time, :selection, 0) do
      {:selection, selection} -> selectable(%{value | time: selection}, value)
      nil -> :ok
    end
  end

  defp walkable(_value), do: :ok

  # Whether a value is placed on the time line by a year of its own, where one
  # with no year lies on an axis that comes round again.
  defp on_the_time_line?(time) do
    case List.keyfind(time, :year, 0) do
      {:year, year} when is_integer(year) -> true
      {:year, {year, _annotations}} when is_integer(year) -> true
      _no_year -> false
    end
  end

  defp whole_turn_error(from, cadence) do
    ConversionError.exception(
      value: from,
      reason:
        "#{inspect(cadence)} brings #{inspect(from)}, which has no year, back to itself, so " <>
          "each occurrence would be the same whole turn of its axis. Place the start on a " <>
          "date first with `Tempo.at/2` or `Tempo.on/2`."
    )
  end

  # The stepper names what it cannot step by an atom where it has no value to
  # name; the start is in scope here.
  defp step_error(_from, reason) when is_exception(reason), do: reason
  defp step_error(from, :unanchored), do: UnanchoredError.exception(value: from)
  defp step_error(from, reason), do: materialisation_error(from, reason)

  # The span a value and a duration give: the stepper's error when the
  # duration cannot be counted from the value (a day past 28 February of no
  # year), never an interval holding it. A value that holds unspecified
  # digits steps to a set of candidates, which is no one end either.
  defp derived_span({:error, reason}, value, _span), do: {:error, step_error(value, reason)}
  defp derived_span(%Tempo{} = derived, _value, span), do: {:ok, span.(derived)}

  defp derived_span(_several, value, _span),
    do: {:error, step_error(value, :grouped_component)}

  defp selectable(%Tempo{time: time} = rule, interval) do
    if selects_by_month?(time) and week_based_calendar?(calendar_of(rule)) do
      {:error,
       ConversionError.exception(
         value: interval,
         reason:
           "#{inspect(calendar_of(rule))} is a calendar of weeks, with no months, so " <>
             "#{inspect(interval)} cannot select by a month, a day of one or a day of the year."
       )}
    else
      NotBuilt.selection(time, interval, Compare.effective_calendar(calendar_of(rule)))
    end
  end

  defp selectable(_no_rule, _interval), do: :ok

  # Whether a selection, or a window within it, selects by a month, by a day
  # of one or by a day of the year: the units a date written for a calendar of
  # weeks is read in the Gregorian calendar by.
  defp selects_by_month?(units) when is_list(units), do: Enum.any?(units, &selects_by_month?/1)

  defp selects_by_month?({unit, _value})
       when unit in [:month, :traditional_month, :day, :day_of_year],
       do: true

  defp selects_by_month?({:selection, selection}), do: selects_by_month?(selection)

  defp selects_by_month?({:interval, %Tempo.Interval{from: %Tempo{time: time}}}),
    do: selects_by_month?(time)

  defp selects_by_month?(_other_unit), do: false

  @doc false
  # 1.x called the window `:bound`. A leftover `:bound` is an error naming
  # `:within`, never silently ignored — every function that takes the window
  # checks its options here. An open-ended window (`2026-09-28/..`) is a lazy
  # walk that only `to_interval/2` and `to_interval_set/2` return, so every
  # other function that takes a window needs one with an end.
  @spec check_within_option(keyword(), String.t()) :: :ok | {:error, Exception.t()}
  def check_within_option(options, function) do
    with :ok <- check_bound_option(options, function) do
      check_window_end(Keyword.get(options, :within), function)
    end
  end

  defp check_bound_option(options, function) do
    if Keyword.has_key?(options, :bound) do
      {:error,
       ArgumentError.exception(
         ":bound is not an option of #{function}; pass the window as :within"
       )}
    else
      :ok
    end
  end

  defp check_window_end(within, function) do
    case open_window_start(within) do
      :bounded ->
        :ok

      _open ->
        {:error,
         ArgumentError.exception(
           "#{function} needs a :within window with an end; " <>
             "an open-ended window is for Tempo.to_interval_set/2"
         )}
    end
  end

  # An open-ended window — `~o"2026-09-28/.."`, or `Tempo.Interval.new(from: today)`
  # — has a start and no end. Its start is the earliest instant of its `from`,
  # as a bounded window's is, so a masked or selected `from` starts where the
  # span it names does.
  defp open_window_start(%Tempo.Interval{
         from: %Tempo{} = from,
         to: to,
         duration: nil,
         recurrence: 1
       })
       when to in [nil, :undefined] do
    with %Tempo{} = start <- bound_lower(from),
         true <- anchored?(start) do
      {:ok, start}
    else
      _no_point_in_time ->
        {:error,
         ArgumentError.exception(
           "an open-ended :within window must start at a point in time; " <>
             "#{inspect(from)} names none"
         )}
    end
  end

  defp open_window_start(_within), do: :bounded

  # With an open-ended window, a value with no end of its own walks its
  # occurrences lazily from the window's start; any other value materialises as
  # in a bounded window, keeping what overlaps the time from the start on.
  defp occurrences_from(value, window_from, opts) do
    if unending?(value) do
      lazy_occurrences(value, window_from, opts)
    else
      materialise(value, opts)
    end
  end

  # A value with no end of its own: a recurrence with no count or UNTIL, one
  # with an open start, one over an open domain, a selection made in every
  # year, or a recurrence set holding one — a conditional member counting when
  # the set it reads its condition from has no end.
  defp unending?(%Tempo.Interval{from: %Tempo.Set{} = domain}), do: open_domain?(domain)

  defp unending?(%Tempo.Interval{from: from, to: to, recurrence: recurrence})
       when from in [nil, :undefined] and to in [nil, :undefined] and recurrence != 1,
       do: true

  defp unending?(%Tempo.Interval{from: %Tempo{}, to: to, recurrence: :infinity})
       when to in [nil, :undefined],
       do: true

  defp unending?(%Tempo.RecurrenceSet{members: members}), do: Enum.any?(members, &unending?/1)

  defp unending?(%Conditional{member: member, falls_on: falls_on}),
    do: unending?(member) or unending?(falls_on)

  defp unending?(%Tempo{time: time}), do: every_year_selection?(time)
  defp unending?(_value), do: false

  defp open_domain?(%Tempo.Set{set: [_ | _] = members}),
    do: Enum.any?(members, &open_ended_range?/1)

  defp open_domain?(%Tempo.Set{set: [], except: [], filter: nil}), do: false
  defp open_domain?(%Tempo.Set{set: []}), do: true

  defp open_ended_range?(%Tempo.Range{last: :undefined}), do: true
  defp open_ended_range?(_member), do: false

  defp every_year_selection?(time) do
    case Enum.split_while(time, &(not match?({:selection, _}, &1))) do
      {context, [{:selection, _selection} | _trailing]} ->
        Keyword.get(context, :year) in [nil, :any]

      {_time, []} ->
        false
    end
  end

  # How far the walk from an open-ended window's start goes without finding an
  # occurrence before it ends. A calendar rule repeats within its calendar's
  # cycle — 400 years in the Gregorian — so a rule with no occurrence in a
  # thousand years has none to find.
  @occurrence_horizon %Tempo.Duration{time: [year: 1_000]}

  # The occurrences of a value with no end of its own, from an open-ended
  # window's start on, as a lazy set. The walk materialises one bounded window
  # at a time, as a `:within` window does: small at first, so the next
  # occurrence comes quickly, then doubling to a limit. An occurrence belongs to
  # the window it starts in, the first window also keeping one already under
  # way, so none repeats and they come in time order, never coalesced. The walk
  # ends once the horizon passes with no occurrence, or where a window cannot be
  # materialised (beyond a calendar's range); an error in the first window is
  # returned, and a computed event with no date in a later one is raised when
  # the walk reaches it (`walked/5`).
  defp lazy_occurrences(value, window_from, opts) do
    base = value |> cadence_unit() |> walk_base()
    walk_opts = Keyword.delete(opts, :coalesce)

    with %Tempo{} = first_to <- walk_end(window_from, base, 0),
         {:ok, first} <- walk_window(value, window_from, first_to, walk_opts) do
      found = IntervalSet.members(first)
      horizon = horizon_after(Math.add(window_from, @occurrence_horizon), found)

      later =
        {first_to, 1, horizon}
        |> Stream.unfold(&walk_next(&1, value, base, walk_opts))
        |> Stream.concat()

      {:ok,
       IntervalSet.from_stream(Stream.concat(found, later), metadata: IntervalSet.metadata(first))}
    end
  end

  defp walk_next({_window_from, _step, horizon}, _value, _base, _opts)
       when not is_struct(horizon, Tempo),
       do: nil

  defp walk_next({window_from, step, horizon}, value, base, opts) do
    with :earlier <- Compare.compare_endpoints(window_from, horizon),
         %Tempo{} = window_to <- walk_end(window_from, base, step) do
      value
      |> walk_window(window_from, window_to, opts)
      |> walked(window_from, window_to, step, horizon)
    else
      _past_the_horizon_or_unreachable -> nil
    end
  end

  # A window's occurrences that start in it, and the walk's next state; a window
  # that cannot be materialised ends the walk. One in which a computed event
  # has no date does not end it quietly, which would say the event stops
  # happening: the walk goes back to its smallest window, so that it gives
  # every occurrence before the year the event is not computed for, and there
  # it raises the event's error, as `Enum` raises for a walk it cannot make.
  defp walked({:ok, set}, window_from, window_to, step, horizon) do
    found = set |> IntervalSet.members() |> Enum.filter(&starts_from?(&1, window_from))
    {found, {window_to, step + 1, horizon_after(horizon, found)}}
  end

  defp walked({:error, %EventError{}}, window_from, _window_to, step, horizon) when step > 0,
    do: {[], {window_from, 0, horizon}}

  defp walked({:error, %EventError{} = no_date}, _window_from, _window_to, _step, _horizon),
    do: raise(no_date)

  defp walked({:error, _reason}, _window_from, _window_to, _step, _horizon), do: nil

  defp walk_window(value, window_from, window_to, opts) do
    window = %Tempo.Interval{from: window_from, to: window_to}

    case materialise(value, Keyword.put(opts, :within, window)) do
      {:ok, %IntervalSet{} = set} -> {:ok, set}
      {:ok, %Tempo.Interval{} = interval} -> IntervalSet.new([interval])
      {:error, _reason} = error -> error
    end
  end

  # The end of the walk's `step`th window: the base size, doubled each step up
  # to 64 times it.
  defp walk_end(window_from, {unit, count}, step) do
    Math.add(window_from, %Tempo.Duration{time: [{unit, count * Integer.pow(2, min(step, 6))}]})
  end

  defp starts_from?(%Tempo.Interval{from: %Tempo{} = from}, window_from),
    do: at_or_after_bound?(from, window_from)

  defp starts_from?(_occurrence, _window_from), do: false

  # The walk ends a horizon after the last occurrence it found.
  defp horizon_after(horizon, []), do: horizon
  defp horizon_after(_horizon, found), do: horizon_from(List.last(found))

  defp horizon_from(%Tempo.Interval{from: %Tempo{} = from}),
    do: Math.add(from, @occurrence_horizon)

  # The finest unit a value recurs by, which sizes the walk's windows.
  defp cadence_unit(%Tempo.Interval{duration: %Tempo.Duration{time: [_ | _] = time}}),
    do: time |> List.last() |> elem(0)

  defp cadence_unit(%Tempo.RecurrenceSet{members: [_ | _] = members}),
    do: members |> Enum.map(&cadence_unit/1) |> Enum.reduce(&finer_unit/2)

  defp cadence_unit(%Conditional{member: member}), do: cadence_unit(member)
  defp cadence_unit(_value), do: :year

  defp finer_unit(unit, other), do: if(coarser_unit?(unit, other), do: other, else: unit)

  defp walk_base(unit) when unit in [:year, :month], do: {:year, 1}
  defp walk_base(unit) when unit in [:week, :day], do: {:month, 1}
  defp walk_base(:hour), do: {:day, 1}
  defp walk_base(:minute), do: {:hour, 1}
  defp walk_base(:second), do: {:minute, 1}
  defp walk_base(_unit), do: {:year, 1}

  @doc false
  # A window with each of its ends that has no zone placed in UTC: how
  # `Tempo.ICal.available/2` reads a window written with none, since the
  # times it is met with are in UTC or a named zone (RFC 7953) and a value
  # with no zone is not combined with a zoned one.
  @spec read_in_utc(term()) :: term()
  def read_in_utc(%__MODULE__{} = value) do
    with true <- floating?(value),
         {:ok, placed} <- in_zone(value, "Etc/UTC") do
      placed
    else
      _zoned_or_unplaceable -> value
    end
  end

  def read_in_utc(%Interval{from: from, to: to} = interval),
    do: %{interval | from: read_in_utc(from), to: read_in_utc(to)}

  def read_in_utc(%IntervalSet{} = set) do
    if IntervalSet.bounded?(set),
      do: IntervalSet.with_intervals(set, Enum.map(IntervalSet.members(set), &read_in_utc/1)),
      else: set
  end

  def read_in_utc(other), do: other

  @doc false
  # The occurrences a `:within` window keeps — those that overlap it — for the
  # modules that assemble occurrences themselves (an iCalendar's events, a
  # JSCalendar's), so every function that takes a window keeps the same ones.
  # No window keeps them all.
  @spec occurrences_within([Tempo.Interval.t()], keyword()) ::
          {:ok, [Tempo.Interval.t()]} | {:error, error_reason()}
  def occurrences_within(occurrences, options), do: keep_within(occurrences, options)

  # A recurrence of no occurrences (`R0/2026-06-15/P1D`) is an empty set.
  defp materialise(%Tempo.Interval{recurrence: 0}, _opts), do: IntervalSet.new([])

  # A bounded recurrence (`R3/1985-01/P1M`) expands to N disjoint
  # intervals. Each occurrence starts at `from + i*duration` and
  # runs for one duration. Requires `Tempo.Math.add/2`.
  #
  # When `repeat_rule` is present, BY-rule selections apply
  # before the COUNT cap: N = "the first N occurrences that
  # survived the BY-rule filter," per RFC 5545. A `:within` window
  # then keeps those of the N that overlap it.
  defp materialise(
         %Tempo.Interval{
           recurrence: n,
           direction: direction,
           from: %Tempo{} = from,
           duration: %Tempo.Duration{} = duration
         } = interval,
         opts
       )
       when is_integer(n) and n > 1 do
    {from, interval} = fill_selection_start(from, interval)
    step = if direction == -1, do: Duration.negate(duration), else: duration

    walk =
      iterate_recurrence(
        from,
        step,
        occurrence_end_fn(from, duration, interval),
        fn _start -> true end,
        selection_fn(interval, duration),
        interval.metadata,
        n
      )

    with {:ok, intervals} <- walk,
         {:ok, kept} <- keep_within(intervals, opts) do
      IntervalSet.new(kept, coalesce: coalesce_opt(opts))
    end
  end

  # An unbounded recurrence with UNTIL: `recurrence: :infinity`
  # plus `to: %Tempo{}`. Iterate by one cadence at a time and stop
  # the step before the first occurrence whose start is at or past
  # the UNTIL endpoint. `from + i*duration` while `from(i) ≤ to`, and
  # every occurrence a period's selection gives is held to the same
  # inclusive UNTIL (RFC 5545), so a week expanded to its days stops
  # at the UNTIL day. A `:within` window then keeps those that start
  # within it.
  defp materialise(
         %Tempo.Interval{
           recurrence: :infinity,
           from: %Tempo{} = from,
           duration: %Tempo.Duration{} = duration,
           to: %Tempo{} = until
         } = interval,
         opts
       ) do
    {from, interval} = fill_selection_start(from, interval)

    walk =
      iterate_recurrence(
        from,
        duration,
        occurrence_end_fn(from, duration, interval),
        &under_until?(&1, until),
        selection_fn(interval, duration),
        interval.metadata
      )

    with {:ok, intervals} <- walk,
         under_until = Enum.filter(intervals, &starts_under_until?(&1, until)),
         {:ok, kept} <- keep_within(under_until, opts) do
      IntervalSet.new(kept, coalesce: coalesce_opt(opts))
    end
  end

  # A recurrence with no end: `recurrence: :infinity`, `to` is
  # nil/:undefined, so the caller's `:within` window is what ends it.
  # Iterate while every new occurrence's start falls strictly before
  # the window's end — a period that starts before it can select days
  # at or past it (a week expanded to its days) — and keep the
  # occurrences that overlap the window, as every recurrence does:
  # `R/2020-01-01/P1Y` within 2026 is 2026's occurrence alone.
  defp materialise(
         %Tempo.Interval{
           recurrence: :infinity,
           from: %Tempo{},
           duration: %Tempo.Duration{},
           to: to
         } = interval,
         opts
       )
       when to in [nil, :undefined] do
    materialise_unending(interval, Keyword.get(opts, :within), opts)
  end

  # A count-1 recurrence carrying a BY-rule selection —
  # `FREQ=DAILY;BYDAY=SU;COUNT=1` — is "the first occurrence that
  # survives the filter", not the raw `[from, from + duration)` period
  # (DTSTART itself need not satisfy the rule — it may be a Monday). So
  # apply the selection and return that first occurrence, still a single
  # interval per the count-1 contract and consistent with COUNT ≥ 2.
  defp materialise(
         %Tempo.Interval{
           recurrence: 1,
           direction: direction,
           from: %Tempo{} = from,
           duration: %Tempo.Duration{} = duration,
           repeat_rule: %Tempo{},
           to: to
         } = interval,
         _opts
       )
       when to in [nil, :undefined] do
    {from, interval} = fill_selection_start(from, interval)
    step = if direction == -1, do: Duration.negate(duration), else: duration

    case iterate_recurrence(
           from,
           step,
           occurrence_end_fn(from, duration, interval),
           fn _start -> true end,
           selection_fn(interval, duration),
           interval.metadata,
           1
         ) do
      {:ok, [%Tempo.Interval{} = first | _]} ->
        {:ok, first}

      {:ok, []} ->
        {:error,
         IntervalEndpointsError.exception(
           interval: interval,
           operation: "convert a count-1 recurrence whose BY-rule selects no occurrence",
           reason: :empty_selection
         )}

      {:error, _reason} = error ->
        error
    end
  end

  # A one-occurrence rule with no BY-rule (`FREQ=WEEKLY;COUNT=1`) steps
  # nothing, so its occurrence spans the event it carries — the
  # `occurrence_base_to` or `occurrence_duration` every occurrence of a
  # longer rule spans — not its cadence, which is all `duration` holds.
  defp materialise(
         %Tempo.Interval{
           recurrence: 1,
           from: %Tempo{} = from,
           duration: %Tempo.Duration{} = duration,
           to: to,
           metadata: metadata
         } = interval,
         _opts
       )
       when to in [nil, :undefined] and
              (is_map_key(metadata, :occurrence_base_to) or
                 is_map_key(metadata, :occurrence_duration)) do
    occurrence_end = occurrence_end_fn(from, duration, interval)

    {:ok,
     %Tempo.Interval{
       from: from,
       to: occurrence_end.(from, 0),
       metadata: strip_span_directives(metadata)
     }}
  end

  # A `from + duration` interval (`1985-01/P3M`). Materialise to
  # a closed `[from, from + duration)` interval. Preserves the
  # source interval's metadata — callers like `Tempo.ICal` need
  # event-level metadata (summary, location, …) to ride along
  # onto every materialised occurrence.
  defp materialise(
         %Tempo.Interval{
           from: %Tempo{time: time} = from,
           duration: %Tempo.Duration{} = duration,
           to: to,
           recurrence: 1,
           metadata: metadata
         },
         opts
       )
       when to in [nil, :undefined] do
    if Keyword.has_key?(time, :selection) do
      selected_spans(from, &{&1, Math.add(&1, duration)}, metadata, opts)
    else
      from
      |> Math.add(duration)
      |> derived_span(from, &%Tempo.Interval{from: from, to: &1, metadata: metadata})
    end
  end

  # A `duration + to` interval (`P1M/1985-06`). Materialise to a
  # closed `[to - duration, to)` interval.
  defp materialise(
         %Tempo.Interval{
           from: :undefined,
           duration: %Tempo.Duration{} = duration,
           to: %Tempo{time: time} = to,
           recurrence: 1,
           metadata: metadata
         },
         opts
       ) do
    if Keyword.has_key?(time, :selection) do
      selected_spans(to, &{Math.subtract(&1, duration), &1}, metadata, opts)
    else
      to
      |> Math.subtract(duration)
      |> derived_span(to, &%Tempo.Interval{from: &1, to: to, metadata: metadata})
    end
  end

  # A recurrence over a domain set (`R/{2020Y..2030Y,^2026Y}/P1Y/FL…N`). The
  # domain's plain members are the window: the selection is materialised for each
  # and unioned. `^` exclusions are already removed by materialising the domain
  # set, so an excluded year yields no occurrence — the domain is self-bounding.
  # A `:within` window, when given, narrows it further: only the domain periods
  # whose occurrences can reach it are materialised, and only the occurrences
  # that overlap it are kept — the rule every recurrence keeps. An open-ended
  # range (`{2017Y..}`, `{..2016Y}`) takes its missing end from the window, so it
  # needs one. A cadence longer than one period (`R/{1848Y..}/P4Y/…`) keeps every
  # nth period, phased from the domain's first stated value.
  defp materialise(%Tempo.Interval{from: %Tempo.Set{set: [_ | _]} = domain} = interval, opts) do
    with {:ok, window} <- within_window(opts),
         {:ok, reach} <- domain_reach_window(window, interval),
         {:ok, closed_domain} <- close_domain_ranges(domain, reach),
         {:ok, domain_set} <- to_interval(closed_domain) do
      domain_set
      |> IntervalSet.members()
      |> filter_domain_years(domain.filter)
      |> step_domain_periods(domain, interval.duration)
      |> domain_periods_to_walk(interval, reach)
      |> reduce_domain_occurrences(interval, opts)
      |> first_occurrences(interval)
      |> keep_occurrences_in_window(window)
    end
  end

  # An open, filtered domain (`R/..e/P1Y/FL…N`) has no window of its own, so it
  # needs a `:within` window: materialise the recurrence there, then keep only
  # the years matching the `:even` / `:odd` / `:leap` filter.
  defp materialise(
         %Tempo.Interval{from: %Tempo.Set{set: [], except: [], filter: filter}} = interval,
         opts
       )
       when not is_nil(filter) do
    with {:ok, occurrences} <- to_interval(%{interval | from: nil}, opts) do
      occurrences
      |> IntervalSet.members()
      |> filter_domain_years(filter)
      |> IntervalSet.new()
    end
  end

  # An exclusions-only domain (`R/^2026/P1Y/FL…N`) has no window of its own, so
  # it needs a `:within` window: materialise the recurrence there, then subtract
  # the excluded values.
  defp materialise(%Tempo.Interval{from: %Tempo.Set{set: [], except: except}} = interval, opts) do
    with {:ok, occurrences} <- to_interval(%{interval | from: nil}, opts),
         {:ok, excluded} <- to_interval(%Tempo.Set{type: :all, set: except}) do
      difference(occurrences, excluded)
    end
  end

  # A recurrence with an open start — `Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=MO")`
  # ("every Monday" beginning nowhere), or the ISO 8601 holiday form
  # `R/../P1Y/FL…N` — has no start of its own. The `:within` window supplies
  # one: the recurrence starts at the window's start and yields every
  # occurrence that starts within it. The start takes the recurrence's own
  # selection resolution — day for `FL6M1K2IN` ("the 2nd Monday of June"),
  # month for `FL6MN` ("June") — so each occurrence lands at the grain the
  # selection names rather than being forced to a day. With no window there is
  # nothing to start from, so it stays an error rather than reporting success
  # while handing back the unmaterialised rule.
  defp materialise(%Tempo.Interval{from: from, to: to, recurrence: recurrence} = interval, opts)
       when from in [nil, :undefined] and to in [nil, :undefined] and recurrence != 1 do
    case Keyword.get(opts, :within) do
      nil ->
        {:error,
         IntervalEndpointsError.exception(
           interval: interval,
           operation: "convert a recurrence that has no start",
           reason: :open_start
         )}

      within ->
        case window_start(within, interval) do
          {:ok, start} ->
            materialise_from_bound(interval, in_rule_zone(start, interval), within, opts)

          {:error, _} = error ->
            error
        end
    end
  end

  # A recurrence written with a start and an end (`R5/2026-06-15/2026-06-20`,
  # ISO 8601-1 §5.6.1 a). The two identify the first occurrence, and each one
  # after it starts where the one before ends and is as long, measured in the
  # unit its endpoints are written in (`duration/2`): `R3/2026-01/2026-03` steps
  # two months at a time. It materialises as the same recurrence written with
  # that duration, so its count, an unending one's `:within` window and a repeat
  # rule apply as they do there.
  defp materialise(
         %Tempo.Interval{
           recurrence: recurrence,
           from: %Tempo{} = from,
           to: %Tempo{} = to,
           duration: nil
         } = interval,
         opts
       )
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    with {:ok, duration} <- duration(from, to) do
      case materialise(%{interval | to: nil, duration: duration}, opts) do
        {:error, %UnboundedRecurrenceError{} = error} -> {:error, %{error | interval: interval}}
        materialised -> materialised
      end
    end
  end

  # A recurrence written with a duration and an end (`R5/P1D/2026-06-20`,
  # ISO 8601-1 §5.6.1 c). The two identify the last occurrence, and the others
  # run back from it, one duration each. Every occurrence is counted from the
  # end (`end − k × duration`), as a forward recurrence counts from its start,
  # so a month cadence keeps the stated end. An unending one runs back without
  # limit, so the `:within` window ends it.
  defp materialise(
         %Tempo.Interval{
           recurrence: recurrence,
           from: :undefined,
           duration: %Tempo.Duration{} = duration,
           to: %Tempo{} = to
         } = interval,
         opts
       )
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    back = Duration.negate(duration)
    metadata = strip_span_directives(interval.metadata)

    with {:ok, occurrences} <- occurrences_back(to, back, recurrence, interval, metadata, opts),
         {:ok, kept} <- keep_within(occurrences, opts) do
      IntervalSet.new(kept, coalesce: coalesce_opt(opts))
    end
  end

  # A single interval is its own span, each end read as the point it names:
  # `20C/21C` is `2000Y/2100Y`.
  defp materialise(%Tempo.Interval{} = interval, _opts) do
    Interval.endpoints_as_points(interval)
  end

  defp materialise(%Tempo.IntervalSet{} = set, _opts) do
    {:ok, set}
  end

  # A `%Tempo.RecurrenceSet{}` materialises each member in the `:within` window
  # (recurrences and nested sets) or as-is (concrete members), tags each
  # occurrence with the member's own metadata (a holiday name, say), and unions
  # them into one set carrying the recurrence set's own metadata. Conditional
  # members resolve in a second pass over the others' occurrences. The window's
  # start rule holds for every member, a concrete one included: a one-off 2026
  # member is not among the set's occurrences within 2027.
  defp materialise(%Tempo.RecurrenceSet{members: members, metadata: metadata}, opts) do
    with {:ok, occurrences} <- set_member_occurrences(members, opts),
         {:ok, kept} <- keep_within(occurrences, opts) do
      IntervalSet.new(kept, metadata: metadata)
    end
  end

  # A value's metadata (`new/1`'s `:metadata`) moves to the interval or
  # intervals it materialises to, so each endpoint is the value alone and
  # compares equal to it written plainly.
  defp materialise(%Tempo{metadata: metadata} = tempo, opts) when map_size(metadata) > 0 do
    with {:ok, materialised} <- to_interval(%{tempo | metadata: %{}}, opts) do
      {:ok, with_value_metadata(materialised, metadata)}
    end
  end

  defp materialise(%Tempo{time: time} = tempo, opts) do
    case Enum.split_while(time, &(not match?({:selection, _}, &1))) do
      {context, [{:selection, selection} | trailing]} ->
        materialise_selection(tempo, context, selection, trailing, opts)

      {_time, []} ->
        materialise_value(tempo)
    end
  end

  # An all-of `%Tempo.Set{}` (`{a,b,c}` syntax at the expression
  # level) is free/busy semantics — every member is materialised
  # and coalesced into an `IntervalSet`. A one-of set
  # (`[a,b,c]`) is an epistemic disjunction ("it was one of
  # these, I don't know which") and stays as a set; flattening it
  # to an IntervalSet would assert all members happened, which is
  # the opposite of what the user wrote.
  #
  # Exclusion members (`^x`, carried in `:except`) are subtracted
  # from the plain members — `{2020..2030, ^2026}` is the range
  # 2020–2030 with 2026 removed.
  defp materialise(%Tempo.Set{type: :all, set: members, except: [_ | _] = except}, opts) do
    with {:ok, included} <- members_to_interval_set(members),
         {:ok, excluded} <- members_to_interval_set(except) do
      difference(included, excluded, opts)
    end
  end

  defp materialise(%Tempo.Set{type: :all, set: members}, _opts) do
    members_to_interval_set(members)
  end

  defp materialise(%Tempo.Set{type: :one} = value, _opts) do
    {:error, ConversionError.exception(value: value, reason: :one_of_set)}
  end

  # A `%Tempo.Range{}` set member (`{2020Y..2030Y}`) is inclusive of both bounds,
  # so it materialises to every value from `first` to `last` at the range's own
  # resolution — a year range yields years, a month range months. An open-ended
  # range (`:undefined` endpoint) spans no finite set and cannot materialise.
  defp materialise(%Tempo.Range{first: %Tempo{} = first, last: %Tempo{} = last}, _opts) do
    {unit, _level} = resolution(first)

    first
    |> Stream.iterate(&shift(&1, [{unit, 1}]))
    |> Enum.take_while(fn value -> compare(value, last) != :gt end)
    |> members_to_interval_set()
  end

  defp materialise(%Tempo.Range{} = range, _opts) do
    {:error, ConversionError.exception(value: range, reason: :open_range)}
  end

  defp materialise(%Tempo.Duration{} = value, _opts) do
    {:error, ConversionError.exception(value: value, reason: :bare_duration)}
  end

  defp materialise(value, _opts) do
    {:error, ConversionError.exception(value: value, target: Tempo.Interval)}
  end

  # The start a window supplies takes the zone the rule's suffix names, unless
  # the window is in one of its own.
  defp in_rule_zone(%__MODULE__{extended: nil} = start, %Interval{
         repeat_rule: %__MODULE__{extended: %{} = extended}
       }),
       do: %{start | extended: extended}

  defp in_rule_zone(start, _interval), do: start

  # A recurrence with no end is ended by the caller's `:within` window; with
  # none it cannot be materialised. A window running back from each anchor
  # carries occurrences into the window from periods after it, so the walk goes
  # on to the last of those.
  defp materialise_unending(interval, nil, _opts),
    do: {:error, UnboundedRecurrenceError.exception(interval: interval)}

  defp materialise_unending(
         %Tempo.Interval{from: from, duration: duration} = interval,
         within,
         opts
       ) do
    with {:ok, window_to} <- bound_upper(within),
         {_forward, backward} = window_reach(interval),
         {:ok, walk_to} <- reach_end(window_to, interval, backward),
         {from, interval} = fill_selection_start(from, interval),
         {:ok, intervals} <-
           iterate_recurrence(
             from,
             duration,
             occurrence_end_fn(from, duration, interval),
             &under_bound?(&1, walk_to),
             selection_fn(interval, duration),
             interval.metadata
           ),
         {:ok, kept} <- keep_within(intervals, opts) do
      IntervalSet.new(kept, coalesce: coalesce_opt(opts))
    end
  end

  # The `:within` window supplies the recurrence's start, at the window's start.
  # The start is aligned to the start of the cadence period it sits in, so the
  # recurrence walks whole calendar periods — a `P1Y` cadence whole calendar
  # years, `P1M` whole months, `P1W` whole weeks from their Monday — and every
  # period the window overlaps is walked; the occurrences are then kept by
  # overlap with the window. Unaligned, a period boundary falls mid-period, and
  # the last period the window reaches into is never walked (`R/../P1Y/FL1M15DN` over September 2026 to March 2027 lost
  # 15 January 2027). When the selection resolves in another calendar — an IXDTF
  # `[u-ca=…]` suffix on the whole expression, carried on the `repeat_rule` —
  # the start is converted into that calendar first, so the periods are that
  # calendar's and the selection resolves in-calendar, with the window
  # intersection converting back. This makes `R/../P1Y/FL1M1DN[u-ca=persian]`
  # behave like the form with a calendared start, `R/<persian new year>/P1Y[u-ca=persian]`.
  defp start_in_repeat_calendar(
         %Tempo{} = start,
         %Tempo.Interval{
           repeat_rule: %Tempo{calendar: calendar},
           duration: %Tempo.Duration{} = cadence
         }
       )
       when calendar not in [nil, Calendrical.Gregorian, Calendrical.ISOWeek] do
    with {:ok, %Tempo{} = converted} <- to_calendar(start, calendar),
         %Tempo{} = aligned <- aligned_to_cadence(converted, cadence) do
      aligned
    else
      _other -> start
    end
  end

  defp start_in_repeat_calendar(%Tempo{} = start, %Tempo.Interval{
         duration: %Tempo.Duration{} = cadence
       }) do
    case aligned_to_cadence(start, cadence) do
      %Tempo{} = aligned -> aligned
      _other -> start
    end
  end

  defp start_in_repeat_calendar(%Tempo{} = start, _interval), do: start

  # The start of the cadence period a value sits in, at the value's own
  # resolution: 1 April 2026 for a month, 30 March 2026 (its week's Monday) for
  # a week holding 3 April.
  defp aligned_to_cadence(%Tempo{} = start, cadence) do
    with {unit, _span} <- resolution(start),
         %Tempo{} = period <- at_resolution(start, freq_of(cadence)) do
      at_resolution(period, unit)
    end
  end

  # A recurrence with an open start keeps the occurrences that overlap its
  # window, `[window_from, window_to)`. The periods it walks can place one
  # outside: a calendar-aligned recurrence walks whole calendar years, so the
  # year it starts in can begin before `window_from` or straddle `window_to`, and
  # in any calendar a period that starts inside the window can select a day at
  # or after its end (`R/../P1Y/FL9M23DN` over `[1 Sep, 23 Sep)` selects 23
  # September). Trim the materialised set to the window.
  defp filter_to_bound_window(
         {:ok, %Tempo.IntervalSet{}} = result,
         %Tempo.Interval{repeat_rule: %Tempo{}},
         within
       ) do
    case bound_upper(within) do
      {:ok, window_to} -> keep_occurrences_in_window(result, {bound_lower(within), window_to})
      _no_upper_edge -> result
    end
  end

  defp filter_to_bound_window(result, _interval, _within), do: result

  # Materialise a recurrence with an open start from its window's start. A
  # §12.10 window can move an occurrence off the period whose selection produced
  # it — a Saturday 1 January observed the previous Friday lands in the year
  # before, a Saturday 31 December observed the following Monday in the year
  # after — a week a year numbers can hold days of the year beside it, and an
  # occurrence's own span can run on past its period, so a
  # recurrence that reaches out of its periods walks from the first period
  # whose occurrences can reach the window, and keeps those that overlap it.
  defp materialise_from_bound(interval, start, within, opts) do
    case window_reach(interval) do
      {[], []} ->
        %{interval | from: start_in_repeat_calendar(start, interval)}
        |> to_interval(opts)
        |> filter_to_bound_window(interval, within)

      reach ->
        materialise_reaching(interval, start, reach, opts)
    end
  end

  # A window reaching back places a period's occurrence before the period
  # starts, and the walk keeps none that starts before the walk does, so the
  # walk starts that much earlier again. The walk's end reaches on in
  # `materialise_unending/3`.
  defp materialise_reaching(interval, start, {forward, backward}, opts) do
    with {:ok, %Tempo{} = reach_from} <- reach_start(start, interval, forward),
         %Tempo{} = carried_from <- carried(reach_from, backward, :back),
         %Tempo{} = walk_from <- at_start_resolution(carried_from, start, interval) do
      to_interval(%{interval | from: start_in_repeat_calendar(walk_from, interval)}, opts)
    end
  end

  # The walk's start at the resolution the start it reaches from has, so an
  # occurrence keeps the shape it has without a reach (a week selected from a
  # year is the week, not its days), unless that resolution cannot hold the
  # cadence's periods (a day, for an hourly cadence): then the carried start
  # stands as it is.
  defp at_start_resolution(carried_from, start, %Tempo.Interval{duration: cadence}) do
    {unit, _span} = resolution(start)

    if coarser_unit?(unit, freq_of(cadence)),
      do: carried_from,
      else: at_resolution(carried_from, unit)
  end

  # How far an occurrence can reach outside the period that selects it, as the
  # durations that carry it there, `{forward, backward}`: a §12.10 window
  # running on from its anchor or back from it, a nested window adding its own,
  # an occurrence's own span (`:occurrence_duration`) running on, as a
  # December–January school break does, and a week reaching past the period's
  # edges.
  defp window_reach(%Tempo.Interval{
         repeat_rule: %Tempo{time: [{:selection, selection} | _units]},
         duration: %Tempo.Duration{} = cadence,
         metadata: metadata
       }) do
    durations = window_durations(selection)
    {forward_weeks, backward_weeks} = week_reach(selection, cadence)

    {reaching(durations ++ spanned_durations(metadata), &(&1 > 0)) ++ forward_weeks,
     reaching(durations, &(&1 < 0)) ++ backward_weeks}
  end

  defp window_reach(_interval), do: {[], []}

  defp spanned_durations(%{occurrence_duration: %Tempo.Duration{} = span}), do: [span]
  defp spanned_durations(_metadata), do: []

  # The parts of each duration that run one way, as a duration of that way's
  # length: a window of `P-3D` reaches three days back.
  defp reaching(durations, direction?) do
    for %Tempo.Duration{time: time} <- durations,
        parts = for({unit, amount} <- time, direction?.(amount), do: {unit, abs(amount)}),
        parts != [],
        do: %Tempo.Duration{time: parts}
  end

  defp window_durations(selection) when is_list(selection) do
    Enum.flat_map(selection, fn
      {:interval, %Tempo.Interval{duration: %Tempo.Duration{} = duration, from: inner}} ->
        [duration | window_durations(window_inner_selection(inner))]

      _other ->
        []
    end)
  end

  defp window_inner_selection(%Tempo{time: [selection: selection]}), do: selection
  defp window_inner_selection(%Tempo{time: time}) when is_list(time), do: time
  defp window_inner_selection(_inner), do: []

  # A week reaches past the period it is selected in: a week a year numbers
  # (`W`, or the calendar's own `w`) can hold days of the year either side,
  # and a weekday in a weekly period comes from the week holding the period's
  # start, which can begin before it. Either lies within a week of the period.
  defp week_reach(selection, cadence) do
    week = %Tempo.Duration{time: [week: 1]}

    cond do
      selects_any?(selection, [:week, :calendar_week]) ->
        {[week], [week]}

      freq_of(cadence) == :week and selects_any?(selection, [:day_of_week, :byday]) ->
        {[], [week]}

      true ->
        {[], []}
    end
  end

  # Whether a selection, or a window's anchor in it, names one of `units`.
  defp selects_any?(selection, units) do
    Enum.any?(selection, fn
      {:interval, %Tempo.Interval{from: inner}} ->
        selects_any?(window_inner_selection(inner), units)

      {unit, _value} ->
        unit in units

      _other ->
        false
    end)
  end

  # The start of the first period whose occurrences can reach forward into a
  # window opening at `window_from`: back from the period holding the window's
  # start, whole cadences at a time so a multi-period cadence keeps its phase,
  # while the period ending there, carried on by the reach, still runs past the
  # window's start. Periods and reach are both stepped with the recurrence
  # calendar's own arithmetic, so a month is that calendar's month and a year
  # that calendar's year.
  defp reach_start(window_from, _interval, []), do: {:ok, window_from}

  defp reach_start(%Tempo{} = window_from, %Tempo.Interval{duration: cadence} = interval, forward) do
    with {:ok, first} <- period_holding(window_from, interval) do
      period_not_reaching(
        first,
        Duration.negate(cadence),
        &reaches_forward?(&1, forward, window_from)
      )
    end
  end

  defp reach_start(window_from, _interval, _forward), do: {:ok, window_from}

  # Where a walk that must meet every occurrence reaching back into a window
  # closing at `window_to` can stop: the start of the first period, on from the
  # one holding the window's end, whose occurrences cannot. A period's start,
  # carried back by the reach, falls at or after the window's end.
  defp reach_end(window_to, _interval, []), do: {:ok, window_to}

  defp reach_end(%Tempo{} = window_to, %Tempo.Interval{duration: cadence} = interval, backward) do
    with {:ok, last} <- period_holding(window_to, interval) do
      period_not_reaching(last, cadence, &reaches_back?(&1, backward, window_to))
    end
  end

  defp reach_end(window_to, _interval, _backward), do: {:ok, window_to}

  # The period `count` steps from `period` for the least `count` at which
  # `reaching?` no longer holds. The count doubles until it fails, then halves
  # back to the first that does, so a reach of many periods takes few steps.
  # Each period is `period + count × step`, so a month-end start never drifts.
  defp period_not_reaching(period, step, reaching?) do
    reached? = fn count -> reaching?.(add_n_durations(period, step, count)) end
    count = if reached?.(0), do: first_unreached(reached?, 0, 1), else: 0

    case add_n_durations(period, step, count) do
      %Tempo{} = unreached -> {:ok, unreached}
      error -> error
    end
  end

  # A reach past this many periods is a malformed rule, not a reason to search
  # for ever.
  @most_periods_reaching 1_048_576

  defp first_unreached(reached?, reached, count) do
    cond do
      count > @most_periods_reaching -> count
      reached?.(count) -> first_unreached(reached?, count, count * 2)
      true -> narrow_unreached(reached?, reached, count)
    end
  end

  defp narrow_unreached(_reached?, reached, unreached) when unreached - reached <= 1,
    do: unreached

  defp narrow_unreached(reached?, reached, unreached) do
    middle = div(reached + unreached, 2)

    if reached?.(middle),
      do: narrow_unreached(reached?, middle, unreached),
      else: narrow_unreached(reached?, reached, middle)
  end

  # Whether the period ending at `period_end` has occurrences that can run past
  # `window_from`: its anchors fall before `period_end`, and run on as far as
  # the reach carries them.
  defp reaches_forward?(period_end, forward, window_from) do
    case carried(period_end, forward, :on) do
      %Tempo{} = reach -> under_bound?(window_from, reach)
      _error -> false
    end
  end

  # Whether the period starting at `period_start` has occurrences that can
  # start before `window_to`: its anchors fall at or after `period_start`, and
  # start as far back as the reach carries them.
  defp reaches_back?(period_start, backward, window_to) do
    case carried(period_start, backward, :back) do
      %Tempo{} = reach -> under_bound?(reach, window_to)
      _error -> false
    end
  end

  # A value carried on or back by each duration in turn, with its calendar's
  # own arithmetic. A step the calendar cannot take is returned as it is.
  defp carried(%Tempo{} = value, durations, direction) do
    Enum.reduce_while(durations, value, fn duration, carried ->
      case Math.add(carried, oriented(duration, direction)) do
        %Tempo{} = next -> {:cont, next}
        other -> {:halt, other}
      end
    end)
  end

  defp carried(error, _durations, _direction), do: error

  defp oriented(duration, :on), do: duration
  defp oriented(duration, :back), do: Duration.negate(duration)

  # The start of the cadence period `edge` falls in, at the grain the
  # recurrence starts at and in the calendar it selects in.
  defp period_holding(edge, interval) do
    with {:ok, start} <- start_at_unit(edge, start_unit(interval)),
         do: {:ok, start_in_repeat_calendar(start, interval)}
  end

  # Apply a duration N times as a single scalar-multiplied step:
  # `tempo + (n × duration)` in one call, not `n` successive
  # `+ duration` calls.
  #
  # Scalar vs iterative matters when the start is a day the
  # calendar clamps. DTSTART = 2020-02-29 with cadence
  # `year: 1`:
  #
  # * Iterative (+1y then +1y then +1y then +1y): the first step
  #   clamps Feb 29 → Feb 28. Every subsequent step starts from
  #   Feb 28, so day 29 is lost forever.
  #
  # * Scalar (+4y in one shot): 2020-02-29 → 2024-02-29 (a leap
  #   year, valid).
  #
  # Matches the RFC intent: "DTSTART + i × INTERVAL" addresses a
  # specific point relative to DTSTART, not a walk.
  defp add_n_durations(tempo, _duration, 0), do: tempo

  defp add_n_durations(tempo, %Tempo.Duration{time: time}, n) when n > 0 do
    scaled = Enum.map(time, &scaled_amount(&1, n))
    Math.add(tempo, %Tempo.Duration{time: scaled})
  end

  # A fractional second's microseconds are a `{value, precision}` pair.
  defp scaled_amount({:microsecond, {value, precision}}, n),
    do: {:microsecond, {value * n, precision}}

  defp scaled_amount({unit, amount}, n), do: {unit, amount * n}

  ## ---------------------------------------------------------
  ## Recurrence-expansion helpers
  ##
  ## `iterate_recurrence/5` is the single stepwise expander used
  ## by both the UNTIL and :within clauses above. The only
  ## difference between the two is the termination predicate;
  ## factoring it out keeps the interpreter's loop authoritative
  ## and eliminates parallel engines in calling modules.
  ## ---------------------------------------------------------

  # Hard safety ceiling on how many occurrences any single
  # recurrence can materialise. Matches `Tempo.ICal.@safety_cap`.
  @recurrence_safety_cap 10_000

  # Coalescing is the default for back-compat with `to_interval/1`
  # semantics: an `R3/1985-01/P1M` interval is a single 3-month
  # span post-coalesce, which matches the documented contract.
  # Expansion consumers that care about event identity
  # (Tempo.ICal, the RRULE expander) pass `coalesce: false`.
  # Pre-semantic-flip this defaulted to `true`. As of v0.2 the
  # IntervalSet default is member-preserving (`coalesce: false`),
  # so this helper passes the caller's explicit opt through
  # unchanged and otherwise omits the option — letting
  # `IntervalSet.new/2` apply its own default.
  defp coalesce_opt(opts) do
    case Keyword.get(opts, :coalesce) do
      nil -> false
      value -> value
    end
  end

  # The stepwise expander. Shared by all three recurrence shapes:
  #
  # * `start_predicate` drives upstream termination — returns
  #   `true` while the candidate's start is still in-bounds
  #   (pre-filter), `false` once we're past UNTIL / the `:within` window's end.
  #
  # * `selection_fn` is the BY-rule resolver. It takes one
  #   candidate `%Interval{}` and returns a list (0 for LIMIT
  #   rejection, 1 for passthrough, N for EXPAND). Delegates to
  #   `Tempo.RRule.Selection.apply/3`.
  #
  # * `output_limit` is the downstream cap — `n` for a bounded
  #   recurrence, `@recurrence_safety_cap` otherwise. BY-rule
  #   filtering happens before this cap, so a COUNT of 3 with
  #   `BYMONTH=6` really means "first 3 June occurrences."
  #
  # The upstream `@recurrence_safety_cap` on the candidate stream
  # is a belt-and-braces guard against impossible BY-rule
  # combinations (e.g. `BYMONTHDAY=31` for months that never have
  # 31 days — the filter would reject every candidate forever).
  defp iterate_recurrence(
         %Tempo{} = from,
         %Tempo.Duration{} = cadence,
         occurrence_end,
         start_predicate,
         selection_fn,
         metadata,
         output_limit \\ @recurrence_safety_cap
       )
       when is_function(start_predicate, 1) and is_function(selection_fn, 1) do
    from
    |> period_occurrences(cadence, occurrence_end, start_predicate, selection_fn, metadata)
    |> from_the_start(from)
    |> Stream.take(output_limit)
    |> Enum.to_list()
    |> walked(from)
  end

  # The occurrences a walk gave. A step its cadence could not take ends the
  # walk as its last element, and is the walk's error: the second month after
  # `12M31D` is a 31 February, and an occurrence that would end there has no
  # end. A walk that has all the occurrences it was asked for before such a
  # step never meets it.
  defp walked(occurrences, from) do
    case List.last(occurrences) do
      {:error, reason} -> {:error, step_error(from, reason)}
      _occurrence -> {:ok, occurrences}
    end
  end

  # The occurrences of a recurrence written with a duration and an end, earliest
  # first: a count's, or an unending one's back to the start of its `:within`
  # window, without which it has no first occurrence.
  defp occurrences_back(to, back, count, _interval, metadata, _opts) when is_integer(count) do
    occurrences_back_to(to, back, metadata, 0, fn k, _occurrence -> k < count end, [])
  end

  defp occurrences_back(to, back, :infinity, interval, metadata, opts) do
    case Keyword.fetch(opts, :within) do
      {:ok, within} -> occurrences_back_within(to, back, bound_lower(within), metadata)
      :error -> {:error, UnboundedRecurrenceError.exception(interval: interval)}
    end
  end

  defp occurrences_back_within(_to, _back, nil, _metadata), do: {:error, empty_bound_error()}

  defp occurrences_back_within(to, back, %Tempo{} = window_from, metadata) do
    ends_in_window? = fn _k, %Tempo.Interval{to: stop} ->
      Compare.compare_endpoints(stop, window_from) == :later
    end

    occurrences_back_to(to, back, metadata, 0, ends_in_window?, [])
  end

  # Walks back from the end one occurrence at a time while `more?` holds for an
  # occurrence and its index, prepending each, so the list comes out earliest
  # first.
  defp occurrences_back_to(to, back, metadata, k, more?, occurrences)
       when k < @recurrence_safety_cap do
    case occurrence_back(to, back, k, metadata) do
      {:ok, occurrence} ->
        if more?.(k, occurrence),
          do: occurrences_back_to(to, back, metadata, k + 1, more?, [occurrence | occurrences]),
          else: {:ok, occurrences}

      {:error, _reason} = error ->
        error
    end
  end

  defp occurrences_back_to(_to, _back, _metadata, _k, _more?, occurrences),
    do: {:ok, occurrences}

  # The occurrence `k` cadences back from the end: it ends `k` durations before
  # the end and starts one duration earlier.
  defp occurrence_back(to, back, k, metadata) do
    case {add_n_durations(to, back, k + 1), add_n_durations(to, back, k)} do
      {%Tempo{} = start, %Tempo{} = stop} ->
        {:ok, %Tempo.Interval{from: start, to: stop, metadata: metadata}}

      {{:error, _reason} = error, _stop} ->
        error

      {_start, {:error, _reason} = error} ->
        error

      {start, _stop} ->
        {:error,
         ConversionError.exception(
           value: to,
           reason:
             "Stepping #{inspect(to)} back by #{inspect(back)} gives #{inspect(start)}, not one value."
         )}
    end
  end

  # Every occurrence the periods from `from` select, walking while a
  # period's start satisfies `start_predicate`.
  defp period_occurrences(from, cadence, occurrence_end, start_predicate, selection_fn, metadata) do
    from
    |> recurrence_candidates(cadence, occurrence_end, metadata)
    |> Stream.take_while(&walking?(&1, start_predicate))
    |> Stream.take(@recurrence_safety_cap)
    |> Stream.flat_map(&selected(&1, selection_fn))
    |> until_failure()
  end

  # A walk ends with its first failure: a step the cadence could not take, or
  # a selection that has no answer for a candidate (a computed event with no
  # date in its year). The failure is the walk's last element, which
  # `walked/2` returns as its error.
  defp until_failure(occurrences) do
    Stream.transform(occurrences, :walking, fn
      _occurrence, :failed -> {:halt, :failed}
      {:error, _reason} = failure, :walking -> {[failure], :failed}
      occurrence, :walking -> {[occurrence], :walking}
    end)
  end

  # A step the cadence could not take is the walk's last candidate, kept so
  # the walk can return it (`walked/2`).
  defp walking?({:error, _reason}, _start_predicate), do: true
  defp walking?({start, _candidate}, start_predicate), do: start_predicate.(start)

  defp selected({:error, _reason} = failure, _selection_fn), do: [failure]
  defp selected({_start, candidate}, selection_fn), do: selection_fn.(candidate)

  # Contiguous fast path: walk the starts once and pair each with the
  # next, so occurrence i's `to` is occurrence i+1's `from`. One
  # `Math.add` per occurrence instead of two.
  defp recurrence_candidates(from, cadence, :contiguous, metadata) do
    occurrence_metadata = strip_span_directives(metadata)

    Stream.unfold(from, &contiguous_candidate(&1, cadence, occurrence_metadata))
  end

  # General path: each start is `from + i × cadence` (scaled, so
  # month/year cadences don't clamp-drift) and the `to` comes from the
  # end function.
  defp recurrence_candidates(from, cadence, occurrence_end_fn, metadata)
       when is_function(occurrence_end_fn, 2) do
    occurrence_metadata = strip_span_directives(metadata)

    Stream.unfold(
      0,
      &stepped_candidate(&1, from, cadence, occurrence_end_fn, occurrence_metadata)
    )
  end

  # The candidate that starts at `start` and the start of the one after it,
  # which is where it ends. A step the cadence cannot take is the walk's last
  # candidate.
  defp contiguous_candidate(:stopped, _cadence, _metadata), do: nil

  defp contiguous_candidate(start, cadence, metadata) do
    case Math.add(start, cadence) do
      %Tempo{} = next_start ->
        {{start, %Tempo.Interval{from: start, to: next_start, metadata: metadata}}, next_start}

      failed ->
        {step_failure(failed), :stopped}
    end
  end

  defp stepped_candidate(:stopped, _from, _cadence, _occurrence_end_fn, _metadata), do: nil

  defp stepped_candidate(step, from, cadence, occurrence_end_fn, metadata) do
    with %Tempo{} = start <- add_n_durations(from, cadence, step),
         %Tempo{} = stop <- occurrence_end_fn.(start, step) do
      {{start, %Tempo.Interval{from: start, to: stop, metadata: metadata}}, step + 1}
    else
      failed -> {step_failure(failed), :stopped}
    end
  end

  # A start or an end the cadence could not be stepped to, as the candidate
  # that ends the walk. A value that holds unspecified digits steps to a set
  # of candidates, which is no one start either.
  defp step_failure({:error, _reason} = failure), do: failure
  defp step_failure(_several), do: {:error, :grouped_component}

  # `occurrence_duration` / `occurrence_base_to` are *directives* to
  # this materialiser — they say how to span each occurrence. Once the
  # span is fixed in `from`/`to` they've done their job, so they're
  # dropped from the emitted occurrences rather than riding along as
  # pseudo-semantic metadata (which would surface, e.g., in inspect).
  defp strip_span_directives(metadata) when is_map(metadata) do
    Map.drop(metadata, [:occurrence_duration, :occurrence_base_to])
  end

  defp strip_span_directives(metadata), do: metadata

  # DTSTART floor — per RFC 5545, DTSTART is always the first occurrence.
  # BY-rule EXPAND can legitimately produce dates earlier in the
  # DTSTART-containing period (e.g. BYMONTHDAY=1 with DTSTART=Sep 30 → also
  # Sep 1), and those are dropped. A start with no year lies on an axis that
  # comes round again — the hours of a day, the days of a week — so an
  # occurrence after it in the walk can be earlier on the axis
  # (`R3/T22H/PT1H` reaches 00:00): only those before the first occurrence
  # at or after the start are dropped.
  defp from_the_start(occurrences, %Tempo{time: time} = from) do
    if on_the_time_line?(time),
      do: Stream.reject(occurrences, &before_dtstart?(&1, from)),
      else: Stream.drop_while(occurrences, &before_dtstart?(&1, from))
  end

  defp before_dtstart?(%Tempo.Interval{from: %Tempo{} = candidate_from}, %Tempo{} = dtstart) do
    Compare.compare_endpoints(candidate_from, dtstart) == :earlier
  end

  # The step that ended a walk is not an occurrence to drop.
  defp before_dtstart?(_failure, _dtstart), do: false

  # Build the per-candidate selection filter/expand function. When
  # `repeat_rule` is nil, returns a passthrough (identity). When
  # non-nil, delegates to `Tempo.RRule.Selection.apply/3` with the
  # enclosing FREQ derived from the cadence's primary unit.
  defp selection_fn(%Tempo.Interval{repeat_rule: nil}, _cadence) do
    fn candidate -> [candidate] end
  end

  defp selection_fn(
         %Tempo.Interval{repeat_rule: %Tempo{} = rule, metadata: metadata} = interval,
         %Tempo.Duration{} = cadence
       ) do
    freq = freq_of(cadence)
    explicit_span? = explicit_occurrence_span?(metadata)
    resize? = not explicit_span? and Selection.expands?(rule, freq)
    origin_day = origin_day_of(interval)

    fn candidate ->
      case Selection.apply(candidate, rule, freq,
             origin_day: origin_day,
             keep_span: explicit_span?
           ) do
        {:error, _reason} = failure -> [failure]
        occurrences -> resize_selected_occurrences(occurrences, resize?)
      end
    end
  end

  # The day the recurrence started on — DTSTART's day-of-month —
  # which cadence stepping may have clamped away on individual
  # candidates (a start on 29 February steps to the 28th in common years).
  defp origin_day_of(%Tempo.Interval{from: %Tempo{time: time}}) do
    case Keyword.get(time, :day) do
      day when is_integer(day) -> day
      _other -> nil
    end
  end

  defp origin_day_of(_interval), do: nil

  # A selection that expands picks *points* at their own resolution —
  # "the 15th" is the day the 15th, not the month it sits in. The
  # candidate it expands spans a whole cadence period (so the resolver
  # can see the enclosing month/year), so each point inherits that
  # period as its span. Unless the recurrence carries an explicit event
  # span (a DTEND-style `occurrence_base_to` or `occurrence_duration`),
  # resize each point to one unit of its own resolution. A selection
  # that only limits keeps whole candidates, each spanning its cadence
  # as it would without the selection: the Monday hours of an hourly
  # recurrence are hours, and the January weeks of a weekly one weeks.
  # This keeps native `~o".../FL15DN"`, RRULE, and cron consistent
  # without storing any per-occurrence metadata.
  defp resize_selected_occurrences(occurrences, false) do
    Enum.map(occurrences, &drop_windowed_marker/1)
  end

  defp resize_selected_occurrences(occurrences, true) do
    Enum.map(occurrences, &resize_to_resolution/1)
  end

  defp drop_windowed_marker(%Tempo.Interval{metadata: %{windowed: _} = metadata} = occurrence) do
    %{occurrence | metadata: Map.delete(metadata, :windowed)}
  end

  defp drop_windowed_marker(occurrence), do: occurrence

  # A §12.10 window occurrence already carries its own span, so it is kept as
  # is; the internal marker that protected it from resizing is dropped here.
  defp resize_to_resolution(%Tempo.Interval{metadata: %{windowed: true} = metadata} = occurrence) do
    %{occurrence | metadata: Map.delete(metadata, :windowed)}
  end

  defp resize_to_resolution(%Tempo.Interval{from: %Tempo{} = from} = occurrence) do
    {unit, _value} = resolution(from)
    %{occurrence | to: Math.add(from, %Tempo.Duration{time: [{unit, 1}]})}
  end

  defp resize_to_resolution(occurrence), do: occurrence

  defp explicit_occurrence_span?(metadata) do
    match?(%{occurrence_base_to: %Tempo{}}, metadata) or
      match?(%{occurrence_duration: %Tempo.Duration{}}, metadata)
  end

  # The FREQ of a recurrence is the primary unit of its cadence —
  # e.g. `%Duration{time: [week: 1]}` → `:week`.
  defp freq_of(%Tempo.Duration{time: [{unit, _amount} | _]}), do: unit

  # Resolve a "given this iteration's start, what's the
  # occurrence's `to`?" function from the interval's metadata or
  # its AST fields. Priority order:
  #
  # 1. `metadata.occurrence_base_to` — an occurrence-0 `to` Tempo.
  #    Each occurrence's `to` is `base_to` shifted by `i × cadence`.
  #    This matches iCal semantics where DTEND − DTSTART defines
  #    the event span and every occurrence carries it forward.
  #
  # 2. `metadata.occurrence_duration` — an explicit Duration for
  #    each occurrence's span. Used when a caller knows the span
  #    as a Duration (hand-built AST, adapter layers).
  #
  # 3. The AST's `duration` — when no override is supplied, each
  #    occurrence spans one cadence, and ends where the next starts: ISO
  #    8601-1 §3.1.1.11 defines a recurring time interval as a series of
  #    consecutive time intervals. A month from 31 January is 28 February,
  #    and the occurrence from there runs to 31 March, where the third
  #    starts, not to the 28th a month on from its own start.
  defp occurrence_end_fn(
         %Tempo{} = from,
         %Tempo.Duration{} = cadence,
         %Tempo.Interval{metadata: metadata, duration: duration} = interval
       ) do
    cond do
      match?(%{occurrence_base_to: %Tempo{}}, metadata) ->
        base_to = metadata.occurrence_base_to
        fn _start, i -> add_n_durations(base_to, cadence, i) end

      match?(%{occurrence_duration: %Tempo.Duration{}}, metadata) ->
        span = metadata.occurrence_duration
        fn start, _i -> Math.add(start, span) end

      contiguous_occurrences?(cadence, interval) ->
        :contiguous

      consecutive_occurrences?(cadence, interval) ->
        fn _start, i -> add_n_durations(from, cadence, i + 1) end

      true ->
        fn start, _i -> Math.add(start, duration) end
    end
  end

  # A plain recurrence that runs forward, each occurrence one cadence long:
  # its occurrences are consecutive whatever the cadence's unit. One whose
  # unit has one length is `contiguous_occurrences?/2`'s, which reaches each
  # end by the step it takes anyway.
  defp consecutive_occurrences?(cadence, %Tempo.Interval{
         repeat_rule: nil,
         direction: direction,
         duration: cadence
       }),
       do: direction != -1

  defp consecutive_occurrences?(_cadence, _interval), do: false

  # A plain frequency recurrence (no BY-rules) whose cadence is a
  # fixed-length unit and that runs forward has *contiguous*
  # occurrences: each occurrence's `to` is exactly the next
  # occurrence's `from`. The loop can then reuse every computed start
  # as the previous occurrence's end — one `Math.add` per occurrence
  # rather than two. Excluded: month/year cadences (they clamp, so
  # `start + 2×month` ≠ `(start + month) + month`); backward
  # recurrences (the next start precedes this one); and BY-filtered
  # recurrences (selection resizes each occurrence anyway).
  defp contiguous_occurrences?(
         %Tempo.Duration{time: [{unit, _amount} | _]},
         %Tempo.Interval{repeat_rule: repeat_rule, direction: direction}
       ) do
    is_nil(repeat_rule) and direction != -1 and
      unit in [:week, :day, :hour, :minute, :second]
  end

  defp contiguous_occurrences?(_cadence, _interval), do: false

  # Termination predicates for the recurrence loop.
  defp under_until?(%Tempo{} = from, %Tempo{} = until) do
    Compare.compare_endpoints(from, until) in [:earlier, :same]
  end

  defp under_bound?(%Tempo{} = from, %Tempo{} = bound_to) do
    Compare.compare_endpoints(from, bound_to) == :earlier
  end

  defp starts_under_until?(%Tempo.Interval{from: %Tempo{} = from}, until),
    do: under_until?(from, until)

  defp starts_under_until?(_occurrence, _until), do: true

  defp at_or_after_bound?(%Tempo{} = from, %Tempo{} = bound_from) do
    Compare.compare_endpoints(from, bound_from) in [:same, :later]
  end

  # Compute the upper endpoint of a `:within` window. Accepts any
  # Tempo value that `to_interval_set/1` handles; uses the
  # highest `:to` across the set's intervals as the termination
  # boundary.
  defp bound_upper(bound) do
    case to_interval_set(bound) do
      {:ok, %Tempo.IntervalSet{} = set} -> bound_upper_from_set(set)
      {:error, _} = err -> err
    end
  end

  defp bound_upper_from_set(set) do
    if IntervalSet.empty?(set) do
      {:error,
       UnboundedRecurrenceError.exception(
         reason: "An empty `:within` window — nothing to end the recurrence against."
       )}
    else
      upper =
        set
        |> IntervalSet.members()
        |> Enum.map(& &1.to)
        |> Enum.reduce(&later_endpoint/2)

      {:ok, upper}
    end
  end

  # The lower endpoint of a `:within` window — the earliest `:from` across its
  # intervals. Used to drop occurrences that a calendar-aligned start places
  # before the window (a start at the beginning of the calendar year that
  # contains the window's start can precede the window itself). `nil` when the
  # bound is empty, so the window has no lower edge to enforce.
  defp bound_lower(bound) do
    case to_interval_set(bound) do
      {:ok, %Tempo.IntervalSet{} = set} -> bound_lower_from_set(set)
      {:error, _} -> nil
    end
  end

  defp bound_lower_from_set(set) do
    if IntervalSet.empty?(set) do
      nil
    else
      set
      |> IntervalSet.members()
      |> Enum.map(& &1.from)
      |> Enum.reduce(&earlier_endpoint/2)
    end
  end

  # The start for a recurrence with an open start, materialised in a `:within`
  # window: the window's lower endpoint, taken at the resolution the
  # recurrence's selection names — day for `FL6M1K2IN` ("the 2nd Monday
  # of June"), month for `FL6MN` ("June"), hour for a time-of-day rule.
  # Starting at that grain (rather than always a day) is what lets a
  # coarse selection yield a coarse occurrence; the window already says
  # where it starts, so a separate start option would be redundant.
  defp window_start(bound, %Tempo.Interval{} = interval) do
    case to_interval_set(bound) do
      {:ok, %Tempo.IntervalSet{} = set} -> window_start_from_set(set, start_unit(interval))
      {:error, _} = err -> err
    end
  end

  # A written start coarser than the grain its selection names —
  # `R/2020Y/P4Y/FL11M3DN`, a year starting a day selection — is filled down to
  # that grain (2020-01-01) before the recurrence walks from it, as the window
  # start of a recurrence with an open start is; otherwise the selection would
  # expand days within a year that names no month. A start at or finer than the
  # grain is left exactly as written.
  defp fill_selection_start(
         %Tempo{} = from,
         %Tempo.Interval{repeat_rule: %Tempo{time: [{:selection, [_ | _]} | _units]}} = interval
       ) do
    unit = start_unit(interval)

    with {from_unit, _span} <- resolution(from),
         true <- coarser_unit?(from_unit, unit),
         {:ok, %Tempo{} = filled} <- start_at_unit(from, unit) do
      {filled, %{interval | from: filled}}
    else
      _other -> {from, interval}
    end
  end

  defp fill_selection_start(from, interval), do: {from, interval}

  defp coarser_unit?(unit_1, unit_2) do
    case {Unit.fetch_sort_key(unit_1), Unit.fetch_sort_key(unit_2)} do
      {{:ok, key_1}, {:ok, key_2}} -> key_1 > key_2
      _unknown -> false
    end
  end

  defp window_start_from_set(set, unit) do
    case IntervalSet.first(set) do
      %Tempo.Interval{from: %Tempo{} = from} -> start_at_unit(from, unit)
      _ -> {:error, empty_bound_error()}
    end
  end

  defp start_at_unit(%Tempo{} = from, :day) do
    case at_resolution(from, :day) do
      %Tempo{} = start -> {:ok, start}
      {:error, _} = error -> error
    end
  end

  # A selection whose resolution the bound's start cannot reach — a week
  # selection over a year value, where the ISO-week axis has no path from
  # the calendar axis — falls back to the day floor rather than failing.
  # Day is reachable from every value, so the recurrence still
  # materialises (at day grain) instead of erroring.
  defp start_at_unit(%Tempo{} = from, unit) do
    case at_resolution(from, unit) do
      %Tempo{} = start -> {:ok, start}
      {:error, _} -> start_at_unit(from, :day)
    end
  end

  # The grain a recurrence starts at: the finest unit its selection
  # names, mapped onto the calendar axis (a weekday or ordinal selects a
  # *day*, and a §12.10 window ending the selection runs from a day). With
  # no selection, the day floor keeps a plain cadence (`R/../P1D`) walking
  # days.
  defp start_unit(%Tempo.Interval{repeat_rule: %Tempo{time: [{:selection, selection} | _units]}})
       when selection != [] do
    # The finest unit is the last selection component (they are written
    # coarse-to-fine), the week start (`q`) aside: it is context, not a unit.
    # Read it straight from the AST rather than through `resolution/1`, whose
    # declared `time_unit()` return elides the selection-only keys (`:byday`,
    # `:day_of_week`) this must normalise.
    case selection |> Enum.reject(&match?({:wkst, _day}, &1)) |> List.last() do
      {finest_unit, _value} -> calendar_start_unit(finest_unit)
      nil -> :day
    end
  end

  defp start_unit(%Tempo.Interval{}), do: :day

  # A week-of-year selection starts from its enclosing year (a dayless
  # year value), not the week axis: `at_resolution/2` has no path from a
  # calendar year to a week, and the week expander builds the week from
  # the candidate's year. The dayless start is also what marks the
  # selection as native (a whole week), distinct from RRULE `BYWEEKNO`,
  # whose `DTSTART` day expands the week to its seven days.
  defp calendar_start_unit(week) when week in [:week, :calendar_week], do: :year

  defp calendar_start_unit(unit)
       when unit in [:byday, :day_of_week, :day_of_year, :instance, :event, :interval],
       do: :day

  defp calendar_start_unit(unit), do: unit

  defp empty_bound_error do
    UnboundedRecurrenceError.exception(
      reason: "An empty `:within` window — nothing to start the recurrence from."
    )
  end

  defp later_endpoint(a, b) do
    if Compare.compare_endpoints(a, b) == :later, do: a, else: b
  end

  defp earlier_endpoint(a, b) do
    if Compare.compare_endpoints(a, b) == :earlier, do: a, else: b
  end

  # A mask narrows to the values its digits allow (`Mask.valid_values/4`, which
  # asks the calendar how many months, days and weeks there are). One followed
  # by something that narrows further — a concrete unit, a set, a group or a
  # partly masked unit (`1985-XX-15`, `2026-XX-1X`) — names disjoint spans, so
  # it is replaced by its candidate values and expanded member by member. A
  # partly masked unit with nothing that narrows after it is the span from its
  # first candidate to its last (`2026-06-1X`, 10 to 19 June), or its candidates
  # when they are not consecutive (`2026-06-X5`, the 5th, 15th and 25th). A
  # fully masked unit with nothing that narrows after it (`1985-XX-XX`) widens
  # to the units before it, which is exactly its span, as a year mask is the
  # span its digits allow (`202X`, the 2020s).
  defp expand_non_contiguous_mask(%Tempo{time: time, calendar: calendar} = tempo) do
    case find_non_contiguous_mask(time, [], calendar) do
      nil -> {:ok, tempo}
      {new_time} -> {:ok, %{tempo | time: new_time}}
      {:span, first, last} -> {:span, %{tempo | time: first}, %{tempo | time: last}}
      {:members, times} -> {:members, Enum.map(times, &%{tempo | time: &1})}
      {:error, reason} -> {:error, Mask.error(tempo, reason)}
    end
  end

  defp find_non_contiguous_mask([], _previous, _calendar), do: nil

  defp find_non_contiguous_mask([{unit, {:mask, mask}} = entry | rest], previous, calendar),
    do: narrowed_mask(entry, unit, mask, Enum.reverse(previous), rest, calendar)

  # An unspecified unit other than the year (`X*D`, any day) is every value
  # the unit takes, as one with every digit masked is (`XXD`).
  defp find_non_contiguous_mask([{unit, :any} = entry | rest], previous, calendar)
       when unit != :year,
       do: narrowed_mask(entry, unit, :any, Enum.reverse(previous), rest, calendar)

  defp find_non_contiguous_mask([entry | rest], previous, calendar) do
    find_non_contiguous_mask(rest, [entry | previous], calendar)
  end

  defp narrowed_mask(entry, unit, mask, prefix, rest, calendar) do
    if tail_narrows?(rest, prefix ++ [entry]) or every_week_follows?(rest, calendar),
      do: mask_before_narrower(unit, mask, prefix, rest, calendar),
      else: mask_alone(unit, mask, prefix, calendar)
  end

  # Every week of a year is not the year (`spans_its_values?/4`), so a mask
  # of all the weeks after a masked year (`202XYXXW`) narrows it: the weeks
  # of each year, where any other unit masked whole widens to the years.
  defp every_week_follows?([{:week, week} | _rest], calendar) when week == :any or is_tuple(week),
    do: calendar.calendar_base() != :week

  defp every_week_follows?(_rest, _calendar), do: false

  # A mask with something after it that narrows: its candidates are values of
  # their own when a later mask narrows within each, and otherwise replace it.
  defp mask_before_narrower(unit, mask, prefix, rest, calendar) do
    if tail_masked?(rest),
      do: mask_members(unit, mask, prefix, rest, calendar),
      else: substitute_mask(unit, mask, prefix, rest, calendar)
  end

  # A mask with nothing after it that narrows is the span of its values when
  # they are fewer than the unit's, and otherwise is left to widen to the
  # units before it.
  defp mask_alone(unit, mask, prefix, calendar) do
    if spans_its_values?(unit, mask, prefix, calendar),
      do: narrow_mask(unit, mask, prefix, calendar),
      else: nil
  end

  defp spans_its_values?(:year, _mask, _prefix, _calendar), do: false

  # Every week of a year is not the year: ISO 8601's weeks of 2026 run from
  # 29 December 2025 to 3 January 2027. So a mask of all of them is the span
  # from the first week to the last, where any other unit's is the span of the
  # units before it. In a calendar of weeks the two are one.
  defp spans_its_values?(:week, mask, prefix, calendar) do
    narrowing_mask?(:week, mask, prefix) or
      (prefix != [] and calendar.calendar_base() != :week)
  end

  # Every day of a month is not the month in a year that does not begin with
  # its first month: a date's month is the month it names, and the month the
  # calendar counts from the year's start is another span. So a mask of all
  # of a month's days there is the span from its first day to its last.
  defp spans_its_values?(:day, mask, [{:year, year}, {:month, month}] = prefix, calendar)
       when is_integer(year) and is_integer(month) do
    narrowing_mask?(:day, mask, prefix) or
      not UnitValues.year_begins_with_first_month?(year, calendar)
  end

  defp spans_its_values?(unit, mask, prefix, _calendar), do: narrowing_mask?(unit, mask, prefix)

  # The values a masked unit takes after the units before it: those the walk
  # of the value yields (`Tempo.Mask.candidates/4`), so a conversion and a
  # walk cannot read a mask two ways. An unspecified unit takes all the unit
  # has there.
  defp masked_values(unit, :any, prefix, calendar) do
    with {:ok, range} <- Mask.unspecified(unit, prefix, calendar) do
      {:ok, Enum.to_list(range)}
    end
  end

  defp masked_values(unit, mask, prefix, calendar),
    do: Mask.candidates(unit, mask, prefix, calendar)

  # Whether a mask allows fewer values than its unit takes: some digit of it
  # is given (`1X`), it counts from the end (`-X`, the last nine), or it has
  # fewer digits than the unit's values do (`XM` is months 1 to 9). One that
  # allows them all is the span of the units before it.
  defp narrowing_mask?(_unit, :any, _before), do: false
  defp narrowing_mask?(_unit, [:negative | _digits], _before), do: true

  defp narrowing_mask?(unit, mask, before),
    do: partial_mask?(mask) or length(mask) < unit_digits(unit, before)

  # The digits of the greatest value a unit takes, in any calendar: a day of
  # the year, or a day written straight after its year, has three.
  defp unit_digits(:day_of_week, _before), do: 1
  defp unit_digits(:day_of_year, _before), do: 3
  defp unit_digits(:day, before), do: if(List.keymember?(before, :month, 0), do: 2, else: 3)
  defp unit_digits(_unit, _before), do: 2

  # Use a scalar when exactly one candidate survives the calendar
  # constraint; otherwise a list, which the multi path expands via
  # `Enumerable`.
  defp substitute_mask(unit, mask, prefix, rest, calendar) do
    case masked_values(unit, mask, prefix, calendar) do
      {:ok, []} -> {:error, {:no_candidates, unit}}
      {:ok, [single]} -> {prefix ++ [{unit, single}] ++ rest}
      {:ok, many} -> {prefix ++ [{unit, many}] ++ rest}
      {:error, _reason} = error -> error
    end
  end

  # A mask with a mask after it that narrows: each candidate is a value of its
  # own, so the later mask narrows within it rather than being walked value by
  # value (`2026-XX-1X` is twelve spans of ten days, not 120 days).
  defp mask_members(unit, mask, prefix, rest, calendar) do
    case masked_values(unit, mask, prefix, calendar) do
      {:ok, []} -> {:error, {:no_candidates, unit}}
      {:ok, values} -> {:members, Enum.map(values, &(prefix ++ [{unit, &1}] ++ rest))}
      {:error, _reason} = error -> error
    end
  end

  defp tail_masked?(rest), do: Enum.any?(rest, &masked?/1)

  # A unit some or all of whose digits are masked, which an unspecified unit
  # other than the year is.
  defp masked?({_unit, {:mask, _mask}}), do: true
  defp masked?({unit, :any}), do: unit != :year
  defp masked?(_component), do: false

  # A partly masked unit with nothing that narrows after it. Anything after it
  # is fully masked and widens, so it is dropped.
  defp narrow_mask(unit, mask, prefix, calendar) do
    case masked_values(unit, mask, prefix, calendar) do
      {:ok, []} ->
        {:error, {:no_candidates, unit}}

      {:ok, [single]} ->
        {prefix ++ [{unit, single}]}

      {:ok, [first | _] = values} ->
        consecutive_or_scattered(unit, first, values, prefix, calendar)

      {:error, _reason} = error ->
        error
    end
  end

  defp consecutive_or_scattered(unit, first, values, prefix, calendar) do
    last = List.last(values)

    if last - first + 1 == length(values) and one_run?(unit, first, last, prefix, calendar),
      do: {:span, prefix ++ [{unit, first}], prefix ++ [{unit, last}]},
      else: {prefix ++ [{unit, values}]}
  end

  # Values that follow one another in number follow one another in time,
  # but for the days of a month that a year turns within: 24 March is the
  # last day of a `Calendrical.Julian.March25` year and 25 March its first.
  defp one_run?(:day, first, last, [{:year, year}, {:month, month}], calendar)
       when is_integer(year) and is_integer(month) do
    UnitValues.year_begins_with_first_month?(year, calendar) or
      days_between(year, month, first, last, calendar) == last - first
  end

  defp one_run?(_unit, _first, _last, _prefix, _calendar), do: true

  defp days_between(year, month, first, last, calendar) do
    with {:ok, from} <- Date.new(year, month, first, calendar),
         {:ok, to} <- Date.new(year, month, last, calendar) do
      Date.diff(to, from)
    end
  end

  # A mask some of whose digits are given (`1X`, `X5`, `XXX{0,2,4,6,8}`).
  defp partial_mask?(mask), do: Enum.any?(mask, &(is_integer(&1) or is_list(&1)))

  # Whether anything after a mask narrows its span further. `before` is the
  # units before the one looked at, which say how many digits a day has.
  defp tail_narrows?([], _before), do: false
  defp tail_narrows?([{_unit, value} | _rest], _before) when is_integer(value), do: true
  defp tail_narrows?([{_unit, values} | _rest], _before) when is_list(values), do: true
  defp tail_narrows?([{_unit, {:group, _range}} | _rest], _before), do: true

  defp tail_narrows?([{_unit, {value, meta}} | _rest], _before)
       when is_integer(value) and is_list(meta),
       do: true

  defp tail_narrows?([{unit, {:mask, mask}} = entry | rest], before),
    do: narrowing_mask?(unit, mask, before) or tail_narrows?(rest, before ++ [entry])

  defp tail_narrows?([entry | rest], before), do: tail_narrows?(rest, before ++ [entry])

  # A Tempo is "multi" if any of its time slots holds a list of
  # more than one candidate value. The existing Enumerable
  # protocol handles the expansion — we just detect the trigger
  # here and let Enumerable do the walk.
  defp multi_tempo?(%Tempo{time: time}) do
    Enum.any?(time, &multi_slot?/1)
  end

  defp multi_slot?({_unit, value}) when is_integer(value), do: false
  defp multi_slot?({_unit, {:mask, _}}), do: false
  defp multi_slot?({_unit, :any}), do: false
  defp multi_slot?({_unit, {_value, meta}}) when is_list(meta), do: false

  defp multi_slot?({_unit, values}) when is_list(values) do
    case values do
      [] ->
        false

      # A count-from-the-end bound that survived parsing could not be
      # resolved there — a coarser component is itself set-valued, so
      # this unit's extent is not yet known. Counting it now would
      # read the inverted range as empty and send a value that needs
      # expansion down the single-interval path, where the unresolved
      # bound reaches calendar arithmetic. Expansion resolves it
      # against each concrete context instead.
      [%Range{first: first, last: last}] when first < 0 or last < 0 ->
        true

      [%Range{first: first, last: last, step: step}] ->
        Enum.count(first..last//step) > 1

      [_single] ->
        false

      _ ->
        true
    end
  end

  defp multi_slot?(_), do: false

  defp materialise_multi(%Tempo{} = tempo) do
    # The existing Enumerable.Tempo yields one concrete Tempo per
    # cartesian-product combination. Each of those is a single
    # Tempo we can pass through the single-interval path. Collect
    # the intervals, then build a coalesced IntervalSet.
    #
    # A negative component under a set-valued container
    # (`2026Y{1..12}M-1D`) cannot resolve at parse time — there is
    # no single month for `-1D` to count back from — so it survives
    # into the members. Each member's context is concrete now:
    # re-validate, which resolves the negative against that member's
    # own month or year (leap-aware, per ISO 8601-2 §4.4.1), exactly
    # as a scalar literal resolves at parse.
    with {:ok, members} <- expand_members(tempo) do
      materialise_members(members)
    end
  end

  defp materialise_members(members) do
    members
    |> Enum.map(&member_interval/1)
    |> gather_members()
  end

  # Members expanded from a mask, or from a set before one, are kept only when
  # they hold a date, as a set drops the values its context cannot hold
  # (`2026-XX-3X` has no February). When none does, the value names no date.
  defp materialise_mask_members(members) do
    results = Enum.map(members, &member_interval/1)

    case Enum.reject(results, &match?({:error, %InvalidDateError{}}, &1)) do
      [] when results != [] -> hd(results)
      kept -> gather_members(kept)
    end
  end

  defp member_interval(member) do
    case normalise_member(member) do
      {:ok, %Tempo{} = resolved} -> to_interval(resolved)
      {:error, _} = err -> err
    end
  end

  # A member that still holds a mask (`2026-01-1X` from `2026-XX-1X`) may be a
  # span or several, so the members' intervals are gathered into one set.
  defp gather_members(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> results |> Enum.flat_map(&member_intervals/1) |> IntervalSet.new()
      {:error, _} = err -> err
    end
  end

  defp member_intervals({:ok, %IntervalSet{} = set}), do: IntervalSet.members(set)
  defp member_intervals({:ok, %Tempo.Interval{} = interval}), do: [interval]

  # The members are the values the walk of `Tempo.Enumeration` names: each
  # component resolves against its already-concrete coarser units, so nested
  # open ranges (`{2000..2010}Y{1..-1}M{1..-1}D`) terminate, and a value that
  # cannot be walked is an error here rather than a raise.
  defp expand_members(%Tempo{} = tempo), do: Enumeration.members(tempo)

  # An expanded member is a raw combination of component values, in
  # whatever axis the source value used. The parser normalises such a
  # value on its way in — a week-and-weekday becomes a calendar date,
  # an ordinal day becomes a month and day — and `to_interval/1`
  # expects that normalised form, so each member takes the same route
  # through the validator. It also resolves any count-from-the-end
  # component against the member's now-concrete context.
  # The member's *own* calendar decides what its components mean —
  # validating a Hebrew member against the default Gregorian calendar
  # would reject its thirteenth month.
  defp normalise_member(%Tempo{calendar: calendar} = member) when not is_nil(calendar) do
    Validation.validate(member, calendar)
  end

  defp normalise_member(%Tempo{} = member) do
    Validation.validate(member)
  end

  defp members_to_interval_set(members) do
    intervals =
      Enum.reduce_while(members, {:ok, []}, fn member, {:ok, acc} ->
        case to_interval(member) do
          {:ok, %Tempo.Interval{} = i} ->
            {:cont, {:ok, [i | acc]}}

          {:ok, %Tempo.IntervalSet{} = inner_set} ->
            {:cont, {:ok, Enum.reverse(IntervalSet.members(inner_set)) ++ acc}}

          {:error, _} = err ->
            {:halt, err}
        end
      end)

    case intervals do
      {:ok, reversed} ->
        reversed |> Enum.reverse() |> IntervalSet.new()

      {:error, _} = err ->
        err
    end
  end

  # Materialise a recurrence's selection over its domain's periods (each an
  # interval from the domain set), unioning the occurrences. Adjacent domain
  # periods — each starting where the one before ends, as the years of
  # `{2020Y..2024Y}` do — run as one recurrence across them.
  defp reduce_domain_occurrences(domain_intervals, %Tempo.Interval{} = interval, opts) do
    domain_intervals
    |> adjacent_periods()
    |> Enum.reduce_while({:ok, []}, fn {first, last}, {:ok, acc} ->
      case run_occurrences(interval, Interval.from(first), Interval.to(last), opts) do
        {:ok, own} -> {:cont, {:ok, acc ++ own}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, intervals} -> IntervalSet.new(intervals)
      {:error, _} = err -> err
    end
  end

  # The occurrences a run's periods select. In the calendar the domain counts
  # its years in, the run's periods are the recurrence's own: a walk from the
  # period the run starts in, at the grain the recurrence starts at, while a
  # period starts before the run ends, keeps all they give, wherever a §12.10
  # window, a week or an occurrence's span carries them. A recurrence in
  # another calendar has periods that straddle the domain's years, which gate
  # it instead: it keeps the occurrences that start in the run.
  defp run_occurrences(%Tempo.Interval{} = interval, run_from, run_to, opts) do
    with {:ok, %Tempo{calendar: run_calendar} = start} <-
           start_at_unit(run_from, start_unit(interval)) do
      case start_in_repeat_calendar(start, interval) do
        %Tempo{calendar: ^run_calendar} = first_period ->
          walk_run(first_period, interval, run_to)

        _other_calendar ->
          gated_run_occurrences(interval, run_from, run_to, opts)
      end
    end
  end

  defp walk_run(first_period, %Tempo.Interval{duration: cadence} = interval, run_to) do
    {from, interval} = fill_selection_start(first_period, %{interval | from: first_period})

    from
    |> period_occurrences(
      cadence,
      occurrence_end_fn(from, cadence, interval),
      &under_bound?(&1, run_to),
      selection_fn(interval, cadence),
      interval.metadata
    )
    |> Enum.to_list()
    |> walked(from)
  end

  defp gated_run_occurrences(interval, run_from, run_to, opts) do
    run = %Tempo.Interval{from: run_from, to: run_to}
    open_start = %{interval | from: nil, recurrence: :infinity}

    case to_interval(open_start, Keyword.put(opts, :within, run)) do
      {:ok, %Tempo.IntervalSet{} = set} ->
        {:ok, set |> IntervalSet.members() |> Enum.filter(&starts_in_run?(&1, run_from, run_to))}

      {:error, _reason} = error ->
        error
    end
  end

  # Whether an occurrence starts in the half-open run `[run_from, run_to)`.
  defp starts_in_run?(%Tempo.Interval{from: %Tempo{} = from}, run_from, run_to),
    do: at_or_after_bound?(from, run_from) and under_bound?(from, run_to)

  defp starts_in_run?(_occurrence, _run_from, _run_to), do: true

  # A counted recurrence (`R3/{…}/…`) counts its occurrences from the
  # domain's first period, so it walks them all; any other walks the periods
  # whose occurrences can reach the window.
  defp domain_periods_to_walk(periods, %Tempo.Interval{recurrence: count}, _reach)
       when is_integer(count),
       do: periods

  defp domain_periods_to_walk(periods, _interval, reach),
    do: Enum.filter(periods, &domain_period_in_window?(&1, reach))

  # A counted recurrence keeps its domain's first occurrences, as one from a
  # start keeps its first.
  defp first_occurrences({:ok, %Tempo.IntervalSet{} = set}, %Tempo.Interval{recurrence: count})
       when is_integer(count),
       do: set |> IntervalSet.members() |> Enum.take(count) |> IntervalSet.new()

  defp first_occurrences(result, _interval), do: result

  # The runs of periods each starting where the one before ends, as
  # `{first_period, last_period}` pairs in order.
  defp adjacent_periods([]), do: []

  defp adjacent_periods([first | rest]) do
    {runs, run} =
      Enum.reduce(rest, {[], {first, first}}, fn period, {runs, {run_first, run_last}} ->
        if adjacent_period?(run_last, period),
          do: {runs, {run_first, period}},
          else: {[{run_first, run_last} | runs], {period, period}}
      end)

    Enum.reverse([run | runs])
  end

  defp adjacent_period?(%Tempo.Interval{to: %Tempo{} = previous_to}, %Tempo.Interval{
         from: %Tempo{} = next_from
       }) do
    Compare.compare_endpoints(previous_to, next_from) == :same
  end

  defp adjacent_period?(_previous, _next), do: false

  # A caller's `:within` as a half-open `{window_from, window_to}` start window,
  # or `:none` when no window is given (a domain, a count or an UNTIL then
  # bounds the recurrence alone). An open-ended window has no `window_to`.
  defp within_window(opts) do
    case Keyword.fetch(opts, :within) do
      {:ok, within} -> window_edges(within)
      :error -> {:ok, :none}
    end
  end

  # An open-ended window's start and no end, or the earliest start and the
  # latest end of what any other window materialises to.
  defp window_edges(within) do
    case open_window_start(within) do
      {:ok, window_from} ->
        {:ok, {window_from, nil}}

      {:error, _reason} = error ->
        error

      :bounded ->
        with {:ok, window_to} <- bound_upper(within) do
          {:ok, {bound_lower(within), window_to}}
        end
    end
  end

  # One rule for every recurrence: the occurrences kept are those that overlap
  # the caller's window, `[from, to)` — one already in progress when the window
  # opens, and one that runs past its end. No window keeps them all.
  defp keep_within(occurrences, opts) do
    with {:ok, window} <- within_window(opts) do
      {:ok, occurrences_in_window(occurrences, window)}
    end
  end

  defp occurrences_in_window(occurrences, :none), do: occurrences

  defp occurrences_in_window(occurrences, {window_from, window_to}) do
    Enum.filter(occurrences, &overlaps_window?(&1, window_from, window_to))
  end

  # A domain period is materialised when an occurrence it yields can overlap
  # the window: the periods the window overlaps, and those either side whose
  # occurrences can reach it (a December–January break yielded by 2025
  # overlaps a window in January 2026). The rest are skipped.
  defp domain_period_in_window?(_period, :none), do: true

  defp domain_period_in_window?(%Tempo.Interval{} = period, {window_from, window_to}),
    do: overlaps_window?(period, window_from, window_to)

  defp domain_reach_window(:none, _interval), do: {:ok, :none}

  defp domain_reach_window({window_from, window_to}, %Tempo.Interval{} = interval) do
    {forward, backward} = window_reach(interval)

    with {:ok, reach_from} <- reach_start(window_from, interval, forward),
         {:ok, reach_to} <- reach_end(window_to, interval, backward),
         do: {:ok, {reach_from, reach_to}}
  end

  defp keep_occurrences_in_window(result, :none), do: result

  defp keep_occurrences_in_window({:ok, %Tempo.IntervalSet{} = set}, window) do
    set
    |> IntervalSet.members()
    |> occurrences_in_window(window)
    |> IntervalSet.new()
  end

  defp keep_occurrences_in_window({:error, _} = error, _window), do: error

  # An occurrence overlaps the window `[window_from, window_to)` when it starts
  # before the window's end and ends after its start — so one that only touches
  # an edge does not. A nil `window_from` (an empty window) enforces only the
  # upper edge, and a nil `window_to` (an open-ended window) only the lower.
  defp overlaps_window?(
         %Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to},
         window_from,
         window_to
       ),
       do: starts_before?(from, window_to) and ends_after?(to, window_from)

  defp overlaps_window?(_occurrence, _window_from, _window_to), do: true

  defp starts_before?(_from, nil), do: true
  defp starts_before?(from, window_to), do: under_bound?(from, window_to)

  defp ends_after?(_to, nil), do: true
  defp ends_after?(to, window_from), do: under_bound?(window_from, to)

  # Close an open-ended domain range against the bound's window: a missing upper
  # end becomes the bound's end and a missing lower end the bound's start, each
  # truncated to the range's own resolution (the window filter then drops any
  # period the bound only touches). With no bound an open range stays open, and
  # materialising it reports the open range.
  defp close_domain_ranges(domain, :none), do: {:ok, domain}

  defp close_domain_ranges(%Tempo.Set{set: members} = domain, {bound_from, bound_to}) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case close_domain_range(member, bound_from, bound_to) do
        {:ok, closed} -> {:cont, {:ok, [closed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, closed} -> {:ok, %{domain | set: Enum.reverse(closed)}}
      {:error, _} = error -> error
    end
  end

  defp close_domain_range(
         %Tempo.Range{first: %Tempo{} = first, last: :undefined} = range,
         _bound_from,
         %Tempo{} = bound_to
       ) do
    with %Tempo{} = last <- trunc_to_resolution_of(bound_to, first) do
      {:ok, %{range | last: last}}
    end
  end

  defp close_domain_range(
         %Tempo.Range{first: :undefined, last: %Tempo{} = last} = range,
         %Tempo{} = bound_from,
         _bound_to
       ) do
    with %Tempo{} = first <- trunc_to_resolution_of(bound_from, last) do
      {:ok, %{range | first: first}}
    end
  end

  defp close_domain_range(member, _bound_from, _bound_to), do: {:ok, member}

  defp trunc_to_resolution_of(value, like) do
    {unit, _level} = resolution(like)
    trunc(value, unit)
  end

  # A cadence longer than one period — `R/{1848Y..}/P4Y/…`, "every four years
  # since 1848" — keeps every nth domain period, counted from the domain's first
  # stated value, as RRULE's INTERVAL steps from DTSTART. The cadence unit must be
  # the periods' own (years stepping years, months stepping months); a
  # one-period cadence keeps every period.
  defp step_domain_periods([], _domain, _duration), do: []

  defp step_domain_periods(
         [first_period | _rest] = periods,
         domain,
         %Tempo.Duration{time: [{unit, step}]}
       )
       when unit in [:year, :month] and is_integer(step) and step > 1 do
    with {^unit, _level} <- resolution(Interval.from(first_period)),
         %Tempo{} = phase <- domain_phase(domain) do
      origin = cadence_index(phase, unit)

      Enum.filter(periods, fn period ->
        Integer.mod(cadence_index(Interval.from(period), unit) - origin, step) == 0
      end)
    else
      _other -> periods
    end
  end

  defp step_domain_periods(periods, _domain, _duration), do: periods

  # The domain's earliest stated value — the origin its cadence counts from.
  defp domain_phase(%Tempo.Set{set: members}) do
    members
    |> Enum.flat_map(&stated_domain_values/1)
    |> Enum.reduce(nil, fn
      value, nil -> value
      value, earliest -> earlier_endpoint(value, earliest)
    end)
  end

  defp stated_domain_values(%Tempo{} = value), do: [value]
  defp stated_domain_values(%Tempo.Range{first: %Tempo{} = first}), do: [first]
  defp stated_domain_values(%Tempo.Range{last: %Tempo{} = last}), do: [last]
  defp stated_domain_values(_member), do: []

  defp cadence_index(%Tempo{} = value, :year), do: year(value)
  defp cadence_index(%Tempo{} = value, :month), do: year(value) * 12 + month(value)

  # Keep only the domain years matching a `:even` / `:odd` / `:leap` / `:common`
  # filter (`{2000Y..2020Y}e`). Parity is arithmetic on the year number; leap and
  # common delegate to each year's calendar `leap_year?/1` (Calendrical), so the
  # Gregorian century rule applies — 2100, divisible by 4 but not 400, is common.
  defp filter_domain_years(year_intervals, nil), do: year_intervals

  defp filter_domain_years(year_intervals, filter) do
    Enum.filter(year_intervals, fn year_interval ->
      tempo = Interval.from(year_interval)
      year_filter_matches?(filter, year(tempo), tempo.calendar)
    end)
  end

  defp year_filter_matches?(:even, year, _calendar), do: Integer.mod(year, 2) == 0
  defp year_filter_matches?(:odd, year, _calendar), do: Integer.mod(year, 2) == 1
  defp year_filter_matches?(:leap, year, calendar), do: calendar.leap_year?(year)
  defp year_filter_matches?(:common, year, calendar), do: not calendar.leap_year?(year)

  # A recurrence set's occurrences, member by member. A set holding a conditional
  # member (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`) resolves in two
  # passes, since a conditional depends on the other members' occurrences.
  defp set_member_occurrences(members, opts) do
    if Enum.any?(members, &match?(%Conditional{}, &1)) do
      conditional_set_occurrences(members, opts)
    else
      members_occurrences(members, opts)
    end
  end

  defp members_occurrences(members, opts) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case recurrence_set_member(member, opts) do
        {:ok, occurrences} -> {:cont, {:ok, [occurrences | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, occurrences} -> {:ok, occurrences |> Enum.reverse() |> Enum.concat()}
      {:error, _} = error -> error
    end
  end

  # The second pass — date-holidays' `PostRule`, generalised. Every member's
  # occurrences over the `:within` window widened by the conditions' reach are
  # the tally a condition reads; each conditional resolves its own occurrences
  # against the others' and keeps those that overlap the window. The other
  # members materialise over the window itself, exactly as in a set without
  # conditionals.
  defp conditional_set_occurrences(members, opts) do
    {conditionals, others} = Enum.split_with(members, &match?(%Conditional{}, &1))

    with :ok <- validate_conditionals(conditionals),
         {:ok, window} <- conditional_window(conditionals, opts),
         first_opts = widened_opts(opts, window),
         {:ok, first_pass} <- first_pass_occurrences(members, first_opts),
         {:ok, reads} <- conditional_reads(first_pass, first_opts),
         {:ok, others_occurrences} <- members_occurrences(others, opts) do
      resolved =
        for {index, %Conditional{} = conditional, occurrences} <- first_pass,
            occurrence <- occurrences,
            outcome <-
              resolve_conditional_occurrence(occurrence, conditional, Map.get(reads, index, [])),
            in_conditional_window?(outcome, window),
            do: outcome

      {:ok, others_occurrences ++ resolved}
    end
  end

  # A conditional names what it falls on and either the offsets it keeps `:at`
  # or the selector it moves `:to_next`, never both.
  defp validate_conditionals(conditionals) do
    case Enum.reject(conditionals, &Conditional.valid?/1) do
      [] ->
        :ok

      [invalid | _] ->
        {:error, ConversionError.exception(value: invalid, reason: :conditional_member)}
    end
  end

  # Each conditional's condition as the spans of the occurrences it can fall on,
  # keyed by the conditional's member index: the other members' first-pass
  # occurrences whose metadata includes a `:falls_on` map — never its own — or
  # every occurrence of a `:falls_on` recurrence set, materialised over the same
  # widened window.
  defp conditional_reads(first_pass, opts) do
    tally = occurrence_tally(first_pass)

    first_pass
    |> Enum.filter(&match?({_index, %Conditional{}, _occurrences}, &1))
    |> Enum.reduce_while({:ok, %{}}, fn {index, conditional, _occurrences}, {:ok, reads} ->
      case condition_spans(conditional, index, tally, opts) do
        {:ok, spans} -> {:cont, {:ok, Map.put(reads, index, spans)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp condition_spans(
         %Conditional{falls_on: %Tempo.RecurrenceSet{} = reference},
         _index,
         _tally,
         opts
       ) do
    with {:ok, occurrences} <- to_interval_set(reference, opts) do
      spans =
        for %Tempo.Interval{from: %Tempo{}, to: %Tempo{}} = occurrence <-
              IntervalSet.members(occurrences),
            do: occurrence_span(occurrence)

      {:ok, spans}
    end
  end

  defp condition_spans(%Conditional{falls_on: falls_on}, index, tally, _opts) do
    spans =
      for {other, from, to, metadata} <- tally,
          other != index,
          metadata_includes?(metadata, falls_on),
          do: {from, to}

    {:ok, spans}
  end

  # The `:within` window, and the window widened by the conditions' reach — each
  # `:at` offset from either edge, and a move's search span back from the lower
  # edge — so a condition near an edge reads the occurrences just outside it.
  # Without a window (or with an empty one) the members bound themselves and
  # nothing widens.
  defp conditional_window(conditionals, opts) do
    with {:ok, window} <- within_window(opts) do
      widened_window(window, conditional_reach(conditionals))
    end
  end

  defp widened_window(:none, _reach), do: {:ok, :none}
  defp widened_window({nil, _window_to}, _reach), do: {:ok, :none}

  defp widened_window({%Tempo{} = window_from, window_to}, {lower_reach, upper_reach}) do
    widened_from =
      Enum.reduce(lower_reach, window_from, &earlier_endpoint(Math.add(window_from, &1), &2))

    widened = %Tempo.Interval{from: widened_from, to: widened_upper(window_to, upper_reach)}
    {:ok, {window_from, window_to, widened}}
  end

  # An open-ended window stays open.
  defp widened_upper(nil, _upper_reach), do: :undefined

  defp widened_upper(window_to, upper_reach),
    do: Enum.reduce(upper_reach, window_to, &later_endpoint(Math.add(window_to, &1), &2))

  defp conditional_reach(conditionals) do
    Enum.reduce(conditionals, {[], []}, fn
      %Conditional{to_next: nil, at: offsets}, {lower, upper} ->
        {offsets ++ lower, offsets ++ upper}

      %Conditional{to_next: selector}, {lower, upper} ->
        {[Duration.negate(selection_search_span(selector)) | lower], upper}
    end)
  end

  defp widened_opts(opts, :none), do: opts

  defp widened_opts(opts, {_bound_from, _bound_to, widened}),
    do: Keyword.put(opts, :within, widened)

  defp in_conditional_window?(_occurrence, :none), do: true

  defp in_conditional_window?(occurrence, {window_from, window_to, _widened}),
    do: overlaps_window?(occurrence, window_from, window_to)

  # Every member's occurrences, a conditional's being its member's, tagged with
  # the conditional's metadata as a nested set's are.
  defp first_pass_occurrences(members, opts) do
    members
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {member, index}, {:ok, acc} ->
      case recurrence_set_member(first_pass_member(member), opts) do
        {:ok, occurrences} -> {:cont, {:ok, [{index, member, occurrences} | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _} = error -> error
    end
  end

  defp first_pass_member(%Conditional{member: member, metadata: metadata}),
    do: %Tempo.RecurrenceSet{members: [member], metadata: metadata}

  defp first_pass_member(member), do: member

  # Each first-pass occurrence as `{member_index, from, to, metadata}`, its extent
  # in UTC seconds so a condition compares spans without materialising again.
  defp occurrence_tally(first_pass) do
    for {index, _member, occurrences} <- first_pass,
        %Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to, metadata: metadata} <-
          occurrences,
        do: {index, Compare.to_utc_seconds(from), Compare.to_utc_seconds(to), metadata}
  end

  # Keep an occurrence when every day `:at` from its start falls on one of the
  # condition's spans; move one that falls on such a span to the next span its
  # selector gives.
  defp resolve_conditional_occurrence(occurrence, %Conditional{to_next: nil, at: offsets}, spans) do
    if Enum.all?(offsets, &falls_on?(offset_span(occurrence, &1), spans)),
      do: [occurrence],
      else: []
  end

  defp resolve_conditional_occurrence(occurrence, %Conditional{to_next: selector}, spans) do
    if falls_on?(occurrence_span(occurrence), spans),
      do: [next_selected(occurrence, selector)],
      else: [occurrence]
  end

  defp occurrence_span(%Tempo.Interval{from: from, to: to}),
    do: {Compare.to_utc_seconds(from), Compare.to_utc_seconds(to)}

  # The span of the value `offset` from an occurrence's start, at the start's
  # resolution (a day for a day's occurrence).
  defp offset_span(%Tempo.Interval{from: from}, offset) do
    case to_interval(Math.add(from, offset)) do
      {:ok, %Tempo.Interval{} = span} -> occurrence_span(span)
      _no_single_span -> :none
    end
  end

  defp falls_on?({from_seconds, to_seconds}, spans) do
    Enum.any?(spans, fn {span_from, span_to} ->
      span_from < to_seconds and from_seconds < span_to
    end)
  end

  defp falls_on?(:none, _spans), do: false

  defp metadata_includes?(metadata, pattern) do
    Enum.all?(pattern, fn {key, value} -> Map.fetch(metadata, key) == {:ok, value} end)
  end

  # The first span `selector` gives after the occurrence, searched over a week
  # for a weekday and a year otherwise; with none, the occurrence stays.
  defp next_selected(
         %Tempo.Interval{to: after_occurrence, metadata: metadata} = occurrence,
         selector
       ) do
    search = %Tempo.Interval{
      from: after_occurrence,
      to: Math.add(after_occurrence, selection_search_span(selector))
    }

    with {:ok, %IntervalSet{} = selected} <- select(search, selector),
         %Tempo.Interval{} = next <- IntervalSet.first(selected) do
      %{next | metadata: metadata}
    else
      _nothing_selected -> occurrence
    end
  end

  defp selection_search_span(%Tempo{time: [day_of_week: _]}), do: %Tempo.Duration{time: [day: 7]}
  defp selection_search_span(_selector), do: %Tempo.Duration{time: [year: 1]}

  # One recurrence-set member's occurrences: an interval member (a recurrence, or
  # a concrete interval) carries its metadata onto each occurrence; a plain
  # `%Tempo{}` member is a concrete value, materialised to its span. A nested
  # recurrence set is one member (a holiday and its observed days): its own
  # metadata tags every occurrence its members produce. Anything else is not a
  # member, so it is an error rather than a raise.
  defp recurrence_set_member(%module{metadata: metadata} = member, opts)
       when module in [Tempo.Interval, Tempo.RecurrenceSet] do
    with {:ok, materialised} <- to_interval(member, opts) do
      occurrences =
        materialised
        |> recurrence_set_occurrences()
        |> Enum.map(&merge_member_metadata(&1, metadata))

      {:ok, occurrences}
    end
  end

  defp recurrence_set_member(%Tempo{} = member, opts) do
    with {:ok, materialised} <- to_interval(member, opts) do
      {:ok, recurrence_set_occurrences(materialised)}
    end
  end

  defp recurrence_set_member(member, _opts) do
    {:error, ConversionError.exception(value: member, reason: :recurrence_set_member)}
  end

  defp recurrence_set_occurrences(%Tempo.Interval{} = interval), do: [interval]
  defp recurrence_set_occurrences(%Tempo.IntervalSet{} = set), do: IntervalSet.members(set)

  # A value's metadata onto the interval, or each interval, it materialised to.
  defp with_value_metadata(%Tempo.Interval{} = interval, metadata),
    do: merge_member_metadata(interval, metadata)

  defp with_value_metadata(%IntervalSet{} = set, metadata) do
    labelled = IntervalSet.map(set, &merge_member_metadata(&1, metadata))

    case IntervalSet.new(labelled, metadata: IntervalSet.metadata(set)) do
      {:ok, labelled_set} -> labelled_set
      {:error, _} -> set
    end
  end

  # Carry a recurrence-set member's metadata (e.g. a holiday name) onto each
  # occurrence it produces; an occurrence's own metadata wins any conflict. The
  # member's span directives have already shaped each occurrence's extent, so —
  # as when a recurrence emits its occurrences — they are not copied onto them.
  defp merge_member_metadata(interval, metadata) when map_size(metadata) == 0, do: interval

  defp merge_member_metadata(%Tempo.Interval{metadata: existing} = interval, metadata) do
    %{interval | metadata: Map.merge(strip_span_directives(metadata), existing)}
  end

  @doc """
  Convert any Tempo value to a `t:Tempo.IntervalSet.t/0`.

  Unlike `to_interval/1` (which may return either a single
  interval or an IntervalSet), `to_interval_set/1` always returns
  an IntervalSet — wrapping a single interval in a one-element
  set if needed. This is the convenient form when the caller
  wants a uniform shape (e.g. to pipe into set operations).

  ### Arguments

  * `value` is a `t:#{__MODULE__}.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.IntervalSet.t/0`, `t:Tempo.Set.t/0`, or a
    `t:Tempo.RecurrenceSet.t/0`.

  ### Options

  * `:within` is the window whose occurrences you want. Every
    recurrence (or a `t:Tempo.RecurrenceSet.t/0` of them) keeps the
    occurrences that overlap it — one already in progress when the
    window opens, and one that runs past its end. An open-ended
    window (`~o"2026-09-28/.."`) keeps those from its start on,
    lazily for a value with no end of its own. See `to_interval/2`.

  ### Returns

  * `{:ok, interval_set}` on success, or `{:error, reason}` for
    the same cases that `to_interval/2` errors on.

  ### Examples

      iex> {:ok, tempo} = Tempo.from_iso8601("2026-01")
      iex> {:ok, set} = Tempo.to_interval_set(tempo)
      iex> Tempo.IntervalSet.count(set)
      1

  """
  @spec to_interval_set(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.Duration.t()
          | Tempo.RecurrenceSet.t(),
          keyword()
        ) ::
          {:ok, Tempo.IntervalSet.t()} | {:error, error_reason()}
  def to_interval_set(value, options \\ []) do
    case to_interval(value, options) do
      {:ok, %Tempo.IntervalSet{} = set} -> {:ok, set}
      {:ok, %Tempo.Interval{} = interval} -> IntervalSet.new([interval])
      {:error, _} = err -> err
    end
  end

  @doc """
  Raising version of `to_interval_set/1`.

  ### Arguments

  * `value` is any value `to_interval_set/1` accepts.

  ### Returns

  * The `t:Tempo.IntervalSet.t/0`.

  ### Examples

      iex> Tempo.to_interval_set!(~o"2026-06")
      #Tempo.IntervalSet<[#Tempo.Interval<~o"2026Y6M/7M" unit: day>]>

  """
  @spec to_interval_set!(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.Duration.t()
        ) :: Tempo.IntervalSet.t()
  def to_interval_set!(value) do
    case to_interval_set(value) do
      {:ok, set} -> set
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  @doc """
  Map `fun` over an enumerable of Tempo values, collecting the results into
  a `t:Tempo.IntervalSet.t/0`.

  The Tempo analogue of `Enum.map/2`: it walks any enumerable Tempo value
  (a `t:Tempo.IntervalSet.t/0`, a `t:Tempo.Set.t/0`, a plain list of
  values, …), applies `fun` to each element, and gathers the results into
  an interval set instead of a list. Each result is converted with
  `Tempo.to_interval/1`, so `fun` may return either a `t:t/0` — a day
  becomes its `[day, next_day)` span — or an interval. Members are kept
  distinct (no coalescing); apply `Tempo.IntervalSet.coalesce/1` afterward
  if you want touching spans merged.

  Raises if a mapped value cannot be converted to a bounded interval.
  Use `try_map/2` for the error-returning form.

  ### Arguments

  * `enumerable` is any enumerable of Tempo values.

  * `fun` is a one-arity function applied to each element.

  ### Returns

  * a `t:Tempo.IntervalSet.t/0` of the mapped, converted values.

  ### Examples

      iex> [~o"2025-07-04", ~o"2026-07-04", ~o"2027-07-04"]
      ...> |> Tempo.map(&Tempo.nearest_workday(&1, :US))
      ...> |> Tempo.IntervalSet.count()
      3

  """
  @spec map(Enumerable.t(), (term() -> term())) :: Tempo.IntervalSet.t()
  def map(enumerable, fun) when is_function(fun, 1) do
    case try_map(enumerable, fun) do
      {:ok, set} ->
        set

      {:error, exception} when is_exception(exception) ->
        raise exception

      {:error, reason} ->
        raise ArgumentError, "Tempo.map/2 could not build the set: #{inspect(reason)}"
    end
  end

  @doc """
  Like `map/2`, but returns `{:ok, interval_set}` or halts at the first
  value that cannot be converted, returning its `{:error, reason}`.

  This is the "traverse" form — map every element, or stop at the first
  failure and report it — analogous to Gleam's `list.try_map` or a Rust
  `collect::<Result<_, _>>()`. `fun` returns a plain Tempo value (exactly
  as for `map/2`); the error is the first result that `Tempo.to_interval/1`
  rejects (an unbounded, unanchored or otherwise unconvertible
  value), so a partially-resolvable set never yields a partial result.

  ### Arguments

  * `enumerable` is any enumerable of Tempo values.

  * `fun` is a one-arity function applied to each element.

  ### Returns

  * `{:ok, interval_set}` when every mapped value converts, or

  * `{:error, reason}` for the first that does not.

  ### Examples

      iex> {:ok, set} = Tempo.try_map([~o"2025-07-04", ~o"2026-07-04"], &Tempo.nearest_workday(&1, :US))
      iex> Tempo.IntervalSet.count(set)
      2

      iex> match?({:error, _}, Tempo.try_map([~o"P1D"], & &1))
      true

  """
  @spec try_map(Enumerable.t(), (term() -> term())) ::
          {:ok, Tempo.IntervalSet.t()} | {:error, error_reason()}
  def try_map(enumerable, fun) when is_function(fun, 1) do
    enumerable
    |> Enum.reduce_while([], fn element, acc ->
      case to_interval(fun.(element)) do
        {:ok, interval} -> {:cont, [interval | acc]}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:error, _} = error -> error
      intervals -> IntervalSet.new(Enum.reverse(intervals))
    end
  end

  defp materialisation_error(tempo, reason) do
    ConversionError.exception(value: tempo, reason: reason)
  end

  # What a function of one date or time value says of anything else: an
  # interval, a duration, a set, a recurrence, or a term that is no Tempo
  # value at all.
  defp not_one_value(function, value) do
    ArgumentError.exception(
      "Tempo.#{function} takes one date or time value, and #{inspect(value)} is not one."
    )
  end

  # An unspecified year on its own (`X*Y`) is a year no one has named, with
  # no place on the time line and no cycle to lie on.
  defp materialise_value(%Tempo{time: [{:year, :any}]} = tempo),
    do: {:error, UnanchoredError.exception(value: tempo)}

  defp materialise_value(%Tempo{} = tempo) do
    # `X*Y2M28D` is "28 February of an unspecified year", and whether the
    # next day is the 29th or 1 March depends on which year. The stepper
    # reports that as `{:error, :unanchored}`; name the value here,
    # where it is still in scope.
    case do_to_interval(tempo) do
      {:error, :unanchored} -> {:error, UnanchoredError.exception(value: tempo)}
      {:error, :grouped_component} -> {:error, materialisation_error(tempo, :grouped_component)}
      other -> other
    end
  end

  # A concrete value with a selection (ISO 8601-2 §12.11): the units before the
  # selection are its context — `2018Y9M` in `2018Y9ML1K1IN`, "the first Monday
  # of September 2018" — and the units after it apply to every date it selects
  # (§12.11.2). Each period of the context (a year, or a month of a year)
  # resolves the selection once, so a set or mask of years
  # (`XXX{0,2,4,6,8}Y11MLLL1K1IN/P9DN2K1IN`, US Election Day) costs one
  # selection per year it names. A `:within` window keeps the dates that overlap
  # it and narrows the years before any is resolved; a context without a year
  # takes its years from the window, so it needs one.
  defp materialise_selection(%Tempo{} = tempo, context, selection, trailing, opts) do
    rule = %{tempo | time: [selection: selection]}
    cadence = %Tempo.Duration{time: [{selection_cadence_unit(context), 1}]}
    finer_context = Keyword.delete(context, :year)

    with {:ok, window} <- within_window(opts),
         {:ok, years} <- selection_years(tempo, Keyword.get(context, :year), window),
         members = selection_members(tempo, years, finer_context),
         {:ok, occurrences} <- members_selection(members, rule, cadence) do
      occurrences
      |> IntervalSet.new()
      |> keep_occurrences_in_window(window)
      |> with_trailing_units(trailing)
    end
  end

  # Each period of the context the selection resolves in: a year, or a month
  # of a year, of each year the context names.
  defp selection_members(tempo, years, finer_context) do
    for year <- years,
        member <- context_members(%{tempo | time: [{:year, year} | finer_context]}),
        do: member
  end

  # The dates the selection picks in every period, or the error of the first
  # period it has no answer for.
  defp members_selection(members, rule, cadence) do
    Enum.reduce_while(members, {:ok, []}, fn member, {:ok, occurrences} ->
      case member_selection(member, rule, cadence) do
        {:error, _reason} = error -> {:halt, error}
        selected -> {:cont, {:ok, occurrences ++ selected}}
      end
    end)
  end

  # The dates the selection picks in one period of the context: the period,
  # filled down to the grain the selection names, as the one candidate the
  # selection resolves in.
  defp member_selection(%Tempo{} = member, rule, cadence) do
    {start, recurrence} =
      fill_selection_start(member, %Tempo.Interval{from: member, repeat_rule: rule})

    candidate = %Tempo.Interval{from: start, to: Math.add(start, cadence)}

    case Selection.apply(candidate, rule, freq_of(cadence), origin_day: origin_day_of(recurrence)) do
      {:error, _reason} = error -> error
      occurrences -> resize_selected_occurrences(occurrences, true)
    end
  end

  # The years a context names — a year, a list of years and ranges, a mask
  # (`202XY`, `XXX{0,2,4,6,8}Y`) standing for the years it matches — narrowed
  # to a bound's years, which are also the years of a context that names none.
  defp selection_years(tempo, year, :none) when year in [nil, :any] do
    {:error,
     UnboundedRecurrenceError.exception(
       reason:
         "#{inspect(tempo)} selects in every year, so it needs a :within window — " <>
           "any Tempo value that limits the years."
     )}
  end

  defp selection_years(%Tempo{calendar: calendar}, year, :none) do
    {:ok, context_years(year, calendar)}
  end

  # An open-ended window keeps the named years from its start on.
  defp selection_years(%Tempo{calendar: calendar}, year, {%Tempo{} = window_from, nil})
       when year not in [nil, :any] do
    with {:ok, first} <- year_in_calendar(window_from, calendar) do
      {:ok, year |> context_years(calendar) |> Enum.filter(&(&1 >= first))}
    end
  end

  defp selection_years(%Tempo{calendar: calendar}, year, window) do
    with {:ok, window_years} <- window_years(window, calendar) do
      {:ok, Enum.filter(window_years, &year_named?(&1, year))}
    end
  end

  defp context_years(year, _calendar) when is_integer(year), do: [year]

  defp context_years({:mask, mask}, calendar) do
    {:ok, years} = Mask.valid_values(:year, mask, [], calendar)
    years
  end

  defp context_years(years, calendar) when is_list(years) do
    Enum.flat_map(years, fn
      %Range{} = range -> Enum.to_list(range)
      year -> context_years(year, calendar)
    end)
  end

  defp year_named?(_year, year) when year in [nil, :any], do: true
  defp year_named?(year, named), do: Selection.year_selected?(year, named)

  # The years of `calendar` a bound's window meets: from the year its start
  # falls in to the year its end does.
  defp window_years({%Tempo{} = bound_from, %Tempo{} = bound_to}, calendar) do
    with {:ok, first} <- year_in_calendar(bound_from, calendar),
         {:ok, last} <- year_in_calendar(bound_to, calendar) do
      {:ok, Enum.to_list(first..last//1)}
    end
  end

  defp window_years(_window, _calendar), do: {:error, empty_bound_error()}

  defp year_in_calendar(%Tempo{calendar: calendar, time: time}, calendar) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> {:ok, year}
      _no_year -> {:error, empty_bound_error()}
    end
  end

  defp year_in_calendar(%Tempo{} = endpoint, calendar) do
    with %Tempo{} = day <- at_resolution(endpoint, :day),
         {:ok, %Tempo{} = converted} <- to_calendar(day, calendar) do
      year_in_calendar(converted, calendar)
    end
  end

  # Each member of a context with a set of finer values (`2018Y{3,9}M`) is its
  # own period.
  defp context_members(%Tempo{} = member) do
    case multi_tempo?(member) and expand_members(member) do
      false -> [member]
      {:ok, members} -> members
      # A context is expanded with its year, which bounds every range in
      # it; one that cannot be listed names no period.
      {:error, _exception} -> []
    end
  end

  # The recurrence steps by the context's finest unit, so each period is one
  # member of the context.
  defp selection_cadence_unit([]), do: :year

  defp selection_cadence_unit(context) do
    case List.last(context) do
      {:day_of_year, _value} -> :day
      {unit, _value} when unit in [:year, :month, :week, :day, :hour, :minute] -> unit
      _other -> :year
    end
  end

  # An interval that starts or ends on a selection (ISO 8601-2 §12.11.3):
  # `2018Y9ML1K1IN/P5D` is the five days from the first Monday of September
  # 2018, one span for each date the selection gives.
  defp selected_spans(%Tempo{} = endpoint, span_of, metadata, opts) do
    with {:ok, %IntervalSet{} = selected} <- to_interval(endpoint, opts) do
      selected
      |> IntervalSet.members()
      |> Enum.map(fn %Tempo.Interval{from: date} ->
        {from, to} = span_of.(date)
        %Tempo.Interval{from: from, to: to, metadata: metadata}
      end)
      |> IntervalSet.new()
    end
  end

  # The units after a selection apply to every date it selects (ISO 8601-2
  # §12.11.2): `2018YL{1,2,5}KNT10H0M0S` is each of those days at 10:00:00.
  defp with_trailing_units(result, []), do: result

  defp with_trailing_units({:ok, %IntervalSet{} = set}, trailing) do
    set
    |> IntervalSet.members()
    |> Enum.reduce_while({:ok, []}, fn %Tempo.Interval{from: %Tempo{} = from}, {:ok, acc} ->
      case selected_with_units(from, trailing) do
        {:ok, %Tempo.Interval{} = interval} ->
          {:cont, {:ok, [interval | acc]}}

        {:ok, %IntervalSet{} = expanded} ->
          {:cont, {:ok, Enum.reverse(IntervalSet.members(expanded)) ++ acc}}

        # A date the units do not make (`2026YL{1,2}MN30D` has no 30
        # February) is passed over, as a selection passes over a value its
        # period lacks.
        {:error, %InvalidDateError{}} ->
          {:cont, {:ok, acc}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, intervals} ->
        intervals |> Enum.reverse() |> Enum.map(&selected_span/1) |> IntervalSet.new()

      {:error, _reason} = error ->
        error
    end
  end

  defp with_trailing_units({:error, _reason} = error, _trailing), do: error

  # A date the selection picked with the units after it, read as the same
  # text is: a unit counted from the end (`2026YL6MN-1D`) is counted in the
  # date picked, which the text before the selection could not give it.
  defp selected_with_units(%Tempo{time: time, calendar: calendar} = selected, trailing) do
    with_units = %{selected | time: Keyword.merge(time, trailing)}

    with {:ok, %Tempo{} = read} <-
           Validation.validate(with_units, Compare.effective_calendar(calendar)) do
      to_interval(read)
    end
  end

  # A span a selection picks is walked as the span it is, as the dates it
  # picks are: the unit a value's own span is walked by, which
  # `to_interval/1` gave it, is not the selection's.
  defp selected_span(%Tempo.Interval{} = interval), do: %{interval | unit: nil}

  # A value of whole numbers alone names its own one span, and nothing a
  # shape is read by applies to it, so it is converted at once: most values
  # converted are such, each member of a set among them.
  defp do_to_interval(%Tempo{time: time} = tempo) do
    if whole_numbers?(time), do: single_span(tempo), else: shaped_interval(tempo)
  end

  # A group with a unit after it (`2026Y2G4WU3K`, the Wednesday of each of
  # four weeks) is the spans its walk names, since what the unit after a
  # group counts in is the walk's to read (`Tempo.Enumeration`): it is not
  # the one span a group with nothing after it is.
  defp shaped_interval(%Tempo{} = tempo) do
    with {:ok, %Tempo{time: time} = tempo} <- crisp_reading(tempo) do
      cond do
        group_of_set?(time) -> spans_of_each_group(tempo)
        group_before_unit?(time) -> materialise_multi(tempo)
        true -> ungrouped_interval(tempo)
      end
    end
  end

  # A group of a set (`2026Y{1,2}G3MU`, the first and the second groups of
  # three months) names a span in each of its groups, and each is converted
  # as the group it is, a unit after it counted from that group's start. A
  # group its container lacks is passed over, as a set drops a member its
  # context cannot hold. One of several groups (`[1,2]G3MU`) is no one
  # span, as a one-of set is none.
  defp spans_of_each_group(%Tempo{time: time, calendar: calendar} = tempo) do
    {prefix, [{unit, {:group, {kind, members}}, size} | rest]} =
      Enum.split_while(time, &(not match?({_unit, {:group, _members}, _size}, &1)))

    calendar = Compare.effective_calendar(calendar)

    with :all <- kind,
         {:ok, groups} <- Group.groups_of_set(unit, members, size, prefix, calendar) do
      groups
      |> Enum.map(&%{tempo | time: prefix ++ [{unit, {:group, &1}} | rest]})
      |> Enum.map(&group_spans(&1, calendar))
      |> spans_of_groups_in_container()
    else
      :one -> {:error, materialisation_error(tempo, :one_of_set)}
      {:error, {:unresolved, unit}} -> {:error, uncounted_group_error(tempo, unit)}
    end
  end

  defp group_spans(%Tempo{} = group, calendar) do
    with {:ok, %Tempo{} = read} <- Validation.validate(group, calendar), do: to_interval(read)
  end

  defp spans_of_groups_in_container(results) do
    case Enum.reject(results, &match?({:error, %InvalidDateError{}}, &1)) do
      [] when results != [] -> hd(results)
      kept -> gather_members(kept)
    end
  end

  defp uncounted_group_error(%Tempo{} = tempo, unit) do
    if anchored?(tempo) do
      ConversionError.exception(
        value: tempo,
        reason:
          "Cannot convert #{inspect(tempo)}: its #{unit} group counts from the end of a " <>
            "span the units before it do not fix."
      )
    else
      UnanchoredError.exception(value: tempo)
    end
  end

  # Whether every unit is one whole number: a year of either sign, and a
  # unit after it that is not counted from the end.
  defp whole_numbers?([{:year, year} | rest]) when is_integer(year), do: whole_after_year?(rest)
  defp whole_numbers?(time), do: whole_after_year?(time)

  defp whole_after_year?([{_unit, value} | rest]) when is_integer(value) and value >= 0,
    do: whole_after_year?(rest)

  defp whole_after_year?([{:microsecond, {value, precision}}])
       when is_integer(value) and is_integer(precision),
       do: true

  defp whole_after_year?([]), do: true
  defp whole_after_year?(_shaped), do: false

  # A value is converted as the walk yields it. A margin of error is dropped
  # (`2026±2Y` spans 2026), and what could not be read beside it when the
  # value was written is read now: a count from the end (`2026±2Y-1M`), a
  # group (`2026±2Y2G3MU`). Significant digits are the mask they are
  # equivalent to (`1950S2Y1XM` is `19XXY1XM`), so that a unit after them is
  # read in each year of the block and not once for the block, and they are
  # the value itself where every digit is significant (`1950S4` is 1950).
  defp crisp_reading(%Tempo{time: time, calendar: calendar} = tempo) do
    case time |> Compare.drop_margin_of_error() |> Interval.significant_digits_as_mask() do
      ^time -> {:ok, tempo}
      crisp -> Validation.validate(%{tempo | time: crisp}, calendar)
    end
  end

  # A group of a set (`2026Y{1,2}G3MU15D`) names a span in each of its
  # groups. It is taken apart into its groups before anything reads the
  # units around it, which a mask after it would (`{1,2}G3MUXD`).
  defp group_of_set?(time),
    do: Enum.any?(time, &match?({_unit, {:group, _members}, _size}, &1))

  defp ungrouped_interval(%Tempo{} = tempo) do
    case mask_context_members(tempo) do
      {:ok, members} -> materialise_mask_members(members)
      {:error, _exception} = error -> error
      :none -> narrowed_interval(tempo)
    end
  end

  defp group_before_unit?([{_unit, {:group, %Range{}}}, _finer | _rest]), do: true
  defp group_before_unit?([_component | rest]), do: group_before_unit?(rest)
  defp group_before_unit?([]), do: false

  # A set before a value's first mask (`2026-{6,7}-1X`): each member of the set
  # is a context of its own, in which the mask narrows.
  defp mask_context_members(%Tempo{time: time} = tempo) do
    time
    |> Enum.split_while(&(not masked?(&1)))
    |> context_members(tempo)
  end

  defp context_members({[_ | _] = context, [_ | _] = masked}, tempo) do
    case Enumeration.expand(%{tempo | time: context}) do
      {:ok, members} -> {:ok, Enum.map(members, &%{&1 | time: &1.time ++ masked})}
      {:error, _exception} = error -> error
      :not_expandable -> :none
    end
  end

  defp context_members(_split, _tempo), do: :none

  defp narrowed_interval(%Tempo{} = tempo) do
    # Step 1: narrow any mask to the values it allows (see
    # `expand_non_contiguous_mask/1`): replaced by its candidates when
    # they are disjoint spans (`1985-XX-15`), by values of their own when
    # a later mask narrows within each (`2026-XX-1X`), or the span from
    # the first to the last when they are consecutive (`2026-06-1X`).
    case expand_non_contiguous_mask(tempo) do
      {:ok, tempo} -> materialise_expanded(tempo)
      {:span, first, last} -> masked_span(first, last)
      {:members, members} -> materialise_mask_members(members)
      {:error, _reason} = error -> error
    end
  end

  # The span of a mask's consecutive candidates: from the start of the first to
  # the end of the last. It walks the masked unit, as the mask does and as a
  # year mask's span walks its years. Each end is a raw candidate, so it is
  # read as a member is: a day of the year (`2026Y3XO`, or a day written
  # straight after its year, `2026Y3XD`) is its month and day, and the span
  # runs from 30 January to 9 February.
  defp masked_span(%Tempo{} = first, %Tempo{} = last) do
    with {:ok, first} <- normalise_member(first),
         {:ok, last} <- normalise_member(last),
         {:ok, {lower, _upper}, _unit} <- Interval.next_unit_boundary(first),
         {:ok, {_lower, upper}, _unit} <- Interval.next_unit_boundary(last) do
      {:ok, %Tempo.Interval{from: lower, to: upper}}
    end
  end

  defp materialise_expanded(%Tempo{} = tempo) do
    # Step 2: detect whether the resulting Tempo expands to
    # multiple intervals. A "multi" shape is any time slot whose
    # value is a list containing more than one candidate (ranges,
    # multi-element lists). Masks, scalars, and single-element
    # lists use the existing single-interval path in
    # `next_unit_boundary/1`.
    case span_shape(tempo.time, :single) do
      :single -> single_span(tempo)
      :multi -> materialise_multi(tempo)
      :group_of_set -> {:error, materialisation_error(tempo, :grouped_component)}
    end
  end

  # Whether a value names one span or several, read in one pass. A group of
  # a set (`2026Y{1,2}G3MU15D`, the first and the second groups of three
  # months) names a span in each of its groups, and nothing expands it to
  # them, so it is no one span.
  defp span_shape([], shape), do: shape
  defp span_shape([{_unit, {:group, _members}, _size} | _rest], _shape), do: :group_of_set

  # Significant digits with a unit after them (`1950S2Y6M`, the June of each
  # year of the 1900s) name a span in each value of the block, as the walk
  # yields them. With nothing after them they are the one span of the block.
  defp span_shape([{_unit, {_value, [significant_digits: _digits]}}, _finer | rest], _shape),
    do: span_shape(rest, :multi)

  defp span_shape([slot | rest], shape),
    do: span_shape(rest, if(multi_slot?(slot), do: :multi, else: shape))

  # The bounds keep the value's own resolution; the iteration granularity of
  # the implicit span travels on `:unit` (see
  # `Tempo.Interval.next_unit_boundary/1`).
  defp single_span(tempo) do
    case Interval.next_unit_boundary(tempo) do
      {:ok, {lower, upper}, unit} -> {:ok, %Tempo.Interval{from: lower, to: upper, unit: unit}}
      {:error, _} = err -> err
    end
  end

  @doc """
  Raising version of `to_interval/1`.

  ### Arguments

  * `value` is a `t:#{__MODULE__}.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.IntervalSet.t/0`, `t:Tempo.RecurrenceSet.t/0`, or
    `t:Tempo.Set.t/0`.

  ### Returns

  * The converted `t:Tempo.Interval.t/0` or
    `t:Tempo.IntervalSet.t/0`.

  ### Raises

  * `ArgumentError` when the input cannot be converted. See
    `to_interval/1` for the error cases.

  ### Examples

      iex> {:ok, tempo} = Tempo.from_iso8601("2026")
      iex> interval = Tempo.to_interval!(tempo)
      iex> {interval.from.time, interval.to.time}
      {[year: 2026], [year: 2027]}

  """
  @spec to_interval!(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.RecurrenceSet.t()
          | Tempo.Duration.t()
        ) ::
          Tempo.Interval.t() | Tempo.IntervalSet.t()
  def to_interval!(value) do
    case to_interval(value) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Union of two Tempo values — every instant in either operand.
  See `Tempo.Operations.union/3` for full details.
  ### Examples

      iex> {:ok, either} = Tempo.union(~o"2026-01", ~o"2026-03")
      iex> either
      #Tempo.IntervalSet<[#Tempo.Interval<~o"2026Y1M/2M" unit: day>, #Tempo.Interval<~o"2026Y3M/4M" unit: day>]>

  """
  defdelegate union(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Intersection of two Tempo values — every instant in both
  operands. Each result interval is the trimmed overlap; `a`
  members can split into multiple fragments. See
  `Tempo.Operations.intersection/3`.
  ### Examples

      iex> {:ok, both} = Tempo.intersection(~o"2026-06-15T09/2026-06-15T17", ~o"2026-06-15T14/2026-06-15T20")
      iex> both
      #Tempo.IntervalSet<[~o"2026Y6M15DT14H/T17H"]>

  """
  defdelegate intersection(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Complement of a Tempo value within a window — the instants of the
  `:within` window it does not cover. The `:within` option is
  required. See `Tempo.Operations.complement/2`.

  ### Examples

      iex> meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"
      iex> {:ok, free} = Tempo.complement(meeting, within: ~o"2026-06-15T09:00/2026-06-15T17:00")
      iex> free
      #Tempo.IntervalSet<[~o"2026Y6M15DT9H0M/T10H0M", ~o"2026Y6M15DT11H0M/T17H0M"]>

  """
  defdelegate complement(set, opts), to: Tempo.Operations

  @doc """
  Difference `a \\ b` — every instant in `a` that is not in
  `b`. Each result interval is the trimmed remainder; `a`
  members can split into multiple fragments. See
  `Tempo.Operations.difference/3`.
  ### Examples

      iex> workday = ~o"2026-06-15T09/2026-06-15T17"
      iex> lunch = ~o"2026-06-15T12/2026-06-15T13"
      iex> {:ok, working} = Tempo.difference(workday, lunch)
      iex> working
      #Tempo.IntervalSet<[~o"2026Y6M15DT9H/T12H", ~o"2026Y6M15DT13H/T17H"]>

  """
  defdelegate difference(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Symmetric difference `a △ b` — instants in exactly one of
  the two operands. Trimmed/instant-level. See
  `Tempo.Operations.symmetric_difference/3`.
  ### Examples

      iex> {:ok, exactly_one} = Tempo.symmetric_difference(~o"2026-06-15T09/2026-06-15T13", ~o"2026-06-15T11/2026-06-15T17")
      iex> exactly_one
      #Tempo.IntervalSet<[~o"2026Y6M15DT9H/T11H", ~o"2026Y6M15DT13H/T17H"]>

  """
  defdelegate symmetric_difference(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Member-preserving overlap filter — returns the whole members of
  `a` that overlap any member of `b`, with their original
  metadata. Use this when the question is about *which events*
  hit the query window. See `Tempo.Operations.members_overlapping/3`.
  ### Examples

      iex> busy = Tempo.IntervalSet.new!([
      ...>   Tempo.to_interval!(~o"2026-06-15T10:00/2026-06-15T11:00"),
      ...>   Tempo.to_interval!(~o"2026-06-16T14:00/2026-06-16T15:00")
      ...> ])
      iex> {:ok, monday_events} = Tempo.members_overlapping(busy, ~o"2026-06-15")
      iex> monday_events
      #Tempo.IntervalSet<[~o"2026Y6M15DT10H0M/T11H0M"]>

  """
  defdelegate members_overlapping(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Member-preserving anti-overlap filter — returns the whole
  members of `a` that do NOT overlap any member of `b`, kept
  whole with their original metadata. Use this when the
  question is about *which events* survive the filter (e.g.
  "which workdays aren't holidays?"). See
  `Tempo.Operations.members_outside/3`.
  ### Examples

      iex> busy = Tempo.IntervalSet.new!([
      ...>   Tempo.to_interval!(~o"2026-06-15T10:00/2026-06-15T11:00"),
      ...>   Tempo.to_interval!(~o"2026-06-16T14:00/2026-06-16T15:00")
      ...> ])
      iex> {:ok, not_monday} = Tempo.members_outside(busy, ~o"2026-06-15")
      iex> not_monday
      #Tempo.IntervalSet<[~o"2026Y6M16DT14H0M/T15H0M"]>

  """
  defdelegate members_outside(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Member-preserving symmetric-difference filter — members of
  either operand that don't overlap any member of the other,
  kept whole. See `Tempo.Operations.members_in_exactly_one/3`.
  ### Examples

      iex> busy = Tempo.IntervalSet.new!([
      ...>   Tempo.to_interval!(~o"2026-06-15T10:00/2026-06-15T11:00"),
      ...>   Tempo.to_interval!(~o"2026-06-16T14:00/2026-06-16T15:00")
      ...> ])
      iex> monday_only = Tempo.IntervalSet.new!([Tempo.to_interval!(~o"2026-06-15T10:00/2026-06-15T11:00")])
      iex> {:ok, unshared} = Tempo.members_in_exactly_one(busy, monday_only)
      iex> unshared
      #Tempo.IntervalSet<[~o"2026Y6M16DT14H0M/T15H0M"]>

  """
  defdelegate members_in_exactly_one(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when `a` and `b` share no instants.
  See `Tempo.Operations.disjoint?/3`.
  ### Examples

      iex> Tempo.disjoint?(~o"2026-01", ~o"2026-03")
      true

      iex> Tempo.disjoint?(~o"2026-01", ~o"2026-01-15")
      false

  """
  defdelegate disjoint?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when `a` and `b` share at least one instant.
  See `Tempo.Operations.overlaps?/3`.
  ### Examples

      iex> Tempo.overlaps?(~o"2026-06-15T10/2026-06-15T12", ~o"2026-06-15T11/2026-06-15T14")
      true

      iex> Tempo.overlaps?(~o"2026-01", ~o"2026-03")
      false

  """
  defdelegate overlaps?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when every instant of `b` is also in `a` — the mirror of
  `within?/3`. See `Tempo.Operations.contains?/3`.
  ### Examples

      iex> Tempo.contains?(~o"2026-06", ~o"2026-06-15")
      true

      iex> Tempo.contains?(~o"2026-06-15", ~o"2026-06")
      false

  """
  defdelegate contains?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when `a` and `b` span the same instants (at their
  aligned resolution). See `Tempo.Operations.equal?/3`.
  ### Examples

      iex> Tempo.equal?(~o"2026-06", ~o"2026-06-01/2026-07-01")
      true

      iex> Tempo.equal?(~o"2026-06", ~o"2026-07")
      false

  """
  defdelegate equal?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Classify the Allen interval-algebra relation between two
  interval-like values.

  Thin delegate to `Tempo.Interval.relation/2` — see that
  function's docs for the full table of 13 relations.

  Named `relation` (not `compare`) because it returns one of 13
  Allen relations rather than stdlib's ternary `:lt | :eq | :gt`
  — using `compare` would invite the wrong mental model at the
  call site.

  Use `Tempo.IntervalSet.relation_matrix/2` when both operands
  are multi-member sets and you want the per-pair breakdown.

  ### Examples

      iex> Tempo.relation(~o"2026-06-15", ~o"2026-06-16")
      :meets

      iex> a = Tempo.Interval.new!(from: ~o"2026-06-01", to: ~o"2026-06-10")
      iex> b = Tempo.Interval.new!(from: ~o"2026-06-05", to: ~o"2026-06-15")
      iex> Tempo.relation(a, b)
      :overlaps

  """
  defdelegate relation(a, b), to: Tempo.Interval

  @doc """
  Compare two Tempo values, returning stdlib's ternary
  `:lt | :eq | :gt`.

  Thin delegate to `Tempo.Compare.compare/3` — see that function for
  the full discussion, including how uncertainty is handled and how
  calendar-dependent durations are resolved.

  This is the sorter-module callback `Enum` looks for, so `Tempo` may
  be passed anywhere `Date` or `DateTime` would be. Use `relation/2`
  when the question is *how* two intervals relate rather than which
  comes first.

  ### Examples

      iex> Tempo.compare(~o"2026-06-15", ~o"2026-06-16")
      :lt

      iex> [~o"2026-06-16", ~o"2026-06-15"]
      ...> |> Enum.sort(Tempo)
      [~o"2026Y6M15D", ~o"2026Y6M16D"]

      iex> Tempo.compare(~o"PT1H", ~o"PT90M")
      :lt

  """
  defdelegate compare(a, b, options \\ []), to: Tempo.Compare

  @doc """
  Return the length of an interval or of the span a value names, or
  the time an interval set covers, as a `%Tempo.Duration{}`.

  A length is counted in the unit its endpoints are written in: two
  days are a number of days apart, two times of day a number of hours
  or minutes — see `Tempo.Interval.duration/1`. A value is the span it
  names, so June is a month long. A set's duration counts time that
  two members share once — see `Tempo.IntervalSet.duration/1`.

  ### Arguments

  * `value` is a `t:Tempo.Interval.t/0`, a `t:Tempo.IntervalSet.t/0`,
    a `t:Tempo.t/0` or a `t:Tempo.Set.t/0`, measured as the span or the
    spans it names.

  ### Returns

  * A `t:Tempo.Duration.t/0` in the endpoints' unit, or `:infinity`
    for an interval with an open end.

  * `{:error, %Tempo.UnanchoredError{}}` for a value or an interval
    without a year, which has no place on the time line to measure.

  * `{:error, %Tempo.ConversionError{}}` for a recurrence, whose
    length is its occurrences' (convert it with `to_interval_set/2`
    first), and `{:error, reason}` for a value that is not a Tempo
    value.

  ### Examples

      iex> Tempo.duration(~o"2026-06-15T09:00/2026-06-15T10:30")
      ~o"PT90M"

      iex> Tempo.duration(~o"2026-06")
      ~o"P1M"

      iex> bookings = Tempo.IntervalSet.new!([~o"2026-06-15T09/2026-06-15T11", ~o"2026-06-15T10/2026-06-15T12"])
      iex> Tempo.duration(bookings)
      ~o"PT3H"

  """
  @spec duration(t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()) ::
          Duration.t() | :infinity | {:error, Exception.t()}
  def duration(%IntervalSet{} = set), do: IntervalSet.duration(set)

  def duration(%__MODULE__{} = value) do
    if anchored?(value) do
      with {:ok, span} <- to_interval(value), do: duration(span)
    else
      {:error, UnanchoredError.exception(operation: :duration, value: value)}
    end
  end

  def duration(%Interval{} = interval), do: Interval.duration(interval)

  # A set written as its members (`{2026Y,2028Y}`) is measured as the same
  # set written in one value is (`{2026,2028}Y`): by the spans it converts to.
  def duration(%Tempo.Set{} = set) do
    with {:ok, spans} <- to_interval(set), do: duration(spans)
  end

  def duration(value) do
    {:error,
     ArgumentError.exception("Tempo.duration/1 takes a Tempo value, got #{inspect(value)}")}
  end

  @doc """
  Return the duration between two endpoints as a `%Tempo.Duration{}`.

  A convenience that builds the interval `[from, to)` internally and
  measures it — `Tempo.duration(today, election_day)` instead of
  constructing a `t:Tempo.Interval.t/0` first. The length is counted
  in the endpoints' unit, as `Tempo.Interval.duration/1` counts it:
  days between two days, and elapsed hours between two hours, so
  midnight to midnight across a daylight-saving change is 23 or 25
  hours.

  Unlike `duration/1`, whose interval argument is valid by
  construction, this takes raw endpoints that may not form a
  measurable interval, so it returns a tagged tuple. Use
  `duration!/2` when the endpoints are known-good.

  ### Arguments

  * `from` is the start `t:Tempo.t/0` — must be anchored (carry a
    year).

  * `to` is the end `t:Tempo.t/0` — anchored, and strictly later
    than `from`.

  ### Returns

  * `{:ok, duration}` where `duration` is a `t:Tempo.Duration.t/0`.

  * `{:error, reason}` when an endpoint is unanchored, the
    endpoints are of incompatible calendars, or `from` is not
    strictly earlier than `to`.

  * `{:error, %Tempo.FloatingTempoError{}}` when one endpoint is
    zoned and the other floating: they are on different time lines,
    and `relation/2` refuses the same pair.

  ### Examples

      iex> {:ok, duration} = Tempo.duration(~o"2026-09-28", ~o"2026-11-03")
      iex> duration
      ~o"P36D"

      iex> {:ok, duration} = Tempo.duration(~o"2026-06-15T09", ~o"2026-06-15T17")
      iex> duration
      ~o"PT8H"

      iex> match?({:error, _reason}, Tempo.duration(~o"2026-06-15T17", ~o"2026-06-15T09"))
      true

  """
  @spec duration(t(), t()) :: {:ok, Duration.t()} | {:error, Exception.t()}
  def duration(%__MODULE__{} = from, %__MODULE__{} = to) do
    cond do
      not anchored?(from) ->
        {:error, UnanchoredError.exception(operation: :duration, value: from)}

      not anchored?(to) ->
        {:error, UnanchoredError.exception(operation: :duration, value: to)}

      floating?(from) != floating?(to) ->
        floating = if floating?(from), do: from, else: to
        {:error, FloatingTempoError.exception(operation: :measure, value: floating)}

      true ->
        measured_between(from, to)
    end
  end

  def duration(%__MODULE__{}, to), do: {:error, not_one_value("duration/2", to)}
  def duration(from, _to), do: {:error, not_one_value("duration/2", from)}

  # The interval from `from` to `to`, measured as `Interval.duration/2`
  # measures it.
  defp measured_between(from, to) do
    with {:ok, interval} <- Interval.new(from, to) do
      case Interval.duration(interval) do
        %Duration{} = duration -> {:ok, duration}
        {:error, _reason} = error -> error
      end
    end
  end

  @doc """
  Bang variant of `duration/2`. Raises on invalid endpoints and
  returns the `%Tempo.Duration{}` directly.

  ### Examples

      iex> Tempo.duration!(~o"2026-06-15T09", ~o"2026-06-15T17")
      ~o"PT8H"

  """
  @spec duration!(t(), t()) :: Duration.t()
  def duration!(from, to) do
    case duration(from, to) do
      {:ok, duration} -> duration
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "Tempo.duration!/2 failed: #{inspect(reason)}"
    end
  end

  @doc """
  `true` when a value is at least as long as the given duration.

  An interval, or the span a value names, is measured between its
  endpoints (see `Tempo.Interval.at_least?/2`); an interval set by the
  time it covers, from its first instant, as `duration/1` measures it.
  An unbounded interval or set is longer than any duration.

  ### Arguments

  * `value` is a `t:Tempo.Interval.t/0`, a `t:Tempo.IntervalSet.t/0` or
    a `t:t/0`.

  * `duration` is a `t:Tempo.Duration.t/0`.

  ### Returns

  * `true` or `false`. A value `to_interval/1` cannot give a span raises
    its error.

  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.at_least?(meeting, ~o"PT1H")
      true
      iex> Tempo.at_least?(meeting, ~o"PT2H")
      false

      iex> {:ok, weekends} = Tempo.select(~o"2026-06", Tempo.weekends(:AU))
      iex> Tempo.at_least?(weekends, ~o"P8D")
      true

  """
  @spec at_least?(t() | Interval.t() | IntervalSet.t(), Duration.t()) :: boolean()
  def at_least?(value, duration),
    do: length_holds?(value, duration, &Interval.at_least?/2, [:gt, :eq])

  @doc """
  `true` when a value is at most as long as the given duration,
  measured as `at_least?/2` measures it.

  ### Arguments

  * `value` is a `t:Tempo.Interval.t/0`, a `t:Tempo.IntervalSet.t/0` or
    a `t:t/0`.

  * `duration` is a `t:Tempo.Duration.t/0`.

  ### Returns

  * `true` or `false`. A value `to_interval/1` cannot give a span raises
    its error.

  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.at_most?(meeting, ~o"PT2H")
      true
      iex> Tempo.at_most?(meeting, ~o"PT1H")
      false

  """
  @spec at_most?(t() | Interval.t() | IntervalSet.t(), Duration.t()) :: boolean()
  def at_most?(value, duration),
    do: length_holds?(value, duration, &Interval.at_most?/2, [:lt, :eq])

  @doc """
  `true` when a value's length equals the given duration, measured as
  `at_least?/2` measures it.

  ### Arguments

  * `value` is a `t:Tempo.Interval.t/0`, a `t:Tempo.IntervalSet.t/0` or
    a `t:t/0`.

  * `duration` is a `t:Tempo.Duration.t/0`.

  ### Returns

  * `true` or `false`. A value `to_interval/1` cannot give a span raises
    its error.

  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.exactly?(meeting, ~o"PT90M")
      true
      iex> Tempo.exactly?(meeting, ~o"PT1H")
      false

      iex> Tempo.exactly?(~o"2026-02", ~o"P28D")
      true

  """
  @spec exactly?(t() | Interval.t() | IntervalSet.t(), Duration.t()) :: boolean()
  def exactly?(value, duration),
    do: length_holds?(value, duration, &Interval.exactly?/2, [:eq])

  @doc """
  `true` when a value is strictly longer than the given duration,
  measured as `at_least?/2` measures it.

  ### Arguments

  * `value` is a `t:Tempo.Interval.t/0`, a `t:Tempo.IntervalSet.t/0` or
    a `t:t/0`.

  * `duration` is a `t:Tempo.Duration.t/0`.

  ### Returns

  * `true` or `false`. A value `to_interval/1` cannot give a span raises
    its error.

  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.longer_than?(meeting, ~o"PT1H")
      true
      iex> Tempo.longer_than?(meeting, ~o"PT90M")
      false

  """
  @spec longer_than?(t() | Interval.t() | IntervalSet.t(), Duration.t()) :: boolean()
  def longer_than?(value, duration),
    do: length_holds?(value, duration, &Interval.longer_than?/2, [:gt])

  @doc """
  `true` when a value is strictly shorter than the given duration,
  measured as `at_least?/2` measures it.

  ### Arguments

  * `value` is a `t:Tempo.Interval.t/0`, a `t:Tempo.IntervalSet.t/0` or
    a `t:t/0`.

  * `duration` is a `t:Tempo.Duration.t/0`.

  ### Returns

  * `true` or `false`. A value `to_interval/1` cannot give a span raises
    its error.

  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.shorter_than?(meeting, ~o"PT2H")
      true
      iex> Tempo.shorter_than?(meeting, ~o"PT90M")
      false

  A week of workdays is shorter than a week:

      iex> {:ok, workdays} = Tempo.select(~o"2026-06-15/2026-06-22", Tempo.workdays(:AU))
      iex> Tempo.shorter_than?(workdays, ~o"P1W")
      true

  """
  @spec shorter_than?(t() | Interval.t() | IntervalSet.t(), Duration.t()) :: boolean()
  def shorter_than?(value, duration),
    do: length_holds?(value, duration, &Interval.shorter_than?/2, [:lt])

  # Whether a value's length stands in one of `orders` to `duration`. An
  # interval set's length is the time it covers, compared from its first
  # instant; an unbounded set is longer than any duration and an empty one
  # has none. A value's length is that of the span it names, and an
  # interval's is measured between its endpoints by `interval_predicate`.
  defp length_holds?(%IntervalSet{} = set, duration, _interval_predicate, orders),
    do: set_length_order(set, duration) in orders

  defp length_holds?(%Interval{} = interval, duration, interval_predicate, _orders),
    do: interval_predicate.(interval, duration)

  defp length_holds?(value, duration, interval_predicate, orders),
    do: length_holds?(span!(value), duration, interval_predicate, orders)

  defp set_length_order(set, duration) do
    if IntervalSet.bounded?(set),
      do: covered_length_order(IntervalSet.first(set), set, duration),
      else: :gt
  end

  defp covered_length_order(nil, _set, duration), do: zero_length_order(duration)

  defp covered_length_order(%Interval{} = first, set, duration) do
    case IntervalSet.duration(set) do
      %Duration{} = covered ->
        Duration.compare(covered, duration, relative_to: Interval.from(first))

      {:error, exception} ->
        raise exception
    end
  end

  # Nothing against `duration`: the signs of its components decide, as they
  # agree in a duration as it is written.
  defp zero_length_order(%Duration{time: time} = duration) do
    case time |> Enum.map(&component_sign/1) |> Enum.uniq() |> List.delete(0) do
      [] -> :eq
      [1] -> :lt
      [-1] -> :gt
      _mixed -> Duration.compare(%Duration{time: [second: 0]}, duration)
    end
  end

  defp component_sign({_unit, {value, _precision}}), do: amount_sign(value)
  defp component_sign({_unit, value}), do: amount_sign(value)

  defp amount_sign(value) when value > 0, do: 1
  defp amount_sign(value) when value < 0, do: -1
  defp amount_sign(_zero), do: 0

  @doc """
  `true` when both endpoints of the interval are concrete
  (neither `:undefined` nor `nil`). See `Tempo.Interval.bounded?/1`.
  ### Examples

      iex> Tempo.bounded?(Tempo.to_interval!(~o"2026-06-15"))
      true

      iex> {:ok, onwards} = Tempo.to_interval(~o"2026-01-15/..")
      iex> Tempo.bounded?(onwards)
      false

  """
  @spec bounded?(t() | Interval.t() | IntervalSet.t()) :: boolean()
  def bounded?(%Interval{} = interval), do: Interval.bounded?(interval)
  def bounded?(%IntervalSet{} = set), do: IntervalSet.bounded?(set)
  def bounded?(value), do: value |> span!() |> bounded?()

  # The interval or the interval set a value spans, for a predicate, which
  # has only true and false to give: a value with no span raises its error.
  defp span!(value) do
    case to_interval(value) do
      {:ok, span} -> span
      {:error, exception} when is_exception(exception) -> raise exception
    end
  end

  @doc """
  `true` when the interval has zero length. See
  `Tempo.Interval.empty?/1`.
  ### Examples

      iex> Tempo.empty?(Tempo.to_interval!(~o"2026-06-15"))
      false

  """
  @spec empty?(t() | Interval.t() | IntervalSet.t()) :: boolean()
  def empty?(%Interval{} = interval), do: Interval.empty?(interval)
  def empty?(%IntervalSet{} = set), do: IntervalSet.empty?(set)
  def empty?(value), do: value |> span!() |> empty?()

  @doc """
  `true` when `a` ends at or before `b` starts — the two share no
  instant and `a` is earlier. An 11:00–12:00 meeting is before a 12:00
  lunch. Allen's `:precedes`, which also needs a gap, is
  `Tempo.Allen.precedes?/2`. See `Tempo.Interval.before?/2`.

  ### Examples

      iex> Tempo.before?(~o"2026-01", ~o"2026-03")
      true

  Adjacent months share no instant, so January is before February:

      iex> Tempo.before?(~o"2026-01", ~o"2026-02")
      true

  """
  defdelegate before?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` starts at or after `b` ends — the two share no
  instant and `a` is later. Allen's `:preceded_by`, which also needs a
  gap, is `Tempo.Allen.preceded_by?/2`. See `Tempo.Interval.after?/2`.

  ### Examples

      iex> Tempo.after?(~o"2026-03", ~o"2026-01")
      true

      iex> Tempo.after?(~o"2026-01", ~o"2026-03")
      false

  """
  defdelegate after?(a, b), to: Tempo.Interval

  @doc """
  `true` when the two intervals touch at a single boundary
  (Allen's `:meets | :met_by`). See `Tempo.Interval.adjacent?/2`.
  ### Examples

      iex> Tempo.adjacent?(~o"2026-02", ~o"2026-01")
      true

      iex> Tempo.adjacent?(~o"2026-01", ~o"2026-03")
      false

  """
  defdelegate adjacent?(a, b), to: Tempo.Interval

  @doc """
  `true` when every instant of `a` is also in `b` — `a` fits inside
  `b`, shared ends included. The canonical "does this fit inside that
  window?" predicate, for single values and sets alike; see
  `Tempo.Operations.within?/3`.

  `within?/3` asks about the whole of `a`. The `:within` option of
  `to_interval_set/2` and the set operations is looser: it keeps
  every occurrence that overlaps its window, one already in
  progress when the window opens included. Allen's strict `:during`
  is `Tempo.Allen.during?/2`.

  ### Examples

      iex> Tempo.within?(~o"2026-06-01/2026-06-15", ~o"2026-06")
      true

      iex> Tempo.within?(~o"2026-06", ~o"2026-06")
      true

      iex> Tempo.within?(~o"2026-06", ~o"2026-06-15")
      false

  """
  defdelegate within?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  The three-valued certainty that `a` and `b` intersect, given their
  `±` margins. See `Tempo.Interval.overlap_certainty/2`.
  ### Examples

      iex> Tempo.overlap_certainty(~o"2026-06", ~o"2026-06-15")
      :certain

      iex> Tempo.overlap_certainty(~o"2000±1Y", ~o"2001±1Y")
      :possible

      iex> Tempo.overlap_certainty(~o"2000±1Y", ~o"2010±1Y")
      :impossible

  """
  defdelegate overlap_certainty(a, b), to: Tempo.Interval

  @doc """
  The three-valued certainty that `a` falls within `b`, given their
  `±` margins. See `Tempo.Interval.within_certainty/2`.
  ### Examples

      iex> Tempo.within_certainty(~o"20XX", ~o"2000Y/2100Y")
      :certain

  One grounding (2000) escapes a span starting at 2001, so within is
  only possible:

      iex> Tempo.within_certainty(~o"20XX", ~o"2001Y/2101Y")
      :possible

  """
  defdelegate within_certainty(a, b), to: Tempo.Interval

  @doc """
  The three-valued certainty that `relation(a, b)` is (one of) `target`.
  See `Tempo.Interval.relation_certainty/3`.
  ### Examples

      iex> Tempo.relation_certainty(~o"20XX", ~o"2200", :precedes)
      :certain

      iex> Tempo.relation_certainty(~o"20XX", ~o"2050", :precedes)
      :possible

  """
  defdelegate relation_certainty(a, b, target), to: Tempo.Interval

  @doc """
  `true` when `a` and `b` intersect for *every* placement of their `±`
  margins. See `Tempo.Interval.certainly_overlaps?/2`.
  ### Examples

      iex> Tempo.certainly_overlaps?(~o"2000±1Y", ~o"2001±1Y")
      false

      iex> Tempo.certainly_overlaps?(~o"2026-06", ~o"2026-06-15")
      true

  """
  defdelegate certainly_overlaps?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` and `b` *could* intersect for some placement of their
  `±` margins. See `Tempo.Interval.possibly_overlaps?/2`.
  ### Examples

      iex> Tempo.possibly_overlaps?(~o"2000±1Y", ~o"2001±1Y")
      true

      iex> Tempo.possibly_overlaps?(~o"2000±1Y", ~o"2010±1Y")
      false

  """
  defdelegate possibly_overlaps?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` falls within `b` for *every* placement of their `±`
  margins. See `Tempo.Interval.certainly_within?/2`.
  ### Examples

      iex> Tempo.certainly_within?(~o"2000±1Y", ~o"1990Y/2010Y")
      true

      iex> Tempo.certainly_within?(~o"2000±1Y", ~o"2000Y")
      false

  """
  defdelegate certainly_within?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` *could* fall within `b` for some placement of their
  `±` margins. See `Tempo.Interval.possibly_within?/2`.
  ### Examples

      iex> Tempo.possibly_within?(~o"2000±1Y", ~o"2000Y")
      true

  """
  defdelegate possibly_within?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` ends before `b` starts for *every* placement of their
  `±` margins. See `Tempo.Interval.certainly_before?/2`.
  ### Examples

      iex> Tempo.certainly_before?(~o"2000±1Y", ~o"2010")
      true

      iex> Tempo.certainly_before?(~o"2000±1Y", ~o"2001")
      false

  """
  defdelegate certainly_before?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` *could* end before `b` starts for some placement of
  their `±` margins. See `Tempo.Interval.possibly_before?/2`.
  ### Examples

      iex> Tempo.possibly_before?(~o"2000±1Y", ~o"2001")
      true

  """
  defdelegate possibly_before?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` starts after `b` ends for *every* placement of their
  `±` margins. See `Tempo.Interval.certainly_after?/2`.
  ### Examples

      iex> Tempo.certainly_after?(~o"2010±1Y", ~o"2000")
      true

      iex> Tempo.certainly_after?(~o"2001±1Y", ~o"2000")
      false

  """
  defdelegate certainly_after?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` *could* start after `b` ends for some placement of
  their `±` margins. See `Tempo.Interval.possibly_after?/2`.
  ### Examples

      iex> Tempo.possibly_after?(~o"2001±1Y", ~o"2000")
      true

  """
  defdelegate possibly_after?(a, b), to: Tempo.Interval

  @doc """
  Narrow a Tempo span by a selector — the composition primitive
  for "workdays of June", "the 15th of every month", and similar
  queries.

  `Tempo.select/2` is a **pure function**: the selector is a value,
  not an ambient configuration. Locale-dependent constraints are
  constructed by `Tempo.workdays/1` and `Tempo.weekends/1` and
  composed in at the call site.

  A span is selected period by period at its start's resolution, so
  the Christmases of `~o"2026/2029"` are three. An open-ended span
  (`~o"2026-06-15/.."`) gives a lazy set, walked as far as it is
  taken. What is selected keeps the metadata of what it is selected
  from. See `Tempo.Select` for the full vocabulary.

  A computed event is selected from the year, the month or the week it falls in (`Tempo.select(~o"2026Y4M", ~o"L(easter)eN")` is 5 April). One with no date where it is asked for, a year it is not computed for or a name no resolver knows, is `{:error, %Tempo.EventError{}}`.

  ### Examples

      iex> {:ok, set} = Tempo.select(~o"2026-02", [1, 15])
      iex> set |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [1, 15]

      iex> {:ok, set} = Tempo.select(~o"2026", ~o"12-25")
      iex> [xmas] = Tempo.IntervalSet.members(set)
      iex> from = Tempo.Interval.from(xmas)
      iex> {Tempo.year(from), Tempo.month(from), Tempo.day(from)}
      {2026, 12, 25}

  The school days of a term are tagged with the term:

      iex> {:ok, term} = Tempo.Interval.new(from: ~o"2027-07-19", to: ~o"2027-07-21", metadata: %{term: 3})
      iex> {:ok, days} = Tempo.select(term, Tempo.workdays(:AU))
      iex> days |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.metadata/1)
      [%{term: 3}, %{term: 3}]

  """
  defdelegate select(base, selector), to: Tempo.Select

  @doc """
  Raising version of `select/2`.

  ### Arguments

  * `base` and `selector` — see `select/2`.

  ### Returns

  * The selected `t:Tempo.IntervalSet.t/0`.

  ### Examples

      iex> Tempo.select!(~o"2026-06", [15])
      #Tempo.IntervalSet<[#Tempo.Interval<~o"2026Y6M15D/16D" unit: hour>]>

  """
  @spec select!(
          t() | Tempo.Interval.t() | Tempo.IntervalSet.t(),
          Tempo.Select.selector()
        ) :: Tempo.IntervalSet.t()
  def select!(base, selector) do
    case select(base, selector) do
      {:ok, set} -> set
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  @doc """
  Return a selector for the workdays of a territory: the days of the
  week outside its weekend, less any holidays.

  Together `workdays/1` and `weekends/1` partition the week. In the
  United States the workdays are Monday to Friday and the weekends
  Saturday and Sunday; in Saudi Arabia the workdays are Sunday to
  Thursday. With `:except`, the workdays leave out a set of holidays
  too: a territory's public holidays make its business days, a
  school's its school days.

  ### Arguments

  * `territory` is an atom, string, locale, or `%Localize.LanguageTag{}`
    resolved through `Tempo.Territory.resolve/1`. The default, `nil`,
    walks the territory-resolution chain (app config, then ambient
    locale).

  * `options` is a keyword list of options.

  ### Options

  * `:except` is the holidays the workdays leave out: anything
    `Tempo.to_interval_set/2` converts, such as a
    `t:Tempo.RecurrenceSet.t/0` of recurring holidays, an interval set
    or a single day.

  ### Returns

  * A `t:Tempo.t/0` value naming the workdays by day of week, to pass
    to `Tempo.select/2`.

  * With `:except`, a `t:Tempo.Workdays.t/0`, which `Tempo.select/2`
    and the workday functions (`add_workdays/3`, `next_workday/2`,
    `previous_workday/2`, `nearest_workday/2`, `count_workdays/2`,
    `workday?/2`) take in place of a territory.

  * `{:error, reason}` when the territory cannot be resolved or an
    option is not one this takes. `Tempo.select/2` returns such an
    error as it is, so a pipeline reports it.

  ### Examples

      iex> {:ok, workdays} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      iex> Tempo.IntervalSet.count(workdays)
      20

      iex> {:ok, workdays} = Tempo.select(~o"2026-06-15/2026-06-22", Tempo.workdays(:SA))
      iex> workdays |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [15, 16, 17, 18, 21]

  Leaving out the King's Birthday, June 2026 has 21 Australian
  workdays, one fewer than its weekdays:

      iex> business_days = Tempo.workdays(:AU, except: ~o"2026-06-08")
      iex> Tempo.count_workdays(~o"2026-06", business_days)
      21

  """
  @spec workdays(Tempo.Territory.input(), keyword()) ::
          t() | Tempo.Workdays.t() | {:error, error_reason()}
  def workdays(territory \\ nil, options \\ []) do
    with {:ok, resolved} <- Territory.resolve(territory),
         {:ok, except} <- workdays_except(options) do
      workdays_of(resolved, except)
    end
  end

  defp workdays_of(resolved, nil), do: day_of_week_tempo(Localize.Calendar.weekdays(resolved))

  defp workdays_of(resolved, except) do
    %Tempo.Workdays{
      weekdays: Localize.Calendar.weekdays(resolved),
      weekend: Localize.Calendar.weekend(resolved),
      except: except
    }
  end

  defp workdays_except(options) do
    with true <- Keyword.keyword?(options),
         [] <- Keyword.keys(options) -- [:except],
         except = Keyword.get(options, :except),
         true <- holiday_set?(except) do
      {:ok, except}
    else
      _invalid ->
        {:error,
         ArgumentError.exception(
           "Tempo.workdays/2 takes one option, :except, a Tempo value, interval, " <>
             "interval set or recurrence set, not #{inspect(options)}."
         )}
    end
  end

  defp holiday_set?(nil), do: true

  defp holiday_set?(%struct{})
       when struct in [__MODULE__, Interval, IntervalSet, Tempo.RecurrenceSet],
       do: true

  defp holiday_set?(_other), do: false

  @doc """
  Return a selector for the weekends of a territory.

  Territories take their weekend on different days: the United States
  on Saturday and Sunday, Saudi Arabia on Friday and Saturday, India on
  Sunday. `weekends/1` reads a territory's weekend from CLDR through
  Localize and returns it as a selector for `Tempo.select/2`.

  ### Arguments

  * `territory` is an atom, string, locale, or `%Localize.LanguageTag{}`
    resolved through `Tempo.Territory.resolve/1`. The default, `nil`,
    walks the territory-resolution chain.

  ### Returns

  * A `t:Tempo.t/0` value naming the weekend by day of week, to pass to
    `Tempo.select/2`.

  * `{:error, reason}` when the territory cannot be resolved.
    `Tempo.select/2` returns such an error as it is.

  ### Examples

      iex> {:ok, weekends} = Tempo.select(~o"2026-02", Tempo.weekends(:US))
      iex> weekends |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [1, 7, 8, 14, 15, 21, 22, 28]

      iex> {:ok, weekends} = Tempo.select(~o"2026-02", Tempo.weekends(:SA))
      iex> weekends |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [6, 7, 13, 14, 20, 21, 27, 28]

  From a date on, the weekends are a lazy set that walks only as far as
  it is taken. Three days of machine time from Thursday at 16:00, with
  the weekends skipped, run to Tuesday at 16:00:

      iex> {:ok, weekends} = Tempo.select(~o"2026-06-18/..", Tempo.weekends(:US))
      iex> weekends |> Tempo.IntervalSet.walk() |> Enum.take(3) |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [20, 21, 27]
      iex> Tempo.shift(~o"2026-06-18T16:00", ~o"P3D", skipping: weekends)
      ~o"2026Y6M23DT16H0M0S"

  """
  @spec weekends(Tempo.Territory.input()) :: t() | {:error, error_reason()}
  def weekends(territory \\ nil) do
    with {:ok, resolved} <- Territory.resolve(territory) do
      day_of_week_tempo(Localize.Calendar.weekend(resolved))
    end
  end

  defp day_of_week_tempo(days) when is_list(days) do
    %Tempo{time: [day_of_week: days], calendar: Calendrical.Gregorian}
  end

  @doc """
  Return `true` when `tempo` falls on a weekend day in the given
  territory.

  Different territories weekend on different days — the United States
  on `[Saturday, Sunday]`, Saudi Arabia on `[Friday, Saturday]`, India
  on `[Sunday]` — read from CLDR via Localize. The value's date is
  converted to `Calendar.ISO` first and the day of week read as ISO
  (`1` = Monday … `7` = Sunday), so a non-Gregorian value (Japanese,
  Islamic, Hebrew, …) is classified by the correct weekday regardless
  of its calendar's own weekday numbering — Hebrew and Islamic weeks
  number from Sunday and Persian from Saturday, while CLDR's weekend
  data is ISO-numbered.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a single day — a date or
    datetime, including the day-of-year and week-date forms.

  * `territory` is an atom, string, locale, or `%Localize.LanguageTag{}`
    resolved through `Tempo.Territory.resolve/1`. Defaults to `nil`,
    which walks the territory-resolution chain (app config, then
    ambient locale).

  ### Returns

  * `true` when the value's day of week is one of the territory's
    weekend days, `false` otherwise.

  * Raises when `tempo` does not denote a day (a year or a month, or a
    value without a year) or the territory cannot be resolved. The
    workday functions, such as `add_workdays/3`, return these errors
    instead.

  ### Examples

      iex> Tempo.weekend?(~o"2026-06-13", :US)
      true

      iex> Tempo.weekend?(~o"2026-06-15", :US)
      false

      iex> # The same Friday: a weekend in Saudi Arabia, a workday in the US.
      iex> Tempo.weekend?(~o"2026-06-12", :SA)
      true
      iex> Tempo.weekend?(~o"2026-06-12", :US)
      false

  """
  @spec weekend?(t(), Tempo.Territory.input() | Tempo.Workdays.t()) :: boolean()
  def weekend?(tempo, territory \\ nil)

  def weekend?(%Tempo{} = tempo, territory), do: on_weekend?(tempo, territory, :weekend?)
  def weekend?(value, _territory), do: raise(not_one_value("weekend?/2", value))

  @doc """
  Return `true` when `tempo` falls on a workday — a day that is *not*
  in the territory's weekend, nor one of the holidays of the workdays
  `workdays/2` builds with `:except`.

  Given a territory, the complement of `weekend?/2`: together they
  partition the week.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a single day.

  * `territory` is resolved through `Tempo.Territory.resolve/1`, as for
    `weekend?/2`, or is a `t:Tempo.Workdays.t/0` from `workdays/2`.

  ### Returns

  * `true` when the value's day of week is not a weekend day in the
    territory, `false` otherwise.

  * Raises as `weekend?/2` does.

  ### Examples

      iex> Tempo.workday?(~o"2026-06-15", :US)
      true

      iex> Tempo.workday?(~o"2026-06-13", :US)
      false

  """
  @spec workday?(t(), Tempo.Territory.input() | Tempo.Workdays.t()) :: boolean()
  def workday?(tempo, territory \\ nil)

  def workday?(%Tempo{} = tempo, territory) do
    answer = with {:ok, days_off} <- days_off(territory), do: day_off?(tempo, days_off, :workday?)
    not predicate_answer!(answer)
  end

  def workday?(value, _territory), do: raise(not_one_value("workday?/2", value))

  # Whether `tempo` falls on the territory's weekend.
  defp on_weekend?(tempo, territory, function) do
    answer =
      with {:ok, day_of_week, weekend} <- weekday_and_weekend(tempo, territory, function),
           do: {:ok, day_of_week in weekend}

    predicate_answer!(answer)
  end

  # A predicate has only true and false to give, so a question with no
  # answer raises.
  defp predicate_answer!({:ok, answer}), do: answer
  defp predicate_answer!({:error, exception}) when is_exception(exception), do: raise(exception)
  defp predicate_answer!({:error, reason}), do: raise(ArgumentError, inspect(reason))

  @doc """
  Shift `tempo` by `count` workdays, stepping over the territory's
  weekend.

  A positive `count` moves forward, a negative one backward, and `0`
  returns the value unchanged. Each step lands on a workday, so one
  workday after a Friday is the following Monday where the weekend is
  Saturday and Sunday. The time of day, calendar and zone are kept.
  Given the workdays `workdays/2` builds with `:except`, it steps over
  their holidays too.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a day: a date or a datetime.

  * `count` is the number of workdays to add, negative to go back.

  * `territory` is resolved through `Tempo.Territory.resolve/1`, as for
    `weekend?/2`, or is a `t:Tempo.Workdays.t/0` from `workdays/2`.

  ### Returns

  * The `t:t/0` that is `count` workdays from `tempo`.

  * `{:error, reason}` when `tempo` does not denote a day (a
    `Tempo.ResolutionError` for a year or a month, a
    `Tempo.UnanchoredError` for a value without a year), the territory
    cannot be resolved, the holidays cannot be converted around a day,
    or more than a thousand days off fall in a row.

  ### Examples

      iex> Tempo.add_workdays(~o"2026-06-12", 1, :US)
      ~o"2026Y6M15D"

      iex> Tempo.add_workdays(~o"2026-06-15", -1, :US)
      ~o"2026Y6M12D"

      iex> # Five workdays on from a Monday is the next Monday.
      iex> Tempo.add_workdays(~o"2026-06-15", 5, :US)
      ~o"2026Y6M22D"

      iex> # The weekend differs by territory (Saudi Arabia: Friday and Saturday).
      iex> Tempo.add_workdays(~o"2026-06-11", 1, :SA)
      ~o"2026Y6M14D"

  """
  @spec add_workdays(t(), integer(), Tempo.Territory.input() | Tempo.Workdays.t()) ::
          t() | {:error, error_reason()}
  def add_workdays(tempo, count, territory \\ nil) do
    workdays_from(tempo, count, territory, :add_workdays)
  end

  @doc """
  The next workday after `tempo` in the territory.

  The same as `add_workdays(tempo, 1, territory)`.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a day.

  * `territory` is resolved through `Tempo.Territory.resolve/1`, or is a
    `t:Tempo.Workdays.t/0` from `workdays/2`.

  ### Returns

  * The next workday, or `{:error, reason}` as for `add_workdays/3`.

  ### Examples

      iex> Tempo.next_workday(~o"2026-06-12", :US)
      ~o"2026Y6M15D"

  With Monday 26 April a holiday, the next workday after Friday 23 April
  2027 is the Tuesday:

      iex> business_days = Tempo.workdays(:AU, except: ~o"2027-04-26")
      iex> Tempo.next_workday(~o"2027-04-23", business_days)
      ~o"2027Y4M27D"

  """
  @spec next_workday(t(), Tempo.Territory.input() | Tempo.Workdays.t()) ::
          t() | {:error, error_reason()}
  def next_workday(tempo, territory \\ nil) do
    workdays_from(tempo, 1, territory, :next_workday)
  end

  @doc """
  The workday before `tempo` in the territory.

  The same as `add_workdays(tempo, -1, territory)`.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a day.

  * `territory` is resolved through `Tempo.Territory.resolve/1`, or is a
    `t:Tempo.Workdays.t/0` from `workdays/2`.

  ### Returns

  * The previous workday, or `{:error, reason}` as for `add_workdays/3`.

  ### Examples

      iex> Tempo.previous_workday(~o"2026-06-15", :US)
      ~o"2026Y6M12D"

  """
  @spec previous_workday(t(), Tempo.Territory.input() | Tempo.Workdays.t()) ::
          t() | {:error, error_reason()}
  def previous_workday(tempo, territory \\ nil) do
    workdays_from(tempo, -1, territory, :previous_workday)
  end

  @doc """
  The workday nearest to `tempo` in the territory: `tempo` itself when
  it is a workday, otherwise the closest day outside the territory's
  weekend.

  The nearer workday wins, and a tie goes to the day before. For a
  two-day weekend this is the common observed-holiday rule — a Saturday
  moves back to Friday, a Sunday forward to Monday — which is how a
  fixed-date holiday such as US Independence Day is observed when it
  falls on a weekend.

  Given the workdays `workdays/2` builds with `:except`, a holiday is
  stepped over too, so Good Friday's nearest school day is the Thursday,
  and a day in the school holidays finds the nearer end of the break.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a day.

  * `territory` is resolved through `Tempo.Territory.resolve/1` and
    sets which days are the weekend, or is a `t:Tempo.Workdays.t/0`
    from `workdays/2`.

  ### Returns

  * `tempo` when it is a workday, otherwise the nearest workday.

  * `{:error, reason}` as for `add_workdays/3`.

  ### Examples

      iex> Tempo.nearest_workday(~o"2026-07-04", :US)
      ~o"2026Y7M3D"

      iex> Tempo.nearest_workday(~o"2027-07-04", :US)
      ~o"2027Y7M5D"

      iex> Tempo.nearest_workday(~o"2025-07-04", :US)
      ~o"2025Y7M4D"

  """
  @spec nearest_workday(t(), Tempo.Territory.input() | Tempo.Workdays.t()) ::
          t() | {:error, error_reason()}
  def nearest_workday(tempo, territory \\ nil)

  def nearest_workday(%Tempo{} = tempo, territory) do
    with :ok <- one_value(tempo),
         {:ok, days_off} <- days_off(territory),
         {:ok, off?} <- day_off?(tempo, days_off, :nearest_workday) do
      if off?, do: nearest_workday_from(tempo, days_off, 1), else: tempo
    end
  end

  def nearest_workday(value, _territory), do: {:error, not_a_day(value, :nearest_workday)}

  @doc """
  Count the workdays of a span: its days outside the territory's
  weekend.

  The span is half-open, so the day it ends on is not counted. Given
  the workdays `workdays/2` builds with `:except`, their holidays are
  left out too.

  ### Arguments

  * `value` is anything `Tempo.select/2` selects from: a `t:t/0`, a
    `t:Tempo.Interval.t/0` or a `t:Tempo.IntervalSet.t/0`.

  * `territory` is resolved through `Tempo.Territory.resolve/1`, or is a
    `t:Tempo.Workdays.t/0` from `workdays/2`.

  ### Returns

  * The number of workdays in `value`.

  * `{:error, reason}` when the territory cannot be resolved, `value`
    cannot be selected from, or it has no end to count to (a
    `Tempo.UnboundedSetError`).

  ### Examples

      iex> Tempo.count_workdays(~o"2026-06", :US)
      22

      iex> Tempo.count_workdays(~o"2026-06-15/2026-06-22", :SA)
      5

  """
  @spec count_workdays(
          t() | Tempo.Interval.t() | IntervalSet.t(),
          Tempo.Territory.input() | Tempo.Workdays.t()
        ) :: non_neg_integer() | {:error, error_reason()}
  def count_workdays(value, territory \\ nil) do
    with {:ok, selector} <- workday_selector(territory),
         {:ok, %IntervalSet{} = selected} <- select(value, selector) do
      count_selected(selected)
    end
  end

  defp workday_selector(%Tempo.Workdays{} = workdays), do: {:ok, workdays}

  defp workday_selector(territory) do
    case workdays(territory) do
      %Tempo{} = selector -> {:ok, selector}
      {:error, _reason} = error -> error
    end
  end

  defp count_selected(selected) do
    if IntervalSet.bounded?(selected) do
      IntervalSet.count(selected)
    else
      {:error, UnboundedSetError.exception(operation: "Tempo.count_workdays/2", set: selected)}
    end
  end

  defp workdays_from(%Tempo{} = tempo, count, territory, function) when is_integer(count) do
    with {:ok, days_off} <- days_off(territory),
         {:ok, _day_of_week} <- iso_day_of_week(tempo, function) do
      step_workdays(tempo, count, days_off, function)
    end
  end

  defp workdays_from(%Tempo{}, count, _territory, function) do
    {:error,
     ArgumentError.exception("`#{function}` counts whole workdays, not #{inspect(count)}.")}
  end

  defp workdays_from(value, _count, _territory, function),
    do: {:error, not_a_day(value, function)}

  # Step `count` workdays from `tempo`, one day at a time.
  defp step_workdays(tempo, 0, _days_off, _function), do: tempo

  defp step_workdays(tempo, count, days_off, function) do
    step = if count < 0, do: -1, else: 1

    Enum.reduce_while(1..abs(count), tempo, fn _workday, day ->
      case workday_after(day, step, days_off, function, 1) do
        %Tempo{} = next -> {:cont, next}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # The most days off in a row a step passes before it gives up, so a
  # holiday set that never ends cannot hold it forever.
  @most_days_off_in_a_row 1_000

  # The first workday `step` days on from `tempo` (a step of -1 goes back).
  defp workday_after(tempo, _step, _days_off, _function, run)
       when run > @most_days_off_in_a_row do
    {:error,
     ArgumentError.exception(
       "No workday follows #{inspect(tempo)} within #{@most_days_off_in_a_row} days off."
     )}
  end

  defp workday_after(tempo, step, days_off, function, run) do
    next = shift(tempo, day: step)

    with {:ok, off?} <- day_off?(next, days_off, function) do
      if off?, do: workday_after(next, step, days_off, function, run + 1), else: next
    end
  end

  # The workday `distance` days before `tempo`, else the one `distance`
  # days after, else one day further out each way.
  defp nearest_workday_from(tempo, days_off, distance)
       when distance <= @most_days_off_in_a_row do
    preceding = shift(tempo, day: -distance)
    following = shift(tempo, day: distance)

    with {:ok, preceding_off?} <- day_off?(preceding, days_off, :nearest_workday),
         {:ok, following_off?} <- day_off?(following, days_off, :nearest_workday) do
      cond do
        not preceding_off? -> preceding
        not following_off? -> following
        true -> nearest_workday_from(tempo, days_off, distance + 1)
      end
    end
  end

  defp nearest_workday_from(tempo, _days_off, _distance) do
    {:error,
     ArgumentError.exception(
       "No workday falls within #{@most_days_off_in_a_row} days of #{inspect(tempo)}."
     )}
  end

  # The ISO day of week (1 = Monday … 7 = Sunday) of the day `tempo`
  # denotes, and the ISO days of the territory's weekend.
  defp weekday_and_weekend(tempo, territory, function) do
    with {:ok, {weekend, _except}} <- days_off(territory),
         {:ok, day_of_week} <- iso_day_of_week(tempo, function) do
      {:ok, day_of_week, weekend}
    end
  end

  # The days a territory, or a `Tempo.Workdays`, has off: its weekend and
  # any holidays.
  defp days_off(%Tempo.Workdays{weekend: weekend, except: except}), do: {:ok, {weekend, except}}

  defp days_off(territory) do
    with {:ok, resolved} <- Territory.resolve(territory),
         do: {:ok, {Localize.Calendar.weekend(resolved), nil}}
  end

  # Whether a day is off: on the weekend or on a holiday.
  defp day_off?(day, {weekend, except}, function) do
    with {:ok, day_of_week} <- iso_day_of_week(day, function) do
      if day_of_week in weekend, do: {:ok, true}, else: on_holiday?(day, except)
    end
  end

  defp on_holiday?(_day, nil), do: {:ok, false}

  # The holidays converted around the day, as a recurrence needs a window;
  # a concrete holiday is what it is, so the day asks which overlap it.
  defp on_holiday?(day, except) do
    with {:ok, %IntervalSet{} = holidays} <- to_interval_set(except, within: day),
         {:ok, %IntervalSet{} = on_the_day} <- members_overlapping(holidays, day),
         do: {:ok, IntervalSet.count(on_the_day) > 0}
  end

  # ISO day of week (1 = Monday … 7 = Sunday) of the day a value
  # denotes. The day of week is the same in every calendar, but a
  # calendar date carries year/month/day in *its own* calendar, so the
  # date is built in that calendar and then converted to `Calendar.ISO`
  # before reading `Date.day_of_week/1` — ISO's default numbering is a
  # stable Monday-based 1..7, whereas a Calendrical calendar's own
  # `day_of_week` may use a different week start or only support the
  # `:default` ordering. The ordinal (day-of-year) and ISO week-date
  # forms resolve through `to_date/1`.
  defp iso_day_of_week(%Tempo{} = tempo, function) do
    with {:ok, date} <- day_date(tempo),
         {:ok, iso_date} <- Date.convert(date, Calendar.ISO) do
      {:ok, Date.day_of_week(iso_date)}
    else
      _no_single_day -> {:error, not_a_day(tempo, function)}
    end
  end

  defp iso_day_of_week({:error, _reason} = error, _function), do: error
  defp iso_day_of_week(value, function), do: {:error, not_a_day(value, function)}

  defp day_date(%Tempo{time: time} = tempo) do
    case {whole_unit(time, :year), whole_unit(time, :month), whole_unit(time, :day)} do
      {year, month, day} when is_integer(year) and is_integer(month) and is_integer(day) ->
        Date.new(year, month, day, calendar_of(tempo))

      _ordinal_or_week_date ->
        to_date(tempo)
    end
  end

  # A unit as the one whole number it is, or `nil` for one that is absent or
  # holds several values. A group of a set is a three-element entry, which
  # `Keyword.get/2` cannot read.
  defp whole_unit(time, unit) do
    case List.keyfind(time, unit, 0) do
      {^unit, value} when is_integer(value) -> value
      _absent_or_several -> nil
    end
  end

  defp not_a_day(%Tempo{} = tempo, function) do
    if anchored?(tempo) do
      ResolutionError.exception(
        operation: function,
        current: tempo |> resolution() |> elem(0),
        target: :day,
        reason:
          "`#{function}` needs a value that denotes a day, such as a date or a datetime; " <>
            "#{inspect(tempo)} does not."
      )
    else
      UnanchoredError.exception(operation: function, value: tempo)
    end
  end

  defp not_a_day(value, function) do
    ArgumentError.exception(
      "`#{function}` needs a Tempo value that denotes a day, not #{inspect(value)}."
    )
  end

  @doc """
  Return a multi-line prose explanation of any Tempo value — what it is, what it spans, and how to work with it.

  For structured output that renderers can style (ANSI, HTML), use `Tempo.Explain.explain/1` directly and pick a formatter. A recurrence set is described member by member, each led by its name; a week by its number, with the days it spans; a month by the name its calendar gives it; and a value holding a set or a group by each value it names.

  ### Arguments

  * `value` is any Tempo value: a `t:Tempo.t/0`, an interval, a set, a duration or a recurrence set. Anything else is described as a value Tempo does not know.

  ### Returns

  * A plain multi-line string, suitable for iex.

  ### Examples

      iex> Tempo.explain(~o"2026-06") |> String.split("\\n") |> hd()
      "June 2026."

      iex> Tempo.explain(~o"2026-W25") |> String.split("\\n") |> Enum.take(2)
      ["Week 25 of 2026.", "Span: [2026-06-15, 2026-06-22)."]

  """
  @spec explain(term()) :: String.t()
  def explain(value) do
    value |> Explain.explain() |> Explain.to_string()
  end

  @valid_units Unit.units()

  @doc false
  def validate_unit(unit) when unit in @valid_units do
    {:ok, unit}
  end

  def validate_unit(unit) do
    {:error, InvalidUnitError.exception(unit: unit, valid_units: @valid_units)}
  end
end
