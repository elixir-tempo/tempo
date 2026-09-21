# Uncertainty Roadmap — graded relations and beyond

**Status:** draft, 2026-07-06

This document records the strategy for adding uncertainty-aware reasoning to Tempo once the crisp interval algebra (Allen relations, set operations, IntervalSet coalescing, the STP/Network solver, CPM scheduling) is feature-complete. It exists to commit the team to a *framework choice* and an *architectural boundary* before any code is written.

## Why now

The crisp layer is mature: every Tempo value is a half-open `[from, to)` interval, relations are the 13 Allen base relations, and set operations are exact and closed (the result of a set operation on intervals is itself intervals). The dimension that remains untouched is **uncertainty** — and it is the dimension that the rest of the date/time ecosystem ignores almost entirely. Tempo is unusually well-positioned here because it already parses the ISO 8601-2 §8 uncertainty vocabulary; today that vocabulary is inert metadata, and the opportunity is to make it *mean something*.

## Three frameworks, not one

"Fuzzy/Bayesian" is not a single feature. It bundles three mathematically and philosophically distinct frameworks, and conflating them would violate Tempo's crisp-semantics ethos. Pick deliberately.

* **Fuzzy / possibility** — each interval carries a membership function `μ(t) ∈ [0,1]` (e.g. trapezoidal: a *core* where `μ = 1`, flanked by ramps where the value is "approximately"). Set operations become `intersection = min(μ)`, `union = max(μ)` (or another t-norm). This is the natural semantic home for the **`~` (approximate)** qualifier.

* **Bayesian / probability** — each endpoint is a random variable with a distribution; `P(A overlaps B)` is an integral over a joint distribution, evaluated analytically (convolution) or by Monte Carlo. Different math, different philosophy. The natural home for the **`?` (uncertain)** qualifier *once a prior is supplied*.

* **Epistemic disjunction** — already modelled. A one-of set `[a,b,c]` means "one of these, we do not know which," and `Tempo.to_interval/2` deliberately *errors* on it rather than asserting all members happened. Weighting the members with a prior is the cleanest Bayesian on-ramp because it preserves interval closure.

These are not interchangeable. Possibility answers "could this be true?"; probability answers "how often is this true?"; they give different numbers and require different inputs. A design that blurs them produces results that look authoritative and are meaningless.

## The magnitude problem

Fuzzy and Bayesian math both need a *magnitude* — "how uncertain." The ISO 8601-2 qualifiers as Tempo holds them today do **not** carry one:

* `~o"2022Y?"` has bounds identical to `~o"2022Y"`. The `?`/`~`/`%` qualifiers are qualitative flags stored as metadata (`:qualification` / `:qualifications`); they do not widen the interval, and Allen relations are insensitive to them.

* The only quantitative uncertainty Tempo already ingests is the **margin of error**, `~o"2018±2Y"`, which the tokenizer preserves in the value as `[year: {2018, [margin_of_error: 2]}]`.

So the magnitude exists for `±` and nowhere else. Inventing ramp-widths for a bare `~`/`?` would be an arbitrary, un-Tempo-like semantic decision. **Therefore the first uncertainty work grounds itself entirely in `±`** and leaves the magnitude-less qualifiers alone until there is a reason and a convention for them.

## Architectural boundary — core vs companion library

The line is principled, not aesthetic:

* **Graded *relations and predicates* → Tempo core.** They read the `±` margin the parser already produces, they are read-only queries that return a *verdict* (`:certain` / `:possible`) rather than a new value type, and so they preserve interval closure completely. They belong beside `relation/2`, `overlaps?/2`, and `within?/2` — splitting them into another library would fragment the relation vocabulary and surprise anyone who found `overlaps?/2` but not its modal siblings next to it.

* **Uncertainty-bearing *set algebra* → companion library.** Fuzzy intersection/union produce *membership functions*, and probabilistic operations produce *distributions* — neither is an interval, so both break the `IntervalSet`/`coalesce` machinery and would need a parallel `FuzzyIntervalSet` / probabilistic type plus heavier dependencies (t-norms, convolution, Monte Carlo). That is the part to keep opt-in and out of the lean core.

Phase 1 below sits firmly on the core side of this line. Everything that introduces a new *value* type sits on the companion side.

## Phase 0 — stop crashing on `±` values (prerequisite, and a live bug)

`Tempo.relation(~o"2018±2Y", ~o"2019Y")` currently raises `ArithmeticError` (the crisp relation does arithmetic on the `{2018, [margin_of_error: 2]}` tuple at `lib/tempo/interval.ex`). A validly-parsed value must never crash a library function — this is a standing rule-#2 violation independent of any uncertainty feature. Before Phase 1, the crisp relations and predicates must *tolerate* margin-bearing values by reducing them to their crisp core (the margin ignored) so existing behaviour is well-defined. This is worth fixing immediately, regardless of whether Phase 1 proceeds.

## Phase 1 — graded relations over `±`-bearing intervals

### Semantics: necessary and possible satisfaction

