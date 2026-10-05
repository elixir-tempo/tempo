# Migrating to Tempo 2.0

Tempo 2.0 gives each word in its API one meaning, the one it has in everyday English. Most of the changes are renames: the compiler warns about every call to a removed function, and a leftover `:bound` option returns an error that names its replacement. A few names keep their spelling and change what they answer, and those need a read of each call site. This guide takes the changes one at a time, each with its 1.x form and its 2.0 form.

## Overview

| 1.x | 2.0 |
|---|---|
| `Tempo.IntervalSet.total_duration/1` | `Tempo.IntervalSet.duration/1` |
| the `:bound` option | `:within` |
| `Tempo.subset?/3` | `Tempo.within?/3` |
| `during?/2`, `meets?/2` on `Tempo` and `Tempo.Interval` | `Tempo.Allen.during?/2`, `Tempo.Allen.meets?/2` |
| `Tempo.Interval.inverse_relation/1` | `Tempo.Allen.inverse/1` |
| `compose/2` on `Tempo` and `Tempo.Interval` | `Tempo.Allen.compose/2` |
| `Tempo.Interval.equivalent?/2` | `Tempo.equal?/3` |
| IXDTF tags through `Tempo.new/1`'s `:metadata` | `:tags` |
| `Tempo.anchor/2` | `Tempo.on/2` or `Tempo.at/2`, in either order |
| `Tempo.NonAnchoredError`, `Tempo.RequiresAnchorError` | `Tempo.UnanchoredError` |
| `Tempo.grounded?/1` | `Tempo.zoned?/1` |
| `Tempo.GroundedTempoError` | `Tempo.ZonedTempoError` |
| `Tempo.to_date_time/1`, `from_date_time/1` | `Tempo.to_datetime/1`, `from_datetime/1` |
| `Tempo.to_naive_date_time/1`, `from_naive_date_time/1` | `Tempo.to_naive_datetime/1`, `from_naive_datetime/1` |
| `Tempo.to_calendar/1` | `Tempo.to_elixir/1` |
| `Tempo.ICal.from_ical/2`, `from_ical_file/2` | `Tempo.ICal.parse/2`, `parse_file/2` |
| `Tempo.ICal.available_from_ical/2` | `Tempo.ICal.available/2`, given text |
| `Tempo.JSCalendar.from_jscalendar/2` | `Tempo.JSCalendar.parse/2` |
| `Tempo.to_rrule/1`, `to_rrule!/1` | `Tempo.RRule.to_string/1`, `to_string!/1` |
| `Tempo.MaterialisationError` | `Tempo.ConversionError` |
| `Tempo.RRule.Expander.expand/3` | `Tempo.RRule.parse/2`, then `Tempo.to_interval_set/2` |
| `Tempo.add_working_days/3` | `Tempo.add_workdays/3` |
| `Tempo.next_working_day/2`, `previous_working_day/2` | `Tempo.next_workday/2`, `previous_workday/2` |
| `Tempo.nearest_working_day/2` | `Tempo.nearest_workday/2` |
| `Tempo.working_days_in/2` | `Tempo.count_workdays/2` |
| `Tempo.weekend/1` | `Tempo.weekends/1` |
| `Tempo.weekends(from: date)`, a lazy set | `Tempo.select/2` over a span with no end |
| `Tempo.IntervalSet.to_list/1` | `Tempo.IntervalSet.members/1` |
| `Tempo.IntervalSet.overlapping/2` | `Tempo.IntervalSet.covered/2` |
| `Tempo.beginning_of_day/1`, `beginning_of_week/1`, `beginning_of_month/1` | `Tempo.trunc/2` to `:day`, `:week` or `:month` |
| `Tempo.end_of_day/1`, `end_of_month/1` | `Tempo.Interval.to/1` of the day or month `Tempo.trunc/2` gives |
| `Tempo.Network.TimePeriod.new/2`'s `:start`, `:end` | `:from`, `:to` |
| `Tempo.Network.Solver.tighten/1` | `Tempo.Network.Solver.propagate/1` |
| `Tempo.Schedule.Slot` | `Tempo.Schedule.ScheduledTask` |
| `Tempo.Schedule.task/3`'s `:earliest` | `:not_before` |

These keep their names and change their meaning:

* **`before?/2` and `after?/2`** — two spans that meet now count, because they share no instant.

* **`today/1` and `utc_today/0`** — the date with no zone, where 1.x returned the zoned day.

* **An interval with a zone on its start only** — the zone applies to its end too, as ISO 8601-1 says.

* **`duration/1` and `duration/2`** — counted in the unit the endpoints are written in, where 1.x counted seconds.

* **`shift/2` on a zoned value** — hours, minutes and seconds are time on the time line, where 1.x added them to the wall clock.

* **`duration/1` on a set** — the time the set covers, counting time its members share once.

* **The `:within` window** — every occurrence that overlaps the window, for every kind of recurrence.

* **`Tempo.new/1`'s `:metadata`** — the value's own data, no longer written into its ISO 8601 form.

* **`parse/2` and the typed parsers** — ISO 8601 first, then the locale's words, where `parse/2` read only words and the typed parsers only ISO 8601.

* **`select/2` across a span** — selects in every period of the span, where 1.x selected in its first period alone.

* **`shift/3`'s `:skipping` on a day shifted by days or weeks** — steps from free day to free day and returns a day, where 1.x counted days of free time and returned the instant they ran out.

* **`Tempo.RecurrenceSet.new/2`** — returns `{:ok, set}` and checks its members, where 1.x returned the struct; `new!/2` returns the struct.

* **`Tempo.Network.TimePeriod.new/2`** — returns `{:ok, period}`, where 1.x returned the struct; `new!/2` returns the struct.

* **The network and schedule builders** — record an option or a value they cannot read, which the solver then returns, where 1.x ignored an unknown option and raised on a bad value.

