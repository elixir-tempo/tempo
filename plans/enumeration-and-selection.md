# Enumeration and selection in every calendar

**Status:** in progress, 2026-10-09

Enumeration and selection are core capabilities of Tempo, and the requirement (user, 2026-10-04) is confidence that they work correctly for all calendar types, at all resolutions, on all full and partial date and time combinations. This document says what that space is, what in it is verified, what is wrong, what is missing and what has not been measured yet, and sets the order of the work. It continues [plans/validated-core.md](validated-core.md), whose matrix it extends.

## What verified means

An answer is verified when it agrees, member by member, with an answer worked out apart from the library: from `Date`, `:calendar` and the calendar module's own functions, with none of Tempo's code. Agreement between two of Tempo's functions is not verification, since both can be wrong the same way, and a value or a named error is not verification either, since a wrong answer is a value. That is the lesson of the selections the matrix did not measure: every one of them passed.

Three instruments hold such answers:

* **The reference** — `Tempo.Matrix.Reference` and the 59 properties of `test/tempo/reference_test.exs`, for a date or a time written in whole numbers: the span it covers and the values its walk yields. It generates the Gregorian calendar and the Hebrew, Persian, Coptic and civil Islamic ones at year, month and day.

* **The selections** — `Tempo.Matrix.Selections`, for a selection: each part written seven ways in 42 periods, a week of a month among them since 2026-10-09, and the days of the period every part names.

* **The calendar census** — a run of 2026-10-04 of a script, and since 2026-10-09 a test (`test/tempo/calendar_census_test.exs`), of every calendar module Calendrical ships but the astronomical ones: each form of a value on three dates, and thirty selections, against spans counted from the calendar's `valid_date?/3`, `months_in_year/1` and `weeks_in_year/1`.

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

### Run again on 2026-10-08

The same 1,170 cells on the code of `0deedac`. Thirty-eight changed, and none is an answer that became wrong.

| Calendar | Full forms | Selections | No year |
|---|---|---|---|
| The sixteen calendars of months | 441 of 441 | 480 of 480 | not verified |
| ISOWeek | 15 of 15 | 20 of 20 | not verified |
| NRF | 15 of 15 | 4 of 20 | not verified |
| Julian.March25 | 15 of 27 | 3 of 30 | not verified |
| All | 486 of 498 | 507 of 550 | 0 of 122 |

* **`Reform.England`** — the six cells of its month with days missing are right (36 of 36).

* **`ISOWeek`** — the eight cells of a week selected in a year, and of a year's weekdays, are right.

* **`NRF`** — the sixteen cells flagged are held to ISO 8601's week, which is not the calendar's. Held to `Calendrical.NRF.week/2`, a week, a weekday of one and a year's weekdays, each written four ways in 2025, 2026 and 2028, are the calendar's in all 36 cells, as `ISOWeek`'s 36 are held to its own.

* **`Julian.March25`** — the census's own answer is the reading decided against on 2026-10-05 (a month is the nth the calendar counts, so `2026Y6M` is the dates of `month(2026, 6)`, which are August's), and its year raises in the census itself. Its nine full forms and twelve selections in a year that differ therefore say nothing, and its fifteen selections in a month are the named refusal (`:not_built`).

So the census as a test needed two answers it did not have: the calendar's own week in a calendar of weeks, and the decided reading of a year that starts within its months. It has both since 2026-10-09, and with them every full form in the 22 calendars and every selection in the eighteen it measures them in are right.

## Status

| Area | Status |
|---|---|
| Full dates and times, every resolution, in a calendar of whole months | Done |
| Selections in a year and a month, in a calendar of whole months | Done |
| Full dates and times in a calendar of weeks | Done |
| Every shape of a Gregorian value (the matrix) | Done |
| One implementation of a unit's values and of a count from the end | Done |
| A selection in a calendar of weeks | Done |
| A weekday selected in a Gregorian week | Done |
| A month whose days are not `1..n` (a reform) | Done |
| A year that starts within the months | Done for values, Open for selections |
| A value with no year in a calendar other than the Gregorian | Done |
| `inspect/1` and `to_iso8601/1` on a selection under an hour | Done |
| `Tempo.select/2` against the selection | Done |
| A recurrence with no year and a rule | Done |
| The astronomical calendars | In progress |
| Shapes, intervals and recurrences in other calendars | Done |
| A zone with another calendar | Open |

