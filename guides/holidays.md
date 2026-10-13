# Holidays — Planning with a Real Holiday Calendar

The [workdays-and-weekends guide](./workdays-and-weekends.md) showed how `Tempo.select(interval, Tempo.workdays(:US))` leaves out weekends. Holidays are the other half of "when is the office closed?" — they are a territory's, they change by the year, and they are kept by people who care about them. Tempo ships no holiday data. It gives you two ways to hold a holiday calendar, and one way to use it:

* **Rules**, for holidays that have one: "the third Monday in January" is a recurrence ISO 8601 can write.

* **A feed**, for everything else: a standard iCalendar (`.ics`) file read with `Tempo.ICal.parse/2`.

Either way the holidays are a set of days, and the set operations do the rest. This guide answers three planning questions with them: *how many workdays are really in the third quarter?*, *which holidays will hit my project?* and *what is five business days from today?*

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`:

```elixir
import Tempo.Sigils
```

## Holidays as rules

Many holidays need no feed at all. One with a purely calendrical rule is a recurrence, written as ISO 8601 text that reads back to the same rule. Here are the eleven US federal holidays, each by the day it falls on:

| Holiday | When | ISO 8601 |
|---|---|---|
| New Year's Day | 1 January | `R/../P1Y/FL1M1DN` |
| Martin Luther King Jr. Day | 3rd Monday in January | `R/../P1Y/FL1M1K3IN` |
| Presidents Day | 3rd Monday in February | `R/../P1Y/FL2M1K3IN` |
| Memorial Day | last Monday in May | `R/../P1Y/FL5M1K-1IN` |
| Juneteenth | 19 June | `R/../P1Y/FL6M19DN` |
| Independence Day | 4 July | `R/../P1Y/FL7M4DN` |
| Labor Day | 1st Monday in September | `R/../P1Y/FL9M1K1IN` |
| Columbus Day | 2nd Monday in October | `R/../P1Y/FL10M1K2IN` |
| Veterans Day | 11 November | `R/../P1Y/FL11M11DN` |
| Thanksgiving | 4th Thursday in November | `R/../P1Y/FL11M4K4IN` |
| Christmas Day | 25 December | `R/../P1Y/FL12M25DN` |

**Reading a rule.** `R/../P1Y` is a recurrence with no start and no end that steps by a year, and `F` begins its rule, a selection between `L` and `N`. Inside it `nM` is a month, `nD` a day of the month, `nK` a weekday (`1K` is Monday, `7K` Sunday) and `nI` the position among what the rest select (`3I` the third, `-1I` the last). So `FL1M1K3IN` reads "in January, the Mondays, the third" and `FL7M4DN` "in July, the 4th". The [conformance guide](./iso8601-conformance.md) has the whole of it.

A rule with no end is listed within a window, and a name is carried as metadata on each of its dates:

```elixir
iex> thanksgiving = Tempo.put_metadata(~o"R/../P1Y/FL11M4K4IN", %{name: "Thanksgiving"})
iex> {:ok, in_2026} = Tempo.to_interval(thanksgiving, within: ~o"2026")
iex> Tempo.IntervalSet.map(in_2026, &{Tempo.month(&1), Tempo.day(&1), Tempo.metadata(&1).name})
[{11, 26, "Thanksgiving"}]
```

> *"**Thanksgiving** in 2026: the fourth Thursday of November, the 26th."*

`Tempo.RecurrenceSet` holds several rules as one calendar:

<!-- guides:run -->
```elixir
federal = [
  {"New Year's Day", ~o"R/../P1Y/FL1M1DN"},
  {"Martin Luther King Jr. Day", ~o"R/../P1Y/FL1M1K3IN"},
  {"Presidents Day", ~o"R/../P1Y/FL2M1K3IN"},
  {"Memorial Day", ~o"R/../P1Y/FL5M1K-1IN"},
  {"Juneteenth", ~o"R/../P1Y/FL6M19DN"},
  {"Independence Day", ~o"R/../P1Y/FL7M4DN"},
  {"Labor Day", ~o"R/../P1Y/FL9M1K1IN"},
  {"Columbus Day", ~o"R/../P1Y/FL10M1K2IN"},
  {"Veterans Day", ~o"R/../P1Y/FL11M11DN"},
  {"Thanksgiving", ~o"R/../P1Y/FL11M4K4IN"},
  {"Christmas Day", ~o"R/../P1Y/FL12M25DN"}
]

rules = for {name, rule} <- federal, do: Tempo.put_metadata(rule, %{name: name})
{:ok, calendar} = Tempo.RecurrenceSet.new(rules)
{:ok, holidays} = Tempo.to_interval(calendar, within: ~o"2026")
```

```elixir
iex> Tempo.IntervalSet.count(holidays)
11

