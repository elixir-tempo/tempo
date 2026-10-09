# What each operation gives each value

Tempo reads far more than dates: masks, sets, groups, qualified and unspecified units, values with no year, intervals with one end, recurrences. Not every function has an answer for every one of them, and this page is the table of which do. It is generated from the code and checked against it by the test suite, so it cannot fall behind.

A cell that is not complete is not a defect. A date has no time of day to convert to a `Time`, and a duration has no place on the time line to compare. What the table promises is that every cell is one of two things: an answer, or an error that says by name why there is none. No function raises an error it did not mean to, runs without end, or answers one way where another function answers another.

## How it is tested

Three sets of checks stand behind the table, in `test/tempo/matrix_test.exs` and `test/tempo/reference_test.exs`.

* **Total** — every function in the table is run against every value below, and against some seven hundred more that put each shape in each position of each form. Each must return a value or a named error. The run has no list of exceptions.

* **Consistent** — for every value, the span `Tempo.to_interval/2` gives is the span its walk covers, and the lengths, comparisons, relations and set operations all agree with that span, measured apart from the code under test.

* **Right** — for dates, times, zones, calendars, intervals with two ends, durations, counted recurrences and sets of whole values, the answers equal a reference worked out from the numbers alone with `Date`, `NaiveDateTime`, `DateTime` and a calendar's own functions, for values generated at random and written in every form ISO 8601 allows.

A longer run, `mix test --include exhaustive`, puts two shapes in one value and a shaped value at each end of an interval: about 1.2 million cells.

## Reading the table

Each row is one value, standing for its class, and the cells say what the functions give that value. Each column is a kind of operation, and a cell says how many of the kind's functions have an answer for the value: `all`, `none`, or a count of them. The last column names the errors the others return. The functions of each column are listed above the tables.

A function has an answer for a value when it answers with some argument: `Tempo.round/2` has one for a date, since a date rounds to a month, though not to an hour, which is finer than a date is written to. A function of two values is asked with the value in either place and with other values beside it: a date is what a time of day is placed on, so `Tempo.on/2` has an answer for it. A bang form is counted with its function, and `Enum.member?/2` is asked of the value's own walk.

The three tables are three levels of guarantee.

* **Core** — dates and times at every resolution, week and ordinal dates, zones, calendars, intervals, durations, recurrences, and sets and ranges of whole values. Those the reference generates are held to it, and the rest (an interval with one end or with no year, a recurrence with no end) to the first two checks.

* **Extended** — masks, unspecified units, qualification, margins of error, significant digits, groups, counts from the end and selections. Their meaning is the values their walk yields: every one converts and can be walked, and every other function is held to that.

* **Open** — shapes the walk or the conversion has no answer for. Most are yet to be defined, and their rows are the list of what remains. A season with no hemisphere (`2026-21`) is here by design: it has no dates to walk until it is given one.

## The matrix

<!-- matrix: generated, do not edit by hand -->

### The functions of each column

* **Convert** — `Tempo.to_interval/1`, `Tempo.to_interval/2`, `Tempo.to_interval_set/1`, `Tempo.to_calendar/2`, `Tempo.shift_zone/2`, `Tempo.in_zone/2`, `Tempo.to_date/1`, `Tempo.to_time/1`, `Tempo.to_naive_datetime/1`, `Tempo.to_datetime/1`, `Tempo.to_elixir/1`.

* **Walk** — `Enum.take/2`, `Enum.count/1`, `Enum.at/2`, `Enum.member?/2`.

* **Measure** — `Tempo.duration/1`, `Tempo.bounded?/1`, `Tempo.empty?/1`, `Tempo.at_least?/2`, `Tempo.at_most?/2`, `Tempo.exactly?/2`, `Tempo.longer_than?/2`, `Tempo.shorter_than?/2`, `Tempo.duration/2`.