## Bugs

Each is a wrong answer, a raise or two functions that disagree, with the cells it accounts for.

* **A month with days missing** — `Reform.England`'s September 1752 has the days 1, 2 and 14 to 30. The walk of `1752Y9M` yielded 1 to 19, `1752Y9M3D` was read though no such day existed, and `1752Y9M20D` was an `InvalidDateError` though it did: Tempo took a month's days to be `1..days_in_month/2`, here 19. Six cells. Done 2026-10-05: in a composite calendar `Tempo.UnitValues` lists a month's days and a year's months from the calendar, its values may be several ranges, and a date is stepped by the calendar (`test/tempo/composite_calendar_test.exs`). England's years before 1751, whose months the composite numbers as their dates do, are an item of `TODO.md`.

* **A year that starts within the months** — in `Julian.March25` the year 2026 runs from 25 March to the next 24 March. The walk of `2026Y` yielded months 1 to 12 as the Julian months of those numbers, the first three of which are in the year after the fourth, and March was one month though the year turns within it. Decided 2026-10-04 (a month is the nth month of the year as Calendrical's `month/2` counts, and a date keeps its month's own number) and done 2026-10-05 for values in the four Julian calendars: the year, its months, their dates, steps, durations, quarters, groups, masks, set operations and text are held to Calendrical's `year/1` and `month/2` in `test/tempo/year_start_test.exs`. The twelve selection cells of that calendar, which the census's own answer also got wrong, are still wrong. A month selected with a day is the month the date names, as it is read (decided 2026-10-05); a selection inside a month or a year the calendar counts is to build, and is refused until it is: `Tempo.NotBuilt` returns a `Tempo.ConversionError` whose reason is `:not_built` for it, for a season, for a step by days from several months or years, and for a month of a `Calendrical.Reform.England` year before 1751 (done 2026-10-05, held in `test/tempo/not_built_test.exs` beside what is still answered).

* **The weeks of a year with no year** — no calendar counts them without a year, so the stepper holds a literal 52, `53W` has no span and `54W` is read. An item of `TODO.md`, with a decision: a count from Calendrical, or a week with no year that is neither bounded nor stepped.

* **A selection in a calendar of weeks** — a week selected in a year is the whole year, in `ISOWeek` and `NRF` alike. Six cells of the matrix. A year's weekdays, which stopped at its twelfth week, are those of each of its weeks since 2026-10-04 (nine cells). Done 2026-10-07: a week selected in a year is the week, and on 2026-10-08 each is the calendar's own `week/2` in both calendars.

* **A weekday selected in a Gregorian week** — `2026Y25WL3KN` was the week's Monday whatever the weekday, in a value and in a recurrence's rule (42 cells). Fixed 2026-10-05 with the days of a Gregorian week being given as calendar dates: the day selected was a week and a day of it, which the conversion to a span cut back to its week.

* **A selection under an hour cannot be written** — `inspect/1` and `Tempo.to_iso8601/1` raised a `FunctionClauseError` on `2026Y6M15DT10HLT30MN`. 35 cells. Done 2026-10-06: both write it.

## Feature gaps

