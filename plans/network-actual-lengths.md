# Network actual lengths

**Status:** implemented (v2.0.0), 2026-09-30

`Tempo.Network.Normalize` put a network's durations on one integer axis with a mean Gregorian year and month (365.2425 and 30.436875 days). Tempo does not use mean year and month lengths: it uses the actual ones, even if that requires enumeration (user, 2026-09-30). This plan replaces the means, and fixes the other ways the normaliser placed values inexactly.

## What was wrong

* **Mean lengths** — a period from 1 January 2024 lasting `P1Y` got 365 days (2024 has 366); from 1 Tishri 5784, 365 (5784 has 383); `P1M` from 31 January 2026 got 30 days, where calendar arithmetic ends it on 28 February.

* **Relation delays** — they did not set the axis, so "starts at least `P6M` after" between year-dated periods rounded to a year.

* **Coarse bounds** — a year bound on a day axis read as its first day, so `{:not_after, ~o"1300Y"}` cut 1300 to 1 January.

* **Other calendars** — a bound in another calendar on a year axis became the Gregorian year its start falls in.

* **Raises** — a network counting only weeks, or naming hours, raised `FunctionClauseError`, as did a `Tempo.Schedule` task lasting `PT4H`.

## Decisions

* **The axis** is the finest unit among the bounds, the period durations and the relation delays; a week counts in days. A year axis counts the years of the network's calendar when all its bounds share one; a month axis only Gregorian months; a day axis Calendrical's iso days, calendar-neutral; and hours, minutes and seconds count seconds on the time line, results shown in the network's unit.

* **A bound is the span it names**: a lower bound takes its first axis unit, an upper bound its last.

* **A duration in the axis unit** (or in weeks on a day axis) is a count, and a fraction of the axis unit is an error. **A coarser one is measured**: added by calendar arithmetic to every position its start can take. The shortest and longest runs bound its length, the earliest and latest run ends bound its end, and the latest (or earliest) start whose run can end within its end's range bounds its start, so a pinned start gives its exact length. The solver solves, re-measures from the bounds it found, and repeats until nothing changes; each round only tightens. A wide start waits while narrower measures still move the bounds.

* **A duration counts in its period's calendar** (the calendar of its bounds), a relation delay in that of the period it counts from, and otherwise in the network's calendar, or Gregorian.

* **An unbounded start**: in the Gregorian calendar, the shortest and longest lengths over one 400-year cycle, which a start range as wide as a cycle also takes; in any other calendar an error, unless Calendrical comes to give a calendar's extremes (user, 2026-09-30).

* **Results** are in the axis calendar. `normalize/1` returns `{:ok, normalized}` or `{:error, reason}` (breaking).

## Tasks

### Done

* [x] **Networks and schedules in hours** — a sub-day network counts seconds on the time line (the wall clock for floating bounds, UTC for zoned ones; floating and zoned bounds together are an error) and shows its unit. Hours, minutes and seconds are counts; a day or longer is measured in the period's zone, its start range cut into segments of one length at wall midnights, or in a zone sampled hourly with bisection, so a day across a daylight-saving change is its 23 or 25 hours even where a gap moves its end. A zoned start with no bound is an error. 2026-09-30.

* [x] **Normalize** — the axis, bounds as spans, counts, measures and their bounds, errors for what a network cannot place. 2026-09-30.

* [x] **Solver** — the settle loop in every entry point: wide starts wait for the narrower measures, then take the Gregorian cycle's lengths or return an error; results in the axis calendar. 2026-09-30.

* [x] **Tests, docs, CHANGELOG and migration** — each defect above in `test/tempo/network/actual_lengths_test.exs`, the networks guide, the breaking `normalize/1`. 2026-09-30.
