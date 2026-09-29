# TODO

Open work on Tempo. The analysis behind each item, and the record of every decision taken on the way to 1.0, is in [plans/design-notes.md](plans/design-notes.md).

## Open

* [ ] **A domain run drops an occurrence a backward window moves out of it** — `R/{2020Y..2030Y}/P1Y/FLL1M3DN/-P5DN` within 2026 misses 2026's own run from 29 December 2025, which the open-start form keeps: a run keeps the occurrences that start in it, not those its periods yield.

* [ ] **`to_interval/2` raises with an open-ended window** — `Tempo.to_interval(~o"R/../P1Y/FLL1M3DN/-P5DN", within: ~o"2026/..")` raises `UnboundedSetError` from `IntervalSet.members/1`, where `to_interval_set/2` returns the lazy set; return the set or an error.

* [ ] **Gregorian constants outside the `:within` reach** — `Network.Normalize` puts a year at 365.2425 days and a month at 30.436875 to place undated periods on one axis, and `Format` a month and a year in seconds to choose a relative-time unit. Review whether each belongs in Calendrical, as the reach did.

* [ ] **An anchored terminal window loses its selection** — `R/2026/P1Y/FLL3K4IN/P5DN` gives each year's first five days (`2026Y/1M6D`), where `R/../P1Y/FLL3K4IN/P5DN` gives the five days from the fourth Wednesday (`2026Y1M28D/2M2D`).

* [ ] **A windowed selection in a one-occurrence recurrence raises** — `R1/2026/P1Y/FLL12M19DN/P40DN` raises `FunctionClauseError` from `Calendrical.Base.Month.days_in_month(2026, nil)`, which `Tempo.RRule.Selection.expand_candidate_days/2` calls with no month; `R/../P1Y/FLL12M19DN/P40DN` works.

* [ ] **A terminal window within a value does not parse** — `2027YLL(easter)eN/-P2DN`, the two days before Easter 2027, returns a `ParseError` (":year is less than the selection min of :interval") where the recurrence form parses.

* [ ] **A week of free time under `:skipping`** — a day shifted by days steps from free day to free day (2026-09-29), but shifted by weeks it still counts free seconds and returns an instant: `P1W` from Friday 23 April 2027 is `2027Y5M5DT0H0M0S`. Decide what a week of free time from a day is, and return a day for it.

* [ ] **Livebooks install 2.0 at the release** — `getting-started`, `tempo_tour`, `scheduling-workbook` and `uncertain-dates-workbook` install `{:ex_tempo, "~> 1.6"}` and the Melbourne deck `~> 1.6.3`, while their code uses the 2.0 names: at the 2.0.0 release each installs `~> 2.0`, as `everyday-holidays` already does.

* [ ] **`to_relative_string/2` raises** — `Tempo.Format.render_relative/2` raises `UnanchoredError` for a value without a year and `IntervalEndpointsError` for an open interval, where the library returns `{:error, reason}`; its spec says it returns a string.

* [ ] **A grouped endpoint raises when compared** — a hand-built interval whose endpoint holds a group (`~o"20C"`, `~o"2022Y1M2G3DU"`) raises in `Compare.to_utc_seconds/1` when measured or compared; `to_interval/1` converts such values first, the other entry points do not.

* [ ] **`rescue` in the library** — `lib/ical.ex` (`parse/2`, `available/2`, errors from the `ical` parser), `lib/inspect.ex` (Localize's calendar encoding) and `lib/iso8601/parser.ex` rescue exceptions where the rest of Tempo passes tagged tuples.

* [ ] **A never-matching selector walks the whole horizon** — `Tempo.select/2` over an open-ended span walks a thousand years of periods before a selector that never matches ends: 30 ms of years, 0.2 s of months, about 10 s of days, minutes of hours. An index selector on a fixed-range unit could end after its first empty period, a daylight-saving gap day aside.

* [ ] **Create a glossary guide** — a guide that tables every term Tempo uses (span, window, occurrence, resolution, floating, zoned, anchored, …) and defines it, so it doubles as the reference future development checks its vocabulary against (user, 2026-09-28). The decisions in [plans/vocabulary.md](plans/vocabulary.md) are its starting point.

* [ ] **A zone on a recurrence is dropped** — `R/../P1Y/FL3M20DN[+09:00]` and a domain recurrence's `[zone]` suffix parse and vanish (the start value's suffix, `R/2026-03-20[+09:00]/P1Y`, is kept). Carry it as zoned occurrences, as the suffix means elsewhere, or refuse it.

* [ ] **§12.10 window shorter than a day** — `FL11MLL1K1IN/PT12HN1K1IN` (and `/P0DN…`) walks `[lo, lo - 1]`, the anchor and the day before, as `Date.range/2` infers for a reversed range (with a runtime deprecation warning before the day-number walk replaced it). Decide the semantics — no day, or the anchor day whose start the window contains — and test it.

