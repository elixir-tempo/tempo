# Scheduling

Scheduling is really two questions, and Tempo answers each with a different part of the library:

1. **"When does this recur?"** — generate the occurrences of a repeating rule, bounded and zone-correct (sections 1–4).

2. **"When are we free to meet?"** — turn busy calendars into open, bookable time with set operations (section 5).

The first question has the sharpest edges — future dates, wall-clock vs UTC, and time zones that change rules out from under you — so it gets the most space. Sections 1–4 each give the principle, the Tempo idiom, and the pitfall to avoid:

* **You can't list an infinite stream.** Bounded scheduling is a design decision.

* **Wall-clock time is authoritative; UTC is a projection.** Tempo stores the user's wall time and derives the UTC instant on demand.

* **"Floating" events vs zoned events** — Tempo distinguishes them through what's on the value, not a flag.

* **Future dates survive zone-rule changes** — because Tempo never caches a UTC value, re-reading a future event automatically uses the current zone data.

A third question — *when can these dependent tasks run, and which of them is critical?* — is the critical path method, and belongs to the companion package `tempo_network`, which solves it over Tempo's intervals.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` to the caller's namespace; no helper functions leak in.

## 1. Bounded enumeration

An RRULE like `FREQ=MONTHLY;BYDAY=2MO` ("the second Monday of every month") is **infinite** — occurrences continue forever. You cannot call `Enum.to_list/1` on an infinite sequence.

Tempo splits the two operations: reading the rule into a recurrence is cheap and needs no bound, but **listing** its occurrences as an interval set does.

```elixir
iex> recurrence = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2025-01-01")
iex> Tempo.bounded?(recurrence)
false

iex> {:ok, set} = Tempo.to_interval(recurrence, within: ~o"2025")
iex> Tempo.IntervalSet.count(set)
12

iex> Tempo.IntervalSet.first(set)
~o"2025Y1M13D/2025Y1M13D"
```

> *"The **recurrence** is the second Monday of every month from the start of 2025. Its **occurrences within 2025** are twelve days, the first the 13th of January."*

The **recurrence** is the *rule*; the **interval set** is its *occurrences* inside a window. `:within` is supplied when the occurrences are listed, never at the rule. Each occurrence stays a member of its own — which is what you want for scheduling. For the time the occurrences cover between them, with those that touch merged into one span, pipe through `Tempo.IntervalSet.coalesce/1` — useful for free-busy questions but not for "list the events."

For ad-hoc use, `Enum.take/2` and `Stream.take/2` work directly on the recurrence — it is enumerable, lazily:

```elixir
iex> Enum.take(recurrence, 3)
[~o"2025Y1M13D/2025Y1M13D", ~o"2025Y2M10D/2025Y2M10D", ~o"2025Y3M10D/2025Y3M10D"]
```

### Pitfall

Forgetting the window:

```elixir
iex> {:error, error} = Tempo.to_interval(recurrence)
iex> Exception.message(error)
"~o\"R/2025Y1M1D/P1M/FL1K2IN\" has no end; give a :within window to bound it"
```

Tempo refuses rather than hanging — a forgotten window is a design error, not a runtime surprise.

## 2. Wall-clock time is authoritative

When a user schedules "08:00 on 1 March 2030 in Paris", the *real* scheduling intent is the wall-clock reading on that morning — not a specific UTC instant. If Paris changes its DST rules between now and 2030, the UTC instant should shift; the wall-clock event should not.

Tempo stores exactly what the user wrote:

```elixir
iex> event = ~o"2030-03-01T08:00:00[Europe/Paris]"
iex> {Tempo.hour(event), Tempo.minute(event)}
{8, 0}

iex> Tempo.to_iso8601!(event)
"2030Y3M1DT8H0M0S[Europe/Paris]"
```

No UTC seconds are cached on the value. When you ask for the UTC projection, Tempo consults the configured time zone database at the time of the call, and the result reflects whatever zone rules it currently knows about 2030. Re-run the same call after a data update and the number may change — that's the correct behaviour for future dates.

### Principle

**Store what the user said. Compute UTC when you need it.** This is the same discipline Apple Calendar and Google Calendar enforce: the canonical form of a future event is wall-clock + zone, not UTC.

### Pitfall

Serialising a Tempo value as "the UTC seconds" and rehydrating from that:

