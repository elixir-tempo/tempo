defmodule Tempo.Duration do
  @moduledoc """
  A length of time with no place on the time line: `P1Y2M3DT4H5M6S`.

  A duration is the one companion of `Tempo`: it is not an expression and
  denotes no span, and it is what an interval is formed from once it is
  given a start (`2026-06-01/P1M`) and what a value is shifted by
  (`Tempo.shift`).

  `new/1` builds one from its units and `Tempo.duration/2` measures the
  length of an expression. `add/2`, `subtract/2`, `sum/1`, `multiply/2` and
  `negate/1` are its arithmetic; `compare/3` orders two, and `Tempo`'s
  `at_least?/2`, `at_most?/2` and `exactly?/2` say how they compare.
  `to_unit/3` and `to_microseconds/1` count one in a unit, and `exact?/1`
  says whether it has a length without a place to begin, which a duration
  of years or months does not.

  """

  alias Tempo.ConversionError
  alias Tempo.InvalidCalendarError
  alias Tempo.Options
  alias Tempo.Scale
  alias Tempo.Spans

  @units [:year, :month, :week, :day, :hour, :minute, :second, :microsecond]
  @day 86_400_000_000

  defstruct units: []

  @typedoc """
  The units of a duration, coarsest first, each a whole number, negative
  for a length in the reverse direction; a part of a second is
  `{microseconds, precision}` as Elixir's types hold one.
  """
  @type units :: [
          {:year | :month | :week | :day | :hour | :minute | :second, integer()}
          | {:microsecond, {integer(), 0..6}}
        ]

  @type t :: %__MODULE__{units: units()}

  @doc """
  The units a duration is written in, coarsest first.

  ### Returns

  * The list of unit atoms, from `:year` to `:microsecond`.

  ### Examples

      iex> Tempo.Duration.units()
      [:year, :month, :week, :day, :hour, :minute, :second, :microsecond]

  """
  @spec units() :: [:year | :month | :week | :day | :hour | :minute | :second | :microsecond, ...]
  def units, do: @units

  @doc """
  Builds a duration from its units.

  ### Arguments

  * `components` is a keyword list of units (`:year`, `:month`, `:week`,
    `:day`, `:hour`, `:minute`, `:second`, `:microsecond`), in any order,
    each a whole number, negative for a length in the reverse direction; a
    `:microsecond` is `{microseconds, precision}`.

  ### Returns

  * `{:ok, duration}`, a `t:t/0` with its units ordered coarsest first.

  * `{:error, %ArgumentError{}}` when a key is not a unit of a duration, is
    given twice, or holds what is not a whole number.

  ### Examples

      iex> Tempo.Duration.new(month: 6, year: 1)
      {:ok, ~o"P1Y6M"}

      iex> Tempo.Duration.new(hour: 1, minute: 30)
      {:ok, ~o"PT1H30M"}

      iex> {:error, %ArgumentError{}} = Tempo.Duration.new(fortnight: 1)

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(components) when is_list(components) do
    keys = Keyword.keys(components)

    cond do
      Enum.any?(keys, &(&1 not in @units)) ->
        {:error,
         argument("#{inspect(Enum.reject(keys, &(&1 in @units)))} are not units of a duration")}

      keys != Enum.uniq(keys) ->
        {:error,
         argument("a unit is given once; #{inspect(keys -- Enum.uniq(keys))} are given twice")}

      not Enum.all?(components, &whole?/1) ->
        {:error,
         argument(
           "a duration's units hold whole numbers, and a microsecond {microseconds, precision}"
         )}

      true ->
        {:ok,
         %__MODULE__{
           units:
             Enum.sort_by(components, fn {unit, _} -> Enum.find_index(@units, &(&1 == unit)) end)
         }}
    end
  end

  def new(other),
    do:
      {:error,
       argument("a duration is built from a keyword list of units, not #{inspect(other)}")}

  @doc """
  Builds a duration as `new/1` does, returning it or raising.

  ### Arguments

  * `components` is a keyword list of units, as for `new/1`.

  ### Returns

  * The `t:t/0`, or raises the error `new/1` returns.

  ### Examples

      iex> Tempo.Duration.new!(day: 1)
      ~o"P1D"

  """
  @spec new!(keyword()) :: t()
  def new!(components) do
    case new(components) do
      {:ok, duration} -> duration
      {:error, exception} -> raise exception
    end
  end

  # ── Arithmetic on durations ───────────────────────────────────────────

  @doc """
  Whether a duration has a fixed length: one of weeks, days and units of
  the clock alone. A month or a year is as long as the one it is counted
  from, so a duration with either is not exact.

  ### Arguments

  * `duration` is a `t:t/0`.

  ### Returns

  * `true` for a duration of weeks, days and units of the clock alone, and
    `false` for one with a month or a year. A value that is no duration
    raises a `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Duration.exact?(~o"P1W2DT3H")
      true

      iex> Tempo.Duration.exact?(~o"P1M")
      false

  """
  @spec exact?(t()) :: boolean()
  def exact?(%__MODULE__{units: units}),
    do: not Enum.any?(units, fn {unit, _} -> unit in [:year, :month] end)

  def exact?(other), do: not_a_duration!(other)

  @doc """
  The length of an exact duration in microseconds, with a week seven days
  and a day twenty-four hours.

  ### Returns

  * `{:ok, microseconds}`.

  * `{:error, %ArgumentError{}}` for a duration with a month or a year, and
    `{:error, %Tempo.ConversionError{}}` for a value that is no duration.

  ### Arguments

  * `duration` is a `t:t/0`.

  ### Examples

      iex> Tempo.Duration.to_microseconds(~o"PT1H30M")
      {:ok, 5_400_000_000}

      iex> {:error, %ArgumentError{}} = Tempo.Duration.to_microseconds(~o"P1M")

  """
  @spec to_microseconds(t()) :: {:ok, integer()} | {:error, Exception.t()}
  def to_microseconds(%__MODULE__{units: units} = duration) do
    if exact?(duration) do
      {:ok, Enum.reduce(units, 0, fn {unit, value}, sum -> sum + ticks(unit, value) end)}
    else
      {:error, argument("#{inspect(duration)} has a month or a year, which has no fixed length")}
    end
  end

  def to_microseconds(other), do: {:error, not_a_duration(other)}

  @doc """
  `to_microseconds/1`, returning its answer or raising the error.

  ### Arguments

  * The arguments are those of `to_microseconds/1`.

  ### Returns

  * What `to_microseconds/1` returns as `{:ok, answer}`, the answer alone.
    The error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.Duration.to_microseconds!(~o"PT1H30M")
      5_400_000_000

  """
  @spec to_microseconds!(t()) :: integer()
  def to_microseconds!(duration) do
    case to_microseconds(duration) do
      {:ok, answer} -> answer
      {:error, exception} -> raise exception
    end
  end

  defp ticks(:week, weeks), do: weeks * 7 * @day
  defp ticks(:day, days), do: days * @day
  defp ticks(:hour, hours), do: hours * 3_600_000_000
  defp ticks(:minute, minutes), do: minutes * 60_000_000
  defp ticks(:second, seconds), do: seconds * 1_000_000
  defp ticks(:microsecond, {microseconds, _precision}), do: microseconds

  @doc """
  A duration in the reverse direction: each unit negated.

  ### Arguments

  * `duration` is a `t:t/0`.

  ### Returns

  * The `t:t/0` with each unit negated. A value that is no duration raises
    a `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Duration.negate(~o"P1DT2H")
      ~o"-P1DT2H"

  """
  @spec negate(t()) :: t()
  def negate(%__MODULE__{} = duration), do: multiply(duration, -1)
  def negate(other), do: not_a_duration!(other)

  @doc """
  A duration taken a whole number of times: each unit multiplied.

  ### Arguments

  * `duration` is a `t:t/0`.

  * `n` is a whole number.

  ### Returns

  * The `t:t/0` with each unit multiplied by `n`. A value that is no
    duration raises a `Tempo.ConversionError`, and an `n` that is no whole
    number an `ArgumentError`.

  ### Examples

      iex> Tempo.Duration.multiply(~o"P1M15D", 2)
      ~o"P2M30D"

  """
  @spec multiply(t(), integer()) :: t()
  def multiply(%__MODULE__{units: units}, n) when is_integer(n) do
    %__MODULE__{
      units:
        units
        |> Enum.map(fn
          {:microsecond, {microseconds, precision}} ->
            {:microsecond, {microseconds * n, precision}}

          {unit, value} ->
            {unit, value * n}
        end)
        |> carried()
    }
  end

  def multiply(%__MODULE__{}, n),
    do: raise(ArgumentError, "a duration is multiplied by a whole number, not #{inspect(n)}")

  def multiply(other, _n), do: not_a_duration!(other)

  # A fraction is of its second, so a million microseconds or more are whole
  # seconds: the one carry between a duration's units.
  defp carried(units) do
    case Keyword.fetch(units, :microsecond) do
      {:ok, {microseconds, precision}} when abs(microseconds) >= 1_000_000 ->
        seconds = Keyword.get(units, :second, 0) + div(microseconds, 1_000_000)
        fraction = {rem(microseconds, 1_000_000), precision}

        units
        |> Keyword.drop([:second, :microsecond])
        |> Kernel.++(second: seconds, microsecond: fraction)

      _within_a_second ->
        units
    end
  end

  @doc """
  The sum of two durations, unit by unit: an hour and a half plus forty-five
  minutes is an hour and seventy-five minutes, no unit carried into another,
  because an hour is sixty minutes but a month is not a fixed number of days.
  A fraction of a second is the one exception, being part of its second.

  ### Arguments

  * `duration1` and `duration2` are each a `t:t/0`.

  ### Returns

  * The `t:t/0` of their units added. A value that is no duration raises a
    `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Duration.add(~o"PT1H30M", ~o"PT45M")
      ~o"PT1H75M"

      iex> Tempo.Duration.add(~o"P1Y", ~o"P2M")
      ~o"P1Y2M"

      iex> Tempo.Duration.add(~o"PT0.7S", ~o"PT0.6S")
      ~o"PT1.3S"

  """
  @spec add(t(), t()) :: t()
  def add(a, _b) when not is_struct(a, __MODULE__), do: not_a_duration!(a)
  def add(_a, b) when not is_struct(b, __MODULE__), do: not_a_duration!(b)

  def add(%__MODULE__{units: a}, %__MODULE__{units: b}) do
    units =
      Enum.flat_map(@units, fn unit ->
        case {Keyword.fetch(a, unit), Keyword.fetch(b, unit)} do
          {:error, :error} -> []
          {{:ok, value}, :error} -> [{unit, value}]
          {:error, {:ok, value}} -> [{unit, value}]
          {{:ok, x}, {:ok, y}} -> [{unit, added(x, y)}]
        end
      end)

    %__MODULE__{units: carried(units)}
  end

  defp added({x, px}, {y, py}), do: {x + y, max(px, py)}
  defp added(x, y), do: x + y

  @doc """
  The first duration less the second: `add/2` of the second negated.

  ### Arguments

  * `a` and `b` are each a `t:t/0`.

  ### Returns

  * The `t:t/0` of `a` less `b`, unit by unit. A value that is no duration
    raises a `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Duration.subtract(~o"PT2H", ~o"PT30M")
      ~o"PT2H-30M"

  """
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{} = a, %__MODULE__{} = b), do: add(a, negate(b))
  def subtract(a, %__MODULE__{}), do: not_a_duration!(a)
  def subtract(_a, b), do: not_a_duration!(b)

  @doc """
  The sum of a list of durations, as `add/2` sums two.

  ### Arguments

  * `durations` is a list of `t:t/0`.

  ### Returns

  * The `t:t/0` of their units added, `P` with no units for an empty list.
    A member that is no duration raises a `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Duration.sum([~o"PT1H", ~o"PT2H", ~o"P1D"])
      ~o"P1DT3H"

  """
  @spec sum([t()]) :: t()
  def sum(durations) when is_list(durations),
    do: Enum.reduce(durations, %__MODULE__{units: []}, &add(&2, &1))

  def sum(other),
    do: raise(ArgumentError, "a sum is of a list of durations, not #{inspect(other)}")

  @doc """
  Orders two durations by length, so that `Tempo.Duration` is a sorter:
  `Enum.sort(durations, Tempo.Duration)`.

  Two exact durations are compared as lengths, however they are written:
  `PT90M` and `PT1H30M` are equal. A duration with a month or a year has no
  length until it is counted from a date, given as `:relative_to`. Without
  one, years and months are counted in months by the calendar's year, as
  ISO 8601-2's Amendment 1 (2025) converts them, and the rest as a length:
  `P7Y24M` and `P9Y` are equal, and `P1Y1D` is longer than `P12M`. Where
  the months differ one way and the rest the other (`P1M` against `P30D`),
  or the calendar's years differ in months, the comparison raises, having
  only three answers to give.

  ### Arguments

  * `a` and `b` are each a `t:t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:relative_to` is a `t:Tempo.t/0` the two durations are counted from:
    each is laid from the value's start, and the two ends compared.

  * `:calendar` is the calendar whose year counts the months of a year,
    without `:relative_to`. The default is `Calendar.ISO`.

  ### Returns

  * `:lt`, `:eq` or `:gt`.

  ### Examples

      iex> Tempo.Duration.compare(~o"PT90M", ~o"PT1H30M")
      :eq

      iex> Tempo.Duration.compare(~o"P7Y24M", ~o"P9Y")
      :eq

      iex> Enum.sort([~o"PT2H", ~o"PT30M", ~o"PT1H"], Tempo.Duration)
      [~o"PT30M", ~o"PT1H", ~o"PT2H"]

      iex> Tempo.Duration.compare(~o"P1M", ~o"P30D", relative_to: ~o"2026-02-01")
      :lt

  """
  @spec compare(t(), t(), keyword()) :: :lt | :eq | :gt
  def compare(a, b, options \\ [])

  def compare(%__MODULE__{} = a, %__MODULE__{} = b, options) do
    Options.check!(options, [:relative_to, :calendar], "Tempo.Duration.compare/3")

    if is_nil(options[:relative_to]) and not (exact?(a) and exact?(b)) do
      by_parts(a, b, Keyword.get(options, :calendar, Tempo.Calendar.default()))
    else
      by_length(a, b, options)
    end
  end

  def compare(%__MODULE__{}, b, _options), do: not_a_duration!(b)
  def compare(a, _b, _options), do: not_a_duration!(a)

  defp by_length(a, b, options) do
    case {laid(a, options), laid(b, options)} do
      {{:ok, x}, {:ok, y}} -> Scale.compare(x, y)
      {{:error, exception}, _} -> raise exception
      {_, {:error, exception}} -> raise exception
    end
  end

  # Months counted by the calendar's year, and the rest as a length: two
  # durations are in order where the two counts do not disagree.
  defp by_parts(a, b, calendar) do
    case {months_and_rest(a, calendar), months_and_rest(b, calendar)} do
      {{:ok, {months_a, rest_a}}, {:ok, {months_b, rest_b}}} ->
        agreed(Scale.compare(months_a, months_b), Scale.compare(rest_a, rest_b), a, b)

      _months_not_counted ->
        raise argument(
                "#{inspect(a)} or #{inspect(b)} has years in a calendar whose years differ " <>
                  "in months, which have no fixed length; give :relative_to"
              )
    end
  end

  defp agreed(:eq, order, _a, _b) do
    order
  end

  defp agreed(order, :eq, _a, _b) do
    order
  end

  defp agreed(order, order, _a, _b) do
    order
  end

  defp agreed(_months, _rest, a, b) do
    raise argument(
            "#{inspect(a)} and #{inspect(b)} differ one way in months and the other in the " <>
              "rest, so which is longer depends on the date they are counted from; give :relative_to"
          )
  end

  defp months_and_rest(%__MODULE__{units: units}, calendar) do
    {years_and_months, rest} = Enum.split_with(units, fn {unit, _} -> unit in [:year, :month] end)

    with {:ok, months} <- months_of(years_and_months, calendar) do
      {:ok, {months, chain_length(rest, week_sizes(calendar))}}
    end
  end

  defp months_of(parts, calendar) do
    years = Keyword.get(parts, :year, 0)
    months = Keyword.get(parts, :month, 0)

    case {years, Tempo.Calendar.months_in_year_bounds(calendar)} do
      {0, _bounds} -> {:ok, months}
      {_years, {in_year, in_year}} -> {:ok, years * in_year + months}
      _varying -> :error
    end
  end

  @doc """
  A duration in canonical form, as ISO 8601-2's Amendment 1 (2025) defines
  it (§14.7 and D.5): no part past the unit above it that it converts into,
  and a negative part only where no coarser part written can take it in.

  Parts convert along two chains. Years and months convert by the months in
  the calendar's year, where every year has as many. Weeks, days, hours,
  minutes, seconds and parts of a second convert by the days in the
  calendar's week, 24 hours, 60 minutes and 60 seconds. A minute is 60
  seconds, as Tempo's clock has it, which is the nominal duration rule the
  amendment allows (§14.6). Months and days do not convert, and nor do years
  and weeks: the month and the days of `P1M30D` stay apart.

  A chain of positive length is written from the coarsest unit it reaches:
  `PT26H` is `P1DT2H`, and `P10D` is `P1W3D`. A chain of negative length
  carries its sign on the coarsest unit written in it, the rest positive:
  `P-1Y-15M` is `P-3Y9M`.

  The canonical form is for comparing and for writing. A shift by it can
  land elsewhere in a zone across a change of the clock, where a day is a
  day of the calendar and 24 hours are elapsed time.

  ### Arguments

  * `duration` is a `t:t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:calendar` is the calendar whose years and weeks count the months and
    days. The default is `Calendar.ISO`.

  ### Returns

  * `{:ok, duration}` in canonical form, or

  * `{:error, exception}` for a value that is no duration, an option the
    function does not take, or a calendar Tempo does not know.

  ### Examples

      iex> Tempo.Duration.canonical(~o"P7Y24M")
      {:ok, ~o"P9Y"}

      iex> Tempo.Duration.canonical(~o"PT1H-10M")
      {:ok, ~o"PT50M"}

      iex> Tempo.Duration.canonical(~o"P3DT-10M")
      {:ok, ~o"P2DT23H50M"}

  """
  @spec canonical(t(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def canonical(duration, options \\ [])

  def canonical(%__MODULE__{units: units}, options) do
    with :ok <- Options.check(options, [:calendar], "Tempo.Duration.canonical/2"),
         {:ok, calendar} <- calendar_named(options) do
      {:ok, %__MODULE__{units: canonical_units(units, calendar)}}
    end
  end

  def canonical(other, _options) do
    {:error, not_a_duration(other)}
  end

  @doc """
  `canonical/2`, returning its answer or raising the error.

  ### Arguments

  * The arguments are those of `canonical/2`.

  ### Returns

  * What `canonical/2` returns as `{:ok, answer}`, the answer alone. The
    error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.Duration.canonical!(~o"PT1H90M")
      ~o"PT2H30M"

  """
  @spec canonical!(t(), keyword()) :: t()
  def canonical!(duration, options \\ []) do
    case canonical(duration, options) do
      {:ok, answer} -> answer
      {:error, exception} -> raise exception
    end
  end

  defp calendar_named(options) do
    calendar = Keyword.get(options, :calendar, Tempo.Calendar.default())

    if Tempo.Calendar.calendar?(calendar) do
      {:ok, calendar}
    else
      {:error, InvalidCalendarError.exception(calendar: calendar)}
    end
  end

  defp canonical_units([], _calendar) do
    []
  end

  defp canonical_units(units, calendar) do
    {years_and_months, rest} = Enum.split_with(units, fn {unit, _} -> unit in [:year, :month] end)
    canonical = years_and_months(years_and_months, calendar) ++ weeks_and_less(rest, calendar)

    case canonical do
      [] -> [zero(List.last(units))]
      [_ | _] -> canonical
    end
  end

  defp zero({:microsecond, {_microseconds, precision}}) do
    {:microsecond, {0, precision}}
  end

  defp zero({unit, _n}) do
    {unit, 0}
  end

  # Years and months are one chain where every year has as many months.
  defp years_and_months([], _calendar) do
    []
  end

  defp years_and_months(parts, calendar) do
    case Tempo.Calendar.months_in_year_bounds(calendar) do
      {months, months} -> chained(parts, [year: months, month: 1], :year)
      _varying -> parts
    end
  end

  defp weeks_and_less([], _calendar) do
    []
  end

  defp weeks_and_less(parts, calendar) do
    chained(parts, week_sizes(calendar), :week)
  end

  # The microseconds in each unit from a week down, a week the calendar's.
  defp week_sizes(calendar) do
    [
      week: Tempo.Calendar.days_in_week(calendar) * @day,
      day: @day,
      hour: 3_600_000_000,
      minute: 60_000_000,
      second: 1_000_000,
      microsecond: 1
    ]
  end

  defp chain_length(parts, sizes) do
    Enum.reduce(parts, 0, fn part, sum -> sum + part_length(part, sizes) end)
  end

  # The parts of one chain as one length, written again down to the chain's
  # finest unit, a part of zero left out: from the chain's top for a
  # positive length, from the coarsest unit written for a negative one.
  defp chained(parts, sizes, top) do
    length = chain_length(parts, sizes)
    {coarsest, _} = List.first(parts)
    {finest, _} = List.last(sizes)
    precision = precision(parts)

    cond do
      length == 0 -> []
      length > 0 -> written(length, units_between(sizes, top, finest), sizes, precision)
      true -> written(length, units_between(sizes, coarsest, finest), sizes, precision)
    end
  end

  defp part_length({:microsecond, {microseconds, _precision}}, _sizes) do
    microseconds
  end

  defp part_length({unit, n}, sizes) when is_integer(n) do
    n * Keyword.fetch!(sizes, unit)
  end

  # A decimal fraction on the finest part (`P1.5W`) is counted to the
  # microsecond.
  defp part_length({unit, n}, sizes) when is_float(n) do
    round(n * Keyword.fetch!(sizes, unit))
  end

  defp precision(parts) do
    case List.keyfind(parts, :microsecond, 0) do
      {:microsecond, {_microseconds, precision}} -> precision
      nil -> 6
    end
  end

  defp units_between(sizes, from, to) do
    sizes
    |> Keyword.keys()
    |> Enum.drop_while(&(&1 != from))
    |> Enum.take_while(&(&1 != to))
    |> Kernel.++([to])
  end

  # The first unit takes the length's sign (a floor, so the rest is
  # positive); each after it what is left.
  defp written(length, [first | rest], sizes, precision) do
    size = Keyword.fetch!(sizes, first)
    count = Integer.floor_div(length, size)

    [{first, count} | each_written(length - count * size, rest, sizes)]
    |> Enum.reject(fn {_unit, n} -> n == 0 end)
    |> Enum.map(&with_precision(&1, precision))
  end

  defp each_written(_left, [], _sizes) do
    []
  end

  defp each_written(left, [unit | rest], sizes) do
    size = Keyword.fetch!(sizes, unit)
    [{unit, div(left, size)} | each_written(rem(left, size), rest, sizes)]
  end

  defp with_precision({:microsecond, microseconds}, precision) do
    {:microsecond, {microseconds, precision}}
  end

  defp with_precision(part, _precision) do
    part
  end

  @doc """
  The length of a duration in one unit of fixed length, as a float.

  ### Arguments

  * `duration` is a `t:t/0`.

  * `unit` is `:week`, `:day`, `:hour`, `:minute`, `:second` or
    `:microsecond`.

  * `options` is a keyword list of options.

  ### Options

  * `:relative_to` is a `t:Tempo.t/0` the duration is counted from, which a
    duration with a month or a year needs.

  ### Returns

  * `{:ok, length}`, a float.

  * `{:error, %ArgumentError{}}` when the unit is a month or a year, or the
    duration has one and no `:relative_to`.

  ### Examples

      iex> Tempo.Duration.to_unit(~o"PT90M", :hour)
      {:ok, 1.5}

      iex> Tempo.Duration.to_unit(~o"P1M", :day, relative_to: ~o"2026-02-01")
      {:ok, 28.0}

  """
  @spec to_unit(t(), :week | :day | :hour | :minute | :second | :microsecond, keyword()) ::
          {:ok, float()} | {:error, Exception.t()}
  def to_unit(duration, unit, options \\ [])

  def to_unit(%__MODULE__{} = duration, unit, options)
      when unit in [:week, :day, :hour, :minute, :second, :microsecond] do
    with :ok <- Options.check(options, [:relative_to], "Tempo.Duration.to_unit/3"),
         {:ok, microseconds} <- laid(duration, options) do
      {:ok, microseconds / ticks(unit, 1)}
    end
  end

  def to_unit(%__MODULE__{}, unit, _options),
    do: {:error, argument("#{inspect(unit)} has no fixed length to count a duration in")}

  def to_unit(other, _unit, _options), do: {:error, not_a_duration(other)}

  @doc """
  `to_unit/3`, returning its answer or raising the error.

  ### Arguments

  * The arguments are those of `to_unit/3`.

  ### Options

  * The options of `to_unit/3`.

  ### Returns

  * What `to_unit/3` returns as `{:ok, answer}`, the answer alone.
    The error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> Tempo.Duration.to_unit!(~o"PT90M", :hour)
      1.5

  """
  @spec to_unit!(t(), :week | :day | :hour | :minute | :second | :microsecond, keyword()) ::
          float()
  def to_unit!(duration, unit, options \\ []) do
    case to_unit(duration, unit, options) do
      {:ok, answer} -> answer
      {:error, exception} -> raise exception
    end
  end

  # A duration's length in microseconds: its own when exact, else from a date.
  defp laid(%__MODULE__{} = duration, options) do
    case {exact?(duration), options[:relative_to]} do
      {true, _} -> to_microseconds(duration)
      {false, %Tempo{} = from} -> laid_from(duration, from)
      {false, _} -> to_microseconds(duration)
    end
  end

  defp laid_from(duration, from) do
    frame = Spans.frame_of(from)

    with {:ok, {start, _stop}} <- Spans.extent(from),
         {:ok, stop} <- Spans.shifted(start, duration, frame, from) do
      {:ok, stop - start}
    end
  end

  defp whole?({:microsecond, {microseconds, precision}}),
    do: is_integer(microseconds) and is_integer(precision) and precision in 0..6

  defp whole?({:microsecond, _other}), do: false
  defp whole?({_unit, value}), do: is_integer(value)

  defp argument(message), do: ArgumentError.exception(message)

  defp not_a_duration(other),
    do: ConversionError.exception(value: other, reason: :not_a_duration)

  @spec not_a_duration!(term()) :: no_return()
  defp not_a_duration!(other), do: raise(not_a_duration(other))
end
