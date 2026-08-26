# Scheduling

Scheduling is really three questions, and Tempo answers each with a different part of the library:

1. **"When does this recur?"** — generate the occurrences of a repeating rule, bounded and zone-correct (sections 1–4).

2. **"When are we free to meet?"** — turn busy calendars into open, bookable time with set operations (section 5).

3. **"When can these dependent tasks run?"** — order constrained work to a deadline and find the critical path (section 6).

The first question has the sharpest edges — future dates, wall-clock vs UTC, and time zones that change rules out from under you — so it gets the most space. Sections 1–4 each give the principle, the Tempo idiom, and the pitfall to avoid:

* **You can't materialise an infinite stream.** Bounded scheduling is a design decision.

* **Wall-clock time is authoritative; UTC is a projection.** Tempo stores the user's wall time and derives the UTC instant on demand.

* **"Floating" events vs zoned events** — Tempo distinguishes them through what's on the value, not a flag.

* **Future dates survive zone-rule changes** — because Tempo never caches a UTC value, re-reading a future event automatically uses the current zone data.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

## 1. Bounded enumeration

An RRULE like `FREQ=MONTHLY;BYDAY=2MO` ("the second Monday of every month") is **infinite** — occurrences continue forever. You cannot call `Enum.to_list/1` on an infinite sequence.

Tempo splits the two operations: parsing the rule into a recurring interval is cheap and always bounded-free, but **materialising** it into a concrete `%Tempo.IntervalSet{}` requires a bound.

```elixir
recurrence = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2025-01-01")

# `recurrence` is a %Tempo.Interval{recurrence: :infinity, ...} — not an error.
# Materialising it requires a bound:

{:ok, set} = Tempo.to_interval(recurrence, bound: ~o"2025-07-01")
Tempo.IntervalSet.count(set)
#=> 7
```

> The **recurring interval** is the recurrence *rule*; the **IntervalSet** is its *occurrences* inside a window. `:bound` is always supplied at materialisation, never at the rule. Tempo's default member-preserving semantics keep each occurrence as a distinct member of the IntervalSet — which is what you want for scheduling. For the covered-instant form (individual occurrences merged into contiguous spans), pipe through `Tempo.IntervalSet.coalesce/1` — useful for free/busy questions but not for "list the events."

For ad-hoc use, `Stream.take/2` and `Enum.take/2` work directly on the recurring interval — it's enumerable, lazily:

```elixir
recurrence |> Stream.take(10) |> Enum.to_list()
```

### Pitfall

Forgetting the bound and calling `Tempo.to_interval(recurrence)`:

```elixir
{:error,
 "Cannot materialise an unbounded recurrence (recurrence: :infinity, no UNTIL). Supply a :bound option — any Tempo value whose upper endpoint limits the expansion."}
```

Tempo refuses rather than hanging — forgotten bounds are a design error, not a runtime surprise.

## 2. Wall-clock time is authoritative

When a user schedules "08:00 on 1 March 2030 in Paris", the *real* scheduling intent is the wall-clock reading on that morning — not a specific UTC instant. If Paris changes its DST rules between now and 2030, the UTC instant should shift; the wall-clock event should not.

Tempo stores exactly what the user wrote:

```elixir
t = ~o"2030-03-01T08:00:00[Europe/Paris]"
t.time
#=> [year: 2030, month: 3, day: 1, hour: 8, minute: 0, second: 0]

t.extended.zone_id
#=> "Europe/Paris"
```

No UTC seconds are cached on the struct. When you ask for the UTC projection, Tempo consults the configured time zone database at the time of the call, and the result reflects whatever zone rules it currently knows about 2030. Re-run the same call after a data update and the number may change — that's the correct behaviour for future dates.

### Principle

**Store what the user said. Compute UTC when you need it.** This is the same discipline Apple Calendar and Google Calendar enforce: the canonical form of a future event is wall-clock + zone, not UTC.

### Pitfall

Serialising a Tempo value as "the UTC seconds" and rehydrating from that:

```elixir
# Do NOT do this for future events:
cached_utc = Tempo.Compare.to_utc_seconds(event)
store_in_database(cached_utc)
```

When the IANA database ships a DST rule change for 2030, your cached number is now wrong — but you've lost the wall-clock information needed to recompute. Serialise the Tempo value itself (`Tempo.to_iso8601/1` round-trips faithfully) and project to UTC only at display or comparison time.

