# Seasons by locale

**Status:** in progress, 2026-10-09

Localize gives a territory's hemisphere since 2026-10-09 (`Localize.Territory.Hemisphere`). The decisions below are the user's, taken on 2026-10-08 in three rounds and, for the four questions that were open, on 2026-10-09.

## The problem

ISO 8601-2 §4.8.1 lists twelve seasons: 21 to 24 are spring, summer, autumn and winter "independent of location", 25 to 28 the same four of the northern hemisphere, and 29 to 32 of the southern. §3.1.3 notes that one calendar date can be of different seasons by local custom or by place, the two hemispheres being its example. The standard does not say whether a season is reckoned by the months or by the sun.

Tempo reads a season into its dates when it parses, and the value is an interval from then on:

```elixir
Tempo.from_iso8601("2026-21")  # {:ok, ~o"2026Y3M/6M"}, the northern meteorological spring, wherever it is read
Tempo.from_iso8601("2026-25")  # {:ok, ~o"2026Y3M20D/6M21D"}, the March equinox to the June solstice
Tempo.from_iso8601("2026-29")  # {:ok, ~o"2026Y9M23D/12M21D"}, the southern spring
```

So a season of 21 to 24 is the northern one for a reader in Australia, where spring is September to November, and the value does not remember that it was written as a season.

## Decisions

* **The codes stay as they are** — 21 to 24 are meteorological, whole months, and 25 to 32 astronomical, each from an equinox or a solstice to the next, as Astro computes them. An astronomical season is written with 25 to 32, and a season of 21 to 24 is not to be switched to the astronomical by an option.

* **A territory's hemisphere is Localize's to give** — it is territory data, and Tempo asks `Localize.Territory.Hemisphere.hemisphere/1` and holds no table of its own.

* **A season of 21 to 24 is resolved by a locale or a territory given where it is read** — an option of `Tempo.from_iso8601/2` and `Tempo.parse/2`.

* **With no locale or territory given it is not resolved** — it stays an abstract season in the value until it is composed with a locale or a territory, and is never expanded when the `~o` sigil is compiled. This replaces the first answer of the day, which had the sigil resolve the season at run time by the current locale.

* **It is composed with a locale or a territory by an option and by a function of its own** — an option of `Tempo.to_interval/2` and the functions built on it, and a function that takes the value and the locale or territory and returns the season resolved. Both.

* **The application's `:default_territory` and the current locale count as given** — where an abstract season is composed and no option names one, the chain `Tempo.Territory.resolve/1` has is asked.

* **A region override in the value does not resolve it** — `2026-21[u-rg=auzzzz]` stays an abstract season. A territory given explicitly is what decides, and wins.

* **An operation that needs the dates of a season not yet resolved is an error** — a named one, which says to give a locale or a territory.

## What Localize gives

```elixir
Localize.Territory.Hemisphere.hemisphere(:AU)     # {:ok, :southern}
Localize.Territory.Hemisphere.hemisphere(:GB)     # {:ok, :northern}
Localize.Territory.Hemisphere.hemisphere(:BR)     # {:ok, :ambiguous}
Localize.Territory.Hemisphere.hemisphere(:"053")  # {:ok, :southern}, Australasia
Localize.Territory.Hemisphere.hemisphere(:ZZ)     # {:error, %Localize.UnknownTerritoryError{}}
```

* It takes a territory code, as an atom or a string, or a language tag, whose territory is asked.

* A territory the equator runs through is `:ambiguous`, where one answer was asked for: Brazil, Colombia, Ecuador, Indonesia, Kenya and nine more, and a region that holds territories on both sides, the world (`:"001"`) among them. What a season is there is the fourth open question.

* A region that lies on one side is answered from its territories, and a territory it does not know is an error.

## The four questions, answered 2026-10-09 (user, each as recommended)

* **Where the current locale is asked** — a reader resolves a season only with an explicit `:locale` or `:territory`, so `~o"2026-21"` and `Tempo.from_iso8601("2026-21")` are abstract and `Tempo.from_iso8601("2026-21", territory: :AU)` is `~o"2026Y9M/12M"`. A season is composed later, by `Tempo.to_interval/2` and the functions built on it or by the function below, and it is there that the application's default and the current locale are asked where none is named: `Tempo.to_interval(~o"2026-21")` is the spring of the current locale's territory.

* **How the value holds it** — a unit of its own in the value's units (`[year: 2026, season: 21]`), written back as `2026Y21M`. A range and a set of seasons stay abstract until they are composed. A day or a time of day after a season is refused, where `2026-21-15` read as 15 March.

* **The name of the function** — `Tempo.in_territory/2`, beside `Tempo.in_zone/2`.

* **A territory with no one hemisphere** — a named error, which says to write the season of a hemisphere (25 to 32) or to give a territory on one side of the equator.

## The shape of the work

The parser keeps a season of 21 to 24 as a unit where no territory is given, and expands it as it does today where one is, with the months of the territory's hemisphere. A season of 25 to 32 is expanded as it is today. The sigil then needs no run-time form: what it compiles is the abstract season.

Every function that takes a value takes the new shape, which is the cost of this plan: the conversion, the walk, comparison and the set operations, formatting, `Tempo.explain/1`, the inspect protocol and the operation matrix, whose cells for a season are new.

## Tasks

* [ ] **A season kept in the value** — the parser, the value's units, `inspect` and `Tempo.to_iso8601/1`.

* [ ] **A season resolved** — the readers' options, the hemisphere's months, and whatever the answers to the open questions name.

* [ ] **Every operation on an abstract season** — the named error or the answer, the matrix's cells, the guides.

### Done

* [x] **The open questions** — put to the user and answered, each as recommended. 2026-10-09.

* [x] **The hemisphere from Localize** — `Localize.Territory.Hemisphere.hemisphere/1`, in Tempo's lock since `117932d`. 2026-10-09.
