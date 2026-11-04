defmodule Tempo.Application do
  @moduledoc false

  # Starts Tempo's supervision tree, unless a host supervises it itself
  # (`Tempo.Supervisor`) and sets `runtime: false`.

  use Application

  @impl true
  def start(_type, _args) do
    Tempo.Supervisor.start_link([])
  end
end
