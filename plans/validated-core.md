# A validated core

**Status:** in progress, 2026-10-04

All five stages are done and the six objectives hold, the fourth by the checks that keep two paths in step rather than by one path replacing the other (see One reader). What the plan leaves open is the four questions at the end of Findings, which are the user's, and the rows of the published table that name an error, which are features to build.

Tempo's defects are found by hand, one cell at a time, and each fix turns up more. This plan replaces that loop with a generated matrix that runs every public operation against every shape of value, a reference the core is checked against, and one rule for where a shape's meaning is defined. When it is done, the core is validated by machine, every other cell is right or a named error, and a new feature is added by turning a named error into an answer the matrix checks.

## The problem

On 2026-10-03 thirty-three items were closed and fifteen new ones were still open at the end of the day. Over the last four items, four were closed and eleven logged. The list does not converge, for three reasons.

* **The defects are in the exotic shapes** — all eleven open correctness items concerned masks, unspecified units, groups of sets, values with no year or intervals with no end. None concerned a plain date, time, interval, duration or zone.

* **Every function reads the shapes for itself** — masks are matched in 9 files of `lib/`, unspecified units in 10, groups in 13 and selections in 15, against 96 public functions in `Tempo` alone. That is a grid of thousands of cells, each written by hand, and most recent defects were two code paths reading one shape differently.

* **Discovery is by hand** — a fix is probed around its edges and each broken neighbour is logged. There is no total, so no trend can be trusted.

## Constraints

* **The public API keeps its names** — no function is renamed or removed. What a function answers changes where the standard, or the project's own architecture, contradicts what was documented: the user allowed breaking changes for 2.0 on 2026-10-03, and each is listed under Decisions and in the CHANGELOG.

* **ISO 8601 and the extensions stay whole** — everything that parses today parses, and nothing that works today is removed. A named error replaces only a raise, a hang or a wrong answer.

* **The 2.0 goal is unchanged** — this plan is the footing the remaining features are built on, not a narrowing of them.

## Objectives

These are the exit criteria. The plan is done when all six hold.

1. **Total** — every operation of the matrix, on every value of the corpus, returns a value or a named error inside its time limit. No raise that is not a Tempo exception, no hang, no error that is not an exception.

2. **Consistent** — for every value, what `Tempo.to_interval/2` covers is what the value's walk yields, and the measuring, comparing and set operations agree with what `to_interval/2` covers.

3. **Right** — for the core, the answers equal an independent reference built on `Date`, `NaiveDateTime` and Calendrical, for values generated as data and written in every spelling the standard allows.

4. **One reader** — `Tempo.to_interval/2`, backed by the walk, is where a shape's meaning is defined. No measuring function reads a shape for itself.

5. **An empty baseline** — the matrix's list of known failures is empty, and CI fails when a cell is added to it.

6. **A published matrix** — the docs carry a table of what each kind of operation gives each class of value, checked against the code, so the named errors that remain are the list of features still to build.

## Design

### The matrix

The columns are classes of value, each a short list of ISO 8601 texts in `test/support/matrix/corpus.ex`. The rows are the public operations of `Tempo` and the `Enumerable` and `Inspect` protocols, in `test/support/matrix/operations.ex`, each with the contract its kind implies.

| Kind | May return | May raise |
|---|---|---|
| Result | A value, `{:ok, value}` or `{:error, exception}` | Nothing |
| Predicate | `true` or `false` | A Tempo exception |
| Bang | A value | A Tempo exception or an `ArgumentError` |
| Walk | A value | A Tempo exception or an `ArgumentError` |
| Inspect | Text | Nothing, and no `#Inspect.Error` in the text |

Operations of two values run each corpus value against itself and against a small set of partners, in both orders.

### What a cell must do

* **Total** — the outcome is classed as a value, a named error, a named raise, a stray raise, a bad error or a timeout. The last three are failures, and a named raise is one where the kind forbids it. Each cell runs in a process of its own with a time limit and a heap limit, since the rule against `try` and `rescue` holds in test support too.

