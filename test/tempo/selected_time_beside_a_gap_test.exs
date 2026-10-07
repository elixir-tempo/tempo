defmodule Tempo.SelectedTimeBesideAGapTest do
  @moduledoc """
  A time a rule selects where the clock of its zone skips its start.

  Lord Howe's clocks go from 02:00 to 02:30 on the first Sunday of October,
  so the hour from 02:00 that morning is the half of it the clock shows,
  from 02:30 to 03:00. The value `T2H` there is that half hour, and
  `Tempo.select/2` gives it so. A value's selection and a recurrence's rule
  gave the hour as running to 03:30, an hour counted from the reading the
  clock comes out on and half an hour into the hour after it; each is the
  part the clock shows (decided 2026-10-08).

  The measure is Elixir's own `DateTime`: the moments the clock of the zone
  shows a reading of the hour, from the first to the one the next hour
  starts at.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RRule

  @zone "Australia/Lord_Howe"
  @epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  ## The measure

  # The moment a clock time of a day is in the zone.
  defp moment(%Date{} = day, %Time{} = time, zone),
    do: DateTime.to_unix(DateTime.new!(day, time, zone)) + @epoch

  # The first moment the clock shows a reading of an hour of a day.
  defp first_shown(%Date{} = day, hour, zone) do
    minute =
      Enum.find(0..59, fn minute ->
        match?({:ok, _shown}, DateTime.new(day, Time.new!(hour, minute, 0), zone))
      end)

    moment(day, Time.new!(hour, minute, 0), zone)
  end

  # The moments an hour of a day runs between, as the clock shows it: from
  # its first reading to the first of the hour after it.
  defp hour_shown(%Date{} = day, hour, zone),
    do: {first_shown(day, hour, zone), first_shown(day, hour + 1, zone)}

  defp bounds(%Interval{} = span),
    do: {Compare.to_utc_seconds(Interval.from(span)), Compare.to_utc_seconds(Interval.to(span))}

  defp spans({:ok, %IntervalSet{} = set}), do: Enum.map(IntervalSet.members(set), &bounds/1)

  defp read(text), do: Tempo.from_iso8601!(text)

  describe "the hour the clock skips the first half of" do
    test "is half an hour long, by the clock" do
      assert {:gap, _before, _after} = DateTime.new(~D[2026-10-04], ~T[02:15:00], @zone)

      {from, to} = hour_shown(~D[2026-10-04], 2, @zone)
      assert to - from == 1_800
      assert from == moment(~D[2026-10-04], ~T[02:30:00], @zone)
    end

    test "is the part the clock shows where a value's selection picks it" do
      assert spans(Tempo.to_interval(read("2026Y10M4DLT2HN[#{@zone}]"))) ==
               [hour_shown(~D[2026-10-04], 2, @zone)]
    end

    test "ends where the hour after it starts, each hour picked being apart from the next" do
      picked = spans(Tempo.to_interval(read("2026Y10M4DLT{1,2,3}HN[#{@zone}]")))

      assert picked == for(hour <- 1..3, do: hour_shown(~D[2026-10-04], hour, @zone))

      # They are an hour, half an hour and an hour, one after another.
      assert Enum.map(picked, fn {from, to} -> to - from end) == [3_600, 1_800, 3_600]

      for [{_from, ends}, {starts, _to}] <- Enum.chunk_every(picked, 2, 1, :discard) do
        assert ends == starts
      end
    end

    test "is the part the clock shows on that day of a recurrence, and an hour on the days beside it" do
      days = [~D[2026-10-03], ~D[2026-10-04], ~D[2026-10-05]]
      expected = Enum.map(days, &hour_shown(&1, 2, @zone))

      for text <- ["R3/2026-10-03T00[#{@zone}]/P1D/FLT2HN", "R3/2026-10-03[#{@zone}]/P1D/FLT2HN"] do
        assert {text, spans(Tempo.to_interval(read(text)))} == {text, expected}
      end

      {:ok, rule} =
        RRule.parse("FREQ=DAILY;BYHOUR=2;COUNT=3", from: read("2026-10-03T00[#{@zone}]"))

      assert spans(Tempo.to_interval(rule)) == expected

      assert Enum.map(expected, fn {from, to} -> to - from end) == [3_600, 1_800, 3_600]
    end

    test "is what the value of that hour is, and what select/2 gives" do
      {:ok, own} = Tempo.to_interval(read("2026-10-04T02[#{@zone}]"))

      assert spans(Tempo.to_interval(read("2026Y10M4DLT2HN[#{@zone}]"))) == [bounds(own)]
      assert spans(Tempo.select(read("2026-10-04[#{@zone}]"), ~o"T2H")) == [bounds(own)]
    end
  end

  describe "a time selected where the clock skips none of it, or all" do
    test "is an hour where the clock shows the whole of it" do
      # The hour before the change, and an hour of a day with none.
      for {text, day, hour} <- [
            {"2026Y10M4DLT1HN[#{@zone}]", ~D[2026-10-04], 1},
            {"2026Y10M4DLT3HN[#{@zone}]", ~D[2026-10-04], 3},
            {"2026Y6M15DLT2HN[#{@zone}]", ~D[2026-06-15], 2}
          ] do
        assert {text, spans(Tempo.to_interval(read(text)))} ==
                 {text, [hour_shown(day, hour, @zone)]}
      end
    end

    test "is not selected where the clock skips the whole of it, as it was" do
      # New York's clocks go from 02:00 to 03:00 on 8 March 2026.
      assert {:gap, _before, _after} =
               DateTime.new(~D[2026-03-08], ~T[02:30:00], "America/New_York")

      assert spans(Tempo.to_interval(read("2026Y3M8DLT2HN[America/New_York]"))) == []
    end

    test "is a minute where a minute is selected" do
      # 02:00 is skipped whole, and 02:30 is the first minute the clock shows.
      assert spans(Tempo.to_interval(read("2026Y10M4DLT2H{0,30}MN[#{@zone}]"))) ==
               [
                 {moment(~D[2026-10-04], ~T[02:30:00], @zone),
                  moment(~D[2026-10-04], ~T[02:31:00], @zone)}
               ]
    end
  end
end
