# Enumeration and selection in every calendar

**Status:** in progress, 2026-10-04

Enumeration and selection are core capabilities of Tempo, and the requirement (user, 2026-10-04) is confidence that they work correctly for all calendar types, at all resolutions, on all full and partial date and time combinations. This document says what that space is, what in it is verified, what is wrong, what is missing and what has not been measured yet, and sets the order of the work. It continues [plans/validated-core.md](validated-core.md), whose matrix it extends.

## What verified means

An answer is verified when it agrees, member by member, with an answer worked out apart from the library: from `Date`, `:calendar` and the calendar module's own functions, with none of Tempo's code. Agreement between two of Tempo's functions is not verification, since both can be wrong the same way, and a value or a named error is not verification either, since a wrong answer is a value. That is the lesson of the selections the matrix did not measure: every one of them passed.

Three instruments hold such answers:

* **The reference** — `Tempo.Matrix.Reference` and the 59 properties of `test/tempo/reference_test.exs`, for a date or a time written in whole numbers: the span it covers and the values its walk yields. It generates the Gregorian calendar and the Hebrew, Persian, Coptic and civil Islamic ones at year, month and day.

* **The selections** — `Tempo.Matrix.Selections`, for a selection: each part written seven ways in 31 periods, and the days of the period every part names.

