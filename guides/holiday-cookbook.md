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

Other markers: `nD` a day of the month, `nO` a day of the year, `nW` a week; `(name)e` a **computed event** (`Tempo.Event`); `…/±PnD` an ISO 8601-2 §12.10 **window** (the selection becomes the start of a span, and the selectors after it pick within — used for "N days before/after" feasts); a `{…}` **domain** in the repeat slot (`R/{…}/P1Y/…`) restricts which years the recurrence fires, with `^` excluding one; and a `[u-ca=…]` suffix puts the whole value in another **calendar**. Materialise any of them with `Tempo.to_interval(value, bound: ~o"2026")`.

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

Easter is `(easter)e` (the Gregorian paschal computus) or `(orthodox-easter)e` (the same computus in the Julian calendar). Every moveable feast around it is a **§12.10 window** off Easter, resolved to its own weekday — Good Friday is the last Friday in the seven days before Easter, Ascension the last Thursday in the forty-two days after. No RRULE can compute Easter, so the whole cycle is a dash. *(For the Orthodox cycle, swap `(easter)e` for `(orthodox-easter)e`.)*

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Easter − N (window) | Ash Wednesday — 46 days before Easter (a Wednesday) | `~o"R/../P1Y/FLLL(easter)eN/-P49DN3K1IN"` | — |
| Easter − N (window) | Carnival / Mardi Gras — the Tuesday before Ash Wednesday | `~o"R/../P1Y/FLLL(easter)eN/-P49DN2K1IN"` | — |
| Easter − N (window) | Palm Sunday — the Sunday before Easter | `~o"R/../P1Y/FLLL(easter)eN/-P7DN7K1IN"` | — |
| Easter − N (window) | Good Friday — the Friday before Easter | `~o"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN"` | — |
| Computed event | Easter Sunday — the paschal computus | `~o"R/../P1Y/FL(easter)eN"` | — |
| Computed event | Orthodox Easter — the computus in the Julian calendar | `~o"R/../P1Y/FL(orthodox-easter)eN"` | — |
| Easter + N (window) | Easter Monday — the Monday after Easter | `~o"R/../P1Y/FLLL(easter)eN/P2DN1K1IN"` | — |
| Easter + N (window) | Ascension — 39 days after Easter (a Thursday) | `~o"R/../P1Y/FLLL(easter)eN/P42DN4K-1IN"` | — |
| Easter + N (window) | Pentecost / Whitsun — 49 days after Easter | `~o"R/../P1Y/FLLL(easter)eN/P50DN7K-1IN"` | — |
| Easter + N (window) | Whit Monday — the day after Pentecost | `~o"R/../P1Y/FLLL(easter)eN/P51DN1K-1IN"` | — |
| Easter + N (window) | Corpus Christi — 60 days after Easter (a Thursday) | `~o"R/../P1Y/FLLL(easter)eN/P63DN4K-1IN"` | — |

## Astronomical events and solar terms (computed)

The equinoxes and solstices come from `Astro`; the 24 East Asian solar terms and the new moon from `Calendrical`/`Astro`. Each is a computed event, so again no RRULE. A solar term is measured at the Chinese meridian by default; `Tempo.Event.date/3` takes a Vietnamese, Korean or Japanese lunisolar calendar to shift the meridian.

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Astronomical | March equinox — Nowruz's astronomical anchor, Ostara | `~o"R/../P1Y/FL(march-equinox)eN"` | — |
| Astronomical | June solstice — Midsummer | `~o"R/../P1Y/FL(june-solstice)eN"` | — |
| Astronomical | September equinox — Mabon, Chuseok's anchor | `~o"R/../P1Y/FL(september-equinox)eN"` | — |
| Astronomical | December solstice — Yule, Dōngzhì | `~o"R/../P1Y/FL(december-solstice)eN"` | — |
| Solar term | Qīngmíng — Tomb-Sweeping Day (15° solar longitude) | `~o"R/../P1Y/FL(qingming)eN"` | — |
| Solar term | Lìchūn — start of spring (315°) | `~o"R/../P1Y/FL(lichun)eN"` | — |
| Lunar | First new moon of the year | `~o"R/../P1Y/FL(new-moon)eN"` | — |

## Other calendars — Islamic, Hebrew, and the lunisolar new years

