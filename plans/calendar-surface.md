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
| Functions that decide by a calendar's kind, the accessor apart | 47, at 176 calls | 1, at 1 call |
| Lines that hold the days of a week | 16 | 0 |
| Lines that hold a fact of the Gregorian calendar | 15 | 0, or in the one module |
| Lines that hold the reader's bounds | 6 | 0 |
| Constants that are a calendar's to answer | 13 of 250 | 0 |

## Decisions

Taken by the user on 2026-10-10.

* **What a calendar is** — a module that implements the `Calendar` and `Calendrical` behaviours, and `Calendrical.validate_calendar/1` "needs only to check" that, which is cheap. The whole contract is checked nowhere: "The contract for Tempo is that calendars adhere to these behaviours and therefore breaking the contract is on the user - not us."

* **No constant for what a calendar answers** — "All calendars should implement `days_in_week/0` so that should NEVER be a constant in Tempo. Indeed any time we define a constant in Tempo is probably a bad smell and need to be carefully checked." Every constant Tempo defines is to be read, which is a task of its own below.

* **Callbacks, not functions beside the behaviour** — `weeks_in_month` "should be a straight up `Calendrical.Behaviour` callback", where it is a function of `Calendrical.Interval`. What Tempo asks of a calendar is to be a callback wherever it is the calendar's own to answer.

* **`nil` for a calendar** — "Keep it, in one accessor": a value built by hand with `calendar: nil` still reads as the Gregorian, and every place that settles it calls one function.

* **The rest as recommended** — "Implement the plan until completion", so each is taken as it was recommended: a calendar of weeks stays a second shape of date, known in one function; no fast path is keyed on a calendar's name, each being removed and measured; a period's values are two new callbacks; and what only the Gregorian has is decided case by case (`SKIP` asks `days_in_month/1`, the seasons are the notation's, and the cycle of 400 years is still to decide).

## What this plan has not done

* **It names what each class of place becomes, and not yet each place** — the census lists every one. Three tasks begin by reading their places one at a time, and say so: `nil` as a calendar, the 96 places that ask weeks or months, and the 9 fast paths.

* **It has read the numbers a calendar would be asked for, and not every constant** — a module attribute that holds any other number, or a list or a map of them, is not yet in the census.

* **It has measured no speed** — no fast path is known to be needed, and none is known not to be.

* **It has read `lib/` alone** — the tests' own support code holds calendar knowledge too (`test/support/matrix/calendar_census.ex` names calendars to choose its dates), and `tempo_holidays` and `tempo_sql` are not read.

* **It has not read Localize** — what Localize asks of a calendar is its own list, and one contract for the three libraries is the first change proposed for Calendrical.

## Found on the way

* **A count taken for a number of values** — `Tempo.Validation` sums `calendar.months_in_year/1` over a group of years for the months the group has (`lib/validation.ex:642`), and a composite answers with its last month that has days: 12 for England's 1751, which has ten.

* **A year written to its day in a set** — `Tempo.extend_resolution(~o"1751Y{3..5}M", :day)` in `Calendrical.Reform.England` is `1751Y{3..5}M1D`, which names 1 March 1751, a day that year does not have.

* **Half of a year written as a group it is not** — `1751Y1H` there is written `1751Y1G4MU`, which reads back as the months 1 to 4.

Each is the third cause above, and goes with the task for `Tempo.UnitValues`.

## Tasks

* [ ] **The guards that take `nil` for the Gregorian** — the lines that test `calendar in [Gregorian, Calendar.ISO, nil]` ask the accessor first, with the tasks for what is outside and for fast paths.

* [ ] **No probe of a required callback** — needs nothing upstream.

* [ ] **What is outside, in one module** — needs nothing upstream.

* [ ] **Weeks or months, asked once** — needs nothing upstream.

* [ ] **No fast path by name** — each measured as it goes.

* [ ] **The Gregorian asked, not named** — needs nothing upstream.

* [ ] **Every constant Tempo defines, read** — a section of the census for each module attribute that holds a number, and each one a calendar would answer asked of it.

* [ ] **What only the Gregorian has** — `SKIP` and the seasons first; the cycle is to decide.

### Blocked

* [ ] **`Tempo.UnitValues` asks for values** — blocked on the two callbacks that give a period's values (Calendrical's `TODO.md`).

* [ ] **Week dates through Calendrical** — blocked on the date of an ISO week date and the ISO weeks of a year (Calendrical's `TODO.md`).

* [ ] **Names, traditional months and solar terms** — blocked on `cardinal_day/3` and the four callbacks of traditional months being required, and on a solar term asked of a calendar (Calendrical's `TODO.md`).

### Done

* [x] **A value's calendar is read through one accessor** — `Tempo.Calendars` is the one module that names a calendar: `effective/1`, `of/1`, `settled/1`, `default/0`, `native/1` and `validated/1`, which asks `Calendrical.validate_calendar/1`. No line outside it defaults to the Gregorian or maps `Calendar.ISO`, where 38 did, and the lines that name a calendar are 89 of the 128. 2026-10-10.

* [x] **`plus/6` alone** — all 19 calls are at the arity the behaviour declares and the 5 probes of `plus` are gone; the declaration of every unit is in Calendrical's `TODO.md`. 2026-10-10.

* [x] **The week's seven days** — the 16 lines are none: 12 ask `days_in_week/0`, 2 were cron's own weekdays, and 2 went with Tempo's own working-out of a month's weeks, which is Calendrical's (`Calendrical.Interval.weeks_in_month/3` and `week/4`). 2026-10-10.

* [x] **Calendrical's changes written up** — nine items in Calendrical's `TODO.md`, for the pass on its behaviour. 2026-10-10.

* [x] **The decisions** — taken by the user. 2026-10-10.
