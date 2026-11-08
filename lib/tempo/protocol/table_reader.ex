if Code.ensure_loaded?(Table.Reader) do
  defimpl Table.Reader, for: Tempo do
    @moduledoc false

    # A bounded plural expression (a set, a one-of set, a recurrence with an
    # end, a value with a list) is a table of its members as
    # `Tempo.members/2` gives them: each member's `from` and `to`, written as
    # the reader reads an interval's ends (law 9), then a column for every
    # metadata key the members carry, in the order they first appear, `nil`
    # where a member has none. A key named `:from` or `:to` is left out, its
    # column being the member's end. A singular expression (one value, one
    # span) and an unbounded one are not tabular.

    alias Tempo.Spans

    @ends [:from, :to]

    def init(%Tempo{} = expression) do
      if tabular?(expression) do
        rows(Tempo.members(expression))
      else
        :none
      end
    end

    defp tabular?(expression) do
      not Spans.singular?(expression) and Tempo.bounded?(expression)
    end

    defp rows({:ok, members}) do
      keys = metadata_keys(members)
      metadata = %{columns: @ends ++ keys, count: length(members)}

      {:rows, metadata, Stream.map(members, &row(&1, keys))}
    end

    defp rows({:error, _exception}) do
      :none
    end

    defp metadata_keys(members) do
      members
      |> Enum.flat_map(&Map.keys(Tempo.metadata(&1)))
      |> Enum.uniq()
      |> Enum.reject(&(&1 in @ends))
    end

    defp row(member, keys) do
      {from, to} = ends(member)
      metadata = Tempo.metadata(member)

      [from, to | Enum.map(keys, &Map.get(metadata, &1))]
    end

    defp ends(%Tempo{form: {:span, from, to}}) do
      {from, to}
    end

    defp ends(member) do
      member
      |> Tempo.to_interval()
      |> interval_ends()
    end

    defp interval_ends({:ok, %Tempo{form: {:span, from, to}}}) do
      {from, to}
    end

    defp interval_ends(_other) do
      {nil, nil}
    end
  end
end
