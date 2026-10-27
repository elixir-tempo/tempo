# TODO

Open work on Tempo 2.0. The design is [plans/architecture-redesign.md](plans/architecture-redesign.md): nine laws, the modules written to them, and a record of each phase as it was built (sections 12 to 20). This file tracks what is open against that design; what is done is recorded where it was decided, in `plans/decisions.md`, and in the git history. It was rewritten on 2026-10-13, cleared of its completed items on 2026-10-15, and put in the house format of five sections on 2026-10-16.

An item is a defect to fix, a decision to take, or work of another kind. What an operation gives a shape of value is not listed cell by cell: `mix test --only total` holds every operation on every value of the corpus to an answer or a named error. Each decision is recorded in `plans/decisions.md` when it is made, with its question, its context and the answer; none is open.

## Open

* [ ] **Every calendar call a callback, the rest of it** — the user, 2026-10-10: "all calendar calls in Tempo should be `calendar.some_callback`". Calendrical's side is done: every callback of its behaviour is required, with a default, since Calendrical `e3e8688` (2026-10-16), and Tempo probes no calendar and asks none its kind. Three places in Tempo still know Calendrical rather than ask a calendar. (1) Three calls of Calendrical's own functions, `Calendrical.parse`, `Calendrical.calendar_from_cldr_calendar_type` and `Calendrical.additional_calendars`, which the task "Calendrical an optional dependency" in [plans/calendar-surface.md](plans/calendar-surface.md) is to make callbacks, questions of Localize or modules the caller gives. (2) `lib/tempo/core/calendar/weeks_from.ex` builds six calendars with `use Calendrical.Base.Month`, a module internal to Calendrical (`@moduledoc false`): to build them through Calendrical's public `Calendrical.new/3`, or, where Tempo needs them at compile time, through a public way to define such a calendar that Calendrical would have to add. (3) `lib/tempo/core/calendar.ex:173` answers a solar term of `Calendar.ISO` as `Calendrical.Gregorian`'s itself, where the calendar would be asked: `Calendar.ISO` answers no solar term, so it is to ask Localize's `Localize.Calendar.ISO`, or Calendrical's Gregorian calendar through a callback. Moved from Calendrical's TODO, where the item is closed, 2026-10-16.

* [ ] **A Rust port.** Decided 2026-10-16 ([plans/translation-assessment.md](plans/translation-assessment.md), section 8): idiomatic Rust, `#![forbid(unsafe_code)]` in its own crates, over ICU4X and `jiff`, with a calendar crate and an astronomy crate beside it, and the Elixir suite run against its core through Rustler while the engine is ported. Its fixtures are written (`census.json`, `guides.json`, beside the five before them).

## Blocked

### Before the release

* [ ] **`ex_tempo_network` 1.0.0.** The companion package (`~/Development/tempo/tempo_network`, `elixir-tempo/tempo_network`) carries `Tempo.Network` and `Tempo.Schedule` onto 2.0 and takes Tempo from GitHub `main`, its gates passing (225 tests, 2026-10-26); it names `{:ex_tempo, "~> 2.0"}` and is published once Tempo 2.0 is on hex. It calls the hidden `Tempo.Calendar` in one file (`Tempo.Network.Calendar`), an agreed private seam for now (`plans/decisions.md`, 15), so a change to the adapter checks the companions.

* [ ] **Companions on 2.0.** `agenda`, `tempo_sql` and `tempo_holidays` take Tempo from GitHub `main` (2026-10-15), and move to `~> 2.0` once it is on hex; all three pass their gates against `2b04789`. `agenda` is ported (2026-10-15) under decisions 64 to 69. `tempo_holidays` is ported (2026-10-14) against a path dependency: its rules are built from parts, its conformance unchanged (168,186 matched, 0 mismatched), all 223 of its tests passing. `tempo_sql` is ported (2026-10-14) against a path dependency, under decisions 43 and 44: all 280 of its tests pass against Postgres, its version 1 and 2 composite rows read as 1.x meant them.

### Upstream

Every item here is upstream: Tempo follows each library as it is, and the item is closed by a release of that library.

* [ ] **`tz` compiles an hour at -02:00 for America/Scoresbysund on 2024-03-31 that the IANA data does not have.** The zone line `-1:00 EU -01/+00 2024 Mar 31` ends at 00:00 local time, which at the standard offset then in force (-01:00) is 01:00Z, the moment the EU rule begins summer time; `zdump -v America/Scoresbysund` shows one change at 01:00Z, of `isdst` alone, with the offset -01:00 before and after. `Tz.PeriodsProvider.periods("America/Scoresbysund")` has three periods for the day: `+00` from 01:00Z (never the answer, listed after the next), `-02` from 00:00Z and `-01` from 01:00Z, so `DateTime.shift_zone(~U[2024-03-31 00:30:00Z], "America/Scoresbysund", Tz.TimeZoneDatabase)` is 22:30-02:00 where it is 23:30-01:00, and `DateTime.from_naive(~N[2024-03-30 22:30:00], ...)` is ambiguous between +00:00 and -02:00, offsets the zone did not have. The end of a zone line looks to be converted with the offset of the period being built (+00, summer time of the old line) rather than the standard offset. `tz` 0.28.4, tzdata 2026d, found 2026-10-15; `Tempo.Zone.Table` drops the dead record and says what the database says for the rest, tick by tick (`zone_table_test.exs`, `change_of_the_clock_test.exs`).

