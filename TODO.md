# TODO

Open work on Tempo. The analysis behind each item, and the record of every decision taken on the way to 1.0, is in [plans/design-notes.md](plans/design-notes.md). Open items are grouped and ordered by priority, correctness first and conformance second (reviewed 2026-10-03).

What each operation gives each shape of value is not listed here cell by cell: [guides/operation-matrix.md](guides/operation-matrix.md) is that table, generated from the code and checked by the test suite, and a cell that returns a named error there is a feature not yet built. An item below is a decision to take, a gap the matrix does not measure, or work of another kind.

## Open

### Correctness

* [ ] **A set with no year in `covered?/2` and in a tree** — `Tempo.IntervalSet.covered?/2` raises a `Tempo.IntervalEndpointsError` for any point asked of a set with a member that runs through its cycle's end (`~o"T22/T02"` and `~o"T00:30"`, `~o"6K/2K"` and `~o"7K"`), where `Tempo.contains?/2` of the same two is `true`: it asks `Tempo.Interval.within?/2` of the member whole, which refuses a span that is two in one turn of its cycle. And `Tempo.IntervalSet.new/2` raises an `ArgumentError` for a member with no year given `backend: :tree`, where it returns an error for every other member it refuses. Found beside the fix of `covered/2`, 2026-10-04.

* [ ] **A span that crosses its cycle's end comes back from a set operation in two** — `~o"T22/T02"` is one member, cut at midnight to be swept and not joined again: `Tempo.union(~o"T22/T02", ~o"T03/T04")` has three members where two were given, and `Tempo.members_outside(~o"T22/T02", ~o"T03/T04")`, the value kept whole, is `T0H/T2H` and `T22H/T0H`; `12M20D/1M10D` likewise. The time covered is right and `coalesce/1` joins them, so the matrix, which compares time, passes. Found 2026-10-04.

* [ ] **A time of day placed on a week gives nothing** — `Tempo.intersection(~o"T09/T17", ~o"2026-W25", within: ~o"2026-W25")` is empty and `Tempo.complement(~o"T09/T17", within: ~o"2026-W25")` the whole week, where the same week written as dates gives its seven days' hours: the window's days are taken from its month and day (`days_in/1` in `lib/operations.ex`), and a week's ends hold neither. Found 2026-10-04.

* [ ] **An intersection is one part for each pair of members that overlap** — `sweep_intersection/3` assumes that no member of an operand overlaps another and skips pairs when one does: of the 4,356 pairs of small sets 1,947 are not one part a pair, and `metadata: {:merge, fun}` misses a member that contributed (`[Alice 0–1]` and `[Bob 0–1, Carol 0–1]` give Alice and Bob alone). The time covered is right. Decided 2026-10-04: each member of the first cut to each member of the second it overlaps, as the documentation says. In [plans/set-operations.md](plans/set-operations.md).

* [ ] **A `:within` window bounds where a time of day is placed** — a time of day is placed on the part of each day the window holds, for every operation alike, where it is placed on the whole of every day the window touches: with a window from noon to noon `Tempo.union(~o"T09/T17", window, within: window)` starts at 09:00, before it opens, and an intersection with a meeting at 10:00 that day returns the meeting. The other operand is not cut. Decided 2026-10-04.

* [ ] **A month with days missing is walked, read and stepped as `1..n`** — `Calendrical.Reform.England`'s September 1752 has the days 1, 2 and 14 to 30: the walk of `1752Y9M` yields 1 to 19, `1752Y9M3D` is read and `1752Y9M20D` is an `InvalidDateError`, since Tempo takes a month's days to be `1..days_in_month/2`. Its 1751 is shorter still, the legal year beginning on 25 March: no January or February (`days_in_month/2` is 0) and a March of the days 25 to 31. A step follows the same count: `1752-08-25` plus a month is the 19th where the 25th exists, `1752-03-15` less thirteen months is `1751Y2M0D`, and `Tempo.shift/2` of `1752YX*M15D` by `month: -13` raises an `ArgumentError` on that day 0. Calendrical lists a month's dates (`Calendrical.Interval.month/3`, `valid_date?/3`), so the fix is Tempo's, and it has one place to go: the reading, the masks and the step all ask `Tempo.UnitValues` for a unit's values, its first and last, and what follows and precedes a value. Found 2026-10-04.

* [ ] **A month of a year that starts within the months is the nth month of the year** — in `Calendrical.Julian.March25` `2026Y1M` is 25 to 31 March and `2026Y12M` 1 February to 24 March, as Calendrical's `month/2` counts them, and the walk of a year yields them in that order, where it yields the Julian months 1 to 12 in number order, the first three of which come after the other nine. A date keeps its month's Julian number, so a month's number is not the month of its dates. Decided 2026-10-04.

* [ ] **A Gregorian week's days are calendar dates from the walk and a shift** — `Enum.to_list(~o"2026-W25")` yields `2026Y6M15D` to `2026Y6M21D` and `Tempo.shift(~o"2026-W25", day: 1)` is `2026Y6M16D`, where both give a week and a day of it (`2026Y25W2K`), which the parser reads as the calendar date. A calendar of weeks keeps its week dates. Decided 2026-10-04, following the decision of 2026-10-03 for a value built or read.

* [ ] **`extend/2` of a group writes what the group walks** — `Tempo.extend(~o"2026Y2G3MU")` is `{:ok, ~o"2026Y{4..6}M"}`, the months the group yields, where it writes `2026Y2G3MU{1..-1}D`, a range of days counted from the group's start that nothing reads (`:counted_in_group`). Groups of days and of hours each need their writing. Decided 2026-10-04.

* [ ] **A qualification is held per component alone** — `2026?` and `?2026` are one value (ISO 8601-2 §8.2.4), written in the preferred form, where the first holds `qualification: :uncertain` and the second `qualifications: %{year: :uncertain}`, the two are not `==`, and the walk of the first yields uncertain months (`2026Y1M?`). A unit a walk adds is not qualified, and `trunc/2` drops the qualifier of a unit it drops. The matrix's read-back check (`same_value/4` in `test/support/matrix/checks.ex`) is then `==`. Decided 2026-10-04.

### Conformance and completeness

* [ ] **A day with no month selected in a year is a day of the year** — `2026YL-1DN` is 31 December and `2026YL45DN` 14 February, as the value `2026Y-1D` and `Tempo.select(~o"2026", ~o"-1D")` read it, where the selection reads the day in the year's first month (31 January). An RRULE's `BYMONTHDAY` keeps its own rule, DTSTART's month. Decided 2026-10-04; with it a constraint of `select/2` and a selection go through one resolver, and the matrix's selections take the form in.

* [ ] **An interval's end of several components in the basic format** — `20260615/0720` and `20260615T1030/1130` read the end as a year (720, 1130), where the extended forms (`/07-20`, `/11:30`) and a bare number (`/20`) take the units the end leaves out from the start. For the grammar of [plans/parser-formal-grammar.md](plans/parser-formal-grammar.md). Found 2026-10-03.

* [ ] **A §12.10 window shorter than the unit selected in it is an error** — `FL11MLL1K1IN/PT12HN1K1IN` and a window of no length (`/P0DN…`) are refused when the value is read, where they walk the anchor day and the day before it (a reversed range). A window of twelve hours that selects hours is read. Decided 2026-10-04.

* [ ] **A range of years before the era is read and not listed** — `Enum.to_list(~o"{-5..-3}Y")` is a `ConversionError` ("its year counts from the end of a span the units before it do not fix"): the walk takes a negative end of a range for a count from the end, where a year below zero is a year. A set of them (`{-5,-3}Y`) is listed. Found 2026-10-04.

* [ ] **Sets the parser does not read** — a qualified member (`{2026-06-15?,2026-06~}`); the fractions of a second as a set (`T10H30M45.{0..9}S`), the form `extend/2` gives a second and `inspect/1` writes; and a fraction before a comma or the closing brace (`{T10:30:45.5,T11:00}`, `{2021-06-15.5}`), which the lookahead after a fraction's digits refuses, so a set's member has no fraction of a second. Found 2026-10-02 to 2026-10-04.

