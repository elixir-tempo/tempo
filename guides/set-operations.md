# Set operations

Tempo implements the core set operations — `union/2`, `intersection/2`, `complement/2`, `difference/2`, `symmetric_difference/2` — over `%Tempo.IntervalSet{}`. **The named operations all behave the way set algebra textbooks behave**: `intersection`, `difference`, `complement`, and `symmetric_difference` are **instant-level** — they return the trimmed covered-time result. `union` is the only member-preserving default, because two members covering the same time stay distinct events with their own metadata; the merged-span form is one explicit `IntervalSet.coalesce/1` away.

When you need to ask an **event-list question** — "*which* meetings hit this window?", "*which* workdays aren't holidays?" — reach for the `members_*` companion. Each of them is a member-preserving filter that keeps surviving members whole, with their identity and metadata intact:

* `members_overlapping/2` — companion to `intersection/2`
* `members_outside/2` — companion to `difference/2`
* `members_in_exactly_one/2` — companion to `symmetric_difference/2`

Companion predicates (`disjoint?/2`, `overlaps?/2`, `subset?/2`, `contains?/2`, `equal?/2`) operate at the instant-set level.

Every operation accepts any Tempo shape — an implicit `%Tempo{}`, an `%Tempo.Interval{}`, a `%Tempo.IntervalSet{}`, or an all-of `%Tempo.Set{}` — and returns a `%Tempo.IntervalSet{}` (or a boolean for predicates). The top-level API lives on the `Tempo` module: `Tempo.union/2`, `Tempo.intersection/2`, and so on.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

## 0. Instant-level vs member-preserving

This is the most important distinction in Tempo's set algebra, and the one that drives every design decision below.

A `%Tempo.IntervalSet{}` is two things at once:

1. **A list of distinct member intervals** — typically events, bookings, meetings, holidays, or any domain object with identity and metadata.

2. **A set of covered instants** on the time line — a sub-region of the timeline that may span multiple, contiguous, or overlapping members.

Different questions need different views, so Tempo gives you both. Each canonical operation has the shape that's right for the textbook reading; each comes with an explicit companion when the other shape is what you want.

### The two shapes side by side

| Question shape | Default — instant-level | Companion — member-preserving |
|---|---|---|
| "What time is in both?" / "What time is the overlap?" | `intersection/2` — trimmed `A ∩ B` | `members_overlapping/2` — whole A members that overlap B |
| "What time is in A but not B?" / "What's left after subtracting?" | `difference/2` — trimmed `A ∖ B` | `members_outside/2` — whole A members that don't overlap B |
| "What time is in exactly one of A or B?" | `symmetric_difference/2` — trimmed `A △ B` | `members_in_exactly_one/2` — whole members of either side that don't overlap the other |
| "What time is uncovered within a bound?" | `complement/2` (always instant-level) | — |
| "What members are in either set?" | — | `union/2` (always member-preserving — coalesce explicitly with `IntervalSet.coalesce/1` for the instant-level form) |

**Instant-level operations** treat operands as covered time and produce a trimmed result. The result interval(s) cover exactly the instants the question asks for. A single A member may split into multiple fragments; each fragment carries the source A member's metadata.

**Member-preserving operations** treat operands as event-lists and keep surviving members whole with their identity and metadata. Members are either *kept whole* or *dropped entirely* — they are never trimmed.

### Picking the right shape

Read your question aloud:

* If it talks about **time** ("the overlap between …", "the workday minus lunch", "free time", "covered period"), use the default — `intersection`, `difference`, `symmetric_difference`, `complement`. The result is the time region you asked about.

* If it talks about **events**, **members**, or **objects with identity** ("which bookings", "which workdays", "which holidays", "which events appear on exactly one calendar"), use the `members_*` companion. The result is the surviving event-list with original metadata intact.

Worked examples:

* *"What time of day are Alice and Bob both free for at least an hour?"* → instant-level. Use `difference` to get Alice's free fragments, `difference` for Bob's, `intersection` for the mutual fragments, then filter by duration.

* *"Which of my next 30 meetings fall inside Q2?"* → event-list. Use `members_overlapping(meetings, ~o"2026-Q2")` — each surviving meeting keeps its full title, location, and attendees.

