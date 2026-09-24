# TODO

Open work on Tempo. The analysis behind each item, and the record of every
decision taken on the way to 1.0, is in
[plans/design-notes.md](plans/design-notes.md).

## Open

* [ ] **Recurrence sets** — a `%Tempo.RecurrenceSet{}` value for a collection of recurrence rules (a territory's holidays, a calendar's events) that materialises as one `IntervalSet` against a window, so it composes with a diary through set algebra (`intersection(diary, Holidays.recurrence_set(:AU))`). Completes the Interval → RecurrenceSet → IntervalSet triad and generalises `ICal.from_ical/2`. Plan in [plans/recurrence-set.md](plans/recurrence-set.md).
* [ ] **Week-of-month selections, and calendar-aware RRULE `BYWEEKNO`** — parse `2026Y6M2W` ("2nd week of June", a positional `W` after a month) and materialise it via `Calendrical.week_of_month/3`; and replace the hard-coded ISO week walk still used by RRULE `BYWEEKNO` with Calendrical's calendar-aware functions. Month and native week-of-year selections are done. Plan in [plans/recurrence-selection-resolution.md](plans/recurrence-selection-resolution.md).
* [ ] **`Tempo.Intervallic` protocol** — let user-defined structs such as `%Booking{check_in, check_out}` take part in Allen comparisons and set operations without being copied into `%Tempo.Interval{}`; default implementations for `Tempo.Interval`, `Tempo` and single-member `Tempo.IntervalSet`.
* [ ] **Lazy backend follow-ups** — splicing a lazy set into a busy list (needs a sorted stream merge), lazy set algebra (union and intersection of generators), and holiday generator sources. The refusal semantics must hold: an answer that needs an unbounded walk without a `:bound` refuses rather than hangs.
* [ ] **Parser cost by shape** — bare dates still pay the backtracking tax: `tokenize/1` takes ~360 µs for `2026-06-15` and ~430 µs for `20260615`, against ~40 µs for `2026Y6M15D` (measured 2026-09-24). Take a shape histogram of a real consumer's calls; if it is mostly dates, choice ordering in the single `defparsec :iso8601` entry point is the whole story. Any hand-rolled scanner must be conservative and differentially tested against the general parser.
* [ ] **A composable builder** — an API between `Tempo.new/1` (flat components) and `Tempo.from_iso8601/1` (a string) in complexity, building a value from composable sub-expressions with human names — `selection`, `recur`, windows, domains, exclusions, events — nesting freely, so programs (tempo_holidays among them) construct recurrences structurally instead of interpolating ISO 8601 strings and re-parsing them.
* [ ] **A non-leap-year domain filter** — a spelling beside `e`/`o`/`l` for "not a leap year" (date-holidays' `09-11 in non-leap years`, 3 rules in tempo_holidays). Awaiting the choice of spelling.
* [ ] **Explain weekday sets by name** — `explain/1` reads `{6..7}K` as "on a weekday [6..7]"; it should read "on a Saturday or Sunday", now that holiday recurrences carry weekday limits routinely.
* [ ] **Unify interval and recurrence into one concept** (research, plan, advise) — an `Interval` is a single occurrence, i.e. a count-1 recurrence, which suggests everything is a recurrence and the only value types are intervals / interval-sets, with a `Tempo` as a single expression. Research whether `%Tempo{}`, `%Tempo.Interval{}` and `%Tempo.RecurrenceSet{}` collapse cleanly, what breaks (implicit vs explicit spans, half-open convention, Allen relations, `%Date{}` interop, materialisation with/without `:bound`), and advise before any code. Plan in [plans/interval-recurrence-unification.md](plans/interval-recurrence-unification.md).

## Deferred

* [ ] **A domain gating by a window's anchor** — a domain admits the occurrences that start in its periods; date-holidays gates on the year of a window's anchor instead. They differ only when a window crosses a gated boundary year, which no tempo_holidays rule does; reviving it needs anchor tracking through `Tempo.RRule.Selection`.

## Done

* [x] **Six recurrence defects from the tempo_holidays gate census** — `(name)e` with a weekday limit, a year-resolution anchor and a plain-`Tempo` recurrence-set member no longer raise; a domain steps a multi-year cadence and closes an open range against the bound; a window crossing the bound's year lands in it. 2026-09-24.

* [x] **Each shared grammar prefix parsed once** — a §12.10 window parses in ~3.5 ms (was ~1.2 s), a nested window in ~60 ms (was minutes), a selection recurrence in ~0.4 ms (was ~15 ms), bare dates ~2.4× faster. 2026-09-24.

* [x] **A supplied `:bound` narrows a self-bounding recurrence domain** — `R/{2020Y..2049Y}/P1Y/…` with `bound: ~o"2029Y"` yields 2029 only (it yielded all thirty years), using the same `[bound_from, bound_to)` start rule as any unanchored recurrence; domain periods outside the bound are skipped. 2026-09-24.

* [x] **Consumer-extensible computed events** — `Tempo.Event.Resolver`, a behaviour registered via `config :ex_tempo, :event_resolvers`; consumer `(name)E` events resolve beside the built-ins and appear in `Tempo.Event.known/0`, unknown names yield zero occurrences. Plan in [plans/consumer-events.md](plans/consumer-events.md). 2026-09-23.

* [x] **Computed-event selections** — `(name)E`: Easter and `orthodox-easter` (Calendrical.Ecclesiastical), the equinoxes/solstices and first `new-moon` of the year (Astro), and the 24 solar terms (Calendrical, per-meridian via `Tempo.Event.date/3`). Plan in [plans/selection-extensions.md](plans/selection-extensions.md). 2026-09-22.
* [x] **ISO 8601-2 §12.10 selection with a time interval, and the `I`-as-position convergence** — windowed/nested selections (Election Day, Good Friday, the spec's worked examples) and `I` as the §12.9 position designator with `V` retired. Plan in [plans/i-position-convergence.md](plans/i-position-convergence.md). 2026-09-22.
* [x] **Materialise an unanchored recurrence against a bound alone** — a `:bound` now supplies the missing anchor, so the ISO 8601 holiday forms (`FL12M25DN`, `FL6M1K2IN`, …) project onto a year in one call at any bound resolution — year, month or day; day- and hour-resolution occurrences are correct. 2026-09-21.
* [x] **Duration parse entry point** — `Tempo.parse_duration/1` and `parse_duration!/1` over a second `defparsec :duration_only`, 17–42× faster than the general path and rejecting anything that is not a duration. 2026-09-02.
* [x] **Pluggable `IntervalSet` backends** — public `Tempo.IntervalSet.Backend` behaviour with `Backend.List`, `Backend.Tree` (balanced interval tree, ~2,900× faster stabbing on 10k members) and `Backend.Lazy` with `from_stream/2` and `Tempo.UnboundedSetError`; `Tempo.weekends/1` as an unbounded busy set. 2026-07-27.
* [x] **`Tempo.shift/3` with `skipping:`** — shifts over a busy set in gregorian UTC seconds; origin inside a busy span ejects to its edge at no cost, backward shifts are symmetric, `:year` and `:month` refuse. 2026-07-27.
* [x] **`Enum` over a recurring interval** — a bounded recurrence enumerates the sub-points of every occurrence; an unbounded one raises `UnboundedRecurrenceError`. 2026-07-15.
* [x] **What a bare un-anchored partial means** — ratified as a single abstract span on its own resolution axis; the recurring reading belongs to selections and RRULE. `:bound` day-anchoring and the certainty API hardened to match. 2026-07-15.
* [x] **`function_exported?/3` without `Code.ensure_loaded?/1`** — all 25 call sites across tempo, calendrical, localize and astro reviewed; twelve fixed. 2026-07-15.
* [x] **`Enumerable.Tempo.IntervalSet` semantics** — left as sub-point walking, with the member view as named vocabulary and a user-settable `:unit`. 2026-07-15.
* [x] **IXDTF strict mode** — `Tempo.validate_zone_offset/1` and `from_iso8601(str, strict: true)` reject an offset that disagrees with the zone; a critical zone (`[!America/New_York]`) enforces RFC 9557 §4.2 unconditionally and round-trips. 2026-07-11.
* [x] **1.0 readiness fixes** — an exponential set/group parse and an unbounded input length closed; `R10000/…/P1D` materialisation from ~6 s to ~20 ms via absolute-day arithmetic in `Tempo.Math`. 2026-07-05.
* [x] **`V` and `Q` selection designators** — ratified as permanent extensions (BYSETPOS and WKST have no ISO spelling); documented in conformance guide §5.
* [x] **Un-anchored arithmetic boundaries** — one principle, stated in `lib/math.ex` and the `Tempo.shift/2` doc: computed when invariant to the missing year, `%Tempo.RequiresAnchorError{}` otherwise, never raising.
* [x] **Selection builders consolidated** — both RRULE and cron paths build through `Tempo.RRule.Rule.to_selection/1`.
* [x] **Non-anchored time-of-day groups** — a pure time-of-day group materialises to a non-anchored interval when its carry stays within the present units; date groups still error.
* [x] **iCal zero-duration events** — punctual events materialise at `DTSTART`'s one-unit span, tagged `metadata: %{punctual: true}`, at a single construction chokepoint in `lib/ical.ex`.
* [x] **Cron AST gaps** — `W` nearest-weekday (`:bymonthday_nearest`), multi-year lists (`:byyear`), POSIX day-of-month OR day-of-week (`:bymonthday_or_byday`), and step LHS on day-of-week in cron numbering.
* [x] **Workdays and weekends** — `Tempo.weekend?/2`, `workday?/2`, `add_working_days/3`, `next_working_day/2`, `previous_working_day/2` and `working_days_in/2`, territory-aware via `Localize.Calendar.weekend/1`.
* [x] **Qualifications, explicit form and rendering** — implicit-form parsing fully §8-conformant; explicit per-component qualifiers parse; `inspect/1` and `to_iso8601/1` emit them, collapsing to the compact complete form where every component shares one qualifier.
