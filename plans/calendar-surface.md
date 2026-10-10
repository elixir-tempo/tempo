# One calendar surface

**Status:** in progress, 2026-10-10

Tempo is to know nothing of how a calendar is implemented (the user, 2026-10-10: "Tempo, by design, should not know anything about a calendars implementation", and no special cases for a calendar are acceptable). Today it knows a great deal, and this plan is to take that knowledge out and leave one surface that every calendar answers alike. It rests on a census of the whole implementation, [calendar-surface-census.md](calendar-surface-census.md): 109 files and 36,162 lines of code read by a script, every match written, nothing sampled. The decisions at the foot were taken on 2026-10-10 and the work is under way: the tasks at the end say what is done, and what waits on Calendrical is in its `TODO.md`.

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

At the first census, of commit `254923c` with Calendrical at `43006d7` (the census file holds the counts of the tree as it now stands):

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

One contract: a calendar is a module that implements Elixir's `Calendar` behaviour and `Calendrical`'s. Whether it does is asked once, where the module enters Tempo, and is no more than whether it declares the two; that it then keeps them is its author's to see to, and Tempo calls their required callbacks alone and probes nothing. Each question Tempo asks is then asked one way.

| Question | Asked today | To be asked | Calendrical today |
|---|---|---|---|
| Is this module a calendar? | `calendar_module?/1`, and a probe at each call | `Calendrical.validate_calendar/1`, once | Checks one callback, not the two behaviours |
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

* **`validate_calendar/1` asks whether a module implements the two behaviours** — it checks that `cldr_calendar_type/0` is exported. All 34 calendar modules Calendrical has declare both behaviours, and `Calendar.ISO` declares one and is answered as the Gregorian. No list of callbacks is checked, there or in Tempo (the user, 2026-10-10).

* **A period's values, as values** — two required callbacks: the months a year has, and the days a month of a year has, each as ranges in the order of time (`[3..12]` for England's 1751, `[25..31]` for its March, `[1..2, 14..30]` for September 1752). `months_in_year/1` and `days_in_month/2` stay, as Elixir requires them.

* **`months_in_year/0` required** — it is optional, and `days_in_month/1` beside it is required.

* **`plus/6` for every unit** — declared for `:years`, `:quarters`, `:months`, `:weeks` and `:days`. `Calendrical.Behaviour`, the month and week compilers and the composite each define all five today, at both arities.

* **The weeks of a month as callbacks** — `Calendrical.Interval.weeks_in_month/3` and `week/4` are functions that walk the days about a month, and are to be callbacks beside `weeks_in_year/1` (the user, 2026-10-10). Tempo calls the two until then.

* **The date of an ISO 8601 week date, for a calendar** — and the ISO weeks a year has, as callbacks. Tempo names `Calendrical.ISOWeek` for the Gregorian and works the date out itself for any other, by `plus` and `Calendrical.Kday`.

* **`cardinal_day/3` required** — with the day itself as its default.

* **The four callbacks of traditional months required and total** — `leap_month/1`, `traditional_leap_month/1`, `ordinal_month_from_traditional/2` and `lunar_month_of_year/2`, a calendar with no leap month answering `nil` and the month it is given; or their work behind `Calendrical.traditional_months/2` and its inverse.

* **A solar term asked of a calendar** — so that Tempo asks no `location/1` and does not fall back on `Calendrical.Chinese`. Reported on 2026-10-09.

## What Tempo would change

In the order they can be done. The first three need nothing of Calendrical.

* **A value's calendar is read through one accessor** — a value written as a struct with `nil` or `Calendar.ISO` for its calendar is still read as the notation's (the user, 2026-10-10: "Keep it, in one accessor"), and one function says so: `Tempo.Calendars.effective/1`, in the one module that may name a calendar. The 38 lines that defaulted to the Gregorian or mapped `Calendar.ISO`, and the 8 functions that did it at 83 calls, call it. A probe can go only where the calendar has passed through it.

* **No probe of a required callback** — 19 probes go, and whether the module is a calendar is asked once, where it enters, of `Calendrical.validate_calendar/1`.

* **What is outside, in one module** — the notation's calendar, the zone database's and a standard's are each named once: the 26 outside lines and the 9 of text come to that module.

