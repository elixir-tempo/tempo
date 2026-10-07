# Falsehoods Programmers Believe About Time

Every programmer who has worked seriously with calendars has their own version of this list. The falsehoods below are the ones with the largest bug-surface — the ones that are true for 95% of inputs, accepted by code review, and then silently wrong in production. Each one is followed by the Tempo idiom that makes the correct behaviour automatic.

The final section is honest about where Tempo stops, and says what to use instead.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

---

## 1. "Every day has 24 hours"

Daylight-saving transitions add or remove an hour. A day that starts a DST spring-forward is 23 hours long; a day that ends a DST fall-back is 25 hours. Code that multiplies days by 86 400 seconds and adds the result to a zoned timestamp gets the wrong answer for roughly two days per year per zone.

**Traditional approach — silent wrong answer:**

```elixir
# 86_400 seconds later is NOT necessarily "the same time tomorrow"
DateTime.add(datetime, 86_400, :second)
```

**Tempo — the duration is computed correctly:**

```elixir
iex> iv = Tempo.Interval.new!(
...>   from: Tempo.from_iso8601!("2024-03-09T12[America/New_York]"),
...>   to:   Tempo.from_iso8601!("2024-03-10T12[America/New_York]")
...> )
iex> Tempo.Interval.duration(iv)
~o"PT23H"
```

Spring forward in New York removes one hour from that calendar day — Tempo measures hours as elapsed time, so noon to noon is 23 of them, not 24. The calendar day itself is still one day: measured in days, `2024-03-10` is `~o"P1D"`.

Shifting keeps the same two rules. A day later is the same time tomorrow; twenty-four hours later is the reading the clock shows when twenty-four hours have passed:

```elixir
iex> Tempo.shift(~o"2024-03-09T12[America/New_York]", day: 1)
~o"2024Y3M10DT12H[America/New_York]"

iex> Tempo.shift(~o"2024-03-09T12[America/New_York]", hour: 24)
~o"2024Y3M10DT13H[America/New_York]"
```

---

## 2. "Every wall-clock time exists once and only once"

Two ways this is wrong:

* **Spring-forward gaps**: the clock jumps from 01:59 to 03:00, so 02:30 never appears.
* **Fall-back duplicates**: the clock rolls back from 02:00 to 01:00, so 01:30 appears twice.

Libraries that parse `"02:30 America/New_York"` on a spring-forward date and silently return *something* have hidden a bug behind convenience.

**Tempo — invalid wall times are rejected at parse time:**

```elixir
iex> {:error, error} = Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")
iex> Exception.message(error)
"Wall time 2024-03-10T02:30:00 does not exist in \"America/New_York\" (it falls inside a daylight-saving or zone-transition gap)."
```

The error surfaces at the boundary — parse time — not hours later in a downstream calculation. A set that names such a time is refused with it: `2024Y3M{9,10}DT2H30M[America/New_York]` names 02:30 on the 10th, and is the same error.

---

## 3. "01:30 during a fall-back refers to a single instant"

The fall-back duplicate is the mirror of the gap. When New York sets the clocks back, 01:30 EST occurs twice: once during EDT and once during EST. A bare `01:30` is ambiguous.

**Tempo — the UTC offset names which instant you mean:**

```elixir
iex> pre  = Tempo.from_iso8601!("2024-11-03T01:30:00-04:00[America/New_York]")
iex> post = Tempo.from_iso8601!("2024-11-03T01:30:00-05:00[America/New_York]")
iex> Tempo.duration(pre, post)
{:ok, ~o"PT3600S"}
```

`-04:00` names the EDT instant; `-05:00` names the EST instant. They are 3 600 seconds apart. Tempo stores both the wall time and the offset, so the disambiguation is carried through every subsequent operation. Supplying neither offset makes the parse ambiguous — Tempo surfaces the ambiguity rather than guessing.

---

## 4. "Storing a future event as UTC is safe"

For past events this is fine. For future events it is wrong: DST rules change. When a government changes its zone rules after you stored a UTC instant, the UTC number is now stale — and you've lost the wall-clock information needed to recompute it.

**Tempo — store what the user said; project UTC on demand:**

```elixir
iex> event = Tempo.from_iso8601!("2030-03-01T08:00:00[Europe/Paris]")
iex> event.extended.zone_id
"Europe/Paris"
```

No UTC is stored on the struct. Comparison and conversion consult the configured time zone database at call time, so re-evaluating after a data update automatically reflects any rule change. Serialise with `Tempo.to_iso8601/1`; the round-trip is faithful.

```elixir
iex> Tempo.to_iso8601(event)
{:ok, "2030Y3M1DT8H0M0S[Europe/Paris]"}
```

