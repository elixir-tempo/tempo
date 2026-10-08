defmodule Tempo.CalendarCensusTest do
  @moduledoc """
  The calendar census (`plans/enumeration-and-selection.md`): a value in
  each full form and a selection of each kind, in each calendar module
  Calendrical ships, held to what the calendar alone says.

  A value is converted to the span it covers and walked, and a selection
  converted to the spans it selects. `Tempo.Matrix.CalendarCensus` works
  each answer out with the calendar's own functions and `Date`, and none
  of Tempo's: the dates a month has, the weeks of a year, the dates of a
  week, the months of a year that starts within them.

  It was a run of a script, whose table the plan holds; this is the table
  as a test. It found a month with days missing walked as a run of days, a
  year that starts within its months read from its January, and a week
  selected in a calendar of weeks that was the whole year.
  """
  use ExUnit.Case, async: true

  alias Tempo.Matrix.CalendarCensus
  alias Tempo.Matrix.Extent

  # A day's hours, an hour's minutes and a minute's seconds are walked
  # whole, and so are a month's days and a year's months or weeks.
  @walk_limit 400

  # The span a value covers, as `Tempo.Matrix.Extent` reads the interval it
  # converts to.
  defp covered(value) do
    {:ok, converted} = Tempo.to_interval(value)
    {:ok, %{spans: spans}} = Extent.of(converted)
    spans
  end

  # Each value the walk yields, as the span it covers.
  defp walked(value) do
    for yielded <- Enum.take(value, @walk_limit) do
      [span] = covered(yielded)
      span
    end
  end

  defp selected(value) do
    {:ok, converted} = Tempo.to_interval(value)
    {:ok, members} = Extent.members(converted)
    Enum.map(members, & &1.spans)
  end

  for calendar <- CalendarCensus.calendars() do
    describe "in #{inspect(calendar)}" do
      test "a value in each full form covers what the calendar says, and is walked by its parts" do
        calendar = unquote(calendar)

        for %{form: form, text: text, expect: expect} <- CalendarCensus.forms(calendar) do
          {span, walk} = CalendarCensus.expected(expect, calendar)
          value = Tempo.from_iso8601!(text, calendar)

          assert {form, text, covered(value)} == {form, text, [span]}

          if walk != :unchecked do
            assert {form, text, walked(value)} == {form, text, Enum.take(walk, @walk_limit)}
          end
        end
      end

      test "a selection of each kind selects what the calendar says" do
        calendar = unquote(calendar)

        for %{scenario: scenario, text: text, selected: expected} <-
              CalendarCensus.selections(calendar) do
          value = Tempo.from_iso8601!(text, calendar)

          assert {scenario, text, selected(value)} == {scenario, text, expected}
        end
      end
    end
  end

  describe "the census itself" do
    test "holds every full form of a calendar of months, and of a calendar of weeks" do
      assert Enum.count(CalendarCensus.forms(Calendrical.Gregorian)) == 27
      assert Enum.count(CalendarCensus.forms(Calendrical.Reform.England)) == 36
      assert Enum.count(CalendarCensus.forms(Calendrical.ISOWeek)) == 15
    end

    test "holds thirty selections in a calendar of months and twenty in a calendar of weeks" do
      assert Enum.count(CalendarCensus.selections(Calendrical.Hebrew)) == 30
      assert Enum.count(CalendarCensus.selections(Calendrical.NRF)) == 20

      # A selection in a year that starts within its months is not built,
      # and is not measured until it is.
      assert CalendarCensus.selections(Calendrical.Julian.March25) == []
    end

    test "reads the September of 1752 in England as the days the reform left it" do
      {{from, to}, days} = CalendarCensus.expected({:month, 1752, 9}, Calendrical.Reform.England)

      # Nineteen days, one after another: the 2nd was followed by the 14th.
      assert Enum.count(days) == 19
      assert div(to - from, 86_400_000_000) == 19
    end

    test "reads a year from 25 March as the dates the calendar counts in it" do
      calendar = Calendrical.Julian.March25
      {{from, _to}, months} = CalendarCensus.expected({:year, 2026}, calendar)

      first = Date.convert!(Date.new!(2026, 3, 25, calendar), Calendar.ISO)

      assert from == Date.to_gregorian_days(first) * 86_400_000_000
      assert Enum.count(months) == 12
    end
  end
end
