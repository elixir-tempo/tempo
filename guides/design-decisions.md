# Design Decisions

Tempo 2.0 was built against nine laws (one struct, resolution as meaning, half-open spans, one calendar and one zone to an expression, a named error where the laws give no answer). Most of what Tempo does follows from them. Where they did not settle a question, a decision was made, and this guide records those decisions: the question, the alternatives that were weighed, what Tempo chose, and why.

It is written for two readers. One is using Tempo and wants to know why it answers as it does. The other is designing a date and time library of their own, and meeting the same questions: what `BYDAY=2MO,2WE` means in ISO 8601-2, what a set operation does with a recurrence that never ends, what an offset written beside a zone that disagrees with it is. The alternatives are given in full because each is a design another library could reasonably choose.

The decisions are grouped by subject. Each is numbered as it is in the project's record, which also holds the context each arose in and the state of the code at the time.

## Setup — required for every example

```elixir
import Tempo.Sigils
```

## Sets and expressions with no end

A recurrence with no end (`R/2026-06-01/P1W/FL1KN`, every Monday from 1 June 2026) is a set with infinitely many members. Set operations and predicates need an answer for it that is exact, and that finishes.

### What a set operation answers when an operand has no end (decisions 9 and 21)

**The question.** What do `Tempo.union/3`, `Tempo.intersection/3`, `Tempo.difference/3` and `Tempo.symmetric_difference/3` answer when one operand, or both, has no end?

**The alternatives.**

* Refuse any operand with no end unless the caller gives a window (`:within`).

* Window the endless operand by the other operand, always.

* Leave the two kinds of endless operand (a recurrence, and a set read from a stream) to answer differently, as they did.

**Tempo's choice.** The result is as bounded as the mathematics makes it. With A endless and B bounded:

* `intersection` in either order, and `difference(B, A)`, lie inside B, so A is taken within B. That is exact.

* `union` in either order, `symmetric_difference`, and `difference(A, B)` are themselves endless. They are answered as endless sets in time order, which a caller bounds with `:within` or takes from with `Enum.take/2`. Windowing `difference(A, B)` by B would drop all of A after B ends.

* Of two endless operands, only `union` is answered. `intersection`, `difference` and `symmetric_difference` are a `Tempo.ConversionError` with reason `:unbounded` unless `:within` is given.

```elixir
iex> mondays = ~o"R/2026-06-01/P1W/FL1KN"
iex> {:ok, in_june} = Tempo.intersection(mondays, ~o"2026-06")
iex> Tempo.IntervalSet.count(in_june)
5
iex> {:ok, with_a_wednesday} = Tempo.union(mondays, ~o"2026-06-10")
iex> with_a_wednesday |> Enum.take(3) |> Enum.map(&Tempo.to_iso8601!/1)
["2026Y6M1D/2026Y6M1D", "2026Y6M8D/2026Y6M8D", "2026Y6M10D/2026Y6M10D"]
iex> {:error, %Tempo.ConversionError{reason: :unbounded}} =
...>   Tempo.intersection(mondays, ~o"R/2026-06-02/P1W/FL2KN")
```

**Why.** Refusing every endless operand makes the common, well-defined cases (Mondays in June) need a window that adds nothing. Windowing always is silently wrong for half the operations. The rule that remains is the one that answers exactly what can be answered exactly, and says so where it cannot.

Two endless operands are the subtle case. It first seemed that a difference of two would be an endless set, each next member taking finite work. It is not: where one operand covers the other from some day on (every week, less every second day), no next member is ever found, and the search never ends. Every Monday and every Tuesday never meet, and an intersection of them would search for ever. A union alone always makes progress.

### What a predicate answers when an operand has no end (decision 26)

**The question.** What do `Tempo.within?/2`, `contains?/2`, `overlaps?/2`, `disjoint?/2`, `equal?/2`, `before?/2`, `after?/2` and `adjacent?/2` answer when an operand has no end?

**The alternatives.**

* Answer each by a table that needs no search, and refuse two endless operands without a window.

* Refuse any predicate with an endless operand without a window.

* Take the endless operand within the other's extent, as was done, and document it.

