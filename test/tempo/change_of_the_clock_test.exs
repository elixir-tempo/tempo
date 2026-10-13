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

  alias Tempo.ChangeOfTheClock
  alias Tempo.Interval

  @minute 60

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
