# Date rules

**Status:** in progress, 2026-10-27

A reader for the date-holidays rule grammar in Tempo, `Tempo.DateRule`, beside `Tempo.RRule` and `Tempo.Cron`: a rule written for people, `2nd Monday in June`, `Friday after 4th Thursday in November`, `easter -2`, `15 Nisan`, `chinese 01-0-01`, `march equinox in Asia/Tokyo`, read into the Tempo expression it means. ISO 8601-2 can say all of these, but it was written for machines to exchange; RRULE says cadences well and has no Easter and few calendars. The grammar is date-holidays' (https://github.com/commenthol/date-holidays), read as its parser, date-holidays-parser, reads it, so the rules of its dataset of some 200 territories, and any written for it, read here.

It began in tempo_holidays (`plans/rule-compiler.md` there), which compiles the dataset with its own compiler and has the tokenizer of this plan's first task; the user moved it here on 2026-10-27: "the rule compiler better belongs in Tempo itself since it's a generally useful tool, especially since ISO 8601 itself is difficult to read since it was designed for machine-to-machine communication."

## The grammar

The authority is date-holidays-parser (`src/Parser.js`, v3.4.7, ISC licence), whose `specification.md` in date-holidays describes it. Its grammar is compositional: a rule is a sequence of parts, read left to right by an ordered list of token readers, then reordered so the base date comes first.

```text
rule         = [same-day] {weekday-step} base [time] [duration] {modifier} [active]

base         = gregorian | month-start | julian | easter | equinox
             | islamic | hebrew | persian | lunisolar | solar-term | bengali
gregorian    = [year "-"] month "-" day                 ; "12-25", "2015-10-09"
month-start  = month-name                               ; "February" = "02-01"
julian       = "julian " gregorian
easter       = ("easter" | "orthodox") [" " signed-days] ; "easter -2", "orthodox 49"
equinox      = season (" equinox" | " solstice") [" in " zone]
islamic      = day " " islamic-month [" " year]         ; "10 Dhu al-Hijjah"
hebrew       = day " " hebrew-month [" " year]          ; "15 Nisan", "AdarII"
persian      = day " " persian-month [" " year]         ; "1 Farvardin 1401"
lunisolar    = ("chinese" | "korean" | "vietnamese") " " [cycle "-" year "-"] month "-" leap "-" day
solar-term   = ("chinese" | "korean" | "vietnamese") " " [cycle "-" year "-"] term "-" day " solarterm"
bengali      = "bengali-revised " [year "-"] month "-" day

weekday-step = [count " "] (weekday | "day" | "days") " " ("before" | "after" | "in" | "next" | "previous") " "
                                                        ; "Friday after", "2nd Sunday after", "4 days before"
time         = ["T"] hour ":" minute | "T" hour         ; "12-31 14:00"
duration     = "P" [n "D"] ["T" [n "H"] [n "M"]]        ; "PT5H", "P1DT12H"

modifier     = ("substitutes" | "and" | "if" | "then" | "if equal") ...  ; joins the clauses below
             | "if " weekdays " then " [direction " " weekday]   ; "if sunday then next monday"
             | "in " ("even" | "odd" | "leap" | "non-leap") " years" | "every " n " years since " year
             | ["not "] "on " weekdays                  ; "on Monday, Tuesday"
             | "is " [type " "] "holiday"                ; a bridge: "09-22 if 09-21 is holiday"
             | "if is " [type " "] "holiday then " [count " "] [direction " " (weekday | "day")] [" omit " weekdays]
active       = "since " date-part [" and"] | "prior to " date-part
same-day     = "#" digits                               ; the same rule, kept apart
```

The metadata beside a rule in `holidays.yaml` (a name per language, `type`, `substitute`, `active` periods, `disable` and `enable` dates, `false` to remove an inherited rule) is not part of the rule; it is the holiday around it.

## How much of it tempo_holidays compiles today

A census of every rule in date-holidays-parser's own golden fixture (`test/fixtures/parser.cjs`, 117 rules, each with the tokens the parser makes of it) and every example in the specification, compiled by tempo_holidays' `Compiler.compile/1` on 2026-10-27:

* **The parser's fixture:** 102 of 117 compile. Of the fifteen that do not, one is no rule (`#1111` alone).

* **The specification's examples:** 52 of 58 compile, leaving out the 16 placeholders the census caught (`<weekday>`, `D`).

* **The dataset (3.38.0):** every rule compiles but three shapes, accepted gaps: the eight Bengali rules, Poland's `Thursday before easter -46`, and a US rule that ended in 2016, `friday before 1st monday before 06-01`.

