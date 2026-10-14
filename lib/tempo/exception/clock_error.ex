defmodule Tempo.ClockError do
  @moduledoc """
  A clock that cannot tell the time.

  * `:clock` is the clock asked.

  * `:reason` is `:not_pinned` for `Tempo.Clock.Test` asked the time, or
    moved, in a process that has pinned none.

  """

  defexception [:clock, :reason]

  @type t :: %__MODULE__{clock: module(), reason: :not_pinned}

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{clock: clock, reason: :not_pinned}) do
    "#{inspect(clock)} has no time pinned in this process: " <>
      "call #{inspect(clock)}.put/1 with a DateTime before reading the current time"
  end
end
