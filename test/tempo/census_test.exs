defmodule Tempo.CensusTest do
  use ExUnit.Case, async: true

  # The calendar census (`Tempo.Matrix.CalendarCensus`): a value in each full
  # form, each value with no year and each shape, in every calendar module
  # Calendrical ships, held to what the calendar alone says. A value's extent
  # is the span it covers and its walk the values `Enum` yields; a shape's
  # members are the spans `Tempo.to_interval/1` gives. The census works each
  # answer out with the calendar's own functions and `Date`, never with Tempo.
  #
  # The observational Islamic calendars are left out, as the census leaves
  # them apart; selections wait for phase 6.

  alias Tempo.IntervalSet
  alias Tempo.Matrix.CalendarCensus
  alias Tempo.Spans

  @walk_limit 400

  defp extent!(value) do
    {:ok, extent} = Spans.extent(value)
    extent
  end

  defp walked(value) do
    value |> Enum.take(@walk_limit) |> Enum.map(&extent!/1)
  end

  defp starts(value) do
    value |> Enum.take(@walk_limit) |> Enum.map(fn yielded -> yielded |> extent!() |> elem(0) end)
  end

  defp members(value) do
    {:ok, interval} = Tempo.to_interval(value)

    interval
    |> IntervalSet.members()
    |> Enum.map(fn member -> [extent!(member)] end)
  end

  for calendar <- CalendarCensus.calendars() -- CalendarCensus.observed() do
    describe "in #{inspect(calendar)}" do
      test "a value in each full form covers what the calendar says, and is walked by its parts" do
        calendar = unquote(calendar)

        for %{form: form, text: text, expect: expect} <- CalendarCensus.forms(calendar) do
          {span, walk} = CalendarCensus.expected(expect, calendar)
          value = Tempo.from_iso8601!(text, calendar)

          assert {form, text, extent!(value)} == {form, text, span}

          if walk != :unchecked do
            assert {form, text, walked(value)} == {form, text, Enum.take(walk, @walk_limit)}
          end
        end
      end

      test "a value with no year covers what the calendar counts in any year, or needs a year" do
        calendar = unquote(calendar)

        for %{text: text, covers: covers, walk: walk} <- CalendarCensus.no_year(calendar) do
          case covers do
            {:ok, span} ->
              assert {text, Spans.extent(Tempo.from_iso8601!(text, calendar))} ==
                       {text, {:ok, span}}

            :no_such_value ->
              assert {text, match?({:error, _}, Tempo.from_iso8601(text, calendar))} ==
                       {text, true}

            :needs_a_year ->
              :ok
          end

          case walk do
            {:ok, expected} ->
              assert {text, starts(Tempo.from_iso8601!(text, calendar))} == {text, expected}

            {:count, count} ->
              assert {text,
                      Enum.count(Enum.take(Tempo.from_iso8601!(text, calendar), @walk_limit))} ==
                       {text, count}

            :needs_a_year ->
              assert_raise Tempo.ConversionError, fn ->
                Enum.take(Tempo.from_iso8601!(text, calendar), @walk_limit)
              end

            :unchecked ->
              :ok
          end
        end
      end

      test "a value in each shape converts to the spans the calendar says, and is walked by its parts" do
        calendar = unquote(calendar)

        for %{shape: shape, text: text, members: expected, walk: walk} <-
              CalendarCensus.shapes(calendar) do
          value = Tempo.from_iso8601!(text, calendar)
          assert {shape, text, members(value)} == {shape, text, expected}

          case walk do
            {:ok, expected_starts} ->
              assert {shape, text, starts(value)} == {shape, text, expected_starts}

            :unchecked ->
              :ok
          end
        end
      end
    end
  end
end
