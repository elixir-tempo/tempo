# Selection

A selection picks values out of a period: the second Monday of a month, the last weekday, Christmas Day, nine o'clock on each of them. It names no year of its own. It is applied to a period by `Tempo.select/3`, and to every period of a recurrence by `Tempo.every/2`'s `:select` option, which is what an iCalendar RRULE, a cron expression and a JSCalendar rule are read into.

ISO 8601-2 writes a selection between `L` and `N`: `L1K2IN` is the second (`2I`) Monday (`1K`). Tempo reads and writes that form, adds a few parts of its own, and builds the same thing from a keyword list with `Tempo.selection/1`. This guide goes through the parts, each written form beside the keyword list that builds it.

## Setup — required for every example

```elixir
import Tempo.Sigils
```

## Building one, and selecting with it

```elixir
iex> {:ok, second_monday} = Tempo.selection(day_of_week: 1, instance: 2)
iex> second_monday
~o"L1K2IN"
iex> Tempo.select(~o"2026-06", second_monday)
{:ok, ~o"{2026Y6M8D}"}
```

> *"The second Monday of June 2026 is the 8th."*

The text form is read as well, where text is what was given:

```elixir
iex> Tempo.select(~o"2026", ~o"L1K2IN")
{:ok, ~o"{2026Y1M12D}"}
```

A selection counts in the period it is given. In a year, the second Monday is the year's second.

## The parts

| Keyword | Written | Selects |
|---|---|---|
| `month: 12` | `12M` | a month of the year |
| `day: 25`, `day: -1` | `25D`, `-1D` | a day of the month, counted from its end where negative |
| `day_of_week: 1` | `1K` | a day of the week, from the day the weeks begin on: Monday 1 to Sunday 7 in the Gregorian calendar, Sunday 1 in the Hebrew |
| `day_of_year: 100` | `100O` | a day of the year |
| `week: 20` | `20W` | a week of the year |
| `hour: 9`, `minute: 30`, `second: 0` | `T9H30M0S` | a time of day |
| `year: [2026, 2028]` | `{2026,2028}Y` | the years an occurrence may fall in |
| `traditional_month: 7` | `7m` | a month as a lunisolar calendar names it; `{5, :leap}`, written `5+m`, its leap month |
| `instance: 2`, `instance: -1` | `2I`, `-1I` | a position among what the other parts select |
| `selection: [...]`, `window: duration` | `L…N/P…` | a selection made first, and what the parts after it select in |
| `all: [[...], [...]]` | `{…,…}` | several selections whose values are taken together |
| `event: "easter"` | `(easter)e` | a day a calendar computes |
| `roll: :following` | `(following)r` | each day selected moved to a working day |
| `skip: :forward` | `(forward)s` | what is taken for a day or a month a year lacks |

Each part takes a whole number, a list of them, or a range:

```elixir
iex> {:ok, christmas} = Tempo.selection(month: 12, day: 25)
iex> Tempo.select(~o"2026/2028", christmas)
{:ok, ~o"{2026Y12M25D,2027Y12M25D,2028Y12M25D}"}
iex> {:ok, last_day} = Tempo.selection(day: -1)
iex> Tempo.select(~o"2026-01/2026-03", last_day)
{:ok, ~o"{2026Y1M31D,2026Y2M28D,2026Y3M31D}"}
iex> {:ok, monday_wednesday_friday} = Tempo.selection(day_of_week: [1, 3, 5])
iex> Tempo.select(~o"2026-06-01/2026-06-07", monday_wednesday_friday)
{:ok, ~o"{2026Y6M1D,2026Y6M3D,2026Y6M5D}"}
iex> {:ok, opening_hours} = Tempo.selection(hour: [9, 17])
iex> Tempo.select(~o"2026-06-15", opening_hours)
{:ok, ~o"{2026Y6M15DT9H,2026Y6M15DT17H}"}
```

> *"Christmas is the 25th of December in each year. The last day of each month is its last, whatever its length. Monday, Wednesday and Friday of the first week of June are the 1st, 3rd and 5th."*

A day of the year, and a week, are given as the year counts them:

```elixir
iex> {:ok, hundredth_day} = Tempo.selection(day_of_year: 100)
iex> Tempo.select(~o"2026", hundredth_day)
{:ok, ~o"{2026Y100O}"}
```

## Positions

`instance` picks among everything the other parts select in the period, counted from the start, or from the end where it is negative. A list picks several:

```elixir
iex> {:ok, last_weekday} = Tempo.selection(day_of_week: 1..5, instance: -1)
iex> Tempo.select(~o"2026-06", last_weekday)
{:ok, ~o"{2026Y6M30D}"}
iex> {:ok, first_and_last_weekday} = Tempo.selection(day_of_week: 1..5, instance: [1, -1])
iex> Tempo.select(~o"2026-06", first_and_last_weekday)
{:ok, ~o"{2026Y6M1D,2026Y6M30D}"}
```

