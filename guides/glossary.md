# Glossary

The words Tempo's API and documentation use, each with the one meaning it has. Tempo holds to two rules: a word means one thing, and a thing has one word. A standard's own term is used where the standard is being quoted (Allen's relations, ISO 8601's *repeat rule* and *selection*, RFC 5545's property names) and nowhere else. A new name is checked against this page before it is given.

The tables are grouped by subject, and within a table the terms a later one builds on come first.

## Spans

| Term | Meaning | Where |
|---|---|---|
| span | A stretch of the time line with a first instant and a last. Every Tempo value is one. | `Tempo.to_interval/2` |
| half-open | A span holds its first instant and not its last: `[from, to)`. | every span |
| implicit span | The span a value names by how precisely it is written: `2026-06` is June. | `%Tempo{}` |
| interval | A span written with its two ends, or with one end and a length. | `%Tempo.Interval{}` |
| ends | A span's `from` and `to`. | `Tempo.Interval.from/1`, `Tempo.Interval.to/1` |
| extent | Where a span starts and where it ends. | `Tempo.to_interval/2` |
| resolution | The finest unit a value states: a day for `2026-06-15`. | `Tempo.resolution/1` |
| unit | The unit a walk of a span yields: the one below a value's resolution, or an interval's own. | `:unit` of an interval |
| bounded | Both ends are stated. | `Tempo.bounded?/1` |
| open | An end is not stated (`2026-06-15/..`). | `%Tempo.Interval{}` |
| duration | A length of time with no place on the time line (`P1M`). | `%Tempo.Duration{}`, `Tempo.duration/1` |
| instant | A point with no length. Tempo has none: its finest value is a span as long as its resolution. | |

## Placing a value

| Term | Meaning | Where |
|---|---|---|
| anchored | The value has a year, and so a place on the time line. | `Tempo.anchored?/1` |
| unanchored | The value has no year and comes round again: 10:30, or 15 June. | `Tempo.UnanchoredError` |
| `at`, `on` | Place a time of day on a day: 17:00 on 15 June. | `Tempo.at/2`, `Tempo.on/2` |
| floating | The value is a reading of a clock, in no zone. | `Tempo.floating?/1` |
| zoned | The value is in a named zone or carries a shift. | `Tempo.zoned?/1`, `Tempo.in_zone/2` |
| zone | A named time zone, written as an IXDTF suffix (`[Europe/Paris]`). | `Tempo.shift_zone/2` |
| shift | A fixed offset from UTC written with a value (`+02:00`). Also the verb: to move a value by a duration. | `Tempo.shift/2` |
| reading | What a zone's clock shows. | `Tempo.ZoneGapError` |
| a reading the clock skips | A reading no moment has, on the day the clock goes forward. It is refused. | `Tempo.ZoneGapError` |
| a reading the clock shows twice | A reading two moments have, on the day the clock goes back. | `Tempo.in_zone/2` |
| calendar | A module that implements `Calendar`, in which a value's units are counted. Never a CLDR calendar type. | `Tempo.to_calendar/2` |
| calendar of weeks | A calendar whose year is counted in weeks and whose dates are a week and a day of it. | `Calendrical.ISOWeek` |
| territory | A CLDR territory code (`:AU`, `:SA`), which decides the weekend and the first day of the week. Never "region". | `Tempo.Territory` |

## Several values at once

| Term | Meaning | Where |
|---|---|---|
| set | Several values written as one: all of them (`{…}`), or one of them (`[…]`). | `%Tempo.Set{}`, ISO 8601-2 §6 |
| member | One value of a set, or one span of an interval set. | `Tempo.IntervalSet.members/1` |
| range | The values from one to another within a set (`{1..5}`). | `%Tempo.Range{}` |
| interval set | Spans held together, in order. | `%Tempo.IntervalSet{}` |
| covered | The time at least one member of an interval set holds. | `Tempo.duration/1`, `Tempo.IntervalSet.covered/2` |
| slot | A bookable piece of free time. | `Tempo.IntervalSet.slots/3` |
| unspecified digits | Digits written as `X`: `202X` is some year of the 2020s. | ISO 8601-2 §4.6 |
| mask | A unit that holds unspecified digits. | `Tempo.Mask` |
| group | A run of a unit's values counted in equal parts: `2G3MU` is the second group of three months. | ISO 8601-2 §5 |
| qualification | A mark that a value is uncertain (`?`), approximate (`~`) or both (`%`). | ISO 8601-2 §4.5 |
| margin of error | A value with a stated error (`2018±2Y`). | `guides/uncertain-dates.md` |
| significant digits | How many of a year's digits are known (`1950S2`). | ISO 8601-2 §4.4.3 |

## Recurrences

| Term | Meaning | Where |
|---|---|---|
| recurrence | A span repeated at a cadence (`R5/2026-06-15/P1W`). | `%Tempo.Interval{}` with `:recurrence` |
| start | The first value a recurrence counts from. | ISO 8601 |
| cadence | The duration from one period of a recurrence to the next. | `:duration` of a recurrence |
| period | The span a recurrence steps to, one cadence long. | `Tempo.select/2` |
| occurrence | One span a recurrence gives. | `Tempo.to_interval/2` |
| repeat rule | The selection a recurrence applies in each period. ISO 8601-2's term. | `:repeat_rule` |
| selection | The parts of a period that are taken (`L…N`): the 15th, the Mondays, 09:00. ISO 8601-2's term. | ISO 8601-2 §12 |
| part | One unit of a selection or of an RRULE: a month, a weekday, a position. | `Tempo.RRule` |
| position | Which of the values a selection has picked is kept: the first, the last (`I`, RFC 5545's `BYSETPOS`). | ISO 8601-2 §12.9 |
| window | A span that limits what is taken: the `:within` option's, and the span a selection opens from each date it picks. | `:within`, ISO 8601-2 §12.10 |
| `:within` | The window whose overlapping occurrences are kept. | `Tempo.to_interval/2` |
| recurrence set | Recurrences and dates held together, with the dates left out. | `%Tempo.RecurrenceSet{}` |
| event | A day a rule computes rather than counts, such as Easter. | `Tempo.Event` |

## Relating and comparing

| Term | Meaning | Where |
|---|---|---|
| relation | Which of Allen's thirteen relations holds between two spans. | `Tempo.relation/2`, `Tempo.Allen` |
| before, after | The spans share no instant and one is earlier. The everyday sense: a meeting that ends at 12:00 is before a lunch at 12:00. | `Tempo.before?/2`, `Tempo.after?/2` |
| adjacent | One span ends where the other starts. | `Tempo.adjacent?/2` |
| overlaps | The spans share an instant. | `Tempo.overlaps?/3` |
| within, contains | The whole of one span is inside the other. | `Tempo.within?/2`, `Tempo.contains?/3` |
| disjoint | The spans share no instant. | `Tempo.disjoint?/3` |
| certainly, possibly | Whether a relation holds for every reading of an uncertain value, or for some. | `Tempo.certainly_before?/2` |
| compare | Order two values as `:lt`, `:eq` or `:gt`, for sorting. | `Tempo.compare/3` |
| at least, at most, exactly | How a span's length stands to a duration. | `Tempo.at_least?/2` |

## What is done to a value

| Term | Meaning | Where |
|---|---|---|
| read | Turn text into a value. | `Tempo.from_iso8601/1`, `Tempo.parse/2` |
| write | Turn a value into ISO 8601 text. | `Tempo.to_iso8601/1` |
| show | Turn a value into a locale's words. | `Tempo.to_string/2` |
| explain | Say in English what a value means. | `Tempo.explain/1` |
| convert | Turn a value into another kind: its span, its occurrences, an Elixir date. | `Tempo.to_interval/2`, `Tempo.to_date/1` |
| walk | Take a span's values one after another. | `Enum`, `Enumerable` |
| select | Keep the parts of a span that a selector names. | `Tempo.select/2` |
| selector | What `select/2` selects by: a value, a selection, the workdays. | `Tempo.select/2` |
| shift | Move a value by a duration. | `Tempo.shift/2` |
| truncate, round | Write a value at a coarser unit: the one it starts in, or the nearer one. | `Tempo.trunc/2`, `Tempo.round/2` |
| extend | Write a value by the unit below its own. | `Tempo.extend/1`, `Tempo.extend_resolution/2` |
| union, intersection, difference, complement | The set operations, over the time spans cover. | `Tempo.union/2` |
| refuse | Return a named error rather than a guess. | `{:error, exception}` |
| not built | What Tempo knows it does not answer yet, refused by name. | `Tempo.ConversionError` |

## Days of work

| Term | Meaning | Where |
|---|---|---|
| workday | A day that is not of the weekend, nor a day off. | `Tempo.workday?/2`, `Tempo.workdays/2` |
| weekend | The days a territory rests on each week. | `Tempo.weekend?/2`, `Tempo.weekends/1` |
| days off | The days left out of the workdays beside the weekend: holidays. | `:except` of `Tempo.workdays/2` |

## Notations

| Term | Meaning | Where |
|---|---|---|
| ISO 8601 | The standard Tempo reads and writes, Parts 1 and 2. | `Tempo.from_iso8601/1` |
| extended format | A date written with separators (`2026-06-15`). | ISO 8601-1 |
| basic format | A date written without them (`20260615`). | ISO 8601-1 |
| explicit form | A date written with a designator after each unit (`2026Y6M15D`), the form Tempo writes. | ISO 8601-2 §7 |
| week date | A date written by its week and its day of the week (`2026-W25-3`). | ISO 8601-1 |
| ordinal date | A date written by its day of the year (`2026-166`). | ISO 8601-1 |
| EDTF | The Extended Date/Time Format, now ISO 8601-2's uncertain and unspecified dates. | `guides/uncertain-dates.md` |
| IXDTF | The suffix that names a zone or a calendar (`[Europe/Paris]`, `[u-ca=hebrew]`). | RFC 9557 |
| RRULE | RFC 5545's recurrence rule, read into the same recurrence an ISO 8601 rule is. | `Tempo.RRule.parse/2` |
| iCalendar, JSCalendar | The calendar formats of RFC 5545 and RFC 8984. | `Tempo.ICal`, `Tempo.JSCalendar` |
