# Conditional recurrence-set members

**Status:** draft, 2026-09-27

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

## Open questions

* Whether the filter is an equality map on metadata (serialisable, and enough for `type`) or a predicate function (more general, not serialisable).

* Whether a moved occurrence is itself seen by other conditionals (date-holidays: no — the tally is the first pass's).

## Tasks

* [ ] Choose an option (user).

* [ ] Tempo: the conditional member and the second pass in `RecurrenceSet` materialisation, with tests and a guide section.

* [ ] tempo_holidays: emit the four rules as conditional members, validated against the concrete second pass over 2000–2035 and the conformance corpus.
