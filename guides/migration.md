# Migrating from Tempo 1.6 to 2.0

Tempo 2.0 is a new implementation of the same idea: every date and time is a span on the time line. It keeps the words of the 1.6 API and gives each one meaning, and it removes what 1.6 needed only because of how it was built: five structs, twenty-four error modules, and several functions that did one thing under two names.

Most of an upgrade is mechanical. A call to a function that no longer exists fails when it is compiled, and an option a function does not take is an error that names the option. Three changes are not mechanical, because code written for 1.6 still compiles and answers something else. They come first.

Every 2.0 example on this page is run by the test suite. The 1.6 examples were run against the published 1.6.4.

## Updating the dependency

```elixir
def deps do
  [
    {:ex_tempo, "~> 2.0"}
  ]
end
```

`Tempo.Network` and `Tempo.Schedule` are no longer in this package. They are in `tempo_network`, with their module names unchanged; add it beside `ex_tempo` if you use them.

## A written end is read through

This is the change to read every call site for. In 1.6 an interval written with two dates ended at the start of its second date: `2026-06-15/2026-06-20` was five days and did not hold the 20th. In 2.0 a date names a period of the calendar, and an interval written to a date runs through that date, as it does when it is said aloud and as EDTF and ISO 8601-2 read it.

<!-- guides:skip -->

```elixir
# 1.6
Enum.count(~o"2026-06-15/2026-06-20")
#=> 5
Tempo.overlaps?(~o"2026-06-15/2026-06-20", ~o"2026-06-20/2026-06-25")
#=> false
```

```elixir
iex> Enum.count(~o"2026-06-15/2026-06-20")
6
iex> Tempo.overlaps?(~o"2026-06-15/2026-06-20", ~o"2026-06-20/2026-06-25")
true
iex> Tempo.adjacent?(~o"2026-06-15/2026-06-20", ~o"2026-06-21/2026-06-25")
true
```

> *"The fifteenth to the twentieth is **six days**. It **overlaps** the twentieth to the twenty-fifth, which share the twentieth, and is **adjacent** to a span that starts on the twenty-first."*

An end written to a time of day is a reading of the clock, and a reading is a boundary, so nothing changes there: nine to five is eight hours and ends as five begins.

```elixir
iex> Tempo.duration(~o"2026-06-15T09/2026-06-15T17")
~o"PT8H"
iex> Tempo.Allen.meets?(~o"2026-06-15T09/2026-06-15T12", ~o"2026-06-15T12/2026-06-15T17")
true
```

The rule is by the unit the end is written to: a year, a month, a week or a date is read through; an hour, a minute or a second is a boundary. Spans are still half-open underneath, so set operations and Allen's relations are exact, and an interval is written back as it was read.

What to look for:

* **An interval that named its end by the next period**, such as `2026-06-01/2026-07-01` for June. It now holds 1 July. Write `2026-06-01/2026-06-30`, or the month itself.

* **Back-to-back bookings written with dates**, each ending on the date the next begins. They now overlap by a day. End each on its last day, or write the ends as times of day.

* **A `Date.Range` brought in with `Tempo.from_elixir/2`** needs no change. A range holds its last date, and 2.0 writes it as it is.

```elixir
iex> Tempo.equal?(~o"2026-06", ~o"2026-06-01/2026-06-30")
true
iex> Tempo.from_elixir(Date.range(~D[2026-06-15], ~D[2026-06-20]))
{:ok, ~o"2026Y6M15D/20D"}
```