---

## 5. "A minute has 60 seconds"

Occasionally it has 61. The IERS has inserted 27 positive leap seconds since 1972; the most recent was on 31 December 2016 at 23:59:60 UTC. Code that counts across that boundary and assumes 60-second minutes is off by one.

**Tempo — leap seconds are first-class interval metadata:**

```elixir
iex> iv = ~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z"
iex> Tempo.Interval.spans_leap_second?(iv)
true
iex> Tempo.Interval.duration(iv)
~o"PT120S"
iex> Tempo.Interval.duration(iv, leap_seconds: true)
~o"PT121S"
```

`duration/1` returns the POSIX elapsed time (120 s). `duration/2` with `leap_seconds: true` returns the physical elapsed time (121 s). Both are correct for their purpose; Tempo exposes both. The `spans_leap_second?/1` predicate lets downstream code branch explicitly rather than silently dropping the second.

---

## 6. "1582-01-01 means the same thing everywhere"

The Gregorian calendar was adopted at different times in different countries. In England, the Julian calendar was used until 1752. In France, the switch happened in 1582. A date written as `1582-01-01` in a French historical record and the same date in an English record refer to different days on the astronomical time line — they are ten days apart.

**Tempo — the calendar is part of the value:**

```elixir
iex> julian_1582_jan1     = Tempo.from_iso8601!("1582-01-01[u-ca=julian]")
iex> gregorian_1582_jan1  = Tempo.from_iso8601!("1582-01-01")
iex> Tempo.overlaps?(julian_1582_jan1, gregorian_1582_jan1)
false
```

`[u-ca=julian]` is an IXDTF annotation; `Tempo.overlaps?/2` converts both values to the same astronomical reference frame before comparing. The two `1582-01-01` dates do not overlap.

---

## 7. "There is no year 0"

In the proleptic Gregorian calendar used by ISO 8601 and most programming environments, year 0 exists and represents 1 BCE. Year -1 is 2 BCE. Code that converts a signed year to a historical "n BCE" label by negating it is off by one for every negative year.

**Tempo — year 0 is a valid, parseable value:**

```elixir
iex> Tempo.from_iso8601("0000-01-01")
{:ok, ~o"0Y1M1D"}
iex> Tempo.from_iso8601("-0001-01-01")
{:ok, ~o"-1Y1M1D"}
```

`~o"0Y1M1D"` is 1 BCE; `~o"-1Y1M1D"` is 2 BCE. Label conversion requires `year_value + 1` when `year_value <= 0` — Tempo's calendar-aware display helpers do this correctly.

---

## 8. "February always has 28 or 29 days"

In the Hebrew calendar, the month Cheshvan (month 2) has 29 days in a regular year and 30 days in a complete year. So February-30 is invalid in the Gregorian calendar but valid for some Hebrew years. Month-length rules are calendar-specific and cannot be hard-coded.

**Tempo — month lengths are validated per calendar:**

```elixir
iex> {:error, error} = Tempo.from_iso8601("2024-02-30")
iex> Exception.message(error)
"30 is not valid for a day of 2024-02. The valid values are 1..29"

iex> Tempo.from_iso8601("5785-02-30[u-ca=hebrew]")
{:ok, ~o"5785Y2M30D[u-ca=hebrew]"}

iex> {:error, error} = Tempo.from_iso8601("5784-02-30[u-ca=hebrew]")
iex> Exception.message(error)
"30 is not valid for a day of 5784-02 in Calendrical.Hebrew. The valid values are 1..29"
```

The calendar module supplies the correct `days_in_month/2` for each calendar system. Tempo delegates to it rather than hard-coding 28/29.

---

## 9. "Every location follows a 24-hour offset from UTC"

Samoa skipped 30 December 2011 entirely when it moved across the International Date Line, from UTC−11 to UTC+13, to align its calendar with Australia and New Zealand. The day after Thursday 29 December was Saturday 31 December: the calendar day between them never existed for that territory.

**Tempo — the missing day is an error, not a silent correction:**

```elixir
iex> {:error, error} = Tempo.from_iso8601("2011-12-30[Pacific/Apia]")
iex> Exception.message(error)
"Wall time 2011-12-30 does not exist in \"Pacific/Apia\" (it falls inside a daylight-saving or zone-transition gap)."

iex> {:error, %Tempo.ZoneGapError{}} = Tempo.from_iso8601("2011-12-30T12:00:00[Pacific/Apia]")
```

