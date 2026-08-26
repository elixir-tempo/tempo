# Chronological networks

*For historians and archaeologists — no programming background assumed.*

A chronology is rarely a list of fixed dates. It is a **web of relationships**: a king reigns before another, a stratum is built during a reign, a pottery style overlaps the next, an inscription gives a "no earlier than". Tempo lets you write that web down as a **chronological network**, check it for contradictions, and compute the tightest dates each entity can possibly take.

This implements the ChronoLog scheme of Levy, Geeraerts, Pluquet, Piasetzky and Fantalkin, *"Chronological networks in archaeology: A formalised scheme"* (*Journal of Archaeological Science*, 2020), as a Tempo library layer (`Tempo.Network`).

## 1. Your chronology is a network

Three kinds of thing make up a network:

* **Periods** — the things with a beginning and an end: a reign, an era, the life of a stratum or a pottery style.

* **Sequences** — periods that follow one another with no gap: each one ends exactly where the next begins.

* **Relations** — everything you know that ties two periods together: "is contemporary with", "is included in", "starts during", "ends at least 20 years before", and so on.

You state what you know. Tempo works out what that *implies*.

## 2. Stating what you know

Dates and durations are ordinary Tempo values, written with the `~o` sigil: a year is `~o"1200Y"` (`~o"-664Y"` for BCE), a precise day `~o"1200-06-15"`, a duration `~o"P20Y"`. A period's start, end, and duration are each stated independently, and each can be exact, one-sided, a range, or simply unknown:

```elixir
import Tempo.Sigils
alias Tempo.Network

network =
  Network.new()
  # "King K1's reign began no earlier than 1200 and lasted at most 10 years."
  |> Network.add_period(:k1, name: "King K1", start: {:not_before, ~o"1200Y"}, duration: {:at_most, ~o"P10Y"})
  # "King K2's reign ended by 1300 and lasted at least 35 years."
  |> Network.add_period(:k2, name: "King K2", end: {:not_after, ~o"1300Y"}, duration: {:at_least, ~o"P35Y"})
```

The vocabulary mirrors how an archaeologist actually speaks:

| You want to say | You write |
|---|---|
| "exactly 664 BCE" | `start: ~o"-664Y"` |
| "no earlier than 1200" | `start: {:not_before, ~o"1200Y"}` |
| "no later than 1300" | `end: {:not_after, ~o"1300Y"}` |
| "between 1200 and 1250" | `start: {~o"1200Y", ~o"1250Y"}` |
| "lasted at least 20 years" | `duration: {:at_least, ~o"P20Y"}` |
| "lasted 20 to 100 years" | `duration: {~o"P20Y", ~o"P100Y"}` |
| "circa 720 (`~720`)" | `start: ~o"~720Y"` *(the `~` is kept as a note; it does not move the date)* |

A bare integer year (`1200`, `-664`) and an ISO 8601 string are also accepted as shorthands for year-grained work, but the `~o` form is the idiom — and it is what every bound is stored and returned as.

> *"K1 began no earlier than 1200 and reigned at most 10 years; K2 ended by 1300 and reigned at least 35."*

## 3. Building ChronoLand

The paper's worked example. In the Kingdom of ChronoLand, kings **K1** then **K2** reigned in succession, both between 1200 and 1300 CE; K1 reigned at most 10 years and K2 at least 35. Two strata follow one another: **S1** (built by K1, who founded the city) and **S2** (destroyed by fire under K2). Each stratum lasted 20 to 100 years.

<!-- guides:run -->

```elixir
import Tempo.Sigils
alias Tempo.Network

chronoland =
  Network.new()
  |> Network.add_period(:k1, name: "King K1", start: {:not_before, ~o"1200Y"}, duration: {:at_most, ~o"P10Y"})
  |> Network.add_period(:k2, name: "King K2", end: {:not_after, ~o"1300Y"}, duration: {:at_least, ~o"P35Y"})
  |> Network.add_period(:s1, name: "Stratum S1", duration: {~o"P20Y", ~o"P100Y"})
  |> Network.add_period(:s2, name: "Stratum S2", duration: {~o"P20Y", ~o"P100Y"})
  |> Network.add_sequence([:k1, :k2])
  |> Network.add_sequence([:s1, :s2])
  |> Network.add_relation(:starts_during, :s1, :k1)
  |> Network.add_relation(:ends_during, :s2, :k2)
```

