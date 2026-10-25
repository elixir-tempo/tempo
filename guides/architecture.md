# Architecture: the model, the engine and its contracts

This guide is Tempo's design written for a reader who is not using Elixir: someone assessing the architecture, or porting it to another language. It states the model as types and functions in a notation of no particular language, gives each algorithm in pseudo-code, names the two contracts the engine depends on (a calendar and a zone database) and what each must satisfy, lists every error the library can answer with and why, and gives the cost of each operation. It says nothing about Elixir's syntax, processes or protocols except where a choice of representation is a choice of the design.

The laws and the decisions it rests on are recorded in the project's `plans/architecture-redesign.md` and `plans/decisions.md`; the behavioural decisions are explained for users in the [Design decisions](https://hexdocs.pm/ex_tempo/design-decisions.html) guide, and the words used here have the one meaning each has in the [Glossary](https://hexdocs.pm/ex_tempo/glossary.html). The conformance fixtures a port runs are described at the end.

## Setup, required for the examples

The few examples below use the `~o` sigil, which reads ISO 8601 text into an expression.

```elixir
import Tempo.Sigils
```

## 1. The nine laws

Everything else follows from these. A behaviour that cannot be derived from them is not Tempo's.

1. **Denotation.** An *expression* is a value (`2026-06`), an interval (`2026-06-01/2026-06-20`), a recurrence (`R5/2026-06-15/P1D`), an all-of set (`{2026-06,2026-08}`) or a one-of set (`[2026,2027]`). Every expression denotes an ordered sequence of half-open spans, `spans(E)`, possibly empty, possibly infinite. A duration denotes a length and is not an expression. Every operation on an expression is defined on `spans(E)`.

2. **Half-open.** A span is `[from, to)`: its first instant is in it, its last is not. Adjacent spans concatenate without gap or overlap. No span has zero extent.

3. **Resolution is meaning.** A value written to resolution *r* denotes the one span `[v, next_r(v))`, where `next_r` is one unit of *r* later. The written units are kept as written; nothing drills into them. A span written with two ends denotes exactly that extent.

4. **Frames.** A span lies on one frame: the UTC line (it has a year and a zone or a shift), the floating line (a year, no zone, no shift), or a cycle (no year: the day for a time of day, the week for a weekday, the year for a month and day). Two spans relate, compare or combine only on one frame; otherwise the answer is a named error. A window, the `:within` option, places a cyclic expression on each period of an anchored one.

5. **One expression, one calendar, one zone.** The calendar and the zone are properties of the whole expression, written once after it. A time shift is a property of a written end. What cannot be written is an error, never another value.

6. **Enumeration.** Enumerating an expression yields what it is made of. A *singular* expression (one span) yields its children: the units one level below the resolution of a value, or the finer of its ends' resolutions for an interval. A *plural* expression yields its members, each an expression. `members(E)` gives the spans of either.

7. **One calendar question.** Tempo knows its own units, the labels a day can carry and the notations it reads and writes. It asks a calendar what span of days a period is, what date a day number is and what labels a date has, whether a date exists, and how to shift a date. It never asks what kind of calendar it is talking to, and holds no number a calendar would answer.

8. **Refusal.** What Tempo cannot answer by these laws is a named error that says why. It is never a guess, a fallback or a silently different value.

9. **Written ends.** A written interval `a/b` runs from the start of `a`. It runs to the *end* of `b` when `b` is written to a calendar unit (a year, a month, a week, a date), and to the *start* of `b` when `b` is written to a clock unit (a time of day). The struct holds the half-open span that results, every operation is defined on it, and the writer writes a span back as it was read, so that text round-trips.

```elixir
iex> Tempo.relation(~o"2026/2028", ~o"2029")
:meets
```

## 2. The data model

One type holds every expression. In a notation of sum and product types:

```text
Expression  = { form : Form, calendar : Calendar, zone : Zone?, shift : Shift?,
                qualifications : Qualifications?, metadata : Map }

Form        = Value Units
            | Span End End
            | Every Expression Bound Selection?          -- first span, how many, rule
            | All [Expression]                           -- all of several; may be lazy
            | One [Expression]                           -- one of several
            | When Expression [Condition]                -- a member with conditions

End         = Expression | Duration | Open                -- a Value, a length, or no end
Bound       = Count Int | Infinity | Until Expression

Units       = ordered list of (Unit, Held), coarsest first
Unit        = Century | Decade | Year | Quarter | Season | Month | TraditionalMonth
            | Week | DayOfYear | Day | DayOfWeek | Hour | Minute | Second | Fraction
            | Group | Selection

Held        = Whole Int                                   -- 15
            | Several [Int | Range]                       -- {1,3}, {1..5}; a negative counts from the end
            | Mask [Digit | Free]                         -- 1X; X* is Any
            | Any
            | Group nth [(Unit, size)]                    -- 2G3MU: the second group of three months
            | Significant Int digits                      -- 1950S2
            | Margin Int plusminus                        -- 2018±2
            | Leap Int                                    -- a traditional leap month
            | Selection [Part]                            -- L…N, for the unit Selection only

Part        = (Unit, Held) | Instance [Int] | Event name | Roll convention | Skip direction
            | Window (Duration | Expression) | Nested Selection | AllOf [Selection]

Duration    = ordered list of (Unit, Int)                 -- a length, not an expression
Zone        = Named name critical? | Fixed minutes
Shift       = (hours, minutes, seconds), the sign on the first that is not zero
Qualifications = Unit -> Uncertain | Approximate | Both
Calendar    = an implementation of the calendar contract (section 6.1)
```

Three things about the representation are design, not convenience.

* **Units are an ordered association, not a record.** A value is its written units in the order written, coarsest first, and no unit is filled in. `2026-06` has two units and no day; `2026Y15D` has a year and a day and a gap, which the engine fills with "any month" only when it expands the value. A port must keep the order and the absence.

* **A span's ends are expressions.** The form `Span from to` holds the two written ends as the values they were written as, and the half-open positions are derived from them (section 4). That is what lets the writer write a span back as it was read (law 9), and what lets a result of a set operation carry the resolution of the operand end it stopped at.

* **A set may be lazy.** `All` holds a list, or a stream of members that are read as they are asked for, for a set with no last member. Everything that needs every member refuses a lazy set without a window.

A duration is the one companion type. It has units and no place, and it takes part only where a length is asked: the end of a span (`2026-06-01/P1M`), the cadence of a recurrence, a shift, a measure.

## 3. Positions, frames and precision

A **position** is an integer. On a line it is a count of microseconds, called ticks, from 0000-01-01T00:00:00; on a cycle it is a count of ticks from the cycle's start (midnight for the day, the first day of week one for the week, the first day of the year's first month for the year), on the longest cycle the calendar counts, so that every value of the cycle has a place and two positions compare as integers.

A **frame** is where positions are comparable:

```text
Frame = UTCLine | FloatingLine | Cycle Unit

frame(value) = Cycle (coarsest unit)   if the value has no year
             | UTCLine                 if it has a zone or a written shift
             | FloatingLine            otherwise
```

Two spans relate, compare or combine only on one frame. A floating value beside a zoned one is an error (law 4). A span on a cycle that runs through the cycle's end (`T22/T02`) is cut into two for any sweep and joined after it.

The **precision model** is this. A tick is a microsecond, which is the finest unit ISO 8601 text in this library writes and the precision of the platform's own date and time types. Positions through the year 9999 fit in 59 bits, so they are machine integers on a 64-bit platform. A fraction of a second written in text keeps its number of places as part of the value (`{value, places}`), so that `10:30:45.5` and `10:30:45.500` are different values with the same position and are written back as they were read; law 3 then gives the first a span of a tenth of a second and the second a span of a thousandth. A port that counts nanoseconds changes one constant and the fraction's bound.

The **day scale** is the count of days from the same origin, the proleptic Gregorian day number, which is the fixed date of Reingold and Dershowitz. Every calendar converts to and from it directly; nothing converts through another calendar. A date's position on a line is its day number times the ticks in a day, plus its clock, placed through the zone.

## 4. The denotation

