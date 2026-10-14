defmodule Tempo.Event.Resolver do
  @moduledoc """
  A behaviour for a consumer's own computed events, written `(name)e` in a
  selection beside the built-ins of `Tempo.Event`.

  A resolver names the events it owns with `known/0` and computes each one's
  date with `date/3`, and is registered with
  `config :ex_tempo, :event_resolvers, [MyApp.Events]`. The registry is read
  each time a date is asked, so it may be set at compile time or at runtime;
  the first resolver whose `known/0` claims a name computes it.

      defmodule MyApp.Events do
        @behaviour Tempo.Event.Resolver

        @impl true
        def known, do: ["fiscal-year-start"]

        @impl true
        def date("fiscal-year-start", year, _calendar), do: Date.new(year, 4, 1)
        def date(_name, _year, _calendar), do: {:error, :unknown_event}
      end

  """

  @doc "The event names this resolver computes."
  @callback known() :: [String.t()]

  @doc """
  The date of a named event in a Gregorian year, `{:ok, date}` in
  `Calendar.ISO` or `{:error, reason}`. `Tempo.Event.date/3` returns the
  reason as that of a `Tempo.InvalidDateError`, and an exception as it is.
  """
  @callback date(name :: String.t(), year :: integer(), calendar :: module()) ::
              {:ok, Date.t()} | {:error, term()}
end
