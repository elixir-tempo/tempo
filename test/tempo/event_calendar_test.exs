defmodule Tempo.EventCalendarTest do
  use ExUnit.Case, async: true

  # A computed event (`(easter)e`) is a day on the time line, worked out for a
  # year of the Gregorian calendar. In a recurrence or a selection of another
  # calendar it is that day, written in the calendar, in the period it falls
  # in: the Easter of the Hebrew year 5786 is 5 April 2026, where it was the
  # Easter of the Gregorian year 5786.
  #
  # The measure is taken apart from the resolver. Each event's date in each
  # Gregorian year, from `Tempo.Event.date/2`, is converted with
  # `Date.convert!/2`, and the dates whose year in the calendar is the one
  # asked for are that year's: one, none or two.

  alias Calendrical.Buddhist
  alias Calendrical.Coptic
  alias Calendrical.Hebrew
  alias Calendrical.Islamic.UmmAlQura
  alias Calendrical.ISOWeek
  alias Calendrical.Julian
  alias Calendrical.Julian.March25
  alias Calendrical.NRF
  alias Calendrical.Persian
  alias Tempo.Event
  alias Tempo.Interval
  alias Tempo.IntervalSet

  # A year of each calendar: lunisolar, solar with another year start and
  # another year number, lunar, a year that turns within a month, and two
  # calendars of weeks.
  @years [
    {Hebrew, 5786},
    {Persian, 1405},
    {Coptic, 1742},
    {UmmAlQura, 1447},
    {Buddhist, 2569},
    {Julian, 2026},
    {March25, 2025},
    {NRF, 2026},
    {ISOWeek, 2026}
  ]

  @events ~w(easter orthodox-easter march-equinox september-equinox december-solstice new-moon
             qingming)

  defp read(text, calendar), do: Tempo.from_iso8601!(text, calendar)

  # The Gregorian years about a year of a calendar, more than its neighbours
  # run through.
  defp gregorian_years_about(year, calendar) do
    %Date{year: gregorian_year} = Date.convert!(Date.new!(year, 1, 1, calendar), Calendar.ISO)
    (gregorian_year - 3)..(gregorian_year + 7)
  end

  # Each date an event falls on in the Gregorian years about `year`, as a date
  # of `calendar`, earliest first.
  defp event_dates(event, year, calendar) do
    for gregorian_year <- gregorian_years_about(year, calendar),
        {:ok, date} <- [Event.date(event, gregorian_year)],
        do: Date.convert!(date, calendar)
  end

  defp in_year(dates, year), do: Enum.filter(dates, &(&1.year == year))
  defp from_year(dates, year), do: Enum.filter(dates, &(&1.year >= year))

  # The day each member of a set starts on, as a date of the set's calendar.
  defp dates({:ok, %IntervalSet{} = set}) do
    for member <- IntervalSet.members(set) do
      {:ok, date} = member |> Interval.from() |> Tempo.to_date()
      date
    end
  end

  defp gregorian(dates), do: Enum.map(dates, &Date.convert!(&1, Calendar.ISO))

  describe "a computed event in a year of another calendar" do
    for {calendar, year} <- @years do
      test "is each day it falls on in a year of #{inspect(calendar)}" do
        calendar = unquote(calendar)

        for event <- @events, year <- (unquote(year) - 1)..(unquote(year) + 3) do
          every_year = read("R/../P1Y/FL(#{event})eN", calendar)
          selected = dates(Tempo.to_interval(every_year, within: read("#{year}Y", calendar)))

          assert {event, year, selected} ==
                   {event, year, event |> event_dates(year, calendar) |> in_year(year)}
        end
      end

      test "is counted from the year a recurrence of #{inspect(calendar)} starts in" do
        calendar = unquote(calendar)
        year = unquote(year)

        for event <- @events do
          selected = dates(Tempo.to_interval(read("R4/#{year}Y/P1Y/FL(#{event})eN", calendar)))

          assert {event, selected} ==
                   {event,
                    event |> event_dates(year, calendar) |> from_year(year) |> Enum.take(4)}
        end
      end

      test "is selected from a year of #{inspect(calendar)}" do
        calendar = unquote(calendar)
        year = unquote(year)

        for event <- @events do
          in_the_year = event |> event_dates(year, calendar) |> in_year(year)
          span = read("#{year}Y", calendar)

          assert {event, dates(Tempo.select(span, read("L(#{event})eN", calendar)))} ==
                   {event, in_the_year}

          # An event names no month and no day of one, so a selector written
          # in the Gregorian calendar selects it from any calendar's year.
          assert {event, dates(Tempo.select(span, Tempo.from_iso8601!("L(#{event})eN")))} ==
                   {event, in_the_year}
        end
      end
    end

    test "is the Easter of the Gregorian year the Hebrew year runs through" do
      easters = Tempo.to_interval(read("R2/5786Y/P1Y/FL(easter)eN", Hebrew))

      assert dates(easters) == [Date.new!(5786, 7, 18, Hebrew), Date.new!(5787, 7, 19, Hebrew)]
      assert gregorian(dates(easters)) == [~D[2026-04-05], ~D[2027-03-28]]

      assert gregorian(dates(Tempo.to_interval(read("5786YL(easter)eN", Hebrew)))) ==
               [~D[2026-04-05]]
    end

    test "falls in a year of the calendar not at all, once or twice" do
      equinoxes = read("R/../P1Y/FL(september-equinox)eN", Hebrew)
      within = fn year -> Tempo.to_interval(equinoxes, within: read("#{year}Y", Hebrew)) end

      # 5786 begins on 23 September 2025, the day after an equinox, and ends
      # on 11 September 2026, before the next. 5787 runs on to 1 October 2027.
      assert gregorian(dates(within.(5785))) == [~D[2025-09-22]]
      assert gregorian(dates(within.(5786))) == []
      assert gregorian(dates(within.(5787))) == [~D[2026-09-23], ~D[2027-09-23]]

      # A year that turns on 25 March holds the Easters from one 25 March
      # (5 April in the Gregorian calendar) to the next.
      easters = read("L(easter)eN", March25)
      assert gregorian(dates(Tempo.select(read("1750Y", March25), easters))) == []

      assert gregorian(dates(Tempo.select(read("1751Y", March25), easters))) ==
               [~D[1751-04-11], ~D[1752-04-02]]
    end
  end

  describe "a computed event that limits a recurrence of another calendar" do
    test "keeps the days of a daily recurrence that are the event's" do
      for {calendar, first_day} <- [
            {Hebrew, "5786Y1M1D"},
            {Buddhist, "2569Y1M1D"},
            {March25, "2025Y3M25D"},
            {NRF, "2026Y1W1K"},
            {ISOWeek, "2026Y1W1K"}
          ],
          event <- ~w(easter new-moon) do
        %Tempo{time: [{:year, year} | _]} = start = read(first_day, calendar)
        {:ok, first} = Tempo.to_date(start)

        expected =
          event
          |> event_dates(year, calendar)
          |> Enum.filter(&(Date.diff(&1, first) >= 0))
          |> Enum.take(3)

        every_day = read("R3/#{first_day}/P1D/FL(#{event})eN", calendar)

        assert {calendar, event, dates(Tempo.to_interval(every_day))} ==
                 {calendar, event, expected}
      end
    end

    test "keeps the weeks of a weekly recurrence whose day is the event's" do
      # An NRF week starts on a Sunday, and Easter is one.
      every_week = read("R3/2026Y1W1K/P1W/FL(easter)eN", NRF)

      assert gregorian(dates(Tempo.to_interval(every_week))) ==
               [~D[2026-04-05], ~D[2027-03-28], ~D[2028-04-16]]
    end
  end

  describe "a computed event of another calendar's year beside other parts" do
    test "is limited by a day of the week counted as the calendar counts it" do
      window = fn calendar, years -> [within: read(years, calendar)] end
      easters = [~D[2026-04-05], ~D[2027-03-28], ~D[2028-04-16]]

      # Sunday is the seventh day in a calendar of months and the first of an
      # NRF week.
      sundays = read("R/../P1Y/FL(easter)e7KN", Hebrew)

      assert gregorian(dates(Tempo.to_interval(sundays, window.(Hebrew, "5786Y/5789Y")))) ==
               easters

      mondays = read("R/../P1Y/FL(easter)e1KN", Hebrew)
      assert dates(Tempo.to_interval(mondays, window.(Hebrew, "5786Y/5789Y"))) == []

      first_days = read("R/../P1Y/FL(easter)e1KN", NRF)

      assert gregorian(dates(Tempo.to_interval(first_days, window.(NRF, "2026Y/2029Y")))) ==
               easters
    end

    test "is limited by a month of the calendar selected beside it" do
      # Easter falls in the seventh month of a Hebrew year of twelve months
      # and the eighth of a year of thirteen, which numbers Nisan after its
      # second Adar.
      for month <- 7..8 do
        in_the_month = read("R/../P1Y/FL#{month}M(easter)eN", Hebrew)
        selected = dates(Tempo.to_interval(in_the_month, within: read("5780Y/5800Y", Hebrew)))

        expected =
          for year <- 5780..5799,
              date <- "easter" |> event_dates(year, Hebrew) |> in_year(year),
              date.month == month,
              do: date

        assert {month, selected} == {month, expected}
      end
    end

    test "anchors a window, whose days are selected in the years they fall in" do
      # Each feast is a count of days from Easter, taken here with `Date.add/2`.
      # Ash Wednesday of 2027 falls in the Persian year 1405 and its Easter in
      # 1406: the feast is listed in the year its own day falls in.
      feasts = [
        {"R/../P1Y/FLLL(easter)eN/-P7DN5K-1IN", -2},
        {"R/../P1Y/FLLL(easter)eN/-P49DN3K1IN", -46},
        {"R/../P1Y/FLLL(easter)eN/P2DN1K1IN", 1},
        {"R/../P1Y/FLLL(easter)eN/P50DN7K-1IN", 49}
      ]

      for {calendar, year} <- [{Hebrew, 5786}, {Persian, 1405}, {Buddhist, 2569}],
          {rule, days_from_easter} <- feasts do
        expected =
          for gregorian_year <- gregorian_years_about(year, calendar),
              {:ok, easter} = Event.date("easter", gregorian_year),
              feast = Date.convert!(Date.add(easter, days_from_easter), calendar),
              feast.year in year..(year + 1),
              do: feast

        two_years = read("#{year}Y/#{year + 2}Y", calendar)

        assert {calendar, rule, dates(Tempo.to_interval(read(rule, calendar), within: two_years))} ==
                 {calendar, rule, expected}
      end
    end

    test "takes its date in a named zone" do
      # The March equinox of 2002 was on the 20th in UTC and the 21st in Tokyo.
      equinoxes = read("R/../P1Y/FL(march-equinox@+09:00)eN", Hebrew)

      assert gregorian(dates(Tempo.to_interval(equinoxes, within: read("5762Y", Hebrew)))) ==
               [~D[2002-03-21]]
    end

    test "is no occurrence in a year the event cannot be computed for" do
      # Astro computes an equinox from 1000 CE, and the Persian year 100 is
      # in the eighth century.
      equinoxes = read("R/../P1Y/FL(march-equinox)eN", Persian)
      assert dates(Tempo.to_interval(equinoxes, within: read("0100Y", Persian))) == []
    end
  end
end
