# Converting to and from Elixir date/time types

Tempo treats every value as a **bounded interval on the time line**, never as an instant (see [When to use Tempo](when-to-use-tempo.md) for why). The moment you bring a stdlib `Date`, `Time`, `NaiveDateTime`, or `DateTime` into Tempo, it stops being a point and becomes a span.

This guide answers the two questions that follow from that:

* **At what resolution** does a converted value land?
* **What interval** does a "point in time" actually become — and why does the width matter?
* **What shape** does a string become — and how do you say which shape you expected?

## Setup — required for every example

Every example uses the `~o` sigil from `Tempo.Sigils`. Bring it into scope first:

```elixir
import Tempo.Sigils
```

## 1. Stdlib → Tempo: the resolution you get

`Tempo.from_elixir/2` is the unified gateway (there are also type-specific `from_date/1`, `from_time/1`, `from_naive_date_time/1`, `from_date_time/1`).

The rule is: **resolution follows the type's declared precision, not the magnitude of its fields.** Elixir's `Time`/`NaiveDateTime`/`DateTime` are second-granular by construction, so `09:00:00` is a *fully specified second* — not an under-specified hour. A zero component is still a specified component.

| Elixir value | Inferred resolution |
|---|---|
| `~D[2022-07-04]` | `:day` (a `Date` has no time axis) |
| `~T[14:30:00]` | `:second` |
| `~N[2022-07-04 14:30:00]` | `:second` |
| `~U[2022-07-04 14:30:00Z]` | `:second` |
| `~U[2022-07-04 14:30:00.000000Z]` | `:microsecond` (sub-second precision present) |

```elixir
Tempo.from_elixir(~U[2022-07-04 14:30:00Z]) |> Tempo.resolution()
#=> {:second, 1}
```

To deliberately widen to a coarser span, pass `:resolution`:

```elixir
# Treat a midnight value as the whole day, not the first second of it.
Tempo.from_elixir(~N[2022-07-04 00:00:00], resolution: :day)
#=> ~o"2022Y7M4D"
```

> *"Read a calendar value at the precision it was written; widen to a whole day only when you ask for it."*

## 2. A point in time **is** an interval

Every Tempo value materialises to an explicit half-open `[from, to)` span via `Tempo.to_interval/1`. The width is **one unit at the value's resolution** — so the resolution from §1 decides the span:

| Converted from | Interval | Width |
|---|---|---|
| `~D[2022-07-04]` (day) | `[2022-07-04, 2022-07-05)` | 1 day |
| `~U[…14:30:45Z]` (second) | `[…14:30:45, …14:30:46)` | 1 second |
| `~U[…14:30:45.123456Z]` (µs) | `[…45.123456, …45.123457)` | 1 microsecond |

```elixir
{:ok, interval} = Tempo.from_elixir(~U[2022-07-04 14:30:45Z]) |> Tempo.to_interval()
Tempo.Interval.duration(interval)
#=> ~o"PT1S"
```

```elixir
{:ok, day} = Tempo.from_elixir(~D[2022-07-04]) |> Tempo.to_interval()
Tempo.Interval.duration(day)
#=> ~o"PT86400S"   # one whole day
```

The upper bound is **exclusive** (`[from, to)`), which is what makes the spans tile the time line cleanly — `[2022-07-04, 2022-07-05)` followed by `[2022-07-05, 2022-07-06)` is exactly `[2022-07-04, 2022-07-06)` with no gap or overlap. See [Enumeration semantics](enumeration-semantics.md) for how this drives iteration, and `Tempo.to_interval/2` for the full materialisation contract.

> *"A day is the span from this midnight to the next; a timestamp is the span from this second to the next."*

Two notes:

* **Sub-second spans and `duration/1`.** `duration/1` reports whole seconds, so a one-microsecond interval reads as `~o"PT0S"`. The span is still one microsecond wide — inspect the endpoints (`from/1`, `to/1`) when you need sub-second extent.

* **A bare `Time` materialises non-anchored.** `~T[14:30:00]` becomes `T14H30M0S/T1S` — a one-second span on the *time-of-day* axis with no date. Operations that need an absolute position (duration in wall-clock seconds, cross-zone comparison) require anchoring it to a date first.

* **A pure time-of-day group materialises non-anchored too.** A grouped time value with no date — for example the first quarter-hour `[hour: 16, minute: {:group, 1..15}]` — becomes the relative span `[16:01, 16:16)` on the time-of-day axis. The same anchoring caveat applies. A group whose upper bound would carry off the end of the day (`23:45..`, with no date to carry into) or any group with a date component (`5G10DU`) needs anchoring first and returns a `Tempo.MaterialisationError` until then.

## 3. Why the width matters

This is the whole point of the interval model, and the place stdlib intuition trips up. Because each "instant" is really a half-open one-unit span, **two timestamps one second apart do not overlap — they meet at the shared boundary.**

```elixir
earlier = ~o"2022Y7M4DT14H30M45S"   # the span [45s, 46s)
later   = ~o"2022Y7M4DT14H30M46S"   # the span [46s, 47s)

Tempo.relation(earlier, later)
#=> :meets

Tempo.overlaps?(earlier, later)
#=> false
```