`spans : Expression × Options → Sequence of Span` is the meaning of any expression, and every operation reads an expression through it. The options carry a window (`within`), without which a sequence that has no end of its own is refused where every member is needed and read lazily where it is not.

```text
spans(Value units, options)
  | units hold a Selection      = the selection applied in each period the units before it name (5.4)
  | units have no year, window  = the value placed on each period of the window (5.4), then spans of each
  | units name one span         = [ the span [extent(units)] ]                        (5.1)
  | otherwise                   = spans of each value the units expand to (5.3), in order

spans(Span from to, options)
  | an end is plural            = a span for each value of that end, in order
  | otherwise                   = [ resolved(from, to) ]
      where a Duration end is placed from the other end, and an Open end by the window

spans(Every first bound rule, options)
  | rule is none                = first moved by n cadences for n = 0, 1, 2, … within bound  (5.5)
  | otherwise                   = in each period of the cadence, what the rule selects       (5.5)

spans(All members, options)     = the members' spans merged in order of start;
                                  a member marked as an exclusion removes what it covers
spans(One members, options)     = error: a one-of set has readings, not spans
spans(When member conditions)   = the member's spans, each kept, moved or dropped as the conditions say
```

The **extent** of a span is its two positions on its frame. For a written span `a/b` (law 9):

```text
extent(Span a b) = ( start(a), end(b) )
  where end(b) = stop of extent(b)   if b is written to a calendar unit (year … day)
               = start of extent(b)  if b is written to a clock unit (hour … fraction)
```

**Enumeration** (law 6) is a function of the form:

```text
children(E) | E is singular = walk(extent(E), one unit below E's resolution)   (5.2)
            | E is plural   = members(E)

members(E)  | Value with a plural unit = each value it expands to
            | All, One                 = the members
            | Every, Span              = spans(E)
```

A value is singular when every unit holds one value and each unit lies within the one before it (a month in a year, a day in a month); a written span is singular when both ends are. Anything else is plural.

## 5. The algorithms

### 5.1 The extent of a value

```text
extent(units, calendar, zone, shift):
  if the units are not anchored (no year):
      cycle position of the units (section 3), and that plus one unit of the resolution
  else:
      days      = span_of(calendar, date units)             -- the calendar contract: [first day, day after last)
      wall      = first_day × ticks_per_day + clock ticks of the clock units
      start     = place(wall)                                -- through the zone (5.7); the wall itself on the floating line
      stop      = place(after_last × ticks_per_day)          if no clock units
                = clock_end(start, one unit of the finest clock unit)   otherwise
```

`clock_end` is one unit of elapsed time, except in a named zone whose clock changes within the unit: there an hour the clock skips in part is as long as the clock shows it, and an hour the clock shows in two parts runs on through the second showing. The zone contract answers where the clock leaves a unit (section 6.2).

A value with a count from the end (`-1D`), a group, a century, a quarter or a season is first resolved to plain units through its children (5.3), then placed as above.

### 5.2 The walk

A span is walked at a unit by stepping on the scale the unit lives on. There is one rule and no special case for a change of the clock.

```text
walk((start, stop), unit, frame):
  calendar unit (year, month, week, day, quarter):
      day = the day of start on the frame's wall clock
      repeat: yield the period of `unit` that holds day (asked of the calendar); day = the day after that period
      until day is past the day of stop - 1
      a day the zone leaves out whole (a day with no reading) is not yielded
  clock unit (hour, minute, second, fraction):
      tick = start
      repeat: yield the reading of tick on the wall clock, to `unit`; tick = where the clock leaves that unit
      until tick >= stop
      a reading the clock shows twice is yielded twice, the second with the shift it has then
```

A day across a change of the clock has 23 or 25 hours because its two ends are 23 or 25 hours apart; nothing is skipped or doubled by hand. The count of clock units in a span is closed-form where the clock keeps one offset through it.

### 5.3 Expansion

Expansion gives every concrete value a value's units allow, in order, coarsest unit first. It is the one engine for a set in a unit, a mask, a count from the end, a group, a gap between units, and the parts of a selection and of an RRULE.

