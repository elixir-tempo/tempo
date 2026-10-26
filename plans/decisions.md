# Decisions of the redesign

The questions put to the user while Tempo 2.0 was built, each with its context, the options and the answer given. It is the record the release documentation is written from: `TODO.md` tracks what is left to build, and this file says why a thing is as it is. A decision is added here when it is made, with its number, and is never rewritten; one that is later changed gets a new entry that names the one it replaces.

Each entry has the same parts: the question, the context it arose in (with what the code did at the time), the options, the decision and its date, and its state (built, or to build).

`guides/design-decisions.md` is the published form, for users of the library and for anyone designing one: the decisions grouped by subject, each with its question, its alternatives, the choice and the reasons, and examples the guide tests run. A decision added here that bears on what Tempo does is added there too.

## 1. The golden comparison with 1.6

* **Question.** Does the suite that compared every answer with the published 1.6 stay?

* **Context.** The comparison recorded 1.6's answer to each cell of a corpus and classified every difference. By phase 8 every difference was classified and the comparison held nothing new.

* **Decision (2026-10-13).** "Retire it, keep only the corpus." The corpus feeds the totality check (every function on every shape answers or returns a named error).

* **State.** Built: `test/support/matrix/cells.ex`.

## 2. The version

* **Question.** Is the redesign 2.0 or 3.0?

* **Context.** The plan was written as "3.0" because a 2.0 had been developed; it was never published.

* **Decision (2026-10-13).** "Version it 2.0.0 (thats never been released)". The plan's text says 3.0 and means 2.0.

* **State.** Built.

## 3. The oldest OTP

* **Question.** Is OTP 26 supported?

* **Decision (2026-10-13).** "No OTP 26. Only OTP 27 and later."

* **State.** Built: a guard in `mix.exs`.

## 4. The engine modules

* **Question.** Are `Tempo.Unit`, `Tempo.Scale`, `Tempo.Zone`, `Tempo.Limit` and the other modules under `lib/tempo/core/` public?

* **Decision (2026-10-13).** "Engine is not part of the API." They are `@moduledoc false`, and the types a caller sees live in `Tempo`.

* **State.** Built.

## 5. Functions of 1.6 left unbuilt

* **Question.** Are `merge/2`, `from_date_range/2`, `season/1` and `Tempo.Interval.through/1` rebuilt?

* **Decision (2026-10-13).** They stay unbuilt.

* **State.** Nothing to build.

## 6. One calendar behaviour

* **Question.** Who owns the contract a calendar meets, and how is `Calendar.ISO` treated, which has none of Calendrical's callbacks?

* **Context.** Tempo asks every calendar question through one hidden module, `Tempo.Calendar`. `Calendar.ISO` is answered for by `Localize.Calendar.ISO`. Three options were put: keep a private adapter, have Calendrical publish a second and smaller behaviour, or swap `Calendar.ISO` for a conforming module at the boundary.

* **Decision (2026-10-13).** "One behaviour, defined by Calendrical, that all calendars conform to, including Localize.Calendar.ISO (although the last one not by `@impl`)." Calendrical depends on Localize, so Localize cannot name the behaviour. The behaviour is primarily, but not only, in support of Tempo, and Calendrical complies fully with both `Calendar` and its own behaviour. The function that says which module answers for `Calendar.ISO` stays in Tempo, since Calendrical is to be optional for Tempo.

* **State.** Built. Calendrical holds `Localize.Calendar.ISO` to every required callback and to its laws test. `leap_month/1`, `weeks_in_month/2` and `month_week/3` left the behaviour on 2026-10-14: nothing called them and another callback answers each.

## 7. A solar term of a value with no calendar

* **Question.** Which calendar reckons a solar term (`qingming`) for a value in the default calendar?

* **Context.** `Localize.Calendar.ISO.solar_term/2` answers `{:error, :undefined}`, as Localize has no astronomy, so the one behaviour does not answer this for `Calendar.ISO`. The options: (1) the adapter asks `Calendrical.Gregorian`, which reckons the terms at the traditional reference, the Chinese calendar's meridian; (2) such a term is an error unless a calendar is written; (3) another module with astronomy answers for `Calendar.ISO`.

* **Decision (2026-10-14).** Option 1.

* **State.** Built: one clause of `Tempo.Calendar.solar_term/3`.

## 8. The calendar adapter stays as it is

* **Question.** Is what the adapter still knows (the `Calendar.ISO` table, the Gregorian for a solar term, Easter, the registry lookup by name) removed now?

* **Decision (2026-10-14).** "If all calendar access is guaranteed ONLY to go through the adapter, we can leave it that way for now and revisit the adapter at a later time."

* **State.** Built: `test/tempo/calendar_surface_test.exs` fails if a library module other than the adapter names a module that answers for a calendar. Beside the guarantee, not under it: Elixir's own date structs call the calendar of the value they are built in, the zone code uses Erlang's `:calendar` for Gregorian seconds, and `Tempo.Workdays` reads a territory's weekdays from Localize.

## 9. Set operations with an operand that has no end

* **Question.** What does `union`, `intersection` or `difference` answer when one operand has no end?

* **Context.** Two cases differed. A recurrence with no end took its other operand as its window, silently. A set read from a stream was refused (`:too_many_values`). The options: refuse both without `:within`, window both by the other operand, or leave them different.

* **Decision (2026-10-14).** Window by the other operand, and where that would be wrong answer with an endless set: "a `union` would return an infinite recurrence - but thats not really different to the recurrence with no end as the first operand." Agreed in full as: the result is as bounded as the mathematics makes it. With A endless and B bounded, `intersection` in either order and `difference(B, A)` lie inside B, so A is windowed by B, which is exact. `union` in either order and `difference(A, B)` are endless sets, in time order, bounded by `:within`; windowing `difference(A, B)` by B would drop all of A after B ends. Of two endless operands, `union` and `difference` are endless sets, and `intersection` is refused without `:within`, since two that never meet (every Monday and every Tuesday) are searched for ever. A recurrence with no end and a set read from a stream follow the one rule.

* **State.** Built, with the two corrections of decision 21: `Tempo.Algebra.streamed/4`, `swept/3` and `merged/2`, `test/tempo/endless_operands_test.exs`.

## 10. The order of a selection by a list of selectors

* **Question.** In what order does `Tempo.select/3` answer when its selector is a list?

* **Context.** A list of selectors answered in the list's order with repeats kept: `Tempo.select(~o"2026-06/2026-07", [~o"20D", ~o"5D"])` was the 20th of June, the 20th of July, the 5th of June, the 5th of July. A list of integers was sorted, with repeats kept: `[20, 5, 5]` was the 5th, the 5th, the 20th. The result is an `:all` set, which everywhere else is in time order. The options: (1) time order, repeats removed; (2) time order, repeats kept; (3) the list's order, documented.

* **Decision (2026-10-14).** Option 1, for a list of selectors and a list of integers alike.

* **State.** Built: `Tempo.Select`, `test/tempo/select_test.exs`.

## 11. A cron expression with no start

* **Question.** What start does `Tempo.Cron.parse/2` give a rule when the caller gives no `:from`?

* **Context.** A cron expression has no start of its own. Tempo invented one, the first minute of 2000: `Tempo.Cron.parse("0 9 * * 1")` was `~o"R/2000Y1M1DT0H0M/P1M/FL1KT9H0MN"`, and `Enum.take/2` of it began at Monday 3 January 2000. An RRULE with no start is read with none: `Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=MO;BYHOUR=9")` is `~o"R/../P1W/FL1KT9HN"`, refused as unbounded until `:within` or a start is given. With `within: ~o"2026-06"` the two gave the same five Mondays. The options: (1) an open start, as an RRULE; (2) keep 2000; (3) start at the present, which makes the reading depend on the clock.

* **Decision (2026-10-14).** Option 1: a cron rule with no `:from` has no start, and needs `:from` or `:within` before it has occurrences.

* **State.** Built: `Tempo.Cron`, `test/tempo/cron_test.exs`.

## 12. `Tempo.to_elixir/1` of an interval of dates

* **Question.** Does `Tempo.to_elixir/1` give a `Date.Range` for an interval?

* **Context.** `Tempo.from_elixir/2` read a `Date.Range`, and `Tempo.to_elixir/1` could not give one back: `Tempo.from_elixir(Date.range(~D[2026-06-15], ~D[2026-06-20]))` was `~o"2026Y6M15D/20D"`, and `Tempo.to_elixir/1` of that was a `Tempo.ConversionError` (`:not_an_elixir_value`). A `Date.Range` holds both its ends, as Tempo reads an end written to a date (law 9), so the two are the same six days. The options: (1) a `Date.Range` for an interval whose two ends are dates, and an error for everything else; (2) a `Date.Range` for a coarser value or interval too (`~o"2026-06"` as 1 to 30 June), which reads back as a span of days, another expression; (3) leave it an error.

* **Decision (2026-10-14).** Option 1. A month, a year, an interval of them, an interval of clock times and a stepped `Date.Range` stay errors.

* **State.** Built: `Tempo.Interop`, `test/tempo/interop_test.exs`.

## 13. RFC 7529's `RSCALE` and `SKIP`, and a week that does not start on Monday

* **Question.** Does 2.0 read an RRULE (and a JSCalendar rule) with `RSCALE`, with `SKIP`, and with a `WKST` other than `MO` where it changes the weeks counted?

* **Context.** The published 1.6 read all three and 2.0 refused them: `FREQ=YEARLY;RSCALE=CHINESE;BYMONTH=1;BYMONTHDAY=1` ("RSCALE (RFC 7529) is not supported"), `FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;RSCALE=GREGORIAN` ("SKIP (RFC 7529) is not supported"), `FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,SU;WKST=SU` ("a WKST other than MO is not supported"). A `WKST` that changes nothing was read (`FREQ=WEEKLY;BYDAY=TU,SU;WKST=SU`); it is significant in a weekly rule with `INTERVAL` above 1 and a yearly rule with `BYWEEKNO`, which three of RFC 5545's own examples are. `RSCALE` names the calendar a rule counts in, which fits the one-calendar rule when the whole recurrence is in that calendar. `SKIP` says what becomes of a day a month lacks: Tempo omits it, RFC 5545's rule, and `BACKWARD` and `FORWARD` need a new part of a rule. A significant `WKST` needs weeks counted from another day than the expression's calendar counts them, for which there was no form. The options: (1) keep refusing all three; (2) read `RSCALE` as the recurrence's calendar and keep refusing the other two; (3) build all three.

* **Decision (2026-10-14).** Option 3: build all three.

* **State.** Built: `WKST` by decision 27, `RSCALE` and `SKIP` by decisions 28 and 29. RFC 5545's three examples that name a week start, and the four of RFC 7529, are read and held to the standards' lists.

## 14. Where a week start lives

* **Question.** RFC 5545's `WKST=SU` asks for weeks counted from Sunday; where does a week start live, when an expression's weeks are its calendar's and an expression has one calendar?

* **Context.** BCP 47 has a key for the first day of the week, `fw`, and the reader already carried it as a suffix tag that changed nothing: `Tempo.from_iso8601("R/2026-06-15/P2W[u-fw=sun]")` was `~o"R/2026Y6M15D/P2W[u-fw=sun]"`, the tag kept in the metadata. The options: (1) a property of the whole expression, written `[u-fw=sun]` once at its end, as the calendar and the zone are; (2) a part of the rule alone, which ISO 8601 has no way to write; (3) a calendar of Sunday weeks, a second calendar module with no IXDTF name.

* **Decision (2026-10-14).** Option 1. The week start is of the whole expression: its weekly cadence, its week numbers and its days of the week. `WKST` reads to it and is written from it. It follows that `2026-W25[u-fw=sun]` is a week that begins on Sunday with its days counted from Sunday, where the text was read as the Monday week with a tag.

* **State.** Built, as decision 27 records: `Tempo.to_week_start/2`, `Tempo.week_start/1`, `test/tempo/week_start_test.exs`.

* **Superseded in part (2026-10-16).** A day of the week on its own is counted from the week's first day too, by decision 80; `2026-06-21[u-fw=sun]` is day 1.

## 15. How `tempo_network` asks a calendar

* **Question.** May the companion package `tempo_network` call Tempo's hidden calendar adapter?

* **Context.** `tempo_network` calls `Tempo.Calendar`, which is `@moduledoc false`, for six questions in one file (`Tempo.Network.Calendar`): the months a year can have, a date's day number and the date of a day number, the days in a week, the years in the calendar's cycle, and the first day of a year. The options: (1) an agreed private seam, the companions of Tempo may call the adapter and other code may not; (2) a small public module in Tempo with the six questions, which fixes part of the adapter's shape before it is revisited (decision 8); (3) the companion calls the calendar's behaviour itself, with its own copy of the `Calendar.ISO` lookup.

* **Decision (2026-10-14).** Option 1: "tempo_network is our work, its ok - at least for now."

* **State.** Nothing to build. A change to `Tempo.Calendar` checks the companions.

## 16. Cron's `28W` to `31W`: a part of a rule that rolls a day to a weekday

* **Question.** Are cron's `28W` to `31W` read, and how?

* **Context.** Cron's `nW` is the weekday nearest day n of the month, without leaving the month. `1W` to `27W` and `LW` were read, `15W` as three rules (the 15th when it is a weekday, the 14th when that is a Friday, the 16th when that is a Monday): `Tempo.Cron.parse("0 9 15W * *", from: ~o"2026-01-01")` was `~o"{R/2026Y1M1D/P1M/FL15D{1,2,3,4,5}KT9H0MN,R/2026Y1M1D/P1M/FL14D5KT9H0MN,R/2026Y1M1D/P1M/FL16D1KT9H0MN}"`. From the 28th the three rules fail: a 30th that is a Sunday rolls to Monday the 31st in a long month and to Friday the 28th in a month of thirty days, and a rule's parts could not say "by the month's length", so `31W` was an error. The options: (1) keep refusing them in 2.0; (2) a part of a rule that rolls a day to the nearest weekday within its month, by which every `nW` is one rule, and which also serves a holiday observed on the nearest weekday (`tempo_holidays`); (3) rules by the length of the month, with a condition for a leap year's February.

* **Decision (2026-10-14).** Option 2, against the recommendation to leave it until after 2.0.

