# A formal grammar for the parser

**Status:** in progress, 2026-10-06

Deferred by the user on 2026-10-04, who is wary of the speed a generalised ABNF parser would lose, and taken up in part on 2026-10-06: a generator pilot scoped to sets and ranges, as test support, with the tokenizer untouched. What it built and found is under "The pilot on sets and ranges" below. The grammar files, the recogniser and the standard's examples are not started, and are still the user's to weigh.

What is chosen below keeps the tokenizer as it is and uses the grammar's recogniser as an oracle in test support, so the parser's speed is not at stake in it; generating the tokenizer from the grammar is the option that would cost speed, and it is set aside under Options considered.

Tempo's parser is checked today by examples someone thought to write. This plan gives it a written grammar, transcribed from ISO 8601 clause by clause, and tests that hold the parser to that grammar in both directions, so a parse defect is found by a generator in CI rather than by accident. It starts with a pilot on ISO 8601-1 clause 5, and decides the rest on what the pilot finds.

## The problem

Parse defects are still turning up after months of work, and each one was found by hand while fixing something else. Those fixed on 2026-10-03, and those open in `TODO.md` that day, fall into four classes.

| Class | Examples | Standing |
|---|---|---|
| An earlier alternative takes the text | `09.5` tokenized as a century, `2026-06-15/20` reading `20` as a century, `0S1` in `FL1KT10H0M0S1IN` | First fixed, others open |
| A form no combinator reads | `6MT10H`, `{2020/2021,2023/2024}`, `{2026-06-15?,2026-06~}`, `2018Y9MTLT8H20MN3I` | First three fixed; the last is a divergence the conformance guide describes |
| Accepted, then failing later | `20.5C`, `1XC`, `{19,20}C` raised after tokenizing | Fixed |
| Written but not read | A qualified set written per member, `45.{0..9}S` | Fixed |

Three facts about the parser explain why the suite did not find them.

* **Ordered choice hides alternatives** — the tokenizer is 2,917 lines of NimbleParsec in `lib/iso8601/tokenizer/` and `lib/iso8601/tokenizer.ex`, with 85 calls to `choice` and 23 lookaheads, and `lib/iso8601/parser.ex` is 787 more. `choice` takes the first alternative that matches, so the order of alternatives decides which reading wins and nothing reports an alternative that can no longer be reached.

* **The tests are examples** — the 18 files under `test/tempo/iso8601/` hold 259 tests, and `test/support/edtf_corpus.ex` the test corpus of `unt-libraries/edtf-validate`. One property test, `test/tempo/range_expansion_property_test.exs`, already works the way this plan proposes: it generates sets and ranges as data, writes them as ISO 8601 text and holds the result to an independent reference. It covers one corner of the language, and nothing generates the rest.

* **Nothing states what should parse** — the grammar exists only as the combinators. `guides/iso8601-conformance.md` lists what is supported by hand, and no test ties a clause of the standard to the text it defines, so coverage cannot be measured.

Round trips do not close the gap: parsing what `inspect/1` wrote and comparing cannot see a misreading that is consistent with itself.

## What the standard gives us

Neither part of ISO 8601:2019 contains a grammar. A search of both documents finds no ABNF, BNF or production rules. What they give is three things.

* **Representation templates** — each form is written as a sequence of named components and literal separators, with the components defined in the symbols clause (3.2 of each part). Clause 12 of Part 2 goes further and writes its selection rules almost as productions. These transcribe into a grammar rule by rule.

* **Examples** — 133 lines marked `EXAMPLE` in Part 1 and 440 in Part 2, by a count of the extracted text. Each carries an expression and the reading the standard intends.

* **Choices left to agreement** — about a dozen passages (nine in Part 1 and two in Part 2 by a text search) leave a choice to the parties exchanging the data: the digits of an expanded year, among others. A grammar has to make each choice, and the choices are ours.

| Document | Clause | Example lines |
|---|---|---|
| Part 1 | 3 Terms and symbols | 16 |
| Part 1 | 4 Fundamental principles | 22 |
| Part 1 | 5.2 Date | 24 |
| Part 1 | 5.3 Time of day | 23 |
| Part 1 | 5.4 Date and time of day | 30 |
| Part 1 | 5.5 Time interval | 12 |
| Part 1 | 5.6 Recurring time interval | 6 |
| Part 2 | 3 Terms and symbols | 5 |
| Part 2 | 4 Extensions to components and units | 51 |
| Part 2 | 5 Grouped time scale units | 30 |
| Part 2 | 6 Set representation | 23 |
| Part 2 | 7 Explicit representation | 39 |
| Part 2 | 8 Qualification | 64 |
| Part 2 | 9 Unspecified digits | 23 |
| Part 2 | 10 Extended time intervals | 23 |
| Part 2 | 11 Explicit duration | 19 |
| Part 2 | 12 Selection | 39 |
| Part 2 | 13 Repeat rules | 17 |
| Part 2 | 14 Arithmetic | 21 |
| Part 2 | Annex A, the EDTF profile | 54 |
| Part 2 | Annexes B, C and D | 32 |

