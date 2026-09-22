defmodule Tempo.Event.Resolver do
  @moduledoc """
  A behaviour for registering consumer-defined `(name)E` computed events.

  Tempo ships a fixed set of computed events — Easter, the equinoxes and
  solstices, the first new moon of the year, and the 24 solar terms (see
  `Tempo.Event`). A consumer application adds its own — a fiscal calendar's
  quarter starts, a liturgical feast, any date fixed by an algorithm rather
  than by the calendar — by implementing this behaviour and registering the
  module:

      config :ex_tempo, :event_resolvers, [MyApp.Events]

  A resolver names the events it owns with `known/0` and computes each one's
  date with `date/3`. Once registered, the name is usable anywhere a built-in
  event is: `~o"R/../P1Y/FL(fiscal-year-start)EN"` materialises against a bound
  exactly as `(easter)E` does, and `Tempo.Event.known/0` lists it. A name no
  resolver claims resolves to nothing, so a recurrence over an unknown event
  yields zero occurrences rather than raising.

  The registry is read at materialise time, so `config :ex_tempo,
  :event_resolvers` can be set at compile time or at runtime, and several
  resolvers can be registered at once — the first whose `known/0` claims a name
  computes it.

  ### Example

      defmodule MyApp.Events do
        @behaviour Tempo.Event.Resolver

        @impl true
        def known, do: ["fiscal-year-start", "fiscal-q3"]

        @impl true
        def date("fiscal-year-start", year, _calendar), do: Date.new(year, 4, 1)
        def date("fiscal-q3", year, _calendar), do: Date.new(year, 10, 1)
        def date(_name, _year, _calendar), do: {:error, :unknown_event}
      end

  """

  @doc """
  Returns the event names this resolver can compute.

  ### Returns

  * A list of the lowercase event-name strings the resolver owns, each usable
    as `(name)E` in a selection.

  """
  @callback known() :: [String.t()]

  @doc """
  Computes the date of one of the resolver's events in a given year.

  Tempo calls this only for a `name` the resolver's `known/0` claims, once per
  candidate year while a recurrence is materialised.

  ### Arguments

  * `name` is the event name — one of those `known/0` returns.

  * `year` is the proleptic-Gregorian year the event falls in.

  * `calendar` is the calendar the surrounding recurrence is resolving in,
    passed for events whose date depends on it (a meridian, say). Resolvers
    that do not need it ignore it.

  ### Returns

  * `{:ok, date}` with the event's `Date`, in any calendar Tempo can convert
    from — `Calendar.ISO` is the usual choice.

  * `{:error, reason}` when the event cannot be computed for that year; Tempo
    turns it into zero occurrences. The callback returns a tagged tuple rather
    than raising, so a bad year never crashes the materialise path.

  """
  @callback date(name :: String.t(), year :: integer(), calendar :: module()) ::
              {:ok, Date.t()} | {:error, term()}
end
