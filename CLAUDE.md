# Tempo — Project Guidance

## Project objective

Tempo treats **date and time as intervals, not as instants**. Every value represents a bounded span on the time line, which means:

* We can **reduce and map** across intervals as first-class structures.

* We can **compare** intervals using [Allen's Interval Algebra](https://ics.uci.edu/~alspaugh/cls/shr/allen.html).

* We **never run the risk of invalid dates** because every value is a bounded interval — partial specifications like `2022Y` or `2022Y-11M` are intervals spanning the whole year or month, not uncertain instants.

## Architecture — implicit vs explicit spans

Every Tempo value is a span on the time line. Spans come in two forms and the distinction matters for iteration, comparison, and set operations.

### Implicit span

A single ISO 8601 datetime **is** an interval. Its span runs from the stated datetime to the same datetime incremented by one unit **at the next-higher-resolution-that-is-not-defined**. For example:

* `2026` → `2026-01-01 .. 2027-01-01` (year resolution, span of one year)

* `2026-01` → `2026-01-01 .. 2026-02-01` (month resolution, span of one month)

* `2026-01-15` → `2026-01-15 .. 2026-01-16` (day resolution, span of one day)

* `2026-01-15T10` → `2026-01-15T10:00 .. 2026-01-15T11:00` (hour resolution, span of one hour)

Map and reduce on implicit spans is already implemented. The iteration unit is the **next-higher-resolution below what is stated** — e.g., iterating over `2026-01` yields days, iterating over `2026` yields months (or weeks, depending on calendar).

### Explicit span

An explicit span is a pair of datetimes written with a range operator, such as `2026-01-01..2026-02-01`. By default it is iterated at **its own highest resolution** — the resolution of the boundaries. Iterating `2026-01-01..2026-02-01` yields days, not months.

The exception is an explicit iteration unit: `%Tempo.Interval{}` carries a `:unit` field that, when set, overrides the derived granularity. Materialising an implicit span sets it — `Tempo.to_interval(~o"2025-07-04")` yields bounds `2025-07-04/2025-07-05` (the value's own resolution, per *resolution = meaning*) with `unit: :hour`, so the materialised span still walks hours like its implicit twin. The walk fills the anchor down to the unit at iteration time; the bounds never carry drilled components. An interval has three separable properties: **extent** (the half-open span), **resolution** (how precisely the bounds are stated), and **granularity** (`:unit`, the unit a walk yields).

### Half-open convention

**Every span is inclusive of the first boundary and exclusive of the last boundary** — `[first, last)`. This is deliberate, not incidental. It:

* Makes map/reduce work uniformly regardless of the iteration resolution.

* Makes adjacent spans concatenate cleanly: `[a, b)` followed by `[b, c)` is exactly `[a, c)` with no overlap or gap.

* Matches the implicit-span semantics above (`2026-01` ends just before `2026-02-01`, not on it).

Any new span, interval, comparison, or set-operation code **must honour this convention**. Code that treats the upper bound as inclusive is a bug.

## Documentation and example style

**Every example in Tempo docs, guides, cookbook recipes, livebooks, and module docs should read aloud as English prose a product manager would say.** This is the test of whether the abstractions are doing their job — if a snippet can't be translated to a sentence a non-programmer would understand, there's a missing predicate or operation, and it should be added before the example is written.

### The pipeline-prose shape

Examples follow a consistent three-part structure:

1. **Setup in a few named bindings** (the nouns):

   ```elixir
   work        = ~o"2026-06-15T09/2026-06-15T17"
   alice_busy  = ...
   bob_busy    = ...
   ```

2. **Pipeline in set-algebra + predicate verbs** (the sentence):

   ```elixir
   {:ok, alice_free} = Tempo.difference(work, alice_busy)
   {:ok, bob_free}   = Tempo.difference(work, bob_busy)
   {:ok, mutual}     = Tempo.intersection(alice_free, bob_free)

   slots =
     mutual
     |> Tempo.IntervalSet.to_list()
     |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))
   ```

3. **Prose translation in a callout** (the human reading):

   > *"Alice's free time is the workday **minus** her busy periods. Bob's is the same. **Mutual** free time is the **intersection** of theirs. **Bookable slots** are the mutual windows **at least an hour** long."*

The three parts reinforce each other — nouns, verbs, prose.

### What this excludes from examples

If any of these appear in user-facing examples, it's a signal that an abstraction is missing:

* **`to_utc_seconds/1`** or other raw second counting — add a duration predicate instead (`at_least?`, `exactly?`, `shorter_than?`, …).
* **Struct field accessors** like `set.intervals`, `iv.from.time[:hour]` — add a named helper (`IntervalSet.to_list/1`, a predicate, or a query function).
* **Magic numbers** for durations (`3600`, `86_400`) — use an ISO 8601 duration literal (`~o"PT1H"`, `~o"P1D"`).
* **Hand-rolled geometric checks** like `compare_endpoints(a + d, b) in [:earlier, :same]` — add a predicate that names the concept.
* **Pattern-matching on Allen relation lists inline** like `Tempo.relation(a, b) in [:equals, :starts, :during, :finishes]` — name that set (`Tempo.within?/2` does exactly this). Note `Tempo.relation/2` returns the Allen relation; `Tempo.compare/3` is the separate stdlib-ternary sorter callback returning `:lt | :eq | :gt`.

When writing a new example and one of these patterns appears, stop and add the missing abstraction first. The codebase already models this — `within?/2`, `at_least?/2`, `adjacent?/2` all exist because geometric checks and inline-relation-lists were recurring in examples.

### Applies to

* Module docs and `@doc` examples.
* Guides in `guides/`.
* The cookbook.
* Livebooks.
* README code blocks.
* Release notes and CHANGELOG entries (where examples appear).

### Does NOT apply to

* Internal implementation code and helpers.
* Tests asserting specific AST shapes or low-level behaviour.
* Error messages (which need to reference specific field names and types).

These are about correctness and mechanics; they legitimately work at the plumbing level.

## Naming conventions

### Territory, not region

**Tempo standardises on "territory" everywhere — never "region".** A territory is a CLDR/BCP 47 territory code (`:US`, `:AU`, `:SA`, `:GB`, …) — the two- or three-letter country/region code that locale data is keyed by. The word "region" means something different in everyday speech (a vague geographic area), and the Localize library already names its API `Localize.Territory.territory_from_locale/1`, so Tempo follows suit.

This applies to every user-facing surface:

* **Option keys**: `territory: :SA`, never `region: :SA`.

* **Application config keys**: `:default_territory`, never `:default_region`.

* **Type names and variable names**: `territory`, `normalize_territory`, `resolve_territory`, `ixdtf_territory`.

* **Prose in docs, cookbook, livebook, changelog**: "territory resolution chain", "territory override", "the territory `:SA`".

The single exception is when referring to an **external standard's own terminology**. BCP 47 calls its `u-rg-XX` subtag a "region override" — that's the standard's name, we quote it verbatim with the "region" word in scare quotes or parentheses. IXDTF inherits that name via the `u-rg` key. Those specific references are fine; everywhere else it is "territory".

When reviewing new code or docs, grep for `region` / `:region` / `default_region` and rename them unless they're quoting BCP 47 directly.

## Upstream library bugs — report and pause

The global "never work around a library deficiency" rule applies to Tempo's upstreams — Calendrical, Localize, Astro, Tzdata, any hex dep. A bug or gap there is reported back with a minimal reproducer (name the function/module), a fix suggested in the upstream's own idiom, and paused on until the user coordinates the fix (a hex release or a path-dep to the fixed branch); resume against the upstream behaviour, no scar tissue left behind. The only exception is an explicit "work around it in Tempo for now", which also gets a TODO.md entry flagging the upstream fix and what to remove once it lands.

## Calendar calculations belong in Calendrical

**Tempo does not do calendar calculations — they are ALWAYS done in Calendrical.** Anything that computes a date, a month length, a leap month or year, a solar term's longitude or moment, a lunisolar conversion, an ecclesiastical (Easter) date, or any other calendar-arithmetic result goes through Calendrical — never re-derived in Tempo or a downstream (`tempo_holidays`, a guide, a helper). Tempo is the *representation and selection* layer (ISO 8601 syntax, intervals, recurrences, Allen relations, set algebra); the calendar maths underneath is Calendrical's. `Tempo.Event` is the pattern — it holds selection-layer data (event names) and delegates every computation to Calendrical (and Astro for astronomy).

A formula like `rem(300 + term * 15, 360)` to derive a solar term's longitude, or a hand-rolled leap-month or traditional-to-ordinal conversion, is a defect wherever it appears outside Calendrical — move it into Calendrical.

**If Calendrical cannot provide a capability the work needs, stop and ask the user what to do** — do not fill the gap with a calculation in Tempo. This is the calendar-specific case of the upstream "report and pause" rule above.

## Definition of done — Credo

This library adds a sixth gate to the global definition of done: `mix credo --strict` must report **no issues** before a change is complete, run alongside the global's five gates.

The `.credo.exs` config runs every check at its **default threshold** — there are no elevated `max_complexity` or `max_nesting` overrides, and there are no inline `# credo:disable` suppressions anywhere in the codebase. This is deliberate: when Credo flags new code, the fix is to **refactor the code**, not loosen the config. The two established idioms for the things Credo most often flags here:

* A `case`/`cond` dispatching over a vocabulary (Allen relations, cron cascade fields, iteration shapes) becomes **multi-head function clauses**. Credo scores cyclomatic complexity per head, so the giant branch collapses to many trivial heads — and the pattern-matched table reads better than the `case`.

* A `case`/`with` nested inside another `with`/`if` is extracted to a **multi-head helper** with pattern matching, never tolerated as depth-3 nesting.

The only standing config deviations are disables with concrete, documented reasons in `.credo.exs`: `Design.AliasUsage` is **enabled** (nested `Tempo.*` modules are aliased to collapse the namespace by the primary level — `Tempo.Foo.Bar` → `Bar`) but carries an `excluded_lastnames` list so an alias never shadows an Elixir/Erlang built-in (`Calendar`, `Inspect`, `Duration`, `Range`, …); `Design.TagTODO` and `Design.TagFIXME` are off because inline tags are intentional pointers. Changing a threshold or adding a new disable is itself a change that needs its own justification — refactor first.

## Reference documents

The following documents are **critical** when working on this project. Consult them whenever behaviour, syntax, or semantics need to be verified — do not guess.

* **ISO 8601 standards** — the canonical PDFs live in `~/Documents/Development/iso_standards/`. These are the source of truth for ISO 8601 Part 1 (date/time representations) and Part 2 (extensions), which Tempo implements.

* **IETF draft-ietf-sedate-datetime-extended-09 (IXDTF)** — <https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html#name-format-of-extended-informat>. Defines the extended information suffix syntax (`[zone]`, `[u-ca=calendar]`, `[key=value]`, critical `!` flag) parsed by `Tempo.Iso8601.Tokenizer.Extended`.

* **Allen's Interval Algebra** — <https://ics.uci.edu/~alspaugh/cls/shr/allen.html>. The 13 base relations (`precedes`, `meets`, `overlaps`, `finished_by`, `contains`, `starts`, `equals`, and their inverses, plus `preceded_by`) used by `Tempo.relation/2` (delegating to `Tempo.Interval.relation/2`) when comparing intervals. For ordering rather than relating, `Tempo.compare/3` returns `:lt | :eq | :gt` and makes `Tempo` usable as an `Enum` sorter module.