* **Consistent** — the extent of a result is the set of half-open spans it covers, computed in test support from the endpoints' own units. The extent of `to_interval/2` equals that of the walk, of `to_interval_set/2` and of a second conversion. Union, intersection and difference equal the same operations on extents, and the predicates and the Allen relation equal what the extents give.

* **Right** — a core value is generated as data, written in each spelling, read back, and compared with the span, the length, the walk and the conversions the reference computes from the data.

### Guarantee levels

Every value parses, validates and writes back at every level. The levels say what the measuring operations promise.

| Level | Classes | Promise |
|---|---|---|
| Core | Dates and times at every resolution, week and ordinal dates, zones, calendars, intervals, durations, recurrences with selections, sets and ranges of whole values | Right, against the reference, for what it generates |
| Extended | Masks, unspecified units, qualification, margins of error, significant digits, groups, counts from the end, selections in a value | Consistent, the walk being the definition |
| Open | Any shape the walk or the conversion has no answer for yet (a group of a set was the first, until 2026-10-04) | A named error from every measuring operation |

A class moves from open to extended when its meaning is defined in the walk, and the matrix then holds every operation to it. The matrix test holds the levels to what they say: every value of an extended class converts and can be walked, and an open class has a value that does not.

### The baseline

`test/support/matrix/baseline.exs` lists the cells known to fail. The matrix test fails when a cell fails that is not listed, and when a listed cell passes, so the list can only shrink and is rewritten only on purpose (`MATRIX_BASELINE=write`). It starts as the census and ends empty.

### One reader

A value's meaning is the spans its walk yields (`Tempo.Enumeration`). `Tempo.to_interval/2` may reach them by a shorter path, and the consistency check holds each such path to the walk. A function that measures, compares or combines works from `to_interval/2`'s result, and one that needs a single value or a single point says so through one shared check, with one named error.

What it came to: every function that measures, compares or combines reads a shape through `Tempo.to_interval/2` or the point its span starts at (`Tempo.Compare.start_point/1`), and the consistency checks hold each of them to the walk on every value of the corpus. The number of files that match a shape did not fall. Counted by the opening of each shape's tuple, masks were matched in 9 files of `lib/` before the branch and are in 9 now, unspecified units in 10 and 12, groups in 11 and 11, and selections in 15 and 15: the parser, the writer, `explain/1`, the stepper and the walk each still match them, to read, write, describe, refuse or define them. So there are still two paths to what a shape covers, the walk and `to_interval/2`'s shorter one, and it is the checks that hold the second to the first, not the absence of the second.

## Stages

1. **The census** — the corpus, the operations, the runner and the baseline, with the total check. The first run is the baseline and the measure of the problem.

2. **Total** — the stray raises, hangs and bad errors, taken class by class: the shared checks first, since one of them clears a row.

3. **Consistent** — the extent helper and the consistency checks, their census, and the paths that disagree with the walk brought to it.

4. **Right** — the reference and its generators for the core, in every spelling, and whatever they find.

5. **Published** — the matrix as a guide table checked against the code, `TODO.md`'s cell items replaced by it, and the gates.

## Decisions

### The user's, 2026-10-03

* **Breaking changes are allowed for 2.0** — "If your changes are more authoritative (ie match better against ISO8601 and against normal user expectations), adopt them - its a 2.0 release so we can have breaking changes. If unsure, ask." A documented behaviour that the standard, or the project's own architecture, contradicts is changed, with its docs and tests.

* **An interval is walked by the finer of its two ends' units** — so its values are the interval and none runs past its end (`2026/2026-03` is January and February). It was walked by its start's unit.

* **A time of day placed on a `:within` window starts on each day of it** — the documented reading stays: `T22H/T2H` within 15 June is 22:00 on the 15th to 02:00 on the 16th.

* **`relation/2` and the certainty functions return the floating error** — `{:error, %Tempo.FloatingTempoError{}}`, as they return every other. The predicates still raise it.

* **A value with no zone and a zoned one are refused everywhere** — the set operations return a `Tempo.FloatingTempoError` and the sorter raises it, as the predicates and `relation/2` did. `Tempo.ICal.available/2` reads a window with no zone in UTC.

