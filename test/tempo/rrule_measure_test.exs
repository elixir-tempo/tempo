defmodule Tempo.RRuleMeasureTest do
  use ExUnit.Case, async: true

  # Recurrence rules held to occurrences worked out apart from the library.
  #
  # `Tempo.RRuleMeasure` reads a rule's text itself and tries every day from
  # the start against what RFC 5545 section 3.3.10 says each part does. It
  # is first held to the standard's own examples, so that what it says is
  # what the standard says; then Tempo is held to it over the rules the
  # examples leave out: each frequency of days or coarser, every one, two
  # and three of them, with each part alone and the parts together, from a
  # last day of January, a leap day and a Monday in June.

  alias Tempo.{Interval, Rfc5545Examples, RRule, RRuleMeasure}

  @starts [~N[2025-01-31 09:00:00], ~N[2024-02-29 09:00:00], ~N[2026-06-15 10:30:00]]

  # Parts a rule of any frequency takes.
  @any [
    "",
    "BYMONTH=1,6",
    "BYDAY=MO,WE,FR",
    "BYMONTHDAY=1,15,-1",
    "BYMONTH=2;BYMONTHDAY=29",
    "BYHOUR=9,17",
    "BYHOUR=9;BYMINUTE=0,30",
    "BYDAY=TU;BYHOUR=8,12",
    "BYMONTH=3,9;BYDAY=SA,SU"
  ]

  @parts %{
    "DAILY" => @any,
    "WEEKLY" => [
      "",
      "BYDAY=TU,TH",
      "BYDAY=SU,MO",
      "BYMONTH=1,6",
      "BYDAY=MO,WE,FR;BYHOUR=9,17",
      "BYMONTH=6;BYDAY=FR"
    ],
    "MONTHLY" =>
      @any ++
        [
          "BYDAY=1MO",
          "BYDAY=-1FR",
          "BYDAY=2TU,4TU",
          "BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1",
          "BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1",
          "BYMONTHDAY=13;BYDAY=FR",
          "BYMONTHDAY=-1",
          "BYMONTHDAY=31",
          "BYDAY=SA;BYMONTHDAY=7,8,9,10,11,12,13",
          "BYDAY=TU,WE,TH;BYSETPOS=3"
        ],
    "YEARLY" =>
      @any ++
        [
          "BYYEARDAY=1,100,-1",
          "BYWEEKNO=20;BYDAY=MO",
          "BYWEEKNO=20",
          "BYDAY=20MO",
          "BYDAY=-1SU;BYMONTH=10",
          "BYMONTH=3;BYDAY=TH",
          "BYMONTH=11;BYDAY=TU;BYMONTHDAY=2,3,4,5,6,7,8",
          "BYDAY=MO",
          "BYMONTH=1,7;BYDAY=1MO",
          "BYDAY=1SU,-1SU;BYMONTH=4,10",
          "BYMONTH=6,7;BYMONTHDAY=1,-1;BYHOUR=8,20"
        ]
  }

  @count 12

  # Two hundred years of days: a rule that picks a leap day every third day
  # has its first after the year 2200.
  @days_tried 366 * 200

  defp rule(frequency, interval, parts) do
    ["FREQ=#{frequency}", if(interval > 1, do: "INTERVAL=#{interval}"), parts, "COUNT=#{@count}"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(";")
  end

  defp measured(rule, start),
    do: RRuleMeasure.occurrences(rule, start, Date.add(NaiveDateTime.to_date(start), @days_tried))

  defp given(rule, start) do
    {:ok, recurrence} = RRule.parse(rule, from: Tempo.from_elixir!(start))

    Enum.map(recurrence, fn occurrence ->
      {:ok, at} = Tempo.to_naive_datetime(Interval.from(occurrence))
      at
    end)
  end

  # The measure tries two hundred years of days. Where it finds every
  # occurrence the rule counts, or none (a second month from February is
  # never March), Tempo gives the same; where it finds some, Tempo gives
  # those first.
  defp held(rule, start, measured, given) when length(measured) in [0, @count],
    do: assert({rule, start, given} == {rule, start, measured})

  defp held(rule, start, measured, given),
    do: assert({rule, start, Enum.take(given, length(measured))} == {rule, start, measured})

  # The standard's examples begin on the clock of New York and end at a
  # time of UTC; the measure is given the end as that clock shows it.
  defp on_the_clock_of_new_york(rule) do
    Regex.replace(~r/UNTIL=(\d{8}T\d{6})Z/, rule, fn _all, at ->
      {:ok, utc, 0} = DateTime.from_iso8601(at <> "Z", :basic)
      shown = DateTime.shift_zone!(utc, "America/New_York")
      "UNTIL=" <> Calendar.strftime(shown, "%Y%m%dT%H%M%S")
    end)
  end

  describe "the measure" do
    # The examples it can say: of days or coarser, with weeks from Monday,
    # and none left out by an EXDATE.
    for {example, index} <- Enum.with_index(Rfc5545Examples.all()),
        example.excluded == [],
        rule <- example.rules,
        not String.contains?(rule, ["HOURLY", "MINUTELY", "SECONDLY", "WKST=SU"]) do
      test "gives what RFC 5545 lists for #{rule} (#{example.title})" do
        example = Enum.at(Rfc5545Examples.all(), unquote(index))
        {{year, month, day}, {hour, minute, second}} = example.start
        start = NaiveDateTime.new!(year, month, day, hour, minute, second)

        listed =
          for {{y, m, d}, {h, mi}, _zone} <- example.occurrences,
              do: NaiveDateTime.new!(y, m, d, h, mi, 0)

        occurrences = measured(on_the_clock_of_new_york(unquote(rule)), start)

        if example.complete?,
          do: assert(occurrences == listed),
          else: assert(Enum.take(occurrences, length(listed)) == listed)
      end
    end
  end

  for {frequency, parts} <- @parts, part <- parts, interval <- [1, 2, 3] do
    @rule ["FREQ=#{frequency}", if(interval > 1, do: "INTERVAL=#{interval}"), part]
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(";")

    test "#{@rule} has the occurrences the measure gives it" do
      for start <- @starts do
        rule = rule(unquote(frequency), unquote(interval), unquote(part))
        held(rule, start, measured(rule, start), given(rule, start))
      end
    end
  end

  describe "a yearly rule of every second year or more" do
    # It keeps its years where it counts a weekday in the months it names:
    # the last Sunday of October of every second year.
    test "that counts a weekday in named months" do
      {:ok, recurrence} = RRule.parse("FREQ=YEARLY;INTERVAL=2;BYDAY=-1SU;BYMONTH=10")

      assert Tempo.to_iso8601!(recurrence) == "R/../P2Y/FL10ML7K-1INN"
      assert RRule.to_string(recurrence) == {:ok, "FREQ=YEARLY;INTERVAL=2;BYMONTH=10;BYDAY=-1SU"}

      assert given(
               "FREQ=YEARLY;INTERVAL=2;BYDAY=-1SU;BYMONTH=10;COUNT=3",
               ~N[2025-01-31 09:00:00]
             ) ==
               [~N[2025-10-26 09:00:00], ~N[2027-10-31 09:00:00], ~N[2029-10-28 09:00:00]]
    end
  end
end
