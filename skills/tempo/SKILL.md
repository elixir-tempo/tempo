---
name: tempo
description: >-
  Map a natural-language date, time, interval, recurrence, or scheduling problem
  to the Tempo Elixir library — choose the right representation (ISO 8601 /
  ISO 8601-2 / IXDTF via the `~o` sigil), pick the right operation (Allen
  relations, graded/uncertain relations, set algebra, enumeration, recurrence,
  workdays), validate it, run it, and
  explain the result in plain language. Use whenever someone describes a
  temporal problem in prose — "do these overlap?", "when does each task run?",
  "which reigns could be contemporary?", "the second Monday of every month",
  "circa 600 BCE" — and wants to represent or solve it with Tempo. Serves both
  developers (who want correct Tempo code) and researchers/historians (who want
  answers).
---

# Tempo: from an English time problem to a solved one

Tempo treats **every date/time value as a span of time** at a declared resolution, never an instant. `2026` *is* the whole year; `2026-06-15` is one day. Underneath, a span is half-open, `[from, to)`. An interval is read as it is said: `2026-06-15/2026-06-20` runs **through** the 20th (six days), and `T09/T17` ends as five o'clock begins (eight hours). Partial and uncertain values are first-class, so you never hand-roll validity checks. One struct, `%Tempo{}`, holds every expression: a value, an interval, a recurrence, a set.

The hard part for a user is not the concept — it's (a) ISO 8601-2's obtuse syntax and (b) knowing *which layer* solves their problem. This skill's job is to bridge both.

## The workflow (always follow this loop)

1. **Understand** the problem and restate it as a sentence with nouns (the values) and verbs (the operation).
2. **Represent** each input as a Tempo value — usually the `~o"…"` sigil. **Never present a `~o` string you have not validated** (see Grounding).
3. **Route** to the right layer using the decision table below.
4. **Execute** the pipeline and get a real result.
5. **Explain** the result back in the user's language. For a developer, show the pipeline (in the pipeline-prose style). For a researcher, lead with the plain-language answer and keep the code available but secondary.

## Grounding — never guess at obtuse syntax

ISO 8601-2 is easy to get subtly wrong (`2004-06~-11` vs `2004-?06-11` mean different things). So:

* **Validate every representation.** In a project with Tempo available, run it: `Tempo.from_iso8601("2004-06~-11")` returns `{:ok, value}` or `{:error, exception}`, whose message says where the reading stopped and why — use that error to self-correct. `~o"…"` is the compile-time sigil; `from_iso8601/1` is the runtime, error-returning form for anything user-derived.
* **Confirm the meaning** with `Tempo.explain/1`, which renders a value as prose. Echo it back — *"`~o"1200±60Y"` means: the year 1200, give or take 60"* — so the user can confirm you understood before you build on it.
* If a Tempo MCP is connected, its `parse`/`explain` tools do this without a project checkout; prefer them for validation.
* Library code must never crash on bad input — use `from_iso8601/1` (not the `!` bang) and `case` on the result for anything derived from user/LLM text.

See `iso8601-cheatsheet.md` for the syntax forms, each with the English it encodes.

## Decision procedure — problem shape → layer → functions

