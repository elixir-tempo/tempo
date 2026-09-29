---
name: tempo
description: >-
  Map a natural-language date, time, interval, recurrence, or scheduling problem
  to the Tempo Elixir library — choose the right representation (ISO 8601 /
  ISO 8601-2 / IXDTF via the `~o` sigil), pick the right operation (Allen
  relations, graded/uncertain relations, set algebra, enumeration, recurrence,
  dependency scheduling, or constraint networks), validate it, run it, and
  explain the result in plain language. Use whenever someone describes a
  temporal problem in prose — "do these overlap?", "when does each task run?",
  "which reigns could be contemporary?", "the second Monday of every month",
  "circa 600 BCE" — and wants to represent or solve it with Tempo. Serves both
  developers (who want correct Tempo code) and researchers/historians (who want
  answers).
---

# Tempo: from an English time problem to a solved one

Tempo treats **every date/time value as a bounded, half-open interval** `[from, to)` at a declared resolution — never an instant. `2026` *is* the whole year `2026-01-01 .. 2027-01-01`; `2026-06-15` is one day. Partial and uncertain values are first-class, so you never hand-roll validity checks. On top of that interval core sit layers: enumeration, set algebra, Allen relations (crisp and graded-under-uncertainty), recurrence, dependency scheduling, and constraint networks.

The hard part for a user is not the concept — it's (a) ISO 8601-2's obtuse syntax and (b) knowing *which layer* solves their problem. This skill's job is to bridge both.

## The workflow (always follow this loop)

1. **Understand** the problem and restate it as a sentence with nouns (the values) and verbs (the operation).
2. **Represent** each input as a Tempo value — usually the `~o"…"` sigil. **Never present a `~o` string you have not validated** (see Grounding).
3. **Route** to the right layer using the decision table below.
4. **Execute** the pipeline and get a real result.
5. **Explain** the result back in the user's language. For a developer, show the pipeline (in the pipeline-prose style). For a researcher, lead with the plain-language answer and keep the code available but secondary.

## Grounding — never guess at obtuse syntax

ISO 8601-2 is easy to get subtly wrong (`2004-06~-11` vs `2004-?06-11` mean different things). So:

* **Validate every representation.** In a project with Tempo available, run it: `Tempo.from_iso8601("2004-06~-11")` returns `{:ok, value}` or a precise `{:error, reason}` that names the bad component — use that error to self-correct. `~o"…"` is the compile-time sigil; `from_iso8601/1` is the runtime, error-returning form for anything user-derived.
* **Confirm the meaning** with `Tempo.explain/1`, which renders a value as prose. Echo it back — *"`~o"1200±60Y"` means: the year 1200, give or take 60"* — so the user can confirm you understood before you build on it.
* If a Tempo MCP is connected, its `parse`/`explain` tools do this without a project checkout; prefer them for validation.
* Library code must never crash on bad input — use `from_iso8601/1` (not the `!` bang) and `case` on the result for anything derived from user/LLM text.

See `iso8601-cheatsheet.md` for the syntax forms, each with the English it encodes.

## Decision procedure — problem shape → layer → functions

