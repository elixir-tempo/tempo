# Tempo Cookbook

Task-oriented recipes for common time-and-calendar problems. Each recipe states the problem, shows the solution, and explains why it works. Copy, adapt, iterate.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in. In `iex`, paste it once and every subsequent snippet runs against it.

---

## Contents

1. [Parsing and construction](#1-parsing-and-construction)
2. [Exploring a value](#2-exploring-a-value)
3. [Iteration](#3-iteration)
4. [Comparison and predicates](#4-comparison-and-predicates)
5. [Set operations](#5-set-operations)
6. [Selecting sub-spans with `Tempo.select/2`](#6-selecting-sub-spans-with-tempo-select-2)
7. [Recurring events (RRULE)](#7-recurring-events-rrule)
8. [iCalendar import](#8-icalendar-import)
9. [Cross-calendar and cross-timezone](#9-cross-calendar-and-cross-timezone)
10. [Archaeological / approximate dates](#10-archaeological-approximate-dates)
11. [Chronological networks](#11-chronological-networks)
12. [Scheduling](#12-scheduling)
13. [Real-world scenarios](#13-real-world-scenarios)
14. [Famous moments in time](#14-famous-moments-in-time)

---

## 1. Parsing and construction

### How do I parse an ISO 8601 date?

```elixir
iex> ~o"2026-06-15"
~o"2026Y6M15D"
```

The sigil output uses ISO 8601-2's unit-suffix form (`Y`/`M`/`D`/`H`/…) which disambiguates months from minutes.

### How do I convert an Elixir `Date`, `Time`, `NaiveDateTime`, or `DateTime` to a Tempo?

```elixir
iex> Tempo.from_elixir(~D[2026-06-15])
~o"2026Y6M15D"

iex> Tempo.from_elixir(~U[2026-06-15 10:30:00Z])
~o"2026Y6M15DT10H30M0SZ[Etc/UTC]"   # second resolution, zone_id "Etc/UTC"
```

`from_elixir/2` accepts a `:resolution` option when you want to coarsen or extend the inferred one.

### How do I express a duration?

```elixir
iex> ~o"P1Y6M"
~o"P1Y6M"

iex> ~o"P1Y6M".time
[year: 1, month: 6]
```

### How do I express an interval between two dates?

```elixir
iex> ~o"2026-06-01/2026-06-30"
~o"2026Y6M1D/2026Y6M30D"
```

Tempo uses the half-open `[from, to)` convention. Adjacent intervals concatenate cleanly.

### How do I say "approximately 2022" or "uncertain 1984"?

```elixir
iex> ~o"2022~"
# Approximate 2022

iex> ~o"1984?"
# Uncertain 1984

iex> ~o"1984%"
# Both uncertain and approximate (equivalent to ISO 8601-2 `%`)
```

The qualification is stored on the value's `:qualification` field; the span stays the same calendar year.

---

### How do I mark just *part* of a date as uncertain?

The **position** of the `?` / `~` / `%` decides its scope, following ISO 8601-2 §8:

```elixir
# LEFT of a component → that component only (individual)
iex> Tempo.from_iso8601!("2004-?06-11").qualifications
%{month: :uncertain}

# RIGHT of a component → that component AND every coarser one (group)
iex> Tempo.from_iso8601!("2004-06~-11").qualifications
%{year: :approximate, month: :approximate}

# At the very END → the whole value (complete)
iex> Tempo.from_iso8601!("2004-06-11~").qualification
:approximate
```

So `2004-06~-11` reads as *"approximately June 2004, on the 11th"* — the `~` sits to the right of the month, so it covers the month **and the year it belongs to**, but not the day. Per-component qualifiers land on the `:qualifications` map (keyed by unit); a whole-value qualifier on `:qualification`. The span is unchanged either way — the marker is metadata, not a widening of the date.

The full rule — group / individual / complete, the explicit `2004~Y6~M11D` form, and how it round-trips — is in the [ISO 8601 conformance guide](iso8601-conformance.md#component-qualification-iso-8601-2-8).

---

## 2. Exploring a value

### How do I see what a value represents?

```elixir
iex> Tempo.explain(~o"156X")
"""
A masked year spanning the 1560s.
Span: [1560-01-01, 1570-01-01).
Iterates at :month granularity.
Materialise as an interval with `Tempo.to_interval/1`.
"""
```

`Tempo.explain/1` returns a plain string. For structured output (HTML, terminal colour) call `Tempo.Explain.explain/1` which returns a `%Tempo.Explanation{}` with tagged parts — `Tempo.Explain.to_string/1`, `to_ansi/1`, and `to_iodata/1` format it for different surfaces.

### How do I see the concrete bounds of an implicit interval?

```elixir
iex> {:ok, iv} = Tempo.to_interval(~o"2026-06")
iex> {from, to} = Tempo.Interval.endpoints(iv)
iex> {Tempo.year(from), Tempo.month(from), Tempo.day(from), Tempo.year(to), Tempo.month(to), Tempo.day(to)}
{2026, 6, 1, 2026, 7, 1}
```

Every Tempo value *is* an interval. `to_interval/1` materialises the implicit span into explicit `from`/`to` endpoints.

### How do I check a value's resolution?

```elixir
iex> Tempo.resolution(~o"2026-06-15")
{:day, 1}
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

A year iterates at month granularity — the next-finer unit below what's specified.

### How do I list every day of a month?

```elixir
iex> Enum.take(~o"2026-06", 30) |> length()
30
```

### How do I list every year in the 1560s?

```elixir
iex> Enum.take(~o"156X", 5)
[~o"1560Y", ~o"1561Y", ~o"1562Y", ~o"1563Y", ~o"1564Y"]
```

The `X` mask is interpreted as "any digit." Enumeration walks the concrete years the mask represents.

### How do I step by a non-default unit?

Wrap the value in an explicit interval with the resolution you want:

```elixir
iex> interval = ~o"2026-06-01/2026-07-01"
# Iterates at day resolution (the boundaries' resolution).
iex> Enum.take(interval, 3)
# First three days of June
```

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

Named predicates cover the common one-shot checks:

| Predicate | Maps to |
|---|---|
| `Tempo.before?(a, b)` | `:precedes` — ends with a gap before b |
| `Tempo.after?(a, b)` | `:preceded_by` |
| `Tempo.meets?(a, b)` | `:meets` — ends exactly at b's start |
| `Tempo.adjacent?(a, b)` | `:meets \| :met_by` — touches, no gap |
| `Tempo.during?(a, b)` | `:during` — strictly inside |
| `Tempo.within?(a, b)` | `:equals \| :starts \| :during \| :finishes` — fits inside, inclusive |

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
iex> iv = ~o"2026-06-15T09/2026-06-15T11"
iex> Tempo.duration(iv)
~o"PT7200S"
```

Returns `:infinity` when one or both endpoints are `:undefined`.

### How do I check an interval's length against a duration?

Five predicates cover the comparison lattice:

```elixir
iv = ~o"2026-06-15T09/2026-06-15T10"

Tempo.at_least?(iv, ~o"PT1H")      # true — length ≥ 1h
Tempo.exactly?(iv, ~o"PT1H")       # true — length == 1h
Tempo.at_most?(iv, ~o"PT1H")       # true — length ≤ 1h
Tempo.longer_than?(iv, ~o"PT30M")  # true — strict >
Tempo.shorter_than?(iv, ~o"PT2H")  # true — strict <
```

### How do I compare two values across different calendars?

```elixir
iex> {:ok, hebrew} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
iex> hebrew.calendar
Calendrical.Hebrew

iex> Tempo.overlaps?(hebrew, ~o"2026-06-15")
true
```

The IXDTF `[u-ca=NAME]` suffix swaps the value's calendar to the corresponding `Calendrical.*` module — `hebrew`, `islamic-umalqura`, `persian`, `buddhist`, and the rest. See `Calendrical.supported_cldr_calendar_types/0` for the full list. Cross-calendar comparisons then convert operands to a shared reference automatically.

---

## 5. Set operations

### How do I merge two overlapping intervals into one?

```elixir
iex> a = ~o"2026-06-01/2026-06-15"
iex> b = ~o"2026-06-10/2026-06-20"
iex> {:ok, both} = Tempo.union(a, b)
iex> Tempo.IntervalSet.count(both)
2                                    # union is member-preserving — both intervals survive
iex> merged = Tempo.IntervalSet.coalesce(both)
iex> Tempo.IntervalSet.count(merged)
1                                    # June 1 .. June 20 after coalescing
```

`Tempo.union/2` keeps both members so each event's identity and metadata survive. When you want the merged-span shape, call `Tempo.IntervalSet.coalesce/1` explicitly.

### How do I find the overlap between two intervals?

```elixir
iex> {:ok, overlap} = Tempo.intersection(a, b)
iex> [span] = Tempo.IntervalSet.to_list(overlap)
iex> {from, to} = Tempo.Interval.endpoints(span)
iex> {Tempo.day(from), Tempo.day(to)}
{10, 15}
```

### How do I subtract a busy period from a free window?

```elixir
work_day = ~o"2026-06-15T09/2026-06-15T17"
lunch    = ~o"2026-06-15T12/2026-06-15T13"

{:ok, free} = Tempo.difference(work_day, lunch)
```

> The **workday minus lunch** is my **free** time — two intervals, 09:00-12:00 and 13:00-17:00.

### How do I compose free/busy across a real schedule?

<!-- guides:skip -->

```elixir
{:ok, schedule} = Tempo.ICal.from_ical_file("~/work.ics")

work = ~o"2026-06-15T09/2026-06-15T17"
{:ok, free} = Tempo.difference(work, schedule)
```

> **Work** minus **my schedule** gives me **free** time that day.

Each free-time fragment carries the workday's metadata (the A-operand). To trace which meeting caused each gap, query the schedule directly with `Tempo.members_overlapping/2`.

### How do I get the symmetric difference (everything in A or B but not both)?

```elixir
iex> {:ok, set} = Tempo.symmetric_difference(a, b)
```

---

## 6. Selecting sub-spans with `Tempo.select/2`

`Tempo.select/2` narrows a base span (a Tempo, an Interval, or an IntervalSet) by a **selector** and returns the matched spans as a `{:ok, %Tempo.IntervalSet{}}` tuple. The same vocabulary covers territory-aware queries (via `Tempo.workdays/1` and `Tempo.weekend/1`), integer indices at the next-finer unit, and projection of a Tempo or Interval onto a larger base.

`Tempo.select/2` is a **pure function** — no ambient territory, no hidden options. Locale-dependent constraints are constructed by `Tempo.workdays/1` and `Tempo.weekend/1` (which resolve the territory once at construction time) and composed in at the call site.

### How do I select the workdays of a month?

```elixir
iex> {:ok, workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
iex> Tempo.IntervalSet.count(workdays)
22
```

> **Workdays** of **June 2026** in the **United States** are Monday through Friday — 22 day-resolution intervals.

### How do I pick specific days inside a month?

```elixir
iex> {:ok, paydays} = Tempo.select(~o"2026-06", [1, 15])
iex> Tempo.IntervalSet.map(paydays, &Tempo.day/1)
[1, 15]
```

> **Integer selectors** apply at the **next-finer unit** below the base's resolution — on a month base that's day, on a year base it's month. A `Range` works too: `Tempo.select(~o"2026-06", 10..15)`.

### How do I project a date pattern onto a larger base?

```elixir
iex> {:ok, set} = Tempo.select(~o"2026", ~o"12-25")
iex> [xmas] = Tempo.IntervalSet.to_list(set)
iex> {Tempo.year(xmas), Tempo.month(xmas), Tempo.day(xmas)}
{2026, 12, 25}
```

> **Project** the constraint `12-25` onto the base year — Dec 25 of 2026. A list of constraints works the same: `Tempo.select(~o"2026", [~o"07-04", ~o"12-25"])` yields both US holidays.

### How do I select a different territory's weekend?

```elixir
iex> {:ok, sa_weekend} = Tempo.select(~o"2026-02", Tempo.weekend(:SA))
iex> Tempo.IntervalSet.map(sa_weekend, &Tempo.day/1)
[6, 7, 13, 14, 20, 21, 27, 28]
```

> Saudi Arabia's **weekend** is **Friday + Saturday**. `Tempo.weekend/1` and `Tempo.workdays/1` accept a territory atom (`:SA`), a territory string (`"SA"`, `"sazzzz"`), a locale string (`"ar-SA"`), or a `%Localize.LanguageTag{}`. With no argument they use the ambient resolution chain: `Application.get_env(:ex_tempo, :default_territory)` → `Localize.get_locale()`.

Pass a full locale when you have one rather than the territory:

```elixir
iex> {:ok, sa_weekend} = Tempo.select(~o"2026-02", Tempo.weekend("ar-SA"))
iex> Tempo.IntervalSet.map(sa_weekend, &Tempo.day/1)
[6, 7, 13, 14, 20, 21, 27, 28]
```

### How do I compose select with the set operations?

```elixir
{:ok, june_workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
{:ok, vacation} = Tempo.to_interval_set(~o"2026-06-15/2026-06-20")
{:ok, available} = Tempo.difference(june_workdays, vacation)
```

> **US workdays** of June **minus** my **vacation** yields the workdays I'm **available**. Because `select/2` returns an IntervalSet, it drops straight into `union/2`, `intersection/2`, `difference/2`, and `symmetric_difference/2`.

### How do I use a function as a selector?

```elixir
holidays = fn _base -> [~o"01-01", ~o"07-04", ~o"12-25"] end
{:ok, set} = Tempo.select(~o"2026", holidays)
```

> **Function selectors** receive the base and return any selector shape (list of Tempos here). This is the extension point for user-defined holiday calendars, business rules, or anything else you want to compute from the base.

### How do I pick "the last X of Y"?

ISO 8601-2 §4.4.1 allows any component to be negative, meaning "count from the end of the containing unit". Negative components flow straight through `Tempo.select/2` — no string arithmetic, no `days_in_month/2` calls, no calendar branches:

```elixir
iex> {:ok, last_month} = Tempo.select(~o"2026", ~o"-1M")
iex> Tempo.Interval.from(Tempo.IntervalSet.first(last_month))
~o"2026Y12M"

iex> {:ok, last_day_of_feb} = Tempo.select(~o"2024-02", ~o"-1D")
iex> Tempo.Interval.from(Tempo.IntervalSet.first(last_day_of_feb))
~o"2024Y2M29D"

iex> {:ok, last_day_of_feb} = Tempo.select(~o"2026-02", ~o"-1D")
iex> Tempo.Interval.from(Tempo.IntervalSet.first(last_day_of_feb))
~o"2026Y2M28D"
```

> **`-1M`** on a year base is the **last month**. **`-1D`** on a month base is the **last day of that month** — **leap-aware** (Feb 29 in 2024, Feb 28 in 2026). **`-1W`** on a year base is the **last ISO week** (52 or 53 depending on year).

The resolution is axis-aware: `-1W` on a month base gives the last week-of-month (4 or 5), while on a year base it gives the last ISO week-of-year (52 or 53). `-1O` (ordinal) on a year base is the year's last day; `-1K` is the week's last day-of-week.

Time-of-day units work the same way. `~o"-1H"` is hour 23, `~o"T-1M"` is minute 59, `~o"T-1S"` is second 59:

```elixir
iex> {:ok, last_hour} = Tempo.select(~o"2026-06-15", ~o"-1H")
iex> last_hour |> Tempo.IntervalSet.first() |> Tempo.Interval.from()
~o"2026Y6M15DT23H"

iex> {:ok, last_minute} = Tempo.select(~o"2026-06-15T14", ~o"T-1M")
iex> last_minute |> Tempo.IntervalSet.first() |> Tempo.Interval.from()
~o"2026Y6M15DT14H59M"
```

> **`~o"-1M"`** is always **month** (last month of year). Use **`~o"T-1M"`** — with the `T` time designator — to select **minute-of-hour**. The bare-form `M` belongs to the date axis; the `T`-prefixed form belongs to time-of-day.

Negative components compose with the rest of the selector vocabulary — `Tempo.select(~o"2026", [~o"-1D", ~o"12-25"])` projects *both* "last day of year" and "Christmas" onto 2026, yielding Dec 25 and Dec 31 as separate members.

### How do I express business hours across a quarter?

An interval selector projects as a **span** — the coarser units come from each base member, the finer units from the selector's endpoints — so a time-of-day window applies to every day in one expression. A list gives several windows per day:

```elixir
iex> {:ok, workdays} = Tempo.select(~o"2026-07/2026-10", Tempo.workdays(:AU))
iex> {:ok, open} = Tempo.select(workdays, [~o"T09/T12", ~o"T13/T17"])
iex> Tempo.IntervalSet.count(open)
132
iex> Tempo.Duration.to_unit(Tempo.IntervalSet.total_duration(open), :hour)
{:ok, 462.0}
```

> *"The **workdays** of the quarter, **nine to five** with an **hour for lunch**"* — 66 days, two windows each, 462 open hours. Bounds are half-open throughout Tempo, so nine-to-five is written as nine to five: `~o"T09/T17"` is eight hours, no off-by-one, no `coalesce/1`.

Subtract the public holidays with `Tempo.members_outside(open, holidays)` and the result is still one pipeline. A window that is not hour-aligned uses the duration form — `~o"T09/PT7H36M"` is a statutory 7.6-hour day — and a window crossing midnight rolls its end to the following day: `~o"T21/T05"` is the night shift a roster writes.

See `Tempo.Select` for the full selector vocabulary.

---

## 7. Recurring events (RRULE)

An RRULE parses into a recurring `%Tempo.Interval{}` with `Tempo.RRule.parse!/2`; you materialise it into occurrences with `Tempo.to_interval/2`, limited by a `:bound` window or by the rule's own `COUNT`/`UNTIL`. (A plain periodic cadence with no calendar filter needs no RRULE at all — build it directly with `Tempo.Interval.new!(from: ~o"2026-06-01", duration: ~o"P1W", recurrence: 10)`; see the [scheduling guide](./scheduling.md).)

### How do I express "every Monday for 10 weeks"?

```elixir
iex> recurrence = Tempo.RRule.parse!("FREQ=WEEKLY;BYDAY=MO;COUNT=10", from: ~o"2026-06-01")
iex> {:ok, set} = Tempo.to_interval(recurrence)
iex> Tempo.IntervalSet.count(set)
10
```

### How do I express "the 4th Thursday of November" (Thanksgiving)?

```elixir
iex> recurrence = Tempo.RRule.parse!("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=5", from: ~o"2022-11-24")
iex> {:ok, set} = Tempo.to_interval(recurrence)
iex> Enum.map(Tempo.IntervalSet.to_list(set), &Tempo.day(Tempo.Interval.from(&1)))
[24, 23, 28, 27, 26]
```

Positive ordinals count from the start of the period; negatives count from the end (`-1FR` = last Friday).

### How do I express "every Friday the 13th"?

```elixir
iex> recurrence = Tempo.RRule.parse!("FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR;COUNT=10", from: ~o"1998-02-13")
iex> {:ok, set} = Tempo.to_interval(recurrence)
iex> Tempo.IntervalSet.count(set)
10
```

When `BYMONTHDAY` is co-present, `BYDAY` becomes a filter (per RFC Note 1) — `BYMONTHDAY=13` picks day 13 of each month, then `BYDAY=FR` keeps only the Fridays.

### How do I express US Presidential Election Day?

"Every four years, the first Tuesday after a Monday in November":

```elixir
iex> recurrence =
...>   Tempo.RRule.parse!(
...>     "FREQ=YEARLY;INTERVAL=4;BYMONTH=11;BYDAY=TU;BYMONTHDAY=2,3,4,5,6,7,8;COUNT=3",
...>     from: ~o"1996-11-05"
...>   )
iex> {:ok, set} = Tempo.to_interval(recurrence)
iex> Enum.map(Tempo.IntervalSet.to_list(set), fn iv ->
...>   start = Tempo.Interval.from(iv)
...>   {Tempo.year(start), Tempo.day(start)}
...> end)
[{1996, 5}, {2000, 7}, {2004, 2}]
```

### How do I express "last weekday of every month"?

```elixir
iex> recurrence = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3", from: ~o"2026-06-01")
iex> {:ok, set} = Tempo.to_interval(recurrence)
iex> Tempo.IntervalSet.count(set)
3
```

`BYDAY=MO,TU,WE,TH,FR` expands each month to all weekdays; `BYSETPOS=-1` picks the last.

### How do I handle an unbounded rule?

Supply `:bound`:

```elixir
iex> recurrence = Tempo.RRule.parse!("FREQ=DAILY", from: ~o"2026-06-01")  # No COUNT, no UNTIL
iex> {:ok, set} = Tempo.to_interval(recurrence, bound: ~o"2026-06")
iex> Tempo.IntervalSet.count(set)
30
```

---

## 8. iCalendar import

### How do I import an `.ics` file?

<!-- guides:skip -->

```elixir
iex> {:ok, schedule} = Tempo.ICal.from_ical_file("~/work.ics")
iex> Tempo.IntervalSet.count(schedule)
# One interval per VEVENT (or per materialised recurrence occurrence).
```

Each event becomes a `%Tempo.Interval{}` with full metadata (summary, location, attendees, …) attached to `:metadata`.

### How do I import an `.ics` that contains recurring events?

Pass a `:bound` so unbounded recurrences terminate:

<!-- guides:skip -->

```elixir
iex> {:ok, schedule} = Tempo.ICal.from_ical(ics, bound: ~o"2026-04-01/2026-07-01")
```

Every RRULE part (including BY-rules, BYSETPOS, WKST, RDATE, EXDATE) materialises correctly — one `%Tempo.Interval{}` per occurrence carrying the event's metadata.

### How do I find when a specific attendee is in a meeting?

<!-- guides:skip -->

```elixir
{:ok, schedule} = Tempo.ICal.from_ical(ics)

ada_meetings =
  schedule
  |> Tempo.IntervalSet.to_list()
  |> Enum.filter(fn meeting ->
    "ada@example.com" in (Tempo.Interval.metadata(meeting)[:attendees] || [])
  end)
```

> **Ada's meetings** are every event in the **schedule** whose **attendees** include her.

Metadata rides through any downstream set operation — after `intersection/difference/union`, you can still trace each result fragment to its originating event.

---

## 9. Cross-calendar and cross-timezone

### How do I compare a Hebrew date to a Gregorian one?

```elixir
hebrew    = Tempo.new!(year: 5786, month: 10, day: 30, calendar: Calendrical.Hebrew)
gregorian = ~o"2026-06-15"

Tempo.overlaps?(hebrew, gregorian)
#=> true
```

> The **Hebrew date** 5786-10-30 **overlaps** the **Gregorian date** 2026-06-15 — they're the same day.

### How do I compare across timezones?

```elixir
paris      = Tempo.from_elixir(DateTime.new!(~D[2026-06-15], ~T[10:00:00], "Europe/Paris"))
utc_window = ~o"2026-06-15T07/2026-06-15T09Z"

Tempo.overlaps?(paris, utc_window)
#=> true
```

> **Paris 10:00 CEST** **overlaps** the **UTC 07:00-09:00 window** — it projects to UTC 08:00, which is inside.

Tempo projects to UTC via the configured time zone database for cross-zone comparisons. The wall-clock representation on the struct is preserved; the projection happens per-call.

### How do I convert a Tempo to a specific calendar?

```elixir
iex> {:ok, hebrew} = Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)
iex> {Tempo.year(hebrew), Tempo.month(hebrew), Tempo.day(hebrew)}
{5786, 10, 30}
```

### How do I get a fiscal quarter from the calendar that defines it?

Calendrical's period functions answer *"which days are in this quarter?"* in any calendar — fiscal, retail, academic — and return an inclusive `Date.Range`. `Tempo.from_elixir/2` (or the named `Tempo.from_date_range/2`) converts it to a half-open interval covering exactly those days, with the calendar preserved:

```elixir
iex> {:ok, calendar} = Calendrical.FiscalYear.calendar_for(:AU)
iex> {:ok, quarter} = Tempo.from_elixir(calendar.quarter(2027, 1))
iex> {:ok, workdays} = Tempo.select(quarter, Tempo.workdays(:AU))
iex> Tempo.IntervalSet.count(workdays)
66
```

> *"The first quarter of Australian financial year 2027 has **66 working days**"* — including the quarter's final day, which a hand-written `range.first`-to-`range.last` interval silently drops (the inclusive/half-open off-by-one this conversion exists to prevent). The literal alternative, `~o"2026-07-01/2026-10-01"`, encodes the fiscal boundary by hand — right when written, wrong the year the rules change; the calendar itself says which days it is.

Fiscal values compose with Gregorian ones directly — `Tempo.relation(Tempo.Interval.from(quarter), ~o"2026-07-01")` is `:equals` — so nothing needs converting before the set algebra. A stepped or descending `Date.Range` is refused rather than guessed: it enumerates a set of days, not a span.

---

## 10. Archaeological / approximate dates

### How do I say "sometime in the 1560s"?

```elixir
iex> ~o"156X"
# Decade mask — spans 1560-01-01 .. 1570-01-01.
```

### How do I say "the 15th of every month in 1985"?

```elixir
iex> {:ok, set} = Tempo.to_interval(~o"1985-XX-15")
iex> Tempo.IntervalSet.count(set)
12
```

A non-contiguous mask (masked month, concrete day) expands to one interval per valid month.

### How do I move an approximate date?

Arithmetic shifts the whole block. A block-aligned shift stays a mask; a misaligned one gives the exact candidate values; and a mask with a concrete component after it — which denotes *disjoint* spans — gives an `IntervalSet`.

```elixir
iex> Tempo.shift(~o"156X", ~o"P10Y")
# The 1560s a decade on — still a decade mask: ~o"157X".

iex> Tempo.shift(~o"156X", ~o"P1Y")
# One year isn't a clean decade, so the ten candidate years: ~o"[1561Y..1570Y]".

iex> Tempo.shift(~o"156X-06-XX", ~o"P1Y") |> Tempo.IntervalSet.count()
# The Junes of the 1560s, a year on — ten disjoint month spans: 10.
```

### How do I express an open-ended interval?

```elixir
iex> ~o"1985/.."
# From 1985 onward, no end.

iex> ~o"../2024"
# No start, ending 2024.

iex> ~o"../.."
# Fully open.
```

### How do I attach a qualifier to a single endpoint?

```elixir
iex> ~o"1984?/2004~"
# Uncertain lower bound, approximate upper bound.
```

Each endpoint carries its own `:qualification` in addition to any expression-level one.

---

## 11. Chronological networks

`Tempo.Network` reasons over periods whose start, end, and duration are only partly known: give each its bounds (exact, ranged, or one-sided), link them with sequences and relations like `:starts_during` or `:overlaps`, and the solver returns the tightest dates consistent with everything — or flags a contradiction. The [Chronological networks guide](chronological-networks.md) covers it in full, including traces that explain each derived bound.

### How do I derive dates from partial constraints?

```elixir
iex> network =
...>   Tempo.Network.new()
...>   |> Tempo.Network.add_period(:reign, start: {:not_before, ~o"1200Y"}, duration: {:at_most, ~o"P10Y"})
...>   |> Tempo.Network.add_period(:stratum, duration: {:at_least, ~o"P20Y"})
...>   |> Tempo.Network.add_relation(:starts_during, :stratum, :reign)
iex> {:ok, solved} = Tempo.Network.Solver.tighten(network)
iex> solved.periods[:stratum].earliest_end
~o"1220Y"
```

The stratum has no dates of its own, but *"it began during a reign that started no earlier than 1200, and it lasted at least 20 years"* forces it to end no earlier than 1220. Every bound comes back as a Tempo value.

### How do I check a chronology for contradictions?

```elixir
iex> Tempo.Network.new()
...> |> Tempo.Network.add_period(:k, start: ~o"1200Y", end: ~o"1180Y")
...> |> Tempo.Network.Solver.consistent?()
false
```

`consistent?/1` is `true` when at least one assignment of dates satisfies every constraint at once — here it's `false`, since a period can't end before it starts.

### How do I tell whether two periods could overlap?

Two pottery phases dated only to overlapping windows — nothing forces them together or apart:

```elixir
iex> network =
...>   Tempo.Network.new()
...>   |> Tempo.Network.add_period(:phase_a, start: {:not_before, ~o"1200Y"}, end: {:not_after, ~o"1260Y"})
...>   |> Tempo.Network.add_period(:phase_b, start: {:not_before, ~o"1250Y"}, end: {:not_after, ~o"1300Y"})
iex> Tempo.Network.Solver.contemporaneity(network, :phase_a, :phase_b)
:possible
```

`contemporaneity/3` reads the tightened network and answers three ways — `:certain` (every consistent chronology has them overlapping), `:possible` (some do, some don't), or `:impossible` (none do) — so *"could these two phases have been in use at the same time?"* gets a graded answer, not a guess. `certainly_contemporary?/3` and `possibly_contemporary?/3` are the boolean shortcuts.

---

## 12. Scheduling

`Tempo.Schedule` is critical-path project planning built on `Tempo.Network`: declare tasks with durations and finish-to-start dependencies (plus optional anchors and deadlines), then `solve/1` for each task's earliest/latest position and its critical-path flag. See the [Scheduling guide](scheduling.md).

### How do I schedule tasks with dependencies?

```elixir
iex> {:ok, plan} =
...>   Tempo.Schedule.new()
...>   |> Tempo.Schedule.task(:design, duration: ~o"P2D", start: ~o"2026-06-01")
...>   |> Tempo.Schedule.task(:build,  duration: ~o"P3D", after: :design)
...>   |> Tempo.Schedule.task(:docs,   duration: ~o"P1D", after: :design)
...>   |> Tempo.Schedule.task(:ship,   duration: ~o"P2D", after: [:build, :docs])
...>   |> Tempo.Schedule.solve()
iex> plan[:ship].start
~o"2026Y6M6D"
```

Each task lands at its earliest feasible position. `ship` waits for both `build` and `docs`, so it can't begin until `build` finishes on the 6th — even though `docs` was done on the 4th.

### How do I find the critical path?

```elixir
iex> Tempo.Schedule.critical_path(plan)
[:design, :build, :ship]
iex> plan[:docs].critical?
false
```

The critical path is the zero-slack chain — delay any of those tasks and the whole project slips. `docs` has slack, so it sits off the path.

### How do I catch an impossible deadline?

```elixir
iex> Tempo.Schedule.new()
...> |> Tempo.Schedule.task(:a, duration: ~o"P5D", start: ~o"2026-06-01")
...> |> Tempo.Schedule.task(:b, duration: ~o"P5D", after: :a, deadline: ~o"2026-06-08")
...> |> Tempo.Schedule.solve()
{:error, :infeasible}
```

`a` then `b` need ten days from June 1 but `b` is due the 8th, so `solve/1` returns `{:error, :infeasible}` (a dependency cycle is reported the same way).

---

## 13. Real-world scenarios

### Find every Friday the 13th this century

```elixir
friday_the_13th =
  Tempo.RRule.parse!("FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR", from: ~o"2000-01-01")

century = ~o"2000-01-01/2100-01-01"

{:ok, occurrences} = Tempo.to_interval(friday_the_13th, bound: century)
```

> **Friday the 13th** is a monthly rule — Fridays whose day-of-month is 13. **Expanding** the rule across the **century** gives every occurrence.

### Find when two people are both free for at least 1 hour

<!-- guides:skip -->

```elixir
{:ok, ada}   = Tempo.ICal.from_ical_file("~/ada.ics")
{:ok, grace} = Tempo.ICal.from_ical_file("~/grace.ics")

work = ~o"2026-06-15T09/2026-06-15T17"

{:ok, ada_free}   = Tempo.difference(work, ada)
{:ok, grace_free} = Tempo.difference(work, grace)
{:ok, mutual}     = Tempo.intersection(ada_free, grace_free)

slots =
  mutual
  |> Tempo.IntervalSet.to_list()
  |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))
```

> Ada's free time is the workday **minus** her busy periods. Grace's is the same. **Mutual** free time is the **intersection** of theirs. **Slots** are the mutual windows **at least an hour** long.

### List every bookable 1-hour slot two people share

```elixir
mutual                                  # the mutual free time from above
|> Tempo.IntervalSet.slots(~o"PT1H")    # cut into back-to-back 1-hour slots
|> Tempo.IntervalSet.to_list()
```

> Where the recipe above gives the free **windows**, `slots/2` cuts each window into the discrete **1-hour slots** a booking page would actually offer. Pass `every: ~o"PT30M"` to start a slot on every half-hour (overlapping), or a larger `:every` to leave gaps between offered times.

### Which of these candidate meeting times can I book?

```elixir
candidates = [
  ~o"2026-06-15T09/2026-06-15T10",
  ~o"2026-06-15T11/2026-06-15T12",
  ~o"2026-06-15T16/2026-06-15T17"
]

bookable =
  Enum.filter(candidates, fn candidate ->
    Enum.any?(Tempo.IntervalSet.to_list(mutual), &Tempo.within?(candidate, &1))
  end)
```

> A **candidate** is **bookable** if **any** mutual free window **contains** it.

### How do I check if a dig layer overlaps a historical period?

```elixir
dig_layer    = ~o"1520/1590"
ming_period  = ~o"1368/1644"

Tempo.overlaps?(dig_layer, ming_period)
#=> true
```

> The **dig layer overlaps** the **Ming period** — the site was in use during the dynasty.

### How do I find free time across multiple schedules and timezones?

<!-- guides:skip -->

```elixir
{:ok, ny}     = Tempo.ICal.from_ical_file("~/cal_ny.ics")
{:ok, london} = Tempo.ICal.from_ical_file("~/cal_london.ics")

work = ~o"2026-06-15T09/2026-06-15T17"

{:ok, ny_free}   = Tempo.difference(work, ny)
{:ok, free}      = Tempo.difference(ny_free, london)
```

> **Work** minus **New York's busy times** gives one person's free window; that **minus London's busy times** gives the cross-timezone **free** slots. Each `difference/2` call projects to UTC internally, so wall-clock mismatches across zones resolve correctly.

### How do I round a datetime to the nearest hour?

```elixir
iex> Tempo.at_resolution(~o"2026-06-15T10:37:42", :hour)
~o"2026Y6M15DT10H"
```

`at_resolution/2` is the single entry point for normalising to a target unit — coarser uses `trunc/2`, finer uses `extend_resolution/2`.

### How do I generate a list of business days in a month?

```elixir
iex> {:ok, workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
iex> Tempo.IntervalSet.count(workdays)
22
```

> **Workdays** of **June 2026** are Monday through Friday — 22 day-resolution intervals, locale-aware via `Localize.Calendar`. See [§6](#6-selecting-sub-spans-with-tempo-select-2) for the full selector vocabulary and territory-resolution chain.

An RRULE equivalent is available when you need the full rule machinery (byday counts, bymonth filters, intervals greater than 1):

```elixir
weekdays =
  Tempo.RRule.parse!("FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR", from: ~o"2026-06-01")

{:ok, days} = Tempo.to_interval(weekdays, bound: ~o"2026-06")
```

### Business/252 — Brazil's business-day year fraction

Brazilian fixed-income instruments accrue interest on the BUS/252 day count: the year fraction between two dates is the number of business days between them divided by a fixed 252, where a business day is Monday–Friday minus the [ANBIMA](https://www.anbima.com.br/feriados/feriados.asp) national banking holidays. Tempo's half-open `[from, to)` convention is exactly the counting rule BUS/252 requires — two consecutive business days count as 1.

ANBIMA publishes the holiday list (2001–2099) as a spreadsheet; `scripts/anbima_xls_to_ics.py` in this repository converts it to an iCalendar file that Tempo loads directly.

<!-- guides:skip -->

```elixir
{:ok, holidays} = Tempo.ICal.from_ical_file("feriados_anbima.ics")

settlement = ~o"2024-01-01"
maturity   = ~o"2025-01-01"

{:ok, window}        = Tempo.Interval.new(from: settlement, to: maturity)
{:ok, workdays}      = Tempo.select(window, Tempo.workdays(:BR))
{:ok, business_days} = Tempo.members_outside(workdays, holidays)

Tempo.IntervalSet.count(business_days) / 252
#=> 1.003968253968254   (253 business days in 2024)
```

> The **window** runs from settlement to maturity. **Workdays** narrow it to Brazil's Monday–Friday. **Business days** are the workdays falling **outside** the ANBIMA holidays. The **year fraction** is the business-day count over a fixed 252.

The denominator is always 252, regardless of how many business days a given year actually contains — a fraction slightly above 1 for a calendar year is correct, not a bug. And because the holiday list is normative pricing data, pin a dated copy of the generated `.ics` rather than refreshing it from a live feed.

### Ramadan working hours — statutory hours across two calendars

UAE labour law (Article 17 of Federal Decree-Law No. 33 of 2021) reduces the private-sector workday by two hours — from eight to six — for every day of Ramadan, for all employees. The payroll year is Gregorian; Ramadan is the ninth month of the Islamic calendar, and it drifts about eleven days earlier each Gregorian year. Computing statutory hours therefore means intersecting a Gregorian working year with an Islamic month — a set operation *across two calendars*:

```elixir
work_year = ~o"2026"
ramadan   = ~o"1447-09[u-ca=islamic-civil]"

standard_hours = 8
ramadan_hours  = 6

{:ok, workdays}         = Tempo.select(work_year, Tempo.workdays(:AE))
{:ok, ramadan_workdays} = Tempo.members_overlapping(workdays, ramadan)
{:ok, normal_workdays}  = Tempo.members_outside(workdays, ramadan)

Tempo.IntervalSet.count(normal_workdays) * standard_hours +
  Tempo.IntervalSet.count(ramadan_workdays) * ramadan_hours
#=> 2044   (239 normal workdays × 8h + 22 Ramadan workdays × 6h; 44 hours reduced)
```

> The **workdays** of 2026 are the working year narrowed to the UAE's Monday–Friday. The **Ramadan workdays** are the ones **overlapping** Ramadan 1447; the **normal workdays** are the ones **outside** it. **Statutory hours** are eight for each normal workday and six for each Ramadan workday.

Three things are doing quiet work here. `Tempo.workdays(:AE)` knows from CLDR that the UAE moved its weekend to Saturday–Sunday in 2022 — no hand-coded weekday list. The intersection of a Gregorian year with `~o"1447-09[u-ca=islamic-civil]"` converts calendars internally — Ramadan 1447 lands on 2026-02-18 through 2026-03-19 without either value being manually converted. And the two member-preserving filters partition the workdays exactly, so the hours arithmetic cannot double-count a day.

Next year the same pipeline needs only new bindings — `~o"2027"` and `~o"1448-09[u-ca=islamic-civil]"` — and Ramadan moves ten days earlier (2027-02-08 through 2027-03-09) with nothing else changing.

Two production caveats. The tabular `islamic-civil` calendar is a planning approximation: the legal month follows the moon-sighting announcement, so for an actual payroll run pin the announced start and end dates (the same advice as pinning the ANBIMA `.ics` above). And public holidays — Eid al-Fitr immediately follows Ramadan — subtract with `Tempo.members_outside/2` exactly as in the Business/252 recipe.

### The 25-hour shift — DST and payroll

A night-shift worker in New York works 21:00–05:00. On the night the clocks fall back (the first Sunday of November) the 01:00–02:00 hour happens twice, and US wage law pays non-exempt workers for hours *actually worked* — nine hours, not eight. On the spring-forward night the 02:00 hour never exists, and the same shift is seven. Naive `end - start` wall-clock arithmetic gets both wrong; Tempo's hour walk gets both right because the timezone database drives the enumeration:

```elixir
normal      = ~o"2026-10-24T21[America/New_York]/2026-10-25T05[America/New_York]"
fall_back   = ~o"2026-10-31T21[America/New_York]/2026-11-01T05[America/New_York]"
spring_fwd  = ~o"2026-03-07T21[America/New_York]/2026-03-08T05[America/New_York]"

Enum.count(normal)     #=> 8
Enum.count(fall_back)  #=> 9   (01:00 EDT and 01:00 EST both worked — both paid)
Enum.count(spring_fwd) #=> 7   (02:00 never happened)
```

> The **shift** is an explicit hour-resolution interval in the worker's zone. **Counting** its hours walks the wall clock the worker actually lived: the fall-back night contains the 01:00 hour **twice**, the spring-forward night skips 02:00 entirely.

The two occurrences of the repeated hour are distinct values, disambiguated by their UTC offset exactly as RFC 9557 prescribes — the first is `~o"2026Y11M1DT1HZ-4H[America/New_York]"` (EDT), the second `~o"2026Y11M1DT1HZ-5H[America/New_York]"` (EST) — so a payroll record built from the walk round-trips each hour to the correct instant.

### Is the on-call rotation fair?

Three engineers rotate weekly on-call, handing over each Monday, thirteen weeks a quarter. By shift count the rota looks nearly fair — 5 / 4 / 4 weeks. But weekends are what on-call actually costs, and each rotation is written as one set-of-intervals sigil, so the question is one `select` per person:

```elixir
alice = ~o"{2025-12-29/2026-01-05,2026-01-19/2026-01-26,2026-02-09/2026-02-16,2026-03-02/2026-03-09,2026-03-23/2026-03-30}"
bob   = ~o"{2026-01-05/2026-01-12,2026-01-26/2026-02-02,2026-02-16/2026-02-23,2026-03-09/2026-03-16}"
carol = ~o"{2026-01-12/2026-01-19,2026-02-02/2026-02-09,2026-02-23/2026-03-02,2026-03-16/2026-03-23}"

for {name, rota} <- [alice: alice, bob: bob, carol: carol] do
  {:ok, weekend_days} = Tempo.select(rota, Tempo.weekend(:US))
  {name, Tempo.IntervalSet.count(weekend_days)}
end
#=> [alice: 10, bob: 8, carol: 8]   (240 vs 192 vs 192 weekend hours)
```

> Each engineer's **rota** is the set of weeks they carry the pager. Their **weekend burden** is the rota's days **selected** down to Saturdays and Sundays. Alice's five weekends against four make her weekend load **25% heavier** — from a rotation that looked fair by shift count.

The mechanics: a `{a/b,c/d,…}` sigil is a set of explicit intervals; `Tempo.select/2` materialises it and applies the selector to every member, so "the weekend days of Alice's five separate weeks" needs no loop. The counts convert to hours because each selected member is exactly one day.

### Daylight-limited work — Tempo + Astro

Outdoor crews — surveyors, riggers, film units — can only use site hours that are also daylight. How much workable time does a Helsinki crew have in December 2026, against the same crew in Lisbon? Sunrise and sunset come from the [Astro](https://hex.pm/packages/astro) ephemeris; the rest is set algebra:

```elixir
workable_daylight = fn december, territory, location, zone ->
  {:ok, workdays} = Tempo.select(december, Tempo.workdays(territory))

  for day <- workdays do
    {:ok, date}    = Tempo.to_date(day)
    {:ok, sunrise} = Astro.sunrise(location, date, time_zone: zone)
    {:ok, sunset}  = Astro.sunset(location, date, time_zone: zone)

    {:ok, daylight} =
      Tempo.Interval.new(
        from: Tempo.from_elixir(DateTime.truncate(sunrise, :second)),
        to: Tempo.from_elixir(DateTime.truncate(sunset, :second))
      )

    {:ok, site_hours} = Tempo.select(day, 8..15)
    {:ok, workable}   = Tempo.intersection(site_hours, daylight)
    Tempo.duration(workable)
  end
end

{:ok, helsinki_december} = Tempo.from_iso8601("2026-12[Europe/Helsinki]")
{:ok, lisbon_december}   = Tempo.from_iso8601("2026-12[Europe/Lisbon]")

workable_daylight.(helsinki_december, :FI, {24.9384, 60.1699}, "Europe/Helsinki")
# totals 137.8 hours across 23 workdays

workable_daylight.(lisbon_december, :PT, {-9.1393, 38.7223}, "Europe/Lisbon")
# totals 184.0 hours — every site hour is daylit
```

> The **workdays** of a zoned December, each drilled to its 08:00–16:00 **site hours**, **intersected** with that day's **daylight** from the ephemeris, and **totalled**. Lisbon crews get their full 184 site-hours; Helsinki crews get 137.8 — a **34% December capacity gap** from geography alone.

Three details matter. The December value carries its zone (`~o"2026-12[Europe/Helsinki]"`), and `select` propagates it down to the hour members — without it, naive site hours would compare as UTC and shift the overlap by two hours. `Astro.sunrise/3` needs `time_zone:` named explicitly unless `tz_world` is a dependency to resolve zones from coordinates. And the `DateTime.truncate(:second)` keeps sunrise at whole-second resolution, which is as precise as any site schedule needs.

```elixir
{:ok, schedule} = Tempo.ICal.from_ical(ics, bound: ~o"2026-06")

month = ~o"2026-06"
{:ok, free} = Tempo.difference(month, schedule)
```

> The **month** of June **minus** my **schedule** is my **free** time that month.

---

## 14. Famous moments in time

A small collection of historically awkward dates — the kind that break naive date libraries. Each recipe demonstrates a specific Tempo capability against a real artefact of history.

### The Ides of March, 44 BCE

```elixir
iex> {:ok, ides} = Tempo.from_iso8601("-0043-03-15")
iex> {Tempo.year(ides), Tempo.month(ides), Tempo.day(ides)}
{-43, 3, 15}
```

> ISO 8601 uses **astronomical year numbering** — 1 BCE is year 0, 2 BCE is year -1, and so on. The Ides of March in **44 BCE** is therefore year **-43**. Tempo parses this without fuss; negative years are first-class.

### The 1560s as an iterable decade

```elixir
iex> decade = ~o"156X"
iex> Enum.to_list(decade) |> Enum.map(&Tempo.year/1)
[1560, 1561, 1562, 1563, 1564, 1565, 1566, 1567, 1568, 1569]
```

> `~o"156X"` is an **ISO 8601-2 masked year** — "some year in the 1560s." It's both a bounded span (the full decade) and an enumerable sequence of 10 year-values. Archaeological records and historical citations use this form routinely; Tempo gives it a first-class type.

### A leap second — detected, never represented as a value

```elixir
iex> iv = ~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z"
iex> Tempo.Interval.spans_leap_second?(iv)
true

iex> Tempo.Interval.duration(iv)
~o"PT120S"

iex> Tempo.Interval.duration(iv, leap_seconds: true)
~o"PT121S"
```

> At the end of 2016 UTC, a **leap second** was inserted — the minute 23:59 had **61 seconds**, numbered 00 through 60. Tempo rejects `23:59:60` as a *value* (to stay compatible with `Time`, `DateTime`, and `Calendar.ISO` in Elixir/OTP — none of which represent leap seconds). Instead, Tempo exposes leap-second information as **interval metadata** via `Tempo.Interval.spans_leap_second?/1`, `leap_seconds_spanned/1`, and the `leap_seconds: true` option on `duration/2`. Scientific and financial pipelines that need exact elapsed time get a clean API; everyone else gets stdlib interop for free. See `Tempo.LeapSeconds.dates/0` for the 27 IERS-announced insertions.

### A daylight-saving gap — the hour that never was

```elixir
iex> Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")
{:error,
 "Wall time 2024-03-10T02:30:00 does not exist in \"America/New_York\" — it falls inside a daylight-saving or zone-transition gap."}
```

> At 02:00 local time on the second Sunday of March, US clocks **jump to 03:00** — the hour 02:00–03:00 never exists. Tempo consults the time zone database at parse time and rejects wall times inside the gap, so downstream operations never encounter a phantom instant. Fall-back ambiguity (the repeated hour in November) is accepted by default — callers can disambiguate with an explicit offset.

### Samoa skipping the international date line, 2011

```elixir
iex> Tempo.from_iso8601("2011-09-24T12:00:00[Pacific/Apia]")
{:error,
 "Wall time 2011-09-24T12:00:00 does not exist in \"Pacific/Apia\" — it falls inside a daylight-saving or zone-transition gap."}
```

> In 2011, Samoa shifted from east of the international date line to west of it — their timeline **skipped forward 25 hours**. Tempo consults the time zone database for the exact gap boundaries. (Current IANA data has the gap spanning Sep 24 03:00 → Sep 25 04:00 local, 25 hours; the news coverage at the time described the shift as end-of-December 2011. Wherever IANA places the transition, Tempo uses it as authoritative.)

### Julian vs Gregorian — the same nominal date, different calendars

```elixir
iex> {:ok, julian}    = Tempo.from_iso8601("1582-01-01", Calendrical.Julian)
iex> {:ok, gregorian} = Tempo.from_iso8601("1582-01-01[u-ca=gregory]")
iex> Tempo.overlaps?(julian, gregorian)
false
```

> 1 January 1582 under the **Julian calendar** and 1 January 1582 under the **Gregorian calendar** are not the same real day — they're **10 days apart** because of the Julian-to-Gregorian drift. Tempo comparisons are **calendar-aware**: same nominal components, different calendar, different underlying instant. The answer is `false`.

### How do I work in a fiscal year?

```elixir
iex> {:ok, us_fiscal}   = Calendrical.FiscalYear.calendar_for(:US)
iex> {:ok, fiscal_2026} = Tempo.from_iso8601("2026", us_fiscal)
iex> {:ok, months}      = Tempo.to_interval(fiscal_2026)
iex> Enum.count(months)
12
iex> Tempo.relation(Tempo.from_iso8601!("2026-01-01", us_fiscal), ~o"2025-10-01")
:equals
```

> The **US federal fiscal year** starts on 1 October, so fiscal year 2026 iterates to its **twelve fiscal months** and its first day **equals** 1 October 2025 on the shared timeline. A fiscal calendar is just a `Calendrical` calendar — every comparison, duration, and set operation stays calendar-aware. See the [custom calendars guide](custom-calendars.md).

### Allen's interval algebra

```elixir
iex> Tempo.relation(~o"2022-06", ~o"2022-07")
:meets

iex> Tempo.relation(~o"2022-06", ~o"2022-06-15")
:contains

iex> Tempo.relation(~o"2022-06", ~o"2023-06")
:precedes
```

> Two intervals relate in one of **13 named ways** — [Allen's interval algebra](https://ics.uci.edu/~alspaugh/cls/shr/allen.html). June **meets** July (touches at the boundary with no gap or overlap). June 2022 **contains** June 15 2022. June 2022 **precedes** June 2023. The relation is always exact; no equality-tolerance bikeshedding.

---

## Related reading

* [When to use Tempo](./when-to-use-tempo.md) — a short decision guide on choosing between Tempo and the Elixir standard library.
* [Scheduling](./scheduling.md) — bounded enumeration, wall-clock-vs-UTC authority, floating vs zoned events, and how future dates survive zone-rule changes.
* [Working with workdays and weekends](./workdays-and-weekends.md) — business-day queries (N days from today, next workday, workdays between two dates) built from `Tempo.workdays/1` and set algebra.
* [Holidays — planning with a real holiday calendar](./holidays.md) — fetch an ICS holiday feed, parse it with `Tempo.ICal.from_ical/1`, and compose it with `Tempo.workdays/1` for territory-aware scheduling.
* [Falsehoods programmers believe about time](./falsehoods.md) — the ten most impactful wrong assumptions, each with the Tempo idiom that makes the right behaviour automatic.
* [ISO 8601 conformance](./iso8601-conformance.md) — what's supported from the standard.
* [Enumeration semantics](./enumeration-semantics.md) — how iteration works across Tempo values.
* [Set operations](./set-operations.md) — union, intersection, complement, difference.
* [iCalendar integration](./ical-integration.md) — full `.ics` import with RRULE/RDATE/EXDATE.
* [Shared AST for ISO 8601 and RRULE](./shared-ast-iso8601-and-rrule.md) — the internal representation.
