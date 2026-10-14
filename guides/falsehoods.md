# Falsehoods Programmers Believe About Time

Every programmer who has worked seriously with calendars has their own version of this list. The falsehoods below are the ones with the largest bug-surface — the ones that are true for 95% of inputs, accepted by code review, and then silently wrong in production. Each one is followed by the Tempo idiom that makes the correct behaviour automatic.

The final section says where Tempo stops, and what to use instead.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` to the caller's namespace; no helper functions leak in.

---

## 1. "Every day has 24 hours"

Daylight-saving transitions add or remove an hour. A day on which the clocks go forward is 23 hours long; a day on which they go back is 25. Code that multiplies days by 86 400 seconds and adds the result to a zoned timestamp gets the wrong answer for roughly two days per year per zone.

**Traditional approach — silent wrong answer:**

<!-- guides:skip -->
```elixir
# 86_400 seconds later is NOT necessarily "the same time tomorrow"
DateTime.add(datetime, 86_400, :second)
```

**Tempo — the duration is computed correctly:**

```elixir
iex> Tempo.duration(~o"2024-03-09T12/2024-03-10T12[America/New_York]")
~o"PT23H"

iex> Tempo.duration(~o"2024-03-10[America/New_York]")
~o"P1D"

iex> Enum.count(~o"2024-03-10[America/New_York]")
23
```

> *"Noon to noon across the spring change in New York is **twenty-three hours**. The day itself is still **one day**, and it has twenty-three hours to walk."*

Tempo measures hours as elapsed time and days on the calendar, and shifting keeps the same two rules. A day later is the same time tomorrow; twenty-four hours later is the reading the clock shows when twenty-four hours have passed:

```elixir
iex> Tempo.shift(~o"2024-03-09T12[America/New_York]", day: 1)
{:ok, ~o"2024Y3M10DT12H[America/New_York]"}

iex> Tempo.shift(~o"2024-03-09T12[America/New_York]", hour: 24)
{:ok, ~o"2024Y3M10DT13H[America/New_York]"}
```

---

## 2. "Every wall-clock time exists once and only once"

Two ways this is wrong:

* **Spring-forward gaps**: the clock jumps from 01:59 to 03:00, so 02:30 never appears.
* **Fall-back duplicates**: the clock rolls back from 02:00 to 01:00, so 01:30 appears twice.

Libraries that read `"02:30 America/New_York"` on a spring-forward date and return *something* have hidden a bug behind convenience.

**Tempo — a reading the clock skips is no value:**

```elixir
iex> {:error, error} = Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")
iex> Exception.message(error)
"~o\"2024Y3M10DT2H30M0S[America/New_York]\" is a reading the clock of \"America/New_York\" skips"
```

The error surfaces at the boundary — where the value is read or built — not hours later in a downstream calculation. `Tempo.new/1` and `Tempo.in_zone/2` return the same `Tempo.ZoneError`.

An expression that names several times names the ones the clock shows. Half past two on the 9th and the 10th of March is, in New York, one time:

```elixir
iex> Enum.to_list(~o"2024Y3M{9,10}DT2H30M[America/New_York]")
[~o"2024Y3M9DT2H30M[America/New_York]"]
```

---

## 3. "01:30 during a fall-back refers to a single instant"

The fall-back duplicate is the mirror of the gap. When New York sets the clocks back, 01:30 occurs twice: once in daylight time and, an hour later, once in standard time. A bare `01:30` is ambiguous.

**Tempo — the time shift names which instant you mean:**

```elixir
iex> first = ~o"2024-11-03T01:30:00-04:00[America/New_York]"
iex> second = ~o"2024-11-03T01:30:00-05:00[America/New_York]"
iex> Tempo.duration(first, second)
{:ok, ~o"PT3600S"}

iex> Tempo.relation(first, second)
:precedes
```

> *"Half past one at four hours behind UTC **precedes** half past one at five hours behind, by **an hour**."*

`-04:00` names the daylight-time instant; `-05:00` the standard-time one. Tempo holds the reading, the shift and the zone, so the choice is carried through every later operation. With no shift written, the reading is the first of the two — the rule is fixed and documented, so that the same text is always the same instant:

```elixir
iex> Tempo.relation(~o"2024-11-03T01:30:00[America/New_York]", first)
:equals
```

---

## 4. "Storing a future event as UTC is safe"

For past events this is fine. For future events it is wrong: DST rules change. When a government changes its zone rules after you stored a UTC instant, the UTC number is now stale — and you've lost the wall-clock information needed to recompute it.

**Tempo — store what the user said; project UTC on demand:**

```elixir
iex> event = ~o"2030-03-01T08:00:00[Europe/Paris]"
iex> {Tempo.hour(event), Tempo.zoned?(event)}
{8, true}

