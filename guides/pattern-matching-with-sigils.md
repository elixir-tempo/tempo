# Pattern matching with sigils

The `~o"..."` sigil does double duty. In value context it parses a string into a `%Tempo{}` / `%Tempo.Interval{}` / `%Tempo.Duration{}` / `%Tempo.Set{}`. In **match context** — on the left-hand side of `match?/2`, a `case` clause, a bare `=`, or a function head — the same sigil expands to a *structural pattern* against that value's fields.

This guide is the complete specification of match context. For the everyday value-context use, see the module docs for `Tempo.Sigils`.

## The mental model

In value context, `~o"2026Y"` **produces** a Tempo for the whole of 2026. In match context, `~o"2026Y"` **recognises** any Tempo whose `:time` starts with `[year: 2026]`. The sigil string is the same; its meaning shifts with where you put it.

```elixir
import Tempo.Sigils

# Value context — produces a value.
year = ~o"2026Y"
#=> %Tempo{time: [year: 2026], …}

# Match context — recognises a value.
match?(~o"2026Y", year)
#=> true
```

The match-context pattern is deliberately **permissive**: it constrains only the struct fields the sigil string actually names. Calendar, time-zone shift, IXDTF metadata, and qualification are left unconstrained by default. The intent is temporal — "did the year/month/day/… line up?" — not structural equality.

## Prefix matching on Tempo and Duration

### Year / month / day prefixes

The sigil string is parsed as usual; the resulting `:time` keyword list becomes a cons-pattern terminated by a wildcard. A sigil with fewer units matches **any value whose `:time` starts with the same units**.

```elixir
import Tempo.Sigils

today = Tempo.new!(year: 2026, month: 4, day: 24)

match?(~o[2026Y], today)          #=> true  — year prefix
match?(~o[2026Y4M], today)        #=> true  — year + month prefix
match?(~o[2026Y4M24D], today)     #=> true  — full prefix
match?(~o[2026Y1M], today)        #=> false — month disagrees
match?(~o[2025Y], today)          #=> false — year disagrees
```

*"**Today** is a Tempo whose `:time` **starts with** year 2026, month 4, day 24."*

### Other fields are free

Because the pattern targets `:time` only, the matched value's `:calendar`, `:shift`, `:extended`, `:qualification`, and `:qualifications` fields are unconstrained.

```elixir
hebrew = Tempo.new!(
  year: 2026, month: 4, day: 24,
  calendar: Calendrical.Hebrew
)

match?(~o[2026Y], hebrew)        #=> true — :calendar is free
```

*"**Hebrew** shares a year-month-day prefix with the Gregorian sigil — temporal intent holds even though the calendars differ."*

### Durations

`%Tempo.Duration{}` values are matched the same way by their own `:time` keyword list.

```elixir
duration = Tempo.Duration.new!(year: 1, month: 6)

match?(~o[P1Y6M], duration)      #=> true
match?(~o[P2Y6M], duration)      #=> false
```

`%Tempo{}` and `%Tempo.Duration{}` patterns are *not* interchangeable — a Duration sigil won't match a Tempo value and vice versa:

```elixir
match?(~o[1Y6M], duration)       #=> false  — %Tempo{} pattern vs %Duration{} value
match?(~o[P1Y6M], today)         #=> false  — %Duration{} pattern vs %Tempo{} value
```

## Modifier-driven bindings

Modifier letters after the closing delimiter **bind** the matched value's unit to a same-named variable in the caller's scope. Modifiers are only meaningful on `%Tempo{}` and `%Tempo.Duration{}` values — the shapes with a `:time` keyword list to destructure.

### The modifier alphabet

| Letter | Unit           | Mnemonic                                         |
|--------|----------------|--------------------------------------------------|
| `Y`    | `:year`        | Year                                             |
| `O`    | `:month`       | m**O**nth — `M` is overloaded for minute in ISO  |
| `W`    | `:week`        | Week                                             |
| `D`    | `:day`         | Day                                              |
| `I`    | `:day_of_year` | Ordinal day — I for "day-of-year index"          |
| `K`    | `:day_of_week` | Week**d**ay                                      |
| `H`    | `:hour`        | Hour                                             |
| `N`    | `:minute`      | mi**N**ute — again avoiding the `M` overload     |
| `S`    | `:second`      | Second                                           |

The letters `O` and `N` (not the expected `M` for both month and minute) exist because ISO 8601 uses `M` for both units, and binding one to a variable named `M` in scope would be ambiguous. The modifier alphabet disambiguates by picking less-overloaded letters.

### Single-unit binding

Pick a unit to pull out of the matched value:

```elixir
today = Tempo.new!(year: 2026, month: 4, day: 24)

case today do
  ~o[2026Y]D -> day
end
#=> 24
```

*"Match a Tempo whose year is **2026** and **bind the day** to `day`."*

### Multi-unit binding

