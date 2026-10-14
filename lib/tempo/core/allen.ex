defmodule Tempo.Allen do
  @moduledoc """
  Allen's thirteen relations between two spans, their inverses and their
  composition, and the everyday predicates as sets of them.

  A span is `[from, to)`. The relation of two spans is read from four
  comparisons, start against start, end against end, the first's end against
  the second's start and the first's start against the second's end
  (`relation/2`); every pair of spans stands in exactly one relation. The
  composition table is derived from the classifier when this module compiles,
  so the two cannot disagree. The everyday predicates (`before?/2`, `within?/2`,
  ...) are the sets of relations `Tempo.before?/2` and its companions answer
  by for two single spans.

  """

  alias Tempo.Allen.Classifier
  alias Tempo.ConversionError

  @relations [
    :precedes,
    :meets,
    :overlaps,
    :finished_by,
    :contains,
    :starts,
    :equals,
    :started_by,
    :during,
    :finishes,
    :overlapped_by,
    :met_by,
    :preceded_by
  ]

  @inverses %{
    precedes: :preceded_by,
    meets: :met_by,
    overlaps: :overlapped_by,
    finished_by: :finishes,
    contains: :during,
    starts: :started_by,
    equals: :equals,
    started_by: :starts,
    during: :contains,
    finishes: :finished_by,
    overlapped_by: :overlaps,
    met_by: :meets,
    preceded_by: :precedes
  }

  # The predicate vocabulary, each a set of relations. This is the one table.
  @predicates %{
    before: [:precedes, :meets],
    after: [:met_by, :preceded_by],
    adjacent: [:meets, :met_by],
    within: [:equals, :starts, :during, :finishes],
    contains: [:equals, :started_by, :contains, :finished_by],
    disjoint: [:precedes, :meets, :met_by, :preceded_by],
    overlaps: @relations -- [:precedes, :meets, :met_by, :preceded_by],
    equal: [:equals]
  }

  # Two spans in each relation, for the documentation of its predicate.
  @examples [
    precedes: {{1, 2}, {3, 4}},
    meets: {{1, 3}, {3, 5}},
    overlaps: {{1, 4}, {3, 6}},
    finished_by: {{1, 5}, {3, 5}},
    contains: {{1, 5}, {2, 3}},
    starts: {{1, 3}, {1, 5}},
    equals: {{1, 3}, {1, 3}},
    started_by: {{1, 5}, {1, 3}},
    during: {{2, 3}, {1, 5}},
    finishes: {{3, 5}, {1, 5}},
    overlapped_by: {{3, 6}, {1, 4}},
    met_by: {{3, 5}, {1, 3}},
    preceded_by: {{3, 4}, {1, 2}}
  ]

  @type relation ::
          :precedes
          | :meets
          | :overlaps
          | :finished_by
          | :contains
          | :starts
          | :equals
          | :started_by
          | :during
          | :finishes
          | :overlapped_by
          | :met_by
          | :preceded_by

  @type predicate ::
          :before | :after | :adjacent | :within | :contains | :disjoint | :overlaps | :equal

  @typedoc "A span as two positions on one frame, `{from, to}`, half-open."
  @type span :: {integer(), integer()}

  @doc """
  The thirteen relations, in Allen's order.

  ### Returns

  * A list of the thirteen `t:relation/0` atoms.

  ### Examples

      iex> length(Tempo.Allen.relations())
      13

      iex> hd(Tempo.Allen.relations())
      :precedes

  """
  @spec relations() :: [relation(), ...]
  def relations, do: @relations

  @doc """
  The relation of one span to another, from four comparisons.

  ### Arguments

  * `a` and `b` are each a `t:Tempo.t/0` that names one span, or each a
    `t:span/0` of two positions on one frame.

  ### Returns

  * One of the thirteen `t:relation/0` atoms. For two expressions it is
    what `Tempo.relation/2` answers, and the error that would return is
    raised; a value that is neither an expression nor a span raises a
    `Tempo.ConversionError`.

  ### Examples

      iex> Tempo.Allen.relation(~o"2026-01", ~o"2026-02")
      :meets

      iex> Tempo.Allen.relation({1, 3}, {3, 5})
      :meets

      iex> Tempo.Allen.relation({1, 5}, {2, 3})
      :contains

      iex> Tempo.Allen.relation({2, 3}, {1, 5})
      :during

  """
  @spec relation(span() | Tempo.t(), span() | Tempo.t()) :: relation()
  def relation(%Tempo{} = a, %Tempo{} = b) do
    case Tempo.relation(a, b) do
      {:error, exception} -> raise exception
      relation -> relation
    end
  end

  def relation({_, _} = a, {_, _} = b), do: Classifier.relation(a, b)

  def relation(a, b) do
    neither = if span_or_expression?(a), do: b, else: a
    raise ConversionError.exception(value: neither, reason: :not_an_expression)
  end

  defp span_or_expression?(%Tempo{}), do: true
  defp span_or_expression?({from, to}) when is_integer(from) and is_integer(to), do: true
  defp span_or_expression?(_other), do: false

  @doc """
  The inverse of a relation: the relation of the second span to the first.

  ### Arguments

  * `relation` is a `t:relation/0`.

  ### Returns

  * The `t:relation/0` the second span stands in to the first.

  ### Examples

      iex> Tempo.Allen.inverse(:precedes)
      :preceded_by

      iex> Tempo.Allen.inverse(:equals)
      :equals

  """
  @spec inverse(relation()) :: relation()
  def inverse(relation) when is_map_key(@inverses, relation), do: Map.fetch!(@inverses, relation)
  def inverse(other), do: no_relation!(other)

  # The composition table, derived from the classifier: for every placing of
  # three spans on a short line, the relation of the first to the third is
  # possible given the first's to the second and the second's to the third.
  @composition (for a_from <- 0..6,
                    a_to <- (a_from + 1)..7,
                    b_from <- 0..6,
                    b_to <- (b_from + 1)..7,
                    c_from <- 0..6,
                    c_to <- (c_from + 1)..7,
                    reduce: %{} do
                  table ->
                    key =
                      {Classifier.relation({a_from, a_to}, {b_from, b_to}),
                       Classifier.relation({b_from, b_to}, {c_from, c_to})}

                    Map.update(
                      table,
                      key,
                      [Classifier.relation({a_from, a_to}, {c_from, c_to})],
                      &Enum.uniq([Classifier.relation({a_from, a_to}, {c_from, c_to}) | &1])
                    )
                end)
               |> Map.new(fn {key, relations} ->
                 {key, Enum.sort_by(relations, &Enum.find_index(@relations, fn r -> r == &1 end))}
               end)

  @doc """
  The composition of two relations: the relations a first span may stand in
  to a third, given its relation to a second and the second's to the third.

  ### Arguments

  * `first` is the `t:relation/0` of the first span to the second.

  * `second` is the `t:relation/0` of the second span to the third.

  ### Returns

  * The `t:relation/0` atoms the first span may stand in to the third, in
    Allen's order.

  ### Examples

      iex> Tempo.Allen.compose(:precedes, :precedes)
      [:precedes]

      iex> Tempo.Allen.compose(:equals, :during)
      [:during]

      iex> Tempo.Allen.compose(:overlaps, :overlaps)
      [:precedes, :meets, :overlaps]

  """
  @spec compose(relation(), relation()) :: [relation(), ...]
  def compose(first, second) when first in @relations and second in @relations,
    do: Map.fetch!(@composition, {first, second})

  def compose(first, second) when first in @relations, do: no_relation!(second)
  def compose(first, _second), do: no_relation!(first)

  @doc """
  The relations an everyday predicate stands for.

  ### Arguments

  * `name` is a `t:predicate/0`, or a `t:relation/0`, which stands for
    itself.

  ### Returns

  * The `t:relation/0` atoms the predicate holds for.

  ### Examples

      iex> Tempo.Allen.predicate(:within)
      [:equals, :starts, :during, :finishes]

      iex> Tempo.Allen.predicate(:meets)
      [:meets]

  """
  @spec predicate(predicate() | relation()) :: [relation(), ...]
  def predicate(name) when is_map_key(@predicates, name), do: Map.fetch!(@predicates, name)
  def predicate(relation) when relation in @relations, do: [relation]

  def predicate(other),
    do:
      raise(
        ArgumentError,
        "#{inspect(other)} is none of the predicates #{inspect(Map.keys(@predicates))} or Allen's relations"
      )

  @spec no_relation!(term()) :: no_return()
  defp no_relation!(other),
    do: raise(ArgumentError, "#{inspect(other)} is not one of Allen's thirteen relations")

  @doc """
  The everyday predicates: `:before`, `:after`, `:adjacent`, `:within`,
  `:contains`, `:disjoint`, `:overlaps` and `:equal`.

  ### Returns

  * A list of the `t:predicate/0` atoms.

  ### Examples

      iex> :within in Tempo.Allen.predicates()
      true

  """
  @spec predicates() :: [predicate(), ...]
  def predicates, do: Map.keys(@predicates)

  @doc """
  Whether a predicate or a relation holds between two spans.

  ### Arguments

  * `name` is a `t:predicate/0` or a `t:relation/0`.

  * `a` and `b` are each a `t:Tempo.t/0` that names one span, or each a
    `t:span/0`, as for `relation/2`.

  ### Returns

  * `true` when the relation of `a` to `b` is one the name stands for, and
    `false` when it is not.

  ### Examples

      iex> Tempo.Allen.holds?(:before, {1, 3}, {3, 5})
      true

      iex> Tempo.Allen.holds?(:precedes, {1, 3}, {3, 5})
      false

  """
  @spec holds?(predicate() | relation(), span() | Tempo.t(), span() | Tempo.t()) :: boolean()
  def holds?(name, a, b), do: relation(a, b) in predicate(name)

  for {relation, {a, b}} <- @examples do
    @doc """
    Whether the first span #{String.replace(Atom.to_string(relation), "_", " ")} the
    second, under Allen's own name.

    ### Arguments

    * `a` and `b` are each a `t:Tempo.t/0` that names one span, or each a
      `t:span/0`, as for `relation/2`.

    ### Returns

    * `true` when the relation of `a` to `b` is `#{inspect(relation)}`, and
      `false` when it is not.

    ### Examples

        iex> Tempo.Allen.#{relation}?(#{inspect(a)}, #{inspect(b)})
        true

    """
    @spec unquote(:"#{relation}?")(span() | Tempo.t(), span() | Tempo.t()) :: boolean()
    def unquote(:"#{relation}?")(a, b), do: relation(a, b) == unquote(relation)
  end
end
