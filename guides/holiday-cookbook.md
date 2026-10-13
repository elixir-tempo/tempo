# Holiday cookbook

Holidays are the sternest test of a recurrence language: they are fixed dates, nth-weekdays, moon phases, computed feasts, and dates in half a dozen calendars, often with an observed-day shift on top. This cookbook takes each **rule family** a holiday library uses (the shapes `date-holidays` and `tempo_holidays` classify rules into) and gives the equivalent Tempo value.

Every expression below has been **listed as its dates and checked against the holiday's real date** — the dates in the prose are what Tempo answers. The fourth column is the equivalent RFC 5545 **RRULE** where there is one; a dash means the rule is one RRULE cannot say (a computed feast, a date in another calendar, a domain of years), and `Tempo.RRule.to_string/1` returns an error that says why rather than a rule that means something else.

## Setup — required for every example

```elixir
import Tempo.Sigils
```

## Reading a holiday value

A recurring holiday is an unbounded yearly recurrence wrapping a per-year **selection**:

```text
R/../P1Y/FL 11M 4K 4I N
│    │  │   │   │  │  └ close the selection
│    │  │   │   │  └ 4I  = position 4 (the 4th …)
│    │  │   │   └ 4K   = weekday 4 (Thursday; 1=Mon … 7=Sun)
│    │  │   └ 11M  = month 11 (November)
│    │  └ FL…N = the per-year selection frame
│    └ P1Y = one-year cadence
└ R/.. = repeat, no fixed start (convert within a window to get dates)
```

Other markers: `nD` a day of the month, `nO` a day of the year, `nW` a week; `(name)e` a **computed event** (`Tempo.Event`); `…/±PnD` an ISO 8601-2 §12.10 **window** (each date selected opens a span, back from it for a negative length, and what is written after selects within — used for "N days before or after" feasts); a `{…}` **domain** in the start's place (`R/{…}/P1Y/…`) says which years the recurrence falls in, with `^` leaving one out; and a `[u-ca=…]` suffix puts the whole expression in another **calendar**. List any of them with `Tempo.to_interval/2`:

```elixir
iex> Tempo.to_interval(~o"R/../P1Y/FL11M4K4IN", within: ~o"2026")
{:ok, ~o"{2026Y11M26D/2026Y11M26D}"}

iex> Tempo.RRule.to_string(~o"R/../P1Y/FL11M4K4IN")
{:ok, "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH"}
```

## Fixed dates