> *"The kings reign in succession, and so do the strata. Stratum S1 starts during King K1's reign; Stratum S2 is destroyed — ends — during King K2's."*

First, is it even possible? **Consistency** asks whether any assignment of dates satisfies everything at once:

```elixir
Tempo.Network.Solver.consistent?(chronoland)
#=> true
```

## 4. Reading the answer

**Tightening** computes, for every period, the narrowest start, end, and duration the network allows. Anything outside those bounds would break a constraint; anything inside is still possible.

```elixir
{:ok, solved} = Tempo.Network.Solver.tighten(chronoland)

solved.periods[:k2].earliest_end
#=> ~o"1240Y"
```

Every bound comes back as a Tempo value. The strata, which had *no dates at all* as input, now have them — derived purely from the relations:

| Period | Start | End | Duration |
|---|---|---|---|
| King K1 | 1200 – 1260 | 1200 – 1265 | ≤ 10 |
| King K2 | 1200 – 1265 | 1240 – 1300 | 35 – 100 |
| Stratum S1 | 1200 – 1260 | 1220 – 1280 | 20 – 80 |
| Stratum S2 | 1220 – 1280 | 1240 – 1300 | 20 – 80 |

The bounds you typed in are **input**; the ones Tempo worked out are **computed**. For example, the duration of each stratum tightened from "20–100" to "20–80", because the whole dynasty is too short to hold a longer one.

### The trace — *why* a bound holds

Every computed bound can be explained. A **trace** is the chain of constraints that forces it — the same reasoning an archaeologist would write out by hand:

```elixir
{:ok, trace} = Tempo.Network.Solver.trace(chronoland, {:end, :k2}, bound: :earliest)
trace.prose
```

> King K1 starts no earlier than 1200 ⇒ the start of King K1 ≥ 1200; Stratum S1 starts during King K1 ⇒ the start of Stratum S1 ≥ 1200; Stratum S1 lasts at least 20 years ⇒ the end of Stratum S1 ≥ 1220; Stratum S1 immediately precedes Stratum S2 ⇒ the start of Stratum S2 ≥ 1220; Stratum S2 lasts at least 20 years ⇒ the end of Stratum S2 ≥ 1240; Stratum S2 ends during King K2 ⇒ the end of King K2 ≥ 1240.

No hidden assumptions, no "rule of thumb" — every step names the input it rests on. If a colleague disputes the conclusion, they can point at exactly which input they reject.

## 5. Testing a hypothesis

Because consistency is a one-line question, you can *test ideas*. Could King K1 have also built Stratum S2? Add the claim and ask:

```elixir
hypothesis = Tempo.Network.add_relation(chronoland, :starts_during, :s2, :k1)
Tempo.Network.Solver.consistent?(hypothesis)
#=> false
```

The network says **no**: if S2 had begun during K1's reign, that reign would have had to contain the whole of S1 *and* the start of S2 — at least 20 years — which exceeds K1's 10-year maximum. A conclusion that was far from obvious by eye.

### Asking directly — could two periods overlap?