* *"What workdays aren't holidays?"* → ambiguous in English, but the implementations agree because `workdays` is a multi-member set of single-day intervals — each holiday either fully covers a workday-member (drop) or doesn't overlap (keep). Use `difference` (canonical name) or `members_outside` (more explicit about intent); both produce the same result here.

* *"What's the workday minus lunch as a free-time block list?"* → instant-level. `difference(workday, lunch)` gives the two free blocks (09:00–12:00 and 13:00–17:00). `members_outside` would drop the workday entirely (it overlaps lunch).

The rule of thumb: **if you're going to say *"time"* or *"the period"* about the result, use the default; if you're going to say *"events"*, *"meetings"*, or *"members"*, use the `members_*` companion.

## 1. The four rules

Before any operation runs, both operands are **aligned** by a shared preflight. Three rules govern that alignment; a fourth governs what results carry.

### 1.1. Resolution — finer wins

Given operands at different resolutions, the coarser one is extended to the finer one before math runs. This is lossless: extending `2022Y` to day resolution yields `[2022-01-01, 2023-01-01)` — the same span, just more explicit.

```
iex> {:ok, set} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
iex> Tempo.IntervalSet.count(set)
1
```

The result's endpoints are at day precision — the finer of the two inputs (the trimmed overlap is the day itself). The alternative (truncate the finer operand to year) would silently destroy information.

### 1.2. Timezone — compare via UTC, inherit first operand's zone

Each operand keeps its wall-clock time and zone as authoritative. When set operations need to compare endpoints across zones, Tempo computes UTC projections on demand — per-operation, never cached. The result's `extended.zone_id` comes from the first operand, so the caller controls the display frame.

A Paris 12:00 CEST interval compares equal to a UTC 10:00 interval because they map to the same UTC instant. Zone-data updates don't invalidate stored values — nothing UTC-shaped is stored — so results stay stable when IANA pushes new zone rules.

### 1.3. Calendar — first operand's calendar wins

If the operands are in different calendars (Gregorian vs Hebrew, say), the second is converted to the first's calendar before math runs. Each endpoint of the second operand is extended to day precision, then year/month/day are converted via `Date.convert!/2`; hour/minute/second pass through unchanged (those units are calendar-independent). The result's calendar is the first operand's.

```elixir
hebrew_day = Tempo.new!(year: 5782, month: 10, day: 16, calendar: Calendrical.Hebrew)
# Hebrew 5782-10-16 corresponds to Gregorian 2022-06-15.

Tempo.overlaps?(hebrew_day, ~o"2022-06-15")
# => true

Tempo.disjoint?(hebrew_day, ~o"2023-01")
# => true
```

### 1.4. Iteration granularity — members keep it, new extents derive it

A materialised operand carries its iteration granularity on the interval's `:unit` field (a month materialises with `unit: :day`, so `Enum` walks its days — see the [enumeration guide](enumeration-semantics.html)). Set operations treat that as part of member identity: a member that passes through an operation **unchanged** keeps its unit, while an interval the sweep **constructs** — an intersection overlap, a difference remainder, a complement gap, a coalesced merge (which inherits the first merged member's unit) — is a new extent that walks at its own bounds resolution.

```elixir
# Members pass through union unchanged — each month still walks its days.
{:ok, months} = Tempo.union(~o"2022Y1M", ~o"2022Y3M")
Enum.count(months)
#=> 62    # 31 + 31 days

# Difference constructs new extents — the fragments walk at month resolution.
{:ok, gaps} = Tempo.difference(~o"2022", ~o"2022-06")
Enum.count(gaps)
#=> 11    # Jan–May and Jul–Dec, as months
```

The practical rule: **event-list questions** (the member-preserving operations) keep each member enumerating exactly as it did before the operation; **covered-time questions** (the instant-level operations) return extents, and an extent walks at the resolution its bounds state. `equal?/2` ignores `:unit` entirely — instant-set equality is about extents.

## 2. The anchor-class rule

A Tempo value is **anchored** when it has a year-level component — it's a position on the universal time line. A **non-anchored** value has no year: it recurs on a cycle rather than sitting at one instant. That's a pure time-of-day (`~o"T10:30"` — 10:30 every day), but also a month/day (`~o"1M31D"` — January 31st every year), a bare day (`~o"15D"` — the 15th of every month), a month (`~o"3M"` — every March), and so on. A `Tempo.Duration` is neither — it's a length, not a set of instants.