Two neighbouring specifications do publish ABNF and are copied rather than transcribed: RFC 3339, a profile of Part 1, and RFC 9557 (IXDTF), whose suffix `Tempo.Iso8601.Tokenizer.Extended` reads.

The standard's PDFs are copyrighted and kept out of the repository (`papers/iso8601_specs/` is in `.gitignore`), so CI cannot read them. Whatever is taken from them is extracted once, locally, and committed as data. The grammar is our own statement of the syntax, not a copy of the standard's text.

## What validated means here

`Tempo.from_iso8601/1` gives one of three outcomes for a text: a value, a `Tempo.ParseError`, or another error (`Tempo.InvalidDateError` for 30 February, which is well formed and names no date). A grammar speaks only to the first distinction, so the properties are stated with all three.

* **Complete** — every text the grammar derives is read, or is refused by an error other than `Tempo.ParseError`. Forms Tempo deliberately does not support are marked in the grammar and left out.

* **Sound** — every text Tempo reads is in a grammar: ISO 8601, RFC 9557, or Tempo's own extensions. Nothing is accepted by accident.

* **One reading** — a text with two derivations has an entry in a table of readings that says which one Tempo takes, and Tempo takes it.

* **Right reading** — a value written in each spelling the standard allows reads back as that value, and the spellings of one value (`19850412`, `1985-04-12`, `1985Y4M12D`) read equal.

* **Readable output** — everything `inspect/1` and `Tempo.to_iso8601/1` write is in a grammar and reads back equal.

* **The standard's examples** — every example in both parts reads as the standard says, is marked as a deliberate divergence, or is marked unsupported.

This is not a proof. That a hand-written parser and a context-free grammar accept the same language cannot be established by testing, and is not decidable in general. Transcribing the standard's prose into rules is a human step: it can be reviewed clause by clause, and cannot be checked by machine. What the properties give is agreement on every form up to a bound for single values, randomised agreement for nested forms, and an account of every example. Meaning beyond syntax, such as which days a week date names, stays with `Tempo.Validation` and Calendrical and their own tests.

## Design

### The grammar files

A `grammar/` directory at the repository root holds one ABNF file (RFC 5234, with the case-sensitive strings of RFC 7405) for each source, so what is ISO and what is ours is a matter of which file a rule is in.

* **`iso8601-1.abnf`** — clause 5 of Part 1.

* **`iso8601-2.abnf`** — clauses 4 to 13 of Part 2.

* **`rfc9557.abnf`** — the IXDTF suffix, copied from the RFC under the IETF Trust's terms for code components, which are to be checked when it is copied.

* **`tempo.abnf`** — Tempo's extensions: the position designator `I`, the week start `q`, computed events `e`, the traditional month `m`, the calendar week `w`, exclusions `^`, and the forms `inspect/1` writes that no standard defines.

Each rule carries a comment naming its clause and its standing, which the reader parses.

```abnf
; @clause 8601-1:5.2.2.1 @standing supported
calendar-date-complete-extended = year %s"-" month %s"-" day
```

ISO designators are case-sensitive in Tempo (`M` and `m`, `W` and `w`), and a quoted string in ABNF is not, so every literal is written `%s"…"` or as a character code. The start symbols match the tokenizer's entry points: the whole language, and the date, time, date and time, interval and duration profiles.

### The reader, the recogniser and the generator

Three pieces of test support under `test/support/grammar/`, none shipped in the package.

* **The reader** — parses the ABNF subset the files use into a rule table, with each rule's clause and standing.

* **The recogniser** — matches a text against a rule by trying every alternative, memoised, and returns every way the text derives. It is a recogniser for the context-free grammar itself, so it has no ordered choice to hide an alternative, and it shares no code with the tokenizer.

* **The generator** — derives texts from a rule as a `StreamData` generator, so failures shrink. Numeric components take representative values (the least, the greatest, and the boundaries the standard names), and each component's whole range is covered on its own. Single values are enumerated exhaustively by form; compositions (an interval of two date and times, a set of intervals) are sampled.

