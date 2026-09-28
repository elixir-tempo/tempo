# Set algebra over open-ended windows

**Status:** deferred, 2026-09-28

A research project for later (user, 2026-09-28): how far Tempo's set algebra can go when an operand is the lazy, unbounded set an open-ended `:within` window gives. It tests the whole algebra — every operation has to say what it can answer from a walk that never ends, and refuse what it cannot, without hanging.

## Where things stand

An open-ended window (`~o"2026-09-28/.."`) gives a recurrence's occurrences from its start as a lazy `Tempo.IntervalSet`, walked one bounded window at a time (`Tempo.to_interval/2`); a walk that finds nothing for a thousand years ends. `Tempo.IntervalSet.first/1` and the other walking questions work on it. Set operations, `Tempo.complement/2` and the calendar formats refuse an open-ended window with an error, and the lazy backend refuses every aggregate (`count/1`, `to_list/1`, set algebra) with `Tempo.UnboundedSetError`.

## Questions

* **Union** — a sorted merge of the operands' walks is lazy and exact while it keeps every member. Coalescing needs a merge that holds a member until the next one stops touching it, which an unending run of touching members (a daily recurrence) never releases.

* **Intersection** — a merge-join of two sorted walks is lazy, but an empty intersection of two unending sets (Christmas Day and Easter Sunday) never proves itself empty. It needs a walk's horizon, or an argument from periodicity.

* **Difference and complement** — the gaps between a lazy set's members are a walk too, so "the free time from now on" is lazy. The difference of a lazy set and a bounded one is lazy only on the lazy side.

* **Predicates** — `overlaps?/2` can answer `true` from a finite prefix, but `disjoint?/2` and `within?/2` only from a proof. Which predicates are semi-decidable, and what should the rest return?

* **The horizon** — a walk ends after a thousand years with no occurrence. A composed walk needs a horizon of its own, and a rule that is purely calendrical might replace the horizon with its calendar's period (400 Gregorian years).

* **Conditional members and calendar feeds** — a conditional member reads the other members' occurrences near its own, and an iCalendar or JSCalendar feed "from now on" merges events with unending rules.

## Why it matters

Each answer is a lazy walk, a finite answer from a prefix, or a refusal. Deciding which, operation by operation, exercises the half-open convention, member identity, coalescing, and the refusal that keeps an unbounded question from hanging — the algebra as a whole.
