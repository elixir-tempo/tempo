# Plan — Cookbook-grade use cases for further articles

**Status:** planning, 2026-07-09

A pipeline of real-world use cases to receive the "Business/252 treatment": a cookbook recipe in pipeline-prose style, executed and verified, then posted to the [ElixirForum Tempo thread](https://forum.elixirforum.com/t/tempo-a-unified-time-type-that-models-time-as-interval-sets-not-instants/75083).

## The treatment (what makes one work)

Distilled from Business/252 and Ramadan working hours — a candidate earns an article when it has all five:

* **A normative rule, not a toy.** A law, a market convention, a compliance requirement — something with a citation (ANBIMA day count; UAE Federal Decree-Law 33/2021 Art. 17).

* **A quirk that surprises.** The fixed 252 denominator making a year fraction > 1; Ramadan drifting ~11 days a year across the payroll calendar.

* **A 1:1 mapping to Tempo verbs.** The domain's own vocabulary should *be* the pipeline (`members_outside` = "workdays that aren't holidays"). If the example needs plumbing, an abstraction is missing — add it first.

* **Real data, executed numbers.** Import the actual dataset where possible; run every snippet; document only verified output. Pin normative data (dated `.ics`) rather than live feeds.

* **Honest caveats.** Where the model approximates reality (tabular vs moon-sighted Islamic calendar; holiday lists as pricing data), say so and give the production advice.

## Published

* **Business/252 — Brazil's business-day year fraction.** Cookbook §13; posted to the forum thread (post 44). Bonus outcome: profiling the recipe exposed the O(n×m) member-preserving filters, fixed to an O(n+m) merge-sweep in 0.18.1 (~675 ms → ~2 ms).

* **Ramadan working hours — statutory hours across two calendars.** Cookbook §13, immediately after Business/252. UAE Art. 17 two-hour reduction; Gregorian work year ∩ Islamic month 1447-09; verified 239 × 8h + 22 × 6h = 2,044 hours for 2026, identical pipeline for 2027/1448 with Ramadan ten days earlier. Bonus outcome: exposed the stale-`u-ca`-tag round-trip bug in cross-calendar set ops (task chip filed). Draft post in `articles/ramadan-working-hours-uae.md`.

## Candidates (in rough order of punch)

All three candidates below were executed on 2026-07-07: cookbook recipes verified and shipped, forum-post drafts saved in `articles/`. Bonus outcomes: the on-call recipe surfaced the week-axis set-op crash (chip task_16d4814d) and drove the `Tempo.Set` select-base addition; the daylight recipe surfaced the `from_elixir` microsecond crash (chip task_902f6909) and drove `Tempo.IntervalSet.duration/1`.

### DST payroll double-hour

**Pitch:** A night-shift worker on the November fall-back night in `America/New_York` works the 01:00–02:00 hour twice — and under FLSA "actual hours worked" must be paid for 9 hours, not 8. Tempo's DST-aware enumeration emits the folded hour twice by design (distinguished by `:shift` offset, RFC 9557 disambiguation), so `Enum.count` of the shift interval is simply 9.

**Quirk:** The 23-hour and 25-hour days that break naive `hours = (end - start)` payroll code; the spring-forward twin (a shift crossing the gap hour is 7 paid hours).

**Exercises:** zone-aware intervals, DST fold/gap semantics in enumeration, duration vs sub-point counting (ties into the Counting note in the IntervalSet moduledoc).

**Feasibility notes:** smallest of the candidates — a dozen lines. Verify the fold actually emits twice for an explicit interval spanning the transition (the Enumerable.Tempo reduce handles `{:ambiguous, first, second}`; confirm the Interval reduce path does too). Good quick-turnaround post.

### On-call fairness audit

**Pitch:** Import a PagerDuty-style rotation (`.ics` export), intersect each engineer's shifts with weekends and nights, and produce a fairness table of antisocial-hours load per person per quarter.

**Quirk:** Rotations look fair by shift count but skew badly by weekend/night burden; the set algebra makes the skew visible in a few lines.

**Exercises:** `Tempo.ICal.from_ical_file/1` with per-member metadata (who), `select` with `weekend/1`, `intersection`, duration accumulation across an IntervalSet, group-by on member metadata.

**Feasibility notes:** most relatable to the Elixir/ops crowd, but reuses the iCal + select + member-filter shape of Business/252 — schedule it a few posts after, not immediately next. Synthesize a small three-person rotation inline (or ship a fixture) rather than depending on a PagerDuty account. Check: does per-event metadata (attendee/summary) survive `from_ical` well enough to group members by person?

### Daylight-limited work (Tempo + Astro)

**Pitch:** Outdoor crews (solar installers, surveyors, film units) can only work *workday hours ∩ daylight*. Compare workable hours in Helsinki vs Lisbon across December — or across the year — using the Astro ephemeris for sunrise/sunset.

**Quirk:** Helsinki in late December has under six daylight hours, none before 09:30; the same query in June needs the `bound:` because the sun barely sets. Geographic + seasonal punchline, chart-friendly.

**Exercises:** the Tempo + Astro pairing (sunrise/sunset as interval endpoints), `from_elixir` interop for DateTime pairs, intersection of time-of-day spans with day members, duration sums.

**Feasibility notes:** Astro is already a dependency with the ephemeris cached locally. Needs a small bridge: `Astro.sun_rise_set` (or equivalent) per day → build `%Tempo.Interval{}` list → `IntervalSet.new`. If the bridge feels like plumbing in the example, that is the abstraction-gap signal — consider a `Tempo.daylight(location)` selector first (which would itself be a nice release feature).

## Backlog (brainstormed, not yet vetted)

* **Lease/contract proration under 30/360 vs actual/actual.** Day-count conventions again — strong finance quirk (February "has" 30 days), but close cousin of Business/252; save for variety later.

* **Aviation crew rest (FAA/EASA duty limits).** "Minimum 10 hours rest, of which 8 uninterrupted sleep opportunity" — adjacency + duration predicates on interval sequences. Normative and quirky but data-heavy; needs careful scoping to stay short.

## Sequencing suggestion

DST payroll next (small, punchy, universally relatable, different shape from the last two), then daylight/Astro (visual, showcases the ecosystem pairing), then on-call fairness (once enough distance from Business/252's iCal shape), with the backlog for later variety.
