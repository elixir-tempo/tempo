# The date rule grammar

This is the grammar of every rule `Tempo.DateRule.parse/2` reads, written in the ABNF of [RFC 5234](https://www.rfc-editor.org/rfc/rfc5234) and transcribed from the readers of [date-holidays-parser](https://github.com/commenthol/date-holidays-parser) v3.4.7 (`src/Parser.js`), the parser of the [date-holidays](https://github.com/commenthol/date-holidays) dataset. A rule read here gives the dates that parser gives it. The [date rules guide](./date-rules.md) shows how to write and use rules; this page is the reference for what each part may be and what it reads to.

The reader (`lib/tempo/reader/date_rule.ex`) has one reader for each production of section 2 to 6, tried in the parser's order (section 7), and gives the parser's tokens: the parser's own fixture of 119 rules, with the tokens it makes of each, is its golden test.

**What the grammar decides, and what it does not.** The grammar says which rules are well formed. It does not say which name a date: `13-01` is a `gregorian` date by this grammar and is refused when the rule is read, because there is no thirteenth month, with the `Tempo.InvalidDateError` that says so. What a rule *means* is the reading of section 8, as date-holidays-parser reads it.

## 1. Lexical rules

Every quoted string is matched as it is written, with its case (RFC 7405's `%s`); where the parser takes a word with a capital or a small first letter, both are written.

```abnf
SP          = 1*%x20                          ; parts are separated by spaces
DIGIT       = %x30-39
n           = 1*DIGIT                         ; a count
ordinal     = n ["st" / "nd" / "rd" / "th"]   ; "2nd", "4th", or "2"
year        = 1*4DIGIT                        ; leading zeros allowed
month       = 1*2DIGIT                        ; 1 to 12, a leading zero allowed
day         = 1*2DIGIT

weekday     = ("S" / "s") "unday" / ("M" / "m") "onday" / ("T" / "t") "uesday"
            / ("W" / "w") "ednesday" / ("T" / "t") "hursday" / ("F" / "f") "riday"
            / ("S" / "s") "aturday"
weekdays    = weekday *("," [" "] weekday)     ; "saturday, sunday", "Saturday,Sunday"
type        = "public" / "bank" / "school" / "observance" / "optional"
```

## 2. The base date

A rule has one base date, which its steps step from and its modifiers apply to.

### 2.1 A Gregorian date, a month

```abnf
gregorian   = [year "-"] month "-" day        ; "12-25", "2015-10-09"
month-start = "January" / "February" / "March" / "April" / "May" / "June" / "July"
            / "August" / "September" / "October" / "November" / "December"
julian      = "julian " gregorian             ; "julian 12-25", a date of the Julian calendar
```

A month alone is its first day: `February` is `02-01`. A date with a year falls in that year alone, a Julian date with a year in that year of the Julian calendar.

### 2.2 Easter

```abnf
easter      = ("easter" / "orthodox") [" " offset [[" "] ("days" / "day" / "d")]]
offset      = ["+" / "-"] 1*2DIGIT            ; "easter -2", "orthodox 49", "easter 1 day"
```

`easter` is the Western Easter Sunday and `orthodox` the Orthodox, reckoned in the Julian calendar; the offset is a count of days from it, at most 99 either way.

### 2.3 An equinox or a solstice

```abnf
equinox     = season " " ("equinox" / "solstice") [" in " (zone / shift)]
season      = ("M" / "m") "arch" / ("J" / "j") "une" / ("S" / "s") "eptember"
            / ("D" / "d") "ecember"
zone        = 1*(%x21-7E)                     ; a time zone name, "Asia/Tokyo"
shift       = ("+" / "-") 2DIGIT ":" 2DIGIT   ; "+09:00"
```

The day of the equinox or solstice is the day it falls on in the zone, or at the shift; with neither, in UTC.

### 2.4 A date in the Islamic, Hebrew or Persian calendar

```abnf
islamic     = day " " islamic-month [" " year]
hebrew      = day " " hebrew-month [" " year]
persian     = day " " persian-month [" " year]

islamic-month = "Muharram" / "Safar" / "Rabi al-awwal" / "Rabi al-thani" / "Jumada al-awwal"
              / "Jumada al-thani" / "Rajab" / "Shaban" / "Ramadan" / "Shawwal"
              / "Dhu al-Qidah" / "Dhu al-Hijjah"
hebrew-month  = "Nisan" / "Iyyar" / "Sivan" / "Tamuz" / "Av" / "Elul" / "Tishrei"
              / "Cheshvan" / "Kislev" / "Tevet" / "Shvat" / "AdarII" / "Adar"
persian-month = "Farvardin" / "Ordibehesht" / "Khordad" / "Tir" / "Mordad" / "Shahrivar"
              / "Mehr" / "Aban" / "Azar" / "Dey" / "Bahman" / "Esfand"
```

An Islamic date is read in the Umm al-Qura calendar (`Calendrical.Islamic.UmmAlQura`), a Hebrew one in `Calendrical.Hebrew` and a Persian one in `Calendrical.Persian`. A year written with the date is a year of that calendar, and the date falls in that year alone.

A Hebrew month is its traditional month, the same month in every year: Nisan is the seventh month of an ordinary year and the eighth of a leap year. `Adar` is the sixth month in order, Adar I in a leap year and Adar in an ordinary one; `AdarII` is the Adar of Purim, Adar in an ordinary year and Adar II in a leap year. An Islamic day past the end of a short month runs on into the next: `30 Ramadan` in a Ramadan of 29 days is the first of Shawwal.

### 2.5 A date in the Chinese, Korean or Vietnamese calendar

```abnf
lunisolar   = lunisolar-calendar " " [cycle "-" year "-"] month "-" leap "-" day
solar-term  = lunisolar-calendar " " [cycle "-" year "-"] term "-" day " solarterm"
lunisolar-calendar = "chinese" / "korean" / "vietnamese"
cycle       = 1*DIGIT                         ; a sexagenary cycle, counted from 2637 BCE
leap        = "0" / "1"                       ; 1 for the leap month after the month
term        = 1*2DIGIT                        ; 1 to 24, the solar terms from lichun
```

`chinese 01-0-01` is the first day of the first month, which is not a leap month; a day of `00` is the eve of the month, the day before its first. A solar term is numbered from the start of spring, and its day `01` is the day the term begins, a later day being days from it:

| Term | Name | Term | Name | Term | Name | Term | Name |
|---|---|---|---|---|---|---|---|
| 1 | lichun | 7 | lixia | 13 | liqiu | 19 | lidong |
| 2 | yushui | 8 | xiaoman | 14 | chushu | 20 | xiaoxue |
| 3 | jingzhe | 9 | mangzhong | 15 | bailu | 21 | daxue |
| 4 | chunfen | 10 | xiazhi | 16 | qiufen | 22 | dongzhi |
| 5 | qingming | 11 | xiaoshu | 17 | hanlu | 23 | xiaohan |
| 6 | guyu | 12 | dashu | 18 | shuangjiang | 24 | dahan |

A date is read in `Calendrical.Chinese`, `Calendrical.Korean` or `Calendrical.Vietnamese`, and a solar term at the Chinese meridian. A cycle and year (`chinese 78-32-8-15 solarterm`), and a solar term of the Korean or Vietnamese calendar, are not read yet (section 9).

### 2.6 A date in the revised Bengali calendar

```abnf
bengali     = "bengali-revised " [["-"] year "-"] month "-" day
```

Not read yet: Calendrical has no Bengali calendar (section 9).

## 3. Steps from a date

```abnf
step        = [ordinal " "] (weekday / "day") ["s"] " " direction
direction   = "before" / "after" / "next" / "previous" / "in"
```

A rule has any number of steps before its base date, each stepping from the date after it: `Friday after 4th Thursday in November` is the 4th Thursday from the 1st of November, then the Friday after it. A step of `day` or `days` is a count of days; a weekday step is the `ordinal`-th such weekday.

* **after** — on or after the date: `2nd sunday after 05-01` is the second Sunday of May, the 1st itself when it is a Sunday.

* **in** — after the first of the month written next: `2nd Monday in June`.

* **next** — strictly after the date, a week on when the date is that weekday.

* **before**, **previous** — strictly before the date.

## 4. A time of day and a length

```abnf
time        = ["T"] 1*2DIGIT ":" 1*2DIGIT / "T" 1*2DIGIT    ; "14:00", "T16"
duration    = "P" [n "D"] ["T" [n "H"] [n "M"]]             ; "P4D", "PT90H", "P1DT12H"
```

A holiday is read as the days it covers. A time is when it starts, and it lasts to the midnight after it; a duration is how long it lasts from then, so `12-31 14:00 PT12H` covers the 31st and the 1st.

## 5. Observed days

```abnf
observed    = "if " weekdays " then" [" " ("next" / "previous") " " weekday] *(" " (time / duration))
substitutes = "substitutes"                   ; the rule gives its observed days alone
and         = "and"                           ; the date is kept beside its observed day
```

`if sunday then next monday` moves the date to the Monday after it when it is a Sunday. Clauses are read in order, each on the weekdays no earlier clause took. A clause after `and` keeps the date and adds its observed day; a rule that begins `substitutes` gives its observed days alone. A clause with a time and no weekday (`if Sunday then 00:00`) changes when the date starts, and is read only where that leaves its days unchanged. An observed day carries `%{substitute: true}` in its metadata.

## 6. Filters, conditions and years

```abnf
on-weekdays = ["not "] "on " weekdays          ; "on Monday, Tuesday", "not on Friday"
in-years    = "in " ("even" / "odd" / "leap" / "non-leap") " years"
every-years = "every " n " year" ["s"] " since " year
since       = "since " year ["-" month ["-" day]] [" and"]
prior-to    = "prior to " year ["-" month ["-" day]]

bridge      = "if " gregorian *(" and " gregorian) " is " [type " "] "holiday"
if-holiday  = "if is " [type " "] "holiday then" [" " ordinal] [" " direction " " (weekday / "day")]
              [" omit " weekdays]
if-equal    = "if equal " base " then " base
same-day    = "#" 1*DIGIT                     ; a rule kept apart from another of the same text
```

* **on**, **not on** — the date in the years it falls, or does not fall, on one of the weekdays.

* **in even years**, **in odd years**, **in leap years**, **in non-leap years** — the date in those years; leap years are the calendar's own.

* **every n years since** — the date every n years from that year.

* **since**, **prior to** — the years from the one given, and those before it; with a month or a day, the years whose date is on or after it, or before it. A year here is a Gregorian year, also for a date of another calendar: `12 Cheshvan since 1997` is from the Hebrew year that begins in 1997.

* **bridge** — the date kept only when the dates given are holidays of the type (`public` where none is named): a conditional member, decided in a `Tempo.RecurrenceSet` against its members whose metadata holds that type.

* **if is holiday then** — the date moved, when it falls on a holiday of the type, to the next weekday given or the next day, skipping the weekdays omitted: a conditional member, decided as a bridge is. A move by more than one or back is not read yet.

* **if equal** — not read yet.

## 7. The rule, and the order the parts are read in

```abnf
base        = julian / gregorian / easter / islamic / hebrew / persian / equinox
            / solar-term / lunisolar / bengali / month-start
part        = base / observed / on-weekdays / in-years / every-years / step / if-holiday
            / bridge / time / duration / substitutes / and / "if" / "then" / if-equal
            / same-day / since / prior-to
rule        = part *(SP part)
```

A rule is read from the start: at each place the parts are tried in the order the parser tries them, and the first that reads the text there is taken.

1. `julian`, `gregorian`, `easter`, `islamic`, `hebrew`, `persian`, `equinox`, `solar-term`, `lunisolar`, `bengali`, `month-start`

2. `observed`, `on-weekdays`, `in-years` and `every-years`, `step`, `if-holiday`, `bridge`

3. `time`, `duration`, then the words `substitutes`, `and`, `if equal`, `then` and `if`

4. `same-day`, `since`, `prior-to`

The parts are then put in order: the base date first, its steps after it, the one nearest it first. Text no part reads is an error that names it.

## 8. What a rule reads to

A rule reads to a yearly recurrence in the base date's calendar, `R/../P1Y/F…N`, its years in its domain (`R/{2020Y..2024Y}/…`); a rule with observed days to a `Tempo.RecurrenceSet` of the date and its observed days; a bridge or an `if is holiday` move to a conditional member. A step is an ISO 8601-2 §12.10 window off the date it steps from with the weekday selected in it, and Easter, an equinox, a solstice and a solar term are `Tempo.Event` events.

| Rule | Reads to |
|---|---|
| `12-25` | `R/../P1Y/FL12M25DN` |
| `2015-10-09` | `R/{2015Y}/P1Y/FL10M9DN` |
| `2nd Monday in June` | `R/../P1Y/FL6M1K2IN` |
| `Monday before 06-01` | `R/../P1Y/FLL6M1DN/P-7D1K1IN` |
| `easter -2` | `R/../P1Y/FLL(easter)eN/P-3D5K1IN` |
| `march equinox in Asia/Tokyo` | `R/../P1Y/FL(march-equinox@Asia/Tokyo)eN` |
| `15 Nisan` | `R/../P1Y/FL7m15DN[u-ca=hebrew]` |
| `chinese 01-0-01` | `R/../P1Y/FL1m1DN[u-ca=chinese]` |
| `chinese 5-01 solarterm` | `R/../P1Y/FL(qingming)eN` |
| `12-25 P4D` | `R/../P1Y/FLL12M25DN/P4DN` |
| `12-25 since 2020 prior to 2025` | `R/{2020Y..2024Y}/P1Y/FL12M25DN` |
| `03-02 in even years` | `R/..e/P1Y/FL3M2DN` |
| `12-26 not on Friday, Monday` | `R/../P1Y/FL12M26D{2..4,6..7}KN` |
| `01-01 and if sunday then next monday` | `{R/../P1Y/FL1M1DN,R/../P1Y/FLL1M1D7KN/P8D1K-1IN}` |

The holiday around a rule in date-holidays' dataset, which is not part of the rule, is given to `Tempo.DateRule.parse/2` as options: `:observed` (its observed days as written, moved, or none), `:active` (the windows it is active in), `:disable` and `:enable` (a date moved from one day to another), `:replaced_by` (the `substitutes` entries that may stand in for it) and `:falls_on` (what a bridge or a move is decided against).

## 9. What is not read

These are well formed and return a `Tempo.ParseError` that names them:

* **The Bengali calendar** — `bengali-revised 1-1`: Calendrical has no Bengali calendar.

* **A year of the sexagenary cycle** — `chinese 78-32-8-15 solarterm`. date-holidays-parser drops the cycle and its year and reads the date in every year; Tempo reads it in that year or not at all.

* **A solar term of the Korean or Vietnamese calendar** — `korean 5-01 solarterm`.

* **`if equal`** — `2nd sunday after 05-01 if equal easter 49 then 3rd sunday after 05-01`.

* **An `if is holiday` move by more than one, or back** — `if is holiday then 2nd next Tuesday`.

* **A clause that moves the end of a date into another day** — `12-31 14:00 PT12H if Sunday then 00:00`.

* **A year filter on a date of another calendar**, and a year both even or odd and leap or not.

## 10. How the grammar is tested

The reader's tokens are held to date-holidays-parser's own: its fixture of 119 rules (`test/fixtures/date_holidays_parser_tokens.json`, ISC licence, in `NOTICE`) records the tokens it makes of each, and every one reads to them. What the rules read to is held to the dates the parser's own tests expect (`test/fixtures/date_holidays_parser_dates.json`, 97 rules), and every rule of the date-holidays dataset reads but the Bengali.
