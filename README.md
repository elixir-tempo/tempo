# Tempo

![Tempo](https://raw.githubusercontent.com/elixir-tempo/tempo/main/assets/logo-social-cropped.png)

Tempo is an Elixir library that models time the way humans actually use it — as bounded spans on a shared timeline rather than as scalar instants. Everything positioned is an interval — a year, a month, an afternoon, a meeting, an archaeological period, a recurring event — each a bounded interval at some resolution. Collections of them, like a free-busy calendar, are *derivations* over that one type rather than new types; the sole companion is `Duration`, an unpositioned width from which an interval is formed once it is given a start. Every operation (iteration, comparison, set-theoretic combination) is defined uniformly.

This conceptual shift — *time as interval, not instant* — removes a surprising number of real-world bugs (off-by-one day errors, ambiguous "end of day", last day of month, last day of year, DST edge cases, "what date does this year mean?") while unlocking queries that are awkward or impossible in other libraries.

## Features

* **One type.** No more `Date` for days, `Time` for hours, `DateTime` for both, `NaiveDateTime` for "I don't know what I have" — one `%Tempo{}` holds a value at any resolution, an interval, a recurrence, a set of them or a choice among them. `Tempo.Interval`, `Tempo.IntervalSet` and `Tempo.RecurrenceSet` are constructors of that one struct, not types of their own; the one distinct companion is `Tempo.Duration`, a length with no place on the time line. Conversion from Elixir's types is `Tempo.from_elixir/2`.

* **Correctness by construction.** Every value denotes half-open spans `[from, to)` on the time line, so adjacent spans join cleanly (`[a, b)` and `[b, c)` are `[a, c)`). An interval is read as it is written: one written to a date runs through that date (`2026/2028` is three years), and one written to a time of day runs to that reading. "End of day" ambiguity, midnight off-by-ones and DST-hour confusion vanish at the type level.

* **Full support for the time standards that matter.** ISO 8601 Parts 1 and 2, EDTF Levels 0–2, IXDTF. 100% of the `unt-libraries/edtf-validate` corpus passes. Long years (`Y17E8`), significant-digits notation, mask syntax, open-ended intervals, per-endpoint qualifications — all parsed and queryable — and the leap seconds a span holds are counted into its length (`Tempo.LeapSeconds`).

* **First-class set algebra on time.** Union, intersection, complement, difference, symmetric difference — plus the predicate set (`disjoint?`, `overlaps?`, `within?`, `contains?`, `equal?`) — all defined over any Tempo value. Cross-zone, cross-calendar, across resolutions.

* **Constraint reasoning, in a companion package.** `Tempo.Network` models a web of partially-known intervals — reigns, strata, project tasks — and computes the tightest dates each one can take (the ChronoLog scheme), and `Tempo.Schedule` applies the same solver to project scheduling. Both live in the `tempo_network` package, which depends on this one.

* **Business days and territory-aware calendars.** `Tempo.weekend?/2`, `Tempo.workday?/2`, `Tempo.add_workdays/3`, and `Tempo.count_workdays/2` answer "how many workdays until the deadline?" with CLDR-correct weekends per territory (the US weekends Saturday/Sunday, Saudi Arabia Friday/Saturday) and correct on any calendar, and `Tempo.roll_to_workday/3` moves a date that falls on a day off by a contract's business day convention.

* **Yearly dates written in words, and counting.** `Tempo.DateRule.parse/2` reads a date as a holiday calendar writes it — `4th Thursday in November`, `easter -2`, `15 Nisan`, `01-26 and if saturday then next monday` — into the Tempo recurrence it means, and `Tempo.count/3` counts the days, hours or seconds an expression holds: `Tempo.count(business_days, :day)`.

* **iCalendar import with metadata that travels.** `Tempo.ICal.parse/2` parses RFC 5545 `.ics` data and every event's metadata (summary, location, attendees, status, …) rides along through every downstream operation. Intersect your schedule with work hours, get back *which meetings* are in work hours.

* **Unlocking queries that used to be hard.** "Every Friday the 13th this century." "When was I both in Japan and enrolled at my university?" "Free time on Tuesday, accounting for meetings across three zones." "Does this dig layer overlap with this dynasty?" All direct expressions over the same `Tempo` API.

## Supported Elixir and OTP versions

Tempo supports **Elixir 1.17** and later on **Erlang/OTP 27** and later; OTP 26 is not supported.

## Installation

```elixir
def deps do
  [
    {:ex_tempo, "~> 2.1"},
    # Optional but recommended - needed for iCalendar import.
    {:ical, "~> 3.2"}
  ]
end
```

Tempo is published on hex as `ex_tempo` because the `tempo` name on hex was already taken; its modules are `Tempo` and `Tempo.*`, so in code it is `tempo`. Docs at [https://hexdocs.pm/ex_tempo](https://hexdocs.pm/ex_tempo).

## Quick start

Full ISO 8601-2 / EDTF / IXDTF support, calendar-aware arithmetic, cross-zone set operations. In fact, probably the only full implementation of ISO 8601 Parts 1 and 2 in existence (really, I couldn't find one anywhere - please let me know if you know of one).

Every example below uses the `~o` sigil to construct Tempo values at compile time. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` to the caller's namespace; no helper functions leak in. Treat this line as a prerequisite for every code block that follows in this README.

```elixir
# A date is an interval: a day is a day long, and holds its hours
iex> ~o"2026-06-15"
~o"2026Y6M15D"

iex> Tempo.duration(~o"2026-06-15")
~o"P1D"

iex> Enum.take(~o"2026-06-15", 3)
[~o"2026Y6M15DT0H", ~o"2026Y6M15DT1H", ~o"2026Y6M15DT2H"]

iex> ~o"2026-06-15T10:30" in ~o"2026-06-15"
true

# Values in different zones are compared on the one time line
iex> paris = Tempo.from_elixir!(DateTime.new!(~D[2026-06-15], ~T[10:00:00], "Europe/Paris"))
iex> Tempo.within?(paris, ~o"2026-06-15T07Z/2026-06-15T09Z")
true

# Values in different calendars too, with no conversion by hand
iex> hebrew = Tempo.new!(year: 5786, month: 9, day: 30, calendar: Calendrical.Hebrew)
iex> Tempo.overlaps?(hebrew, ~o"2026-06-15")
true
```

> *"The fifteenth of June is a day long and holds twenty-four hours, half past ten among them. Ten o'clock in Paris is **within** seven to nine in UTC. The thirtieth of Sivan 5786 **overlaps** the fifteenth of June 2026."*

### Four ways to construct a Tempo

The `~o` sigil is ideal for literal values in source code. For runtime data — form inputs, database rows, API payloads — reach for `Tempo.new/1`, which takes its units in any order and validates them against the calendar:

```elixir
# A literal, read when the module compiles
iex> ~o"2026-06-15T14:30[Australia/Sydney]"
~o"2026Y6M15DT14H30M[Australia/Sydney]"

# Units at runtime, in any order
iex> Tempo.new!(day: 15, year: 2026, month: 6, hour: 14, minute: 30, zone: "Australia/Sydney")
~o"2026Y6M15DT14H30M[Australia/Sydney]"

# Elixir's own Date, Time, NaiveDateTime and DateTime
iex> Tempo.from_elixir(~U[2026-06-15 14:30:00Z])
{:ok, ~o"2026Y6M15DT14H30M0SZ"}
```

A rule, or anything said a piece at a time, is built a step at a time with `Tempo.Builder`, each step a complete expression:

```elixir
iex> import Tempo.Builder
iex> every(:week) |> on(:monday) |> at(hour: 9) |> starting(~o"2026-06-01") |> times(10)
{:ok, ~o"R10/2026Y6M1D/P1W/FL1KT9HN"}
```

> *"Every week, on Monday, at nine, starting the 1st of June, ten times."*

`Tempo.new/1` validates its units against the calendar (a Gregorian February has 28 days in a common year, a Hebrew leap year a thirteenth month), returns `{:ok, value}` or `{:error, exception}`, and has a `new!/1` that raises. `Tempo.Interval.new/1` and `Tempo.Duration.new/1` follow the same contract, as does every constructor, conversion, parser and set operation.

Now the playful side — what you actually get to write:

```elixir
# "Sometime in the 1560s"
iex> Enum.take(~o"156X", 5)
[~o"1560Y", ~o"1561Y", ~o"1562Y", ~o"1563Y", ~o"1564Y"]

# "The 15th of some month of 1985": twelve days, not one span
iex> {:ok, fifteenths} = Tempo.to_interval(~o"1985-XX-15")
iex> Tempo.IntervalSet.count(fifteenths)
12

# "The last Friday of each month of 2026", written as ISO 8601-2 writes it
iex> {:ok, fridays} = Tempo.to_interval(~o"R12/2026-01-01/P1M/FL5K-1IN")
iex> Tempo.IntervalSet.map(fridays, &Tempo.day/1)
[30, 27, 27, 24, 29, 26, 31, 28, 25, 30, 27, 25]
```

A schedule read from iCalendar keeps each event's summary and location as metadata, on every interval that survives a set operation:

<!-- guides:skip -->
```elixir
{:ok, schedule} = Tempo.ICal.parse_file("work.ics")
{:ok, free} = Tempo.difference(~o"2026-06-15T09/2026-06-15T17", schedule)

Tempo.IntervalSet.map(schedule, &Tempo.metadata(&1).summary)
#=> ["Design review", "1:1 with Ada", "Standup"]
```

> *"My free time is the working day **minus** my schedule."*

And when you're looking at an unfamiliar value in iex, ask it to explain itself:

```elixir
iex> Tempo.Explain.lines(~o"156X")
[
  "A value with unspecified digits, some one of the values they allow, written to the year: Jan 1560 – Dec 1569.",
  "It is one of 10 values.",
  "It is floating: a reading of a clock in no zone.",
  "Walking it gives its members."
]

iex> Tempo.Explain.lines(~o"1984?/2004~")
[
  "An interval: 1984 – 2004.",
  "It covers 1984Y? through 2004Y~.",
  "It is floating: a reading of a clock in no zone.",
  "Walking it gives its years."
]
```

`Tempo.explain/1` joins the lines into one text for `IO.puts/1`, and `Tempo.to_string/2` gives a locale's words for any value (`"Jun 15, 2026"`, `"15 juin 2026"`).

The `~o` sigil also does **pattern matching**. In `match?/2`, `case` clauses, `=` and function heads, the same sigil is a pattern that matches every value whose units begin with the units written, and constrains nothing else:

```elixir
iex> today = ~o"2026-04-24"
iex> match?(~o"2026", today)
true

iex> match?(~o"2026-04", today)
true

iex> match?(~o"2025", today)
false

iex> case today do
...>   ~o"2026-04" -> :this_april
...>   ~o"2026" -> :this_year
...>   _ -> :another_time
...> end
:this_april
```

More in the [Pattern matching with sigils](https://hexdocs.pm/ex_tempo/pattern-matching-with-sigils.html) guide.

## Why intervals, not instants

Every mainstream language treats `date`, `time`, and `datetime` as distinct scalar types. That fragmentation creates three classes of common bugs that Tempo eliminates by construction:

1. *The "what does this value mean" ambiguity:* Is `~D[2026-06-15]` the instant of midnight on June 15, or the whole day? Most libraries can't say — the type is a scalar but it's being *used* as a span, with every developer inventing their own `end_of_day/1` helper. In Tempo, `~o"2026-06-15"` *is* the interval `[2026-06-15T00:00, 2026-06-16T00:00)`. No helpers needed; the semantics are the type.

2. *The type-per-resolution explosion:* `Date` for days, `Time` for hours/minutes/seconds, `DateTime` for the combination — and conversions between them are lossy in confusing directions. Tempo's single `%Tempo{}` struct carries its own resolution. A year, a month, a meeting, a millennium — same type, different resolution.

3. *The "I can't express that" ceiling:* Archaeological dates ("sometime in the 1560s"), EDTF-qualified values ("approximately 2022"), open-ended intervals ("from 1985 onwards"), Hebrew-to-Gregorian queries, recurrences, free-busy spans — all awkward or impossible to express cleanly as scalar instants. All natural in Tempo.

Once every value is a bounded interval, set operations follow naturally: union, intersection, complement, difference, and predicates (`overlaps?`, `within?`, `contains?`) all work on any combination of Tempo values, across resolutions, across timezones, across calendars.

## Configuration

### Time-zone database

Tempo asks Elixir's standard `Calendar.TimeZoneDatabase` behaviour for a zone's rules, and comes with [`:tz`](https://hex.pm/packages/tz), which compiles the IANA data in and downloads nothing at run time. A named zone works with no configuration:

```elixir
iex> Tempo.from_iso8601!("2026-06-15T09:00:00[Europe/Paris]")
~o"2026Y6M15DT9H0M0S[Europe/Paris]"
```

Tempo asks the database the application configures where it configures one: `config :ex_tempo, :time_zone_database, ...` for Tempo alone, else Elixir's own `config :elixir, :time_zone_database, ...` (or `Calendar.put_time_zone_database/1`), which `DateTime` reads too. Any implementation works there — `:tz`, [`:tzdata`](https://hex.pm/packages/tzdata), [`:time_zone_info`](https://hex.pm/packages/time_zone_info) or [`:zoneinfo`](https://hex.pm/packages/zoneinfo) (reads the OS zone files) — and where neither names one, or Elixir's is its own UTC-only default, Tempo asks `tz`. `Tempo.time_zone_database/0` returns the one Tempo asks, so a library built on Tempo reads a zone as Tempo does. A zone update reaches Tempo by updating the database package; Tempo keeps no zone data of its own.

A database configured under `:ex_tempo` that knows only UTC (`Calendar.UTCOnlyTimeZoneDatabase`) refuses a named zone where it is given — by the reader (`[Europe/Paris]`), `Tempo.in_zone/2`, `Tempo.shift_zone/2` and `Tempo.now/1` — with a `Tempo.ZoneError` whose reason is `:no_database`. UTC, a fixed offset (`[+02:00]`) and a time shift (`+02:00`) need no database. iCalendar import reads Elixir's setting rather than Tempo's: the upstream `:ical` library only populates an event's `dtstart`/`dtend` fields when a default `Calendar.TimeZoneDatabase` is installed, so set `config :elixir, :time_zone_database, Tz.TimeZoneDatabase` (or call `Calendar.put_time_zone_database/1`) before importing `DTSTART;TZID=...` events.

### The most values at once

Tempo refuses a value that asks for more than 10,000 values at once — the members of a set, the spans a mask or a selection is converted to, the occurrences of a recurrence — so that a short text cannot ask for work without end: `~o"2026Y{1..12}M{1..28}DT{0..23}H{0..59}M{0..59}S"` names 29 million seconds. The refusal is a `Tempo.ConversionError` whose reason is `:too_many_values`, and `Enum` and `Stream` still take such a value's values one at a time. The application may set the limit:

```elixir
# config/config.exs
config :ex_tempo, max_values_at_once: 100_000
```

## Livebooks

Interactive, runnable tours for [Livebook](https://livebook.dev):

* [![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Felixir-tempo%2Ftempo%2Fmain%2Flivebook%2Fgetting-started.livemd) **Getting started** — time as intervals: the sigil, resolutions, iteration, Allen relations, set algebra, and locale-aware formatting.

* [![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Felixir-tempo%2Ftempo%2Fmain%2Flivebook%2Ftempo_tour.livemd) **A tour of Tempo** — the whole surface in one pass: parsing, resolutions, arithmetic, comparison and formatting.

* [![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Felixir-tempo%2Ftempo%2Fmain%2Flivebook%2Fscheduling-workbook.livemd) **Scheduling** — free-busy algebra, bookable slots, arrival times that skip busy spans and weekends, and RFC 5545 recurrence.

* [![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Felixir-tempo%2Ftempo%2Fmain%2Flivebook%2Funcertain-dates-workbook.livemd) **Uncertain dates** — masks, one-of sets, margins, EDTF qualifications, and three-valued certainty.

## Talks and background

The [ElixirConf '22 talk](https://www.youtube.com/watch?v=4VfPvCI901c) introduces the core idea of a unified time type and builds toward intervals as the primary representation. The talk is still a good overview of the thesis; the library has evolved substantially since — full ISO 8601-2 support, set operations, cross-calendar comparisons, iCalendar import, and recurring events have all landed in the years that followed.

## Prior art

Tempo draws on several bodies of work:

* **Allen's Interval Algebra** — James F. Allen's 13 relations between intervals (`precedes`, `meets`, `overlaps`, `finished_by`, `contains`, `starts`, `equals`, and their inverses). [See the survey](https://ics.uci.edu/~alspaugh/cls/shr/allen.html). Tempo's interval relations and `overlaps?/2` / `contains?/2` predicates descend directly from this work.

* **Temporal databases and the chronon concept.** Jensen, Dyreson, and Tansel's *Consensus Glossary of Temporal Database Concepts* (1998) defines the *chronon* — an indivisible time unit whose resolution determines how the surrounding value is interpreted. Tempo's resolution (`Tempo.resolution/1`) is the direct analogue.

* **Eric Evans' "Exploring Time"** talk. Evans makes the case for considering time as an interval rather than an instant in a domain-driven-design setting. His framing influenced the earliest design sketches of Tempo.

* **PostgreSQL multirange types.** Postgres 14+ ships sorted, non-overlapping, coalesced interval sets. The result of a Tempo set operation follows the same conceptual model, and is computed by the same sweep-line algorithm.

* **Wojtek Mach's [`calendar_interval`](https://github.com/wojtekmach/calendar_interval).** A partial-but-elegant implementation of calendar intervals in Elixir. Concepts from this library informed Tempo's implicit-span semantics.

* **ISO 8601-2 / EDTF.** The 2019 extension to ISO 8601 formalises archaeological and approximate dates. The `unt-libraries/edtf-validate` conformance corpus — the only public test suite for EDTF — is exercised in full.

* **RFC 5545 (iCalendar) / RFC 7529 (RSCALE).** The iCalendar specification for RRULE, RDATE, EXDATE, VTIMEZONE. Tempo imports `.ics` data via `Tempo.ICal.parse/2`.

* **RFC 9557, the Internet Extended Date/Time Format (IXDTF).** The extended date-time format for annotations such as `[Europe/Paris][u-ca=hebrew]`. Supported in both parse and round-trip.

## Related links

Tempo implements or interoperates with these standards:

* [ISO 8601-1:2019](https://www.iso.org/standard/70907.html) — date and time representations: the base grammar for dates, times, durations, and intervals.

* [ISO 8601-2:2019](https://www.iso.org/standard/70908.html) — extensions: uncertain and approximate dates, unspecified digits, seasons, sets, and negative components.

* [EDTF](https://www.loc.gov/standards/datetime/) — the Library of Congress Extended Date/Time Format, aligned with ISO 8601-2.

* [RFC 9557](https://www.rfc-editor.org/rfc/rfc9557.html) — Internet Extended Date/Time Format (IXDTF): the `[zone]`, `[u-ca=…]`, and `[key=value]` suffixes and the critical `!` flag.

* [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339.html) — Date and Time on the Internet: Timestamps, the internet profile of ISO 8601.

* [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545.html) — iCalendar: `RRULE` recurrences and `VEVENT` parsing.

* [RFC 7953](https://www.rfc-editor.org/rfc/rfc7953.html) — Calendar Availability: `VAVAILABILITY` and `AVAILABLE`.

* [RFC 8984](https://www.rfc-editor.org/rfc/rfc8984.html) — JSCalendar.

* [BCP 47](https://www.rfc-editor.org/info/bcp47) — language and territory tags, used by the `u-ca` calendar and `u-rg` territory subtags.

* [Unicode CLDR](https://cldr.unicode.org/) — calendar, locale, and territory data (via Calendrical and Localize).

* [Allen's Interval Algebra](https://ics.uci.edu/~alspaugh/cls/shr/allen.html) — the 13 interval relations behind `Tempo.relation/2`.

Further reading:

* [RFC 3339 and ISO 8601](https://ijmacd.github.io/rfc3339-iso8601/) — a helpful visual crossref of the two.

* [Computerphile: Timezones](https://www.youtube.com/watch?v=-5wpm-gesOY) — an excellent primer on why timezones are hard.

* [Time words don't mean what you think](https://www.youtube.com/watch?v=TK-8gfqmFNo) — a fun look at the etymology of the words we use to describe time.

* [Computerphile: Why CPU Time ≠ Wall Clock Time](https://www.youtube.com/watch?v=xs5iOwkX9fU).

## Documentation

* [Migrating from Tempo 1.6 to 2.0](https://hexdocs.pm/ex_tempo/migration.html) — each change, with its 1.6 form and its 2.0 form.

* [Tutorial: build a booking-availability service](https://hexdocs.pm/ex_tempo/tutorial-booking-availability.html) — the journey-shaped introduction: one small system, every core concept.

* [Cookbook](https://hexdocs.pm/ex_tempo/cookbook.html) — recipe-format answers to common temporal questions.

* [When to use Tempo](https://hexdocs.pm/ex_tempo/when-to-use-tempo.html) — where the interval model earns its keep (and where it doesn't).

* [Building expressions](https://hexdocs.pm/ex_tempo/building-expressions.html) — rules and values built a step at a time, each step an expression.

* [Set operations](https://hexdocs.pm/ex_tempo/set-operations.html) — union, intersection, complement, difference, predicates.

* [Scheduling](https://hexdocs.pm/ex_tempo/scheduling.html) — recurrence, free-busy availability, and dependency (critical-path) scheduling.

* [Workdays and weekends](https://hexdocs.pm/ex_tempo/workdays-and-weekends.html) — territory-aware business-day arithmetic.

* [Holidays](https://hexdocs.pm/ex_tempo/holidays.html) — composing a real holiday calendar with workday logic.

* [iCalendar integration](https://hexdocs.pm/ex_tempo/ical-integration.html) — importing `.ics` schedules with metadata preserved.

* [Date rules](https://hexdocs.pm/ex_tempo/date-rules.html) — yearly dates written in words (`4th Thursday in November`, `easter -2`, `15 Nisan`) read into Tempo recurrences.

* [The date rule grammar](https://hexdocs.pm/ex_tempo/date-rule-grammar.html) — the reference for every part of a date rule and what it reads to.

* [Enumeration semantics](https://hexdocs.pm/ex_tempo/enumeration-semantics.html) — iterating across Tempo values and interval sets.

* [Interop](https://hexdocs.pm/ex_tempo/interop.html) — anchored and unanchored values, and bridging native Elixir types.

* [Pattern matching with sigils](https://hexdocs.pm/ex_tempo/pattern-matching-with-sigils.html) — destructuring Tempo values in function heads.

* [ISO 8601 conformance](https://hexdocs.pm/ex_tempo/iso8601-conformance.html) — what's supported from the standards.

* [Glossary](https://hexdocs.pm/ex_tempo/glossary.html) — every word Tempo's API and documentation use, with the one meaning each has.

* [RFC 5545 RRULE conformance](https://hexdocs.pm/ex_tempo/rfc5545_rrule_conformance.html) — recurrence-rule coverage, property by property.

* [Shared AST for ISO 8601 and RRULE](https://hexdocs.pm/ex_tempo/shared-ast-iso8601-and-rrule.html) — the internal representation that unifies both.

* [Temporal formalisms](https://hexdocs.pm/ex_tempo/temporal-formalisms.html) — how Tempo relates to Allen's algebra and the time-ontology literature.

* [Architecture](https://hexdocs.pm/ex_tempo/architecture.html) — the model as types, each algorithm in pseudo-code, the calendar and zone contracts, the errors and the cost of each operation, written for a reader porting or assessing the design.

The full documentation, every module and function with the guides above, is on [HexDocs](https://hexdocs.pm/ex_tempo).

## License

Tempo is licensed under the Apache License 2.0; see [LICENSE.md](https://github.com/elixir-tempo/tempo/blob/v2.1.1/LICENSE.md). Copyright © Kip Cole.
