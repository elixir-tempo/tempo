# Enumeration semantics

Every Tempo expression implements `Enumerable`, so `Enum` and `Stream` work on all of them. What a walk gives follows from two rules, and this guide is those two rules and their consequences.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` to the caller's namespace; no helper functions leak in.

## 1. The two rules

**An expression that names one span is walked at the unit below the one it is written to.** A year gives its months, a month its days, a day its hours.

**An expression that names several spans is walked member by member.** A set gives its members, a recurrence its occurrences, a value that holds a list of days each of those days.

There is no third case, and no setting that changes which applies. To walk at another unit, say the unit with `Tempo.walk/2` (section 4).

## 2. One span: the unit below

```elixir
iex> Enum.take(~o"2022Y", 3)
[~o"2022Y1M", ~o"2022Y2M", ~o"2022Y3M"]

iex> Enum.count(~o"2026-06")
30

iex> Enum.take(~o"2026-06-15", 2)
[~o"2026Y6M15DT0H", ~o"2026Y6M15DT1H"]

iex> Enum.to_list(~o"2026-W25")
[~o"2026Y6M15D", ~o"2026Y6M16D", ~o"2026Y6M17D", ~o"2026Y6M18D", ~o"2026Y6M19D", ~o"2026Y6M20D", ~o"2026Y6M21D"]
```

> *"The first three months of 2022. June has thirty days. The first two hours of the fifteenth. The seven days of week twenty-five."*

Each value a walk gives is itself an expression, a span one unit long, so it can be walked in turn, compared, or passed to a set operation. A second is walked as its tenths, and a value written to the microsecond has nothing finer and gives nothing.

A value with no year is walked the same way, on its own cycle:

```elixir
iex> Enum.take(~o"6M", 3)
[~o"6M1D", ~o"6M2D", ~o"6M3D"]

iex> Enum.take(~o"T10", 3)
[~o"T10H0M", ~o"T10H1M", ~o"T10H2M"]
```

A duration has no place on the time line and is not enumerable.

### An interval is walked at the unit it is written to

An interval names one span too, and its ends say the unit. It is walked at the finer of the units its two ends are written to, from its first end to its last. A date end is read through (`2026/2028` is three years); a clock end is the reading the span runs to (nine to twelve is three hours).

```elixir
iex> Enum.to_list(~o"2026/2028")
[~o"2026Y", ~o"2027Y", ~o"2028Y"]

iex> Enum.to_list(~o"2026-06-01/2026-06-03")
[~o"2026Y6M1D", ~o"2026Y6M2D", ~o"2026Y6M3D"]

iex> Enum.to_list(~o"2026-06-15T09/2026-06-15T12")
[~o"2026Y6M15DT9H", ~o"2026Y6M15DT10H", ~o"2026Y6M15DT11H"]
```

> *"The years 2026 through 2028. The first three days of June. The hours from nine to twelve."*

This is the difference between a value and the interval of the same extent: `~o"2026-06"` is walked as its days, and `~o"2026-06/2026-06"` as the one month its ends name. Both cover the same time, and `Tempo.equal?/2` says so.

### An interval with no end is walked lazily

An interval with an open end has a first value and no last, so it is a stream. Take what you need:

```elixir
iex> Enum.take(~o"1985/..", 3)
[~o"1985Y", ~o"1986Y", ~o"1987Y"]
```

An interval with an open *start* has nowhere to begin, and walking it raises a `Tempo.ConversionError` whose reason is `:open`.

## 3. Several spans: member by member

```elixir
iex> Enum.to_list(~o"{2026-01,2026-03}")
[~o"2026Y1M", ~o"2026Y3M"]

iex> Enum.to_list(~o"2026Y6M{1,15}D")
[~o"2026Y6M1D", ~o"2026Y6M15D"]

iex> Enum.to_list(~o"R3/2026-06-01/P1D")
[~o"2026Y6M1D/2026Y6M1D", ~o"2026Y6M2D/2026Y6M2D", ~o"2026Y6M3D/2026Y6M3D"]

iex> Enum.to_list(~o"2026Y6ML5KN")
[~o"2026Y6M5D", ~o"2026Y6M12D", ~o"2026Y6M19D", ~o"2026Y6M26D"]
```

> *"January and March. The first and the fifteenth of June. Three daily occurrences from the first of June. The Fridays of June."*

`Enum.count/1` of a plural expression is therefore how many spans it names: a set's members, a recurrence's occurrences. A recurrence with no end is a stream, as an open interval is:

```elixir
iex> Enum.take(~o"R/2026-06-01/P1W", 2)
[~o"2026Y6M1D/7D", ~o"2026Y6M8D/14D"]
```

A value with unspecified digits and a one-of set are walked through the values they may be:

```elixir
iex> Enum.take(~o"156X", 3)
[~o"1560Y", ~o"1561Y", ~o"1562Y"]

