defmodule Tempo.Network.ChronoLog do
  @moduledoc """
  Decode a ChronoLog `.clog` file (the JSON export of ChronoLog 3) into
  a `t:Tempo.Network.t/0`.

  ChronoLog (Levy et al. 2020) is the reference implementation of the
  chronological-network scheme Tempo's `Tempo.Network` adopts. Its
  saved models — sequences of periods, lone periods, events, and the
  synchronisms between them — exercise the same Simple Temporal Problem
  the Tempo solver builds, so a published ChronoLog model is an
  independent oracle for validating Tempo's network code.

  This decoder reads the case-study `.clog` files bundled under
  `test/support/data/chronolog/` and is used only by the test suite; it
  is not part of Tempo's public API.

  ## Mapping

  A period's `durationLB`/`durationUB` become a Tempo duration bound.
  An event is a zero-duration period pinned to its `dateLB`..`dateUB`
  window. A `sequence` becomes a gap-free `Tempo.Network.add_sequence/2`.

  Synchronisms map to `Tempo.Network.Relation` types — the qualitative
  relations directly, the boundary inequalities to the `{:boundary, …}`
  relation, and delay synchronisms to the metric `{:delay, …}` relation.

  ## Provenance of the constraint semantics

  Each synchronism's exact constraint was read from the ChronoLog 3
  bytecode (`com.chronolog.synchronisms.*.update/3`). A delay
  synchronism with `beforeAfter: "a"` constrains `boundary1` of
  `period1` to lie `delay` units **after** `boundary2` of `period2`,
  with `mostLeast` selecting `==` (`"e"`), `≥` (`"l"`), or `≤` (`"m"`).

  """

  alias Tempo.Network

  @zero Tempo.from_iso8601!("P0Y")

  @doc """
  Decode the ChronoLog `.clog` file at `path` into a network.

  ### Arguments

  * `path` is the path to a ChronoLog 3 `.clog` (JSON) file.

  ### Returns

  * a `t:Tempo.Network.t/0`.

  """
  @spec from_file(Path.t()) :: Network.t()
  def from_file(path) do
    path |> File.read!() |> from_json()
  end

  @doc """
  Decode a ChronoLog `.clog` document (a JSON binary) into a network.

  ### Arguments

  * `json` is the binary contents of a ChronoLog 3 `.clog` file.

  ### Returns

  * a `t:Tempo.Network.t/0`.

  """
  @spec from_json(binary()) :: Network.t()
  def from_json(json) when is_binary(json) do
    data = :json.decode(json)

    Network.new()
    |> add_sequences(Map.get(data, "sequences", []))
    |> add_lone_periods(Map.get(data, "lonePeriods", []))
    |> add_events(Map.get(data, "events", []))
    |> add_synchronisms(Map.get(data, "synchronisms", []))
  end

  # --- periods, sequences, events --------------------------------

  defp add_sequences(network, sequences) do
    Enum.reduce(sequences, network, fn sequence, network ->
      ids = Enum.map(sequence["periods"], & &1["name"])

      sequence["periods"]
      |> Enum.reduce(network, fn period, network ->
        Network.add_period(network, period["name"], period_options(period))
      end)
      |> Network.add_sequence(ids)
    end)
  end

  defp add_lone_periods(network, periods) do
    Enum.reduce(periods, network, fn period, network ->
      Network.add_period(network, period["name"], period_options(period))
    end)
  end

  # An event is a point in time — a zero-duration period whose single
  # boundary is pinned to the event's date window.
  defp add_events(network, events) do
    Enum.reduce(events, network, fn event, network ->
      window = {event["dateLB"], event["dateUB"]}
      Network.add_period(network, event["name"], from: window, to: window, duration: @zero)
    end)
  end

  defp period_options(period) do
    case {period["durationLB"], period["durationUB"]} do
      {nil, nil} -> []
      {lower, lower} -> [duration: years(lower)]
      {lower, nil} -> [duration: {:at_least, years(lower)}]
      {nil, upper} -> [duration: {:at_most, years(upper)}]
      {lower, upper} -> [duration: {years(lower), years(upper)}]
    end
  end

  defp years(count), do: Tempo.from_iso8601!("P#{count}Y")

  # --- synchronisms ----------------------------------------------

  defp add_synchronisms(network, synchronisms) do
    Enum.reduce(synchronisms, network, &add_synchronism(&2, &1))
  end

  # A delay synchronism: period1.boundary1 is `delay` years after (or
  # before) period2.boundary2. "After" reads as "period2.boundary2 is
  # `delay` before period1.boundary1", which is Tempo's delay direction.
  defp add_synchronism(network, %{"type" => "Delay synchronism"} = synchronism) do
    comparison = comparison(synchronism["mostLeast"])
    boundary1 = boundary(synchronism["boundary1"])
    boundary2 = boundary(synchronism["boundary2"])
    delay = years(synchronism["delay"])
    period1 = synchronism["period1"]
    period2 = synchronism["period2"]

    case synchronism["beforeAfter"] do
      "a" ->
        relation = {:delay, boundary2, boundary1, comparison, delay}
        Network.add_relation(network, relation, period2, period1)

      "b" ->
        relation = {:delay, boundary1, boundary2, comparison, delay}
        Network.add_relation(network, relation, period1, period2)
    end
  end

  defp add_synchronism(network, %{"type" => type, "period1" => a, "period2" => b}) do
    Network.add_relation(network, relation_for(type), a, b)
  end

  # Qualitative synchronisms with a one-to-one Tempo relation.
  defp relation_for(type) when type in ["Equals", "Equality"], do: :equals
  defp relation_for("Starts with"), do: :synchronous_start
  defp relation_for("Ends with"), do: :synchronous_end
  defp relation_for(type) when type in ["Included in", "Is included in"], do: :included_in
  defp relation_for("Includes"), do: :includes

  # Single-boundary inequalities map to the boundary-comparison relation.

  # start(A) ≥ start(B).
  defp relation_for(type) when type in ["Starts after or at start of", "Starts after start of"],
    do: {:boundary, :start, :at_or_after, :start}

  # end(A) ≥ start(B).
  defp relation_for(type) when type in ["Ends after or at start of", "Ends after start of"],
    do: {:boundary, :end, :at_or_after, :start}

  # end(A) ≤ start(B).
  defp relation_for("Ends before or at start of"),
    do: {:boundary, :end, :at_or_before, :start}

  defp comparison("e"), do: :exactly
  defp comparison("l"), do: :at_least
  defp comparison("m"), do: :at_most

  defp boundary("s"), do: :start
  defp boundary("e"), do: :end
end
