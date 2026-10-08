# Set operations

**Status:** in progress, 2026-10-09

The requirement (user, 2026-10-04): once validation, the walk, `Tempo.select/2`, the selection's resolver and `Tempo.explain/1` rest on one implementation, the next step is strong confidence in a single implementation of the set operations. This is the inventory that work starts from: what the operations are and where each is implemented, what holds them to an answer, what does not, what has been found, and the tasks in order. The measure of its first task has landed, and the one defect it found, in `covered/2`, is fixed.

An earlier plan of this name (April 2026, removed at `1b668b7` once the operations shipped) was their design. Its decisions still stand and are restated below, since `Tempo.Operations`, `Tempo.Compare.to_utc_seconds/1` and `guides/set-operations.md` point here for them.

## Decisions that stand

* **An interval set is the form every operation works on and returns** — an empty set for nothing, a set of one for one span. A predicate returns a boolean. Algebra on rules (two unending recurrences intersected into a rule) is deferred: a rule is listed within a window first.

* **The finer resolution** — the coarser operand's ends are extended to the finer's, so nothing is rounded: a year and a day meet at day resolution.

* **The first operand's calendar** — the second is converted to it, and the result is in it.

* **Zones are compared on the universal time line, and nothing of it is stored** — each end keeps its wall clock and its zone, and its UTC reading is worked out when two are compared, so a new time zone database changes no stored set. A value with a zone and one with none are refused.

* **Two operands are on one line** — both with a year, or both without and led by the same unit. A value with no year meets one with a year only through a `:within` window, which places a time of day on each of its days. A duration and a one-of set are never operands.

* **Members are kept** — a set holds the spans it was given, each with its metadata, and `Tempo.IntervalSet.coalesce/1` is what merges them.

## What the operations are

All are in `lib/operations.ex` and are what `Tempo` delegates to. Each brings its operands to two sorted lists of members through one preflight, `align/3`, and then sweeps them.

| Function | Answers | Computed by |
|---|---|---|
| `union/3` | The members of both | The two lists joined |
| `intersection/3` | Each member of the first cut to each member of the second it overlaps | `sweep_intersection/3` |
| `difference/3` | The time the first covers and the second does not | `sweep_difference/2` |
| `symmetric_difference/3` | The time exactly one covers | Two `difference/3` |
| `complement/2` | The window's time the value does not cover | `sweep_difference/2` of the window and the merged value |
| `members_overlapping/3` | The first's members that overlap the second | `sweep_members/3` |
| `members_outside/3` | The first's members that do not | `sweep_members/3` |
| `members_in_exactly_one/3` | The members of either that overlap none of the other | Two `members_outside/3` |
| `disjoint?/3`, `overlaps?/3` | Whether they share time | `intersection/3` is empty |
| `within?/3`, `contains?/3` | Whether one's time is all in the other's | `difference/3` is empty |
| `equal?/3` | Whether they cover the same time | The merged members, end by end |

`align/3` is ten steps in a row: a recurrence set is listed against the other operand; durations and one-of sets are refused; a zoned operand and one with no zone are refused; the two are classed as with or without a year; each is converted to a set; a time of day is placed on each day of the `:within` window; spans with no year are cut at their cycle's end; the second is converted to the first's calendar; a week date beside a calendar date is rewritten as one; and the coarser is extended to the finer resolution.

So the algebra itself is one implementation: three sweeps over two sorted lists, every end compared by `Tempo.Compare.compare_endpoints/2`.

## The same questions, answered elsewhere

Around that one implementation, five other places answer a question the sweeps also answer, each in its own code:

