# Inclusive ends for intervals written to a date

**Status:** draft, 2026-10-08

A proposal for the user to decide. Nothing here is built, and nothing is to be built before the decision.

## The problem

A set and an interval written with the same two years name different spans:

```elixir
Enum.to_list(~o"{2024..2026}Y")   # [~o"2024Y", ~o"2025Y", ~o"2026Y"]
Enum.to_list(~o"2024Y/2026Y")     # [~o"2024Y", ~o"2025Y"]
Tempo.duration(~o"2024Y/2026Y")   # ~o"P2Y"
Tempo.to_string(~o"2024Y/2026Y")  # {:ok, "2024 – 2025"}
```

The interval ends where its written end begins, so it holds nothing of 2026. Feedback to the user (2026-10-08) is that readers, and ISO 8601, take the end of an interval written with two dates to be part of it, which would also make the two writings agree.

## What the standards say

* **ISO 8601-1 §3.1.1.6** — a time interval is the part of the time axis between two instants and, unless stated otherwise, those two instants too. That is a closed interval of instants.

* **ISO 8601-2 Annex A.4.4** — the EDTF level 0 profile, for intervals whose two ends are dates and hold no time. Its examples describe `1964/2008` as ending "sometime in 2008", and say the same of an end written to a month (`2004-06/2006-08`), to a day (`2004-02-01/2005-02-08`) and of ends of different precision (`2004-02-01/2005`). An interval that stops as 2008 begins does not end in 2008.

* **RFC 5545 §3.6.1** — an all-day event's `DTEND` is the day after its last day: the end is not part of the event. This is the one convention Tempo exchanges data with that reads a date end as Tempo does today.

* **Elixir** — `Date.range/2` holds its last date.

Not verified here: what the EDTF libraries (`edtf.js`, `python-edtf`) compute for the bounds of `1964/2008`.

## Why one rule cannot serve dates and times

Taking an end's own span into the interval is what a reader means by a date and not what a reader means by a time. Nine to five ends at five. Read with its end's span included, `T09/T17` would run to 18:00, a meeting written `10:00/11:00` would last sixty-one minutes, and two bookings written back to back would overlap. Annex A.4.4 is itself limited to ends that are dates.

`Tempo.to_string/2` already draws this line. A span of dates is shown to the last value it holds ("Jun 1 – 14" for `2026-06-01/2026-06-15`), and a span of clock times to its end as it is written ("9 AM – 5 PM", decided 2026-10-08).

## The options

* **A. Leave it** — `/` keeps its end out at every precision, the guides say so, and a reader who wants the end in writes the set (`{2024..2026}Y`). Nothing breaks. Tempo's reading of an interval of dates then differs from Annex A.4.4's examples, which the conformance guide would have to say.

* **B. An end written to a date is included, in the notation alone** — recommended, and set out below.

* **C. Every end is included** — one rule, and wrong for times, as above.

* **D. The struct holds an inclusive end** — the value's `:to` becomes the last unit held. Every comparison, walk and set operation reads `:to` as the bound today, so this is B's reading at many times the cost, and it gives up the half-open bound the set operations rest on.

* **E. An option where a value is read** — `Tempo.from_iso8601("2024/2026", ends: :inclusive)`. The sigil has no place for it, and one text would then mean two things.

## The proposal (B)

An end written to a day or coarser — a day, a week, a month, a year, a decade, a century — is the last unit of the interval. An end written to a time of day is the instant the interval stops at, as it is now.

| Written | Today | Proposed |
|---|---|---|
| `2024/2026` | 2024 and 2025 | 2024, 2025 and 2026 |
| `2026-06-01/2026-06-15` | fourteen days | fifteen days |
| `2026-W25/2026-W27` | two weeks | three weeks |
| `2004-02-01/2005` | to the end of 2004 | to the end of 2005 |
| `1K/5K` | Monday to Thursday | Monday to Friday |
| `2026-06-15T09/2026-06-15T17` | eight hours | eight hours |
| `2026-06-15T09/2026-06-16` | to the start of the 16th | to the end of the 16th |

The struct stays half-open. The reader stores a date end as the start of the unit after it, and `inspect`, `Tempo.to_iso8601/1` and `Tempo.explain/1` write the stored bound back as the unit before it, so what is written reads back. The comparisons, the walk, the set operations and the storage of `tempo_sql` read the same bound they read today and do not change. A step to the next unit and back is Calendrical's.

## What follows from it, to settle with the decision

* **One unit is written with the same start and end** — the interval a year converts to is stored `2024Y/2025Y` and would be written `2024Y/2024Y`, a day `2026Y6M15D/15D`.

* **An interval that holds nothing has no writing** — its end would be written before its start, which is refused when read (decided 2026-10-08). `Tempo.round/2` can make one.

* **`Tempo.Interval.new/1`** — whether `:to` stays the bound, as the struct holds it, with a `:through` beside it for the last unit, or reads as the notation does.

* **A duration and an end** — `P1M/1985-06` is May 1985 today. Read with its end included it is June.

* **A recurrence written with two ends** — `R5/2026-06-15/2026-06-20` steps by the length of its first occurrence, which grows by a day.

* **Spans that meet** — `2024/2026` and `2026/2028` would share 2026, and are written `2024/2025` and `2026/2027`. Two stored spans still meet where one's bound is the other's start.

* **The seam at midnight** — `2026-06-15/2026-06-16` is two days and `2026-06-15T00/2026-06-16T00` one.

* **iCalendar and JSCalendar** — `Tempo.ICal` converts an all-day `DTEND` at the boundary, in both directions.

* **A set and an interval still differ in shape** — `{2024..2026}Y` is three spans of a year and `2024/2026` one span of three. They would cover the same time.

## Census

Intervals written with an end of date precision, counted by parsing every quoted, backticked and sigil string of each tree with the library (2026-10-08, at `deeb0aa`). Each is a literal whose meaning or whose printed form changes.

| Tree | Written | Distinct | Files |
|---|---|---|---|
| `lib` (documentation and doctests) | 155 | 103 | 22 |
| `test` | 1,071 | 690 | 115 |
| `guides` and `README.md` | 130 | 99 | 15 |
| `livebook` | 11 | 9 | 4 |
| `CHANGELOG.md` | 58 | 55 | 1 |
| `tempo_holidays` | 37 | 35 | 8 |
| `tempo_sql` | 5 | 4 | 3 |

Of the 1,425 in this repository, 1,232 are written with two ends, 62 with a duration and an end, 56 as a recurrence written to an end, 49 with an open start and 26 as a recurrence of two ends. Intervals written with an end of time precision, which do not change, number 813.

The census counts what is written. It does not count results computed and compared with `Date` or `DateTime`, which change wherever the interval they are computed from does.

## The shape of the work

* The reader: an end of date precision is stored as the start of the next unit, in every form an interval is written in.

* The writers: `inspect`, `Tempo.to_iso8601/1`, `Tempo.explain/1`, and `Tempo.to_string/2`, which then shows every span as it is written.

* The boundaries: `Tempo.ICal`, `Tempo.JSCalendar`, `Tempo.Interval.new/1`.

* The literals of the census, by a script that rewrites each from what it parses to today, checked by the suite.

* The guides, and the half-open paragraph of the project's `CLAUDE.md`, which is true of the struct and no longer of the notation.

## Tasks

* [ ] **The decision** — A or B, and for B the points under "What follows from it". With the user.
