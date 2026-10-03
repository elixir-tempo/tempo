# TODO

Open work on Tempo. The analysis behind each item, and the record of every decision taken on the way to 1.0, is in [plans/design-notes.md](plans/design-notes.md). Open items are grouped and ordered by priority, correctness first and conformance second (reviewed 2026-10-03).

## Open

### Correctness

* [ ] **A group of a set has no span for each group** — `to_interval/2` and `Enum` are a `ConversionError` for a value holding one (`2026Y{1,2}G3MU`, the first and second groups of three months), where they could give a span for each group. The functions that need one value return the same error since 2026-10-03. Found 2026-10-02.

* [ ] **`Tempo.extend/2` raises** — for a value at microsecond precision 6 it raises the `ArgumentError` the enumeration documents (`Tempo.extend(~o"2026-06-15T10:30:45.123456")`), where a function that returns tuples returns one. Found 2026-10-03.

* [ ] **`Enum.count/1` and `Enum.member?/2` of an interval with no end never return** — `Enum.count(~o"2026Y/..")` walks for ever, where a lazy interval set refuses with an `UnboundedSetError`. Found 2026-10-03.

* [ ] **`to_interval/2` of a partly masked day straight after a year says the value has no year** — `~o"2026Y3XD"` returns an `UnanchoredError` ("`~o"2026Y3XD"` has none"), where its walk is the days of 2026 the value names. An unspecified one (`~o"2026YX*D"`) is the year since 2026-10-03, as `2026YXXXD` is. Found 2026-10-03.

* [ ] **An interval or a recurrence from a masked start, written with a duration, keeps the mask in its ends** — `Tempo.to_interval(~o"2026Y6MXXD/P1M")` is `2026Y6MXXD/7MXXD`, and so for an unspecified day (`X*D`), a partly masked one (`1XD`) and each occurrence of `R3/2026Y6MXXD/P1M`, where an interval written with two ends is read as points (`2026Y6M/7M`): `Tempo.overlaps?/2` with 15 June is false, the intersection is empty and `Tempo.to_string/2` raises a `FunctionClauseError`. Found 2026-10-03.

* [ ] **An unspecified year is no point to measure from** — `Tempo.duration(~o"X*Y12M31D")` is `P0D`, `Tempo.duration(~o"X*Y6M")` and `Tempo.to_relative_string(~o"X*Y12M31D")` raise a `FunctionClauseError`, and `Tempo.to_interval(~o"X*Y")` is `X*Y/X*Y`, where a value with no year is an `UnanchoredError`. A mask or an unspecified unit under one (`X*Y6MX*D`) is a `ConversionError` that names no value. Found 2026-10-03.

* [ ] **The walk of an interval from an unspecified month or day steps it as its last value** — `Enum.count(~o"2026Y6MX*D/P1M")` is 32, the start and then July's days, where a start written as a mask (`2026Y6MXXD/P1M`) is a `ConversionError`, as a walk steps from one point. Found 2026-10-03.

* [ ] **The days of a February with no year have two answers** — 29 written `2MX*D` or `2M{1..-1}D` or left to the walk of `2M`, as validation accepts a 29th that some year has, and an `UnanchoredError` written `2MXXD`, as a mask wants every candidate to fit the shortest month, so `XXMXXD` yields January and raises at February (`to_interval/2` of `2MXXD` is the month, `2M/3M`). The months of a year with none split the other way: `X*M` and `XXM` are the twelve the Gregorian calendar always has, `{1..-1}M` and `-1M` an error. Decide one rule. Found 2026-10-03.

* [ ] **A set none of whose members exists is empty** — `Enum.to_list(~o"{2,6}M31D")` is `[]` and `to_interval/2` an empty set, where a mask no value matches (`1985-02-3X`) is an `InvalidDateError`. Decide whether it is an error. Found 2026-10-03.