> *"The last weekday of June 2026 is the 30th, and the first is the 1st."*

A position is applied last, among everything selected, as ISO 8601-2 §12.9 has it. With times of day in the selection it counts among the times as well:

```elixir
iex> {:ok, counted_among_times} = Tempo.selection(day_of_week: 1, hour: [9, 10], instance: 2)
iex> Tempo.select(~o"2026-06", counted_among_times)
{:ok, ~o"{2026Y6M1DT10H}"}
```

That is the second of the Mondays' nine and ten o'clocks, ten o'clock on the first Monday. To say "the second Monday, at nine and at ten", the Monday is selected first and the times within it, which is what a nested selection is for.

## A selection made first

A selection given as the `:selection` part is made first, and the parts after it select within each value it picks:

```elixir
iex> {:ok, second_monday_at_nine_and_ten} =
...>   Tempo.selection(selection: [day_of_week: 1, instance: 2], hour: [9, 10])
iex> second_monday_at_nine_and_ten
~o"LL1K2INT{9,10}HN"
iex> Tempo.select(~o"2026-06", second_monday_at_nine_and_ten)
{:ok, ~o"{2026Y6M8DT9H,2026Y6M8DT10H}"}
```

Parts written before the nested selection say where it is made. `L11MLL1K1IN/P9DN2K1IN` is, in November, the first Tuesday after the first Monday: the nested `LL1K1IN/P9DN` opens a window of nine days from the first Monday, and `2K1I` is the first Tuesday in it. That is the day of a United States election:

```elixir
iex> Tempo.select(~o"2026", ~o"L11MLL1K1IN/P9DN2K1IN")
{:ok, ~o"{2026Y11M3D}"}
```

A window of a negative length runs back from the value. Good Friday is the last Friday of the seven days before Easter:

```elixir
iex> {:ok, good_friday} =
...>   Tempo.selection(selection: [event: "easter"], window: ~o"-P7D", day_of_week: 5, instance: -1)
iex> Tempo.select(~o"2026", good_friday)
{:ok, ~o"{2026Y4M3D}"}
```

> *"Easter is the day the church calendar computes. The week before it is the seven days back from it. Good Friday is the **last Friday** of that week."*

## Several selections together

ISO 8601-2 allows one rule of a kind in a selection, and applies a position last, over everything selected. So `L{1,3}K2IN` is the second of the Mondays and Wednesdays taken together, and cannot say "the second Monday and the second Wednesday". Tempo's set of selections can: each selection is made in the period, and their values are taken together, in time order.

```elixir
iex> Tempo.select(~o"2026-06", ~o"L{1,3}K2IN")
{:ok, ~o"{2026Y6M3D}"}
iex> {:ok, first_monday_and_last_friday} =
...>   Tempo.selection(all: [[day_of_week: 1, instance: 1], [day_of_week: 5, instance: -1]])
iex> first_monday_and_last_friday
~o"L{1K1I,5K-1I}N"
iex> Tempo.select(~o"2026-06", first_monday_and_last_friday)
{:ok, ~o"{2026Y6M1D,2026Y6M26D}"}
```

Parts written after the set select within each of its values, and a position written after it counts among them all. RFC 5545's `BYDAY=2MO,2WE` is read into one (see [Design decisions](design-decisions.md), decision 34).

## Days a calendar computes

An event names a day a calendar computes, rather than one it numbers: Easter and Orthodox Easter, the equinoxes and solstices, the new moon, and the twenty-four solar terms of the Chinese calendar. `Tempo.Event.known/0` lists them. An astronomical event is the day it falls on in UTC, or in the zone written after an `@`:

```elixir
iex> Tempo.select(~o"2026", ~o"L(qingming)eN")
{:ok, ~o"{2026Y4M5D}"}
iex> {:ok, equinox_in_tokyo} = Tempo.selection(event: {"march-equinox", "Asia/Tokyo"})
iex> equinox_in_tokyo
~o"L(march-equinox@Asia/Tokyo)eN"
iex> Tempo.select(~o"2026", equinox_in_tokyo)
{:ok, ~o"{2026Y3M20D}"}
```

An event is computed by Calendrical, and by Astro for astronomy; Tempo selects it.

## Moving a day

### To a working day

A roll moves each day selected to a working day, by one of six conventions: `following` and `preceding` move forward or back, `nearest` to the closer (the later on a tie), and the three `modified-` forms do the same but turn back rather than leave the month. Working days are those of the locale the selection is asked in, given as `:locale` or the territory in force, never a fixed Monday to Friday:

```elixir
iex> {:ok, first_working_day} = Tempo.selection(day: 1, roll: :following)
iex> Tempo.select(~o"2026-05", first_working_day, locale: "en-US")
{:ok, ~o"{2026Y5M1D}"}
iex> Tempo.select(~o"2026-05", first_working_day, locale: "ar-SA")
{:ok, ~o"{2026Y5M3D}"}
iex> {:ok, last_working_day} = Tempo.selection(day: -1, roll: :modified_following)
iex> Tempo.select(~o"2026-05/2026-07", last_working_day, locale: "en-US")
{:ok, ~o"{2026Y5M29D,2026Y6M30D,2026Y7M31D}"}
```

