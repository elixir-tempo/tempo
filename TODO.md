# TODO

Open work on Tempo 2.0. The design is [plans/architecture-redesign.md](plans/architecture-redesign.md): nine laws, the modules written to them, and a record of each phase as it was built (sections 12 to 20). This file tracks what is open against that design. It was rewritten on 2026-10-13; the list it replaced described the design before the rewrite and is in the git history.

An item is a defect to fix, a decision to take, or work of another kind. What an operation gives a shape of value is not listed cell by cell: `mix test --only total` holds every operation on every value of the corpus to an answer or a named error.

## Open

### Before the release

* [ ] **Test coverage has little headroom.** CI's coverage run (`mix test --cover --include guides --include total`: the suite, the guides and the totality check, 1,340 tests on 2026-10-14) is at 90.12% against the 90% it requires. The Gregorian calendars of other week starts are left out of the measure, being Calendrical's code. The suite it replaced was 217 files. Each was run against the new library on 2026-10-13 (`git show a43b944:test`): 52 still compile, and 775 of their 1,478 tests pass, so the old tests are not carried over as they stand, and what is worth carrying is their cases, each rewritten for the new API and checked against the standard it cites rather than the old answer. Every file ported so far found a defect.
    * [x] Cron, held to a matcher written apart from the library (`test/tempo/cron_test.exs`).
    * [x] RFC 5545's own examples, read from the text of the standard (`test/tempo/rfc5545_examples_test.exs`).
    * [x] iCalendar and JSCalendar import, with the fixtures (`ical_test.exs`, `ical_availability_test.exs`, `jscalendar_test.exs`).
    * [x] Computed events, `explain/1`, reading text and profiles, conversions, intervals, territories (new files, from the lines no test ran).
    * [x] The rule tests beside the RFC's examples (`rrule/*_test.exs`, 30 files), for the cases the examples leave out: `rrule_measure_test.exs` holds 162 rules from three starts to an expander written apart from the library (`test/support/rrule_measure.ex`), itself held to the RFC's examples. It found a yearly rule of every second year that lost its interval.
    * [x] Allen's axioms (`allen_axioms_test.exs`): the composition table held to what three spans give, meeting one way, and a chain of spans that meet as one.
    * [x] The set operations held to a measure written apart (`set_operations_measure_test.exs`): every pair of sets of up to two members between five points, of days, hours, hours in two zones, days in two calendars and times of day, each answer read back with `Date` and `DateTime` and held to arithmetic on whole numbers.
    * [x] Zones: a change of the clock (`change_of_the_clock_test.exs`), twenty-one days of twelve zones held to what `DateTime` says the clock showed.
    * [x] Zones: a fixed offset (`fixed_offset_test.exs`), held to the `DateTime` and its instant.
    * [x] Zones: a day a zone left out, over the six zones that left one (`day_left_out_test.exs`), and what a zone's clock makes of a reading (`zone_validation_test.exs`), each held to `Date` and `DateTime`.
    * [x] Words: `to_string/2` and `to_relative_string/2` (`format_test.exs`, `to_relative_string_test.exs`): `words_test.exs` holds the words to what Localize says of the Elixir dates an expression covers, and a relative count to `Date`'s. It found options passed over unread, weeks and quarters counted by sevens and threes, hours across a change of the clock read off the clock, and a `:from` of another calendar counted as it stood. The unit counted in where none is asked is decision 31.
    * [x] Calendars other than `Calendar.ISO` (`other_calendars_test.exs`): a calendar of weeks, one that left days out as it changed and one whose year begins in the middle of a month, each held to Calendrical's own answers. The old files were of the old design's forms and were not carried; their questions were.

