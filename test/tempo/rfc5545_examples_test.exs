defmodule Tempo.Rfc5545ExamplesTest do
  use ExUnit.Case, async: true

  alias Tempo.{Interval, Rfc5545Examples, RRule}

  # Every recurrence example of RFC 5545 section 3.8.5.3, read from the text
  # of the standard (`Tempo.Rfc5545Examples`): each rule is read with the
  # example's DTSTART in America/New_York, and its occurrences are the dates
  # and times the standard lists, on the clock (EDT or EST) it lists them on.
  # Where the standard elides with "...", the occurrences before the
  # elision are held.

  # RFC 5545 lets a rule name the day its weeks start on, which is
  # significant in a rule of every second week or more that names weekdays:
  # such a rule is read into the weeks that begin on that day
  # (`[u-fw=sun]`), and is held to the standard's list as any other is.

  # One example's rule does not give what the standard lists for it: "Every 3
  # hours from 9:00 AM to 5:00 PM" has UNTIL at 17:00 UTC, which is 1 PM in
  # New York, where its text and its list mean 5 PM there. It is held to the
  # rule as it was meant, and the rule as printed is held to what it says.
  @misprinted %{
    "FREQ=HOURLY;INTERVAL=3;UNTIL=19970902T170000Z" =>
      "FREQ=HOURLY;INTERVAL=3;UNTIL=19970902T210000Z"
  }

  defp start({{year, month, day}, {hour, minute, second}}) do
    Tempo.new!(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      zone: "America/New_York"
    )
  end

  defp occurrences(recurrence, example) do
    listed = length(example.occurrences) + length(example.excluded)

    occurrences =
      if Tempo.bounded?(recurrence),
        do: Enum.to_list(recurrence),
        else: Enum.take(recurrence, listed)

    occurrences
    |> Enum.map(&occurrence/1)
    |> Enum.reject(fn {date, _time, _zone} -> date in example.excluded end)
  end

  defp occurrence(span) do
    {:ok, at} = span |> Interval.from() |> Tempo.to_datetime()
    {{at.year, at.month, at.day}, {at.hour, at.minute}, at.zone_abbr}
  end

  # The examples are read once, and each test takes its own by number.
  defp example(index), do: Enum.at(Rfc5545Examples.all(), index)

  for {example, index} <- Enum.with_index(Rfc5545Examples.all()), rule <- example.rules do
    test "#{example.title}: #{rule}" do
      example = example(unquote(index))
      rule = Map.get(@misprinted, unquote(rule), unquote(rule))
      assert {:ok, recurrence} = RRule.parse(rule, from: start(example.start))

      given = occurrences(recurrence, example)
      listed = example.occurrences

      if example.complete? and Tempo.bounded?(recurrence),
        do: assert(given == listed),
        else: assert(Enum.take(given, length(listed)) == listed)
    end
  end

  test "the misprinted rule, as printed, ends where it says" do
    start = start({{1997, 9, 2}, {9, 0, 0}})

    for {printed, _meant} <- @misprinted do
      assert {:ok, recurrence} = RRule.parse(printed, from: start)
      assert Enum.map(recurrence, &elem(occurrence(&1), 1)) == [{9, 0}, {12, 0}]
    end
  end

  test "the standard's examples are all read" do
    examples = Rfc5545Examples.all()
    assert Enum.count_until(examples, 40) == 39
    assert Enum.all?(examples, &match?(%{rules: [_ | _], occurrences: [_ | _]}, &1))
  end
end
