# A value that carries its position (decision 62)

**Status:** design and prototype, 2026-10-15. Measured on the mise-current toolchain against `bench/against_1_6_bench.exs` and the cases below.

## The question

A value is held as its units as written (`[year: 2026, month: 6, day: 15, hour: 10]`), and each question of it walks them again: its resolution, whether it is plain or has a year, which of its units are of the date and which of the clock, its frame, its extent. Profiled by layer, walking unit lists is 35 to 50% of a rule's time (decision 62's context). Should a value inside the engine be held with its frame, extent and resolution reckoned once, and written as units only when it is handed back?

## What one occurrence costs

A daily rule's occurrence (`FREQ=DAILY` from 23:59 in Chicago) takes about 6.4 µs. Of that:

| Work | Each | Per occurrence | Share |
|---|---:|---:|---:|
| Placing a value (`Spans.extent/1`, a zoned minute) | 312 ns | 5 | about 25% |
| Building a value at a position (`Spans.value_at/4`) | 480 ns | 2 to 3 | about 20% |
| The rest of the walk: the period's selection, its steps and bounds | | | about 55% |

A plain recurrence (`R30/2023-02-21T23:59:00/P1D[America/Chicago]`), with no rule, took as long: 6.8 µs an occurrence. Its builder, `Recurrence.occurrence/4`, placed the first span's start, which is the same for every occurrence, twice for each, and placed each next start again though the step before had found it: six placings and three buildings an occurrence.

## Two places a position is lost

1. **Within a module, between two steps that both know it.** `occurrence/4` shifts a position, builds the value at it, and then places the value to learn the position it was built at. The rule walk's builder, `occurrence_at/4`, had already stopped doing so (decisions 37 and 56): the first start placed once for a walk, each next start kept for the step after.

2. **Across a module boundary.** `Select.in_period/3` answers values, and the walk places what it picked again. Carrying positions across it was built and reverted (decision 57): 0 to 13% for a second shape through all of `Select`.

The general form of this decision, a second representation of a value through the whole engine, would recover the second kind everywhere. Its ceiling is measured above: placing is about a quarter of an occurrence, and the values the walk builds must still be written as units, since each is handed back. Recovering it would cost a second shape in `Spans`, `Select`, `Expand` and `Recurrence`, with the rule that the carried position is the value's own kept by hand at each step, which decision 57 found harder to change safely.

## The design

Not a second representation. One rule instead, which the code already keeps where it is fast:

> A step that finds a position hands it to the next step that needs it, within its module, rather than writing a value and having the next step place it again.

Positions cross a module boundary only where they already do, in the occurrence-and-extent pairs of a walk (`Tempo.Recurrence`, `Tempo.Spans.windowed/2`), which stay inside the walk and are dropped before an occurrence is handed back.

## The prototype

Plain recurrences are built by the rule walk's builder: `Recurrence.occurrences/4` maps each index through `occurrence_at/4` with a walk of its own, so the first start is placed once and each next start is kept; the occurrence-and-extent pairs it makes are deduplicated, bounded and windowed as the walk's are, and dropped at the end. An extent is carried only on a line: on a cycle each occurrence is its own, as before, and an occurrence with none is placed where it is asked (`landing/1`, `Spans.ends_by?/2`, `Spans.starts_before?/2`).

| Plain recurrence | Before | Prototype |
|---|---:|---:|
| R30 daily, in Chicago | 204 µs | 116 µs |
| R100 daily, floating | 338 µs | 192 µs |
| R60 monthly from the 31st | 214 µs | 106 µs |
| R720 hourly, in Chicago | 4,356 µs | 2,771 µs |

36 to 50% faster, every test passing. The change is one function and three clauses, and it leaves one builder of an occurrence of a span with a length where there were two in use.

## Recommendation

* Keep the prototype.
* Do not build a second representation of a value through the engine: its measured ceiling is about a quarter of an occurrence, at the cost decision 57 declined.
* Hold the rule above in review, as decisions 37, 56 and this prototype did: where a step throws away a position the next step places again, within one module, hand it on.
