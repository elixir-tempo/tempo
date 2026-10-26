# Set operations

Tempo implements the core set operations — `union/3`, `intersection/3`, `complement/2`, `difference/3`, `symmetric_difference/3` — over any expression that has spans. **The named operations all behave the way set algebra textbooks behave**: `intersection`, `difference`, `complement`, and `symmetric_difference` are **instant-level** — they return the trimmed covered-time result. `union` is the only member-preserving default, because two members covering the same time stay distinct events with their own metadata; the merged-span form is one explicit `Tempo.IntervalSet.coalesce/2` away.

When you need to ask an **event-list question** — "*which* meetings hit this window?", "*which* workdays aren't holidays?" — reach for the `members_*` companion. Each of them is a member-preserving filter that keeps surviving members whole, with their identity and metadata intact:

* `members_overlapping/3` — companion to `intersection/3`

* `members_outside/3` — companion to `difference/3`

* `members_in_exactly_one/3` — companion to `symmetric_difference/3`

Companion predicates (`disjoint?/2`, `overlaps?/2`, `within?/2`, `contains?/2`, `equal?/2`) operate at the instant-set level.

Every operation accepts any expression with spans — a value, an interval, a set, a bounded recurrence — and returns `{:ok, set}`, the set a `%Tempo{}` holding the result's spans (or a boolean for predicates). The top-level API lives on the `Tempo` module: `Tempo.union/3`, `Tempo.intersection/3`, and so on.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` to the caller's namespace; no helper functions leak in.

## 0. Instant-level vs member-preserving

This is the most important distinction in Tempo's set algebra, and the one that drives every design decision below.

A set of intervals is two things at once:

1. **A list of distinct member intervals** — typically events, bookings, meetings, holidays, or any domain object with identity and metadata.

2. **A set of covered instants** on the time line — a sub-region of the timeline that may span multiple, contiguous, or overlapping members.

Different questions need different views, so Tempo gives you both. Each canonical operation has the shape that's right for the textbook reading; each comes with an explicit companion when the other shape is what you want.

### The two shapes side by side

| Question shape | Default — instant-level | Companion — member-preserving |
|---|---|---|
| "What time is in both?" / "What time is the overlap?" | `intersection/3` — trimmed `A ∩ B` | `members_overlapping/3` — whole A members that overlap B |
| "What time is in A but not B?" / "What's left after subtracting?" | `difference/3` — trimmed `A ∖ B` | `members_outside/3` — whole A members that don't overlap B |
| "What time is in exactly one of A or B?" | `symmetric_difference/3` — trimmed `A △ B` | `members_in_exactly_one/3` — whole members of either side that don't overlap the other |
| "What time is uncovered within a window?" | `complement/2` (always instant-level) | — |
| "What members are in either set?" | — | `union/3` (always member-preserving — coalesce explicitly with `IntervalSet.coalesce/2` for the instant-level form) |

**Instant-level operations** treat operands as covered time and produce a trimmed result. The result interval(s) cover exactly the instants the question asks for. A single A member may split into multiple fragments; each fragment carries the source A member's metadata.

**Member-preserving operations** treat operands as event-lists and keep surviving members whole with their identity and metadata. Members are either *kept whole* or *dropped entirely* — they are never trimmed.

### Picking the right shape

Read your question aloud:

* If it talks about **time** ("the overlap between …", "the workday minus lunch", "free time", "covered period"), use the default — `intersection`, `difference`, `symmetric_difference`, `complement`. The result is the time region you asked about.

* If it talks about **events**, **members**, or **objects with identity** ("which bookings", "which workdays", "which holidays", "which events appear on exactly one calendar"), use the `members_*` companion. The result is the surviving event-list with original metadata intact.

Worked examples:

* *"What time of day are Alice and Bob both free for at least an hour?"* → instant-level. Use `difference` to get Alice's free fragments, `difference` for Bob's, `intersection` for the mutual fragments, then filter by duration.

* *"Which of my next 30 meetings fall inside the second quarter?"* → event-list. Use `members_overlapping(meetings, ~o"2026-04/2026-06")` — each surviving meeting keeps its full title, location, and attendees.