iex> Tempo.to_iso8601(event)
{:ok, "2030Y3M1DT8H0M0S[Europe/Paris]"}
```

No UTC is stored on the value. Comparison and conversion consult the configured time zone database at call time, so re-evaluating after a data update reflects any rule change. Serialise with `Tempo.to_iso8601/1`; the round-trip is faithful.

---

## 5. "A minute has 60 seconds"

Occasionally it has 61. The IERS has inserted 27 leap seconds since 1972; the most recent was on 31 December 2016 at 23:59:60 UTC. Code that counts across that boundary and assumes 60-second minutes is off by one.

**Tempo — a leap second is a fact about a span:**

```elixir
iex> new_year = ~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z"
iex> Tempo.Interval.spans_leap_second?(new_year)
true

iex> Tempo.duration(new_year)
~o"PT120S"

iex> Tempo.duration(new_year, leap_seconds: true)
~o"PT121S"

iex> Tempo.LeapSeconds.spanned(~o"2015/2017")
{:ok, [{2015, 6, 30}, {2016, 12, 31}]}
```

> *"The two minutes around New Year 2017 **span a leap second**: a hundred and twenty seconds on the clock, a hundred and twenty-one elapsed."*

`duration/1` returns the length on the clock, as POSIX time counts it. `duration/2` with `leap_seconds: true` returns the physical elapsed time. Both are correct for their purpose, and `spans_leap_second?/1` lets downstream code branch explicitly rather than drop the second. A second numbered 60 is itself no value, as it is none in Elixir's own types.

---

## 6. "1582-01-01 means the same thing everywhere"

The Gregorian calendar was adopted at different times in different countries. In England, the Julian calendar was used until 1752. In France, the switch happened in 1582. A date written as `1582-01-01` in a French historical record and the same date in an English record are different days — ten days apart.

**Tempo — the calendar is part of the value:**

```elixir
iex> julian = ~o"1582-01-01[u-ca=julian]"
iex> gregorian = ~o"1582-01-01"
iex> Tempo.overlaps?(julian, gregorian)
false

iex> Tempo.to_calendar(julian, Calendrical.Gregorian)
{:ok, ~o"1582Y1M11D[u-ca=gregorian]"}
```

> *"New Year's Day 1582 on the Julian calendar **does not overlap** New Year's Day on the Gregorian: it is the Gregorian **11th of January**."*

`[u-ca=julian]` is an RFC 9557 suffix. `Tempo.overlaps?/2` places both values on the one time line before comparing them.

---

## 7. "There is no year 0"

In the proleptic Gregorian calendar used by ISO 8601 and most programming environments, year 0 exists and is 1 BCE. Year -1 is 2 BCE. Code that converts a signed year to a historical "n BCE" label by negating it is off by one for every year before 1.

**Tempo — year 0 is a value:**

```elixir
iex> Tempo.from_iso8601("0000-01-01")
{:ok, ~o"0Y1M1D"}

iex> Tempo.from_iso8601("-0001-01-01")
{:ok, ~o"-1Y1M1D"}

iex> Tempo.duration(~o"-0001-12-31", ~o"0000-01-01")
{:ok, ~o"P1D"}
```

`~o"0Y1M1D"` is in 1 BCE and `~o"-1Y1M1D"` in 2 BCE, and the years run on without a break: the last day of year -1 is the day before the first of year 0.

---

## 8. "February always has 28 or 29 days"

In the Hebrew calendar the second month, Cheshvan, has 29 days in some years and 30 in others. So a thirtieth of the second month is no date in the Gregorian calendar and a date in some Hebrew years. Month lengths are the calendar's and cannot be hard-coded.

**Tempo — a date is checked against its own calendar:**

```elixir
iex> {:error, error} = Tempo.from_iso8601("2024-02-30")
iex> Exception.message(error)
"~o\"2024Y2M30D\" is no date or time: its day is 30, a day the calendar does not have in that month"

iex> Tempo.from_iso8601("5785-02-30[u-ca=hebrew]")
{:ok, ~o"5785Y2M30D[u-ca=hebrew]"}

