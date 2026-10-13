# Custom calendars — fiscal years, retail weeks, academic years

Tempo treats a calendar as **data, not a built-in assumption**. Relations, lengths, walks and conversions all go through an expression's calendar — so a *custom human calendar* stands beside the Gregorian, the Hebrew or the Persian. You build the calendar once with [Calendrical](https://hexdocs.pm/calendrical), and every Tempo operation works on the values that are in it.

This is the [time-granularity idea](temporal-formalisms.md) made concrete: a **granularity is a calendar**. A fiscal quarter, a retail week and an academic term are all *granules* of a calendar whose year happens not to begin on the 1st of January.

## Setup — required for every example

```elixir
import Tempo.Sigils
```

## A fiscal year

The US federal fiscal year runs from October to September. Calendrical has the fiscal calendars, and a value is read in one with the `:calendar` option:

```elixir
iex> {:ok, us_fiscal} = Calendrical.FiscalYear.calendar_for(:US)
iex> {:ok, fiscal_2026} = Tempo.from_iso8601("2026", calendar: us_fiscal)
iex> Enum.count(fiscal_2026)
12

iex> Tempo.to_calendar(fiscal_2026, Calendrical.Gregorian)
{:ok, ~o"2025Y10M1D/2026Y9M30D[u-ca=gregorian]"}
```

> *"**Fiscal year 2026** is twelve fiscal months to walk, and on the Gregorian calendar it is the 1st of October 2025 through the 30th of September 2026."*

Every relation places both sides on the one time line, so a fiscal date and a Gregorian date are compared with no conversion by hand:

```elixir
iex> first_day = Tempo.from_iso8601!("2026-01-01", calendar: us_fiscal)
iex> Tempo.relation(first_day, ~o"2025-10-01")
:equals

iex> Tempo.quarter_of_year(Tempo.from_iso8601!("2026-11-15", calendar: us_fiscal))
4
```

> *"The first day of fiscal 2026 **is** the 1st of October 2025, and its eleventh month is in the **fourth quarter**."*

A fiscal quarter as an interval, ready for the set operations, is in the [cookbook](cookbook.md#9-cross-calendar-and-cross-timezone).

## A retail 4-4-5 calendar

Retailers count time in **weeks**, grouped four, four and five into quarters of thirteen. Build one with `Calendrical.new/3`:

```elixir
iex> {_, retail} = Calendrical.new(MyApp.Retail, :week, weeks_in_month: [4, 4, 5])
iex> {:ok, retail_2026} = Tempo.from_iso8601("2026", calendar: retail)
iex> {:ok, weeks} = Tempo.walk(retail_2026, :week)
iex> Enum.count(weeks)
52

iex> Tempo.to_calendar(retail_2026, Calendrical.Gregorian)
{:ok, ~o"2025Y12M29D/2026Y12M27D[u-ca=gregorian]"}
```

> *"The **2026 retail year** is fifty-two weeks, from Monday the 29th of December 2025 through Sunday the 27th of December 2026."*

The `weeks_in_month: [4, 4, 5]` layout is all that tells this calendar from ISO 8601's weeks. Its months are four or five weeks long, and everything else follows.

## An academic year

An academic year is a year that begins in another month:

```elixir
iex> {_, academic} = Calendrical.new(MyApp.Academic, :month, month_of_year: 9)
iex> term_start = Tempo.from_iso8601!("2026-01-01", calendar: academic)
iex> Tempo.relation(term_start, ~o"2025-09-01")
:equals
```

> *"Academic year 2026 begins on the 1st of September 2025."*

## Writing them down

ISO 8601 writes a calendar other than the Gregorian with an RFC 9557 suffix, `[u-ca=…]`, which names CLDR's calendars and the ones Calendrical registers. A fiscal, retail or academic calendar has no name there. So `Tempo.to_iso8601/1` returns an error for a value in one, rather than a text another calendar would read as other days, and `inspect/1` shows the struct, with its calendar module. To store or show such a value, convert it:

```elixir
iex> {:error, %Tempo.Iso8601EncodeError{}} = Tempo.to_iso8601(term_start)
iex> Tempo.to_calendar(term_start, Calendrical.Gregorian)
{:ok, ~o"2025Y9M1D[u-ca=gregorian]"}
```

> *"The first day of the academic year has **no text of its own**; as a Gregorian date it is the 1st of September 2025."*

## What ties them together

Each of these is a small lattice of granularities: a fiscal *day* is of a fiscal *month*, of a fiscal *quarter*, of a fiscal *year*. Tempo asks the calendar for the span of each period, so a walk and `Tempo.to_interval/2` give the calendar's own granules and not the Gregorian ones.

## What is not here yet

Two families of human "calendar" are cycles counted from an epoch rather than divisions of a year, and Calendrical does not build them:

* **Sprints and pay periods** — a fixed cycle of *N* weeks from a start date. As a recurrence this needs no calendar: `~o"R/2026-01-05/P2W"` is a fortnightly cycle from the 5th of January.

* **Irregular academic terms** — autumn, spring and summer with boundaries of their own need a calendar of named periods, not a month offset.

Both would be additions to Calendrical.
