# Day starts

**Status:** planning, 2026-11-01

A day of the Hebrew or an Islamic calendar begins in the evening: at sunset, at nightfall, or at 18:00 as a proxy for them. Tempo reads such a day as a day, the span from one midnight to the next; placed on the UTC line it is the span from the evening before to the evening of the day. `tempo_holidays` does that placing itself today (`Tempo.Holidays.DayStart.project/3`), with Astro for the sunset and its own rules for the rest. When a day begins is calendar maths, so it belongs in Calendrical, with the astronomy in Astro; Tempo projects through Calendrical, and `tempo_holidays` through Tempo.

## Where it stands

| | Calendrical `date_at/2` | `tempo_holidays` `DayStart` |
|---|---|---|
| Direction | an instant to its calendar date | a calendar day to its instants |
| Conventions | `:midnight`, `:evening`, `:sunset`, `:nightfall` | `:midnight`, `:evening`, `:sunset` |
| Where | Hebrew: `:location`, a point (Jerusalem); Islamic: Mecca only | a zone id or a point; Mecca or Jerusalem by default |
| 18:00 on | the location's standard offset (Mecca +03:00, Jerusalem's mean time) | the zone's wall clock, its daylight saving included |

The two disagree: a summer evening in Jerusalem is 18:00 at +02:21 to one and at +03:00 to the other, and an Islamic day cannot be asked about anywhere but Mecca in Calendrical.

## Decisions

Decision 91 of `plans/decisions.md`, the user's, 2026-11-01:

* **Calendrical gives a day's bounds.** `day_bounds/2` on every calendar with `date_at/2` (`Calendrical.Hebrew`, `Calendrical.Islamic.UmmAlQura`, `Calendrical.Islamic.Rgsa`, `Calendrical.Islamic.Observational`) takes a date of the calendar and the options of `date_at/2`, and returns `{:ok, {start, stop}}`: the UTC instants the day begins and the next begins, half-open. It is the inverse of `date_at/2`: `date_at/2` of `start` is the date, and of the instant before it the day before.

* **An evening is 18:00 on a zone's wall clock.** `date_at/2` and `day_bounds/2` take a `:time_zone`, an IANA zone, and read 18:00 on its clock, daylight saving included; without one, the fixed offset of today.

* **Every Islamic calendar takes a `:location`**, a point, as the Hebrew calendar does, for `:sunset` and `:nightfall`; Mecca is the default.

* **Tempo projects with `Tempo.day_start/3`.** `Tempo.day_start(expression, day_start, options)` gives the expression with each day of a calendar that has `day_bounds/2` as the span on the UTC line its bounds give, the options passed to Calendrical.

## The shape of the work

### Calendrical

* `day_bounds/2` beside `date_at/2` on each of the four calendars, through `Calendrical.DayStart`, with `day_start` one of `:midnight`, `:evening`, `:sunset` and `:nightfall`. `:midnight` is the civil day at the location's offset, or in `:time_zone`.

* `:time_zone` on `date_at/2` and `day_bounds/2`: the clock 18:00 is read on, and the zone `:midnight` is read in. A reading the zone skips or shows twice is its first instant after the change, as Tempo places one.

* `:location` on the three Islamic calendars, default Mecca.

* A point is a `Geo.Point` or `Geo.PointZ`, as Astro takes.

### Tempo

* `Tempo.day_start/3`: a value of a day, an interval of days, a set or a recurrence. A day of a calendar with `day_bounds/2` is the span from its start to its stop, in `:time_zone` where one is given and at UTC otherwise; a run of days is from the start of the first to the stop of the last.

* A day of another calendar beside them is the civil day in `:time_zone` (decision 41), so the result lies on one line (law 4); with none given, it is a `Tempo.FrameError`.

* A value with a time of day, or coarser than a day, is an error that names it; so is a day start Calendrical refuses, as its own error.

### tempo_holidays

* `Tempo.Holidays.DayStart.project/3` calls `Tempo.day_start/3`; its astronomy, its evening clock and its canonical places go.

* What is about holidays stays: `day_start/2` over a holiday set, the zone the civil days beside projected ones go in, and `tz_world` for a point's zone.

## Tasks

* [ ] **Calendrical `day_bounds/2`** — on the four calendars, the inverse of `date_at/2`, tested against it.

* [ ] **Calendrical `:time_zone`** — the evening on a zone's wall clock, for `date_at/2` and `day_bounds/2`.

* [ ] **Calendrical `:location` for the Islamic calendars.**

* [ ] **`Tempo.day_start/3`** — on Calendrical's `day_bounds/2`. Blocked on the three above.

* [ ] **tempo_holidays on `Tempo.day_start/3`** — `DayStart.project/3` reduced to a call, its own maths removed. Blocked on `Tempo.day_start/3`.
