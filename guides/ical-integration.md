# iCalendar integration

Tempo imports iCalendar (RFC 5545) data — the interchange format used by Google Calendar, Apple Calendar, Outlook, CalDAV servers, and every `.ics` file on disk — via `Tempo.ICal.parse/2`. Events convert to `%Tempo.Interval{}` values with their full metadata (summary, location, attendees, status, …) preserved and carried through every downstream operation, including set operations and enumeration.

This unlocks free/busy scheduling, schedule overlap analysis, and event-aware time queries as direct expressions over the same API you use for any other Tempo value.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

## 1. A complete round-trip

```elixir
ics = File.read!("~/my-schedule.ics")

{:ok, schedule} = Tempo.ICal.parse(ics)
# #Tempo.IntervalSet<[
#   #Tempo.Interval<~o"..." · Design review @ Room 101>,
#   #Tempo.Interval<~o"..." · 1:1 with Ada>,
#   ...
# ] · Work>

# What's on the schedule today?
today = ~o"2026-04-21"
{:ok, today_events} = Tempo.members_overlapping(schedule, today)

# What time am I actually busy? (the covered-instant form)
busy = Tempo.IntervalSet.coalesce(schedule)
# Overlapping events merge into contiguous busy-time spans.

# When am I free during work hours?
work_hours = ~o"2026-04-21T09/2026-04-21T17"
{:ok, free} = Tempo.difference(work_hours, schedule)
```

Every result is a standard `%Tempo.IntervalSet{}`. Event metadata from the source schedule is preserved on whichever intervals came from those events.

## 2. Setup

