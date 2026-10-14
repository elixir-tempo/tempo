defmodule Tempo.ZoneValidationTest do
  use ExUnit.Case, async: true

  # What a zone's clock makes of a reading: one it shows twice is told apart
  # by a shift, one it skips is refused, an old name is the zone it names,
  # and an offset is within a day. Each instant is held to Elixir's
  # `DateTime`, which reads the zone database apart from the library.
  #
  # The readings are New York's: its clock goes from 02:00 to 03:00 on the
  # second Sunday of March, so 2024-03-10 02:00 to 03:00 is skipped, and
  # from 02:00 back to 01:00 on the first Sunday of November, so 2024-11-03
  # 01:00 to 02:00 is shown twice.

  # The instant a text names, in seconds since 1970.
  defp unix(text) do
    {:ok, date_time} = Tempo.to_datetime(Tempo.from_iso8601!(text))
    DateTime.to_unix(date_time)
  end

  describe "a reading the clock shows twice" do
    test "is read, and is the first showing where no shift says which" do
      {:ambiguous, first, _second} =
        DateTime.new(~D[2024-11-03], ~T[01:30:00], "America/New_York")

      assert unix("2024-11-03T01:30:00[America/New_York]") == DateTime.to_unix(first)
    end

    test "is the showing its shift says" do
      {:ambiguous, first, second} = DateTime.new(~D[2024-11-03], ~T[01:30:00], "America/New_York")

      assert unix("2024-11-03T01:30:00-04:00[America/New_York]") == DateTime.to_unix(first)
      assert unix("2024-11-03T01:30:00-05:00[America/New_York]") == DateTime.to_unix(second)
      assert DateTime.to_unix(second) - DateTime.to_unix(first) == 3_600
    end

    # RFC 9557 section 3.4: an offset that is neither of the two disagrees
    # with the zone, and gives the moment.
    test "with a shift that is neither showing's is the moment the shift gives" do
      moment = DateTime.new!(~D[2024-11-03], ~T[01:30:00], "Etc/UTC")

      assert unix("2024-11-03T01:30:00+00:00[America/New_York]") == DateTime.to_unix(moment)
    end
  end

  describe "a reading the clock skips" do
    test "is refused from the first second of the gap to the last" do
      for text <- [
            "2024-03-10T02:00:00[America/New_York]",
            "2024-03-10T02:30:00[America/New_York]",
            "2024-03-10T02:59:59[America/New_York]"
          ] do
        assert {^text, {:error, %Tempo.ZoneError{reason: :gap}}} =
                 {text, Tempo.from_iso8601(text)}
      end
    end

    test "is every minute of the gap" do
      for minute <- 0..59 do
        assert {^minute, {:error, %Tempo.ZoneError{reason: :gap}}} =
                 {minute,
                  Tempo.new(
                    year: 2024,
                    month: 3,
                    day: 10,
                    hour: 2,
                    minute: minute,
                    zone: "America/New_York"
                  )}
      end
    end

    test "is not the second before the gap nor the first after it" do
      for {text, time} <- [
            {"2024-03-10T01:30:00[America/New_York]", ~T[01:30:00]},
            {"2024-03-10T01:59:59[America/New_York]", ~T[01:59:59]},
            {"2024-03-10T03:00:00[America/New_York]", ~T[03:00:00]},
            {"2024-03-10T03:30:00[America/New_York]", ~T[03:30:00]}
          ] do
        {:ok, shown} = DateTime.new(~D[2024-03-10], time, "America/New_York")
        assert {text, unix(text)} == {text, DateTime.to_unix(shown)}
      end
    end

    test "names its zone in what it says" do
      {:error, error} = Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")
      assert Exception.message(error) =~ "America/New_York"
    end

    test "is refused at an end of an interval" do
      assert {:error, %Tempo.ZoneError{reason: :gap}} =
               Tempo.from_iso8601("2024-03-10T02:30:00/2024-03-10T05:00:00[America/New_York]")

      assert {:ok, _} =
               Tempo.from_iso8601("2024-03-10T01:30:00/2024-03-10T05:00:00[America/New_York]")
    end

    test "is no matter with no zone, or at a fixed offset" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T02:30:00")
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T02:30:00+05:30")
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10[America/New_York]")
      assert {:ok, _} = Tempo.from_iso8601("2024-03[America/New_York]")
    end
  end

  describe "an old name of a zone" do
    # The zone database keeps the names zones have had: `US/Pacific` is
    # `America/Los_Angeles`, and `Asia/Calcutta` is `Asia/Kolkata`.
    test "is read, kept as it is written, and is the zone it names" do
      for {text, current, written} <- [
            {"2024-06-15T12:00:00[US/Pacific]", "America/Los_Angeles",
             "2024Y6M15DT12H0M0S[US/Pacific]"},
            {"2024-06-15T12:00:00[Asia/Calcutta]", "Asia/Kolkata",
             "2024Y6M15DT12H0M0S[Asia/Calcutta]"},
            {"2024-06-15T12:00:00[Pacific/Enderbury]", "Pacific/Kanton",
             "2024Y6M15DT12H0M0S[Pacific/Enderbury]"}
          ] do
        {:ok, shown} = DateTime.new(~D[2024-06-15], ~T[12:00:00], current)

        assert {text, unix(text)} == {text, DateTime.to_unix(shown)}
        assert Tempo.to_iso8601!(Tempo.from_iso8601!(text)) == written
      end
    end
  end

  describe "a zone's offset in the past" do
    # British Double Summer Time ran from May 1941: London's clocks were two
    # hours ahead of UTC, where its summer offset is one.
    test "is the offset the zone had then" do
      assert unix("1941-06-15T12:00:00Z") - unix("1941-06-15T12:00:00[Europe/London]") == 7_200
    end
  end

  describe "an offset" do
    test "is within a day" do
      for text <- [
            "2024-03-10T12:00:00+14:00",
            "2024-03-10T12:00:00-12:00",
            "2024-03-10T12:00:00Z",
            "2024-03-10T12:00:00[+14:00]"
          ] do
        assert {^text, {:ok, _}} = {text, Tempo.from_iso8601(text)}
      end

      for text <- [
            "2024-03-10T12:00:00+25:00",
            "2024-03-10T12:00:00-25:00",
            "2024-03-10T12:00:00[+25:00]"
          ] do
        assert {^text, {:error, _}} = {text, Tempo.from_iso8601(text)}
      end
    end
  end

  describe "the length of a span across a change of the clock" do
    import Tempo.Sigils

    # Noon to noon is twenty-four hours of the clock, and one fewer or one
    # more of time where the clock goes forward or back between them.
    test "is the time between its ends, and not the hours its clock shows" do
      assert Tempo.duration(~o"2024-03-09T12/2024-03-10T12[America/New_York]") == ~o"PT23H"
      assert Tempo.duration(~o"2024-11-02T12/2024-11-03T12[America/New_York]") == ~o"PT25H"
      assert Tempo.duration(~o"2024-06-15T12/2024-06-16T12[America/New_York]") == ~o"PT24H"
      assert Tempo.duration(~o"2024-03-09T12/2024-03-10T12") == ~o"PT24H"
    end
  end

  # RFC 9557 section 3.4, and its figures 1 and 2. London's clock is an hour
  # ahead of UTC in July, so `+00:00` beside it says a local time it does not
  # show. With the critical flag an application must act on that; without
  # it, it may. `Z` says no local time, and is never at odds with a zone.
  describe "a time shift a zone does not have then" do
    defp read(text), do: Tempo.from_iso8601(text)

    test "is refused where the zone is critical" do
      assert {:error, %Tempo.ZoneError{reason: :inconsistent, zone: "Europe/London"} = error} =
               read("2022-07-08T00:14:07+00:00[!Europe/London]")

      assert Exception.message(error) =~ "does not have then"
    end

    test "is the moment the shift gives where the zone is not critical" do
      assert {:ok, _} = read("2022-07-08T00:14:07+00:00[Europe/London]")
      assert unix("2022-07-08T00:14:07+00:00[Europe/London]") == unix("2022-07-08T00:14:07Z")
    end

    test "is no matter where the shift is Z, critical or not" do
      for text <- ["2022-07-08T00:14:07Z[!Europe/London]", "2022-07-08T00:14:07Z[Europe/London]"] do
        assert {:ok, _} = read(text)
        assert unix(text) == DateTime.to_unix(~U[2022-07-08 00:14:07Z])
      end

      # An offset of nothing behind UTC is Z (RFC 9557 section 2).
      assert read("2022-07-08T00:14:07-00:00[!Europe/London]") ==
               read("2022-07-08T00:14:07Z[!Europe/London]")
    end

    test "is not a shift the zone does have" do
      assert {:ok, _} = read("2022-07-08T00:14:07+01:00[!Europe/London]")
      assert {:ok, _} = read("2022-01-08T00:14:07+00:00[!Europe/London]")
    end

    test "is either of the two a reading shown twice has" do
      # London's clock goes from 02:00 back to 01:00 on 25 October 2026.
      assert {:ok, _} = read("2026-10-25T01:30+01:00[!Europe/London]")
      assert {:ok, _} = read("2026-10-25T01:30+00:00[!Europe/London]")

      assert {:error, %Tempo.ZoneError{reason: :inconsistent}} =
               read("2026-10-25T01:30+02:00[!Europe/London]")
    end

    test "is refused at an end of an interval, in a set and at the start of a recurrence" do
      for text <- [
            "2022-07-08T00:14+00:00/2022-07-08T02:14+01:00[!Europe/London]",
            "{2022-07-08T00:14+00:00,2022-07-09T00:14+01:00}[!Europe/London]",
            "R3/2022-07-08T00:14+00:00/P1D[!Europe/London]"
          ] do
        assert {:error, %Tempo.ZoneError{reason: :inconsistent}} = read(text)
      end

      assert {:ok, _} = read("2022-07-08T00:14Z/2022-07-08T02:14+01:00[!Europe/London]")
    end

    test "is one that does not repeat a critical offset written as the zone" do
      assert {:ok, _} = read("2022-07-08T00:14:07+08:45[!+08:45]")

      assert {:error, %Tempo.ZoneError{reason: :inconsistent, zone: "+08:00"}} =
               read("2022-07-08T00:14:07+08:45[!+08:00]")

      assert {:ok, _} = read("2022-07-08T00:14:07+08:45[+08:00]")
    end
  end

  describe "an offset of nothing" do
    test "is held apart from Z, and written back as it was read" do
      {:ok, at_no_offset} = Tempo.from_iso8601("2022-07-08T00:14:07+00:00")
      {:ok, utc} = Tempo.from_iso8601("2022-07-08T00:14:07Z")

      assert at_no_offset != utc
      assert Tempo.to_iso8601(at_no_offset) == {:ok, "2022Y7M8DT0H14M7SZ0H0M"}
      assert Tempo.to_iso8601(utc) == {:ok, "2022Y7M8DT0H14M7SZ"}
      assert Tempo.from_iso8601("2022Y7M8DT0H14M7SZ0H0M") == {:ok, at_no_offset}
      assert Tempo.from_iso8601("2022-07-08T00:14:07+00") == {:ok, at_no_offset}
    end

    test "is the same moment as Z" do
      {:ok, at_no_offset} = Tempo.from_iso8601("2022-07-08T00:14:07+00:00")
      {:ok, utc} = Tempo.from_iso8601("2022-07-08T00:14:07Z")

      assert Tempo.to_datetime(at_no_offset) == Tempo.to_datetime(utc)
      assert Tempo.relation(at_no_offset, utc) == :equals
      assert Tempo.compare(at_no_offset, utc) == :eq
    end
  end
end
