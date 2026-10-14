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
  # them apart; selections wait for phase 6. Each value is built from the
  # parts the census gives (decision 48), never read from text.

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Matrix.CalendarCensus
  alias Tempo.Spans

  @walk_limit 400

  # A census entry's parts, built in the calendar it asks.
  defp built({:value, units}, calendar), do: Tempo.new(units ++ [calendar: calendar])

  defp built({:span, from, to}, calendar) do
    with {:ok, from} <- built({:value, from}, calendar),
         {:ok, to} <- built({:value, to}, calendar),
         do: Interval.new(from: from, to: to)
  end

  defp built({:every, count, start, cadence}, calendar) do
    with {:ok, start} <- built({:value, start}, calendar),
         do: Tempo.every(cadence, from: start, count: count)
  end

  defp built!(parts, calendar) do
    {:ok, value} = built(parts, calendar)
    value
  end

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

        for %{form: form, parts: parts, expect: expect} <- CalendarCensus.forms(calendar) do
          {span, walk} = CalendarCensus.expected(expect, calendar)
          value = built!(parts, calendar)

          assert {form, parts, extent!(value)} == {form, parts, span}

          if walk != :unchecked do
            assert {form, parts, walked(value)} == {form, parts, Enum.take(walk, @walk_limit)}
          end
        end
      end

      test "a value with no year covers what the calendar counts in any year, or needs a year" do
        calendar = unquote(calendar)

        for %{parts: parts, covers: covers, walk: walk} <- CalendarCensus.no_year(calendar) do
          case covers do
            {:ok, span} ->
              assert {parts, Spans.extent(built!(parts, calendar))} == {parts, {:ok, span}}

            :no_such_value ->
              assert {parts, match?({:error, _}, built(parts, calendar))} == {parts, true}

            :needs_a_year ->
              :ok
          end

          case walk do
            {:ok, expected} ->
              assert {parts, starts(built!(parts, calendar))} == {parts, expected}

            {:count, count} ->
              assert {parts, Enum.count(Enum.take(built!(parts, calendar), @walk_limit))} ==
                       {parts, count}

            :needs_a_year ->
              assert_raise Tempo.ConversionError, fn ->
                Enum.take(built!(parts, calendar), @walk_limit)
              end

            :unchecked ->
              :ok
          end
        end
      end

      test "a value in each shape converts to the spans the calendar says, and is walked by its parts" do
        calendar = unquote(calendar)

        for %{shape: shape, parts: parts, members: expected, walk: walk} <-
              CalendarCensus.shapes(calendar) do
          value = built!(parts, calendar)
          assert {shape, parts, members(value)} == {shape, parts, expected}

          case walk do
            {:ok, expected_starts} ->
              assert {shape, parts, starts(value)} == {shape, parts, expected_starts}

            :unchecked ->
              :ok
          end
        end
      end
    end
  end
end
