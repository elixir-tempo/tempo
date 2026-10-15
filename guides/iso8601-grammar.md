# The grammar Tempo reads

This is the grammar of every text `Tempo.from_iso8601/2` reads and `Tempo.to_iso8601/1` writes, written in the ABNF of [RFC 5234](https://www.rfc-editor.org/rfc/rfc5234) and transcribed clause by clause from ISO 8601-1:2019, ISO 8601-2:2019 and RFC 9557. Each production names the clause it comes from. Productions that are Tempo's own, and not in any standard, are in section 4 and marked `; Tempo`.

The reader (`lib/tempo/reader.ex`) is written as one function per production, in the order given here, so that the code can be held against the standard and this page against the code. A generator built from this grammar produces texts the reader must accept and round-trip through the writer, and a mutator produces texts it must refuse; the examples of the two standards (ISO 8601-1 Annex A, ISO 8601-2's worked examples) are a table beside them.

**What the grammar decides, and what it does not.** The grammar says which texts are well formed. It does not say which are *valid*: `2026-13-01` is a `date-extended` by this grammar and is refused when the value is validated, because the calendar has no thirteenth month; `2026-03-29T02:30[Europe/Paris]` is well formed and refused because the clock skips that reading; `2026-07/2026-06` is well formed and refused because its end is before its start. Ranges of values, the existence of a date, the readings a zone's clock shows and the order of an interval's ends are the validator's, after the reader. Likewise the grammar does not say what a text *means*: that is `plans/architecture-redesign.md`, section 4, and in particular the reading of a written end (law 9).

**Ambiguity.** ABNF is declarative and ISO 8601's basic format is not prefix-free: `1985` is a year, `198504` is not a month (ISO 8601-1 §5.2.2.2 forbids the basic form of a year and month), `19850412` is a date and `1985102` an ordinal date. The reader tells the basic forms apart by the length of a digit run, as ISO 8601-1 §5.2 does, and this page notes each such rule where it applies. Where ISO 8601-2 makes a form ambiguous (a bare integer set, `{1,2}`, is a set of years in one place and of integers in another), the context production says which reading applies.

## 1. Lexical rules

```abnf
DIGIT      = %x30-39                          ; RFC 5234
ALPHA      = %x41-5A / %x61-7A
integer    = 1*DIGIT                          ; [i] in both parts, with leading zeros allowed by ISO 8601-2 §4.3.2
negint     = ["-"] integer                    ; [negi], ISO 8601-2 §4.4.1.1
decimal    = ("." / ",") 1*DIGIT              ; the decimal sign and fraction, ISO 8601-1 §3.2.6, §5.3.1.4
```

Tempo writes `.` and reads either sign. A fraction belongs to the lowest-order component written, and no component follows it (ISO 8601-1 §5.3.1.4).

## 2. ISO 8601-1:2019, the core representations

### 2.1 Time scale components in implied form

```abnf
year       = 4DIGIT                           ; §3.2.2 [year], 0000 to 9999
month      = 2DIGIT                           ; [month], 01 to 12 by the Gregorian calendar; Tempo validates by the value's calendar
day        = 2DIGIT                           ; [day]
week       = 2DIGIT                           ; [week]
dayk       = DIGIT                            ; [dayk], 1 to 7 from Monday
dayo       = 3DIGIT                           ; [dayo], 001 to 366
hour       = 2DIGIT                           ; [hour], 00 to 23; 24 is refused (§5.3.2)
minute     = 2DIGIT                           ; [min]
second     = 2DIGIT                           ; [sec]; 60 is a leap second and is refused by Tempo (see the conformance guide)
dec        = 3DIGIT                           ; [dec], a decade, §5.2.2.2 c)
cent       = 2DIGIT                           ; [cent], a century, §5.2.2.2 d)

sign       = "+" / "-"                        ; [±]
year-x     = sign 4*DIGIT                     ; an expanded year, §5.2.2.3: the agreed extra digits, signed
dec-x      = sign 3*DIGIT                     ; an expanded decade, [dec(5)] in the example
cent-x     = sign 2*DIGIT                     ; an expanded century, [cent(4)]
```

An expanded year must be signed and is written with a fixed number of digits agreed between the parties; Tempo accepts any run of four or more digits after the sign and writes the fewest it needs (ISO 8601-2 §4.7 removes the need for agreement with the `Y` prefix of 3.6).

### 2.2 Calendar date

```abnf
date-basic      = (year / year-x) month day                  ; §5.2.2.1 a), 19850412
date-extended   = (year / year-x) "-" month "-" day          ; §5.2.2.1 b), 1985-04-12
year-month      = (year / year-x) "-" month                  ; §5.2.2.2 a), 1985-04; there is no basic form
year-only       = year / year-x                              ; §5.2.2.2 b), 1985
decade          = dec / dec-x                                ; §5.2.2.2 c), 198 (the 1980s)
century         = cent / cent-x                              ; §5.2.2.2 d), 19 (the 1900s)
```

Reading rule: a bare run of digits with no separator and no designator is a year when it has four digits, a decade with three, a century with two, and a calendar date with eight; six digits is not a date (§5.2.2.2 forbids a basic year-month), and seven digits is an ordinal date (2.3). A signed run is read the same way after its sign, by the agreed width.

### 2.3 Ordinal date

```abnf
odate-basic     = (year / year-x) dayo                       ; §5.2.3.1 a), 1985102
odate-extended  = (year / year-x) "-" dayo                   ; §5.2.3.1 b), 1985-102
```

### 2.4 Week date

```abnf
wdate-basic     = (year / year-x) "W" week dayk              ; §5.2.4.1 a), 1985W155
wdate-extended  = (year / year-x) "-W" week "-" dayk         ; §5.2.4.1 b), 1985-W15-5
week-basic      = (year / year-x) "W" week                   ; §5.2.4.2 a), 1985W15
week-extended   = (year / year-x) "-W" week                  ; §5.2.4.2 b), 1985-W15
```

### 2.5 Time of day

```abnf
time-basic      = "T" hour [minute [second [decimal]]]       ; §5.3.1.2 a), §5.3.1.3, §5.3.1.4: T232050, T2320, T23, T232030,5
time-extended   = ["T"] hour ":" minute [":" second] [decimal]  ; §5.3.1.2 b), §5.3.1.3 a): 23:20:50, 23:20; the T may be omitted (§5.3.5)
time-hour-frac  = "T" hour decimal                           ; §5.3.1.4 c), T23.3; basic only
time-minute-frac = "T" hour minute decimal                   ; §5.3.1.4 b) basic, T2320,8
                 / ["T"] hour ":" minute decimal             ; §5.3.1.4 b) extended, 23:20,8
time            = time-basic / time-extended / time-hour-frac / time-minute-frac
```

A fraction may follow the hour, the minute or the second and nothing follows it. `T` is required in the basic format, where `1920` would otherwise be a year (§5.3.5), and is written by Tempo in every time of day. Tempo reads a basic time with no `T` only where the text cannot be a date: `093455`, which has six digits, and `0934,9` or `23Z`, where a fraction or a shift follows the run (§5.3.1.3 lets the `T` be omitted where no ambiguity arises). RFC 3339 §5.6's allowances, a space or a lower-case `t` before an extended time and a lower-case `z`, and ISO 8601-1 §3.4.2's hyphen (U+2010) and minus (U+2212), are read as the ASCII forms.

### 2.6 UTC and the time shift

```abnf
utc             = "Z"                                        ; §5.3.3
shift-basic     = sign hour minute                           ; §5.3.4.1 a) [shift], +0100
shift-hour      = sign hour                                  ; [shiftH], +01
shift-extended  = sign hour ":" minute                       ; §5.3.4.1 b) [shiftX], +01:00
shift           = utc / shift-basic / shift-hour / shift-extended
```

A shift is written after a time of day, without a space (§5.3.4.2), and belongs to the written end it follows (`plans/architecture-redesign.md`, law 5). Tempo also reads a shift after a date with no time of day, as ISO 8601-2 §7.5 allows in the explicit form. `Z` names UTC and asserts no local time; `+00:00` asserts a local time at no offset, is held apart from `Z` and is written back as `Z0H0M`; `-00:00` is `Z` (RFC 9557 §2).

### 2.7 Date and time of day

```abnf
date-any-basic     = date-basic / odate-basic / wdate-basic
date-any-extended  = date-extended / odate-extended / wdate-extended
datetime-basic     = date-any-basic time-basic [shift]                       ; §5.4.2 a), §5.4.3
datetime-extended  = date-any-extended "T" hour [":" minute [":" second]] [decimal] [shift]   ; §5.4.2 b): the T is required here
```

The whole expression is in one format: a basic date takes a basic time and an extended date an extended time (§5.4.3). The date part is complete; the time may be reduced.

### 2.8 Duration

```abnf
duration-units  = [integer "Y"] [integer "M"] [integer "D"] ["T" [integer "H"] [integer "M"] [integer "S"]]   ; §5.5.2.2 a)
duration-weeks  = integer "W"                                                 ; §5.5.2.2 b): in Part 1 W stands alone
duration        = "P" (duration-units / duration-weeks)                       ; at least one component, §5.5.2.3 a)
duration-alt    = "P" (date-basic "T" hour minute second / date-extended "T" hour ":" minute ":" second
                      / odate-basic "T" hour minute second / odate-extended "T" hour ":" minute ":" second)   ; §5.5.2.4, P00020110T223355
```

The lowest-order component may carry a `decimal` (§5.5.2.3 b)). ISO 8601-2 §11 widens durations (3.10): weeks beside other units, negative components and a leading sign. Tempo reads the widened form everywhere a `duration` is named below.

### 2.9 Time interval

```abnf
interval-start-end       = point "/" point                    ; §5.5.3.1, 1985-04-12T23:20:50/1985-06-25T10:30:00
interval-start-duration  = point "/" duration                 ; §5.5.3.2
interval-duration-end    = duration "/" point                 ; §5.5.3.3
interval                 = interval-start-end / interval-start-duration / interval-duration-end
point                    = datetime-basic / datetime-extended / date-any-basic / date-any-extended
                         / year-month / year-only / week-basic / week-extended / time / explicit-datetime   ; §5.5.4 allows ends other than complete
```

Both ends are in one format. **The abbreviated end** (§5.5.1): higher-order components may be omitted from the end when the result is unambiguous, and are taken from the start: `2018-01-15/02-20` is `2018-01-15/2018-02-20`. Tempo reads an end of one or two components of the extended format, or of the explicit form, by the units it names (`2026-06-15/20`, `2026Y1M15D/2M20D`), and refuses an abbreviated end that would be before the start (ISO 8601-2 §7.14.2 Example 2). A shift on the start applies to the end unless the end has one (§5.5.1 Example 2).

### 2.10 Recurring time interval

```abnf
recurrence      = "R" [integer] "/" interval                  ; §5.6.2, §5.6.3: R12/1985-04-12T23:20:50/P1Y2M15DT12H30M0S
```

An absent count is an unbounded recurrence. ISO 8601-2 §13 adds the repeat rule (3.14).

## 3. ISO 8601-2:2019, the extensions

### 3.1 Explicit time scale components (§4.3, §7)

```abnf
yearE      = negint "Y"                       ; §7.2, §4.4.1.2: 1985Y, -2018Y
monthE     = integer "M"
weekE      = negint "W"                       ; §4.4.1.3: a negative week counts from the year's end
dayE       = negint "D"                       ; §4.4.1.4: -5D is the fifth last day of the month
daykE      = integer "K"                      ; §4.3.3, 1K is Monday
dayoE      = negint "O"                       ; §4.3.4, §4.4.1.5
hourE      = integer "H"
minE       = integer "M"                      ; the M after T is a minute
secE       = integer "S"
decE       = negint "J"                       ; §4.3.5, 196J is the 1960s
centE      = negint "C"                       ; §4.3.6, 16C is the 1600s
seasonE    = integer "A"                      ; §4.8.2 c), 21A to 41A (Tempo reads the month-slot form of 3.7 and does not read A)
yearB      = integer "YB"                     ; §4.4.1.6, 12YB is the twelfth year before year one, -11Y
```

Leading zeros are allowed in every explicit value (§4.3.2): `01M` is January. A value is any `negint`, so the explicit form has no digit-count ambiguity; its unit is its designator.

A decade or a century is written alone (§4.3.5, §4.3.6). Tempo also reads one before the units a year holds, filling the years between (`202J6M` is June of each year of the 2020s); a year written after one is a year it names (`202J2026Y`, `-12J-125Y`), one it does not name is an error, and so is a decade written after a century.

### 3.2 Exponents and significant digits (§4.4.2, §4.4.3)

```abnf
exp        = negint "E" integer               ; 3E3 is 3000; 17E7Y is the year 170000000
sig        = negint "S" integer               ; 1950S2 is some year 1900 to 1999, estimated 1950
exp-sig    = negint "E" integer "S" integer   ; 271828E5S6
value-ext  = exp / sig / exp-sig / negint     ; what replaces [i] in a component that accepts unbounded integers: the year, and a duration's components
```

`sig` is read in a year (`1950S2`, `1950S2Y`); the second `S` of a time of day is a second and cannot follow a number that already ends a component, so `S` is read as significant digits only where the unit is a year or the text is a duration component.

### 3.3 Qualification (§4.5, §8)

```abnf
qualifier  = "?" / "~" / "%"                  ; uncertain, approximate, both: ISO 8601-2 §3.2.6
```

Three placements, in the implied and the explicit form (§8.2):

* **Complete** (§8.2.1): a qualifier at the end of the whole expression, `1985-04-12?`, `1985Y04M12D?`, qualifying every component.
* **Group** (§8.2.2): a qualifier immediately after a component, qualifying it and every component to its left: `2004-06~-11`, `2004Y06M~11D` (year and month approximate).
* **Individual** (§8.2.3): in the implied form a qualifier immediately *before* a component, `2004-%06-%11`; in the explicit form between the value and its designator, `2004Y6%M11%D`.

```abnf
component-q     = [qualifier] component [qualifier]           ; implied form: a leading individual qualifier, a trailing group qualifier
componentE-q    = negint [qualifier] designator [qualifier]   ; explicit form: individual between value and designator, group after
expression-q    = expression [qualifier]                      ; complete
```

An end of an interval may be qualified (§10.3): `1984?/2004~`, `2004-06-~01/2004-06-~20`. A qualifier is not an extension in the sense of law 5: it stays on the component or end it is written on.

### 3.4 Unspecified digits (§4.6, §9)

```abnf
x-digit         = DIGIT / "X"
unspecified     = "X*"                                        ; §4.6.2: the whole value is unspecified, explicit form only: X*D
year-mask       = 4x-digit                                   ; §9.2.1.2 c), §9.2.2: 201X, 1XXX, XXXX; implied form, four digits
month-mask      = 2x-digit                                   ; 1999-XX, 1560-X2
day-mask        = 2x-digit                                   ; 1999-01-XX
masked-valueE   = 1*x-digit / unspecified                     ; explicit form: 195XY, 1390YXXM, 2052Y1MX*D, X*Y
```

A masked digit stands for any digit (§4.6.3); in the implied form an unspecified component is every digit masked. Tempo reads a mask in any component of the implied and the explicit forms, including the week, the day of the year and the clock (§9.3: `2018Y3M17DT20H40MX*S`).

### 3.5 Expanded calendar year with a prefix (§4.7)

```abnf
year-p          = "Y" negint                                 ; §4.7.2: Y1700000002, Y-1700000002
year-e          = "Y" negint "E" integer                     ; §4.7.3: Y17E7
year-s          = "Y" negint ["E" integer] "S" integer       ; §4.7.4: Y171010000S3, Y3388E2S3
```

A prefixed year is a whole date of year resolution and takes no month or day in the implied form; in the explicit form it is the `yearE` of 3.1 with `value-ext`.

### 3.6 Negative years, decades and centuries in the implied form (§4.4.1)

```abnf
year-neg        = "-" year                                   ; §4.4.1.2 a): -1985
dec-neg         = "-" dec                                    ; §4.4.1.7 a): -019 is the years -199 to -190
cent-neg        = "-" cent                                   ; §4.4.1.8 a): -19 is the years -1999 to -1900
```

In the implied form a negative year has exactly four digits (`-0001`), a negative decade three and a negative century two; the explicit form (3.1) has no digit limit.

### 3.7 Seasons and divisions of a year (§4.8)

```abnf
season          = "21" / "22" / "23" / "24"                  ; §4.8.2 a): spring, summer, autumn, winter, independent of location
ydivision       = "21" / "22" / ... / "41"                   ; §4.8.2 b): 25 to 32 the hemispheres' seasons, 33 to 36 quarters, 37 to 39 quadrimesters, 40 and 41 halves
year-season     = (year / year-x) "-" (season / ydivision)   ; §4.8.3: 2001-21, 2001-34; the month slot carries the grouping
```

In the explicit form the same values are written in the month's place (`2026Y21M`, `2026Y34M`); the `A` designator of §4.8.2 c) is not read. A quarter, a quadrimester and a half are groups of months (3.8) and are held as such.

### 3.8 Grouped units (§5)

```abnf
group-unit      = "G" duration-units "U"                     ; §5.2: G11DU, GT30MU, G2DT6HU; duration-units without the P
group           = integer group-unit                         ; §5.3: 5G10DU, the fifth group of ten days
group-set       = int-set group-unit                         ; §6.6 Example 3: 2018-{1,3,5}G2MU
group-datetime  = higher-units (group / group-set) [lower-units]   ; §5.4.2: 2018Y4G60DU6D, 2018-02-2G14DU, 2018Y9M2DT3GT8HU0H30M
```

A group replaces a time scale unit in a date or time (§5.4.1); the units before it are of higher order than the group's unit and those after it of equal or lower order (§5.4.2). The last group is cut at the boundary of what holds it (§5.4.5.2). Tempo reads a group in the explicit form and, after a `-`, in the implied form.

### 3.9 Sets and ranges (§6)

```abnf
set-all         = "{" member *("," member) "}"               ; §6.1: all members; {1960,1961,1962}
set-one         = "[" member *("," member) "]"               ; §6.2: one member; [1984,1986,1988]
member          = expression / range / open-range
range           = expression ".." expression                 ; §6.3 c): 1670..1673, inclusive, of one precision
open-range      = ".." expression / expression ".."          ; §6.3 a), b): on or before, on or after
int-set         = "{" int-member *("," int-member) "}" / "[" int-member *("," int-member) "]"   ; §6.6, inside a component: {1,2..5}, [1,3,5]
int-member      = negint / negint ".." negint
```

A set holds expressions of different precisions (§6.1 Example 2) and durations (§6.5, `{P1M2S..P1M5S}`); an integer set stands where a component's `[i]` stands (§6.6), so `2026Y{1,3}M` is two months and `{2026,2027}Y` two years. No space is written anywhere in a set. A set written with braces is read as every member and one written with brackets as one member of the set, which has readings and no spans (`plans/architecture-redesign.md`, section 5.1).

### 3.10 Explicit dates, times, shifts and durations (§7, §11)

```abnf
dateE           = yearE [monthE [dayE]] / yearE dayoE / yearE [weekE [daykE]] / decE / centE   ; §7.2, §7.8, §7.9, with reduced precision (§7.13)
timeE           = "T" [hourE] [minE] [secE]                  ; §7.3: T23H20M50S, T23H20M, T30M (hour omitted as zero, §7.10)
shiftE          = "Z" [["-"] [hourE] [minE] [secE]]          ; §7.4: Z, Z-5H, Z8H, Z7H33M14S
datetimeE       = dateE [timeE] [shiftE] / timeE [shiftE] / dateE shiftE   ; §7.5 to §7.7: 1985Y4M12DT23H20M30SZ8H, 1985Y4M12DZ-5H
```

A zero-valued component of higher order than the lowest written may be omitted (§7.10): `T30M0S` is 00:30:00 at second precision. The lowest written component is the precision (§7.11). A fraction may follow the hour, the minute or the second (§7.12). Tempo writes every value in this form: `2026Y6M15DT10H30M`.

```abnf
duration-unitsE = [yearE] [monthE] [weekE] [dayE] ["T" [hourE] [minE] [secE]]   ; §11.2, higher order first; weeks beside other units (§11.3.2 Example 3)
duration-composite = ["-"] "P" duration-unitsE               ; §11.3.2: P3W2D, P-3M-3DT1H5M, -P2M1D; a component may be negative
duration-fraction  = a duration-unitsE whose lowest component carries a decimal   ; §11.4: P1M2.5D
```

The precedence representation of §11.3.3 (`P1YP3MP2D`, one `P` per component to fix the order of evaluation) is not read: Tempo applies years, then months, then clamps, then days, as `Date.shift/2` does, and says so in `Tempo.shift/3`.

### 3.11 Explicit intervals and recurrences (§7.14, §7.15)

```abnf
intervalE       = datetimeE "/" datetimeE / datetimeE "/" duration / duration "/" datetimeE   ; §7.14.1
recurrenceE     = "R" [integer] "/" intervalE                ; §7.15
```

The abbreviated end (§7.14.2) and the shift carried from the start (§7.14.3) apply as in 2.9. An end of either form may be written in the implied form or the explicit, and Tempo reads a mixture (`2026-06-01/2026Y7M1D`).

### 3.12 Open and unknown ends (§10.2)

```abnf
interval-open-end     = point "/" ".."                       ; §10.2 a): 1985-04-12/..
interval-open-start   = ".." "/" point                       ; §10.2 b): ../1985-04-12
interval-open         = ".." "/" ".."                        ; both ends open; Tempo reads it and refuses to walk it
interval-unknown-end  = point "/"                            ; §10.2 c): 1985-04-12/
interval-unknown-start = "/" point                           ; §10.2 d): /1985-04-12
```

Tempo reads an open end as `:open`. An unknown end (a bare `/`) is read as open too, and written back as `..`; the distinction EDTF draws between unknown and open is not kept (see the conformance guide).

### 3.13 Selection (§12)

```abnf
selection       = "L" *selection-rule ["/" duration] "N"     ; §12.1, §12.10: L1K1IN, LL3K4IN/P5DN
selection-rule  = monthSR / weekSR / daySR / daykSR / dayoSR / hourSR / minSR / secSR / positionSR / selection
monthSR         = (negint / int-set) "M"                     ; §12.2.1, 1 to 12
weekSR          = (negint / int-set) "W"                     ; §12.2.2, 1 to 53 and -53 to -1
daySR           = (negint / int-set) "D"                     ; §12.3, 1 to 31 and -31 to -1
daykSR          = (negint / int-set) "K"                     ; §12.4, 1 to 7
dayoSR          = (negint / int-set) "O"                     ; §12.5, 1 to 366 and -366 to -1
hourSR          = "T" (negint / int-set) "H" / (negint / int-set) "H"   ; §12.6, 0 to 23; the T separates the clock rules (§12.11.1 Example 2)
minSR           = (negint / int-set) "M"                     ; §12.7, after T
secSR           = (negint / int-set) "S"                     ; §12.8, 0 to 60
positionSR      = (negint / int-set) "I"                     ; §12.9: the nth of what the rules before it selected, -1 the last; written last
```

Rules are written higher order first (§12.1) and each kind at most once. A position is applied last to the set the other rules made (§12.9). A selection with `/duration` (§12.10) makes each selected element the start of a window of that length, and a selection written after it selects within each window; `L…N` pairs nest from the outside in (`LLL2K2IN/P10DN4K2IN`, the second Thursday within the ten days from the second Tuesday). A selection stands where a time scale component stands in an explicit expression (§12.11): `2018Y3ML1K1IN`, `2018Y9MTLT8H20MN3I`; components written after it apply to each date it selects (§12.11.2); it may be an end of an interval (§12.11.3).

### 3.14 Repeat rules (§13)

```abnf
eligibility     = "F" integer ("Y" / "M" / "W" / "D" / "H" / "M" / "S")   ; §13.4.2: F2W, F1Y; the unit after T is a minute
repeat-rule     = eligibility [selection]                    ; §13.4.1
recurrence-rule = "R" [integer] "/" (interval / intervalE) "/" repeat-rule   ; §13.5: R12/20150929T140000/P1H30M0S/F2W
```

The eligibility part sets the cadence and the eligible interval (the last unit of each repeating interval, §13.4.2 c)); the selection part selects within each eligible interval (§13.4.3); components of the start of lower order than the eligibility's unit that the selection does not name are inherited from it (§13.6.3). Tempo reads a repeat rule with or without `F`: `R/2026-01-01/P1Y/FL12M25DN`, and reads the cadence from the interval's duration where `F` is absent.