`Tempo.to_interval/2` follows the same rule, so a month as an interval is June through June where 1.6 wrote June to July.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.to_interval(~o"2026-06")
#=> {:ok, #Tempo.Interval<~o"2026Y6M/7M" unit: day>}
```

```elixir
iex> Tempo.to_interval(~o"2026-06")
{:ok, ~o"2026Y6M/2026Y6M"}
iex> {:ok, june} = Tempo.to_interval(~o"2026-06")
iex> Tempo.Interval.to(june)
~o"2026Y6M"
```

## One struct

1.6 had a struct for each kind of thing: `%Tempo{}`, `%Tempo.Interval{}`, `%Tempo.IntervalSet{}`, `%Tempo.Set{}` and `%Tempo.Range{}`. In 2.0 every expression is a `%Tempo{}`, and what kind it is is its `:form`. The modules `Tempo.Interval`, `Tempo.IntervalSet` and `Tempo.RecurrenceSet` keep their functions and return a `%Tempo{}`.

<!-- guides:skip -->

```elixir
# 1.6
%Tempo.Interval{from: from, to: to} = ~o"2026-06-15/2026-06-20"
%Tempo{time: [year: year, month: month]} = ~o"2026-06"
```

A match on `%Tempo.Interval{}` or `%Tempo.IntervalSet{}` no longer compiles, and neither does one on the `:time` or `:extended` field. Ask for what you need by name, or match with the sigil, which expands to the new shape and matches any value written within it:

```elixir
iex> {from, to} = Tempo.Interval.endpoints(~o"2026-06-15/2026-06-20")
iex> {from, to}
{~o"2026Y6M15D", ~o"2026Y6M20D"}
iex> match?(~o"2026", ~o"2026-06-15")
true
iex> {Tempo.year(~o"2026-06"), Tempo.month(~o"2026-06")}
{2026, 6}
```

| 1.6 | 2.0 |
|---|---|
| `%Tempo.Interval{from: f, to: t}` | `Tempo.Interval.endpoints/1`, `from/1`, `to/1` |
| `set.intervals` | `Tempo.IntervalSet.members/1` |
| `value.time[:hour]` | `Tempo.hour/1` and its siblings |
| `value.extended.zone_id` | `Tempo.zoned?/1`; the name is `value.zone.name` |
| `value.qualification` | `Tempo.qualification/1` |
| `interval.metadata` | `Tempo.metadata/1`, `Tempo.put_metadata/2` |

A set is shown as the text that reads it, where 1.6 showed a struct, and it now has ISO 8601 text:

```elixir
iex> Tempo.union(~o"2026-06-15T09/2026-06-15T11", ~o"2026-06-16T09/2026-06-16T11")
{:ok, ~o"{2026Y6M15DT9H/T11H,2026Y6M16DT9H/T11H}"}
```

## A function that can fail returns a tuple

In 1.6 some functions that could fail returned a bare value and raised, and others returned a tuple. In 2.0 every function that can fail returns `{:ok, value}` or `{:error, exception}`, and has a `!` form that returns the value or raises.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.shift(~o"2026-06-15", day: 1)
#=> ~o"2026Y6M16D"
Tempo.to_iso8601(~o"2026-06-15")
#=> "2026Y6M15D"
```

```elixir
iex> Tempo.shift(~o"2026-06-15", day: 1)
{:ok, ~o"2026Y6M16D"}
iex> Tempo.shift!(~o"2026-06-15", day: 1)
~o"2026Y6M16D"
iex> Tempo.to_iso8601(~o"2026-06-15")
{:ok, "2026Y6M15D"}
```

These now return a tuple where 1.6 returned the value: `shift/3`, `trunc/2`, `round/2`, `at_resolution/2`, `to_iso8601/1`, `to_string/2`, `to_relative_string/2`, `from_elixir/2`, `today/1`, `now/1`, `days_in_month/1`, `workdays/2`, `weekends/1` and `Tempo.IntervalSet.coalesce/2`. The predicates, `compare/3`, `duration/1` and a walk with `Enum` return a bare value and raise the same exception.

## Names

The compiler finds every one of these.

