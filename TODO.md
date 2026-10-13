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
    * [ ] The rule tests beside the RFC's examples (`rrule/*_test.exs`, 30 files), for the cases the examples leave out.
    * [x] Allen's axioms (`allen_axioms_test.exs`): the composition table held to what three spans give, meeting one way, and a chain of spans that meet as one.
    * [ ] The set operations held to a measure written apart (`set_operations_measure_test.exs`).
    * [x] Zones: a change of the clock (`change_of_the_clock_test.exs`), twenty-one days of twelve zones held to what `DateTime` says the clock showed.
    * [ ] Zones: a day a zone left out, a fixed offset, and what a zone refuses (`day_left_out_test.exs`, `fixed_offset_test.exs`, `zone_validation_test.exs`).
    * [ ] Words: `to_string/2` and `to_relative_string/2` (`format_test.exs`, `to_relative_string_test.exs`).
    * [ ] Calendars other than `Calendar.ISO`: weeks, composites, a year that starts in March (`week_calendar_test.exs`, `composite_calendar_test.exs`, `year_start_test.exs`).

* [ ] **Calendrical 1.4 and Localize on hex.** `mix.exs` takes both from GitHub `main`; a release needs published versions. Calendrical has one behaviour that every calendar answers, `Localize.Calendar.ISO` among them by shape (Calendrical's `localize_calendar_iso_test.exs` and its laws test hold it there); `leap_month/1`, `weeks_in_month/2` and `month_week/3` left the behaviour on 2026-10-14, as nothing called them and another callback answers each.

* [ ] **`tempo_network` 0.1.0.** The companion package (`~/Development/tempo/tempo_network`) is built and its gates pass against a path dependency on this repository; it needs its own repository, and `{:ex_tempo, "~> 2.0"}` once 2.0 is on hex. It calls the hidden `Tempo.Calendar` in one file (`Tempo.Network.Calendar`), an agreed private seam for now (`plans/decisions.md`, 15), so a change to the adapter checks the companions.

* [ ] **Companions on 2.0.** `tempo_sql` and `tempo_holidays` move to `~> 2.0` once it is on hex. `tempo_holidays` builds its rules with `Tempo.every/2` and `Tempo.selection/1`, where it wrote text to be read.

* [ ] **Performance is not measured.** The reader, the walk, the set operations and the rule engine have no benchmarks against 1.6.4 (`attic/bench` holds the old ones). The reader no longer has a fast path for plain forms; whether it needs one is a measurement.

### Decisions for the user

Each decision is recorded in `plans/decisions.md` when it is made, with its question, its context and the answer; what it leaves to build moves to the defects and gaps below.

### Defects and gaps

* [ ] **An hour a fall-back shows in two parts.** The Chatham Islands' clock goes from 03:45 back to 02:45 (5 April 2026), so the hour from 02:00 is shown for an hour, and an hour later for fifteen minutes more. The walk steps through both, and the value of the second (`T2H` with the offset it then has) is given the whole hour from 02:00 at that offset, forty-five minutes of which the clock showed as 03:00. It is the one day left out of `change_of_the_clock_test.exs`. To decide: what such a value is.

* [ ] **`BYDAY` with numbered weekdays of several days** (`BYDAY=2MO,2WE`) is refused.

* [ ] **A solar term of a year before 0 is a day late**: `Tempo.Event.date("qingming", -3000, Calendrical.Chinese)` is 7 April and the moment is on the 6th. Calendrical's `solar_term/3` takes `trunc/1` of the moment where it wants `floor/1`. Upstream.

* [ ] **Text that is no calendar is read as a calendar of no events**: `Tempo.ICal.parse("hello, world")` is `{:ok, ~o"{}"}`. The `ical` library returns no error for text it cannot read. Upstream.

* [ ] **Two Localize defects** found before the rewrite and not rechecked since: a month that begins after its first day (`Calendrical.Reform.England`, March 1751) is not written from its year and month, and a day of the month a year turns in (`Calendrical.Julian.March25`) is read back a year early.

### Ideas, not committed to

* [ ] **Revisit the calendar adapter.** Every calendar question goes through `Tempo.Calendar`, and `test/tempo/calendar_surface_test.exs` holds the library to it; what the adapter itself still knows (the `Calendar.ISO` table, the Gregorian for a solar term, Easter and the registry lookup by name) is left as it is for now (2026-10-14).
* [ ] **A `Tempo.Intervallic` protocol**, so that a struct of the caller's (`%Booking{check_in, check_out}`) takes part in relations and set operations without being copied into a `%Tempo{}`.

* [ ] **A guide to selection**: the selector vocabulary, with `Tempo.selection/1` beside each written form.

* [ ] **`Table.Reader` for a set**, so that Livebook shows a set's members and their metadata as rows. The dependency was dropped with the struct it was written for.

## Done since the rewrite

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
