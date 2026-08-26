# Holidays — Planning with a Real Holiday Calendar

The [workdays-and-weekends guide](./workdays-and-weekends.md) showed how `Tempo.select(interval, Tempo.workdays(:US))` filters out weekends. Holidays are the other half of "when is the office closed?" — they're territory-specific, year-specific, and maintained by people who care about them. Tempo doesn't ship holiday data; instead, it consumes standard iCalendar (`.ics`) feeds through `Tempo.ICal.from_ical/1` and lets set operations do the rest.

This guide walks through fetching a real holiday calendar from [officeholidays.com](https://www.officeholidays.com/subscribe), parsing it into a `%Tempo.IntervalSet{}`, and using it to answer three scheduling questions: "how many working days are actually in Q3?", "which holidays will hit my project?", and "what's five business days from today if we skip holidays?".

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

## The data source

[officeholidays.com](https://www.officeholidays.com/subscribe) publishes public-holiday calendars for every UN-recognised country and territory, updated weekly, delivered as iCalendar `.ics` feeds. Two URL patterns to know:

* `https://www.officeholidays.com/ics/{country}` — all public holidays (includes state and regional holidays where relevant).

* `https://www.officeholidays.com/ics-fed/{country}` — federal or national-level holidays only.

Country names are lowercase with hyphens: `usa`, `united-kingdom`, `germany`, `japan`, `saudi-arabia`. Subscription URLs are the same as download URLs — a calendar program like iCal or Outlook points at the `webcal://` equivalent; our code fetches the `https://` form as a plain HTTP body.

## Fetching and parsing

The end-to-end fetch-and-parse is three lines:

<!-- guides:skip -->

```elixir
%Req.Response{body: ics} =
  Req.get!("https://www.officeholidays.com/ics-fed/usa")

{:ok, holidays} = Tempo.ICal.from_ical(ics)

Tempo.IntervalSet.count(holidays)
#=> 12    (US federal holidays for 2026)
```

(Any HTTP client works — the examples use [`:req`](https://hex.pm/packages/req); `:httpc` from OTP or another library is equally fine. What Tempo needs is the response body as a string.)

`Tempo.ICal.from_ical/1` returns a `%Tempo.IntervalSet{}` where each member is a `%Tempo.Interval{}` with the iCal event metadata preserved on `:metadata` — `summary`, `description`, `location`, `uid`, custom `X-*` properties. The intervals themselves are half-open `[from, to)` day-spans in Tempo's standard convention.

<!-- guides:skip -->

```elixir
holidays
|> Tempo.IntervalSet.to_list()
|> Enum.take(3)
|> Enum.each(fn iv ->
  IO.puts "#{Tempo.month(iv)}/#{Tempo.day(iv)}: #{Tempo.Interval.metadata(iv).summary}"
end)
#=> 1/1: New Year's Day
#=> 1/19: Martin Luther King Jr. Day
#=> 2/16: President's Day (Regional Holiday)
```

**Caching** — don't fetch on every request. The calendar updates weekly at most; store the parsed `%Tempo.IntervalSet{}` in an Agent, GenServer, `:persistent_term`, or your application's config cache and refresh on a schedule.

## Expressing fixed-rule holidays directly in ISO 8601

Many holidays need no feed at all: the ones with a purely calendrical rule — "the third Monday in January" — are recurrences Tempo can express as a native ISO 8601 string. Each round-trips through `Tempo.from_iso8601/1` and materialises to concrete dates once anchored to a year. Here are the eight US federal holidays with a fixed rule, given as the **observed public holiday** (not the underlying event date — see the notes below):

| Holiday | When it occurs (public holiday) | ISO 8601 expression |
|---|---|---|
| Martin Luther King Jr. Day | 3rd Monday in January | `R/../P1Y/FL1M3I1KN` |
| Presidents Day | 3rd Monday in February | `R/../P1Y/FL2M3I1KN` |
| Memorial Day | last Monday in May | `R/../P1Y/FL5M-1I1KN` |
| Independence Day | July 4 | `R/../P1Y/FL7M4DN` |
| Columbus Day | 2nd Monday in October | `R/../P1Y/FL10M2I1KN` |
| Veterans Day | November 11 | `R/../P1Y/FL11M11DN` |
| Thanksgiving | 4th Thursday in November | `R/../P1Y/FL11M4I4KN` |
| Christmas Day | December 25 | `R/../P1Y/FL12M25DN` |

**Reading the expression.** `R/../P1Y` is an unbounded yearly recurrence (`../` = no fixed start, `P1Y` = one-year cadence); `FL…N` wraps the per-year selection. Inside it, `nM` is the month (`1M` = January), `nD` is a day of the month (`4D` = the 4th), `nI` is the nth instance (`3I` = 3rd, `-1I` = last), and `nK` is a weekday (`1K` = Monday … `7K` = Sunday). So `FL1M3I1KN` reads "in January, the 3rd Monday" and `FL7M4DN` reads "in July, the 4th day". The full grammar is in the [ISO 8601 conformance guide](./iso8601-conformance.md).

**Observed day vs event day.** MLK Day, Presidents Day, Columbus Day, and Memorial Day are observed on a *weekday of the month*, deliberately different from the underlying event: Dr King's birthday is January 15, Washington's is February 22, the 1492 landing was October 12, and Memorial Day replaced a fixed May 30. The table gives the observed public-holiday rule, as intended.

**Weekend "in lieu" shifts are not part of the rule.** The three fixed-date holidays — Independence Day, Veterans Day, Christmas — are federally observed on the nearest weekday when the date lands on a weekend (July 4 on a Saturday is observed Friday July 3, which is why the feed above lists `7/3: Independence Day (in lieu)`). That shift is an observational rule, not a calendrical recurrence, so the ISO 8601 expression names the nominal date; where in-lieu days matter, the `.ics` feed remains authoritative.

### Computing the observed day yourself

You don't have to defer to the feed for the weekend shift — `Tempo.nearest_working_day/2` applies exactly the federal in-lieu rule (a Saturday rolls back to Friday, a Sunday forward to Monday), territory-aware for which days are the weekend:

```elixir
# 4 July 2026 is a Saturday
Tempo.nearest_working_day(~o"2026-07-04", :US)
#=> ~o"2026Y7M3D"    (observed Friday, 3 July)
```

It is a single-day transform, so map it over as many years as you like — the working-day family is weekend-aware, not holiday-aware, which is precisely right here because the in-lieu rule only cares about weekends:

```elixir
[2025, 2026, 2027]
|> Enum.map(&Tempo.nearest_working_day(Tempo.from_iso8601!("#{&1}-07-04"), :US))
#=> [~o"2025Y7M4D", ~o"2026Y7M3D", ~o"2027Y7M5D"]
#     Fri 4 (weekday)  Fri 3 (from Sat)  Mon 5 (from Sun)
```

`nearest_working_day/2` requires a value that denotes a day and raises otherwise; its siblings `next_working_day/2` and `previous_working_day/2` move by a fixed number of working days instead of snapping to the closest.

## Three planning questions

Assume the calendar has been fetched and parsed into `holidays`.

### 1. How many working days are actually in Q3 2026?

Pure set algebra: workdays minus holidays.

<!-- guides:skip -->

```elixir
q3 = ~o"2026-07-01/2026-10-01"

{:ok, workdays}     = Tempo.select(q3, Tempo.workdays(:US))
{:ok, net_workdays} = Tempo.members_outside(workdays, holidays)

Tempo.IntervalSet.count(net_workdays)
#=> 64    (66 workdays − 2 federal holidays in Q3)
```

Read aloud: *"Workdays in Q3 are the Monday-through-Friday days inside July-September. Net working days are those workday members that don't overlap any holiday."*

`Tempo.members_outside/2` is the **member-preserving** companion to `Tempo.difference/2`: each workday that survives the filter is kept as a distinct member, with its own day-level endpoints. This is the natural shape for "count the days" and "list the days" queries — no trimming, no fragmentation. (`Tempo.difference/2` would produce the same numeric result here, since each workday is either fully a holiday or fully not, but `members_outside` is the right name for an event-list question.)

#### Expressing the Q3 window

The `~o"from/to"` range sigil above is the most literal form. Three more concise alternatives all compose equally well with `Tempo.select/2` and the set operations:

```elixir
# ISO 8601 interval range:
q3 = ~o"2026-07/2026-10"

# ISO 8601-2 quarter designator:
q3 = ~o"2026Y3Q"

# Range-in-slot:
q3 = ~o"2026Y{7..9}M"
```

All four produce the same 66-workday count when passed through `Tempo.select(q3, Tempo.workdays(:US))`. Pick whichever reads most naturally for your domain. The quarter designator is the shortest and most direct for calendar-quarter queries; the range form `~o"2026-07/2026-10"` is the best fit when your window doesn't align to a standard quarter.

The same composition works for **seasons** (ISO 8601-2 codes 25–32, astronomical equinox/solstice bounded — e.g. `~o"2026Y26M"` for Northern summer), **month ranges** (`~o"2026Y{3..6}M"` for H1 minus Q1), and **archaeological masks** (`~o"156X"` for the 1560s). Each of these AST shapes materialises to concrete endpoints and flows cleanly through the workday selector and set operations.

### 2. Which holidays will hit my project?

`Tempo.members_overlapping/2` returns the holiday members that fall inside the query window — with their iCal metadata intact:

<!-- guides:skip -->

```elixir
q3 = ~o"2026-07/2026-10"
{:ok, q3_holidays} = Tempo.members_overlapping(holidays, q3)

q3_holidays
|> Tempo.IntervalSet.to_list()
|> Enum.each(fn iv ->
  IO.puts "#{Tempo.month(iv)}/#{Tempo.day(iv)}: #{Tempo.Interval.metadata(iv).summary}"
end)
#=> 7/3: Independence Day (in lieu)
#=> 7/4: Independence Day
#=> 9/7: Labor Day
```

Read aloud: *"The Q3 holidays are the holiday-set members that overlap the Q3 window. Each one carries its name from the iCal feed."*

Because `Tempo.members_overlapping/2` keeps surviving members whole — with their original metadata — you can compose further: filter to a team's availability, difference out someone's PTO, union multiple territories' holidays for an international team. The names travel through.

### 3. What's five business days from today, skipping holidays?

Four composed set operations. The whole pipeline is set-algebra; no list-level filtering required.

<!-- guides:skip -->

```elixir
today  = ~o"2026-06-30"
window = Tempo.Interval.new!(from: today, to: Tempo.shift(today, week: 3))

{:ok, workdays}  = Tempo.select(window, Tempo.workdays(:US))
{:ok, open_days} = Tempo.members_outside(workdays, holidays)

target =
  open_days
  |> Tempo.IntervalSet.to_list()
  |> Enum.at(5)
#=> %Tempo.Interval{from: ~o"2026Y7M8D", ...}
```

Read aloud: *"Starting today, build a three-week window. Keep the workdays inside it. Subtract the holidays. The sixth survivor is the answer for 'five business days from today' under the banking convention where today is day zero."*

(`Enum.at(5)` picks the sixth element. If your convention counts today as day one, use `Enum.at(n - 1)`.)

## Territory-aware planning

Change the URL, get a different country's holidays. The same code works for every territory officeholidays.com publishes:

```elixir
defmodule MyApp.HolidayCalendar do
  def fetch(territory) do
    url = "https://www.officeholidays.com/ics/#{territory_slug(territory)}"

    with {:ok, %Req.Response{status: 200, body: ics}} <- Req.get(url),
         {:ok, set} <- Tempo.ICal.from_ical(ics) do
      {:ok, set}
    end
  end

  defp territory_slug(:US), do: "usa"
  defp territory_slug(:GB), do: "united-kingdom"
  defp territory_slug(:DE), do: "germany"
  defp territory_slug(:JP), do: "japan"
  defp territory_slug(:SA), do: "saudi-arabia"
  # extend as needed
end
```

Pair this with `Tempo.select(interval, Tempo.workdays(:SA))` for a fully territory-consistent planning layer: Saudi weekends (Fri/Sat) are excluded by the workday query; Saudi holidays come from the ICS feed; the set operations compose across both.

For teams across multiple territories, **union the holiday sets before differencing** — "office closed" becomes "any member territory's holiday":

```elixir
{:ok, us_holidays} = MyApp.HolidayCalendar.fetch(:US)
{:ok, gb_holidays} = MyApp.HolidayCalendar.fetch(:GB)
{:ok, de_holidays} = MyApp.HolidayCalendar.fetch(:DE)

{:ok, all_closed} = Tempo.union(us_holidays, gb_holidays)
{:ok, all_closed} = Tempo.union(all_closed, de_holidays)
```

Then compute "working days for the global team" as `Tempo.members_outside(workdays, all_closed)`. Each member interval still carries the territory/name metadata — so the July 3 entry stays labelled as US in the global union, and you can render conflicts with full attribution.

## Scheduling a training week

A concrete example that ties it together: pick the first five-day work week in Q3 2026 with no US federal holidays, suitable for scheduling a training course.

<!-- guides:skip -->

```elixir
q3 = ~o"2026-07/2026-10"

{:ok, workdays}  = Tempo.select(q3, Tempo.workdays(:US))
{:ok, open_days} = Tempo.members_outside(workdays, holidays)

candidate_weeks =
  open_days
  |> Tempo.IntervalSet.to_list()
  |> Enum.chunk_by(&week_key/1)
  |> Enum.filter(&(length(&1) == 5))

first_available = hd(candidate_weeks)
#=> five-member list starting the Monday of the first clean week
```

Read aloud: *"Take the open workdays of Q3, group them by week, keep only the weeks that still have all five workdays, and pick the first."* `week_key/1` is a helper you'd write — the year-week pair derived from each interval's `from` endpoint. The core logic is four composable set operations on Tempo's primitives.

## Related reading

* [Working with workdays and weekends](./workdays-and-weekends.md) — `Tempo.workdays/1`, `Tempo.weekend/1`, territory-aware weekend conventions, and the primitive patterns this guide builds on.

* [Set operations](./set-operations.md) — union, intersection, difference, the instant-level vs member-preserving distinction, and companions like `members_overlapping`/`members_outside`.

* [iCalendar integration](./ical-integration.md) — full detail on `Tempo.ICal.from_ical/1`, metadata preservation, and round-tripping `.ics` files.

* [Cookbook](./cookbook.md) — recipe-format examples for scheduling, availability, and related queries.