* [ ] **`explain/1` words a window of hours in ISO 8601** — `Tempo.explain(~o"R/2027-01-01/P1D/FLLT22HN/PT4HN")` says "the PT4H window from at 22:00" where it means the four hours from 22:00: `window_phrase/2` in `lib/explain.ex` words only a window of days or weeks, and a time-of-day selection's noun carries its "at".

* [ ] **Week-of-month selections, and calendar-aware RRULE `BYWEEKNO`** — parse `2026Y6M2W` ("2nd week of June", a positional `W` after a month) and materialise it via `Calendrical.week_of_month/3`; and replace the hard-coded ISO week walk still used by RRULE `BYWEEKNO` with Calendrical's calendar-aware functions. Month and native week-of-year selections are done. Plan in [plans/recurrence-selection-resolution.md](plans/recurrence-selection-resolution.md).

* [ ] **`Tempo.Intervallic` protocol** — let user-defined structs such as `%Booking{check_in, check_out}` take part in Allen comparisons and set operations without being copied into `%Tempo.Interval{}`; default implementations for `Tempo.Interval`, `Tempo` and single-member `Tempo.IntervalSet`.

* [ ] **Lazy backend follow-ups** — splicing a lazy set into a busy list (needs a sorted stream merge), lazy set algebra (the research project under Deferred), and holiday generator sources. The refusal semantics must hold: an answer that needs an unbounded walk without a `:within` window refuses rather than hangs.

* [ ] **Parser cost by shape** — bare dates still pay the backtracking tax: `tokenize/1` takes ~360 µs for `2026-06-15` and ~430 µs for `20260615`, against ~40 µs for `2026Y6M15D` (measured 2026-09-24). Take a shape histogram of a real consumer's calls; if it is mostly dates, choice ordering in the single `defparsec :iso8601` entry point is the whole story. Any hand-rolled scanner must be conservative and differentially tested against the general parser.

* [ ] **A composable builder** — an API between `Tempo.new/1` (flat components) and `Tempo.from_iso8601/1` (a string) in complexity, building a value from composable sub-expressions with human names — `selection`, `recur`, windows, domains, exclusions, events — nesting freely, so programs (tempo_holidays among them) construct recurrences structurally instead of interpolating ISO 8601 strings and re-parsing them.

* [ ] **Explain weekday sets by name** — `explain/1` reads `{6..7}K` as "on a weekday [6..7]"; it should read "on a Saturday or Sunday", now that holiday recurrences carry weekday limits routinely.

* [ ] **Coverage to 90%** — the CI lint row runs plain `mix test` until coverage reaches the default 90% threshold, then takes the reference workflow's `mix test --cover`. 85.5% today (2026-09-27) with the existing `ignore_modules`; `mix test --cover` lists the modules below it.

