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
  alias Tempo.Clock
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Enumeration
  alias Tempo.Enumeration.Zone
  alias Tempo.Explain
  alias Tempo.FloatingTempoError
  alias Tempo.Interval
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
  alias Tempo.Mask
  alias Tempo.MaterialisationError
  alias Tempo.Math
  alias Tempo.RecurrenceSet.Conditional
  alias Tempo.ResolutionError
  alias Tempo.Rounding
  alias Tempo.RRule.Encoder
  alias Tempo.RRule.Selection
  alias Tempo.Split
  alias Tempo.Territory
  alias Tempo.TimeZoneDatabase
  alias Tempo.UnanchoredError
  alias Tempo.UnboundedRecurrenceError
  alias Tempo.UnknownZoneError
  alias Tempo.Validation
  alias Tempo.ZonedTempoError

  defstruct [:time, :shift, :calendar, :extended, :qualification, :qualifications, metadata: %{}]

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
  Extended information parsed from an IXDTF suffix.

  * `:calendar` — calendar identifier atom derived from `u-ca=`.

  * `:zone_id` — IANA time zone name such as `"Europe/Paris"`.

  * `:zone_offset` — numeric offset in minutes from `[+HH:MM]`.

  * `:tags` — map of non-`u-ca` elective tagged suffixes.

  """
  @type extended_info :: %{
          calendar: atom() | nil,
          zone_id: String.t() | nil,
          zone_offset: integer() | nil,
          zone_critical: boolean(),
          tags: %{optional(String.t()) => [String.t()]}
        }

  @typedoc """
  ISO 8601-2 / EDTF date qualification.

  * `:uncertain` — the value is uncertain (`?`).

  * `:approximate` — the value is approximate (`~`), e.g. "circa".

  * `:uncertain_and_approximate` — both (`%`).

  * `nil` when no qualification was supplied.

  """
  @type qualification ::
          :uncertain | :approximate | :uncertain_and_approximate | nil

  @typedoc """
  Per-component qualifications parsed from an EDTF Level 2 date.

  A map from the component unit (`:year`, `:month`, `:day`) to its
  qualification atom. `nil` when no component-level qualification
  was present in the parsed string.

  """
  @type qualifications :: %{optional(atom()) => qualification()} | nil

  @type t :: %__MODULE__{
          time: token_list(),
          shift: time_shift(),
          calendar: Calendar.calendar() | nil,
          extended: extended_info() | nil,
          qualification: qualification(),
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
    :second
  ]

  @time_axis_units [:hour, :minute, :second]
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

  Every component value must be an integer.

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

  * `:hour` is the clock hour `0..23`.

  * `:minute` is the clock minute `0..59`.

  * `:second` is the clock second `0..59` (or `60` on a leap-second date).

  ### Options

  * `:calendar` is the `Calendrical` calendar module used to
    interpret and validate the components. Defaults to
    `Calendrical.Gregorian`.

  * `:zone` is an IANA time-zone name as a binary (e.g.
    `"Australia/Sydney"`). Sets `extended.zone_id`. Requires at
    least one of `:hour`, `:minute`, `:second` to be present —
    a zoned value without a time of day has no UTC projection.

  * `:shift` is a manual UTC offset expressed as `[hour: n]` or
    `[hour: n, minute: m]`.

  * `:qualification` marks the value's EDTF qualification.
    One of `:uncertain`, `:approximate`, or
    `:uncertain_and_approximate`.

  * `:metadata` is a map of the caller's own data carried with the
    value (a holiday name, a source), read with `metadata/1`. It is
    not part of the value's ISO 8601 form: `to_iso8601/1` leaves it
    out, and materialising the value (`to_interval/2`) moves it to
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

      iex> {:ok, ww} = Tempo.new(year: 2026, week: 24, day_of_week: 3)
      iex> ww.time
      [year: 2026, week: 24, day_of_week: 3]

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
         :ok <- validate_zone_requires_time(components, options),
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

        not is_integer(value) ->
          {:halt,
           {:error,
            InvalidDateError.exception(
              unit: unit,
              value: value,
              reason: "must be an integer"
            )}}

        true ->
          {:cont, :ok}
      end
    end)
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

  defp validate_zone_requires_time(components, options) do
    zone = Keyword.get(options, :zone)
    has_time_of_day? = Enum.any?(Keyword.keys(components), &(&1 in @time_axis_units))

    if zone && not has_time_of_day? do
      {:error,
       ArgumentError.exception(
         ":zone requires at least one of #{inspect(@time_axis_units)} — a " <>
           "zoned value without a time of day has no UTC projection."
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
  # date `2026-166` parses to, from Calendrical.
  defp day_of_year_to_date(components, options) do
    case Keyword.pop(components, :day_of_year) do
      {nil, components} ->
        {:ok, components}

      {day_of_year, components} ->
        calendar = Keyword.get(options, :calendar) || Calendrical.Gregorian
        ordinal_date(components, day_of_year, calendar)
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
       qualification: qualification,
       qualifications: nil,
       metadata: Keyword.get(options, :metadata, %{})
     }}
  end

  # A value with neither a zone nor a tag carries no extended information.
  defp new_extended(nil, tags) when map_size(tags) == 0, do: nil

  defp new_extended(zone, tags) do
    %{calendar: nil, zone_id: zone, zone_offset: nil, zone_critical: false, tags: tags}
  end

  # Defer to `Tempo.Validation.validate/2` for calendar-aware range
  # checks (month ≤ months_in_year, day ≤ days_in_month, leap-aware
  # Feb 29, etc.). Validation may return an `InvalidDateError` with
  # rich context.
  defp validate_against_calendar(%__MODULE__{calendar: calendar} = tempo) do
    case Validation.validate(tempo, calendar) do
      {:ok, _validated} -> {:ok, tempo}
      {:error, _} = err -> err
    end
  end

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
  (see the options form) to reject an elective disagreement too.

  ### Arguments

  * `string` is any ISO 8601 formatted string, optionally
    followed by an IXDTF suffix.

  * `calendar` (optional) is any `t:Calendar.calendar/0`. When
    passed, the explicit calendar always wins over any
    `[u-ca=NAME]` tag in the IXDTF suffix. When omitted, the
    `[u-ca=NAME]` tag is resolved to a `Calendrical.*` module via
    `Calendrical.calendar_from_cldr_calendar_type/1`; if no tag is present,
    `Calendrical.Gregorian` is used.

  ### Returns

  * `{:ok, t}` where the returned struct's `:extended` field
    is populated when an IXDTF suffix was parsed, or `nil`
    otherwise.

  * `{:error, reason}` when the string cannot be parsed or a
    critical IXDTF suffix is unrecognised.

  ## Examples

      iex> Tempo.from_iso8601("2022-11-20")
      {:ok, ~o"2022Y11M20D"}

      iex> Tempo.from_iso8601("2022Y")
      {:ok, ~o"2022Y"}

      iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("invalid")

      iex> {:ok, tempo} = Tempo.from_iso8601("5786-09-30[u-ca=hebrew]")
      iex> tempo.calendar
      Calendrical.Hebrew

      iex> {:ok, tempo} = Tempo.from_iso8601("2022-11-20T10:30:00Z[Europe/Paris][u-ca=hebrew]")
      iex> {tempo.extended.zone_id, tempo.extended.calendar, tempo.calendar}
      {"Europe/Paris", :hebrew, Calendrical.Hebrew}

      iex> {:error, %Tempo.UnknownZoneError{zone_id: "Continent/Imaginary"}} =
      ...>   Tempo.from_iso8601("2022-11-20T10:30:00Z[!Continent/Imaginary]")

  ### Examples


      iex> Tempo.from_iso8601("2026-06-15")
      {:ok, ~o"2026Y6M15D"}

  ### Examples


      iex> Tempo.from_iso8601("2026-06-15", Calendrical.ISOWeek)
      {:ok, ~o"2026Y6M15D"W}

  """
  @spec from_iso8601(string :: String.t()) ::
          {:ok,
           t()
           | Tempo.Interval.t()
           | Tempo.Duration.t()
           | Tempo.Set.t()}
          | {:error, error_reason()}
  @spec from_iso8601(string :: String.t(), calendar :: Calendar.calendar()) ::
          {:ok,
           t()
           | Tempo.Interval.t()
           | Tempo.Duration.t()
           | Tempo.Set.t()}
          | {:error, error_reason()}
  def from_iso8601(string) when is_binary(string) do
    # No explicit calendar — the IXDTF `[u-ca=NAME]` suffix wins
    # when present, otherwise fall back to Gregorian.
    do_from_iso8601(string, :from_ixdtf_or_default)
  end

  @spec from_iso8601(string :: String.t(), options :: keyword()) ::
          {:ok,
           t()
           | Tempo.Interval.t()
           | Tempo.Duration.t()
           | Tempo.Set.t()}
          | {:error, error_reason()}
  def from_iso8601(string, options) when is_binary(string) and is_list(options) do
    # Options form. `:calendar` selects the calendar (default: IXDTF or
    # Gregorian); `strict: true` rejects an IXDTF value whose numeric
    # offset disagrees with its zone (RFC 9557 §4.2), via
    # `Tempo.Compare.validate_zone_offset/1`. Strict only applies to a
    # `%Tempo{}` result; intervals/durations pass straight through.
    calendar = Keyword.get(options, :calendar, :from_ixdtf_or_default)

    with {:ok, %Tempo{} = tempo} <- do_from_iso8601(string, calendar) do
      enforce_strict(tempo, options)
    end
  end

  def from_iso8601(string, calendar) when is_binary(string) do
    # Explicit user calendar always wins — IXDTF `[u-ca=NAME]` is
    # recorded on `extended.calendar` for metadata but does not
    # override the user's choice. This keeps the existing
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
      {:ok, propagated}
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

  defp propagate_endpoint_frame(other), do: other

  # A per-endpoint IXDTF `u-ca` suffix (`1447Y9M1D[u-ca=islamic-civil]/…`,
  # the form `to_iso8601/1` emits for non-Gregorian interval endpoints)
  # determines that endpoint's calendar the same way a top-level suffix
  # does for a whole value — otherwise the endpoint's units would be
  # interpreted in the default calendar while its tag claims another,
  # breaking the serialise/re-parse round trip. Applies only when the
  # caller didn't choose a calendar explicitly: an explicit calendar
  # always wins and `u-ca` stays metadata-only.
  defp maybe_resolve_endpoint_calendars(%Tempo.Interval{} = interval, :from_ixdtf_or_default) do
    %{
      interval
      | from: resolve_endpoint_calendar(interval.from),
        to: resolve_endpoint_calendar(interval.to)
    }
  end

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
    %{range | first: attach_extended(range.first, extended)}
  end

  def attach_extended(%Tempo.Interval{} = interval, extended) do
    # A top-level suffix on an interval propagates to each endpoint
    # unless that endpoint carries its own IXDTF info (which the
    # parser has already attached to `endpoint.extended`).
    %{
      interval
      | from: attach_extended(interval.from, extended),
        to: attach_extended(interval.to, extended)
    }
  end

  def attach_extended(other, _extended), do: other

  @doc """
  Creates a `t:Tempo.t/0` struct from an ISO8601
  string.

  The parser supports the vast majority of [ISO8601](https://www.iso.org/iso-8601-date-and-time-format.html)
  parts 1 and 2.

  ### Arguments

  * `string` is any ISO8601 formatted string

  * `calendar` is any `t:Calendar.calendar/0`. The default is
    `Calendrical.Gregorian`.

  ### Returns

  * `t:t/0` or

  * raises an exception

  ## Examples

      iex> Tempo.from_iso8601!("2022-11-20")
      ~o"2022Y11M20D"

      iex> Tempo.from_iso8601!("2022Y")
      ~o"2022Y"

  ### Examples


      iex> Tempo.from_iso8601!("2026-06-15T14:30[Australia/Sydney]")
      ~o"2026Y6M15DT14H30M[Australia/Sydney]"

  """
  @spec from_iso8601!(string :: String.t()) :: t | no_return()
  def from_iso8601!(string) when is_binary(string) do
    # Mirror `from_iso8601/1` — no explicit calendar, so IXDTF
    # `[u-ca=NAME]` wins when present.
    case from_iso8601(string) do
      {:ok, tempo} -> tempo
      {:error, exception} -> raise exception
    end
  end

  @spec from_iso8601!(string :: String.t(), options :: keyword()) :: t | no_return()
  def from_iso8601!(string, options) when is_binary(string) and is_list(options) do
    case from_iso8601(string, options) do
      {:ok, tempo} -> tempo
      {:error, exception} -> raise exception
    end
  end

  @spec from_iso8601!(string :: String.t(), calendar :: Calendar.calendar()) :: t | no_return()
  def from_iso8601!(string, calendar) when is_binary(string) do
    case from_iso8601(string, calendar) do
      {:ok, tempo} -> tempo
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Parse a string that must be an ISO 8601 duration.

  `from_iso8601/1` admits every shape the standard defines and returns
  whichever type the string turned out to be. When the caller already
  knows the profile its value belongs to — an iCalendar `DURATION`
  property, a duration-form `TRIGGER` (RFC 5545 §3.3.6) — that is one
  guarantee short: a property holding a date-time parses *successfully
  as the wrong type*, and the mistake surfaces later, somewhere else.

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
  Parse a string that must be an ISO 8601 date.

  Unlike `from_iso8601/1`, which returns whichever shape the string
  turns out to be, this requires the value to be a date and says so
  when it is not. A date at any resolution is accepted — `"2026"`,
  `"2026-06"`, `"2026-06-15"`, `"2026-W12"` and `"2026-166"` are all
  dates, being intervals of a year, month, day, week and day
  respectively. A date carrying a time of day is not.

  Prefer this over `from_iso8601/1` wherever the field is known to hold
  a date. A date, a datetime and a time all come back from
  `from_iso8601/1` as a `t:Tempo.t/0`, so a time-of-day string arriving
  in a date field is not detected at the point of parsing — it is
  detected much later, or not at all.

  ### Arguments

  * `string` is the candidate ISO 8601 date.

  ### Options

  * `:calendar` is the calendar to parse against. Defaults to the
    calendar named by an IXDTF `[u-ca=NAME]` suffix, or
    `Calendrical.Gregorian`.

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

  A datetime is not a date, and says so rather than succeeding as the
  wrong shape:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_date("2026-06-15T10:30")

  """
  @spec parse_date(String.t(), keyword()) :: {:ok, t()} | {:error, error_reason()}
  def parse_date(string, options \\ []) when is_binary(string) and is_list(options) do
    parse_profile(string, :date, options)
  end

  @doc """
  Raising version of `parse_date/2`.

  ### Arguments

  * `string` is the candidate ISO 8601 date.

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
  Parse a string that must be an ISO 8601 datetime.

  A datetime carries both a date and a time of day. A date alone is not
  a datetime — use `parse_date/2` for that — and neither is a time
  alone.

  ### Arguments

  * `string` is the candidate ISO 8601 datetime.

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

  A date with no time of day is not a datetime:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_datetime("2026-06-15")

  """
  @spec parse_datetime(String.t(), keyword()) :: {:ok, t()} | {:error, error_reason()}
  def parse_datetime(string, options \\ []) when is_binary(string) and is_list(options) do
    parse_profile(string, :datetime, options)
  end

  @doc """
  Raising version of `parse_datetime/2`.

  ### Arguments

  * `string` is the candidate ISO 8601 datetime.

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
  Parse a string that must be an ISO 8601 time of day.

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

  * `string` is the candidate ISO 8601 time of day.

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

  A datetime is not a time of day:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_time("2026-06-15T10:30")

  """
  @spec parse_time(String.t(), keyword()) :: {:ok, t()} | {:error, error_reason()}
  def parse_time(string, options \\ []) when is_binary(string) and is_list(options) do
    parse_profile(string, :time, options)
  end

  @doc """
  Raising version of `parse_time/2`.

  ### Arguments

  * `string` is the candidate ISO 8601 time of day.

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
  Parse a string that must be an ISO 8601 interval.

  Every form the standard gives an interval is accepted: a pair of
  datetimes, a datetime and a duration in either order, an open-ended
  pair, and any of those carrying a repeat rule.

  A `t:Tempo.Interval.t/0` is already distinguishable from the other
  shapes `from_iso8601/1` returns, so this adds a named error where a
  match would otherwise raise `MatchError`, rather than a type
  guarantee unavailable by other means.

  ### Arguments

  * `string` is the candidate ISO 8601 interval.

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

  A single date is not an interval, even though every Tempo value spans
  one — an implicit span is not written with a range operator:

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_interval("2026-06-15")

  """
  @spec parse_interval(String.t(), keyword()) ::
          {:ok, Tempo.Interval.t()} | {:error, error_reason()}
  def parse_interval(string, options \\ []) when is_binary(string) and is_list(options) do
    parse_profile(string, :interval, options)
  end

  @doc """
  Raising version of `parse_interval/2`.

  ### Arguments

  * `string` is the candidate ISO 8601 interval.

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

  defp enforce_critical_zone_offset(_other), do: :ok

  defp zone_critical?(%__MODULE__{extended: extended}) when is_map(extended),
    do: Map.get(extended, :zone_critical, false)

  defp zone_critical?(_other), do: false

  @doc """
  Parse a locale-formatted date, time, datetime, or interval
  string into a Tempo value.

  Delegates to `Calendrical.parse/2` with `as: :map`, then routes
  the resulting field map (or `{from_map, to_map}` interval pair)
  through `Tempo.new/1`. Useful when the input shape is not known
  up-front — a single text field that may carry any of
  `"2026-05-16"`, `"14:30"`, `"May 16, 2026 2:30 PM"`, or
  `"May 5 – May 10, 2026"`.

  For ISO 8601 / IXDTF input prefer `from_iso8601/1`, which
  preserves EDTF qualification and IXDTF extended suffixes that
  the locale-style parser does not understand.

  ### Arguments

  * `input` is the raw user input string.

  * `options` is a keyword list forwarded to `Calendrical.parse/2`.

  ### Options

  Notable keys forwarded to `Calendrical.parse/2`:

  * `:locale` is the locale used to interpret month names, AM/PM
    markers, and similar locale-dependent tokens. Defaults to
    `Localize.get_locale/0`.

  * `:calendar` is the calendar module the input is read in, such as
    `Calendrical.Hebrew`. Defaults to `Calendar.ISO`. A CLDR calendar
    name such as `:hebrew` is not a calendar and returns an error.

  * `:reference_date` is the "today" that two-digit years pivot on
    and partial dates inherit from.

  The `:as` option is set to `:map` regardless of any caller-supplied
  value — Tempo always asks Calendrical for the field-map form so it
  can rebuild a Tempo value from the parsed fields. A UTC offset such
  as `"+05:00"` becomes the value's shift, as `from_iso8601/1` reads
  it, and a week of the year (`"week 1 of 2026"`) is the week
  `from_iso8601/1` reads in `2026-W01`.

  ### Returns

  * `{:ok, t()}` for a single-value input.

  * `{:ok, Tempo.Interval.t()}` when the input names a range.

  * `{:error, exception}` when Calendrical cannot parse the string,
    or when `Tempo.new/1` rejects the resulting field map.

  ### Examples

      iex> {:ok, tempo} = Tempo.parse("2026-05-16", locale: :en)
      iex> tempo.time
      [year: 2026, month: 5, day: 16]

      iex> {:ok, tempo} = Tempo.parse("May 16, 2026", locale: :en)
      iex> tempo.time
      [year: 2026, month: 5, day: 16]

      iex> {:ok, tempo} = Tempo.parse("14:30", locale: :en)
      iex> tempo.time
      [hour: 14, minute: 30]

      iex> {:ok, %Tempo.Interval{}} = Tempo.parse("2026-05-05 – 2026-05-10", locale: :en)

  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, t() | Tempo.Interval.t()} | {:error, Exception.t()}
  def parse(input, options \\ []) when is_binary(input) do
    options = Keyword.put(options, :as, :map)

    with {:ok, value} <- Calendrical.parse(input, options) do
      parsed_to_tempo(value)
    end
  end

  @doc """
  Bang variant of `parse/2`. Raises on parse failure or invalid
  component combination.

  ### Examples

      iex> Tempo.parse!("2026-05-16", locale: :en).time
      [year: 2026, month: 5, day: 16]

  """
  @spec parse!(String.t(), Keyword.t()) :: t() | Tempo.Interval.t()
  def parse!(input, options \\ []) when is_binary(input) do
    case parse(input, options) do
      {:ok, value} -> value
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "Tempo.parse!/2 failed: #{inspect(reason)}"
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

  IXDTF suffixes (`[Europe/Paris]`, `[u-ca=hebrew]`) are **not**
  emitted by this function — the `:extended` field is currently
  ignored. Round-trip of IXDTF-enriched values is a future
  extension.

  ### Arguments

  * `value` is a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.Duration.t/0`, or `t:Tempo.Set.t/0`.

  ### Returns

  * An ISO 8601-2 binary that parses back to the same AST.

  ### Examples

      iex> Tempo.from_iso8601!("2022-11-20") |> Tempo.to_iso8601()
      "2022Y11M20D"

      iex> Tempo.from_iso8601!("R5/2022-01-01/P1M") |> Tempo.to_iso8601()
      "R5/2022Y1M1D/P1M"

      iex> {:ok, i} = Tempo.from_iso8601("1984?/2004~")
      iex> Tempo.to_iso8601(i)
      "1984Y?/2004Y~"

  """
  @spec to_iso8601(Tempo.t() | Tempo.Interval.t() | Tempo.Duration.t() | Tempo.Set.t()) ::
          String.t()
  def to_iso8601(value) do
    value
    |> Tempo.Inspect.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc """
  Encode a `t:Tempo.Interval.t/0` into an RFC 5545 RRULE string.

  The output does **not** include the leading `RRULE:` prefix,
  nor a `DTSTART` property — RRULE is a recurrence pattern, not
  a full iCalendar record. Callers wanting the full record
  prepend `DTSTART` themselves using the interval's `:from`
  field.

  ### Supported inputs

  * A `%Tempo.Interval{}` with a single-unit `%Tempo.Duration{}`
    cadence. Supported units: `:second`, `:minute`, `:hour`,
    `:day`, `:week`, `:month`, `:year`.

  * `:recurrence` of `:infinity` (no COUNT), a positive integer
    (COUNT), or `1` combined with `:to` (UNTIL).

  * `:repeat_rule` of `nil`, or a `%Tempo{}` whose `:time` holds a
    single `{:selection, [...]}` entry. Selection entries for
    `:month`, `:day` (→ BYMONTHDAY), `:day_of_year`, `:week`,
    `:hour`, `:minute`, `:second`, and the paired
    `:day_of_week`/`:instance` (→ BYDAY with optional ordinals)
    are encoded directly.

  ### Returns

  * `{:ok, rrule_string}` on success.

  * `{:error, reason}` when the interval cannot be expressed as
    an RRULE (e.g. multi-unit duration, unsupported selection
    entry).

  ### Examples

      iex> {:ok, i} = Tempo.RRule.parse("FREQ=DAILY;COUNT=10")
      iex> Tempo.to_rrule(i)
      {:ok, "COUNT=10;FREQ=DAILY"}

      iex> {:ok, i} = Tempo.RRule.parse("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH")
      iex> Tempo.to_rrule(i)
      {:ok, "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH"}

      iex> {:error, %Tempo.ConversionError{}} =
      ...>   Tempo.to_rrule(Tempo.from_iso8601!("2022-06-15"))

  """
  @spec to_rrule(Tempo.Interval.t() | term()) ::
          {:ok, String.t()} | {:error, Tempo.ConversionError.t()}
  def to_rrule(%Tempo.Interval{} = interval) do
    Encoder.encode(interval)
  end

  def to_rrule(other) do
    {:error,
     ConversionError.exception(
       reason:
         "Only a %Tempo.Interval{} can be converted to an RRULE. " <>
           "RRULE is a recurrence rule; got: #{inspect(other)}",
       value: other,
       target: :rrule
     )}
  end

  @doc """
  Bang variant of `to_rrule/1`.

  ### Returns

  * The RRULE string on success.

  * Raises `Tempo.ConversionError` otherwise.

  ### Examples


      iex> Tempo.to_rrule!(~o"R12/2026-01-05/P1D")
      "COUNT=12;FREQ=DAILY"

  """
  @spec to_rrule!(Tempo.Interval.t()) :: String.t() | no_return()
  def to_rrule!(value) do
    case to_rrule(value) do
      {:ok, rrule} -> rrule
      {:error, %Tempo.ConversionError{} = error} -> raise error
    end
  end

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
    AST.build([year: year, month: month, day: day], calendar)
  end

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
    `at_resolution/2`. The default is `:day`.

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
    if Date.compare(first, last) == :gt do
      {:error,
       ConversionError.exception(
         value: range,
         target: Tempo.Interval,
         reason:
           "An empty Date.Range spans no days, so it cannot become an interval " <>
             "(Tempo intervals have positive extent)."
       )}
    else
      resolution = Keyword.get(options, :resolution, :day)

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
      [year: year, month: month, day: day, hour: hour, minute: minute, second: second] ++
        microsecond_component(naive),
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
      [year: year, month: month, day: day, hour: hour, minute: minute, second: second] ++
        microsecond_component(dt)

    total_offset = utc_offset + std_offset

    %__MODULE__{
      time: time,
      shift: Zone.offset_to_shift(total_offset),
      calendar: tempo_calendar,
      extended: %{
        zone_id: time_zone,
        zone_offset: div(total_offset, 60),
        calendar: nil,
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

  def resolution(%__MODULE__{time: units}) do
    units
    |> Enum.reverse()
    |> hd
    |> unit_resolution()
  end

  @doc """
  Returns the maximum and minimum time units as a
  2-tuple.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  ### Returns

  * `{max_unit, min_unit}`

  ### Examples

        iex> Tempo.unit_min_max ~o"2022Y1M2G3DU"
        {:day, :year}

        iex> Tempo.unit_min_max ~o"2022"
        {:year, :year}

  """
  @spec unit_min_max(tempo :: t | token_list()) :: {time_unit(), time_unit()}
  def unit_min_max(%__MODULE__{time: units}) do
    unit_min_max(units)
  end

  def unit_min_max(units) when is_list(units) do
    {max, _} = unit_resolution(hd(units))
    {min, _} = unit_resolution(hd(Enum.reverse(units)))
    {min, max}
  end

  defp unit_resolution(time_unit) do
    case time_unit do
      {:selection, selection} -> unit_min_max(selection)
      {unit, {:group, first..last//_}} -> {unit, last - first + 1}
      # A materialised group is `{unit, {:group, members}, size}` — the
      # third element is the group's own size, which is its resolution.
      {unit, {:group, _members}, size} when is_integer(size) -> {unit, size}
      {unit, %Range{last: last}} -> {unit, last}
      # A microsecond component is `{value, precision}`; the precision
      # (digit count) is its resolution scale — `{:microsecond, 3}` is
      # millisecond resolution.
      {:microsecond, {_value, precision}} when is_integer(precision) -> {:microsecond, precision}
      {unit, {_value, meta}} when is_list(meta) -> {unit, Keyword.get(meta, :margin_of_error, 1)}
      {unit, {_value, continuation}} when is_function(continuation) -> {unit, 1}
      {unit, _value} -> {unit, 1}
    end
  end

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
  def week(%__MODULE__{time: time}) do
    case Keyword.get(time, :week) do
      value when is_integer(value) -> value
      _other -> nil
    end
  end

  def week(%Tempo.Interval{from: %__MODULE__{} = from, to: to}) do
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
  defp component(%__MODULE__{time: time}, unit) do
    case Keyword.get(time, unit) do
      value when is_integer(value) -> value
      nil -> nil
      _other -> nil
    end
  end

  defp component(
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
  it is anchored.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  ### Returns

  * `true` or `false`

  ### Examples

      iex> Tempo.anchored? ~o"2022"
      true

      iex> Tempo.anchored? ~o"2M"
      false

  """
  @spec anchored?(tempo :: t) :: boolean()
  def anchored?(%__MODULE__{time: [{:year, _year} | _rest]}) do
    true
  end

  def anchored?(%__MODULE__{}) do
    false
  end

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

  """
  @spec trunc(tempo :: t, truncate_to :: time_unit()) :: t | {:error, error_reason()}
  def trunc(%__MODULE__{} = tempo, truncate_to \\ :day) do
    with {:ok, truncate_to} <- validate_unit(truncate_to) do
      truncate(tempo, truncate_to)
    end
  end

  # A value already on the week axis holds `:week` as a component, so
  # the ordinary rule applies.
  defp truncate(%__MODULE__{time: time} = tempo, :week) when is_list(time) do
    if Keyword.has_key?(time, :week) do
      take_units(tempo, :week)
    else
      week_of(tempo)
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
  defp week_of(%__MODULE__{} = tempo) do
    with %__MODULE__{} = start <- beginning_of_week(tempo) do
      take_units(start, :day)
    end
  end

  defp take_units(%__MODULE__{time: time} = tempo, truncate_to) do
    case Enum.take_while(time, &(Unit.compare(&1, truncate_to) in [:gt, :eq])) do
      [] ->
        {:error,
         ResolutionError.exception(
           operation: :trunc,
           target: truncate_to,
           current: resolution(tempo) |> elem(0),
           reason: :empty_resolution
         )}

      other ->
        %{tempo | time: other}
    end
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
         value when value != :any <- time |> Keyword.keys() |> axis_of(),
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

  defp axis_of(units) do
    cond do
      Enum.any?(units, &(&1 in @week_only)) -> :week
      Enum.any?(units, &(&1 in @ordinal_only)) -> :ordinal
      Enum.any?(units, &(&1 in @gregorian_only)) -> :gregorian
      true -> :any
    end
  end

  @doc """
  Rounds a tempo struct to the specified resolution.

  The value rounds to the nearest `round_to`: 21 November 2022 rounds
  to December at month resolution and to 2023 at year resolution,
  where `trunc/2` would keep November and 2022.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  * `round_to` is any time unit. The default
    is `:day`.

  ### Returns

  * `rounded` is a tempo struct that is rounded or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.round ~o"2022-11-21", :day
      ~o"2022Y11M21D"

      iex> Tempo.round ~o"2022-11-21", :month
      ~o"2022Y12M"

      iex> Tempo.round ~o"2022-11-21", :year
      ~o"2023Y"

  """
  @spec round(tempo :: t, round_to :: time_unit()) :: t | {:error, error_reason()}
  def round(%__MODULE__{} = tempo, round_to \\ :day) do
    with {:ok, round_to} <- validate_unit(round_to) do
      case Rounding.round(tempo, round_to) do
        {:error, reason} -> {:error, reason}
        other -> %{tempo | time: other}
      end
    end
  end

  @doc """
  Split a tempo struct into a date
  and time.

  ### Examples


      iex> Tempo.split(~o"2026-06-15T14:30:00")
      {~o"2026Y6M15D", ~o"T14H30M0S"}

  """
  @spec split(t()) :: {t() | nil, t() | nil}
  def split(%__MODULE__{time: time, calendar: calendar}) do
    case Split.split(time) do
      {date, []} ->
        {%Tempo{time: date, calendar: calendar}, nil}

      {[], time} ->
        {nil, %Tempo{time: time, calendar: calendar}}

      {date, time} ->
        {%Tempo{time: date, calendar: calendar}, %Tempo{time: time, calendar: calendar}}
    end
  end

  # Passes through any non-`{:ok, _}` from `Validation.validate/2`,
  # which dialyzer widens beyond the spec.
  @dialyzer {:nowarn_function, merge: 2}
  @spec merge(t(), t()) :: t() | {:error, error_reason()}
  def merge(%__MODULE__{} = base, %Tempo{} = from) do
    units = Enumeration.merge(base.time, from.time)
    shift = from.shift || base.shift

    case Validation.validate(%{base | time: units, shift: shift}) do
      {:ok, tempo} -> tempo
      other -> other
    end
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

  A value with a year is checked against its calendar, so
  `~o"2026-02" |> Tempo.on(~o"29D")` is an error: 2026 is not a leap
  year.

  ### Arguments

  * `value` and `other` are `t:#{__MODULE__}.t/0` values, at most one
    of them with a year.

  ### Returns

  * `{:ok, tempo}` with the one value placed on the other.

  * `{:error, reason}` when both values have a year, or when the
    result is not a date in its calendar.

  ### Examples

      iex> Tempo.at(~o"2026-06-15", ~o"T17")
      {:ok, ~o"2026Y6M15DT17H"}

      iex> Tempo.at(~o"T17", ~o"2026-06-15")
      {:ok, ~o"2026Y6M15DT17H"}

      iex> Tempo.at(~o"3M", ~o"2D")
      {:ok, ~o"3M2D"}

  """
  @dialyzer {:nowarn_function, at: 2}

  @spec at(t(), t()) :: {:ok, t()} | {:error, error_reason()}
  def at(%__MODULE__{} = value, %__MODULE__{} = other) do
    place(value, other, anchored?(value), anchored?(other))
  end

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
  @spec at!(t(), t()) :: t()
  def at!(%__MODULE__{} = value, %__MODULE__{} = other) do
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

  """
  @spec on(t(), t()) :: {:ok, t()} | {:error, error_reason()}
  def on(%__MODULE__{} = value, %__MODULE__{} = other), do: at(value, other)

  @doc """
  Bang variant of `on/2` — returns the placed value or raises. See
  `on/2`.

  ### Examples

      iex> Tempo.on!(~o"3M", ~o"2D")
      ~o"3M2D"

  """
  @spec on!(t(), t()) :: t()
  def on!(%__MODULE__{} = value, %__MODULE__{} = other), do: at!(value, other)

  # Compose two values along the resolution axis: keep `high_source`'s
  # components strictly coarser than `low_value`'s coarsest, then graft
  # `low_value` on. The engine of `at/2`, whose value with a year (or
  # coarser value) is the high source. Reusing `merge/2` keeps a single
  # validated path; pre-trimming `high_source` is what makes it a clean
  # replace rather than a leaky overlay.
  defp graft(%__MODULE__{} = high_source, %__MODULE__{time: []} = low_value),
    do: merge(high_source, low_value)

  defp graft(%__MODULE__{} = high_source, %__MODULE__{time: [{unit, _value} | _]} = low_value) do
    cutoff = Unit.sort_key(unit)
    trimmed = Enum.filter(high_source.time, fn {other, _v} -> Unit.sort_key(other) > cutoff end)
    merge(%{high_source | time: trimmed}, low_value)
  end

  @doc """
  Adds an extended enumeration to a Tempo.

  This has the effect of increasing the
  resolution of the the Tempo struct but
  still covering the same interval.

  ### Example

      iex> Tempo.extend(~o"2020")
      {:ok, ~o"2020Y{1..12}M"}

  ### Examples


      iex> Tempo.extend(~o"2026-06")
      {:ok, ~o"2026Y6M{1..30}D"}

  """

  @spec extend(t(), nil) :: {:ok, t()} | {:error, error_reason()}
  def extend(tempo, unit \\ nil)

  def extend(%Tempo{} = tempo, nil) do
    tempo
    |> Enumeration.add_implicit_enumeration()
    |> Validation.validate()
  end

  @spec extend!(t(), nil) :: t()
  def extend!(%Tempo{} = tempo, unit \\ nil) do
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
  spans once materialised with `to_interval/1`.

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
    resolution = Keyword.get(options, :resolution, :day)

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

  """
  @spec extend_resolution(tempo :: t, target_unit :: time_unit()) ::
          t | {:error, error_reason()}
  def extend_resolution(%Tempo{time: time, calendar: calendar} = tempo, target_unit) do
    with {:ok, target_unit} <- validate_unit(target_unit) do
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

  defp fill_to_resolution(time, current_unit, target_unit, calendar) do
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
        min_value = range_first(range)
        new_time = time ++ [{next_unit, min_value}]
        fill_to_resolution(new_time, next_unit, target_unit, calendar)
    end
  end

  defp range_first(%Range{first: first}), do: first

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
      {current_unit, _span} = resolution(tempo)

      case Unit.compare(target_unit, current_unit) do
        :eq -> tempo
        :gt -> trunc(tempo, target_unit)
        :lt -> extend_resolution(tempo, target_unit)
      end
    end
  end

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
    counted in the calendar's own year, and a week-based calendar's
    `[year: Y, week: W, day: K]`.

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

  # A week-based calendar's own date: year, week and day of the week.
  def to_date(%Tempo{time: [year: year, week: week, day: day], calendar: calendar})
      when is_integer(year) and is_integer(week) and is_integer(day) and is_atom(calendar) and
             not is_nil(calendar) do
    Date.new(year, week, day, calendar)
  end

  def to_date(%Tempo{} = value) do
    {:error, ConversionError.exception(value: value, target: Date)}
  end

  @doc """
  Convert a Tempo struct into a Time.

  ### Examples


      iex> Tempo.to_time(~o"T14:30:00")
      {:ok, ~T[14:30:00.000000]}

  """
  # A zoned time-of-day projects to the wall-clock `Time`, dropping
  # the offset — the same lossy projection `Time` itself is (it has
  # no zone). Mirrors `to_date/1`, and `DateTime.to_time/1` in the
  # stdlib. Callers who need the offset should keep the Tempo.
  @spec to_time(t()) :: {:ok, Time.t()} | {:error, error_reason()}
  def to_time(%Tempo{time: [hour: hour, minute: minute, second: second]}) do
    Time.new(hour, minute, second, 0)
  end

  def to_time(%Tempo{} = value) do
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
      {:ok, ~N[2022-11-19 01:02:03.000000]}

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
      ) do
    NaiveDateTime.new(year, month, day, hour, minute, second, microsecond, native_calendar(tempo))
  end

  def to_naive_datetime(
        %Tempo{
          time: [year: year, month: month, day: day, hour: hour, minute: minute, second: second]
        } = tempo
      ) do
    NaiveDateTime.new(year, month, day, hour, minute, second, 0, native_calendar(tempo))
  end

  def to_naive_datetime(%Tempo{} = value) do
    {:error, ConversionError.exception(value: value, target: NaiveDateTime)}
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
      {:ok, ~U[2022-11-19 01:02:03.000000Z]}

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
  # Tempo recorded (`extended.zone_offset`, in minutes). Falls back
  # to the first (pre-transition, higher-offset) candidate.
  defp disambiguate_fold(first, second, %Tempo{extended: %{zone_offset: minutes}})
       when is_integer(minutes) do
    target_seconds = minutes * 60

    Enum.find([first, second], first, fn dt ->
      dt.utc_offset + dt.std_offset == target_seconds
    end)
  end

  defp disambiguate_fold(first, _second, _tempo), do: first

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
      iex> Tempo.to_iso8601(gregorian)
      "2026Y7M1D/10M1D"

  An interval set converts member by member:

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-06-15/2026-06-16"])
      iex> {:ok, hebrew} = Tempo.to_calendar(set, Calendrical.Hebrew)
      iex> hebrew |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.to_iso8601/1)
      ["5786Y9M30D/10M1D"]

  """
  @spec to_calendar(t() | Interval.t() | IntervalSet.t(), module()) ::
          {:ok, t() | Interval.t() | IntervalSet.t()} | {:error, Tempo.ConversionError.t()}
  def to_calendar(%Interval{} = interval, calendar) when is_atom(calendar) do
    with {:ok, from} <- convert_endpoint(interval.from, calendar),
         {:ok, to} <- convert_endpoint(interval.to, calendar) do
      {:ok, %{interval | from: from, to: to}}
    end
  end

  def to_calendar(%IntervalSet{} = set, calendar) when is_atom(calendar) do
    set
    |> IntervalSet.members()
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case to_calendar(member, calendar) do
        {:ok, converted} -> {:cont, {:ok, [converted | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, members} -> IntervalSet.new(Enum.reverse(members))
      {:error, reason} -> {:error, reason}
    end
  end

  def to_calendar(
        %Tempo{time: [year: year, month: month, day: day], shift: nil, calendar: source} = value,
        calendar
      )
      when is_atom(calendar) do
    convert_date(value, Date.new(year, month, day, source || Calendrical.Gregorian), calendar)
  end

  # A week-based calendar's date is its year, week and day of the week.
  def to_calendar(
        %Tempo{time: [year: year, week: week, day: day], shift: nil, calendar: source} = value,
        calendar
      )
      when is_atom(calendar) and is_atom(source) and not is_nil(source) do
    convert_date(value, Date.new(year, week, day, source), calendar)
  end

  def to_calendar(%Tempo{} = value, calendar) when is_atom(calendar) do
    {:error,
     ConversionError.exception(
       value: value,
       target: calendar,
       reason: "only day-resolution, unzoned values convert between calendars"
     )}
  end

  defp convert_date(value, date_in_source, calendar) do
    with {:ok, in_source} <- date_in_source,
         {:ok, converted} <- Date.convert(in_source, calendar) do
      {:ok, from_elixir(converted)}
    else
      {:error, reason} ->
        {:error, ConversionError.exception(value: value, target: calendar, reason: reason)}
    end
  end

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
  defp convert_endpoint(%Tempo{} = endpoint, calendar), do: to_calendar(endpoint, calendar)

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
  # floating form. A calendar or tags it carries stay.
  defp drop_zone(%__MODULE__{extended: %{calendar: nil, tags: tags}} = tempo)
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

  defp put_zone_id(nil, zone),
    do: %{zone_id: zone, zone_offset: nil, calendar: nil, zone_critical: false, tags: %{}}

  defp put_zone_id(%{} = extended, zone), do: %{extended | zone_id: zone}

  ## ---------------------------------------------------------
  ## Zone shifting — project a zoned Tempo into another zone
  ## ---------------------------------------------------------

  @doc """
  Project a zoned Tempo — one with a zone or an offset — into
  another IANA time zone, preserving the UTC instant.

  The returned Tempo names the same point on the time line, but the
  wall-clock reading is the one an observer in `target_zone` would
  see. This is the stdlib analogue of `DateTime.shift_zone/2`: in
  Tempo it routes through `Tempo.Compare.to_utc_seconds/1` so zone
  rules are re-evaluated from the configured time zone database at
  call time.

  ### Arguments

  * `tempo` is a `t:t/0` that carries zone information — either an
    IANA zone on `extended.zone_id`, a numeric `zone_offset`, or a
    `shift` keyword list. A floating Tempo (no zone info) cannot be
    projected because its UTC instant is undefined.

  * `target_zone` is an IANA zone name (`"Europe/Paris"`,
    `"America/New_York"`, `"Etc/UTC"`, …).

  ### Returns

  * `{:ok, tempo}` at second resolution in `target_zone`, or

  * `{:error, reason}` when `tempo` is not zoned or `target_zone`
    is unknown to the configured time zone database.

  ### Examples

      iex> paris = Tempo.from_iso8601!("2026-06-15T14:00:00[Europe/Paris]")
      iex> {:ok, new_york} = Tempo.shift_zone(paris, "America/New_York")
      iex> new_york.extended.zone_id
      "America/New_York"
      iex> Keyword.take(new_york.time, [:hour, :minute])
      [hour: 8, minute: 0]

  """
  @spec shift_zone(t(), String.t()) :: {:ok, t()} | {:error, error_reason()}
  def shift_zone(%Tempo{} = tempo, target_zone) when is_binary(target_zone) do
    cond do
      not anchored?(tempo) ->
        {:error, UnanchoredError.exception(operation: :shift_zone, value: tempo)}

      floating?(tempo) ->
        {:error, FloatingTempoError.exception(operation: :shift_zone, value: tempo)}

      true ->
        do_shift_zone(tempo, target_zone)
    end
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
  has no universal position — so `relation/2` and the interval
  predicates raise a `Tempo.FloatingTempoError` when only one operand
  is floating.

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

  defp do_shift_zone(%Tempo{calendar: calendar} = tempo, "Etc/UTC") do
    utc_seconds = Compare.to_utc_seconds(tempo)

    {{year, month, day}, {hour, minute, second}} =
      seconds_to_datetime(utc_seconds)

    {:ok,
     %__MODULE__{
       time: [
         year: year,
         month: month,
         day: day,
         hour: hour,
         minute: minute,
         second: second
       ],
       shift: [hour: 0],
       calendar: calendar || Calendrical.Gregorian,
       extended: %{
         zone_id: "Etc/UTC",
         zone_offset: 0,
         calendar: nil,
         zone_critical: false,
         tags: %{}
       }
     }}
  end

  defp do_shift_zone(%Tempo{calendar: calendar} = tempo, target_zone) do
    utc_seconds = Compare.to_utc_seconds(tempo)

    case TimeZoneDatabase.period_at_utc(target_zone, utc_seconds) do
      {:ok, period} ->
        offset_seconds = TimeZoneDatabase.total_offset(period)
        wall_seconds = utc_seconds + offset_seconds

        {{year, month, day}, {hour, minute, second}} =
          seconds_to_datetime(wall_seconds)

        {:ok,
         %__MODULE__{
           time: [
             year: year,
             month: month,
             day: day,
             hour: hour,
             minute: minute,
             second: second
           ],
           shift: Zone.offset_to_shift(offset_seconds),
           calendar: calendar || Calendrical.Gregorian,
           extended: %{
             zone_id: target_zone,
             zone_offset: div(offset_seconds, 60),
             calendar: nil,
             zone_critical: false,
             tags: %{}
           }
         }}

      {:error, _reason} ->
        {:error, UnknownZoneError.exception(zone_id: target_zone)}
    end
  end

  # Seconds-on-the-gregorian-line back to `{{y, m, d}, {h, mi, s}}`.
  # `Calendrical.Gregorian.date_from_iso_days/1` counts from 0000-01-01
  # (day 0) and, unlike OTP ≤ 28's
  # `:calendar.gregorian_seconds_to_datetime/1`, handles negative
  # (pre-common-era) values on every OTP.
  defp seconds_to_datetime(seconds) do
    days = Integer.floor_div(seconds, 86_400)
    time_of_day = Integer.mod(seconds, 86_400)
    {year, month, day} = Gregorian.date_from_iso_days(days)

    {{year, month, day},
     {div(time_of_day, 3_600), time_of_day |> rem(3_600) |> div(60), rem(time_of_day, 60)}}
  end

  ## ---------------------------------------------------------
  ## Metadata — the caller's own data on any value
  ## ---------------------------------------------------------

  @doc """
  Returns a value's metadata: the caller's own data carried with it (a holiday
  name, an event's summary).

  Every Tempo value carries a metadata map. It is not part of the value's
  ISO 8601 form, and materialisation carries it along: a recurrence's metadata
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
  def day_of_week(%Tempo{} = tempo, starting_on \\ :default) do
    {year, month, day} = require_ymd!(tempo, :day_of_week)
    {dow, _first, _last} = calendar_of(tempo).day_of_week(year, month, day, starting_on)
    dow
  end

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
  def leap_year?(%Tempo{time: time} = tempo) do
    year =
      Keyword.get(time, :year) ||
        raise ArgumentError,
              "Tempo.leap_year?/1 requires a year component. Got: #{inspect(tempo)}"

    calendar_of(tempo).leap_year?(year)
  end

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
    year =
      Keyword.get(time, :year) ||
        raise ArgumentError,
              "Tempo.days_in_month/1 requires a year component. Got: #{inspect(tempo)}"

    month =
      Keyword.get(time, :month) ||
        raise ArgumentError,
              "Tempo.days_in_month/1 requires a month component. Got: #{inspect(tempo)}"

    calendar_of(tempo).days_in_month(year, month)
  end

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
  # quarter-of-year on a year-resolution value still works.
  defp require_ymd!(%Tempo{time: time} = tempo, function, opts \\ []) do
    default_day = Keyword.get(opts, :default_day, 1)

    year =
      Keyword.get(time, :year) ||
        raise ArgumentError,
              "Tempo.#{function}/1 requires a year component. Got: #{inspect(tempo)}"

    month = Keyword.get(time, :month, 1)
    day = Keyword.get(time, :day, default_day)
    {year, month, day}
  end

  ## ---------------------------------------------------------
  ## Day and month boundary helpers
  ## ---------------------------------------------------------

  @doc """
  Return a second-resolution `t:t/0` at the start (`00:00:00`) of
  the day that contains `tempo`.

  Preserves the input's calendar, shift, and zone metadata so that
  beginning-of-day in `[Europe/Paris]` still names midnight Paris
  time, not midnight UTC.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month/day components.

  ### Returns

  * A second-resolution `t:t/0`.

  ### Examples

      iex> Tempo.beginning_of_day(~o"2026-06-15T14:30:00")
      ~o"2026Y6M15DT0H0M0S"

      iex> Tempo.beginning_of_day(~o"2026-06-15")
      ~o"2026Y6M15DT0H0M0S"

  """
  @spec beginning_of_day(t()) :: t() | {:error, error_reason()}
  def beginning_of_day(%Tempo{} = tempo) do
    tempo
    |> trunc(:day)
    |> extend_to_second()
  end

  @doc """
  Return a second-resolution `t:t/0` at the start of `tempo`'s week.

  **The week starts where the value's own calendar starts its weeks.**
  `Calendrical.Gregorian` begins on Monday, so a Sunday belongs to the
  week that preceded it; a calendar configured `day_of_week:
  Calendrical.sunday()` begins on Sunday, so the same Sunday begins a
  week of its own. Reading the convention off the value rather than
  assuming ISO is what keeps a weekly total counting the seven days
  its holder actually keeps.

  Completes the family with `beginning_of_day/1` and
  `beginning_of_month/1`.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month/day components.

  ### Returns

  * A second-resolution `t:t/0`; or

  * `{:error, reason}` when the value has no day to place, or its
    calendar defines no week.

  ### Examples

      iex> Tempo.beginning_of_week(~o"2026-06-17T14:30:00")
      ~o"2026Y6M15DT0H0M0S"

  A Sunday belongs to the preceding week under an ISO calendar:

      iex> Tempo.beginning_of_week(~o"2026-08-16")
      ~o"2026Y8M10DT0H0M0S"

  """
  @spec beginning_of_week(t()) :: t() | {:error, error_reason()}
  def beginning_of_week(%Tempo{} = tempo) do
    with %Tempo{} = day <- trunc(tempo, :day),
         {:ok, date} <- to_date(day) do
      date
      |> Date.beginning_of_week(:default)
      |> from_date()
      |> then(&%{&1 | shift: tempo.shift, extended: tempo.extended})
      |> extend_to_second()
    end
  end

  @doc """
  Return a second-resolution `t:t/0` at the **exclusive** end of
  the day that contains `tempo` — i.e. `00:00:00` of the following
  day.

  Tempo follows the half-open `[from, to)` convention everywhere,
  so `end_of_day/1` returns the upper bound at which the day ends
  and the next day begins. This is the right argument for
  interval construction — pairing `beginning_of_day/1` and
  `end_of_day/1` gives you the 24-hour (or DST-adjusted) window.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month/day components.

  ### Returns

  * A second-resolution `t:t/0`.

  ### Examples

      iex> Tempo.end_of_day(~o"2026-06-15T14:30:00")
      ~o"2026Y6M16DT0H0M0S"

      iex> Tempo.end_of_day(~o"2026-12-31")
      ~o"2027Y1M1DT0H0M0S"

  """
  @spec end_of_day(t()) :: t() | {:error, error_reason()}
  def end_of_day(%Tempo{} = tempo) do
    case beginning_of_day(tempo) do
      {:error, _} = err -> err
      %Tempo{} = start -> Math.add(start, Duration.build(day: 1))
    end
  end

  @doc """
  Return a second-resolution `t:t/0` at the start of the month
  (`YYYY-MM-01T00:00:00`) that contains `tempo`.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month components.

  ### Returns

  * A second-resolution `t:t/0`.

  ### Examples

      iex> Tempo.beginning_of_month(~o"2026-06-15T14:30:00")
      ~o"2026Y6M1DT0H0M0S"

      iex> Tempo.beginning_of_month(~o"2026-06")
      ~o"2026Y6M1DT0H0M0S"

  """
  @spec beginning_of_month(t()) :: t() | {:error, error_reason()}
  def beginning_of_month(%Tempo{} = tempo) do
    tempo
    |> trunc(:month)
    |> extend_to_second()
  end

  @doc """
  Return a second-resolution `t:t/0` at the **exclusive** end of
  the month that contains `tempo` — i.e. the first day of the
  following month at `00:00:00`.

  Half-open by design; see `end_of_day/1` for the rationale.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month components.

  ### Returns

  * A second-resolution `t:t/0`.

  ### Examples

      iex> Tempo.end_of_month(~o"2026-06-15")
      ~o"2026Y7M1DT0H0M0S"

      iex> Tempo.end_of_month(~o"2026-12")
      ~o"2027Y1M1DT0H0M0S"

  """
  @spec end_of_month(t()) :: t() | {:error, error_reason()}
  def end_of_month(%Tempo{} = tempo) do
    case beginning_of_month(tempo) do
      {:error, _} = err -> err
      %Tempo{} = start -> Math.add(start, Duration.build(month: 1))
    end
  end

  # Pad to second resolution. `extend_resolution/2` handles the
  # general case; this helper just threads the {:error, _} case
  # through so the boundary helpers degrade gracefully.
  defp extend_to_second(%Tempo{} = tempo) do
    extend_resolution(tempo, :second)
  end

  defp extend_to_second({:error, _} = err), do: err

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
    {skip_options, units} = Keyword.split(units, [:skipping])
    shift(tempo, Duration.build(units), Keyword.merge(skip_options, options))
  end

  ## ---------------------------------------------------------
  ## Locale-aware formatting — to_string/1,2
  ## ---------------------------------------------------------

  @doc """
  Format a Tempo value as a locale-aware string.

  Routes through Localize so format patterns, month and weekday
  names, day periods, and punctuation all follow CLDR data for
  the chosen locale. The default format is keyed off the Tempo's
  resolution — a year-only value renders as `"2026"`, a month
  value as `"Jun 2026"`, a day value as `"Jun 15, 2026"`, and so
  on.

  `Tempo.to_string/1,2` is the end-user display function.
  `inspect/1` remains the programmer-facing form and returns the
  `~o"…"` sigil representation unchanged.

  ### Arguments

  * `value` is a `t:t/0`, `t:Tempo.Interval.t/0`, or
    `t:Tempo.IntervalSet.t/0`.

  ### Options

  * `:format` is a CLDR format atom (`:short | :medium | :long |
    :full`), a skeleton atom (`:yMMM`, `:yMMMd`, `:hm`, …), or a
    pattern string. Defaults to a resolution-appropriate choice
    (see the module doc of `Tempo.Format` for the table).

  * `:locale` is a CLDR locale identifier such as `"en"`,
    `"en-GB"`, or `"de"`. Defaults to Localize's configured
    default locale.

  * Any other option accepted by `Localize.Date.to_string/2`,
    `Localize.Time.to_string/2`, `Localize.DateTime.to_string/2`,
    or `Localize.Interval.to_string/3` is forwarded verbatim.

  ### Returns

  * A `t:String.t/0`.

  ### Raises

  * Any exception Localize raises for invalid locales, missing
    CLDR data, or unresolvable format skeletons.

  ### Examples

      iex> Tempo.to_string(~o"2026")
      "Jan\u2009\u2013\u2009Dec 2026"

      iex> Tempo.to_string(~o"2026-06")
      "Jun 1\u2009\u2013\u200930, 2026"

      iex> Tempo.to_string(~o"2026-06-15")
      "Jun 15, 2026"

      iex> Tempo.to_string(~o"2026-06-15", format: :long)
      "June 15, 2026"

      iex> Tempo.to_string(~o"2026", format: :long)
      "January\u2009\u2013\u2009December 2026"

      iex> Tempo.to_string(~o"P1Y6M")
      "1 year, 6 months"

      iex> Tempo.to_string(~o"P3DT2H", format: :short)
      "3 days, 2 hr"

  """
  @spec to_string(
          t() | Tempo.Interval.t() | Tempo.IntervalSet.t() | Tempo.Duration.t(),
          keyword()
        ) :: String.t()
  defdelegate to_string(value, options \\ []), to: Tempo.Format

  @doc """
  Format a Tempo as a locale-aware relative time string like
  `"3 hours ago"` or `"in 2 days"`.

  Routes through Localize's CLDR `relativeTime` patterns. The
  reference point ("now") comes from `Tempo.utc_now/0` unless
  overridden with the `:from` option — which makes this safe to
  use in tests via `Tempo.Clock.Test`.

  For intervals, the `:from` endpoint of the interval is used as
  the target — "the meeting starts in 2 hours" rather than
  "lasts 2 hours" (for duration phrasing, use `Tempo.to_string/2`
  on a `Tempo.Duration`).

  ### Arguments

  * `value` is a `t:t/0` or `t:Tempo.Interval.t/0`. The value
    must be anchored (have a year component); unanchored values
    raise `Tempo.UnanchoredError`.

  ### Options

  * `:from` is a `t:t/0` — the reference point the output is
    relative to. Defaults to `Tempo.utc_now/0`.

  * `:unit` forces the output unit (`:second`, `:minute`,
    `:hour`, `:day`, `:week`, `:month`, `:year`). Omit to let
    Localize auto-derive.

  * `:format` is `:standard`, `:narrow`, or `:short`. Defaults to
    `:standard`.

  * `:locale` is a CLDR locale. Defaults to Localize's configured
    default.

  ### Returns

  * A `t:String.t/0`.

  ### Examples

      iex> now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")
      iex> Tempo.to_relative_string(~o"2026-06-14T12:00:00Z", from: now)
      "yesterday"

      iex> now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")
      iex> Tempo.to_relative_string(~o"2026-06-15T15:00:00Z", from: now)
      "in 3 hours"

      iex> now = Tempo.from_iso8601!("2026-06-15T12:00:00Z")
      iex> Tempo.to_relative_string(~o"2026-06-10T12:00:00Z", from: now)
      "5 days ago"

  """
  @spec to_relative_string(t() | Tempo.Interval.t(), keyword()) :: String.t()
  defdelegate to_relative_string(value, options \\ []), to: Tempo.Format

  @doc """
  Convert an implicit-span `t:#{__MODULE__}.t/0` into the
  equivalent explicit `t:Tempo.Interval.t/0` or
  `t:Tempo.IntervalSet.t/0`.

  Every Tempo value represents a bounded interval on the time
  line. `~o"2026-01"` *is* the interval `[2026-01-01, 2026-02-01)`
  — `to_interval/1` materialises that implicit span as a pair of
  concrete endpoints under the half-open `[from, to)` convention
  (`from` inclusive, `to` exclusive). The span is one unit at the
  value's resolution: a day value becomes a one-day interval, a
  second value a one-second interval. This is the canonical
  representation used by the set-operations API (`union/2`,
  `intersection/2`, `coalesce/1`). See the
  [interop guide](interop.html) for how converted Elixir
  date/time values materialise.

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

  * `{:ok, interval}` when the value materialises to a single
    contiguous span.

  * `{:ok, interval_set}` when the value expands to multiple
    disjoint spans.

  * `{:ok, interval_set}` on the lazy backend when an open-ended
    `:within` window walks a value with no end of its own. It
    answers `Tempo.IntervalSet.first/1` and the other walking
    questions; `Tempo.IntervalSet.count/1` and `to_list/1` raise
    `Tempo.UnboundedSetError`.

  * `{:error, reason}` when the input cannot be materialised — a
    bare `Tempo.Duration` (no start), a `Tempo` at a resolution
    with no finer unit available to bound the span (microsecond
    materialises to a one-microsecond span; only exotic selector
    resolutions have no span), a one-of `Tempo.Set` (epistemic
    disjunction is not an interval list; the user must pick one or
    handle the disjunction themselves), a recurrence with no end and
    no `:within` window, or a leftover `:bound` option.

  * `{:error, %Tempo.UnanchoredError{}}` when the value has no
    concrete year and resolving the span would depend on the missing
    one — `~o"X*Y2M28D"` (February is 28 or 29 days), or a yearless
    masked month in a calendar whose month count varies by year.

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
      iex> {:error, %Tempo.MaterialisationError{reason: :bare_duration}} = Tempo.to_interval(duration)

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
          | Tempo.Duration.t(),
          keyword()
        ) ::
          {:ok, Tempo.Interval.t() | Tempo.IntervalSet.t()} | {:error, error_reason()}
  def to_interval(value, opts \\ []) do
    with :ok <- check_bound_option(opts, "Tempo.to_interval/2") do
      case open_window_start(Keyword.get(opts, :within)) do
        {:ok, window_from} -> occurrences_from(value, window_from, opts)
        {:error, _reason} = error -> error
        :bounded -> materialise(value, opts)
      end
    end
  end

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
  # returned.
  defp lazy_occurrences(value, window_from, opts) do
    base = value |> cadence_unit() |> walk_base()
    walk_opts = Keyword.delete(opts, :coalesce)

    with %Tempo{} = first_to <- walk_end(window_from, base, 0),
         {:ok, first} <- walk_window(value, window_from, first_to, walk_opts) do
      found = IntervalSet.to_list(first)
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
  # that cannot be materialised ends the walk.
  defp walked({:ok, set}, window_from, window_to, step, horizon) do
    found = set |> IntervalSet.to_list() |> Enum.filter(&starts_from?(&1, window_from))
    {found, {window_to, step + 1, horizon_after(horizon, found)}}
  end

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
  # The occurrences a `:within` window keeps — those that overlap it — for the
  # modules that assemble occurrences themselves (an iCalendar's events, a
  # JSCalendar's), so every function that takes a window keeps the same ones.
  # No window keeps them all.
  @spec occurrences_within([Tempo.Interval.t()], keyword()) ::
          {:ok, [Tempo.Interval.t()]} | {:error, error_reason()}
  def occurrences_within(occurrences, options), do: keep_within(occurrences, options)

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
    step = if direction == -1, do: negate_duration(duration), else: duration

    intervals =
      iterate_recurrence(
        from,
        step,
        occurrence_end_fn(from, duration, interval),
        fn _start -> true end,
        selection_fn(interval, duration),
        interval.metadata,
        n
      )

    with {:ok, kept} <- keep_within(intervals, opts) do
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

    intervals =
      from
      |> iterate_recurrence(
        duration,
        occurrence_end_fn(from, duration, interval),
        &under_until?(&1, until),
        selection_fn(interval, duration),
        interval.metadata
      )
      |> Enum.filter(&starts_under_until?(&1, until))

    with {:ok, kept} <- keep_within(intervals, opts) do
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
    step = if direction == -1, do: negate_duration(duration), else: duration

    case iterate_recurrence(
           from,
           step,
           occurrence_end_fn(from, duration, interval),
           fn _start -> true end,
           selection_fn(interval, duration),
           interval.metadata,
           1
         ) do
      [%Tempo.Interval{} = first | _] ->
        {:ok, first}

      [] ->
        {:error,
         IntervalEndpointsError.exception(
           interval: interval,
           operation: "materialise a count-1 recurrence whose BY-rule selects no occurrence",
           reason: :empty_selection
         )}
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
      to_tempo = Math.add(from, duration)
      {:ok, %Tempo.Interval{from: from, to: to_tempo, metadata: metadata}}
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
      from_tempo = Math.subtract(to, duration)
      {:ok, %Tempo.Interval{from: from_tempo, to: to, metadata: metadata}}
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
         reach = domain_reach_window(window, interval),
         {:ok, closed_domain} <- close_domain_ranges(domain, reach),
         {:ok, domain_set} <- to_interval(closed_domain) do
      domain_set
      |> IntervalSet.to_list()
      |> filter_domain_years(domain.filter)
      |> step_domain_periods(domain, interval.duration)
      |> Enum.filter(&domain_period_in_window?(&1, reach))
      |> reduce_domain_occurrences(interval, opts)
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
      |> IntervalSet.to_list()
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
           operation: "materialise a recurrence that has no start",
           reason: :open_start
         )}

      within ->
        case window_start(within, interval) do
          {:ok, start} -> materialise_from_bound(interval, start, within, opts)
          {:error, _} = error -> error
        end
    end
  end

  defp materialise(%Tempo.Interval{} = interval, _opts) do
    {:ok, interval}
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
    {:error, MaterialisationError.exception(value: value, reason: :one_of_set)}
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
    {:error, MaterialisationError.exception(value: range, reason: :open_range)}
  end

  defp materialise(%Tempo.Duration{} = value, _opts) do
    {:error, MaterialisationError.exception(value: value, reason: :bare_duration)}
  end

  # A recurrence with no end is ended by the caller's `:within` window; with
  # none it cannot be materialised.
  defp materialise_unending(interval, nil, _opts),
    do: {:error, UnboundedRecurrenceError.exception(interval: interval)}

  defp materialise_unending(
         %Tempo.Interval{from: from, duration: duration} = interval,
         within,
         opts
       ) do
    with {:ok, window_to} <- bound_upper(within),
         {from, interval} = fill_selection_start(from, interval),
         intervals =
           iterate_recurrence(
             from,
             duration,
             occurrence_end_fn(from, duration, interval),
             &under_bound?(&1, window_to),
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
      tag_start_calendar(aligned, calendar)
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

  # Attach the calendar's IXDTF `u-ca` identifier to the synthesised start's
  # extended metadata, so each materialised occurrence round-trips as
  # `[u-ca=tag]` — the same self-describing form a written calendared start
  # gives its occurrences. A calendar with no faithful identifier is left as is.
  defp tag_start_calendar(%Tempo{} = start, calendar) do
    case repeat_calendar_tag(calendar) do
      nil ->
        start

      tag ->
        attach_extended(start, %{
          calendar: tag,
          zone_id: nil,
          zone_offset: nil,
          zone_critical: false,
          tags: %{}
        })
    end
  end

  # A calendar module's IXDTF `u-ca` identifier: a non-CLDR calendar Calendrical
  # resolves (`Calendrical.Julian` → `:julian`) through its additional-calendar
  # registry, otherwise the CLDR type — but only when that type round-trips back
  # to the same module, so a calendar whose type names a different one
  # (`Calendrical.ISOWeek`, typed `:gregorian`) stays untagged rather than
  # mis-tagged.
  defp repeat_calendar_tag(calendar) do
    case additional_calendar_tag(calendar) do
      nil -> faithful_cldr_tag(calendar)
      tag -> tag
    end
  end

  defp additional_calendar_tag(calendar) do
    Enum.find_value(Calendrical.additional_calendars(), fn {tag, module} ->
      if module == calendar, do: tag
    end)
  end

  defp faithful_cldr_tag(calendar) do
    with true <- function_exported?(calendar, :cldr_calendar_type, 0),
         calendar_type = calendar.cldr_calendar_type(),
         {:ok, ^calendar} <- Calendrical.calendar_from_cldr_calendar_type(calendar_type) do
      calendar_type
    else
      _other -> nil
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
  # after — so a windowed recurrence also walks as many periods either side of
  # the window as the §12.10 window can reach across, and keeps the occurrences
  # that overlap the window.
  defp materialise_from_bound(interval, start, within, opts) do
    case window_periods(interval) do
      {0, 0} ->
        %{interval | from: start_in_repeat_calendar(start, interval)}
        |> to_interval(opts)
        |> filter_to_bound_window(interval, within)

      periods ->
        materialise_windowed(interval, start, within, periods, opts)
    end
  end

  defp materialise_windowed(
         %Tempo.Interval{duration: cadence} = interval,
         start,
         within,
         {periods_before, periods_after},
         opts
       ) do
    with {:ok, window_to} <- bound_upper(within) do
      widened_from = add_n_durations(start, negate_duration(cadence), periods_before)
      widened_to = add_n_durations(window_to, cadence, periods_after)
      widened = %Tempo.Interval{from: widened_from, to: widened_to}

      %{interval | from: start_in_repeat_calendar(widened_from, interval)}
      |> to_interval(Keyword.put(opts, :within, widened))
      |> keep_occurrences_in_window({bound_lower(within), window_to})
    end
  end

  # How many cadence periods before and after a bound a §12.10 window can reach
  # into it from: a window running forward from an earlier period, or back from
  # a later one. Each direction's durations are summed (a nested window adds its
  # own) over the shortest the cadence period can be, plus one for the period
  # itself; none when the selection has no window that way, or the cadence is
  # finer than a day.
  defp window_periods(%Tempo.Interval{
         repeat_rule: %Tempo{time: [selection: selection]},
         duration: %Tempo.Duration{} = cadence
       }) do
    durations = window_durations(selection)
    floor = cadence_days_floor(cadence)

    {periods_reaching(reach_days(durations, :forward), floor),
     periods_reaching(reach_days(durations, :backward), floor)}
  end

  defp window_periods(_interval), do: {0, 0}

  defp periods_reaching(0, _floor), do: 0
  defp periods_reaching(_reach, 0), do: 0
  defp periods_reaching(reach, floor), do: 1 + div(reach, floor)

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

  # The most days the windows' durations can span one way (a year is at most
  # 366 days, a month 31); any time-of-day part counts as a whole day.
  defp reach_days(durations, direction) do
    for %Tempo.Duration{time: time} <- durations,
        {unit, amount} <- time,
        reaches?(amount, direction),
        reduce: 0 do
      total -> total + Kernel.ceil(abs(amount) * max_days_per(unit))
    end
  end

  defp reaches?(amount, :forward), do: amount > 0
  defp reaches?(amount, :backward), do: amount < 0

  defp max_days_per(:year), do: 366
  defp max_days_per(:month), do: 31
  defp max_days_per(:week), do: 7
  defp max_days_per(_unit), do: 1

  # The fewest days a cadence period spans (a year is at least 365, a month 28);
  # zero for a cadence finer than a day.
  defp cadence_days_floor(%Tempo.Duration{time: time}) do
    Enum.reduce(time, 0, fn {unit, amount}, total ->
      total + Kernel.trunc(abs(amount) * min_days_per(unit))
    end)
  end

  defp min_days_per(:year), do: 365
  defp min_days_per(:month), do: 28
  defp min_days_per(:week), do: 7
  defp min_days_per(:day), do: 1
  defp min_days_per(_unit), do: 0

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
    scaled = Enum.map(time, fn {unit, amount} -> {unit, amount * n} end)
    Math.add(tempo, %Tempo.Duration{time: scaled})
  end

  defp negate_duration(%Tempo.Duration{time: time}) do
    negated = Enum.map(time, fn {unit, amount} -> {unit, -amount} end)
    %Tempo.Duration{time: negated}
  end

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
    |> recurrence_candidates(cadence, occurrence_end, metadata)
    |> Stream.take_while(fn {start, _} -> start_predicate.(start) end)
    |> Stream.take(@recurrence_safety_cap)
    |> Stream.flat_map(fn {_start, candidate} -> selection_fn.(candidate) end)
    # DTSTART floor — per RFC 5545, DTSTART is always the first
    # occurrence. BY-rule EXPAND can legitimately produce dates
    # earlier in the DTSTART-containing period (e.g.
    # BYMONTHDAY=1 with DTSTART=Sep 30 → also Sep 1). Drop any
    # such pre-DTSTART candidates.
    |> Stream.reject(fn %Tempo.Interval{from: f} -> before_dtstart?(f, from) end)
    |> Stream.take(output_limit)
    |> Enum.to_list()
  end

  # Contiguous fast path: walk the starts once and pair each with the
  # next, so occurrence i's `to` is occurrence i+1's `from`. One
  # `Math.add` per occurrence instead of two.
  defp recurrence_candidates(from, cadence, :contiguous, metadata) do
    occurrence_metadata = strip_span_directives(metadata)

    from
    |> Stream.iterate(&Math.add(&1, cadence))
    |> Stream.chunk_every(2, 1, :discard)
    |> Stream.map(fn [start, next_start] ->
      {start, %Tempo.Interval{from: start, to: next_start, metadata: occurrence_metadata}}
    end)
  end

  # General path: each start is `from + i × cadence` (scaled, so
  # month/year cadences don't clamp-drift) and the `to` comes from the
  # end function.
  defp recurrence_candidates(from, cadence, occurrence_end_fn, metadata)
       when is_function(occurrence_end_fn, 2) do
    occurrence_metadata = strip_span_directives(metadata)

    0
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(fn i ->
      start = add_n_durations(from, cadence, i)

      {start,
       %Tempo.Interval{
         from: start,
         to: occurrence_end_fn.(start, i),
         metadata: occurrence_metadata
       }}
    end)
  end

  # `occurrence_duration` / `occurrence_base_to` are *directives* to
  # this materialiser — they say how to span each occurrence. Once the
  # span is fixed in `from`/`to` they've done their job, so they're
  # dropped from the emitted occurrences rather than riding along as
  # pseudo-semantic metadata (which would surface, e.g., in inspect).
  defp strip_span_directives(metadata) when is_map(metadata) do
    Map.drop(metadata, [:occurrence_duration, :occurrence_base_to])
  end

  defp strip_span_directives(metadata), do: metadata

  defp before_dtstart?(%Tempo{} = candidate_from, %Tempo{} = dtstart) do
    Compare.compare_endpoints(candidate_from, dtstart) == :earlier
  end

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
    resize? = not explicit_occurrence_span?(metadata)
    origin_day = origin_day_of(interval)

    fn candidate ->
      candidate
      |> Selection.apply(rule, freq, origin_day: origin_day)
      |> resize_selected_occurrences(resize?)
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

  # A selection picks *points* at its own resolution — "the 15th"
  # is the day the 15th, not the month it sits in. The candidate the
  # selection expands spans a whole cadence period (so the resolver
  # can see the enclosing month/year), so each selected occurrence
  # inherits that period as its span. Unless the recurrence carries
  # an explicit event span (a DTEND-style `occurrence_base_to` or
  # `occurrence_duration`), resize each occurrence to one unit of its
  # own resolution. This keeps native `~o".../FL15DN"`, RRULE, and
  # cron consistent without storing any per-occurrence metadata.
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
  #    occurrence spans one cadence.
  defp occurrence_end_fn(
         %Tempo{} = _from,
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

      true ->
        fn start, _i -> Math.add(start, duration) end
    end
  end

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

  # A start lies in the half-open span `[span_from, span_to)`.
  defp in_bound_window?(%Tempo{} = from, %Tempo{} = span_from, %Tempo{} = span_to) do
    at_or_after_bound?(from, span_from) and under_bound?(from, span_to)
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
        |> IntervalSet.to_list()
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
      |> IntervalSet.to_list()
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
         %Tempo.Interval{repeat_rule: %Tempo{time: [selection: [_ | _]]}} = interval
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
  # *day*). With no selection, the day floor keeps a plain cadence
  # (`R/../P1D`) walking days.
  defp start_unit(%Tempo.Interval{repeat_rule: %Tempo{time: [selection: selection]}})
       when selection != [] do
    # The finest unit is the last selection component (they are written
    # coarse-to-fine). Read it straight from the AST rather than through
    # `resolution/1`, whose declared `time_unit()` return elides the
    # selection-only keys (`:byday`, `:day_of_week`) this must normalise.
    {finest_unit, _value} = List.last(selection)
    calendar_start_unit(finest_unit)
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
       when unit in [:byday, :day_of_week, :day_of_year, :instance, :event],
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

  # A "non-contiguous mask" is a mask at some unit followed by
  # one or more concrete units: `1985-XX-15` (month masked, day
  # concrete) produces 12 disjoint day-intervals, not a single
  # year-wide span. When detected, rewrite the mask position to
  # the list of valid candidate values (calendar-aware) so the
  # existing multi-expansion path handles it.
  #
  # A mask with only masks after it (`1985-XX-XX`) is still
  # "contiguous widening" — no concrete unit pins a sub-span, so
  # the enclosing year interval is the right representation.
  defp expand_non_contiguous_mask(%Tempo{time: time, calendar: calendar} = tempo) do
    case find_non_contiguous_mask(time, [], calendar) do
      nil -> {:ok, tempo}
      {new_time} -> {:ok, %{tempo | time: new_time}}
      {:error, :unanchored} -> {:error, UnanchoredError.exception(value: tempo)}
    end
  end

  defp find_non_contiguous_mask([], _previous, _calendar), do: nil

  defp find_non_contiguous_mask([{unit, {:mask, mask}} | rest], previous, calendar) do
    if tail_has_concrete?(rest) do
      # Non-contiguous: substitute the mask with candidate values.
      substitute_mask(unit, mask, Enum.reverse(previous), rest, calendar)
    else
      nil
    end
  end

  defp find_non_contiguous_mask([entry | rest], previous, calendar) do
    find_non_contiguous_mask(rest, [entry | previous], calendar)
  end

  # Use a scalar when exactly one candidate survives the calendar
  # constraint; otherwise a list, which the multi path expands via
  # `Enumerable`.
  defp substitute_mask(unit, mask, prefix, rest, calendar) do
    case Mask.valid_values(unit, mask, prefix, calendar) do
      {:ok, [single]} -> {prefix ++ [{unit, single}] ++ rest}
      {:ok, many} -> {prefix ++ [{unit, many}] ++ rest}
      {:error, :unanchored} = error -> error
    end
  end

  defp tail_has_concrete?([]), do: false
  defp tail_has_concrete?([{_unit, {:mask, _}} | rest]), do: tail_has_concrete?(rest)
  defp tail_has_concrete?([{_unit, :any} | rest]), do: tail_has_concrete?(rest)

  defp tail_has_concrete?([{_unit, value} | _rest]) when is_integer(value) do
    true
  end

  defp tail_has_concrete?([_ | rest]), do: tail_has_concrete?(rest)

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
    intervals =
      tempo
      |> expand_members()
      |> Enum.map(fn member ->
        case normalise_member(member) do
          {:ok, %Tempo{} = resolved} -> to_interval(resolved)
          {:error, _} = err -> err
        end
      end)

    case Enum.find(intervals, &match?({:error, _}, &1)) do
      nil ->
        intervals
        |> Enum.map(fn {:ok, i} -> i end)
        |> IntervalSet.new()

      {:error, _} = err ->
        err
    end
  end

  # Any combination of ranges, in any component positions, expands
  # through the cartesian expander — each component resolves against
  # its already-concrete coarser units, so nested open ranges
  # (`{2000..2010}Y{1..-1}M{1..-1}D`) terminate. Shapes it does not
  # cover (masks, groups, `:any`) keep the odometer walk.
  defp expand_members(%Tempo{} = tempo) do
    case Enumeration.expand(tempo) do
      {:ok, members} -> members
      :not_expandable -> Enum.to_list(tempo)
    end
  end

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
            {:cont, {:ok, Enum.reverse(IntervalSet.to_list(inner_set)) ++ acc}}

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

  # Materialise a recurrence's selection once per year of its domain (each an
  # interval from the domain set), unioning the occurrences. The domain year is
  # passed as the `:within` window, so the open-start materialisation projects
  # the selection onto it.
  # Adjacent domain periods — each starting where the one before ends, as the
  # years of `{2020Y..2024Y}` do — run as one recurrence across them, so the
  # periods a §12.10 window must look into beyond the run are looked into once
  # per run rather than once per period. A run keeps the occurrences that start
  # within it — exactly those its periods would each keep — so a neighbouring
  # year outside the domain contributes none.
  defp reduce_domain_occurrences(domain_intervals, %Tempo.Interval{} = interval, opts) do
    domain_intervals
    |> adjacent_periods()
    |> Enum.reduce_while({:ok, []}, fn {first, last}, {:ok, acc} ->
      run_from = Interval.from(first)
      run_to = Interval.to(last)
      run = %Tempo.Interval{from: run_from, to: run_to}

      case to_interval(%{interval | from: nil}, Keyword.put(opts, :within, run)) do
        {:ok, %Tempo.IntervalSet{} = set} ->
          own =
            set |> IntervalSet.to_list() |> Enum.filter(&starts_in_window?(&1, run_from, run_to))

          {:cont, {:ok, acc ++ own}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, intervals} -> IntervalSet.new(intervals)
      {:error, _} = err -> err
    end
  end

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
  # the window: the periods the window overlaps, and as many either side as a
  # §12.10 window can reach across (a December–January break yielded by 2025
  # overlaps a window in January 2026). The rest are skipped.
  defp domain_period_in_window?(_period, :none), do: true

  defp domain_period_in_window?(%Tempo.Interval{} = period, {window_from, window_to}),
    do: overlaps_window?(period, window_from, window_to)

  defp domain_reach_window(:none, _interval), do: :none

  defp domain_reach_window({window_from, window_to} = window, %Tempo.Interval{} = interval) do
    case window_periods(interval) do
      {0, 0} ->
        window

      {periods_before, periods_after} ->
        cadence = interval.duration

        {window_from && add_n_durations(window_from, negate_duration(cadence), periods_before),
         window_to && add_n_durations(window_to, cadence, periods_after)}
    end
  end

  defp keep_occurrences_in_window(result, :none), do: result

  defp keep_occurrences_in_window({:ok, %Tempo.IntervalSet{} = set}, window) do
    set
    |> IntervalSet.to_list()
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

  # A domain run keeps the occurrences its own periods yield: those that start
  # within the run's span. (The caller's window then keeps those that overlap it.)
  defp starts_in_window?(%Tempo.Interval{from: %Tempo{} = from}, window_from, window_to),
    do: in_bound_window?(from, window_from, window_to)

  defp starts_in_window?(_occurrence, _window_from, _window_to), do: true

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
    case Enum.reject(conditionals, &valid_conditional?/1) do
      [] ->
        :ok

      [invalid | _] ->
        {:error, MaterialisationError.exception(value: invalid, reason: :conditional_member)}
    end
  end

  defp valid_conditional?(%Conditional{falls_on: falls_on, at: [_ | _] = offsets, to_next: nil}),
    do: valid_falls_on?(falls_on) and Enum.all?(offsets, &match?(%Tempo.Duration{}, &1))

  defp valid_conditional?(%Conditional{falls_on: falls_on, at: nil, to_next: %Tempo{}}),
    do: valid_falls_on?(falls_on)

  defp valid_conditional?(_conditional), do: false

  # What a condition falls on: a metadata map the other members' occurrences are
  # matched against, or a recurrence set whose own occurrences it reads.
  defp valid_falls_on?(%Tempo.RecurrenceSet{}), do: true
  defp valid_falls_on?(%_struct{}), do: false
  defp valid_falls_on?(falls_on), do: is_map(falls_on)

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
              IntervalSet.to_list(occurrences),
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
        {[negate_duration(selection_search_span(selector)) | lower], upper}
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
    {:error, MaterialisationError.exception(value: member, reason: :recurrence_set_member)}
  end

  defp recurrence_set_occurrences(%Tempo.Interval{} = interval), do: [interval]
  defp recurrence_set_occurrences(%Tempo.IntervalSet{} = set), do: IntervalSet.to_list(set)

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
  an interval set instead of a list. Each result is materialised with
  `Tempo.to_interval/1`, so `fun` may return either a `t:t/0` — a day
  becomes its `[day, next_day)` span — or an interval. Members are kept
  distinct (no coalescing); apply `Tempo.IntervalSet.coalesce/1` afterward
  if you want touching spans merged.

  Raises if a mapped value cannot be materialised into a bounded interval.
  Use `try_map/2` for the error-returning form.

  ### Arguments

  * `enumerable` is any enumerable of Tempo values.

  * `fun` is a one-arity function applied to each element.

  ### Returns

  * a `t:Tempo.IntervalSet.t/0` of the mapped, materialised values.

  ### Examples

      iex> [~o"2025-07-04", ~o"2026-07-04", ~o"2027-07-04"]
      ...> |> Tempo.map(&Tempo.nearest_working_day(&1, :US))
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
  value that cannot be materialised, returning its `{:error, reason}`.

  This is the "traverse" form — map every element, or stop at the first
  failure and report it — analogous to Gleam's `list.try_map` or a Rust
  `collect::<Result<_, _>>()`. `fun` returns a plain Tempo value (exactly
  as for `map/2`); the error is the first result that `Tempo.to_interval/1`
  rejects (an unbounded, unanchored, or otherwise un-materialisable
  value), so a partially-resolvable set never yields a partial result.

  ### Arguments

  * `enumerable` is any enumerable of Tempo values.

  * `fun` is a one-arity function applied to each element.

  ### Returns

  * `{:ok, interval_set}` when every mapped value materialises, or

  * `{:error, reason}` for the first that does not.

  ### Examples

      iex> {:ok, set} = Tempo.try_map([~o"2025-07-04", ~o"2026-07-04"], &Tempo.nearest_working_day(&1, :US))
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
    MaterialisationError.exception(value: tempo, reason: reason)
  end

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
         {:ok, years} <- selection_years(tempo, Keyword.get(context, :year), window) do
      for year <- years,
          member <- context_members(%{tempo | time: [{:year, year} | finer_context]}),
          occurrence <- member_selection(member, rule, cadence) do
        occurrence
      end
      |> IntervalSet.new()
      |> keep_occurrences_in_window(window)
      |> with_trailing_units(trailing)
    end
  end

  # The dates the selection picks in one period of the context: the period,
  # filled down to the grain the selection names, as the one candidate the
  # selection resolves in.
  defp member_selection(%Tempo{} = member, rule, cadence) do
    {start, recurrence} =
      fill_selection_start(member, %Tempo.Interval{from: member, repeat_rule: rule})

    %Tempo.Interval{from: start, to: Math.add(start, cadence)}
    |> Selection.apply(rule, freq_of(cadence), origin_day: origin_day_of(recurrence))
    |> resize_selected_occurrences(true)
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
    if multi_tempo?(member), do: Enum.to_list(expand_members(member)), else: [member]
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
      |> IntervalSet.to_list()
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
    |> IntervalSet.to_list()
    |> Enum.reduce_while({:ok, []}, fn %Tempo.Interval{from: %Tempo{} = from}, {:ok, acc} ->
      case to_interval(%{from | time: Keyword.merge(from.time, trailing)}) do
        {:ok, %Tempo.Interval{} = interval} ->
          {:cont, {:ok, [interval | acc]}}

        {:ok, %IntervalSet{} = expanded} ->
          {:cont, {:ok, Enum.reverse(IntervalSet.to_list(expanded)) ++ acc}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, intervals} -> IntervalSet.new(Enum.reverse(intervals))
      {:error, _reason} = error -> error
    end
  end

  defp with_trailing_units({:error, _reason} = error, _trailing), do: error

  defp do_to_interval(%Tempo{} = tempo) do
    # Step 1: if the Tempo has a non-contiguous mask (a mask
    # followed by concrete units — e.g. `1985-XX-15`), rewrite the
    # time list to substitute the mask with the list of valid
    # values. This turns a previously-widened case into a proper
    # multi-interval expansion.
    with {:ok, tempo} <- expand_non_contiguous_mask(tempo) do
      materialise_expanded(tempo)
    end
  end

  defp materialise_expanded(%Tempo{} = tempo) do
    # Step 2: detect whether the resulting Tempo expands to
    # multiple intervals. A "multi" shape is any time slot whose
    # value is a list containing more than one candidate (ranges,
    # multi-element lists). Masks, scalars, and single-element
    # lists use the existing single-interval path in
    # `next_unit_boundary/1`.
    if multi_tempo?(tempo) do
      materialise_multi(tempo)
    else
      # The bounds keep the value's own resolution; the iteration
      # granularity of the implicit span travels on `:unit` (see
      # `Tempo.Interval.next_unit_boundary/1`).
      case Interval.next_unit_boundary(tempo) do
        {:ok, {lower, upper}, unit} -> {:ok, %Tempo.Interval{from: lower, to: upper, unit: unit}}
        {:error, _} = err -> err
      end
    end
  end

  @doc """
  Raising version of `to_interval/1`.

  ### Arguments

  * `value` is a `t:#{__MODULE__}.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.IntervalSet.t/0`, or `t:Tempo.Set.t/0`.

  ### Returns

  * The materialised `t:Tempo.Interval.t/0` or
    `t:Tempo.IntervalSet.t/0`.

  ### Raises

  * `ArgumentError` when the input cannot be materialised. See
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
  Return the length of an interval, or the time an interval set
  covers, as a `%Tempo.Duration{}`.

  A length is counted in the unit its endpoints are written in: two
  days are a number of days apart, two times of day a number of hours
  or minutes — see `Tempo.Interval.duration/1`. A set's duration
  counts time that two members share once — see
  `Tempo.IntervalSet.duration/1`.

  ### Arguments

  * `value` is a `t:Tempo.Interval.t/0` or a `t:Tempo.IntervalSet.t/0`.

  ### Returns

  * A `t:Tempo.Duration.t/0` in the endpoints' unit, or `:infinity`
    for an interval with an open end.

  ### Examples

      iex> Tempo.duration(Tempo.to_interval!(~o"2026-06-15T09:00/2026-06-15T10:30"))
      ~o"PT90M"

      iex> Tempo.duration(Tempo.to_interval!(~o"2026-06"))
      ~o"P1M"

      iex> bookings = Tempo.IntervalSet.new!([~o"2026-06-15T09/2026-06-15T11", ~o"2026-06-15T10/2026-06-15T12"])
      iex> Tempo.duration(bookings)
      ~o"PT3H"

  """
  def duration(%IntervalSet{} = set), do: IntervalSet.duration(set)
  def duration(interval), do: Interval.duration(interval)

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
        with {:ok, interval} <- Interval.new(from, to) do
          {:ok, Interval.duration(interval)}
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
  def duration!(%__MODULE__{} = from, %__MODULE__{} = to) do
    case duration(from, to) do
      {:ok, duration} -> duration
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "Tempo.duration!/2 failed: #{inspect(reason)}"
    end
  end

  @doc """
  `true` when the interval is at least as long as the given
  duration. See `Tempo.Interval.at_least?/2`.
  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.at_least?(meeting, ~o"PT1H")
      true
      iex> Tempo.at_least?(meeting, ~o"PT2H")
      false

  """
  defdelegate at_least?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when the interval is at most as long as the given
  duration. See `Tempo.Interval.at_most?/2`.
  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.at_most?(meeting, ~o"PT2H")
      true
      iex> Tempo.at_most?(meeting, ~o"PT1H")
      false

  """
  defdelegate at_most?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when the interval's length equals the given duration.
  See `Tempo.Interval.exactly?/2`.
  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.exactly?(meeting, ~o"PT90M")
      true
      iex> Tempo.exactly?(meeting, ~o"PT1H")
      false

  """
  defdelegate exactly?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when the interval is strictly longer than the given
  duration. See `Tempo.Interval.longer_than?/2`.
  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.longer_than?(meeting, ~o"PT1H")
      true
      iex> Tempo.longer_than?(meeting, ~o"PT90M")
      false

  """
  defdelegate longer_than?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when the interval is strictly shorter than the given
  duration. See `Tempo.Interval.shorter_than?/2`.
  ### Examples

      iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
      iex> Tempo.shorter_than?(meeting, ~o"PT2H")
      true
      iex> Tempo.shorter_than?(meeting, ~o"PT90M")
      false

  """
  defdelegate shorter_than?(interval, duration), to: Tempo.Interval

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
  defdelegate bounded?(interval), to: Tempo.Interval

  @doc """
  `true` when the interval has zero length. See
  `Tempo.Interval.empty?/1`.
  ### Examples


      iex> Tempo.empty?(Tempo.to_interval!(~o"2026-06-15"))
      false

  """
  defdelegate empty?(interval), to: Tempo.Interval

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
  constructed by `Tempo.workdays/1` and `Tempo.weekend/1` and
  composed in at the call site.

  See `Tempo.Select` for the full vocabulary.

  ### Examples

      iex> {:ok, set} = Tempo.select(~o"2026-02", [1, 15])
      iex> set |> Tempo.IntervalSet.to_list() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [1, 15]

      iex> {:ok, set} = Tempo.select(~o"2026", ~o"12-25")
      iex> [xmas] = Tempo.IntervalSet.to_list(set)
      iex> from = Tempo.Interval.from(xmas)
      iex> {Tempo.year(from), Tempo.month(from), Tempo.day(from)}
      {2026, 12, 25}

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
  Return a selector that matches the workdays of a territory —
  the days of week that are *not* in that territory's weekend.

  Together, `workdays/1` and `weekend/1` partition the seven days
  of the week: `workdays(:US) ++ weekend(:US)` spans Monday..Sunday.

  ### Arguments

  * `territory` is an atom, string, locale, or `%Localize.LanguageTag{}`
    resolved through `Tempo.Territory.resolve/1`. Defaults to `nil`,
    which walks the territory-resolution chain (app config, then
    ambient locale).

  ### Returns

  * A `t:Tempo.t/0` value carrying a `day_of_week` list. Composable
    directly with `Tempo.select/2`.

  ### Examples

      iex> {:ok, set} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      iex> Tempo.IntervalSet.count(set)
      20

      iex> Tempo.workdays(:US).time
      [day_of_week: [1, 2, 3, 4, 5]]

  """
  @spec workdays(Tempo.Territory.input()) :: Tempo.t()
  def workdays(territory \\ nil) do
    {:ok, resolved} = Territory.resolve(territory)
    day_of_week_tempo(Localize.Calendar.weekdays(resolved))
  end

  @doc """
  Return a selector that matches the weekend days of a territory.

  Different territories weekend on different days: the United
  States is `[Saturday, Sunday]`, Saudi Arabia is `[Friday,
  Saturday]`, India is `[Sunday]`. `Tempo.weekend/1` reads that
  definition from CLDR via Localize and returns it as a
  composable selector.

  ### Arguments

  * `territory` is an atom, string, locale, or `%Localize.LanguageTag{}`
    resolved through `Tempo.Territory.resolve/1`. Defaults to `nil`,
    which walks the territory-resolution chain.

  ### Returns

  * A `t:Tempo.t/0` value carrying a `day_of_week` list. Composable
    directly with `Tempo.select/2`.

  ### Examples

      iex> {:ok, us} = Tempo.select(~o"2026-02", Tempo.weekend(:US))
      iex> us |> Tempo.IntervalSet.to_list() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [1, 7, 8, 14, 15, 21, 22, 28]

      iex> {:ok, sa} = Tempo.select(~o"2026-02", Tempo.weekend(:SA))
      iex> sa |> Tempo.IntervalSet.to_list() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [6, 7, 13, 14, 20, 21, 27, 28]

  """
  @spec weekend(Tempo.Territory.input()) :: Tempo.t()
  def weekend(territory \\ nil) do
    {:ok, resolved} = Territory.resolve(territory)
    day_of_week_tempo(Localize.Calendar.weekend(resolved))
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

  * Raises `ArgumentError` when `tempo` does not denote a day (for
    example a year- or month-resolution value).

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
  @spec weekend?(t(), Tempo.Territory.input()) :: boolean()
  def weekend?(%Tempo{} = tempo, territory \\ nil) do
    {:ok, resolved} = Territory.resolve(territory)
    day_of_week_iso(tempo, :weekend?) in Localize.Calendar.weekend(resolved)
  end

  @doc """
  An unbounded lazy set of weekend days, walking forward from a start
  date.

  The result is a `t:Tempo.IntervalSet.t/0` on the lazy backend: each
  member is one weekend day's span, generated on demand and never
  materialised in full. Use it wherever a walk suffices — most
  naturally as a `Tempo.shift/3` `skipping:` busy set, with no
  `:within` window required:

      Tempo.shift(start, ~o"P3D", skipping: Tempo.weekends(from: start))

  Aggregate operations (`Tempo.IntervalSet.to_list/1`, `count/1`, set
  algebra) raise `Tempo.UnboundedSetError` — take the members you need
  from `Tempo.IntervalSet.walk/1` instead.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:from` is the day the walk starts at (inclusive). The default is
    `Tempo.today/0`.

  * `:territory` selects whose weekend applies, resolved through
    `Tempo.Territory.resolve/1` as for `weekend?/2` — `:SA` weekends
    on Friday–Saturday, `:IN` on Sunday only.

  ### Returns

  * A `t:Tempo.IntervalSet.t/0` on the lazy backend.

  ### Examples

      iex> weekends = Tempo.weekends(from: ~o"2026-06-15")
      iex> weekends |> Tempo.IntervalSet.walk() |> Enum.take(2) |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [20, 21]

      iex> saudi = Tempo.weekends(from: ~o"2026-06-15", territory: :SA)
      iex> saudi |> Tempo.IntervalSet.walk() |> Enum.take(2) |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
      [19, 20]

  """
  @spec weekends(keyword()) :: Tempo.IntervalSet.t()
  def weekends(options \\ []) do
    from = Keyword.get_lazy(options, :from, &today/0)
    territory = Keyword.get(options, :territory)

    from
    |> Stream.iterate(&shift(&1, day: 1))
    |> Stream.filter(&weekend?(&1, territory))
    |> Stream.map(&to_interval!/1)
    |> IntervalSet.from_stream()
  end

  @doc """
  Return `true` when `tempo` falls on a workday — a day that is *not*
  in the territory's weekend.

  The complement of `weekend?/2`; together they partition the week.
  This is the weekend/weekday distinction only — it does not consult
  public-holiday calendars.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a single day.

  * `territory` is resolved through `Tempo.Territory.resolve/1`, as for
    `weekend?/2`.

  ### Returns

  * `true` when the value's day of week is not a weekend day in the
    territory, `false` otherwise.

  ### Examples

      iex> Tempo.workday?(~o"2026-06-15", :US)
      true

      iex> Tempo.workday?(~o"2026-06-13", :US)
      false

  """
  @spec workday?(t(), Tempo.Territory.input()) :: boolean()
  def workday?(%Tempo{} = tempo, territory \\ nil) do
    not weekend?(tempo, territory)
  end

  @doc """
  Shift `tempo` by `count` working days, skipping the territory's
  weekend.

  A positive `count` moves forward, a negative `count` backward, and
  `0` returns the value unchanged. Each counted step lands on a working
  day, so adding one working day to a Friday returns the following
  Monday (in a Saturday/Sunday-weekend territory). The time of day,
  calendar, and zone are preserved.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a single day (a date or
    datetime).

  * `count` is the integer number of working days to add — negative to
    subtract.

  * `territory` is resolved through `Tempo.Territory.resolve/1`, as for
    `weekend?/2`.

  ### Returns

  * a `t:t/0` that is `count` working days from `tempo`.

  ### Examples

      iex> Tempo.add_working_days(~o"2026-06-12", 1, :US)
      ~o"2026Y6M15D"

      iex> Tempo.add_working_days(~o"2026-06-15", -1, :US)
      ~o"2026Y6M12D"

      iex> # Five working days on from a Monday is the next Monday.
      iex> Tempo.add_working_days(~o"2026-06-15", 5, :US)
      ~o"2026Y6M22D"

      iex> # The weekend differs by territory (Saudi Arabia: Friday/Saturday).
      iex> Tempo.add_working_days(~o"2026-06-11", 1, :SA)
      ~o"2026Y6M14D"

  """
  @spec add_working_days(t(), integer(), Tempo.Territory.input()) :: t()
  def add_working_days(%Tempo{} = tempo, count, territory \\ nil) when is_integer(count) do
    # weekend?/2 validates that the value denotes a day and resolves the
    # territory, so a coarse value or bad territory fails up front.
    _ = weekend?(tempo, territory)
    step = if count < 0, do: -1, else: 1

    Enum.reduce(1..abs(count)//1, tempo, fn _, day ->
      advance_to_working_day(day, step, territory)
    end)
  end

  @doc """
  The next working day strictly after `tempo` in the territory.

  Equivalent to `add_working_days(tempo, 1, territory)`.

  ### Examples

      iex> Tempo.next_working_day(~o"2026-06-12", :US)
      ~o"2026Y6M15D"

  """
  @spec next_working_day(t(), Tempo.Territory.input()) :: t()
  def next_working_day(%Tempo{} = tempo, territory \\ nil) do
    add_working_days(tempo, 1, territory)
  end

  @doc """
  The working day immediately before `tempo` in the territory.

  Equivalent to `add_working_days(tempo, -1, territory)`.

  ### Examples

      iex> Tempo.previous_working_day(~o"2026-06-15", :US)
      ~o"2026Y6M12D"

  """
  @spec previous_working_day(t(), Tempo.Territory.input()) :: t()
  def previous_working_day(%Tempo{} = tempo, territory \\ nil) do
    add_working_days(tempo, -1, territory)
  end

  @doc """
  The nearest working day to `tempo` in the territory — `tempo` itself
  when it already is a working day, otherwise the closest day that is not
  in the territory's weekend.

  Distance is measured outward in both directions and the nearer working
  day wins, ties broken toward the preceding day. For the usual two-day
  weekend this reproduces the common "observed holiday" rule — a Saturday
  rolls back to Friday, a Sunday forward to Monday — which is how a
  fixed-date public holiday such as US Independence Day is observed when
  it lands on a weekend.

  Like the rest of the working-day family this is weekend-aware but not
  holiday-aware: the weekend is the territory's (via `Localize`). Subtract
  a holiday `t:Tempo.IntervalSet.t/0` with set operations if you also need
  to step over holidays.

  ### Arguments

  * `tempo` is a `t:t/0` that denotes a single day; a coarser or
    unanchored value raises `ArgumentError`.

  * `territory` is resolved through `Tempo.Territory.resolve/1` and sets
    which days are the weekend.

  ### Returns

  * `tempo` unchanged when it already is a working day, otherwise the
    nearest working day.

  ### Examples

      iex> Tempo.nearest_working_day(~o"2026-07-04", :US)
      ~o"2026Y7M3D"

      iex> Tempo.nearest_working_day(~o"2027-07-04", :US)
      ~o"2027Y7M5D"

      iex> Tempo.nearest_working_day(~o"2025-07-04", :US)
      ~o"2025Y7M4D"

  """
  @spec nearest_working_day(t(), Tempo.Territory.input()) :: t()
  def nearest_working_day(%Tempo{} = tempo, territory \\ nil) do
    # weekend?/2 validates day resolution and resolves the territory, so a
    # coarse value or bad territory fails up front.
    if weekend?(tempo, territory) do
      find_nearest_working_day(tempo, territory, 1)
    else
      tempo
    end
  end

  defp find_nearest_working_day(tempo, territory, distance) when distance <= 7 do
    preceding = shift(tempo, day: -distance)
    following = shift(tempo, day: distance)

    cond do
      not weekend?(preceding, territory) -> preceding
      not weekend?(following, territory) -> following
      true -> find_nearest_working_day(tempo, territory, distance + 1)
    end
  end

  defp find_nearest_working_day(tempo, _territory, _distance) do
    # Unreachable for any real territory — weekends are one or two days —
    # but guard against a pathological all-weekend calendar rather than
    # recurse without end.
    raise ArgumentError, "no working day found within a week of #{inspect(tempo)}"
  end

  @doc """
  Count the working days within an interval, excluding the territory's
  weekend.

  The interval is half-open `[from, to)`, so the result is the number
  of working days from its start up to but not including its end. Any
  day-yielding value works the same way through `Enum` —
  `Enum.count(value, &Tempo.workday?(&1, territory))`.

  ### Arguments

  * `interval` is a `t:Tempo.Interval.t/0` whose boundaries denote days.

  * `territory` is resolved through `Tempo.Territory.resolve/1`.

  ### Returns

  * the count of working days in the interval.

  ### Examples

      iex> {:ok, june} = Tempo.Interval.new(from: ~o"2026-06-01", to: ~o"2026-07-01")
      iex> Tempo.working_days_in(june, :US)
      22

  """
  @spec working_days_in(Tempo.Interval.t(), Tempo.Territory.input()) :: non_neg_integer()
  def working_days_in(%Tempo.Interval{} = interval, territory \\ nil) do
    Enum.count(interval, &workday?(&1, territory))
  end

  defp advance_to_working_day(%Tempo{} = tempo, step, territory) do
    next = shift(tempo, day: step)
    if weekend?(next, territory), do: advance_to_working_day(next, step, territory), else: next
  end

  # ISO day of week (1 = Monday … 7 = Sunday) of the day a value
  # denotes. The day of week is the same in every calendar, but a
  # calendar date carries year/month/day in *its own* calendar, so the
  # date is built in that calendar and then converted to `Calendar.ISO`
  # before reading `Date.day_of_week/1` — ISO's default numbering is a
  # stable Monday-based 1..7, whereas a Calendrical calendar's own
  # `day_of_week` may use a different week start or only support the
  # `:default` ordering. The date-with-time case is covered here (its
  # date part is the year/month/day); the ordinal (day-of-year) and ISO
  # week-date forms are Gregorian/ISO only and resolve through
  # `to_date/1`, which already returns a `Calendar.ISO` date.
  defp day_of_week_iso(%Tempo{time: time} = tempo, function) do
    year = Keyword.get(time, :year)
    month = Keyword.get(time, :month)
    day = Keyword.get(time, :day)

    iso_date =
      if is_integer(year) and is_integer(month) and is_integer(day) do
        with {:ok, date} <- Date.new(year, month, day, calendar_of(tempo)) do
          {:ok, Date.convert!(date, Calendar.ISO)}
        end
      else
        to_date(tempo)
      end

    case iso_date do
      {:ok, %Date{} = date} ->
        Date.day_of_week(date)

      _ ->
        raise ArgumentError,
              "Tempo.#{function}/2 requires a value that denotes a day. " <>
                "Got: #{inspect(tempo)}"
    end
  end

  @doc """
  Return a multi-line prose explanation of any Tempo value —
  what it is, what it spans, and how to work with it.

  Returns a plain string suitable for iex. For structured output
  that renderers can style (ANSI, HTML),
  use `Tempo.Explain.explain/1` directly and pick a formatter.
  ### Examples


      iex> Tempo.explain(~o"2026-06") |> String.split("\\n") |> hd()
      "June 2026."

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
