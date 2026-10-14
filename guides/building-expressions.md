# Building expressions

An expression can be written, as ISO 8601 writes it, or built from its parts. A literal in source code is written with the `~o` sigil. A value whose units arrive at runtime (a form, a database row, an API payload) is built with `Tempo.new/1`. A rule, or any expression said a piece at a time, is built with the steps of `Tempo.Builder`: each step refines the expression the step before made, so the pipeline reads as the sentence it means.

A program that holds the parts of an expression builds it from them. It never writes the parts into ISO 8601 text to have the text read back.

## Setup — required for every example

```elixir
import Tempo.Sigils
import Tempo.Builder
```

## A sentence, a step at a time

```elixir
iex> every(:week)
...> |> on(:monday)
...> |> at(hour: 9)
...> |> starting(~o"2026-06-01")
...> |> times(10)
{:ok, ~o"R10/2026Y6M1D/P1W/FL1KT9HN"}
```

> *"Every week, on Monday, at nine, starting the 1st of June, ten times."*

The result is the expression `R10/2026-06-01/P1W/FL1KT9HN` reads to, written in Tempo's explicit form, and it is used as any expression is:

```elixir
iex> {:ok, standups} =
...>   every(:week) |> on(:monday) |> at(hour: 9) |> starting(~o"2026-06-01") |> times(10)
iex> standups |> Tempo.IntervalSet.members() |> Enum.take(3) |> Enum.map(&Tempo.Interval.from/1)
[~o"2026Y6M1DT9H", ~o"2026Y6M8DT9H", ~o"2026Y6M15DT9H"]
```

## Each step is an expression

Every step returns `{:ok, expression}`, and what it returns is complete: the step before the last is as usable as the last.

```elixir
iex> every(:week)
{:ok, ~o"R/../P1W"}

iex> every(:week) |> on(:monday)
{:ok, ~o"R/../P1W/FL1KN"}
```

> *"Every week." "Every week, on Monday."*

A recurrence with no start of its own is placed by a window, so a step part-way through a pipeline can be asked what it holds:

```elixir
iex> {:ok, mondays} = every(:week) |> on(:monday)
iex> mondays |> Tempo.to_interval!(within: ~o"2026-06") |> Tempo.IntervalSet.count()
5
```

The order of the steps is free where they say different things. These two pipelines build one expression:

```elixir
iex> every(:week) |> on(:monday) |> at(hour: 9)
{:ok, ~o"R/../P1W/FL1KT9HN"}

iex> every(:week) |> at(hour: 9) |> on(:monday)
{:ok, ~o"R/../P1W/FL1KT9HN"}
```

## What repeats

`every/1` takes a unit, a duration, or a duration's units:

```elixir
iex> every(:month)
{:ok, ~o"R/../P1M"}

iex> every(week: 2)
{:ok, ~o"R/../P2W"}

iex> every(~o"PT90M")
{:ok, ~o"R/../PT90M"}
```

## Choosing days

`on/3` selects days: a weekday by its name, several of them, or the parts of a selection.

```elixir
iex> every(:week) |> on([:monday, :wednesday, :friday])
{:ok, ~o"R/../P1W/FL{1,3,5}KN"}

iex> every(:year) |> on(month: 12, day: 25)
{:ok, ~o"R/../P1Y/FL12M25DN"}

iex> every(:month) |> on(day: -1)
{:ok, ~o"R/../P1M/FL-1DN"}

iex> every(:year) |> on(event: "easter")
{:ok, ~o"R/../P1Y/FL(easter)eN"}
```

> *"Every week, on Monday, Wednesday and Friday." "Every year, on the 25th of December." "Every month, on its last day." "Every year, on Easter Sunday."*

Its `:nth` option says which of the days in each repeat: the second, or the last.

```elixir
iex> every(:month) |> on(:monday, nth: 2)
{:ok, ~o"R/../P1M/FL1K2IN"}

iex> every(:month) |> on(:friday, nth: -1)
{:ok, ~o"R/../P1M/FL5K-1IN"}
```

