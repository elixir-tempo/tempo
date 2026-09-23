# Recurrence sets

**Status:** planning, 2026-09-23 — representation settled: option 2, a thin `%Tempo.RecurrenceSet{members, metadata}` whose members are `%Tempo.Interval{}` recurrences-with-metadata (agreed 2026-09-23). Exceptions resolved: the recurrence's domain sits in its interval slot with `^` exclusion members (`R/^2026/P1Y/…`, or `R/{2020..2030,^2026}/P1Y/…`), applied via existing set algebra — no new `%Tempo.Interval{}` field. **Status → in progress (2026-09-23):** `^` is a general set-exclusion member (decided); Q2 accepted — conditionals/lunisolar pre-materialised, simple transforms + exclusions ride on the member. Implementing in stages: **(a)** `%Tempo.Set{}` exclusion members + `^` grammar + interval-slot domain; **(b)** `%Tempo.RecurrenceSet{}` + `to_interval_set` + `align` window-derivation; **(c)** tempo_holidays emit-as-recurrence-with-metadata (last, near release).

## Problem

The motivating query: *"Which of my diary entries fall on an Australian public holiday?"* — or its relatives, *"the working days I have free that aren't holidays,"* *"holidays I've booked a meeting over."* Australia's holidays are a **set of recurrences** — one rule per holiday: `~o"R/../P1Y/FL12M25DN"` (Christmas), `~o"R/../P1Y/FL(easter)EN"` and its window feasts, `~o"R/1447Y1M1D[u-ca=islamic-umalqura]/P1Y"` (calendar recurrences), an nth-weekday, a solar event. A diary is a concrete `%Tempo.IntervalSet{}`.

To intersect them, the holiday *rules* must first become a concrete `IntervalSet` over some window, then the existing set algebra runs. Tempo has the two ends of that pipeline but nothing in the middle:

* `%Tempo.Interval{}` — **one** recurrence rule (unmaterialised).
* `%Tempo.IntervalSet{}` — a materialised set of **concrete** intervals.

There is no first-class value for **a collection of recurrence rules that materialises as a unit**. Today a consumer must materialise each holiday rule against a bound, union the results by hand, then intersect — and `tempo_holidays` hands back a bare `[Holiday.t()]` list (`recurrences/2`) that does not compose through set algebra at all.

This plan proposes that middle construct and how it materialises.

## What already holds (verified against the source)

* A recurrence is `%Tempo.Interval{recurrence: n, repeat_rule: …, from: nil, to: nil}` ([lib/tempo/interval.ex:103](../lib/tempo/interval.ex)); `Tempo.to_interval(rec, bound: window)` → `{:ok, %Tempo.IntervalSet{}}` ([lib/tempo.ex:4974](../lib/tempo.ex)). Without a `:bound` it refuses (`IntervalEndpointsError`, `:unanchored`) rather than looping.
* `%Tempo.IntervalSet{intervals, metadata, backend}` holds **bounded** members only — `new/2` rejects `:undefined`/`nil` bounds (`validate_all_bounded`, [lib/tempo/interval_set.ex:150](../lib/tempo/interval_set.ex)). Backends: `List` (default), `Tree`, `Lazy` (`from_stream/2`).
* `Tempo.intersection/union/difference` already (a) accept `Tempo | Interval | IntervalSet | Tempo.Set`, (b) **fold over a list of operands** — `intersection(a, [b, c, …])` ([lib/operations.ex:839](../lib/operations.ex)), and (c) normalise each operand with `to_interval_set` + `maybe_anchor_to_bound`, which anchors a non-anchored operand against `opts[:bound]`. Two gaps: `maybe_anchor_to_bound` **`Keyword.fetch!`es `:bound`** (so intersecting an unanchored recurrence without a bound raises rather than deriving the window from the concrete counterparty), and no operand class covers "a bag of rules."
* Precedent: `Tempo.ICal.from_ical/2` already fuses a whole calendar (many components, each with RRULE/RDATE/EXDATE) into **one** coalesced `%Tempo.IntervalSet{}`, materialised within a `:window` ([lib/ical.ex:100](../lib/ical.ex)). That is exactly the many-rules→one-set operation, specialised to ICS.
* The Lazy backend + `Tempo.UnboundedSetError` / `UnboundedRecurrenceError` already encode the contract: an answer that needs an unbounded walk without a `:bound` refuses rather than hangs.

## (a) Representing a set of recurrences

