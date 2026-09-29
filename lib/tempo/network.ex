defmodule Tempo.Network do
  @moduledoc """
  A chronological network — a set of time-periods together with the
  sequences and relations that constrain them.

  This is the top-level model of the ChronoLog scheme (Levy et al.
  2020). A network is built incrementally and then handed to
  `Tempo.Network.Solver` to check consistency or to propagate the
  constraints to every period's narrowest bounds.

  A network holds:

  * `periods` — a map of `id => t:Tempo.Network.TimePeriod.t/0`;

  * `sequences` — ordered lists of period ids with no gaps between
    consecutive members (`end(pᵢ) = start(pᵢ₊₁)`);

  * `relations` — `t:Tempo.Network.Relation.t/0` constraints between
    pairs of periods;

  * `errors` — what the builders could not add, in order.

  The primary public API is `new/0`, `add_period/2,3`, `add_sequence/2`,
  and `add_relation/4,5`. The builders never raise: an option they do
  not take, or a value they cannot read, is recorded in `errors`, and
  every `Tempo.Network.Solver` function returns the first of them as
  `{:error, reason}` (its predicates raise it).

  """

  alias Tempo.Network.{Relation, TimePeriod}

  @type t :: %__MODULE__{
          periods: %{optional(term()) => TimePeriod.t()},
          sequences: [[term()]],
          relations: [Relation.t()],
          errors: [Exception.t()]
        }

  defstruct periods: %{}, sequences: [], relations: [], errors: []

  @doc """
  An empty network.

  ### Returns

  * an empty `t:Tempo.Network.t/0`.

  ### Examples

      iex> network = Tempo.Network.new()
      iex> {map_size(network.periods), network.sequences, network.relations}
      {0, [], []}

  """
  def new, do: %__MODULE__{}

  @doc """
  Add a time-period to the network.

  ### Arguments

  * `network` is the network to extend.

  * `period` is a `t:Tempo.Network.TimePeriod.t/0`.

  ### Returns

  * the network with `period` added (replacing any period of the same
    id), or with an error recorded when `period` is not a time-period.

  ### Examples

      iex> {:ok, period} = Tempo.Network.TimePeriod.new(:k1, name: "King 1")
      iex> network = Tempo.Network.new() |> Tempo.Network.add_period(period)
      iex> Map.keys(network.periods)
      [:k1]

  """
  @spec add_period(t(), TimePeriod.t()) :: t()
  def add_period(%__MODULE__{} = network, %TimePeriod{id: id} = period) do
    %{network | periods: Map.put(network.periods, id, period)}
  end

  def add_period(%__MODULE__{} = network, period) do
    record(
      network,
      "Tempo.Network.add_period/2 takes a Tempo.Network.TimePeriod, not #{inspect(period)}."
    )
  end

  @doc """
  Build a time-period from `id` and `options` and add it to the network.

  A convenience wrapping `Tempo.Network.TimePeriod.new/2` and
  `add_period/2`.

  ### Arguments

  * `network` is the network to extend.

  * `id` is any term uniquely identifying the period.

  * `options` is a keyword list of options.

  ### Options

  * The options of `Tempo.Network.TimePeriod.new/2`: `:name`, `:from`,
    `:to`, `:duration` and `:metadata`.

  ### Returns

  * the network with the new period added, or with the error
    `Tempo.Network.TimePeriod.new/2` returns recorded.

  ### Examples

      iex> network = Tempo.Network.new() |> Tempo.Network.add_period(:k1, from: {:not_before, ~o"1200Y"})
      iex> network.periods[:k1].earliest_start
      ~o"1200Y"

  """
  @spec add_period(t(), term(), keyword()) :: t()
  def add_period(%__MODULE__{} = network, id, options) do
    case TimePeriod.new(id, options) do
      {:ok, period} -> add_period(network, period)
      {:error, exception} -> record_error(network, exception)
    end
  end

  @doc """
  Add a gap-free sequence of periods.

  The periods, given by id in chronological order, are consecutive:
  each one ends exactly where the next begins. Normalisation expands a
  sequence into `immediately_precedes` constraints between adjacent
  members.

  ### Arguments

  * `network` is the network to extend.

  * `period_ids` is an ordered list of period ids.

  ### Returns

  * the network with the sequence recorded, or with an error recorded
    when `period_ids` is not a list.

  ### Examples

      iex> network = Tempo.Network.new() |> Tempo.Network.add_sequence([:k1, :k2, :k3])
      iex> network.sequences
      [[:k1, :k2, :k3]]

  """
  @spec add_sequence(t(), [term()]) :: t()
  def add_sequence(%__MODULE__{} = network, period_ids) when is_list(period_ids) do
    %{network | sequences: network.sequences ++ [period_ids]}
  end

  def add_sequence(%__MODULE__{} = network, period_ids) do
    record(
      network,
      "Tempo.Network.add_sequence/2 takes a list of period ids, not #{inspect(period_ids)}."
    )
  end

  @doc """
  Add a chronological relation between two periods.

  ### Arguments

  * `network` is the network to extend.

  * `type` is a relation type (see `Tempo.Network.Relation`).

  * `from` and `to` are the ids of the related periods, read as
    "`from` *type* `to`".

  * `options` is a keyword list of options.

  ### Options

  * `:metadata` is an arbitrary map carried with the relation.

  ### Returns

  * the network with the relation added, or with an error recorded for
    a type `Tempo.Network.Relation` does not define or an option it
    does not take.

  ### Examples

      iex> network = Tempo.Network.new() |> Tempo.Network.add_relation(:included_in, :s1, :k1)
      iex> [relation] = network.relations
      iex> {relation.type, relation.from, relation.to}
      {:included_in, :s1, :k1}

  """
  @spec add_relation(t(), Relation.relation_type(), term(), term(), keyword()) :: t()
  def add_relation(%__MODULE__{} = network, type, from, to, options \\ []) do
    cond do
      not Relation.valid_type?(type) ->
        record(
          network,
          "Tempo.Network.add_relation/5 does not know the relation #{inspect(type)}."
        )

      not relation_options?(options) ->
        record(
          network,
          "Tempo.Network.add_relation/5 takes one option, :metadata, a map, not " <>
            "#{inspect(options)}."
        )

      true ->
        %{network | relations: network.relations ++ [Relation.new(type, from, to, options)]}
    end
  end

  defp relation_options?(options) do
    Keyword.keyword?(options) and Keyword.keys(options) -- [:metadata] == [] and
      is_map(Keyword.get(options, :metadata, %{}))
  end

  @doc """
  The list of all period ids referenced by the network — those with a
  registered period plus any named only by a sequence or relation.

  ### Returns

  * a sorted-by-insertion list of unique period ids.

  ### Examples

      iex> network = Tempo.Network.new() |> Tempo.Network.add_period(:k1, []) |> Tempo.Network.add_relation(:before, :k1, :k2)
      iex> Enum.sort(Tempo.Network.period_ids(network))
      [:k1, :k2]

  """
  @spec period_ids(t()) :: [term()]
  def period_ids(%__MODULE__{} = network) do
    from_periods = Map.keys(network.periods)
    from_sequences = List.flatten(network.sequences)
    from_relations = Enum.flat_map(network.relations, &[&1.from, &1.to])

    (from_periods ++ from_sequences ++ from_relations)
    |> Enum.uniq()
  end

  @doc false
  # The first thing the builders could not add, or a relation of a type
  # the solver cannot read in a network built without them.
  @spec check(t()) :: :ok | {:error, Exception.t()}
  def check(%__MODULE__{errors: [error | _rest]}), do: {:error, error}

  def check(%__MODULE__{relations: relations}) do
    case Enum.find(relations, &(not Relation.valid_type?(&1.type))) do
      nil -> :ok
      relation -> {:error, ArgumentError.exception("Unknown relation #{inspect(relation.type)}.")}
    end
  end

  @doc false
  # Record an error a builder met, for the solver to return.
  @spec record_error(t(), Exception.t()) :: t()
  def record_error(%__MODULE__{} = network, exception) do
    %{network | errors: network.errors ++ [exception]}
  end

  defp record(network, message), do: record_error(network, ArgumentError.exception(message))
end