## 3. Floating vs grounded values

Every Tempo value is one of two kinds, and the distinction governs whether it can be placed on the universal (UTC) time line at all:

* A **grounded** value carries a zone or an offset — `[Europe/Paris]`, `Z`, or `+05:30` — so it names a position every observer agrees on. `Tempo.grounded?/1` returns `true`.

* A **floating** value carries neither. `~o"2030-03-01T08:00:00"` is a wall-clock reading with no observer attached — "8am wherever the reader happens to be". It has no single universal instant. `Tempo.floating?/1` returns `true`.

Apple Calendar's **"floating"** events (they call them "All-day" in the UI, but the concept applies to timed events too in iCal RFC 5545) are exactly this kind: a "6am workout" on holiday is still 6am local, whatever zone you fly to.

Tempo makes the distinction through **what is on the value**, not a flag — and exposes it through two predicates rather than field-poking:

```elixir
Tempo.floating?(~o"2030-03-01T08:00:00")                 #=> true
Tempo.grounded?(~o"2030-03-01T08:00:00[Europe/Paris]")   #=> true
Tempo.grounded?(~o"2030-03-01T08:00:00Z")                #=> true
Tempo.grounded?(~o"2030-03-01T08:00:00+05:30")           #=> true
```

Grounded values come in three flavours; the table lays out all four forms:

| Form | Kind | Meaning |
|---|---|---|
| `~o"2030-03-01T08:00:00"` | **Floating** | 8am in whatever zone the reader is in — no universal instant |
| `~o"2030-03-01T08:00:00[Europe/Paris]"` | Grounded — zoned | 8am Paris wall time, UTC derived on demand |
| `~o"2030-03-01T08:00:00Z"` | Grounded — UTC-anchored | a specific UTC instant, wall times vary by zone |
| `~o"2030-03-01T08:00:00+05:30"` | Grounded — fixed-offset | UTC+05:30 regardless of zone-rule changes |

The right choice depends on what the user said:

* "Morning workout at 6am" when travelling — floating.

* "Meeting at 2pm Paris" — grounded, zoned (`[Europe/Paris]`).

* "Server job at 03:00 UTC" — grounded, UTC-anchored (`Z`).

* "Event at UTC+05:30" (fixed-offset calendar system) — grounded, fixed-offset.

### Grounding a floating value

When a floating value needs to go on the time line — to compare it, project it to UTC, or shift it to another zone — place it into a zone with `Tempo.in_zone/2`. This interprets its wall-clock reading as the local time in that zone; the numbers on the clock do not move, only the frame is attached:

```elixir
floating = ~o"2030-03-01T08:00:00"
{:ok, paris} = Tempo.in_zone(floating, "Europe/Paris")   # read 8am as Paris local
Tempo.grounded?(paris)                                   #=> true
```

`in_zone/2` *places* a floating value into a zone. Its counterpart `shift_zone/2` *moves* an already-grounded value to a different zone, recomputing the wall clock to preserve the instant. The two are mirror images: `in_zone/2` rejects an already-grounded value (use `shift_zone/2` to move it), and `shift_zone/2` rejects a floating one (use `in_zone/2` to place it).

### Comparing floating and grounded values

A floating value has no position on the universal time line, so **it cannot be compared with a grounded one** — there is no fact of the matter about whether "8am somewhere" falls before or after "8am in Paris" until you say *which* somewhere. Rather than silently grounding the floating side to UTC and inventing an answer, Tempo refuses the comparison:

```elixir
Tempo.relation(~o"2030-03-01T08:00:00", ~o"2030-03-01T08:00:00[Europe/Paris]")
#=> ** (Tempo.FloatingTempoError) Cannot compare on a floating Tempo (no zone or offset information) ...
```

The same rejection applies to every comparison verb built on the relation — `before?/2`, `after?/2`, `overlaps?/2`, `within?/2`, the set predicates (`disjoint?/2`, `contains?/2`, …), and the certainty API (`overlap_certainty/2`, `certainly_before?/2`, …). Only the *mixed* case is refused: two floating values compare structurally on their shared wall-clock frame, and two grounded values compare by their instants (projected to UTC). Ground the floating side first and the comparison is well-defined:

```elixir
{:ok, grounded} = Tempo.in_zone(~o"2030-03-01T08:00:00", "Europe/Paris")
Tempo.relation(grounded, ~o"2030-03-01T08:00:00[Europe/Paris]")   #=> :equals
```

This is the comparison corollary of "same wall clock is not the same instant" (see the [Falsehoods](./falsehoods.md) guide): if two grounded readings in different zones are already different instants, then a *floating* reading — which fixes no zone at all — has no instant to compare, and the right response is to decline rather than guess.

### A zone on an interval

When you write an interval as an ISO 8601 string, the zone goes once at the end, where IXDTF binds it to the upper endpoint — and it grounds the whole span. Tempo propagates that trailing zone backward onto a floating lower endpoint, so a single-zone interval never straddles the floating and universal time lines:

```elixir
{:ok, iv} = Tempo.from_iso8601("2030-03-01T08:00/2030-03-05T08:00[Europe/Paris]")
{from, to} = Tempo.Interval.endpoints(iv)
{Tempo.grounded?(from), Tempo.grounded?(to)}   #=> {true, true}
```

Propagation is one-directional and non-destructive: it flows only from the upper endpoint (`to`) back to a floating lower one (`from`), never forward, and never over a zone an endpoint already carries — so `2030-03-01T08:00[Europe/Paris]/2030-03-05T08:00[Europe/London]` keeps both zones as written. It applies only to parsed interval *strings*; `Tempo.Interval.new/2` builds exactly the endpoints you hand it, mixed frames included.

### Principle

**The interpretation of a wall-clock reading is metadata, not an afterthought.** Tempo forces you to make that choice at parse time, preserves it through every operation, and refuses operations that would need a choice you have not yet made.

## 4. Future dates survive zone-rule changes

When Paris last moved its DST rules in 1996, any calendar entry stored as a frozen UTC instant for a post-1996 date had to be rewritten. Modern calendars (Google, Apple, Outlook) avoid this by storing wall-clock + zone and deriving UTC on demand — which is exactly what Tempo does.

Concretely: a Paris event stored today for 2030 will be re-evaluated with whatever the zone database knows about Paris's rules in 2030 *at the time of the computation*:

```elixir
event = ~o"2030-03-01T08:00:00[Europe/Paris]"

# Today, the IANA data says this is UTC+1 (standard time in March).
Tempo.Compare.to_utc_seconds(event)
#=> 64052726400

# If IANA 2028a ships saying France abolished DST in 2027,
# the next call to to_utc_seconds returns a different number
# — the event is "still 8am Paris wall time, but the UTC shifts."
```

`Tempo.Interval.duration/2` likewise re-evaluates each endpoint's UTC projection on every call. Comparisons and set operations do the same. Nothing is frozen.

### When to freeze

There are cases where you **want** the UTC instant frozen — a CI build that must run "at exactly 03:00 UTC on 15 March 2030" regardless of how zones shift. Store those as UTC (`~o"2030-03-15T03:00:00Z"`). The `Z` suffix is the explicit promise: "this is a UTC instant, don't recompute."

### Principle

**Don't cache UTC. Don't cache DST. Tempo doesn't, and the reason you trust this library over rolling your own is exactly this discipline.**

## 5. Free-busy and availability

The recurrence sections generate *when things happen*. The opposite question — *when is nobody busy* — is set algebra over those occurrences. **Free time is the workday minus the busy periods; mutual free time is the intersection of each person's free time.**

```elixir
work = ~o"2026-06-15T09:00:00/2026-06-15T17:00:00"

alice_busy =
  Tempo.IntervalSet.new!([
    ~o"2026-06-15T10:00:00/2026-06-15T11:00:00",
    ~o"2026-06-15T14:00:00/2026-06-15T15:00:00"
  ])

bob_busy =
  Tempo.IntervalSet.new!([
    ~o"2026-06-15T09:30:00/2026-06-15T10:30:00",
    ~o"2026-06-15T16:00:00/2026-06-15T17:00:00"
  ])

{:ok, alice_free} = Tempo.difference(work, alice_busy)
{:ok, bob_free}   = Tempo.difference(work, bob_busy)
{:ok, mutual}     = Tempo.intersection(alice_free, bob_free)
#=> 09:00–09:30, 11:00–14:00, 15:00–16:00
```

> *"Alice's free time is the workday **minus** her meetings; Bob's is the same. **Mutual** free time is the **intersection** of theirs."*

