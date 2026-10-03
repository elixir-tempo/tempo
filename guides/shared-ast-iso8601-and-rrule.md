# A shared AST for ISO 8601 and RFC 5545 RRULE

Tempo's internal representation — `%Tempo{}`, `%Tempo.Interval{}`, `%Tempo.Duration{}`, `%Tempo.Set{}` and their supporting tokens — is a single AST that underpins two otherwise unrelated input formats:

* **ISO 8601** / **ISO 8601-2** / **IXDTF** — the big, permissive, human-readable standard family Tempo was built around
* **RFC 5545 RRULE** — the tight, machine-oriented recurrence rule language used by iCalendar

This guide explains what the two formats have in common, where they differ, and where the shared AST draws the line.

Short version:

* Both formats describe **time on a half-open interval**. They land on the same AST by design.
* ISO 8601 can express **a superset** of what RRULE can. Uncertainty, approximation, unspecified digits, groups, selections, sets, open-ended intervals, explicit-form partial dates, BCE years, expanded years — none of these have RRULE equivalents.
* RRULE can express **one thing ISO 8601 can't** cleanly: a weekday-name ordinal (`BYDAY=4TH`), which Tempo models via paired `:day_of_week` + `:instance` selection tokens. ISO 8601-2 selections encode the same data in the same AST shape.
* The AST validates **both directions**. Round-trip testing (ISO → AST → ISO and RRULE → AST → RRULE) stays within the subset each format supports.

## What's shared

Both formats model a bounded recurrence as:

* A **cadence** — how often an event recurs. In ISO 8601 that's a `P…` duration; in RRULE it's `FREQ` + `INTERVAL`.

* A **bound** — how many times or until when. In ISO 8601 the bound is the count prefix (`R<n>/…`) alone: an `R/<from>/<to>` interval names the first occurrence, not an end. RRULE has the count, `COUNT=n`, and an end, `UNTIL=<date>`, which cannot be present together; a rule with an `UNTIL` has no ISO 8601 form.

* A **selection pattern** — which specific instances to pick from the underlying recurrence. In ISO 8601 this is the selection sublanguage `L…N` and the `/F<rule>` repeat-rule combinator; in RRULE this is the family of `BY*` rules (`BYMONTH`, `BYDAY`, `BYMONTHDAY`, `BYHOUR`, `BYSETPOS`, etc.).

Tempo puts each concern in its own field on `%Tempo.Interval{}`:

| Concept | `%Tempo.Interval{}` field | ISO 8601 | RRULE |
|---|---|---|---|
| Cadence | `:duration` (`%Tempo.Duration{time: [{unit, n}]}`) | `P<n><unit>` | `FREQ=<unit>;INTERVAL=<n>` |
| Count | `:recurrence` (integer or `:infinity`) | `R<n>/...` | `COUNT=<n>` |
| Until | `:to` beside a cadence (`%Tempo{}`) | none: `R/<from>/<to>` names the first occurrence | `UNTIL=<date>` |
| Selection | `:repeat_rule` (`%Tempo{time: [selection: [...]]}`) | `/F<rule>` or inline `L…N` | `BY*` rules |
| Start | `:from` (`%Tempo{}`) | `<from>/...` | `DTSTART` (not in RRULE itself) |

The token-level selection shape — `{:selection, [unit: value_or_list, ...]}` — is **byte-for-byte identical** whether it comes from parsing `L4KN` in ISO 8601-2 or `BYDAY=4TH` in RRULE. That shared shape is what makes `Tempo.RRule.to_string/1` and `Tempo.to_iso8601/1` both possible without any format-specific intermediate.

### Where a selection picks its points