<!-- guides:skip -->
```elixir
# Do NOT do this for future events:
{:ok, cached_utc} = Tempo.shift_zone(event, "Etc/UTC")
store_in_database(cached_utc)
```

When the IANA database ships a DST rule change for 2030, your cached number is now wrong — but you've lost the wall-clock information needed to recompute. Serialise the Tempo value itself (`Tempo.to_iso8601/1` round-trips faithfully) and project to UTC only at display or comparison time.

## 3. Floating vs zoned values

Every Tempo value is one of two kinds, and the distinction governs whether it can be placed on the universal (UTC) time line at all:

* A **zoned** value carries a zone or a time shift — `[Europe/Paris]`, `Z`, or `+05:30` — so it names a position every observer agrees on. `Tempo.zoned?/1` returns `true`.

* A **floating** value carries neither. `~o"2030-03-01T08:00:00"` is a wall-clock reading with no observer attached — "8am wherever the reader happens to be". It has no single universal instant. `Tempo.floating?/1` returns `true`.

Apple Calendar's **"floating"** events (iCalendar, RFC 5545, calls the form "local time") are exactly this kind: a "6am workout" on holiday is still 6am local, whatever zone you fly to.

Tempo makes the distinction through **what is on the value**, not a flag — and exposes it through two predicates rather than field-poking:

```elixir
iex> Tempo.floating?(~o"2030-03-01T08:00:00")
true

iex> Tempo.zoned?(~o"2030-03-01T08:00:00[Europe/Paris]")
true

iex> Tempo.zoned?(~o"2030-03-01T08:00:00Z")
true

iex> Tempo.zoned?(~o"2030-03-01T08:00:00+05:30")
true
```

Zoned values come in three flavours; the table lays out all four forms:

| Form | Kind | Meaning |
|---|---|---|
| `~o"2030-03-01T08:00:00"` | **Floating** | 8am in whatever zone the reader is in — no universal instant |
| `~o"2030-03-01T08:00:00[Europe/Paris]"` | Zoned — named zone | 8am Paris wall time, UTC derived on demand |
| `~o"2030-03-01T08:00:00Z"` | Zoned — UTC | a specific UTC instant, wall times vary by zone |
| `~o"2030-03-01T08:00:00+05:30"` | Zoned — time shift | UTC+05:30 regardless of zone-rule changes |

The right choice depends on what the user said:

* "Morning workout at 6am" when travelling — floating.

* "Meeting at 2pm Paris" — zoned, in a named zone (`[Europe/Paris]`).

* "Server job at 03:00 UTC" — zoned, in UTC (`Z`).

* "Event at UTC+05:30" — zoned, at a time shift.

### Placing a floating value in a zone

When a floating value needs to go on the time line — to compare it, project it to UTC, or move it to another zone — place it in a zone with `Tempo.in_zone/2`. This reads its wall clock as the local time in that zone; the numbers on the clock do not move, only the frame is attached:

```elixir
iex> floating = ~o"2030-03-01T08:00:00"
iex> {:ok, paris} = Tempo.in_zone(floating, "Europe/Paris")
iex> paris
~o"2030Y3M1DT8H0M0S[Europe/Paris]"
```

`in_zone/2` *places* a floating value in a zone. Its counterpart `shift_zone/2` *moves* a zoned value to another zone, giving the reading of the same instants on that zone's clock:

```elixir
iex> Tempo.shift_zone(paris, "America/New_York")
{:ok, ~o"2030Y3M1DT2H0M0S[America/New_York]"}
```

The two are mirror images, and each refuses the other's operand with a `Tempo.FrameError` that names the one to use:

```elixir
iex> {:error, %Tempo.FrameError{reason: :zoned}} = Tempo.in_zone(paris, "Europe/London")
iex> {:error, %Tempo.FrameError{reason: :floating}} = Tempo.shift_zone(floating, "Europe/London")
```

### Comparing floating and zoned values

A floating value has no position on the universal time line, so **it cannot be compared with a zoned one** — there is no fact of the matter about whether "8am somewhere" falls before or after "8am in Paris" until you say *which* somewhere. Rather than reading the floating side as UTC and inventing an answer, Tempo refuses the comparison:

```elixir
iex> {:error, %Tempo.FrameError{}} = Tempo.relation(floating, paris)
```