* **The calendar census** — a run of 2026-10-04 (`calcensus.exs` in the session's scratchpad, to be made part of the matrix) of every calendar module Calendrical ships: each form of a value on three dates, and thirty selections, against spans counted from the calendar's `valid_date?/3`, `months_in_year/1` and `weeks_in_year/1`.

## The space

| Dimension | Values |
|---|---|
| Calendar types | Solar; solar with a thirteenth month; lunar; lunisolar with a leap month; weeks; reform; year starting within a month; fiscal and configured |
| Resolutions | Year, month, week, day, hour, minute, second, fraction of a second |
| Full forms | A year down to a second; a week and a day of it; a day of the year |
| Partial forms | No year (`6M`, `6M15D`, `25W`, `3K`, `T10H`); a unit left out (`2026YT17H`, `2026Y6MT17H`) |
| Shapes | Sets, ranges, masks, unspecified units, groups, counts from the end, qualification |
| Enumeration | The walk of a value (`Enum`), of an interval, of a set, of a recurrence; `to_interval/2`; `to_interval_set/2` |
| Selection | A selection in a value (`L…N`); a recurrence's rule (`F…`); `Tempo.select/2` |

The calendar modules, by type: `Gregorian`, `Julian`, `Buddhist`, `Roc`, `Japanese`, `Indian` and `Persian` (solar); `Coptic`, `Ethiopic` and `Ethiopic.AmeteAlem` (a thirteenth month); `Islamic.Civil`, `Tbla`, `UmmAlQura`, `Observational` and `Rgsa` (lunar); `Hebrew`, `Chinese`, `Korean`, `Vietnamese` and `LunarJapanese` (lunisolar); `ISOWeek` and `NRF` (weeks); `Reform.England` and `Reform.Sweden` (reform); `Julian.March25`, `Dec25`, `March1` and `Sept1` (a year that starts within the sequence of months).

## What the census measured

Nineteen calendars, 1,170 cells. A cell passes when it agrees with the calendar-only answer.

| Calendar | Full forms | Selections | No year |
|---|---|---|---|
| Gregorian | 27 of 27 | 30 of 30 | not verified |
| Julian | 27 of 27 | 30 of 30 | not verified |
| Buddhist, Roc, Japanese | 81 of 81 | 90 of 90 | not verified |
| Indian, Persian | 54 of 54 | 60 of 60 | not verified |
| Coptic, Ethiopic, Ethiopic.AmeteAlem | 81 of 81 | 90 of 90 | not verified |
| Islamic.Civil, Tbla, UmmAlQura | 81 of 81 | 90 of 90 | not verified |
| Hebrew | 27 of 27 | 30 of 30 | not verified |
| Reform.Sweden | 27 of 27 | 30 of 30 | not verified |
| Reform.England | 30 of 36 | 30 of 30 | not verified |
| Julian.March25 | 24 of 27 | 18 of 30 | not verified |
| ISOWeek | 15 of 15 | 12 of 20 | not verified |
| NRF | 15 of 15 | 4 of 20 | not verified |
| All | 489 of 498 | 514 of 550 | 0 of 122 |

A full form is a year, a month, a day, an hour, a minute, a second, a day of the year, and a time on a year and on a month (in a calendar of weeks: a year, a week, a day of one and a time on each), each converted and walked. A selection is a month, a month and day, a day of the year, a day, a weekday and a position, each written five ways (a number, a count from the end, a range that reaches the end, the first and the last, and a value the period lacks).

So for a date or a time with a year, in the fifteen calendars of whole months that begin their year with their first month, and in `Reform.England` outside the month of its reform, every cell is right: the span, the walk at every resolution, and every selection of the thirty. That part of the requirement is met and measured. What is not right is below, and it is in four places: a month with days missing, a year that starts within the months, a calendar of weeks, and a value with no year.

## Status

| Area | Status |
|---|---|
| Full dates and times, every resolution, in a calendar of whole months | Done |
| Selections in a year and a month, in a calendar of whole months | Done |
| Full dates and times in a calendar of weeks | Done |
| Every shape of a Gregorian value (the matrix) | Done |
| One implementation of a unit's values and of a count from the end | In progress |
| A selection in a calendar of weeks | Open |
| A weekday selected in a Gregorian week | Open |
| A month whose days are not `1..n` (a reform) | Open |
| A year that starts within the months | Open |
| A value with no year in a calendar other than the Gregorian | Open |
| `inspect/1`, `to_iso8601/1` and `explain/1` on a selection | Open |
| `Tempo.select/2` against the selection | Done |
| A recurrence with no year and a rule | Done |
| The astronomical calendars | In progress |
| Shapes, intervals, recurrences and zones in other calendars | Open |

## Bugs

Each is a wrong answer, a raise or two functions that disagree, with the cells it accounts for.

* **A month with days missing** — `Reform.England`'s September 1752 has the days 1, 2 and 14 to 30. The walk of `1752Y9M` yields 1 to 19, `1752Y9M3D` is read though no such day existed, and `1752Y9M20D` is an `InvalidDateError` though it did. Tempo takes a month's days to be `1..days_in_month/2`, here 19. Six cells.

* **A year that starts within the months** — in `Julian.March25` the year 2026 runs from 25 March to the next 24 March. The walk of `2026Y` yields months 1 to 12 in that order, the first three of which are in the year after the fourth, and March is one month though the year turns within it. Three cells, and the twelve selection cells of that calendar, which the census's own answer also gets wrong.

* **A value with no year, in a calendar other than the Gregorian** — the conversion and the walk disagree in both directions. In `Persian`, `Coptic`, `Ethiopic`, `Indian`, `Islamic.*` and `Hebrew` a month (`6M`) converts and its walk raises an `UnanchoredError`, and a month and day (`6M15D`) is refused by the conversion and walked. In `Julian` it is the other way round: `6M` is refused and walked. It is so in each of the ten month calendars probed, and none of the 122 cells with no year is verified.

* **A range of a clock unit past its last value** — `2026Y6M15DT{22..25}H` is read, its walk yields hours 24 and 25, and `to_interval/2` refuses it; minutes and seconds alike, where a range of days or months past the end is an `InvalidDateError` when it is read. The reading of a value holds a set or a range of a date unit to the unit's values and not one of a clock unit. Found with the walk's step, 2026-10-04; not measured by the matrix, whose shapes hold no range past a unit's end.

* **A selection in a calendar of weeks** — a week selected in a year is the whole year, and a year's weekdays stop at its twelfth week, in `ISOWeek` and `NRF` alike. Fifteen cells of the matrix, and eight of the census's in `ISOWeek`.

* **A weekday selected in a Gregorian week** — `2026Y25WL3KN` is the week's Monday whatever the weekday, in a value and in a recurrence's rule. 42 cells.

* **A selection under an hour cannot be written** — `inspect/1` and `Tempo.to_iso8601/1` raise a `FunctionClauseError` on `2026Y6M15DT10HLT30MN`. 35 cells.

* **`Tempo.explain/1` on a range that reaches the end** — a `CaseClauseError` or a `MatchError`. 19 cells.

## Feature gaps

* **A month's length with no year** — Calendrical answered `{:error, :undefined}` for every month of twelve calendars and the Julian calendars answered unlike the Gregorian. Both were recorded in its `TODO.md` and are fixed there at `6bbb560` (2026-10-04); Tempo locks `ad5ff77`, so its own work with no year starts with moving the lock.

* **What Calendrical already answers** — two things first thought missing there are not. It lists the days a month has (`Calendrical.Interval.month/3` is the range of September 1752's nineteen dates in `Reform.England`, and `valid_date?/3` answers each), and it counts the months of a year that starts within them from the year's start (`month/2` of a Julian year-start variant, and `year/1` for its days in order). Both bugs are Tempo's, and the second needs a decision: what a month of such a year is.

* **A month in a calendar of weeks** — `6M` in `ISOWeek` or `NRF` is a `ConversionError` when it is read. An open decision in `TODO.md`.

* **A day with no month, selected in a year** — undecided, in `TODO.md`.

* **A weekday in a calendar whose week does not start on Monday** — whether `3K` in `NRF` is the third day of its week or Wednesday is not written down, and the selection and the value may differ. To decide.

* **Traditional months in a selection** — a set, a mask or a count from the end. In `TODO.md`.

## Not yet measured

* **The astronomical calendars** — `Chinese`, `Korean`, `Vietnamese`, `LunarJapanese`, `Islamic.Observational` and `Islamic.Rgsa`: a cell takes seconds to minutes, so the census of them was stopped. `Islamic.Observational` agreed in the 24 full-form cells whose answer could be worked out in eight seconds, and its year's could not; the others are not measured.

* **A value with no year** — no answer is worked out apart from the library for any calendar. The matrix checks that the walk and the conversion agree, for the Gregorian calendar alone.

* **A selection in `NRF`** — the answer worked out for a week is ISO 8601's, so twelve of its sixteen failing cells say nothing yet.

* **Shapes in other calendars** — sets, ranges, masks, groups and counts from the end are generated for the Gregorian calendar and, for dates, the Hebrew.

* **Intervals, sets and recurrences in other calendars** — the walk of an explicit span and the occurrences of a recurrence, and a recurrence's rule in any calendar but the Gregorian, the Hebrew and `ISOWeek`.

* **A zone with another calendar**, **a fraction of a second**, and **a selection of hours or minutes** in any calendar but the Gregorian.

* **Fiscal and configured calendars** — `Calendrical.FiscalYear` and a calendar made with `Calendrical.Config`.

## Decisions

* 2026-10-04, the user — a finding in Calendrical is confirmed against its latest `main` and then recorded in its `TODO.md`.

* 2026-10-04, the user — once validation, the walk, `Tempo.select/2`, the selection's resolver and `Tempo.explain/1` rest on one implementation, the next step is strong confidence in a single implementation of the set operations. It is an item of `TODO.md` and will have a plan of its own.

* 2026-10-04, the user — one implementation of a count from the end, for validation, the walk, `Tempo.select/2`, the selection's resolver and `Tempo.explain/1`, so that there is one place to verify.

## The one implementation

Counting from the end was written five times, each copy covering a different part of the space. `Tempo.UnitValues` is the one implementation (2026-10-04): `in_period/3` for the values a unit takes and `named/2` for the values a written value names, verified in `test/tempo/unit_values_test.exs` against the calendar asked another way in fourteen calendars. A selection, `Tempo.select/2` and the walk read through it; the other two copies are still where they were:

| Where | Function | Used by |
|---|---|---|
| `lib/validation.ex:360` and `:1513` | `from_end/2`, `conform/2` | Reading a value |
| `lib/enumeration.ex` | moved to `Tempo.UnitValues` | The walk |
| `lib/tempo/select.ex` | moved to `Tempo.UnitValues` | `Tempo.select/2` |
| `lib/tempo/rrule/selection.ex` | moved to `Tempo.UnitValues` | A selection |
| `lib/explain.ex:1758` | `ordinals_phrase/1`, `expand_int/1` | `Tempo.explain/1` |

`Tempo.Iso8601.Unit.value_range/2` is a sixth piece: the values a clock unit and a weekday take, with `:unknown` for every unit that depends on the date.

They become one module with two questions, each asked of Calendrical and of nothing else:

* **The values a unit takes** — given a unit, the units before it and the calendar: the months of a year, the days of a month, the days and weeks of a year, the days of a week, the hours of a day. With no year it is the values every year has, or that the answer waits for a year. It is where a month with days missing and a year that starts within the months are answered once, for every caller.

* **The values a written value names among them** — a number, a count from the end, a range resolved end by end, a set: in order and once each, with what the period lacks either an error (reading a value) or passed over (a selection), as the caller asks.

Validation, the walk, `select/2`, the selection and `explain/1` call it and hold no arithmetic of their own. `select/2` keeps one count of its own, the weeks of a month (`weeks_in_month/3`), which is the week-of-month item of `TODO.md`; and it still merges a constraint onto its base and reads the result as a value, so a constraint that is no selection is resolved by the reading of a value and not by the selection's resolver. Whether the two become one is open, and waits on the reading of a day with no month. It is verified in one place: its own property test against `Tempo.Matrix.Selections`' counting, in every calendar of the census.

## Tasks

* [ ] **One implementation** — `Tempo.UnitValues`, then each of the five callers moved to it in turn, the matrix green after each. Moved: a selection's resolver, `Tempo.select/2`'s count from the end and its weekdays, and the walk's reading of a range that reaches past a period's values (the walk reads everything else through the reading of a value). To move: the reading of a value (`conform/2`, with the values of a unit with no year), `Tempo.explain/1`; then `Tempo.Iso8601.Unit.value_range/2` and the week counts of `Tempo.Validation` come into it.

* [ ] **The census in the matrix** — every calendar module as a generated class of `Tempo.Matrix.Corpus`, with the calendar-only answer as a check, so that the table above is a test.

* [ ] **A selection in a calendar of weeks, and a weekday in a Gregorian week** — 57 cells of the baseline.

* [ ] **A selection under an hour, and `explain/1` on a range to the end** — 54 cells of the baseline.

* [ ] **A value with no year, measured** — Tempo's lock moved to Calendrical's `6bbb560`, which answers a month's length with no year in every calendar; then an answer worked out apart from the library, and the walk and the conversion made to agree in every calendar.

* [ ] **The measure widened** — shapes, intervals, recurrences and rules in every calendar; a calendar-generic answer for a week, for `NRF`; the astronomical calendars with a time limit that suits them.

* [ ] **A month with days missing** — the walk and the reading of a month take its days from Calendrical (`Calendrical.Interval.month/3`), not from `1..days_in_month/2`.

* [ ] **A year that starts within the months** — once what a month of such a year is has been decided, the walk follows Calendrical's `month/2` and `year/1`.

### Done

* [x] **The walk reads a range through the one implementation** — a range that reaches past a period's values names its own values there, in the order written and on its own steps. 2026-10-04.

* [x] **`Tempo.select/2` reads its counts through the one implementation** — its count from the end and the weekdays a constraint names; 24 cells of the baseline, which lists 111. 2026-10-04.

* [x] **A recurrence with no year and a rule** — a rule counted in a date is an `UnanchoredError` on a start with no year, where it raised or searched without end. Its class in the matrix comes with the census. 2026-10-04.