* [ ] **A range written backwards in a set** — `{2026-06-20..2026-06-15}` parses and converts to nothing, where an interval written so is an `IntervalEndpointsError`. Decide whether it is an error. Found 2026-10-02.

### Conformance and completeness

* [ ] **Three §12 selection parses** — `2018Y9MTLT8H20MN3I` does not parse, `FL1KT10H0M0S1IN` misreads `0S1`, and `{1,3}K1I` merges where ISO 8601-2 §12.11.3 example 2 distributes.

* [ ] **An interval's end of a day alone reads as a century** — `2026-06-15/20` is `2026-06-15/21G100YU`, the two digits read as a century, where `2026-06-15/07-20`, `2026-06/08` and `2026-06-15T10:00/11:00` take the units the end leaves out from the start. ISO 8601-1 §5.5.1 allows the omission "provided that the resulting expression is unambiguous": decide whether two digits after a whole date are its day. Found 2026-10-02.

* [ ] **§12.10 window shorter than a day** — `FL11MLL1K1IN/PT12HN1K1IN` (and `/P0DN…`) walks `[lo, lo - 1]`, the anchor and the day before, as `Date.range/2` infers for a reversed range (with a runtime deprecation warning before the day-number walk replaced it). Decide the semantics — no day, or the anchor day whose start the window contains — and test it.

* [ ] **Sets the parser does not read** — several intervals in the extended format (`{2020/2021,2023/2024}`, where `{2020Y/2021Y,2023Y/2024Y}` parses) and a qualified member (`{2026-06-15?,2026-06~}`). Found 2026-10-02.

* [ ] **Week-of-month selections, and calendar-aware RRULE `BYWEEKNO`** — parse `2026Y6M2W` ("2nd week of June", a positional `W` after a month) and materialise it via `Calendrical.week_of_month/3`; and replace the hard-coded ISO week walk still used by RRULE `BYWEEKNO` with Calendrical's calendar-aware functions. Month and native week-of-year selections are done. Plan in [plans/recurrence-selection-resolution.md](plans/recurrence-selection-resolution.md).

* [ ] **Set operations across a week calendar's resolutions** — `Tempo.difference(~o"2026"W, ~o"2026-W25"W)` is a `ResolutionError` ("Cannot express … as a month-axis calendar date"), in `Calendrical.ISOWeek` and `Calendrical.NRF` alike. Found 2026-10-02.

* [ ] **A month in a calendar of weeks, read over the value's own span** — a month, a day of one or a day of the year placed on (`at/2`, `on/2`) or selected in (`select/2`, a recurrence) a week calendar's value is a `ConversionError`, since reading the value's year as the Gregorian year lands outside it (30 December on the ISO week year 2024 is in 2025, and January on the NRF year 2026 is January 2027). Decide whether they should be the Gregorian dates within the value's span, June of a week year a span of week dates, and what a week year's January is when it holds days of two. Found 2026-10-02.

* [ ] **Traditional months that are sets or masks** — `2026Y{1,2}m` parses as a mask (`traditional_month: {:mask, [[1..2]]}`) and a masked one (`1Xm`) is a `ConversionError` from `Enum` and `to_interval/2`: nothing lists the traditional months a year has, which is Calendrical's to answer. Found 2026-10-03.

* [ ] **A shift does not reach each value of a set** — a shift that would count from a unit holding several values is a `ConversionError` (`~o"2026Y6M{1,15}D"` plus a day, `~o"2026Y{6,7}M"` plus a month), where each value it names could be shifted and the results gathered. Decide the result: a set, an interval set as a disjoint mask gives, or the value itself where it can hold them (`2026Y6M{2,16}D`). Found 2026-10-02.

### Errors and API

* [ ] **An impossible date's error names too little** — `Tempo.on(~o"2M29D", ~o"2027")` returns an `InvalidDateError` with only its reason ("29 is not valid. The valid values are 1..28"), naming no year, month or calendar.