A holiday defined in another calendar is anchored at a start date **in that calendar** and given a `P1Y` cadence — one *calendar* year — so successive occurrences **recur on that calendar's own year** and drift against the Gregorian year exactly as the holiday does. The `[u-ca=…]` tag is a single **trailing suffix** on the whole recurrence (`R/5787Y3M25D/P1Y[u-ca=hebrew]`), qualifying the anchor and the cadence together, not embedded mid-string on the date. RRULE is Gregorian-only, so every row is a dash; the **Materialises to** column is the Gregorian date each recurrence resolves to in 2026.

| Rule type | Holiday (rule in English) | Tempo | Materialises to (2026) | RRULE |
|---|---|---|---|---|
| Islamic (Umm al-Qura) | Islamic New Year — 1 Muḥarram | `~o"R/1447Y1M1D/P1Y[u-ca=islamic-umalqura]"` | 2026-06-16 | — |
| Islamic | Mawlid — 12 Rabīʿ al-awwal | `~o"R/1447Y3M12D/P1Y[u-ca=islamic-umalqura]"` | 2026-08-25 | — |
| Islamic | Eid al-Fitr — 1 Shawwāl | `~o"R/1447Y10M1D/P1Y[u-ca=islamic-umalqura]"` | 2026-03-20 | — |
| Islamic | Eid al-Adha — 10 Dhū al-Ḥijja | `~o"R/1447Y12M10D/P1Y[u-ca=islamic-umalqura]"` | 2026-05-27 | — |
| Hebrew | Rosh Hashanah — 1 Tishrei | `~o"R/5787Y1M1D/P1Y[u-ca=hebrew]"` | 2026-09-12 | — |
| Hebrew | Yom Kippur — 10 Tishrei | `~o"R/5787Y1M10D/P1Y[u-ca=hebrew]"` | 2026-09-21 | — |
| Hebrew | Hanukkah — 25 Kislev | `~o"R/5787Y3M25D/P1Y[u-ca=hebrew]"` | 2026-12-05 | — |
| Hebrew (leap-aware) | Passover — 15 Nisan | `~o"R/5786Y7m15D/P1Y[u-ca=hebrew]"` | 2026-04-02 | — |
| Chinese lunisolar | Chinese New Year — 1st day of the 1st month | `~o"R/4663Y1M1D/P1Y[u-ca=chinese]"` | 2026-02-17 | — |
| Persian (Solar Hijri) | Nowruz — 1 Farvardin | `~o"R/1405Y1M1D/P1Y[u-ca=persian]"` | 2026-03-21 | — |
| Coptic | Coptic / Orthodox Christmas — 29 Koiak | `~o"R/1742Y4M29D/P1Y[u-ca=coptic]"` | 2026-01-07 | — |
| Julian | Orthodox Christmas (Julian reckoning) — 25 December Julian (Gregorian 7 January) | `~o"R/2025Y12M25D/P1Y[u-ca=julian]"` | 2026-01-07 | — |
| Julian | Old New Year — 1 January Julian (Gregorian 14 January) | `~o"R/2026Y1M1D/P1Y[u-ca=julian]"` | 2026-01-14 | — |

> **Hebrew month numbers shift in leap years.** A Hebrew leap year inserts Adar I before Adar II, so Nisan is month 7 of an ordinary year like 5786 but month **8** of a leap year like 5787. Write a month after Adar with the traditional `m` marker — Passover's `7m` above is 15 Nisan in any year — and a `P1Y` cadence keeps it on Nisan in every later year.

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

## Year gates — the recurrence domain (`{…}` and `^`)

Several rule families do not change *which day* a holiday falls on but *which years* it fires: an "active" window, a "since" / "prior to" bound, a year cancelled outright, an even/odd or leap-year rule. Tempo writes these into the recurrence's **domain** — the `{…}` slot between the repeat and the cadence — as an inclusion set of years and year-ranges, with `^` marking a year to carve back out and a trailing `e` / `o` / `l` keeping only the even, odd or leap years. The holiday stays one self-bounding value: it materialises to its dates with no bound and no post-hoc set operation, and it round-trips through `Tempo.to_iso8601/1`.

| Rule type | Holiday (rule in English) | Tempo | RRULE |
|---|---|---|---|
| Active window / since–until | Christmas, only 2025 through 2027 | `~o"R/{2025Y..2027Y}/P1Y/FL12M25DN"` | — |
| Disable a year | Christmas 2020–2030, cancelled in 2026 | `~o"R/{2020Y..2030Y,^2026Y}/P1Y/FL12M25DN"` | — |
| Disable several years | … cancelled in 2026 and 2028 | `~o"R/{2020Y..2030Y,^2026Y,^2028Y}/P1Y/FL12M25DN"` | — |
| In even years | Christmas in the even years of the decade | `~o"R/{2024Y..2030Y}e/P1Y/FL12M25DN"` | — |
| In odd years | Christmas in the odd years of the decade | `~o"R/{2024Y..2030Y}o/P1Y/FL12M25DN"` | — |
| In leap years | Christmas in the decade's leap years | `~o"R/{2024Y..2030Y}l/P1Y/FL12M25DN"` | — |

