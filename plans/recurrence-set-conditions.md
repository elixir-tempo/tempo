# Conditional recurrence-set members

**Status:** in progress, 2026-09-27

**Decision (user, 2026-09-27):** Option 1, before tempo_holidays returns its holidays as a `RecurrenceSet` ([plans/interval-recurrence-unification.md](interval-recurrence-unification.md)), so the set is complete. The open questions are settled as recommended: the filter is an equality map on member metadata (serialisable, and enough for `type`), and a moved occurrence is not seen by other conditionals — the tally is the first pass's, as in date-holidays.

A few holidays are kept or moved by the *other* holidays of their year, so no member of a `%Tempo.RecurrenceSet{}` can say them alone. tempo_holidays resolves them concretely today, in a second pass over the year's holidays; this plan proposes a declarative form, so a territory's whole holiday set is re-materialisable. [plans/recurrence-set.md](recurrence-set.md) (Open question 2) left these to be pre-materialised or resolved "in a set-level second pass at materialise time"; this document chooses between those.

## Problem

Of the 1,828 date-holidays rules, 1,824 are declarative recurrences. The last four each depend on the year's other holidays:

| Rule | Territory | Condition | Effect |
|---|---|---|---|
| `09-22 if 09-21 and 09-23 is public holiday` | Japan (Citizens' Holiday) | both neighbours are public holidays | kept, else none |
| `Thursday after 04-02 if is observance holiday then next Thursday` | CH-GL (Näfelser Fahrt) | it falls on an observance | the next Thursday |
| `Monday after 2nd saturday in June since 2022-09-09 if is public holiday then next monday` | Norfolk Island | it falls on a public holiday | the next Monday |
| `03-23 if Tuesday,Wednesday,Thursday then previous Monday if Friday,Saturday,Sunday then next Monday if is public holiday then next Monday` | NZ-OTA (Otago Anniversary) | it falls on a public holiday | the next Monday |

The semantics to preserve are date-holidays' `PostRule` pass, which tempo_holidays mirrors exactly (0 conformance mismatches): the first pass materialises every holiday's base occurrences and tallies the year's days by holiday type; the second resolves each conditional against that tally, discounting its own occurrences. So a conditional sees every other holiday's *base* occurrences, conditional ones included, but never itself.

## Options

### 1. A conditional member, resolved in a second pass

A recurrence-set member carries a condition over the other members' occurrences, and `Tempo.to_interval(%Tempo.RecurrenceSet{})` resolves it after materialising the rest:

* **Keep when** a list of dates relative to the occurrence — the day before and the day after, for the bridge — are all occurrences of other members matching a metadata filter (`%{type: :public}`).

* **Move when** the occurrence coincides with an occurrence of another member matching the filter, to the date a selection gives from it — "the next Thursday" is the §12.10 window `P7D` picking Thursday, as a relative weekday already is.

Tempo stays generic: member metadata is opaque except for the equality filter a condition names, and the move reuses the selection engine on a concrete anchor. The second pass needs the window widened by the move's reach, as windowed recurrences already are.

Costs: a new member shape and a second pass in `RecurrenceSet` materialisation; no ISO 8601 or RFC 5545 string form, which a recurrence set does not have anyway.

### 2. Set-algebra expressions over the other members

Say each condition with set operations: the bridge is the candidate day ∩ (the public holidays shifted a day later) ∩ (shifted a day earlier); the move is (candidate − colliding) ∪ next-Thursday(candidate ∩ colliding). It builds on general primitives, but needs two new ones — shifting a set by a duration, and mapping each member of a set through a selection — and the expression must name "the set without this member", which a set value cannot say about itself. Harder to read and to emit.

### 3. Leave them concrete

The four rules stay `:needs_window`, resolved by tempo_holidays' second pass; a recurrence set that holds them is only meaningful for a given window.

## Recommendation

Option 1. It states date-holidays' semantics directly — a second pass over the other members' base occurrences, self excluded — keeps Tempo generic through an equality filter on member metadata, and reuses the selection engine for every move. Option 2's primitives may still appear inside it.

## Design (2026-09-27)

A conditional member is a `%Tempo.RecurrenceSet.Conditional{}` wrapping an ordinary member, built by two constructors that read as the rule does:

```elixir
citizens_holiday =
  Tempo.RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN",
    at: [~o"-P1D", ~o"P1D"],
    falls_on: %{type: :public}
  )

naefelser_fahrt =
  Tempo.RecurrenceSet.move_when(~o"R/../P1Y/FLL4M2DN/P7DN4K-1IN",
    falls_on: %{type: :observance},
    to_next: ~o"4K"
  )
```

> *"Citizens' Holiday is 22 September, **kept** only when the day before and the day after both **fall on** public holidays. Näfelser Fahrt is the Thursday after 2 April, **moved to the next** Thursday when it falls on an observance."*

* **Falls on** — a day falls on an occurrence of another member of the set whose metadata includes every key and value of `:falls_on`; the day and the occurrence overlap. `:falls_on` may instead be a recurrence set whose occurrences the condition reads (user, 2026-09-28): a holiday set selected by type carries the holidays a kept conditional depends on, so a selection never changes a date.

* **Keep** — an occurrence is kept when every day `:at` away from its start falls on such an occurrence, and dropped otherwise.

* **Move** — an occurrence that falls on such an occurrence moves to the first span `Tempo.select/2` gives for `:to_next` after it (searching a week for a weekday, a year otherwise); one that does not stays. A selector says "the next Thursday" directly (`~o"4K"`), where a weekly recurrence (`R/../P1W/FL4KN`) would need a window built around the occurrence.

* **The tally** is every member's first-pass occurrences, a conditional's base occurrences included and its own never, so a moved occurrence is not seen by another conditional.

* **The window** — the first pass runs over the bound widened by the conditions' reach (the `:at` offsets both ways, the move's search span backward), so a bridge on the bound's first day sees the day before and an occurrence moved into the bound from before it is found; conditional results are then kept by start within the bound, and the other members materialise over the bound itself, exactly as without conditionals.

## Open questions

* Whether the filter is an equality map on metadata (serialisable, and enough for `type`) or a predicate function (more general, not serialisable).

* Whether a moved occurrence is itself seen by other conditionals (date-holidays: no — the tally is the first pass's).

## Tasks

* [x] Choose an option (user, 2026-09-27: Option 1).

* [x] Tempo: the conditional member (`keep_when/2`, `move_when/2`) and the second pass in `RecurrenceSet` materialisation, with tests. 2026-09-27.

* [x] Tempo: a guide section for conditional members — "Bridge days and moved holidays" in the holiday cookbook. 2026-09-27.

* [ ] tempo_holidays: emit the four rules as conditional members, validated against the concrete second pass over 2000–2035 and the conformance corpus.