* **What Calendrical already answers** — two things first thought missing there are not. It lists the days a month has (`Calendrical.Interval.month/3` is the range of September 1752's nineteen dates in `Reform.England`, and `valid_date?/3` answers each), and it counts the months of a year that starts within them from the year's start (`month/2` of a Julian year-start variant, and `year/1` for its days in order). Both bugs are Tempo's, and the second needs a decision: what a month of such a year is.

* **A month in a calendar of weeks** — `6M` in `ISOWeek` or `NRF` is a `ConversionError` when it is read, and stays one (decided 2026-10-04).

* **A day with no month, selected in a year** — a day of the year (decided 2026-10-04); built 2026-10-05 as one reading, `Tempo.RRule.Selection.read_in_its_period/1`, which the conversion, the RRULE writer and `explain/1` ask, with `Tempo.select/2` reading a constraint the same way where it is merged onto a year. Held in `test/tempo/day_with_no_month_test.exs` against `Date` and in the matrix's selections.

* **A weekday in a calendar whose week does not start on Monday** — `K` counts the days of the week the value is in: the calendar's own in a calendar of weeks, ISO 8601's in a calendar of months (decided 2026-10-05). The value `2026Y25W3K` in `NRF` is its third day, Tuesday, and so are a selection and a rule there since 2026-10-05, where they read Wednesday. A selector given to `Tempo.select/2` is read in the calendar it is written in (decided the same day, when it was seen that `Tempo.workdays/1` is a Gregorian `K` value): `~o"3K"` selects Wednesdays from an `NRF` week and `~o"3K[u-ca=nrf]"` Tuesdays from any span. Held in `test/tempo/week_calendar_test.exs` against the weekday Elixir gives each date.

* **Traditional months in a selection** — a set, a mask or a count from the end. In `TODO.md`.

## Not yet measured

* **The astronomical calendars** — `Chinese`, `Korean`, `Vietnamese`, `LunarJapanese`, `Islamic.Observational` and `Islamic.Rgsa`: a cell takes seconds to minutes, so the census of them was stopped. `Islamic.Observational` agreed in the 24 full-form cells whose answer could be worked out in eight seconds, and its year's could not; the others are not measured.

* **A value with no year** — measured since 2026-10-09 in the census test, for a month, a day of one and a day of the week. Not measured: a week with no year, which no calendar counts (an item of `TODO.md`), and a month with no year in a calendar whose year starts within its months, where it is the month a date names (`1M` is January's 31 days in `Julian.March25`) and with a year the nth the calendar counts (`2026Y1M` is the seven days from 25 March): a question for the user, in `TODO.md`.

* **A selection in `NRF`** — the answer the census works out for a week is ISO 8601's, so its sixteen failing cells say nothing. Held to the calendar's own `week/2` on 2026-10-08 they are right; that answer is not yet in the census or the matrix.

* **Shapes in other calendars** — measured since 2026-10-09 in the census test for a set, a range, a count from the end, a mask and an unspecified unit; a group and qualification are generated for the Gregorian calendar alone.

* **Intervals, sets and recurrences in other calendars** — measured since 2026-10-09 in the census test: the walk of an explicit span, the occurrences of a recurrence, a recurrence's rule and `Tempo.select/2`.

* **A zone with another calendar**, **a fraction of a second**, and **a selection of hours or minutes** in any calendar but the Gregorian.

* **Fiscal and configured calendars** — `Calendrical.FiscalYear` and a calendar made with `Calendrical.Config`.

## Decisions

* 2026-10-05, the user, four questions on how the decisions of the same day are held, each answered as recommended: a rule read from an RRULE states what RFC 5545 takes from its start, as ISO 8601-2 Annex C.4 has a converted rule do (its day of the month written into the rule, so a month that lacks it is passed over, and an occurrence as long as its start is precise), and all of Annex C.3 is stated, a weekly rule's weekday too; `Tempo.RRule.to_string/1` writes an ISO 8601 recurrence that keeps the last day as the RRULE that says the same (`BYMONTHDAY=-1`, or the last of the days up to the start's) and refuses the rest; and an event that cannot be computed, for its year or its name, is an error where it was no occurrence.

* 2026-10-05, the user, four questions put at the end of the second run through the Correctness items, each answered as recommended: a computed event expands in a year, a month and a week, each of its days that falls in the period, and limits a day and finer (it expanded a year alone, so the Easter of a month or a week was not selected); a rule read from an RRULE, iCalendar or JSCalendar omits a start's day that a period does not have, as RFC 5545 says, and an ISO 8601 recurrence keeps the period's last day, the rule holding which as RFC 7529's `SKIP` names it; `Tempo.RRule.to_string/1` writes the allowed equivalent of a part RFC 5545 forbids for the frequency and refuses the rest; and a yearly rule's day of the month with no month stays a day of DTSTART's month. The first three are the Correctness items of `TODO.md`.

* 2026-10-05, the user, four questions put during the run through the Conformance items, each answered as recommended and each an item of `TODO.md`: a day (`D`) with no month selected from a week is the day of the month, each day of the week that is that day of its month (the explicit value `2026Y25W3D` is not read, and a day of the week is `K`); a week selected from a year is that ISO week-year's week, though it start in the December before, as the value `2026YL1WN` is; a selector as coarse as its period or coarser keeps the period, a filter, as the selection form gives and a weekday selector does, the plain constraint being brought to the resolver for it; and an interval's end of four digits in the basic format stays a year, as ISO 8601-1 §5.5.1 allows the omission only where it is unambiguous, with an error that says so.

* 2026-10-05, the user, six questions put after the run through the Correctness items, each answered as recommended and each an item of `TODO.md`: a month selected with a day, in a year that does not begin with its first month, is the month the date names; `K` counts the days of the week the value is in (the third day of an `NRF` week is Tuesday; a selector given to `Tempo.select/2` is a value of its own and is read in its own calendar, asked again the same day); `Tempo.select/2` refuses a selector that holds a month or a day of another calendar than the span's (built the same day, for a year and a week too, the Gregorian and the ISO week calendars sharing ISO 8601's weeks, and held in `test/tempo/select_test.exs`); a week of a calendar of months converts to an interval with `unit: day` (built the same day: `Unit.walked_by/2`); a day of the year from the walk is the calendar date (built the same day: the walk yields dates, and a shift reaches each date a set of them names, held in `test/tempo/day_of_year_test.exs` against `Date`); and for 2.0 an area known to answer wrongly and not yet built returns a named error (built the same day: `Tempo.NotBuilt`).

