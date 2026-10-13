defmodule Tempo.Core.ScaleTest do
  use ExUnit.Case, async: true

  # Positions on the scale: every concrete anchored value of the corpus has
  # an extent whose end follows its start, and the lengths of a few are what
  # the calendar and the zone make them.

  alias Tempo.Matrix.Corpus
  alias Tempo.Scale
  alias Tempo.Unit
  alias Tempo.Zone

  @second 1_000_000
  @day 86_400 * @second

  defp concrete_anchored do
    for entry <- Corpus.entries(),
        {:ok, %Tempo{form: {:value, units}} = value} <- [Corpus.read(entry)],
        Unit.plain?(units),
        Unit.anchored?(units),
        do: {entry.text, value}
  end

  test "every concrete anchored value of the corpus has an extent that ends after it starts" do
    values = concrete_anchored()
    assert Enum.count_until(values, 101) > 100

    for {text, %Tempo{form: {:value, units}} = value} <- values do
      assert {:ok, {start, stop}} = Scale.extent(units, value.calendar, value.zone, value.shift),
             text

      assert Scale.compare(start, stop) == :lt, text
    end
  end

  test "a day across a change of the clock is 23 or 25 hours long" do
    {:ok, paris} = Zone.named("Europe/Paris")
    {:ok, {start, stop}} = Scale.extent([year: 2026, month: 3, day: 29], Calendar.ISO, paris, nil)
    assert stop - start == 23 * 3600 * @second

    {:ok, {start, stop}} =
      Scale.extent([year: 2026, month: 10, day: 25], Calendar.ISO, paris, nil)

    assert stop - start == 25 * 3600 * @second

    {:ok, {start, stop}} =
      Scale.extent([year: 2026, month: 10, day: 25, hour: 2], Calendar.ISO, paris, nil)

    assert stop - start == 3600 * @second
  end

  test "a value's span is one unit of its resolution" do
    assert {:ok, {start, stop}} = Scale.extent([year: 2026, month: 6], Calendar.ISO, nil, nil)
    assert stop - start == 30 * @day
    assert {:ok, {start, stop}} = Scale.extent([year: 2026, week: 25], Calendar.ISO, nil, nil)
    assert stop - start == 7 * @day
    assert {:ok, {start, stop}} = Scale.extent([year: 5787], Calendrical.Hebrew, nil, nil)
    assert stop - start == 385 * @day

    assert {:ok, {start, stop}} =
             Scale.extent(
               [
                 year: 2026,
                 month: 6,
                 day: 15,
                 hour: 10,
                 minute: 30,
                 second: 45,
                 microsecond: {500_000, 1}
               ],
               Calendar.ISO,
               nil,
               nil
             )

    assert stop - start == 100_000
  end

  test "a value with no year lies on the cycle of its coarsest unit" do
    assert Scale.frame([hour: 10], nil, nil) == {:cycle, :hour}
    assert Scale.frame([month: 6, day: 15], nil, nil) == {:cycle, :month}
    assert Scale.frame([year: 2026], nil, nil) == :floating
    assert Scale.frame([year: 2026], nil, hour: 2) == :utc

    # A position on a cycle is ticks from the cycle's start, on the longest
    # cycle: the months before June have 152 days at most, the whole year 366.
    hour = 3600 * @second

    assert Scale.extent([hour: 10], Calendar.ISO, nil, nil) == {:ok, {10 * hour, 11 * hour}}

    assert Scale.extent([month: 6, day: 15], Calendar.ISO, nil, nil) ==
             {:ok, {166 * @day, 167 * @day}}

    assert Scale.extent([month: 12, day: 31], Calendar.ISO, nil, nil) ==
             {:ok, {365 * @day, 366 * @day}}

    assert Scale.extent([hour: 23, minute: 59], Calendar.ISO, nil, nil) ==
             {:ok, {23 * hour + 59 * 60 * @second, 24 * hour}}

    assert Scale.extent([day_of_week: 3], Calendar.ISO, nil, nil) == {:ok, {2 * @day, 3 * @day}}
    assert Scale.cycle_length(:month, Calendar.ISO) == {:ok, 366 * @day}
    assert Scale.compare(22 * hour, 23 * hour) == :lt
  end
end
