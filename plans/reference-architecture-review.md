# Tempo 2.0 as a reference architecture: a review

**Status:** review, 2026-10-15, against `main` at `a2ac91b` (Elixir 1.20.2, OTP 29.0.3, tz 0.28.4 with tzdata 2026d). Answers three questions the user asked once the redesign of [architecture-redesign.md](architecture-redesign.md) was built: whether the implementation can stand as a reference architecture for developers in other language ecosystems, where its performance can be improved by architecture, data structure or algorithm, and what the TIME 2027 submission ([papers/time-2027](../papers/time-2027/extended-abstract-body.tex)) should now say. The engine was read end to end (`Tempo.Unit`, `Scale`, `Zone`, `Calendar`, `Expand`, `Walk`, `Spans`, `Children`, `Algebra`, `Allen`, `Recurrence`, `Select`, `Shift`, `Validate`), the public surface and guides were sampled, the benchmark was rerun, four cases were profiled function by function with `tprof`, and one assumption of the zone layer was checked against the whole zone database.

## 1. Summary

The architecture is sound and will read well to a critical audience: one struct whose meaning is an ordered sequence of half-open spans, integer positions on one of three frames, one sweep for every set operation, one four-comparison classifier from which the composition table is derived at compile time, one calendar contract of eighteen questions, and a named error wherever the laws give no answer. The implementation holds to it: 26,862 lines (14,524 of code) replace 82,875, each concept is implemented once, and the conformance is held by oracles written apart from the library. Those are the things a reader from Java, Rust or TypeScript will check first, and they will find them.

Four things stand between the code as it is and a reference implementation that survives that reader's second look, in order of weight:

1. **The zone layer keeps hidden mutable state in the process dictionary and rests on an assumption the zone database breaks.** `Tempo.Zone` samples a zone's offset at points six days apart and reasons that no zone's offset changes twice between them. In tzdata 2026d, America/Scoresbysund changed twice within one hour on 2024-03-31, and Tempo places 2024-03-31T00:30:00Z there an hour late (section 3.1). The fix is the structure every other ecosystem uses: a transition table per zone.

2. **The engine's internal currency is the public struct.** A span the engine has just built from two positions is handed on as a `%Tempo{}` of two value ends and placed again by the next step, so a union places each member span four times and a weekly rule reckons a value's frame twenty-one times an occurrence. The code already carries positions beside spans in four ad hoc shapes; naming one is the architectural move (section 3.2 and 4.3).

3. **The model exists only in Elixir.** The nine laws, the forms, the contracts and the algorithms are written in `plans/architecture-redesign.md` in Elixir terms and project history. A reader in another ecosystem needs the model as a language-neutral specification: algebraic data types, the denotation function, the sweep, the classifier, the calendar and zone contracts, the error taxonomy, the complexity of each operation (section 3.3).

4. **The oracles are not portable.** The RRULE measure, the set-operations measure, Allen's axioms, the clock-change check against `DateTime` and the totality corpus are the strongest evidence the implementation is right, and they are Elixir test support. Exported as fixtures (input text, operation, expected text), they become the conformance suite a port in any language runs (section 3.4).

On performance, three moves are architectural and the rest is micro-optimisation: the positioned currency of item 2, the transition table of item 1, and a compiled day-number matcher for plain rules in front of the general selection engine (section 4.3). The profile puts the general engine's expansion machinery, unit classification and zone sampling at about half of a rule's time, and the zone database's own period computation at a sixth of a rule that runs twenty years ahead.

The paper is updated in this review's branch of work: it described the 1.x types (`Interval`, `IntervalSet`, `anchor/2`, `align/3`, `ZoneGapError`) and an explicit span `2026-01-01/2026-02-01` as `[Jan 1, Feb 1)`, which law 9 now reads as through 1 February. Section 5 lists what changed.

## 2. What a critical reader will respect

Each of these is something a reviewer from another ecosystem would look for and not expect to find in a date library.

* **A denotational semantics, stated and then implemented once.** Law 1 (`spans(E)`) is `Tempo.Spans.spans/2`, and every operation is written on its output. There is one walk (`Tempo.Walk`), one expansion (`Tempo.Expand`), one sweep (`Tempo.Algebra.sweep/5`), one classifier (`Tempo.Allen.Classifier`), one arithmetic (`Tempo.Shift`). The plan's section 2.2 counted ten walks and five Allen tables before.

