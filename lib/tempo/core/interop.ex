defmodule Tempo.Interop do
  @moduledoc false
  # Elixir's date and time structs to and from Tempo values.
  #
  # A `Date` is a day, a `Time` a second (or the fraction it carries), a
  # `NaiveDateTime` a floating second, a `DateTime` a second in its zone:
  # UTC as a zero shift, a named zone by name. A `Date.Range` is the span of
  # its days, written to its last day (law 9). The other way a value is the
  # struct its units fill: a date, a time, a date and time, in its zone when
  # it has one.

  alias Tempo.{Clock, ConversionError, Duration, Shift, Unit, Validate, Zone}

  @doc "A Tempo value from an Elixir struct, at a resolution when one is asked."
  @spec from(term(), keyword()) :: {:ok, Tempo.t() | Duration.t()} | {:error, Exception.t()}
  def from(value, options \\ []) do
    with {:ok, tempo} <- converted(value), do: at_resolution(tempo, options[:resolution])
  end

  defp at_resolution(tempo, nil), do: {:ok, tempo}
  defp at_resolution(%Tempo{} = tempo, unit), do: Shift.at_resolution(tempo, unit)
  defp at_resolution(other, _unit), do: {:ok, other}

  defp converted(%Date{year: y, month: m, day: d, calendar: calendar}),
    do: {:ok, %Tempo{form: {:value, [year: y, month: m, day: d]}, calendar: calendar}}

  defp converted(%Time{} = time),
    do: {:ok, %Tempo{form: {:value, clock(time)}, calendar: Calendar.ISO}}

  defp converted(%NaiveDateTime{year: y, month: m, day: d, calendar: calendar} = naive),
    do:
      {:ok,
       %Tempo{form: {:value, [year: y, month: m, day: d] ++ clock(naive)}, calendar: calendar}}

  defp converted(%DateTime{year: y, month: m, day: d, calendar: calendar} = datetime) do
    with {:ok, zone, shift} <- zone_of(datetime) do
      {:ok,
       %Tempo{
         form: {:value, [year: y, month: m, day: d] ++ clock(datetime)},
         calendar: calendar,
         zone: zone,
         shift: shift
       }}
    end
  end

  defp converted(%Date.Range{first: first, last: last, step: 1})
       when first.calendar == last.calendar do
    with {:ok, from} <- converted(first),
         {:ok, to} <- converted(last),
         do: Validate.run(%Tempo{form: {:span, from, to}, calendar: first.calendar})
  end

  defp converted(%Elixir.Duration{} = duration) do
    duration
    |> Map.from_struct()
    |> Enum.reject(fn {_, value} -> value in [0, {0, 0}] end)
    |> Duration.new()
  end

  defp converted(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_elixir_value)}

  defp clock(%{hour: h, minute: m, second: s, microsecond: {_, 0}}),
    do: [hour: h, minute: m, second: s]

  defp clock(%{hour: h, minute: m, second: s, microsecond: {us, precision}}),
    do: [hour: h, minute: m, second: s, microsecond: {us, precision}]

  defp zone_of(%DateTime{time_zone: "Etc/UTC"}), do: {:ok, nil, [hour: 0]}

  defp zone_of(%DateTime{time_zone: name}) do
    with {:ok, zone} <- Zone.named(name), do: {:ok, zone, nil}
  end

  # ── To Elixir ─────────────────────────────────────────────────────────

  @doc "The Elixir struct a value fills: a date, a time, a naive or a zoned date and time, a duration."
  @spec to(Tempo.t() | Duration.t()) :: {:ok, struct()} | {:error, Exception.t()}
  def to(%Duration{units: units}), do: {:ok, Elixir.Duration.new!(units)}

  def to(%Tempo{form: {:value, units}} = value) do
    date? = Keyword.has_key?(units, :day) and Keyword.has_key?(units, :year)
    zoned? = value.zone != nil or value.shift != nil
    filled(value, date?, Keyword.has_key?(units, :hour), zoned?)
  end

  def to(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_elixir_value)}

  defp filled(value, true, true, true), do: to_datetime(value)
  defp filled(value, true, true, false), do: to_naive(value)
  defp filled(value, true, false, _zoned?), do: to_date(value)
  defp filled(value, false, true, _zoned?), do: to_time(value)

  defp filled(value, false, false, _zoned?),
    do: {:error, ConversionError.exception(value: value, reason: :not_an_elixir_value)}

  @doc "The date of a value written to the day or finer."
  @spec to_date(Tempo.t()) :: {:ok, Date.t()} | {:error, Exception.t()}
  def to_date(%Tempo{calendar: calendar} = value) do
    with {:ok, y, m, d} <- date_parts(value), do: Date.new(y, m, d, calendar) |> named(value)
  end

  @doc "The time of day of a value with one: its clock units, the rest zero."
  @spec to_time(Tempo.t()) :: {:ok, Time.t()} | {:error, Exception.t()}
  def to_time(%Tempo{form: {:value, units}} = value) do
    if Keyword.has_key?(units, :hour) and Unit.concrete?(Unit.clock_units(units)) do
      {h, m, s, us} = clock_parts(units)
      Time.new(h, m, s, us) |> named(value)
    else
      {:error, ConversionError.exception(value: value, reason: :not_an_elixir_value)}
    end
  end

  def to_time(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_elixir_value)}

  @doc "The naive date and time of a value written to the day or finer: its clock units, the rest zero."
  @spec to_naive(Tempo.t()) :: {:ok, NaiveDateTime.t()} | {:error, Exception.t()}
  def to_naive(%Tempo{form: {:value, units}, calendar: calendar} = value) do
    with {:ok, y, mo, d} <- date_parts(value) do
      {h, m, s, us} = clock_parts(units)
      NaiveDateTime.new(y, mo, d, h, m, s, us, calendar) |> named(value)
    end
  end

  def to_naive(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_elixir_value)}

  @doc "The zoned date and time of a value with a zone or a shift."
  @spec to_datetime(Tempo.t()) :: {:ok, DateTime.t()} | {:error, Exception.t()}
  def to_datetime(%Tempo{zone: nil, shift: nil} = value),
    do: {:error, ConversionError.exception(value: value, reason: :floating)}

  def to_datetime(%Tempo{zone: %Zone{name: name}} = value) when is_binary(name) do
    with {:ok, naive} <- to_naive(value) do
      case DateTime.from_naive(naive, name) do
        {:ok, datetime} -> {:ok, datetime}
        {:ambiguous, first, _second} -> {:ok, first}
        {:gap, _before, after_gap} -> {:ok, after_gap}
        {:error, reason} -> {:error, ConversionError.exception(value: value, reason: reason)}
      end
    end
  end

  def to_datetime(%Tempo{shift: shift} = value) when is_list(shift) do
    with {:ok, naive} <- to_naive(value) do
      seconds = div(Zone.shift_ticks(shift), 1_000_000)
      {:ok, naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.add(-seconds, :second)}
    end
  end

  def to_datetime(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_elixir_value)}

  # The year, month and day of a value on any axis, through its parts.
  defp date_parts(%Tempo{form: {:value, _}} = value) do
    case {Tempo.year(value), Tempo.month(value), Tempo.day(value)} do
      {y, m, d} when is_integer(y) and is_integer(m) and is_integer(d) -> {:ok, y, m, d}
      _ -> {:error, ConversionError.exception(value: value, reason: :not_an_elixir_value)}
    end
  end

  defp date_parts(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_elixir_value)}

  defp clock_parts(units) do
    {Keyword.get(units, :hour, 0), Keyword.get(units, :minute, 0), Keyword.get(units, :second, 0),
     Keyword.get(units, :microsecond, {0, 0})}
  end

  defp named({:ok, struct}, _value), do: {:ok, struct}

  defp named({:error, reason}, value),
    do: {:error, ConversionError.exception(value: value, reason: reason)}

  # ── Now ───────────────────────────────────────────────────────────────

  @doc "The current second in a zone, from the configured clock."
  @spec now(String.t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def now(zone) do
    with {:ok, _} <- Zone.named(zone),
         {:ok, local} <- shifted(Clock.clock().utc_now(), zone) do
      from(%{local | microsecond: {0, 0}})
    end
  end

  defp shifted(utc, zone) do
    case DateTime.shift_zone(utc, zone) do
      {:ok, local} -> {:ok, local}
      {:error, reason} -> {:error, ConversionError.exception(value: zone, reason: reason)}
    end
  end
end
