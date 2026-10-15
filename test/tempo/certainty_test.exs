defmodule Tempo.CertaintyTest do
  use ExUnit.Case, async: true

  # `Tempo.certainty/3` asks a relation of every reading of two expressions.
  # A year written with a margin (`2018±2Y`) is each year it may be, and an
  # interval with one at an end is each pairing of its ends' readings.

  import Tempo.Sigils

  test "an interval from a year with a margin holds a relation in some readings" do
    from_about_2018 = Tempo.from_iso8601!("2018±2Y/2025")

    assert Tempo.certainty(:contains, from_about_2018, ~o"2017") == :possible
    assert Tempo.certainty(:contains, from_about_2018, ~o"2021") == :certain
    assert Tempo.certainty(:contains, from_about_2018, ~o"2015") == :impossible
  end

  test "an interval to a year with a margin is read through each year it may end" do
    to_about_2020 = Tempo.from_iso8601!("2016/2020±1Y")

    assert Tempo.certainty(:before, to_about_2020, ~o"2030") == :certain
    assert Tempo.certainty(:contains, to_about_2020, ~o"2021") == :possible
  end

  test "a margin is written on a year alone, as it is read" do
    assert {:ok, _about_2018} = Tempo.new(year: {2018, [margin: 2]})

    assert {:error,
            %Tempo.InvalidDateError{unit: :hour, reason: {:annotated, {22, [margin: 1]}}} =
              error} = Tempo.new(hour: {22, [margin: 1]})

    assert Exception.message(error) =~ "is written on a year alone"
  end
end