* **`Tempo.Network.Normalize.normalize/1`** — returns `{:ok, normalized}`, or an error for a unit finer than a second, floating and zoned bounds in one network of hours, or a fraction of the axis unit, where 1.x returned the map and raised; a duration in a coarser unit than the axis is in its new `:measures`, not its `:edges`.

* **A network's lengths** — a year or a month in a network of days (or a year in one of months) is its actual length from where its period can start, in the period's calendar, where 1.x used a mean Gregorian year and month: a year from 1 January 2024 is 366 days, where it was 365.

* **`Tempo.to_iso8601/1`** — returns `{:ok, string}`, or an error for a value ISO 8601 cannot write, where 1.x returned the string and raised; `to_iso8601!/1` returns the string.

* **`Tempo.to_relative_string/2`** — counts calendar periods in the value's own calendar and on its own wall clock, and never in a unit finer than the value's own, where 1.x divided the seconds between two UTC instants by a mean month or year. It returns `{:ok, string}`, or an error where 1.x raised; `to_relative_string!/2` returns the string.

* **`Tempo.to_string/2`** — returns `{:ok, string}`, or an error for a value it cannot render, where 1.x returned the string and raised; `to_string!/2` returns the string, and interpolating a value it cannot render writes its ISO 8601 form. Several spans are joined as a list in the locale, where 1.x used commas.

* **`round/2`** — to the nearest boundary, half way up, for a date with a time too, where 1.x rounded half an hour down and a mid-June day to the next year.

* **`shift_zone/2`** — the span a value names on the other zone's clock: the same resolution where it is one unit there and otherwise an interval, where 1.x gave the second it starts at.

* **`to_time/1`, `to_naive_datetime/1`, `to_datetime/1` and `to_elixir/1`** — a whole second has a precision of zero, where 1.x gave six digits.

* **`Tempo.new/1` of a week and a day of it** — the calendar date they name, as the parser reads them, where 1.x kept the week date.

* **`shift/3` by months and days** — the months, then the days from the day they land on, as `Date.shift/2` counts; and an unknown unit is an error, where 1.x passed it over.

* **A recurrence across the end of a month** — its occurrences are consecutive, each ending where the next starts.

* **A value with no zone beside one with a zone** — refused by the set operations and the sorter, where the floating one was read as UTC.

* **An interval's walk** — by the finer of its two ends' units.

* **An interval's end of one bare number** — the start's last unit, where it was a century.

* **A span with no year that ends where it starts** — once round its cycle, where it was empty.

* **`split/1` and `at/2`** — keep the zone of the value they split or place, where 1.x dropped it.

* **A time of day under a year, a month or a week** — that time on its first day, with the day held in the value (`2026-06T17` is 17:00 on 1 June), where 1.x kept the gap.

* **`1950S0`** — a parse error, since a value has at least one significant digit.

* **Ordinal days** — a day of the year that does not resolve to a date (`350O`, `2020Y{100,200}O`) holds a `:day_of_year`, written back as `O`, where 1.x held a `:day` written `D`, so a match on `[day: _]` for one now matches `[day_of_year: _]`. The walk of one with a year yields the dates the days name (`Enum.to_list(~o"2020Y{100,200}O")` is `~o"2020-04-09"` and `~o"2020-07-18"`), and a shift reaches each of them.

* **A value's `extended` map** — a zone, an offset and tags only, and `nil` with none of them: the calendar a `[u-ca=…]` suffix names is the value's `:calendar` module alone, where 1.x also kept its name as `extended.calendar`. A value read with a suffix now equals the same value made with a calendar module, and a Gregorian value read with `[u-ca=gregory]` is written without the suffix.

## Updating the dependency

```elixir
def deps do
  [
    {:ex_tempo, "~> 2.0"}
  ]
end
```

A search for the removed names finds the renames:

```bash
grep -rnE 'bound:|subset\?|total_duration|inverse_relation|equivalent\?|Tempo\.(meets|during)\?|Interval\.(meets|during)\?|(Tempo|Interval)\.compose|Tempo\.anchor[(/]|(NonAnchored|RequiresAnchor)Error|:unanchored|grounded\?|GroundedTempoError|(to|from)_(naive_)?date_time|from_(ical|jscalendar)|available_from_ical|to_rrule|MaterialisationError|Expander.expand|working_days?|Tempo\.weekend\(|weekends\(from|IntervalSet\.(to_list|overlapping)|RecurrenceSet\.new\(|Tempo\.to_iso8601[(/]|beginning_of_|end_of_(day|month)|tighten\(|Schedule\.Slot|earliest:|extended\.calendar|(add_period|TimePeriod\.new)\([^)]*(start|end):' lib test
```

The changes of meaning need a read rather than a replace: every `before?`, `after?` and their `certainly_` and `possibly_` forms, every duration read as a count of seconds, every shift of a zoned value by hours, every `duration/1` of a set, every window, every `:metadata` passed to `Tempo.new/1`, every `select/2` across a span longer than one period, every `:skipping` shift of a day by days or weeks, every `round/2`, every `shift_zone/2` of a value coarser than a second, every conversion to an Elixir time compared with a literal, every `Tempo.new/1` of a week and a weekday, every set operation on a value with no zone and one with a zone, and every `RecurrenceSet.new/2` and `to_iso8601/1`, which the search finds.

## A set's duration is the time it covers