The hex packages were checked on 2026-10-03 and none serves as the recogniser. `abnf_parsec` 2.1.0 builds its parsers on NimbleParsec, which brings ordered choice back and is the library under test. `ex_abnf` 0.3.0 and `abnf2` 0.1.4 were last released in 2017 and 2018.

### The tests

| Test | Property | Method |
|---|---|---|
| Derived texts parse | Complete | Generator against `from_iso8601/1` |
| Read texts derive | Sound | Mutations of derived texts, and the existing corpora, against the recogniser |
| Readings | One reading | Texts with two derivations against the table of readings |
| Spellings | Right reading | A value written by template in each form, read, compared |
| Output | Readable output | `inspect/1` and `to_iso8601/1` of generated values against the recogniser |
| Examples | The standard's examples | A table of expression, clause and reading |

Mutations are single edits of a derived text: a character dropped, doubled or swapped, a designator replaced by another, a separator removed. A mutation the recogniser rejects and Tempo reads is a soundness defect; one both accept is fine.

The spellings test writes values with small template writers kept beside the grammar, one for each rule that denotes a value, and never with `inspect/1`. A check fails the suite when a value rule has no writer, so the semantic side cannot fall behind the grammar.

### The standard's examples

One data file, `test/support/grammar/examples.exs`, with a row for each example: the part, clause and example number, the expression, the reading as Tempo's explicit form, and a standing of `Done`, `Open`, divergent or unsupported. Only expressions and clause numbers are taken from the standard, none of its prose. The rows are extracted from the PDF text once and the readings reviewed by hand. The test reports the count by clause, and `guides/iso8601-conformance.md` takes its supported and unsupported lists from the same file in place of the hand-kept ones.

### Where it runs

A seeded sample runs in the default `mix test`, sized to stay under a few seconds. The exhaustive runs carry the `all: true` tag `test/test_helper.exs` already excludes, and get a step of their own on the CI lint row. A change to the tokenizer that alters what is read then fails until the grammar says the same, in the same commit.

## Options considered

* **A grammar as the oracle, the parser as it is** — chosen. It adds an independent statement of the language and finds defects without touching 3,704 tuned lines.

* **Generate the tokenizer from the grammar** — deferred. It removes drift by construction, and it is a rewrite of the tokenizer with the parse-cost work to redo. It is worth weighing only once the oracle has shown how far the parser is from the grammar.

* **A grammar written as Elixir data** — rejected. It is quicker to read into the recogniser, and it is not a notation anyone outside the project can review against the standard or reuse.

* **More example tests** — rejected as the whole answer. The standard's examples are worth having as a table, and they are part of this plan, but examples only cover what is written down, which is the gap.

## The pilot

ISO 8601-1 clause 5: dates (5.2), times of day (5.3), dates and times (5.4), time intervals (5.5) and recurring time intervals (5.6). It is the small part of the language, the part real traffic uses most, and the one RFC 3339 overlaps, so the transcription has a second source to check against.

The pilot delivers the grammar for clause 5, the examples table for Part 1, the reader, recogniser and generator, and the six tests over that grammar. It ends with a findings section in this document: the texts checked, the defects found with a `TODO.md` item each, the texts with two readings, the choices left to agreement and what Tempo chose, and what the runs cost.

It has to show the method works before Part 2 is started. The interval end read as a century (`2026-06-15/20`, open in `TODO.md`) is in clause 5.5, so the pilot should find it unaided, and the fraction read as a century (`09.5`, fixed on 2026-10-03) should fail if its fix is reverted. If the pilot finds neither, the method is wrong and the plan stops for review.

## The pilot on sets and ranges

Taken up on 2026-10-06 in place of clause 5, where the defects were: the parser's sets, ranges and basic format had given about two new defects for each one fixed by hand. It is a generator and not a grammar. `Tempo.GeneratedSets` (`test/support/generated_sets.ex`) builds each text from the texts of its members, so what it should read as is known without reading it, and `Tempo.Iso8601.GeneratedSetsTest` holds each to three properties: reading it, `inspect/1` and `Tempo.to_iso8601/1` never raise; a member of a set is its own text read alone; and what is written reads back as the same value.

* **The texts** — 1,948 (1,931 at first), from 67 families of members in the explicit, the extended and the basic format (dates, week dates, days of the year, centuries, decades, seasons, times, dates and times, with zones, shifts, qualifiers, unspecified digits, significant digits, groups and selections), each as a set of all and of one, with ranges between two members and open at an end; and 40 templates of a set in one unit of a value, with steps, counts from the end, two sets in one value, a zone, a qualifier and a fraction. The run takes 2.3 seconds in the default suite.