Adding a claim and re-checking consistency is the general tool, but for the common question *"could these two have coexisted at all?"* there is a direct query. `contemporaneity/3` reads the tightened network and answers three ways — `:certain` (every valid chronology has them overlapping), `:possible` (some do, some don't), or `:impossible` (none do):

```elixir
Tempo.Network.Solver.contemporaneity(chronoland, :k1, :s2)
#=> :impossible
```

> *"King K1 and Stratum S2 can never have coexisted — S2 begins at least ten years after K1 is already dead."*

K1's reign (≤ 10 years) is shorter than the ≥ 20 years that must separate the two strata's starts, so K1 has ended well before S2 begins. `certainly_contemporary?/3` and `possibly_contemporary?/3` are the boolean shortcuts, and unlike adding a relation they leave the network untouched. The verdict is read in constant time from the tightened network's shortest-path weights — the sure/possible-contemporaneity result of Geeraerts, Levy & Pluquet (TIME 2017, Props 7 and 10).

### Asking directly — what *is* the relation?

`contemporaneity/3` collapses the thirteen Allen relations into a single overlap question. When you want the actual relation the constraints leave open — the archaeologist's real question, *"given everything I know, how does King K1's reign sit against Stratum S2?"* — `relation/3` answers in the same vocabulary `Tempo.relation/2` uses for fixed dates:

```elixir
Tempo.Network.Solver.relation(chronoland, :k1, :s2)
#=> :precedes
```

> *"King K1's reign falls entirely before Stratum S2 — not merely non-overlapping, but earlier."*

A single atom means the network **entails** that relation: every chronology consistent with the constraints agrees. It is the sharp form of the `:impossible` overlap above — the evidence doesn't just forbid coexistence, it fixes the order. When the constraints leave room, the answer is the tightest disjunction that still holds:

```elixir
Tempo.Network.Solver.relation(chronoland, :s1, :k1)
#=> [:started_by, :overlapped_by, :met_by]
```

> *"Stratum S1 starts within King K1's reign and outlasts it — but whether it shares his accession, overlaps mid-reign, or begins just as he ends, the evidence doesn't say."*

`relation_certainty/4` asks the same of one named relation, in the three-valued vocabulary the ±-margin comparisons already use — `:certain` when the network entails it, `:possible` when it is one of several, `:impossible` when ruled out:

```elixir
Tempo.Network.Solver.relation_certainty(chronoland, :k1, :s2, :precedes)
#=> :certain
```

Like `contemporaneity/3`, both read straight off the tightened network's shortest-path weights — no extra solve, and no qualitative disjunction enters, so the query stays polynomial.

## 6. When you don't need a network

A network earns its keep when something is *uncertain* or the structure is *not a simple line*. When neither is true — one anchor, exact durations, plain succession — you don't need it at all. You can just chain intervals.

The Egyptian 26th dynasty (after Kitchen 2000) is six reigns in succession with known lengths, anchored at Psammetichus I's accession in 664 BCE. Each reign runs from its accession to its accession plus its length, and the next begins where the last ended:

<!-- guides:run -->

```elixir
import Tempo.Sigils

reigns = [
  {"Psammetichus I", ~o"P54Y"},
  {"Necho II", ~o"P15Y"},
  {"Psammetichus II", ~o"P6Y"},
  {"Apries", ~o"P19Y"},
  {"Amasis II", ~o"P44Y"},
  {"Psammetichus III", ~o"P1Y"}
]

{reign_spans, _dynasty_end} =
  Enum.map_reduce(reigns, ~o"-664Y", fn {_name, length}, accession ->
    abdication = Tempo.Math.add(accession, length)
    {Tempo.Interval.new!(from: accession, to: abdication), abdication}
  end)
```

`reign_spans` is now the six reigns as intervals (Psammetichus I is `~o"-664Y/-610Y"`, and so on). Because Tempo's intervals are half-open, the consecutive reigns abut exactly, so collapsing them yields the dynasty as one span:

```elixir
reign_spans |> Tempo.IntervalSet.new!() |> Tempo.IntervalSet.coalesce()
#=> #Tempo.IntervalSet<[~o"-664Y/-525Y"]>
```

> *"Six reigns, each starting where the last ended, collapse to a single 139-year dynasty from 664 to 525 BCE."* No network, no solver — just addition and the half-open convention.

A network would give the identical answer, but it adds nothing here. Reach for `Tempo.Network` the moment a length becomes a *range*, a relation is anything other than succession, or you need to propagate from an anchor that isn't first — exactly the ChronoLand case in §3–5.

## 7. Uncertainty

* **Qualifiers vs bounds.** An EDTF qualifier such as `~720` ("circa") is carried as a *note* on the period; it does not silently widen a date. If you mean "720 give or take a decade", say so with a range (`{710, 730}`). Keeping the two separate stops a vague "circa" from quietly doing arithmetic.

* **Absolute vs floating.** A period with no tie to a calendar date is *floating*: its duration and its order relative to its neighbours are known, but not its position in absolute time. Tempo handles both in one network — a floating sub-sequence inherits absolute dates the moment any one of its members is anchored.

* **Regional sequences.** Where two regions' phases overlap rather than line up (as in Coldstream's Greek Geometric pottery), model each region as its own sequence and join them with `:overlaps` or `:contemporary` relations, rather than forcing one master sequence.

