# Dating under uncertainty

Historical and archaeological dates are rarely crisp. A radiocarbon sample gives "around 1200, give or take sixty years"; a regnal date is "circa 600 BCE". ISO 8601-2 writes that uncertainty with a **margin of error** — `1200±60` — and Tempo parses it, carries it, and lets you ask *graded* questions about it: not just "do these overlap?" but "*could* they overlap, and *must* they?".

## The margin is carried, not guessed

A `±` value is a first-class Tempo value. It round-trips, it survives arithmetic, and — importantly — it does **not** silently widen your bounds:

```elixir
import Tempo.Sigils

~o"1200±60Y"                      #=> ~o"1200±60Y"        # round-trips
Tempo.shift(~o"1200±60Y", ~o"P5Y") #=> ~o"1205±60Y"       # the margin travels along
```

The crisp span of `1200±60` is exactly the span of `1200` — the `±60` is metadata about *where that span sits*, not a wider span. So the exact interval algebra stays exact, and the uncertainty only speaks up when you ask a graded question.

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
Tempo.possibly_overlaps?(hearth, midden)                #=> true
Tempo.certainly_overlaps?(hearth, midden)               #=> false
Tempo.overlap_certainty(hearth, midden)                 #=> :possible

Tempo.relation_certainty(hearth, later_wall, :precedes) #=> :certain
Tempo.certainly_within?(hearth, occupation)             #=> true
```

> *"The hearth and the midden **might** be contemporary, but the dates aren't tight enough to be sure. The hearth is **certainly** earlier than the later wall, and **certainly** falls within the site's occupation."*

That callout is the whole point: each line reads as a sentence a historian would actually say.

## What the three verdicts mean

A margin widens each endpoint into a range of where it could really sit. A relation is then:

* **`:certain`** — it holds for *every* placement consistent with the margins.

* **`:possible`** — it holds for *some* placements but not all.

* **`:impossible`** — it holds for *no* placement.

`overlap_certainty/2` and `within_certainty/2` are the three-valued counterparts of `overlaps?/2` and `within?/2`; `relation_certainty/3` asks about any Allen relation (or list of them); and the `certainly_*?`/`possibly_*?` predicate pairs read the verdict off as a boolean when that is all you need.

## Crisp dates fall back to yes and no

When neither operand carries a margin there is only one possible placement, so a graded relation collapses to the ordinary predicate — `:possible` never arises:

```elixir
Tempo.certainly_overlaps?(~o"2000Y", ~o"2000Y")  #=> true    # == Tempo.overlaps?/2
Tempo.certainly_overlaps?(~o"2000Y", ~o"2001Y")  #=> false
Tempo.overlap_certainty(~o"2000Y", ~o"2001Y")    #=> :impossible
```

So you can reach for the graded verdicts everywhere and pay nothing on crisp data.

## Underspecification is uncertainty too

A margin is not the only way a date is vague. ISO 8601-2 also lets a value leave digits **unspecified** — `~o"20XXY"` is *some* year in 2000–2099, `~o"2020YXXM"` *some* month of 2020 — and a value may be **un-anchored**, carrying a month or day with no year at all. Tempo reads these the same three-valued way, over the set of dates the value could actually be:

```elixir
# "Some year in 2000–2099" — certainly within that span, but not every
# grounding survives a window that opens a year later.
Tempo.certainly_within?(~o"20XXY", ~o"2000Y/2100Y")   #=> true
Tempo.within_certainty(~o"20XXY", ~o"2001Y/2101Y")    #=> :possible

# A masked year may precede a date inside its span, or follow it.
Tempo.relation_certainty(~o"20XXY", ~o"2050Y", :precedes)  #=> :possible
Tempo.certainly_before?(~o"20XXY", ~o"2200Y")              #=> true
```

> *"A find dated only to 'the 2000s' is certainly within 2000–2100, only possibly before 2050, and certainly before 2200."*

Un-anchored values — a recurring month or day with no year — compare on a **shared leading unit**, the same-axis rule the set operations use:

```elixir
Tempo.certainly_before?(~o"1M31D", ~o"3M15D")   #=> true
```

> *"The 31st of January is before the 15th of March in any year."*

Comparing across resolution axes — an un-anchored month against an anchored year — has no answer without knowing the year, so Tempo says so rather than guess:

```elixir
Tempo.within_certainty(~o"2M", ~o"2050Y")
#=> {:error, %Tempo.RequiresAnchorError{}}
```

## What this is not (yet)

The verdicts are three-valued, not numeric — Tempo will tell you an overlap is *possible*, but not that it is "70% likely". A probability needs a prior over where the true date sits, and a soft, fades-at-the-edges *approximately* needs a membership function; both are planned for a companion library rather than the crisp core. For today, `±` is inert in your bounds and your exact relations, and speaks only through the graded questions above.