* **An interval's end that is one bare number is the start's last unit** — `2026-06-15/20` ends on the 20th, `2026-06-15T10:30/45` at 10:45 and `2026-166/170` on day 170 (ISO 8601-1 §5.5.1). It was read as what the number is alone, century 20, and the interval ran backwards with no error. A century is written `20C`.

* **`round/2` rounds to the nearest, halves up** — to the start of the unit a value is in or of the next, by where the value starts in the unit as the unit is there, for every value, dates with times included. Half past ten was ten o'clock, 16 June rounded to 2027, and a date and time was refused.

* **A span with no year that ends where it starts is a whole turn** — `T0H/T0H` is the whole day and `T10H/T10H` the 24 hours from ten. It was empty, and `coalesce/1` wrote the whole day with an hour 24 that is not read back. With a year, equal ends are still empty.

* **A `:within` window with no zone bounds a zoned value in the value's zone** — 1 to 3 June, for a recurrence in New York, is those days in New York. It was read as UTC.

* **A Gregorian week date with a weekday is the calendar date, built or read** — `Tempo.new(year: 2026, week: 25, day_of_week: 3)` is `~o"2026-W25-3"`, which is 17 June, as an ordinal date is its date from both. The constructor kept the week date, a value the parser never gives. A week alone stays a week, and a calendar of weeks keeps its week dates.

* **`shift_zone/2` keeps the span a value names** — a value keeps its resolution where its span is one unit on the other zone's clock, and is otherwise the interval it is there. It gave the moment a value starts at, to the second: an hour, a day and a month each became one second.

### Mine

Taken without the user, by instruction, and flagged here.

* **A named error is an answer** — where a shape's meaning is not defined, an operation returns a Tempo exception in an error tuple, and the matrix counts that as passing. It is the list of features to build, not a list of defects.

* **Nothing that works is refused** — the levels describe what is promised, and no operation that gives a right answer today is made to refuse.

* **The parse layer** — the reference writes every core value in each spelling and reads it back, which holds the parser to the standard for the core. The grammar, its recogniser and the standard's examples stay with [plans/parser-formal-grammar.md](parser-formal-grammar.md).

* **A value built is the value read** — `Tempo.new/1` returns what the same components parse to: a zoned date with no time of day (which it refused), a fraction of a second (which it could not take), and the maps of a `Time` and a `NaiveDateTime` as of a `Date`.

* **A duration is counted from a point** — a start or an end that names one span (a mask, a group, a quarter) is the point the span starts at before a duration is counted from it, as it is in an interval written with two ends. `R3/2026-33/P3M` is three quarters and `202XY/P1Y` the year 2020, where each was refused.

* **Elixir's values keep the digits a second is written to** — `to_time/1`, `to_naive_datetime/1` and `to_datetime/1` give a whole second a precision of zero, as Elixir reads the same text, and a fraction its digits. They gave six, and `from_elixir/1` of the result was a microsecond.

* **Months, then days** — a duration's years and months are applied and the day brought into the month they land in before its days are counted, as `Date.shift/2` and every calendar library count: 29 July less five months and a day is 27 February.

* **A recurrence's occurrences are consecutive** — ISO 8601-1 §3.1.1.11. Each ends where the next starts, a multiple of the duration from the start: a month from 31 January is 28 February, and the next occurrence runs from there to 31 March.

* **A value placed on another takes the zone either has** — `at/2` of a date and a time of day in Paris is in Paris, whichever of the two carries the zone, and two zones are an error. `split/1` keeps the zone, the qualification and the metadata on both parts, so the two placed are the value.

* **The explicit time shift is written as ISO 8601-2 §7.4 writes it** — `Z2H0M`, with no sign ahead of UTC. `Z+2H0M` is still read.

* **A time of day is on a day** — written under a year, a month or a week with the day left out, it is that time on the first day of what is written, and the value holds the units (`2026T17` is `2026Y1M1DT17H`), as a clock unit left out is read as zero (ISO 8601-2 §7.10). The value held the gap, and each function read it its own way. Under a group it is the group's first day, what follows a group being one instance within it (§5.4.2): `2026Y2G3MUT10H` is 10:00 on 1 April, where it was that time in each of the group's months. `Tempo.new/1` and `at/2` build the same value.

