# Working with workdays and weekends

Business-day queries are the most common reason developers reach for a date library beyond the standard library. "How many workdays until the deadline?" "What's five business days from today?" "When does this invoice age out?" Tempo answers these directly with territory-aware, calendar-correct functions — `add_workdays/3`, `next_workday/2`, `previous_workday/2`, `nearest_workday/2`, `roll_to_workday/3`, `count_workdays/2`, and the `workday?/2` and `weekend?/2` predicates.

This guide starts with those functions, then shows the `Tempo.select/2` selectors they build on — `Tempo.workdays/1` and `Tempo.weekends/1`, useful when you need to weave workday-awareness into a larger set-operation query — and finishes with how to extend them with a real holiday calendar.

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
Tempo.add_workdays(~o"2026-06-15", 5, :US)
#=> ~o"2026Y6M22D"

# Walk one workday forward or back, skipping the weekend.
Tempo.next_workday(~o"2026-06-12", :US)        #=> ~o"2026Y6M15D"  (Fri → Mon)
Tempo.previous_workday(~o"2026-06-15", :US)    #=> ~o"2026Y6M12D"

# A weekend day moves to the nearest workday: this Saturday back to Friday.
Tempo.nearest_workday(~o"2026-07-04", :US)     #=> ~o"2026Y7M3D"

# A day off rolls to the workday after it: this Saturday on to Monday.
Tempo.roll_to_workday(~o"2026-05-30", :US)     #=> ~o"2026Y6M1D"

# Is this a workday, or a weekend, in this territory?
Tempo.workday?(~o"2026-06-13", :US)            #=> false  (Saturday)
Tempo.weekend?(~o"2026-06-12", :SA)            #=> true   (Friday, in Saudi Arabia)

# How many workdays in June? (half-open, so the 1st of July is not counted)
Tempo.count_workdays(~o"2026-06", :US)         #=> 22
```

The territory argument resolves through `Tempo.Territory.resolve/1` — an atom (`:US`), a string (`"US"`), a locale (`"en-GB"`), or `nil` to walk the configured/ambient chain. `add_workdays/3` preserves the time of day, calendar, and zone, and `0` is a no-op. A value that does not denote a day, or a territory that cannot be resolved, returns `{:error, reason}` rather than raising.

Given a territory, these functions know its weekend; given the workdays `Tempo.workdays/2` makes with `:except`, they step over holidays too — see [Holidays](#holidays) at the end of this guide. The rest of the guide shows the `Tempo.select/2` selectors the built-ins compose with — reach for them when a workday filter is one step inside a larger query.

## The three primitives

All business-day queries in Tempo reduce to three capabilities the library already provides:

* **Name a span.** A month (`~o"2026-06"`), an explicit span (`~o"2026-06-15/2026-06-29"`), or a span with no end (`~o"2026-06-15/.."`) is the window to search.

* **Narrow to workdays.** `Tempo.workdays/1` returns a territory-aware day-of-week selector — `Tempo.workdays(:US)` is Mon-Fri, `Tempo.workdays(:SA)` is Sun-Thu. `Tempo.select(span, Tempo.workdays(:US))` returns a `%Tempo.IntervalSet{}` of just the workdays inside the span. The companion `Tempo.weekends/1` is the complement — together they partition the seven days of the week.

* **Pick an element.** `Tempo.IntervalSet.members/1` produces a plain list of `%Tempo.Interval{}` values that `Enum.at/2`, `Enum.count/1`, `List.last/1`, `hd/1`, and friends operate on directly, and `Tempo.IntervalSet.walk/1` walks a set that has no end.

Every workday query below is a one-liner composition of these three.

## Core example — N business days from today

"Five business days from today" is the most-asked version of this question. `Tempo.add_workdays/3` answers it; here it is with the selectors, end to end:

```elixir
today = ~o"2026-06-15"  # a Monday

{:ok, workdays} = Tempo.select(Tempo.Interval.new!(from: today), Tempo.workdays(:US))

workdays
|> Tempo.IntervalSet.walk()
|> Enum.at(5)
#=> ~o"2026Y6M22D/23D"
```

Read aloud: *"The US workdays from today on. Take the fifth after today."* The convention here matches banking and SLA usage — today is day zero, so `Enum.at(5)` is "the fifth business day after today". If you want to count today as day one, use `Enum.at(n - 1)`.

### A span with no end

`Tempo.Interval.new!(from: today)` is the span from today on — `~o"2026-06-15/.."` written as a literal. Selecting from a span with no end gives a lazy set: it finds each workday only as the walk reaches it, so `Enum.at(5)` finds six and stops. Questions that need every member (`Tempo.IntervalSet.count/1`, `members/1`, the set operations) refuse a lazy set with `Tempo.UnboundedSetError`: take what you need from `Tempo.IntervalSet.walk/1`, or give the span an end. The same lazy set is the busy time `Tempo.shift/3` skips — see the [scheduling guide](./scheduling.md).

## Related queries

Every scheduling question you'd ask about business days is a small variation on the core pattern.

### Is today a business day?

```elixir
Tempo.workday?(~o"2026-06-12", :SA)
#=> false   (Friday is the weekend in Saudi Arabia)
```

As a selection, a single day selects itself or nothing:

```elixir
{:ok, set} = Tempo.select(~o"2026-06-12", Tempo.workdays(:SA))
Tempo.IntervalSet.count(set)
#=> 0
```

### Next business day

```elixir
Tempo.next_workday(~o"2026-06-12", :US)
#=> ~o"2026Y6M15D"   (Friday → Monday)
```

As a selection, the first of the workdays from tomorrow on:

```elixir
tomorrow = Tempo.shift(~o"2026-06-12", day: 1)