| The user is asking… | Layer | Reach for |
|---|---|---|
| "what does this string mean / is it valid?" | **Parse + Explain** | `Tempo.from_iso8601/1`, `Tempo.explain/1` |
| "does A overlap / meet / come before / fall within B?" | **Relations** | `Tempo.relation/2` (the 13 Allen relations); predicates `overlaps?/2`, `within?/2`, `contains?/2`, `disjoint?/2`, `before?/2`, `after?/2` |
| "…but the dates are uncertain / circa / ±" | **Graded relations** | `overlap_certainty/2`, `within_certainty/2`, `relation_certainty/3` → `:certain \| :possible \| :impossible`; booleans `certainly_overlaps?/2`, `possibly_overlaps?/2`, and the `*_before?`/`*_after?`/`*_within?` pairs |
| "free/busy, subtract, merge, or split into bookable slots" | **Set algebra** | `Tempo.difference/2`, `intersection/2`, `union/2`; `Tempo.IntervalSet.members/1`, `coalesce/1`, `covered/2` (the double-booked time with `at_least: 2`), `slots/3`, `count/1` |
| "how long is it / is it at least an hour?" | **Duration predicates** | `Tempo.Interval.at_least?/2`, `at_most?/2`, `exactly?/2`, `longer_than?/2`, `shorter_than?/2`, `adjacent?/2` |
| "every Nth weekday / recurring events / occurrences of a rule" | **Recurrence** | `Tempo.RRule.parse!/2` or `Tempo.Cron.parse!/2` (RFC 5545 / cron string → a recurring `%Tempo.Interval{}`), the native `~o"R/…/FL…N"` selection they compile to, or `Tempo.Interval.new!(from:, duration:, recurrence: :infinity)` for a simple period; convert to its occurrences with `Tempo.to_interval(value, within: …)` |
| "list the days/months/hours within a span" | **Enumeration** | `Enum.to_list/1` / `Enum.take/2` on a value; `Tempo.to_interval/1` for the implicit span |
| "order these dependent tasks; when does each run; critical path; deadline" | **Scheduling** | `Tempo.Schedule.new/0 \|> task/3 \|> solve/1`; then `critical_path/1`, `span/1`; each slot has `.start`/`.finish`/`.critical?` |
| "given uncertain/relative constraints, are they consistent, could two have coexisted, and what do they imply?" | **Constraint network** | `Tempo.Network.new/0 \|> add_period/3 \|> add_sequence/2 \|> add_relation/4`; solve with `Tempo.Network.Solver.consistent?/1`, `Tempo.Network.Solver.contemporaneity/3` (could two periods overlap — `:certain` / `:possible` / `:impossible`), and `Tempo.Network.Solver.tighten/1` (derives narrowest bounds, even for undated periods) |
| "N years later / shift by a duration" | **Arithmetic** | `Tempo.shift/2` (takes a `~o"P…"` duration) |
| "convert to/from Elixir `Date`/`DateTime`" | **Interop** | `Tempo.from_elixir/2`, `Tempo.to_date/1`, `Tempo.to_datetime/1` |

Choosing between adjacent layers:

* **Relations vs set algebra** — relations answer a yes/no or which-of-13 question about *two* intervals; set algebra *produces new* intervals (the free gap, the overlap, the merged span). "Do they clash?" → `overlaps?`. "When is everyone free?" → `difference`/`intersection`.
* **Crisp vs graded** — if any input carries a `±` margin or the user says "circa/around/roughly", use the `*_certainty` functions; they degrade exactly to the plain predicates when inputs are crisp, so they are always safe.
* **Scheduling vs network** — `Schedule` is for *dependency* planning (tasks with durations and finish-to-start links, one timeline forward). `Network` is for *relative, possibly-undated* constraints and asking whether they're jointly consistent / what they imply (the historian's "which reign overlaps which stratum"). Scheduling composes by conjunction; free-gap placement ("drop this into the first opening") is a set-algebra job, not scheduling.

## The pipeline-prose idiom (how to present code)

Tempo code should read aloud as a sentence a product manager — or a historian — would say. Structure examples in three parts: **named bindings** (the nouns), a **pipeline of set-algebra + predicate verbs** (the sentence), and a **prose translation** (the human reading). If a snippet can't be read as plain English, a predicate is probably missing — prefer the named helper (`at_least?`, `within?`, `overlap_certainty`) over a hand-rolled endpoint comparison. `recipes.md` holds worked templates in exactly this shape.

## Reference material (load as needed)

* `iso8601-cheatsheet.md` — every ISO 8601 / ISO 8601-2 / IXDTF form with its plain-English meaning (the obtuse bits: `?`/`~`/`%` qualifiers and their positions, masks, sets with `..` ranges, `±` margins, significant digits, recurrence, IXDTF `[zone]`/`[u-ca=]`/`!`).
* `recipes.md` — English-problem → Tempo-pipeline templates for each layer, as few-shot examples.
* The library's own guides (in `guides/`) go deeper: `when-to-use-tempo.md`, `set-operations.md`, `uncertain-dates.md`, `scheduling.md`, `chronological-networks.md`, `iso8601-conformance.md`, `enumeration-semantics.md`, `ical-integration.md`. Point developers there for detail.