| 1.6 | 2.0 |
|---|---|
| the `:bound` option | `:within` |
| `Tempo.subset?/3` | `Tempo.within?/3` |
| `Tempo.grounded?/1` | `Tempo.zoned?/1` |
| `Tempo.anchor/2`, `Tempo.merge/2` | `Tempo.at/2` or `Tempo.on/2`, in either order |
| `Tempo.to_date_time/1`, `from_date_time/1` | `Tempo.to_datetime/1`, `from_datetime/1` |
| `Tempo.to_naive_date_time/1`, `from_naive_date_time/1` | `Tempo.to_naive_datetime/1`, `from_naive_datetime/1` |
| `Tempo.to_calendar/1` | `Tempo.to_elixir/1` |
| `Tempo.from_date_range/2` | `Tempo.from_elixir/2` |
| `Tempo.extend_resolution/2` | `Tempo.at_resolution/2` |
| `Tempo.to_interval_set/2` | `Tempo.to_interval/2` |
| `Tempo.to_rrule/1` | `Tempo.RRule.to_string/1` |
| `Tempo.parse_date/2`, `parse_time/2`, `parse_datetime/2`, `parse_interval/2` | `Tempo.from_iso8601/2` with `:profile` |
| `Tempo.meets?/2`, `during?/2` | `Tempo.Allen.meets?/2`, `during?/2` |
| `Tempo.compose/2`, `Tempo.Interval.inverse_relation/1` | `Tempo.Allen.compose/2`, `inverse/1` |
| `Tempo.Interval.equivalent?/2` | `Tempo.equal?/3` |
| the `certainly_`, `possibly_` and `_certainty` functions | `Tempo.certainly?/3`, `possibly?/3`, `certainty/3` |
| `Tempo.add_working_days/3` | `Tempo.add_workdays/3` |
| `Tempo.next_working_day/2`, `previous_working_day/2`, `nearest_working_day/2` | `Tempo.next_workday/2`, `previous_workday/2`, `nearest_workday/2` |
| `Tempo.working_days_in/2` | `Tempo.count_workdays/2` |
| `Tempo.weekend/1` | `Tempo.weekends/1` |
| `Tempo.beginning_of_day/1`, `beginning_of_week/1`, `beginning_of_month/1` | `Tempo.trunc/2` |
| `Tempo.end_of_day/1`, `end_of_month/1` | the day or month `Tempo.trunc/2` gives, which is its own span |
| `Tempo.IntervalSet.to_list/1` | `Tempo.IntervalSet.members/1` |
| `Tempo.IntervalSet.total_duration/1` | `Tempo.duration/1` |
| `Tempo.IntervalSet.overlapping/2` | `Tempo.IntervalSet.covered/2` |
| `Tempo.ICal.from_ical/2` given text, `from_ical_file/2` | `Tempo.ICal.parse/2`, `parse_file/2` |
| `Tempo.ICal.available_from_ical/2` | `Tempo.ICal.available/2` |
| `Tempo.JSCalendar.to_interval_set/2` | `Tempo.JSCalendar.parse/2` |
| `Tempo.RRule.Expander.expand/3` | `Tempo.RRule.parse/2`, then `Tempo.to_interval/2` |
| `Tempo.Clock.utc_now/0` | `Tempo.utc_now/0` |
| the functions of `Tempo.Operations`, `Tempo.Select`, `Tempo.Format`, `Tempo.Compare` and `Tempo.Explain` | the same names on `Tempo` |
| the relations, predicates and lengths on `Tempo.Interval` | the same names on `Tempo` |
| the `W` and other modifiers of `~o` | a `[u-ca=…]` suffix in the text |

Each operation is documented on `Tempo` and nowhere else. The modules 1.6 listed as its engine (the tokenizer, the comparison of values, the RRULE expander, `Tempo.TimeZoneDatabase`, `Tempo.Clock.Test`) are no part of the API.

A search finds most of the renames before the compiler does:

```bash
grep -rnE 'bound:|subset\?|grounded\?|Tempo\.(anchor|merge|meets\?|during\?|compose)\(|_date_time|to_calendar\(|from_date_range|extend_resolution|to_interval_set|to_rrule|parse_(date|time|datetime|interval)|inverse_relation|equivalent\?|certainly_|possibly_|_certainty|working_day|Tempo\.weekend\(|beginning_of_|end_of_(day|month)|IntervalSet\.(to_list|total_duration|overlapping)|from_ical|Expander|Tempo\.(Operations|Select|Format|Compare)\.|%Tempo\.(Interval|IntervalSet|Set|Range)\{' lib test
```

## An option a function does not take is an error

1.6 passed over an option it did not know. 2.0 refuses it, so a misspelt window is not read as no window, and the 1.6 name of an option says what it became.

```elixir
iex> Tempo.to_interval(~o"R/2020-01-01/P1Y", bound: ~o"2026")
{:error, %ArgumentError{message: ":bound is not an option of Tempo.to_interval/2: it is :within"}}
```

## A value that names no calendar is in Calendar.ISO

In 1.6 a value written with no calendar was in `Calendrical.Gregorian`. In 2.0 it is in `Calendar.ISO`, Elixir's own, so its dates are the ones the standard library gives and takes. `Calendrical.Gregorian` is a calendar like any other, read from `[u-ca=gregory]`.