```text
expand(units, frame):
  units = units with gaps filled by Any (a day after a year gets "any month" between)
  values of the first unit from what it holds (a year, a decade, a century name their own values)
  for each later (unit, held), in order:
      for each prefix found so far:
          candidates = children(prefix, unit)       -- the values `unit` takes under the prefix
          keep those `held` selects (5.3a), each appended to the prefix

children(prefix, unit):
  calendar unit or label under an anchored prefix:
      walk the prefix's span of days period by period (as 5.2), reading each period's number
      from the calendar; a day's label is counted within its period from one question
      (a day of the year from the year's first day, a weekday round the week, a day of the
      month from the month's first label where the month's labels count its days, and
      asked day by day where a calendar leaves labels out as it changes)
  clock unit under an anchored prefix:
      the ticks of the prefix's extent stepped at the unit (as 5.2)
  any unit under a prefix with no year:
      the values every year has alike (from the calendar's bounds), else an error (needs a year)

select(held, candidates):                                       -- 5.3a
  Whole n          -> those numbered n            (negative: the nth from the end)
  Several members  -> each member, ranges included, in the order written
  Mask digits      -> those whose number matches the mask digit by digit
  Any              -> all
  Group nth size   -> the candidates in groups of `size`, the nth group
```

Two shortcuts are exact and are the only ones: a month of a year or a day of a month named by number is asked of the calendar directly, and a reading of the clock named by number (`T17H`) is found by arithmetic where the clock keeps one offset through the prefix. Everything else walks.

### 5.4 Selection

A selection (`L…N` in ISO 8601-2; what an RRULE, a cron expression and a JSCalendar rule lower to) is parts applied in a period. The period is the units written before the selection, or each period of a window, or each period of a base for `select(base, selector)`.

```text
in_period(period, parts):
  split the parts into: those before a nested selection, the nested selection with its window, those after
  scopes  = the period, or each value the parts before select in it
  windows = the scopes, or a span of the window's length from each value the nested selection picks
  in each window:
      candidates = expand(container units ++ unit parts) kept within the window,
                   the container being the unit the coarsest part counts in
                   (days in their month, weeks in their year, the clock in its day)
      plus the replacements a Skip names for a date the year lacks
      filtered by the years named, moved by a Roll to a weekday, sorted by start,
      a reading shown twice kept at its first showing
      then Instance picks the nth of the candidates, negative from the end
```

A selection on a period of one day asks of that day whether it is one the parts name, and expands nothing. A rule whose parts are whole numbers and lists of months, days of the month and days of the week, with or without positions, is compiled once to a test of a day number and taken in front of the engine in each period of a day or coarser: the calendar is asked once a month and once a period, and each day that passes is given each reading the rule names. The engine remains the meaning of every rule, and the matcher is held to it by the conformance fixtures; it leaves to the engine any rule it cannot compile and any month whose labels do not count its days. A set of selections (`L{1K2I,3K2I}N`) picks what each picks, once each, in time order, and an instance after the set counts among all of them.

### 5.5 The recurrence walk and why it ends

A recurrence `Every first bound rule` is its first span moved by whole cadences. The nth occurrence is the first shifted by n cadences in one step, never the previous plus one, so a monthly cadence from the 31st lands on the last day of every month. A span written with a length is one of a series of consecutive spans, each ending where the next begins.

With a rule, the cadence's periods are the repeating intervals (RFC 5545's weeks and months; ISO 8601-2's eligible intervals), each aligned to its unit, and the rule selects in each (5.4). The units of the start finer than the rule's finest unit are inherited by the rule. A count counts the occurrences selected; an until bounds them inclusively, as a date read through and as a time of day the last to start on it.

The walk ends, which a port must be able to argue for:

* A count or an until ends it directly, and a window ends it at the window's end.

* With none of those, a period of a day or finer in which the rule selects nothing is followed by the next for two periods, and then the walk looks ahead to where the rule's parts next name a value, a year, a month or a day at a time. A rule that repeats by an interval of several units selects in the first unit of each period, so its look-ahead names only a value in a period's first unit, placing each period it passes once.