* **State.** Built: `{:roll, convention}` in a rule's parts, applied by `Tempo.Select`; cron's `nW` is `[day: n, roll: :modified_nearest]` and `LW` is `[day: -1, roll: :preceding]`. `test/tempo/roll_test.exs`, `test/tempo/cron_test.exs`.

## 17. How a roll is written

* **Question.** How is the part of a rule that rolls a day to a weekday (decision 16) written as text?

* **Context.** ISO 8601 has no form for it, and a rule that cannot be written is an error of `Tempo.to_iso8601/1`. Tempo had two precedents: the computed-event part inside a selection, a name in parentheses and a letter (`~o"R/../P1Y/FL(easter)eN"`), and a suffix on the whole expression, where RFC 9557 keeps a key that begins with an underscore for experiments (`[_foo=bar]`). The vocabulary existed: `Tempo.roll_to_workday/3` takes `:following`, `:preceding`, `:modified_following` and `:modified_preceding`, the modified ones turning back at the end of the month, and there is `Tempo.nearest_workday/2`. The options: (1) a named part inside the selection, shaped as the event part is, beside the day it rolls: `L31D(modified-nearest)rN`; (2) a suffix on the whole expression, `[_roll=modified-nearest]`, which rolls every day the expression selects and which other readers pass over; (3) no written form, and an error from the writer.

* **Decision (2026-10-14).** Option 1. The letter proposed is `r`; that it is free in the selection grammar is to be checked when it is built.

* **Put with the question, not ruled on.** What a weekday is: Monday to Friday unless the expression names a territory, and that territory's workdays when it does. It was offered as the default and not objected to; it is confirmed or changed when the part is built.

* **State.** Built: `(convention)r`, the letter `r` being free; the conventions are `following`, `preceding`, `nearest` and the three `modified-` forms.

## 18. What a weekday is, for a roll

* **Question.** Which days are the weekdays a roll (decisions 16 and 17) moves a day to?

* **Context.** Put with decision 17 and left open there: the default offered was Monday to Friday unless the expression names a territory. Cron's own `W` means Monday to Friday; a holiday is observed by the working week of where it is kept. `Tempo.workdays/2` and `Tempo.roll_to_workday/3` take a territory, and `Tempo.Territory.resolve/1` is the chain from an option to the application's default and the current locale.

* **Decision (2026-10-14).** "Weekdays are always locale dependent. Use the locale option if one is provided or the current locale (Localize.get_locale/0) if one is not." There is no fixed Monday to Friday: the offer of decision 17 is not taken.

* **What follows.** A rule with a roll has the days of the locale it is asked in, so the functions that give a rule its occurrences take `:locale`, and the same rule answers with other days under a locale whose working week differs (Sunday to Thursday, for one). Cron's `nW` read by Tempo rolls to the locale's weekdays, not to Monday to Friday always.

* **State.** Built: `:locale` on `Tempo.to_interval/2`, `Tempo.members/2` and `Tempo.select/3`, and the territory in force where none is given. See decision 23 for what "in force" is.

## 19. Seasons in the new engine

* **Question.** Do the decisions on seasons of 8 and 9 October 2026 (`plans/seasons-by-locale.md`) hold in 2.0?