* **Compare** — `Tempo.relation/2`, `Tempo.compare/2`, `Tempo.overlaps?/2`, `Tempo.contains?/2`, `Tempo.within?/2`, `Tempo.before?/2`, `Tempo.after?/2`, `Tempo.adjacent?/2`, `Tempo.disjoint?/2`, `Tempo.equal?/2`, `Tempo.overlap_certainty/2`, `Tempo.within_certainty/2`, `Tempo.relation_certainty/3`, `Tempo.possibly_before?/2`, `Tempo.possibly_after?/2`, `Tempo.possibly_overlaps?/2`, `Tempo.possibly_within?/2`, `Tempo.certainly_before?/2`, `Tempo.certainly_after?/2`, `Tempo.certainly_overlaps?/2`, `Tempo.certainly_within?/2`.

* **Combine** — `Tempo.union/2`, `Tempo.intersection/2`, `Tempo.difference/2`, `Tempo.symmetric_difference/2`, `Tempo.complement/2`, `Tempo.members_overlapping/2`, `Tempo.members_outside/2`, `Tempo.members_in_exactly_one/2`.

* **Shift and round** — `Tempo.trunc/2`, `Tempo.round/2`, `Tempo.at_resolution/2`, `Tempo.extend_resolution/2`, `Tempo.shift/2`, `Tempo.trunc/1`, `Tempo.round/1`, `Tempo.extend/1`, `Tempo.split/1`, `Tempo.at/2`, `Tempo.on/2`.

* **Select** — `Tempo.select/2`, `Tempo.workday?/2`, `Tempo.weekend?/2`, `Tempo.count_workdays/2`, `Tempo.nearest_workday/2`, `Tempo.roll_to_workday/3`, `Tempo.next_workday/2`, `Tempo.previous_workday/2`, `Tempo.add_workdays/3`.

* **Format** — `Tempo.to_iso8601/1`, `Tempo.to_string/1`, `Tempo.to_relative_string/2`, `Tempo.explain/1`, `Kernel.inspect/1`.

* **Read parts** — `Tempo.year/1`, `Tempo.month/1`, `Tempo.week/1`, `Tempo.day/1`, `Tempo.hour/1`, `Tempo.minute/1`, `Tempo.second/1`, `Tempo.day_of_week/1`, `Tempo.day_of_year/1`, `Tempo.quarter_of_year/1`, `Tempo.days_in_month/1`, `Tempo.leap_year?/1`, `Tempo.anchored?/1`, `Tempo.floating?/1`, `Tempo.zoned?/1`, `Tempo.resolution/1`, `Tempo.metadata/1`, `Tempo.put_metadata/2`.

### Core

