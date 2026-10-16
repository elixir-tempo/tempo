defmodule Tempo.CensusTest do
  use ExUnit.Case, async: true

  # The calendar census (`Tempo.Matrix.CalendarCensus`): a value in each full
  # form, each value with no year, each shape and each selection, in every
  # calendar module Calendrical ships, held to what the calendar alone says. A value's extent
  # is the span it covers and its walk the values `Enum` yields; a shape's
  # members are the spans `Tempo.to_interval/1` gives. The census works each
  # answer out with the calendar's own functions and `Date`, never with Tempo.
  #
  # The answers are read from the conformance fixture `census.json`, which
  # `scripts/conformance_fixtures.exs` writes from the census and the first
  # test holds to it, so that a port runs what this runs. The observational
  # Islamic calendars are left out, as the census leaves them apart. Each
  # value is built from the parts the census gives (decision 48), never read
  # from text.

  alias Tempo.Conformance
  alias Tempo.IntervalSet
  alias Tempo.Matrix.CalendarCensus
  alias Tempo.Spans

  @walk_limit 400

  setup_all do
    %{fixture: Conformance.fixture("census")}
  end

  defp built!(parts, calendar) do
    {:ok, value} = Conformance.built(parts, calendar)
    value
  end

  defp extent!(value) do
    {:ok, extent} = Spans.extent(value)
    extent
  end

  defp walked(value) do
    value
    |> Enum.take(@walk_limit)
    |> Enum.map(&extent!/1)
  end

  defp starts(value) do
    value
    |> Enum.take(@walk_limit)
    |> Enum.map(fn yielded -> yielded |> extent!() |> elem(0) end)
  end

  defp members(value) do
    {:ok, interval} = Tempo.to_interval(value)

    interval
    |> IntervalSet.members()
    |> Enum.map(fn member -> [extent!(member)] end)
  end

  # The fixture's entries of one kind for a calendar.
  defp entries(fixture, kind, calendar) do
    name = Conformance.calendar_name(calendar)
    Enum.filter(fixture[kind], &(&1["calendar"] == name))
  end

  defp spans(listed) do
    Enum.map(listed, &List.to_tuple/1)
  end

  describe "the conformance fixture" do
    test "lists what the census works out from each calendar alone", %{fixture: fixture} do
      census = Conformance.census()

      for kind <- ["calendars", "forms", "no_year", "shapes", "selections"] do
        assert {kind, length(fixture[kind])} == {kind, length(census[kind])}

        for {listed, worked_out} <- Enum.zip(fixture[kind], census[kind]) do
          assert listed == worked_out
        end
      end
    end
  end

  for calendar <- CalendarCensus.calendars() -- CalendarCensus.observed() do
    describe "in #{inspect(calendar)}" do
      test "a value in each full form covers what the calendar says, and is walked by its parts",
           %{fixture: fixture} do
        calendar = unquote(calendar)

        for %{"form" => form, "parts" => written, "extent" => extent, "walk" => walk} <-
              entries(fixture, "forms", calendar) do
          parts = Conformance.parts(written)
          value = built!(parts, calendar)

          assert {form, parts, extent!(value)} == {form, parts, List.to_tuple(extent)}

          if walk != nil do
            expected =
              walk
              |> Enum.take(@walk_limit)
              |> spans()

            assert {form, parts, walked(value)} == {form, parts, expected}
          end
        end
      end

      test "a value with no year covers what the calendar counts in any year, or needs a year",
           %{fixture: fixture} do
        calendar = unquote(calendar)

        for %{"parts" => written, "covers" => covers, "walk" => walk} <-
              entries(fixture, "no_year", calendar) do
          parts = Conformance.parts(written)

          case covers do
            [from, to] ->
              assert {parts, Spans.extent(built!(parts, calendar))} == {parts, {:ok, {from, to}}}

            "no_such_value" ->
              assert {parts, match?({:error, _}, Conformance.built(parts, calendar))} ==
                       {parts, true}

            "needs_a_year" ->
              :ok
          end

          case walk do
            %{"starts" => expected} ->
              assert {parts, starts(built!(parts, calendar))} == {parts, expected}

            %{"count" => count} ->
              assert {parts, Enum.count(Enum.take(built!(parts, calendar), @walk_limit))} ==
                       {parts, count}

            "needs_a_year" ->
              assert_raise Tempo.ConversionError, fn ->
                Enum.take(built!(parts, calendar), @walk_limit)
              end

            nil ->
              :ok
          end
        end
      end

      # A selection of a value no period has is refused, as the value is
      # (decision 79); a day of the week is the calendar's (decision 80).
      test "a selection selects what the calendar says, or is refused for a value no period has",
           %{fixture: fixture} do
        calendar = unquote(calendar)

        for %{"scenario" => scenario, "period" => period, "selection" => parts} = entry <-
              entries(fixture, "selections", calendar) do
          built =
            Conformance.selection_built(
              Conformance.units_of(period),
              Conformance.units_of(parts),
              calendar
            )

          case entry["selected"] do
            "no_such_value" ->
              assert {scenario, match?({:error, %Tempo.InvalidDateError{}}, built)} ==
                       {scenario, true}

            occurrences ->
              {:ok, value} = built
              expected = Enum.map(occurrences, &spans/1)
              assert {scenario, members(value)} == {scenario, expected}
          end
        end
      end

      test "a value in each shape converts to the spans the calendar says, and is walked by its parts",
           %{fixture: fixture} do
        calendar = unquote(calendar)

        for %{"shape" => shape, "parts" => written, "members" => listed, "walk" => walk} <-
              entries(fixture, "shapes", calendar) do
          parts = Conformance.parts(written)
          value = built!(parts, calendar)
          expected = Enum.map(listed, &spans/1)

          assert {shape, parts, members(value)} == {shape, parts, expected}

          if walk != nil do
            assert {shape, parts, starts(value)} == {shape, parts, walk}
          end
        end
      end
    end
  end
end