* **Context.** Those decisions were built in the unreleased 2.0 and not carried into the rewrite, where a season was read and written and nothing more: `Tempo.to_interval(~o"2026-21")` and `Tempo.to_interval(~o"2026-25")` were a `Tempo.ConversionError` (`:season`), and `:territory` was no option of `Tempo.to_interval/2` or `Tempo.from_iso8601/2`. `TODO.md` said, wrongly, that a season waited on Calendrical. The October decisions: codes 21 to 24 are meteorological, whole months, abstract until a locale or a territory is given (an option of the reader and of `Tempo.to_interval/2`, or the application's default and the current locale), with the hemisphere asked of Localize; codes 25 to 32 are astronomical, from an equinox or a solstice to the next as Astro computes them, and name their hemisphere; a season with no territory to be had is a named error. The options: (1) rebuild those decisions as they stand; (2) rebuild the astronomical codes alone; (3) leave seasons read and written only.

* **Decision (2026-10-14).** Option 1.

* **Put with the question, not ruled on.** The months of a meteorological season (March to May in the north) are a convention and not a computation, so they are held in Tempo with the hemisphere asked of Localize, as in October, and are not Calendrical's to answer.

* **State.** Built, with what decision 22 records: `Tempo.Season`, `Tempo.in_territory/2`, `test/tempo/season_test.exs` and `season_in_force_test.exs`.

## 20. Where the months of a meteorological season are held

* **Question.** Are the months of a meteorological season (March to May in the north) held in Tempo, or are they Calendrical's to answer?

* **Context.** Put with decision 19 and left open there. The months are a convention and not a computation; in October they were held in Tempo, with the hemisphere asked of Localize.

* **Decision (2026-10-14).** "meteorological season months in Tempo is ok for now". Held in Tempo, and open to being moved later.

* **State.** Built: the months are in `Tempo.Season`.

## 21. Two corrections to decision 9, found in building it

* **Question.** None was put: these are two things the building of decision 9 showed, recorded so that the release documents say what is built and not what was first agreed.

* **Of two operands with no end, only the union is answered.** Decision 9 said a `difference` of two such operands is an endless set, on the reasoning that each next member takes finite work. That was wrong: where one operand covers the other from some day on (every week as whole weeks, less every second day as two days), no result is ever come to and the search does not end. The same holds for a symmetric difference. So `intersection`, `difference` and `symmetric_difference` of two operands with no end are a `Tempo.ConversionError` (`:unbounded`) without `:within`, and `union` alone is an endless set.

* **A result with no end keeps apart what abuts.** A sweep of operands that have an end joins two results that meet into one span. An endless recurrence whose occurrences abut (every week, as whole weeks) less a bounded span would be one span that never closes, so the sweep that answers one result at a time ends a result where the members covering it end, and begins another where the next member begins. The time covered is the same; the spans are the operand's members, less what was taken out. With `:within` given to the operation the whole sweep is used and results that meet are joined as before.

* **Also found.** `Tempo.symmetric_difference/3` follows the rule of `union/3` (an endless set with one operand with no end), which decision 9 did not name. A predicate with an operand with no end (`Tempo.within?/2` and its kin) still takes that operand within the other, which answers wrongly in one case at least: every Monday for ever is "within" June. It is in `TODO.md` as a defect and was not changed.

* **Decision.** Mine, in building (2026-10-14); for the user to overrule.

* **State.** Built.

## 22. What the building of seasons settled, and one question it leaves

* **Question.** None was put for the first four: they are where the new engine answers otherwise than the October design, recorded for the release documents. The fifth is open.

* **A season of a hemisphere is kept as it is written.** In October a season of 25 to 32 was read into its dates (`2026-25` was `2026Y3M20D/6M21D`). Law 3 keeps what is written, so `~o"2026-25"` is `2026Y25M` and has its days where they are asked for: 20 March to 20 June 2026, the day of the March equinox to the day before the June solstice, in UTC.

* **A season is walked.** In October a walk of a season was an error. The engine walks any span it has an extent for, so a season yields its days, and an interval of meteorological seasons its months.

* **A season has a length.** A meteorological season is counted in months (`P3M`) and an astronomical one in days (`P93D`), there being no unit of one season.

* **Errors are `Tempo.ConversionError`.** October's `Tempo.AbstractSeasonError` is not rebuilt: a territory on no one side of the equator is the reason `{:no_hemisphere, territory}`, a move by other than whole years `{:season_moved, duration}`, and a season in a calendar that is not the Gregorian `:season`.

* **Open: the order of two seasons of 21 to 24 as they are read.** October said an interval of seasons "is read whatever the order of its seasons", since autumn comes before spring south of the equator, and is held to its order where it is given a hemisphere. EDTF's corpus, which the reader is held to, refuses `2012-24/2012-21`. The reader keeps EDTF's order (spring, summer, autumn, winter), so `2026-23/2026-21`, March to November in Australia, is not read; `Tempo.Interval.new/1` of the two months is the way to it. To decide: conformance with the corpus, or October's reading.

* **Decision.** Mine, in building (2026-10-14); for the user to overrule.

* **State.** Built, the fifth as described.

## 23. What the building of the roll settled

* **Question.** None was put: these are where the building of decisions 16 to 18 chose, recorded for the release documents and for the user to overrule.

* **Six conventions.** A roll is one of the four `Tempo.roll_to_workday/3` had (`following`, `preceding`, `modified-following`, `modified-preceding`) and two new to it and to that function: `nearest`, the closer weekday and the one after on a tie, and `modified-nearest`, the closer weekday of the day's own month, which is cron's `W`.

* **Where no locale is given.** Decision 18 said the current locale (`Localize.get_locale/0`). What is asked is `Tempo.Territory.resolve/1`, the chain every other territory question in Tempo asks: the application's `:default_territory` where it is set, and the current locale's territory otherwise. So a configured default territory comes before the current locale.

* **Which functions take `:locale`.** `Tempo.to_interval/2`, `Tempo.members/2` and `Tempo.select/3`. Enumeration (`Enum`), `Tempo.walk/3` and the set operations take no options of the kind and ask the territory in force.

* **A day rolled out of its period is kept.** The first of February 2026, a Sunday, rolled by `preceding` is Friday 30 January: it is an occurrence of February's repeat, and lies in January. `modified-` conventions never leave the month.

* **A day a month lacks has no weekday near it.** `31W` in June fires on no day, as `31` does not.

* **Two days that roll to one are that day once**, and a position (`instance`) counts the days as they are rolled.

* **A rule with a roll has no RRULE**: `Tempo.RRule.to_string/1` is an error for one, RFC 5545 having no part for it.

* **`LW` changed its form.** It was "the last of Monday to Friday" and is "the last day, rolled back to a weekday", so that it keeps to the locale's working week as `nW` does.

* **Found, for decisions 13 and 14.** A selection already has a week start as a part, `nq` (`1q` is Monday), which the reader reads and the validator refuses unless it is Monday. Decision 14 put the week start on the whole expression as `[u-fw=sun]`; whether `nq` stays beside it, as what a rule of its own says, is to be settled when 13 and 14 are built.

* **Decision.** Mine, in building (2026-10-14); for the user to overrule.

* **State.** Built.

## 24. One notation for a week start

* **Question.** A selection already had a week start as a part, `nq` (`1q` Monday, `7q` Sunday), read and then refused unless it was Monday. Decision 14 put the week start on the whole expression as `[u-fw=sun]`. Do both stay?

* **Context.** The options: (1) keep only `[u-fw=sun]` and remove `nq`, so there is one way to say it and RFC 5545's `WKST` reads to the suffix; (2) keep both, the suffix for the expression and `nq` for one rule's own counting, where a rule could then disagree with its expression; (3) use `nq` and drop the suffix, closest to RFC 5545 and against decision 14, and a week number outside a rule could have no Sunday start.

* **Decision (2026-10-14).** Option 1.

* **State.** Built: `nq` is no longer read or written.

## 25. The order of two seasons of 21 to 24 in an interval

* **Question.** Is an interval of two seasons of 21 to 24 held to the order of their numbers as it is read? It is the question decision 22 left open.

* **Context.** Autumn (March to May) comes before spring (September to November) south of the equator, so `2026-23/2026-21` is March to November in Australia and runs backwards in Britain. The October design read such an interval "whatever the order of its seasons" and held it to its order once it had a hemisphere. EDTF's corpus, which the reader is held to, lists `2012-24/2012-21` and `2012-23/2012-22` as invalid. As built with decision 19, the reader kept the numbers' order: `Tempo.from_iso8601("2026-23/2026-21")` was a `Tempo.IntervalEndpointsError`, and so was `Tempo.in_territory(~o"2026-21/2026-23", :AU)`, rightly, spring to autumn of one year running backwards there. The options: (1) keep EDTF's order, a southern interval being written as months; (2) October's reading, any order read and the order held to only with a territory, two corpus cases becoming recorded departures; (3) any order read only where a territory is named as the text is read, the bare text staying an error.

* **Decision (2026-10-14).** Option 3.

* **State.** Built: with `:territory` or `:locale`, `Tempo.from_iso8601/2` and `Tempo.parse/2` give each season its months before the order of the ends is held to. `Tempo.from_iso8601("2026-23/2026-21", territory: :AU)` is `~o"2026Y3M/11M"`; the same text with no territory, and the `~o` sigil, which has none, are errors as in EDTF. `test/tempo/season_test.exs`.

## 26. A predicate with an operand that has no end

* **Question.** What do `within?/2`, `contains?/2`, `overlaps?/2`, `disjoint?/2`, `equal?/2`, `before?/2`, `after?/2` and `adjacent?/2` answer when an operand has no end?

* **Context.** The predicates did what the set operations did before decision 9: they took the operand with no end within the other operand's extent and compared what was left. That was sometimes right and sometimes wrong: `Tempo.within?(~o"R/2026-06-01/P1W/FL1KN", ~o"2026-06")`, every Monday for ever within June, was `true`. With E the operand with no end and B the one with an end, every case has an answer that needs no search: `within?(E, B)`, `contains?(B, E)`, `equal?`, `before?(E, B)` and `after?(B, E)` are false, what has no end not fitting in what has one; `overlaps?`, `disjoint?`, `within?(B, E)` and `contains?(E, B)` are decided within B's extent, where taking E there is exact; `after?(E, B)`, `before?(B, E)` and `adjacent?` are decided by where E begins. The options: (1) answer by that table, and refuse two operands with no end without `:within`; (2) refuse any predicate with such an operand without `:within`; (3) leave it and say so.

* **Decision (2026-10-14).** Option 1.

* **State.** Built: `Tempo.Algebra.decided/4`, `test/tempo/endless_operands_test.exs`. Two operands with no end raise a `Tempo.ConversionError` (`:unbounded`) without a window.

## 27. How a week start is held, and what building it settled

* **Question.** None was put: this is how decisions 14 and 24 were built, recorded for the release documents and for the user to overrule.

* **A week start is held as the expression's calendar.** An expression written `[u-fw=sun]` is in the Gregorian calendar whose weeks begin on Sunday: a calendar of the same dates that Calendrical builds from the day (`use Calendrical.Base.Month, day_of_week: 7, min_days_in_first_week: 4`), one for each day but Monday, under `Tempo.Calendar.WeeksFrom`. The struct has no new field, the engine asks its calendar as it always does, and law 5 (one expression, one calendar) is what makes the week start the whole expression's. Decision 14 turned down "a calendar of Sunday weeks" as a way to write it, having no name; with `[u-fw=sun]` as its name it is how it is held. The module shows where a value's calendar is inspected as a struct, and nowhere in its text.

* **The Gregorian calendar only.** `[u-fw=sun]` beside `[u-ca=hebrew]` is an error that says so, as is `Tempo.to_week_start/2` of a Hebrew value: another calendar has its own weeks. `[u-fw=mon]` is the calendar as it is, and is not written back.

* **Week 1 is the first week with four days of the year in it**, ISO 8601's rule from another first day, and the weeks RFC 5545 counts for a `WKST`: where weeks begin on Sunday, week 1 of 2026 is 4 to 10 January and week 25 is 21 to 27 June.

* **A day of a numbered week is counted from the day the week begins on**, as decision 14 said: `2026-W25-1[u-fw=sun]` is Sunday 21 June. A weekday on its own is not moved: `1K` in a rule is Monday, and `Tempo.day_of_week/1` is 1 for a Monday, whatever the week start. Building this found that the engine wrote the weekday where it meant the day of the week counted from its first day (the two agree where weeks begin on Monday); it now writes the latter, and `Tempo.day_of_week/1` asks the day itself.

* **Two expressions of different week starts** relate and combine by their days, the second brought to the calendar of the first as two calendars are: a week of one start is the span of its days in the other.

* **`WKST` is kept only where it counts.** RFC 5545 says the day is significant in a weekly rule of every second week or more that names weekdays and a yearly rule that names weeks of the year; there the recurrence is in the weeks of that day, and `Tempo.RRule.to_string/1` writes `WKST` back. Elsewhere it is read and not kept, as before. Under `BYWEEKNO`, `BYDAY=MO` with `WKST=SU` is read as the second day of the week, and written back as `MO`.

* **JSCalendar's `firstDayOfWeek`** is read the same way.

* **Decision.** Mine, in building (2026-10-14); for the user to overrule.

* **State.** Built.

## 28. How `SKIP` is written, and what `RSCALE` gives back

* **Question.** Two things the building of decision 13 has to settle: how RFC 7529's `SKIP` is written in ISO 8601 form, which has no notation for it, and what a rule with `RSCALE` gives as its occurrences.

* **Context.** Put before building, with what was intended. By analogy with the roll of decision 17, `SKIP` is a named part inside the selection with a letter of its own: `(backward)s` and `(forward)s`, beside the day or the month it applies to; `SKIP=OMIT`, the default and RFC 5545's rule, is no part. A recurrence with `RSCALE` is in the calendar named, so its occurrences are values of that calendar (`[u-ca=hebrew]`) and not Gregorian dates, and a caller converts them with `Tempo.to_calendar/2`.

* **Decision (2026-10-14).** "Agreed."

* **State.** Built, as decision 29 records.

## 29. What the building of `RSCALE` and `SKIP` settled

* **Question.** None was put: these are where the building of decisions 13 and 28 chose, and what it found, recorded for the release documents and for the user to overrule.

* **The four examples of RFC 7529 section 4.3 are the test.** Chinese New Year, the Ethiopic thirteenth month, a Hebrew anniversary that starts in a leap month, and a Gregorian leap day with a skip: each is read from the standard's rule and start and held to the Gregorian dates of its table (`test/tempo/rfc7529_test.exs`).

* **A month is named as its calendar names it.** With an `RSCALE` that is not the Gregorian, `BYMONTH` is the month by its name (`traditional_month`, written `5m`), and `5L` its leap month (`5+m`): CLDR's numbering, which Calendrical gives, is RFC 7529's (Adar I is `5L`). A yearly rule takes the month of its start the same way, in any rule from a start of another calendar, with `RSCALE` or without.

* **`RSCALE=GREGORIAN` is the calendar a rule is in with none.** It is written back only where the rule has a `SKIP`, which RFC 7529 gives with an `RSCALE` and not without; a `SKIP` with no `RSCALE`, and a leap month with none, are errors as they are read. A rule of another calendar that steps by weeks, days or the clock and selects by weekday and time of day is written with no `RSCALE`, reading in the Gregorian as itself, as before.

* **A skip is a part of a selection**, `skip: :forward` or `:backward`, written `(forward)s` after the days it moves. A month the year lacks (a leap month in a year with none, a month past the year's last) is changed first, to the month after or the month before, and then a day the month lacks, to the first of the month after or the month's last day. It moves a month and a day of a month, and nothing else a selection names. Two days moved to one are that day once, and a day moved out of its period is kept, as a rolled day is.

* **JSCalendar's `rscale`, `skip` and a `byMonth` of `"5L"`** are read the same way.

* **Found and fixed: a leap month was read as the month before it.** `~o"5774Y5+m8D[u-ca=hebrew]"`, the eighth of Adar I, was given the day of the eighth of Shevat, the note of a leap month being taken off where a number's annotation is. It is 8 February 2014 now, and was 9 January.

* **Found and fixed: a guide gave a wrong date.** `guides/rfc5545_rrule_conformance.md` showed a yearly rule from 15 Nisan 5786 falling on 24 March 2027. The rule had taken the start's month by its place in the year, which is another month in a year with a leap month before it; Passover in 2027 is 22 April, which it gives now. The example had been run, and was wrong.

* **Not done.** A value that names a leap month in a year that has none (`5775Y5+m8D[u-ca=hebrew]`) is read and has no day, where it should be refused as it is read. It is in `TODO.md`.

* **Decision.** Mine, in building (2026-10-14); for the user to overrule.

* **State.** Built.

## 30. An hour a fall-back shows in two parts

* **Question.** What is the value of an hour when a zone's clock goes back into the middle of it, and shows a part of it a second time without coming to its start again?

* **Context.** On 5 April 2026 the Chatham Islands' clock goes from 03:45 back to 02:45, so it shows 02:00 to 03:00, then 03:00 to 03:45, then 02:45 to 03:00 again, then 03:00 to 04:00. The walk of the day gave the four hours in that order, the second showing of each with the offset it has. The value of the second part of the hour from 02:00, `T2H` at +12:45, was sixty minutes long: "02:00 at +12:45" is a moment the clock read 03:00 at +13:45, so the value ran over the forty-five minutes before it, and `Enum.count/1` of its minutes was sixty where the clock showed fifteen. The engine's rule was that a shift written beside a zone "gives the moment, whatever the clock showed", which disagrees here with "an hour is what the clock shows of it". The old design had left this day out of its table for a decision. The options: (1) the value is the part the clock showed, a shift beside a zone saying which showing is meant; (2) leave it, the hours of this day overlapping; (3) the walk yields an interval for a partial showing, a walk of hours then giving values and intervals.

* **Decision (2026-10-14).** Option 1. A shift the zone never has within the unit is still the moment itself.

* **State.** Built: `Tempo.Zone.shown_from/4`. The day is in the table `test/tempo/change_of_the_clock_test.exs` holds to `DateTime`, twenty-two days now. The value is fifteen minutes long, `Tempo.to_datetime/1` of it is 02:45 at +12:45, and its interval is written `T2HZ12H45M/T3HZ12H45M`: its start as the value itself, which begins where the clock shows it, and not as `T2H45M`, as was said when the question was put.

## 31. The unit relative words are counted in where none is asked for

* **Question.** In which unit does `Tempo.to_relative_string/2` count the difference between an expression and what it is relative to, when the caller names no `:unit`?

* **Context.** The rewrite counted in the first unit the two starts differ in. Porting the old tests of the words showed what that gives: `2026-01-01T00:01` from `2025-12-31T23:59` was "next year", `2026-07-01T01` from `2026-06-30T23` "next month", `2026-06-15T12:00:30` from `2026-06-15T11:59:45` "this hour", `2026` from `2026-06-15` "5 months ago", `2026-06` from `2026-06-15` "14 days ago", `2026-06-15` from `2026-06-15T12:00` "12 hours ago", and `2026-02-01` from `2026-01-31` "next month". The old suite's rule was the largest unit of which a whole one lies between the two, and never a unit finer than the expression's own, which gives "in 2 minutes", "in 2 hours", "in 45 seconds", "this year", "this month", "today" and "tomorrow" for the same. The options were (1) the old rule, (2) the first differing unit with its clock cases made consistent, and (3) to refuse where no unit is given.

* **Decision (2026-10-14).** Option 1.

* **State.** Built in `Tempo.Format`. The unit is the largest of year, month, week, day, hour, minute and second of which a whole one lies between the two starts (a year and a month by the calendar's own, from a day and a time to the same again), unless that is finer than the unit the expression is written to, which is then the unit. A year, a quarter, a month, a week and a day are counted by the calendar's periods on the expression's clock; an hour, a minute and a second by those that pass, so `2026-03-29T04[Europe/Paris]` is "in 2 hours" from `T01` of that day. A unit asked for is counted in as it is. `test/tempo/words_test.exs` holds the examples above and the old suite's.

## 32. Relative words for a floating value beside a zoned one

* **Question.** May `Tempo.to_relative_string/2` count a floating expression from a zoned `:from`, or a zoned one from a floating `:from`, where every other operation on the two is a `Tempo.FrameError`?

* **Context.** The default `:from` is the current second of UTC, so the answer decides what `Tempo.to_relative_string(~o"2026-06-16")` does with no `:from` at all. As built, the floating one was read on the zoned one's clock: `2026-06-16` from `2026-06-15T09:00[Europe/Paris]` was "tomorrow", and so were `2026-06-16[Europe/Paris]` from `2026-06-15` and `2026-06-16T10:00[Europe/Paris]` from `2026-06-15T09:00`. The options were (1) to keep answering on the zoned one's clock, (2) to answer for dates and refuse a floating time of day, close to what the old suite did, and (3) to refuse always, which makes the default `:from` an error for every floating value.

* **Decision (2026-10-14).** Option 1.

* **State.** As built, now documented in `Tempo.to_relative_string/2` as the one place a floating value stands beside a zoned one, and held by `test/tempo/words_test.exs`.

## 33. A time shift that disagrees with the zone beside it

* **Question.** What does Tempo make of a time shift written beside a named zone that the zone does not have at that moment, as in RFC 9557's `2022-07-08T00:14:07+00:00[!Europe/London]`?

* **Context.** RFC 9557 section 3.4 says an application MUST act on such an inconsistency where the zone's suffix has the critical flag `!`, and MAY where it has not; and that `Z` in place of the offset asserts no local time, so `2022-07-08T00:14:07Z[Europe/London]` is never inconsistent. Tempo read all four of the section's figures, critical or not, as the moment the shift gives, and read `+00:00` as `Z`, so it could not tell the form that asserts a local time from the one that does not. Decision 30 had settled that a shift a zone never has within a unit is still the moment itself. The options were (1) to refuse the critical case and keep the rest, (2) to refuse every disagreement, as JavaScript's Temporal does by default, which makes a stored meeting unreadable after a zone's rules change, and (3) to leave it and record the gap.

* **Decision (2026-10-14).** Option 1.

* **State.** Built. `Tempo.Validate` refuses a value of a day or finer whose shift asserts a local time the critical zone has neither as the value begins nor as it ends (so either shift of a reading shown twice stands): a `Tempo.ZoneError` with reason `:inconsistent`. It holds at an end of an interval, a member of a set and the start of a recurrence, and for a critical offset written as the zone (`+08:45[!+08:00]`). `+00:00`, `+00` and `Z0H` are held as `[hour: 0, minute: 0]`, apart from `Z` (`[hour: 0]`), and written back as `Z0H0M`; `-00:00` is `Z`, as RFC 9557 section 2 has it. `test/tempo/zone_validation_test.exs` holds the section's figures.

## 34. Numbered weekdays of several days in one rule

* **Question.** How does Tempo read RFC 5545's `BYDAY=2MO,2WE`, the second Monday and the second Wednesday of each month, which it refused, as it refused `1MO,-1FR` and `MO,1TU`?

* **Context.** ISO 8601-2 §12 allows "only one selection rule of the same kind within a selection rule set", and applies a position last, over everything selected, so `L{1,3}K2IN` is the second of the Mondays and Wednesdays taken together (3 June 2026), not the second of each (8 and 10 June). No single ISO 8601-2 selection says the rule. Several numbers on one weekday (`2TU,4TU`, `L2K{2,4}IN`) were read. The options were (1) a set of selections as a Tempo extension, `L{1K2I,3K2I}N`, whose values are taken together, with `COUNT`, `UNTIL`, `BYSETPOS` and times of day applying to them all, (2) a set of recurrences, one for each numbered weekday, which cannot express `COUNT` and is not one RRULE to write back, and (3) to keep refusing.

* **Decision (2026-10-14).** Option 1.

* **State.** Built. A selection holds `{:all, [parts, ...]}`, read from `{…,…}` inside `L…N` and written back so; `Tempo.selection/1` takes `all: [[...], ...]`. Each selection of the set is made in the period, or in each value the parts before it select (`L6M{1K1I,2K}N`, in June), and their values are taken in time order, a value two pick once; the parts after it select within each value, and a position after it counts among all it selects. `Tempo.RRule.parse/2` lowers numbered weekdays of several days, or numbered weekdays beside a `BYSETPOS`, to a set with one selection for each weekday (a weekday written plain beside a numbered one is every one of it), and `Tempo.RRule.to_string/1` writes it back as `BYDAY`. `test/tempo/selection_set_test.exs` holds it to `Date`, and `test/tempo/rrule_measure_test.exs` to the independent expander. The grammar guide and the conformance guides list it among Tempo's own extensions.

## 35. How fast rule expansion must be before release

* **Question.** How much faster must the expansion of a recurrence rule be before 2.0 is released?

* **Context.** `bench/against_1_6_bench.exs` ran one set of cases against 1.6.4 and 2.0. Reading text was thirty times faster, walking and writing a little faster, the set operations about three times slower, and rule expansion 145 to 19,000 times slower: 240 last weekdays of a month took 28 seconds and 36 GB. Two fixes (a clock reading named by number found by arithmetic where the offset is steady, and the children of a steady span found without the zone database) brought that to 18 to 2,000 times slower: 50 yearly fourth Thursdays of November 0.61 s, 240 last weekdays 1.9 s, 720 hours 0.15 s. What remained was structural: each period of a rule is selected in afresh, and in a zone each period asks the database tens of times. The options were (1) to make it fast now, aiming at about ten times 1.6.4 on the same cases, (2) to release and optimise in 2.x, and (3) to fix the zone lookups alone.

* **Decision (2026-10-14).** Option 1.

* **State.** Built, with decision 37. On 2026-10-14 rule expansion stands at 3 to 11 times 1.6.4 on the benchmark's cases, from 145 to 19,000. The work found and fixed three defects: an hourly rule across a repeated hour searched for ever, a time of day selected on a fall-back day missed moments, and decision 36 was put.

## 36. A time of day the clock shows twice, or skips, within a period

* **Question.** What does a selection, or a rule, give for a time of day that a zone's clock shows twice, or skips, within the period it selects in?

* **Context.** Making rule expansion fast (decision 35) found that a selection of a time of day in a day gave both showings of a repeated reading: a daily rule at 01:30 in Chicago had two occurrences on 1 November 2026 (at -05:00 and -06:00), and `Tempo.select` of minute 30 in that day gave 25 values. A value written `2026-11-01T01:30[America/Chicago]` is read as the first showing. RFC 5545 section 3.3.5 says a local time that occurs twice "refers to the first occurrence", and section 3.3.10 says the same of a rule's instances; of a time that does not occur, 3.3.10 says such instances "MUST be ignored" and also that they are read as 3.3.5 reads them, by the offset before the gap. A daily rule at 02:30 gave nothing on 8 March. The options were (1) one answer for selections and rules alike, a reading shown twice within a period being its first showing, as a value written to it is, (2) every moment for a selection and the first showing for a rule, and (3) every moment everywhere.

* **Decision (2026-10-14).** Option 1. A reading the clock skips stays no value, following section 3.3.10's "MUST be ignored".

* **State.** Built in `Tempo.Select`: a period's values are taken once by their reading, the first showing in time. The second showing is kept where the period holds it and not the first, so an hourly rule across a repeated hour still gives each hour that passes. `test/tempo/clock_selection_test.exs` holds both to `DateTime`.

## 37. Whether to carry rule expansion on to ten times 1.6.4

* **Question.** With rule expansion at 5 to 28 times 1.6.4 on the benchmark's cases (from 145 to 19,000), is it carried on to about ten times before 2.0, or accepted?

* **Context.** Daily and hourly rules stood at 16 times: a period costs about 9 µs with no zone, where 1.6.4 took about 1 µs an occurrence, in some twenty computations of an extent a period, spread over building the period, selecting in it, making the occurrence's span and testing its end. The yearly fourth Thursday of November stood at 28 times in Chicago and about 17 floating, the difference being `tz` computing each period past its precompiled years afresh. The options were (1) to accept this for 2.0 and move to the release work, (2) to carry on to ten times by restructuring the rule walk so that a period's span is built once and passed on, and (3) to accept it and add a fast path for rules that keep only the start's time of day, exact with no zone.

* **Decision (2026-10-14).** Option 2.

* **State.** Built. The rule walk carries each period's extent and each occurrence's (`Tempo.Spans`), a period's extent is given to the selection, the start of the next period is kept from the one before, a period of one day is tested for its date and its named times built directly, and a yearly rule with a numbered weekday in named months keeps one period a year (where it had twelve, and was written back as a monthly rule). Rule expansion stands at 3 to 11 times 1.6.4 on the benchmark's cases; `TODO.md` holds the numbers and, under "Performance", where 2.0 could be faster still.

## 38. A member both operands of a union hold

* **Question.** Is a member that both operands of `Tempo.union/3` hold one member of the union, or two?

* **Context.** `Tempo.union(~o"2026-06", ~o"2026-06")` was `{2026Y6M/2026Y6M,2026Y6M/2026Y6M}`, and the union of June and July with June held June twice. The redesign plan had listed "`union(a, a)` doubles every member" among 1.6's flaws; 2.0's set-algebra models defined union as both operands' members, repeats included, and `Tempo.equal?/2` (which compares the time covered) already held `union(a, a)` equal to `a`. The options were (1) the same member, in span, written form and metadata, being one member, members that differ in any of those staying two, (2) keeping both operands' members with repeats, and (3) merging members that cover the same time, whatever their form or metadata, which drops one member's metadata.

* **Decision (2026-10-14).** Option 1.

* **State.** Built: `Tempo.union/3` takes a member once where both operands hold it (or one holds it twice), with an endless operand too (`Tempo.Algebra.merged/2`). The models of `test/tempo/set_operations_test.exs` and `set_operations_measure_test.exs` say so, and its tests hold June beside 1 to 30 June, and two bookings of one hour with different metadata, as two members.

## 39. An argument that is no expression

* **Question.** What does a public function answer when an argument that should be an expression is not one: `nil`, a string, a `Date`, a number?

* **Context.** Found porting the `tempo_holidays` cases, whose tests passed `nil`, `""`, `:""` and `42` to `Tempo.on/2`, `Tempo.at/2` and `Tempo.duration/1`. A survey of every public function of one or two arguments found about sixty that raised `FunctionClauseError`, about thirty that returned a named error (the set operations, `relation/2`, `to_string/2`: `Tempo.ConversionError` with reason `:not_an_expression`), eleven accessors (`year/1`, `day_of_week/1`) that returned `nil`, and the relation predicates, which raised a `Tempo.ConversionError`. The rule the redesign holds every function to on every shape of expression is that it answers or returns a named error. The options were (1) every public function returns `{:error, %Tempo.ConversionError{reason: :not_an_expression}}`, as the set operations did; (2) raise `FunctionClauseError`, as Elixir does by convention, and leave the type to Dialyzer, changing the functions that returned an error; (3) leave it mixed.

* **Decision (2026-10-14).** Option 1.

* **State.** Built. A function that returns its errors returns `:not_an_expression`; a function that answers a bare value (a predicate, an accessor, `metadata/1`, `compare/3`) raises it, as it raises its other errors, since an `{:error, _}` tuple from a predicate would read as true in `Enum.filter/2`. Text given to a reader that is not a string is an `ArgumentError`, a zone that is not a string a `Tempo.ZoneError`, and an Elixir value of the wrong kind to `from_date/1` and its siblings is `:not_an_elixir_value`. The `Tempo` moduledoc states the rule. Extended at the 2.0 release review (2026-10-15) to every documented function of every public module: `Tempo.Interval.from/1` and its siblings given a value that is not an interval return `:not_an_interval`; `Tempo.Duration`'s functions given no duration `:not_a_duration`; `Tempo.map/2` and `try_map/2` an `ArgumentError` for what is not enumerable or not a function of one argument; and a unit that is not one, given to `trunc/2`, `round/2` or `at_resolution/2`, an `ArgumentError`. `test/tempo/not_an_expression_test.exs` calls every documented function of the library with `42` for each argument, and again with a right first argument and `42` for the rest, and holds each to a named error.

## 40. A set of rules in two calendars

* **Question.** How does one set hold recurrences of different calendars: Saudi Arabia's holidays, Islamic rules beside Gregorian ones, or Korea's, Korean rules beside Gregorian ones?

* **Context.** Found porting `tempo_holidays`. An expression is in one calendar (decided 2026-10-12), and `Tempo.IntervalSet.new/2` and `Tempo.RecurrenceSet.new/2` bring every member to the first member's calendar with `Tempo.to_calendar/2`. That converts a value, an interval or a bounded recurrence through its spans, and refuses a recurrence with no end as `:unbounded`, so `Tempo.Holidays.holidays(:SA)` was an error. The options were (1) to convert a rule as a rule: `to_calendar/2` of a recurrence with no end keeps selecting in its own calendar and gives its occurrences in the target, and a set brings such a member to its calendar so, every span the set gives being of one calendar, and such a set having no ISO 8601 text, since a member's own calendar cannot be written inside it; (2) to let a set of recurrences hold several calendars, its occurrences read in its first member's, an exception to one calendar to an expression with the same mechanics; (3) to keep refusing, and have `tempo_holidays` return a set for each calendar, combined by the caller within a window.

* **Decision (2026-10-14).** Option 1.

* **State.** Built. `Tempo.to_calendar/2` of an expression with no end is `{:when, rule, read_in: calendar}`: `Tempo.Spans` selects the rule in its own calendar and reads each span in the other, with the wrapper's metadata beneath the span's; `Tempo.Writer` refuses it (`:read_in_another_calendar`); `Tempo.Select` takes it as a selector, as it takes a recurrence. A rule whose domain has a last year (`R/{2015Y}/P1Y/F…`) is not one with no end, and is converted through its spans as a bounded recurrence is. `test/tempo/read_in_calendar_test.exs` holds Eid al-Fitr beside Saudi National Day to the Umm al-Qura dates, and every public function to answering such a rule or refusing it by name.

## 41. Civil holidays beside holidays projected onto their evenings

* **Question.** `Tempo.Holidays.day_start/2` (in `tempo_holidays`) projects the occurrences of a holiday whose day begins at sunset onto the evening before, a zoned interval, and leaves every other occurrence the civil day it is. A set is of one frame in 2.0, so the two are refused together. Where do the civil days go?

* **Context.** Found running `tempo_holidays` on 2.0: Saudi Arabia's holidays projected onto their evenings in Riyadh beside Founding Day. The reference place of a bare `:evening` or `:sunset` is the holiday calendar's (Mecca and Riyadh for an Islamic date, Jerusalem for a Hebrew one), and a civil day has none of its own. The options were (1) to place the civil days in the zone the day start is read in: the zone named, a location's zone through `tz_world`, or for a bare boundary the reference zone of the set's sunset holidays, UTC where none is found, a lazy set with a bare boundary needing a location; (2) to return the occurrences as a list, not a set; (3) to project to wall-clock times with no zone, so every member is floating, losing the instant.

* **Decision (2026-10-14).** Option 1.

* **State.** Built in `tempo_holidays`: `Tempo.Holidays.DayStart.civil_zone/2` and `Tempo.Holidays.day_start/2`, a lazy set given a bare boundary returning `{:error, {:location_required, day_start}}`; Saudi Arabia's Founding Day is a day in Riyadh beside Eid al-Fitr's evening.

## 42. Results of set operations across members that meet

* **Question.** Where two members of an operand meet, or overlap, is a result of an intersection, a difference or a symmetric difference one run across them, or a piece of each?

* **Context.** Found running `tempo_holidays` on 2.0: England's and Australia's holidays in 2027 share Christmas, observed Monday 27 December, and Boxing Day, observed Tuesday 28 December; their intersection was one two-day span named Christmas Day. The sweep gave maximal runs, each carrying the metadata of the member it began with, and the set-operation model compared answers as the time covered. Decision 38 kept members that differ in form or metadata two in a union. The options were (1) a result ends where the member it comes from ends and another goes on, so each keeps its own metadata, the time covered unchanged and `Tempo.IntervalSet.coalesce/1` joining; (2) to keep maximal runs; (3) to split only when `:metadata` is given.

* **Decision (2026-10-14).** Option 1.

* **State.** Built. `Tempo.Algebra`'s sweep credits a result, on each side, to the member covering its start that opened last, and ends it where that member ends while the result goes on; the time-covered sweep (`covered/3`, for free time) still joins. `Tempo.Matrix.Sets.by_member/3` works the same out on whole numbers apart from the code, and `test/tempo/set_operations_test.exs` holds intersection, difference and symmetric difference to it over every pair of sets of up to two members between four points and generated sets of four between nine. The iCal and cookbook guides join with `coalesce/1` where they ask for the time covered.

## 43. What `tempo_sql`'s Ecto types take and give on 2.0

* **Question.** `tempo_sql` 0.2.0 has a type for each 1.x struct: `Tempo.Ecto.Interval` (a `%Tempo.Interval{}` in a `tstzrange`), `Tempo.Ecto.IntervalSet` (a `%Tempo.IntervalSet{}` in a `tstzmultirange`), `Tempo.Ecto.Tempo` (a bare `%Tempo{}`, stored as its span) and the composite `Tempo.Ecto.TempoRange` and `TempoMultirange`. Every value is a `%Tempo{}` in 2.0. What does each type take and give?

* **Context.** Found porting `tempo_sql` to 2.0. The types can no longer tell a value from an interval or a set by its struct, and a companion is not to match Tempo's forms. The options were (1) types named for what the column holds: `Interval` takes any expression that is one span and loads an interval, `IntervalSet` any expression with a last span and loads a set, `Tempo` is `Interval` under its old name, the composites take any expression with ISO 8601 text, all through `Tempo.to_interval/2`; (2) 1.x's strictness, each type taking its one shape; (3) two plain types and the composites, `Tempo.Ecto.Tempo` dropped.

* **Decision (2026-10-14).** Option 1.

* **State.** Built in `tempo_sql`. `Tempo.Ecto.Interval` casts and dumps any expression of one span through `Tempo.to_interval/2` and `Tempo.Interval.instants/1`, and `Tempo.Ecto.IntervalSet` any expression with a last span. The composites keep any expression with ISO 8601 text and a place on the time line, their range the stretch it covers: its first start to its last end, unbounded above for a recurrence with no end; `../..`, a value with no year and a recurrence counted back with no start are refused. The port found four defects in Tempo, fixed: `IntervalSet.first/1` of a recurrence with no end raised, `IntervalSet.new/2` raised on a member that is no expression, `Interval.new/1` took an interval as an end, and `Interval.instants/1` of `../..` asked for a year.

## 44. Composite rows written by `tempo_sql` 0.2.0

* **Question.** The composite types' `meta` column holds each end of an interval as ISO 8601 text. A row written by 0.2.0 holding `from: "2026-06-15", to: "2026-06-21"` meant 15 June up to the 21st, the end exclusive as 1.x read it; 2.0 reads an end written to a day through it, a day longer. How are such rows read?

* **Context.** Found porting `tempo_sql` to 2.0. The plain `tstzrange` columns hold UTC instants and mean the same under 2.0. The options were (1) a meta version 3 holding the whole expression's 2.0 text, with versions 1 and 2 read as 1.x wrote them, an end written to a calendar unit moved back one unit to the end 2.0 reads and 1.x's forms translated, so no stored row is misread and none needs migrating; (2) version 3 for new rows, and versions 1 and 2 refused with an error naming a one-off migration task the library provides; (3) the version 2 format kept, its ends converted to and from 1.x's reading on every write and read.

* **Decision (2026-10-14).** Option 1.

* **State.** Built in `tempo_sql`. Meta version 3 holds the expression's text, its metadata and each member's for a set. A version 1 or 2 row is read with its end written to a calendar unit moved back a unit, a recurrence rebuilt with `Tempo.every/2` (`:to` for one counted back), and a set of version 2 intervals read member by member; a document with neither an expression nor both ends is refused.


## 45. How a built expression composes

* **Question.** Each builder (`Tempo.new/1`, `Tempo.every/2`, `Tempo.selection/1`, `Tempo.one_of/1`, the `new` functions of `Tempo.Interval`, `Tempo.Duration` and `Tempo.IntervalSet`) makes a whole expression in one call from keyword parts. Nothing refines an expression a step at a time: every week, then on Mondays, at nine, from June, ten times, in Paris. How does a pipeline of steps compose?

* **Context.** Asked for by the user as the one key feature Tempo lacks (2026-10-14), before a sweep that removes every expression built by string manipulation. The options were (1) refinement verbs on the one struct, each taking an expression or a result (`{:ok, _}`, `{:error, _}`) and returning a result, an error passing through to the end, every step's result an expression built as its text reads; (2) the same verbs returning the bare expression and raising on a part that cannot be built; (3) verbs that gather a plan, made into an expression by a final `build/1`, the steps not themselves expressions.

* **Decision (2026-10-14).** Option 1.

* **State.** Built. `Tempo.Builder` (`lib/tempo/builder.ex`) holds the steps: `every/1`, `on/3` (with `:nth` and `:within`), `at/2`, `lasting/2`, `starting/2`, `until/2`, `times/2`, `ending/2`, `in_zone/2`, `in_calendar/2`, `weeks_beginning/2`, `in_years/3`, `except/2`, `with_metadata/2` and `all_of/1`. A recurrence is rebuilt through `Tempo.every/2` from its own options with the one changed (`Tempo.Build.every_options/1`), a start, an end, a count and years each given once; a selection is merged into a recurrence's rule or a value's, and a time given to a positioned selection closes it first. `test/tempo/builder_test.exs` holds each pipeline to the text it reads as, seventeen of RFC 5545's examples among them, and `test/tempo/holiday_builder_test.exs` builds a rule of each of the 290 shapes `tempo_holidays` makes for its 208 territories. Building it found five defects, fixed: the occurrences of a recurrence with no rule did not carry its metadata; `Tempo.in_zone/2` took no fixed offset; a set whose member is a recurrence with an open start did not read (every holiday set of its territories, 375 of 3,695 rules, which now all read back as they were written); and `Tempo.every/2` and the RRULE reader left an until out of its start's zone and calendar.

## 46. Where the builder's verbs live

* **Question.** The verbs read as English words (`every`, `on`, `at`, `starting`, `until`, `times`), and `Tempo.at/2` and `Tempo.on/2` already place one value on another. Where are they?

* **Context.** With decision 45. The options were (1) a module the caller imports, `Tempo.Builder`, so the verbs are short English words beside `Tempo`'s functions without colliding with them; (2) in `Tempo`, under names that do not collide.

* **Decision (2026-10-14).** Option 1.

* **State.** Built: `Tempo.Builder`, meant to be imported.

## 47. What the builder's verbs refine

* **Question.** Do the verbs refine recurrences and selections only, or any expression?

* **Context.** With decision 45. A value holds a selection as a recurrence does (`2026Y6ML1KT9HN`, the Mondays of June 2026 at nine), so one verb can refine both. The options were (1) the verbs refine any expression where they have a meaning: `~o"2026-06" |> on(:monday) |> at(hour: 9)` as `every(:week) |> on(:monday) |> at(hour: 9)`, values, spans, sets and recurrences alike; (2) recurrences and selections only, values and spans kept to `Tempo.new/1` and `Tempo.Interval.new/1`.

* **Decision (2026-10-14).** Option 1.

* **State.** Built: `on/3` and `at/2` refine a value, a recurrence and the members of a set; an interval is refused, with `Tempo.select/3` named.

## 48. Test code that generates the text of an expression

* **Question.** With no expression to be built by string manipulation or interpolation (asked by the user, 2026-10-14), what of the test code that writes text on purpose: the matrix's corpus (`test/support/matrix/selections.ex`, `shapes.ex`, `calendar_census.ex`), which writes each entry as ISO 8601 text from data so a reference can work out its answers without calling Tempo, and whose values the operations' tests read from that text; the grammar's generator and mutator, which hold the reader to the grammar; `rrule_measure_test.exs`, which writes 162 RRULEs from parts; and the iCalendar and JSCalendar tests, which assemble their documents from fragments?

* **Context.** The sweep of the four projects found no expression built from text in any library, guide, livebook or README; it rewrote the reader's two re-reads of text it had assembled and six test sites that built values from text. The options were (1) generated text only where reading text is what is tested: the grammar's generator and mutator stay; the matrix and census build each value from parts and hold the reader by reading the writer's text back; the RRULE measure builds its rules with `Tempo.RRule.from_rule/2`; the iCalendar and JSCalendar documents are written whole; (2) everything from parts, the grammar's generator included, the reader held to literal texts and round trips alone; (3) as 1, with the calendar documents left as they are, a document of another format being that format's input.

* **Decision (2026-10-14).** Option 1.

* **State.** Built. The matrix's generated values are built from parts: `Tempo.Matrix.Shapes` holds each shape as what a unit holds and builds with `Tempo.new/1`, `Tempo.Interval.new/1` and `Tempo.every/2`; `Tempo.Matrix.Selections.value/1` builds each selection with `Tempo.selection/1` and `Tempo.on/2` (all 294 equal to what their old text read to); the census gives its forms, values with no year and shapes as parts its test builds; `test/tempo/matrix_written_test.exs` holds the reader to the writer's text of every value built. The RRULE measure takes its generated rules as the map `Tempo.RRule.from_rule/2` takes, reading text only for the standard's examples, an `UNTIL` at UTC read on the start's clock; the JSCalendar tests make each document as data and encode it, and the iCalendar tests write theirs whole. Building the matrix from parts needed two builders, added: `Tempo.new/1` takes a group (`group: {2, [month: 3]}`) and `:qualifications`; and found one defect, fixed: a recurrence whose start's year is a set (`R3/{2026,2028}Y6M15D/P1D`) was written but not read.

## 49. The builder's steps for qualifications

* **Question.** `Tempo.new/1` takes `:qualifications`, and `Tempo.Builder` had no step for them. How does a pipeline mark a value uncertain or approximate?

* **Context.** Asked with decisions 50 and 51, finishing the builder. The reader marks every unit of a value for a mark after it (`2026-06-15?`) and one unit for a mark on it (`2026Y6?M`); an interval's marks are on its ends; `?` and `~` together are `%`. The options were (1) `uncertain/2` and `approximate/2`, marking the whole value or the units named, the two together `%`, a set's members each, and an interval refused with the instruction to mark its ends before joining them; (2) one step, `qualified(step, mark, units)`; (3) as 1, with an interval's ends marked in place by an option.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: `Tempo.Builder.uncertain/2` and `approximate/2` (`Tempo.Build.qualifying/3`), held to the reader's forms in `test/tempo/builder_test.exs`.

## 50. The builder's step for a group

* **Question.** How does a pipeline say "the second three months of 2026" (`2026Y2G3MU`)?

* **Context.** With decision 49. The options were (1) `grouped(step, nth, length)`, `nth` a number, a list or a range; (2) the same as `group/3`; (3) no step, groups kept to `Tempo.new/1`.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: `Tempo.Builder.grouped/3` (`Tempo.Build.grouping/3`), its span held to `Date`.

## 51. The builder's steps for unspecified units, masks, margins and significant digits

* **Question.** Which of the rarer unit shapes have steps?

* **Context.** With decision 49. The options were (1) `some(step, unit)` for an unspecified unit (`2026Y6MX*D`), with masks, margins and significant digits left to `Tempo.new/1`'s held forms; (2) as 1, named `unspecified/2`; (3) steps for all four.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: `Tempo.Builder.some/2` (`Tempo.Build.unspecifying/2`).

## 52. The errors of `Tempo.Event.date/3`

* **Question.** `Tempo.Event.date/3` returned bare reasons (`{:error, {:unknown_event, name}}`, `{:invalid_zone, zone}`, a resolver's own reason) where every other public function returns an exception. Which should it return?

* **Context.** Found in the 2.0 release review. The reasons come from the computation and from `Tempo.Event.Resolver` implementations, which return `{:error, reason}`. The options were (1) to name the error in `date/3` and leave the behaviour as it is; (2) to change the behaviour so a resolver returns an exception; (3) to leave it.

* **Decision (2026-10-15).** Option 1.

* **State.** Built. `date/3` returns a `Tempo.InvalidDateError` with `unit: :event` and the reason, as the reader already reported an unknown event, a `Tempo.ZoneError` with reason `:unknown` for a zone after an `@` that is none, and an exception a resolver returns as it is.

## 53. A workday predicate that cannot answer

* **Question.** `Tempo.workday?/2` and `weekend?/2` returned `{:error, exception}` for a value that names several days or a territory that is none. Decision 39 has predicates raise. Which do they do?

* **Context.** Found in the 2.0 release review. The options were (1) raise, as the other predicates do; (2) keep the error, as an exception to the rule.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: both raise the error, and a non-expression raises `:not_an_expression`. `Tempo.Workdays`'s own functions, which are no API, keep returning it for the workday functions that use them.

## 54. Truncating to a season or a traditional month

* **Question.** `Tempo.trunc(~o"2026-06-15", :season)` answered the month, and a Hebrew date truncated to `:traditional_month` its ordinal month. What should they answer?

* **Context.** Found in the 2.0 release review. The options were (1) a named error unless the value is written in the unit; (2) compute the season or the traditional month. A season of 21 to 24 has months in the territory in force (decisions 19, 20 and 22), so option 2 is open for a season without new work in Calendrical.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: `trunc/2`, `round/2` and `at_resolution/2` return `Tempo.ConversionError` with reason `{:not_written_in, unit}`, and extending a value to either unit is the same error, since a year begins in neither. Found with it and fixed: `at_resolution/2` appended a unit on another axis to the value (`2026Y6M1W`, `2026Y34M1D`, and `2026Y1K`, every Monday of 2026), and now names the period of that unit the value starts in, as `trunc/2` does; a weekday or a day of the year extended to the clock skipped the hour and the minute; a year extended to a quarter or a century to a decade raised `KeyError`.

## 55. A clock for tests

* **Question.** 1.6 documented `Tempo.Clock.Test` for pinning the current time in a test. 2.0 had dropped it, leaving a test to write a clock module and `Process.put({Tempo.Clock, :clock}, MyClock)`. Should 2.0 have one?

* **Context.** Found in the 2.0 release review: the removal had no changelog entry, and the migration guide counted the module as engine. The options were (1) restore `Tempo.Clock.Test` with its 1.6 API, so a 1.6 suite migrates unchanged; (2) add `Tempo.Clock.put/1`; (3) leave it and document the `Process.put` route.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: `put/1`, `advance/1`, `reset/0` and `utc_now/0` as in 1.6. `put/1` also makes it the calling process's clock, so the 1.6 `config :ex_tempo, clock: Tempo.Clock.Test` is optional; a time asked or moved before one is pinned is a `Tempo.ClockError` with reason `:not_pinned`, where 1.6 raised a `RuntimeError`.

## 56. Rule expansion

* **Question.** Rule expansion is 2.7 to 9.7 times 1.6.4's time after the 2026-10-15 work on the set operations. How is it made faster without making the engine harder to read?

* **Context.** `Tempo.Expand` and `Tempo.Select` pass `%Tempo{}` values from step to step, and each step places the value on the line again: an occurrence of a weekly rule places about 25 values, which ask the zone about 100 times. The options were (1) carry the span each candidate was found at along with it, inside `Expand` and `Select`, the algorithms as they are; (2) a second path for rules that are pure Gregorian day arithmetic, compiled to tests of a day number, beside the general engine; (3) stop for 2.0.

* **Decision (2026-10-15).** Option 1.

* **State.** Built, each change commented where it is made. `Tempo.Expand.placed/2` gives each value with the extent finding it gave (a reading of a clock that keeps one offset), and an hour's minutes are found under the hour's extent rather than the hour placed again; `Tempo.Select` takes that extent to judge a candidate, keeps the extent a next container was found with, and looks for no container past the period's end; the walk places its first start once, and a span picked whole keeps the extent the walk gave it. Weekly MWF went from 22.2 to 16.8 ms, last weekday from 37.8 to 30.3, hourly from 9.0 to 7.3, yearly from 1.94 to 1.68: 4 to 8 times 1.6.4. What is left is `Tempo.Select.in_period/3` answering values without their extents, so the walk places what it picks again; carrying them out would thread `{value, extent}` through every picking, rolling and positioning step of `Select`.

## 57. Extents threaded through all of `Tempo.Select`

* **Question.** Decision 56 left `Tempo.Select.in_period/3` answering values without their extents, so the walk placed what it picked again. Threading `{value, extent}` through every picking, rolling and positioning step of `Select` was built and measured. Is it kept?

* **Context.** It made hourly and yearly rules 10 to 13% faster, last weekday and weekdays 2 to 4%, daily and weekly not measurably. The readability assessment found the algorithm as easy to follow as before, but `Select` harder to change safely: its picking pipeline carried pairs and a few steps plain values, two helpers took either, and the rule that a carried extent is what `Tempo.Spans.extent/1` gives was kept by hand in six places, where a forgotten one gives a wrong position near a change of the clock. The options were (1) revert it and keep decision 56's first round; (2) keep it with one constructor for a pair and a test holding every carried extent to `Spans.extent/1`; (3) keep it as it is.

* **Decision (2026-10-15).** Option 1.

* **State.** Reverted before it was committed. `Select` answers values; decision 56's carrying stays inside `Expand.placed/2`, `Select`'s judging of a candidate and its containers, and the walk. Further work on rule expansion starts from the zone: about 100 questions of it in each weekly occurrence, for skipped days, readings shown twice and steady offsets.

## 58. `Tempo.Spans` split along its sections

* **Question.** `Tempo.Spans`, budgeted at 500 lines as the meaning of any expression, had grown to 2,452: repeat rules, recurrences, exclusions, children and readings beside the meaning. Is it split?

* **Context.** Found in the review of the redesign against the 2.0 it replaced (2026-10-15). Each section was a module's job; every change of the performance work landed there.

* **Decision (2026-10-15).** Yes, one module for each job, with no change of behaviour.

* **State.** Built: `Tempo.Spans` keeps the meaning (frames, extents, `spans/2`, written spans, plural ends and sets, placing in a window, windows, members), 1,225 lines; `Tempo.Recurrence` has the occurrences of the `:every` form and the rule walk, 851; `Tempo.Exclusions` what a set or a rule leaves out, 148; `Tempo.Children` law 6 and the readings, 363. Each function another module calls is public with a `@doc` and a `@spec`; each module keeps its own `conversion/2`.

## 59. One home for a reading the clock shows twice

* **Question.** How a reading a zone's clock shows twice is found and written was implemented in `Tempo.Zone`, `Tempo.Expand`, `Tempo.Select` and `Tempo.Spans`. Is it brought to one place?

* **Context.** Found in the same review: the proposal's one classifier of a change of the clock, where 2.0 had three.

* **Decision (2026-10-15).** Yes, in `Tempo.Zone`, which the others call.

* **State.** Built: `Tempo.Zone.at_showing/3` gives a value, a container or a frame the shift of the second showing where the reading at a UTC tick is one, and `second_showing_of/2` the shift of a wall reading's second showing. `Expand`, `Select` and `Spans` call them, and their eight helpers for it are gone.

## 60. The module budgets restated

* **Question.** The budgets of the proposal's module map (section 5.3) are exceeded: the core is about 2.6 times its budget, `Spans` 4.9. Is the code held to them, or are they restated?

* **Context.** Found in the same review. Some of the excess is documentation and scope the budgets did not foresee (the builder, conditional holidays, named errors throughout).

* **Decision (2026-10-15).** Restated after 58 and 59, against the code as it then stands, each module's measured size with the reason it exceeds its first budget.

* **State.** Done: section 5.5 of `plans/architecture-redesign.md`, each budget the module's size rounded up to the next fifty lines, which a review holds the code to.

## 61. A zone asked once for each stretch of one offset

* **Question.** `Tempo.Zone` answers an offset at a tick from what it keeps in the process, sampled six days apart, and a weekly rule's occurrence asks it about 100 times. Is the zone asked for a stretch of one offset instead?

* **Context.** Found profiling rule expansion by layer (2026-10-15): the zone was 11 to 22% of a rule's time. A zone's offset changes a few times a year; `Calendar.TimeZoneDatabase` answers at an instant and gives no bounds, so the stretch's ends are found as `Zone` already finds a change, by halving.

* **Decision (2026-10-15).** Yes.

* **State.** Built inside `Tempo.Zone`, its callers unchanged. Sampled stretches of one offset next to each other are kept as one, as a walk comes to them, and the two last grown are kept (the offsets before and after a change, which a walk near one asks on both sides of); a question of a tick, of the days about a wall reading or of a span within one is answered by comparing integers. The stretch's ends are where the samples are, not the change itself, so nothing is halved to find them. A question of the zone went from 53 to 45 ns, of the days about a wall reading from 98 to 45, of a span's one offset from 109 to 41. Weekly MWF went from 17.5 to 13.6 ms, last weekday from 29.8 to 26.9, weekdays from 3.84 to 3.64; hourly and daily are unchanged, and yearly went from 1.52 to 1.69 ms, a walk that jumps a year at a time missing the stretch it keeps at each step, and walking the hours of a day the clock springs forward from 2.1 to 3.1 µs, every question near the change missing too. `Zone` is 613 lines, its budget raised to 650 (section 5.5).

## 62. An engine value that carries its position

* **Question.** A value is held as its units as written, and each question of it (its resolution, whether it is plain or has a year, which units are of the date and which of the clock, its extent) walks them again: 35 to 50% of a rule's time. Is a value inside the engine held with its frame, extent and resolution reckoned once, written as units only when it is handed back?

* **Context.** The same profile. Decision 56 carried an extent along one path; decision 57 weighed the cost of a second representation in `Tempo.Select`. The options were (1) a short design and a prototype on one path, measured, before deciding; (2) after 2.0.

* **Decision (2026-10-15).** Option 1.

* **State.** Designed and prototyped: `plans/carried-position.md`. A daily occurrence is about a quarter placing values and a fifth building them, so a second representation through the engine has a ceiling of about a quarter, at the cost decision 57 declined. The prototype builds plain recurrences with the rule walk's builder (`occurrence_at/4`), the first start placed once and each next start kept: 36 to 50% faster, one builder where two were in use. The design recommends keeping it, and a rule for review in place of a second representation: a step that finds a position hands it to the next step that needs it, within its module.

## 63. What is kept of decision 62

* **Question.** The design and prototype of decision 62 (`plans/carried-position.md`) measured a second representation of a value through the engine at a ceiling of about a quarter of an occurrence, and found plain recurrences built by a builder that placed their unchanging first start twice an occurrence. What is kept?

* **Context.** The options were (1) keep the prototype, build no second representation, and hold the design's rule in review: a step that finds a position hands it to the next step that needs it, within its module; (2) keep the prototype and build the second representation; (3) revert the prototype.

* **Decision (2026-10-15).** Option 1.

* **State.** The prototype is kept: plain recurrences are built with the rule walk's builder, 36 to 50% faster. The rule is stated in `plans/carried-position.md` for reviews to hold.

## 64. Comparing where two expressions begin

* **Question.** 1.6's `Tempo.Compare.compare_endpoints/2` ordered two values by where each begins, and a consumer (`agenda`) orders session starts, a cutoff against a day, and a hold's expiry with it. `Tempo.compare/3` breaks a tie of starts by the ends, so a reading at nine and the day it begins are not the same. How does 2.0 compare where two expressions begin?

* **Context.** Found porting `agenda` to 2.0 (2026-10-15). The options were (1) a `:by` option of `compare/3`, `by: :start`; (2) a function of its own, `compare_starts/2`; (3) none, a consumer comparing the instants of `Tempo.Interval.instants/1`.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: `Tempo.compare(a, b, by: :start)`, the default `:start_and_end`; a `:by` it does not take is an `ArgumentError`. `test/tempo/compare_test.exs`. 1.6's `to_utc_seconds/1`, used to group by where values begin, is the same sorter (migration guide).

## 65. Where at least n members of a set overlap

* **Question.** 1.6's `Tempo.IntervalSet.overlapping(set, at_least: n)` gave the time n members cover at once, which `agenda` uses for a resource's concurrency. Is it in 2.0?

* **Context.** Found porting `agenda`. The options were (1) in Tempo, on the sweep; (2) in `agenda`.

* **Decision (2026-10-15).** Option 1.

* **State.** It was already there: `Tempo.IntervalSet.covered(set, at_least: n)`, with members that only meet not overlapping, as 1.6's did; the migration guide lists it. The survey that found the gap matched names, not meanings.

## 66. 1.6's quarter and half shorthand

* **Question.** 1.6 read `2026Y2Q` as the second quarter and `2026Y1H` as the first half, its own shorthand for ISO 8601-2's `34M` and `40M`. 2.0 read neither, and the migration guide did not say so. Are they read?

* **Context.** Found porting `agenda`, whose tests and 1.6's own holidays guide wrote `~o"2026Y3Q"`. The options were (1) not read, the migration guide and `agenda` writing the standard's form; (2) read as 1.6 did, as Tempo's own extension, written back as the standard's.

* **Decision (2026-10-15).** Option 2, in lower case as Tempo's designators are, since neither is a standard's: `q` and `h`.

* **State.** Built: `2026Y1q` to `2026Y4q` read as the quarters (`33M` to `36M`) and `2026Y1h`, `2026Y2h` as the halves (`40M`, `41M`, held as groups of six months), each written back as the standard's; a quarter or a half the year has not is a `Tempo.ParseError`. The conformance guide lists them with Tempo's extensions, the grammar guide has their productions, and the migration guide says that 1.6's `2Q` is now `2q`.

## 67. A set operation with several operands

* **Question.** 1.6's `union/3`, `intersection/3` and `difference/3` took a list as the second operand, combining the first with each in turn, an empty list imposing nothing. 2.0 took two expressions and refused a list, and the migration guide did not say so. Does 2.0 take a list?

* **Context.** Found porting `agenda`, whose planner intersects the free time of everyone a session needs in one call. The options were (1) a list as the second operand, as 1.6; (2) a one-argument form over a list; (3) none, a consumer folding with `Enum.reduce/3`.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: the list is taken one operand after another with the same options, the `:metadata` function applying at each step; an empty list leaves the first operand as it is; an operand that is no expression stops the operation with its error. `test/tempo/set_operation_operands_test.exs`. The migration guide maps 1.6's `metadata: :left` and `{:merge, fun}` to `:first` and the function itself.

## 68. A floating window beside zoned availability, in agenda

* **Question.** Agenda's `busy:` claims, `Agenda.only_during/2` and a session's `window:` are combined with a resource's free time by Tempo's set operations. Availability imported from a VAVAILABILITY in UTC (`Z`) is zoned, and a floating window or claim beside it is a `Tempo.FrameError` (`:floating_and_zoned`), where `Agenda.free(resource, within: window)` takes a floating window because Tempo's `:within` reads it on the expression's clock. Should agenda read its window-like arguments as `:within` does?

* **Context.** Found porting `agenda` onto 2.0: three VAvailability tests wrote floating windows against UTC hours. The options were (1) law 4: a caller states the frame, and the tests write `Z`; (2) a session's window and `only_during/2` read on the resource's clock as `:within` is, `busy:` held strict, which needs a public Tempo function to place a floating window on another expression's frame.

* **Decision (2026-10-15).** Option 1.

* **State.** Built in agenda: the three tests write their windows and claims in UTC beside hours imported in UTC, and `Agenda.from_ical/1`'s doc says a claim, a refinement or a session's window combined with imported hours is on their line, and a `within:` window alone may be floating.

## 69. A sentence about a span in a calendar ISO 8601 cannot name, in agenda

* **Question.** Agenda writes spans into sentences (`Agenda.Reconciliation.explain/1`, `Agenda.Arrangement.explain/1`, a ledger entry's default name) with `Tempo.to_iso8601!/1`. A span of a calendar with no IXDTF name, a fiscal calendar's, cannot be written (`Tempo.Iso8601EncodeError`), where 1.6 wrote it without its calendar. How is such a span written in a sentence?

* **Context.** Found porting `agenda`'s timesheets livebook: open hours selected from a fiscal quarter made `explain/1` raise. The options were (1) write such a span in the Gregorian calendar, so a sentence names its times in one calendar; (2) `explain/1` returns `{:error, exception}`. `Tempo.to_string/2` was no option: Localize writes a fiscal date of July to December with its fiscal year and its Gregorian month (recorded in Localize's TODO.md).

* **Decision (2026-10-15).** Option 1.

* **State.** Built in agenda: `Agenda.Written.span/1` (internal) writes a span as `Tempo.to_iso8601/1` does, and one of a calendar ISO 8601 cannot name in `Calendar.ISO`; `Agenda.Reconciliation.explain/1`, `Agenda.Arrangement.explain/1`, a hold's default name and a refusal's message use it. Tested by hours of a fiscal quarter explained as `2026Y8M10DT9H/T17H`.

## 70. Which functions have a `!` form

* **Question.** The CHANGELOG and the migration guide say every function that can fail has a `!` form. 51 public functions return `{:ok, value}` or `{:error, exception}` with none: `to_date/1`, `shift_zone/2`, `members/2`, `complement/2`, `Tempo.IntervalSet.coalesce/2` among them. Which have one?

* **Context.** Found porting `agenda`. The options were (1) a `!` form for every constructor, conversion, parser and set operation, and the claim reworded to say so; (2) a `!` form for all 51; (3) the claim reworded only.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: 31 `!` forms. In `Tempo`, from the table of raising forms, which takes a default for a last argument a function defaults (so `union!/3`, `intersection!/3` and `difference!/3` now take options): `to_date!`, `to_time!`, `to_naive_datetime!`, `to_datetime!`, `to_elixir!`, `to_week_start!`, `shift_zone!`, `in_zone!`, `walk!`, `members!`, `today!`, `now!`, `parse_duration!`, `symmetric_difference!`, `complement!`, `members_overlapping!`, `members_outside!` and `members_in_exactly_one!`. Beside their functions: `Tempo.Duration.to_unit!` and `to_microseconds!`, `Tempo.IntervalSet.slots!`, `coalesce!` and `covered!`, `Tempo.ICal.parse!`, `parse_file!`, `from_ical!` and `available!`, `Tempo.JSCalendar.parse!` and `from_jscalendar!`, `Tempo.RRule.from_rule!` and `Tempo.Workdays.new!`. Left without one, as queries and workday arithmetic: `days_in_month/1`, `Tempo.Event.date/3`, `Tempo.Interval.instants/1`, `Tempo.IntervalSet.relation_matrix/2`, `Tempo.LeapSeconds`, `Tempo.Territory.resolve/1`, the workday functions, and `try_map/2`, whose raising form is `map/2`. `test/tempo/not_an_expression_test.exs` found `Tempo.JSCalendar.parse/2` returning the `jscalendar` library's bare reason (`:invalid_json`), which its `!` form could not raise; it returns an `ArgumentError` naming it. The claim is reworded in the CHANGELOG, the migration guide, the README and `Tempo`'s moduledoc.

## 71. A decade or a century followed by other units

* **Question.** The reader read `202J2026Y`, `202J6Y`, `20C26Y` and `20C3J`, which ISO 8601-2 does not write (a decade and a century are written alone, §4.3.5, §4.3.6). A year after a decade was an absolute year, but one outside it (`202J2035Y`) failed only where it was used, and `Tempo.to_interval(~o"20C3J")` did not finish. What do these mean?

* **Context.** Found raising coverage on `Tempo.Expand`. The options were (1) a year or the units a year holds after a decade or a century, a year checked to be one it names, a decade after a century refused; (2) a year after one read as a place within it; (3) a decade and a century read alone only.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: `Tempo.Validate` refuses a decade after a century (`:after_a_century`) and a year its decade or century does not name (`{:out_of_range, year, years}`), with `Expand.years_of/2` the years each names. A year under its decade is found by its number, not counted from the end, so `-12J-125Y` is the year -125. `test/tempo/decade_century_test.exs`; the grammar guide says so.

## 72. An interval with no year in a :within window

* **Question.** `:within` places a value with no year, and set operations placed an interval with no year in their window, but `Tempo.to_interval/2` and `Tempo.members/2` left one as written (`T22/T02` within `2026-06-01` stayed `T22/T02`). Should they place it?

* **Context.** Found raising coverage on `Tempo.Spans`. The options were (1) place it as a value is, from each start the window holds; (2) a named error; (3) document that it is not placed.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: in a window on the line, each start the window holds (selected as a value with no year is) runs to the first reading of its end within one turn of the cycle the ends differ on, so `5K/2K` within two weeks is each Friday to the Tuesday after, and `12M/2M` within `2026` is December 2026 to February 2027. A window with no year places nothing. `test/tempo/placing_test.exs`, and an example on `Tempo.to_interval/2`.

## 73. A table of each zone's changes in place of samples six days apart

* **Question.** `Tempo.Zone` read the zone database at points six days apart, kept what it learned in the process dictionary, and reasoned that no zone's offset changes twice between two samples. The review of 2026-10-15 (`plans/reference-architecture-review.md`, section 3.1) found the state hidden and the reasoning broken by what `tz` answers for America/Scoresbysund on 2024-03-31 (an hour at -02:00 between two changes an hour apart, which is `tz`'s compilation and not IANA's data, but is what the database Tempo is given says). How should a zone's clock be read?

* **Context.** Elixir's `Calendar.TimeZoneDatabase` answers an offset at a point and gives no period's bounds, which is why the sampling existed. The options were (1) sample more finely, which no spacing makes exact; (2) a table of each zone's changes, built from the database's own list of periods where it has one and by sampling where it has none, kept for every process and searched by halving, as every other ecosystem's zone type is (Java's `ZoneRules`, Temporal's time zones, Rust's `chrono-tz`); (3) ask the database's wall-clock API for gaps and folds, whose limits are the changes, which still needs samples to find them.

* **Decision (2026-10-15).** Option 2. `Tempo.Zone.Table` holds a zone's changes as two tuples, the ticks ascending and the offset in force from each, in `:persistent_term` by database, data version and name. `Tempo.Zone.Transitions` is the one question Tempo asks beside the behaviour, a database's list of its changes and where its rule-made periods begin; it is known for `tz` (which generates the list but does not publish it: TODO.md, upstream) and configured for another. Where the list ends, or there is none, the table is grown by sampling six days apart with each change found to the second by halving, the assumption that a rule-made period changes once at most between two samples stated once there, and tested against every zone of the vendored database (`zone_table_test.exs`). Before any zone's standard time a sampled table begins in 1800. Every question of a named zone is a search in the table: the offset at a tick, the stretches of one offset about a wall reading (one, two for a fold, none for a gap, found by which stretch the reading's moment lies in), the first change in a span. `steady_offset/4` answers any span, not two days. A zoned value's `DateTime` is placed by Tempo's extent and shown on the zone's clock there, where it was placed again by the database's reading of the wall clock. The rule that no offset exists before year one is gone: the table answers the database's first period (local mean time) there, as `DateTime` does. `Tempo.Recurrence` carries the start of a rule's next period in the walk's own accumulator, where it kept it in the process; no `Process.get/2` or `Process.put/2` remains under `lib/tempo/core`.

* **State.** Built the same day. `Tempo.Zone` is 494 lines (260 of code) from 613 (349), with `Tempo.Zone.Table` 277 (175) and `Tempo.Zone.Transitions` 99 (42) beside it. Held by `zone_table_test.exs`: every change of every zone the database lists has the database's offset a tick before it and at it; a table grown past the list finds the changes where the database makes them (five zones, ten years); a database that lists nothing gives by sampling what the list gives; and America/Scoresbysund is read tick by tick and wall reading by wall reading as the database reads it, its day of two changes added to the clock-change measure. The benchmark (`bench/against_1_6_bench.exs`, 2026-10-15) is slower on rule expansion than with the samples kept in the process: weekly Monday, Wednesday, Friday 17.6 ms where it was 12.9, the last weekday of the month 32.3 where it was 26.2, hourly 8.3 where it was 5.5, weekdays 4.8 where it was 3.3; relating, comparing, the set operations and the walks are unchanged. Measured with Benchee: a question of the table costs about 250 ns (the configured database read as Erlang reads it, 120 ns; the data version, 15 ns; the persistent term, 70 ns; the search, 40 ns) where a hit in the process dictionary cost 55 ns, and a weekly rule asks the zone 45 times an occurrence (`Tempo.Zone.Table.of/3` is called 45 times for each: 19 for whether a clock keeps one offset through an extent, 23 for the offsets at a wall reading, the rest for the offset at a tick). The cost is the number of questions, which is the review's item on one positioned currency through the engine (`plans/reference-architecture-review.md`, sections 3.2 and 4.3 A) and not the table's; a table held in the frame an expression is read in would ask once for each frame reckoned, about 21 times an occurrence, and was left for that work. The exactness and the end of hidden state were taken at that price.

## 74. One positioned span type through the engine

* **Question.** A span the engine had built from positions it held was handed on as a `%Tempo{}` of two value ends and placed again by the next step, and four shapes carried a position beside a span in four modules (`plans/reference-architecture-review.md`, sections 3.2 and 4.3 A). Decision 63 declined a second representation of a *value* through the engine. Is the span given one?

* **Context.** Measured on 2026-10-15: a union of two sets of 100 placed each member span four times, a relation of two values placed each twice, and a weekly rule reckoned a value's frame 21 times an occurrence. The options were (1) one struct, `Tempo.Placed`, the written span with its two positions, made by `Tempo.Spans` for every span it denotes and read by every engine module that took a span; (2) the four shapes as they were; (3) decision 62's representation of a value, declined.

* **Decision (2026-10-15).** Option 1. It is not what decision 63 declined: a value keeps its units, and `Tempo.Expand` and `Tempo.Select` still hand a candidate's extent on as decision 56 built it; what changes is that a *span* is never placed twice.

* **State.** Built. `Tempo.Spans.placed/2` is the engine's reading of an expression, each span a `%Tempo.Placed{start, stop, span}` made where the span is made (a value's one span, a written span resolved, an occurrence of a recurrence, a member of a set merged in order, a span cut around an exclusion, a conditional member judged), an open end's position `nil`; `Tempo.Spans.spans/2` is `placed/2` with the places left off, for the public layer. `Tempo.Algebra` takes an operand's placed spans as the sweep's edges; `Tempo.Recurrence` carries occurrences and periods as placed spans and hands a placed period to `Tempo.Select.in_period/3`, whose `:extent` option is now its own; `Tempo.Children`'s readings, `Tempo.Conditions` and `Tempo.Exclusions` read positions from the placed span. The benchmark: relating two values 2.46 to 1.40 µs and comparing them 2.54 to 1.46, a union of two sets of 100 366 to 303 µs, an intersection 481 to 419, a difference 468 to 429; rule expansion unchanged (weekly MWF 17.6 to 18.3 ms, within its run-to-run spread), its placings being of values in `Tempo.Expand` (eight extents an occurrence) and its 45 questions of the zone an occurrence coming from there, which decision 63 leaves as they are. Memory per relation halved and per set operation fell by a sixth; per rule occurrence it rose by about a tenth, the placed struct beside each occurrence. Two defects the change found, fixed and held by `test/tempo/placed_test.exs`: a sequence that ends with a member (a recurrence with a count) lost that member where it was merged with another's spans, the merge reading a halting stream's last element as its end (`{R3/2026-06-01/P1M,2027}` had three spans, not four), in `Tempo.Spans.merged/1` and `Tempo.Algebra`'s cursor alike; and a recurrence whose start names several values (`R3/2026Y6M{1,15}D/P1M`) gave the first span's two values and no repeat of them, a match of one span against several falling through, where it is now each value's series merged in the order of time (under a rule the start is truncated to the cadence's unit, as before, and a start that still names several periods is refused by name). The totality fixture caught the second as the refactor changed what it answered.