In 1.x, `Tempo.IntervalSet.duration/1` (and `Tempo.duration/1` of a set) added up its members' lengths, and `total_duration/1` measured the time they covered. In 2.0 `duration/1` measures the time covered, and `total_duration/1` is gone.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.IntervalSet.total_duration(bookings)
```

```elixir
iex> {:ok, bookings} = Tempo.union(~o"2026-06-15T09/2026-06-15T11", ~o"2026-06-15T10/2026-06-15T12")
iex> Tempo.duration(bookings)
~o"PT3H"
```

> *"Two bookings, nine to eleven and ten to twelve, **cover** three hours."*

The two meanings agree for the sets the set operations return, whose members never overlap. They differ only where a set keeps overlapping members apart, as a union does. A member's own length is still `Tempo.duration/1` of that member.

## A duration is counted in its endpoints' unit

In 1.x `duration/1` and `duration/2` answered in seconds. In 2.0 they answer in the unit the endpoints are written in: days between two days, months between two months, hours between two hours, and the finer unit where the endpoints differ. Years, months, weeks and days are counted on the calendar, so the day a clock change shortens is one day; hours, minutes and seconds are elapsed time, so the same day is 23 hours.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.duration(~o"2026-09-28", ~o"2026-11-03")
#=> {:ok, ~o"PT3110400S"}
```

```elixir
iex> Tempo.duration(~o"2026-09-28", ~o"2026-11-03")
{:ok, ~o"P36D"}
```

> *"From the twenty-eighth of September to Election Day is **thirty-six days**."*

Code that read the seconds converts the duration with `Tempo.Duration.to_unit/3`. A month or a year has no fixed length, so converting one, or ordering it against another duration with `Tempo.Duration.compare/3`, takes a `:relative_to` date:

```elixir
iex> Tempo.Duration.to_unit(~o"P36D", :second)
{:ok, 3110400.0}

iex> Tempo.Duration.to_unit(~o"P3M", :day, relative_to: ~o"2026-01-01")
{:ok, 90.0}
```

## A zoned value's hours are time on the time line

In 1.x `Tempo.shift/2` added every unit to a zoned value's wall clock, so five hours after 23:00 on the night New York springs forward was 04:00, four hours later. In 2.0 hours, minutes and seconds are time on the time line, and the result is the reading the clock shows then; years, months, weeks and days still step the calendar, so a day after noon is noon. An interval written as a start and a number of hours, an hour's own span and an hourly recurrence follow the same rule.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.shift(~o"2026-03-07T23[America/New_York]", hour: 5)
#=> ~o"2026Y3M8DT4H[America/New_York]"
```

```elixir
iex> Tempo.shift(~o"2026-03-07T23[America/New_York]", hour: 5)
~o"2026Y3M8DT5H[America/New_York]"