## 4. RFC 9557, the IXDTF suffix

Transcribed from RFC 9557 §4.1 (`standards/rfc/rfc9557.txt`).

```abnf
time-zone-initial = ALPHA / "." / "_"
time-zone-char    = time-zone-initial / DIGIT / "-" / "+"
time-zone-part    = time-zone-initial *time-zone-char       ; but not "." or ".."
time-zone-name    = time-zone-part *("/" time-zone-part)
time-numoffset    = ("+" / "-") time-hour ":" time-minute   ; RFC 3339 §5.6
time-zone         = "[" critical-flag (time-zone-name / time-numoffset) "]"
critical-flag     = [ "!" ]
key-initial       = lcalpha / "_"
key-char          = key-initial / DIGIT / "-"
suffix-key        = key-initial *key-char
suffix-value      = 1*alphanum
suffix-values     = suffix-value *("-" suffix-value)
suffix-tag        = "[" critical-flag suffix-key "=" suffix-values "]"
suffix            = [time-zone] *suffix-tag
lcalpha           = %x61-7A
alphanum          = ALPHA / DIGIT
```

A suffix is written once, after the whole expression (law 5): after the end of an interval, after a set, after a recurrence's rule. The time zone, if present, comes first and at most once. A `u-ca` tag names the calendar (`[u-ca=hebrew]`), which Tempo resolves to its calendar module; any other tag is kept as metadata. A critical tag (`[!…]`) that Tempo cannot act on is an error; an elective one may be ignored (RFC 9557 §3.3). A time zone's name is validated against the zone database; a suffix inside an expression, on an end or a member, is a `Tempo.ParseError` that says where it belongs.