* 2026-10-04, the user — a finding in Calendrical is confirmed against its latest `main` and then recorded in its `TODO.md`.

* 2026-10-04, the user — once validation, the walk, `Tempo.select/2`, the selection's resolver and `Tempo.explain/1` rest on one implementation, the next step is strong confidence in a single implementation of the set operations. It is an item of `TODO.md` and will have a plan of its own.

* 2026-10-04, the user — one implementation of a count from the end, for validation, the walk, `Tempo.select/2`, the selection's resolver and `Tempo.explain/1`, so that there is one place to verify.

## The one implementation

Counting from the end was written five times, each copy covering a different part of the space. `Tempo.UnitValues` is the one implementation (2026-10-04): `in_period/3` for the values a unit takes, `in_any_year/3` for those it takes with no year (the values every year has, and those of the year that has the most) and `named/2` for the values a written value names, verified in `test/tempo/unit_values_test.exs` against the calendar asked another way in fourteen calendars: with no year, against the fewest and the most each of 121 years gives. A selection, `Tempo.select/2`, the walk, the reading of a value and `Tempo.explain/1` count through it:

| Where | Function | Used by |
|---|---|---|
| `lib/validation.ex` | `conform/2` is `Tempo.UnitValues.resolve/2` | Reading a value |
| `lib/enumeration.ex` | moved to `Tempo.UnitValues` | The walk |
| `lib/tempo/select.ex` | moved to `Tempo.UnitValues` | `Tempo.select/2` |
| `lib/tempo/rrule/selection.ex` | moved to `Tempo.UnitValues` | A selection |
| `lib/explain.ex` | counts through `Tempo.UnitValues` where a unit's values are fixed | `Tempo.explain/1` |

`Tempo.Iso8601.Unit.value_range/2` is a sixth piece: the values a clock unit and a weekday take, with `:unknown` for every unit that depends on the date. Only `Tempo.UnitValues` reads it now.

With no year the calendar was asked in five modules, each reading its three answers (a count, the counts its years run over, or none) its own way: the reading of a value, the masks, the stepper, rounding and `explain/1`. All five take `in_any_year/3` now, and no other module calls a calendar's `days_in_month/1` or `months_in_year/0`. What needs a year is one rule, read against its two ranges: a value below the last every year has is followed by the next; the last value of the year that has the most is the last in every year that has it, and is followed by the first of the next period; a value between the two is followed by one or the other by the year, and is an `UnanchoredError`. So a reform calendar, which answers nothing with no year, has a day whose hours are walked and whose span is refused: the hours ask nothing of the calendar, and the span asks for the day after.

