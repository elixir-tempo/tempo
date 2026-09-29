# Recipes — English problem → Tempo pipeline

Few-shot templates, one per layer, in the pipeline-prose shape: **named bindings** (nouns) → **pipeline** (verbs) → **prose translation** (the human reading). Adapt the values; keep the shape. All assume `import Tempo.Sigils`. Validate any `~o"…"` you adapt (see `SKILL.md` → Grounding).

---

### "What does this uncertain date actually mean?" — Parse + Explain

```elixir
Tempo.explain(~o"2004-06~-11")
```

> *"June 2004, approximately, on the 11th — the year and month are the fuzzy part, the day is firm."* Use `explain/1` to confirm you've represented the user's intent before building on it.

---

### "Does the delivery window clash with the holiday?" — Relations

```elixir
delivery = ~o"2026-06-15/2026-06-20"
holiday  = ~o"2026-06-18"

Tempo.overlaps?(delivery, holiday)   #=> true
Tempo.relation(delivery, holiday)    #=> :contains
```

> *"The delivery window **contains** the holiday, so yes — they clash."* `relation/2` gives the precise Allen relation; the `?` predicates give the yes/no.

---

### "When is everyone free for an hour?" — Set algebra

```elixir
work = ~o"2026-06-15T09/2026-06-15T17"
{:ok, busy} = Tempo.union(
  ~o"2026-06-15T10/2026-06-15T11",
  ~o"2026-06-15T14/2026-06-15T15"
)

{:ok, free} = Tempo.difference(work, busy)
bookable =
  free
  |> Tempo.IntervalSet.slots(~o"PT1H")
  |> Tempo.IntervalSet.members()   #=> six one-hour openings
```

> *"Free time is the workday **minus** the busy blocks; **bookable** slots are those gaps cut into one-hour pieces."* `difference`/`intersection`/`union` produce new intervals; `slots/3` discretises a free region into fixed-length openings.

---

### "The second Monday of every month in 2025" — Recurrence

```elixir
rule = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2025-01-01")
Tempo.explain(rule)                 #=> "An unbounded recurrence. … Selects: on the 2nd Monday. …"
{:ok, months} = Tempo.to_interval(rule, within: ~o"2025")
Tempo.IntervalSet.members(months)   #=> the 12 second-Mondays
```

> *"Parse the calendar rule into a recurring interval — `explain/1` reads it back in plain English so you can confirm the pattern — then **convert** it to its occurrences within 2025."* For a simple period (no BY-rules) skip RRULE entirely: `Tempo.Interval.new!(from: dtstart, duration: ~o"P1W", recurrence: :infinity)`. RRULE and `Cron.parse!/2` are convenient front-doors; each compiles to a native ISO 8601 recurring interval — `inspect/1` shows the canonical `~o"R/…/FL…N"` form, which parses straight back.

---

### "The last weekday of every month" — BYSETPOS (`I`)

```elixir
rule = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", from: ~o"2025-01-01")
Tempo.explain(rule)              #=> "… Selects: on a weekday [1..5], keeping the last occurrence. …"
{:ok, days} = Tempo.to_interval(rule, within: ~o"2025")
Tempo.IntervalSet.members(days)  #=> Jan 31, Feb 28, Mar 31, … (last weekday of each month)
```

> *"The last **weekday** of the month — not the last Friday."* `BYSETPOS` is ISO 8601-2's position designator `I`, applied last over the whole resolved set: `~o"R/../P1M/FL{1..5}K-1IN"` ranks each month's Mon–Fri candidates and keeps the last, where `BYDAY=-1FR` (`5K-1I`) would pick the last *Friday*, a different date. For cross-system interchange, write the rule as RFC 5545 with `Tempo.RRule.to_string/1`. See `guides/iso8601-conformance.md` §5.

---

### "List every month in the year" — Enumeration

```elixir
Enum.to_list(~o"2026Y")     #=> [~o"2026Y1M", …, ~o"2026Y12M"]
Enum.take(~o"2026-06", 5)   #=> first five days of June
```

> *"A year value **is** an enumerable sequence of its months; a month, of its days."* Iteration drills to the next-finer unit.

---

### "Could these circa-dated finds be contemporary?" — Graded relations (uncertainty)

```elixir
hearth = ~o"1200±60Y"
midden = ~o"1240±40Y"
wall   = ~o"1500±20Y"

Tempo.possibly_overlaps?(hearth, midden)               #=> true
Tempo.certainly_overlaps?(hearth, midden)              #=> false
Tempo.relation_certainty(hearth, wall, :precedes)      #=> :certain
```

> *"The hearth and midden **might** be contemporary but we can't be sure; the hearth is **certainly** earlier than the wall."* The `*_certainty` functions read `±` margins and answer three-valued; they collapse to the plain predicates on crisp dates.

---

### "Order these dependent tasks and find the critical path" — Scheduling

```elixir
{:ok, plan} =
  Tempo.Schedule.new()
  |> Tempo.Schedule.task(:design, duration: ~o"P2D", start: ~o"2026-06-01")
  |> Tempo.Schedule.task(:build,  duration: ~o"P3D", after: :design)
  |> Tempo.Schedule.task(:docs,   duration: ~o"P1D", after: :design)
  |> Tempo.Schedule.task(:ship,   duration: ~o"P2D", after: [:build, :docs], deadline: ~o"2026-06-08")
  |> Tempo.Schedule.solve()

plan[:ship].early                    #=> ~o"2026Y6M6D/8D"
plan[:docs].critical?                #=> false   (docs has slack)
Tempo.Schedule.critical_path(plan)   #=> [:design, :build, :ship]
```

> *"Design, then build and docs in parallel, then ship — due the 8th. Ship runs from the 6th to the 8th; docs has slack; the critical path is design → build → ship."*

---

### "Which reign overlaps which stratum, given only relative dates?" — Constraint network

```elixir
alias Tempo.Network

net =
  Network.new()
  |> Network.add_period(:k1, from: {:not_before, ~o"1200Y"}, duration: {:at_most, ~o"P10Y"})
  |> Network.add_period(:k2, to: {:not_after, ~o"1300Y"}, duration: {:at_least, ~o"P35Y"})
  |> Network.add_period(:s1, duration: {~o"P20Y", ~o"P100Y"})
  |> Network.add_sequence([:k1, :k2])
  |> Network.add_relation(:starts_during, :s1, :k1)

Tempo.Network.Solver.consistent?(net)               #=> true
Tempo.Network.Solver.contemporaneity(net, :k1, :s1) #=> :certain  (S1 starts during K1's reign)
{:ok, solved} = Tempo.Network.Solver.propagate(net)
solved.periods[:s1].earliest_start                  #=> a derived Tempo value
```

> *"The kings reign in succession; stratum S1 starts during King K1. Do they overlap, is it jointly possible, and what does it pin down?"* `contemporaneity/3` answers "could these two have coexisted?" three-valued — `:certain`, `:possible`, or `:impossible` — read in constant time from the propagated network; `propagate/1` derives the narrowest start/end/duration for every period, even ones given no dates at all.
