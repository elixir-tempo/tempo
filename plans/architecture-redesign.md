# Tempo: architecture review and redesign

**Status:** accepted, 2026-10-13: the user agreed to all eighteen decisions and asked for phase 0 on the `redesign` branch. The release's version is undecided; it may replace the unreleased 2.0 work. Section 4.2, on written ends, was added at the user's request the same day. Written against `main` at `a43b944` (Calendrical `3a85c80`, Localize `0d89acb6`). Answers the brief in [architecture_review.md](architecture_review.md).

## 1. Summary

Tempo's ideas are right and its public API is largely right. The implementation is not: 82,875 lines of `lib/` (plus 72,885 of tests) carry the same handful of concepts in many parallel forms, so that the principles the brief states, time as intervals, one resolution-independent core, set operations as the primary operations, calendar independence, are each true in some module and contradicted in another. The review found ten distinct walk implementations, six sweep implementations, five copies of the Allen table, four selection engines, two complete arithmetics, three DST classifiers, two endpoint comparators and a calendar surface of 41 callbacks reached from 157 sites, plus 393 sites that rewrite every argument and result to swap `Calendar.ISO` for its implementation.

The redesign rests on one observation that the current code never states: **every Tempo expression denotes an ordered set of half-open spans, and every operation is defined on spans.** Once that is written down, one data structure holds a value, an interval, a recurrence and a set; one function (`spans/2`) gives any expression its meaning; one sweep performs every set operation; one classifier performs every Allen relation; one expansion engine performs enumeration and selection alike; and the calendar is asked one kind of question, what span of days a period is and what period a day belongs to, through a contract of eighteen callbacks, five of which are already Elixir's own.

The five moves:

1. **One struct.** `%Tempo{}` is an expression with a `:form` (a value, a span, a recurrence, an all-of set, a one-of set), one calendar, one zone and metadata. `Tempo.Interval`, `Tempo.IntervalSet`, `Tempo.RecurrenceSet` and `Tempo.Set` stay as the modules that build and read those forms, not as types. `Tempo.Duration` stays the one companion.

2. **One meaning.** `Tempo.spans/2` turns any expression into a stream of concrete spans, each a pair of positions on a scale (ticks on the UTC line, the floating line, or a cycle) with its written ends kept. Enumeration, set operations, relations, selection and shifting are all written over spans, so there is nothing to keep in parity.

3. **One engine each.** A coverage sweep for the set algebra (prototyped and verified against a point-set oracle on 3,000 random pairs, section 7.6). A four-comparison classifier for Allen (verified exhaustive and inverse-correct, section 7.7). A single expansion over a value's units for enumeration, masks, groups, selections and RRULE parts (section 7.4). One stepping rule for walks: calendar units step on the day scale, clock units step on the tick scale.

4. **One calendar question.** Tempo asks a calendar for the span of a period (`year/1`, `month/2`, `week/2`, `quarter/2`), the conversion between a date and a day number, a date's labels (`day_of_week/4`, `week_of_year/3`), validity, a shift and three naming callbacks. Everything else Tempo asks today (counts, number lists, `plus/6`, `diff/3`, `day_of_year`, `date_from_day_of_year`, `days_in_week`, `years_in_cycle`, the kind of calendar) is derived on the day scale or dropped. Verified across eleven calendars, including a reform calendar with an eleven-day gap and a ten-month year, two lunisolar calendars, a shifted-new-year Julian and a week calendar (section 8.2). `Calendar.ISO` is routed to its implementation in one adapter module, and the `inside`/`outside` term rewriting goes.

5. **One reader.** A hand-written recursive-descent reader whose functions are the productions of a written ABNF of ISO 8601-1, ISO 8601-2 and RFC 9557, producing `%Tempo{}` forms in one pass, followed by one calendar-aware validation pass. Two stages where there are seven today.

The public API as the guides document it is preserved in its names and its examples (section 9), with these proposed changes to its meaning, each a decision for the user (section 10): enumeration of a plural expression yields its members rather than their sub-points; a materialised span walks at the resolution of its ends and the `:unit` field goes; the struct types `%Tempo.Interval{}`, `%Tempo.IntervalSet{}`, `%Tempo.Set{}`, `%Tempo.Range{}` and `%Tempo.RecurrenceSet{}` become forms of `%Tempo{}`; and the network solver and scheduler move to a companion package. A set of smaller API simplifications is proposed in section 9.3.

The estimated size is about 15,000 lines, of which the core (layers 0 to 3 of section 5.3) is about 4,500, against 82,875. The existing test corpus, in particular the operation matrix, the reference tests and the calendar census, is the oracle for the rewrite (section 11).

## 2. What was reviewed and how

* **The code.** All of `lib/` was read in seven passes by subsystem (parsing, enumeration, set operations, selection and RRULE, comparison and Allen, arithmetic, calendar surface), each pass recording data shapes, algorithms, calendar calls and duplication with file and line references. Those references are kept in this document where a claim rests on them.

* **The intent.** The brief; `CLAUDE.md`; the guides, in particular the glossary, the enumeration semantics, the set operations and the operation matrix; the README; the TIME 2027 extended abstract; and the prior plans in `plans/` for what they record of the user's rulings. Following the user's instruction of 2026-10-13, the prior plans' *decisions* are not treated as binding; the *intent and the public API* are.

* **The dependency.** Calendrical at the pinned `3a85c80`, read from `~/Development/localize/calendrical` because the copy under `deps/` was a stale hex 1.3.0 until `mix deps.get` was run for this review. Localize is treated as stable and is not asked to change.

* **Prototypes.** Three scratch programs were run to test the load-bearing claims before they were written down: the one-sweep set algebra against a brute-force point-set model, the four-comparison Allen classifier against exhaustive enumeration, and the day-scale expansion across eleven Calendrical calendars. Their results are in sections 7.6, 7.7 and 8.2. Current behaviour quoted in section 9 was taken from the compiled library at `a43b944`.

### 2.1 Size

| Area | Files | Lines | Notes |
|---|---|---|---|
| `Tempo` module | 1 | 17,778 | 271 `def` clauses, about 150 public functions |
| ISO 8601 reader (tokenizer, parser, group, AST, unit, validation, mask) | 15 | 11,634 | 3,300 of NimbleParsec combinators, 1,400 hand-written |
| Enumeration (enumeration, zone, skipped readings, protocols, steps, cycle, unit values) | 11 | 5,897 | |
| Set operations (operations, interval set, backends, recurrence set) | 8 | 4,558 | |
| Selection and RRULE (select, rrule, rule, selection, expander, encoder, cron) | 7 | 11,271 | |
| Comparison and Allen (compare, interval, allen, relations, composition) | 5 | 6,861 | `interval.ex` alone is 4,441 |
| Arithmetic (math, rounding, duration) | 3 | 5,040 | |
| Networks and scheduling | 9 | 4,462 | one-way dependency on the core |
| Text (format, explain, inspect, sigil) | 4 | 7,375 | |
| Interop (ical, jscalendar, event, workdays, territory, clock, zone database, leap seconds) | 10 | 2,950 | |
| Exceptions | 24 | 1,340 | |
| **Total** | **109** | **82,875** | |

### 2.2 The duplication, counted

| Concept | Implementations today | Where |
|---|---|---|
| Walking a span | 10 | component DFS `enumeration.ex:183-442`; interval stepper `protocol/enumeration/range.ex:551-981`; closed forms `interval/steps.ex:138-461`; clock walk `steps.ex:521-643`; recurrence period walk `tempo.ex:10500-11467`; doubling-window walk `tempo.ex:9156-9235`; per-period selection `tempo.ex:14152-14225`; `Tempo.Range` iterate `tempo.ex:9876-9883`; interval-set concatenation; `Tempo.Set` list |
| Sweep or overlap test | 6 + 4 | `operations.ex:1334, 1393, 1652-1720, 310`; `interval_set.ex:1370-1408, 1483`; plus `relation/2`, backend `overlapping/2`, `overlaps_window?`, conditionals' `falls_on?` |
| The Allen table | 5 | `interval.ex:1656-1707` (code); `network/solver.ex:316-330`; `interval/composition.ex`; `allen.ex:45-59`; three doc copies |
| Everyday predicates | 2 engines | relation sets `interval.ex:3334-3403, 3447-3459`; set algebra `operations.ex:1804-1900` |
| Selection engine | 4 | resolver `rrule/selection.ex`; weekday fast path `select.ex:762-776, 1570-1680`; integer indices `select.ex:1695-1758`; merge/projection `select.ex:2668-2901` |
| Weekday of a date | 5 | `select.ex:1652`; `selection.ex:2824, 2834, 2869, 3454` |
| Nth weekday of a month | 3 | `selection.ex:3952-4011, 2495-2498, 2437-2455` |
| Arithmetic | 2 | `calendar.plus` paths and the O(n) `add_unit`/`subtract_unit` engine `math.ex:91-880` |
| Adding years | 3 | `math.ex:3001, 3210`; `unit_values.ex:353` |
| DST classification | 3 | `zone.ex:39-56`; `steps.ex:521-643`; `enumeration.ex:588-604` |
| Endpoint comparison | 2 + 1 local | `compare.ex:89-161` structural, `compare.ex:1052-1193` UTC; `range.ex:886-949` |
| Time-line projection | 4 | `compare.ex:1187`; `steps.ex:739`; `tempo.ex:6900`; Erlang `:calendar` in the zone modules |
| Three-valued certainty | 2 | `interval.ex:3803`; `network/solver.ex:234-300, 436` |
| Duration comparison | 2 semantics | calendar stepping `interval.ex:3280`; float seconds `duration.ex:412, 631` |
| Cycle wrap rule | 2 | `range.ex:702-731`; `cycle.ex:114-143` |
| Microsecond lifting | 3 | `numbers.ex:558-575`; `validation.ex:1169, 1213`; `duration.ex:747` |
| "Coarsest unit" list | 3 | `parser.ex:421`; `ast.ex:89`; `helpers.ex:379-380` |
| Calendar swap at the border | 393 sites | `inside` 218, `outside` 105, `outside?` 70; `Calendars.inspect/2` 424 more |

## 3. Review: what the implementation does today

Each subsection says what the subsystem is for, how it does it, where it asks the calendar, and what in it is essential against incidental. "Essential" means the behaviour the guides promise; "incidental" means a consequence of how the code grew.

### 3.1 Data structures

Seven structs stand for positioned time: `%Tempo{}` (`tempo.ex:162`, the written value: `time`, `shift`, `extended`, `qualifications`, `calendar`, `metadata`), `%Tempo.Interval{}` (`interval.ex:112`: `from`, `to`, `duration`, `recurrence`, `direction`, `repeat_rule`, `unit`, `metadata`), `%Tempo.IntervalSet{}` (`interval_set.ex:118`: `intervals`, `backend`, `metadata`), `%Tempo.RecurrenceSet{}` (`recurrence_set.ex:45`), `%Tempo.RecurrenceSet.Conditional{}`, `%Tempo.Set{}` (`set.ex:61`: `type`, `set`, `except`, `filter`) and `%Tempo.Range{}` (`range.ex:27`). `%Tempo.Duration{}` is the eighth and the only one that is not a span.

Findings:

* **The same thing has several homes.** A set of values is a list inside a unit (`[1, 3]` for `{1,3}M`), a `%Tempo.Set{}` at the top level, a `{:group, {:all, set}}` triple inside a group, and an `IntervalSet` once materialised. A one-of component set is distributed into a `%Tempo.Set{type: :one}` by the parser (`parser.ex:513-521`) while an all-of one stays a list.

* **`%Tempo.Interval{}` is two things.** It is the written form of `2026-06-01/2026-07-01`, and it is the materialised form of any value (`to_interval/2`). Because the second use must walk like its source, the `:unit` field was added to carry the source's walk granularity (`interval.ex:118`, guide §2.10), which the writer then has to show as a decoration because it is not syntactic. The field is dropped by set operations when they construct an extent and kept when they pass a member through (`operations.ex:1424-1428, 1716`), which is a rule a user has to learn.

* **Calendar and zone are not where the user's rule puts them.** The user's rule is that an extension applies to the whole expression. In the structs, an interval has no calendar and no zone of its own: each lives on each end's `calendar` and `extended` and is kept equal by `propagate_endpoint_frame`, run twice during parsing (`tempo.ex:1249, 1252`) and checked again by `validate_one_calendar` and `validate_one_zone` (`interval.ex:227-228`).

* **`:time` is a tagged list with an open vocabulary.** The public type `token_list` (`tempo.ex:199-214`) omits `:group`, the group-of-set triple, `:fraction`, `:fractions` and `:any`, all of which appear in values. Quarters are months 33 to 36 and halves 40 to 41 in the tokenizer (`helpers.ex:160-184`) and decoded later (`group.ex:164-177`).

* **The border shim.** A value a caller holds is in `Calendar.ISO`; a value Tempo works on is in `Localize.Calendar.ISO`. Every public function has a first clause guarded by `is_outside/1` (57 places) or a test of `outside?/1` (70), and rewrites every argument and every result through `Tempo.Calendars.inside/1` and `outside/1` (`calendars.ex:83-130`, 218 and 105 call sites), which walk every struct, map, list and tuple of the term (`calendars.ex:175-243`). Every message is built with `Tempo.Calendars.inspect/2` (424 sites) for the same reason. This exists because `Calendar.ISO` keeps only Elixir's `Calendar` behaviour and Tempo calls Calendrical callbacks on it.

### 3.2 Parsing

**Flow.** `from_iso8601/2` → a byte-level fast scanner for the common shapes (`tokenizer/plain.ex`, 347 lines) → or the NimbleParsec grammar (`tokenizer/grammar.ex` and six more files, about 3,300 lines of combinators) under a packrat memo kept in the process dictionary (`tokenizer/memo.ex`) → `Extended.split_extended/1` lifts the IXDTF suffix (`extended.ex:216-239`) → `from_tokens/4` (`tempo.ex:1235-1260`) runs nine steps: resolve the calendar, `Parser.parse/2` (which first runs four or five whole-tree `refused/1` walks, `parser.ex:23-397`), `Group.expand_groups/2`, attach the suffix and propagate the frame, `Validation.validate/2` (about 60 `resolve/2` clauses, `validation.ex:589-1357`), attach the suffix and propagate again, place the value on its zone's clock, check the zone, strip calendar names.

**Essential.** The three spellings of a date and time; intervals with the §5.5.1 abbreviated end; recurrences and durations; shifts; §8 qualification at three levels; §9 unspecified digits; §6 sets; §5 groups; §4.4 long years, exponents, significant digits and margins; centuries, decades and ordinal days; §4.8 seasons; §12 selections with §12.10 windows; §13 repeat rules; the IXDTF suffix; calendar-aware validation. The Tempo extensions (`q`, `e`, `m`, `w`, `^`, the `e/o/l/c` filters) are needed for RRULE interoperability.

**Incidental.**

* Two tokenizers for the same language, held equal only by a test (`plain.ex:20-22`); the typed entry points skip the fast one (`tokenizer.ex:242-250`).
* Memoisation with three combinators per memoised rule (`helpers.ex:95-134`) and near-copied parsers kept to avoid re-reading (`date.ex:217-245`), both costs of ordered choice over a grammar with shared prefixes.
* The IXDTF suffix is parsed on every end and member where it is illegal, so that it can be refused afterwards (`date.ex:17-53`, `extended.ex:252-281`).
* Error states encoded as data: a backwards range is a step of `-1` (`grammar.ex:1361-1367`); `:no_range`; `:trailing_qualification` is emitted and never read.
* About a dozen separate walkers over the tree after tokenizing; later stages build token lists by hand and call the parser again (`group.ex:1216, 1301, 1378, 1463`); `Validation` calls `Parser.reduce_list`; `tempo.ex` re-matches the raw input with a regex to rewrite an error (`tempo.ex:1162-1173`).
* `Parser.parse/1` skips the `refused/1` checks and the `ParseError` rescue that `parse/2` has; `parse_duration/1` calls `parse/1` (`tempo.ex:1519`).
* Validation's own comment says it "performs two roles (and maybe should be split)" (`validation.ex:24-31`): range checks and group resolution.
* There is no written grammar. The conformance guide is kept by hand; defects are found by hand (`plans/parser-formal-grammar.md`).

**Calendar.** Through `UnitValues.in_period/3` (`unit_values.ex:97-149`): `month_numbers/1`, `day_numbers/2`, `days_in_month/2`, `days_in_year/1`, `months_in_year/1`, the week counts, `days_in_week/0`, `date_from_day_of_year/2`, `traditional_months/1`, `ordinal_month_from_traditional/3`, `valid_date?(0, 1, 1)` for year zero, `plus/6`.

### 3.3 Enumeration

**Flow.** `Enumerable.Tempo.reduce/3` (`protocol/enumeration/tempo.ex:108-116`) chooses among three machines: the interval-set walk for a selection, the UTC-second clock walk for a zoned sub-day value, otherwise `Enumeration.implicit_walk/1` (`enumeration.ex:85-91`), a lazy depth-first search over a stack of component frames in which each component is expanded against its concrete ancestors (`candidates/3`, `enumeration.ex:854-926`) and every candidate is re-validated by `Validation.validate` on the whole prefix (`enumeration.ex:1036-1057`). `Enumerable.Tempo.Interval.reduce/3` (`range.ex:338-355`) is a second machine: fill the start to the walk unit (`steps.ex:55-90`), step with `Math.add_unit` (`range.ex:959-981`), stop when past the end, classify each value against the zone (`zone.ex:39-56`). `count/1`, `member?/2` and `slice/1` take closed forms in `Steps` (`steps.ex:138-461`), a third machine. Recurrences take a fourth (`tempo.ex:10500-11467`) and a fifth for open windows (`tempo.ex:9156-9235`).

**Essential.** Three functions over one shape: the values a unit takes under a concrete prefix (`UnitValues.in_period/3` and `named/2`, which exist and are right); the cartesian expansion over them; and a half-open step at a unit. Everything the guide promises follows from these.

**Incidental.**

* Ten walks (section 2.2). Filling to the first child is done twice (`enumeration.ex:1364-1373`, `steps.ex:59-90`); week and ordinal dates are rewritten to calendar dates twice (`enumeration.ex:293-312`, `range.ex:791-797`); the cycle-wrap rule exists twice; a local `compare_time` duplicates `Tempo.Compare` and returns `:eq` for mismatched units (`range.ex:944-949`).
* Three DST mechanisms (`zone_status/1` per value, the clock walk on UTC seconds, and a `shown?/1` filter that drops gaps but does not double the fold hour, `enumeration.ex:588-604`).
* `count/1` and `reduce/3` of the same value use different machines and agree only by test.
* The rule "walk at the next finer unit" is broken in three documented places: a second walks tenths implicitly but its span walks one second (guide §5.6); a mask walks its candidates but its span walks the covering extent; a set-valued value yields its finest written unit while its own materialised set yields sub-points (section 9.2 shows the measured divergence).
* Half-open exceptions: component ranges are closed (`{1..3}M`), UNTIL is inclusive (`tempo.ex:9402-9409`), `T0H/T0H` is a whole turn (`range.ex:710-715`), and with an explicit `:unit` coarser than the end, members can run past the end (`steps.ex:232-252`).
* `Enumerable.Tempo.Set` returns `{:halted, acc}` on exhaustion instead of `{:done, acc}` (`set.ex:18-25`).

**Calendar.** `UnitValues` is nearly the gateway; `steps.ex:361, 374, 718` bypass it with `plus/6` and `months_in_year/1`; `zone.ex` round-trips every zoned value through the Gregorian calendar with `Date.new` and `Date.convert` (`zone.ex:94-170`).

### 3.4 Set operations

**Flow.** Every public operation (`tempo.ex:14789-15163`) runs `align_members/3` (`operations.ex:102-126`): materialise a recurrence set against the window or the other operand; refuse durations and one-of sets; check one frame; classify anchored against unanchored; convert both to interval sets; place a time of day on each day of a window (`operations.ex:340-548`); convert the second operand to the first's calendar (`operations.ex:764-917`); rewrite a week axis to a month axis (`operations.ex:938-1023`); extend both to the finer resolution (`operations.ex:1060-1125`); rewrite `:day_of_week` to `:day`. Then one of six sweeps (section 2.2) over `Compare.compare_endpoints/2`, which chooses structural or UTC comparison on every call and caches nothing.

**Essential.** The instant-level and member-preserving distinction the guide draws (union keeps members; intersection, difference, complement and symmetric difference trim; `members_*` filter whole members), first-operand-wins for the result's calendar, zone and metadata, `:within` for a universe, the refusals (duration, one-of, floating against zoned, dated against undated without a window), and the cyclic case for spans with no year.

**Incidental.**

