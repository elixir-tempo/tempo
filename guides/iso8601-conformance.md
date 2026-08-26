# ISO 8601 Conformance Guide

Tempo implements a substantial subset of [ISO 8601:2019](https://www.iso.org/standard/70907.html) Part 1 and [ISO 8601-2:2019](https://www.iso.org/standard/70908.html) Part 2, plus the [IETF IXDTF draft (draft-ietf-sedate-datetime-extended-09)](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html). This guide catalogues what is supported, what isn't, and where Tempo diverges from the strict standard.

The canonical authority is the PDF of the ISO standard (held locally in `~/Documents/Development/iso_standards/`). When this document and the standard disagree, the standard wins — please file an issue.

## 1. Core principle — bounded intervals

Every Tempo value is a **bounded interval on the time line**, not an instant. `2026-01` is not the single instant "January 2026"; it is the interval `[2026-01-01, 2026-02-01)` — inclusive of the first boundary, exclusive of the last. This is called the **implicit-span semantics**: a partial date specification spans the next-finer unit that isn't given.

A single `Tempo.from_iso8601/1` call therefore always returns a bounded value, never a "partial" or "unresolved" date. This lets the set operations (`Tempo.union/2`, `intersection/2`, `difference/2`, and interval-set coalescing) reason about every value uniformly.

## 2. ISO 8601 Part 1 — core representations

### Two forms, three spellings: implicit and explicit

ISO 8601 lets you write the *same* value more than one way. The choice runs on two independent axes — worth knowing both, because **Tempo accepts all of them as input but always prints the explicit form**: `inspect(~o"2022-06-15")` shows `~o"2022Y6M15D"`, which surprises people the first time.

**Axis 1 — what identifies each component (the *form*).**

* **Implicit form** — a component's identity is implied by its **position**. In `2022-06-15`, `06` is the month because it sits in the month slot. This is the everyday form, defined in ISO 8601 Part 1.

* **Explicit form** — each component carries a **designator letter** naming it: `Y` year, `M` month, `D` day, `W` week, and after the `T`, `H` hour, `M` minute, `S` second. `2022Y6M15D` needs no fixed positions because every field is labelled. Defined in ISO 8601 Part 2.

**Axis 2 — separators (the *format*; applies to the implicit form only).**

* **Extended format** — components separated by `-` and `:`: `2022-06-15`, `T14:30:00`. The human-readable default.

* **Basic format** — no separators: `20220615`, `T143000`. Compact, for fixed-width contexts (filenames, identifiers).

The explicit form needs no separators — the designators already say which field is which — so "basic vs extended" is a property of the implicit form. That yields **three concrete spellings** of any value:

| Value | Implicit · extended | Implicit · basic | Explicit |
|---|---|---|---|
| 15 June 2022 | `2022-06-15` | `20220615` | `2022Y6M15D` |
| 14:30:00 | `T14:30:00` | `T143000` | `T14H30M0S` |
| that date **and** time | `2022-06-15T14:30:00` | `20220615T143000` | `2022Y6M15DT14H30M0S` |

All three parse to the identical `%Tempo{}`; `Tempo.to_iso8601/1`, `inspect/1`, and the `~o` sigil all emit the explicit form.

**Why Tempo prints explicit form.** It is self-describing and order-independent, so it round-trips unambiguously — and it is the only form in which Tempo's richer constructs (durations like `P1Y6M`, groups, selections, and the recurrence designators) compose. It is also why the same letter `M` can mean both **month** and **minute**: the `T` beginning the time part disambiguates them. Before the `T`, `M` is a month (`6M` in `2022Y6M15D` = June); after it, `M` is a minute (`30M` in `T14H30M` = thirty minutes) — the same rule durations use (`P6M` is six months, `PT6M` is six minutes).

**Which should you write?** Prefer **implicit extended** (`2022-06-15T14:30`) for input — it is the most familiar and what most other systems emit. Reach for **explicit** only when you need what it uniquely offers: position independence, or Tempo's extended group/selection syntax.

### Supported

| Feature | Examples |
|---|---|
| Year | `2022`, `-0001`, `+002022` |
| Year-month | `2022-06`, `202206` |
| Year-month-day | `2022-06-15`, `20220615` |
| Ordinal date | `2022-166`, `2022166` |
| Week date | `2022-W24`, `2022-W24-3`, `2022W243` |
| Month-day | `06-15` (the truncated `--06-15` / `--0615` forms are deprecated — see below) |
| Time of day | `T10`, `T10:30`, `T10:30:00`, `T103000` |
| Fractional seconds | `T10:30:00.5`, `T10:30:00,5` |
| Time zone `Z`, `+HH`, `+HH:MM`, `+HHMM` | `10:30:00Z`, `10:30:00+05:30` |
| Combined datetime | `2022-06-15T10:30:00Z` |
| Durations `PnYnMnDTnHnMnS` | `P1Y`, `PT30M`, `P3Y6M4DT12H30M5S` |
| Negative duration | `-P100D` |
| Fixed-endpoint interval | `2022-01/2022-06`, `20220101/20220630` |
| Interval with an abbreviated end (§5.5.1) | `2018-01-15/02-20`, `2025-08-28T09:00/T10:15` |
| Duration-relative interval | `2022-01-01/P1Y`, `P1Y/2022-12-31` |
| Recurring interval | `R/2022-01/P1M`, `R5/2022-01/P1M` |
| Expanded (large) years | `+002022`, `-0001` |
| Leap second | `23:59:60Z` on 30 June or 31 December UTC |

### Partial or divergent

* **Truncated representations** (`--06-15`, `85-06-15` — 2-digit year) were deprecated in the 2019 edition and are not accepted. Modernise your input.

* **Fractional seconds** are preserved as a `:microsecond {value, precision}` component (not truncated to whole seconds). The digit count is significant — `T10:30:00.120` is millisecond resolution and `T10:30:00.12` is centisecond resolution, two distinct interval widths. ISO 8601 permits an unbounded number of fractional digits; Tempo caps precision at 6 (microsecond), matching Elixir's `Time`/`DateTime`. Input with more than 6 fractional digits is truncated to microsecond. Fractional minutes and hours (`T10:30,5`, `T10,5`) still cascade to a coarser-unit remainder as before.

### Not supported

* Nothing known to be missing from Part 1 as of v0.2.0.

## 3. ISO 8601-2 Part 2 — extensions

### Supported

| Feature | Examples |
|---|---|
| **Unspecified digits** (`X`) | `156X`, `1XXX`, `2022-XX`, `1985-XX-XX`, `-1XXX-XX`, `-XXXX-12-XX` |
| **EDTF Level 1 qualification** (`?`, `~`, `%`) | `2022?`, `2022~`, `2022%` |
| **ISO 8601-2 §8 component qualification** (implicit form) | `2004-06~-11` (group), `2004-?06-11` (individual), `?2022-06-15` (leading individual). See "Component qualification" below. |
| **Per-endpoint qualification in intervals** | `1984?/2004~`, `2019-12/2020%`, `2004-06-11%/2004-06~` |
| **Leading prefix qualifier** | `?2022-06-15`, `%2001`, `?-2004-06` |
| **Open-ended intervals** | `1985/..`, `../1985`, `../..`, `1985/`, `/1985`, `/`, `/..`, `../` |
| **Set of dates — all of** | `{1960,1961,1962}`, `{1960..1970}` |
| **Set of dates — one of** | `[1984,1986,1988]`, `[1667..1672]` |
| **Range in set** | `[1900..2000]`, `{-1640-06..-1200-01}` |
| **Groups** | `5G10DU` (5th group of 10 days), `2018Y4G60DU6D` (2018, day 6 of the 4th group of 60 days) |
| **Selections** | `L1MN`, `L2MI3N` (1st month, 3rd instance of the 2nd month) |
| **Meteorological seasons** (codes 21–24) | `2022-21` (spring), `2022-22` (summer), `2022-23` (autumn), `2022-24` (winter) |
| **Astronomical seasons** (codes 25–32) | `2022-25` (N spring), `2022-26` (N summer), `2022-27` (N autumn), `2022-28` (N winter), `2022-29..32` (Southern hemisphere). Boundaries computed via the `Astro` library using March/September equinoxes and June/December solstices (accurate to ≈2 minutes for years 1000–3000 CE). |
| **Quarters** (codes 33–36) | `2022-33` (Q1), `2022-36` (Q4) |
| **Quadrimesters** (codes 37–39) | `2022-37`, `2022-38`, `2022-39` |
| **Semestrals / halves** (codes 40–41) | `2022-40` (H1), `2022-41` (H2) |
| **Negative calendar qualification** | `-2004?`, `-2004-06?`, `-2001-34` (Q1 BCE) |
| **Sets / ranges with negative members** | `[-1667,1668]`, `{-1640-06..-1200-01}` |
| **Margin of error** | numeric literal with `±` (via `form_number`) |
| **Exponents on year** | `2018E3` style — parsed by `numbers.ex` `exponent()` |
| **Significant-digit annotations** (short form) | `1950S2`, `-1859S5`, `Y3388E2S3` |
| **Year-zero** (`0000`, `-0000`) | Parses as year 0. Interpretation per astronomical convention (year 0 = 1 BCE) is the caller's responsibility. |

### Not supported

| Feature | Example | Reason |
|---|---|---|
| Cross-endpoint semantic validation of intervals | `2012-24/2012-21` (winter before spring) | Parses at the syntax level; a semantic ordering check across the two endpoints is not currently enforced, so a small number of syntactically-valid but semantically-inverted intervals are accepted. |

All other EDTF Level 2 features — including wide-range exponent years (`Y17E8`, `Y-170000002`) and long-year significant-digit annotations (`Y171010000S3`) — are supported.

### Component qualification (ISO 8601-2 §8)

A `?` (uncertain), `~` (approximate), or `%` (both) qualifier's **position** sets its scope, per §8.2. Tempo honours all three scopes for implicit-form dates, storing whole-value qualification on `:qualification` and per-component qualification on the `:qualifications` map (keyed by unit):

| Position | §8 scope | Example | Result |
|---|---|---|---|
| Rightmost end | §8.2.1 **complete** | `2004-06-11%` | `qualification: :uncertain_and_approximate` |
| Right of a component | §8.2.2 **group** — that component and every coarser one to its left | `2004-06~-11` | `qualifications: %{year: :approximate, month: :approximate}` |
| Left of a component | §8.2.3 **individual** — that component only | `2004-?06-11` | `qualifications: %{month: :uncertain}` |
| Leading (left of the first component) | §8.2.3 **individual** | `?2004-06-11` | `qualifications: %{year: :uncertain}` |

Overlapping qualifiers on one component combine: `2004-?06~-11` (individual `?` on the month, group `~` on the month and year) yields `%{year: :approximate, month: :uncertain_and_approximate}`.

The **explicit** (designator) form is also parsed: a qualifier between a value and its designator (`2004~Y6?M11D`, §8.3, including a qualified BC year `2004~YB`) is always individual. `inspect/1` and `to_iso8601/1` render the `:qualifications` map back in this form, so component qualification **round-trips** — a parsed group such as `2004-06~-11` re-encodes as the equivalent explicit individual qualifiers `2004~Y6~M11D`. Per §8.2.4, a value whose every present component shares one qualifier collapses to the compact complete form (`2004%Y6%M11%D` → `2004Y6M11D%`); group collapse is not attempted, as the explicit output form has no group representation.

## 3a. Intervals whose end omits higher order components

ISO 8601-1 §5.5.1 lets the end of an interval leave out the components it shares with the start: *"higher order time scale components may be omitted from the 'end of time interval', provided that the resulting expression is unambiguous. In this case the omitted higher order components from the 'start of time interval' expression apply."*

Tempo applies them, so the end is a fully anchored value rather than a fragment:

```elixir
iex> Tempo.from_iso8601!("2018-01-15/02-20") == Tempo.from_iso8601!("2018-01-15/2018-02-20")
true

iex> Tempo.from_iso8601!("2025-08-28T09:00/T10:15") == Tempo.from_iso8601!("2025-08-28T09:00/2025-08-28T10:15")
true
```

Rendering goes the other way — `inspect/1` and `to_iso8601/1` drop the shared prefix again, so a value prints as compactly as it was written and round-trips unchanged:

```elixir
iex> Tempo.to_iso8601(Tempo.from_iso8601!("2026-06-15/2026-06-16"))
"2026Y6M15D/16D"
```

**The "unambiguous" proviso is load-bearing.** §5.2.2.2 makes a bare two-digit date component a *century*, so `2022-02-15/04` is century 04 — years 400–499 — not April, and nothing is inherited into it. Omit a component only where a designator or a separator keeps the reading clear: `/02-20` is a month and a day, `/04` is not.

## 4. IXDTF — Internet Extended Date/Time Format

Tempo implements the [IXDTF draft](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html) suffix syntax. After any ISO 8601 date-time, an optional suffix may carry:

| Suffix | Example | Stored on `%Tempo{}` |
|---|---|---|
| IANA time zone | `[Europe/Paris]` | `extended.zone_id` |
| Numeric offset | `[+08:45]`, `[-03:30]`, `[+0530]` | `extended.zone_offset` (minutes from UTC) |
| Calendar (`u-ca=`) | `[u-ca=hebrew]`, `[u-ca=gregory]` | `extended.calendar` (atom) |
| Generic tag | `[_foo=bar-baz]` | `extended.tags` (`%{"key" => ["value", ...]}`) |

Each bracket may be prefixed with `!` to mark it **critical**. Unrecognised critical tags cause the parse to fail; unrecognised elective tags are retained verbatim in `extended.tags`.

A critical flag on a *time zone* also triggers RFC 9557 §4.2 offset consistency: `2022-01-01T00:00:00+05:00[!America/New_York]` is rejected with a `Tempo.ZoneOffsetMismatchError` because `+05:00` is not New York's offset on that date. Marking the zone critical is retained on `extended.zone_critical` and round-trips back out through `to_iso8601/1`. An *elective* zone leaves the numeric offset authoritative and the zone advisory, so a disagreement parses cleanly. To reject disagreement even for elective zones, pass `strict: true` to `from_iso8601/2` — a superset of the mandatory critical check.

Time zones are validated against the configured time zone database (`Tempo.TimeZoneDatabase.zone_exists?/1`); with no database configured, syntactically valid zone names are accepted without registry validation. Calendars are validated against `Localize.validate_calendar/1`, which also handles the `"gregory"` → `:gregorian` alias per BCP 47.

## 5. Project-specific extensions (not in ISO 8601)

These syntaxes are Tempo conveniences, not part of any standard:

* **Step in range** — `{1990..1999//2}Y` or `2023Y{1..-1//2}W` means "every second week in 2023".
* **Explicit suffixes** — `2022Y11M20D` instead of `2022-11-20`. Used by the `~o` sigil as the canonical output form.
* **Repeat rule** — `/F` combinator inside a parsed expression.
* **Selection instance count** — `L…N` with an `I` modifier for the nth instance of a *single* weekday (`2I1K` = "the 2nd Monday"). `I` is ISO 8601-2, not a Tempo invention; it is mentioned here only to contrast it with `V` below, which it is easily confused with.

None of these break ISO 8601 compatibility — Tempo accepts the standard forms too.

### Ratified RRULE selection designators — `V` and `Q`

A recurrence selection may carry two RFC 5545 (iCalendar RRULE / cron) filters that have **no ISO 8601 representation**: `BYSETPOS` and `WKST`. Tempo gives them project-specific designators — `V` and `Q` — so a rule that uses them round-trips through `inspect/1` and `Tempo.to_iso8601/1` instead of being silently lost. These are **ratified** as permanent extensions: the letters and their meanings are stable and will not change.

They are kept, rather than dropped for the sake of a spec-pure output, for two reasons:

1. They express selections that ISO 8601 genuinely cannot. Neither the ISO ordinal designator `I` nor Tempo's set operations (`Tempo.intersection/2`, `Tempo.difference/2`, …) can reproduce them — see the contrasts below.

2. They give Tempo's native string form the same reach as the RRULE it parses, so `RRULE → to_iso8601 → from_iso8601 → to_rrule` is loss-free and symmetric with the recurrence vocabulary.

#### `V` — set position (RRULE `BYSETPOS`)

`nV` keeps the **Nth occurrence of the whole per-period candidate set**, after every other `BY`-rule has run and the survivors are sorted. Negative counts index from the end and a set picks several: `-1V` is the last, `{1,3}V` is the 1st and 3rd.

The subtlety — and the reason it is more than the ordinary ordinal — is that it ranks the *merged* set, not one weekday. "The last **weekday** of the month" is `V`; "the last **Friday**" is the ISO ordinal `I`. They are different selections:

```elixir
# Last WEEKDAY of each month — R/../P1M/FL{1..5}K-1VN
# -1V over the merged Mon–Fri set
Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")
#   from 2022-06 → June 30 (Thu), July 29 (Fri), Aug 31 (Wed)

# Last FRIDAY of each month — the ISO ordinal `I`, a genuinely different result
Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=-1FR")
#   from 2022-06 → June 24, July 29, Aug 26
```

They coincide only when the last weekday happens to be a Friday (July, above). RFC 5545's own worked example — "the third instance of Tuesday, Wednesday, or Thursday each month" — is `3V`:

```elixir
# R/../P1M/FL{2..4}K3VN
Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=TU,WE,TH;BYSETPOS=3")
#   from 1997-09 → Sept 4, Oct 7, Nov 6
```

#### `Q` — week start (RRULE `WKST`)

`nQ` sets the weekday a week **begins** on (`1Q` = Monday, the default; `7Q` = Sunday). Because ISO 8601 weeks start on Monday by definition, any other week start has no ISO representation. The designator is emitted only when it is *not* the Monday default.

`WKST` is a no-op for most rules: it changes nothing for `FREQ=WEEKLY;INTERVAL=1`, since one day per week is picked wherever the boundary sits. It becomes observable only when the week boundary decides *which* weeks are on — an `INTERVAL` of two or more, or a `BYWEEKNO`. This is RFC 5545's canonical example, with the week start as the only difference:

```elixir
# Every other week, Tue + Sun, from Tue 1997-08-05
Tempo.RRule.parse!("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO")
#   → Aug 5, 10, 19, 24   (R4/../P2W/FL{2,7}KN — no Q, Monday is the default)

Tempo.RRule.parse!("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=SU")
#   → Aug 5, 17, 19, 31   (R4/../P2W/FL{2,7}K7QN)
```

Moving the week start from Monday to Sunday changes which fortnight each candidate falls in, so a different set of dates survives the `INTERVAL=2` filter.

#### Interchange risk

`V` and `Q` are the **only** non-standard letters Tempo emits inside a selection. Because they are not ISO 8601, a *different* system reading Tempo's ISO string would not understand them. We rate this risk **low**: we have not identified any other system that consumes ISO 8601-2 recurrence at all, let alone one a Tempo `V`/`Q` string would reach in practice. Where a standard interchange form is needed — sharing a rule with a calendar server, for instance — use `Tempo.to_rrule/1`, which emits `BYSETPOS`/`WKST` in their portable RFC 5545 spelling. Treat the `V`/`Q` string as Tempo's native, loss-free persistence form and the RRULE string as the wire format.

## 6. Ambiguity resolution

A few ISO 8601 constructs are genuinely ambiguous; Tempo resolves them as follows.

| Construct | Standard says | Tempo does |
|---|---|---|
| Seasons `21-24` | Hemisphere unspecified | Treated as **Northern meteorological** (`21` = spring = March-May). |
| `Z` without offset | "UTC is known, local offset unknown" (per RFC 5322 / IXDTF) | Stored as `shift: [hour: 0]`. No distinction from `+00:00`. |
| `-00:00` | ISO 8601:2000 forbade; ISO 8601:2019 permits | Permitted; equivalent to `Z`. |
| Leading qualifier on a date (`?2022-06-15`) | §8.2.3: left of a component qualifies that component | Individual qualification of the leftmost (coarsest) component — `?2022-06-15` stamps `%{year: :uncertain}` on `:qualifications`, not the whole value. See §3 "Component qualification". |

## 7. Test coverage

Tempo's conformance is exercised by:

* **`test/tempo/iso8601/dates_times_test.exs`** — Part 1 core representations.
* **`test/tempo/iso8601/duration_test.exs`**, **`interval_test.exs`**, **`set_test.exs`** — interval, duration, and set constructs.
* **`test/tempo/iso8601/extended_test.exs`** — IXDTF suffix parsing.
* **`test/tempo/iso8601/qualification_test.exs`** — EDTF L1 and L2 qualification.
* **`test/tempo/iso8601/open_interval_test.exs`** — open-ended intervals.
* **`test/tempo/iso8601/unspecified_digit_test.exs`** — unspecified-digit masks.
* **`test/tempo/iso8601/leap_second_test.exs`** — leap-second validation.
* **`test/tempo/iso8601/round_trip_test.exs`** — one representative per token round-trips through `inspect/1`: parse a value, re-parse the canonical `~o"…"` form `inspect/1` shows, and get the identical value back — no component dropped or mangled.
* **`test/tempo/iso8601/edtf_corpus_test.exs`** — the full `unt-libraries/edtf-validate` corpus (BSD-3-Clause), exercised at 100%. See `test/support/edtf_corpus.ex` for the raw strings and attribution.

The EDTF corpus is the only publicly-available conformance test set we know of for ISO 8601-2 Part 2; Tempo passes it in full.

## 8. Comparison to other implementations

No other known implementation in any language supports **full** ISO 8601 Parts 1 and 2. The RFC 3339 subset is covered by every mainstream date library (`java.time`, `chrono`, Python `datetime`, etc.). Part 2 — sets, groups, uncertainty, seasons, selections — is covered only by the EDTF family of libraries (`python-edtf`, `edtf.js`, `edtf-validate`, `mbklein/nulib` for Elixir), which themselves target EDTF's subset of the 2019 standard. Tempo's Part 2 coverage is roughly equivalent to EDTF Level 2 plus Tempo-specific extensions (groups, selections, step ranges).

See `docs/iso8601-conformance-research.md` for the detailed prior-art survey.

## 9. Reporting a conformance gap

If you have an ISO 8601 or EDTF string that should parse and doesn't, please open an issue including:

* The input string.
* The expected result (cite the ISO 8601 clause or EDTF level).
* The actual output from `Tempo.from_iso8601/1`.

Pull requests with a failing test case are especially welcome.
