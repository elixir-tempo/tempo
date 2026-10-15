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

  alias Tempo.{Conformance, Interval, Rfc5545Examples, RRule, RRuleMeasure}

  # The rules, their starts and the measure's occurrences are the conformance
  # fixture `rrule.json` (`scripts/conformance_fixtures.exs` writes it from
  # the measure, and a test here holds the file to the measure): each
  # frequency of days or coarser, every one, two and three of them, with each
  # part alone and the parts together, from a last day of January, a leap day
  # and a Monday in June.
  @cases Conformance.fixture("rrule")["cases"]

  @count 12

  # Two hundred years of days: a rule that picks a leap day every third day
  # has its first after the year 2200.
  @days_tried 366 * 200

  defp measured(text, start),
    do: RRuleMeasure.occurrences(text, start, Date.add(NaiveDateTime.to_date(start), @days_tried))

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
  defp held(rule, start, measured, true = _complete?, given),
    do: assert({rule, start, given} == {rule, start, measured})

  defp held(rule, start, measured, false = _complete?, given),
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

  describe "the fixture" do
    test "holds 192 rules from three starts" do
      assert length(@cases) == 192 * 3
      assert @cases |> Enum.map(& &1["start"]) |> Enum.uniq() |> length() == 3
    end

    test "has the occurrences the measure gives each rule" do
      for %{"rule" => rule, "start" => start, "occurrences" => listed} = case <- @cases do
        start = NaiveDateTime.from_iso8601!(start)
        measured = measured(rule, start)

        assert {rule, start, Enum.map(measured, &NaiveDateTime.to_iso8601/1)} ==
                 {rule, start, listed}

        assert {rule, start, case["complete"]} == {rule, start, length(measured) in [0, @count]}
      end
    end
  end

  for {rule, cases} <- Enum.group_by(@cases, & &1["rule"]) do
    test "#{rule} has the occurrences the measure gives it" do
      for %{"start" => start, "occurrences" => listed, "complete" => complete?} <-
            unquote(Macro.escape(cases)) do
        start = NaiveDateTime.from_iso8601!(start)
        measured = Enum.map(listed, &NaiveDateTime.from_iso8601!/1)
        held(unquote(rule), start, measured, complete?, given(unquote(rule), start))
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
