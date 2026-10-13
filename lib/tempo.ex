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

  alias Tempo.InvalidCalendarError
  alias Tempo.Reader
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
