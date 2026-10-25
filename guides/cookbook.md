# Tempo Cookbook

Task-oriented recipes for common time-and-calendar problems. Each recipe states the problem, shows the solution, and explains why it works. Copy, adapt, iterate.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` to the caller's namespace; no helper functions leak in. In `iex`, paste it once and every subsequent snippet runs against it.

---

## Contents

1. [Parsing and construction](#1-parsing-and-construction)
2. [Exploring a value](#2-exploring-a-value)
3. [Iteration](#3-iteration)
4. [Comparison and predicates](#4-comparison-and-predicates)
5. [Set operations](#5-set-operations)
6. [Selecting with `Tempo.select/3`](#6-selecting-with-tempo-select-3)
7. [Recurring events (RRULE)](#7-recurring-events-rrule)
8. [iCalendar import](#8-icalendar-import)
9. [Cross-calendar and cross-timezone](#9-cross-calendar-and-cross-timezone)
10. [Archaeological / approximate dates](#10-archaeological-approximate-dates)
11. [Chronological networks and dependency scheduling](#11-chronological-networks-and-dependency-scheduling)
12. [Real-world scenarios](#12-real-world-scenarios)
13. [Famous moments in time](#13-famous-moments-in-time)

---

## 1. Parsing and construction

### How do I parse an ISO 8601 date?

```elixir
iex> ~o"2026-06-15"
~o"2026Y6M15D"
```

A value is shown as the sigil that reads it, in ISO 8601-2's explicit form (`Y`, `M`, `D`, `H`, …), which tells months from minutes. `Tempo.from_iso8601/2` reads the same text at run time and returns `{:ok, value}` or an error.

### How do I convert an Elixir `Date`, `Time`, `NaiveDateTime`, or `DateTime` to a Tempo?

```elixir
iex> Tempo.from_elixir(~D[2026-06-15])
{:ok, ~o"2026Y6M15D"}

iex> Tempo.from_elixir(~U[2026-06-15 10:30:00Z])
{:ok, ~o"2026Y6M15DT10H30M0SZ"}

iex> Tempo.from_date(~D[2026-06-15])
~o"2026Y6M15D"
```

A `DateTime` is a second in its zone. `from_elixir/2` takes a `:resolution` option when the value is really coarser than its type, and the typed `from_date/1`, `from_time/1`, `from_naive_datetime/1` and `from_datetime/1` return the value itself. See [Converting to and from Elixir date/time types](interop.md).

### How do I express a duration?

```elixir
iex> ~o"P1Y6M"
~o"P1Y6M"

iex> Tempo.Duration.new(year: 1, month: 6)
{:ok, ~o"P1Y6M"}
```

### How do I express an interval between two dates?

```elixir
iex> ~o"2026-06-01/2026-06-30"
~o"2026Y6M1D/30D"
```

An interval written to a date runs through that date: this is the whole of June, the 1st through the 30th. One written to a time of day runs to that reading, so `~o"2026-06-15T09/2026-06-15T17"` ends as five o'clock begins. Either way the span itself is half-open, `[start, end)`, and adjacent intervals join with no gap and no overlap.

### How do I say "approximately 2022" or "uncertain 1984"?

```elixir
iex> Tempo.qualification(~o"2022~", :year)
:approximate

iex> Tempo.qualification(~o"1984?", :year)
:uncertain

iex> Tempo.qualification(~o"1984%", :year)
:both
```

`Tempo.qualification/2` reads a unit's mark back; the span stays the same calendar year.

---

### How do I mark just *part* of a date as uncertain?

The **position** of the `?` / `~` / `%` decides its scope, following ISO 8601-2 §8:

```elixir
# LEFT of a component → that component only (individual)
iex> some_june = Tempo.from_iso8601!("2004-?06-11")
iex> {Tempo.qualification(some_june, :year), Tempo.qualification(some_june, :month)}
{nil, :uncertain}

# RIGHT of a component → that component AND every coarser one (group)
iex> about_june = Tempo.from_iso8601!("2004-06~-11")
iex> {Tempo.qualification(about_june, :year), Tempo.qualification(about_june, :month)}
{:approximate, :approximate}
iex> Tempo.qualification(about_june, :day)
nil

# At the very END → the whole value (complete)
iex> Tempo.qualification(Tempo.from_iso8601!("2004-06-11~")) == %{year: :approximate, month: :approximate, day: :approximate}
true
```

So `2004-06~-11` reads as *"approximately June 2004, on the 11th"* — the `~` sits to the right of the month, so it covers the month **and the year it belongs to**, but not the day. A qualifier is held per component: `Tempo.qualification/2` reads one component's, and `Tempo.qualification/1` all of them as a map. The span is unchanged either way — the marker is metadata, not a widening of the date.

The full rule — group / individual / complete, the explicit `2004~Y6~M11D` form, and how it round-trips — is in the [ISO 8601 conformance guide](iso8601-conformance.md#component-qualification-iso-8601-2-8).

---

## 2. Exploring a value

### How do I see what a value represents?

```elixir
iex> Tempo.explain(~o"2026-06") |> String.split("\n")
["A value written to the month: Jun 1 – 30, 2026.", "It covers 2026Y6M through 2026Y6M.", "It is floating: a reading of a clock in no zone.", "Walking it gives its days."]
```

`Tempo.explain/1` returns a plain string, a sentence to a line: what kind of expression it is, what it covers, what frame it is in and what a walk of it gives. `Tempo.Explain.lines/1` returns the lines as a list.

### How do I see the concrete bounds of an implicit interval?

```elixir
iex> Tempo.to_interval(~o"2026-06")
{:ok, ~o"2026Y6M/2026Y6M"}

iex> Tempo.to_interval(~o"2026-06-15T10")
{:ok, ~o"2026Y6M15DT10H/T11H"}

iex> Tempo.at_resolution(~o"2026-06", :day)
{:ok, ~o"2026Y6M1D"}
```

Every Tempo value *is* an interval, and `to_interval/2` writes it as one at the value's own resolution: June is from June through June, and ten o'clock is from ten to eleven. `at_resolution/2` gives the first day, hour or minute of a value when that is what you are after.

### How do I check a value's resolution?

```elixir
iex> Tempo.resolution(~o"2026-06-15")
:day
```

---

## 3. Iteration

### How do I list every month of a year?

```elixir
iex> Enum.take(~o"2026Y", 12)
[~o"2026Y1M", ~o"2026Y2M", ~o"2026Y3M", ~o"2026Y4M", ~o"2026Y5M",
 ~o"2026Y6M", ~o"2026Y7M", ~o"2026Y8M", ~o"2026Y9M", ~o"2026Y10M",
 ~o"2026Y11M", ~o"2026Y12M"]
```

A walk of a year gives its months — the unit below the one the value is written to.

### How do I list every day of a month?

```elixir
iex> Enum.take(~o"2026-06", 30)
...> |> length()
30
```

### How do I list every year in the 1560s?

```elixir
iex> Enum.take(~o"156X", 5)
[~o"1560Y", ~o"1561Y", ~o"1562Y", ~o"1563Y", ~o"1564Y"]
```

An `X` is a digit left unspecified. The value names ten years, and a walk of a value that names several gives each of them.

### How do I step by another unit?

An interval is walked in the unit its ends are written to, and `Tempo.walk/2` walks any expression in the unit you name:

```elixir
iex> Enum.take(~o"2026-06-01/2026-06-30", 3)
[~o"2026Y6M1D", ~o"2026Y6M2D", ~o"2026Y6M3D"]