> *"Every month, on its second Monday." "Every month, on its last Friday."*

Weekdays here are named days, Monday to Sunday. Which days a territory works is its own, and `Tempo.workdays/1` knows it.

A selection made beforehand, with `Tempo.selection/1`, is given as it is. This one is the Friday before Easter:

```elixir
iex> {:ok, good_friday} =
...>   Tempo.selection(selection: [event: "easter"], window: ~o"-P7D", day_of_week: 5, instance: -1)
iex> {:ok, every_good_friday} = every(:year) |> on(good_friday)
iex> every_good_friday |> Tempo.to_interval!(within: ~o"2026") |> Tempo.IntervalSet.map(&Tempo.Interval.from/1)
[~o"2026Y4M3D"]
```

A day can be counted from another the expression already selects. `:within` gives the window it is counted in, forward or, with a negative length, back:

```elixir
iex> every(:year) |> on(event: "easter") |> on(:sunday, nth: -1, within: [day: 50])
{:ok, ~o"R/../P1Y/FLL(easter)eN/P50D7K-1IN"}

iex> every(:year) |> on(event: "easter") |> on(:friday, nth: 1, within: [day: -3])
{:ok, ~o"R/../P1Y/FLL(easter)eN/P-3D5K1IN"}
```

> *"Pentecost, the last Sunday in the fifty days from Easter." "Good Friday, the Friday in the three days before it."*

It is how a holiday falling on a weekend is moved. Christmas on a Sunday, kept on the Monday in the eight days from it:

```elixir
iex> every(:year) |> on(month: 12, day: 25) |> on(:sunday) |> on(:monday, nth: -1, within: [day: 8])
{:ok, ~o"R/../P1Y/FLL12M25D7KN/P8D1K-1IN"}
```

`lasting/2` makes each day selected the start of a stretch: a holiday of several days.

```elixir
iex> every(:year) |> on(month: 8, day: 16) |> lasting(day: 2)
{:ok, ~o"R/../P1Y/FLL8M16DN/P2DN"}
```

## Times of day

`at/2` selects a time of day, given as its parts or written as a value:

```elixir
iex> every(:day) |> at(hour: 9, minute: 30)
{:ok, ~o"R/../P1D/FLT9H30MN"}

iex> every(:day) |> at(~o"T17:00")
{:ok, ~o"R/../P1D/FLT17H0MN"}
```

A time given to a day counted by its position is a time on that day, so the second Monday at nine is nine o'clock of each second Monday:

```elixir
iex> every(:month) |> on(:monday, nth: 2) |> at(hour: 9)
{:ok, ~o"R/../P1M/FLL1K2INT9HN"}
```

## What a value says of itself

`uncertain/2` and `approximate/2` mark a value as ISO 8601-2's `?` and `~` do: the whole of it, or the units named. Both together are `%`.

```elixir
iex> uncertain(~o"2026-06-15")
{:ok, ~o"2026Y6M15D?"}

iex> ~o"2026-06-15" |> uncertain(:month) |> approximate(:day)
{:ok, ~o"2026Y6?M15~D"}
```

> *"The 15th of June 2026, perhaps." "The 15th of June 2026: the month uncertain, the day approximate."*

An interval's marks are on its ends, so each end is marked before the two are joined:

```elixir
iex> {:ok, from} = uncertain(~o"1984")
iex> {:ok, to} = approximate(~o"2004")
iex> until(from, to)
{:ok, ~o"1984Y?/2004Y~"}
```

`grouped/3` names the nth group of a length within a value, and `some/2` a unit the value leaves unspecified:

```elixir
iex> grouped(~o"2026", 2, month: 3)
{:ok, ~o"2026Y2G3MU"}

iex> some(~o"2026-06", :day)
{:ok, ~o"2026Y6MX*D"}
```

> *"The second three months of 2026." "Some day of June 2026."*

A mask (`202X`), a margin (`2026±2Y`) and significant digits (`1950S2Y`) are rarer, and `Tempo.new/1` builds them from what each unit holds.