iex> holidays |> Tempo.IntervalSet.members() |> Enum.take(3) |> Enum.map(&{Tempo.month(&1), Tempo.day(&1), Tempo.metadata(&1).name})
[{1, 1, "New Year's Day"}, {1, 19, "Martin Luther King Jr. Day"}, {2, 16, "Presidents Day"}]
```

> *"The **federal holidays within 2026**: eleven days, each with its name."*

### The day a holiday is observed

A holiday on a fixed date is observed on the nearest weekday when the date is on a weekend: the 4th of July on a Saturday is observed on Friday the 3rd. `Tempo.nearest_workday/2` is that rule, knowing each territory's weekend:

```elixir
iex> Tempo.nearest_workday(~o"2026-07-04", :US)
{:ok, ~o"2026Y7M3D"}

iex> Enum.map([2025, 2026, 2027], &Tempo.nearest_workday(Tempo.new!(year: &1, month: 7, day: 4), :US))
[ok: ~o"2025Y7M4D", ok: ~o"2026Y7M3D", ok: ~o"2027Y7M5D"]
```

> *"The **nearest workday** to the 4th of July: itself in 2025, the Friday before in 2026, the Monday after in 2027."*

The same rule is a part of a recurrence, so a holiday and the day it is observed are one expression. The part is a roll, written `(nearest)r` after the day it moves:

```elixir
iex> independence_day = Tempo.every!(~o"P1Y", from: ~o"2025-01-01", select: [month: 7, day: 4, roll: :nearest])
iex> Tempo.to_iso8601!(independence_day)
"R/2025Y1M1D/P1Y/FL7M4D(nearest)rN"

iex> {:ok, observed} = Tempo.members(independence_day, within: ~o"2025/2027", locale: "en-US")
iex> Enum.map(observed, &Tempo.Interval.from/1)
[~o"2025Y7M4D", ~o"2026Y7M3D", ~o"2027Y7M5D"]
```

> *"**Every year**, the **4th of July**, **rolled to the nearest weekday** of the **American** working week."*

The weekdays are those of the locale the days are asked for in, and of the territory in force where none is named: under a locale that works Sunday to Thursday the same rule keeps a Sunday and moves a Friday. The conventions are those of `Tempo.roll_to_workday/3`; `(modified-nearest)r` never leaves the month, which is cron's `15W`.

`Tempo.next_workday/2` and `Tempo.previous_workday/2` move one way only, for the territories that always observe a weekend holiday on the Monday.

Holidays derived from a computed one are rules too. Good Friday is the last Friday in the seven days before Easter:

```elixir
iex> Tempo.to_interval(~o"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN", within: ~o"2026/2027")
{:ok, ~o"{2026Y4M3D/2026Y4M3D,2027Y3M26D/2027Y3M26D}"}
```

The [holiday cookbook](./holiday-cookbook.md) has many more, by territory.

## Holidays from a feed

A rule says when a holiday falls. It does not say that a government moved one this year, declared a day of mourning, or observes a regional holiday. For those, use a feed. [officeholidays.com](https://www.officeholidays.com/subscribe) publishes one for every country and territory as iCalendar:

* `https://www.officeholidays.com/ics/{country}` — all public holidays, regional ones among them.

* `https://www.officeholidays.com/ics-fed/{country}` — national holidays only.

Country names are lowercase with hyphens: `usa`, `united-kingdom`, `germany`, `japan`, `saudi-arabia`.

<!-- guides:skip -->
```elixir
%Req.Response{body: ics} = Req.get!("https://www.officeholidays.com/ics-fed/usa")

{:ok, holidays} = Tempo.ICal.parse(ics)
```

Any HTTP client will do; what Tempo needs is the body as text. Each holiday is an interval of days, with the event's `SUMMARY` as `Tempo.metadata(holiday).summary` (see [iCalendar integration](./ical-integration.md)). Do not fetch on every request: a holiday calendar changes weekly at most, so keep the parsed set and refresh it on a schedule.

Everything below works the same on a set from a feed as on the set from the rules above.

## Three planning questions

### 1. How many workdays are really in the third quarter of 2026?

Workdays, less the holidays:

```elixir
iex> third_quarter = ~o"2026-07/2026-09"
iex> {:ok, workdays} = Tempo.select(third_quarter, Tempo.workdays(:US))
iex> Tempo.IntervalSet.count(workdays)
66

iex> {:ok, net_workdays} = Tempo.members_outside(workdays, holidays)
iex> Tempo.IntervalSet.count(net_workdays)
65
```

