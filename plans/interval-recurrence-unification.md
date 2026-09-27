# Interval and recurrence unification

**Status:** in progress, 2026-09-27

The question (user, 2026-09-27): do we need separate interval, interval-set, recurrence and recurrence-set types, when an interval is a recurrence with one instance? And, following from it, `tempo_holidays` should return recurrences, each carrying its holiday's metadata the way a Tempo value or interval carries metadata. This records what holds today, the options, and the decisions.

**Decisions (user, 2026-09-27):** Option 2 — two types, the two states of one concept — with the four gaps closed. `Tempo.new/1`'s published `:metadata` option becomes opaque metadata on the value, IXDTF tags move to a `:tags` option, listed under Breaking changes for v1.7.0. In tempo_holidays: a holiday with observed days is one nested member; conditional members ([plans/recurrence-set-conditions.md](recurrence-set-conditions.md), Option 1) come before the reshape so `recurrences/2` is complete; `materialise/3` stays and returns an `IntervalSet`. Member metadata: `id` (the date-holidays rule), `name`, `type`, and `substitute: true` on observed days.

## What holds today

Verified on `extensions` at `0ab5676`.

* **Interval and recurrence are one struct.** `%Tempo.Interval{}` carries `recurrence: 1 | n | :infinity` beside `from`, `to`, `duration` and `repeat_rule`. `R1/2026-01-01/P1D` parses to the same value as `2026-01-01/P1D` — they compare equal and both print without `R1`. There is no recurrence type to remove.

* **The two set types differ by state, not by count.** `%Tempo.IntervalSet{}` holds materialised members only (`new/2` rejects an unbounded one), sorted, in a List, Tree or Lazy backend; the set algebra works on it and it is `Enumerable`. `%Tempo.RecurrenceSet{}` is a bag of rules (`members`, `metadata`) that needs a window before it can be enumerated, and is not `Enumerable`. `%Tempo.Set{}` is the ISO 8601-2 `{…}` literal.

* **One materialiser, one algebra.** `Tempo.to_interval/2` takes every value type — a `%Tempo{}`, an interval, a recurrence, a domain set, either set type — to concrete spans; one span comes back as `%Tempo.Interval{}`, several as `%Tempo.IntervalSet{}`. The set operations accept every type and materialise a `RecurrenceSet` against the other operand, or an explicit `:bound`.

* **Single-span operations refuse many.** `Tempo.relation(~o"R3/2026-01-01/P1D", …)` returns `{:error, %Tempo.MaterialisationError{reason: :recurring_interval}}`.

* **Metadata.** An interval, an interval set and a recurrence set carry an opaque `:metadata` map. A recurrence's metadata reaches every occurrence; a recurrence set's members keep theirs through materialisation; `intersection/3` keeps the left operand's by default and combines both with `metadata: :merge` or `{:merge, fun}`; `IntervalSet.coalesce/1` keeps the earlier member's. `%Tempo{}` has no metadata: `Tempo.new(…, metadata: m)` stores `m` in `extended.tags`, which `to_iso8601/1` writes out as IXDTF suffix tags (`2026Y[name=x]`).

* **Imports materialise.** `Tempo.ICal.from_ical/2` and `Tempo.JSCalendar.from_jscalendar/2` return an `IntervalSet` over a window, each event's properties in its interval's metadata; the rules themselves are not kept.

## Defects found

* `Tempo.relation/2` refuses a start-and-duration interval: `relation(~o"2026-01-01/P1D", ~o"2026-01-02/P1D")` is an error, "Operand :a has an open-ended endpoint (`:undefined`)", although the interval is bounded; with an explicit end it is `:meets`.

* `Tempo.to_iso8601/1` raises on a `%Tempo{}` with atom-keyed metadata (`Tempo.new(year: 2026, metadata: %{name: "x"})`), and writes an invalid IXDTF tag for a value with a space (`2026Y[name=Christmas Day]`).

* Materialising a `RecurrenceSet` drops the set's own metadata: `to_interval/2` builds the result with `IntervalSet.new(intervals)` alone.

* A `RecurrenceSet` cannot hold a `RecurrenceSet` (`MaterialisationError`, `:recurrence_set_member`).

