defmodule Tempo.Core.CalendarTest do
  use ExUnit.Case, async: true

  # The laws of plans/architecture-redesign.md, section 8.4, held through the
  # adapter for `Calendar.ISO` and every calendar the census runs, so that
  # the core may walk any of them on the day scale alone.

  @calendars [Calendar.ISO | Tempo.Matrix.CalendarCensus.calendars()]

  @years %{
    Calendrical.Reform.England => [1751, 1752],
    Calendrical.Julian.March25 => [1750],
    Calendrical.Hebrew => [5786, 5787]
  }

  defp years(calendar) do
    Map.get(@years, calendar, [2024, 2026] |> Enum.map(&year_of(calendar, &1)))
  end

  # The calendar's year holding the Gregorian year's 1 June.
  defp year_of(Calendar.ISO, year), do: year

  defp year_of(calendar, year) do
    {:ok, date} = Date.new(year, 6, 1)
    {:ok, converted} = Date.convert(date, calendar)
    converted.year
  end

  for calendar <- @calendars do
    describe inspect(calendar) do
      @calendar calendar

      test "a date round-trips through the day scale and the scale is in the order of the fields" do
        for year <- years(@calendar) do
          {:ok, {first, after_last}} = Tempo.Calendar.period(@calendar, :year, year, nil)

          dates = for day <- first..(after_last - 1), do: Tempo.Calendar.date(@calendar, day)
          assert Enum.sort(dates) == dates

          assert Enum.all?(dates, fn {y, m, d} ->
                   Tempo.Calendar.valid_date?(@calendar, y, m, d)
                 end)

          assert Enum.map(dates, fn {y, m, d} -> Tempo.Calendar.iso_days(@calendar, y, m, d) end) ==
                   Enum.to_list(first..(after_last - 1))
        end
      end

      test "the months of a year tile it, walked on the day scale" do
        for year <- years(@calendar) do
          {:ok, {first, after_last}} = Tempo.Calendar.period(@calendar, :year, year, nil)

          months =
            Stream.unfold(first, fn
              day when day < after_last ->
                {y, m, _} = Tempo.Calendar.date(@calendar, day)
                {:ok, {^day, next}} = Tempo.Calendar.period(@calendar, :month, y, m)
                {{m, next - day}, next}

              _ ->
                nil
            end)
            |> Enum.to_list()

          assert Enum.sum(for {_, days} <- months, do: days) == after_last - first
          assert months == Enum.uniq_by(months, &elem(&1, 0))
        end
      end

      test "a day is in the week its week-year and week name" do
        for year <- years(@calendar) do
          {:ok, {first, after_last}} = Tempo.Calendar.period(@calendar, :year, year, nil)

          for day <- Enum.take_every(first..(after_last - 1), 37) do
            {y, m, d} = Tempo.Calendar.date(@calendar, day)
            {:ok, {week_year, week}} = Tempo.Calendar.week_of_year(@calendar, y, m, d)

            {:ok, {week_first, week_after}} =
              Tempo.Calendar.period(@calendar, :week, week_year, week)

            assert week_first <= day and day < week_after
          end
        end
      end

      test "the day of the week runs 1 to 7 over consecutive days" do
        for year <- years(@calendar) do
          {:ok, {first, _}} = Tempo.Calendar.period(@calendar, :year, year, nil)

          weekdays =
            for day <- first..(first + 13) do
              {y, m, d} = Tempo.Calendar.date(@calendar, day)
              Tempo.Calendar.day_of_week(@calendar, y, m, d)
            end

          assert Enum.sort(Enum.take(weekdays, 7)) == Enum.to_list(1..7)
          assert Enum.take(weekdays, 7) == Enum.drop(weekdays, 7)
        end
      end

      test "a period the calendar does not have is an error, never another period" do
        for year <- years(@calendar) do
          assert {:error, _} = Tempo.Calendar.period(@calendar, :month, year, 99)
          assert {:error, _} = Tempo.Calendar.period(@calendar, :week, year, 99)
          assert {:error, _} = Tempo.Calendar.first_day(@calendar, year: year, month: 99, day: 1)
          assert {:error, _} = Tempo.Calendar.first_day(@calendar, year: year, day_of_year: 0)
        end
      end

      test "the weeks of a month cover it" do
        for year <- years(@calendar) do
          {:ok, {first, _}} = Tempo.Calendar.period(@calendar, :year, year, nil)
          {y, m, _} = Tempo.Calendar.date(@calendar, first)
          {:ok, {month_first, month_after}} = Tempo.Calendar.period(@calendar, :month, y, m)
          {:ok, weeks} = Tempo.Calendar.weeks_of_month(@calendar, y, m)

          # TR35 lets a month's first or last days fall in no week of it, so the
          # weeks hold the month's middle and run on without a gap.
          middle = div(month_first + month_after, 2)
          assert weeks != []
          assert Enum.any?(weeks, fn {lo, hi} -> lo <= middle and middle < hi end)

          assert weeks
                 |> Enum.chunk_every(2, 1, :discard)
                 |> Enum.all?(fn [{_, hi}, {lo, _}] -> hi == lo end)
        end
      end
    end
  end

  test "the first day of a week date and of a day of the year are derived on the day scale" do
    assert {:ok, day} =
             Tempo.Calendar.first_day(Calendar.ISO, year: 2026, week: 25, day_of_week: 3)

    assert Tempo.Calendar.date(Calendar.ISO, day) == {2026, 6, 17}
    assert {:ok, day} = Tempo.Calendar.first_day(Calendar.ISO, year: 2026, day_of_year: 166)
    assert Tempo.Calendar.date(Calendar.ISO, day) == {2026, 6, 15}
    assert Tempo.Calendar.day_of_year(Calendar.ISO, 2026, 6, 15) == {:ok, 166}
  end

  test "Calendar.ISO is asked through its implementation and answers as itself" do
    assert Tempo.Calendar.calendar?(Calendar.ISO)
    assert Tempo.Calendar.calendar?(Calendrical.Hebrew)
    refute Tempo.Calendar.calendar?(Enum)
    assert Tempo.Calendar.type(Calendar.ISO) == :gregorian
    assert Tempo.Calendar.from_type(:iso8601) == {:ok, Calendar.ISO}
    assert {:ok, Calendrical.Hebrew} = Tempo.Calendar.from_type(:hebrew)
    assert Tempo.Calendar.months_in_year_bounds(Calendar.ISO) == {12, 12}
    assert Tempo.Calendar.days_in_month_bounds(Calendar.ISO, 2) == {28, 29}
    assert Tempo.Calendar.traditional_month(Calendrical.Hebrew, 5787, 7) == 6

    assert Tempo.Calendar.shift_date(Calendar.ISO, 2026, 1, 31, Duration.new!(month: 1)) ==
             {2026, 2, 28}
  end
end
