# The Brazilian ANBIMA business-day calendar

**Status:** planning, 2026-10-03

ANBIMA's national holiday list is the calendar Brazilian financial markets count business days (*dias úteis*) on. This document records the research into whether Tempo and `tempo_holidays` can provide it, what was verified, and the work that remains. It was prompted by [bizdays](https://forum.elixirforum.com/t/bizdays-business-day-calculations-with-the-brazilian-anbima-calendar/76934), a hex package that provides the calendar for 2001–2099.

## The conclusion

The calendar can be provided today, with no new holiday rules: the Brazil rules in `tempo_holidays` reproduce ANBIMA's published list exactly for 2001–2099, and `Tempo.workdays/2` with `:except` gives the same business-day counts. Two gaps remain, one in each repository, and one difference from bizdays is deliberate.

## The holiday set

ANBIMA lists 12 holidays a year to 2023 and 13 from 2024, when 20 November was added. Each is a rule in the date-holidays Brazil data that `tempo_holidays` compiles.

| ANBIMA holiday | Rule | Type |
|---|---|---|
| Confraternização Universal | `01-01` | `:public` |
| Carnaval, Monday and Tuesday | `easter -48`, `easter -47` | `:bank` |
| Paixão de Cristo | `easter -2` | `:public` |
| Tiradentes | `04-21` | `:public` |
| Dia do Trabalho | `05-01` | `:public` |
| Corpus Christi | `easter 60` | `:bank` |
| Independência do Brasil | `09-07` | `:public` |
| Nossa Senhora Aparecida | `10-12` | `:public` |
| Finados | `11-02` | `:public` |
| Proclamação da República | `11-15` | `:public` |
| Consciência Negra | `11-20`, active from 2023-12-21 | `:public` |
| Natal | `12-25` | `:public` |

`Tempo.Holidays.holidays(:BR, include: [:public, :bank])` returns these and two `Election Day` members (the first and the last Sunday of October in even years), which the data types `:public`. The `:optional` and `:observance` types leave out what ANBIMA leaves out: Ash Wednesday morning, Carnival Saturday and Sunday, 24 and 31 December, Mother's Day and the like.

## What was verified

The official dates were read from ANBIMA's own page for each year, `https://www.anbima.com.br/feriados/fer_nacionais/<year>.asp`, for 2001–2099, on 2026-10-03.

* **Dates** — 1,264 official occurrences and 1,264 computed (Election Day set aside), with none missing and none extra in either direction.

* **20 November** — absent to 2023 and present from 2024 on both sides.

* **Coinciding holidays** — Tiradentes and Good Friday both fall on 21 April 2079. The set holds a member for each and the day is counted once: April 2079 has 19 business days by both counts.

* **Business days a year** — `Tempo.count_workdays/2` over each year equals an independent count from the official list (the weekdays not in it) for all 99 years. The 99 counts took about 0.8 seconds.

* **The bizdays examples** — 16 February 2026 is not a business day, one business day after 13 February 2026 is the 18th, and (13 February, 24 February] holds 5 business days.

Outside 2001–2099 the rules still produce dates, and there is no official list to check them against.

## Business days in a financial period

```elixir
{:ok, holidays} = Tempo.Holidays.holidays(:BR, include: [:public, :bank])
anbima = Tempo.workdays(:BR, except: holidays)

Tempo.workday?(~o"2026-02-16", anbima)
#=> false

Tempo.add_workdays(~o"2026-02-13", 1, anbima)
#=> ~o"2026Y2M18D"

Tempo.count_workdays(~o"2026-02-14/2026-02-25", anbima)
#=> 5
```

A period is half-open, so the day it ends on is not counted.

## Against bizdays

Read from the forum post and the bizdays README, not from its source.

| bizdays | Tempo | Covered |
|---|---|---|
| `business_day?` | `Tempo.workday?/2` | Yes |
| `count` | `Tempo.count_workdays/2` | Yes, forwards |
| `add` | `Tempo.add_workdays/3` | Yes, but for an offset of 0 |
| `range` | `Tempo.select/2` with the workdays | Yes by the documentation, not run |
| `holidays(cal, year)` | `Tempo.to_interval_set/2` within the year | Yes, with Election Day |
| `following`, `preceding` | None | No |
| `modified_following`, `modified_preceding` | None | No |
| A custom calendar's holidays | `:except` takes any set | Yes |
| A custom calendar's weekend days | The territory's weekend | By decision, no |

The smaller differences: bizdays' `add` with an offset of 0 returns the following business day where Tempo returns the date unchanged; bizdays counts (from, to] where Tempo counts [from, to); bizdays returns a negative count for a reversed range, which was not tested in Tempo; and bizdays raises outside 2001–2099 where Tempo has no bounds.

## The gaps

* **Election Day in the selection** — in `tempo_holidays`. No type selection gives ANBIMA's list exactly, because the two `Election Day` members are `:public`. All 98 occurrences in 2001–2099 are Sundays, so no business-day answer changes, but a listing of the holidays shows two rows ANBIMA does not have in even years. `holidays/2` has no way to leave a holiday out by its `:id` or `:name`.

* **Business-day adjustments** — in Tempo. There is no "this day when it is a workday, otherwise the next one" (following), its mirror (preceding), or the modified forms that turn back when the adjusted day leaves the month. These are the standard date-roll conventions of financial contracts. `Tempo.nearest_workday/2` is a different rule (the nearer side wins), and `Tempo.next_workday/2` always moves.

* **A custom weekend** — not a gap. `Tempo.workdays/2` reads the weekend from the territory's CLDR data, where bizdays takes a list of weekday numbers. The territory's weekend is the more correct source and nothing is to be implemented (user, 2026-10-03).

## Tasks

* [ ] **Workday adjustments: following, preceding and their modified forms** — tracked in Tempo's `TODO.md`.

* [ ] **Brazil's ANBIMA holidays without Election Day** — tracked in the `tempo_holidays` `TODO.md`.
