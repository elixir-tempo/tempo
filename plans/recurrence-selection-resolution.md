# Recurrence selection resolution

**Status:** in progress, 2026-10-07

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

RRULE `BYWEEKNO` numbers its weeks as RFC 5545 §3.3.10 does, from `WKST` with week 1 the week that holds the year's fourth day, and the walk is Calendrical's in any calendar: `Tempo.Validation.week_starts/3` takes the fourth day of the year from `Calendrical.date_from_day_of_year/3`, the week start on or before it from `Calendrical.Kday`, and each week after from `Calendrical.next/2`. The hard-coded ISO walk (`week_dates_in_year/3`) is gone. A calendar's own weeks are the `w` selection (`:calendar_week`), which asks the calendar's `week_of_year/3`.

## Week of month — done

Week **of month** ("the 2nd week of June") needed no new designator: the spelling is `2026Y6M2W`, a `W` read positionally, a week of the year after a bare year and a week of the month after a month (decided 2026-10-07: the week Calendrical numbers, whole).

* **The weeks** — `Tempo.UnitValues.weeks_of_month/3` is the one place they are found. Calendrical says which week of which month a date is in (`week_of_month/3`) and has no inverse, so the days a week can end on are asked: the month's first day and the days before it for the start of week 1, then six days on and the day after for each week, and a day at a time where the calendar cuts a week short. A calendar of weeks has no months, and one whose year does not begin with its first month counts its months otherwise than its dates name them, and is refused by name.

* **The value** — `Tempo.Iso8601.Group.expand_groups/2` reads `[year, month, week | rest]` as a calendar week of a year (`w`) is read: alone as the interval of the week's dates, with a day of the week as the date, and with a time of day under the week alone on its first date. It is written back as the dates it names. A set, a mask or a range in the week, the month or the year is a `ParseError` that points to `Tempo.select/2`.

* **The constraint** — `Tempo.select/2` gives a week selected from a month the same reading (`merged_onto/3` in `lib/tempo/select.ex`), each week a set or a range names in the month as a constraint of its own (`each_week_of_month/2`), and keeps a selected week by starting among the month's weeks and not in the month (`span_selected_in/2`), so the week that starts on 29 June is July's first and is selected once from a span of months.

* **The selection** — a week part at the scope of a month, with a candidate that is a month, is the week's span (`week_in_month/3` in `lib/tempo/rrule/selection.ex`), marked to keep that span as a calendar week's is. A rule that steps by months starts from its month (`calendar_start_unit/2` in `lib/tempo.ex`). A candidate that is a day is still kept or dropped by its week of the year.

Not built, and refused by name: a week of a month beside a part that picks within it (`2026Y6ML2W3KN`), whose start is filled to a day; a week of the calendar's own numbering under a month (`w`); a mask of weeks. A month beside a week in a yearly selection (`2026YL6M2WN`) is still ISO week 2 of the year. Each is an item of `TODO.md`.

## Tasks

* [x] Month selections yield a month span; RRULE `BYMONTH` unchanged.

* [x] Native week-of-year selection (`FL10WN`) yields a week span, resolved by the calendar; RRULE `BYWEEKNO` unchanged.

* [x] Parse `W` after a month (`2026Y6M2W`) as week-of-month, and materialise it via `Calendrical.week_of_month/3`: Calendrical counts whole weeks, week 1 the one that holds the month's first day, so 29 and 30 June 2026 are in week 1 of July. 2026-10-07.

* [ ] A week of a month beside a part that picks within it, in a selection (`TODO.md`).

* [x] Replace the hard-coded ISO `week_dates_in_year/3` on the RRULE `BYWEEKNO` path with Calendrical's calendar-aware week functions (`Tempo.Validation.week_starts/3`).
