# Migrating to Tempo 2.0

Tempo 2.0 gives each word in its API one meaning, the one it has in everyday English. Most of the changes are renames: the compiler warns about every call to a removed function, and a leftover `:bound` option returns an error that names its replacement. A few names keep their spelling and change what they answer, and those need a read of each call site. This guide takes the changes one at a time, each with its 1.x form and its 2.0 form.

## Overview

| 1.x | 2.0 |
|---|---|
| `Tempo.IntervalSet.total_duration/1` | `Tempo.IntervalSet.duration/1` |
| the `:bound` option | `:within` |
| `Tempo.subset?/3` | `Tempo.within?/3` |
| `during?/2`, `meets?/2` on `Tempo` and `Tempo.Interval` | `Tempo.Allen.during?/2`, `Tempo.Allen.meets?/2` |
| `Tempo.Interval.inverse_relation/1` | `Tempo.Allen.inverse/1` |
| `compose/2` on `Tempo` and `Tempo.Interval` | `Tempo.Allen.compose/2` |
| `Tempo.Interval.equivalent?/2` | `Tempo.equal?/3` |
| IXDTF tags through `Tempo.new/1`'s `:metadata` | `:tags` |

These keep their names and change their meaning:

* **`before?/2` and `after?/2`** — two spans that meet now count, because they share no instant.

* **`duration/1` on a set** — the time the set covers, counting time its members share once.

* **The `:within` window** — every occurrence that overlaps the window, for every kind of recurrence.

* **`Tempo.new/1`'s `:metadata`** — the value's own data, no longer written into its ISO 8601 form.

## Updating the dependency

```elixir
def deps do
  [
    {:ex_tempo, "~> 2.0"}
  ]
end
```

A search for the removed names finds the renames:

```bash
grep -rnE 'bound:|subset\?|total_duration|inverse_relation|equivalent\?|Tempo\.(meets|during)\?|Interval\.(meets|during)\?|(Tempo|Interval)\.compose' lib test
```

The changes of meaning need a read rather than a replace: every `before?`, `after?` and their `certainly_` and `possibly_` forms, every `duration/1` of a set, every window, and every `:metadata` passed to `Tempo.new/1`.

## A set's duration is the time it covers