```elixir
iex> (~o"2026-06-15").calendar
Calendar.ISO
iex> (~o"2026-06-15[u-ca=gregory]").calendar
Calendrical.Gregorian
```

> *"A date is in Elixir's calendar unless it says otherwise."*

## Walking a plural expression gives its members

`Enum` over one span gives the units below it, as before: a month its days, a day its hours. Over an expression that is several spans (a set, a recurrence, a value with a list in it) 1.6 had two rules, and a recurrence was walked by the units inside its occurrences. In 2.0 a plural expression gives its members, always.

<!-- guides:skip -->

```elixir
# 1.6
Enum.count(~o"R5/2022-01-01/P1M")
#=> 151
Enum.count(Tempo.to_interval!(~o"2026Y{1,3}M"))
#=> 62
```

```elixir
iex> Enum.count(~o"R5/2022-01-01/P1M")
5
iex> Enum.count(Tempo.to_interval!(~o"2026Y{1,3}M"))
2
iex> Enum.count(~o"2026-06")
30
```

> *"Five monthly occurrences are **five** things. January and March are **two**. June is thirty days."*

An interval made from a value no longer carries a unit to walk by. `Tempo.to_interval(~o"2026-06-15")` is the interval of that one day, which walks its one day, where 1.6 kept `unit: hour` on it to walk 24 hours. To walk a span at a unit, say the unit:

```elixir
iex> {:ok, day} = Tempo.to_interval(~o"2026-06-15")
iex> Enum.count(day)
1
iex> {:ok, hours} = Tempo.walk(day, :hour)
iex> Enum.count(hours)
24
```

An interval of two ends is walked by the finer of its ends' units, where 1.6 walked by its start's:

```elixir
iex> Enum.to_list(~o"2026/2026-03")
[~o"2026Y1M", ~o"2026Y2M", ~o"2026Y3M"]
```

## A duration is counted in its ends' unit

In 1.6 `Tempo.duration/1` and `duration/2` answered in seconds. In 2.0 they answer in the unit the ends are written in: days between two days, months between two months, hours between two hours. Years, months, weeks and days are counted on the calendar; hours, minutes and seconds are elapsed time.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.duration(~o"2026-09-28", ~o"2026-11-03")
#=> {:ok, ~o"PT3110400S"}
```

```elixir
iex> Tempo.duration(~o"2026-09-28", ~o"2026-11-03")
{:ok, ~o"P36D"}
iex> Tempo.duration(~o"2026-06")
~o"P1M"
```

> *"From the twenty-eighth of September to Election Day is **thirty-six days**. June is **a month** long."*

Code that read the seconds converts the duration. A month or a year has no fixed length, so converting one takes a date to count from:

```elixir
iex> Tempo.Duration.to_unit(~o"P36D", :second)
{:ok, 3110400.0}
iex> Tempo.Duration.to_unit(~o"P3M", :day, relative_to: ~o"2026-01-01")
{:ok, 90.0}
```

The duration of a set is the time it covers, counting time two members share once. In 1.6 that was `Tempo.IntervalSet.total_duration/1`, and `duration/1` added the members' lengths.

```elixir
iex> {:ok, bookings} = Tempo.union(~o"2026-06-15T09/2026-06-15T11", ~o"2026-06-15T10/2026-06-15T12")
iex> Tempo.duration(bookings)
~o"PT3H"
```

> *"Two bookings, nine to eleven and ten to twelve, **cover** three hours."*

## A zoned value's hours are time on the time line

In 1.6 `Tempo.shift/2` added every unit to a zoned value's wall clock, so five hours after 23:00 on the night New York springs forward was 04:00, four hours later. In 2.0 hours, minutes and seconds are elapsed time, and the answer is the reading the clock shows then. Years, months, weeks and days still step the calendar, so a day after noon is noon.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.shift(~o"2026-03-07T23[America/New_York]", hour: 5)
#=> ~o"2026Y3M8DT4H[America/New_York]"
```

```elixir
iex> Tempo.shift(~o"2026-03-07T23[America/New_York]", hour: 5)
{:ok, ~o"2026Y3M8DT5H[America/New_York]"}
iex> Tempo.shift(~o"2026-03-07T12[America/New_York]", day: 1)
{:ok, ~o"2026Y3M8DT12H[America/New_York]"}
```

> *"Five hours after eleven at night is five in the morning, though the clocks went forward in between; a day after noon is noon."*

