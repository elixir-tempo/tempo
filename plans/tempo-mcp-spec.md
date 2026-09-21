# Tempo MCP — tool schema spec

**Status:** draft, 2026-07-06

Companion to the `tempo` skill. The skill teaches an LLM *how to think* about a time problem and write Tempo; this MCP lets it **execute and ground** — validate representations and run pipelines — with no Elixir project or terminal, so a researcher in a chat client gets real answers.

## Architecture principles

1. **Strings in, strings + prose out.** Every Tempo value round-trips to an ISO 8601 / IXDTF string, so that string *is* the interchange format. Tools accept value strings, operate, and return result strings — plus `Tempo.explain/1` prose. The model chains tools by passing result strings from one into the next (`difference` → `slots`). Stateless, composable, no server-side handles.
2. **Grounding by construction.** Any tool that accepts a value first parses it; on failure it returns a precise `{error, reason}` naming the bad component (never raises). `parse` is the dedicated validate-and-explain primitive the model calls before building anything.
3. **Prose alongside every result.** So the model can narrate the answer in the user's language without re-deriving it.
4. **Descriptions encode routing.** Each tool's description restates *when to use it* (mirroring the skill's decision table), so tool selection works even if the skill isn't loaded.
5. **Never crash.** Library rule #2 applies at the boundary: malformed input → structured error, always.

Values are strings in **sigil-body form** (`"2004-06~-11"`, `"1200±60Y"`, `"2026-06-15T09/2026-06-15T17"`, `"P1W"`). Intervals/durations/sets are just their string forms.

## Tools

### `parse` — validate, canonicalise, and explain a value
The grounding primitive. Call before relying on any representation.
```jsonc
// in
{ "value": "2004-06~-11", "calendar": "gregorian" /* optional */ }
// out
{ "valid": true,
  "canonical": "2004-06~-11",
  "explanation": "June 2004, approximately; the day (11th) is firm.",
  "resolution": "day",
  "from": "2004-06-11", "to": "2004-06-12" }
// out (error)
{ "valid": false, "error": "day 31 is not valid for June (1..30)" }
```

### `explain` — prose for a value
```jsonc
{ "value": "1200±60Y" }
// → { "explanation": "The year 1200, give or take 60 years." }
```

### `relate` — Allen relation + graded certainty
Answers "how do A and B stand in time?" — crisp and, when inputs carry `±`/qualifiers, graded.
```jsonc
// in
{ "a": "1200±60Y", "b": "1240±40Y" }
// out
{ "relation": "precedes",                 // crisp Allen relation of the nominal values
  "overlap": "possible",                   // :certain | :possible | :impossible
  "within": "impossible",
  "before": "possible",
  "explanation": "They might be contemporary; A might precede B; A is not certainly within B." }
```
Optional `"concept"` to ask one thing: `{ "a","b","concept":"before" }` → `{ "certainty":"possible" }`.

### `set` — difference / intersection / union
Produces new intervals: free/busy, overlap, merged span. `a`/`b` accept a string or a list of strings (a list is unioned into a set first).
```jsonc
// in
{ "op": "difference",
  "a": "2026-06-15T09/2026-06-15T17",
  "b": ["2026-06-15T10/2026-06-15T11", "2026-06-15T14/2026-06-15T15"],
  "coalesce": false }
// out
{ "result": ["2026-06-15T09/2026-06-15T10",
             "2026-06-15T11/2026-06-15T14",
             "2026-06-15T15/2026-06-15T17"],
  "count": 3,
  "explanation": "The workday minus the two busy blocks — three free gaps." }
```

### `slots` — cut regions into fixed-length openings (booking)
```jsonc
// in
{ "regions": ["2026-06-15T09/2026-06-15T10", "2026-06-15T11/2026-06-15T14"],
  "duration": "PT1H", "every": "PT30M" /* optional stride */ }
// out
{ "slots": ["2026-06-15T09/2026-06-15T10", "2026-06-15T11/2026-06-15T12", …], "count": 6 }
```

