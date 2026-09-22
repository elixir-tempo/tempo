# Selection extensions for holiday rules

**Status:** implemented, 2026-09-22

Everything planned here has landed: the `I`/position convergence (see [i-position-convergence.md](i-position-convergence.md)); ISO 8601-2 §12.10 selection-with-a-time-interval (windows + nesting, resolving the spec's own examples — Election Day, "2nd Sunday before April 4", Good Friday); and the computed-event mechanism (`(name)E`) for Easter/orthodox-easter, the equinoxes/solstices, the first new moon of the year, and the 24 solar terms (per-meridian). The one open thread is a dependency: `mix.exs` points at the local Calendrical checkout for the Vietnamese/Korean/Japanese lunisolar calendars (see Blocked), to be reverted to a hex requirement once Calendrical ships them.

Downstream `tempo_holidays` wants to express every date-holidays rule as a Tempo floating-recurrence value (see `tempo_holidays/plans/holiday-grammar.md`). This document is the Tempo-side design for the selection operators that needs. The headline finding, after reading ISO 8601-2:2019 §12 (Selection of date and time), is that **most of what looked like "extensions" is already standard ISO 8601-2** — so the work is largely completing Tempo's §12 support and reconciling one divergence, not inventing symbols. We extend only where ISO genuinely has no form (computed events).

## What is already standard ISO 8601-2 §12

Verified against the spec (§12) and against Tempo's parser (all forms below parse today; materialisation is incomplete — see gaps).

* **Relative / nearest weekday** — a day-range selection plus a weekday plus a position. ISO §12.11 Example 6 is literally `L4M{19..26}D4K1IN` = "first Thursday after April 18". So:
  * "Friday after 11-11" → `FL11M{11..17}D5K1IN` (the Friday in Nov 11–17).
  * "Monday before 06-01" → `FL5M1K-1IN` (last Monday of May).
  * "1st Sunday after 09-01" → `FL9M{1..7}D7K1IN`.

* **Day offset / span** — §12.10 "selection with time interval": `[selection]/[duration]`, and the duration may be **negative** (§12.11 Example 7 uses `/-P20D` for "20 days before"). So "1 day before X, 5-day span" and "N days after the equinox" are `…/-P1D…` / `…/PnD…`, no new symbol.

* **Year parity** — a year digit-set (`{0,2,4,6,8}Y` = even years, §12.11 Example 8) or a stepped year range (`{2000..2100//2}Y`, parses today).

* **Leap years** — the `366O` ordinal-day idiom matches only leap years (§12.5 NOTE), and `2M29D` selects the leap day (§12.11 Example 3). Filtering an arbitrary holiday to leap years is a set-intersection with the leap-year set (the `tempo_holidays` interval-set layer), not a selection operator.

None of these needs a new designator. They are the ISO 8601-2 §12 selection sublanguage.

## The divergence to reconcile: `I` / position

ISO §12.9 defines **`I` as the position (set-position) designator**: `positionSR = [position]["I"]`, "applied last, selecting the i-th of the occurrences already selected". "First Monday" is `L1K1IN` — weekday `1K`, then position `1I`, position on the **right**, lower-order. This is exactly RFC 5545 `BYSETPOS`, and because ISO's `I` operates over the whole resolved set, ISO needs no separate set-position designator.

Tempo currently uses `I` differently — as an **instance paired to a weekday**, written to the **left** (`FL5M-1I1KN` = last Monday of May) — and invented a **`V`** designator for `BYSETPOS` (documented in `guides/iso8601-conformance.md` §5). So Tempo diverges from ISO in both the meaning and the ordering of `I`, and carries a `V` that ISO folds into `I`.

To express holidays in *standard* ISO 8601-2, Tempo should support ISO's `…K…I` position form (weekday then position, position over the resolved set). Whether to converge on the ISO model (making `V` an alias or a deprecated synonym) or to keep both and document the mapping is the main open question here; it affects how ISO-standard the emitted holiday forms are, and whether `Tempo.to_iso8601/1` should prefer the ISO order.

## The one genuine extension: computed events (Easter, equinox, solar term)

ISO 8601-2 has **no** form for an algorithmically computed recurrence — Easter/computus, or an astronomical event (equinox/solstice/solar term). These are the only families that need a real extension. Options, in order of preference:

* A **named-event selection designator** — one new letter (the `V`/`Q` precedent: a project-specific selection designator, documented in the conformance guide) whose value names an event resolved by a function (`Tempo.Event.Easter` already exists but is unwired; equinox/solstice already back the season codes via `Astro`).

* An **IXDTF `[event=…]` annotation** — carries the event name as elective metadata, keeping the value a valid annotated string. Bounded by the current `to_iso8601/1` not re-emitting `:extended` suffixes.

Extend only for this, and only the one symbol we use.

## Gaps in Tempo's current §12 support

The standard forms parse but do not all materialise. Observed: `FL11M{11..17}D5K1IN` raises `FunctionClauseError in Calendrical.Base.Month.days_in_month/3` when expanded onto a year — a day-range-in-selection materialisation bug. Completing and fixing §12 materialisation (day ranges, negative-duration §12.10, `366O` leap matching, the position semantics) is the bulk of the work, ahead of any new designator.

## Tasks

* [x] Reconcile `I`/position with ISO §12.9 (meaning, ordering, the `V` relationship). Converged on `I` as §12.9 position, retired `V`. See [i-position-convergence.md](i-position-convergence.md).

* [x] Fix the day-range materialisation bug (`days_in_month/3`). It was an artefact of the deleted `fold_byday_selection` path; day-range + weekday + position patterns (Election Day, Friday-after-a-date) all materialise now.

* [x] Add the computed-event mechanism for Easter and the equinox/solstice events (`(name)E` designator, `Tempo.Event`). `Tempo.explain/1` renders them; documented in `guides/iso8601-conformance.md` §5.

* [x] **§12.10 selection with a time interval** — `[selection]/[duration]` makes each resolved date the start of a window; nested outer selectors pick within it. Resolves the spec's Examples 1, 3, 7, 8 (Election Day, "2nd Sunday before April 4"), Good Friday, and terminal windows. `Tempo.RRule.Selection.apply_windowed_selection/6`.

* [x] **Solar terms** — the 24 jié-qì (`(qingming)E`, `(dongzhi)E`, …) resolved via `Calendrical.Lunisolar.solar_longitude_on_or_after/3` at the Chinese meridian (`Calendrical.Chinese.location/1`). Not blocked on Astro after all — `Calendrical` has them.

* [x] **Windowed `explain/1` prose** — reads "on the last Friday within the 7 days before Easter"; a terminal window reads "the 5 days from the 4th Wednesday".

* [x] **Solar terms for other meridians** — `Tempo.Event.date/3` takes the lunisolar calendar (`Calendrical.Chinese` default, or Vietnamese / Korean / LunarJapanese) whose meridian to compute the term at. Needs the local Calendrical checkout (path dep — see Blocked).

* [x] **`new-moon` event** — the first new moon of the year, via `Astro.date_time_new_moon_at_or_after/1`.

* [x] **Year digit-sets and `366O` leap matching confirmed** — `{0,2,4,6,8}Y` parses; `FL366ON` yields Dec 31 only in leap years (2024, 2028); the `2M29D` leap-day selection across a year set yields only leap years (v1.6.4).

### Blocked

* [ ] **Restore the hex Calendrical dependency** — `mix.exs` points at the local Calendrical checkout (`path:` + `override: true`) for the Vietnamese/Korean/Japanese lunisolar calendars, which are ahead of the published release. Revert to `{:calendrical, "~> 1.x"}` once Calendrical ships them; CI cannot resolve a path dep.
