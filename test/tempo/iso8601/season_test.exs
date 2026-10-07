defmodule Tempo.Iso8601.SeasonTest do
  @moduledoc """
  A season (ISO 8601-2 Table 2: the numbers 21 to 32, written where a month
  is) is a span of dates, and is read as the interval it is. What its value
  holds beside its units is each end's: what qualifies it, and the zone, the
  calendar and the tags of its own suffix. At an end of an interval it is
  where its span starts, as a month is.

  A qualified season was read with nothing qualifying it, a member of a set
  written with a zone of its own lost the zone, and an interval from one
  season to another was an interval of two intervals, which nothing read.

  The measure is the same span written out: the spring of 2026 is March to
  May, `2026-03/2026-06`.
  """
  use ExUnit.Case, async: true

  defp read(text), do: Tempo.from_iso8601!(text)

  defp reads_back?(value), do: read(Tempo.to_iso8601!(value)) == value

  describe "a qualified season" do
    test "is its span with each end qualified" do
      for {season, written_out} <- [
            {"2026-21?", "2026-03?/2026-06?"},
            {"2026-21~", "2026-03~/2026-06~"},
            {"2026-22%", "2026-06%/2026-09%"},
            {"2026-23?", "2026-09?/2026-12?"},
            {"2026-21", "2026-03/2026-06"}
          ] do
        assert {season, read(season)} == {season, read(written_out)}
      end
    end

    test "is qualified at each end by a qualifier of its year, which each date is worked out from" do
      assert read("?2026-21") == read("2026-03?/2026-06?")
      assert read("2026?-21") == read("2026-03?/2026-06?")
    end

    test "reads back from its own text" do
      for season <- ["2026-21?", "2026-22~", "2026-25?", "2026-28%", "?2026-21"] do
        assert {season, reads_back?(read(season))} == {season, true}
      end
    end

    test "is qualified as a member of a set, and at the end of a range of seasons" do
      assert %Tempo.Set{set: [spring, summer]} = read("{2026-21?,2026-22}")
      assert {spring, summer} == {read("2026-03?/2026-06?"), read("2026-06/2026-09")}

      assert %Tempo.Set{set: [first, second, third]} = read("{2026-21?..2026-23}")

      assert {first, second, third} ==
               {read("2026-03?/2026-06?"), read("2026-06/2026-09"), read("2026-09/2026-12")}
    end
  end

  describe "a season with a suffix of its own" do
    test "is its span in that zone" do
      assert read("2026-21[Europe/Paris]") ==
               read("2026-03[Europe/Paris]/2026-06[Europe/Paris]")
    end

    test "keeps it as a member of a set" do
      assert %Tempo.Set{set: [spring, summer]} = read("{2026-21[Europe/Paris],2026-22}")

      assert {spring, summer} ==
               {read("2026-03[Europe/Paris]/2026-06[Europe/Paris]"), read("2026-06/2026-09")}
    end
  end

  describe "a season at an end of an interval" do
    test "is where its span starts, as a month is" do
      for {interval, written_out} <- [
            {"2026-21/2026-23", "2026-03/2026-09"},
            {"2026-21/2026-24", "2026-03/2026-12"},
            {"2026-24/2027-21", "2026-12/2027-03"},
            {"2026-21/2026-09", "2026-03/2026-09"},
            {"2026-03/2026-23", "2026-03/2026-09"},
            {"2026-21/P1M", "2026-03/P1M"},
            {"2026-21/..", "2026-03/.."},
            {"../2026-23", "../2026-09"},
            {"2026-21?/2026-23", "2026-03?/2026-09"},
            {"R3/2026-21/P1Y", "R3/2026-03/P1Y"}
          ] do
        assert {interval, read(interval)} == {interval, read(written_out)}
      end
    end

    test "reads back from its own text" do
      for interval <- ["2026-21/2026-23", "2026-25/2026-27", "2026-21?/2026-23", "2026-21/P1M"] do
        assert {interval, reads_back?(read(interval))} == {interval, true}
      end
    end

    test "is refused where the end's season starts before the start's" do
      # A winter starts in the December of its year, after that year's
      # spring, summer and autumn: EDTF's corpus lists `2012-24/2012-21`
      # and `2012-23/2012-22` as no intervals.
      for interval <- ["2026-24/2026-21", "2026-24/2026-23", "2026-23/2026-22", "2012-24/2012-21"] do
        assert {^interval, {:error, %Tempo.IntervalEndpointsError{}}} =
                 {interval, Tempo.from_iso8601(interval)}
      end
    end
  end
end