| Class | Convert | Walk | Measure | Compare | Combine | Shift and round | Select | Format | Read parts | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| Year `2026` | 4 of 11 | all | all | all | all | 10 of 11 | 2 of 9 | all | 17 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Year month `2026-06` | 4 of 11 | all | all | all | all | 10 of 11 | 2 of 9 | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Date `2026-06-15` | 7 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Week `2026-W25` | 4 of 11 | all | all | all | all | 10 of 11 | 2 of 9 | all | 17 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Week date `2026-W25-3` | 7 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Ordinal date `2026-166` | 7 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Date and hour `2026-06-15T10` | 5 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Date and minute `2026-06-15T10:30` | 5 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Date and second `2026-06-15T10:30:45` | 7 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Date and fraction `2026-06-15T10:30:45.5` | 7 of 11 | all | all | all | all | 10 of 11 | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError` |
| Date and microsecond `2026-06-15T10:30:45.123456` | 7 of 11 | none | all | all | all | 9 of 11 | all | all | all | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError` |
| UTC `2026-06-15T10:30:45Z` | 8 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.ZonedTempoError` |
| Offset `2026-06-15T10:30:45+02:00` | 8 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.ZonedTempoError` |
| Zoned `2026-06-15T10:30:45[Europe/Paris]` | 8 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.ZonedTempoError` |
| Zoned date `2026-06-15[Europe/Paris]` | 6 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.ZonedTempoError` |
| Expanded year `-2026Y` | 4 of 11 | all | all | all | all | 10 of 11 | 2 of 9 | all | 17 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Time of day `T10:30:45` | 6 of 11 | all | 8 of 9 | all | all | 9 of 11 | 2 of 9 | 4 of 5 | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.ResolutionError`, `Tempo.UnanchoredError` |
| Month day `6M15D` | 4 of 11 | all | 2 of 9 | all | all | all | 2 of 9 | 4 of 5 | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.UnanchoredError` |
| Weekday `3K` | 4 of 11 | all | 8 of 9 | all | all | 10 of 11 | 2 of 9 | 3 of 5 | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.ResolutionError`, `Tempo.UnanchoredError` |
| Last of its cycle `T23H` | 4 of 11 | all | 8 of 9 | all | all | 9 of 11 | 2 of 9 | 4 of 5 | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.ResolutionError`, `Tempo.UnanchoredError` |
| Interval `2026-06-01/2026-07-01` | 4 of 11 | all | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 5 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Interval, start and duration `2026-06-01/P1M` | 4 of 11 | all | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 5 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Interval, duration and end `P1M/2026-07-01` | 4 of 11 | all | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 5 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Interval, open end `2026-06-01/..` | 3 of 11 | 2 of 4 | 8 of 9 | 1 of 21 | none | 7 of 11 | 1 of 9 | 4 of 5 | 9 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.IntervalEndpointsError`, `Tempo.UnboundedSetError` |
| Interval, open start `../2026-06-01` | 3 of 11 | none | 8 of 9 | 1 of 21 | none | 7 of 11 | none | 3 of 5 | 2 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.IntervalEndpointsError` |
| Interval, open both ends `../..` | 3 of 11 | none | 8 of 9 | 1 of 21 | none | 7 of 11 | none | 3 of 5 | 2 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.IntervalEndpointsError` |
| Interval, no year `T22H/T2H` | 3 of 11 | all | 8 of 9 | 6 of 21 | all | 5 of 11 | 2 of 9 | 4 of 5 | 7 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.IntervalEndpointsError`, `Tempo.ResolutionError`, `Tempo.UnanchoredError` |
| Interval, no year, open end `T10H/..` | 2 of 11 | 2 of 4 | 8 of 9 | 1 of 21 | none | 5 of 11 | 2 of 9 | 3 of 5 | 9 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.IntervalEndpointsError`, `Tempo.ResolutionError`, `Tempo.UnanchoredError` |
| Interval, two resolutions `2026/2026-03` | 3 of 11 | all | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 4 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Interval, week to date `2026-W25/2026-07-01` | 3 of 11 | all | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 8 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Interval, zoned `2026-06-15T09:00[Europe/Paris]/2026-06-15T17:00[Europe/Paris]` | 4 of 11 | all | 8 of 9 | all | all | 5 of 11 | 2 of 9 | all | 7 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.IntervalEndpointsError` |
| Interval, two zones `2026-06-15T10:00+02:00/2026-06-15T12:00Z` | 4 of 11 | all | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 7 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Duration `P1D` | 1 of 11 | none | none | 1 of 21 | none | none | none | 4 of 5 | none | `ArgumentError`, `Protocol.UndefinedError`, `Tempo.ConversionError` |
| Set of durations `{P1D,P2D}` | none | all | none | none | none | none | none | 3 of 5 | none | `ArgumentError`, `Tempo.ConversionError` |
| Recurrence, counted `R3/2026-06-01/P1D` | 4 of 11 | all | 2 of 9 | 6 of 21 | all | 3 of 11 | 2 of 9 | all | 2 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Recurrence, unending `R/2026-01-01/P1Y` | 2 of 11 | none | 3 of 9 | 1 of 21 | none | 3 of 11 | none | 4 of 5 | 2 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.UnboundedRecurrenceError` |
| Recurrence, selecting `R3/2026-01-01/P1Y/FL7M4DN` | 4 of 11 | all | 2 of 9 | 6 of 21 | all | 3 of 11 | 2 of 9 | all | 2 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Set in a unit `2026Y{6,7}M` | 4 of 11 | all | 8 of 9 | 6 of 21 | all | 9 of 11 | 2 of 9 | 4 of 5 | 14 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.IntervalEndpointsError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Range in a unit `2026Y{1..3}M` | 4 of 11 | all | 8 of 9 | 6 of 21 | all | 9 of 11 | 2 of 9 | 4 of 5 | 14 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.IntervalEndpointsError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Set of values `{2026-06-15,2026-07-01}` | 3 of 11 | all | 8 of 9 | 5 of 21 | all | none | 2 of 9 | 4 of 5 | none | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| One of a set `[2026,2027]` | none | all | none | 11 of 21 | none | none | none | 4 of 5 | none | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Range of values `{2020Y..2022Y}` | 3 of 11 | all | 8 of 9 | 5 of 21 | all | none | 2 of 9 | 4 of 5 | none | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Hebrew calendar `5786Y6M15D[u-ca=hebrew]` | 7 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Week calendar `2026Y25W3K` | 7 of 11 | all | all | all | all | all | 8 of 9 | all | 17 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError` |