| Where | The question | Its own code |
|---|---|---|
| `Tempo.IntervalSet.coalesce/1`, `merged/1` | The time a set covers | `merge_in_order/1` |
| `Tempo.IntervalSet.covered/2` | The time at least n members cover | A sweep of edges, `sweep_depth/5`, between `coalesce/1`'s cut of a set with no year and its writing back |
| `Tempo.IntervalSet.covered?/2` and the backends' `overlapping/2` | The members a span of seconds overlaps | UTC seconds, in the list, the lazy and the tree backend |
| `Tempo.Interval.relation/2` and its predicates | How two spans stand, and whether one is within the other | Allen's relations; `Tempo.Interval.within?/2` beside `Tempo.Operations.within?/3` |
| `Tempo.shift/3` with `:skipping`, and a `:within` window on a recurrence | Whether a span overlaps busy time, or a window | `busy_day?/2` on UTC seconds; `overlaps_window?/3` |

None is a second algebra. But "do these two spans overlap" has four answers in the library (the sweeps' comparison of ends, the backends' seconds, Allen's relation, the window's bound), and nothing holds the four to one another.

## What holds them to an answer

* **The matrix** — `Tempo.Matrix.Checks.binary/0` runs each hand-written value of the corpus with six plain Gregorian values and each generated one with one of them, in both orders, and each with itself: about 1,100 values. For `union/2`, `intersection/2`, `difference/2`, `symmetric_difference/2` and `complement/2` it compares the time the result covers with what `Tempo.Matrix.Extent` works out from the two operands' own spans; for `members_overlapping/2` and `members_outside/2` the time the kept members cover; for the five predicates their answer. That is an answer worked out apart from the library, and no cell of it fails.

* **The measure** — `test/tempo/set_operations_measure_test.exs` builds two sets from spans between the numbered points of a line, reads each answer back as positions on that line with `Tempo.Matrix.Extent`, and compares it with what `Tempo.Matrix.Sets` makes of the same spans by arithmetic on whole numbers. What is compared is the members an answer holds, each with the mark of the member it is or was cut from, and that they come in the order of their starts; not only the time they cover. It runs every pair of sets of up to two members between five points (4,356 pairs: every way two members of each side precede, meet, overlap, nest and repeat), a fifth of them again on a tree, and generated sets of up to six members of days, of hours, of the two mixed, of hours in two zones, and of days of the Hebrew, the Persian and the Gregorian calendars. It holds `union/2`, `difference/2`, `symmetric_difference/2`, `complement/2` with a set as its window, `members_overlapping/2`, `members_outside/2`, `members_in_exactly_one/2`, the five predicates, `coalesce/1`, `covered/2`'s regions, `covered?/2`, and an answer used as an operand again. Of `intersection/2` it holds one part for each pair of members that overlap, the first's cut to the second's. For two sets with no year it holds each operation to the cells of the cycle their members hold, a member that runs through the cycle's end being one member, and for one such set `coalesce/1`, `covered/2` and `covered?/2` to arcs of the set's cycle: every set of up to two spans between five hours of the day, and generated sets of the day's hours, the week's days, the year's months and its days. `Tempo.Matrix.Sets` is itself held to each operation's definition, cell by cell. Every sweep agrees with it.

* **Examples** — `test/tempo/operations_test.exs` (113 tests, one property), `test/tempo/interval_set_test.exs` (59), and 29 for the three backends.

## What it does not reach

The matrix measures the time covered, with one plain partner at a time. The measure reaches two sets of several members, the members an answer holds, a tree beside a list, two calendars neither of which is the Gregorian, and two sets with no year. Neither reaches:

* **A `:within` window with a zone, or of several members** — the measure places times of day on one window with no zone, for every operation; a window in a zone, and one that is a set of several spans, are measured by the matrix for `complement/2` alone.

* **The forms that take a list of operands, the `:metadata` option, and a recurrence set as an operand** — held to no answer worked out apart from the library.

* **The lazy backend** — the measure builds lists and trees. What an operation gives of an unending lazy set is the deferred [plans/open-ended-set-algebra.md](plans/open-ended-set-algebra.md).

* **Three of the five other places** — `Tempo.Interval.relation/2`, `:skipping` and a recurrence's `:within` are in neither, and the backends' `overlapping/2` is reached only through `covered?/2`.

## Found

