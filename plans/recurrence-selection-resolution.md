# Recurrence selection resolution

**Status:** in progress, 2026-09-21

An unanchored recurrence materialises against a `:bound` alone. Each
occurrence should land at the grain the selection names — day for
`FL6M2I1KN`, month for `FL6MN`, week for `FL10WN` — using the **calendar**
as the source of truth, never a hard-coded week rule.

## Month selections — done

`R/../P1Y/FL6MN` ("every June") now yields the month `~o"2026Y6M/7M"`, not
June 1st. Two changes: the bound-derived anchor takes the selection's
resolution (`anchor_unit/1` in `lib/tempo.ex`), and `expand_candidate_months/4`
in `lib/tempo/rrule/selection.ex` produces a month occurrence for a dayless
candidate instead of rejecting it (`swap_date` preserves the candidate's own
resolution).

RRULE is untouched: `FREQ=YEARLY;BYMONTH=6` with `DTSTART=2026-06-15` still
means June 15 (a day) — `BYMONTH` filters, `DTSTART` pins the day — because
RRULE carries a real day anchor and never routes through the bound anchor.
The native-vs-RRULE split is exactly the day/month resolution difference.

## Week of year — done

`R/../P1Y/FL10WN` now yields the week span `~o"2026Y10W/11W"`, matching
`Tempo.select(~o"2026", ~o"10W")`. A week selection anchors on its enclosing
year (`calendar_anchor_unit(:week) → :year` — the week axis has no
`at_resolution/2` path from a year), which makes the candidate dayless;
`expand_candidate_week_numbers/2` then builds the `[year, week]` value rather
than walking to dates, and the calendar resolves its span. RRULE `BYWEEKNO`
is unchanged: its `DTSTART` day makes the candidate day-carrying, so it still
expands each week to its seven days per RFC 5545.

Calendar-awareness lives in the `[year, week]` value's own resolution (which
already rejects `~o"2026Y53W"` for a 52-week year), not in
`lib/tempo/rrule/selection.ex`. So the native path never touches the
hard-coded ISO walk.

## Still to do

The `week_dates_in_year/3` ISO walk (Monday-first, Jan-4 anchor) is
**still** what RRULE `BYWEEKNO` uses, and it is wrong for non-ISO calendars.
Calendrical is the source of truth: `week_of_year/3`, `weeks_in_year/2`,
`min_days_in_first_week` with `min_days_for_territory/1` /
`min_days_for_locale/1`, and per-calendar schemes (`NRF`, `BasicWeek`,
`Julian`, ISO).

Week **of month** ("the 2nd week of June") needs no new designator: the
natural spelling is `2026Y6M2W` — a `W` component read positionally, week-of-
year after a bare year, week-of-month after a month. The tokenizer rejects
`W` after a month today (`Error detected at "2W"`), so the work is a parser
extension plus materialisation via `Calendrical.week_of_month/3`.

## Tasks

* [x] Month selections yield a month span; RRULE `BYMONTH` unchanged.

* [x] Native week-of-year selection (`FL10WN`) yields a week span, resolved by the calendar; RRULE `BYWEEKNO` unchanged.

* [ ] Parse `W` after a month (`2026Y6M2W`) as week-of-month, and materialise it via `Calendrical.week_of_month/3`.

* [ ] Replace the hard-coded ISO `week_dates_in_year/3` on the RRULE `BYWEEKNO` path with Calendrical's calendar-aware week functions.