iex> {:ok, hours} = Tempo.walk(~o"2026-06-15", :hour)
iex> Enum.take(hours, 2)
[~o"2026Y6M15DT0H", ~o"2026Y6M15DT1H"]
```

See [Enumeration semantics](enumeration-semantics.md) for the two rules behind every walk.

---

## 4. Comparison and predicates

### How do I check if a date is in an interval?

```elixir
iex> Tempo.contains?(~o"2026Y", ~o"2026-06-15")
true
```

### How do I check if two intervals overlap?

```elixir
iex> a = ~o"2026-06-01/2026-06-15"
iex> b = ~o"2026-06-10/2026-06-20"
iex> Tempo.overlaps?(a, b)
true
```

### What's the full set of relationships between two intervals?

Tempo implements Allen's interval algebra — every pair of bounded intervals stands in exactly one of 13 relations. `Tempo.relation/2` returns the atom:

```elixir
iex> a = ~o"2026-06-01/2026-06-10"
iex> b = ~o"2026-06-05/2026-06-15"
iex> Tempo.relation(a, b)
:overlaps

iex> Tempo.relation(~o"2026-06-15", ~o"2026-06-16")
:meets
```

Everyday predicates cover the common one-shot checks, and `Tempo.Allen` has one for each of the thirteen relations under Allen's own name:

| Predicate | Maps to |
|---|---|
| `Tempo.before?(a, b)` | `:precedes \| :meets` — over by the time b starts |
| `Tempo.after?(a, b)` | `:preceded_by \| :met_by` — starts once b is over |
| `Tempo.adjacent?(a, b)` | `:meets \| :met_by` — touches, no gap |
| `Tempo.within?(a, b)` | `:equals \| :starts \| :during \| :finishes` — fits inside, inclusive |
| `Tempo.Allen.precedes?(a, b)` | `:precedes` alone — a gap before b |
| `Tempo.Allen.during?(a, b)` | `:during` alone — strictly inside |

`Tempo.within?/2` is the canonical "does this fit inside that window?" predicate:

```elixir
iex> candidate = ~o"2026-06-15T10/2026-06-15T11"
iex> window = ~o"2026-06-15T09/2026-06-15T17"
iex> Tempo.within?(candidate, window)
true
```

For set-level questions across two multi-member `IntervalSet`s, use `Tempo.IntervalSet.relation_matrix/2` which returns every pairwise relation.

### How long is an interval?

```elixir
iex> Tempo.duration(~o"2026-06-15T09/2026-06-15T11")
~o"PT2H"

iex> Tempo.duration(~o"2026-06-15/2026-07-21")
~o"P37D"

iex> Tempo.duration(~o"2026-06-15", ~o"2026-07-21")
{:ok, ~o"P36D"}
```

> *"Nine to eleven is **two hours**. The fifteenth of June **through** the twenty-first of July is **thirty-seven days**; **from** the one **to** the other is thirty-six."*

A length is counted in the unit the ends are written in. Years, months, weeks and days are calendar steps, so the day a clock change shortens is still one day; hours, minutes and seconds are elapsed time, so that same day is 23 hours. An interval written to dates runs through its last date, where `duration/2` measures from the start of one value to the start of another. An interval with an open end is `:infinity` long.

### How do I check an interval's length against a duration?

Five predicates cover the comparison lattice:

```elixir
iex> meeting = ~o"2026-06-15T09/2026-06-15T10"
iex> {Tempo.at_least?(meeting, ~o"PT1H"), Tempo.exactly?(meeting, ~o"PT1H"), Tempo.at_most?(meeting, ~o"PT1H")}
{true, true, true}

iex> {Tempo.longer_than?(meeting, ~o"PT30M"), Tempo.shorter_than?(meeting, ~o"PT2H")}
{true, true}
```

> *"The meeting is **at least**, **exactly** and **at most** an hour; it is **longer than** half an hour and **shorter than** two."*

### How do I compare two values across different calendars?

```elixir
iex> {:ok, hebrew} = Tempo.from_iso8601("5786-09-30[u-ca=hebrew]")
iex> hebrew.calendar
Calendrical.Hebrew

iex> Tempo.overlaps?(hebrew, ~o"2026-06-15")
true
```

The RFC 9557 suffix `[u-ca=NAME]` says which calendar the value is in — `hebrew`, `islamic-umalqura`, `persian`, `buddhist` and the rest of CLDR's. Two expressions in different calendars are compared on the one time line they share.

---

## 5. Set operations

### How do I merge two overlapping intervals into one?

```elixir
iex> a = ~o"2026-06-01/2026-06-15"
iex> b = ~o"2026-06-10/2026-06-20"
iex> {:ok, both} = Tempo.union(a, b)
iex> Tempo.IntervalSet.count(both)
2

iex> Tempo.IntervalSet.coalesce(both)
{:ok, ~o"{2026Y6M1D/20D}"}
```

> *"The **union** keeps both members. **Coalesced**, they are one span, the 1st of June through the 20th."*

`Tempo.union/2` keeps both members so each event's identity and metadata survive. When you want the time they cover as merged spans, call `Tempo.IntervalSet.coalesce/1`.

### How do I find the overlap between two intervals?

```elixir
iex> Tempo.intersection(a, b)
{:ok, ~o"{2026Y6M10D/15D}"}
```

> *"The two **overlap** from the 10th of June through the 15th."*

### How do I subtract a busy period from a free window?

```elixir
iex> work_day = ~o"2026-06-15T09/2026-06-15T17"
iex> lunch = ~o"2026-06-15T12/2026-06-15T13"
iex> Tempo.difference(work_day, lunch)
{:ok, ~o"{2026Y6M15DT9H/T12H,2026Y6M15DT13H/T17H}"}
```

> *"The **workday minus lunch** is my **free** time — nine to twelve, and one to five."*

### How do I compose free/busy across a real schedule?

<!-- guides:skip -->

```elixir
{:ok, schedule} = Tempo.ICal.parse_file("~/work.ics")

