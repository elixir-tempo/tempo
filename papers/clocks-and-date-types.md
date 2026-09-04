# Machine Clocks and Date Types: A Short History

## Scope

This note summarises a discussion of two related questions: when computers first let a running program find out the time and the date, and when programming languages first gave the programmer a genuine *type* for holding those values. The two milestones are separated by roughly thirty years, and the gap is the interesting part of the story.

Several of the attributions below are contested or poorly documented. Where a claim rests on inference rather than a primary source, it is marked as such.

## Hardware: reading the clock

The conventional answer for the first programmer-readable clock is **Whirlwind I** at MIT, operational in April 1951. Whirlwind was built for real-time work — first flight simulation, then the Cape Cod air-defence experiment that became SAGE — and real-time work obliges the program itself to know when events occurred, in order to time-stamp radar returns and schedule responses against them. Whirlwind accordingly carried a crystal-driven counter that a program could read through an input instruction.

A qualification is owed here. What Whirlwind had was an elapsed-time counter with a settable origin, not a clock that inherently knew the hour; if the counter was initialised to wall-clock time at start-up, it served as a time-of-day clock in the ordinary sense. That distinction applies to nearly every machine built for the following two decades, however, so insisting on it would leave the question with no answer at all.

Earlier machines — ENIAC, EDSAC, the Manchester and Ferranti Mark 1 — ran as batch calculators and had no reason to expose time to the program at all. LEO I, also 1951, is occasionally advanced as a rival claim, but I have not been able to verify it.

## Hardware: reading the date

There is no comparably clean answer, because for a long time no machine had a date. The date was operational data: an operator typed it at start-up, or it was punched onto a card at the head of the job deck, and programs read it from there. IBM's System/360 of 1964 had an interval timer but nothing resembling a calendar.

The decisive move was to make the date *implicit* in a monotonic counter running from a fixed epoch, so that a program could derive the calendar date arithmetically without external help. That design belongs to **Multics**, not to IBM. Saltzer proposed it in October 1965, and the system programmers' manual of early 1966 specifies it: a hardware Calendar Clock reachable through a Memory Controller as a special register, holding a double-word integer incremented once per microsecond, set before system startup to the time elapsed since 0000 GMT on 1 January 1901. Software carried the value as a signed 71-bit integer in microseconds relative to that origin, and a companion section defined the conversion routines to and from year, month, day, hour, minute, second, zone and day of week.

The choice of 1901 over 1900 was deliberate: 1900 is a century year without a leap day, and starting a day later keeps conversion arithmetic simple. IBM chose 1 January 1900 for the System/370 Time-of-Century clock two or three years afterwards, which obliged every conversion routine on the 370 and its successors to carry a century-year adjustment and thereby exposed them to the 400-year rule. The common workaround was to add a day's worth of counts to the reading and convert as though the clock had started on "0 January 1900".

Note that none of these clocks survived a power cycle. The GE-645's crystal-in-an-oven unit was extremely expensive, as was the later 6180 clock in the SCU, and neither kept time while the system was off; the operator still set it, and Multics carried "gullibility checks" in software to screen out obviously wrong values.

## Where Unix sits

Unix time is downstream of Multics, not of IBM, and it arrives later than both. The First Edition Programmer's Manual of November 1971 defines time as a count of 60 Hz ticks since 1 January 1971 — a base date chosen recently precisely because 32 bits at that rate overflow in about two and a half years. The Third Edition manual moved the base forward to 1 January 1972 as a stopgap. One-second resolution, and with it the familiar 1970 epoch, appear with the Fourth Edition in 1973.

Two observations follow. First, the S/370 clock precedes Unix time by about a year in specification and the settled 1970 form by about three. Second, the comparison is not like for like: the S/370 clock is architecture, a hardware counter read directly by the program, whereas Unix time is a kernel variable maintained off a line-frequency interrupt on a PDP-11 that had no calendar hardware whatsoever. Bell Labs was a Multics partner before withdrawing, and Thompson and Ritchie carried the epoch-counter idea out with them.

## Languages: exposure without types

Every language discussed below let a program obtain the time and date long before any of them had a type for the result. The early facilities hand back a character string or a numeric field, and the meaning of those characters is entirely the programmer's affair.

**BCPL** (1967) and **B** (1969) could not have had such a type, because neither had types at all. BCPL is deliberately typeless: the only object is the machine word, and meaning comes from the operator applied to it rather than from the datum. B inherited that wholesale. A date in either language is a word — or on a 16-bit machine a pair of words — plus a convention the compiler cannot check, obtained by calling a library or system routine. **C** inherited the same posture: `time_t` is defined as an arithmetic type and `struct tm` is a plain record of integers, so adding two dates together is meaningless but perfectly legal. That assumption propagated through C's descendants for decades and is much of the reason genuine date types arrived so late in general-purpose programming.

**COBOL** is the earliest exposure of both time and date, by a wide margin. Date appears even in the Identification Division of the 1960 language, as `DATE-WRITTEN` and `DATE-COMPILED` — metadata about the source rather than runtime values, but indicative of the priorities. For runtime values, the special registers `CURRENT-DATE` and `TIME-OF-DAY` appear in the early 1960s; `ACCEPT ... FROM DATE`, `FROM DAY` and `FROM TIME` were standardised by the 1970s; `DAY-OF-WEEK` followed in COBOL-85; the intrinsic functions `CURRENT-DATE`, `INTEGER-OF-DATE` and `DATE-OF-INTEGER` came with the 1989 amendment; and the four-digit `DATE YYYYMMDD` phrase later still. The precise edition attributions here should be treated as approximate — see the note on sources below.