**Tempo's choice.** The table. With E endless and B bounded: `within?(E, B)`, `contains?(B, E)`, `equal?`, `before?(E, B)` and `after?(B, E)` are false, since what has no end does not fit in what has one. `overlaps?`, `disjoint?`, `within?(B, E)` and `contains?(E, B)` are decided within B, where taking E is exact. `after?(E, B)`, `before?(B, E)` and `adjacent?` are decided by where E begins.

```elixir
iex> Tempo.within?(~o"R/2026-06-01/P1W/FL1KN", ~o"2026-06")
false
iex> Tempo.overlaps?(~o"R/2026-06-01/P1W/FL1KN", ~o"2026-06")
true
```

**Why.** Taking the endless operand within the other was sometimes right and sometimes wrong: it said every Monday for ever was within June. Each predicate has an answer that needs no search, so none needs a window.

### A member both operands of a union hold (decision 38)

**The question.** `Tempo.union/3` keeps members whole rather than merging the time they cover. Is a member both operands hold one member of the union, or two?

**The alternatives.**

* One member, where it is the same in span, written form and metadata; members that differ in any of those stay two.

* Two: the union is both operands' members, repeats included.

* One for any two members covering the same time, whatever their form or metadata.

**Tempo's choice.** The first.

```elixir
iex> {:ok, union} = Tempo.union(~o"2026-06", ~o"2026-06")
iex> Tempo.IntervalSet.count(union)
1
iex> {:ok, union} = Tempo.union(~o"2026-06", ~o"2026-06-01/2026-06-30")
iex> Tempo.IntervalSet.count(union)
2
```

**Why.** In set algebra the union of a set with itself is the set. Keeping members whole is what lets a union carry each member's metadata (two bookings of one hour are two bookings), so members that differ in form or metadata stay apart, and merging the time they cover is left to `Tempo.IntervalSet.coalesce/1`.

### The order of a selection by a list (decision 10)

**The question.** In what order does `Tempo.select/3` answer when its selector is a list, such as the 20th and the 5th of each month?

**The alternatives.** Time order with repeats removed; time order with repeats kept; the list's order, documented.

**Tempo's choice.** Time order, repeats removed, for a list of selectors and a list of integers alike.

```elixir
iex> Tempo.select(~o"2026-06/2026-07", [~o"20D", ~o"5D"])
{:ok, ~o"{2026Y6M5D,2026Y6M20D,2026Y7M5D,2026Y7M20D}"}
```

**Why.** The answer is a set, and every other set in Tempo is in time order with each member once. A list's order is how the caller happened to write it, not something the result should carry.

## Recurrence rules

Tempo reads RFC 5545's `RRULE` (and RFC 7529's extensions to it, and JSCalendar's rules, and cron) into the same recurrence an ISO 8601-2 repeating interval reads to. ISO 8601-2 and RFC 5545 do not say all the same things, and these decisions are where they part.

### Numbered weekdays of several days: `BYDAY=2MO,2WE` (decision 34)

**The question.** RFC 5545's `FREQ=MONTHLY;BYDAY=2MO,2WE` is the second Monday and the second Wednesday of each month. How is it held?

**The alternatives.**

* A set of selections, a Tempo extension, `L{1K2I,3K2I}N`: each selection is made in the period and their values are taken together, with `COUNT`, `UNTIL`, `BYSETPOS` and times of day applying to them all.

* A set of recurrences, one for each numbered weekday. It needs no new notation, but `COUNT` cannot be said (each member would count on its own), and the set is not one rule to write back.

* Refuse the rule.

**Tempo's choice.** A set of selections.

```elixir
iex> Tempo.RRule.parse("FREQ=MONTHLY;BYDAY=2MO,2WE")
{:ok, ~o"R/../P1M/FL{1K2I,3K2I}N"}
iex> Tempo.select(~o"2026-06", ~o"L{1K2I,3K2I}N")
{:ok, ~o"{2026Y6M8D,2026Y6M10D}"}
iex> Tempo.select(~o"2026-06", ~o"L{1,3}K2IN")
{:ok, ~o"{2026Y6M3D}"}
```