What does not compile, by production:

* **A base date's optional year or cycle:** `31 Shahrivar 1401`, `chinese 78-32-08-0-15`, `chinese 78-32-24-01 solarterm`, `julian 2015-01-09`.

* **A month alone:** `February`.

* **A weekday step before a base other than a fixed date:** `3rd monday before December solstice`, `3rd Sunday after june solstice in Asia/Tokyo`, `friday before chinese 78-32-8-15 solarterm`, `Thursday before easter -46`.

* **A count of days as a step:** `4 days before 11-23`, `4 days after 11-27`.

* **A nested step whose inner direction is `before`:** `friday before 1st monday before 06-01`.

* **`if equal`:** `2nd sunday after 05-01 if equal easter 49 then 3rd sunday after 05-01`.

* **`prior to` a month:** `09-21 prior to 2020-11`.

* **A time written `T16`:** `03-12T16`.

* **Bengali:** no Bengali calendar in Calendrical (`TODO.md`, blocked).

* **A defect:** the Islamic month 11 is spelled `Dhu al-Qadah` in the compiler and `Dhu al-Qidah` in the grammar, so `4 Dhu al-Qidah` is refused. No rule in the dataset uses the month.

## What a rule reads to

Every part has a Tempo form already: tempo_holidays' `Rule.recurrence/2` builds each of the dataset's rules from them, and those builders move here.

* **A fixed date** — a yearly recurrence selecting the month and day (`FL12M25DN`); with a year, the one day.

* **A weekday step** — a §12.10 window off the date it steps from, the nth weekday in it (`LL9M1DN/P7D7K-1IN`); a count of days, a shift of the date.

* **Easter and Orthodox Easter, an equinox or a solstice, a solar term** — `Tempo.Event`'s events (`(easter)e`), with an offset or a zone.

* **A date in another calendar** — a recurrence in that calendar, its module named by the rule's words: `Calendrical.Islamic.UmmAlQura`, `Calendrical.Hebrew`, `Calendrical.Persian`, `Calendrical.Chinese`, `Calendrical.Korean`, `Calendrical.Vietnamese`, `Calendrical.Julian`; Bengali, which Calendrical does not have, an error.

* **A time and a duration** — the time of day the occurrence starts at and its length.

* **`if <weekdays> then next <weekday>`, `substitutes`, `and`** — the observed day: the occurrence moved, its observed day added, or the observed day alone.

* **A year filter, a weekday filter, `since`, `prior to`** — the years and days the recurrence is kept in.

