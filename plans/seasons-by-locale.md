# Seasons by locale

**Status:** implemented (v2.0.0), 2026-10-09

Localize gives a territory's hemisphere since 2026-10-09 (`Localize.Territory.Hemisphere`). The decisions below are the user's, taken on 2026-10-08 in three rounds and, for the four questions that were open, on 2026-10-09.

## The problem

ISO 8601-2 §4.8.1 lists twelve seasons: 21 to 24 are spring, summer, autumn and winter "independent of location", 25 to 28 the same four of the northern hemisphere, and 29 to 32 of the southern. §3.1.3 notes that one calendar date can be of different seasons by local custom or by place, the two hemispheres being its example. The standard does not say whether a season is reckoned by the months or by the sun.

Tempo read a season into its dates when it parsed, and the value was an interval from then on:

```elixir
Tempo.from_iso8601("2026-21")  # was {:ok, ~o"2026Y3M/6M"}, the northern meteorological spring, wherever it was read
Tempo.from_iso8601("2026-25")  # {:ok, ~o"2026Y3M20D/6M21D"}, the March equinox to the June solstice
Tempo.from_iso8601("2026-29")  # {:ok, ~o"2026Y9M23D/12M21D"}, the southern spring
```

So a season of 21 to 24 was the northern one for a reader in Australia, where spring is September to November, and the value did not remember that it was written as a season.

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

## What was built

A season of 21 to 24 is a unit of its own, `:season`, in the month's place: `~o"2026-21"` is `%Tempo{time: [year: 2026, season: 21]}`, written back as `2026Y21M`. It is coarser than a month and finer than a year. Nothing follows it, and the season of a hemisphere (25 to 32) is its dates as it is read, as it was.

```elixir
Tempo.from_iso8601("2026-21")                    # {:ok, ~o"2026Y21M"}
Tempo.from_iso8601("2026-21", territory: :AU)    # {:ok, ~o"2026Y9M/12M"}
Tempo.in_territory(~o"2026-21", :GB)             # {:ok, ~o"2026Y3M/6M"}
Tempo.in_territory(~o"2026-22", :NZ)             # {:ok, ~o"2026Y12M/2027Y3M"}
Tempo.in_territory(~o"2026-21", :BR)             # {:error, %Tempo.AbstractSeasonError{territory: :BR}}
Tempo.to_interval(~o"2026-21", locale: "en-AU")  # {:ok, ~o"2026Y9M/12M"}
Tempo.to_interval(~o"2026-21")                   # the spring of the default territory, then of the current locale
```

Three kinds of operation, and no fourth.

* **What needs no dates answers** — the year, `inspect`, `Tempo.to_iso8601/1`, a step of whole years, the walk of a set of seasons by its members, a zone, `Tempo.trunc/2` of the season alone, `Tempo.explain/1`, which names the season and chooses no hemisphere.

* **What is built on `Tempo.to_interval/2` gives the season its dates** — the conversion, the comparisons and the relations, the lengths, the set operations, `Tempo.select/2` with the season as its base or its selector, `Tempo.count_workdays/2`, and `Tempo.to_string/2` and `Tempo.to_relative_string/2`, which take the territory of the locale they render in. A season is no point (`Tempo.Compare.point?/1`), so it is read as the start of the span the conversion gives it, the one place a value that is not a point is read as a moment.

* **What else needs its dates is `Tempo.AbstractSeasonError`** — a walk, a date read from it (`Tempo.day_of_week/1`), a step of anything but years, a time of day placed on it, a finer unit, a rounding, and a truncation or a rounding of an interval with a season at an end.

An interval of seasons is read whatever the order of its seasons, since the autumn of a year comes before its spring south of the equator, and is held to its order where it is given a hemisphere: `2026-23/2026-21` is March to September in Australia and a `Tempo.IntervalEndpointsError` in Britain. A value is read the same whatever territory is in force, the sigil being read where it is compiled.

A season where a season is not built (a year that does not begin with its first month, `Tempo.NotBuilt`) is refused as it is read.

Mine, flagged to the user (2026-10-09): the error's name; the walk raises and is not given the hemisphere in force, a walk not being built on the conversion; a `:locale` is read as a locale (`"ar"` is Arabic, and its territory Egypt) where the territory `"ar"` is Argentina; a season that is the `:within` window is given its dates with the value; the territory given to `Tempo.count_workdays/2` names the working week and not the season's hemisphere; `Tempo.Interval.new/1` holds its ends to their order in the hemisphere in force, where the parser does not; `Tempo.empty?/1` of an interval of seasons out of order is `true`, as of any span that ends before it starts.

## Tasks

### Done

* [x] **Every operation on an abstract season** — the named error or the answer, the matrix's cells in three territories (`test/tempo/season_in_force_test.exs`), the guides. 2026-10-09.

* [x] **A season resolved** — `Tempo.in_territory/2`, the readers' options, the months of each hemisphere measured apart from the library (`test/tempo/season_test.exs`). 2026-10-09.

* [x] **A season kept in the value** — the parser, the value's units, `inspect`, `Tempo.to_iso8601/1` and the sigil in a match. 2026-10-09.

* [x] **The open questions** — put to the user and answered, each as recommended. 2026-10-09.

* [x] **The hemisphere from Localize** — `Localize.Territory.Hemisphere.hemisphere/1`, in Tempo's lock since `117932d`. 2026-10-09.