**Why.** ISO 8601-2 §12 allows one selection rule of a kind in a selection, and applies a position (`I`) last, over everything selected. So `L{1,3}K2IN` is the second of the Mondays and Wednesdays taken together, 3 June 2026, and not the second of each. No ISO 8601-2 selection says the RFC 5545 rule. The set of selections is the only alternative that reads every rule RFC 5545 allows and writes it back as it was read. `Tempo.selection(all: [...])` builds the same thing, and it also says "the first Monday and the last Friday" in code.

### Calendars, skipped days and week starts: `RSCALE`, `SKIP` and `WKST` (decisions 13, 14, 24, 27, 28 and 29)

**The question.** Does Tempo read RFC 7529's `RSCALE` (the calendar a rule counts in) and `SKIP` (what becomes of a day a month lacks), and a `WKST` other than Monday where it changes which weeks are counted? And where does a week start live?

**The alternatives for the three parts.** Refuse all three; read `RSCALE` alone; build all three.

**The alternatives for the week start.**

* A property of the whole expression, written once at its end as `[u-fw=sun]`, BCP 47's key for the first day of the week, as the calendar and the zone are.

* A part of the rule alone, which ISO 8601 has no way to write, and which lets a rule disagree with its own expression.

* A calendar of Sunday weeks with a name of its own.

**Tempo's choice.** All three are read, and the week start is of the whole expression. A rule with `RSCALE` is in the calendar named, so its occurrences are dates of that calendar. A `SKIP` is a part of the selection, written `(forward)s` or `(backward)s` beside the day it moves. A significant `WKST` becomes the expression's week start, held as a Gregorian calendar whose weeks begin on that day.

```elixir
iex> Tempo.RRule.parse("FREQ=YEARLY;RSCALE=CHINESE;BYMONTH=1;BYMONTHDAY=1")
{:ok, ~o"R/../P1Y/FL1m1DN[u-ca=chinese]"}
iex> Tempo.RRule.parse("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=FORWARD;RSCALE=GREGORIAN")
{:ok, ~o"R/../P1Y/FL2M29D(forward)sN"}
iex> Tempo.RRule.parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,SU;WKST=SU")
{:ok, ~o"R/../P2W/FL{2,7}KN[u-fw=sun]"}
```

**Why.** An expression is in one calendar, so a rule that counts in the Chinese calendar is a recurrence in the Chinese calendar, and its months are named as that calendar names them (`1m`, the first month; `5+m`, a leap month). A week start changes which weeks exist, which week is number 25, and what a two-week cadence steps over, so it belongs to the expression as its calendar does. Holding it as a calendar keeps the struct as it is: the engine already asks an expression's calendar every question about weeks. ISO 8601-2's selection had its own week start part (`nq`), and it was removed so that there is one way to say it. `WKST` that changes nothing is read and not kept.

### A day rolled to a weekday: cron's `W` (decisions 16, 17, 18 and 23)

**The question.** Cron's `15W` is the weekday nearest the 15th that does not leave the month. Rules by the day of the month could say `1W` to `27W`. From the 28th they cannot, since a 30th that is a Sunday rolls to Monday the 31st in a long month and back to Friday the 28th in a short one. Are `28W` to `31W` read, and what is a weekday?

**The alternatives.**

* Refuse them.

* A part of a rule that rolls a day to a weekday by a convention, so that every `nW` is one rule. It also serves a holiday observed on the nearest working day.

* Rules by the length of the month, with a condition for a leap year's February.

**Tempo's choice.** A part of the rule, written inside the selection beside the day it rolls: `31D(modified-nearest)r`. The conventions are `following`, `preceding`, `nearest`, and the three `modified-` forms, which turn back rather than leave the month. A weekday is a working day of the locale the rule is asked in, never a fixed Monday to Friday.

```elixir
iex> Tempo.Cron.parse("0 9 31W * *")
{:ok, ~o"R/../P1M/FL31D(modified-nearest)rT9H0MN"}
```

**Why.** One part that rolls is simpler than a family of conditional rules, and it is the operation holidays need as well. Working weeks differ: in some territories the week is Sunday to Thursday. A rule that hard-coded Monday to Friday would be wrong there, so the days come from the locale (the `:locale` option, or the territory in force).

### A cron expression with no start (decision 11)

**The question.** A cron expression has no start. What start does a rule read from one have?

