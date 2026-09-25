# RFC 5545 RRULE Conformance

Tempo treats RFC 5545 RRULE as a first-class recurrence vocabulary. Every rule that [section 3.3.10 of the standard](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10) defines can be parsed into a recurring `%Tempo.Interval{}` (modelled internally by Tempo's typed RRULE AST, `%Tempo.RRule.Rule{}`), materialised into a `%Tempo.IntervalSet{}` over any bounded window, and composed with the rest of Tempo's set algebra — `union`, `intersection`, `difference`, and friends. This guide catalogues precisely what that means, what's supported, and what isn't.

Tempo's RRULE parsing is its own implementation; it does not delegate to a third-party library for the string-to-AST step. For full iCalendar (`.ics`) files with events, RDATEs, and EXDATEs, Tempo delegates to the excellent [`ical`](https://hex.pm/packages/ical) library and converts its `%ICal.Recurrence{}` into the same Tempo AST — giving you a single materialisation path regardless of whether the rule came from a hand-written string or a parsed iCalendar feed.

The reference is [RFC 5545 §3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10). A companion extension, RFC 7529 (RSCALE for alternative calendars), is **not** implemented as a named property — Tempo achieves the same outcome through its calendar-aware expansion pipeline (see below).

## What Tempo guarantees

Given an RRULE, Tempo will:

* **Parse** the string into a recurring `%Tempo.Interval{}` via `Tempo.RRule.parse/2` — its recurrence is described by the typed `%Tempo.RRule.Rule{}` field vocabulary catalogued below.

* **Expand** that recurring interval into an explicit `%Tempo.IntervalSet{}` of occurrences via `Tempo.to_interval/2`.

* **Apply set operations**: occurrences compose with every operation (`Tempo.union/2`, `Tempo.intersection/2`, `Tempo.difference/2`, `Tempo.symmetric_difference/2`, `Tempo.complement/2`, `Tempo.members_overlapping/2`, `Tempo.members_outside/2`, `Tempo.members_in_exactly_one/2`) and with the predicates (`overlaps?/2`, `disjoint?/2`, `contains?/2`, `equal?/2`, `subset?/2`).

* **Iterate** via `Enum` — `Enum.to_list/1`, `Stream.take/2`, etc. — when the rule is bounded or a `:bound` is supplied.

* **Re-encode** back to an RRULE string via `Tempo.to_rrule/1` for values that originated as RRULEs.

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
* `BYWEEKNO` expands when `FREQ=YEARLY`; limits otherwise.
* `BYDAY`'s role depends on `FREQ` and whether `BYWEEKNO` or `BYMONTH` is also present — Tempo follows the RFC's §3.3.10 decision table.
* `BYHOUR`/`BYMINUTE`/`BYSECOND` expand when `FREQ` is coarser than the unit; limit when finer.
* `BYSETPOS` is always applied last as a LIMIT across the candidate set.

### RDATE and EXDATE

These are VEVENT-level properties rather than RRULE-level, but they compose with RRULE expansion through `Tempo.ICal.from_ical/2`:

* **`RDATE`** contributes additional occurrences beyond the RRULE expansion. Tempo implements this as a `union` of the RRULE expansion with an `%Tempo.IntervalSet{}` of the RDATEs (each RDATE carries the event's original `DTEND - DTSTART` span; metadata is preserved).

* **`EXDATE`** removes matching occurrences from the expansion. Tempo implements this as a member-filter difference — an occurrence is removed if its `.from` moment matches an EXDATE via RFC-compliant endpoint comparison.

The end-to-end formula: **`occurrences = (expand(rrule) ∪ rdates) − exdates`**.

## Calendar awareness

RFC 5545 is implicitly Gregorian. RFC 7529 defines a separate `RSCALE` property for alternative calendars; Tempo does not implement `RSCALE` as a parsed property. Instead, **Tempo's RRULE expansion is calendar-aware through the rule's DTSTART**. Parse a DTSTART in the Hebrew calendar (`5786-09-30[u-ca=hebrew]`) and expand an RRULE against it, and the expansion iterates in Hebrew months. The same rule string yields different occurrences depending on which calendar the anchor is in — which is closer to what most applications want than the RSCALE annotation dance.

Occurrence selection helpers (`days_in_month/2`, `day_of_year/3`, `iso_week_of_year/3`, `weeks_in_year/1`, `day_of_week/4`) dispatch to the calendar module, so BYMONTH/BYMONTHDAY/BYYEARDAY/BYWEEKNO all respect calendar-specific month lengths, year lengths, and week structures.

## Unbounded rules require a bound

A rule with `FREQ` but no `COUNT`, no `UNTIL`, and no externally-supplied `:bound` is infinite — Tempo cannot materialise it. Attempting to do so returns:

```elixir
{:error, %Tempo.UnboundedRecurrenceError{reason: ...}}
```

The error message points callers at the `:bound` option. This is a deliberate design choice (see the [scheduling guide](./scheduling.md)) — infinite recurrences are rule-shaped, not set-shaped, and Tempo refuses to silently iterate without a stop condition.

## Not supported

A small list of features outside Tempo's current RRULE scope:

* **`EXRULE`** — deprecated by RFC 5545 Errata in favour of EXDATE. Not exposed by the underlying `ical` library and not implemented in Tempo. EXDATE covers every use case.

* **Duration-only VEVENT** (DURATION without DTEND) — not yet supported in `Tempo.ICal.from_ical/2`. The iCal library parses it; Tempo's conversion doesn't handle it. Raises `Tempo.ConversionError`.

* **Sub-second `FREQ` or `BY*`** — Tempo's resolution ladder currently stops at `:second`. Sub-second recurrence isn't meaningful within Tempo's AST.

* **RFC 7529 `RSCALE`** — the named property is not parsed. Calendar-awareness via DTSTART gives equivalent behaviour, described above.

## Test coverage

Tempo's RRULE conformance is covered by six test files:

* `test/tempo/rrule_test.exs` — parse/round-trip behaviour at the string level.
* `test/tempo/rrule/expander_test.exs` — AST materialisation across FREQ values.
* `test/tempo/rrule/selection_test.exs` — the RFC 5545 §3.8.5.3 worked examples (Thanksgiving, Election Day, Friday-the-13th, last-weekday-of-month, etc.).
* `test/tempo/rrule/rfc5545_conformance_test.exs` — broad conformance suite.
* `test/tempo/rrule/rdate_exdate_test.exs` — RDATE/EXDATE integration.
* `test/tempo/rrule/wkst_and_edges_test.exs` — WKST and boundary edge cases.

These sit on top of the broader suite that exercises the AST and set-algebra pipelines the RRULE machinery depends on.

## Acknowledgement

Tempo's iCalendar integration (event parsing, VTIMEZONE, RDATE/EXDATE collection, RRULE string tokenisation used as one of our input paths) relies on the excellent [`ical`](https://hex.pm/packages/ical) library, which claims full RFC 5545 compliance at the iCalendar object-graph level. The division of labour is clean: `ical` handles the iCalendar wire format; Tempo takes the parsed structures and turns them into something you can iterate, operate on, and compose with the rest of the time line. Without `ical`'s work, Tempo's iCal integration would have been a much larger undertaking.

## Related reading

* [Scheduling](./scheduling.md) — bounded enumeration, the `:bound` option, wall-clock-vs-UTC authority, floating vs zoned events.

* [iCalendar integration](./ical-integration.md) — full details on `Tempo.ICal.from_ical/2` and round-tripping `.ics` files.

* [Set operations](./set-operations.md) — the member-preserving set algebra that RRULE expansions compose into.

* [Cookbook](./cookbook.md) — practical scheduling examples built on RRULE.

* [RFC 5545 §3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10) — the standard itself.