**A member is a recurrence with metadata — no bespoke `Holiday` type.** `%Tempo.Interval{}` already carries a `metadata` map ([lib/tempo/interval.ex:103](../lib/tempo/interval.ex)) and is *already* the union "a recurrence (open bounds + `repeat_rule`) **or** a concrete interval (fixed bounds)" — `to_interval/2` handles both. So a holiday, an iCal event, any annotated occurrence generator is just a `%Tempo.Interval{}` whose metadata holds its name (and, for a gated holiday, its year/date gate operands, applied via set algebra rather than a new field — see Open question 1). Set operations already carry metadata through — a materialised occurrence keeps its `:name`, and the resolver can even merge metadata on overlap ([lib/operations.ex:822](../lib/operations.ex)). This dissolves tempo_holidays' `%Holiday{name, rule, type}` into `metadata: %{name:, type:}` on the recurrence; `%Rule{}` stays as the *compiler's* typed IR, but what it produces is a recurrence-with-metadata.

The set itself is then genuinely thin — a bag of members plus set-level metadata:

```
%Tempo.RecurrenceSet{
  members:  [Tempo.Interval.t()],   # each a recurrence-with-metadata OR a concrete interval-with-metadata
  metadata: %{}                     # set-level, e.g. %{territory: :AU}
}
```

No set-level `exceptions` field — exceptions ride on each member (see Open question 1). And because a member may be *either* a rule or an already-concrete interval, tempo_holidays puts its **declarative** holidays in as recurrences and its **context-dependent** ones (bridges/conditionals, the lunisolar query) in as **pre-materialised concrete intervals** — both are `%Tempo.Interval{}`, both materialise uniformly (a recurrence needs the window; a concrete interval returns itself). Members keep their own calendars (`[u-ca=…]`); materialisation converts per member as `align` already does (`convert_calendar`).

**Decision (agreed 2026-09-23):** members are `%Tempo.Interval{}` recurrences-with-metadata; the `%Tempo.RecurrenceSet{}` struct is a thin `{members, metadata}` bag, with a bare list accepted as sugar and a `Tempo.to_interval_set/2` clause so it drops into the existing algebra. The alternatives that were weighed are recorded below.

## (b) Materialising into an interval set

The core operation is `RecurrenceSet × window → IntervalSet`. `Tempo.to_interval_set(rset, bound: window)` (and the matching `to_interval/2` clause):

1. For each member, `Tempo.to_interval(member, bound: window)` → a per-member `IntervalSet`, reusing the single-recurrence path (calendar recurrences, §12 selections, computed events); a member that is already a concrete interval returns itself. A gated member then has its `^`-exclusions (`metadata[:except]`) folded in by the existing set algebra — `difference` for excluded spans, `intersection` for an active window (Open question 1) — so the member is self-contained.
2. `union` the per-member sets. Default `coalesce: false` so each occurrence keeps its member's metadata (a materialised Christmas interval stays labelled "Christmas"); `coalesce: true` yields the canonical instant-set.
3. Return one `%Tempo.IntervalSet{}`.

The **window** is the user's "anchor," supplied two ways:

* **Explicit** — `bound: ~o"2026Y"` (or any interval/set): materialise across it.
* **Implicit from the counterparty** (the ergonomic win) — `Tempo.intersection(au_holidays, my_diary)` should materialise `au_holidays` across `my_diary`'s extent (`[min from, max to)`), because an intersection with a concrete set never needs occurrences outside that set's span. This means teaching `maybe_anchor_to_bound` to fall back to the concrete operand's extent when no explicit `:bound` is given, instead of `Keyword.fetch!`ing it (which also removes the current raise). `diary − holidays` uses the diary's extent likewise; `holidays − diary`, or two rule-sets with no concrete side, still need an explicit `:bound` and otherwise refuse cleanly.

**Unbounded / lazy.** Holidays recur forever, so a `RecurrenceSet` has no intrinsic upper bound. `RecurrenceSet.to_lazy/1` → a Lazy `IntervalSet` whose stream is the **sorted merge** of each member's occurrence stream (the "sorted stream merge" the Lazy-backend TODO already anticipates). Intersecting a Lazy holiday set with a bounded diary bounds the walk; an unbounded walk with no bound raises `UnboundedSetError`, per the existing contract.

## Edge cases & decisions

* **Identity vs canonical form** — default `coalesce: false` so a materialised holiday keeps its name and abutting *different* holidays stay distinct (tempo_holidays already relies on name-aware coalescing); `coalesce: true` for the pure instant-set.
* **Half-open** — every materialised member is `[from, to)`; union/difference honour it (existing invariant).
* **Mixed calendars** — members in Islamic/Hebrew/Julian/lunisolar each materialise in their own calendar, then convert to a common axis for the union (existing `convert_calendar`).
* **Empty window / no occurrences** — an empty `IntervalSet`, never an error.

## Alternatives considered (for the set representation)

The deciding fact: a "set of holidays" means the **union** of its members (a diary entry clashes if it hits *any* holiday), which is what steers the choice.

