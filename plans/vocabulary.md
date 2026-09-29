# Vocabulary

**Status:** in progress, 2026-09-29

A review of the words Tempo and tempo_holidays use in their public API — the names of functions, options, modules and errors, and the prose that explains them — against three tests: each word is familiar, each word means one thing, and each thing has one word. The precedent is `select/2`, chosen over the more exact `project/2`. The changes ship as Tempo 2.0.

The review read the documentation of all 73 public modules and 414 public functions of ex_tempo, every option the code documents or reads, the exception modules, the guides, and tempo_holidays. ex_tempo 1.6.4 is the latest release on hex; tempo_holidays is unpublished, so its names change outright. The user took every decision on 2026-09-28; they are recorded under Decisions and folded into the sections below.

## Principles

* **Familiar over exact** — the word a product manager would use: `select`, not `project`; `within`, not `bound`.

* **One meaning per word, one word per meaning** — a word with two meanings keeps one, and two words for one idea become one.

* **Elixir's word where Elixir has one** — `to_*` and `from_*`, `shift`, `shift_zone`, `datetime`, `parse` with `to_string`, and `?` for predicates.

* **A standard's term only when quoting the standard** — Allen's relations, ISO 8601's "repeat rule" and "selection", RFC 5545's property names. `Tempo.Allen` is the quotation marks for Allen.

* **Predicates speak everyday English over half-open spans** — `before?/2` answers the everyday question; `Tempo.Allen` answers Allen's exact one.

## Within replaces bound

`:bound` has three meanings today. For an anchored recurrence, and in RRULE expansion, it is an upper limit: `R/2020-01-01/P1Y` with `bound: ~o"2026"` gives the seven years 2020 to 2026. For a recurrence with an open start, or a recurrence set, it is a window: `R/../P1Y/FL12M25DN` gives 2026's Christmas alone. For `complement/2` it is the universe. Predicting which applies means knowing whether the recurrence is anchored, which is how "anchor" came into the explanation of a window. The same idea also goes by a positional `window` in `Tempo.Holidays.materialise/3`, and the unreleased `:overlapping` switch adds a third word.

| Today | Decided |
|---|---|
| `:bound` (seven functions) | `:within` |
| upper limit or window, by recurrence | occurrences that overlap it |
| `:overlapping` (unreleased) | removed: overlap is the rule |
| the positional window of `materialise/3` | `within:` on `Tempo.to_interval_set/2` |

The seven are `to_interval/2`, `to_interval_set/2`, the set operations (through `Operations.align/3`), `complement/2`, `ICal.from_ical/2`, `JSCalendar.from_jscalendar/2` and `RRule.Expander.expand/3`. The iCalendar availability functions already call it `:within` and keep it.

* **One rule, in the same sentence everywhere** — the `:within` option keeps every occurrence that overlaps the window: one already in progress when the window opens, and one that runs past its end. It is the calendar convention (CalDAV's time range, Google's `timeMin`/`timeMax`, Outlook's calendar view), so busy time read from an iCalendar keeps the overnight shift that began before the week. An occurrence that spans two back-to-back windows is in both: the December–January school break is among 2026's holidays and 2027's. `within?/2` asks whether a whole span is inside another, and its doc points out the difference.

* **Every occurrence, every source** — the rule holds for anchored, counted, UNTIL and open-start recurrences, for a recurrence set's one-off members, and for the events `Tempo.ICal.from_ical/2` and `Tempo.JSCalendar.from_jscalendar/2` return, one-off events included. A domain year still owns the occurrences its selection yields; the window then keeps those that overlap it.

* **`Schedule.task/3`'s `:within`** is the window the whole task must fit inside, as `within?/2` reads.

* **Bound keeps one meaning, a limit** — `bounded?/1` (both ends stated), an unbounded recurrence (no end), and the network solver's earliest and latest bounds.

* **A leftover `:bound` is an error naming `:within`** — never silently ignored.

## Anchor keeps one meaning

"Anchor" has six meanings today: a value placed on the time line because it has a year (`anchored?/1`, `anchor/2`); a zoned value ("UTC-anchored" in `shift_zone/2`); a recurrence's start (`RRule.Expander.to_ast/3`, "an unanchored recurrence"); a counting origin (`Interval.Steps.on_step?/4`); a task's fixed date (`Schedule.task/3`'s `:start`); and a place (tempo_holidays' `{:sunset, anchor}`). Its negative is spelled "non-anchored", "un-anchored" and "unanchored".

| Today | Decided |
|---|---|
| anchored: has a year | unchanged |
| non-anchored, un-anchored | unanchored |
| UTC-anchored | zoned |
| a recurrence's anchor | its start (ISO 8601's word) |
| an unanchored recurrence | a recurrence with an open start |
| anchored at `from` | counted from `from` |
| `{:sunset, anchor}` | `{:sunset, location}` |
| `NonAnchoredError`, `RequiresAnchorError` | `UnanchoredError` |
| `anchor/2` | folded into `at/2` and `on/2` |

