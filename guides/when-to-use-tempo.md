# When to Use Tempo

The one-line answer: reach for Tempo whenever **time is a span**. Reach for the Elixir standard library (`Date`, `Time`, `DateTime`, `NaiveDateTime`) whenever **time is a single instant and a single operation** — timestamps, benchmarks, quick comparisons, and integration with systems that speak POSIX seconds.

Interop between the two is deliberate and cheap. Convert at the boundary; use whichever idiom fits the task.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

## Tempo is the right call when…

### You're thinking in intervals

Scheduling ("this meeting from 2pm to 3pm"), availability ("free during work hours Mon–Fri"), date ranges ("Q3 2026" — a span, not a moment), recurrence ("every second Monday of the month" — infinite span needing bounded materialisation). The stdlib models these as awkward pairs of `DateTime` values and hand-rolled comparison logic. Tempo models them as first-class bounded spans with predicates and operators.

### You need set operations on time

`Tempo.union/2`, `intersection/2`, `difference/2`, `symmetric_difference/2`, `complement/2`. "Find the overlap between these two people's calendars." "Available slots within the work day minus busy periods." "Free hours across a team of five." None of this exists in the stdlib.

### You need Allen's interval algebra

The thirteen named relations — `:precedes`, `:meets`, `:overlaps`, `:during`, `:equals`, and the eight inverses — exposed as `Tempo.before?/2`, `after?/2`, `meets?/2`, `adjacent?/2`, `during?/2`, `within?/2`, `overlaps?/2`. When "A comes before B" isn't specific enough ("is there a gap? does A end where B begins? do they overlap?"), stdlib's three-valued `:lt | :eq | :gt` doesn't help.

### You need calendar awareness beyond Gregorian

Hebrew, Islamic, Julian, Coptic, Ethiopic, Persian, Chinese, Japanese, and more. `~o"5786-10-30[u-ca=hebrew]"` and `~o"2026-06-15"` can be compared, enumerated, and combined directly — Tempo performs the calendar conversion automatically. Historical / archaeological dates (the switch from Julian to Gregorian is a real thing that happens inside date comparisons before 1582) are first-class.

### You need RRULE or iCalendar integration

Stdlib cannot model recurrence at all. `Tempo.RRule` and `Tempo.ICal` parse, generate, and expand RFC 5545 rules, round-trip `.ics` files, and preserve metadata through interval operations.

### You need uncertain or masked dates

ISO 8601-2 EDTF: `~o"156X"` (the 1560s), `~o"2022?"` (approximately 2022), `~o"2026~"` (circa 2026). Tempo treats these as bounded, enumerable values you can compare and operate on. Stdlib has no vocabulary for uncertainty.

### You need locale-aware display

`Tempo.to_string(tempo, locale: "de", format: :long)` goes through CLDR via Localize. Year and month values render as closed intervals ("Jan – Dec 2026") because they *are* intervals. Stdlib's `Calendar.strftime/2` has no concept of this — it formats instants, in the developer's choice of pattern string, without locale-specific month or weekday names.

### You need leap-second awareness

`Tempo.Interval.spans_leap_second?/1`, `leap_seconds_spanned/1`, `duration(iv, leap_seconds: true)`. There have been 27 positive leap seconds since 1972; the POSIX abstraction hides them. No stdlib equivalent.

### You want wall-clock + zone preservation for future events

`~o"2030-03-01T08:00:00[Europe/Paris]"` stores the wall time and the zone, and projects UTC on demand — so your event survives DST rule changes that happen between now and 2030. Stdlib's `DateTime` caches a frozen UTC offset, which becomes stale the moment the zone data updates.

## Elixir stdlib is the right call when…

### You need sub-second precision

Tempo operates at second resolution today. Comparison and arithmetic below the second fail. For microsecond or millisecond precision — API latency measurement, audio/video timing, high-frequency trading — use `DateTime` with its microsecond field.

### You need monotonic time

