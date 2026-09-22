# Holiday cookbook

Holidays are the sternest test of a recurrence language: they are fixed dates, nth-weekdays, moon phases, computed feasts, and dates in half a dozen calendars, often with an observed-day shift on top. This cookbook takes each **rule family** a holiday library uses (the shapes `date-holidays` and `tempo_holidays` classify rules into) and gives the equivalent Tempo value.

Every expression below has been **materialised and checked against the holiday's real date** — the dates in the prose are what Tempo produces, not what it ought to. The fourth column is the equivalent RFC 5545 **RRULE** where one exists; a dash means the rule is one RRULE genuinely cannot express (a computed feast, or a date in a non-Gregorian calendar), and `Tempo.to_rrule/1` reports as much rather than emitting a wrong approximation.

## Reading a holiday value

A recurring holiday is an unbounded yearly recurrence wrapping a per-year **selection**:

```text
R/../P1Y/FL 11M 4K 4I N
│    │  │   │   │  │  └ close the selection
│    │  │   │   │  └ 4I  = position 4 (the 4th …)
│    │  │   │   └ 4K   = weekday 4 (Thursday; 1=Mon … 7=Sun)
│    │  │   └ 11M  = month 11 (November)
│    │  └ FL…N = the per-year selection frame
│    └ P1Y = one-year cadence
└ R/.. = repeat, no fixed start (materialise against a bound to get dates)
```

Other markers: `nD` a day of the month, `nO` a day of the year, `nW` a week; `(name)E` a **computed event** (`Tempo.Event`); `…/±PnD` an ISO 8601-2 §12.10 **window** (the selection becomes the start of a span, and the selectors after it pick within — used for "N days before/after" feasts); and a `[u-ca=…]` suffix puts the whole value in another **calendar**. Materialise any of them with `Tempo.to_interval(value, bound: ~o"2026")`.

## Fixed dates

The plain case: a month and a day. The RRULE is a `BYMONTH` + `BYMONTHDAY` pair.

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Fixed date | New Year's Day — January 1 | `~o"R/../P1Y/FL1M1DN"` | `FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=1` |
| Fixed date | Valentine's Day — February 14 | `~o"R/../P1Y/FL2M14DN"` | `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=14` |
| Fixed date | Saint Patrick's Day — March 17 | `~o"R/../P1Y/FL3M17DN"` | `FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=17` |
| Fixed date | International Workers' Day — May 1 | `~o"R/../P1Y/FL5M1DN"` | `FREQ=YEARLY;BYMONTH=5;BYMONTHDAY=1` |
| Fixed date | US Independence Day — July 4 | `~o"R/../P1Y/FL7M4DN"` | `FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=4` |
| Fixed date | Halloween — October 31 | `~o"R/../P1Y/FL10M31DN"` | `FREQ=YEARLY;BYMONTH=10;BYMONTHDAY=31` |
| Fixed date | Armistice / Veterans Day — November 11 | `~o"R/../P1Y/FL11M11DN"` | `FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=11` |
| Fixed date | Christmas Day — December 25 | `~o"R/../P1Y/FL12M25DN"` | `FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25` |
| Fixed date + span | Christmas break — December 25 for 4 days | `~o"R/../P1Y/FLL12M25DN/P4DN"` | — |

## The nth (or last) weekday of a month

A weekday plus a position: `nK` picks the weekday, `nI` the occurrence within the month (`-1I` = the last). The RRULE is `BYMONTH` + an ordinal `BYDAY` (`3MO`, `-1MO`).

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Nth weekday | Martin Luther King Jr. Day — 3rd Monday in January | `~o"R/../P1Y/FL1M1K3IN"` | `FREQ=YEARLY;BYMONTH=1;BYDAY=3MO` |
| Nth weekday | Presidents' Day — 3rd Monday in February | `~o"R/../P1Y/FL2M1K3IN"` | `FREQ=YEARLY;BYMONTH=2;BYDAY=3MO` |
| Nth weekday | Mother's Day (US) — 2nd Sunday in May | `~o"R/../P1Y/FL5M7K2IN"` | `FREQ=YEARLY;BYMONTH=5;BYDAY=2SU` |
| Last weekday | Memorial Day — last Monday in May | `~o"R/../P1Y/FL5M1K-1IN"` | `FREQ=YEARLY;BYMONTH=5;BYDAY=-1MO` |
| Nth weekday | Father's Day (US) — 3rd Sunday in June | `~o"R/../P1Y/FL6M7K3IN"` | `FREQ=YEARLY;BYMONTH=6;BYDAY=3SU` |
| Nth weekday | US Labor Day — 1st Monday in September | `~o"R/../P1Y/FL9M1K1IN"` | `FREQ=YEARLY;BYMONTH=9;BYDAY=1MO` |
| Nth weekday | Canadian Thanksgiving / Columbus Day — 2nd Monday in October | `~o"R/../P1Y/FL10M1K2IN"` | `FREQ=YEARLY;BYMONTH=10;BYDAY=2MO` |
| Nth weekday | US Thanksgiving — 4th Thursday in November | `~o"R/../P1Y/FL11M4K4IN"` | `FREQ=YEARLY;BYMONTH=11;BYDAY=4TH` |
| Last weekday of month | Last working day of every month (payroll) — the last Mon–Fri | `~o"R/../P1M/FL{1..5}K-1IN"` | `FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1` |