They become one module with two questions, each asked of Calendrical and of nothing else:

* **The values a unit takes** — given a unit, the units before it and the calendar: the months of a year, the days of a month, the days and weeks of a year, the days of a week, the hours of a day. With no year it is the values every year has, or that the answer waits for a year. It is where a month with days missing and a year that starts within the months are answered once, for every caller.

* **The values a written value names among them** — a number, a count from the end, a range resolved end by end, a set: in order and once each, with what the period lacks either an error (reading a value) or passed over (a selection), as the caller asks.

Validation, the walk, `select/2`, the selection and `explain/1` call it and hold no arithmetic of their own. `select/2` held one count of its own, the weeks of a month (`weeks_in_month/3`), until 2026-10-05, when a week selected from within a month became a named refusal (the week-of-month item of `TODO.md`); and it merged a constraint onto its base and read the result as a value, so a constraint that was no selection was resolved by the reading of a value and not by the selection's resolver. The two are one since 2026-10-07 (decided by the user that day): a constraint whose parts the resolver counts is resolved as the selection of the same parts, a week of a month among them (`Tempo.UnitValues.weeks_of_month/3`), and a point either form selects is the value it is. The merge is left for what the resolver has no reading for, a mask, a fraction of a second or a group in a constraint, the ends of a span and a day of a week of a month, which is an item of `TODO.md`; the two forms give the same members in 1,296 of the 1,347 cells of thirty bases and fifty-three parts both write. It is verified in one place: its own property test against `Tempo.Matrix.Selections`' counting, in every calendar of the census.

## Tasks

* [ ] **The astronomical calendars, measured** — `Chinese`, `Korean`, `Vietnamese`, `LunarJapanese`, `Islamic.Observational` and `Islamic.Rgsa` with a time limit that suits them: a cell takes seconds, the census's own answer for a year could not be worked out in eight, and `1447YL{2..-1}ON` did not convert in eight in `Islamic.Observational` (2026-10-08). Shapes, intervals and recurrences in a year that starts within its months wait on the items of `TODO.md` for such a year.

### Done

* [x] **One implementation** — `Tempo.UnitValues`, then each of the five callers moved to it in turn, the matrix green after each. Moved: a selection's resolver, `Tempo.select/2`'s count from the end and its weekdays, and the walk's reading of a range that reaches past a period's values (the walk reads everything else through the reading of a value). `Tempo.Validation.conform/2` is `resolve/2`, and a set or a range of a clock unit is held to the unit's values. What a unit takes with no year is `in_any_year/3`, for every module that asked. The reading of a value and its masks take a unit's values in a year from `in_period/3` (`validation.ex`, `mask.ex`, the calendar weeks of `group.ex`). A step from a value asks `following/4` and `preceding/4` what comes after and before a value, `first/3` and `last/3` for the value a carry or a borrow lands on, and `at_or_before/4` for the day a step of months lands on (`math.ex`, which has no count of its own left but the weeks of a year with no year and a fraction of a year in months). A selection's resolver takes a month's days, a year's months and their ends from it too (`selection.ex`). `Tempo.explain/1` expanded a range as Elixir's, which names nothing where the range reaches the end; it counts a weekday, an hour, a minute and a second, and a month where a year's months can be counted, through `resolve/2` and `named/2`, and words a day, a week and a position, whose period a rule selects in each of, as they are written. Still arithmetic of its own in the resolver: the nearest weekday of cron's `W`, which steps a day or two within a month. Not to move: the arithmetic of a group and of a fraction (the nth day of a group of months, half of a year), which counts a period's units, where the calendar's own count is the answer. All five callers were moved by 2026-10-04, and the week counts on 2026-10-09: how many weeks a year has, where each starts, the date a day of one is and which week of its year a week is (`date_from_iso_week/4`, `iso_weeks_in_year/2`, `calendar_weeks_in_year/2`, `calendar_week_range/3`, `week_starts/3`, `week_number/4`) are the module's, and it asks nothing of the reading of a value. 2026-10-09.