`anchor/2` is the mirror of `at/2`: `date |> at(time)` sets a time, and `time |> anchor(date)` places one. English already has the words — `~o"T17" |> Tempo.on(~o"2026-06-15")` reads "17:00 on 15 June" — so `at/2` and `on/2` fill whichever side is missing: the value with a year keeps it, and the other supplies what it lacks. With the rule for `:within` uniform, a recurrence's documentation no longer needs the word at all, and "anchored" is left meaning one thing.

## Occurrences, not materialisation

Turning a rule into its occurrences has four names: `to_interval_set/2`, `RRule.Expander.expand/3`, `Tempo.Holidays.materialise/3`, and "materialise" in the docs and in `MaterialisationError`. The public verbs become Elixir's conversion idiom alone, `to_interval/2` and `to_interval_set/2`, and "materialise" stays the name of the internal operation.

| Today | Decided |
|---|---|
| `Tempo.Holidays.materialise/3` | removed |
| `MaterialisationError` | `ConversionError` |
| `RRule.Expander.expand/3` | internal |
| "materialise" in doc summaries | "occurrences", "convert" |

`ConversionError` is already the error of the other `to_*` functions. The RRULE path becomes `RRule.parse/2`, then `to_interval_set/2`. Without `Tempo.Holidays.materialise/3`, a year of holidays reads:

```elixir
{:ok, holidays} = Tempo.Holidays.holidays(:AU, exclude: :observance)
{:ok, this_year} = Tempo.to_interval_set(holidays, within: ~o"2026")
```

Its three extra steps move:

* **Type selection** — already in `holidays/2`.

* **The same-name merge** — it joins abutting occurrences that share a name. A period date-holidays splits at the year end needs it, and that case moves into `holidays/2`, which holds the period as one member. It also joins separate day rules (the 1st and 2nd Shawwal of Eid al-Fitr) and a holiday with its observed day (US Independence Day 2026 becomes one span from 3 July), losing the second rule's `:id` and the observed day's `substitute: true`; those stay separate occurrences.

* **`:day_start`** — a sunset boundary cannot be part of a recurrence, so it becomes a step over the occurrences: `Tempo.Holidays.day_start(this_year, :sunset)`.

## Floating and zoned

