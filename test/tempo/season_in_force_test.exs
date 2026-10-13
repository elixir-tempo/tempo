defmodule Tempo.SeasonInForceTest do
  # The application's environment is set here, so this runs alone.
  use ExUnit.Case, async: false

  import Tempo.Sigils

  alias Tempo.ConversionError

  # A season of 21 to 24 with no territory named has its months in the
  # territory in force: the application's `:default_territory`, then the
  # current locale's (`plans/seasons-by-locale.md`).

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

  test "its days are those of the territory in force" do
    in_force(:GB)
    assert Enum.at(~o"2026-21", 0) == ~o"2026-03-01"
    assert Tempo.duration(~o"2026-21") == ~o"P3M"
    assert Tempo.relation(~o"2026-21", ~o"2026-04") == :contains

    in_force(:AU)
    assert Enum.at(~o"2026-21", 0) == ~o"2026-09-01"
    assert Enum.at(~o"2026-22", -1) == ~o"2027-02-28"
    assert Tempo.relation(~o"2026-21", ~o"2026-04") == :preceded_by
  end

  test "the value is the same whatever is in force" do
    in_force(:GB)
    north = ~o"2026-21"
    in_force(:AU)
    assert ~o"2026-21" == north
    assert Tempo.to_iso8601!(north) == "2026Y21M"
  end

  test "a territory named is the one used, whatever is in force" do
    in_force(:AU)
    assert Tempo.to_interval(~o"2026-21", territory: :GB) == {:ok, ~o"2026-03/2026-05"}
  end

  test "a territory on no one side of the equator gives it none" do
    in_force(:BR)

    assert {:error, %ConversionError{reason: {:no_hemisphere, :BR}}} =
             Tempo.duration(~o"2026-21")

    assert Tempo.duration(~o"2026-25") == ~o"P93D"
  end
end
