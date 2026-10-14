defmodule Tempo.Clock.Test do
  @moduledoc """
  A clock for tests: the current time pinned in the calling process.

  A test pins the time before it exercises code that reads the current
  time through `Tempo.utc_now/0`, `Tempo.now/1`, `Tempo.utc_today/0` or
  `Tempo.today/1`:

      test "renews a subscription at renewal time" do
        Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
        assert Subscription.should_renew?(subscription)
      end

  `put/1` makes this the clock of the calling process, so no
  configuration is needed. A suite that names it in `config/test.exs`
  (`config :ex_tempo, clock: Tempo.Clock.Test`), as Tempo 1.6 asked, is
  read the same way, and a process that asks the time before it pins one
  is a `Tempo.ClockError` rather than the system's time.

  The time is held in the process dictionary, so each test has its own,
  and tests run with `async: true` do not see one another's. `advance/1`
  moves it on, and `reset/0` clears it.

  """

  @behaviour Tempo.Clock

  alias Tempo.ClockError

  @now {__MODULE__, :now}
  @clock {Tempo.Clock, :clock}

  @doc """
  Pins the time of the calling process, and makes this its clock.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` in any zone. It is held as the same
    instant in `Etc/UTC`.

  ### Returns

  * `:ok`.

  ### Examples

      iex> Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      :ok
      iex> Tempo.utc_now()
      ~o"2026-06-15T12:00:00Z"

  """
  @spec put(DateTime.t()) :: :ok
  def put(%DateTime{} = date_time) do
    Process.put(@now, DateTime.shift_zone!(date_time, "Etc/UTC"))
    Process.put(@clock, __MODULE__)
    :ok
  end

  def put(other),
    do: raise(ArgumentError, "the time is pinned as a DateTime, not #{inspect(other)}")

  @doc """
  Moves the pinned time on by a number of seconds, or back for a negative
  number.

  ### Arguments

  * `seconds` is an integer.

  ### Returns

  * `:ok`. Raises a `Tempo.ClockError` in a process that has pinned no
    time.

  ### Examples

      iex> Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      iex> Tempo.Clock.Test.advance(3600)
      :ok
      iex> Tempo.Clock.Test.utc_now()
      ~U[2026-06-15 13:00:00Z]

  """
  @spec advance(integer()) :: :ok
  def advance(seconds) when is_integer(seconds) do
    Process.put(@now, DateTime.add(utc_now(), seconds, :second))
    :ok
  end

  def advance(other),
    do: raise(ArgumentError, "the clock is moved by whole seconds, not #{inspect(other)}")

  @doc """
  Clears the pinned time from the calling process, and with it this
  process's choice of this clock.

  ### Returns

  * `:ok`.

  ### Examples

      iex> Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      iex> Tempo.Clock.Test.reset()
      :ok
      iex> Tempo.Clock.clock()
      Tempo.Clock.System

  """
  @spec reset() :: :ok
  def reset do
    Process.delete(@now)
    if Process.get(@clock) == __MODULE__, do: Process.delete(@clock)
    :ok
  end

  @doc """
  The time pinned in the calling process.

  ### Returns

  * The pinned `t:DateTime.t/0`, in `Etc/UTC`. Raises a
    `Tempo.ClockError` in a process that has pinned none.

  ### Examples

      iex> Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      iex> Tempo.Clock.Test.utc_now()
      ~U[2026-06-15 12:00:00Z]

  """
  @impl true
  @spec utc_now() :: DateTime.t()
  def utc_now do
    case Process.get(@now) do
      %DateTime{} = now -> now
      nil -> raise ClockError.exception(clock: __MODULE__, reason: :not_pinned)
    end
  end
end