* *"What workdays aren't holidays?"* → ambiguous in English, but the implementations agree because `workdays` is a multi-member set of single-day intervals — each holiday either fully covers a workday-member (drop) or doesn't overlap (keep). Use `difference` (canonical name) or `members_outside` (more explicit about intent); both produce the same result here.

* *"What's the workday minus lunch as a free-time block list?"* → instant-level. `difference(workday, lunch)` gives the two free blocks (09:00–12:00 and 13:00–17:00). `members_outside` would drop the workday entirely (it overlaps lunch).

The rule of thumb: **if you're going to say *"time"* or *"the period"* about the result, use the default; if you're going to say *"events"*, *"meetings"*, or *"members"*, use the `members_*` companion.

## 1. The four rules

Before any operation runs, both operands are read as spans on one **frame**. Three rules govern that; a fourth governs what walking a result gives.

### 1.1. Resolution — finer wins

Operands of different resolutions are compared as the spans they are: `2022Y` is the span from the start of 1 January 2022 to the start of 1 January 2023, whatever unit it is written in, so nothing is extended or truncated.

```elixir
iex> {:ok, set} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
iex> Tempo.IntervalSet.count(set)
1
```

The result's ends are written to the day: each end of a result is written at the resolution of the operand end that stands there.

### 1.2. Timezone — compare on the one time line, inherit the first operand's zone

Each operand keeps its wall-clock time and zone as authoritative. When set operations compare ends across zones, Tempo finds each one's place on the universal time line as it is needed — per operation, never stored. The result is written in the first operand's zone, so the caller controls the display frame.

A Paris 12:00 CEST interval compares equal to a UTC 10:00 interval because they map to the same UTC instant. Zone-data updates don't invalidate stored values — nothing UTC-shaped is stored — so results stay stable when IANA pushes new zone rules.

A value with no zone has no place on the universal time line, so it is not combined with one that has: the set operations return a `Tempo.FrameError` for the pair, and the predicates raise it. Place the floating value first with `Tempo.in_zone/2`.

```elixir
iex> {:error, %Tempo.FrameError{reason: :floating_and_zoned}} = Tempo.union(~o"2026-06-15T10", ~o"2026-06-15T10Z")
iex> {:ok, in_utc} = Tempo.in_zone(~o"2026-06-15T10", "Etc/UTC")
iex> Tempo.equal?(in_utc, ~o"2026-06-15T10Z")
true
```

### 1.3. Calendar — first operand's calendar wins

If the operands are in different calendars (Gregorian and Hebrew, say), both are placed on the one time line, where a day is a day in any calendar, and the result is written in the first operand's calendar. A result end that comes from the second operand is written to the day, a month of one calendar being no month of another.

```elixir
# Hebrew 5782-10-16 is Gregorian 2022-06-15.
iex> hebrew_day = Tempo.new!(year: 5782, month: 10, day: 16, calendar: Calendrical.Hebrew)
iex> Tempo.overlaps?(hebrew_day, ~o"2022-06-15")
true

iex> Tempo.disjoint?(hebrew_day, ~o"2023-01")
true
```

### 1.4. Walking a result gives its members

A result is a set, and walking a set gives its members: the intervals it holds, one by one. That is one rule for every operation, so `Enum.count/1` of a result is how many spans it has.

```elixir
# Union keeps each member: two months.
iex> {:ok, months} = Tempo.union(~o"2022Y1M", ~o"2022Y3M")
iex> Enum.count(months)
2

# Difference answers the time left: January to May, and July to December.
iex> {:ok, gaps} = Tempo.difference(~o"2022", ~o"2022-06")
iex> Enum.count(gaps)
2
```

To walk the days or the hours inside a result, say the unit: `Tempo.walk/2` walks every span of an expression at the unit asked.

```elixir
iex> {:ok, months} = Tempo.union(~o"2022Y1M", ~o"2022Y3M")
iex> {:ok, days} = Tempo.walk(months, :day)
iex> Enum.count(days)
62
```

## 2. The anchor-class rule