A shift of months and days applies the months, brings the day into the month they land in, and then counts the days, as `Date.shift/2` does. A unit that is none is an error, where 1.6 passed it over.

```elixir
iex> Tempo.shift(~o"2026-07-29", month: -5, day: -1)
{:ok, ~o"2026Y2M27D"}
iex> Tempo.shift(~o"2026-06-15", fortnight: 1)
{:error, %ArgumentError{message: "[:fortnight] are not units of a duration"}}
```

## Before and after share no instant

`Tempo.before?/2` and `Tempo.after?/2` answer the everyday question: is one over by the time the other starts? In 1.6 they were Allen's `:precedes`, which also needs a gap between the two, so a meeting that ends as lunch starts was not before lunch.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.before?(~o"2026-06-15T11/2026-06-15T12", ~o"2026-06-15T12/2026-06-15T13")
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

`Tempo`'s predicates are the everyday ones: `before?`, `after?`, `adjacent?`, `overlaps?`, `disjoint?`, `within?`, `contains?` and `equal?`, each for any two expressions, sets included. Allen's thirteen relations are in `Tempo.Allen` under Allen's own names, beside `inverse/1` and `compose/2`.

```elixir
iex> Tempo.Allen.during?(~o"2026-06-21", ~o"2026-06")
true
iex> Tempo.Allen.compose(:precedes, :during)
[:precedes, :meets, :overlaps, :starts, :during]
```

## One function for certainty

The eleven functions `certainly_before?/2`, `possibly_within?/2`, `overlap_certainty/2` and their like are three, which take the predicate as their first argument and so cover every predicate and every Allen relation.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.certainly_before?(~o"2026-06~", ~o"2026-08")
Tempo.overlap_certainty(~o"2026-06~", ~o"2026-06-15")
```

```elixir
iex> Tempo.certainly?(:before, ~o"2026-06~", ~o"2026-08")
true
iex> Tempo.certainty(:overlaps, ~o"2026-06~", ~o"2026-06-15")
:certain
```

> *"About June is **certainly before** August."*

## Today is a date

`Tempo.today/1` and `Tempo.utc_today/0` are the calendar date with no zone, where 1.6 gave the zoned day. A date written without a zone (a holiday, a birthday) relates to it directly, where the zoned day raised `Tempo.FloatingTempoError`. `Tempo.now/1` is still the zoned instant.

```elixir
iex> {:ok, today} = Tempo.today("Australia/Sydney")
iex> Tempo.floating?(today)
true
iex> {:ok, now} = Tempo.now("Australia/Sydney")
iex> Tempo.zoned?(now)
true
```

For the zoned day, place the date in the zone with `Tempo.in_zone/2`.

## Floating and zoned do not mix

A value with no zone is a reading of a clock, in no particular place; a value with a zone is a moment. 1.6 read the floating one as UTC in some functions and raised in others. 2.0 refuses the pair everywhere with one error, and the caller says which zone the floating value is in.

<!-- guides:skip -->

```elixir
# 1.6: the floating date is measured as though it were in UTC
Tempo.duration(~o"2026-09-28T09:00:00[Australia/Sydney]", ~o"2026-11-03")
#=> {:ok, ~o"PT3114000S"}
```

```elixir
iex> {:error, error} = Tempo.duration(~o"2026-09-28[Australia/Sydney]", ~o"2026-11-03")
iex> error.reason
:floating_and_zoned
iex> {:ok, election_day} = Tempo.in_zone(~o"2026-11-03", "Australia/Sydney")
iex> Tempo.duration(~o"2026-09-28[Australia/Sydney]", election_day)
{:ok, ~o"P36D"}
```

> *"A day in Sydney and a day in no zone share no time line to be measured on. **In** Sydney's **zone**, the two are thirty-six days apart."*

## One expression, one calendar, one zone

An IXDTF suffix (`[Europe/Paris]`, `[u-ca=hebrew]`, `[key=value]`) is written once, after the whole expression, and is the zone and the calendar of all of it. 1.6 read a suffix on either end of an interval and on a member of a set, and kept each end in its own.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.from_iso8601("2026-06-15T10:00[Europe/Paris]/2026-06-15T12:00[Europe/Paris]")
```

