defmodule Tempo.TerritoryTest do
  # The default territory is read from the application's environment.
  use ExUnit.Case, async: false

  alias Tempo.Territory

  describe "resolve/1" do
    test "a territory, as an atom or as text" do
      assert Territory.resolve(:AU) == {:ok, :AU}
      assert Territory.resolve("AU") == {:ok, :AU}
    end

    test "a locale, as its name or as a language tag" do
      assert Territory.resolve("en-GB") == {:ok, :GB}
      {:ok, tag} = Localize.validate_locale("fr-CA")
      assert Territory.resolve(tag) == {:ok, :CA}
    end

    test "none is the application's, and then the locale's" do
      assert Territory.resolve(nil) == {:ok, :US}

      Application.put_env(:ex_tempo, :default_territory, :SA)
      on_exit(fn -> Application.delete_env(:ex_tempo, :default_territory) end)
      assert Territory.resolve(nil) == {:ok, :SA}
    end

    test "what names no territory is an error that says what does" do
      assert {:error, %ArgumentError{message: message}} = Territory.resolve(42)
      assert message =~ "names no territory"
    end
  end

  describe "a territory in an operation" do
    test "gives the weekend its people keep" do
      assert Tempo.weekend?(Tempo.new!(year: 2026, month: 6, day: 12), :SA) == true
      assert Tempo.weekend?(Tempo.new!(year: 2026, month: 6, day: 12), :US) == false
    end
  end
end