## 8. Sharing

Every period boundary is an ordinary Tempo value, so it round-trips through ISO 8601 / EDTF for exchange with other tools:

<!-- guides:skip -->

```elixir
Tempo.to_iso8601(solved.periods["Psammetichus I"].earliest_start)
#=> "-664Y"
```

## 9. Validated against ChronoLog

Tempo's network model *is* the ChronoLog scheme, so the proof it is faithful is that it re-solves ChronoLog's own models and gets ChronoLog's own answers. Tempo's test suite decodes a corpus of published `.clog` files — the Egyptian 26th dynasty, three Near-Eastern models from the 2022 Radiocarbon Dating and Chronology workshop (Dynasty 18, the Aegean LH→PG ceramic sequence, the Iron Age Levant), and the Mediterranean Late Bronze Age study — and checks each one is consistent and, where the model is anchored, recovers the same dates.

The Egyptian dynasty is the sharpest demonstration. In §6 we assumed exact reign lengths *and* a known accession, so no network was needed. The original ChronoLog model assumes neither: every reign length is only a **lower bound**, and the sole calendar anchor — the Persian conquest of Egypt in 525 BCE — sits at the dynasty's *end*. What pins the accessions is a web of epigraphic **delay synchronisms**: dated Apis-bull installations, each tied to a specific regnal year. A delay synchronism is a metric relation, the one constraint Allen's algebra cannot state — "this boundary falls exactly *n* years after that one":

<!-- guides:run -->

```elixir
import Tempo.Sigils
alias Tempo.Network
alias Tempo.Network.Solver

dynasty =
  Network.new()
  |> Network.add_period("Psammetichus I", duration: {:at_least, ~o"P54Y"})
  |> Network.add_period("Necho II", duration: {:at_least, ~o"P15Y"})
  |> Network.add_period("Psammetichus II", duration: ~o"P6Y")
  |> Network.add_period("Apries", duration: {:at_least, ~o"P19Y"})
  |> Network.add_period("Amasis", duration: ~o"P44Y")
  |> Network.add_period("Psammetichus III", duration: ~o"P1Y")
  |> Network.add_sequence(["Psammetichus I", "Necho II", "Psammetichus II", "Apries", "Amasis", "Psammetichus III"])
  # The Persian conquest, 525 BCE, ends Psammetichus III's reign.
  |> Network.add_period("Persian conquest", start: ~o"-525Y", end: ~o"-525Y", duration: ~o"P0Y")
  |> Network.add_relation(:synchronous_end, "Persian conquest", "Psammetichus III")
  # Apis bull III was installed exactly 52 years into Psammetichus I's reign.
  |> Network.add_period("Apis Bull III", duration: ~o"P17Y")
  |> Network.add_relation({:delay, :start, :start, :exactly, ~o"P52Y"}, "Psammetichus I", "Apis Bull III")

{:ok, solved} = Solver.tighten(dynasty)
solved.periods["Psammetichus I"].latest_start
#=> ~o"-664Y"
```

> *"Even with every reign length only a 'no less than' and the only fixed date at the very end, a single dated Apis bull already forces Psammetichus I's accession to no later than 664 BCE."* The complete model — all five Apis bulls, the full set of delay synchronisms, and the Herodotus/Manetho reign lengths — tightens that bound to *exactly* 664 BCE, recovering the §6 dates without ever assuming them. That model, decoded straight from ChronoLog's `.clog` export, is checked end-to-end in Tempo's test suite.

## 10. Scope relative to ChronoLog

