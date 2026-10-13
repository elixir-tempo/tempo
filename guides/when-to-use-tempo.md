# When to Use Tempo

The one-line answer: reach for Tempo whenever **time is a span**. Reach for the Elixir standard library (`Date`, `Time`, `DateTime`, `NaiveDateTime`) whenever **time is a single instant and a single operation** — timestamps, benchmarks, quick comparisons, and integration with systems that speak POSIX seconds.

Interop between the two is deliberate and cheap. Convert at the boundary; use whichever idiom fits the task.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` to the caller's namespace; no helper functions leak in.

## Tempo is the right call when…

### You're thinking in intervals

Scheduling ("this meeting from 2pm to 3pm"), availability ("free during work hours Mon–Fri"), date ranges ("Q3 2026" — a span, not a moment), recurrence ("every second Monday of the month" — infinite span whose occurrences need a window). The stdlib models these as awkward pairs of `DateTime` values and hand-rolled comparison logic. Tempo models them as first-class bounded spans with predicates and operators.

### You need set operations on time

`Tempo.union/2`, `intersection/2`, `difference/2`, `symmetric_difference/2`, `complement/2`. "Find the overlap between these two people's calendars." "Available slots within the work day minus busy periods." "Free hours across a team of five." None of this exists in the stdlib.

```elixir
iex> work = ~o"2026-06-15T09/2026-06-15T17"
iex> busy = Tempo.IntervalSet.new!([~o"2026-06-15T10/2026-06-15T11", ~o"2026-06-15T14/2026-06-15T15"])
iex> Tempo.difference(work, busy)
{:ok, ~o"{2026Y6M15DT9H/T10H,2026Y6M15DT11H/T14H,2026Y6M15DT15H/T17H}"}
```

> *"The **workday minus** the busy periods is the time that is **free**."*

### You need Allen's interval algebra

The thirteen named relations — `:precedes`, `:meets`, `:overlaps`, `:during`, `:equals`, and the eight inverses — named by `Tempo.relation/2`, with a predicate for each in `Tempo.Allen` and the everyday unions of them as `Tempo.before?/2`, `after?/2`, `adjacent?/2`, `within?/2` and `overlaps?/2`. When "A comes before B" isn't specific enough ("is there a gap? does A end where B begins? do they overlap?"), stdlib's three-valued `:lt | :eq | :gt` doesn't help.

### You need calendar awareness beyond Gregorian

Hebrew, Islamic, Julian, Coptic, Ethiopic, Persian, Chinese, Japanese, and more. `~o"5786-09-30[u-ca=hebrew]"` and `~o"2026-06-15"` are related, walked and combined directly, on the one time line their calendars share. Historical and archaeological dates — a Julian date before the Gregorian reform — are values like any other.

```elixir
iex> Tempo.relation(~o"5786-09-30[u-ca=hebrew]", ~o"2026-06-15")
:equals
```

### You need RRULE or iCalendar integration

Stdlib cannot model recurrence at all. `Tempo.RRule` reads and writes RFC 5545 rules as the recurrences ISO 8601-2 writes, and `Tempo.ICal` and `Tempo.JSCalendar` read calendar files into intervals that carry each event's metadata.

### You need uncertain or masked dates

ISO 8601-2's uncertain and unspecified dates: `~o"156X"` (some year of the 1560s), `~o"2022?"` (2022, uncertain), `~o"2026~"` (about 2026). Tempo holds them as written, walks them, and answers whether a relation between them is certain, possible or impossible. Stdlib has no vocabulary for uncertainty.

### You need locale-aware display

`Tempo.to_string/2` writes a value in a locale's words, through CLDR and Localize. A year or a month is shown as the span it is. Stdlib's `Calendar.strftime/2` formats an instant in a pattern the developer chooses, with no locale's month or weekday names.

```elixir
iex> Tempo.to_string(~o"2026", locale: "de", format: :long)
{:ok, "Januar–Dezember 2026"}