## 75. Day labels by arithmetic within a period

* **Question.** `Tempo.Expand` asked the calendar for every day of a span to learn the day's label: the date of each day for its day of the month, the date and the year's span for its day of the year, the date and then the day of the week for its weekday; `Tempo.Walk` asked the date of every day it walked. Are the labels counted within the period instead?

* **Context.** `plans/reference-architecture-review.md`, section 4.3 D. The calendar modules were 8% of a weekly rule's profiled time and 16% of a monthly one's. A day of the year is by definition a count from the year's first day, and a weekday runs round the week (the calendar contract's law 4), so both are arithmetic from one question. A day of the month is a label, and a calendar that leaves days out as it changes (England, September 1752: the 1st, the 2nd, then the 14th) does not count them, nor does one whose month begins mid-way (England, March 1751: the 25th to the 31st). The options were (1) count where the labels count the days, asked of the calendar once a month by its first and last day's labels, and ask day by day where they do not; (2) leave the readings as they were; (3) assume labels count days, which the probe of section 8.2 of the plan shows false.

* **Decision (2026-10-15).** Option 1, with the week's length asked of the calendar and never assumed.

* **State.** Built: `Tempo.Calendar.month_of_day/2` answers the month a day falls in with its span, its first day's label and whether its labels count its days, and `year_of_day/2` the year's span; `Tempo.Expand` reads the three labels from them, and `Tempo.Walk` dates each day it walks from the month it keeps from the day before. The calendar modules are now 5% of the weekly rule's profiled time and 4% of the monthly one's; the benchmark's times are within their run-to-run spread (weekly MWF 17.6 ms, last weekday 33.0, the days of a year walked 113 µs), the readings replaced having been cheap in themselves. What the calendar is still asked an occurrence is the placing of values (`Tempo.Calendar.iso_days/4` eleven times, `valid_date?/4` eleven, the validation inside `Calendar.ISO.date_to_iso_days/3` of dates the calendar itself produced), which is decision 63's ground. `Tempo.Calendar` is 533 lines (311 of code), `Tempo.Expand` 1099 (742), `Tempo.Walk` 281 (183). The reform calendars' tests (`other_calendars_test.exs`) hold the fallback: September 1752 walks as the 1st, the 2nd and the 14th to the 30th.

