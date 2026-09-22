# Refactor: converge `I` on ISO 8601-2 §12.9 position, retire `V`

**Status:** implemented, 2026-09-22

Implementation blueprint for retiring the invented `V` (BYSETPOS) designator and making `I` the ISO 8601-2 §12.9 position / set-position designator (applied last over the resolved set, canonical order weekday-then-`I`). Companion to [selection-extensions.md](selection-extensions.md). This is the saved map; implement from here.

## 0. The model change

Today Tempo carries three selection operations across three token shapes:

| Operation | RRULE origin | Today's token | Today's `~o` form | Rendered by |
|---|---|---|---|---|
| Per-weekday ordinal ("2nd Monday", "1st & 3rd Mon") | `BYDAY=2MO` | `{:byday, [{ord, day}]}` | `2I1K` (instance left of weekday) | inspect.ex:691 |
| Set-position over merged resolved set | `BYSETPOS=-1` | `{:set_position, n}` | `-1V` | inspect.ex:703 |
| Raw postfix instance (currently a no-op in the materialiser) | — | `{:day_of_week, d}, {:instance, n}` | `3K1I` | inspect.ex:682 + AST order |

ISO §12.9 collapses the first two designators into one: `I` **is** set-position, applied last over the whole resolved set, written right-of / lower-order-than the weekday (`1K1I` = first Monday). Target model:

* **One position token, `:instance`**, carrying BYSETPOS semantics. **Retire `:set_position`** (rename every use to `:instance`).
* **Canonical order weekday-then-position** (`dK nI`), enforced by no longer stripping `:instance` in `Unit.ordered?/1`, so a position-first spelling fails to parse.
* **`:byday` survives only as an adapter-internal, RRULE-only token** for the one case ISO cannot express: ordinals on multiple distinct weekdays (`BYDAY=2MO,2WE`). Single-distinct-weekday ordinals (`2MO`, `-1FR`, `4TH`, `1MO,3MO`) **lower to `day_of_week + instance`** and become ISO-conformant.

This also fixes a latent bug: the postfix `3K1I` form currently reaches the materialiser and its `:instance` is silently dropped by the catch-all (selection.ex:340). After the refactor it is a real set-position selection.

## 1. AST shapes (verified)

A selection is `%Tempo{time: [selection: <keyword-list>]}` (built by `Tempo.RRule.Rule.to_selection/1` rule.ex:190, or the ISO parser parser.ex:338-345).

`FL5M-1I1KN` today → tokenizer emits `[month: 5, instance: -1, day_of_week: 1]`; parser.ex:344 `fold_byday_selection/1` (parser.ex:473-501) folds the adjacent pair → `[selection: [month: 5, byday: [{-1, 1}]]]`.

`FL1K-1VN` today → `[selection: [day_of_week: 1, set_position: -1]]` (no fold; `:instance` absent).

After the refactor both converge (weekday then position, one token):

```
FL5M1K-1IN  ->  [selection: [month: 5, day_of_week: 1, instance: -1]]
FL1K-1IN    ->  [selection: [day_of_week: 1, instance: -1]]
```

Materialisation: `month` LIMIT → `day_of_week` EXPAND (all Mondays) → `instance` set-position `-1` (last) → last Monday.

## 2. lib/iso8601/tokenizer/grammar.ex

* Line 375 `maybe_negative_integer_or_integer_set("V", :set_position, min: 1)` in `selection_date_element/0` (365) — **delete** (only place `V` is tokenized).
* Lines 373-374 the `V`/`Q` comment — update to `Q` only.
* Line 396 `selection_instance/0` = `maybe_negative_integer_or_integer_set("I", :instance, min: 1)` — **keep**. `maybe_negative_integer_or_integer_set` (numbers.ex:250) already accepts `-1I`, `{1,3}I`, `[1,3]I`, so no grammar work for negative/set positions.
* Recommend hard removal of `V` (not a deprecated alias): the AST token and `to_iso8601` output are internal, the RRULE string is the wire format.

## 3. lib/iso8601/unit.ex

* Line 212 `non_scale_token?({unit, _value}) when unit in [:instance, :set_position, :wkst]` — remove `:set_position` and `:instance`. Line 211 `non_scale_token?(:instance), do: true` — delete.
  * Why drop `:instance` from the strip list: `@sort_keys` (27) ranks `instance: 3` (finest). With `:instance` no longer stripped, `Unit.ordered?/1` (204) sees `[…, day_of_week(18), instance(3)]` as strictly decreasing → ordered; the position-first `[instance(3), day_of_week(18)]` is increasing → rejected. This *enforces* the ISO weekday-then-position order. Keep `:wkst` stripped (context-only, no sort_key).
* Lines 199-203, 24-25 comments (`2I1K`) — update.
* No `sort_key`/`@sort_keys` change; `:set_position` and `:wkst` were never passed to `Unit.sort/1` (not in `@sort_keys`) — removing `:set_position` leaves no dangling `Map.fetch!`.

## 4. lib/iso8601/parser.ex (the crux)