## A weekday relative to another day

"The Monday before June 1", "the Friday after the fourth Thursday", "the first Tuesday after the first Monday". A **day range** narrows the month to the seven days a "before"/"after" anchor spans, then a weekday and position pick within it — and that gives a faithful `BYMONTHDAY` (range) + `BYDAY` RRULE. When the anchor is itself a *computed* selection (an nth-weekday, a date offset, an event), a §12.10 window off it (`FLLL…N/PnDN…`) does the same job but has no RRULE.

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Weekday after a date | US Labor Day, as "1st Monday on/after September 1" | `~o"R/../P1Y/FL9M{1..7}D1K1IN"` | `FREQ=YEARLY;BYMONTH=9;BYMONTHDAY=1,2,3,4,5,6,7;BYDAY=1MO` |
| Weekday before a date | Memorial Day, as "Monday before June 1" | `~o"R/../P1Y/FL5M{25..31}D1K1IN"` | `FREQ=YEARLY;BYMONTH=5;BYMONTHDAY=25,26,27,28,29,30,31;BYDAY=1MO` |
| Weekday in a day range | US Election Day — the 1st Tuesday after the 1st Monday of November (a Tuesday in the 2nd–8th) | `~o"R/../P1Y/FL11M{2..8}D2K1IN"` | `FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=2,3,4,5,6,7,8;BYDAY=1TU` |
| Weekday after a weekday | Black Friday — the Friday after the 4th Thursday of November (a Friday in the 23rd–29th) | `~o"R/../P1Y/FL11M{23..29}D5K1IN"` | `FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=23,24,25,26,27,28,29;BYDAY=1FR` |
| Weekday in a day range | First Friday of the month (devotions) | `~o"R/../P1M/FL{1..7}D5K1IN"` | `FREQ=MONTHLY;BYMONTHDAY=1,2,3,4,5,6,7;BYDAY=1FR` |
| Weekday on/after a date | The Friday on or after the 11th | `~o"R/../P1Y/FL11M{11..17}D5K1IN"` | `FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=11,12,13,14,15,16,17;BYDAY=1FR` |
| Nested off a computed anchor | "The Monday after the 3rd Sunday after September 1" — a window off a windowed selection | `~o"R/../P1Y/FLLL9M{1..21}D7K3IN/P2DN1K1IN"` | — |

## The Easter cycle (computed)

Easter is `(easter)E` (the Gregorian paschal computus) or `(orthodox-easter)E` (the same computus in the Julian calendar). Every moveable feast around it is a **§12.10 window** off Easter, resolved to its own weekday — Good Friday is the last Friday in the seven days before Easter, Ascension the last Thursday in the forty-two days after. No RRULE can compute Easter, so the whole cycle is a dash. *(For the Orthodox cycle, swap `(easter)E` for `(orthodox-easter)E`.)*

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Easter − N (window) | Ash Wednesday — 46 days before Easter (a Wednesday) | `~o"R/../P1Y/FLLL(easter)EN/-P49DN3K1IN"` | — |
| Easter − N (window) | Carnival / Mardi Gras — the Tuesday before Ash Wednesday | `~o"R/../P1Y/FLLL(easter)EN/-P49DN2K1IN"` | — |
| Easter − N (window) | Palm Sunday — the Sunday before Easter | `~o"R/../P1Y/FLLL(easter)EN/-P7DN7K1IN"` | — |
| Easter − N (window) | Good Friday — the Friday before Easter | `~o"R/../P1Y/FLLL(easter)EN/-P7DN5K-1IN"` | — |
| Computed event | Easter Sunday — the paschal computus | `~o"R/../P1Y/FL(easter)EN"` | — |
| Computed event | Orthodox Easter — the computus in the Julian calendar | `~o"R/../P1Y/FL(orthodox-easter)EN"` | — |
| Easter + N (window) | Easter Monday — the Monday after Easter | `~o"R/../P1Y/FLLL(easter)EN/P2DN1K1IN"` | — |
| Easter + N (window) | Ascension — 39 days after Easter (a Thursday) | `~o"R/../P1Y/FLLL(easter)EN/P42DN4K-1IN"` | — |
| Easter + N (window) | Pentecost / Whitsun — 49 days after Easter | `~o"R/../P1Y/FLLL(easter)EN/P50DN7K-1IN"` | — |
| Easter + N (window) | Whit Monday — the day after Pentecost | `~o"R/../P1Y/FLLL(easter)EN/P51DN1K-1IN"` | — |
| Easter + N (window) | Corpus Christi — 60 days after Easter (a Thursday) | `~o"R/../P1Y/FLLL(easter)EN/P63DN4K-1IN"` | — |

