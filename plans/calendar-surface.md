# One calendar surface

**Status:** planning, 2026-10-10

Tempo is to know nothing of how a calendar is implemented (the user, 2026-10-10: "Tempo, by design, should not know anything about a calendars implementation", and no special cases for a calendar are acceptable). Today it knows a great deal, and this plan is to take that knowledge out and leave one surface that every calendar answers alike. It rests on a census of the whole implementation, [calendar-surface-census.md](calendar-surface-census.md): 109 files and 36,162 lines of code read by a script, every match written, nothing sampled. Nothing here is built yet, and nothing is to be built until the decisions at the foot are taken.

## The rule

Tempo holds a calendar as a module and asks it questions. It may know:

* **Its own units** — a year, a month, a week, a day and the units of a time of day, and the order they are written in.

* **The notations it reads and writes** — ISO 8601, IXDTF, RFC 5545 and RFC 7529, RFC 8984 and cron, each of which says for itself which calendar it counts in.

* **The calendar of what lies outside it** — the zone database's, Astro's and Erlang's `:calendar`, all Gregorian.

It may not know any fact of how a calendar counts: which module it is, what it exports, what kind it is, where its year begins, or how many of anything it has. The test is mechanical, and the census script applies it:

* No line of code names a calendar module, outside one module that holds the three kinds of knowledge above.

* No line asks what a calendar exports.

* Every function called on a calendar is a required callback, of Elixir's `Calendar` behaviour or of `Calendrical`'s.

* No function answers by what kind of calendar it is given.

* No number is held that a calendar would be asked for.

## What the census found

At commit `254923c`, with Calendrical at `43006d7`:

* **107 calls on a calendar, of 34 functions** — 36 calls are of required callbacks of Elixir's `Calendar` and 44 of required callbacks of `Calendrical`. 6 calls are of 6 callbacks `Calendrical` declares optional. 21 calls are of 4 functions that neither behaviour declares: `plus/5` (18 calls), `location/1`, `new/3` and `year_of_era/1`.

* **`plus` is the function Tempo calls most, and the contract does not cover how it is called** — the callback is `plus/6`, declared for `:months` and `:quarters` ("Calendars need only implement this callback for `:months` and `:quarters`"). Of Tempo's 19 calls, 18 are at arity 5, and 14 pass `:days` (9), `:weeks` (3) or `:years` (2).

* **37 probes of what a calendar exports, of 25 functions** — 19 probe a callback that is required (3 of `Calendar`, 16 of `Calendrical`), so they answer `true` for every calendar that keeps the behaviour. 10 probe an optional callback, 7 a function neither behaviour declares, and 1 a function whose name is in a variable.

* **128 lines name a calendar module** — the Gregorian on 116, `Calendar.ISO` on 31, `Calendrical.ISOWeek` on 9 and `Calendrical.Chinese` on 1. By what the line does: 31 default to the Gregorian where no calendar is given, 7 read `Calendar.ISO` as it, 17 are fast paths for it, 16 give a named calendar other behaviour than the rest, 10 compute in it where any calendar could be asked, 12 pair `Calendrical.ISOWeek` with it for week dates, 26 are the calendar of something outside Tempo, and 9 leave its name out of what is written.

* **55 functions decide by a calendar's kind, and are called at 259 places** — whether it is a calendar of weeks or of months (15 functions, 81 calls, and 16 more direct calls of `calendar_base/0`), whether no calendar was given or `Calendar.ISO` (8, 83), whether its year begins on another day than the first of its first month (10, 32), whether it is the Gregorian (9, 18), whether it is a composite (3, 14), whether it has a year 0 (1, 11), what it exports (1, 11), how it names a month or a day (6, 7), and whether it has traditional months or numbers the weeks of its months (2, 2).

* **105 lines hold a number a calendar would be asked for** — 30 are the table of leap seconds, 27 are a standard's own numbers and 6 are prose. Of the rest, 16 hold the seven days of a week, 15 a fact of the Gregorian calendar, 6 a bound the reader keeps before it knows the calendar, and 5 a bound on the zone database's year.