* [ ] **Week-of-month selections, and calendar-aware RRULE `BYWEEKNO`** — parse `2026Y6M2W` ("2nd week of June", a positional `W` after a month) and materialise it via `Calendrical.week_of_month/3`; and replace the hard-coded ISO week walk still used by RRULE `BYWEEKNO` with Calendrical's calendar-aware functions. Month and native week-of-year selections are done. Plan in [plans/recurrence-selection-resolution.md](plans/recurrence-selection-resolution.md).

* [ ] **Set operations across a week calendar's resolutions** — `Tempo.difference(~o"2026"W, ~o"2026-W25"W)` is a `ResolutionError` ("Cannot express … as a month-axis calendar date"), in `Calendrical.ISOWeek` and `Calendrical.NRF` alike. Found 2026-10-02.

* [ ] **Traditional months that are sets or masks** — `2026Y{1,2}m` parses as a mask (`traditional_month: {:mask, [[1..2]]}`) and a masked one (`1Xm`) is a `ConversionError` from `Enum` and `to_interval/2`: nothing lists the traditional months a year has, which is Calendrical's to answer. Found 2026-10-03.

* [ ] **A shift reaches each value of a set** — `~o"2026Y6M{1,15}D"` plus a day is `~o"2026Y6M{2,16}D"`: each value the set names is shifted and the results gathered into the value where one unit can hold them, and into an interval set where it cannot (`{15,30}D` plus a day is 16 June and 1 July), where a shift from a unit that holds several values is a `ConversionError`. Decided 2026-10-04.

### Errors and API

* [ ] **An impossible date's error names too little** — `Tempo.on(~o"2M29D", ~o"2027")` returns an `InvalidDateError` with only its reason ("29 is not valid. The valid values are 1..28"), naming no year, month or calendar.

* [ ] **An open-start window's error** — `within: ~o"../2027"` returns an `IntervalEndpointsError` about including an open interval in a set: correct, but it should say that a window needs a start.

* [ ] **`Schedule.task/3`'s `:within` is a pair** — it takes a `{from, to}` tuple, where every other `:within` takes a Tempo value or an interval.

* [ ] **`explain/1` words a window of hours in ISO 8601** — `Tempo.explain(~o"R/2027-01-01/P1D/FLLT22HN/PT4HN")` says "the PT4H window from at 22:00" where it means the four hours from 22:00: `window_phrase/2` in `lib/explain.ex` words only a window of days or weeks, and a time-of-day selection's noun carries its "at".

* [ ] **A struct with no calendar is half read** — `%Tempo{time: [year: 2026], calendar: nil}` converts, extends and walks in the default calendar, but `Enum.count/1` raises an `UndefinedFunctionError` (`Tempo.Interval.Steps.fill_to_unit/3`) and it inspects as `Tempo.from_iso8601!("2026Y", nil)`. Found 2026-10-03.

* [ ] **A mask with no unit before it names no value in its error** — `Tempo.to_interval/2` of `~o"XXM"`, `~o"X*M"` or `~o"TX*H"` returns a `ConversionError` whose `value` is `nil` ("Cannot convert a masked Tempo with no un-masked coarser unit to an interval"). Found 2026-10-03.

### Performance

* [ ] **A never-matching selector walks the whole horizon** — `Tempo.select/2` over an open-ended span walks a thousand years of periods before a selector that never matches ends: 30 ms of years, 0.2 s of months, about 10 s of days, minutes of hours. An index selector on a fixed-range unit could end after its first empty period, a daylight-saving gap day aside. A recurrence's rule that selects nothing is as slow where the search has no bound of its own: twelve seconds where its start has no year (`R3/T22H/PT1H/FLT25HN`) and over forty-five in a calendar of weeks (`R2/2026-W25/P1W/FL8KN` in `Calendrical.ISOWeek`), where a Gregorian one answers in under a second.

