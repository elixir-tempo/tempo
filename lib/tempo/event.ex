defmodule Tempo.Event do
  @moduledoc """
  The date of a named computed event in a year: an event fixed by an
  algorithm rather than by the calendar.

  Four families are built in: Easter, Western and Orthodox, from
  `Calendrical.Ecclesiastical`; the equinoxes and solstices and the first
  new moon of the year, from `Astro`; and the twenty-four solar terms
  (jié-qì) of the East Asian calendars, from `Calendrical`, reckoned at the
  meridian of the calendar asked. A consumer adds its own with a
  `Tempo.Event.Resolver`.

  ISO 8601-2 has no notation for such a date, so Tempo writes it as a
  selection `(name)e` and asks here for it, once per year, when a selection
  or a recurrence such as `~o"R/../P1Y/FL(easter)eN"` is given its spans.

  """

  alias Tempo.Calendar, as: Calendars
  alias Tempo.InvalidDateError
  alias Tempo.ZoneError

  # The solar terms by name, each with the number Calendrical counts it by,
  # from `lichun`; Tempo holds the names to select by.
  @solar_terms Calendars.solar_term_names()

  @events Map.merge(
            %{
              "easter" => :easter,
              "orthodox-easter" => :orthodox_easter,
              "march-equinox" => {:equinox, :march},
              "june-solstice" => {:solstice, :june},
              "september-equinox" => {:equinox, :september},
              "december-solstice" => {:solstice, :december},
              "new-moon" => :new_moon
            },
            Map.new(@solar_terms, fn {name, number} -> {name, {:solar_term, number}} end)
          )

  @doc """
  The names of the events `date/3` resolves: the built-ins and every name a
  registered `Tempo.Event.Resolver` claims, sorted.

  ### Returns

  * A sorted list of event names, each a string.

  ### Examples

      iex> "qingming" in Tempo.Event.known()
      true

      iex> "easter" in Tempo.Event.known()
      true

  """
  @spec known() :: [String.t()]
  def known do
    registered = Enum.flat_map(resolvers(), & &1.known())
    (Map.keys(@events) ++ registered) |> Enum.uniq() |> Enum.sort()
  end

  @doc """
  Whether a name is one of the twenty-four solar terms.

  ### Arguments

  * `name` is an event's name, a string.

  ### Returns

  * `true` for one of the twenty-four, and `false` for any other name. A
    name that is no string raises an `ArgumentError`.

  ### Examples

      iex> Tempo.Event.solar_term?("qingming")
      true

      iex> Tempo.Event.solar_term?("easter")
      false

  """
  @spec solar_term?(String.t()) :: boolean()
  def solar_term?(name) when is_binary(name), do: Map.has_key?(@solar_terms, name)

  def solar_term?(other),
    do: raise(ArgumentError, "an event's name is a string, not #{inspect(other)}")

  @doc """
  The date of a named event in a year of the proleptic Gregorian calendar.

  ### Arguments

  * `name` is an event `known/0` lists. An equinox or a solstice may name
    the zone whose date it takes after an `@`, an IANA zone or a `±HH:MM`
    offset (`"march-equinox@+09:00"`), the instant falling on another date
    there than in UTC.

  * `year` is the Gregorian year.

  * `calendar` is the calendar whose meridian a solar term is reckoned at:
    one of Calendrical's lunisolar calendars, or the Gregorian, the default,
    which reckons it at the Chinese meridian.

  ### Returns

  * `{:ok, date}`, a `t:Date.t/0` in `Calendar.ISO`.

  * `{:error, %Tempo.InvalidDateError{unit: :event}}` whose reason is
    `{:unknown_event, name}`, `{:no_instant, name}` for an `@` zone after an
    event that is no instant, `{:no_solar_terms, calendar}`,
    `:year_out_of_range` for a year `Astro` does not reach, or a resolver's
    own reason.

  * `{:error, %Tempo.ZoneError{reason: :unknown}}` for a zone after an `@`
    that is none.

  * `{:error, %ArgumentError{}}` for a name that is no string or a year
    that is no integer.

  ### Examples

      iex> Tempo.Event.date("easter", 2026)
      {:ok, ~D[2026-04-05]}

      iex> Tempo.Event.date("orthodox-easter", 2026)
      {:ok, ~D[2026-04-12]}

      iex> Tempo.Event.date("december-solstice", 2026)
      {:ok, ~D[2026-12-21]}

      iex> Tempo.Event.date("march-equinox@+09:00", 2002)
      {:ok, ~D[2002-03-21]}

      iex> Tempo.Event.date("qingming", 2026, Calendrical.Gregorian)
      {:ok, ~D[2026-04-05]}

      iex> {:error, %Tempo.InvalidDateError{reason: {:unknown_event, "brigadoon"}}} =
      ...>   Tempo.Event.date("brigadoon", 2026)

  """
  @spec date(String.t(), integer(), module()) :: {:ok, Date.t()} | {:error, Exception.t()}
  def date(name, year, calendar \\ Calendars.default())

  def date(name, year, calendar) when is_binary(name) and is_integer(year) do
    name
    |> String.split("@", parts: 2)
    |> dated_event(year, calendar)
    |> named(name)
  end

  def date(name, year, _calendar) when is_binary(name),
    do:
      {:error, ArgumentError.exception("an event's year is a whole number, not #{inspect(year)}")}

  def date(name, _year, _calendar),
    do: {:error, ArgumentError.exception("an event's name is a string, not #{inspect(name)}")}

  defp dated_event([event, zone], year, _calendar), do: zoned_date(event, zone, year)
  defp dated_event([event], year, calendar), do: event_date(event, year, calendar)

  # Every error is named where it leaves the module, the reasons the
  # computation carries in it becoming the exception's.
  defp named({:ok, %Date{}} = date, _name), do: date
  defp named({:error, %{__exception__: true}} = error, _name), do: error

  defp named({:error, {:invalid_zone, zone}}, _name),
    do: {:error, ZoneError.exception(zone: zone, reason: :unknown)}

  defp named({:error, reason}, name),
    do: {:error, InvalidDateError.exception(value: name, unit: :event, reason: reason)}

  defp event_date(name, year, calendar) do
    case Map.fetch(@events, name) do
      {:ok, spec} -> resolve(spec, year, calendar)
      :error -> resolve_registered(name, year, calendar)
    end
  end

  # An instant's date in a zone.
  defp zoned_date(name, zone, year) do
    with {:ok, spec} <- instant_event(name),
         {:ok, %DateTime{} = instant} <- instant(spec, year),
         {:ok, %DateTime{} = local} <- in_zone(instant, zone) do
      {:ok, DateTime.to_date(local)}
    end
  end

  defp instant_event(name) do
    case Map.fetch(@events, name) do
      {:ok, {kind, _} = spec} when kind in [:equinox, :solstice] -> {:ok, spec}
      {:ok, _not_an_instant} -> {:error, {:no_instant, name}}
      :error -> {:error, {:unknown_event, name}}
    end
  end

  defp instant({:equinox, event}, year), do: Astro.equinox(year, event)
  defp instant({:solstice, event}, year), do: Astro.solstice(year, event)

  defp in_zone(
         %DateTime{} = instant,
         <<sign, hours::binary-size(2), ?:, minutes::binary-size(2)>>
       )
       when sign in [?+, ?-] do
    case {Integer.parse(hours), Integer.parse(minutes)} do
      {{h, ""}, {m, ""}} when h <= 23 and m <= 59 ->
        offset = (h * 3600 + m * 60) * if(sign == ?-, do: -1, else: 1)
        {:ok, DateTime.add(instant, offset, :second)}

      _ ->
        {:error, {:invalid_zone, <<sign, hours::binary, ?:, minutes::binary>>}}
    end
  end

  defp in_zone(%DateTime{} = instant, zone) do
    case DateTime.shift_zone(instant, zone) do
      {:ok, %DateTime{} = local} -> {:ok, local}
      {:error, _reason} -> {:error, {:invalid_zone, zone}}
    end
  end

  defp resolve(:easter, year, _calendar),
    do: iso_date(Calendars.easter(year), :easter)

  defp resolve(:orthodox_easter, year, _calendar),
    do: iso_date(Calendars.orthodox_easter(year), :orthodox_easter)

  defp resolve({:equinox, event}, year, _calendar), do: dated(Astro.equinox(year, event))
  defp resolve({:solstice, event}, year, _calendar), do: dated(Astro.solstice(year, event))
  defp resolve(:new_moon, year, _calendar), do: new_moon(year)
  defp resolve({:solar_term, number}, year, calendar), do: solar_term(number, year, calendar)

  defp dated({:ok, %DateTime{} = datetime}), do: {:ok, DateTime.to_date(datetime)}
  defp dated({:error, _reason} = error), do: error

  defp new_moon(year) do
    with {:ok, %Date{} = start} <- Date.new(year, 1, 1),
         {:ok, %DateTime{} = datetime} <- Astro.date_time_new_moon_at_or_after(start) do
      {:ok, DateTime.to_date(datetime)}
    end
  end

  defp iso_date(%Date{} = date, event) do
    case Date.convert(date, Calendars.default()) do
      {:ok, %Date{} = converted} -> {:ok, converted}
      _error -> {:error, {:uncomputable_event, event}}
    end
  end

  defp solar_term(number, year, calendar) do
    if Calendars.calendar?(calendar),
      do: a_solar_term(Calendars.solar_term(calendar, number, year), number, calendar),
      else: {:error, {:no_solar_terms, calendar}}
  end

  defp a_solar_term({:ok, %Date{} = date}, number, _calendar),
    do: iso_date(date, {:solar_term, number})

  defp a_solar_term({:error, :undefined}, _number, calendar),
    do: {:error, {:no_solar_terms, calendar}}

  defp a_solar_term(_other, number, _calendar),
    do: {:error, {:uncomputable_event, {:solar_term, number}}}

  defp resolve_registered(name, year, calendar) do
    Enum.find_value(resolvers(), {:error, {:unknown_event, name}}, fn resolver ->
      if name in resolver.known(), do: a_date(resolver.date(name, year, calendar))
    end)
  end

  defp a_date({:ok, %Date{}} = date), do: date
  defp a_date({:error, _reason} = error), do: error
  defp a_date(given), do: {:error, {:not_a_date, given}}

  defp resolvers, do: List.wrap(Application.get_env(:ex_tempo, :event_resolvers, []))
end
