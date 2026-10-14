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
        assert {text, {:error, %Tempo.ZoneError{reason: :gap}}} = {text, Tempo.from_iso8601(text)}
      end
    end

    test "is every minute of the gap" do
      for minute <- 0..59 do
        assert {minute, {:error, %Tempo.ZoneError{reason: :gap}}} =
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
      for {old, current} <- [
            {"US/Pacific", "America/Los_Angeles"},
            {"Asia/Calcutta", "Asia/Kolkata"},
            {"Pacific/Enderbury", "Pacific/Kanton"}
          ] do
        text = "2024-06-15T12:00:00[#{old}]"
        {:ok, shown} = DateTime.new(~D[2024-06-15], ~T[12:00:00], current)

        assert {old, unix(text)} == {old, DateTime.to_unix(shown)}
        assert Tempo.to_iso8601!(Tempo.from_iso8601!(text)) =~ "[#{old}]"
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
        assert {text, {:ok, _}} = {text, Tempo.from_iso8601(text)}
      end

      for text <- [
            "2024-03-10T12:00:00+25:00",
            "2024-03-10T12:00:00-25:00",
            "2024-03-10T12:00:00[+25:00]"
          ] do
        assert {text, {:error, _}} = {text, Tempo.from_iso8601(text)}
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
end