Benchmarks, timeouts, retries, rate limiting. `System.monotonic_time/0,1` is the right tool — *any* wall-clock interval is wrong for this purpose, in *any* library. Tempo deliberately does not model monotonic time, and never will, because the correct stdlib primitive exists.

### You're talking to a POSIX world

Unix timestamps in HTTP headers (`Last-Modified`, `Set-Cookie`), database columns of type `timestamp` or `bigint` storing seconds-since-epoch, log lines, sensor data, webhook payloads. Use `DateTime.from_unix/1` / `DateTime.to_unix/1` at the edge, then promote to Tempo if the next operation is interval-shaped. Tempo deliberately does not expose `from_unix`/`to_unix` because those functions are instant-valued and would undermine the "time is intervals" thesis; the two-step conversion is the feature.

### You just need the current time, once

`DateTime.utc_now/0` is fine for a single timestamp on a single log line or error. `Tempo.utc_now/0` exists and is also fine — but for a single instant in a single location with no further operations on it, stdlib's surface is all you need.

### You're at a system boundary talking to non-Tempo code

Ecto schemas with `:utc_datetime` columns — use `DateTime`. Phoenix controllers returning `%DateTime{}` to the client — use `DateTime`. Convert to Tempo when the next operation is interval-ish; stay in stdlib when it isn't. Premature conversion adds struct-traversal cost without benefit.

### You're in a hot loop where allocation matters

Tempo values carry more fields than stdlib values (`:calendar`, `:extended`, `:qualification`, `:qualifications`). For high-frequency per-event work (log processing at millions of events per second, sensor streams), stdlib's lighter structs pay off. If you then need interval operations, promote *after* aggregation.

## The interop contract

Conversion is one function call each way:

```elixir
# Stdlib → Tempo
Tempo.from_date(~D[2026-06-15])
Tempo.from_time(~T[14:30:00])
Tempo.from_naive_date_time(~N[2026-06-15 14:30:00])
Tempo.from_date_time(~U[2026-06-15 14:30:00Z])
Tempo.from_elixir(value, resolution: :day)  # unified gateway

# Tempo → Stdlib
Tempo.to_date(tempo)
Tempo.to_time(tempo)
Tempo.to_naive_date_time(tempo)
Tempo.to_elixir(tempo)  # best-fit Date | Time | NaiveDateTime (durations too)
```

A healthy Tempo-using application looks like this:

* **Edge layer** (HTTP controllers, DB adapters, log parsing): stdlib. Parse Unix timestamps, `DateTime` fields, ISO 8601 strings into stdlib types and hand them to the domain layer.

* **Domain layer** (scheduling, availability, recurrence, set operations, interval predicates): Tempo. This is where the "intervals, not instants" thesis pays off.

* **Display layer** (UI rendering, reports, notifications): `Tempo.to_string/2` for user-facing output via CLDR/Localize.

Convert at the edges; stay in Tempo wherever the business logic is interval-shaped.

## The decision tree

> **Am I asking a question about a span?**
> Yes → Tempo.
> No → stdlib is probably enough.
>
> **Do I need sub-second precision or monotonic time?**
> Yes → stdlib.
> No → either works; prefer whichever idiom the surrounding code already uses.
>
> **Am I integrating with a POSIX system or a `%DateTime{}`-typed API?**
> Yes → stdlib at the boundary, promote to Tempo if the next operation is interval-shaped.
>
> **Am I comparing values across different calendars, time zones for future dates, or uncertain / masked dates?**
> Yes → Tempo. Stdlib can't represent these cleanly.

## Related reading

* [The cookbook](./cookbook.md) — recipes for real scheduling and availability queries.

* [Scheduling](./scheduling.md) — bounded enumeration, wall-clock authority, floating vs zoned events.

* [Falsehoods programmers believe about time](./falsehoods.md) — the ten most impactful wrong assumptions, with Tempo idioms showing the correct behaviour.

* [Set operations](./set-operations.md) — union, intersection, difference, and the sweep-line algorithm.

* [Enumeration semantics](./enumeration-semantics.md) — what iteration means on a Tempo value or IntervalSet.