The same refusal applies to every verb built on the relation. A function with an error to return returns it, as `relation/2` and the set operations do. A predicate, with only true and false to give, raises it: `before?/2`, `after?/2`, `overlaps?/2`, `within?/2`, `disjoint?/2`, `contains?/2` and the rest. Only the *mixed* case is refused: two floating values compare on their shared wall clock, and two zoned values by their instants. Place the floating side in a zone first and the comparison is well-defined:

```elixir
iex> {:ok, placed} = Tempo.in_zone(floating, "Europe/Paris")
iex> Tempo.relation(placed, paris)
:equals
```

This is the comparison corollary of "same wall clock is not the same instant" (see the [Falsehoods](./falsehoods.md) guide): if two zoned readings in different zones are already different instants, then a *floating* reading — which fixes no zone at all — has no instant to compare, and the right response is to decline rather than guess.

### A zone on an interval

An interval is in one zone. Written as ISO 8601, the zone goes once, at the end, after the whole interval — and it is the zone of both ends, so an interval never straddles the floating and universal time lines:

```elixir
iex> conference = ~o"2030-03-01T08:00/2030-03-05T08:00[Europe/Paris]"
iex> Tempo.zoned?(conference)
true

iex> {Tempo.zoned?(Tempo.Interval.from(conference)), Tempo.zoned?(Tempo.Interval.to(conference))}
{true, true}
```

A time shift is each end's own, and one written on the first end applies to a second that has none, as ISO 8601-1 §5.5.1 says — "representations for time zones and UTC included with the component preceding the separator shall be assumed to apply to the component following the separator":

```elixir
iex> Tempo.zoned?(~o"2030-03-01T08:00+01:00/2030-03-05T08:00")
true
```

A zone written on an end, as in `2030-03-01T08:00[Europe/Paris]/2030-03-05T08:00[Europe/London]`, is a `Tempo.ParseError`: it is written once, after the whole interval. `Tempo.Interval.new/1` follows the same rule and returns an error for two ends in different zones, so an interval you build and its ISO 8601 text agree. Move one end with `Tempo.shift_zone/2` first.

```elixir
iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2030-03-01T08:00[Europe/Paris]/2030-03-05T08:00[Europe/London]")

iex> {:error, %Tempo.IntervalEndpointsError{reason: :zones}} = Tempo.Interval.new(from: ~o"2030-03-01T08:00[Europe/Paris]", to: ~o"2030-03-05T08:00[Europe/London]")
```

### Principle

**The interpretation of a wall-clock reading is metadata, not an afterthought.** Tempo has you make that choice when the value is read, preserves it through every operation, and refuses operations that would need a choice you have not yet made.

## 4. Future dates survive zone-rule changes

When Paris last moved its DST rules in 1996, any calendar entry stored as a frozen UTC instant for a post-1996 date had to be rewritten. Modern calendars (Google, Apple, Outlook) avoid this by storing wall-clock + zone and deriving UTC on demand — which is exactly what Tempo does.

Concretely: a Paris event stored today for 2030 will be re-evaluated with whatever the zone database knows about Paris's rules in 2030 *at the time of the computation*:

```elixir
# Today, the IANA data says this is UTC+1 (standard time in March).
iex> Tempo.shift_zone(event, "Etc/UTC")
{:ok, ~o"2030Y3M1DT7H0M0S[Etc/UTC]"}
```

If a later release of the IANA data says France abolished DST in 2027, the next `shift_zone/2` returns another UTC time — the event is still 8am on Paris's clock, and the UTC reading moves. `Tempo.duration/1` likewise places each end afresh on every call, and so do comparisons and set operations. Nothing is frozen: the day the clocks go forward is, each time you ask, as long as the zone data then says it is.

```elixir
iex> Tempo.duration(~o"2026-03-29T00:00/2026-03-30T00:00[Europe/Paris]")
~o"PT1380M"
```

> *"The 29th of March 2026 in Paris, midnight to midnight, is **twenty-three hours** long."*

### When to freeze

There are cases where you **want** the UTC instant frozen — a CI build that must run "at exactly 03:00 UTC on 15 March 2030" regardless of how zones shift. Store those as UTC (`~o"2030-03-15T03:00:00Z"`). The `Z` suffix is the explicit promise: "this is a UTC instant, don't recompute."

A time shift written beside the zone freezes the instant too. `2030-03-01T08:00:00+01:00[Europe/Paris]` states both, and the shift gives the moment (RFC 9557 §3.4): should Paris be at another offset by then, the value is still seven o'clock UTC, and no longer eight on Paris's clock.

