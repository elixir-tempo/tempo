defmodule Tempo.Iso8601.TimeShiftTest do
  @moduledoc """
  A time shift is a whole number of hours and of minutes (ISO 8601-1
  §4.3.13), and of seconds too in the explicit form (ISO 8601-2 §7.4).

  Its units were read by the combinators that read a time of day's, which
  take a set, a range, unspecified digits, a group, a selection and a
  fraction. A shift written with one raised where the value was read, where
  it was written or where it was compared, and `Tempo.new/1` held whatever
  its caller gave as a shift.

  The offset is measured against `DateTime`: the time a shift is written
  after, less the seconds its units count, is the time in UTC.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.ParseError
  alias Tempo.TimeZoneDatabase

  @wall ~N[2026-06-15 10:00:00]

  # The shift a text holds, written after a time of day in the explicit form.
  defp shift_of(text), do: Tempo.from_iso8601!("2026Y6M15DT10H0M0S" <> text).shift

  # The time in UTC of 10:00:00 on 15 June 2026 written with this shift.
  defp in_utc(text) do
    {:ok, utc} = Tempo.to_datetime(Tempo.from_iso8601!("2026Y6M15DT10H0M0S" <> text))
    DateTime.to_naive(utc)
  end

  defp refused?(text), do: match?({:error, %ParseError{}}, Tempo.from_iso8601(text))

  describe "a time shift in the explicit form" do
    # ISO 8601-2 §7.4, examples 1, 2, 4 to 8, and §7.10: a unit that is zero
    # may be left out, so `Z0S` is UTC to the second and `Z30M` half an hour
    # ahead. Only a shift that began with its hours was read.
    @written [
      {"Z", [hour: 0], 0},
      {"Z8H", [hour: 8], 8 * 3600},
      {"Z-5H", [hour: -5], -5 * 3600},
      {"Z6H0M", [hour: 6, minute: 0], 6 * 3600},
      {"Z7H33M14S", [hour: 7, minute: 33, second: 14], 7 * 3600 + 33 * 60 + 14},
      {"Z0H0M", [hour: 0, minute: 0], 0},
      {"Z0S", [second: 0], 0},
      {"Z30M", [minute: 30], 30 * 60},
      {"Z30S", [second: 30], 30},
      {"Z5M30S", [minute: 5, second: 30], 5 * 60 + 30},
      {"Z1H30S", [hour: 1, second: 30], 3600 + 30},
      {"Z-5H30M", [hour: -5, minute: 30], -(5 * 3600 + 30 * 60)},
      {"Z-0H30M", [hour: 0, minute: -30], -30 * 60},
      {"Z-30M", [minute: -30], -30 * 60},
      {"Z-7H33M14S", [hour: -7, minute: 33, second: 14], -(7 * 3600 + 33 * 60 + 14)},
      {"Z-0H0M14S", [hour: 0, minute: 0, second: -14], -14},
      {"Z+1H", [hour: 1], 3600},
      {"Z24H", [hour: 24], 24 * 3600}
    ]

    test "is its hours, minutes and seconds, any of them left out" do
      for {text, shift, _seconds} <- @written do
        assert {text, shift_of(text)} == {text, shift}
      end
    end

    test "is ahead of UTC by the seconds its units count" do
      for {text, _shift, seconds} <- @written do
        assert {text, in_utc(text)} == {text, NaiveDateTime.add(@wall, -seconds, :second)}
      end
    end

    test "reads back from its own text" do
      for {text, _shift, _seconds} <- @written do
        value = Tempo.from_iso8601!("2026Y6M15DT10H0M0S" <> text)
        assert {text, Tempo.from_iso8601(Tempo.to_iso8601!(value))} == {text, {:ok, value}}
      end
    end

    test "is read alone and after a date" do
      assert Tempo.from_iso8601("Z0S") ==
               {:ok, %Tempo{calendar: Calendrical.Gregorian, time: [], shift: [second: 0]}}

      assert Tempo.from_iso8601!("1985Y4M12DZ30M").shift == [minute: 30]
    end

    test "is written behind UTC with a hyphen or with the minus sign" do
      assert shift_of("Z−5H30M") == [hour: -5, minute: 30]
      assert in_utc("Z−5H30M") == in_utc("Z-5H30M")
    end

    test "is refused where a unit is a set, a range or unspecified digits" do
      for shift <- [
            "Z{1,2}H",
            "Z{1..2}H",
            "Z1H{0,30}M",
            "Z1H0M{1,2}S",
            "Z1H0M{1..2}S",
            "ZXH",
            "ZX*H",
            "Z1HXXM",
            "Z1H0MXXS"
          ] do
        assert {shift, refused?("2026Y6M15DT10H" <> shift)} == {shift, true}
      end
    end

    test "is refused where a unit is a group or a selection" do
      for shift <- ["Z1G2HU", "Z1H1G2MU", "ZL1HN", "Z1HL1MN", "Z1H0ML1SN"] do
        assert {shift, refused?("2026Y6M15DT10H" <> shift)} == {shift, true}
      end
    end

    test "is refused where a unit has a fraction" do
      for shift <- [
            "Z1.5H",
            "Z1,5H",
            "Z1H30.5M",
            "Z1H0M5.5S",
            "Z1H0M5,5S",
            "Z1H0M5.{0..9}S"
          ] do
        assert {shift, refused?("2026Y6M15DT10H" <> shift)} == {shift, true}
      end
    end

    test "is refused where a unit after the first has a sign of its own" do
      for shift <- ["Z1H-30M", "Z-1H-30M", "Z1H0M-5S"] do
        assert {shift, refused?("2026Y6M15DT10H" <> shift)} == {shift, true}
      end
    end

    test "is refused wherever a value with one is written" do
      for text <- [
            "T10H/T11HZ1H0M5.5S",
            "{T10HZ1H0M5.5S,T11H}",
            "R/T10HZ1H0M{1,2}S/PT1H",
            "T10HZ{1,2}H"
          ] do
        assert {text, refused?(text)} == {text, true}
      end
    end

    test "has the minutes of an hour and the seconds of a minute" do
      for shift <- ["Z1H60M", "Z90M", "Z1H0M60S", "Z1H60S"] do
        assert {:error, %ParseError{} = error} = Tempo.from_iso8601("2026Y6M15DT10H" <> shift)
        assert Exception.message(error) =~ "minutes and seconds are from 0 to 59"
      end
    end

    test "is no longer than a day" do
      for shift <- ["Z25H", "Z28H", "Z24H1M", "Z-24H0M1S"] do
        assert {:error, %ParseError{} = error} = Tempo.from_iso8601("2026Y6M15DT10H" <> shift)
        assert Exception.message(error) =~ "within ±24h"
      end
    end
  end

  describe "a time shift written with a sign" do
    # ISO 8601-1 §4.3.13: `[±][hour][min]`, `[±][hour]` and
    # `[±][hour][":"][min]`.
    test "is two digits of hours and two of minutes" do
      for {text, shift, seconds} <- [
            {"2026-06-15T10:00:00+01", [hour: 1], 3600},
            {"2026-06-15T10:00:00+01:00", [hour: 1, minute: 0], 3600},
            {"2026-06-15T10:00:00+0130", [hour: 1, minute: 30], 5400},
            {"20260615T100000+0130", [hour: 1, minute: 30], 5400},
            {"2026-06-15T10:00:00-05:30", [hour: -5, minute: 30], -19_800},
            {"2026-06-15T10:00:00−05:30", [hour: -5, minute: 30], -19_800},
            {"2026-06-15T10:00:00-00:30", [hour: 0, minute: -30], -1800},
            {"2026-06-15T10:00:00Z", [hour: 0], 0}
          ] do
        value = Tempo.from_iso8601!(text)
        {:ok, utc} = Tempo.to_datetime(value)

        assert {text, value.shift} == {text, shift}

        assert {text, DateTime.to_naive(utc)} ==
                 {text, NaiveDateTime.add(@wall, -seconds, :second)}
      end
    end

    # A fraction was taken for part of the hour or the minute it follows, so
    # `+01.5` was an hour and a half and `Tempo.relation/2` raised on it.
    test "has no fraction" do
      for text <- [
            "T10+01.5",
            "T10+01,5",
            "T10:00:00+01:30.5",
            "2026-06-15T10:00+01.5",
            "20260615T1000+01.5"
          ] do
        assert {text, refused?(text)} == {text, true}
      end
    end

    test "is not a set of hours or of minutes" do
      for text <- ["T10:00+{01,02}", "T10:00+01:{00,30}", "T10:00+XX:00"] do
        assert {text, refused?(text)} == {text, true}
      end
    end

    test "has the minutes of an hour" do
      for text <- ["2026-06-15T10:00:00+01:60", "2026-06-15T10:00:00+0160"] do
        assert {:error, %ParseError{} = error} = Tempo.from_iso8601(text)
        assert Exception.message(error) =~ "minutes and seconds are from 0 to 59"
      end
    end

    test "ends at the comma after a member of a set" do
      assert %Tempo.Set{set: [first, second]} = Tempo.from_iso8601!("{T10:30+01,T11:30+01}")
      assert {first.shift, second.shift} == {[hour: 1], [hour: 1]}
    end
  end

  describe "a numeric offset in an IXDTF suffix" do
    # RFC 3339 §5.6: `time-minute` is 00 to 59. `[+01:60]` was read as
    # `[+02:00]`.
    test "has the minutes of an hour" do
      for text <- [
            "2026-06-15T10:00[+01:60]",
            "2026-06-15T10:00[+0160]",
            "2026-06-15T10:00[+01:99]"
          ] do
        assert {text, refused?(text)} == {text, true}
      end
    end

    test "is read up to fifty-nine minutes" do
      assert Tempo.from_iso8601!("2026-06-15T10:00[+01:59]") ==
               Tempo.from_iso8601!("2026-06-15T10:00[+0159]")

      assert Tempo.to_iso8601!(Tempo.from_iso8601!("2026-06-15T10:00[-00:30]")) ==
               "2026Y6M15DT10H0M[-00:30]"
    end
  end

  describe "an offset that is not a whole number of minutes" do
    # New York kept local mean time until 1883, 4 hours 56 minutes and 2
    # seconds behind UTC. The seconds were dropped from the shift written
    # beside the zone, which was then not the zone's offset.
    test "keeps its seconds in the shift it is written as" do
      {:ok, noon} =
        DateTime.new(
          ~D[1850-06-15],
          ~T[12:00:00],
          "America/New_York",
          TimeZoneDatabase.database()
        )

      assert noon.utc_offset + noon.std_offset == -(4 * 3600 + 56 * 60 + 2)
      assert Tempo.from_elixir(noon).shift == [hour: -4, minute: 56, second: 2]

      {:ok, shifted} = Tempo.shift_zone(~o"1850-06-15T12:00:00Z", "America/New_York")

      assert shifted.shift == [hour: -4, minute: 56, second: 2]
      assert Tempo.to_iso8601!(shifted) == "1850Y6M15DT7H3M58SZ-4H56M2S[America/New_York]"
      assert Tempo.from_iso8601(Tempo.to_iso8601!(shifted)) == {:ok, shifted}
    end

    test "is still written to the minute where it has no seconds" do
      {:ok, shifted} = Tempo.shift_zone(~o"2026-06-15T12:00:00Z", "Asia/Kolkata")
      assert shifted.shift == [hour: 5, minute: 30]

      {:ok, shifted} = Tempo.shift_zone(~o"2026-06-15T12:00:00Z", "America/New_York")
      assert shifted.shift == [hour: -4]
    end
  end

  describe "a shift given to Tempo.new/1" do
    @date [year: 2026, month: 6, day: 15, hour: 10]

    test "is the shift the same value is read with" do
      for {shift, text} <- [
            {[hour: 1], "2026Y6M15DT10HZ1H"},
            {[hour: 1, minute: 0], "2026Y6M15DT10HZ1H0M"},
            {[hour: -5, minute: 30], "2026Y6M15DT10HZ-5H30M"},
            {[hour: 0, minute: -30], "2026Y6M15DT10HZ-0H30M"},
            {[minute: -30], "2026Y6M15DT10HZ-30M"},
            {[second: 30], "2026Y6M15DT10HZ30S"},
            {[hour: 7, minute: 33, second: 14], "2026Y6M15DT10HZ7H33M14S"},
            {[hour: 0], "2026Y6M15DT10HZ"}
          ] do
        assert {shift, Tempo.new(@date ++ [shift: shift])} ==
                 {shift, Tempo.from_iso8601(text)}
      end
    end

    # Each was held as it was given: a fraction of an hour raised in
    # `Tempo.relation/2`, a set of hours in `Tempo.new/1` itself, and what
    # is no list of units in `inspect/1`.
    test "is refused where it is not whole hours, minutes and seconds in that order" do
      for shift <- [
            [hour: 1.5],
            [hour: [1, 2]],
            [hour: 1..2],
            [hour: {:mask, [:X]}],
            [hour: nil],
            [day: 1],
            [hour: 1, day: 1],
            [minute: 30, hour: 1],
            [hour: 1, hour: 2],
            [{"hour", 1}],
            [1, 2],
            [],
            :utc,
            "+01:00",
            3600,
            %{hour: 1}
          ] do
        assert {:error, %ArgumentError{} = error} = Tempo.new(@date ++ [shift: shift])
        assert Exception.message(error) =~ "A time shift is hours, minutes and seconds"
        assert Exception.message(error) =~ inspect(shift)
      end
    end

    test "is refused where a unit after the first that is not zero has a sign" do
      for shift <- [
            [hour: 1, minute: -30],
            [hour: -1, minute: -30],
            [hour: 0, minute: 30, second: -5]
          ] do
        assert {:error, %ArgumentError{} = error} = Tempo.new(@date ++ [shift: shift])
        assert Exception.message(error) =~ "carries its sign on its first unit that is not zero"
      end
    end

    test "has the minutes of an hour, the seconds of a minute and no more than a day" do
      for shift <- [
            [hour: 1, minute: 60],
            [minute: 90],
            [second: 60],
            [hour: 25],
            [hour: -24, minute: 1]
          ] do
        assert {:error, %ParseError{} = error} = Tempo.new(@date ++ [shift: shift])
        assert Exception.message(error) =~ "Time-zone offset out of range"
      end
    end

    test "is compared by the time it places the value at" do
      {:ok, ahead} = Tempo.new(@date ++ [minute: 0, shift: [minute: 30]])
      utc = ~o"2026Y6M15DT9H30MZ"

      assert Tempo.relation(ahead, utc) == :equals
    end
  end
end
