# Tempo — Educational Video Series Plan

**Status:** draft, 2026-07-06

A Computerphile-flavoured series: one presenter, paper or a terminal, no slides-deck gloss. Informal voice, rigorous content. Each video opens *in medias res* — a bug, a paradox, or a blunt question — never with "Hi, in this video…". Hard ceiling 15 minutes; **aim for 12–13** so the edit has room to breathe.

## The spine (say it, in some form, in every video)

**Time is an interval, not an instant.** A "point in time" is just an interval at the finest resolution you bothered to state. Once you commit to that one idea, a whole *category* of date/time bugs stops being something you catch and starts being something you cannot express. Every video is one consequence of the thesis.

## Running order

The nine-video running order below is the argument in sequence. Two of them — **4 (Recurrence)** and **6 (Allen's Interval Algebra)** — were added on review; the rationale is in "Design decisions" at the end.

| # | Video | Consequence of "time is an interval" | New? |
|---|---|---|---|
| 1 | Unified time type | invalid/ambiguous instants become unrepresentable | |
| 2 | Specifying time (ISO 8601-1 / -2) | the notation *is* the interval | |
| 3 | Enumerating time | iteration = map/reduce over a bounded span | |
| 4 | Recurrence — RRULE & cron | recurrence = enumeration over an *unbounded* span | ★ |
| 5 | Set operations | intervals form a set algebra | |
| 6 | Allen's Interval Algebra | exactly 13 relations, and they *compose* | ★ |
| 7 | Tempo math | arithmetic = interval arithmetic; anchored *and* not | |
| 8 | Uncertain time | uncertainty is just a wider span / a set of spans | |
| 9 | Constraint scheduling | intervals + relations = a reasoning engine | |

## Running examples (reuse across videos for continuity)

Pick a small cast and bring them back — continuity is a Computerphile trick that makes a series feel like one argument.

* **"One month after January 31st."** The naive-arithmetic paradox. Cold-opens video 7; can be teased earlier.
* **The two-person meeting.** Alice/Bob free-busy. Threads specifying → enumerate → recurrence → set-ops → constraints.
* **The half-open `[from, to)` convention.** Planted in 1, paid off in 5 (coalescing with no gap/overlap), formalised in 6 (why `meets` is exact), reused in 9. This is the hidden hero — name it out loud every time it does work.
* **Dating the pharaohs (Egypt's 26th dynasty).** The archaeology-chronology story. Teased in 8, the climax of 9 — the single most Computerphile-native hook in the whole series.
* **The 23-hour day** (New York, 10 March 2024, spring-forward). The falsehood that recurs whenever DST comes up (2, 3, 4, 7).

---

## Video 1 — A unified time type, and why it simplifies nearly everything

**Logline.** Almost every date bug traces to one wrong assumption — that a time is a point. Drop it, and the bugs become impossible rather than merely caught.

**Cold open (0:00–1:00).** On screen: `tomorrow = now + 86_400`. "Looks fine. Ships. Then twice a year it's off by an hour, and once a year it's off by a *day* for anyone near a date line. The bug isn't the arithmetic — it's the belief that a day is 86 400 seconds. It usually is. That 'usually' is where the bodies are buried." Roll the falsehoods montage.

**Big idea.** `2026` is not a point — it's the whole year `[2026-01-01, 2027-01-01)`. `2026-06-15` is a whole day. A partial specification isn't an *uncertain instant*; it's a *definite interval*. So "February 30th" can't be constructed — there is no such interval.

**Beat sheet.**

| Time | Beat | On screen |
|---|---|---|
| 0:00 | The 86 400 bug; the instant fallacy | the one-liner, then the DST/date-line failure |
| 2:00 | The reframe: every value is a bounded span; resolution = precision | `2026` / `2026-06` / `2026-06-15` as three span widths |
| 5:00 | One type, not a zoo | contrast the stdlib `Date`/`Time`/`NaiveDateTime`/`DateTime` + interval-lib sprawl with one `%Tempo{}` |
| 8:00 | Invalid states unrepresentable | you cannot build Feb 30; partial dates are legal spans, not nulls |
| 10:00 | The half-open `[from, to)` convention | adjacent spans tile: no gap, no overlap — plant the seed |
| 12:00 | Payoff + teaser | "a category of bugs is now *unrepresentable*" |

**Payoff.** The difference between "we validate against bad dates" and "bad dates don't typecheck."

**Teaser.** "If every value is a span — how do you write one down so a human *and* a machine agree? That's a solved problem, and it's beautiful."

**Cut to stay ≤15.** Don't demo the API yet. Resist tangents into zones/DST mechanics (that's video 3). One thesis, one payoff.

---

## Video 2 — Specifying a time (ISO 8601-1 and -2)

**Logline.** ISO 8601 is designed so the notation *is* the interval; Part 2 (EDTF) extends it to the things humans actually say — "the 1960s", "around June", "one of these three."

**Cold open.** "`03/04/05`. March 4th? April 3rd? 5th of April '03? Three continents, three answers. This ambiguity has caused outages. It's also completely unnecessary." Reveal ISO 8601: big-endian, unambiguous, and — the quiet magic — **it sorts correctly as plain text**.

**Big idea.** The resolution you *write* is the span you *get*. `2026`, `2026-06`, `2026-06-15` are the same notation at three widths — the string carries its own precision.

**Beat sheet.**

| Time | Beat |
|---|---|
| 0:00 | The ambiguity problem → 8601 big-endian, lexical sort |
| 2:30 | The grammar: date → `T` → time → zone; ordinal & week dates; durations `P1Y2M`; intervals `start/end`; Tempo's `~o` sigil |
| 6:00 | Resolution = the notation carries its own precision (three widths) |
| 8:00 | ISO 8601-2 / EDTF — the *human* layer: unspecified digits (`201X` = the 2010s), qualifiers (`2004?` / `~` / `%`), sets (`{…}` all-of vs `[…]` one-of), seasons. One line on the LoC-EDTF origin (and that Part 2 is EDTF adopted by ISO — freely readable at the Library of Congress even though the ISO PDF isn't) |
| 12:00 | IXDTF suffixes `[Europe/Paris][u-ca=hebrew]` (RFC 9557) — zone & calendar annotations |
| 13:30 | Payoff + teaser |

**Payoff.** Every value the rest of the series needs, in one notation a person reads and a machine parses.

**Teaser.** "We can write a span. Watch what happens when we walk across one."

**Cut.** Don't enumerate every 8601 corner (leap seconds, expanded years) — name they exist, move on. EDTF depth belongs to video 8; here it's a *taster*.

---

## Video 3 — Enumerating times (variable months, time zones, DST)

**Logline.** Because a value is an interval, iterating it is map/reduce over a bounded span — the library knows where the real boundaries are, so you stop hand-rolling month lengths and DST.

**Cold open.** "`for (d = 1; d <= 31; d++)` — congratulations, you just generated February 30th. Now make it a calendar-month loop that survives a leap year *and* a daylight-saving change. Still confident?"

**Big idea.** Iterate a span and you get the next-finer resolution — days from a month, months (or weeks) from a year — with boundaries the calendar/zone actually has, not the ones you assumed.

**Beat sheet.**

| Time | Beat |
|---|---|
| 0:00 | The `d <= 31` bug; "the loop you're afraid to write" |
| 1:30 | Iterate `2026-02` → exactly the right days; iterate `2026` → months. The "next-finer resolution" rule |
| 4:00 | **DST**: iterate hours across spring-forward → the 23-hour day; the non-existent wall time is skipped; fall-back → 25 hours. The instant model can't even *say* this |
| 7:30 | **Calendars**: iterate a Hebrew or Islamic month — variable months, a leap month (Adar I) — same `map`, because iteration is over the calendar's own periods; cross-calendar via absolute-day projection |
| 10:30 | *60-second aside for the nerds*: a minute isn't always 60 seconds — leap seconds — and iteration walks the real second boundaries |
| 12:00 | Payoff + teaser |

**Payoff.** Month rollover, leap years, DST, non-Gregorian calendars — all just `Enum.map` over a span.

**Teaser.** "Walking a span *once* is enumeration. What about walking it *forever* — 'every second Tuesday'? Same idea, unbounded — and it's where every calendar app goes to die."

**Cut.** Don't re-explain what a zone is — assume it. Keep the leap-second bit to 60 seconds; it's seasoning, not a course.

---

## Video 4 — Recurrence: RRULE and cron without tears ★

**Logline.** A recurring event is enumeration over an *unbounded* interval, evaluated lazily — which is exactly why the parts that make iCalendar `RRULE` a graveyard (month rollover, "the last weekday", DST) are already solved by the interval model.

**Cold open.** "`0 0 31 * *` — a cron job you set for the 31st of the month. It quietly didn't run in February. Or April, June, September, November. Now try iCalendar: 'the last weekday of every month, except December.' There's a whole mini-language for this — `RRULE` — and it's where calendar apps go to die. Let's find out why, and why intervals make it boring."

**Big idea.** A recurrence is a **lazy stream of occurrences** over an open-ended span. Each occurrence is itself an interval *at its own resolution* — "the 15th of every month" is the *day* the 15th, not the month it sits in. Native ISO 8601-2 recurrence, RRULE, and cron all lower to the same stream.

**Beat sheet.**

| Time | Beat |
|---|---|
| 0:00 | Why recurrence is hard: the cron-31 trap; RRULE's BY-rule combinatorics (`BYDAY`, `BYMONTHDAY`, `BYSETPOS`, "last weekday"); unbounded `COUNT`/`UNTIL`; the "just add 7 days" bug across DST |
| 3:30 | The reframe: recurrence = a `Stream` of occurrences, `DTSTART + i × INTERVAL`, each occurrence an interval; lazy, so "every day forever" is fine until you `take` |
| 7:00 | Occurrence span = the selection's own resolution — native, RRULE, and cron all agree "the 15th" is a day; contrast a plain repeating interval that spans its whole cadence |
| 10:00 | *Engineering beat*: an infinite series needs a fuse — unbounded recurrence is capped / demands a bound, or a tiny input becomes an unbounded computation (the DoS angle) |
| 12:00 | Payoff + teaser |

**Payoff.** The thing every calendar app reimplements badly is a lazy fold over spans — and the horrible edge cases were already handled in video 3.

**Teaser.** "One schedule is a stream of spans. Two schedules — when do they collide, or align? That needs an algebra."

**Cut.** Don't tour all of RFC 5545 — pick two vicious BY-rules and the cron-31 gotcha. The point is the *reframe*, not RRULE completeness.

---

## Video 5 — Set operations (scheduling made simple)

**Logline.** Intervals form a set algebra, and half-open boundaries make it *exact*.

**Cold open.** "Alice is free 9–12 and 2–5. Bob is free 10–1 and 3–6. When can they meet, for at least an hour? You *can* write the overlap arithmetic by hand. Everyone gets an edge case wrong. Let's not."

**Big idea.** `union` / `intersection` / `difference` on spans read like the English sentence, and `[from, to)` makes coalescing fencepost-free.

**Beat sheet.**

| Time | Beat |
|---|---|
| 0:00 | The free/busy problem stated in English |
| 1:30 | `work − busy = free` (difference); `alice_free ∩ bob_free` (intersection); filter `≥ PT1H` — the pipeline reads aloud |
| 5:00 | Why half-open is load-bearing: `[9,12) ∪ [12,14) = [9,14)` exactly — no gap, no overlap, no off-by-one. Pay off video 1's seed |
| 8:00 | IntervalSets: results kept canonical (sorted + coalesced) automatically |
| 10:30 | A taste of the vocabulary: `overlaps?`, `during?`, `meets?` — we keep *naming* the ways two spans sit… |
| 12:30 | Payoff + teaser |

**Payoff.** Scheduling logic becomes set algebra you can read out loud.

**Teaser.** "We keep saying 'overlaps', 'during', 'meets'. How many such relations *are* there? Not infinite. Exactly thirteen — and that turns out to be a whole theory."

**Cut.** Introduce the relation *names* but don't derive them here — that's the next video's entire job.

---

## Video 6 — Allen's Interval Algebra: thirteen ways two things can happen ★

**Logline.** There are exactly thirteen ways two intervals can be arranged — no more, no fewer — and they form a tiny algebra you can *compute* with, even holding no actual dates.

**Cold open.** "Two events. How many ways can they sit in time? Not infinite. Not 'it depends.' Exactly thirteen. James Allen worked them out in 1983, and they turn up everywhere — temporal databases, AI planning, and, it turns out, this library." Slide two bars past each other on paper.

**Big idea.** The 13 relations are **jointly exhaustive and pairwise disjoint** — a partition of every possible arrangement — and they **compose**: knowing `A r₁ B` and `B r₂ C` constrains `A`-to-`C` to a *set* of relations. Qualitative inference, no numbers required.

**Beat sheet.**

| Time | Beat |
|---|---|
| 0:00 | Slide two intervals and derive them: precedes, meets, overlaps, finished-by, contains, starts, equals (+ the six inverses). Why *exactly* 13 (it's the orderings of two pairs of endpoints) |
| 3:30 | It's a partition: any two intervals stand in exactly one relation. `Tempo.relation/2`. The predicates `before?`/`during?`/`overlaps?` are just membership tests over relation sets — pay off video 5's "naming" |
| 6:30 | The composition table: `A before B`, `B during C` ⟹ `A ∈ {before, meets, overlaps, starts, during}`. `Tempo.compose/2` — inference with no interval in hand |
| 9:30 | Half-open, again: why `meets` is *exact* under `[from, to)` — the shared boundary, no gap, no overlap. Callback |
| 11:30 | Where it lives in the wild: temporal databases, planning, and — foreshadow — the vocabulary the constraint solver reasons in |
| 13:00 | Payoff + teaser |

**Payoff.** A finite algebra that turns "reason about time" into "look it up in a table."

**Teaser.** "That's how intervals *relate*. Next — how they *move*. Arithmetic. Starting with a question that has no right answer."

**Cut.** Don't prove the composition table; show one entry being used. The derivation of "why 13" is the fun part — give it room; the applications can be a fast montage.

---

## Video 7 — Tempo math (anchored *and* unanchored)

**Logline.** Date arithmetic is interval arithmetic — and Tempo will compute on values with *missing* parts whenever the answer is invariant to what's missing, and honestly refuse when it isn't.

**Cold open.** "What is one month after January 31st? … February 31st doesn't exist, so *every* date library has to choose. Some clamp to the 28th. Some overflow to March 3rd. Neither is 'wrong' — but you'd better know which one you've got." (Reuse the exact worked answer.)

**Big idea.** Arithmetic that respects calendars, is honest about non-reversibility, and — the unusual bit — runs on *unanchored* values.

**Beat sheet.**

| Time | Beat |
|---|---|
| 0:00 | Jan 31 + 1 month: clamp vs overflow; non-reversibility (`+1mo −1mo ≠ identity`); leap-year dependence |
| 3:30 | Anchored math: add/subtract durations across month/year/DST boundaries correctly |
| 6:30 | *Aside for the CS crowd*: `+10 000 days` is O(1) via absolute-day conversion, not a 10 000-step loop — why naive stepping is quadratic and how you kill it (the same trick that made large recurrences from video 4 fast) |
| 9:00 | **Unanchored** math: `~o"T10:30" + PT2H`; `~o"1M31D" + P1D = 2M1D` (January is *always* 31 days — no year needed); but `2M29D + P1Y` → `RequiresAnchorError` (leap-year-dependent) |
| 12:00 | The principle: compute when the result is invariant to the unknown; refuse cleanly when it isn't — never guess |
| 13:30 | Payoff + teaser |

**Payoff.** Arithmetic that's calendar-correct *and* knows the boundary of what it can honestly answer.

**Teaser.** "We've assumed we *know* the date. Historians, archaeologists, a database column full of NULLs — often you don't. Can you still compute? More than you'd think."

**Cut.** The O(1)-days aside is a treat, not the point — 90 seconds. Don't wander into zones here.

---

## Video 8 — Uncertain times (and how to handle them, quite well)

**Logline.** Uncertainty is just a wider interval, or a set of them — so in a library where every value is already a span, "we're not sure" is a first-class value, not a bolt-on.

**Cold open.** "When was the Great Pyramid built? 'Around 2560 BC.' That's not a date — it's a *cloud* of dates. How does a type hold 'around 2560 BC' without lying about precision it doesn't have?"

**Big idea.** EDTF gives the notation; because Tempo values are spans, uncertainty flows through comparison, set-ops, and arithmetic — and you reason about it with three-valued logic: *certain / possible / impossible*.

**Beat sheet.**

| Time | Beat |
|---|---|
| 0:00 | "Around 2560 BC" as a cloud; the `birth_year`-known-to-the-decade DB case |
| 2:00 | Kinds of uncertainty: reduced precision (`201X` = some year in the 2010s), qualifiers (`2004?` / `~`), sets (`[2020,2021,2022]` one-of), open ranges (`../2020`) |
| 5:30 | Comparing uncertain values: `within_certainty(~o"20XX", window)` → `:possible` (some years in, some out); the `certainly_*?` / `possibly_*?` predicates — three-valued temporal logic |
| 9:00 | It composes: a masked year is read across *every* year it admits, through comparison and set ops |
| 12:00 | Payoff + teaser |

**Payoff.** Store and compute with "we're not sure" without dropping to a string or a comment — and the library tells you when a comparison is actually decidable.

**Teaser.** "Several uncertain events, but you *do* know their order and rough gaps — you can pin them down. That's not storage any more. That's reasoning."

**Cut.** Don't fully formalise three-valued logic; show it working. Save the *solving* for video 9.

---

## Video 9 — Constraint-based scheduling (the natural outcome)

**Logline.** Know the *relations* between intervals but not their absolute positions, and you have a temporal constraint network — solve it and every interval's tightest possible bounds fall out. Same tool for dating pharaohs and scheduling a build.

**Cold open.** "We don't know when the pharaohs of Egypt's 26th dynasty actually reigned. But we know the *order*, roughly how long each reigned, and a couple of fixed astronomical anchors. From only that — can you compute each reign's earliest and latest possible dates? You can. And it's the identical machinery that finds the critical path in your CI pipeline."

**Big idea.** Periods with start/end/duration bounds + asserted Allen relations = a Simple Temporal Problem: a weighted graph where consistency is "no negative cycle" and tightening is "all-pairs shortest paths." The series converges here.

**Beat sheet.**

| Time | Beat |
|---|---|
| 0:00 | The 26th-dynasty puzzle; "relative order + rough gaps → absolute windows?" |
| 2:30 | From video 6: you *named* the relations to check facts; now *assert* them as unknowns to solve |
| 4:30 | The STP model: bounds + sequences + relations → graph; consistency = no negative cycle; tighten via Floyd–Warshall shortest paths. Name-drop Allen; Dechter, Meiri & Pearl |
| 8:00 | Same engine, second face: critical-path project scheduling — tasks, durations, finish-to-start deps, deadlines → each task's early/late window and the critical path; `trace/3` *explains* a bound |
| 11:00 | Certainty queries: is A *necessarily* before B given every constraint? — ties back to video 8's three-valued logic and video 6's relations |
| 13:00 | Series close: this is the payoff of "time is an interval" — not fewer bugs, a reasoning engine. Everything converges |

**Payoff / series close.** Specify → enumerate → recur → set-ops → relate → move → uncertainty → *reason*. Return to video 1's thesis and land it.

**Cut.** Don't teach Floyd–Warshall in full — show the graph, state the property, run it. The archaeology story is the emotional core; give it room.

---

## Design decisions (why the series is shaped this way)

* **Recurrence (video 4) earns its own episode.** It's the most *relatable* developer pain in the whole domain — everyone has been burned by `RRULE` or a cron job that skipped February — and it drops in perfectly right after enumeration, because a recurrence just *is* enumeration over an unbounded span. It also sets up the "two schedules colliding" hook for set operations.

* **Allen's Interval Algebra (video 6) earns its own episode.** It's the most Computerphile-native idea Tempo contains: a finite, elegant algebra with a composition table that lets you infer relations with no data in hand. Left buried inside set-ops and constraints it gets short-changed; as its own episode it's a strong, shareable standalone *and* it de-loads videos 5 and 9. "Thirteen ways two things can happen" is a title that travels.

* **The half-open `[from, to)` convention is a through-line, not a footnote.** Planted in 1, load-bearing in 5 (exact coalescing), formalised in 6 (why `meets` is exact), reused in 9. Say the one-liner every time — "inclusive start, exclusive end; that's the whole trick" — so viewers feel it accrue.

* **Keep it language-agnostic.** Computerphile's reach comes from selling *ideas*, not APIs. Mention Elixir and the `~o` sigil once; show the pipelines because they read beautifully; but every episode should leave a Python/Rust/Java viewer wanting this, not thinking "that's an Elixir thing." This is the single biggest risk to reach — guard it in every edit.

* **The falsehoods guide is the cold-open reservoir.** `guides/falsehoods.md` is a ready-made bank — each falsehood is a 30-second opener (24-hour day, wall times that don't exist, 01:30 twice on fall-back, "no year 0", 1582 meaning different things in different countries). Mine it across the series.

## Release strategy & dependencies

* **1** is the manifesto — release first; it frames everything.
* **2** is the best *standalone* gateway (broad ISO-8601 appeal, no prerequisites). Promote it hardest to pull newcomers in, even though 1 is the thesis.
* **4 (Recurrence)** and **6 (Allen)** are also strong standalones — "why is 'every second Tuesday' so hard?" and "thirteen ways two things can happen" both travel on their own.
* **3, 5, 7** mostly stand alone once 1 is seen.
* **8 → 9** are a pair; 9 leans on 6 (relations) and 8 (three-valued certainty). Release them close together, with 9 as the finale.

## Production notes

* One presenter, paper or terminal; no title-card preamble — cold open, always.
* Target **12–13 minutes**; treat 15 as the hard fail line.
* Continuity: reuse the running cast (Alice/Bob, Jan 31, the pharaohs, the 23-hour day) so the series reads as one argument.
* Every video ends on a one-line thesis callback + a concrete teaser for the next.
* Tone: Computerphile — an expert thinking out loud, tangents welcome, the *why* over the API. Rigorous underneath, relaxed on top.
