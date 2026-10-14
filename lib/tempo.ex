defmodule Tempo do
  @moduledoc """
  Time as intervals, not instants.

  Every Tempo expression denotes an ordered set of half-open spans on the
  time line: a value (`2026-06`), an interval (`2026-06-01/2026-07-01`), a
  recurrence (`R5/2026-06-15/P1D`), a set of them (`{2026-06,2026-08}`), or
  one of several (`[2026,2027]`). One struct holds every form, with one
  calendar, one zone and the caller's metadata; `Tempo.Duration` is the one
  companion, a length with no place on the time line.

  See `plans/architecture-redesign.md` for the model: nine laws every
  module holds to, and the forms below.

  ## Errors

  A function that can fail returns `{:ok, value}` or `{:error, exception}`,
  and has a `!` form that raises. A predicate, an accessor and `compare/3`
  answer a bare value (a boolean, a part, `:lt`), and raise their errors, so
  that an error is never read as an answer.

  An argument that should be an expression and is not one (`nil`, a string,
  a `Date`) is a `Tempo.ConversionError` with reason `:not_an_expression`,
  returned or raised as the function's other errors are. Text given to a
  reader that is not a string is an `ArgumentError`, and a zone that is not
  a string a `Tempo.ZoneError`.

  """

  alias Tempo.Algebra
  alias Tempo.Allen
  alias Tempo.Build
  alias Tempo.ConversionError
  alias Tempo.Duration
  alias Tempo.Expand
  alias Tempo.Explain
  alias Tempo.Format
  alias Tempo.FrameError
  alias Tempo.Interop
  alias Tempo.InvalidCalendarError
  alias Tempo.LeapSeconds
  alias Tempo.Limit
  alias Tempo.Measure
  alias Tempo.Options
  alias Tempo.Parts
  alias Tempo.Reader
  alias Tempo.Scale
  alias Tempo.Season
  alias Tempo.Select
  alias Tempo.Shift
  alias Tempo.Spans
  alias Tempo.Text
  alias Tempo.Unit
  alias Tempo.Validate
  alias Tempo.Workdays
  alias Tempo.Writer
  alias Tempo.Zone
  alias Tempo.ZoneError

  # The options of the set operations: a window to place their operands in, and whose metadata a result carries.
  @set_options [:within, :metadata]
  @words_options [:locale, :format, :within, :number_system, :prefer, :except]
  @relative_options [:from, :unit, :format, :locale, :numeric]
  # No unit asked is the largest of which a whole one lies between the two.
  @relative_units [nil, :year, :quarter, :month, :week, :day, :hour, :minute, :second]
  # The days a week can be counted from by `day_of_week/2`.
  @week_starts [:default, :monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @enforce_keys [:form]
  defstruct form: nil,
            calendar: Tempo.Calendar.default(),
            zone: nil,
            shift: nil,
            qualifications: nil,
            metadata: %{}

  # An argument a function takes as an expression: a `%Tempo{}`, or a
  # duration, which a function answers for or refuses by name. Anything else
  # is `:not_an_expression`, returned as a function's other errors are, or
  # raised by one that answers a bare value (decision 39).
  defguardp is_expression(value) when is_struct(value, __MODULE__) or is_struct(value, Duration)

  defp not_an_expression(value),
    do: {:error, ConversionError.exception(value: value, reason: :not_an_expression)}

  # A unit a value is written in, as `trunc/2`, `round/2` and
  # `at_resolution/2` take one.
  defp a_unit(unit) do
    if unit in Unit.order(),
      do: :ok,
      else: {:error, ArgumentError.exception("#{inspect(unit)} is not a unit of a value")}
  end

  @spec not_an_expression!(term()) :: no_return()
  defp not_an_expression!(value),
    do: raise(ConversionError.exception(value: value, reason: :not_an_expression))

  defp not_text(value),
    do: {:error, ArgumentError.exception("text to read is a string, not #{inspect(value)}")}

  defp not_a_zone(value), do: {:error, ZoneError.exception(zone: value, reason: :unknown)}

  @typedoc "A unit a value is written in, or a label a day carries."
  @type unit ::
          :century
          | :decade
          | :year
          | :month
          | :week
          | :day
          | :hour
          | :minute
          | :second
          | :microsecond
          | :day_of_week
          | :day_of_year
          | :quarter
          | :season
          | :traditional_month

  @typedoc """
  A value's units, coarsest first, each with what it holds.
  """
  @type units :: [{unit(), held()}]

  @typedoc """
  The parts of a selection (`L…N`): the units selected, each with what it
  holds; `instance`, `event`, `roll`, `window`, and a nested `selection`.
  """
  @type selection :: [{unit() | :instance | :event | :roll | :window | :selection, term()}]

  @typedoc """
  What a unit holds in a written value: a whole number; a list of whole
  numbers and ranges, a negative counting from the end; a mask of digits,
  `:x` for one unspecified; `:any`, a unit unspecified (`X*`); a number
  with its significant digits or its margin of error; a traditional leap
  month. A group is a unit of its own, `:group`, holding the nth group, or
  several, and the length it counts in: `{2, [month: 3]}` is `2G3MU`, the
  second three months.
  """
  @type held ::
          integer()
          | [integer() | Range.t()]
          | {:mask, [0..9 | :x | :negative]}
          | :any
          | {pos_integer() | [pos_integer() | Range.t()], [{unit(), pos_integer()}]}
          | {integer(), [significant: pos_integer()]}
          | {integer(), [margin: pos_integer()]}
          | {integer(), :leap}

  @typedoc """
  The zone of an expression: a name the zone database knows, or a fixed
  offset from UTC in minutes, with RFC 9557's critical flag.
  """
  @type zone :: %Zone{name: String.t() | nil, offset: integer() | nil, critical: boolean()}

  @typedoc "A written time shift: whole hours, minutes and seconds, the sign on the first that is not zero."
  @type shift :: [{:hour, integer()} | {:minute, integer()} | {:second, integer()}]

  @typedoc """
  What an expression is, as written.

  * `{:value, units}` — a written value, its units coarsest first, each with
    what it holds (`t:held/0`).

  * `{:span, from, to}` — an interval: two ends, each a value, a duration
    (one of the two) or `:open`.

  * `{:every, first, bound, rule}` — a recurrence: the span of its first
    occurrence, how many (a count, `:infinity`, or a value it runs until) and
    the repeat rule applied in each period, if any.

  * `{:all, members}` — all of several expressions: a written set, an interval
    set, a recurrence set, the result of a set operation.

  * `{:one, members}` — one of several expressions, which has readings and no
    spans.

  * `{:when, member, conditions}` — a member with the conditions
    `Tempo.RecurrenceSet.keep_when/2` and `move_when/2` express.

  """
  @type form ::
          {:value, units()}
          | {:span, t() | Duration.t() | :open, t() | Duration.t() | :open}
          | {:every, t(), pos_integer() | :infinity | t(), selection() | nil}
          | {:all, [t()] | Enumerable.t()}
          | {:one, [t()]}
          | {:when, t(), [term()]}

  @typedoc """
  A mark that a component is uncertain (`?`), approximate (`~`) or both (`%`),
  held for each unit it qualifies.
  """
  @type qualifications :: %{optional(unit()) => :uncertain | :approximate | :both} | nil

  @type t :: %__MODULE__{
          form: form(),
          calendar: module(),
          zone: zone() | nil,
          shift: shift() | nil,
          qualifications: qualifications(),
          metadata: map()
        }

  @typedoc "The error every function returns in an `{:error, reason}` tuple."
  @type error :: Exception.t()

  # ── Reading and writing ───────────────────────────────────────────────

  @doc """
  Reads an ISO 8601, ISO 8601-2, EDTF or RFC 9557 text into an expression.

  ### Arguments

  * `text` is the text to read.

  * `calendar_or_options` is the calendar module a text that names none is
    read in, or a keyword list of options. The default is `Calendar.ISO`.

  ### Options

  * `:calendar` is the calendar a text that names none is in. A text that
    names its calendar (`[u-ca=hebrew]`) is read in that one.

  * `:profile` is the kind of text the caller declares it to be: `:date`,
    `:time`, `:datetime`, `:interval` or `:duration`. A text of another
    kind is an error, where without a profile it would be read as the kind
    it is.

  * `:territory` is the territory a season of 21 to 24 is given its months
    in as it is read, as `in_territory/2` takes it; with none, and no
    `:locale`, a season is read as its code.

  * `:locale` is a locale whose territory is used as `:territory` is.

  ### Returns

  * `{:ok, expression}`, a `t:t/0`, or a `t:Tempo.Duration.t/0` for a
    duration.

  * `{:error, exception}` when the text cannot be read (`Tempo.ParseError`),
    names a date the calendar does not have (`Tempo.InvalidDateError`), a zone
    the database does not know (`Tempo.ZoneError`), or an interval whose
    ends are out of order (`Tempo.IntervalEndpointsError`).

  ### Examples

      iex> Tempo.from_iso8601("2026-06-15")
      {:ok, ~o"2026-06-15"}

      iex> Tempo.from_iso8601("2026Y6M15D")
      {:ok, ~o"2026-06-15"}

      iex> Tempo.from_iso8601("P1Y2M")
      {:ok, ~o"P1Y2M"}

      iex> Tempo.from_iso8601("2026-06-15", profile: :date)
      {:ok, ~o"2026-06-15"}

      iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2026-06-15T10:30", profile: :date)

      iex> {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026-02-30")

      iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("tomorrow")

  """
  @spec from_iso8601(String.t(), module() | keyword()) ::
          {:ok, t() | Duration.t()} | {:error, error()}
  def from_iso8601(text, calendar_or_options \\ [])

  def from_iso8601(text, calendar) when is_binary(text) and is_atom(calendar),
    do: Reader.read(text, calendar: calendar)

  def from_iso8601(text, _calendar_or_options) when not is_binary(text), do: not_text(text)

  def from_iso8601(_text, other) when not is_list(other),
    do:
      {:error,
       ArgumentError.exception(
         "Tempo.from_iso8601/2 takes a calendar or a keyword list, not #{inspect(other)}"
       )}

  def from_iso8601(text, options) do
    with :ok <-
           Options.check(
             options,
             [:calendar, :profile, :territory, :locale],
             "Tempo.from_iso8601/2"
           ),
         {:ok, territory} <- territory_named(options) do
      Text.read(text, [territory: territory] ++ Keyword.take(options, [:calendar, :profile]))
    end
  end

  @doc """
  Reads a text as `from_iso8601/2` does, returning the expression or raising.

  ### Arguments

  * The arguments are those of `from_iso8601/2`.

  ### Returns

  * What `from_iso8601/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.from_iso8601!("2026-06")
      ~o"2026-06"

  """
  @spec from_iso8601!(String.t(), module() | keyword()) :: t() | Duration.t()
  def from_iso8601!(text, calendar_or_options \\ []) do
    case from_iso8601(text, calendar_or_options) do
      {:ok, expression} -> expression
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Writes an expression or a duration as ISO 8601 text, in the explicit form
  of ISO 8601-2 (`2026Y6M15D`) that every expression has.

  A span is written as it was read (law 9): an end that was abbreviated is
  abbreviated again, and a date end is the date the interval runs through.

  ### Arguments

  * `expression` is a `t:t/0` or a `t:Tempo.Duration.t/0`.

  ### Returns

  * `{:ok, text}`.

  * `{:error, %Tempo.Iso8601EncodeError{}}` for a struct built by hand with
    parts in two calendars or two zones, which has no one text.

  ### Examples

      iex> Tempo.to_iso8601(~o"2026-06-15")
      {:ok, "2026Y6M15D"}

      iex> Tempo.to_iso8601(~o"2026-06-15T10:30Z")
      {:ok, "2026Y6M15DT10H30MZ"}

      iex> Tempo.to_iso8601(~o"2026-06-01/2026-06-30")
      {:ok, "2026Y6M1D/30D"}

  """
  @spec to_iso8601(t() | Duration.t()) :: {:ok, String.t()} | {:error, error()}
  def to_iso8601(expression) when is_expression(expression), do: Writer.to_iso8601(expression)
  def to_iso8601(other), do: not_an_expression(other)

  @doc """
  Writes an expression as `to_iso8601/1` does, returning the text or raising.

  ### Arguments

  * The arguments are those of `to_iso8601/1`.

  ### Returns

  * What `to_iso8601/1` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.to_iso8601!(~o"P1Y2M")
      "P1Y2M"

  """
  @spec to_iso8601!(t() | Duration.t()) :: String.t()
  def to_iso8601!(expression) do
    case to_iso8601(expression) do
      {:ok, text} -> text
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Reads a text written in ISO 8601 or in a locale's own words.

  ISO 8601 is read first, with the whole grammar `from_iso8601/2` reads. A
  text it does not describe is then read as the locale's words for a date,
  a time or a range of them (`"May 16, 2026"`, `"2:30 PM"`,
  `"May 5 – May 10, 2026"`), through `Calendrical.parse/2`, so one text
  field can take either form.

  ### Arguments

  * `text` is the text.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is the locale whose words are read; the default is
    Localize's. One named is also where a season of 21 to 24 is given its
    months, as for `from_iso8601/2`.

  * `:territory` is as for `from_iso8601/2`.

  * `:calendar` is the calendar the text is read in.

  * `:profile` is as for `from_iso8601/2`, for the ISO 8601 reading.

  * `:reference_date` is the day two-digit years and partial dates are
    read against.

  ### Returns

  * `{:ok, expression}`.

  * `{:error, %Tempo.ParseError{}}` for a text that is neither.

  ### Examples

      iex> Tempo.parse("2026-06-15")
      {:ok, ~o"2026-06-15"}

      iex> Tempo.parse("May 16, 2026", locale: :en)
      {:ok, ~o"2026-05-16"}

      iex> Tempo.parse("15 juin 2026", locale: :fr)
      {:ok, ~o"2026-06-15"}

      iex> Tempo.parse("May 5 – May 10, 2026", locale: :en)
      {:ok, ~o"2026-05-05/2026-05-10"}

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse("whenever")

  """
  @spec parse(String.t(), keyword()) :: {:ok, t() | Duration.t()} | {:error, error()}
  def parse(text, options \\ [])

  def parse(text, _options) when not is_binary(text), do: not_text(text)

  def parse(text, options) do
    with :ok <-
           Options.check(
             options,
             [:locale, :territory, :calendar, :profile, :reference_date],
             "Tempo.parse/2"
           ),
         {:ok, territory} <- territory_named(options) do
      Text.parse(text, Keyword.put(options, :territory, territory))
    end
  end

  @doc """
  `parse/2`, returning the expression or raising.

  ### Arguments

  * The arguments are those of `parse/2`.

  ### Returns

  * What `parse/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.parse!("15 June 2026", locale: :en)
      ~o"2026-06-15"

  """
  @spec parse!(String.t(), keyword()) :: t() | Duration.t()
  def parse!(text, options \\ []) do
    case parse(text, options) do
      {:ok, expression} -> expression
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Reads a text that must be an ISO 8601 duration and nothing else: an
  iCalendar `DURATION`, a configured timeout. A date read where a duration
  was meant is an error here, where `from_iso8601/2` would succeed with a
  value of the wrong kind.

  ### Arguments

  * `text` is a string.

  ### Returns

  * `{:ok, duration}`, a `t:Tempo.Duration.t/0`.

  * `{:error, %Tempo.ParseError{}}` for any other text.

  ### Examples

      iex> Tempo.parse_duration("PT1H")
      {:ok, ~o"PT1H"}

      iex> {:error, %Tempo.ParseError{}} = Tempo.parse_duration("2026-06-15")

  """
  @spec parse_duration(String.t()) :: {:ok, Duration.t()} | {:error, error()}
  def parse_duration(text) when is_binary(text), do: Text.read(text, profile: :duration)
  def parse_duration(other), do: not_text(other)

  # ── Construction ──────────────────────────────────────────────────────

  @doc """
  Builds a value from its units.

  ### Arguments

  * `components` is a keyword list or a map of units (`:year`, `:month`,
    `:day`, `:week`, `:day_of_week`, `:day_of_year`, `:quarter`, `:season`,
    `:hour`, `:minute`, `:second`, `:microsecond`), in any order, each holding
    what a written unit holds (`t:held/0`); a `:microsecond` holds
    `{microseconds, digits}` as Elixir's `Time` does, or an integer, which
    is six digits. These keys go beside them:

    * `:calendar` is the calendar the value is in. The default is
      `Calendar.ISO`.

    * `:zone` is the name of the value's time zone, as the database knows it.

    * `:shift` is the time shift, `[hour: 2]` for `Z2H`, `[hour: 0]` for `Z`,
      and `[hour: 0, minute: 0]` for `+00:00`, a local time at no offset.

    * `:qualifications` marks units of the value as ISO 8601-2's `?`, `~`
      and `%` do: a map of the unit to `:uncertain`, `:approximate` or
      `:both`, so `%{year: :uncertain}` is `2026?Y`.

    * `:metadata` is a map the caller keeps on the value. The default is `%{}`.

  ### Returns

  * `{:ok, value}`, a `t:t/0` whose units are ordered coarsest first.

  * `{:error, exception}` when a unit is not one a value has or two units
    name the same thing (an `ArgumentError`), when the calendar does not
    have the date (`Tempo.InvalidDateError`), when the calendar is not one
    (`Tempo.InvalidCalendarError`), or when the zone is not known
    (`Tempo.ZoneError`).

  ### Examples

      iex> Tempo.new(year: 2026, month: 6, day: 15)
      {:ok, ~o"2026-06-15"}

      iex> Tempo.new(day: 15, month: 6, year: 2026)
      {:ok, ~o"2026-06-15"}

      iex> Tempo.new(year: 2026, week: 24, day_of_week: 3)
      {:ok, ~o"2026-W24-3"}

      iex> Tempo.new(year: 2026, month: 6, day: 15, zone: "Europe/Paris")
      {:ok, ~o"2026-06-15[Europe/Paris]"}

      iex> Tempo.new(hour: 10, minute: 30, second: 45, microsecond: {500_000, 1})
      {:ok, ~o"T10:30:45.5"}

      iex> Tempo.new(year: 2020..2024)
      {:ok, ~o"{2020..2024}Y"}

      iex> Tempo.new(year: 2026, month: 6, qualifications: %{month: :approximate})
      {:ok, ~o"2026Y6~M"}

      iex> Tempo.new(year: 2026, group: {2, [month: 3]})
      {:ok, ~o"2026Y2G3MU"}

      iex> {:error, %Tempo.InvalidDateError{}} = Tempo.new(year: 2026, month: 13)

      iex> {:error, %ArgumentError{}} = Tempo.new(year: 2026, month: 6, week: 24)

      iex> {:error, %Tempo.ZoneError{}} = Tempo.new(year: 2026, zone: "Mars/Olympus")

      iex> {:ok, value} = Tempo.new(%{year: 2026, month: 6, day: 15})
      iex> value
      ~o"2026-06-15"

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, error()}
  def new(components) when is_map(components) and not is_struct(components),
    do: components |> Map.to_list() |> new()

  def new(components) when is_list(components) do
    {frame, units} =
      Keyword.split(components, [:calendar, :zone, :shift, :qualifications, :metadata])

    with {:ok, units} <- units |> Enum.map(&held_as_written/1) |> Unit.ordered(),
         {:ok, calendar} <- calendar_of(Keyword.get(frame, :calendar, Tempo.Calendar.default())),
         {:ok, zone} <- zone_of(Keyword.get(frame, :zone)),
         {:ok, qualifications} <- qualifications_of(Keyword.get(frame, :qualifications), units) do
      Validate.run(%__MODULE__{
        form: {:value, units},
        calendar: calendar,
        zone: zone,
        shift: Keyword.get(frame, :shift),
        qualifications: qualifications,
        metadata: Keyword.get(frame, :metadata, %{})
      })
    end
  end

  def new(other) do
    {:error,
     ArgumentError.exception(
       "a value is built from a keyword list or a map of units, not #{inspect(other)}"
     )}
  end

  # A range alone is held as a list of it, as `{2020..2024}Y` is read.
  defp held_as_written({unit, %Range{} = range}), do: {unit, [range]}

  # An integer of microseconds is six digits of them, as `Time.new/4` reads one.
  defp held_as_written({:microsecond, microsecond}) when is_integer(microsecond),
    do: {:microsecond, {microsecond, 6}}

  defp held_as_written(part), do: part

  # A value's qualifications, each of a unit it has, as `?`, `~` and `%`
  # write them on that unit: `2026Y6~M` is `%{month: :approximate}`.
  defp qualifications_of(nil, _units), do: {:ok, nil}
  defp qualifications_of(qualifications, _units) when qualifications == %{}, do: {:ok, nil}

  defp qualifications_of(%{} = qualifications, units) do
    held = Enum.map(units, fn {unit, _} -> unit end)

    case Enum.reject(qualifications, fn {unit, mark} ->
           unit in held and mark in [:uncertain, :approximate, :both]
         end) do
      [] ->
        {:ok, qualifications}

      [{unit, mark} | _] ->
        {:error,
         ArgumentError.exception(
           ":qualifications marks a unit the value has as :uncertain, :approximate or :both, " <>
             "not #{inspect(unit)} as #{inspect(mark)}"
         )}
    end
  end

  defp qualifications_of(other, _units),
    do:
      {:error,
       ArgumentError.exception(
         ":qualifications is a map of a value's units to their marks, not #{inspect(other)}"
       )}

  @doc """
  Builds a value as `new/1` does, returning the value or raising.

  ### Arguments

  * The arguments are those of `new/1`.

  ### Returns

  * What `new/1` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.new!(year: 2026, month: 6)
      ~o"2026-06"

  """
  @spec new!(keyword() | map()) :: t()
  def new!(components) do
    case new(components) do
      {:ok, value} -> value
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Builds a selection from its parts: what a repeat rule picks in each of its
  periods, and what `select/3` picks in each period of a base. It is the
  value ISO 8601-2 writes between `L` and `N`.

  ### Arguments

  * `parts` is a keyword list of the parts, in any order.

  ### Options

  * `:month`, `:week`, `:day_of_year`, `:day`, `:day_of_week`, `:hour`,
    `:minute` and `:second` are each a whole number, a range, or a list of
    numbers and ranges. A negative number counts from the end of the period:
    `day: -1` is its last day. `:day_of_week` is 1, Monday, to 7.

  * `:instance` picks among everything the other parts select, by position:
    `2` the second, `-1` the last.

  * `:event` is the name of a day a calendar computes, one of
    `Tempo.Event.known/0`: `"easter"`.

  * `:traditional_month` is a month as a lunisolar calendar names it: its
    number, or `{5, :leap}` for the leap month after the fifth. It is
    written `5m` and `5+m`.

  * `:skip` is `:forward` or `:backward`: what is taken for a day or a
    month the selection names and a year lacks, the next there is (the
    first of March for a 29th of February) or the last before it (the
    28th). With none such a day is passed over. It is written `(forward)s`.

  * `:roll` moves each day the other parts select to a weekday, by one of
    the conventions of `roll_to_workday/3`: `:modified_nearest` is the
    weekday nearest the day and in its month. The weekdays are those of
    the locale the selection is asked in. It is written `(modified-nearest)r`.

  * `:selection` is a selection made first, as parts or as what this
    function returns; the other parts then select within what it gives. It
    says "the second Monday, at nine and at ten" where a position alone
    would count among the times as well.

  * `:window` is a `t:Tempo.Duration.t/0`, the length of what the nested
    `:selection` selects: `~o"P1D"` for the day after, `~o"-P7D"` for the
    week before.

  * `:all` is a list of selections, each as parts, whose values are taken
    together: `[[day_of_week: 1, instance: 2], [day_of_week: 3, instance:
    2]]` is the second Monday and the second Wednesday. The parts written
    after it select within each value, and a position counts among them
    all. It is Tempo's own, written `L{1K2I,3K2I}N`: ISO 8601-2 has one rule
    of a kind in a selection.

  ### Returns

  * `{:ok, selection}`, a `t:t/0` with no year.

  * `{:error, exception}`: an `ArgumentError` for a part a selection does
    not have, and a `Tempo.InvalidDateError` for an event no calendar knows.

  ### Examples

      iex> Tempo.selection(day_of_week: 1, instance: 2)
      {:ok, ~o"L1K2IN"}

      iex> {:ok, christmas} = Tempo.selection(month: 12, day: 25)
      iex> Tempo.select(~o"2026/2027", christmas)
      {:ok, ~o"{2026-12-25,2027-12-25}"}

      iex> {:ok, last_weekday} = Tempo.selection(day_of_week: 1..5, instance: -1)
      iex> Tempo.select(~o"2026-06", last_weekday)
      {:ok, ~o"{2026-06-30}"}

      iex> {:ok, first_monday_and_last_friday} =
      ...>   Tempo.selection(all: [[day_of_week: 1, instance: 1], [day_of_week: 5, instance: -1]])
      iex> Tempo.select(~o"2026-06", first_monday_and_last_friday)
      {:ok, ~o"{2026-06-01,2026-06-26}"}

      iex> {:error, %ArgumentError{}} = Tempo.selection(fortnight: 1)

  """
  @spec selection(keyword()) :: {:ok, t()} | {:error, error()}
  def selection(parts), do: Build.selection(parts)

  @doc """
  Builds a recurrence from its cadence and what it is given: where it
  starts, how it ends, and what it selects in each repeat. It is what
  `R/start/cadence/F…` reads to, built from parts where a program would
  otherwise write that text to have it read.

  ### Arguments

  * `cadence` is the length of each repeat, a `t:Tempo.Duration.t/0` or its
    units: `~o"P1M"`, or `[month: 1]`.

  * `options` is a keyword list of options.

  ### Options

  * `:from` is where the recurrence starts, a `t:t/0` value. A set here is a
    domain: the rule is applied in each of its members
    (`~o"{2026Y..2030Y}"`). With none the recurrence has an open start and
    is placed by a `:within` window.

  * `:to` is where a recurrence counted back ends, a `t:t/0` value: its
    last repeat ends with it (`R5/P1M/2026-06-01`). A recurrence starts at
    `:from` or ends at `:to`, not both.

  * `:count` is how many occurrences it has.

  * `:until` is a `t:t/0` value it runs to. A recurrence ends by one of
    `:count` and `:until`, or has no end.

  * `:select` is what it selects in each repeat: the parts of a selection,
    or what `selection/1` returns. With none each repeat is an occurrence.

  * `:calendar` is the calendar of a recurrence with no `:from`
    (`R/../P1Y/FL7M1DN[u-ca=hebrew]`). One with a `:from` is in its start's.

  * `:years` keeps the years of its domain that are `:even`, `:odd`,
    `:leap` or `:common`: of every year where there is no `:from`
    (`R/..e`), or of the set given as `:from` (`R/{2017Y..}l`).

  * `:metadata` is a map the recurrence and every occurrence carry.

  ### Returns

  * `{:ok, recurrence}`, a `t:t/0` of the `:every` form, in the calendar and
    the zone of its start.

  * `{:error, exception}` as for `selection/1`, and an `ArgumentError` for a
    cadence, a start or an end of another kind.

  ### Examples

      iex> Tempo.every(~o"P1M", from: ~o"2026-01-01", select: [day_of_week: 1, instance: 2])
      {:ok, ~o"R/2026-01-01/P1M/FL1K2IN"}

      iex> {:ok, paydays} = Tempo.every([month: 1], from: ~o"2026-01-01", count: 3, select: [day: -1])
      iex> Enum.map(paydays, &Tempo.Interval.from/1)
      [~o"2026-01-31", ~o"2026-02-28", ~o"2026-03-31"]

      iex> {:ok, good_friday} =
      ...>   Tempo.every(~o"P1Y",
      ...>     select: [selection: [event: "easter"], window: ~o"-P7D", day_of_week: 5, instance: -1]
      ...>   )
      iex> good_friday |> Tempo.to_interval!(within: ~o"2026") |> Tempo.IntervalSet.map(&Tempo.Interval.from/1)
      [~o"2026-04-03"]

      iex> Tempo.every(~o"P1Y", from: ~o"{2026Y..2028Y}", select: [month: 7, day: 4])
      {:ok, ~o"R/{2026Y..2028Y}/P1Y/FL7M4DN"}

      iex> {:error, %ArgumentError{}} = Tempo.every(~o"P1D", count: 3, until: ~o"2026")

  """
  @spec every(Duration.t() | keyword(), keyword()) :: {:ok, t()} | {:error, error()}
  def every(cadence, options \\ []), do: Build.every(cadence, options)

  @doc """
  Builds a set one of whose members is meant: "in 1984, 1986 or 1988". It
  has readings and no spans, where the set `Tempo.IntervalSet.new/2` builds
  is all of its members.

  ### Arguments

  * `members` is a list of `t:t/0`, in one calendar and one zone.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:one` form.

  * `{:error, %ArgumentError{}}` for no members, or members in two
    calendars or two zones.

  ### Examples

      iex> Tempo.one_of([~o"1984", ~o"1986", ~o"1988"])
      {:ok, ~o"[1984,1986,1988]"}

      iex> {:ok, one_year} = Tempo.one_of([~o"1984", ~o"1986"])
      iex> Tempo.possibly?(:before, one_year, ~o"1985")
      true

  """
  @spec one_of([t()]) :: {:ok, t()} | {:error, error()}
  def one_of(members), do: Build.one_of(members)

  # ── Spans, members and walks ──────────────────────────────────────────

  @doc """
  The interval an expression denotes: a singular expression's one span, or
  a set of the spans of a plural one.

  A value is the span from itself through itself when written to a calendar
  unit, and to the next reading when written to a clock unit (law 3). A
  written interval has its duration end made a value, and an open end placed
  by the `:within` window if one is given. A recurrence, a set and a value
  with a set, a mask or a group in a unit are a set of the spans of their
  members, in order.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a singular expression whose extent bounds a sequence with no
    end of its own (a recurrence with no count) and places a value with no
    year on each of its periods.

  * `:territory` is the territory a season of 21 to 24 has its months in, as
    `in_territory/2` takes it. With none, and no `:locale`, such a season
    keeps its code and has its dates in the territory in force.

  * `:locale` is a locale whose territory is used as `:territory` is, and
    whose working week a rule that rolls a day to a weekday keeps to.

  ### Returns

  * `{:ok, interval}`, a `t:t/0` of the `:span` form, or of the `:all` form
    for a plural expression.

  * `{:error, %Tempo.ConversionError{}}` for a duration, a one-of set, a
    recurrence with no count and no window, a value with no year and no
    window, or more than 10,000 members at once (the application's `:max_values_at_once`).

  ### Examples

      iex> Tempo.to_interval(~o"2026-06")
      {:ok, ~o"2026-06/2026-06"}

      iex> Tempo.to_interval(~o"2026-06-15T10")
      {:ok, ~o"2026-06-15T10/2026-06-15T11"}

      iex> Tempo.to_interval(~o"2026-06-01/P1M")
      {:ok, ~o"2026-06-01/2026-06-30"}

      iex> Tempo.to_interval(~o"2026Y{1,3}M")
      {:ok, ~o"{2026-01/2026-01,2026-03/2026-03}"}

      iex> Tempo.to_interval(~o"R3/2026-01-31/P1M")
      {:ok, ~o"{2026-01-31/2026-02-27,2026-02-28/2026-03-30,2026-03-31/2026-04-29}"}

      iex> Tempo.to_interval(~o"6M15D", within: ~o"2026")
      {:ok, ~o"2026-06-15/2026-06-15"}

      iex> {:error, %Tempo.ConversionError{reason: :bare_duration}} = Tempo.to_interval(~o"P1M")

      iex> {:error, %Tempo.ConversionError{reason: :unbounded}} = Tempo.to_interval(~o"R/2026-01-01/P1Y")

  """
  @spec to_interval(t() | Duration.t(), keyword()) :: {:ok, t()} | {:error, error()}
  def to_interval(expression, options \\ [])

  def to_interval(expression, options) when is_expression(expression) do
    with :ok <- Options.check(options, [:within, :territory, :locale], "Tempo.to_interval/2"),
         {:ok, expression} <- seasons_placed(expression, options) do
      spanned(expression, Keyword.take(options, [:within, :locale]))
    end
  end

  def to_interval(other, _options), do: not_an_expression(other)

  defp spanned(%Tempo.Duration{} = duration, _options),
    do: {:error, ConversionError.exception(value: duration, reason: :bare_duration)}

  defp spanned(%__MODULE__{form: {:every, first, :infinity, _}} = recurrence, options) do
    if Keyword.has_key?(options, :within) or domain?(first),
      do: plural_interval(recurrence, options),
      else: {:error, ConversionError.exception(value: recurrence, reason: :unbounded)}
  end

  defp spanned(%__MODULE__{} = expression, options) do
    if Spans.singular?(expression),
      do: singular_interval(expression, options),
      else: plural_interval(expression, options)
  end

  defp singular_interval(expression, options) do
    with {:ok, spans} <- Spans.spans(expression, options) do
      case Enum.to_list(spans) do
        [span] -> {:ok, span}
        spans -> {:ok, set_of(spans, expression)}
      end
    end
  end

  defp plural_interval(expression, options) do
    with {:ok, spans} <- Spans.spans(expression, options),
         {:ok, spans} <- bounded(spans, expression) do
      {:ok, set_of(spans, expression)}
    end
  end

  defp bounded(enumerable, expression), do: Limit.take(enumerable, expression)

  defp set_of(spans, expression),
    do: %__MODULE__{
      form: {:all, spans},
      calendar: expression.calendar,
      zone: expression.zone,
      metadata: expression.metadata
    }

  @doc """
  `to_interval/2`, returning the interval or set or raising.

  ### Arguments

  * The arguments are those of `to_interval/2`.

  ### Returns

  * What `to_interval/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.to_interval!(~o"2026-06-15")
      ~o"2026-06-15/2026-06-15"

  """
  @spec to_interval!(t(), keyword()) :: t()
  def to_interval!(expression, options \\ []) do
    case to_interval(expression, options) do
      {:ok, interval} -> interval
      {:error, exception} -> raise exception
    end
  end

  @doc """
  The members of an expression (law 6): the values a value with a set, a
  mask or a group in a unit allows; the members of a set; the occurrences
  of a recurrence; a singular expression itself.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in.

  * `:locale` is the locale whose working week a rule that rolls a day to a
    weekday keeps to; the default is the territory in force.

  ### Returns

  * `{:ok, members}`, a list of `t:t/0`.

  * `{:error, %Tempo.ConversionError{}}` as for `to_interval/2`.

  ### Examples

      iex> Tempo.members(~o"2026Y{1,3}M")
      {:ok, [~o"2026-01", ~o"2026-03"]}

      iex> Tempo.members(~o"{2026-06,2026-08}")
      {:ok, [~o"2026-06", ~o"2026-08"]}

      iex> Tempo.members(~o"2026-06")
      {:ok, [~o"2026-06"]}

  """
  @spec members(t() | Duration.t(), keyword()) :: {:ok, [t()]} | {:error, error()}
  def members(expression, options \\ [])

  def members(expression, options) when is_expression(expression) do
    with :ok <- Options.check(options, [:within, :locale], "Tempo.members/2"),
         {:ok, members} <- Spans.members(expression, options),
         do: bounded(members, expression)
  end

  def members(other, _options), do: not_an_expression(other)

  @doc """
  An expression walked at a unit: the values of that unit its extent holds,
  lazily and in order, half-open. A calendar unit steps on the day scale
  through the calendar's periods; a clock unit on the tick scale, each tick
  shown as a wall reading of the zone, so a day across a change of the clock
  has 23 or 25 hours. A plural expression is each member walked in turn.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `unit` is a `t:unit/0`: `:year`, `:month`, `:week`, `:day`,
    `:hour`, `:minute`, `:second`, or `{:microsecond, precision}` for a part
    of a second.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in.

  ### Returns

  * `{:ok, stream}`, an `Enumerable` of `t:t/0` values.

  * `{:error, %Tempo.ConversionError{}}` for an expression with an open
    start, no year, or no spans.

  ### Examples

      iex> {:ok, days} = Tempo.walk(~o"2026-06", :day)
      iex> Enum.count(days)
      30

      iex> {:ok, hours} = Tempo.walk(~o"2026-03-29[Europe/Paris]", :hour)
      iex> Enum.count(hours)
      23

      iex> {:ok, weeks} = Tempo.walk(~o"2026-06-01/2026-06-30", :week)
      iex> Enum.map(weeks, &Tempo.to_iso8601!/1)
      ["2026Y23W", "2026Y24W", "2026Y25W", "2026Y26W", "2026Y27W"]

  """
  @spec walk(t(), unit() | {:microsecond, 1..6}, keyword()) ::
          {:ok, Enumerable.t()} | {:error, error()}
  def walk(expression, unit, options \\ [])

  def walk(expression, unit, options) when is_expression(expression) do
    with :ok <- Options.check(options, [:within], "Tempo.walk/3"),
         do: Spans.walk(expression, unit, options)
  end

  def walk(other, _unit, _options), do: not_an_expression(other)

  # ── Set operations ────────────────────────────────────────────────────

  @doc """
  The union of two expressions: every member of either, kept whole with its
  own metadata, in order of start. A member both hold, the same in its span,
  its form and its metadata, is one member; two members that cover one time
  otherwise stay two, and `Tempo.IntervalSet.coalesce/1` merges them.

  ### Arguments

  * `a` and `b` are each a `t:t/0` that has spans: a value, an interval, a
    recurrence, a set.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window the operation works in: a value with
    no year is placed on each of its periods, and a recurrence with no end
    is bounded by it. Required when one operand has a year and the other
    none.

  ### An operand with no end

  With no window, an operation on an operand with no end (a recurrence with
  no count, or a set with no last member) is as bounded as it makes its
  answer. An `intersection/3`, and a `difference/3` from an operand that has
  an end, lie within that operand, and the other is taken within it. A
  `union/3`, a `symmetric_difference/3` and a `difference/3` from an operand
  with no end have no end themselves: the answer is a set with no last
  member, in the order of time, which `:within` bounds wherever it is asked
  for. Of two operands with no end only the union is answered; any other
  operation on them needs a window.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form, with no last member where
    the answer has no end.

  * `{:error, %Tempo.FrameError{}}` when the operands share no frame: one
    zoned and one not, one with a year and one without and no window, two
    with no year on different cycles.

  * `{:error, %Tempo.ConversionError{}}` for a duration, a one-of set, an
    open end, more than 10,000 spans (the application's
    `:max_values_at_once`), or two operands with no end in an operation
    other than a union.

  ### Examples

      iex> Tempo.union(~o"2026-01", ~o"2026-03")
      {:ok, ~o"{2026-01/2026-01,2026-03/2026-03}"}

      iex> {:ok, every_week_and_a_day} = Tempo.union(~o"R/2026-06-01/P1W", ~o"2026-06-10")
      iex> Tempo.bounded?(every_week_and_a_day)
      false
      iex> Tempo.members(every_week_and_a_day, within: ~o"2026-06-01/2026-06-14")
      {:ok, [~o"2026-06-01/2026-06-07", ~o"2026-06-08/2026-06-14", ~o"2026-06-10/2026-06-10"]}

      iex> {:ok, both} = Tempo.union(~o"2026-01", ~o"2026-02")
      iex> Tempo.IntervalSet.count(both)
      2

  """
  @spec union(t(), t(), keyword()) :: {:ok, t()} | {:error, error()}
  def union(a, b, options \\ []) do
    with :ok <- Options.check(options, @set_options, "Tempo.union/3") do
      united(Algebra.streamed(:union, a, b, options), a, b, options)
    end
  end

  defp united(:bounded, a, b, options) do
    with {:ok, frame, pa, pb} <- Algebra.aligned(a, b, options) do
      # A member both operands hold is one member of their union (decision 38).
      members =
        Algebra.whole(pa ++ pb)
        |> Enum.sort_by(&{&1.start, &1.stop})
        |> Enum.map(& &1.span)
        |> Enum.uniq()

      Algebra.gathered(members, calendar: frame.calendar, zone: frame.zone, metadata: a.metadata)
    end
  end

  defp united({:ok, frame, in_a, in_b}, a, _b, _options) do
    members = in_a |> Algebra.merged(in_b) |> Stream.map(&Algebra.brought!(&1.span, frame))
    {:ok, set_of(members, %{a | calendar: frame.calendar, zone: frame.zone})}
  end

  defp united({:error, _exception} = error, _a, _b, _options), do: error

  # A member kept whole is brought to the result's calendar, as the sweep's results are.
  # A recurrence over a domain (`R/{2020Y..2024Y}/P1Y/F…`) is bounded by it.
  defp domain?(%__MODULE__{form: {:span, %__MODULE__{form: form}, _}}),
    do: elem(form, 0) in [:all, :when]

  defp domain?(_first), do: false

  defp in_frame(%__MODULE__{calendar: calendar} = span, %{calendar: calendar}), do: span

  defp in_frame(%__MODULE__{} = span, %{calendar: calendar}) do
    case to_calendar(span, calendar) do
      {:ok, converted} -> converted
      {:error, _} -> span
    end
  end

  @doc """
  The intersection of two expressions: every instant in both, as spans
  trimmed to the overlap, each carrying the first operand's metadata. A
  span ends where the member it comes from ends, so two members that meet
  are two spans; `Tempo.IntervalSet.coalesce/1` joins them.

  ### Arguments

  * `a` and `b` are each a `t:t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in. With none, an operand
    with no end is treated as `union/3` says.

  * `:metadata` says which member's metadata a result carries: `:first` (the
    default), `:second`, `:merge`, or a function of the two.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form, empty when nothing is shared.

  * `{:error, exception}` as for `union/3`.

  ### Examples

      iex> Tempo.intersection(~o"2026", ~o"2026-06-15")
      {:ok, ~o"{2026-06-15/2026-06-15}"}

      iex> Tempo.intersection(~o"2026-06-15T09/2026-06-15T17", ~o"2026-06-15T12/2026-06-15T13")
      {:ok, ~o"{2026-06-15T12/2026-06-15T13}"}

  """
  @spec intersection(t(), t(), keyword()) :: {:ok, t()} | {:error, error()}
  def intersection(a, b, options \\ []),
    do: operate(:intersection, a, b, options, "Tempo.intersection/3")

  @doc """
  The difference of two expressions: every instant in the first and not the
  second, as spans trimmed to what is left, each carrying the first
  operand's metadata. A span ends where the member it comes from ends.

  ### Arguments

  * `a` and `b` are each a `t:t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in. With none, an operand
    with no end is treated as `union/3` says.

  * `:metadata` says which member's metadata a result carries: `:first` (the
    default), `:second`, `:merge`, or a function of the two.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form.

  * `{:error, exception}` as for `union/3`.

  ### Examples

      iex> Tempo.difference(~o"2026", ~o"2026-06")
      {:ok, ~o"{2026/2026-05,2026-07/2026}"}

      iex> {:ok, free_weeks} = Tempo.difference(~o"R/2026-06-01/P1W", ~o"2026-06-10/2026-06-20")
      iex> Tempo.members(free_weeks, within: ~o"2026-06-01/2026-06-14")
      {:ok, [~o"2026-06-01/2026-06-07", ~o"2026-06-08/2026-06-09"]}

      iex> Tempo.difference(~o"2026-06-15T09/2026-06-15T17", ~o"2026-06-15T12/2026-06-15T13")
      {:ok, ~o"{2026-06-15T09/2026-06-15T12,2026-06-15T13/2026-06-15T17}"}

  """
  @spec difference(t(), t(), keyword()) :: {:ok, t()} | {:error, error()}
  def difference(a, b, options \\ []),
    do: operate(:difference, a, b, options, "Tempo.difference/3")

  @doc """
  The symmetric difference of two expressions: every instant in exactly one
  of them, as spans, each ending where the member it comes from ends.

  ### Arguments

  * `a` and `b` are each a `t:t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in. With none, an operand
    with no end is treated as `union/3` says.

  * `:metadata` says which member's metadata a result carries: `:first` (the
    default), `:second`, `:merge`, or a function of the two.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form.

  * `{:error, exception}` as for `union/3`.

  ### Examples

      iex> Tempo.symmetric_difference(~o"2026-01/2026-06", ~o"2026-04/2026-09")
      {:ok, ~o"{2026-01/2026-03,2026-07/2026-09}"}

  """
  @spec symmetric_difference(t(), t(), keyword()) :: {:ok, t()} | {:error, error()}
  def symmetric_difference(a, b, options \\ []),
    do: operate(:symmetric_difference, a, b, options, "Tempo.symmetric_difference/3")

  @doc """
  The complement of an expression within a window: every instant of the
  window not covered by it.

  ### Arguments

  * `a` is a `t:t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window the complement is taken in. It is
    required.

  * `:metadata` says which member's metadata a result carries: `:first` (the
    default), `:second`, `:merge`, or a function of the two.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form.

  * `{:error, exception}` as for `union/3`, and a `Tempo.ConversionError`
    with `:unbounded` when no window is given.

  ### Examples

      iex> Tempo.complement(~o"2026-06", within: ~o"2026")
      {:ok, ~o"{2026/2026-05,2026-07/2026}"}

  """
  @spec complement(t(), keyword()) :: {:ok, t()} | {:error, error()}
  def complement(a, _options) when not is_expression(a), do: not_an_expression(a)

  def complement(a, options) do
    with :ok <- Options.check(options, @set_options, "Tempo.complement/2"),
         do: complemented(a, options)
  end

  defp complemented(a, options) do
    case Keyword.get(options, :within) do
      %__MODULE__{} = window ->
        operate(:difference, window, a, options, "Tempo.complement/2")

      _ ->
        {:error, ConversionError.exception(value: a, reason: :unbounded)}
    end
  end

  @doc """
  The members of the first expression some instant of which is in the
  second, each kept whole with its metadata.

  ### Arguments

  * `a` and `b` are each a `t:t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form.

  * `{:error, exception}` as for `union/3`.

  ### Examples

      iex> Tempo.members_overlapping(~o"{2026-01,2026-03}", ~o"2026-03-15")
      {:ok, ~o"{2026-03/2026-03}"}

  """
  @spec members_overlapping(t(), t(), keyword()) :: {:ok, t()} | {:error, error()}
  def members_overlapping(a, b, options \\ []),
    do:
      members_where(&Algebra.members_overlapping/2, a, b, options, "Tempo.members_overlapping/3")

  @doc """
  The members of the first expression no instant of which is in the second,
  each kept whole with its metadata.

  ### Arguments

  * `a` and `b` are each a `t:t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form.

  * `{:error, exception}` as for `union/3`.

  ### Examples

      iex> Tempo.members_outside(~o"{2026-01,2026-03}", ~o"2026-03-15")
      {:ok, ~o"{2026-01/2026-01}"}

  """
  @spec members_outside(t(), t(), keyword()) :: {:ok, t()} | {:error, error()}
  def members_outside(a, b, options \\ []),
    do: members_where(&Algebra.members_outside/2, a, b, options, "Tempo.members_outside/3")

  @doc """
  The members of either expression no instant of which is in the other.

  ### Arguments

  * `a` and `b` are each a `t:t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form.

  * `{:error, exception}` as for `union/3`.

  ### Examples

      iex> Tempo.members_in_exactly_one(~o"2020", ~o"2022")
      {:ok, ~o"{2020/2020,2022/2022}"}

      iex> Tempo.members_in_exactly_one(~o"2026-01/2026-06", ~o"2026-04/2026-09")
      {:ok, ~o"{}"}

  """
  @spec members_in_exactly_one(t(), t(), keyword()) :: {:ok, t()} | {:error, error()}
  def members_in_exactly_one(a, b, options \\ []) do
    with :ok <- Options.check(options, @set_options, "Tempo.members_in_exactly_one/3"),
         {:ok, frame, pa, pb} <- Algebra.aligned(a, b, options) do
      members =
        (Algebra.members_outside(pa, pb) ++ Algebra.members_outside(pb, pa))
        |> Algebra.whole()
        |> Enum.sort_by(&{&1.start, &1.stop})
        |> Enum.map(&in_frame(&1.span, frame))

      {:ok, set_of(members, %{a | calendar: frame.calendar, zone: frame.zone})}
    end
  end

  defp operate(operation, a, b, options, function) do
    with :ok <- Options.check(options, @set_options, function) do
      operated(Algebra.streamed(operation, a, b, options), operation, a, b, options)
    end
  end

  # A result with an end is swept whole; one with no end is a set whose
  # members are come to one at a time, in the order of time.
  defp operated(:bounded, operation, a, b, options) do
    with {:ok, frame, pa, pb} <- Algebra.aligned(a, b, options) do
      spans = operation |> sweep(pa, pb, frame) |> Enum.map(&Algebra.written(&1, frame, options))
      {:ok, set_of(spans, %{a | calendar: frame.calendar, zone: frame.zone})}
    end
  end

  defp operated({:ok, frame, in_a, in_b}, operation, a, _b, options) do
    spans =
      operation |> Algebra.swept(in_a, in_b) |> Stream.map(&Algebra.written(&1, frame, options))

    {:ok, set_of(spans, %{a | calendar: frame.calendar, zone: frame.zone})}
  end

  defp operated({:error, _exception} = error, _operation, _a, _b, _options), do: error

  defp sweep(:intersection, pa, pb, frame), do: Algebra.intersection(pa, pb, frame)
  defp sweep(:difference, pa, pb, frame), do: Algebra.difference(pa, pb, frame)

  defp sweep(:symmetric_difference, pa, pb, frame),
    do: Algebra.symmetric_difference(pa, pb, frame)

  defp members_where(filter, a, b, options, function) do
    with :ok <- Options.check(options, @set_options, function),
         {:ok, frame, pa, pb} <- Algebra.aligned(a, b, options) do
      members = pa |> filter.(pb) |> Algebra.whole() |> Enum.map(&in_frame(&1.span, frame))
      {:ok, set_of(members, %{a | calendar: frame.calendar, zone: frame.zone})}
    end
  end

  # ── Relations and predicates ──────────────────────────────────────────

  @doc """
  Allen's relation of one singular expression to another: one of the thirteen
  `t:Tempo.Allen.relation/0` atoms.

  ### Arguments

  * `a` and `b` are each a `t:t/0` with one span: a value or an interval.

  ### Returns

  * The relation.

  * `{:error, %Tempo.FrameError{}}` when either has several spans or none, or
    the two share no frame.

  ### Examples

      iex> Tempo.relation(~o"2026-06-15", ~o"2026-06-16")
      :meets

      iex> Tempo.relation(~o"2026-06-01/2026-06-10", ~o"2026-06-05/2026-06-15")
      :overlaps

      iex> Tempo.relation(~o"2026", ~o"2026-06-15")
      :contains

  """
  @spec relation(t(), t()) :: Allen.relation() | {:error, error()}
  def relation(a, b) do
    with {:ok, _frame, pa, pb} <- Algebra.aligned(a, b, []),
         {:ok, sa} <- Algebra.single(pa, a, b),
         {:ok, sb} <- Algebra.single(pb, a, b) do
      Allen.relation(sa, sb)
    end
  end

  for {name, doc} <- [
        before?:
          "ends no later than the second begins: an eleven o'clock meeting is before a noon lunch",
        after?: "begins no earlier than the second ends",
        adjacent?: "meets the second: one ends as the other begins",
        within?: "covers no instant outside the second",
        contains?: "covers every instant of the second",
        overlaps?: "shares an instant with the second",
        disjoint?: "shares no instant with the second",
        equal?: "covers the same instants as the second"
      ] do
    predicate = name |> Atom.to_string() |> String.trim_trailing("?") |> String.to_atom()

    @doc """
    Whether the first expression #{doc}. Both are read as the time they
    cover, so either may be plural; for two single spans this is a set of
    Allen's relations (`Tempo.Allen.predicate/1`).

    ### Arguments

    * `a` and `b` are each a `t:t/0` that has spans.

    * `options` is a keyword list of options.

    ### Options

    * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in.

    ### An operand with no end

    With no window, a recurrence with no count or a set with no last member
    is answered for where the answer follows from the ends: it is within
    nothing that has an end, equals it never and is before it never; whether
    it overlaps a span, contains it or begins after it is answered within
    that span. Two operands with no end need a window.

    ### Returns

    * `true` or `false`; raises the error `union/3` would return for operands
      that share no frame or have no spans, and a `Tempo.ConversionError`
      for two operands with no end and no window.

    ### Examples

        iex> Tempo.#{name}(~o"2026-01", ~o"2026-03")
        #{name in [:before?, :disjoint?]}

        iex> Tempo.#{name}(~o"2026-06", ~o"2026")
        #{name in [:within?, :overlaps?]}

    """
    @spec unquote(name)(t(), t(), keyword()) :: boolean()
    def unquote(name)(a, b, options \\ []) do
      Options.check!(options, [:within], "Tempo.#{unquote(name)}/3")

      case Algebra.decided(unquote(predicate), a, b, options) do
        {:ok, answer} -> answer
        :compare -> compared(unquote(predicate), a, b, options)
        {:error, exception} -> raise exception
      end
    end
  end

  defp compared(predicate, a, b, options) do
    case Algebra.aligned(a, b, options) do
      {:ok, frame, pa, pb} -> Algebra.holds?(predicate, pa, pb, frame)
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Orders two expressions by where they begin, ties by where they end, so that
  `Tempo` sorts as `Date` does: `Enum.sort(values, Tempo)`. A plural
  expression is placed by its first span.

  ### Arguments

  * `a` and `b` are each a `t:t/0` on one frame.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window an expression with no end of its own (a
    recurrence with no count) or no year is placed in.

  ### Returns

  * `:lt`, `:eq` or `:gt`; raises a `Tempo.FrameError` for two expressions
    that share no frame.

  ### Examples

      iex> Tempo.compare(~o"2026-06-15", ~o"2026-06-16")
      :lt

      iex> Tempo.compare(~o"2026-06-15T09:00Z", ~o"2026-06-15T10:00+01:00")
      :eq

      iex> Enum.sort([~o"2026-06-16", ~o"2026-06-15"], Tempo)
      [~o"2026-06-15", ~o"2026-06-16"]

  """
  @spec compare(t(), t(), keyword()) :: :lt | :eq | :gt
  def compare(a, b, options \\ []) do
    Options.check!(options, [:within], "Tempo.compare/3")

    case Algebra.aligned(a, b, options) do
      {:ok, _frame, [pa | _], [pb | _]} ->
        compare_positions({pa.start, pa.stop}, {pb.start, pb.stop})

      {:ok, _frame, _, _} ->
        raise FrameError.exception(a: a, b: b, reason: :several)

      {:error, exception} ->
        raise exception
    end
  end

  defp compare_positions({start, stop}, {start, other_stop}),
    do: Scale.compare(stop, other_stop)

  defp compare_positions({start, _}, {other_start, _}),
    do: Scale.compare(start, other_start)

  # ── Certainty ─────────────────────────────────────────────────────────

  @doc """
  Whether a predicate holds between two expressions however their uncertain
  parts are read: `:certain` when it holds for every reading, `:impossible`
  when for none, `:possible` otherwise. A reading is a member of a one-of set,
  a placing of a year with a margin, or a value a mask allows; an expression
  with no uncertainty has one.

  ### Arguments

  * `predicate` is an everyday predicate (`:before`, `:after`, `:adjacent`,
    `:within`, `:contains`, `:overlaps`, `:disjoint`, `:equal`) or one of
    Allen's relations (`t:Tempo.Allen.relation/0`).

  * `a` and `b` are each a `t:t/0`.

  ### Returns

  * `:certain`, `:possible` or `:impossible`.

  * `{:error, %ArgumentError{}}` for a predicate that is none of
    `Tempo.Allen.predicates/0` or `Tempo.Allen.relations/0`, and
    `{:error, exception}` as for `relation/2`.

  ### Examples

      iex> Tempo.certainty(:before, ~o"1984?", ~o"2004~")
      :certain

      iex> Tempo.certainty(:overlaps, ~o"2018±2Y", ~o"2019")
      :possible

      iex> Tempo.certainty(:within, ~o"[2026,2027]", ~o"2026")
      :possible

      iex> Tempo.certainty(:overlaps, ~o"2018±2Y", ~o"2030")
      :impossible

  """
  @spec certainty(Tempo.Allen.predicate() | Allen.relation(), t(), t()) ::
          :certain | :possible | :impossible | {:error, error()}
  def certainty(_predicate, a, _b) when not is_expression(a), do: not_an_expression(a)
  def certainty(_predicate, _a, b) when not is_expression(b), do: not_an_expression(b)

  def certainty(predicate, a, b) do
    with :ok <- known_predicate(predicate),
         :ok <- one_frame(a, b),
         {:ok, readings_a} <- Spans.readings(a),
         {:ok, readings_b} <- Spans.readings(b),
         :ok <- few_enough(readings_a, readings_b, a) do
      holds = for ra <- readings_a, rb <- readings_b, do: Allen.holds?(predicate, ra, rb)

      cond do
        Enum.all?(holds) -> :certain
        Enum.any?(holds) -> :possible
        true -> :impossible
      end
    end
  end

  # Two expressions are compared on one frame (law 4): both with a year or
  # both on the same cycle, both zoned or both floating.
  defp one_frame(a, b) do
    case {Spans.frame(a), Spans.frame(b)} do
      {same, same} -> :ok
      {{:cycle, _}, {:cycle, _}} -> {:error, FrameError.exception(a: a, b: b, reason: :cycles)}
      {{:cycle, _}, _} -> {:error, FrameError.exception(a: a, b: b, reason: :needs_a_year)}
      {_, {:cycle, _}} -> {:error, FrameError.exception(a: a, b: b, reason: :needs_a_year)}
      _ -> {:error, FrameError.exception(a: a, b: b, reason: :floating_and_zoned)}
    end
  end

  @doc """
  Whether a predicate holds between two expressions for every reading of them.

  ### Arguments

  * `predicate` is a predicate or relation, as for `certainty/3`.

  * `a` and `b` are each a `t:t/0`.

  ### Returns

  * `true` when `certainty/3` is `:certain`, otherwise `false`. The error
    `certainty/3` returns is raised.

  ### Examples

      iex> Tempo.certainly?(:before, ~o"2018±2Y", ~o"2021")
      true

      iex> Tempo.certainly?(:before, ~o"2018±2Y", ~o"2020")
      false

  """
  @spec certainly?(Tempo.Allen.predicate() | Allen.relation(), t(), t()) :: boolean()
  def certainly?(predicate, a, b), do: verdict(certainty(predicate, a, b)) == :certain

  @doc """
  Whether a predicate holds between two expressions for some reading of them.

  ### Arguments

  * `predicate` is a predicate or relation, as for `certainty/3`.

  * `a` and `b` are each a `t:t/0`.

  ### Returns

  * `true` when `certainty/3` is `:certain` or `:possible`, otherwise
    `false`. The error `certainty/3` returns is raised.

  ### Examples

      iex> Tempo.possibly?(:overlaps, ~o"2018±2Y", ~o"2020")
      true

      iex> Tempo.possibly?(:overlaps, ~o"2018±2Y", ~o"2030")
      false

  """
  @spec possibly?(Tempo.Allen.predicate() | Allen.relation(), t(), t()) :: boolean()
  def possibly?(predicate, a, b), do: verdict(certainty(predicate, a, b)) in [:certain, :possible]

  defp known_predicate(predicate) do
    if predicate in Allen.predicates() or predicate in Allen.relations(),
      do: :ok,
      else:
        {:error,
         ArgumentError.exception(
           "a predicate is one of #{inspect(Allen.predicates())} or an Allen relation, not #{inspect(predicate)}"
         )}
  end

  # Every pairing of readings is judged, so there may be no more pairings than values at once.
  defp few_enough(readings_a, readings_b, expression) do
    if length(readings_a) * length(readings_b) > Limit.values(),
      do: {:error, ConversionError.exception(value: expression, reason: :too_many_values)},
      else: :ok
  end

  defp verdict({:error, exception}), do: raise(exception)
  defp verdict(verdict), do: verdict

  # ── Frames ────────────────────────────────────────────────────────────

  @doc """
  An expression in another calendar: the same spans, their dates written in
  that calendar. A date keeps its time of day; a value written to a month or
  a year becomes the span of dates it covers, a month of one calendar being
  no month of another; a set converts member by member.

  A recurrence with no end is converted as a rule: it is still selected in
  its own calendar, and each of its spans is read in `calendar`. So a set
  holds rules of several calendars, each read in the set's: Eid al-Fitr
  beside National Day, both in the Gregorian. Such a rule has no ISO 8601
  text, its own calendar having no place inside another's.

  ### Arguments

  * `expression` is a `t:t/0` that has spans.

  * `calendar` is a calendar module.

  ### Returns

  * `{:ok, converted}`, a `t:t/0` in `calendar`.

  * `{:error, %Tempo.InvalidCalendarError{}}` when `calendar` is not one, or
    the error `to_interval/2` gives for an expression with no spans.

  ### Examples

      iex> Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)
      {:ok, ~o"5786-09-30[u-ca=hebrew]"}

      iex> Tempo.to_calendar(~o"2026-06-15T09:30", Calendrical.Hebrew)
      {:ok, ~o"5786-09-30T09:30[u-ca=hebrew]"}

      iex> Tempo.to_calendar(~o"5786-09[u-ca=hebrew]", Calendar.ISO)
      {:ok, ~o"2026-05-17/2026-06-15"}

      iex> eid = Tempo.every!(~o"P1Y", select: [month: 10, day: 1], calendar: Calendrical.Islamic.UmmAlQura)
      iex> {:ok, in_gregorian} = Tempo.to_calendar(eid, Calendar.ISO)
      iex> Tempo.to_interval(in_gregorian, within: ~o"2026")
      {:ok, ~o"{2026-03-20/2026-03-20}"}

  """
  @spec to_calendar(t(), module()) :: {:ok, t()} | {:error, error()}
  def to_calendar(other, _calendar) when not is_struct(other, __MODULE__),
    do: not_an_expression(other)

  def to_calendar(%__MODULE__{calendar: calendar} = expression, calendar), do: {:ok, expression}

  def to_calendar(%__MODULE__{} = expression, calendar) do
    with {:ok, calendar} <- calendar_of(calendar) do
      if Algebra.endless?(expression),
        do: {:ok, read_in(expression, calendar)},
        else: converted(expression, calendar)
    end
  end

  # A rule with no end is converted as a rule: it is selected in its own
  # calendar, and each of its spans read in the other (decision 40).
  defp read_in(%__MODULE__{form: {:when, rule, read_in: _}}, calendar),
    do: read_in(rule, calendar)

  defp read_in(%__MODULE__{calendar: calendar} = rule, calendar), do: rule

  defp read_in(%__MODULE__{} = rule, calendar) do
    %__MODULE__{
      form: {:when, rule, read_in: calendar},
      calendar: calendar,
      zone: rule.zone,
      metadata: rule.metadata
    }
  end

  defp converted(expression, calendar) do
    with {:ok, _frame, positioned} <- Algebra.positioned(expression, []) do
      frame = %{calendar: calendar, zone: expression.zone}
      converted = Enum.map(positioned, &converted_span(&1, frame))

      case {expression.form, converted} do
        {{:value, _}, [one]} -> {:ok, as_value(one, expression)}
        {{:span, _, _}, [one]} -> {:ok, one}
        _ -> {:ok, set_of(converted, %{expression | calendar: calendar})}
      end
    end
  end

  @doc """
  An expression with its weeks begun on another day: the same days, in the
  Gregorian calendar whose weeks begin on the day given. It is written with
  the suffix `[u-fw=sun]`, BCP 47's first day of the week, and is what an
  RRULE's `WKST` reads to.

  Week 1 of a year is its first week with four days in it, as in ISO 8601,
  whatever day begins it; a day of a numbered week (`2026-W25-1`) is counted
  from that day, and a weekday on its own (`1K`, Monday) is not moved. A
  week is of one start, so a week converted is the span of its days.

  ### Arguments

  * `expression` is a `t:t/0` in the Gregorian calendar.

  * `day` is the day a week begins on, 1 (Monday) to 7 (Sunday).

  ### Returns

  * `{:ok, expression}`.

  * `{:error, %ArgumentError{}}` for a day that is none, or an expression of
    a calendar that is not the Gregorian, which has its own weeks.

  ### Examples

      iex> Tempo.to_week_start(~o"2026-06-21", 7)
      {:ok, ~o"2026-06-21[u-fw=sun]"}

      iex> {:ok, saturday} = Tempo.to_week_start(~o"2026-06-20", 7)
      iex> Tempo.week(saturday)
      24
      iex> Tempo.week(~o"2026-06-20")
      25

      iex> ~o"2026-W25[u-fw=sun]" |> Tempo.to_interval!() |> Tempo.to_calendar!(Calendar.ISO)
      ~o"2026-06-21/2026-06-27"

  """
  @spec to_week_start(t(), 1..7) :: {:ok, t()} | {:error, error()}
  def to_week_start(other, _day) when not is_struct(other, __MODULE__),
    do: not_an_expression(other)

  def to_week_start(%__MODULE__{calendar: calendar} = expression, day) do
    with {:ok, calendar} <- Tempo.Calendar.with_week_start(calendar, day),
         do: to_calendar(expression, calendar)
  end

  @doc """
  The day an expression's weeks begin on, 1 (Monday) to 7 (Sunday): Monday
  unless it was written or built with another. Nil for an expression of a
  calendar that is not the Gregorian, whose weeks are its own.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * The day, 1 to 7, or `nil` for a calendar whose weeks are its own.

  ### Examples

      iex> Tempo.week_start(~o"2026-W25")
      1

      iex> Tempo.week_start(~o"2026-W25[u-fw=sun]")
      7

  """
  @spec week_start(t()) :: 1..7 | nil
  def week_start(%__MODULE__{calendar: calendar}) do
    cond do
      day = Tempo.Calendar.week_start(calendar) -> day
      Tempo.Calendar.gregorian?(calendar) -> 1
      true -> nil
    end
  end

  def week_start(other), do: not_an_expression!(other)

  # A span's ends written in the calendar at day resolution, or at the clock's where they have one.
  defp converted_span(
         %{start: start, stop: stop, span: %__MODULE__{form: {:span, from, to}}},
         frame
       ) do
    %__MODULE__{
      form:
        {:span, Spans.at_position(start, from, :start, frame.calendar, frame.zone),
         Spans.at_position(stop, to, :end, frame.calendar, frame.zone)},
      calendar: frame.calendar,
      zone: frame.zone
    }
  end

  # A converted or moved value is one value again where the result is one
  # unit of its own resolution, read at its start: a Paris hour is a New York
  # hour, but half past the hour in Kolkata is a span of minutes.
  defp as_value(%__MODULE__{form: {:span, _, _}} = span, %__MODULE__{} = original) do
    case Spans.extent(span) do
      {:ok, {start, _} = extent} when is_integer(start) ->
        candidate = Spans.at_position(start, original, :start, span.calendar, span.zone)
        if same_extent?(candidate, extent), do: candidate, else: span

      _ ->
        span
    end
  end

  defp same_extent?(candidate, extent) do
    case Spans.as_span(candidate) do
      {:ok, candidate_span} -> Spans.extent(candidate_span) == {:ok, extent}
      {:error, _} -> false
    end
  end

  @doc """
  A floating expression placed in a time zone, its readings unchanged: the
  runtime form of writing `[zone]` after it.

  ### Arguments

  * `expression` is a `t:t/0` with no zone and no shift.

  * `zone` is a time zone name the database knows, or a fixed offset as
    IXDTF writes one (`"+02:00"`).

  ### Returns

  * `{:ok, zoned}`.

  * `{:error, %Tempo.ZoneError{}}` when the zone is not known or its clock
    skips the reading, or `{:error, %Tempo.FrameError{}}` when the expression
    is already zoned or shifted (`shift_zone/2` moves one).

  ### Examples

      iex> Tempo.in_zone(~o"2026-06-15T10", "Europe/Paris")
      {:ok, ~o"2026-06-15T10[Europe/Paris]"}

      iex> Tempo.in_zone(~o"2026-06-15T10", "+02:00")
      {:ok, ~o"2026-06-15T10[+02:00]"}

      iex> {:error, %Tempo.FrameError{}} = Tempo.in_zone(~o"2026-06-15T10Z", "Europe/Paris")

  """
  @spec in_zone(t(), String.t()) :: {:ok, t()} | {:error, error()}
  def in_zone(other, _zone) when not is_struct(other, __MODULE__), do: not_an_expression(other)
  def in_zone(_expression, zone) when not is_binary(zone), do: not_a_zone(zone)

  def in_zone(%__MODULE__{} = expression, zone) do
    with {:ok, zone} <- Zone.written(zone), do: Build.in_zone(expression, zone)
  end

  @doc """
  An expression with its seasons given their months in a territory. A
  season of 21 to 24 (spring, summer, autumn, winter) is three whole months,
  and which three is the hemisphere's to say: spring is March to May north
  of the equator and September to November south of it.

  A season of a hemisphere (25 to 32) names its own and is as it was, as is
  an expression with no season in it.

  ### Arguments

  * `expression` is a `t:t/0`: a season, an interval with a season at an end,
    or a set of them.

  * `territory` is a territory (`:AU`, `"GB"`) or a locale whose territory
    is taken (`"en-AU"`), as `Tempo.Territory.resolve/1` reads it.

  ### Returns

  * `{:ok, expression}`, each season the interval of its months.

  * `{:error, %Tempo.ConversionError{}}` for a territory on no one side of
    the equator (Brazil, Kenya, the world).

  * `{:error, %Tempo.IntervalEndpointsError{}}` for an interval of seasons
    that ends before it begins in that hemisphere.

  * `{:error, %ArgumentError{}}` for what names no territory.

  ### Examples

      iex> Tempo.in_territory(~o"2026-21", :GB)
      {:ok, ~o"2026-03/2026-05"}

      iex> Tempo.in_territory(~o"2026-21", :AU)
      {:ok, ~o"2026-09/2026-11"}

      iex> Tempo.in_territory(~o"2026-22", :NZ)
      {:ok, ~o"2026-12/2027-02"}

      iex> {:error, %Tempo.ConversionError{}} = Tempo.in_territory(~o"2026-21", :BR)

  """
  @spec in_territory(t(), atom() | String.t()) :: {:ok, t()} | {:error, error()}
  def in_territory(other, _territory) when not is_struct(other, __MODULE__),
    do: not_an_expression(other)

  def in_territory(%__MODULE__{} = expression, territory) do
    with {:ok, territory} <- Tempo.Territory.resolve(territory),
         {:ok, placed} <- Season.in_territory(expression, territory) do
      Validate.run(placed)
    end
  end

  @doc """
  `in_territory/2`, returning the expression or raising.

  ### Arguments

  * The arguments are those of `in_territory/2`.

  ### Returns

  * What `in_territory/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.in_territory!(~o"2026-23", :AU)
      ~o"2026-03/2026-05"

  """
  @spec in_territory!(t(), atom() | String.t()) :: t()
  def in_territory!(expression, territory) do
    case in_territory(expression, territory) do
      {:ok, placed} -> placed
      {:error, exception} -> raise exception
    end
  end

  # An expression asked for with a territory or a locale named has its
  # seasons given their months there; with neither it is as it was, and a
  # season is given its dates where they are needed by the territory in force.
  defp seasons_placed(%__MODULE__{} = expression, options) do
    case territory_named(options) do
      {:ok, nil} -> {:ok, expression}
      {:ok, territory} -> in_territory(expression, territory)
      {:error, _exception} = error -> error
    end
  end

  defp seasons_placed(other, _options), do: {:ok, other}

  # The territory an option names: `:territory` itself, or the territory of
  # a `:locale`, which is read as a locale (`"ar"` is Arabic, and Egypt).
  defp territory_named(options) do
    case {options[:territory], options[:locale]} do
      {nil, nil} -> {:ok, nil}
      {nil, locale} -> Localize.Territory.territory_from_locale(locale)
      {territory, _locale} -> Tempo.Territory.resolve(territory)
    end
  end

  @doc """
  A zoned expression moved to another time zone: the same instants, read on
  that zone's clock. A value whose span is one reading there stays a value;
  a day in Paris is a span from six in the evening to six in New York.

  ### Arguments

  * `expression` is a `t:t/0` with a zone or a shift.

  * `zone` is a time zone name the database knows.

  ### Returns

  * `{:ok, moved}`, a `t:t/0` in `zone`.

  * `{:error, %Tempo.FrameError{}}` when the expression is floating
    (`in_zone/2` places one), or `{:error, %Tempo.ZoneError{}}`.

  ### Examples

      iex> Tempo.shift_zone(~o"2026-06-15T14:00[Europe/Paris]", "America/New_York")
      {:ok, ~o"2026-06-15T08:00[America/New_York]"}

      iex> Tempo.shift_zone(~o"2026-06-15[Europe/Paris]", "America/New_York")
      {:ok, ~o"2026-06-14T18/2026-06-15T18[America/New_York]"}

      iex> Tempo.shift_zone(~o"2026-06-15T14[Europe/Paris]", "Asia/Kolkata")
      {:ok, ~o"2026-06-15T17:30/2026-06-15T18:30[Asia/Kolkata]"}

  """
  @spec shift_zone(t(), String.t()) :: {:ok, t()} | {:error, error()}
  def shift_zone(other, _zone) when not is_struct(other, __MODULE__), do: not_an_expression(other)
  def shift_zone(_expression, zone) when not is_binary(zone), do: not_a_zone(zone)

  def shift_zone(%__MODULE__{} = expression, zone) do
    with :ok <- zoned(expression),
         {:ok, zone} <- Zone.named(zone),
         {:ok, _frame, positioned} <- Algebra.positioned(expression, []) do
      frame = %{calendar: expression.calendar, zone: zone}
      moved = Enum.map(positioned, &moved_span(&1, frame))

      case {expression.form, moved} do
        {{:value, _}, [one]} -> {:ok, as_value(one, expression)}
        {{:span, _, _}, [one]} -> {:ok, one}
        _ -> {:ok, set_of(moved, %{expression | zone: zone})}
      end
    end
  end

  defp zoned(%__MODULE__{} = expression) do
    if Spans.frame(expression) == :utc,
      do: :ok,
      else: {:error, FrameError.exception(a: expression, b: nil, reason: :floating)}
  end

  # A span's ends read on the new zone's clock to the minute, or to the hour
  # where the minutes are zero and the end was no finer than an hour.
  defp moved_span(
         %{start: start, stop: stop, span: %__MODULE__{form: {:span, from, to}} = span},
         frame
       ) do
    from_value = Spans.at_position(start, clock_model(from), :start, frame.calendar, frame.zone)
    to_value = Spans.at_position(stop, clock_model(to), :end, frame.calendar, frame.zone)

    %__MODULE__{
      form: {:span, trimmed(from_value, from), trimmed(to_value, to)},
      calendar: frame.calendar,
      zone: frame.zone,
      metadata: span.metadata
    }
  end

  defp trimmed(%__MODULE__{form: {:value, units}} = value, %__MODULE__{form: {:value, original}}) do
    coarse? = Unit.compare(Unit.resolution(original), :minute) == :lt

    case List.last(units) do
      {:minute, 0} when coarse? -> %{value | form: {:value, Enum.drop(units, -1)}}
      _ -> value
    end
  end

  # An end moved between zones is read to the minute, or finer where it was:
  # a date's edges fall within days there, an hour's within hours.
  defp clock_model(%__MODULE__{form: {:value, units}} = model) do
    clock = Unit.clock_units(units)

    clock =
      cond do
        clock == [] -> [hour: 0, minute: 0]
        Keyword.has_key?(clock, :minute) -> clock
        true -> clock ++ [minute: 0]
      end

    %{model | form: {:value, Unit.date_units(units) ++ clock}, shift: nil}
  end

  @doc """
  One value placed on another: a date at a time of day, a time of day on a
  date, a month and a day. The value with a year keeps it and the other
  supplies the finer units it lacks; a unit between the two that neither
  names is its first. An interval is placed end by end. A selection selects
  within the units before it, so it follows the other's units and finer
  units follow it, with nothing filled beside it.

  ### Arguments

  * `value` and `other` are each a `t:t/0`, at most one of them with a year,
    or one of them an interval whose ends are placed on the other.

  ### Returns

  * `{:ok, placed}`, a `t:t/0`.

  * `{:error, exception}` when both have a year, both hold a selection,
    either is not a `t:t/0`, or the result is no date or time the calendar
    and zone have.

  ### Examples

      iex> Tempo.at(~o"2026-06-15", ~o"T17")
      {:ok, ~o"2026-06-15T17"}

      iex> Tempo.at(~o"T17", ~o"2026-06-15")
      {:ok, ~o"2026-06-15T17"}

      iex> Tempo.at(~o"3M", ~o"2D")
      {:ok, ~o"3M2D"}

      iex> Tempo.at(~o"2026-06-15", ~o"T09/T17")
      {:ok, ~o"2026-06-15T09/2026-06-15T17"}

      iex> Tempo.at(~o"2026-06", ~o"T17")
      {:ok, ~o"2026-06-01T17"}

      iex> Tempo.on(~o"L(easter)eN", ~o"2027")
      {:ok, ~o"2027YL(easter)eN"}

  """
  @spec at(t(), t()) :: {:ok, t()} | {:error, error()}
  def at(%__MODULE__{form: {:span, from, to}} = span, %__MODULE__{form: {:value, _}} = other) do
    with {:ok, from} <- placed_end(from, other),
         {:ok, to} <- placed_end(to, other) do
      placed = %{
        span
        | form: {:span, from, to},
          calendar: other.calendar,
          zone: span.zone || other.zone
      }

      Validate.run(placed)
    end
  end

  def at(%__MODULE__{form: {:value, _}} = value, %__MODULE__{form: {:span, _, _}} = span),
    do: at(span, value)

  def at(%__MODULE__{form: {:value, a}} = value, %__MODULE__{form: {:value, b}} = other) do
    case {Unit.anchored?(a), Unit.anchored?(b)} do
      {true, true} -> {:error, FrameError.exception(a: value, b: other, reason: :several)}
      {false, true} -> at(other, value)
      _ when value == other -> {:ok, value}
      _ -> composed(value, other)
    end
  end

  def at(%__MODULE__{form: {:every, first, bound, rule}} = recurrence, %__MODULE__{} = other) do
    with {:ok, first} <- at(first, other),
         {:ok, bound} <- placed_end(bound, other) do
      Validate.run(%{recurrence | form: {:every, first, bound, rule}, calendar: other.calendar})
    end
  end

  def at(%__MODULE__{form: {kind, members}} = set, %__MODULE__{} = other)
      when kind in [:all, :one] do
    with :ok <- Spans.whole(set),
         {:ok, members} <- each_at(members, other) do
      Validate.run(%{set | form: {kind, members}, calendar: other.calendar})
    end
  end

  def at(%__MODULE__{} = value, %__MODULE__{form: {kind, _, _, _}} = recurrence)
      when kind == :every,
      do: at(recurrence, value)

  def at(%__MODULE__{} = value, %__MODULE__{form: {kind, _}} = set) when kind in [:all, :one],
    do: at(set, value)

  def at(%__MODULE__{} = a, %__MODULE__{} = b),
    do: {:error, FrameError.exception(a: a, b: b, reason: :several)}

  def at(%__MODULE__{}, other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_expression)}

  def at(other, _value),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_expression)}

  defp each_at(members, other) do
    Enum.reduce_while(members, {:ok, []}, fn member, {:ok, acc} ->
      case at(member, other) do
        {:ok, placed} -> {:cont, {:ok, acc ++ [placed]}}
        error -> {:halt, error}
      end
    end)
  end

  defp placed_end(%__MODULE__{} = value, other), do: at(other, value)
  defp placed_end(other, _value), do: {:ok, other}

  # The coarser value's units above the finer's first unit, the chain between
  # filled with its first values, then the finer's units whole. A finer value
  # of any year alone (`X*Y`) adds nothing to the other. A selection selects
  # within the units before it, so nothing is filled beside one: a selection
  # follows the coarser value's units, and finer units follow a selection.
  defp composed(
         %__MODULE__{form: {:value, coarse}} = value,
         %__MODULE__{form: {:value, b}} = other
       ),
       do: composed(value, other, coarse, Unit.cyclic(b))

  defp composed(value, _other, _coarse, []), do: {:ok, value}

  defp composed(value, other, coarse, fine) do
    first = Unit.coarsest(fine)
    selects? = Keyword.has_key?(coarse, :selection)

    cond do
      selects? and Keyword.has_key?(fine, :selection) ->
        {:error, ConversionError.exception(value: other, reason: :selection)}

      selects? or first == :selection ->
        placed_units(value, other, coarse ++ fine)

      Unit.label?(first) and not Expand.one_span?(coarse ++ fine) ->
        {:error, ConversionError.exception(value: other, reason: :selection)}

      true ->
        composed_units(value, other, coarse, fine, first)
    end
  end

  defp composed_units(value, other, coarse, fine, first) do
    coarse
    |> Enum.take_while(fn {unit, _} -> Unit.compare(unit, first) == :lt end)
    |> Expand.filled_to(first)
    |> Kernel.++(fine)
    |> then(&placed_units(value, other, &1))
  end

  defp placed_units(value, other, filled) do
    Validate.run(%{
      value
      | form: {:value, filled},
        zone: value.zone || other.zone,
        shift: value.shift || other.shift
    })
  end

  @doc """
  `at/2` with its arguments the other way round, so that the code reads as
  English does: *10:30 on 4 January*.

  ### Arguments

  * `value` is a `t:t/0`, a time of day.

  * `other` is a `t:t/0`, a date.

  ### Returns

  * What `at(other, value)` returns.

  ### Examples

      iex> Tempo.on(~o"T10:30", ~o"2026-01-04")
      {:ok, ~o"2026-01-04T10:30"}

  """
  @spec on(t(), t()) :: {:ok, t()} | {:error, error()}
  def on(value, other), do: at(other, value)

  # ── Arithmetic ────────────────────────────────────────────────────────

  @doc """
  An expression moved by a duration.

  A value is shifted at its own resolution, extended to the duration's
  finest unit where that is finer: a year a day on is its second day. Years
  and months are counted first, through the calendar, with the day clamped
  to the month landed in as `Date.shift/2` clamps it; then weeks and days;
  then the units of the clock as elapsed time, so an hour across a change
  of the clocks is an hour. A value stays on its own axis: a week date a day
  on is a week date. An interval is moved end by end, and keeps its length
  when the duration has a month or a year; a set is moved member by member;
  a recurrence by its first span and its end.

  A value with no year is shifted when the answer is the same in every
  year: the thirty-first of January a day on is the first of February, but a
  month on it has no answer, and a year on it is itself.

  A value that names several (`2026Y6M{1,15}D`, a mask) is each value it
  names shifted, written as one value where its units can hold them all,
  and as a set of values where they cannot. A mask the shift carries is one
  of the values it lands on.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `by` is a `t:Tempo.Duration.t/0`, its ISO 8601 text, or a keyword list
    of units and amounts such as `[month: 1, day: -5]`; amounts may be
    negative.

  * `options` is a keyword list of options, which may ride in the keyword
    form of `by`.

  ### Options

  * `:skipping` is a busy set the shift jumps over: a `t:t/0` with spans,
    or a list of them. The duration is consumed from free time only, so a
    busy span costs nothing to cross, and an origin inside one first moves
    to its edge. The duration must be exact (weeks, days and units of the
    clock); a month or a year of free time has no fixed length. A date
    shifted by days or weeks steps from free day to free day.

  ### Returns

  * `{:ok, expression}`, the expression moved.

  * `{:error, %Tempo.ConversionError{}}` with reason `:needs_a_year` when
    the answer depends on a year the value has not, `:group` when the value
    ends in a group, `{:inexact, unit}` when `:skipping` is given a month or
    a year, and `:selection` when the value holds a selection; and
    `{:error, exception}` when `by` is not a duration.

  ### Examples

      iex> Tempo.shift(~o"2026-06-15", ~o"P1D")
      {:ok, ~o"2026-06-16"}

      iex> Tempo.shift(~o"2026-01-31", month: 1)
      {:ok, ~o"2026-02-28"}

      iex> Tempo.shift(~o"2026", "P1D")
      {:ok, ~o"2026-01-02"}

      iex> Tempo.shift(~o"2026-W25", day: 1)
      {:ok, ~o"2026Y25W2K"}

      iex> Tempo.shift(~o"2026Y6M{1,15}D", day: 1)
      {:ok, ~o"2026Y6M{2,16}D"}

      iex> Tempo.shift(~o"1M31D", day: 1)
      {:ok, ~o"2M1D"}

      iex> {:error, %Tempo.ConversionError{reason: :needs_a_year}} = Tempo.shift(~o"1M31D", month: 1)

      iex> meeting = ~o"2026-06-15T10:00/2026-06-15T11:00"
      iex> Tempo.shift(~o"2026-06-15T09:30", ~o"PT1H", skipping: meeting)
      {:ok, ~o"2026-06-15T11:30"}

  """
  @spec shift(t(), Duration.t() | keyword() | String.t(), keyword()) ::
          {:ok, t()} | {:error, error()}
  def shift(expression, by, options \\ [])

  def shift(expression, by, options) when is_expression(expression) do
    with :ok <- Options.check(options, [:skipping], "Tempo.shift/3"),
         do: shift_by(expression, by, options)
  end

  def shift(other, _by, _options), do: not_an_expression(other)

  defp shift_by(expression, by, options) when is_list(by) do
    {skipping, units} = Keyword.pop(by, :skipping)

    with {:ok, duration} <- Duration.new(units),
         do: shift_by(expression, duration, Keyword.put_new(options, :skipping, skipping))
  end

  defp shift_by(expression, by, options) when is_binary(by) do
    case from_iso8601(by) do
      {:ok, %Duration{} = duration} -> shift_by(expression, duration, options)
      {:ok, other} -> {:error, ConversionError.exception(value: other, reason: :not_a_duration)}
      {:error, _} = error -> error
    end
  end

  defp shift_by(expression, %Duration{} = by, options) do
    case Keyword.get(options, :skipping) do
      nil -> Shift.shift(expression, by)
      busy -> Shift.skipping(expression, by, busy_set(busy))
    end
  end

  defp shift_by(_expression, by, _options),
    do: {:error, ConversionError.exception(value: by, reason: :not_a_duration)}

  defp busy_set(%__MODULE__{} = busy), do: busy

  defp busy_set([%__MODULE__{} = first | _] = members),
    do: %__MODULE__{form: {:all, members}, calendar: first.calendar, zone: first.zone}

  defp busy_set(other), do: other

  @doc """
  An expression written to a coarser unit: its units through that one, so
  a date and time truncated to the day is the date.

  A unit the value is not written in names the period of it the value
  starts in: a date truncated to the week is its week, written as a week
  date. The ends of an interval and the members of a set are truncated
  each. A unit finer than the value is written to leaves it as it is.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `unit` is a unit; the default is `:day`.

  ### Returns

  * `{:ok, expression}`.

  * `{:error, %Tempo.ConversionError{}}` when a unit the value is not
    written in is asked of a value that names several periods, or has no
    year.

  ### Examples

      iex> Tempo.trunc(~o"2022-11-21T09:30:00")
      {:ok, ~o"2022-11-21"}

      iex> Tempo.trunc(~o"2022-11-21T09:30:00", :minute)
      {:ok, ~o"2022-11-21T09:30"}

      iex> Tempo.trunc(~o"2026-08-16T10:00:00", :week)
      {:ok, ~o"2026-W33"}

      iex> Tempo.trunc(~o"2026Y6M{1,15}D", :month)
      {:ok, ~o"2026-06"}

  """
  @spec trunc(t(), unit()) :: {:ok, t()} | {:error, error()}
  def trunc(expression, unit \\ :day)

  def trunc(expression, unit) when is_expression(expression) do
    with :ok <- a_unit(unit), do: Shift.trunc(expression, unit)
  end

  def trunc(other, _unit), do: not_an_expression(other)

  @doc """
  A value rounded to the nearest period of a unit: the period it starts in,
  or the next when its start is past the midpoint, measured in elapsed
  time. Half way rounds up, as `Kernel.round/1` does.

  ### Arguments

  * `expression` is a `t:t/0` that is one value, or an interval or set of
    them, rounded end by end and member by member.

  * `unit` is a unit no finer than the value is written to; the default is
    `:day`.

  ### Returns

  * `{:ok, expression}` at the unit's resolution.

  * `{:error, %Tempo.ConversionError{}}` with reason
    `{:finer_than_written, unit}` when the unit is finer than the value,
    and `:several` when the value names several.

  ### Examples

      iex> Tempo.round(~o"2022-11-21T13:30:00")
      {:ok, ~o"2022-11-22"}

      iex> Tempo.round(~o"2022-11-21", :month)
      {:ok, ~o"2022-12"}

      iex> Tempo.round(~o"2026-02-15", :month)
      {:ok, ~o"2026-03"}

      iex> Tempo.round(~o"T23:45", :hour)
      {:ok, ~o"T0H"}

  """
  @spec round(t(), unit()) :: {:ok, t()} | {:error, error()}
  def round(expression, unit \\ :day)

  def round(expression, unit) when is_expression(expression) do
    with :ok <- a_unit(unit), do: Shift.round(expression, unit)
  end

  def round(other, _unit), do: not_an_expression(other)

  @doc """
  A value with its next finer unit written as the values that unit takes:
  a year as its months, a month as its days, a day in a zone as the hours
  its clock shows, a group as the values it names.

  Under a value that names several, the finer unit is written from its
  first value to its last (`{1..-1}`). With a unit given, the value is
  extended level by level down to it.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `unit` is the unit to extend to, or `nil` for one level.

  ### Returns

  * `{:ok, expression}`.

  * `{:error, %Tempo.ConversionError{reason: :no_finer_unit}}` for a value
    written to the second or finer.

  ### Examples

      iex> Tempo.extend(~o"2020")
      {:ok, ~o"2020Y{1..12}M"}

      iex> Tempo.extend(~o"2026-06")
      {:ok, ~o"2026Y6M{1..30}D"}

      iex> Tempo.extend(~o"2026Y{6,7}M")
      {:ok, ~o"2026Y{6,7}M{1..-1}D"}

      iex> Tempo.extend(~o"2026Y2G3MU")
      {:ok, ~o"2026Y{4..6}M"}

      iex> Tempo.extend(~o"2026-03-29[Europe/Paris]")
      {:ok, ~o"2026Y3M29DT{0..1,3..23}H[Europe/Paris]"}

  """
  @spec extend(t(), unit() | nil) :: {:ok, t()} | {:error, error()}
  def extend(expression, unit \\ nil)

  def extend(expression, unit) when is_expression(expression), do: Shift.extend(expression, unit)
  def extend(other, _unit), do: not_an_expression(other)

  @doc """
  A value written at a unit: truncated to a coarser one as `trunc/2`
  truncates, and extended to a finer one with the first value of each unit
  between.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `unit` is a unit.

  ### Returns

  * `{:ok, expression}`, or `{:error, exception}` as for `trunc/2`.

  ### Examples

      iex> Tempo.at_resolution(~o"2020Y", :day)
      {:ok, ~o"2020Y1M1D"}

      iex> Tempo.at_resolution(~o"2020Y6M15DT10H", :day)
      {:ok, ~o"2020Y6M15D"}

      iex> Tempo.at_resolution(~o"2026-W25", :hour)
      {:ok, ~o"2026Y25W1KT0H"}

  """
  @spec at_resolution(t(), unit()) :: {:ok, t()} | {:error, error()}
  def at_resolution(expression, unit) when is_expression(expression) do
    with :ok <- a_unit(unit), do: Shift.at_resolution(expression, unit)
  end

  def at_resolution(other, _unit), do: not_an_expression(other)

  @doc """
  A value split into its date and its time of day, each keeping the value's
  calendar, zone, qualifications and metadata, so that `at/2` of the two is
  the value.

  ### Arguments

  * `value` is a `t:t/0` that is one value.

  ### Returns

  * `{date, time}`, either `nil` when the value has none.

  * `{:error, exception}` for an expression that is not a value.

  ### Examples

      iex> Tempo.split(~o"2026-06-15T14:30:00")
      {~o"2026Y6M15D", ~o"T14H30M0S"}

      iex> Tempo.split(~o"2026-06-15T14:30[Europe/Paris]")
      {~o"2026Y6M15D[Europe/Paris]", ~o"T14H30M[Europe/Paris]"}

      iex> Tempo.split(~o"2026-06-15")
      {~o"2026Y6M15D", nil}

  """
  @spec split(t()) :: {t() | nil, t() | nil} | {:error, error()}
  def split(value) when is_expression(value), do: Shift.split(value)
  def split(other), do: not_an_expression(other)

  # ── Lengths ───────────────────────────────────────────────────────────

  @doc """
  The duration an expression covers, in the unit it is written to.

  A value is one unit of its resolution long: a month is `P1M`, whichever
  month. An interval is measured between its ends in their finer unit, days
  between two dates and elapsed hours between two times, so a day across a
  change of the clocks is 23 or 25 hours. A set, a recurrence or a value
  that names several is the time it covers once, summed.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * A `t:Tempo.Duration.t/0`, or `:infinity` for an open end or a
    recurrence with none.

  * `{:error, %Tempo.ConversionError{}}` with reason `:needs_a_year` for an
    interval or set of dates with no year, whose length is its year's, and
    `:bare_duration` for a duration.

  ### Examples

      iex> Tempo.duration(~o"2026-06-15T09:00/2026-06-15T10:30")
      ~o"PT90M"

      iex> Tempo.duration(~o"2026-06")
      ~o"P1M"

      iex> Tempo.duration(~o"2026-06-15/2026-06-20")
      ~o"P6D"

      iex> Tempo.duration(~o"T22/T02")
      ~o"PT4H"

      iex> bookings = Tempo.IntervalSet.new!([~o"2026-06-15T09/2026-06-15T11", ~o"2026-06-15T10/2026-06-15T12"])
      iex> Tempo.duration(bookings)
      ~o"PT3H"

  """
  @spec duration(t() | Duration.t()) :: Duration.t() | :infinity | {:error, error()}
  def duration(expression) when is_expression(expression), do: Measure.duration(expression)
  def duration(other), do: not_an_expression(other)

  @doc """
  The duration from the start of one value to the start of another, in
  their finer unit: days between two dates, elapsed hours between two
  times. Unlike an interval written between them, which runs through its
  last date, this measures start to start.

  Given an expression and options, it is `duration/1` of the expression
  with the options applied.

  ### Arguments

  * `from` and `to` are each a `t:t/0` with one span, on one frame, `to`
    after `from`.

  * Or `expression`, a `t:t/0`, and `options`, a keyword list.

  ### Options

  * `:leap_seconds` is `true` to count the leap seconds the expression
    spans (`Tempo.LeapSeconds.spanned/1`) into its length, a second for
    each. The default is `false`: a length on the clock, in which every
    minute is sixty seconds.

  ### Returns

  * `{:ok, duration}` for two values.

  * A `t:Tempo.Duration.t/0`, `:infinity` or `{:error, exception}` for an
    expression and options, as `duration/1` returns them.

  * `{:error, %Tempo.IntervalEndpointsError{}}` when `to` is not after
    `from`, and `{:error, %Tempo.FrameError{}}` when the two share no frame.

  ### Examples

      iex> Tempo.duration(~o"2026-09-28", ~o"2026-11-03")
      {:ok, ~o"P36D"}

      iex> Tempo.duration(~o"2026-09-28T10", ~o"2026-09-29")
      {:ok, ~o"PT14H"}

      iex> new_year = ~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z"
      iex> Tempo.duration(new_year)
      ~o"PT120S"
      iex> Tempo.duration(new_year, leap_seconds: true)
      ~o"PT121S"

  """
  @spec duration(t(), t()) :: {:ok, Duration.t()} | {:error, error()}
  @spec duration(t(), keyword()) :: Duration.t() | :infinity | {:error, error()}
  def duration(expression, options) when is_list(options) do
    case Keyword.validate(options, leap_seconds: false) do
      {:ok, [leap_seconds: true]} ->
        with_leap_seconds(expression)

      {:ok, [leap_seconds: false]} ->
        Measure.duration(expression)

      _other ->
        {:error,
         ArgumentError.exception(":leap_seconds, true or false, is the one option of duration/2")}
    end
  end

  def duration(from, to), do: Measure.between(from, to)

  defp with_leap_seconds(expression) do
    case {Measure.duration(expression), LeapSeconds.count(expression)} do
      {%Duration{} = duration, {:ok, 0}} -> duration
      {%Duration{} = duration, {:ok, n}} -> Duration.add(duration, %Duration{units: [second: n]})
      {%Duration{}, {:error, _} = error} -> error
      {other, _count} -> other
    end
  end

  for {name, comparison, phrase} <- [
        {:at_least?, :at_least, "at least as long as"},
        {:at_most?, :at_most, "no longer than"},
        {:exactly?, :exactly, "exactly as long as"},
        {:longer_than?, :longer, "longer than"},
        {:shorter_than?, :shorter, "shorter than"}
      ] do
    @doc """
    Whether an expression is #{phrase} a duration.

    The expression is measured as `duration/1` measures it, as the time it
    covers; the duration is laid from the expression's start, so a month is
    as long as the month it starts in. An open end is longer than any
    duration.

    ### Arguments

    * `expression` is a `t:t/0`.

    * `duration` is a `t:Tempo.Duration.t/0`.

    ### Returns

    * `true` or `false`.

    * `{:error, exception}` as for `duration/1`.

    ### Examples

        iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
        iex> Tempo.#{name}(meeting, ~o"PT1H")
        #{comparison in [:at_least, :longer]}

        iex> meeting = ~o"2026-06-15T09:00/2026-06-15T10:30"
        iex> Tempo.#{name}(meeting, ~o"PT90M")
        #{comparison in [:at_least, :at_most, :exactly]}

    """
    @spec unquote(name)(t(), Duration.t()) :: boolean() | {:error, error()}
    def unquote(name)(expression, duration) when is_expression(expression),
      do: Measure.holds?(unquote(comparison), expression, duration)

    def unquote(name)(other, _duration), do: not_an_expression(other)
  end

  # ── Parts ─────────────────────────────────────────────────────────────

  for {name, unit, example, answer, none} <- [
        {:year, :year, ~s(~o"2026-06-15"), 2026, ~s(~o"202XY")},
        {:month, :month, ~s(~o"2026-06-15"), 6, ~s(~o"2026")},
        {:day, :day, ~s(~o"2026-06-15"), 15, ~s(~o"2026-06")},
        {:hour, :hour, ~s(~o"2026-06-15T10:30"), 10, ~s(~o"2026-06-15")},
        {:minute, :minute, ~s(~o"2026-06-15T10:30"), 30, ~s(~o"2026-06-15T10")},
        {:second, :second, ~s(~o"T10:30:45"), 45, ~s(~o"T10:30")},
        {:week, :week, ~s(~o"2026-W32"), 32, ~s(~o"2026-06")}
      ] do
    @doc """
    The #{unit} an expression names, as a number.

    A unit the value is written in is read as written. One the value is not
    written in, but lies within one period of, is read through the calendar:
    the day of the month of a week date, the week of a date. An interval or a
    set answers when every end or member answers the same.

    ### Arguments

    * `expression` is a `t:t/0`.

    ### Returns

    * The number, or `nil` when the expression names no #{unit} or several.

    ### Examples

        iex> Tempo.#{name}(#{example})
        #{answer}

        iex> Tempo.#{name}(#{none})
        nil

    """
    @spec unquote(name)(t()) :: integer() | nil
    def unquote(name)(expression) when is_expression(expression),
      do: Parts.part(expression, unquote(unit))

    def unquote(name)(other), do: not_an_expression!(other)
  end

  @doc """
  The day of the week an expression names, 1 to 7, Monday first by default.

  ### Arguments

  * `expression` is a `t:t/0`: a date, a week date, or an interval or set
    within one day.

  * `starting_on` is the day numbered 1: `:default` or `:monday` (the
    default), `:tuesday`, `:wednesday`, `:thursday`, `:friday`, `:saturday`
    or `:sunday`.

  ### Returns

  * The day of the week, or `nil` when the expression names no day or
    several.

  ### Examples

      iex> Tempo.day_of_week(~o"2026-06-15")
      1

      iex> Tempo.day_of_week(~o"2026-06-15", :sunday)
      2

      iex> Tempo.day_of_week(~o"2026-06")
      nil

  """
  @spec day_of_week(t(), atom()) :: 1..7 | nil
  def day_of_week(expression, starting_on \\ :default)

  def day_of_week(expression, starting_on)
      when is_expression(expression) and starting_on in @week_starts,
      do: Parts.weekday(Parts.part(expression, :day_of_week), starting_on)

  def day_of_week(expression, starting_on) when is_expression(expression),
    do: raise(ArgumentError, "a week starts on a day, as :monday, not #{inspect(starting_on)}")

  def day_of_week(other, _starting_on), do: not_an_expression!(other)

  @doc """
  The day of the year an expression names, counted from the year's first
  day.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * The day of the year, from 1; `nil` when the expression names no single
    day.

  ### Examples

      iex> Tempo.day_of_year(~o"2026-06-15")
      166

      iex> Tempo.day_of_year(~o"2026-06")
      nil

  """
  @spec day_of_year(t()) :: pos_integer() | nil
  def day_of_year(expression) when is_expression(expression),
    do: Parts.part(expression, :day_of_year)

  def day_of_year(other), do: not_an_expression!(other)

  @doc """
  The quarter of the year an expression lies in, 1 to 4.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * The quarter, 1 to 4; `nil` when the expression lies in no single
    quarter.

  ### Examples

      iex> Tempo.quarter_of_year(~o"2026-06-15")
      2

      iex> Tempo.quarter_of_year(~o"2026")
      nil

  """
  @spec quarter_of_year(t()) :: 1..4 | nil
  def quarter_of_year(expression) when is_expression(expression),
    do: Parts.part(expression, :quarter)

  def quarter_of_year(other), do: not_an_expression!(other)

  @doc """
  Whether the year an expression names is a leap year of its calendar.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * `true` or `false`.

  * `{:error, %Tempo.ConversionError{reason: :needs_a_year}}` when the
    expression names no year or several.

  ### Examples

      iex> Tempo.leap_year?(~o"2024")
      true

      iex> Tempo.leap_year?(~o"2025-06-15")
      false

  """
  @spec leap_year?(t()) :: boolean() | {:error, error()}
  def leap_year?(expression) when is_expression(expression), do: Parts.leap_year?(expression)
  def leap_year?(other), do: not_an_expression(other)

  @doc """
  The number of days in the month an expression names, in its calendar.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * `{:ok, days}`.

  * `{:error, %Tempo.ConversionError{reason: :needs_a_month}}` when the
    expression names no year and month, or several.

  ### Examples

      iex> Tempo.days_in_month(~o"2024-02-15")
      {:ok, 29}

      iex> Tempo.days_in_month(~o"2025-02")
      {:ok, 28}

  """
  @spec days_in_month(t()) :: {:ok, pos_integer()} | {:error, error()}
  def days_in_month(expression) when is_expression(expression),
    do: Parts.days_in_month(expression)

  def days_in_month(other), do: not_an_expression(other)

  @doc """
  The unit an expression is written to: the finest unit of a value, of an
  interval's ends or a set's members. A value ending in a group is written
  to the group's unit.

  ### Arguments

  * `expression` is a `t:t/0` or a `t:Tempo.Duration.t/0`.

  ### Returns

  * The unit, an atom; `nil` for an interval open at both ends, which is
    written to none.

  ### Examples

      iex> Tempo.resolution(~o"2022-11")
      :month

      iex> Tempo.resolution(~o"../..")
      nil

      iex> Tempo.resolution(~o"2022Y1M2G3DU")
      :day

      iex> Tempo.resolution(~o"2026-06-15T10/2026-06-16")
      :hour

  """
  @spec resolution(t() | Duration.t()) :: unit() | nil
  def resolution(expression) when is_expression(expression), do: Parts.resolution(expression)
  def resolution(other), do: not_an_expression!(other)

  @doc """
  Whether an expression has a year, so a place on the time line. A value
  with an unspecified year (`X*Y`) has none.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.anchored?(~o"2022")
      true

      iex> Tempo.anchored?(~o"2M")
      false

      iex> Tempo.anchored?(~o"X*Y2M")
      false

  """
  @spec anchored?(t()) :: boolean()
  def anchored?(expression) when is_expression(expression), do: Parts.anchored?(expression)
  def anchored?(other), do: not_an_expression!(other)

  @doc """
  Whether an expression is floating: a reading of a clock with no zone and
  no time shift, which names a civil time but not whose. The complement of
  `zoned?/1`.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.floating?(~o"2024-01-01")
      true

      iex> Tempo.floating?(~o"2024-01-01T10Z")
      false

      iex> Tempo.floating?(~o"2024-01-01[Australia/Sydney]")
      false

  """
  @spec floating?(t()) :: boolean()
  def floating?(expression) when is_expression(expression), do: not Parts.zoned?(expression)
  def floating?(other), do: not_an_expression!(other)

  @doc """
  Whether an expression carries a zone or a time shift, so a place on the
  universal time line. The complement of `floating?/1`.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.zoned?(~o"2024-01-01[Australia/Sydney]")
      true

      iex> Tempo.zoned?(~o"2024-01-01")
      false

  """
  @spec zoned?(t()) :: boolean()
  def zoned?(expression) when is_expression(expression), do: Parts.zoned?(expression)
  def zoned?(other), do: not_an_expression!(other)

  @doc """
  Whether every end an expression has is written: an interval with an open
  end is not bounded, nor a recurrence with no end, nor a set that has no
  last member (a selection over a span with no end).

  ### Arguments

  * `expression` is a `t:t/0` or a `t:Tempo.Duration.t/0`.

  ### Returns

  * `true` or `false`. A duration has no end to leave open and is bounded.

  ### Examples

      iex> Tempo.bounded?(~o"2026-06-15")
      true

      iex> Tempo.bounded?(~o"2026-01-15/..")
      false

      iex> Tempo.bounded?(~o"R/2026-01-15/P1D")
      false

      iex> {:ok, mondays} = Tempo.select(~o"2026-06-01/..", ~o"1K")
      iex> Tempo.bounded?(mondays)
      false

  """
  @spec bounded?(t() | Duration.t()) :: boolean()
  def bounded?(expression) when is_expression(expression), do: Parts.bounded?(expression)
  def bounded?(other), do: not_an_expression!(other)

  @doc """
  Whether an expression covers no time: a set with no members.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.empty?(~o"{}")
      true

      iex> Tempo.empty?(~o"2026-06-15")
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(expression) when is_expression(expression), do: Parts.empty?(expression)
  def empty?(other), do: not_an_expression!(other)

  @doc """
  The qualifications of a value: which of its units are uncertain (`?`),
  approximate (`~`) or both (`%`), as a map from unit to qualification.

  ### Arguments

  * `value` is a `t:t/0`.

  ### Returns

  * A map from unit to `:uncertain`, `:approximate` or `:both`; `nil` when
    the value has none.

  ### Examples

      iex> Tempo.qualification(~o"2026-06~-15")
      %{year: :approximate, month: :approximate}

      iex> Tempo.qualification(~o"2026-06-15")
      nil

  """
  @spec qualification(t()) :: qualifications()
  def qualification(%__MODULE__{qualifications: qualifications}), do: qualifications
  def qualification(other), do: not_an_expression!(other)

  @doc """
  The qualification of one unit of a value: whether it is uncertain (`?`),
  approximate (`~`) or both (`%`).

  ### Arguments

  * `value` is a `t:t/0`.

  * `unit` is a unit, such as `:year` or `:month`.

  ### Returns

  * `:uncertain`, `:approximate` or `:both`; `nil` when the unit is
    neither.

  ### Examples

      iex> Tempo.qualification(~o"2026-06~-15", :month)
      :approximate

      iex> Tempo.qualification(~o"2026-06~-15", :day)
      nil

  """
  @spec qualification(t(), unit()) :: :uncertain | :approximate | :both | nil
  def qualification(%__MODULE__{qualifications: nil}, _unit), do: nil

  def qualification(%__MODULE__{qualifications: qualifications}, unit),
    do: Map.get(qualifications, unit)

  def qualification(other, _unit), do: not_an_expression!(other)

  @doc """
  The metadata an expression carries: a map, empty by default.

  ### Arguments

  * `expression` is a `t:t/0`.

  ### Returns

  * The metadata, a map.

  ### Examples

      iex> Tempo.metadata(~o"2026-06-15")
      %{}

      iex> ~o"2026-06-15" |> Tempo.put_metadata(%{room: "A"}) |> Tempo.metadata()
      %{room: "A"}

  """
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{metadata: metadata}), do: metadata
  def metadata(other), do: not_an_expression!(other)

  @doc """
  An expression with metadata merged into what it carries.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `metadata` is a map.

  ### Returns

  * The expression with the metadata merged in, a key given replacing
    the one it carried.

  ### Examples

      iex> ~o"2026-06-15" |> Tempo.put_metadata(%{room: "A"}) |> Tempo.put_metadata(%{owner: "Ann"}) |> Tempo.metadata()
      %{room: "A", owner: "Ann"}

  """
  @spec put_metadata(t(), map()) :: t()
  def put_metadata(%__MODULE__{metadata: existing} = expression, metadata) when is_map(metadata),
    do: %{expression | metadata: Map.merge(existing, metadata)}

  def put_metadata(%__MODULE__{}, metadata),
    do: raise(ArgumentError, "metadata is a map, not #{inspect(metadata)}")

  def put_metadata(other, _metadata), do: not_an_expression!(other)

  # ── Selection ─────────────────────────────────────────────────────────

  @doc """
  The values a selector picks in each span of an expression: the Fridays of
  June, Christmas Day in each year of a span, half past ten in a working
  day, a territory's workdays in a term.

  ### Arguments

  * `base` is a `t:t/0` with spans: a value, an interval, a set, a bounded
    recurrence. Each span is a period the selector is applied in.

  * `selector` is one of: a `t:t/0` with no year, whose units are the parts
    selected (`~o"12M25D"`, `~o"5K"`, `~o"T02"`, `~o"L1K1IN"`); a span with
    no year, placed in each period it begins in (`~o"T22/T02"`); a
    recurrence, whose occurrences within each period are selected; a
    `t:Tempo.Workdays.t/0` from `workdays/2`, or `weekends/1`; a list or a
    range of integers, the days of the month; a list of selectors, each
    applied; or a function given each period that answers with a selector
    for it, or `{:error, reason}`.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:t/0`, the window a base with no end of its own or no
    year is placed in.

  * `:locale` is the locale whose working week a selector that rolls a day
    to a weekday keeps to; the default is the territory in force.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form holding the values picked in
    order, each with its period's metadata.

  * `{:error, %ArgumentError{}}` for a selector of no recognised shape, and
    `{:error, exception}` when the base has no spans or an open start.

  ### Examples

      iex> {:ok, days} = Tempo.select(~o"2026-02", [1, 15])
      iex> Tempo.IntervalSet.map(days, &Tempo.day/1)
      [1, 15]

      iex> {:ok, fridays} = Tempo.select(~o"2026-06", ~o"5K")
      iex> Tempo.IntervalSet.map(fridays, &Tempo.day/1)
      [5, 12, 19, 26]

      iex> {:ok, christmases} = Tempo.select(~o"2026/2028", ~o"12M25D")
      iex> Tempo.IntervalSet.map(christmases, &Tempo.year/1)
      [2026, 2027, 2028]

      iex> {:ok, first_monday} = Tempo.select(~o"2026-06", ~o"L1K1IN")
      iex> Tempo.IntervalSet.members(first_monday)
      [~o"2026-06-01"]

      iex> {:ok, workdays} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      iex> Tempo.IntervalSet.count(workdays)
      20

      iex> clocks_go_forward = ~o"2024-03-10[America/New_York]"
      iex> {:ok, skipped} = Tempo.select(clocks_go_forward, ~o"T02")
      iex> Tempo.IntervalSet.count(skipped)
      0

  """
  @spec select(t(), term(), keyword()) :: {:ok, t()} | {:error, error()}
  def select(base, selector, options \\ [])

  def select(base, _selector, _options) when not is_struct(base, __MODULE__),
    do: not_an_expression(base)

  def select(base, selector, options) do
    with :ok <- Options.check(options, [:within, :locale], "Tempo.select/3"),
         {:ok, selector} <- selector(selector),
         {:ok, values} <- Select.select(base, selector, options) do
      {:ok, set_of(values, base)}
    end
  end

  # A selector may be given as the `{:ok, _}` that `workdays/2` and `weekends/1` return.
  defp selector({:ok, selector}), do: {:ok, selector}
  defp selector({:error, _} = error), do: error
  defp selector(selector), do: {:ok, selector}

  @doc """
  `select/3`, returning the set or raising.

  ### Arguments

  * The arguments are those of `select/3`.

  ### Returns

  * What `select/3` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> ~o"2026-06" |> Tempo.select!(~o"5K") |> Tempo.IntervalSet.count()
      4

  """
  @spec select!(t(), term(), keyword()) :: t()
  def select!(base, selector, options \\ []) do
    case select(base, selector, options) do
      {:ok, set} -> set
      {:error, exception} -> raise exception
    end
  end

  # ── Workdays ──────────────────────────────────────────────────────────

  @doc """
  The workdays of a territory, less any days off: a selector for `select/3`
  and the calendar the workday functions step through.

  ### Arguments

  * `territory` is a territory code (`:US`, `:SA`, `:IN`), whose weekdays
    and weekend come from CLDR through Localize; `nil` is the configured
    `:default_territory`, or the world's when none is configured.

  * `options` is a keyword list of options.

  ### Options

  * `:except` is a `t:t/0` with spans, the days off: a set of dates, a
    recurrence, a holiday set.

  ### Returns

  * `{:ok, %Tempo.Workdays{}}`.

  * `{:error, %ArgumentError{}}` for a territory Localize does not know, an
    option this function does not take, or days off that are not a `t:t/0`.

  ### Examples

      iex> {:ok, workdays} = Tempo.workdays(:SA)
      iex> workdays.weekend
      [5, 6]

      iex> {:ok, school_days} = Tempo.workdays(:AU, except: ~o"{2026-01-26,2026-04-25}")
      iex> Tempo.count_workdays(~o"2026-01-19/2026-02-01", school_days)
      {:ok, 9}

  """
  @spec workdays(term(), keyword()) :: {:ok, Workdays.t()} | {:error, error()}
  def workdays(territory \\ nil, options \\ []), do: Workdays.new(territory, options)

  @doc """
  `workdays/2`, returning the workdays or raising: for a territory written
  in the code, as in a module attribute.

  ### Arguments

  * The arguments are those of `workdays/2`.

  ### Returns

  * What `workdays/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> saudi_arabia = Tempo.workdays!(:SA)
      iex> Tempo.workday?(~o"2026-06-19", saudi_arabia)
      false

      iex> observed = Tempo.workdays!(:US, except: ~o"2026-07-03")
      iex> Tempo.workday?(~o"2026-07-03", observed)
      false

  """
  @spec workdays!(term(), keyword()) :: Workdays.t()
  def workdays!(territory \\ nil, options \\ []) do
    case workdays(territory, options) do
      {:ok, workdays} -> workdays
      {:error, exception} -> raise exception
    end
  end

  @doc """
  The weekend of a territory as a selector: the days of the week its
  weekend falls on.

  ### Arguments

  * `territory` is a territory code or `nil`, as for `workdays/2`.

  ### Returns

  * `{:ok, selector}`, a `t:t/0` naming the days of the week.

  * `{:error, exception}` for a territory Localize does not know.

  ### Examples

      iex> {:ok, weekends} = Tempo.weekends(:US)
      iex> {:ok, days} = Tempo.select(~o"2026-06-15/2026-06-21", weekends)
      iex> Tempo.IntervalSet.map(days, &Tempo.day/1)
      [20, 21]

  """
  @spec weekends(term()) :: {:ok, t()} | {:error, error()}
  def weekends(territory \\ nil) do
    with {:ok, %Workdays{weekend: weekend}} <- Workdays.new(territory),
         do: {:ok, %__MODULE__{form: {:value, [day_of_week: weekend]}}}
  end

  for {name, phrase} <- [
        {:workday?, "falls on a workday of a territory: a weekday that is not a day off"},
        {:weekend?, "falls on the weekend of a territory"}
      ] do
    @doc """
    Whether a value, a day or finer, #{phrase}.

    ### Arguments

    * `value` is a `t:t/0` within one day.

    * `territory` is a territory code, a `t:Tempo.Workdays.t/0` or `nil`,
      as for `workdays/2`.

    ### Returns

    * `true` or `false`, or `{:error, exception}` for a value that names
      several days or a territory Localize does not know.

    ### Examples

        iex> Tempo.#{name}(~o"2026-06-13", :US)
        #{name == :weekend?}

        iex> Tempo.#{name}(~o"2026-06-15", :US)
        #{name == :workday?}

    """
    @spec unquote(name)(t(), term()) :: boolean() | {:error, error()}
    def unquote(name)(value, territory \\ nil)

    def unquote(name)(value, territory) when is_expression(value) do
      with {:ok, workdays} <- Workdays.new(territory),
           do: Workdays.unquote(name)(value, workdays)
    end

    def unquote(name)(other, _territory), do: not_an_expression(other)
  end

  @doc """
  A value moved by a number of workdays, forward for a positive count and
  back for a negative one, stepping over the weekend and the days off.

  ### Arguments

  * `value` is a `t:t/0` within one day.

  * `count` is the number of workdays to move, an integer.

  * `territory` is a territory code, a `t:Tempo.Workdays.t/0` or `nil`,
    as for `workdays/2`.

  ### Returns

  * `{:ok, workday}`, a `t:t/0`.

  * `{:error, %Tempo.ConversionError{reason: :open}}` when the days off
    never end in the direction moved, and `{:error, exception}` for a value
    that names several days or a territory Localize does not know.

  ### Examples

      iex> Tempo.add_workdays(~o"2026-06-12", 3, :US)
      {:ok, ~o"2026-06-17"}

      iex> Tempo.add_workdays(~o"2026-06-15", -1, :US)
      {:ok, ~o"2026-06-12"}

  """
  @spec add_workdays(t(), integer(), term()) ::
          {:ok, t()} | {:error, error()}
  def add_workdays(value, count, territory \\ nil)

  def add_workdays(value, count, territory) when is_expression(value) do
    with {:ok, workdays} <- Workdays.new(territory), do: Workdays.add(value, count, workdays)
  end

  def add_workdays(other, _count, _territory), do: not_an_expression(other)

  @doc """
  The first workday after a value.

  ### Arguments

  * `value` is a `t:t/0` within one day.

  * `territory` is a territory code, a `t:Tempo.Workdays.t/0` or `nil`,
    as for `workdays/2`.

  ### Returns

  * `{:ok, workday}`, a `t:t/0`.

  * `{:error, %Tempo.ConversionError{reason: :open}}` when the days off
    never end after the value, and `{:error, exception}` for a value
    that names several days or a territory Localize does not know.

  ### Examples

      iex> Tempo.next_workday(~o"2026-06-12", :US)
      {:ok, ~o"2026-06-15"}

  """
  @spec next_workday(t(), term()) :: {:ok, t()} | {:error, error()}
  def next_workday(value, territory \\ nil)

  def next_workday(value, territory) when is_expression(value) do
    with {:ok, workdays} <- Workdays.new(territory), do: Workdays.step(value, 1, workdays)
  end

  def next_workday(other, _territory), do: not_an_expression(other)

  @doc """
  The last workday before a value.

  ### Arguments

  * `value` is a `t:t/0` within one day.

  * `territory` is a territory code, a `t:Tempo.Workdays.t/0` or `nil`,
    as for `workdays/2`.

  ### Returns

  * `{:ok, workday}`, a `t:t/0`.

  * `{:error, %Tempo.ConversionError{reason: :open}}` when the days off
    never end before the value, and `{:error, exception}` for a value
    that names several days or a territory Localize does not know.

  ### Examples

      iex> Tempo.previous_workday(~o"2026-06-15", :US)
      {:ok, ~o"2026-06-12"}

  """
  @spec previous_workday(t(), term()) :: {:ok, t()} | {:error, error()}
  def previous_workday(value, territory \\ nil)

  def previous_workday(value, territory) when is_expression(value) do
    with {:ok, workdays} <- Workdays.new(territory), do: Workdays.step(value, -1, workdays)
  end

  def previous_workday(other, _territory), do: not_an_expression(other)

  @doc """
  The nearest workday to a value: the value itself when it is one, else the
  closer of the next and the previous, the next on a tie.

  ### Arguments

  * `value` is a `t:t/0` within one day.

  * `territory` is a territory code, a `t:Tempo.Workdays.t/0` or `nil`,
    as for `workdays/2`.

  ### Returns

  * `{:ok, workday}`, a `t:t/0`.

  * `{:error, %Tempo.ConversionError{reason: :open}}` when the days off
    never end either way from the value, and `{:error, exception}` for a value
    that names several days or a territory Localize does not know.

  ### Examples

      iex> Tempo.nearest_workday(~o"2026-06-13", :US)
      {:ok, ~o"2026-06-12"}

      iex> Tempo.nearest_workday(~o"2026-06-14", :US)
      {:ok, ~o"2026-06-15"}

  """
  @spec nearest_workday(t(), term()) :: {:ok, t()} | {:error, error()}
  def nearest_workday(value, territory \\ nil)

  def nearest_workday(value, territory) when is_expression(value) do
    with {:ok, workdays} <- Workdays.new(territory), do: Workdays.nearest(value, workdays)
  end

  def nearest_workday(other, _territory), do: not_an_expression(other)

  @doc """
  A value rolled to a workday by a business day convention: itself when it
  is a workday, else the workday the convention names.

  ### Arguments

  * `value` is a `t:t/0` within one day.

  * `territory` is as for `workdays/2`.

  * `options` is a keyword list of options.

  ### Options

  * `:roll` is `:following` (the default), `:preceding`, `:nearest` (the
    closer of the two, the one after on a tie), or one of
    `:modified_following`, `:modified_preceding` and `:modified_nearest`;
    the modified conventions turn back when the roll would leave the month.

  ### Returns

  * `{:ok, workday}`, a `t:t/0`.

  * `{:error, %ArgumentError{}}` for a convention or an option this
    function does not take, `{:error, %Tempo.ConversionError{reason:
    :open}}` when the days off never end the way the value is rolled, and
    `{:error, exception}` for a value that names several days or a
    territory Localize does not know.

  ### Examples

      iex> Tempo.roll_to_workday(~o"2026-05-30", :US)
      {:ok, ~o"2026-06-01"}

      iex> Tempo.roll_to_workday(~o"2026-05-30", :US, roll: :modified_following)
      {:ok, ~o"2026-05-29"}

      iex> Tempo.roll_to_workday(~o"2026-11-01", :US, roll: :modified_preceding)
      {:ok, ~o"2026-11-02"}

  """
  @spec roll_to_workday(t(), term(), keyword()) ::
          {:ok, t()} | {:error, error()}
  def roll_to_workday(value, territory \\ nil, options \\ []) do
    with :ok <- Options.check(options, [:roll], "Tempo.roll_to_workday/3"),
         {:ok, workdays} <- Workdays.new(territory),
         do: Workdays.roll(value, workdays, Keyword.get(options, :roll, :following))
  end

  @doc """
  How many workdays an expression's days hold.

  ### Arguments

  * `expression` is a `t:t/0` with an end: a value, an interval, a set.

  * `territory` is a territory code, a `t:Tempo.Workdays.t/0` or `nil`,
    as for `workdays/2`.

  ### Returns

  * `{:ok, count}`, a non-negative integer.

  * `{:error, %Tempo.ConversionError{reason: :unbounded}}` for an
    expression with no end, and `{:error, exception}` for a territory
    Localize does not know.

  ### Examples

      iex> Tempo.count_workdays(~o"2026-06", :US)
      {:ok, 22}

  """
  @spec count_workdays(t(), term()) ::
          {:ok, non_neg_integer()} | {:error, error()}
  def count_workdays(expression, territory \\ nil)

  def count_workdays(expression, territory) when is_expression(expression) do
    with {:ok, workdays} <- Workdays.new(territory), do: Workdays.count(expression, workdays)
  end

  def count_workdays(other, _territory), do: not_an_expression(other)

  # ── Elixir's dates and times ──────────────────────────────────────────

  @doc """
  A Tempo value from one of Elixir's date and time structs.

  A `Date` is a day, a `Time` a second, a `NaiveDateTime` a floating
  second, a `DateTime` a second in its zone (UTC as `Z`), each in the
  struct's calendar; a `Date.Range` is the span of its days; an Elixir
  `Duration` a `t:Tempo.Duration.t/0`.

  ### Arguments

  * `value` is a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0`,
    `t:DateTime.t/0`, `t:Date.Range.t/0` or `t:Duration.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:resolution` is a unit the value is written at, as `at_resolution/2`
    writes it.

  ### Returns

  * `{:ok, value}`.

  * `{:error, %Tempo.ConversionError{}}` for anything else, and for a
    stepped or descending range.

  ### Examples

      iex> Tempo.from_elixir(~D[2022-06-15])
      {:ok, ~o"2022-06-15"}

      iex> Tempo.from_elixir(~N[2022-06-15 10:30:00])
      {:ok, ~o"2022-06-15T10:30:00"}

      iex> Tempo.from_elixir(~U[2022-06-15 10:30:00Z])
      {:ok, ~o"2022-06-15T10:30:00Z"}

      iex> Tempo.from_elixir(Date.range(~D[2026-07-01], ~D[2026-07-31]))
      {:ok, ~o"2026-07-01/2026-07-31"}

      iex> Tempo.from_elixir(~N[2022-06-15 10:30:00], resolution: :day)
      {:ok, ~o"2022-06-15"}

  """
  @spec from_elixir(term(), keyword()) :: {:ok, t() | Duration.t()} | {:error, error()}
  def from_elixir(value, options \\ []) do
    with :ok <- Options.check(options, [:resolution], "Tempo.from_elixir/2"),
         do: Interop.from(value, options)
  end

  @doc """
  `from_elixir/2`, returning the value or raising.

  ### Arguments

  * The arguments are those of `from_elixir/2`.

  ### Returns

  * What `from_elixir/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.from_elixir!(~T[10:30:00])
      ~o"T10:30:00"

  """
  @spec from_elixir!(term(), keyword()) :: t() | Duration.t()
  def from_elixir!(value, options \\ []) do
    case from_elixir(value, options) do
      {:ok, tempo} -> tempo
      {:error, exception} -> raise exception
    end
  end

  for {name, struct, example, answer} <- [
        {:from_date, Date, "~D[2022-06-15]", ~s(~o"2022-06-15")},
        {:from_time, Time, "~T[10:30:00]", ~s(~o"T10:30:00")},
        {:from_naive_datetime, NaiveDateTime, "~N[2022-06-15 10:30:00]",
         ~s(~o"2022-06-15T10:30:00")},
        {:from_datetime, DateTime, "~U[2022-06-15 10:30:00Z]", ~s(~o"2022-06-15T10:30:00Z")}
      ] do
    @doc """
    A Tempo value from a `#{inspect(struct)}`, as `from_elixir/2` reads one.

    ### Arguments

    * `value` is a `t:#{inspect(struct)}.t/0`.

    ### Returns

    * The value, a `t:t/0`. Anything but a `#{inspect(struct)}` raises a
      `Tempo.ConversionError`.

    ### Examples

        iex> Tempo.#{name}(#{example})
        #{answer}

    """
    @spec unquote(name)(unquote(struct).t()) :: t()
    def unquote(name)(%unquote(struct){} = value), do: from_elixir!(value)

    def unquote(name)(other),
      do: raise(ConversionError.exception(value: other, reason: :not_an_elixir_value))
  end

  @doc """
  The Elixir struct a value fills: a `Date` for a day, a `Time` for a time
  of day, a `NaiveDateTime` for a floating date and time, a `DateTime` for
  one with a zone or a shift, and an Elixir `Duration` for a duration. An
  interval of two dates is the `Date.Range` of them, which holds its last
  day as the interval does; one with a duration for an end is the range of
  the dates it runs between.

  ### Arguments

  * `value` is a `t:t/0` or a `t:Tempo.Duration.t/0`.

  ### Returns

  * `{:ok, struct}`, or `{:ok, range}` with a `t:Date.Range.t/0` for an
    interval of two dates.

  * `{:error, %Tempo.ConversionError{}}` for a value coarser than a day, a
    value that names several, an interval whose ends are not both dates, or
    any other expression.

  ### Examples

      iex> Tempo.to_elixir(~o"2026-06-15")
      {:ok, ~D[2026-06-15]}

      iex> Tempo.to_elixir(~o"2026-06-15T10:30")
      {:ok, ~N[2026-06-15 10:30:00]}

      iex> Tempo.to_elixir(~o"2026-06-15T10:30:00Z")
      {:ok, ~U[2026-06-15 10:30:00Z]}

      iex> Tempo.to_elixir(~o"PT8H")
      {:ok, Duration.new!(hour: 8)}

      iex> Tempo.to_elixir(~o"2026-06-15/2026-06-20")
      {:ok, Date.range(~D[2026-06-15], ~D[2026-06-20])}

      iex> Tempo.to_elixir(~o"2026-06-15/P6D")
      {:ok, Date.range(~D[2026-06-15], ~D[2026-06-20])}

      iex> {:error, %Tempo.ConversionError{}} = Tempo.to_elixir(~o"2026-06")

  """
  @spec to_elixir(t() | Duration.t()) :: {:ok, struct()} | {:error, error()}
  # A span with a duration for an end is the span of its two ends first.
  def to_elixir(%__MODULE__{form: {:span, from, to}} = span)
      when is_struct(from, Duration) or is_struct(to, Duration) do
    with {:ok, resolved} <- to_interval(span), do: Interop.to(resolved)
  end

  def to_elixir(value), do: Interop.to(value)

  @doc """
  The `Date` of a value written to the day or finer, on any axis.

  ### Arguments

  * `value` is a `t:t/0`.

  ### Returns

  * `{:ok, date}`, a `t:Date.t/0`.

  * `{:error, %Tempo.ConversionError{}}` for a value coarser than a day, a
    value with no date, or any other expression.

  ### Examples

      iex> Tempo.to_date(~o"2026-06-15T10:30")
      {:ok, ~D[2026-06-15]}

      iex> Tempo.to_date(~o"2026-W25-3")
      {:ok, ~D[2026-06-17]}

  """
  @spec to_date(t()) :: {:ok, Date.t()} | {:error, error()}
  def to_date(value) when is_expression(value), do: Interop.to_date(value)
  def to_date(other), do: not_an_expression(other)

  @doc """
  The `Time` of a value with a time of day; units it does not write are zero.

  ### Arguments

  * `value` is a `t:t/0`.

  ### Returns

  * `{:ok, time}`, a `t:Time.t/0`.

  * `{:error, %Tempo.ConversionError{}}` for a value with no time of day,
    or any other expression.

  ### Examples

      iex> Tempo.to_time(~o"2026-06-15T10:30")
      {:ok, ~T[10:30:00]}

  """
  @spec to_time(t()) :: {:ok, Time.t()} | {:error, error()}
  def to_time(value) when is_expression(value), do: Interop.to_time(value)
  def to_time(other), do: not_an_expression(other)

  @doc """
  The `NaiveDateTime` of a value written to the day or finer; units it does
  not write are zero, and a zone is dropped.

  ### Arguments

  * `value` is a `t:t/0`.

  ### Returns

  * `{:ok, datetime}`, a `t:NaiveDateTime.t/0`.

  * `{:error, %Tempo.ConversionError{}}` for a value coarser than a day, a
    value with no date, or any other expression.

  ### Examples

      iex> Tempo.to_naive_datetime(~o"2026-06-15")
      {:ok, ~N[2026-06-15 00:00:00]}

  """
  @spec to_naive_datetime(t()) :: {:ok, NaiveDateTime.t()} | {:error, error()}
  def to_naive_datetime(value) when is_expression(value), do: Interop.to_naive(value)
  def to_naive_datetime(other), do: not_an_expression(other)

  @doc """
  The `DateTime` of a value with a zone or a time shift.

  ### Arguments

  * `value` is a `t:t/0`.

  ### Returns

  * `{:ok, datetime}`, in the value's zone, or in UTC for a shift.

  * `{:error, %Tempo.ConversionError{reason: :floating}}` for a value with
    neither.

  ### Examples

      iex> {:ok, paris} = Tempo.to_datetime(~o"2026-06-15T10:30[Europe/Paris]")
      iex> {paris.time_zone, paris.hour}
      {"Europe/Paris", 10}

      iex> {:error, %Tempo.ConversionError{reason: :floating}} = Tempo.to_datetime(~o"2026-06-15T10:30")

  """
  @spec to_datetime(t()) :: {:ok, DateTime.t()} | {:error, error()}
  def to_datetime(value) when is_expression(value), do: Interop.to_datetime(value)
  def to_datetime(other), do: not_an_expression(other)

  # ── Now ───────────────────────────────────────────────────────────────

  @doc """
  The current second in a zone, from the configured `Tempo.Clock`.

  ### Arguments

  * `zone` is an IANA zone name; the default is `"Etc/UTC"`.

  ### Returns

  * `{:ok, value}`, a `t:t/0` at second resolution in the zone.

  * `{:error, %Tempo.ZoneError{}}` for a zone the database does not know.

  ### Examples

      iex> {:ok, now} = Tempo.now("Europe/London")
      iex> Tempo.resolution(now)
      :second

      iex> {:error, %Tempo.ZoneError{}} = Tempo.now("Continent/Imaginary")

  """
  @spec now(String.t()) :: {:ok, t()} | {:error, error()}
  def now(zone \\ "Etc/UTC")
  def now(zone) when is_binary(zone), do: Interop.now(zone)
  def now(other), do: not_a_zone(other)

  @doc """
  The current second in UTC.

  ### Returns

  * The current second, a `t:t/0` in `Etc/UTC`.

  ### Examples

      iex> Tempo.zoned?(Tempo.utc_now())
      true

  """
  @spec utc_now() :: t()
  def utc_now do
    {:ok, now} = now("Etc/UTC")
    now
  end

  @doc """
  Today's date in a zone: a floating day.

  ### Arguments

  * `zone` is an IANA zone name; the default is `"Etc/UTC"`.

  ### Returns

  * `{:ok, value}`, a `t:t/0` at day resolution with no zone.

  * `{:error, %Tempo.ZoneError{}}` for a zone the database does not know.

  ### Examples

      iex> {:ok, today} = Tempo.today("Australia/Sydney")
      iex> Tempo.resolution(today)
      :day

  """
  @spec today(String.t()) :: {:ok, t()} | {:error, error()}
  def today(zone \\ "Etc/UTC") do
    with {:ok, now} <- now(zone),
         {:ok, day} <- trunc(now, :day),
         do: {:ok, %{day | zone: nil, shift: nil}}
  end

  @doc """
  Today's date in UTC.

  ### Returns

  * Today's date in UTC, a `t:t/0` at day resolution with no zone.

  ### Examples

      iex> Tempo.floating?(Tempo.utc_today())
      true

  """
  @spec utc_today() :: t()
  def utc_today do
    {:ok, today} = today("Etc/UTC")
    today
  end

  # ── Words ─────────────────────────────────────────────────────────────

  @doc """
  A locale's words for an expression, through Localize and CLDR.

  An expression is shown as the time it covers. A value written to the day
  is that day, one written coarser runs from the first to the last of the
  next unit down (a year its months, a month or a week its days), and one
  written to a clock unit is its date and time. An interval runs from its
  first end to its last as the finer of the two is written. An expression
  of several spans is their list, and a one-of set its alternatives. A
  duration is its units. A year before 1 is shown with its era.

  ### Arguments

  * `expression` is a `t:t/0` or a `t:Tempo.Duration.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a CLDR locale; the default is Localize's.

  * `:format` is a CLDR format (`:short`, `:medium`, `:long`, `:full`) or a
    skeleton (`:yMMMd`).

  * `:within` is a `t:t/0`, the window an expression with no year or no end
    is placed in.

  * `:number_system` and `:prefer` are Localize's: the digits a number is
    written in, and which of a locale's variants of a format is taken.

  * `:except` is a list of the units a duration's words leave out.

  ### Returns

  * `{:ok, words}`.

  * `{:error, exception}`: a `Tempo.ConversionError` with reason `:open`
    for an interval with an open end and `:needs_a_year` for an expression
    with no year that the units alone cannot show, an `ArgumentError` for
    an option it does not take, or Localize's own error.

  ### Examples

      iex> Tempo.to_string(~o"2026-06-15")
      {:ok, "Jun 15, 2026"}

      iex> Tempo.to_string(~o"2026-06")
      {:ok, "Jun 1 –30, 2026" |> String.replace("–30", "– 30")}

      iex> Tempo.to_string(~o"2026-06-15", format: :long, locale: "fr")
      {:ok, "15 juin 2026"}

      iex> Tempo.to_string(~o"2026/2028")
      {:ok, "2026 – 2028"}

      iex> Tempo.to_string(~o"R3/2026-06-15/P1D")
      {:ok, "Jun 15, 2026, Jun 16, 2026, and Jun 17, 2026"}

      iex> Tempo.to_string(~o"[2026-06-15,2026-07-04]")
      {:ok, "Jun 15, 2026 or Jul 4, 2026"}

      iex> Tempo.to_string(~o"-0044-03-15")
      {:ok, "Mar 15, 45 BC"}

      iex> Tempo.to_string(~o"P1Y6M")
      {:ok, "1 year, 6 months"}

      iex> {:error, %Tempo.ConversionError{reason: :open}} = Tempo.to_string(~o"2026-06-15/..")

  """
  @spec to_string(t() | Duration.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def to_string(expression, options \\ []) do
    with :ok <- Options.check(options, @words_options, "Tempo.to_string/2"),
         do: Format.to_string(expression, options)
  end

  @doc """
  `to_string/2`, returning the words or raising.

  ### Arguments

  * The arguments are those of `to_string/2`.

  ### Returns

  * What `to_string/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.to_string!(~o"2026-06-15")
      "Jun 15, 2026"

  """
  @spec to_string!(t() | Duration.t(), keyword()) :: String.t()
  def to_string!(expression, options \\ []) do
    case to_string(expression, options) do
      {:ok, words} -> words
      {:error, exception} -> raise exception
    end
  end

  @doc """
  A locale's words for where an expression starts relative to another:
  yesterday, in 3 hours, next year.

  Where no unit is asked for, the difference is counted in the largest unit
  of which a whole one lies between the two starts, and never in one finer
  than the expression is written to: two minutes across midnight are two
  minutes, 1 February is tomorrow from 31 January, and the year a day is in
  is this year. A year, a quarter, a month, a week and a day are counted by
  the calendar's own on the expression's clock, and an hour, a minute and a
  second by those that pass.

  ### Arguments

  * `expression` is a `t:t/0` with a year.

  * `options` is a keyword list of options.

  ### Options

  * `:from` is the `t:t/0` the words are relative to; the default is
    `utc_now/0`.

  * `:unit` is the unit counted in: `:year`, `:quarter`, `:month`, `:week`,
    `:day`, `:hour`, `:minute` or `:second`.

  * `:format` is `:standard` (the default), `:short` or `:narrow`, and
    `:locale` a CLDR locale.

  * `:numeric` is `:auto` (the default), which takes a locale's word for a
    difference it has one for (yesterday, next year), or `:always`, which
    counts it (1 day ago, in 1 year).

  A `:from` of another calendar is brought to the expression's, so a Hebrew
  date is counted in Hebrew months and years from a Gregorian one.

  A floating expression, one with no zone, is counted from a zoned `:from`
  on that zone's clock, and a zoned one from a floating `:from` on its own:
  the day after the day a clock shows is tomorrow, whichever of the two the
  clock belongs to. This is the one place a floating value stands beside a
  zoned one.

  ### Returns

  * `{:ok, words}`.

  * `{:error, %Tempo.ConversionError{reason: :needs_a_year}}` when either
    has no year, and `:open` when the expression has no start.

  * `{:error, %ArgumentError{}}` for an option it does not take or a unit
    it does not count in.

  ### Examples

      iex> now = ~o"2026-06-15T12:00:00Z"
      iex> Tempo.to_relative_string(~o"2026-06-14T12:00:00Z", from: now)
      {:ok, "yesterday"}

      iex> now = ~o"2026-06-15T12:00:00Z"
      iex> Tempo.to_relative_string(~o"2026-06-15T15:00:00Z", from: now)
      {:ok, "in 3 hours"}

      iex> Tempo.to_relative_string(~o"2026-02-01", from: ~o"2026-01-31")
      {:ok, "tomorrow"}

      iex> Tempo.to_relative_string(~o"2026-02-01", from: ~o"2026-01-31", unit: :month)
      {:ok, "next month"}

      iex> Tempo.to_relative_string(~o"2026", from: ~o"2026-06-15")
      {:ok, "this year"}

      iex> Tempo.to_relative_string(~o"2026-06-16", from: ~o"2026-06-15T23:30[Europe/Paris]")
      {:ok, "tomorrow"}

      iex> Tempo.to_relative_string(~o"2026-01-01T00:01", from: ~o"2025-12-31T23:59")
      {:ok, "in 2 minutes"}

      iex> {:error, %Tempo.ConversionError{reason: :needs_a_year}} = Tempo.to_relative_string(~o"T10:30", from: ~o"2026-06-15")

  """
  @spec to_relative_string(t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def to_relative_string(expression, options \\ []) do
    with :ok <- Options.check(options, @relative_options, "Tempo.to_relative_string/2"),
         :ok <- relative_unit(options[:unit]),
         {:ok, options} <- from_in_calendar(expression, options),
         do: Format.to_relative_string(expression, options)
  end

  defp relative_unit(unit) when unit in @relative_units, do: :ok

  defp relative_unit(unit) do
    counted = @relative_units |> Enum.reject(&is_nil/1) |> Enum.map_join(", ", &inspect/1)
    message = "Tempo.to_relative_string/2 does not count in #{inspect(unit)}: it counts in "
    {:error, ArgumentError.exception(message <> counted)}
  end

  # The reference is brought to the calendar of what is counted from it.
  defp from_in_calendar(%__MODULE__{calendar: calendar}, options) do
    case Keyword.fetch(options, :from) do
      {:ok, %__MODULE__{} = from} ->
        with {:ok, from} <- to_calendar(from, calendar),
             do: {:ok, Keyword.put(options, :from, from)}

      {:ok, other} ->
        {:error, ConversionError.exception(value: other, reason: :not_an_expression)}

      :error ->
        {:ok, options}
    end
  end

  defp from_in_calendar(_other, options), do: {:ok, options}

  @doc """
  A description of an expression in prose: what it is, the time it covers,
  the frame it is in, and what walking it gives.

  ### Arguments

  * `expression` is a `t:t/0` or a `t:Tempo.Duration.t/0`.

  ### Returns

  * A string of several lines; `Tempo.Explain.lines/1` gives them one by one.

  ### Examples

      iex> Tempo.explain(~o"2026-06-15") |> String.split("\\n") |> hd()
      "A value written to the day: Jun 15, 2026."

      iex> Tempo.explain(~o"1984/1986") |> String.split("\\n") |> Enum.take(2)
      ["An interval: 1984 – 1986.", "It covers 1984Y through 1986Y."]

  """
  @spec explain(term()) :: String.t()
  def explain(expression), do: expression |> Explain.lines() |> Enum.join("\n")

  # ── Mapping ───────────────────────────────────────────────────────────

  @doc """
  A function applied to each member of an enumerable of expressions, the
  results gathered into a set: `Enum.map/2` that answers a `t:t/0`.

  The function may answer a `t:t/0` or `{:ok, t}`, as the functions of
  this module do, so they map directly.

  ### Arguments

  * `enumerable` is an enumerable of `t:t/0`: a list, a set, a value walked.

  * `fun` is a function of one member.

  ### Returns

  * `{:ok, set}`, a `t:t/0` of the `:all` form holding the results in order.

  * `{:error, exception}`, the first error the function answers.

  * `{:error, %ArgumentError{}}` when `enumerable` is not enumerable or
    `fun` is not a function of one argument.

  ### Examples

      iex> independence_days = [~o"2025-07-04", ~o"2026-07-04", ~o"2027-07-04"]
      iex> {:ok, observed} = Tempo.try_map(independence_days, &Tempo.nearest_workday(&1, :US))
      iex> Tempo.IntervalSet.map(observed, &Tempo.day/1)
      [4, 3, 5]

      iex> {:error, %Tempo.ConversionError{}} = Tempo.try_map([~o"2026"], &Tempo.nearest_workday(&1, :US))

  """
  @spec try_map(Enumerable.t(), (t() -> t() | {:ok, t()} | {:error, error()})) ::
          {:ok, t()} | {:error, error()}
  def try_map(enumerable, fun) when is_function(fun, 1) do
    if Enumerable.impl_for(enumerable),
      do: mapping(enumerable, fun),
      else: {:error, not_enumerable(enumerable)}
  end

  def try_map(_enumerable, fun), do: {:error, not_a_function(fun)}

  defp mapping(enumerable, fun) do
    enumerable
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case fun.(member) do
        {:ok, %__MODULE__{} = result} ->
          {:cont, {:ok, [result | acc]}}

        %__MODULE__{} = result ->
          {:cont, {:ok, [result | acc]}}

        {:error, _} = error ->
          {:halt, error}

        other ->
          {:halt, {:error, ConversionError.exception(value: other, reason: :not_an_expression)}}
      end
    end)
    |> mapped()
  end

  defp not_enumerable(enumerable),
    do: ArgumentError.exception("an enumerable of expressions, not #{inspect(enumerable)}")

  defp not_a_function(fun),
    do: ArgumentError.exception("a function of one argument, not #{inspect(fun)}")

  defp mapped({:ok, []}), do: {:ok, %__MODULE__{form: {:all, []}}}

  defp mapped({:ok, reversed}) do
    [first | _] = results = Enum.reverse(reversed)
    {:ok, %__MODULE__{form: {:all, results}, calendar: first.calendar, zone: first.zone}}
  end

  defp mapped(error), do: error

  @doc """
  `try_map/2`, returning the set or raising.

  ### Arguments

  * The arguments are those of `try_map/2`.

  ### Returns

  * What `try_map/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> [~o"2025-07-04", ~o"2026-07-04"] |> Tempo.map(&Tempo.nearest_workday(&1, :US)) |> Tempo.IntervalSet.count()
      2

  """
  @spec map(Enumerable.t(), (t() -> t() | {:ok, t()} | {:error, error()})) :: t()
  def map(enumerable, fun) do
    case try_map(enumerable, fun) do
      {:ok, set} -> set
      {:error, exception} -> raise exception
    end
  end

  # ── Raising forms ─────────────────────────────────────────────────────

  for {name, argument_types, answer_type, example, answer} <- [
        {:at, [quote(do: t()), quote(do: t())], quote(do: t()),
         ~s|Tempo.at!(~o"2026-01-04", ~o"T10:30")|, ~s|~o"2026-01-04T10:30"|},
        {:on, [quote(do: t()), quote(do: t())], quote(do: t()),
         ~s|Tempo.on!(~o"T10:30", ~o"2026-01-04")|, ~s|~o"2026-01-04T10:30"|},
        {:shift, [quote(do: t()), quote(do: Duration.t() | keyword() | String.t())],
         quote(do: t()), ~s|Tempo.shift!(~o"2026-06-15", day: 1)|, ~s|~o"2026-06-16"|},
        {:trunc, [quote(do: t()), quote(do: unit())], quote(do: t()),
         ~s|Tempo.trunc!(~o"2026-06-15T10:30", :day)|, ~s|~o"2026-06-15"|},
        {:round, [quote(do: t()), quote(do: unit())], quote(do: t()),
         ~s|Tempo.round!(~o"2026-06-15T13:30", :day)|, ~s|~o"2026-06-16"|},
        {:extend, [quote(do: t())], quote(do: t()), ~s|Tempo.extend!(~o"2020")|,
         ~s|~o"2020Y{1..12}M"|},
        {:at_resolution, [quote(do: t()), quote(do: unit())], quote(do: t()),
         ~s|Tempo.at_resolution!(~o"2020", :day)|, ~s|~o"2020-01-01"|},
        {:to_calendar, [quote(do: t()), quote(do: module())], quote(do: t()),
         ~s|Tempo.to_calendar!(~o"2026-06-15", Calendrical.Hebrew)|,
         ~s|~o"5786Y9M30D[u-ca=hebrew]"|},
        {:duration, [quote(do: t()), quote(do: t())], quote(do: Duration.t()),
         ~s|Tempo.duration!(~o"2026-09-28", ~o"2026-11-03")|, ~s|~o"P36D"|},
        {:to_relative_string, [quote(do: t()), quote(do: keyword())], quote(do: String.t()),
         ~s|Tempo.to_relative_string!(~o"2027", from: ~o"2026-07-01")|, ~s|"next year"|},
        {:union, [quote(do: t()), quote(do: t())], quote(do: t()),
         ~s|Tempo.union!(~o"2026-01", ~o"2026-03") \|> Tempo.IntervalSet.count()|, "2"},
        {:intersection, [quote(do: t()), quote(do: t())], quote(do: t()),
         ~s|Tempo.intersection!(~o"2026-01/2026-03", ~o"2026-03/2026-05") \|> Tempo.IntervalSet.count()|,
         "1"},
        {:difference, [quote(do: t()), quote(do: t())], quote(do: t()),
         ~s|Tempo.difference!(~o"2026", ~o"2026-06") \|> Tempo.IntervalSet.count()|, "2"},
        {:weekends, [quote(do: term())], quote(do: t()), ~s|Tempo.weekends!(:US)|,
         ~s|~o"{6,7}K"|},
        {:selection, [quote(do: keyword())], quote(do: t()),
         ~s|Tempo.selection!(month: 12, day: 25)|, ~s|~o"L12M25DN"|},
        {:every, [quote(do: Duration.t() | keyword()), quote(do: keyword())], quote(do: t()),
         ~s|Tempo.every!(~o"P1W", from: ~o"2026-06-01", count: 3)|, ~s|~o"R3/2026-06-01/P1W"|},
        {:one_of, [quote(do: [t()])], quote(do: t()), ~s|Tempo.one_of!([~o"1984", ~o"1986"])|,
         ~s|~o"[1984,1986]"|}
      ] do
    bang = String.to_atom("#{name}!")
    arity = length(argument_types)
    arguments = Macro.generate_arguments(arity, __MODULE__)

    @doc """
    `#{name}/#{arity}`, returning its answer or raising the error.

    ### Arguments

    * The arguments are those of `#{name}/#{arity}`.

    ### Returns

    * What `#{name}/#{arity}` returns as `{:ok, answer}`, the answer alone.
      The error it returns as `{:error, exception}` is raised.

    ### Examples

        iex> #{example}
        #{answer}

    """
    @spec unquote(bang)(unquote_splicing(argument_types)) :: unquote(answer_type)
    def unquote(bang)(unquote_splicing(arguments)) do
      case unquote(name)(unquote_splicing(arguments)) do
        {:ok, answer} -> answer
        {:error, exception} -> raise exception
      end
    end
  end

  defp calendar_of(calendar) do
    if Tempo.Calendar.calendar?(calendar),
      do: {:ok, calendar},
      else: {:error, InvalidCalendarError.exception(calendar: calendar)}
  end

  defp zone_of(nil), do: {:ok, nil}
  defp zone_of(%Zone{} = zone), do: {:ok, zone}
  defp zone_of(name) when is_binary(name), do: Zone.named(name)

  defp zone_of(other),
    do: {:error, ZoneError.exception(zone: other, reason: :unknown)}
end