* [x] **The measure widened to every calendar** — the census test holds, in each of its eighteen calendars whose year begins with its first month or is of weeks: each selection again as the rule of a recurrence of its period within that period (520) and as `Tempo.select/2` of the period (388, a position being a selection's alone and some parts no value's text); and a set, a range, a count from the end, a mask and an unspecified unit, an interval of days and one of months or weeks, and a recurrence by days, by months or weeks and by years (238 values), each with its members and its walk worked out from the calendar. The calendar-generic answer for a week is the calendar's own `week/2`. Every one is right. 2026-10-09.

* [x] **A value with no year, measured** — the census test holds every month and every day of each, and every day of the week, with no year, to the calendar's own counts (`months_in_year/0`, `days_in_month/1`): the span each covers on the cycle of the longest year, the values its walk yields, that its span needs a year where what follows it depends on one, and that no year has it. 5,632 values in eighteen calendars, of which 47 need a year and 204 are no value; a reform calendar counts nothing with no year, so each of its months and days needs one. Every one is right. `Tempo.Matrix.Extent` now closes the cycle of a calendar whose years differ in their months (the Hebrew thirteenth month read as empty). The walk and the conversion already ask one place what needs a year: only `Tempo.UnitValues` calls a calendar with no year. 2026-10-09.

* [x] **The census as a test** — `test/tempo/calendar_census_test.exs` holds a value in each full form, converted and walked, and a selection of each kind to `Tempo.Matrix.CalendarCensus`, which works each answer out from the calendar's own functions and `Date`: 22 calendars (the 19 of the census and the Julian years from 1 March, 1 September and 25 December), 579 full forms and 520 selections, in five seconds. A calendar of weeks is held to its own `week/2`, and a year that starts within its months to the calendar's `year/1` and `month/2`, which `Tempo.Matrix.Extent` now reads such a value by. It is a test of its own and not a class of the matrix's corpus, where every operation would run on a thousand values more. Not in it: the astronomical calendars, a selection in a year that starts within its months (not built) and a value with no year. 2026-10-09.

* [x] **A week selected in a year of a calendar of weeks** — a year and a week of it are combined, so the selection is the week where it was the year: the six cells of the baseline, which lists none. The weekday in a Gregorian week, 42 more, was fixed on 2026-10-05. 2026-10-07.

* [x] **A selection under an hour** — `inspect/1` and `to_iso8601/1` write a selection that follows a time of day; the 35 cells of the baseline. 2026-10-06.

* [x] **A month with days missing** — the days of such a month come from Calendrical (its `valid_date?/3`, since `month/2` of a year that begins on 25 March lists a part of March), not from `1..days_in_month/2`, and a unit's values stop being a run: `in_period/3`'s range, the counts `named/2`, `resolve/2` and `from_end/2` make in it, and `first/3`, `last/3`, `following/4` and `preceding/4`, are the places to change, and their callers none. `Reform.England` is the measure: September 1752 (1, 2, 14 to 30), and 1751, which has no January or February and a March of the days 25 to 31. Timed, since a step asks on every value. 2026-10-05.

* [x] **A year that starts within the months** — the walk, and everything else that reads a value, follows Calendrical's `month/2` and `year/1`: `Tempo.UnitValues.year_begins_with_first_month?/2`, `first_date/2`, `dates_of_month/3` and `month_of_date/4`. Selections there are an item of `TODO.md`. 2026-10-05.

* [x] **`Tempo.explain/1` on the one implementation** — the last of the five callers. A range that reaches the end is worded by its ends, a weekday, a month and a time of day are counted and named, and a selection's minutes, seconds and the month of its period are worded where they were left out. A probe of 1,288 explanations (selections and rules, 72 parts on seven periods and five recurrences, four calendars) raised in 356 and raises in none; the baseline's nineteen `explain/1` cells are fixed, and it lists 83. 2026-10-04.

