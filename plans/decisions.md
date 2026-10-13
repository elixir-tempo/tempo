# Decisions of the redesign

The questions put to the user while Tempo 2.0 was built, each with its context, the options and the answer given. It is the record the release documentation is written from: `TODO.md` tracks what is left to build, and this file says why a thing is as it is. A decision is added here when it is made, with its number, and is never rewritten; one that is later changed gets a new entry that names the one it replaces.

Each entry has the same parts: the question, the context it arose in (with what the code did at the time), the options, the decision and its date, and its state (built, or to build).

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

* **State.** To build. How a week start sits beside the one-calendar rule is decision 14.

## 14. Where a week start lives

* **Question.** RFC 5545's `WKST=SU` asks for weeks counted from Sunday; where does a week start live, when an expression's weeks are its calendar's and an expression has one calendar?

* **Context.** BCP 47 has a key for the first day of the week, `fw`, and the reader already carried it as a suffix tag that changed nothing: `Tempo.from_iso8601("R/2026-06-15/P2W[u-fw=sun]")` was `~o"R/2026Y6M15D/P2W[u-fw=sun]"`, the tag kept in the metadata. The options: (1) a property of the whole expression, written `[u-fw=sun]` once at its end, as the calendar and the zone are; (2) a part of the rule alone, which ISO 8601 has no way to write; (3) a calendar of Sunday weeks, a second calendar module with no IXDTF name.

* **Decision (2026-10-14).** Option 1. The week start is of the whole expression: its weekly cadence, its week numbers and its days of the week. `WKST` reads to it and is written from it. It follows that `2026-W25[u-fw=sun]` is a week that begins on Sunday with its days counted from Sunday, where the text was read as the Monday week with a tag.

* **State.** To build, with decision 13.

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

* **State.** To build, with decisions 13 and 14.

## 25. The order of two seasons of 21 to 24 in an interval

* **Question.** Is an interval of two seasons of 21 to 24 held to the order of their numbers as it is read? It is the question decision 22 left open.

* **Context.** Autumn (March to May) comes before spring (September to November) south of the equator, so `2026-23/2026-21` is March to November in Australia and runs backwards in Britain. The October design read such an interval "whatever the order of its seasons" and held it to its order once it had a hemisphere. EDTF's corpus, which the reader is held to, lists `2012-24/2012-21` and `2012-23/2012-22` as invalid. As built with decision 19, the reader kept the numbers' order: `Tempo.from_iso8601("2026-23/2026-21")` was a `Tempo.IntervalEndpointsError`, and so was `Tempo.in_territory(~o"2026-21/2026-23", :AU)`, rightly, spring to autumn of one year running backwards there. The options: (1) keep EDTF's order, a southern interval being written as months; (2) October's reading, any order read and the order held to only with a territory, two corpus cases becoming recorded departures; (3) any order read only where a territory is named as the text is read, the bare text staying an error.

* **Decision (2026-10-14).** Option 3.

* **State.** Built: with `:territory` or `:locale`, `Tempo.from_iso8601/2` and `Tempo.parse/2` give each season its months before the order of the ends is held to. `Tempo.from_iso8601("2026-23/2026-21", territory: :AU)` is `~o"2026Y3M/11M"`; the same text with no territory, and the `~o` sigil, which has none, are errors as in EDTF. `test/tempo/season_test.exs`.