```elixir
iex> Tempo.from_iso8601("2026-06-15T10:00/2026-06-15T12:00[Europe/Paris]")
{:ok, ~o"2026Y6M15DT10H0M/T12H0M[Europe/Paris]"}
iex> {:error, error} = Tempo.from_iso8601("2026-06-15T10:00[Europe/Paris]/2026-06-15T12:00")
iex> error.reason
"a zone, a calendar or a tag is written once, after the whole expression"
```

`Tempo.Interval.new/1` returns an error for two ends in different zones or calendars; convert one with `Tempo.shift_zone/2` or `Tempo.to_calendar/2` first. A set is brought to its first member's calendar and zone. A time shift (`+02:00`, `Z`) is not a suffix: ISO 8601 writes one on each end, and each end keeps its own.

```elixir
iex> {:error, error} = Tempo.Interval.new(from: ~o"2026-06-15[Europe/Paris]", to: ~o"2026-06-20[America/New_York]")
iex> error.reason
:zones
```

## The window

`:within` replaces `:bound` everywhere. It keeps every occurrence that overlaps the window, for every kind of expression. In 1.6 a recurrence with a start read `:bound` as an upper limit and returned every occurrence from its start.

<!-- guides:skip -->

```elixir
# 1.6: every year from 2020 up to the bound
Tempo.to_interval(~o"R/2020-01-01/P1Y", bound: ~o"2026")
```

```elixir
iex> {:ok, this_year} = Tempo.to_interval(~o"R/2020-01-01/P1Y", within: ~o"2026")
iex> Tempo.IntervalSet.count(this_year)
1
iex> {:ok, since_2020} = Tempo.to_interval(~o"R/2020-01-01/P1Y", within: ~o"2020/2026")
iex> Tempo.IntervalSet.count(since_2020)
7
```

> *"The yearly occurrence **within** 2026 is 2026's own. For every year since 2020, the window starts in 2020."*

A window also places a value with no year, which 1.6 returned unplaced:

```elixir
iex> Tempo.to_interval(~o"6M15D", within: ~o"2026")
{:ok, ~o"2026Y6M15D/2026Y6M15D"}
```

## Selection

`Tempo.select/3` selects in every period of its base, where 1.6 selected in the first alone, and what it selects are values of the selector's own resolution, where 1.6 gave intervals.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.select(~o"2026/2029", ~o"12M25D") |> elem(1) |> Tempo.IntervalSet.count()
#=> 1
```

```elixir
iex> {:ok, christmases} = Tempo.select(~o"2026/2029", ~o"12M25D")
iex> Tempo.IntervalSet.count(christmases)
4
iex> Tempo.select(~o"2026-06", [1, 15])
{:ok, ~o"{2026Y6M1D,2026Y6M15D}"}
```

> *"**Select** the twenty-fifth of December in each year from 2026 through 2029: four Christmases."*

## Workdays

A territory's workdays are a `Tempo.Workdays`, which holds its weekdays, its weekend and the days left out of them, where 1.6 gave a set of weekdays. The names say "workday" throughout.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.add_working_days(~o"2026-06-12", 1, :US)
Tempo.select(~o"2026-06", Tempo.workdays(:US))
```

```elixir
iex> Tempo.add_workdays(~o"2026-06-12", 1, :US)
{:ok, ~o"2026Y6M15D"}
iex> Tempo.count_workdays(~o"2026-06", :US)
{:ok, 22}
iex> {:ok, working} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
iex> Tempo.IntervalSet.count(working)
22
```

> *"One **workday** after Friday the twelfth is Monday the fifteenth. June has twenty-two."*

## Reading text

`Tempo.from_iso8601/2` with a `:profile` replaces the typed parsers, and holds the text to the profile, where `Tempo.parse_date/2` read a date with a time.

```elixir
iex> Tempo.from_iso8601("2026-06-15", profile: :date)
{:ok, ~o"2026Y6M15D"}
iex> {:error, error} = Tempo.from_iso8601("2026-06-15T10", profile: :date)
iex> error.reason
"not a date"
```

A value is kept as it is written, where 1.6 resolved some forms as it read them. A week date, an ordinal date and a season keep their own units and are written back as they were read:

<!-- guides:skip -->

```elixir
# 1.6
Tempo.from_iso8601("2026-W25-2")
#=> {:ok, ~o"2026Y6M16D"}
Tempo.from_iso8601("2026-166")
#=> {:ok, ~o"2026Y6M15D"}
Tempo.from_iso8601("2026-21")
#=> {:ok, ~o"2026Y3M/5M"}
```