### Extended

| Class | Convert | Walk | Measure | Compare | Combine | Shift and round | Select | Format | Read parts | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| Masked year `202X` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Partly masked unit `2026-06-1X` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 15 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Masked unit `2026-06-XX` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 15 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Mask before a unit `1985-XX-15` | 4 of 11 | all | 8 of 9 | 17 of 21 | all | 9 of 11 | 2 of 9 | 4 of 5 | 14 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.IntervalEndpointsError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Unspecified unit `2026Y6MX*D` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 15 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Qualified `2026-06-15?` | 7 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Margin of error `2018±2Y` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Significant digits `1950S2` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Group `2026Y1G3MU` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 14 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Count from the end `2026Y6M-1D` | 7 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Selection `2026Y4ML1K1IN` | 4 of 11 | all | all | all | all | 7 of 11 | 2 of 9 | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Season `2026-25` | 4 of 11 | all | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 5 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Season set `{2026-21,2026-23}` | 3 of 11 | all | 8 of 9 | 5 of 21 | all | none | 2 of 9 | 4 of 5 | none | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Week of a month `2026Y6M2W` | 4 of 11 | all | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 6 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Zone transition `2026-10-25T02:30[Europe/Paris]` | 5 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.ZonedTempoError` |
| Mask from the end `2026Y-XM` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 14 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Mask of fewer digits `2026YXM` | 4 of 11 | all | all | all | all | 9 of 11 | 2 of 9 | all | 14 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |
| Time on a year or month `2026YT17H` | 5 of 11 | all | all | all | all | all | all | all | all | `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Recurrence from a masked day `R3/2026Y6MXXD/P1M` | 3 of 11 | all | 2 of 9 | 6 of 21 | all | 3 of 11 | 2 of 9 | all | 2 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError` |
| Set with a day a month lacks `{1,2}M31D` | 4 of 11 | all | 2 of 9 | all | all | 9 of 11 | 2 of 9 | 4 of 5 | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.RoundingError`, `Tempo.UnanchoredError` |
| Group of a set `2026Y{1,2}G3MU` | 4 of 11 | all | 8 of 9 | 6 of 21 | all | 3 of 11 | 2 of 9 | 4 of 5 | 14 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.IntervalEndpointsError`, `Tempo.ResolutionError`, `Tempo.RoundingError` |

### Open

| Class | Convert | Walk | Measure | Compare | Combine | Shift and round | Select | Format | Read parts | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| Season with no hemisphere `2026-21` | 4 of 11 | none | all | all | all | 5 of 11 | 2 of 9 | all | 14 of 18 | `ArgumentError`, `Tempo.AbstractSeasonError`, `Tempo.ConversionError`, `Tempo.FloatingTempoError`, `Tempo.ResolutionError` |
| Season interval `2026-21/2026-23` | 3 of 11 | none | 8 of 9 | all | all | 1 of 11 | 2 of 9 | all | 5 of 18 | `ArgumentError`, `Tempo.AbstractSeasonError`, `Tempo.ConversionError` |
| Unspecified year `X*Y` | 1 of 11 | none | none | 1 of 21 | none | 9 of 11 | none | 3 of 5 | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.RoundingError`, `Tempo.UnanchoredError` |
| Interval from a masked day `2026Y6MXXD/P1M` | 3 of 11 | none | 8 of 9 | all | all | 7 of 11 | 2 of 9 | all | 5 of 18 | `ArgumentError`, `Tempo.ConversionError` |
| Masked day, no year `2MXXD` | 4 of 11 | none | 2 of 9 | all | all | 8 of 11 | 2 of 9 | 4 of 5 | 13 of 18 | `ArgumentError`, `Tempo.ConversionError`, `Tempo.RoundingError`, `Tempo.UnanchoredError` |