* **An interval is shown in the unit it is walked by** — `Tempo.to_string/2` names its first and last values in the finer of its ends' units, and a week beside a date as the date its first day is.

* **The day of a week date is its day of the week** — `:day` truncates, rounds and extends a value on the week axis to it, in a calendar of weeks and for a Gregorian week, and every value of a calendar of weeks is on that axis, its year included.

* **Significant digits are their mask in every position** — every digit significant is the value itself (`1950S4` is 1950), and a count of none (`1950S0`) is a parse error, the count being a positive integer (ISO 8601-2 §4.4.3).

* **The published table counts functions** — a cell is how many of a kind's functions have an answer for one value of the class, with some argument or some other value beside it, and not how many cells of the run answered.

## Findings

### The census, 2026-10-03

The first run of the matrix was 66,778 cells over 173 values and about 130 operations, in three seconds. 3,523 cells failed, and they were a dozen causes rather than thousands.

| Cause | Cells | Resolution |
|---|---|---|
| A function of one value given an interval, a duration, a set or a recurrence (`FunctionClauseError`) | 3,036 | One shared error, a worded `ArgumentError`, or a `ConversionError` from a conversion |
| A comparison of a floating and a zoned value raised from a function that returns tuples | 288 | Documented and tested behaviour, so the contract records it and nothing changes |
| An error that is a bare atom (`:invalid_date`, `:no_resolution`) | 107 | An exception |
| An accessor reading a unit that holds several values (`MatchError`, `CaseClauseError`) | 49 | The accessor's `ArgumentError` |
| An accessor documented to raise for an ambiguous interval | 36 | The contract records it |
| A shift of a mask counted from the end (`Enum.EmptyError`) | 5 | The mask read by the walk's reader |
| A slow cell taken for a hang (a thousand years of weekends) | 2 | A smaller value of the same shape |

### Total, 2026-10-03

The baseline is empty: 67,725 cells, none failing. What changed in the library:

* **One error for the wrong kind of value** — about forty functions of one date or time value return, or raise where they have no error to return, the same worded `ArgumentError` for an interval, a duration, a set, a recurrence or any other term. Conversions return a `Tempo.ConversionError`.

* **Accessors read whole numbers** — `day_of_week/1`, `day_of_year/1`, `quarter_of_year/1`, `leap_year?/1` and `days_in_month/1` raise their documented `ArgumentError` for a unit that holds several values, and the component accessors read an interval written with a duration, or with an end that is a mask or a group, as the span it is.

* **A calendar is a module** — `to_calendar/2` returns an error for a calendar type (`:hebrew`), where it called it as a module.

* **Predicates of a span take any value with one** — `bounded?/1`, `empty?/1` and the length predicates convert a value or a set as `to_interval/2` does, and raise its error for what has no span.

* **An unspecified year is no place to measure from** — `duration/1`, `duration/2` and `to_relative_string/2` return a `Tempo.UnanchoredError` for `X*Y…`.

* **Masks have one reader** — `to_interval/2` and `shift/2` read a mask with `Tempo.Mask.candidates/4`, as the walk does. A mask counted from the end, and one with fewer digits than its unit, convert to the values they name, where they converted to the whole unit or to no date.

* **Spans between points** — an interval written with a duration, and each occurrence of a recurrence, from a start that is a mask, a group or an unspecified unit, is read as the two-ended form is.

### Every shape in every position, 2026-10-03

`Tempo.Matrix.Shapes` writes each of fourteen shapes in each position of each of fourteen forms: 352 more values, 130,473 cells in all. 139 cells failed, and every one came from the comparison of two values being given something that is not one point: a mask, a set, a group, an unspecified year. The comparison ordered the terms as they were written (a mask is a tuple, and a tuple sorts after every number), so most such comparisons did not raise: they answered wrongly. `Tempo.compare(~o"202XY", ~o"2026-06-15")` was `:gt`, `Tempo.Interval.new(from: ~o"202XY", to: ~o"2026-06-15")` was refused as ending before it started, and a month with no year was `:eq` to any dated day.