* The look-ahead has a horizon: two years for a rule that names times of day alone (a zone's clock changes by the year), and otherwise a full cycle of the calendar's years (four hundred in the Gregorian), in which every date and weekday the rule could name has come round, or a thousand years in a calendar with no cycle. A rule that repeats by an interval of `n` units, `u` of them to such a span (to a day, for a rule of times of day by hours, minutes or seconds), selects in other units in each span than in the last until its periods come round, so it is walked `n / gcd(n, u)` spans: seven Gregorian cycles for every seventh month, one for every third. Where the units cannot be counted it is walked `n` spans, and in a calendar with no cycle a thousand years `n` times over. A rule that selects nothing within its horizon has no more occurrences, and the sequence ends.

Occurrences are made with the positions the walk found them at, and the start of each next period is handed from the period that reckoned it, so no occurrence is placed twice.

### 5.6 Set operations: one sweep

Every instant-level set operation is one sweep over the sorted ends of the operands' spans, asking at each position how many spans of each operand cover the point after it.

```text
sweep(a, b, keep):                                 -- a, b: lists of (start, stop, span, side)
  edges = for each span: (start, Open, side, span), (stop, Close, side, span)
  group the edges by position, in order of position
  covering = {a: [], b: []}; open = none; results = []
  for each position, with its edges:
      apply every close and open at the position to `covering`
      now = keep(count of covering.a, count of covering.b)
      if open is none and now:   open = (position, the operand end that opened here, covering members)
      if open and not now:       results += (open.start, position, …); open = none
      if open and now, by member: where the member credited with the result has ended,
                                   close the result here and open another credited to the members covering now
  return results

intersection(a, b)        = sweep(a, b, (da, db) -> da > 0 and db > 0)
difference(a, b)          = sweep(a, b, (da, db) -> da > 0 and db == 0)
symmetric_difference(a,b) = sweep(a, b, (da, db) -> (da > 0) != (db > 0))
covered(a, k)             = sweep(a, [], (da, _)  -> da >= k)          -- points covered by at least k members
union(a, b)               = the members of both, each once, in order of start   -- member-preserving
coalesce(a)               = covered(a, 1)
```

A result begins where `keep` turns true and ends where it turns false, so a result's ends are always operands' ends, and each is written back as the operand end that stands there wrote it, at its resolution: the difference of a month and a day ends on a day. Each result is credited to the operand members that cover it, so it carries their metadata. A result that opens and closes at one position has no length and is none.

Operands come to the sweep on one frame: the second operand is brought to the first's calendar; two zoned operands meet on the UTC line and the result is written in the first's zone; a floating operand beside a zoned one is an error unless placed. An operand with no end is bounded by the window, or by the other operand where the operation's result lies within it (an intersection; a difference from a bounded first operand); a union of two endless operands is itself endless and is given as a stream in time order; any other operation on two endless operands is refused without a window.

The everyday predicates are defined on covered time: `within?(a, b)` is that `difference(a, b)` is empty, `overlaps?(a, b)` that `intersection(a, b)` is not, `before?(a, b)` is that `a` ends no later than `b` begins, `adjacent?` that the coalesced forms meet, `equal?` that they cover the same points. For two single spans they coincide with the relation sets of 5.7.

### 5.7 Allen's relations: four comparisons, and a derived table

The relation of two spans is read from four integer comparisons: start against start, end against end, the first's end against the second's start, the first's start against the second's end. Every pair of spans stands in exactly one relation.

```text
relation((a_from, a_to), (b_from, b_to)):
  ss = compare(a_from, b_from); ee = compare(a_to, b_to)
  es = compare(a_to, b_from);   se = compare(a_from, b_to)
  es == LT  -> precedes        es == EQ  -> meets
  se == GT  -> preceded_by     se == EQ  -> met_by
  (ss, ee) = (LT, LT) -> overlaps     (LT, EQ) -> finished_by   (LT, GT) -> contains
             (EQ, LT) -> starts       (EQ, EQ) -> equals        (EQ, GT) -> started_by
             (GT, LT) -> during       (GT, EQ) -> finishes      (GT, GT) -> overlapped_by
```

```elixir
iex> Tempo.Allen.relation({1, 3}, {3, 5})
:meets
```

The composition table (given `A r1 B` and `B r2 C`, the relations `A` may stand in to `C`) is not transcribed. It is derived when the library compiles by placing three spans every way on eight points (six endpoints need at most six distinct values, so the enumeration is complete) and classifying each pair with the function above; it is then held by test to Allen's published table. The classifier and the table therefore cannot disagree, and a port derives its table the same way.

```elixir
iex> Tempo.Allen.compose(:overlaps, :overlaps)
[:precedes, :meets, :overlaps]
```

The predicate vocabulary is one table of relation sets: before is `{precedes, meets}`, after `{met_by, preceded_by}`, adjacent `{meets, met_by}`, within `{equals, starts, during, finishes}`, contains `{equals, started_by, contains, finished_by}`, disjoint `{precedes, meets, met_by, preceded_by}`, overlaps the rest, equal `{equals}`.

The **certainty** of a relation between uncertain expressions (a year with a margin, a mask, a one-of set) asks the relation of every reading of one against every reading of the other: `certain` when every pair stands in a relation of the predicate's set, `impossible` when none does, `possible` otherwise.

### 5.8 Arithmetic: one shift

An expression is moved by a duration at the position of its start, and written back at the moved position on its own axis and at its own resolution, extended to the duration's finest unit where that is finer (a year a day on is its second day).

```text
shifted(position, duration, frame):
  date part (years, months, weeks, days):
      day    = the day of position on the frame's wall clock
      moved  = shift_date(calendar, day, years, months, weeks + days)     -- years, then months with the day clamped, then days
      if the zone leaves `moved` out whole, the day after it (or before, going back)
      position = place(moved × ticks_per_day + the clock part of the wall reading)
  clock part (hours, minutes, seconds, fraction):
      position = position + the clock part in ticks                      -- elapsed time, through a change of the clock
```

A week date stays a week date and an ordinal date an ordinal date. A value with no year is shifted in each of a run of sample years and is the one answer they agree on, or an error where they disagree. A value with a set in a unit is each value it names shifted, gathered back into one value where its units can hold them. Truncating, rounding and extending to a unit are written on the same positions.

### 5.9 Reading and writing

The reader is one function per production of the written grammar ([ISO 8601 grammar](https://hexdocs.pm/ex_tempo/iso8601-grammar.html)): the text is split at the places the grammar makes structural (the suffix, a leading `R`, the `/` of an interval outside braces, the braces of a set), each piece is read by its form, and the result is validated once against the calendar and the zone (every unit in range, every date existing, no reading the clock skips, ends ordered, one calendar and one zone). The writer is its inverse, and `write(read(text)) == text` for every text the grammar accepts, up to the one normalisation the grammar allows (`2026-06-15` and `2026Y6M15D` are one value). A written end read through (law 9) is written back as it was read.

## 6. The contracts

### 6.1 The calendar

Tempo asks a calendar eighteen questions and no other. It never asks what kind of calendar it is talking to.

| Group | Question | Answers |
|---|---|---|
| Day scale | `date_to_iso_days(year, month, day)` | the day number of a date |
| Day scale | `date_from_iso_days(day)` | the `(year, month, day)` of a day number |
| Validity | `valid_date?(year, month, day)` | whether a date exists |
| Periods | `year(year)` | the range of days of a year, or an error |
| Periods | `month(year, month)` | the range of a month, or an error |
| Periods | `week(year, week)` | the range of a week of the calendar's own week-year, or an error |
| Periods | `quarter(year, quarter)` | the range of a quarter, or an error |
| Periods | `weeks_of_month(year, month)` | the ranges of the weeks a month has |
| Labels | `day_of_week(year, month, day)` | 1 to 7, from the day the calendar's weeks begin on |
| Labels | `week_of_year(year, month, day)` | `(week_year, week)` in the calendar's own weeks |
| Arithmetic | `shift_date(year, month, day, duration)` | the date moved: years, then months with the day clamped, then days |
| No year | `months_in_year_bounds()` | the fewest and the most months any year has |
| No year | `days_in_month_bounds(month)` | the fewest and the most days the month has in any year |
| Names | `cldr_calendar_type()` | the CLDR name, for IXDTF and for words |
| Names | `traditional_month(year, month)` | the month as the calendar names it, `n` or `(n, leap)` |
| Names | `month_from_traditional(year, named)` | the inverse |
| Accessors | `leap_year?(year)`, `quarter_of_year(year, month, day)` | forwarded to the user unchanged |

Every answer is a day number, a tuple of numbers, a range of day numbers or a label; never a date of the calendar's own type. A value's calendar is what the caller gave, from construction to output.

A calendar must satisfy these laws, which Tempo relies on in place of knowing the calendar's kind:

1. **Round trip.** `date_from_iso_days(date_to_iso_days(y, m, d)) == (y, m, d)` for every valid date.
2. **Order.** For valid dates, `date_to_iso_days` is strictly increasing in the lexicographic order of `(y, m, d)`.
3. **Tiling.** The months of a year, found by walking `year(y)` on the day scale through `month`, cover the year exactly, with no gap and no overlap; the weeks of a week-year likewise through `week`; a day belongs to exactly one month and one week.
4. **Labels agree with periods.** `week_of_year(y, m, d) == (wy, w)` exactly when the day is in `week(wy, w)`; `day_of_week` runs 1 to 7 over any seven consecutive days.
5. **Absence is an error.** `month`, `week` and `quarter` return an error for a period the calendar does not have, never a range of another period.
6. **Bounds.** The bounds are the minimum and maximum over the calendar's years; a value within the minimum exists in every year.
7. **Shift.** `shift_date` returns a valid date, applies years then months then clamps the day then adds days, and a shift of zero is the identity.

In this implementation every calendar question goes through one adapter module, which is the one place that names which module answers for the platform's own calendar; the calendars themselves are Calendrical's, and every calendar calculation (a month's length, a leap year, a solar term, Easter) is made there and never in Tempo. A port keeps the same boundary: the contract above, one adapter, no calendar arithmetic of its own.

### 6.2 The zone

A zone is a name the zone database knows or a fixed offset. Tempo asks of a named zone:

| Question | Answers |
|---|---|
| `offset_at_utc(zone, tick)` | the offset in force at a UTC tick |
| `offsets_at_wall(zone, wall)` | the offsets a wall reading is shown at: one; two for a reading the clock shows twice, earliest showing first; none, with the offsets before and after the change, for a reading the clock skips |
| `first_shown(zone, wall)` | the UTC tick at which the clock first shows a reading, or where it comes out of the gap that skips it |
| `unit_end(zone, tick, step)` | where the clock leaves the unit of `step` ticks it is showing at `tick` |
| `steady_offset(zone, start, stop)` | the one offset the clock keeps through a span, or that it changes |
| `days_skipped(zone, first, after_last)` | the days of a span the clock leaves out whole |

Every one of these is answered from a **table of the zone's changes**: the UTC ticks at which the offset changes, ascending, with the offset in force from each. The table is built once for a zone and shared; every question is a binary search in it and a walk of the few changes about the tick asked for. Java's `ZoneRules`, the `Temporal` proposal's time zones and Rust's `chrono-tz` are the same structure.

The table is exact where the database lists its periods, which Tempo asks for through one optional question beside the platform's point-wise database: *the changes of a zone's offset, earliest first, and the instant from which the database makes its periods from a rule rather than its list*. Where the database lists nothing, or beyond its list, the changes are found by sampling the offset six days apart and halving between two samples that differ, on the one stated assumption that a rule-made period changes at most once between two samples (no zone's rule changes its clock twice within a week). A reading the clock skips is refused when a value is built; a reading the clock shows twice is read at its first showing unless a written shift says which.

## 7. Refusal: the errors

Every function that can fail returns an error value; a predicate, an accessor and a comparison answer a bare value and raise theirs, so that an error is never read as an answer. There are nine errors, and each carries the reason it was given.

| Error | Reason it carries | When |
|---|---|---|
| `ParseError` | what was expected or refused, and where in the text | text the grammar does not accept, or a suffix written inside an expression |
| `InvalidDateError` | the unit and why: out of range, no such date, skipped by the clock | a value the calendar or the zone has no reading for |
| `IntervalEndpointsError` | order, two calendars, two zones | an interval whose ends cannot be one expression (law 5) |
| `FrameError` | the two expressions and the frame each lies on | two expressions related or combined across frames (law 4) |
| `ZoneError` | unknown, no database, gap, mixed, critical, inconsistent | a zone the database lacks, a reading in a gap, a shift that disagrees with its zone |
| `InvalidCalendarError` | the calendar | a module that is not a calendar, or one that IXDTF cannot name |
| `ConversionError` | needs a year, open, unbounded, several, no such value, one of, bare duration, not an expression, too many values, among others | what the laws give no answer for: a value with no year asked where it lies, a sequence with no end asked for all of it, a one-of set asked for its spans, more values than the bound on work |
| `Iso8601EncodeError` | the reason | a struct built by hand that the grammar cannot write |
| `ClockError` | not pinned | the test clock asked the time in a process that has set none |

The bound on work is one number, read in one place: an enumeration or conversion that would yield more than it is refused whole with `too_many_values`, never cut short, which would answer for part of what was asked.

## 8. The cost of an operation

Positions are computed once per end and compared as integers; calendars and zones are consulted only to compute positions.

| Operation | Cost | Asks the calendar | Asks the zone |
|---|---|---|---|
| place a value (5.1) | O(units) | one period or one date | once or twice per end |
| relation, compare, the predicates of two single spans | O(1) after placing | | |
| a set operation of m and n spans (5.6) | O((m + n) log(m + n)) | | |
| walk a span at a unit (5.2) | O(k) for k values yielded | one period per value | once per clock unit, at most |
| expand a value (5.3) | O(size of the result), with a walk per plural unit | one period per candidate | per clock candidate |
| a rule's occurrences (5.5) | O(periods walked × candidates per period) | per candidate | per candidate |
| read or write text (5.9) | O(length of the text), plus one validation pass | per unit validated | once per zoned reading |
| the relation of two uncertain expressions | O(readings of one × readings of the other) | | |

A span is placed once: the engine hands every span on as `(start, stop, written span)`, made where the span is made, and the written span alone crosses to the public layer. What a port will want to optimise next is the placing of *values* inside expansion and selection, where a candidate is built from its units and placed to be judged; this implementation hands a candidate's extent on where expansion found it and places the rest.

## 9. What is Tempo's and what is not

Tempo is the representation and selection layer: the written grammar, the forms, the frames, the walk, expansion, selection, the sweep, the relations, the shift, the errors. It holds no number a calendar or a zone database would answer: no month length, no leap rule, no transition. Calendar calculations are the calendar's (here Calendrical's), zone data is the database's, and the words of a locale are Localize's. A port that keeps those three seams keeps the architecture.

## 10. Conformance

The library is held to oracles written apart from it, and those oracles are exported as fixtures a port can run from its own test suite, under `test/fixtures/conformance/` in the repository, each with a README of its shape:

* `allen.json`: the thirteen relations with a pair of spans for each, and the 169 cells of the composition table.

* `set_operations.json`: every pair of sets of up to two members between five points of a line, with the covered cells of each operation, and the lines (days, hours, hours in two zones, days in two calendars) the points stand on.

* `rrule.json`: 192 recurrence rules from three starts, each with the occurrences an expander written to RFC 5545 section 3.3.10 gives, beside the standard's own examples.

* `clock_changes.json`: the hours a zone's clock shows on each of twenty-two days on which it changes, as the platform's own date and time say.

* `expressions.json`: every expression of a corpus written by hand against every operation, with every cell that refuses and the name and reason of its error; every other cell answers with a value.

* `census.json`: a value in each full form, each value with no year, each shape and each selection in 27 calendars, with the positions each covers, its walk yields or it selects, worked out from the calendar alone.

* `guides.json`: every call the guides' examples make, with its arguments and its answer, for a port's own examples to be held to.

Tempo's own tests read the same files, and a script regenerates them from the oracles, so the two cannot drift.