The day, and any hour or timestamp on it, is rejected in that zone. The same mechanism that catches DST gaps (falsehood #2) catches this one — the wall time is invalid in the IANA data and Tempo surfaces the error.

**Tempo — the days on either side are neighbours:**

```elixir
iex> thursday = ~o"2011-12-29[Pacific/Apia]"
iex> saturday = ~o"2011-12-31[Pacific/Apia]"

iex> Tempo.shift(thursday, day: 1) == saturday
true

iex> Tempo.relation(thursday, saturday)
:meets

iex> Enum.count(~o"2011-12[Pacific/Apia]")
30
```

> *"The day **after** Thursday the 29th is Saturday the 31st, and the one **meets** the other. December 2011 had **thirty days** in Samoa."*

Nothing gives the day that is not there: a step that lands on it is the day after (the day before, where the step runs back), and a walk, a recurrence and a selection pass over it.

---

## 10. "Two timestamps represent the same instant if they show the same time"

`2026-04-15T10:30+05:30` and `2026-04-15T10:30+09:00` show the same wall-clock reading but are 3.5 hours apart. "Same time, different zone" is not "same instant." The Allen relation makes the structure explicit.

**Tempo — comparing two zoned times gives the correct Allen relation:**

```elixir
iex> a = Tempo.from_iso8601!("2026-04-15T10:30:00+05:30")
iex> b = Tempo.from_iso8601!("2026-04-15T10:30:00+09:00")
iex> Tempo.relation(a, b)
:preceded_by
```

`b` is 3.5 hours earlier in UTC — it precedes `a`. The comparison goes through UTC projection so the Allen relation reflects the real ordering on the time line, not the face value of the clock reading.

**Corollary — a value with *no* zone has no instant to compare at all.** If two zoned readings in different zones are different instants, then a *floating* reading — one that fixes no zone or offset — has no position on the universal time line, and there is no fact of the matter about how it orders against a zoned value. Tempo declines the comparison rather than silently reading the floating side as UTC:

```elixir
iex> {:error, %Tempo.FloatingTempoError{} = refused} =
...>   Tempo.relation(~o"2026-04-15T10:30:00", ~o"2026-04-15T10:30:00[Europe/Paris]")
iex> refused.operation
:compare
```

Place the floating value in a zone first with `Tempo.in_zone/2`, or write an offset (`Z`/`+HH:MM`), and the comparison becomes well-defined. See the [Scheduling](./scheduling.md) guide's "Floating vs zoned values" section for the full treatment.

---

## 11. "A duration is a number of seconds"

`DateTime.diff/3` answers in seconds, and so do most date libraries. But a month has no fixed number of seconds, and neither does a day — the day a clock change shortens is 82 800 seconds long and still one day — while a count of whole seconds drops the fraction of a second a timestamp was written with.

**Tempo — a duration is counted in the unit its endpoints are written in:**

```elixir
iex> Tempo.duration(~o"2026-09-28", ~o"2026-11-03")
{:ok, ~o"P36D"}

iex> Tempo.duration(~o"2026-01", ~o"2026-04")
{:ok, ~o"P3M"}

iex> Tempo.duration(~o"2024-06-15T12:00:00.1", ~o"2024-06-15T12:00:00.9")
{:ok, ~o"PT0.8S"}
```

Years, months, weeks and days are counted on the calendar, and hours, minutes and seconds are elapsed time. A fraction of a second keeps the precision it was written with — the digit count is the resolution, so `.1` and `.2` are adjacent tenth-of-a-second spans:

```elixir
iex> Tempo.relation(~o"2024-06-15T12:00:00.1", ~o"2024-06-15T12:00:00.2")
:meets
```

---

## Where Tempo won't help (yet)

The guide above shows Tempo making correct behaviour automatic. Here is where it stops, with a recommendation. (Three earlier entries have since been resolved: sub-second comparison and set operations, sub-second durations — see falsehood 11 — and clock mocking, which landed as the `Tempo.Clock` behaviour with a `Tempo.Clock.Test` stub for deterministic "now" in tests.)

### Monotonic time

Tempo has no abstraction over `System.monotonic_time/0`. Elapsed-duration measurements in benchmarks, timeouts, or retry loops should use `System.monotonic_time(:millisecond)` directly — using wall-clock intervals for that purpose is wrong in any library. **Recommendation**: document this boundary clearly (a `Time.Monotonic` note in the README is enough) so users know when to step outside Tempo. This is not a library gap so much as a boundary that should be named.

---

## Related reading

* [Scheduling](./scheduling.md) — how Tempo handles future dates, DST, floating vs zoned events, and bounded recurrence.
* [Set operations](./set-operations.md) — union, intersection, free/busy queries, and the sweep-line algorithm.
* [The cookbook](./cookbook.md) — recipe-format queries for the common patterns referenced here.
