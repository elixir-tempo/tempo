defmodule Tempo.Clock.System do
  @moduledoc """
  The default `Tempo.Clock`: the system's time, from `DateTime.utc_now/0`.

  """

  @behaviour Tempo.Clock

  @impl true
  def utc_now, do: DateTime.utc_now()
end