<!-- matrix: end -->

## The errors

Each error in the table is an exception module, returned in an `{:error, exception}` tuple by a function that returns tuples and raised by a predicate, an accessor, a bang function or a walk.

* **`Tempo.ConversionError`** — the value has no form in what was asked for: a year is no `Date`, a one-of set is no one span, and a date with a time of day is not moved to another calendar. One whose `:reason` is `:not_built` is an answer Tempo does not yet work out, listed below.

* **`Tempo.UnanchoredError`** — the function needs a place on the time line and the value has no year. Place it on a date first with `Tempo.at/2` or `Tempo.on/2`.

* **`Tempo.FloatingTempoError`** — the function needs a moment and the value has no zone, or one operand has a zone and the other none. Place it in a zone first with `Tempo.in_zone/2`.

* **`Tempo.ZonedTempoError`** — the value has a zone already. `Tempo.in_zone/2` places a value that has none, and `Tempo.shift_zone/2` moves one that has.

* **`Tempo.IntervalEndpointsError`** — an interval has no start or no end to measure from, an end that names several spans, or ends that are not in order.

* **`Tempo.ResolutionError`** — a unit the value's axis does not have, or that it is already written past: a month of a week date, a day of a time of day.

* **`Tempo.RoundingError`** — a unit finer than the value is written to, or a value that holds several.

* **`Tempo.UnboundedRecurrenceError`** — a recurrence with no count and no end, which needs a `:within` window.

* **`Tempo.EventError`** — a computed event (`(easter)e`) has no date where a recurrence or a selection asks for it: a year the event is not computed for, or a name no resolver knows. It names the event and the year.

* **`Tempo.UnboundedSetError`** — the days of a span with no end, which cannot be counted or listed.

* **`Tempo.AbstractSeasonError`** — the function needs the dates of a season that has no hemisphere (`2026-21`, spring wherever it is read), or the season was given a territory the equator runs through. Give it a hemisphere with `Tempo.in_territory/2`, or convert it with `Tempo.to_interval/2`, which takes `:territory` and `:locale`.

* **`ArgumentError`** — the value is of another kind than the function takes: a duration given to a function of a date, an interval or a set to a function of one value.

* **`Protocol.UndefinedError`** — a duration names no span, so it has nothing to walk: `Enum` raises this for it.

## What is not built

Some answers Tempo does not yet work out. Where it is known that the answer it would give is wrong, it gives none: the function returns, and a walk raises, a `Tempo.ConversionError` whose `:reason` is `:not_built`, whose `:target` says what was asked for and whose `:calendar` names the calendar. What has not been measured, and is not known to be wrong, still answers.