* **Found and fixed** — a set of one value in a unit read as another value than its member (`2026Y25W{1}K`); a set of days of the year read as months, so that `2026-{001}` was January; one of several years before the year designator (`[2025,2026]Y6M`) and a member with a zone of its own, neither read; a range of seasons whose ends were intervals, which nothing walked; a zone that is not known written in a form no suffix reads; and a set of one year with significant digits that no span was read from. Each has its line under Done in `TODO.md`, dated 2026-10-06.

* **The forms not read** — each is generated and held to being refused, or left out with its reason in the module: an interval at an end of a range; a range of a year's divisions that is no run in time, or open at an end; a set of whole values as a member of a set; a value with unspecified digits in a set of a unit below the year; one of several values in a unit of the extended or the basic format, where a bracket is the suffix of RFC 9557; and a time shift after a set. The basic format's sets in a week date and a time alone were among them, and are read since 2026-10-07.

* **What it says of the method** — two runs found seven classes that 259 example tests had not, at a cost of two seconds a run, and the same generator fails at the commit before each fix. The members' texts are the oracle, which a grammar would be for forms with no member to read alone. It does not say whether a text Tempo reads is in the standard (the Sound property), which needs the recogniser.

## After the pilot

Part 2 follows by clause, the clauses where defects have been found first: selection (12), sets (6), explicit forms (7), qualification (8), then unspecified digits (9), extended intervals (10), explicit duration (11), repeat rules (13), grouped units (5) and the component extensions (4). Annex A, the EDTF profile, is a start symbol of its own over the same rules, checked against `test/support/edtf_corpus.ex`. RFC 9557 and Tempo's extensions come last, and the soundness test is only complete once they are in, since until then an extension reads as a text in no grammar.

## Decisions for the user

* **The examples in a public repository** — the table holds the standard's expressions and clause numbers. Short expressions are facts rather than prose, and the selection is still taken from a copyrighted document the repository deliberately leaves out. The recommendation is to commit expressions and clause numbers alone. The alternative is to keep the table beside the PDFs, out of the repository, and run that one test locally.

* **Where the grammar lives** — `grammar/` at the root is the recommendation, with the files published later as a guide so a reader of the docs can see exactly what Tempo reads.

* **The CI budget** — a sample in every run and an exhaustive step on the lint row is the recommendation. The sizes are set from the pilot's timings.

* **Tempo's own written forms** — whether a form `inspect/1` writes and `from_iso8601/1` does not read is a defect in the writer or a gap in the reader is decided case by case. The output test only reports them.

## Risks

* **Transcription errors** — a wrong rule makes the tests agree with the wrong language. Each rule names its clause so it can be reviewed against the PDF, and RFC 3339 and the EDTF corpus check the parts they cover.

* **A grammar wider than the standard means** — the templates say less than the prose around them. A rule that derives text the standard's prose forbids shows up as a completeness failure, and the resolution is recorded on the rule.

* **Run time** — the tokenizer takes between about 40 and 430 microseconds a text (measured 2026-09-24), so a hundred thousand texts take between four and forty-three seconds. Compositions multiply quickly, which is why they are sampled and not enumerated.

* **Upkeep** — every change to what Tempo reads needs a change to a grammar file. That is the purpose: the grammar is the review record of the change.

## Tasks

* [x] **The pilot on sets and ranges** — a generator of 1,931 texts and three properties in the default suite, and the seven classes it found fixed. 2026-10-06.

* [ ] **The grammar for Part 1 clause 5** — `grammar/iso8601-1.abnf`, each rule with its clause and standing, and the list of choices the standard leaves to agreement with what Tempo chose.

* [ ] **The reader and the recogniser** — the ABNF subset read into a rule table, and a matcher that returns every derivation, with tests of their own on small grammars.

* [ ] **The generator** — texts derived from a rule as a `StreamData` generator, with representative values for numeric components and an exhaustive mode by form.

* [ ] **Part 1's examples** — the rows for the 133 example lines of Part 1, extracted from the PDF text and reviewed, and the test that reports the count by clause.

* [ ] **The six tests over clause 5** — derived texts parse, read texts derive, readings, spellings, output and examples, with a sample in the default run and the exhaustive runs tagged `all: true`.

* [ ] **The pilot's findings** — the defects as `TODO.md` items, the table of readings, the timings, and the decision on Part 2 recorded here.

### Blocked

* [ ] **Part 2, RFC 9557 and the extensions** — the same work clause by clause. Blocked on the pilot's findings.

### Deferred

* [ ] **Generate the tokenizer from the grammar** — parked until the oracle has measured how far the parser is from the grammar. A large number of defects that share a cause in choice order would revive it.
