defmodule Tempo.CronTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.{Cron, Interval, IntervalSet}

  # The firings of a cron expression, held to a matcher written apart from
  # the library: every minute of a window is asked, with Elixir's own `Date`
  # and `NaiveDateTime`, whether the expression's fields name it.

  @window ~o"2026-01/2026-04"
  @first ~N[2026-01-01 00:00:00]
  @minutes 120 * 24 * 60

  # ── The matcher ───────────────────────────────────────────────────────

  @months ~w(jan feb mar apr may jun jul aug sep oct nov dec)
  @days ~w(sun mon tue wed thu fri sat)

  defp expected(expression) do
    [minute, hour, dom, month, dow] = String.split(expression)

    for offset <- 0..(@minutes - 1),
        at = NaiveDateTime.add(@first, offset * 60),
        named?(minute, at.minute, 0..59, []),
        named?(hour, at.hour, 0..23, []),
        named?(month, at.month, 1..12, @months),
        day?(dom, dow, NaiveDateTime.to_date(at)),
        do: at
  end

  # POSIX: both day fields restricted fire on either; one restricted, on it.
  defp day?("*", "*", _date), do: true
  defp day?(dom, "*", date), do: day_of_month?(dom, date)
  defp day?("*", dow, date), do: day_of_week?(dow, date)
  defp day?(dom, dow, date), do: day_of_month?(dom, date) or day_of_week?(dow, date)

  defp day_of_month?("L", date), do: date.day == Date.days_in_month(date)
  defp day_of_month?("LW", date), do: date == last_weekday(Date.end_of_month(date))

  defp day_of_month?(field, date) do
    case Integer.parse(field) do
      {day, "W"} -> date == nearest_weekday(%{date | day: day})
      _ -> named?(field, date.day, 1..31, [])
    end
  end

  defp last_weekday(date),
    do: if(Date.day_of_week(date) > 5, do: last_weekday(Date.add(date, -1)), else: date)

  # The weekday nearest a day, never leaving its month.
  defp nearest_weekday(date) do
    case {Date.day_of_week(date), date.day} do
      {6, 1} -> Date.add(date, 2)
      {6, _} -> Date.add(date, -1)
      {7, _} -> Date.add(date, 1)
      _weekday -> date
    end
  end

  defp day_of_week?(field, date) do
    weekday = rem(Date.day_of_week(date), 7)

    cond do
      String.ends_with?(field, "L") ->
        weekday == cron_day(String.trim_trailing(field, "L")) and
          date.month != Date.add(date, 7).month

      String.contains?(field, "#") ->
        [day, nth] = String.split(field, "#")
        weekday == cron_day(day) and div(date.day - 1, 7) + 1 == String.to_integer(nth)

      true ->
        named?(field, weekday, 0..6, @days) or (weekday == 0 and named?(field, 7, 0..7, @days))
    end
  end

  defp cron_day(text), do: rem(value(text, @days), 7)

  defp named?(field, value, range, names) do
    field
    |> String.split(",")
    |> Enum.any?(fn item ->
      {body, step} =
        case String.split(item, "/") do
          [body, step] -> {body, String.to_integer(step)}
          [body] -> {body, 1}
        end

      {first, last} =
        case String.split(body, "-") do
          ["*"] -> {range.first, range.last}
          [one] -> {value(one, names), value(one, names)}
          [a, b] -> {value(a, names), value(b, names)}
        end

      value in first..last//step
    end)
  end

  defp value(text, names) do
    case Integer.parse(text) do
      {n, ""} ->
        n

      _ ->
        Enum.find_index(names, &(&1 == String.downcase(text))) +
          if(names == @months, do: 1, else: 0)
    end
  end

  # ── What the library gives ────────────────────────────────────────────

  defp firings(expression) do
    {:ok, recurrence} = Cron.parse(expression, from: ~o"2026-01-01T00:00")
    {:ok, set} = Tempo.to_interval(recurrence, within: @window)

    set
    |> IntervalSet.members()
    |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_naive_datetime() |> elem(1)))
    |> Enum.sort(NaiveDateTime)
    |> Enum.dedup()
  end

  @expressions [
    "0 9 * * *",
    "*/15 * 1 1 *",
    "5/20 9-10 * * 1-5",
    "0 0 * * 0",
    "0 0 * * 7",
    "0 12 1,15 * *",
    "30 8 * feb,mar mon",
    "0 0 13 * 5",
    "0 9 L * *",
    "0,30 9 L * *",
    "0 9 LW * *",
    "0,30 9,17 LW * *",
    "0 9 15W * *",
    "0 9 1W * *",
    "0 9 27W * *",
    "15,45 8 14W 2-3 *",
    "0 9 * * 5L",
    "0,30 9 * * 5L",
    "0 9 * * 1#2",
    "0,30 9,10 * * mon#1",
    "0 9 * * 0#5",
    "0 9 L * 5L",
    "0 9 15W * 3"
  ]

  for expression <- @expressions do
    test "#{expression} fires when its fields say" do
      assert firings(unquote(expression)) == expected(unquote(expression))
    end
  end

  describe "what is not a cron expression" do
    test "is an error that says so" do
      for text <- [
            "@reboot",
            "0 9 * *",
            "61 9 * * *",
            "0 9 31W * *",
            "0 9 1-5W * *",
            "0 9 * * 8L",
            "0 9 * * 1#6",
            "0 9 L,15 * *"
          ] do
        assert {:error, %ArgumentError{}} = Cron.parse(text)
      end
    end

    test "a day a short month may not have has no nearest weekday" do
      assert {:error, %ArgumentError{message: message}} = Cron.parse("0 9 30W * *")
      assert message =~ "depends on the month's length"
    end
  end

  describe "a rule given no start" do
    test "has none, as an RRULE has none" do
      assert Cron.parse("0 9 * * 1") == {:ok, ~o"R/../P1M/FL1KT9H0MN"}
    end

    test "has its firings in a window, and none without one" do
      {:ok, mondays} = Cron.parse("0 9 * * 1")
      {:ok, set} = Tempo.to_interval(mondays, within: ~o"2026-06-01/2026-06-14")

      assert IntervalSet.map(set, &Interval.from/1) ==
               [~o"2026-06-01T09:00", ~o"2026-06-08T09:00"]

      assert {:error, %Tempo.ConversionError{reason: :unbounded}} = Tempo.members(mondays)
    end
  end

  describe "aliases and fields" do
    test "an alias is its five fields" do
      assert Cron.parse("@daily", from: ~o"2026-01-01") ==
               Cron.parse("0 0 * * *", from: ~o"2026-01-01")
    end

    test "six fields have seconds first, and seven a year last" do
      {:ok, recurrence} = Cron.parse("30 0 9 1 1 * 2026-2027", from: ~o"2026-01-01T00:00:00")
      {:ok, set} = Tempo.to_interval(recurrence, within: ~o"2025/2029")

      assert IntervalSet.map(set, &Interval.from/1) ==
               [~o"2026-01-01T09:00:30", ~o"2027-01-01T09:00:30"]
    end
  end
end