* **`plus/6` alone** — 18 calls change arity and the 5 probes of `plus` go. The 7 calls of `valid_date?/3` beside them stay: each asks a required callback whether what is stepped from is a date, which is no probe. Calendrical's declaration of every unit is in its `TODO.md`.

* **`Tempo.UnitValues` asks for values** — `in_period/3` and `in_any_year/3` ask the two new callbacks, and the deciders of a composite (3 functions, 14 calls) and of a year's first day (10, 32) go with 5 of the fast paths, as does the one that asks whether a calendar has a year 0 (11 calls), which becomes whether the year has any month. Needs the two callbacks.

* **Week dates through Calendrical** — the 12 lines that pair `Calendrical.ISOWeek` with the Gregorian, and `date_from_iso_week/4` and `iso_weeks_in_year/2` at 17 calls. Needs the ISO week functions.

* **Names, traditional months and solar terms** — 7 deciders, 11 probes and 3 fast paths. Needs the three changes of those names.

* **Weeks or months, asked once** — `calendar_base/0` is asked in the one function that gives a unit the unit below it (`Tempo.Iso8601.Unit.implicit_enumerator/2`), and the other 15 direct calls and the 15 deciders, at 81 calls, ask that function (17 of those calls are the week dates' above). Its first step is to read each of those 96 places for what it needs of the answer.

* **No fast path by name** — the 9 that remain are measured against the general path, each for the same answers and for its time, and go.

* **The Gregorian asked, not named** — the 10 lines that convert to Gregorian fields to compute ask the value's own calendar for its day count.

* **The week's seven days** — the 16 lines ask `days_in_week/0`.

## The measure

`python3 scripts/calendar_census.py` counts each. A task is done when its count is at its target and the suite passes.

| Count | First census | Target |
|---|---|---|
| Lines that name a calendar, outside the one module | 128 | 0 |
| Probes of what a calendar exports | 37 | 0 |
| Functions called on a calendar that neither behaviour declares | 4 | 0 |
| Functions called on a calendar that are optional | 6 | 0 |
| Direct asks of a calendar's base | 16 | 1 |
| Functions that decide by a calendar's kind, the accessor and the base apart | 32, at 95 calls | 0 |
| Lines that hold the days of a week | 16 | 0 |
| Lines that hold a fact of the Gregorian calendar | 15 | 0, or in the one module |
| Lines that hold the reader's bounds | 6 | 0 |
| Constants that are a calendar's to answer | 13 of 250 | 0 |

## Every call a callback

The end state the user set on 2026-10-10: "Basically, all calendar calls in Tempo should be `calendar.some_callback` It really should be as simple as that." At `29b4677` Tempo calls 28 functions on a calendar at 93 places, and makes 84 calls of 35 functions in Calendrical's own modules ([calendar-surface-census.md](calendar-surface-census.md), sections 3 and 5), most of them with a calendar passed as an argument. Read one at a time, the 84 are of four kinds.

### A callback exists today, and Tempo calls a wrapper of it (25 calls)

These need no change in Calendrical: Tempo asks the calendar it already holds.

| Tempo calls | Calls | Becomes |
|---|---|---|
| `Calendrical.diff(from, to, unit)` | 4 | `calendar.diff(from, to, unit)` |
| `Calendrical.date_from_iso_days(days, calendar)` | 3 | `calendar.date_from_iso_days(days)` |
| `Calendrical.date_to_iso_days(date)` | 2 | `calendar.date_to_iso_days(year, month, day)` |
| `Calendrical.iso_days(year, month, day, calendar)` | 3 | `calendar.valid_date?/3`, then `calendar.date_to_iso_days/3` |
| `Calendrical.first_day_of_year(year, calendar)` | 1 | `calendar.year(year)` |
| `Calendrical.first_gregorian_day_of_year/2`, `last_gregorian_day_of_year/2` | 2 | `calendar.year(year)`, then `calendar.date_to_iso_days/3` |
| `Calendrical.Interval.year(year, calendar)`, `Calendrical.Interval.quarter(year, quarter, calendar)` | 2 | `calendar.year(year)`, `calendar.quarter(year, quarter)` |
| `Calendrical.weeks_to_days(n)` | 8 | `n * calendar.days_in_week()` |

### A callback is to be added, or made required (25 calls, and the 7 probes)

Each is in Calendrical's `TODO.md`, or is added to it by this section.

| Tempo calls | Calls | Becomes |
|---|---|---|
| `Calendrical.traditional_months(year, calendar)` | 3 | `calendar.traditional_months(year)`, new |
| `calendar.ordinal_month_from_traditional/2` behind a probe | 2 probes | the same call with no probe, the callback required of every calendar |
| `Calendrical.Interval.weeks_in_month(year, month, calendar)`, `Calendrical.Interval.week(year, month, nth, calendar)` | 3 | `calendar.weeks_in_month(year, month)` and the dates of a month's nth week, new |
| `Calendrical.Interval.quadrimester/3`, `Calendrical.Interval.semester/3` | 2 | `calendar.quadrimester(year, n)`, `calendar.semester(year, n)`: back on the behaviour, decided 2026-10-10 |
| `Calendrical.named_month(year, month, calendar)` | 1 | `calendar.named_month(year, month)`, new |
| `Calendrical.date_from_day_of_year(year, day, calendar)` | 11 | `calendar.date_from_day_of_year(year, day)`, new: the inverse of `day_of_year/3` |
| `Calendrical.Base.Common.composite?(calendar)`, and Tempo's own deciders of a year's start | 1 | the months a year has and the days a month has, new |
| `calendar.cardinal_day/3` and `calendar.months_in_year/0` behind probes | 4 probes | the same calls with no probe, each required |
| `Calendrical.Gregorian.leap_year?/1`, `Calendrical.Gregorian.day_of_week/4` | 2 | the cycle a calendar's years come round in, new, and then the calendar's own `leap_year?/1` and `day_of_week/4` |
| `Calendrical.Lunisolar.solar_term/3`, `Calendrical.Chinese.location/1`, and `calendar.location/1` behind a probe | 2, and 1 probe | a solar term asked of the calendar, which every calendar answers, decided 2026-10-10 |

### A function of dates, which takes no calendar (22 calls)

| Tempo calls | Calls | What it is |
|---|---|---|
| `Calendrical.next(date, unit)`, `Calendrical.previous(date, unit)` | 16 | the period after or before a date: the date's own calendar is asked inside it |
| `Calendrical.Kday.kday_on_or_before/2`, `kday_on_or_after/2`, `nth_kday/3` | 6 | a weekday on or about a day, counted on the day's number |

Decided 2026-10-10: the first becomes `calendar.plus/6` and the callbacks that give a period (`year/1`, `month/2`, `week/2`), with no new callback; the second stays, since it counts days of a week and asks no calendar anything.

### Not a question to a calendar (12 calls)

`Calendrical.additional_calendars/0` (3) and `Calendrical.calendar_from_cldr_calendar_type/1` (4) turn a name the notation carries into a module, where the notation carries one; `Calendrical.validate_calendar/1` (1) says whether a module is a calendar; `Calendrical.parse/2` (1) hands text to Localize; `Calendrical.Ecclesiastical.easter_sunday/1` and `orthodox_easter_sunday/1` (2) are events; `Calendrical.Lunisolar.solar_term_name/1` (1) is a name.

## Decisions

Taken by the user on 2026-10-10.

* **What a calendar is** — a module that implements the `Calendar` and `Calendrical` behaviours, and `Calendrical.validate_calendar/1` "needs only to check" that, which is cheap. The whole contract is checked nowhere: "The contract for Tempo is that calendars adhere to these behaviours and therefore breaking the contract is on the user - not us."

* **No constant for what a calendar answers** — "All calendars should implement `days_in_week/0` so that should NEVER be a constant in Tempo. Indeed any time we define a constant in Tempo is probably a bad smell and need to be carefully checked." Every constant Tempo defines is to be read, which is a task of its own below.

* **Callbacks, not functions beside the behaviour** — `weeks_in_month` "should be a straight up `Calendrical.Behaviour` callback", where it is a function of `Calendrical.Interval`. What Tempo asks of a calendar is to be a callback wherever it is the calendar's own to answer.

* **`nil` for a calendar** — "Keep it, in one accessor": a value built by hand with `calendar: nil` still reads as the Gregorian, and every place that settles it calls one function.

* **The names of months and of weekdays** — "Month and weekday names should come from Localize": `Tempo.explain/1` holds none.

* **The cycle a calendar's years come round in** — asked with what each choice would answer, and chosen: a Calendrical callback. Tempo neither keeps 400 as a fact of the notation's calendar nor gives the cycle up, which would have made 30 February every year an error after 10,000 periods where it is an empty set in 20 ms, and refused a month with no fixed start where it is 28 to 31 days. Measured for the choice: a year's layout repeats after 400 years in the Gregorian and the Indian calendars, 28 in the Julian, Coptic and Ethiopic, 210 in the tabular Islamic, and not within 1,200 in the Hebrew, Persian and Umm al-Qura.

* **Every call is a callback** — "Basically, all calendar calls in Tempo should be `calendar.some_callback` It really should be as simple as that." And of Calendrical: "We need the Calendrical API to be primarily standard and consistent across all calendars, added to the Calendrical.Behaviour to enforce that. We do not want Tempo - or any other consumer - to have to know anything at all about a specific individual calendar. We may tolerate some exceptions for certain classes of calendars - like lunisolar - but only after consultation." So the target for the 84 calls Tempo makes into Calendrical's own modules with a calendar in hand, and for its 7 probes, is none: each is a required callback every calendar answers. The user gave leave on the same day to make the changes in Calendrical that its `TODO.md` lists.

* **Four things about "every call a callback"** — asked on 2026-10-10 with what each choice would answer, and each taken as recommended. Tempo stops calling `Calendrical.next/3` and `previous/3` and asks `calendar.plus/6` and the callbacks that give a period, and `Calendrical.Kday` stays, since it counts weekdays on day numbers and asks no calendar anything. `quadrimester/2` and `semester/2` go back on the behaviour. A solar term is answered by every calendar: a lunisolar one at its own meridian, and the default at the traditional reference Tempo uses today. An ISO-style week of a calendar of months is of that calendar's own year, by new callbacks, and `iso_week_of_year/3` keeps its meaning, the Gregorian ISO week of the day.

* **The rest as recommended** — "Implement the plan until completion", so each is taken as it was recommended: a calendar of weeks stays a second shape of date, known in one function; no fast path is keyed on a calendar's name, each being removed and measured; a period's values are two new callbacks; and what only the Gregorian has is decided case by case (`SKIP` asks `days_in_month/1`, the seasons are the notation's, and the cycle of 400 years is still to decide).

## What this plan has not done

* **It has read `lib/` alone** — the tests' own support code holds calendar knowledge too (`test/support/matrix/calendar_census.ex` names calendars to choose its dates), and `tempo_holidays` and `tempo_sql` are not read.

* **It has not read Localize** — what Localize asks of a calendar is its own list, and one contract for the three libraries is the first change proposed for Calendrical.

* **It has measured what it removed, and nothing else** — each fast path and each held name that went was timed before and after, and the timings are with its task under Done. No path that was not changed has been timed.

## Found on the way

* **A count taken for a number of values** — `Tempo.Validation` sums `calendar.months_in_year/1` over a group of years for the months the group has (`lib/validation.ex:642`), and a composite answers with its last month that has days: 12 for England's 1751, which has ten.

* **A year written to its day in a set** — `Tempo.extend_resolution(~o"1751Y{3..5}M", :day)` in `Calendrical.Reform.England` is `1751Y{3..5}M1D`, which names 1 March 1751, a day that year does not have.

* **Half of a year written as a group it is not** — `1751Y1H` there is written `1751Y1G4MU`, which reads back as the months 1 to 4.

Each is the third cause above, and goes with the task for `Tempo.UnitValues`.

## Tasks

* [ ] **Ask the calendar where a callback exists** — the 25 calls of the first table of "Every call a callback", a function at a time, each compared before and after: nothing in Calendrical changes for them.

* [ ] **Calendrical's callbacks, then Tempo's calls of them** — the second table: each callback is added to `Calendrical.Behaviour` for every calendar, with leave from the user of 2026-10-10 to make the change there, and Tempo's call follows when its lock moves to it.

* [ ] **The period after or before a date, asked of its calendar** — the 16 calls of `Calendrical.next/3` and `previous/3` become `calendar.plus/6` and the callbacks that give a period, each compared before and after; nothing in Calendrical changes for them. The 6 calls of `Calendrical.Kday` stay.

### Blocked

* [ ] **The cycle a calendar's years come round in** — blocked on a callback that gives it (Calendrical's `TODO.md`), decided by the user on 2026-10-10. Tempo holds 400 for the Gregorian by name: a rule that names no date of any year is known so after one year of each of the 14 kinds a cycle has (`@years_of_a_cycle`, `@kinds_of_year`, `kind_of_year/1` and `no_date_in_year?/3` in `lib/tempo.ex`), and the network solver keeps the lengths of 400 years and counts a month as twelve to a year on its axis (`lib/tempo/network/normalize.ex`): 10 lines that name the calendar and 6 constants. With the callback each asks the calendar, the kinds of year are found by asking a cycle's years for their months and first weekday, and the Julian, Coptic, Ethiopic, Indian and tabular Islamic calendars are answered as the Gregorian is.

* [ ] **`Tempo.UnitValues` asks for values** — blocked on the two callbacks that give a period's values (Calendrical's `TODO.md`).

