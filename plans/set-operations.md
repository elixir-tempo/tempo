# Set operations

**Status:** in progress, 2026-10-04

The requirement (user, 2026-10-04): once validation, the walk, `Tempo.select/2`, the selection's resolver and `Tempo.explain/1` rest on one implementation, the next step is strong confidence in a single implementation of the set operations. This is the inventory that work starts from: what the operations are and where each is implemented, what holds them to an answer, what does not, what has been found, and the tasks in order. The measure of its first task has landed; no library code has changed yet.

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
| `intersection/3` | The time both cover | `sweep_intersection/3` |
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
| `Tempo.IntervalSet.covered/2` | The time at least n members cover | A sweep of edges, `sweep_depth/5` |
| `Tempo.IntervalSet.covered?/2` and the backends' `overlapping/2` | The members a span of seconds overlaps | UTC seconds, in the list, the lazy and the tree backend |
| `Tempo.Interval.relation/2` and its predicates | How two spans stand, and whether one is within the other | Allen's relations; `Tempo.Interval.within?/2` beside `Tempo.Operations.within?/3` |
| `Tempo.shift/3` with `:skipping`, and a `:within` window on a recurrence | Whether a span overlaps busy time, or a window | `busy_day?/2` on UTC seconds; `overlaps_window?/3` |

None is a second algebra. But "do these two spans overlap" has four answers in the library (the sweeps' comparison of ends, the backends' seconds, Allen's relation, the window's bound), and nothing holds the four to one another.

## What holds them to an answer

* **The matrix** — `Tempo.Matrix.Checks.binary/0` runs each hand-written value of the corpus with six plain Gregorian values and each generated one with one of them, in both orders, and each with itself: about 1,100 values. For `union/2`, `intersection/2`, `difference/2`, `symmetric_difference/2` and `complement/2` it compares the time the result covers with what `Tempo.Matrix.Extent` works out from the two operands' own spans; for `members_overlapping/2` and `members_outside/2` the time the kept members cover; for the five predicates their answer. That is an answer worked out apart from the library, and no cell of it fails.

* **The measure** — `test/tempo/set_operations_measure_test.exs` builds two sets from spans between the numbered points of a line, reads each answer back as positions on that line with `Tempo.Matrix.Extent`, and compares it with what `Tempo.Matrix.Sets` makes of the same spans by arithmetic on whole numbers. What is compared is the members an answer holds, each with the mark of the member it is or was cut from, and that they come in the order of their starts; not only the time they cover. It runs every pair of sets of up to two members between five points (4,356 pairs: every way two members of each side precede, meet, overlap, nest and repeat), a fifth of them again on a tree, and generated sets of up to six members of days, of hours, of the two mixed, of hours in two zones, and of days of the Hebrew, the Persian and the Gregorian calendars. It holds `union/2`, `difference/2`, `symmetric_difference/2`, `complement/2` with a set as its window, `members_overlapping/2`, `members_outside/2`, `members_in_exactly_one/2`, the five predicates, `coalesce/1`, the time `covered/2` gives, `covered?/2`, and an answer used as an operand again. Of `intersection/2` it holds the time covered and that each part is a member of the first cut to a member of the second, and the parts one for one where no two members of a side overlap each other. `Tempo.Matrix.Sets` is itself held to each operation's definition, cell by cell. Every sweep agrees with it.

* **Examples** — `test/tempo/operations_test.exs` (113 tests, one property), `test/tempo/interval_set_test.exs` (59), and 29 for the three backends.

## What it does not reach

The matrix measures the time covered, with one plain partner at a time. The measure reaches two sets of several members, the members an answer holds, a tree beside a list, and two calendars neither of which is the Gregorian. Neither reaches:

* **Two values with no year** — every line of the measure has a year. A span that crosses its cycle's end comes back in two (below), so a line with no year waits for that.

* **A `:within` window that places a time of day** — the matrix measures it for `complement/2` alone, in a window with no zone; the measure gives `complement/2` a set as its window and places nothing on it.

* **The forms that take a list of operands, the `:metadata` option, and a recurrence set as an operand** — held to no answer worked out apart from the library.

* **How many parts the intersection of overlapping members has** — held to the time covered and to each part being a pair's, until it is decided (below).