* [ ] **An open-start window's error** — `within: ~o"../2027"` returns an `IntervalEndpointsError` about including an open interval in a set: correct, but it should say that a window needs a start.

* [ ] **`Schedule.task/3`'s `:within` is a pair** — it takes a `{from, to}` tuple, where every other `:within` takes a Tempo value or an interval.

* [ ] **`explain/1` words a window of hours in ISO 8601** — `Tempo.explain(~o"R/2027-01-01/P1D/FLLT22HN/PT4HN")` says "the PT4H window from at 22:00" where it means the four hours from 22:00: `window_phrase/2` in `lib/explain.ex` words only a window of days or weeks, and a time-of-day selection's noun carries its "at".

* [ ] **Explain weekday sets by name** — `explain/1` reads `{6..7}K` as "on a weekday [6..7]"; it should read "on a Saturday or Sunday", now that holiday recurrences carry weekday limits routinely.

* [ ] **A mask with no unit before it names no value in its error** — `Tempo.to_interval/2` of `~o"XXM"`, `~o"X*M"` or `~o"TX*H"` returns a `ConversionError` whose `value` is `nil` ("Cannot convert a masked Tempo with no un-masked coarser unit to an interval"). Found 2026-10-03.

### Performance

* [ ] **A never-matching selector walks the whole horizon** — `Tempo.select/2` over an open-ended span walks a thousand years of periods before a selector that never matches ends: 30 ms of years, 0.2 s of months, about 10 s of days, minutes of hours. An index selector on a fixed-range unit could end after its first empty period, a daylight-saving gap day aside.

* [ ] **Converting a week date costs 220 µs** — `to_interval/2` of `2026Y{1..-1}W{1,3}KT10HX*M`, 6,360 members, takes 1.4 s where as many calendar dates take 60 ms: validating a week date walks the year's week starts (`Tempo.Validation.date_from_iso_week/4`). Listing a year mask before walking it costs the same way: `Enum.take(~o"XXXX-XX-XX", 100)` takes 2.9 ms. Found 2026-10-03.