* **A bridge, `if is holiday then …`, `if equal`** — a conditional member (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`), decided against the other members of a set whose metadata matches (`falls_on: %{type: :public}`), and against none alone.

## Decisions

The first three were taken in tempo_holidays and carry here; D4, holidays an application defines, stays there; D5 moved the work here.

* **D1 — the grammar.** A tokenizer of date-holidays-parser's grammar, one reader for each of its token kinds in its order, tested against the tokens its own 119-rule fixture records; rules compile from the tokens, part by part.

* **D2 — the result.** `Tempo.DateRule.parse(rule, options)` gives `{:ok, expression}`, a `t:Tempo.t/0`, or `{:error, exception}` naming where the rule stopped; `parse!/2` raises it.

* **D3 — rules that depend on other members.** Conditional members, decided in a set against the members whose metadata matches, and against none alone.

* **D5 — the home and the name.** Tempo, as `Tempo.DateRule` (user, 2026-10-27).

Taken by the user on 2026-10-27, for tempo_holidays to compile its dataset with `Tempo.DateRule` (a census of its 5,154 entries counts each):

* **D6 — observed days.** `parse(rule, observed: :as_written | :moved | :none)`: as written (the default); each clause moving the date, an `and` adding nothing (tempo_holidays' `dates: :substitute`, 333 `and if` entries); or no observed day (`:gazetted`), which leaves a `substitutes` rule, only observed days, no date (amended by D12: it was the dates the rule substitutes for, which `:replaced_by` does not use).

* **D12 — a substitutes rule read with `observed: :none`** (user, 2026-10-27). An empty set, so tempo_holidays' `dates: :gazetted` passes `observed: :none` to every rule and drops what is empty.

* **D7 — substitute entries.** `parse(rule, replaced_by: [entry])`: the date read as not on the entry's trigger weekdays in the entry's years, a recurrence with its ISO 8601 text (229 `substitutes …` entries stand in for a holiday of their type).

* **D8 — the dataset's metadata.** `parse(rule, active: windows, disable: dates, enable: dates)`, folded into the domain as tempo_holidays folds them now: a disabled date takes its year out of the member that gives it, an enabled date is a one-year member (253, 51 and 45 entries).

* **D9 — a period split at the year end** (tempo_holidays). One member, the union of the two dated spans coalesced into the one period (Victoria's term 4 holidays, five pairs).

## Tasks

* [ ] **tempo_holidays on Tempo.DateRule** — its dataset compiled with it; its conformance corpus unchanged.

### Deferred

* [ ] **The Bengali calendar** — eight rules of the dataset (`bengali-revised 1-1` …) and two of the parser's tests, read as a named error. Set aside by the user (2026-10-27); it needs a Bengali (revised) calendar in Calendrical, which has none.

* [ ] **An `if is holiday` move by more than one, or back** — `if is holiday then 2nd next Tuesday`. `Tempo.RecurrenceSet.move_when/2` moves to the first span its selector gives after the occurrence and takes no count; no rule of the dataset needs one.

* [ ] **`if equal`** — `2nd sunday after 05-01 if equal easter 49 then 3rd sunday after 05-01`: the date replaced when it falls on another rule's date, a primitive `Tempo.RecurrenceSet` does not have; no rule of the dataset needs one.

### Done

* [x] **A year of the sexagenary cycle** — on Calendrical 2.2's `elapsed_years/2` (`Tempo.Calendar.year_of_cycle/3`): a lunisolar date written with its cycle and year falls in that year of its calendar (`chinese 78-32-08-0-15`, 2015-09-27), and a solar term in the Gregorian year that year begins in (`chinese 78-32-8-15 solarterm`, 2015-06-04). The parser drops the cycle and reads the date in every year. 2026-10-27.

* [x] **The options for a holiday dataset** — `:observed` (D6), `:active`, `:disable` and `:enable` (D8) and `:replaced_by` (D7), in `parse/2` and the guide's "Reading a holiday dataset"; `parse/2` refuses an option it does not take. Against tempo_holidays' `Rule` over 2000–2035: 773 readings of the dataset's observed-day rules the same; 269 of 270 entries with `active`, `disable` or `enable`; and in its `:substitute` reading 1,949 of 1,954 holidays, all 386 with `substitutes` entries among them, the five others spans `Rule` read as one day. A disabled date takes out its year of the rule's own calendar, where `Rule` took the Gregorian year and added back the rest. 2026-10-27.

* [x] **`Tempo.DateRule.parse/2` documented** — the guide (`guides/date-rules.md`), each part of the grammar with the dates it falls on, its examples run; the moduledoc, the README, the holiday cookbook and the CHANGELOG. Two defects found writing it and fixed: a rule's directions were made atoms by the atom table, so a rule read before the modules naming them were loaded raised; a span was counted from midnight and dropped on a weekday step or an observed day, where the parser counts it from the time of day on every date (four dataset rules, `1st saturday in October P2D` among them, now span their days). 2026-10-27.

* [x] **The census gaps** — a count of days or a weekday step from any date, chained as windows (an equinox, a solstice, Easter, a solar term, a weekday step before a weekday step); a solar term's later day; a date of another calendar in a year of its own (`31 Shahrivar 1401`, `julian 2015-01-09`); `if is holiday then next day omit …`. The parser's `Adar` is the sixth month in order, Adar I in a leap year, where it was read as Adar II. 1,556 of the dataset's 1,564 rules read, all but the Bengali, with only the two new ones written differently; the 97 rules of the parser's own tests that read a rule alone (`test/fixtures/date_holidays_parser_dates.json`) fall on the dates they expect, but the two Bengali. 2026-10-27.

* [x] **Reading tokens into expressions** — `Tempo.DateRule.parse/2` (`Tempo.Reader.DateRule.Plan`, `.Expression`), tempo_holidays' recurrence builders moved here without its dataset metadata, a week's days asked of the calendar and the grammar's calendar words in `Tempo.Calendar`. Checked against tempo_holidays on every distinct rule of its 3.38.0 fixtures: 1,534 of 1,564 build the same expression, 20 another of the same dates (the nth weekday after the first of a month as a weekday-in-month, a solar term in the default calendar, the fifth Monday's window), and the 10 that fail both are the known gaps. A span in hours is the days it reaches into (`PT90H` four), where tempo_holidays reads one. 2026-10-27.

* [x] **The tokenizer** — `Tempo.Reader.DateRule` (`tokens/1`, `tokenize/1`), tempo_holidays' `Grammar` moved here; every one of the 119 rules of date-holidays-parser's fixture (`test/fixtures/date_holidays_parser_tokens.json`, its ISC notice in `NOTICE`) reads to the parser's tokens. 2026-10-27.
