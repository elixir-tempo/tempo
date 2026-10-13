# One form for ISO 8601 and RFC 5545 RRULE

Tempo reads two otherwise unrelated notations for a recurrence into the same expression:

* **ISO 8601-2**, whose repeating interval (`R…/…`) and repeat rule (`F…`) are part of the big, descriptive standard Tempo is built around.
* **RFC 5545 RRULE**, the tight recurrence-rule language of iCalendar.

This guide says what the two have in common, where each says something the other cannot, and what Tempo does at those edges.

In short:

* A rule and an ISO 8601-2 recurrence that mean the same thing **are the same value**. There is no RRULE struct: `Tempo.RRule.parse/2` returns the `%Tempo{}` that `Tempo.from_iso8601/2` returns for the equivalent text.
* ISO 8601 says **far more** than RRULE: uncertainty, unspecified digits, sets, open ends, other calendars, events such as Easter. None has an RRULE form.
* RRULE leaves to its `DTSTART` what it does not say. ISO 8601-2 has no implicit selection, so the reader **states** what the rule took from its start.
* What one notation cannot write is an **error that says why**, never a rule that means something else.

## Setup — required for every example

```elixir
import Tempo.Sigils
```

## The same value

```elixir
iex> {:ok, from_rrule} = Tempo.RRule.parse("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2026-01-01")
iex> {:ok, from_iso} = Tempo.from_iso8601("R/2026-01-01/P1M/FL1K2IN")
iex> from_rrule == from_iso
true

iex> Tempo.to_iso8601(from_rrule)
{:ok, "R/2026Y1M1D/P1M/FL1K2IN"}

iex> Tempo.RRule.to_string(from_iso)
{:ok, "FREQ=MONTHLY;BYDAY=2MO"}

iex> Enum.take(from_iso, 3)
[~o"2026Y1M12D/2026Y1M12D", ~o"2026Y2M9D/2026Y2M9D", ~o"2026Y3M9D/2026Y3M9D"]
```

> *"The **second Monday** of **every month** from the start of 2026 — read from either notation, written to either, and walked as one."*

## What the two share

Both describe a recurrence by four things, and a recurrence holds each of them once:

| | ISO 8601-2 | RRULE |
|---|---|---|
| **Start** — where the recurrence counts from | the first end of the interval, `2026-01-01/…` | `DTSTART`, which is beside the rule and not in it (`:from`) |
| **Cadence** — how far from one period to the next | the duration, `P1M`, `P2W` | `FREQ` and `INTERVAL` |
| **Bound** — how many, or until when | the count `R5`; Tempo also writes an end after the cadence, `R/2026-06-01/P1D/2026-06-10` | `COUNT`, or `UNTIL` |
| **Rule** — which values of each period are taken | the selection after `F`, between `L` and `N` | the `BY…` parts |

```elixir
iex> Tempo.RRule.parse!("FREQ=DAILY;COUNT=10", from: ~o"2026-06-01")
~o"R10/2026Y6M1D/P1D"

iex> Tempo.RRule.parse!("FREQ=DAILY;UNTIL=20260610", from: ~o"2026-06-01")
~o"R/2026Y6M1D/P1D/2026Y6M10D"

iex> Tempo.RRule.to_string(~o"R5/2026-06-15/P2W")
{:ok, "FREQ=WEEKLY;INTERVAL=2;COUNT=5"}
```

ISO 8601 bounds a repeating interval by its count alone. The end after the cadence is Tempo's extension to the text, so that a rule with an `UNTIL` has text that reads back; the [grammar guide](iso8601-grammar.md) lists it with the other extensions.

### The parts of a rule

Each `BY…` part is a unit of the selection, and they are written in the same order, coarsest first:

| RRULE | Selection | Example |
|---|---|---|
| `BYMONTH=11` | `11M` | |
| `BYWEEKNO=20` | `20W` | |
| `BYYEARDAY=45` | `45O` | |
| `BYMONTHDAY=13` | `13D` | |
| `BYDAY=MO,WE,FR` | `{1,3,5}K` | |
| `BYHOUR=9;BYMINUTE=30` | `T9H30M` | |
| `BYSETPOS=-1` | `-1I` | the position, applied last (ISO 8601-2 §12.9) |
| `BYDAY=2MO` | `1K2I` | a numbered weekday is the weekday and its position |

```elixir
iex> last_weekday = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", from: ~o"2026-01-01")
iex> Tempo.to_iso8601(last_weekday)
{:ok, "R/2026Y1M1D/P1M/FL{1,2,3,4,5}K-1IN"}

iex> Enum.map(Enum.take(last_weekday, 3), &Tempo.Interval.from/1)
[~o"2026Y1M30D", ~o"2026Y2M27D", ~o"2026Y3M31D"]
```

> *"Of each month's **weekdays**, the **last**."*

A weekday beside a day of the month is a filter, as RFC 5545's Note 1 has it: `BYMONTHDAY=13;BYDAY=FR` is `13D5K`, a thirteenth that is a Friday.

### Where a rule picks its values