### `occurrences` — enumerate a value or expand a recurrence
Give either a `value` (any enumerable/recurring value) or an `rrule` + `from`. Always bounded (Tempo refuses an unbounded expansion).
```jsonc
// in
{ "rrule": "FREQ=MONTHLY;BYDAY=2MO", "from": "2025-01-01", "bound": "2025" }
//   or: { "value": "2026Y", "bound": "2026", "limit": 12 }
// out
{ "occurrences": ["2025-01-13", "2025-02-10", …], "count": 12,
  "explanation": "The second Monday of each month in 2025." }
```

### `schedule` — dependency scheduling (critical path)
```jsonc
// in
{ "tasks": [
    { "id": "design", "duration": "P2D", "start": "2026-06-01" },
    { "id": "build",  "duration": "P3D", "after": ["design"] },
    { "id": "docs",   "duration": "P1D", "after": ["design"] },
    { "id": "ship",   "duration": "P2D", "after": ["build","docs"], "deadline": "2026-06-08" } ] }
// out
{ "feasible": true,
  "tasks": { "ship": { "start": "2026-06-06", "finish": "2026-06-08", "critical": true },
             "docs": { "start": "2026-06-03", "finish": "2026-06-04", "critical": false }, … },
  "critical_path": ["design","build","ship"],
  "span": "2026-06-01/2026-06-08" }
// out (over-tight deadline or cycle)
{ "feasible": false, "error": "infeasible: ship cannot finish by 2026-06-08" }
```
Task duration may be a range `{"min":"P2D","max":"P4D"}`; bounds via `start` / `earliest` / `deadline` / `within`.

### `network` — relative constraint network (STP), consistency + tightening
For relative, possibly-undated constraints and "is this jointly possible, and what does it pin down?".
```jsonc
// in
{ "periods": [
    { "id": "k1", "start": {"not_before":"1200Y"}, "duration": {"at_most":"P10Y"} },
    { "id": "k2", "end": {"not_after":"1300Y"},   "duration": {"at_least":"P35Y"} },
    { "id": "s1", "duration": {"min":"P20Y","max":"P100Y"} } ],
  "sequences": [["k1","k2"]],
  "relations": [ {"kind":"starts_during","a":"s1","b":"k1"} ] }
// out
{ "consistent": true,
  "periods": { "s1": { "earliest_start":"1200Y", "latest_start":"1260Y",
                        "earliest_end":"1220Y", "latest_end":"1280Y" }, … },
  "explanation": "The constraints are jointly satisfiable; S1 — undated on input — is pinned to 1200–1260." }
// out
{ "consistent": false, "explanation": "No assignment satisfies all constraints (negative cycle: …)." }
```

### `shift` — arithmetic
```jsonc
{ "value": "2018±2Y", "by": "P1Y" }   // → { "result": "2019±2Y", … }
```

## End-to-end (researcher mode, no code shown)

> *"A hearth ~1200±60, a midden ~1240±40, a wall ~1500±20; occupation 1000–1500. Which could be contemporary, and does everything fall in the occupation?"*

Model: `parse` each (grounds the `±` values) → `relate` hearth/midden (`overlap:"possible"`) → `relate` hearth/wall (`before:"certain"`) → `relate` each vs `"1000/1500"` (`within:"certain"`) → answers in prose: *"The hearth and midden might be contemporary; the wall is certainly later; all three certainly fall within the occupation."*

## Implementation notes

* **Elixir MCP server** (Tempo is BEAM) — e.g. Hermes MCP or an equivalent, exposing the tools above. Ship as `mix tempo.mcp` (stdio, for a local dev/Claude Code) and an optional HTTP mode (for hosted/researcher use).
* Each tool is a thin wrapper over the verified public API: `parse`→`from_iso8601/1`+`explain/1`; `relate`→`relation/2`+`overlap_certainty/2`/`relation_certainty/3`; `set`→`difference/2`|`intersection/2`|`union/2`(+`coalesce/1`); `slots`→`IntervalSet.slots/3`; `occurrences`→`RRule.parse!/2`+`to_interval/2` or `Enum`; `schedule`→`Schedule.new/task/solve` + `critical_path`/`span`; `network`→`Network.new/add_period/add_sequence/add_relation` + `Solver.consistent?/1`/`tighten/1`; `shift`→`shift/2`.
* Return `explanation` from `Tempo.explain/1` (and, since Explain/Localize are i18n-aware, honour a `locale` param later for non-English answers).
* Version the tool surface against Tempo's version; regenerate examples from the same verified recipes the skill uses.