* [ ] **`tz` has no public list of a zone's periods.** `Tempo.Zone.Transitions.Tz` reads `Tz.PeriodsProvider.periods/1`, which `tz` generates and marks `@moduledoc false`, guarded so that a `tz` without it falls back to sampling. A public function in `tz` (and one in `tzdata`, whose `Tzdata.periods/1` is public and could be adapted next) would make the table exact by contract. The same gap in Elixir's `Calendar.TimeZoneDatabase`, which answers at a point and gives no period's bounds, is the reason the table exists at all.

* [ ] **Text that is no calendar is read as a calendar of no events**: `Tempo.ICal.parse("hello, world")` is `{:ok, ~o"{}"}`. The `ical` library returns no error for text it cannot read. Rechecked against `ical` 3.2.0 on 2026-10-14.

## Deferred

### Performance

Where 2.0 stands against 1.6.4 after the work of 2026-10-15 (decisions 56 to 63 and 73 to 76), and where it could still be faster. Nothing here is needed for the release (decision 37); each item is a measurement first, against `bench/against_1_6_bench.exs`, profiled by layer, and records what it bought in its decision (`plans/reference-architecture-review.md`, section 4, has the profiles the work was ordered by).

The position on 2026-10-15 (Apple M1 Max, OTP 29.0.3, JIT), 2.0 over 1.6.4: reading text 0.03, writing 0.8, walking 0.8, relating two values about the same (1.4 µs), comparing two values 7 (1.5 µs), a set operation of two sets of a hundred members 2 (union 303 µs, intersection 419, difference 429). Of rule expansion, the weekly and monthly rules the matcher compiles are 4 to 6.5 times faster than 1.6.4 (weekly Monday-Wednesday-Friday 3.3 ms for 780 occurrences, the last weekday of the month 4.0 ms for 240, weekdays 3.8 ms for 520) and the daily rule within a fifth of it (0.19 ms for 30); the yearly fourth Thursday (1.75 ms for 50) and the hourly rule (8.4 ms for 720) go to the engine, and the hourly one is slower than before the zone table (5.5 ms), each of its occurrences asking the zone.

The engine's cost is in the placing of values. A `%Tempo{}` holds its units as written, and every question of where a value lies (`Tempo.Spans.extent/1`) reads them again through the calendar, a few hundred nanoseconds a time; a span now carries its place (`Tempo.Placed`, decision 74), but a value does not, and a rule the engine expands places each candidate as it is built, tested and bounded. A second representation of a value through the engine was measured and declined (decisions 57 and 63): about a quarter of an occurrence, for two shapes through every module. What is left is below.

* [ ] **A rule the matcher leaves to the engine.** `Tempo.Matcher` compiles a rule of months, days of the month, weekdays, positions and clock readings whose period is a day or coarser; a rule with a day of the year, a mask, a stepped range, a month counted from the end, a nested selection, a roll, or a period finer than a day is the engine's. Each of those the measures hold the engine to could be compiled the same way, the hourly and yearly rules of the benchmark first; what the matcher takes must stay exact by `rrule_measure_test.exs`, `rfc5545_examples_test.exs` and `cron_test.exs`.

* [ ] **The zone asked in the engine.** A question of `Tempo.Zone.Table` is about 250 ns, a binary search in a `:persistent_term`, where a sample kept in the process was 55 ns; the matcher asks it once a candidate reading and the engine about 45 times an occurrence. A table carried in the frame, or the stretch of one offset a walk is in handed on with the position (as decision 61 does for the walk), would take most of those out of the hourly rule.

* [ ] **Every calendar question goes through the adapter.** `Tempo.Calendar` dispatches each to the calendar's module (decisions 6 and 8); the default calendar's day numbers are answered by `Calendar.ISO` directly, and a month's labels are asked once a month (decision 75), so the calendar modules are 4 to 5% of a rule's profiled time. Gregorian day-number arithmetic held inline in the walk would remove most of what is left in a date's extent.

* [ ] **Lazy streams of structs.** Occurrences are made one at a time by `Stream.unfold/2`, each a new struct with keyword lists, and memory is 2 to 8 times 1.6.4's on the rule cases. Most callers take a bounded list, which could be made by a loop.

* [ ] **Comparing two values** is 1.5 µs, 7 times 1.6.4, which compared their fields: each is placed on the line first. A comparison of two values of one calendar and frame written to the same units could compare the units.

### Ideas, not committed to

