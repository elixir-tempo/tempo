# Converting to and from Elixir date/time types

Tempo treats every value as a **bounded interval on the time line**, never as an instant (see [When to use Tempo](when-to-use-tempo.md) for why). The moment you bring a stdlib `Date`, `Time`, `NaiveDateTime`, or `DateTime` into Tempo, it stops being a point and becomes a span.

This guide answers the questions that follow from that:

* **At what resolution** does a converted value land?

* **What interval** does a "point in time" actually become — and why does the width matter?

* **What kind of value** does a text become — and how do you say which kind you expected?

## Setup — required for every example

Every example uses the `~o` sigil from `Tempo.Sigils`. Bring it into scope first:

```elixir
import Tempo.Sigils
```

## 1. Stdlib → Tempo: the resolution you get

`Tempo.from_elixir/2` is the one gateway, and returns `{:ok, value}`. `Tempo.from_elixir!/2` returns the value, as do the typed `from_date/1`, `from_time/1`, `from_naive_datetime/1` and `from_datetime/1`, which cannot fail.

The rule is: **resolution follows the type's declared precision, not the magnitude of its fields.** Elixir's `Time`, `NaiveDateTime` and `DateTime` are second-granular by construction, so `09:00:00` is a *fully specified second* — not an under-specified hour. A zero component is still a specified component.

| Elixir value | Resolution |
|---|---|
| `~D[2022-07-04]` | `:day` (a `Date` has no time of day) |
| `~T[14:30:00]` | `:second` |
| `~N[2022-07-04 14:30:00]` | `:second` |
| `~U[2022-07-04 14:30:00Z]` | `:second` |
| `~U[2022-07-04 14:30:00.000000Z]` | `:microsecond` (a fraction of a second is written) |

```elixir
iex> Tempo.from_elixir(~U[2022-07-04 14:30:00Z])
{:ok, ~o"2022Y7M4DT14H30M0SZ"}

iex> ~U[2022-07-04 14:30:00Z] |> Tempo.from_datetime() |> Tempo.resolution()
:second
```

To deliberately widen to a coarser span, pass `:resolution`:

```elixir
# Treat a midnight value as the whole day, not the first second of it.
iex> Tempo.from_elixir(~N[2022-07-04 00:00:00], resolution: :day)
{:ok, ~o"2022Y7M4D"}
```

> *"Read a calendar value at the precision it was written; widen to a whole day only when you ask for it."*

A `Date.Range` is the span of its days, written to its last day, and an Elixir `Duration` is a Tempo duration:

```elixir
iex> Tempo.from_elixir(Date.range(~D[2026-07-01], ~D[2026-07-31]))
{:ok, ~o"2026Y7M1D/31D"}

iex> Tempo.from_elixir(Duration.new!(hour: 8))
{:ok, ~o"PT8H"}
```

## 2. A point in time **is** an interval

Every value is a half-open span `[from, to)` one unit of its resolution long — so the resolution from section 1 decides the span:

| Converted from | Span | Length |
|---|---|---|
| `~D[2022-07-04]` (day) | `[2022-07-04, 2022-07-05)` | 1 day |
| `~U[…14:30:45Z]` (second) | `[…14:30:45, …14:30:46)` | 1 second |

```elixir
iex> ~U[2022-07-04 14:30:45Z] |> Tempo.from_datetime() |> Tempo.duration()
~o"PT1S"

iex> ~D[2022-07-04] |> Tempo.from_date() |> Tempo.duration()
~o"P1D"
```

The spans are half-open, which is what makes them tile the time line cleanly — the fourth of July followed by the fifth is exactly the two days, with no gap or overlap. See [Enumeration semantics](enumeration-semantics.md) for how this drives a walk.

> *"A day is the span from this midnight to the next; a timestamp is the span from this second to the next."*

`Tempo.to_interval/2` writes a value out as the interval it is. An interval's text follows one rule: an end written to a date is read through that date, and an end written to a time of day is the reading the span runs to. So a day is written from itself through itself, and a second from itself to the next:

```elixir
iex> Tempo.to_interval(~o"2022-07-04")
{:ok, ~o"2022Y7M4D/2022Y7M4D"}

iex> Tempo.to_interval(~o"2022-07-04T14:30:45")
{:ok, ~o"2022Y7M4DT14H30M45S/T46S"}
```

Two notes:

* **A duration is in the unit the value is written to.** The day is `~o"P1D"` and the second `~o"PT1S"`.

* **A bare `Time` is a value with no date.** `~T[14:30:00]` becomes `~o"T14:30:00"`, a second of every day. Operations that need a place on the time line (a comparison with a dated value, a zone) want it placed on a date first with `Tempo.on/2`.

## 3. Why the width matters

This is the whole point of the interval model, and the place stdlib intuition trips up. Because each "instant" is really a half-open one-unit span, **two timestamps one second apart do not overlap — they meet at the shared boundary.**

```elixir
iex> earlier = ~o"2022Y7M4DT14H30M45S"
iex> later = ~o"2022Y7M4DT14H30M46S"
iex> Tempo.relation(earlier, later)
:meets

iex> Tempo.overlaps?(earlier, later)
false
```

Identical timestamps are `:equals`; consecutive ones `:meets`; only spans that share time `:overlaps`. That precision is exactly what lets free-busy scans, coalescing and set operations be unambiguous — there is never a "do these touch?" grey area.

> *"14:30:45 and 14:30:46 don't clash — they're back-to-back."*

And because a `DateTime` or a `NaiveDateTime` converts to a second, converted timestamps drop straight into the set-algebra API:

```elixir
iex> {:ok, busy} = Tempo.union(~o"2022Y7M4DT14H30M45S", ~o"2022Y7M4DT14H30M46S")
iex> Tempo.IntervalSet.count(busy)
2
```

## 4. Tempo → stdlib: projecting back out

Going the other way, you choose how much of the value to keep. Each returns `{:ok, struct}`, and `Tempo.to_elixir/1` picks the struct the value fills:

| Function | Result | Zone handling |
|---|---|---|
| `to_date/1` | `Date` | dropped (the date on its own clock) |
| `to_time/1` | `Time` | dropped (the time of day on its own clock) |
| `to_naive_datetime/1` | `NaiveDateTime` | **dropped** (the reading on its own clock) |
| `to_datetime/1` | `DateTime` | **kept** |

`to_naive_datetime/1` keeps the numbers on the value's own clock and discards the zone — exactly like the stdlib `DateTime.to_naive/1`. It does **not** shift to UTC:

```elixir
# Paris is UTC+2 in summer; the reading is 10:30, not 08:30.
iex> paris = Tempo.from_datetime(DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris"))
iex> Tempo.to_naive_datetime(paris)
{:ok, ~N[2022-06-15 10:30:00]}
```

When the zone matters, `to_datetime/1` is the inverse of `from_datetime/1` — it keeps the named zone and takes the offset from the time zone database:

```elixir
iex> {:ok, datetime} = Tempo.to_datetime(paris)
iex> {datetime.time_zone, datetime.utc_offset + datetime.std_offset}
{"Europe/Paris", 7200}
```

If you want the reading in UTC rather than the local one, move the value there first:

```elixir
iex> {:ok, utc} = Tempo.shift_zone(paris, "Etc/UTC")
iex> Tempo.to_naive_datetime(utc)
{:ok, ~N[2022-06-15 08:30:00]}
```

Two caveats:

* **A value coarser than a day fills none of them.** `~o"2022-11"` returns `{:error, %Tempo.ConversionError{}}` from every projection. A day fills a `Date`, and a `NaiveDateTime` at midnight; a value with no zone and no shift returns an error from `to_datetime/1`.

* **Units not written are zero.** `~o"2022-06-15T10"` projects to `10:00:00`.

## 5. An interval's text is the interval

An expression's ISO 8601 text carries all of it: its ends as they were written, its calendar and its zone. So `Tempo.to_iso8601/1` and `Tempo.from_iso8601/2` round-trip every expression, and `inspect/1` shows an expression as the `~o` sigil that reads it. What a text does not carry is metadata, which is your application's to store beside it.

```elixir
iex> span = ~o"2025-07-04T09/2025-07-04T17[Europe/Paris]"
iex> Tempo.from_iso8601!(Tempo.to_iso8601!(span)) == span
true
```

## 6. Text → Tempo: declare the kind you expect

`Tempo.from_iso8601/2` reads every form ISO 8601 defines and returns whichever one the text turned out to be. `Tempo.parse/2` reads those and, after them, a locale's own words (`"15 June 2026"`, `"2:30 PM"`). That is the right tool when the kind is genuinely unknown — a single text field a user may fill with anything. At an edge where the kind *is* known, declaring it with `:profile` turns a wrong value into an error at the point of reading:

```elixir
iex> Tempo.from_iso8601("2026-06-15", profile: :date)
{:ok, ~o"2026Y6M15D"}

iex> Tempo.parse("15 June 2026", locale: :en)
{:ok, ~o"2026Y6M15D"}

# A date and time is not a date
iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("2026-06-15T10:30", profile: :date)
```

| Profile | Admits |
|---|---|
| `:date` | a date at any resolution: `2026`, `2026-06`, `2026-06-15`, `2026-W12`, `2026-166` |
| `:datetime` | a date *and* a time of day |
| `:time` | a time of day alone: `T14:30` |
| `:interval` | any interval form, a recurrence among them |
| `:duration` | a duration; `Tempo.parse_duration/1` is this profile by name |

The whole text must be of the declared kind, so a value that merely *begins* with one is refused rather than cut short:

```elixir
# That is an interval, not a duration
iex> {:error, %Tempo.ParseError{}} = Tempo.parse_duration("P1D/2026-06-15")
```

### Why this matters most for dates, date-times and times

A date, a date and time and a time of day are all a `%Tempo{}` of the same form, so a time of day arriving in a date column reads successfully and the problem surfaces somewhere downstream, or not at all:

```elixir
# Both succeed. The reader cannot tell a date field that it received something else.
iex> {:ok, %Tempo{}} = Tempo.from_iso8601("2026-06-15")
iex> {:ok, %Tempo{}} = Tempo.from_iso8601("T10:30")

# Declaring the kind is what makes the second one an error.
iex> {:ok, %Tempo{}} = Tempo.from_iso8601("2026-06-15", profile: :date)
iex> {:error, %Tempo.ParseError{}} = Tempo.from_iso8601("T10:30", profile: :date)
```

A profile changes only what is admitted. The text is read, placed in its calendar and validated exactly as it is without one:

```elixir
iex> Tempo.from_iso8601("2026-06-15[u-ca=gregory]", profile: :date) == Tempo.from_iso8601("2026-06-15[u-ca=gregory]")
true

# Refused by validation, not admitted by the profile
iex> {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601("2026-02-30", profile: :date)
```

## 7. Where to convert

Convert at the **edges**, compute in the **middle**:

* **Edge layer** (HTTP, DB, log parsing): stdlib types. Parse Unix timestamps and ISO strings into `Date` and `DateTime`.

* **Domain layer** (scheduling, availability, recurrence, set operations): Tempo. Convert in with `from_elixir/2` when the next operation is interval-shaped.

* **Display layer**: `Tempo.to_string/2` for a locale's words, or the `to_*` projections above to hand a stdlib value back to code that does not use Tempo.

See [When to use Tempo](when-to-use-tempo.md) for the full decision tree.

## Cheat sheet

```elixir
# Text → Tempo  (declare the kind; the whole text must be of it)
Tempo.from_iso8601("2026-06-15", profile: :date)        # {:ok, value}
Tempo.from_iso8601("2026-06-15T14:30", profile: :datetime)
Tempo.from_iso8601("T14:30", profile: :time)
Tempo.from_iso8601("2026-06-15/2026-06-20", profile: :interval)
Tempo.parse_duration("PT1H30M")                         # {:ok, duration}
Tempo.parse("15 June 2026", locale: :en)                # ISO 8601, then the locale's words

# Stdlib → Tempo  (resolution is the type's precision; override with :resolution)
Tempo.from_date(~D[2026-06-15])                         # a day
Tempo.from_time(~T[14:30:00])                           # a second of any day
Tempo.from_naive_datetime(~N[2026-06-15 14:30:00])
Tempo.from_datetime(~U[2026-06-15 14:30:00Z])           # a second, in UTC
Tempo.from_elixir(value, resolution: :day)              # {:ok, value}, at a unit you choose

# A value as the interval it is
Tempo.to_interval(value)                                # {:ok, interval}

# Tempo → Stdlib
Tempo.to_date(value)                                    # zone dropped
Tempo.to_time(value)                                    # zone dropped
Tempo.to_naive_datetime(value)                          # zone dropped (its own clock, not UTC)
Tempo.to_datetime(value)                                # zone kept
Tempo.shift_zone(value, "Etc/UTC")                      # move to UTC first if needed
```