1. **A bare list of recurrences** (no new type), riding the list-folding the algebra already has (`intersection(a, [b, c])`). Rejected as the value: `intersection(diary, [xmas, new_year])` folds pairwise to `diary ∩ xmas ∩ new_year` (empty), not `diary ∩ (xmas ∪ new_year)`; a list does not encode "these are unioned." Kept only as *input* sugar.
2. **A thin `%Tempo.RecurrenceSet{members, metadata}`** — chosen. Fixes members-as-union; introspectable/round-trippable; set-level metadata; materialises eagerly or lazily; the shared output of both `tempo_holidays` and `ICal.from_ical`.
3. **A lazy `%Tempo.IntervalSet{}` only** (reuse the existing set, no new type) — the set built by merging members' occurrence streams. Correct (it *is* the union) and needs no new type, but the rules are hidden inside a stream: not introspectable/round-trippable, nowhere clean to hang per-member exceptions/transforms. It is the (lazily-) materialised form, not the rule form. Kept as a *materialisation target* of option 2 (`RecurrenceSet.to_lazy/1`), not the representation.
4. **`Tempo.Intervallic` protocol** (already a TODO) — let a consumer's own list participate in set ops via a window-materialisation callback. Complementary (it answers *composability*, not *representation*); worth doing alongside, not instead.
5. **Nothing in Tempo — `tempo_holidays` owns materialisation** (`materialise(:AU, window)` → plain `IntervalSet`). Simplest, works today, but no reusable concept: iCal and a consumer's own rules each reinvent the merge, and the window must always be pre-chosen.

## Open design questions (from the "recurrence + metadata" refinement)

1. **Exceptions — RESOLVED (2026-09-23): no new field; they are set operations over year/date sets.** Every gate the holiday corpus carries is already a set op, and the holiday cookbook already expresses them: `active`/`since`/`until` = `intersection` with a year *range*; even/odd/leap = `intersection` with a year *set*; `disable`/`EXDATE` = `difference` with a date; `enable`/`RDATE` = `union` with a date. (Note gates are not *only* year-based — `disable`/`enable` and iCal `EXDATE`/`RDATE` are specific dates — but year or date, all are `∩`/`−`/`∪` over ordinary Tempo sets.) So `%Tempo.Interval{}` gains **nothing**, and there is no bespoke exception mechanism to build. For a `RecurrenceSet` that must re-materialise against any window, a gated member carries its gate operands as **set-valued metadata** (`%{active: ~o"2009/2016", disable: date_set}`) and the materialiser folds them in with the *same* `intersection`/`difference`/`union` after materialising the base recurrence; the rest of metadata stays strictly opaque. (Equivalently, tempo_holidays — which already applies these gates in `rule.ex` — can bake them in when it emits the member.)

   **Surface syntax — a domain set in the interval slot, with `^` exclusion members (2026-09-23).** The recurrence's *domain* goes in its interval slot, and `^` marks an exclusion: `~o"R/^2026/P1Y/FL12M25DN"` is Christmas every year except 2026; `~o"R/{2020..2030,^2026}/P1Y/FL12M25DN"` narrows to 2020–2030 (half-open) *and* drops 2026 — one expression carrying both the active window and the exceptions, where the recurrence's domain belongs. As everywhere in Tempo, braces are only for a genuine **set**: a lone exclusion (`^2026`) or a lone range (`^2009..2017`) needs none, exactly as `2026Y` does not but `{2024,2026}Y` does; the braces appear once members are combined. `^` is otherwise just a new exclusion **member** of the existing `{…}` literal, which generalises: `~o"{2020..2030,^2026}Y"` is a set usable anywhere (its plain members minus its `^` members; with no plain members, `^` subtracts from the universe). Semantics are the set algebra already agreed — plain members intersect, `^` members `difference`. A member carries any span, so `^2026`, `^2026-12`, `^2026-12-25` all work, covering the year *and* date exclusions in one syntax. `^` is free in the grammar; like `E`/`+` it is a non-conformant extension needing a syntax-guide note. Storage: the domain rides as a `%Tempo.Set{}` on the recurrence (the interval slot / repeat rule), not a new top-level `%Tempo.Interval{}` field, and the parser distinguishes it from an anchor date by the braces. Non-contiguous *computed* sets (even/odd/leap) are not spans, so they stay explicit `intersection` with a year set.

   **Parse-time coalescing (2026-09-23).** `^` is input sugar that normalises away wherever the members are commensurable concrete ranges — the common year case: `{2020..2030,^2026}` folds at parse time into the plain set `{2020..2025,2027..2030}` (and adjacent/overlapping ranges merge, `{2020..2025,2026..2030}` → `{2020..2030}`), so `except` stays empty and the value round-trips as the coalesced set. `^` (and a populated `except`) survives only where it *cannot* fold: a finer-grained or cross-calendar exclusion (`{2020..2030,^2026-06-15}` — a day out of a set of years) or a bare exclusion against the universe (`R/^2026-12-25/P1Y`, no plain domain to fold into). So the core (parse → `set`/`except` → materialise via `difference`) is built first, and coalescing is a normalisation layered on top that empties `except` in the common case.

   **Open sub-choice:** is `^` a **general** set-member modifier (valid wherever a `{…}` set appears — recommended, since the recurrence-domain use is then just one application and `%Tempo.Set{}` gains exclusion members once), or **only** in the recurrence interval slot? Recommend general.

