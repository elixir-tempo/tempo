# Date rules

**Status:** planning, 2026-10-27

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

## Tasks

* [ ] **The tokenizer** — tempo_holidays' `Tempo.Holidays.Grammar` (every rule of the parser's fixture reads to its tokens) moved here, with the fixture and its ISC notice.

* [ ] **Reading tokens into expressions** — each part to its Tempo form, tempo_holidays' recurrence builders moved here; every rule of the parser's fixture and of the 3.38.0 dataset read, but Bengali.

* [ ] **The census gaps** — the productions above that tempo_holidays did not compile.

* [ ] **`Tempo.DateRule.parse/2`** — the API, its options and errors, and the guide: each production with examples that run.

* [ ] **tempo_holidays on Tempo.DateRule** — its dataset compiled with it; its conformance corpus unchanged.
