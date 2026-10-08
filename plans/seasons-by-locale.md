# Seasons by locale

**Status:** planning, 2026-10-08

Blocked on Localize giving a territory's hemisphere. The decisions below are the user's, taken on 2026-10-08; the open questions are to be put before the work starts.

## The problem

ISO 8601-2 §4.8.1 lists twelve seasons: 21 to 24 are spring, summer, autumn and winter "independent of location", 25 to 28 the same four of the northern hemisphere, and 29 to 32 of the southern. §3.1.3 notes that "a single calendar date may represent different seasons depending on local customs or location, such as the difference between the northern or southern hemispheres". The standard does not say whether a season is reckoned by the months or by the sun.

Tempo reads a season into its dates when it parses, and the value is an interval from then on:

```elixir
Tempo.from_iso8601("2026-21")  # {:ok, ~o"2026Y3M/6M"}, the northern meteorological spring, wherever it is read
Tempo.from_iso8601("2026-25")  # {:ok, ~o"2026Y3M20D/6M21D"}, the March equinox to the June solstice
Tempo.from_iso8601("2026-29")  # {:ok, ~o"2026Y9M23D/12M21D"}, the southern spring
```

So a season of 21 to 24 is the northern one for a reader in Australia, where spring is September to November, and the value does not remember that it was written as a season.

## Decisions

* **The codes stay as they are** — 21 to 24 are meteorological, whole months, and 25 to 32 astronomical, each from an equinox or a solstice to the next, as Astro computes them. An astronomical season is written with 25 to 32, and a season of 21 to 24 is not to be switched to the astronomical by an option.

* **A territory's hemisphere is Localize's to give** — neither CLDR nor Localize records one, and it is territory data. Tempo asks `Localize.Territory.hemisphere/1` and holds no table of its own.

* **A season of 21 to 24 is resolved by a locale or a territory given where it is read** — an option of `Tempo.from_iso8601/2` and `Tempo.parse/2`.

* **With no locale or territory given it is not resolved** — it stays an abstract season in the value until it is composed with a locale or a territory, and is never expanded when the `~o` sigil is compiled. This replaces the first answer of the day, which had the sigil resolve the season at run time by the current locale.

## What is asked of Localize

```elixir
Localize.Territory.hemisphere(:AU)  # {:ok, :southern}
Localize.Territory.hemisphere(:GB)  # {:ok, :northern}
```

* It takes what `Localize.Territory.info/1` takes: a territory, or a language tag, whose territory is asked.

* A territory the equator crosses (Brazil, Indonesia, Kenya, Ecuador) has one answer, which is Localize's to choose.

* A region that is no one territory (`:"001"`) and a territory it does not know are an error.

## Open questions

* **What composes an abstract season with a locale or a territory** — the options of the readers are decided. After the value is read: an option of `Tempo.to_interval/2` and the functions built on it, a function of its own, or both.

* **Whether the application's `:default_territory` and the current locale count as given** — `Tempo.Territory.resolve/1` falls back to them. The user's words are "if no locale/territory is provided", which read as an explicit one only.

* **Whether a region override in the value counts** — `2026-21[u-rg=auzzzz]` names a territory in the text itself.

* **What an abstract season answers until it is resolved** — written back as it was read (`2026-21`), worded by `Tempo.explain/1` as the season it is, and for an operation that needs its dates a named error that says to give a locale or a territory, or the empty answer.

* **How the value holds it** — a unit of its own in the value's units (`[year: 2026, season: 21]`), and what a range of seasons (`2026-21/2026-23`), a season in a set, and a season with a day after it (`2026-21-15`, its fifteenth day) become.

## The shape of the work

The parser keeps a season of 21 to 24 as a unit where no territory is given, and expands it as it does today where one is, with the months of the territory's hemisphere. A season of 25 to 32 is expanded as it is today. The sigil then needs no run-time form: what it compiles is the abstract season.

Every function that takes a value takes the new shape, which is the cost of this plan: the conversion, the walk, comparison and the set operations, formatting, `Tempo.explain/1`, the inspect protocol and the operation matrix, whose cells for a season are new.

## Tasks

* [ ] **The hemisphere from Localize** — `Localize.Territory.hemisphere/1`, as above. Blocked on Localize.

* [ ] **The open questions** — put to the user before any of the work below.

* [ ] **A season kept in the value** — the parser, the value's units, `inspect` and `Tempo.to_iso8601/1`.

* [ ] **A season resolved** — the readers' options, the hemisphere's months, and whatever the answers to the open questions name.

* [ ] **Every operation on an abstract season** — the named error or the answer, the matrix's cells, the guides.
