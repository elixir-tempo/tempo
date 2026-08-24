defmodule Tempo.Duration do
  @moduledoc """
  A calendar-relative duration — a list of `{unit, amount}`
  pairs such as `[year: 1, month: 6]`. Produced by the ISO 8601
  parser (`P1Y6M`), the RRULE encoder (as the `FREQ + INTERVAL`
  cadence), and arithmetic helpers in `Tempo.Math`.
  """

  alias Tempo.Compare
  alias Tempo.Microsecond

  @type unit ::
          :year
          | :month
          | :week
          | :day
          | :hour
          | :minute
          | :second
          | :microsecond
          | :day_of_year
          | :day_of_week

  @type t :: %__MODULE__{
          time: [{unit(), integer() | Tempo.Microsecond.t()}]
        }

  defstruct [:time]

  @valid_units [
    :year,
    :month,
    :week,
    :day,
    :hour,
    :minute,
    :second,
    :microsecond,
    :day_of_year,
    :day_of_week
  ]
  @canonical_unit_order [
    :year,
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

  @doc """
  Construct a `t:Tempo.Duration.t/0` from a keyword list of
  `{unit, amount}` pairs.

  Components can be passed in any order; `new/1` reorders them
  coarse-to-fine before building the struct.

  ### Arguments

  * `components` is a keyword list of duration units.

  ### Options

  Every value must be an integer. Negative values are permitted
  (reverse-direction duration).

  * `:year` is the year count.

  * `:month` is the month count.

  * `:week` is the week count.

  * `:day` is the day count.

  * `:day_of_year` is a day-of-year offset (used by RRULE expansion).

  * `:day_of_week` is a day-of-week offset (used by RRULE expansion).

  * `:hour` is the hour count.

  * `:minute` is the minute count.

  * `:second` is the second count.

  ### Returns

  * `{:ok, t()}` on success.

  * `{:error, reason}` when a key is unknown or a value is not an
    integer.

  ### Examples

      iex> {:ok, d} = Tempo.Duration.new(year: 1, month: 6)
      iex> d.time
      [year: 1, month: 6]

      iex> {:ok, d} = Tempo.Duration.new(month: 6, year: 1)
      iex> d.time
      [year: 1, month: 6]

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(components) when is_list(components) do
    with :ok <- ensure_keyword(components),
         :ok <- validate_components(components) do
      ordered =
        components
        |> ensure_second_for_microsecond()
        |> Enum.sort_by(fn {unit, _v} ->
          Enum.find_index(@canonical_unit_order, &(&1 == unit))
        end)

      {:ok, %__MODULE__{time: ordered}}
    end
  end

  # A fractional second is stored as a `:microsecond` component riding
  # on its `:second`. Keep `second: 0` present whenever microseconds
  # are — otherwise `to_iso8601/1` has no whole-second part to attach
  # the fraction to and cannot render the value.
  defp ensure_second_for_microsecond(components) do
    if Keyword.has_key?(components, :microsecond) and
         not Keyword.has_key?(components, :second) do
      components ++ [second: 0]
    else
      components
    end
  end

  @doc """
  Bang variant of `new/1`.
  """
  @spec new!(keyword()) :: t()
  def new!(components) when is_list(components) do
    case new(components) do
      {:ok, d} -> d
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "Tempo.Duration.new!/1 failed: #{inspect(reason)}"
    end
  end

  # Seconds per fixed-length unit. `:month` and `:year` are
  # deliberately absent — they have no fixed length (28–31 days,
  # 365–366 days), so they can only be converted against a reference
  # date.
  @microsecond_seconds 1.0e-6
  @fixed_unit_seconds %{
    microsecond: @microsecond_seconds,
    second: 1.0,
    minute: 60.0,
    hour: 3_600.0,
    day: 86_400.0,
    week: 604_800.0
  }
  @fixed_units Map.keys(@fixed_unit_seconds)

  @doc """
  The same length in the opposite direction.

  Every unit is negated, including the fractional part, so a negated
  duration shifts backwards by exactly what the original shifted
  forwards. Negating twice returns the original.

  This is what a caller needs whenever the direction of a shift is
  decided at runtime rather than written literally — stepping back by a
  configured lead time, widening an interval at both ends, walking a
  recurrence in reverse.

  ### Arguments

  * `duration` is a `t:t/0`.

  ### Returns

  * a `t:t/0` of the same magnitude and the opposite sign.

  ### Examples

      iex> Tempo.Duration.negate(~o"PT15M")
      ~o"PT-15M"

      iex> Tempo.Duration.negate(~o"PT-15M")
      ~o"PT15M"

  Shifting by a duration and then by its negation returns where you
  started:

      iex> lead = ~o"PT15M"
      iex> ~o"2027-03-02T10:00:00"
      ...> |> Tempo.shift(Tempo.Duration.negate(lead))
      ...> |> Tempo.shift(lead)
      ~o"2027Y3M2DT10H0M0S"

  Every component flips, fractional seconds included:

      iex> Tempo.Duration.negate(~o"P1Y2MT1.5S").time
      [year: -1, month: -2, second: -1, microsecond: {-500000, 1}]

  """
  @spec negate(t()) :: t()
  def negate(%__MODULE__{time: time} = duration) do
    %{duration | time: Enum.map(time, &negate_component/1)}
  end

  defp negate_component({:microsecond, {value, precision}}),
    do: {:microsecond, {-value, precision}}

  defp negate_component({unit, value}), do: {unit, -value}

  @doc """
  Add two durations component-wise, returning a new duration.

  Corresponding components sum — hours with hours, months with months —
  and no unit is converted into another, so calendar-length units
  (`:year`, `:month`) add exactly without needing a reference date.
  Fractional seconds carry into whole seconds when they overflow.
  Components that sum to zero are dropped, so a duration and its
  `negate/1` add to the zero duration.

  ### Arguments

  * `duration_a` is a `t:t/0`.

  * `duration_b` is a `t:t/0`.

  ### Returns

  * A `t:t/0` with each unit's components summed.

  ### Examples

      iex> Tempo.Duration.add(~o"PT7H30M", ~o"PT6H")
      ~o"PT13H30M"

      iex> Tempo.Duration.add(~o"P1Y", ~o"P2M3D")
      ~o"P1Y2M3D"

      iex> Tempo.Duration.add(~o"PT1.5S", ~o"PT0.7S")
      ~o"PT2.2S"

      iex> Tempo.Duration.add(~o"PT1H", Tempo.Duration.negate(~o"PT1H")).time
      []

  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{time: time_a}, %__MODULE__{time: time_b}) do
    merged =
      for unit <- @canonical_unit_order,
          summed = add_components(Keyword.get(time_a, unit), Keyword.get(time_b, unit)),
          not zero_component?(summed),
          do: {unit, summed}

    %__MODULE__{time: normalise_microseconds(merged)}
  end

  @doc """
  Sum a list of durations, returning a new duration.

  Reduces the list with `add/2`, so the same component-wise rules
  apply: like units sum, nothing converts, fractional seconds carry.
  An empty list sums to the zero duration.

  ### Arguments

  * `durations` is a list of `t:t/0` values.

  ### Returns

  * A `t:t/0` with each unit's components summed across the list.

  ### Raises

  * `FunctionClauseError` when a list member is not a
    `t:Tempo.Duration.t/0`.

  ### Examples

      iex> Tempo.Duration.sum([~o"PT7H30M", ~o"PT6H", ~o"PT8H"])
      ~o"PT21H30M"

      iex> Tempo.Duration.sum([]).time
      []

  """
  @spec sum([t()]) :: t()
  def sum(durations) when is_list(durations) do
    Enum.reduce(durations, %__MODULE__{time: []}, &add(&2, &1))
  end

  defp add_components(nil, nil), do: nil
  defp add_components(value, nil), do: value
  defp add_components(nil, value), do: value

  defp add_components({value_a, precision_a}, {value_b, precision_b}),
    do: {value_a + value_b, max(precision_a, precision_b)}

  defp add_components(value_a, value_b), do: value_a + value_b

  defp zero_component?(nil), do: true
  defp zero_component?({0, _precision}), do: true
  defp zero_component?(0), do: true
  defp zero_component?(_summed), do: false

  # Recombine the second and its fraction from their microsecond total,
  # so a summed fraction that overflows (`0.5 + 0.7`) carries into the
  # second, mixed signs borrow (`1 s − 0.2 s` is `0.8 s`, not
  # `1 s and −0.2 s`), and the surviving components always share one
  # sign. `div`/`rem` truncate toward zero, so a negative total keeps
  # negative components.
  defp normalise_microseconds(time) do
    case Keyword.get(time, :microsecond) do
      nil ->
        time

      {micro, precision} ->
        total = Keyword.get(time, :second, 0) * 1_000_000 + micro
        seconds = div(total, 1_000_000)
        remainder = rem(total, 1_000_000)
        base = time |> Keyword.delete(:second) |> Keyword.delete(:microsecond)

        cond do
          remainder == 0 and seconds == 0 -> base
          remainder == 0 -> base ++ [second: seconds]
          true -> base ++ [second: seconds, microsecond: {remainder, precision}]
        end
    end
  end

  @doc """
  Express a duration as a single magnitude in `unit`, as a float.

  For a duration built only from fixed-length units (microsecond
  through week, with `day = 24 h` and `week = 7 d`), the conversion
  is exact and needs no context. A duration carrying `:month` or
  `:year` has no fixed length, so it converts only against a
  reference date supplied as `:relative_to` — the duration is applied
  to that date and the elapsed time measured on the UTC time line
  (DST-exact when the reference is zoned). Tempo never assumes a
  nominal month or year; it returns an error instead.

  ### Arguments

  * `duration` is a `t:t/0`.

  * `unit` is the target unit — one of `:microsecond`, `:second`,
    `:minute`, `:hour`, `:day`, `:week`. (`:month`/`:year` are not
    fixed magnitudes and cannot be a target.)

  ### Options

  * `:relative_to` is a `t:Tempo.t/0` reference date. Required to
    convert a duration containing `:month` or `:year`; optional
    otherwise, where a zoned reference makes `:day`/`:week` DST-exact.

  ### Returns

  * `{:ok, magnitude}` where `magnitude` is a `float()`.

  * `{:error, reason}` when the duration needs a `:relative_to` it
    was not given, the target unit is not fixed-length, or the
    reference is invalid.

  ### Examples

      iex> Tempo.Duration.to_unit(~o"PT90M", :hour)
      {:ok, 1.5}

      iex> Tempo.Duration.to_unit(~o"P2D", :hour)
      {:ok, 48.0}

      iex> Tempo.Duration.to_unit(~o"P1M", :day, relative_to: ~o"2026-02-01")
      {:ok, 28.0}

  """
  @spec to_unit(t(), unit(), keyword()) :: {:ok, float()} | {:error, Exception.t()}
  def to_unit(duration, unit, options \\ [])

  def to_unit(%__MODULE__{} = duration, unit, options) when unit in @fixed_units do
    case Keyword.get(options, :relative_to) do
      nil -> to_unit_nominal(duration, unit)
      anchor -> to_unit_relative(duration, unit, anchor)
    end
  end

  def to_unit(%__MODULE__{}, unit, _options) do
    {:error,
     ArgumentError.exception(
       "Tempo.Duration.to_unit/3 target #{inspect(unit)} is not a fixed-length unit. Use " <>
         "one of #{inspect(Enum.sort(@fixed_units))} — a :month or :year has no fixed " <>
         "magnitude, so a duration cannot be expressed *in* them."
     )}
  end

  @doc """
  Bang variant of `to_unit/3` — returns the float or raises.

  ### Examples

      iex> Tempo.Duration.to_unit!(~o"PT8H", :hour)
      8.0

  """
  @spec to_unit!(t(), unit(), keyword()) :: float()
  def to_unit!(%__MODULE__{} = duration, unit, options \\ []) do
    case to_unit(duration, unit, options) do
      {:ok, magnitude} ->
        magnitude

      {:error, exception} when is_exception(exception) ->
        raise exception

      {:error, reason} ->
        raise ArgumentError, "Tempo.Duration.to_unit!/3 failed: #{inspect(reason)}"
    end
  end

  # Nominal conversion using the fixed ratios. A `:month`/`:year`
  # component has no fixed length, so it errors and points the caller
  # at `:relative_to`.
  defp to_unit_nominal(%__MODULE__{time: time}, unit) do
    case sum_fixed_seconds(time) do
      {:ok, seconds} ->
        {:ok, seconds / @fixed_unit_seconds[unit]}

      {:error, offending} ->
        {:error,
         ArgumentError.exception(
           "a duration containing #{inspect(offending)} has no fixed length, so it cannot be " <>
             "converted to #{inspect(unit)} without a reference date — pass " <>
             "`relative_to: some_tempo` to resolve it against the calendar."
         )}
    end
  end

  defp sum_fixed_seconds(time) do
    Enum.reduce_while(time, {:ok, 0.0}, fn {unit, value}, {:ok, acc} ->
      case component_seconds(unit, value) do
        {:ok, seconds} -> {:cont, {:ok, acc + seconds}}
        :error -> {:halt, {:error, unit}}
      end
    end)
  end

  defp component_seconds(:microsecond, {microseconds, _precision}) do
    {:ok, microseconds * @microsecond_seconds}
  end

  defp component_seconds(:microsecond, microseconds) when is_integer(microseconds) do
    {:ok, microseconds * @microsecond_seconds}
  end

  defp component_seconds(unit, value) when unit in [:second, :minute, :hour, :day, :week] do
    {:ok, value * @fixed_unit_seconds[unit]}
  end

  defp component_seconds(_unit, _value), do: :error

  # Anchor-relative conversion: apply the duration to the reference
  # date, then measure the elapsed seconds on the UTC time line and
  # express them in `unit`. A zoned reference makes day/week DST-exact
  # and resolves month/year against the calendar. Runtime calls into
  # `Tempo` (no struct match) keep this module free of a compile cycle.
  defp to_unit_relative(duration, unit, anchor) do
    cond do
      not is_struct(anchor, Tempo) ->
        {:error,
         ArgumentError.exception(":relative_to must be a Tempo value; got #{inspect(anchor)}")}

      not Tempo.anchored?(anchor) ->
        {:error,
         ArgumentError.exception(
           ":relative_to must be anchored (carry a year); got #{inspect(anchor)}"
         )}

      true ->
        ended = Tempo.shift(anchor, duration)
        seconds = Compare.to_utc_seconds(ended) - Compare.to_utc_seconds(anchor)
        {:ok, seconds / @fixed_unit_seconds[unit]}
    end
  end

  @doc false
  # Internal constructor — accepts token-shaped input from the
  # parser without validation. Use `new/1` for developer-facing
  # construction.
  def build(tokens) do
    %__MODULE__{time: lift_microsecond(tokens)}
  end

  # A fractional duration-second is parsed as a sibling `{:fraction,
  # {digits, count}}` token; lift it into a `:microsecond {value,
  # precision}` component (same shape as the clock second) so it
  # round-trips with its digit count and participates in arithmetic.
  # The tokenizer's reduced duration-second: sign applied to both the
  # second and its lifted fraction, keeping component signs consistent.
  defp lift_microsecond([{:second, {:signed_fraction, sign, second, {digits, count}}} | rest]) do
    {value, precision} = Microsecond.from_fraction(digits, count)

    [
      {:second, sign * second},
      {:microsecond, {sign * value, precision}}
      | lift_microsecond(rest)
    ]
  end

  defp lift_microsecond([{:second, second}, {:fraction, {digits, count}} | rest]) do
    # The fraction extends the second's magnitude and inherits its sign
    # (`-1.5 s` is `second: -1, microsecond: {-500000, 1}`).
    {micro_value, precision} = Microsecond.from_fraction(digits, count)
    microsecond = if second < 0, do: {-micro_value, precision}, else: {micro_value, precision}

    [
      {:second, second},
      {:microsecond, microsecond}
      | lift_microsecond(rest)
    ]
  end

  defp lift_microsecond([head | rest]), do: [head | lift_microsecond(rest)]
  defp lift_microsecond([]), do: []

  defp ensure_keyword(components) do
    if Keyword.keyword?(components) do
      :ok
    else
      {:error,
       ArgumentError.exception(
         "Tempo.Duration.new/1 expects a keyword list. Got: #{inspect(components)}"
       )}
    end
  end

  defp validate_components([]) do
    {:error, ArgumentError.exception("Tempo.Duration.new/1 requires at least one component.")}
  end

  defp validate_components(components) do
    Enum.reduce_while(components, :ok, fn {unit, value}, :ok ->
      cond do
        unit not in @valid_units ->
          {:halt,
           {:error,
            ArgumentError.exception(
              "Tempo.Duration.new/1 does not recognise component #{inspect(unit)}. " <>
                "Valid components: #{inspect(@valid_units)}"
            )}}

        unit == :microsecond and not Microsecond.valid?(value) ->
          {:halt,
           {:error,
            ArgumentError.exception(
              "Tempo.Duration :microsecond must be a {value, precision} tuple, got #{inspect(value)}"
            )}}

        unit != :microsecond and not is_integer(value) ->
          {:halt,
           {:error,
            ArgumentError.exception(
              "Tempo.Duration component #{inspect(unit)} must be an integer, got #{inspect(value)}"
            )}}

        true ->
          {:cont, :ok}
      end
    end)
  end
end