The zone axis has two words for one side: `grounded?/1`, `GroundedTempoError` and "ground" in `in_zone/2`'s doc, but "zoned" in `to_date_time/1`'s. "Floating" is the calendaring word (RFC 5545, JSCalendar), and its familiar opposite is "zoned" (Temporal's `ZonedDateTime`).

| Today | Decided |
|---|---|
| `floating?/1` | unchanged, the pair of `zoned?/1` |
| `grounded?/1` | `zoned?/1` |
| `FloatingTempoError` | unchanged, the pair of `ZonedTempoError` |
| `GroundedTempoError` | `ZonedTempoError` |
| "ground", "UTC-anchored" | "zone", "zoned" |

`at/2`'s doc calls a value with no year "floating", the zone axis's word; it becomes "unanchored".

## Parsing and formats

`parse` reads locale text in `parse/2`, which accepts ISO 8601 too, but only ISO 8601 in `parse_date/2`, `parse_datetime/2`, `parse_time/2`, `parse_interval/2` and `parse_duration/1`: `Tempo.parse_date("15 June 2026", locale: :en)` is an error. The format modules use three verbs and stutter (`Tempo.ICal.from_ical/2`), and RRULE is read by `Tempo.RRule.parse/2` but written by `Tempo.to_rrule/1`.

| Today | Decided |
|---|---|
| `parse_date/2` and its siblings | read what `parse/2` reads, of one kind |
| `ICal.from_ical/2`, `from_ical_file/2` | `ICal.parse/2`, `ICal.parse_file/2` |
| `ICal.available_from_ical/2` | `ICal.available/2`, given text |
| `JSCalendar.from_jscalendar/2` | `JSCalendar.parse/2` |
| `Tempo.to_rrule/1` | `RRule.to_string/1` |

In the event `parse/2` read ISO dates through Calendrical but not ISO datetimes, intervals, durations or IXDTF, so it now reads Tempo's ISO 8601 grammar first and the locale's words after, and the typed parsers read the same.

`parse` with `to_string` is the text pair, as in Localize and `URI`. `Tempo.from_iso8601/2` and `to_iso8601/1` stay on `Tempo`: ISO 8601 is Tempo's own syntax, as it is `Date`'s.

## Elixir conversions

Elixir writes "datetime" as one word (`Calendar.ISO.parse_naive_datetime/1`), and so does Tempo's own `parse_datetime/2`.

| Today | Decided |
|---|---|
| `to_date_time/1`, `from_date_time/1` | `to_datetime/1`, `from_datetime/1` |
| `to_naive_date_time/1` | `to_naive_datetime/1` |
| `from_naive_date_time/1` | `from_naive_datetime/1` |
| `to_calendar/1` (deprecated) | removed, for `to_elixir/1` |

## Predicates and Tempo.Allen

The `?` functions mix two vocabularies. `before?/2` and `after?/2` follow Allen and need a gap, so an 11:00–12:00 meeting is not before a 12:00 lunch, and `during?/2` and `meets?/2` are Allen's strict relations; but `overlaps?/3`, `contains?/3` and `within?/2` use the everyday sense. Containment has three names (`within?/2`, `contains?/3`, `subset?/3`), and sameness two (`equal?/3`, `Interval.equivalent?/2`). Allen's own operations are scattered too: the inverse of a relation is `Interval.inverse_relation/1` and `Relations.converse/1`, and composition is on `Tempo`, `Interval` and `Relations`.

| Today | Decided |
|---|---|
| `before?/2`, `after?/2` need a gap | share no instant, one earlier |
| `during?/2`, `meets?/2` | `Tempo.Allen.during?/2`, `Tempo.Allen.meets?/2` |
| `subset?/3` | removed |
| `Interval.equivalent?/2` | removed |
| `Interval.inverse_relation/1`, `Relations.converse/1` | `Tempo.Allen.inverse/1` |
| `compose/2` on `Tempo`, `Interval` and `Relations` | `Tempo.Allen.compose/2` |

* **`Tempo` keeps the everyday predicates** — `before?/2`, `after?/2`, `adjacent?/2`, `overlaps?`, `disjoint?`, `within?`, `contains?` and `equal?`, for intervals and sets alike. `before?/2`'s doc explains the everyday sense — an 11:00–12:00 meeting is before a 12:00 lunch — and points to `Tempo.Allen.precedes?/2` for the version that needs a gap. The certainty family (`certainly_before?/2`, `possibly_before?/2` and the rest) follows the everyday predicates.

* **`Tempo.Allen` holds Allen's exact vocabulary** — a predicate for each of the 13 relations, named as Allen named them (`precedes?/2`, `meets?/2`, `overlaps?/2`, `finished_by?/2`, `contains?/2`, `starts?/2`, `equals?/2`, `started_by?/2`, `during?/2`, `finishes?/2`, `overlapped_by?/2`, `met_by?/2`, `preceded_by?/2`), with `inverse/1` and `compose/2`. Inside it every name is Allen's — the module name is the quotation — so `Tempo.Allen.overlaps?/2` is the strict relation while `Tempo.overlaps?/3` is the everyday one. `Tempo.relation/2` stays the way in.

* **The network solver keeps "contemporary"** — `contemporaneity/3`, `certainly_contemporary?/3` and `possibly_contemporary?/3` treat a period's ends as closed, so two periods that only touch are contemporary, the chronology literature's own sense and that of `add_relation(:contemporary, …)`. `Tempo.overlaps?/3` needs a shared instant, so naming the solver's functions "overlaps" would give that word two meanings. (Found while implementing, 2026-09-28; the plan first proposed the rename.)

## Workdays

Two words name one idea: `workday?/2` and `workdays/1`, but `add_working_days/3`, `next_working_day/2`, `previous_working_day/2`, `nearest_working_day/2` and `working_days_in/2`; the guides say "workday" eight times as often. The weekend has two shapes under near-identical names: `weekend/1` is a selector like `workdays/1`, while `weekends/1` is a lazy set of days.

| Today | Decided |
|---|---|
| `add_working_days/3` | `add_workdays/3` |
| `next_working_day/2` | `next_workday/2` |
| `previous_working_day/2` | `previous_workday/2` |
| `nearest_working_day/2` | `nearest_workday/2` |
| `working_days_in/2` | `count_workdays/2` |
| `weekend/1`, a selector | `weekends/1` |
| `weekends/1`, a lazy set | `select/2` over an open span |

Selectors are plural nouns: "the workdays of June" is `Tempo.select(~o"2026-06", Tempo.workdays(:AU))`. The lazy weekend days from a date become `Tempo.select(~o"2026-06-15/..", Tempo.weekends(:AU))`, which needs `select/2` to return a lazy set for an open-ended span; `shift/3`'s `:skipping` takes it as it takes the lazy set today.

* **Found while implementing (2026-09-29)** — `select/2` selected only in a span's first period (`~o"2026/2029"` held 2026's Christmas alone), so the open span's period-by-period walk is every span's. The workday functions return `{:error, reason}`, as `shift/2` does, where they raised.