* [ ] **Conditional first pass walks whole periods** — it widens the bound by the conditions' reach, and the walk covers every period the widened bound touches, so a ±1-day bridge crossing both year ends materialises three years: Japan's holiday set takes 55 ms a year with its bridge, 25 ms without. Widen only where a condition reaches past the bound (the bridge's days, a move's search back from the bound's start).

* [ ] **Parser cost by shape** — bare dates still pay the backtracking tax: `tokenize/1` takes ~360 µs for `2026-06-15` and ~430 µs for `20260615`, against ~40 µs for `2026Y6M15D` (measured 2026-09-24). Take a shape histogram of a real consumer's calls; if it is mostly dates, choice ordering in the single `defparsec :iso8601` entry point is the whole story. Any hand-rolled scanner must be conservative and differentially tested against the general parser.

### Features

* [ ] **`Tempo.Intervallic` protocol** — let user-defined structs such as `%Booking{check_in, check_out}` take part in Allen comparisons and set operations without being copied into `%Tempo.Interval{}`; default implementations for `Tempo.Interval`, `Tempo` and single-member `Tempo.IntervalSet`.

* [ ] **A composable builder** — an API between `Tempo.new/1` (flat components) and `Tempo.from_iso8601/1` (a string) in complexity, building a value from composable sub-expressions with human names — `selection`, `recur`, windows, domains, exclusions, events — nesting freely, so programs (tempo_holidays among them) construct recurrences structurally instead of interpolating ISO 8601 strings and re-parsing them.

* [ ] **Lazy backend follow-ups** — splicing a lazy set into a busy list (needs a sorted stream merge), lazy set algebra (the research project under Deferred), and holiday generator sources. The refusal semantics must hold: an answer that needs an unbounded walk without a `:within` window refuses rather than hangs.

* [ ] **Create a glossary guide** — a guide that tables every term Tempo uses (span, window, occurrence, resolution, floating, zoned, anchored, …) and defines it, so it doubles as the reference future development checks its vocabulary against (user, 2026-09-28). The decisions in [plans/vocabulary.md](plans/vocabulary.md) are its starting point.

* [ ] **Workday adjustments: following, preceding and their modified forms** — the date-roll conventions of financial contracts: a day when it is a workday, otherwise the next (or the previous) one, and the modified forms that turn back when the adjusted day leaves the month. `nearest_workday/2` and `next_workday/2` are different rules; found comparing Tempo with bizdays' ANBIMA calendar, 2026-10-03. Analysis in [plans/anbima-calendar.md](plans/anbima-calendar.md).

### Release and housekeeping

* [ ] **Livebooks install 2.0 at the release** — `getting-started`, `tempo_tour`, `scheduling-workbook` and `uncertain-dates-workbook` install `{:ex_tempo, "~> 1.6"}` and the Melbourne deck `~> 1.6.3`, while their code uses the 2.0 names: at the 2.0.0 release each installs `~> 2.0`, as `everyday-holidays` already does.

* [ ] **`rescue` in the library** — `lib/ical.ex` (`parse/2`, `available/2`, errors from the `ical` parser), `lib/inspect.ex` (Localize's calendar encoding) and `lib/iso8601/parser.ex` rescue exceptions where the rest of Tempo passes tagged tuples.

* [ ] **Coverage to 90%** — the CI lint row runs plain `mix test` until coverage reaches the default 90% threshold, then takes the reference workflow's `mix test --cover`. 85.5% today (2026-09-27) with the existing `ignore_modules`; `mix test --cover` lists the modules below it.

* [ ] **`ClockTest` timing** — "process-local override does not leak to peer processes" failed once under load (passing in isolation and on re-runs): `assert_receive`'s default 100 ms timeout is short on a busy machine.

## In progress

* [ ] **Vocabulary for 2.0** — one meaning per word and one word per meaning across Tempo and tempo_holidays: `:within` for `:bound`, "anchor" in one sense, no public "materialise", `Tempo.Allen` beside everyday predicates, `datetime`, "workday". Every decision is taken; the tasks are in [plans/vocabulary.md](plans/vocabulary.md). Fifteen of its sixteen tasks have landed, through tempo_holidays and the real-world livebook (`livebook/everyday-holidays.livemd`, and its tempo_holidays copy); `tempo_sql`'s move to `~> 2.0` remains, once 2.0.0 is on hex.

## Blocked

* [ ] **A week calendar's week in `to_string/2`** — a week in a calendar of weeks reads "2026-W25", and a range of them "2026-W25 – 2026-W26" (user, 2026-10-02), where it is its first and last day today, "2026-W25-1 – 2026-W25-7". Blocked on Localize writing a year and a week in the calendar's notation, the first Open item of its `TODO.md`: `Localize.Date.to_string(%{year: 2026, month: 25, calendar: Calendrical.ISOWeek})` is "M06 2026 AD".

## Deferred

* [ ] **Set algebra over open-ended windows** — a research project for later (user, 2026-09-28): how far union, intersection, difference, complement and the predicates go on the lazy sets an open-ended window gives, a test of the whole algebra. Questions in [plans/open-ended-set-algebra.md](plans/open-ended-set-algebra.md).

* [ ] **`Calendar.ISO`'s week numbers follow the locale in Localize** — in Localize's next commit after `9fa075f5`, `Y`, `w` and `W` for a `Calendar.ISO` value are the locale's weeks (1 January 2027 is in week 1 of 2027 in `en`, week 53 of 2026 in `de`), ISO 8601's only where the locale's week data is Monday and four days or with `-u-ca-iso8601`. Tempo passes no week pattern to Localize today, so nothing changes until it does. Noted from the Localize session.

## Done

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
