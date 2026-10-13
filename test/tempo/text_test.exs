defmodule Tempo.TextTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ParseError

  # Reading text: a profile holds a text to one kind of expression, and
  # `Tempo.parse/2` reads a locale's words where the text is not ISO 8601.

  describe "a profile" do
    test "reads the kind of expression it names" do
      assert Tempo.from_iso8601("2026-06-15", profile: :date) == {:ok, ~o"2026-06-15"}
      assert Tempo.from_iso8601("T10:30", profile: :time) == {:ok, ~o"T10:30"}

      assert Tempo.from_iso8601("2026-06-15T10:30", profile: :datetime) ==
               {:ok, ~o"2026-06-15T10:30"}

      assert Tempo.from_iso8601("P1D", profile: :duration) == {:ok, ~o"P1D"}

      assert Tempo.from_iso8601("2026-06-15/2026-06-20", profile: :interval) ==
               {:ok, ~o"2026-06-15/2026-06-20"}

      assert Tempo.from_iso8601("R3/2026-06-15/P1D", profile: :interval) ==
               {:ok, ~o"R3/2026-06-15/P1D"}
    end

    test "refuses another kind, and says which was wanted" do
      for {text, profile, wanted} <- [
            {"2026-06-15T10", :date, "not a date"},
            {"2026-06-15", :time, "not a time"},
            {"2026-06-15", :datetime, "not a datetime"},
            {"2026-06-15", :interval, "not an interval"},
            {"2026", :duration, "not a duration"},
            {"P1D", :date, "not a date"}
          ] do
        assert {^text, {:error, %ParseError{reason: ^wanted}}} =
                 {text, Tempo.from_iso8601(text, profile: profile)}
      end
    end

    test "that is none is an error naming the profiles" do
      assert {:error, %ParseError{reason: reason}} =
               Tempo.from_iso8601("2026", profile: :nonsense)

      assert reason =~ ":nonsense is not a profile"
    end

    test "holds what `parse/2` reads too" do
      assert Tempo.parse("2026-06-15", profile: :date) == {:ok, ~o"2026-06-15"}
      assert {:error, %ParseError{}} = Tempo.parse("2026-06-15T10", profile: :date)
    end
  end

  describe "parse/2" do
    test "reads ISO 8601 first, and then the locale's words" do
      assert Tempo.parse("2026-06-15") == {:ok, ~o"2026-06-15"}
      assert Tempo.parse("15 June 2026", locale: :en) == {:ok, ~o"2026-06-15"}
      assert Tempo.parse("15 juin 2026", locale: :fr) == {:ok, ~o"2026-06-15"}
    end

    test "words with a time in UTC are a moment" do
      assert Tempo.parse("15 June 2026 10:30 UTC", locale: :en) == {:ok, ~o"2026-06-15T10:30Z"}
    end

    test "text that is neither is the error of the ISO 8601 reading" do
      assert {:error, %ParseError{text: "nonsense words"}} =
               Tempo.parse("nonsense words", locale: :en)
    end

    test "the raising form raises that error" do
      assert Tempo.parse!("15 June 2026", locale: :en) == ~o"2026-06-15"
      assert_raise ParseError, fn -> Tempo.parse!("nonsense words", locale: :en) end
    end
  end

  describe "the sigil" do
    test "takes a literal, with no modifiers and no interpolation" do
      assert_raise ArgumentError, ~r/takes no modifiers/, fn ->
        Code.eval_string(~S|import Tempo.Sigils; ~o"2026-W25-2"W|)
      end

      assert_raise ArgumentError, ~r/no interpolation/, fn ->
        Code.eval_string(~S|import Tempo.Sigils; year = 2026; ~o"#{year}-06"|)
      end
    end

    test "a text that is no expression fails where it is written" do
      assert_raise ParseError, fn -> Code.eval_string(~S|import Tempo.Sigils; ~o"nonsense"|) end

      assert_raise Tempo.InvalidDateError, fn ->
        Code.eval_string(~S|import Tempo.Sigils; ~o"2026-13"|)
      end
    end

    test "in a match, a value matches what is written within it" do
      assert match?(~o"2026", ~o"2026-06-15T10:30")
      refute match?(~o"2025", ~o"2026-06-15T10:30")
      assert match?(~o"P1D", ~o"P1D")
    end
  end

  describe "a value in text" do
    test "is its ISO 8601, and is inspected as the sigil that reads it" do
      assert "#{~o"2026-06-15"}" == "2026Y6M15D"
      assert "#{~o"P1DT2H"}" == "P1DT2H"
      assert inspect(~o"P1DT2H") == ~s(~o"P1DT2H")
      assert inspect(~o"2026-06-15/2026-06-20") == ~s(~o"2026Y6M15D/20D")
    end
  end
end
