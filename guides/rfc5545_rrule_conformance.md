# RFC 5545 RRULE Conformance

Tempo reads the recurrence rule of [RFC 5545 §3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10) into a recurrence — the same `%Tempo{}` an ISO 8601-2 repeating interval reads to — which is walked, listed within a window, and combined with the rest of Tempo's set algebra. This guide says precisely what is read, how each part is taken, and what is not.

`Tempo.RRule.parse/2` is Tempo's own reader of the rule's text. For whole iCalendar files, with their events, `RDATE`s and `EXDATE`s, Tempo hands the file to the [`ical`](https://hex.pm/packages/ical) library and gives what it finds to the same engine, so a rule means the same whether it came from a hand-written string or a calendar feed.

## Setup — required for every example

```elixir
import Tempo.Sigils
```

## What Tempo does with a rule

* **Reads** it with `Tempo.RRule.parse/2`, given its `DTSTART` as `:from`.

* **Walks** it with `Enum` and `Stream`, lazily, whether or not it has an end.

* **Lists** its occurrences with `Tempo.to_interval/2`, bounded by its `COUNT` or `UNTIL`, or by a `:within` window.

* **Combines** them with every set operation and predicate.

* **Writes** it back with `Tempo.RRule.to_string/1`, and as ISO 8601-2 with `Tempo.to_iso8601/1`.

```elixir
iex> rule = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=-1FR;COUNT=3", from: ~o"2026-01-01")
iex> Enum.map(rule, &Tempo.Interval.from/1)
[~o"2026Y1M30D", ~o"2026Y2M27D", ~o"2026Y3M27D"]

iex> Tempo.RRule.to_string(rule)
{:ok, "FREQ=MONTHLY;COUNT=3;BYDAY=-1FR"}

iex> Tempo.to_iso8601(rule)
{:ok, "R3/2026Y1M1D/P1M/FL5K-1IN"}
```

> *"The **last Friday** of each month, **three** times."*

## Part by part

| Part | Read | Notes |
|---|:---:|---|
| `FREQ` | ✓ | `SECONDLY`, `MINUTELY`, `HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY`. |
| `INTERVAL` | ✓ | A positive whole number; 1 where none is written. |
| `COUNT` | ✓ | Not beside `UNTIL`. Counts from the rule's start. |
| `UNTIL` | ✓ | A date or a date and time; the last occurrence may begin on it. |
| `BYSECOND`, `BYMINUTE`, `BYHOUR` | ✓ | |
| `BYDAY` | ✓ | Weekdays, numbered weekdays (`2MO`, `-1FR`, `1MO,3MO`), and numbered weekdays of several days (`2MO,2WE`, `1MO,-1FR`), read as a set of selections, `L{1K2I,3K2I}N`, one for each weekday. |
| `BYMONTHDAY` | ✓ | From 1, or from -1 back from the end of the month. |
| `BYYEARDAY` | ✓ | From 1, or from -1 back from the end of the year. |
| `BYWEEKNO` | ✓ | ISO 8601 weeks; from -1 back from the year's last. |
| `BYMONTH` | ✓ | |
| `BYSETPOS` | ✓ | Applied last, to what the other parts select in each period. |
| `WKST` | any day | A week begins on Monday unless the rule says otherwise. Where the day is significant (a weekly rule of every second week or more that names weekdays, and a yearly rule that names weeks of the year) the recurrence is of the weeks that begin on it, written `[u-fw=sun]`; where it is not, it is read and not kept. |

### Parts coarser and finer than the frequency

RFC 5545 has each `BY…` part either add occurrences within a period of the frequency or keep some of the periods, by whether the part is finer or coarser than the frequency. Tempo's engine does the same from one rule: the parts are selected in each period, and a period that lies within what a coarser part names is kept whole.

```elixir
iex> first = fn rule, from, count ->
...>   rule |> Tempo.RRule.parse!(from: from) |> Enum.take(count) |> Enum.map(&Tempo.Interval.from/1)
...> end
iex> first.("FREQ=YEARLY;BYMONTH=3,6", ~o"2026-01-15", 3)
[~o"2026Y3M15D", ~o"2026Y6M15D", ~o"2027Y3M15D"]

iex> first.("FREQ=DAILY;BYMONTH=1", ~o"2026-12-30", 3)
[~o"2027Y1M1D", ~o"2027Y1M2D", ~o"2027Y1M3D"]

iex> first.("FREQ=DAILY;BYDAY=MO", ~o"2026-01-01", 3)
[~o"2026Y1M5D", ~o"2026Y1M12D", ~o"2026Y1M19D"]
```

> *"Yearly in **March and June**, on the start's 15th. Daily in **January**: every day of it. Daily on **Mondays**."*

Parts that name a day hold at once, so the days selected are those every one of them names:

```elixir
iex> first.("FREQ=YEARLY;BYMONTH=3,4;BYYEARDAY=80,100", ~o"2026-01-01", 2)
[~o"2026Y3M21D", ~o"2026Y4M10D"]

iex> first.("FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR", ~o"1998-02-13", 3)
[~o"1998Y2M13D", ~o"1998Y3M13D", ~o"1998Y11M13D"]
```

> *"The 80th and 100th days of the year that are in **March or April**. A **13th** that is a **Friday**."*

A day of the month in a yearly rule with no `BYMONTH` is that day of every month, the part adding to the year as RFC 5545's table has it:

```elixir
iex> first.("FREQ=YEARLY;BYMONTHDAY=15", ~o"2026-03-10", 3)
[~o"2026Y3M15D", ~o"2026Y4M15D", ~o"2026Y5M15D"]
```

### What a rule takes from DTSTART

A rule takes from its start what it does not say: a weekly rule with no `BYDAY` its weekday, a monthly rule with neither `BYMONTHDAY` nor `BYDAY` its day of the month, a yearly rule its month and day, a rule that names a week and no day its day of the week. The recurrence read states each, as ISO 8601-2's Annex C.4 has a conversion do, so `Tempo.RRule.to_string/1` writes `FREQ=MONTHLY` from the 31st back as `FREQ=MONTHLY;BYMONTHDAY=31`, which RFC 5545 reads as the rule it was.

```elixir
iex> Tempo.RRule.parse!("FREQ=YEARLY;BYWEEKNO=20", from: ~o"2026-05-11") |> Enum.take(2)
[~o"2026Y20W1K/20W1K", ~o"2027Y20W1K/20W1K"]
```

> *"The **Monday of week 20**, the start being a Monday."*

A time of day in the start is kept by every occurrence. A rule with no start (`:from` not given) is read, written and listed within a window, taking nothing from a start: `FREQ=YEARLY;BYWEEKNO=24` is week 24 of each year.

### How long an occurrence is

An occurrence is as long as its start is precise: a day for a date, which is the length RFC 5545 gives an event with no `DTEND`, and an hour for a time written to the hour. An event's `DTEND` or `DURATION` is given as `:duration` and sets the length otherwise.

```elixir
iex> Tempo.RRule.parse!("FREQ=DAILY", from: ~o"2026-06-01") |> Enum.take(1)
[~o"2026Y6M1D/2026Y6M1D"]

iex> Tempo.RRule.parse!("FREQ=DAILY", from: ~o"2026-06-01T10") |> Enum.take(1)
[~o"2026Y6M1DT10H/T11H"]

iex> Tempo.RRule.parse!("FREQ=DAILY", from: ~o"2026-06-01T10:00", duration: ~o"PT45M") |> Enum.take(1)
[~o"2026Y6M1DT10H0M/T45M"]
```

### Dates that do not exist

RFC 5545 §3.3.10 has a rule's instances on a date that does not exist ignored, and not counted. A day a month lacks is passed over, and so is a time of day a zone's clock skips, and a day a zone left out:

```elixir
iex> first.("FREQ=MONTHLY", ~o"2026-01-31", 3)
[~o"2026Y1M31D", ~o"2026Y3M31D", ~o"2026Y5M31D"]

iex> first.("FREQ=DAILY;BYHOUR=2;BYMINUTE=30", ~o"2024-03-09T00:00[America/New_York]", 2)
[~o"2024Y3M9DT2H30M[America/New_York]", ~o"2024Y3M11DT2H30M[America/New_York]"]

iex> first.("FREQ=MONTHLY;BYMONTHDAY=30", ~o"2011-11-30[Pacific/Apia]", 2)
[~o"2011Y11M30D[Pacific/Apia]", ~o"2012Y1M30D[Pacific/Apia]"]
```

> *"Monthly on the **31st** passes February over. Half past two in New York has no occurrence on the night the clocks go from two to three. The **30th of December 2011** never came in Samoa."*

## A rule with no end needs a bound to be listed

A rule with no `COUNT` and no `UNTIL` has no last occurrence. It is walked as far as it is taken, and listed within a window:

```elixir
iex> daily = Tempo.RRule.parse!("FREQ=DAILY", from: ~o"2026-06-01")
iex> {:error, %Tempo.ConversionError{reason: :unbounded}} = Tempo.to_interval(daily)
iex> {:ok, june} = Tempo.to_interval(daily, within: ~o"2026-06")
iex> Tempo.IntervalSet.count(june)
30
```

A window keeps the occurrences that overlap it, and never changes which they are: a `COUNT` counts from the rule's start, so the first three days of 2000 are none of them in 2026.

```elixir
iex> long_ago = Tempo.RRule.parse!("FREQ=DAILY;COUNT=3", from: ~o"2000-01-01")
iex> Tempo.to_interval(long_ago, within: ~o"2026")
{:ok, ~o"{}"}
```

A window with no zone, beside a rule in one, is read on the rule's clock: June is the June of the rule's zone.

Listing answers at most 10,000 occurrences at once (the application's `:max_values_at_once`), and more than that is a `Tempo.ConversionError` with the reason `:too_many_values`, rather than some of them.

## Rules far between, and rules with nothing

A rule whose parts leave its occurrences far apart for its frequency is not asked of every period. Where a period selects nothing, the walk goes on from the next value the parts name:

```elixir
iex> first.("FREQ=SECONDLY;BYHOUR=9", ~o"2026-01-01T00:00:00", 2)
[~o"2026Y1M1DT9H0M0S", ~o"2026Y1M1DT9H0M1S"]

iex> first.("FREQ=DAILY;BYMONTH=2;BYMONTHDAY=29;BYDAY=MO", ~o"2026-01-01", 2)
[~o"2044Y2M29D", ~o"2072Y2M29D"]
```

> *"Every second of the **nine o'clock hour**, reached without counting the seconds before it. Each **29th of February that is a Monday**, decades apart."*

A rule that has no occurrence has none, and its walk ends:

```elixir
iex> first.("FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=31;COUNT=2", ~o"2026-01-01", 2)
[]

iex> first.("FREQ=DAILY;INTERVAL=7;BYDAY=MO", ~o"2026-01-06", 1)
[]

iex> first.("FREQ=DAILY;BYSETPOS=2", ~o"2026-01-01", 1)
[]
```

> *"The **31st of April**. Every seventh day from a Tuesday that is a **Monday**. The **second** of a day's one."*

A rule is given up once it has selected nothing in a whole cycle of its calendar's years — four hundred in the Gregorian calendar, in which every date and weekday it could name comes round — or in a thousand years in a calendar with no such cycle. A rule that names times of day alone is given up after two years. A rule that repeats by an interval its cycle does not divide selects in other months in each cycle than in the last, and is walked until its periods come round:

```elixir
iex> first.("FREQ=MONTHLY;INTERVAL=7;BYMONTH=2;BYMONTHDAY=29;BYDAY=FR", ~o"2025-03-01", 1)
[~o"2504Y2M29D"]
```

> *"Every **seventh month**'s **Friday the 29th of February**: none for more than a cycle of four hundred years, and then one in **2504**."*

## Other calendars

RFC 5545 is Gregorian. A rule is counted in the calendar of its start, so the same text from a start in another calendar steps by that calendar's months and years:

```elixir
iex> passover = Tempo.RRule.parse!("FREQ=YEARLY;COUNT=3", from: ~o"5786-07-15[u-ca=hebrew]")
iex> Enum.map(passover, fn occurrence ->
...>   Tempo.to_calendar!(Tempo.Interval.from(occurrence), Calendrical.Gregorian)
...> end)
[~o"2026Y4M2D[u-ca=gregorian]", ~o"2027Y4M22D[u-ca=gregorian]", ~o"2028Y4M11D[u-ca=gregorian]"]
```

> *"**Every year** on the 15th of **Nisan**: the 2nd of April 2026, the 22nd of April 2027, the 11th of April 2028."*

A yearly rule takes the month of its start as the calendar names it, so it keeps to Nisan in a year that has a leap month before it, as 5787 has.

RFC 7529 names the calendar in the rule itself, with `RSCALE`, and says with `SKIP` what is taken for a day or a month a year lacks. The start is then given in any calendar and the occurrences are in the one named:

```elixir
iex> anniversary = Tempo.RRule.parse!("RSCALE=HEBREW;FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=8;SKIP=FORWARD;COUNT=3", from: ~o"2014-02-08")
iex> Tempo.to_iso8601!(anniversary)
"R3/5774Y6M8D/P1Y/FL5+m8D(forward)sN[u-ca=hebrew]"

iex> Enum.map(anniversary, fn occurrence ->
...>   Tempo.to_calendar!(Tempo.Interval.from(occurrence), Calendar.ISO)
...> end)
[~o"2014Y2M8D", ~o"2015Y2M27D", ~o"2016Y2M17D"]
```

> *"**Every year** on the **8th of Adar I**, the leap month, and in a year that has none on the **8th of Adar**, the month after: the 8th of February 2014, the 27th of February 2015, the 17th of February 2016."*

`Tempo.RRule.to_string/1` writes a recurrence of another calendar that counts in its months, its years or their days with `RSCALE`, by the name CLDR gives the calendar, and one that steps by weeks, days or the clock and selects by weekday and time of day as the plain rule it reads as in any calendar. A calendar with no such name (a fiscal calendar) is a `Tempo.ConversionError` (`{:no_rrule, {:calendar, module}}`).

## What is written, and what is refused

`Tempo.RRule.to_string/1` writes a recurrence only as a rule RFC 5545 reads as that recurrence. Each of these is a `Tempo.ConversionError` whose reason is `{:no_rrule, what}`:

```elixir
iex> refused = fn expression ->
...>   {:error, %Tempo.ConversionError{reason: {:no_rrule, what}}} = Tempo.RRule.to_string(expression)
...>   what
...> end
iex> refused.(~o"R/2026-01-01/P1W/FL15DN")
{:part_at, :day, :week}

iex> refused.(~o"R/2026-01-01/P1M/FL20WN")
{:part_at, :week, :month}

iex> refused.(~o"R/2026-01-31/P1M")
:month_end

iex> refused.(~o"R/2026-01-01/P1Y/FL(easter)eN")
{:part, :event}
```

* **A part RFC 5545 forbids the frequency**: a day of the month in a weekly rule, a day of the year in a daily, weekly or monthly one, a week of the year in any but a yearly one, a numbered weekday outside a monthly rule and a yearly rule with no `BYWEEKNO`, a `BYSETPOS` with no other part.

* **A recurrence with no rule that lands on a month's last day.** `R/2026-01-31/P1M` goes to the 28th of February where `FREQ=MONTHLY` from the 31st passes February over, so no one rule says it.

* **A part with no `BY…`**: an event the calendar computes, a traditional month, a selection within the window of another.

* **A cadence of several units**, and a recurrence of another calendar, as above.

An occurrence's length is no part of an RRULE and is not written; iCalendar carries it beside the rule.

## Not read

`Tempo.RRule.parse/2` returns `{:error, %ArgumentError{}}` that names what it does not read, rather than a rule that is nearly it:

* **`EXRULE`**, which RFC 5545 deprecated in favour of `EXDATE`.

`RDATE` and `EXDATE` are properties of an event rather than parts of a rule. `Tempo.ICal.parse/2` adds the one and removes the other, and `Tempo.RecurrenceSet` holds rules and dates together for the same purpose in code.

## Test coverage

`test/tempo/rrule_test.exs` holds the worked examples of RFC 5545 §3.8.5.3 — Thanksgiving, US election day, Friday the 13th, the last weekday of a month and the rest — each asserted as its occurrences, as the ISO 8601-2 text it writes, and as the rule read back from that text. `test/tempo/calendars_test.exs` holds events with `RDATE` and `EXDATE` read from iCalendar and JSCalendar.

## Acknowledgement

Tempo's reading of iCalendar files relies on the excellent [`ical`](https://hex.pm/packages/ical) library. The division of labour is clean: `ical` reads the wire format, and Tempo makes of what it finds something to walk, relate and combine.

## Related reading

* [One form for ISO 8601 and RRULE](./shared-ast-iso8601-and-rrule.md) — how a rule and an ISO 8601-2 recurrence are one value.

* [Scheduling](./scheduling.md) — bounding a recurrence, wall-clock time and zones.

* [iCalendar integration](./ical-integration.md) — `Tempo.ICal.parse/2` and what an event becomes.

* [Set operations](./set-operations.md) — what occurrences are combined with.

* [RFC 5545 §3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10) — the standard itself.
