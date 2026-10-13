# iCalendar integration

Tempo reads iCalendar (RFC 5545) — the format of Google Calendar, Apple Calendar, Outlook, CalDAV servers and every `.ics` file on disk — with `Tempo.ICal.parse/2`. Each event becomes an interval, each recurring event an interval for every occurrence, and each carries the event's summary, location, attendees and the rest as its metadata.

What comes back is a set of intervals like any other, so free-busy scheduling, overlap between schedules and questions of an event's time are the same expressions you write of any Tempo value.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`:

```elixir
import Tempo.Sigils
```

`Tempo.ICal` needs the [`ical`](https://hex.pm/packages/ical) library, which Tempo declares as an optional dependency. Add it to your own project:

<!-- guides:skip -->
```elixir
def deps do
  [
    {:ex_tempo, "~> 2.0"},
    {:ical, "~> 3.2"}
  ]
end
```

### Time zone database

**The `ical` library needs a `Calendar.TimeZoneDatabase` to read `DTSTART;TZID=…` and `DTEND;TZID=…`.** Without one those properties come through as nothing and the event has no start. Most real feeds write zoned times, so this is not optional:

<!-- guides:skip -->
```elixir
# config/config.exs
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

Any implementation works — [`:tz`](https://hex.pm/packages/tz), [`:tzdata`](https://hex.pm/packages/tzdata), [`:time_zone_info`](https://hex.pm/packages/time_zone_info) or [`:zoneinfo`](https://hex.pm/packages/zoneinfo). Times in UTC (`20260401T090000Z`) and times with no zone need none.

## 1. A schedule, read and asked about

The examples below read this calendar: two meetings on a Tuesday, and a stand-up every weekday of the week with one cancelled.

<!-- guides:run -->
```elixir
ics = """
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Example//Schedule//EN
X-WR-CALNAME:Work
BEGIN:VEVENT
UID:review@example.com
DTSTAMP:20260101T000000Z
DTSTART;TZID=Europe/London:20260421T103000
DTEND;TZID=Europe/London:20260421T113000
SUMMARY:Design review
LOCATION:Room 101
ATTENDEE;CN=Grace:mailto:grace@example.com
END:VEVENT
BEGIN:VEVENT
UID:one-to-one@example.com
DTSTAMP:20260101T000000Z
DTSTART;TZID=Europe/London:20260421T110000
DTEND;TZID=Europe/London:20260421T120000
SUMMARY:1:1 with Ada
END:VEVENT
BEGIN:VEVENT
UID:standup@example.com
DTSTAMP:20260101T000000Z
DTSTART;TZID=Europe/London:20260420T093000
DTEND;TZID=Europe/London:20260420T094500
RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=5
EXDATE;TZID=Europe/London:20260422T093000
SUMMARY:Standup
END:VEVENT
END:VCALENDAR
"""
```

```elixir
iex> {:ok, schedule} = Tempo.ICal.parse(ics)
iex> Tempo.IntervalSet.count(schedule)
6

iex> Tempo.IntervalSet.map(schedule, &Tempo.metadata(&1).summary)
["Standup", "Standup", "Design review", "1:1 with Ada", "Standup", "Standup"]

iex> tuesday = ~o"2026-04-21[Europe/London]"
iex> {:ok, on_tuesday} = Tempo.members_overlapping(schedule, tuesday)
iex> Tempo.IntervalSet.map(on_tuesday, &Tempo.metadata(&1).summary)
["Standup", "Design review", "1:1 with Ada"]
```

> *"The **schedule** is six events, in order of time. Those **overlapping Tuesday** are the stand-up, the design review and the one-to-one."*

The time I am busy, with meetings that overlap merged, and the time I am free in working hours:

```elixir
iex> working_hours = ~o"2026-04-21T09/2026-04-21T17[Europe/London]"
iex> {:ok, busy} = Tempo.intersection(schedule, working_hours)
iex> busy
~o"{2026Y4M21DT9H30M0S/T45M0S,2026Y4M21DT10H30M0S/T12H0M0S}[Europe/London]"

iex> Tempo.difference(working_hours, schedule)
{:ok, ~o"{2026Y4M21DT9H/T30M0S,2026Y4M21DT9H45M0S/T10H30M0S,2026Y4M21DT12H0M0S/T17H}[Europe/London]"}
```

> *"**Busy** is the schedule **within** working hours: the stand-up, then half past ten to noon. **Free** is working hours **minus** the schedule."*

`Tempo.ICal.parse_file/2` reads a file the same way, and `Tempo.ICal.from_ical/2` takes a calendar the `ical` library has already parsed.

## 2. What each event becomes

A `VEVENT` is an interval from its `DTSTART` to its `DTEND`:

| iCalendar | Tempo |
|---|---|
| `DTSTART` and `DTEND` as dates | An interval of days, written through its last day (`DTEND` being the day after it) |
| `DTSTART` and `DTEND` as times | An interval from the one reading to the other |
| `DTSTART` with `DURATION` | An interval of that length |
| `DTSTART` alone | The span of the start itself: its day, or its second |
| `TZID` | The interval's zone |
| A time ending in `Z` | An interval in UTC |
| A time with no zone | An interval with no zone — RFC 5545's local time |

```elixir
iex> Tempo.IntervalSet.first(schedule)
~o"2026Y4M20DT9H30M0S/T45M0S[Europe/London]"

iex> Tempo.shift_zone(Tempo.IntervalSet.first(schedule), "America/New_York")
{:ok, ~o"2026Y4M20DT4H30M0S/T45M0S[America/New_York]"}
```

> *"The first stand-up: half past nine to a quarter to ten in London, **half past four** in the morning in New York."*

The event's other properties are the interval's metadata, read with `Tempo.metadata/1`:

| Property | Metadata key |
|---|---|
| `UID` | `:uid` |
| `SUMMARY` | `:summary` |
| `DESCRIPTION` | `:description` |
| `LOCATION` | `:location` |
| `STATUS` | `:status`, an atom such as `:tentative` |
| `TRANSP` | `:transparency` |
| `CATEGORIES` | `:categories`, a list |
| `URL` | `:url` |
| `CLASS` | `:classification` |
| `PRIORITY` | `:priority` |
| `ORGANIZER` | `:organizer` |
| `ATTENDEE`s | `:attendees`, a list of names |
| `X-…` | `:custom`, a map |

A property the event does not have is not in the map. The calendar's own properties are the set's metadata: `:prodid`, `:version`, `:scale` (`CALSCALE`), `:method` and `:name` (`X-WR-CALNAME`).

```elixir
iex> design_review = Enum.find(Tempo.IntervalSet.members(schedule), &(Tempo.metadata(&1).summary == "Design review"))
iex> {Tempo.metadata(design_review).location, Tempo.metadata(design_review).attendees}
{"Room 101", ["Grace"]}

iex> Tempo.metadata(schedule).name
"Work"
```

## 3. One set, one zone

A set is one expression, and one expression is in one zone. A calendar whose events are in several zones is read as a set in the first zone named, and each event of another zone is moved to it: the same instants, read on that zone's clock. An event with no zone — an all-day event, or a time written with none — is read on that clock too, as a calendar application shows local times in the viewer's zone.

To see a schedule on another clock, move it:

```elixir
iex> {:ok, in_new_york} = Tempo.shift_zone(schedule, "America/New_York")
iex> Tempo.IntervalSet.first(in_new_york)
~o"2026Y4M20DT4H30M0S/T45M0S[America/New_York]"
```

Members that carry only a UTC time (`Z`) keep it where no event names a zone.

## 4. Metadata and the set operations

There are two kinds of operation, and they treat events differently.

**The operations that keep members** — `Tempo.union/2`, `Tempo.members_overlapping/2`, `Tempo.members_outside/2`, `Tempo.members_in_exactly_one/2`, and `Tempo.IntervalSet.filter/2` — keep each event whole, with its metadata. These are the ones for questions about *events*: which meetings are on Tuesday, which of mine clash with yours.

```elixir
iex> {:ok, morning} = Tempo.members_overlapping(schedule, ~o"2026-04-21T09/2026-04-21T11[Europe/London]")
iex> Tempo.IntervalSet.map(morning, &Tempo.metadata(&1).summary)
["Standup", "Design review"]
```

**The operations on time** — `Tempo.intersection/2`, `Tempo.difference/2`, `Tempo.symmetric_difference/2`, `Tempo.complement/2`, `Tempo.IntervalSet.coalesce/1` — answer the time covered, with events that overlap or touch merged into one span. These are the ones for *free-busy* questions. A span of the answer that came from one event carries that event's metadata; one merged from several is no one event.

```elixir
iex> {:ok, covered} = Tempo.IntervalSet.coalesce(schedule)
iex> Tempo.IntervalSet.count(covered)
5
```

> *"Six events **cover** five stretches of time: the design review and the one-to-one overlap, and are one."*

## 5. Free-busy across calendars

The common workflow, with two calendars:

<!-- guides:skip -->
```elixir
{:ok, work}     = Tempo.ICal.parse_file("work.ics", within: ~o"2026-04")
{:ok, personal} = Tempo.ICal.parse_file("personal.ics", within: ~o"2026-04")

{:ok, all_busy} = Tempo.union(work, personal)

working_hours = ~o"2026-04-21T09/2026-04-21T17[Europe/London]"
{:ok, free}   = Tempo.difference(working_hours, all_busy)
{:ok, slots}  = Tempo.IntervalSet.slots(free, ~o"PT30M")
```

> *"Everything I am busy with is my work calendar **and** my personal one. **Free** time is working hours **minus** that. The **slots** to offer are the free time cut into half hours."*

`Tempo.ICal.available/2` reads the `VAVAILABILITY` components of a calendar (RFC 7953), the time its owner offers, and answers it within a window.

## 6. Recurring events

An event with an `RRULE` is an interval for each occurrence, each as long as the event and each with its metadata. The rule is read by the same engine as `Tempo.RRule.parse/2`, with the event's `DTSTART` as its start and its length as each occurrence's; the [RRULE conformance guide](./rfc5545_rrule_conformance.md) says what each part means and which are not read.

* **`RDATE`** adds occurrences, each as long as the event.

* **`EXDATE`** removes the occurrences that start when it says.

So the occurrences are those the rule gives, with the `RDATE`s, less the `EXDATE`s. The stand-up above is five weekdays from the 20th with the 22nd taken out:

```elixir
iex> standups = Tempo.IntervalSet.filter(schedule, &(Tempo.metadata(&1).summary == "Standup"))
iex> Tempo.IntervalSet.map(standups, &Tempo.day/1)
[20, 21, 23, 24]
```

### A rule with no end needs a window

A rule with a `COUNT` or an `UNTIL` is listed whole. One with neither has no last occurrence, and `parse/2` returns an error unless it is given the window whose events are wanted:

```elixir
iex> endless = String.replace(ics, ";COUNT=5", "")
iex> {:error, %Tempo.ConversionError{reason: :unbounded}} = Tempo.ICal.parse(endless)
iex> {:ok, this_week} = Tempo.ICal.parse(endless, within: ~o"2026-04-20/2026-04-24")
iex> Tempo.IntervalSet.count(this_week)
6
```

> *"Within the week of the 20th: four stand-ups and the two meetings."*

With a window, events that do not recur are kept when they overlap it too. A window with no zone is read on each event's own clock, so `~o"2026-04"` is April where the event is.

### A day a month lacks

A rule that leaves its day to `DTSTART` has no occurrence in a month or a year without that day, as RFC 5545 §3.3.10 says: an event on the 31st with `FREQ=MONTHLY` is listed in the months of 31 days, and one on the 29th of February with `FREQ=YEARLY` in the leap years. A rule that means the last day of each month says so, with `BYMONTHDAY=-1`.

## 7. What is not read or written

* **`EXRULE`**, which RFC 5545 deprecated. Use `EXDATE`.

* **More than one `RRULE` in an event.** RFC 5545 says an event should not have them, and the `ical` library gives the first.

* **`VTIMEZONE` definitions.** The `ical` library uses them to read an event's times; Tempo itself asks the configured time zone database, so a zone that is defined only in the file and is not in the IANA data cannot be placed.

* **Writing iCalendar.** Tempo writes a recurrence's rule with `Tempo.RRule.to_string/1`, and no whole calendar.

`Tempo.JSCalendar` reads JSCalendar (RFC 8984) events and groups through the same engine, with the same answers.

## 8. Related reading

* [RRULE conformance](./rfc5545_rrule_conformance.md) — RFC 5545's rule, part by part.

* [Set operations](./set-operations.md) — combining schedules, and the two kinds of operation.

* [Scheduling](./scheduling.md) — zones, windows and free-busy.

* [Holidays](./holidays.md) — a holiday feed as an `.ics` file.

* [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) — the iCalendar specification.