* **Three places ask the same question another way** — `Tempo.calendar_module?/1` takes a module for a calendar if it exports `months_in_year/1`; `Calendrical.validate_calendar/1` if it exports `cldr_calendar_type/0`; and Localize holds its own list of the callbacks it asks beside Elixir's. Nothing states once what a calendar is.

## Why it is so

Four causes account for nearly all of it, and each task below removes one.

* **A value may hold no calendar** — `nil` and `Calendar.ISO` are both let into a `%Tempo{}`, so each function that needs the calendar resolves it again: 60 calls of `Tempo.Compare.effective_calendar/1`, 31 default lines and 7 for `Calendar.ISO`.

* **No one check says a module is a calendar** — so each call defends itself with a probe, 19 of them of callbacks the behaviour already requires.

* **The behaviour answers with counts, and Tempo needs values** — `months_in_year/1` and `days_in_month/2` say how many, which is the same as saying which only where the values run from 1 with none missing. England's 1751 has the months 3 to 12, its March the days 25 to 31, and September 1752 the days 1, 2 and 14 to 30. So Tempo finds out for itself where the counts are not enough (a composite, a year that begins late, a calendar of weeks) and works the values out, which is what 13 of the deciders and their 46 calls are for.

* **Speed was bought by naming the Gregorian** — 17 lines answer for it without asking it, on the belief that asking is slow. Whether any is still needed has not been measured.

## The surface

One contract: a calendar is a module that keeps the whole of Elixir's `Calendar` behaviour and the required callbacks of `Calendrical`, checked once where the module enters Tempo, and Tempo calls nothing else on it and probes nothing. Each question Tempo asks is then asked one way.

| Question | Asked today | To be asked | Calendrical today |
|---|---|---|---|
| Is this module a calendar? | `calendar_module?/1`, and a probe at each call | `Calendrical.validate_calendar/1`, once | Checks one callback |
| Which values does a unit take in a period? | 3 counts, `valid_date?/3`, 13 deciders | 2 callbacks that give values | Missing |
| The same, with no year | `months_in_year/0`, `days_in_month/1`, both probed | The same, unprobed | One is optional |
| The dates of a period | `year/1`, `month/2`, probed | `year/1`, `month/2`, `week/2`, `quarter/2` | Required |
| A date so many units on | `plus/5`, 5 probes, 7 guards | `plus/6`, for all five units | Declared for two units |
| The count between two dates | `Calendrical.diff/3`, `Date.diff/2` | `diff/3` | Required |
| A date's day count, and back | 2 callbacks, 3 generics, the Gregorian by name | The 2 callbacks | Required |
| Where a date falls | 7 callbacks, 3 probed | The same, unprobed | Required |
| The date at a place | Calendrical's generics, and `ISOWeek` by name | Generics that take the calendar | ISO week missing |
| What a month and a day are called | 3 callbacks, 1 optional, 6 deciders | The 3 callbacks | One is optional |
| A traditional month | 4 optional callbacks, `new/3` | The 4, required and total | Optional |
| The era of a year | `year_of_era/1`, the CLDR type | `year_of_era/3` | Required, of `Calendar` |
| A solar term | `location/1`, the Chinese by name | A function that takes the calendar | Missing |
| Weeks, or months? | `calendar_base/0` at 16 places, 15 deciders | `calendar_base/0`, at one place | Required |

Three kinds of knowledge stay in Tempo and are no calendar's to answer. Each goes to one module, which is then the only place a calendar is named:

* **The notation's calendar** — ISO 8601 writes Gregorian dates, so a value read with no calendar is Gregorian and one written in it carries no suffix (the 31 default lines, the 9 text lines, and `Calendar.ISO` at 7).

* **The calendar of what is outside** — the zone database, Astro, Easter and Erlang's `:calendar` take and give Gregorian dates (19 of the 26 outside lines, and the 20 calls of `:calendar`).

* **The calendar of a standard** — RFC 5545 and cron count in the Gregorian (7 of the 26).

## What Calendrical would change

Each is proposed, and its name and shape are Calendrical's to choose. Every calendar Calendrical has would answer each by a default where it is built (`Calendrical.Behaviour`, the month and week compilers, the composite and the Julian variants), so no calendar's author writes more.

