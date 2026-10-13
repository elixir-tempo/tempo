# Pattern matching with sigils

The `~o"..."` sigil does double duty. In an expression it reads an ISO 8601 text, at compile time, into the `%Tempo{}` or `%Tempo.Duration{}` the text names. In a **pattern** — on the left-hand side of `match?/2`, a `case` clause, a bare `=`, or a function head — the same sigil is a *structural pattern* for values of that shape.

This guide is the complete specification of the sigil in a pattern. For its everyday use in an expression, see the module docs for `Tempo.Sigils`.

## The mental model

In an expression, `~o"2026"` **produces** the whole of 2026. In a pattern, `~o"2026"` **recognises** any value written in 2026: the year, a month of it, a day of it, a minute of it. The text is the same; its meaning shifts with where you put it.

```elixir
iex> import Tempo.Sigils
iex> year = ~o"2026"
iex> match?(~o"2026", year)
true

iex> match?(~o"2026", ~o"2026-06-15T10:30")
true
```

> *"The pattern **2026** recognises anything written in 2026."*

The pattern is deliberately **permissive**: it constrains only the units the text writes. The calendar, the zone, a time shift, a qualification and the metadata of the value are left free. The intent is temporal — "did the year, the month and the day line up?" — not structural equality. When you want equality, use `==`.

## Values match by their leading units

A value's units run from the coarsest to the finest, and the pattern is those units *and then anything*. So a sigil of fewer units matches every value that **begins with** them:

```elixir
iex> today = ~o"2026-04-24"
iex> match?(~o"2026", today)
true

iex> match?(~o"2026-04", today)
true

iex> match?(~o"2026-04-24", today)
true

iex> match?(~o"2026-01", today)
false

iex> match?(~o"2025", today)
false
```

> *"**Today** is in 2026, in April 2026, and is the 24th of April 2026. It is not in January, and it is not in 2025."*

The text may be in either of ISO 8601's notations, because both read to the same value:

```elixir
iex> match?(~o"2026Y4M", today)
true
```

### The other fields are free

Because the pattern is of the units alone, a value in a zone or with a qualification matches as its bare twin does:

```elixir
iex> match?(~o"2026-06-15", ~o"2026-06-15T10:00[Europe/Paris]")
true

iex> match?(~o"2026-06", ~o"2026-06-15?")
true
```

The calendar is free too, which means the *numbers* are what match: a pattern of the year 5786 recognises a Hebrew date of that year, and would as readily recognise a Gregorian one. A pattern is no place to ask which calendar a value is in — match on `%Tempo{calendar: Calendrical.Hebrew}` beside it when that matters.

```elixir
iex> match?(~o"5786", ~o"5786-07-15[u-ca=hebrew]")
true
```

### Dates of weeks, ordinal dates and times of day

A value written by week (`2026-W17-5`) or by day of the year (`2026-114`) keeps the units it was written in, and so does its pattern. A week pattern recognises the days of that week *written by week*; it does not recognise the same days written by month.

```elixir
iex> match?(~o"2026-W17", ~o"2026-W17-5")
true

iex> match?(~o"2026-W17", today)
false

iex> match?(~o"T14", ~o"T14:30")
true
```

To ask whether a value lies in a week, a month or any other span however either is written, ask the question of the time line rather than of the text:

```elixir
iex> Tempo.within?(today, ~o"2026-W17")
true
```

> *"The 24th of April **is within** week 17, though it was not **written** in week 17."*

### Durations

A duration matches the same way, by the units it begins with, and a duration pattern never matches a value nor a value pattern a duration:

```elixir
iex> match?(~o"P1Y6M", ~o"P1Y6M")
true

iex> match?(~o"P1Y", ~o"P1Y6M")
true

iex> match?(~o"P2Y", ~o"P1Y6M")
false

iex> match?(~o"P1Y6M", today)
false
```

## Intervals, sets and recurrences match exactly

An interval, a set and a recurrence have no single run of units to begin with, so their pattern is the form the text names, whole: the same ends, the same members in the same order, the same rule.

```elixir
iex> match?(~o"1984/2004", ~o"1984Y/2004Y")
true

iex> match?(~o"1984/2004", ~o"1984/2005")
false

iex> match?(~o"1984/..", ~o"1984/..")
true

iex> match?(~o"R5/2026-01-01/P1D", ~o"R5/2026-01-01/P1D")
true
```

A set is one of its members (`[a,b,c]`) or all of them (`{a,b,c}`), and the two never match each other. Write a set with the string delimiters `~o"…"`, since its text begins with a bracket:

```elixir
iex> match?(~o"[1984,1986,1988]", ~o"[1984,1986,1988]")
true

iex> match?(~o"{1984,1986,1988}", ~o"[1984,1986,1988]")
false
```

The ends of an interval are whole values, and they match whole — their zone and their calendar with them. An interval in Paris is not the interval with no zone:

```elixir
iex> match?(~o"2026-06-15T09/2026-06-15T17", ~o"2026-06-15T09/2026-06-15T17[Europe/Paris]")
false
```

For anything looser than "exactly this interval", the relations say it better than a pattern can:

```elixir
iex> Tempo.within?(~o"1984-10/1984-12", ~o"1984")
true

iex> Tempo.within?(~o"1984-10/1985-03", ~o"1984")
false
```

> *"The last quarter of 1984 **is within** 1984. An interval that runs on into 1985 is not."*

## Reading the parts of a matched value

The sigil takes no modifiers and binds no variables: it recognises. What a matched value holds is read with the functions that name each part.

```elixir
iex> case today do
...>   ~o"2026" -> {Tempo.month(today), Tempo.day(today)}
...> end
{4, 24}

iex> Tempo.day_of_week(today)
5
```

> *"When **today** is in 2026, give its **month** and its **day**."*

A part the value was not written to is `nil`, and `Tempo.resolution/1` names the finest unit that was written, which is what a clause for each precision dispatches on:

```elixir
iex> Tempo.day(~o"2026-04")
nil

iex> Tempo.resolution(~o"2026-04")
:month
```

## Function heads and case clauses

A pattern earns its keep in a function head, where the clauses read as a table from the most particular to the least:

```elixir
iex> quarter_end? = fn
...>   ~o"2026-03" -> true
...>   ~o"2026-06" -> true
...>   ~o"2026-09" -> true
...>   ~o"2026-12" -> true
...>   %Tempo{} -> false
...> end
iex> quarter_end?.(~o"2026-06-30")
true

iex> quarter_end?.(today)
false
```

> *"A value **closes a quarter** when it is in March, June, September or December of 2026."*

Clauses are tried in the order written, and a coarser pattern matches everything a finer one does, so write the finer first:

```elixir
iex> describe = fn
...>   ~o"2026-04-24" -> "the day itself"
...>   ~o"2026-04" -> "that month"
...>   ~o"2026" -> "that year"
...>   %Tempo{} -> "another year"
...> end
iex> Enum.map([~o"2026-04-24T09", ~o"2026-04-01", ~o"2026-11", ~o"2027"], describe)
["the day itself", "that month", "that year", "another year"]
```

## Guards

A sigil is a pattern, and a pattern cannot be written in a `when` clause: Elixir admits only its own guard expressions there. Match in the function head or the clause, and keep the guard for what a guard can test.

<!-- guides:skip -->
```elixir
# Not allowed: match?/2 is not a guard.
def summer?(value) when match?(~o"2026-06", value), do: true

# The pattern is the head.
def june?(~o"2026-06"), do: true
def june?(%Tempo{}), do: false

# Or a comparison, when you want equality and not a leading match.
def exactly_june?(value), do: value == ~o"2026-06"
```

## Errors at compile time

The sigil's text is read when the module compiles, so these are compile errors that name the text, not matches that quietly fail:

* **A text that cannot be read.** `~o"2026-13"` has no thirteenth month and `~o"2026-02-30"` no thirtieth of February.

* **A modifier.** `~o"2026"D` — the sigil takes none.

* **An interpolation.** `~o"#{year}-06"` — the text must be a literal. Build a value from parts with `Tempo.new/1`, or read a text with `Tempo.from_iso8601/2`.

## What a pattern deliberately does not do

* **It does not bind.** Read a part with `Tempo.year/1`, `Tempo.month/1`, `Tempo.day/1` and the rest.

* **It does not match stdlib types.** `~o"…"` is a pattern for a `%Tempo{}` and cannot match a `%Date{}`, `%Time{}`, `%NaiveDateTime{}` or `%DateTime{}`. Use the stdlib sigils `~D`, `~T`, `~N` and `~U` for those, or convert with `Tempo.from_elixir/2` before matching.

* **It does not compare.** A pattern asks how a value was *written*. Whether one span is before, within or across another is a question for `Tempo.relation/2` and the predicates built on it — `Tempo.within?/2`, `Tempo.overlaps?/2`, `Tempo.contains?/2`.

## A worked example

Sorting a list of publication dates of mixed precision into the decade's years, by pattern alone:

```elixir
iex> in_1984? = &match?(~o"1984", &1)
iex> Enum.filter([~o"1984", ~o"1990-03", ~o"1984-10-12", ~o"1985-01"], in_1984?)
[~o"1984Y", ~o"1984Y10M12D"]
```

> *"Keep the dates **written in 1984**, whatever their precision."*

And the same question of intervals, where it is one of extent rather than of text:

```elixir
iex> published_in_1984? = &Tempo.within?(&1, ~o"1984")
iex> Enum.filter([~o"1984-01/1984-06", ~o"1990/1991", ~o"1984-10/1985-03"], published_in_1984?)
[~o"1984Y1M/6M"]
```

> *"Keep the intervals that lie **within 1984**."*
