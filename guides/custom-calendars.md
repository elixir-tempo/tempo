# Custom calendars — fiscal years, retail weeks, academic years

Tempo treats a calendar as **data, not a built-in assumption**. Comparison, duration, iteration, and materialisation all route through the value's calendar — so a *custom human calendar* is a first-class citizen alongside Gregorian, Hebrew, or Persian. You build the calendar once with [Calendrical](https://hexdocs.pm/calendrical), and every Tempo operation just works on values that carry it.

This is the [time-granularity idea](temporal-formalisms.md) made concrete: a **granularity is a calendar**. A fiscal quarter, a retail week, an academic term are all *granules* of a calendar whose year happens not to start on the 1st of January.

## A fiscal year

The US federal fiscal year runs October → September. Calendrical ships the fiscal calendars; Tempo consumes one directly:

```elixir
{:ok, us_fiscal} = Calendrical.FiscalYear.calendar_for(:US)

{:ok, fiscal_2026} = Tempo.from_iso8601("2026", us_fiscal)
{:ok, fiscal_months} = Tempo.to_interval(fiscal_2026)

Enum.count(fiscal_months)                       #=> 12
fiscal_months |> Enum.at(0) #=> ~o"2026Y1M"
```

> *"Fiscal year 2026 is twelve fiscal months; iterating it walks them in order."*

Because every comparison projects through the calendar, a fiscal date and a Gregorian date sit on the **same timeline** — no manual conversion:

```elixir
fiscal_q1_start = Tempo.from_iso8601!("2026-01-01", us_fiscal)

Tempo.relation(fiscal_q1_start, ~o"2025-10-01")   #=> :equals
Tempo.quarter_of_year(Tempo.from_iso8601!("2026-11-15", us_fiscal))  #=> 4
```

> *"US fiscal year 2026 begins on the 1st of October, 2025, and its eleventh fiscal month falls in the fourth fiscal quarter."*

## A retail 4-4-5 calendar

Retailers count time in **weeks**, grouped 4-4-5 into thirteen-week quarters. Build one with `Calendrical.new/3` and hand it to Tempo:

```elixir
{:ok, retail} = Calendrical.new(MyApp.Retail, :week, weeks_in_month: [4, 4, 5])

{:ok, retail_2026} = Tempo.from_iso8601("2026", retail)
{:ok, retail_weeks} = Tempo.to_interval(retail_2026)

Enum.count(retail_weeks)                        #=> 52
retail_weeks |> Enum.at(0) #=> ~o"2026Y1W"
```

> *"The 2026 retail year is fifty-two retail weeks; iterating it walks week by week."*

The `weeks_in_month: [4, 4, 5]` layout is the only thing that distinguishes this calendar from ISO weeks — everything else (iteration, comparison, duration) is inherited.

## An academic year

An academic year is just a year that starts in a different month. A September-start calendar is a month-based calendar with a `month_of_year` offset:

```elixir
{:ok, academic} = Calendrical.new(MyApp.Academic, :month, month_of_year: 9)

Tempo.relation(Tempo.from_iso8601!("2026-01-01", academic), ~o"2025-09-01")  #=> :equals
```

> *"Academic year 2026 begins on the 1st of September, 2025."*

## What ties them together

Each of these is a **granularity lattice** in miniature: a fiscal *day* groups into a fiscal *month* groups into a fiscal *quarter* groups into a fiscal *year*. Tempo reads that nesting off the calendar's own period structure, so `to_interval/1` and iteration yield the calendar's natural granules rather than Gregorian ones — the finer-than / groups-into relations of [time-granularity theory](temporal-formalisms.md) realised as calendar arithmetic.

## What isn't here yet

Two families of human "calendar" are **epoch-anchored cycles** rather than year-structured, and Calendrical does not yet build them, so Tempo cannot consume them:

* **Sprints and pay periods** — a fixed *N*-week cycle counted from an epoch (2-week sprints from a start date, biweekly pay periods) has no year boundary to hang on `Calendrical.Config`'s year-anchored fields.

* **Irregular academic terms** — Fall/Spring/Summer with bespoke, non-uniform boundaries need a *labelled* calendar, not a month offset.

Both are upstream Calendrical enhancements (an epoch-anchored *periodic* builder and a *labelled* builder). A small set of period-query conveniences on the Tempo side — "which fiscal quarter contains this date" as an interval, "the 3rd business day of Q2" — are also planned. Until then, the year-structured calendars above are fully supported.