Modifiers compose — each letter binds its unit independently. Order inside the sigil is irrelevant: `~o[2026Y]OD` and `~o[2026Y]DO` expand to the same pattern.

```elixir
case today do
  ~o[2026Y]OD -> {month, day}
end
#=> {4, 24}
```

```elixir
point = Tempo.new!(
  year: 2026, month: 6, day: 15,
  hour: 14, minute: 30, second: 45
)

case point do
  ~o[2026Y6M]DN -> {day, minute}
end
#=> {15, 30}
```

*"On **this point in 2026-06**, bind the **day** and the **minute** — we don't care about the hour or the second for this clause."*

### Binding in combination with prefix matching

A unit can appear in both the sigil *and* a modifier — but not the same unit twice. Use the sigil to fix a value; use modifiers to bind the remaining units:

```elixir
case point do
  ~o[2026Y6M15DT14H30M]S -> second
end
#=> 45
```

### Missing units fall through

A modifier that targets a unit the matched value doesn't carry simply fails to match; the case falls through to the next clause. This makes resolution-agnostic matching natural:

```elixir
year_only = Tempo.new!(year: 2026)

case year_only do
  ~o[2026Y]D -> {:got_day, day}
  ~o[2026Y]O -> {:got_month, month}
  ~o[2026Y]  -> :year_only
end
#=> :year_only
```

*"Does the value have a **day**? No. A **month**? No. It's **year-only** — take the fallthrough."*

## Calendar axes

The modifier set you name determines which calendar *axis* the pattern is laid out against:

* **Gregorian** — `:year → :month → :day → :hour → :minute → :second`. The default. Any combination of `Y O D H N S` lands on this axis.

* **ISO Week** — `:year → :week → :day_of_week → :hour → :minute → :second`. Named by any combination of `Y W K H N S`.

* **Ordinal** — `:year → :day_of_year → :hour → :minute → :second`. Named by any combination of `Y I H N S`.

Mixing axes is an expansion-time error:

```elixir
~o[2026Y4M]W   # ArgumentError: Gregorian month + ISO week
```

The axis is inferred from the union of units named by the sigil string *and* the modifiers — the builder picks the single axis that covers every unit requested, then fills in wildcards for positions between the earliest and latest unit. You never have to declare the axis explicitly; naming compatible units is enough.

## Matching containers

The sigil also expands to a structural pattern when the parsed value is a container: `%Tempo.Interval{}`, `%Tempo.Range{}`, or `%Tempo.Set{}`. Each endpoint is itself prefix-matched using the rules above, so `~o"2022Y"` as an endpoint matches any Tempo whose `:time` starts with year 2022.

### Intervals

Container patterns constrain only fields the sigil string names. `:from` and `:to` are always constrained; `:duration`, `:recurrence`, `:direction`, and `:repeat_rule` are only constrained when they differ from their struct defaults. This means `~o[1984Y/2004Y]` doesn't accidentally require `:metadata => %{}` or some default recurrence.

```elixir
import Tempo.Sigils

{:ok, closed}  = Tempo.from_iso8601("1984Y/2004Y")
{:ok, open_up} = Tempo.from_iso8601("1984/..")
{:ok, dur_iv}  = Tempo.from_iso8601("P1D/2022-01-01")

match?(~o[1984Y/2004Y], closed)     #=> true
match?(~o[1984Y/..], closed)        #=> false  — closed vs open
match?(~o[1984Y/..], open_up)       #=> true
match?(~o[../..], open_up)          #=> false
match?(~o[P1D/2022-01-01], dur_iv)  #=> true
```

*"A **closed** interval doesn't match an **open-ended** pattern — the `:to` endpoint disagrees."*

### Sets

`%Tempo.Set{}` patterns constrain the set's type (`:one` for `[a, b, c]` disjunctions vs `:all` for `{a, b, c}` conjunctions), the member count, and each member's shape in order.

```elixir
{:ok, one_of} = Tempo.from_iso8601("[1984,1986,1988]")
{:ok, all_of} = Tempo.from_iso8601("{1960,1961-12}")

match?(~o"[1984Y,1986Y,1988Y]", one_of)  #=> true
match?(~o"{1960Y,1961Y12M}", all_of)     #=> true
match?(~o"{1984Y,1986Y,1988Y}", one_of)  #=> false — :one ≠ :all
```

Sets whose literal text begins with `[` or `{` collide with the `~o[…]` and `~o{…}` sigil delimiters — use the string-delimited form `~o"…"` for them.

Member count is load-bearing: a sigil set with three members never matches a value with two or four. Members are matched in source order.

### Ranges

`%Tempo.Range{first: _, last: _}` values are matched structurally whether they appear at the top level or nested inside a `%Tempo.Set{}`. Each boundary follows the same endpoint-prefix rules as interval endpoints.

### Modifiers don't apply to containers

A container value has no single `:time` keyword list to destructure — the sigil string describes *which* endpoint is which, not a single unit stream. Using a modifier on a container pattern raises `ArgumentError` at expansion time:

```elixir
~o[1984Y/2004Y]D   # ArgumentError: modifiers not supported on Tempo.Interval
```

Reach into an endpoint manually when you need a binding:

```elixir
case interval do
  ~o[1984Y/..] ->
    %Tempo.Interval{from: ~o[1984Y]D = from} = interval
    from.time[:day]
end
```

*"Recognise an **open-ended interval from 1984**, then **destructure** its `:from` endpoint to bind the day."*

## Guards

Patterns from `~o"…"` cannot appear in a `when` clause. Elixir guards have a constrained set of allowed expressions, and the macro expansion used here isn't one of them. The sigil detects the `:guard` context and raises a clear `ArgumentError` — use a preceding `match?/2` or an `==` comparison instead.

```elixir
# Not allowed — raises ArgumentError at compile time:
def summer?(t) when match?(~o"2026Y6M", t), do: true   # ✗

# Use a preceding match clause:
def summer?(t) do
  match?(~o"2026Y6M", t)                               # ✓
end

# Or a direct comparison when you actually want equality, not
# prefix matching:
def exactly_june_2026?(t), do: t == ~o"2026Y6M"        # ✓
```

## Expansion-time errors

The following raise `ArgumentError` when the sigil is expanded — errors surface at compile time, not during the match:

* **Unknown modifier letter.** `~o[2026Y]X` — `X` isn't in the modifier alphabet.

* **Modifier targets a unit already fixed by the sigil.** `~o[2026Y]Y` — the sigil already names `:year`, so binding it again is ambiguous.

* **Mixing calendar axes.** `~o[2026Y4M]W` — Gregorian month plus ISO week, or `~o[2026Y]IW` — ordinal day-of-year plus ISO week.

* **Modifiers on container sigils.** `~o[1984Y/2004Y]D` — containers don't have a single `:time` to destructure.

* **Guard context.** Any `~o"…"` inside a `when` clause.

All these errors name the specific violation and point at the expression in the caller's source — they don't surface as opaque BEAM patterns-don't-match failures.

## What match context deliberately doesn't do

* **No calendar modifier.** In value context, `~o"…"W` parses the string against the ISO Week calendar. In match context, `W` always means "bind `:week`". Match-context sigils are always parsed as Gregorian and leave the matched value's `:calendar` field unconstrained.

* **No stdlib types.** `~o"…"` produces a `%Tempo{}`-family pattern and cannot match `%Date{}`, `%Time{}`, `%NaiveDateTime{}`, or `%DateTime{}`. Use the stdlib sigils `~D` / `~T` / `~N` / `~U` for those, or convert via `Tempo.from_elixir/1` before matching.

* **No complex time elements.** Groups (`5G10DU`), selections (`L1KN`), ranges (`{1..3}M`), margin-of-error tuples (`2022?+/-1Y`), and continuations aren't expressible as static Elixir patterns. Attempting to use a sigil that contains them in match context raises `ArgumentError` at expansion time.

## Pipeline-prose examples

The following recipes show match context in idiomatic use.

### Day-of-week dispatch on calendar dates

```elixir
import Tempo.Sigils

handle = fn date ->
  case date do
    ~o[2026Y]K when day_of_week in 1..5 -> :workday
    ~o[2026Y]K                          -> :weekend
  end
end
```

Oh wait — that's **not legal** (match-context sigil inside a guard). Written correctly with a split clause body:

```elixir
handle = fn date ->
  case date do
    ~o[2026Y]K ->
      if day_of_week in 1..5, do: :workday, else: :weekend
  end
end
```

*"Recognise any 2026 date, **bind its day-of-week**, then classify."*

### Endpoint-scoped year filtering on an interval list

```elixir
import Tempo.Sigils

published_in_1984? = fn
  %Tempo.Interval{} = iv ->
    match?(~o[1984Y/..], iv)
end

[~o"1984Y/1985Y", ~o"1990Y/1991Y", ~o"1984Y10M/1985Y3M"]
|> Enum.filter(published_in_1984?)
#=> [~o"1984Y/1985Y", ~o"1984Y10M/1985Y3M"]
```

*"An interval **was published in 1984** if its `:from` endpoint **starts with year 1984** and its `:to` endpoint is anything."*

### Precision-specific handlers

```elixir
import Tempo.Sigils

describe = fn tempo ->
  case tempo do
    ~o[2026Y]S -> "precise to the second: #{second} past the minute"
    ~o[2026Y]N -> "precise to the minute: #{minute}"
    ~o[2026Y]H -> "precise to the hour: #{hour}"
    ~o[2026Y]D -> "precise to the day: #{day}"
    ~o[2026Y]O -> "precise to the month: #{month}"
    ~o[2026Y]  -> "year only"
  end
end
```

*"Match the **most specific** resolution the value carries, and narrate it."*

The cases fall through in source order; each attempts to bind its named unit, and the first one whose unit is actually present wins.
