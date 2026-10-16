# Conformance fixtures

These files are the oracles Tempo is tested against, written apart from the library and exported as data, so that an implementation of the same architecture in any language can be held to them. Tempo's own tests read the same files (`test/support/conformance.ex`), and `MIX_ENV=test mix run scripts/conformance_fixtures.exs` writes them again from the oracles, so the files and the oracles cannot drift. The model the fixtures hold an implementation to is the [Architecture](https://hexdocs.pm/ex_tempo/architecture.html) guide.

Every file is JSON. A file that lists many cases writes each case on one line, so that a diff reads case by case. Dates and times are ISO 8601 text; a moment is seconds since 1970-01-01T00:00:00Z; a span on a line of integer points is `[from, to]`, half-open.

## allen.json

* `relations`: the thirteen relations of Allen's interval algebra, each with a pair of half-open spans on a line of integer points that stands in it, `a` to `b`.

* `composition`: the 169 cells of the composition table: given `a first b` and `b second c`, the relations `a` may stand in to `c`, in Allen's order. Derived by placing three spans every way on eight points and classifying each pair by four comparisons of their ends.

## set_operations.json

* `lines`: five points, 0 to 4, on each of five lines, and the text of the span `from/to` on each line: days written through their last day, hours ending as the last begins, the same hours at UTC and on the clock of Europe/Paris, the same days in the Hebrew calendar.

* `pairings`: the lines the two operands of a case are built on, in order: the same line twice, UTC beside Paris both ways, Gregorian beside Hebrew both ways.

* `cases`: every pair of sets of up to two spans between the five points, with the result of each operation as the coalesced spans of the cells it covers: a cell is in a union when a member of either set holds it, in an intersection when a member of each does, in a difference when one of the first does and none of the second, in a symmetric difference when the members of just one do. A union preserves members; its covered cells are what is held here.

* `cycle` and `cycle_cases`: times of day on the day's cycle, four points, with a span from a later hour to an earlier one running through midnight; the result of an intersection and a difference as the hours of the day covered.

## rrule.json

* `cases`: 192 recurrence rules in RFC 5545's text, each from three starts on no clock in particular, with the first twelve occurrences an expander written to RFC 5545 section 3.3.10 gives within two hundred years of the start. Where `complete` is false the rule has fewer than twelve in two hundred years, and an implementation gives these first.

* `example_cases`: the examples of RFC 5545 section 3.8.5.3 as the standard lists them, read from its text: the start on the clock of America/New_York, the rules (some given two ways), the dates an `EXDATE` leaves out, and the occurrences with the abbreviation the standard prints. Where `complete` is false the standard elides.

## clock_changes.json

* `days`: twenty-two days on which a zone's clock changes, chosen for the shape of the change (by half an hour, at a quarter to the hour, at midnight, by two hours, a day left out, two changes an hour apart). For each, the moments the day is shown from and to, and the hours the clock showed: each hour's number and the moments it ran from and to, an hour the clock skips in part as long as the clock shows it, an hour shown in two parts as two entries. Read from the platform's own date and time, minute by minute.

## expressions.json

* `operations`: the operations of the library, by group, as the matrix names them (`shift/2 P1D` is a shift by one day). An operation of two expressions is run with the expression itself (argument `self`), with each partner (the partner's text) and after each partner (the partner's text and a bar).

* `partners`: the texts of the partners.

* `expressions`: every expression of the corpus written by hand (the levels core, extended and open), as ISO 8601 text with the calendar it is read in where one is given, and what it refuses, by answer: each refusal is the operation's name followed, for an operation of two expressions, by an at sign and the argument (`relation/2 @ 2026-06-15`). An answer is `error Name reason` for a named error, `raised Name` for a raise, `unread Name` for text the grammar refuses. Every cell not listed answers with a value. The corpus's generated expressions are Tempo's own and are not here. An implementation of the same laws refuses what this refuses; Tempo's own check against it runs with `mix test --only total`.

## census.json

* `positions` and `parts`: how a position and a value's parts are written. A position here is a count of microseconds from 0000-01-01, as `guides/architecture.md` section 3 has it, and exceeds 2^53, so it is read as a 64-bit integer.

* `calendars`: the census's 27 calendars, each by its module's name and its IXDTF identifier, null for the one with none (the Australian fiscal year). The observational Islamic calendars are not here.

* `forms`: a value in each full form on each of the census's dates in each calendar (a year, a month, a date, a date with a time to the hour, the minute, the second and the tenth, an ordinal date, a time in Europe/Paris, and in a calendar of weeks a week, a week date and its times), with the span it covers and the spans its walk yields, worked out from the calendar's own functions and `Date` and never from Tempo.

* `no_year`: every month with no year, every day of each and one past the last, and every day of the week, with the span each covers on its cycle (or `needs_a_year`, or `no_such_value` for a value no year has) and where each value its walk yields starts, or how many it yields.

* `shapes`: a set, a range, a count from the end, a mask and an unspecified unit, two intervals and three recurrences on the census's first date, with the spans of each member the value converts to and, where the census works it out, where each value its walk yields starts.