* **The lazy backend** — the measure builds lists and trees. What an operation gives of an unending lazy set is the deferred [plans/open-ended-set-algebra.md](plans/open-ended-set-algebra.md).

* **Three of the five other places** — `Tempo.Interval.relation/2`, `:skipping` and a recurrence's `:within` are in neither, and the backends' `overlapping/2` is reached only through `covered?/2`.

## Found

By reading the code and probing what the reading suggested, and `covered/2` by the measure. Each is reproduced.

* **A span that crosses its cycle's end comes back in two** — `~o"T22/T02"` is one member, cut at midnight to be swept and not joined again: `Tempo.union(~o"T22/T02", ~o"T03/T04")` has three members where two were given, and `Tempo.members_outside(~o"T22/T02", ~o"T03/T04")`, the same value kept whole, is `T0H/T2H` and `T22H/T0H`. So is `12M20D/1M10D`. The time covered is right, which is why the matrix passes; the members are not. `coalesce/1` joins them.

* **A time of day placed on a week gives nothing** — `Tempo.intersection(~o"T09/T17", ~o"2026-W25", within: ~o"2026-W25")` is empty, where the same week written as dates (`2026-06-15/2026-06-22`) gives its seven days' hours; and `Tempo.complement(~o"T09/T17", within: ~o"2026-W25")` is the whole week, the hours not taken from it. `days_in/1` takes the window's days from its month and day, and a week's ends hold neither.

* **`covered/2` cuts a region where members meet, and loses a span that crosses its cycle's end** — `Tempo.IntervalSet.covered/2` sweeps the members' ends itself (`sweep_depth/5`), apart from `coalesce/1`. Ends at one instant are taken closing first, so the count falls below the threshold and rises again there: two hours back to back give `T9H/T10H` and `T10H/T11H`, where its documentation says members that touch are merged as `coalesce/1` gives, and at `at_least: 2` a member over two that meet gives two regions likewise. And its ends are sorted as written, so a span with no year that crosses its cycle's end closes before it opens: `covered/2` of `~o"T22/T02"` alone is empty, and with `~o"T01/T03"` beside it is `T1H/T2H`, where `coalesce/1`, which cuts such a span at the cycle's end and writes the parts back as one, gives `T22H/T3H`. The first is a matter of members; the second is the wrong time.

* **A set operation across a week calendar's resolutions is refused** — `Tempo.difference/2` of an ISO week year and one of its weeks is a `ResolutionError`. Already an item of `TODO.md`.

## To decide

* **Whether `:within` bounds the result** — a time of day is placed on every day the window touches, so `Tempo.union(~o"T09/T17", window, within: window)` for a window from noon to noon includes 09:00 to 12:00 before it opens. For `intersection/3` and `complement/2` the window cuts that off; for `union/3` nothing does.

* **What the intersection of overlapping members is** — the sweep emits one fragment for each stretch of time it reaches, so two members of the first operand that both overlap one of the second give one fragment, with the first's metadata. The time is right. If a fragment is "a member of the first cut to a member of the second", as the function's documentation says, there should be two, and `metadata: {:merge, fun}` would then see both.

## Tasks

* [ ] **`covered/2` on the one cover** — a region runs for as long as the threshold holds, across members that meet, and a span with no year is cut at its cycle's end and written back as `coalesce/1` does; then the measure compares its regions and not only their cover.

* [ ] **A span that crosses its cycle's end is one member** — the parts are joined again where the operation keeps members.

* [ ] **A time of day on a week window** — the window's days are those of its span, whatever axis it is written on.

* [ ] **The measure widened** — two values with no year, once a span that crosses its cycle's end is one member; a `:within` window that places a time of day, for each operation; the forms that take a list of operands and the `:metadata` option; a lazy set within a window.

* [ ] **One answer to whether two spans overlap** — a property that the sweeps, the backends, Allen's relation and a window's bound agree on every generated pair; then whether any is to be read through another.

* [ ] **The two decisions** — whether `:within` bounds a union, and what the intersection of overlapping members is.

### Done

* [x] **The measure** — two sets of several members, each operation's members and their marks held to arithmetic on whole numbers, on a list and on a tree, in two zones and three calendars; an answer as an operand again in place of the laws, which follow where each answer is its definition's. 2026-10-04.