* The ten-step preflight exists because comparison is structural and results reuse operand values: the week-axis rewrite, the resolution extension and the `:day_of_week` rewrite would all go if ends were compared as positions and results reused the written ends by reference.
* Six sweeps and four further overlap tests where one coverage sweep with two member-level variants would do. `interval_set.ex:1391-1408` (`sweep_depth`) already is the coverage sweep.
* The cyclic and linear cases are forked inside each operation (`operations.ex:1283-1289, 212-221, 237-243`) instead of cutting operands at the cycle end once.
* No canonical form is maintained; laws hold only up to `Tempo.equal?/2`; `union(a, a)` doubles every member.
* First-operand-wins is broken by `complement/2` (the window's calendar and metadata win, `operations.ex:1530`) and by `symmetric_difference/2` when `a \ b` is empty (the result lands in b's calendar through `IntervalSet.new`'s first-member rule, `operations.ex:1747-1753`, `interval_set.ex:232-240`).
* A lazy operand raises instead of returning an error (`operations.ex:959`); a failed recurrence-set materialisation is discarded (`operations.ex:733`); backends are never kept by an operation although the docs say they are (`operations.ex:1192` and seven more); defensive code for `nil` ends that `new/2` already rejects; docs that still call members disjoint (`backend.ex:16, 77-79, 651`).

### 3.5 Selection and RRULE

**Flow.** A selection is `[selection: parts]` inside a value's `:time`; RFC 5545, cron, iCalendar and JSCalendar all lower to it through `Rule.to_selection/2` (`rule.ex:522-557`), the one good seam in this area. `Tempo.select/2` → `Select.do_select` (`select.ex:399-463`) → per period `select_in_period` → one of four engines: the resolver `Selection.apply/4` (`selection.ex:210-235`), a weekday fast path, integer indices, or a merge/projection path with its own axis model and value counting (`select.ex:2668-2901`). The resolver sorts parts by `@application_order` (`selection.ex:1740-1760`), fuses weekday and instance, splits at `:instance`, and reduces each part over the candidates by a role (`role/3`, 13 clauses, `apply_role/6`, 34 clauses, `selection.ex:1798-1904, 2170-2506`), then picks positions with `UnitValues.named/2`.

**Essential.** Enumerate a unit within a period, name values including from the end, weekday and week membership, positions, events, §12.10 windows, times of day, calendar-aware weekday numbering, zone gaps. The resolver already almost has the shape "group by period, enumerate, filter, index".

**Incidental.**

* Four engines where the guide promises one meaning; the merge path and the resolver agree on 1,296 of 1,347 measured cells (`plans/enumeration-and-selection.md:385`).
* About 1,000 lines of per-unit expanders that each hand-write their own enumeration of a period (`selection.ex:2884-4042`), and `goes_on_from` (`selection.ex:2008-2058`), a second encoding of every LIMIT predicate kept for speed.
* Five implementations of the weekday of a date, three of the nth weekday of a month, three of week-of-month (section 2.2).
* Two near-verbatim copies of the clock-skip handling (`select.ex:530-588`, `selection.ex:261-295`); five unit-order tables.
* RFC 5545 rules that are not selection: `origin_day` clamping, the Note 1/2 EXPAND→LIMIT downgrades, `byday_ordinal_scope`, `limits_after_the_days_made`, the `:within` role, DTSTART inheritance (`rule.ex:657-781`), SKIP, WKST, cron's `W` and `?`. These are real, but they belong in the RRULE adapter as rewrites, not in the engine.

**What resists a single engine**, and must be parameters of it: which period a selected unit belongs to (a week in a week-year, a week of a month that starts in the previous month, `select.ex:1009-1058`); the grain of the result (a month selection yields months, a weekday selection days, a time selection minutes); that an index counts in a period that may differ from the enumeration period (`BYDAY=2MO` in a yearly rule counts in each month, a position across all); and generators that move a date rather than filter it (SKIP, nearest weekday).

### 3.6 Comparison and Allen

**Flow.** `Compare.order/2` (`compare.ex:295`) takes a structural path when both values are whole, share a line, calendar, zone, offset and axis and have fields in day order (`compare.ex:645-758`), comparing component lists with missing units as minima, and otherwise projects each to UTC seconds (`compare.ex:1121`): a day number from the value's own calendar times 86,400, plus the clock, minus an offset resolved from the zone (gaps, folds, `compare.ex:1534-1637`). `Tempo.relation/2` reduces each operand to one span and makes four `order` calls into a 13-head table (`interval.ex:1645-1707`). The everyday predicates are defined on two engines: `before?`, `after?`, `adjacent?` and `Interval.within?/2` as relation sets; `Tempo.overlaps?/3`, `disjoint?/3`, `within?/3`, `contains?/3`, `equal?/3` as set algebra (`operations.ex:1804-1900`). The certainty layer (`interval.ex:3418-4441`, about 1,000 lines) computes the set of possible relations over the readings of a one-of set, a non-contiguous mask, a margin of error or an unanchored value and reads the verdict by containment, which is sound. Duration predicates step the duration from `from` on the calendar and compare with `to` (`interval.ex:3280`); `Duration.compare/3` instead converts to float seconds (`duration.ex:412, 631`).

**Essential.** One endpoint order, one relation table, one predicate table, the inverse and composition tables, the unanchored and floating refusals, calendar-aware day numbers, and the certainty verdict by containment over readings.

**Incidental.** Two ordering paths that must agree and that both query the calendar or the zone database on the way; the Allen table written five times; predicates on two engines with asymmetric signatures (`before?/2` takes no `:within`, `overlaps?/3` does); near-identical `point?`/`whole?` checks (`compare.ex:421-518`) and a third in `Interval.single_value?`; six functions that turn a non-point value into its start at different layers; two three-valued certainties; two duration semantics; `compare_time/2` returning `:eq` as a bailout (`compare.ex:155, 159`) while public; a silent Gregorian fallback for an invalid date in projection (`compare.ex:1503-1512`); the guide's claim that comparison projects to a single UTC frame being true only off the fast path.

### 3.7 Arithmetic

**Flow.** `Tempo.shift/3` (`tempo.ex:7656`) → `Math.add/2` (`math.ex:954-1066`): refuse the undefined cases; if the value is in a named zone, split the duration into calendar units applied to the wall clock and clock units applied on the time line (`math.ex:1161-1383`); otherwise `add_wall`, which tries a fast path for a plain date and a single integer unit (`math.ex:1393-1420`), else routes masks, sets and groups to expansion and re-gathering (`math.ex:1486-2790`, about 1,300 lines), else `add_crisp` (`math.ex:1962`): years and months first through `calendar.plus/6`, one clamp (`maybe_clamp`, `math.ex:3027`), then weeks, days, clock units, then microseconds as a carry. An interval is shifted end by end with its day length kept (`tempo.ex:7719-7832`). Beside this is a complete second arithmetic, `add_unit/3` and `subtract_unit/3` (`math.ex:91-880`), which steps one unit in the last place and is used for values with no year, masks and groups.

**Essential.** Calendar units then clamp then counted units (as `Date.shift/2` does); the zone split; the invariance rule for a value with no year; interval shifting that keeps the day length.

**Incidental.** The second arithmetic; three ways to add years and two to add months (section 2.2); week normalised in three places with two semantics (`math.ex:2820, 2031-2057`; `duration.ex:178` evaluated at compile time on the notation calendar); fast paths that re-enter the general path; four time-line projections; `shift_skipping` (380 lines) as a separate walk inside `math.ex`; the mask and set shifting that exists for ISO 8601-2 shapes and dwarfs the arithmetic.

**Durations.** `%Tempo.Duration{time: [...]}` with no type-level distinction between calendar and fixed units; the distinction is behavioural (`@fixed_unit_seconds` has no month or year, `duration.ex:170-180`).

### 3.8 The calendar surface

Measured at `3a85c80`: Tempo calls **41 calendar callbacks at 157 sites** (section 8.1 lists them), 33 of Calendrical's 51 and 8 of Elixir's 28, plus 17 calls on Calendrical's own modules (`Kday`, `Ecclesiastical`, `Lunisolar`, the CLDR registry), 18 calls of Erlang's `:calendar` for Gregorian seconds, and 56 indirect calls through `Date.new`, `Date.convert` and `Date.diff`. No `function_exported?` probe is left and only `lib/tempo/calendars.ex` names a calendar module. These are the plan `calendar-surface.md`'s achievements and they hold.

What remains against the principle that Tempo never introspects a calendar:

* **Identity checks**, 23 sites: `is_notation/1` at 18 (`zone.ex:61, 251, 542, 741`; `group.ex:144, 372, 1194`; `inspect.ex:482, 704`; `validation.ex:2324, 2823`; and eight more), `is_notation_weeks/1` at 4, `calendar in [Calendars.default(), implied]` at `inspect.ex:321`. `select.ex:2459` decides whether a calendar's weeks are ISO 8601's by which module it is; `group.ex` chooses the season algorithm by module.
* **Kind read from the shape of an answer**: `{:ambiguous, _}` from `months_in_year/0` means lunisolar (`math.ex:3242`); an integer `years_in_cycle/0` means arithmetic (`tempo.ex:10669, 10962`); `valid_date?(0, 1, 1)` means a year zero exists (`unit_values.ex:236`); a persistent-term probe works out the day a calendar's weeks start (`unit_values.ex:1821-1840`), which is the generated `first_day_of_week/0` that is not a callback.
* **The CLDR type as a discriminator**: `== :gregorian` (`format.ex:1063`); equality of two types (`rrule/rule.ex:381`).
* **Overlap in the surface itself.** Counts, number lists and period ranges answer the same question three ways (`days_in_month/2`, `day_numbers/2`, `month/2`); three week numberings (`iso_week_of_year/3`, `week_of_year/3`, `date_from_week_date/3`) with inconsistent return shapes (`weeks_in_year/1` a tuple, `weeks_in_week_year/1` an integer); `plus/6` and `diff/3` beside the day scale that makes both derivable.

### 3.9 Cross-cutting

* **`Tempo` is 17,778 lines** because the bodies of its functions were moved into it (the user's ruling that the body lives with the doc). The engine modules are hidden. The result is a module a reader cannot navigate and an engine a reader cannot find.
* **Limits** are set in at least five places (`Tempo.Limit`, `@spans_at_once`, `@occurrence_horizon`, `@recurrence_safety_cap`, `@candidates_at_once`, `@max_placement_pairs`).
* **The networks** (`Tempo.Network`, `Schedule`, `RelationNetwork`, `Qualitative`, 4,462 lines) depend one way on `Compare.to_utc_seconds`, `Compare.offset_seconds`, `Math.add` and `Tempo.to_date`, and nothing in the core depends on them.
* **The test corpus is the asset.** The operation matrix (`test/tempo/matrix_test.exs`, generated and checked against the code), the reference tests (`reference_test.exs`, answers worked out from `Date`, `NaiveDateTime` and a calendar's own functions), the calendar census (`calendar_census_test.exs`, 22 calendars, 579 full forms, 520 selections), the EDTF corpus and the RFC 5545 conformance tests are independent of the implementation and are the oracle for any rewrite.

## 4. The model: nine laws

The redesign begins by stating what the current code leaves implicit. Every module in section 5 is written to these laws and nothing else; a behaviour not derivable from them is not Tempo's. The ninth law, on written ends, is in section 4.2.

1. **Denotation.** An *expression* is a value (`2026-06`), an interval (`2026-06-01/2026-07-01`), a recurrence (`R5/2026-06-15/P1D`), an all-of set (`{2026-06,2026-08}`) or a one-of set (`[2026,2027]`). Every expression *denotes* an ordered sequence of half-open spans, `spans(E)`, possibly empty, possibly infinite. A duration denotes a length and is not an expression. Every operation on an expression is defined on `spans(E)`.

2. **Half-open.** A span is `[from, to)`: the first instant is in it, the last is not. Adjacent spans concatenate without gap or overlap. No span has zero extent.

3. **Resolution is meaning.** A value written to resolution *r* denotes the one span `[v, next_r(v))`, where `next_r` is one unit of *r* later. The written ends of a span are kept as written; nothing drills into them. A span written with two ends denotes exactly that extent.

4. **Frames.** A span lies on one frame: the **UTC line** (it has a year and a zone or a shift), the **floating line** (a year, no zone, no shift), or a **cycle** (no year: the day for a time of day, the week for a weekday, the year for a month and day). Two spans relate, compare or combine only on the same frame; otherwise the answer is a named error. `at/2`, `on/2` and `in_zone/2` move a value from one frame to another; the `:within` option places a cyclic expression on the line of an anchored one.

5. **One expression, one calendar, one zone.** The calendar and the zone are properties of the whole expression, written once after it (the user's rule of 2026-10-12). A time shift is a property of a written end. What cannot be written is an error, never another value.

6. **Enumeration.** `Enum` over an expression yields what it is made of. A *singular* expression (one span) yields its children: the units one level below the resolution of a value, or the finer of its ends' resolutions for an interval. A *plural* expression (a set, a value with a set-valued unit, a mask with several candidates, a selection, a recurrence, an interval set) yields its members, each an expression. `Tempo.members/1` gives the spans of either. This replaces today's two rules (section 9.2).

7. **One calendar question.** Tempo knows its own units (year, month, week, day, hour, minute, second, fraction), the labels a day can carry (day of the week, day of the year, week of the year, quarter, season, a traditional month), and the notations it reads and writes. It asks a calendar what span of days a period is, what date a day number is and what labels a date has, whether a date exists, and how to shift a date. It never asks what kind of calendar it is talking to, and holds no number a calendar would answer.

8. **Refusal.** What Tempo cannot answer by these laws is a named error that says why. It is never a guess, a fallback or a silently different value.

### 4.1 Consequences worth stating

* **Enumeration and selection are one operation.** `2026Y{1,3}M` and `2026Y6ML1K1IN` are both values whose units are constraints; expanding the constraints over the calendar is the one engine (section 7.4). A selector is a value with no year applied to each period of a base.

* **Set operations and relations are integer algebra.** Once the ends of spans are positions on a frame, every set operation is a coverage sweep over sorted boundaries (section 7.6) and every Allen relation is four comparisons (section 7.7). Calendars and zones are consulted only to compute positions, once per end.

* **The walk has one rule.** A span is walked at a unit by stepping on the scale that unit lives on: calendar units (year, month, week, day) on the day scale, through the calendar's period spans; clock units (hour, minute, second, fraction) on the tick scale, shown as wall readings through the zone. Daylight saving falls out: a day in Paris has 23 or 25 hours because its two ends are 23 or 25 hours apart, with nothing skipped or doubled by hand.

* **Materialising changes the form, and so the walk.** `to_interval(~o"2026-06-15")` is the interval `2026-06-15/2026-06-16`, which walks days (one of them), where the value walks hours. There is no `:unit` field to keep them in parity, because by law 3 they are different expressions with the same extent. A caller who wants an extent walked at a unit says so: `Tempo.walk(expression, :hour)`.

### 4.2 Written ends

The user raised this on 2026-10-13: `~o"2026Y{1,3}M"` is two months and `~o"2026Y{1..3}M"` three, but `~o"2026/2028"` has been two years, `[2026, 2027]`, where anyone reading it expects three. The two conventions have to be reconciled without giving up the half-open model.

**The reading.** A date names a period of the calendar: "2026 to 2028" and "1 to 3 June" include their last day, in speech, in EDTF (`1964/2008` is "beginning sometime in 1964 and ending sometime in 2008") and in ISO 8601-2 Annex A. A time of day names a reading of the clock, and a reading is a boundary: "nine to five" ends when the clock shows five, not a minute later. The convention differs because what is named differs, not because the model does. So:

9. **Written ends.** A written interval `a/b` runs from the start of `a`. It runs to the *end* of `b` when `b` is written to a calendar unit (a year, a month, a week, a date), and to the *start* of `b` when `b` is written to a clock unit (a time of day). The struct holds the half-open span that results, every operation is defined on it as before, and the writer writes a span back as it was read, so that text round-trips.

| Written | Denotes | Walks as |
|---|---|---|
| `2026/2028` | `[2026-01-01, 2029-01-01)` | 2026, 2027, 2028 |
| `2026-06-01/2026-06-03` | `[06-01, 06-04)` | three days |
| `2026-W25/2026-W27` | three weeks | W25, W26, W27 |
| `2026/2026-03` | January to March inclusive | Jan, Feb, Mar |
| `T09/T17` | `[09:00, 17:00)` | eight hours |
| `2026-06-15T10:30/2026-06-15T10:45` | fifteen minutes | |
| `2026-06-15/2026-06-15T17` | `[06-15T00:00, 06-15T17:00)` | seventeen hours |
| `2026-06-15T10/2026-06-16` | from 10:00 on the 15th through the 16th | thirty-eight hours |
| `P1M/2026-07` | the month ending when July ends: July | |
| `R3/2026-01-01/2026-01-08` | eight-day occurrences | |
| `{2026,2027}Y/2030Y` | each through 2030 | |

The rule is Tempo's own to apply: it decides by `Tempo.Unit.calendar?/1` against `clock?/1`, which is the classification every other module already uses, and asks nothing of a calendar. Ranges inside a unit (`{1..3}M`) were already inclusive; sets of values (`{2026,2027}Y`) list members; both stay as they are, and all three written forms now agree with how they are read aloud.

**What follows.**

* The reader moves a calendar-resolution end forward by one unit of its resolution to make the half-open bound (`2028` becomes `2029`, `2026-06-03` becomes `2026-06-04`), through `Tempo.Expand.children/3`'s successor; the writer moves it back. A clock-resolution end is kept as written. `to_iso8601/1` of what `from_iso8601/2` read is the original text.

* `Tempo.Interval.new/1` keeps `:to` as the half-open bound and `:through` as the included last period, as today. `Tempo.Interval.to/1` answers the half-open bound; a new `Tempo.Interval.through/1` answers the last period included, for an end written to a calendar unit. The two words are the two readings.

* A materialised month, `to_interval(~o"2026-06")`, is the span `{:span, 2026-06, 2026-07}` and is written `2026-06/2026-06`: June through June. It is correct under the rule and reads oddly at first; the alternative, a marker for an exclusive end, is not in ISO 8601, and the user's rule that what cannot be written is an error settles it. `inspect/1` shows a span whose two written ends are one period as that period: `~o"2026Y6M"` with a note that it is an interval.

* The migration guide lists the change under written ends. The golden files tag every cell whose input has a written calendar-resolution end (`written_end`), so the diff on this decision is one filter. In this repository about 1,425 written intervals change meaning (counted in `plans/interval-end-inclusive.md`); the guides are re-run as part of phase 7 and each is read for which reading it meant.

* Mixed resolutions follow the rule as written: `2026-06-15T10/2026-06-16` is thirty-eight hours, where today it is fourteen. The current guide uses this example; it will be rewritten as `2026-06-15T10/2026-06-16T00` for the fourteen hours.

## 5. The architecture

### 5.1 One struct

```elixir
defmodule Tempo do
  @enforce_keys [:form]
  defstruct form: nil,
            calendar: Calendar.ISO,
            zone: nil,
            shift: nil,
            qualifications: nil,
            metadata: %{}

  @type t :: %__MODULE__{
          form: form(),
          calendar: module(),
          zone: Tempo.Zone.t() | nil,
          shift: [hour: integer(), minute: integer(), second: integer()] | nil,
          qualifications: %{optional(unit()) => :uncertain | :approximate | :both} | nil,
          metadata: map()
        }

  @type form ::
          {:value, units()}
          | {:span, t() | Tempo.Duration.t() | :open, t() | Tempo.Duration.t() | :open}
          | {:every, t(), pos_integer() | :infinity | t(), selection() | nil}
          | {:all, [t()] | Enumerable.t()}
          | {:one, [t()]}
          | {:when, t(), [condition()]}
end
```

* **`{:value, units}`** is what today's `%Tempo{}` is: the units of a written value, coarsest first, each with what it holds (section 5.2). `shift` and `qualifications` belong to this form and are `nil` on every other.

* **`{:span, from, to}`** is today's `%Tempo.Interval{}` without `recurrence`, `repeat_rule`, `direction` or `unit`. An end is a value, a duration (one of the two, for `2026-06/P1M` and `P1M/2026-07`) or `:open`.

* **`{:every, span, bound, rule}`** is a recurrence: the span of the first occurrence (its `to` is the cadence when written as a duration), how many (a count, `:infinity`, or an `UNTIL` value), and the repeat rule applied in each period, if any. A domain (`R/{2020..2024}Y/P1Y/…`) is a span whose `from` holds a set, as any value may.

* **`{:all, members}`** is `{a,b}`, an interval set, a recurrence set and the result of every set operation. Members are expressions, each with its own metadata; a lazy set holds an `Enumerable` of them. A set operation's result is in canonical form: sorted by start, and for the instant-level operations coalesced.

* **`{:one, members}`** is `[a,b]`, an epistemic choice. It has no spans; it has readings, and only the certainty predicates and the writer read it.

* **`{:when, member, conditions}`** is a member with the substitution rules `Tempo.RecurrenceSet.keep_when/2` and `move_when/2` express, read by `spans/2` alone.

Nested expressions carry the calendar and zone of their parent, set by the constructors, so a function reading an end reads its own fields; the writer writes the suffix once. `Tempo.Interval.new/1` refuses two ends in two calendars or two zones, as today.

The one companion is unchanged in role:

```elixir
defmodule Tempo.Duration do
  defstruct units: []   # [year: 1, month: 2, day: 3, hour: 4, minute: 5, second: 6, microsecond: {0, 0}]
end
```

### 5.2 What a unit holds

```elixir
@type unit ::
        :year | :month | :week | :day | :hour | :minute | :second | :microsecond
        | :day_of_week | :day_of_year | :quarter | :season | :traditional_month
        | :selection

@type held ::
        integer()                               # 15
        | [integer() | Range.t()]                # {1,3}, {1..5}, {1..-1//2}; a negative counts from the end
        | {:mask, [0..9 | :x]}                   # 1X ; X* is {:mask, [:x]} with every digit free
        | {:group, held(), pos_integer()}        # 2G3MU: the second group of three
        | {integer(), [significant: n]}          # 1950S2
        | {integer(), [margin: n]}               # 2018±2
        | {integer(), :leap}                     # a traditional leap month
        | selection()                            # for :selection only

@type selection :: [
        {unit(), held()}                         # parts, in the order written: month: 11, day_of_week: 4
        | {:instance, [integer()]}               # I: positions, counted in the period
        | {:week_start, 1..7}                    # q
        | {:event, String.t()}                   # e
        | {:window, Tempo.Duration.t() | t()}    # §12.10
      ]
```

Quarters, halves, centuries and decades are groups of months or years as ISO 8601-2 defines them and are held as `{:group, …}` or as the unit `:quarter`; they are not encoded as month numbers. A unit holds exactly one of these shapes, and every module reads them through `Tempo.Unit`, which is the only module that knows the shapes.

### 5.3 Module map

Each module has one job, a line budget, and depends only on the layers below it.

| Layer | Module | Job | Budget |
|---|---|---|---|
| 0 | `Tempo.Calendar` | The calendar contract (section 8) and the one adapter that routes `Calendar.ISO` to the module that implements it. Every calendar call in the library goes through it. | 300 |
| 0 | `Tempo.Zone` | Reading the zone database: the offset at a UTC tick, the offsets a wall reading can have (one, none for a gap, two for a fold), the changes in a range. | 300 |
| 0 | `Tempo.Unit` | Tempo's own units: their order, which are calendar and which clock, the axis each lives on, the label units and their grain, the shapes a unit holds and how to read them. | 300 |
| 0 | `Tempo.Limit` | The one place every bound on work is set. | 50 |
| 1 | `Tempo.Scale` | Positions and frames: a value's start and end as ticks on the UTC or floating line, or as a tuple on its cycle; the frame of an expression; the comparison of two positions. | 400 |
| 2 | `Tempo.Expand` | The values a unit takes under a concrete prefix (children and labels), the cartesian expansion of a value's units, counts from the end, masks, groups, positions. | 600 |
| 2 | `Tempo.Walk` | Stepping a span at a unit, on the day scale or the tick scale, half-open, lazily. The closed forms for count and nth. | 300 |
| 2 | `Tempo.Validate` | One calendar-aware pass over a read or built expression: every unit in range, every date existing, no reading the clock skips, ends ordered, one calendar and one zone. | 500 |
| 3 | `Tempo.Spans` | `spans/2`: the denotation of any expression, including the occurrences of a recurrence and the readings of a `:when`. Needs a `:within` window where the sequence is infinite. | 500 |
| 3 | `Tempo.Select` | A selector applied to each period of a base: expand, filter, index. The home of `select/2` and of what RRULE and cron lower to. | 400 |
| 3 | `Tempo.Algebra` | The coverage sweep and the eight set operations on spans; canonical form. | 300 |
| 3 | `Tempo.Allen` | The thirteen relations from four comparisons; inverse; composition; the predicate sets; the certainty verdict over readings. | 400 |
| 3 | `Tempo.Shift` | Shifting a value, span or set by a duration; truncating, rounding, extending. | 500 |
| 4 | `Tempo.Reader` | ISO 8601-1, ISO 8601-2 and RFC 9557 text to an expression, one function per production of the written grammar. | 2,000 |
| 4 | `Tempo.Writer` | An expression to ISO 8601 text, the inverse of the reader. | 400 |
| 4 | `Tempo.Format`, `Tempo.Explain`, `Tempo.Sigils`, `Inspect` | As today, rewritten over the one struct. | 2,500 |
| 5 | `Tempo` | The public API: documentation and a short body per function that validates its arguments, calls one core function and shapes the answer. | 3,000 |
| 5 | `Tempo.Interval`, `Tempo.IntervalSet`, `Tempo.RecurrenceSet`, `Tempo.Duration` | Constructors and accessors of the forms, with the functions the guides name. | 800 |
| 5 | `Tempo.RRule`, `Tempo.Cron`, `Tempo.ICal`, `Tempo.JSCalendar` | Adapters to and from the recurrence form and the selection shape; RFC 5545's own rules (DTSTART inheritance, SKIP, the EXPAND/LIMIT downgrades) live here as rewrites. | 2,000 |
| 5 | `Tempo.Event`, `Tempo.Workdays`, `Tempo.Territory`, `Tempo.Clock`, `Tempo.LeapSeconds` | As today, smaller. | 800 |
| off | `tempo_network` (companion package) | `Tempo.Network`, `Tempo.Schedule`, `Tempo.Interval.RelationNetwork`, `Tempo.Network.Qualitative`, depending on `Tempo.Scale`, `Tempo.Allen` and `Tempo.Shift`. | 4,500, moved |

The core (layers 0 to 3) is about 4,500 lines; with the reader, writer, text and the public module, 13,000 to 15,000; against 82,875 today. The budgets are targets that a review should hold the code to, not estimates to be grown into.

### 5.4 The border

A caller's values are in `Calendar.ISO`, Elixir's own, and so are Tempo's: nothing is rewritten on the way in or out. Every calendar question is a function of `Tempo.Calendar` that takes the calendar module as its first argument and resolves the module that answers for it:

```elixir
defmodule Tempo.Calendar do
  # The one line in the library that names a calendar's implementation.
  @implementations %{Calendar.ISO => Localize.Calendar.ISO}

  defp impl(calendar), do: Map.get(@implementations, calendar, calendar)

  def month(calendar, year, month), do: impl(calendar).month(year, month)
  # …
end
```

This is the whole of today's `Tempo.Calendars`, `inside/1`, `outside/1`, `outside?/1`, `is_outside/1`, `Calendars.inspect/2`, the engine proxies in `test/support` and the 393 border sites. A value's `calendar` field is what the caller gave; an error message inspects the term it was given. Which module answers for `Calendar.ISO` is configuration (`config :ex_tempo, :calendar_implementations`), so a consumer without Localize can supply another, and Calendrical can become the optional dependency the plans want with no conditional code in Tempo.

### 5.5 The budgets restated (2026-10-15, decision 60)

The budgets of 5.3 were estimates made before the code; the review of 2026-10-15 found the core at about 2.6 times its budget. After `Tempo.Spans` was split along its sections (decision 58) and a reading the clock shows twice given one home in `Tempo.Zone` (decision 59), each module's budget is restated as its measured size rounded up to the next fifty lines. A review holds the code to these: a module that grows past its budget says why in the decision that grows it. Lines are all lines; code is lines that are neither documentation, comment nor blank.

| Layer | Module | First budget | Lines | Code | Budget | Why it exceeds its first budget |
|---|---|---:|---:|---:|---:|---|
| 0 | `Tempo.Calendar` (with `WeeksFrom`) | 300 | 534 | 338 | 550 | Calendars of weeks of other week starts, and every question answered or refused by name. |
| 0 | `Tempo.Zone` (with `Table` and `Transitions`) | 300 | 870 | 477 | 900 | Gaps, folds and a written shift beside a zone; the readings shown twice (decision 59); the table of a zone's changes, listed by the database or sampled, and the one question asked beside `Calendar.TimeZoneDatabase` (decision 73), which replaced the sampling of decision 61. |
| 0 | `Tempo.Unit` | 300 | 354 | 216 | 400 | The ordering and one-axis checks of building from parts, and the rank of a unit. |
| 0 | `Tempo.Limit` | 50 | 50 | 17 | 50 | Within. |
| 1 | `Tempo.Scale` | 400 | 355 | 226 | 400 | Within. |
| 2 | `Tempo.Expand` | 600 | 1,045 | 714 | 1,050 | Masks, groups, counts from the end, labels, days a zone leaves out, readings found by arithmetic and the extents they carry (decision 56). |
| 2 | `Tempo.Walk` | 300 | 243 | 163 | 250 | Within. |
| 2 | `Tempo.Validate` | 500 | 446 | 322 | 450 | Within. |
| 3 | `Tempo.Spans` (with `Placed`) | 500 | 1,413 | 915 | 1,450 | Written spans with duration and open ends, plural ends, placing in a window, the merging of a set's members, the conditions' widened window; every span made with its place (decision 74). |
| 3 | `Tempo.Recurrence` | (in `Spans`) | 851 | 568 | 900 | The rule walk: periods by number, looking ahead past quiet periods (decision 37), domains of years, counts and untils. |
| 3 | `Tempo.Exclusions` | (in `Spans`) | 148 | 100 | 150 | New, from `Spans`. |
| 3 | `Tempo.Children` | (in `Spans`) | 363 | 258 | 400 | New, from `Spans`: law 6 and the readings of certainty. |
| 3 | `Tempo.Select` | 400 | 1,045 | 700 | 1,050 | Rolls, skips, events, nested selections and sets of them, windows, readings shown twice, a day tested whole. |
| 3 | `Tempo.Algebra` | 300 | 938 | 616 | 950 | Results ended where their members end (decision 42), operands with no end streamed, frames brought to agree. |
| 3 | `Tempo.Allen` (with `Classifier`) | 400 | 409 | 185 | 450 | Within its code. |
| 3 | `Tempo.Shift` | 500 | 1,031 | 743 | 1,050 | Truncating, rounding and extending across axes, seasons, a value with no year shifted where the answer is one. |
| 3 | The core modules the map did not name: `Build` 680, `Parts` 222, `Measure` 274, `Interop` 265, `Season` 182, `Conditions` 158, `Occurrences` 126, `Skip` 123, `Text` 113, `Options` 51 | — | 2,194 | 1,515 | each its size, rounded up | Building from parts (decisions 45 to 51), the parts and lengths of a value, Elixir's types, seasons, conditional holidays, iCalendar events, RFC 7529's skip, text in a locale, the options check. |
| 4 | `Tempo.Reader` | 2,000 | 2,101 | 1,489 | 2,150 | The grammar of ISO 8601-1, ISO 8601-2 and RFC 9557 whole. |
| 4 | `Tempo.Writer` | 400 | 494 | 341 | 500 | Every form written back, including what the builder makes. |
| 4 | `Format`, `Explain`, `Sigils`, the protocols | 2,500 | 900 | 582 | 900 | Within. |
| 5 | `Tempo` | 3,000 | 4,721 | 1,216 | 4,750 | Its documentation: every function's Arguments, Options, Returns and Examples. Its code is 1,216. |
| 5 | `Interval`, `IntervalSet`, `RecurrenceSet`, `Duration` | 800 | 1,872 | 580 | 1,900 | Their documentation; their code is within. |
| 5 | `RRule`, `Cron`, `ICal`, `JSCalendar` | 2,000 | 2,371 | 1,399 | 2,400 | The RRULE writer, iCalendar availability, cron's extensions. |
| 5 | `Event`, `Workdays`, `Territory`, `Clock` (with `Test`), `LeapSeconds` | 800 | 1,170 | 534 | 1,200 | Event resolvers, workday conventions, the test clock (decision 55). |
| 5 | `Tempo.Builder` | — | 1,034 | 325 | 1,050 | New (decisions 45 to 51): its documentation. |
| 5 | Exceptions | — | 422 | 252 | 450 | One named error for each refusal (law 8). |
| | **The library** | **about 15,000** | **26,862** | **14,524** | | The core (layers 0 to 3) is 11,777 lines and 7,806 of code, against about 4,500. |

The 2.0 it replaced was 82,875 lines and 46,326 of code.

## 6. Reference implementation, part one: the scale, the calendar and expansion

The code in sections 6 and 7 is the design written as Elixir: complete in its algorithms, abbreviated in its error shaping and docs. Where a block was executed as a prototype the section says so and gives the result. Names follow the glossary; `options` is always `options`.

### 6.1 `Tempo.Unit`: what Tempo knows about its own units

```elixir
defmodule Tempo.Unit do
  @moduledoc false
  # The one module that knows Tempo's units, their order, their axes and the shapes a unit holds.

  @calendar_units [:year, :month, :week, :day]
  @clock_units [:hour, :minute, :second, :microsecond]
  @label_units [:day_of_week, :day_of_year, :quarter, :season, :traditional_month]

  # Coarsest first. A label sorts where the unit it labels does.
  @order [:year, :quarter, :season, :month, :traditional_month, :week, :day, :day_of_year,
          :day_of_week, :hour, :minute, :second, :microsecond]

  # The unit a value's children are in, under the unit a value is written to.
  @child %{year: :month, month: :day, week: :day, day: :hour, hour: :minute, minute: :second,
           second: :microsecond}

  # A label is a property of a day (or of a month), read from a date; its grain is the unit that is enumerated to find it.
  @grain %{day_of_week: :day, day_of_year: :day, quarter: :month, season: :month, traditional_month: :month}

  @microseconds %{microsecond: 1, second: 1_000_000, minute: 60_000_000, hour: 3_600_000_000}

  def calendar?(unit), do: unit in @calendar_units
  def clock?(unit), do: unit in @clock_units
  def label?(unit), do: unit in @label_units
  def child(unit), do: Map.fetch!(@child, unit)
  def grain(unit), do: Map.get(@grain, unit, unit)
  def microseconds(unit), do: Map.fetch!(@microseconds, unit)
  def compare(a, b), do: Enum.find_index(@order, &(&1 == a)) |> Kernel.-(Enum.find_index(@order, &(&1 == b)))

  def resolution(units), do: units |> Keyword.keys() |> Enum.reject(&(&1 == :selection)) |> List.last()
  def anchored?(units), do: Keyword.has_key?(units, :year)
  def coarsest(units), do: units |> hd() |> elem(0)

  # Whether a held shape names one value, several, or depends on its context.
  def singular?(held) when is_integer(held), do: true
  def singular?({n, _annotation}) when is_integer(n), do: true
  def singular?(_), do: false
end
```

### 6.2 `Tempo.Calendar`: the contract and the adapter

The functions below are every calendar question the library asks. Section 8 gives the callbacks they map to and the laws a calendar must satisfy.

```elixir
defmodule Tempo.Calendar do
  @moduledoc false
  @implementations Application.compile_env(:ex_tempo, :calendar_implementations,
                     %{Calendar.ISO => Localize.Calendar.ISO})

  @type span :: {first_day :: integer(), after_last_day :: integer()}   # half-open, in ISO days

  defp impl(calendar), do: Map.get(@implementations, calendar, calendar)

  # The day scale
  def iso_days(c, y, m, d), do: impl(c).date_to_iso_days(y, m, d)
  def date(c, days), do: impl(c).date_from_iso_days(days) |> as_tuple()
  def valid_date?(c, y, m, d), do: impl(c).valid_date?(y, m, d)

  # Periods as spans of days. {:error, _} when the period does not exist.
  def period(c, :year, [year: y]), do: span(impl(c).year(y))
  def period(c, :month, [year: y, month: m]), do: span(impl(c).month(y, m))
  def period(c, :week, [year: y, week: w]), do: span(impl(c).week(y, w))
  def period(c, :quarter, [year: y, quarter: q]), do: span(impl(c).quarter(y, q))
  def weeks_of_month(c, y, m), do: impl(c).weeks_of_month(y, m) |> Enum.map(&span/1)

  # Labels of a date
  def day_of_week(c, y, m, d), do: impl(c).day_of_week(y, m, d, :monday) |> elem(0)
  def week_of_year(c, y, m, d), do: impl(c).week_of_year(y, m, d)
  def traditional_month(c, y, m), do: impl(c).traditional_month(y, m)
  def month_from_traditional(c, y, named), do: impl(c).month_from_traditional(y, named)

  # Arithmetic the calendar owns
  def shift_date(c, y, m, d, %Duration{} = by), do: impl(c).shift_date(y, m, d, by)

  # Bounds with no year, for a value on a cycle
  def months_in_year(c), do: impl(c).months_in_year()         # {fewest, most}
  def days_in_month(c, m), do: impl(c).days_in_month(m)      # {fewest, most}

  # Naming
  def type(c), do: impl(c).cldr_calendar_type()
  def from_type(type), do: Calendrical.calendar_from_cldr_calendar_type(type)

  # Derived here, never asked: the span of a day of the year, a week date, a day of the week.
  def first_day(c, units) do
    case units do
      [year: y, day_of_year: n] -> with {:ok, {lo, _}} <- period(c, :year, year: y), do: {:ok, lo + n - 1}
      [year: y, week: w, day_of_week: k] -> with {:ok, {lo, _}} <- period(c, :week, year: y, week: w),
                                                 do: {:ok, lo + Integer.mod(k - day_of_week_of(c, lo), 7)}
      [year: y, month: m, day: d] -> if valid_date?(c, y, m, d), do: {:ok, iso_days(c, y, m, d)}, else: {:error, :no_date}
      [year: y, month: m] -> with {:ok, {lo, _}} <- period(c, :month, year: y, month: m), do: {:ok, lo}
      [year: y] -> with {:ok, {lo, _}} <- period(c, :year, year: y), do: {:ok, lo}
    end
  end

  defp span(%Date.Range{first: f, last: l}), do: {:ok, {iso_days(f.calendar, f.year, f.month, f.day), iso_days(l.calendar, l.year, l.month, l.day) + 1}}
  defp span({:error, _} = error), do: error
end
```

### 6.3 `Tempo.Scale`: positions and frames

```elixir
defmodule Tempo.Scale do
  @moduledoc false
  @day 86_400_000_000

  @type frame :: :utc | :floating | {:cycle, Tempo.Unit.t()}
  @type position :: integer() | tuple()

  def frame(%Tempo{form: {:value, units}} = value) do
    cond do
      not Tempo.Unit.anchored?(units) -> {:cycle, Tempo.Unit.coarsest(units)}
      value.zone != nil or value.shift != nil -> :utc
      true -> :floating
    end
  end
  def frame(%Tempo{form: {:span, from, to}}), do: frame(from || to)   # the constructor made them one
  def frame(%Tempo{form: {:all, [first | _]}}), do: frame(first)

  # The half-open extent of a concrete value: {start, end} on its frame.
  def extent(%Tempo{form: {:value, units}} = value) do
    case frame(value) do
      {:cycle, _} -> {cycle_position(units, value.calendar), cycle_end(units, value.calendar)}
      frame -> {tick(value, units, frame), tick_after(value, units, frame)}
    end
  end

  # A value's start as a tick: its first day on the day scale, then its clock.
  defp tick(value, units, frame) do
    {:ok, day} = Tempo.Calendar.first_day(value.calendar, date_units(units))
    wall = day * @day + clock_microseconds(units)
    if frame == :utc, do: wall - Tempo.Zone.offset_at_wall(value.zone, value.shift, wall), else: wall
  end

  # The end is one unit later at the value's resolution: for a calendar unit the day after the period's last,
  # for a clock unit one unit of ticks. Each is read on the clock of its own moment, so a day across a change of
  # the clock is 23 or 25 hours long with nothing done by hand.
  defp tick_after(value, units, frame) do
    unit = Tempo.Unit.resolution(units)
    wall =
      if Tempo.Unit.calendar?(unit) or Tempo.Unit.label?(unit) do
        {:ok, {_, after_last}} = period_of(value.calendar, units)
        after_last * @day
      else
        {:ok, day} = Tempo.Calendar.first_day(value.calendar, date_units(units))
        day * @day + clock_microseconds(units) + Tempo.Unit.microseconds(unit)
      end
    if frame == :utc, do: wall - Tempo.Zone.offset_at_wall(value.zone, value.shift, wall), else: wall
  end

  # On a cycle a position is the tuple of the units from the cycle's unit down, missing ones as their minimum:
  # a time of day is {hour, minute, second, microsecond}; a month and day is {month, day, 0, 0, 0, 0}.
  # Tuples of integers order as Erlang orders them, which is the order of the cycle.
  defp cycle_position(units, _calendar), do: units |> fill_minima() |> Keyword.values() |> List.to_tuple()

  def compare(a, b) when a < b, do: :lt
  def compare(a, b) when a > b, do: :gt
  def compare(_, _), do: :eq
end
```

Two consequences. Calendar and zone are consulted once per end to compute a position and never during a comparison, so sorting ten thousand spans asks the calendar twenty thousand times, not two hundred thousand. And because a result's end is always some operand's end, `Tempo.Algebra` carries the written end beside each position and never has to re-derive a value from a position.

### 6.4 `Tempo.Zone`: one place that reads the zone database

```elixir
defmodule Tempo.Zone do
  @moduledoc false
  defstruct [:name, :offset, critical: false]   # a name, or a fixed offset in minutes ([+05:30]); never both

  # The offsets, in microseconds, a wall reading can have in a zone: one; none when the clock skips it; two when it shows it twice.
  def offsets_at_wall(%__MODULE__{name: name}, wall_tick) :: [integer()]
  # The offset at a UTC tick.
  def offset_at_utc(%__MODULE__{name: name}, utc_tick) :: integer()
  # The offset a value takes: its shift when written, else the one offset, else the first of two.
  def offset_at_wall(zone, shift, wall_tick)
  # Every change of the clock in a range of UTC ticks, for the clock walk and for `Tempo.extend/2`.
  def changes(zone, from_utc, to_utc) :: [{utc_tick, before, after}]
end
```

A reading the clock skips is refused by `Tempo.Validate` when a value is built, and never reaches the scale; a reading the clock shows twice is the first unless a shift says otherwise, and a walk yields both with their offsets (section 6.6).

### 6.5 `Tempo.Expand`: the values a unit takes

This is the engine for every set-valued unit, every mask, every group, every count from the end, every selection part and every RRULE `BY*` part. It was prototyped against eleven Calendrical calendars (section 8.2) in the form of `children/3` below.

```elixir
defmodule Tempo.Expand do
  @moduledoc false
  alias Tempo.{Calendar, Unit}

  @type prefix :: [{Unit.t(), integer()}]          # concrete, coarsest first
  @type child :: {value :: integer(), Calendar.span() | nil}

  # The values `unit` takes under a concrete prefix, each with its span of days (nil for a clock unit), in order.
  # A calendar unit's children are found by walking the prefix's span on the day scale, period by period:
  # the month that holds a day, then the day after that month's last, until the prefix's span is used up.
  @spec children(prefix(), Unit.t(), module()) :: {:ok, [child()]} | {:error, Exception.t()}
  def children(prefix, :month, calendar) do
    with {:ok, {lo, hi}} <- Calendar.period(calendar, :year, year: prefix[:year]) do
      {:ok, periods(lo, hi, fn day ->
        {y, m, _} = Calendar.date(calendar, day)
        {:ok, span} = Calendar.period(calendar, :month, year: y, month: m)
        {m, span}
      end)}
    end
  end

  def children(prefix, :week, calendar) do
    with {:ok, {lo, hi}} <- Calendar.period(calendar, :year, year: prefix[:year]) do
      {:ok, periods(lo, hi, fn day ->
        {y, m, d} = Calendar.date(calendar, day)
        {wy, w} = Calendar.week_of_year(calendar, y, m, d)
        {:ok, span} = Calendar.period(calendar, :week, year: wy, week: w)
        {w, span}
      end)}
    end
  end

  def children(prefix, :day, calendar) do
    with {:ok, {lo, hi}} <- period_of(calendar, prefix) do
      {:ok, for day <- lo..(hi - 1)//1, do: {Calendar.date(calendar, day) |> elem(2), {day, day + 1}}}
    end
  end

  # Clock units are Tempo's own.
  def children(_prefix, :hour, _), do: {:ok, for(h <- 0..23, do: {h, nil})}
  def children(_prefix, :minute, _), do: {:ok, for(m <- 0..59, do: {m, nil})}
  def children(_prefix, :second, _), do: {:ok, for(s <- 0..59, do: {s, nil})}

  # A label is read from each day (or month) of the prefix's span: a Monday of June is a day of June whose weekday is 1.
  def labelled(prefix, :day_of_week, calendar) do
    with {:ok, {lo, hi}} <- period_of(calendar, prefix) do
      {:ok, for day <- lo..(hi - 1)//1 do
        {y, m, d} = Calendar.date(calendar, day)
        {Calendar.day_of_week(calendar, y, m, d), {day, day + 1}}
      end}
    end
  end

  def labelled(prefix, :day_of_year, calendar) do
    with {:ok, {lo, hi}} <- period_of(calendar, prefix) do
      {:ok, for day <- lo..(hi - 1)//1, do: {day - lo + 1, {day, day + 1}}}
    end
  end

  # The cartesian expansion of a value's units: a lazy stream of concrete values, coarsest first,
  # each the prefix it was built from. A value the calendar has no room for drops out (RFC 5545's rule).
  @spec expand([{Unit.t(), Tempo.held()}], module()) :: Enumerable.t()
  def expand(units, calendar) do
    Enum.reduce(units, [[]], fn {unit, held}, prefixes ->
      Stream.flat_map(prefixes, fn prefix ->
        case candidates(prefix, unit, calendar) do
          {:ok, children} -> for {value, _span} <- select(held, children), do: prefix ++ [{unit, value}]
          {:error, _} -> []
        end
      end)
    end)
  end

  defp candidates(prefix, unit, calendar) do
    if Unit.label?(unit), do: labelled(prefix, unit, calendar), else: children(prefix, unit, calendar)
  end

  # What a held shape keeps of the children, in the order written.
  defp select(n, children) when is_integer(n) and n > 0, do: Enum.filter(children, &match?({^n, _}, &1))
  defp select(n, children) when is_integer(n) and n < 0, do: children |> Enum.reverse() |> Enum.drop(-n - 1) |> Enum.take(1)
  defp select(list, children) when is_list(list), do: Enum.flat_map(list, &select(&1, children))
  defp select(%Range{} = r, children), do: children |> values_named(r) |> Enum.map(&find(children, &1))
  defp select({:mask, digits}, children), do: Enum.filter(children, fn {v, _} -> digits_match?(v, digits) end)
  defp select({:group, nth, size}, children), do: children |> Enum.chunk_every(size) |> select(nth) |> List.flatten()
  defp select({n, _annotation}, children), do: select(n, children)

  # Walking a span period by period: `step` gives the item for the period holding `day` and the period's span.
  defp periods(lo, hi, _step) when lo >= hi, do: []
  defp periods(lo, hi, step) do
    {item, {_, next}} = step.(lo)
    [item | periods(next, hi, step)]
  end

  # The span of a concrete prefix: of its finest calendar unit's period, or of its day.
  defp period_of(calendar, prefix) do
    case Unit.resolution(prefix) do
      :year -> Calendar.period(calendar, :year, Keyword.take(prefix, [:year]))
      :month -> Calendar.period(calendar, :month, Keyword.take(prefix, [:year, :month]))
      :week -> Calendar.period(calendar, :week, Keyword.take(prefix, [:year, :week]))
      _ -> with {:ok, day} <- Calendar.first_day(calendar, date_units(prefix)), do: {:ok, {day, day + 1}}
    end
  end
end
```

What this replaces: the component DFS and its per-candidate re-validation (`enumeration.ex`), `Mask.candidates`, `Group.bound_groups` and `groups_of_set`, `UnitValues.in_period/3`, `named/2`, `first/3`, `last/3`, `following/4`, `preceding/4`, the per-unit expanders of `rrule/selection.ex:2884-4042`, the five weekday functions, and `month_numbers/1`, `day_numbers/2`, `days_in_month/2`, `days_in_year/1`, `date_from_day_of_year/2` and `day_of_year/3` as calendar questions. A reform calendar's missing days, a lunisolar leap month, a year that begins in March and a week calendar's 35-day month need no special case: the day scale has every day, and the calendar labels each.

Two properties the design relies on and section 8.3 asks Calendrical to guarantee: the periods of a unit tile their parent exactly (the months of a year cover its days with no gap or overlap), and a period's labels are lexicographically ordered within it.

### 6.6 `Tempo.Walk`: stepping a span at a unit

```elixir
defmodule Tempo.Walk do
  @moduledoc false
  @day 86_400_000_000

  # The children of a span at a unit, lazily, half-open. A calendar unit steps on the day scale through the
  # calendar's periods; a clock unit steps on the tick scale and is shown as a wall reading of the zone.
  def walk(%Tempo{} = span, unit) do
    {lo, hi} = Tempo.Scale.extent(span)
    cond do
      Tempo.Unit.calendar?(unit) -> calendar_steps(span, unit, div(lo, @day), div(hi + @day - 1, @day))
      Tempo.Unit.clock?(unit) -> clock_steps(span, unit, lo, hi)
    end
  end

  defp calendar_steps(span, :day, lo, hi), do: Stream.map(lo..(hi - 1)//1, &value_of_day(span, &1))
  defp calendar_steps(span, unit, lo, hi) do
    Stream.unfold(lo, fn
      day when day < hi ->
        {prefix, {_, next}} = period_holding(span.calendar, unit, day)
        {value(span, prefix), next}
      _ -> nil
    end)
  end

  # Each step is a tick; the wall reading it is shown as carries the offset it had, so an hour shown twice is two
  # values that differ in their offset, and an hour the clock skips is never reached.
  defp clock_steps(span, unit, lo, hi) do
    step = Tempo.Unit.microseconds(unit)
    lo |> Stream.iterate(&(&1 + step)) |> Stream.take_while(&(&1 < hi)) |> Stream.map(&wall_value(span, &1, unit))
  end

  # Closed forms, for Enum.count/1, Enum.at/2 and Enum.member?/2.
  def count(span, unit) do
    {lo, hi} = Tempo.Scale.extent(span)
    if Tempo.Unit.clock?(unit), do: div(hi - lo, Tempo.Unit.microseconds(unit)), else: span |> walk(unit) |> Enum.count()
  end
end
```

Because a span's two ends are already UTC ticks, `Enum.count(~o"2026-03-29[Europe/Paris]")` is 23 and `Enum.count(~o"2026-10-25[Europe/Paris]")` is 25 with no gap list, no fold list and no third classifier. A day of a calendar is one day; a month of a reform calendar is the days it has.

## 7. Reference implementation, part two: meaning, algebra, relations, arithmetic, selection, reading

### 7.1 `Tempo.Spans`: the meaning of any expression

Every other core module reads an expression only through this one.

```elixir
defmodule Tempo.Spans do
  @moduledoc false
  alias Tempo.{Expand, Scale, Select, Shift, Walk}

  # A lazy, ordered stream of concrete spans, each a `%Tempo{form: {:span, from, to}}` whose ends are concrete
  # values and which carries its source's metadata. `:within` bounds a sequence that has no end of its own.
  @spec spans(Tempo.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, Exception.t()}

  # A concrete value is its own one span.
  def spans(%Tempo{form: {:value, units}} = value, _options) when concrete?(units), do: {:ok, [as_span(value)]}

  # A value with a selection is the selection applied to the period the units before it name.
  def spans(%Tempo{form: {:value, units}} = value, options) when has_selection?(units) do
    {prefix, selection} = split_selection(units)
    Select.in_period(as_span(%{value | form: {:value, prefix}}), selection, options)
  end

  # A value with a set, a mask or a group in a unit is each value its units allow, in order.
  def spans(%Tempo{form: {:value, units}} = value, _options) do
    {:ok, units |> Expand.expand(value.calendar) |> Stream.map(&as_span(%{value | form: {:value, &1}}))}
  end

  # An interval is one span once a duration end is resolved and an open end is placed by the window.
  def spans(%Tempo{form: {:span, from, to}} = span, options) do
    with {:ok, from, to} <- ends(from, to, span, options), do: {:ok, [%{span | form: {:span, from, to}}]}
  end

  # A recurrence is its first span moved by n cadences for each n, scaled rather than accumulated so that a
  # month cadence from 31 January is right on every occurrence, each period given to its rule if it has one.
  def spans(%Tempo{form: {:every, first, bound, rule}} = recurrence, options) do
    with {:ok, limit} <- occurrences_limit(bound, recurrence, options) do
      occurrences =
        0
        |> Stream.iterate(&(&1 + 1))
        |> Stream.map(fn n -> Shift.by_cadences(first, n) end)
        |> Stream.take_while(&before_bound?(&1, bound, options))
        |> Stream.take(limit)
        |> Stream.flat_map(fn period -> if rule, do: Select.in_period!(period, rule, options), else: [period] end)
      {:ok, within(occurrences, options)}
    end
  end

  # A set is its members' spans in order; a lazy set is read as far as it is asked.
  def spans(%Tempo{form: {:all, members}}, options) do
    {:ok, Stream.flat_map(members, fn member -> spans!(member, options) end) |> ordered()}
  end

  # One of several values names no span to walk; it has readings, which `Tempo.Allen` reads.
  def spans(%Tempo{form: {:one, _}} = value, _options), do: {:error, Tempo.ConversionError.exception(value: value, reason: :one_of)}

  # A member with conditions is its spans, each kept, moved or added to as the conditions say.
  def spans(%Tempo{form: {:when, member, conditions}}, options) do
    with {:ok, occurrences} <- spans(member, options), do: {:ok, Stream.flat_map(occurrences, &apply_conditions(&1, conditions))}
  end

  # The one span of a concrete value, by law 3: [v, next(v)).
  defp as_span(%Tempo{form: {:value, _}} = value) do
    {from, to} = Scale.extent(value)
    %{value | form: {:span, written_start(value), written_end(value, to)}} |> with_positions(from, to)
  end
end
```

Three details worth fixing in writing:

* **A window bounds, it does not cut.** `:within` says how far an unbounded sequence is read and places a cyclic expression on each day of the window; the spans themselves are whole, as the set-operations guide says today.

* **Occurrences are scaled.** The nth occurrence is the first shifted by n cadences in one `Shift.by_cadences/2` call, never the previous plus one, so `R12/2026-01-31/P1M` lands on the last day of every month and the recurrence quadratic that `plans/design-notes.md` records cannot return.

* **Positions ride with the span.** `as_span/1` computes the two positions once and stores them in the span's private metadata, so `Algebra` and `Allen` never recompute them.

### 7.2 `Tempo.Algebra`: one sweep

Prototyped and verified: 3,000 random pairs of sets of one to four spans, five operations each, against a brute-force point-set model, zero failures; every result in canonical form (sorted, disjoint, no two members meeting).

```elixir
defmodule Tempo.Algebra do
  @moduledoc false

  # A member on the scale: its two positions, the written span it came from, and which operand it is of.
  @type edge :: {position :: term(), :open | :close, side :: :a | :b, member :: Tempo.t()}

  # Every instant-level operation is the one sweep with a different `keep?`: given how many members of a and of b
  # cover a point, is the point in the result? A result begins where keep? turns true and ends where it turns false;
  # a result's ends are therefore always ends of operands, and are written as those operands wrote them.
  def union(a, b), do: sweep(a, b, fn da, db -> da > 0 or db > 0 end)
  def intersection(a, b), do: sweep(a, b, fn da, db -> da > 0 and db > 0 end)
  def difference(a, b), do: sweep(a, b, fn da, db -> da > 0 and db == 0 end)
  def symmetric_difference(a, b), do: sweep(a, b, fn da, db -> (da > 0) != (db > 0) end)
  def complement(a, window), do: difference(window, a)

  # The member-preserving companions are the same sweep asked a different question of each member of a:
  # is any point of it covered by b?
  def members_overlapping(a, b), do: Enum.filter(a, fn m -> intersection([m], b) != [] end)
  def members_outside(a, b), do: Enum.filter(a, fn m -> intersection([m], b) == [] end)
  def members_in_exactly_one(a, b), do: members_outside(a, b) ++ members_outside(b, a)

  defp sweep(a, b, keep?) do
    (edges(a, :a) ++ edges(b, :b))
    |> Enum.sort_by(fn {p, kind, _, _} -> {p, if(kind == :close, do: 0, else: 1)} end)   # at one position, closes before opens
    |> Enum.reduce({[], 0, 0, nil}, fn {p, kind, side, member}, {out, da, db, open} ->
      {da, db} = step({kind, side}, da, db)
      was = open != nil
      now = keep?.(da, db)
      cond do
        not was and now -> {out, da, db, {p, member}}
        was and not now -> {[span_between(open, {p, member}) | out], da, db, nil}
        true -> {out, da, db, open}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp step({:open, :a}, da, db), do: {da + 1, db}
  defp step({:close, :a}, da, db), do: {da - 1, db}
  defp step({:open, :b}, da, db), do: {da, db + 1}
  defp step({:close, :b}, da, db), do: {da, db - 1}

  # A result span runs from one operand's written start (or end) to another's, and carries the metadata of the
  # a-side member it opened in, which is the first-operand rule of the guide.
  defp span_between({from_position, opened_in}, {to_position, closed_by}), do: ...
end
```

The public operations differ from this only in what they do before and after: `Tempo.union/3` keeps members whole (`spans(a) ++ spans(b)`, sorted, not coalesced), as the guide promises, while `Tempo.IntervalSet.coalesce/1` is the sweep's `union`; the instant-level operations are the sweep as written. Members that recur on a cycle are cut at the cycle's end into two edges before the sweep and joined after it (`Tempo.Scale.cut/1`), once, for every operation alike. A `:within` window places a cyclic operand on each day of the window before the sweep. Nothing converts a calendar, extends a resolution or rewrites an axis: positions are positions.

**Laws, held by property tests rather than by cases:** commutativity and associativity of union and intersection at the extent level, De Morgan under a window, `difference(a, a) == []`, `union(a, a) ≡ coalesce(a)`, and that every result is canonical. The reference model is the one above with integers for positions.

### 7.3 `Tempo.Allen`: four comparisons

Prototyped and verified: over every pair of spans on a seven-point line (441 pairs) the classifier hits all thirteen relations and no pair hits two; the inverse law holds for every pair; the composition table derived by brute force has exactly 169 cells and `equals ∘ r = r`.

```elixir
defmodule Tempo.Allen do
  @moduledoc """
  Allen's thirteen relations between two spans, their inverses and their composition, and the everyday predicates as sets of them.
  """
  alias Tempo.Scale

  @relations [:precedes, :meets, :overlaps, :finished_by, :contains, :starts, :equals,
              :started_by, :during, :finishes, :overlapped_by, :met_by, :preceded_by]

  # The predicate vocabulary, each a set of relations. This is the one table.
  @before [:precedes, :meets]
  @after [:met_by, :preceded_by]
  @adjacent [:meets, :met_by]
  @within [:equals, :starts, :during, :finishes]
  @contains [:equals, :started_by, :contains, :finished_by]
  @disjoint [:precedes, :meets, :met_by, :preceded_by]
  @overlapping @relations -- @disjoint

  def relation({a_from, a_to}, {b_from, b_to}) do
    classify(Scale.compare(a_from, b_from), Scale.compare(a_to, b_to), Scale.compare(a_to, b_from), Scale.compare(a_from, b_to))
  end

  # start–start, end–end, a's end against b's start, a's start against b's end
  defp classify(_, _, :lt, _), do: :precedes
  defp classify(_, _, :eq, _), do: :meets
  defp classify(_, _, _, :gt), do: :preceded_by
  defp classify(_, _, _, :eq), do: :met_by
  defp classify(:lt, :lt, _, _), do: :overlaps
  defp classify(:lt, :eq, _, _), do: :finished_by
  defp classify(:lt, :gt, _, _), do: :contains
  defp classify(:eq, :lt, _, _), do: :starts
  defp classify(:eq, :eq, _, _), do: :equals
  defp classify(:eq, :gt, _, _), do: :started_by
  defp classify(:gt, :lt, _, _), do: :during
  defp classify(:gt, :eq, _, _), do: :finishes
  defp classify(:gt, :gt, _, _), do: :overlapped_by

  def inverse(relation), do: Map.fetch!(@inverses, relation)
  def compose(r1, r2), do: Map.fetch!(@composition, {r1, r2})     # the 169-cell table, generated at compile time from classify/4
  def holds?(set, a, b), do: relation(a, b) in set
end
```

The composition table is not written by hand: a compile-time comprehension over spans on a short line derives it from `classify/4`, as the prototype did, so it cannot disagree with the classifier. `Tempo.Interval.Composition` (315 lines) goes.

**Everyday predicates on any expression.** `before?/2`, `after?/2`, `adjacent?/2`, `within?/2`, `contains?/2`, `overlaps?/2`, `disjoint?/2` and `equal?/2` are defined on covered time, so they take plural operands: `within?(a, b)` is `difference(a, b) == []`, `overlaps?(a, b)` is `intersection(a, b) != []`, `before?(a, b)` is that the last span of `a` ends no later than the first of `b` begins, `adjacent?` that the coalesced forms meet, `equal?` that the coalesced forms are the same spans. For two single spans these coincide with the relation sets above, which a property test asserts for every pair. `Tempo.relation/2` is the thirteen-way answer for two single spans and an error for a plural operand, as today. This is one engine with one table, where today there are two engines and five tables.

**Certainty.** `certainly_*` and `possibly_*` ask the same question of every *reading* of an uncertain operand: the members of a one-of set, the candidates of a mask, the placements of a margin. `Tempo.Allen.readings/1` gives the readings as spans (bounded by `Tempo.Limit`), `relations(a, b)` is the set of relations over the cartesian product, and a verdict is `:certain` when the set is within the predicate's set, `:impossible` when disjoint from it, `:possible` otherwise. The envelope shortcut for a margin over many placements (classify once over sets of comparisons) is kept as an optimisation of `relations/2` with the same result. This is today's design, kept, in about a quarter of its lines, because the readings are spans like any other.

### 7.4 `Tempo.Select`: periods, expansion, positions

```elixir
defmodule Tempo.Select do
  @moduledoc false
  alias Tempo.{Expand, Spans}

  # The selector applied to each span of the base: the base's spans are the periods, as today.
  def select(base, selection, options) do
    with {:ok, periods} <- Spans.spans(base, options) do
      {:ok, Stream.flat_map(periods, &in_period!(&1, selection, options))}
    end
  end

  # In one period: the period's concrete units are the prefix, the selection's parts are the units beneath it, and
  # the expansion is the candidates in order; positions pick among them; a window opens a span from each.
  def in_period(period, selection, options) do
    {parts, positions, window} = Tempo.Unit.split_selection(selection)
    prefix = concrete_units(period)
    candidates = Expand.expand(prefix ++ parts, period.calendar)
    picked = if positions == [], do: candidates, else: Expand.positions(candidates, positions)
    {:ok, picked |> Stream.map(&as_span(period, &1)) |> windowed(window, options)}
  end
end
```

That is the whole of `select/2`, `Tempo.selected_in/1`, the weekday fast path, the index path and the merge path. `Tempo.workdays/2` is a selection by `day_of_week` from Localize's territory data, less the days off, as today, built on `select/3`. Three parameters the review found resisting a single engine are explicit here:

* **Ownership.** A part names the period it counts in by its position in the prefix: `[year: 2026, month: 6, day_of_week: 1]` counts Mondays in June, `[year: 2026, day_of_week: 1]` in the year. A week under a month is `Tempo.Calendar.weeks_of_month/3`, a calendar fact (TR35's minimum days), asked as a period.

* **Grain.** The result's resolution is the finest unit the selection names, as it is for any value: a weekday selection gives days, a month selection months, a time selection minutes. `as_span/2` writes the picked value at that resolution.

* **Positions count in the period.** `I` and `BYSETPOS` index the candidates of one period; `BYDAY=2MO` in a yearly rule is lowered by the RRULE adapter to `[month: {1..12}, day_of_week: 1, instance: 2]` applied in each month, so the two meanings are two selections, not one engine with a switch.

RFC 5545's own rules live in `Tempo.RRule` as rewrites of the selection before it reaches the engine: DTSTART inheritance (`rule.ex:657-781` today), the EXPAND/LIMIT downgrades, `origin_day` clamping and `SKIP` (a generator, applied to the expansion's output), `WKST` (a parameter of `week_of_year` and `day_of_week` numbering), and cron's `W` and `?`. The engine knows none of them.

### 7.5 `Tempo.Shift`: one arithmetic

```elixir
defmodule Tempo.Shift do
  @moduledoc false

  # A value shifted by a duration keeps its resolution, extended to the duration's finest unit as the guide says.
  # The calendar part (years, months, weeks, days) is the calendar's: `shift_date/4` on the value's first day, as
  # `Date.shift/2` does, years then months then clamp then days. The clock part is tick arithmetic on the value's
  # frame, shown through the zone, so an hour across a change of the clock is an hour of elapsed time.
  def shift(%Tempo{form: {:value, units}} = value, %Tempo.Duration{} = by) do
    with {:ok, units} <- extend_to(units, finest(by), value.calendar),
         {date, clock} <- split(by),
         {:ok, units} <- shift_date(units, date, value),
         {:ok, units} <- shift_clock(units, clock, value) do
      {:ok, %{value | form: {:value, units}}}
    end
  end

  # An interval is shifted end by end and keeps its length in days when the duration has months or years.
  def shift(%Tempo{form: {:span, from, to}} = span, by), do: ...
  # A plural expression is its members shifted; a recurrence is its first span shifted.
  def shift(%Tempo{form: {:all, members}} = set, by), do: ...

  # The nth cadence from a recurrence's first span, in one call: the duration multiplied, never accumulated.
  def by_cadences(first, n), do: shift(first, Tempo.Duration.multiply(cadence(first), n))

  # A value with no year is shifted on its cycle with the calendar's bounds for any year, and is an
  # UnanchoredError where the answer would depend on the year (today's invariance rule, unchanged).
  defp shift_date(units, by, %Tempo{} = value) when not anchored?(units), do: cycle_shift(units, by, value.calendar)

  defp shift_date(units, by, value) do
    {y, m, d} = first_date(units, value.calendar)
    {:ok, {y, m, d}} = Tempo.Calendar.shift_date(value.calendar, y, m, d, by)
    {:ok, rewrite_date(units, {y, m, d}, value.calendar)}      # back onto the value's axis: a week date stays a week date
  end
end
```

`trunc/2` drops units; `round/2` is `trunc` plus one unit when the value's start is past the midpoint of the coarser period, measured in ticks; `extend/2` and `at_resolution/2` append the first child (`Expand.children/3`, first element). A shift of a value with a set in a unit shifts each value `Expand` gives and gathers the results, as today, but through `Spans` and `Algebra` rather than 1,300 lines of its own. `shift/3` with `:skipping` is `Algebra.difference` of the line against the busy set, then a walk of the free spans for the duration, about 60 lines.

### 7.6 `Tempo.Reader` and `Tempo.Writer`

**The grammar is written down first.** `guides/iso8601-grammar.md` carries an ABNF transcribed clause by clause from ISO 8601-1 §4 and §5, ISO 8601-2 §4 to §13, RFC 9557 §4, and Tempo's extensions in a marked section. Each production names the clause it comes from. The reader is then written as one function per production, in the order of the grammar, so that a reader of the code can hold it against the standard:

```elixir
defmodule Tempo.Reader do
  @moduledoc false
  # Each function is a production of guides/iso8601-grammar.md and returns {:ok, result, rest} or :error.
  # The text is split first at the places ISO 8601 makes structural: a trailing suffix, a leading `R`, the `/`
  # of an interval, the braces of a set. Within a piece the alternatives are tried in the order the grammar lists
  # them, and basic-format digit runs are told apart by their length, as ISO 8601-1 §5.2 tells them apart.

  @spec read(String.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Tempo.ParseError.t()}
  def read(text, options) do
    with {:ok, body, suffix} <- suffix(text),
         {:ok, form, ""} <- expression(body),
         {:ok, expression} <- build(form, suffix, options),
         {:ok, expression} <- Tempo.Validate.validate(expression) do
      {:ok, expression}
    end
  end

  # expression = recurrence / interval / set / duration / value
  defp expression(<<"R", rest::binary>>), do: recurrence(rest)
  defp expression(<<"{", _::binary>> = text), do: set(text, :all)
  defp expression(<<"[", _::binary>> = text), do: set(text, :one)
  defp expression(<<"P", _::binary>> = text), do: duration(text)
  defp expression(text), do: interval_or_value(text)

  # date-basic = 4DIGIT [2DIGIT [2DIGIT]]  ; ISO 8601-1 §5.2.2.1
  defp date_basic(<<y::binary-size(4), m::binary-size(2), d::binary-size(2), rest::binary>>) when digits?(y) and digits?(m) and digits?(d), do: ...
  # …
end
```

Validation of what is read is not the reader's: `Tempo.Validate` runs once over the built expression and is the same pass `Tempo.new/1` and `Tempo.Interval.new/1` run. The reader needs no memo table, no fast path and no profile entry points: binary pattern matching on a hand-written reader is the fast path, and `parse_date/2` and its siblings are the same reader entered at one production.

**Tests.** A generator from the ABNF (the pilot of `plans/parser-formal-grammar.md` is this generator) produces texts the reader must accept and round-trip through `Tempo.Writer`; a mutator produces texts it must refuse; the standard's own examples are a table (the plan counts 573). The EDTF corpus and the conformance guide's examples stay.

`Tempo.Writer` is the inverse by form: a value's units in explicit form, an interval's two ends with `/`, `R` and the count, braces for a set, the suffix once. It reads the same `Tempo.Unit` shapes and nothing else.

### 7.7 `Tempo.Validate`: one pass

```elixir
defmodule Tempo.Validate do
  @moduledoc false
  # A value: every unit is one the calendar gives under its prefix (Expand.children), the clock is in range,
  # the shift is in range, a zoned reading is one the clock shows (Zone.offsets_at_wall != []), a value with no
  # year is within the calendar's bounds for any year.
  def validate(%Tempo{form: {:value, units}} = value), do: ...
  # An interval: both ends valid, one calendar, one zone, from before to on their frame (Scale), at most one duration end.
  def validate(%Tempo{form: {:span, from, to}} = span), do: ...
  # A recurrence: its span valid, its bound a count, :infinity or a value after the start, its rule's parts finer than the cadence.
  def validate(%Tempo{form: {:every, span, bound, rule}}), do: ...
  # A set: every member valid and in the set's calendar and zone.
  def validate(%Tempo{form: {kind, members}}) when kind in [:all, :one], do: ...
end
```

This replaces `Validation` (2,944 lines), the parser's `refused/1` walks, `Group`'s shape errors, `on_the_clock_of_its_zone`, `validate_zone_existence` and the constructors' private checks.

## 8. Calendrical: the contract Tempo needs

### 8.1 Today: forty-one callbacks at 157 sites

Measured at `3a85c80` (the copy under `deps/` was stale; the figures are from the pinned source). Tempo calls 33 of Calendrical's 51 callbacks and 8 of Elixir's 28, plus 17 calls on `Calendrical.Kday`, `Calendrical.Ecclesiastical`, `Calendrical.Lunisolar` and the CLDR registry. By concept:

| Concept | Callbacks called today | Sites |
|---|---|---|
| Day scale and arithmetic | `date_to_iso_days/3`, `date_from_iso_days/1`, `plus/6`, `diff/3` | 31 |
| Lengths, numbers and validity | `valid_date?/3`, `leap_year?/1`, `months_in_year/0`, `months_in_year/1`, `days_in_month/1`, `days_in_month/2`, `days_in_year/1`, `month_numbers/1`, `day_numbers/2`, `days_in_week/0`, `years_in_cycle/0` | 65 |
| Periods | `year/1`, `month/2`, `quarter/2`, `quadrimester/2`, `semester/2`, `week/2`, `weeks_in_month/2`, `month_week/3` | 16 |
| Weeks, three numberings | `day_of_week/4`, `week_of_year/3`, `iso_week_of_year/3`, `date_from_week_date/3`, `week_date_from_date/3`, `weeks_in_year/1`, `weeks_in_week_year/1` | 18 |
| Other axes | `day_of_year/3`, `date_from_day_of_year/2`, `quarter_of_year/3` | 16 |
| Names | `cldr_calendar_type/0`, `traditional_months/1`, `ordinal_month_from_traditional/2`, `month_of_year/3`, `cardinal_month/1`, `cardinal_day/3`, `named_month/2`, `year_of_era/3` | 13 |
| Events | `solar_term/2` | 1 |

Seventeen Calendrical callbacks are never called: `numeric_month/3`, `week_of_month/3`, `calendar_base/0`, `dates_in_gregorian_year/3`, `months_in_leap_year/0`, `lunar_month_of_year/2`, `leap_month/1`, `traditional_leap_month/1`, `cldr_calendar_type/3`, `calendar_from_cldr_calendar_type/1`, `era_calendar_type/0`, `parsing_calendar/0`, `parsing_calendars/0`, `calendar_year/3`, `extended_year/3`, `related_gregorian_year/3`, `cyclic_year/3`, and the four of `Calendrical.Formatter`.

### 8.2 The probe

Before proposing the contract, the claim that periods and the day scale suffice was tested against the pinned Calendrical for eleven calendars: Gregorian, Hebrew (a common and a leap year), the ISO week calendar, England's reform calendar (1751 and 1752), the Julian year beginning 25 March, Chinese, Coptic, Umm al-Qura and Persian. For each, the months of a year were found by walking the year's span on the day scale (the month holding a day, then the day after its last) and the days of a month by stepping its span.

| Calendar | Year | Months walked | Days by month | Year days | Weeks walked |
|---|---|---|---|---|---|
| Gregorian | 2026 | 12 | 31 28 31 30 … | 365 = 365 | 52 |
| Hebrew | 5787 | 13 | 30 30 30 29 30 30 29 30 29 30 29 30 29 | 385 = 385 | 56 |
| Hebrew | 5786 | 12 | 30 29 30 29 … | 354 = 354 | 51 |
| ISO week calendar | 2026 | 12 | 28 35 28 28 35 28 28 35 28 28 35 35 | 371 = 371 | 53 |
| Reform.England | 1751 | 10 (months 3 to 12) | 7 30 31 30 31 31 30 31 30 31 | 282 = 282 | 41 |
| Reform.England | 1752 | 12 | … 31 **19** 31 30 31 | 355 = 355 | 51 |
| Julian.March25 | 1750 | 13 | 7 30 31 30 31 31 30 31 30 31 31 28 24 | 365 = 365 | 53 |
| Chinese | 4663 | 12 | 30 29 30 29 29 30 29 29 30 30 30 29 | 354 = 354 | 51 |
| Coptic | 1742 | 13 | 30 × 12, 5 | 365 = 365 | 53 |
| Umm al-Qura | 1447 | 12 | 30 29 30 30 30 29 … | 355 = 355 | 52 |
| Persian | 1405 | 12 | 31 × 6, 30 × 5, 29 | 365 = 365 | 53 |

In every calendar the months walked on the day scale sum exactly to the year's days. September 1752 in England walked as `1 2 14 15 … 30`, nineteen days, with no gap handling: the days exist, only their labels skip, and `valid_date?(1752, 9, 3)` is false. `Localize.Calendar.ISO`, the adapter's target for `Calendar.ISO`, answers the same questions (`week(2026, 1)` is 29 December 2025 to 4 January 2026; 53 weeks in 2026). Two observations for Calendrical from the same run: `Reform.England.months_in_year(1751)` answers 12 where the year has ten months (3 to 12), which the contract below makes moot by not asking; and `Calendrical.Gregorian.weeks_in_year(2026)` is 52 where ISO 8601 (and `Localize.Calendar.ISO`) count 53, which is the Gregorian calendar's own week rule as the 2.0 changelog describes it, and is one reason for decision 13 in section 10.

### 8.3 The contract

Eighteen callbacks, in a `Tempo.Calendar` behaviour that `Calendrical.Behaviour` implements for every calendar and `Localize.Calendar.ISO` implements for `Calendar.ISO`. Five are Elixir's own `Calendar` callbacks and cost nothing.

| Group | Callback | Answers | Replaces |
|---|---|---|---|
| Day scale | `date_to_iso_days/3` | the day number of a date | — |
| Day scale | `date_from_iso_days/1` | `{year, month, day}` of a day number | — |
| Validity | `valid_date?/3` (Elixir) | whether a date exists | `month_numbers/1`, `day_numbers/2` |
| Periods | `year/1` | the `Date.Range` of a year, or an error | `days_in_year/1`, `date_from_day_of_year/2`, `day_of_year/3`, `years_in_cycle/0` |
| Periods | `month/2` | the range of a month, or an error | `months_in_year/1`, `days_in_month/2`, `plus/6`, `diff/3` |
| Periods | `week/2` | the range of a week of the calendar's own week-year, or an error | `weeks_in_year/1`, `weeks_in_week_year/1`, `date_from_week_date/3`, `days_in_week/0` |
| Periods | `quarter/2` | the range of a quarter | `quadrimester/2`, `semester/2` (groups of months) |
| Periods | `weeks_of_month/2` | the ranges of the weeks a month has | `weeks_in_month/2`, `month_week/3` |
| Labels | `day_of_week/4` (Elixir) | the day of the week, 1 to 7 from Monday | `Kday.*`, the week-start probe |
| Labels | `week_of_year/3` | `{week_year, week}` in the calendar's own weeks | `iso_week_of_year/3`, `week_date_from_date/3` |
| Arithmetic | `shift_date/4` (Elixir) | a date moved by a `Duration` of years, months, weeks and days, years then months then clamp then days | `plus/6` |
| No year | `months_in_year/0` | `{fewest, most}` months any year has | the `{:ambiguous, _}` shape |
| No year | `days_in_month/1` | `{fewest, most}` days the month has in any year | the `{:ambiguous, _}` shape |
| Names | `cldr_calendar_type/0` | the CLDR type, for IXDTF and Localize | — |
| Names | `traditional_month/2` | a month as the calendar names it: `n` or `{n, :leap}` | `traditional_months/1`, `month_of_year/3`, `lunar_month_of_year/2`, `leap_month/1`, `traditional_leap_month/1` |
| Names | `month_from_traditional/2` | the inverse | `ordinal_month_from_traditional/2` |
| Accessors | `leap_year?/1`, `quarter_of_year/3` (Elixir) | forwarded by `Tempo.leap_year?/1` and `Tempo.quarter_of_year/1` | — |

Not callbacks: `Calendrical.Ecclesiastical.easter_sunday/1` and a `Calendrical.Lunisolar.solar_term/3` that takes the calendar are module functions `Tempo.Event` calls (section 7 leaves `Tempo.Event` as it is); `Calendrical.calendar_from_cldr_calendar_type/1` is the registry `Tempo.Calendar.from_type/1` calls; `Calendrical.validate_calendar/1` is replaced by asking whether a module declares the `Tempo.Calendar` behaviour. Eras, cardinal months and days, named months and `numeric_month/3` are display facts Localize reads from the calendar itself when Tempo hands it a date.

### 8.4 The laws a calendar must satisfy

These are what Tempo relies on in place of knowing a calendar's kind. Calendrical should carry them as a property test every calendar runs (`Calendrical.Test.Laws`), as Tempo will run them against each calendar it is tested with.

1. **Round trip.** `date_from_iso_days(date_to_iso_days(y, m, d)) == {y, m, d}` for every valid date.
2. **Order.** For valid dates, `date_to_iso_days` is strictly increasing in the lexicographic order of `{y, m, d}`. This is what lets two values of one calendar be compared by their fields without a calendar call.
3. **Tiling.** The months of a year, found by walking `year(y)` on the day scale through `month/2`, cover the year exactly, with no gap and no overlap; the weeks of a week-year likewise through `week/2`; a day belongs to exactly one month and one week.
4. **Labels agree with periods.** `week_of_year(y, m, d) == {wy, w}` exactly when the day is in `week(wy, w)`; `day_of_week` runs 1 to 7 over any seven consecutive days.
5. **Absence is an error.** `month/2`, `week/2` and `quarter/2` return `{:error, _}` for a period the calendar does not have (`month(1751, 1)` in England, `week(2026, 54)`), never a range of another period.
6. **Bounds.** `months_in_year/0` and `days_in_month/1` are the minimum and maximum over the calendar's years; a value within the minimum exists in every year.
7. **Shift.** `shift_date/4` returns a valid date, applies years then months then clamps the day then adds weeks and days, and a shift of zero is the identity.

### 8.5 Changes asked of Calendrical

* Add `weeks_of_month/2`, `traditional_month/2` and `month_from_traditional/2`; change `months_in_year/0` and `days_in_month/1` to answer `{fewest, most}`; make `week/2` and `quarter/2` answered by every calendar (the behaviour's defaults return `{:error, :not_defined}` today).
* Publish the laws of 8.4 as a test every calendar runs.
* Declare `Tempo.Calendar` (or, so that Calendrical does not depend on Tempo, a `Calendrical.Period` behaviour of the same eighteen that Tempo names as its contract) from `Calendrical.Behaviour`, and from `Localize.Calendar.ISO`.
* Deprecate, for Tempo's purposes, the callbacks of 8.1 that the contract replaces (the fourth column of 8.3). Whether Calendrical keeps them for other consumers is Calendrical's call; Tempo will not call them.
* Settle the week question (decision 13).

## 9. The public API

### 9.1 What is preserved

Every function the guides name keeps its name, its arguments and its documented examples, which are the acceptance test (`test/guides_test.exs` runs them today):

* **Construction and reading.** `Tempo.new/1`, `new!/1`, `from_iso8601/2`, `from_iso8601!/2`, `parse/2`, `parse!/2`, `parse_duration/1`, `from_elixir/2`, `from_date/1`, `from_time/1`, `from_naive_datetime/1`, `from_datetime/1`, `from_date_range/2`, the `~o` sigil in value and match context, `Tempo.Interval.new/1`, `Tempo.IntervalSet.new/2`, `Tempo.RecurrenceSet.new/2`, `Tempo.Duration.new/1`, `Tempo.RRule.parse/2`, `Tempo.Cron.parse/2`, `Tempo.ICal.parse/2`, `Tempo.JSCalendar.parse/2`.
* **Reading parts.** `year/1` to `second/1`, `week/1`, `season/1`, `day_of_week/2`, `day_of_year/1`, `quarter_of_year/1`, `leap_year?/1`, `days_in_month/1`, `resolution/1`, `anchored?/1`, `floating?/1`, `zoned?/1`, `bounded?/1`, `empty?/1`, `qualification/1,2`, `metadata/1`, `put_metadata/2`, `Tempo.Interval.from/1`, `to/1`, `endpoints/1`, `Tempo.IntervalSet.members/1`, `count/1`, `first/1`, `last/1`.
* **Conversion and text.** `to_interval/2`, `to_iso8601/1`, `to_string/2`, `to_relative_string/2`, `explain/1`, `to_elixir/1`, `to_date/1`, `to_time/1`, `to_naive_datetime/1`, `to_datetime/1`, `to_calendar/2`, `in_zone/2`, `shift_zone/2`, `in_territory/2`, `Tempo.RRule.to_string/1`, `inspect/1`.
* **Walking.** `Enumerable` for every expression, `Tempo.map/2`, `try_map/2`, `Tempo.IntervalSet.walk/1`, `from_stream/1`, `filter/2`, `map/2`, `coalesce/1`, `covered/2`, `covered?/2`, `slots/3`, `relation_matrix/1`.
* **Selection.** `select/2`, `select!/2`, `workdays/2`, `weekends/1`, `weekend?/2`, `workday?/2`, `add_workdays/3`, `next_workday/2`, `previous_workday/2`, `nearest_workday/2`, `roll_to_workday/3`, `count_workdays/2`.
* **Set operations.** `union/3`, `intersection/3`, `difference/3`, `complement/2`, `symmetric_difference/3`, `members_overlapping/3`, `members_outside/3`, `members_in_exactly_one/3`, with `:within` and `:metadata`.
* **Relations and lengths.** `relation/2`, `compare/3`, `before?/2`, `after?/2`, `adjacent?/2`, `within?/3`, `contains?/3`, `overlaps?/3`, `disjoint?/3`, `equal?/3`, `Tempo.Allen.compose/2`, `inverse/1` and the thirteen `Tempo.Allen.<relation>?/2`, `duration/1,2`, `at_least?/2`, `at_most?/2`, `exactly?/2`, `longer_than?/2`, `shorter_than?/2`, `Tempo.Duration.add/2`, `subtract/2`, `sum/1`, `negate/1`, `compare/3`, `to_unit/3`.
* **Arithmetic.** `shift/3` with `:skipping`, `trunc/2`, `round/2`, `extend/2`, `at/2`, `on/2`, `merge/2`, `split/1`.
* **Time.** `now/1`, `utc_now/0`, `today/1`, `utc_today/0`, `Tempo.Clock`.
* **Recurrence sets.** `Tempo.RecurrenceSet.keep_when/2`, `move_when/2`, `filter/2`, `members/1`.
* **Events, networks, scheduling.** `Tempo.Event.date/3`, `known/0`; `Tempo.Network.*` and `Tempo.Schedule.*` as the chronological-networks and scheduling guides use them (from the companion package).

### 9.2 What changes in meaning

Each is a decision in section 10. Quoted behaviour is the compiled library at `a43b944`.

1. **Enumerating a plural expression yields its members.** Today `Enum.count(~o"2026Y{1,3}M")` is 2 while `Enum.count(Tempo.to_interval!(~o"2026Y{1,3}M"))` is 62, and `Enum.count(~o"R5/2022-01-01/P1M")` is 151 where the guide has to add that the occurrence count is `IntervalSet.count/1`. Under law 6, all three are the members: 2, 2 and 5. `Enum.count(~o"2026-06")` stays 30 and `Enum.count(~o"2026-06-15")` 24. `Tempo.members/1` gives the spans of anything; to walk a set's members at a unit, `Enum.flat_map(set, &Tempo.walk(&1, :day))`.

2. **No `:unit`.** `Tempo.to_interval(~o"2026-06-15")` is `~o"2026-06-15/2026-06-16"`, which walks its one day; today it carries `unit: :hour` so that it walks 24 hours. `Tempo.walk/2` says the unit explicitly. The `unit:` decoration in `inspect/1` goes with it, and so does §1.4 of the set-operations guide.

3. **The structs become forms.** `%Tempo.Interval{}`, `%Tempo.IntervalSet{}`, `%Tempo.Set{}`, `%Tempo.Range{}`, `%Tempo.RecurrenceSet{}` and `%Tempo.RecurrenceSet.Conditional{}` are no longer struct types; their modules keep the functions of 9.1 and return `%Tempo{}`. Code that matches `%Tempo.Interval{from: f}` breaks at compile time and is rewritten as `%Tempo{form: {:span, f, _}}` or, better, through `Tempo.Interval.from/1`; the `~o` sigil in match context expands to the new shape, so every sigil pattern in the pattern-matching guide keeps working. Interval-set backends go: members are a list or a `Stream`, and `IntervalSet.from_stream/1` stays.

4. **Networks and scheduling move to a companion package**, `tempo_network`, with their module names unchanged.

### 9.3 Where the same ideas can be said more simply

Each proposal keeps what the guides mean and removes a word, a duplicate or a mechanism. Each is a decision.

5. **One certainty function.** Eleven functions (`overlap_certainty/2`, `within_certainty/2`, `relation_certainty/3`, and `certainly_` and `possibly_` for `before`, `after`, `overlaps` and `within`) become three: `Tempo.certainty(predicate, a, b) :: :certain | :possible | :impossible`, `Tempo.certainly?(predicate, a, b)` and `Tempo.possibly?(predicate, a, b)`, where `predicate` is one of the everyday predicates (`:before`, `:after`, `:adjacent`, `:within`, `:contains`, `:overlaps`, `:disjoint`) or an Allen relation. It reads aloud as well (*"certainly within?"*) and every predicate gets a graded form for free.

6. **One reader.** `from_iso8601/2` with a `:profile` option (`:date`, `:time`, `:datetime`, `:interval`, `:duration`) replaces `parse_date/2`, `parse_time/2`, `parse_datetime/2`, `parse_interval/2` and `parse_duration/1`, and `read/2` goes as a duplicate of `from_iso8601/2`. `parse/2` stays as the locale-aware reader that falls back to ISO 8601. Five entry points become two.

7. **`to_interval_set/1` goes.** With one struct, `to_interval/2` already answers a span for a singular expression and an `{:all, …}` for a plural one, as it does today; a function whose only job is to wrap one in a list of one is not needed. `Tempo.members/1` is the list.

8. **One word for resolution change.** `extend/2`, `extend_resolution/2` and `at_resolution/2` are three names for writing a value at another unit. One, `Tempo.at_resolution/2`, with `extend/2` as the one-step form, is enough; the review did not find a meaning the third carries that the others do not.

9. **Workdays have one home.** The ten workday functions stay on `Tempo` for the guides' examples, with their bodies in `Tempo.Workdays`, which today holds a struct and nothing else.

10. **The `Tempo` module is the API, not the engine.** It keeps every public function's documentation and a body that validates arguments, calls one core function and shapes the answer; it does not hold the algorithms. This revisits the ruling of 2026-10-12 that a documented function's body lives with its documentation: the body does, and is short, because the algorithm has a module of its own that a reader can open. A 17,778-line module is the alternative, and it is the one thing in the current code every reviewer named first.

11. **One place for limits.** `Tempo.Limit` holds every bound; the five module attributes that hold one today go.

12. **Errors are fewer and say the same thing.** Twenty-four exception modules today. Those that differ only in wording (`UnboundedRecurrenceError` and `UnboundedSetError`; `FloatingTempoError`, `ZonedTempoError` and `ZoneOffsetMismatchError`; `InvalidDateError`, `InvalidTimeError`, `InvalidUnitError` and `ResolutionError`) merge into one per cause with a `:reason`, which is the shape `ConversionError` already has. About ten remain.

## 10. Decisions for the user

Numbered to match sections 9.2 and 9.3 where they correspond. Each carries the recommendation this review makes.

| # | Decision | Recommendation |
|---|---|---|
| 1 | Enumeration of a plural expression yields its members (law 6). | Yes. It removes the two-rule semantics and the three documented divergences; `Enum.count` of a recurrence becomes its occurrence count. |
| 2 | Drop the `:unit` field; add `Tempo.walk/2`. | Yes. It follows from law 3; the field exists only to make two different expressions walk alike. |
| 3 | One struct, `%Tempo{}`, with six forms; the struct modules become constructors. | Yes. It is the README's stated objective, and every core module becomes one set of clauses over one type. |
| 4 | Networks and scheduling to a companion package. | Yes. The dependency is one way and the 4,462 lines double the size of the core. |
| 5 | Collapse the certainty API to `certainty/3`, `certainly?/3`, `possibly?/3`. | Yes. |
| 6 | One reader, `from_iso8601/2` with `:profile`; `read/2` goes. | Yes. |
| 7 | `to_interval_set/1` goes. | Yes, with `to_interval/2` documented as answering a set for a plural expression, as it does. |
| 8 | One name for writing a value at another resolution. | Yes, `at_resolution/2` and `extend/2`. |
| 9 | Workday bodies in `Tempo.Workdays`. | Yes. |
| 10 | `Tempo` holds documentation and short bodies; algorithms in core modules. | Yes. This revisits the 2026-10-12 ruling. |
| 11 | One `Tempo.Limit`. | Yes. |
| 12 | Merge exceptions by cause, about ten remaining. | Yes. |
| 13 | **Weeks.** One week system per calendar, the calendar's own, which for `Calendar.ISO` is ISO 8601's; `W` on a value of another calendar means that calendar's weeks; the Gregorian ISO week of a Hebrew date is a conversion (`to_calendar/2`), not a second numbering. The `w` designator goes. | Yes. It removes three numberings and the one place that still decides by module (`select.ex:2459`). This changes what `~o"5786Y10W"` means for a Hebrew value. |
| 14 | **Written ends** (section 4.2): an interval written to a date runs through that date; one written to a time of day runs to that reading; the struct stays half-open and the writer writes a span back as it was read. | Decided by the user on 2026-10-13 after review: yes. `~o"2026/2028"` is three years. |
| 15 | The border adapter `Tempo.Calendar` with `Calendar.ISO → Localize.Calendar.ISO` as configuration, replacing `inside`/`outside`. | Yes. |
| 16 | The calendar contract of 8.3 and the laws of 8.4, with the Calendrical changes of 8.5. | Yes. Calendrical work is small: three additions, two signature changes, a law test. |
| 17 | A hand-written reader over a written ABNF, replacing NimbleParsec, with generator tests. | Yes. The fast path already proves the approach; the grammar becomes a document a reader can hold the code to. |
| 18 | Build the redesign on a branch, with the current library's answers as golden files (section 11.1). | Yes. |

## 11. Delivery

### 11.1 The oracle comes first

Before any core code changes, the current library's answers are frozen as data. A script over a generated corpus (every form in the operation matrix, the calendar census's 579 full forms and 520 selections, the EDTF corpus, the RFC 5545 conformance rules, the guides' examples, and random pairs for the set operations and relations) writes, for each input, what the current library answers: `to_iso8601/1`, the ends of `to_interval/2`, the first fifty of `Enum.to_list/1`, `relation/2` for pairs, each set operation for pairs, `shift/2` for a table of durations, `select/2` for the census's selections. The redesign's tests read these files; a difference is either a defect in the new code or a change decided in section 10, and nothing else. The matrix's "total, consistent, right" checks and the reference tests, which compute answers independently of either implementation, are ported as they stand.

### 11.2 Phases

Each phase ends with its slice of the oracle green, the six gates clean (format, compile with warnings as errors, tests, dialyzer, credo strict, docs with warnings as errors) on the mise-current toolchain, and its line budget from 5.3 held.

| Phase | Builds | Oracle slice | Budget |
|---|---|---|---|
| 0 | The golden files; the ABNF; the Calendrical additions of 8.5 and their law test | — | — |
| 1 | `Tempo.Unit`, `Tempo.Calendar`, `Tempo.Zone`, `Tempo.Limit`, `Tempo.Scale`, `Tempo.Duration` | The law test against every Calendrical calendar; positions against `Compare.to_utc_seconds` for every census value | 1,300 |
| 2 | The struct; `Tempo.Reader`, `Tempo.Writer`, `Tempo.Validate`; `Tempo.new/1`, `Interval.new/1`, `IntervalSet.new/2`, the sigils | Round trip of every text in the oracle; the EDTF corpus; the generator and mutator tests; the matrix's "total" check | 3,500 |
| 3 | `Tempo.Expand`, `Tempo.Walk`, `Tempo.Spans`; `Enumerable`; `to_interval/2`, `members/1`, `walk/2` | The census's walks; the matrix's "consistent" and "right" checks for Convert and Walk; the enumeration guide | 1,400 |
| 4 | `Tempo.Algebra`, `Tempo.Allen`; the set operations, relations, predicates, certainty | The set-operations measure test and its integer model; the predicate and certainty tests; the set-operations guide | 700 |
| 5 | `Tempo.Shift`; `shift/3`, `trunc`, `round`, `at_resolution`, `at/on`, durations between values | The stepping, shift-of-sets and shift-of-masks tests; the matrix's Shift and Measure columns | 500 |
| 6 | `Tempo.Select`; `Tempo.RRule`, `Cron`, `ICal`, `JSCalendar`; `Tempo.Event`; workdays | The census's selections; RFC 5545 conformance; the cron, iCal and JSCalendar tests; the holidays guides | 2,800 |
| 7 | `Tempo.Format`, `Tempo.Explain`, `Inspect`, `to_string/2` | The format and explain tests; every guide and livebook re-run | 2,500 |
| 8 | `tempo_network`; the migration guide; the changelog; the release | The chronological-networks and scheduling guides; `mix docs --warnings-as-errors` | moved |

Phases 4 and 5 can proceed in parallel with 6 once 3 is done; 7 waits on all of them.

### 11.3 Risks and how the plan meets them

* **Speed.** The reader must read a plain date in about 15 µs, which is what the byte scanner does today; a hand-written reader on binary patterns is the same technique applied to the whole grammar. The expansion engine walks periods where today's code counts, so a walk of a year's days asks `month/2` twelve times and `date_from_iso_days` 365 times; the arithmetic calendars answer in nanoseconds, and the astronomical ones (Umm al-Qura, Chinese) already dominate every path today. Positions are computed once per end and carried, so sorting and sweeping do not touch a calendar. Each phase runs benchee against the oracle corpus and the budget is "no slower than 2.0 on the plain forms, no more than twice as slow anywhere".

* **Semantics that move.** Decisions 1, 2, 3 and 13 change answers the guides document. The golden files mark each affected cell with the decision that changed it, so a diff is explained by number. The migration guide is written from those marks.

* **Coverage of the long tail.** ISO 8601-2's shapes are many and the matrix lists them. The matrix's "total" check (every function, every shape, an answer or a named error) is the first test every phase runs, so a shape the new code does not handle is a visible named error from day one rather than a crash found later.

* **Calendrical coupling.** Phase 0 lands the three additions and two signature changes in Calendrical first, behind the law test, so Tempo never waits on it mid-phase. The adapter means a calendar that lacks a callback fails at `Tempo.Calendar.calendar?/1`, by name, when it is given.

### 11.4 What done looks like

The redesign reads and writes every text the current library does, answers every cell of the operation matrix with an answer or a named error, agrees with 2.0 on every golden file except where section 10 decided otherwise, passes the laws of 8.4 against every Calendrical calendar, holds every line budget of 5.3, and has one implementation of each concept in section 2.2.

## Appendix A. Where today's lines go

| Today | Lines | Becomes |
|---|---|---|
| `tempo.ex` | 17,778 | `Tempo` (3,000) over the core |
| Reader stack (15 files) | 11,634 | `Reader`, `Writer`, `Validate` (2,900) and `guides/iso8601-grammar.md` |
| Selection and RRULE (7 files) | 11,271 | `Select` (400) and the adapters (2,000) |
| Comparison and Allen (5 files) | 6,861 | `Scale` (400), `Allen` (400) |
| Enumeration (11 files) | 5,897 | `Expand` (600), `Walk` (300), `Spans` (500) |
| Arithmetic (3 files) | 5,040 | `Shift` (500), `Duration` (300) |
| Set operations (8 files) | 4,558 | `Algebra` (300), `IntervalSet` (300) |
| Networks (9 files) | 4,462 | `tempo_network` |
| Text (4 files) | 7,375 | about 2,500 |
| Interop and exceptions (34 files) | 4,290 | about 1,500 |
| **Total** | **82,875** | **about 15,000** |

## 12. Phase 0, as built (2026-10-13)

On the `redesign` branch, from `07f96f3`.

* **The golden files.** `Tempo.Golden` (`test/support/golden.ex`) runs every entry of the matrix's corpus (`Tempo.Matrix.Corpus.entries/0`: the written core, extended and open classes, every generated shape and every generated selection) through forty-eight one-value operations in six groups (read, convert, walk, measure, parts, arithmetic, format), six selectors over the core periods, and twenty-six two-value operations in two groups (compare, combine) against the corpus's partners (every partner in both orders for a core value, one partner for a generated one), and writes one gzipped JSON Lines file per group under `test/golden/`: 152,274 cells, 1.1 MB. Each cell carries its operation, input text, calendar, argument, the tags `written_end` and `plural` of section 11.1, and the answer as data (ISO 8601 text, a list of texts, a plain value, `{"error", "reason"}`, `{"raised"}` or `{"timeout"}`). `mix test --include golden` compares the library with the files (`test/tempo/golden_test.exs`, 14 seconds); `GOLDEN=write` rewrites them. Two consecutive runs agree cell for cell. The matrix's own consistency and reference checks are not duplicated here; they are ported as they stand in phase 3.

* **The grammar.** `guides/iso8601-grammar.md`: the ABNF of ISO 8601-1 §5, ISO 8601-2 §4 to §13 and RFC 9557 §4.1, each production with its clause, Tempo's extensions in a marked section, the reading rules for the basic format's digit runs, and the test plan of section 7.6. Listed under Reference in the docs. The precedence duration of ISO 8601-2 §11.3.3 and the `A` season designator are recorded as not read.

* **The standards.** `standards/iso8601/` holds the two ISO PDFs (moved from `iso8601/`; git-ignored as before) and `standards/rfc/` the texts of RFCs 3339, 5234, 5545, 7529, 8984 and 9557, with `standards/README.md` saying what each is for. `CLAUDE.md` pointed at `papers/iso8601_specs/`, which did not exist, and at the IXDTF draft; both now point here, and the library's and guides' citations of the draft name RFC 9557.

* **Calendrical.** The additions of 8.5 and the law test of 8.4 are being made in `~/Development/localize/calendrical` (uncommitted; see the session's report for what the laws found).

* **Decision 14** was taken by the user after the review in section 4.2; the golden files' `written_end` tag marks the 22 corpus texts whose last end is written to a calendar unit, and the 8,818 cells on them, that the decision changes. Shaped values at an interval's ends are in the matrix's exhaustive corpus, which the golden files do not yet include; phase 2 adds them.

## 13. Phase 1, as built (2026-10-13)

* **The border.** `Tempo.Calendar` (`lib/tempo/core/calendar.ex`) is the adapter of section 5.4: one map, `%{Calendar.ISO => Localize.Calendar.ISO}` (configurable as `:calendar_implementations`), one private `impl/1`, and the questions of section 8.3 as functions that take the calendar first. Answers are day numbers, `{year, month, day}` tuples, half-open spans of days and labels, never a date of the answering module, so a value's calendar is what the caller gave throughout and nothing is rewritten at the border. `first_day/2` and `span_of/2` derive a week date's day and a day of the year from the week's and the year's spans on the day scale, which `date_from_week_date/3` and `date_from_day_of_year/2` answered before. `calendar?/1` accepts the implementations' keys and any module that declares Calendrical's behaviour.

* **The contract is complete on both sides.** The user ruled on 2026-10-13 that `Localize.Calendar.ISO` fully complies with the `Calendar` and `Calendrical` behaviours: the five callbacks of 8.5 are now required in Calendrical (no `@optional_callbacks` for them) and `Localize.Calendar.ISO` answers them (`weeks_of_month/2`, `traditional_month/2`, `month_from_traditional/2`, `months_in_year_bounds/0`, `days_in_month_bounds/1`, about forty lines, each a one-line fact of the Gregorian calendar or a map over its existing `month_week/3`). It answers all 52 required Calendrical callbacks. Both changes are uncommitted in `~/Development/localize/localize` and `~/Development/localize/calendrical`; this branch reads both as path dependencies until they are pushed, when `mix.exs` returns to the pinned GitHub dependencies.

* **The laws.** Calendrical carries `Calendrical.Laws` and `test/calendrical/laws_test.exs` (300 tests over 30 calendars). Tempo holds the same laws through the adapter in `test/tempo/core/calendar_test.exs` for `Calendar.ISO` and the 22 calendars of the census: round trip and order on the day scale, months tiling the year by the walk of section 6.5, a day in the week its `week_of_year/3` names, the weekday cycling over seven days, errors for periods a calendar lacks, and the weeks of a month contiguous and holding its middle (TR35 lets a month's first or last day fall in no week of it, so "cover" was the wrong law and is corrected here). One finding for the user from Calendrical's run: law 6 as written ("a value within the fewest exists in every year") does not hold for `Reform.England`, whose 1751 lacks months 1 and 2 while `months_in_year_bounds/0` is `{10, 13}`; the law conflates a count with a numbering and needs rewording to "the fewest and the most a year counts", which the bounds callbacks already answer.

* **Units, zones and positions.** `Tempo.Unit` (section 6.1, with the cycle chains and minima a value with no year runs through), `Tempo.Zone` (section 6.4, over the existing `Tempo.TimeZoneDatabase` reads: the offsets a wall reading has, one, two or a gap's before-and-after; the offset at a UTC tick; a value placed by its shift, else the first offset, else the clock before a change) and `Tempo.Scale` (section 6.3: frames; the extent of concrete units as ticks on the UTC or floating line, a calendar-resolution end read on its own clock and a clock-resolution end one unit of elapsed time on; cycle positions as tuples). `test/tempo/core/scale_test.exs` holds the start of every concrete anchored corpus value to the second `Tempo.Compare.to_utc_seconds/1` places it at, and the end to the end `Tempo.to_interval/1` writes, through the whole corpus; the four location-independent seasons are the only values skipped, having no dates.

* **Not yet.** `Tempo.Duration` keeps its 2.0 struct until phase 2 renames `time` to `units` with the one struct; `Tempo.Limit` stays as it is. `Tempo.Zone.changes/3` (the clock's changes in a range, for the walk) waits for phase 3.

## 14. Phase 2, as built (2026-10-13)

* **The one struct.** `%Tempo{form, calendar, zone, shift, qualifications, metadata}` (`lib/tempo.ex`) with the six forms of section 5.1, and `%Tempo.Duration{units}` as the one companion. The 2.0 `lib/` and `test/` trees are in `attic/` for reference until phase 7 and are not compiled.

* **The reader.** `Tempo.Reader` and its five parts (`Reader.Number`, `.Value`, `.Implied`, `.Duration`, `.Selection`, `.Suffix`; 1,900 lines) read the grammar of `guides/iso8601-grammar.md` one function per production. A text is split at its structural places first (the RFC 9557 suffix, a leading `R`, the `/` of an interval outside braces, the braces of a set), the explicit form is tried before the implied, and where both read a prefix the one that uses the text up wins, so `2026W25` is a year and a week and `0934,9` a time. What is written is what is held: a week date, an ordinal date, a season, a group, a count from the end, a set `{6,7}` and a century stay as written, where 2.0 resolved each to a Gregorian date, a range or a group. An abbreviated end inherits the start's units down the chain of years, months, days and the clock up to the unit it begins with (`Tempo.Unit.inherited/2`, with `follows?/2` saying which unit may follow which), and inherits the start's qualification marks with them. A zero shift in any spelling is `[hour: 0]`, written `Z`. The `u-ca` identifier is resolved through `Tempo.Calendar.from_type/1`, which knows CLDR's names and Calendrical's own (`iso-week`, `julian`), and a zone name is checked against the database as it is read.

* **The validator.** `Tempo.Validate` checks what the reader builds once: every whole number and every member and range end of a set against the bounds the calendar gives it through the adapter (`months_in_year/2`, `days_in_month/3`, `weeks_in_year/2`, `days_in_year/2`, `days_in_week/1`, and the `_bounds` callbacks where the year or month is not a number), hour 0 to 23 and second 0 to 59 as the grammar guide says, a shift below a day, and an interval's two ends in order where both have a place on the scale (`Tempo.Scale.extent/4`) or are two seasons of one numbering. A mask, `X*`, a group and a selection are shapes and have no number to check.

* **The writer.** `Tempo.Writer` writes the explicit form of ISO 8601-2 for every expression, as 2.0 did: `2026Y6M15DT10H30M`, `Z2H0M`, qualifiers in their three placements, `L…N`, `R`, sets with `^` and a filter letter, a range member as `2020Y..2022Y`, and one suffix after the whole expression. An end is abbreviated along the child chain only, when the two ends agree on their shift and their marks and go on in the same unit after what they share (`2026Y6M15DT10H/16D`, but `2026Y25W/2026Y7M1D`), which is what 2.0 did and what the reader gives back. A calendar is written by `Tempo.Calendar.identifier/1`; one with no name is a `Tempo.Iso8601EncodeError`.

* **The public API.** `Tempo.from_iso8601/2` (a calendar or options as the second argument), `from_iso8601!/2`, `to_iso8601/1`, `to_iso8601!/1`, `new/1` (units in any order, ordered by `Tempo.Unit.ordered/1`, with `:calendar`, `:zone`, `:shift`, `:metadata`), `new!/1`; `Tempo.Interval.new/1,2,3`, `new!/1`, `from/1`, `to/1`, `endpoints/1`; `Tempo.IntervalSet.new/2`, `members/1`, `count/1`, `first/1`, `last/1`; `Tempo.Duration.new/1`, `new!/1`; `Tempo.Sigils.sigil_o` in value context (read at compile time) and match context (a prefix pattern on a value's units, exact on the other forms, no other field constrained). `Tempo.Unit` and `Tempo.Zone` are public, since their types are in the public signatures. Every function carries the documented examples and the doctests run.

* **The tests.** 255 tests pass: 54 doctests; the phase 1 core tests, with the scale test now asserting that every plain anchored corpus value has an extent (the 2.0 oracle it compared seconds with is gone); the EDTF validation corpus, every level 0, 1 and 2 date and interval read and round-tripped and every invalid text refused but for seven that ISO 8601 or RFC 3339 read (named in the test); the three data files of ijmacd's RFC 3339/ISO 8601 table, every text read and round-tripped but for the underscore separator, which Tempo does not read; and the grammar's property tests (`test/support/grammar/`: a generator of 37 production families and a mutator), 925 generated texts read and round-tripped, every broken text refused, every varied text answered without a raise. The golden `read` group (`test/golden_test.exs`, `mix test --include golden`) answers 1,002 of 1,206 cells as 2.0 did; the 204 that differ each read back as the same value as the input (the classifier's test) and are grouped by what is kept: counts from the end 92, sets as written 42, groups 19, weeks and ordinal dates 18, a time under a period 13, weeks of another calendar 11 (decision 13), seasons 3, centuries and decades 3, a range of values 1, and 2 texts 2.0 refused that are now read (`2GT6HU30M`, a clock group with no `T`). None differs with no decision to account for it.

* **For the user, from this phase.** (1) The as-written forms above are the canonical text now: `2026Y6M-1D` is written back as itself where 2.0 wrote `2026Y6M30D`; `Tempo.at_resolution/2` or a phase 3 `resolve` is where a caller asks for the resolved form. (2) `2026YT17H` and `2026-06T17` are kept with their gap, where 2.0 filled `1M1D`; what a time under a period means (the hour of each day, or of the first) is a phase 3 decision and the grammar guide lists the form as Tempo's own. (3) ISO 8601-1:2019 §5.3.2 refuses `24:00`, so `T24:00` is a `Tempo.InvalidDateError`; 2.0 read it. (4) `Y` prefixes a year of more than four digits or one with an exponent, `+2006` is refused as an expanded year of too few digits and `-0000` as no year, all per EDTF's corpus and ISO 8601-1 §5.2.2.3. (5) RFC 3339's space, lower-case `t` and `z`, and ISO 8601's Unicode hyphen and minus are read as the ASCII forms; the underscore separator ijmacd's table lists is not. (6) `Calendrical.ISOWeek` has no CLDR type; its values are written `2026Y25W3K[u-ca=iso-week]` by Calendrical's own name for it, where 2.0 converted them to a date of its months. (7) The six gates pass on the mise toolchain; Dialyzer's one earlier finding (a spec that promised an `:error` no clause returned) is fixed.

* **Not yet.** `Tempo.Scale.extent/4` places plain values only; a count from the end, a group, a margin, a century and a decade wait for phase 3's expansion, which is why `Tempo.Validate` orders an interval's ends only where both are plain. `Tempo.Limit` is not written. Interval sets of two calendars are refused rather than converted (`to_calendar/2` is phase 4). The `w` designator is not read (decision 13). The golden groups other than `read` run as their phases land.

## 15. Phase 3, as built (2026-10-13)

* **The engine.** `Tempo.Expand` (`lib/tempo/core/expand.ex`, 800 lines) is the one engine of section 6.5: the children a unit takes under a concrete prefix, found by walking the prefix's span on the day scale period by period for a calendar unit, read from each day for a label, stepped on the tick scale and shown through the zone for a clock unit (a day in Paris has 23 or 25 hours with nothing done by hand), and counted from the calendar's bounds for a value with no year; what each held shape selects (a number, a count from the end, a set and its ranges, a mask with a leading minus counting from the end, `:any`, the nth group of a size); the lazy cartesian expansion of a value's units with the gaps between them filled by `:any`; and the extent of any concrete prefix, a count from the end, a group, a century, a quarter or an annotated year resolved to the plain units the calendar gives it before `Tempo.Scale` places it. Units after a group count within it as ISO 8601-2 §5.4.2 has them, a calendar unit from one and a clock unit from zero, and a label keeps its value, so `2026Y2G4WU3K` is each Wednesday of the group. `Tempo.Walk` (section 6.6) steps a span at a unit, on the day scale through the calendar's periods or on the tick scale through the zone, and on the day cycle through midnight. `Tempo.Spans` (section 7.1) gives every expression its spans: a value as `[v, next(v))`, a written span under law 9 with its duration end made a value at the finer of the start's and the duration's resolution and its open end placed by a window, a recurrence as its first span moved n cadences for each n with a duration end measured from each occurrence's own start, a set as its members' spans; and the children law 6 names, the members of a plural expression, and a walk at any unit.

* **Positions on a cycle are ticks.** A value with no year lies on the cycle of its coarsest unit, and its position is ticks from the cycle's start on the longest cycle the calendar counts (`Tempo.Scale.cycle_position/2`: the months before June have 152 days at most, so `6M15D` begins on day 166), where phase 1 had a tuple of the units. Two positions on one cycle compare as numbers, an end not after its start runs on through the cycle's end (`T22H/T2H` is 22, 23, 0 and 1; `12M/2M` December, January and February), a group on a cycle has a span, and the census's own cycle reckoning agrees to the microsecond. `Tempo.Scale.cycle_units/4` reads a position back into units. The week cycle's length is 53 weeks and the day-of-year cycle's the longest year, Tempo's own numbers, flagged below.

* **Enumerable and the public functions.** `Enum` over a `%Tempo{}` yields a singular expression's children, the values one unit below its resolution (the finer of its ends' for a written span, the duration's for a duration end, a group's unit for a group, a second's tenths), and a plural expression's members (law 6); the walk is lazy and stops with a `Tempo.ConversionError` after `Tempo.Limit.values/0` values. `Tempo.to_interval/2` answers a singular expression's one span or an `{:all, …}` of a plural one's, bounded by `Tempo.Limit` and by `:within` for a recurrence with no count; `Tempo.members/2` the members; `Tempo.walk/3` an expression at a unit. `:within` places a value with no year on each period of its window (`T10H` within June is thirty hours) and bounds an open end or an endless recurrence. `Tempo.Limit` and `Tempo.ConversionError` (the merged `:bare_duration`, `:one_of`, `:needs_a_year`, `:unbounded`, `:open`, `:too_many_values`, `:season`, `:selection`, `:exclusion`, `:repeat_rule`, `:conditions`, `:no_such_value` reasons of decision 12) are new.

* **The oracle.** The golden `walk` and `convert` groups now run beside `read` (`mix test --include golden`): 2,787 of their cells differ from 2.0 and every one is accounted for by a decision, classified in `test/support/golden.ex` by what changed: members where 2.0 walked into them (1), a date end read through (14), the merged errors (12), a value placed by its window, a value as its own span, members kept apart where 2.0 coalesced a mask into one span, the order of a cycle recurrence's members, and the forms kept as written; the cells of seasons, selections and repeat rules are marked pending their phases. The calendar census is the phase's own oracle (`test/tempo/census_test.exs`, 81 tests over 27 calendars): every full form's extent and walk, every value with no year, and every shape, held to the calendar's own counts; the census's two interval shapes were moved to law 9, its mask and unspecified-unit shapes to members, its gap forms removed as a decision below, and its reckoning of a reform calendar with no year taught to read the bounds callbacks of the phase 1 contract (`Calendrical.Reform.Sweden` counts twelve months in every year though `months_in_year/0` cannot say). The weekday within a week is the nth of the week's own days, whatever day the calendar's week begins on, as the census and `Tempo.Calendar.first_day/2` now agree for `Calendrical.NRF`. 350 tests pass and the six gates are clean on the mise toolchain.

* **For the user, from this phase.** (1) `Tempo.to_interval/2` of a plural expression is a set of its members' spans and never coalesces them: `2026Y6M1XD` is ten day spans where 2.0 wrote `2026Y6M10D/20D`; `Tempo.IntervalSet.coalesce/1` (phase 4) merges them. (2) A gap between a value's units is every value of the units left out: `2026YT17H` is each day's seventeenth hour (365 members) and `2026Y15D` the fifteenth of each month, where 2.0 filled the gap with the first day; the grammar guide lists the form as Tempo's own and the census's gap forms were removed on this reading. (3) A day straight after a year (`2026Y3XD`) follows from (2), the 30th to the 39th of each month, where 2.0 read it as a day of the year; write `O` for the day of the year. (4) A year's significant digits or margin name a range: `1950S2Y6M` is June of each year 1900 to 1999 and `2018±2Y` the years 2016 to 2020, where 2.0 walked 2018 alone. (5) `X*Y6M` is read as `6M`, a value on the cycle of the year, as 2.0 read it. (6) A written clock end of a span on the day cycle may be `T24H`, the one place 24:00 is read, since the cycle has no next day; `Tempo.Validate` allows it there only. (7) A cycle recurrence is not placed by `:within` (`R3/T22H/PT1H` within 2026 is still the three cycle spans), where 2.0 placed its occurrences on each day of the window. (8) `Tempo.Scale.cycle_length/2` takes a week cycle as 53 weeks and a day-of-year cycle as the longest year, numbers Tempo holds rather than asks; a calendar whose weeks or days of the year exceed them would need a `weeks_in_year_bounds/0` from Calendrical. (9) Seasons still have no dates: `2026-25` is a `Tempo.ConversionError` with `:season` until Calendrical answers a season's span, as the phase 2 report asked. (10) A clock walk shows a fold's two hours as two equal values, not as two values with their offsets as section 6.6 described; the offset is a phase 4 or 7 question of what a yielded value carries.

* **Not yet.** Selections (`:selection`), repeat rules, exclusions and `:when` conditions are named errors until phase 6. `Enumerable.member?/2` and `slice/1` fall back to the walk until phase 4 gives positions to compare. Interval sets of two calendars are refused until `to_calendar/2` (phase 4). The golden `measure`, `parts`, `arithmetic`, `format`, `select`, `compare` and `combine` groups run with their phases.

## 16. Phase 4, as built (2026-10-13)

* **Allen's relations.** `Tempo.Allen` (`lib/tempo/core/allen.ex`, with the classifier apart in `Tempo.Allen.Classifier` so that the module can derive from it) answers the relation of two spans from four comparisons, their inverses, and their composition from a table derived when the module compiles by placing three spans every way on a short line, which gives the 169 cells and cannot disagree with the classifier. The thirteen predicates and the everyday predicate sets (`before`, `after`, `adjacent`, `within`, `contains`, `disjoint`, `overlaps`, `equal`) are one table. `test/tempo/allen_test.exs` holds the axioms: exhaustiveness, self-equality, the inverse law, composition with `equals` as identity, and that `Tempo`'s everyday predicates of two single spans are the relation sets.

* **One sweep.** `Tempo.Algebra` (section 7.2) reads an operand as its spans, each placed on the frame as two positions, requires two operands on one frame (law 4: a `Tempo.FrameError` names a zoned and a floating one, one with a year and one without and no window, or two cycles), places a value with no year on each period of the `:within` window, bounds a recurrence with no end by the window or by the other operand's whole stretch, and cuts a cycle span that runs through the cycle's end into two for the sweep and joins them after. Every instant-level operation is the one sweep with a different question of how many members of each side cover a point, every edge at a position applied before the point after it is judged; a result's ends are operands' ends and are written as the operand wrote them, at its resolution, in the first operand's calendar and zone (`Tempo.Spans.at_position/5`: an end of another calendar is written to the day, one in a named zone as that zone's wall reading). The member-preserving companions keep members whole, one entry per cut member, converted to the result's calendar. The eight predicates are defined on covered time and take plural operands. The operations are held to the attic's integer model (`Tempo.Matrix.Sets`, ported) over every pair of sets of up to two members between four points and over generated sets of up to four members between nine, and the laws of the guide's section 4 (commutativity, associativity, `a − a = ∅`, De Morgan under a window) are tested on covered time.

* **The public surface.** `Tempo.union/3` (members whole, in order of start), `intersection/3`, `difference/3`, `symmetric_difference/3` (each with `:within` and `:metadata`, the latter `:first`, `:second`, `:merge` or a function), `complement/2` (`:within` required), `members_overlapping/3`, `members_outside/3`, `members_in_exactly_one/3`; `relation/2` for two single spans; `compare/3` by start then end, making `Tempo` a sorter; the eight predicates; `certainty/3`, `certainly?/3` and `possibly?/3` over the readings of uncertain operands (decision 5: the members of a one-of set, each placing of a year with a margin, each value a mask allows, `Tempo.Spans.readings/1`), with the pairings judged bounded by `Tempo.Limit`; `to_calendar/2` (a date keeps its clock, a month or a year becomes the dates it covers), `in_zone/2`, `shift_zone/2` (a value stays a value where the result is one unit of its own resolution, else a span written to the minute: a Paris hour is a New York hour, half past the hour in Kolkata is a span), `at/2` and `on/2` (the value with a year keeps it, the other supplies the finer units whole; an interval is placed end by end); `Enumerable.member?/2` as cover; `Tempo.IntervalSet.coalesce/2`, `covered/2` (with `:at_least`), `covered?/2`, `relation_matrix/2`, `filter/2`, `map/2`, `walk/1`, `from_stream/2`. The reader reads `{}`, the empty set the operations leave.

* **The oracle.** The golden `compare` and `combine` groups run beside `read`, `walk` and `convert`: 53,280 compare cells of which 26,640 differ, and 35,520 combine cells of which 24,970 differ, every difference accounted for by a decision (most by law 9's written ends, canonical form, named errors, and the covering of plural operands). Every differing cell is accounted for by a decision; the rules are in `test/support/golden.ex`. The suite is 421 tests; the six gates pass on the mise toolchain.

* **For the user, from this phase.** (1) **Membership is cover** (law 1): `~o"2026-06-15" in ~o"2026"` is true, where 2.0 asked whether the value was one of the children walked (`2026-06-15 in 2026` was false, `2026 in 2026` false too). (2) **The predicates answer for plural and wrapped operands**: `before?`, `within?` and the rest take a set, a recurrence or `T22H/T2H` on their covered time, where 2.0 raised; `relation/2` alone still wants two single spans and refuses a mask, where 2.0 read the mask as its whole span. (3) **Instant-level results are in canonical form**: an intersection or difference merges members that meet, so `R3/2026-06-01/P1D ∩ itself` is one three-day span where 2.0 kept three; `union/3` keeps members whole, as the guide says. (4) **`compare/3` orders by start, then by end**, for values as for intervals: `2026-W25` is after `2026-06-15` though they begin together, where 2.0 called them equal. (5) **Certainty is judged over readings**: `2026Y6MX*D` possibly overlaps 15 June where 2.0, reading the mask as its whole span, said certainly; `202X` cannot be within a day where 2.0 said possibly. (6) **A partner written with a date end reads through it** (decision 14): `within?(June, 2026-06-01/2026-07-01)` is false, the partner running through 1 July; the golden files tag these by the partner's text. (7) **Results 2.0 could not write are written**: a Paris day less a UTC hour is `{2026Y6M15D/T12H0M, …}[Europe/Paris]`, each end in the first operand's zone. (8) **`at/2` with a label is refused** until phase 6's selection (`3K at 2025-01-01` is a `:selection` error), where 2.0 returned the date unchanged. (9) **`in_zone/2` refuses a zoned value and `shift_zone/2` a floating one** with a `Tempo.FrameError`, where 2.0 had `FloatingTempoError` and `ZonedTempoError` (decision 12). (10) **A cycle recurrence's members come in occurrence order**, `T22H/T23H, T23H/T0H, T0H/T1H`, where 2.0 sorted them by start.

* **Not yet.** `duration/1,2` and the length predicates are phase 5, with `Tempo.Shift`; `Tempo.IntervalSet.slots/3` goes with them. Selections, repeat rules, exclusions and conditions are phase 6. A fold's two hours are still two equal values in a walk.

## 17. Phase 5, as built (2026-10-13)

* **One arithmetic.** `Tempo.Shift` (`lib/tempo/core/shift.ex`) moves an expression by a duration: a value at its own resolution, extended to the duration's finest unit, by moving the position of its start (`Spans.shifted/4`: years and months through the calendar's `shift_date` with the day clamped, then weeks and days, then the clock in ticks through the zone) and writing the value back on its own axis at that position (`Shift.rewritten/3`: a week date stays a week date, an ordinal date an ordinal date, with its annotations carried). A value with no year is placed in each of 33 consecutive years of its calendar, shifted in each, and is the one answer they agree on or a `:needs_a_year` error. A value that names several is each value it names shifted and gathered back: the written shape kept where the shift passes the plural units by, every combination of unit values written as one value with lists, a mask carried written as one of its values, else a set. A span is moved end by end, and at day resolution or finer keeps its wall-clock length when the duration has a month or a year; a recurrence by its first span and its end; a set member by member. `:skipping` is the free-time walk of section 7.5 over `Algebra.aligned/3` and `Algebra.covered/3`: ticks through the gaps for a time, free day to free day for a date. `trunc/2` drops units or names the containing period (`Shift.period_units/3`), `round/2` is `trunc` plus one unit past the midpoint, `extend/2` lists `Expand.children/3`, `at_resolution/2` truncates or fills with first values, `split/1` parts date from clock.

* **Lengths and parts.** `Tempo.Measure` (`lib/tempo/core/measure.ex`) measures a singular value as one unit of its resolution, and anything else as the time it covers once (`Algebra.covered/3`) counted in the unit it is written to (`Walk.count/3`, ticks for the clock); `between/2` counts start to start; the five length predicates lay the duration from the expression's start, so a month is as long as the month it starts in. `Tempo.Parts` (`lib/tempo/core/parts.ex`) reads a unit as written, computes one the value lies within one period of through the calendar (the week of a date, the day of the month of a week date, a count from the end), and answers nil where an expression names several or none. `Tempo.Duration` gains `exact?/1`, `to_microseconds/1`, `negate/1`, `multiply/2`, `add/2`, `subtract/2`, `sum/1`, `compare/3` (a sorter; a month needs `:relative_to`) and `to_unit/3`. `Tempo.IntervalSet.slots/3` cuts each span into fixed slots at the duration's resolution; `IntervalSet.new!/2` is added.

* **The public surface.** `Tempo.shift/3` (a duration, its text or a keyword list, with `:skipping`), `trunc/2`, `round/2`, `extend/2`, `at_resolution/2`, `split/1`; `duration/1`, `duration/2`, `at_least?/2`, `at_most?/2`, `exactly?/2`, `longer_than?/2`, `shorter_than?/2`; `year/1` to `second/1`, `week/1`, `day_of_week/2`, `day_of_year/1`, `quarter_of_year/1`, `leap_year?/1`, `days_in_month/1`, `resolution/1`, `anchored?/1`, `floating?/1`, `zoned?/1`, `bounded?/1`, `empty?/1`, `qualification/1,2`, `metadata/1`, `put_metadata/2`. `extend_resolution/2` is gone (decision 8). Tests: `test/tempo/shift_test.exs`, `measure_test.exs`, `parts_test.exs`, and the doctests.

* **The oracle.** The golden `arithmetic`, `measure` and `parts` groups run beside the five of phases 2 to 4: 12,060 arithmetic cells of which 10,793 differ (5,106 only by the `{:ok, _}` tag), 6,030 measure cells of which 1,502 differ, and 18,090 parts cells of which 6,720 differ. Across all eight groups 73,412 cells differ and none is undecided. Every differing cell is accounted for by a decision; the rules are in `test/support/golden.ex`.

* **For the user, from this phase.** (1) **The arithmetic returns tagged tuples**: `shift/3`, `trunc/2`, `round/2`, `extend/2` and `at_resolution/2` return `{:ok, _}`, as every function of the redesign that can fail does; 2.0 returned the value bare. (2) **A value stays on its axis**: `2026-W25` a day on is `2026Y25W2K`, a year on is `2027Y25W` with the week clamped to the year's last, and `2026Y166O` a day on is `2026Y167O`; 2.0 wrote the answer as a month date. (3) **Sets keep their written shape and a carried mask is one of its values**: `2026Y{6,7}M{1,15}D` a day on is `2026Y{6,7}M{2,16}D`, `2026Y6M{15,30}D` a day on is the set `{2026-06-16, 2026-07-01}` of values (2.0: an interval set of their spans), and `2026Y6M1XD` a day on is `[2026Y6M11D..2026Y6M20D]`. (4) **A span keeps its wall-clock length a month or a year on only at day resolution or finer**: `2026-01/2026-03` a month on is `2026-02/2026-04`, each end moved; `2026-01-29/2026-01-31` a month on is `2026-02-28/2026-03-02`. (5) **`trunc/2` to a unit the value is not written in is the containing period, on that unit's axis**: `2026-08-16T10:00` truncated to the week is `2026-W33`, where 2.0 gave the Monday as a date; a unit finer than the value leaves it as it is, where 2.0 raised. (6) **`round/2` to a unit finer than the value is an error** (`{:finer_than_written, unit}`), and a plural value is `:several`; 2.0 rounded some spans and kept open ones. (7) **`extend/2` stops at the second**: a second's tenths are not written (2.0 wrote `45.{0..9}S`); the `unit` argument extends level by level down to a unit. (8) **A value's duration is one unit of its resolution, whatever the year**: `6M` is `P1M` where 2.0 asked for a year; anything else is measured in the unit it is written to, so `2026-06-XX` is `P30D` (2.0: `P1M`) and `2026-06-15/PT36H` is `PT36H`. A span of dates with no year is `:needs_a_year`. (9) **`duration/2` measures start to start**, unlike a written span, which runs through its last date (law 9): `2026-09-28` to `2026-11-03` is `P36D`. (10) **Parts answer only within one period**: `day_of_week(~o"2026")` is nil where 2.0 gave the year's first day's; an interval or set answers when every end or member agrees (`hour/1` of `T9H/T17H` is nil, 2.0 gave 9); a count from the end resolves (`day/1` of `2026Y6M-1D` is 30); a unit the value lies within one period of is computed (`week/1` of a date). (11) **`resolution/1` is the unit atom** as written (`:day_of_week` for a week date, `:century` for `20C`), not 2.0's `{unit, scale}` pair. (12) **`shift/3` with `:skipping` returns `{:inexact, unit}`** for a month or a year of free time, and a date steps from free day to free day.

* **Not yet.** Selections, repeat rules, exclusions and conditions are phase 6, so `shift/3` and `duration/1` refuse them with the phase-3 reasons. `Tempo.Format`, `Explain` and `Inspect` are phase 7, so the golden `split/1` cell is rendered by the harness. A traditional month or a season shifted is written as a month.

## 18. Phase 6, as built (2026-10-13)

* **One selection engine.** `Tempo.Select` (`lib/tempo/core/select.ex`, section 7.4) picks the values a selection's parts name in a period: it walks the period at the parts' container (months for days of the month and of the week, years for months, weeks and days of the year, days for the clock), expands each container's units with the parts through `Tempo.Expand.expand/2`, keeps the values that lie within the period (or the period itself when it lies within a value: an hour of the 15th asked for the 15th), filters by a year rule, sorts, and applies the positions (`I`) to the whole period's candidates. A nested selection with a window (`LL3K4IN/P5DN`) opens a span from each value it picks and the parts after it select within each; an event (`(easter)e`) is asked of `Tempo.Event` for each year the period runs through. `Select.select/3` applies a selector to each span of a base: a value with no year (its units are the parts), a span with no year (placed in each period it begins in), a recurrence, a `Tempo.Workdays`, a list of days or of selectors, or a function of the period.

* **Selections, rules, domains and exclusions in `Tempo.Spans`.** A value holding a selection (`2026Y6ML1K1IN`) has spans and members: the units before the selection are the period, placed by `:within` when they have no year, and the units after it apply to each value picked. A repeat rule (`R/2026-01-01/P1Y/FL12M25DN`) selects in whole periods of its cadence's unit, the first the one its start is in; with a cadence of several units (every second week) the first unit of each repeating interval is the eligible one; occurrences before the start are dropped; the start's units finer than the rule's are inherited (ISO 8601-2 §13.6.3); a count counts the occurrences selected. A domain (`R/{2020Y..2024Y}/…`) gives its members as the periods and bounds the recurrence; a domain filter (`e`, `o`, `l`, `c`) keeps the years it names; an exclusion (`^2022Y`) removes the spans that lie within it. A recurrence may be bounded by an until value written after its interval (`R/2026-01-01/P1D/2026-01-05`, Tempo's own, RFC 5545's `UNTIL`), which the reader and writer now carry. With no end of its own a sequence within a window is its occurrences that overlap the window.

* **The vocabularies lower to one rule.** `Tempo.RRule` reads an RFC 5545 rule into a map of its parts, takes from the start what the rule leaves to `DTSTART` (§3.3.10: the weekday of a weekly rule, the day of a monthly one, the month and day of a yearly one, the hour of a daily one), and lowers it to a `%Tempo{}` recurrence whose rule is selection parts (`from_rule/2`); `to_string/1` writes one back. `Tempo.Cron` builds the same map from five to seven fields and the aliases, and `Tempo.ICal` and `Tempo.JSCalendar` from their parsed structs, so every vocabulary's occurrences come from `Tempo.Spans`. `Tempo.Occurrences` is the one event engine the two calendar formats share: a start, a length, rules, extra dates, excluded dates and rules. `Tempo.ICal.available/2` reads RFC 7953 availability by priority with the set operations. `Tempo.RecurrenceSet` is a constructor of the `:all` form; `keep_when/2` and `move_when/2` build members of the `:when` form that `Tempo.Conditions` judges against the other members' spans. `Tempo.Event` and `Tempo.Event.Resolver` are ported, every computation Calendrical's or Astro's.

* **Workdays, and Elixir's own types.** `Tempo.Workdays` holds a territory's weekdays and weekend (CLDR through Localize) and its days off, and `Tempo.workdays/2`, `weekends/1`, `workday?/2`, `weekend?/2`, `add_workdays/3`, `next_workday/2`, `previous_workday/2`, `nearest_workday/2`, `roll_to_workday/3` and `count_workdays/2` are short bodies over it (decision 9). `Tempo.Interop` converts to and from `Date`, `Time`, `NaiveDateTime`, `DateTime`, `Date.Range` and Elixir's `Duration` (`from_elixir/2`, `from_date/1` and its kin, `to_elixir/1`, `to_date/1`, `to_time/1`, `to_naive_datetime/1`, `to_datetime/1`), and `Tempo.now/1`, `utc_now/0`, `today/1` and `utc_today/0` read the `Tempo.Clock`. `Tempo.to_interval!/2` is added.

* **The oracle.** The golden `select` group runs beside the eight of earlier phases: 7,236 select cells of which 678 differ. Across the nine groups 70,091 cells differ and none is undecided (fewer than after phase 5, selections and repeat rules now being answered). Tests: `test/tempo/select_test.exs`, `rrule_test.exs` (the examples of RFC 5545 §3.8.5.3 with the dates the RFC lists, and cron), `calendars_test.exs`, and the doctests of every new module.

* **For the user, from this phase.** (1) **A selector's parts are selected in each period they count in**: `select(~o"2026", ~o"15D")` is the fifteenth of each month of 2026, and `select(~o"2026", ~o"T10:30")` half past ten on each day, where 2.0 gave the first only. (2) **A position counts in the period**: `select(~o"2026-06-01/P1M", ~o"L5K-1IN")` is the last Friday of the span, where 2.0 listed every Friday. (3) **A list of integers selects days of the month in every base**, where 2.0 selected the base's next unit (hours of a day, seconds of a minute); a time is selected with a time (`~o"T{1,15}H"`). (4) **Only values within a period are selected**: a workday the base holds part of is not selected, where 2.0 cut it at the base's end. (5) **`select/3` answers a set of values**, each the value picked (`2026Y6M5D`), where 2.0 answered a set of their spans; `to_interval/2` of the set gives the spans. (6) **A base with no year is an error** (`:needs_a_year`), where 2.0 answered an empty set. (7) **`workdays/2` and `weekends/1` return `{:ok, _}`**, and `select/3` takes that tuple as a selector so that `Tempo.select(x, Tempo.workdays(:US))` reads as before; `workdays/2` always answers a `Tempo.Workdays`, where 2.0 answered a bare day-of-week value when there were no days off. (8) **A repeat rule's periods are whole periods of the cadence's unit, and of several units the first is eligible** (RFC 5545's reading of `INTERVAL`); ISO 8601-2 §13.4.2 c) names the last unit, which is not implemented, and the reader still drops the written `F` eligibility. (9) **An until bound is written after the interval** (`R/start/P1D/until`), a Tempo extension to add to the grammar guide's section 5. (10) **RRULE: not read** are `WKST` other than `MO`, RFC 7529's `RSCALE` and `SKIP`, and numbered weekdays of several days in one `BYDAY` (`2MO,WE`), each a named error; 2.0 read them. A yearly rule with a numbered weekday and `BYMONTH` is lowered to a monthly cadence, so `to_string/1` writes it back as `FREQ=MONTHLY`. (11) **Cron: not read** are the Vixie `L`, `W` and `#`; a day of the month and a day of the week both restricted is a set of two recurrences. (12) **`from_elixir/2` returns `{:ok, _}`** and `from_elixir!/2`, `from_date/1` and its kin return the value; a `Date.Range` is a span written to its last day. (13) **`Tempo.RecurrenceSet` and `Tempo.Workdays` are the only struct-like modules left**: the first is a constructor of `%Tempo{}`, the second a small struct of its own. (14) **`Tempo.ICal.parse/2` raises nothing of its own but does not rescue the `ical` parser**, and an event's `DTEND` on a date is read as exclusive, as RFC 5545 has it, and written to the last day (law 9).

* **Not yet.** `Tempo.Format`, `Explain`, `Inspect` and `to_string/2` are phase 7, with the guides re-run against the new API; the guides still show 2.0's return shapes. `Tempo.map/2`, `try_map/2`, `parse/2` and `in_territory/2` of section 9.1 are not built. The network and scheduling modules go to the companion package in phase 8.


## 19. Phase 7, as built (2026-10-13)

* **Words.** `Tempo.Format` (`to_string/2`, `to_relative_string/2`, over Localize), `Tempo.Explain` (`lines/1`), `Inspect` and `String.Chars` for `%Tempo{}` and `%Tempo.Duration{}`, `Tempo.Text` (`parse/2`, `parse_duration/1`, the `:profile` option of `from_iso8601/2`), `Tempo.map/2` and `try_map/2`. An expression is inspected as the `~o` sigil that reads it, and as its struct where it has no text.

* **The guides were the test.** Every guide and livebook was rewritten for the new library and its examples are run: `test/guides_test.exs` (`mix test --only guides`) holds each page to the answers it prints. Rewriting them found more defects than the golden comparison had, because a guide asks questions the corpus does not: a rule with a count and no occurrence, a calendar with events in three zones, a holiday observed in the year before. Each was fixed in the library with a test, and the list is below. The lesson for the rest of the work is that an example a user would write is a better oracle than a cell 2.0 answered.

* **What the guides found, and is fixed.**
    * *Zones and clocks.* The clock part of a shift is elapsed time, after the date part moves the wall-clock day (section 7.5 said so; the code added both to the wall). A reading a zone's clock skips is refused when a value is read, built or placed (`Tempo.ZoneError`, `:gap`; section 6.4), and a day a zone left out is passed over by a walk, a selection, a shift and a recurrence. An hour a clock shows twice is two values in a walk, each with its offset (section 6.6). `to_datetime/1` takes the moment from a shift written beside a zone. `shift_zone/2` keeps metadata.
    * *Recurrences.* A rule's periods are stepped by number: a run of periods that select nothing is passed over to the next value the parts name, and a rule that selects nothing in a cycle of its calendar's years (`Tempo.Calendar.years_in_cycle/1`), a thousand years where there is none, or two years for a rule of times of day alone, ends. A counted rule with no occurrence looped for ever. A part coarser than the cadence keeps the periods it names (`FREQ=DAILY;BYMONTH=1`). A weekday or a day of the year beside a day or a month is a label (Friday the 13th, US election day). A rule that names a week takes its start's weekday. A `:within` window is applied after a count or an until, and a window with no zone is read on a zoned recurrence's clock. A set's dated members are kept by a window as occurrences are.
    * *Selections.* A numbered week is of the year or the month that numbers it. A nested selection is made where the parts before it say; a window of a negative length runs back from its date; what a window selects may lie outside the period that opened it. A traditional month is selected. A domain of exclusions alone takes its periods from the window; a domain that is one range is stepped from its start by the cadence, with its filter of years. An event name no resolver knows, and a week start other than Monday, are refused when read. A solar term in a Gregorian rule is reckoned by `Calendrical.Gregorian`.
    * *One expression, one calendar, one zone.* `Tempo.Algebra.gathered/2` brings a set's members to its first member's calendar and to the first named zone; `IntervalSet.new/2`, `union/3`, `Tempo.ICal` and `Tempo.JSCalendar` use it, and the two readers place an event with no zone on the calendar's clock. A value in a calendar no `u-ca` name reads back to (a fiscal calendar) has no text.
    * *Text.* An occurrence's length is the grammar's nested window (`FLL7KN/PT1HN`) and reads back. Fractional seconds of a duration are measured, read with their sign, written and carried. ISO 8601-1's alternative duration format is read. A conditional member of a recurrence set has no text, where inspecting one raised. `Tempo.RRule.to_string/1` returns an error for a recurrence RFC 5545 would read as another: one of another calendar that counts in months or years, one over a domain, one with no rule that lands on a month's last day, a part its frequency forbids.
    * *Built because section 5.3 listed it.* `Tempo.LeapSeconds`, `Tempo.Interval.spans_leap_second?/1` and `leap_seconds_spanned/1`, and `Tempo.duration(expression, leap_seconds: true)`.

* **Retired.** `guides/operation-matrix.md` and its generator: a table of which function takes which shape was an account of 2.0's irregularity, and the new library's rules are few enough to state (one struct; a plural expression is its members; no year needs placing; floating and zoned share no frame; an open end has no position). Its guarantee is kept as `test/tempo/total_test.exs` (`mix test --only total`): every operation of the golden groups on every value of the corpus answers, or returns or raises one of Tempo's own errors. Its first run found five defects, fixed. The errors it listed are a table in the glossary. `guides/chronological-networks.md` is in `attic/guides/` for the companion package.

* **Decided by the user (2026-10-13), each a change from 2.0.** (1) `FREQ=YEARLY;BYMONTHDAY=15` is the 15th of every month, RFC 5545's reading. (2) A time of day a rule takes from its start is passed over on a night the clock skips it, as one a part names is. (3) `leap_seconds:` is an option of `Tempo.duration/2`. (4) An iCalendar event with no zone is read on the clock of the calendar's first named zone. (5) A critical zone beside an offset the zone does not have is read without error. And the standing instruction: 2.0's work is adapted only where it serves correctness or conformance.

* **For the user, open.** (1) A solar term on a value with no calendar is reckoned by the Gregorian calendar, where the unreleased 2.0 changelog made it an error. (2) A selection by a list of selectors answers in the list's order, not time's. (3) `Tempo.Cron.parse/2` with no `:from` starts at the first minute of 2000; an open start would say "no start" as `Tempo.RRule.parse/2` does. (4) Seasons have no dates until Calendrical answers one. (5) `Tempo.to_elixir/1` of an interval of dates is an error, where a `Date.Range` would mirror `from_elixir/2`. (6) The version: `mix.exs` says 2.0.0-dev, this plan says 3.0, and 1.6.4 is the last published.

* **Not read or built, by decision of the grammar** (`guides/iso8601-grammar.md`, `guides/iso8601-conformance.md` section 6): the `A` season designator, the precedence form of a duration, a set within a unit of the extended format, a time shift after a set, `D` as a day of the year, the `w` calendar week and the set of fractions (both struck from the grammar guide, where phase 0 had listed them), RRULE's `WKST` other than Monday, `RSCALE` and `SKIP`, cron's `L`, `W` and `#`, sigil modifiers, the typed parsers (`:profile` replaces them), `in_territory/2`.

* **Phase 8, remaining.** The golden comparison has not been rerun since phase 6 and needs rules for every decision above. The migration guide and the changelog describe an unreleased 2.0 and are to be rewritten from 1.6.4. The companion `tempo_network` (networks, dependency scheduling, their guide). `mix.exs` (version, the `nimble_parsec` dependency, the OTP guard, module groups). The `skills/tempo` skill, which still teaches 2.0.

## 20. Phase 8, as built so far (2026-10-13)

* **The migration guide is from the published library.** `guides/migration.md` is rewritten as "Migrating from Tempo 1.6 to 3.0". The tag `v1.6.4` was extracted and compiled beside the repository, and about 280 expressions were run through both libraries, so each 1.6 answer on the page is what 1.6.4 answers and each 3.0 answer is held by the guides test. It leads with the three changes that compile and answer otherwise (a written end read through, one struct, tuples), then the table of names, then each change of meaning. `CHANGELOG.md`'s unreleased section is rewritten as 3.0 from 1.6.4, one line an entry, in place of the thousand lines that described an unreleased 2.0. `test/guides_test.exs` holds every page to its answers; the list of pages pending a rewrite is gone.

* **What measuring against 1.6.4 found, and is fixed.** Each is a defect of the new library that neither the guides nor the corpus had asked about.
    * *A recurring interval's occurrences are consecutive* (ISO 8601-1 3.1.1.11). `R3/2026-01-31/P1M` left 28 to 30 March between its second occurrence and its third, because each occurrence was its own start and a month. Both ends of an occurrence are now the first's moved by whole cadences; where the next start is no later (a day a clock left out, a cycle come round) the occurrence keeps its own length.
    * *A value with a gap is shifted member by member.* `Tempo.shift(~o"2026-06T17", day: 1)` returned the value unchanged: it was moved as its first member and written back without the day. It is now each of its thirty values moved, written in the units it was written in where that says the same (`2026-06T17` by an hour is `2026-06T18`), as one value with a list where one unit varies (`2026Y7M{1..30}DT17H`), else as a set.
    * *An option a function does not take is an error* (law 8). No function checked its options, so `bound: window` or a misspelt `withn:` was passed over and the answer was for no window. `Tempo.Options` (internal) checks every public function that takes options and names what the function does take; `:bound` is told it is `:within`.
    * *`Tempo.extend/1` of several groups* (`2026Y{1,2}G3MU`) raised `ArithmeticError`; each group is extended and they are a set.
    * *A suffix written inside an expression says where it belongs*, as the project's rule requires: the reader's error was "not an end of an interval" or "text after the value".
    * *`Tempo.bounded?/1`* raised on a set of durations and did not return on a set with no last member (a selection over a span with no end), which is not bounded.
    * *A base with no year and no end* (`6M/..`, `T10H/..`) was selected from as the year 0; it is refused with `:needs_a_year`, as a base with an end and no year is.

* **The totality check runs.** It had never finished: a selection over a span with no end is an endless lazy set, which is the design, and the golden recorder listed every member of it. The recorder now takes the first twenty (`"lazy_set"`), the run takes two minutes, and it found the `extend/1` and `bounded?/1` defects above. `mix test --only total` passes.

* **`mix.exs`.** The version is `3.0.0-dev`. The guard that refused OTP 26 is gone with the tokenizer it was for, and the README says what is tested (Elixir 1.17 and later on OTP 27 and later). `nimble_parsec`, `table` and the JSON polyfill are no longer dependencies; the description no longer promises scheduling and networks; the module groups are the modules there are. Documentation warnings were switched off for every page; they are now off for the changelog and the migration guide alone, which name what 1.6 had, and the five references the other pages made to hidden modules are reworded.

* **The skill.** `skills/tempo` teaches the new API: written ends, tuples, `certainty/3`, workdays, the companion package for scheduling and networks. Every answer in it was run.

* **For the user, open.** (1) The version: everything now says 3.0. (2) OTP 26: the guard is removed, and CI does not run it; either add it to the matrix or say 27 is required. (3) `Tempo.Unit`, `Tempo.Scale`, `Tempo.Zone` and `Tempo.Limit` are documented modules, 46 functions between them; section 5.3 calls them the engine, and the migration guide says the engine is no part of the API. (4) `merge/2`, `from_date_range/2`, `season/1` and `Tempo.Interval.through/1`, which section 9.1 and section 4.2 list, are not built: `at/2`, `from_elixir/2` and the written end cover the first, second and fourth. (5) `Tempo.explain/1` of a rule says that it selects and not what, where 1.6 said "on the 2nd Monday". (6) The project's `CLAUDE.md` still describes the `:unit` field and an exclusive written end; laws 3 and 9 replaced both. (7) About twenty functions name their options under Arguments and have no `### Options` heading.

* **The golden comparison, rerun and judged.** Its test had a one-minute limit and takes three; with the limit lifted, 71,595 cells differ from what 2.0 answered and its 55 rules account for all but two. Those two were a defect (the base with no year and no end, above), and the same defect in 22 other cells was passed by a rule, `selection_pending`, that accounts for any difference in a selection. A third of the rules are of that breadth (`named_error_12` accounts for 34,852 cells, `now_answered` for 9,784). So the comparison now passes, and says little by passing: it asks whether the library differs from 2.0 in a way nobody has excused, and nearly every way has been. **Recommended:** retire `test/golden/`, the rules of `test/support/golden.ex` and `test/golden_test.exs`, and keep the corpus and the operations, which the totality check runs. What held the library to account in phases 7 and 8 was the guides, the published 1.6.4 and the totality check. This is for the user to decide; nothing is deleted.

* **Remaining.** The companion `tempo_network`. The release itself waits on Calendrical 1.4 and Localize being published: `mix.exs` takes both from GitHub.

* **Decided by the user (2026-10-13), and done.** (1) The golden comparison is retired: `test/golden/`, its rules and its test are deleted, and the corpus's operations are `Tempo.Matrix.Cells` (`test/support/matrix/cells.ex`), which the totality check runs. (2) The version is 2.0.0, which was never released; this plan's "3.0" reads as 2.0 throughout, and the guides, livebooks, changelog and `mix.exs` say 2.0. (3) OTP 27 or later is required: the guard is back in `mix.exs`, with the reason it now has. (4) The engine is no part of the API: `Tempo.Unit`, `Tempo.Scale`, `Tempo.Zone` and `Tempo.Limit` are `@moduledoc false`, the types a caller sees (`unit`, `units`, `held`, `selection`, `zone`, `shift`) are `Tempo`'s own, and no public page refers to an engine module. (5) The project's `CLAUDE.md` describes the one struct, written ends and enumeration as the laws have them. (6) `merge/2`, `from_date_range/2`, `season/1` and `Tempo.Interval.through/1` stay unbuilt. (7) `Tempo.explain/1` says what a rule selects ("In each repeat of 1 month it selects Monday, the 2nd of them"), and every function that takes options has an `### Options` section.

## 21. After phase 8 (2026-10-13)

* **`tempo_network`.** The companion package is at `~/Development/tempo/tempo_network`: the nine modules of networks and scheduling as they were at `a43b944`, ported to the one struct and the public API, with their 225 tests, a README and the chronological-networks guide, each example run. It reaches the engine in one module, `Tempo.Network.Calendar`, which asks `Tempo.Calendar` six questions (the day number of a date and back, the months every year has, the days in a week, the years in a cycle, a year's first day); everything else is the public API. A scheduled task's interval is written as Tempo writes one (a two-day task from 1 June is `2026-06-01/2026-06-02`), which `Tempo.Network.Ends` converts from the boundaries a network counts on. Whether the one seam stays private or Tempo gives a public way to ask a calendar is open.

* **A builder** (section 9.1 had none, and the old TODO asked for one). `Tempo.every/2`, `Tempo.selection/1` and `Tempo.one_of/1` build a recurrence, a selection and a one-of set from parts, beside `Tempo.new/1`, `Tempo.Interval.new/1`, `Tempo.Duration.new/1` and `Tempo.IntervalSet.new/2`. `Tempo.Build` makes the form the reader makes and runs the same validation, and `test/tempo/build_test.exs` holds eighteen built expressions equal to what their text reads to. The library, its tests and the companion no longer write text to have it read; the project's `CLAUDE.md` makes it a rule.

* **Cron.** `Tempo.Cron` was built in phase 6 without the extensions the published library read. `L`, `LW`, `nL` and `n#k` are parts the engine already had (a day counted from the end, a numbered weekday, a position); `nW`, the weekday nearest a day, is three rules whose weekday is a label (the day itself when it is a weekday, the Friday before a Saturday, the Monday after a Sunday), returned as a set as POSIX's either-day rule is. No engine change was needed. `28W` to `31W` are refused: for a day a short month may not have, the nearest weekday depends on the month's length. The firings are held to a matcher written apart from the library.

* **RFC 5545, from the standard.** `test/support/rfc5545_examples.ex` reads the 39 recurrence examples of section 3.8.5.3 from `standards/rfc/rfc5545.txt`, and each rule's occurrences are held to the dates, times and clock (EDT or EST) the standard lists. It found three things. A numbered weekday beside times of day (`BYDAY=2MO;BYHOUR=9,10`) was lowered to a position counted among the times too, so it gave 10:00 on the first Monday; it is now a nested selection, the weekday first. A nested selection that selected nothing in a period ended the rule; it now steps to the next period. And `UNTIL` written to a time of day was read as an exclusive boundary, where the standard bounds "in an inclusive manner": an occurrence that starts on it is now the last, in every recurrence. One example's rule is misprinted in the standard (its `UNTIL` is 1 PM where its list runs to 3 PM) and is held to the rule as meant. Three rules need a week that starts on Sunday and are refused; `WKST` is otherwise read where the standard says it is not significant.

* **A set with no last member.** A selection over a span with no end is a lazy set, by design. Six operations did not return on one (`duration`, `shift`, `trunc`, `resolution`, `in_zone`, `at_least?`), `explain` raised, and `count_workdays` and `to_string` answered for its first 10,000 members. Now what reads one member at a time answers (`Enum`, `IntervalSet.first/1`, `filter/2`, `map/2`), a `:within` window bounds it, and what needs every member is refused (`:unbounded`, or `:too_many_values` where the members are walked to find out).

* **A bound is a refusal** (law 8). Eighteen places cut a sequence to `Tempo.Limit.values/0` and went on with the part, so `count_workdays` of a century counted its first 27 years. `Tempo.Limit.take/2` is the one way a bound is applied: the list, or `:too_many_values`. A count made as it is walked is not bounded.

* **The old tests, judged.** Each of the 217 test files at `a43b944` was run against the new library: 86 do not compile, 78 give no result, and of the 1,478 tests in the 52 that run, 775 pass. They are not carried over as they stand. Their cases are worth carrying where they hold the library to a standard or to a measure written apart from it, and `TODO.md` lists them in order; the cron matcher and the RFC 5545 examples are the first two, done.

* **Coverage.** The suite was 940 tests and 81% of lines, against the 90% CI requires. CI's coverage run now includes the guides and the totality check, which are tests, and the suite grew by porting: the JSCalendar and iCalendar tests with their fixtures, and new tests for events, `explain/1`, reading text, conversions, intervals, territories and the less common written forms. It is 1,227 tests and 90.19%. Each file ported found something: a recurrence with a cadence of nothing did not return (a span or a cadence of no length is now refused); `Tempo.ICal.available/2` refused a window with no zone that `parse/2` reads on the calendar's clock; `Tempo.parse/2` did not hold a locale's words to a `:profile`. The margin is thin, and `TODO.md` lists what is still to port.

* **`TODO.md`** is rewritten for this design and tracks what is open.