`Tempo.ICal` depends on the [`ical`](https://hex.pm/packages/ical) library, declared `optional: true` on Tempo's side. Pull it into your own project:

```elixir
def deps do
  [
    {:tempo, "~> 0.2"},
    {:ical, "~> 2.0 or ~> 3.0"}
  ]
end
```

### Time-zone database

**The `ical` library needs a `Calendar.TimeZoneDatabase` installed to parse `DTSTART;TZID=...` and `DTEND;TZID=...` properties.** Without one, those datetime fields come through as `nil` and Tempo silently drops the event. For most real `.ics` feeds (Google Calendar, iCloud, Outlook all emit zoned datetimes), this is not optional.

Configure a database in the host application's `config/config.exs` (or per-environment file):

```elixir
# config/config.exs
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

Any `Calendar.TimeZoneDatabase` implementation works — [`:tz`](https://hex.pm/packages/tz), [`:tzdata`](https://hex.pm/packages/tzdata), [`:time_zone_info`](https://hex.pm/packages/time_zone_info), or [`:zoneinfo`](https://hex.pm/packages/zoneinfo); Tempo does not bundle one. Tempo's own dev and test environments pull in `:tz` and configure `Tz.TimeZoneDatabase` via `config/dev.exs` and `config/test.exs`, which is how the project's demo schedules (`demo/calendars/*.ics`) round-trip zoned events in `mix test` runs.

UTC datetimes (the `20260401T090000Z` form) and floating/naive datetimes do not need a zone database — only the `TZID=`-parameterised form does.

## 3. What each event produces

A `VEVENT` becomes a `%Tempo.Interval{}`:

| iCalendar property | Tempo placement |
|---|---|
| `DTSTART` (date) | `interval.from` at day resolution |
| `DTSTART` (datetime) | `interval.from` at datetime resolution |
| `DTSTART` (floating datetime, no `Z` or `TZID`) | `interval.from` zone-less (`extended: nil`) — RFC 5545 §3.3.5 floating time, preserved as-is rather than placed in a zone |
| `DTEND` | `interval.to` at matching resolution |
| `TZID` (on DTSTART/DTEND) | `interval.from.extended.zone_id` via `Tempo.from_elixir/2` |
| `UID` | `metadata.uid` |
| `SUMMARY` | `metadata.summary` |
| `DESCRIPTION` | `metadata.description` |
| `LOCATION` | `metadata.location` |
| `STATUS` | `metadata.status` (atom like `:tentative`) |
| `TRANSPARENCY` | `metadata.transparency` |
| `CATEGORIES` | `metadata.categories` (list) |
| `URL` | `metadata.url` |
| `CLASS` | `metadata.classification` |
| `PRIORITY` | `metadata.priority` |
| `ORGANIZER` | `metadata.organizer` (name or inspected struct) |
| `ATTENDEE`s | `metadata.attendees` (list of names or inspected structs) |
| `X-*` custom | `metadata.custom` (map) |

The `VCALENDAR` envelope produces set-level metadata on the `IntervalSet`:

| Envelope property | Set-level metadata |
|---|---|
| `PRODID` | `metadata.prodid` |
| `VERSION` | `metadata.version` |
| `CALSCALE` | `metadata.scale` |
| `METHOD` | `metadata.method` |
| `X-WR-CALNAME` | `metadata.name` |

## 4. Metadata flows through set operations

The key promise: once an event is in Tempo, its metadata travels with any portion of it that survives set operations.

```elixir
# A design review meeting
event = Tempo.Interval.new!(
  from: ~o"2026-04-21T10:30",
  to: ~o"2026-04-21T11:30",
  metadata: %{summary: "Design review", location: "Room 101"}
)

# Clip to work hours
{:ok, clipped} = Tempo.intersection(event, ~o"2026-04-21T09/2026-04-21T17")
[iv] = Tempo.IntervalSet.members(clipped)

Tempo.Interval.metadata(iv).summary
# "Design review"  — preserved through the intersection
```

The rule: **result intervals inherit the A-operand's per-interval metadata**. For `intersection/2` and `difference/2` (both trimmed/instant-level), every result fragment stays tagged with the source event's metadata. For `members_overlapping/2` and `members_outside/2`, surviving members are kept whole and untouched. Set-level metadata (calendar `PRODID` etc.) follows the first operand through all operations.

## 5. Overlapping events are preserved

Real schedules routinely have overlapping events — a travel event on top of a lunch meeting, an all-day conference covering several one-hour talks. `Tempo.ICal.parse/2` returns **an IntervalSet with overlaps preserved** — each VEVENT is a distinct member with its own metadata, and `Tempo.union/2` (the only member-preserving default in the set algebra) keeps it that way through compositions like merging multiple calendars.

```elixir
{:ok, set} = Tempo.ICal.parse(ics)
# The set may contain overlapping intervals — each one a
# distinct VEVENT with its own metadata.
```

When you want free/busy spans (canonical covered-instant form), coalesce explicitly:

```elixir
busy = Tempo.IntervalSet.coalesce(set)
```

`Tempo.IntervalSet.coalesce/1` merges touching and overlapping members under the half-open convention and drops the dropped members' metadata. Use it when you want the covered-instant shape (free/busy block lists). For event-list questions on the schedule (which meeting, which event), reach for the `members_*` companions instead — they keep each VEVENT and its metadata intact.

## 6. Free/busy patterns

The most common iCal workflow:

```elixir
# 1. Import the schedules
{:ok, work} = Tempo.ICal.parse_file("work.ics")
{:ok, personal} = Tempo.ICal.parse_file("personal.ics")

# 2. Merge into one busy-set
{:ok, all_busy} = Tempo.union(work, personal)

# 3. Find free time within a window
work_hours = ~o"2026-04-21T09/2026-04-21T17"
{:ok, free} = Tempo.difference(work_hours, all_busy)

# 4. Enumerate free slots
Tempo.IntervalSet.map(free, &Tempo.Interval.endpoints/1)
```

## 7. Recurrence expansion

Events with an `RRULE` expand through a single pipeline:

```
RRULE string ──────────► Tempo.RRule.parse/2 ──┐
                                                ├──► %Tempo.Interval{}
%ICal.Recurrence{} ─► %Tempo.RRule.Rule{} ──────┘            │
                                                             ▼
                                                   Tempo.to_interval/2
                                                             │
                                                             ▼
                                                  Tempo.RRule.Selection
                                                             │
                                                             ▼
                                                   [%Tempo.Interval{}]
```

Every RFC 5545 BY-rule flows through one interpreter — there is no "simple core" and no "full expander" split. Each occurrence is a distinct `%Tempo.Interval{}` with the event's metadata attached.

### Supported rule parts

| Part         | Support                                                     |
| ------------ | ----------------------------------------------------------- |
| `FREQ`       | `SECONDLY`, `MINUTELY`, `HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY` |
| `INTERVAL`   | Positive integer; applied as `DTSTART + i × INTERVAL`       |
| `COUNT`      | Terminates after N occurrences (post-filter)                |
| `UNTIL`      | Date or UTC datetime; inclusive                             |
| `BYMONTH`    | LIMIT generally; EXPAND for `FREQ=YEARLY`                   |
| `BYMONTHDAY` | LIMIT generally; EXPAND for `FREQ=MONTHLY` / `YEARLY`. Signed indexing (`-1` = last day of the month) |
| `BYYEARDAY`  | LIMIT generally; EXPAND for `FREQ=YEARLY`. Signed           |
| `BYWEEKNO`   | EXPAND for `FREQ=YEARLY`: weeks start on `WKST`, week 1 holds the year's fourth day, and a week keeps its days in the adjacent years. Signed. Without `BYDAY`, `BYMONTHDAY` or `BYYEARDAY`, DTSTART's weekday (ISO 8601-2 Annex C.3) |
| `BYDAY`      | LIMIT for `DAILY` and finer. EXPAND within the enclosing week / month / year for `WEEKLY` / `MONTHLY` / `YEARLY`. Ordinal prefixes (`1MO`, `-1FR`, `4TH`) select the Nth weekday of the enclosing period via `Calendrical.Kday.nth_kday/3`. RFC Notes 1/2 downgrade to LIMIT when BYMONTHDAY / BYYEARDAY is co-present, and pick within each week when BYWEEKNO is |
| `BYHOUR`     | EXPAND when `FREQ` is coarser than hour; LIMIT otherwise    |
| `BYMINUTE`   | Same pattern at the minute unit                             |
| `BYSECOND`   | Same pattern at the second unit                             |
| `BYSETPOS`   | Applied last, across the per-period candidate set. Signed   |
| `WKST`       | Week-start day (default Monday). Affects `FREQ=WEEKLY + BYDAY` week boundaries and `BYWEEKNO` week numbers |
| `RDATE`      | Extra occurrences; carry the event's span                   |
| `EXDATE`     | Subtracted from the combined set by start-moment match      |

### Termination paths

* **`COUNT=N`** — stop after N occurrences (after BY-rule filtering / expansion).

* **`UNTIL=<date-or-datetime>`** — stop when the next occurrence would start past `UNTIL`.

* **No `COUNT` or `UNTIL`** — a `:within` option is required at the call site. The rule expands within the window.

### Worked examples

```elixir
# "Every Friday the 13th, 5 occurrences"
ics = "...RRULE:FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13;COUNT=5..."
{:ok, set} = Tempo.ICal.parse(ics)
# => 1998-02-13, 1998-03-13, 1998-11-13, 1999-08-13, 2000-10-13

# "The 4th Thursday of November" (US Thanksgiving)
ics = "...RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=3..."
{:ok, set} = Tempo.ICal.parse(ics)
# => 2022-11-24, 2023-11-23, 2024-11-28

# "Last weekday of every month"
ics = "...RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3..."
{:ok, set} = Tempo.ICal.parse(ics)

# With RDATE + EXDATE
ics = """
...
RRULE:FREQ=WEEKLY;COUNT=3
RDATE:20220618T140000Z
EXDATE:20220608T090000Z
...
"""
{:ok, set} = Tempo.ICal.parse(ics)
# Weekly series has Jun 8 removed and Jun 18 14:00 added
```

### DTSTART is always the first occurrence

Per RFC 5545, `DTSTART` is the first instance in the recurrence. When `BY*` rules EXPAND, they can legitimately produce candidates earlier than `DTSTART` in the same period — the resolver drops these automatically so the emitted list starts at (or after) `DTSTART`.

### Calendar-aware throughout

Every arithmetic operation goes through the candidate's own calendar (`calendar.day_of_week/4`, `calendar.days_in_month/2`, `calendar.iso_week_of_year/3`, Calendrical's date arithmetic, `Calendrical.Kday.nth_kday/3`). A Hebrew-calendar VEVENT with `FREQ=YEARLY;BYMONTHDAY=-1` expands correctly against Hebrew month lengths.

## 8. What's not supported

* **`EXRULE`** — RFC-deprecated (RFC 2445 → 5545) and not surfaced by the underlying `ical` library. If you need subtractive rules, use `EXDATE` for specific dates.

* **Multiple `RRULE` per `VEVENT`** — RFC 5545 says SHOULD NOT. Some exports do it anyway; the `ical` library exposes only the first `RRULE` on `event.rrule`, so we expand that one and silently ignore the rest.

* **VTIMEZONE definitions.** `VTIMEZONE` blocks in the input are used by the `ical` library to resolve zoned DTSTART/DTEND values, but Tempo itself relies on the configured time zone database for zone calculations. Zones absent from the IANA data (historical / non-standard zones defined in the `VTIMEZONE`) may not round-trip cleanly.

* **Export.** `Tempo → iCalendar` (going the other way) isn't implemented. Tempo writes an RRULE with `Tempo.RRule.to_string/1` for individual values; a full `to_ical/1` that produces a VCALENDAR envelope with VEVENTs is a future step.

## 9. Related reading

* [`guides/rfc5545_rrule_conformance.md`](./rfc5545_rrule_conformance.md) for the property-by-property RRULE coverage table.

* [`guides/set-operations.md`](./set-operations.md) for how to combine imported schedules.

* [`guides/enumeration-semantics.md`](./enumeration-semantics.md) for how iteration works over the resulting IntervalSets.

* [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) for the iCalendar spec itself.