Set operations require **both operands to share an anchor class**:

| A | B | Valid without `:bound`? |
|---|---|---|
| anchored | anchored | ✓ compare on the universal time line |
| non-anchored | non-anchored | ✓ when both recur on the **same axis** (see below) |
| anchored | non-anchored | needs `:bound` |
| duration | anything | always raises — anchor it first |

Two non-anchored operands must recur on the **same axis** — share their coarsest (leading) unit — to be comparable. `~o"1M31D"` and `~o"6M15D"` are both annual, so they align; `~o"1M31D"` (annual) and `~o"15D"` (monthly) recur on different cycles with no common time line, so they return a `Tempo.NonAnchoredError` rather than a silently misaligned result. Anchor them, or give both the same leading unit.

The cross-axis case *is* mathematically defined — a bare time-of-day is an infinite set of 1-second slots (one per day), and an anchored operand bounds it to finite occurrences. But picking the universe (what year range does "every day" mean?) isn't something Tempo can do without inventing a default. The `:bound` option makes the choice explicit:

```elixir
# No bound — raises
Tempo.intersection(~o"2026-01-04", ~o"T10:30")
# ** (ArgumentError) Set operations between an anchored operand and a 
#    non_anchored operand require a `:bound` option to anchor the 
#    non-anchored side. Alternatively, use `Tempo.anchor/2` to combine 
#    a date-like value with a time-of-day value before the operation.

# With bound — works
Tempo.intersection(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-04")
# {:ok, #Tempo.IntervalSet<[~o"2026Y1M4DT10H30M/T31M"]>}
```

The `:bound` option is also required on `complement/2` — for the same reason. An unbounded complement is infinite; Tempo refuses to pick a universe.

### Composing across axes — `at/2` and `anchor/2`

When you want to *compose* a date with a time-of-day rather than intersect them, use `at/2` or its mirror `anchor/2`. This is axis composition, not a set operation, and no algebraic laws apply — these are constructors.

`at/2` *right-fills*: it sets the time-of-day on a value already on the timeline, replacing any finer components it carried (a value that was `09:30` becomes exactly `10:30`, not a merge of the two).

```elixir
iex> Tempo.at(~o"2026-01-04", ~o"T10:30")
{:ok, ~o"2026Y1M4DT10H30M"}
```

`anchor/2` *left-fills*: it places a floating time onto a reference date, supplying the missing year so the value can sit on the timeline.

```elixir
iex> Tempo.anchor(~o"T10:30", ~o"2026-01-04")
~o"2026Y1M4DT10H30M"
```

## 3. The operations

### Union — member-preserving

All members of both operands, kept as distinct intervals with their original metadata.

```elixir
iex> {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
iex> Tempo.IntervalSet.count(r)
2                                    # two distinct year members
```

For the canonical instant-set form (touching members merged into one span), coalesce explicitly:

```elixir
iex> {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
iex> r |> Tempo.IntervalSet.coalesce() |> Tempo.IntervalSet.count()
1                                    # [2022-01-01, 2024-01-01)
```

Identities hold at the instant-set level: `∅ ∪ A` has the same covered instants as `A`; `A ∪ B` and `B ∪ A` differ only in sort order, which is normalised.

### Intersection — instant-level (trimmed)

Every instant in both operands. Each result interval is the portion of an A member trimmed to its overlap with some B member, carrying A's metadata.

```elixir
iex> {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
iex> [iv] = Tempo.IntervalSet.to_list(r)
iex> Tempo.day(iv)
15                                   # trimmed to the day-shaped overlap
```

For the member-preserving filter — keep whole A members that overlap, don't trim:

```elixir
iex> {:ok, r} = Tempo.members_overlapping(~o"2022Y", ~o"2022-06-15")
iex> [iv] = Tempo.IntervalSet.to_list(r)
iex> Tempo.year(iv)
2022                                 # the year member is kept whole
```

The surviving A member inherits A's calendar and metadata; the B operand is used only to decide *whether* to keep the member.

### Complement — instant-level

