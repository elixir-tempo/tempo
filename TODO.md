# TODO

Open work on Tempo 2.0. The design is [plans/architecture-redesign.md](plans/architecture-redesign.md): nine laws, the modules written to them, and a record of each phase as it was built (sections 12 to 20). This file tracks what is open against that design. It was rewritten on 2026-10-13; the list it replaced described the design before the rewrite and is in the git history.

An item is a defect to fix, a decision to take, or work of another kind. What an operation gives a shape of value is not listed cell by cell: `mix test --only total` holds every operation on every value of the corpus to an answer or a named error.

## Open

### Before the release

* [ ] **Test coverage has little headroom.** CI's coverage run (`mix test --cover --include guides --include total`: the suite, the guides and the totality check, 1,227 tests) is at 90.19% against the 90% it requires, and the suite on its own (`mix test`, 1,194 tests in 38 files) is near 83%. The suite it replaced was 217 files. Each was run against the new library on 2026-10-13 (`git show a43b944:test`): 52 still compile, and 775 of their 1,478 tests pass, so the old tests are not carried over as they stand, and what is worth carrying is their cases, each rewritten for the new API and checked against the standard it cites rather than the old answer. Every file ported so far found a defect.
    * [x] Cron, held to a matcher written apart from the library (`test/tempo/cron_test.exs`).
    * [x] RFC 5545's own examples, read from the text of the standard (`test/tempo/rfc5545_examples_test.exs`).
    * [x] iCalendar and JSCalendar import, with the fixtures (`ical_test.exs`, `ical_availability_test.exs`, `jscalendar_test.exs`).
    * [x] Computed events, `explain/1`, reading text and profiles, conversions, intervals, territories (new files, from the lines no test ran).
    * [ ] The rule tests beside the RFC's examples (`rrule/*_test.exs`, 30 files), for the cases the examples leave out.
    * [ ] Allen's axioms as properties (`allen_axioms_test.exs`), and the set operations held to a measure written apart (`set_operations_measure_test.exs`).
    * [ ] Zones: a change of the clock, a day a zone left out, a fixed offset (`change_of_the_clock_test.exs`, `day_left_out_test.exs`, `fixed_offset_test.exs`, `zone_validation_test.exs`).
    * [ ] Words: `to_string/2` and `to_relative_string/2` (`format_test.exs`, `to_relative_string_test.exs`).
    * [ ] Calendars other than `Calendar.ISO`: weeks, composites, a year that starts in March (`week_calendar_test.exs`, `composite_calendar_test.exs`, `year_start_test.exs`).

* [ ] **Calendrical 1.4 and Localize on hex.** `mix.exs` takes both from GitHub `main`; a release needs published versions. Calendrical has one behaviour that every calendar answers, `Localize.Calendar.ISO` among them by shape (Calendrical's `localize_calendar_iso_test.exs` and its laws test hold it there); `leap_month/1`, `weeks_in_month/2` and `month_week/3` left the behaviour on 2026-10-14, as nothing called them and another callback answers each.

* [ ] **`tempo_network` 0.1.0.** The companion package (`~/Development/tempo/tempo_network`) is built and its gates pass against a path dependency on this repository; it needs its own repository, and `{:ex_tempo, "~> 2.0"}` once 2.0 is on hex. It reaches the engine in one file (`Tempo.Network.Calendar` calls `Tempo.Calendar`): either that stays an agreed private seam, or Tempo gives a public way to ask a calendar the same six questions.

* [ ] **Companions on 2.0.** `tempo_sql` and `tempo_holidays` move to `~> 2.0` once it is on hex. `tempo_holidays` builds its rules with `Tempo.every/2` and `Tempo.selection/1`, where it wrote text to be read.

* [ ] **Performance is not measured.** The reader, the walk, the set operations and the rule engine have no benchmarks against 1.6.4 (`attic/bench` holds the old ones). The reader no longer has a fast path for plain forms; whether it needs one is a measurement.

### Decisions for the user

* [ ] **A selection by a list of selectors** answers in the list's order, not time's (section 19).

* [ ] **`Tempo.Cron.parse/2` with no `:from`** starts at the first minute of 2000, where an open start would say "no start" as `Tempo.RRule.parse/2` does (section 19).

* [ ] **`Tempo.to_elixir/1` of an interval of dates** is an error, where a `Date.Range` would mirror `from_elixir/2` (section 19).

* [ ] **Set operations with an operand that has no end.** A recurrence with no end takes its other operand as its window; a set read from a stream is refused (`:too_many_values`). One rule for both is wanted: the refusal is the safe one, and a union with an endless operand has no finite answer under either.

### Defects and gaps

* [ ] **RFC 7529's `RSCALE` and `SKIP`** are refused in an RRULE and in a JSCalendar rule, and a week that starts on another day than Monday is refused where it changes the weeks counted (three of RFC 5545's examples). The published 1.6 read all three. Each wants a rule counted in a calendar or a week other than the expression's own, which the one-calendar rule (law 5) does not have a form for; whether to give it one is a decision.

* [ ] **`BYDAY` with numbered weekdays of several days** (`BYDAY=2MO,2WE`) is refused.

* [ ] **`cron`'s `28W` to `31W`** are refused: the weekday nearest a day a short month may not have depends on the month's length, which a rule's parts cannot say. It wants a part that rolls a day to a weekday within its month, as `Tempo.roll_to_workday/3` rolls a value.

* [ ] **An exclusion that cannot be read is passed over** in a recurrence's domain (`Tempo.Spans.without/3` answers the stream unchanged on an error). It should be the error.

* [ ] **A season has no dates** until a calendar answers one for a territory (`Tempo.to_interval/2` of `2026-21` is `:season`). Calendrical's to provide.

* [ ] **A solar term of a year before 0 is a day late**: `Tempo.Event.date("qingming", -3000, Calendrical.Chinese)` is 7 April and the moment is on the 6th. Calendrical's `solar_term/3` takes `trunc/1` of the moment where it wants `floor/1`. Upstream.

* [ ] **Text that is no calendar is read as a calendar of no events**: `Tempo.ICal.parse("hello, world")` is `{:ok, ~o"{}"}`. The `ical` library returns no error for text it cannot read. Upstream.

* [ ] **Two Localize defects** found before the rewrite and not rechecked since: a month that begins after its first day (`Calendrical.Reform.England`, March 1751) is not written from its year and month, and a day of the month a year turns in (`Calendrical.Julian.March25`) is read back a year early.

### Ideas, not committed to

* [ ] **Revisit the calendar adapter.** Every calendar question goes through `Tempo.Calendar`, and `test/tempo/calendar_surface_test.exs` holds the library to it; what the adapter itself still knows (the `Calendar.ISO` table, the Gregorian for a solar term, Easter and the registry lookup by name) is left as it is for now (2026-10-14).
* [ ] **A `Tempo.Intervallic` protocol**, so that a struct of the caller's (`%Booking{check_in, check_out}`) takes part in relations and set operations without being copied into a `%Tempo{}`.

* [ ] **A guide to selection**: the selector vocabulary, with `Tempo.selection/1` beside each written form.

* [ ] **`Table.Reader` for a set**, so that Livebook shows a set's members and their metadata as rows. The dependency was dropped with the struct it was written for.

## Done since the rewrite

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
