# Tempo — Project Guidance

## Project objective

Tempo treats **date and time as intervals, not as instants**. Every value represents a bounded span on the time line, which means:

* We can **reduce and map** across intervals as first-class structures.

* We can **compare** intervals using [Allen's Interval Algebra](https://ics.uci.edu/~alspaugh/cls/shr/allen.html).

* We **never run the risk of invalid dates** because every value is a bounded interval — partial specifications like `2022Y` or `2022Y-11M` are intervals spanning the whole year or month, not uncertain instants.

## Architecture — one struct, written forms, half-open spans

The design is `plans/architecture-redesign.md`: nine laws (section 4) and the modules written to them (section 5). A behaviour that does not follow from the laws is not Tempo's. In short:

### One struct

Every expression is a `%Tempo{}`, and what it is is its `:form`: `{:value, units}`, `{:span, from, to}`, `{:every, first, bound, rule}`, `{:all, members}`, `{:one, members}` or `{:when, member, conditions}`. `Tempo.Interval`, `Tempo.IntervalSet` and `Tempo.RecurrenceSet` are modules of functions over that struct, not structs. A duration is a `%Tempo.Duration{}`: a length, not an expression.

### Resolution is meaning

A value written to a resolution denotes one unit of it: `2026` is the year, `2026-06` the month, `2026-06-15` the day, `2026-06-15T10` the hour. The written units are kept as written; nothing drills into them. There is no `:unit` field: an interval made from a value (`Tempo.to_interval/2`) is a different expression with the same extent, and a caller who wants an extent walked at a unit says so with `Tempo.walk/3`.

### Spans are half-open; written ends are read as they are said

Underneath, **every span is `[first, last)`**: inclusive of the first instant, exclusive of the last. Adjacent spans concatenate with no gap and no overlap, and every set operation and Allen relation is exact on those positions. Code that treats the *stored* upper bound as inclusive is a bug.

What is *written* is read as it is said aloud (law 9):

* An end written to a **calendar unit** (a year, a month, a week, a date) is read **through**: `2026-06-15/2026-06-20` is six days and holds the 20th; `2026/2028` is three years.

* An end written to a **clock unit** (an hour, a minute, a second) is a **boundary**: `T09/T17` is eight hours and ends as five begins.

* Docs say an interval as it is written: dates by their first and last day, inclusively ("the 15th through the 20th", `2026-06-15/2026-06-20`), and times of day as a range that stops where its end begins ("nine to five", `T09/T17`).

The reader makes the half-open bound and the writer writes a span back as it was read, an end with a time of day from its hour (`2026Y1M5DT9H15M/T9H30M`). `Tempo.to_interval(~o"2026-06")` is therefore `~o"2026-06/2026-06"`, June through June.

ISO 8601 leaves the reading of a reduced-precision end open; law 9 follows the weight of its examples (decision 85).

### Enumeration

`Enum` over a singular expression (one span) yields its children: the unit below a value's resolution, or the finer of an interval's two ends'. Over a plural expression (a set, a recurrence, a value with a list, a mask or a selection in it) it yields its members. `Tempo.members/2` gives the spans of either.

### Frames, and refusal

A span lies on the UTC line (a year and a zone or a shift), the floating line (a year, no zone) or a cycle (no year). Two spans relate, compare or combine only on one frame; a floating value beside a zoned one is a `Tempo.FrameError`. What Tempo cannot answer by the laws is a named error, never a guess: an option a function does not take, a reading a zone's clock skips, a base with no year.

### Build from parts, never from text

A program that holds the parts of an expression builds it from them: `Tempo.new/1` for a value, `Tempo.Interval.new/1`, `Tempo.Duration.new/1`, `Tempo.IntervalSet.new/2`, and `Tempo.every/2`, `Tempo.selection/1` and `Tempo.one_of/1` for a recurrence, a selection and a one-of set. Interpolating parts into ISO 8601 text and reading it back (`Tempo.from_iso8601!("#{year}-01-01")`) is a defect, in the library, its tests, its guides and its companions. Text is read where text is what was given: a user's input, a file, an example of the written form. The builders and the reader make one form (`test/tempo/build_test.exs` holds them to it), so a shape that cannot be built is a builder to add, not a string to write.

### The API and the engine

`Tempo` is the API: each operation is documented there, validates its arguments and calls one engine function. The engine is under `lib/tempo/core/` (`Tempo.Unit`, `Scale`, `Zone`, `Limit`, `Spans`, `Algebra`, `Select`, `Shift` and the rest) and is `@moduledoc false`: it is no part of the public API, and public docs do not refer to it.

## One expression, one calendar — extensions come last

An **expression** is one thing as it is written or built: a value, an interval (a recurrence among them), a duration, a set. These rules are the user's, given on 2026-10-12, and the reader, the constructors and every new function hold to them. Code that is more permissive than they are is a defect to simplify, not a feature to keep.

* **An expression is in a single calendar** — "An expression (a tempo, an interval or duration) can only be in a single calendar. No mixing calendars across endpoints." The two ends of an interval are of one calendar (`Tempo.Interval.new/1` returns an error for two), and the members of an interval set are (`Tempo.IntervalSet.new/2` brings them to its first member's). A recurrence is one expression: its start, its end, its domain and its rule are of one calendar, so a domain's years are years of the calendar written after the recurrence, with no exception for the Gregorian (decided 2026-10-12). The Gregorian years a rule of another calendar falls in are another expression, a `:within` window.

* **Extensions are only valid after all date/time expressions** — "edtf and ixdtf extensions are only valid after all date/time expressions." An IXDTF suffix (`[Europe/Paris]`, `[u-ca=hebrew]`, `[key=value]`) is written once, at the end of the whole expression: after the end of an interval, after a set, after a recurrence's rule. One written anywhere inside (on the start of an interval, on a member of a set, on an end of a range, on a recurrence's start) is an error that says where it belongs.

* **Extensions apply to the whole expression, always** — "The extensions apply to the whole expression, always." A zone or a calendar written after an interval is the zone and the calendar of both its ends; one written after a set is that of every member.

* **An interval is in one zone** — decided 2026-10-12, as for two calendars: `Tempo.Interval.new/1` returns an error for two ends in different named zones, and the caller converts one with `Tempo.shift_zone/2`. A time shift (`+02:00`, `Z`) is not an extension: ISO 8601 writes one on each end, and each end keeps its own.

* **Qualifiers are not extensions** — decided 2026-10-12: the rule covers the bracketed suffixes only. EDTF's `?`, `~` and `%` stay where ISO 8601-2 §8 puts them, on an end of an interval, a member of a set or a single component.

* **What cannot be written is an error, never another value** — `Tempo.to_iso8601/1` returns a `Tempo.Iso8601EncodeError` for a struct given parts in two zones or two calendars by hand, where the writer once wrote a suffix on each part.

* **Explicit conversion to another calendar is permitted** — a caller who holds values of two calendars converts one (`Tempo.to_calendar/2`), and the operations that take two expressions may convert for them, as the set operations bring their second operand to the calendar of their first. Two separate expressions of different calendars may be compared and combined; one expression may not hold both.

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
     |> Tempo.IntervalSet.members()
     |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))
   ```

3. **Prose translation in a callout** (the human reading):

   > *"Alice's free time is the workday **minus** her busy periods. Bob's is the same. **Mutual** free time is the **intersection** of theirs. **Bookable slots** are the mutual windows **at least an hour** long."*

The three parts reinforce each other — nouns, verbs, prose.

### What this excludes from examples

If any of these appear in user-facing examples, it's a signal that an abstraction is missing:

* **Raw second counting** (`Tempo.Duration.to_unit(d, :second)` compared with a number) — add a duration predicate instead (`at_least?`, `exactly?`, `shorter_than?`, …).
* **Struct field accessors** like `value.form`, `value.zone.name` — add a named helper (`IntervalSet.members/1`, a predicate, or a query function).
* **Magic numbers** for durations (`3600`, `86_400`) — use an ISO 8601 duration literal (`~o"PT1H"`, `~o"P1D"`).
* **Hand-rolled geometric checks** on an interval's ends (shift one end, compare it with another) — add a predicate that names the concept.
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

## Performance — hand on what is found, within the module

**A step that finds a position hands it to the next step that needs it, within its module, rather than writing a value and having the next step place it again.** Placing a value on the line (`Tempo.Spans.extent/1`) and building one at a position (`Tempo.Spans.value_at/4`) are each a few hundred nanoseconds, and a walk that throws away what it has just found pays them again at every step: a plain recurrence that placed its unchanging first start twice an occurrence was half its time (decisions 62 and 63, `plans/carried-position.md`). A review that finds a position computed, discarded and recomputed within one module hands it on.

Positions cross a module boundary only where they already do, as the occurrence-and-extent pairs of a walk (`Tempo.Recurrence`, `Tempo.Spans.windowed/2`), dropped before an occurrence is handed back. A second representation of a value through the engine was measured and declined (decisions 57 and 63): it threads two shapes through a module's pipeline and keeps the rule that a carried extent is the value's own by hand, for a gain the measurement put at about a quarter of an occurrence. Measure first (`bench/against_1_6_bench.exs`, profiled by layer), and record what a change bought in its decision.

## Reference documents

The following documents are **critical** when working on this project. Consult them whenever behaviour, syntax, or semantics need to be verified — do not guess.

* **ISO 8601 standards** — the canonical PDFs live in this repository at `standards/iso8601/` (`ISO_8601-1_2019(en).PDF` and `ISO_8601-2_2019(en).PDF`; read them with `pdftotext -layout`). They are git-ignored, never committed or packaged. These are the source of truth for ISO 8601 Part 1 (date/time representations) and Part 2 (extensions), which Tempo implements.

* **RFC 9557 (IXDTF)** — vendored at `standards/rfc/rfc9557.txt` (<https://www.rfc-editor.org/rfc/rfc9557>), the published form of draft-ietf-sedate-datetime-extended. The other RFCs Tempo implements (3339, 5234, 5545, 7529, 8984) are beside it; `standards/README.md` lists them. Defines the extended information suffix syntax (`[zone]`, `[u-ca=calendar]`, `[key=value]`, critical `!` flag) read by `Tempo.Reader.Suffix`.

* **Allen's Interval Algebra** — <https://ics.uci.edu/~alspaugh/cls/shr/allen.html>. The 13 base relations (`precedes`, `meets`, `overlaps`, `finished_by`, `contains`, `starts`, `equals`, and their inverses, plus `preceded_by`) used by `Tempo.relation/2` and, as predicates under Allen's own names, by `Tempo.Allen`. For ordering rather than relating, `Tempo.compare/3` returns `:lt | :eq | :gt` and makes `Tempo` usable as an `Enum` sorter module.