Every instant in the universe that is NOT covered by any member of `set`. The `:bound` option is **required**. Internally coalesces before computing gaps.

```elixir
iex> {:ok, r} = Tempo.complement(~o"2022-06", bound: ~o"2022Y")
iex> Tempo.IntervalSet.count(r)
2                                    # January–May and July–December
```

An unbounded complement is infinite; Tempo refuses to pick a universe implicitly.

### Difference — instant-level (trimmed)

Every instant in `a` that is NOT in `b`. Each result interval is the portion of an A member trimmed to the gaps left by B; a single A member can split into multiple fragments. Each fragment carries A's metadata.

```elixir
iex> {:ok, r} = Tempo.difference(~o"2022Y", ~o"2022-06")
iex> Tempo.IntervalSet.count(r)
2                                    # Jan–Jun and Jul–Dec
```

For the member-preserving filter — keep whole A members that don't overlap, drop any that do:

```elixir
iex> {:ok, r} = Tempo.members_outside(~o"2022Y", ~o"2022-06")
iex> Tempo.IntervalSet.members(r)
[]                                   # the year overlaps June, so it's dropped entirely
```

The shapes diverge when an A member is *partially* overlapped by B: `difference` returns the surviving fragments, `members_outside` drops the whole member.

### Symmetric difference — instant-level (trimmed)

`A △ B` — every instant in exactly one of the operands. Derived as `(A ∖ B) ∪ (B ∖ A)` using the trimmed `difference`.

```elixir
iex> {:ok, a} = Tempo.from_iso8601("2022-01/2022-07")
iex> {:ok, b} = Tempo.from_iso8601("2022-04/2022-10")
iex> {:ok, r} = Tempo.symmetric_difference(a, b)
iex> Tempo.IntervalSet.count(r)
2                                    # Jan–Mar and Jul–Oct (the trimmed edges)
```

For the member-preserving filter — keep whole members of either side that don't overlap any member of the other:

```elixir
iex> {:ok, r} = Tempo.members_in_exactly_one(~o"2020Y", ~o"2022Y")
iex> Tempo.IntervalSet.count(r)
2                                    # disjoint operands → both members survive
```

If the single A and B members overlap each other (as in the first example), `members_in_exactly_one` returns the empty set — both members are dropped.

### Predicates — instant-level

All return booleans. Predicates answer "covered instants" questions — they ignore member identity and compare the coalesced forms.

```elixir
iex> Tempo.disjoint?(~o"2020Y", ~o"2022Y")
true

iex> Tempo.overlaps?(~o"2022Y", ~o"2022-06")
true

iex> Tempo.subset?(~o"2022-06", ~o"2022Y")
true                                 # June ⊆ 2022

iex> Tempo.contains?(~o"2022Y", ~o"2022-06")
true                                 # 2022 ⊇ June (alias: subset?(b, a))

iex> Tempo.equal?(~o"2022Y", Tempo.from_iso8601!("2022-01-01/2023-01-01"))
true                                 # same covered instants, different representations
```

### Counting a result

Once you hold a result set, three different "how much" questions each have their own tool — and they return very different numbers, so pick the one that matches intent:

* **How many windows** (member spans)? — `Tempo.IntervalSet.count/1`, the set's cardinality.

