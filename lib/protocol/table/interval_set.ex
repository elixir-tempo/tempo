if Code.ensure_loaded?(Table.Reader) do
  defimpl Table.Reader, for: Tempo.IntervalSet do
    # A bounded set is a table of its members: each member's `from` and `to`,
    # then a column for every metadata key the members carry, in the order
    # they first appear, `nil` where a member has none. A lazy set is not
    # tabular: its rows never end.
    alias Tempo.Interval
    alias Tempo.IntervalSet

    def init(set) do
      if IntervalSet.bounded?(set) do
        members = IntervalSet.members(set)
        keys = metadata_keys(members)
        metadata = %{columns: [:from, :to | keys], count: length(members)}

        {:rows, metadata, Enum.map(members, &row(&1, keys))}
      else
        :none
      end
    end

    defp metadata_keys(members) do
      members
      |> Enum.flat_map(&(&1 |> Tempo.metadata() |> Map.keys()))
      |> Enum.uniq()
    end

    defp row(member, keys) do
      metadata = Tempo.metadata(member)
      [Interval.from(member), Interval.to(member) | Enum.map(keys, &Map.get(metadata, &1))]
    end
  end
end
