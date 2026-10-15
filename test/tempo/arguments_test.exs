defmodule Tempo.ArgumentsTest do
  use ExUnit.Case, async: true

  # What the API takes in its less travelled forms, and what it refuses by
  # name: a default argument, a duration given as text, marks and zones
  # given to `Tempo.new/1`, an empty enumerable to `Tempo.try_map/2`.

  import Tempo.Sigils

  alias Tempo.Clock.Test, as: TestClock

  describe "the default arguments" do
    setup do
      TestClock.put(~U[2026-06-15 12:00:00Z])
      on_exit(&TestClock.reset/0)
    end

    test "the clock is read in UTC" do
      assert Tempo.now() == {:ok, ~o"2026-06-15T12:00:00Z"}
      assert Tempo.today() == {:ok, ~o"2026-06-15"}
    end

    test "text is read in the locale in force" do
      assert Tempo.parse!("June 15, 2026") == ~o"2026-06-15"
    end
  end

  describe "Tempo.new/1" do
    test "takes marks on the units the value has" do
      assert {:ok, _} = Tempo.new(year: 2026, month: 6, qualifications: %{month: :uncertain})
    end

    test "refuses a mark that is none, on a unit the value has not, or not given as a map" do
      assert {:error, %ArgumentError{message: message}} =
               Tempo.new(year: 2026, month: 6, qualifications: %{month: :sure})

      assert message =~ "not :month as :sure"

      assert {:error, %ArgumentError{}} =
               Tempo.new(year: 2026, qualifications: %{day: :uncertain})

      assert {:error, %ArgumentError{}} = Tempo.new(year: 2026, qualifications: [:uncertain])
    end

    test "takes a zone by name or as a zone, and refuses another" do
      paris = Tempo.new!(year: 2026, month: 6, day: 15, hour: 10, zone: "Europe/Paris")

      assert Tempo.new(
               year: 2026,
               month: 6,
               day: 15,
               hour: 10,
               zone: %Tempo.Zone{name: "Europe/Paris"}
             ) ==
               {:ok, paris}

      assert {:error, %Tempo.ZoneError{zone: 123, reason: :unknown}} =
               Tempo.new(year: 2026, zone: 123)
    end
  end

  describe "Tempo.shift/3" do
    test "takes a duration as its ISO 8601 text" do
      assert Tempo.shift(~o"2026-06-15", "P1D") == {:ok, ~o"2026-06-16"}
    end

    test "refuses text that is no duration, or not ISO 8601" do
      assert {:error, %Tempo.ConversionError{reason: :not_a_duration}} =
               Tempo.shift(~o"2026-06-15", "2026")

      assert {:error, %Tempo.ParseError{}} = Tempo.shift(~o"2026-06-15", "nonsense")
    end
  end

  describe "Tempo.certainty/3" do
    test "refuses a second argument that is no expression" do
      assert {:error, %Tempo.ConversionError{value: "2027", reason: :not_an_expression}} =
               Tempo.certainty(:before, ~o"2026", "2027")
    end

    test "refuses two values on different cycles" do
      assert {:error, %Tempo.FrameError{reason: :cycles}} =
               Tempo.certainty(:before, ~o"6M", ~o"T10")
    end
  end

  describe "Tempo.try_map/2" do
    test "of nothing is the empty set" do
      assert Tempo.try_map([], &Tempo.trunc(&1, :day)) == {:ok, ~o"{}"}
    end

    test "refuses a function that answers with no expression" do
      assert {:error, %Tempo.ConversionError{value: 1, reason: :not_an_expression}} =
               Tempo.try_map([~o"2026"], fn _value -> 1 end)
    end
  end
end