## Astronomical events and solar terms (computed)

The equinoxes and solstices come from `Astro`; the 24 East Asian solar terms and the new moon from `Calendrical`/`Astro`. Each is a computed event, so again no RRULE. A solar term is measured at the Chinese meridian by default; `Tempo.Event.date/3` takes a Vietnamese, Korean or Japanese lunisolar calendar to shift the meridian.

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Astronomical | March equinox — Nowruz's astronomical anchor, Ostara | `~o"R/../P1Y/FL(march-equinox)EN"` | — |
| Astronomical | June solstice — Midsummer | `~o"R/../P1Y/FL(june-solstice)EN"` | — |
| Astronomical | September equinox — Mabon, Chuseok's anchor | `~o"R/../P1Y/FL(september-equinox)EN"` | — |
| Astronomical | December solstice — Yule, Dōngzhì | `~o"R/../P1Y/FL(december-solstice)EN"` | — |
| Solar term | Qīngmíng — Tomb-Sweeping Day (15° solar longitude) | `~o"R/../P1Y/FL(qingming)EN"` | — |
| Solar term | Lìchūn — start of spring (315°) | `~o"R/../P1Y/FL(lichun)EN"` | — |
| Lunar | First new moon of the year | `~o"R/../P1Y/FL(new-moon)EN"` | — |

## Other calendars — Islamic, Hebrew, and the lunisolar new years

A holiday defined in another calendar is that calendar's date under `[u-ca=…]`, and it **recurs on that calendar's own year**: anchor the recurrence at a start date and give it a `P1Y` cadence — one *calendar* year, so successive occurrences drift against the Gregorian year exactly as the holiday does. RRULE is Gregorian-only, so every row is a dash.

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Islamic (Umm al-Qura) | Islamic New Year — 1 Muḥarram | `~o"R/1447Y1M1D[u-ca=islamic-umalqura]/P1Y"` | — |
| Islamic | Mawlid — 12 Rabīʿ al-awwal | `~o"R/1447Y3M12D[u-ca=islamic-umalqura]/P1Y"` | — |
| Islamic | Eid al-Fitr — 1 Shawwāl | `~o"R/1447Y10M1D[u-ca=islamic-umalqura]/P1Y"` | — |
| Islamic | Eid al-Adha — 10 Dhū al-Ḥijja | `~o"R/1447Y12M10D[u-ca=islamic-umalqura]/P1Y"` | — |
| Hebrew | Rosh Hashanah — 1 Tishrei | `~o"R/5787Y1M1D[u-ca=hebrew]/P1Y"` | — |
| Hebrew | Yom Kippur — 10 Tishrei | `~o"R/5787Y1M10D[u-ca=hebrew]/P1Y"` | — |
| Hebrew | Hanukkah — 25 Kislev | `~o"R/5787Y3M25D[u-ca=hebrew]/P1Y"` | — |
| Hebrew (leap-aware) | Passover — 15 Nisan | `~o"R/5786Y8M15D[u-ca=hebrew]/P1Y"` | — |
| Chinese lunisolar | Chinese New Year — 1st day of the 1st month | `~o"R/4663Y1M1D[u-ca=chinese]/P1Y"` | — |
| Persian (Solar Hijri) | Nowruz — 1 Farvardin | `~o"R/1405Y1M1D[u-ca=persian]/P1Y"` | — |
| Coptic | Coptic / Orthodox Christmas — 29 Koiak | `~o"R/1742Y4M29D[u-ca=coptic]/P1Y"` | — |
| Julian | Orthodox Christmas (Julian reckoning) — 25 December Julian (Gregorian 7 January) | `~o"R/2025Y12M25D[u-ca=julian]/P1Y"` | — |
| Julian | Old New Year — 1 January Julian (Gregorian 14 January) | `~o"R/2026Y1M1D[u-ca=julian]/P1Y"` | — |

