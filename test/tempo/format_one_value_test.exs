defmodule Tempo.FormatOneValueTest do
  @moduledoc """
  A value and the interval it converts to are shown alike.

  `Tempo.to_string/2` shows an hour as the one value it is ("10 AM"). The
  interval the hour converts to carries the unit it is walked by, and was
  shown in that unit, as its first and last minutes ("10:00 – 10:59 AM"):
  so were the members of a set of hours, and a minute was its first and
  last seconds.

  The measure is the value's own words, which the conversion must not
  change, beside what those words are for one value of each resolution.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval

  @values [
    "2026",
    "2026-06",
    "2026-W25",
    "2026-06-15",
    "2026-06-15T00",
    "2026-06-15T10",
    "2026-06-15T23",
    "2026-06-15T10:00",
    "2026-06-15T10:30",
    "2026-06-15T23:59",
    "2026-06-15T10:30:00",
    "2026-06-15T10:30:15",
    "2026-06-15T10[Europe/Paris]",
    "2026-06-15T10:30Z",
    "T10",
    "T10:30",
    "6M15D"
  ]

  defp shown(value, options \\ []) do
    {:ok, text} = Tempo.to_string(value, options)
    text
  end

  describe "the interval a value converts to" do
    test "is shown as the value is" do
      for text <- @values, options <- [[], [format: :long], [locale: :de]] do
        value = Tempo.from_iso8601!(text)
        {:ok, interval} = Tempo.to_interval(value)

        assert {text, options, shown(interval, options)} == {text, options, shown(value, options)}
      end
    end

    test "is one hour, one minute or one second in the locale's words" do
      assert shown(Tempo.to_interval!(~o"2026-06-15T10")) == "Jun 15, 2026, 10 AM"
      assert shown(Tempo.to_interval!(~o"2026-06-15T10:30")) == "Jun 15, 2026, 10:30 AM"
      assert shown(Tempo.to_interval!(~o"2026-06-15T10:30:15")) == "Jun 15, 2026, 10:30:15 AM"
      assert shown(Tempo.to_interval!(~o"T10")) == "10 AM"
    end
  end

  describe "a value that names several hours or minutes" do
    test "is each of them, shown as the value it is" do
      assert shown(~o"2026Y6M15DT{9,14}H") ==
               "#{shown(~o"2026-06-15T09")} and #{shown(~o"2026-06-15T14")}"

      assert shown(~o"2026Y6M15DT10H{0,30}M") ==
               "#{shown(~o"2026-06-15T10:00")} and #{shown(~o"2026-06-15T10:30")}"

      assert shown(~o"2026Y6M15DT{9,14}H") == "Jun 15, 2026, 9 AM and Jun 15, 2026, 2 PM"
    end
  end

  describe "a span of several hours" do
    test "is shown from its first to its last, as it was" do
      assert shown(~o"2026-06-15T09/2026-06-15T17") ==
               "Jun 15, 2026, 9 AM – 4 PM"

      # One written to be walked by its minutes is shown by them.
      by_minutes =
        Interval.new!(from: ~o"2026-06-15T09", to: ~o"2026-06-15T17", unit: :minute)

      assert shown(by_minutes) == "Jun 15, 2026, 9:00 AM – 4:59 PM"
    end
  end
end
