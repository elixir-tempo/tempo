defmodule Tempo.Zone.Store do
  @moduledoc false

  # The owner of the ETS table each named zone's table of offset changes is
  # kept in (`Tempo.Zone.Table`), a child of `Tempo.Supervisor`. Any process
  # reads and writes the table; it lasts as long as this process does. Where
  # the store is not running, a zone's table is built for each question and
  # kept nowhere.

  use GenServer

  @table __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc "Whether the store is running, so that zone tables are kept between questions."
  @spec running?() :: boolean()
  def running? do
    :ets.whereis(@table) != :undefined
  end

  # The ETS table belongs to this process and goes with it: a store that is
  # restarted, or stopped by its host, takes the table away between a check
  # and a read, and ETS raises for a table that is gone. That is answered as
  # a store not running, never as a crash of the process asking.

  @doc "The table kept under a key, or `:error` where none is or the store is not running."
  @spec fetch(term()) :: {:ok, term()} | :error
  def fetch(key) do
    if running?() do
      looked_up(key)
    else
      :error
    end
  end

  @doc "Keeps a table under a key where the store is running, and returns it."
  @spec keep(term(), term()) :: term()
  def keep(key, table) do
    if running?() do
      inserted(key, table)
    end

    table
  end

  defp looked_up(key) do
    fetched(:ets.lookup(@table, key))
  rescue
    ArgumentError -> :error
  end

  defp inserted(key, table) do
    :ets.insert(@table, {key, table})
  rescue
    ArgumentError -> false
  end

  defp fetched([{_key, table}]) do
    {:ok, table}
  end

  defp fetched([]) do
    :error
  end

  @impl true
  def init(_options) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, nil}
  end
end
