defmodule Tempo.SeasonInForceTest do
  @moduledoc """
  A season with no hemisphere under the application's default territory
  (`plans/seasons-by-locale.md`).

  `config :ex_tempo, :default_territory` is asked before the current
  locale where a season is given its dates and no territory is named. It
  is the application's, and every process reads it, so the tests that set
  it run one at a time, apart from `Tempo.SeasonTest`.

  Three things are held here. The default territory is asked where a
  season is converted, and a territory that is named wins over it. A value
  is read the same whatever territory is in force, since a sigil is read
  where it is compiled and not where it runs. And every operation of the
  matrix, asked of a season in a territory north of the equator, south of
  it and on both sides of it, gives a value or an error by name: none
  raises what it did not mean to, and none answers one way where the
  conversion answers another.
  """
  use ExUnit.Case, async: false

  import Tempo.Sigils

  alias Tempo.AbstractSeasonError
  alias Tempo.Matrix.Census
  alias Tempo.Matrix.Corpus

  setup do
    before = Application.get_env(:ex_tempo, :default_territory)

    on_exit(fn ->
      if before,
        do: Application.put_env(:ex_tempo, :default_territory, before),
        else: Application.delete_env(:ex_tempo, :default_territory)
    end)

    :ok
  end

  defp in_force(territory), do: Application.put_env(:ex_tempo, :default_territory, territory)

  describe "the application's default territory" do
    test "is where a season is given its dates when none is named" do
      in_force(:AU)

      assert Tempo.to_interval(~o"2026-21") == {:ok, ~o"2026-09/2026-12"}
      assert Tempo.in_territory(~o"2026-21", nil) == {:ok, ~o"2026-09/2026-12"}
      assert Tempo.relation(~o"2026-21", ~o"2026-10") == :contains

      in_force(:GB)

      assert Tempo.to_interval(~o"2026-21") == {:ok, ~o"2026-03/2026-06"}
      assert Tempo.relation(~o"2026-21", ~o"2026-10") == :precedes
    end

    test "is asked before the current locale" do
      in_force(:AU)
      Localize.put_locale("en-GB")

      assert Tempo.to_interval(~o"2026-21") == {:ok, ~o"2026-09/2026-12"}
    end

    test "gives way to a territory or a locale that is named" do
      in_force(:AU)

      assert Tempo.to_interval(~o"2026-21", territory: :GB) == {:ok, ~o"2026-03/2026-06"}
      assert Tempo.to_interval(~o"2026-21", locale: "en-GB") == {:ok, ~o"2026-03/2026-06"}
      assert Tempo.in_territory(~o"2026-21", :GB) == {:ok, ~o"2026-03/2026-06"}
      assert Tempo.from_iso8601("2026-21", territory: :GB) == {:ok, ~o"2026-03/2026-06"}
    end

    test "has no dates for a season where it is on both sides of the equator" do
      in_force(:BR)

      assert {:error, %AbstractSeasonError{territory: :BR}} = Tempo.to_interval(~o"2026-21")
      assert Tempo.to_interval(~o"2026-21", territory: :AU) == {:ok, ~o"2026-09/2026-12"}
    end
  end

  describe "a value" do
    test "is read the same whatever territory is in force" do
      texts = [
        "2026-21",
        "2026-21?",
        "2026-21/2026-23",
        "2026-23/2026-21",
        "2026-24/2026-21",
        "2026-06/2026-21",
        "2026-21/P1M",
        "R3/2026-21/P1Y",
        "{2026-21..2026-24}",
        "2026-21[Europe/Paris]",
        "2026-21/2026-23[Australia/Sydney]",
        "20XX-21",
        "5787-22[u-ca=hebrew]",
        "2026-21-15"
      ]

      [north, south, both] =
        for territory <- [:GB, :AU, :BR] do
          in_force(territory)
          Enum.map(texts, &Tempo.from_iso8601/1)
        end

      assert north == south
      assert north == both
      assert Enum.count(north, &match?({:ok, _value}, &1)) == 13
    end
  end

  describe "every operation of the matrix, asked of a season" do
    # The season rows of the corpus, and beside them an interval of seasons
    # that is one south of the equator and none north of it, a recurrence
    # from a season, and a season in a zone.
    defp season_entries do
      rows =
        for %{class: class} = entry <- Corpus.written(),
            class in [:season_with_no_hemisphere, :season_interval, :season_set],
            do: entry

      beside =
        for text <- [
              "2026-23/2026-21",
              "2026-06/2026-21",
              "R3/2026-21/P1Y",
              "2026-21[Asia/Tokyo]"
            ] do
          %{class: :season_interval, level: :open, text: text, calendar: nil}
        end

      rows ++ beside
    end

    # A cell that raises ends its process, which the runtime logs: the
    # outcomes say what the reports would.
    defp run_unlogged(entries) do
      level = Logger.level()
      Logger.configure(level: :none)
      cells = Census.run(entries)
      Logger.configure(level: level)
      cells
    end

    for territory <- [:GB, :AU, :BR] do
      @tag timeout: 300_000
      test "gives a value or an error by name with #{inspect(territory)} in force" do
        in_force(unquote(territory))

        cells = run_unlogged(season_entries())

        assert Census.failures(cells) == []
        assert Enum.count(cells) > 5_000
      end
    end
  end
end
