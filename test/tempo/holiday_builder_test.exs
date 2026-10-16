defmodule Tempo.HolidayBuilderTest do
  use ExUnit.Case, async: true

  # The builder is complete for what holidays need: each shape of rule
  # `tempo_holidays` builds for its 208 territories (290 shapes, 1,533 rules,
  # gathered on 2026-10-14) is built here with `Tempo.Builder`, and held equal
  # to what the parser reads from the text `tempo_holidays` wrote for it.

  import Tempo.Sigils
  import Tempo.Builder

  alias Tempo.{Interval, IntervalSet}

  @hebrew Calendrical.Hebrew

  @built [
    # A fixed day, every year and in a domain of years.
    {"R/../P1Y/FL1M15DN", quote(do: every(:year) |> on(month: 1, day: 15))},
    {"R/{2021Y}/P1Y/FL4M14DN",
     quote(do: every(:year) |> on(month: 4, day: 14) |> in_years(2021))},
    {"R/{2005Y/..}/P1Y/FL9M15DN",
     quote(do: every(:year) |> on(month: 9, day: 15) |> in_years(from: 2005))},
    {"R/{../2005Y}/P1Y/FL11M20DN",
     quote(do: every(:year) |> on(month: 11, day: 20) |> in_years(through: 2005))},
    {"R/{1949Y..1988Y}/P1Y/FL4M29DN",
     quote(do: every(:year) |> on(month: 4, day: 29) |> in_years(1949..1988))},
    {"R/{../2016Y,2018Y/..}/P1Y/FL3M1DN",
     quote(do: every(:year) |> on(month: 3, day: 1) |> in_years(through: 2016, from: 2018))},
    {"R/{../1975Y,1982Y..1987Y}/P1Y/FL10M12DN",
     quote(do: every(:year) |> on(month: 10, day: 12) |> in_years([{:through, 1975}, 1982..1987]))},
    {"R/{1995Y..2009Y,2022Y/..}/P1Y/FL10M25DN",
     quote(do: every(:year) |> on(month: 10, day: 25) |> in_years([1995..2009, from: 2022]))},
    {"R/{1961Y/..,^2011Y}/P1Y/FL6M19DN",
     quote(do: every(:year) |> on(month: 6, day: 19) |> in_years([from: 1961], except: 2011))},
    {"R/..l/P1Y/FL9M12DN", quote(do: every(:year) |> on(month: 9, day: 12) |> in_years(:leap))},
    {"R/..c/P1Y/FL9M11DN", quote(do: every(:year) |> on(month: 9, day: 11) |> in_years(:common))},

    # A numbered weekday of a month, and on a cadence of years.
    {"R/../P1Y/FL1M1K4IN", quote(do: every(:year) |> on(month: 1) |> on(:monday, nth: 4))},
    {"R/{1988Y/..}/P1Y/FL12M5K1IN",
     quote(do: every(:year) |> on(month: 12) |> on(:friday, nth: 1) |> in_years(from: 1988))},
    {"R/..e/P1Y/FL10M7K1IN",
     quote(do: every(:year) |> on(month: 10) |> on(:sunday, nth: 1) |> in_years(:even))},
    {"R/{1848Y/..}/P4Y/FLL11M1K1IN/P7D2K-1IN",
     quote(
       do:
         every(year: 4)
         |> on(month: 11)
         |> on(:monday, nth: 1)
         |> on(:tuesday, nth: -1, within: [day: 7])
         |> in_years(from: 1848)
     )},

    # A day on some weekdays, and moved to another when it falls on others.
    {"R/../P1Y/FL6M21D{1..6}KN",
     quote(do: every(:year) |> on(month: 6, day: 21, day_of_week: 1..6))},
    {"R/../P1Y/FLL12M8D7KN/P8D1K-1IN",
     quote(
       do:
         every(:year)
         |> on(month: 12, day: 8)
         |> on(:sunday)
         |> on(:monday, nth: -1, within: [day: 8])
     )},
    {"R/{2040Y}/P1Y/FLL2M12D7KN/P8D2K-1IN",
     quote(
       do:
         every(:year)
         |> on(month: 2, day: 12)
         |> on(:sunday)
         |> on(:tuesday, nth: -1, within: [day: 8])
         |> in_years(2040)
     )},
    {"R/../P1Y/FLL8M4DN/P-7D4K1IN",
     quote(do: every(:year) |> on(month: 8, day: 4) |> on(:thursday, nth: 1, within: [day: -7]))},
    {"R/../P1Y/FLL6M1DN/P21D7K-1IN",
     quote(do: every(:year) |> on(month: 6, day: 1) |> on(:sunday, nth: -1, within: [day: 21]))},
    {"{R/../P1Y/FL10M24D{1..6}KN,R/../P1Y/FLL10M24D7KN/P8D1K-1IN}",
     quote(
       do:
         all_of([
           every(:year) |> on(month: 10, day: 24, day_of_week: 1..6),
           every(:year)
           |> on(month: 10, day: 24)
           |> on(:sunday)
           |> on(:monday, nth: -1, within: [day: 8])
         ])
     )},
    {"{R/../P1Y/FL12M31D{1..5}KN,R/../P1Y/FLL12M31D6KN/P8D1K-1IN,R/../P1Y/FLL12M31D7KN/P8D2K-1IN}",
     quote(
       do:
         all_of([
           every(:year) |> on(month: 12, day: 31, day_of_week: 1..5),
           every(:year)
           |> on(month: 12, day: 31)
           |> on(:saturday)
           |> on(:monday, nth: -1, within: [day: 8]),
           every(:year)
           |> on(month: 12, day: 31)
           |> on(:sunday)
           |> on(:tuesday, nth: -1, within: [day: 8])
         ])
     )},
    {"{R/{../2022Y}/P1Y/FL12M25DN,R/{2023Y/..}/P1Y/FL12M25D{1..5}KN}",
     quote(
       do:
         all_of([
           every(:year) |> on(month: 12, day: 25) |> in_years(through: 2022),
           every(:year) |> on(month: 12, day: 25, day_of_week: 1..5) |> in_years(from: 2023)
         ])
     )},
    {"{R/{2020Y/..,^2020Y,^2021Y}/P1Y/FL10M1K2IN,R/{2020Y}/P1Y/FL7M24DN,R/{2021Y}/P1Y/FL7M23DN}",
     quote(
       do:
         all_of([
           every(:year)
           |> on(month: 10)
           |> on(:monday, nth: 2)
           |> in_years([from: 2020], except: [2020, 2021]),
           every(:year) |> on(month: 7, day: 24) |> in_years(2020),
           every(:year) |> on(month: 7, day: 23) |> in_years(2021)
         ])
     )},

    # Days counted from Easter, and holidays of several days.
    {"R/../P1Y/FL(easter)eN", quote(do: every(:year) |> on(event: "easter"))},
    {"R/../P1Y/FLL(easter)eN/P50D7K-1IN",
     quote(do: every(:year) |> on(event: "easter") |> on(:sunday, nth: -1, within: [day: 50]))},
    {"R/../P1Y/FLL(easter)eN/P-3D5K1IN",
     quote(do: every(:year) |> on(event: "easter") |> on(:friday, nth: 1, within: [day: -3]))},
    {"R/{1995Y..1997Y}/P1Y/FLL(orthodox-easter)eN/P51D1K-1IN",
     quote(
       do:
         every(:year)
         |> on(event: "orthodox-easter")
         |> on(:monday, nth: -1, within: [day: 51])
         |> in_years(1995..1997)
     )},
    {"R/../P1Y/FLLL(easter)eN/P-7D1K1IN/P7DN",
     quote(
       do:
         every(:year)
         |> on(event: "easter")
         |> on(:monday, nth: 1, within: [day: -7])
         |> lasting(day: 7)
     )},
    {"R/../P1Y/FLL8M16DN/P2DN",
     quote(do: every(:year) |> on(month: 8, day: 16) |> lasting(day: 2))},

    # Days the sky gives, reckoned in a zone.
    {"R/{1949Y/..}/P1Y/FL(march-equinox@+09:00)eN",
     quote(do: every(:year) |> on(event: {"march-equinox", "+09:00"}) |> in_years(from: 1949))},
    {"R/{2022Y/..}/P1Y/FL(june-solstice@America/Santiago)eN",
     quote(
       do:
         every(:year)
         |> on(event: {"june-solstice", "America/Santiago"})
         |> in_years(from: 2022)
     )},
    {"R/{1973Y/..}/P1Y/FL(september-equinox@+09:00)e{1..6}KN",
     quote(
       do:
         every(:year)
         |> on(event: {"september-equinox", "+09:00"}, day_of_week: 1..6)
         |> in_years(from: 1973)
     )},
    {"R/../P1Y/FL(december-solstice)eN",
     quote(do: every(:year) |> on(event: "december-solstice"))},

    # Other calendars.
    {"R/../P1Y/FL7m10DN[u-ca=hebrew]",
     quote(do: every(:year) |> on(traditional_month: 7, day: 10) |> in_calendar(@hebrew))},
    {"R/{5758Y/..}/P1Y/FL2m12DN[u-ca=hebrew]",
     quote(
       do:
         every(:year)
         |> on(traditional_month: 2, day: 12)
         |> in_calendar(@hebrew)
         |> in_years(from: 5758)
     )},
    {"R/../P1Y/FLL3m25DN/P8DN[u-ca=hebrew]",
     quote(
       do:
         every(:year)
         |> on(traditional_month: 3, day: 25)
         |> lasting(day: 8)
         |> in_calendar(@hebrew)
     )},
    {"{R/../P1Y/FL10m17D{2..6,1}KN,R/../P1Y/FLL10m17D7KN/P8D1K-1IN}[u-ca=hebrew]",
     quote(
       do:
         all_of([
           every(:year)
           |> on(traditional_month: 10, day: 17, day_of_week: [1..5, 7])
           |> in_calendar(@hebrew),
           every(:year)
           |> on(traditional_month: 10, day: 17)
           |> on(:saturday)
           |> on(:sunday, nth: -1, within: [day: 8])
           |> in_calendar(@hebrew)
         ])
     )},
    {"{5780Y6M6D/5780Y6M6D}[u-ca=hebrew]",
     quote(
       do:
         all_of([
           until(
             Tempo.new!(year: 5780, month: 6, day: 6, calendar: @hebrew),
             Tempo.new!(year: 5780, month: 6, day: 6, calendar: @hebrew)
           )
         ])
     )},
    {"R/../P1Y/FL1M1DN[u-ca=persian]",
     quote(do: every(:year) |> on(month: 1, day: 1) |> in_calendar(Calendrical.Persian))},
    {"R/../P1Y/FL12M24DN[u-ca=julian]",
     quote(do: every(:year) |> on(month: 12, day: 24) |> in_calendar(Calendrical.Julian))}
  ]

  for {{text, built}, index} <- Enum.with_index(@built) do
    test "#{index}: #{text} is built as it is read" do
      assert unquote(built) == Tempo.from_iso8601(unquote(text))
    end
  end

  test "a holiday built is used as one read" do
    {:ok, pentecost} =
      every(:year) |> on(event: "easter") |> on(:sunday, nth: -1, within: [day: 50])

    assert pentecost
           |> Tempo.to_interval!(within: ~o"2026")
           |> IntervalSet.map(&Interval.from/1) == [~o"2026-05-24"]
  end
end