## Sets

| Today | Decided |
|---|---|
| `IntervalSet.members/1`, `to_list/1` | `members/1` |
| `duration/1` sums members | `duration/1` measures covered time |
| `IntervalSet.total_duration/1` | removed |
| `IntervalSet.overlapping/2` | `IntervalSet.covered/2` |
| `RecurrenceSet.new/2` returns a struct | returns `{:ok, set}`, with `new!/2` |

* **`members/1`** — `IntervalSet.to_list/1` returns the members while `Enum.to_list/1` walks the days inside them, the one module whose `to_list/1` differs from `Enum`'s; `members/1` is the same function under a name that says which list, as on `RecurrenceSet`.

* **`duration/1`** — `Tempo.duration/1` and `IntervalSet.duration/1` sum member lengths and `total_duration/1` measures covered time, so 09:00–11:00 with 10:00–12:00 is 4 hours or 3 depending on the name. Covered time is what the name promises, and `Tempo.duration/1`'s doc already promises it.

* **`covered/2`** — the time covered by at least n members, beside `covered?/2`: `IntervalSet.covered(bookings, at_least: 2)` is the double-booked time. "Overlapping" is left to `members_overlapping/3`.

* **`RecurrenceSet.new/2`** — every other constructor that takes input returns `{:ok, value}` and has a bang variant.

* **Found while implementing (2026-09-29)** — `covered/2` defaults `:at_least` to one, the time the set covers, and returns `{:ok, set}`, so a bad option or a lazy set is an error rather than a raise. `new/2` checks members as conversion does, which still checks a set built without it.

## Span ends

`Interval` names a span's ends `from` and `to`. `Network.TimePeriod.new/2` calls them `:start` and `:end`, and `Schedule.Slot` has `start`, `finish`, `latest_start` and `latest_finish`.

| Today | Decided |
|---|---|
| `TimePeriod.new/2`'s `:start`, `:end` | `:from`, `:to` |
| `Schedule.Slot`'s four times | two intervals, early and late |
| `beginning_of_day/1` and four more | deleted |

The five are `beginning_of_day/1`, `beginning_of_week/1`, `beginning_of_month/1`, `end_of_day/1` and `end_of_month/1`. They return instants, and instants are not what Tempo is about; `Tempo.end_of_month/1` also answers 1 July where Elixir's `Date.end_of_month/1` answers 30 June. In Tempo the month containing a value is `Tempo.trunc(value, :month)`, a span whose ends are `Interval.from/1` and `Interval.to/1`.

* **Decided while implementing (2026-09-29, user)** — only `TimePeriod.new/2`'s options take `:from` and `:to`; ChronoLog's own boundary vocabulary (`{:start, id}`, `:starts_during`, `earliest_start`) stays. The builders never raise: `TimePeriod.new/2` returns `{:ok, period}`, and an option or value `add_period/3`, `add_sequence/2`, `add_relation/5` or `Schedule.task/3` cannot read is recorded on the network and returned by the solver, so a leftover `start:` or `earliest:` is an error naming its 2.0 option.

## Specialist modules

* **Schedule** — `Schedule.task/3`'s `:earliest` becomes `:not_before`, since it does not say earliest what; `:deadline` and `:within` stay. `Schedule.Slot`, a solved task, takes another name so "slot" means only a bookable piece of time (`IntervalSet.slots/3`).

* **Constraint networks** — `Interval.RelationNetwork.propagate/1` and `Network.Solver.tighten/1` do the same job for a qualitative and a metric network; one verb, `propagate/1`.