**The alternatives.** No start, as an RRULE with no `DTSTART`; a fixed start (it was the first minute of 2000); the present moment.

**Tempo's choice.** No start. It needs `:from` or `:within` before it has occurrences.

```elixir
iex> Tempo.Cron.parse("0 9 * * 1")
{:ok, ~o"R/../P1M/FL1KT9H0MN"}
```

**Why.** A fixed start is an invented fact, and the present moment makes reading text depend on the clock. A rule with no start is what the text says, and it is the same as an RRULE read with none.

## Time zones and offsets

Tempo holds an hour, a minute or a day in a named zone as the time that zone's clock shows it, and a time shift written beside a zone (`+02:00[Europe/Paris]`) as saying which of two showings is meant. These decisions are where that rule met the edges of the time zone database.

### An hour a clock shows in two parts (decision 30)

**The question.** On 5 April 2026 the Chatham Islands' clock goes back from 03:45 to 02:45. It shows 02:00 to 03:00, then 03:00 to 03:45, then 02:45 to 03:00 a second time, then 03:00 to 04:00. What is the value of the hour from 02:00 at the second showing's offset, `T02+12:45`?

**The alternatives.**

* The part of the hour the clock shows at that offset: fifteen minutes, from 02:45.

* The sixty minutes from "02:00 at +12:45", which the clock never showed as 02:00, overlapping the hours before it.

* A walk of the day yields an interval for a partial showing, so that a walk of hours gives values and intervals.

**Tempo's choice.** The part the clock shows. A shift the zone never has within the unit is still the moment the shift gives.

```elixir
iex> {:ok, second_showing} = Tempo.from_iso8601("2026-04-05T02+12:45[Pacific/Chatham]")
iex> Tempo.duration(second_showing)
~o"PT15M"
```

**Why.** An hour in a zone is what the zone's clock shows of it, and the hours of a day should not overlap. Most zones change by whole hours at the start of an hour, where the question does not arise; Chatham's change at 03:45 by an hour is where "an hour is what the clock shows" and "a shift gives the moment" disagree, and the first is the law.

### A time of day the clock shows twice, or skips, within a period (decision 36)

**The question.** On 1 November 2026 Chicago's clock shows 01:30 twice, an hour apart. What does a selection of 01:30 in that day give, and what does a daily rule at 01:30 give that day? And on 8 March, when 02:30 is never shown?

**The alternatives.**

* One answer for selections and rules alike: a reading shown twice within the period is its first showing, as a value written `2026-11-01T01:30[America/Chicago]` is read.

* Every moment the clock shows it for a selection, and the first showing for a rule.

* Every moment the clock shows it, everywhere, so that a daily rule has two occurrences that day.

**Tempo's choice.** The first. A reading the clock skips is no value. The second showing is kept only where a period holds it and not the first, as an hour of an hourly rule does, so an hourly rule still gives each hour that passes.

```elixir
iex> {:ok, half_past_one} = Tempo.selection(hour: 1, minute: 30)
iex> Tempo.select(~o"2026-11-01[America/Chicago]", half_past_one)
{:ok, ~o"{2026Y11M1DT1H30M}[America/Chicago]"}
iex> {:ok, hourly} = Tempo.RRule.parse("FREQ=HOURLY;COUNT=4", from: ~o"2026-11-01T00:30[America/Chicago]")
iex> Enum.map(hourly, &Tempo.to_iso8601!/1)
["2026Y11M1DT0H30M/T31M[America/Chicago]", "2026Y11M1DT1H30M/T31M[America/Chicago]", "2026Y11M1DT1H30MZ-6H0M/T31MZ-6H0M[America/Chicago]", "2026Y11M1DT2H30M/T31M[America/Chicago]"]
```

**Why.** It is how Tempo already reads a value written to that time, and it is what RFC 5545 §3.3.5 says of a local time that occurs twice. Having a selection answer one way and the same selection inside a rule another would make one written form mean two things. On a time that does not occur RFC 5545 contradicts itself: §3.3.10 says such instances "MUST be ignored", and later that they are read by the offset before the gap. Tempo follows the first, which needs no invented time.

### A time shift that disagrees with its zone (decision 33)

