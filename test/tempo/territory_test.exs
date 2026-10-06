defmodule Tempo.TerritoryTest do
  use ExUnit.Case, async: true

  # A territory is given as its code, in either case, as an atom or a string;
  # as a locale, which names one or implies one; or as a region override of
  # BCP 47 (`u-rg`). What names none is an error and never a raise: the
  # value comes from a caller's options, a form or a configuration.

  alias Tempo.Territory

  doctest Tempo.Territory

  describe "resolve/1" do
    test "reads a territory's code in either case, as an atom or a string" do
      for given <- [:AU, :au, "AU", "au"] do
        assert {given, Territory.resolve(given)} == {given, {:ok, :AU}}
      end
    end

    test "reads the territory a locale names, and the one its region override does" do
      assert Territory.resolve("en-AU") == {:ok, :AU}
      assert Territory.resolve("ar-SA") == {:ok, :SA}

      # The region override wins over the locale's own territory.
      assert Territory.resolve("en-US-u-rg-sazzzz") == {:ok, :SA}
      assert Territory.resolve("sazzzz") == {:ok, :SA}
    end

    test "reads the territory of a language tag" do
      {:ok, french_of_canada} = Localize.validate_locale("fr-CA")
      {:ok, overridden} = Localize.validate_locale("en-US-u-rg-sazzzz")

      assert Territory.resolve(french_of_canada) == {:ok, :CA}
      assert Territory.resolve(overridden) == {:ok, :SA}
    end

    test "is an error, and no raise, for what names no territory" do
      for given <- [
            "",
            :"",
            " ",
            "not a territory",
            "en-",
            String.duplicate("x", 5_000),
            42,
            1.5,
            %{},
            [],
            {:US},
            ~D[2026-06-15]
          ] do
        assert {given, match?({:error, %ArgumentError{}}, Territory.resolve(given))} ==
                 {given, true}
      end
    end

    test "says what it was given" do
      assert {:error, error} = Territory.resolve("not a territory")
      assert Exception.message(error) =~ ~s("not a territory")

      assert {:error, error} = Territory.resolve(42)
      assert Exception.message(error) =~ "42"
    end
  end
end
