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

  alias Tempo.{Clock, ConversionError, Duration, Shift, Spans, Unit, Validate, Zone}

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
    do: {:ok, %Tempo{form: {:value, clock(time)}}}

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

  # A `DateTime` in a zone the database has is in that zone. Any other says
  # its moment by its own offset, which is then its shift: UTC, a time zone
  # that is an offset (`"-05:00"`, as RFC 9557 and Localize name one), UTC
  # named beside an offset that is not zero, and a zone no database has.
  defp zone_of(%DateTime{time_zone: "Etc/UTC", utc_offset: 0, std_offset: 0}),
    do: {:ok, nil, [hour: 0]}

  defp zone_of(%DateTime{time_zone: "Etc/UTC"} = datetime), do: {:ok, nil, own_shift(datetime)}

  defp zone_of(%DateTime{time_zone: name} = datetime) do
    case Zone.named(name) do
      {:ok, zone} -> {:ok, zone, nil}
      {:error, _not_in_the_database} -> {:ok, nil, own_shift(datetime)}
    end
  end

  defp own_shift(%DateTime{utc_offset: utc_offset, std_offset: std_offset}),
    do: Zone.shift_of((utc_offset + std_offset) * 1_000_000)

  # ── To Elixir ─────────────────────────────────────────────────────────

  @doc "The Elixir struct a value fills: a date, a time, a naive or a zoned date and time, a duration; and the range of dates an interval of two dates is."
  @spec to(Tempo.t() | Duration.t()) :: {:ok, struct()} | {:error, Exception.t()}
  def to(%Duration{units: units}), do: {:ok, Elixir.Duration.new!(units)}

  def to(%Tempo{form: {:value, units}} = value) do
    date? = Keyword.has_key?(units, :day) and Keyword.has_key?(units, :year)
    zoned? = value.zone != nil or value.shift != nil
    filled(value, date?, Keyword.has_key?(units, :hour), zoned?)
  end

  # An interval of two dates is the range of them: both hold their last day,
  # the interval by how an end written to a date is read and the range by
  # what a `Date.Range` is.
  def to(%Tempo{form: {:span, %Tempo{} = from, %Tempo{} = to}} = interval) do
    with true <- a_date?(from) and a_date?(to),
         {:ok, %Date{} = first} <- to_date(placed(from, interval)),
         {:ok, %Date{} = last} <- to_date(placed(to, interval)) do
      {:ok, Date.range(first, last)}
    end
    |> a_range(interval)
  end

  def to(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_elixir_value)}

  defp a_date?(%Tempo{form: {:value, units}}), do: Keyword.keys(units) == [:year, :month, :day]
  defp a_date?(_end), do: false

  defp placed(%Tempo{} = an_end, %Tempo{calendar: calendar}), do: %{an_end | calendar: calendar}

  defp a_range({:ok, %Date.Range{}} = range, _interval), do: range

  defp a_range(_not_dates, interval),
    do: {:error, ConversionError.exception(value: interval, reason: :not_an_elixir_value)}

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

  # A shift written beside a zone gives the moment (RFC 9557 §3.4), and the
  # zone the clock that moment is shown on. Where the shift says which of
  # two showings of a reading is meant and the clock comes to that showing
  # part of the way through it, the moment is where the value begins: the
  # hour from 02:00 shown again from 02:45.
  def to_datetime(%Tempo{zone: %Zone{name: name}, shift: shift} = value)
      when is_binary(name) and is_list(shift) do
    with {:ok, moment} <- to_datetime(%{value | zone: nil}) do
      moment
      |> DateTime.add(seconds_to_its_start(value), :second)
      |> DateTime.shift_zone(name)
      |> named(value)
    end
  end

  # The moment is where the value begins on the UTC line, as Tempo places
  # every reading (`Tempo.Spans.extent/1`: a reading the clock shows twice
  # at its first showing, one it skips where the clock comes out of the
  # gap), shown on the zone's clock there. The database reads the wall
  # clock once, in Tempo's table of its changes, and not a second time here.
  def to_datetime(%Tempo{zone: %Zone{name: name}, calendar: calendar} = value)
      when is_binary(name) do
    with {:ok, naive} <- to_naive(value),
         {:ok, {start, _stop}} when is_integer(start) <- Spans.extent(value),
         {:ok, shown} <- at_tick(start, naive.microsecond, name) |> named(value) do
      DateTime.convert(shown, calendar) |> named(value)
    end
  end

  # A zone that is a fixed offset (`[-05:00]`) is that offset, and the
  # moment is the reading at it; a shift written beside it says the moment.
  def to_datetime(%Tempo{zone: %Zone{name: nil, offset: minutes}, shift: shift} = value)
      when is_integer(minutes) do
    to_datetime(%{value | zone: nil, shift: shift || Zone.shift_of(minutes * 60 * 1_000_000)})
  end

  def to_datetime(%Tempo{shift: shift} = value) when is_list(shift) do
    with {:ok, naive} <- to_naive(value) do
      seconds = div(Zone.shift_ticks(shift), 1_000_000)
      {:ok, naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.add(-seconds, :second)}
    end
  end

  def to_datetime(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_elixir_value)}

  # A UTC tick shown on a zone's clock, at the precision of a part of a second.
  defp at_tick(tick, {_microseconds, precision}, zone) do
    seconds = Integer.floor_div(tick, 1_000_000)
    microsecond = {Integer.mod(tick, 1_000_000), precision}
    seconds |> DateTime.from_gregorian_seconds(microsecond) |> DateTime.shift_zone(zone)
  end

  # The seconds from the moment a value's reading and shift name to where
  # the value begins in its zone: none, but where the zone's clock comes to
  # that showing within the reading.
  defp seconds_to_its_start(%Tempo{} = value) do
    case {Spans.extent(value), Spans.extent(%{value | zone: nil})} do
      {{:ok, {start, _}}, {:ok, {written, _}}} when is_integer(start) and is_integer(written) ->
        div(start - written, 1_000_000)

      _no_place ->
        0
    end
  end

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