{:ok, workdays} = Tempo.select(Tempo.Interval.new!(from: tomorrow), Tempo.workdays(:US))
Tempo.IntervalSet.first(workdays)
#=> ~o"2026Y6M15D/16D"
```

Read aloud: *"Starting tomorrow, the US workdays; take the first."*

### A date that must fall on a business day

A payment that falls due on a day off is made on a workday, and which one is the contract's business day convention. `Tempo.roll_to_workday/3` leaves a workday where it is and rolls a day off by the convention `:roll` names:

```elixir
due = ~o"2026-05-30"  # a Saturday

Tempo.roll_to_workday(due, :US)
#=> ~o"2026Y6M1D"

Tempo.roll_to_workday(due, :US, roll: :preceding)
#=> ~o"2026Y5M29D"

Tempo.roll_to_workday(due, :US, roll: :modified_following)
#=> ~o"2026Y5M29D"
```

> *"A payment due on a Saturday is made on the Monday **following**. By the **preceding** convention it is made on the Friday. By **modified following** it is made on the Monday unless that is in the next month, and Monday is 1 June, so it is made on the Friday."*

The four conventions are `:following` (the default), `:preceding`, and `:modified_following` and `:modified_preceding`, which turn back where the workday they roll to is in another month, so a payment due at a month's end stays in its month. A workday is not moved, which `next_workday/2` always does, and the side is the convention's to say, where `nearest_workday/2` takes the closer one. Given the business days of [Holidays](#holidays) in place of the territory, a holiday is rolled over as a weekend day is.

### Business days between two dates

```elixir
Tempo.count_workdays(~o"2026-06-15/2026-06-29", :US)
#=> 10   (two full work weeks)
```

Tempo uses half-open `[from, to)` consistently, so a 14-day span (`2026-06-15` through `2026-06-28` inclusive) is `from: 15, to: 29`.

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

Weekend conventions vary by territory. `Tempo.workdays/1` and `Tempo.weekends/1` honour CLDR data:

```elixir
# United States: Mon–Fri workdays, Sat–Sun weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:US))

# Saudi Arabia: Sun–Thu workdays, Fri–Sat weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:SA))

# Iran: Sat–Thu workdays, a Friday weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:IR))
```

`Tempo.workdays/1` and `Tempo.weekends/1` accept a territory atom (`:US`), a territory string (`"US"`, `"sa"`, `"sazzzz"`), a locale string (`"en-GB"`, `"ar-SA"`), or a `%Localize.LanguageTag{}`. Passing `nil` (or calling with no arguments) walks the resolution chain: `Application.get_env(:ex_tempo, :default_territory)`, then the ambient `Localize.get_locale()`. See `Tempo.Territory.resolve/1` for the full normalisation rules.

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

## Holidays

Which days are holidays is your application's to say: which territory's, which year's, whether a fiscal quarter-end counts. Tempo's part is to leave them out. `Tempo.workdays/2` with `:except` makes the workdays less a set of holidays, and `Tempo.select/2` and every workday function take that in place of a territory:

```elixir
# Independence Day, and Friday 3 July 2026, the day it is observed.
holidays = Tempo.RecurrenceSet.new!([~o"R/../P1Y/FL7M4DN", ~o"2026-07-03"])
business_days = Tempo.workdays(:US, except: holidays)

Tempo.add_workdays(~o"2026-06-30", 5, business_days)
#=> ~o"2026Y7M8D"

Tempo.workday?(~o"2026-07-03", business_days)
#=> false

Tempo.count_workdays(~o"2026-07", business_days)
#=> 22
```

> *"Business days are the US workdays except Independence Day and the day it is observed. Five business days after 30 June is 8 July, 3 July is not a business day, and July has 22 of them."*

The holidays are anything `Tempo.to_interval_set/2` converts: a set of recurring holidays (a `Tempo.RecurrenceSet`, as the `tempo_holidays` package returns), an interval set read from an ICS feed (see the [Holidays guide](./holidays.md)), or a single day. A recurring set needs no window of its own: the holidays are converted around the days a question asks about.

The same value folds a business-day filter into a larger `Tempo.select/2` pipeline, as the weekday selector does:

```elixir
{:ok, open_days} = Tempo.select(~o"2026Y3Q", business_days)
```

## Related reading

* [Holidays — planning with a real holiday calendar](./holidays.md) — fetch an ICS holiday feed and leave its holidays out of the workdays.

* [Cookbook](./cookbook.md) — recipe-format examples for more scheduling patterns.

* [Set operations](./set-operations.md) — union, intersection, difference.

* [Scheduling](./scheduling.md) — bounded enumeration, wall-clock-vs-UTC, floating vs zoned.

* [Enumeration semantics](./enumeration-semantics.md) — how iteration works on Tempo values and IntervalSets.
