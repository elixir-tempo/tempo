# RFC 5545 RRULE Conformance

Tempo treats RFC 5545 RRULE as a first-class recurrence vocabulary. Every rule that [section 3.3.10 of the standard](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10) defines can be parsed into a recurring `%Tempo.Interval{}` (modelled internally by Tempo's typed RRULE AST, `%Tempo.RRule.Rule{}`), converted to a `%Tempo.IntervalSet{}` of occurrences within any window, and composed with the rest of Tempo's set algebra — `union`, `intersection`, `difference`, and friends. This guide catalogues precisely what that means, what's supported, and what isn't.

Tempo's RRULE parsing is its own implementation; it does not delegate to a third-party library for the string-to-AST step. For full iCalendar (`.ics`) files with events, RDATEs, and EXDATEs, Tempo delegates to the excellent [`ical`](https://hex.pm/packages/ical) library and converts its `%ICal.Recurrence{}` into the same Tempo AST — giving you a single conversion path regardless of whether the rule came from a hand-written string or a parsed iCalendar feed.

The reference is [RFC 5545 §3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10). A companion extension, RFC 7529, adds `RSCALE`, the calendar a rule counts in, and `SKIP`, what it does with a date that does not exist. Tempo reads both for the Gregorian calendar and reports what it does not build; a rule in another calendar is counted through the calendar of its start (see below).

## What Tempo guarantees

Given an RRULE, Tempo will:

* **Parse** the string into a recurring `%Tempo.Interval{}` via `Tempo.RRule.parse/2` — its recurrence is described by the typed `%Tempo.RRule.Rule{}` field vocabulary catalogued below.

* **Expand** that recurring interval into an explicit `%Tempo.IntervalSet{}` of occurrences via `Tempo.to_interval/2`.

* **Apply set operations**: occurrences compose with every operation (`Tempo.union/2`, `Tempo.intersection/2`, `Tempo.difference/2`, `Tempo.symmetric_difference/2`, `Tempo.complement/2`, `Tempo.members_overlapping/2`, `Tempo.members_outside/2`, `Tempo.members_in_exactly_one/2`) and with the predicates (`overlaps?/2`, `disjoint?/2`, `contains?/2`, `equal?/2`, `within?/2`).

* **Iterate** via `Enum` — `Enum.to_list/1`, `Stream.take/2`, etc. — when the rule is bounded or a `:within` window is supplied.

* **Re-encode** back to an RRULE string via `Tempo.RRule.to_string/1` for values that originated as RRULEs.

## Property-by-property support

Every property defined by RFC 5545 §3.3.10, with Tempo's handling:

| Property | Supported | AST field | Notes |
| -------- | :-------: | --------- | ----- |
| `FREQ` | ✓ | `:freq` | All seven values: `:second`, `:minute`, `:hour`, `:day`, `:week`, `:month`, `:year`. |
| `INTERVAL` | ✓ | `:interval` | Positive integer; defaults to `1`. |
| `COUNT` | ✓ | `:count` | Mutually exclusive with `UNTIL` per §3.3.10. |
| `UNTIL` | ✓ | `:until` | `%Tempo{}` endpoint. |
| `WKST` | ✓ | `:wkst` | Integer 1–7, default Monday. Affects `BYWEEKNO` calculations. |
| `BYSECOND` | ✓ | `:bysecond` | Integer list 0–60. |
| `BYMINUTE` | ✓ | `:byminute` | Integer list 0–59. |
| `BYHOUR` | ✓ | `:byhour` | Integer list 0–23. |
| `BYDAY` | ✓ | `:byday` | List of `{ordinal_or_nil, weekday_1_to_7}` tuples. Ordinals (`1MO`, `-1FR`) honoured under `FREQ=MONTHLY`/`YEARLY`; ignored as filters under other FREQs per RFC. |
| `BYMONTHDAY` | ✓ | `:bymonthday` | Integer list -31..31; negatives count from end of month (`-1` = last day). |
| `BYYEARDAY` | ✓ | `:byyearday` | Integer list -366..366. |
| `BYWEEKNO` | ✓ | `:byweekno` | Integer list -53..53; `FREQ=YEARLY` only, per RFC. |
| `BYMONTH` | ✓ | `:bymonth` | Integer list 1–12. |
| `BYSETPOS` | ✓ | `:bysetpos` | Integer list; applied **last** to pick the Nth candidate of the per-period set, per RFC. |

### BY-rule EXPAND vs LIMIT semantics

RFC 5545 defines each BY-rule as either **EXPAND** (generates additional candidates inside a period) or **LIMIT** (filters the candidate set) depending on the outer `FREQ`. Tempo implements the full table from the RFC:

* `BYMONTH` expands when `FREQ=YEARLY`; limits under finer FREQs.

* `BYMONTHDAY` expands when `FREQ=MONTHLY`/`YEARLY`; limits under finer FREQs.

* `BYYEARDAY` expands when `FREQ=YEARLY`; limits otherwise.

* `BYWEEKNO` expands when `FREQ=YEARLY`; limits otherwise. Its weeks start on `WKST`, and week 1 holds the year's fourth day, so with the default Monday they are ISO 8601's weeks, the `W` of the ISO form. A YEARLY rule with `BYWEEKNO` and no `BYYEARDAY`, `BYMONTHDAY` or `BYDAY` takes DTSTART's weekday, as ISO 8601-2 Annex C.3 reads RFC 5545: `FREQ=YEARLY;BYWEEKNO=20` from Monday 1997-05-12 is the Monday of week 20 each year.

* `BYDAY`'s role depends on `FREQ` and whether `BYWEEKNO` or `BYMONTH` is also present — Tempo follows the RFC's §3.3.10 decision table.

* `BYHOUR`/`BYMINUTE`/`BYSECOND` expand when `FREQ` is coarser than the unit; limit when finer.

* `BYSETPOS` is always applied last as a LIMIT across the candidate set.

In a `YEARLY` rule the parts that name a day hold at once, so the days selected are those that satisfy every one of them: `BYMONTH=3;BYYEARDAY=100` selects nothing, day 100 being 10 April, `BYMONTH=3,4;BYYEARDAY=80,100` is 21 March and 10 April, each once, and `BYMONTHDAY=15;BYYEARDAY=74` is 15 March in the years whose 74th day it is.

### What the writer allows a frequency

RFC 5545 §3.3.10 forbids some parts at some frequencies: `BYMONTHDAY` in a `WEEKLY` rule, `BYYEARDAY` in a `DAILY`, `WEEKLY` or `MONTHLY` one, `BYWEEKNO` in any but a `YEARLY` one, a numbered `BYDAY` outside a `MONTHLY` rule and a `YEARLY` rule with no `BYWEEKNO`, and a `BYSETPOS` with no other `BY` part. `Tempo.RRule.parse/2` reads such a rule, as many calendars write them, and `Tempo.RRule.to_string/1` does not write one: a numbered weekday is written as the weekday and its position where the number is not allowed (`FREQ=WEEKLY;BYDAY=WE;BYSETPOS=2`), and every other forbidden part is a `Tempo.ConversionError` that names the part and the frequency.

### What a rule takes from DTSTART

A rule takes from DTSTART what it does not say, as ISO 8601-2 Annex C.3 lists it: a `WEEKLY` rule with no `BYDAY` its weekday, a `MONTHLY` rule with no `BYMONTHDAY` and no `BYDAY` its day of the month, and a `YEARLY` rule its month and its day, so `FREQ=YEARLY;BYMONTHDAY=15` is the 15th of DTSTART's month. A rule read with a start states each part, as Annex C.4 has a conversion do: `FREQ=MONTHLY` from 31 January is `~o"R/2026-01-31/P1M/FL31DN"`, and `Tempo.RRule.to_string/1` writes it `FREQ=MONTHLY;BYMONTHDAY=31`, which RFC 5545 reads as the rule it was.

A rule read with no start has nothing to take a month from, and is the rule its ISO 8601 form says: `FREQ=YEARLY;BYMONTHDAY=-1` with no `:from` is `~o"R/../P1Y/FL-1DN"`, whose day with no month is a day of the year, 31 December. The writer keeps the two apart for a reader of RFC 5545: the ISO 8601 rule `~o"R/2026/P1Y/FL45DN"`, the 45th day of each year, is written `FREQ=YEARLY;BYYEARDAY=45`, and `BYMONTHDAY` is written where the rule or its start names the month.

A day so stated is passed over where a month or a year lacks it, as RFC 5545 §3.3.10 says of an instance with an invalid date: that rule lists the months of 31 days, and `FREQ=YEARLY` from 29 February the leap years. An occurrence is as long as its start is precise, a day for a date, which is the length RFC 5545 gives an event with no `DTEND`; an event's `DTEND` or `DURATION` sets it otherwise.

A time of day a rule picks that the zone's clock skips on some day is passed over there too, and is not counted, as §3.3.10 says of an instance on a nonexistent local time: `FREQ=DAILY;BYHOUR=2;BYMINUTE=30` in `America/New_York` has no occurrence on the night the clocks go from 02:00 to 03:00, and neither has a day of the month the zone left out, as Samoa left out 30 December 2011. An hour the clock skips part of is the part it shows: `FREQ=DAILY;BYHOUR=2` in `Australia/Lord_Howe` is the half hour from 02:30 to 03:00 on the morning the clocks go from 02:00 to 02:30, as the hour `T2H` is there. A time of day the rule takes from DTSTART is another matter. The same section has the computed start of an instance that does not exist read as §3.3.5 reads a date and time, with the offset before the gap, so `FREQ=DAILY` from 02:30 has its occurrence that night at 03:30.

An ISO 8601 recurrence is not a rule of RFC 5545. `~o"R/2026-01-31/P1M"` selects nothing: it is its start and n months on, 28 February and 30 April among them, each occurrence a month long. `Tempo.RRule.to_string/1` writes it as the rule that lists those days for a reader of RFC 5545, `FREQ=MONTHLY;BYMONTHDAY=-1`, the last day of each month; one from the 30th is the last of the days up to it, `BYMONTHDAY=28,29,30;BYSETPOS=-1`, and one from 29 February `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-1`. Where no one rule says it, the recurrence holding a position or several times of day already, or naming months of different lengths in a year, the writer returns a `Tempo.ConversionError`.

### RDATE and EXDATE

These are VEVENT-level properties rather than RRULE-level, but they compose with RRULE expansion through `Tempo.ICal.parse/2`:

* **`RDATE`** contributes additional occurrences beyond the RRULE expansion. Tempo implements this as a `union` of the RRULE expansion with an `%Tempo.IntervalSet{}` of the RDATEs (each RDATE carries the event's original `DTEND - DTSTART` span; metadata is preserved).

* **`EXDATE`** removes matching occurrences from the expansion. Tempo implements this as a member-filter difference — an occurrence is removed if its `.from` moment matches an EXDATE via RFC-compliant endpoint comparison.

The end-to-end formula: **`occurrences = (expand(rrule) ∪ rdates) − exdates`**.

## Calendar awareness

RFC 5545 is implicitly Gregorian. RFC 7529 defines a separate `RSCALE` part for alternative calendars; Tempo reads `RSCALE=GREGORIAN` and reports any other (`{:error, {:unsupported_rscale, name}}`). Instead, **Tempo's RRULE expansion is calendar-aware through the rule's DTSTART**. Parse a DTSTART in the Hebrew calendar (`5786-09-30[u-ca=hebrew]`) and expand an RRULE against it, and the expansion iterates in Hebrew months. The same rule string yields different occurrences depending on which calendar the DTSTART is in — which is closer to what most applications want than the RSCALE annotation dance.

Occurrence selection dispatches to the calendar module (`days_in_month/2`, `day_of_year/3`, `day_of_week/4`) and steps through Calendrical, so BYMONTH/BYMONTHDAY/BYYEARDAY respect calendar-specific month and year lengths, and BYWEEKNO numbers the weeks of the calendar's own year from `WKST`.

Writing is narrower than reading. `Tempo.RRule.to_string/1` writes a rule for an RFC 5545 reader, who counts months, years and weeks of the year in the Gregorian calendar, so a recurrence of another calendar is written only where that reader finds the same days: one that steps by weeks, days or less and selects by weekday and time of day. Its `UNTIL` is the Gregorian date its end is, and in a calendar of weeks its `WKST` is the day the calendar's weeks begin (`WKST=SU` in `Calendrical.NRF`). One that steps or selects by a month, a year, a week of the year or a day of one returns a `Tempo.ConversionError` whose `:reason` is `:not_built`, since only `RSCALE` could say which calendar counts them.

## Unbounded rules require a window

A rule with `FREQ` but no `COUNT`, no `UNTIL`, and no `:within` window is infinite — Tempo cannot list its occurrences. Attempting to do so returns:

```elixir
{:error, %Tempo.UnboundedRecurrenceError{reason: ...}}
```

The error message points callers at the `:within` option. This is a deliberate design choice (see the [scheduling guide](./scheduling.md)) — infinite recurrences are rule-shaped, not set-shaped, and Tempo refuses to silently iterate without a stop condition.

## A walk is bounded

A rule's occurrences are found by walking the periods of its frequency. A walk makes at most 10,000 periods and gives at most 10,000 occurrences at once, and a rule that has not come to its `COUNT`, its `UNTIL` or the end of its window by then returns a `Tempo.UnboundedRecurrenceError` and none of what it found, which would not be all of it.

A rule whose parts leave its occurrences far apart for its frequency is not asked of every period. Where a period selects nothing, the walk goes on from the next value named by the part that dropped it — a `BYMONTH`, `BYMONTHDAY`, `BYYEARDAY` or `BYDAY`, a `BYHOUR`, `BYMINUTE` or `BYSECOND` — so `FREQ=MINUTELY;BYHOUR=9;BYMINUTE=0;COUNT=30` is thirty mornings in a few periods a day, and `FREQ=DAILY;BYMONTH=2;BYMONTHDAY=29;BYDAY=MO` comes to each 29 February that is a Monday, decades apart. A `BYWEEKNO` is asked of each period, a week running across a month and a year.

A rule that has no occurrence has none, and returns the empty set: the 31st of April (`FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=31`), an April from a start on 31 January, the 29 February of every fourth year from 2026. A rule of years or months is told so once it has selected nothing in the periods of four hundred years, in which the Gregorian calendar comes round, and a rule of a finer frequency from the dates its parts name. One of days, hours, minutes or seconds is told so too where it steps past every value its parts name: every seventh day from a Tuesday is a Tuesday, so `FREQ=DAILY;INTERVAL=7;BYDAY=MO` from one has no occurrence, and nor has `FREQ=HOURLY;INTERVAL=12;BYHOUR=9` from 10:00. A zone's clock changes the hour a step comes to, so a rule in a zone is told so from its steps only where it steps by days: a stop there is on the day stepped to or, where the clock skips its time until past midnight, the day after, so every seventh day from a Tuesday at 10:00 in any zone has no Monday. A rule in another calendar is told so from its steps alone, and either is otherwise cut short as any long walk is.

## Not supported

A small list of features outside Tempo's current RRULE scope:

* **`EXRULE`** — deprecated by RFC 5545 Errata in favour of EXDATE. Not exposed by the underlying `ical` library and not implemented in Tempo. EXDATE covers every use case.

* **Duration-only VEVENT** (DURATION without DTEND) — not yet supported in `Tempo.ICal.parse/2`. The iCal library parses it; Tempo's conversion doesn't handle it. Raises `Tempo.ConversionError`.

* **Sub-second `FREQ` or `BY*`** — Tempo's resolution ladder currently stops at `:second`. Sub-second recurrence isn't meaningful within Tempo's AST.

* **RFC 7529 `RSCALE` and `SKIP`** — read in an RRULE string for the Gregorian calendar, and neither is written. `SKIP=OMIT`, the default and RFC 5545's rule, passes over a date that does not exist, and `SKIP=BACKWARD` keeps the last day of a month or a year without its start's day (`RSCALE=GREGORIAN;FREQ=MONTHLY;SKIP=BACKWARD` from 31 January lists 28 February), each occurrence as long as the start is precise; JSCalendar's `skip` is read the same way. Reported as `{:error, reason}` rather than read as another: `SKIP=FORWARD` (`:unsupported_skip`), an `RSCALE` other than `GREGORIAN` (`:unsupported_rscale`), a `SKIP` with no `RSCALE`, which RFC 7529 §4.1 forbids (`:skip_without_rscale`), and `BACKWARD` beside a day the rule writes that a month or a year can lack, a `BYMONTHDAY` past the 28th or a `BYYEARDAY` past the 365th. Reading in another calendar is through DTSTART, and writing refuses what only `RSCALE` could say, both described above.

## Test coverage

Tempo's RRULE conformance is covered by six test files:

* `test/tempo/rrule_test.exs` — parse/round-trip behaviour at the string level.
* `test/tempo/rrule/expander_test.exs` — AST expansion across FREQ values.
* `test/tempo/rrule/selection_test.exs` — the RFC 5545 §3.8.5.3 worked examples (Thanksgiving, Election Day, Friday-the-13th, last-weekday-of-month, etc.).
* `test/tempo/rrule/rfc5545_conformance_test.exs` — broad conformance suite.
* `test/tempo/rrule/rdate_exdate_test.exs` — RDATE/EXDATE integration.
* `test/tempo/rrule/wkst_and_edges_test.exs` — WKST and boundary edge cases.

These sit on top of the broader suite that exercises the AST and set-algebra pipelines the RRULE machinery depends on.

## Acknowledgement

Tempo's iCalendar integration (event parsing, VTIMEZONE, RDATE/EXDATE collection, RRULE string tokenisation used as one of our input paths) relies on the excellent [`ical`](https://hex.pm/packages/ical) library, which claims full RFC 5545 compliance at the iCalendar object-graph level. The division of labour is clean: `ical` handles the iCalendar wire format; Tempo takes the parsed structures and turns them into something you can iterate, operate on, and compose with the rest of the time line. Without `ical`'s work, Tempo's iCal integration would have been a much larger undertaking.

## Related reading

* [Scheduling](./scheduling.md) — bounded enumeration, the `:within` option, wall-clock-vs-UTC authority, floating vs zoned events.

* [iCalendar integration](./ical-integration.md) — full details on `Tempo.ICal.parse/2` and round-tripping `.ics` files.

* [Set operations](./set-operations.md) — the member-preserving set algebra that RRULE expansions compose into.

* [Cookbook](./cookbook.md) — practical scheduling examples built on RRULE.

* [RFC 5545 §3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10) — the standard itself.
