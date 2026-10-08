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

  A value with no year is held to the calendar's own counts of the months
  a year has and the days a month has in any year: the span it covers on
  the cycle of the longest year, the values its walk yields, and that it
  needs a year where what follows it depends on one.

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

  defp selected(value, options \\ []) do
    {:ok, converted} = Tempo.to_interval(value, options)
    {:ok, members} = Extent.members(converted)
    Enum.map(members, & &1.spans)
  end

  # What a value with no year covers: a span of its cycle, or that it needs
  # a year, or that no year has it.
  defp covered_with_no_year(text, calendar) do
    with {:ok, value} <- Tempo.from_iso8601(text, calendar),
         {:ok, converted} <- Tempo.to_interval(value) do
      {:ok, %{spans: [span]}} = Extent.of(converted)
      {:ok, span}
    else
      {:error, %Tempo.UnanchoredError{}} -> :needs_a_year
      {:error, _no_such_value} -> :no_such_value
    end
  end

  defp assert_walk_with_no_year(_text, _calendar, :unchecked), do: :ok

  # A walk cannot return an error, so one that needs a year raises it.
  defp assert_walk_with_no_year(text, calendar, :needs_a_year) do
    value = Tempo.from_iso8601!(text, calendar)

    assert_raise Tempo.UnanchoredError, fn -> Enum.take(value, @walk_limit) end
  end

  defp assert_walk_with_no_year(text, calendar, {:count, count}) do
    value = Tempo.from_iso8601!(text, calendar)

    assert {text, Enum.count(Enum.take(value, @walk_limit))} == {text, count}
  end

  defp assert_walk_with_no_year(text, calendar, {:ok, starts}) do
    value = Tempo.from_iso8601!(text, calendar)

    assert {text, Enum.map(Enum.take(value, @walk_limit), &start/1)} == {text, starts}
  end

  defp start(yielded) do
    {:ok, _line, position} = Extent.position(yielded)
    position
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

      test "a value with no year covers what the calendar counts in any year, or needs a year" do
        calendar = unquote(calendar)

        for %{text: text, covers: covers, walk: walk} <- CalendarCensus.no_year(calendar) do
          assert {text, covered_with_no_year(text, calendar)} == {text, covers}
          assert_walk_with_no_year(text, calendar, walk)
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

      test "the same parts as a recurrence's rule, within its period, select the same" do
        calendar = unquote(calendar)

        for %{rule: {rule, window}, selected: expected} <- CalendarCensus.selections(calendar) do
          recurrence = Tempo.from_iso8601!(rule, calendar)
          within = Tempo.from_iso8601!(window, calendar)

          assert {rule, selected(recurrence, within: within)} == {rule, expected}
        end
      end

      test "the same parts given to select/2 on the period select the same" do
        calendar = unquote(calendar)

        asked =
          for %{select: {base, selector}, selected: expected} <-
                CalendarCensus.selections(calendar),
              {:ok, selector} <- [Tempo.from_iso8601(selector, calendar)] do
            {:ok, selection} = Tempo.select(Tempo.from_iso8601!(base, calendar), selector)
            {:ok, members} = Extent.members(selection)

            assert {base, selector, Enum.map(members, & &1.spans)} == {base, selector, expected}
          end

        # Parts that are no value's text cannot be asked; most are.
        if CalendarCensus.selections(calendar) != [], do: assert(Enum.count(asked) >= 8)
      end

      test "a shape, an interval and a recurrence cover and yield what the calendar says" do
        calendar = unquote(calendar)

        for %{shape: shape, text: text, members: members, walk: walk} <-
              CalendarCensus.shapes(calendar) do
          value = Tempo.from_iso8601!(text, calendar)

          assert {shape, text, selected(value)} == {shape, text, members}
          assert_walk_with_no_year(text, calendar, walk)
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

    test "holds every month and day with no year of a calendar of months, and its weekdays" do
      # Twelve months and a thirteenth no year has, each month's days and
      # the day after its last, and seven weekdays and an eighth.
      days = Enum.sum([31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])

      assert Enum.count(CalendarCensus.no_year(Calendrical.Gregorian)) == 13 + days + 12 + 8
      assert Enum.count(CalendarCensus.no_year(Calendrical.ISOWeek)) == 8
      assert Enum.count(CalendarCensus.no_year(Calendrical.Reform.England)) == 6 + 8
    end

    test "reads 28 February with no year as needing one, and the 29th as the leap day" do
      cells = Map.new(CalendarCensus.no_year(Calendrical.Gregorian), &{&1.text, &1.covers})
      day = 86_400_000_000

      assert cells["2M27D"] == {:ok, {57 * day, 58 * day}}
      assert cells["2M28D"] == :needs_a_year
      assert cells["2M29D"] == {:ok, {59 * day, 60 * day}}
      assert cells["2M30D"] == :no_such_value
      assert cells["12M"] == {:ok, {335 * day, 366 * day}}
    end

    test "reads the twelfth month of a Hebrew year as needing a year, and the thirteenth as its last" do
      cells = Map.new(CalendarCensus.no_year(Calendrical.Hebrew), &{&1.text, &1.covers})

      assert cells["12M"] == :needs_a_year
      assert {:ok, {_from, _to}} = cells["13M"]
      assert cells["14M"] == :no_such_value
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