A Tempo value is **anchored** when it has a year-level component — it's a position on the universal time line. An **unanchored** value has no year: it recurs on a cycle rather than sitting at one instant. That's a pure time-of-day (`~o"T10:30"` — 10:30 every day), but also a month/day (`~o"1M31D"` — January 31st every year), a bare day (`~o"15D"` — the 15th of every month), a month (`~o"3M"` — every March), and so on. A `Tempo.Duration` is neither — it's a length, not a set of instants.

Set operations require **both operands to share an anchor class**:

| A | B | Valid without `:within`? |
|---|---|---|
| anchored | anchored | ✓ compare on the universal time line |
| unanchored | unanchored | ✓ when both recur on the **same axis** (see below) |
| anchored | unanchored | needs `:within` |
| duration | anything | an error — a duration has no place on the time line |

Two unanchored operands must recur on the **same axis** — share their coarsest (leading) unit — to be comparable. `~o"1M31D"` and `~o"6M15D"` are both annual, so they align; `~o"1M31D"` (annual) and `~o"15D"` (monthly) recur on different cycles with no common time line, so they return a `Tempo.FrameError` rather than a silently misaligned result. Place them on a date, or give both the same leading unit.

The cross-axis case *is* mathematically defined — a bare time-of-day is an infinite set of 1-second slots (one per day), and an anchored operand bounds it to finite occurrences. But picking the universe (what year range does "every day" mean?) isn't something Tempo can do without inventing a default. The `:within` option makes the choice explicit:

```elixir
# No window: an error that says what to give
iex> {:error, %Tempo.FrameError{reason: :needs_a_year}} = Tempo.intersection(~o"2026-01-04", ~o"T10:30")

# With a window, half past ten is placed on the day
iex> Tempo.intersection(~o"2026-01-04", ~o"T10:30", within: ~o"2026-01-04")
{:ok, ~o"{2026Y1M4DT10H30M/T10H31M}"}
```

A window places a time of day on each day it touches, and what is placed is inside the window: on a window from noon on Monday to noon on Wednesday, nine to five is noon to five on Monday, nine to five on Tuesday and nine to noon on Wednesday, for every operation alike. The other operand is not cut by the window. A dated window places every operand that has no year, whatever the other operand is, so the working hours of a week with no meetings in it are still that week's hours, and each placed span keeps the metadata of the time of day it is.

The `:within` option is also required on `complement/2` — for the same reason. An unbounded complement is infinite; Tempo refuses to pick a universe.

A window may be several spans, an interval set of two separate days say. A time of day is placed inside each span. A recurrence, or a set of recurrences, is kept across the one stretch from the first span's start to the last one's end, so a daily rule within 2 June and 5 June has 3 and 4 June too. The other operand serves as the window the same way when no `:within` is given: `Tempo.difference(holidays, meetings)` is every holiday from the first meeting to the last, less the meetings.

### Composing across axes — `at/2` and `on/2`

When you want to *compose* a date with a time-of-day rather than intersect them, place one on the other with `at/2` or `on/2`. This is axis composition, not a set operation, and no algebraic laws apply — these are constructors.

The value with a year keeps it, and the other supplies the finer components it lacks, taken whole (a value that was `09:30` becomes exactly `10:30`, not a merge of the two). `at/2` and `on/2` are one function, so the code reads the way English does — *"4 January **at** 10:30"*, *"10:30 **on** 4 January"* — and either order gives the same value.

```elixir
iex> Tempo.at(~o"2026-01-04", ~o"T10:30")
{:ok, ~o"2026Y1M4DT10H30M"}

iex> Tempo.on(~o"T10:30", ~o"2026-01-04")
{:ok, ~o"2026Y1M4DT10H30M"}
```

## 3. The operations

### Union — member-preserving

All members of both operands, kept as distinct intervals with their original metadata. A member both operands hold, the same in its span, its written form and its metadata, is one member of the union, so `union(a, a)` is `a`; members that cover the same time but differ in form or metadata (June, and 1 to 30 June; two bookings of one hour) stay two.

```elixir
iex> {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
iex> Tempo.IntervalSet.count(r)
2                                    # two distinct year members
```

For the canonical instant-set form (touching members merged into one span), coalesce explicitly:

```elixir
iex> {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
iex> {:ok, merged} = Tempo.IntervalSet.coalesce(r)
iex> Tempo.IntervalSet.count(merged)
1                                    # 2022 through 2023
```

Identities hold at the instant-set level: `∅ ∪ A` has the same covered instants as `A`; `A ∪ B` and `B ∪ A` differ only in sort order, which is normalised.

### Intersection — instant-level (trimmed)

Every instant in both operands. Each result interval is the portion of an A member trimmed to its overlap with some B member, carrying A's metadata.

```elixir
iex> {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
iex> [iv] = Tempo.IntervalSet.members(r)
iex> Tempo.day(iv)
15                                   # trimmed to the day-shaped overlap
```

For the member-preserving filter — keep whole A members that overlap, don't trim:

```elixir
iex> {:ok, r} = Tempo.members_overlapping(~o"2022Y", ~o"2022-06-15")
iex> [iv] = Tempo.IntervalSet.members(r)
iex> Tempo.year(iv)
2022                                 # the year member is kept whole
```

The surviving A member inherits A's calendar and metadata; the B operand is used only to decide *whether* to keep the member.

A result ends where the member it comes from ends, so it carries that one member's metadata. Two holidays that meet are two results, each with its own name; `Tempo.IntervalSet.coalesce/1` joins them where the time covered is the question:

```elixir
iex> christmas = Tempo.put_metadata(~o"2027-12-27", %{name: "Christmas Day"})
iex> boxing_day = Tempo.put_metadata(~o"2027-12-28", %{name: "Boxing Day"})
iex> {:ok, holidays} = Tempo.IntervalSet.new([christmas, boxing_day])
iex> {:ok, shared} = Tempo.intersection(holidays, ~o"2027-12")
iex> Tempo.IntervalSet.map(shared, &Tempo.metadata(&1).name)
["Christmas Day", "Boxing Day"]
iex> {:ok, covered} = Tempo.IntervalSet.coalesce(shared)
iex> Tempo.IntervalSet.count(covered)
1
```

> *"Christmas and Boxing Day **shared** with December are two holidays, each with its name; the time they **cover** is one stretch of two days."*

### Complement — instant-level

Every instant in the universe that is NOT covered by any member of `set`. The `:within` option is **required**. Internally coalesces before computing gaps.

```elixir
iex> {:ok, r} = Tempo.complement(~o"2022-06", within: ~o"2022Y")
iex> Tempo.IntervalSet.count(r)
2                                    # January–May and July–December
```

An unbounded complement is infinite; Tempo refuses to pick a universe implicitly.

### Difference — instant-level (trimmed)

Every instant in `a` that is NOT in `b`. Each result interval is the portion of an A member trimmed to the gaps left by B; a single A member can split into multiple fragments. Each fragment carries A's metadata.

```elixir
iex> {:ok, r} = Tempo.difference(~o"2022Y", ~o"2022-06")
iex> Tempo.IntervalSet.count(r)
2                                    # January to May, and July to December
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

iex> Tempo.within?(~o"2022-06", ~o"2022Y")
true                                 # June ⊆ 2022

iex> Tempo.contains?(~o"2022Y", ~o"2022-06")
true                                 # 2022 ⊇ June (the mirror: within?(b, a))

iex> Tempo.equal?(~o"2022Y", ~o"2022-01-01/2022-12-31")
true                                 # the same covered time, written two ways
```

### Counting a result

Once you hold a result set, three different "how much" questions each have their own tool, and they answer very different numbers, so pick the one that matches intent:

* **How many windows** (member spans)? — `Tempo.IntervalSet.count/1`, or `Enum.count/1`: walking a set gives its members.

* **How many days, or hours**? — `Tempo.walk/2` at that unit, then `Enum.count/1`.

* **How long** (elapsed time)? — `Tempo.duration/1` on the whole set (the time it covers) or on a member, or `Tempo.at_least?/2` to keep only windows of a given length. Don't count walked values for this — across a change of the clocks a day's walk has 23 or 25 hours, as the clock shows them.

