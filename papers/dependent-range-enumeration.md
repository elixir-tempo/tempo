# Enumerating a dependent product: multi-range, multi-position date expansion

How Tempo expands a date literal in which several components are set-valued — `{2000..2010}Y{1..-1}M{1..-1}D`, "every day of every month of eleven years" — and why the obvious implementation, an odometer, cannot do it.

## TL;DR

A date whose components are ranges is not a cartesian product. It is a **dependent** product: the domain of each component is a function of the values chosen for the components to its left. How many months are in a year depends on *which* year (twelve in Gregorian, thirteen in a Hebrew leap year). How many days are in a month depends on which year *and* which month.

* An **odometer** — the natural implementation, one wheel per component with carry — assumes fixed wheel sizes. Making a wheel's size depend on the wheels to its left forces the odometer to consult its own previous reading to reset a wheel, and with two or more dependent wheels that definition becomes circular. Tempo's odometer terminated with one such wheel and did not converge with two.
* A **recursive descent over the dependent product** has no such problem. Walking components coarse-to-fine means every ancestor is already concrete when a component's domain is needed, so the domain is always computable. Depth-first traversal emits members in chronological order with no sort.
* The domain function is **not a table**. It is the library's ordinary validator, called on a partial value. Calendar knowledge stays in one place, so a Hebrew leap year's thirteenth month appears without the expander knowing that Hebrew calendars exist.
* Resolution is **two-phase**: parse time bounds a component by the widest domain it could ever have; expansion time resolves it exactly against the domain it actually has. The two phases answer different questions — *could this ever exist?* and *does this exist here?*

## 1. The shape of the problem

Write a value as an ordered list of components $c_1 \ldots c_n$, coarse to fine — year, month, day, hour. Each component carries a *spec*: a single integer, a list, or a range, and a range bound may be negative, counting back from the end of whatever contains it (ISO 8601-2 §4.4.1, so `-1` is "last").

If every spec denoted a fixed set, expansion would be an ordinary cartesian product and any product algorithm would do. It does not. The set a spec denotes is a function of its context:

$$\mathrm{dom}(c_i) = f_i(v_1, \ldots, v_{i-1})$$

`{1..-1}M` denotes twelve values under a Gregorian year and thirteen under a Hebrew leap year. `{1..-1}D` denotes 28, 29, 30 or 31 values depending on both the year and the month above it. Even a *concrete* spec is context-dependent in its validity: day 29 exists in February 2020 and not in February 2021.

This is the difference between a rectangle and a tree. The members are the leaves of a tree whose branching factor at each level is decided by the path taken to reach it.

## 2. Why the odometer fails

The obvious way to enumerate a product is an odometer: hold a reading, advance the rightmost wheel, and when it passes its last value reset it to its first and carry into the wheel on its left.

This is correct when wheel sizes are constant, and it is attractive because it is lazy — the state is one reading, and the next member costs O(1) amortised. Tempo used one, and its wheels were allowed to be dependent: a wheel with an open range (`1..-1`) resolved its bounds when it was reset, by inspecting the reading it was resetting *within*.

That inspection is the flaw. Resetting wheel $i$ requires the values of wheels $1 \ldots i-1$, which is fine; but the reset happens *during* the carry that is itself updating those wheels, so the reset consults a reading that is mid-update. With one dependent wheel the sequencing happens to work out. With two — a month range and a day range both open — resolving the day wheel needs the month, resolving the month wheel needs the year, and the carry that produced the new month has not finished. The mutual recursion between "advance" and "resolve bounds by looking at the previous reading" has no base case, and the enumeration does not converge.

The bug is not a coding slip that a careful patch would fix. It is that the odometer's state — a single reading plus per-wheel bounds — is the wrong state for a dependent product. The bounds are not a property of a wheel; they are a property of a *path*.

## 3. Recursive descent over the dependent product

Make the path the state, and the difficulty disappears:

```
expand([], chosen)           = [ value(chosen) ]
expand([cᵢ | rest], chosen)  = for v in domain(cᵢ, chosen):
                                   expand(rest, chosen ++ [v])
```

Because components are visited coarse-to-fine, everything `domain/2` needs — every value to the left — is already fixed and concrete by the time it is called. There is no mid-update reading to consult, no mutual recursion, and termination is immediate: each call consumes one component from a finite list, and each domain is a finite set.

