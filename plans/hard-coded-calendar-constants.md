# Hard-coded calendar constants

**Status:** reference, 2026-10-09

A number in Tempo that a calendar would be asked for (the days of a month, the months of a year, the years of a cycle) is a bad sign: it is right for the calendar it was written for and wrong, or not asked, for every other. The user asked for the library to be read for them on 2026-10-09, after a rule's `SKIP` was found to test a day against 28 in every calendar. This is what was found, by reading every line of `lib/` that holds 7, 12, 13, 28 to 31, 52, 53, 354, 355, 365, 366 or 400 outside a comment, a doc or a string: about a hundred lines, each read.

## Wrong answers, fixed

* **28, the days every month has** — `Tempo.RRule.Rule` wrote a rule's `SKIP` into its selection only beside a day past the 28th, in every calendar. The thirteenth month of an Ethiopic year has five days or six, so `RSCALE=ETHIOPIC;FREQ=YEARLY;BYMONTH=13;BYMONTHDAY=6;SKIP=FORWARD` was never moved. The 28 is now the Gregorian calendar's alone; in any other the skip is written beside any day of the month, and each month is asked its own days where the rule is resolved.

* **12, the months of a year** — `Tempo.Interval.Steps.months_apart/3` counted twelve a year wherever the two end years had twelve months, so a Hebrew year of thirteen between them was a month short (Tishri 5785 to Tishri 5788 was 36, and is 37). It now asks the calendar whether its years all have the same months, and how many. Tempo's own one caller reaches the count only for a calendar whose years Calendrical steps, none of which has a thirteenth month, so no answer `Tempo.duration/1` gave was wrong; the function's own was.

## Gregorian facts Tempo holds, each asked of the Gregorian calendar alone

These are right today. Each is a fact Calendrical could give, and is held in Tempo because it does not.

* **28** in `Tempo.RRule.Rule` (`moves_a_day?/2`) — the days every Gregorian month has. It lets a rule whose `SKIP` moves nothing be the rule without it, which is what `Tempo.RRule.to_string/1` and `Tempo.to_iso8601/1` write. Needs the lengths a calendar's months have in any year (below).

* **400 years, 4,800 months, fourteen kinds of year, 1 January and 31 December** in `Tempo` (`has_no_occurrence?/3` and what it calls) — the Gregorian calendar comes round in 400 years, and a year is one of fourteen kinds by its leap day and the weekday it starts on. They answer whether a rule has any occurrence at all. No other calendar is asked: a rule with none there is walked to the limit.

* **400 years from 2000, and twelve months a year** in `Tempo.Network.Normalize` — the positions of months on a network's axis, which is Gregorian months alone, and the cycle its longest and shortest spans are measured over.

* **Twelve months a year** in `Tempo` (`cadence_index/2`) — where a recurrence's domain is stepped by months. A domain's years and months are Gregorian by design, whatever calendar the rule is in.

* **March, June, September and December** in `Tempo.Iso8601.Group` — the months the meteorological seasons start in. A season in another calendar is the Gregorian one that starts within its year.

## A table Calendrical also has, removed

* **The longitudes of the twenty-four solar terms** — `Tempo.Event` held them by name (`"qingming" => 15`) and worked out the day the sun reaches one. The user's word, 2026-10-09: "Tempo should not need a solar-term longitude table", and "you MUST ask the appropriate calendar (Chinese, Korean, Vietnamese, Japanese Lunisolar) for the appropriate terms". It now takes the names from `Calendrical.Lunisolar.solar_term_name/1`, asking until there are no more, and the day from `Calendrical.Lunisolar.solar_term/3` at the place the value's own calendar is reckoned (`location/1`), where it named three calendars and gave the rest the Chinese meridian. The two agreed on every one of 960 dates compared before the change (24 terms, eight years from 1700 to 2500, five calendars), and 62 terms from 2000 to 2030 fall on different days in the four calendars.