## 76. A compiled day-number matcher for plain rules

* **Question.** Rule expansion was two to six times slower than the published 1.6.4, which had a weekday fast path beside its resolver, where 2.0 has one selection engine for every rule (decision 36's `Tempo.Select`), and the review of 2026-10-15 put the remedy at a rule compiled once into a test of a day number, the engine kept as the meaning (`plans/reference-architecture-review.md`, section 4.3 C). Is it built, and what does it cover?

* **Context.** Built after decisions 73 to 75, which changed what it costs. A rule whose parts are whole numbers and lists of months, days of the month and days of the week, with or without positions among what they pick, and whose period is a day or coarser, is a predicate on a day number: the weekday is one question of the calendar for a period's first day and then counted round the week; a day of the month is counted from the month's first label where the month's labels count its days (decision 75); a position is an index into the days that pass. The options were (1) the matcher in front of the engine, taken only where a rule is plain and a period is one it can test, proved equal to the engine by the measures; (2) the engine alone; (3) the matcher as the meaning of plain rules, two meanings where there was one.

* **Decision (2026-10-15).** Option 1.

* **State.** Built: `Tempo.Matcher` (284 lines, 178 of code) compiles a rule's parts once, in `Tempo.Recurrence`'s walk, to the months, the days counted from either end, the weekdays and the positions it tests and the readings of the clock it names; in a placed period it walks the period's days a month at a time, the calendar asked once a month and once a period, each day that passes given each reading, a reading the zone's clock skips left out, the positions applied, and each occurrence placed once as the engine places one. It leaves to the engine every other rule (a nested selection, a set of them, a day of the year, a mask, a range it cannot count, an event, a roll, a skip, a period finer than a day), a period in which a month does not count its days (England, September 1752), and a period on a fixed offset written beside a shift; the engine's look-ahead past periods that pick nothing is unchanged. The measures hold it to the engine: `rrule_measure_test.exs` (192 rules from three starts), `rfc5545_examples_test.exs`, `cron_test.exs` and the rule tests, and the conformance fixtures are unchanged; `matcher_test.exs` holds what compiles. The benchmark: weekly Monday, Wednesday, Friday 17.7 to 3.3 ms, the last weekday of the month 33.0 to 4.0, weekdays 4.9 to 3.8, daily 0.25 to 0.19; yearly (a nested selection) and hourly (a period of an hour) go to the engine and are unchanged at 1.75 and 8.4 ms. Against 1.6.4 the weekly rule is 3.9 times faster and the monthly 6.5 times, where they were 1.4 and 1.3 times slower; the daily rules are at 1.1 to 1.2 times 1.6.4, their cost now the period's own placing in the walk (`occurrence_at/4`) and the occurrence's writing, which are the value placings decision 63 leaves. `Tempo.Recurrence` is 940 lines (624 of code) and `Tempo.Select` 1058 (706), with `positions/2` public for the matcher.

## 77. `tz` as a dependency, asked where no database is configured

* **Question.** Tempo asked only the `Calendar.TimeZoneDatabase` the application configured, under `:ex_tempo` or `:elixir`, and under Elixir's own default, which knows only UTC, refused every named zone as `:no_database`. Every guide, the README and the livebooks told the reader to add `tz` and set it first, `tempo_holidays` requires it, and `tz` is the community's choice over `tzdata` (the user, 2026-10-16). Should Tempo require it?

* **Context.** The options were (1) `tz` a dependency, asked where neither `:ex_tempo` nor `:elixir` names a database, a database configured asked as before, and Tempo setting no global database; (2) `tz` a dependency and `Calendar.put_time_zone_database/1` called at start, which sets the application's `DateTime` behaviour from a library; (3) as it was, `tz` for dev and test only. Option 1 costs an application without `tz` one compile of the IANA data; one on `tzdata` carries both, which agree. It makes the transition table (decision 73) exact by default, since the `tz` adapter is then always present, and makes the request to `tz` for a public periods function one from a dependent package.

* **Decision (2026-10-16).** Option 1.

* **State.** Built: `{:tz, "~> 0.28"}` in every environment; `Tempo.Zone.database/0` reads Tempo's setting, else Elixir's where it is other than `Calendar.UTCOnlyTimeZoneDatabase`, else `tz`'s database; Elixir sets its UTC-only default in its own application env, so that default is not read as a choice, and a UTC-only database chosen on purpose is set under `:ex_tempo`; `:no_database` is now the refusal for a database configured that knows only UTC, its message saying so (`zone_database_test.exs`). The README's database section, the iCalendar guide and the booking tutorial say `tz` comes with Tempo and that `:ical` reads Elixir's own setting, which an application still sets to import a `TZID`; the tutorial's install line, which named `~> 3.0`, names `~> 2.0`.

## 78. Translating Tempo to Rust, Zig and Roc

* **Question.** Can Tempo be translated to Zig, Rust and Roc keeping the design and the public API as closely as possible, passing the same tests and conformance, with documentation that serves every port; the Rust idiomatic and safe, and ICU assumed for words and calendars in place of Localize and Calendrical?

* **Context.** `plans/translation-assessment.md`, from a census of `main` at `508e981` and the state of ICU4X 2.3, ICU4C 78.3, Zig 0.17 and Roc on 2026-10-16. The design is already written for ports (`guides/architecture.md`, the grammar, the conformance fixtures). ICU4X answers the core of the calendar contract for 16 of the census's 26 calendars, and not quarters, the weeks of a month, the bounds over all years, the cycle of years, solar terms, the weeks of any calendar but ISO's, astronomy or a locale's words. Nine questions were put to the user one at a time, each with a recommendation (the plan's section 8).