A selection that picks points — the 15th, 09:00, the Mondays of a week — picks them in the calendar period of the cadence's unit that holds each step's start: the day for a daily cadence, the month for a monthly one. That is how RFC 5545 evaluates its `BY*` rules and ISO 8601-2 §13.4 its eligible time intervals, and the step's start only moves the periods along. So a point can fall before its step when the start is not at the top of its period: `R/2026-01-05T12/P2D/FLT9HN`, like `FREQ=DAILY;INTERVAL=2;BYHOUR=9` from noon, fires at 09:00 on 7, 9 and 11 January, three hours before each step.

A cadence of mixed units, which ISO 8601-2's repeat rule has no form for, takes its period from its first unit. `P1DT12H` picks in days, so `R/2026-01-05/P1DT12H/FLT9HN` fires at 09:00 on the first day of each step — 5, 6, 8, 9 and 11 January — while `PT36H` picks in hours, where `FLT9HN` keeps only the steps that start at 09:00.

## What ISO 8601 can express and RRULE cannot

ISO 8601-2 and IXDTF were designed to be descriptive. RRULE was designed to be prescriptive. The difference shows:

### Uncertainty, approximation, qualification

ISO 8601-2 gives you `?`, `~`, and `%` to mark a value as uncertain, approximate, or both. An archaeologist writing `1850~` says "around 1850, give or take". This lives on Tempo's `:qualification` field (expression-level) and `:qualifications` field (per-component, for forms like `2022-?06-15`).

RRULE has no equivalent. A `COUNT=10` means exactly ten occurrences, no hedging.

### Unspecified digits

ISO 8601-2 lets you write `156X`, `1985-XX-XX`, or `-1XXX-XX` when you don't know every digit. Tempo represents these with `{:mask, [digits, :X, :X, ...]}` tokens.

RRULE has no concept of partial values. Every RRULE part is fully specified.

### Date-only values

`Tempo.from_iso8601!("2022-06-15")` is a perfectly valid Tempo value. It's not a recurrence — it's a single bounded interval (one day).

`Tempo.RRule.to_string/1` rejects this with `Tempo.ConversionError`: RRULE exists to describe recurrence, and a single date has no recurrence to describe. Callers who want "a single event" in iCalendar use `DTSTART` alone, without an `RRULE`.

### Open-ended intervals

ISO 8601-2 supports `1985/..` ("from 1985 onwards"), `../1985` ("up to 1985"), and `../..` ("unbounded"). Tempo represents these with `:undefined` endpoints.

RRULE can approximate the "from 1985 onwards" case by omitting `COUNT` and `UNTIL`, but only if you also supply `DTSTART`. The "up to 1985" and fully-unbounded forms have no RRULE equivalent.

### Sets of dates

ISO 8601-2 defines `{a,b,c}` (all-of) and `[a,b,c]` (one-of) as set constructors. Tempo represents these as `%Tempo.Set{type: :all | :one, set: [...]}`.

RRULE has no set concept. You can't say "these three specific dates" as an RRULE — that's what `RDATE` (a *different* iCalendar property) is for, which Tempo doesn't currently model.

### Seasons, quarters, halves

ISO 8601-2 reserves month codes 21–41 for seasons (meteorological and astronomical), quarters, quadrimesters and halves. Tempo expands these to concrete intervals at parse time — e.g. `2022-25` becomes the interval `[2022-03-20, 2022-06-21)` (the Northern astronomical spring).

RRULE has no native vocabulary for any of these. The closest approximations are `BYMONTH=3,4,5` (a three-month set), but the astronomical seasons won't land on month boundaries, so the approximation is inaccurate.

### Groups and selections (inline)

ISO 8601-2 lets you embed a group (`5G10DU`) or selection (`L4KI4N`) directly inside a date expression. Tempo token-structures these as nested values on the `:time` keyword list.

RRULE doesn't compose like this. A single RRULE describes one repetition pattern.

### Wide-range years

ISO 8601-2's `Y` prefix allows arbitrary-length years: `Y17E8` is 1,700,000,000. Tempo stores this as an integer on the `:year` token.