* [x] **A selection's resolver asks the one implementation** — the weekdays of a month and of a year, the clamp of a day to its month, the nearest weekday, a day of the year and the bounds of a month and a year. The months of a year are those the resolver's own `period_values/2` gives, which for a calendar of weeks are its weeks, so a year's weekdays no longer stop at week twelve: nine cells of the baseline, which lists 102. A probe of 5,892 selections, rules, RRULE strings and cron expressions in eight calendars changed in 33 cells, all of them those; four rules timed the same. 2026-10-04.

* [x] **The units before a selection are read as a value** — `Validation.resolve_units/2` reads them apart from the selection, so a month, a week or a set of days of the year its year does not have is refused, and a count from the end is counted in its year. 444 cells of the same probe, each a period its year does not have. 2026-10-04.

* [x] **A step asks the one implementation** — `following/4`, `preceding/4`, `first/3` and `last/3` in `Tempo.UnitValues`, and the stepper's with-year and no-year paths made one on them. A value below the last every year has is followed by the next with no year asked for, so the year's count is asked only where the answer depends on it (28 February) or the calendar cannot say without a year (a reform's). Three probes hold it to the same answers: 133,110 cells of single steps, shifts and spans in twelve calendars, and the 24,484 and 13,951 of values with a year and with none; none changed. Timed against the commit before, best of three: a day step 16% faster, a walk of a year's days 8% and of a Hebrew year's 18%; a month step 16% slower and a walk of months 11%; a day step back 26% slower and a day of the year's step 40%, neither on the path of a walk. 2026-10-04.

* [x] **The reading and the masks take a unit's values in a year from `in_period/3`** — sixteen places that wrote `1..calendar.days_in_month(year, month)` and its kin. Two probes hold it to the same answers: 24,484 cells of values with a year (months, days, days of the year and weeks, in and out of range, read, spanned and walked in thirteen calendars) and the 13,951 with none; none changed. `in_period/3` checks that a year has the month before it asks for the month's days: asked for a thirteenth month's, a Gregorian calendar answers 31, a Julian raises and a Hebrew answers 0. Timed against the commit before: a date read is unchanged, a walk of a year's days 9% slower and a walk of a month's hours 12% faster. 2026-10-04.

* [x] **With no year, one place asks the calendar** — `Tempo.UnitValues.in_any_year/3`, taken by the reading of a value, the masks, the stepper, rounding and `explain/1`. Of 13,951 cells of a probe of values with no year in eleven calendars (the reading, the span, the walk, eight steps, rounding and `explain/1`), 75 changed, each a thirteenth month of a Hebrew or a Chinese year that was refused and is answered. 2026-10-04.

* [x] **With no year, every calendar is read as the Gregorian is** — Tempo locks Calendrical `6bbb560`, whose `days_in_month/1` and `months_in_year/0` answer with no year in every calendar built on its behaviour and in the Julian calendars: a month of one length is converted and walked, and a day of a month converted, in the Julian, Persian, Coptic, Ethiopic, Indian, Islamic and Hebrew calendars, where the walk raised or the conversion refused. Of the fourteen calendars probed, no month of the Umm al-Qura or the Chinese has one length, a reform calendar answers nothing with no year, and a calendar of weeks reads no month. The census of full forms and selections is unchanged at the new lock (489 of 498, 514 of 550). 2026-10-04.

* [x] **The reading of a value counts through the one implementation** — `conform/2` is `Tempo.UnitValues.resolve/2`; a set or a range of hours, minutes, seconds or weekdays past the unit's values is an `InvalidDateError`, as one of days is. 2026-10-04.

* [x] **The walk reads a range through the one implementation** — a range that reaches past a period's values names its own values there, in the order written and on its own steps. 2026-10-04.

* [x] **`Tempo.select/2` reads its counts through the one implementation** — its count from the end and the weekdays a constraint names; 24 cells of the baseline, which lists 111. 2026-10-04.

* [x] **A recurrence with no year and a rule** — a rule counted in a date is an `UnanchoredError` on a start with no year, where it raised or searched without end. Its class in the matrix comes with the census. 2026-10-04.