* **Decided while implementing (2026-09-29, user)** — `Schedule.Slot` becomes `Tempo.Schedule.ScheduledTask`, holding `early` and `late` intervals and `critical?`.

## Out of the public API

Internal machinery listed as public API, several modules with a vocabulary of their own, moves to the Internals docs group:

* **`Tempo.Compare`** — `compare_endpoints/2` answers `:earlier | :later | :same`, a second comparison vocabulary beside `compare/3`'s `:lt | :eq | :gt`, and `to_utc_seconds/1` is the raw-seconds API the example rules exclude.

* **`Tempo.Iso8601.Tokenizer` and its sub-modules** — NimbleParsec's generated `datetime_or_date_or_time__0/6` and its siblings are listed in the docs.

* **Engine helpers** — `Tempo.Interval.Steps`, `Tempo.Microsecond`, `Tempo.Network.Normalize`, `Tempo.RRule.Expander`, `Tempo.RRule.Rule`, `Tempo.RRule.Selection` and `Tempo.unit_min_max/1`.

* **Undocumented public functions** — `Tempo.merge/2`, `Tempo.extend!/2`, `Tempo.from_iso8601/2` and `Tempo.from_iso8601!/2` are documented or hidden.

The two behaviours consumers implement, `Tempo.Event.Resolver` and `Tempo.IntervalSet.Backend`, stay public.

## What stays

`select/2`, `shift/3`, `shift_zone/2`, `in_zone/2`, `at/2`, `on/2`, the set operations and the `members_*` filters, `relation/2` and Allen's atoms, `resolution/1` and `:unit`, `metadata/1` and `put_metadata/2`, `floating?/1`, `anchored?/1`, `to_interval/2`, `to_interval_set/2`, `from_iso8601/2`, `to_iso8601/1`, `parse/2`, `to_string/2`, `explain/1`, the duration predicates (`at_least?/2`, `at_most?/2`, `exactly?/2`, `longer_than?/2`, `shorter_than?/2`), the certainty family (`certainly_*?`, `possibly_*?`, `*_certainty`), "territory", and ISO 8601's "repeat rule" and "selection".

## Real-world questions

A livebook of everyday questions tests the vocabulary: when the next Victorian school holidays are, how many days until the next US Election Day, how many public holidays the UK has, and which of them it shares with Australia. Wherever an answer needed a helper, a library was missing something:

* **The next school holidays** — `within:` refused an open-ended window, so "next" needed a guessed horizon. An open-ended window gives the occurrences from its start, and `Tempo.IntervalSet.first/1` of them is the next.

* **Today against a holiday** — `today/1` returned a zoned day, so `relation/2` raised against a floating holiday date and `duration/2` silently added the zone's offset (36 days 10 hours to Election Day). `today/1` returns the floating date, `now/1` stays zoned, and `duration/2` refuses a zoned value against a floating one as `relation/2` does.

* **Days until Election Day** — `duration/2` answered in seconds. It answers in its endpoints' unit: `~o"P36D"` between two days, `~o"PT8H"` between two hours.

* **Showing an answer** — an interval set's inspect hides its members' metadata, so every answer mapped `Tempo.metadata/1` over its members. `Table.Reader` for `Tempo.IntervalSet` lets Livebook show a set as a table.

* **Victorian school holidays** — tempo_holidays dropped a dated period's length: `2026-09-19 P16D` became one day. A dated period keeps its length. (date-holidays has no NSW school holidays; the user will add them there.)

* **England's holidays** — `subdivision: "ENG"` silently returned the national set, because England is a `:division`. One `:subdivision` option, the ISO 3166-2 word, names a subdivision at whichever level the data holds it, and an unknown one is an error.

* **How many holidays** — a weekend holiday and its substitute day were both occurrences, so England counted 9 holidays in 2026 for its 8. `dates: :substitute` (the default) gives the substitute day when there is one, `:gazetted` the gazetted date, and `:both` both.

## Defects found on the way

These need no rename:

* **`Tempo.duration/1` on a set** sums member lengths, although its doc promises covered time.

* **`Tempo.round/2`'s summary** says "Truncates".

* **`Interval.certainly_overlaps?/2`'s doc** points to an `Interval.overlaps?/2` that does not exist.

* **`at/2`'s doc** calls an unanchored value "floating".

## Decisions

Taken by the user on 2026-09-28:

* **The window's name** — `:within`: clearer than `:window` despite the difference from `within?/2`.

* **The window's rule** — every occurrence that overlaps the window, the calendar convention; chosen over the start rule, which drops an event already in progress when the window opens and so loses busy time.