work = ~o"2026-06-15T09/2026-06-15T17"
{:ok, free} = Tempo.difference(work, schedule)
```

> **Work** minus **my schedule** gives me **free** time that day.

To trace which meeting made each gap, ask the schedule with `Tempo.members_overlapping/2`.

### How do I get the symmetric difference (everything in A or B but not both)?

```elixir
iex> Tempo.symmetric_difference(a, b)
{:ok, ~o"{2026Y6M1D/9D,2026Y6M16D/20D}"}
```

> *"In one **or** the other but **not both**: the 1st through the 9th, and the 16th through the 20th."*

### How do I find double-booked time?

```elixir
iex> bookings = Tempo.IntervalSet.new!([
...>   ~o"2026-06-15T09:00:00/2026-06-15T11:00:00",
...>   ~o"2026-06-15T10:00:00/2026-06-15T12:00:00",
...>   ~o"2026-06-15T14:00:00/2026-06-15T15:00:00"
...> ])
iex> {:ok, double_booked} = Tempo.IntervalSet.covered(bookings, at_least: 2)
iex> Tempo.IntervalSet.members(double_booked)
[~o"2026Y6M15DT10H0M0S/T11H0M0S"]
```

> The **double-booked** time is the time **covered** by **at least two** bookings. Without `:at_least`, `covered/2` is the time the bookings cover at all; two bookings that merely meet, one ending as the next begins, never count twice.

---

## 6. Selecting with `Tempo.select/3`

`Tempo.select/3` picks, from a base, the values a selector names: the workdays of a month, the fifteenth of each month of a year, nine to five on each day of a quarter. It answers a set of the values picked, which drops straight into the set operations.

### How do I select the workdays of a month?

```elixir
iex> {:ok, workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
iex> Tempo.IntervalSet.count(workdays)
22
```

> *"The **workdays** of **June 2026** in the **United States**: twenty-two days, Monday to Friday."*

### How do I pick specific days inside a month?

```elixir
iex> Tempo.select(~o"2026-06", [1, 15])
{:ok, ~o"{2026Y6M1D,2026Y6M15D}"}

iex> {:ok, mid_month} = Tempo.select(~o"2026-06", 10..15)
iex> Tempo.IntervalSet.map(mid_month, &Tempo.day/1)
[10, 11, 12, 13, 14, 15]
```

> *"The **1st** and the **15th** of June."*

A list of whole numbers, or a range of them, is days of the month, in each month the base runs through: from a year, `[1, 15]` is twenty-four paydays.

### How do I select a date in a year?

```elixir
iex> Tempo.select(~o"2026", ~o"12M25D")
{:ok, ~o"{2026Y12M25D}"}

iex> Tempo.select(~o"2026", [~o"7M4D", ~o"12M25D"])
{:ok, ~o"{2026Y7M4D,2026Y12M25D}"}
```

> *"**Christmas Day** of 2026; and the **Fourth of July** with it."*

A selector is a value with no year — a month and a day, a day of the week, a time of day — and the base supplies the rest. Write one in the explicit form (`12M25D`): the extended form `12-25` is read as a time of day with a shift.

### How do I select a different territory's weekend?

```elixir
iex> {:ok, sa_weekend} = Tempo.select(~o"2026-02", Tempo.weekends(:SA))
iex> Tempo.IntervalSet.map(sa_weekend, &Tempo.day/1)
[6, 7, 13, 14, 20, 21, 27, 28]
```

> *"Saudi Arabia's **weekend** is **Friday and Saturday**."*

`Tempo.weekends/1` and `Tempo.workdays/2` take a territory atom (`:SA`), a territory string (`"SA"`), a locale string (`"ar-SA"`) or a `%Localize.LanguageTag{}`. With no argument they use the application's `:default_territory`, and then the territory of `Localize.get_locale/0`. Pass a full locale when you have one rather than the territory:

```elixir
iex> {:ok, sa_weekend} = Tempo.select(~o"2026-02", Tempo.weekends("ar-SA"))
iex> Tempo.IntervalSet.map(sa_weekend, &Tempo.day/1)
[6, 7, 13, 14, 20, 21, 27, 28]
```

### How do I select from a date on, with no end?

```elixir
iex> {:ok, weekends} = Tempo.select(~o"2026-06-15/..", Tempo.weekends(:SA))
iex> Enum.take(weekends, 3)
[~o"2026Y6M19D", ~o"2026Y6M20D", ~o"2026Y6M26D"]

iex> {:ok, christmases} = Tempo.select(~o"2026/..", ~o"12M25D")
iex> Enum.take(christmases, 2)
[~o"2026Y12M25D", ~o"2027Y12M25D"]
```

> *"The **weekend days** of **Saudi Arabia** from **the 15th of June on**; and every **Christmas** from this year on."*

A base with no end gives a lazy set, walked only as far as it is taken. The same set is busy time for `Tempo.shift/3` to skip (see the [scheduling guide](./scheduling.md)).

### How do I compose select with the set operations?

```elixir
iex> {:ok, june_workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
iex> vacation = ~o"2026-06-15/2026-06-20"
iex> {:ok, at_work} = Tempo.difference(june_workdays, vacation)
iex> Tempo.IntervalSet.coalesce(at_work)
{:ok, ~o"{2026Y6M1D/5D,2026Y6M8D/12D,2026Y6M22D/26D,2026Y6M29D/30D}"}

iex> {:ok, days_at_work} = Tempo.members_outside(june_workdays, vacation)
iex> Tempo.IntervalSet.count(days_at_work)
17
```

> *"The **US workdays** of June **minus** my **vacation** are the days I am at work, **joined** into four runs of days. The workdays **outside** my vacation are seventeen."*

`difference/2` answers the time left, with days that touch joined into one span. `members_outside/2` keeps each workday a member of its own, which is the one to use when the days are to be counted or listed.

### How do I use a function as a selector?

```elixir
iex> holidays = fn _base -> [~o"1M1D", ~o"7M4D", ~o"12M25D"] end
iex> Tempo.select(~o"2026", holidays)
{:ok, ~o"{2026Y1M1D,2026Y7M4D,2026Y12M25D}"}
```

> *"The **holidays** of 2026, by a rule of my own."*

A function selector is given the base and returns any other selector — here a list of values. It is the place for a holiday calendar, a business rule, or anything else computed from the base.

### How do I pick "the last X of Y"?

ISO 8601-2 §4.4.1 lets a component be negative, counting from the end of the unit that holds it. A negative component goes straight through `Tempo.select/3` — no arithmetic on text, no `days_in_month/1`, no branch for the calendar:

```elixir
iex> Tempo.select(~o"2026", ~o"-1M")
{:ok, ~o"{2026Y12M}"}

iex> Tempo.select(~o"2024-02", ~o"-1D")
{:ok, ~o"{2024Y2M29D}"}

iex> Tempo.select(~o"2026-02", ~o"-1D")
{:ok, ~o"{2026Y2M28D}"}

iex> Tempo.select(~o"2026", ~o"-1W")
{:ok, ~o"{2026Y53W}"}
```

> *"The **last month** of 2026. The **last day** of February, in a leap year and in a common one. The **last week** of 2026, which is its fifty-third."*

`-1O` is the year's last day and `-1K` the week's last day. The weeks asked of a month are the weeks the calendar numbers in that month: `Tempo.select(~o"2026-06", ~o"-1W")` is the last of June's four, and `~o"1W"` from July 2026 begins on the 29th of June, the Monday of the week that holds the 1st.

Times of day work the same way, written after a `T`:

```elixir
iex> Tempo.select(~o"2026-06-15", ~o"T-1H")
{:ok, ~o"{2026Y6M15DT23H}"}

iex> Tempo.select(~o"2026-06-15T14", ~o"T-1M")
{:ok, ~o"{2026Y6M15DT14H59M}"}
```

> *"The **last hour** of the 15th; the **last minute** of two o'clock."*

`~o"-1M"` is always a month. `~o"T-1M"`, with the time designator, is a minute.

The last *weekday* of a period is a position among the days selected — a selection of its own, written between `L` and `N`:

```elixir
iex> Tempo.select(~o"2026-06", ~o"L5K-1IN")
{:ok, ~o"{2026Y6M26D}"}
```

> *"Of the **Fridays** of June, the **last**."*

### How do I express business hours across a quarter?

An interval with no date selects a span of each day: the day comes from the base, the times from the selector. A list gives several windows a day:

```elixir
iex> {:ok, workdays} = Tempo.select(~o"2026-07/2026-09", Tempo.workdays(:AU))
iex> {:ok, open} = Tempo.select(workdays, [~o"T09/T12", ~o"T13/T17"])
iex> Tempo.IntervalSet.count(open)
132

iex> Tempo.duration(open)
~o"PT462H"

iex> Tempo.IntervalSet.first(open)
~o"2026Y7M1DT9H/T12H"
```

> *"The **workdays** of the quarter, **nine to five** with an **hour for lunch**: sixty-six days, two windows each, 462 open hours."*

A clock end is the reading the span runs to, so nine to five is written as nine to five: `~o"T09/T17"` is eight hours, with nothing to add or take away.

Take the public holidays out with `Tempo.members_outside(open, holidays)` and the result is still one pipeline. A window that does not end on the hour is written with a duration — `~o"T09/PT7H36M"` is a statutory 7.6-hour day — and one that crosses midnight ends on the day after: `~o"T21/T05"` is the night shift as a roster writes it.

---

## 7. Recurring events (RRULE)

`Tempo.RRule.parse!/2` reads an RRULE into a recurrence, the same expression ISO 8601-2 writes as `R…/…/F…`. Walk it, or list its occurrences with `Tempo.to_interval/2`, bounded by the rule's own `COUNT` or `UNTIL` or by a `:within` window. (A plain cadence needs no RRULE at all: `~o"R10/2026-06-01/P1W"` is ten weeks from the 1st of June. See the [scheduling guide](./scheduling.md).)

### How do I express "every Monday for 10 weeks"?

```elixir
iex> mondays = Tempo.RRule.parse!("FREQ=WEEKLY;BYDAY=MO;COUNT=10", from: ~o"2026-06-01")
iex> Enum.count(mondays)
10

iex> Enum.take(mondays, 2)
[~o"2026Y6M1D/2026Y6M1D", ~o"2026Y6M8D/2026Y6M8D"]
```

> *"**Every Monday** from the 1st of June, **ten** times."*

An occurrence is a span — here a day, from itself through itself. Give `parse!/2` a `:duration` and each is that long.

### How do I express "the 4th Thursday of November" (Thanksgiving)?

```elixir
iex> thanksgiving = Tempo.RRule.parse!("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=5", from: ~o"2022-11-24")
iex> Enum.map(thanksgiving, &Tempo.day(Tempo.Interval.from(&1)))
[24, 23, 28, 27, 26]
```

> *"The **fourth Thursday** of **November**, for five years."*

A positive number counts from the start of the month and a negative one from its end (`-1FR` is the last Friday).

### How do I express "every Friday the 13th"?

```elixir
iex> friday_13th = Tempo.RRule.parse!("FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR;COUNT=4", from: ~o"1998-02-13")
iex> Enum.map(friday_13th, &Tempo.Interval.from/1)
[~o"1998Y2M13D", ~o"1998Y3M13D", ~o"1998Y11M13D", ~o"1999Y8M13D"]

iex> Tempo.select(~o"2026", ~o"13D5K")
{:ok, ~o"{2026Y2M13D,2026Y3M13D,2026Y11M13D}"}
```

> *"The **13th** of a month that is a **Friday**."*

Beside `BYMONTHDAY`, `BYDAY` is a filter (RFC 5545's Note 1): the thirteenth of each month, kept when it is a Friday. As a selector the same thing is `13D5K`, a day of the month and the day of the week it must be.

### How do I express US Presidential Election Day?

"Every four years, the first Tuesday after a Monday in November":

```elixir
iex> election_day =
...>   Tempo.RRule.parse!(
...>     "FREQ=YEARLY;INTERVAL=4;BYMONTH=11;BYDAY=TU;BYMONTHDAY=2,3,4,5,6,7,8;COUNT=3",
...>     from: ~o"1996-11-05"
...>   )
iex> Enum.map(election_day, &Tempo.Interval.from/1)
[~o"1996Y11M5D", ~o"2000Y11M7D", ~o"2004Y11M2D"]
```

> *"Every **fourth year**, the **Tuesday** of November that falls on the **2nd to the 8th**."*

### How do I express "last weekday of every month"?

```elixir
iex> last_weekday = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3", from: ~o"2026-06-01")
iex> Enum.map(last_weekday, &Tempo.Interval.from/1)
[~o"2026Y6M30D", ~o"2026Y7M31D", ~o"2026Y8M31D"]
```

> *"Of each month's **weekdays**, the **last**."*

`BYDAY=MO,TU,WE,TH,FR` is every weekday of the month; `BYSETPOS=-1` picks the last of them.

### How do I handle an unbounded rule?

Supply `:within`:

```elixir
iex> daily = Tempo.RRule.parse!("FREQ=DAILY", from: ~o"2026-06-01")
iex> {:ok, june} = Tempo.to_interval(daily, within: ~o"2026-06")
iex> Tempo.IntervalSet.count(june)
30

iex> Enum.take(daily, 2)
[~o"2026Y6M1D/2026Y6M1D", ~o"2026Y6M2D/2026Y6M2D"]
```

> *"**Every day** from the 1st of June, with no end: thirty of them **within June**, or as many as are taken."*

---

### How do I build a recurrence from parts, without writing its text?

When a program holds the parts (a month from a form, a weekday from a table), build the recurrence from them. `Tempo.every/2` takes the cadence, where it starts, how it ends and what it selects in each repeat; `Tempo.selection/1` builds what is selected on its own. What they build is what the text reads to, so nothing is written to be read back.

```elixir
iex> month = 11
iex> {:ok, thanksgiving} = Tempo.every(~o"P1Y", select: [month: month, day_of_week: 4, instance: 4])
iex> thanksgiving
~o"R/../P1Y/FL11M4K4IN"

iex> thanksgiving
...> |> Tempo.to_interval!(within: ~o"2026/2027")
...> |> Tempo.IntervalSet.map(&Tempo.Interval.from/1)
[~o"2026Y11M26D", ~o"2027Y11M25D"]
```

> *"**Every** year, **select** in November the Thursdays, and of them the **fourth**."*

A selection made first, and others within what it gives, is a nested `:selection`. Good Friday is the Friday in the week before Easter:

```elixir
iex> {:ok, good_friday} =
...>   Tempo.every(~o"P1Y",
...>     select: [selection: [event: "easter"], window: ~o"-P7D", day_of_week: 5, instance: -1]
...>   )
iex> good_friday
...> |> Tempo.to_interval!(within: ~o"2026/2027")
...> |> Tempo.IntervalSet.map(&Tempo.Interval.from/1)
[~o"2026Y4M3D", ~o"2027Y3M26D"]
```

> *"**Every** year, take **Easter**, open a **window** of the week before it, and **select** its last Friday."*

### How do I read a cron schedule?

`Tempo.Cron.parse/2` reads five, six or seven fields into a recurrence, with the extensions of Vixie cron and Quartz for the last day of a month (`L`), its last weekday (`LW`), the weekday nearest a day (`15W`), the last of a weekday (`5L`) and the nth (`5#2`).

```elixir
iex> {:ok, month_end} = Tempo.Cron.parse("0 17 LW * *", from: ~o"2026-01-01T00:00")
iex> month_end
...> |> Tempo.to_interval!(within: ~o"2026-01/2026-03")
...> |> Tempo.IntervalSet.map(&Tempo.Interval.from/1)
[~o"2026Y1M30DT17H0M", ~o"2026Y2M27DT17H0M", ~o"2026Y3M31DT17H0M"]
```

> *"At five in the afternoon on the **last weekday** of each month."*

## 8. iCalendar import

### How do I import an `.ics` file?

<!-- guides:skip -->

```elixir
iex> {:ok, schedule} = Tempo.ICal.parse_file("~/work.ics")
iex> Tempo.IntervalSet.count(schedule)
# One interval per VEVENT (or per recurrence occurrence).
```

Each event is an interval, with the event's summary, location, attendees and the rest as its metadata.

### How do I import an `.ics` that contains recurring events?

Pass a `:within` so unbounded recurrences terminate:

<!-- guides:skip -->

```elixir
iex> {:ok, schedule} = Tempo.ICal.parse(ics, within: ~o"2026-04-01/2026-07-01")
```

A recurring event is one interval for each occurrence in the window, each carrying the event's metadata. See the [iCalendar guide](ical-integration.md) for what is read, and the [RRULE conformance guide](rfc5545_rrule_conformance.md) for the parts of a rule that are not.

### How do I find when a specific attendee is in a meeting?

<!-- guides:skip -->

```elixir
{:ok, schedule} = Tempo.ICal.parse(ics)

ada_meetings =
  schedule
  |> Tempo.IntervalSet.members()
  |> Enum.filter(fn meeting ->
    "ada@example.com" in (Tempo.metadata(meeting)[:attendees] || [])
  end)
```

> **Ada's meetings** are every event in the **schedule** whose **attendees** include her.

The operations that keep members — `union/2`, `members_overlapping/2`, `members_outside/2` — keep each member's metadata with it.

---

## 9. Cross-calendar and cross-timezone

### How do I compare a Hebrew date to a Gregorian one?

```elixir
iex> hebrew = Tempo.new!(year: 5786, month: 9, day: 30, calendar: Calendrical.Hebrew)
iex> gregorian = ~o"2026-06-15"
iex> Tempo.overlaps?(hebrew, gregorian)
true

iex> Tempo.relation(hebrew, gregorian)
:equals
```

> *"The **Hebrew** 30th of the ninth month of 5786 **is** the **Gregorian** 15th of June 2026 — the same day."*

### How do I compare across timezones?

```elixir
iex> paris = Tempo.from_datetime(DateTime.new!(~D[2026-06-15], ~T[10:00:00], "Europe/Paris"))
iex> utc_window = ~o"2026-06-15T07Z/2026-06-15T09Z"
iex> Tempo.within?(paris, utc_window)
true

iex> Tempo.shift_zone(paris, "Etc/UTC")
{:ok, ~o"2026Y6M15DT8H0M0S[Etc/UTC]"}
```

> *"Ten o'clock in **Paris** is **within** seven to nine **UTC**: it is eight o'clock there."*

Two zoned expressions are compared as the instants they are, through the configured time zone database at the time of the call. Each keeps the reading it was written with.

### How do I convert a Tempo to a specific calendar?

```elixir
iex> {:ok, hebrew} = Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)
iex> {Tempo.year(hebrew), Tempo.month(hebrew), Tempo.day(hebrew)}
{5786, 9, 30}
```

### How do I get a fiscal quarter from the calendar that defines it?

Calendrical's period functions answer *"which days are in this quarter?"* in any calendar — fiscal, retail, academic — and return a `Date.Range`. `Tempo.from_elixir/2` makes it the interval of exactly those days, in that calendar:

```elixir
iex> {:ok, calendar} = Calendrical.FiscalYear.calendar_for(:AU)
iex> {:ok, quarter} = Tempo.from_elixir(calendar.quarter(2027, 1))
iex> {:ok, workdays} = Tempo.select(quarter, Tempo.workdays(:AU))
iex> Tempo.IntervalSet.count(workdays)
66
```

> *"The first quarter of Australian financial year 2027 has **66 workdays**."*

Written out, the same quarter is `~o"2026-07-01/2026-09-30"` — the fiscal boundary by hand, right when written and wrong the year the rules change. The calendar itself says which days it is.

A fiscal value is related to and combined with a Gregorian one directly: the quarter's first day is the Gregorian 1st of July 2026.

```elixir
iex> Tempo.relation(Tempo.Interval.from(quarter), ~o"2026-07-01")
:equals

iex> Tempo.to_calendar(quarter, Calendrical.Gregorian)
{:ok, ~o"2026Y7M1D/9M30D[u-ca=gregorian]"}
```

A fiscal calendar has no name ISO 8601 can write, so a value in it has no text of its own (`Tempo.to_iso8601/1` returns an error rather than a date another calendar would read): convert it to the Gregorian calendar to store or show it. A `Date.Range` with a step is refused: it lists days, and is no span.

---

## 10. Archaeological / approximate dates

### How do I say "sometime in the 1560s"?

```elixir
iex> Enum.count(~o"156X")
10

iex> Tempo.duration(~o"156X")
~o"P10Y"

iex> Tempo.within?(~o"1564-06", ~o"156X")
true
```

> *"Some year of the **1560s**: one of **ten** years, a decade between them, and June 1564 is **within** it."*

An `X` is a digit left unspecified, so the value names each year it could be.

### How do I say "the 15th of every month in 1985"?

```elixir
iex> {:ok, set} = Tempo.to_interval(~o"1985-XX-15")
iex> Tempo.IntervalSet.count(set)
12
```

An unspecified month with a day written after it is that day of each month: twelve days, each a span of its own.

### How do I move an approximate date?

A shift moves each value the expression names, and gathers them back in the shape that holds them:

```elixir
iex> Tempo.shift(~o"156X", ~o"P10Y")
{:ok, ~o"[1570Y..1579Y]"}

iex> Tempo.shift(~o"156X", ~o"P1Y")
{:ok, ~o"[1561Y..1570Y]"}

iex> Tempo.shift(~o"1985-XX-15", ~o"P1D")
{:ok, ~o"1985YXXM16D"}
```

> *"Some year of the 1560s, **a decade on**, is some year of the 1570s; **a year on**, some year from 1561 to 1570. The 15th of some month of 1985, **a day on**, is its 16th."*

Where the shift passes the unspecified digits by, the mask is kept as written. Where it does not, the answer is the years it could be, written as one of a range.

### How do I express an open-ended interval?

```elixir
iex> since_1985 = ~o"1985/.."
iex> {Tempo.bounded?(since_1985), Tempo.duration(since_1985)}
{false, :infinity}

iex> Tempo.Interval.to(~o"1985/..")
:open

iex> Tempo.Interval.from(~o"../2024")
:open
```

> *"From 1985 on, with **no end**: it is not bounded, and its length is infinite."*

An open end has no place on the time line, so an open-ended interval is a window (`within: ~o"2026/.."`) and a base to select from, and is refused by the relations and the set operations until it is given both ends.

### How do I attach a qualifier to a single endpoint?

```elixir
iex> reign = ~o"1984?/2004~"
iex> Tempo.qualification(Tempo.Interval.from(reign), :year)
:uncertain

iex> Tempo.qualification(Tempo.Interval.to(reign), :year)
:approximate
```

> *"From an **uncertain** 1984 to an **approximate** 2004."*

Each end carries its own marks.

---

## 11. Chronological networks and dependency scheduling

Two kinds of reasoning build on Tempo's intervals and live in the companion package `tempo_network`:

* **Chronological networks** — periods whose start, end and length are only partly known, linked by relations such as "began during" or "overlaps", solved for the tightest dates consistent with all of them, or for the contradiction among them.

* **Dependency scheduling** — tasks with durations and finish-to-start dependencies, solved for each task's earliest and latest place and for the critical path.

Both take and return Tempo values, so everything in this cookbook applies to what they answer.

---

## 12. Real-world scenarios

### Find every Friday the 13th this century

```elixir
iex> {:ok, unlucky} = Tempo.select(~o"2000/2099", ~o"13D5K")
iex> Tempo.IntervalSet.count(unlucky)
172

iex> Tempo.IntervalSet.first(unlucky)
~o"2000Y10M13D"
```

> *"The **13ths** of the century that are **Fridays**: a hundred and seventy-two of them, the first in October 2000."*

The same days as a rule, for a system that speaks RRULE:

```elixir
iex> friday_13th = Tempo.RRule.parse!("FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR", from: ~o"2000-01-01")
iex> {:ok, occurrences} = Tempo.to_interval(friday_13th, within: ~o"2000/2099")
iex> Tempo.IntervalSet.count(occurrences)
172
```

### Find when two people are both free for at least 1 hour

```elixir
iex> work = ~o"2026-06-15T09/2026-06-15T17"
iex> ada = Tempo.IntervalSet.new!([~o"2026-06-15T10/2026-06-15T11", ~o"2026-06-15T14/2026-06-15T15"])
iex> grace = Tempo.IntervalSet.new!([~o"2026-06-15T09:30/2026-06-15T10:30", ~o"2026-06-15T16/2026-06-15T17"])
iex> {:ok, ada_free} = Tempo.difference(work, ada)
iex> {:ok, grace_free} = Tempo.difference(work, grace)
iex> {:ok, mutual} = Tempo.intersection(ada_free, grace_free)
iex> mutual |> Tempo.IntervalSet.members() |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))
[~o"2026Y6M15DT11H/T14H", ~o"2026Y6M15DT15H/T16H"]
```

> *"Ada's free time is the workday **minus** her busy periods. Grace's is the same. **Mutual** free time is the **intersection** of theirs. The windows worth offering are those **at least an hour** long."*

With real calendars, `ada` and `grace` come from `Tempo.ICal.parse_file/2` instead; nothing else changes.

### List every bookable 1-hour slot two people share

```elixir
iex> {:ok, slots} = Tempo.IntervalSet.slots(mutual, ~o"PT1H")
iex> Tempo.IntervalSet.members(slots)
[~o"2026Y6M15DT11H/T12H", ~o"2026Y6M15DT12H/T13H", ~o"2026Y6M15DT13H/T14H", ~o"2026Y6M15DT15H/T16H"]
```

> *"The mutual free time, **cut into hour-long slots**."*

Where the recipe above gives the free *windows*, `slots/3` cuts each into the slots a booking page offers. Pass `every: ~o"PT30M"` to start a slot on every half-hour, or a larger `:every` to leave gaps between them.

### Which of these candidate meeting times can I book?

```elixir
iex> candidates = [~o"2026-06-15T09/2026-06-15T10", ~o"2026-06-15T11/2026-06-15T12", ~o"2026-06-15T15/2026-06-15T16"]
iex> Enum.filter(candidates, &Tempo.within?(&1, mutual))
[~o"2026Y6M15DT11H/T12H", ~o"2026Y6M15DT15H/T16H"]
```

> *"A candidate is **bookable** when it is **within** the mutual free time."*

### How do I check if a dig layer overlaps a historical period?

```elixir
iex> dig_layer = ~o"1520/1590"
iex> ming_period = ~o"1368/1644"
iex> Tempo.overlaps?(dig_layer, ming_period)
true

iex> Tempo.within?(dig_layer, ming_period)
true
```

> *"The **dig layer overlaps** the **Ming period** — and lies wholly **within** it."*

### How do I find free time across multiple schedules and timezones?

<!-- guides:skip -->

```elixir
{:ok, ny}     = Tempo.ICal.parse_file("~/cal_ny.ics")
{:ok, london} = Tempo.ICal.parse_file("~/cal_london.ics")

work = ~o"2026-06-15T09/2026-06-15T17[America/New_York]"

{:ok, ny_free} = Tempo.difference(work, ny)
{:ok, free}    = Tempo.difference(ny_free, london)
```

> *"**Work** minus **New York's busy times**, minus **London's**, is the time **free** for both."*

Each operand is in its own zone and all are compared as the instants they are, so the clocks' five hours' difference takes care of itself. The answer is in the zone of the first operand.

### How do I round a datetime to the hour?

```elixir
iex> Tempo.trunc(~o"2026-06-15T10:37:42", :hour)
{:ok, ~o"2026Y6M15DT10H"}

iex> Tempo.round(~o"2026-06-15T10:37:42", :hour)
{:ok, ~o"2026Y6M15DT11H"}
```

> *"**Truncated** to the hour it is ten o'clock; **rounded**, eleven."*

`Tempo.at_resolution/2` is the one to use when the target may be coarser or finer than the value: coarser it truncates, finer it fills with the first of each unit.

### How do I generate a list of business days in a month?

```elixir
iex> {:ok, workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
iex> Tempo.IntervalSet.count(workdays)
22
```

> *"The **workdays** of **June 2026**: twenty-two, Monday to Friday."*

See [section 6](#6-selecting-with-tempo-select-3) for the selectors, and [Working with workdays and weekends](workdays-and-weekends.md) for holidays and the territory. As a rule, for a system that speaks RRULE:

```elixir
iex> weekdays = Tempo.RRule.parse!("FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR", from: ~o"2026-06-01")
iex> {:ok, days} = Tempo.to_interval(weekdays, within: ~o"2026-06")
iex> Tempo.IntervalSet.count(days)
22
```

### Business/252 — Brazil's business-day year fraction

Brazilian fixed-income instruments accrue interest on the BUS/252 day count: the year fraction between two dates is the number of business days between them divided by a fixed 252, where a business day is Monday to Friday less the [ANBIMA](https://www.anbima.com.br/feriados/feriados.asp) national banking holidays.

ANBIMA publishes the holiday list (2001–2099) as a spreadsheet; `scripts/anbima_xls_to_ics.py` in this repository converts it to an iCalendar file that Tempo loads directly.

<!-- guides:skip -->

```elixir
{:ok, holidays} = Tempo.ICal.parse_file("feriados_anbima.ics")

accrual = ~o"2024-01-01/2024-12-31"

{:ok, workdays}      = Tempo.select(accrual, Tempo.workdays(:BR))
{:ok, business_days} = Tempo.members_outside(workdays, holidays)

Tempo.IntervalSet.count(business_days) / 252
#=> 1.003968253968254   (253 business days in 2024)
```

> *"The **workdays** of the accrual period are Brazil's Monday to Friday. **Business days** are the workdays **outside** the ANBIMA holidays. The **year fraction** is their count over a fixed 252."*

The accrual period is written to its last day: BUS/252 counts from settlement up to and not including maturity, so a bond maturing on the 1st of January 2025 accrues through the 31st of December. The denominator is always 252, however many business days a year holds, so a fraction a little above 1 for a calendar year is correct. And because the holiday list is pricing data, pin a dated copy of the generated `.ics` rather than refreshing it from a live feed.

### Ramadan working hours — statutory hours across two calendars

UAE labour law (Article 17 of Federal Decree-Law No. 33 of 2021) reduces the private-sector workday by two hours — from eight to six — for every day of Ramadan, for all employees. The payroll year is Gregorian; Ramadan is the ninth month of the Islamic calendar, and falls about eleven days earlier each Gregorian year. Statutory hours are therefore a question of a Gregorian working year and an Islamic month — two expressions in *two calendars*:

```elixir
iex> work_year = ~o"2026"
iex> ramadan = ~o"1447-09[u-ca=islamic-civil]"
iex> {:ok, workdays} = Tempo.select(work_year, Tempo.workdays(:AE))
iex> {:ok, ramadan_workdays} = Tempo.members_overlapping(workdays, ramadan)
iex> {:ok, normal_workdays} = Tempo.members_outside(workdays, ramadan)
iex> {Tempo.IntervalSet.count(normal_workdays), Tempo.IntervalSet.count(ramadan_workdays)}
{239, 22}

iex> Tempo.IntervalSet.count(normal_workdays) * 8 + Tempo.IntervalSet.count(ramadan_workdays) * 6
2044

iex> Tempo.to_calendar(ramadan, Calendrical.Gregorian)
{:ok, ~o"2026Y2M18D/3M19D[u-ca=gregorian]"}
```

> *"The **workdays** of 2026 are the UAE's Monday to Friday. The **Ramadan workdays** are those **overlapping** Ramadan 1447; the **normal workdays** are those **outside** it. **Statutory hours** are eight for each normal workday and six for each of Ramadan's."*

Three things are doing quiet work here. `Tempo.workdays(:AE)` knows from CLDR that the UAE moved its weekend to Saturday and Sunday in 2022. The Gregorian workdays are compared with an Islamic month on the time line the two calendars share — Ramadan 1447 is the 18th of February through the 19th of March — with neither converted by hand. And the two filters part the workdays exactly, so no day is counted twice.

Next year the same pipeline needs only new bindings — `~o"2027"` and `~o"1448-09[u-ca=islamic-civil]"`.

Two cautions for production. The tabular `islamic-civil` calendar is for planning: the legal month follows the announced sighting of the moon, so for a payroll run pin the announced dates. And public holidays — Eid al-Fitr follows Ramadan at once — come out with `Tempo.members_outside/2` exactly as in the Business/252 recipe.

### The 25-hour shift — DST and payroll

A night-shift worker in New York works 21:00 to 05:00. On the night the clocks go back the hour from one to two happens twice, and US wage law pays non-exempt workers for hours *actually worked* — nine, not eight. On the night they go forward the hour from two to three never happens, and the same shift is seven. Arithmetic on the wall clock gets both wrong; Tempo measures and walks elapsed hours through the time zone database:

```elixir
iex> normal = ~o"2026-10-24T21/2026-10-25T05[America/New_York]"
iex> fall_back = ~o"2026-10-31T21/2026-11-01T05[America/New_York]"
iex> spring_forward = ~o"2026-03-07T21/2026-03-08T05[America/New_York]"
iex> {Tempo.duration(normal), Tempo.duration(fall_back), Tempo.duration(spring_forward)}
{~o"PT8H", ~o"PT9H", ~o"PT7H"}

iex> fall_back |> Enum.to_list() |> Enum.slice(4, 2)
[~o"2026Y11M1DT1HZ-4H0M[America/New_York]", ~o"2026Y11M1DT1HZ-5H0M[America/New_York]"]
```

> *"The usual shift is **eight hours**; the night the clocks go back it is **nine**, and the night they go forward **seven**. One o'clock happens **twice** in the long one: once four hours behind UTC, once five."*

The two one o'clocks are two values, told apart by the offset each had, as RFC 9557 writes them. So a payroll record made from the walk reads each hour back to the instant it was.

### Is the on-call rotation fair?

Three engineers rotate weekly on call, handing over each Monday, thirteen weeks a quarter. By count of weeks the rota looks nearly fair — five, four and four. But weekends are what on-call costs, and each rotation is one set of intervals, so the question is one selection each:

```elixir
iex> alice = ~o"{2025-12-29/2026-01-04,2026-01-19/2026-01-25,2026-02-09/2026-02-15,2026-03-02/2026-03-08,2026-03-23/2026-03-29}"
iex> bob = ~o"{2026-01-05/2026-01-11,2026-01-26/2026-02-01,2026-02-16/2026-02-22,2026-03-09/2026-03-15}"
iex> carol = ~o"{2026-01-12/2026-01-18,2026-02-02/2026-02-08,2026-02-23/2026-03-01,2026-03-16/2026-03-22}"
iex> for {name, rota} <- [alice: alice, bob: bob, carol: carol] do
...>   {:ok, weekend_days} = Tempo.select(rota, Tempo.weekends(:US))
...>   {name, Tempo.IntervalSet.count(weekend_days)}
...> end
[alice: 10, bob: 8, carol: 8]
```

> *"Each engineer's **rota** is the weeks they carry the pager, Monday through Sunday. Their **weekend burden** is the **weekend days selected** from it. Alice's ten against eight make her load a **quarter heavier**, from a rotation that looked fair by count of weeks."*

A `{a/b,c/d,…}` sigil is a set of intervals, and `Tempo.select/3` selects from every member, so "the weekend days of Alice's five weeks" needs no loop.

### Daylight-limited work — Tempo + Astro

Outdoor crews — surveyors, riggers, film units — can use only the site hours that are also daylight. How much workable time does a Helsinki crew have in December 2026, against the same crew in Lisbon? Sunrise and sunset come from the [Astro](https://hex.pm/packages/astro) ephemeris; the rest is set algebra:

```elixir
iex> workable_daylight = fn december, territory, location, zone ->
...>   {:ok, workdays} = Tempo.select(december, Tempo.workdays(territory))
...>
...>   lengths =
...>     for day <- workdays do
...>       {:ok, date} = Tempo.to_date(day)
...>       {:ok, sunrise} = Astro.sunrise(location, date, time_zone: zone)
...>       {:ok, sunset} = Astro.sunset(location, date, time_zone: zone)
...>
...>       daylight =
...>         Tempo.Interval.new!(
...>           from: Tempo.from_datetime(DateTime.truncate(sunrise, :second)),
...>           to: Tempo.from_datetime(DateTime.truncate(sunset, :second))
...>         )
...>
...>       {:ok, site_hours} = Tempo.select(day, ~o"T08/T16")
...>       {:ok, workable} = Tempo.intersection(site_hours, daylight)
...>       Tempo.duration(workable)
...>     end
...>
...>   {:ok, hours} = lengths |> Tempo.Duration.sum() |> Tempo.Duration.to_unit(:hour)
...>   Float.round(hours, 1)
...> end
iex> workable_daylight.(~o"2026-12[Europe/Helsinki]", :FI, {24.9384, 60.1699}, "Europe/Helsinki")
137.7

iex> workable_daylight.(~o"2026-12[Europe/Lisbon]", :PT, {-9.1393, 38.7223}, "Europe/Lisbon")
184.0
```

> *"For each **workday** of a December, the **site hours**, eight to four, **intersected** with that day's **daylight**, and their lengths **summed**. Lisbon's crew has all 184 of its site hours; Helsinki's has 137.7 — a quarter fewer, from geography alone."*

Three details matter. The December is in its zone (`~o"2026-12[Europe/Helsinki]"`), and the days and site hours selected from it are too, so they are compared with the sunrise as the instants they are. `Astro.sunrise/3` needs `time_zone:` named unless `tz_world` is a dependency to find the zone from the coordinates. And `DateTime.truncate(:second)` keeps sunrise to the second, as precise as any site schedule needs.

---

## 13. Famous moments in time

A small collection of historically awkward dates — the kind that break naive date libraries. Each recipe shows one thing Tempo does, against a real artefact of history.

### The Ides of March, 44 BCE

```elixir
iex> {:ok, ides} = Tempo.from_iso8601("-0043-03-15")
iex> {Tempo.year(ides), Tempo.month(ides), Tempo.day(ides)}
{-43, 3, 15}
```

> *"The **Ides of March** in the year **-43**."*

ISO 8601 numbers years astronomically — 1 BCE is year 0, 2 BCE is year -1 — so the Ides of March in 44 BCE is in year -43.

### The 1560s as a decade to walk

```elixir
iex> Enum.map(~o"156X", &Tempo.year/1)
[1560, 1561, 1562, 1563, 1564, 1565, 1566, 1567, 1568, 1569]
```

> *"**Some year of the 1560s**, and each year it could be."*

`~o"156X"` is ISO 8601-2's year with an unspecified digit. Archaeological records and historical citations use the form routinely.

### A leap second — spanned, never a value

```elixir
iex> new_year = ~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z"
iex> Tempo.Interval.spans_leap_second?(new_year)
true

iex> Tempo.duration(new_year)
~o"PT120S"

iex> Tempo.duration(new_year, leap_seconds: true)
~o"PT121S"
```

> *"The two minutes around New Year 2017 **span a leap second**: 120 seconds on the clock, 121 elapsed."*

At the end of 2016 UTC a leap second was inserted — the minute 23:59 had 61 seconds, numbered 00 to 60. Tempo reads no `23:59:60` as a *value*, as Elixir's `Time`, `DateTime` and `Calendar.ISO` read none. A leap second is instead a fact about a span: `Tempo.Interval.spans_leap_second?/1`, `Tempo.LeapSeconds.spanned/1`, and the `leap_seconds: true` option of `Tempo.duration/2`. `Tempo.LeapSeconds.dates/0` lists the 27 the IERS has announced.

### A daylight-saving gap — the hour that never was

```elixir
iex> {:error, error} = Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")
iex> Exception.message(error)
"~o\"2024Y3M10DT2H30M0S[America/New_York]\" is a reading the clock of \"America/New_York\" skips"
```

> *"Half past two on the 10th of March is a reading New York's clock **skips**."*

At two in the morning on the second Sunday of March, US clocks jump to three: the hour between never exists. Tempo asks the time zone database as the value is read and refuses a reading in the gap, so nothing downstream meets a phantom instant. The hour shown twice in November is read as the first of the two, or as the one a written shift names.

### Samoa skipping a day, 2011

```elixir
iex> {:error, %Tempo.ZoneError{reason: :gap}} = Tempo.from_iso8601("2011-12-30[Pacific/Apia]")
iex> december = ~o"2011-12[Pacific/Apia]"
iex> thursday = ~o"2011-12-29[Pacific/Apia]"
iex> Tempo.shift(thursday, day: 1)
{:ok, ~o"2011Y12M31D[Pacific/Apia]"}

iex> {:ok, fridays} = Tempo.select(december, ~o"5K")
iex> Tempo.IntervalSet.map(fridays, &Tempo.day/1)
[2, 9, 16, 23]

iex> Enum.count(december)
30
```

> *"The day **after** Thursday the 29th is Saturday the 31st. The **Fridays** of that December are four, where the calendar shows five; and the month has **thirty days**."*

At the end of 29 December 2011 Samoa moved from east of the international date line to west of it, and 30 December never happened there. The day, any hour of it and any timestamp in it are refused, and a step, a walk and a selection pass over it.

### Julian vs Gregorian — the same date written, two days

```elixir
iex> {:ok, julian} = Tempo.from_iso8601("1582-01-01", calendar: Calendrical.Julian)
iex> {:ok, gregorian} = Tempo.from_iso8601("1582-01-01[u-ca=gregory]")
iex> Tempo.overlaps?(julian, gregorian)
false

iex> Tempo.duration(gregorian, julian)
{:ok, ~o"P10D"}
```

> *"The 1st of January 1582 on the **Julian** calendar is **ten days after** the same date on the **Gregorian**."*

The calendar is part of the value, so the same numbers in two calendars are the two days they are.

### How do I work in a fiscal year?

```elixir
iex> {:ok, us_fiscal} = Calendrical.FiscalYear.calendar_for(:US)
iex> {:ok, fiscal_2026} = Tempo.from_iso8601("2026", calendar: us_fiscal)
iex> Enum.count(fiscal_2026)
12

iex> Tempo.relation(Tempo.from_iso8601!("2026-01-01", calendar: us_fiscal), ~o"2025-10-01")
:equals
```

> *"**Fiscal 2026** has twelve months to walk, and its first day **is** the 1st of October 2025."*

The US federal fiscal year begins on 1 October. A fiscal calendar is a Calendrical calendar like any other, so every relation, length and set operation knows it. See the [custom calendars guide](custom-calendars.md).

### Allen's interval algebra

```elixir
iex> Tempo.relation(~o"2022-06", ~o"2022-07")
:meets

iex> Tempo.relation(~o"2022-06", ~o"2022-06-15")
:contains

iex> Tempo.relation(~o"2022-06", ~o"2023-06")
:precedes
```

> *"June **meets** July. June **contains** its 15th. June 2022 **precedes** June 2023."*

Two intervals stand in exactly one of thirteen relations — [Allen's interval algebra](https://ics.uci.edu/~alspaugh/cls/shr/allen.html). The relation is always exact, with no tolerance to tune.

---

## Related reading

* [When to use Tempo](./when-to-use-tempo.md) — a short decision guide on choosing between Tempo and the Elixir standard library.

* [Scheduling](./scheduling.md) — bounded enumeration, wall-clock-vs-UTC authority, floating vs zoned events, and how future dates survive zone-rule changes.

* [Working with workdays and weekends](./workdays-and-weekends.md) — business-day queries (N days from today, next workday, workdays between two dates) built from `Tempo.workdays/1` and set algebra.

* [Holidays — planning with a real holiday calendar](./holidays.md) — fetch an ICS holiday feed, parse it with `Tempo.ICal.parse/1`, and compose it with `Tempo.workdays/1` for territory-aware scheduling.

* [Falsehoods programmers believe about time](./falsehoods.md) — eleven wrong assumptions with the largest bug-surface, each with the Tempo idiom that makes the right behaviour automatic.

* [ISO 8601 conformance](./iso8601-conformance.md) — what's supported from the standard.

* [Enumeration semantics](./enumeration-semantics.md) — how iteration works across Tempo values.

* [Set operations](./set-operations.md) — union, intersection, complement, difference.

* [iCalendar integration](./ical-integration.md) — full `.ics` import with RRULE/RDATE/EXDATE.

* [One form for ISO 8601 and RRULE](./shared-ast-iso8601-and-rrule.md) — how a rule and an ISO 8601 recurrence are the same expression.
