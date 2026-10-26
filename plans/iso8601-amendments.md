# ISO 8601 amendments

**Status:** in progress, 2026-10-27

What the two amendments to ISO 8601 ask of Tempo: ISO 8601-1:2019/Amd 1:2022 (technical corrections) and ISO 8601-2:2019/Amd 1:2025 (canonical expressions, time scale components and date and time arithmetic). Their texts are in `standards/iso8601/`, under a single-user licence and not distributed, so this document cites clauses and paraphrases them. Each clause is set beside what Tempo does, probed on `fc86ca0` (2.0.0 as it stands, law 9). Every clause of both amendments is listed; none was skipped.

## Part 1, Amendment 1 (2022)

* **3.1.1.24 and 4.2.3 — leap seconds.** A positive leap second is written `23:59:60Z`; a negative one omits `23:59:59`, so the minute ends at `23:59:58`. This restates 2019's §4.3.10. Tempo refuses a second numbered 60 (`InvalidDateError`) by design: its clock has 60-second minutes, which Part 2's amendment calls a nominal duration rule (§14.6, below). Decision D6.

* **3.1.2.15 — a week as a length.** A note on the term. No change.

* **4.2.2 — the week year.** A note that a week-calendar year and a Gregorian year need not align. Tempo reads `2019-W01-1` as 31 December 2018. No change.

* **4.3.2 — years.** A year may be preceded by a minus sign for a year before year zero, and an expanded representation may have more than four digits. Tempo reads `-0001` and `-0001-03-01`, and six-digit signed years (`+002023`, `+123456`) and the explicit `Y12345`; it refuses five digits (`+12345`) and seven or more. Decision D5.

* **4.3.11 and 4.3.12 — decades and centuries.** Decades are numbered `000` to `999` and centuries `00` to `99`. Tempo reads them (`196` is `196J`, `19` is `19C`, `000` is `0J`). No change.

* **5.3.1.4 — fractions.** Adds a cross-reference to the leading-zeros rule. No change.

* **5.3.2 — the beginning and the ending of the day.** Restores `24:00:00` as the last instant of a day, in every reduced and fractional form whose parts below the hour are zeros (`T24`, `24`, `T24:00`, `24:00`, `T240000`, `T240000.000`). It is an instant, not a unit: not the last second of the day nor the first of the next. Used in an interval, for a duration or in arithmetic, it is read as the first instant of the next day, so `2022-04-19T00:00:00/2022-04-19T24:00:00` and `2022-04-18T24:00:00/2022-04-19T24:00:00` are both the 19th, whole. Tempo refuses hour 24 everywhere, except at the end of an interval with no date (`T22/T24` is read, two hours). Work and decision D1.

* **5.3.2, note 5 — expressions name the first instant of their unit.** An informative note, as typically true. Tempo reads a date end through (law 9, decision 85), as Part 2's own examples of grouped units do. No change.

* **5.5.1 — a time shift carried to the end.** A shift written on an interval's start applies to an end written without one; the amendment corrects 2019's example, which put a shift on a date. 2019 already said so (Part 1 §5.5.1, Part 2 §7.14.3). Tempo read the end as UTC: `2018-01-15T12:00+05:00/T13:00` was six hours. Fixed, 2026-10-27.

* **5.5.2.2 — durations.** The complete forms are restated as in 2019. No change.

## Part 2, Amendment 1 (2025)

* **3.1.2.14 to 3.1.2.18 — terms.** Canonical form, normalise, normalised duration, overflow (a component past the unit above it, `90M` beside hours) and underflow (a negative component the unit above can absorb, `-10M` beside `1H`). No change in themselves.

* **14.5 — overflow and underflow.** An expression may hold a component outside its range. Tempo's durations hold them as written (`PT1H90M`, `PT1H-10M`, `P-1Y9M-4DT15H30M-9S`). Its dates and times refuse them: `2018Y13M`, `2020Y2M59D`, `2019Y3M396D`, `2020Y367O`, `T26H` and `2016Y12M31DT60S` are each an `InvalidDateError`. Decision D2.

* **14.5 and Annex D — a negative day.** The amendment's examples read a negative component as underflow, but not consistently: §14.7.2 and D.4.6 example 1 take `2020Y4M-1D` to be 30 March, where D.3.3 example 3 takes `2024Y3M-300D` to be the 300th day before 1 March. Part 2's §4.4.1.4, which the amendment does not change, counts a negative day back from the end of the month: `2020Y4M-1D` is 30 April, and Tempo reads it so. Decision D3.

* **14.6 — conversion boundaries.** Century, decade, year and month convert into one another, and so do week, day, hour and minute. Year and week, year and day, month and day, and minute and second do not, without a date to decide them. A nominal duration rule may relax a boundary (a 60-second minute, a 30-day month, a 360-day year). Tempo's clock has 60-second minutes, a nominal duration rule not yet stated as one. `Tempo.Duration.compare/3` answers durations of the clock (`PT1H90M` is `PT2H30M`, `PT1M` is `PT60S`) and raises for any with a year or a month, `P7Y24M` against `P9Y` among them, which convert. How many months a calendar's year has is Calendrical's (`Calendrical.Info.months_in_year/1`: 12 for the Gregorian, `{:ambiguous, 12..13}` for the Hebrew), and the days of its week are the calendar's, so Calendrical has what this needs. Work and decision D4.

* **14.7 and D.5 — canonical form.** An expression is canonical with no overflow and as little underflow as the boundaries allow; D.5 resolves underflow by borrowing, then overflow by carrying. A value Tempo holds is in range, so canonical already. A duration has no canonical form in Tempo. Work and decision D4.

