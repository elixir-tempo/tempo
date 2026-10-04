# Changelog

## [v2.0.0] — Unreleased

### Breaking changes

* With no year, a day counted from the end of a month whose length depends on the year is kept as written until the value is placed on one: `~o"2M-1D"` on 2027 is 28 February and `Tempo.select(~o"2026", ~o"2M-1D")` selects it, where it was read as the 29th, an error on 2027 and an empty selection in 2026. A February with no year is no longer walked (`Enum.to_list(~o"2M")` raises a `Tempo.UnanchoredError`, where it listed 29 days), and `Tempo.to_interval/2` of a count from the end with no year returns that error, where it was a `Tempo.ConversionError` about several values.

* A value's calendar is recorded once, as its `:calendar` module: its `extended` map has no `:calendar` key and is `nil` for a value with no zone, offset or tag, so `Tempo.from_iso8601!("5786-09-30[u-ca=hebrew]")` equals the same date made with `Calendrical.Hebrew`, `Tempo.new/1`, `Tempo.from_elixir/1` or `Tempo.to_calendar/2`, and every value equals its own text read back. A Gregorian value read with `[u-ca=gregory]` is written without the suffix, and `Tempo.explain/1` no longer prints an "IXDTF calendar hint".

* A day of the year that does not resolve to a date (`350O`, `2020Y{100,200}O`) is its own unit, `:day_of_year`, written back as `O`, where it was a `:day` written `D`, and a day of the year never follows a month. A `D` with no month is still read as a day of the year where a year resolves it: `2026Y32D` is 1 February.

Tempo 2.0 gives each word in its API one meaning. The table maps each 1.x name that changed to its 2.0 form, and the [migration guide](guides/migration.md) shows each change with examples.

| 1.x | 2.0 |
|---|---|
| `Tempo.IntervalSet.total_duration/1` | `Tempo.IntervalSet.duration/1` |
| the `:bound` option | `:within` |
| `Tempo.subset?/3` | `Tempo.within?/3` |
| `during?/2`, `meets?/2` on `Tempo` and `Tempo.Interval` | `Tempo.Allen.during?/2`, `Tempo.Allen.meets?/2` |
| `Tempo.Interval.inverse_relation/1` | `Tempo.Allen.inverse/1` |
| `compose/2` on `Tempo` and `Tempo.Interval` | `Tempo.Allen.compose/2` |
| `Tempo.Interval.equivalent?/2` | `Tempo.equal?/3` |
| `Tempo.anchor/2` | `Tempo.on/2` or `Tempo.at/2`, in either order |
| `Tempo.NonAnchoredError`, `Tempo.RequiresAnchorError` | `Tempo.UnanchoredError` |
| `Tempo.grounded?/1` | `Tempo.zoned?/1` |
| `Tempo.GroundedTempoError` | `Tempo.ZonedTempoError` |
| `Tempo.to_date_time/1`, `from_date_time/1` | `Tempo.to_datetime/1`, `from_datetime/1` |
| `Tempo.to_naive_date_time/1`, `from_naive_date_time/1` | `Tempo.to_naive_datetime/1`, `from_naive_datetime/1` |
| `Tempo.to_calendar/1` | `Tempo.to_elixir/1` |
| `Tempo.ICal.from_ical/2`, `from_ical_file/2` | `Tempo.ICal.parse/2`, `parse_file/2` |
| `Tempo.ICal.available_from_ical/2` | `Tempo.ICal.available/2`, given text |
| `Tempo.JSCalendar.from_jscalendar/2` | `Tempo.JSCalendar.parse/2` |
| `Tempo.to_rrule/1`, `to_rrule!/1` | `Tempo.RRule.to_string/1`, `to_string!/1` |
| `Tempo.MaterialisationError` | `Tempo.ConversionError` |
| `Tempo.RRule.Expander.expand/3` | `Tempo.RRule.parse/2`, then `Tempo.to_interval_set/2` |
| `Tempo.add_working_days/3` | `Tempo.add_workdays/3` |
| `Tempo.next_working_day/2`, `previous_working_day/2` | `Tempo.next_workday/2`, `previous_workday/2` |
| `Tempo.nearest_working_day/2` | `Tempo.nearest_workday/2` |
| `Tempo.working_days_in/2` | `Tempo.count_workdays/2` |
| `Tempo.weekend/1` | `Tempo.weekends/1` |
| `Tempo.weekends(from: date)`, a lazy set | `Tempo.select/2` over a span with no end |
| `Tempo.IntervalSet.to_list/1` | `Tempo.IntervalSet.members/1` |
| `Tempo.IntervalSet.overlapping/2` | `Tempo.IntervalSet.covered/2` |
| `Tempo.beginning_of_day/1`, `beginning_of_week/1`, `beginning_of_month/1` | `Tempo.trunc/2` to `:day`, `:week` or `:month` |
| `Tempo.end_of_day/1`, `end_of_month/1` | `Tempo.Interval.to/1` of the day or month `Tempo.trunc/2` gives |
| `Tempo.Network.TimePeriod.new/2`'s `:start`, `:end` | `:from`, `:to` |
| `Tempo.Network.Solver.tighten/1` | `Tempo.Network.Solver.propagate/1` |
| `Tempo.Schedule.Slot` | `Tempo.Schedule.ScheduledTask` |
| `Tempo.Schedule.task/3`'s `:earliest` | `:not_before` |

* `Tempo.duration/1` and `Tempo.IntervalSet.duration/1` measure the time a set covers, counting time its members share once; `IntervalSet.total_duration/1`, which did, is removed.

* A duration is counted in the unit its endpoints are written in, where it was seconds: `~o"P36D"` between two days and `~o"PT8H"` between two hours, years to days on the calendar through `Calendrical.diff/3` and hours to fractions of a second as elapsed time.

* A zoned value's hours, minutes and seconds are time on the time line in `Tempo.shift/2`, a start-and-duration interval, an hour's own span and an hourly recurrence, and its days stay calendar days: five hours after 23:00 on the night the clocks spring forward is 05:00, where it was 04:00.

* `:within` replaces `:bound` on `Tempo.to_interval/2`, `to_interval_set/2`, the set operations, `complement/2`, `Tempo.ICal.parse/2`, `Tempo.JSCalendar.parse/2` and the RRULE expander; a leftover `:bound` is an error naming it.

* The `:within` window keeps every occurrence that overlaps it, for every recurrence: `R/2020-01-01/P1Y` within 2026 is 2026's occurrence alone, not every year since 2020, and iCalendar and JSCalendar return only the events that overlap the window.

* `Tempo.before?/2` and `after?/2`, with their `certainly_` and `possibly_` forms, hold when the two share no instant, so an 11:00–12:00 meeting is before a 12:00 lunch. Allen's strict relations, which need a gap, are `Tempo.Allen.precedes?/2` and `preceded_by?/2`.

* `Tempo.Allen` has a predicate for each of Allen's thirteen relations under Allen's own name, with `inverse/1` and `compose/2` on a relation or a set; `during?/2`, `meets?/2`, `inverse_relation/1` and `compose/2` move there.

* `Tempo.within?/3` takes `subset?/3`'s place and compares any two values instant by instant, as `contains?/3` does; `Tempo.Interval.within?/2` stays the single-interval form, and `Interval.equivalent?/2` is removed for `Tempo.equal?/3`.

* `Tempo.today/1` and `utc_today/0` return the floating date, so it compares with a holiday or any date written without a zone; `now/1` stays zoned.

* `Tempo.duration/2` returns `{:error, %Tempo.FloatingTempoError{}}` for a zoned value against a floating one, the pair `relation/2` refuses, where it measured the floating one as UTC.

* `Tempo.to_relative_string/2` counts calendar periods in the value's own calendar and on its own wall clock, never in a unit finer than the value's own: 1 February is "next month" from 31 January and 2027 "next year" from July 2026, where 1.x divided seconds by a mean month. A zoned value finer than a day raises `Tempo.FloatingTempoError` from a floating `:from`, where it read that as UTC.

* A zone or offset on an interval's start applies to a floating end, as ISO 8601-1 §5.5.1 says: `2018-01-15T10:00+05:00/2018-02-20T10:00` ends at +05:00, where its end was floating. `Tempo.Interval.new/1` follows the same rule.

* `Tempo.new/1`'s `:metadata` is the value's own metadata, read with `Tempo.metadata/1` and never written to its ISO 8601 form, where it was written as IXDTF suffix tags; tags take the new `:tags` option, validated so `to_iso8601/1` cannot fail on one.

* `Tempo.anchor/2` is removed: `at/2` and `on/2` place a value without a year on one with a year in either order, so `Tempo.on(~o"T17", ~o"2026-06-15")` is 17:00 on 15 June.

* `Tempo.UnanchoredError` replaces `NonAnchoredError` and `RequiresAnchorError`, and a recurrence with an open start returns `IntervalEndpointsError` with `reason: :open_start`, where it was `:unanchored`.

* A value with a zone or an offset is zoned, the pair of floating: `Tempo.zoned?/1` replaces `grounded?/1`, and `Tempo.ZonedTempoError` replaces `GroundedTempoError`.

* The Elixir conversions write "datetime" as one word, as Elixir does: `to_datetime/1`, `from_datetime/1`, `to_naive_datetime/1` and `from_naive_datetime/1`. The deprecated `to_calendar/1` is removed for `to_elixir/1`.

* The format modules read with `parse`: `Tempo.ICal.parse/2` and `parse_file/2`, `ICal.available/2` given text or a parsed calendar, and `Tempo.JSCalendar.parse/2`. An RRULE is written with `Tempo.RRule.to_string/1`, the pair of `RRule.parse/2`.

* `Tempo.ConversionError` replaces `MaterialisationError`, keeping its reasons, so `to_interval/2` and the other conversions share one error; the docs say "convert" and "occurrences" where they said "materialise".

* The workday functions say "workday": `add_workdays/3`, `next_workday/2`, `previous_workday/2`, `nearest_workday/2` and `count_workdays/2`, which counts the days of any value `select/2` takes. They return `{:error, reason}` for a value that is not a day, where they raised.

* `Tempo.weekends/1` is the weekend selector, plural as `workdays/1` is, and both return an error for a territory they cannot resolve, which `select/2` returns as it is. 1.x's lazy `weekends/1` is `Tempo.select(~o"2026-06-15/..", Tempo.weekends())`.

* `Tempo.select/2` selects in every period of a span, at its start's resolution, where it selected in the first alone: `~o"2026/2029"` holds three Christmases. A selection starts in its period, so `Tempo.select(~o"2026-06", ~o"07-01")` is empty.

* `Tempo.IntervalSet.members/1` is the one name for a set's member intervals; `to_list/1`, a second name that read like `Enum.to_list/1`, which walks the days inside them, is removed.

* `Tempo.IntervalSet.covered/2` is `overlapping/2` renamed: the time covered by at least `:at_least` members, one by default. It returns `{:ok, set}`, and an error for a bad option or a lazy set, where it raised.

* `Tempo.RecurrenceSet.new/2` returns `{:ok, set}` and checks its members and options, with `new!/2` for the struct; a bad member failed only when the set was converted.

* The instant helpers `beginning_of_day/1`, `beginning_of_week/1`, `beginning_of_month/1`, `end_of_day/1` and `end_of_month/1` are removed: the day, week or month containing a value is `Tempo.trunc/2`, a span whose end is `Interval.to/1`.

* `Tempo.Network.TimePeriod.new/2` names a period's ends `:from` and `:to`, as `Interval.new/1` does, and returns `{:ok, period}`, with `new!/2`; a 1.x `:start` or `:end` is an error naming the new option.

* The network and schedule builders never raise: what they cannot read is recorded on the network, and every `Tempo.Network.Solver` function and `Schedule.solve/1` returns it, its predicates raising it.

* `Tempo.Network.Solver.tighten/1` is `propagate/1`, the verb `Interval.RelationNetwork` uses for the same job.

* `Tempo.Schedule.ScheduledTask` replaces `Schedule.Slot`: its `early` and `late` schedules are intervals, where `start`, `finish`, `latest_start` and `latest_finish` were four dates. `Schedule.task/3` takes `:not_before` for `:earliest`.

* `Tempo.to_iso8601/1` returns `{:ok, string}`, or a `Tempo.Iso8601EncodeError` for a value with no ISO 8601 form — a set, a conditional member, a cron nearest weekday or a value that is not Tempo's — where it raised. `to_iso8601!/1` returns the string.

* `Tempo.to_relative_string/2` returns `{:ok, string}`, or an error for a value it cannot count from — one without a year, an interval without a start, a zoned time from a floating `:from`, a value naming several spans or one that is not a Tempo value — and Localize's error for an option it refuses, where it raised. `to_relative_string!/2` returns the string.

* `Tempo.to_string/2` returns `{:ok, string}`, or an error for a value it cannot render — an interval without both ends, an interval set without an end or a value of another kind — and Localize's error for a value, locale or format it refuses, where it raised. `to_string!/2` returns the string, and interpolation writes a value it cannot render in ISO 8601.

* `Tempo.shift/3` with `:skipping` steps a day shifted by days or weeks from free day to free day and returns a day: one day of free time after a Friday before a long weekend is the Tuesday, where it was midnight on the Saturday.

* A network measures a year or a month in a network of days by its actual length from where its period can start, in the period's calendar, and gives its results in the network's calendar, where it used a mean Gregorian year and month: a year from 1 January 2024 is 366 days, and one from 1 Tishri 5784 is 383. `Tempo.Network.Normalize.normalize/1` returns `{:ok, normalized}` or an error, where it returned the map and raised.

* An interval is walked by the finer of its two ends' units, so the values it yields are the interval and none runs past its end: `~o"2026/2026-03"` is January and February, where it was 2026 alone.

* A value with no zone and one with a zone are refused by the set operations and by `Tempo.compare/3` as a sorter, with a `Tempo.FloatingTempoError`, where the floating one was read as UTC; `Tempo.ICal.available/2` reads a window with no zone in UTC. `Tempo.relation/2` and the certainty functions return the error where they raised it.

* Two values with no line to share (one with a year and one without, or two with none that lead with different units) have no order: `Tempo.compare/3` raises a `Tempo.UnanchoredError`, and `relation/2`, `Interval.new/1`, `IntervalSet.new/2`, `select/2` and the set operations return it. A value that is not one point (a mask, a set, a group) is compared as the point its span starts at, where `Tempo.compare(~o"202XY", ~o"2026-06-15")` was `:gt`.

* An interval's end written as one bare number is the start's last unit (ISO 8601-1 §5.5.1): `2026-06-15/20` ends on the 20th and `2026-06-15T10:30/45` at 10:45, where the number was read as century 20 and the interval ran backwards. A century is written `20C`.

* `Tempo.round/2` rounds to the nearer of the unit's start and the next unit's, by where the value starts in the unit, and half way rounds up: `T10:30` is eleven o'clock, `2026-06-16` rounds to 2026 and `2026-01-16` to January. A date and time rounds to any coarser unit, where it was an error.

* A span with no year that ends where it starts is once round its cycle: `~o"T0H/T0H"` is the whole day and `~o"T10H/T10H"` the 24 hours from ten, where each was empty. `Tempo.IntervalSet.coalesce/1` writes a set that covers the day so, where it wrote an hour 24 that is not read back.

* A `:within` window with no zone bounds a value in a zone in that zone: 1 to 3 June, for a recurrence in New York, is those days in New York, where the window was read as UTC.

* `Tempo.new/1` returns the value the same components are read as: a week and a day of it are the calendar date they name (`Tempo.new(year: 2026, week: 25, day_of_week: 3)` is `~o"2026-06-17"`), where it kept a week date the parser never gives. A date with a `:zone` and no time of day is that day in the zone, where it was refused.

* `Tempo.shift_zone/2` keeps the span a value names: an hour in Paris is the hour in New York, and a day in Paris is the interval from 18:00 to 18:00 there, where each was the one second it starts at. A fraction of a second is kept, where it was dropped.

* `Tempo.to_time/1`, `to_naive_datetime/1`, `to_datetime/1` and `to_elixir/1` give a whole second a precision of zero (`~T[14:30:00]`), as Elixir reads the same text, and a fraction its digits, so `from_elixir/1` gives the value back. They gave six digits, and `to_time/1` refused a fraction.

* `Tempo.shift/3` applies a duration's years and months, brings the day into the month they land in, and then counts its days, as `Date.shift/2` does: 29 July less five months and a day is 27 February, where it was the 28th. A fraction of a second added to a whole one is written to the fraction's digits, where it was six.

* A recurrence's occurrences are consecutive, as ISO 8601-1 §3.1.1.11 defines one: a month from 31 January is 28 February and the next occurrence runs from there to 31 March, where it ended on 28 March, three days before the third began.

* A duration is counted from a point: a start or an end that names one span (a mask, a group, a quarter) is the point the span starts at before a duration is counted from it. `R3/2026-33/P3M` is three quarters and `202XY/P1Y` the year 2020, where each was a `Tempo.ConversionError`.

* An explicit time shift ahead of UTC is written with no sign, as ISO 8601-2 §7.4 writes it: `Z2H0M`, where it was `Z+2H0M`, which is still read.

* `Tempo.split/1` keeps the value's zone, qualification and metadata on both parts, and `Tempo.at/2` gives its result the zone either value has, so the two parts placed are the value. Both dropped the zone, and two values in two zones are a `Tempo.ZonedTempoError`.

* A unit after a group counts from the group's start in every operation (ISO 8601-2 §5.4.2), and where it cannot be counted (a group of months with no year, a set or a mask of days) the walk and `Tempo.to_interval/2` return a `Tempo.ConversionError` with reason `:counted_in_group`. The walk yielded the unit in each of the group's values.

* A time of day under a date with its month or its day left out is that time on the first day of what is written, and the value holds the units: `2026T17` is `~o"2026Y1M1DT17H"`, `Tempo.at(~o"2026-06", ~o"T17")` is 17:00 on 1 June, and under a group it is the group's first day (`2026Y2G3MUT10H` is 10:00 on 1 April). The value held the gap, so it compared as equal to any day of its year and lost a day added to it, and under a group of months it was that time in each month.

* `1950S0` is a `Tempo.ParseError`, since the count of significant digits is a positive integer (ISO 8601-2 §4.4.3). Its walk yielded the year 1950 and its conversion was an error.

### Added

* A group of a set (`2026Y{1,2}G3MU`, the first and the second groups of three months) converts to a span for each group and walks the values of each, a unit after it counted from each group's start, where `Tempo.to_interval/2` and `Enum` returned a `Tempo.ConversionError`. A group counted from the end (`{1..-1}G3MU`) is counted in what holds it, and one of several groups (`[1,2]G3MU`) is no one span, as a one-of set is none.

* [What each operation gives each value](guides/operation-matrix.md) is a table of every class of value against every kind of operation, generated from the code and checked by the test suite, so the named errors in it are the list of what is not yet built.

* `Tempo.new/1` takes `:microsecond`, a fraction of a second as Elixir's types hold one (`{500_000, 1}` is `.5`), and so takes the map of a `Time` or a `NaiveDateTime` as it takes a `Date`'s.

* An interval's end may leave out the units it shares with its start in three more forms: a day and a time (`2007-11-13T09:00/15T17:00`), a week and its day (`2026-W25-1/W26-5`) and a day of the week (`2026-W25-1/5`). `W26-5` is read alone too, as `26W5K` is.

* `Tempo.to_string/2` renders a `Tempo.Set` and a `Tempo.RecurrenceSet`, which interpolate too, and takes `:within`, the window for a value with no end of its own: `Tempo.to_string(~o"R/2026-06-15/P1W", within: ~o"2026-06")` is that June's weeks.

* A `Tempo.Network`, and so a `Tempo.Schedule`, counts in hours, minutes and seconds on the time line, where one naming them raised: a task of `~o"PT4H"` from 09:00 runs to 13:00. An hour is elapsed time, and a day in a zone is measured, so one across a daylight-saving change is its 23 or 25 hours.

* A `Tempo.IntervalSet` is tabular data (`Table.Reader`) when the optional `table` package is present: a row per member with its `from`, `to` and metadata, so `Kino.DataTable.new/1` shows a set of holidays with their names.

* The livebook `everyday-holidays.livemd` answers everyday holiday questions — the next school holidays, the days until Election Day, a year's holidays and those two countries share — with each holiday written as its ISO 8601 rule.

* An open-ended `:within` window (`~o"2026-09-28/.."`) gives a recurrence's occurrences from its start on as a lazy set, so `Tempo.IntervalSet.first/1` is the next one. Set operations, `complement/2` and the calendar formats return an error for one.

* `Tempo.select/2` over an open-ended span (`~o"2026-06-15/.."`) gives a lazy set, selected period by period as it is walked, and a selection across a lazy set is lazy too. A span with an open start returns `IntervalEndpointsError` with `reason: :open_start`.

