# ISO 8601 Conformance Guide

Tempo reads and writes [ISO 8601-1:2019](https://www.iso.org/standard/70907.html), [ISO 8601-2:2019](https://www.iso.org/standard/70908.html) and the suffix of [RFC 9557](https://www.rfc-editor.org/rfc/rfc9557) (IXDTF). This guide says what is read, how each form is held and written back, where Tempo reads a text another way than the standard does, what it adds, and what it does not read.

The grammar itself — every production, with the clause it comes from — is in [The grammar Tempo reads](iso8601-grammar.md). When this page and the standard disagree, the standard wins: please file an issue.

## Setup — required for every example

```elixir
import Tempo.Sigils
```

## 1. Two principles

**Every value is a span.** `2026-01` is not an instant: it is January 2026, from its first instant up to February's. A value written to any unit is the span of that unit, so every text reads to something that can be walked, related and combined.

**What is written is what is held.** A week date stays a week date, an ordinal date an ordinal date, a group a group, a year with unspecified digits just that. Nothing is resolved to another form when it is read, so every expression writes back the text it was read from, in the explicit form.

```elixir
iex> ~o"2026-W25-3"
~o"2026Y25W3K"

iex> ~o"2026-166"
~o"2026Y166O"

iex> Tempo.relation(~o"2026-W25-3", ~o"2026-06-17")
:equals
```

> *"The Wednesday of week 25 is **written** as it was read, and **is** the 17th of June."*

## 2. ISO 8601-1 — the core representations

### Three spellings of one value

ISO 8601 writes the same value in more than one way, and Tempo reads them all and writes one.

* **Extended format** — components in fixed places, separated by `-` and `:`: `2022-06-15T14:30:00`.

* **Basic format** — the same with no separators: `20220615T143000`.

* **Explicit form** (ISO 8601-2 §7) — each component followed by a designator: `Y` year, `M` month, `D` day, `O` day of the year, `W` week, `K` day of the week, and after the `T`, `H` hour, `M` minute, `S` second: `2022Y6M15DT14H30M0S`.

```elixir
iex> ~o"2022-06-15T14:30:00" == ~o"20220615T143000"
true

iex> ~o"20220615T143000"
~o"2022Y6M15DT14H30M0S"
```

`Tempo.to_iso8601/1`, `inspect/1` and the `~o` sigil write the explicit form. It says which component is which without relying on position, and it is the one form in which durations, groups, selections and repeat rules all compose. It is also why `M` is both month and minute: before the `T` it is a month, after it a minute, as in a duration (`P6M` is six months, `PT6M` six minutes).

Write the extended format for input: it is what people know and what other systems write.

### What is read

| Feature | Examples |
|---|---|
| Year | `2022`, `-0001`, `+002022` |
| Year and month | `2022-06` |
| Calendar date | `2022-06-15`, `20220615` |
| Ordinal date | `2022-166`, `2022166` |
| Week date | `2022-W24`, `2022-W24-3`, `2022W243` |
| Time of day | `T10`, `T10:30`, `T10:30:00`, `T103000`, and with no `T` where it is unambiguous |
| A fraction of a second, a minute or an hour | `T10:30:00.5`, `T10:30:00,5`, `T10:30,5`, `T10,5` |
| Time shift | `Z`, `+05`, `+05:30`, `+0530`, with a hyphen or a minus sign |
| Date and time | `2022-06-15T10:30:00Z` |
| Duration | `P1Y`, `PT30M`, `P3Y6M4DT12H30M5S`, `-P100D`, `P1.5W` |
| Duration, alternative format (§5.5.2.4) | `P0002-01-10T22:33:55`, `P0002-178T22:33:55` |
| Interval | `2022-01/2022-06`, `2022-01-01/P1Y`, `P1Y/2022-12-31` |
| Interval with an abbreviated end (§5.5.1) | `2018-01-15/02-20`, `2026-06-15/20`, `2025-08-28T09:00/T10:15` |
| Recurring interval | `R/2022-01/P1M`, `R5/2022-01/P1M` |

### Where a reading may surprise

* **Digits alone are read by how many there are**, as ISO 8601-1 §5.2 has it: four are a year, eight a calendar date, seven an ordinal date, and six a time of day (`202206` is 20:22:06), the basic format of a year and month being one the standard does not allow. Two digits are a century and three a decade.

* **An interval's end is read through, when it is a date.** `2022-01/2022-06` is January through June, and `2026-06-15/2026-06-20` six days. An end that is a time of day is the reading the span runs to: `T09/T17` is eight hours. So `2004-06-11/2004-06` is read, as the 11th through the end of June.

* **An abbreviated end takes from the start the components it leaves out**, down to the one it begins with: `2018-01-15/02-20` ends on the 20th of February 2018. An end cut down to one bare number is the day of a calendar date (`2026-06-15/20`); after a time, a week date or an ordinal date, write the end with its designator or its `T`.

* **A time of day under a year, a month or a week is that time on each of its days.** ISO 8601 wants the date of a date and time complete; Tempo reads `2026-06T17` as five o'clock on each day of June, as it reads any gap between two units written.

```elixir
iex> ~o"202206"
~o"T20H22M6S"

iex> Tempo.duration(~o"2026-06-15/2026-06-20")
~o"P6D"

iex> ~o"2018-01-15/02-20" == ~o"2018-01-15/2018-02-20"
true

iex> Enum.count(~o"2026-06T17")
30
```

* **A fraction of a second is kept, with its precision.** `T10:30:00.120` is a millisecond and `T10:30:00.12` a hundredth of a second, two spans of different lengths. Six digits are kept, as Elixir's own types keep them, and more are cut.

* **A second numbered 60 is no value**, on any date, as it is none in Elixir's types. A leap second is a fact about a span: see `Tempo.LeapSeconds`.

* **Truncated forms** (`--06-15`, a two-digit year) were removed from the standard in 2019 and are not read.

## 3. ISO 8601-2 — the extensions

| Feature | Examples | Held and written as |
|---|---|---|
| Unspecified digits (§4.6) | `156X`, `1XXX`, `2022-XX`, `1985-XX-XX`, `-1XXX-XX` | `156XY`, `1985YXXMXXD` |
| Qualification (§4.5, §8) | `2022?`, `2022~`, `2022%`, `2004-06~-11`, `2004-?06-11`, `?2022-06-15` | per component: `2004~Y6~M11D` |
| Qualified ends | `1984?/2004~`, `2019-12/2020%` | each end's own |
| Open ends (§10.2) | `1985/..`, `../1985`, `1985/`, `/1985`, `../..` | `1985Y/..` |
| Set, all of (§6) | `{1960,1961,1962}`, `{1960..1970}` | `{1960Y..1970Y}` |
| Set, one of | `[1984,1986,1988]`, `[1667..1672]` | `[1667Y..1672Y]` |
| Set of durations | `{P1D,P2D}`, `{P1M2S..P1M5S}` | the durations it names |
| A set or a range in a unit | `2026Y{1,3}M`, `2026Y6M{1..-1}D`, `{2026,2027}Y1M` | as written |
| Groups (§5) | `5G10DU`, `2018Y4G60DU6D`, `2026Y2G13WU`, `T16H1GT15MU` | as written |
| Decade and century (§4.3.5, §4.3.6) | `196J`, `196`, `16C`, `16`, `-19C` | `196J`, `16C` |
| Day of the year (§4.3.4) | `350O`, `1985Y102O` | as written |
| Quarter, quadrimester, half (§4.8) | `2022-33` to `2022-36`, `2022-37` to `2022-39`, `2022-40`, `2022-41` | `2022Y33M`; `2022Y1G4MU`; `2022Y1G6MU` |
| Season (§4.8) | `2022-21` to `2022-32` | `2022Y21M`; read and written, with no dates (below) |
| Exponent and significant digits (§4.4.2, §4.4.3) | `2018E3`, `1950S2`, `Y3388E2S3` | `1950S2Y` |
| Long years (§4.7) | `Y17E8`, `Y-170000002` | `17E8Y` |
| Margin of error | `2018±2Y` | as written |
| Selection (§12) | `L1MN`, `2018Y3ML1K1IN`, `L5KT{9,17}H2IN` | as written |
| Selection with a window (§12.10) | `LL(easter)eN/-P7DN`, `L11MLL1K1IN/P9DN2K1IN` | as written |
| Repeat rule (§13) | `R/2026-01-01/P1M/FL1K2IN` | as written |
| Explicit time shift (§7.4) | `Z`, `Z8H`, `Z-5H30M` | as written |

### Qualification

A `?` (uncertain), `~` (approximate) or `%` (both) is of the components its place says (§8.2): at the very end, of every component; to the right of a component, of that one and every coarser one; to the left, of that one alone. Tempo holds a mark per component, so that texts of one meaning are one value, and writes the marks back in the explicit form, with one mark after the value where every component has it.

```elixir
iex> ~o"2004-06~-11"
~o"2004~Y6~M11D"

iex> ~o"2004-?06-11"
~o"2004Y6?M11D"

iex> ~o"2015-02-28?" == ~o"2015-02?-?28"
true

iex> Tempo.qualification(~o"2004-06~-11", :month)
:approximate
```

A qualification is information about a value and changes nothing of its span. See [Uncertain dates](uncertain-dates.md) for the relations that answer in three values.

### Unspecified digits, sets and ranges

A value with an unspecified digit, or with a set or a range in a unit, names several values, and is walked, listed and selected from as each of them:

```elixir
iex> Enum.count(~o"156X")
10

iex> {:ok, fifteenths} = Tempo.to_interval(~o"1985-XX-15")
iex> Tempo.IntervalSet.count(fifteenths)
12

iex> Enum.to_list(~o"2026Y{1,3}M")
[~o"2026Y1M", ~o"2026Y3M"]
```

A set of whole numbers with no designator is a set of years where each has four digits, and otherwise each member is read as it is alone: `{19,20}` is two centuries, `{19,20}Y` two years.

### Seasons and divisions of a year

A quarter, a quadrimester and a half are divisions of the year in every calendar, and have dates. A season is read, held and written as its code, and has its dates by its kind. The seasons of a hemisphere, 25 to 28 in the north and 29 to 32 in the south, are astronomical: each runs from an equinox or a solstice to the next. The seasons 21 to 24 are "independent of location" in the standard, and Tempo reads them as meteorological, three whole months that the hemisphere chooses: one has its months in a territory (`Tempo.in_territory/2`, or the `:territory` and `:locale` options of `Tempo.from_iso8601/2` and `Tempo.to_interval/2`), and where none is named, in the application's `:default_territory` or the current locale's.

```elixir
iex> Tempo.duration(~o"2022-33")
~o"P3M"

iex> ~o"2022-21"
~o"2022Y21M"

iex> Tempo.in_territory(~o"2022-21", :AU)
{:ok, ~o"2022Y9M/11M"}

iex> Tempo.in_territory(~o"2022-21", :GB)
{:ok, ~o"2022Y3M/5M"}

iex> Tempo.duration(~o"2022-25")
~o"P93D"

iex> {:error, %Tempo.ConversionError{}} = Tempo.in_territory(~o"2022-21", :BR)
```

> *"**Spring** of 2022 is **September to November** in **Australia** and **March to May** in **Britain**. The **northern astronomical spring** is **ninety-three days**. In **Brazil**, which the equator runs through, spring is **no one set of months**."*

Two seasons of 21 to 24 at the ends of an interval are read in the order of their numbers, as EDTF holds them: `2026-23/2026-21` is an error. Read with a territory (`Tempo.from_iso8601("2026-23/2026-21", territory: :AU)`) they are held to the order of that hemisphere instead, where autumn comes before spring.

A season is moved by whole years and by nothing finer, and is in the Gregorian calendar: a season of a year of another calendar has no dates.

### Selections and repeat rules

A selection (`L…N`) names the parts of a period to take: a month, a week, a day of the month or of the year, a weekday, a time of day, and a position among what those select (`I`, §12.9). Written in a value it is the dates it picks in the period before it; written after `F` in a recurrence it is the rule applied in each period.

```elixir
iex> Tempo.to_interval(~o"2018Y3ML1K1IN")
{:ok, ~o"{2018Y3M5D/2018Y3M5D}"}

iex> Enum.take(~o"R/2026-01-01/P1M/FL5K-1IN", 2)
[~o"2026Y1M30D/2026Y1M30D", ~o"2026Y2M27D/2026Y2M27D"]
```

> *"The **first Monday** of March 2018. The **last Friday** of each month from January 2026."*

Rules apply higher order first (§12.1). A selection followed by a duration (§12.10) opens a window of that length from each date it picks — back from it, for a negative length — and what is written after selects within the window:

```elixir
iex> Tempo.to_interval(~o"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN", within: ~o"2026")
{:ok, ~o"{2026Y4M3D/2026Y4M3D}"}

iex> Tempo.to_interval(~o"R/../P1Y/FL11MLL1K1IN/P9DN2K1IN", within: ~o"2026")
{:ok, ~o"{2026Y11M3D/2026Y11M3D}"}
```

> *"**Good Friday**: the last Friday in the seven days before Easter. **US election day**: the first Tuesday in the nine days from November's first Monday."*

A window may carry a date out of the period that made it, and a `:within` window keeps each date where it lands: a holiday observed on the Friday before a Saturday New Year's Day is in the year before.

A day `D` is always a day of a month, in each month of the period it is selected in, and `O` a day of the year: `2026YL-1DN` is the last day of each month of 2026 and `2026YL-1ON` the 31st of December.

[One form for ISO 8601 and RRULE](shared-ast-iso8601-and-rrule.md) says how an RFC 5545 rule is the same expression.

## 4. RFC 9557 — the suffix

| Suffix | Example | Held as |
|---|---|---|
| Time zone | `[Europe/Paris]` | the expression's zone |
| Offset as a zone | `[+08:45]` | a zone at a fixed offset |
| Calendar | `[u-ca=hebrew]`, `[u-ca=gregory]` | the expression's calendar |
| Any other tag | `[_foo=bar]` | metadata, written back |

```elixir
iex> ~o"2026-06-15T10:00[Europe/Paris][u-ca=gregory]"
~o"2026Y6M15DT10H0M[Europe/Paris][u-ca=gregorian]"

iex> Tempo.relation(~o"5786-09-30[u-ca=hebrew]", ~o"2026-06-15")
:equals

iex> {:error, %Tempo.ZoneError{reason: :unknown}} = Tempo.from_iso8601("2026-06-15T10:00[Nowhere/City]")
```

**A suffix is written once, after the whole expression**, and is of the whole of it: after the end of an interval it is the zone and calendar of both ends, after a set of every member, after a recurrence of its start, its end and its rule. One written inside — on the start of an interval, on a member of a set — is a `Tempo.ParseError`.

```elixir
iex> conference = ~o"2030-03-01T08:00/2030-03-05T08:00[Europe/Paris]"
iex> Tempo.zoned?(Tempo.Interval.from(conference))
true

iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2030-03-01T08:00[Europe/Paris]/2030-03-05T08:00")
```

A zone is the first suffix or there is none (RFC 9557 §4.1), and its name is checked against the time zone database. A tag marked critical (`[!…]`) that Tempo cannot act on is an error; an elective one is kept as metadata.

**A time shift beside a zone gives the moment** (RFC 9557 §3.4), and the zone the clock it is to be shown on. Both are held and written back. A shift that the zone does not have at that reading is read too, as the moment the shift says.

```elixir
iex> stated = ~o"2022-07-08T00:14:07+01:00[Europe/Paris]"
iex> Tempo.shift_zone(stated, "Etc/UTC")
{:ok, ~o"2022Y7M7DT23H14M7S[Etc/UTC]"}
```

`Z`, `+00:00` and `-00:00` are one time. A time shift is each end's own in an interval, and one written on the start is the end's too where the end has none (ISO 8601-1 §5.5.1).

**A reading a zone's clock skips is no value**: an hour of a spring change, a day a territory left out. One it shows twice is the first, or the one a written shift names. See [Falsehoods](falsehoods.md).

**Calendars.** `u-ca` takes CLDR's calendar names (`hebrew`, `islamic-umalqura`, `persian`, `chinese`, `buddhist`, with `gregory` for the Gregorian) and Calendrical's own for the calendars CLDR does not name (`iso-week`, `julian`, `nrf`, `reform-england`). A calendar no name reads back to, such as a fiscal calendar, has no suffix, and a value in it has no text: `Tempo.to_iso8601/1` returns an error rather than a date another calendar would read.

## 5. Tempo's own extensions

These are in no standard. Each is written by `Tempo.to_iso8601/1` and read back, and a system that reads only the standards will not read them. Where an RFC 5545 form exists, `Tempo.RRule.to_string/1` is the portable one.

Tempo marks the designators it adds with a lowercase letter, so that they are seen at a glance to be its own. `I`, the position, is uppercase because it is ISO 8601-2's.

| Extension | Example | Meaning |
|---|---|---|
| A step in a range | `{1990..1999//2}Y`, `2023Y{1..-1//2}W` | every second year; every second week |
| A week of a month | `2026Y6M2W` | the second week of June, as the calendar numbers a month's weeks |
| A time under a period | `2026-06T17`, `6MT10H` | that time on each day of the period |
| An end after a cadence | `R/2026-06-01/P1D/2026-06-10` | a recurrence's last date, RFC 5545's `UNTIL` |
| A computed event, `e` | `L(easter)eN`, `L(march-equinox@+09:00)eN` | a day a rule computes |
| A traditional month, `m` | `8m15D`, `6+m` | a lunisolar calendar's named month, and its leap month |
| An exclusion, `^` | `{2020Y..2024Y,^2022Y}` | a member left out |
| A recurrence's domain | `R/{2020Y..2024Y}/P1Y/F…` | the periods a rule recurs in |
| A domain filter | `{2020Y..2026Y}e`, `o`, `l`, `c` | even, odd, leap or common years |
| A year in a rule | `FL{2026,2028}Y1M1DN` | the years an occurrence may fall in |
| A week start, `q` | `1q` | the day a week begins on: Monday, the one start kept to |

### Computed events

ISO 8601-2 cannot write a date fixed by an algorithm: Easter, an equinox, one of the twenty-four solar terms. `e` names one, in parentheses:

```elixir
iex> Tempo.to_interval(~o"R/../P1Y/FL(easter)eN", within: ~o"2026/2028")
{:ok, ~o"{2026Y4M5D/2026Y4M5D,2027Y3M28D/2027Y3M28D,2028Y4M16D/2028Y4M16D}"}

iex> Tempo.to_interval(~o"R/../P1Y/FL(march-equinox@+09:00)eN", within: ~o"2002")
{:ok, ~o"{2002Y3M21D/2002Y3M21D}"}

iex> {:error, %Tempo.InvalidDateError{unit: :event}} = Tempo.from_iso8601("R/../P1Y/FL(nonsense)eN")
```

> *"**Easter Sunday** of each year. The **March equinox** as its date falls in Japan: the 21st in 2002, where it was the 20th in UTC."*

`Tempo.Event.known/0` lists the names: `easter` and `orthodox-easter`, the equinoxes and solstices, `new-moon`, and the solar terms (`qingming`, `lichun`, `dongzhi` and the rest). Easter is computed by Calendrical and the astronomical events by Astro. An equinox or a solstice happens at an instant, so its date is of a zone: UTC's, or the one written after `@`.

### Traditional months

ISO 8601 numbers a year's months in order, which is what `M` writes. A lunisolar calendar also names them, and a named month's place moves in a year that has a leap month before it. `m` is the named month and `+m` the leap month after it, in a Chinese, Korean, Vietnamese or Hebrew calendar:

```elixir
iex> Tempo.select(~o"4662[u-ca=chinese]", ~o"8m15D")
{:ok, ~o"{4662Y8m15D}[u-ca=chinese]"}

iex> Enum.map(Enum.take(~o"R/5786Y7m15D/P1Y[u-ca=hebrew]", 2), &Tempo.Interval.from/1)
[~o"5786Y7M15D[u-ca=hebrew]", ~o"5787Y8M15D[u-ca=hebrew]"]
```

> *"The **15th of the eighth named month**: the Mid-Autumn Festival. **Passover** each year, the seventh month of 5786 and the eighth of the leap year 5787."*

### Exclusions, domains and filters

A member of a set written with `^` is left out of it. A set in the place of a recurrence's start is its **domain**, the periods it recurs in, so a rule that lapsed for a year, or holds in even years only, is one expression:

```elixir
iex> Tempo.to_interval(~o"{2024Y,2026Y,2028Y,^2026Y}")
{:ok, ~o"{2024Y/2024Y,2028Y/2028Y}"}

iex> years = fn text, options ->
...>   {:ok, set} = Tempo.to_interval(Tempo.from_iso8601!(text), options)
...>   Tempo.IntervalSet.map(set, &Tempo.year/1)
...> end
iex> years.("R/{2020Y..2024Y,^2022Y}/P1Y/FL12M25DN", [])
[2020, 2021, 2023, 2024]

iex> years.("R/{2020Y..2026Y}e/P1Y/FL1M1DN", [])
[2020, 2022, 2024, 2026]

iex> years.("R/{1848Y..}/P4Y/FL11MLL1K1IN/P9DN2K1IN", within: ~o"2019/2028")
[2020, 2024, 2028]

iex> years.("R/^2022Y/P1Y/FL12M25DN", within: ~o"2020/2023")
[2020, 2021, 2023]

iex> years.("R/2026-01-01/P1Y/FL{2026,2028}Y1M1DN", within: ~o"2026/2030")
[2026, 2028]
```

> *"Christmas from 2020 to 2024, **but not** 2022. New Year's Day in **even** years. Election day **every four years since 1848**. Christmas within a window, less 2022. New Year's Day in 2026 and 2028 **only**."*

A domain that lists its periods needs no window. One that is open (`{1848Y..}`) or holds exclusions alone takes its periods from `:within`. A cadence of several units steps through a domain from its first period. The filters `l` and `c` ask the calendar which years are leap years, so 2100 is a common one.

## 6. What is not read

* **The `A` season designator** of §4.8.2 c); the month-slot form (`2022-21`) is read.