```elixir
iex> Tempo.from_iso8601("2026-W25-2")
{:ok, ~o"2026Y25W2K"}
iex> Tempo.from_iso8601("2026-166")
{:ok, ~o"2026Y166O"}
iex> Tempo.to_date(~o"2026-W25-2")
{:ok, ~D[2026-06-16]}
iex> Tempo.from_iso8601("2026-21")
{:ok, ~o"2026Y21M"}
```

A season of 21 to 24 has no dates of its own: spring is March to May in one hemisphere and September to November in the other, and 1.6 read the northern months everywhere. It has its months in a territory, named with `Tempo.in_territory/2` or the `:territory` and `:locale` options, and otherwise taken from the application's `:default_territory` or the current locale. A season of a hemisphere (25 to 32) runs from an equinox or a solstice to the next, and is kept as it is written where 1.6 read it into its dates.

Three texts 1.6 read are read otherwise:

* **An end of one number** takes the start's last unit: `2026-06-15/20` is the fifteenth through the twentieth, where 1.6 read a century.

* **A month and a day with no year** is written `6M15D`. `12-25` is twelve o'clock with a shift of minus twenty-five hours, and an error.

* **A zone or a calendar inside an expression** is an error, as above.

```elixir
iex> Tempo.from_iso8601("2026-06-15/20")
{:ok, ~o"2026Y6M15D/20D"}
```

## Writing text

`Tempo.to_iso8601/1`, `Tempo.to_string/2` and `Tempo.to_relative_string/2` return a tuple. Interpolating a value writes its ISO 8601 text, where 1.6 wrote the locale's words; ask for the words with `Tempo.to_string/2`.

<!-- guides:skip -->

```elixir
# 1.6
"#{~o"2026-06-15"}"
#=> "Jun 15, 2026"
```

```elixir
iex> "#{~o"2026-06-15"}"
"2026Y6M15D"
iex> Tempo.to_string(~o"2026-06-15")
{:ok, "Jun 15, 2026"}
iex> Tempo.to_relative_string(~o"2026-12-25", from: ~o"2026-06-15")
{:ok, "in 6 months"}
```

## Rounding

`Tempo.round/2` is to the nearest boundary, half way up, for every unit. 1.6 rounded half an hour down and a day in mid-June up to the next year.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.round(~o"T10:30", :hour)
#=> ~o"T10H"
Tempo.round(~o"2026-06-16", :year)
#=> ~o"2027Y"
```

```elixir
iex> Tempo.round(~o"T10:30", :hour)
{:ok, ~o"T11H"}
iex> Tempo.round(~o"2026-06-16", :year)
{:ok, ~o"2026Y"}
```

`Tempo.trunc/2` to a week gives the week, where 1.6 gave its first day:

```elixir
iex> Tempo.trunc(~o"2026-06-15T14:30", :week)
{:ok, ~o"2026Y25W"}
```

## Another zone's clock

`Tempo.shift_zone/2` gives the span a value names on the other zone's clock: the same resolution where it is one unit there and otherwise an interval, where 1.6 gave the second it starts at.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.shift_zone(~o"2026-06-15[Europe/Paris]", "America/New_York")
#=> {:ok, ~o"2026Y6M14DT18H0M0SZ-4H[America/New_York][-04:00]"}
```

```elixir
iex> Tempo.shift_zone(~o"2026-06-15T10[Europe/Paris]", "America/New_York")
{:ok, ~o"2026Y6M15DT4H[America/New_York]"}
iex> Tempo.shift_zone(~o"2026-06-15[Europe/Paris]", "America/New_York")
{:ok, ~o"2026Y6M14DT18H/15DT18H[America/New_York]"}
```

> *"Ten in Paris is four in New York. The fifteenth in Paris runs from six in the evening of the fourteenth to six in the evening of the fifteenth in New York."*

## Elixir's own types