* `Tempo.RecurrenceSet.keep_when/2` and `move_when/2` — a member kept only when days around it fall on the other members' occurrences (a bridge day), or moved `:to_next` a selected day when it falls on one, resolved in a second pass. `:falls_on` matches the other members' metadata, or names a recurrence set to read.

* A `%Tempo{}` carries its own `:metadata`, as an interval and both sets do: `Tempo.metadata/1` and `Tempo.put_metadata/2` read and set it on any value, and materialising a value moves it to the interval or intervals the value becomes.

* A `Tempo.RecurrenceSet` member can be a `Tempo.RecurrenceSet` — a holiday and its observed days as one member — whose metadata tags every occurrence it produces, and a set's own metadata carries to the `Tempo.IntervalSet` it materialises to; `RecurrenceSet.members/1`, `metadata/1` and `IntervalSet.metadata/1` read them.

* An equinox or solstice takes its date in a named zone: `(march-equinox@+09:00)e` or `(june-solstice@America/Santiago)e` is the event's date there, a floating date like any holiday's, where the UTC date can be a day off.

* A `c` filter after a recurrence domain keeps its common (non-leap) years, beside `e`/`o`/`l`: `R/{2000Y..}c/P1Y/FL9M11DN` is 11 September in every common year from 2000, with the century rule the calendar's own.

* The `w` designator names a week in the calendar's own numbering, where `W` is ISO 8601's: `~o"2027Y1w1K"` is 28 December 2026 in `Calendrical.Gregorian`, which counts from the week holding January 1, and `R/../P1Y/FL10wN` is the calendar's week 10 of each year.

* `Tempo.new/1` takes `:quarter`, the span the calendar's `quarter/2` gives it, held as the months (in a week-based calendar, the weeks) `2026-34` parses to; `Tempo.parse/2` reads `"Q2 2026"` through it.

* A value after a group of its own unit counts within the group (ISO 8601-2 §5.4.2): `2018Y9M2DT3GT8HU0H30M` is 16:30, `2018Y2G3MU2M` is May and `2026Y2G13WU3W` is week 16.

* `Tempo.to_calendar/2` and `Tempo.to_date/1` convert a week-based calendar's date: `Tempo.to_calendar(~o"2020-W01-1"W, Calendrical.Gregorian)` is `2019-12-30`.

* `Tempo.Event` and the `(name)e` computed-event selection — a recurrence resolved by algorithm rather than the calendar. `~o"R/../P1Y/FL(easter)eN"` is Western Easter and `(orthodox-easter)e` the Julian-calendar computus (both from `Calendrical.Ecclesiastical`); the equinoxes, solstices and first `(new-moon)e` of the year come from `Astro`; and the 24 East Asian solar terms (`(qingming)e`, …) from `Calendrical`, for the Chinese meridian by default or another via `Tempo.Event.date/3`.

* `Tempo.Event.Resolver` — a behaviour that lets a consumer register its own `(name)e` events (a fiscal calendar, a feast day) through `config :ex_tempo, :event_resolvers`. Registered names resolve beside the built-ins and appear in `Tempo.Event.known/0`; a name no resolver claims yields zero occurrences.

* `Tempo.RecurrenceSet` — a collection of recurrence rules (a territory's holidays, a calendar's events) that materialises as one `IntervalSet` against a window, so `Tempo.intersection(diary, holidays)` composes it with a diary through set algebra.