* **The whole contract checked at once** — `Calendrical.validate_calendar/1` checks every required callback of both behaviours, where it checks `cldr_calendar_type/0` alone, so that Tempo, Localize and Calendrical hold a calendar to one list.

* **A period's values, as values** — two required callbacks: the months a year has, and the days a month of a year has, each as ranges in the order of time (`[3..12]` for England's 1751, `[25..31]` for its March, `[1..2, 14..30]` for September 1752). `months_in_year/1` and `days_in_month/2` stay, as Elixir requires them.

* **`months_in_year/0` required** — it is optional, and `days_in_month/1` beside it is required.

* **`plus/6` for every unit** — declared for `:years`, `:quarters`, `:months`, `:weeks` and `:days`. `Calendrical.Behaviour`, the month and week compilers and the composite each define all five today, at both arities.

* **The date of an ISO 8601 week date, for a calendar** — and the ISO weeks a year has. Tempo names `Calendrical.ISOWeek` for the Gregorian and works the date out itself for any other, by `plus` and `Calendrical.Kday`.

* **`cardinal_day/3` required** — with the day itself as its default.

* **The four callbacks of traditional months required and total** — `leap_month/1`, `traditional_leap_month/1`, `ordinal_month_from_traditional/2` and `lunar_month_of_year/2`, a calendar with no leap month answering `nil` and the month it is given; or their work behind `Calendrical.traditional_months/2` and its inverse.

* **A solar term asked of a calendar** — so that Tempo asks no `location/1` and does not fall back on `Calendrical.Chinese`. Reported on 2026-10-09.

## What Tempo would change

In the order they can be done. The first three need nothing of Calendrical.

* **A value always holds a calendar** — the default and `Calendar.ISO` are settled once, where a value is made, and nothing downstream asks again: 38 lines and the 8 deciders of that group, at 83 calls. Its first step is to read whether `nil` means anything today that a module could not say.

* **No probe of a required callback** — 19 probes go, and the calendar is validated where it enters.

* **What is outside, in one module** — the notation's calendar, the zone database's and a standard's are each named once: the 26 outside lines and the 9 of text come to that module.

* **`plus/6` alone** — 18 calls change arity, and the 5 probes of `plus` and the 7 `valid_date?/3` guards beside them go. Needs `plus/6` declared for every unit.

* **`Tempo.UnitValues` asks for values** — `in_period/3` and `in_any_year/3` ask the two new callbacks, and the deciders of a composite (3 functions, 14 calls) and of a year's first day (10, 32) go with 5 of the fast paths, as does the one that asks whether a calendar has a year 0 (11 calls), which becomes whether the year has any month. Needs the two callbacks.

* **Week dates through Calendrical** — the 12 lines that pair `Calendrical.ISOWeek` with the Gregorian, and `date_from_iso_week/4` and `iso_weeks_in_year/2` at 17 calls. Needs the ISO week functions.

* **Names, traditional months and solar terms** — 7 deciders, 11 probes and 3 fast paths. Needs the three changes of those names.