Two properties fall out of the traversal rather than being engineered:

* **Chronological order.** Components are ordered coarse-to-fine and each domain is enumerated ascending, so depth-first pre-order visits leaves in lexicographic order on $(v_1, \ldots, v_n)$ — which, for date components ordered by significance, *is* time order. No sorting step, and none of the sorting-across-calendars questions a sort would raise.
* **Distinctness.** Distinct paths give distinct tuples, so no member can be emitted twice, and no deduplication pass is needed.

## 4. The domain function is the validator

The interesting part is what `domain/2` is. The temptation is a table of unit lengths, or a `days_in_month/2` special case per calendar. Tempo does neither. It builds a *partial* value — the ancestors already chosen, plus this component's spec — and hands it to `Tempo.Validation.validate/2`, the same function that resolves a scalar literal at parse time:

```elixir
# "every day of February 2024" — a leap year, so 29
{:ok, days} = Tempo.Validation.validate(%Tempo{time: [year: 2024, month: 2, day: 1..-1//1], calendar: Calendrical.Gregorian}, Calendrical.Gregorian)
days.time
#=> [year: 2024, month: 2, day: 1..29]

# "every month of 5784" — a Hebrew leap year, so 13
{:ok, leap} = Tempo.Validation.validate(%Tempo{time: [year: 5784, month: 1..-1//1], calendar: Calendrical.Hebrew}, Calendrical.Hebrew)
leap.time
#=> [year: 5784, month: 1..13]

# and 5785, a common year, so 12
{:ok, common} = Tempo.Validation.validate(%Tempo{time: [year: 5785, month: 1..-1//1], calendar: Calendrical.Hebrew}, Calendrical.Hebrew)
common.time
#=> [year: 5785, month: 1..12]
```

Calendar knowledge therefore lives in exactly one place. The expander contains no notion of leap years, month lengths, or thirteenth months; it asks, and the calendar answers. A calendar Tempo has never seen expands correctly provided it implements the same callbacks a scalar literal already requires.

### Two kinds of extent

Not every component is dependent. An hour always has sixty minutes; a week always has seven days. These units have a **context-free extent**, and the distinction matters more than it first appears, because it decides *when* a count-from-the-end bound can be resolved:

* **Context-dependent extent** (`:month`, `:day`, `:week`, `:day_of_year`) — `{1..-1}` cannot be resolved until the year, and often the month, is concrete. Resolution must wait for expansion.
* **Context-free extent** (`:hour`, `:minute`, `:second`, `:day_of_week`) — `{0..-1}` can be resolved immediately, because no ancestor changes the answer.

Conflating the two is a quiet trap. If the context-free units are *also* left to expansion, an unresolved `1..-1` survives into the walk, where an inverted range enumerates to the empty list — and a value that should have produced sixty members produces none, silently. That is strictly worse than the non-termination it replaces: a hang is at least visible.

So resolution of the context-free units belongs at validation, alongside the scalar form (`T-1M` has always parsed as minute 59), and the expander asserts the invariant rather than repairing it: a count-from-the-end bound reaching the walk raises, because by then it can only be a bug.

The validator returns one of three outcomes, and each has a distinct meaning for expansion:

| Outcome | Meaning | Expansion |
| --- | --- | --- |
| `{:ok, resolved}` | the spec's values in this context | enumerate them |
| `{:error, …, valid_range: r}` on a range | the range overruns this context | clip to `r`, enumerate the rest |
| `{:error, …}` on a single value | this value cannot exist here | drop — not an occurrence |

The third row is set semantics, and it is what both ISO 8601-2 and RFC 5545 already prescribe for recurrence expansion: invalid dates are ignored rather than raised. The second row is the same principle applied to a range that partly fits — `{28..31}D` is four days in October and three in September.

## 5. Two phases, two questions

A subtlety appears when the *context itself* is not yet concrete. Consider `{2020,2021}Y2M{1..-1}D` — a set of years, February, every day. At parse time the year is not a single value, so February's length is genuinely unknown; the day range cannot be resolved. Refusing is tempting, and Tempo did refuse, which made the value unrepresentable.

The resolution is to separate two questions that had been conflated:

* **Parse time asks: could this exist in *some* context?** February's day range is bounded by 29 — the maximum over all years. `2M30D` is rejected here, because no February has a thirtieth; `2M{1..-1}D` is admitted, bounded at 29.
* **Expansion time asks: does this exist in *this* context?** With the year concrete, 2020 yields 29 days and 2021 yields 28.

