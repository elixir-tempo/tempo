# Public surface

**Status:** in progress, 2026-10-12

Tempo's primary API is construction, enumeration, selection, set operations and networks, and those need a clear and open public surface. Everything else the library exports is to be evaluated: whether it should be public at all (the user, 2026-10-11: "As you go through these functions, evaluate if they should really be public functions. … Everything else needs careful evaluation as to what the public API surface should be."). This document is that evaluation. It rests on a census of every exported function, [public-surface-census.md](public-surface-census.md), written by `zsh scripts/public_surface/run.sh`.

It goes with [calendar-surface.md](calendar-surface.md), "The border": the public functions are the ones that replace `Calendar.ISO`, which a caller holds, by the module Tempo works with, and back. What is public decides which functions do, so the two are settled together.

The counts below are of the library as it stood before the decisions, on 2026-10-11; "Decisions" and "As built" say what changed, and the census itself is regenerated from the code.

## What was measured

* **What is exported** — every function and macro of every module under `lib/`, from each module's documentation chunk, with how its module and it are documented.

* **Who calls it** — every call the compiler sees, recorded by a compile tracer as the library and then the test files compile: calls from its own module, from other modules of the library, and from tests (doctests among them). A call made through `apply/3` is not seen; a callback (`message/1`, a protocol's functions, a struct's) is counted as a callback and not as dead.

* **Whether a guide names it** — mentions of `Module.function(` or `Module.function/` in `guides/`, the livebooks and the README.

## What is exported

The library exports 38,917 functions and macros. 37,947 are the steps NimbleParsec generates for the combinators one tokenizer module calls of another (`defcombinator`, which makes every step public); they are in hidden modules, no caller names one, and they are set aside. The other 970, in 119 modules:

| Documented as | Functions | Of which |
|---|---|---|
| Documented, in a documented module | 384 | 316 in the API's modules, 68 in the engine's (ExDoc's "Internals" group) |
| `@doc false`, in a documented module | 252 | 160 callbacks (a struct's functions, an exception's, a backend's), 92 others |
| No `@doc`, in a documented module | 27 | all in `Tempo.Iso8601.Tokenizer.Numbers` |
| In a hidden module (`@moduledoc false`) | 307 | 47 callbacks (a protocol's functions among them), 260 others |

## The documented surface, by area

| Area | Functions | Named in a guide | Called by another module |
|---|---|---|---|
| Construction | 55 | 43 | 13 |
| Enumeration | 17 | 13 | 7 |
| Selection | 13 | 9 | 4 |
| Set operations | 31 | 17 | 19 |
| Networks | 38 | 16 | 17 |
| Relations and comparison | 47 | 24 | 18 |
| Lengths | 10 | 5 | 5 |
| Arithmetic | 10 | 5 | 6 |
| Conversion and text | 22 | 16 | 7 |
| Reading a value | 39 | 32 | 17 |
| Zones and leap seconds | 18 | 5 | 11 |
| Workdays | 9 | 9 | 0 |
| The clock | 5 | 0 | 1 |
| The engine, documented | 68 | 3 | 55 |
| Strays | 2 | 0 | 2 |

The first five areas are the primary API: 154 functions. The census lists every function of each area with its counts.

## Evaluation

### The primary API

The 154 functions of construction, enumeration, selection, set operations and networks stay public. Two things in them are not clear and open today:

* **Set operations are documented twice** — `Tempo.union/3` and the twelve others each call a documented `Tempo.Operations` function of the same name. No guide names a `Tempo.Operations` function; the guides name the `Tempo` ones 176 times. `Tempo.Operations.align/3` is the fourteenth, called by tests alone.

* **Selection is documented twice** — `Tempo.select/2` (92 mentions in the guides) calls a documented `Tempo.Select.select/2` (none).

### Functions documented twice

46 documented functions of `Tempo` call a documented function of the same name in another module: 23 in `Tempo.Interval` (the relations, the certainties and the lengths), 13 in `Tempo.Operations`, 3 in `Tempo.IntervalSet`, 2 in `Tempo.Format`, 2 in `Tempo.Compare`, and one each in `Tempo.Select`, `Tempo.Explain` and `Tempo.Clock`. A guide names the second form of four of them (`Tempo.Interval.duration/2`, `Tempo.IntervalSet.duration/1`, `Tempo.Interval.empty?/1`, `Tempo.Explain.explain/1`) and of none of the other 42.

One home each is the clear surface: `Tempo` is where a caller finds an operation on any value, and the struct modules (`Tempo.Interval`, `Tempo.IntervalSet`, `Tempo.Duration`, `Tempo.RecurrenceSet`) are where a value of that kind is built and read. The 42 second forms that no guide names become `@doc false`; the code stays where it is.

### The documented engine

68 documented functions are in the eleven modules `mix.exs` groups as "Internals" and describes as "documented for contributors, but not the API a caller uses": `Tempo.UnitValues` 20, `Tempo.Iso8601.Tokenizer` 10 and `.Extended` 2, `Tempo.Interval.Cycle` 8, `Tempo.Compare` 7, `Tempo.RRule.Rule` 6, `Tempo.RRule.Selection` 4, `Tempo.Interval.Steps` 3, `Tempo.Microsecond` 3, `Tempo.RRule.Expander` 3, `Tempo.Network.Normalize` 2. A guide names 3 of them; other modules call 55.

With the border a documented function is a promise: a caller may call it with the values it holds. Kept documented, each of these crosses the border, and every call the library makes to one pays the border's check: 45.7 million calls of `Tempo.Compare.compare_time/2` and 19.7 million of `Tempo.UnitValues.resolve/2` in one run of the tests. Left documented and outside the border, a documented function fails for a caller's value. Hidden (`@moduledoc false`, the prose kept as comments), they are the engine and nothing more, and the 80 test modules that call the engine directly give it values as it holds them.

### The rest of the documented surface

About 160 functions outside the primary API and outside the two groups above: relations and comparison, lengths, arithmetic, conversion and text, reading a value, zones, workdays and the clock. The guides are built on them (a guide names 96), and the documentation style asks for them: an example reads as prose because `Tempo.at_least?/2` and `Tempo.within?/2` exist. They stay, with these exceptions, each documented and used by the library alone or by a test alone:

* **`Tempo.TimeZoneDatabase`** — 7 of its 9 functions are how the engine reads the zone database (`period_at_utc/2`, `period_at_wall/2`, `total_offset/1`, `changes/3`, `change_within?/3`, `clear_of_changes?/3`, `days_left_out/1`). `database/0` and `zone_exists?/1` are what a caller configures and asks.

* **`Tempo.validate_zone_offset/1`** — a check the parser makes, documented on `Tempo`, in no guide.

* **`Tempo.Clock.utc_now/0`** — the library's own reading of the configured clock, called by `Tempo` alone; `Tempo.utc_now/0` is the public one.

* **`Tempo.Interval.next_unit_boundary/1`** and **`Tempo.ZoneOffsetMismatchError.format_offset/1`** — called by the library alone.

### Exported and not documented

* **Only its own module calls it** — 60 functions (34 in the tokenizer's grammar, 9 in the parser) are exported and called by nothing but their own module. They become `defp`.

* **No caller at all** — 6 functions that are no callback: `Tempo.Iso8601.AST.build_duration/1`, `Tempo.Iso8601.Tokenizer.Grammar.explicit_week_date/0`, `Tempo.Iso8601.Tokenizer.Helpers.day_of_week/0`, `Tempo.Qualification.units/0`, and the three-argument `positive_integer_or_integer_set/3` and `positive_number_or_integer_set/3` of `Tempo.Iso8601.Tokenizer.Numbers`. They are removed.

* **No `@doc`** — 27 functions of `Tempo.Iso8601.Tokenizer.Numbers`, a documented module, have none: ExDoc lists them bare. They are combinators of the grammar and take `@doc false`, or the module is hidden with the rest of the engine.

* **The engine in public modules** — 84 `@doc false` functions of documented modules are called by other modules of the library (`Tempo.week_based_calendar?/1` by 37 places, `Tempo.Compare.order/2` by 18). They are no part of the surface and need no change for it; a hidden module is the better home for each when its code is next worked on.

## What the border needs of it

* **Documented means it takes a caller's value** — a documented function that asks a calendar anything takes a value in `Calendar.ISO` and answers in it, by a first clause or by asking `Tempo.Calendars.outside?/1` of its arguments ([calendar-surface.md](calendar-surface.md), "As built"). A function that is not documented does not: it is given values as Tempo works with them.

* **The library calls its own API with a calendar in hand** — a documented function called from inside is given values that hold the inside calendar, which its first clause does not match. One that makes a value from arguments that hold no calendar (`Tempo.from_iso8601/2`, `Tempo.utc_now/0`) is the caller's and always answers as a caller holds a value, and the library has its own readers.

* **A date from another library is made a date of a calendar Tempo holds where it arrives** — the clock's, the zone database's, the `ical` library's, a resolver's.

## Decisions

The user, 2026-10-11, each asked with the census in hand:

* **The names of the second forms go** — "Remove the names": a 1.x call of a function that is no longer documented fails by name, where it failed inside the engine. Asked again on 2026-10-12, once the way first decided for it was withdrawn: "Fail at compile time".

* **A message says of a term what a caller holds** — "Every message site": `Tempo.Calendars.inspect/2` at every call of `inspect/1,2` in the library.

* **A hidden module behind each documented one, withdrawn** — "Hidden module per public one" was decided on 2026-10-11, built, and withdrawn by the user on 2026-10-12: "I'm very unconfortable that our primary public API is just `defdelegates`. This makes it very hard for someone reading our code to navigate. … I would expect the basic function body to be in the same module as the documentation." A documented function's body stays in the module that documents it, and its clause for a caller's value is written there.

* **Tempo is the home** — `@doc false` for the 42 second forms no guide names, and for the 11 functions the library alone calls.

* **The engine is hidden** — the eleven modules take `@moduledoc false`, their prose kept as comments and their function docs kept for whoever works on them. They take values as Tempo works with them, and the tests that call them give them such values.

## As built

* **The whole doc is on `Tempo`** — the docs of 30 functions of `Tempo` named the second form for their detail ("See `Tempo.Operations.union/3`"). Each now carries it: the arguments, the options (`:within`, `:metadata`), what is returned and what is raised, and the examples of both forms. Their keyword list is named `options`.

* **`Tempo.Select` and `Tempo.Format` stay documented, with no documented function** — the module doc of the one is the selector vocabulary and of the other the rule a value is rendered by, and `Tempo.select/2` and `Tempo.to_string/2` point at them. `Tempo.Operations` is hidden: its module doc pointed at `Tempo`, and `guides/set-operations.md` is the guide.

* **A public name for a part of a second** — `t:Tempo.microsecond/0`, which `t:Tempo.t/0` and `t:Tempo.Duration.t/0` hold, where they named a type of a hidden module.

* **The engine's tests** — `Tempo.Test.Engine.<Module>` is a module of the engine as a test calls it, its arguments given `Tempo.Calendars.inside/1` and its answer `outside/1`, and `Tempo.Test.Inside` a sigil for a value as the engine holds it. The engine's doctests run in `test/tempo/engine_doctest_test.exs`.

* **No doc names what is hidden** — `mix docs` warned of 43 references to a hidden function, module or type after the decisions, and of none now.

* **The surface now** — of 902 exported functions that NimbleParsec did not generate, 265 are documented (384 before), 139 of them the primary API; 234 are `@doc false` in a documented module (160 callbacks), 403 in a hidden module, and none is without a `@doc`. None is called by its own module alone, and none by nothing. None of the 53 names that were documented and are not is exported any longer. A documented function takes a caller's value by the guard `Tempo.Calendars.is_outside/1` (57 places) or by asking `Tempo.Calendars.outside?/1` (70). No documented function is called by the library alone, and none is in the engine.

## Tasks

### Done

* [x] **Exports only their own module calls, and dead exports** — 60 functions are private (the tokenizer's six entry parsers by `defparsecp`), 10 are removed (the 6 with no caller, and `parse_time/1`, `parse_datetime/1` and `parse_interval/1` of the parser and `Tempo.UnitValues.whole_years/1`, which only called themselves), and 3 stay exported: `Tempo.Compare.start_point/1`, `Tempo.RRule.Expander.from_ical_recurrence/1` and `Tempo.Iso8601.Parser.parse_date/1`, which tests call through the tests' proxies of the engine. The census had counted neither those calls nor a function's call of itself apart, and counts both rightly now: none is left in either column. 2026-10-12.

* [x] **The names of the second forms are gone** — the user, 2026-10-12, asked again with what a 1.x caller gets today (`Tempo.Interval.at_least?/2` raised `UndefinedFunctionError` for `Calendar.ISO.calendar_base/0` from inside, where `Tempo.Interval.before?/2` happened to answer): "Fail at compile time". Each of the 53 is renamed where it is defined, to `do_<name>` (the prefix is mine), its body staying where it was: 22 on `Tempo.Interval`, 14 on `Tempo.Operations`, 7 on `Tempo.TimeZoneDatabase`, 2 each on `Tempo.Format`, `Tempo.IntervalSet` and `Tempo.Compare`, and `Tempo.Select.select/2`, `Tempo.Clock.utc_now/0` and `Tempo.ZoneOffsetMismatchError.format_offset/1`; `Tempo.validate_zone_offset/1`, a delegate nothing called, is removed. 48 of the 53 were documented in 1.6.4, and the migration guide maps each or says it has no replacement. A test that called an old name with a function of the same name on `Tempo` calls that one. 2026-10-12.

* [x] **`Tempo.Iso8601.Tokenizer.Numbers`** — hidden with the engine, so its 27 combinators are no longer listed bare. 2026-10-11.

* [x] **The five exceptions among the rest** — `@doc false` for 7 functions of `Tempo.TimeZoneDatabase`, `Tempo.validate_zone_offset/1`, `Tempo.Clock.utc_now/0`, `Tempo.Interval.next_unit_boundary/1` and `Tempo.ZoneOffsetMismatchError.format_offset/1`. 2026-10-11.

* [x] **The documented engine** — hidden, eleven modules and `Tempo.Operations`. 2026-10-11.

* [x] **One home for each function documented twice** — `@doc false` for the 42 second forms no guide names, and the whole doc on `Tempo`. 2026-10-11.
