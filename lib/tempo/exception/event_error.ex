defmodule Tempo.EventError do
  @moduledoc """
  Exception returned, or raised by a bang function, when a computed event (`(easter)e`) has no date where a recurrence or a selection asks for one.

  `Tempo.to_interval/2` and `Tempo.select/2` return it in place of an answer with the event's occurrences missing: no occurrence would say that there is no equinox in a year, or that a misspelt event never happens.

  `:event` is the event's name as it was written, `:year` the year of the Gregorian calendar it was asked for, and `:reason` why it has no date there:

  * `:unknown_event` — no built-in event and no registered `Tempo.Event.Resolver` has the name; `Tempo.Event.known/0` lists those that are known. `:year` is `nil`.

  * `:year_out_of_range` — the year is outside those the event is computed for. An equinox and a solstice are computed from 1000 CE to 3000 CE.

  * `:unzoned_event` — a zone is written after the `@` of an event with no instant of its own, such as `(easter@+09:00)e`.

  * `{:invalid_zone, zone}` and `{:time_zone_database_required, zone}` — the zone is neither an IANA zone nor a `±HH:MM` offset, or it is an IANA zone and no time zone database is configured.

  * Any other term is the reason a registered resolver gave, or the reason a date it returned could not be read as one.

  """

  defexception [:event, :year, :reason]

  @type t :: %__MODULE__{
          event: String.t() | nil,
          year: integer() | nil,
          reason: term()
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{event: event, reason: :unknown_event}) do
    "No computed event is named #{inspect(event)}. `Tempo.Event.known/0` lists the names " <>
      "that are, the built-in events and those a registered `Tempo.Event.Resolver` claims."
  end

  def message(%__MODULE__{event: event, year: year, reason: :year_out_of_range}) do
    "The event #{inspect(event)} cannot be computed for the year #{year}, which is outside " <>
      "the years it is computed for."
  end

  def message(%__MODULE__{event: event, reason: :unzoned_event}) do
    "The event #{inspect(event)} names a zone, and it has no instant of its own to take a " <>
      "date in one: an equinox or a solstice does."
  end

  def message(%__MODULE__{event: event, year: year, reason: reason}) do
    "The event #{inspect(event)} cannot be computed for the year #{year}: #{inspect(reason)}"
  end
end
