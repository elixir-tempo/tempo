defmodule Tempo.CountTest do
  use ExUnit.Case, async: true

  # `Tempo.count/3`: how many values of a unit an expression holds, the
  # values `Tempo.walk/3` gives, counted.

  import Tempo.Sigils

  alias Tempo.IntervalSet

  test "a value counts the units its extent holds" do
    assert Tempo.count(~o"2026-06", :day) == {:ok, 30}
    assert Tempo.count(~o"2026", :month) == {:ok, 12}
    assert Tempo.count(~o"2026-03-29[Europe/Paris]", :hour) == {:ok, 23}
  end

  test "a set counts its members' units in turn, whatever they are written to" do
    {:ok, weekends} = Tempo.weekends(:BR)
    {:ok, business_days} = Tempo.difference(~o"2026-01-02/2026-03-31", weekends)
    days = IntervalSet.new!([~o"2026-06-01", ~o"2026-06-05"])

    assert Tempo.count(business_days, :day) == {:ok, 63}
    assert Tempo.count(days, :day) == {:ok, 2}
    assert Tempo.count(IntervalSet.new!([]), :day) == {:ok, 0}
  end

  test "counts what walk/3 walks: each unit touched, calendar or clock" do
    assert Tempo.count(~o"2026-06-01T12/2026-06-03T12", :day) == {:ok, 3}
    assert Tempo.count(~o"2026-07", :week) == {:ok, 5}
    assert Tempo.count(~o"2026-06-15T10:30/2026-06-15T12:30", :hour) == {:ok, 3}
    assert Tempo.count(~o"2026-06-15T10:00/2026-06-15T12:00", :hour) == {:ok, 2}
    assert Tempo.count(~o"2026-06-06T10:15/2026-06-06T10:45", :hour) == {:ok, 1}

    for {expression, unit} <- [
          {~o"2026-06-01T12/2026-06-03T12", :day},
          {~o"2026-06-15T10:30/2026-06-15T12:30", :hour},
          {~o"2026-01-15/2026-03-10", :month}
        ] do
      {:ok, walked} = Tempo.walk(expression, unit)
      assert Tempo.count(expression, unit) == {:ok, Enum.count(walked)}
    end
  end

  test "a clock unit is counted as it is walked, through a change of the clock" do
    for expression <- [
          ~o"2026-03-28T22:15/2026-03-30T02:45[Europe/Paris]",
          ~o"2026-10-24T22:15/2026-10-26T02:45[Europe/Paris]",
          ~o"2026-04-04T23:10/2026-04-06T03:20[Australia/Lord_Howe]",
          ~o"2026-03-07T22:10/2026-03-09T04:20[America/St_Johns]",
          ~o"2026-06-15T10:30+05:45/2026-06-16T12:31+05:45"
        ],
        unit <- [:hour, :minute] do
      {:ok, walked} = Tempo.walk(expression, unit)
      assert Tempo.count(expression, unit) == {:ok, Enum.count(walked)}
    end
  end

  test "a long span of a clock unit is counted without walking it" do
    assert Tempo.count(~o"2026", :second) == {:ok, 31_536_000}
    assert Tempo.count(~o"2026[Europe/Paris]", :second) == {:ok, 31_536_000}
    assert Tempo.count(~o"2026-03-29[Europe/Paris]", :second) == {:ok, 82_800}
  end

  test "an expression with no end or no year is counted within a window" do
    assert Tempo.count(~o"R/2026-06-01/P1W", :day, within: ~o"2026-06") == {:ok, 35}
    assert Tempo.count(~o"{6,7}K", :day, within: ~o"2026-06") == {:ok, 8}
  end

  test "what has no count is an error, not a crash" do
    assert {:error, %Tempo.ConversionError{reason: :unbounded}} =
             Tempo.count(~o"R/2026-06-01/P1W", :day)

    {:ok, june_or_july} = Tempo.one_of([~o"2026-06", ~o"2026-07"])

    assert {:error, %Tempo.ConversionError{reason: :one_of}} =
             Tempo.count(june_or_july, :day)

    assert {:error, %Tempo.ConversionError{reason: :bare_duration}} =
             Tempo.count(~o"P1D", :day)

    assert {:error, %Tempo.ConversionError{}} = Tempo.count(~o"6K", :day)
    assert {:error, %Tempo.ConversionError{}} = Tempo.count(~o"2026", :fortnight)
    assert {:error, %Tempo.ConversionError{}} = Tempo.count(nil, :day)
    assert {:error, %ArgumentError{}} = Tempo.count(~o"2026", :day, bound: 1)
  end

  test "walk/3 of a duration is an error, not a crash" do
    assert {:error, %Tempo.ConversionError{reason: :bare_duration}} =
             Tempo.walk(~o"P1D", :day)
  end
end