Parse-time validation is thus a *soundness filter over the union of possible contexts*, and expansion-time resolution is *exact within one context*. Neither can do the other's job: the parser cannot know which February, and the expander should not have to re-litigate whether a February thirtieth is conceivable.

This also settles a question that looks like an inconsistency and is not. A day set overflowing a *concrete* month is rejected outright, because a concrete month's length is known whatever the year:

```elixir
Tempo.from_iso8601("2026Y9M{28..31}D")
#=> {:error, %Tempo.InvalidDateError{value: 31, valid_range: 1..30}}
#   September has no 31st, in any year

Tempo.from_iso8601!("2026Y{9..10}M{28..31}D") |> Tempo.to_interval()
#=> September 28, 29, 30 and October 28, 29, 30, 31
#   the month varies, so the set clips per member
```

The same literal is an error in a determined context and a clip in a varying one, because in the first case the user has written something that cannot happen, and in the second they have written something that happens differently in each member.

## 6. Cost

Domain resolution happens once per *interior node*, not once per leaf. For `{2000..2010}Y{1..-1}M{1..-1}D`: one resolution for the year range, eleven for the month ranges (one per year), and 132 for the day ranges (one per year-month). Tracing the validator during expansion counts exactly those 144 resolutions, producing 4018 members — 144 rather than 4018, because the cost attaches to the branching, not to the leaves. The whole call, including materialising every member into an interval, runs in 3–4 ms warm.

The honest trade-off against the odometer is **laziness**. The odometer streams: it holds one reading and can be halted after three members without computing the fourth. The descent as implemented is eager, materialising the full member list, which is right for the bounded values it handles and wrong for a value with an unbounded component. Tempo keeps both — shapes the descent does not cover (masks, `:any`, groups, selections) still use the odometer — and the descent's recursion is structurally a `flat_map`, so making it lazy is a change of combinator rather than of algorithm.

## 7. Testing a dependent product

A property test for this must be careful about two things: its oracle, and its coverage.

The **oracle** must be independent. Checking the expander against Tempo's own calendar functions would be checking the implementation against itself; the interesting failures are exactly those where the expander and the calendar disagree. So the reference is computed with plain `Date` arithmetic and the clock units' own extents:

* Generate a spec per position — single, list, range, or open-ended `{n..-1}`.
* Render the specs to an ISO 8601 string *and* resolve them to an expected list independently.
* Assert that materialisation and enumeration each produce exactly that list, in time order, without duplicates.

The **coverage** must span every position. A first version of this property generated only year, month and day — and passed, while set-valued *clock* components silently expanded to nothing. The bug lived in the positions the generator never visited, which is the ordinary failure mode of property tests: they are only as good as their generators' reach. The version that found it walks the whole component chain, year through second, with the week and ordinal axes in their own properties.

A separate property fixes the year and asserts per-month counts against the calendar, so a leap February is checked as 29 and a common one as 28 without either number appearing in the test.

The two-path assertion earns its place: a value that materialises one way must enumerate the same way, and before this work the two paths were separate implementations that could — and did — disagree.

## 8. What generalises

Nothing here is specific to dates. The pattern is: *enumerate a product whose factor domains depend on the choices already made*, and it recurs wherever a structure is both ordered and context-sensitive — configuration matrices with dependent options, generated test-case spaces, schema-driven form permutations.

The three transferable lessons:

1. **If a factor's domain depends on earlier factors, make the path the state.** Odometer state (a reading plus per-factor bounds) cannot express bounds that belong to a path.
2. **Get the domain from the system's own validator, not a table.** The validator already knows the rules, is already tested, and cannot drift from itself.
3. **Separate "possible anywhere" from "valid here".** They are different predicates, they belong to different phases, and conflating them either rejects representable values or admits impossible ones.

## References

* ISO 8601-2:2019 §4.4.1 — negative components counting from the end of the containing unit.
* RFC 5545 §3.3.10 — recurrence expansion; invalid dates are ignored rather than raised.
* Implementation: `Tempo.Enumeration.expand/1`, with the deferral rule in `Tempo.Validation.resolve/2` and the property test in `test/tempo/range_expansion_property_test.exs`.