* [ ] **Calendrical 1.4 and Localize on hex.** `mix.exs` takes both from GitHub `main`; a release needs published versions. Calendrical has one behaviour that every calendar answers, `Localize.Calendar.ISO` among them by shape (Calendrical's `localize_calendar_iso_test.exs` and its laws test hold it there); `leap_month/1`, `weeks_in_month/2` and `month_week/3` left the behaviour on 2026-10-14, as nothing called them and another callback answers each.

* [ ] **`tempo_network` 0.1.0.** The companion package (`~/Development/tempo/tempo_network`) is built and its gates pass against a path dependency on this repository; it needs its own repository, and `{:ex_tempo, "~> 2.0"}` once 2.0 is on hex. It calls the hidden `Tempo.Calendar` in one file (`Tempo.Network.Calendar`), an agreed private seam for now (`plans/decisions.md`, 15), so a change to the adapter checks the companions.

* [ ] **Companions on 2.0.** `tempo_sql` and `tempo_holidays` move to `~> 2.0` once it is on hex. `tempo_holidays` builds its rules with `Tempo.every/2` and `Tempo.selection/1`, where it wrote text to be read.

* [x] **Rule expansion against 1.6.4** (decisions 35 and 37). `bench/against_1_6_bench.exs` runs one set of cases against 1.6.4 and 2.0. On 2026-10-14, 2.0 over 1.6.4: reading text 0.03, writing 0.8, walking 0.8, relating 2.4, comparing 14 (3 µs), set operations 3, and of rule expansion weekdays 3.1, last weekdays 5.4, yearly fourth Thursdays 6.7, daily 8.7, Monday-Wednesday-Friday 8.9, hourly 11 (from 145 to 19,000 before the work). The work and what it found are in decisions 35 to 37; where 2.0 could be faster is under "Performance" below.

### Decisions for the user

Each decision is recorded in `plans/decisions.md` when it is made, with its question, its context and the answer; what it leaves to build moves to the defects and gaps below.

### Defects and gaps

* [x] **An offset with seconds is held to the minute.** Fixed: a shift made from an offset keeps its seconds (`Z-7H52M58S`), held to `DateTime` in `fixed_offset_test.exs`. It was: a `DateTime` whose offset has seconds (`-07:52:58`, a local mean time) is converted with a shift of hours and minutes, the seconds dropped, though ISO 8601-2 writes a shift with them (`Z7H33M14S`) and the reader reads one.

* [x] **`BYDAY` with numbered weekdays of several days** (`BYDAY=2MO,2WE`) is refused. Built (decision 34): a set of selections, `L{1K2I,3K2I}N`, held to `Date` in `selection_set_test.exs` and to the RRULE measure.

* [ ] **A solar term of a year before 0 is a day late**: `Tempo.Event.date("qingming", -3000, Calendrical.Chinese)` is 7 April and the moment is on the 6th. Calendrical's `solar_term/3` takes `trunc/1` of the moment where it wants `floor/1`. Upstream.

* [ ] **Text that is no calendar is read as a calendar of no events**: `Tempo.ICal.parse("hello, world")` is `{:ok, ~o"{}"}`. The `ical` library returns no error for text it cannot read. Upstream.

* [ ] **Two Localize defects** found before the rewrite and not rechecked since: a month that begins after its first day (`Calendrical.Reform.England`, March 1751) is not written from its year and month, and a day of the month a year turns in (`Calendrical.Julian.March25`) is read back a year early.

### Performance

Why 2.0 is slower than 1.6.4 where it is, and where it could be faster. None of it is needed for 2.0 (decision 37); each is a measurement first, against `bench/against_1_6_bench.exs`.

* **A value does not carry where it is.** A `%Tempo{}` holds its units as written, and every question of where it lies (`Tempo.Spans.extent/1`) reads them again through the calendar: about 0.4 µs a value, ten times in a period of a rule (the period, the selection's test that a value lies in it, the span made of the value, its end written as a value and read back, the duplicate check, the bound). 1.6.4 expanded rules over Elixir dates and naive datetimes it held as positions. The rule walk now carries a period's extent and each occurrence's (decision 37); the general opportunity is an internal value that carries its position from where the engine builds it, written as units only when it is handed back.

* **One selection engine for every rule.** RRULE, cron, JSCalendar and ISO 8601-2 selections all lower to one selection, made in each period by containers, expansion, filters and positions. That is what gives them one meaning (zones, other calendars, sets of selections, rolls, skips); 1.6.4 had a weekday fast path, integer indices and a merge path beside its resolver. 2.0 has shortcuts only where they are exact (a named reading by arithmetic, a period of one day tested for its date). A rule could instead be compiled once into a test of a day number (a set of months, weekdays, days of the month) walked by integer arithmetic, the general engine kept for what that cannot say.

* **Every calendar question goes through the adapter.** `Tempo.Calendar` dispatches each to the calendar's module (decisions 6 and 8); the default calendar's day numbers are now answered by `Calendar.ISO` directly. Day-number arithmetic for the Gregorian calendar held inline in the walk would remove most of what is left in a date's extent.

* **A zone is asked by point.** `Calendar.TimeZoneDatabase` answers an offset at an instant and gives no period's bounds, so Tempo keeps what it learns at points six days apart and bounds a change as it is asked about (`Tempo.Zone`). A database that gave its periods (as `tz`'s own list does) would answer a span at once. `tz` also computes each period past its precompiled years afresh, which is most of what a zoned rule in the 2040s costs.

* **Lazy streams of structs.** Occurrences are made one at a time by `Stream.unfold/2`, each a new struct with keyword lists, and memory is 2 to 8 times 1.6.4's on the rule cases. Most callers take a bounded list, which could be made by a loop.

* **Comparing two values** is 3 µs (14 times 1.6.4, small in itself): each is placed on the line first. A comparison of two values of one calendar and frame written to the same units could compare the units.

## Ideas, not committed to

* [ ] **Revisit the calendar adapter.** Every calendar question goes through `Tempo.Calendar`, and `test/tempo/calendar_surface_test.exs` holds the library to it; what the adapter itself still knows (the `Calendar.ISO` table, the Gregorian for a solar term, Easter and the registry lookup by name) is left as it is for now (2026-10-14).
* [ ] **A `Tempo.Intervallic` protocol**, so that a struct of the caller's (`%Booking{check_in, check_out}`) takes part in relations and set operations without being copied into a `%Tempo{}`.

* [ ] **A guide to selection**: the selector vocabulary, with `Tempo.selection/1` beside each written form.

* [ ] **`Table.Reader` for a set**, so that Livebook shows a set's members and their metadata as rows. The dependency was dropped with the struct it was written for.

## Done since the rewrite

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
* [x] A composable builder: `Tempo.every/2`, `Tempo.selection/1`, `Tempo.one_of/1`.
* [x] Cron's `L`, `LW`, `nW`, `nL` and `n#k`.
* [x] A set with no end: refused by what needs every member, bounded by a window, read lazily by what can.
* [x] A bound on work is a refusal, never a part of the answer (`Tempo.Limit.take/2`).
* [x] RFC 5545 conformance from the standard's text: a numbered weekday beside times of day, a nested selection that selects nothing, `UNTIL` as an inclusive bound, `WKST` where it changes nothing.
* [x] A span or a cadence of no length is refused (`2026-06-01/P0D`, `R3/2026-06-01/P0D` did not return).
* [x] `Tempo.ICal.available/2` reads a window with no zone on the calendar's clock, as `parse/2` does.
* [x] `Tempo.parse/2` holds a locale's words to the `:profile`.