* **Integer positions on explicit frames.** A position is a microsecond tick from 0000-01-01 on the UTC line or the floating line, or a tick from a cycle's start for a value with no year (`Tempo.Scale`). Every relation is four integer comparisons; every set operation is a sweep over sorted integers. Two frames never meet silently: a floating value beside a zoned one is a `Tempo.FrameError`. This is the Vilain and Kautz reduction used as an engine under an interval ontology, and the paper says so.

* **The composition table cannot disagree with the classifier.** `Tempo.Allen` derives all 169 cells at compile time by placing three intervals every way on eight points (six endpoints need at most six distinct values, so the enumeration is complete) and classifying each pair. The published table is then a check, not a source.

* **Written ends read as they are said (law 9).** `2026/2028` is three years and `T09/T17` eight hours, by the class of the unit the end is written to, decided by `Tempo.Unit.calendar?/1` alone. The rule reconciles EDTF and ISO 8601-2 Annex A with the half-open model without a notation for an exclusive end. It is the one semantic choice in the library with no direct precedent, and the paper now presents it as such.

* **One calendar contract, held by a test.** `Tempo.Calendar` is the only module that names a calendar's implementation, asks eighteen questions and never asks what kind of calendar it is talking to; `test/tempo/calendar_surface_test.exs` holds the library to it. The day scale is the proleptic Gregorian day number, which is the fixed date of Reingold and Dershowitz, so every calendar in Calendrical joins it without a conversion path through another calendar.

* **Refusal over guessing.** Nine exceptions, each a reason the laws give: a reading the clock skips, two calendars in one expression, a value with no year asked where it lies, a bound on work exceeded (`Tempo.Limit.take/2` refuses rather than truncates). A reviewer who probes the edges finds a named error, which is what they are probing for.

* **Oracles written apart from the library.** `test/support/rrule_measure.ex` expands 192 rules from three starts independently of the engine and is itself held to RFC 5545's examples; `set_operations_measure_test.exs` checks every pair of sets of up to two members between five points by integer arithmetic on `Date` and `DateTime`; `allen_axioms_test.exs` holds the composition table to what three spans give; `change_of_the_clock_test.exs` holds twelve zones over twenty-one days to `DateTime`; `total_test.exs` holds every operation on every corpus value to an answer or a named error. 2,443 tests, 92.8% line coverage.

* **The size.** A reader who is told the laws compress an implementation threefold will doubt it; the line counts in the plan's section 5.5 and the git history let them check.

## 3. What a critical reader will attack

### 3.1 The zone layer: hidden state, and an assumption the database breaks

**The finding.** `Tempo.Zone` reads the zone database at points six days apart (`@sample_spacing`), keeps what it learns in the process dictionary under `{Tempo.Zone, name, stretch}` and `{Tempo.Zone, name, :steady}` keys (`known_days/2`, `known_steady/3`, `steady_through/3`), forgets everything once 40,000 answers are kept by walking every key in the dictionary (`forget_days/0`), and reasons from the comment "since 1900 no zone's offset has changed twice within a week (the shortest gap in the database is 166 hours)". `Tempo.Recurrence` likewise keeps the start of a walk's next period under `{Tempo.Recurrence, :next_start}` (`start_at/3`, `next_start_at/3`).

**The assumption, checked.** A script over every `Zone` of tzdata 2026d (340 zones) through `Tz.PeriodsProvider.periods/1`, taking consecutive offset changes since 1900:

| Gap between two changes | Zones |
|---|---|
| 597,600 s (166 hours) | America/Cambridge_Bay 2000; America/Boa_Vista, Noronha, Recife 2000; Asia/Gaza and Hebron in 2040, 2054, 2072 |
| 3,600 s (one hour) | America/Scoresbysund, 2024-03-31 00:00Z (base offset -01:00 to -02:00) and 01:00Z (summer time begins) |

The 166-hour cases are safe, as the comment says: six days is 144 hours. The one-hour case is not. The offset before the pair is -01:00 and after it is -01:00 (summer time on the new base), so `across/2` sees the same offset at both samples and `known_days/2` records the stretch as steady. Reproduced against `DateTime` with the tz database:

```
2024-03-31T00:30:00Z   DateTime: 2024-03-30T22:30:00-02:00   Tempo.shift_zone: 2024Y3M30DT23H30M0S[America/Scoresbysund]
```