**The question.** RFC 9557 §3.4 gives `2022-07-08T00:14:07+00:00[!Europe/London]` as its example: London was at +01:00 that day, so the offset and the zone disagree. With the critical flag `!` an application MUST act on that; without it, it MAY. `Z` in place of the offset asserts no local time, so `…Z[Europe/London]` never disagrees. What does Tempo do?

**The alternatives.**

* Refuse the critical case, and take the moment the shift gives otherwise.

* Refuse every disagreement, critical or not, as JavaScript's Temporal does by default.

* Take the moment the shift gives always, and record that the critical case is not acted on.

**Tempo's choice.** Refuse the critical case alone, and hold `+00:00` apart from `Z` so that the two can be told apart.

```elixir
iex> {:error, %Tempo.ZoneError{reason: :inconsistent}} =
...>   Tempo.from_iso8601("2022-07-08T00:14:07+00:00[!Europe/London]")
iex> {:ok, _moment} = Tempo.from_iso8601("2022-07-08T00:14:07+00:00[Europe/London]")
iex> {:ok, _moment} = Tempo.from_iso8601("2022-07-08T00:14:07Z[!Europe/London]")
```

**Why.** It is what the RFC requires, and no more. Refusing every disagreement makes a stored future meeting unreadable once a zone's rules change, which is the RFC's own example of why it permits leniency. `+00:00` says "the local time is UTC's" and `Z` says "no local time is asserted"; they are the same moment, but only one of them can disagree with a zone, so Tempo keeps them apart and writes each back as it was read.

### Relative words for a floating value beside a zoned one (decision 32)

**The question.** Every other operation refuses a floating value (one with no zone) beside a zoned one, with a `Tempo.FrameError`. May `Tempo.to_relative_string/2` count one from the other? Its default reference is the current second of UTC, so the answer decides whether `Tempo.to_relative_string(~o"2026-06-16")` works at all.

**The alternatives.**

* Answer, counting the floating value on the zoned one's clock.

* Answer for dates and refuse a floating time of day.

* Refuse always, so that every floating value needs a floating reference.

**Tempo's choice.** Answer, on the zoned one's clock. It is the one place a floating value stands beside a zoned one.

```elixir
iex> Tempo.to_relative_string(~o"2026-06-16", from: ~o"2026-06-15T23:30[Europe/Paris]")
{:ok, "tomorrow"}
```

**Why.** A floating date has no zone of its own, so the day after the day the reference's clock shows is what a person means by "tomorrow". Refusing would make the default reference an error for the commonest values.

### A set of rules in two calendars (decision 40)

**The question.** One expression is in one calendar. How then does a set hold Saudi Arabia's holidays, Islamic rules beside Gregorian ones?

**The alternatives.**

* Convert a rule as a rule: a recurrence with no end converted to another calendar is still selected in its own, and each of its occurrences is read in the other. A set brings such a member to its calendar so.

* Let a set of recurrences hold several calendars, its occurrences read in its first member's: the same mechanics, as an exception to the rule.

* Refuse, and keep a set for each calendar, combined by the caller within a window.

**The choice.** Convert a rule as a rule.

```elixir
iex> eid = Tempo.every!(~o"P1Y", select: [month: 10, day: 1], calendar: Calendrical.Islamic.UmmAlQura)
iex> national_day = Tempo.every!(~o"P1Y", select: [month: 9, day: 23])
iex> {:ok, holidays} = Tempo.RecurrenceSet.new([national_day, eid])
iex> Tempo.to_interval(holidays, within: ~o"2026")
{:ok, ~o"{2026Y3M20D/2026Y3M20D,2026Y9M23D/2026Y9M23D}"}
```

**Why.** The rule stays whole: every span the set gives is in the set's calendar, so one calendar to an expression holds where it matters, in the spans a caller sees. Converting an endless rule had been refused, since its occurrences cannot all be listed; read this way it needs none listed, and every rule converts. What such a set cannot have is ISO 8601 text, since a member's own calendar would be written inside the expression, and the writer says so.

## Seasons

ISO 8601-2 numbers seasons: 21 to 24 are spring, summer, autumn and winter, and 25 to 32 the same seasons of the northern and southern hemispheres. Spring is March to May in the north and September to November in the south.

### What a season is (decisions 19, 20 and 22)

