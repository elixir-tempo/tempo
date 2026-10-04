# Enumeration semantics

Tempo implements the `Enumerable` protocol for `%Tempo{}`, `%Tempo.Set{}`, and `%Tempo.Interval{}`. This document explains what each value can and cannot be iterated over, and why.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

## 1. The two kinds of iteration

Tempo values are **bounded intervals on the time line**, not instants. That informs two distinct iteration modes, each produced by a different shape of value:

* **Implicit enumeration — "drill into this span."** A single `%Tempo{}` at some resolution yields its sub-units. `Enum.take(~o"2022Y", 3)` yields `[2022Y1M, 2022Y2M, 2022Y3M]` — the year span is walked one month at a time. Implicit enumeration is the default when the value is a single resolved point at a coarser-than-finest resolution.

* **Forward-stepping — "walk across this interval."** A `%Tempo.Interval{}` yields each resolution-unit along the span. `Enum.take(Tempo.Interval.new!(from: ~o"1985Y", to: :undefined), 3)` yields `[1985Y, 1986Y, 1987Y]` — successive years at the endpoint's own resolution.

Iteration always honours the **half-open `[from, to)` convention**: the lower bound is inclusive, the upper bound is exclusive. This makes adjacent intervals concatenate cleanly without overlap or gap.

`Tempo.to_interval/1` converts between the two forms: it takes any implicit-span `%Tempo{}` and returns the equivalent `%Tempo.Interval{}` with concrete `from` and `to` endpoints. Iteration on the explicit form is guaranteed to yield the same sequence as iteration on the implicit source (for every shape where both are defined — see §5.6 for the edge cases). `to_interval/1` is idempotent on values that are already intervals.

## 2. Enumerable — what you can iterate

### 2.1. Single `%Tempo{}` values

Every resolved Tempo at coarser-than-finest resolution is enumerable via implicit enumeration. The iteration unit is the next-finer unit that isn't already specified.

| Construct | Example | Yields |
|---|---|---|
| Year | `2022Y` | 12 months |
| Year-month | `2022-06` | days of June |
| Year-month-day | `2022-06-15` | 24 hours |
| Hour | `2022-06-15T10` | 60 minutes |
| Minute | `2022-06-15T10:30` | 60 seconds |
| Week | `2022-W24` | its 7 days, the dates 13 to 19 June |
| Ordinal date | `2022-166` | 24 hours |

A week's days are the dates they name: `Enum.to_list(~o"2026-W25")` is `~o"2026-06-15"` to `~o"2026-06-21"`, the values a week date is read as (`2026-W25-2` is `~o"2026-06-16"`), so `~o"2026-06-16" in ~o"2026-W25"` is true. A step of days or hours from a week lands on a date too (`Tempo.shift(~o"2026-W25", day: 1)` is `~o"2026-06-16"`), and a step of whole weeks on a week. A calendar of weeks, which has no months, keeps its week and its day of the week (`2026Y25W2K`), and so does a week with no year.

