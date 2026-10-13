# Glossary

The words Tempo's API and documentation use, each with the one meaning it has. Tempo holds to two rules: a word means one thing, and a thing has one word. A standard's own term is used where the standard is being quoted (Allen's relations, ISO 8601's *repeat rule* and *selection*, RFC 5545's property names) and nowhere else. A new name is checked against this page before it is given.

The tables are grouped by subject, and within a table the terms a later one builds on come first.

## Spans

| Term | Meaning | Where |
|---|---|---|
| expression | One thing as it is written or built: a value, an interval, a recurrence, a set. All are a `%Tempo{}`, and one expression is in one calendar and one zone. | `t:Tempo.t/0` |
| span | A stretch of the time line with a first instant and a last. Every Tempo value is one. | `Tempo.to_interval/2` |
| half-open | A span holds its first instant and not its last: `[from, to)`. | every span |
| value | A date or a time written to some unit, which names the span of that unit: `2026-06` is June. | `Tempo.new/1`, `~o"2026-06"` |
| interval | A span written with its two ends, or with one end and a length. | `Tempo.Interval.new/1`, `~o"2026-06-01/2026-06-30"` |
| written end | The end of an interval as its text gives it: a date is read through, a time of day is the reading the span runs to. | `Tempo.Interval.to/1` |
| ends | A span's `from` and `to`. | `Tempo.Interval.from/1`, `Tempo.Interval.to/1` |
| extent | Where a span starts and where it ends. | `Tempo.to_interval/2` |
| resolution | The finest unit a value states: a day for `2026-06-15`. | `Tempo.resolution/1` |
| unit | A year, a month, a day, an hour and the rest. A walk of a value yields the unit below its resolution; a walk of an interval, its ends' own. | `Tempo.walk/2` |
| bounded | Both ends are stated. | `Tempo.bounded?/1` |
| open | An end is not stated (`2026-06-15/..`). | `Tempo.Interval.to/1` |
| duration | A length of time with no place on the time line (`P1M`). | `Tempo.Duration`, `Tempo.duration/1` |
| instant | A point with no length. Tempo has none: its finest value is a span as long as its resolution. | |

## Placing a value

| Term | Meaning | Where |
|---|---|---|
| anchored | The value has a year, and so a place on the time line. | `Tempo.anchored?/1` |
| unanchored | The value has no year and comes round again: 10:30, or 15 June. | `Tempo.anchored?/1` |
| frame | What two expressions must share to be related or combined: the one time line of zoned values, the wall clock of floating ones, or the cycle of values with no year. | `Tempo.FrameError` |
| `at`, `on` | Place a time of day on a day: 17:00 on 15 June. | `Tempo.at/2`, `Tempo.on/2` |
| floating | The value is a reading of a clock, in no zone. | `Tempo.floating?/1` |
| zoned | The value is in a named zone or carries a shift. | `Tempo.zoned?/1`, `Tempo.in_zone/2` |
| zone | A named time zone, written as an RFC 9557 suffix (`[Europe/Paris]`). | `Tempo.shift_zone/2` |
| shift | A fixed offset from UTC written with a value (`+02:00`). Also the verb: to move a value by a duration. | `Tempo.shift/3` |
| reading | What a zone's clock shows. | `Tempo.ZoneError` |
| a reading the clock skips | A reading no moment has, on the day the clock goes forward. It is refused. | `Tempo.ZoneError` |
| a reading the clock shows twice | A reading two moments have, on the day the clock goes back. It is the first unless a shift is written with it. | `Tempo.in_zone/2` |
| calendar | A module that implements `Calendar`, in which a value's units are counted. Never a CLDR calendar type. | `Tempo.to_calendar/2` |
| calendar of weeks | A calendar whose year is a whole number of weeks and whose months are four or five of them. Its dates are a year, a month and a day, as any calendar's are, and a week date written for it is placed in its own weeks. | `Calendrical.ISOWeek` |
| territory | A CLDR territory code (`:AU`, `:SA`), which decides the weekend and the first day of the week. Never "region". | `Tempo.Territory` |

## Several values at once

| Term | Meaning | Where |
|---|---|---|
| set | Several values written as one: all of them (`{…}`), or one of them (`[…]`). | ISO 8601-2 §6 |
| member | One value of a set, or one span of an interval set. | `Tempo.IntervalSet.members/1` |
| range | The values from one to another within a set (`{1..5}`). | ISO 8601-2 §6 |
| interval set | A set of all its members, each a span: what the set operations and `to_interval/2` of several spans answer. | `Tempo.IntervalSet` |
| singular, plural | An expression that names one span, or several: a value with a set or a mask in a unit, a set, a recurrence. | `Tempo.members/1` |
| covered | The time at least one member of an interval set holds. | `Tempo.duration/1`, `Tempo.IntervalSet.covered/2` |
| slot | A bookable piece of free time. | `Tempo.IntervalSet.slots/3` |
| unspecified digits | Digits written as `X`: `202X` is some year of the 2020s. | ISO 8601-2 §4.6 |
| mask | A unit that holds unspecified digits. | ISO 8601-2 §4.6 |
| group | A run of a unit's values counted in equal parts: `2G3MU` is the second group of three months. | ISO 8601-2 §5 |
| qualification | A mark that a value is uncertain (`?`), approximate (`~`) or both (`%`). | ISO 8601-2 §4.5 |
| margin of error | A value with a stated error (`2018±2Y`). | `guides/uncertain-dates.md` |
| significant digits | How many of a year's digits are known (`1950S2`). | ISO 8601-2 §4.4.3 |

## Recurrences

| Term | Meaning | Where |
|---|---|---|
| recurrence | A span repeated at a cadence (`R5/2026-06-15/P1W`). | `~o"R5/2026-06-15/P1W"`, `Tempo.RRule.parse/2` |
| start | The first value a recurrence counts from. | ISO 8601 |
| cadence | The duration from one period of a recurrence to the next. | ISO 8601-1 §5.6 |
| period | The span a recurrence steps to, one cadence long. | `Tempo.select/3` |
| occurrence | One span a recurrence gives. | `Tempo.to_interval/2` |
| repeat rule | The selection a recurrence applies in each period (`F…`). ISO 8601-2's term. | ISO 8601-2 §13 |
| selection | The parts of a period that are taken (`L…N`): the 15th, the Mondays, 09:00. ISO 8601-2's term. | ISO 8601-2 §12 |
| part | One unit of a selection or of an RRULE: a month, a weekday, a position. | `Tempo.RRule` |
| position | Which of the values a selection has picked is kept: the first, the last (`I`, RFC 5545's `BYSETPOS`). | ISO 8601-2 §12.9 |
| window | A span that limits what is taken: the `:within` option's, and the span a selection opens from each date it picks. | `:within`, ISO 8601-2 §12.10 |
| `:within` | The window whose overlapping occurrences are kept. | `Tempo.to_interval/2` |
| recurrence set | Recurrences and dates held together, with the dates left out. | `Tempo.RecurrenceSet` |
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
| certainly, possibly | Whether a relation holds for every reading of an uncertain value, or for some. | `Tempo.certainly?/3`, `Tempo.possibly?/3`, `Tempo.certainty/3` |
| compare | Order two values as `:lt`, `:eq` or `:gt`, for sorting. | `Tempo.compare/3` |
| at least, at most, exactly | How a span's length stands to a duration. | `Tempo.at_least?/2` |

## What is done to a value

| Term | Meaning | Where |
|---|---|---|
| read | Turn text into a value. | `Tempo.from_iso8601/2`, `Tempo.parse/2` |
| profile | The kind of expression a text is declared to be when it is read: a date, a time, an interval. | `:profile` of `Tempo.from_iso8601/2` |
| write | Turn a value into ISO 8601 text. | `Tempo.to_iso8601/1` |
| show | Turn a value into a locale's words. | `Tempo.to_string/2` |
| explain | Say in English what a value means. | `Tempo.explain/1` |
| convert | Turn a value into another kind: its span, its occurrences, an Elixir date. | `Tempo.to_interval/2`, `Tempo.to_date/1` |
| walk | Take a span's values one after another. | `Enum`, `Tempo.walk/2` |
| select | Pick, from a base, the values a selector names. | `Tempo.select/3` |
| selector | What `select/3` selects by: a value with no year, a selection, the workdays. | `Tempo.select/3` |
| shift | Move a value by a duration. | `Tempo.shift/3` |
| truncate, round | Write a value at a coarser unit: the one it starts in, or the nearer one. | `Tempo.trunc/2`, `Tempo.round/2` |
| extend | Write a value by the unit below its own. | `Tempo.extend/2`, `Tempo.at_resolution/2` |
| union, intersection, difference, complement | The set operations, over the time spans cover. | `Tempo.union/2` |
| refuse | Return a named error rather than a guess. | `{:error, exception}` |
| not built | What Tempo knows it does not answer yet, refused by name. | `Tempo.ConversionError` |
| leap second | A second the IERS has added at the end of a UTC day. No value, and a fact about a span. | `Tempo.LeapSeconds` |

## Errors

A function that can fail returns `{:error, exception}`, and its `!` form, a predicate and a walk raise the same exception. Each says in its message what was asked, of what, and what to do instead.

| Error | Meaning | Reasons |
|---|---|---|
| `Tempo.ParseError` | A text that is not ISO 8601 as Tempo reads it. It says where the reading stopped. | |
| `Tempo.InvalidDateError` | A text that is well formed and names no date or time: a thirteenth month, the 30th of February, an event no resolver knows. | `:unit` names the unit at fault |
| `Tempo.ZoneError` | A zone Tempo cannot use. | `:unknown`, a name the database lacks; `:gap`, a reading the zone's clock skips |
| `Tempo.FrameError` | Two expressions that share no frame to be related or combined on, or one in the wrong frame for what was asked. | `:floating_and_zoned`, `:needs_a_year`, `:cycles`, `:open`, `:several`, `:zoned`, `:floating` |
| `Tempo.IntervalEndpointsError` | Ends that make no interval. | `:order`, `:calendars`, `:zones`, `:not_values` |
| `Tempo.ConversionError` | An expression that has no form in what was asked for. | `:unbounded`, a recurrence with no end and no window; `:needs_a_year`; `:open`; `:one_of`; `:too_many_values`; `:season`; `{:no_rrule, why}`; `:not_an_elixir_value` |
| `Tempo.Iso8601EncodeError` | An expression ISO 8601 has no text for: a set read from a stream, a value in a calendar no name reads back to, a member with conditions on the others of its set. | `:lazy_set`, `{:calendar, module}`, `:conditions` |
| `Tempo.InvalidCalendarError` | A calendar Tempo cannot name or use. | |
| `ArgumentError` | An argument of another kind than the function takes: an option it does not have, a unit that is none. | |

## Days of work

| Term | Meaning | Where |
|---|---|---|
| workday | A day that is not of the weekend, nor a day off. | `Tempo.workday?/2`, `Tempo.workdays/2` |
| weekend | The days a territory rests on each week. | `Tempo.weekend?/2`, `Tempo.weekends/1` |
| days off | The days left out of the workdays beside the weekend: holidays. | `:except` of `Tempo.workdays/2` |

## Notations

| Term | Meaning | Where |
|---|---|---|
| ISO 8601 | The standard Tempo reads and writes, Parts 1 and 2. | `Tempo.from_iso8601/2` |
| extended format | A date written with separators (`2026-06-15`). | ISO 8601-1 |
| basic format | A date written without them (`20260615`). | ISO 8601-1 |
| explicit form | A date written with a designator after each unit (`2026Y6M15D`), the form Tempo writes. | ISO 8601-2 §7 |
| week date | A date written by its week and its day of the week (`2026-W25-3`). | ISO 8601-1 |
| ordinal date | A date written by its day of the year (`2026-166`). | ISO 8601-1 |
| EDTF | The Extended Date/Time Format, now ISO 8601-2's uncertain and unspecified dates. | `guides/uncertain-dates.md` |
| IXDTF | RFC 9557's suffix, which names a zone or a calendar (`[Europe/Paris]`, `[u-ca=hebrew]`), written once after the whole expression. | RFC 9557 |
| RRULE | RFC 5545's recurrence rule, read into the same recurrence an ISO 8601 rule is. | `Tempo.RRule.parse/2` |
| iCalendar, JSCalendar | The calendar formats of RFC 5545 and RFC 8984. | `Tempo.ICal`, `Tempo.JSCalendar` |