One zone, one hour, one year: small in effect, but it is exactly the probe a critical reader makes of a library whose claim is that it refuses rather than guesses, and the library's own rule (law 7: "holds no number a calendar would answer") applies to the zone database as it does to a calendar. `@sample_spacing`, `@steady_span` and the two-day window of `offsets_at_wall/2` are numbers the database would answer.

**What the case turned out to be (added 2026-10-15, later the same day).** The two changes an hour apart are the `tz` library's and not IANA's: `zdump -v America/Scoresbysund` shows one change at 01:00Z, of `isdst` alone, with the offset -01:00 before and after, where `tz` compiles an hour at -02:00 from 00:00Z (TODO.md, under upstream). That changes the report of the finding and not the conclusion: Tempo must say what the database it is given says, at every tick, and a sampling scheme cannot promise that for any database. The table was built the same day (decision 73).

**Why it matters beyond the defect.** Every other ecosystem's zone type is a transition table: `java.time.zone.ZoneRules` holds its transitions and the rules that generate the rest, `Temporal.TimeZone` is implemented over one, Rust's `chrono-tz` compiles one. A reader who finds a sampling scheme in a process-local cache instead will read it as a workaround for an API gap, which it is: Elixir's `Calendar.TimeZoneDatabase` answers at a point and lists nothing. The TODO's performance note already names this ("A zone is asked by point").

**The fix.** A transition table per zone, immutable and shared, as `Tempo.Zone`'s own data structure:

* Define the question Tempo needs, `transitions(name, from_tick, to_tick) :: [{tick, offset}]`, as an optional richer contract beside `Calendar.TimeZoneDatabase`. Adapt `tz` to it (`Tz.PeriodsProvider.periods/1` already lists every period) and `tzdata` likewise.

* With a point-only database, build the table by the wall-datetime API rather than by bisection: `time_zone_periods_from_wall_datetime/2` answers `{:gap, {period, limit}, {period, limit}}` and `{:ambiguous, ...}`, and the limits are the transition instants. The residual assumption (no two changes between two samples that return to the same offset) is then stated once, with the measured 166 hours beside it, and checked in CI by the script above against the vendored database, so that the next tzdata that breaks it fails a test rather than a user.

* Hold the table in `:persistent_term` keyed by zone and database version, or in the `%Tempo.Zone{}` value itself; either removes the process dictionary from the core. Every question `Tempo.Zone` answers today (`offsets_at_wall/2`, `offset_at_utc/2`, `first_shown/2`, `unit_end/4`, `steady_offset/4`, `day_skipped?/3`) becomes a binary search in the table, and the halving search of `first_change/4` goes.

The `Tempo.Recurrence` key is a smaller instance of the same thing: a walk's next start is state of the walk, and belongs in the accumulator of the `Stream.unfold/2` that drives it, not in the process.

### 3.2 The engine's currency is the public struct

**The finding.** `Tempo.Spans.spans/2` yields `%Tempo{}` spans with two value ends. The engine built each from positions it held (`Spans.span_of/2`, `Recurrence.occurrence_at/4`, `Algebra.written/3`), and the next step places it again through `Spans.extent/1`, which reads the units through `Tempo.Unit` (seven list scans: `cyclic`, `anchored?`, `plain?`, `concrete?`, `date_units`, `clock_units`, `clock?`) and the calendar. The profile makes the cost visible: a union of two sets of 100 calls `Scale.line_extent/5` 800 times for 200 member spans and 100 results, and `Tempo.Unit` is 14.5% of its time; a weekly rule of 780 occurrences calls `Scale.frame/3` 16,477 times and `Zone.known_steady/3` 58,332 times, which is 21 and 75 an occurrence.

The code already knows this. Four shapes carry a position beside a span: `Algebra.positioned/0` (`%{start, stop, span, side}`), `Recurrence`'s `{occurrence, extent}` pairs, `Expand.child/0` (`{value, {first, after_last}}`) and `Select`'s `:extent` option. Decisions 56, 61, 62 and 63 added these one by one, measured a fifth representation of a *value* (units beside its position) and declined it at about a quarter of an occurrence.

**Why it matters.** A reader expects the boundary between a library's public values and its engine's working representation to be one line. Here it is four lines in four modules, and the public struct crosses it in both directions, so a port in another language has to discover the invariant ("a span's ends are values that were built from these positions") by reading the engine. It is also where the memory goes: one occurrence of a weekly rule is 1,448 bytes flat (three structs, two keyword lists, the zone held three times), and the benchmark allocates about 31 KB an occurrence to make it.

