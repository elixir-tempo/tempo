# Day starts

**Status:** in progress, 2026-11-01

A day of the Hebrew or an Islamic calendar begins at sunset. Tempo reads such a day as a day, the span from one midnight to the next; placed on the UTC line it is the span from the sunset before to the sunset of the day. `tempo_holidays` does that placing itself today (`Tempo.Holidays.DayStart.project/3`), with Astro for the sunset and its own rules for where and on whose clock. When a day begins is calendar maths, so it belongs in Calendrical, with the astronomy in Astro; Tempo projects through Calendrical, and `tempo_holidays` through Tempo.

## A day start is the calendar's

A day start is calendar-relative, as everything else is: the calendar names its boundary and its place, and a caller names only the calendar. `tempo_holidays` knows each holiday's calendar, so it says nothing more.

| Calendar | Boundary | Place |
|---|---|---|
| `Calendrical.Hebrew` | sunset (shkiah) | Jerusalem |
| `Calendrical.Islamic.UmmAlQura` | sunset (Maghrib) | Mecca |
| `Calendrical.Islamic.Rgsa` | sunset (Maghrib) | Mecca |
| `Calendrical.Islamic.Observational` | sunset (Maghrib) | Cairo, where it predicts each month's crescent |

These are the boundaries and places `date_at/2` already uses for `day_start: :sunset`. A day that begins somewhere else, a Hebrew day at New York's sunset or an Islamic day at Kuala Lumpur's, is a day of another calendar: one defined for that place, with its own boundary and place.

## Decisions

Decision 91 of `plans/decisions.md`, the user's, 2026-11-01:

* **Calendrical gives a day's bounds, calendar-relative.** `day_bounds/1` on every calendar with `date_at/2` takes a date of the calendar and returns `{:ok, {start, stop}}`: the UTC instants of the sunset the day begins at and of the one it ends at, half-open, at the calendar's own place. It takes no location, no zone and no boundary: the calendar fixes all three. It is the inverse of `date_at/2` with `day_start: :sunset`: `date_at` of `start` is the date, and of the instant before it the day before.

* **Tempo projects with `Tempo.day_start/1`**, over Calendrical's `day_bounds/1`.

* **A day start of another place is another calendar** (Deferred): a Hebrew calendar for a community outside Israel, or an Islamic calendar of a country that sets its own months, is a calendar defined with its place.

## The shape of the work

### Calendrical

* `day_bounds/1` beside `date_at/2` on each of the four calendars, through `Calendrical.DayStart`, from Astro's sunset at the calendar's place.

* A date of another calendar is a `Calendrical.IncompatibleCalendarError`; a date outside the calendar's range, or a day with no sunset at the place, is the error `date_at/2` gives for it.

* `date_at/2` and its options stay as they are: released API, on which nothing new is built.

### Tempo

* `Tempo.day_start/1`: a value of a day, an interval of days, a set or a recurrence. A day of a calendar with `day_bounds/1` is the span from its start to its stop, on the UTC line; a run of days is from the start of the first to the stop of the last.

* A day of another calendar beside them is the civil day in the zone of the sunset days' place (decision 41), so the result lies on one line (law 4); beside sunset days of two places, it is a `Tempo.FrameError`.

* A value with a time of day, or coarser than a day, is an error that names it.

### tempo_holidays

* `Tempo.Holidays.day_start/2` projects a holiday set through `Tempo.day_start/1`: its own astronomy, evening clock, canonical places and locations go, and with them `{:evening, …}`, `{:sunset, location}` and `tz_world`. What stays is about holidays: the zone the civil days beside projected ones go in.

## Tasks

* [x] **Calendrical `day_bounds/1`** — on the four calendars, the inverse of `date_at/2` with `day_start: :sunset`, tested against it; in Calendrical 2.4.0, unreleased. 2026-11-01.

* [ ] **`Tempo.day_start/1`** — on Calendrical's `day_bounds/1`. Blocked on a Calendrical release with it.

* [ ] **tempo_holidays on `Tempo.day_start/1`** — `day_start/2` reduced to the holiday-set logic. Blocked on `Tempo.day_start/1`.

### Deferred

* [ ] **A calendar of another place** — a Hebrew calendar for a community outside Israel, an Islamic calendar of a country that sets its own months, defined with its place, when one is wanted.
