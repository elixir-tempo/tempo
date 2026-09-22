# Lunisolar traditional-month input

**Status:** in progress, 2026-09-23 — the `+` leap-month input capability is implemented in Tempo; the tempo_holidays `:lunisolar` clause conversion remains.

## Problem

date-holidays writes lunisolar dates (`chinese`, `korean`/`dangi`, `vietnamese`, japanese-lunisolar) in **traditional** month numbering with a leap flag — `<month>-<leap>-<day>`, e.g. `08-0-15` (traditional month 8, not leap) or `06-1-01` (leap month 6, 閏6月). Tempo and Calendrical use **ordinal** months (counting the intercalary month as its own position), so traditional 8 is ordinal 9 in a year whose leap month falls at or before position 6. The mapping is **year-dependent**, so no fixed ordinal recurrence represents "traditional month 8" — it must resolve per year. This blocks a declarative `:lunisolar` clause in `tempo_holidays`.

## Interop constraint (why the representation stays ordinal)

Grounded in the code (`Calendrical.Chinese`, Chinese year 4662 = Gregorian 2025, leap month 6 at ordinal 7):

* `%Date{}.month` is an integer, and Elixir `Date.new/4` takes integers only — a leap month has **no home** in the struct. `Calendrical.Chinese.new(4662, {6,:leap}, 1)` accepts the traditional `{n,:leap}` tuple but **stores ordinal** (`~D[4662-07-01]`, `.month = 7`). The `{n,:leap}` construct is a one-directional creation convenience; the leap label is not stored (recover it via `leap_month?/1`).
* `Calendrical.Chinese.new(4662, 8, 15)` (traditional 8) → `~D[4662-09-15]`, `.month = 9` (ordinal). Tempo's `.time` stores ordinal too (`[month: 9]`).
* `Date.to_iso8601/1` on a non-ISO calendar converts to **Gregorian** — it never shows Chinese months.

So the concrete value — `%Date{}`, `Tempo.to_date`, `.time`, inspect — is irreducibly ordinal. Making the *rendered* representation traditional would force `date.month` (9) to disagree with the string (8), or push a `month :: integer | {integer, :leap}` type through all of Tempo. Rejected.

## Decision

* **`+` is a leap-month *input* convenience only.** In a lunisolar `[u-ca=…]` context, `6+M` means 閏6月 (the leap month after traditional 6), parsed to the `{6, :leap}` construct Calendrical already resolves. `+` was chosen over CLDR's `L` suffix because `L` collides with the selection frame delimiter (`FL…N`).
* **Storage and rendering are ordinal**, for Elixir compatibility. A `+` (or traditional) input resolves to its ordinal and renders ordinal — `4662Y6+M1D[u-ca=chinese]` → `4662Y7M1D`. `+` never survives a round-trip; there is nothing to disagree with `%Date{}.month`.
* **Conformance:** this is a documented deviation from ISO 8601 (which has no lunisolar/leap-month concept), in the same class as the `E` computed-event selector. The syntax guide gets a "non-conformant extension" note.

## Decisions (settled)

* **Fork A — parse-time only** (not the selection engine). Chosen 2026-09-23.
* **Bare lunisolar month = ordinal**, unchanged, for compatibility — an existing `[u-ca=chinese]` string keeps its meaning. Chosen 2026-09-23 over the fully-declarative "bare = traditional", which would silently reinterpret every existing ordinal string (today's `9M` → traditional 9 = ordinal 10).
* Consequence: the `:lunisolar` clause is **not** a pure recurrence. The non-leap traditional→ordinal step (8→9) stays a Calendrical calendar query inside `tempo_holidays` — a legitimate computation, like Easter's. `+` only adds the ability to *write* a leap month.

## `+` leap-month input capability (the deliverable)

`<n>+M` in a lunisolar `[u-ca=…]` **concrete** date is the leap month after traditional month `n` (閏n月) — Calendrical's existing `{n, :leap}` construct in ISO form. It resolves to its ordinal (year known) and stores/renders **ordinal**; `+` never survives a round-trip. `<n>M` (no `+`) stays ordinal. `+` on a non-lunisolar calendar, or where the year has no such leap month, is an error.

* `4662Y6+M1D[u-ca=chinese]` → `~D[4662-07-01]` / renders `4662Y7M1D` (閏6月 = ordinal 7).
* `4662Y6M1D[u-ca=chinese]` → ordinal 6 (unchanged).

## Tasks

* [x] Tempo tokenizer/grammar: `<n>+M` → `{:month, {n, :leap}}` (`Grammar.leap_month`, in `explicit_month`).
* [x] Tempo validation: `resolve/2` clause lowers `{n, :leap}` → ordinal via `leap_month/1` guarded by `traditional_leap_month/1 == n`, gated by `function_exported?(calendar, :leap_month, 1)`; a clean `InvalidDateError` otherwise.
* [x] Render ordinal (unchanged) — `6+M` → `7M`, `6M` unchanged, verified.
* [x] Conformance note in `guides/iso8601-conformance.md` (§5, after the `E` designator).
* [x] Tests in `test/tempo/calendar_test.exs`: `6+M`→`7M`, regular unchanged, non-leap year / wrong traditional month / non-lunisolar / Islamic (leap years not months) all error cleanly. All six gates green (4398 tests).
* [ ] `tempo_holidays`: use `+` where it constructs a leap-month lunisolar date; the non-leap traditional query stays (documented as a legitimate calendar computation, not imperative date math).