> **Hebrew month numbers shift in leap years.** A Hebrew leap year inserts Adar I before Adar II, so Nisan is month 7 in a common year but month **8** in a leap year like 5786 — hence Passover's `8M` above. Anchor each Hebrew holiday on a year whose month numbering you have checked; `Tempo.to_date/1` will tell you the Gregorian date.

## Observed-date substitution (a transform over a holiday)

Many holidays are *observed* on a nearby working day when they land on a weekend — "if January 1 is a Saturday or Sunday, it is observed the following Monday". This is not a new selection but a **map** over the base recurrence, using the territory-aware working-day helpers:

```elixir
new_years  = ~o"R/../P1Y/FL1M1DN"
{:ok, set} = Tempo.to_interval(new_years, bound: ~o"{2028..2033}Y")

# The observed date of each occurrence — the nearest US working day.
# `IntervalSet.map/2` returns the list of whatever the function yields:
observed = Tempo.IntervalSet.map(set, fn iv ->
  Tempo.nearest_working_day(Tempo.Interval.from(iv), :US)
end)
#   2028-01-01 is a Saturday, so it is observed on Friday 2027-12-31; and so on.
```

> *"New Year's Day is January 1, observed on the nearest working day."* `Tempo.next_working_day/2`, `previous_working_day/2` and `add_working_days/3` cover the "next Monday" and "N working days later" variants; all take a territory so the weekend and the holiday set are the right ones.

## Filters, gates, and bridges (set algebra)

The remaining rule families are not *selections* — they modify or condition a base recurrence — so they are **set operations** rather than a single value. Because a materialised holiday *is* an interval set, every one of them is one call:

```elixir
{:ok, xmas} = Tempo.to_interval(~o"R/../P1Y/FL12M25DN", bound: ~o"{2020..2030}Y")

# active window / "since" / "prior to" — the holiday only within a range of years:
{:ok, active} = Tempo.intersection(xmas, ~o"2025-01-01/2028-01-01")

# disable / enable specific dates:
{:ok, trimmed} = Tempo.difference(xmas, ~o"2026-12-25")    # drop one year
{:ok, added}   = Tempo.union(xmas, ~o"2027-12-26")         # add an ad-hoc date

# in even / odd / leap years — intersect with the set of qualifying years
# (a bare year digit-set is NOT a selection filter, so the parity/leap rule
# lives here; leap years are just the year set that happens to be leap):
{:ok, even} = Tempo.intersection(xmas, ~o"{2024,2026,2028,2030}Y")
{:ok, leap_only} = Tempo.intersection(xmas, ~o"{2024,2028}Y")

# "on"/"not on" a weekday — a filter over the occurrences:
weekdays = Tempo.IntervalSet.filter(xmas, fn iv ->
  Tempo.day_of_week(Tempo.Interval.from(iv)) not in [6, 7]
end)

# bridge / "if it is a holiday then…" — test a candidate day against the set:
{:ok, holidays} = Tempo.union(~o"2026-05-14", [~o"2026-05-25"])   # Ascension + Whit Monday
Tempo.subset?(~o"2026-05-14", holidays)                          # => true
```

And *"every N years"* is a plain cadence — `~o"R/2024-07-04/P4Y"` fires on the 4th of July only in leap-numbered years — so it stays a single value, not a filter.

`intersection/2`, `difference/2` and `union/2` give the active / disable / enable / parity / since-until families; `IntervalSet.filter/2` the weekday gates; and `subset?/2`, `contains?/2` are the predicates the bridge and "if it is a holiday then…" cascades test against the year's holiday set. This is the point of modelling holidays as interval sets: they compose with each other, and with anyone's free-time set, through the same algebra.

## Coverage of the date-holidays grammar

Every **selection**-shaped rule in the corpus — including several the `tempo_holidays` compiler itself still lists as *not handled* — is a single Tempo value: fixed dates and spans; nth/last weekday-in-month; a weekday **before/after a date, a weekday, or another computed anchor** (Black Friday, Election Day, "the Monday after the 3rd Sunday after September 1"); Easter/Orthodox and the whole moveable cycle; the equinoxes, solstices, solar terms and new moon; and dates in the Islamic, Hebrew, Persian, Chinese, Coptic and Julian calendars.

The **transforming and conditioning** families — observed-date **substitution** (the `if/then`, `and if`, `substitutes` modes), the year and weekday **filters** (`since`/`prior to`, even/odd, leap/non-leap, `on`/`not on`), and the `disable`/`enable`/bridge/"if-holiday" **cascades** — are operations over a holiday set, shown above, not single sigils. The only genuine gaps are calendar-arithmetic edge cases inside the dependencies (a tabular-vs-computed Umm al-Qura day, an Islamic day-overflow like `30 Safar`), which live in `Calendrical`, not in this grammar.

