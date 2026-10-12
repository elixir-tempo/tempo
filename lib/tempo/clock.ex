defmodule Tempo.Clock do
  @moduledoc """
  A behaviour for providing the current time to Tempo.

  All "now" queries in Tempo (`Tempo.utc_now/0`, `Tempo.now/1`,
  `Tempo.utc_today/0`, `Tempo.today/1`) go through the clock
  configured under `:ex_tempo, :clock`. The default is
  `Tempo.Clock.System`, which delegates to `DateTime.utc_now/0`.

  The indirection exists so tests can swap in a deterministic clock
  without stubbing the Erlang system time. `Tempo.Clock.Test` is a
  process-local stub suitable for `ExUnit` tests; see its module doc
  for the usage pattern.

  ### Configuring the clock

  Application-wide default in `config/test.exs`:

      config :ex_tempo, clock: Tempo.Clock.Test

  Process-local override (safer in `async: true` ExUnit suites —
  swaps the clock for the calling process only, leaving concurrent
  tests and doctests with the default clock):

      Process.put({Tempo.Clock, :clock}, Tempo.Clock.Test)

  In application code, use `Tempo.utc_now/0` etc. rather than calling
  the clock directly — the swap is transparent to callers.

  ### Implementing a custom clock

  A custom clock must return a `t:DateTime.t/0`. Implementations are
  free to read from a database, a time-service mock, or a
  distributed-system clock skew model. The one rule: the returned
  `DateTime` must be in UTC (i.e. `time_zone: "Etc/UTC"`, zero
  offset). Zone projection happens downstream in `Tempo.now/1`.

  """

  alias Tempo.Calendars

  @doc """
  Return the current UTC time as a `t:DateTime.t/0` in `Etc/UTC`.

  """
  @callback utc_now() :: DateTime.t()

  @doc false
  # The current UTC time from the configured clock (`:ex_tempo, :clock`,
  # `Tempo.Clock.System` unless another is set). The clock is a caller's
  # module, so its reading is a caller's value, and is given as Tempo works
  # with it.
  @spec do_utc_now() :: DateTime.t()
  def do_utc_now do
    Calendars.inside(clock().utc_now())
  end

  @doc """
  Return the currently configured clock module.

  Looks first at `Process.get({Tempo.Clock, :clock})` (the
  process-local override used by ExUnit setups), then falls back to
  `Application.get_env(:ex_tempo, :clock)`, defaulting to
  `Tempo.Clock.System` when neither is set.

  The process-local override means tests that install
  `Tempo.Clock.Test` do not leak that choice into unrelated
  concurrent processes — a non-test doctest sharing the VM continues
  to see the default system clock.

  """
  @spec clock() :: module()
  def clock do
    Process.get({__MODULE__, :clock}) ||
      Application.get_env(:ex_tempo, :clock, Tempo.Clock.System)
  end
end
