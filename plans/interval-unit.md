# Decouple iteration granularity from endpoint resolution

**Status:** implemented, 2026-07-11

All phases landed, six gates green. Two consumers surfaced during phase 2 beyond the plan's list and were given the walk-time fill: `Tempo.Select.project_merge/2` (merges constraints into the walk anchor) and `Tempo.Format` (renders the sub-unit range). `equal?/2` normalises `:unit` before comparing; member-preserving set operations keep member units so `Enum` over a union still drills. **Prerequisite reading:** `guides/enumeration-semantics.md`, the implicit/explicit span rules in `CLAUDE.md`.

## Problem

An interval has three separable properties that today share one encoding:

* **Extent** — what the span covers (half-open `[from, to)`).

* **Resolution** — how precisely its bounds are stated.

* **Granularity** — the unit a walk (`Enum`) yields.

`%Tempo.Interval{}` has no channel for granularity, so materialisation smuggles it through endpoint resolution. `Tempo.to_interval(~o"2025-07-04")` returns `[2025-07-04T0H, 2025-07-05T0H)` — hour-resolution bounds whose only purpose is telling the walker to step hours. A day-resolution fact comes back stated at hour resolution, violating the library's first principle: *resolution = meaning; give only as much precision as the fact has*.

The empirical signature (one span, three behaviours):

| Value | Bounds resolution | `Enum.count` |
|---|---|---|
| `~o"2025-07-04"` (implicit) | day | 24 (hours) |
| `~o"2025-07-04/2025-07-05"` (explicit) | day | 1 (day) |
| `to_interval(~o"2025-07-04")` (materialised) | **hour** (`T0H`) | 24 (hours) |

User-visible symptoms: `Tempo.map/2` / `try_map/2` collect day inputs into `T0H`-bound members; `to_interval_set/1` shows the same; `inspect` of any materialised implicit span leaks the drilled unit.

The drill is load-bearing: removing it without a replacement channel broke 59 tests + 11 doctests — a DST fall-back day counted 1 instead of 25 hours, a Coptic month 1 instead of 30 days, a 13-month year 1 instead of 13 months. Enumeration derives its step from `Tempo.resolution(from)`, so coarsening the bounds collapses the walk.

## Design

Add an explicit iteration-unit field to `%Tempo.Interval{}`:

```elixir
defstruct recurrence: 1,
          direction: 1,
          from: nil,
          to: nil,
          duration: nil,
          repeat_rule: nil,
          unit: nil,          # NEW — iteration granularity; nil = derive from resolution(from)
          metadata: %{}
```

Semantics:

* `unit: nil` — derive the step from `Tempo.resolution(from)`, exactly today's behaviour. Every user-constructed interval is unaffected.

* `unit: atom` — the walker steps at this unit regardless of endpoint resolution. Set by materialisation: `to_interval(~o"2025-07-04")` returns bounds `2025-07-04/2025-07-05` with `unit: :hour`.

* The drill still happens — but lazily, inside the walker, at iteration time (fill `from` to `unit` with unit minimums before stepping), instead of eagerly persisted in the endpoint values. Extent keeps its honest resolution; granularity travels as data.

The struct already models "how to step" as data for recurrences (`duration` is the cadence); `unit` is the same move for sub-iteration of a single span.

### What sets `unit`

* `to_interval/1` on an implicit `%Tempo{}` (the `concrete_boundary/2` path): bounds at the value's own resolution, `unit` = the next-finer unit that `Unit.implicit_enumerator/2` reports. This is the only *required* setter.

* `materialise_multi/1` (mask expansion, e.g. `1985-XX-15` → 12 day intervals): each member gets the same treatment.

* Group (`20C`) and mask-widening (`19XX`) paths already produce bounds whose derived granularity is correct — leave `unit: nil`.

* Second- and microsecond-resolution values: `concrete_boundary` already preserves resolution for these and the implicit rule bottoms out at `:second` — leave `unit: nil`; verify parity with a test.

* Set-operation results are extents, not walks — construct with `unit: nil`.

* `Interval.new/1`: accept `:unit` as a public option (add to `@public_new_options`) so a caller can request "this day-interval walks hours" explicitly; validate it against the known unit atoms.

### What reads `unit`

Every site that currently derives the step from `Tempo.resolution(from)`:

* `Enumerable.Tempo.Interval` in `lib/protocol/enumeration/range.ex` — `count/1` (line ~30), `member?/2` (~45), `slice/1` (~66), and `increment/1` (~297) inside `reduce`. Each becomes `interval.unit || derived`. `reduce` additionally fills `from` to `unit` (unit minimums) before the first step so emitted values are unit-resolution; subsequent increments derive from the current value as today.

