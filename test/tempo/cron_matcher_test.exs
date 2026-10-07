defmodule Tempo.CronMatcherTest do
  @moduledoc """
  The firings of a cron expression, held to a matcher written apart from
  the library.

  A five-field expression fires at each minute whose minute, hour and month
  are ones its fields name and whose day is: the day of the month and the
  day of the week both, or either where neither field starts with `*`
  (POSIX's union). The matcher here reads an expression's fields into the
  values they name and asks every minute of two months, one after another,
  with Elixir's own `NaiveDateTime` and `Date.day_of_week/1`.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Cron
  alias Tempo.Interval
  alias Tempo.IntervalSet

  @months ~w(jan feb mar apr may jun jul aug sep oct nov dec)
  @days ~w(sun mon tue wed thu fri sat)

  @expressions [
    "*/15 * * * *",
    "5/15 * * * *",
    "0 9-17 * * 1-5",
    "0 0 * * 0",
    "0 0 * * 7",
    "30 2 1,15 * *",
    "0 0 13 * 5",
    "0 0 */2 * 1",
    "0 12 * JAN-MAR *",
    "0 12 * 6 MON,WED,FRI",
    "15,45 8-10/2 * * *",
    "0 0 1-7 * 1",
    "0 6 * * 6,0",
    "59 23 31 12 *",
    "0 0 29 2 *",
    "*/7 */5 * * *",
    "0 0 1 */3 *",
    "0 0 * * 1-5/2",
    "0 0 * * 0/3",
    "0 0 * * */2",
    "0 0 * * 5/2",
    "10-50/20 * * * *",
    "0 0 2-30/7 * *",
    "0 0 * * SUN",
    "0 0 * * sat",
    "0 0 31 * *",
    "0 0 30 2,4 *",
    "0 4 8-14 * *",
    "5 0 * 8 *",
    "0 22 * * 1-5",
    "23 0-20/2 * * *"
  ]

  # The first firings compared, and the window they are looked for in.
  @compared 40
  @window_starts ~N[2026-06-01 00:00:00]
  @minutes_in_window 61 * 24 * 60

  ## The matcher

  # The values a field names, and whether it is restricted: a field that
  # starts with `*` is not, whatever its step.
  defp field(text, low..high//_, names) do
    values =
      for part <- String.split(text, ","),
          value <- values_of(String.split(part, "/"), {low, high}, names),
          do: value

    {MapSet.new(values), not String.starts_with?(text, "*")}
  end

  defp values_of([range], bounds, names), do: Enum.to_list(ends(range, bounds, names, nil))

  defp values_of([range, step], bounds, names) do
    step = String.to_integer(step)
    range |> ends(bounds, names, step) |> Enum.take_every(step)
  end

  # A range's ends. A number alone before a step runs from it to the end of
  # its field.
  defp ends(range, {low, high}, names, step) do
    case String.split(range, "-") do
      ["*"] -> low..high//1
      [one] when is_nil(step) -> number(one, names)..number(one, names)//1
      [one] -> number(one, names)..high//1
      [first, last] -> number(first, names)..number(last, names)//1
    end
  end

  defp number(text, names) do
    case Enum.find_index(names, &(&1 == String.downcase(text))) do
      nil -> String.to_integer(text)
      index when names == @months -> index + 1
      index -> index
    end
  end

  defp matcher(expression) do
    [minute, hour, day, month, weekday] = String.split(expression, " ")
    {minutes, _restricted?} = field(minute, 0..59, [])
    {hours, _restricted?} = field(hour, 0..23, [])
    {months, _restricted?} = field(month, 1..12, @months)
    days = field(day, 1..31, [])
    weekdays = field(weekday, 0..7, @days)

    fn %NaiveDateTime{} = at ->
      at.minute in minutes and at.hour in hours and at.month in months and
        on_its_day?(at, days, weekdays)
    end
  end

  # Both of its days where either field starts with a star, and either of
  # them where neither does.
  defp on_its_day?(at, {days, day_restricted?}, {weekdays, weekday_restricted?}) do
    day? = at.day in days
    weekday? = Enum.any?(numbers_of(Date.day_of_week(at)), &(&1 in weekdays))

    if day_restricted? and weekday_restricted?, do: day? or weekday?, else: day? and weekday?
  end

  # Sunday is 0 and 7.
  defp numbers_of(7), do: [0, 7]
  defp numbers_of(weekday), do: [weekday]

  # Every minute of the window, one after another.
  defp minutes_of_window do
    @window_starts
    |> Stream.iterate(&NaiveDateTime.add(&1, 60))
    |> Enum.take(@minutes_in_window)
  end

  defp firings(expression, minutes \\ minutes_of_window()),
    do: minutes |> Stream.filter(matcher(expression)) |> Enum.take(@compared)

  defp moment(%NaiveDateTime{} = at),
    do: at |> NaiveDateTime.to_erl() |> :calendar.datetime_to_gregorian_seconds()

  describe "a five-field expression" do
    test "fires at the minutes the matcher finds, in June and July 2026" do
      minutes = minutes_of_window()

      for expression <- @expressions do
        {:ok, rule} = Cron.parse(expression)
        {:ok, %IntervalSet{} = fired} = Tempo.to_interval(rule, within: ~o"2026-06-01/2026-08-01")

        starts =
          fired
          |> IntervalSet.members()
          |> Enum.take(@compared)
          |> Enum.map(&(&1 |> Interval.from() |> Compare.to_utc_seconds() |> trunc()))

        assert {expression, starts} ==
                 {expression, Enum.map(firings(expression, minutes), &moment/1)}
      end
    end

    test "is the union of its days where neither day field starts with a star, and else both" do
      # The 13th or a Friday: eleven midnights of June and July 2026.
      fridays =
        Enum.filter(Date.range(~D[2026-06-01], ~D[2026-07-31]), &(Date.day_of_week(&1) == 5))

      assert Enum.count(fridays) == 9
      assert Enum.count(firings("0 0 13 * 5")) == 11

      # Odd-numbered days that are Mondays: both.
      assert Enum.map(firings("0 0 */2 * 1"), &NaiveDateTime.to_date/1) ==
               Enum.filter(
                 Date.range(~D[2026-06-01], ~D[2026-07-31]),
                 &(Date.day_of_week(&1) == 1 and rem(&1.day, 2) == 1)
               )
    end
  end
end