**The question.** What span is a season?

**The alternatives.** The design taken up had three parts: seasons 21 to 24 as meteorological seasons, whole months, with the hemisphere taken from a territory; seasons 25 to 32 as astronomical seasons, from an equinox or a solstice to the next; and a season with no territory to give it a hemisphere as a named error. The alternatives were to build all of it, to build the astronomical seasons alone, or to read and write seasons and nothing more.

**Tempo's choice.** All of it. A season 21 to 24 has the months of the territory's hemisphere, given by `:territory`, `:locale`, `Tempo.in_territory/2`, or the territory in force. A season 25 to 32 runs from the day of its equinox or solstice, as Astro computes it, to the day before the next.

```elixir
iex> Tempo.to_interval(~o"2026-21", territory: :AU)
{:ok, ~o"2026Y9M/11M"}
```

**Why.** Season 21 is a different span in Sydney and London, so it cannot be one span without a territory, and a guess would be wrong for half the world. The months of a meteorological season are a convention, not a computation, so they are held in Tempo rather than asked of a calendar library. An astronomical season is a computation, and is computed.

### The order of two seasons in an interval (decisions 22 and 25)

**The question.** Autumn comes before spring south of the equator. Is `2026-23/2026-21`, autumn to spring, read?

**The alternatives.**

* Keep the order of the numbers, as EDTF's test corpus does (it lists `2012-24/2012-21` as invalid), and write a southern interval as months.

* Read any order, and hold the interval to its order once it has a hemisphere.

* Read any order only where a territory is named as the text is read.

**Tempo's choice.** The third.

```elixir
iex> Tempo.from_iso8601("2026-23/2026-21", territory: :AU)
{:ok, ~o"2026Y3M/11M"}
iex> {:error, %Tempo.IntervalEndpointsError{reason: :order}} = Tempo.from_iso8601("2026-23/2026-21")
```

**Why.** With a territory the text has a meaning, March to November in Australia, and refusing it would make a southern user write months. Without one the order cannot be checked, and EDTF's corpus is kept: the bare text stays an error.

## Calendars

Tempo does no calendar arithmetic of its own: a month's length, a leap year, a solar term and a date in another calendar are answered by [Calendrical](https://hexdocs.pm/calendrical), and by Localize for `Calendar.ISO`.

### One calendar behaviour (decisions 6 and 8)

**The question.** Who owns the contract a calendar meets, given that Elixir's `Calendar.ISO` has none of the callbacks Tempo needs?

**The alternatives.**

* A private adapter in Tempo that knows each calendar library's functions.

* A second, smaller behaviour published by Calendrical for Tempo's needs.

* Swap `Calendar.ISO` for a conforming module wherever a value enters Tempo.

**Tempo's choice.** None of the three: one behaviour, defined by Calendrical, that every calendar conforms to, including the module of Localize that answers for `Calendar.ISO`. Inside Tempo every calendar question goes through one hidden module, and a test fails if any other module names a calendar module.

**Why.** One contract means a calendar written by anyone works in Tempo if it meets the behaviour, with no table in Tempo to extend. Calendrical depends on Localize, so the behaviour cannot live in Localize. Keeping every question in one module of Tempo means the remaining knowledge of particular calendars (which module answers for `Calendar.ISO`, the Gregorian for a solar term) is in one place, to be revisited.

### A solar term of a value with no calendar (decision 7)

**The question.** Which calendar reckons a solar term, such as `qingming`, for a value in the default calendar, which has no astronomy?

**The alternatives.** Ask the Gregorian calendar of Calendrical, which reckons the terms at the traditional reference meridian; make it an error unless a calendar is written; have another module with astronomy answer for `Calendar.ISO`.

**Tempo's choice.** Ask the Gregorian.

```elixir
iex> Tempo.Event.date("qingming", 2026)
{:ok, ~D[2026-04-05]}
```

**Why.** A solar term is a moment in the year, and the Gregorian calendar has the same years and days as `Calendar.ISO`. Refusing a question whose answer is not in doubt would make every caller name a calendar to ask it.

## Words and conversion

### The unit relative words count in (decision 31)

**The question.** When no `:unit` is given, in which unit does `Tempo.to_relative_string/2` count the difference between an expression and its reference?