Free time gives you the *regions* where a meeting could go. Turn them into the discrete slots a booking page actually offers with `Tempo.IntervalSet.slots/3`:

```elixir
mutual
|> Tempo.IntervalSet.slots(~o"PT1H")    # cut into back-to-back 1-hour slots
|> Tempo.IntervalSet.to_list()
#=> 11:00–12:00, 12:00–13:00, 13:00–14:00, 15:00–16:00
```

### Arrival time — shift through free time only

Free-busy answers *where* something can go. The dual question — **when will it be done?** — is a shift that consumes free time only: `Tempo.shift/3` with `skipping:` jumps busy spans at no cost.

```elixir
start   = ~o"2026-06-19T15:00"                        # Friday afternoon
weekend = ~o"2026-06-19/2026-06-23" |> Enum.filter(&Tempo.weekend?/1)
freeze  = ~o"2026-06-22T00:00/2026-06-22T06:00"       # Monday deploy freeze

Tempo.shift(start, ~o"PT12H", skipping: [freeze | weekend])
#=> ~o"2026Y6M22DT9H0M0S"
```

> *"Twelve hours of processing starting **Friday 15:00**: nine hours run before midnight, the **weekend** is skipped, the **deploy freeze** is skipped, and the remaining three hours finish **Monday 09:00**."*

The weekend comes from the calendar's own vocabulary — `Tempo.weekend?/1` is territory-aware, so `Tempo.weekend?(&1, :SA)` would skip Friday–Saturday instead. The busy set accepts any mix of intervals, day values, interval sets, or bounded recurrences; overlapping and adjacent spans are coalesced before the walk.

The rules at the edges: an origin already inside a busy span first moves to its end (a shift of `PT0S` from inside a meeting lands at the meeting's end); a negative duration walks backward symmetrically; and the duration must be exact — `~o"P1M"` of free time has no fixed length, so `:year`/`:month` components return `{:error, %Tempo.InvalidUnitError{}}`.

When the only busy time *is* the weekend, skip the window arithmetic entirely: `Tempo.weekends/1` is an unbounded lazy busy set, and the walk consumes only as much of it as the shift needs — no `:bound` required.

```elixir
Tempo.shift(~o"2026-06-18T16:00", ~o"P3D", skipping: Tempo.weekends(from: ~o"2026-06-18"))
#=> ~o"2026Y6M23DT16H0M0S"
```

> *"Three days of processing starting **Thursday 16:00**, skipping **every weekend from then on**, finishes **Tuesday 16:00**."*

A lazy busy set is used on its own (not spliced into a busy list); see `Tempo.IntervalSet.Backend.Lazy` for what an unbounded set can and cannot answer.

> *"The bookable hour-long slots are the mutual windows cut into one-hour pieces."* The 09:00–09:30 opening is too short to hold an hour, so it drops out. Pass `every: ~o"PT30M"` to offer a start on every half-hour instead (overlapping slots), or a larger `:every` to leave gaps between offered times.

This is **instant-level** set algebra — you are asking about *time regions*, not preserving individual calendar events — so `difference`/`intersection` are the right operators rather than their member-preserving companions. The [set operations guide](./set-operations.md) explains that distinction in full; to load real calendars from `.ics` files instead of inline busy sets, see the free-busy recipe in the [cookbook](./cookbook.md).

## 6. Dependency scheduling (the critical path)

The sections above schedule *recurrences* — a rule repeated over a window. A different question is scheduling *a plan of dependent tasks*: "design takes 2 days, then build (3 days) and docs (1 day) can run, then ship (2 days) needs both — when does each run, and what's due by the deadline?" That's the critical path method, and `Tempo.Schedule` solves it directly (it's the same Simple Temporal Problem `Tempo.Network` already solves — tasks are periods, dependencies are boundary relations).

```elixir
{:ok, plan} =
  Tempo.Schedule.new()
  |> Tempo.Schedule.task(:design, duration: ~o"P2D", start: ~o"2026-06-01")
  |> Tempo.Schedule.task(:build, duration: ~o"P3D", after: :design)
  |> Tempo.Schedule.task(:docs, duration: ~o"P1D", after: :design)
  |> Tempo.Schedule.task(:ship, duration: ~o"P2D", after: [:build, :docs], deadline: ~o"2026-06-08")
  |> Tempo.Schedule.solve()

plan[:ship].start                 #=> ~o"2026Y6M6D"
plan[:docs].critical?             #=> false   (docs has slack)
Tempo.Schedule.critical_path(plan) #=> [:design, :build, :ship]
Tempo.Schedule.span(plan)          #=> the project interval, 06-01 .. 06-08
```