> *"The **workdays** of the quarter are its Mondays to Fridays: sixty-six. Those **outside the holidays** are sixty-five — Labor Day is a Monday, and the 4th of July a Saturday."*

`Tempo.members_outside/2` keeps each surviving workday a member of its own, which is the shape for counting and listing days.

The quarter can be written several ways, and each selects the same sixty-six workdays:

```elixir
iex> Enum.map([~o"2026-07/2026-09", ~o"2026-35", ~o"2026Y{7..9}M"], fn quarter ->
...>   {:ok, workdays} = Tempo.select(quarter, Tempo.workdays(:US))
...>   {Tempo.to_iso8601!(quarter), Tempo.IntervalSet.count(workdays)}
...> end)
[{"2026Y7M/9M", 66}, {"2026Y35M", 66}, {"2026Y{7..9}M", 66}]
```

`~o"2026-35"` is ISO 8601-2's third quarter (33 to 36 are the four), the shortest for a calendar quarter. The interval is the one to write when a window is not a quarter.

### 2. Which holidays will hit my project?

```elixir
iex> {:ok, in_quarter} = Tempo.members_overlapping(holidays, third_quarter)
iex> Tempo.IntervalSet.map(in_quarter, &{Tempo.month(&1), Tempo.day(&1), Tempo.metadata(&1).name})
[{7, 4, "Independence Day"}, {9, 7, "Labor Day"}]
```

> *"The holidays **overlapping** the quarter, each with its name."*

`Tempo.members_overlapping/2` keeps each holiday whole, with its metadata, so the answer composes further: with a team's availability, with someone's leave, with another territory's holidays.

### 3. What is five business days from today, skipping holidays?

The workdays less the holidays are one value, and the workday functions step over both:

```elixir
iex> business_days = Tempo.workdays(:US, except: holidays)
iex> Tempo.add_workdays(~o"2026-08-31", 5, business_days)
{:ok, ~o"2026Y9M8D"}

iex> Tempo.count_workdays(third_quarter, business_days)
{:ok, 65}

iex> Tempo.workday?(~o"2026-09-07", business_days)
false
```

> *"**Business days** are the US workdays **except** the holidays. Five of them after the 31st of August is the 8th of September, Labor Day being stepped over."*

The same value answers question 1 in one call, asks about one day, and is a selector: `Tempo.select(window, business_days)` gives the days themselves.

## Several territories

A feed for another country is the same code with another name, and `Tempo.workdays/2` knows each territory's weekend, so Saudi Arabia's Friday and Saturday are left out by the workdays and its holidays by the feed.

<!-- guides:skip -->
```elixir
defmodule MyApp.HolidayCalendar do
  @slugs %{US: "usa", GB: "united-kingdom", DE: "germany", JP: "japan", SA: "saudi-arabia"}

  def fetch(territory) do
    url = "https://www.officeholidays.com/ics/#{Map.fetch!(@slugs, territory)}"

    with {:ok, %Req.Response{status: 200, body: ics}} <- Req.get(url) do
      Tempo.ICal.parse(ics)
    end
  end
end

{:ok, us_holidays} = MyApp.HolidayCalendar.fetch(:US)
{:ok, gb_holidays} = MyApp.HolidayCalendar.fetch(:GB)

{:ok, all_closed} = Tempo.union(us_holidays, gb_holidays)
```

> *"The office is **closed** on a holiday of **either** territory."*

`Tempo.union/2` keeps every member, so each holiday in the union still carries its name.

## Scheduling a training week

To finish: the first week of the quarter with all five workdays open, for a course that runs Monday to Friday.

```elixir
iex> {:ok, open_days} = Tempo.members_outside(workdays, holidays)
iex> first_whole_week =
...>   open_days
...>   |> Tempo.IntervalSet.members()
...>   |> Enum.chunk_by(&Tempo.week/1)
...>   |> Enum.find(&(Enum.count(&1) == 5))
iex> Enum.map(first_whole_week, &Tempo.day/1)
[6, 7, 8, 9, 10]
```

> *"Take the **open workdays** of the quarter, **by week**, and find the first week that still has **all five**: the 6th to the 10th of July."*

## Related reading

* [Working with workdays and weekends](./workdays-and-weekends.md) — `Tempo.workdays/2`, `Tempo.weekends/1` and each territory's weekend.

* [Holiday cookbook](./holiday-cookbook.md) — holiday rules by territory.

* [Set operations](./set-operations.md) — the operations on time and the ones that keep members.

* [iCalendar integration](./ical-integration.md) — what an `.ics` event becomes.

* [Cookbook](./cookbook.md) — recipes for scheduling and availability.