```elixir
iex> {:ok, datetime} = Tempo.to_datetime(~o"2030-03-01T08:00:00+03:00[Europe/Paris]")
iex> DateTime.to_naive(datetime)
~N[2030-03-01 06:00:00]
```

> *"Eight o'clock at three hours ahead of UTC is five o'clock UTC, and that moment is **six** on Paris's clock."*

An event that is meant to stay at 8am on Paris's clock is stored with its zone and no shift.

### Principle

**Don't cache UTC. Don't cache DST. Tempo doesn't, and the reason you trust this library over rolling your own is exactly this discipline.**

## 5. Free-busy and availability

The recurrence sections generate *when things happen*. The opposite question — *when is nobody busy* — is set algebra over those occurrences. **Free time is the workday minus the busy periods; mutual free time is the intersection of each person's free time.**

```elixir
iex> work = ~o"2026-06-15T09:00/2026-06-15T17:00"
iex> alice_busy = Tempo.IntervalSet.new!([~o"2026-06-15T10:00/2026-06-15T11:00", ~o"2026-06-15T14:00/2026-06-15T15:00"])
iex> bob_busy = Tempo.IntervalSet.new!([~o"2026-06-15T09:30/2026-06-15T10:30", ~o"2026-06-15T16:00/2026-06-15T17:00"])
iex> {:ok, alice_free} = Tempo.difference(work, alice_busy)
iex> {:ok, bob_free} = Tempo.difference(work, bob_busy)
iex> {:ok, mutual} = Tempo.intersection(alice_free, bob_free)
iex> mutual
~o"{2026Y6M15DT9H0M/T9H30M,2026Y6M15DT11H0M/T14H0M,2026Y6M15DT15H0M/T16H0M}"
```

> *"Alice's free time is the workday **minus** her meetings; Bob's is the same. **Mutual** free time is the **intersection** of theirs."*

Free time gives you the *regions* where a meeting could go. Turn them into the discrete slots a booking page actually offers with `Tempo.IntervalSet.slots/3`:

```elixir
iex> {:ok, slots} = Tempo.IntervalSet.slots(mutual, ~o"PT1H")
iex> Tempo.IntervalSet.members(slots)
[~o"2026Y6M15DT11H0M/T12H0M", ~o"2026Y6M15DT12H0M/T13H0M", ~o"2026Y6M15DT13H0M/T14H0M", ~o"2026Y6M15DT15H0M/T16H0M"]
```

> *"The bookable hour-long slots are the mutual windows cut into one-hour pieces."*

The 09:00–09:30 opening is too short to hold an hour, so it drops out. Pass `every: ~o"PT30M"` to offer a start on every half-hour instead (overlapping slots), or a larger `:every` to leave gaps between offered times:

```elixir
iex> {:ok, half_hourly} = Tempo.IntervalSet.slots(mutual, ~o"PT1H", every: ~o"PT30M")
iex> Tempo.IntervalSet.count(half_hourly)
6
```

These operations ask about *regions of time*, not about individual calendar events, so `difference/2` and `intersection/2` are the right operators. The [set operations guide](./set-operations.md) explains that distinction in full; to load real calendars from `.ics` files instead of inline busy sets, see the free-busy recipe in the [cookbook](./cookbook.md).

### Arrival time — shift through free time only

Free-busy answers *where* something can go. The dual question — **when will it be done?** — is a shift that consumes free time only: `Tempo.shift/3` with `skipping:` jumps busy spans at no cost.

```elixir
iex> start = ~o"2026-06-19T15:00"
iex> weekend = Enum.filter(~o"2026-06-19/2026-06-23", &Tempo.weekend?/1)
iex> freeze = ~o"2026-06-22T00:00/2026-06-22T06:00"
iex> Tempo.shift(start, ~o"PT12H", skipping: [freeze | weekend])
{:ok, ~o"2026Y6M22DT9H0M"}
```

> *"Twelve hours of processing starting **Friday 15:00**: nine hours run before midnight, the **weekend** is skipped, the **deploy freeze** is skipped, and the remaining three hours finish **Monday 09:00**."*

The weekend comes from the calendar's own vocabulary — `Tempo.weekend?/2` knows each territory's, so `Tempo.weekend?(&1, :SA)` skips Friday and Saturday instead. The busy list takes any mix of intervals, day values, interval sets and bounded recurrences; spans that overlap or touch are merged before the walk.

