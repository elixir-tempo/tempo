Another recipe from the interval-sets-not-instants files. This one is for everyone who carries a pager.

### The rotation that looks fair

Three engineers rotate on-call weekly, handing over each Monday, thirteen weeks a quarter. Five weeks for Alice, four each for Bob and Carol — as close to fair as thirteen divides by three. Shift counts are what rota tools display, so that's what gets eyeballed for fairness.

But shift count isn't what on-call *costs*. Weekends are. And the weekend arithmetic is exactly the kind of thing nobody checks by hand.

### Weekend burden per engineer

Here's the recipe. Each engineer's rotation is **one sigil** — a set of explicit week intervals:

```elixir
import Tempo.Sigils

alice = ~o"{2025-12-29/2026-01-05,2026-01-19/2026-01-26,2026-02-09/2026-02-16,2026-03-02/2026-03-09,2026-03-23/2026-03-30}"
bob   = ~o"{2026-01-05/2026-01-12,2026-01-26/2026-02-02,2026-02-16/2026-02-23,2026-03-09/2026-03-16}"
carol = ~o"{2026-01-12/2026-01-19,2026-02-02/2026-02-09,2026-02-23/2026-03-02,2026-03-16/2026-03-23}"

for {name, rota} <- [alice: alice, bob: bob, carol: carol] do
  {:ok, weekend_days} = Tempo.select(rota, Tempo.weekends(:US))
  {name, Tempo.IntervalSet.count(weekend_days)}
end
*#=> [alice: 10, bob: 8, carol: 8]*
```

Ten weekend days for Alice against eight — **240 hours of weekend pager duty against 192**. A rotation that reads 5/4/4 by shift count is carrying a 25% weekend skew, and it will stay skewed until the quarter boundary rotates the phase.

### Walkthrough of the recipe

Two Tempo ideas do the work: a `{a/b,c/d,…}` sigil is a *set of intervals* (Alice's five separate weeks are one value, not five variables), and `Tempo.select/2` applies a selector across every member of a set.

```elixir
# Each on-call stint is an explicit half-open interval — Monday to
# Monday. The braces make the five stints a single set-of-intervals
# value. No structs, no lists, no loop.
iex> alice = ~o"{2025-12-29/2026-01-05,2026-01-19/2026-01-26,2026-02-09/2026-02-16,2026-03-02/2026-03-09,2026-03-23/2026-03-30}"

# `Tempo.weekends/1` derives the weekend for a territory from CLDR
# data, the same way `Tempo.workdays/1` does — Saturday and Sunday
# for :US, Friday and Saturday for :SA, and so on.
iex> Tempo.weekends(:US)
~o"{6,7}K"

# `select` materialises the rota and picks, from every member week,
# the days matching the selector. Alice's five weeks flatten to ten
# weekend days:
iex> {:ok, weekend_days} = Tempo.select(alice, Tempo.weekends(:US))
iex> weekend_days
#Tempo.IntervalSet<[~o"2026Y1M3D/4D", ~o"2026Y1M4D/5D", ~o"2026Y1M24D/25D", ~o"2026Y1M25D/26D", …]>

# Each member is exactly one day, so counting members is counting
# weekend days on call.
iex> Tempo.IntervalSet.count(weekend_days)
10
```

From here the variations are one-liners: swap `Tempo.weekends(:US)` for a list of night hours to audit night burden; `Tempo.members_outside(rota, holidays)` to see who kept getting the public-holiday weeks (the same move as the [Business/252 recipe](https://ex-tempo.hexdocs.pm/cookbook.html#business-252-brazil-s-business-day-year-fraction)); or `Tempo.intersection/2` between two engineers' rotations to prove a handover overlap.

### Trying this at home

* The recipe in the cookbook: https://ex-tempo.hexdocs.pm/cookbook.html#is-the-on-call-rotation-fair
* `Tempo.select/2` and the selector vocabulary: https://ex-tempo.hexdocs.pm/Tempo.Select.html