* **`before?/2` and `after?/2`** — the everyday sense, sharing no instant, with the difference explained in their docs; Allen's exact relations live in `Tempo.Allen`.

* **`anchor/2`** — folded into `at/2` and `on/2`.

* **The typed parsers** — read what `parse/2` reads.

* **`beginning_of_*` and `end_of_*`** — deleted: instants are not what Tempo is about.

* **tempo_holidays' merge** — only a period split at the year end.

* **The release** — 2.0.0: the unreleased 1.7.0 becomes 2.0.0, old names are removed rather than kept as deprecated aliases, and the CHANGELOG carries a migration table.

* **`floating?/1`** — stays, the pair of `zoned?/1`.

* **A migration guide** — `guides/migration.md` shows each change with its 1.x and 2.0 forms.

* **The real-world gaps** — decided as "Real-world questions" describes: an open-ended window for "next", the floating `today/1`, durations at their endpoints' resolution, and a holiday on its substitute day by default, its gazetted date or both on request. The livebook uses Victoria's school holidays.

## Tasks

Each task is one commit, verified on both upstream branches, with its guides, README, cookbook and livebook examples updated in the same commit, and its section of the migration guide written in it.

* [x] **2.0 and the defects** — `2.0.0-dev`, the CHANGELOG's migration table, the four defects, covered time as `duration/1`'s one meaning. 2026-09-28, `a7a4010`.

* [x] **Within** — `:within` for `:bound`, overlap as the one rule for every recurrence and calendar format, `:overlapping` removed, a leftover `:bound` an error. 2026-09-28, `b92a189`.

* [x] **Predicates and `Tempo.Allen`** — the everyday `before?/2` and `after?/2`, `Tempo.Allen`, the removals and renames above, and the migration guide. 2026-09-28, `c669d20`.

* [x] **From now on** — an open-ended `within:` window, the floating `today/1`, and `duration/2` refusing a zoned value against a floating one. 2026-09-28, `f04caaa`.

* [x] **Sets as tables** — `Table.Reader` for `Tempo.IntervalSet`, so Livebook shows a set's members and their metadata as a table. 2026-09-28, `c902247`.

* [x] **Durations at resolution** — `duration/1` and `duration/2` in their endpoints' unit, the finer where they differ: years to days on the calendar through `Calendrical.diff/3`, hours to fractions of a second as elapsed time, and a week against a month or a year in days. 2026-09-28, `19eecb1`.

* [x] **Anchor** — one meaning, `UnanchoredError`, `anchor/2` folded into `at/2` and `on/2`. 2026-09-28, `3a1b236`.

* [x] **Floating, zoned and datetime** — `zoned?/1`, `ZonedTempoError`, the `datetime` conversions, `to_calendar/1` removed. 2026-09-28, `93e2e25`.

* [x] **Parsing and formats** — the typed parsers, `ICal.parse/2`, `JSCalendar.parse/2`, `RRule.to_string/1`. 2026-09-29, `acb9d33`.

* [x] **Occurrences and internals** — `ConversionError`, `RRule.Expander` internal, the Internals group, the undocumented functions. 2026-09-29, `3b2167a`.

* [x] **Workdays** — the renames, plural selectors, and `select/2` over an open span. 2026-09-29, `3e5467a`.

* [x] **Sets** — `members/1`, `covered/2`, `RecurrenceSet.new/2`. 2026-09-29, `4ebfbcb`.

* [ ] **Span ends and specialist modules** — `:from`/`:to`, `Schedule.Slot`, the deleted instant helpers, `:not_before`, `propagate/1`.

* [ ] **tempo_holidays** — `materialise/3` removed, `within:`, the year-end merge in `holidays/2`, `day_start/2`, `{:sunset, location}`, and its publish comment at `~> 2.0`. Its per-year checks compare by start year, date-holidays' convention: under the overlap rule a year's window also holds a holiday still running from December (Hanukkah 2005–06, Eid al-Adha 2006–07), which made 6 rules and 3 Hebrew conformance dates differ when measured against task 2. Also a dated period's length, one `:subdivision` option with an unknown one an error, and `dates: :substitute | :gazetted | :both`.

* [ ] **Real-world livebook** — the next Victorian school holidays, the days until the next US Election Day, the UK's public holidays, and those the UK shares with Australia, each read as prose.

* [ ] **Downstream** — `tempo_sql` moves to `~> 2.0` once 2.0.0 is on hex.
