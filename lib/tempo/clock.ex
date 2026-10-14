defmodule Tempo.Clock do
  @moduledoc """
  A behaviour that gives Tempo the current time.

  `Tempo.utc_now/0`, `Tempo.now/1`, `Tempo.utc_today/0` and `Tempo.today/1`
  ask the clock configured under `:ex_tempo, :clock`, which by default is
  `Tempo.Clock.System` and answers with `DateTime.utc_now/0`. A test swaps
  in its own for the calling process with
  `Process.put({Tempo.Clock, :clock}, MyClock)`, which leaves concurrent
  tests their own.

  """

  @doc "The current time as a `t:DateTime.t/0` in `Etc/UTC`."
  @callback utc_now() :: DateTime.t()

  @doc """
  The clock in use: the calling process's, else the application's, else
  `Tempo.Clock.System`.

  ### Returns

  * The module of the clock in use, one that implements `Tempo.Clock`.

  ### Examples

      iex> Tempo.Clock.clock()
      Tempo.Clock.System

  """
  @spec clock() :: module()
  def clock do
    Process.get({__MODULE__, :clock}) ||
      Application.get_env(:ex_tempo, :clock, Tempo.Clock.System)
  end
end
