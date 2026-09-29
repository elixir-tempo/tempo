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
grep -rnE 'bound:|subset\?|total_duration|inverse_relation|equivalent\?|Tempo\.(meets|during)\?|Interval\.(meets|during)\?|(Tempo|Interval)\.compose|Tempo\.anchor[(/]|(NonAnchored|RequiresAnchor)Error|:unanchored|grounded\?|GroundedTempoError|(to|from)_(naive_)?date_time|from_(ical|jscalendar)|available_from_ical|to_rrule|MaterialisationError|Expander.expand|working_days?|Tempo\.weekend\(|weekends\(from' lib test
```

The changes of meaning need a read rather than a replace: every `before?`, `after?` and their `certainly_` and `possibly_` forms, every duration read as a count of seconds, every shift of a zoned value by hours, every `duration/1` of a set, every window, every `:metadata` passed to `Tempo.new/1`, and every `select/2` across a span longer than one period.

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
"2026Y12M25D"

iex> {:ok, tagged} = Tempo.new(year: 2026, month: 6, day: 15, tags: %{"x-source" => "hr"})
iex> Tempo.to_iso8601(tagged)
"2026Y6M15D[x-source=hr]"
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
{:ok, #DateTime<2026-06-15 09:00:00.000000+02:00 CEST Europe/Paris>}
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

A span is selected in each of its periods at its start's resolution, where 1.x selected in its first period alone: the Christmases of `~o"2026/2029"` are three, where 1.x found 2026's.

```elixir
iex> {:ok, christmases} = Tempo.select(~o"2026/2029", ~o"12-25")
iex> Tempo.IntervalSet.count(christmases)
3
```
