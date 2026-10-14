defmodule Tempo.SetOperationsMeasureTest do
  use ExUnit.Case, async: true

  # The set operations held to answers worked out apart from them.
  #
  # Two sets are built from spans between numbered points of a line: days,
  # hours, hours written in two zones, days written in two calendars. Each
  # operation's answer is read back as the cells of that line it covers,
  # through `Date`, `NaiveDateTime` and `DateTime` and nothing of Tempo's
  # own, and compared with what the same spans give by arithmetic on whole
  # numbers: a cell is in a union when a member of either set holds it, in
  # an intersection when a member of each does, in a difference when one of
  # the first does and none of the second, and in a symmetric difference
  # when the members of just one do.
  #
  # Every pair of sets of up to two members between five points is run,
  # which is every way two members of each side can precede, meet, overlap,
  # nest and repeat.

  alias Tempo.{Interval, IntervalSet}

  @points 0..4
  @spans for from <- @points, to <- @points, from < to, do: {from, to}
  @sets [[]] ++
          for(span <- @spans, do: [span]) ++
          for(first <- @spans, second <- @spans, first <= second, do: [first, second])

  @operations [
    union: &Tempo.union/2,
    intersection: &Tempo.intersection/2,
    difference: &Tempo.difference/2,
    symmetric_difference: &Tempo.symmetric_difference/2
  ]

  ## The measure: the cells of a line

  defp cells(spans),
    do: for({from, to} <- spans, cell <- from..(to - 1), into: MapSet.new(), do: cell)

  defp expected(:union, a, b), do: MapSet.union(cells(a), cells(b))
  defp expected(:intersection, a, b), do: MapSet.intersection(cells(a), cells(b))
  defp expected(:difference, a, b), do: MapSet.difference(cells(a), cells(b))

  defp expected(:symmetric_difference, a, b),
    do: MapSet.union(MapSet.difference(cells(a), cells(b)), MapSet.difference(cells(b), cells(a)))

  ## The lines: a point as a value, and a member read back as its cells

  @first_day ~D[2026-06-01]
  @first_hour ~N[2026-06-01 09:00:00]

  # A day is a cell, and a span of days is written through its last day.
  defp day(slot, calendar \\ Calendar.ISO) do
    %Date{year: year, month: month, day: day} =
      Date.convert!(Date.add(@first_day, slot), calendar)

    Tempo.new!(year: year, month: month, day: day, calendar: calendar)
  end

  # An hour begins a cell, and a span of hours ends as its last hour begins.
  defp hour(slot, frame \\ []) do
    at = NaiveDateTime.add(@first_hour, slot * 3600)
    Tempo.new!([year: at.year, month: at.month, day: at.day, hour: at.hour] ++ frame)
  end

  # The same instant as the Paris clock shows it: the line is UTC's hours.
  defp paris_hour(slot) do
    at =
      @first_hour
      |> NaiveDateTime.add(slot * 3600)
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.shift_zone!("Europe/Paris")

    Tempo.new!(year: at.year, month: at.month, day: at.day, hour: at.hour, zone: "Europe/Paris")
  end

  defp span(:days, {from, to}), do: Interval.new!(from: day(from), to: day(to - 1))

  defp span(:hebrew_days, {from, to}),
    do: Interval.new!(from: day(from, Calendrical.Hebrew), to: day(to - 1, Calendrical.Hebrew))

  defp span(:hours, {from, to}), do: Interval.new!(from: hour(from), to: hour(to))

  defp span(:utc_hours, {from, to}),
    do: Interval.new!(from: hour(from, shift: [hour: 0]), to: hour(to, shift: [hour: 0]))

  defp span(:paris_hours, {from, to}),
    do: Interval.new!(from: paris_hour(from), to: paris_hour(to))

  defp set(line, spans), do: IntervalSet.new!(Enum.map(spans, &span(line, &1)))

  # The cells a member covers, read with Elixir's own dates and times.
  defp member_cells(member, :days) do
    {:ok, first} = Tempo.to_date(Interval.from(member))
    {:ok, last} = Tempo.to_date(Interval.to(member))
    Enum.to_list(day_slot(first)..day_slot(last))
  end

  defp member_cells(member, :hours) do
    {:ok, from} = Tempo.to_naive_datetime(Interval.from(member))
    {:ok, to} = Tempo.to_naive_datetime(Interval.to(member))
    Enum.to_list(hour_slot(from)..(hour_slot(to) - 1)//1)
  end

  defp member_cells(member, :instants) do
    {:ok, from} = Tempo.to_datetime(Interval.from(member))
    {:ok, to} = Tempo.to_datetime(Interval.to(member))
    Enum.to_list(instant_slot(from)..(instant_slot(to) - 1)//1)
  end

  defp day_slot(%Date{} = date), do: Date.diff(Date.convert!(date, Calendar.ISO), @first_day)
  defp hour_slot(%NaiveDateTime{} = at), do: div(NaiveDateTime.diff(at, @first_hour), 3600)

  defp instant_slot(%DateTime{} = at),
    do: div(DateTime.diff(at, DateTime.from_naive!(@first_hour, "Etc/UTC")), 3600)

  defp covered(set, reading) do
    set |> IntervalSet.members() |> Enum.flat_map(&member_cells(&1, reading)) |> MapSet.new()
  end

  # An operation over every pair of sets of two lines, each answer read back.
  defp held(line_a, line_b, reading) do
    for a <- @sets, b <- @sets, {name, operation} <- @operations do
      {:ok, answer} = operation.(set(line_a, a), set(line_b, b))

      assert {name, a, b, covered(answer, reading)} == {name, a, b, expected(name, a, b)}
    end
  end

  describe "every pair of sets of up to two members between five points" do
    test "of days" do
      held(:days, :days, :days)
    end

    test "of hours" do
      held(:hours, :hours, :hours)
    end

    test "of hours, one set written in UTC and the other on Paris's clock" do
      held(:utc_hours, :paris_hours, :instants)
      held(:paris_hours, :utc_hours, :instants)
    end

    test "of days, one set in the Gregorian calendar and the other in the Hebrew" do
      held(:days, :hebrew_days, :days)
      held(:hebrew_days, :days, :days)
    end
  end

  describe "two sets with no year, on the day's cycle" do
    # Times of day: a span from a later hour to an earlier one runs through
    # midnight, and is one member. A cell is an hour of the day.
    @cycle_points [0, 6, 12, 18]
    @cycle_spans for from <- @cycle_points, to <- @cycle_points, from != to, do: {from, to}
    @cycle_sets for(span <- @cycle_spans, do: [span]) ++
                  for(
                    first <- @cycle_spans,
                    second <- @cycle_spans,
                    first < second,
                    do: [first, second]
                  )

    defp cycle_cells(spans) do
      for {from, to} <- spans, cell <- hours_of(from, to), into: MapSet.new(), do: cell
    end

    defp hours_of(from, to) when from < to, do: Enum.to_list(from..(to - 1))
    defp hours_of(from, to), do: Enum.to_list(from..23) ++ Enum.to_list(0..(to - 1)//1)

    defp time_of_day(hour), do: Tempo.new!(hour: hour)

    defp cycle_set(spans) do
      IntervalSet.new!(
        Enum.map(spans, fn {from, to} ->
          Interval.new!(from: time_of_day(from), to: time_of_day(to))
        end)
      )
    end

    defp cycle_covered(set) do
      for member <- IntervalSet.members(set),
          cell <- hours_of(Tempo.hour(Interval.from(member)), Tempo.hour(Interval.to(member))),
          into: MapSet.new(),
          do: cell
    end

    test "are held to the hours of the day each covers" do
      for a <- @cycle_sets, b <- @cycle_sets do
        ca = cycle_cells(a)
        cb = cycle_cells(b)

        for {name, wanted} <- [
              intersection: MapSet.intersection(ca, cb),
              difference: MapSet.difference(ca, cb)
            ] do
          {:ok, answer} = Keyword.fetch!(@operations, name).(cycle_set(a), cycle_set(b))

          assert {name, a, b, cycle_covered(answer)} == {name, a, b, wanted}
        end
      end
    end
  end

  describe "the members of an answer" do
    # What an instant-level operation answers is spans that neither overlap
    # nor meet out of order: each begins after the one before it ends.
    test "of an intersection, a difference and a symmetric difference are apart and in order" do
      for a <- @sets, b <- @sets, name <- [:intersection, :difference, :symmetric_difference] do
        {:ok, answer} = Keyword.fetch!(@operations, name).(set(:hours, a), set(:hours, b))
        spans = answer |> IntervalSet.members() |> Enum.map(&member_cells(&1, :hours))

        for [earlier, later] <- Enum.chunk_every(spans, 2, 1, :discard) do
          assert {name, a, b, List.last(earlier) < hd(later)} == {name, a, b, true}
        end
      end
    end

    # A union keeps its operands' members, each whole, in the order of
    # their starts.
    test "of a union are the members of both, in the order of their starts" do
      for a <- @sets, b <- @sets do
        {:ok, answer} = Tempo.union(set(:hours, a), set(:hours, b))
        spans = answer |> IntervalSet.members() |> Enum.map(&member_cells(&1, :hours))

        assert {a, b, Enum.map(spans, &{hd(&1), List.last(&1) + 1})} == {a, b, Enum.sort(a ++ b)}
      end
    end
  end

  describe "the predicates" do
    test "are what the cells of two sets say" do
      for a <- @sets, b <- @sets, a != [], b != [] do
        sa = set(:hours, a)
        sb = set(:hours, b)
        ca = cells(a)
        cb = cells(b)

        assert {a, b, Tempo.overlaps?(sa, sb)} == {a, b, not MapSet.disjoint?(ca, cb)}
        assert {a, b, Tempo.disjoint?(sa, sb)} == {a, b, MapSet.disjoint?(ca, cb)}
        assert {a, b, Tempo.within?(sa, sb)} == {a, b, MapSet.subset?(ca, cb)}
        assert {a, b, Tempo.contains?(sa, sb)} == {a, b, MapSet.subset?(cb, ca)}
        assert {a, b, Tempo.equal?(sa, sb)} == {a, b, MapSet.equal?(ca, cb)}
      end
    end
  end
end