```elixir
iex> {:ok, free} = Tempo.union(~o"2026Y1M", ~o"2026Y3M")
iex> free
~o"{2026Y1M/2026Y1M,2026Y3M/2026Y3M}"

iex> Tempo.IntervalSet.count(free)
2                                    # two windows: January and March

iex> Tempo.duration(free)
~o"P2M"

iex> free
...> |> Tempo.IntervalSet.members()
...> |> Enum.filter(&Tempo.at_least?(&1, ~o"P1M"))
[~o"2026Y1M/2026Y1M", ~o"2026Y3M/2026Y3M"]
```

`Tempo.IntervalSet.members/1` gives the windows as a list for `Enum`; `Tempo.at_least?/2` (and its companions) then select by length.

## 4. Algebraic laws

Set-algebra identities hold at the **instant-set level** — i.e. after coalescing, or equivalently, when compared via `Tempo.equal?/2`. The instant-level operations (`intersection`, `difference`, `symmetric_difference`, `complement`) satisfy them directly. The member-preserving operation `union` and the member-preserving filters (`members_overlapping`, `members_outside`, `members_in_exactly_one`) preserve A-side member identity, so they don't satisfy classical laws like commutativity at the member-list level — but they do at the covered-instant level once you compare via `Tempo.equal?/2`:

* Commutativity: `intersection(A, B) ≡ intersection(B, A)` (same covered instants — symmetric by construction)

* Associativity: `(A ∪ B) ∪ C ≡ A ∪ (B ∪ C)` under coalescing

* Identity: `A ∪ ∅ ≡ A`, `intersection(A, U) ≡ A` (with `U` = the window)

* De Morgan's laws: `¬(A ∪ B) ≡ ¬A ∩ ¬B` and `¬(A ∩ B) ≡ ¬A ∪ ¬B` (within a common window)

Tempo's test suite covers all of these.

Note that `≡` here is covered-instant equality (via `Tempo.equal?/2`), not member-list equality. The member-preserving filters are *not* commutative in the classical sense: `members_overlapping(a, b)` returns A-side members, `members_overlapping(b, a)` returns B-side — same covered instants, different members.

## 5. Edge cases

| Case | Behaviour |
|---|---|
| An empty set on either side | Follows algebraic identities |
| Open-ended interval (`1985/..`) as operand | An error: bound the interval first |
| An operand with no end (`R/…/P1M`, a set with no last member) | Bounded by the `:within` window. With none, an intersection and a difference from a bounded operand lie within the other operand; a union, a symmetric difference and a difference from the operand with no end are sets with no last member; two operands with no end have a union and need a window for anything else |
| `Tempo.Duration` | An error: a duration is no set of instants |
| A one-of set (`[a,b,c]`) | An error: one of several values is no set of them; ask `Tempo.certainty/3` |
| Cross-calendar operands | Second operand converted to the first's calendar; the result is in the first's |
| Cross-zone operands | Compared via UTC; the result is in the first operand's zone |
| A value with no zone and one with a zone | A `Tempo.FrameError`, reason `:floating_and_zoned` |
| A value with a year and one with none | A `Tempo.FrameError`, reason `:needs_a_year` |
| A span with no year that runs through its cycle's end (`T23:30/T01:00`) | One member: swept as the two spans it is in one turn of the cycle, and written back as one |
| A span with no year that ends where it starts (`T00/T00`) | Once round its cycle: the whole day |

Each error is returned by the operations that return a set, and raised by the predicates, which have only `true` and `false` to give.

## 6. Not in scope

* **Rule-algebra** — intersecting two infinite recurrences to produce a closed-form rule. Intentionally deferred.

## 7. Implementation notes

Every instant-level operation is one sweep (`lib/tempo/core/algebra.ex`): each operand is read as its spans, each span placed on the frame as two positions, and the edges of both operands are walked in order with a count of how many spans of each cover the point after them. Intersection keeps where both counts are positive, difference where only the first is, symmetric difference where exactly one is, and a complement is the window less the operand. The sweep is O((n + m) log(n + m)) in the spans of the two operands. The member-preserving operations use the same positioned spans and keep or drop each member whole. The predicates are questions of the same sweep, and the algebraic laws above are checked against an integer model in `test/tempo/set_operations_test.exs`.