| The user is asking… | Layer | Reach for |
|---|---|---|
| "what does this string mean / is it valid?" | **Parse + Explain** | `Tempo.from_iso8601/1`, `Tempo.explain/1` |
| "does A overlap / meet / come before / fall within B?" | **Relations** | `Tempo.relation/2` (which of the 13 Allen relations); everyday predicates `overlaps?/2`, `within?/2`, `contains?/2`, `disjoint?/2`, `adjacent?/2`, `before?/2`, `after?/2`, `equal?/2`; Allen's own under their names in `Tempo.Allen` (`meets?/2`, `during?/2`, …) |
| "…but the dates are uncertain / circa / ±" | **Graded relations** | `Tempo.certainty(predicate, a, b)` → `:certain \| :possible \| :impossible`; booleans `Tempo.certainly?/3` and `possibly?/3`. The predicate is any everyday one (`:before`, `:after`, `:overlaps`, `:within`, `:contains`, `:adjacent`, `:disjoint`) or an Allen relation (`:precedes`, `:during`, …) |
| "free/busy, subtract, merge, or split into bookable slots" | **Set algebra** | `Tempo.difference/3`, `intersection/3`, `union/3`, `complement/2` (each `{:ok, set}`); `Tempo.IntervalSet.members/1`, `coalesce/2`, `covered/2` (the double-booked time with `at_least: 2`), `slots/3`, `count/1` |
| "how long is it / is it at least an hour?" | **Duration predicates** | `Tempo.at_least?/2`, `at_most?/2`, `exactly?/2`, `longer_than?/2`, `shorter_than?/2` on an interval, the span a value names or the time a set covers; `Tempo.duration/1`; `adjacent?/2` |
| "N business days later / the next school day / workdays in a month" | **Workdays** | `Tempo.workdays(territory, except: holidays)` (a territory's weekend plus your holidays), then `add_workdays/3`, `next_workday/2`, `previous_workday/2`, `nearest_workday/2`, `roll_to_workday/3`, `count_workdays/2`, `workday?/2`; `Tempo.select(span, workdays)` lists them |
| "every Nth weekday / recurring events / occurrences of a rule" | **Recurrence** | `Tempo.RRule.parse!/2` or `Tempo.Cron.parse!/2` (RFC 5545 / cron text → a recurrence), or the native `~o"R/…/FL…N"` selection they compile to; `Tempo.to_interval(rule, within: window)` for its occurrences; `Tempo.RRule.to_string/1` to write one back |
| "list the days/months/hours within a span" | **Enumeration** | `Enum.to_list/1` / `Enum.take/2` on a value (a month gives its days; a set or a recurrence gives its members); `Tempo.walk(span, :hour)` to walk at a chosen unit; `Tempo.members/1` for the spans of anything |
| "N years later / shift by a duration" | **Arithmetic** | `Tempo.shift/3` (takes a `~o"P…"` duration or `day: 1`; returns `{:ok, value}`), `Tempo.trunc/2`, `Tempo.round/2`, `Tempo.duration/1,2` |
| "convert to/from Elixir `Date`/`DateTime`" | **Interop** | `Tempo.from_elixir/2`, `Tempo.to_elixir/1`, `Tempo.to_date/1`, `Tempo.to_datetime/1`; `Tempo.in_zone/2`, `Tempo.shift_zone/2` |

Choosing between adjacent layers:

* **Relations vs set algebra** — relations answer a yes/no or which-of-13 question about *two* intervals; set algebra *produces new* intervals (the free gap, the overlap, the merged span). "Do they clash?" → `overlaps?`. "When is everyone free?" → `difference`/`intersection`.
* **Crisp vs graded** — if any input carries a `±` margin, a qualifier or a mask, or the user says "circa/around/roughly", use `Tempo.certainty/3` and its two booleans; they agree with the plain predicates when the inputs are crisp, so they are always safe.
* **Floating vs zoned** — a value with no zone is a reading of a clock in no place; one with a zone is a moment. Tempo refuses to relate or combine the two (`Tempo.FrameError`). Place the floating one with `Tempo.in_zone/2` first.
* **Dependency scheduling and constraint networks** — tasks with durations and finish-to-start links, and relative, possibly undated constraints ("which reign overlaps which stratum"), are in the companion package `tempo_network` (`Tempo.Schedule`, `Tempo.Network`). Free-gap placement ("drop this into the first opening") is a set-algebra job in Tempo itself.

## Results are tuples

A function that can fail returns `{:ok, value}` or `{:error, exception}`, and its `!` form returns the value or raises: `Tempo.shift/3` and `shift!/3`, `Tempo.to_interval/2` and `to_interval!/2`, `Tempo.union/3` and `union!/2`. Predicates, `Tempo.relation/2`, `Tempo.duration/1` and `Enum` return a bare value. An option a function does not take is an error, so a misspelt `within:` is caught.

## The pipeline-prose idiom (how to present code)

Tempo code should read aloud as a sentence a product manager — or a historian — would say. Structure examples in three parts: **named bindings** (the nouns), a **pipeline of set-algebra + predicate verbs** (the sentence), and a **prose translation** (the human reading). If a snippet can't be read as plain English, a predicate is probably missing — prefer the named helper (`at_least?`, `within?`, `certainly?`) over a hand-rolled endpoint comparison. `recipes.md` holds worked templates in exactly this shape.

## Reference material (load as needed)

* `iso8601-cheatsheet.md` — every ISO 8601 / ISO 8601-2 / IXDTF form with its plain-English meaning (the obtuse bits: `?`/`~`/`%` qualifiers and their positions, masks, sets with `..` ranges, `±` margins, significant digits, recurrence, IXDTF `[zone]`/`[u-ca=]`/`!`).
* `recipes.md` — English-problem → Tempo-pipeline templates for each layer, as few-shot examples.
* The library's own guides (in `guides/`) go deeper: `when-to-use-tempo.md`, `set-operations.md`, `uncertain-dates.md`, `scheduling.md`, `workdays-and-weekends.md`, `iso8601-grammar.md`, `iso8601-conformance.md`, `enumeration-semantics.md`, `ical-integration.md`, and `migration.md` for code written against Tempo 1. Point developers there for detail.