* [ ] **Week dates through Calendrical** — blocked on the date of an ISO week date, the ISO weeks of a year and the week date of a date, each by ISO 8601's rule over a calendar's own year (Calendrical's `TODO.md`). The 7 lines that name a calendar for it compute with the pair of the Gregorian and `Calendrical.ISOWeek`: 5 in `lib/tempo/unit_values.ex`, 1 in `lib/math.ex` and 1 in `lib/enumeration/zone.ex`, which reads a date back as a week date for those two alone, since `iso_week_of_year/3` is the week of the Gregorian year in every calendar (`Calendrical.Hebrew.iso_week_of_year(5786, 3, 4)` is `{2025, 48}`, the Monday of Tempo's `5786W10`).

* [ ] **Names, traditional months and solar terms** — blocked on `cardinal_day/3` and the four callbacks of traditional months being required, and on a solar term asked of a calendar (Calendrical's `TODO.md`).

### Done

* [x] **Traditional months from the year's list of them** — the place of a leap month, the name of a month at a place and a set or a mask of traditional months are read from the year's months as Calendrical names them (`Calendrical.traditional_months/2`), where the calendar was probed for `leap_month/1`, `traditional_leap_month/1`, `lunar_month_of_year/2` and `new/3`: the probes are 7 of the 37, and `location/1` is the one function called that no behaviour declares. One month by its number still asks `ordinal_month_from_traditional/2` behind a probe, since the list takes 4.5 ms in the Chinese calendar where that takes 0.2. Each of the three calls is `Calendrical.traditional_months(year, calendar)`, a function beside the behaviour, and becomes `calendar.traditional_months(year)` when it is a callback. 2026-10-10.

* [x] **A year on the solver's axis, built one way** — `Tempo.Network.Normalize.date_at/2` read a year's position as ISO 8601 text for the Gregorian calendar and built it with `Tempo.new/1` for another; both give the same value for the 15 years compared, from 100,000 before the year 0 to 9,999,999 after, so the clause by name is gone. The lines that name a calendar are 18 of the 128. 2026-10-10.

* [x] **The names of months and of weekdays, from Localize** — the user, 2026-10-10: "Month and weekday names should come from Localize". `Tempo.explain/1` held the Gregorian calendar's twelve and the seven weekdays and asked Localize for another calendar's; it holds neither now and asks for both in every calendar (`Localize.Date.to_string/2` for a month, by the calendar module and the year, and `Localize.Calendar.display_name/3` for a weekday by ISO 8601's number). What it writes is the same for the 44 values and rules compared before and after, and the tests measure the names against ISO 8601-1's own tables. Measured before and after, in microseconds: a day 44 and 83, a month 45 and 81, a yearly rule on the 2nd Monday of March 21 and 63, a weekly rule on three weekdays 21 and 41, a monthly rule that names five months 25 and 192: a month's name is 30 µs from Localize and a weekday's 3. The lines that name a calendar are 19 of the 128, and the constants a calendar would answer 7. 2026-10-10.

* [x] **ISO 8601's week dates, in the one module** — `Calendrical.ISOWeek` is the calendar of the notation's week dates and is named where the Gregorian is (`Tempo.Calendars.weeks/0`, and the guard `is_notation_weeks/1`). What asks is a question of the notation and of no calendar's making: the sigil's `W`, how a value in it is written, a rule that names no calendar of its own (`start_in_repeat_calendar/2`), and a selector's weeks, which the notation's two calendars number alike. The census counts each use of the two guards, 21 and 4, where it counted none. The lines that name a calendar are 20 of the 128. 2026-10-10.

* [x] **Every constant Tempo defines, read** — section 8 of the census reads each of the 252 module attributes with its class. Nine are a calendar's to answer, and each is under a task: six with the cycle, two with the names, and `@any_year` with the values a period has. 2026-10-10.

* [x] **`SKIP`, the seasons and two computations asked of the calendar** — a rule's `SKIP` is written beside a day past the fewest days any month of its calendar has, which the calendar says with no year (28, 29 and 5 for the Gregorian, the Hebrew and the Ethiopic), where 28 was held for the Gregorian and any day taken for another; ISO 8601-2's seasons ask the one module whether a value is in the notation's calendar; a weekday is asked of the date's own calendar, and a season's nth day of the calendar its first day is in. The lines that name a calendar are 26 of the 128. 2026-10-10.

* [x] **No fast path by name** — the 17 are gone. Fifteen clauses answered for the Gregorian what the general path answers, and are removed; a day count is turned to a date by the calendar's own `date_from_iso_days/1` in every calendar; and a step of months or years takes its short path for any calendar that does not step its own dates, where it took it for the Gregorian by name. Measured before and after, in microseconds: a day shifted by a month 7.0 and 8.0, by a year 3.1 and 4.0, by ten days 2.8 and 3.1; 36 monthly occurrences 684 and 766, 36 yearly 472 and 553; a day to its interval 3.3 and 4.2; a year extended to its day 1.1 and 1.4; a date read 14.7 and 15.4; a relation 17.2 and 18.8; and a Hebrew day shifted by a month 14.1 and 5.6. The cost is the two questions a step asks of its calendar (whether it is a composite, and where its year begins), which go when a calendar gives a period's values. 2026-10-10.

* [x] **Weeks or months, asked once** — `Tempo.week_based_calendar?/1` is the one function that asks a calendar its base: the other 15 direct calls of `calendar_base/0` ask it, as the three private copies of it do. What its callers then do with the answer is the second shape of date, which stays. 2026-10-10.

* [x] **No probe of a required callback** — the 19 are gone, each calendar passing through the accessor before it is asked, and a division of a year is asked of `Calendrical.Interval` by its name where it was applied by a variable. The probes that remain are of the six optional callbacks and of `location/1` and `new/3`, each waiting on Calendrical. The era of a year is asked by `year_of_era/3` of the year's first day, where `year_of_era/1`, which no behaviour declares, was probed and called. 2026-10-10.

* [x] **A value placed on the time line by its own calendar** — `Tempo.Compare` asks a value's calendar for the count of its day (`date_to_iso_days/3`, and `Calendrical.iso_days/4` for a year, a month and a day), where it converted to Gregorian fields and counted in the Gregorian by name, with a fast path for it. Measured before and after: a comparison of two Gregorian days 962 and 998 ns, a relation 17.5 and 17.4 µs, a Hebrew day with a Gregorian one 7.6 and 6.6 µs. 2026-10-10.

* [x] **What is outside, in one module** — the zone database's calendar (`Tempo.Calendars.zone/0`), a rule's (`rule/0`), Elixir's own (`native/0`) and the notation's are named in the one module, and a guard there (`is_notation/1`) is what the lines that left the Gregorian's name out of text or took `nil` for it now ask: the 26 outside lines and the 9 of text name no calendar, and the lines that do are 54 of the 128. 2026-10-10.

* [x] **A value's calendar is read through one accessor** — `Tempo.Calendars` is the one module that names a calendar: `effective/1`, `of/1`, `settled/1`, `default/0`, `native/1` and `validated/1`, which asks `Calendrical.validate_calendar/1`. No line outside it defaults to the Gregorian or maps `Calendar.ISO`, where 38 did, and the lines that name a calendar are 89 of the 128. 2026-10-10.

* [x] **`plus/6` alone** — all 19 calls are at the arity the behaviour declares and the 5 probes of `plus` are gone; the declaration of every unit is in Calendrical's `TODO.md`. 2026-10-10.

* [x] **The week's seven days** — the 16 lines are none: 12 ask `days_in_week/0`, 2 were cron's own weekdays, and 2 went with Tempo's own working-out of a month's weeks, which is Calendrical's (`Calendrical.Interval.weeks_in_month/3` and `week/4`). 2026-10-10.

* [x] **Calendrical's changes written up** — nine items in Calendrical's `TODO.md`, for the pass on its behaviour. 2026-10-10.

* [x] **The decisions** — taken by the user. 2026-10-10.
