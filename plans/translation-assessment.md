# Translating Tempo to Rust, Zig and Roc

**Status:** reference, 2026-10-16

This assesses whether Tempo can be translated to Rust, Zig and Roc keeping the integrity of the design and the public API as closely as possible, passing the same test suite and conformance, with documentation that serves every port. The user set two conditions: the Rust must be idiomatic and safe (no `unsafe` in Tempo's own code), and ICU is assumed for localization and for calendars in place of Localize and Calendrical. It was written against `main` at `508e981` (Elixir 1.20.4, OTP 29), from a mechanical census of the code, the tests and the documents (section 2) and from the current state of ICU4X, ICU4C, Zig and Roc as their own sources give it (section 4, with links).

## 1. Summary

**Rust: feasible, and the one to do first.** The design translates directly: the one struct is a struct over an enum of six forms, the laws and algorithms are integer arithmetic on positions, and nothing in the design needs `unsafe`, so Tempo's own crates can forbid it. The public API keeps its names, its arguments and its meanings; what changes is Rust's idiom, not Tempo's design: `Result` in place of the 45 `!` functions of `Tempo`, option structs in place of keyword lists (an unknown option becomes a compile error), iterators of `Result` for law 6, and a compile-time macro for the sigil's value context, with no counterpart for its match context. ICU4X 2.3 answers the core of the calendar contract (the day scale, a year's and a month's days, month codes with leap months, arithmetic with the day constrained, Easter) for 16 of the 26 calendars the census holds Tempo to. It does not answer the weeks of any calendar but ISO's, quarters, the weeks of a month, the bounds over all years, the cycle of years or solar terms, it has no public astronomy, and it cannot read a locale's words at all; its interval, relative-time and duration formatters are unstable or experimental. Those gaps, not the language, are the work: they need a calendar layer beside the port, as Calendrical is beside Tempo, or named refusals.

**Zig: possible, not now.** ICU4C covers more of the seams than ICU4X (every calendar's weeks, reading words, every formatter, zone transitions), and Zig calls it directly. Against that, the language is before 1.0 and each of its last three releases broke source, including removing `@cImport` in 0.17; it has no garbage collector, so Tempo's shared, recursive and endless expressions need an allocator in every signature and an owner for every result; and its errors carry no payload, so every refusal needs a diagnostics argument. The API keeps its names but not its shape, and the port is a standing cost at every Zig release.

**Roc: not feasible as a library under ICU, now.** On the language alone Roc fits the design best (immutable values, recursive tag unions, `Result`, list patterns that give the sigil's match context a counterpart). But Roc has no release, its compiler has just been rewritten, and a Roc package cannot call C: ICU would have to be supplied by the platform an application runs on, making Tempo a feature of one platform rather than a package, or the calendars and zone data would have to be written in Roc, which is a port of Calendrical too. Revisit after Roc 0.1.

**Across all three:**

* **The design is already portable.** The nine laws, the data model as sum and product types, the algorithms in pseudo-code, the calendar and zone contracts with their laws, the error taxonomy and the costs are written without Elixir in `guides/architecture.md`; the grammar is ABNF; five oracles are exported as JSON fixtures that Tempo's own tests read. This was done on 2026-10-15 for exactly this purpose and is the strongest finding of the census (section 3).

* **The same test suite** is the fixtures and the text corpora, which any port runs as they are, plus the suite's cases translated: 54 of the 80 test files test by ISO 8601 text and port as text; 26 files test the struct's fields or Elixir's `inspect` notation in places (52 lines), which do not port; 20 name a calendar, of which those ICU lacks cannot run; 19 test words and are re-baselined to ICU's CLDR. The fixtures lack the expected answers of most operations, and exporting the guides' examples and the census's walks as text fixtures would close most of that before a port begins (section 6).

* **The documentation** divides into a specification that serves every port as it is (architecture, grammar, conformance, glossary, design decisions, enumeration semantics), tutorials whose prose ports and whose examples need a block per language, and a few Elixir-only pages (section 7).

* **Nine decisions** are the user's before a port starts (section 8); the first is what to do about the calendar questions ICU does not answer.

## 2. What was counted

Every figure here is a count over the tree at `508e981`, made by script, not a sample. Code lines are lines that are neither blank, comment nor inside a `@doc`, `@moduledoc` or `@typedoc` heredoc.

### 2.1 The library

| Part | Files | Lines | Code |
|---|---|---|---|
| `lib/` in all | 73 | 28,632 | 15,183 |
| The engine, `lib/tempo/core/` (layers 0 to 3) | 31 | 12,407 | 7,915 |
| The reader, `Tempo.Reader` and its five parts | 7 | 2,110 | 1,468 |
| `Tempo.Writer` and `Tempo.Validate` | 2 | 1,071 | 740 |
| The `Tempo` module | 1 | 4,870 | 1,304 |
| Adapters: `RRule`, `Cron`, `ICal`, `JSCalendar` | 4 | 2,596 | 1,446 |
| Exceptions | 9 | 444 | 266 |
| Protocol implementations | 3 | 91 | 65 |

Documentation is 7,418 of the 28,632 lines, and 610 lines of it are `iex>` examples run as doctests.

### 2.2 The public surface

Read from the compiled documentation (`Code.fetch_docs/1`), not from the source:

* **30 public modules**, 9 of them exceptions, and 51 hidden ones (the engine, the reader's parts, six generated calendars of weeks, the protocol implementations).

* **275 public functions** by name and arity. `Tempo` has 150 of them, of which 45 are `!` forms of a function that returns `{:ok, _}` or `{:error, _}` and 23 are predicates; 25 of its functions take options.

* **9 exceptions**, each a named refusal with a reason (law 8), and 3 behaviours a consumer may implement: `Tempo.Clock`, `Tempo.Event.Resolver` and the calendar contract (by declaring Calendrical's behaviour).

### 2.3 What the code takes from its platform

| Construct | Sites | Where | What it becomes in a port |
|---|---|---|---|
| The calendar contract | 25 questions, one module | `Tempo.Calendar` | the seam to ICU's calendars (section 4.1) |
| Calls to Calendrical outside the contract | 5 functions | `Tempo.Calendar` | Easter, Orthodox Easter, the CLDR-name registry and its list of further names, locale-aware parsing (sections 4.2 and 4.3) |
| Calls to Localize | 13 functions, and `Localize.Calendar.ISO` as the implementation of `Calendar.ISO` | `Format`, `Territory`, `Workdays`, `Season`, `Tempo`, `Tempo.Calendar` | ICU's formatters, territory data and Gregorian calendar (section 4.2) |
| Calls to Astro | 3 functions | `Season`, `Event` | equinox, solstice, new moon (section 4.3) |
| The zone database | `Calendar.TimeZoneDatabase`, plus `Tz.PeriodsProvider` for the transition table | `Tempo.Zone` | a zone library (section 4.4) |
| `Stream` (lazy and endless sets) | 74 | 15 files | iterators or explicit state machines |
| Protocol implementations | 5 | `Enumerable`, `Inspect`, `String.Chars` for `Tempo` and `Tempo.Duration` | iteration, display and debug traits |
| Macros | 1 | the `~o` sigil, reading ISO 8601 text at compile time, in value and match context | a compile-time macro or nothing |
| Behaviours | 3 | `Clock`, `Event.Resolver`, `Zone.Transitions` | interfaces |
| `:persistent_term` | 1 cache | the zone transition table | a shared immutable cache |
| Process dictionary | 1 | the test clock (`Tempo.Clock.Test`) | an injected clock |
| Application configuration | 4 | the calendar implementations, the zone database, the clock, the work bound | configuration values or type parameters |
| Optional dependencies | 2 | `ical`, `jscalendar` (read with `Code.ensure_loaded?/1`) | optional features |
| `try`/`rescue`, processes, ETS, `apply/3` | 0 | | nothing to translate |

Nothing in the engine depends on BEAM concurrency, hot code loading or message passing. The engine is pure functions over one immutable recursive type, which is the shape all three languages can express.

### 2.4 The tests

| Measure | Count |
|---|---|
| Test files | 80, 14,325 lines, with 24 support files of 5,880 lines |
| Tests, as ExUnit counts them | 2,488 |
| Modules doctested | 22 |
| Of which: guide pages and livebooks run as tests | 28 and 12 |
| Of which: the totality check (`mix test --only total`) | 10, over every operation and every corpus value |
| Of which: the calendar census | 81, over 27 calendars |
| Language-neutral fixtures (`test/fixtures/conformance/`) | 5 JSON files, 2.7 MB, read by 5 test files |
| Text corpora | ISO 8601, ISO 8601 ranges and RFC 3339 lists, the EDTF corpus, iCalendar files, the 39 examples read from RFC 5545's text |

How much of the suite says something only Elixir can say, counted in the 80 test files:

| What a test uses | Files | Lines | Portable? |
|---|---|---|---|
| ISO 8601 text read with `~o` | 54 | 1,498 | yes: text in, text out |
| `Enum` over an expression | 54 | 353 | yes: iteration under law 6 |
| Elixir's `Date`, `Time`, `NaiveDateTime`, `DateTime` | 35 | 408 | as the target's own date types |
| A Calendrical calendar by name | 20 | 42 | only for the calendars ICU has (section 4.1) |
| Words in a locale (`to_string`, `to_relative_string`, `explain`) | 19 | 117 | re-baselined to ICU's CLDR |
| `inspect/1` output | 17 | 30 | no: Elixir's notation |
| `assert_raise` | 20 | 40 | as a panic or an error value |
| A `%Tempo{}` pattern on the struct's fields | 11 | 22 | no: representation |

### 2.5 The documents

27 guides of 9,074 lines with 478 Elixir blocks and 30 ABNF blocks; 6 livebooks; a 326-line README. Two of the guides were written for exactly this purpose on 2026-10-15: `guides/architecture.md` states the model in a notation of no language (the data model as sum and product types, the denotation, each algorithm in pseudo-code, the calendar and zone contracts with their laws, the nine errors, the cost of each operation), and `guides/iso8601-grammar.md` is the ABNF the reader implements. `plans/reference-architecture-review.md` set out what a port would need and the conformance fixtures are its answer.

## 3. What carries to any language unchanged

The design was made portable before this question was asked, and that is the strongest finding of the census:

* **The laws and the model.** The nine laws, the six forms, `Held` and `Part`, frames and integer positions, the half-open spans and law 9's written ends are stated in `guides/architecture.md` without Elixir. A port that implements that page implements Tempo.

* **The grammar.** `guides/iso8601-grammar.md` is the reader's specification, one production a function. A recursive-descent reader over bytes is the most portable kind of parser there is; nothing in it depends on NimbleParsec, which is gone.

* **The algorithms.** One sweep for every set operation, one four-comparison classifier for Allen's relations with the composition table derived from it, one expansion, one walk, one shift. Each is integer arithmetic on positions once a value is placed; none needs the BEAM.

* **The oracles.** `allen.json`, `set_operations.json`, `rrule.json`, `clock_changes.json` and `expressions.json` were exported so that "an implementation of the same architecture in any language can be held to them" (the fixtures' README), and Tempo's own tests read the same files.

* **The seams.** "Calendar calculations are the calendar's, zone data is the database's, and the words of a locale are Localize's. A port that keeps those three seams keeps the architecture" (`guides/architecture.md` section 9). Replacing Calendrical and Localize by ICU is a change at two of the three seams and nowhere else, so far as ICU can stand behind them, which section 4 measures.

## 4. ICU and the other dependencies, as they stand

Checked on 2026-10-16 against each project's own releases, documentation and source at its release tag; the sources are listed in section 4.6.

### 4.1 Calendars

The current releases are ICU4X `icu` 2.3.1 (2026-08-20, `icu_calendar` 2.3.0) and ICU4C 78.3 (2026-03-17), with ICU4C 79 at release candidate.

The census's 26 Calendrical calendars against ICU:

| Calendar | ICU4X 2.3 | ICU4C 78.3 |
|---|---|---|
| Gregorian, Julian, Buddhist, ROC, Japanese, Indian, Persian, Coptic, Ethiopic, Ethiopic Amete Alem, Hebrew | yes | yes; the Julian as a Gregorian calendar whose change is moved out of reach |
| Islamic civil and `tbla`, Umm al-Qura | yes, `Hijri` with the tabular and Umm al-Qura rules | yes |
| Chinese, Korean | yes, `EastAsianTraditional` | yes, `chinese` and `dangi` |
| Islamic observational, `rgsa` | no; the simulation rule is deprecated and is now data with a tabular fallback | `islamic` and `islamic-rgsa`, which compute, not observe from a place |
| Vietnamese, Japanese lunisolar | no | no |
| England's and Sweden's reforms | no | one Julian-to-Gregorian change (`ucal_setGregorianChange`), without England's change of new year in 1751–1752 |
| Julian with the year from 25 March, 1 March, 1 September or 25 December | no | no |
| ISO week calendar, NRF | no | no |
| Fiscal years (`Calendrical.FiscalYear`) | no | no |

ICU has 16 of the 26: no calendar of weeks, no fiscal calendar, no change of new year, no observational Islamic calendar, and not the two other East Asian calendars. Where ICU has a calendar, its algorithm is not Calendrical's, so agreement with Calendrical over the census's years is to be measured, not assumed.

The contract of `guides/architecture.md` section 6.1, with the further questions `Tempo.Calendar` asks (25 in all), against ICU:

| Question | ICU4X 2.3 | ICU4C 78.3 |
|---|---|---|
| The day number of a date, and back | `Date::to_rata_die`, `from_rata_die`: the same scale up to a constant | the Julian day field |
| Whether a date exists | `Date::try_new` with `Overflow::Reject` | fields set on a strict calendar |
| The days of a year and of a month | `days_in_year`, `days_in_month`, `months_in_year` | the actual maximum of a field |
| The calendar's own weeks: `week/2`, `week_of_year/3`, weeks in a year | the ISO calendar's only; other calendars' weeks were hidden in 2.0 | every calendar, with a first day and a minimal days |
| The weeks of a month | no | the week-of-month field |
| A quarter and the quarter of a date | no | no |
| The day of the week | `weekday` | the day-of-week field |
| A traditional month and back | Temporal's month codes (`M05L`) and `MonthInfo` | the leap-month field beside the month |
| Shifting a date | `try_added_with_options`, with the day constrained | `ucal_add` |
| The fewest and most months of any year, days of a month in any year | no | the limits of a field, not of a month |
| The years in the calendar's cycle | no | no |
| Leap year | `is_in_leap_year` | no general call in the C API |
| The CLDR name | `AnyCalendarKind` | the calendar's type |
| A solar term | no | no |

What ICU4X does not answer (weeks of every calendar but ISO's, quarters, the weeks of a month, the bounds over all years, the years in a cycle, solar terms) is calendar calculation. The project's rule puts it in the calendar library, never in Tempo, and that rule is what makes the port's seam the same as Elixir's. A port therefore needs a calendar layer beside it, which implements the contract over ICU and answers what ICU does not, as Calendrical does for the Elixir library (decision 1).

**Years.** ICU4X builds a date from fields in −9999 to 9999, and from arithmetic and `try_from_fields` to about ±999,999; ICU4C's limit is about ±5.8 million years. Calendrical places any year Elixir's integers hold, and the tests and guides write years beyond all of these in 15 places (`Y-170000002`, `Y17E8`, from the EDTF corpus). A port reads and writes them; it cannot place them through ICU, and refuses by name (decision 4).

### 4.2 Words in a locale

| What Tempo says or reads | Localize today | ICU4X 2.3 | ICU4C 78.3 |
|---|---|---|---|
| A date, a time, a date and time | `Localize.Date`, `Time`, `DateTime` | `icu_datetime`, stable | `udat` |
| An interval | `Localize.Interval` | `icu_datetime::range`, new in 2.3, behind the `unstable` feature | `udtitvfmt` |
| A relative time (`to_relative_string/2`) | `Localize.DateTime.Relative` | `icu_experimental` 0.6, all of it unstable | `ureldatefmt` |
| A duration | `Localize.Duration` | `icu_experimental` 0.6 | not verified |
| A list (`explain/1`, words for sets) | `Localize.List` | `icu_list`, stable | `ulistfmt` |
| A territory's weekdays and weekend | `Localize.Calendar` | `WeekInformation`, stable | the calendar's week data |
| The territory of a locale | `Localize.Territory` | `icu_locale` | `uloc` |
| A territory's hemisphere (seasons) | `Localize.Territory.Hemisphere` | no; it is not CLDR data | no |
| Reading words: `Tempo.parse/2` | `Calendrical.parse/2` over Localize | none: ISO 8601 and RFC 9557 only (`ixdtf`) | `udat_parse`, lenient |

Everything Tempo writes in words is in ICU4C. In ICU4X, dates, times and lists are stable, intervals are unstable, relative times and durations are experimental, and reading a locale's words does not exist. ISO 8601 and RFC 9557 reading are Tempo's own reader and are not affected. The words a test expects are re-baselined in any case: Localize's `main` is on CLDR 49, and ICU4X moves to CLDR 49 only in its unreleased 2.4.

### 4.3 Events and astronomy

* **Easter** is in ICU4X: `calendrical_calculations` 0.2.4 has `gregorian::easter` and `julian::easter`, and `icu_calendar`'s `Gregorian` and `Julian` expose them. ICU4C has none.

* **Solar terms, equinoxes, solstices and new moons** are in neither ICU's public API: ICU4X's astronomy module is private to `calendrical_calculations`, though its Chinese calendar uses it. Tempo asks Calendrical for solar terms and Astro for the rest (seasons by the sky, the events of `Tempo.Event`).

* **A territory's hemisphere**, which decides whether June is summer, is Localize's own data and not CLDR's.

### 4.4 Zones

ICU's localization and calendars are not its zone database, but ICU has one, and the port's zone layer is the same table of a zone's changes Tempo now builds (decision 73), with six questions answered by search in it (`guides/architecture.md` section 6.2).

* **Rust.** `icu_time` 2.3 names and formats zones and says it "does not ship time zone offset information". The offsets are in `zoneinfo64` 0.3.0, from the ICU4X project, which reads ICU4C's zone data and answers the offset at an instant, a wall reading's one, two or no offsets with the transition, and the previous and next transitions: the questions Tempo asks. `jiff` 0.2.38 (2026-10-06, TZDB 2026e bundled, not at 1.0) answers the same (`to_offset`, `to_ambiguous_zoned`, `preceding`, `following`) and converts to and from ICU4X through `jiff-icu`.

* **Zig.** ICU4C answers through `ucal_getTimeZoneTransitionDate` and `ucal_getTimeZoneOffsetFromLocal`.

### 4.5 The languages

* **Rust** is stable; ICU4X 2.3 needs Rust 1.88. On safety: ICU4X's public API is safe, but its crates do not forbid `unsafe` (`icu_calendar` has one `unsafe` block; `zerovec` defines `unsafe` traits; recent changelogs record undefined-behaviour fixes in `tinystr` and `resb`), and `jiff` uses `unsafe` in its zone and buffer code. Tempo's own crates can forbid `unsafe` and need none; no Rust calendar and zone stack is free of `unsafe` in its dependencies (decision 5).

* **Zig** 0.17.0 was released on 2026-10-01 and has no date for 1.0. The last three releases each broke source: 0.15 rewrote the I/O interfaces and removed `async`; 0.16 made I/O an interface passed to every call and deprecated `@cImport`; 0.17 removed `@cImport` (C headers are translated by a package through the build system), moved package management into the build system and renamed `std.builtin`. There are ICU4X bindings (`icu4zig`, untagged) and a zone-aware date library (`zeit` 0.10.0); ICU4C is reached through its C headers.

* **Roc** has no release: the README says it is not ready for 0.1, the last tag is `alpha4-rolling` (2025-08-26), and most users run nightlies. The compiler has been rewritten in Zig; static dispatch has replaced abilities. A package is an archive named by its hash, and "must" reach other languages through "primitives provided by the platform": a package cannot call C. There is no Roc ICU or CLDR package. `roc-time` (begun 2026-09-05) is an interval-based library in pure Roc that names Tempo as its inspiration; it is not a port of Tempo's API.

### 4.6 Sources

* ICU4X: [releases](https://github.com/unicode-org/icu4x/releases), [`icu_calendar` calendars](https://docs.rs/icu_calendar/2.3.0/icu_calendar/cal/index.html), [`AnyCalendarKind`](https://docs.rs/icu_calendar/2.3.0/icu_calendar/cal/enum.AnyCalendarKind.html), [`Date`](https://docs.rs/icu_calendar/2.3.0/icu_calendar/struct.Date.html), [`WeekInformation`](https://docs.rs/icu_calendar/2.3.0/icu_calendar/week/struct.WeekInformation.html), [`icu_time` zones](https://docs.rs/icu_time/2.3.0/icu_time/zone/index.html), [`icu_experimental`](https://docs.rs/icu_experimental/0.6.0/icu_experimental/).

* Rust zones and Temporal: [jiff](https://github.com/BurntSushi/jiff), [temporal_rs](https://github.com/boa-dev/temporal), [rust_icu](https://github.com/google/rust_icu).

* ICU4C: [downloads](https://unicode-org.github.io/icu/download/), and `icu4c/source/i18n/calendar.cpp`, `gregoimp.h` and `unicode/*.h` at tag `release-78.3`.

* Zig: [releases](https://ziglang.org/download/index.json), [0.17.0 release notes](https://ziglang.org/download/0.17.0/release-notes.html).

* Roc: [repository and language reference](https://github.com/roc-lang/roc).

## 5. The design in each language

Each subsection takes the data model of `guides/architecture.md` section 2 and the platform constructs of section 2.3 above, and says what each becomes.

### 5.1 Rust

The model is a direct translation, and every part of it is expressible in safe Rust; nothing in the design calls for `unsafe`, and the Tempo crates can carry `#![forbid(unsafe_code)]`.

```rust
pub struct Tempo {
    form: Form,
    calendar: Calendar,                      // a handle on an implementation of the calendar contract
    zone: Option<Zone>,
    shift: Option<Shift>,
    qualifications: Option<Qualifications>,
    metadata: Metadata,
}

pub enum Form {
    Value(Units),                            // ordered (Unit, Held) pairs, coarsest first
    Span(End, End),
    Every { first: Arc<Tempo>, bound: Bound, rule: Option<Selection> },
    All(Members),
    One(Arc<[Tempo]>),
    When(Arc<Tempo>, Arc<[Condition]>),
}

pub enum End { Value(Arc<Tempo>), Length(Duration), Open }
pub enum Members { Listed(Arc<[Tempo]>), Lazy(LazyMembers) }
```

* **Sharing.** Elixir shares immutable subterms for nothing and Tempo relies on it: an end, a recurrence's first span and a set's members are passed on whole. `Arc` for the recursive parts makes a clone a counter increment and keeps `Tempo: Send + Sync`.

* **Lazy sets.** `{:all, stream}` is a description that can be run again, not a consumed iterator. In Rust it is a shared generator, `Arc<dyn Fn() -> Box<dyn Iterator<Item = Result<Tempo, Error>>> + Send + Sync>`, which is safe and ordinary. Everything that needs every member refuses a lazy set without a window, as it does now.

* **Errors.** `{:ok, _} | {:error, exception}` is `Result<T, Error>` with `Error` an enum of the nine refusals and their reasons. The 45 `!` functions of `Tempo` have no Rust counterpart, since `?` and `expect` are the idiom; that is the one large, mechanical difference in the surface. The project's rule that a predicate may raise has no idiomatic Rust reading for a library: predicates return `Result<bool, Error>`, or panic on invalid input by documented contract. That is decision 8.

* **Options.** A keyword list becomes an options struct with `Default` (`ShiftOptions { skipping: Some(free), ..Default::default() }`). Law 8's "an option a function does not take is an error" becomes a compile error, which is stronger than today.

* **Enumeration.** Law 6 is `IntoIterator for &Tempo` yielding `Result<Tempo, Error>`, since a walk can be refused part way (`too_many_values`, a gap). `Enum.member?/2` as cover is a `contains` method.

* **Text.** `String.Chars` is `Display` (the ISO 8601 text), `Inspect` is `Debug`. The `~o` sigil in value context is a procedural macro, `tempo!("2026-06-15")`, which can run the same reader at compile time from a shared crate and refuse bad text as a compile error, exactly as the sigil does. In match context it has no Rust counterpart: a macro cannot write a pattern that reaches through `Arc` and a vector's prefix. `guides/pattern-matching-with-sigils.md` (58 uses of the sigil) does not port; a `starts_with` method does what it does at run time.

* **The calendar.** A trait for the contract, implemented over ICU4X's calendars, and open to a consumer's own type, which is how `guides/custom-calendars.md` ports. The project's rule that a calendar is a module and never a CLDR type holds by construction: ICU4X's calendar kind is a different type from a calendar, and the only place a kind becomes a calendar is the `[u-ca=…]` suffix.

* **Metadata.** Elixir's metadata is a map of any terms, merged by `:first`, `:second`, `:merge` or a function. Rust needs a value type for it: a map of strings to a small JSON-like enum, or a type parameter on `Tempo`, which would reach every signature. The first is recommended.

* **Elixir's own types.** `from_date/1`, `to_datetime/1` and their kin convert to and from `Date`, `NaiveDateTime` and `DateTime`. Rust has no standard date type; the conversions become `From`/`TryFrom` implementations for the types of the crates the port depends on (ICU4X's dates, the zone library's instants), behind features.

* **Configuration.** The four application settings become a configuration value passed where needed or a builder on the entry points; the process-dictionary test clock becomes an injected `Clock`.

* **Positions.** A tick is a microsecond from 0000-01-01, which fits `i64` to about ±292,000 years. ISO 8601-2 and EDTF write years far past that (`Y-170000002`, `Y17E8`; 15 places in the tests and guides), which Elixir's integers place without thought. A port places them in `i128` or refuses them by name, and ICU's own range of years (section 4.1) makes refusal the only meaningful choice (decision 7).

* **The composition table** is derived when the module compiles from the classifier by placing three spans every way on eight points. In Rust this is a `const fn` or a build script, and the table remains a check rather than a source.

### 5.2 Zig

The model translates, and Zig's comptime is a good fit for parts of it; the cost is in memory, errors and the stability of the language.

* **Forms** are a tagged union, `union(enum) { value: Units, span: Span, every: Every, all: Members, one: []const Tempo, when: When }`, recursive through pointers.

* **Memory is the main cost.** Tempo's values share subterms, sets can be endless, and an operation's result reuses its operands' ends. Zig has no garbage collector and no reference counting in its standard library, so every function that builds an expression takes an allocator and every result has an owner: an arena per call that the caller frees, or reference counts written by hand. Every public signature gains an allocator, which changes the shape of the API though not its names.

* **Laziness without closures.** An endless set is a struct with a `next` function and its state, made generic through a pointer and a table of functions, as the standard library's `Allocator` is. It is what Elixir's `Stream` does, written by hand for each kind of lazy set.

* **Errors carry no payload.** A Zig error is a tag. Law 8's refusals carry a reason and their context (where in the text a parse failed, which two frames), so each fallible function also takes a diagnostics argument, the pattern `std.json` uses. The nine errors survive; their shape changes.

* **ICU through C.** Zig calls ICU4C's C API directly, without bindings to write by hand. ICU4C's calendar is a stateful object (set a moment, read fields; set fields, read a moment), so the adapter is more code per question than over ICU4X (section 4.1).

* **comptime** can run a reader that does not allocate at run time, so a literal can be checked when the program is compiled, which is the sigil's value context. There is no match context.

* **The language is not stable.** Zig is before 1.0 and its releases break source compatibility (section 4.5). A port of 15,000 lines of Elixir becomes a standing maintenance cost at every Zig release.

### 5.3 Roc

Roc's model is the closest of the three to the design: immutable values, structural equality, tag unions that may be recursive, records, `Result`, and pattern matching with list patterns (so the sigil's match context has a counterpart, which neither Rust nor Zig gives). On the language alone, Roc would preserve the design best.

Three things stand against it now:

* **No foreign calls from a package.** In Roc, everything outside pure Roc is provided by the platform the application runs on. A Roc package cannot call ICU. A Tempo in Roc either requires a platform that exposes ICU's calendars, formatters and a zone database (and is then usable only on that platform), or carries its calendars and zone data in pure Roc, which is a port of the calendar library as well, not an assumption of ICU.

* **Endless sets** need functions stored in data. Roc has closures; whether its new compiler holds them in recursive data reliably is to be proved before the model is committed to.

* **The language and its compiler are not released** (section 4.5). There is no stable version to port to, and the compiler has only just been rewritten.

## 6. The same test suite and conformance

"The same test suite" can be read three ways, and they differ in what they prove.

* **The conformance fixtures, run by each port.** This exists. A port reads the five JSON files and the text corpora (533 ISO 8601 texts, 81 ISO 8601 ranges, 59 RFC 3339 texts, the EDTF corpus, 6 iCalendar files, RFC 5545's own examples from `standards/rfc/rfc5545.txt`) and holds itself to them, and Tempo's own tests read the same files. Under ICU the set-operations fixture's Hebrew line and the clock-change days are also a first check that ICU's Hebrew calendar and the port's zone database agree with Calendrical and `tz`.

* **The suite's cases, translated.** The census of section 2.4 says how much of it is Elixir only: 54 of 80 files test by ISO 8601 text, which ports as text; 11 files (22 lines) match the struct's fields and 17 (30 lines) compare `inspect/1` output, which do not port and are representation tests in any case; 35 files (408 lines) use Elixir's date types, which become the port's; 19 files (117 lines) test words, which must be re-baselined to the CLDR version ICU ships; and 20 files (42 lines) name a Calendrical calendar, of which those ICU lacks cannot be run (section 4.1). The 22 doctested modules become Rust doctests or Zig test blocks naturally; the guide and livebook runners (40 tests) become a runner of each port's own guide examples.

* **The Elixir suite itself, run against a port.** For Rust and Zig, a port's core can be loaded into the BEAM as a native library (Rustler, whose API is safe Rust, or Zigler) behind the Elixir API, and the existing 2,488 tests run unchanged. This proves the engine against the whole suite during a port, one module at a time, and measures the ICU gap exactly, since every test that names a calendar ICU lacks or a word CLDR changed fails by name. It does not test the port's own public API, and it is a means, not the conformance.

What the fixtures lack today is the one thing a port needs most: answers. `expressions.json` lists the cells that refuse and says that every other cell answers with a value, without the value, because every answer would be about 20 MB and a golden file, which the project has retired. For a port, the answers of the expressions written by hand to each operation (not the generated ones) are the acceptance test the guides are for Tempo. Two cheaper exports would close most of it: **the guides' examples as fixtures** (each example's input, operation and printed answer, 478 Elixir blocks), and **the census's walks and selections** (the extent and the members of each full form in each calendar, as ISO 8601 text). Both are text, so they are language-neutral and do not freeze an implementation's representation.

Two oracles must be rebuilt in each language rather than exported: the grammar's generator and mutator (`test/support/grammar/`, 37 production families), which are property tests and become `proptest` in Rust, and the calendar laws of `guides/architecture.md` section 6.1, which each port runs against every calendar it supports, ICU's included.

## 7. Documentation

The documents divide cleanly.

* **Language-neutral already**: `guides/architecture.md` (the model, the algorithms, the contracts, the errors, the costs), `guides/iso8601-grammar.md` (the ABNF), the conformance guides for ISO 8601 and RFC 5545, the glossary, `design-decisions.md`, `enumeration-semantics.md`, `temporal-formalisms.md`, `falsehoods.md`, `uncertain-dates.md` in its prose, and the fixtures' README. These serve every port as they are, and together they are the specification.

* **Neutral in prose, Elixir in examples**: the tutorials and cookbooks (`cookbook.md`, `holiday-cookbook.md`, `set-operations.md`, `selection.md`, `workdays-and-weekends.md`, `tutorial-booking-availability.md` and the rest). The project's three-part example shape (named bindings, a pipeline of set-algebra and predicate verbs, a prose translation) carries to Rust's method chains with little change and to Roc's pipelines with none; to Zig less well, since every call takes an allocator. The prose translation in each callout is the part that is the same in every language. Single-sourcing the prose with an example block per language is the way to keep one set of guides; the examples' answers belong in the fixtures (section 6), so each language's examples are tested against the same answers.

* **Elixir only**: `pattern-matching-with-sigils.md`, `interop.md` (Elixir's date types), `migration.md`, `ai-assistance.md`, the livebooks.

## 8. Decisions a port needs from the user

Each says what stays the same, what the question is, and a recommendation. None changes the Elixir library.

1. **The calendar questions ICU4X does not answer.** The contract, its laws and Tempo's rule that it does no calendar arithmetic stay. ICU4X does not answer the weeks of any calendar but ISO's, quarters, the weeks of a month, the bounds over all years, the cycle of years or solar terms (section 4.1). Either a calendar crate beside the port implements the contract over ICU4X and answers these, as Calendrical does beside Tempo, or the port refuses them by name for every calendar but the ISO one. **Recommended:** the calendar crate, since weeks and quarters of a Hebrew or Chinese date are in the guides; it is also where the calendars ICU lacks would go.

2. **The ten calendars ICU does not have** (section 4.1: the calendars of weeks, the fiscal years, the reforms, the Julian with another new year, the Vietnamese and Japanese lunisolar, the observational Islamic). Tempo's handling of a calendar it is given stays. **Recommended:** none ported until a consumer asks for one; the census and the 20 test files that name them run for ICU's 16, and a calendar the port does not have is an `InvalidCalendarError`.

3. **Reading a locale's words in Rust.** Reading ISO 8601 and RFC 9557 is Tempo's own and stays whole. ICU4X cannot read "1 February 2024"; `rust_icu` (active, 5.8.0) can, through ICU4C, at the price of a system ICU4C, a second ICU beside ICU4X and `unsafe` FFI in the dependencies. **Recommended:** `parse/2` reads ISO 8601 only in the Rust port, and the words wait for ICU4X.

4. **Solar terms, equinoxes, solstices, new moons and hemispheres.** Easter stays, from ICU4X. The rest is in neither ICU's public API, and a hemisphere is not CLDR data (section 4.3). The choices are to write up a request that ICU4X make its astronomy public (for the user to file, as with any upstream), to port Astro as a crate beside the port, or to refuse solar-term events and astronomical seasons by name. **Recommended:** the write-up, and named refusals until it lands; a hemisphere table belongs with the territory data of the calendar crate of decision 1.

5. **What "safe Rust" covers.** Tempo's own crates forbid `unsafe`, which is achievable and recommended. ICU4X and `jiff` contain `unsafe` in their implementations behind safe APIs (section 4.5), and no Rust calendar and zone stack is free of it. If the requirement covers the dependency tree, it cannot be met with ICU in Rust. **Recommended:** the requirement applies to Tempo's crates, and the dependencies' `unsafe` is a matter for review when one is added.

6. **Unstable ICU4X formatters.** Words for dates, times and lists are stable. Words for intervals (behind ICU4X's `unstable` feature) and for relative times and durations (`icu_experimental`) are not. **Recommended:** `to_string/2` of an interval, `to_relative_string/2` and duration words are behind a feature of the port that says they are unstable, rather than refused.

7. **Years beyond ICU's range.** The port reads and writes every year Tempo does. ICU4X places years to ±9,999 from fields and about ±999,999 by arithmetic; ICU4C to about ±5.8 million; a microsecond in `i64` to about ±292,000. **Recommended:** positions stay `i64` microseconds, as `guides/architecture.md` states the precision model, and a year the calendar cannot place is a refusal by name (`InvalidDateError`, out of range).

8. **The zone library for Rust and predicates on invalid input.** The six zone questions and the transition table stay. `zoneinfo64` reads ICU's own zone data; `jiff` is the more used and bundles the database (section 4.4). Elixir predicates raise on invalid input; the Rust ones return `Result<bool, Error>` or panic by documented contract. **Recommended:** `jiff`, with `jiff-icu` at the border to ICU4X; `Result<bool, Error>`, since a Rust library does not panic on its caller's data.

9. **The order of work and the parity harness.** **Recommended:** Rust first; Zig after its 1.0 and Roc after its 0.1, each reassessed then; the Elixir suite run against the Rust core through Rustler while the engine is ported (section 6), retired once the port's own tests and the fixtures cover it.

## 9. The first step, if there is to be one

Port the core's lowest layers to Rust and run the fixtures that need nothing more: `Tempo.Unit`, the calendar adapter over ICU4X with the seven laws as property tests against every ICU calendar, `Tempo.Zone` over the zone library, `Tempo.Scale`, `Tempo.Allen` with `allen.json` (which needs nothing else, its spans being on a line of integers), and `Tempo.Algebra` with `set_operations.json`; then `Tempo.Walk` with `clock_changes.json`. Those modules are 2,004 lines of the engine's 7,915 of code; the set-operations fixture also needs the reader, the writer and `Tempo.Spans` for plain values and spans, which is a part of each. The step exercises both seams ICU and the zone library stand behind, and it gives a measured ratio of Rust to Elixir lines and of time per operation, from which the rest can be estimated rather than guessed. Before it, export the answers of section 6, since every later step is held to them.