## 5. Tempo's own extensions

These are not in ISO 8601 or any RFC. Each is marked `; Tempo`, each is written by `Tempo.to_iso8601/1`, and the conformance guide, section 5, gives their semantics and their interchange risk. A system that reads only the standards will not read them; `Tempo.RRule.to_string/1` is the portable form where one exists.

```abnf
range-step      = negint ".." negint "//" integer            ; Tempo: {1..-1//2}W, every second week
week-of-month   = monthE negint "W"                          ; Tempo: a week of a month, 2026Y6M2W; ISO 8601 has weeks of a year only
week-start      = "[u-fw=" ("mon" / "tue" / "wed" / "thu" / "fri" / "sat" / "sun") "]"   ; BCP 47's first day of the week, a suffix of the whole expression: its weeks begin on that day, RFC 5545's WKST. The Gregorian calendar only
event           = "(" event-name ["@" (time-zone-name / time-numoffset)] ")" "e"   ; Tempo, in a selection: (easter)e, (march-equinox@+09:00)e
event-name      = lcalpha *(lcalpha / DIGIT / "-")
skip            = "(" ("forward" / "backward") ")" "s"       ; Tempo, in a selection, after the day it moves: what is taken for a day or a month the year lacks, RFC 7529's SKIP: 2M29D(forward)s
roll            = "(" convention ")" "r"                     ; Tempo, in a selection, after the day it rolls to a weekday: 31D(modified-nearest)r
convention      = "following" / "preceding" / "nearest" / "modified-following" / "modified-preceding" / "modified-nearest"
traditional-month = (negint / int-set / masked-valueE) ["+"] "m"   ; Tempo: a lunisolar calendar's named month, 8m; its leap month, 6+m
quarter-short   = ("1" / "2" / "3" / "4") "q"                ; Tempo, in a month's place: a quarter, 2026Y2q, held and written as 2026Y34M
half-short      = ("1" / "2") "h"                            ; Tempo, in a month's place: a half of the year, 2026Y1h, held and written as 2026Y40M
exclusion       = "^" member                                 ; Tempo, in a set: a member removed, {2020Y..2024Y,^2022Y}
domain-filter   = set-all ("e" / "o" / "l" / "c")           ; Tempo, after a recurrence's domain: even, odd, leap, common years
domain          = (set-all / set-one / exclusion / domain-filter)   ; Tempo: in a recurrence's interval slot, R/{2020Y..2024Y}/P1Y/…
year-rule       = (negint / int-set / masked-valueE) "Y"     ; Tempo, in a selection: the years an occurrence may fall in, FL{2026,2028}Y1M1DN
time-under-period = (year-only / year-month / week-basic / week-extended / monthE) time   ; Tempo: 2026T17, 2026-06T17, 6MT10H, that time on each day of the period
selection-set   = "{" 1*selection-rule *("," 1*selection-rule) "}"   ; Tempo, in a selection: several selections whose values are taken together, L{1K2I,3K2I}N; a position after it counts among them all
```

