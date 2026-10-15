defmodule Tempo.ChangeOfTheClockTest do
  use ExUnit.Case, async: true

  # The hours of a day on which a zone's clock changes.
  #
  # A change by a whole hour on the hour is the one every implementation is
  # written for. A current zone or two has another every year: Lord Howe
  # Island's clocks go forward and back by half an hour, and the Chatham
  # Islands' go from 02:45 to 03:45. `Tempo.ChangeOfTheClock` asks Elixir's
  # `DateTime` what the clock showed in each minute of such a day and gathers
  # the minutes into hours, apart from the library; each day is held to
  # that. An hour is from where the clock comes to it to where the clock
  # leaves it: thirty minutes where the clock skips half of it, ninety where
  # the clock shows half of it twice.

  alias Tempo.{ChangeOfTheClock, Conformance, Interval}

  @minute 60
  @fixture Conformance.fixture("clock_changes")

  describe "the conformance fixture" do
    test "lists the days of the measure, each with the hours DateTime says the clock showed" do
      days = ChangeOfTheClock.gaps() ++ ChangeOfTheClock.folds()
      assert length(@fixture["days"]) == length(days)

      for {{zone, date, change}, listed} <- Enum.zip(days, @fixture["days"]) do
        {from, to} = ChangeOfTheClock.day_shown(zone, date)

        shown =
          for {hour, from, to} <- ChangeOfTheClock.hours_shown(zone, date),
              do: %{"hour" => hour, "from" => from, "to" => to}

        assert listed == %{
                 "zone" => zone,
                 "date" => Date.to_iso8601(date),
                 "change" => change,
                 "day_shown" => [from, to],
                 "hours" => shown
               }
      end
    end

    test "has the hours a walk of each day gives" do
      for %{"zone" => zone, "date" => date, "hours" => hours, "day_shown" => [from, to]} <-
            @fixture["days"] do
        day = ChangeOfTheClock.day(zone, Date.from_iso8601!(date))

        assert {zone, date, ChangeOfTheClock.hours_listed(zone, Date.from_iso8601!(date))} ==
                 {zone, date, Enum.map(hours, &{&1["hour"], &1["from"], &1["to"]})}

        assert ChangeOfTheClock.span(day) == {from, to}
      end
    end
  end

  describe "the length of an hour the clock does not show whole" do
    import Tempo.Sigils

    test "is the part it shows, in the units that say it" do
      # Lord Howe Island, 4 October 2026: the clock goes from 02:00 to 02:30.
      skipped = ChangeOfTheClock.day("Australia/Lord_Howe", ~D[2026-10-04])
      assert Tempo.duration(Enum.at(skipped, 2)) == ~o"PT30M"
      assert Tempo.duration(Tempo.to_interval!(Enum.at(skipped, 2))) == ~o"PT30M"
      assert Tempo.duration(Enum.at(skipped, 3)) == ~o"PT1H"

      # 5 April 2026: it goes from 02:00 back to 01:30.
      shown_twice = ChangeOfTheClock.day("Australia/Lord_Howe", ~D[2026-04-05])
      assert Tempo.duration(Enum.at(shown_twice, 1)) == ~o"PT1H30M"

      # The Chatham Islands, the same day: from 03:45 back to 02:45.
      two_parts = ChangeOfTheClock.day("Pacific/Chatham", ~D[2026-04-05])
      assert Tempo.duration(Enum.at(two_parts, 4)) == ~o"PT15M"
    end

    test "is a whole hour where the clock shows a whole hour" do
      assert Tempo.duration(~o"2026-06-15T10[Europe/Paris]") == ~o"PT1H"
      assert Tempo.duration(~o"2026-03-29T01/2026-03-29T04[Europe/Paris]") == ~o"PT2H"
    end
  end

  for {zone, date, change} <- ChangeOfTheClock.gaps() ++ ChangeOfTheClock.folds() do
    describe "#{zone} on #{date}, #{change}" do
      @zone zone
      @date date

      test "the hours of the day are the hours the clock shows" do
        assert ChangeOfTheClock.hours_listed(@zone, @date) ==
                 ChangeOfTheClock.hours_shown(@zone, @date)
      end

      test "the day runs from its first reading to the first of the next" do
        assert ChangeOfTheClock.span(ChangeOfTheClock.day(@zone, @date)) ==
                 ChangeOfTheClock.day_shown(@zone, @date)
      end

      test "each hour has the minutes of its span" do
        for hour <- Enum.to_list(ChangeOfTheClock.day(@zone, @date)) do
          {from, to} = ChangeOfTheClock.span(hour)
          minutes = Enum.map(hour, fn minute -> minute |> ChangeOfTheClock.span() |> elem(0) end)

          assert {hour, minutes} == {hour, Enum.to_list(from..(to - @minute)//@minute)}
        end
      end

      test "the hours are counted as they are listed, and each is found among them" do
        day = ChangeOfTheClock.day(@zone, @date)
        listed = Enum.to_list(day)

        assert Enum.count(day) == length(listed)

        for {hour, place} <- Enum.with_index(listed) do
          assert Enum.at(day, place) == hour
        end
      end

      test "each hour meets the next" do
        hours = Enum.to_list(ChangeOfTheClock.day(@zone, @date))

        for [earlier, later] <- Enum.chunk_every(hours, 2, 1, :discard) do
          {_from, earlier_ends} = ChangeOfTheClock.span(earlier)
          {later_begins, _to} = ChangeOfTheClock.span(later)
          assert {earlier, later, earlier_ends} == {earlier, later, later_begins}
        end
      end

      test "the day and each of its hours is written and read as itself" do
        day = ChangeOfTheClock.day(@zone, @date)

        for value <- [day | Enum.to_list(day)] do
          {:ok, span} = Tempo.to_interval(value)
          {:ok, text} = Tempo.to_iso8601(span)
          {:ok, read} = Tempo.from_iso8601(text)

          assert {text, Interval.from(read), Interval.to(read)} ==
                   {text, Interval.from(span), Interval.to(span)}
        end
      end
    end
  end
end