A rule picks in the whole calendar period of the cadence's unit that holds each step: the day for a daily cadence, the month for a monthly one. That is how RFC 5545 evaluates its `BY…` parts and ISO 8601-2 §13.4 its eligible intervals. The start only says which periods, and nothing before the start is an occurrence. So a value can fall before its step where the start is not at the top of its period:

```elixir
iex> every_other_day = Tempo.RRule.parse!("FREQ=DAILY;INTERVAL=2;BYHOUR=9", from: ~o"2026-01-05T12")
iex> Tempo.to_iso8601(every_other_day)
{:ok, "R/2026Y1M5DT12H/P2D/FLT9HN"}

iex> Enum.map(Enum.take(every_other_day, 3), &Tempo.Interval.from/1)
[~o"2026Y1M7DT9H", ~o"2026Y1M9DT9H", ~o"2026Y1M11DT9H"]
```

> *"**Nine o'clock** on **every other day** from noon on the 5th: the 7th, the 9th, the 11th. Nine on the 5th is before the start."*

## What a rule takes from its start

RFC 5545 lets a rule leave to `DTSTART` what it does not say. ISO 8601-2 has no implicit selection, and its Annex C.4 has a converted rule state each part. `Tempo.RRule.parse/2` does so:

```elixir
iex> Tempo.RRule.parse!("FREQ=WEEKLY", from: ~o"2026-06-02")
~o"R/2026Y6M2D/P1W/FL2KN"

iex> Tempo.RRule.parse!("FREQ=MONTHLY", from: ~o"2026-01-31")
~o"R/2026Y1M31D/P1M/FL31DN"

iex> Tempo.RRule.parse!("FREQ=YEARLY", from: ~o"2026-03-10")
~o"R/2026Y3M10D/P1Y/FL3M10DN"
```

> *"Weekly from a **Tuesday** is every Tuesday. Monthly from the **31st** is every 31st. Yearly from the **10th of March** is every 10th of March."*

The stated rule is what `Tempo.RRule.to_string/1` writes back — `FREQ=WEEKLY;BYDAY=TU`, `FREQ=MONTHLY;BYMONTHDAY=31` — which RFC 5545 reads as the rule it was. A time of day in the start is kept by each occurrence without being stated, and a rule that names a week and no day of it takes the day of the week its start falls on.

Stating the day is also where the two notations part, as they should. A day selected is passed over in a month that lacks it, so the rule read from `FREQ=MONTHLY` on the 31st of January gives the months of 31 days, as RFC 5545 has it. The ISO 8601 recurrence with no rule is another thing: its start and then *n* months on, the last day of a shorter month among them, each occurrence a month long.

```elixir
iex> monthly_rule = Tempo.RRule.parse!("FREQ=MONTHLY", from: ~o"2026-01-31")
iex> Enum.map(Enum.take(monthly_rule, 3), &Tempo.Interval.from/1)
[~o"2026Y1M31D", ~o"2026Y3M31D", ~o"2026Y5M31D"]

iex> Enum.map(Enum.take(~o"R/2026-01-31/P1M", 3), &Tempo.Interval.from/1)
[~o"2026Y1M31D", ~o"2026Y2M28D", ~o"2026Y3M31D"]
```

### An occurrence's length

An RRULE has no length: iCalendar gives it beside the rule, as `DURATION` or as `DTEND` less `DTSTART`. Give it to `parse/2` as `:duration` and each occurrence is a window of that length from the value the rule picks — ISO 8601-2 §12.10's selection with a window:

```elixir
iex> standup = Tempo.RRule.parse!("FREQ=WEEKLY;BYDAY=MO", from: ~o"2026-06-01T09:30", duration: ~o"PT15M")
iex> Tempo.to_iso8601(standup)
{:ok, "R/2026Y6M1DT9H30M/P1W/FLL1KN/PT15MN"}

iex> Enum.take(standup, 2)
[~o"2026Y6M1DT9H30M/T45M", ~o"2026Y6M8DT9H30M/T45M"]

iex> Tempo.RRule.to_string(standup)
{:ok, "FREQ=WEEKLY;BYDAY=MO"}
```

> *"**Every Monday** at half past nine, for **a quarter of an hour**."*

The ISO 8601 text carries the length and reads back to the same recurrence. The RRULE is the rule alone, as it is in iCalendar.

## What ISO 8601 says and an RRULE cannot

`Tempo.RRule.to_string/1` returns `{:error, %Tempo.ConversionError{}}`, with a reason that names what has no RRULE, for each of these:

```elixir
iex> reason = fn expression ->
...>   {:error, %Tempo.ConversionError{reason: {:no_rrule, what}}} = Tempo.RRule.to_string(expression)
...>   what
...> end
iex> reason.(~o"2026-06-15")
:not_a_recurrence

iex> reason.(~o"R/2026-01-01/P1Y6M")
{:cadence, ~o"P1Y6M"}

iex> reason.(~o"R/2026-01-01/P1Y/FL(easter)eN")
{:part, :event}

iex> reason.(~o"R/5786-01-01/P1Y[u-ca=hebrew]")
{:calendar, Calendrical.Hebrew}

iex> reason.(~o"R/2026-01-31/P1M")
:month_end
```