* **Weeks or months, asked once** — `calendar_base/0` is asked in the one function that gives a unit the unit below it (`Tempo.Iso8601.Unit.implicit_enumerator/2`), and the other 15 direct calls and the 15 deciders, at 81 calls, ask that function (17 of those calls are the week dates' above). Its first step is to read each of those 96 places for what it needs of the answer.

* **No fast path by name** — the 9 that remain are measured against the general path, each for the same answers and for its time, and go.

* **The Gregorian asked, not named** — the 10 lines that convert to Gregorian fields to compute ask the value's own calendar for its day count.

* **The week's seven days** — the 16 lines ask `days_in_week/0`.

## The measure

`python3 scripts/calendar_census.py` counts each. A task is done when its count is at its target and the suite passes.

| Count | Today | Target |
|---|---|---|
| Lines that name a calendar, outside the one module | 128 | 0 |
| Probes of what a calendar exports | 37 | 0 |
| Functions called on a calendar that neither behaviour declares | 4 | 0 |
| Functions called on a calendar that are optional | 6 | 0 |
| Functions that decide by a calendar's kind | 55, at 259 calls | 1, at 1 call |
| Lines that hold the days of a week | 16 | 0 |
| Lines that hold a fact of the Gregorian calendar | 15 | 0, or in the one module |
| Lines that hold the reader's bounds | 6 | 0 |

## Decisions for the user

* **What a calendar is** — recommended: a module that keeps the required callbacks of `Calendrical` and of `Calendar`, so a calendar that keeps Elixir's behaviour alone is refused where it enters, and `Calendar.ISO` is the one exception, read as the Gregorian there. The other course is to keep answering for such a calendar, which is what the 19 probes of required callbacks are for.

* **A calendar of weeks** — recommended: it stays a second shape of date (a week and a day of the week where a month and a day are), known in one function. The other course is for Calendrical to give every calendar's dates one shape, which is a larger change to it than any above.

* **Speed** — recommended: no fast path keyed on a calendar's name. Each is removed and measured, and where the general path is too slow the speed is Calendrical's to give (it keeps what a calendar is asked often), with a number agreed first for what too slow is.

* **What only the Gregorian has** — 16 lines (one of them the Chinese calendar's, for a solar term) and 15 numbers give a named calendar behaviour of its own: ISO 8601-2's seasons by its months, the 400 years its dates come round in (a rule that names no date of any year, and the lengths the network solver keeps), a month counted as twelve to a year on the network's axis and in a recurrence's domain, and the 28 days of its shortest month in a rule's `SKIP`. Recommended: each is decided on its own. `SKIP` asks `days_in_month/1`; the seasons are the notation's and go to the one module; the cycle is either asked of the calendar by a new callback or dropped for a bound that needs none.

* **The two callbacks that give values** — whether they are callbacks, as proposed, or generic functions of Calendrical built on `year/1` and `month/2`, which need no change to the behaviour and cost a walk of the period's days.

## What this plan has not done

* **It names what each class of place becomes, and not yet each place** — the census lists every one. Three tasks begin by reading their places one at a time, and say so: `nil` as a calendar, the 96 places that ask weeks or months, and the 9 fast paths.

* **It has measured no speed** — no fast path is known to be needed, and none is known not to be.

* **It has read `lib/` alone** — the tests' own support code holds calendar knowledge too (`test/support/matrix/calendar_census.ex` names calendars to choose its dates), and `tempo_holidays` and `tempo_sql` are not read.

* **It has not read Localize** — what Localize asks of a calendar is its own list, and one contract for the three libraries is the first change proposed for Calendrical.

## Found on the way

* **A count taken for a number of values** — `Tempo.Validation` sums `calendar.months_in_year/1` over a group of years for the months the group has (`lib/validation.ex:642`), and a composite answers with its last month that has days: 12 for England's 1751, which has ten.

* **A year written to its day in a set** — `Tempo.extend_resolution(~o"1751Y{3..5}M", :day)` in `Calendrical.Reform.England` is `1751Y{3..5}M1D`, which names 1 March 1751, a day that year does not have.

* **Half of a year written as a group it is not** — `1751Y1H` there is written `1751Y1G4MU`, which reads back as the months 1 to 4.

Each is the third cause above, and goes with the task for `Tempo.UnitValues`.

## Tasks

* [ ] **The decisions** — the five above, the user's.

* [ ] **Calendrical's changes** — the eight above, for the user to take to Calendrical; Tempo's tasks that need one wait on it.

* [ ] **A value always holds a calendar** — needs nothing upstream.

* [ ] **No probe of a required callback** — needs the first decision.

* [ ] **What is outside, in one module** — needs nothing upstream.

* [ ] **`plus/6` alone** — needs it declared for every unit.

* [ ] **`Tempo.UnitValues` asks for values** — needs the two callbacks.

* [ ] **Week dates through Calendrical** — needs the ISO week functions.

* [ ] **Names, traditional months and solar terms** — needs the three changes.

* [ ] **Weeks or months, asked once** — needs the second decision.

* [ ] **No fast path by name** — needs the third decision.

* [ ] **The Gregorian asked, not named, and the week's seven days** — needs nothing upstream.

* [ ] **What only the Gregorian has** — needs the fourth decision.