iex> Enum.to_list(~o"[2026-06-15,2026-07-04]")
[~o"2026Y6M15D", ~o"2026Y7M4D"]
```

`Tempo.members/2` gives the same members as a list in a tagged tuple, and takes a `:within` window for an expression with no year or no end.

## 4. Walking at a unit you choose

`Tempo.walk/2` walks every span of an expression at the unit asked, and answers a stream:

```elixir
iex> {:ok, weeks} = Tempo.walk(~o"2026-06", :week)
iex> Enum.to_list(weeks)
[~o"2026Y23W", ~o"2026Y24W", ~o"2026Y25W", ~o"2026Y26W", ~o"2026Y27W"]

iex> {:ok, minutes} = Tempo.walk(~o"2026-06-15", :minute)
iex> Enum.count(minutes)
1440

iex> {:ok, months} = Tempo.union(~o"2022Y1M", ~o"2022Y3M")
iex> {:ok, days} = Tempo.walk(months, :day)
iex> Enum.count(days)
62

iex> Tempo.count(months, :day)
{:ok, 62}
```

> *"The weeks of June. The minutes of the fifteenth. The days of January and of March, walked and then counted."*

A calendar unit gives each period the span touches, the first and the last in part where the span begins or ends within them: July walked by week begins with the week of the 29th of June. A clock unit gives the readings one unit apart from its start to its end. `Tempo.count/3` counts what a walk gives, without the stream.

## 5. Membership is cover

`in` asks whether an expression covers a value, not whether the value is one of the things a walk happens to give:

```elixir
iex> ~o"2026-06-15" in ~o"2026"
true

iex> ~o"2026-06-15T10" in ~o"2026-06-01/2026-06-20"
true

iex> ~o"2027" in ~o"2026"
false
```

> *"The fifteenth of June is in 2026. Ten o'clock on the fifteenth is in the first twenty days of June. 2027 is not in 2026."*

It is `Tempo.contains?/2` with its arguments the other way round, and takes any expression that has spans on either side.

## 6. The clock is the zone's

A walk at a clock unit gives the readings the zone's clock shows. On the day the clocks of Paris go forward there is no two o'clock, and on the day they go back there are two:

```elixir
iex> Enum.count(~o"2026-03-29[Europe/Paris]")
23

iex> Enum.count(~o"2026-10-25[Europe/Paris]")
25
```

So count a walk to know how many readings there are, and ask `Tempo.duration/1` to know how long a span is.

## 7. The calendar is the value's

The units a walk gives are the value's own calendar's. The Hebrew year 5786 has twelve months, and a leap year thirteen:

```elixir
iex> ~o"5786[u-ca=hebrew]" |> Enum.count()
12
```

## 8. Bounds on work

A walk is lazy: it gives one value at a time and holds none, so `Enum.take/2` on a stream with no end returns at once. Functions that need every value at once (`Enum.count/1`, `Enum.to_list/1`, `Tempo.to_interval/2`, the set operations) stop at ten thousand, unless the application sets another limit (`config :ex_tempo, max_values_at_once: 100_000`), with a `Tempo.ConversionError` whose reason is `:too_many_values`:

```elixir
iex> Enum.count(~o"2026Y{1..12}M{1..28}DT{0..23}H{0..59}M{0..59}S")
** (Tempo.ConversionError)
```

That value names twenty-nine million seconds, and `Enum.take/2` still gives the first few.

## 9. Qualifications ride along

An uncertain or approximate value is walked as the value it is written as, and each end of an interval keeps its own qualification:

```elixir
iex> interval = ~o"1984?/2004~"
iex> interval |> Tempo.Interval.from() |> Tempo.qualification()
%{year: :uncertain}

iex> interval |> Tempo.Interval.to() |> Tempo.qualification(:year)
:approximate

iex> Enum.count(interval)
21
```

## Related reading

* [Set operations](./set-operations.md) — what walking a result gives.

* [Workdays and weekends](./workdays-and-weekends.md) — selecting from a span with no end.

* [ISO 8601 conformance](./iso8601-conformance.md) — the forms that name several spans.