Tempo marks its selection extensions with a lowercase designator (`q`, `e`, `m`) so that they are visible at a glance as non-standard; `I` is uppercase because it is ISO 8601-2 §12.9.

## 6. The whole

```abnf
text            = [qualifier] body [qualifier] suffix
body            = recurrence-rule / recurrence / recurrenceE / interval / intervalE / interval-open-end / interval-open-start / interval-open
                / set-all / set-one / duration / duration-composite / duration-alt / value
value           = datetime-basic / datetime-extended / date-any-basic / date-any-extended / year-month / year-only / year-season
                / decade / century / year-neg / dec-neg / cent-neg / year-p / year-e / year-s / week-basic / week-extended / time
                / datetimeE / group-datetime / time-under-period
```

The reader splits a text at the places the grammar makes structural before it reads any component: the suffix at the end, a leading `R` and its count, the `/` of an interval outside any braces and parentheses, the braces of a set. Within a piece the alternatives are tried in the order this page lists them, and a basic-format digit run is read by its length (2.2). Every production that reads a component accepts a mask (3.4), a set (3.9), a qualifier (3.3) and, in the explicit form, a group (3.8) or a selection (3.13) in that component's place, so those are not repeated in every rule above.

## 7. How the grammar is tested

* **Generated texts.** `test/support/grammar/` holds a generator for each production that produces texts the production matches, with unit values the validator accepts, and a property test asserts that `Tempo.from_iso8601/2` reads each one and `Tempo.to_iso8601/1` writes a text the reader reads to the same value.
* **Mutated texts.** A mutator takes a generated text and makes one change the grammar forbids (a separator dropped, a designator doubled, a suffix moved inside, a set left unclosed) and asserts a `Tempo.ParseError` that names the position.
* **The standards' examples.** Every example in ISO 8601-1 Annex A and in the clauses of ISO 8601-2 cited above, and every example of RFC 9557 §4, is a row of a table with the value it is read as or the reason it is refused; the conformance guide's "partial or divergent" list says which rows diverge and why.
