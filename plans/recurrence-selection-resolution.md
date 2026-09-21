# Recurrence selection resolution

**Status:** planning, 2026-09-21

An unanchored recurrence now materialises against a `:bound` alone
(`plans/` companion to the `to_interval/2` bound-anchoring change). That fix
is correct for every selection whose occurrences are **day resolution or
finer** — every holiday form, and time-of-day recurrences. A gap remains for
selections **coarser than a day**.

## The gap

A native "every June" materialises to June 1st, a single day, instead of
June, a whole month:

```elixir
Tempo.select(~o"2026", ~o"6M")
#=> ~o"2026Y6M/7M"                     # the month — the intended shape

{:ok, june} = Tempo.from_iso8601("R/../P1Y/FL6MN")
Tempo.to_interval(june, bound: ~o"2026")
#=> {:ok, IntervalSet<[~o"2026Y6M1D/2D"]>}   # June 1st — wrong
```

It is **pre-existing and independent of the bound**: an explicit anchor
fails the same way (`R/2026-01-01/P1Y/FL6MN` → June 1st), and a coarse
anchor is worse still (`R/2026-01/P1Y/FL6MN` → empty, count 0).

## Root cause

Two facts combine:

* `Selection.apply/4` returns **nothing** for a month-resolution candidate
  and a month selection, so the materialiser is forced to feed it a
  day-resolution candidate (the bound-anchor floor, and any real day
  anchor). The selected point then carries day resolution.

* `resize_to_resolution/1` sizes each occurrence to `resolution(from)` of
  that **selected point** — day — so "June" comes back a day wide.

## Why the obvious fix breaks RRULE

Sizing to the **selection's** resolution instead (month for `L6M`, day for
`L15D`, hour for `LT9H`) fixes native selections but breaks RFC 5545: there
`FREQ=YEARLY;BYMONTH=6` with `DTSTART=2026-06-15` means **June 15**, a day —
`BYMONTH` *filters*, `DTSTART` pins the day. Both carry
`[selection: [month: 6]]`, so the selection's resolution cannot tell "the
month of June" (native) from "filter to June, keep the DTSTART day" (RRULE).
A prototype that sized to the selection resolution turned 12 BYMONTH /
BYWEEKNO tests red.

The distinguishing signal is whether the day component is **named** (RRULE's
`DTSTART`) or an **artefact** of anchoring (the native selection has no day).
`origin_day` is set in both cases, so presence alone does not separate them.

## Options

* **Fix `Selection.apply/4` for coarse candidates** — make a month selection
  on a month candidate yield the month. Then anchor at the selection's
  resolution and leave `resize_to_resolution/1` reading the selected point.
  RRULE is untouched (its day lives in `DTSTART`, not the candidate). This is
  the principled fix; it is a change inside the `Selection` engine.

* **Mark the synthesised anchor** — flag the bound-derived day anchor so the
  resize can coarsen only artefact days, never a real `DTSTART` day. Smaller
  blast radius, but it is scar tissue on the shared engine.

## Tasks

* [ ] Reproduce the `Selection.apply/4` empty result for a coarse candidate in a focused `Selection` test.

* [ ] Decide between the two options above; the first is preferred.

* [ ] Extend the resolution matrix (year and month selections) once a fix lands.