The plain case: a month and a day. The RRULE is a `BYMONTH` + `BYMONTHDAY` pair.

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Fixed date | New Year's Day — January 1 | `~o"R/../P1Y/FL1M1DN"` | `FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=1` |
| Fixed date | Valentine's Day — February 14 | `~o"R/../P1Y/FL2M14DN"` | `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=14` |
| Fixed date | Saint Patrick's Day — March 17 | `~o"R/../P1Y/FL3M17DN"` | `FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=17` |
| Fixed date | International Workers' Day — May 1 | `~o"R/../P1Y/FL5M1DN"` | `FREQ=YEARLY;BYMONTH=5;BYMONTHDAY=1` |
| Fixed date | US Independence Day — July 4 | `~o"R/../P1Y/FL7M4DN"` | `FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=4` |
| Fixed date | Halloween — October 31 | `~o"R/../P1Y/FL10M31DN"` | `FREQ=YEARLY;BYMONTH=10;BYMONTHDAY=31` |
| Fixed date | Armistice / Veterans Day — November 11 | `~o"R/../P1Y/FL11M11DN"` | `FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=11` |
| Fixed date | Christmas Day — December 25 | `~o"R/../P1Y/FL12M25DN"` | `FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25` |
| Fixed date + span | Christmas break — December 25 for 4 days | `~o"R/../P1Y/FLL12M25DN/P4DN"` | `FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25` (the four days are the event's `DURATION`, beside the rule) |

## The nth (or last) weekday of a month

A weekday plus a position: `nK` picks the weekday, `nI` the occurrence within the month (`-1I` = the last). The RRULE is `BYMONTH` + an ordinal `BYDAY` (`3MO`, `-1MO`).

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Nth weekday | Martin Luther King Jr. Day — 3rd Monday in January | `~o"R/../P1Y/FL1M1K3IN"` | `FREQ=YEARLY;BYMONTH=1;BYDAY=3MO` |
| Nth weekday | Presidents' Day — 3rd Monday in February | `~o"R/../P1Y/FL2M1K3IN"` | `FREQ=YEARLY;BYMONTH=2;BYDAY=3MO` |
| Nth weekday | Mother's Day (US) — 2nd Sunday in May | `~o"R/../P1Y/FL5M7K2IN"` | `FREQ=YEARLY;BYMONTH=5;BYDAY=2SU` |
| Last weekday | Memorial Day — last Monday in May | `~o"R/../P1Y/FL5M1K-1IN"` | `FREQ=YEARLY;BYMONTH=5;BYDAY=-1MO` |
| Nth weekday | Father's Day (US) — 3rd Sunday in June | `~o"R/../P1Y/FL6M7K3IN"` | `FREQ=YEARLY;BYMONTH=6;BYDAY=3SU` |
| Nth weekday | US Labor Day — 1st Monday in September | `~o"R/../P1Y/FL9M1K1IN"` | `FREQ=YEARLY;BYMONTH=9;BYDAY=1MO` |
| Nth weekday | Canadian Thanksgiving / Columbus Day — 2nd Monday in October | `~o"R/../P1Y/FL10M1K2IN"` | `FREQ=YEARLY;BYMONTH=10;BYDAY=2MO` |
| Nth weekday | US Thanksgiving — 4th Thursday in November | `~o"R/../P1Y/FL11M4K4IN"` | `FREQ=YEARLY;BYMONTH=11;BYDAY=4TH` |
| Last weekday of month | Last workday of every month (payroll) — the last Mon–Fri | `~o"R/../P1M/FL{1..5}K-1IN"` | `FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1` |

## A weekday relative to another day

"The Monday before June 1", "the Friday after the fourth Thursday", "the first Tuesday after the first Monday". A **day range** narrows the month to the seven days a "before"/"after" anchor spans, then a weekday and position pick within it — and that gives a faithful `BYMONTHDAY` (range) + `BYDAY` RRULE. When the anchor is itself a *computed* selection (an nth-weekday, a date offset, an event), a §12.10 window off it (`FLLL…N/PnDN…`) does the same job but has no RRULE.

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Weekday after a date | US Labor Day, as "1st Monday on/after September 1" | `~o"R/../P1Y/FL9M{1..7}D1K1IN"` | `FREQ=YEARLY;BYMONTH=9;BYMONTHDAY=1,2,3,4,5,6,7;BYDAY=1MO` |
| Weekday before a date | Memorial Day, as "Monday before June 1" | `~o"R/../P1Y/FL5M{25..31}D1K1IN"` | `FREQ=YEARLY;BYMONTH=5;BYMONTHDAY=25,26,27,28,29,30,31;BYDAY=1MO` |
| Weekday in a day range | US Election Day — the 1st Tuesday after the 1st Monday of November (a Tuesday in the 2nd–8th) | `~o"R/../P1Y/FL11M{2..8}D2K1IN"` | `FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=2,3,4,5,6,7,8;BYDAY=1TU` |
| Weekday after a weekday | Black Friday — the Friday after the 4th Thursday of November (a Friday in the 23rd–29th) | `~o"R/../P1Y/FL11M{23..29}D5K1IN"` | `FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=23,24,25,26,27,28,29;BYDAY=1FR` |
| Weekday in a day range | First Friday of the month (devotions) | `~o"R/../P1M/FL{1..7}D5K1IN"` | `FREQ=MONTHLY;BYMONTHDAY=1,2,3,4,5,6,7;BYDAY=1FR` |
| Weekday on/after a date | The Friday on or after the 11th | `~o"R/../P1Y/FL11M{11..17}D5K1IN"` | `FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=11,12,13,14,15,16,17;BYDAY=1FR` |
| Nested off a computed anchor | "The Monday after the 3rd Sunday after September 1" — a window off a windowed selection | `~o"R/../P1Y/FLLL9M{1..21}D7K3IN/P2DN1K1IN"` | — |

## The Easter cycle (computed)

Easter is `(easter)e` (the Gregorian paschal computus) or `(orthodox-easter)e` (the same computus in the Julian calendar). Every moveable feast around it is a **§12.10 window** off Easter, resolved to its own weekday — Good Friday is the last Friday in the seven days before Easter, Ascension the last Thursday in the forty-two days after. No RRULE can compute Easter, so the whole cycle is a dash. *(For the Orthodox cycle, swap `(easter)e` for `(orthodox-easter)e`.)*

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Easter − N (window) | Ash Wednesday — 46 days before Easter (a Wednesday) | `~o"R/../P1Y/FLLL(easter)eN/-P49DN3K1IN"` | — |
| Easter − N (window) | Carnival / Mardi Gras — the Tuesday before Ash Wednesday | `~o"R/../P1Y/FLLL(easter)eN/-P49DN2K1IN"` | — |
| Easter − N (window) | Palm Sunday — the Sunday before Easter | `~o"R/../P1Y/FLLL(easter)eN/-P7DN7K1IN"` | — |
| Easter − N (window) | Good Friday — the Friday before Easter | `~o"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN"` | — |
| Computed event | Easter Sunday — the paschal computus | `~o"R/../P1Y/FL(easter)eN"` | — |
| Computed event | Orthodox Easter — the computus in the Julian calendar | `~o"R/../P1Y/FL(orthodox-easter)eN"` | — |
| Easter + N (window) | Easter Monday — the Monday after Easter | `~o"R/../P1Y/FLLL(easter)eN/P2DN1K1IN"` | — |
| Easter + N (window) | Ascension — 39 days after Easter (a Thursday) | `~o"R/../P1Y/FLLL(easter)eN/P42DN4K-1IN"` | — |
| Easter + N (window) | Pentecost / Whitsun — 49 days after Easter | `~o"R/../P1Y/FLLL(easter)eN/P50DN7K-1IN"` | — |
| Easter + N (window) | Whit Monday — the day after Pentecost | `~o"R/../P1Y/FLLL(easter)eN/P51DN1K-1IN"` | — |
| Easter + N (window) | Corpus Christi — 60 days after Easter (a Thursday) | `~o"R/../P1Y/FLLL(easter)eN/P63DN4K-1IN"` | — |

## Astronomical events and solar terms (computed)

The equinoxes and solstices come from `Astro`; the 24 East Asian solar terms and the new moon from `Calendrical` and `Astro`. Each is a computed event, so again no RRULE. A solar term is reckoned at the Chinese meridian in a Gregorian rule; `Tempo.Event.date/3` takes a Vietnamese, Korean or Japanese lunisolar calendar to reckon it at that calendar's.

```elixir
iex> Tempo.to_interval(~o"R/../P1Y/FL(qingming)eN", within: ~o"2026")
{:ok, ~o"{2026Y4M5D/2026Y4M5D}"}
```

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Astronomical | March equinox — Nowruz's astronomical anchor, Ostara | `~o"R/../P1Y/FL(march-equinox)eN"` | — |
| Astronomical | June solstice — Midsummer | `~o"R/../P1Y/FL(june-solstice)eN"` | — |
| Astronomical | September equinox — Mabon, Chuseok's anchor | `~o"R/../P1Y/FL(september-equinox)eN"` | — |
| Astronomical | December solstice — Yule, Dōngzhì | `~o"R/../P1Y/FL(december-solstice)eN"` | — |
| Solar term | Qīngmíng — Tomb-Sweeping Day (15° solar longitude) | `~o"R/../P1Y/FL(qingming)eN"` | — |
| Solar term | Lìchūn — start of spring (315°) | `~o"R/../P1Y/FL(lichun)eN"` | — |
| Lunar | First new moon of the year | `~o"R/../P1Y/FL(new-moon)eN"` | — |

## Other calendars — Islamic, Hebrew, and the lunisolar new years

A holiday defined in another calendar is the same selection, made **in that calendar**: the `[u-ca=…]` suffix is written once, after the whole recurrence (`R/../P1Y/FL3M25DN[u-ca=hebrew]`), so the `P1Y` cadence is one of *that calendar's* years and the month and day are its own. Its occurrences recur on the calendar's own year and move against the Gregorian year exactly as the holiday does. An RRULE is Gregorian, so every row is a dash; the **In 2026** column is the Gregorian date of the occurrence within that year.

```elixir
iex> {:ok, rosh_hashanah} = Tempo.to_interval(~o"R/../P1Y/FL1M1DN[u-ca=hebrew]", within: ~o"2026")
iex> Tempo.IntervalSet.map(rosh_hashanah, &Tempo.to_calendar!(&1, Calendrical.Gregorian))
[~o"2026Y9M12D/2026Y9M12D[u-ca=gregorian]"]
```

> *"The **first day of the Hebrew year**, within the Gregorian year 2026: the 12th of September."*

| Rule type | Holiday (rule in English) | Tempo | In 2026 | RRULE |
|---|---|---|---|---|
| Islamic (Umm al-Qura) | Islamic New Year — 1 Muḥarram | `~o"R/../P1Y/FL1M1DN[u-ca=islamic-umalqura]"` | 2026-06-16 | — |
| Islamic | Mawlid — 12 Rabīʿ al-awwal | `~o"R/../P1Y/FL3M12DN[u-ca=islamic-umalqura]"` | 2026-08-25 | — |
| Islamic | Eid al-Fitr — 1 Shawwāl | `~o"R/../P1Y/FL10M1DN[u-ca=islamic-umalqura]"` | 2026-03-20 | — |
| Islamic | Eid al-Adha — 10 Dhū al-Ḥijja | `~o"R/../P1Y/FL12M10DN[u-ca=islamic-umalqura]"` | 2026-05-27 | — |
| Hebrew | Rosh Hashanah — 1 Tishrei | `~o"R/../P1Y/FL1M1DN[u-ca=hebrew]"` | 2026-09-12 | — |
| Hebrew | Yom Kippur — 10 Tishrei | `~o"R/../P1Y/FL1M10DN[u-ca=hebrew]"` | 2026-09-21 | — |
| Hebrew | Hanukkah — 25 Kislev | `~o"R/../P1Y/FL3M25DN[u-ca=hebrew]"` | 2026-12-05 | — |
| Hebrew (leap-aware) | Passover — 15 Nisan | `~o"R/../P1Y/FL7m15DN[u-ca=hebrew]"` | 2026-04-02 | — |
| Chinese lunisolar | Chinese New Year — 1st day of the 1st month | `~o"R/../P1Y/FL1M1DN[u-ca=chinese]"` | 2026-02-17 | — |
| Persian (Solar Hijri) | Nowruz — 1 Farvardin | `~o"R/../P1Y/FL1M1DN[u-ca=persian]"` | 2026-03-21 | — |
| Coptic | Coptic / Orthodox Christmas — 29 Koiak | `~o"R/../P1Y/FL4M29DN[u-ca=coptic]"` | 2026-01-07 | — |
| Julian | Orthodox Christmas (Julian reckoning) — 25 December Julian (Gregorian 7 January) | `~o"R/../P1Y/FL12M25DN[u-ca=julian]"` | 2026-01-07 | — |
| Julian | Old New Year — 1 January Julian (Gregorian 14 January) | `~o"R/../P1Y/FL1M1DN[u-ca=julian]"` | 2026-01-14 | — |

> **Hebrew month numbers shift in leap years.** A Hebrew leap year inserts Adar I before Adar II, so Nisan is month 7 of an ordinary year like 5786 but month **8** of a leap year like 5787. Write a month after Adar with the traditional `m` marker — Passover's `7m` above is 15 Nisan in any year.

> **A holiday is a rule, not a start and a cadence.** A recurrence with no rule is as long as it steps: `~o"R/5787Y1M1D/P1Y[u-ca=hebrew]"` is the whole year from 1 Tishrei, and then the next, where the rule `FL1M1DN` is the one day of each. Left out of the workdays (`Tempo.workdays(:US, except: holiday)`), the first leaves no working day after it starts and the second leaves out Rosh Hashanah.

## Observed-date substitution (a transform over a holiday)

Many holidays are *observed* on a nearby workday when they land on a weekend — "if January 1 is a Saturday or Sunday, it is observed the following Monday". This is not a new selection but a **map** over the base recurrence, using the territory-aware workday helpers:

```elixir
iex> {:ok, new_years} = Tempo.to_interval(~o"R/../P1Y/FL1M1DN", within: ~o"2028/2030")
iex> Tempo.IntervalSet.map(new_years, &Tempo.nearest_workday(&1, :US))
[ok: ~o"2027Y12M31D/2027Y12M31D", ok: ~o"2029Y1M1D/2029Y1M1D", ok: ~o"2030Y1M1D/2030Y1M1D"]
```

> *"New Year's Day is the 1st of January, **observed on the nearest workday**: 2028's is a Saturday, and is observed on Friday the 31st of December 2027."*

`Tempo.next_workday/2`, `Tempo.previous_workday/2` and `Tempo.add_workdays/3` are the "next Monday" and "N workdays later" variants, and `Tempo.roll_to_workday/3` the conventions that name a side (`roll: :following`, `:preceding` and the modified ones); all take a territory, or the workdays `Tempo.workdays/2` makes with `:except`, so the weekend and the holidays are the right ones.

An observed day that is always on one side can be the rule itself, with a window: the Friday before a New Year's Day that is a Saturday.

```elixir
iex> Tempo.to_interval(~o"R/../P1Y/FLLL1M1D6KN/-P7DN5K1IN", within: ~o"2027")
{:ok, ~o"{2027Y12M31D/2027Y12M31D}"}
```

## Year gates — the recurrence domain (`{…}` and `^`)

Several rule families do not change *which day* a holiday falls on but *which years* it fires: an "active" window, a "since" / "prior to" bound, a year cancelled outright, an even/odd or leap-year rule. Tempo writes these into the recurrence's **domain** — the `{…}` slot between the repeat and the cadence — as an inclusion set of years and year-ranges, with `^` marking a year to carve back out and a trailing `e` / `o` / `l` keeping only the even, odd or leap years. The holiday stays one expression that bounds itself: it is listed with no `:within` window and no set operation afterwards, and its text reads back.

```elixir
iex> years = fn rule -> rule |> Tempo.to_interval!() |> Tempo.IntervalSet.map(&Tempo.year/1) end
iex> years.(~o"R/{2020Y..2030Y,^2026Y,^2028Y}/P1Y/FL12M25DN")
[2020, 2021, 2022, 2023, 2024, 2025, 2027, 2029, 2030]

iex> years.(~o"R/{2096Y..2104Y}l/P1Y/FL12M25DN")
[2096, 2104]
```

> *"Christmas from 2020 to 2030, **but not** 2026 or 2028. Christmas in the **leap years** from 2096 to 2104 — and 2100 is not one."*

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Active window / since–until | Christmas, only 2025 through 2027 | `~o"R/{2025Y..2027Y}/P1Y/FL12M25DN"` | — |
| Disable a year | Christmas 2020–2030, cancelled in 2026 | `~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"` | — |
| Disable several years | … cancelled in 2026 and 2028 | `~o"R/{2020Y..2030Y,^2026Y,^2028Y}/P1Y/FL12M25DN"` | — |
| In even years | Christmas in the even years of the decade | `~o"R/{2024Y..2030Y}e/P1Y/FL12M25DN"` | — |
| In odd years | Christmas in the odd years of the decade | `~o"R/{2024Y..2030Y}o/P1Y/FL12M25DN"` | — |
| In leap years | Christmas in the decade's leap years | `~o"R/{2024Y..2030Y}l/P1Y/FL12M25DN"` | — |

> The domain is **inclusion-first**: `{2020Y..2030Y}` is the span of years the holiday runs, each `^2026Y` removes one, and a trailing `e`/`o`/`l`/`c` filters the rest to the even, odd, leap or common years — `l` and `c` follow the calendar's own leap rule, so `{2096Y..2104Y}l` skips 2100 and `c` keeps it. A domain of exclusions alone (`~o"R/^2026Y/P1Y/FL12M25DN"`) or an open one (`~o"R/{2020Y..}e/P1Y/FL12M25DN"`, every even year from 2020) has no end of its own, so it is listed within a window: `Tempo.to_interval(value, within: ~o"2024/2028")`.

Every RRULE here is a dash, and for a reason worth stating: RFC 5545 keeps year restrictions *out* of the recurrence rule. It can bound a run (`UNTIL`, `COUNT`) and thin a cadence (`INTERVAL`), but a *disabled* year is an `EXDATE` alongside the rule, not in it, and even/odd or leap-year selection it cannot express at all. The rule alone — `FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25` for every row above — would recur in the cancelled years and the years of the wrong parity, so `Tempo.RRule.to_string/1` returns an error for a recurrence over a domain (`{:no_rrule, :domain}`) rather than write it, and the column is a dash, as it is for the computed feasts.

## Enable, weekday gates, and bridges (set algebra)

The families that remain need *another* set, not just a restriction on the years: adding an ad-hoc date the pattern never produces, filtering by the weekday an occurrence lands on, or testing a day against the year's other holidays. Because a converted holiday *is* an interval set, each is one call:

```elixir
iex> {:ok, christmases} = Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN")
iex> {:ok, with_boxing_day} = Tempo.union(christmases, ~o"2027-12-26")
iex> Tempo.IntervalSet.count(with_boxing_day)
12

iex> on_weekdays = Tempo.IntervalSet.filter(christmases, &(Tempo.day_of_week(&1) not in [6, 7]))
iex> Tempo.IntervalSet.map(on_weekdays, &Tempo.year/1)
[2020, 2023, 2024, 2025, 2026, 2028, 2029, 2030]

iex> holidays = Tempo.IntervalSet.new!([~o"2026-05-14", ~o"2026-05-25"])
iex> {Tempo.within?(~o"2026-05-14", holidays), Tempo.within?(~o"2026-05-15", holidays)}
{true, false}
```

> *"The Christmases of the decade **and** one Boxing Day. Those **on a weekday**. Is the 14th of May **within** the holidays? It is; the 15th is not."*

`union/2` adds a date the rule never gives; `IntervalSet.filter/2` keeps the occurrences on, or not on, a weekday; and `within?/2` is the test a bridge or an "if it is a holiday then…" rule asks of the year's holidays. And *"every N years"* is a longer cadence, not a filter:

```elixir
iex> Enum.map(Enum.take(~o"R/2024/P4Y/FL7M4DN", 3), &Tempo.year/1)
[2024, 2028, 2032]
```

This is the point of holding holidays as sets of intervals: they combine with each other, and with anyone's free time, through the same algebra.

## Bridge days and moved holidays (conditional members)

A bridge day and a holiday moved off another depend on the *other* holidays of the set, so neither is a property of one recurrence. A `Tempo.RecurrenceSet` holds them as conditional members, resolved after its other members: `Tempo.RecurrenceSet.keep_when/2` keeps an occurrence only when the days `:at` offsets from it fall on the others' occurrences, and `Tempo.RecurrenceSet.move_when/2` moves one that falls on them to the next day its `:to_next` selector gives. `:falls_on` names the others by their metadata, or is a recurrence set of them the condition reads directly — how a set selected by holiday type keeps a holiday's date when what it depends on is left out.

```elixir
iex> respect_for_the_aged = Tempo.put_metadata(~o"R/../P1Y/FL9M1K3IN", %{type: :public})
iex> autumnal_equinox = Tempo.put_metadata(~o"R/../P1Y/FL(september-equinox@+09:00)eN", %{type: :public})
iex> citizens_holiday =
...>   Tempo.RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN",
...>     at: [~o"-P1D", ~o"P1D"],
...>     falls_on: %{type: :public}
...>   )
iex> {:ok, september} = Tempo.RecurrenceSet.new([respect_for_the_aged, autumnal_equinox, citizens_holiday])
iex> {:ok, silver_week} = Tempo.to_interval(september, within: ~o"2026")
iex> Tempo.IntervalSet.map(silver_week, &Tempo.day/1)
[21, 22, 23]

iex> {:ok, no_bridge} = Tempo.to_interval(september, within: ~o"2025")
iex> Tempo.IntervalSet.map(no_bridge, &Tempo.day/1)
[15, 23]
```

> *"Japan's Citizens' Holiday is the 22nd of September, **kept** only when the day before and the day after both **fall on** public holidays. In 2026 Respect for the Aged Day and the equinox meet around it; in 2025 they do not."*

```elixir
iex> maundy_thursday = Tempo.put_metadata(~o"R/../P1Y/FLLL(easter)eN/-P7DN4K-1IN", %{type: :observance})
iex> naefelser_fahrt =
...>   Tempo.RecurrenceSet.move_when(~o"R/../P1Y/FLLL4M2DN/P7DN4K-1IN",
...>     falls_on: %{type: :observance},
...>     to_next: ~o"4K"
...>   )
iex> {:ok, glarus} = Tempo.RecurrenceSet.new([maundy_thursday, naefelser_fahrt])
iex> {:ok, spring} = Tempo.to_interval(glarus, within: ~o"2026")
iex> Tempo.IntervalSet.map(spring, &{Tempo.month(&1), Tempo.day(&1)})
[{4, 2}, {4, 9}]
```

> *"Näfelser Fahrt is the first Thursday from the 2nd of April, **moved to the next** Thursday when it falls on an observance — as it does in 2026, when the 2nd of April is Maundy Thursday."*

A conditional member has no ISO 8601 text, since it reads the other members of its set: `Tempo.to_iso8601/1` returns an error for one, and for a set that holds one.

A condition reads the other members' occurrences as they first fall, a conditional's own among them but never the member's own, so a holiday one conditional moves is not seen by another. Near a window's edge the set looks past it — the day before a bridge on the bound's first day, a holiday moved in from the week before — and keeps what starts inside.

## Coverage of the date-holidays grammar

Every **selection**-shaped rule in the corpus — including several the `tempo_holidays` compiler itself still lists as *not handled* — is a single Tempo value: fixed dates and spans; nth/last weekday-in-month; a weekday **before/after a date, a weekday, or another computed anchor** (Black Friday, Election Day, "the Monday after the 3rd Sunday after September 1"); Easter/Orthodox and the whole moveable cycle; the equinoxes, solstices, solar terms and new moon; and dates in the Islamic, Hebrew, Persian, Chinese, Coptic and Julian calendars.

The **transforming and conditioning** families split two ways. The **year gates** — an active `since` / `prior to` window, even/odd and leap/non-leap rules, a disabled year — fold into the recurrence's `{…}` **domain**, so they stay single, round-trippable values. What genuinely needs the set algebra is the rest: observed-date **substitution** (the `if/then`, `and if`, `substitutes` modes), the weekday **filters** (`on`/`not on`), and `enable`ing an ad-hoc date — operations over a holiday set, shown above — while the bridge / "if-holiday" **cascades** are conditional members of the holiday `Tempo.RecurrenceSet`. The only genuine gaps are calendar-arithmetic edge cases inside the dependencies (a tabular-vs-computed Umm al-Qura day, an Islamic day-overflow like `30 Safar`), which live in `Calendrical`, not in this grammar.