* **One comparison** — `Tempo.Compare.order/2` reads a value that is not one point as the point its span starts at (`Tempo.to_interval/1`), so comparing agrees with converting. Two values with no line to share (one with a year and one without, or two without that lead with different units) are a `Tempo.UnanchoredError`, the rule the set operations and the certainty functions already held their operands to. `Tempo.compare/3` raises it, and `Tempo.relation/2`, `Tempo.Interval.new/1`, `Tempo.IntervalSet.new/2`, `Tempo.select/2` and the set operations return it.

* **An unspecified year is no year** — `Tempo.anchored?(~o"X*Y6M")` is `false`, and every operation treats the value as it treats `~o"6M"`. `Tempo.at/2` places it on a year.

* **A unit after a group** — ISO 8601-2 §5.4.2 counts it from the group's start (`2018Y2G3MU50D` is the fiftieth day of the second quarter). The walk read it so only where validation could, and otherwise yielded the unit in each of the group's values, which is another meaning. Where it cannot be counted (no year for a group of months, or a set or a mask of days) the walk and `to_interval/2` return `Tempo.ConversionError` with reason `:counted_in_group`. A unit counted in each value by its nature (a weekday in a group of weeks) is walked so, and `to_interval/2` now gives those spans where it gave the group as written.

* **A span with no year ends at its cycle's end** — `~o"12M31D"` and `~o"7K"` run to the turn of the year and of the week, as `~o"T23H"` runs to the end of the day. The set operations cut such a span there (`Tempo.Interval.cycle_parts/1`), where they wrote a zero month and day.

### Consistent, 2026-10-03

`Tempo.Matrix.Extent` measures what a value, an interval or a set covers, with `Date`, `NaiveDateTime`, `DateTime` and Calendrical and without `Tempo.Compare`: the spans as microseconds on the time line, on the wall clock of no zone, or on the cycle a value with no year lies on. `Tempo.Matrix.Checks` holds each operation to it: the walk, `to_interval_set/2`, a second conversion, the text a value is written as, `duration/1` and `duration/2`, `empty?/1`, `bounded?/1`, the length predicates, `compare/2`, `relation/2` and the predicates on it, the set predicates, the certainty functions, the set operations and each function against its bang form. That is 43,056 cells. The first run had 390 that disagreed, of which 230 were the check expecting the wrong thing and 160 were the library.

* **A span with no year ends at its cycle's end** — `~o"T23H"` is `T23H/T0H`, since ISO 8601-1:2019 has no hour 24, and the end read as before the start: `empty?/1` was true, `relation/2` of the last hour and its half hour `:precedes`, `at_least?(~o"T23H", ~o"PT30M")` false, and `coalesce/1` lost the hour. `Tempo.Interval.Cycle` is now the one reader, and `relation/2`, the length predicates, `empty?/1`, `coalesce/1`, `Interval.new/2` and the set operations go through it. The set operations write their results as `to_interval/2` does, where they wrote hour 24.

* **A time of day against a day or more** — a duration with a unit the span does not track was added as nothing, so an hour was at least a day. On a cycle a length is measured, and a day, a month or a year is longer than any span of one.

* **An unspecified year in the walk** — the walk read `X*Y` as the current year and every other operation as no year. ISO 8601-2 §4.6.2 reads `X*Y12M28D` as 28 December of an unspecified year, so the walk now carries it: `X*Y6M` is the days of a June of no year, and `X*Y` alone names nothing to list.

* **`difference/2` with overlapping members** — a member of the second operand that ended inside one member of the first was dropped before the next, which it also cut. Two bookings that overlap each lost only one.

* **A year and a week** — `2027` and `2027-W01` compared as one moment, the week being the unit's first, where ISO 8601's first week of 2027 starts on 4 January. `relation(~o"2026", ~o"2026-W53")` was `:finished_by`.