* **How many sub-points** (days, hours, … at the members' resolution)? — `Enum.count/1`. The `Enumerable` protocol walks *into* each member and yields its stepped points, so this totals across every window, not the number of windows.

* **How long** (elapsed time)? — `Tempo.duration/1` on the whole set (the members' total) or on a member, or `Tempo.at_least?/2` to keep only windows of a given length. Don't count sub-points for this — across a DST boundary the walk skips the spring-forward hour and emits the fall-back hour twice, so `Enum.count` deliberately diverges from elapsed time.

```elixir
iex> {:ok, free} = Tempo.union(~o"2026Y1M", ~o"2026Y3M")
{:ok, #Tempo.IntervalSet<[~o"2026Y1M1D/2M1D", ~o"2026Y3M1D/4M1D"]>}

iex> Tempo.IntervalSet.count(free)
2                                    # two windows: January and March

iex> Enum.count(free)
62                                   # 62 sub-points: 31 + 31 days

iex> free |> Tempo.IntervalSet.to_list() |> Enum.filter(&Tempo.at_least?(&1, ~o"P1M"))
[~o"2026Y1M1D/2M1D", ~o"2026Y3M1D/4M1D"]   # both windows ≥ 1 month
```

`to_list/1` exposes the windows for `Enum`; `Tempo.at_least?/2` (and its companions) then select by duration — the member-level idiom that keeps the sub-point walk and the window count from being confused.

## 4. Algebraic laws

Set-algebra identities hold at the **instant-set level** — i.e. after coalescing, or equivalently, when compared via `Tempo.equal?/2`. The instant-level operations (`intersection`, `difference`, `symmetric_difference`, `complement`) satisfy them directly. The member-preserving operation `union` and the member-preserving filters (`members_overlapping`, `members_outside`, `members_in_exactly_one`) preserve A-side member identity, so they don't satisfy classical laws like commutativity at the member-list level — but they do at the covered-instant level once you compare via `Tempo.equal?/2`:

- Commutativity: `intersection(A, B) ≡ intersection(B, A)` (same covered instants — symmetric by construction)
- Associativity: `(A ∪ B) ∪ C ≡ A ∪ (B ∪ C)` under coalescing
- Identity: `A ∪ ∅ ≡ A`, `intersection(A, U) ≡ A` (with `U` = bound)
- De Morgan's laws: `¬(A ∪ B) ≡ ¬A ∩ ¬B` and `¬(A ∩ B) ≡ ¬A ∪ ¬B` (within a common bound)

Tempo's test suite covers all of these.

Note that `≡` here is covered-instant equality (via `Tempo.equal?/2`), not member-list equality. The member-preserving filters are *not* commutative in the classical sense: `members_overlapping(a, b)` returns A-side members, `members_overlapping(b, a)` returns B-side — same covered instants, different members.

## 5. Edge cases

| Case | Behaviour |
|---|---|
| Empty IntervalSet on either side | Follows algebraic identities |
| Open-ended interval (`1985/..`) as operand | Raises — bound the interval first |
| Unbounded recurrence (`R/.../P1M`) | Raises — same reason |
| `Tempo.Duration` | Raises — durations aren't instant sets |
| One-of `Tempo.Set` (`[a,b,c]`) | Raises — epistemic disjunction, not IntervalSet |
| Cross-calendar operands | Second operand converted to first's calendar via `Date.convert!/2`; result inherits first's calendar |
| Cross-zone operands | Compared via UTC; result inherits first operand's zone |
| Midnight-crossing non-anchored interval (`T23:30/T01:00`) | Anchored to day D materialises as `[D T23:30, D+1 T01:00)`; on the time-of-day axis, split into `[T23:30, T24:00)` ∪ `[T00:00, T01:00)` before sweep-line |

## 6. Not in scope

- **Rule-algebra** — intersecting two infinite recurrences to produce a closed-form rule. Intentionally deferred; see `plans/set-operations.md` for the rationale.
- **UTC caching on IntervalSet** — projections are recomputed per operation. Enables stability across zone-data updates; revisit if profiling shows the recomputation matters.

## 7. Implementation notes

- **Union** (member-preserving): concat + `IntervalSet.new/1` (which sorts but does *not* coalesce by default). O(n log n) on the combined input.
- **Intersection** (instant-level): sweep-line, O(n+m). Each step emits the trimmed overlap and advances whichever interval ends first.
- **Difference** (instant-level): sweep-line over A with a running cursor into B, emitting A's uncovered portions.
- **Symmetric difference** (instant-level): derived as `(A ∖ B) ∪ (B ∖ A)`.
- **Complement**: internally coalesces the input and then calls `difference(bound, coalesced)`.
- **`members_overlapping`** (member-preserving): per-A-member overlap check against B. O(n × m) in the worst case; sweep-line optimisation planned for large sets.
- **`members_outside`** (member-preserving): per-A-member anti-overlap check against B. Same complexity as `members_overlapping`.
- **`members_in_exactly_one`**: derived as `members_outside(A, B) ∪ members_outside(B, A)`.

Implementation in `lib/operations.ex`. Shared comparison primitives in `lib/compare.ex`. Tests in `test/tempo/operations_test.exs`.