* **The precedence form of a duration** (§11.3.3, `P1YP3MP2D`). Tempo applies years, then months with the day clamped, then weeks and days, then the clock.

* **A set of values within a unit of the extended format** (`2026-[01,03]`) and a time shift written after a set. Write the set whole (`[2026-01,2026-03]`), or in the explicit form (`2026Y{1,3}M`).

* **A range whose ends are not of one shape**, and digits and sets mixed in one unit (`XXX{0,2,4,6,8}Y`).

* **`D` as a day of the year.** `1985Y102D` is refused; write `1985Y102O`.

* **Truncated forms**, and a year and month in the basic format.

Each is a `Tempo.ParseError`, or a `Tempo.InvalidDateError` where the text is well formed and names no date, that says where the reading stopped.

## 7. Test coverage

* **The grammar's generators** produce texts for each production, which must be read and written back to a text that reads to the same value; a mutator makes texts that must be refused.

* **The EDTF corpus** of `unt-libraries/edtf-validate` (BSD-3-Clause), the one public conformance set for ISO 8601-2 we know of, in `test/support/edtf_corpus.ex`.

* **This guide's own examples**, and every other guide's, are run by `mix test --only guides`.

## 8. Reporting a gap

If a text of ISO 8601 should be read and is not, please open an issue with the text, the reading you expect and the clause that gives it, and what `Tempo.from_iso8601/2` returned.