* **Decision (2026-10-16).** Rust first; Zig reassessed after its 1.0 and Roc after its 0.1. Beside the Rust port, a calendar crate that implements the contract over ICU4X and answers what ICU4X does not, with the eight calendars ICU lacks that are arithmetic on the Gregorian or Julian calendar, and an astronomy crate for equinoxes, solstices, new moons and solar longitude, with a hemisphere table; the lunisolar and observational calendars wait for a consumer. `parse/2` reads ISO 8601 only until ICU4X reads a locale's words. `#![forbid(unsafe_code)]` in the port's own three crates; a dependency's `unsafe` reviewed when it is added. Words for intervals, relative times and durations behind a feature marked unstable. Years −9,999 to 9,999 placed (ICU4X's `Date::try_new`), the rest read and written but refused by name when placed, so `Y12026` and `Y-61000/-2000` are expected differences. `jiff` for zones. Predicates return `Result<bool, Error>`. The Elixir suite run against the Rust core through Rustler while the engine is ported, then retired. The guides' examples and the census's walks and selections exported as text fixtures before the port begins.

* **State.** To build: the answer fixtures first (`TODO.md`, Open), then the port (`TODO.md`, Blocked on them).

## 79. A selection of a value no period has

* **Question.** A selection that names a value no period has (`L40DN`, `LT25HN`, `L60WN`, `L6M40DN`): does it select nothing, or is it refused?