* [ ] **Conditional first pass walks whole periods** — it widens the bound by the conditions' reach, and the walk covers every period the widened bound touches, so a ±1-day bridge crossing both year ends materialises three years: Japan's holiday set takes 55 ms a year with its bridge, 25 ms without. Widen only where a condition reaches past the bound (the bridge's days, a move's search back from the bound's start).

* [ ] **Validating a week date costs twenty times a calendar date** — a week and a day of it validate in 42 µs where a year, month and day take 2 µs, after the week's own lookup was made one step of Calendrical's arithmetic, so `2026Y25W3K` is read in 106 µs where `2026Y6M15D` takes 48. Profile validation of the week axis. Measured 2026-10-04.

* [ ] **Parser cost by shape** — bare dates still pay the backtracking tax: `tokenize/1` takes ~360 µs for `2026-06-15` and ~430 µs for `20260615`, against ~40 µs for `2026Y6M15D` (measured 2026-09-24). Take a shape histogram of a real consumer's calls; if it is mostly dates, choice ordering in the single `defparsec :iso8601` entry point is the whole story. Any hand-rolled scanner must be conservative and differentially tested against the general parser.

### Features

* [ ] **Shift, truncate and round an interval** — `Tempo.shift/3`, `trunc/2` and `round/2` take one date or time value and return an `ArgumentError` for an interval, where moving a meeting a day on is a shift of both its ends. The matrix's Shift and round column for the interval classes is the list.

* [ ] **The length of a span with no year** — `Tempo.duration(~o"T22/T02")` is a `Tempo.UnanchoredError`, where the span is four hours on any day, as `at_least?/2` already measures it (`Tempo.Interval.Cycle.microseconds/1`).

* [ ] **`Tempo.Intervallic` protocol** — let user-defined structs such as `%Booking{check_in, check_out}` take part in Allen comparisons and set operations without being copied into `%Tempo.Interval{}`; default implementations for `Tempo.Interval`, `Tempo` and single-member `Tempo.IntervalSet`.

* [ ] **A composable builder** — an API between `Tempo.new/1` (flat components) and `Tempo.from_iso8601/1` (a string) in complexity, building a value from composable sub-expressions with human names — `selection`, `recur`, windows, domains, exclusions, events — nesting freely, so programs (tempo_holidays among them) construct recurrences structurally instead of interpolating ISO 8601 strings and re-parsing them.

* [ ] **Lazy backend follow-ups** — splicing a lazy set into a busy list (needs a sorted stream merge), lazy set algebra (the research project under Deferred), and holiday generator sources. The refusal semantics must hold: an answer that needs an unbounded walk without a `:within` window refuses rather than hangs.

* [ ] **Create a glossary guide** — a guide that tables every term Tempo uses (span, window, occurrence, resolution, floating, zoned, anchored, …) and defines it, so it doubles as the reference future development checks its vocabulary against (user, 2026-09-28). The decisions in [plans/vocabulary.md](plans/vocabulary.md) are its starting point.

* [ ] **Workday adjustments: following, preceding and their modified forms** — the date-roll conventions of financial contracts: a day when it is a workday, otherwise the next (or the previous) one, and the modified forms that turn back when the adjusted day leaves the month. `nearest_workday/2` and `next_workday/2` are different rules; found comparing Tempo with bizdays' ANBIMA calendar, 2026-10-03. Analysis in [plans/anbima-calendar.md](plans/anbima-calendar.md).

* [ ] **A span with no year in `to_string/2` can take Localize's interval** — Localize `main` writes an interval of two dates with no year in CLDR's interval format for the fields they hold: `%{month: 6}` to `%{month: 8}` is "Jun – Aug", and with a day on each end "Jun 15 – Sep 1", or "Jun 15 – 20" in one month. Both ends must hold the same fields, and no order is asked of them, so November to February is written too. It unblocks the Blocked item below once the lock moves. Found in the Localize session, 2026-10-04.

### Release and housekeeping

* [ ] **Livebooks install 2.0 at the release** — `getting-started`, `tempo_tour`, `scheduling-workbook` and `uncertain-dates-workbook` install `{:ex_tempo, "~> 1.6"}` and the Melbourne deck `~> 1.6.3`, while their code uses the 2.0 names: at the 2.0.0 release each installs `~> 2.0`, as `everyday-holidays` already does.

* [ ] **`rescue` in the library** — `lib/ical.ex` (`parse/2`, `available/2`, errors from the `ical` parser), `lib/inspect.ex` (Localize's calendar encoding) and `lib/iso8601/parser.ex` rescue exceptions where the rest of Tempo passes tagged tuples.

* [ ] **Coverage to 90%** — the CI lint row runs plain `mix test` until coverage reaches the default 90% threshold, then takes the reference workflow's `mix test --cover`. 85.5% today (2026-09-27) with the existing `ignore_modules`; `mix test --cover` lists the modules below it.

* [ ] **`ClockTest` timing** — "process-local override does not leak to peer processes" failed once under load (passing in isolation and on re-runs): `assert_receive`'s default 100 ms timeout is short on a busy machine.

* [ ] **`Tempo.Enumeration.maybe_add_implicit_enumeration/1` has no caller** — remove it. Found 2026-10-03.

* [ ] **The exhaustive matrix on a schedule** — `mix test --include exhaustive` runs 1.2 million cells in about sixteen minutes on sixteen cores, so it is run by hand; a weekly CI job would hold it. The default suite runs the 324,000 cells of the smaller corpus in half a minute.

## In progress

* [ ] **One implementation of the set operations, verified** — the step after the one implementation of a unit's values (user, 2026-10-04): strong confidence in a single implementation of `Tempo.union/2`, `intersection/2`, `difference/2`, `symmetric_difference/2`, `complement/2`, the member operations and the predicates. The inventory is [plans/set-operations.md](plans/set-operations.md): they are one implementation, three sweeps in `lib/operations.ex` behind one preflight, with five other places that answer a question the sweeps also answer. Landed: the inventory, with two bugs and two decisions found by it; and the measure (`test/tempo/set_operations_measure_test.exs`), which holds each operation of two sets of several members to the members worked out from their positions by arithmetic on whole numbers, each with the mark of the member it is or was cut from: every pair of sets of up to two members between five points, a fifth of them again on a tree, and generated sets of days, of hours, of the two mixed, of hours in two zones and of days of the Hebrew, Persian and Gregorian calendars. Every sweep agrees with it; `covered/2` did not, and is fixed: its regions, and `coalesce/1`'s, are held on a line with a year and on four cycles (the day's hours, the week's days, the year's months and its days). It does not yet reach two operands with no year, a time of day placed on a `:within` window, the forms that take a list of operands or the `:metadata` option. Next: the two bugs (a span that crosses its cycle's end in two; a time of day on a week window), then the measure widened. 2026-10-04.

* [ ] **Enumeration and selection in every calendar** — the requirement (user, 2026-10-04) is confidence that both work for all calendar types, at all resolutions, on all full and partial dates and times. A census of nineteen calendars against answers worked out from the calendar alone has 489 of 498 full forms and 514 of 550 selections right, and nothing with no year verified; the bugs, the gaps, what is not measured and the order of work, which starts with one implementation of a count from the end, are in [plans/enumeration-and-selection.md](plans/enumeration-and-selection.md). Landed: `Tempo.UnitValues`, the one implementation, verified against the calendar asked another way in fourteen calendars, with a selection's resolver, `Tempo.select/2`, the walk and the reading of a value (`conform/2`) counting through it, `in_any_year/3` the one place a calendar is asked what a unit takes with no year, and the reading of a value and its masks taking a unit's values in a year from `in_period/3`. A step from a value asks it what follows and what precedes a value and for a period's first and last, a selection's resolver holds no count of its own, and `Tempo.explain/1` counts through it where a unit's values are fixed: the five callers are on the one implementation. To follow: the census as a test, and the bugs and gaps the plan lists. 2026-10-04.

* [ ] **Selections the matrix lists** — the matrix now measures selections: `Tempo.Matrix.Selections` writes each part of a selection in each of seven ways in 31 periods (217 values, in the Gregorian and Hebrew calendars and a calendar of weeks) and works out what each selects from the calendar alone, and three checks hold `to_interval/2`, a recurrence's rule and `Tempo.select/2` to it. Its baseline listed 135 cells, five causes, and lists 83, three causes, to fix one a turn: a weekday selected in a Gregorian week is its Monday, in a value and in a rule (`2026Y25WL3KN`, 42 cells); in a calendar of weeks a week selected in a year is the year (6); and `inspect/1` and `to_iso8601/1` raise a `FunctionClauseError` on a selection under an hour (`2026Y6M15DT10HLT30MN`, 35). Fixed: `Tempo.select/2` on a set or a range of weekdays and on a weekday with a time of day (24), a year's weekdays in a calendar of weeks, which stopped at its twelfth week (9), and `explain/1` on a range that reaches the end (19). 2026-10-04.

* [ ] **Vocabulary for 2.0** — one meaning per word and one word per meaning across Tempo and tempo_holidays: `:within` for `:bound`, "anchor" in one sense, no public "materialise", `Tempo.Allen` beside everyday predicates, `datetime`, "workday". Every decision is taken; the tasks are in [plans/vocabulary.md](plans/vocabulary.md). Fifteen of its sixteen tasks have landed, through tempo_holidays and the real-world livebook (`livebook/everyday-holidays.livemd`, and its tempo_holidays copy); `tempo_sql`'s move to `~> 2.0` remains, once 2.0.0 is on hex.

## Blocked

* [ ] **A span of two values with no year in `to_string/2`** — `Tempo.to_string(~o"6M/9M")` and `~o"6M15D/9M1D"` return Localize's `DateTimeIntervalFormatError` (`:mixed_endpoints`), where each end alone is shown ("Jun", "Jun 15"). Blocked on `Localize.Interval.to_string/3` taking a date with no year, the second Open item of its `TODO.md`: `Localize.Interval.to_string(%{month: 6, calendar: Calendrical.Gregorian}, %{month: 8, calendar: Calendrical.Gregorian})` is that error, since its `date_value?/1` wants a `:year`. Found 2026-10-03.

* [ ] **A week calendar's week in `to_string/2`** — a week in a calendar of weeks reads as the locale's words, "week 25 of 2026" ("Woche 25 des Jahres 2026" in `de`), and two weeks "week 25 of 2026 – week 26 of 2026", where it is its first and last day today, "2026-W25-1 – 2026-W25-7"; `to_iso8601/1` is the notation. Decided 2026-10-04, replacing the "2026-W25" expected on 2026-10-02. Blocked on Tempo's lock moving to a Localize `main` that writes a year and a week with CLDR's `yw`, as it does since the Localize session of 2026-10-04.

## Deferred

* [ ] **A formal grammar the parser is held to** — an ABNF transcribed from ISO 8601 clause by clause, a recogniser and a generator that check `from_iso8601/1` against it in both directions, and the standard's 573 examples as a table, with a pilot on Part 1 clause 5 first. Deferred (user, 2026-10-04) over the speed a generalised ABNF parser would lose; the plan keeps the tokenizer and runs the grammar in test support, which is to be weighed when it is taken up again. Plan in [plans/parser-formal-grammar.md](plans/parser-formal-grammar.md).

* [ ] **Set algebra over open-ended windows** — a research project for later (user, 2026-09-28): how far union, intersection, difference, complement and the predicates go on the lazy sets an open-ended window gives, a test of the whole algebra. Questions in [plans/open-ended-set-algebra.md](plans/open-ended-set-algebra.md).

* [ ] **`Calendar.ISO`'s week numbers follow the locale in Localize** — in Localize's next commit after `9fa075f5`, `Y`, `w` and `W` for a `Calendar.ISO` value are the locale's weeks (1 January 2027 is in week 1 of 2027 in `en`, week 53 of 2026 in `de`), ISO 8601's only where the locale's week data is Monday and four days or with `-u-ca-iso8601`. Tempo passes no week pattern to Localize today, so nothing changes until it does. Noted from the Localize session.

## Done

* [x] **An interval with no end refuses what needs its end** — `Enum.at/2`, `Enum.fetch/2`, `Enum.empty?/1`, `Enum.random/1`, `Enum.slice/2` and `Enum.take/2` with a negative count raise the interval's own `Tempo.IntervalEndpointsError`, as its `Enum.count/1` did, where two of them walked for ever; a lazy set refuses the same with its `UnboundedSetError`. 2026-10-04.

* [x] **A value is placed only on a value of its own calendar** — `Tempo.at/2` and `on/2` return a `ConversionError` naming both calendars where two values that hold date units are of different ones (`~o"6M15D"` or `~o"25W2K"` on a Hebrew or an ISO week year), where the numbers were read in the other's calendar; a time of day is placed on any. `Tempo.select/2` still reads a selector's numbers in the span's calendar, a question for the user. 2026-10-04.

* [x] **A week with no year has no week after it and no span** — the stepper asks `Tempo.UnitValues` for the week after a week as for every other unit, and with no year it has no answer, where it counted to a literal 52 in every calendar; so `25W` and the last day of a week (`25W7K`) have no span, which weeks 1 to 51 had. A step back needs no count and stays. A count of weeks with no year in Calendrical (a `weeks_in_year/0`) would let a week follow the rule of months and days. 2026-10-04.

* [x] **An unspecified unit follows the count with no year** — the walk of `2MX*D` is a `Tempo.UnanchoredError`, as that of `2M`, `2MXXD` and `2M{1..-1}D` is, and so is a Hebrew `X*M` and a mask counted from the end of such a month (`2M-XD`), where each listed the values of the longest year; the span stays the month, and a cycle still ends at the most a year can have (`Tempo.Mask.at_most/3`). 2026-10-04.

* [x] **A set none of whose members exists is an `InvalidDateError`** — `~o"2026Y{2,6}M31D"`, `{2026,2027}Y2M29D` and their like are read, as a mask no value matches is, and name no date: the walk raises the error and `to_interval/2` and what rests on it return it, where the walk yielded nothing and the conversion an empty set. One of whose members exists gives those. 2026-10-04.

* [x] **A range written backwards is a parse error** — `{2026-06-20..2026-06-15}`, `2026Y6M{20..15}D` and every other range whose first value is after its last are a `Tempo.ParseError` when read, in a value, a set, a group, a selection or a rule, and one whose ends are counted to a first after its last (`{-1..1}D`) an `InvalidDateError`; the walk of a range downwards, and the negative step in `Tempo.UnitValues`, are gone. 2026-10-04.

* [x] **A position after a set of weekdays follows §12.9** — decided: `L{1,3}K1IN` stays the first of the Mondays and Wednesdays taken together, as the normative clause and RRULE's `BYSETPOS` read it, and not each weekday's first, as an example of §12.11.3 has it, which is written as a set of two selections. 2026-10-04.

* [x] **A month placed on or selected in a calendar of weeks stays refused** — decided: the `ConversionError` that says the calendar has no months, and to place a week and a day of the week, is the answer. 2026-10-04.

* [x] **`covered/2` gives each region as long as it can be, and reads a set with no year on its cycle** — members that meet are one region at any threshold, a member that runs to or through its cycle's end is covered where it was lost (`covered/2` of `T22/T02` was empty), and one no cycle can be cut for is an error; the measure holds its regions, and those of `coalesce/1`, on a line with a year and on four cycles. 2026-10-04.

* [x] **`explain/1` words a count from the end, and a selection in full** — a range that reaches the end of its period is worded by its ends ("on the 28th to the last") where `explain/1` raised, a weekday, a month and a time of day are counted through `Tempo.UnitValues` and named ("on a Saturday or Sunday", "in December", "at 10:30"), the minutes and seconds of a selection and the month of its period are no longer left out, and a value with no year reads "The last day of February". Nineteen cells of the matrix's baseline, which lists 83. 2026-10-04.

* [x] **A selection's resolver asks the one implementation** — the eight places `Tempo.RRule.Selection` asked the calendar for a count take a month's days, a year's months and their first and last from `Tempo.UnitValues`, as the stepper's clamp does (`at_or_before/4`). A year's weekdays in a calendar of weeks are those of each of its weeks, where they stopped at the twelfth: nine cells of the matrix's baseline, which lists 102. 2026-10-04.

* [x] **A month or a week before a selection is held to its year** — the units before a selection are read as they are with no selection after them: `2027Y53WL1KN` and a Hebrew `5786Y13ML1KN` are an `InvalidDateError`, where a week its year does not have converted to a week that does not exist, or raised in a calendar of weeks. 2026-10-04.

* [x] **A step asks the one implementation what follows a value** — `Tempo.UnitValues.following/4`, `preceding/4`, `first/3` and `last/3`, held to the calendar's own word on which dates are valid in fourteen calendars; the stepper's separate paths for a value with a year and one with none are one, with the same answers in 171,545 probed cells. A walk of a year's days is 8% faster and of a Hebrew year's 18%, the year being asked only where the answer depends on it; a walk of months is 11% slower. 2026-10-04.

* [x] **The reading of a value and its masks take a unit's values in a year from the one implementation** — the months, weeks and days of a year, the days of a month and of a week come from `Tempo.UnitValues.in_period/3` wherever a value is read or a mask expanded, with the same answers in 38,435 probed cells; `in_period/3` now refuses the days of a month its year does not have, where it passed on what the calendar answered or raised. 2026-10-04.

* [x] **With no year, one place asks the calendar what a unit takes** — `Tempo.UnitValues.in_any_year/3` gives the values a unit takes in every year and in the year that has the most, and the reading of a value, its masks, its walk, a step from it, rounding and `explain/1` take it, where five modules each asked the calendar. The last month a year can have (a Hebrew or a Chinese `13M`) has its span and its next month, as the last day a month can have always had. 2026-10-04.

* [x] **A set that holds a count from the end is the set of its numbers** — the parser joined a set's members across the two ends and took a signed list to be in order: `{-1,0}H` was the range `23..0`, `{28..30,-1}D` lost its last day and `{1..9//2,10}D` its 10th. Members are joined only where both count from one end by ones, the reading of a value and the walk put the set in order once its counts are taken, and a set of years is in order whatever its signs. 2026-10-04.

* [x] **With no year, every calendar is read as the Gregorian is** — Tempo locks Calendrical `6bbb560`, which answers a month's length with no year: a month of one length is converted and walked, and a day of a month converted, in the Julian, Persian, Coptic, Ethiopic, Indian, Islamic and Hebrew calendars, where the walk raised or the conversion refused. 2026-10-04.

* [x] **A set or a range of a clock unit is held to the unit's values** — `T{22..25}H`, `{58..61}M` and `2026Y25W{1,8}K` are an `InvalidDateError` when they are read, as a range of days past the month's end is; the walk yielded hours 24 and 25. The reading of a value counts through `Tempo.UnitValues.resolve/2`. 2026-10-04.

* [x] **A rule counted in a date, on a start with no year, is an `UnanchoredError`** — `R3/6M/P1M/FL15DN` raised a `FunctionClauseError` and a weekday or a month from the end searched for an occurrence that could not come; `Tempo.to_interval/2` refuses each by name, and a rule of months as written or of a time of day is answered as before. 2026-10-04.

* [x] **A count from the end in a selection is counted in its period** — a month, a weekday, an hour, a range that reaches the end (`{28..-1}D`), a position (`{2..-1}I`) and a unit after the selection (`2026YL6MN-1D`) select what their positive twins do, in a value and in a recurrence's rule; the values a part names are taken in the order of time and once each, which puts an RRULE's unordered lists right (`BYMONTHDAY=15,1;COUNT=3`), and a value its period lacks (hour 25) is passed over. 2026-10-04.

* [x] **A time of day selected in a month is on its first day, a divergence** — a selection follows the first-day rule (user's decision): `2018Y9MLT8H20MN` is 08:20 on 1 September and has no third instance, where ISO 8601-2 §12.11.1 example 2 reads the third as 3 September; recorded in the conformance guide with the form that names the days (`2018Y9ML{1..30}DT8H20M3IN`). 2026-10-04.

* [x] **A fraction of a minute or an hour is read to the second or the minute** — the reading stands (user's decision): `T10:30.5` is the second 10:30:30 and `T10.5` the minute 10:30, as ISO 8601-2 §7.12 reads them; a fraction that does not land on a whole minute or second is the one the time falls in (`T10.51` is 10:30), where the value held a fractional minute nothing could read. 2026-10-04.

* [x] **A time of day under a year or a month is on its first day, a divergence** — it stays the first day (user's decision) and is recorded as a divergence from ISO 8601-1 §5.4.1 and ISO 8601-2 §7.7.1 in the conformance guide, the migration guide and `at/2`, with the form that names each day (`2026Y6M{1..-1}DT17H`). 2026-10-04.

* [x] **A count from the end with no year waits for one** — a day counted from the end of a month whose length depends on the year is kept as written until the value is placed on a year (user's decision): `~o"2M-1D"` on 2027 is 28 February, where it was the 29th and an error there; a month from the end is kept as written too, and what needs the count returns an `UnanchoredError`. 2026-10-04.

* [x] **A comma between a set's members is never a decimal sign** — `{2023,2020/2021}` is a year and an interval, where `2023,2020` was read as a number and the set was one interval from part way through 2023, and `{2020/2021,2023/2024}` parses; a fraction in a member is written with a full stop. 2026-10-04.

* [x] **A second followed by a position, and numbers given to significant digits** — in a selection `0S1I` is second 0 and position 1 (the `S` was read as the significant-digit marker and the second lost); a duration's seconds take significant digits and a set, where they raised; a position, and a fraction no exponent has scaled, take none. 2026-10-04.

* [x] **A value's calendar is recorded once** — the name a `[u-ca=…]` suffix gives is the value's calendar module and is not kept in `extended`, which holds a zone and tags or is `nil`, so a value equals the same value however it was made, and its own text read back. 2026-10-04.

* [x] **The enumeration `extend/2` adds is the one the parser reads** — the months of several years and the days of several months are written `1..-1//1`, so `Tempo.extend(~o"2026Y{6,7}M")` equals `~o"2026Y{6,7}M{1..-1}D"` and inspects as it. 2026-10-04.

* [x] **A group of a set has a span for each group** — `to_interval/2` gives a span for each group and the walk their values in turn (`2026Y{1,2}G3MU` is the first two quarters), a group from the end counted in what holds it. 2026-10-04.

* [x] **The Calendrical and Localize locks moved to their heads** — Calendrical `ad5ff77`, fourteen commits on from `a60de7a`, and Localize `6c5d4ef2`, ten on from `45f252e`; the suite and the matrix pass unchanged. 2026-10-03.

* [x] **A validated core** — a matrix of every public operation against every shape of value (324,000 cells on every test run, 1.2 million on request), consistency checks against an independent measure of what a value covers, a reference for the core in 59 properties, and a published table of what each function gives each class; none of its cells fails. Plan in [plans/validated-core.md](plans/validated-core.md). 2026-10-03.

* [x] **An interval's end of a day alone reads as a century** — a bare number is the start's last unit (`2026-06-15/20` ends on the 20th), and a day and a time, a week and its day and a day of the week are read as ends too. 2026-10-03.

* [x] **A mask counted from the end, or with fewer digits than its unit, converts to the whole unit** — `to_interval/2` reads a mask with the walk's reader: `2026Y-XM` is April to December and `2026YXM` January to September. 2026-10-03.

* [x] **An interval or a recurrence from a masked start, written with a duration** — a start that names one span is the point it starts at before the duration is counted (`2026Y6MXXD/P1M` is June, `R3/2026-33/P3M` three quarters), and its walk is refused as a mask's is. 2026-10-03.

* [x] **An unspecified year is no point to measure from** — `X*Y` is no year in every operation: `duration/1`, `to_relative_string/2` and `to_interval/2` return a `Tempo.UnanchoredError` where they raised or answered. 2026-10-03.

* [x] **Functions that return tuples raise for what is no value** — every function of one date or time value returns the same `ArgumentError` for an interval, a set or any other term. 2026-10-03.

* [x] **Converting a week date costs 220 µs** — an ISO week's start is one step of Calendrical's arithmetic, where every week of the year was listed. 2026-10-03.

* [x] **`to_interval/2` of a partly masked day straight after a year says the value has no year** — a masked day of the year, written `O` or as a day straight after its year, is the span of the dates it names (`2026Y3XD` is `2026Y1M30D/2M9D`), where the `O` form gave bounds that measured as no time. 2026-10-03.

* [x] **`Enum.count/1` and `Enum.member?/2` of an interval with no end never return** — the count is an `IntervalEndpointsError`; membership is answered from the step the value would be, or by a walk that stops once it has passed it, where the start has a year, and refused where it has none. 2026-10-03.

* [x] **`Tempo.extend/2` raises** — a value with no finer unit is a `ResolutionError`, and a value that is not one date or time, or a unit that is not `nil`, an `ArgumentError`; a second extends a decimal place at a time and inspects as `45.{0..9}S`. 2026-10-03.

* [x] **An unspecified month or day is no point to measure from** — `to_interval/2` reads an unspecified unit other than the year as the mask of all its digits is (`2026Y6MX*D` is June 2026, `2026YX*M15D` the 15th of each month), so `duration/1` and `to_relative_string/2` measure it and an interval end written so is the point its span starts at. 2026-10-03.

* [x] **`Tempo.shift/3` with `:skipping` raises for a value that is not one moment** — a set, a range, a group, unspecified digits or a selection is a `ConversionError`, checked before the walk; a margin of error still shifts. 2026-10-03.

* [x] **A group of a set raises outside `to_interval/2`** — `at/2`, `on/2`, `trunc/2`, `nearest_workday/2` and the resolution functions return a `ConversionError` for a value holding one, the accessors read no one number from it, and `trunc/2` of a value holding a selection no longer raises. A span for each group remains, as its own item. 2026-10-03.

* [x] **A selected day is walked as a day and a selected hour by its minutes** — a span a value's selection picks is walked as the span it is: the hour of `2026Y4ML1K1INT10H` carries no walking unit, as its day and a recurrence's occurrences carry none. 2026-10-03.

* [x] **A time after a month with no day** — a month alone with a time written with its `T` parses (`6MT10H`), as after a year it did, so `2G2MUT10H` walks to `3MT10H` and `4MT10H` that read back, and validation resolves a month before a time against its year (`2026Y-1MT10H` is December). 2026-10-03.

* [x] **A qualified set is written in a form that does not parse** — a qualification the members share is written once after the set, before any suffix, and a range member is qualified at both ends. 2026-10-03.

* [x] **A fraction of a century or a decade is written back as the whole one** — it is not a value: ISO 8601 gives a decimal fraction to an hour, a minute or a second alone, so `20.5C` and `201.5J` are a `ParseError`, as a masked or set century is, and two digits with a fraction (`09,5`, `23.5Z`) are an hour, where the tokenizer read them as a century. 2026-10-03.

* [x] **`to_calendar/2` drops a value's qualification, metadata and tags** — the converted date keeps them (its zone too; not the calendar it was in), and a qualified year, month or day qualifies every unit of it, as a week-calendar date converts. 2026-10-03.

* [x] **A zone on a set or a recurrence's domain is dropped** — a set's zone and tags are each member's that has none (a range's at both ends), and a zone the members share is written once after the set, or after a domain's recurrence, in IXDTF's order. 2026-10-03.

* [x] **A zone on a recurrence with no start is dropped** — the suffix of `R/../P1Y/FL3M20DN[+09:00]` is kept on its rule (its zone and tags; the calendar is the rule's already), written back after the recurrence in IXDTF's order, and given to the start a `:within` window supplies, so the occurrences are zoned. Sets and domains remain, as their own item. 2026-10-03.

* [x] **A day after a group of months under a set of years** — the walk validates a group with the unit after it once the units before it are concrete, so `{2026,2028}Y2G2MU15D` is 15 March of each year, as `2026Y2G2MU15D` is 15 March. 2026-10-03.

* [x] **An unspecified year is the current Gregorian year in every calendar** — the walk takes today from `Tempo.Clock` and converts it to the value's calendar, so `X*Y[u-ca=hebrew]` is the current Hebrew year (5787 on 3 October 2026). 2026-10-03.

* [x] **A month or a year added to a day of the week that names no week is that day again** — it is an `UnanchoredError` (`Tempo.shift(~o"7K", month: 1)`, and `R3/7K/P1M`), as a day of the year with no year is; weeks, days and the time of day still step a bare day of the week. 2026-10-03.

* [x] **An unspecified month or day is stepped as its last** — a shift that reaches an unspecified unit other than the year reads it as the full mask it stands for (`X*D` as `XXD`), so it moves the block: `2026Y6MX*D` plus a day is one of 2 June to 1 July, and a shift back is no longer refused. 2026-10-03.

* [x] **The Localize lock moved to `45f252e`** — two commits on from `208353f`: a comma that is the only separator between date fields is kept (en-ZW), and the ambiguous currency strings are split into smaller functions. 2026-10-03.

* [x] **An unending recurrence with no year gives nothing in a dated window** — a start with no year is placed on the window's first day, month or year (`at/2`), a day of the week on the first such day in the window, so `R/T22H/PT1H` within 15 June is 22:00 and 23:00. 2026-10-03.

* [x] **The Calendrical and Localize locks moved** — Calendrical to `a60de7a` (composite years, Umm al-Qura and Persian dates outside their tables, `strftime/3`) and Localize to `208353f` (Hebrew-numeral years, calendar time formats, GMT offset digits, `-u-rg-` subdivisions, shared currency text). 2026-10-03.

* [x] **`Date.compare/2` orders two dates of one calendar by their fields** — Tempo orders dates by their days (`Tempo.Compare.compare_days/2`, through `Date.diff/2`, as Calendrical does) in its twelve calls, and `compare_endpoints/2` compares the values of a calendar whose year does not begin on 1 January by their days. 2026-10-03.

* [x] **A value's selection and `select/2` in a calendar of weeks** — `at_resolution/2` takes a week value to `:day` as its day of the week, so `2026YL1K1IN`, `R/../P1Y/FL25W2KN` within `~o"2026"W` and `select/2` with `~o"L2KN"` select in a calendar of weeks. 2026-10-03.

* [x] **A recurrence's selection by day of the week in a calendar of weeks** — `Tempo.RRule.Selection` resolves a week calendar's candidate in Calendrical's terms (its week the date's month) and writes the occurrences back as weeks: `R3/2026-W01-1/P1W/FL2KN` is each week's Tuesday, `R3/2026-W25-1/P1Y/FL25W2KN` week 25's. A value's selection and `select/2` remain, as their own item. 2026-10-03.

* [x] **A recurrence from a start that holds a set gives intervals whose ends hold it** — such a recurrence is one from each of the start's values (`R3/2026Y6M{1,15}D/P1M` is six occurrences); a start that holds a mask is still refused. 2026-10-03.

* [x] **A recurrence with no year that wraps its own axis** — the floor at a start with no year drops only the occurrences before the first at or after it, so `R3/T22H/PT1H` reaches 00:00; a cadence that brings such a start back to itself is a `ConversionError`. 2026-10-03.

* [x] **A count from the end under a single month is resolved before its year is known** — a day counted from the end of a month under a year that is a set, a range, a mask or unspecified is left for each year to resolve (`{2026,2027}Y2M-1D` is 28 February of each); `to_interval/2` of `X*Y2M-1D` is now a `ConversionError`. 2026-10-03.

* [x] **The Calendrical lock moved to `48f7f63`** — two commits on from `4ba5827`: composite configurations a composite cannot keep are refused, a composite year runs between its dated days, and a TODO item is rewritten. Localize is unchanged at `6f3f0364`. 2026-10-03.

* [x] **`Enum.count/1` of an interval whose ends differ in resolution** — `Tempo.Interval.Steps.count_steps/4` counts the step that starts before an end finer than the unit, so `count/1`, `at/2` and `slice/3` agree with the walk (`1985/1986-06` is 2). 2026-10-03.

* [x] **An interval with grouped ends compares wrongly** — an end written as a group, a mask or significant digits is read as the point its span starts at, in `to_interval/1`, the Allen relations, the set operations, `duration/1` and the length predicates; an end that names several spans is an `IntervalEndpointsError`. 2026-10-03.

* [x] **`from_iso8601/1` raises for a century or a decade that is not one number** — a `Tempo.ParseError` for one written with unspecified digits, as a set or a range, or with a margin of error or significant digits, wherever it is written, where the parser raised an `ArithmeticError`. 2026-10-03.

* [x] **The Calendrical lock moved to `4ba5827`** — one commit on from `b1cc801`: the years and months between a composite calendar's dates are counted from the days between them. Through Tempo nothing changes: the suite and tempo_holidays pass as before. Localize is unchanged at `6f3f0364`. 2026-10-03.

* [x] **The enumeration raises** — one lazy walk for `Enum` and for `to_interval/2`'s members, each unit read after the values before it: every unit's masks and unspecified values walk, a value or an interval that cannot be walked raises a named error (`to_interval/2` returns it), and an interval with no year is counted by its walk and walks round its axis. Of 14,817 values in a probe of every unit and shape, `Enum.take/2` raised an unnamed error for 5,725 and never returned for 1,256, and now does neither for any. 2026-10-03.

* [x] **The Calendrical lock moved to `b1cc801`** — two commits on from `41b4d45`: a year's days come from the calendar's `year/1`, a composite's dates are read and shifted in the calendar that has them, and a composite year that runs through days with no dates of their own keeps its days and weeks. Through Tempo nothing changes: the suite and the earlier probes give the same results under `41b4d45` and `5d2ff89`, and the suite and the probes of 14,817 values, 2,583 intervals and 662 sets under `5d2ff89` and `b1cc801`. Localize is unchanged at `6f3f0364`. 2026-10-03.

* [x] **A step counts from one whole number** — a day of the week that names no week spans and steps on its own axis (`Tempo.to_interval(~o"{6,7}K")` raised a `KeyError`), a step back from a value with no year borrows as a step forward carries, and a step that would count from a unit holding a set, a range or a group is a `ConversionError` where one every value takes alike is computed. An interval's or a recurrence's end that cannot be counted to is its error. 2026-10-02.

* [x] **The Calendrical lock moved to `41b4d45`** — its composite calendars count an era's days through their changes of calendar, and a `Julian.Sept1` or `Julian.Dec25` year takes the number of the Julian year it ends in: through Tempo only dates in those two calendars change (72 of 930 probes, the year's number moved by one), and the suite and the composite-calendar probes give the same results under the old lock and the new. Localize is unchanged at `6f3f0364`. 2026-10-02.

* [x] **A set's members are checked and in its calendar** — each member, each end of a range, each excluded member and each interval among them is read as a value on its own is, in the calendar the set is written for (`{2026-02-30}` is an error, `{5786-06-15,5786-07-01}[u-ca=hebrew]` two Hebrew dates); a recurrence's domain is checked and keeps its Gregorian years. `to_iso8601/1` and `inspect/1` write a set's calendar once after it and a recurrence's after its rule, and set operations take a range member. 2026-10-02.

* [x] **The Localize and Calendrical locks moved to `6f3f0364` and `6566488`** — Calendrical's `days_in_month/2` now counts a week's seven days in a calendar of weeks, which Tempo does not reach for such a calendar's values, since they hold no month: the suite and nearly 400 week-calendar probes give the same results under the old locks and the new. 2026-10-02.

* [x] **A month and a day in a week calendar** — a whole date written with them, or as a day of the year, is the Gregorian day converted, as Localize reads it (`~o"2026-06-15"W` is `~o"2026-W25-1"W`), where a value is parsed or built; anything less than a whole date, and a month placed on or selected in a week calendar's value, is a `ConversionError`. With it `at/2`, `on/2` and `extend/1` check a value in its own calendar, and `to_interval/2` and `select/2` return where they raised. 2026-10-02.

* [x] **`explain/1` names a month as its calendar does** — a Hebrew `5786-06-15` is "Adar 15, 5786" and a Persian selection "in Farvardin", the names asked of Localize; a lunisolar month with no year, which no one name fits, is given by its number ("Day 15 of month 6"). 2026-10-02.

* [x] **`explain/1` headlines a set or a group as what it names** — a set is each of its members ("June and July 2026", "The 1st and 15th of June 2026", "Weeks 25 and 27 of 2026"), a group one span ("January to March 2026"), a set of years no longer a value without one, and a set of hours its clock times. 2026-10-02.

* [x] **A year in a week calendar's `to_string/2`** — written again ("2026 AD") now that Localize asks a partial date's year of its calendar (`8a22bd22`); the locks moved to Localize `bf25a670` and Calendrical `9851306`, and it is tested. 2026-10-02.

* [x] **`explain/1` reads week values** — a week, a week date and a week calendar's values are headlined by their week ("Week 25 of 2026", "Tuesday of week 25 of 2026") and span the days they start on, a week calendar's in its own notation, wherever they bound something; a week with no year recurs. 2026-10-02.

* [x] **The Localize and Calendrical locks moved to `main`** — Localize `2a778aaa` and Calendrical `df8434a`, together; a week calendar's day reads "2026-W25-2" and a Hebrew year's last month is right ("Tishri – Elul 5786"). 2026-10-02.

* [x] **A span formatted with a skeleton** — `to_string/2` takes a skeleton or a pattern across a span's ends ("Jun 15 – 17, 2026") now that Localize does; tested, and the comment on `expandable_format?/1` corrected. 2026-10-02.

* [x] **Units with nothing above them, and the day of the year** — `O` is its own unit, `:day_of_year`, written back as `O` and never after a month; a `D` with no month reads as a day of the year where a year resolves it. 0 is refused for a day, a day of the year, a month or a week, and a bare month is bounded by `months_in_year/0`; a bare day or week has no upper bound until it has a year. 2026-10-01.

* [x] **`explain/1` describes a recurrence set** — member by member, each led by its name, and a conditional member on its own. 2026-10-01.

* [x] **What `to_string/2` renders for a value naming several spans** — a recurrence however written, a mask, group, set, selection, one-of set (as alternatives) and recurrence set render as the spans `to_interval/2` gives, joined as a list in the locale, with `:within` for one with no end; a duration keeps its fraction of a second. `to_interval/2` expands `Rn/start/end` and `Rn/duration/end` and narrows partial masks. 2026-10-01.

* [x] **`to_string/2` raises** — it returns `{:ok, string}` or `{:error, exception}` for every value it cannot render, Localize's errors included, with `to_string!/2` for the string; interpolation writes such a value in ISO 8601, or as `inspect/1` when it has no ISO 8601 form. 2026-10-01.

* [x] **`to_relative_string/2` raises** — it returns `{:ok, string}` or `{:error, exception}` for every input it cannot count from, Localize's errors included, as `to_iso8601/1` does, with `to_relative_string!/2` for the string. 2026-10-01.

* [x] **A recurrence with an end has no ISO 8601 form** — `to_iso8601/1` returns an `Iso8601EncodeError` for an RFC 5545 `UNTIL`, which ISO 8601 cannot bound a recurrence by, where it raised, wrote a form that did not parse, or wrote the end as the first occurrence's; ISO's duration/end form with a repeat rule keeps its duration. 2026-10-01.

* [x] **An ordinal weekday with several times** — units after a recurrence's selection apply to every date it picks (`FL5K2INT9H0M`, ISO 8601-2 §12.9 Example 5), and an RRULE ordinal weekday's times lower to them, so `BYDAY=2FR;BYHOUR=9,17` fires on the second Friday at both times and round-trips; beside a `BYSETPOS` the ordinal stays `:byday`. 2026-10-01.

* [x] **Cron: a step or a `*` beside a set field** — a step is the values it steps to and a `*` every value of its field, each firing one minute (a second with six or seven fields) from the first whole one at or after `:from`; ordinal weekdays count within the month, years limit both ends, and a starred day field composes with AND, as in Vixie cron. 2026-10-01.

* [x] **A time selection before its step** — documented, not changed (user): a selection picks its points in the calendar period of the cadence's unit that holds each step's start, as RFC 5545 and ISO 8601-2 §13.4 do, and a cadence of mixed units takes its period from its first unit. 2026-10-01.

* [x] **A sub-day cadence's first selected occurrence is a whole day** — a selection that only limits a recurrence keeps each step whole, as without it: `R/../PT1H/FL1KN`'s first Monday hour is an hour, two-hour and 90-minute steps keep their length, and a weekly recurrence's January weeks are weeks, where each was cut to one unit of its start. 2026-10-01.

* [x] **`shift_zone/2` writes two time-zone annotations** — `shift_zone/2`, `now/1`, `utc_now/0` and `from_elixir/1` of a `DateTime` keep the offset in the shift alone and write one annotation, `[America/New_York]`, where a second, `[-05:00]`, went stale across a change of offset; the encoder writes an offset annotation only without a zone name. 2026-10-01.

* [x] **A week date's `to_string/2`** — a week date renders as the day it names and a week, or a range of weeks, as its first and last day ("Jun 15 – 21, 2026"), where both rendered the year alone. 2026-10-01.

* [x] **A week-based calendar's ISO 8601 form** — one shape, ISO 8601's week date `[year, week, day_of_week]`, from the parser, `from_elixir/1`, `to_calendar/2`, `shift_zone/2`, a network's clock and set operations, written as ISO 8601-2's `2026Y25W2K` with its calendar; such values compare, shift, round, split and convert, and a month added to a week date is an error. 2026-09-30.

* [x] **`to_iso8601/1` writes a value's calendar** — however the value was made (`to_calendar/2`, `from_elixir/1`, `new/1`, a parse with a calendar), by the identifier that reads back as its calendar, and drops a parsed one naming another; a calendar IXDTF cannot name whose days differ from the Gregorian's is an error, and inspect names its module for an interval too. 2026-09-30.

* [x] **`shift_zone/2` keeps the value's calendar** — a value in another calendar stays in it, with its calendar annotation, tags, metadata and qualification, where it took the Gregorian wall clock and dropped the rest; a network in hours with a zoned bound in another calendar solves, where it returned an error. 2026-09-30.

* [x] **`to_relative_string/2` counts no finer than the value** — without a `:unit`, the unit Localize chooses but never one finer than the value's own, so 2027 is "next year" from July 2026 (user). 2026-09-30.

* [x] **`to_relative_string/2` counts calendar periods** — Tempo gives Localize the value where its span starts, on its own wall clock and in its own calendar and zone, and `:from` where the value's clock reads it, and Localize counts the unit's periods; Tempo's seconds per month and year are gone. 2026-09-30.

* [x] **A quarter in `to_relative_string/2`** — `unit: :quarter` and the weekday units count calendar quarters and weeks, now that Localize does; tested. 2026-09-30.

* [x] **Networks and schedules in hours** — a network in hours, minutes or seconds counts seconds on the time line (the wall clock, or UTC for zoned bounds) and shows its unit; an hour is elapsed time and a day or longer is measured in its period's zone, a day across a daylight-saving change its 23 or 25 hours. 2026-09-30.

* [x] **A network measures actual lengths** — a year or a month in a network of days is measured by calendar arithmetic from where its period can start, in its calendar, never a mean length; relation delays set the axis, a bound is the span it names, and a week-only or hour network no longer raises (user: actual lengths, 2026-09-30). 2026-09-30.

* [x] **A domain keeps what its years select** — a run keeps every occurrence its periods select, wherever a window moves it, so a window's anchor year gates it as in date-holidays, and a count counts from the domain's first period, where `R1/{…}` raised; a year in a selection limits the periods as a domain's years do (2026's week 1 Monday is 29 December 2025); the `:within` reach covers numbered weeks and a weekly period's weekdays. 2026-09-30.

* [x] **A terminal window within a value** — `2027YLL(easter)eN/-P2DN`, the two days before Easter 2027, parses and resolves as the recurrence form does. 2026-09-30.

* [x] **A week of free time under `:skipping`** — a day shifted by weeks steps free day by free day as it does by days, the weeks counted by `Calendrical.weeks_to_days/1`: `P1W` from Friday 23 April 2027 is Wednesday 5 May. 2026-09-30.

* [x] **`Interval.duration/2` raises no more** — it, `IntervalSet.duration/1` and `leap_seconds_spanned/1` return an error for an endpoint without a year, a finite recurrence, endpoints in different calendars, a value that is not an interval or a bad option; an endpoint naming a span is read from where its span starts. 2026-09-30.

* [x] **A §12.10 window from a year anchor** — a recurrence whose start names only a year walks a window that ends its selection from a day, where `R1/2026/P1Y/FLL12M19DN/P40DN` raised and `R/2026/P1Y/FLL3K4IN/P5DN` gave each year's first five days. 2026-09-30.

* [x] **`select/2` keeps metadata** — each selected member carries the metadata of the base member it came from, lazily for an open-ended span, and a set's own metadata stays with the result (user). 2026-09-29.

* [x] **Three defects the NSW school terms found** — `Interval.from/1`, `to/1` and `:through` read the day a selection picks; `shift/3` and `Math.add/2` return an error for a selection shifted by a unit it does not carry, and for arguments that are not a value and a duration, where they raised. 2026-09-29.

* [x] **The `:within` reach steps through Calendrical** — a walk's periods and an occurrence's reach step in the recurrence's own calendar, with no Gregorian day counts; an anchored recurrence reaches past the window's end too, and a Coptic two-month rule keeps its phase. 2026-09-29.

* [x] **Seven API gaps the NSW school holidays found** — holidays in `workdays/2` (`:except`, `Tempo.Workdays`); the duration predicates and `duration/1` on sets and values; `Interval.from/1` and `to/1` on a value, and `new/1`'s `:through`; `select/2` with an ISO 8601-2 selection; `at/2` and `on/2` with an interval or a selection; `:skipping` stepping days; `RecurrenceSet.filter/2`. 2026-09-29.

* [x] **`to_iso8601/1` returns a tuple, and the span and reach defects** — `{:ok, string}` or an `Iso8601EncodeError`, with `to_iso8601!/1`; sub-second ends encode; a time-of-day selection keeps its span, in iCalendar and as a §12.10 window of hours; `:within` keeps an occurrence that runs into it under a sub-day cadence or a backward window. 2026-09-29.

* [x] **Interval/recurrence unification** — `RecurrenceSet` (the definition) and `IntervalSet` (its occurrences) stay two types, the gaps closed: opaque metadata on `%Tempo{}` (`:metadata` repurposed, `:tags` for IXDTF), nested members, a set's metadata through materialisation, the duration forms in every single-interval function. 2026-09-27.

* [x] **Conditional recurrence-set members** — `RecurrenceSet.keep_when/2` and `move_when/2`, resolved in a second pass over the widened bound; a cookbook section. 2026-09-27.

* [x] **Recurrence bounds are half-open** — a bound starting mid-period reaches every period it overlaps, and anchored, unanchored and UNTIL recurrences keep only occurrences starting in the bound. 2026-09-27.

* [x] **A non-leap-year domain filter** — `c` (common year) beside `e`/`o`/`l`, for date-holidays' `09-11 in non-leap years`: `R/..c/P1Y/FL9M11DN`. 2026-09-27.

* [x] **Six recurrence defects from the tempo_holidays gate census** — `(name)e` with a weekday limit, a year-resolution anchor and a plain-`Tempo` recurrence-set member no longer raise; a domain steps a multi-year cadence and closes an open range against the bound; a window crossing the bound's year lands in it. 2026-09-24.

* [x] **Each shared grammar prefix parsed once** — a §12.10 window parses in ~3.5 ms (was ~1.2 s), a nested window in ~60 ms (was minutes), a selection recurrence in ~0.4 ms (was ~15 ms), bare dates ~2.4× faster. 2026-09-24.

* [x] **A supplied `:bound` narrows a self-bounding recurrence domain** — `R/{2020Y..2049Y}/P1Y/…` with `bound: ~o"2029Y"` yields 2029 only (it yielded all thirty years), using the same `[bound_from, bound_to)` start rule as any unanchored recurrence; domain periods outside the bound are skipped. 2026-09-24.

* [x] **Recurrence sets** — `Tempo.RecurrenceSet`, a collection of recurrence rules that converts to one `IntervalSet` against a window and composes with a diary through set algebra. Plan in [plans/recurrence-set.md](plans/recurrence-set.md). 2026-09-23.

* [x] **Consumer-extensible computed events** — `Tempo.Event.Resolver`, a behaviour registered via `config :ex_tempo, :event_resolvers`; consumer `(name)E` events resolve beside the built-ins and appear in `Tempo.Event.known/0`, unknown names yield zero occurrences. Plan in [plans/consumer-events.md](plans/consumer-events.md). 2026-09-23.

* [x] **Computed-event selections** — `(name)E`: Easter and `orthodox-easter` (Calendrical.Ecclesiastical), the equinoxes/solstices and first `new-moon` of the year (Astro), and the 24 solar terms (Calendrical, per-meridian via `Tempo.Event.date/3`). Plan in [plans/selection-extensions.md](plans/selection-extensions.md). 2026-09-22.

* [x] **ISO 8601-2 §12.10 selection with a time interval, and the `I`-as-position convergence** — windowed/nested selections (Election Day, Good Friday, the spec's worked examples) and `I` as the §12.9 position designator with `V` retired. Plan in [plans/i-position-convergence.md](plans/i-position-convergence.md). 2026-09-22.

* [x] **Materialise an unanchored recurrence against a bound alone** — a `:bound` now supplies the missing anchor, so the ISO 8601 holiday forms (`FL12M25DN`, `FL6M1K2IN`, …) project onto a year in one call at any bound resolution — year, month or day; day- and hour-resolution occurrences are correct. 2026-09-21.

* [x] **Duration parse entry point** — `Tempo.parse_duration/1` and `parse_duration!/1` over a second `defparsec :duration_only`, 17–42× faster than the general path and rejecting anything that is not a duration. 2026-09-02.

* [x] **Pluggable `IntervalSet` backends** — public `Tempo.IntervalSet.Backend` behaviour with `Backend.List`, `Backend.Tree` (balanced interval tree, ~2,900× faster stabbing on 10k members) and `Backend.Lazy` with `from_stream/2` and `Tempo.UnboundedSetError`; `Tempo.weekends/1` as an unbounded busy set. 2026-07-27.

* [x] **`Tempo.shift/3` with `skipping:`** — shifts over a busy set in gregorian UTC seconds; origin inside a busy span ejects to its edge at no cost, backward shifts are symmetric, `:year` and `:month` refuse. 2026-07-27.

* [x] **`Enum` over a recurring interval** — a bounded recurrence enumerates the sub-points of every occurrence; an unbounded one raises `UnboundedRecurrenceError`. 2026-07-15.

* [x] **What a bare un-anchored partial means** — ratified as a single abstract span on its own resolution axis; the recurring reading belongs to selections and RRULE. `:bound` day-anchoring and the certainty API hardened to match. 2026-07-15.

* [x] **`function_exported?/3` without `Code.ensure_loaded?/1`** — all 25 call sites across tempo, calendrical, localize and astro reviewed; twelve fixed. 2026-07-15.

* [x] **`Enumerable.Tempo.IntervalSet` semantics** — left as sub-point walking, with the member view as named vocabulary and a user-settable `:unit`. 2026-07-15.

* [x] **IXDTF strict mode** — `Tempo.validate_zone_offset/1` and `from_iso8601(str, strict: true)` reject an offset that disagrees with the zone; a critical zone (`[!America/New_York]`) enforces RFC 9557 §4.2 unconditionally and round-trips. 2026-07-11.

* [x] **1.0 readiness fixes** — an exponential set/group parse and an unbounded input length closed; `R10000/…/P1D` materialisation from ~6 s to ~20 ms via absolute-day arithmetic in `Tempo.Math`. 2026-07-05.

* [x] **`V` and `Q` selection designators** — ratified as permanent extensions (BYSETPOS and WKST have no ISO spelling); documented in conformance guide §5.

* [x] **Un-anchored arithmetic boundaries** — one principle, stated in `lib/math.ex` and the `Tempo.shift/2` doc: computed when invariant to the missing year, `%Tempo.RequiresAnchorError{}` otherwise, never raising.

* [x] **Selection builders consolidated** — both RRULE and cron paths build through `Tempo.RRule.Rule.to_selection/1`.

* [x] **Non-anchored time-of-day groups** — a pure time-of-day group materialises to a non-anchored interval when its carry stays within the present units; date groups still error.

* [x] **iCal zero-duration events** — punctual events materialise at `DTSTART`'s one-unit span, tagged `metadata: %{punctual: true}`, at a single construction chokepoint in `lib/ical.ex`.

* [x] **Cron AST gaps** — `W` nearest-weekday (`:bymonthday_nearest`), multi-year lists (`:byyear`), POSIX day-of-month OR day-of-week (`:bymonthday_or_byday`), and step LHS on day-of-week in cron numbering.

* [x] **Workdays and weekends** — `Tempo.weekend?/2`, `workday?/2`, `add_working_days/3`, `next_working_day/2`, `previous_working_day/2` and `working_days_in/2`, territory-aware via `Localize.Calendar.weekend/1`.

* [x] **Qualifications, explicit form and rendering** — implicit-form parsing fully §8-conformant; explicit per-component qualifiers parse; `inspect/1` and `to_iso8601/1` emit them, collapsing to the compact complete form where every component shares one qualifier.
