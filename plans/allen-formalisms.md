# Implementing Allen's formalisms

## Where we are

Allen's 1983 paper has four parts. Tempo implements two of them completely and substitutes a different formalism for the third.

| Allen 1983 | Tempo today |
|---|---|
| §2 The 13 relations and inverses | `Tempo.relation/2`, `inverse_relation/1` — complete |
| §3a The composition table (Fig. 4) | `Tempo.compose/2` — complete 13×13, independently derived and cross-checked |
| §3b Propagation over *disjunctive* relation sets | **absent** — no consumer of the composition table |
| §4 Reference intervals | **absent** |

`Tempo.Network` is not the missing piece. It solves the **Simple Temporal Problem** (Dechter, Meiri & Pearl 1991) by Floyd–Warshall over difference bounds. That is *stronger* than Allen on metric information — `at_least: 20, unit: :year` has no expression in the interval algebra at all — and strictly *weaker* on qualitative uncertainty: its relation vocabulary is convex, and asserting a non-convex disjunction raises.

```elixir
Network.add_relation(n, [:before, :after], "a", "b")
#=> ** (FunctionClauseError) in Tempo.Network.Relation.atomic_for/3
```

That disjunction is exactly what Allen's algebra is for, and exactly what makes it NP-complete. The two formalisms are complementary, not substitutes.

## What this plan adds

The ability to reason when the relation between two periods is *unknown but constrained* — "the fire is either before or after the rebuild, never during" — and to derive what follows from a web of such statements.

## Stage 1 — Relation-set algebra

A new module, `Tempo.Interval.Relations`, over subsets of the thirteen. Pure data; no time values involved.

```elixir
@type relation_set :: [Interval.relation()]

converse(relation_set)                 # {precedes, during} -> {preceded_by, contains}
narrow(relation_set, relation_set)     # combine two sources of knowledge
compose(relation_set, relation_set)    # lift Tempo.compose/2 to sets, unioned
full()                                 # all thirteen — "I know nothing"
empty?(relation_set)                   # the contradiction
```

**Naming.** Not `intersect/2`. `Tempo.intersection/2` already means set algebra over time *values* and returns an `IntervalSet`; this operates on relation *atoms* and returns a list of them. Two nearly identical names for unrelated operations would be a trap. `narrow/2` also says what it is for: combining constraints narrows what remains possible.

**Cost.** Small. `converse/1` is a 13-entry map `inverse_relation/1` already provides; `narrow/2` is `MapSet.intersection/2`; `compose/2` on sets is a union over the pairwise table lookups. The only real work is canonical ordering so results compare equal.

**Why first.** It makes `Tempo.compose/2` useful on its own — today nothing consumes it — and every later stage is expressed in these four operations.

## Stage 2 — Qualitative constraint network

`Tempo.Interval.Network`: a pairwise matrix of relation sets plus Allen's §3 propagation.

```elixir
net =
  Network.new([:fire, :rebuild, :occupation])
  |> Network.constrain(:fire, [:precedes, :preceded_by], :rebuild)
  |> Network.constrain(:fire, [:during], :occupation)

{:ok, net} = Network.propagate(net)
Network.between(net, :rebuild, :occupation)   #=> the surviving relations
```

`propagate/1` is the fixpoint `R(i,k) ← R(i,k) ∩ (R(i,j) ∘ R(j,k))`, queue-driven, returning `{:error, :inconsistent}` when a cell empties.

**Complexity.** Path consistency is O(n³) per pass and does *not* decide consistency for the full algebra — that is NP-complete. It computes a sound but incomplete approximation: it prunes impossible relations and detects many inconsistencies, but a path-consistent network may still be unsatisfiable. **The docs must say this plainly**, or users will read a clean `propagate/1` as proof of consistency.

**Testing.** The composition table is already validated cell-for-cell, which removes the usual source of error. Beyond that: convergence and idempotence of the fixpoint; agreement with `Tempo.relation/2` when every period is grounded (an independent oracle we already have); and the paper's own worked examples.

## Stage 3 — Reference intervals (§4)

Allen's scaling device: cluster periods under a reference interval and propagate within a cluster, crossing between clusters only through their references.

Defer until Stage 2 shows a size problem. Allen needed it for natural-language discourse with thousands of intervals; a chronology of a few hundred periods will not.

## Stage 4 — Bridging the two networks

The interesting one, and the reason to do the rest.

- **Qualitative → metric.** A relation set that has narrowed to a single relation is a convex constraint `Tempo.Network` can accept. Feed the results of `propagate/1` into the STP solver to get dates.
- **Metric → qualitative.** `Solver.relation/3` already returns the still-possible relations for a solved network. That is a relation set — seed the qualitative network with it and propagate further.

This is where the combination beats either alone: metric bounds prune qualitative possibilities, and qualitative propagation tightens the metric network.

## Ordering and value

Stage 1 stands alone and is cheap. Stage 2 is the substance. Stage 4 is the payoff. Stage 3 is speculative until measured.

## Non-goals

- Deciding satisfiability of the full algebra (NP-complete; path consistency is the accepted approximation).
- Replacing `Tempo.Network`. The STP solver keeps metric constraints, which Allen's algebra cannot express.
- Tractable subclasses (ORD-Horn, Nebel & Bürckert 1995) — worth citing, not worth implementing until someone needs completeness.
