# Consumer-extensible computed events

**Status:** implemented, 2026-09-23 — `Tempo.Event.Resolver` and the `:event_resolvers` registry; pending a release version.

## Problem

`Tempo.Event` resolves a fixed set of `(name)E` computed events — Easter, the equinoxes/solstices, the first new moon, and the 24 solar terms. The `(name)E` selection is a clean abstraction, and consumers want their own: a fiscal calendar's quarter starts, a liturgical feast, any date fixed by an algorithm rather than the calendar. The question was how a consumer registers `name → resolver`, how that reaches the selection resolver at materialise time, and how an unknown name still degrades to zero occurrences.

## What already held

* The grammar is calendar- and name-blind: `(anything)E` parses to `{:event, name}` with no allow-list, so a consumer name needs no grammar change — verified `R/../P1Y/FL(fiscal-year-start)EN` parses today.
* `Tempo.RRule.Selection` already degrades gracefully: `expand_event/2` and `on_event_date?/2` wrap `Tempo.Event.date/3` in a `with` whose `else` yields `[]` / `false`, so an unknown event already materialises to an empty set — verified `(brigadoon)E` bound to a year returns `#Tempo.IntervalSet<[]>`.

So the only gap was the lookup inside `Tempo.Event.date/3`: it returned `{:error, {:unknown_event, name}}` for anything not built in.

## Options

1. **An option on `to_interval/2`** (`events: %{name => fun}`) — explicit, no global state, but the resolver must thread from `to_interval/2` through `RRule` → `Selection` → `expand_event` on every call, and a consumer would repeat it at every call site. Rejected: invasive, and consumer events are an app-global fact, not a per-call one.
2. **A config map of `name → {module, function}`** — least ceremony, but no grouping and MFAs in config read less cleanly than a module.
3. **A behaviour + config-registered modules** — chosen. It matches Tempo's two existing extension points exactly: `Tempo.Clock` (a config-selected behaviour module under `:ex_tempo`) and `Tempo.IntervalSet.Backend` (a behaviour). No change to any public signature; the registry is read at materialise time inside `Tempo.Event.date/3`.

## Decision

`Tempo.Event.Resolver` is a behaviour with `known/0` (the names it owns) and `date/3` (`name, year, calendar` → `{:ok, Date.t()} | {:error, term()}`). Consumers register a list:

    config :ex_tempo, :event_resolvers, [MyApp.Events]

`Tempo.Event.date/3` checks the built-ins first, then offers an unclaimed name to each registered resolver in turn (`Enum.find_value` over `known/0`); the first to claim it computes it. `known/0` merges the built-ins with every resolver's `known/0`. A name no resolver claims stays `{:error, {:unknown_event, name}}`, which `Selection` already turns into zero occurrences. The registry is read (not compiled) each call, so it can be set at compile or run time, and `List.wrap` accepts a single module as well as a list.

Built-ins are checked before resolvers, so a consumer cannot shadow `easter`. A resolver returns a tagged tuple rather than raising (there is no `try`/`rescue`); a resolver that returns a non-`{:ok, Date}` value degrades to zero occurrences like any unresolvable event.

## Tasks

* [x] `Tempo.Event.Resolver` behaviour (`lib/event/resolver.ex`) with a worked example in the moduledoc.
* [x] `Tempo.Event.date/3` consults `registered_resolvers/0` on a built-in miss; `known/0` merges registered names; `mix.exs` groups `Tempo.Event.*` under "Computed events".
* [x] Tests (`test/tempo/event/resolver_test.exs`, `async: false` with config restored on exit): resolution, `known/0` merge, built-ins unaffected, a registered `(name)E` selection materialising against a bound, and both unknown-name and resolver-error degrading to zero occurrences.

## Open

* [ ] Optional ergonomic sugar (`Tempo.Event.register/1` at runtime, or a single-event `{module, function}` config form) — deferred until a consumer asks; the behaviour covers the need today.