* **Significant digits with a unit after them** — `1950S2Y6M` converted to the whole block, where its walk and its mask (`19XX-06`) are the June of each year.

* **Every week of a year** — `2026YXXW` converted to the calendar year, where the weeks of 2026 run from 29 December 2025 to 3 January 2027.

* **A wall time a clock shows twice** — the walk of `2026-10-25T02:30[Europe/Paris]` yielded each second twice, in turn, 120 values where `Enum.count/1` is 60. It yields the occurrence the value names.

* **`Interval.new/2` across calendars** — a Gregorian start beside a Hebrew end was named a day of the Hebrew year 2025. Each end keeps its calendar, and such an interval is written with the start's calendar named.

* **Smaller ones** — `duration!/2` had no clause for what is not a value; `bounded?/1` was false of a counted recurrence; a day of the year under a year with a margin of error was read as 1 January; a group of a set of hours was written without its time designator; a window that lies within one day had no time of day placed on it; ends on two axes or in two zones were walked and counted as their units.

### Every shape in pairs and at an interval's ends, 2026-10-03

The exhaustive corpus (`mix test --include exhaustive`) puts two shapes in one value and a shaped value at each end of an interval and at the start of a recurrence: 4,798 values, 1,198,298 cells, about seventeen minutes. Its first run failed 7,256 cells, from seven causes.

* **A group of a set before a mask** — `{1,2}G3MUXD` raised from every operation, the mask's reader taking a group of a set for a keyword pair. A group of a set is refused before anything reads the units around it.

* **The candidates of two masked values, pair by pair** — `overlap_certainty/2` of a value of 1,440 candidates against itself took 27 seconds, and one of 3,000 over a minute. Candidates that are spans in order are related along their runs: 71 and 188 milliseconds.

* **Two groups in one value** — `2G10DU2GT6HU30M` resolved its hours and left its days a group, a value its own text does not read back as. Groups resolve until they settle.

* **A margin of error beside another shape** — `2026±2Y2G3MU` and `2026±2Y-1M15D` kept the margin on the ends `to_interval/2` gave, or left the count from the end uncounted. The margin is dropped first, and significant digits before a unit are read as their mask.

* **Ends with no line to share** — `2020Y/X*Y6M15D` converted to itself, was walked for ever, and raised from the certainty functions. It is a `Tempo.UnanchoredError` from each.

* **Every week of several years** — `202XYXXW` converted to the calendar years, as the plain `2026YXXW` once did.

* **Smaller ones** — a qualified unit before a group and an interval's end holding a group of a set raised at parse; an accessor of an interval whose duration cannot be counted raised a `FunctionClauseError`; a recurrence from a group of a set raised its error where it returns it; a duration counted from a masked day of the year left the interval empty.

### Right, 2026-10-03

`Tempo.Matrix.Reference` works out what a core value means from the numbers it is built from, with `Date`, `NaiveDateTime`, `DateTime`, `Time` and a calendar module's own functions: its span, the values its walk yields, the Elixir value it converts to, and the same value a count of its unit on. `Tempo.Matrix.Spellings` writes it in each form ISO 8601 gives it (basic, extended and explicit, each zone form, each abbreviated end of an interval, each duration format) and `Tempo.Matrix.Generators` generates values, pairs chosen to meet in each of the thirteen Allen relations, intervals, durations, recurrences and sets. `test/tempo/reference_test.exs` holds `Tempo` to it in 59 properties. What they found:

* **A fraction of a second before a time shift behind UTC** — `2026-06-15T10:30:45.5-03:30`, the shape of an RFC 3339 timestamp west of Greenwich, was a parse error.

* **A duration of a year and twenty-one months** — `P1Y21M` was read as the season a date's month 21 is, and `P12Y30M` was an error about a solstice.

* **An interval's abbreviated end** — a bare number was read as a century (`2026-06-15/20` ran back to the year 2000), and a day and a time (`15T17:00`), a week and its day (`W26-5`) and a day of the week (`5`) were not read.

* **The constructor and the parser** — three differences, in Decisions above.

* **Conversions to Elixir's types** — the precision of a whole second, and `to_time/1` refusing a fraction.