iex> {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("5784-02-30[u-ca=hebrew]")

iex> {Tempo.days_in_month(~o"5785-02[u-ca=hebrew]"), Tempo.days_in_month(~o"5784-02[u-ca=hebrew]")}
{{:ok, 30}, {:ok, 29}}
```

The calendar supplies the length of each of its months. Tempo asks it rather than hard-coding 28 and 29.

---

## 9. "Every location follows a 24-hour offset from UTC"

Samoa skipped 30 December 2011 entirely when it moved across the International Date Line, from UTC−11 to UTC+13, to align its calendar with Australia and New Zealand. The day after Thursday 29 December was Saturday 31 December: the calendar day between them never existed there.

**Tempo — the missing day is an error, not a silent correction:**

```elixir
iex> {:error, error} = Tempo.from_iso8601("2011-12-30[Pacific/Apia]")
iex> Exception.message(error)
"~o\"2011Y12M30D[Pacific/Apia]\" is a reading the clock of \"Pacific/Apia\" skips"

iex> {:error, %Tempo.ZoneError{reason: :gap}} = Tempo.from_iso8601("2011-12-30T12:00:00[Pacific/Apia]")
```

The day, and any hour or timestamp on it, is refused in that zone. The same check that catches a spring-forward hour (falsehood 2) catches this one: the zone's clock never showed the reading.

**Tempo — the days on either side are neighbours:**

```elixir
iex> thursday = ~o"2011-12-29[Pacific/Apia]"
iex> saturday = ~o"2011-12-31[Pacific/Apia]"
iex> Tempo.shift(thursday, day: 1) == {:ok, saturday}
true

iex> Tempo.shift(saturday, day: -1) == {:ok, thursday}
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

`2026-04-15T10:30+05:30` and `2026-04-15T10:30+09:00` show the same wall-clock reading and are three and a half hours apart. "Same time, different zone" is not "same instant."

**Tempo — two zoned times are related as the instants they are:**

```elixir
iex> india = ~o"2026-04-15T10:30:00+05:30"
iex> japan = ~o"2026-04-15T10:30:00+09:00"
iex> Tempo.relation(india, japan)
:preceded_by

iex> Tempo.before?(japan, india)
true
```

> *"Half past ten in Japan is **before** half past ten in India."*

**Corollary — a value with *no* zone has no instant to compare at all.** If two zoned readings in different zones are different instants, then a *floating* reading — one with no zone and no shift — has no position on the universal time line, and there is no fact of the matter about how it orders against a zoned value. Tempo declines the comparison rather than reading the floating side as UTC:

```elixir
iex> {:error, %Tempo.FrameError{reason: :floating_and_zoned}} = Tempo.relation(~o"2026-04-15T10:30:00", ~o"2026-04-15T10:30:00[Europe/Paris]")
```

Place the floating value in a zone first with `Tempo.in_zone/2`, or write a shift (`Z`, `+HH:MM`), and the comparison is well-defined. See the [Scheduling](./scheduling.md) guide's "Floating vs zoned values" section for the full treatment.

---

## 11. "A duration is a number of seconds"

`DateTime.diff/3` answers in seconds, and so do most date libraries. But a month has no fixed number of seconds, and neither does a day — the day a clock change shortens is 82 800 seconds long and still one day — while a count of whole seconds drops the fraction of a second a timestamp was written with.

**Tempo — a duration is counted in the unit its ends are written in:**

```elixir
iex> Tempo.duration(~o"2026-09-28", ~o"2026-11-03")
{:ok, ~o"P36D"}

iex> Tempo.duration(~o"2026-01", ~o"2026-04")
{:ok, ~o"P3M"}

iex> Tempo.duration(~o"2024-06-15T12:00:00.1", ~o"2024-06-15T12:00:00.9")
{:ok, ~o"PT0.8S"}
```

Years, months, weeks and days are counted on the calendar, and hours, minutes and seconds are elapsed time. A fraction of a second keeps the precision it was written with — the digit count is the resolution, so `.1` and `.2` are adjacent tenths of a second:

```elixir
iex> Tempo.relation(~o"2024-06-15T12:00:00.1", ~o"2024-06-15T12:00:00.2")
:meets
```

---

## Where Tempo won't help

The guide above shows Tempo making correct behaviour automatic. Here is where it stops, with a recommendation.

### Monotonic time

Tempo has no abstraction over `System.monotonic_time/0`. Elapsed time in benchmarks, timeouts and retry loops should be measured with `System.monotonic_time(:millisecond)` directly: the wall clock can be set back under a running program, and no interval on it is a safe stopwatch.

### The current time

Tempo reads the clock in four functions only — `Tempo.utc_now/0`, `Tempo.now/1`, `Tempo.utc_today/0` and `Tempo.today/1` — and through the `Tempo.Clock` behaviour, so a test pins the moment its own process reads. Everything else in the library is a function of its arguments.

```elixir
iex> Tempo.Clock.Test.put(~U[2026-06-15 23:30:00Z])
iex> Tempo.Clock.Test.advance(3600)
iex> Tempo.utc_today()
~o"2026Y6M16D"
```

> *"Pin the clock at half past eleven on the fifteenth of June; an hour on, **today** is the sixteenth."*

---

## Related reading

* [Scheduling](./scheduling.md) — how Tempo handles future dates, DST, floating vs zoned events, and bounded recurrence.
* [Set operations](./set-operations.md) — union, intersection and free-busy queries.
* [The cookbook](./cookbook.md) — recipe-format queries for the common patterns referenced here.