In 1.x, `Tempo.IntervalSet.duration/1` (and `Tempo.duration/1` of a set) added up its members' lengths, and `total_duration/1` measured the time they covered. In 2.0 `duration/1` measures the time covered, and `total_duration/1` is gone.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.IntervalSet.total_duration(bookings)
```

```elixir
iex> {:ok, bookings} = Tempo.union(~o"2026-06-15T09/2026-06-15T11", ~o"2026-06-15T10/2026-06-15T12")
iex> Tempo.duration(bookings)
~o"PT10800S"
```

> *"Two bookings, nine to eleven and ten to twelve, **cover** three hours."*

The two meanings agree for the sets the set operations return, whose members never overlap. They differ only where a set keeps overlapping members apart, as a union does. A member's own length is still `Tempo.duration/1` of that member.

## The within window

`:within` replaces `:bound` everywhere it appeared: `Tempo.to_interval/2`, `Tempo.to_interval_set/2`, the set operations, `Tempo.complement/2`, `Tempo.ICal.from_ical/2`, `Tempo.JSCalendar.from_jscalendar/2` and the RRULE expander. A leftover `:bound` is an error that names its replacement:

```elixir
iex> Tempo.to_interval(~o"R/2020-01-01/P1Y", bound: ~o"2026")
{:error, %ArgumentError{message: ":bound is not an option of Tempo.to_interval/2; pass the window as :within"}}
```

The window keeps every occurrence that overlaps it, including one already under way when the window opens — the rule calendar clients use. In 1.x an anchored recurrence read `:bound` as an upper limit and returned every occurrence from its start up to the bound. In 2.0 the window is a window:

<!-- guides:skip -->

```elixir
# 1.x — every year from 2020 up to the bound
Tempo.to_interval(~o"R/2020-01-01/P1Y", bound: ~o"2026")
```

```elixir
iex> Tempo.to_interval(~o"R/2020-01-01/P1Y", within: ~o"2026")
{:ok, #Tempo.IntervalSet<[~o"2026Y1M1D/2027Y1M1D"]>}

iex> {:ok, since_2020} = Tempo.to_interval(~o"R/2020-01-01/P1Y", within: ~o"2020/2027")
iex> Tempo.IntervalSet.count(since_2020)
7
```

> *"The yearly occurrence **within** 2026 is 2026's own. For every year since 2020, the window starts in 2020."*

iCalendar and JSCalendar imports hold to the window the same way: `Tempo.ICal.from_ical(ics, within: window)` returns only the events that overlap it, one-off events as well as recurring ones.

## Before and after share no instant

`Tempo.before?/2` and `Tempo.after?/2` answer the everyday question: is one over by the time the other starts? In 1.x they followed Allen's `:precedes`, which also needs a gap between the two, so a meeting that ends as lunch starts was not before lunch.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.before?(meeting, lunch)
#=> false
```

```elixir
iex> meeting = ~o"2026-06-15T11/2026-06-15T12"
iex> lunch = ~o"2026-06-15T12/2026-06-15T13"
iex> Tempo.before?(meeting, lunch)
true
iex> Tempo.Allen.precedes?(meeting, lunch)
false
```

> *"The meeting is **before** lunch: it is over when lunch starts. It does not **precede** lunch in Allen's sense, which needs a gap between them."*

Code that relied on the gap asks `Tempo.Allen.precedes?/2`, or `Tempo.Allen.preceded_by?/2` in place of `after?/2`. The certainty forms follow the everyday meaning too: `certainly_before?/2`, `possibly_before?/2`, `certainly_after?/2` and `possibly_after?/2`.

## Allen's relations are in Tempo.Allen

`Tempo`'s predicates are the everyday ones: `before?/2`, `after?/2`, `adjacent?/2`, `overlaps?/2`, `disjoint?/2`, `within?/2`, `contains?/2` and `equal?/2`. Allen's thirteen relations, several of whose names are narrower than the same English words, are predicates in `Tempo.Allen` under Allen's own names, beside `inverse/1` and `compose/2`. `Tempo.Allen.overlaps?/2` is Allen's strict relation, where `Tempo.overlaps?/2` holds for any shared instant.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.meets?(june, july)
Tempo.during?(midsummer, june)
Tempo.Interval.inverse_relation(:precedes)
Tempo.compose(:precedes, :during)
```

```elixir
iex> Tempo.Allen.meets?(~o"2026-06", ~o"2026-07")
true
iex> Tempo.Allen.during?(~o"2026-06-21", ~o"2026-06")
true
iex> Tempo.Allen.inverse(:precedes)
:preceded_by
iex> Tempo.Allen.compose(:precedes, :during)
[:precedes, :meets, :overlaps, :starts, :during]
```

`inverse/1` and `compose/2` also take a list of relations, for reasoning when the relation between two intervals is known only to be one of several.

## Containment and sameness have one name each

`Tempo.within?/3` takes over from `subset?/3`, and answers for any two values, sets included, by the instants they cover — as its mirror `contains?/3` always has. `Tempo.Interval.equivalent?/2` is removed; `Tempo.equal?/3` asks whether two values cover the same instants.

<!-- guides:skip -->

```elixir
# 1.x
Tempo.subset?(holidays, december)
Tempo.Interval.equivalent?(june, first_to_first)
```

```elixir
iex> {:ok, holidays} = Tempo.union(~o"2026-12-25", ~o"2026-12-26")
iex> Tempo.within?(holidays, ~o"2026-12")
true
iex> Tempo.equal?(~o"2026-06", ~o"2026-06-01/2026-07-01")
true
```

> *"Christmas and Boxing Day both fall **within** December. June is **equal** to the span from the first of June to the first of July."*

`Tempo.Interval.within?/2` stays, for a single interval: Allen's `:equals`, `:starts`, `:during` or `:finishes`.

## Metadata belongs to the value

In 1.x `Tempo.new/1`'s `:metadata` was written into the value's ISO 8601 form as IXDTF suffix tags. In 2.0 it is the caller's own data, carried with the value and read with `Tempo.metadata/1`, and the tags have their own option, `:tags`:

```elixir
iex> {:ok, christmas} = Tempo.new(year: 2026, month: 12, day: 25, metadata: %{name: "Christmas Day"})
iex> Tempo.metadata(christmas)
%{name: "Christmas Day"}
iex> Tempo.to_iso8601(christmas)
"2026Y12M25D"

iex> {:ok, tagged} = Tempo.new(year: 2026, month: 6, day: 15, tags: %{"x-source" => "hr"})
iex> Tempo.to_iso8601(tagged)
"2026Y6M15D[x-source=hr]"
```

Materialising a value moves its metadata to the interval or intervals it becomes, so a holiday's name travels with its day through the set operations.
