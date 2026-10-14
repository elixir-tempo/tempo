defmodule Tempo.RRuleMeasureTest do
  use ExUnit.Case, async: true

  # Recurrence rules held to occurrences worked out apart from the library.
  #
  # `Tempo.RRuleMeasure` tries every day from the start against what RFC 5545
  # section 3.3.10 says each part does. It is first held to the standard's
  # own examples, read from the standard's text, so that what it says is
  # what the standard says; then Tempo is held to it over the rules the
  # examples leave out, each made as data and built with
  # `Tempo.RRule.from_rule/2`: each frequency of days or coarser, every one, two
  # and three of them, with each part alone and the parts together, from a
  # last day of January, a leap day and a Monday in June.

  alias Tempo.{Interval, Rfc5545Examples, RRule, RRuleMeasure}

  @starts [~N[2025-01-31 09:00:00], ~N[2024-02-29 09:00:00], ~N[2026-06-15 10:30:00]]

  # Parts a rule of any frequency takes.
  @any [
    [],
    [bymonth: [1, 6]],
    [byday: [{nil, 1}, {nil, 3}, {nil, 5}]],
    [bymonthday: [1, 15, -1]],
    [bymonth: [2], bymonthday: [29]],
    [byhour: [9, 17]],
    [byhour: [9], byminute: [0, 30]],
    [byday: [{nil, 2}], byhour: [8, 12]],
    [bymonth: [3, 9], byday: [{nil, 6}, {nil, 7}]]
  ]

  @parts [
    day: @any,
    week: [
      [],
      [byday: [{nil, 2}, {nil, 4}]],
      [byday: [{nil, 7}, {nil, 1}]],
      [bymonth: [1, 6]],
      [byday: [{nil, 1}, {nil, 3}, {nil, 5}], byhour: [9, 17]],
      [bymonth: [6], byday: [{nil, 5}]]
    ],
    month:
      @any ++
        [
          [byday: [{1, 1}]],
          [byday: [{-1, 5}]],
          [byday: [{2, 2}, {4, 2}]],
          [byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}], bysetpos: [1]],
          [byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}], bysetpos: [-1]],
          [bymonthday: [13], byday: [{nil, 5}]],
          [bymonthday: [-1]],
          [bymonthday: [31]],
          [byday: [{nil, 6}], bymonthday: [7, 8, 9, 10, 11, 12, 13]],
          [byday: [{nil, 2}, {nil, 3}, {nil, 4}], bysetpos: [3]],
          [byday: [{2, 1}, {2, 3}]],
          [byday: [{1, 1}, {-1, 5}]],
          [byday: [{nil, 1}, {1, 2}]],
          [byday: [{1, 1}, {3, 1}], bysetpos: [-1]],
          [byday: [{2, 1}, {2, 3}], byhour: [9, 17], bysetpos: [1, -1]],
          [byday: [{1, 2}, {-1, 4}], bymonth: [2, 8]]
        ],
    year:
      @any ++
        [
          [byyearday: [1, 100, -1]],
          [byweekno: [20], byday: [{nil, 1}]],
          [byweekno: [20]],
          [byday: [{20, 1}]],
          [byday: [{-1, 7}], bymonth: [10]],
          [bymonth: [3], byday: [{nil, 4}]],
          [bymonth: [11], byday: [{nil, 2}], bymonthday: [2, 3, 4, 5, 6, 7, 8]],
          [byday: [{nil, 1}]],
          [bymonth: [1, 7], byday: [{1, 1}]],
          [byday: [{1, 7}, {-1, 7}], bymonth: [4, 10]],
          [bymonth: [6, 7], bymonthday: [1, -1], byhour: [8, 20]],
          [byday: [{1, 7}, {-1, 1}]],
          [byday: [{1, 1}, {1, 2}], bymonth: [6, 7]],
          [byday: [{10, 1}, {-10, 5}]],
          [byday: [{2, 1}, {-1, 6}], bymonth: [3], byhour: [9, 17]]
        ]
  ]

  @count 12

  # Two hundred years of days: a rule that picks a leap day every third day
  # has its first after the year 2200.
  @days_tried 366 * 200

  # A rule as data, the map `Tempo.RRule.from_rule/2` takes and the measure
  # takes alike.
  defp rule(frequency, interval, parts) do
    %{freq: frequency, count: @count}
    |> Map.merge(if interval > 1, do: %{interval: interval}, else: %{})
    |> Map.merge(Map.new(parts))
  end

  defp measured(rule, start),
    do: RRuleMeasure.occurrences(rule, start, Date.add(NaiveDateTime.to_date(start), @days_tried))

  defp given(rule, start) do
    {:ok, recurrence} = recurrence(rule, from: Tempo.from_elixir!(start))

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

        # The standard's examples begin on the clock of New York and end at
        # a time of UTC, which the measure reads on that clock.
        occurrences =
          RRuleMeasure.occurrences(
            unquote(rule),
            start,
            Date.add(NaiveDateTime.to_date(start), @days_tried),
            zone: "America/New_York"
          )

        if example.complete?,
          do: assert(occurrences == listed),
          else: assert(Enum.take(occurrences, length(listed)) == listed)
      end
    end
  end

  # A rule's text where text is what was given, its data where it was made.
  defp recurrence(text, options) when is_binary(text), do: RRule.parse(text, options)
  defp recurrence(%{} = rule, options), do: RRule.from_rule(rule, options)

  for {frequency, parts} <- @parts, part <- parts, interval <- [1, 2, 3] do
    test "every #{interval} #{frequency} with #{inspect(part)} has the occurrences the measure gives it" do
      for start <- @starts do
        rule = rule(unquote(frequency), unquote(interval), unquote(part))
        held(rule, start, measured(rule, start), given(rule, start))
      end
    end
  end

  describe "a yearly rule that counts a weekday in named months" do
    test "is one period a year, and is written back as it was read" do
      {:ok, thanksgiving} = RRule.parse("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH")

      assert Tempo.to_iso8601!(thanksgiving) == "R/../P1Y/FL11ML4K4INN"
      assert RRule.to_string(thanksgiving) == {:ok, "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH"}
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