All but the last three are in a calendar whose year does not begin with its first month: Calendrical's Julian `March25`, `March1`, `Sept1` and `Dec25`, whose years turn on those days, and `Calendrical.Reform.England`, whose years began on 25 March until 1751.

* **A selection that counts days within a month or a year** — `:selection`. A day of a month selected without its month, a weekday and an ordinal, in a value (`1750Y12ML-1DN`) and in the rule of a recurrence that steps by months or years, and a day of a month given to `Tempo.select/2` to select from a month. A month alone, a month with a day, a day of the year, a day with no month selected in a year (which is a day of the year, `1750YL45DN`), a week and a time of day are answered, and so are a weekday given to `Tempo.select/2` and any selection in a recurrence that steps by weeks or by less.

* **A season** — `:season`. `1750Y21M`, the spring of a year. A quarter, a half and the other divisions of a year by its months are answered.

* **A step from several months of a year of `Calendrical.Reform.England` before 1751** — `:shift`. A set, a range or a mask of months there (`1750Y{3,4}M15D`, `1750YXXM15D`), by any unit: the calendar does not count the months of those years, so the values are not listed. One date is stepped by its calendar and is answered, and so is each date a set names and each a mask stands for in every other year and calendar, the days of the month a year begins within among them (`1750Y3MX*D` where the year turns on 25 March).

* **A month of a year of `Calendrical.Reform.England` before 1751** — `:month`. The calendar numbers the months of those years as their dates do, and not from the day the year begins, so no month is the days from 25 to 31 March that begin the year. A month of such a year is not read, and the year is not walked by its months, extended, truncated or rounded to one, or stepped by one. The year, its dates and their steps are answered, and so are the months of 1751 and of every year after it.

* **An RRULE that counts in another calendar than the Gregorian** — `:rrule`. RFC 5545 counts a rule's months, years and weeks of the year in the Gregorian calendar, and RFC 7529's `RSCALE`, which names another, is not written: `Tempo.RRule.to_string/1` of a recurrence of another calendar that steps by months or years, or selects by a month, a day of the month, a day of the year or a week of the year. A rule that steps by weeks, days or less and selects by weekday and time of day is written, and reads in the Gregorian calendar as the days it selects.

* **A week of a month** — `:week_of_month`. A week after a month is a week of that month, which the calendar numbers, and is answered: `2026Y6M2W` is read as 8 to 14 June, `Tempo.select(~o"2026-06", ~o"2W")` selects it, and `2026Y6ML2WN` and `R/2026Y6M/P1M/FL2WN` name it. A selection resolved in a month hands the week's days to a part that picks within it (`2026Y6ML2W3KN` is 10 June, as `Tempo.select(~o"2026-06", ~o"2W3K")` is). A week selected from a month as a mask is each week its digits match (`~o"XW"` is the weeks June has), with a day or a time under it too (`~o"XW3K"` is the Wednesday of each). What is left is a week of a month in a calendar whose year does not begin with its first month. A week of the calendar's own numbering under a month (`2026Y6ML2wN`) is no part of it: such a week is a week of the calendar's year, and under a month it is refused for good, with the reason `:calendar_week_in_month`. A week beside a month in a selection is the week of that month too (`2026YL6M2WN`), and a week selected from a day or a time, which are written with their month, keeps what that week of the month holds. A week with no month beside it, selected from a year or from a week, is a week of the year, and so is the week of a rule whose start is a date, which keeps or drops each day by it.

* **A rule that holds a window, on a recurrence written to its end** — `:rule_to_an_end`. A recurrence written with a duration and an end runs back from the end, and a rule on one is asked of each period back from there: `R3/P1D/2019-01-08/FL7KN` is the three Sundays before 8 January, nearest the end first, each over by the end. What is left is such a rule that holds a window (ISO 8601-2 §12.10, `R2/P1Y/2026-06-01/FL11MLL1K1IN/P7DN45W1KN`), which places an occurrence outside the period that selects it: it is refused in every calendar. The same rule on a recurrence written from its start is answered.
