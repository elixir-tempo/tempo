# Working with Workdays and Weekends

Business-day queries are the most common reason developers reach for a date library beyond the standard library. "How many working days until the deadline?" "What's five business days from today?" "When does this invoice age out?" Tempo answers these directly with territory-aware, calendar-correct functions — `add_working_days/3`, `next_working_day/2`, `previous_working_day/2`, `working_days_in/2`, and the `workday?/2` / `weekend?/2` predicates.

This guide starts with those functions, then shows the lower-level `Tempo.select/2` + `Tempo.workdays/1` selector machinery they build on — useful when you need to weave workday-awareness into a larger set-operation query — and finishes with how to extend them with a real holiday calendar.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

## The built-in functions

For the common questions, reach for the built-ins directly. All are territory-aware (the weekend is read from CLDR) and calendar-correct (they work on any calendar Tempo supports, since the weekday is read off a date in the value's own calendar):

```elixir
import Tempo.Sigils

# Five business days on from a Monday is the next Monday.
Tempo.add_working_days(~o"2026-06-15", 5, :US)
#=> ~o"2026Y6M22D"

# Walk one working day forward / back, skipping the weekend.
Tempo.next_working_day(~o"2026-06-12", :US)        #=> ~o"2026Y6M15D"  (Fri → Mon)
Tempo.previous_working_day(~o"2026-06-15", :US)    #=> ~o"2026Y6M12D"

# Is this a working day, or a weekend, in this territory?
Tempo.workday?(~o"2026-06-13", :US)                #=> false  (Saturday)
Tempo.weekend?(~o"2026-06-12", :SA)                #=> true   (Friday, in Saudi Arabia)

# How many working days in a window? (half-open [from, to))
{:ok, june} = Tempo.Interval.new(from: ~o"2026-06-01", to: ~o"2026-07-01")
Tempo.working_days_in(june, :US)                   #=> 22
```

The territory argument resolves through `Tempo.Territory.resolve/1` — an atom (`:US`), a string (`"US"`), a locale (`"en-GB"`), or `nil` to walk the configured/ambient chain. `add_working_days/3` preserves the time of day, calendar, and zone, and `0` is a no-op.

These functions know about **weekends only**. For a holiday-aware calendar, see [Extending with holidays](#extending-with-holidays) at the end of this guide. The rest of the guide shows the `Tempo.select/2` selector machinery the built-ins compose with — reach for it when a workday filter is one step inside a larger query.

## The three primitives

All business-day queries in Tempo reduce to three capabilities the library already provides:

* **Build a window.** `Tempo.shift/2` (keyword-list duration arithmetic) and `Tempo.Interval.new!/1` construct a bounded span to search over.

* **Narrow to workdays.** `Tempo.workdays/1` returns a territory-aware day-of-week selector — `Tempo.workdays(:US)` is Mon-Fri, `Tempo.workdays(:SA)` is Sun-Thu. `Tempo.select(interval, Tempo.workdays(:US))` returns a `%Tempo.IntervalSet{}` of just the workdays inside the window. The companion `Tempo.weekend/1` is the complement — together they partition the seven days of the week.

* **Pick an element.** `Tempo.IntervalSet.to_list/1` produces a plain list of `%Tempo.Interval{}` values that `Enum.at/2`, `Enum.count/1`, `List.last/1`, `hd/1`, and friends operate on directly.

Every workday query below is a one-liner composition of these three.

## Core example — N business days from today

"Five business days from today" is the most-asked version of this question. Here it is end-to-end:

```elixir
today = ~o"2026-06-15"  # a Monday

window_end = Tempo.shift(today, week: 6)                  # generous window
window     = Tempo.Interval.new!(from: today, to: window_end)

{:ok, workdays} = Tempo.select(window, Tempo.workdays(:US))

target =
  workdays
  |> Tempo.IntervalSet.to_list()
  |> Enum.at(5)
#=> %Tempo.Interval{from: ~o"2026Y6M22D", ...}
```

Read aloud: *"Build a window from today that's long enough to contain five workdays. Narrow it to just the US workdays. Take the fifth one."* The convention here matches banking and SLA usage — today is day zero, so `Enum.at(5)` is "the fifth business day after today". If you want to count today as day one, use `Enum.at(n - 1)`.

The window needs to be generous enough to contain `n` workdays. Six weeks holds 30 workdays in any territory, and `Tempo.select/2` is fast enough that the oversize doesn't matter. The idiomatic way to size it is `Tempo.shift(today, week: n + 1)` — a week per five workdays plus one for good measure.

### Why the window matters

You may wonder why we can't just "walk forward from today until we've counted five workdays". The answer is Tempo's thesis: iteration is bounded by design. Every enumeration is over a finite span — there's no infinite stream of days to filter. The window makes the computation finite and the laziness unnecessary; `Tempo.select/2` returns the complete result, and `Enum.at/2` does the index lookup.

## Related queries

Every scheduling question you'd ask about business days is a small variation on the core pattern.

### Is today a business day?

```elixir
tempo
|> Tempo.day_of_week()
|> Kernel.in(1..5)     # 1 = Mon, 7 = Sun; M-F for the US
#=> true or false
```

This is the fast path — no interval needed. For territory-aware weekend detection, use the selector:

```elixir
{:ok, set} = Tempo.select(tempo, Tempo.workdays(:SA))
Tempo.IntervalSet.count(set) > 0
#=> true if `tempo` is a workday under Saudi Arabia's Fri/Sat weekend
```

### Next business day

```elixir
tomorrow  = Tempo.shift(today, day: 1)
window    = Tempo.Interval.new!(from: tomorrow, to: Tempo.shift(today, week: 2))

{:ok, workdays} = Tempo.select(window, Tempo.workdays(:US))

next_wd =
  workdays
  |> Tempo.IntervalSet.to_list()
  |> hd()
#=> Friday's next_wd is the following Monday.
```

Read aloud: *"Starting tomorrow, find the US workdays in the next two weeks and take the first."* A two-week window is generous — the longest weekend in any territory is three days, so the first workday is always within a week.

### Business days between two dates

```elixir
window = ~o"2026-06-15/2026-06-29"

{:ok, workdays} = Tempo.select(window, Tempo.workdays(:US))
Tempo.IntervalSet.count(workdays)
#=> 10   (two full work weeks)
```

This is a direct `Enum.count/1` on the members. For inclusive/exclusive day-counting semantics, adjust the `from` and `to` endpoints — Tempo uses half-open `[from, to)` consistently, so a 14-day span (`2026-06-15` through `2026-06-28` inclusive) is `from: 15, to: 29`.

### Nth business day of month

```elixir
{:ok, workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
members         = Tempo.IntervalSet.members(workdays)

first = Tempo.Interval.from(Tempo.IntervalSet.first(workdays))  #=> ~o"2026Y6M1D"
last  = Tempo.Interval.from(Tempo.IntervalSet.last(workdays))   #=> ~o"2026Y6M30D"
third = Tempo.Interval.from(Enum.at(members, 2))                #=> ~o"2026Y6M3D"
```

Passing a month-resolution Tempo value to `Tempo.select/2` is the cleanest form — the selector treats the implicit month-span as the search window. Read aloud: *"The US workdays of June 2026 are these; take the first / last / third."*

## Territory-aware weekends

Weekend conventions vary by territory. `Tempo.workdays/1` and `Tempo.weekend/1` honour CLDR data:

```elixir
# United States: Mon–Fri workdays, Sat–Sun weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:US))

# Saudi Arabia: Sun–Thu workdays, Fri–Sat weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:SA))

# Iran: Sat–Wed workdays, Thu–Fri weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:IR))
```

`Tempo.workdays/1` and `Tempo.weekend/1` accept a territory atom (`:US`), a territory string (`"US"`, `"sa"`, `"sazzzz"`), a locale string (`"en-GB"`, `"ar-SA"`), or a `%Localize.LanguageTag{}`. Passing `nil` (or calling with no arguments) walks the resolution chain: `Application.get_env(:ex_tempo, :default_territory)`, then the ambient `Localize.get_locale()`. See `Tempo.Territory.resolve/1` for the full normalisation rules.

## `Tempo.select/2` is pure

`Tempo.select/2` has no ambient reads. Every input that can affect the result is a value on the selector. `Tempo.workdays(:US)` is the value that carries the US workday definition — it's constructed once and composed in:

```elixir
# These produce the same IntervalSet:
Tempo.select(window, Tempo.workdays(:US))
Tempo.select(window, Tempo.workdays("en-US"))

# Hand-rolled day-of-week selector (works but bakes :US-specific knowledge):
Tempo.select(window, ~o"{1..5}K")
```

The benefit of naming a selector `Tempo.workdays(:US)` is that **the territory indirection lives in the constructor**. A hardcoded `[1..5]` would be wrong in Saudi Arabia. `Tempo.workdays(territory)` delegates that decision to CLDR, and because the constructor returns a plain `%Tempo{}` value, it's safe to capture anywhere — including a module attribute, since the territory is explicit and the result isn't locale-sensitive at capture time:

```elixir
@us_workdays Tempo.workdays(:US)  # safe — :US is explicit

def workdays_in(window), do: Tempo.select(window, @us_workdays)
```

Because the result is an `IntervalSet`, set operations compose naturally and preserve member identity. Three common patterns:

```elixir
# Workdays minus holidays — survivors keep their original member
# identity, each day distinct:
{:ok, net_workdays} = Tempo.members_outside(workdays, holidays)

# Workdays that overlap a specific window (filter, not trim):
{:ok, q2_workdays} = Tempo.members_overlapping(workdays, ~o"2026-04/2026-07")

# All workdays across territories — union preserves both sides'
# members so per-territory metadata survives:
{:ok, global}   = Tempo.union(us_workdays, de_workdays)
```

See the [set operations guide](./set-operations.md) for the distinction between the **instant-level** defaults (`intersection`, `difference`, `symmetric_difference`, `complement`) and the **member-preserving** companions (`union`, `members_overlapping`, `members_outside`, `members_in_exactly_one`) — the former for covered-time questions, the latter for event-list questions.

## Extending with holidays

The built-in functions handle weekends; **holidays are a domain concern** Tempo deliberately leaves to your app — which territory's holidays, which year's calendar, whether fiscal-quarter-end adjustments apply, are all choices the library can't make for you. The shape is to compose the built-ins (or the selector) with your own holiday set. Skipping weekends *and* holidays:

```elixir
defmodule MyApp.BusinessDays do
  @moduledoc "Business-day arithmetic that also skips MyApp's holidays."

  # `holidays` is a MapSet of day-resolution Tempo values, e.g. loaded
  # from an ICS feed (see the Holidays guide).
  def add(from, n, holidays, territory \\ :US) when n > 0 do
    Enum.reduce(1..n, from, fn _, day -> next_business_day(day, holidays, territory) end)
  end

  defp next_business_day(day, holidays, territory) do
    candidate = Tempo.next_working_day(day, territory)
    if MapSet.member?(holidays, candidate), do: next_business_day(candidate, holidays, territory), else: candidate
  end

  def business_day?(tempo, holidays, territory \\ :US) do
    Tempo.workday?(tempo, territory) and not MapSet.member?(holidays, tempo)
  end
end
```

The weekend logic is `Tempo.next_working_day/2` and `Tempo.workday?/2`; your module adds only the holiday filter. See the [Holidays guide](./holidays.md) for loading a real holiday calendar from an ICS feed.

If for some reason you need the lower-level selector form of the built-ins — for example to fold a workday filter into a larger `Tempo.select/2` pipeline — the same patterns expressed over `Tempo.workdays/1` are:

```elixir
defmodule MyApp.BusinessDays do
  @moduledoc """
  Business-day arithmetic for MyApp's booking logic.

  Territory defaults to :US; callers pass a different territory
  for locale-specific behaviour.
  """

  @doc """
  Add `n` business days to `from`.

  Today is day zero; `add(today, 1)` is tomorrow-if-workday else
  the next workday.
  """
  @spec add(Tempo.t(), pos_integer(), Tempo.Territory.input()) ::
          {:ok, Tempo.t()} | {:error, term()}
  def add(from, n, territory \\ :US) when n > 0 do
    window_end = Tempo.shift(from, week: n + 1)
    window = Tempo.Interval.new!(from: from, to: window_end)

    with {:ok, workdays} <- Tempo.select(window, Tempo.workdays(territory)) do
      case workdays |> Tempo.IntervalSet.to_list() |> Enum.at(n) do
        nil -> {:error, :not_enough_workdays_in_window}
        interval -> {:ok, Tempo.Interval.from(interval)}
      end
    end
  end

  @doc "Is `tempo` a business day in the given territory?"
  @spec business_day?(Tempo.t(), Tempo.Territory.input()) :: boolean()
  def business_day?(tempo, territory \\ :US) do
    case Tempo.select(tempo, Tempo.workdays(territory)) do
      {:ok, set} -> Tempo.IntervalSet.count(set) > 0
      _ -> false
    end
  end

  @doc "Count business days in `[from, to)`."
  @spec count_between(Tempo.t(), Tempo.t(), Tempo.Territory.input()) :: non_neg_integer()
  def count_between(from, to, territory \\ :US) do
    window = Tempo.Interval.new!(from: from, to: to)
    {:ok, workdays} = Tempo.select(window, Tempo.workdays(territory))
    Tempo.IntervalSet.count(workdays)
  end
end
```

These three selector-form helpers are exactly what `Tempo.add_working_days/3`, `Tempo.workday?/2`, and `Tempo.working_days_in/2` now do for you — shown here so the mechanism underneath the built-ins is legible. Reach for the selector form only when a workday filter is one step inside a larger `Tempo.select/2` pipeline; otherwise prefer the built-ins. What stays in your app is the part Tempo can't decide for you — *which* days are holidays, and any fiscal-calendar adjustments — composed on top as shown above.

## Related reading

* [Holidays — planning with a real holiday calendar](./holidays.md) — fetch an ICS holiday feed, compose it with `Tempo.workdays/1` for territory-aware scheduling.
* [Cookbook](./cookbook.md) — recipe-format examples for more scheduling patterns.
* [Set operations](./set-operations.md) — union, intersection, difference.
* [Scheduling](./scheduling.md) — bounded enumeration, wall-clock-vs-UTC, floating vs zoned.
* [Enumeration semantics](./enumeration-semantics.md) — how iteration works on Tempo values and IntervalSets.