* **Two things are Calendrical's to settle**, reported to the user 2026-10-09. `solar_term/3` takes `trunc/1` of the moment, which before its day 0 is the day after the one that holds it (`solar_term(5, -3000, &Calendrical.Chinese.location/1)` is 7 April, and the moment is on the 6th), so a term of a year before 0 is now a day late in Tempo too, where `floor/1` is wanted. And no calendar answers for its own terms: Tempo passes the calendar's `location/1` to the function of `Calendrical.Lunisolar`, and gives a calendar that is reckoned at no place (the Gregorian) the Chinese meridian, which is Tempo's choice and not a calendar's.

## Bounds on what is read before a calendar is asked

* **A month past 13 and a day past 31** in `Tempo.Iso8601.Tokenizer.Helpers` — refused as no month and no day of any calendar Calendrical has, before the value's calendar was asked. Dropped 2026-10-09 (user: "drop them") for a date written with hyphens or designators: `2026-14` and `2026Y6M32D` are now the calendar's own `Tempo.InvalidDateError`, and a calendar with a fourteenth month or a thirty-second day is read as any other.

* **The same two numbers, for a bare run of digits** (`a_date_and_no_time_of_day/5`) — kept, because there they are no check of a date. Such a run is read as a date before a time of day, and `093455.8` is 09:34:55.8 only because its fifty-fifth month is none. With the bounds gone from this form too, twenty-four basic times with a fraction in `test/support/data/iso8601_test_data.txt` were read as dates and refused. To ask the calendar here the reader must know the value's calendar, which a suffix gives after the digits, and the calendar must say the most months a year has and the most days a month has.

* **1 to 12 and 1 to 31** in `Tempo.Iso8601.Tokenizer.Plain` — the dates the fast reader takes. Any other goes to the general reader, so nothing is refused by it. The same two ranges in `Tempo` (`month_and_day/1`) choose the wording of an error's advice.

## Not a calendar's to say

* A week of seven days (`1..7` in `Tempo.Iso8601.Unit`, `Tempo.UnitValues` and the rule's selection), which is ISO 8601's week.

* The clock: 24, 60, 3,600, 86,400 and 604,800.

* Cron's own ranges and names, and the English names of months and weekdays in `Tempo.explain/1`, which names a Gregorian month alone.

* The table of leap seconds, which is the IERS's.

* Limits on work: thirty years of a zone's changes, four hundred years asked of one, blocks of 366 days.

## What Calendrical would need to give

The user offered, on 2026-10-09, a list of the lengths of a year's months: its least is the shortest month and its count the months the year has.

* **For a year** — that list would serve a year's walk by its months and the count of them. In a year that turns within a month (`Calendrical.Julian.March25`, and England before 1751) it would unblock two items under Blocked if it is in the order of time and holds the month the year turns in twice, as the seven days from 25 March and the twenty-four that end the year.

* **For no year** — a rule's `SKIP` is decided where the rule is built, with no year in hand, so it needs the lengths a month has over every year: the same list with each month's fewest and most days (`[31, 28..29, 31, …]`). `calendar.days_in_month/1` answers so for one month, and Tempo does not walk the months to find the least.

## Tasks

* [ ] **The 28 goes** — blocked on Calendrical giving the lengths a calendar's months have in any year.

* [ ] **The reader's bounds for a bare run of digits** — blocked on the same list (its count and its most), and on the reader knowing the value's calendar before it reads the digits.

### Done

* [x] **The tokenizer's bounds on a month and a day, in a date written with hyphens or designators** — dropped. 2026-10-09.

* [x] **`Tempo.Event` asks Calendrical for a solar term** — its name, its day and the meridian of the value's own calendar. 2026-10-09.

* [x] **A `SKIP` in a calendar whose shortest month is not the Gregorian's** — 2026-10-09.

* [x] **The months between two values, by the calendar's own count** — 2026-10-09.
