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

  """

  alias Tempo.ConversionError
  alias Tempo.InvalidCalendarError
  alias Tempo.Limit
  alias Tempo.Reader
  alias Tempo.Spans
  alias Tempo.Unit
  alias Tempo.Validate
  alias Tempo.Writer
  alias Tempo.Zone
  alias Tempo.ZoneError

  @enforce_keys [:form]
  defstruct form: nil,
            calendar: Calendar.ISO,
            zone: nil,
            shift: nil,
            qualifications: nil,
            metadata: %{}

  @typedoc """
  What an expression is, as written.

  * `{:value, units}` — a written value, its units coarsest first, each with
    what it holds (`t:Tempo.Unit.held/0`).

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
          {:value, Unit.units()}
          | {:span, t() | Tempo.Duration.t() | :open, t() | Tempo.Duration.t() | :open}
          | {:every, t(), pos_integer() | :infinity | t(), Unit.selection() | nil}
          | {:all, [t()] | Enumerable.t()}
          | {:one, [t()]}
          | {:when, t(), [term()]}

  @typedoc """
  A mark that a component is uncertain (`?`), approximate (`~`) or both (`%`),
  held for each unit it qualifies.
  """
  @type qualifications :: %{optional(Unit.t()) => :uncertain | :approximate | :both} | nil

  @type t :: %__MODULE__{
          form: form(),
          calendar: module(),
          zone: Zone.t() | nil,
          shift: Zone.shift() | nil,
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

      iex> {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026-02-30")

      iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("tomorrow")

  """
  @spec from_iso8601(String.t(), module() | keyword()) ::
          {:ok, t() | Tempo.Duration.t()} | {:error, error()}
  def from_iso8601(text, calendar_or_options \\ [])

  def from_iso8601(text, calendar) when is_binary(text) and is_atom(calendar),
    do: Reader.read(text, calendar: calendar)

  def from_iso8601(text, options) when is_binary(text) and is_list(options),
    do: Reader.read(text, options)

  @doc """
  Reads a text as `from_iso8601/2` does, returning the expression or raising.

  ### Examples

      iex> Tempo.from_iso8601!("2026-06")
      ~o"2026-06"

  """
  @spec from_iso8601!(String.t(), module() | keyword()) :: t() | Tempo.Duration.t()
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
  @spec to_iso8601(t() | Tempo.Duration.t()) :: {:ok, String.t()} | {:error, error()}
  def to_iso8601(expression), do: Writer.to_iso8601(expression)

  @doc """
  Writes an expression as `to_iso8601/1` does, returning the text or raising.

  ### Examples

      iex> Tempo.to_iso8601!(~o"P1Y2M")
      "P1Y2M"

  """
  @spec to_iso8601!(t() | Tempo.Duration.t()) :: String.t()
  def to_iso8601!(expression) do
    case to_iso8601(expression) do
      {:ok, text} -> text
      {:error, exception} -> raise exception
    end
  end

  # ── Construction ──────────────────────────────────────────────────────

  @doc """
  Builds a value from its units.

  ### Arguments

  * `components` is a keyword list or a map of units (`:year`, `:month`,
    `:day`, `:week`, `:day_of_week`, `:day_of_year`, `:quarter`, `:season`,
    `:hour`, `:minute`, `:second`, `:microsecond`), in any order, each holding
    what a written unit holds (`t:Tempo.Unit.held/0`), with these keys beside
    them:

    * `:calendar` is the calendar the value is in. The default is
      `Calendar.ISO`.

    * `:zone` is the name of the value's time zone, as the database knows it.

    * `:shift` is the time shift, `[hour: 2]` for `Z2H`, `[hour: 0]` for `Z`.

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
    {frame, units} = Keyword.split(components, [:calendar, :zone, :shift, :metadata])

    with {:ok, units} <- Unit.ordered(units),
         {:ok, calendar} <- calendar_of(Keyword.get(frame, :calendar, Calendar.ISO)),
         {:ok, zone} <- zone_of(Keyword.get(frame, :zone)) do
      Validate.run(%__MODULE__{
        form: {:value, units},
        calendar: calendar,
        zone: zone,
        shift: Keyword.get(frame, :shift),
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

  @doc """
  Builds a value as `new/1` does, returning the value or raising.

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

  ### Returns

  * `{:ok, interval}`, a `t:t/0` of the `:span` form, or of the `:all` form
    for a plural expression.

  * `{:error, %Tempo.ConversionError{}}` for a duration, a one-of set, a
    recurrence with no count and no window, a value with no year and no
    window, or more members than `Tempo.Limit.values/0` allows at once.

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
      {:ok, ~o"{2026-01-31/2026-02-27,2026-02-28/2026-03-27,2026-03-31/2026-04-29}"}

      iex> Tempo.to_interval(~o"6M15D", within: ~o"2026")
      {:ok, ~o"2026-06-15/2026-06-15"}

      iex> {:error, %Tempo.ConversionError{reason: :bare_duration}} = Tempo.to_interval(~o"P1M")

      iex> {:error, %Tempo.ConversionError{reason: :unbounded}} = Tempo.to_interval(~o"R/2026-01-01/P1Y")

  """
  @spec to_interval(t() | Tempo.Duration.t(), keyword()) :: {:ok, t()} | {:error, error()}
  def to_interval(expression, options \\ [])

  def to_interval(%Tempo.Duration{} = duration, _options),
    do: {:error, ConversionError.exception(value: duration, reason: :bare_duration)}

  def to_interval(%__MODULE__{form: {:every, _, :infinity, _}} = recurrence, options) do
    if Keyword.has_key?(options, :within),
      do: plural_interval(recurrence, options),
      else: {:error, ConversionError.exception(value: recurrence, reason: :unbounded)}
  end

  def to_interval(%__MODULE__{} = expression, options) do
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

  # At most `Tempo.Limit.values/0` of a sequence, or the error that says there are more.
  defp bounded(enumerable, expression) do
    limit = Limit.values()

    case Enum.take(enumerable, limit + 1) do
      taken when length(taken) > limit ->
        {:error, ConversionError.exception(value: expression, reason: :too_many_values)}

      taken ->
        {:ok, taken}
    end
  end

  defp set_of(spans, expression),
    do: %__MODULE__{
      form: {:all, spans},
      calendar: expression.calendar,
      zone: expression.zone,
      metadata: expression.metadata
    }

  @doc """
  The members of an expression (law 6): the values a value with a set, a
  mask or a group in a unit allows; the members of a set; the occurrences
  of a recurrence; a singular expression itself.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `options` is a keyword list; `:within` as for `to_interval/2`.

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
  @spec members(t() | Tempo.Duration.t(), keyword()) :: {:ok, [t()]} | {:error, error()}
  def members(expression, options \\ []) do
    with {:ok, members} <- Spans.members(expression, options), do: bounded(members, expression)
  end

  @doc """
  An expression walked at a unit: the values of that unit its extent holds,
  lazily and in order, half-open. A calendar unit steps on the day scale
  through the calendar's periods; a clock unit on the tick scale, each tick
  shown as a wall reading of the zone, so a day across a change of the clock
  has 23 or 25 hours. A plural expression is each member walked in turn.

  ### Arguments

  * `expression` is a `t:t/0`.

  * `unit` is a unit of `Tempo.Unit`: `:year`, `:month`, `:week`, `:day`,
    `:hour`, `:minute`, `:second`, or `{:microsecond, precision}` for a part
    of a second.

  * `options` is a keyword list; `:within` as for `to_interval/2`.

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
  @spec walk(t(), Tempo.Unit.t() | {:microsecond, 1..6}, keyword()) ::
          {:ok, Enumerable.t()} | {:error, error()}
  def walk(expression, unit, options \\ []), do: Spans.walk(expression, unit, options)

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