**The alternatives.**

* The largest unit of which a whole one lies between the two, and never a unit finer than the expression is written to.

* The first unit the two differ in. It gives "next year" for two minutes across midnight on New Year's Eve, and "5 months ago" for the year 2026 from 15 June 2026.

* Refuse, so that every call names a unit.

**Tempo's choice.** The first.

```elixir
iex> Tempo.to_relative_string(~o"2026-01-01T00:01", from: ~o"2025-12-31T23:59")
{:ok, "in 2 minutes"}
iex> Tempo.to_relative_string(~o"2026-02-01", from: ~o"2026-01-31")
{:ok, "tomorrow"}
iex> Tempo.to_relative_string(~o"2026", from: ~o"2026-06-15")
{:ok, "this year"}
```

**Why.** It says what a person would say. A year is asked about as a year, so the year a day is in is "this year", which follows from the law that a value's resolution is its meaning. A year, a quarter, a month, a week and a day are counted by the calendar's own periods, and an hour, a minute and a second by those that pass, so that the hours across a change of the clock are the hours that elapse.

### An interval of dates as an Elixir value (decision 12)

**The question.** `Tempo.from_elixir/2` reads a `Date.Range`. Does `Tempo.to_elixir/1` give one back?

**The alternatives.** A `Date.Range` for an interval whose two ends are dates, and an error for anything else; a `Date.Range` for a month or a year too; no `Date.Range` at all.

**Tempo's choice.** The first.

```elixir
iex> Tempo.to_elixir(~o"2026-06-15/2026-06-20")
{:ok, Date.range(~D[2026-06-15], ~D[2026-06-20])}
```

**Why.** An interval written to two dates holds both of them, as a `Date.Range` does, so the two are the same six days and convert both ways. A month converted to a range of its days would read back as a span of days, a different expression from the month, so it stays an error.

## Errors

### An argument that is no expression (decision 39)

**The question.** What does a function answer when it is given something that is not a Tempo expression at all: `nil`, a string, a `Date`?

**The alternatives.**

* Return a named error, `{:error, %Tempo.ConversionError{reason: :not_an_expression}}`, from every function.

* Raise `FunctionClauseError`, as most Elixir functions do for an argument of the wrong type, and leave the type to Dialyzer.

* Leave each function to answer as it happens to.

**The choice.** A named error. A function that returns its errors returns it; a function that answers a bare value raises it, as it raises its other errors.

```elixir
iex> Tempo.trunc(~D[2026-06-15], :month)
{:error, %Tempo.ConversionError{value: ~D[2026-06-15], reason: :not_an_expression}}
```

**Why.** Every function answers every shape of expression or returns an error that names what is wrong, and an argument of the wrong type is one more shape. A `FunctionClauseError` names the clauses that did not match, which says nothing to a caller who passed a `Date` where Tempo wanted its own value. A predicate raises rather than returns the error because `Enum.filter(values, &Tempo.overlaps?(&1, june))` would read an `{:error, _}` tuple as true.

## Decisions about the project

Some decisions concern the project rather than the meaning of a date, and are recorded here briefly:

* The version of the redesign is 2.0. A 2.0 had been developed and never published.

* OTP 27 is the oldest supported.

* The engine under `lib/tempo/core/` is not public API. Its modules are hidden from the documentation, and the types a caller sees are in `Tempo`.

* Four functions of Tempo 1.6 are not rebuilt: `merge`, `from_date_range` and `season`, and the interval module's `through`.

* The test suite that compared every answer with the published 1.6 was retired once every difference was classified. Its corpus remains, feeding a check that every function answers every shape of expression or returns a named error.

* The companion package `tempo_network` may call Tempo's hidden calendar module, as work of the same project.

## Related reading

* [ISO 8601 conformance](iso8601-conformance.md) says what Tempo reads of ISO 8601-1, ISO 8601-2 and RFC 9557, and lists Tempo's own extensions.

* [RFC 5545 RRULE conformance](rfc5545_rrule_conformance.md) goes through a recurrence rule part by part.

* [Set operations](set-operations.md) covers the set algebra the first section's decisions refine.

* [Falsehoods programmers believe about time](falsehoods.md) collects the edges these decisions were made at.
