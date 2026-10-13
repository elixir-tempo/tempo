# Dating under uncertainty

Historical and archaeological dates are rarely crisp. A radiocarbon sample gives "around 1200, give or take sixty years"; a regnal date is "circa 600 BCE". ISO 8601-2 writes that uncertainty with a **margin of error** — `1200±60` — and Tempo parses it, carries it, and lets you ask *graded* questions about it: not just "do these overlap?" but "*could* they overlap, and *must* they?".

## The margin is carried, not guessed

A `±` value is a first-class Tempo value. It round-trips, it survives arithmetic, and — importantly — it does **not** silently widen your bounds:

```elixir
import Tempo.Sigils
```

```elixir
# It round-trips
iex> ~o"1200±60Y"
~o"1200±60Y"

# The margin travels along
iex> Tempo.shift(~o"1200±60Y", ~o"P5Y")
{:ok, ~o"1205±60Y"}

# It is one year long, wherever that year sits
iex> Tempo.duration(~o"1200±60Y")
~o"P1Y"
```

`1200±60` is one year, and the `±60` says where that year may sit: any of the years from 1140 to 1260. The value is a year long whichever it is, and the uncertainty speaks when you ask a graded question.

## Certain, possible, impossible

Every graded relation answers three-valued. Take a dig with two radiocarbon-dated contexts, a clearly later wall, and the site's known occupation span:

<!-- guides:run -->

```elixir
hearth     = ~o"1200±60Y"   # a hearth, dated to ~1200, give or take 60 years
midden     = ~o"1240±40Y"   # a midden, ~1240 ± 40
later_wall = ~o"1500±20Y"   # a wall, clearly later, ~1500 ± 20
occupation = ~o"1000/1500"  # the site was occupied 1000–1500
```

Now ask the questions a site director would ask:

```elixir
iex> Tempo.possibly?(:overlaps, hearth, midden)
true

iex> Tempo.certainly?(:overlaps, hearth, midden)
false

iex> Tempo.certainty(:overlaps, hearth, midden)
:possible

iex> Tempo.certainty(:before, hearth, later_wall)
:certain

iex> Tempo.certainly?(:within, hearth, occupation)
true
```

> *"The hearth and the midden **might** be contemporary, but the dates aren't tight enough to be sure. The hearth is **certainly** earlier than the later wall, and **certainly** falls within the site's occupation."*

That callout is the whole point: each line reads as a sentence a historian would actually say.

## What the three verdicts mean

A margin gives a value a set of **readings**, the places it could really sit. A relation is then:

* **`:certain`** — it holds for *every* reading.

* **`:possible`** — it holds for *some* readings but not all.

* **`:impossible`** — it holds for *no* reading.

`Tempo.certainty/3` takes the question as its first argument: one of the everyday predicates (`:overlaps`, `:within`, `:contains`, `:before`, `:after`, `:adjacent`, `:disjoint`, `:equal`) or one of Allen's thirteen relations (`:precedes`, `:meets`, `:during`, …). `Tempo.certainly?/3` and `Tempo.possibly?/3` read the verdict off as a boolean when that is all you need.

## Crisp dates fall back to yes and no

When neither operand carries a margin there is only one possible placement, so a graded relation collapses to the ordinary predicate — `:possible` never arises:

```elixir
iex> Tempo.certainly?(:overlaps, ~o"2000Y", ~o"2000Y")
true

iex> Tempo.certainly?(:overlaps, ~o"2000Y", ~o"2001Y")
false

iex> Tempo.certainty(:overlaps, ~o"2000Y", ~o"2001Y")
:impossible
```

So you can reach for the graded verdicts everywhere and pay nothing on crisp data.

## Underspecification is uncertainty too

A margin is not the only way a date is vague. ISO 8601-2 also lets a value leave digits **unspecified** — `~o"20XXY"` is *some* year in 2000–2099, `~o"2020YXXM"` *some* month of 2020 — and a value may be **unanchored**, carrying a month or day with no year at all. Tempo reads these the same three-valued way, over the set of dates the value could actually be:

```elixir
# "Some year in 2000–2099" is certainly within that span, but not every
# reading survives a window that opens a year later.
iex> Tempo.certainly?(:within, ~o"20XXY", ~o"2000Y/2099Y")
true

iex> Tempo.certainty(:within, ~o"20XXY", ~o"2001Y/2100Y")
:possible

# A masked year may be before a date inside its span, or after it.
iex> Tempo.certainty(:before, ~o"20XXY", ~o"2050Y")
:possible

iex> Tempo.certainly?(:before, ~o"20XXY", ~o"2200Y")
true
```

> *"A find dated only to 'the 2000s' is certainly within 2000 to 2099, only possibly before 2050, and certainly before 2200."*

Values with no year — a month or a day of any year — are compared on the cycle they share, as the set operations compare them:

```elixir
iex> Tempo.certainly?(:before, ~o"1M31D", ~o"3M15D")
true
```

> *"The 31st of January is before the 15th of March in any year."*

A month of no year against a year has no answer without knowing the year, so Tempo says so rather than guess:

```elixir
iex> {:error, %Tempo.FrameError{reason: :needs_a_year}} = Tempo.certainty(:within, ~o"2M", ~o"2050Y")
```

## What this is not (yet)

The verdicts are three-valued, not numeric — Tempo will tell you an overlap is *possible*, but not that it is "70% likely". A probability needs a prior over where the true date sits, and a soft, fades-at-the-edges *approximately* needs a membership function; both are planned for a companion library rather than the crisp core. For today, `±` speaks through the graded questions above.
