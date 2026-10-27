# Date rules

A date rule is a yearly date written the way people write one: `4th Thursday in November`, `Monday before 06-01`, `easter -2`, `15 Nisan`, `chinese 01-0-01`, `september equinox in Asia/Tokyo`. `Tempo.DateRule.parse/2` reads one into the Tempo recurrence it means, so a holiday, a festival or a recurring company date can be written in words and then listed, compared and combined like any other Tempo value.

The grammar is the one [date-holidays](https://github.com/commenthol/date-holidays) writes the holidays of some two hundred territories in, read as its parser, [date-holidays-parser](https://github.com/commenthol/date-holidays-parser), reads it. A rule from its dataset, or one written for it, reads here to the same dates. ISO 8601-2 and RFC 5545's `RRULE` can say the same things, but they are written for machines to exchange; a date rule is written for people to read.

This guide shows how to write and use rules, a part at a time. The [date rule grammar](./date-rule-grammar.md) is the reference: every part a rule may have, the words each takes, and the order they are read in.

## Setup — required for every example

```elixir
import Tempo.Sigils
```

## Reading a rule

`Tempo.DateRule.parse/2` returns the rule as a yearly recurrence, and `Tempo.to_interval/2` lists the dates it falls on within a window:

```elixir
iex> {:ok, thanksgiving} = Tempo.DateRule.parse("4th Thursday in November")
iex> Tempo.to_iso8601(thanksgiving)
{:ok, "R/../P1Y/FL11M4K4IN"}

iex> Tempo.to_interval(thanksgiving, within: ~o"2026")
{:ok, ~o"{2026Y11M26D/2026Y11M26D}"}
```

> *"Thanksgiving is the **fourth Thursday in November**: in 2026, the 26th."*

The result is an ordinary `t:Tempo.t/0`: the ISO 8601 above is the same expression written for a machine, and it takes part in set operations, Allen relations and workday arithmetic as any other recurrence does. `Tempo.DateRule.parse!/2` returns the expression alone and raises the error.

## Dates

A month and a day, a month alone for its first day, or a date with its year for that year alone.

| Rule | Reads as | ISO 8601 |
|---|---|---|
| `12-25` | the 25th of December | `R/../P1Y/FL12M25DN` |
| `February` | the 1st of February | `R/../P1Y/FL2M1DN` |
| `2026-12-25` | the 25th of December 2026, and no other year | `R/{2026Y}/P1Y/FL12M25DN` |

## Weekdays, and steps from a date

A weekday is counted in a month (`2nd Monday in June`) or stepped to from a date (`Monday before 06-01`), and a step can be taken from any date the grammar names, another step among them. A weekday **after** a date may be the date itself, as the parser counts it: `2nd sunday after 05-01` is the second Sunday of May. **Before** is always strictly before.

| Rule | Reads as | ISO 8601 |
|---|---|---|
| `2nd Monday in June` | the second Monday of June | `R/../P1Y/FL6M1K2IN` |
| `Monday before 06-01` | the last Monday of May | `R/../P1Y/FLL6M1DN/P-7D1K1IN` |
| `Friday after 4th Thursday in November` | the day after Thanksgiving | `R/../P1Y/FLL11M4K4IN/P7D5K-1IN` |
| `Tuesday after 1st Monday in November` | US Election Day | `R/../P1Y/FLL11M1K1IN/P7D2K-1IN` |
| `4 days after 11-27` | the 1st of December | `R/../P1Y/FLL11M27DN/P5D{1..7}K-1IN` |
| `Thursday before easter -46` | Fat Thursday, the Thursday before Ash Wednesday | `R/../P1Y/FLLL(easter)eN/P-47D3K1IN/P-7D4K1IN` |

```elixir
iex> {:ok, memorial_day} = Tempo.DateRule.parse("Monday before 06-01")
iex> Tempo.to_interval(memorial_day, within: ~o"2026")
{:ok, ~o"{2026Y5M25D/2026Y5M25D}"}
```

> *"Memorial Day is the **Monday before the 1st of June**, the last Monday of May: in 2026, the 25th."*

A step is an ISO 8601-2 window off the date it steps from, with the weekday selected in it: `FLL6M1DN/P-7D1K1IN` is the Monday in the seven days before the 1st of June. The grammar has no `last`; the last weekday of a month is the weekday before the first of the next.

## Easter and its feasts

`easter` is the Western Easter and `orthodox` the Orthodox, each with an offset in days for the feasts that move with it.

| Rule | Reads as | ISO 8601 |
|---|---|---|
| `easter` | Easter Sunday | `R/../P1Y/FL(easter)eN` |
| `easter -2` | Good Friday | `R/../P1Y/FLL(easter)eN/P-3D5K1IN` |
| `easter 1` | Easter Monday | `R/../P1Y/FLL(easter)eN/P2D1K-1IN` |
| `easter 39` | Ascension Day | `R/../P1Y/FLL(easter)eN/P40D4K-1IN` |
| `easter 49` | Pentecost | `R/../P1Y/FLL(easter)eN/P50D7K-1IN` |
| `orthodox` | Orthodox Easter Sunday | `R/../P1Y/FL(orthodox-easter)eN` |
| `orthodox -2` | Orthodox Good Friday | `R/../P1Y/FLL(orthodox-easter)eN/P-3D5K1IN` |

```elixir
iex> {:ok, good_friday} = Tempo.DateRule.parse("easter -2")
iex> Tempo.to_interval(good_friday, within: ~o"2026")
{:ok, ~o"{2026Y4M3D/2026Y4M3D}"}
```

> *"Good Friday is **two days before Easter**: in 2026, the 3rd of April."*

An offset from Easter always lands on the same weekday, so the expression says it as a weekday in a window: Good Friday is the Friday in the three days before Easter.

## Equinoxes, solstices and solar terms

An equinox or a solstice is the day it falls on where the rule says, `in` a time zone; a solar term of the Chinese, Korean or Vietnamese calendar is named by its number, 1 to 24, and the day of it.

| Rule | Reads as | ISO 8601 |
|---|---|---|
| `march equinox` | the day of the March equinox | `R/../P1Y/FL(march-equinox)eN` |
| `september equinox in Asia/Tokyo` | Japan's Autumnal Equinox Day | `R/../P1Y/FL(september-equinox@Asia/Tokyo)eN` |
| `december solstice` | the day of the December solstice | `R/../P1Y/FL(december-solstice)eN` |
| `3rd monday before December solstice` | the third Monday before it | `R/../P1Y/FLL(december-solstice)eN/P-21D1K1IN` |
| `chinese 5-01 solarterm` | Qingming, Tomb-Sweeping Day | `R/../P1Y/FL(qingming)eN` |
| `chinese 22-01 solarterm` | Dongzhi, the winter solstice festival | `R/../P1Y/FL(dongzhi)eN` |

```elixir
iex> {:ok, autumnal_equinox_day} = Tempo.DateRule.parse("september equinox in Asia/Tokyo")
iex> Tempo.to_interval(autumnal_equinox_day, within: ~o"2026")
{:ok, ~o"{2026Y9M23D/2026Y9M23D}"}
```

> *"Autumnal Equinox Day is the day of the **September equinox in Tokyo**: in 2026, the 23rd."*

## Dates in other calendars

A date in the Islamic, Hebrew, Persian, Julian, Chinese, Korean or Vietnamese calendar is a recurrence in that calendar, so each year of the rule is a year of that calendar and the date moves against the Gregorian year as the holiday does. An Islamic date is read in the Umm al-Qura calendar. A lunisolar date is written month, leap and day: `chinese 01-0-01` is the first day of the first month, which is not a leap month. Written with its sexagenary cycle and year before it, it falls in that year alone: `chinese 78-32-08-0-15` is the Mid-Autumn Festival of the 32nd year of the 78th cycle, the 27th of September 2015. date-holidays-parser drops the cycle and its year and reads such a date in every year; Tempo reads it in the year it names.

| Rule | Reads as | ISO 8601 | In 2026 |
|---|---|---|---|
| `1 Shawwal` | Eid al-Fitr | `R/../P1Y/FL10M1DN[u-ca=islamic-umalqura]` | 2026-03-20 |
| `10 Dhu al-Hijjah` | Eid al-Adha | `R/../P1Y/FL12M10DN[u-ca=islamic-umalqura]` | 2026-05-27 |
| `15 Nisan` | Passover | `R/../P1Y/FL7m15DN[u-ca=hebrew]` | 2026-04-02 |
| `1 Farvardin` | Nowruz | `R/../P1Y/FL1M1DN[u-ca=persian]` | 2026-03-21 |
| `julian 12-25` | Orthodox Christmas | `R/../P1Y/FL12M25DN[u-ca=julian]` | 2026-01-07 |
| `chinese 01-0-01` | Lunar New Year | `R/../P1Y/FL1m1DN[u-ca=chinese]` | 2026-02-17 |
| `korean 08-0-15` | Chuseok | `R/../P1Y/FL8m15DN[u-ca=dangi]` | 2026-09-25 |
| `vietnamese 01-0-01` | Tết | `R/../P1Y/FL1m1DN[u-ca=vietnamese]` | 2026-02-17 |

```elixir
iex> {:ok, passover} = Tempo.DateRule.parse("15 Nisan")
iex> {:ok, in_2026} = Tempo.to_interval(passover, within: ~o"2026")
iex> Tempo.IntervalSet.map(in_2026, &Tempo.to_calendar!(&1, Calendar.ISO))
[~o"2026Y4M2D/2026Y4M2D"]
```

> *"Passover begins on the **15th of Nisan**: in 2026, the 2nd of April."*

A Hebrew month is read as its traditional month, the same month in every year, though a leap year inserts a month before it: Nisan is the seventh month of an ordinary year and the eighth of a leap year (`7m`). date-holidays' `Adar` is the sixth month in order, Adar I in a leap year, and its `AdarII` is the Adar of Purim. A year written with a date is a year of its calendar: `31 Shahrivar 1401` is in the Persian year 1401 alone.

## Times and spans

A holiday is read as the days it covers. A time of day says when it starts and lasts to the midnight after; a duration says how long it lasts from then, so a holiday that runs past midnight covers the next day too.

| Rule | Reads as | ISO 8601 |
|---|---|---|
| `12-31 14:00` | the 31st of December, from two in the afternoon | `R/../P1Y/FL12M31DN` |
| `12-25 P4D` | the 25th through the 28th of December | `R/../P1Y/FLL12M25DN/P4DN` |
| `12-31 14:00 PT12H` | the 31st of December and the 1st of January | `R/../P1Y/FLL12M31DN/P2DN` |
| `1 Shawwal PT90H` | the four days from Eid al-Fitr | `R/../P1Y/FLL10M1DN/P4DN[u-ca=islamic-umalqura]` |

```elixir
iex> {:ok, christmas_break} = Tempo.DateRule.parse("12-25 P4D")
iex> Tempo.to_interval(christmas_break, within: ~o"2026")
{:ok, ~o"{2026Y12M25D/28D}"}
```

> *"The Christmas break is **four days from the 25th of December**: the 25th through the 28th."*

## The years a rule is kept in

`since` and `prior to` bound the years a rule falls in, and `in even years`, `in odd years`, `in leap years` and `every 6 years since 1980` choose among them. They become the recurrence's domain, the `{…}` written before its cadence, so a rule with an end of its own lists its dates with no window.

| Rule | Reads as | ISO 8601 |
|---|---|---|
| `12-25 since 2020` | from 2020 on | `R/{2020Y/..}/P1Y/FL12M25DN` |
| `12-25 prior to 2030` | until 2029 | `R/{../2029Y}/P1Y/FL12M25DN` |
| `03-02 in even years` | in the even years | `R/..e/P1Y/FL3M2DN` |
| `12-01 every 6 years since 1980` | in 1980, 1986, 1992 and on | `R/{1980Y/..}/P6Y/FL12M1DN` |
| `12 Cheshvan since 1997` | from the Hebrew year that begins in 1997 | `R/{5758Y/..}/P1Y/FL2m12DN[u-ca=hebrew]` |

```elixir
iex> {:ok, christmas} = Tempo.DateRule.parse("12-25 since 2020 prior to 2025")
iex> {:ok, christmases} = Tempo.to_interval(christmas)
iex> Tempo.IntervalSet.map(christmases, &Tempo.year/1)
[2020, 2021, 2022, 2023, 2024]
```

> *"Christmas **since 2020 and prior to 2025**: five Christmases, 2020 through 2024."*

A year in `since` or `prior to` is a Gregorian year, also for a date of another calendar: `12 Cheshvan since 1997` is from the Hebrew year 5758, which begins in 1997.

## Weekday filters

`on` keeps a date only in the years it falls on one of the weekdays named, and `not on` only in the years it does not.

| Rule | Reads as | ISO 8601 |
|---|---|---|
| `02-01 on Monday, Tuesday` | the 1st of February, when it is a Monday or a Tuesday | `R/../P1Y/FL2M1D{1..2}KN` |
| `12-26 not on Friday, Monday` | the 26th of December, unless it is a Friday or a Monday | `R/../P1Y/FL12M26D{2..4,6..7}KN` |

```elixir
iex> {:ok, boxing_day} = Tempo.DateRule.parse("12-26 not on Friday, Monday")
iex> {:ok, boxing_days} = Tempo.to_interval(boxing_day, within: ~o"2026/2032")
iex> Tempo.IntervalSet.map(boxing_days, &Tempo.year/1)
[2026, 2027, 2028, 2029, 2030, 2032]
```

> *"The 26th of December, **unless it is a Friday or a Monday**: it is a Friday in 2031, so 2031 has none."*

## Observed days

A holiday that falls on a weekend is often observed on another day. `if sunday then next monday` moves it there; `and if sunday then next monday` keeps it and adds the observed day; a rule that begins `substitutes` gives the observed day alone. Clauses are read in order, each on the weekdays no earlier clause took, and an observed day is marked `%{substitute: true}` in its metadata.

| Rule | Reads as |
|---|---|
| `01-01 if sunday then next monday` | the 1st of January, on the Monday after when it is a Sunday |
| `01-01 and if sunday then next monday` | the 1st of January, and the Monday after when it is a Sunday |
| `substitutes 01-01 if sunday then next monday` | the Monday after the 1st of January, in the years it is a Sunday |
| `12-25 if saturday then previous friday if sunday then next monday` | Christmas, on the Friday before a Saturday and the Monday after a Sunday |

```elixir
iex> {:ok, new_years_day} = Tempo.DateRule.parse("01-01 and if sunday then next monday")
iex> {:ok, in_2023} = Tempo.to_interval(new_years_day, within: ~o"2023")
iex> Tempo.IntervalSet.map(in_2023, &Tempo.day/1)
[1, 2]

iex> Tempo.IntervalSet.map(in_2023, &Tempo.metadata/1)
[%{}, %{substitute: true}]
```

> *"New Year's Day, **and** the Monday after it when it is a Sunday: in 2023 it is, so the 1st and the 2nd, the 2nd the **substitute**."*

A rule with an observed day reads to a `Tempo.RecurrenceSet` of the date and its observed days.

## Rules that depend on other holidays

Some rules ask about the other holidays of the year. A bridge, `09-22 if 09-21 and 09-23 is public holiday`, keeps its day only when the days beside it are holidays; `if is observance holiday then next Thursday` moves a date off one. Each reads to a conditional member, decided when it is in a `Tempo.RecurrenceSet` with the others, against the members whose metadata holds the type the rule names (`:public` where it names none). The `:falls_on` option decides it against other metadata instead.

```elixir
iex> {:ok, respect_for_the_aged} = Tempo.DateRule.parse("3rd Monday in September")
iex> {:ok, autumnal_equinox} = Tempo.DateRule.parse("september equinox in Asia/Tokyo")
iex> {:ok, citizens_holiday} = Tempo.DateRule.parse("09-22 if 09-21 and 09-23 is public holiday")
iex> {:ok, september} =
...>   Tempo.RecurrenceSet.new([
...>     Tempo.put_metadata(respect_for_the_aged, %{type: :public}),
...>     Tempo.put_metadata(autumnal_equinox, %{type: :public}),
...>     citizens_holiday
...>   ])
iex> {:ok, silver_week} = Tempo.to_interval(september, within: ~o"2026")
iex> Tempo.IntervalSet.map(silver_week, &Tempo.day/1)
[21, 22, 23]

iex> {:ok, no_bridge} = Tempo.to_interval(september, within: ~o"2025")
iex> Tempo.IntervalSet.map(no_bridge, &Tempo.day/1)
[15, 23]
```

> *"Japan's Citizens' Holiday is the 22nd of September, **kept** only when the days before and after it are **public holidays**. In 2026 Respect for the Aged Day and the equinox fall either side of it; in 2025 they do not."*

```elixir
iex> {:ok, maundy_thursday} = Tempo.DateRule.parse("easter -3")
iex> {:ok, naefelser_fahrt} =
...>   Tempo.DateRule.parse("Thursday after 04-02 if is observance holiday then next Thursday")
iex> {:ok, glarus} =
...>   Tempo.RecurrenceSet.new([
...>     Tempo.put_metadata(maundy_thursday, %{type: :observance}),
...>     naefelser_fahrt
...>   ])
iex> {:ok, spring} = Tempo.to_interval(glarus, within: ~o"2026")
iex> Tempo.IntervalSet.map(spring, &{Tempo.month(&1), Tempo.day(&1)})
[{4, 2}, {4, 9}]
```

> *"Näfelser Fahrt is the first Thursday from the 2nd of April, **moved to the next** Thursday when it falls on an observance: in 2026 the 2nd of April is Maundy Thursday, so it moves to the 9th."*

A conditional member reads the other members of its set, so it has no ISO 8601 text of its own.

## Reading a holiday dataset

date-holidays keeps beside each rule the holiday around it: the years it was held, a date it was moved from and to, and the `substitutes` entries that stand in for it on a weekend. `Tempo.DateRule.parse/2` takes each as an option, so a rule of the dataset reads to the dates its parser gives.

| Option | Reads |
|---|---|
| `observed: :moved` | each observed-day clause moving the date, an `and` adding nothing |
| `observed: :none` | the date alone, with no observed day |
| `active: [{from, to}]` | the years whose date is in one of the windows, `to` not included |
| `disable: dates`, `enable: dates` | a date moved from one day to another in its year |
| `replaced_by: [entry]` | a `substitutes` entry taking its weekdays from the date it stands in for |

```elixir
iex> {:ok, new_years_day} = Tempo.DateRule.parse("01-01 and if sunday then next monday", observed: :moved)
iex> Tempo.to_interval(new_years_day, within: ~o"2023")
{:ok, ~o"{2023Y1M2D/2023Y1M2D}"}
```

> *"New Year's Day, **moved** to the Monday when it is a Sunday: in 2023, the 2nd of January in its place."*

```elixir
iex> {:ok, early_may} =
...>   Tempo.DateRule.parse("1st monday in May", disable: [~D[2020-05-04]], enable: [~D[2020-05-08]])
iex> {:ok, three_years} = Tempo.to_interval(early_may, within: ~o"2019/2021")
iex> Tempo.IntervalSet.map(three_years, &{Tempo.month(&1), Tempo.day(&1)})
[{5, 6}, {5, 8}, {5, 3}]
```

> *"The early May bank holiday is the **first Monday in May**, but in 2020 it was **moved** from the 4th to the 8th, the 75th anniversary of VE Day."*

```elixir
iex> substitute = "substitutes 12-25 if saturday, sunday then next monday"
iex> {:ok, christmas} = Tempo.DateRule.parse("12-25", replaced_by: [substitute])
iex> {:ok, holidays} = Tempo.RecurrenceSet.new([christmas, Tempo.DateRule.parse!(substitute)])
iex> {:ok, three_years} = Tempo.to_interval(holidays, within: ~o"2021/2023")
iex> Tempo.IntervalSet.map(three_years, &{Tempo.year(&1), Tempo.day(&1)})
[{2021, 27}, {2022, 26}, {2023, 25}]
```

> *"Christmas Day, with a **substitute** day on the Monday when it falls on a weekend: the substitute **stands in for** it in 2021 and 2022, and in 2023 it is on the 25th."*

An entry in `replaced_by` stands in for the date only where it is a `substitutes` rule of the same date, gated by its years alone, and the date has no observed day of its own; any other is passed over. So the `substitutes` entries of a dataset can be given to each of its rules, and each takes those that are its own.

## What is not read

A rule that cannot be read returns a `Tempo.ParseError` naming where reading stopped, or which part is not read:

```elixir
iex> {:error, error} = Tempo.DateRule.parse("12-25 tomorrow")
iex> Exception.message(error)
"Cannot read \"12-25 tomorrow\" as a date rule at \"tomorrow\": not a part of a date rule"
```

These parts of the grammar return an error that names them:

* **The Bengali calendar** — `bengali-revised 1-1`, which needs a Bengali calendar in Calendrical.

* **A solar term of the Korean or Vietnamese calendar** — `korean 5-01 solarterm`; a Chinese solar term is read at the Chinese meridian.

* **`if equal`** — a date replaced when it falls on another rule's date.

* **An `if is holiday` move by more than one, or back** — `if is holiday then 2nd next Tuesday`.

* **A clause that changes the time into another day** — `12-31 14:00 PT12H if Sunday then 00:00`, where the time moves the end of a holiday that runs past midnight.

## Related reading

* [The date rule grammar](./date-rule-grammar.md) — the reference for every part of a rule and what it reads to.

* [Holiday cookbook](./holiday-cookbook.md) — each family of holiday rule written as a Tempo expression by hand, with its RRULE where there is one.

* [Holidays](./holidays.md) — planning with a holiday calendar: workdays, observed days and several territories.

* [Building expressions](./building-expressions.md) — rules and values built a step at a time.
