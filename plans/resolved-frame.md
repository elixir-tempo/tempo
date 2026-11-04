# A resolved frame

**Status:** planning, 2026-11-05

Decision 95: an operation resolves what it asks of its zone and its calendar once, and hands it on with a resolved frame beside the values, through the engine; and nothing writes `:persistent_term` at runtime. This document is the shape of the work.

## The problem

Measured on 2026-11-05 (Apple M1 Max, Elixir 1.20.5, OTP 29.1.2), a question of a named zone (`Tempo.Zone.offset_at_utc/2` and the rest) costs about 220 ns:

| Part | Cost |
|---|---|
| `Tempo.Zone.database/0`, two application env reads | 84 ns |
| `Tempo.Zone.Table.of/3`, the table found in `:persistent_term` | 86 ns |
| `Tempo.Zone.Table.offset_at/2`, the search in the table | 39 ns |

A rule asks about 14 times an occurrence, from `Tempo.Walk.wall/2` (about half), `Tempo.Scale.line_extent_of/5`, `Tempo.Spans`, `Tempo.Expand`, `Tempo.Select` and `Tempo.Recurrence`: 34 to 41% of the time of the daily, weekday and hourly rules of `bench/against_1_6_bench.exs`.

Two sites write `:persistent_term` at runtime, each write a system-wide GC: `Tempo.Zone.Table.of/3` (a zone's table on its first question, and again each time it grows ten years) and `Tempo.Calendar.first_weekday/1` (each calendar's answer on first use).

## What the measurements rule out

* **Caching the database globally.** A database set at runtime (`Calendar.put_time_zone_database/1`) takes effect for the next operation: the README says so and `zone_database_test.exs` holds Tempo to it. Within one operation it is stable (the user, 2026-11-05).

* **Building a zone's table for each operation.** From the database's listed periods it is about 25 µs, but grown past their end (2032 for `tz`) by sampling it is about 42 ms, so the tables need a store that outlives an operation.

* **Reading a table from ETS at each question.** A read copies the term out: 787 ns for America/Chicago (262 changes), 107 ns for Asia/Kolkata (8). Once an operation it is cheap; at each question it is more than today.

## The design

* **The store.** A zone's table is kept in an ETS table owned by `Tempo.Zone.Store`, a process under Tempo's own application supervisor (rule 12): built from the listed periods on a zone's first question, grown where a question reaches past it, keyed by database, data version and zone. A host may run the store in its own supervision tree (`Tempo.Zone.Store.child_spec/1`, with `runtime: false`). Nothing is written to `:persistent_term`.

* **The resolved frame.** Where an operation begins, the engine resolves its frame: the frame it has today (`calendar`, `zone`, `shift`, `frame`) and, for a named zone, the zone's table read once from the store, and the calendar's first weekday. The engine functions on the hot paths take the resolved frame beside the value, where they now rebuild a frame from the value (`Spans.frame_of/1`), and `Tempo.Zone`'s questions take the table from it. A table that does not reach a question's tick is grown through the store and handed on.

* **A calendar's first weekday** is asked of the calendar, not kept: `info().weeks.first_day` where the calendar has `info/0` (every Calendrical calendar, `Localize.Calendar.ISO`), Monday for `Calendar.ISO`, and the probe `first_weekday/1` makes today for any other calendar (Tempo's six week-start calendars, a caller's own). The probe is about 100 ns on a calendar built on the ISO calendar; the resolved frame carries the answer through a walk.

* **The cost to a single question.** An operation that asks its zone once pays the store's read (up to about 0.8 µs) where it paid 220 ns; one that asks fourteen times an occurrence pays it once.

## Tasks

* [ ] **First weekday asked of the calendar** — `Tempo.Calendar.first_weekday/1` reads `info().weeks.first_day`, Monday for `Calendar.ISO`, and probes any other calendar; the `:persistent_term` write goes. A test holds every calendar Tempo knows to the probe's answer.

* [ ] **The zone store** — `Tempo.Application` and `Tempo.Zone.Store` (an ETS table owned by a supervised process, with `child_spec/1`), and `Tempo.Zone.Table.of/3` reading and writing it in place of `:persistent_term`. Docs for both forms of supervision; a test of the host-owned form.

* [ ] **The resolved frame** — the frame resolved where an operation begins, and `Tempo.Zone`'s questions taking its table; then each hot path in turn, measured: `Tempo.Walk.wall/2` and `Tempo.Matcher`, `Tempo.Scale.line_extent_of/5`, `Tempo.Spans`, `Tempo.Expand`, `Tempo.Select`, `Tempo.Recurrence`, `Tempo.Shift`.

* [ ] **Measured against 1.6.4** — the rule cases of `bench/against_1_6_bench.exs` side by side, and the table in `TODO.md` brought up to date.
