defmodule Tempo.DayOfYearTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError
  alias Tempo.ParseError
  alias Tempo.UnanchoredError

  describe "a day of the year (ISO 8601-2 §4.3.4)" do
    test "is its own unit, written back as O" do
      assert Tempo.to_iso8601(~o"350O") == {:ok, "350O"}
      assert inspect(~o"-1O") == ~s|~o"-1O"|
      assert inspect(Tempo.from_iso8601!("2020Y{100,200}O")) == ~s|~o"2020Y{100,200}O"|
    end

    test "after its year is the year's ordinal day" do
      assert ~o"2026Y10O" == ~o"2026-01-10"
      assert ~o"2026-166" == ~o"2026-06-15"
      assert Tempo.from_iso8601!("2024Y366O") == ~o"2024-12-31"
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("2026Y366O")
    end

    test "never follows a month" do
      assert {:error, %InvalidDateError{}} = Tempo.at(~o"3M", ~o"2O")
      assert {:error, %ParseError{}} = Tempo.from_iso8601("6M10O")
      assert {:ok, set} = Tempo.select(~o"2026-06", ~o"10O")
      assert IntervalSet.members(set) == []
    end

    test "without a year has no span, no next day and no date to show" do
      assert {:error, %UnanchoredError{}} = Tempo.to_interval(~o"10O")
      assert {:error, %UnanchoredError{}} = Tempo.shift(~o"10O", ~o"P1D")
      assert {:error, %UnanchoredError{}} = Tempo.to_string(~o"10O")
      assert Tempo.explain(~o"10O") =~ "Day 10 of any year"
    end
  end

  describe "a day with no month" do
    test "is a day of the year where a year resolves it" do
      assert ~o"2026Y32D" == ~o"2026-02-01"

      assert {:ok, set} = Tempo.select(~o"2026", ~o"10D")
      assert [january_tenth] = IntervalSet.members(set)
      assert january_tenth.from.time == [year: 2026, month: 1, day: 10]
    end

    test "is a day of a month elsewhere" do
      assert Tempo.at(~o"3M", ~o"2D") == {:ok, ~o"3M2D"}
      assert Tempo.shift(~o"15D", ~o"P1M") == ~o"15D"
      assert {:error, %UnanchoredError{}} = Tempo.shift(~o"28D", ~o"P1D")
    end
  end

  describe "a unit with nothing above it" do
    test "is never 0" do
      for string <- ["0D", "0O", "0M", "0W", "{0,1}D"] do
        assert {:error, %InvalidDateError{}} = Tempo.from_iso8601(string), string
      end
    end

    test "is a month no further from either end than a year of its calendar has" do
      for string <- ["13M", "-13M", "13M1D"] do
        assert {:error, %InvalidDateError{unit: :month}} = Tempo.from_iso8601(string), string
      end

      assert {:ok, _december} = Tempo.from_iso8601("12M")
      assert {:ok, _last_month} = Tempo.from_iso8601("-12M")
      assert {:ok, _adar_ii} = Tempo.from_iso8601("13M[u-ca=hebrew]")
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("14M[u-ca=hebrew]")
    end

    test "is a day or a week bounded once it has a year" do
      for string <- ["32D", "166D", "54W", "367O"] do
        assert {:ok, _value} = Tempo.from_iso8601(string), string
      end

      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("2026Y54W")
      assert {:error, %InvalidDateError{}} = Tempo.from_iso8601("2026Y367O")
    end
  end
end