* **Context.** Found on 2026-10-16 when the calendar census's selections (`Tempo.Matrix.CalendarCensus.selections/1`, worked out apart from the library and held by no test since the redesign) were measured against Tempo for the conformance fixtures: 985 selections, 800 agreeing, 143 of the differences this one. The census, written before the redesign, passes such a value over and selects nothing; Tempo's validator refuses it as it refuses `2026Y6M40D`, an `InvalidDateError` out of range. A value some periods lack (`L31DN`) passes over the periods without it either way.

* **Decision (2026-10-16).** Refuse by name: a selection is checked as a value is, as RFC 5545 bounds `BYMONTHDAY` to 1–31. The census changes to expect the refusal.

* **State.** Built: the census's selections expect the refusal for a month, a day, a day of the week, a week or an hour past every calendar's last, and `census.json` holds it as `no_such_value`; a position or a day of the year past the period's still selects nothing.

## 80. A day of the week, in a calendar whose week does not begin on Monday

* **Question.** In a calendar whose week begins on another day (`Calendrical.NRF`, Sunday), does `K` in a selection name the nth day of the calendar's week, as it does in a week date, or the day of the week counted from Monday?

* **Context.** Found with decision 79: 15 NRF selections differ. `2026Y20W3K[u-ca=nrf]` is the week's third day, a Tuesday, as decided on 2026-10-05 and held by the census, but `2026Y20WL3KN[u-ca=nrf]` selects the Wednesday, the selection engine reading `K` as the day of the week from Monday. In a calendar whose week begins on Monday the two readings are one.

