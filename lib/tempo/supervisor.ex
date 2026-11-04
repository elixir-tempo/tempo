defmodule Tempo.Supervisor do
  @moduledoc """
  Tempo's supervision tree: every process Tempo runs is started under it.

  As it starts, it reads the time zone database the application configures
  (`Tempo.time_zone_database/0`) and builds the table of every zone the
  database lists the changes of, through the end of its list (September 2032
  for `tz`), once, in `:persistent_term`; it takes about 20 ms for `tz`'s
  zones. The database is Tempo's for as long as the tree runs: a database
  configured or updated afterwards is Tempo's once it is restarted.

  A question past the end of a zone's table, of a zone the database lists no
  changes for, or of a database that lists none, is answered by a table
  built from the database on the first such question and grown where a
  question reaches past it. Those tables are kept in an ETS table owned by
  the tree's one process.

  ### Supervision

  Tempo's application starts this supervisor, so an application that adds
  `:ex_tempo` to its dependencies and does nothing more has Tempo's processes
  running:

      def deps do
        [{:ex_tempo, "~> 2.5"}]
      end

  An application that supervises Tempo itself sets `runtime: false`, so that
  Tempo's application does not start, and lists `Tempo.Supervisor` in its own
  supervision tree:

      def deps do
        [{:ex_tempo, "~> 2.5", runtime: false}]
      end

      children = [
        Tempo.Supervisor
      ]

  The supervisor takes no options. Tempo's processes depend on no other
  application having been started. Where they are not running, Tempo still
  answers every question of a zone, reading the zone's changes from the
  database each time: correctly, but tens of microseconds a question, and
  tens of milliseconds for a date past the end of the database's listed
  changes (2032 for `tz`).

  """

  use Supervisor

  alias Tempo.Zone.Store

  @doc """
  Starts Tempo's supervision tree.

  ### Arguments

  * `options` is a keyword list, unused, accepted so that the supervisor can
    be listed as `Tempo.Supervisor` or `{Tempo.Supervisor, []}` in a
    supervision tree.

  ### Returns

  * `{:ok, pid}`, or

  * `{:error, {:already_started, pid}}` when Tempo's supervision tree is
    already running, as it is when Tempo's application has started.

  ### Examples

      iex> {:error, {:already_started, _pid}} = Tempo.Supervisor.start_link([])

  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(options \\ []) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Whether Tempo's processes are running, so that a zone's table is kept
  between questions of it.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Tempo.Supervisor.running?()
      true

  """
  @spec running?() :: boolean()
  def running? do
    Store.running?()
  end

  @impl true
  def init(_options) do
    children = [
      Tempo.Zone.Table,
      Tempo.Zone.Store
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