**The fix.** One positioned span type for layers 2 and 3, `{start, stop, written}` with `written` the `%Tempo{}` span, produced by `spans/2` and consumed by `Algebra`, `Allen`, `Select`, `Recurrence` and `Children`; the `%Tempo{}` alone crosses to layer 5 in `Tempo.members/2` and the Enumerable. This is not the representation decision 63 declined: it threads no second shape of a value, it names the shape the engine already uses and gives it one producer. Section 4.3 puts a measurement on it.

### 3.3 The model is written in Elixir, not in a language-neutral form

**The finding.** The plan is the only statement of the model, and it is 1,497 lines of which the laws are 20 and the rest is Elixir types, module budgets, review history and phases as built. The public docs (`guides/design-decisions.md`, `guides/temporal-formalisms.md`, `guides/enumeration-semantics.md`, `guides/iso8601-grammar.md`) are excellent on *why* and on the written grammar, and say nothing of the engine.

Elixir idioms stand in for the model in places a porter has to translate: a value's units are a keyword list whose order is significant (`[year: 2026, month: 6]`); what a unit holds is a tuple vocabulary (`{:mask, digits}`, `{n, [margin: m]}`, `{:group, ...}`); a frame is a map with an optional key; `Enum` over an expression yields children or members by law 6. None is wrong; each needs its language-neutral statement.

**The fix** (built the same day as `guides/architecture.md`). A document written for the porter and not the Elixir user:

1. The data model as algebraic types: `Expression = Value | Span | Every | All | One | When`; `Held = Int | Set | Mask | Group | Annotated | Leap | Selection`; `Frame = UTC | Floating | Cycle(unit)`; `Position = Int`.
2. The denotation: `spans : Expression × Window → [Span]`, with law 9's rule for written ends and law 6's for enumeration.
3. The algorithms: the sweep (edges sorted, coverage counts, a predicate on the counts, results credited to members), the classifier (four comparisons), the expansion (children under a prefix, selection by held shape), the walk (periods on the day scale, ticks on the tick scale), the shift (date part through the calendar, clock part in ticks).
4. The contracts: the calendar's eighteen questions and the laws of plan section 8.4; the zone's questions (section 3.1's table once built).
5. The error taxonomy: the nine exceptions and the reason each carries.
6. A complexity table: relation O(1) after placing, set operation O((m+n) log(m+n)), expansion O(period) per period, with the places a calendar or a zone is asked.
7. The precision model, stated: a tick is a microsecond, positions are integers (small integers on a 64-bit BEAM through year 9999), a written fraction of a second keeps its precision as `{value, places}`. Java, JavaScript's Temporal and Rust count nanoseconds; the reader will ask.

### 3.4 The oracles are not portable

**The finding.** The strongest evidence that the implementation is right is in `test/support`: `rrule_measure.ex` (192 rules, three starts), the set-operations measure, the Allen axioms, the clock-change check, the totality corpus (`test/support/matrix`), the grammar generator and mutator. All are Elixir. The one language-neutral corpus is `test/support/data/*.txt` (ISO 8601 and RFC 3339 texts) and the iCalendar fixtures.

**The fix** (built the same day: `test/fixtures/conformance/`, written by `scripts/conformance_fixtures.exs`, with the totality fixture holding the refusals of the expressions written by hand rather than every cell's answer, which would be 20 MB and a golden file). Export the oracles' cases as fixtures: for each, the input text, the operation and options, and the expected answer as text (or the expected error's name). The RRULE measure becomes a file of rules, starts and occurrence lists; the set-operations measure a file of operand pairs and results; the clock-change check a file of zone, day, hour and expected reading; the totality corpus a file of expression and, for each operation, answer or error. A port runs the files; Tempo's own tests read the same files, so the two cannot drift. This also answers the paper's "supplementary material at the repository" with something a reviewer can run.

### 3.5 Smaller points

* **Law 6 needs its defence up front.** `Enum` over a month yields days and over a set yields members. The reader who meets this in the API reference without `guides/enumeration-semantics.md` will call iteration type-dependent. The one-line defence (a singular expression is made of its children, a plural one of its members; `Tempo.members/2` and `Tempo.walk/3` say which you mean) belongs in the `Tempo` moduledoc and the paper.

* **`Tempo.Limit.values/0` is read per element.** The Enumerable implementation calls it, and so `Application.get_env/3`, once for every element yielded (377 calls in a walk of 365 days). Read it once when the enumeration begins. A reader would also prefer the bound as an option to the global; keep the global as the default of a `:limit` option.

* **`Tempo.Calendar.calendar?/1` uses reflection** (`Code.ensure_loaded?/1`, `module_info/1`). It is called at construction only (`Build`, `Builder`, `Reader`, `Tempo.new/1`), so the cost is nothing; a port should know it is a behaviour check and not a registry.

* **The public surface is large and flat.** `Tempo` has 85 public function names in 4,870 lines, and `Interval`, `IntervalSet`, `RecurrenceSet`, `Duration`, `Allen`, `RRule`, `Cron`, `ICal`, `JSCalendar`, `Event`, `Workdays`, `Territory`, `Clock`, `Builder` beside it: 32 public modules. `plans/public-surface.md` maps it; a porter needs that map in the docs, grouped as the plan's layer 5 groups it, and a statement of which modules are the core API and which are adapters.

* **Two numbers in `Tempo.Recurrence` are the engine's own**: `@quiet_periods 2` and the horizon of `horizon/1` (two years for a rule of times of day, a calendar's cycle or a thousand years otherwise). Both are sound and both are undocumented outside the module; the specification of 3.3 should state them as the rule's termination argument, since a reader will ask how a rule that selects nothing is known to end.

* **The season table and Easter in `Tempo.Calendar`** are asked of Calendrical, as the project's rule requires; the adapter's own knowledge (the `Calendar.ISO` routing, the Gregorian for a solar term, the registry by name) is three things, listed in TODO under "Revisit the calendar adapter". Fine as it is; say in the spec that these three are the adapter's and no other module's.

## 4. Performance: architecture, data structures and algorithms

### 4.1 What was measured

`bench/against_1_6_bench.exs` on 2026-10-15 (Apple M1 Max, OTP 29.0.3, JIT). The 1.6.4 results file was not present, so the ratios are those recorded in `TODO.md` on the same day from the last run that had it.

| Case | Median | Memory | Against 1.6.4 (TODO, 2026-10-15) |
|---|---:|---:|---|
| relate a month and a day | 2.5 µs | 5 KB | 2.4 times |
| compare a month and a day | 2.5 µs | 5 KB | 14 times |
| walk the hours of a day a zone springs forward | 3.0 µs | 11 KB | 0.8 times |
| write ten values | 10.5 µs | 16 KB | 0.8 times |
| read ten texts | 94 µs | 129 KB | 0.03 times |
| walk the days of a year | 109 µs | 325 KB | |
| expand daily 30 | 174 µs | 293 KB | 2.0 to 6.4 times, by rule |
| union of two sets of 100 | 370 µs | 753 KB | 3 times |
| difference of two sets of 100 | 469 µs | 969 KB | |
| intersection of two sets of 100 | 483 µs | 998 KB | |
| expand yearly 4th Thursday of November 50 | 1.6 ms | 20 MB | |
| expand weekdays 520 | 3.2 ms | 5.8 MB | |
| expand hourly 720 | 5.5 ms | 12 MB | |
| expand weekly MWF 780 | 12.9 ms | 25 MB | |
| expand last weekday 240 | 26.2 ms | 56 MB | |

Memory is allocation during the run, not what is retained: the 780 occurrences of the weekly rule retain 1.1 MB (1,448 bytes each flat, 816 shared) against 25 MB allocated to produce them.

### 4.2 Where the time goes

`tprof` by own time, `mix run` with the OTP `tools` path added (Mix prunes it).

**Weekly Monday, Wednesday, Friday, 780 occurrences.** `Enum` 18%, `Tempo.Expand` 14%, `Tempo.Zone` 11%, `Calendar.ISO` 8%, `Stream` 7%, `Tempo.Unit` 6%, `Tempo.Scale` 4%, `Tempo.Spans` 4%, `Process` 3%, `Tempo.Select` 3%. Calls an occurrence: `Zone.known_steady/3` 75, `Process.get/2` 83, `Unit.clock?/1` 65, `Calendar.ISO.days_in_month/2` 40, `Zone.offsets_at_wall/2` 35, `Calendar.ISO.date_to_iso_days/3` 27, `Scale.frame/3` 21, `Expand.readings_at/5` 16.

**Last weekday of the month, 240 occurrences (twenty years from 2023).** `Calendar.ISO` 16%, `Enum` 18%, `Tempo.Expand` 8%, `Tempo.Zone` 7%, with `NaiveDateTime` 4%, `Tz.PeriodsBuilder` 2.5% and `System` 2%: the tz database computing periods past its precompiled years on each question (41,411 calls of `Calendar.ISO.naive_datetime_to_iso_days/7` inside the database), which the TODO names. `Enum.uniq_list/3` is 2.6% on its own: the sort-and-dedupe of candidates in `Select.picked/5`.

**Union of two sets of 100.** `Enum` 30%, `Tempo.Unit` 15%, `Tempo.Spans` 11%, `Tempo.Scale` 10%, `:gb_sets` 8% (the merge of members in `Spans.in_time_order/1`), `Calendar.ISO` 6%. `Scale.line_extent/5` is called 800 times for 300 spans.

**The days of a year, walked.** `Stream` 26%, `Tempo.Walk` 13%, `Tempo.Children` 8%, `Tempo.Limit` 4% and `Application` 4% (the per-element bound of 3.5). Nothing architectural; the walk is a stream of `Calendar.date/2` and a struct a day.

### 4.3 The moves, in order of return

Each is an architecture, data-structure or algorithm change, and each keeps the one engine as the meaning. None reintroduces a parallel path the measures do not cover.

**A. One positioned currency through layers 2 and 3** (section 3.2). Expected effect: the set operations lose three of four placings a span and most of `Tempo.Unit`'s 15%; relating and comparing two values lose their second placing; a rule's occurrence is built once from the positions the walk already has and `Scale.frame/3`'s 21 calls an occurrence go. It also halves the retained size of an occurrence (one span struct, two integers, the frame shared). Decision 63's measurement was of a different change and does not settle this one; measure it on the union and the weekly rule first.

**B. A transition table per zone** (section 3.1). Built the same day (decision 73); measured, it made rule expansion about a third slower, since a question of the table (250 ns: the configured database, the data version, the persistent term, the search) costs more than a hit in a process-local cache (55 ns) and a weekly rule asks the zone 45 times an occurrence. The cost is the count of questions, which A removes. Expected effect, before it was built: `Tempo.Zone` and `Process` (14% of the weekly rule, 9% of the monthly) become a binary search in an immutable tuple, and the halving search of `first_change/4` and the sampling disappear. For a rule in the 2040s under `tz`, the database's own period computation (a sixth of the monthly rule) is paid once when the table is built rather than at every question. This is also the correctness fix.

**C. A compiled day-number matcher for plain rules, in front of the engine.** A rule whose parts are whole numbers and lists of months, days of the month and days of the week, with or without a position, in a calendar whose week is a continuous cycle (every calendar Tempo has) is a predicate on the day number: the day of the week is `mod(day + k, days_in_week)` with `k` fixed once from one calendar question, the day of the month is `day - first_of_month + 1` with the month spans the calendar already answers, and a position is an index into the days that pass. The walk is integer arithmetic over `[first, after_last)` with one calendar question a month and no expansion, no `Tempo.Unit`, no candidate list to sort and dedupe. The general engine stays the meaning of every rule; the matcher is proved equal by `rrule_measure_test.exs` (192 rules, three starts), `rfc5545_examples_test.exs` and `cron_test.exs`, which already hold the engine to an independent expander, and the matcher is taken only where its preconditions hold (`Select.on_its_day/4` is this idea for a period of one day; this generalises it to a period of any length). Expected effect: the weekday, weekly and monthly cases by an order of magnitude; the TODO estimates the selection's analysis of its parts at a tenth of an occurrence and "building, checking and placing each candidate" at the rest, and the matcher removes the candidates. 1.6.4's weekday fast path was this, written beside its resolver; here it is written under the measures.

**D. Labels by arithmetic within a period.** Independent of C and cheaper: `Expand.day_children/4` asks `Calendar.date/2` for every day of a month to learn its day of the month, which is `day - first + 1`; `ordinal/2` asks the date and the year's span for every day; `weekday/2` asks the date and then the day of the week. Each is one calendar question per period and arithmetic per day. `Calendar.ISO` is 8% to 16% of a rule, most of it `date_to_iso_days/3` re-validating dates the calendar produced.

**E. Occurrences written lazily.** An occurrence today is a span of two value ends, each a `%Tempo{}` with the calendar, the zone struct and the metadata map, made for every occurrence whether or not the caller reads it as text. With A in place the occurrence is a positioned span whose written form is made in `Tempo.members/2` or `inspect/1` when asked, and a caller that takes a count, a filter or a comparison never pays for the units. This is where the 31 KB an occurrence of allocation goes.

**F. Micro, listed for completeness and not for this review:** `Tempo.Limit.values/0` once per enumeration (3.5); `Unit.clock?/1` called 50,000 times in a rule, which A removes; `Enum.filter` and `Enum.reject` chains over units (`Unit.date_units/1`, `clock_units/1` each a pass) replaced by one split; `Select.in_years?/2` flattening its list of years on every candidate.

### 4.4 What not to do

* Do not put a second representation of a *value* through the engine (decision 63 stands). A is about spans, which are already positioned in four places.

* Do not special-case the Gregorian calendar in the engine. C's arithmetic is on day numbers and the calendar's own month spans, and holds for every calendar with a continuous week; `Tempo.Calendar` stays the one place that knows which module answers.

* Do not cache in the process dictionary again. A table in `:persistent_term` or in the value is shared, immutable and visible to a reader; a process-local cache is neither.

* Do not hand-tune `Enum` chains before A, which removes most of the calls.

## 5. The TIME 2027 submission

The extended abstract was last touched on 2026-09-04 and described the 1.x implementation. The body is updated in place ([extended-abstract-body.tex](../papers/time-2027/extended-abstract-body.tex)) and the PDF rebuilt. What changed:

* **The model is now the paper's.** Law 1 (every expression denotes an ordered sequence of half-open spans) and the one struct of six forms replace "two forms of interval that interconvert"; `anchor/2` and `align/3` become the `:within` window and `at/2`, `on/2`, `in_zone/2`; the three frames (UTC line, floating line, cycle) are named, and a value with no year is an expression on a cycle rather than "a non-anchored value".

* **Written ends (law 9) are stated as a contribution.** The old text read `2026-01-01/2026-02-01` as `[Jan 1, Feb 1)`; under law 9 it is through 1 February. The paper now gives the rule (an end written to a calendar unit is read through, to a clock unit as a boundary), its grounding in speech, EDTF and ISO 8601-2 Annex A, and lists it among the open questions for the symposium.

* **The names are the current ones.** `Tempo.compose/2` is `Tempo.Allen.compose/2`; `ZoneGapError` is `Tempo.ZoneError` with reason `:gap`; `relation_matrix/2` and `covered?/2` are `Tempo.IntervalSet`'s; the propagation of qualitative networks is the companion `tempo_network` package; the repository is `elixir-tempo/tempo`.

* **The set operations are described as built.** Every operation returns a set; `union/3` preserves members, the others trim to covered time, and a result is credited to the operand members that cover it so metadata survives (decision 42); operands are brought to one calendar, two named zones meet on the UTC line, and a floating value beside a zoned one is refused unless placed. The old "first-operand-wins" paragraph becomes this, and the discussion notes that the stricter stance partly adopts the alternative the old paper invited comment on.

* **Daylight saving is described as falling out of the walk.** A day across a change is 23 or 25 hours because its ends are; an hour a clock skips in part is as long as the clock shows; a day a zone leaves out is no day of its walk. The gap and fold handling stays, with the current names.

* **The composition table's derivation is the real one.** Derived from the classifier by enumerating every placement of three intervals on eight points, then held to Allen's table by test.

* **A short implementation paragraph.** The size of the redesign against the implementation it replaced, the oracles, and the benchmark in one sentence each, so that "existence proof" has a number behind it.

* **References.** IXDTF is RFC 9557 (April 2024), not the draft.

The chrononetworks companion paper was not reviewed; its footnote in the abstract stands.

## 6. Recommended order of work

1. **B, the transition table** (section 3.1): a correctness fix with the process dictionary removed as its side effect, and the CI check of the sampling assumption until it lands. Record the Scoresbysund defect in `TODO.md` now (done in this review).
2. **A, the positioned currency** (section 3.2), measured on the union and the weekly rule before and after.
3. **D, labels by arithmetic**, small and independent.
4. **The specification** (section 3.3) and **the fixtures** (section 3.4), which are what makes the result a reference implementation rather than a good library; they can be written while A and B are built, since neither changes the model.
5. **C, the compiled matcher**, last, because A and B change what it costs and the measures that prove it are already in place.