* **Decision (2026-10-16).** The nth day of the calendar's own week, in a selection as in a value, so that a written unit has one meaning; RFC 5545's named weekdays (`WE`) are numbered for the calendar in `Tempo.RRule`'s lowering.

* **Decision revisited (2026-10-16).** Put again with its full reach: nine calendars of the census begin their weeks on another day (Sunday: Hebrew, the three Islamic, Coptic, the two Ethiopic, NRF; Saturday: Persian), as does any expression written `[u-fw=…]`, and decision 14 had a day of the week on its own numbered from Monday (`Tempo.day_of_week(~o"2026-06-21[u-fw=sun]")` was 7). The user chose the nth day of the expression's week everywhere: a week date, a day of the week on its own, a selection, a rule, in every calendar and week start. It supersedes that part of decision 14. A day named from outside Tempo (RFC 5545's `BYDAY`, cron's field, CLDR's weekend, the builder's `:monday`) is numbered in the expression's calendar; a selector of one calendar applied in another names the same days.

* **State.** Built: `Tempo.Calendar.day_of_week/4` asks the calendar's own numbering (`day_of_week(…, :default)`), beside `iso_weekday/4`, `first_weekday/1` and the two conversions; `Tempo.day_of_week/2`, `Tempo.Workdays`, `Tempo.RRule`, `Tempo.Select.weekdays_in/3`, `Tempo.Builder`, `Tempo.Explain`; the census's oracle numbers a day as the calendar does. `tempo_holidays` numbers its weekdays from Monday and is to follow.

* **Followed through (2026-10-16).** A day of the week of one calendar placed on a value of another is the same day there in `on/2` and `at/2` too, as in `select/3` and `to_calendar/2` (the user: "Same day everywhere"); a month and a day are the other's units, as written. `Tempo.selection/2` builds a selection in a calendar (`[u-ca=hebrew]`), and the builders take a day by its name, numbered in the expression's calendar.

## 81. The weeks of a rule in another calendar

* **Question.** A rule with `RSCALE` (RFC 7529) and `BYWEEKNO`: are its weeks the calendar's own, or RFC 5545's (weeks from `WKST`, Monday by default, week 1 the first with four days) counted over that calendar's year?

* **Context.** `FREQ=YEARLY;RSCALE=HEBREW;BYWEEKNO=10;BYDAY=MO` is 9 November 2026 in Tempo, the Monday of the Hebrew calendar's own week 10 of 5787; RFC 5545's rule over the Hebrew year would give 16 November. Calendrical's `date_from_week_date/3` answers the second, and its documentation calls that the weeks RFC 7529 counts.

* **Decision (2026-10-16).** Follow RFC 7529 consistently: a rule's weeks are its calendar's weeks, as its day of the week is its calendar's day of the week (decision 80). Tempo's reading stands.

* **State.** Built: nothing changes in Tempo.

## 82. The time zone database Tempo asks, as public API

* **Question.** Decision 77 made Tempo ask `tz` where the application configures no time zone database, or only Elixir's UTC-only default. `tempo_holidays` held its own copy of the rule Tempo's README had given before, Tempo's setting else Elixir's, and refused to start under Elixir's default, so after decision 77 it refused a configuration Tempo reads. How does a companion learn the database Tempo asks?

* **Context.** The options were (1) a public `Tempo.time_zone_database/0` that returns it, the companion calling it and refusing only a database that knows only UTC; (2) each companion repeating decision 77's rule in its own code, which drifts as the first copy did; (3) the companion calling the hidden `Tempo.Zone.database/0`, an engine module no companion is agreed to call (decision 15 allows `tempo_network` the calendar adapter alone).

* **Decision (2026-10-18).** Option 1.

* **State.** Built: `Tempo.time_zone_database/0` in the Frames section of `Tempo`, documented with an example and returning `Tempo.Zone.database/0`, held in `zone_database_test.exs` under each source of the database (Tempo's setting, Elixir's default, none). `tempo_holidays` reads it for its start-up check and for its evening day-start, and refuses to start only where it is `Calendar.UTCOnlyTimeZoneDatabase`, which is now only where an application names that database for Tempo.

## 83. How long a quiet rule is walked

* **Question.** A rule that selects nothing for a while is ended once it has been quiet for a cycle of its calendar's years (400 Gregorian, 28 Julian, 210 Islamic civil, a thousand years in a calendar with no cycle). Is one cycle enough?

* **Context.** Not when the rule repeats by an interval its calendar's cycle does not divide. `FREQ=MONTHLY;INTERVAL=7;BYMONTH=2;BYMONTHDAY=29;BYDAY=FR` from March 2025 selects in every seventh month, and 4,800 months to a Gregorian cycle is no multiple of seven, so each cycle selects in other months than the last: Tempo answered that it never occurs, where it occurs on 29 February 2504. Six of 56 such rules and starts were answered wrongly against `Tempo.RRuleMeasure`, every one with an interval of seven months or seven years. The options were (1) walking until the rule's periods and the cycle come round together, the cycle times `n / gcd(n, u)` for an interval of `n` and `u` of its units to a cycle, counted from the calendar; (2) `n` cycles for every interval, as right but `n` times as long where one cycle is enough (a quarterly rule, three months to a cycle of 4,800); (3) one cycle, documented as a limit.

* **Decision (2026-10-25).** Option 1. A calendar with no cycle is walked its thousand years `n` times over. A rule that names times of day alone, walked two years for a zone's changes, is walked `n / gcd(n, u)` times as long for an interval of a clock unit, with `u` of them to a day.

* **State.** Built: `horizon/1` in `Tempo.Recurrence` counts the interval's units to a cycle from the calendar (`months_in_year_bounds/1` where every year has as many months, the days between two first days of a year a cycle apart, `days_in_week/1`), and walks the units it cannot count `n` cycles. The six rules and starts answer as the measure does, held in `rrule_test.exs`.

## 84. A quiet rule's look-ahead, in the units an interval selects in

* **Question.** A quiet rule looks ahead to where its parts next name a value and steps to that period. Where the value lies outside the first unit of a repeating interval, the unit RFC 5545's `INTERVAL` selects in, the step finds nothing and the rule looks ahead again from the next period, so a rule that never occurs visits every period of its horizon: about a second in the Gregorian calendar for `FREQ=MONTHLY;INTERVAL=3;BYMONTH=3,9;BYDAY=SA,SU` from January, and 94 seconds in the Persian calendar, whose every date costs about 30 µs. Should the look-ahead pass such values over?

* **Context.** Rules whose parts name nothing in the horizon already end in one look-ahead, in 16 to 60 ms. Decision 83 lengthens the horizon for some intervals, and with it the walk.

* **Decision (2026-10-25).** The look-ahead names only a value in the first unit of its period's interval, so a quiet stretch is passed in one look-ahead.

* **State.** Built: `first_selectable/3` passes over a named value outside its period's first unit, read from the units the value is written in where they are the period's own. The search carries its place among the periods from one year to the next, each period placed once from the start the one before carried, and reckons a value more than five periods on (`@periods_stepped_to`). A never-occurring quarterly rule takes 61 ms (306 before), every second month 79 ms (508), Islamic civil 78 ms (581), Julian 12 ms (84); with weekends named, 175 ms (1,000), of which 146 ms is finding the weekends. Persian, a horizon of 3,000 years at about 5 ms a year, takes 15 s (94).

## 85. A written end read as it is said

* **Question.** Law 9 reads an end written to a calendar unit through (`2026/2028` is three years) and one written to a clock unit as a boundary (`T09/T17` is eight hours, ending as five begins). A value written to a clock unit is the unit it names (`T14H` alone is the hour from 14:00), so as an end the hour counts as an instant where the year counts whole. Should every end be read the same way?

* **Context.** Found by the user on 2026-10-26, after 2.0.0 was published. The options were (1) keep law 9, each end read as it is said aloud; (2) every end read through, the clock's as the calendar's; (3) every end a boundary, as in 1.6. Option 2 was built and then withdrawn the same day: nine to five became `T09/T16`, which nobody says. ISO 8601 does not decide it. Part 1 defines an interval by two instants, both included unless otherwise stated, and gives no rule for an end of reduced precision. Part 2 reads date ends through in its grouped units (the first half of 2018 is `2018-01-01/2018-06-30`, and `2018Y9M25D/P8D` is `2018Y9M25D/2018Y10M2D`) and as boundaries in its repeat rules (a one-day occurrence is `2018-08-08/2018-08-09`). Every clock end in either part is a boundary.

* **Decision (2026-10-26).** Option 1, law 9 as published: dates through, times of day as boundaries. It is how each is said and the reading most of the standard's examples take. The two changes made while option 2 was built stay: the writer writes an end with a time of day from its hour (`2026Y1M5DT9H15M/T9H30M`, where 1.6 and the first 2.0.0 wrote `/T30M`), and a fraction of a second is truncated to its precision (`Scale.clock_at/2`).

* **State.** Option 2 reverted in Tempo, 2026-10-26; the writer and the truncation kept, their tests, the CHANGELOG and the migration guide updated. The companions are unchanged.