A calendar whose year turns on another day than the first of its first month (Calendrical's Julian `March25`, `March1`, `Sept1` and `Dec25`) starts its year on that day and counts the year's months from it: the first month of a `March25` year is 25 to 31 March and its twelfth 1 February to 24 March, so `1750Y1M` is walked by seven dates and `1750Y12M` by fifty-two. A date there keeps the number its calendar gives its month (`1750Y3M25D`, the first day of 1750), so a month's number is not the month of its dates.

### 2.2. Explicit ranges and sets

Any component may carry a range, a range with step, a set of values, or a cartesian product of the above.

| Construct | Example | Iterates over |
|---|---|---|
| Inclusive range | `{1..3}M` | months 1, 2, 3 |
| Stepped range | `2022Y{1..-1//2}W` | every second week of 2022 |
| All-of set | `{2021,2022}Y` | 2021, then 2022 |
| One-of set | `[1984,1986,1988]` | exactly those three years |
| Cartesian product | `2022Y{1..2}M{1..2}D` | Jan 1, Jan 2, Feb 1, Feb 2 |
| A range in each of a set | `{2026,2027}Y{1..-1}W` | the 53 weeks of 2026, then the 52 of 2027 |

Each component is read after the values before it, so a count from the end (`-1`, the last) is the last of each: `{2026,2027}Y-1D` is 31 December of each year, and `2026Y{1..-1}M{1..-1}D` every day of 2026. A value its context cannot hold is passed over, as RFC 5545 passes over a date that does not exist: `{2023,2024}Y2M29D` is 29 February 2024 alone. The walk is lazy, so `Enum.take/2` of a large set reads only the values it takes.

### 2.3. Recurring intervals

A *bounded* recurring interval enumerates exactly as its converted occurrences do — the walk delegates to `Tempo.to_interval/1`'s `IntervalSet`, yielding the sub-points of every occurrence. `Enum.count(~o"R5/2022-01-01/P1M")` is `151` (the days of January through May), identical to counting the converted set; for the *occurrence* count use `to_interval!/1` and `Tempo.IntervalSet.count/1`. A recurrence written with a start and an end (`R3/2022-01-01/2022-01-08`, whose first occurrence is that week) or a duration and an end (`R3/P1W/2022-01-22`, whose last occurrence ends there) walks the same way. An *unbounded* recurrence (`R/…`) raises `Tempo.UnboundedRecurrenceError` — convert it with `Tempo.to_interval(r, within: …)` first — matching how `relation/2` and `duration/1` refuse recurrences.

### 2.4. Missing / unknown digits (EDTF masks)

A digit marked `X` means "any value in this position", and `X*` an unspecified unit — any value the unit can take. Tempo walks the values the digits allow where the unit stands, after the year, the month or the week before it, so the value is just as enumerable as an explicit set of the same values.

| Construct | Example | Walks |
|---|---|---|
| Last digit unknown (year) | `156X` | `1560..1569` |
| Positive century masked | `1XXX` | `1000..1999` |
| Negative century masked | `-1XXX` | `-1999..-1000`, earliest first |
| Fully unspecified year | `XXXX` | `1000..9999` |
| Month-day masked | `1985-XX-XX` | the 365 days of 1985 |
| Month only masked | `1985-XX-15` | the 15th of each month |
| A day some months lack | `1985-XX-31` | the 31st of the seven months with one |
| Week masked | `2026-W2X` | weeks 20 to 29 of 2026 |
| Day of the week masked | `2026-W25-X` | the seven days of week 25, 15 to 21 June |
| Day of the year masked | `2026Y1XXO` | days 100 to 199 of 2026 |
| Hour masked | `T1XH` | hours 10 to 19 |
| Unspecified month | `2026YX*M` | the 12 months of 2026 |
| Unspecified hour | `TX*H` | hours 0 to 23 |
| Counted from the end | `2026Y-XM` | the last nine months, April to December |

A mask is read in each context it lands in: `1985-XX-3X` is the 30th and 31st of January, then of March, and no day of February. A value none of whose candidates fits (`1985-02-3X`) names no date, as a set none of whose values exists does (`2026Y{2,6}M31D`, where `2026Y{1,2}M31D` is 31 January), and a unit whose values depend on a year the value does not have (`X*W`, the weeks of no year) cannot be listed; walking any of them raises a named error (§3.6). An unspecified year (`X*Y`) is some year and no year in particular, so the units after it are walked as they are with no year written (`X*Y12M28D` is the hours of 28 December, each still of an unspecified year), and on its own it names nothing to list.

### 2.5. EDTF long-year shapes

| Construct | Example | Notes |
|---|---|---|
| `Y`-prefix short year | `Y2022` | same as `2022`; 12 months |
| `Y`-prefix long year | `Y12345` | single anchored year; 12 months |
| Exponent long year | `Y17E8` | 1 700 000 000; single anchored year |
| Significant-digits year | `1950S2` | block `1900..1999`; 100 × 12 months |
| Significant-digits long | `Y171010000S8` | block of 10 candidates |

Significant-digits blocks are capped at **10 000 candidates**. Larger blocks (e.g. `Y171010000S3`, which would be 10⁶ candidates) raise a clear `ArgumentError` — the parsed value is still usable as a data value, you just cannot iterate it.

### 2.6. Groups and selections

| Construct | Example | Behaviour |
|---|---|---|
| Group | `2022Y5G2MU` | "5th group of 2 months": months 9 and 10 |
| Group in a set | `2022Y{2,6}M3G11DU` | days 23 to 28 of February, then 23 to 30 of June |
| Selection | `2022YL1MN` | "the 1st month of 2022": January 2022 |
| Selection of days | `2026Y6ML2KN` | the five Tuesdays of June 2026 |

A group is bounded by what holds it, so the last group of eleven days in February stops at the 28th. A value that holds a selection is walked as the spans `Tempo.to_interval/2` gives it. A group of a set (`2022Y{1,2}G3MU`, the first and the second groups of three months) is walked group by group, its six months in turn, and a unit after it is counted from the start of each group.

### 2.7. Qualifications (EDTF Level 1 and Level 2)

Qualifications describe epistemic state (`?` uncertain, `~` approximate, `%` both) and never affect whether a value is enumerable. A qualifier is held per component (ISO 8601-2 §8), one written after a whole value being each component's, so each yielded value keeps the qualifiers of the components it was walked from, and the unit the walk adds is not qualified.

| Construct | Example | Each yielded value carries |
|---|---|---|
| Whole value | `2022Y?` | an uncertain year (`2022?Y1M`) |
| Leading | `?2022-06-15` | an uncertain year |
| Approximate | `~2022` | an approximate year |
| Component-level | `2022-?06-15` | an uncertain month |
| Mixed components | `2022?-?06-%15` | each component's own |

### 2.8. IXDTF metadata

Time zone and tagged suffixes attach to the `:extended` field, and a calendar suffix names the value's `:calendar`. Each flows through enumeration unchanged.

| Construct | Example |
|---|---|
| Zone only | `2022-06-15T10:30[Europe/Paris]` |
| Calendar only | `2022-06-15T10:30[u-ca=hebrew]` |
| Zone + offset + calendar | `2022-06-15T10:30[+05:30][u-ca=hebrew]` |
| Per-endpoint on interval | `10:00[Europe/Paris]/12:00[Europe/London]` |

The endpoint iteration starts from (`from`) provides the metadata carried on each yielded value.

### 2.9. Intervals — closed and forward-open

| Shape | Example | Iteration |
|---|---|---|
| Closed day | `1985-01-01/1985-01-04` | Jan 1, 2, 3 (half-open) |
| Closed month | `1985-12/1986-02` | Dec 1985, Jan 1986 |
| Closed week | `2022-W05/2022-W08` | W5, W6, W7 |
| Ends of two resolutions | `1985/1986-06` | Jan 1985 to May 1986, by the finer end's unit |
| Ends on two axes | `2026-W25/2026-07-01` | the sixteen days from 15 June, as dates |
| Open upper | `1985/..` | 1985, 1986, 1987, … (use `Enum.take/2`) |
| Open upper, hour | `1985-01-01T10/..` | 10:00, 11:00, 12:00, … |
| No year, round the clock | `T22H/T2H` | 22:00, 23:00, 00:00, 01:00 |
| No year, round the week | `7K/3K` | Sunday, Monday, Tuesday |
| No year, round the year | `12M/2M` | December, January |
| Per-endpoint qualifier | `1984?/2004~` | 1984 through 2003, each carrying its endpoint's qualifier where applicable |

An interval is walked at the highest resolution its boundaries are written to: the finer of its two ends' units, unless it carries a `:unit` of its own. The start is filled down to that unit, and the walk stops at the end, so the values it yields are the interval and none runs past it: `2026/2026-03` is January and February, and `2026-06-15T10/2026-06-16` the fourteen hours to midnight. An interval written with a duration (`2026-06-15/PT36H`) is walked to the end the duration gives, by the finer of the two.

Ends written to different resolutions are compared as their concrete start-moments: missing trailing units fill with their unit minimum (`:month` / `:day` / `:week` from 1, everything else from 0). Ends on different axes (a week and a date), in different zones or in different calendars are compared as the moments they are.

A span with no year lies on an axis that comes round again — the hours of a day, the days of a week, the months of a year — so one that ends before it starts runs off the end of the axis and on to its end. A walk takes a step only when it goes on, so `Enum.take(~o"2M27D/..", 2)` is 27 and 28 February, and the third value, which depends on the year, is an error only when it is asked for.

A walk steps from one point and stops at another. An interval whose start or end holds several values (`{2026,2027}Y/2030Y`, `2026Y/202XY`) cannot be walked (§3.6), and one whose end holds a selection (`2026Y6ML2KN/P1D`) is walked as the spans `Tempo.to_interval/2` gives it.

An interval with no end (`1985/..`) is walked as far as it is asked: `Enum.take/2`, `Enum.take_while/2`, `Enum.find/2` and the `Stream` functions read what they need and stop. It has no count, so `Enum.count/1` raises a `Tempo.IntervalEndpointsError` (§3.6) rather than walk for ever, and so do the functions a slice answers (`Enum.at/2`, `Enum.fetch/2`, `Enum.empty?/1`, `Enum.random/1`, `Enum.slice/2`), which cannot tell a question about the start from one that needs the last value: `Tempo.Interval.empty?/1` says whether it is empty, and `Enum.take/2` gives its first values. A lazy interval set refuses the same. `Enum.member?/2` is answered without the whole walk where the start has a year — `~o"2030Y" in ~o"1985/.."` is true and `~o"1980Y" in ~o"1985/.."` false — and refused, with the same error, where it has none: `T10H/..` comes round the clock for ever and has no order to stop a search by. What walks every value (`Enum.to_list/1`, `Enum.reverse/1`) never returns, as for any stream with no end.

### 2.10. Implicit-to-explicit conversion (`Tempo.to_interval/1`)

Every enumerable `%Tempo{}` has an explicit equivalent — either a single `%Tempo.Interval{}` (contiguous span) or a `%Tempo.IntervalSet{}` (sorted, member-preserving list of intervals). `Tempo.to_interval/1` converts to the appropriate form under the half-open `[from, to)` convention. The conversion preserves every piece of source metadata (`:qualifications`, `:extended`, `:shift`, `:calendar`) on both endpoints.

The bounds keep the **value's own resolution** — *resolution = meaning*, so a day converts to `[day, day+1)`, not as drilled `T0H` endpoints. The iteration granularity of the implicit span (the next-finer unit) travels separately on the interval's **`:unit` field**, and the walk fills its anchor down to that unit at iteration time. So the converted interval enumerates exactly like its implicit twin (`Enum.count` of both `~o"2026-01-15"` and its interval is 24 hours) while its endpoints state only what the source stated. An interval whose `:unit` is set inspects with a decoration — `#Tempo.Interval<~o"2026-01-15/2026-01-16" unit: hour>` — because the unit is non-syntactic state the bare sigil would not round-trip.

Call `Tempo.to_interval_set/1` if you always want the IntervalSet form (a single interval is wrapped in a one-element set).

| Input | `from.time` | `to.time` | `unit` |
|---|---|---|---|
| `2026` | `[year: 2026]` | `[year: 2027]` | `:month` |
| `2026-01` | `[year: 2026, month: 1]` | `[year: 2026, month: 2]` | `:day` |
| `2026-01-15` | `[year: 2026, month: 1, day: 15]` | `[year: 2026, month: 1, day: 16]` | `:hour` |
| `2026-01-15T10` | `[…, hour: 10]` | `[…, hour: 11]` | `:minute` |
| `156X` | `[year: 1560]` | `[year: 1570]` | `nil` (walks years) |
| `-1XXX` | `[year: -1999]` | `[year: -999]` | `nil` |
| `1985-XX-XX` | `[year: 1985]` | `[year: 1986]` | `nil` |
| `1985-06-XX` | `[year: 1985, month: 6]` | `[year: 1985, month: 7]` | `nil` |
| `1985-06-1X` | `[year: 1985, month: 6, day: 10]` | `[year: 1985, month: 6, day: 20]` | `nil` (walks days) |

A `nil` unit means the walk derives its step from the endpoint resolution — the default for user-written explicit intervals (`~o"2026-01-01/2026-02-01"` iterates days) and for masked/grouped values whose widened bounds already sit at the iteration resolution. You can also set the unit yourself: `Tempo.Interval.new(from: ~o"2025-07-04", to: ~o"2025-07-05", unit: :hour)` walks a day-resolution extent at hour granularity.

Mask rules:

* A **year mask** (`156X`, `-1XXX`) translates directly to a year range via `Tempo.Mask.mask_bounds/1`. The signed half-open upper bound is computed as `-magnitude_min + 1` for negative masks.

* A **finer-unit mask** narrows to the values its digits allow in the calendar: `1985-06-1X` is the 10th to the 19th of June, `[1985-06-10, 1985-06-20)`, and `1985-06-3X` the 30th alone. A fully masked unit allows every value, so `1985-XX-XX` is the year and `1985-06-XX` the month, and a mask walks its own unit, as `156X` walks years. An unspecified unit other than the year (`1985Y6MX*D`) is read as a fully masked one: the month. A masked day of the year, written `O` or as a day straight after its year, is the dates it names: `2026Y3XO` and `2026Y3XD` are 30 January to 8 February, `[2026-01-30, 2026-02-09)`.

* Candidates that are not consecutive (`1985-06-X5`, the 5th, 15th and 25th), or a mask with a narrower unit after it (`1985-XX-15`, the 15th of each month; `1985-XX-1X`, the 10th to the 19th of each), are an `IntervalSet` of a span each. A candidate the calendar has no room for drops out, as a set's does (`1985-XX-31` has no February), and a mask none of whose candidates fits (`1985-02-3X`) is an error.

`to_interval/1` is idempotent on existing intervals and interval sets. Multi-valued AST shapes (ranges, stepped ranges, iterated groups, all-of sets) convert to `%Tempo.IntervalSet{}` with each expanded member distinct. One-of sets (`[a,b,c]`) are *epistemic* (the value is one of these, we don't know which) and return an error from `to_interval/1` — flattening them would assert all members happened, which is semantically wrong. Bare `%Tempo.Duration{}` values also return an error (no anchor on the time line).

| Input shape | Result |
|---|---|
| Scalar `~o"2022Y"` | `%Tempo.Interval{}` |
| Contiguous range `~o"2022Y{1..3}M"` | `%Tempo.IntervalSet{}` with 3 members (one per month) |
| Stepped range `~o"2022Y{1..-1//3}M"` | `%Tempo.IntervalSet{}` with N disjoint members |
| All-of set `~o"{2020,2021,2022}Y"` | `%Tempo.IntervalSet{}` with 3 members (one per year) |
| One-of set `~o"[2020Y,2021Y,2022Y]"` | `{:error, "... epistemic disjunction ..."}` |
| Bare Duration `~o"P3M"` | `{:error, "... no place on the time line"}` |

For the canonical instant-set form (touching members merged into one span), pipe the result through `Tempo.IntervalSet.coalesce/1`.

### 2.11. `%Tempo.IntervalSet{}` — multi-interval values

`%Tempo.IntervalSet{intervals: [%Tempo.Interval{}, ...]}` holds a sorted list of member intervals. By default the constructor preserves member identity — each interval stays a distinct member with its own metadata. `Tempo.IntervalSet.new/1` sorts by `from` endpoint; it does NOT coalesce adjacent or overlapping intervals unless called as `new(intervals, coalesce: true)` or passed through `Tempo.IntervalSet.coalesce/1`.

```elixir
iex> {:ok, tempo} = Tempo.from_iso8601("2022Y{1..-1//3}M")
iex> {:ok, set} = Tempo.to_interval(tempo)
iex> Tempo.IntervalSet.count(set)
4
```

Enumeration walks each interval in time order, crossing interval boundaries seamlessly: `Enum.to_list(set)` on four month-sized intervals yields every day in each month, one interval at a time.

IntervalSet is the form used by set operations — `Tempo.union/2`, `Tempo.intersection/2`, `Tempo.complement/2`, `Tempo.difference/2`, and predicates. See `guides/set-operations.md` for the full treatment. Any call that needs a uniform-shape input can use `Tempo.to_interval_set/1`.

### 2.12. Seasons

The parser expands season codes into intervals before enumeration sees them.

| Code | Example | Expands to |
|---|---|---|
| Astronomical (25–32) | `2022-25` | March equinox to June solstice (computed via `Astro`) |
| Meteorological (21–24) | `2022-21` | March 1 to May 31 (calendar approximation) |

## 3. Not enumerable by design

These constructs *cannot* be enumerated, and no amount of future implementation will change that. They raise `ArgumentError` with a clear message (§3.1 to §3.5) or a named Tempo exception (§3.6), or the protocol falls back to `{:error, Enumerable.<Module>}` for calls like `Enum.count/1`.

### 3.1. Bare `%Tempo.Duration{}` values

A duration is a **length**, not a sequence. `P3M` means "three months" with no place on the time line. Iterating it would be nonsensical — three months starting *when*?

| Construct | Example |
|---|---|
| Pure duration | `P3M`, `P1Y2M3D`, `PT30M` |

A duration that *participates* in an interval (`1985-01/P3M`) is not a bare duration — see §4.1 for that case.

No `Enumerable` instance is defined for `Tempo.Duration`. Calls like `Enum.take(~o"P3M", 3)` raise `Protocol.UndefinedError`.

### 3.2. Fully open intervals

`../..` has no endpoints at all. There is nowhere to start and nowhere to stop.

```elixir
iex> {:ok, interval} = Tempo.from_iso8601("../..")
iex> Enum.take(interval, 3)
** (ArgumentError) Cannot enumerate a fully open interval `../..` — no start to iterate from.
```

### 3.3. Open-lower intervals

`../1985` has an end but no start. `Enumerable` iterates forward by protocol convention, which requires a lower bound. Iterating backwards from the upper bound would be surprising and would invert the half-open semantics.

```elixir
iex> {:ok, interval} = Tempo.from_iso8601("../1985-12-31")
iex> Enum.take(interval, 3)
** (ArgumentError) Cannot enumerate an interval with an open lower bound `../to` — Enumerable iterates forward from the lower bound, which is not defined.
```

### 3.4. Microsecond values at maximum precision

Sub-second resolution drills one decimal place at a time: a second iterates into ten tenths, a tenth into ten hundredths, and so on down to microsecond precision (six digits). This is the intended design — a stated resolution is always enumerable by stepping into the next-finer decimal place. The single exception is a value *already* at microsecond precision 6: it has no finer unit to drill into, so it is the one clock resolution that cannot be enumerated.

```elixir
iex> {:ok, value} = Tempo.from_iso8601("2022-06-15T10:30:00.000000Z")
iex> Enum.take(value, 1)
** (ArgumentError) Cannot enumerate a Tempo at microsecond precision 6 — that is the finest representable ulp. …
```

A second-resolution value, by contrast, *is* enumerable — it drills into ten deciseconds:

```elixir
iex> Enum.take(~o"2026-01-15T10:30:00", 3)
[~o"2026Y1M15DT10H30M0.0S", ~o"2026Y1M15DT10H30M0.1S", ~o"2026Y1M15DT10H30M0.2S"]
```

### 3.5. Significant-digits blocks larger than 10 000

`Y171010000S3` would expand to `171010000..171019999` — a million candidate years. Tempo refuses to iterate a block that large rather than hang or consume unbounded memory.

```elixir
iex> {:ok, value} = Tempo.from_iso8601("Y171010000S3")
iex> Enum.take(value, 3)
** (ArgumentError) Cannot enumerate a significant-digits block of 1000000 candidates (limit: 10000). …
```

The parsed value itself is usable for comparison, equality, and round-trip serialisation; only iteration is refused.

### 3.6. Values with nothing to walk

A value can parse and still name nothing a walk could yield. `Enumerable.reduce/3` has no error to return, so walking one raises a named exception, where `Tempo.to_interval/2` returns one for a value it cannot convert.

| Reason | Example | Raises |
|---|---|---|
| A unit that needs a year the value lacks | `X*W`, `{1..-1}W`, `2MXXD`, `2MX*D` | `Tempo.UnanchoredError` |
| A mask no value matches | `1985-02-3X` | `Tempo.InvalidDateError` |
| A group that starts beyond what holds it | `{2026,2027}Y5G3MU` | `Tempo.InvalidDateError` |
| A group of a set counted from the end of no year | `{1..-1}G3MU` | `Tempo.UnanchoredError` |
| A masked traditional month | `2026Y1Xm` | `Tempo.ConversionError` |
| An interval start with several values | `{2026,2027}Y/2030Y` | `Tempo.ConversionError` |
| An interval end that is no one point | `2026Y/202XY`, `1M/-1M` | `Tempo.IntervalEndpointsError` |
| A step that depends on a missing year | `2M28D/P1D` | `Tempo.UnanchoredError` |
| An unbounded recurrence | `R/2022-01-01/P1M` | `Tempo.UnboundedRecurrenceError` |
| The count of an interval with no end | `Enum.count(~o"2026Y/..")` | `Tempo.IntervalEndpointsError` |
| A slice of an interval with no end | `Enum.at(~o"2026Y/..", 3)`, `Enum.empty?(~o"2026Y/..")` | `Tempo.IntervalEndpointsError` |
| A search of an interval with no end and no year | `Enum.member?(~o"T10H/..", ~o"T12H")` | `Tempo.IntervalEndpointsError` |

```elixir
iex> Enum.take(~o"X*W", 1)
** (Tempo.UnanchoredError) This needs a value with a year: ~o"X*W" has none. Place the value on a date first with `Tempo.at/2` or `Tempo.on/2`.
```

## 4. `count/1`, `member?/2`, `slice/1` — fast paths

`Enum.count/1`, `Enum.member?/2`, and `Enum.slice/2` (with `Enum.at/2`) have O(1) implementations for `%Tempo{}` and `%Tempo.Interval{}`, backed by `Tempo.Interval.Steps`. They are calendar-aware (a Coptic year counts 13 months, not 12) and DST-aware (a spring-forward day counts 23 hours, a fall-back day 25), and they agree element-for-element with the `reduce/3` walk (§5.6 lists the one divergence).

Values that don't convert to a single interval — groups, selections, ranges, sets, masks — return `{:error, …}` and let `Enum` fall back to the `reduce/3` walk, which handles them.

### 4.1. Still pending: `%Tempo.Set{}`

`count/1` and `member?/2` on `%Tempo.Set{}` return `{:error, Enumerable.Tempo.Set}` today, so `Enum` falls back to `reduce/3`. A direct implementation would sum the members' counts; it is tracked with the broader set-operations work.

## 5. Semantic edge cases

### 5.1. "Missing" versus "unknown" versus "qualified"

Three similar-sounding situations have distinct enumeration meanings:

* **Missing (not specified).** `2022Y` simply omits finer units. The value is the *interval* of all of 2022 (§2.1) and implicit enumeration walks its months. **Fully enumerable.**

* **Unknown digit (`X` mask).** `156X` declares "this position is any valid digit." The mask expands to a **range** of candidate values (§2.4). **Fully enumerable.**

* **Qualified (`?`, `~`, `%`).** `2022Y?` is a concrete, fully-specified value — the year 2022 — annotated with uncertainty about the source. The qualification is held beside the value's components; it does not change what is iterated (§2.7). **Fully enumerable.**

These three are semantically distinct and should not be conflated:

| Description | Syntax | What's iterated |
|---|---|---|
| "Some year in the 1560s" | `156X` | each year 1560..1569 |
| "All of the year 1560" | `1560` | each month of 1560 |
| "The year 1560, uncertainly" | `1560?` | each month of 1560, the year of every yielded value flagged uncertain |

### 5.2. Qualification propagation on intervals

Per-endpoint qualifiers attach to that endpoint's value, not to the interior values.

```elixir
iex> {:ok, interval} = Tempo.from_iso8601("1984?/2004~")
iex> interval |> Tempo.Interval.from() |> Tempo.qualification()
:uncertain
iex> interval |> Tempo.Interval.to() |> Tempo.qualification()
:approximate
```

When the interval is enumerated forward from its start, each yielded value keeps the start's qualifiers. The end's qualifier is a property of the boundary, not the interior.

### 5.3. IXDTF metadata propagation on intervals

Per-endpoint IXDTF suffixes (`[Europe/Paris]`) attach to that endpoint. A top-level IXDTF suffix on an interval propagates to each endpoint that does not already carry its own. Iteration walks forward from `:from`, so yielded values carry `:from`'s zone, offset, and calendar.

### 5.4. Calendar-aware increment

Forward-stepping through an interval uses `calendar.months_in_year/1`, `calendar.days_in_month/2`, `calendar.weeks_in_year/1`, and `calendar.days_in_week/0` for carry. Iterating an interval whose endpoint's calendar is Hebrew, Islamic, or any other supported calendar Just Works — the carry boundaries change to match.

### 5.5. DST transitions

A zoned value is walked on the wall clock of its zone, and each value the walk yields is a wall time the zone shows.

* **The hour a clock skips** when it goes forward is not yielded: `2026-03-29[Europe/Paris]` is 23 hours.

* **The hour a clock shows twice** when it goes back is yielded twice, each with the offset that tells it from the other (`T2HZ2H`, then `T2HZ1H`): `2026-10-25[Europe/Paris]` is 25 hours.

* **A value in the hour shown twice** (`2026-10-25T02:30[Europe/Paris]`) names the first time the clock shows it, or the one the offset written with it names. Its walk yields that occurrence, the reading `Enum.count/1`, `Tempo.to_interval/2` and comparison give it.

### 5.6. Parity between implicit and explicit iteration

For every `%Tempo{}` where both implicit and explicit iteration are defined, the two produce identical sequences:

```elixir
iex> {:ok, tempo} = Tempo.from_iso8601("2026-01")
iex> implicit = Enum.to_list(tempo)
iex> {:ok, interval} = Tempo.to_interval(tempo)
iex> explicit = Enum.to_list(interval)
iex> implicit == explicit
true
```

Known divergences:

* **Second-resolution values.** `to_interval/1` converts it to a one-second span (`~o"2026-01-15T10:30:00"` → `[10:30:00, 10:30:01)`), but implicit iteration drills one unit finer into sub-second tenths — so `Enum.to_list(~o"2026-01-15T10:30:00")` yields ten deciseconds (`.0`–`.9`) while the interval forward-steps as a single second. Coarser resolutions don't diverge because their converted interval carries the drill unit on `:unit` (a day walks hours); the second case deliberately carries none (a clean `[t, t+1s)` span for set operations).

* **Masked values.** The implicit walk of a masked value yields each value its digits allow (`1985-XX-XX` is the 365 days of 1985), where `to_interval/1` gives the span or spans they cover, walked at their own resolution (`[1985, 1986)`, one year). Prefer the explicit form for set operations on masked values.

## 6. Summary table

| Category | Examples |
|---|---|
| **Enumerable** | every standard ISO 8601 / EDTF value with a concrete start — single values, ranges, sets, masks, long years, qualified values, IXDTF-tagged values, closed intervals, open-upper intervals, seasons, mixed-resolution intervals |
| **Not enumerable by design** | bare `%Tempo.Duration{}`, fully open intervals `../..`, open-lower intervals `../to`, microsecond values at precision 6 (the finest resolution), significant-digits blocks > 10 000 candidates, values with nothing to walk (§3.6) |
| **O(1) fast paths** | `count/1`, `member?/2`, `slice/1` on `%Tempo{}` and `%Tempo.Interval{}` (calendar- and DST-aware) |
| **Deferred** | `count/1` / `member?/2` on `%Tempo.Set{}` (falls back to `reduce/3`) |