> *"The 1st of May 2026 is a Friday: a working day in the United States, and part of the weekend in Saudi Arabia, where the first working day is Sunday the 3rd. The last day of May is a Sunday, and the **modified following** working day, which may not leave the month, is Friday the 29th."*

Cron's `15W`, the weekday nearest the 15th within its month, is read as `15D(modified-nearest)r`.

### Past a day a year lacks

A day or a month that a year does not have (the 29th of February, a leap month) is passed over unless the selection says what to take instead: the next day there is, or the last before it, RFC 7529's `SKIP`:

```elixir
iex> Tempo.select(~o"2026/2028", ~o"L2M29DN")
{:ok, ~o"{2028Y2M29D}"}
iex> {:ok, leap_day_or_after} = Tempo.selection(month: 2, day: 29, skip: :forward)
iex> Tempo.select(~o"2026/2028", leap_day_or_after)
{:ok, ~o"{2026Y3M1D,2027Y3M1D,2028Y2M29D}"}
```

## In a recurrence

A recurrence selects in each of its periods. `Tempo.every/2` takes the parts as `:select`, and the written form puts the selection after `F`:

```elixir
iex> {:ok, second_mondays} =
...>   Tempo.every(~o"P1M", from: ~o"2026-06-01", count: 3, select: [day_of_week: 1, instance: 2])
iex> second_mondays
~o"R3/2026Y6M1D/P1M/FL1K2IN"
iex> Enum.map(second_mondays, &Tempo.Interval.from/1)
[~o"2026Y6M8D", ~o"2026Y7M13D", ~o"2026Y8M10D"]
```

RFC 5545 rules and cron expressions are read into the same selections:

| Rule | Selection |
|---|---|
| `FREQ=MONTHLY;BYDAY=-1FR` | `R/../P1M/FL5K-1IN`, the last Friday |
| `FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1` | `R/../P1M/FL{1,2,3,4,5}K-1IN`, the last weekday |
| `FREQ=YEARLY;BYMONTH=11;BYDAY=4TH` | `R/../P1Y/FL11ML4K4INN`, the fourth Thursday of November |
| `FREQ=DAILY;BYHOUR=9,17;BYMINUTE=30` | `R/../P1D/FLT{9,17}H30MN` |
| `FREQ=MONTHLY;BYDAY=2MO,2WE` | `R/../P1M/FL{1K2I,3K2I}N` |
| cron `30 9 * * 1-5` | `R/../P1M/FL{1,2,3,4,5}KT9H30MN` |

```elixir
iex> Tempo.RRule.parse("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH")
{:ok, ~o"R/../P1Y/FL11ML4K4INN"}
iex> Tempo.Cron.parse("30 9 * * 1-5")
{:ok, ~o"R/../P1M/FL{1,2,3,4,5}KT9H30MN"}
```

The [RFC 5545 RRULE conformance guide](rfc5545_rrule_conformance.md) goes through a rule part by part.

## In a time zone

A time of day selected in a zone is the moment the zone's clock shows it. Where the clock goes back and shows a time twice, the time is its first showing, as a value written to that time is read; where the clock goes forward past a time, there is none (decision 36):

```elixir
iex> {:ok, half_past_one} = Tempo.selection(hour: 1, minute: 30)
iex> Tempo.select(~o"2026-11-01[America/Chicago]", half_past_one)
{:ok, ~o"{2026Y11M1DT1H30M}[America/Chicago]"}
iex> {:ok, half_past_two} = Tempo.selection(hour: 2, minute: 30)
iex> Tempo.select(~o"2026-03-08[America/Chicago]", half_past_two)
{:ok, ~o"{}[America/Chicago]"}
```

An hourly rule across the hour shown twice still gives each hour that passes, each period holding one showing.

## What is refused

A part a selection does not have, and an event no calendar computes, are errors as the selection is built. A period with no year has no days to select in:

```elixir
iex> {:error, %ArgumentError{}} = Tempo.selection(fortnight: 1)
iex> {:error, %Tempo.InvalidDateError{reason: {:unknown_event, "nonsense"}}} = Tempo.selection(event: "nonsense")
iex> {:error, %Tempo.ConversionError{reason: :needs_a_year}} = Tempo.select(Tempo.new!(month: 6), ~o"L1K2IN")
```

## Related reading

* [ISO 8601 grammar](iso8601-grammar.md) gives the written form of every part, ISO 8601-2's and Tempo's own.

* [ISO 8601 conformance](iso8601-conformance.md) lists Tempo's extensions to the selection and their interchange risk.

* [Design decisions](design-decisions.md) gives the reasons behind sets of selections, rolls, skips and times in a zone.

* [Workdays and weekends](workdays-and-weekends.md) covers the working week a roll uses.