A whole second has a precision of zero, where 1.6 gave six digits, so a converted value equals the literal that names it.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.to_elixir(~o"2026-06-15T10:00:00")
#=> {:ok, ~N[2026-06-15 10:00:00.000000]}
```

```elixir
iex> Tempo.to_elixir(~o"2026-06-15T10:00:00")
{:ok, ~N[2026-06-15 10:00:00]}
iex> Tempo.to_elixir(~o"2026-06-15T10:00:00Z")
{:ok, ~U[2026-06-15 10:00:00Z]}
```

## Recurrences

A recurring interval's occurrences are consecutive, each ending where the next starts, as ISO 8601-1 defines one. From the 31st of January by months, 1.6 left three days between the second occurrence and the third.

```elixir
iex> Tempo.to_interval(~o"R3/2026-01-31/P1M")
{:ok, ~o"{2026Y1M31D/2M27D,2026Y2M28D/3M30D,2026Y3M31D/4M29D}"}
```

A rule read from an RRULE with a start is read as RFC 5545 reads it. A monthly rule from the 31st passes over the months with no 31st, where 1.6 gave the last day of each; a yearly rule with a day of the month is that day of every month, where 1.6 gave the start's month alone; and each occurrence is as long as the start is precise, where 1.6 gave occurrences a cadence long.

<!-- guides:skip -->

```elixir
# 1.6
Tempo.RRule.parse!("FREQ=MONTHLY;COUNT=3", from: ~o"2026-01-31") |> Tempo.to_interval()
#=> {:ok, #Tempo.IntervalSet<[~o"2026Y1M31D/2M28D", ~o"2026Y2M28D/3M28D", ~o"2026Y3M31D/4M30D"]>}
```

```elixir
iex> "FREQ=MONTHLY;COUNT=3" |> Tempo.RRule.parse!(from: ~o"2026-01-31") |> Enum.map(&Tempo.Interval.from/1)
[~o"2026Y1M31D", ~o"2026Y3M31D", ~o"2026Y5M31D"]
iex> "FREQ=YEARLY;BYMONTHDAY=15;COUNT=3" |> Tempo.RRule.parse!(from: ~o"2026-06-01") |> Enum.map(&Tempo.Interval.from/1)
[~o"2026Y6M15D", ~o"2026Y7M15D", ~o"2026Y8M15D"]
```

> *"Monthly from the thirty-first: January, March and May, the months that have one."*

A recurrence with no end and no window is a `Tempo.ConversionError` whose reason is `:unbounded`, where 1.6 had `Tempo.UnboundedRecurrenceError`.

## Metadata

Data of your own travels with a value as `Tempo.metadata/1`, on any expression, where 1.6 kept it on an interval alone. It is no part of the value's text. IXDTF tags read from a text are in it under `:ixdtf_tags`.

```elixir
iex> ~o"2026-06-15" |> Tempo.put_metadata(%{source: "hr"}) |> Tempo.metadata()
%{source: "hr"}
iex> ~o"2026-06-15" |> Tempo.put_metadata(%{source: "hr"}) |> Tempo.to_iso8601()
{:ok, "2026Y6M15D"}
```

## Errors

Twenty-four exception modules are eight, each with a `:reason` that says which case it is. A match on a 1.6 module no longer compiles; the [glossary](glossary.md#errors) lists the reasons.

| 1.6 | 2.0 |
|---|---|
| `Tempo.InvalidDateError`, `InvalidTimeError`, `InvalidUnitError`, `ResolutionError`, `RoundingError` | `Tempo.InvalidDateError` for a value that names no date or time; `ArgumentError` for a unit that is none |
| `Tempo.FloatingTempoError`, `GroundedTempoError`, `ZoneOffsetMismatchError` | `Tempo.FrameError` |
| `Tempo.NonAnchoredError`, `RequiresAnchorError` | `Tempo.ConversionError` or `Tempo.FrameError`, reason `:needs_a_year` |
| `Tempo.UnboundedRecurrenceError`, `UnboundedSetError`, `MaterialisationError` | `Tempo.ConversionError`, reason `:unbounded` among others |
| `Tempo.UnknownZoneError`, `ZoneGapError`, `AmbiguousZoneError`, `DuplicateZoneError` | `Tempo.ZoneError` |
| `Tempo.RRuleError`, `CronError` | `Tempo.ParseError` |

```elixir
iex> {:error, error} = Tempo.shift(~o"2M28D", day: 1)
iex> {error.__struct__, error.reason}
{Tempo.ConversionError, :needs_a_year}
iex> {:error, error} = Tempo.from_iso8601("2026-03-08T02:30[America/New_York]")
iex> {error.__struct__, error.reason}
{Tempo.ZoneError, :gap}
```