RRULE's UNTIL uses the RFC 3339 basic format — four-digit years only. Years outside ±9999 cannot appear in UNTIL.

### Time zones and calendars (via IXDTF)

Tempo's IXDTF support attaches `[Europe/Paris]`, `[u-ca=hebrew]`, or arbitrary elective tags to a datetime: a zone and tags are stored on the `:extended` field, and a calendar is the value's `:calendar`. `Tempo.RRule.to_string/1` does **not** emit these — iCalendar handles zones and calendars via `TZID` and `CALSCALE` at the calendar-object level, not inside `RRULE`.

## RRULE features and how they map to ISO 8601

Most RRULE `BY*` filters map straight onto the ISO 8601-2 selection grammar — `BYWEEKNO` onto the ISO 8601 week `W`, which a rule without `BYDAY` gives DTSTART's weekday, as ISO 8601-2 Annex C.4 has a conversion state it. Tempo's calendar week `w` has no RRULE form, since `BYWEEKNO` counts ISO 8601 weeks. Two need comment: `BYSETPOS` **is** ISO 8601-2 (the §12.9 position designator `I`), while `WKST` has no ISO representation and so gets Tempo's project-specific designator `q`. Both are documented in `guides/iso8601-conformance.md` §5. A rule carrying either round-trips through the ISO form; the canonical *external* form remains the RRULE string via `Tempo.RRule.to_string/1`.

### `BYSETPOS` — the ISO 8601-2 §12.9 position `I`

RRULE `BYSETPOS=-1` ("take the last element of the resolved per-period set") is the ISO 8601-2 position designator: it is held as an `:instance` token, applied last, after every other BY-rule. It renders weekday-then-position, so `FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1` round-trips as `~o"R/../P1M/FL{1..5}K-1IN"`. A single-weekday ordinal is the same token: `BYDAY=2MO` ("the 2nd Monday") lowers to `day_of_week: 1, instance: 2` and renders `1K2I`. Since a position applies last within a selection, the ordinal's times follow the selection rather than join it, as ISO 8601-2 §12.9 writes 09:00 on the second Tuesday: `BYDAY=2TU;BYHOUR=9` is `L2K2INT9H`. The shapes with no ISO form are an ordinal across *distinct* weekdays (`BYDAY=2MO,2WE`) and an ordinal beside a `BYSETPOS`, which takes the selection's one position; each is held as an internal `:byday` token that round-trips only via `Tempo.RRule.to_string/1`.

### `WKST` — the `q` designator

RRULE lets a rule override the week start (`WKST=SU`), which shifts `BYWEEKNO`/`BYDAY`-weekly boundaries. Tempo holds it as a `:wkst` token: `Tempo.RRule.to_string/1` emits `WKST=SU`, and `Tempo.to_iso8601/1` renders it as `7q` (7 = Sunday), so it round-trips both ways. (A non-default `WKST` alone is enough to produce a `:repeat_rule`, since it changes weekly boundaries.)

## What is lossy in the encoders

Because ISO 8601 can describe more than RRULE, and RRULE needs specific features ISO 8601 doesn't model at the AST level, round-tripping isn't always lossless.

### `Tempo.to_iso8601/1` returns `{:error, %Tempo.Iso8601EncodeError{}}` for

* An ordinal spread across distinct weekdays (`BYDAY=2MO,2WE`), or an ordinal beside a `BYSETPOS`, which a single `I` cannot express.

* A recurrence's end (RFC 5545 `UNTIL`): ISO 8601 bounds a recurrence only by its count.

* A cron nearest weekday (`15W`).

* A cron day-of-month OR day-of-week union (`0 0 13 * 5`, the 13th or any Friday), since every part of an ISO 8601 selection holds at once.

* A set of intervals or of recurrences, or a conditional member of one: ISO 8601 has no syntax for a set of values, so encode its members one by one.

