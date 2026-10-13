defmodule Tempo.Clock.Test do
  @moduledoc """
  A process-local deterministic clock for use in tests.

  Configure Tempo to use this clock in `config/test.exs`:

      config :ex_tempo, clock: Tempo.Clock.Test

  Then in a test, pin the clock to a known instant before exercising
  any code that calls `Tempo.utc_now/0`, `Tempo.now/1`,
  `Tempo.utc_today/0`, or `Tempo.today/1`:

      test "renews a subscription at renewal time" do
        Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
        assert Subscription.should_renew?(subscription) == true
      end

  Time is stored in the calling process's dictionary. Each test gets
  its own pin and does not interfere with other tests running
  concurrently, provided the test uses `async: true` (which is the
  default for `ExUnit.Case`).

  If `utc_now/0` is called without a prior `put/1`, it raises so the
  test fails loudly rather than silently returning the system time.

  """

  @behaviour Tempo.Clock

  @process_key {__MODULE__, :now}

  @doc """
  Pin the test clock to the given `t:DateTime.t/0` in the calling
  process.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0`. It may be in any zone; it is
    converted to `Etc/UTC` before storage so that downstream
    `Tempo.now/1` sees the same UTC instant regardless of the
    caller's convenience zone.

  ### Returns

  * `:ok`.

  ### Examples

      iex> Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      :ok

  """
  @spec put(DateTime.t()) :: :ok
  def put(%DateTime{time_zone: "Etc/UTC"} = date_time) do
    Process.put(@process_key, date_time)
    :ok
  end

  def put(%DateTime{} = date_time) do
    Process.put(@process_key, DateTime.shift_zone!(date_time, "Etc/UTC"))
    :ok
  end

  @doc """
  Advance the pinned clock by an integer number of seconds. Raises
  if no time has been pinned.

  Useful for tests that exercise elapsed-time logic without
  re-pinning an absolute instant after each step.

  ### Arguments

  * `seconds` is a signed integer. Negative values move the clock
    backwards.

  ### Returns

  * `:ok`.

  ### Examples

      iex> Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      iex> Tempo.Clock.Test.advance(3600)
      :ok
      iex> Tempo.Clock.Test.utc_now()
      ~U[2026-06-15 13:00:00Z]

  """
  @spec advance(integer()) :: :ok
  def advance(seconds) when is_integer(seconds) do
    case Process.get(@process_key) do
      nil ->
        raise "Tempo.Clock.Test.advance/1 called before put/1. Pin a time first."

      %DateTime{} = now ->
        Process.put(@process_key, DateTime.add(now, seconds, :second))
        :ok
    end
  end

  @doc """
  Clear the pinned time from the calling process.

  Subsequent calls to `utc_now/0` will raise until a new `put/1` is
  made. Useful in `on_exit` callbacks to guarantee isolation.

  ### Returns

  * `:ok`.

  """
  @spec reset() :: :ok
  def reset do
    Process.delete(@process_key)
    :ok
  end

  @impl true
  def utc_now do
    case Process.get(@process_key) do
      nil ->
        raise "Tempo.Clock.Test has no time pinned in this process. " <>
                "Call `Tempo.Clock.Test.put/1` with a DateTime before using " <>
                "functions that read the current time."

      %DateTime{} = now ->
        now
    end
  end
end