> The domain is **inclusion-first**: `{2020Y..2030Y}` is the span of years the holiday runs, each `^2026Y` removes one, and a trailing `e`/`o`/`l` filters the rest to the even, odd or leap years — `l` follows the calendar's own leap rule, so `{2096Y..2104Y}l` skips 2100. A domain of *only* exclusions (`~o"R/^2026Y/P1Y/FL12M25DN"`) or an open filter (`~o"R/..e/P1Y/FL12M25DN"`, every even year) carries no window of its own, so it needs a `bound:` naming the years to work over: `Tempo.to_interval(value, bound: ~o"{2024..2028}Y")`.

Every RRULE here is a dash, and for a reason worth stating: RFC 5545 keeps year restrictions *out* of the recurrence rule. It can bound a run (`UNTIL`, `COUNT`) and thin a cadence (`INTERVAL`), but a *disabled* year is an `EXDATE` alongside the rule, not in it, and even/odd or leap-year selection it cannot express at all. `Tempo.to_rrule/1` folds none of these back into the `RRULE`; it emits the base recurrence — `FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25` for every row above — which, taken alone, would fire in the cancelled and off-parity years. Rather than present that as the equivalent, the column is a dash, exactly as it is for the computed feasts.

## Enable, weekday gates, and bridges (set algebra)

The families that remain need *another* set, not just a restriction on the years: adding an ad-hoc date the pattern never produces, filtering by the weekday an occurrence lands on, or testing a day against the year's other holidays. Because a materialised holiday *is* an interval set, each is one call:

```elixir
{:ok, xmas} = Tempo.to_interval(~o"R/{2020Y..2030Y}/P1Y/FL12M25DN")

# enable — add a date the recurrence never produces (here, Boxing Day):
{:ok, added} = Tempo.union(xmas, ~o"2027-12-26")

# "on" / "not on" a weekday — a filter over the occurrences:
weekdays = Tempo.IntervalSet.filter(xmas, fn iv ->
  Tempo.day_of_week(Tempo.Interval.from(iv)) not in [6, 7]
end)

# bridge / "if it is a holiday then…" — test a candidate day against the set:
{:ok, holidays} = Tempo.union(~o"2026-05-14", [~o"2026-05-25"])   # Ascension + Whit Monday
Tempo.subset?(~o"2026-05-14", holidays)                          # => true
```

And *"every N years"* is a plain cadence, not a filter — `~o"R/2024-07-04/P4Y"` fires on the 4th of July only every fourth year (2024, 2028, 2032, …).

`union/2` gives the enable family; `IntervalSet.filter/2` the weekday gates; and `subset?/2`, `contains?/2` are the predicates the bridge and "if it is a holiday then…" cascades test against the year's holiday set. This is the point of modelling holidays as interval sets: they compose with each other, and with anyone's free-time set, through the same algebra.

## Coverage of the date-holidays grammar

Every **selection**-shaped rule in the corpus — including several the `tempo_holidays` compiler itself still lists as *not handled* — is a single Tempo value: fixed dates and spans; nth/last weekday-in-month; a weekday **before/after a date, a weekday, or another computed anchor** (Black Friday, Election Day, "the Monday after the 3rd Sunday after September 1"); Easter/Orthodox and the whole moveable cycle; the equinoxes, solstices, solar terms and new moon; and dates in the Islamic, Hebrew, Persian, Chinese, Coptic and Julian calendars.

The **transforming and conditioning** families split two ways. The **year gates** — an active `since` / `prior to` window, even/odd and leap/non-leap rules, a disabled year — fold into the recurrence's `{…}` **domain**, so they stay single, round-trippable values. What genuinely needs the set algebra is the rest: observed-date **substitution** (the `if/then`, `and if`, `substitutes` modes), the weekday **filters** (`on`/`not on`), `enable`ing an ad-hoc date, and the bridge / "if-holiday" **cascades** — operations over a holiday set, shown above. The only genuine gaps are calendar-arithmetic edge cases inside the dependencies (a tabular-vs-computed Umm al-Qura day, an Islamic day-overflow like `30 Safar`), which live in `Calendrical`, not in this grammar.