* **A value that is no recurrence.** A date is a date; iCalendar writes one event as a `DTSTART` with no rule.

* **A cadence of several units.** `FREQ` is one unit and `INTERVAL` a count of it.

* **A part with no `BY…`.** An event the calendar computes (Easter, an equinox), a traditional month, a selection within a window of another.

* **A recurrence of another calendar** that counts in months, years or their days. RFC 5545 counts those in the Gregorian calendar, and RFC 7529's `RSCALE`, which names another, is not written. A recurrence that steps by weeks, days or the clock and selects by weekday and time of day reads the same in any calendar, and is written.

* **A recurrence with no rule that would land on a month's last day.** `R/2026-01-31/P1M` goes to the 28th of February; `FREQ=MONTHLY` from the 31st of January passes February over. No one rule says the first.

Beyond recurrences, most of ISO 8601-2 has no RRULE at all: an uncertain or approximate value (`1850~`), unspecified digits (`156X`), a set of dates (`{…}`, `[…]` — iCalendar's `RDATE` is a property of its own, which `Tempo.RecurrenceSet` holds), an open end (`1985/..`), a year beyond four digits.

A zone or a calendar written after an expression (`[Europe/Paris]`, `[u-ca=hebrew]`) is not part of an RRULE either: iCalendar gives the zone as the `TZID` of `DTSTART`.

## What an RRULE says and Tempo does not read

`Tempo.RRule.parse/2` returns `{:error, %ArgumentError{}}` for a rule it does not read, rather than a recurrence that is nearly it:

```elixir
iex> unread = fn rule ->
...>   {:error, error} = Tempo.RRule.parse(rule, from: ~o"2026-01-01")
...>   Exception.message(error)
...> end
iex> unread.("FREQ=WEEKLY;WKST=SU")
"a WKST other than MO is not supported"

iex> unread.("FREQ=MONTHLY;BYDAY=2MO,2WE")
"BYDAY with numbered weekdays of several days is not supported"

iex> unread.("FREQ=YEARLY;RSCALE=HEBREW")
"RSCALE (RFC 7529) is not supported"

iex> unread.("FREQ=DAILY;COUNT=2;UNTIL=20260101")
"COUNT and UNTIL exclude each other"
```

* **`WKST` other than Monday.** A recurrence counts its weeks as its calendar does, and the Gregorian calendar's begin on Monday.

* **Numbered weekdays of several days** (`BYDAY=2MO,2WE`). One weekday with several numbers is read: `BYDAY=1MO,3MO` is `1K{1,3}I`.

* **RFC 7529's `RSCALE` and `SKIP`.** A recurrence in another calendar is written in ISO 8601 with its suffix: `~o"R/5786-07-15/P1Y[u-ca=hebrew]"`.

The [RRULE conformance guide](rfc5545_rrule_conformance.md) goes through RFC 5545 part by part.

## Cron

A cron expression is read into the same form by `Tempo.Cron.parse/2`: each restricted field is a part of the rule, and the cadence is the unit above the coarsest of them.

```elixir
iex> Tempo.Cron.parse("0 9 * * 1-5")
{:ok, ~o"R/2000Y1M1DT0H0M/P1M/FL{1,2,3,4,5}KT9H0MN"}

iex> {:ok, weekday_mornings} = Tempo.Cron.parse("0 9 * * 1-5", from: ~o"2026-06-01T00:00")
iex> Enum.map(Enum.take(weekday_mornings, 2), &Tempo.Interval.from/1)
[~o"2026Y6M1DT9H0M", ~o"2026Y6M2DT9H0M"]
```

> *"**Nine o'clock** on **Monday to Friday**."*

A cron has no start of its own, so one is given as `:from`, and is the first minute of 2000 otherwise. Where both the day of the month and the day of the week are restricted, cron fires on either, which no one selection says — every part of a selection holds at once — so the answer is a set of two recurrences:

```elixir
iex> Tempo.Cron.parse("0 0 13 * 5")
{:ok, ~o"{R/2000Y1M1DT0H0M/P1M/FL13DT0H0MN,R/2000Y1M1DT0H0M/P1M/FL5KT0H0MN}"}
```

## Why one form

1. **One engine.** A walk, a relation, a set operation and a selection are defined on the expression, so a rule read from an `.ics` file, one read from ISO 8601 text and one built in code are walked and combined by the same code.

2. **Conversion for free.** Because both readers answer the same value, `RRULE → ISO 8601` and back is reading with one and writing with the other, for anything both can say.

3. **A check on each reader.** A rule and its ISO 8601 text must read to equal values, and each value must read back from the text it writes. The test suite holds every RFC 5545 example to both.

## Further reading

* [RRULE conformance](rfc5545_rrule_conformance.md) — RFC 5545, part by part.
* [ISO 8601 conformance](iso8601-conformance.md) — the selection and repeat rule grammar, and Tempo's extensions to it.
* [iCalendar integration](ical-integration.md) — rules as they arrive in `.ics` files, with their starts, lengths, exceptions and zones.
* [Scheduling](scheduling.md) — bounding a recurrence, and zones.
