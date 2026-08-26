# Tutorial: build a booking-availability service

This tutorial builds the availability core of a real service, one concept at a time. **Studio Nine** rents a recording room by the hour. By the end you will have: opening hours as data, existing bookings imported from an iCalendar feed, free time computed by set algebra, bookable slots a front end can offer, multi-resource availability, weekend-aware job estimates, a recurring residency, and a cross-timezone booking check — in about forty lines of Tempo.

No scaffolding is needed. Everything below runs in `iex` after:

```elixir
Mix.install([{:ex_tempo, "~> 1.0"}, {:ical, "~> 3.0"}, {:tz, "~> 0.28"}])
Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
import Tempo.Sigils
```

In a Mix project, add the same three dependencies and put the `Calendar` line in `config/runtime.exs`.

## Step 1 — Opening hours are a value, not a pair of integers

Monday June 15, 2026. The studio opens 09:00–17:00 UTC. In most systems that's two columns and a convention; in Tempo it's one value — a half-open interval `[09:00, 17:00)`, so a booking ending at 17:00 fits exactly and nothing double-counts the boundary:

```elixir
iex> open_hours = ~o"2026-06-15T09Z/2026-06-15T17Z"
```

The `Z` grounds the hours on the UTC timeline. Tempo distinguishes *grounded* values (zoned or offset) from *floating* ones (wall-clock only) and refuses to compare across that line — a deliberate guard you will meet if you mix them.

## Step 2 — Import the bookings you already have

Studio Nine's bookings live where everyone's do: an iCalendar feed. Tempo imports it with every event's metadata intact:

<!-- guides:run -->

```elixir
ics = """
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//StudioNine//Bookings//EN
BEGIN:VEVENT
UID:booking-1
DTSTART:20260615T100000Z
DTEND:20260615T120000Z
SUMMARY:Velvet Static — tracking
LOCATION:Room A
END:VEVENT
BEGIN:VEVENT
UID:booking-2
DTSTART:20260615T150000Z
DTEND:20260615T160000Z
SUMMARY:Podcast edit
LOCATION:Room A
END:VEVENT
END:VCALENDAR
"""
```

```elixir
iex> {:ok, bookings} = Tempo.ICal.from_ical(ics)
iex> Tempo.IntervalSet.count(bookings)
2
```

Two bookings: a two-hour tracking session at 10:00 and an hour of podcast editing at 15:00.

## Step 3 — Free time is the day minus the bookings

Here is the sentence the whole service is built on: *free time is the opening hours **minus** the bookings.* Tempo lets you write the sentence:

```elixir
iex> {:ok, free} = Tempo.difference(open_hours, bookings)
iex> Tempo.IntervalSet.count(free)
3
```

Three free regions — before the tracking session, the afternoon gap, and the last hour. No cursor over sorted rows, no edge-case arithmetic at the boundaries: the half-open convention makes adjacent spans meet exactly.

## Step 4 — From free regions to bookable slots

A booking page doesn't offer "regions"; it offers slots. Cut the free time into hour slots and keep only the windows a full hour fits:

```elixir
iex> slots =
...>   free
...>   |> Tempo.IntervalSet.slots(~o"PT1H")
...>   |> Tempo.IntervalSet.to_list()
...>   |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))
iex> length(slots)
5
```

> *"**Bookable slots** are the **free regions**, cut into **hour-long windows**, keeping those **at least an hour** — five of them."*

Every noun and verb in that sentence is a line of the pipeline. This is the test Tempo's API holds itself to: if you can say it, you can write it.

## Step 5 — Two resources must both be free

A session needs the room *and* an engineer. Each has their own busy calendar; the bookable time is the **intersection** of their free time:

```elixir
iex> engineer_busy = ~o"2026-06-15T09Z/2026-06-15T13Z"
iex> {:ok, engineer_free} = Tempo.difference(open_hours, engineer_busy)
iex> {:ok, both_free} = Tempo.intersection(free, engineer_free)
iex> Tempo.IntervalSet.count(both_free)
2
```

