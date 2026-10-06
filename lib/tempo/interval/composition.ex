defmodule Tempo.Interval.Composition do
  @moduledoc false

  # Allen's interval-algebra composition table (J. F. Allen, "Maintaining
  # Knowledge about Temporal Intervals", CACM 26(11), 1983, Fig. 4).
  #
  # Given `A r1 B` and `B r2 C`, `compose(r1, r2)` is the set of Allen
  # relations that can hold between `A` and `C`. Each cell is the exact set of
  # relations `r3` for which some assignment of the six interval endpoints
  # satisfies `r1(A, B) ∧ r2(B, C) ∧ r3(A, C)` under the half-open convention —
  # derived from the endpoint encoding by a difference-bound consistency check
  # (the same reasoning `Tempo.Network.Solver.relation/3` performs) and checked
  # cell-for-cell against a fresh derivation, and spot-checked against the
  # published table, in the test suite.
  #
  # Relations within a cell are listed in Allen's canonical order. Lookup is a
  # constant-time nested-map read — no solver runs at call time.

  @composition %{
    precedes: %{
      precedes: [:precedes],
      meets: [:precedes],
      overlaps: [:precedes],
      finished_by: [:precedes],
      contains: [:precedes],
      starts: [:precedes],
      equals: [:precedes],
      started_by: [:precedes],
      during: [:precedes, :meets, :overlaps, :starts, :during],
      finishes: [:precedes, :meets, :overlaps, :starts, :during],
      overlapped_by: [:precedes, :meets, :overlaps, :starts, :during],
      met_by: [:precedes, :meets, :overlaps, :starts, :during],
      preceded_by: [
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
    },
    meets: %{
      precedes: [:precedes],
      meets: [:precedes],
      overlaps: [:precedes],
      finished_by: [:precedes],
      contains: [:precedes],
      starts: [:meets],
      equals: [:meets],
      started_by: [:meets],
      during: [:overlaps, :starts, :during],
      finishes: [:overlaps, :starts, :during],
      overlapped_by: [:overlaps, :starts, :during],
      met_by: [:finished_by, :equals, :finishes],
      preceded_by: [:contains, :started_by, :overlapped_by, :met_by, :preceded_by]
    },
    overlaps: %{
      precedes: [:precedes],
      meets: [:precedes],
      overlaps: [:precedes, :meets, :overlaps],
      finished_by: [:precedes, :meets, :overlaps],
      contains: [:precedes, :meets, :overlaps, :finished_by, :contains],
      starts: [:overlaps],
      equals: [:overlaps],
      started_by: [:overlaps, :finished_by, :contains],
      during: [:overlaps, :starts, :during],
      finishes: [:overlaps, :starts, :during],
      overlapped_by: [
        :overlaps,
        :finished_by,
        :contains,
        :starts,
        :equals,
        :started_by,
        :during,
        :finishes,
        :overlapped_by
      ],
      met_by: [:contains, :started_by, :overlapped_by],
      preceded_by: [:contains, :started_by, :overlapped_by, :met_by, :preceded_by]
    },
    finished_by: %{
      precedes: [:precedes],
      meets: [:meets],
      overlaps: [:overlaps],
      finished_by: [:finished_by],
      contains: [:contains],
      starts: [:overlaps],
      equals: [:finished_by],
      started_by: [:contains],
      during: [:overlaps, :starts, :during],
      finishes: [:finished_by, :equals, :finishes],
      overlapped_by: [:contains, :started_by, :overlapped_by],
      met_by: [:contains, :started_by, :overlapped_by],
      preceded_by: [:contains, :started_by, :overlapped_by, :met_by, :preceded_by]
    },
    contains: %{
      precedes: [:precedes, :meets, :overlaps, :finished_by, :contains],
      meets: [:overlaps, :finished_by, :contains],
      overlaps: [:overlaps, :finished_by, :contains],
      finished_by: [:contains],
      contains: [:contains],
      starts: [:overlaps, :finished_by, :contains],
      equals: [:contains],
      started_by: [:contains],
      during: [
        :overlaps,
        :finished_by,
        :contains,
        :starts,
        :equals,
        :started_by,
        :during,
        :finishes,
        :overlapped_by
      ],
      finishes: [:contains, :started_by, :overlapped_by],
      overlapped_by: [:contains, :started_by, :overlapped_by],
      met_by: [:contains, :started_by, :overlapped_by],
      preceded_by: [:contains, :started_by, :overlapped_by, :met_by, :preceded_by]
    },
    starts: %{
      precedes: [:precedes],
      meets: [:precedes],
      overlaps: [:precedes, :meets, :overlaps],
      finished_by: [:precedes, :meets, :overlaps],
      contains: [:precedes, :meets, :overlaps, :finished_by, :contains],
      starts: [:starts],
      equals: [:starts],
      started_by: [:starts, :equals, :started_by],
      during: [:during],
      finishes: [:during],
      overlapped_by: [:during, :finishes, :overlapped_by],
      met_by: [:met_by],
      preceded_by: [:preceded_by]
    },
    equals: %{
      precedes: [:precedes],
      meets: [:meets],
      overlaps: [:overlaps],
      finished_by: [:finished_by],
      contains: [:contains],
      starts: [:starts],
      equals: [:equals],
      started_by: [:started_by],
      during: [:during],
      finishes: [:finishes],
      overlapped_by: [:overlapped_by],
      met_by: [:met_by],
      preceded_by: [:preceded_by]
    },
    started_by: %{
      precedes: [:precedes, :meets, :overlaps, :finished_by, :contains],
      meets: [:overlaps, :finished_by, :contains],
      overlaps: [:overlaps, :finished_by, :contains],
      finished_by: [:contains],
      contains: [:contains],
      starts: [:starts, :equals, :started_by],
      equals: [:started_by],
      started_by: [:started_by],
      during: [:during, :finishes, :overlapped_by],
      finishes: [:overlapped_by],
      overlapped_by: [:overlapped_by],
      met_by: [:met_by],
      preceded_by: [:preceded_by]
    },
    during: %{
      precedes: [:precedes],
      meets: [:precedes],
      overlaps: [:precedes, :meets, :overlaps, :starts, :during],
      finished_by: [:precedes, :meets, :overlaps, :starts, :during],
      contains: [
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
      ],
      starts: [:during],
      equals: [:during],
      started_by: [:during, :finishes, :overlapped_by, :met_by, :preceded_by],
      during: [:during],
      finishes: [:during],
      overlapped_by: [:during, :finishes, :overlapped_by, :met_by, :preceded_by],
      met_by: [:preceded_by],
      preceded_by: [:preceded_by]
    },
    finishes: %{
      precedes: [:precedes],
      meets: [:meets],
      overlaps: [:overlaps, :starts, :during],
      finished_by: [:finished_by, :equals, :finishes],
      contains: [:contains, :started_by, :overlapped_by, :met_by, :preceded_by],
      starts: [:during],
      equals: [:finishes],
      started_by: [:overlapped_by, :met_by, :preceded_by],
      during: [:during],
      finishes: [:finishes],
      overlapped_by: [:overlapped_by, :met_by, :preceded_by],
      met_by: [:preceded_by],
      preceded_by: [:preceded_by]
    },
    overlapped_by: %{
      precedes: [:precedes, :meets, :overlaps, :finished_by, :contains],
      meets: [:overlaps, :finished_by, :contains],
      overlaps: [
        :overlaps,
        :finished_by,
        :contains,
        :starts,
        :equals,
        :started_by,
        :during,
        :finishes,
        :overlapped_by
      ],
      finished_by: [:contains, :started_by, :overlapped_by],
      contains: [:contains, :started_by, :overlapped_by, :met_by, :preceded_by],
      starts: [:during, :finishes, :overlapped_by],
      equals: [:overlapped_by],
      started_by: [:overlapped_by, :met_by, :preceded_by],
      during: [:during, :finishes, :overlapped_by],
      finishes: [:overlapped_by],
      overlapped_by: [:overlapped_by, :met_by, :preceded_by],
      met_by: [:preceded_by],
      preceded_by: [:preceded_by]
    },
    met_by: %{
      precedes: [:precedes, :meets, :overlaps, :finished_by, :contains],
      meets: [:starts, :equals, :started_by],
      overlaps: [:during, :finishes, :overlapped_by],
      finished_by: [:met_by],
      contains: [:preceded_by],
      starts: [:during, :finishes, :overlapped_by],
      equals: [:met_by],
      started_by: [:preceded_by],
      during: [:during, :finishes, :overlapped_by],
      finishes: [:met_by],
      overlapped_by: [:preceded_by],
      met_by: [:preceded_by],
      preceded_by: [:preceded_by]
    },
    preceded_by: %{
      precedes: [
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
      ],
      meets: [:during, :finishes, :overlapped_by, :met_by, :preceded_by],
      overlaps: [:during, :finishes, :overlapped_by, :met_by, :preceded_by],
      finished_by: [:preceded_by],
      contains: [:preceded_by],
      starts: [:during, :finishes, :overlapped_by, :met_by, :preceded_by],
      equals: [:preceded_by],
      started_by: [:preceded_by],
      during: [:during, :finishes, :overlapped_by, :met_by, :preceded_by],
      finishes: [:preceded_by],
      overlapped_by: [:preceded_by],
      met_by: [:preceded_by],
      preceded_by: [:preceded_by]
    }
  }

  # Allen's canonical ordering of the 13 base relations.
  @order [
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

  @doc false
  def relations, do: @order

  @doc false
  def compose(relation1, relation2), do: get_in(@composition, [relation1, relation2])
end
