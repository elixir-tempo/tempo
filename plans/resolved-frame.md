# Zone tables read once, and no runtime `:persistent_term`

**Status:** implemented (v2.5.0), 2026-11-06

Decisions 95 and 96: nothing writes `:persistent_term` at runtime, and the time zone database is Tempo's for as long as it runs, so each zone's table is built once as Tempo starts. Decision 95 planned a resolved frame carried through the engine; decision 96 replaced it with static tables, which give most of its gain. The file keeps its first name so that links to it hold.

## The problem

Measured on 2026-11-05 (Apple M1 Max, Elixir 1.20.5, OTP 29.1.2), a question of a named zone (`Tempo.Zone.offset_at_utc/2` and the rest) costs about 220 ns:

| Part | Cost |
|---|---|
| `Tempo.Zone.database/0`, two application env reads | 84 ns |
| `Tempo.Zone.Table.of/3`, the table found in `:persistent_term` | 86 ns |
| `Tempo.Zone.Table.offset_at/2`, the search in the table | 39 ns |

A rule asks about 14 times an occurrence, from `Tempo.Walk.wall/2` (about half), `Tempo.Scale.line_extent_of/5`, `Tempo.Spans`, `Tempo.Expand`, `Tempo.Select` and `Tempo.Recurrence`: 34 to 41% of the time of the daily, weekday and hourly rules of `bench/against_1_6_bench.exs`.

Two sites write `:persistent_term` at runtime, each write a system-wide GC: `Tempo.Zone.Table.of/3` (a zone's table on its first question, and again each time it grows ten years) and `Tempo.Calendar.first_weekday/1` (each calendar's answer on first use).

## What the measurements showed

* **The database could not be cached while it could change at runtime.** Once the user ruled it Tempo's for as long as Tempo runs (decision 96), it is read once, as Tempo starts.

* **A zone's table is cheap to build from the database's list, and dear to grow past it.** Every zone name Localize knows (601) is listed by `tz` but four; all their tables take about 20 ms and 764 KB, through September 2032 at the earliest. Past the list `tz` makes periods from its rules at about 32 µs a question, and growing a table by sampling takes about 42 ms a decade a zone.

* **An ETS read copies a table out:** 787 ns for America/Chicago (262 changes), 107 ns for Asia/Kolkata (8), so ETS serves only the tables grown past the static ones.

## The design

* **Static tables.** `Tempo.Supervisor`, Tempo's supervision tree, starts `Tempo.Zone.Table` first: it reads the configured database and builds the table of every zone it lists, by Localize's names (`Localize.DateTime.Timezone.timezones/0`, canonical names and aliases), through the end of its list, and writes them to `:persistent_term` once, with the database. A zone question reads that map once and searches the zone's table: 139 ns, where it was 220.

* **The store.** A question past a static table, of a zone the database lists no changes for, or of a database that lists none (`tzdata`, `zoneinfo`), takes a table built and grown in an ETS table owned by `Tempo.Zone.Store`, the tree's one process.

* **Supervision.** Tempo's application starts `Tempo.Supervisor`; a host that sets `runtime: false` lists it in its own tree (rule 12). Where the tree has not started, every question is answered from the configured database, more slowly.

* **A calendar's first weekday** is asked of the calendar, not kept: the day Tempo's six week-start calendars are written to begin on (`Tempo.Calendar.week_start/1`), else `info().weeks.first_day` of the calendar's implementation where it has `info/0`, else the probe of a day's two numberings. It is 42 ns or less for every calendar.

## Tasks

* [x] **First weekday asked of the calendar** — `Tempo.Calendar.first_weekday/1` reads the written week start, else the implementation's `info().weeks.first_day`, else probes; the `:persistent_term` write is gone. 2026-11-05.

* [x] **Static zone tables and the store** — `Tempo.Supervisor` (public, with `child_spec/1`), `Tempo.Zone.Table` built once as it starts, `Tempo.Zone.Store` for tables past the static ones, the database read once; README, moduledocs, tests of the host-owned form and of no tree running. 2026-11-05.

* [x] **Measured against 1.6.4** — the rule cases side by side, and the table in `TODO.md` brought up to date: the rules within the static tables 16 to 25% faster, the two past 2032 slower (the ETS store copies a grown table at each question). 2026-11-05.

* [x] **Static tables through 2100** — `tz`'s rule-made changes listed with its compiled ones through 2100, generated once for each rule, start and offset the zones share (decision 98): the build is 40 ms and 1.17 MB, and the yearly and last-weekday rules 1.4 and 3.0 ms. 2026-11-06.

### Deferred

* [ ] **The resolved frame** — carrying a zone's table through the engine beside the values would take a question from 139 ns to the 39 ns search; deferred by decision 96, to be measured again if the zone's share of a rule warrants it.
