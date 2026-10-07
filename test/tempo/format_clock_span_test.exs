defmodule Tempo.FormatClockSpanTest do
  @moduledoc """
  A span of clock times, shown to its end as it is written.

  A span is half-open, and a span of days, months or years is shown to the
  last it holds: three days that end as the 18th begins are "Jun 15 – 17,
  2026". A span of clock times was shown the same way, to its last hour or
  minute, so nine to five was "9 AM – 4 PM" and 9:30 to 10:45 "9:30 – 10:44
  AM". A time is said as it is written, and the span is shown to its end
  (decided 2026-10-08): "9 AM – 5 PM".

  The measure is Elixir's own `Calendar.strftime/2`: the time a span ends
  at, as the locale's twelve-hour clock writes it, is what its words end in.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval

  # The spaces CLDR writes: a thin one each side of the dash of a range, and
  # a narrow no-break one before AM and PM.
  @dash " – "
  @nbsp " "

  # A span as it is written, the time it ends at and the unit it is shown in.
  @spans [
    {"2026-06-15T09/2026-06-15T17", ~T[17:00:00], :hour},
    {"2026-06-15T09:30/2026-06-15T10:45", ~T[10:45:00], :minute},
    {"2026-06-15T10:30:15/2026-06-15T10:30:45", ~T[10:30:45], :second},
    {"2026-06-15T22/2026-06-16T02", ~T[02:00:00], :hour},
    {"2026-06-15T09/2026-06-15T17:30", ~T[17:30:00], :minute},
    {"2026-06-15/2026-06-15T17", ~T[17:00:00], :hour},
    {"2026-06-15T00/2026-06-15T12", ~T[12:00:00], :hour},
    {"2026-06-15T09/2026-06-16T00", ~T[00:00:00], :hour},
    {"2026-06-15T23:30/2026-06-16T00:30", ~T[00:30:00], :minute},
    {"2026-06-15T09[Europe/Paris]/2026-06-15T17[Europe/Paris]", ~T[17:00:00], :hour},
    {"T09/T17", ~T[17:00:00], :hour},
    {"T22/T02", ~T[02:00:00], :hour},
    {"T09:30/T10:45", ~T[10:45:00], :minute}
  ]

  ## The measure

  # A time as the twelve-hour clock of `en` writes it, to a unit.
  defp said(%Time{} = time, :hour), do: Calendar.strftime(time, "%-I#{@nbsp}%p")
  defp said(%Time{} = time, :minute), do: Calendar.strftime(time, "%-I:%M#{@nbsp}%p")
  defp said(%Time{} = time, :second), do: Calendar.strftime(time, "%-I:%M:%S#{@nbsp}%p")

  defp shown(value, options \\ []) do
    {:ok, text} = Tempo.to_string(value, options)
    text
  end

  describe "a span of clock times" do
    test "is shown to the time it ends at, as that time is written" do
      for {text, ends_at, unit} <- @spans do
        words = shown(Tempo.from_iso8601!(text))

        assert {text, String.ends_with?(words, said(ends_at, unit)), words} == {text, true, words}
      end
    end

    test "is nine to five, and half past nine to a quarter to eleven" do
      assert shown(~o"2026-06-15T09/2026-06-15T17") ==
               "Jun 15, 2026, 9#{@nbsp}AM#{@dash}5#{@nbsp}PM"

      assert shown(~o"2026-06-15T09:30/2026-06-15T10:45") ==
               "Jun 15, 2026, 9:30#{@dash}10:45#{@nbsp}AM"

      assert shown(~o"T09/T17") == "9#{@nbsp}AM#{@dash}5#{@nbsp}PM"
      assert shown(~o"2026-06-15T09/2026-06-15T17", locale: :de) == "15.06.2026, 09–17 Uhr"
    end

    test "that ends at midnight is shown to the day it ends on" do
      assert shown(~o"2026-06-15T09/2026-06-16T00") ==
               "Jun 15, 2026, 9#{@nbsp}AM#{@dash}Jun 16, 2026, 12#{@nbsp}AM"
    end

    test "is shown by its minutes to its end where it is walked by them" do
      by_minutes = Interval.new!(from: ~o"2026-06-15T09", to: ~o"2026-06-15T17", unit: :minute)

      assert shown(by_minutes) == "Jun 15, 2026, 9:00#{@nbsp}AM#{@dash}5:00#{@nbsp}PM"
    end

    test "is each of them where a set holds several" do
      {:ok, working} =
        Tempo.difference(~o"2026-06-15T09/2026-06-15T17", ~o"2026-06-15T12/2026-06-15T13")

      assert shown(working) ==
               "Jun 15, 2026, 9#{@nbsp}AM#{@dash}12#{@nbsp}PM and Jun 15, 2026, 1#{@dash}5#{@nbsp}PM"
    end

    test "that starts at a fraction of a second is shown, where it raised" do
      assert shown(Tempo.from_iso8601!("2026-06-15T09:00:00.5/2026-06-15T09:00:02")) ==
               "Jun 15, 2026, 9:00:00#{@nbsp}AM#{@dash}Jun 15, 2026, 9:00:02#{@nbsp}AM"
    end
  end

  describe "a span one hour, one minute or one second long" do
    test "is the value it is, however it is written" do
      for {span, value} <- [
            {"2026-06-15T10/2026-06-15T11", "2026-06-15T10"},
            {"2026-06-15T23/2026-06-16T00", "2026-06-15T23"},
            {"2026-06-15T10:00/2026-06-15T10:01", "2026-06-15T10:00"},
            {"2026-06-15T10:30:15/2026-06-15T10:30:16", "2026-06-15T10:30:15"},
            {"T10/T11", "T10"}
          ] do
        assert {span, shown(Tempo.from_iso8601!(span))} ==
                 {span, shown(Tempo.from_iso8601!(value))}
      end
    end

    test "is not what sixty minutes written as minutes are" do
      assert shown(~o"2026-06-15T10:00/2026-06-15T11:00") ==
               "Jun 15, 2026, 10:00#{@dash}11:00#{@nbsp}AM"
    end

    test "is the value where it holds no time at all" do
      # It was shown backwards, "10 – 9 AM".
      assert shown(~o"2026-06-15T10/2026-06-15T10") == shown(~o"2026-06-15T10")
    end
  end

  describe "a span of days, months or years" do
    test "is shown to the last it holds, as it was" do
      last_day = Date.add(~D[2026-06-18], -1)
      assert last_day == ~D[2026-06-17]

      assert shown(~o"2026-06-15/2026-06-18") == "Jun 15#{@dash}17, 2026"
      assert shown(~o"2026-06/2026-09") == "Jun#{@dash}Aug 2026"
      assert shown(~o"2026/2029") == "2026#{@dash}2028"

      # Midnight to midnight is the days between them.
      assert shown(~o"2026-06-15T00/2026-06-18T00") == shown(~o"2026-06-15/2026-06-18")
    end

    test "is one value where it is one of them" do
      assert shown(Tempo.to_interval!(~o"2026-06-15")) == shown(~o"2026-06-15")
    end
  end
end
