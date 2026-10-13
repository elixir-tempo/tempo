defmodule Tempo.Clock.System do
  @moduledoc """
  Default implementation of `Tempo.Clock` using Erlang's system
  time via `DateTime.utc_now/0`.

  Applications that need a deterministic clock for testing should
  configure `Tempo.Clock.Test` instead (see its module doc).

  """

  @behaviour Tempo.Clock

  @impl true
  def utc_now do
    DateTime.utc_now()
  end
end