## Where it begins and ends

`starting/2` gives a recurrence its first repeat, and `until/2` its last; `times/2` counts its occurrences instead, and `ending/2` counts them back from where they end.

```elixir
iex> every(:day) |> starting(~o"2026-06-01") |> until(~o"2026-06-30")
{:ok, ~o"R/2026Y6M1D/P1D/2026Y6M30D"}

iex> every(:month) |> ending(~o"2026-06-01") |> times(5)
{:ok, ~o"R5/P1M/2026Y6M1D"}
```

> *"Every day from the 1st of June until the 30th." "Five months, the last ending on the 1st of June."*

A recurrence starts once and ends once: a second start, or a count beside an `until`, is refused rather than either one kept.

`until/2` given a value is the interval from it through the value it runs until:

```elixir
iex> until(~o"2026-06-01", ~o"2026-06-12")
{:ok, ~o"2026Y6M1D/12D"}
```

## Its frame

`in_zone/2` places an expression in a time zone, or at a fixed offset, as a suffix written after it does:

```elixir
iex> every(:week) |> on(:monday) |> at(hour: 9) |> in_zone("Europe/Paris")
{:ok, ~o"R/../P1W/FL1KT9HN[Europe/Paris]"}
```

A start given after the zone is read on its clock, so the order of the two does not matter:

```elixir
iex> every(:week) |> in_zone("Europe/Paris") |> starting(~o"2026-06-01T09:00")
{:ok, ~o"R/2026Y6M1DT9H0M/P1W[Europe/Paris]"}
```

`in_calendar/2` counts a recurrence with no start in another calendar. A start given to it after is brought to that calendar, and a start given to a recurrence whose calendar is still the default gives it its own:

```elixir
iex> every(:year) |> on(month: 7, day: 1) |> in_calendar(Calendrical.Hebrew)
{:ok, ~o"R/../P1Y/FL7M1DN[u-ca=hebrew]"}

iex> every(:year) |> in_calendar(Calendrical.Hebrew) |> starting(~o"2026-06-01")
{:ok, ~o"R/5786Y9M16D/P1Y[u-ca=hebrew]"}
```

> *"Every year, on the first of Tishri." "Every year from the 1st of June 2026, which is the 16th of Sivan 5786."*

`weeks_beginning/2` begins its weeks on another day, as an RRULE's `WKST` does:

```elixir
iex> every(week: 2) |> on([:tuesday, :thursday]) |> weeks_beginning(:sunday)
{:ok, ~o"R/../P2W/FL{2,4}KN[u-fw=sun]"}
```

## The years it repeats in

`in_years/3` gives a recurrence the years it repeats in: a year, a range of them, the years from one on or up to one, or a list of those, with years left out:

```elixir
iex> every(:year) |> on(month: 9, day: 15) |> in_years(from: 2005)
{:ok, ~o"R/{2005Y/..}/P1Y/FL9M15DN"}

iex> every(:year) |> on(month: 4, day: 29) |> in_years(1949..1988)
{:ok, ~o"R/{1949Y..1988Y}/P1Y/FL4M29DN"}

iex> every(:year) |> on(month: 3, day: 1) |> in_years(through: 2016, from: 2018)
{:ok, ~o"R/{../2016Y,2018Y/..}/P1Y/FL3M1DN"}

iex> every(:year) |> on(month: 6, day: 19) |> in_years([from: 1961], except: 2011)
{:ok, ~o"R/{1961Y/..,^2011Y}/P1Y/FL6M19DN"}
```

> *"Every 15th of September from 2005." "Every 29th of April from 1949 to 1988." "Every 1st of March up to 2016, and from 2018." "Every 19th of June from 1961, but not in 2011."*

Or it keeps the years that are `:even`, `:odd`, `:leap` or `:common`, of every year or of the years it was given:

```elixir
iex> every(:year) |> on(month: 2, day: 29) |> in_years(:leap)
{:ok, ~o"R/..l/P1Y/FL2M29DN"}
```