`Tempo.to_iso8601!/1` raises the same error. Everything else round-trips, component qualifications included (`2022-?06-15` encodes as `2022Y6?M15D`), except an interval's `:unit` and `:metadata`, which have no ISO 8601 spelling and are not written.

### `Tempo.RRule.to_string/1` returns `{:error, %Tempo.ConversionError{}}` for

* A `%Tempo{}` that is not a `%Tempo.Interval{}` (no recurrence to describe).

* An interval that does not recur, with no `:duration` (no FREQ available). A recurrence written with a start and an end steps by its first occurrence's length (`R5/2026-06-15/2026-06-20` is `COUNT=5;FREQ=DAILY;INTERVAL=5`).

* A recurrence written with a duration and an end and no count (`R/P1D/2026-06-20`), which runs back without a first occurrence; with a count it is `COUNT` and the cadence.

* A duration with multiple units (`P1Y6M` → RRULE has no "year-and-six-months" unit).

* A duration with a unit RRULE doesn't support (`P1C` century, group unit, etc.).

* A `:repeat_rule` whose shape isn't a flat `:selection` keyword list.

* A selection with no RRULE `BY*` part: a calendar week (`w`), a traditional month (`m`), a computed event (`e`), a year, a selection window (ISO 8601-2 §12.10), or a cron nearest weekday or day-of-month-or-weekday. The error names each one rather than dropping it.

Every error carries a human-readable `:message` field and the source `:value`. Errors can be re-raised as exceptions — `Tempo.RRule.to_string!/1` does this.

## Why one AST for two formats

Three practical benefits:

1. **Validation.** A parser that lands on a specific AST shape, combined with a round-trip test suite, is self-validating. If a parser bug changes the AST, round-trip fails loudly. `test/tempo/round_trip_test.exs` (ISO ⇄ RRULE through the encoders) and `test/tempo/iso8601/round_trip_test.exs` (one case per ISO 8601 / ISO 8601-2 / IXDTF token, parse → `inspect` → parse) give exactly this.

2. **Cross-format conversion.** Because both parsers target the same AST, `ISO 8601 → AST → RRULE` works for any input in the intersection. The test suite exercises three such conversions (`R/2022-01-01/P1D` → `FREQ=DAILY`, etc.). When the input is *outside* the intersection, the encoder returns a `Tempo.ConversionError` with a clear message pointing at what's not expressible.

3. **One optimisation surface.** Enumeration, comparison, set operations (the next major milestone) are defined on the AST, not on format-specific token streams. Both ISO 8601 and RRULE values get the same operators for free.

## API surface

```elixir
# Parsers
{:ok, ast} = Tempo.from_iso8601("2022-06-15")
{:ok, ast} = Tempo.RRule.parse("FREQ=DAILY;COUNT=10")

# Encoders
{:ok, iso_string} = Tempo.to_iso8601(ast)              # succeeds or returns Iso8601EncodeError
iso_string = Tempo.to_iso8601!(ast)                    # raises on failure
{:ok, rrule_string} = Tempo.RRule.to_string(ast)       # succeeds or returns ConversionError
rrule_string = Tempo.RRule.to_string!(ast)             # raises on failure

# Round-trip pattern
{:ok, ast_1} = Tempo.from_iso8601(iso)
{:ok, iso_1} = Tempo.to_iso8601(ast_1)
{:ok, ast_2} = Tempo.from_iso8601(iso_1)
assert ast_1 == ast_2           # fixed-point property
```

## Further reading

* Source: `lib/tempo/rrule.ex`, `lib/tempo/rrule/encoder.ex`, `lib/inspect.ex`
* Round-trip tests: `test/tempo/round_trip_test.exs` (encoder round-trips) and `test/tempo/iso8601/round_trip_test.exs` (per-token `inspect`/`to_iso8601` round-trips)
* Conformance coverage (ISO 8601 side): `guides/iso8601-conformance.md` (§5 covers the `I` position designator and the `q` project-specific week-start)