By reading the code and probing what the reading suggested. Each is reproduced. The measure found one more, since fixed: `covered/2` cut a region where one member ended as another began, and lost a member with no year that ran to or through its cycle's end. Beside that fix, and fixed too: `covered?/2` raised for a point asked of a member that runs through its cycle's end, and a tree raised on a member with no year where `new/2` returns its refusals.

* **A set operation across a week calendar's resolutions is refused** — `Tempo.difference/2` of an ISO week year and one of its weeks is a `ResolutionError`. Already an item of `TODO.md`.

## Decided

Both by the user, 2026-10-04.

* **A `:within` window bounds where a time of day is placed** — a time of day is placed on the part of each day the window holds, for every operation alike, and the other operand is not cut. It was placed on the whole of every day the window touches: with a window from noon to noon `Tempo.union(~o"T09/T17", window, within: window)` started at 09:00, before the window opened, and `Tempo.intersection/3` of the hours and a meeting at 10:00 that day returned the meeting.

* **An intersection is one part for each pair of members that overlap** — each member of the first cut to each member of the second it overlaps, as the function's documentation says, so that `metadata: {:merge, fun}` sees every pair. `sweep_intersection/3` advances whichever member ends first, which is right only where no member of an operand overlaps another: where one does it skips pairs, and which parts come back depends on which member ends first. Of the 4,356 pairs of sets of up to two members between five points, 1,947 are not one part a pair, and `[Alice 0–1]` with `[Bob 0–1, Carol 0–1]` gives Alice and Bob alone. The time covered is right throughout. An earlier reading here, that the sweep gave one fragment for each stretch of time, was wrong.

## Tasks

* [ ] **The measure widened** — a `:within` window in a zone and of several members; a lazy set within a window.

* [ ] **One answer to whether two spans overlap** — a property that the sweeps, the backends, Allen's relation and a window's bound agree on every generated pair; then whether any is to be read through another.

### Done

* [x] **A list of operands and `:metadata`, measured** — `union/3`, `difference/3` and `intersection/3` of a list are held to the operation of the first two and then of that and the third, on days, hours and days, two zones and three calendars, and to the first alone for an empty list; an intersection's part carries the first member's mark, the second's where the two are merged, and what a function makes of the two, on a line and on the four cycles. Nothing differed. 2026-10-09.

* [x] **A time of day placed inside its window** — placed on the part of each day the window holds, whatever the other operand is, with its metadata; the measure holds every operation with a window that opens and closes within a day. 2026-10-04.

* [x] **A time of day on a week window** — the window's days are those of its span, whatever units it is written in, and the time of day is placed in the day's calendar. 2026-10-04.

* [x] **An intersection of one part for each pair** — `sweep_pairs/4` holds every member of the second still open against each member of the first; the measure holds `intersection/2` part for part on every pair of sets, with a year and without. 2026-10-04.

* [x] **A span that crosses its cycle's end is one member** — each member of a set with no year is swept by its own parts (`turns/1`) and what an operation leaves of it is written back as the span it is; member operations keep or drop it whole, and an intersection there is one part for each pair of members. The measure holds every operation of two sets with no year on four cycles. 2026-10-04.

* [x] **`covered?/2` and a tree, of a set with no year** — a point is covered when a part of a member holds it, read through `Tempo.Interval.Cycle.parts/1`, and a tree's refusal of a member with no year is `new/2`'s error; the measure holds `covered?/2` on the four cycles. 2026-10-04.

* [x] **`covered/2` on the one cover** — a region runs for as long as the threshold holds, across members that meet, and a set with no year is cut at its cycle's end and written back as `coalesce/1`'s is; the measure holds its regions on a line with a year and on four cycles. 2026-10-04.

* [x] **The measure** — two sets of several members, each operation's members and their marks held to arithmetic on whole numbers, on a list and on a tree, in two zones and three calendars; an answer as an operand again in place of the laws, which follow where each answer is its definition's. 2026-10-04.