The years are of the recurrence's calendar:

```elixir
iex> every(:year) |> on(traditional_month: 2, day: 12) |> in_calendar(Calendrical.Hebrew) |> in_years(from: 5758)
{:ok, ~o"R/{5758Y/..}/P1Y/FL2m12DN[u-ca=hebrew]"}
```

## Refining a value

The steps refine a value as they refine a recurrence. A month, on Mondays, at nine, is the Mondays of that month at nine:

```elixir
iex> {:ok, june_mondays} = ~o"2026-06" |> on(:monday) |> at(hour: 9)
iex> june_mondays
~o"2026Y6ML1KT9HN"
iex> june_mondays |> Tempo.to_interval!() |> Tempo.IntervalSet.map(&Tempo.day/1)
[1, 8, 15, 22, 29]
```

> *"The Mondays of June 2026, at nine: the 1st, 8th, 15th, 22nd and 29th."*

A set's members are each refined:

```elixir
iex> on(~o"{2026-06,2026-08}", :monday)
{:ok, ~o"{2026Y6ML1KN,2026Y8ML1KN}"}
```

An interval is a stretch of time rather than a period to select in; `Tempo.select/3` selects in one.

## Several together

`all_of/1` makes a set of what several pipelines build: a holiday and the day it is moved to.

```elixir
iex> all_of([
...>   every(:year) |> on(month: 12, day: 25, day_of_week: 1..6),
...>   every(:year) |> on(month: 12, day: 25) |> on(:sunday) |> on(:monday, nth: -1, within: [day: 8])
...> ])
{:ok, ~o"{R/../P1Y/FL12M25D{1..6}KN,R/../P1Y/FLL12M25D7KN/P8D1K-1IN}"}
```

> *"Christmas, on the 25th of December if it is not a Sunday, and on the Monday after if it is."*

## Leaving out, and carrying with it

`except/2` leaves values out, as a set of the expression and its exclusions:

```elixir
iex> every(:week) |> starting(~o"2026-06-01") |> except(~o"2026-06-08")
{:ok, ~o"{R/2026Y6M1D/P1W,^2026Y6M8D}"}
```

> *"Every week from the 1st of June, but not the 8th."*

`with_metadata/2` gives the expression a map of the caller's, which each occurrence carries:

```elixir
iex> {:ok, standup} =
...>   every(:day) |> starting(~o"2026-06-01") |> times(2) |> with_metadata(%{title: "Standup"})
iex> standup |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.metadata/1)
[%{title: "Standup"}, %{title: "Standup"}]
```

## When a step cannot be built

A step that cannot be built returns `{:error, exception}`, and every step after it passes the error on untouched, so a pipeline answers with the first thing that was wrong:

```elixir
iex> {:error, %ArgumentError{message: message}} =
...>   every(:week) |> on(:monday) |> on(:friday) |> at(hour: 9)
iex> message
":day_of_week is already selected (1)"
```

Monday and Friday are given together, `on([:monday, :friday])`; given one after the other, the second would say the first was wrong.

## From data

A program whose parts arrive at runtime builds each from them: `Tempo.new/1` for a value, and the steps for the rest. A meeting booked in a form, its weekday and hour chosen from lists and its first date from a calendar control:

```elixir
iex> chosen = %{weekday: :thursday, hour: 14, first: ~D[2026-06-04], weeks: 6}
iex> {:ok, first} = Tempo.from_elixir(chosen.first)
iex> every(:week)
...> |> on(chosen.weekday)
...> |> at(hour: chosen.hour)
...> |> starting(first)
...> |> times(chosen.weeks)
{:ok, ~o"R6/2026Y6M4D/P1W/FL4KT14HN"}
```

## Related reading

* [Selection](selection.md) — every part a selection has, each written form beside the keyword list that builds it.

* [Scheduling](scheduling.md) — recurrences, free and busy time.

* [ISO 8601 conformance](iso8601-conformance.md) — the written forms these build.