* `Tempo.Interval.Steps.count_steps/4`, `nth_step/4`, `on_step?/4` already take `unit` as an explicit parameter — no signature change. They must handle endpoints *coarser* than `unit` (a day-resolution `from` counted in hours) by filling trailing units with minimums before converting; today they always receive endpoints at least as fine as `unit`, so this is the main implementation risk. `Compare.compare_time/2` already fills trailing minimums, so termination (`past_end?`) is unaffected.

### Inspect and round-trip

The `~o` sigil body renders extent only — `~o"2025-07-04/2025-07-05"` — since `unit` is not ISO 8601 syntax and we mint no new designator (per the ratified V/Q-only stance). When `unit` is set and differs from the derived unit, render it as a decoration using the existing metadata-tag pattern: `#Tempo.Interval<~o"2025-07-04/2025-07-05" unit: hour>`. This is honest about the round-trip: re-parsing the bare sigil yields `unit: nil` (derived day granularity), so the decorated form signals "this value carries non-syntactic state", exactly as metadata-bearing intervals already do.

### Equality caveat

`unit` participates in struct equality, so `materialised == parsed` comparisons in tests (and user code) will differ where they previously matched on drilled bounds. Tests comparing intervals should compare extents (`relation/2 == :equals`) or normalise; the plan's phase 2 sweep handles ours.

## Rejected alternatives

* **Special-case `map`/`try_map` to build non-drilled members** — creates a second materialisation path; an implicit day and its materialised twin diverge in enumeration behaviour (24 vs 1); the `T0H` leak remains everywhere else (`to_interval`, `to_interval_set`, inspect).

* **Enumerate implicit values at their own resolution** — a year yielding itself is useless; the next-finer rule is correct and stays.

* **Unify `Tempo` and `IntervalSet` into one type** — reviewed and rejected separately: `Tempo` is intensional (masks, qualifications, one-of sets, floating values — none survive extensional flattening), `Interval` endpoints are themselves Tempos (circularity), and pattern-matching on `time:` lists dies inside a set-of-one.

## Phases

**Phase 0 — ratify design.** Field name `:unit`; nil-derives default; inspect decoration; public in `new/1`. (This document.)

**Phase 1 — plumb, no behaviour change.** Add the field; thread `interval.unit || derived` through the four `range.ex` sites; teach `Steps` to fill coarse endpoints to `unit`; add the walk-start fill in `reduce`. Materialisation still drills, `unit` still always nil → every existing test stays green. Add new tests exercising `unit:` set explicitly via `Interval.new/1` (day bounds, `unit: :hour`, count 24; DST day count 25; Coptic month 30).

**Phase 2 — flip materialisation.** `concrete_boundary/2` general clause stops drilling and returns own-resolution bounds; `to_interval` sets `unit`; `materialise_multi` members likewise. Update the string-shape assertions (measured blast radius from the failed no-channel attempt: ~45 assertions across `format_test`, `to_interval_test`, `interval_set_test`, `tempo_test`, `select_test`, `inspect_interval_set_test`, `operations_test` — these change to the *cleaner* expected strings) while the ~15 behavioural enumeration tests (DST, Coptic, 13-month, materialisation) must pass **unchanged** — they are the proof the channel works.

**Phase 3 — docs and release.** Update `CLAUDE.md` span rules ("explicit span iterates at its own resolution *unless it carries a `unit`*"), `guides/enumeration-semantics.md`, the conformance guide if it references materialised bounds, the skill cheatsheet if affected, CHANGELOG (`Changed`, breaking: `to_interval/1` output resolution). Full six-gate run.

## Risks

* **`Steps` with coarse endpoints** — the count/nth/on_step? fill is the one genuinely new computation; property-test it against the walk (`count == length(Enum.to_list(interval))`) across DST transitions and non-Gregorian calendars.

* **Hidden dependents on drilled bounds** — `Validation.validate_endpoint_order/2` calls `next_unit_boundary/1`; position on the line is unchanged (only stated resolution), and `compare_endpoints` fills minimums, so ordering is unaffected — verify, don't assume.

* **Downstream string expectations** — any external consumer asserting `T0H` shapes breaks; this is the breaking change the CHANGELOG entry names, and why this lands before 1.0.

## Definition of done

All six gates green; the three-row table above collapses to two behaviours — implicit and materialised agree on count *and* on stated resolution; `Tempo.map(days, fun)` members inspect as days.
