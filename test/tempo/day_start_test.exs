defmodule Tempo.DayStartTest do
  use ExUnit.Case, async: true

  # Decision 91: a day of a calendar that begins at sunset is placed on the
  # UTC line from the sunset it begins at to the one it ends at, at the
  # calendar's own place, by Calendrical's `day_bounds/1`.

  import Tempo.Sigils

  alias Calendrical.Hebrew
  alias Tempo.{ConversionError, DateRule, Interval, IntervalSet}

  defp hebrew(text), do: Tempo.from_iso8601!(text <> "[u-ca=hebrew]")

  defp instants(expression) do
    {:ok, instants} = Interval.instants(expression)
    instants
  end

  # Two instants at UTC in the ISO calendar, as Calendrical gives a day's bounds.
  defp utc({from, to}) do
    {iso_utc(from), iso_utc(to)}
  end

  defp iso_utc(instant) do
    instant
    |> DateTime.convert!(Calendar.ISO)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  describe "a day of a calendar whose day begins at sunset" do
    test "runs from the sunset of the evening before to its own, as Calendrical bounds it" do
      {:ok, passover} = Tempo.day_start(hebrew("5786Y7m15D"))

      {:ok, {start, stop}} =
        Hebrew.day_bounds(Date.convert!(~D[2026-04-02], Hebrew))

      assert utc(instants(passover)) ==
               {DateTime.truncate(start, :second), DateTime.truncate(stop, :second)}
    end

    test "is on the clock of the calendar's own place, in the calendar" do
      {:ok, passover} = Tempo.day_start(hebrew("5786Y7m15D"))
      {:ok, eid} = Tempo.day_start(~o"1446Y10M1D[u-ca=islamic-umalqura]")

      assert Tempo.to_iso8601!(passover) =~ "[Asia/Jerusalem][u-ca=hebrew]"
      assert Tempo.to_iso8601!(eid) =~ "[Asia/Riyadh][u-ca=islamic-umalqura]"
      assert Tempo.zoned?(passover) and Tempo.zoned?(eid)
    end

    test "keeps its metadata" do
      day = Tempo.put_metadata(hebrew("5786Y7m15D"), %{name: "Pesach"})
      {:ok, placed} = Tempo.day_start(day)

      assert Tempo.metadata(placed) == %{name: "Pesach"}
    end
  end

  describe "days together" do
    test "a run of days is from the sunset before its first to the sunset of its last" do
      {:ok, week} = Tempo.day_start(hebrew("5786Y7m15D/7m21D"))
      {:ok, first} = Tempo.day_start(hebrew("5786Y7m15D"))
      {:ok, last} = Tempo.day_start(hebrew("5786Y7m21D"))

      assert elem(instants(week), 0) == elem(instants(first), 0)
      assert elem(instants(week), 1) == elem(instants(last), 1)
    end

    test "consecutive days meet, each ending where the next begins" do
      {:ok, days} = Tempo.day_start(hebrew("{5786Y7m15D,5786Y7m16D,5786Y7m17D}"))

      spans = days |> IntervalSet.members() |> Enum.map(&instants/1)

      for {{_from, to}, {next_from, _next_to}} <- Enum.zip(spans, tl(spans)) do
        assert DateTime.compare(to, next_from) == :eq
      end
    end

    test "a rule placed in a window, and a rule with no end placed as it is walked" do
      {:ok, rule} = DateRule.parse("15 Nisan")
      {:ok, three_years} = Tempo.to_interval(rule, within: ~o"2026/2028")
      {:ok, placed} = Tempo.day_start(three_years)

      assert IntervalSet.count(placed) == 3

      endless =
        Tempo.every!(~o"P1Y", from: hebrew("5786Y1M1D"), select: [traditional_month: 7, day: 15])

      {:ok, walked} = Tempo.day_start(endless)
      [first | _] = walked |> IntervalSet.walk() |> Enum.take(2)

      assert first == IntervalSet.members(placed) |> hd()
    end
  end

  describe "a calendar whose day begins at midnight" do
    test "is returned as it is" do
      for expression <- [~o"2026-04-02", ~o"2026-04-02/2026-04-08", ~o"{2026-01-01,2026-12-25}"] do
        assert Tempo.day_start(expression) == {:ok, expression}
      end
    end
  end

  describe "what has no day start" do
    test "a month, a time of day or a duration is not days" do
      for expression <- [hebrew("5786Y7m"), hebrew("5786Y7m15DT10H"), ~o"P1D"] do
        assert {:error, %ConversionError{reason: :not_days}} = Tempo.day_start(expression)
      end
    end

    test "a rule with no start, until it is placed in a window" do
      {:ok, rule} = DateRule.parse("15 Nisan")

      assert {:error, %ConversionError{reason: :unbounded}} = Tempo.day_start(rule)
    end

    test "a value that is no expression" do
      assert {:error, %ConversionError{reason: :not_an_expression}} =
               Tempo.day_start("5786-07-15")
    end
  end
end