iex> Tempo.shift(~o"2026-03-07T12[America/New_York]", day: 1)
~o"2026Y3M8DT12H[America/New_York]"
```

> *"Five hours after eleven at night is five in the morning, though the clocks went forward in between; a day after noon is noon."*

## The within window

`:within` replaces `:bound` everywhere it appeared: `Tempo.to_interval/2`, `Tempo.to_interval_set/2`, the set operations, `Tempo.complement/2`, `Tempo.ICal.parse/2`, `Tempo.JSCalendar.parse/2` and the RRULE expander. A leftover `:bound` is an error that names its replacement:

```elixir
iex> Tempo.to_interval(~o"R/2020-01-01/P1Y", bound: ~o"2026")
{:error, %ArgumentError{message: ":bound is not an option of Tempo.to_interval/2; pass the window as :within"}}
```

The window keeps every occurrence that overlaps it, including one already under way when the window opens — the rule calendar clients use. In 1.x a recurrence with a start read `:bound` as an upper limit and returned every occurrence from its start up to the bound. In 2.0 the window is a window:

<!-- guides:skip -->

```elixir
# 1.x — every year from 2020 up to the bound
Tempo.to_interval(~o"R/2020-01-01/P1Y", bound: ~o"2026")
```

```elixir
iex> Tempo.to_interval(~o"R/2020-01-01/P1Y", within: ~o"2026")
{:ok, #Tempo.IntervalSet<[~o"2026Y1M1D/2027Y1M1D"]>}

iex> {:ok, since_2020} = Tempo.to_interval(~o"R/2020-01-01/P1Y", within: ~o"2020/2027")
iex> Tempo.IntervalSet.count(since_2020)
7
```

> *"The yearly occurrence **within** 2026 is 2026's own. For every year since 2020, the window starts in 2020."*

iCalendar and JSCalendar imports hold to the window the same way: `Tempo.ICal.parse(ics, within: window)` returns only the events that overlap it, one-off events as well as recurring ones.

## Before and after share no instant

`Tempo.before?/2` and `Tempo.after?/2` answer the everyday question: is one over by the time the other starts? In 1.x they followed Allen's `:precedes`, which also needs a gap between the two, so a meeting that ends as lunch starts was not before lunch.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.before?(meeting, lunch)
#=> false
```

```elixir
iex> meeting = ~o"2026-06-15T11/2026-06-15T12"
iex> lunch = ~o"2026-06-15T12/2026-06-15T13"
iex> Tempo.before?(meeting, lunch)
true
iex> Tempo.Allen.precedes?(meeting, lunch)
false
```

> *"The meeting is **before** lunch: it is over when lunch starts. It does not **precede** lunch in Allen's sense, which needs a gap between them."*

Code that relied on the gap asks `Tempo.Allen.precedes?/2`, or `Tempo.Allen.preceded_by?/2` in place of `after?/2`. The certainty forms follow the everyday meaning too: `certainly_before?/2`, `possibly_before?/2`, `certainly_after?/2` and `possibly_after?/2`.

## Allen's relations are in Tempo.Allen

`Tempo`'s predicates are the everyday ones: `before?/2`, `after?/2`, `adjacent?/2`, `overlaps?/2`, `disjoint?/2`, `within?/2`, `contains?/2` and `equal?/2`. Allen's thirteen relations, several of whose names are narrower than the same English words, are predicates in `Tempo.Allen` under Allen's own names, beside `inverse/1` and `compose/2`. `Tempo.Allen.overlaps?/2` is Allen's strict relation, where `Tempo.overlaps?/2` holds for any shared instant.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.meets?(june, july)
Tempo.during?(midsummer, june)
Tempo.Interval.inverse_relation(:precedes)
Tempo.compose(:precedes, :during)
```

```elixir
iex> Tempo.Allen.meets?(~o"2026-06", ~o"2026-07")
true
iex> Tempo.Allen.during?(~o"2026-06-21", ~o"2026-06")
true
iex> Tempo.Allen.inverse(:precedes)
:preceded_by
iex> Tempo.Allen.compose(:precedes, :during)
[:precedes, :meets, :overlaps, :starts, :during]
```

`inverse/1` and `compose/2` also take a list of relations, for reasoning when the relation between two intervals is known only to be one of several.

## Containment and sameness have one name each

`Tempo.within?/3` takes over from `subset?/3`, and answers for any two values, sets included, by the instants they cover — as its mirror `contains?/3` always has. `Tempo.Interval.equivalent?/2` is removed; `Tempo.equal?/3` asks whether two values cover the same instants.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.subset?(holidays, december)
Tempo.Interval.equivalent?(june, first_to_first)
```

```elixir
iex> {:ok, holidays} = Tempo.union(~o"2026-12-25", ~o"2026-12-26")
iex> Tempo.within?(holidays, ~o"2026-12")
true
iex> Tempo.equal?(~o"2026-06", ~o"2026-06-01/2026-07-01")
true
```

> *"Christmas and Boxing Day both fall **within** December. June is **equal** to the span from the first of June to the first of July."*

`Tempo.Interval.within?/2` stays, for a single interval: Allen's `:equals`, `:starts`, `:during` or `:finishes`.

## Today is a date

`Tempo.today/1` and `Tempo.utc_today/0` return the calendar date with no zone, where 1.x returned the zoned day. A date written without a zone — a holiday, a birthday — compares with it directly, where the zoned day raised `Tempo.FloatingTempoError`. `Tempo.now/1` is still the zoned instant.

<!-- guides:skip -->

```elixir
# 1.x — raises: a zoned day against a floating date
Tempo.relation(Tempo.today("Australia/Sydney"), ~o"2026-12-25")
```

```elixir
iex> Tempo.today("Australia/Sydney") |> Tempo.floating?()
true
```

For the zoned day, place today's date in the zone:

```elixir
iex> {:ok, zoned} = Tempo.in_zone(Tempo.today("Australia/Sydney"), "Australia/Sydney")
iex> Tempo.floating?(zoned)
false
```

`Tempo.duration/2` refuses a zoned value against a floating one, as `relation/2` always has, where 1.x measured the floating one as though it were in UTC:

```elixir
iex> Tempo.duration(~o"2026-09-28T09:00:00[Australia/Sydney]", ~o"2026-11-03")
{:error, %Tempo.FloatingTempoError{operation: :measure, value: ~o"2026Y11M3D"}}
```

## A zone on an interval's start applies to its end

An interval written with a zone or offset on its start and none on its end ends in that zone too, as ISO 8601-1 §5.5.1 says. In 1.x its end was floating, so the span straddled the zoned and floating time lines and measuring it treated the end as UTC. `Tempo.Interval.new/1` follows the same rule.

<!-- guides:skip -->

```elixir
# 1.x — the end is floating
{:ok, iv} = Tempo.from_iso8601("2018-01-15T10:00+05:00/2018-02-20T10:00")
{_from, to} = Tempo.Interval.endpoints(iv)
Tempo.floating?(to)
#=> true
```

```elixir
iex> {:ok, iv} = Tempo.from_iso8601("2018-01-15T10:00+05:00/2018-02-20T10:00")
iex> {_from, to} = Tempo.Interval.endpoints(iv)
iex> Tempo.floating?(to)
false
```

## Metadata belongs to the value

In 1.x `Tempo.new/1`'s `:metadata` was written into the value's ISO 8601 form as IXDTF suffix tags. In 2.0 it is the caller's own data, carried with the value and read with `Tempo.metadata/1`, and the tags have their own option, `:tags`:

```elixir
iex> {:ok, christmas} = Tempo.new(year: 2026, month: 12, day: 25, metadata: %{name: "Christmas Day"})
iex> Tempo.metadata(christmas)
%{name: "Christmas Day"}
iex> Tempo.to_iso8601(christmas)
{:ok, "2026Y12M25D"}

iex> {:ok, tagged} = Tempo.new(year: 2026, month: 6, day: 15, tags: %{"x-source" => "hr"})
iex> Tempo.to_iso8601(tagged)
{:ok, "2026Y6M15D[x-source=hr]"}
```

Converting a value moves its metadata to the interval or intervals it becomes, so a holiday's name travels with its day through the set operations.

## A value without a year is placed with at and on

`Tempo.anchor/2` is removed, and `at/2` and `on/2` do its work: the value with a year keeps it, the other supplies what it lacks, and either order gives the same value, so the code reads the way the sentence does. They return `{:ok, value}`, where `anchor/2` returned the value itself; `at!/2` and `on!/2` return it bare.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.anchor(~o"T17", ~o"2026-06-15")
#=> ~o"2026Y6M15DT17H"
```

```elixir
iex> Tempo.on(~o"T17", ~o"2026-06-15")
{:ok, ~o"2026Y6M15DT17H"}
iex> Tempo.at(~o"2026-06-15", ~o"T17")
{:ok, ~o"2026Y6M15DT17H"}
```

> *"Five in the afternoon **on** the fifteenth of June is the fifteenth of June **at** five in the afternoon."*

`Tempo.UnanchoredError` replaces `Tempo.NonAnchoredError` and `Tempo.RequiresAnchorError`. Every operation that needs a year and is given a value without one returns it, with a message that names the value and says to place it on a date with `Tempo.at/2` or `Tempo.on/2`:

```elixir
iex> {:error, %Tempo.UnanchoredError{} = error} = Tempo.shift(~o"2M28D", day: 1)
iex> Exception.message(error) =~ "Place the value on a date first"
true
```

"Anchored" now means one thing, that a value has a year. A recurrence whose rule names no start has an open start, and converting one with no `:within` window returns `Tempo.IntervalEndpointsError` with `reason: :open_start`, where 1.x said `:unanchored`.

## Zoned is the pair of floating

A value with a zone or an offset is zoned, and a value with neither is floating — the calendaring words, as in RFC 5545's floating time and Temporal's `ZonedDateTime`. `Tempo.zoned?/1` replaces `grounded?/1`, and `Tempo.ZonedTempoError`, which `in_zone/2` returns for a value that already has a zone, replaces `GroundedTempoError`.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.grounded?(~o"2026-06-15T09:00[Europe/Paris]")
#=> true
```

```elixir
iex> Tempo.zoned?(~o"2026-06-15T09:00[Europe/Paris]")
true
iex> Tempo.floating?(~o"2026-06-15T09:00")
true
```

> *"Nine in the morning in Paris is **zoned**; nine in the morning wherever you are is **floating**."*

## Datetime is one word

The conversions to and from Elixir's `DateTime` and `NaiveDateTime` write "datetime" as one word, as Elixir does and as `Tempo.parse_datetime/2` already did: `to_datetime/1`, `from_datetime/1`, `to_naive_datetime/1` and `from_naive_datetime/1`. `to_calendar/1`, deprecated since `to_elixir/1` arrived, is removed.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.to_date_time(meeting)
Tempo.to_calendar(birthday)
```

```elixir
iex> Tempo.to_datetime(~o"2026-06-15T09:00:00[Europe/Paris]")
{:ok, #DateTime<2026-06-15 09:00:00+02:00 CEST Europe/Paris>}
iex> Tempo.to_elixir(~o"2026-06-15")
{:ok, ~D[2026-06-15]}
```

## The format modules parse

The iCalendar and JSCalendar readers are `parse/2`, as Localize's and `URI`'s are, and an RRULE is written by `Tempo.RRule.to_string/1`, the pair of `Tempo.RRule.parse/2`. `Tempo.ICal.available/2` takes a calendar's text as well as a calendar already parsed.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.ICal.from_ical(ics, within: week)
Tempo.ICal.available_from_ical(ics, within: week)
Tempo.JSCalendar.from_jscalendar(json)
Tempo.to_rrule(interval)
```

```elixir
iex> {:ok, rule} = Tempo.RRule.parse("FREQ=WEEKLY;COUNT=4")
iex> Tempo.RRule.to_string(rule)
{:ok, "COUNT=4;FREQ=WEEKLY"}
```

## Parse reads ISO 8601 and words

`Tempo.parse/2` reads ISO 8601 first, with the whole grammar `Tempo.from_iso8601/2` reads, and a locale's own words after that; in 1.x it read words only, so an ISO 8601 datetime was an error. The typed parsers read the same, keeping only a value of their own kind:

```elixir
iex> Tempo.parse("2026-06-15T10:30", locale: :en)
{:ok, ~o"2026Y6M15DT10H30M"}
iex> Tempo.parse_date("15 June 2026", locale: :en)
{:ok, ~o"2026Y6M15D"}
```

> *"A date field takes **15 June 2026** as readily as **2026-06-15**."*

## One conversion error

`Tempo.ConversionError` replaces `Tempo.MaterialisationError`, keeping its reasons (`:bare_duration`, `:one_of_set`, `:open_range`, …), so `to_interval/2` and the other conversions share one error. The engine behind them — `Tempo.Compare`, the ISO 8601 tokenizer, the RRULE expander — is documented under Internals, and an RRULE's occurrences come from `Tempo.RRule.parse/2` and `Tempo.to_interval_set/2` rather than the expander:

```elixir
iex> {:error, %Tempo.ConversionError{reason: :bare_duration}} = Tempo.to_interval(~o"P1D")

iex> {:ok, mondays} = Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=MO;COUNT=4", from: ~o"2026-06-01")
iex> {:ok, occurrences} = Tempo.to_interval_set(mondays)
iex> Tempo.IntervalSet.count(occurrences)
4
```

## Workdays

The workday functions are named for the workday, and the weekend selector is plural, as `workdays/1` is: the workdays of June are `Tempo.select(~o"2026-06", Tempo.workdays(:AU))`, and `Tempo.weekends(:AU)` selects the weekends. `count_workdays/2` counts the workdays of any value `select/2` selects from. The functions return `{:error, reason}` for a value that is not a day or a territory they cannot resolve, where 1.x raised.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.add_working_days(~o"2026-06-12", 1, :US)
Tempo.working_days_in(june, :US)
Tempo.shift(start, ~o"P3D", skipping: Tempo.weekends(from: start))
```

```elixir
iex> Tempo.add_workdays(~o"2026-06-12", 1, :US)
~o"2026Y6M15D"
iex> Tempo.count_workdays(~o"2026-06", :US)
22
```

The weekend days from a date on, the lazy set 1.x's `weekends/1` built, are the weekends of a span with no end: `select/2` over an open-ended span selects period by period, only as far as the walk goes.

```elixir
iex> {:ok, weekends} = Tempo.select(~o"2026-06-18/..", Tempo.weekends(:US))
iex> Tempo.shift(~o"2026-06-18T16:00", ~o"P3D", skipping: weekends)
~o"2026Y6M23DT16H0M0S"
```

> *"Three days of work from Thursday at four, skipping the weekends, finish on Tuesday at four."*

A day shifted by days or weeks steps from free day to free day and lands on a day, as a day shifted by a day is the next day. 1.x counted days of free time and returned the instant they ran out, which for one day from a Friday was midnight on the Saturday.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.shift(~o"2026-06-12", ~o"P1D", skipping: Tempo.weekends(from: ~o"2026-06-12"))
#=> ~o"2026Y6M13DT0H0M0S"
```

```elixir
iex> {:ok, weekends} = Tempo.select(~o"2026-06-12/..", Tempo.weekends(:US))
iex> Tempo.shift(~o"2026-06-12", ~o"P1D", skipping: weekends)
~o"2026Y6M15D"
```

> *"The next free day after Friday 12 June, skipping the weekend, is Monday 15 June."*

A span is selected in each of its periods at its start's resolution, where 1.x selected in its first period alone: the Christmases of `~o"2026/2029"` are three, where 1.x found 2026's.

```elixir
iex> {:ok, christmases} = Tempo.select(~o"2026/2029", ~o"12-25")
iex> Tempo.IntervalSet.count(christmases)
3
```

## Sets

An interval set's members have one name, `Tempo.IntervalSet.members/1`: `to_list/1` read like `Enum.to_list/1`, which walks the days inside the members. The time covered by at least some number of members is `covered/2`, beside `covered?/2`, and it returns a tuple. `Tempo.RecurrenceSet.new/2` returns `{:ok, set}` and checks its members, as every other constructor that takes input does, with `new!/2` for the struct.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.IntervalSet.to_list(set)
Tempo.IntervalSet.overlapping(bookings, at_least: 2)
holidays = Tempo.RecurrenceSet.new([christmas, new_year])
```

```elixir
iex> bookings = Tempo.IntervalSet.new!([
...>   ~o"2026-06-15T09:00:00/2026-06-15T11:00:00",
...>   ~o"2026-06-15T10:00:00/2026-06-15T12:00:00"
...> ])
iex> {:ok, double_booked} = Tempo.IntervalSet.covered(bookings, at_least: 2)
iex> Tempo.IntervalSet.members(double_booked)
[~o"2026Y6M15DT10H0M0S/T11H0M0S"]
iex> {:ok, holidays} = Tempo.RecurrenceSet.new([~o"R/../P1Y/FL12M25DN", ~o"R/../P1Y/FL1M1DN"])
iex> {:ok, occurrences} = Tempo.to_interval_set(holidays, within: ~o"2026Y")
iex> Tempo.IntervalSet.count(occurrences)
2
```

> *"The double-booked time is the time covered by at least two bookings."*

## Span ends and the specialist modules

A period in a network names its ends `:from` and `:to`, as an interval does. A scheduled task's early and late schedules are intervals, where 1.x had four dates, and `Schedule.task/3`'s `:earliest` says what it bounds, `:not_before`. The network solver's `propagate/1` shares its verb with `Tempo.Interval.RelationNetwork`. The builders report what they cannot read rather than ignoring or raising it, so a leftover 1.x option comes back from the solver as an error that names the 2.0 option.

<!-- guides:skip -->

```elixir
# 1.x
Network.add_period(network, :k1, start: {:not_before, ~o"1200Y"}, end: {:not_after, ~o"1300Y"})
Tempo.Network.Solver.tighten(network)
Tempo.Schedule.task(schedule, :a, duration: ~o"P2D", earliest: ~o"2026-06-10")
{plan[:b].start, plan[:b].finish, plan[:b].latest_start, plan[:b].latest_finish}
```

```elixir
iex> {:ok, plan} =
...>   Tempo.Schedule.new()
...>   |> Tempo.Schedule.task(:a, duration: ~o"P2D", not_before: ~o"2026-06-10")
...>   |> Tempo.Schedule.task(:b, duration: ~o"P3D", after: :a, deadline: ~o"2026-06-20")
...>   |> Tempo.Schedule.solve()
iex> {plan[:b].early, plan[:b].late}
{~o"2026Y6M12D/15D", ~o"2026Y6M17D/20D"}
```

> *"B can run from the 12th to the 15th at the earliest, and from the 17th to the 20th at the latest."*

The instant helpers are gone. The day, week or month containing a value is `Tempo.trunc/2`, at its own resolution, and where it ends is the `to` of its span — under the half-open convention the start of the next one, as `end_of_month/1` answered:

```elixir
iex> Tempo.trunc(~o"2026-06-15T14:30", :month)
~o"2026Y6M"
iex> {:ok, june} = Tempo.to_interval(~o"2026Y6M")
iex> Tempo.Interval.to(june)
~o"2026Y7M"
```

## Writing ISO 8601 returns a tuple

`Tempo.to_iso8601/1` returns `{:ok, string}`, as `from_iso8601/2` returns `{:ok, value}`, and an error for a value ISO 8601 has no form for: a set of intervals or of recurrences, a conditional member, a cron nearest weekday or day-of-month OR day-of-week union, a recurrence with an RFC 5545 `UNTIL`, a value in a calendar IXDTF cannot name (a fiscal year, say), or anything that is not a Tempo value. 1.x returned the string and raised for those, and wrote a value in another calendar without its calendar unless it had been parsed with one. `to_iso8601!/1` returns the string.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.to_iso8601(~o"2026-12-25")
#=> "2026Y12M25D"
```

```elixir
iex> Tempo.to_iso8601(~o"2026-12-25")
{:ok, "2026Y12M25D"}
iex> {:ok, holidays} = Tempo.RecurrenceSet.new([~o"R/../P1Y/FL12M25DN", ~o"R/../P1Y/FL1M1DN"])
iex> {:error, %Tempo.Iso8601EncodeError{}} = Tempo.to_iso8601(holidays)
iex> holidays |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
["R/../P1Y/FL12M25DN", "R/../P1Y/FL1M1DN"]
```

> *"Christmas is written 2026Y12M25D. A set of holidays has no one ISO 8601 form, so each holiday is written on its own."*

## A relative time counts calendar periods

`Tempo.to_relative_string/2` counts the calendar periods from `:from` to the value in the value's own calendar and on its own wall clock, as Localize counts them. 1.x measured the seconds between the two as UTC instants and divided them by a mean month or year. It returns `{:ok, string}`, as `to_iso8601/1` does, and an error for a value it cannot count from, where 1.x raised; `to_relative_string!/2` returns the string.

<!-- guides:skip -->

```elixir
# 1.x — a day is less than a mean month
Tempo.to_relative_string(~o"2026-02-01", from: ~o"2026-01-31", unit: :month)
#=> "this month"
```

```elixir
iex> Tempo.to_relative_string(~o"2026-02-01", from: ~o"2026-01-31", unit: :month)
{:ok, "next month"}
iex> sydney = Tempo.from_iso8601!("2026-06-16T01:00[Australia/Sydney]")
iex> Tempo.to_relative_string(sydney, from: Tempo.from_iso8601!("2026-06-15T13:00:00Z"), unit: :day)
{:ok, "tomorrow"}
```

> *"The first of February is next month from the last day of January. One in the morning in Sydney is tomorrow from 13:00 UTC the day before, which is 23:00 in Sydney."*

Without a `:unit`, a value is never counted in a unit finer than its own, so a year a few months away is next year:

```elixir
iex> Tempo.to_relative_string(~o"2027", from: ~o"2026-07-01")
{:ok, "next year"}
```

A zoned value finer than a day is measured from a zoned `:from`, and a floating one is an error, a `Tempo.FloatingTempoError`, where 1.x read it as UTC.

## Formatting returns a tuple

`Tempo.to_string/2` returns `{:ok, string}`, as `to_relative_string/2` does, and an error for a value it cannot render, where 1.x raised: an open interval, a recurrence with no end and an interval set without an end have no last day to show. `to_string!/2` returns the string. Interpolation cannot return an error, so it writes such a value in its ISO 8601 form, where 1.x raised. A value naming several spans renders them as a list in the locale ("Jun 15, 2026 and Jul 4, 2026"), where 1.x joined them with commas.

```elixir
iex> Tempo.to_string(~o"2026-06-15")
{:ok, "Jun 15, 2026"}
iex> {:error, %Tempo.IntervalEndpointsError{}} = Tempo.to_string(~o"2026-06-15/..")
iex> "Open from #{~o"2026-06-15/.."}"
"Open from 2026Y6M15D/.."
```

> *"The fifteenth of June is written Jun 15, 2026. A booking open from the fifteenth has no last day to write, so it is an error, and in a sentence it is written in ISO 8601."*

## Rounding is to the nearest

`Tempo.round/2` rounds a value to the start of the unit it is in or the start of the next, whichever its own start is nearer to, and half way rounds up, as `Kernel.round/1` rounds a half. 1.x rounded half an hour down, rounded a day to its month and then the month to its year, so that 16 June became the next year, and refused a date with a time. How far into a unit a value is, is measured in the unit as it is there: a month of 31 days, a day of 23 hours where the clocks go forward.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.round(~o"T10:30", :hour)
#=> ~o"T10H"
Tempo.round(~o"2026-06-16", :year)
#=> ~o"2027Y"
```

```elixir
iex> Tempo.round(~o"T10:30", :hour)
~o"T11H"
iex> Tempo.round(~o"2026-06-16", :year)
~o"2026Y"
iex> Tempo.round(~o"2026-06-15T12:00", :day)
~o"2026Y6M16D"
```

> *"Half past ten is eleven o'clock to the nearest hour. The sixteenth of June is in the first half of its year. Noon is half way through the fifteenth, so it rounds to the sixteenth."*

## A zone shift keeps the span

`Tempo.shift_zone/2` returns the span a value names, read on another zone's clock. A value written to the second is the same second there, as in 1.x, and now keeps a fraction of a second. A coarser value keeps its resolution where its span is one unit on the other clock, and is otherwise the interval it is there, where 1.x gave the one second it starts at.

<!-- guides:skip -->

```elixir
# 1.x — a day became its first second
{:ok, new_york} = Tempo.shift_zone(~o"2026-06-15[Europe/Paris]", "America/New_York")
{Tempo.day(new_york), Tempo.hour(new_york), Tempo.minute(new_york), Tempo.second(new_york)}
#=> {14, 18, 0, 0}
```

```elixir
iex> {:ok, hour} = Tempo.shift_zone(~o"2026-06-15T14[Europe/Paris]", "America/New_York")
iex> Tempo.to_iso8601!(hour)
"2026Y6M15DT8HZ-4H[America/New_York]"
iex> {:ok, day} = Tempo.shift_zone(~o"2026-06-15[Europe/Paris]", "America/New_York")
iex> Tempo.to_iso8601!(day)
"2026Y6M14DT18H0MZ-4H/15DT18H0MZ-4H[America/New_York]"
```

> *"Two in the afternoon in Paris is eight in the morning in New York, the whole hour. The fifteenth in Paris runs from six in the evening of the fourteenth to six in the evening of the fifteenth in New York."*

## A whole second converts to a whole second

`Tempo.to_time/1`, `to_naive_datetime/1`, `to_datetime/1` and `to_elixir/1` give a second with no fraction a precision of zero, as Elixir reads the same ISO 8601 text, and a fraction the digits it is written to. 1.x gave six digits, so `Tempo.from_elixir/1` of the result was a value to the microsecond.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.to_naive_datetime(~o"2022-11-19T01:02:03")
#=> {:ok, ~N[2022-11-19 01:02:03.000000]}
```

```elixir
iex> Tempo.to_naive_datetime(~o"2022-11-19T01:02:03")
{:ok, ~N[2022-11-19 01:02:03]}
iex> Tempo.to_time(~o"T14:30:00.25")
{:ok, ~T[14:30:00.25]}
iex> {:ok, naive} = Tempo.to_naive_datetime(~o"2022-11-19T01:02:03")
iex> Tempo.from_elixir(naive)
~o"2022Y11M19DT1H2M3S"
```

> *"Three seconds past two minutes past one is that second, and converted back it is the value it was."*

## The constructor builds what the parser reads

`Tempo.new/1` returns the value the same components are read as. A week and a day of it are the calendar date they name, as an ordinal date is; 1.x kept them as a week date, a value the parser never gives. A date with a `:zone` and no time of day is that day in the zone, where 1.x refused it, and `:microsecond` is a fraction of the second as Elixir's types hold one.

<!-- guides:skip -->

```elixir
# 1.x
{:ok, day} = Tempo.new(year: 2026, week: 24, day_of_week: 3)
day.time
#=> [year: 2026, week: 24, day_of_week: 3]
```

```elixir
iex> Tempo.new(year: 2026, week: 24, day_of_week: 3)
{:ok, ~o"2026Y6M10D"}
iex> Tempo.new(year: 2026, month: 6, day: 15, zone: "Europe/Paris")
{:ok, ~o"2026Y6M15D[Europe/Paris]"}
iex> Tempo.new(hour: 10, minute: 30, second: 45, microsecond: {500_000, 1})
{:ok, ~o"T10H30M45.5S"}
```

> *"The third day of week 24 of 2026 is the tenth of June. The fifteenth of June in Paris is that day in Paris."*

## A value with no zone and one with a zone do not combine

A value with no zone has no place on the time line, so the set operations return a `Tempo.FloatingTempoError` for it and a zoned value, and `Tempo.compare/3` and the predicates raise it, where the floating one was read as UTC. `Tempo.relation/2` and the certainty functions return the error where they raised it. Place the floating value with `Tempo.in_zone/2` first.

```elixir
iex> {:error, %Tempo.FloatingTempoError{}} = Tempo.union(~o"2026-06-15T10", ~o"2026-06-15T10Z")
iex> {:ok, in_utc} = Tempo.in_zone(~o"2026-06-15T10", "Etc/UTC")
iex> {:ok, both} = Tempo.union(in_utc, ~o"2026-06-15T11Z")
iex> Tempo.IntervalSet.count(both)
2
```

> *"Ten o'clock nowhere in particular and ten o'clock in UTC are not put together. Placed in UTC, ten o'clock joins eleven."*

## An interval is walked by its finer end

An interval whose ends are written to two resolutions is walked by the finer of them, so the values it yields are the interval and none runs past its end. It was walked by its start's unit.

```elixir
iex> Enum.to_list(~o"2026/2026-03")
[~o"2026Y1M", ~o"2026Y2M"]
```

> *"From 2026 to March 2026 is January and February."*

## An interval's bare end is the start's last unit

An interval's end written as one bare number is the unit its start ends with, as ISO 8601-1 §5.5.1 lets an end leave out what it shares with its start. The number was read as what it is alone, a century, and the interval ran backwards. A century at an interval's end is written with its designator.

```elixir
iex> Tempo.from_iso8601!("2026-06-15/20") == Tempo.from_iso8601!("2026-06-15/2026-06-20")
true
iex> Tempo.from_iso8601!("2026-06-15T10:30/45") == Tempo.from_iso8601!("2026-06-15T10:30/2026-06-15T10:45")
true
```

> *"The fifteenth to the twentieth. Half past ten to a quarter to eleven."*

## Months, then days

`Tempo.shift/3` applies a duration's years and months, brings the day into the month they land in, and then counts its days, as `Date.shift/2` does. A recurrence's occurrences are consecutive, each ending where the next starts, as ISO 8601-1 defines a recurring interval. Across the end of a short month both gave another answer.

```elixir
iex> Tempo.shift(~o"2026-07-29", month: -5, day: -1)
~o"2026Y2M27D"
iex> {:ok, months} = Tempo.to_interval(~o"R3/2026-01-31/P1M")
iex> months |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.Interval.to/1)
[~o"2026Y2M28D", ~o"2026Y3M31D", ~o"2026Y4M30D"]
```

> *"Five months before the twenty-ninth of July is the end of February, and the day before that is the twenty-seventh. A month from the end of January ends at the end of February, the next at the end of March, and the third at the end of April."*

## A span that ends where it starts

A span with no year lies on a cycle: the day for a time of day, the week for a day of the week, the year for a month and a day. One that ends where it starts is once round, where it was empty. With a year, a span that ends where it starts is still empty.

```elixir
iex> Tempo.empty?(~o"T0H/T0H")
false
iex> Enum.count(~o"T0H/T0H")
24
iex> Tempo.empty?(~o"2026-06-15/2026-06-15")
true
```

> *"Midnight to midnight is the whole day, twenty-four hours of it."*

## A window takes the zone of what it bounds

A `:within` window with no zone bounds a value in a zone in that zone, where it was read as UTC. A window written with a zone or an offset is the moments it names.

```elixir
iex> late_show = Tempo.from_iso8601!("R/2026-05-30T23:30[America/New_York]/P1D")
iex> {:ok, shows} = Tempo.to_interval(late_show, within: ~o"2026-06-01/2026-06-03")
iex> shows |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.day(Tempo.Interval.from(&1)))
[31, 1, 2]
```

> *"The shows within the first two days of June in New York are the one that runs into the first, and those that start on the first and the second."*

## A time of day is on a day

A time of day written under a year, a month or a week, with the day left out, is that time on the first day of what is written, and the value holds the day. 1.x kept the gap, and each function read it its own way: such a value compared as equal to any day of its year, and a day added to it was lost. `Tempo.at/2` places a time of day on a year or a month the same way, and under a group it is the first day of the group.

```elixir
iex> ~o"2026-06T17"
~o"2026Y6M1DT17H"
iex> Tempo.at(~o"2026", ~o"T17")
{:ok, ~o"2026Y1M1DT17H"}
iex> Tempo.shift(~o"2026YT17H", day: 1)
~o"2026Y1M2DT17H"
```

> *"Five o'clock in June 2026 is five o'clock on the first of June. Five o'clock in 2026 is on the first of January, and a day later is the second."*

ISO 8601 wants the date of a date and time complete, so reading such text at all is Tempo's own: the divergence is recorded in the [ISO 8601 conformance guide](iso8601-conformance.md). That time on each day of a month is written with the days named, `~o"2026Y6M{1..-1}DT17H"`.