`fold_byday_selection/1` + `byday_pairs/3` (463-501) exist to fold instance-left ISO text (`2I1K`) into `:byday`. Under the new order, **ISO text no longer produces `:byday`** — `dK nI` parses straight to `[day_of_week: d, instance: n]`, handled by the materialiser (§5).

* Delete `fold_byday_selection/1` + `byday_pairs/3`; drop `|> fold_byday_selection()` from the three pipelines at 270, 333, 344.
* Consequence: round_trip_test.exs:72 and rrule_test.exs:185-193 change — ISO `FL1K2IN` now yields `[day_of_week: 1, instance: 2]`.
* `Unit.ordered?` guards (parser.ex:258, 324, 339) need no code change but now reject the legacy position-first order once §3 lands (intended).

## 5. lib/tempo/rrule/selection.ex (materialiser)

`selection_fn/2` (tempo.ex:5195) delegates to `Selection.apply/4` — the single engine.

* `@application_order` (152-166): replace trailing `:set_position` (165) with `:instance`; must remain **last**.
* `apply_entry({:set_position, positions}, …)` (331-337) → rename to `apply_entry({:instance, positions}, …)`, body unchanged (`pick_set_positions/2` 1125-1143 already correct). Optionally rename `pick_set_positions`→`pick_positions`.
* Catch-all `apply_entry(_entry, …)` (340) currently swallows stray `:instance`; the real clause fixes the `3K1I` no-op bug.
* `expand_index_ranges/1` (142) already expands `instance: [1..3]` — no change.
* Keep `:byday` handling (`apply_entry({:byday, pairs}, …)` 309; `expand_byday_pairs` 1025; `resolve_byday_pair` 1079/1086) for the retained multi-weekday case.
* Doc table line 34 and comments 114, 331 — update terminology.

## 6. lib/tempo/rrule/rule.ex (RRULE/cron → selection, single source)

* Line 204 `push_by(rule.bysetpos, :set_position)` → `push_by(rule.bysetpos, :instance)`. `push_by` appends then the list is reversed (206) → `:instance` lands last / right.
* `push_byday/2` (230-239): the byday-lowering decision. Today emits `{:day_of_week,…}` when all ordinals nil, else `{:byday, entries}`. Change: when every entry has a non-nil ordinal and they share one distinct weekday, emit `[{:day_of_week, day}, {:instance, ords}]` (ISO `dK nI`); keep `{:byday, entries}` only for multi-distinct-weekday (`[{2,1},{2,3}]`, `[{1,1},{-1,5}]`, mixed `[{nil,1},{2,2}]`).
  * Single-weekday multi-ordinal (`BYDAY=1MO,3MO` → `[{1,1},{3,1}]`) lowers to `[day_of_week: 1, instance: [1,3]]`.
* `to_selection/1` doctest (180-181): `%Rule{byday: [{2,1}]}` → update expected from `~o"L2I1KN"` to `~o"L1K2IN"`.

## 7. lib/tempo/rrule/encoder.ex (selection → RRULE)

* Line 218 `encode_by_entry({:set_position, v})` → `{:instance, v}`, body `["BYSETPOS=#{list_csv(v)}"]` unchanged.
* Consequence: `[day_of_week: 1, instance: 2]` now encodes `BYDAY=MO` + `BYSETPOS=2` (valid RFC 5545, equals `BYDAY=2MO`), changing the emitted string vs today's `BYDAY=2MO`.
  * Decision: recommend the simpler `BYDAY=MO;BYSETPOS=n` emission and update round-trip expectations, unless byte-for-byte `BYDAY=nMO` fidelity is needed (then add a recombine pre-pass).
* Comment 182-185 ("no more disambiguation…") — now partly false; update.

## 8. lib/inspect.ex and lib/explain.ex

**inspect.ex**

* Line 703 `inspect_value({:set_position, position}) -> [inspect_list(position), ?V]` — delete. A standalone position flows through the `{:instance, …}` clause.
* Line 682 `inspect_value({:instance, instance}) -> [inspect_value(instance), ?I]` — keep. The selection-list walker (296-311) preserves AST order → emits `dK nI` with weekday-then-instance AST.
* Lines 691-696 `{:byday, entries}` renders instance-left (`2I1K`). For the retained multi-weekday byday, flip to weekday-then-position (`dK nI`) — or raise `Iso8601EncodeError` (like `:nearest_weekday` 711) to force `to_rrule/1`. Recommend flip-and-document (preserves round-trip).
* Lines 698-702 `V`/`Q` comment — rewrite for `Q` only.

**explain.ex**

* Line 899 `selection_clause({:set_position, p}) -> "keeping #{ordinals_phrase(p)} occurrence"` — rename head to `{:instance, p}` (there is currently no `{:instance,…}` prose clause; postfix instance falls through the catch-all 900, i.e. unexplained today). Keep the wording.
* Line 895 `{:byday, pairs}` / `byday_phrase/1` (902) — keep for retained byday. explain_test.exs:233 expects `"in May, on the last Monday"` from `FL5M-1I1KN`; after lowering, reconstruct prose from `[month:5, day_of_week:1, instance:-1]` — add a small combiner so the holiday prose reads "on the last Monday" rather than "on a Monday, keeping the last occurrence".

