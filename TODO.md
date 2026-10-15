# TODO

Open work on Tempo 2.0. The design is [plans/architecture-redesign.md](plans/architecture-redesign.md): nine laws, the modules written to them, and a record of each phase as it was built (sections 12 to 20). This file tracks what is open against that design. It was rewritten on 2026-10-13; the list it replaced described the design before the rewrite and is in the git history.

An item is a defect to fix, a decision to take, or work of another kind. What an operation gives a shape of value is not listed cell by cell: `mix test --only total` holds every operation on every value of the corpus to an answer or a named error.

## Open

### Before the release

* [ ] **Calendrical 1.4 and Localize on hex.** `mix.exs` takes both from GitHub `main`; a release needs published versions. Calendrical has one behaviour that every calendar answers, `Localize.Calendar.ISO` among them by shape (Calendrical's `localize_calendar_iso_test.exs` and its laws test hold it there); `leap_month/1`, `weeks_in_month/2` and `month_week/3` left the behaviour on 2026-10-14, as nothing called them and another callback answers each.

* [ ] **`tempo_network` 0.1.0.** The companion package (`~/Development/tempo/tempo_network`) is built and its gates pass against a path dependency on this repository; it needs its own repository, and `{:ex_tempo, "~> 2.0"}` once 2.0 is on hex. It calls the hidden `Tempo.Calendar` in one file (`Tempo.Network.Calendar`), an agreed private seam for now (`plans/decisions.md`, 15), so a change to the adapter checks the companions.

* [ ] **Companions on 2.0.** `agenda`, `tempo_sql` and `tempo_holidays` take Tempo from GitHub `main` (2026-10-15), and move to `~> 2.0` once it is on hex; all three pass their gates against `2b04789`. `agenda` is ported (2026-10-15) under decisions 64 to 69. `tempo_holidays` is ported (2026-10-14) against a path dependency: its rules are built from parts, its conformance unchanged (168,186 matched, 0 mismatched), all 223 of its tests passing. `tempo_sql` is ported (2026-10-14) against a path dependency, under decisions 43 and 44: all 280 of its tests pass against Postgres, its version 1 and 2 composite rows read as 1.x meant them.

* [x] **Rule expansion against 1.6.4** (decisions 35 and 37). `bench/against_1_6_bench.exs` runs one set of cases against 1.6.4 and 2.0. On 2026-10-14, 2.0 over 1.6.4: reading text 0.03, writing 0.8, walking 0.8, relating 2.4, comparing 14 (3 µs), set operations 3, and of rule expansion weekdays 3.1, last weekdays 5.4, yearly fourth Thursdays 6.7, daily 8.7, Monday-Wednesday-Friday 8.9, hourly 11 (from 145 to 19,000 before the work). The work and what it found are in decisions 35 to 37; where 2.0 could be faster is under "Performance" below.

### Decisions for the user

Each decision is recorded in `plans/decisions.md` when it is made, with its question, its context and the answer; what it leaves to build moves to the defects and gaps below.

### Defects and gaps

* [x] **An offset with seconds is held to the minute.** Fixed: a shift made from an offset keeps its seconds (`Z-7H52M58S`), held to `DateTime` in `fixed_offset_test.exs`. It was: a `DateTime` whose offset has seconds (`-07:52:58`, a local mean time) is converted with a shift of hours and minutes, the seconds dropped, though ISO 8601-2 writes a shift with them (`Z7H33M14S`) and the reader reads one.

* [x] **`BYDAY` with numbered weekdays of several days** (`BYDAY=2MO,2WE`) is refused. Built (decision 34): a set of selections, `L{1K2I,3K2I}N`, held to `Date` in `selection_set_test.exs` and to the RRULE measure.

* [x] **A zone that changes its offset twice within six days was read as changing once, or not at all.** Fixed (decision 73): `Tempo.Zone` reads a table of each zone's changes (`Tempo.Zone.Table`), built from the database's own list of periods where it has one (`Tempo.Zone.Transitions`, known for `tz`) and by sampling where it has none, and every question of a zone is a binary search in it; the process dictionary is gone from the core. It was: offsets sampled six days apart, the same offset at both taken as the offset throughout. The case that showed it, America/Scoresbysund on 2024-03-31 in tzdata 2026d, is the `tz` library's and not IANA's: `zdump` shows one change of `isdst` at 01:00Z with no change of offset, where `tz` compiles an hour at -02:00 from 00:00Z (below, under upstream). Tempo now says what its database says there, tick by tick (`zone_table_test.exs`, `change_of_the_clock_test.exs`).

* [ ] **`tz` compiles an hour at -02:00 for America/Scoresbysund on 2024-03-31 that the IANA data does not have.** The zone line `-1:00 EU -01/+00 2024 Mar 31` ends at 00:00 local time, which at the standard offset then in force (-01:00) is 01:00Z, the moment the EU rule begins summer time; `zdump -v America/Scoresbysund` shows one change at 01:00Z, of `isdst` alone, with the offset -01:00 before and after. `Tz.PeriodsProvider.periods("America/Scoresbysund")` has three periods for the day: `+00` from 01:00Z (never the answer, listed after the next), `-02` from 00:00Z and `-01` from 01:00Z, so `DateTime.shift_zone(~U[2024-03-31 00:30:00Z], "America/Scoresbysund", Tz.TimeZoneDatabase)` is 22:30-02:00 where it is 23:30-01:00, and `DateTime.from_naive(~N[2024-03-30 22:30:00], ...)` is ambiguous between +00:00 and -02:00, offsets the zone did not have. The end of a zone line looks to be converted with the offset of the period being built (+00, summer time of the old line) rather than the standard offset. Upstream (`tz` 0.28.4, tzdata 2026d), found 2026-10-15; Tempo follows the database as it is.

* [ ] **`tz` has no public list of a zone's periods.** `Tempo.Zone.Transitions.Tz` reads `Tz.PeriodsProvider.periods/1`, which `tz` generates and marks `@moduledoc false`, guarded so that a `tz` without it falls back to sampling. A public function in `tz` (and one in `tzdata`, whose `Tzdata.periods/1` is public and could be adapted next) would make the table exact by contract. Upstream; the same gap in Elixir's `Calendar.TimeZoneDatabase`, which answers at a point and gives no period's bounds, is the reason the table exists at all.

* [ ] **A solar term of a year before 0 is a day late**: `Tempo.Event.date("qingming", -3000, Calendrical.Chinese)` is 7 April and the moment is on the 6th. `Calendrical.Lunisolar.solar_term/3` takes `trunc(moment)`, which rounds a negative day number up, where it wants `floor/1`. Upstream; rechecked against Calendrical `448f435` on 2026-10-14.

* [ ] **Text that is no calendar is read as a calendar of no events**: `Tempo.ICal.parse("hello, world")` is `{:ok, ~o"{}"}`. The `ical` library returns no error for text it cannot read. Upstream; rechecked against `ical` 3.2.0 on 2026-10-14.

* [ ] **Three Localize defects**, rechecked against Localize `9ac3e95` on 2026-10-14 and recorded in its TODO.md. A day of the month a year turns in is read back a year early: `Localize.Date.parse("March 20, 1700", calendar: Calendrical.Julian.March25, format: :long)` is `1699-13-20`, where `Localize.Date.to_string/2` wrote it from `1700-13-20`; Tempo reaches it, `Tempo.parse("March 20, 1700", calendar: Calendrical.Julian.March25)` being `1699Y13M20D`. A month that begins after its first day is not written from its year and month: `Localize.Date.to_string(%{year: 1751, month: 3, calendar: Calendrical.Reform.England}, format: :yMMM)` is an `InvalidValueError`; Tempo no longer reaches it, writing a month by its days (`Mar 25 – 31, 1751`). A fiscal date is written with its fiscal year and its Gregorian month: `Localize.Date.to_string(Date.new!(2027, 2, 10, Calendrical.FiscalYear.AU))` is "Aug 10, 2027" for 10 August 2026, so `Tempo.to_string/2` of a fiscal value from July to December names the wrong year (found 2026-10-15). Upstream.

* [x] **A zone's rules asked of a database that has none raise.** Fixed: with Elixir's UTC-only default a named zone is refused where it is given, a `Tempo.ZoneError` with reason `:no_database` (`zone_database_test.exs`). It was: `Tempo.from_iso8601("2026-06-15T09:00:00[Europe/Paris]")` raised a `MatchError` from `Tempo.Zone.asked_at_utc/2`. A zone made before the database is changed raises that error where its rules are next asked.

### Performance

Why 2.0 is slower than 1.6.4 where it is, and where it could be faster. None of it is needed for 2.0 (decision 37); each is a measurement first, against `bench/against_1_6_bench.exs`.

Done on 2026-10-15, each change commented where it is made: a set's members merged through an ordered set rather than a list scanned for the earliest; a union's duplicates compared only at one position; a span of two values not placed to be resolved; a unit's rank read from a map; `Expand.one_span?/1` without `Enum.chunk_every/4`; a reading of the clock in a zone steady through the day either side placed by its one offset. Union, intersection and difference of two sets of 100 went from 750–810 µs to 390–510 µs (3 times 1.6.4), and rule expansion improved by 5 to 15% (2.7 to 9.7 times 1.6.4).

Decision 56, on 2026-10-15: a candidate carries the extent its expansion found, through `Expand` and into `Select`'s judging of it. Rule expansion is now 2.5 to 7.9 times 1.6.4 (weekly MWF 16.8 ms, last weekday 30.3, hourly 7.3, yearly 1.7, weekdays 4.0, daily 0.2). Giving `Select.in_period/3`'s values their extents was built and reverted (decision 57): too little for what it cost `Select`'s readability. The next step is the zone, asked about 100 times in each weekly occurrence.

The zone is asked once for each stretch of one offset a walk comes to (decision 61), and plain recurrences are built with the rule walk's builder (decisions 62 and 63). A second representation of a value through the engine was measured and declined: its ceiling is about a quarter of an occurrence. Then, profiled with the time of what each function calls (2026-10-15): a value's frame was reckoned about 23 times an occurrence, `Unit.anchored?/1` walking the units three times for each, and is now answered from the first unit, the units being coarsest first; and a reading built at a position is no longer placed to see that it begins there where its clock keeps one offset about it. Rule expansion is now 2.0 to 6.4 times 1.6.4 (daily 0.18 ms, weekdays 3.2, hourly 5.5, weekly MWF 12.9, last weekday 26.2, yearly 1.6). What is left of an occurrence is work done once for each: the selection's analysis of its parts is about a tenth of it, so compiling a rule once for its walk would not pay; building, checking and placing each candidate is the rest.

`plans/reference-architecture-review.md` (2026-10-15) profiles four cases function by function and orders the moves below: a transition table per zone, one positioned span type through the engine, labels by arithmetic within a period, and a compiled day-number matcher for plain rules in front of the one engine.

* [x] **Labels asked of the calendar day by day.** Done (decision 75): a day of the month, a day of the year and a weekday are counted within the period from one question of the calendar, where its labels count its days, and asked day by day where they do not (England, September 1752). The calendar modules are 4 to 5% of a rule's profiled time; what remains is the placing of values.

* [x] **A span does not carry where it is.** Done (decision 74): `Tempo.Placed` is the one shape a span is handed on in, made by `Tempo.Spans.placed/2` as the span is made; relating and comparing two values are 1.8 times faster, the set operations a sixth faster, and rule expansion unchanged, its placings being of values.

* **A value does not carry where it is.** A `%Tempo{}` holds its units as written, and every question of where it lies (`Tempo.Spans.extent/1`) reads them again through the calendar: about 0.4 µs a value, ten times in a period of a rule (the period, the selection's test that a value lies in it, the span made of the value, its end written as a value and read back, the duplicate check, the bound). 1.6.4 expanded rules over Elixir dates and naive datetimes it held as positions. The rule walk now carries a period's extent and each occurrence's (decision 37); the general opportunity is an internal value that carries its position from where the engine builds it, written as units only when it is handed back.

* [x] **One selection engine for every rule.** Done (decision 76): `Tempo.Matcher` compiles a plain rule once to a test of a day number and is taken in front of the engine where its preconditions hold, the engine the meaning of every rule; weekly and monthly rules are now faster than 1.6.4, daily ones within a fifth of it.

* **One selection engine for every rule.** RRULE, cron, JSCalendar and ISO 8601-2 selections all lower to one selection, made in each period by containers, expansion, filters and positions. That is what gives them one meaning (zones, other calendars, sets of selections, rolls, skips); 1.6.4 had a weekday fast path, integer indices and a merge path beside its resolver. 2.0 has shortcuts only where they are exact (a named reading by arithmetic, a period of one day tested for its date). A rule could instead be compiled once into a test of a day number (a set of months, weekdays, days of the month) walked by integer arithmetic, the general engine kept for what that cannot say.

* **Every calendar question goes through the adapter.** `Tempo.Calendar` dispatches each to the calendar's module (decisions 6 and 8); the default calendar's day numbers are now answered by `Calendar.ISO` directly. Day-number arithmetic for the Gregorian calendar held inline in the walk would remove most of what is left in a date's extent.

* [x] **A zone is asked by point.** Done (decision 73): `Tempo.Zone.Table` holds each zone's changes, listed by `tz` and sampled past its list; a zoned rule in the 2040s pays `tz`'s computation of each period past its precompiled years once, as the table grows, and not at every question. Rule expansion is about a third slower than with the samples kept in the process (weekly MWF 17.6 ms from 12.9): a question of the table is 250 ns against 55 ns, asked 45 times an occurrence; the remedy is the positioned currency above, which asks fewer questions, or a table carried in the frame.

* **Lazy streams of structs.** Occurrences are made one at a time by `Stream.unfold/2`, each a new struct with keyword lists, and memory is 2 to 8 times 1.6.4's on the rule cases. Most callers take a bounded list, which could be made by a loop.

* **Comparing two values** is 3 µs (14 times 1.6.4, small in itself): each is placed on the line first. A comparison of two values of one calendar and frame written to the same units could compare the units.

## Ideas, not committed to

* [ ] **Revisit the calendar adapter.** Every calendar question goes through `Tempo.Calendar`, and `test/tempo/calendar_surface_test.exs` holds the library to it; what the adapter itself still knows (the `Calendar.ISO` table, the Gregorian for a solar term, Easter and the registry lookup by name) is left as it is for now (2026-10-14).
* [ ] **A `Tempo.Intervallic` protocol**, so that a struct of the caller's (`%Booking{check_in, check_out}`) takes part in relations and set operations without being copied into a `%Tempo{}`.

* [x] **A guide to selection**: the selector vocabulary, with `Tempo.selection/1` beside each written form. `guides/selection.md`, 2026-10-14.

* [ ] **`Table.Reader` for a set**, so that Livebook shows a set's members and their metadata as rows. The dependency was dropped with the struct it was written for.

## Done since the rewrite

* [x] The architecture written for a reader in another language, and the oracles exported as fixtures (2026-10-15; `plans/reference-architecture-review.md`, sections 3.3 and 3.4): `guides/architecture.md` gives the model as types, each algorithm in pseudo-code, the calendar and zone contracts, the errors and the cost of each operation; `test/fixtures/conformance/` holds Allen's table, the set operations, the recurrence rules, the changes of the clock and the refusals of the corpus as JSON, written by `scripts/conformance_fixtures.exs` from the oracles and read by the tests that were held to them.

* [x] Test coverage (2026-10-15): CI's coverage run (`mix test --cover --include guides --include total`) is at 92.84% against the 90% it requires, with 2,443 tests, where it was 91.70%; good enough, decided 2026-10-15. Raising it found twelve defects, fixed: a walk of a set raised where a member could not be walked; a `:locale` naming no territory raised; `Tempo.members/2` and `Tempo.to_interval/2` left a value or an interval with no year unplaced in a span window (decision 72); a finer part of a second was truncated; a margin built on a unit other than a year; a decade after a century did not finish expanding, and a year outside its decade was caught only at use (decision 71); a negative year under its decade was counted from its end; a selection's units were not held to their bounds; an endless operand beside an empty set was a `too_many_values` error; and two errors had no message. What is left uncovered is mostly error branches in `Tempo.Select`, `Tempo.Expand` and `Tempo.Spans`.
    * [x] Cron, held to a matcher written apart from the library (`test/tempo/cron_test.exs`).
    * [x] RFC 5545's own examples, read from the text of the standard (`test/tempo/rfc5545_examples_test.exs`).
    * [x] iCalendar and JSCalendar import, with the fixtures (`ical_test.exs`, `ical_availability_test.exs`, `jscalendar_test.exs`).
    * [x] Computed events, `explain/1`, reading text and profiles, conversions, intervals, territories (new files, from the lines no test ran).
    * [x] The rule tests beside the RFC's examples (`rrule/*_test.exs`, 30 files), for the cases the examples leave out: `rrule_measure_test.exs` holds 192 rules from three starts to an expander written apart from the library (`test/support/rrule_measure.ex`), itself held to the RFC's examples. It found a yearly rule of every second year that lost its interval.
    * [x] Allen's axioms (`allen_axioms_test.exs`): the composition table held to what three spans give, meeting one way, and a chain of spans that meet as one.
    * [x] The set operations held to a measure written apart (`set_operations_measure_test.exs`): every pair of sets of up to two members between five points, of days, hours, hours in two zones, days in two calendars and times of day, each answer read back with `Date` and `DateTime` and held to arithmetic on whole numbers.
    * [x] Zones: a change of the clock (`change_of_the_clock_test.exs`), twenty-one days of twelve zones held to what `DateTime` says the clock showed.
    * [x] Zones: a fixed offset (`fixed_offset_test.exs`), held to the `DateTime` and its instant.
    * [x] Zones: a day a zone left out, over the six zones that left one (`day_left_out_test.exs`), and what a zone's clock makes of a reading (`zone_validation_test.exs`), each held to `Date` and `DateTime`.
    * [x] Words: `to_string/2` and `to_relative_string/2` (`format_test.exs`, `to_relative_string_test.exs`): `words_test.exs` holds the words to what Localize says of the Elixir dates an expression covers, and a relative count to `Date`'s. It found options passed over unread, weeks and quarters counted by sevens and threes, hours across a change of the clock read off the clock, and a `:from` of another calendar counted as it stood. The unit counted in where none is asked is decision 31.
    * [x] Calendars other than `Calendar.ISO` (`other_calendars_test.exs`): a calendar of weeks, one that left days out as it changed and one whose year begins in the middle of a month, each held to Calendrical's own answers. The old files were of the old design's forms and were not carried; their questions were.
    * [x] The least-covered lines of 2026-10-14: RRULE's `UNTIL` written back (`rrule_test.exs`, which found it written with no `Z` at UTC or in a zone), cron with both day fields given as extensions (`cron_test.exs`), and ISO 8601-2's quarters, quadrimesters and semestrals held to their months (`sub_year_groupings_test.exs`). What remains uncovered is mostly error branches and cycle positions no expression reaches.
    * [x] The cases the `tempo_holidays` work added (seven commits, 22 September to 9 October 2026, about 90 tests): recurrence domains and exclusions, windows across a year, a year as a day rule's start, `Tempo.RecurrenceSet`, workdays with days off, placing, selecting, shifting past busy days, measuring and filtering. Ported by rewriting, each measured against `Date`, Calendrical or a published date; the port found and fixed twenty defects. Not carried: `Interval.new/1`'s `:through` and `Interval.from/1` of a value, which law 9 and `Tempo.to_interval/2` replace, and a thousand days off in a row as an error, since days off with an end now end.
* [x] Offsets (2026-10-14): half an hour behind UTC (`-00:30`) is read as behind, where it was read as ahead; a `DateTime` whose time zone is an offset, UTC beside an offset, or a zone no database has is read by its own offset, where the first and third were errors and the second was five hours out; a value in `[-05:00]` has a `DateTime`; "EST" in words is the shift it is.
* [x] A length on the clock that is not whole units of its resolution has the finer units that say it (2026-10-14): the half hour of a half-skipped hour is `PT30M`, where it was `PT0H`.
* [x] Decision 30 built (2026-10-14): an hour a fall-back shows in two parts is, the second time, the part the clock shows.
* [x] An hour of a zone's clock is from where the clock comes to it to where the clock leaves it (2026-10-14): thirty minutes where the clock skips half of it, ninety where it shows half of it twice. The hours of a day with such a change were each a whole hour long and ran over one another.
* [x] An interval with an open end is read as a member of a set (`{2026-06-03/..}`), as "and later" is written back; a member with several ranges is an error where it raised (2026-10-14).
* [x] Two defects (2026-10-14): a month by its name that its year lacks is refused as it is read, and an exclusion that cannot be given its spans is the error where a rule's occurrences are made (no test reaches the second: every exclusion the reader gives has spans in a window).
* [x] Decision 13 built (2026-10-14): RFC 7529's `RSCALE` and `SKIP` are read and written, with a leap month as `5L`; every decision of `plans/decisions.md` is built.
* [x] Decisions 14 and 24 built (2026-10-14), and the `WKST` of decision 13: the day a week begins on is written `[u-fw=sun]` for the whole expression, and `nq` is gone.
* [x] Decisions 16 to 18 built (2026-10-14): a rule rolls a day to a weekday of the locale's working week, written `(modified-nearest)r`; cron's `28W` to `31W` are read.
* [x] Decisions 19 and 20 built (2026-10-14): seasons have their dates, by territory for 21 to 24 and from Astro for 25 to 32.
* [x] Decision 9 built (2026-10-14): a set operation with an operand that has no end is as bounded as it makes its answer, with the corrections of decision 21.
* [x] Decisions 10 to 12 built (2026-10-14): a list selection in time order, a cron rule with no start, a `Date.Range` from `to_elixir/1`.
* [x] **A solar term on a value with no calendar** is the Gregorian calendar's, asked for by the adapter (`Tempo.Calendar.solar_term/3`), since `Localize.Calendar.ISO` has no astronomy. Decided 2026-10-14.
* [x] The redesign, phases 0 to 8 (sections 12 to 20 of the plan).
* [x] The migration guide and the changelog, from the published 1.6.4.
* [x] The golden comparison retired; the corpus kept for the totality check.
* [x] Version 2.0.0, OTP 27, the engine hidden, `### Options` on every function that takes them.
* [x] `tempo_network` ported: 225 tests, its README, its guide.
* [x] A composable builder: `Tempo.every/2`, `Tempo.selection/1`, `Tempo.one_of/1`, and the steps of `Tempo.Builder` (decisions 45 to 47), each step an expression.
* [x] Cron's `L`, `LW`, `nW`, `nL` and `n#k`.
* [x] A set with no end: refused by what needs every member, bounded by a window, read lazily by what can.
* [x] A bound on work is a refusal, never a part of the answer (`Tempo.Limit.take/2`).
* [x] RFC 5545 conformance from the standard's text: a numbered weekday beside times of day, a nested selection that selects nothing, `UNTIL` as an inclusive bound, `WKST` where it changes nothing.
* [x] A span or a cadence of no length is refused (`2026-06-01/P0D`, `R3/2026-06-01/P0D` did not return).
* [x] `Tempo.ICal.available/2` reads a window with no zone on the calendar's clock, as `parse/2` does.
* [x] `Tempo.parse/2` holds a locale's words to the `:profile`.