* The `<n>m` / `<n>+m` traditional-month designator for the lunisolar and Hebrew calendars (RFC 7529's Hebrew numbering: Nisan is `7m`, Adar I `5+m`) — the named month rather than the ordinal `M`. In a concrete date it resolves to the ordinal; in a selection it resolves per year, so `~o"R/../P1Y/FL8m15DN[u-ca=chinese]"` tracks the true traditional month across leap years.

* Recurrence-domain exclusions and filters — a `^value` member drops a period from any set, a `{…}` domain in the recurrence slot (`R/{2020Y..2024Y,^2022Y}/P1Y/…`) bounds and punches holes in a recurrence, and lowercase `e`/`o`/`l` after a domain keep even/odd/leap years.

* ISO 8601-2 §12.10 selection with a time interval — `[selection]/[duration]` makes each resolved date the start of a window and nested selectors pick within it. `~o"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN"` is Good Friday; `~o"R/../P1Y/FL11MLL1K1IN/P9DN2K1IN"` is US Election Day.

* `Tempo.Network.Qualitative` — bridges the metric and qualitative networks. `from_network/1` seeds relation sets from what a solved network's bounds already prove, `apply_to_network/2` feeds determined relations back, and `refine/1` runs the round trip.

* `Tempo.Interval.RelationNetwork` — Allen's path-consistency propagation over a network of partially known intervals, deriving what a web of relation constraints implies. It represents disjunction (`[:precedes, :preceded_by]`), which `Tempo.Network`'s convex metric vocabulary cannot.

* `Tempo.Interval.Relations` — narrowing and canonical order over *sets* of Allen relations (with `Tempo.Allen.inverse/1` and `compose/2`, which take sets too), for reasoning when the relation between two intervals is constrained but not known. `narrow/2` combines two sources of knowledge; it is not `Tempo.intersection/2`, which operates on time values.

* `Tempo.workdays/2`'s `:except` leaves holidays out of a territory's workdays, as a `Tempo.Workdays` that `select/2` and every workday function take in place of a territory, so `Tempo.next_workday(day, Tempo.workdays(:AU, except: holidays))` steps over the holidays.

* `Tempo.Interval.new/1` takes `:through`, ending an interval where a value's span ends so a published range's last day is inside it, and `Interval.from/1` and `to/1` read the span a value names, the day a selection picks included: `~o"2027YLLL4M7DN/P7DN5K1IN"` is 9 April 2027.

* `Tempo.RecurrenceSet.filter/2` keeps the members a function keeps, as `IntervalSet.filter/2` does.

### Changed

* The certainty functions relate two values of many candidates along their runs and not pair by pair: `Tempo.overlap_certainty/2` of two masked values of 1,440 candidates each takes 70 milliseconds where it took 27 seconds.

* An ISO week of a Gregorian year is found in one step of Calendrical's arithmetic, where every week of the year was listed to find it, so each operation on a week or a week date took several times as long.

* Enumeration reads a value once and then each of its values as it is asked for: `Enum.to_list(~o"2026-06-15T10")` takes 18 µs where it took 290, and `Enum.take/2` of a large set (`{2000..2100}Y{1..-1}M{1..-1}DT{0..-1}H`) takes 50 µs where it built every member first and took a second.

* `Tempo.to_string/2` joins several spans as a list in the locale ("Jun 15, 2026 and Jul 4, 2026"), and a one-of set's members as alternatives ("2026 or 2027"), where it joined them with commas.

* The duration predicates (`at_least?/2`, `at_most?/2`, `exactly?/2`, `longer_than?/2`, `shorter_than?/2`) measure an interval set by the time it covers and a value by the span it names, and `duration/1` measures a value's span.

* `Tempo.select/2` keeps the metadata of what it selects from: each school day of a term tagged `%{term: 3}` is tagged `%{term: 3}` too, and a set's own metadata stays with the set.

* The engine moves to an Internals docs group — `Tempo.Compare`, the ISO 8601 tokenizer, `Interval.Steps`, `Microsecond`, `Network.Normalize` and the RRULE expander, rule and selection — and `Tempo.merge/2` and `unit_min_max/1` are hidden. Every documented module has a group, and `from_iso8601/2` and `from_iso8601!/2` are documented.

* A fractional duration becomes whole units of the next smaller unit, truncated: `P1.5W` is 10 days, `P1.3D` 1 day 7 hours, and `P0.5M` half the days to one month later (ISO 8601-2 D.4.4). A shift by one raised `ArithmeticError` or returned `nil`.

* Date arithmetic in validation, selection, recurrence week expansion, recurrence windows, interval stepping and conversion goes through Calendrical rather than `Date.add/2`, day numbers and month walks.

* `Tempo.parse/2` reads ISO 8601 first, with the whole grammar `from_iso8601/2` reads, then the locale's words, and `parse_date/2`, `parse_datetime/2`, `parse_time/2` and `parse_interval/2` read the same, naming what text of another kind reads as.

* `Tempo.parse/2`'s `:calendar` option is a calendar module, as Calendrical 1.4's is: a CLDR calendar name such as `:hebrew` returns an error.

* A recurrence walks every period either side of its `:within` window whose occurrences a §12.10 window, a numbered week or their own span can carry into it, stepping in the recurrence's own calendar. A domain runs its adjacent periods as one recurrence and keeps every occurrence they select; a count (`R3/{…}/…`) counts them from the domain's first period.

* A recurrence selection that moves a candidate to several dates (weekday, month-day, week and window expansions) finds the candidate's own day numbers once, and a move onto its own date asks the calendar nothing — about a third fewer calendar calls for a lunisolar calendar.

* Traditional lunisolar months resolve through Calendrical's `ordinal_month_from_traditional/2`, dates validate and convert through `Calendrical.iso_days/4`, and a day that fits every month of a calendar skips the per-year month length. The lunisolar holiday workload runs in 1.3 s instead of 2.1 s, with identical results.

* Recurrence selections converge on the ISO 8601-2 §12.9 position designator `I` — applied last over the resolved set and written weekday-then-position (`1K2I` = the 2nd Monday) — and the invented `V` set-position designator is retired. An ordinal `BYDAY` across distinct weekdays (`2MO,2WE`) has no ISO form and round-trips only through `Tempo.RRule.to_string/1`.

### Deprecated

* The week-start selection designator is now lowercase `q` (was `Q`), following the convention that every Tempo extension is lowercase. `Q` is still accepted on input and re-emitted as `q`; support for the uppercase form will be removed in a future major version.

### Fixed

* A range with a step that reaches past the days one of its months has keeps its own steps there: the walk of `~o"{1,2}M{31..1//-7}D"` yields the 24th, 17th, 10th and 3rd of February, the days of the range February has, where it yielded the 29th, 22nd, 15th, 8th and 1st.

* `Tempo.select/2` reads a set or a range of weekdays (`~o"{6..-1}K"`, `~o"{1,-1}K"`), where it selected one of the days or none, and selects a time of day written after a weekday on each of the days (`~o"1KT10H"`), where the time was dropped.

* A recurrence that starts with no year and whose rule is counted in a date (a day of a month, a weekday, a week, a month from the end: `R3/6M/P1M/FL15DN`) returns a `Tempo.UnanchoredError`, where a day rule raised a `FunctionClauseError` and the others searched for an occurrence that could not come. Placed on a year with `:within` it is counted there.

* A count from the end in a selection is counted in the period the selection resolves in, where it selected nothing or raised: a month, a weekday, an hour, a range that reaches the end (`{28..-1}D`), a position (`{2..-1}I`) and a unit after the selection (`2026YL6MN-1D`), so `R/2026-01-01/P1Y/FL-1M-1DN` is each 31 December. The values a selection or an RRULE lists are taken in the order of time and once each (`BYMONTHDAY=15,1;COUNT=3` is 1 January, 15 January and 1 February), and a value its period lacks (hour 25, the 31st of June) is passed over.

* A fraction of an hour or a minute that does not land on a whole minute or second is read to the minute, or the second, the time falls in: `T10.51` is 10:30 and `T10:30.51` is 10:30:30. The value held the fractional minute or second, which `Tempo.to_interval/2` and `Tempo.compare/2` refused, `Enum` raised on, and its own text read back as another value.

* Within a set a comma separates the members and is never a decimal sign: `{2023,2020/2021}` is a year and an interval, where `2023,2020` was read as a number and the set, or a recurrence's domain (`R/{2020,2022/2024}/P1Y`), was one interval from part way through 2023, and `{2020/2021,2023/2024}` parses. A fraction in a set's member is written with a full stop, so `{P1,5Y}` is a `Tempo.ParseError`.

* In a selection a second followed by a position is read as both: `L1KT10H0M30S1IN` is second 30 and position 1, where the `S` was taken for the significant-digit marker and the value was position 30 with no second. A duration's seconds take significant digits and a set (`PT1230S2S`, `PT{1,2}S`), where each raised a `FunctionClauseError`; a position, and a fraction no exponent has scaled (`2026.5S1Y`), take no significant digits and are a `Tempo.ParseError`.

* `Tempo.extend/2` writes the months of several years and the days of several months as text is read: `Tempo.extend(~o"2026Y{6,7}M")` is `~o"2026Y{6,7}M{1..-1}D"`, where it held a range counted backwards (`{1..-1//-1}D`) that walked alike and was not equal.

* `Tempo.to_string/2` shows an interval from its first value to its last in the finer of its ends' units, and a week beside a date as the days between them: `~o"2026/2026-03"` is "Jan – Feb 2026" and `~o"2026-W25/2026-07-01"` is "Jun 15 – 30, 2026", where each was "2026 – 2025". A year written to significant digits is shown as the block it names (`1950S2` is "1900 – 1999"), as a mask is, where it returned Localize's error.

* `Tempo.to_relative_string/2` counts to where an interval written as a duration and an end starts (`P1M/2026-07-01`), and to the first occurrence of a counted recurrence written so, where each was an error.

* A year of a calendar of weeks is shifted by weeks and days and has a length in them (`Tempo.exactly?(year, ~o"P53W")`), where each was a `Tempo.ResolutionError`. `:day` truncates, rounds and extends a week date to its day of the week, in a calendar of weeks and for a Gregorian week.

* `Tempo.duration/1` measures a set written as its members (`{2026Y,2030Y}`) as it measures the same set written in one value, where it returned an `ArgumentError`.

* A year whose every digit is significant (`1950S4`) converts to the year it is, as its walk yields it, where `Tempo.to_interval/1` returned an error.

* A fraction of a second before a time shift behind UTC (`2026-06-15T10:30:45.5-03:30`) is read, where it was a parse error.

* A duration of a year and twenty-one or more months (`P1Y21M`) is that many months, where they were read as the season a date's month 21 is.

* `Tempo.shift/3` returns an error for a unit a duration has none of (`fortnight: 1`, `quarter: 1`) and for a count that is not a number, where the first left the value as it was and the second raised.

* An explicit time shift with seconds (`Z7H33M14S`, ISO 8601-2 §7.4's own example) is written back, where `inspect/1` failed.

* An interval whose ends are on two axes, in two zones or in two calendars is walked and counted as the moments its ends are, and `Tempo.Interval.new/2` keeps each end in its own calendar, where the start was named as a day of the end's.

* `Tempo.difference/2` cuts each member of its first operand by every member of the second that overlaps it, where a member that ended inside one was dropped before the next: two bookings that overlap each lost only one.

* A year and an ISO week compare as the moments they start at, so `2027` and `2027-W01`, which starts on 4 January, are not one moment, and `Tempo.relation(~o"2026", ~o"2026-W53")` is `:overlaps`.

* Significant digits with a unit after them (`1950S2Y6M`) convert to that unit in each year of the block, as their walk yields, and every week of a year (`2026YXXW`) to the span from its first week to its last. Each converted to the whole block or year.

* A wall time a clock shows twice (`2026-10-25T02:30[Europe/Paris]`) is walked as the occurrence the value names, where each of its seconds was yielded twice.

* A span with no year that runs to its cycle's end (`~o"T23H"`, `~o"12M31D"`, `~o"7K"`) is read so by every operation, through `Tempo.Interval.Cycle`: its end was read as before its start, so `Tempo.empty?/1` was true of the last hour of the day and `coalesce/1` lost it.

* A value that holds two groups (`2G10DU2GT6HU30M`) resolves both, where it kept the first as a group and its own text read back as another value. A group of a set followed by a mask returns a `Tempo.ConversionError`, where every operation raised.

* A value with a margin of error converts as its walk yields it beside a group or a count from the end (`2026±2Y2G3MU`, `2026±2Y-1M15D`), where the margin stayed on the ends or the count was left uncounted.

* An interval whose ends have no line to share (`2020Y/X*Y6M15D`) is a `Tempo.UnanchoredError` from `Tempo.to_interval/2`, its walk and the certainty functions, where it converted to itself, was walked without end and raised.

* `Tempo.trunc/2` of a week to a month is a `Tempo.ResolutionError`, where it was the year, and `Tempo.bounded?/1` is true of a recurrence of a count.

* `Tempo.to_interval/2` of a partly masked day of the year is the span of the dates it names: `~o"2026Y3XD"` and `~o"2026Y3XO"` are 30 January to 8 February 2026. A day written straight after its year returned a `Tempo.UnanchoredError`, and one written `O` gave bounds that measured as no time (`2026Y30O/40O`).

* `Enum.count/1` of an interval with no end (`~o"2026Y/.."`) raises a `Tempo.IntervalEndpointsError`, where it walked for ever. `Enum.member?/2` of one is answered without the whole walk where its start has a year (`~o"2020Y" in ~o"2026Y/.."` is false, where it never returned), and raises the same error where it has none.

* `Tempo.extend/2` returns an error where it raised: a `Tempo.ResolutionError` for a value with no finer unit (a fraction of a second at microsecond precision), and an `ArgumentError` for a value that is not one date or time or for a unit that is not `nil`. A second extended twice is its hundred hundredths, and a second written as its fractions inspects as `45.{0..9}S`, where neither could be.

* `Tempo.to_interval/2` reads an unspecified month, week, day, hour, minute or second (`X*`) as the mask of all its digits is: `~o"2026Y6MX*D"` is June 2026 and `~o"2026YX*M15D"` the 15th of each month, where the span started at the value itself and `Tempo.duration/1` and `Tempo.to_relative_string/2` raised. An interval end written so is the point its span starts at (`2026Y6MX*D/2026Y8M` is June and July).

* `Tempo.shift/3` with `:skipping` returns a `Tempo.ConversionError` for a value that is not one moment — a set, a range, a group, unspecified digits or a selection — as a shift without `:skipping` does, where it raised.

* A value holding a group of a set (`2026Y{1,2}G3MU`) returns a `Tempo.ConversionError` from `at/2`, `on/2`, `trunc/2`, `nearest_workday/2`, `at_resolution/2` and `extend_resolution/2`, where they raised. `Tempo.trunc/2` of a value holding a selection drops the selection at or above the units before it (`2026Y4M`), where it raised a `KeyError`.

* A value's selection with a time after it enumerates as the span it selects (`Enum.to_list(~o"2026Y4ML1K1INT10H")` is the one hour), as a selected day and a recurrence's occurrences do, where it was walked by its sixty minutes.

* A month alone with a time after it (`6MT10H`) parses, as a year and a month with one does, and a month counted from the end with a time after it is its year's month (`2026Y-1MT10H` is 10:00 on 1 December).

* A qualified set is written with its qualification once after the set (`{2026Y6M15D,2026Y6M16D}?`), where it was written on each member inside the braces, which does not parse, and a range member is qualified at both ends, where it lost the qualification.

* `Tempo.to_calendar/2` keeps a value's qualification, metadata, zone and tags, and a qualified year, month or day qualifies every unit of the converted date, where the converted value was rebuilt from a `Date` without them.

* A set's `[zone]` and `[key=value]` suffix is each member's that has none of its own, and is written once after the set, as a recurrence's domain's is after the recurrence: `{2026-06-15T10:00,2026-06-16T10:00}[Europe/Paris]` is two times in Paris, where its members were floating and its tags dropped.

* The `[zone]` suffix of a recurrence with no start (`R/../P1Y/FL3M20DN[+09:00]`) is kept on its rule, written back after the recurrence and given to the occurrences a `:within` window supplies, where it was parsed and dropped.

* A unit after a group under a set, a range or a mask of years counts from the group's start, as it does under one year: `{2026,2028}Y2G2MU15D` is 15 March of each year, where it was the 15th of each month of the group.

* An unspecified year (`X*Y`) is no year in particular in every operation, as ISO 8601-2 §4.6.2 reads it: `Tempo.anchored?(~o"X*Y6M")` is `false`, its walk is the days of a June of no year, and `Tempo.at/2` places it on a year. The walk read it as the current year, and comparisons and set operations as a year later than every other.

* A month or a year added to a day of the week that names no week (`7K`) is a `Tempo.UnanchoredError`, since the day of the week it falls on depends on the date, where it was that day again; weeks, days and the time of day still step it.

* A shift that reaches an unspecified month, day, hour, minute or second (`X*`) moves the block of values it stands for, as a mask of all its digits does: `Tempo.shift(~o"2026Y6MX*D", day: 1)` is one of 2 June to 1 July, where it was 1 July, and a shift back is no longer refused.

* A recurrence whose start has no year starts on a dated `:within` window, as `Tempo.at/2` places a value: `R/T22H/PT1H` within 15 June is 22:00 and 23:00 that day, and a day of the week starts on the first one in the window, where such a recurrence gave nothing.

* Dates and values in a calendar whose year turns after its first month (Calendrical's Julian `March25`, `March1`, `Sept1` and `Dec25`) are ordered by their days, where they were ordered by their fields: a `Date.Range` from 31 December to 1 January of one such year converts to its two days, where it was refused as empty.

* A value in a calendar of weeks takes day resolution as its day of the week, so `Tempo.at_resolution/2` to `:day` gives `2026-W25-1`, and a value's selection (`2026YL1K1IN`), a `:within` window and `select/2` select in it, where they gave the whole span or a `Tempo.ResolutionError`.

* A recurrence's selection by day of the week applies in a calendar of weeks: in `Calendrical.ISOWeek`, `R3/2026-W01-1/P1W/FL2KN` is each week's Tuesday and `R3/2026-W25-1/P1Y/FL25W2KN` the Tuesday of week 25, where they gave each week's Monday and nothing.

* A recurrence from a start that holds a set or a range is a recurrence from each of its values: `R3/2026Y6M{1,15}D/P1M` is six occurrences, where it was three intervals whose ends held the set, or a `Tempo.ConversionError` when its values could not all take the step alike.

* A recurrence with no year goes on round its axis: `R3/T22H/PT1H` is 22:00, 23:00 and 00:00 and `R3/6K/P1D` Saturday to Monday, where an occurrence past the end of the axis was dropped and the first repeated. A cadence that brings such a start back to itself (`R3/7K/P1W`, `R3/T22H/P1D`) is a `Tempo.ConversionError`, where its occurrences had no length.

* A day counted from the end of a month under a year that is a set, a range, a mask or unspecified is the last day of that month in each year: `{2026,2027}Y2M-1D` is 28 February of each, where it was read as the 29th before the year was known and named nothing.

* `Enum.count/1`, `Enum.at/2` and `Enum.slice/3` of an interval whose end is finer than the unit it is walked by count the step that starts before the end, as the walk takes it: `Enum.count(~o"1985/1986-06")` is 2 where it was 1, and an hour walk to `T12:30` counts the 12:00 step.

* An interval end written as a group, a mask or significant digits is read as the point its span starts at, so `Tempo.relation(~o"20C/21C", ~o"2050")` is `:contains` where it was `:preceded_by`, and `overlaps?/2`, `within?/2`, the set operations, `duration/1` and the length predicates answer by that point where they answered wrongly or raised. `Tempo.to_interval/1` gives such an interval its points (`2000Y/2100Y`), and an end that names several spans (a set, a selection) is a `Tempo.IntervalEndpointsError`.

* `Tempo.from_iso8601/1` returns a `Tempo.ParseError` for a century or a decade that is not one whole number — a fraction (`20.5C`), unspecified digits (`1XC`, `X*J`), a set or a range (`{19,20}C`), a margin of error or significant digits — where it raised an `ArithmeticError` or misread a fraction, and reads two digits with a fraction as an hour (`09,5` is 09:30).

* `Enum` walks a value whose week, day of the week, day of the year, hour, minute or second is unspecified (`X*`) or masked, and a mask counted from the end (`2026Y-XM`, April to December), where it raised a `FunctionClauseError` or never returned. An unspecified hour, minute or second counts from 0, where it counted from 1, and `Tempo.to_interval/2` narrows a masked day of the week or of the year as it narrows a masked month.

* Each unit of a walked value is read after the values before it: `Enum.count(~o"1985-XX-XX")` is 365 where it was 372, `1985-XX-31` is the seven 31sts where it yielded 31 February, and `{2026,2027}Y-1D` is the last day of each year. `Tempo.to_interval/2` lists its members by the same walk, so `2026Y{100,200}D` is 10 April and 19 July where it was 10 and 19 January, and `2026Y{2,6}MX*D` is February's 28 days and June's 30 where it was 28 of each.

* A value that cannot be walked raises a named error — `Tempo.UnanchoredError` for a unit that needs a year the value lacks (`X*W`, `{1..-1}W`), `Tempo.InvalidDateError` for a mask no value matches (`1985-02-3X`), `Tempo.ConversionError` for a group of a set — where `Enum` raised a `FunctionClauseError`, a `KeyError`, an `ArgumentError` or a `Protocol.UndefinedError`, or never returned. `Tempo.to_interval/2` returns where it raised: an error for `{1..-1}W` and `3m`, and two spans for `2026Y6M{1,15}DT10H30M15.5S`.

* A value that holds a selection enumerates as the spans `Tempo.to_interval/2` gives it — `Enum.to_list(~o"2026Y6ML2KN")` is the five Tuesdays of June 2026 — where it raised an `ArgumentError` or yielded hours that still held the selection. An interval from one (`2026Y6ML2KN/P1D`) walks the same way, where it raised.

* An interval with no year is counted, indexed and searched by its walk (`Enum.count(Tempo.to_interval!(~o"6M"))` is 30, where it raised a `KeyError`), and one that ends before it starts walks round its axis: `T22H/T2H` is 22:00 to 01:00 and `7K/3K` Sunday to Tuesday, where both were empty. A walk takes a step only when it goes on, so `Enum.take(~o"2M27D/..", 2)` is 27 and 28 February, where it raised.

* An interval whose start or end is no one point (`{2026,2027}Y/2030Y`, `2026Y/202XY`, `1M/-1M`) raises `Tempo.ConversionError` or `Tempo.IntervalEndpointsError` when it is walked, where it yielded nothing, walked past its end without stopping, or raised a `CaseClauseError` when counted.

* `Enum.count/1`, `Enum.at/2` and `Enum.member?/2` of a second, a fraction of one and a year with significant digits agree with their walk: `Enum.count(~o"2026-01-15T10:30:00")` is 10, its tenths, where it was 1, and `Enum.count(~o"1950S2Y")` is 1,200 months where it was 100 years.

* A margin of error (`2018±2Y`) is walked as the value it annotates, where it raised, and a year with significant digits in a set (`1950S2Y{1,2}M`) as each year of its block, where it was two values and converted to the century twice. A year mask below zero (`-1XXX`) is walked from its earliest year, and an unspecified traditional month (`X*m`) is an unspecified month, where `Tempo.to_interval/2` raised.

* A day of the week that names no week spans and steps on its own axis: `Tempo.to_interval(~o"{6,7}K")` gives both days, `~o"7K"` spans `7K/1K` and `~o"7K"` plus a day is `~o"1K"`, where the last day of the week raised a `KeyError` and a day added to any left it where it was. A step back from a value with no year borrows as a step forward carries (`~o"T0H"` less an hour is `~o"T23H"`), where it raised.

* `Tempo.shift/3` and the spans of `Tempo.to_interval/2` no longer count from a unit that holds several values (a set, a range or a group): a step every one of them takes alike is computed (`~o"2026Y{6,7}M15D"` plus a day or a year), and any other returns `Tempo.ConversionError` with `reason: :grouped_component`. Such a step raised, collapsed the set (`~o"2026Y6M{1,15}D"` plus a day was `~o"2026Y7M1D"`), left the value as it was or returned a bare atom.

* An interval's duration or a recurrence's cadence that cannot be counted from its start returns the error of the step, where `2M28D/P1D` held the error as its end and `R3/12M31D/P1M` raised a `FunctionClauseError`. An end that would be a set of candidates (`202XY/P1D`) is an error too, and enumerating an interval whose next step counts from a set raises `Tempo.ConversionError`.

* A set's members — each end of a range, each excluded member and each interval among them — are checked as a value on its own is and are in the calendar the set is written for, so `{2026-02-30}` is an error and `{5786-06-15,5786-07-01}[u-ca=hebrew]` is two Hebrew dates, where a set took any member and held it as a Gregorian date. A recurrence's domain is checked too, and keeps its Gregorian years.

* `Tempo.to_iso8601/1` and `inspect/1` write a set's calendar once after it (`{5786Y6M15D,5786Y7M1D}[u-ca=hebrew]`) and a recurrence's after its rule (`R/5786Y1M1D/P1Y/FL7M1DN[u-ca=hebrew]`, with a start or a domain), so both read back in it, where a recurrence's rule read back as Gregorian.

* `Tempo.union/2`, `intersection/2` and `difference/2` take a set whose member is a range (`{2026-06-15..2026-06-20}`), where they raised.

* A whole date written with a month and a day, or as a day of the year, for a calendar of weeks is the Gregorian day converted into it, as Localize reads it: `~o"2026-06-15"W` and `Tempo.new(year: 2026, month: 6, day: 15, calendar: Calendrical.ISOWeek)` are `~o"2026-W25-1"W`, where each held a month and a day its calendar has none of. Anything less than a whole date there, and a month or a day of one placed on (`at/2`, `on/2`) or selected in (`select/2`) a week calendar's value, is a `Tempo.ConversionError`.

* A date converted into a calendar of weeks is qualified in every unit when its year, month or day was: `2026-?06-15[u-ca=iso-week]` is `2026-W25-1?`.

* `Tempo.at/2`, `on/2` and `extend/1` check a value in its own calendar, so a Hebrew leap year takes its thirteenth month and a week date keeps its shape when a time is placed in it, where each was checked as a Gregorian date.

* `Tempo.to_interval/2` returns an error for a recurrence whose start its cadence cannot step (a month from a week date, months from a quarter) and for a selection by a month, a day of one or a day of the year in a calendar of weeks, where it raised or left the selection out.

* `Tempo.select/2` gives a week calendar's days as week dates, where it built them with a month, and skips a span either end of which cannot land (29 February, in a common year), where it raised.

* `explain/1` names a month as its calendar does (a Hebrew `5786-06-15` is "Adar 15, 5786", a Persian selection "in Farvardin"), where every calendar's months took the Gregorian calendar's names. A lunisolar month with no year, which no one name fits, is given by its number.

* `explain/1` headlines a value holding a set or a group by what it names — "June and July 2026", "The 1st and 15th of June 2026", "January to March 2026" for a quarter — where it named only the units before it ("The year 2026"). A set of years is no longer called a value with no year, and a set of hours is written as its clock times, not `??`.

* `explain/1` describes a week, a week date and every value in a week calendar by its week and the days it spans (`~o"2026-W25"` is "Week 25 of 2026", spanning `[2026-06-15, 2026-06-22)`), where it called each "The year 2026" with an empty span. A week calendar's dates are written in its own notation (`2026-W25-2`).

* `Tempo.to_string/2` takes a skeleton or a pattern for a span of several values (`format: :yMMMd` on `2026-06-15/2026-06-18` is "Jun 15 – 17, 2026"), where it returned Localize's error.

* A day, a day of the year, a month or a week of 0 is refused, and a month with no year is no further from either end than the most months a year of its calendar has (`13M` is refused in the Gregorian calendar, allowed in the Hebrew), where they parsed.

* `explain/1` describes a `Tempo.RecurrenceSet` member by member, each led by its name (a holiday's `:name`, an event's `:summary`), and a conditional member on its own, where it said it did not know how to describe them.

* `Tempo.to_interval/2` expands a recurrence written with a start and an end, or a duration and an end (ISO 8601-1 §5.6.1), to its occurrences, where it returned it unexpanded, and `R0` to an empty set. `explain/1`, `duration/1` and `Tempo.RRule.to_string/1` read both forms as recurrences, and `explain/1` an RRULE `UNTIL` as bounded.

* A partly masked unit is the span its digits allow, `2026-06-1X` the 10th to the 19th of June and `2026-06-X5` three days, where `to_interval/2` widened it to the month. A masked week before a day of the week (`2026-W1X-3`) and a set of week dates (`2026-W25-{1,3}`) materialise, where they raised.

* `Tempo.to_string/2` renders a mask, group, set, selection or recurrence as the spans it names, where it rendered the bare year (`2026YL1K1IN` as "2026"), the first span or Localize's error; a month without a year as its name, and a duration's fraction of a second. A week or a day of the week without a year is an error naming it.

* Units written after a recurrence's selection apply to every date it picks, so `R/../P1M/FL5K2INT9H0M` fires at 09:00 on the second Friday, where each occurrence was the whole month. An RRULE ordinal weekday's times take this form, so `BYDAY=2FR;BYHOUR=9,17` fires on the second Friday at both times, where it fired on the first Friday at 17:00.

* `Tempo.to_iso8601/1` returns an error for a recurrence with an RFC 5545 `UNTIL`, which ISO 8601 has no form for, where it raised, wrote a form that did not parse, or wrote the end as the first occurrence's. It writes ISO 8601's duration/end form with a repeat rule (`R/P1D/2026Y12M31D/F…`), where it dropped the duration.

* `Tempo.Cron` fires on the values a step steps to and on every value of a `*`: `*/15 * * * *` at 0, 15, 30 and 45 past each hour whatever the start, `0 * * * 1` every hour of a Monday. Each firing is a minute (a second with six or seven fields), from the first whole one at or after `:from`.

* `Tempo.Cron` fires an ordinal weekday (`5#2`, `5L`) within each month, keeps a year field's years through `parse/2` with a single year bounding both ends, and composes a day field that starts with `*` with AND, as Vixie cron does.

* `Tempo.Cron.parse/2` returns an error for a `:from` that is not a date or time, and `Tempo.to_iso8601/1` for a cron day-of-month OR day-of-week union, where both raised.

* A recurrence whose selection only limits its steps keeps each step whole, as it is without the selection: `R/../PT1H/FL1KN` is a Monday's hours from the first, and `R/2026-01-05/P1W/FL1MN` January's weeks, where each occurrence was cut to one unit of its start, so the first hour was the whole day.

* `Tempo.shift_zone/2` keeps a value in its own calendar, with its calendar annotation, tags, metadata and qualification, where it wrote the Gregorian wall clock under the value's calendar and dropped the rest.

* `Tempo.shift_zone/2`, `now/1`, `utc_now/0` and `from_elixir/1` of a `DateTime` write one time zone annotation, `2026Y3M8DT9H0M0SZ-4H[America/New_York]`, as RFC 9557 allows, where they added the offset as a second (`[-05:00]`) that went stale when the value was shifted across a change of offset.

* `Tempo.to_iso8601/1` writes a value's calendar however the value was made, so a Hebrew date from `Tempo.to_calendar/2` reads back as Hebrew, where it read back as Gregorian; a calendar IXDTF cannot name whose days the Gregorian calendar numbers differently, such as a fiscal year, is an error.

* A week-based calendar's value (the ISO week or NRF calendar's, or a retail one's) has ISO 8601's week date shape however it is made, and `Tempo.to_iso8601/1` writes it as ISO 8601-2's `2026Y25W2K[u-ca=iso-week]`, which reads back, where it wrote `2026Y25W2D` or `2026Y25M2D`. Such values compare, shift by days and weeks, round and convert, where comparing a parsed one raised, and a month added to any week date is an error, where it raised.

* `Tempo.day_of_week/1`, `day_of_year/1`, `quarter_of_year/1`, `split/1` and `round/2` read a week date as the day it names, where they read it as 1 January of its year or split its day off as a time.

* `Tempo.to_string/2` renders a week date as the day it names and a week, or a range of weeks, as its first and last day ("Jun 15 – 21, 2026"), where it rendered the year alone. A week calendar's day is written in that calendar's own notation ("2026-W25-2").

* A network's relation delays set its axis, so a six-month gap between year-dated periods is six months, where it rounded to a year, and a bound on a finer axis is the span it names, so `{:not_after, ~o"1300Y"}` allows all of 1300. A network counting only weeks is placed in days, where it raised.

* `Tempo.Schedule.span/1` returns an error for a plan with no tasks or no fixed start, where it raised.

* An integer index a period does not have selects nothing, where `Tempo.select(~o"2026-02", [30])` made a 30 February; a negative index counts from the end, so `[-1]` on a year is December.

* `Tempo.select/2` returns an error for an open-start span, a quarter with integer indices or a list holding a non-selector, where it raised, and converts a duration-form interval or a recurrence, where it refused them.

* `Tempo.to_interval/2` and `to_interval_set/2` return a `Tempo.ConversionError` for a value that is not a Tempo value, where they raised `FunctionClauseError`, and the error names a module target as `Date`, not `Elixir.Date`.

* `Tempo.now/1` and `today/1` return `{:error, %Tempo.UnknownZoneError{}}` for a zone the time zone database does not know, where they raised.

* `Tempo.to_date/1` returns a `Tempo.ConversionError` for a value whose year, month or day is a group or a range, where it raised `FunctionClauseError`.

* An iCalendar or RRULE rule with `COUNT=1` occurs once for the event's length, where its occurrence spanned the rule's frequency (a week for `FREQ=WEEKLY`).

* A day that enumerating a week gives (`2026Y40W1K`) materialises as a day and takes hours, carrying across days and weeks, and `Enum.at/2`, `count/1`, `slice/3` and `member?/2` read a week, where they raised.

* A day added to a zoned time that lands in a spring-forward gap moves on by the gap (RFC 5545 §3.3.5), and an offset the value carries follows the reading it lands on, where the result named a time that does not exist.

* A recurrence walks every period its `:within` window overlaps, however the window is aligned — `R/../P1Y/FL1M15DN` within September 2026 to March 2027 is 15 January 2027, where it was nothing — and an UNTIL holds every day a period's selection expands to.

* An interval written as a start and a duration (`2026-01-01/P1D`) or a duration and an end (`P1D/2026-01-02`) answers `relation/2`, the relation, certainty and duration predicates, `duration/1`, `bounded?/1`, the endpoint accessors and `IntervalSet.new/2` as its two-endpoint form does, where they raised, crashed or read it as open-ended.

* A duration in the ISO 8601 alternative format (`P0002-01-10T22:33:55`) is the duration its designator form writes, where it was held as a nested date that nothing read; a week date or a day of the week there (`P2K`) is a `Tempo.ParseError`.

* RRULE `BYWEEKNO` numbers weeks from `WKST` as RFC 5545 does, so 2026 has a week 53, and a week keeps its days in the year before or after. `BYDAY` picks within each week, `FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO` from 1997-05-12 being the RFC's May 12, May 11 and May 17 where it gave every Monday of 1997, and a rule without one takes DTSTART's weekday (ISO 8601-2 Annex C.3).

* Every calendar Calendrical implements has a `[u-ca=…]` identifier, from Calendrical's additional calendars where no CLDR type reaches it: `[u-ca=iso8601]` is `Calendrical.ISO`, where it was an unknown calendar, and `[u-ca=vietnamese]`, `[u-ca=lunar-japanese]`, `[u-ca=julian-march25]` or `[u-ca=reform-england]` its own calendar, where the suffix was silently dropped.

* A calendar week (`w`) holds the days Calendrical gives it, so a Hebrew, Islamic, Julian or other week cut short at the start or end of its year spans only its own days (`5787Y1w` is 1 Tishri alone), and its day of the week (`K`) is ISO 8601's. Every Calendrical calendar now numbers `w` weeks.

* A value holding a selection materialises one period of its context at a time (ISO 8601-2 §12.11): `2018Y3ML1K1IN` is 5 March 2018 and `2018Y9ML1K1IN/P5D` the five days from it, where both raised, and US Election Day in any even year takes under a millisecond against a few years' bound, where it ran for minutes.

* A year mask with a digit set (`XXX{0,2,4,6,8}Y`) no longer raises `FunctionClauseError`: `Tempo.Mask` bounds and matches a digit set.

* A year in a recurrence's selection limits it to the occurrences its listed years select, as a domain does: `R/2026-01-01/P1Y/FL2027Y1M1DN` is 1 January 2027 alone, where the year was ignored. A set, range or mask of years, or `X*Y`, works too.

* `Tempo.RRule.to_string/1` returns a `Tempo.ConversionError` naming any selection RRULE cannot express — a traditional month (`m`), a computed event (`e`), a year, a selection window, and cron's nearest weekday and day-of-month-or-weekday — where it silently dropped them.

* A week (`W`) is an ISO 8601 week throughout — dates, week counts, arithmetic, rounding, groups and selections — counted over the calendar's own year in a non-Gregorian calendar. `2026Y53W` is valid, `Tempo.shift(~o"2026Y52W", week: 2)` is `2027Y1W` and Hebrew `5787Y10W1K` is 6 Kislev, where week counts were the Gregorian calendar's and Hebrew week dates came from the Gregorian year 5787.

* The ISO 8601-2 quarters, quadrimesters and semesters (codes 33–41) are the value's calendar's own periods, from Calendrical: a Hebrew leap year's Q2 holds Adar I and II and its Q4 runs to Elul, and a week-based calendar's are groups of weeks.

* A group of hours, minutes or seconds holds clock values from 0: `T16H1GT15MU` is 16:00–16:15 and `6GT2HU` 10:00–12:00, where both started an hour or minute late.

* A group counted from a year alone materialises — weeks (`2026Y2G13WU`), days (`1933Y1G80DU`) or hours (`2018Y20GT12HU`) — and a trailing group ends with its year or month, while one that starts beyond it (`2026Y5G3MU`, month 13) is an error.

* A group renders as it was declared, `3GT8HU` with its `T`, where the last group of a month re-rendered as another (`2018Y2M3G11DU` as `2018Y2M4G6DU`).

* A group whose size is not a duration (`2026Y1G2KU`) returns a `Tempo.ParseError`, where it raised `KeyError`.

* `Tempo.new(year: 2026, day_of_year: 166)` is the date it names, as `2026-166` parses to, so conversion, comparison and enumeration read it; a day the year lacks is an error.

* A fractional year or month lands on the day its elapsed fraction reaches: `1985.5Y` is noon on 2 July and `1985Y2.5M` is 15 February, a day later than before.

* `Tempo.new/1` and `Tempo.from_iso8601/2` take `Calendar.ISO` as `Calendrical.Gregorian`, as the other entry points do.

* A negative UTC offset with minutes carries its sign on its first non-zero component throughout: a `DateTime` in America/St_Johns becomes −03:30, where its shift read as −02:30, and `-00:30` keeps its sign.

* A day after a season is the season's nth day, as a day after a quarter is: `2026-25-10` is March 29, where it produced a value with two day components.

* `Tempo.from_iso8601/1` returns a `Tempo.ParseError` for an out-of-range day in the explicit form (`2026Y1M40D`), where it raised `FunctionClauseError`.

* An astronomical season whose equinox or solstice falls outside the years Astro computes returns a `Tempo.ParseError`, where it raised `MatchError`: `0999-25`, and `3000-28`, whose winter ends at the March equinox of 3001.

* A season in a non-Gregorian year is the Gregorian season that starts within it, with endpoints in that calendar: `5787-25[u-ca=hebrew]` is 11 Adar II to 16 Sivan, where it asked Astro for the equinox of the year 5787. A year that holds none, such as Islamic 1422, returns a `Tempo.InvalidDateError`.

* A meteorological season holds all three of its months, `2026-21` being `2026Y3M/6M` where it ended on 1 May. A season a year with unspecified digits cannot place (`20XX-24`, `20XX-21-10`) returns a `Tempo.InvalidDateError`, where it raised.

* `Tempo.parse/2` keeps a UTC offset as the value's shift, as `from_iso8601/1` does, so `"2026-05-23T14:30:00+05:00"` is 14:30 at +05:00; since Calendrical 1.4 keeps the offset's wall time, it had become 14:30 UTC.

* `Tempo.parse/2` reads a week of the year (`"week 1 of 2026"`) as the week `from_iso8601/1` reads in `2026-W01`, and a weekday beside a full date (`"Monday, May 25, 2026"`) as implied by the date, where both were rejected.

* Adding years to a Hebrew or lunisolar date keeps its traditional month, as the calendar's own arithmetic does: `Tempo.shift(~o"5786Y7M15D[u-ca=hebrew]", ~o"P1Y")` is 15 Nisan 5787, `5787Y8M15D`, where it kept month 7 (Adar II).

* Hebrew years validate, enumerate and step through their months as `1..12` or `1..13`, now that Calendrical numbers a Hebrew month by its position: `5785Y12M` is Elul and `5785Y13M` an error, where Elul was rejected and a missing month 6 appeared.

* `Tempo.Network.Relation.from_allen/1` preserves direction for `:overlapped_by`, which previously mapped to `:overlaps` and silently reversed the operands. Every Allen relation now round-trips through `to_allen/1`.

* A recurrence with an open start materialises within a `:within` window alone: `Tempo.to_interval(~o"R/../P1Y/FL6M1K2IN", within: ~o"2026")` is the second Monday of June 2026. Each occurrence takes the resolution its selection names — `FL6MN` a month, `FL12M25DN` a day.

* `Tempo.select/2` selects with an ISO 8601-2 selection — a computed event, a §12.10 window, any `L…N` — in each period, units before it narrowing the period first, where it silently selected nothing.

* `Tempo.at/2` and `on/2` place an interval endpoint by endpoint and keep a selection after the units it selects in (`4ML1K1IN` on 2027 is `2027Y4ML1K1IN`), where they raised.

* `Tempo.duration/1`, `Tempo.Interval.duration/2`, `Tempo.IntervalSet.duration/1` and `Interval.leap_seconds_spanned/1` return an error where they raised: for an endpoint without a year, a finite recurrence, endpoints in different calendars or a value that is not an interval. An endpoint naming a span is read from where its span starts, so `20C/2100` is a hundred years, where it measured none.

* `Tempo.from_iso8601/2` reads a computed event or a week start (`q`) in a value's selection, so `2027YL(easter)eN` is Easter 2027, where it raised `KeyError`.

* `Tempo.shift/3` returns an error for a value holding a selection shifted by a unit it does not carry, a day on `2027Y4ML1K1IN`, where it raised or ignored the unit, and for arguments that are not a Tempo value and a duration, where it raised.

* A time-of-day selection moves an event's whole span: an iCalendar event from 09:00 to 10:00 with `BYHOUR=9,17` is also 17:00–18:00, where it ran from 17:00 back to 10:00, and `BYMINUTE` and `BYSECOND` likewise.

* `Tempo.to_iso8601/1` and `inspect/1` write an interval whose ends differ only in a fraction of a second, `2026Y6M15DT10H0M0.123S/T0.124S`, where they raised `FunctionClauseError`.

## [v1.6.4] — 2026-09-03

### Fixed

* `Tempo.select/2` no longer projects a date that cannot exist. Selecting `~o"2M29D"` across `~o"{2026..2029}Y"` yields only 2028, where before it fabricated four February 29ths.

* `Tempo.explain/1` describes every representation. An audit over all 1777 ISO literals in the repository found 140 values it crashed on, described generically, or described wrongly; all of them now explain.

* A yearless date (`~o"4M3D"`, a birthday) is no longer reported as "an anchored Tempo value" with a `[?, ?)` span. It reads as "April 3, in any year".

* `Tempo.to_interval/1` no longer raises on a yearless week (`1W`), a clock-only value (`T-1S`), a bare offset (`Z`), or a grouped component (`2018-{1,3,5}G2MU`). Grouped components report `Tempo.MaterialisationError` rather than crashing inside `Keyword`.

* `Tempo.resolution/1` handles a value with no components, and grouped components resolve to their group size instead of raising `CaseClauseError`.

## [v1.6.3] — 2026-09-03

### Fixed

* An interval's `[u-ca=…]` calendar now propagates backward from its end onto an endpoint carrying no tag of its own, as the zone already did. `1448Y9M24D/25D[u-ca=islamic-civil]` was parsing as a mixed Gregorian/Islamic pair, which its abbreviated end cannot mean.

* An interval whose endpoints share a calendar writes `[u-ca=…]` once, at the end. A deliberately mixed pair still names the calendar on each endpoint.

## [v1.6.2] — 2026-09-03

### Fixed

* An interval whose endpoints share a zone writes the IXDTF suffix once, at the end (`2026Y9M2DT18H/T20H[Australia/Melbourne]`), where before it was repeated on both. A per-endpoint `[u-ca=…]` is still written on each, because it decides how that endpoint is read.

* `2026-09-02T18:00/2026-09-02T20:00[Australia/Melbourne]` — the suffix written once, as IXDTF defines it — no longer fails endpoint-order validation. The endpoint frame now propagates before the order check rather than after.

## [v1.6.1] — 2026-09-03

### Fixed

* Un-anchored arithmetic reports a missing anchor by return value rather than `throw`, so it can no longer escape to a caller as an uncaught `{:tempo_math, :requires_anchor}`. `lib/` now contains no `throw`, `catch` or explicit `try`.

* `Tempo.to_interval/1` materialises an unspecified year (`X*Y12M28D`) instead of raising a `FunctionClauseError`. Where the answer depends on the missing year (`X*Y2M28D`) it returns `Tempo.RequiresAnchorError`.

* `Tempo.to_interval/1` resolves a yearless masked month (`XX-15`, the 15th of any month) instead of raising a `KeyError`. Calendars whose month count varies by year return `Tempo.RequiresAnchorError`.

* Enumerating a masked value that needs an anchor (`XX-15` in a calendar whose month count varies by year) raises `Tempo.RequiresAnchorError` rather than a bare `KeyError`. `Enumerable` has no error channel; `Tempo.to_interval/1` returns an error tuple for the same value.

* `Tempo.explain/1` describes a start-and-duration interval (`2026-06-15T09:00/PT8H`) rather than reporting "an unusual shape".

* `Tempo.explain/1` no longer calls a duration-and-end interval (`P1D/2026-06-15`) open-lower. The duration implies the lower bound, so the value is bounded.

* `Tempo.explain/1` explains an unanchored recurrence (`R/../P1Y/FL11M4I4KN`) instead of reporting "an unusual shape". Its selection, cadence and missing anchor are now named in prose.

## [v1.6.0] — 2026-09-02

### Added

* `Tempo.parse_date/2`, `parse_datetime/2`, `parse_time/2`, `parse_interval/2` and `parse_duration/1`, with bang variants, parse a string that must be one ISO 8601 shape. A date, a datetime and a time are all `%Tempo{}`, so `from_iso8601/1` cannot report a time of day arriving in a date field; declaring the profile makes it an error.

* Profile parsing is 4–28× faster than `from_iso8601/1`, being a narrower grammar. Correctness, not speed, is the reason to prefer it.

* `parse_time/2` reads `"2026"` as 20:26 where `from_iso8601/1` reads the year 2026 — the declared profile resolves the ISO 8601 basic-format ambiguity.

### Fixed

* Count-from-the-end bounds on fixed-extent units now resolve at validation, so a set-valued clock component expands instead of yielding nothing. `T{-4..-1}H` is the last four hours of the day.

* Week-and-weekday and ordinal-day values with ranges (`{1..3}W{1..-1}K`, `{1..-1}O`) expand to real calendar dates. `{1..-1}O` previously raised a `KeyError`.

* A set resolving to a single member collapses to that member (`{12..-1}M` is `12M`), fixing a `FunctionClauseError` in `days_in_month/3`.

* Ranges in any combination of component positions now expand: `{2000..2010}Y{1..-1}M{1..-1}D` yields its 4018 days instead of looping forever. Each component resolves against its already-concrete coarser units, so a month range follows the year's own month count and a day range the month's own length.

* A day set under a month of unknown length is bounded by that month's maximum across years rather than refused, so `{2020,2021}Y2M{1..-1}D` and yearless `2M{1..-1}D` resolve. Days that exist in no year (`2M30D`) and day sets overflowing a concrete month (`2026Y9M{28..31}D`) are still rejected.

## [v1.5.4] — 2026-09-01

### Fixed

* A negative component under a set-valued container (`~o"2026Y{1..12}M-1D"`, the last day of each month) resolves against each expanded member's own context — leap-aware, per ISO 8601-2 §4.4.1 — instead of leaking an unresolved `-1` into the materialised intervals. The literal, the recurrence (`R12/2026-01-01/P1M/FL-1DN`), and `Tempo.select/2` now agree.

* RRULE `BYMONTH` expansion no longer lets DTSTART's day-of-month filter occurrences: when `BYMONTHDAY`/`BYDAY` determine the day, results are identical from any DTSTART (a rule anchored on the 31st no longer returns leap-years-only or empty sets), and when nothing later sets the day, the anchor's *original* day clamps to each occurrence's month — per occurrence, leap-aware, in every calendar (Feb 29 anchors restore the 29th in leap years; Hebrew day-30 anchors track each year's month length; leap months drop in common years).

## [v1.5.3] — 2026-08-30

### Fixed

* `Tempo.to_elixir/1` and `to_date_time/1` convert offset-grounded values: a `Z` or `+10:00` value becomes the instant as an `Etc/UTC` `DateTime` (matching `DateTime.from_iso8601/1`'s normalisation), a zoned value keeps its zone instead of degrading to a `NaiveDateTime`, and a floating value's refusal now says why and points at `Tempo.in_zone/2`.

* A negative UTC offset with minutes (`-03:30`) projects as −(3 h 30 m), not −3 h + 30 m — comparisons and conversions for half-hour zones west of Greenwich were off by an hour.

* `Tempo.equal?/2` compares member extents by instant, so the same moment expressed at different offsets (`09:00+05:30` vs `03:30Z`) is equal, agreeing with `relation/2`.

### Added

* `Tempo.shift/2,3` accepts an ISO 8601 duration string (`Tempo.shift(t, "-PT30M")`) — iCalendar `DURATION`/`TRIGGER`/`REPEAT` values shift without a parse at every call site; a string that parses to a non-duration is refused with direction.

## [v1.5.2] — 2026-08-26

### Fixed

* `Tempo.equal?/2,3` now ignores per-member metadata, honouring its contract: two extent-equal values differing only in metadata (a summary, PRODID) compare equal and agree with `Tempo.compare/3`'s `:eq`. The internal unit-strip was leaving metadata on the struct comparison.

## [v1.5.1] — 2026-08-26

### Fixed

* An interval end that omits the components it shares with its start — `2018-01-15/02-20`, ISO 8601-1 §5.5.1 — now inherits them, so it is anchored rather than a fragment.

* Fix `Tempo.to_string/1` for partial dates/times.

### Changed

* `inspect/1` and `Tempo.to_iso8601/1` drop the prefix an interval's end shares with its start: `2026-06-15/2026-06-16` prints as `~o"2026Y6M15D/16D"` and round-trips.

## [v1.5.0] — 2026-08-26

### Changed

* Calendrical 1.3 and Astro 2.5 in the lock: every calendar-touching example in the cookbook, guides, and livebooks re-validated by execution; Hebrew and Islamic calendar weeks now parse and materialise through Tempo (`Tempo.from_iso8601("5786-W03", Calendrical.Hebrew)`), and `beginning_of_week/1` on those calendars lands on their own week start.

### Added

* `Tempo.Duration.compare/3` — compare two durations by length, so `Enum.sort/2`, `Enum.max/2` and `Enum.min/2` take the module the way they take `Date`, `Time` and `Tempo`. Length, not shape: `PT90M` and `PT1H30M` are `:eq`. A duration containing `:month` or `:year` has no fixed length and raises unless given `relative_to:` — February and August are not the same size.

* `Tempo.Duration.subtract/2` (`add/2` of the negation) and the missing bang variants `Tempo.to_calendar!/2`, `to_interval_set!/1`, and `select!/2`, completing the `!` convention across the conversion and selection API.

* `Tempo.week/1` completes the component-accessor family for week-axis values (`~o"2026Y32W"`, Hebrew/Islamic calendar weeks, retail weeks): the week number, `nil` off the week axis, and an `ArgumentError` for an interval spanning more than one week.

* `Tempo.RRule.parse/2` accepts `:duration`, `:base_to` and `:metadata` — the occurrence-span controls `Tempo.RRule.Expander.to_ast/3` already had — so a parsed `RRULE` can carry a per-occurrence span rather than a granule at its resolution. `parse("FREQ=MONTHLY;BYDAY=1WE", from: dtstart, duration: ~o"PT2H")` emits two-hour occurrences, the RRULE echo of iCalendar's `DTSTART` + `DURATION`.

* `Tempo.IntervalSet.last/1` — the latest member interval, or `nil` when empty, pairing with `first/1`. Unlike `first/1`'s constant-time peek, it is O(n) and bounded-only: an unbounded set raises `Tempo.UnboundedSetError` rather than walking to find an end that isn't there.

* `Tempo.to_calendar/2` converts a day-resolution value from its calendar into another via `Date.convert/2` — `Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)` is 30 Tevet 5786, and it round-trips. `Tempo.to_calendar/1` is now a deprecated alias for `Tempo.to_elixir/1`, the outbound mirror of `from_elixir/2` that also converts durations. `Tempo.to_calendar/2` also takes a `t:Tempo.Interval.t/0` — converting both endpoints and carrying duration, recurrence, repeat rule, unit and metadata across untouched, with an unbounded end left unbounded — and a `t:Tempo.IntervalSet.t/0`, converting each member. Taking the whole span saves the caller pulling it apart and rebuilding it, which silently drops whatever it was carrying.

### Fixed

* Shifting a week-axis value by weeks (`Tempo.shift(~o"2026Y32W", week: 1)`) steps weeks natively with year-rollover carry instead of raising `KeyError`; component accessors (`Tempo.year/1`) on single-week intervals no longer crash for the same reason. Month-axis values still take a week as seven days.

* A day duration on a week-axis value computes as a `day_of_week` step (`~o"2026Y32W" + P2D` is `~o"2026Y32W3K"`, carrying across week and year boundaries), and a sub-day duration (`PT1H`) returns `{:error, %Tempo.ResolutionError{}}` instead of raising `KeyError` — the week axis has no path to an hour slot.

* The tour livebook called `Tempo.precedes?/2` (not a Tempo function — the predicate is `before?/2`) and compared a zoned time against a floating window; both cells now run. The `weekend?/2` doc describes the actual mechanism: the date converts to `Calendar.ISO` before the weekday is read, so Calendrical 1.3's culturally-native weekday numbering (Hebrew/Islamic weeks from Sunday, Persian from Saturday) cannot misclassify a weekend.

* `Tempo.trunc/2` with `:week` names the day that value's week begins on, at day resolution, instead of silently answering with the month. `trunc(~o"2026-08-16", :week)` returned `~o"2026Y8M"` — it walked past `:day`, found `:month` still coarser than `:week`, and gave back the **month**. It now answers `~o"2026Y8M10D"`, taking the week boundary from the value's own calendar so a Sunday-start calendar gives a different day from an ISO one. Units on another axis that name nothing expressible — `:day_of_week`, `:day_of_year` against a Gregorian value — return a `Tempo.ResolutionError` rather than an unrelated coarser unit. Coarsening within an axis is unchanged.

* Component accessors (`Tempo.year/1`, `month/1`, `day/1`, `hour/1`, …) on an interval exactly one granule wide now read the component instead of raising "ambiguous" when the half-open upper bound rolls into a coarser unit — so `Tempo.month/1` of `[2026Y12M, 2027Y1M)` (December 2026, e.g. from `Tempo.select(~o"2026", ~o"-1M")`) is `12`. A genuinely multi-unit span still raises.

* Materialised recurrence occurrences no longer carry the internal `occurrence_duration` / `occurrence_base_to` span directives in their metadata: they are consumed to size each occurrence and then dropped, so occurrences from a `DURATION`-bearing rule inspect cleanly instead of showing a spurious metadata key.

* `Tempo.to_elixir/1`, `to_date/1` and `to_naive_date_time/1` now preserve a non-Gregorian value's calendar at the native boundary, mapping only Tempo's internal `Calendrical.Gregorian` to Elixir's `Calendar.ISO`. Previously a Hebrew value converted to a `Date` mislabelled `Calendar.ISO` carrying the Hebrew numbers — a corrupt value; Gregorian conversions are unchanged.

## [v1.4.0] — 2026-08-26

### Added

* `Tempo.beginning_of_week/1` completes the family with `beginning_of_day/1` and `beginning_of_month/1`. **The week starts where the value's own calendar starts its weeks**, read from that calendar's `:day_of_week`, so a Sunday belongs to the preceding week under `Calendrical.Gregorian` and begins one of its own under a Sunday-start calendar.

* `Tempo.IntervalSet.members/1` — the member intervals as a plain list, the same value as `to_list/1` under a name that says which list you get. An IntervalSet enumerates the sub-points *inside* it, so `Enum.count/1` on two blocks totalling seven hours is 25,200 where `members/1` is 2; the two agree at day resolution, which is what makes the confusion hide until someone passes hours.

* `Tempo.from_date_range/1,2` (and a `Date.Range` clause on `from_elixir/2`) — converts Elixir's inclusive `Date.Range` to a half-open interval covering exactly the enumerated days, preserving the range's calendar. Stepped, descending, and empty ranges are refused; `from_date_range!/1,2` raises.

* Interval selectors in `Tempo.select/2` project as **spans**: `Tempo.select(workdays, ~o"T09/T17")` yields each member's half-open eight-hour window (previously a granule at the start). Lists give several windows per member, the duration form (`~o"T09/PT7H36M"`) expresses non-hour-aligned windows, and a window crossing midnight (`~o"T21/T05"`) rolls its end to the following day.

* `Tempo.Duration.add/2` and `Tempo.Duration.sum/1` — component-wise duration addition and list summation: like units sum without conversion, fractional seconds carry and borrow, and cancelling components drop. `sum([])` is the zero duration.

### Fixed

* A count-1 recurrence carrying a BY-rule — `FREQ=DAILY;BYDAY=SU;COUNT=1` — now materialises the first occurrence that *survives* the filter, agreeing with `COUNT >= 2`. Previously it returned the raw `DTSTART` period even when the rule excluded it (a Monday `DTSTART` under `BYDAY=SU`).

* `Tempo.select/2` with integer indices takes the unit from the base's own resolution, not from where its endpoints differ: `Tempo.select(~o"2026-07-31/2026-08-01", 9..16)` selects the hours of 31 July (previously the days 9–16 of July, and months at a year boundary — silently corrupting month-long traversals at their last day).

* `Tempo.relation/2` and `within?/2` between a week-axis value and a month/day-axis value no longer answer `:meets` for every pairing — mixed-axis anchored endpoints now compare by real dates, so `Tempo.within?(~o"2026-08-05", ~o"2026Y32W")` is `true`.

* Negative fractional-second durations are now correct end to end: `PT-1.5S` parses as −1.5 s (previously −0.5 s — the fraction ignored the sign), renders with a single leading sign (previously `PT-1.-5S`), `PT-0.2S` keeps its sign through a round-trip, and `-PT1.5S` no longer raises.

* The zero duration renders as `PT0S` (previously the unparseable `P`), so it round-trips.

## [v1.3.1] — 2026-08-22

### Changed

* Expanding a plain frequency recurrence (`FREQ=MINUTELY`, `FREQ=HOURLY`, `FREQ=DAILY`) is roughly 2× faster: each occurrence reuses the next occurrence's start as its own end — one date add per step instead of two — and adding a fixed-length unit to a crisp datetime skips `Tempo.Math.add/2`'s mask, annotation, and resolution prelude. The `Math.add/2` fast path speeds up every fixed-length shift, not only recurrence expansion.

## [v1.3.0] — 2026-08-16

### Added

* `Tempo.JSCalendar.from_jscalendar/2` reads [RFC 8984](https://www.rfc-editor.org/rfc/rfc8984.html) JSCalendar into a `t:Tempo.IntervalSet.t/0`, resolving each event's wall-clock `start` and `duration` in its own time zone. Requires the optional `jscalendar` dependency.

* `Tempo.JSCalendar` applies `recurrenceOverrides`, so an override that cancels, moves, lengthens or renames a single occurrence is honoured, and an event with overrides and no rules still recurs. Keys match on the recurrence id resolved in the event's zone, so a patched `start` moves the occurrence rather than duplicating it.

* `Tempo.ICal.available_from_ical/2` and `available/2` read [RFC 7953](https://www.rfc-editor.org/rfc/rfc7953.html) `VAVAILABILITY` — the time a calendar user *offers*, as against the `VEVENT` time they have *taken*. Each `AVAILABLE` subcomponent expands through the same recurrence path as an event, and `PRIORITY` resolves overlapping components, the winner deciding its whole period so that its silence means busy.

### Fixed

* Expanding a high-frequency recurrence (`FREQ=MINUTELY`, `FREQ=HOURLY`) is now linear rather than quadratic — adding a sub-day duration (`Tempo.Math.add/2` on hours, minutes or seconds) is O(1) instead of O(magnitude). A 1440-occurrence minutely rule materialises about 7× faster using roughly 13× less memory.

* A component stating `DURATION` instead of `DTEND` is now materialised rather than refused with "Duration-only VEVENT (no DTEND) is not yet supported". RFC 5545 allows either on a `VEVENT` and RFC 7953 allows either on `VAVAILABILITY` and `AVAILABLE`, so all three now accept both.

* An unanchored recurrence — `Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=MO")` with no `:from`, which carries `nil` endpoints rather than the ISO parser's `:undefined` — passed the member validation and crashed several frames into set algebra with `UndefinedFunctionError` or `FunctionClauseError`. Both sentinels now count as unbounded, so `intersection/2`, `union/2` and `difference/2` return `Tempo.IntervalEndpointsError` as they always did for `2020Y/..`.

* `Tempo.to_interval/2` returned `{:ok, recurrence}` for a recurrence with no start, reporting success while handing back the value that could not be materialised. It now returns `Tempo.IntervalEndpointsError` with `reason: :unanchored`, since no `:bound` can supply a missing anchor.

## [v1.2.0] — 2026-08-03

### Added

* `Tempo.compare/3` returns stdlib's ternary `:lt | :eq | :gt`, so `Tempo` can be passed as a sorter module anywhere `Date` or `DateTime` would be — `Enum.sort(values, Tempo)`, `Enum.sort_by(sessions, & &1.starts_at, Tempo)`, `Enum.min/2`, `Enum.max/2`. Consumers previously had to hand-roll a comparator around `Tempo.Compare.compare_endpoints/2`, and reaching for plain `Enum.sort/1` silently sorted by Erlang term order.

* `Tempo.compare/3` orders `t:Tempo.t/0` by start-moment, `t:Tempo.Duration.t/0` by length, and `t:Tempo.Interval.t/0` by start with ties broken by end. Comparing a calendar-dependent duration such as `P1M` requires `relative_to:`, since a month has no fixed length; without it the call raises rather than guessing.

* `Tempo.Compare` is now doctested — its documented examples had never been executed.

## [v1.1.1] — 2026-08-03

### Fixed

* Duration-first recurring intervals render again. `Tempo.from_iso8601("R3/P1D/2022-01-01")` parsed but `Tempo.to_iso8601/1` and `inspect/1` raised a `FunctionClauseError` on the result, so a value Tempo accepted could not be printed.

* An interval taking its extent from a duration now renders whether its end is absent or explicitly open. `%{interval | to: :undefined}` on a value like `R5/2022-01-01/P1M` previously raised instead of rendering.

* `Tempo.IntervalSet.new/2` returns `{:error, Tempo.ConversionError.t()}` for a member that is not a `Tempo.Interval`, rather than raising a `FunctionClauseError`. A function documented to answer with a tagged tuple must not crash on user input.

## [v1.1.0] — 2026-08-03

### Added

* `Tempo.explain/1` surfaces `±` uncertainty margins with a dedicated `:margin` part: `~o"2000±1Y"` now reports "Margin: ±1 year — groundings span [1999-01-01, 2002-01-01)." instead of reading like a precise value.

* `Tempo.intersection/3` takes a `:metadata` option deciding what an emitted fragment carries: `:left` (the default, unchanged), `:merge`, or `{:merge, fun}` for a caller-supplied resolver. Use the resolver form for provenance — a plain merge of `%{resource: "Alice"}` and `%{resource: "Bob"}` silently keeps only Bob.

* `Tempo.intersection/3`, `union/3`, and `difference/3` accept a **list** as the second operand, folded left-to-right: `Tempo.difference(workday, [standup, lunch])`. An empty list is the identity, so "subtract whatever is busy" needs no empty-case handling. Previously a list raised a `FunctionClauseError`.

### Fixed

* `Tempo.IntervalSet.slots/3` now carries each source member's metadata onto the slots cut from it. Previously every slot came back with `%{}`, so cutting a tagged free region into bookable slots lost the tag.

* Every public function in `Tempo.Operations` now carries an `### Examples` section, and the module's doctests run for the first time — it had no `doctest` declaration in the suite, so its documentation had never been executed.

## [v1.0.0] — 2026-08-01

The first stable release. Time as an interval, not an instant: one `%Tempo{}` type for every temporal value at every resolution, ISO 8601 Parts 1 and 2 plus IXDTF and RFC 5545 RRULE conformance, calendar- and territory-aware arithmetic, set algebra with Allen-relation comparison and three-valued certainty over uncertain values, and locale-aware formatting through Localize 1.0. See the [README](https://hexdocs.pm/ex_tempo/readme.html) for the full tour.

### Added

* `Tempo.shift/3` accepts `skipping:` — a busy set the shift jumps over, consuming the duration from free time only (`Tempo.shift(start, ~o"PT1H", skipping: meeting)`). Busy spans cost nothing to cross, an origin inside one first moves to its edge, and negative durations walk backward symmetrically.

* `Tempo.IntervalSet` storage is pluggable through the `Tempo.IntervalSet.Backend` behaviour (`new(intervals, backend: ...)`); the default list backend is unchanged and struct literals remain valid list-backed sets. `IntervalSet.walk/1`, `empty?/1`, and `first/1` are new accessors.

* `Tempo.IntervalSet.Backend.Tree` (`backend: :tree`) — an interval-tree backend for large, query-heavy sets of anchored members. Stabbing via `covered?/2` runs in O(log n + k); on 10k members it benchmarks ~2,900× faster than the list scan for ~9% extra construction cost.

* `Tempo.IntervalSet.Backend.Lazy` and `IntervalSet.from_stream/2` — unbounded lazy sets over an ordered generator. Walking (`walk/1`, `covered?/2`, `Enum.take/2`, `skipping:`) never materialises the set; aggregates raise the new `Tempo.UnboundedSetError` instead of hanging.

* `Tempo.weekends/1` — an unbounded lazy set of weekend days (territory-aware), usable directly as a `skipping:` busy set with no `:bound`: `Tempo.shift(start, ~o"P3D", skipping: Tempo.weekends(from: start))`.

### Changed

* **Breaking:** `Enum` over a *bounded* recurring interval now enumerates the sub-points of every occurrence (delegating to the materialised `IntervalSet`), instead of silently walking only the first occurrence. An *unbounded* recurrence raises `Tempo.UnboundedRecurrenceError` — materialise with `to_interval/2` and a `:bound` first.

* **Breaking:** `:bound` day-anchoring in set operations rejects non-time-of-day partials with a `Tempo.NonAnchoredError`. Previously `~o"15D"` with a `:bound` silently matched every day of the bound; express the recurring reading with a selection or RRULE instead.

* **Breaking:** the duration width option for `Tempo.to_string/2` is now `format: :long | :short | :narrow` (was `style:`), following Localize 1.0 and ECMA-402. Duration parts also now join with CLDR's unit list patterns (`"3 days, 2 hr"`, narrow `"3d 2h"`) instead of the prose conjunction (`"3 days and 2 hr"`).

* Dependency floors move to the stable releases: `localize ~> 1.0`, `calendrical ~> 1.0`, and `astro ~> 2.4` (the first astro without the tzdata/hackney chain). Interval formatting follows Localize 1.0's option naming (`fields:` selects which date fields render; `format:` remains the width).

### Fixed

* The certainty API (`relation_certainty/3`, `overlap_certainty/2`, `possibly_*`/`certainly_*`) reads a non-contiguous mask such as `~o"1985-XX-15"` as its finite candidate set, like a one-of set. Previously it raised a `FunctionClauseError`.


## [v0.21.0] — 2026-07-15

### Added

* `Tempo.nearest_working_day/2` — the closest working day to a date, territory-aware for which days are the weekend. Reproduces the observed-holiday rule: a Saturday rolls back to Friday, a Sunday forward to Monday.

* `Tempo.map/2` and `Tempo.try_map/2` — `Enum.map` analogues that collect mapped Tempo values into a `Tempo.IntervalSet`. `try_map/2` halts at the first value that cannot be materialised and returns its `{:error, reason}`.

* `Tempo.Interval` now carries an explicit iteration granularity on `:unit` (also settable via `Interval.new/1`) — a day-resolution interval with `unit: :hour` walks 24 hours while its bounds stay at day resolution.

* One-of sets feed the certainty API: `relation_certainty/3`, `overlap_certainty/2`, and the `possibly_*`/`certainly_*` predicates read `~o"[1984,1986]"` as a finite envelope (the union of possible relations over member choices). Previously they errored or silently answered `false`.

* `Tempo.at/2`, `at!/2`, and the date-phrased aliases `on/2` and `on!/2` — set finer components on a value already on the timeline (`Tempo.at(~o"2026-06-15", ~o"T17")`, `Tempo.on(~o"3M", ~o"2D")`), replacing the whole tail rather than merging it. Partial values are first-class, so a non-anchored subject is refined without forcing a year, and only anchored results are validated against the calendar.

* `Tempo.floating?/1` and `Tempo.grounded?/1` — predicates for whether a value sits on the universal (UTC) time line: floating values carry no zone or offset, grounded values carry an `[IANA/Zone]`, a `Z`, or a numeric offset.

* `Tempo.in_zone/2` — ground a floating value by placing its wall clock into an IANA zone (`Tempo.in_zone(~o"2030-03-01T08:00", "Europe/Paris")`). It is the counterpart to `shift_zone/2`, which *moves* an already-grounded value between zones.

### Changed

* **Breaking:** Tempo is now time zone database agnostic and no longer depends on `:tzdata` (whose `:hackney` dependency chain is gone from the tree). Add any `Calendar.TimeZoneDatabase` implementation (`:tz`, `:tzdata`, `:time_zone_info`, `:zoneinfo`) and configure it — `config :elixir, :time_zone_database, Tz.TimeZoneDatabase` — or set `config :ex_tempo, :time_zone_database, ...`; see `Tempo.TimeZoneDatabase`. Without one, parsing works fully but zone-rule operations error.

* **Breaking:** `Tempo.to_interval/1` bounds keep the value's own resolution instead of drilling into the next-finer unit — `to_interval(~o"2025-07-04")` is now `2025-07-04/2025-07-05` with `unit: :hour`, not `…T0H` bounds. Enumeration counts are unchanged (the walk fills to `:unit` at iteration time); code reading drilled components off materialised bounds must use the stated resolution.

* **Breaking:** the crisp and certainty boolean predicates (`before?/2`, `within?/2`, `certainly_overlaps?/2`, …) raise on an operand they cannot classify instead of silently returning `false` — a silent false asserted a relation verdict the error could not make.

* **Breaking:** `relation/2` and `duration/1` refuse a recurring interval (`R5/…`) with a directing `Tempo.MaterialisationError` — a recurrence is a rule generating occurrences, not a single span. Materialise with `to_interval/2` and use the set-level API; `duration/1` previously answered `:infinity` for a finite recurrence.

* **Breaking:** `Tempo.anchor/2` now takes the non-anchored value first and the reference second (`Tempo.anchor(~o"T10:30", ~o"2026-01-04")`) and raises when its subject is already anchored — it is strictly a left-fill that places a floating value on the timeline. Use the new `at/2` for the right-fill (setting a time-of-day on a date), which also fixes the previous behaviour of leaking the base's stray sub-units.

* **Breaking:** comparing a floating value with a grounded one now raises `Tempo.FloatingTempoError` — across `relation/2`, the Allen and set predicates, and the certainty API — rather than silently grounding the floating side to UTC. Ground the floating side first with `in_zone/2`.

* A trailing IXDTF zone on an interval *string* now propagates backward onto a floating lower endpoint, so `Tempo.from_iso8601("2030-03-01T08:00/2030-03-05T08:00[Europe/Paris]")` grounds both endpoints. Propagation is one-directional (`to` → `from`), never overwrites an existing zone, and does not affect `Tempo.Interval.new/2`.

* A critical IXDTF zone (`[!Europe/Paris]`) now enforces RFC 9557 §4.2 offset consistency: an offset that disagrees with the critical zone is rejected with `Tempo.ZoneOffsetMismatchError`. Criticality is retained on `extended.zone_critical` and round-trips through `to_iso8601/1`; `strict: true` still rejects elective disagreement too.

* The minimum `calendrical` dependency is now `~> 0.12`, whose `days_in_month/1` reports a month's maximum length across all years.

* `Tempo.Interval.new/1` applies the parser's frame-propagation rule: a grounded `:to` grounds a floating `:from` (never the reverse, never overwriting), so a constructed interval and the re-parse of its own ISO 8601 string agree.

* Comparison-operand errors are exception structs rather than raw strings, and `Tempo.Range`'s docs now state its actual role: the ISO 8601-2 set-member range element, not a top-level value.

### Fixed

* `Tempo.to_iso8601/1` on a cron nearest-weekday rule (`15W`) now raises a descriptive `Tempo.Iso8601EncodeError` instead of a `FunctionClauseError`, and `inspect/1` falls back to a labelled struct view rather than crashing.

* The falsehoods guide's "Where Tempo won't help (yet)" section no longer lists sub-second comparison and clock mocking as gaps — both work (`relation/2` at sub-second resolution; `Tempo.Clock`). The remaining sub-second gap is `duration/2`, which truncates to whole seconds.

* A yearless partial date that occurs in no year is now rejected — `~o"2M30D"` (February 30th) and `Tempo.new(month: 4, day: 31)` return an error, while genuine partials such as `~o"3M2D"` and the leap-year `~o"2M29D"` still succeed. Months whose length can't be bounded without a year (many lunisolar months) are left unchecked rather than falsely rejected.

* Two grounded values with the same wall clock but different numeric offsets (`2026-04-15T10:30+05:30` vs `+09:00`) now compare by their true UTC instants instead of testing equal — structural comparison was ignoring the offset.

## [v0.20.0] — 2026-07-10

### Added

* `Tempo.Interval.new/2` and `new!/2` — positional constructors for the common case, `Tempo.Interval.new(from, to)`, alongside the keyword `new/1` (which keeps the `:duration`, `:recurrence`, and open-ended forms).

* `Tempo.duration/2` and `duration!/2` — the duration between two endpoints, building the interval internally: `Tempo.duration(now, deadline)`. Measured on the UTC time line, so DST-spanning zoned endpoints yield the true elapsed duration.

* `Tempo.from_elixir/2` now accepts an Elixir `Duration`, and `Tempo.to_elixir/1` converts a `%Tempo.Duration{}` back to one (and a `%Tempo{}` to its best-fit calendar type) — closing the round-trip with the standard library's duration type.

* `Tempo.Duration.to_unit/3` and `to_unit!/3` — express a duration as a magnitude in a fixed-length unit (`Tempo.Duration.to_unit(dur, :hour)`). Month/year components are refused rather than approximated; pass `relative_to: a_date` to resolve them exactly against the calendar (DST-exact when the reference is zoned).

### Fixed

* `Tempo.Duration.new/1` with only a `:microsecond` component now keeps `second: 0`, so a sub-second-only duration renders through `Tempo.to_iso8601/1` (e.g. `~o"PT0.5S"`) instead of raising.

## [v0.19.2] — 2026-07-09

### Changed

* The optional `ical` dependency is now `~> 2.0 or ~> 3.0` (was `~> 2.0`). `Tempo.ICal` now maps RFC 5545 floating date-times (no `Z`, no `TZID`), which `ical` 3.0 surfaces as `NaiveDateTime`, to genuinely zone-less `%Tempo{}` values rather than anchoring them to a zone.

## [v0.19.1] — 2026-07-07

### Fixed

* Values that resolve to a pre-common-era Gregorian instant — e.g. `~o"2022-06-15T10:00[Europe/Paris][u-ca=hebrew]"`, whose units read as Hebrew year 2022 ≈ 1739 BCE — no longer crash parsing, comparison, or zone projection on OTP 27/28. UTC projection now uses OTP-version-independent proleptic conversion, and tzdata lookups are skipped for pre-CE instants (local-mean-time era, zero offset).

## [v0.19.0] — 2026-07-07

### Added

* `Tempo.IntervalSet.duration/1` — the total covered duration of a set, the sum of every member's UTC-measured length. `Tempo.duration/1` now accepts an `IntervalSet` as well as an `Interval`.

* `Tempo.select/2` now accepts a `Tempo.Set` base (e.g. a `~o"{2026-01-05/2026-01-12,…}"` set-of-intervals sigil), materialising it and applying the selector to every member.

### Fixed

* Set operations between a week-axis value and a month/day-axis value (e.g. `Tempo.intersection(~o"2026Y1W", ~o"2026-01-03")`) no longer raise `FunctionClauseError` — `align/3` canonicalises week-axis endpoints to month-axis calendar dates before the sweep. `Tempo.select/2` with a day-of-week selector over a week-axis base (e.g. `Tempo.select(~o"2026Y{1..13}W", Tempo.weekend(:US))`) now returns the matching days instead of a silently empty set.

* Set operations mixing a sub-second operand with a second-or-coarser operand — e.g. an interval built with `Tempo.from_elixir/1` from a `DateTime` carrying microseconds, intersected with a minute-resolution window — no longer fail; `Tempo.extend_resolution/2` now extends a whole second to `:microsecond` by filling with zero microseconds at full precision.

* Cross-calendar set operations now keep each converted endpoint's IXDTF `u-ca` tag in step with its converted units — dropped for a Gregorian target, set to the target's CLDR calendar type otherwise — so `to_iso8601/1` output re-parses to the same instants. `Tempo.from_iso8601/1` now also honours per-endpoint `u-ca` suffixes on interval endpoints (an explicit `:calendar` argument still wins).

## [v0.18.1] — 2026-07-07

### Fixed

* `Tempo.members_outside/3` and `Tempo.members_overlapping/3` now scan the two member lists with an `O(n + m)` merge-sweep instead of comparing every pair — the Business/252 cookbook recipe (262 workdays against 1,264 ANBIMA holidays) drops from ~675 ms to ~2 ms. `Tempo.members_in_exactly_one/3` inherits the same speedup.

## [v0.18.0] — 2026-07-07

### Changed

* `Inspect` for `Tempo.IntervalSet` now honours the `Inspect.Opts` `:limit` — it renders up to that many member intervals (default `50`) followed by the current locale's ellipsis via `Localize.ellipsis/1`, rather than collapsing any set over three members to a bare `N intervals` count.

## [v0.17.1] — 2026-07-06

### Changed

* The minimum Erlang/OTP is now **27**; OTP 26 is no longer supported, because the tokenizer's optimiser-disabled compilation (introduced in 0.17.0 to halve build time) trips an OTP-26 code-generation bug that miscompiles the parser and crashes at runtime. `mix.exs` now raises a clear "requires OTP 27 or later" error on older OTP instead of letting the miscompile surface as a cryptic multi-terabyte-allocation crash.

## [v0.17.0] — 2026-07-06

### Changed

* Clean-build and CI compile time is roughly halved (~118 s → ~51 s for `mix compile --force` on the reference machine): the Erlang optimiser is turned off for the ISO 8601 tokenizer — whose parser is not a runtime hot path — and its ~40 NimbleParsec parsers are split across `Tokenizer.Date` / `.Time` / `.Set` modules that compile in parallel. Parsing is byte-identical; there is no public API or behaviour change.

## [v0.16.2] — 2026-07-05

### Fixed

* Materialising a large recurrence is now linear rather than quadratic in the occurrence count: `Tempo.to_interval/2` on a schedule like `~o"R10000/2020-01-01/P1D"` completes in ~20 ms instead of ~6 s. Day arithmetic on a concrete date now uses absolute-day conversion (`O(1)`) instead of stepping one day at a time.

* The ISO 8601 / IXDTF parser is hardened against adversarial input: input longer than 8 KB, or set/group bracket nesting (`{…}` / `[…]`) deeper than six levels, is now rejected up front with a `Tempo.ParseError`. Previously a deeply-nested or unbalanced string (e.g. `"{"` × 40) drove the parser into exponential backtracking; every legitimate value is well within both limits.

## [v0.16.1] — 2026-07-05

### Fixed

* A bare `%Tempo{}` built as a struct literal — carrying the default `calendar: nil` rather than the resolved calendar the parser and `Tempo.new/1` produce — no longer crashes comparison, materialisation, or network placement; the `nil` is resolved to the default Gregorian calendar at each boundary. `Tempo.relation(%Tempo{time: [year: 2026]}, ~o"2026")` is now `:equals` instead of raising `nil.calendar_base/0`.

## [v0.16.0] — 2026-07-04

### Added

* `Tempo.Network.Solver.relation/3` returns the tightest Allen relation(s) still possible between two periods in a constraint network — a single atom when the constraints entail one (`:precedes`), or the smallest disjunction otherwise — generalising `contemporaneity/3` from overlap to the full thirteen-relation vocabulary. `relation_certainty/4` reports whether a named relation is `:certain`, `:possible`, or `:impossible`, and both read off the already-solved network in polynomial time.

* `Tempo.compose/2` composes two Allen relations — given `A r1 B` and `B r2 C` it returns every relation possible from `A` to `C` (Allen's 1983 composition table), as a constant-time lookup that chains one qualitative inference with no interval in hand. `Tempo.compose(:precedes, :during)` is `[:precedes, :meets, :overlaps, :starts, :during]`.

* The three-valued certainty queries — `within_certainty/2`, `relation_certainty/3`, `overlap_certainty/2`, and the `certainly_*?`/`possibly_*?` predicates — now reason over *underspecified* operands: an unspecified-digit value like `~o"20XXY"` (some year in 2000–2099) is read across every year its mask admits, and two un-anchored values compare on a shared leading unit or return a `Tempo.RequiresAnchorError` across resolution axes. `within_certainty(~o"20XXY", ~o"2001Y/2101Y")` is `:possible` because the year 2000 falls outside the window.

* A [Custom calendars](guides/custom-calendars.md) guide (and a cookbook recipe) shows how a fiscal-year, 4-4-5 retail, or academic-year calendar built with `Calendrical.new/3` flows end-to-end through Tempo — iterated by its own periods and compared cross-calendar — realising the time-granularity framing as calendar arithmetic.

### Fixed

* Comparison, duration, and everything built on them — cross-calendar Allen relations, the `Tempo.Network` constraint solver, and interval-set coalescing — are now calendar-independent. A value in a non-Gregorian calendar (`[u-ca=hebrew]`, `[u-ca=persian]`, …) is projected through its calendar's date→absolute-day conversion, so `Tempo.relation(~o"2025-09-23", ~o"5786-01-01[u-ca=hebrew]")` is `:equals`, a Hebrew common year measures 354 days rather than a Gregorian 365, and the Gregorian path is unchanged.

* The IXDTF `u` calendar tag is parsed and generated through Localize's BCP 47 Unicode-extension parser (`localize ~> 0.44`): Tempo reads both the IXDTF `[u-ca=hebrew]` and the BCP 47 `[u-ca-hebrew]` separators — folding registered aliases such as `islamicc` → `islamic-civil` — and emits the canonical IXDTF `=` form with the preferred identifier (`:gregorian` → `gregory`). Calendar values are the Unicode Calendar Identifiers of UTS #35 (`ethioaa`), not CLDR's internal type names (`ethiopic-amete-alem`).

* The `~o` sigil now honours an in-string `[u-ca=NAME]` calendar, so `~o"5786-01-01[u-ca=hebrew]"` is a Hebrew date rather than a silently-Gregorian year 5786 and compares correctly against Gregorian values. A `w` modifier still selects the ISO Week calendar and a plain sigil is still Gregorian.

* A date in a month that doesn't exist in its calendar year — such as the Hebrew Adar I (month 6) in an ordinary year — now returns a clear `"month 6 does not exist in …"` error instead of a confusing empty-range message.

* A date in an astronomical calendar (e.g. Persian) far outside the ephemeris range no longer crashes; the `astro` dependency is bumped to `~> 2.3` (2.3.2), which returns a clean result for such dates rather than raising.

## [v0.15.1] — 2026-07-03

### Fixed

* An IXDTF numeric UTC offset (`[+08:45]`, `[-03:30]`) is now rendered by `inspect/1` and `Tempo.to_iso8601/1`, so a parsed value carrying one round-trips instead of silently dropping the offset.

* An unanchored recurrence — a cron schedule or RRULE with no start, e.g. `Tempo.Cron.parse!("0 17 * * 5")` — now round-trips through its ISO 8601 form: the parser accepts the open-start `R/../P1W/…` shape, and a weekday-plus-time selection serialises the weekday before the time (`FL5KT17H0MN`) so it re-parses to the same value.

* `inspect/1` and `Tempo.to_iso8601/1` no longer crash on a recurrence carrying RRULE `BYSETPOS` or `WKST`; these RFC 5545 filters have no ISO 8601 form, so Tempo renders them with the project-specific selection designators `V` and `Q` (conformance guide §5) and they round-trip. `BYYEARDAY` now round-trips via the `O` ordinal-day designator, and consecutive `BY…` runs (weekdays, months) consolidate to ranges (`{1..5}`) that round-trip while staying readable — while a list mixing a positive value with a negative sentinel (`BYMONTHDAY=1,-1`, "the first and last day") keeps its source order so it round-trips too.

* `Tempo.shift/2` on an un-anchored value (no year, such as `~o"1M31D"`) no longer crashes and now resolves every case the calendar can answer without a year: a whole-year step is a no-op, a month step wraps December to January, a bare day advances while every month has it, and weeks/months extend a coarser value's resolution. Only genuinely year-dependent shifts (a February day count, `~o"2M29D"` plus a year) return `{:error, %Tempo.RequiresAnchorError{}}`.

* Set operations (`Tempo.union/2`, `intersection/2`, `difference/2`) between two un-anchored values on different resolution axes — a month/day like `~o"1M31D"` and a bare day like `~o"15D"`, which recur on different cycles — now return `{:error, %Tempo.NonAnchoredError{}}` instead of silently computing a misaligned result; same-axis pairs still compute.

## [v0.15.0] — 2026-07-02

### Added

* A Claude Code **skill** — shipped as a GitHub plugin — that maps a natural-language date/time problem to validated, runnable Tempo (`~o"…"` syntax, the right layer, checked with `Tempo.explain/1`), plus a *Using Tempo with an AI assistant* guide. Install with `/plugin marketplace add kipcole9/tempo` then `/plugin install tempo@tempo-plugins`.

* `Tempo.Network.Solver.contemporaneity/3` (with `certainly_contemporary?/3` and `possibly_contemporary?/3`) reports whether two periods in a constraint network are `:certain`, `:possible`, or `:impossible` to overlap. It reads the verdict in constant time from the tightened network's shortest-path weights, following Geeraerts, Levy & Pluquet (*Models and Algorithms for Chronology*, TIME 2017), Props 7 and 10.

### Changed

* `Tempo.Cron.parse/2` and `parse!/2` now return a recurring `%Tempo.Interval{}` — the same first-class value `Tempo.RRule.parse/2` produces — instead of an internal `%Tempo.RRule.Rule{}`. A parsed cron schedule now materialises directly with `Tempo.to_interval/2` (no `Expander` step) and accepts a `:from` anchor; the raw field mapping stays available internally.

### Fixed

* Recurrence occurrences now span their selection's own resolution — "the 15th of every month" (`FREQ=MONTHLY;BYMONTHDAY=15`, `~o"R/2025-01-15/P1M/FL15DN"`, or cron `0 0 15 * *`) materialises as the *day* the 15th, not the month-long cadence it sits in. Native ISO 8601-2, RRULE, and cron now agree on occurrence spans, while a plain repeating interval still spans its cadence.

* `Tempo.shift/2` no longer raises on un-anchored values (those with no year, such as `~o"1M31D"`): it computes the answer where the calendar can (`~o"1M31D"` shifted by `P1D` is `~o"2M1D"`, since January always has 31 days) and returns `{:error, %Tempo.RequiresAnchorError{}}` where the result would depend on the missing year. Requires `calendrical ~> 0.10`.

* `Tempo.from_iso8601/2` returns `{:error, %Tempo.InvalidCalendarError{}}` for a module that is not a usable calendar — such as the `Calendrical.Islamic` namespace, whose concrete forms are `Calendrical.Islamic.Civil`, `.UmmAlQura`, and so on — instead of crashing with `UndefinedFunctionError`.

* A recurrence selection written with an index range — e.g. `~o"R/2024-11-01/P1Y/FL11M{2..8}D2KN"` (US Election Day: the Tuesday on the 2nd–8th of November) — now materialises correctly instead of raising, so an inspected recurrence round-trips through the `~o` sigil. Range and explicit-list selections (`{2..8}` and `{2,3,4,5,6,7,8}`) are equivalent.

* An ordinal `BYDAY` recurrence — "the 2nd Monday of the month" (`FREQ=MONTHLY;BYDAY=2MO`), including multi-weekday (`2MO,WE`) and negative-ordinal (`-1FR`, the last Friday) forms — now round-trips through its native ISO 8601-2 selection form: the parser folds the inspected `2I1K` instance-and-weekday notation back into the `:byday` selection, so re-parsing yields the identical value instead of one that selected *every* Monday.

* `Tempo.explain/1` describes recurring intervals in plain English — the recurrence, its cadence, and its BY-rule selection rendered as prose (e.g. "in November, on the 2nd–8th, on a Tuesday") — instead of "a `Tempo.Interval` with an unusual shape".

## [v0.14.0] — 2026-07-02

### Added

* Graded before/after predicates — `Tempo.certainly_before?/2`, `possibly_before?/2`, `certainly_after?/2`, and `possibly_after?/2` answer the disjoint-order question three-valued (`:certain | :possible | :impossible`) over `±` margin-of-error intervals, alongside the existing overlap/within certainty functions.

### Changed

* The graded relations now compute the *exact* set of possible Allen relations — enumerating each operand's discrete `±` placements rather than treating endpoints independently — so verdicts are tighter (e.g. `relation_certainty(~o"2000±5Y", ~o"2000±5Y", [...year relations])` is now `:certain`). Margins beyond ±128 units per operand fall back to the previous sound O(1) endpoint-range method.

* Enumerating a masked value now yields its candidates in ascending order — `~o"2020-06-XX"` gives the 1st … 30th, consistent with year masks and materialisation (month/day masks previously enumerated descending). Mask candidate generation is now shared between the enumeration and materialisation paths through a single resolver, so they can no longer diverge.

### Removed

* The web visualizer — `Tempo.Visualizer` and its `Standalone` Bandit server — is removed, along with the optional `:plug` and `:bandit` dependencies. Interactive exploration is moving to an LLM-based approach that better fits Tempo's scope.

## [v0.13.0] — 2026-07-02

### Fixed

* `Tempo.shift/2`, `Tempo.Math.add/2` and `subtract/2` now support unspecified-digit masks instead of crashing, including masks spanning several components (`195X`, `2020-XX`, `19XX-XX`, `199X-06-XX`). A shift moves the value's block: a block-aligned single-year shift stays a mask (`195X` + `P10Y` → `196X`), a contiguous shift returns a one-of set (`195X` + `P1Y` → `~o"[1951Y..1960Y]"`), and a mask with a concrete component after it — which denotes *disjoint* spans — returns a coalesced IntervalSet (`199X-06-XX` + `P1Y` → the ten Junes of 1991–2000).

* Fixed several long-standing mask bugs surfaced by the above: enumerating a month/day mask dropped single-digit values (`2020-06-XX` skipped days 1–9), `Enum.count/1` on a masked value returned the block count rather than the candidate count, and materialising a non-contiguous mask (`199X-06-XX`) raised instead of expanding to its disjoint intervals.

## [v0.12.0] — 2026-07-02

### Added

* Graded relations over `±` margin-of-error intervals: `Tempo.overlap_certainty/2`, `within_certainty/2`, and modal predicate pairs (`certainly_overlaps?/2`, `possibly_overlaps?/2`, …) answer Allen-relation queries three-valued (`:certain | :possible | :impossible`). Crisp intervals degrade exactly to the existing boolean predicates.

### Fixed

* `Tempo.shift/2` and `Tempo.Math.add/2` / `subtract/2` no longer crash on margin-of-error (`±`) or significant-digits (`S`) values; the annotation now rides along with the shifted component (`Tempo.shift(~o"2018±2Y", ~o"P1Y") == ~o"2019±2Y"`), completing the crisp-inert treatment begun in 0.11.1.

## [v0.11.1] — 2026-07-01

### Fixed

* A margin-of-error value (`~o"2018±2Y"`) crashed `Tempo.relation/2`, `Tempo.to_interval/2`, and endpoint comparison with an `ArithmeticError`. The `±` annotation is now crisp-inert — dropped for materialisation and comparison, preserved on the value — so a `±`-bearing value behaves identically to its crisp core (margin-aware graded relations are a future step).

* A significant-digits value (`~o"1950S3"`) crashed `Tempo.to_interval/2` and `Tempo.relation/2` with an `ArithmeticError`. It now materialises to the block of values sharing its leading digits — `1950S3` spans `~o"1950Y/1960Y"`, identical to the equivalent mask `195X` — and the `S` annotation is preserved on the value.

## [v0.11.0] — 2026-07-01

### Changed

* Recurrences are now constructed and documented as first-class interval values rather than the internal RRULE AST builder. A simple periodic recurrence is `Tempo.Interval.new!(from: dtstart, duration: ~o"P1W", recurrence: :infinity)` (or the `~o"R/…/P1W"` literal), and a calendar rule is `Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=2MO", from: …)`, which returns a recurring `%Tempo.Interval{}`; both materialise with `Tempo.to_interval(value, bound: …)`.

### Fixed

* `Tempo.Interval.new/1` returned an un-inspectable, non-canonical `to: :undefined` for any interval built from a `:duration`. It now derives the endpoint as `to: nil`, so duration and recurring intervals inspect and round-trip as `~o"2020Y/P1D"` and `~o"R/…/P1W"`; open-ended intervals (no `:duration`) are unchanged.

* Inspecting a recurring interval whose `BYDAY` filter carries an ordinal (`FREQ=MONTHLY;BYDAY=2MO`, `-1FR`, `1MO,3MO`) raised a `FunctionClauseError`. The `:byday` selection now renders in the instance/day-of-week notation (`~o"R/2025Y1M1D/P1M/FL2I1KN"`).

## [v0.10.2] — 2026-06-30

### Added

* Component-level "one of a set" (ISO 8601-2 / EDTF): `~o"[1,2,3]M"` is the one-of counterpart of the all-of `~o"{1,2,3}M"`, distributing across the value to a one-of `Tempo.Set` (`2020Y[1,2]M` → one of `2020Y1M`, `2020Y2M`); ranges expand and multiple one-of components form the cartesian product.

* One-of sets work in interval endpoints too: `2020Y[1,2]M/2021Y` distributes to a one-of set of intervals, and an explicit one-of set of intervals (`~o"[2020Y/2021Y,2022Y/2023Y]"`) now builds its interval members correctly.

### Fixed

* Rounding a time of day to the hour or minute always rounded up — `Tempo.round(~o"T10H10M", :hour)` returned `~o"T11H"` instead of `~o"T10H"`. It now rounds to nearest (≤ half down, > half up).

## [v0.10.1] — 2026-06-30

### Fixes

* Links to guides in README.md

## [v0.10.0] — 2026-06-30

### Added

* `Tempo.Network` — a chronological-network constraint layer implementing the ChronoLog scheme (Levy et al. 2020) over Tempo's intervals: time-periods with independent start/end/duration bounds, sequences, and the ChronoLog relation vocabulary, normalised to a Simple Temporal Problem and solved by Floyd–Warshall (`consistent?/1`, `tighten/1`, and explanatory `trace/3`). Reproduces the paper's ChronoLand and 26th-dynasty results exactly.

* `Tempo.Network.Relation` covers ChronoLog's full boundary lattice: the precise Allen relations (`:starts`, `:started_by`, `:finishes`, `:finished_by`), `:strictly_contemporary`, and a parameterised `{:boundary, edge, comparison, edge}` for the start/end before/after/at relations. Validated by decoding and re-solving ChronoLog's published case studies (Egyptian 26th dynasty, RDC-2022 Near-Eastern models, Mediterranean LBA).

* `Tempo.shift/2` now accepts a `Tempo.Duration` directly (`Tempo.shift(~o"2026", ~o"P2Y")`), in addition to the keyword-list form; both delegate to `Tempo.Math.add/2`.

* `Tempo.weekend?/2` and `Tempo.workday?/2` classify a day against a territory's weekend (`weekend?(~o"2026-06-12", :SA)` is `true`, `:US` is `false`). Weekend days come from CLDR via `Localize.Calendar.weekend/1`; the day of week from `Date.day_of_week/1`, computed in the value's own calendar so non-Gregorian values are correct.

* Business-day arithmetic: `Tempo.add_working_days/3` (forward or backward, skipping the territory's weekend), `Tempo.next_working_day/2`, `Tempo.previous_working_day/2`, and `Tempo.working_days_in/2`.

* IXDTF offset/zone consistency (RFC 9557 §4.2): `Tempo.validate_zone_offset/1` flags a numeric offset that disagrees with its IANA zone, and `Tempo.from_iso8601/2` accepts `strict: true` to reject such a value at parse time. A DST fall-back offset is treated as disambiguation, not disagreement.

* `Tempo.IntervalSet.slots/3` cuts a free-time region into discrete fixed-length bookable slots (`slots(mutual_free, ~o"PT1H")`), with an `:every` spacing option. Complements the set operations: where `difference`/`intersection` give the free regions, `slots/3` discretises them into bookable windows.

* `Tempo.Schedule` — constraint-based project scheduling (critical path method) over `Tempo.Network`: declare tasks with durations and finish-to-start dependencies, anchors and deadlines, then `solve/1` for each task's early/late position and `critical?` flag, plus `critical_path/1` and `span/1`. An over-tight deadline or dependency cycle is reported infeasible.

### Changed

* A pure time-of-day group now materialises to a non-anchored interval (`[hour: 16, minute: {:group, 1..15}]` → `[16:01, 16:16)`) instead of erroring, when its upper bound stays within the day. Date groups and end-of-day carries still require anchoring.

* `Tempo.Network` now derives its axis unit from duration bounds as well as dates, so a purely relative network of day-length periods measures in days rather than collapsing onto the default year axis.

### Fixed

* iCal import no longer produces zero-extent intervals. A punctual event (RFC 5545 §3.6.1 zero-duration, or an explicit `DTEND == DTSTART`) now materialises as the one-unit implicit span of its start, tagged `metadata: %{punctual: true}`, upholding the domain's no-degenerate-interval invariant through set operations.

## [v0.9.0] — 2026-06-29

### Added

* `Tempo.to_date_time/1` — convert a zoned Tempo back into a `DateTime`, preserving the named time zone and re-deriving the UTC offset from the time-zone database (the lossless inverse of `from_elixir/2` on a `DateTime`). DST fall-back ambiguity is resolved using the value's stored offset, and a spring-forward gap returns an error.

* `Enumerable` `count/1`, `member?/2`, and `slice/1` are now implemented for `%Tempo{}`, delegating to the materialised interval's O(1) `Tempo.Interval.Steps` paths instead of an O(n) walk. They are DST-aware (a spring-forward day counts 23 hours, a fall-back day 25); group, range, and selection values fall back to the reduce walk.

* ISO 8601-2 expanded years — a sign-prefixed year of five or more digits (`+12022`, `-12022`, `+002022`, `+12022-06-15`). The mandatory sign distinguishes the expanded form from a basic-format date, and a signed four-digit value (`+2006`) is rejected as it is neither basic nor expanded.

* Multi-year cron fields — a 7-field cron carrying a year list or range (`0 0 0 1 1 * 2025,2027,2029`) now expands to occurrences in exactly those years, via a new non-standard `:byyear` field on `Tempo.RRule.Rule`. Previously only a single concrete year was honoured and multi-year lists were silently dropped.

* Cron `W` (nearest-weekday) day-of-month — `15W` and `LW` now resolve to the nearest weekday within the month (Saturday → Friday, Sunday → Monday, never crossing a month boundary), via a new non-standard `:bymonthday_nearest` field on `Tempo.RRule.Rule`. Previously `W` returned an `:unsupported_w` error.

* Cron POSIX day-of-month OR day-of-week — when both fields are restricted (`13 * 5` — "the 13th or any Friday"), occurrences are now the union of the two, via a new non-standard `:bymonthday_or_byday` field on `Tempo.RRule.Rule`. A Quartz extension (ordinal `5#2`, or nearest-weekday `15W`) opts out and keeps the AND-composing interpretation.

* ISO 8601-2 §8 component qualification is now spec-conformant and round-trips. On parse, a qualifier at the rightmost end is *complete* (`2004-06-11%` → the whole value), to the right of a component is *group* (`2004-06~-11` → the month and the year), to the left is *individual* (`2004-?06-11` → the month only), and the explicit designator form (`2004~Y6?M11D`, including a qualified BC year `2004~YB`) parses too. `inspect/1` and `to_iso8601/1` render the per-component qualifications back in explicit form — a parsed group re-encodes as the equivalent `2004~Y6~M11D` — and, per §8.2.4, collapse a uniformly-qualified value to the compact complete form (`2004%Y6%M11%D` → `2004Y6M11D%`).

### Changed

* `Tempo.from_elixir/2` now infers resolution for `Time`, `NaiveDateTime`, and `DateTime` from the type's declared precision (`:second`, or `:microsecond`) rather than the magnitude of the components, so `~U[2022-07-04 09:00:00Z]` is a fully specified second (not an hour) and round-trips losslessly through `to_naive_date_time/1`. Pass an explicit `:resolution` to force a coarser span (e.g. `resolution: :day` for a midnight value).

### Bug Fixes

* Cron day-of-week steps now expand in cron numbering (Sunday = 0) before mapping to RFC, so `0/3` yields Wed, Sat, Sun (previously collapsed to Sunday alone) and `*/2` yields Tue, Thu, Sat, Sun. A Sunday-spanning range step LHS such as `0-3` no longer builds a descending range.

* `Enumerable.Tempo.Interval.reduce/3` is now DST-aware, so an interval's `Enum.to_list/1` agrees with its `Enum.count/1`: a spring-forward day walks 23 hours and a fall-back day 25 (the folded hour emitted twice with its two offsets), matching the `Tempo.Interval.Steps` fast paths and the implicit `%Tempo{}` walk. The classification now lives in a shared `Tempo.Enumeration.Zone`.

* `Tempo.Interval.Steps.nth_step/4` now disambiguates a DST fall-back's duplicated hour, assigning each occurrence its own offset. This makes the O(1) `slice/1` fast path exact across a DST transition, so `Enum.at/2` and `Enum.slice/2` agree with the walk for zoned values too (they previously deferred to the O(n) reduce walk).

* Implicit enumeration of a `%Tempo{}` now resolves its range against the value's own calendar instead of defaulting to Gregorian, for both the `Enum` walk and the `count`/`member?`/`slice` fast paths. A Coptic/Ethiopic year (or a Hebrew leap year) now enumerates 13 months, and a 30-day Coptic month enumerates 30 days rather than a non-existent Gregorian-style 31.

* `Tempo.from_iso8601/1` now rejects genuinely inverted intervals such as `2026/2025` with a `Tempo.IntervalEndpointsError`. The check is narrow — it compares against the end's exclusive upper bound, so EDTF reduced-precision (`1111-01-01/1111`), masked, and non-anchored midnight-crossing (`T22/T02`) intervals stay valid.

* The ISO 8601-2 parser no longer raises `KeyError` when a selection is adjacent to a group; such pairs now validate resolution ordering from each wrapper's units, yielding a clean parse or a clean `Tempo.ParseError`. A copy-paste bug that disabled cross-group ordering validation is also fixed.

* `Tempo.Compare.to_utc_seconds/1` now resolves ISO week dates (`2022-W24`) and ordinal dates (`2022-166`) to their real calendar date before projecting. Previously they collapsed to January 1, so every week interval reported a zero-second duration and adjacent weeks compared `:equals` instead of `:meets`.

* `Tempo.to_interval/1` now materialises group values — centuries (`20C`), decades (`201J`), and unit groups (`2018Y1G6MU`) — to the single contiguous span they denote (`20C` → `[2000, 2100)`). Year groups previously raised an `ArithmeticError`, other unit groups widened to the wrong bounds, and a non-anchored group (`5G10DU`) now returns a clean `:unanchored_group` error instead of crashing.

* `Tempo.to_interval/1` now materialises second-resolution values to a one-second span `[t, t+1s)` instead of returning `{:error, :finest_resolution}`. Since sub-second resolution landed, a second is no longer the finest unit, so the common case of a plain `DateTime`/`NaiveDateTime` (which infers to second resolution) can now become an interval and participate in set operations.

* `Tempo.to_naive_date_time/1` and `Tempo.to_time/1` no longer error on zoned values; they drop the offset and return the wall-clock reading (matching `to_date/1` and the stdlib `DateTime.to_naive/1`), not shifted to UTC. Use `to_date_time/1` to keep the zone, or `shift_zone(tempo, "Etc/UTC")` to normalise to UTC wall time first.

## [v0.8.0] — 2026-06-27

### Bug Fixes

* `Tempo.ICal.from_ical/2` now follows RFC 5545 §3.6.1 for events with no `DTEND`/`DURATION`: a `DATE`-valued `DTSTART` spans exactly one day and a `DATE-TIME` `DTSTART` becomes a zero-duration point (`to == from`) rather than being widened by one resolution unit. The all-day end boundary also stays at day resolution instead of drifting to an hour-resolution midnight.

## [v0.7.0] — 2026-05-28

### Added

* Sub-second (fractional-second) resolution via a `:microsecond {value, precision}` component matching Elixir's `Time`/`DateTime` shape (precision capped at 6 digits). Parsing, materialisation (`[v, v+1ulp)`), Allen comparison, durations (`PT0.5S`) and arithmetic, ISO 8601 / inspect round-trip, `from_elixir`/`to_naive_date_time`, and explicit-interval enumeration are all sub-second aware. Trailing zeros are significant — `.120` (millisecond) and `.12` (centisecond) are distinct resolutions.

* `Tempo.Interval.equivalent?/2` — temporal-extent equality that ignores metadata, calendar, and zone-display labels by projecting endpoints to UTC and comparing only the temporal positions. Matches the equivalence notion of Grüninger and Li's `T_bounded_meeting` ontology (TIME 2017).

* Property tests verifying Allen's interval-algebra axioms and the Sum Axiom of `T_bounded_meeting`. Checks joint exhaustiveness, self-equality, inverse consistency, `meets` asymmetry, and predicate-relation consistency across 1000+ randomly generated interval pairs per property.

### Changed

* Fractional-second input is now preserved rather than truncated. `~o"...45.123"`, `PT1.250S`, and `Tempo.from_elixir(datetime_with_microseconds)` previously dropped the sub-second part; they now retain it as a `:microsecond` component. `Tempo.utc_now/0` and `now/1` remain second-resolution by contract (use `from_elixir(DateTime.utc_now())` for a sub-second reading).

* `Tempo.Interval.new/1` now rejects empty intervals (`from == to`) with `Tempo.IntervalEndpointsError`. Internal set operations already filtered these out; this change closes the public-API hole and matches the ontology's exclusion of degenerate intervals from the domain.

* `Tempo.Operations` set-producing functions (`union/3`, `intersection/3`, `difference/3`, `complement/2`, `symmetric_difference/3`, `members_overlapping/3`, `members_outside/3`, `members_in_exactly_one/3`) now have proper `@spec` operand types (`Tempo.t() | Tempo.Interval.t() | Tempo.IntervalSet.t() | Tempo.Set.t()`) instead of `any()`. Brings them into line with the predicate functions and the `align/3` contract.

* `Tempo.Interval` `@moduledoc` documents the discrete-style interval boundary semantics (exclusive upper bound, `meets` at the seam) against the continuous underlying time line. Clarifies that Tempo's half-open convention matches Rust's `allen-intervals` discrete-domain choice and Hayes' open-interval model cited by Grüninger and Li.

## [v0.6.0] — 2026-05-23

### Added

* `Tempo.parse/2` and `Tempo.parse!/2`. Parse a locale-formatted date, time, datetime, or interval string into a `Tempo` (or `Tempo.Interval` for ranges) by delegating to `Calendrical.parse/2`. Forwards `:locale`, `:calendar`, and `:reference_date` to Calendrical and normalises the resulting field map for `Tempo.new/1`.

* `Tempo.new/1` and `Tempo.new!/1` now also accept a map. `Calendar.ISO` is silently normalised to `Calendrical.Gregorian`, so an Elixir `Date`, `Time`, or `NaiveDateTime` can be passed via `Map.from_struct/1` directly.

## [v0.5.0] — 2026-04-28

### Breaking — set operations now match textbook semantics

The named set operations now behave the way the symbols in `A ∩ B`, `A ∖ B`, and `A △ B` read in a textbook: each returns the *trimmed instant-level result* (covered time). Member-preserving filters — the "give me the whole events that survive" form — moved to explicitly named `members_*` companions. `union/2` is unchanged (the only member-preserving default — coalesce explicitly with `IntervalSet.coalesce/1` for the merged-span form).

* `Tempo.intersection/2` now returns the trimmed overlap. Previous member-preserving form is `Tempo.members_overlapping/2`. Previous `Tempo.overlap_trim/2` is removed — `intersection/2` does its job.

* `Tempo.difference/2` now returns the trimmed remainder (`A` with `B`-shaped holes punched out — possibly splitting an `A` member into multiple fragments). Previous member-preserving form is `Tempo.members_outside/2`. Previous `Tempo.split_difference/2` is removed — `difference/2` does its job.

* `Tempo.symmetric_difference/2` now returns the trimmed non-shared edges of both operands. Previous member-preserving form is `Tempo.members_in_exactly_one/2`.

Migration:

* "What's the overlap?" / "What time is in both?" → `intersection/2` (no change in name; behaviour now trimmed).
* "Which of these meetings hit the query window?" → `members_overlapping/2` (was `intersection/2`).
* "Workday minus lunch as free-time blocks" / "Free time around busy" → `difference/2` (no change in name; behaviour now trimmed). This fixes the previously broken `Tempo.difference(workday, lunch)` pattern, which used to drop the whole workday.
* "Which workdays aren't holidays?" → `members_outside/2` (was `difference/2`). The numeric result is the same when each `A` member is either fully covered or fully outside any `B` member (workdays/holidays case), but `members_outside` is the right name for an event-list question.
* Callers of `Tempo.overlap_trim/2` → `Tempo.intersection/2`.
* Callers of `Tempo.split_difference/2` → `Tempo.difference/2`.

The motivation: when a user reads `Tempo.intersection(japan_trip, enrolled)` or `Tempo.difference(workday, lunch)` aloud, they're describing a covered-time question. The library should return that, not surprise them by collapsing whole members. The member-preserving forms remain available — and clearly named — for the event-list questions where they're the right shape.

### Bug Fixes

* `Tempo.difference/2` (formerly `split_difference/2`) no longer emits a zero-width residue interval when an `A` member is fully consumed by a `B` member and additional `B` members remain. Surfaced when applying the new instant-level `difference` to multi-day workday/holiday set operations; previously masked because the trimmed form was rarely composed against multi-member B sets.

### Changes

* Removed `Tempo.Sigil` shim (was renamed to `Tempo.Sigils`)

## [v4.1.0] — 2026-04-25

### Bug Fixes

* Update `ex_doc` dependency config to remove possible conflict with calendrical's configuration.

## [v0.4.0] — 2026-04-25

### Added

* `~o` in match context. On the left-hand side of `match?/2`, `case` clauses, `=`, or a function head, the sigil now expands to a structural pattern — prefix-matching the value's `:time` keyword list while leaving `:calendar`, `:shift`, `:extended`, and `:qualification` unconstrained. Thanks to @am-kantox for the PR.

## [v0.3.0] — 2026-04-23

### Added

* `Tempo.Interval.metadata/1`. Named accessor for the `:metadata` map on an interval. Mirrors `from/1`, `to/1`, `endpoints/1`, and `resolution/1` added in v0.2.0, so user-facing code never has to reach into struct fields to read iCal `SUMMARY`, `LOCATION`, event UIDs, or any other per-interval data attached by the caller.

### Changed

* Renamed `Tempo.compare/2` and `Tempo.Interval.compare/2` to `Tempo.relation/2` and `Tempo.Interval.relation/2`. The function returns one of 13 Allen interval-algebra relations (`:precedes`, `:meets`, `:overlaps`, …), not the `:lt | :eq | :gt` shape stdlib's `compare/2` promises. The new name avoids the trap.

* Renamed `Tempo.Sigil` to `Tempo.Sigils` (plural), and moved `calendar_from/1` out to `Tempo.Sigils.Options`. `import Tempo.Sigils` now brings only `sigil_o/2` and `sigil_TEMPO/2` into scope — no helper functions leak. The old `Tempo.Sigil` module remains as a deprecated compatibility shim and will be removed in a future major version.

* `Tempo.Visualizer` and `Tempo.Visualizer.Standalone` now compile only when **both** `:plug` and `:bandit` are available. Previously Plug alone was enough to trigger compilation of `Tempo.Visualizer`, and `Standalone` referenced `Bandit` unguarded — so a downstream application that depended on Tempo without pulling in either library saw "undefined module" warnings during compilation. Both modules still expose stub `init/call/start/child_spec/stop` functions that raise a single actionable error when called without the deps in place.

### Bug Fixes

* ISO week-date resolution now uses `Calendrical.ISOWeek` semantics throughout the validation path, regardless of the caller's declared calendar. There is room to be more selective than this (there can be multiple ways to construct a week-based calendar). However there isn't yet a clear way to influence that decision other than through a `-u-ca` qualifier and that only allows ISO Week calendars.

* `Tempo.to_date/1` now handles ordinal dates (`[year, day]` — produced by the `O` designator, the extended `YYYY-DDD` form, or by enumerating a year-only Tempo as days) and ISO week dates (`[year, week, day_of_week]`). Previously both shapes returned a `Tempo.ConversionError` even though the components unambiguously identify a single calendar day. Examples: `Tempo.to_date(~o"2020-166")` now returns `{:ok, ~D[2020-06-14]}`; `Tempo.to_date(~o"2020-W24-3")` returns `{:ok, ~D[2020-06-10]}`; and `~o"2020Y{1..-1}D" |> Enum.to_list() |> hd() |> Tempo.to_date()` returns `{:ok, ~D[2020-01-01]}`.

## [v0.2.0] — 2026-04-23

### Adds

* `Tempo.new/1`, `Tempo.new!/1`, `Tempo.Interval.new/1`, `Tempo.Interval.new!/1`, `Tempo.Duration.new/1`, `Tempo.Duration.new!/1`.

* `Tempo.Interval.spans_leap_second?/1`, `leap_seconds_spanned/1`, and `Tempo.Interval.duration(iv, leap_seconds: true)`. Interval-level leap-second detection and an opt-in duration that counts them. Lets scientific pipelines account for exact elapsed time without Tempo accepting `23:59:60` as a value.

* `Tempo.LeapSeconds.removals/0`. Extension point for future negative leap seconds (CGPM agreed in 2022 that they may become necessary from ~2035). Empty today; interval-level helpers already treat insertions and removals uniformly.

* `Tempo.LeapSeconds`. The 27 IERS-announced positive leap-second dates from 1972-06-30 through 2016-12-31, exposed as `dates/0`, `on_date?/3`, and `latest/0`. Drives historical validation of `:60` seconds.

* Historical leap-second validation. `23:59:60` is now accepted only on the 27 IERS-announced dates. The previous structural check (hour/minute/month-day/offset) remains; a new check rejects `:60` on any other June 30 or December 31. Error messages point callers at `Tempo.LeapSeconds.dates/0`.

* Zone-gap parse rejection. A zoned wall time that falls inside a daylight-saving or zone-transition gap (e.g. `2024-03-10T02:30:00[America/New_York]`) is now rejected at parse time via `Tzdata.periods_for_time/3`. DST fall-back ambiguity is accepted; coarser-than-minute values and unzoned values skip the check.

* `Tempo.year/1`, `month/1`, `day/1`, `hour/1`, `minute/1`, `second/1`. Commodity component accessors for `%Tempo{}` and `%Tempo.Interval{}` values. Return `nil` when the component isn't specified; raise `ArgumentError` when called on an interval whose span covers multiple values of that unit.

* `Tempo.Interval.from/1`, `to/1`, `endpoints/1`, `resolution/1`. Named endpoint and span-resolution accessors so user-facing code never has to reach into struct fields.

* `Tempo.IntervalSet.count/1`, `map/2`, `filter/2`. Named helpers that treat the set as a sequence of member intervals — the complement to the `Enumerable` protocol, which walks sub-points.

* `Tempo.select/2`. Polymorphic composition primitive: narrows a base span (`%Tempo{}`, `%Interval{}`, or `%IntervalSet{}`) by a selector (integer lists, ranges, `%Tempo{}` / `%Interval{}` projection, or a function). Pure function — no ambient reads. Always returns `{:ok, %IntervalSet{}}`, composing with the other set ops.

* `Tempo.workdays/1` and `Tempo.weekend/1`. Territory-aware day-of-week constructors that return `%Tempo{}` selector values — composable with `Tempo.select/2`. Accept a territory atom (`:US`), territory string, locale string (`"ar-SA"`), or `%Localize.LanguageTag{}`; default chain is `Application.get_env(:ex_tempo, :default_territory)` then ambient locale. `workdays(t) ++ weekend(t)` partitions the seven days of the week.

* `Tempo.Territory.resolve/1`. Normalises a territory, territory string, locale, or language-tag value to a canonical uppercase territory atom. The single resolution chain used by `Tempo.workdays/1` and `Tempo.weekend/1`.

* `Tempo.explain/1`. Returns a structured, prose explanation of any Tempo value. `Tempo.Explain` provides `to_string/1`, `to_ansi/1`, and `to_iodata/1` formatters so renderers (the visualizer, terminals, HTML surfaces) can style each tagged part independently.

* Inspect polish. Zoned Tempos round-trip via the sigil with the `[zone_id]` IXDTF trailer. `%Tempo.IntervalSet{}` inspects as `#Tempo.IntervalSet<…>` with a preview and metadata summary. `%Tempo.Interval{}` with non-empty `:metadata` shows the event summary inline.

* iCalendar import. `Tempo.ICal.from_ical/2` and `from_ical_file/2` parse RFC 5545 `.ics` data (via the optional `ical` dependency) into `%Tempo.IntervalSet{}` with per-event metadata on each interval. Overlapping events are preserved.

* Full RFC 5545 `RRULE` expansion. Every `BY*` rule (`BYMONTH`, `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYDAY` with and without ordinals, `BYHOUR`, `BYMINUTE`, `BYSECOND`), `BYSETPOS`, `WKST`, and the `RDATE`/`EXDATE` extras flow through one tagged AST into `Tempo.to_interval/2` and `Tempo.RRule.Selection`. All 30 RFC 5545 §3.8.5.3 worked examples pass — Thanksgiving, Election Day, Friday-the-13th, first-Saturday-after-first-Sunday, last-weekday-of-month, and the rest. Calendar-aware throughout. Unbounded rules still require `:bound`.

* `Tempo.RRule.parse/2` + `Tempo.to_rrule/1`. Parse an RFC 5545 RRULE string to the shared AST; round-trip through the encoder preserves every supported field (including `WKST` and BYDAY-with-ordinal as pairs).

* `Tempo.RRule.Expander.expand/3`. Thin adapter from `%Tempo.RRule.Rule{}` or `%ICal.Recurrence{}` to `%Tempo.Interval{}` AST, delegating materialisation to `Tempo.to_interval/2`. One interpreter path for every recurrence source.

* `Tempo.to_interval/2`. Accepts `:bound` (for unbounded recurrences). New stream pipeline `iterate_recurrence/7` is the single expansion loop — bounded `n`, unbounded `UNTIL`, and `:bound`-capped all share it.

* `RDATE` additive and `EXDATE` subtractive in `Tempo.ICal.from_ical/2`. `final = (expand(rrule) ∪ rdates) − exdates`. RDATEs carry the event's span (`DTEND − DTSTART`); EXDATEs match on the occurrence's start moment via `Tempo.Compare.compare_endpoints/2`.

* Metadata on `%Tempo.Interval{}` and `%Tempo.IntervalSet{}`. Free-form `:metadata` maps travel through set operations — intersection and difference tag result fragments with the A-operand's metadata; set-level metadata follows the first operand.

* Set operations. `Tempo.union/2`, `intersection/2`, `complement/2`, `difference/2`, `symmetric_difference/2`, and predicates (`disjoint?`, `overlaps?`, `subset?`, `contains?`, `equal?`) on any Tempo value. Results are always `%Tempo.IntervalSet{}`.

* Cross-calendar set operations. Operands in different calendars (e.g. Hebrew vs Gregorian) are converted via `Date.convert!/2`; the result inherits the first operand's calendar.

* Midnight-crossing non-anchored intervals. `T23:30/T01:00` anchored to day D materialises as `[D T23:30, D+1 T01:00)`; on the pure time-of-day axis, such intervals are split before set-op sweep-line runs.

* `Tempo.anchor/2`. Axis composition primitive — combines a date-like value with a time-of-day into a datetime. Not a set operation; used to prepare cross-axis values for set algebra.

* `Tempo.Compare`. New shared module with `compare_time/2` (start-moment keyword-list comparison, padding missing trailing units with their unit minimum) and `to_utc_seconds/1` (zone-aware projection via `Tzdata`, per-call, no cache).

* `Tempo.Math.add/2` and `subtract/2`. Calendar-aware Tempo-plus-Duration arithmetic with end-of-month day clamping (`Jan 31 + P1M = Feb 28`, `Feb 29 + P1Y = Feb 28`). Weeks expand to days; negative components subtract.

* Non-contiguous mask expansion. `1985-XX-15` now materialises to an IntervalSet of 12 day-intervals (the 15th of each month) instead of widening to year. Partial masks (`1985-X5-15`) narrow to valid candidates.

* Bounded recurrence and duration-bounded intervals. `R3/1985-01/P1M` expands to N occurrences; `1985-01/P3M` and `P1M/1985-06` materialise to closed intervals via `Tempo.Math` arithmetic. `Enum.to_list/1` on a duration-bounded interval now respects the bound instead of running unbounded.

* `%Tempo.IntervalSet{}` — multi-interval values. Sorted, list of intervals. `to_interval/1` now returns `Interval | IntervalSet` depending on expansion; use `to_interval_set/1` when a uniform shape is wanted.

* Multi-interval materialisation. Range-in-slot (`{1..3}M`), stepped ranges, cartesian ranges, and all-of sets expand to an IntervalSet. One-of sets (`[a,b,c]`) return an error — they're epistemic disjunctions, not free/busy lists.

* Unified conversion from Elixir date/time types. `Tempo.from_elixir/2` accepts `Date.t`, `Time.t`, `NaiveDateTime.t`, or `DateTime.t` and returns a `%Tempo{}` at an inferred or explicit resolution.

* `Tempo.from_date_time/1`. Previously missing for `DateTime.t` — the existing `from_date/1`, `from_time/1`, `from_naive_date_time/1` family now has its fourth member. UTC offset (including DST) populates `:shift`; the IANA zone name and numeric offset in minutes populate `:extended`.

* `Tempo.extend_resolution/2`* fills finer units with their start-of-unit minimum values up to a target resolution.

* `Tempo.at_resolution/2`* dispatches to `trunc/2` or `extend_resolution/2` based on whether the target is coarser or finer than the current resolution. Idempotent when the target matches. The single entry point for normalising a Tempo to a known resolution.

* Implicit-to-explicit interval conversion. `Tempo.to_interval/1` and `Tempo.to_interval!/1` materialise any implicit-span `%Tempo{}` into the equivalent `%Tempo.Interval{}`.

* Support the Internet Extended Date/Time Format (IXDTF) as defined in [draft-ietf-sedate-datetime-extended-09](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html). An optional suffix such as `[Europe/Paris][u-ca=hebrew]` may follow an ISO 8601 datetime.

* Add an `:extended` field to `%Tempo{}` holding `%{calendar:, zone_id:, zone_offset:, tags:}` parsed from the IXDTF suffix (or `nil` when no suffix is present).

* `Tempo.Iso8601.Tokenizer.tokenize/1` now returns `{:ok, {tokens, extended_info}}` where `extended_info` is either `nil` or the parsed IXDTF map.

* Astronomical seasons. ISO 8601-2 season codes 25–28 (Northern) and 29–32 (Southern) now expand to intervals bounded by the relevant March/September equinox and June/December solstice as computed by the `Astro` library. Codes 21–24 remain meteorological calendar approximations.

* Leap-second validation. ISO 8601 permits `second = 60` as a positive leap second. Tempo now accepts it only when the minute is 59, the hour is 23, the calendar date (if present) is 30 June or 31 December, and any time-zone offset is zero. All other uses of `second = 60` are rejected.

* ISO 8601-2 / EDTF qualification operators. Expression-level `?` (uncertain), `~` (approximate) and `%` (both) are now parsed. The parsed qualification is carried on the new `:qualification` field of `%Tempo{}`; the bounded interval semantics of the value are unchanged.

* EDTF conformance corpus. 200+ valid and invalid strings from the `unt-libraries/edtf-validate` corpus (BSD-3-Clause) are now exercised as ExUnit tests. The known-failure list is tracked in `test/tempo/iso8601/edtf_corpus_test.exs`.

* EDTF Level 2 component-level qualification. `?`, `~` and `%` qualifiers can now appear adjacent to individual date components (`2022-?06-15`, `2022-06?-15`, `?2022-06-15`, `%-2011-06-13`). The qualification is stored per-component on the new `:qualifications` field of `%Tempo{}` (a `%{unit => qualifier}` map). Expression-level qualifiers continue to populate the single `:qualification` field.

* Per-endpoint qualification in intervals. Each endpoint of an interval may now carry its own qualifier (`1984?/2004~`, `2019-12/2020%`). The qualifier attaches to that endpoint's `%Tempo{}` struct rather than the interval as a whole.

* Open-ended intervals. `1985/..`, `../1985`, and `../..` now parse, along with the equivalent trailing-/leading-slash forms `1985/`, `/1985`, `/`, `/..`, `../`. Open endpoints are represented as `:undefined` on the `%Tempo.Interval{}` struct.

* Unspecified digits in negative years. Strings like `-1XXX-XX`, `-XXXX-12-XX`, and `-1X32-X1-X2` now parse. The negative sign was previously discarded by `form_number`, causing a crash in `parse_date/1`; it is now carried on the mask as a `:negative` sentinel.

* EDTF long-year notation. `Y`-prefix years with exponent notation (`Y17E8`, `Y-17E7`) or significant-digit annotations (`Y171010000S3`, `Y-171010000S2`) now parse. Combined with existing support for 4-digit `Y`-prefix years (`Y2022`) and plain 5+ digit years (`Y170000002`), this completes Tempo's coverage of the geological-scale year syntax.

* 100% EDTF corpus coverage. The `unt-libraries/edtf-validate` corpus — the only publicly-available conformance test suite we could find for ISO 8601-2 Part 2 — now passes in full. 183 strings exercised, 0 known failures.

* Web visualizer. `Tempo.Visualizer` is a `Plug.Router` that shows a parsed ISO 8601 / ISO 8601-2 / IXDTF string as a large-font echo followed by a component-by-component breakdown.

### Changed

* `tz` added as a `dev/test` dependency and installed as the default `Calendar.TimeZoneDatabase` in `config/dev.exs` and `config/test.exs`. Required for `ical` 2.0 to parse `DTSTART;TZID=…` properties — without a zone database installed, those events come through with `dtstart: nil` and are silently dropped. Runtime consumers configure their own database (see the README).

* Internal builder `Tempo.Iso8601.AST` now owns the token-to-struct conversion path formerly done by a `@doc false` `Tempo.new/2`. The old internal `new/2` is removed. External callers should have been unaffected (the old function was never public); internal callers in the parser / range / set / interval paths have been rewired.

* `Tempo.Clock.clock/0` checks `Process.get({Tempo.Clock, :clock})` before falling back to the application env. Lets the `NowTest` / `ToRelativeStringTest` suites install `Tempo.Clock.Test` process-locally so the swap doesn't leak into concurrent doctests. Fixes an intermittent CI failure in the `utc_now/0` / `now/1` / `utc_today/0` / `today/1` doctests when those suites ran interleaved.

* Leap-second handling is now ecosystem-aligned. `:second = 60` is **rejected at parse** regardless of date (matches `Calendar.ISO`, `Time`, and `DateTime` in Elixir/OTP). Leap-second information is preserved at the interval level via `spans_leap_second?/1`, `leap_seconds_spanned/1`, and `duration(iv, leap_seconds: true)`.

* Cross-calendar `Tempo.Interval.duration/1` now raises `ArgumentError` when endpoints are in different calendars instead of silently computing a garbage value. Error message points at set operations (which handle cross-calendar inputs automatically).

* Numeric zone offsets now bounded to ±24h. Nonsensical values like `+25:00` and `Z28H` are rejected at validation; the ISO 8601 grammar still accepts them but the semantic check refuses anything outside a plausible UTC offset.

* IXDTF `[u-ca=NAME]` suffix now swaps the Tempo struct's calendar. Parse routes the atom (e.g. `:hebrew`, `:islamic-umalqura`, `:ethioaa`) through `Calendrical.calendar_from_cldr_calendar_type/1` to the corresponding `Calendrical.*` module. Explicit `calendar` argument to `Tempo.from_iso8601/2` still wins over IXDTF.

* `mix.exs` docs structure follows the Localize layout — `name:`, `source_url:`, `package()`, `links()`, `groups_for_modules`, `groups_for_extras`, `source_ref`. Hex.pm landing page now anchors to the README rather than the `Tempo` module.

* Dialyzer build now enforces `:underspecs`, `:extra_return`, and `:missing_return` on top of the existing `:error_handling` and `:unknown` flags. All spec mismatches in `lib/` have been resolved.

* Removed all CLDR-family dependencies. `ex_cldr_calendars` has been replaced by [Calendrical](https://hex.pm/packages/calendrical) for calendar functionality and by `Localize.Utils.Math` / `Localize.Utils.Digits` for numeric helpers.

* Reduce parser compile time by ~85% (from ~190s to ~28s) and generated BEAM size by ~61% by converting high-fanout NimbleParsec combinators to `defparsecp` function boundaries. No runtime performance regression.

### Bug Fixes

* Enumeration of zoned values now honours DST transitions. On the day a zone enters DST, the iterator skips the "missing" wall-clock hour (e.g. `Enum.take(~o"2026-10-04[Australia/Sydney]", 5)` yields hours `[0, 1, 3, 4, 5]` — 02:00 never appears on a Sydney clock face that day). On the day a zone exits DST, the duplicated hour is emitted twice, distinguished by the `:shift` field: the first occurrence with the pre-transition offset, the second with the post-transition offset (per RFC 9557 IXDTF's explicit-offset fold disambiguator). The two emitted Tempos round-trip through the parser and project to distinct UTC instants 3600 seconds apart. Unzoned values and values outside DST transitions are unaffected.

* Fix parser interpretation of bare `~o"-1M"`. The `M` designator was resolving to `:minute` inside a time-zone shift (`[minute: -1]`) instead of `:month` (`time: [month: -1]`). Tightened `explicit_time_shift` to require `Z` alone or `Z`-prefixed explicit components; the ambiguous sign-plus-single-unit form now parses as a signed calendar component per ISO 8601-2 §4.4.1.

* Fix `Tempo.select` with negative components and week-of-month context. `~o"-1M"` on a year base now correctly resolves to December; `~o"-1D"` on a year base to Dec 31 (leap-aware); `~o"-1W"` on a year base to the last ISO week; `~o"1W"` on a month base to week-of-month. Week-of-year and week-of-month axes are now kept coherent through the `project_merge` pipeline.

* Fix `Tempo.Inspect` for values with a `:day_of_year` component. `~o"166O"` (day-of-year 166) and its negative-count companion `~o"-1O"` now render through the ISO 8601-2 `O` designator instead of raising a FunctionClauseError inside inspect.

* Removed `Tempo.Shift` (no-op stub that silently dropped shifts) and `Tempo.Comparison` (self-described as "badly wrong" template code with no callers). The one rounding branch that depended on `Tempo.Shift` — `round(time_of_day, :day)` — now returns a clear `Tempo.RoundingError` instead of crashing.

* `Tempo.Interval.spans_leap_second?/1` boundary bug fixed. An interval like `[23:59:59Z, next 00:00:00Z)` now correctly reports `true` — the leap second 23:59:60Z is within this span under the half-open `[from, to)` convention. Previously an off-by-one in the containment test missed the boundary case.

* `Tempo.Interval.empty?/1` now returns `true` for inverted intervals (`from > to`), and `duration/1` returns `PT0S` for any empty interval. Inverted intervals used to silently produce a negative duration.

* Explicit numeric offsets now disambiguate DST fall-back correctly. `01:30:00-04:00[America/New_York]` and `01:30:00-05:00[America/New_York]` now resolve to different UTC instants as RFC 9557 §4.5 describes; previously the zone_id won unconditionally and the explicit offset was silently ignored.

* `Tempo.from_iso8601!/1` no longer silently overrides IXDTF `[u-ca=NAME]` with `Calendrical.Gregorian`. Previously the bang form always passed Gregorian explicitly, which (per the explicit-wins-over-IXDTF rule) nullified the calendar tag; now matches the behaviour of `Tempo.from_iso8601/1`.

* `%Tempo.Interval{}` inspect now preserves each endpoint's IXDTF extended trailer (zone, calendar, tags). Previously the sigil output dropped `[zone]` and `[u-ca=cal]` from interval endpoints even though the data was stored on the underlying Tempo values.

* Spec tightening across the public API to satisfy dialyzer's strict flags. Refined `@spec`s on `Tempo.Compare.to_utc_seconds/1`, `Operations` predicates (`disjoint?/overlaps?/subset?/contains?/equal?`), `RRule.Expander.to_ast/2`, and `Tempo.Interval.resolution/1`.

* Recurrence cadence applies as `DTSTART + i × INTERVAL` (scalar multiplication) rather than `i` successive `+ INTERVAL` steps. The old iterative approach clamped Feb 29 → Feb 28 at step 1 and never recovered; `YEARLY` rules anchored on Feb 29 now correctly produce Feb 29 on every leap year.

* BY-rule EXPAND semantics per RFC 5545 §3.3.10 table. `BYMONTH`/`BYMONTHDAY`/`BYYEARDAY`/`BYWEEKNO` expand when `FREQ` is coarser than the rule's unit (previously they only filtered). Notes 1 and 2 are honoured — `BYDAY` downgrades from EXPAND to LIMIT when `BYMONTHDAY`/`BYYEARDAY` is co-present.

* DTSTART is always the first materialised occurrence. BY-rule EXPAND can legitimately produce candidates earlier than DTSTART (e.g. `BYMONTHDAY=1` with `DTSTART=Sep 30` also yields Sep 1); those are now dropped by the `iterate_recurrence` loop to match the RFC.

* `matches_mask?/2` checks digit equality position-by-position. The previous implementation always returned `true` for concrete digit positions, which silently let non-contiguous year masks like `1_6_` accept any 4-digit candidate. The dialyzer silencer attached to this function has been removed.

* Fix compiler warnings around `%NaiveDateTime{}` struct updates and unreachable clauses in the set enumerable protocol.

* Fix `Enum.take/2` and related Enumerable operations on values with unspecified-digit year masks.

* Fix `Enum.take/2` on year-month-day masks where the day is unspecified (e.g. `1985-XX-XX`, `1985-12-XX`).

* `Tempo.Enumeration.add_implicit_enumeration/1` now raises a clear `ArgumentError` when `Tempo.Iso8601.Unit.implicit_enumerator/2` returns `nil` (e.g. trying to enumerate a fully-specified second-resolution datetime — no finer unit exists).

* Fix group enumeration (`2022Y5G2MU`). The `{:group, %Range{}}` token shape produced by expanded `nGspanUNITU` constructs now has a matching clause in `Tempo.Enumeration.do_next/3` that unwraps the range into the standard range-iteration path. Previously crashed with `no function clause matching in Tempo.Enumeration.do_next/3`.

* Fix selection enumeration (`2022YL1MN`). The `{:selection, _}` clause in `do_next/3` is now ordered before the generic `is_unit` clause, which would otherwise match the selection's inner keyword list and destructively iterate it. `explicitly_enumerable?/1` no longer treats a bare selection as an enumerable shape on its own. The selection tuple is preserved verbatim on every yielded Tempo.

* Enumerate long-year significant-digit shapes (`1950S2`, `Y12345S3`). Year values tagged `{integer, [significant_digits: n]}` now iterate over the block of candidate years sharing the leading n digits (`1950S2` → `1900..1999`, `Y12345S3` → `12300..12399`). Blocks larger than 10,000 candidates raise a clear `ArgumentError` rather than hanging — callers who want to refer to a significant-digits year without iterating can still hold the parsed AST. Negative values enumerate in most-negative-first order.

* Extend `Tempo.Validation.resolve/2`'s `{:year, year}, {:month, months}` clause guard to accept `%Range{}` months. Previously only `is_list(months) or is_integer(months)` was accepted, which meant the implicit month enumerator (`1..-1//-1`) never conformed against `months_in_year` when the year was a range value. Enables correct `1950S2`-style significant-digits enumeration.

* Implement `Enumerable.Tempo.Interval`. Closed intervals and open-upper intervals (`1985/..`) now iterate forward one resolution-unit at a time from the `:from` endpoint; fully-open (`../..`) and open-lower (`../1985`) intervals raise `ArgumentError` with a clear message (no anchor from which to iterate). Iteration honours the half-open `[from, to)` convention — the upper bound is exclusive, so adjacent intervals concatenate without overlap or gap.

* Enumeration of `from/duration` intervals (`1985-01/P3M`) and `R…/from/duration` recurrence intervals no longer crashes. The upper bound is currently treated as open — iteration proceeds forward from the `from` endpoint and `Enum.take/2` / `Stream.take/2` are the idiomatic way to halt it. Computing a concrete upper bound from `from + duration` is tracked separately; until that lands, `Enum.to_list/1` on such an interval is an infinite sequence (don't do it). `duration/to` intervals (`P1M/1985-06`) raise a clear `ArgumentError` explaining that Tempo-Duration subtraction is required to compute the lower bound.

* Enumeration of closed intervals with mismatched-resolution endpoints (`1985/1986-06`, `1985-06/1987`) now compares endpoints as their concrete start-instants rather than bailing on unit-list length mismatch. Missing trailing units are filled with their unit minimum (`:month`/`:day`/`:week` from 1, everything else from 0), so `1985` (start = 1985-01-01) correctly sorts before `1986-06` (start = 1986-06-01) and the interval yields both 1985 and 1986.

* Extend `Enumerable.Tempo.Interval` increment rules to cover `:week`, `:day_of_year`, and `:day_of_week` resolutions. Week-resolution intervals (`2022-W05/2022-W08`) now advance week-by-week, carrying into the next year at `calendar.weeks_in_year/1`.

## [v0.1.0]

This is the changelog for Tempo v0.1.0 released which was never released.

### Enhancements

* Add support for steps in set ranges. This is not ISO8601 compliant but is a natural expectation for Elixir. For example `~o"2023Y{1..-1//2}W"` says "every second week in 2023".

* Add `Tempo.round/2` to round a Tempo struct to a given resolution.

* Add `Tempo.to_date/1`, `Tempo.to_time/1` and `Tempo.to_naive_date_time/1`

* Add `Tempo.to_calendar/1` that will convert a `Tempo.t` struct to the most appropriate native Elixir date, time or naive date time struct.

### Bug Fixes

* Fix implicit enumeration of standalone months like `~o"3M"`. The requires an updated `ex_cldr_calendars` library that supports returning the number of days in the month without a year (returning an error if the result is ambiguous without a year).

* Many miscellaneous bug fixes.