Identical timestamps are `:equals`; consecutive ones `:meets`; only a genuine span covering shared time `:overlaps`. That precision is exactly what lets free/busy scans, coalescing, and set operations be unambiguous — there is never a "do these touch?" grey area.

> *"9:30:45 and 9:30:46 don't clash — they're back-to-back."*

And because a plain `DateTime`/`NaiveDateTime` now materialises (it infers to second resolution, and a second is a one-second span), converted timestamps drop straight into the set-algebra API:

```elixir
{:ok, busy} = Tempo.union(~o"2022Y7M4DT14H30M45S", ~o"2022Y7M4DT14H30M46S")
#=> two adjacent one-second spans, ready for difference/intersection/…
```

## 4. Tempo → stdlib: projecting back out

Going the other way, you choose how much of the interval/zone information to keep:

| Function | Result | Zone handling |
|---|---|---|
| `to_date/1` | `Date` | dropped (wall-clock date) |
| `to_time/1` | `Time` | dropped (wall-clock time-of-day) |
| `to_naive_date_time/1` | `NaiveDateTime` | **dropped** (wall-clock reading) |
| `to_date_time/1` | `DateTime` | **preserved** (lossless inverse) |

`to_naive_date_time/1` keeps the wall-clock numbers and discards the offset — exactly like the stdlib `DateTime.to_naive/1`. It does **not** shift to UTC:

```elixir
# Paris is UTC+2 in summer; the wall reading is 10:30, not 08:30.
paris = Tempo.from_elixir(DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris"))
Tempo.to_naive_date_time(paris)
#=> {:ok, ~N[2022-06-15 10:30:00.000000]}
```

When the zone matters, `to_date_time/1` is the lossless inverse of `from_elixir/2` on a `DateTime` — it preserves the named zone and re-derives the offset from the time-zone database:

```elixir
Tempo.to_date_time(paris)
#=> {:ok, #DateTime<2022-06-15 10:30:00.000000+02:00 CEST Europe/Paris>}
```

If you want UTC *wall* time rather than the local reading, normalise explicitly first:

```elixir
{:ok, utc} = Tempo.shift_zone(paris, "Etc/UTC")
Tempo.to_naive_date_time(utc)
#=> {:ok, ~N[2022-06-15 08:30:00.000000]}
```

Two caveats:

* **Resolution must reach the target.** A value coarser than a full datetime (e.g. `~o"2022-11"`) cannot fill a `NaiveDateTime`/`DateTime` and returns `{:error, _}`. Project to the type the value's resolution supports (`to_date/1` for a day, `to_time/1` for a time-of-day).

* **Microsecond precision normalises to 6.** A second-resolution value round-trips through `{0, 0}` → `{0, 6}` microseconds; the instant, zone, and wall reading are identical, only the precision tag widens.

## 5. Serialising intervals — granularity is not in the string

An interval's ISO 8601 string carries its **extent** only. The iteration granularity a materialised implicit span carries on `:unit` (why `to_interval(~o"2025-07-04")` enumerates 24 hours despite day-resolution bounds) has no ISO 8601 spelling, so `to_iso8601/1` cannot preserve it and the re-parsed interval walks at its bounds resolution instead:

```elixir
{:ok, day} = Tempo.to_interval(~o"2025-07-04")
Enum.count(day)
#=> 24    # walks hours — unit: :hour travels on the struct

reparsed = Tempo.from_iso8601!(Tempo.to_iso8601(day))
Enum.count(reparsed)
#=> 1     # walks at day resolution — the string carried only the extent
```

This is why such an interval inspects in the decorated form (`#Tempo.Interval<~o"2025-07-04/2025-07-05" unit: hour>`) rather than as a bare sigil: the decoration marks state the string cannot round-trip, exactly as it does for iCal metadata. If walk behaviour must survive persistence, store the *source* value (`~o"2025-07-04"` — its implicit enumeration is derived, so it round-trips fully) or re-attach the granularity on load with `Tempo.Interval.new(from: from, to: to, unit: :hour)`.

## 6. Strings → Tempo: declare the shape you expect

`Tempo.from_iso8601/1` admits every shape ISO 8601 defines and returns whichever one the string turned out to be. That is the right tool when the shape is genuinely unknown — a single text field a user may fill with anything. At an edge where the shape *is* known, declaring it turns a wrong value into an error at the point of parsing:

```elixir
Tempo.parse_date("2026-06-15")
#=> {:ok, ~o"2026Y6M15D"}

Tempo.parse_date("2026-06-15T10:30")
#=> {:error, %Tempo.ParseError{}}   # a datetime is not a date
```

One function per shape, each with a bang variant:

| Function | Admits | Returns |
| --- | --- | --- |
| `Tempo.parse_date/2` | a date at any resolution — `2026`, `2026-06`, `2026-06-15`, `2026-W12`, `2026-166` | `%Tempo{}` |
| `Tempo.parse_datetime/2` | a date *and* a time of day | `%Tempo{}` |
| `Tempo.parse_time/2` | a time of day alone | `%Tempo{}` |
| `Tempo.parse_interval/2` | any interval form, including a repeat rule | `%Tempo.Interval{}` |
| `Tempo.parse_duration/1` | a duration | `%Tempo.Duration{}` |

The whole string must be the declared shape, so a value that merely *begins* with one is rejected rather than truncated:

```elixir
Tempo.parse_duration("P1D/2026-06-15")
#=> {:error, %Tempo.ParseError{}}   # that is an interval, not a duration
```

### Why this matters most for dates, datetimes and times

An interval and a duration are already distinguishable by their struct, so a caller can pattern match on `%Tempo.Interval{}` and be certain. A date, a datetime and a time are **all** `%Tempo{}` — there is no struct to match on, so a time of day arriving in a date column parses successfully and the problem surfaces somewhere downstream, or not at all:

<!-- guides:run -->
```elixir
# Both succeed, and both are a %Tempo{}. The general parser cannot
# tell a date field that it received something else.
{:ok, %Tempo{}} = Tempo.from_iso8601("2026-06-15")
{:ok, %Tempo{}} = Tempo.from_iso8601("10:30")

# Declaring the shape is what makes the second one an error.
{:ok, %Tempo{}} = Tempo.parse_date("2026-06-15")
{:error, %Tempo.ParseError{}} = Tempo.parse_date("10:30")
```

Everything downstream of tokenization is unchanged, so a profile parse resolves calendars, honours an IXDTF suffix, keeps an EDTF qualification, and validates exactly as `from_iso8601/1` does:

```elixir
Tempo.parse_date!("2026-06-15[u-ca=gregory]") == Tempo.from_iso8601!("2026-06-15[u-ca=gregory]")
#=> true

Tempo.parse_date("2026-02-30")
#=> {:error, %Tempo.InvalidDateError{}}   # rejected by validation, not admitted by the profile
```

### One ambiguity the profile resolves

ISO 8601 basic format makes some strings both a valid year and a valid time of day: `2026` is the year 2026 and also 20:26. The general grammar resolves this structurally, preferring the date reading. A caller of `parse_time/2` has declared the field holds a time, and that declaration is what selects the other reading:

```elixir
Tempo.from_iso8601!("2026")
#=> ~o"2026Y"

Tempo.parse_time!("2026")
#=> ~o"T20H26M"
```

This is the only profile whose *result* can differ from `from_iso8601/1` rather than only its acceptance. Reach for it when the field genuinely holds a time; the ambiguity it resolves is in the format, not in the parser.

Being narrower grammars, the profile parsers are also faster than `from_iso8601/1` — around 11× on dates, 28× on times — but correctness is the reason to prefer them.

## 7. Where to convert

Convert at the **edges**, compute in the **middle**:

* **Edge layer** (HTTP, DB, log parsing): stdlib types. Parse Unix timestamps and ISO strings into `Date`/`DateTime`.
* **Domain layer** (scheduling, availability, recurrence, set operations): Tempo. Convert in with `from_elixir/2` when the next operation is interval-shaped.
* **Display layer**: `Tempo.to_string/2` for locale-aware output, or the `to_*` projections above to hand a stdlib value back to non-Tempo code.

See [When to use Tempo](when-to-use-tempo.md) for the full decision tree.

## Cheat sheet

```elixir
# String → Tempo  (declare the shape; the whole string must be it)
Tempo.parse_date("2026-06-15")                   # {:ok, %Tempo{}}
Tempo.parse_datetime("2026-06-15T14:30")         # {:ok, %Tempo{}}
Tempo.parse_time("14:30")                        # {:ok, %Tempo{}}
Tempo.parse_interval("2026-06-15/2026-06-20")    # {:ok, %Tempo.Interval{}}
Tempo.parse_duration("PT1H30M")                  # {:ok, %Tempo.Duration{}}
Tempo.from_iso8601("2026-06-15")                 # any shape, when the shape is unknown

# Stdlib → Tempo  (resolution = the type's precision; override with :resolution)
Tempo.from_date(~D[2026-06-15])                  # :day
Tempo.from_time(~T[14:30:00])                    # :second (time-of-day, non-anchored)
Tempo.from_naive_date_time(~N[2026-06-15 14:30:00])
Tempo.from_date_time(~U[2026-06-15 14:30:00Z])   # :second, zoned
Tempo.from_elixir(value, resolution: :day)       # unified gateway + explicit widen

# Point → interval  (every value is a span of one unit at its resolution)
Tempo.to_interval(tempo)                          # {:ok, %Interval{}} half-open [from, to)

# Tempo → Stdlib
Tempo.to_date(tempo)                              # zone dropped
Tempo.to_time(tempo)                              # zone dropped
Tempo.to_naive_date_time(tempo)                   # zone dropped (wall-clock, not UTC)
Tempo.to_date_time(tempo)                         # zone preserved (lossless)
Tempo.shift_zone(tempo, "Etc/UTC")                # normalise to UTC first if needed
```
