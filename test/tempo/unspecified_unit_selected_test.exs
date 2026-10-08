defmodule Tempo.UnspecifiedUnitSelectedTest do
  @moduledoc """
  An unspecified unit (`X*`) in a constraint and in a selection.

  It stands for every value its unit takes in the period, as a mask of as
  many digits does (`XX` of a month's days). A constraint written with one
  was placed on its period and was the period's one span, from a day it
  selected nothing, and a selection written with one selected nothing: the
  resolver passed the part over.

  The measure is Elixir's own `Date`, and the same constraint written with
  a digit for each place.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  defp seconds(%Date{} = date),
    do:
      date |> NaiveDateTime.new!(~T[00:00:00]) |> NaiveDateTime.to_gregorian_seconds() |> elem(0)

  defp day_spans(dates), do: for(date <- dates, do: {seconds(date), seconds(Date.add(date, 1))})

  defp spans({:ok, %IntervalSet{} = set}) do
    for span <- IntervalSet.members(set) do
      {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}
    end
  end

  describe "an unspecified day, as a constraint" do
    test "is each day of the month it is selected from" do
      for {month, first} <- [{~o"2026-06", ~D[2026-06-01]}, {~o"2024-02", ~D[2024-02-01]}] do
        assert {month, spans(Tempo.select(month, ~o"X*D"))} ==
                 {month, day_spans(Date.range(first, Date.end_of_month(first)))}
      end
    end

    test "keeps the day it is asked of, and each day of a span of days" do
      assert spans(Tempo.select(~o"2026-06-15", ~o"X*D")) == day_spans([~D[2026-06-15]])

      assert spans(Tempo.select(~o"2026-06-15/2026-06-18", ~o"X*D")) ==
               day_spans(Date.range(~D[2026-06-15], ~D[2026-06-17]))
    end
  end

  describe "an unspecified unit" do
    test "is the values a mask of as many digits names" do
      for {base, unspecified, masked} <- [
            {~o"2026-06", ~o"X*D", ~o"XXD"},
            {~o"2026", ~o"X*M", ~o"XXM"},
            {~o"2026", ~o"X*M15D", ~o"XXM15D"},
            {~o"2026-06-15", ~o"TX*H", ~o"TXXH"},
            {~o"2026-06-15", ~o"T10HX*M", ~o"T10HXXM"},
            {~o"2026-06", ~o"X*W", ~o"XW"},
            {~o"2026-06", ~o"LX*DN", ~o"LXXDN"},
            {~o"2026", ~o"LX*M15DN", ~o"LXXM15DN"}
          ] do
        assert {unspecified, spans(Tempo.select(base, unspecified))} ==
                 {unspecified, spans(Tempo.select(base, masked))}

        assert {unspecified, spans(Tempo.select(base, unspecified))} != {unspecified, []}
      end
    end

    test "is every value in a selection written after a value, and in a rule" do
      june = day_spans(Date.range(~D[2026-06-01], ~D[2026-06-30]))

      assert spans(Tempo.to_interval(~o"2026Y6MLX*DN")) == june

      assert spans(Tempo.to_interval(~o"R/2026-06-01/P1D/FLX*DN", within: ~o"2026-06")) == june
    end
  end

  describe "an unspecified unit, written and worded" do
    test "is worded by Tempo.explain/1 as it is written, which raised" do
      assert to_string(Tempo.explain(~o"2026Y6MLX*DN")) =~ "on a day written X*"

      assert to_string(Tempo.explain(~o"R/2026-06-01/P1D/FLTX*HN")) =~ "at an hour written X*"
    end

    test "is no part of an RRULE, which the writer says where it raised" do
      assert {:error, %ConversionError{target: :rrule} = error} =
               RRule.to_string(~o"R/2026-06-01/P1M/FLX*DN")

      assert Exception.message(error) =~ "unspecified digits"
    end
  end
end