## Options

### 1. One set type for rules and occurrences

Fold `RecurrenceSet` into `IntervalSet`: members may be rules, and a set of count-1 members is what `IntervalSet` is today. One name, and holidays, diaries and imports all return the same type. But every guarantee `IntervalSet` gives by construction — bounded, sorted members, which the sweep-line algebra, the interval-tree backend, `Enumerable`, `count`, `first` and `last` rely on — becomes a runtime state each operation must check, and each needs a window it may not have. The distinction does not go away; it moves inside every function.

### 2. Two states of one concept

Keep both structs as the two states of one thing, as RFC 5545 has a *recurrence set* (DTSTART, RRULE, RDATE, EXDATE) and its instances in a time range: `RecurrenceSet` is the definition — window-free, possibly infinite, introspectable, each member with its metadata — and `IntervalSet` its occurrences. Materialisation over a window is the one bridge, and the set algebra already crosses it implicitly. The type says whether a window is needed; a single interval-or-recurrence stays one struct, as today.

### 3. One struct for everything

Collapse `%Tempo{}` as well. Rejected: `%Tempo{}` is the ISO 8601 time value, with the resolution semantics intervals are built from, and single-span operations — Allen relations, `to_date/1`, the duration predicates — need exactly one span, which only a type (or a runtime check at every call) can promise.

## Recommendation

Option 2. The interval/recurrence split the question starts from is already gone; the split that remains is definition versus occurrences, and it is real for any set holding an infinite rule. To make the two states interchangeable in practice:

* Give `%Tempo{}` an opaque `:metadata` like the other types, separate from the IXDTF tags `to_iso8601/1` writes.

* Carry a `RecurrenceSet`'s metadata to the `IntervalSet` it materialises.

* Let a `RecurrenceSet` member be a `RecurrenceSet`, so one definition (a holiday and its observed days) is one member with one metadata map.

* Fix `relation/2` for start-and-duration intervals.

## Consequence for tempo_holidays

Holidays become recurrences with metadata, and `%Holiday{}` leaves the public API (`tempo_holidays` is not on hex, so nothing is deprecated); `%Rule{}` stays the compiler's IR.

* `Tempo.Holidays.recurrences(:AU)` returns `{:ok, %Tempo.RecurrenceSet{}}`: one member per holiday — its recurrence, or a nested set when it has observed days — with `metadata: %{name: "Christmas Day", type: :public, …}`, and `%{territory: :AU}` on the set.

* Occurrences come from Tempo: `Tempo.to_interval_set(holidays, bound: ~o"2026")`, each occurrence labelled; `Tempo.intersection(diary, holidays, metadata: :merge)` labels each clash with the holiday it hit.

* Open for the user: the metadata keys (a stable id beside the name, since names are not unique; a flag on observed days); the 4 conditional holidays, which cannot be members until [plans/recurrence-set-conditions.md](recurrence-set-conditions.md) lands; and whether `Tempo.Holidays.materialise/3` stays — returning an `IntervalSet` — for name-aware coalescing, the conditional pass and the `:day_start` projection.

## Tasks

* [x] Choose an option, and settle the tempo_holidays questions above (user, 2026-09-27).

* [x] Tempo: opaque `:metadata` on `%Tempo{}` (`Tempo.new/1`'s `:metadata`, `Tempo.metadata/1`, `Tempo.put_metadata/2` on every value type), IXDTF tags through `:tags`, validated. 2026-09-27.

* [x] Tempo: a `RecurrenceSet`'s metadata reaches its materialised set; nested `RecurrenceSet` members; `IntervalSet.metadata/1`, `RecurrenceSet.members/1` and `metadata/1`. 2026-09-27.

* [x] Tempo: a start-and-duration or duration-and-end interval answers every single-interval function as its two-endpoint form — 22 functions raised, crashed or read it as open-ended, not only `relation/2`. 2026-09-27.

* [ ] tempo_holidays: `recurrences/2` returns a `RecurrenceSet` of holiday recurrences with metadata; `%Holiday{}` leaves the public API; tests, guides and the conformance harness follow.