* **`shift/3`** — a unit it does not know (`fortnight: 1`, `quarter: 1`) left the value where it was with no error, a value that is no number raised, months and days were applied in an order that differs from every other library's across a month's end, and a fraction added to a whole second was written to six digits.

* **`shift_zone/2`** — dropped a fraction of a second, and gave an hour, a day and a month as one second.

* **`round/2`** — the gaps the user's decision closes.

* **Recurrences across a month's end** — occurrences that left gaps.

* **`split/1` and `at/2`** — the zone, the qualification and the metadata dropped by the one, and a named zone on the time of day dropped by the other.

* **The explicit time shift** — written with a sign the standard does not have, and one with seconds (`Z7H33M14S`, the standard's own example) could not be written at all.

What the reference generates is the Gregorian date at every resolution, the time of day, the date and time, each zone form, a year, month and day of the Hebrew, Persian, Coptic and civil Islamic calendars, a week date of a calendar of weeks, the interval of two ends, the duration, the counted recurrence and the set and range of whole values. The other core classes of the corpus (an interval with one end, with no year or in two zones, a recurrence with no end or with a selection, a set within a unit) are held by the total and consistent checks and not by the reference.

### Published, 2026-10-03

`Tempo.Matrix.Table` writes the matrix as the table of [guides/operation-matrix.md](../guides/operation-matrix.md): a row for each class of the hand-written corpus, shown by its first value, and a column for each of nine kinds of operation. A cell counts functions, not the cells of a run: how many of the kind's functions have an answer for the value, with some argument and, for a function of two values, with some other value in either place. The functions of each column are listed with the table, and its last column names the errors of those with no answer. The matrix test fails when the guide's text is not what the run gives, when the guide does not say what an error the table names means, and when a class is not at the level the corpus puts it at.

Reading the table row by row against the cells behind it was a review of its own. What it found the checks could not see, each being an answer, or a named error, that agreed with `to_interval/2`:

* **The text of an interval** — `Tempo.to_string/2` took an interval's last value as one of its start's units before its end, so `2026/2026-03` was shown as "2026 – 2025", and a week beside a date as their years. The walk and the text now read an interval's unit from one function, and two properties of the reference hold the text to the span.

* **Significant digits** — `1950S2` was given to Localize as a year and a month it does not have, `1950S4` converted to an error where its walk yields the year, and `1950S0` was walked as the year 1950.

* **A calendar of weeks** — its year could not be shifted by a week or a day and had no length in either, and `:day` did not truncate or round a week date to its day.

* **A set written as its members** — `duration/1` refused `{2026Y,2030Y}` and measured `{2026,2030}Y`.

* **An interval written to its end** — `to_relative_string/2` refused `P1M/2026-07-01`.

* **A time of day under a year or a month** — a shape outside the corpus: `2026T17` held a gap where its month and day would be, compared as equal to any day of 2026, and lost a day added to it. It is a class of the corpus now.

* **The probes** — four functions had no answer for classes they do answer, the matrix having asked them nothing those classes could answer: `on/2` with a time of day, `round/2` to a year, `to_relative_string/2` from a moment, and `duration/2` to a later value in the value's own calendar.

Upstream, reported and not worked round: `Localize.Interval.to_string/3` takes no date without a year, so a span of two months or two days of no year (`6M/9M`) has no text. It is Blocked in `TODO.md`.

The finished tree, against Calendrical `ad5ff77` and Localize `6c5d4ef2`, their heads on the day: 894 values and 324,282 cells on every test run, in half a minute, and 4,798 more values and 1,217,394 cells in the exhaustive run, in sixteen minutes, with no cell failing in either; 59 properties of the reference; and `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, `mix dialyzer` and `mix docs` clean. Dialyzer had not been run since the branch was cut and found eight warnings in its code, a clause no value reaches and a `MapSet` gathered through recursive calls beside an error, which are fixed.

What it costs: over 39 walks and conversions timed at the branch's base and at its end, the branch is six percent slower on average. A walk is up to sixteen percent slower and the conversion of a set of two up to a quarter, the readings every value now passes through being a fixed cost; the walk of a week is a quarter faster. A value of whole numbers is converted at once, which keeps `to_interval/2` of a plain value, and of a set of hundreds, where it was.

### Selections, 2026-10-04

The matrix did not measure a selection, for two reasons, and fixing one count from the end in a selection found four defects beside it. Its corpus held five selections written by hand, all in a Gregorian month or year, and `Tempo.Matrix.Shapes` writes each shape in each position of a value, not of a selection, which is a language of its own (the units it names, how each is written, the period, the calendar, and whether it is a value's, a recurrence's rule or `Tempo.select/2`'s). And its checks could not see a wrong selection: a value that holds a selection is walked as the spans `to_interval/2` gives it, so the walk agreed with the conversion by definition, and a selection that selects nothing, or the wrong day, is a value and not an error.

`Tempo.Matrix.Selections` is both halves. It writes one part of a selection in each of seven ways (a number, a count from the end, a set, a range, a range that reaches the end, the first and the last, a value no period has) in each of 31 periods, in the Gregorian and Hebrew calendars and a calendar of weeks: 217 values, and every operation runs on each. And it works out what each selects from its parts alone, with `Date`, `:calendar` and the calendar's own functions and none of Tempo's: the days of the period that every part names. Three checks hold the library to it: `to_interval/2` of the value, a recurrence of the period with the same parts as its rule, and `Tempo.select/2` of the period with the same parts.

The first run failed 135 cells of 55,986, five causes, which the baseline lists and `TODO.md` names. The months, the days, the days of the year, the weeks of a Gregorian year, the hours, the minutes and the positions agree with the reference in every way they are written, in both month calendars.

### Open questions

Found and not decided, since each is the user's.

* **A Gregorian week's days** — the walk of `2026-W25`, and that week shifted by a day, give `2026Y25W2K`, a week and a day of it, which the parser and the constructor read as the calendar date. The two are one span and two values, and the text of the first reads back as the second.

* **A time of day under a year or a month** — read on the first day (Mine, above), where ISO 8601-2 §7.7.1 wants the date of a date and time complete, and where "17:00 in June" could as well be that time on each day. `select/2` of a time of day in a month gives the first day too.

* **A count from the end with no year** — `~o"2M-1D"` is the 29th, the longest February, and `~o"-1M"` is left unresolved though every Gregorian year has twelve months.

* **A fraction of a minute or an hour** — `T10:30.5` is read as the second 10:30:30 and `T10.5` as the minute 10:30, where the text names a tenth of a minute and a tenth of an hour. No value has such a resolution to hold it.

## Tasks

* [ ] **Selections** — the 135 cells the baseline lists, five causes, named in `TODO.md` under In progress; then the form left out (a day with no month in a year) once it is decided, and a recurrence with no year.

### Done

* [x] **Selections measured** — `Tempo.Matrix.Selections`: 217 generated selections, a reference for what each selects, and three checks. 2026-10-04.

* [x] **Published** — the table of [guides/operation-matrix.md](../guides/operation-matrix.md), generated from a run and checked by the matrix test with its errors and its levels; what reading it found, fixed; `TODO.md`, the CHANGELOG and the migration guide; every CI step clean on the finished tree. 2026-10-03.

* [x] **Right** — the reference, the spellings and the generators for the core, 59 properties, and what they found fixed. 2026-10-03.

* [x] **Total and consistent, for every shape in pairs** — the exhaustive corpus: 1,217,394 cells, none failing. 2026-10-03.

* [x] **Consistent** — the extent helper, the consistency checks, and every disagreement resolved: 176,100 cells with the checks, none failing. 2026-10-03.

* [x] **Total, for every shape in every position** — the corpus generated by putting each shape in each position of each form: 130,473 cells, none failing. 2026-10-03.

* [x] **Total** — every stray raise, hang and bad error of the first census fixed or turned into a named error, and the baseline empty. 2026-10-03.

* [x] **The census** — the corpus, the operations table, the runner, the baseline file and the matrix test with the total check. 2026-10-03.