## 9. Other consumers (confirmed minimal)

* lib/jscalendar.ex — 449 `bysetpos: rule.by_set_position`, `byday/1` (472) operate on `%Rule{}` fields, not tokens. No change (routes through `Rule.to_selection`).
* lib/tempo/rrule.ex — `parse_kv("BYSETPOS"…)` (186), `parse_kv("BYDAY"…)` (188) populate `%Rule{}`. No change.
* lib/tempo/rrule/expander.ex — 273 `bysetpos: r.by_set_position` builds a `%Rule{}`. No change.
* lib/tempo/cron.ex — builds `:byday` (389), never emits `:set_position`/`:instance`. No change.
* lib/tempo.ex — 5410 `calendar_anchor_unit(unit) when unit in [:byday, :day_of_week, :day_of_year, :instance]` keeps `:instance`; but verify `bound_anchor` (5353) / `anchor_unit/1` (5390, reads `List.last(selection)`) anchors correctly when the last token is `:instance` (a bare position) → `:day` grain. Doc 1518 — update.
* lib/tempo/interval.ex — 116 comment only.
* lib/tempo/exception/iso8601_encode_error.ex — 8 comment (BYSETPOS now has an ISO form via `I`). If §8 chooses "raise for multi-weekday byday", add a `construct: :byday` message clause (29-36).

## 10. Where order is enforced/assumed

1. `Unit.ordered?/1` (unit.ex:204-250) — the real gate; strips `:instance`/`:set_position` today (211-212) so order is unchecked. After §3, decreasing-sort-key validation enforces weekday(18)-before-instance(3), rejects position-first. Called at parser.ex:258, 324, 339.
2. inspect.ex walker (296-311) — preserves AST order, no sort; emitted order == AST order.
3. inspect.ex `{:byday,…}` (691-696) — the one place emitting position-left; must flip (§8).
4. `Rule.to_selection/1` (rule.ex:190-211) — push order fixed; `push_by(bysetpos/instance)` (204) appended then reversed → lands last/right.
5. `Selection.apply` `@application_order` (152-166) — runtime order; position already last.

## 11. AST token decision

Unify into a single `:instance` token; retire `:set_position`. Grammar already maps `I → :instance` (grammar.ex:396) and inspect maps `:instance → I` (682); `:instance` has a `@sort_keys` entry (3), `:set_position` has none (a latent `Map.fetch!` hazard). The two operations genuinely converge under §12.9.

Keep `:byday` distinct and adapter-internal only for the irreducible multi-distinct-weekday case (`BYDAY=2MO,2WE`, `BYDAY=1MO,-1FR`, mixed). Single-distinct-weekday ordinals lower to `day_of_week + instance`.

## 12. Tests and docs to update

Executable gates:

* test/tempo/iso8601/round_trip_test.exs:72,73,78 — `FL2I1KN` (order flip), `F1YL9M3K1IN` (postfix now real position), `FL1K-1VN`→`FL1K-1IN`; comment 76-77.
* test/tempo/rrule_test.exs:115-126 — `[…, set_position: -1]` → `instance: -1`; 96-105, 173-176, 185-193, 215-223.
* test/tempo/interval_regression_test.exs:87-111 — AST `[day_of_week: 5, instance: -1]` and strings `FL2I1KN`, `FL-1I5KN`, `FL1I1K3I1KN` (flip to `…1K…I`); comment 90-91.
* test/tempo/explain_test.exs:230-234 (order + prose combiner), 267-268 (`2018YL1K1IN` already ISO order keeps passing; `L2I1KN` flips).
* test/tempo/round_trip_test.exs:78, test/tempo/rrule/{selection,rfc5545_conformance,expander,wkst_and_edges}_test.exs — mostly materialised-date assertions (insensitive to rename) except those asserting token shape (expander_test.exs:53-62) or emitted RRULE/`~o` strings.

Guides/doctests:

* guides/iso8601-conformance.md §5 (177-235) — headline rewrite: `I` becomes position; delete the `V` section (191-216).
* guides/shared-ast-iso8601-and-rrule.md (14, 95-99) — rewrite `V`→`I`.
* guides/holidays.md (71-73) — `FL5M-1I1KN`→`FL5M1K-1IN`, `FL10M2I1KN`→`FL10M1K2IN`.
* guides/cookbook.md (540-546), guides/ical-integration.md (203, 228), guides/rfc5545_rrule_conformance.md (42, 54).

## Out of scope (separate)

The day-range materialisation bug — `FL11M{11..17}D5K1IN` → `Calendrical.Base.Month.days_in_month/3` FunctionClauseError at `expand_candidate_days/2` (selection.ex:802) — was predicted as a separate fix, but the token refactor resolved it: the crash was an artefact of the deleted `fold_byday_selection` path producing a mis-shaped `:byday` token. Post-refactor, `FL11M{11..17}D5K1IN`, Election Day (`FL11M{2..8}D2K1IN`), and month-range + day patterns all materialise correctly to concrete dates (covered in `test/tempo/rrule/selection_test.exs`, "US holiday patterns").
