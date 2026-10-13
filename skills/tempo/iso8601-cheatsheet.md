# ISO 8601 / ISO 8601-2 / IXDTF syntax → English

Every form below is a string you can hand to the `~o"…"` sigil or `Tempo.from_iso8601/1`. **Always validate before presenting** (see the grounding rule in `SKILL.md`) — several of these are easy to get subtly wrong, and Tempo's error names the bad component. For the exhaustive, authoritative table (seasons, quarters, group/selection codes, expanded years) see `guides/iso8601-conformance.md`.

## Core (ISO 8601-1)

| String | Means |
|---|---|
| `2022` | the whole year 2022 |
| `2022-06` | the month of June 2022 |
| `2022-06-15` | that one day |
| `2022-06-15T10` | that hour; add `:30`, `:30:00`, `:30:00.5` for finer resolution |
| `2022-166` | the 166th day of 2022 (ordinal; kept as written, `2022Y166O`) |
| `2022-W24` / `2022-W24-3` | ISO week 24 / its Wednesday (kept as written, `2022Y24W3K`; `Tempo.to_date/1` gives the date) |
| `Z` / `+05:30` suffix on a time | UTC / a fixed offset (`…T10:00Z`, `…T10:00+05:30`) |

**Resolution = meaning.** A value's span is one unit of its finest *stated* field. Give only as much precision as the fact has.

**Implicit vs explicit form.** The same value has three spellings: implicit *extended* (`2022-06-15`, separators — the everyday input form), implicit *basic* (`20220615`, no separators), and *explicit* (`2022Y6M15D`, a designator letter per field: `Y M D W` and, after `T`, `H M S`). All parse to the same `%Tempo{}`; **Tempo always outputs the explicit form**, so `inspect(~o"2022-06-15")` returns `~o"2022Y6M15D"` — expect it. `M` is month before the `T` and minute after it (like `P6M` vs `PT6M`). Explicit form is what makes durations, groups, and selections composable; full explanation in `guides/iso8601-conformance.md` §2.

## Durations, intervals, recurrence

| String | Means |
|---|---|
| `P1Y6M`, `P1W`, `PT1H30M`, `P1DT2H` | a length: 1 year 6 months; 1 week; 1½ hours; 1 day 2 hours (`P`=period, `T`=time part) |
| `2022-01/2022-06` | January **through** June 2022, six months: an end written to a year, month, week or date is included |
| `2022-06-15T09/2022-06-15T17` | nine to five, eight hours: an end written to a time of day is a boundary |
| `2022-06-15/20` | the 15th through the 20th: a short end takes the start's last unit |
| `1985/..` | from 1985 onward, open end |
| `../1985` | up to 1985, open start |
| `../..` | fully open (any time) |
| `R5/2022-01-01/P1M` | 5 consecutive months starting 2022-01-01 (`Enum.count/1` is 5) |
| `R/2022-01-01/P1M` | monthly, with no end (convert with `Tempo.to_interval(r, within: window)`) |

## ISO 8601-2: uncertainty & approximation (EDTF §8)

Three qualifiers — and **where you put them changes the scope**:

| String | Means |
|---|---|
| `2004?` | year **uncertain** ("was it 2004?") |
| `2004~` | year **approximate** ("about 2004") |
| `2004%` | **both** uncertain and approximate |
| `2004-06-11~` | qualifier after the *whole* value → the entire date is approximate |
| `2004-06~-11` | qualifier right of the month → **group**: month *and* everything coarser (year+month) approximate, day known |
| `2004-?06-11` | qualifier left of the month → **individual**: only the month is uncertain |

Qualifiers are **metadata** — they do not widen the interval's bounds. They ride through arithmetic and set ops, are read with `Tempo.qualification/1`, and drive the graded relations (`Tempo.certainty/3`, `certainly?/3`, `possibly?/3`). For a *quantified* uncertainty, use a margin instead.

| String | Means |
|---|---|
| `1200±60Y` | the year 1200, **give or take 60** (a quantified margin; powers graded relations) |
| `1950S2` | 1950 known to **2 significant digits** → some year in 1900–1999 |

## ISO 8601-2: unspecified digits (masks)

`X` = "any digit here." Denotes a *block* (and enumerates its candidates):

| String | Means |
|---|---|
| `156X` | some year in the 1560s (1560–1569) |
| `19XX` | some year in the 1900s |
| `2020-XX` | some month in 2020 |
| `1985-XX-15` | the 15th of *some* month in 1985 (`Tempo.to_interval/2` gives its 12 days) |

## ISO 8601-2: sets (one-of vs all-of)

| String | Means |
|---|---|
| `{1960,1961,1962}` | **all of** these (a collection that all happened) |
| `[1984,1986,1988]` | **one of** these (exactly one, we don't know which — epistemic) |
| `[1667,1670..1672]` | one of 1667, 1670, 1671, or 1672 (`..` is a range *inside* a set) |

A one-of set is epistemic: `Tempo.to_interval/2` of one is an error (`:one_of`), because spans would assert all members happened.

## Advanced (see `guides/iso8601-conformance.md` for the code tables)

* **Seasons / quarters / halves** — numeric sub-year codes (e.g. `2022-21` is spring). A season is kept as written and has no dates of its own, since spring is other months in the other hemisphere; a quarter (`2022-33`) has. Look up the exact code rather than guessing.
* **Groups & selections** — `nGspanUNITU` groups and `L…N` selections express calendrical patterns natively: `~o"R/2025-01-01/P1M/FL1K2IN"` is "the 2nd Monday of every month" (`1K` = Monday, `2I` = the 2nd of them). RRULE and cron compile to exactly this form and it round-trips, so `inspect/1` on any recurrence returns the canonical selection string.
* **Position `I` and week start `q`** — the two RRULE filters that need care. See `guides/iso8601-conformance.md` §5.
  * **`I` = BYSETPOS** — ISO 8601-2 §12.9's position designator, applied last over the whole resolved set and written after what it counts. This is the one people get wrong: `{1..5}K-1I` over a month is its last **weekday** (e.g. Aug 31 Wed), *not* its last Friday, which is `5K-1I` (Aug 26). Negatives count from the end.
  * **`q` = WKST** — Tempo reads a week as starting on Monday. A rule with another week start (`WKST=SU` where it matters) is refused when it is read, as are `RSCALE` and `SKIP`.

## IXDTF suffixes (RFC 9557 extended info)

Bracketed key/value suffixes, written **once, after the whole expression** (after an interval's end, after a set, after a recurrence's rule). One written on an inner part is an error that says where it belongs.

| Suffix | Means |
|---|---|
| `2026-06-15T10:00[Europe/Paris]` | attach a **named time zone** |
| `2026-06-15T10:00/2026-06-15T12:00[Europe/Paris]` | the zone of **both** ends |
| `…[+08:45]` | attach a fixed **offset** |
| `…[u-ca=hebrew]` | interpret in a named **calendar** |
| `…[key=value]` | an arbitrary **tag**, kept in `Tempo.metadata/1` |
| leading `!` — `…[!u-ca=hebrew]` | **critical**: parsing must fail if the key is unknown, rather than ignore it |