What COBOL never acquired is a date type. Every one of those facilities delivers an alphanumeric or numeric elementary item: `PIC 9(6)`, later `PIC X(21)`. The Year 2000 problem was in large part a consequence of exactly this. The language handed the programmer six characters and held no opinion about what they meant.

**PL/I** repeats the pattern a generation later. The `DATE` builtin returns `CHAR(6)` holding `YYMMDD`; `TIME` returns `CHAR(9)` holding `HHMMSSTTT`, which is millisecond resolution — notably better than COBOL offered — and still a character string. `DAYS` and `SECS` and their inverses arrived later to support arithmetic. IBM's Enterprise PL/I eventually added a `DATE` attribute that can be applied to a declaration with a pattern, which is a real typed date, but that belongs to the 1990s and after rather than to the 1964 language.

## Languages: types, in rough order

| Language | Year | What arrived |
| --- | --- | --- |
| Smalltalk-80 | 1980 | `Date` and `Time` as classes under `Magnitude`; comparable and subtractable first-class objects |
| Ada 83 | 1983 | Package `Calendar` with `Time` as a private type, alongside `Duration` in the language proper; the first internationally standardised general-purpose language with a genuine abstract time type |
| SQL | early 1980s | `DATE`, `TIME` and `TIMESTAMP` in DB2 and SQL/DS, standardised in SQL-92 with `INTERVAL`; almost certainly the date type most programmers met first |
| dBASE III | 1984 | A `D` field type with date arithmetic; the first date type many microcomputer programmers encountered |
| RPG IV | 1994 | `D`, `T` and `Z` types with duration arithmetic, retrofitted onto a language that had done dates in numeric fields for thirty years |
| Object Pascal / Delphi | 1995 | `TDateTime`, a type name over a float with an epoch |
| Java | 1996, then 2014 | `java.util.Date`, then `Calendar`, then the Joda-derived `java.time` |
| Elixir | 2016 | `Date`, `Time`, `NaiveDateTime` and `DateTime` over a pluggable `Calendar` behaviour |

The modern consensus is that the original question is malformed. A date and a time of day are not one type but a family — instant, civil date, civil time, zoned datetime, duration, period — and the languages that shipped a single `DateTime` mostly came to regret it. Elixir's split, introduced in 1.3, is one of the cleaner expressions of that conclusion; refusing to let a naive value masquerade as a zoned one is the entire point of the design.

## Sources

Multics Calendar Clock, primary sources:

- [MSPM section BD.10.01, *Supervisor Clock Services*, February 1966](https://people.csail.mit.edu/saltzer/Multics/Multics-Documents/MSPM/bd-10-01.660228.supervisor-clock-services.pdf) — specifies the hardware Calendar Clock, the microsecond increment and the 1901 epoch. [Mirror at web.mit.edu](https://web.mit.edu/~saltzer/www/publications/multics/bd-10-01.pdf).
- [MSPM section BD.10.02, *Clock Conversion Routines*, March 1966](https://people.csail.mit.edu/saltzer/Multics/Multics-Documents/MSPM/bd-10-02.660304.clock-conversion.pdf) — the conversion conventions and the 52-bit overflow date of October 2042.
- [Saltzer, *Proposal: A System of Clocks for Multics*, 27 October 1965](https://web.mit.edu/~saltzer/www/publications/multics/M0054.pdf) — the original design proposal.
- [Saltzer's later note on the epoch choice](https://multicians.org/jhs-clock.html) — why 1901 rather than 1900, and the consequences of IBM's contrary choice for the S/370.
- [Multicians, on clocks that did not survive power-off](https://multicians.org/multo-antes.html).

COBOL specification:

- [CODASYL, *Report to the Conference on Data Systems Languages*, April 1960](https://www.bitsavers.org/pdf/codasyl/COBOL_Report_Apr60.pdf), the COBOL-60 report, scanned at Bitsavers; [Internet Archive mirror](https://archive.org/details/bitsavers_codasylCOB_6843924).
- Caveat: this scan carries no OCR text layer, so I was not able to read it to confirm the register names and editions given above. COBOL-61 itself (*COBOL — 1961, Revised Specifications for a Common Business Oriented Language*) does not appear to be freely available; it is a Department of Defense publication that is nonetheless not in the public domain. Sammet's *The Early History of COBOL* in the HOPL proceedings is the standard secondary account and cites both documents.

Unix time:

- [TUHS discussion of the successive epochs and the Fourth Edition change](https://minnie.tuhs.org/mailman3/hyperkitty/list/tuhs@tuhs.org/thread/QV27DD3REJLE7HQCKUAZJJBF47Z3V3YH).
- [Schauma, *Time is an illusion, Unix time doubly so*](https://netmeister.org/blog/epoch.html) — reproduces the First Edition manual page defining the 1971 epoch.

Whirlwind:

- [Computer History Museum on Whirlwind](https://computerhistory.org/blog/the-whirlwind-computer-at-chm/).
- [Redmond and Smith, *Project Whirlwind: The History of a Computer Pioneer*](https://gunkies.org/wiki/Whirlwind) is the standard history; the MIT Dome repository holds the contemporary progress reports.