A margin turns a crisp endpoint into a *band*: `~o"2018±2Y"` has a year that ranges over `2016..2020`, so the interval slides within a band of that width. Given two intervals `A` and `B` whose endpoints range over their `±` bands, an Allen relation `R` is:

* **certain** (necessary) iff `R` holds for *every* consistent assignment of the uncertain endpoints within their bands;

* **possible** iff `R` holds for *at least one* assignment;

* **impossible** iff `R` holds for *no* assignment.

This is the standard necessary/possible (modal) reading of constraints under interval uncertainty, and it is **prior-free** — it needs no distribution, only the bands — which is exactly why Phase 1 is three-valued rather than numeric. It is computed by interval arithmetic on the extremal endpoint positions, not by sampling.

Two properties make it safe to add:

* **Graceful degradation.** With zero margins, `certain == possible == the crisp relation`, so `certainly_overlaps?/2`, `possibly_overlaps?/2`, and `overlaps?/2` coincide on crisp values. Phase 1 is a strict superset of today's behaviour.

* **Network synergy.** "Necessary vs possible satisfaction" is the same question the STP/`Tempo.Network` solver already reasons about for constraint feasibility. Under uncertainty, the *relation* between two intervals is in general a **set of Allen base relations** (a disjunction) — precisely the representation Allen's algebra and constraint networks use. The relation is *certain* exactly when that set is a singleton.

### Proposed API (core)

* `Tempo.possible_relations(a, b)` → a set of Allen base relations that could hold given the `±` bands. A singleton means the relation is certain. This is the primitive; everything else is a convenience over it.

* Modal predicate siblings for the common relations, reading as plain English:
  * `Tempo.certainly_overlaps?/2` / `Tempo.possibly_overlaps?/2`
  * `Tempo.certainly_precedes?/2` / `Tempo.possibly_precedes?/2`
  * `Tempo.certainly_within?/2` / `Tempo.possibly_within?/2`

* Optionally `Tempo.relation_certainty(a, b)` → `:certain | :possible | :impossible` for a *named* relation, for callers who already know which relation they are asking about.

The "reads like English" test holds: *"the two reigns **possibly** overlap but do not **certainly** overlap"* is something a historian or product manager would say.

### Worked example (the driver)

This is the use case that justifies the work — the chronological-networks / ChronoLog world, where dates are `circa` and the interesting question is overlap under uncertainty:

```elixir
reign_a = ~o"-0610±5Y/-0595±5Y"   # accession and death each ± 5 years
reign_b = ~o"-0600±5Y/-0585±5Y"

Tempo.possibly_overlaps?(reign_a, reign_b)    # => true
Tempo.certainly_overlaps?(reign_a, reign_b)   # => false
Tempo.possible_relations(reign_a, reign_b)    # => a set: overlaps, contains, during, …
```

> *"Given the dating error on both reigns, an overlap is **possible** but not **certain** — so a synchronism between them is consistent with the evidence, not implied by it."*

## Phase 2 — numeric degree and weighted disjunction (deferred)

Once Phase 1 ships and there is appetite for more, two increments stay close to the crisp core:

* **A numeric degree** `∈ [0,1]` for a relation requires a *prior* over each band (e.g. uniform), which crosses from possibility into probability — a deliberate, documented Bayesian step. `Tempo.overlap_probability(a, b)` would integrate over the (assumed) joint distribution of the bands.

* **Weighted one-of sets.** Attaching a prior to the members of an epistemic `[a,b,c]` set yields expected/MAP queries while preserving closure (it annotates a `Set`, it does not produce a membership function). This is the cleanest "Bayesian" feature that does *not* fork the type system.

## Phase 3 — fuzzy and probabilistic set algebra (deferred, companion library)

The closure-breaking, dependency-heavy part, scoped to a sibling library so the core stays lean:

* **Fuzzy intervals** with trapezoidal membership driven by `~` (with a chosen ramp convention) and `±`; `intersection = min`, `union = max` (t-norm configurable), producing a `FuzzyIntervalSet`.

* **Probabilistic intervals** with distributional endpoints; set operations by convolution or Monte Carlo, producing distributions over occurrence/overlap.

Reference literature for the relation-grading and fuzzy-Allen route: Dubois & Prade on possibility theory, and Schockaert et al. on fuzzy Allen relations.

## Open questions

* **Magnitude-less qualifiers.** Should a bare `~`/`?` ever imply a default band (e.g. one unit of the stated resolution), or remain magnitude-free until `±` is supplied? Phase 1 assumes the latter.

* **Degree priors.** When a numeric degree arrives in Phase 2, is the default prior uniform-over-band, and how is a non-uniform prior expressed?

* **Companion boundary.** Does the numeric degree (`overlap_probability/2`) belong in core or in the companion library? It returns a scalar (closure-preserving) but requires a prior (a probability model) — it sits on the line.

* **t-norm choice.** If/when fuzzy set algebra is built, is `min`/`max` (Zadeh) the only supported t-norm, or is it configurable?