iex> Tempo.to_string(~o"2026-06-15", locale: "de", format: :long)
{:ok, "15. Juni 2026"}
```

### You need leap-second awareness

`Tempo.Interval.spans_leap_second?/1`, `Tempo.LeapSeconds.spanned/1` and `Tempo.duration(span, leap_seconds: true)`. There have been 27 leap seconds since 1972, and POSIX time hides them. No stdlib equivalent.

### You want wall-clock + zone preservation for future events

`~o"2030-03-01T08:00:00[Europe/Paris]"` holds the wall time and the zone, and finds the UTC instant when it is asked for — so the event survives a change of DST rules between now and 2030. Stdlib's `DateTime` holds a UTC offset fixed when it was built, which is stale the moment the zone data changes.

## Elixir stdlib is the right call when…

### You are stamping moments, not asking about spans

Tempo reads, relates and shifts fractions of a second to the microsecond, each a span as long as its precision. But a stream of timestamps that are only ever stored, sorted and subtracted — API latency, audio and video timing, trade ticks — wants a `DateTime` with its microsecond field and `DateTime.diff/3`.

### You need monotonic time

Benchmarks, timeouts, retries, rate limiting. `System.monotonic_time/0,1` is the right tool — *any* wall-clock interval is wrong for this purpose, in *any* library. Tempo deliberately does not model monotonic time, and never will, because the correct stdlib primitive exists.

### You're talking to a POSIX world

Unix timestamps in HTTP headers (`Last-Modified`, `Set-Cookie`), database columns of type `timestamp` or `bigint` storing seconds-since-epoch, log lines, sensor data, webhook payloads. Use `DateTime.from_unix/1` / `DateTime.to_unix/1` at the edge, then promote to Tempo if the next operation is interval-shaped. Tempo deliberately does not expose `from_unix`/`to_unix` because those functions are instant-valued and would undermine the "time is intervals" thesis; the two-step conversion is the feature.

### You just need the current time, once

`DateTime.utc_now/0` is fine for a single timestamp on a single log line or error. `Tempo.utc_now/0` exists and is also fine — but for a single instant in a single location with no further operations on it, stdlib's surface is all you need.

### You're at a system boundary talking to non-Tempo code

Ecto schemas with `:utc_datetime` columns — use `DateTime`. Phoenix controllers returning `%DateTime{}` to the client — use `DateTime`. Convert to Tempo when the next operation is interval-ish; stay in stdlib when it isn't. Premature conversion adds struct-traversal cost without benefit.

### You're in a hot loop where allocation matters

A Tempo value holds its units as a list, with its calendar, zone, marks and metadata beside them, and its operations work through the calendar. For high-frequency per-event work (log processing at millions of events a second, sensor streams), stdlib's lighter structs pay off. If you then need interval operations, convert *after* aggregation.

## The interop contract

Conversion is one function call each way:

```elixir
iex> Tempo.from_date(~D[2026-06-15])
~o"2026Y6M15D"

iex> Tempo.from_elixir(~U[2026-06-15 14:30:00Z], resolution: :minute)
{:ok, ~o"2026Y6M15DT14H30MZ"}

iex> Tempo.to_date(~o"2026-06-15")
{:ok, ~D[2026-06-15]}

iex> Tempo.to_elixir(~o"2026-06-15T14:30Z")
{:ok, ~U[2026-06-15 14:30:00Z]}
```

`from_date/1`, `from_time/1`, `from_naive_datetime/1` and `from_datetime/1` take each type by name and `from_elixir/2` any of them. Going back, `to_date/1`, `to_time/1`, `to_naive_datetime/1` and `to_datetime/1` name the type wanted, and `to_elixir/1` answers with the one the value fills. See [Converting to and from Elixir date/time types](interop.md).

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
> **Do I need monotonic time, or only to stamp and subtract moments?**
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

* [Falsehoods programmers believe about time](./falsehoods.md) — eleven wrong assumptions with the largest bug-surface, with the Tempo idiom for each.

* [Set operations](./set-operations.md) — union, intersection, difference, and the operators that keep members.

* [Enumeration semantics](./enumeration-semantics.md) — what a walk of a Tempo value or an interval set yields.
