# Lunisolar traditional-month input

**Status:** in progress (revised 2026-09-24) — extending the traditional-month designator into the selection frame so lunisolar holidays become declarative recurrences, under a lowercase-extension convention. Supersedes the earlier "the `:lunisolar` clause stays a Calendrical query" finding: the priority changed, `recurrence_set` now wants lunisolar as a re-materialisable recurrence.

## Why this reopens a settled decision

The `+` leap-month *input* for concrete dates shipped (see "Prior work"), and the 2026-09-23 Findings then declined a traditional-month *selection* spelling because `materialise/2` already computed lunisolar dates correctly, so a declarative form "served zero real holidays." That calculus changed: `Tempo.Holidays.recurrence_set/2` now wants every holiday as a standalone recurrence, and the 57 lunisolar rules are the largest remaining `:needs_window` bucket. So we add the selection-frame spelling.

## Convention: lowercase designator = Tempo extension

Uppercase designators are ISO 8601 (`Y M D H W O K I N`, `E` today); lowercase are Tempo extensions. The `^` exclusion domain and the `e`/`o`/`l` year filters already follow this; making it explicit gives a single learnable rule ("if it's lowercase, it's ours") and names the new designators.

## Design

* **`m` — traditional month, in both concrete dates and the selection frame.** `<n>mD` is traditional month `n`. Allowed on **every** calendar (per the 2026-09-24 decision): on a non-lunisolar calendar (Gregorian, Hebrew, Persian, Julian, Coptic) there is no ordinal/traditional distinction, so `m` is identical to `M` and resolves to the ordinal month directly — no calendar-specific rejection. On a lunisolar calendar it is the traditional month, resolved to the ordinal per year by Calendrical. `M` (uppercase) stays the ordinal month, unchanged, so every existing string keeps its meaning.
* **`+` — leap month.** `<n>+m` is 閏n月 (the leap month after traditional `n`), Calendrical's `{n, :leap}` construct. Lunisolar only; an error where the calendar has no leap month or the year has no such one.
* **`E` → `e`.** The computed-event selector becomes lowercase. Nothing published depends on `E`, so it is a clean rename — no dual-support.

**The selection frame is the new capability.** Today `<n>+M` is parsed by `explicit_month` only, so `R/../P1Y/FL6+M1DN[u-ca=chinese]` is a parse error. The §12 selection sublanguage (`FL…N`) gains `m` and `+m`, so `R/../P1Y/FL8mD15DN[u-ca=chinese]` reads "traditional month 8, day 15" — the declarative lunisolar recurrence.

**Rendering is context-dependent, because a recurrence must be year-independent.**

* In a **concrete date** (year known) `m`/`+m` resolve to the ordinal and render ordinal `M`, exactly as the shipped `+` does — `4662Y6+mD1D` → `4662Y7M1D`. There is a `%Date{}` to agree with, and it is ordinal (see Interop constraint).
* In a **recurrence selection** (no year) `m` must **stay `m`** — resolving to a fixed ordinal would be wrong in the years whose leap month shifts the numbering. So `R/../P1Y/FL8mD15DN[u-ca=chinese]` round-trips as written, and the traditional→ordinal step happens per year at materialise time.

**Year attribution — the hard part — is the problem calendar selections already solve.** Which lunar year's traditional month 8 lands in a given Gregorian bound, and cases like Ông Táo (month 12) belonging to the *following* Gregorian year, is exactly what a bounded `[u-ca=hebrew]`/`[u-ca=islamic]` selection resolves (selection + bound → 0/1/2 occurrences). It falls out the same way **iff** `m` in a selection resolves per lunar year during materialisation (through Calendrical's `gregorian_date_for_lunar/3` + a Gregorian-year filter) rather than to a fixed ordinal.

## Interop constraint (unchanged — storage stays ordinal)

`%Date{}.month` is an integer; a leap month has no home in the struct. `Calendrical.Chinese.new(4662, {6,:leap}, 1)` accepts the traditional `{n,:leap}` tuple but **stores ordinal** (`~D[4662-07-01]`, `.month = 7`); the leap label is recovered via `leap_month?/1`. `Date.to_iso8601/1` on a non-ISO calendar converts to Gregorian. So a *concrete* value is irreducibly ordinal, which is why `m`/`+m` render ordinal there. Only a *recurrence* (which has no `%Date{}`) keeps the traditional spelling.

## Tasks

Tempo:

* [ ] Grammar: `<n>m` / `<n>+m` in `explicit_month` (concrete) and in the §12 selection frame; `e` in place of `E` in `selection_event`.
* [ ] Parser/AST: a traditional-month marker distinct from the ordinal `:month`, carried through the selection AST.
* [ ] Materialisation: a traditional-month selection resolves per year via Calendrical for a lunisolar calendar, as the ordinal for a non-lunisolar one; year attribution rides the existing bounded-selection machinery.
* [ ] Rendering: `m` stays `m` in a recurrence, resolves to ordinal `M` in a concrete date; `e` renders lowercase.
* [ ] `E`→`e` sweep: grammar, `Tempo.Event`, inspect, cookbook, guides, tests.
* [ ] Tests + round-trip; all six gates.

Calendrical:

* [ ] Confirm the per-year traditional→ordinal resolution the selection needs is exposed (likely already `gregorian_date_for_lunar/3`); add if not.

tempo_holidays:

* [ ] `:lunisolar` `base_recurrence` clause → `R/../P1Y/FL<m>mD<d>D[u-ca=<cal>]` (with `+m` for leap); validate against `materialise/2` across a leap and a common year.
* [ ] `E`→`e` in the easter/orthodox/equinox/solstice/solar-term recurrence forms.

## Prior work (shipped): `+` concrete leap-month input

`<n>+M` in a lunisolar `[u-ca=…]` **concrete** date is the leap month after traditional `n`, resolving to its ordinal (year known) and storing/rendering ordinal; `+` never survives a round-trip. Implemented 2026-09-23 in `Grammar.leap_month` (`explicit_month`), lowered in `Validation.resolve/2` via `leap_month/1` guarded by `traditional_leap_month/1`, with tests in `test/tempo/calendar_test.exs` and a conformance note in `guides/iso8601-conformance.md`. The revised design folds this into the `m` designator (`+m`) and extends it to the selection frame.

## Superseded finding (2026-09-23) — "the clause stays a Calendrical query"

The earlier finding kept `tempo_holidays`' `:lunisolar` clause a per-year Calendrical query on three grounds: no corpus holiday uses a leap month (all 71 are `<m>-0-<d>`); `+` did not reach the selection frame; and a bare selection month is ordinal with a year-dependent, year-attributed traditional→ordinal step. The first two are addressed by the `m` selection designator above; the third is real but is the same year-attribution a bounded calendar selection already handles. Superseded because the goal is now a declarative recurrence for `recurrence_set`, not merely a correct materialised date.