> *"Design, then build and docs in parallel, then ship — due the 8th. Ship starts on the 6th; docs has slack and isn't on the critical path; the project runs design → build → ship."*

Each task carries a `:duration` (exact or a `{min, max}` range) and optional `:after` dependencies (finish-to-start — a successor starts no earlier than its predecessors finish). Bounds come from `:start` (a fixed anchor), `:earliest`, `:deadline`, or a `:within` window. `solve/1` returns a `%Tempo.Schedule.Slot{}` per task with its early and late positions; `critical?` is true when a task has zero slack. An over-tight deadline or a dependency cycle returns `{:error, :infeasible}`.

### What this is not

Scheduling *around* a busy calendar — "drop this task into the first free gap" — is a disjunctive problem (before *or* after each existing meeting) that the Simple Temporal Problem can't express. For that, subtract the busy periods to find the free regions (`Tempo.difference/2`), then cut those regions into fixed-length bookable slots with `Tempo.IntervalSet.slots/3` (see [set operations](./set-operations.md) and [the cookbook](./cookbook.md)). `Tempo.Schedule` is for *dependency* scheduling, where constraints compose by conjunction.

## Putting it together

A practical scheduling layer built on Tempo looks like:

```elixir
defmodule Schedule do
  def weekly_meeting(name, %Date{} = date, %Time{} = time, zone) do
    {:ok, datetime} = DateTime.new(date, time, zone)
    # A meeting is a to-the-minute thing, so drop the source's seconds.
    dtstart = Tempo.from_elixir(datetime, resolution: :minute)

    # "Every week from `dtstart`, forever" is just a recurring interval.
    recurrence = Tempo.Interval.new!(from: dtstart, duration: ~o"P1W", recurrence: :infinity)
    %{name: name, recurrence: recurrence}
  end

  def occurrences_in(%{recurrence: recurrence}, from, to) do
    bound = Tempo.Interval.new!(from: from, to: to)
    {:ok, set} = Tempo.to_interval(recurrence, bound: bound)
    Tempo.IntervalSet.to_list(set)
  end
end

retrospective =
  Schedule.weekly_meeting("Retro", ~D[2025-06-01], ~T[14:00:00], "Europe/London")

# Occurrences for Q3:
Schedule.occurrences_in(retrospective, ~o"2025-07-01", ~o"2025-10-01")
# 18 weekly occurrences, each with wall time 14:00 in Europe/London
```

> **`Tempo.from_elixir/2` converts native Elixir date/time structs.** When a value arrives as a `Date`, `Time`, `NaiveDateTime`, or `DateTime` — from a database row, an API payload, a form — convert it with `from_elixir/2` rather than picking its fields apart by hand or re-formatting it to an ISO 8601 string and parsing it back. The time zone carries across faithfully, and the `:resolution` option lets you say how precise the value really is: a `DateTime` is second-precise, but a weekly meeting is a *to-the-minute* thing, so `resolution: :minute` makes the value — and every occurrence derived from it — a one-minute span rather than a one-second one. (For a value you are assembling from loose components rather than a struct, `Tempo.new/1` is the runtime companion to the `~o` sigil.)

> **Store** the recurrence as a value — a zoned repeating interval, `~o"R/2025Y6M1DT14H0MZ+1H[Europe/London]/P1W"`. **Materialise** into an IntervalSet only when you need concrete occurrences, bounded to the query window. **Display** by projecting each endpoint's wall time through the viewer's preferred zone. Nothing about the stored value changes when the zone data does.

## Related reading

* [Enumeration semantics](./enumeration-semantics.md) — what iteration means on a Tempo value or IntervalSet.

* [Set operations](./set-operations.md) — free/busy, overlap detection, the sweep-line algorithm.

* [iCalendar integration](./ical-integration.md) — round-trip a real `.ics` file, preserve metadata, expand RRULEs from it.

* [RFC 5545 RRULE conformance](./rfc5545_rrule_conformance.md) — property-by-property coverage of the standard.

* [The cookbook](./cookbook.md) — recipe-format queries for the common scheduling patterns.