* **15.3 — expression templates.** A notation for the pattern of expressions two parties agree on (`[year]["-"][month]["-"][day]`). It describes forms; it adds none Tempo must read. Deferred: a template given to the reader or the writer is a feature to ask for.

* **D.3.1, D.3.3 and D.4.6 — carrying, borrowing, negative durations.** `Tempo.shift/3` carries and borrows: `2018Y12M` and `P1M` make `2019Y1M`; `2023Y12M` less `P15M` is `2022Y9M`; `2022Y2M2D` less `P1Y10M3D` is 30 March 2020; `2025Y59O` less `P20DT1H30M` is `2025Y38OT22H30M`; `T10H10M10S` less `PT5H30M20S` is `T4H39M50S`, where the amendment stops at `T4H40M-10S` (the same time, given 60-second minutes). No change.

* **D.3.2 — truncation.** The example is corrected to `2020Y367O` truncated to `2020Y366O`. Tempo clamps a day past a month's end in arithmetic, a truncation; it refuses `2020Y367O` as text (D2). No change.

* **D.4.2 — adding durations.** Durations add part by part, as `Tempo.Duration.add/2` and `subtract/2` do: `P1Y-10M3D` and `P2Y-5M` make `P3Y-15M3D`; `PT1H60S` less `PT122M` is `PT1H-122M60S`. No change.

## Errata in the amendments

Found while checking the examples against Tempo; for the user to report to ISO/TC 154.

* **Part 2, 14.6, examples 1 and 2** — a decade is written with `D` (`280D`, `33D`); Part 2's decade designator is `J`. Example 1 also names the pair as century and year.

* **Part 2, 14.7.3, example 4** — `90M` is said to be `1M30M`, for `1H30M`.

* **Part 2, D.4.2, example 3** — `P1Y10M3D − P2Y5MT10M` is given as `P3Y15M3DT-10M`, the sum's year and month; the difference is `P-1Y5M3DT-10M`.

* **Part 2, D.4.6, example 2** — the borrow drops the 30 minutes: the result is `2025Y38OT22H30M`, not `2025Y38OT22H`.

* **Part 2, negative days** — §14.7.2 and D.4.6 example 1 read a negative day one way, D.3.3 example 3 another, and §4.4.1.4 a third (above).

## Decisions

Taken by the user on 2026-10-27 (decision 86 in `plans/decisions.md`).

* **D1 — 24:00.** At either end of an interval, 24:00 with zeros below the hour is the next day's first instant, the amendment's reading: `2026-06-15T09/2026-06-15T24` is nine to midnight. Written alone (`2026-06-15T24:00`) it is an instant, not a unit Tempo can hold, and a named error that says to write it as an interval's end. Such an interval is written back with the next day's `T00` (`2026Y6M15DT9H/16DT0H`), which the amendment's example 12 lists as the same interval; no mark is kept on the struct.

* **D2 — out-of-range parts in a value.** Refused by default, as now: a typo stays an error. `Tempo.from_iso8601/2` takes `overflow: :carry` to read them as the amendment does, `2018Y13M` as January 2019 and `2020Y2M59D` as 30 March 2020.

* **D3 — a negative day.** Counted back from the month's end, as §4.4.1.4 has it and Tempo does. No change; the amendment's examples are on the errata list.

* **D4 — canonical durations.** A canonical form on `Tempo.Duration` by D.5, years and months converting by the calendar's count (Calendrical), weeks, days, hours and minutes by their fixed counts, and a minute 60 seconds, as Tempo's clock has it: `PT1H-10M` is `PT50M`, `P7Y24M` is `P9Y`, `PT59M120S` is `PT1H1M`. `compare/3` answers through it, so `P7Y24M` equals `P9Y`, and `PT1M` still equals `PT60S`.

* **D5 — expanded years.** A sign and five or more digits is an expanded year: `+12345-06-15` reads. Six read as now.

* **D6 — the leap second.** `23:59:60` stays an `InvalidDateError`. The conformance guide states the 60-second minute as Tempo's nominal duration rule (§14.6, example 15) and points to `Tempo.LeapSeconds`.

## Tasks

* [ ] **Expanded years** — a sign and five or more digits (D5).

* [ ] **The conformance guide** — cite both amendments; state the 60-second minute as Tempo's nominal duration rule (D6); the negative day (D3), overflow (D2) and expanded years (D5) as decided.

### Done

* [x] **Canonical durations** — `Tempo.Duration.canonical/2` (and `canonical!/2`): two chains, years and months by `Tempo.Calendar.months_in_year_bounds/1` where they agree, weeks to fractions of a second by `days_in_week/1` and a 60-second minute; a positive chain written from its top (so `P10D` is `P1W3D`, as the amendment's overflow has it), a negative one from its coarsest unit written. `compare/3` without `:relative_to` counts months and the rest apart and orders them where they agree. 2026-10-27.

* [x] **Out-of-range parts by option** — `Tempo.from_iso8601/2` with `overflow: :carry` (`Shift.carried/1`): each value's parts are offsets from their least, added by `Shift.shift/2`, in the form written; a negative day is not carried (D3), a time with no date has no day to carry into. Found beside it and fixed: a day of zero raised a `FunctionClauseError` in `Validate`. 2026-10-27.

* [x] **24:00 as the end of a day** — on a date, at either end of an interval, the next day's first unit at the resolution written, placed where the day's extent ends (`Spans.next_day_from_end_of_day/1`); alone, an `InvalidDateError` with `:end_of_day`; on the day's cycle unchanged (`T22/T24`). 2026-10-27.

* [x] **A time shift carried to the end** — an end with no shift takes its start's where there is no zone, in the reader and `Tempo.Interval.new/1`; a floating start before a shifted end is a `Tempo.FrameError`. 2026-10-27.