Tempo implements ChronoLog's **formal scheme** — the chronological network as a reasoning problem — not the ChronoLog *application*. It is worth being precise about where the boundary falls, because the two split a chronology into two layers and Tempo covers one of them completely and the other not at all.

**The relative/metric layer — full coverage.** Periods with bounded durations, gap-free sequences, events, the synchronism vocabulary, consistency checking, bound tightening, and the inconsistency trace are all here, solved as a Simple Temporal Problem exactly as the paper describes. Every ChronoLog synchronism reduces to constraints of the form `boundary₁ − boundary₂ ≤ k`, which is precisely what `Tempo.Network.Relation` emits, so the engine is equivalent — and the test suite proves it by re-solving ChronoLog's own published models and recovering their dates.

**The synchronism vocabulary.** ChronoLog names a large lattice of boundary relations; every one has a Tempo equivalent. The qualitative relations and Allen's thirteen are named atoms; the systematic "starts/ends before/after/at the start/end of" lattice is the single parameterised `{:boundary, edge, comparison, edge}` relation; metric offsets are `{:delay, …}`:

| ChronoLog synchronism | Tempo relation (read `A` *rel* `B`) |
|---|---|
| Equals · Starts with · Ends with | `:equals` · `:synchronous_start` · `:synchronous_end` |
| Meets · Met by | `:immediately_precedes` · `:immediately_follows` |
| Begins · Begun by · Ends · Ended by | `:starts` · `:started_by` · `:finishes` · `:finished_by` |
| Included in · Includes | `:included_in` · `:includes` |
| Starts during · Ends during | `:starts_during` · `:ends_during` |
| Includes start of · Includes end of | `:includes_start` · `:includes_end` |
| Overlaps before · Overlaps after | `:overlaps` · `:overlapped_by` |
| Contemporary with · Strictly contemporary with | `:contemporary` · `:strictly_contemporary` |
| Ends before or at start of | `{:boundary, :end, :at_or_before, :start}` |
| Starts after or at start of | `{:boundary, :start, :at_or_after, :start}` |
| Starts strictly after end of | `{:boundary, :start, :after, :end}` (≡ `:after`) |
| …the full before/after/at lattice | `{:boundary, edge, :before \| :at_or_before \| :coincident \| :at_or_after \| :after, edge}` |
| Delay (n units before/after) | `{:delay, edge, edge, :exactly \| :at_least \| :at_most, duration}` |

ChronoLog's *strict* composite synchronisms (e.g. "strictly included in") are the non-strict relation paired with a strict `{:boundary, …}` edge — two `add_relation/4` calls rather than one name. Its tolerance and hierarchy relations (`Start within`, `Equal within`, `Child of`, `Parent of`) are tied to ChronoLog's period-gazetteer features and are not modelled.

**The absolute/scientific layer — not covered.** Radiocarbon evidence and its Bayesian calibration (the `C14…ForExport` fields, exported to OxCal against the IntCal curve) are a separate, statistical layer. Tempo's network derives *deterministic* date bounds from order, duration, and historical anchors; it does not calibrate radiocarbon or compute probability distributions. Three of the bundled case studies are therefore purely *relative* in Tempo's hands — consistent and internally ordered, but unanchored in absolute time until a historical date is supplied — whereas the Egyptian and Mediterranean models, which carry historical anchors inside the network, resolve to calendar years.

**Also outside Tempo's scope, by design:** the ChronoLog GUI (visual modelling, the implication graph, the interactive trace panel), PERIODO gazetteer linking, and import/export as product features (Tempo's `.clog` decoder exists only to drive the validation tests). In short — Tempo is the chronological-network *engine* at parity with ChronoLog's formal model, not a replacement for the ChronoLog *tool* and its radiocarbon-dating workflow.

## Reference

Levy, E., Geeraerts, G., Pluquet, F., Piasetzky, E., & Fantalkin, A. (2020). Chronological networks in archaeology: A formalised scheme. *Journal of Archaeological Science*, 105225. <https://doi.org/10.1016/j.jas.2020.105225>. The ChronoLog software is at <http://chrono.ulb.be>.