2. **The non-pure-recurrence holidays.** Not every holiday reduces to a self-contained recurrence: observed-date **substitution** is a transform over the base; **bridge / if_holiday** depend on the year's *other* holidays (a second pass — `Holidays.resolve_conditional/4`); the **lunisolar traditional-month** is a Calendrical query. Two ways to carry them: encode the transform in metadata for the materialiser to apply (flexible, untyped), or have tempo_holidays **pre-materialise** them into concrete `%Tempo.Interval{}` intervals-with-name that drop into the same set. **Recommendation:** simple, self-contained transforms (substitution, year/weekday gates, exceptions) ride on the member and are applied at materialise time; conditionals and the lunisolar query — which need set context or a query regardless — are pre-materialised by tempo_holidays into concrete members. `%Rule{}` stays the compiler IR that emits either shape. Consequence: a conditional member is only meaningful for a known window, so a `RecurrenceSet` that contains one is not fully lazy/unbounded — document this, or resolve conditionals in a set-level second pass at materialise time (as `Holidays.materialise/2` already does).

## Tasks

* [ ] Exceptions as a domain set in the recurrence interval slot with `^` exclusion members: extend the `{…}` set literal and the interval-slot grammar to accept a lone `^<span>` (no braces) or a set carrying `^` members (`%Tempo.Set{}` gains exclusion members); `to_interval/2` intersects plain members and `difference`s `^` members after materialising; conformance-guide note (non-conformant extension, like `E`/`+`); round-trip `^` in `inspect`/`to_iso8601`. Decide whether `^` is a general set-member modifier (recommended) or interval-slot-only.
* [ ] Parse-time coalescing: where the domain's plain members and `^` exclusions are commensurable concrete ranges, fold the exclusions into the plain set and merge adjacent/overlapping ranges (`{2020..2030,^2026}` → `{2020..2025,2027..2030}`), leaving `except` empty; keep `set`/`except` split only for incommensurable exclusions. Layered on the core, not a prerequisite.
* [ ] `%Tempo.RecurrenceSet{members, metadata}` struct + `new/1,2`; accept a bare list of `%Tempo.Interval{}` as sugar.
* [ ] `Tempo.to_interval_set/2` and `to_interval/2` clauses for a `RecurrenceSet` — materialise each member against `:bound` (recurrences) or pass through (concrete members), union, preserve member metadata.
* [ ] `RecurrenceSet.to_lazy/1` — sorted-merge occurrence stream → Lazy `IntervalSet`.
* [ ] Set-algebra integration — `to_aligned_set` accepts a `RecurrenceSet`; `maybe_anchor_to_bound` derives the window from a concrete counterparty when no `:bound` is given, and refuses (not raises) when neither exists.
* [ ] `tempo_holidays`: emit each holiday as a `%Tempo.Interval{}` recurrence-with-metadata (`%{name:, type:}`), with substitution/gates/exceptions on the member and conditionals/lunisolar pre-materialised; `Tempo.Holidays.recurrence_set/2` → `%Tempo.RecurrenceSet{}`, so `Tempo.intersection(Holidays.recurrence_set(:AU), diary)` is one call. `%Holiday{}` dissolves into metadata; `%Rule{}` stays the compiler IR.
* [ ] Cookbook recipe in the pipeline-prose shape (below).

## Worked example (target ergonomics)

```elixir
holidays = Tempo.Holidays.recurrence_set(:AU)          # a %Tempo.RecurrenceSet{}
diary    = Tempo.ICal.from_ical!(File.read!("diary.ics"))

{:ok, clashes} = Tempo.intersection(diary, holidays)   # diary's extent is the window
booked_over =
  clashes
  |> Tempo.IntervalSet.to_list()
  |> Enum.map(&Tempo.Interval.metadata/1)
```

> *"My **diary** and Australia's **holidays**. The **clashes** are the diary entries that fall on a holiday — each labelled with the holiday it hit."*

## Relationship to existing plans / TODO

* Subsumes the "holiday generator sources" and "sorted stream merge" parts of the Lazy-backend TODO item.
* Complements the `Tempo.Intervallic` protocol TODO (user structs in set ops) — a `RecurrenceSet` is the rule-side dual.
* Generalises `Tempo.ICal.from_ical/2`, which becomes a `RecurrenceSet` materialisation specialised to ICS.
