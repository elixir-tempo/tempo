# Recipes — English problem → Tempo pipeline

Few-shot templates, one per layer, in the pipeline-prose shape: **named bindings** (nouns) → **pipeline** (verbs) → **prose translation** (the human reading). Adapt the values; keep the shape. All assume `import Tempo.Sigils`. Validate any `~o"…"` you adapt (see `SKILL.md` → Grounding).

---

### "What does this uncertain date actually mean?" — Parse + Explain

```elixir
Tempo.explain(~o"2004-06~-11")
```

> *"The 11th of June 2004; its month and its year are approximate, the day is firm."* `explain/1` says what a value covers, which of its parts are qualified, whether it is floating or zoned, and what walking it gives. Use it to confirm you've represented the user's intent before building on it; `Tempo.qualification/1` gives the qualifiers as data.

---

### "Does the delivery window clash with the holiday?" — Relations

```elixir
delivery = ~o"2026-06-15/2026-06-20"
holiday  = ~o"2026-06-18"

Tempo.overlaps?(delivery, holiday)   #=> true
Tempo.relation(delivery, holiday)    #=> :contains
```

> *"The delivery window, the fifteenth through the twentieth, **contains** the holiday, so yes — they clash."* `relation/2` gives the precise Allen relation; the `?` predicates give the yes/no. An interval written to dates includes its last date.

---

### "When is everyone free for an hour?" — Set algebra

```elixir
work = ~o"2026-06-15T09/2026-06-15T17"
{:ok, busy} = Tempo.union(
  ~o"2026-06-15T10/2026-06-15T11",
  ~o"2026-06-15T14/2026-06-15T15"
)

{:ok, free}  = Tempo.difference(work, busy)
{:ok, slots} = Tempo.IntervalSet.slots(free, ~o"PT1H")
Tempo.IntervalSet.members(slots)   #=> six one-hour openings
```

> *"Free time is the workday **minus** the busy blocks; **bookable** slots are those gaps cut into one-hour pieces."* `difference`/`intersection`/`union` produce new intervals; `slots/3` discretises a free region into fixed-length openings.

---

### "The second Monday of every month in 2025" — Recurrence

```elixir
rule = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=2MO", from: ~o"2025-01-01")
rule                                #=> ~o"R/2025Y1M1D/P1M/FL1K2IN"
{:ok, months} = Tempo.to_interval(rule, within: ~o"2025")
Tempo.IntervalSet.count(months)     #=> 12
Tempo.IntervalSet.members(months)   #=> 13 January, 10 February, 10 March, …
```

> *"Parse the calendar rule into a recurrence — inspecting it shows the ISO 8601-2 selection it is, the second (`2I`) Monday (`1K`) of each month — then **convert** it to its occurrences within 2025."* For a simple period (no BY-rules) skip RRULE entirely and write it: `~o"R/2026-06-01/P1W"`. RRULE and `Cron.parse!/2` are convenient front doors; each compiles to a native selection, and `Tempo.RRule.to_string/1` writes one back.

---

### "The last weekday of every month" — BYSETPOS (`I`)

```elixir
rule = Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", from: ~o"2025-01-01")
{:ok, days} = Tempo.to_interval(rule, within: ~o"2025")
Tempo.IntervalSet.members(days)  #=> 31 January, 28 February, 31 March, … (last weekday of each month)
```

> *"The last **weekday** of the month — not the last Friday."* `BYSETPOS` is ISO 8601-2's position designator `I`, applied last over everything the rule selects in a period: `~o"R/../P1M/FL{1..5}K-1IN"` ranks each month's Monday-to-Friday candidates and keeps the last, where `BYDAY=-1FR` (`5K-1I`) would pick the last *Friday*, a different date. To hand the rule to another system, `Tempo.RRule.to_string/1` writes it as RFC 5545.

---

### "List every month in the year" — Enumeration

```elixir
Enum.to_list(~o"2026Y")     #=> [~o"2026Y1M", …, ~o"2026Y12M"]
Enum.take(~o"2026-06", 5)   #=> first five days of June
```

> *"A year **is** an enumerable sequence of its months; a month, of its days."* One span walks the unit below it; a set or a recurrence gives its members. To walk at another unit, say it: `Tempo.walk(~o"2026-06", :week)`.

---

### "Could these circa-dated finds be contemporary?" — Graded relations (uncertainty)

```elixir
hearth = ~o"1200±60Y"
midden = ~o"1240±40Y"
wall   = ~o"1500±20Y"

Tempo.possibly?(:overlaps, hearth, midden)    #=> true
Tempo.certainly?(:overlaps, hearth, midden)   #=> false
Tempo.certainty(:before, hearth, wall)        #=> :certain
```

> *"The hearth and midden **might** be contemporary but we can't be sure; the hearth is **certainly** before the wall."* `certainty/3` reads `±` margins, qualifiers and masks and answers `:certain`, `:possible` or `:impossible` for any predicate or Allen relation; `certainly?/3` and `possibly?/3` are its booleans. They agree with the plain predicates on crisp dates.

---

### "Five working days after the contract is signed" — Workdays

```elixir
{:ok, working} = Tempo.workdays(:US, except: ~o"2026-07-03")
Tempo.add_workdays(~o"2026-07-02", 1, working)   #=> {:ok, ~o"2026Y7M6D"}
Tempo.count_workdays(~o"2026-06", :US)           #=> {:ok, 22}
```

> *"The **workdays** of the United States, **except** the Friday holiday: one workday after Thursday the second is Monday the sixth."* A territory gives the weekend; `:except` takes the days off, as a date, a set or a recurrence.

---

### "What time is that in New York?" — Zones

```elixir
paris = ~o"2026-06-15T10[Europe/Paris]"
Tempo.shift_zone(paris, "America/New_York")   #=> {:ok, ~o"2026Y6M15DT4H[America/New_York]"}
Tempo.in_zone(~o"2026-06-15T10", "Europe/Paris")   #=> {:ok, ~o"2026Y6M15DT10H[Europe/Paris]"}
```

> *"Ten in Paris is four in New York."* `shift_zone/2` shows the same moment on another clock; `in_zone/2` says which zone a floating reading is in. A floating value and a zoned one are never compared or combined: place the floating one first.

---

### Dependency scheduling and constraint networks

Tasks with durations and dependencies (`Tempo.Schedule`) and relative, possibly undated constraints (`Tempo.Network`) are in the companion package `tempo_network`. If it is in the project, its own guide has the recipes; if not, say so rather than reaching for functions that are not there.