The engineer is out until 13:00, so the morning region drops away and two windows survive — the afternoon gap and the last hour. Add a third resource and it's one more `intersection/2`; the algebra composes.

## Step 6 — The studio week is territory-aware

Studio Nine closes on weekends — but *which days are the weekend* depends on where the studio is. Tempo reads that from CLDR data rather than hard-coding Saturday–Sunday:

```elixir
iex> Tempo.weekend?(~o"2026-06-19")
false
iex> Tempo.weekend?(~o"2026-06-19", :SA)
true
```

June 19 is a Friday — a workday for the London studio, the weekend for a Riyadh branch. Business-day arithmetic rides on the same data:

```elixir
iex> Tempo.add_working_days(~o"2026-06-18", 3)
~o"2026Y6M23D"
```

Three working days from Thursday lands on Tuesday — the weekend doesn't count.

## Step 7 — "When will it be done?"

A client drops off a 72-hour tape restoration on Thursday at 16:00. The machine only runs while the studio is staffed — weekends don't count. `Tempo.shift/3` with `skipping:` consumes the duration from free time only, and `Tempo.weekends/1` supplies the weekend as an *unbounded lazy set* — no end date required, the walk takes only what it needs:

```elixir
iex> Tempo.shift(~o"2026-06-18T16:00", ~o"P3D", skipping: Tempo.weekends(from: ~o"2026-06-18"))
~o"2026Y6M23DT16H0M0S"
```

> *"Seventy-two hours of restoration starting **Thursday 16:00**, skipping **every weekend**, finishes **Tuesday 16:00**."*

Give the customer that timestamp with confidence: busy spans cost nothing to cross, and if the drop-off had landed *inside* a busy span, the shift would first step to its edge.

## Step 8 — The weekly residency

A band books the room every Tuesday for four weeks. That's an RFC 5545 recurrence rule, and Tempo parses it into the same interval model as everything else:

```elixir
iex> {:ok, residency} = Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=TU;COUNT=4", from: ~o"2026-06-01")
iex> {:ok, tuesdays} = Tempo.to_interval(residency)
iex> Tempo.IntervalSet.count(tuesdays)
4
```

Occurrences are just another busy set — every operation from the previous steps applies unchanged. Is June 9 blocked by the residency?

```elixir
iex> Tempo.overlaps?(~o"2026-06-09", tuesdays)
true
```

## Step 9 — A client in another timezone

A Sydney band asks for "8 pm our time on June 15". Does that collide with anything in the book? Ground their wall-clock request in their zone and ask — Tempo compares across zones by UTC instant, no manual conversion:

```elixir
iex> sydney_request = Tempo.from_elixir(DateTime.new!(~D[2026-06-15], ~T[20:00:00], "Australia/Sydney"))
iex> Tempo.overlaps?(sydney_request, bookings)
true
```

Sydney 20:00 is 10:00 UTC — squarely inside the Velvet Static tracking session. The booking page can answer honestly before anyone gets an email.

## What you built

Ten values and eight operations: opening hours and an iCal feed became free time (`difference`), bookable slots (`slots` + `at_least?`), multi-resource windows (`intersection`), territory-aware estimates (`weekend?`, `add_working_days`, `shift` with `skipping:`), a recurring block (`RRule.parse` + `to_interval`), and a cross-timezone collision check (`overlaps?`). Every step was a sentence first and code second.

## Where next

* The [scheduling guide](https://hexdocs.pm/ex_tempo/scheduling.html) — floating vs grounded events, zone-rule-proof future dates, and critical-path scheduling.
* The [scheduling livebook](https://hexdocs.pm/ex_tempo/scheduling-workbook.html) — this material, runnable.
* The [iCal integration guide](https://hexdocs.pm/ex_tempo/ical-integration.html) — recurring events in feeds, attendee filtering, metadata flow.
* The [cookbook](https://hexdocs.pm/ex_tempo/cookbook.html) — recipe-format answers when you know the question.