* [ ] **Revisit the calendar adapter.** Every calendar question goes through `Tempo.Calendar`, and `test/tempo/calendar_surface_test.exs` holds the library to it; what the adapter itself still knows (the `Calendar.ISO` table, the Gregorian for a solar term, Easter and the registry lookup by name) is left as it is for now (2026-10-14).

* [ ] **A `Tempo.Intervallic` protocol**, so that a struct of the caller's (`%Booking{check_in, check_out}`) takes part in relations and set operations without being copied into a `%Tempo{}`.

* [ ] **`Table.Reader` for a set**, so that Livebook shows a set's members and their metadata as rows. The dependency was dropped with the struct it was written for.

## Done

* [x] **The ISO 8601 amendments** — ISO 8601-1:2019/Amd 1:2022 and ISO 8601-2:2019/Amd 1:2025 against Tempo (decision 86, [plans/iso8601-amendments.md](plans/iso8601-amendments.md)): a carried time shift, 24:00, `overflow: :carry`, canonical durations, expanded years, the conformance guide. 2026-10-27, v2.0.0.

* [x] **Calendrical 2.1, Localize 1.4 and Astro 2.9 from hex** — `mix.exs` requires `~> 2.1`, `~> 1.4` and `~> 2.9`, and the lock holds 2.1.0, 1.4.0 and 2.9.0. 2026-10-26.

* [x] **Calendrical's astronomical years worked out once** — Calendrical 2.1 keeps each Persian and lunisolar year once worked out: the census's fixture test takes 6.5 s, where it took 106 s on 2.0.0, and a never-occurring Persian interval rule 2.7 s, where it took 32.5 s. 2026-10-26.

* [x] **A quiet interval rule's look-ahead placed once a period** — a never-occurring quarterly rule in 61 ms, where it took a second; decision 84. 2026-10-25.

* [x] **A quiet rule walked until its interval's periods come round** — every seventh month or year selects in other months each cycle, and was ended after one; decisions 83 and 84. 2026-10-25.

* [x] **A solar term of a year before 0 fixed**, rechecked through Tempo on Calendrical `fb4a2fe` on 2026-10-16. `Calendrical.Lunisolar.solar_term/3` takes the day of the term's moment with `floor/1` where it took `trunc/1`: `Tempo.Event.date("qingming", -3000, Calendrical.Chinese)` is 6 April -3000, the day its moment (iso day -1095631.11) is in, where it was 7 April; 2026's is unchanged, 5 April.
* [x] **The Localize month-naming defect fixed**, rechecked through Tempo on Localize `ffe8fda9` and Calendrical `ae58f5b` on 2026-10-16. A month that begins after its first day is named from its year and month: `Localize.Date.to_string(%{year: 1751, month: 3, calendar: Calendrical.Reform.England}, format: :yMMM)` is "Mar 1751", where it was an `InvalidValueError`; the fix is Calendrical's (`ae58f5b`). Tempo did not reach it, writing a month by its days (`Mar 25 – 31, 1751`).
* [x] **Two Localize defects fixed**, rechecked through Tempo on Localize `ffe8fda9` and Calendrical `dc9beed` on 2026-10-16. A fiscal date is written as the Gregorian date it is: `Localize.Date.to_string(Date.new!(2027, 2, 10, Calendrical.FiscalYear.AU))` is "Aug 10, 2026", where it was "Aug 10, 2027", so `Tempo.to_string/2` of a fiscal value from July to December names the right year; the fiscal year and its ranges are unchanged. A day of the month a year turns in is read back in the year it was written with: `Tempo.parse("March 20, 1700", calendar: Calendrical.Julian.March25)` is `1700Y13M20D`, where it was `1699Y13M20D`. 2026-10-16.

* [x] **Answer fixtures for ports**: `census.json` (the census's full forms, values with no year, shapes and 985 selections in 27 calendars) and `guides.json` (1,646 calls the guides' examples make, with their answers), each read by Tempo's own tests. 2026-10-16.

* [x] **A value with no year converted to another calendar was placed in year 0**: one that names no date now keeps its form, a day of the week renumbered for the other calendar (decision 80), and one that names a month, a day or a week is `:needs_a_year`. 2026-10-16.

* [x] **A day of the week by its name in the parts of what is built** (`Tempo.new/1`, `Tempo.selection/1`, `Tempo.every/2`'s `:select`), numbered in the expression's calendar; `tempo_holidays` hands its weekdays to Tempo by name, its conformance unchanged (168,186 matched, 0 mismatched). 2026-10-16.

* [x] **A day of the week is the nth day of the expression's week, everywhere** (decision 80): every calendar and `[u-fw=…]` week start, in values, selections, rules, workdays, the builder and `explain/1`. 2026-10-16.

* [x] **A range of positions that reaches the end selected nothing** (`2026Y6ML1K{2..-1}IN`): each end is now counted, from the end where it is negative, before the range is walked, as a range of a unit's values is. 2026-10-16.