* [ ] **Conditional first pass walks whole periods** — it widens the bound by the conditions' reach, and the walk covers every period the widened bound touches, so a ±1-day bridge crossing both year ends materialises three years: Japan's holiday set takes 55 ms a year with its bridge, 25 ms without. Widen only where a condition reaches past the bound (the bridge's days, a move's search back from the bound's start).

* [ ] **`Interval.duration/1` raises** — a multi-occurrence recurrence raises `ConversionError` and differing endpoint calendars fail an `:ok =` match; return `{:error, _}` instead. `Tempo.duration/1` returns an error for a recurrence or an unanchored interval since 2026-09-29; `Interval.duration/1,2` called directly still raise. Predicates (`anchored?/1`, the relation and certainty predicates) may raise on invalid input, as Elixir's naming conventions expect (user, 2026-09-27).

* [ ] **An impossible date's error names too little** — `Tempo.on(~o"2M29D", ~o"2027")` returns an `InvalidDateError` with only its reason ("29 is not valid. The valid values are 1..28"), naming no year, month or calendar.

* [ ] **An open-start window's error** — `within: ~o"../2027"` returns an `IntervalEndpointsError` about including an open interval in a set: correct, but it should say that a window needs a start.

* [ ] **`Schedule.task/3`'s `:within` is a pair** — it takes a `{from, to}` tuple, where every other `:within` takes a Tempo value or an interval.

* [ ] **Three §12 selection parses** — `2018Y9MTLT8H20MN3I` does not parse, `FL1KT10H0M0S1IN` misreads `0S1`, and `{1,3}K1I` merges where ISO 8601-2 §12.11.3 example 2 distributes.

* [ ] **`ClockTest` timing** — "process-local override does not leak to peer processes" failed once under load (passing in isolation and on re-runs): `assert_receive`'s default 100 ms timeout is short on a busy machine.

* [ ] **Move the Localize lock to `main`** — Localize `main` (`53519d19`) gives MF2's `:date`, `:time` and `:datetime` TR35's options, has semantic skeletons take the locale's own widths, and numbers its next release 1.4.0; Tempo locks `ff1c9b5`. Tempo `64c2e3b` passes all 4,793 tests, format, credo --strict and release docs against it (a scratch copy, 2026-09-29; dialyzer not run), so `mix deps.update localize` should be the whole change.

## In progress

* [ ] **Vocabulary for 2.0** — one meaning per word and one word per meaning across Tempo and tempo_holidays: `:within` for `:bound`, "anchor" in one sense, no public "materialise", `Tempo.Allen` beside everyday predicates, `datetime`, "workday". Every decision is taken; the tasks are in [plans/vocabulary.md](plans/vocabulary.md). Fifteen of its sixteen tasks have landed, through tempo_holidays and the real-world livebook (`livebook/everyday-holidays.livemd`, and its tempo_holidays copy); `tempo_sql`'s move to `~> 2.0` remains, once 2.0.0 is on hex.

## Deferred

* [ ] **Set algebra over open-ended windows** — a research project for later (user, 2026-09-28): how far union, intersection, difference, complement and the predicates go on the lazy sets an open-ended window gives, a test of the whole algebra. Questions in [plans/open-ended-set-algebra.md](plans/open-ended-set-algebra.md).

* [ ] **A domain gating by a window's anchor** — a domain admits the occurrences that start in its periods; date-holidays gates on the year of a window's anchor instead. They differ only when a window crosses a gated boundary year, which no tempo_holidays rule does; reviving it needs anchor tracking through `Tempo.RRule.Selection`.

## Done

* [x] **The `:within` reach steps through Calendrical** — a walk's periods and an occurrence's reach step in the recurrence's own calendar, with no Gregorian day counts; an anchored recurrence reaches past the window's end too, and a Coptic two-month rule keeps its phase. 2026-09-29.

* [x] **Seven API gaps the NSW school holidays found** — holidays in `workdays/2` (`:except`, `Tempo.Workdays`); the duration predicates and `duration/1` on sets and values; `Interval.from/1` and `to/1` on a value, and `new/1`'s `:through`; `select/2` with an ISO 8601-2 selection; `at/2` and `on/2` with an interval or a selection; `:skipping` stepping days; `RecurrenceSet.filter/2`. 2026-09-29.

* [x] **`to_iso8601/1` returns a tuple, and the span and reach defects** — `{:ok, string}` or an `Iso8601EncodeError`, with `to_iso8601!/1`; sub-second ends encode; a time-of-day selection keeps its span, in iCalendar and as a §12.10 window of hours; `:within` keeps an occurrence that runs into it under a sub-day cadence or a backward window. 2026-09-29.

* [x] **Interval/recurrence unification** — `RecurrenceSet` (the definition) and `IntervalSet` (its occurrences) stay two types, the gaps closed: opaque metadata on `%Tempo{}` (`:metadata` repurposed, `:tags` for IXDTF), nested members, a set's metadata through materialisation, the duration forms in every single-interval function. 2026-09-27.

* [x] **Conditional recurrence-set members** — `RecurrenceSet.keep_when/2` and `move_when/2`, resolved in a second pass over the widened bound; a cookbook section. 2026-09-27.

* [x] **Recurrence bounds are half-open** — a bound starting mid-period reaches every period it overlaps, and anchored, unanchored and UNTIL recurrences keep only occurrences starting in the bound. 2026-09-27.

* [x] **A non-leap-year domain filter** — `c` (common year) beside `e`/`o`/`l`, for date-holidays' `09-11 in non-leap years`: `R/..c/P1Y/FL9M11DN`. 2026-09-27.

* [x] **Six recurrence defects from the tempo_holidays gate census** — `(name)e` with a weekday limit, a year-resolution anchor and a plain-`Tempo` recurrence-set member no longer raise; a domain steps a multi-year cadence and closes an open range against the bound; a window crossing the bound's year lands in it. 2026-09-24.

* [x] **Each shared grammar prefix parsed once** — a §12.10 window parses in ~3.5 ms (was ~1.2 s), a nested window in ~60 ms (was minutes), a selection recurrence in ~0.4 ms (was ~15 ms), bare dates ~2.4× faster. 2026-09-24.

* [x] **A supplied `:bound` narrows a self-bounding recurrence domain** — `R/{2020Y..2049Y}/P1Y/…` with `bound: ~o"2029Y"` yields 2029 only (it yielded all thirty years), using the same `[bound_from, bound_to)` start rule as any unanchored recurrence; domain periods outside the bound are skipped. 2026-09-24.

* [x] **Recurrence sets** — `Tempo.RecurrenceSet`, a collection of recurrence rules that converts to one `IntervalSet` against a window and composes with a diary through set algebra. Plan in [plans/recurrence-set.md](plans/recurrence-set.md). 2026-09-23.

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