The rules at the edges: an origin already inside a busy span first moves to its end (a shift of `PT0S` from inside a meeting lands at the meeting's end); a negative duration walks backward the same way; and the duration must be exact — `~o"P1M"` of free time has no fixed length, so a duration of years or months returns `{:error, %Tempo.ConversionError{}}`.

When the only busy time *is* the weekend, skip the window arithmetic entirely: the weekend days of a span with no end are a busy set with no end, and the walk consumes only as much of it as the shift needs — no `:within` required.

```elixir
iex> {:ok, weekends} = Tempo.select(~o"2026-06-18/..", Tempo.weekends(:US))
iex> Tempo.shift(~o"2026-06-18T16:00", ~o"P3D", skipping: weekends)
{:ok, ~o"2026Y6M23DT16H0M"}
```

> *"Three days of processing starting **Thursday 16:00**, skipping **every weekend from then on**, finishes **Tuesday 16:00**."*

A busy set with no end is given on its own, not spliced into a list, and is walked forward only.

## Putting it together

A practical scheduling layer built on Tempo looks like:

<!-- guides:run -->
```elixir
defmodule Schedule do
  def weekly_meeting(name, %Date{} = date, %Time{} = time, zone, length) do
    datetime = DateTime.new!(date, time, zone)
    # A meeting is a to-the-minute thing, so drop the source's seconds.
    start = Tempo.from_elixir!(datetime, resolution: :minute)

    # "Every week from the start, for this long each time."
    recurrence = Tempo.RRule.parse!("FREQ=WEEKLY", from: start, duration: length)
    %{name: name, recurrence: recurrence}
  end

  def occurrences_in(%{recurrence: recurrence}, window) do
    recurrence |> Tempo.to_interval!(within: window) |> Tempo.IntervalSet.members()
  end
end
```

```elixir
iex> retrospective = Schedule.weekly_meeting("Retro", ~D[2025-06-01], ~T[14:00:00], "Europe/London", ~o"PT1H")
iex> third_quarter = Schedule.occurrences_in(retrospective, ~o"2025-07/2025-09")
iex> length(third_quarter)
13

iex> hd(third_quarter)
~o"2025Y7M6DT14H0M/T15H0M[Europe/London]"

iex> Tempo.shift_zone(hd(third_quarter), "America/New_York")
{:ok, ~o"2025Y7M6DT9H0M/T10H0M[America/New_York]"}
```

> *"The retrospective is **every week** from the 1st of June at two in London, **for an hour**. In the **third quarter** it meets thirteen times, first on the 6th of July — at nine in the morning for a colleague in New York."*

**`Tempo.from_elixir/2` converts native Elixir date/time structs.** When a value arrives as a `Date`, `Time`, `NaiveDateTime` or `DateTime` — from a database row, an API payload, a form — convert it with `from_elixir/2` rather than picking its fields apart by hand or formatting it to ISO 8601 text and reading it back. The time zone carries across faithfully, and the `:resolution` option lets you say how precise the value really is: a `DateTime` is second-precise, but a weekly meeting is a *to-the-minute* thing, so `resolution: :minute` makes the value, and every occurrence derived from it, written to the minute. (For a value you are assembling from loose components rather than a struct, `Tempo.new/1` is the runtime companion to the `~o` sigil.)

**Store** the recurrence as a value — its ISO 8601 text reads back to the same recurrence, zone and occurrence length included:

```elixir
iex> text = Tempo.to_iso8601!(retrospective.recurrence)
"R/2025Y6M1DT14H0M/P1W/FLL7KN/PT1HN[Europe/London]"

iex> Tempo.from_iso8601!(text) == retrospective.recurrence
true
```

**List** its occurrences only when you need them, bounded to the query window. **Display** by moving each to the viewer's zone. Nothing about the stored value changes when the zone data does.

## Related reading

* [Enumeration semantics](./enumeration-semantics.md) — what a walk of a Tempo value or an interval set yields.

* [Set operations](./set-operations.md) — free-busy, overlap detection, and the operators behind them.

* [iCalendar integration](./ical-integration.md) — round-trip a real `.ics` file, preserve metadata, expand RRULEs from it.

* [RFC 5545 RRULE conformance](./rfc5545_rrule_conformance.md) — property-by-property coverage of the standard.

* [The cookbook](./cookbook.md) — recipe-format queries for the common scheduling patterns.
