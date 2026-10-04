defmodule Tempo.SetOperationsMeasureTest do
  @moduledoc """
  The set operations held to answers worked out apart from them
  (`plans/set-operations.md`).

  Two sets are built from spans between numbered points of a line: days,
  hours, hours in two zones, days of two calendars. Each operation's answer
  is read back as positions on that line by `Tempo.Matrix.Extent`, which
  reads a value's units with `Date`, `NaiveDateTime` and `DateTime` and
  never with `Tempo.Compare`, and is compared with what `Tempo.Matrix.Sets`
  makes of the same spans by arithmetic on whole numbers.

  Every pair of sets of up to two members between five points is run, which
  is every way two members of each side can precede, meet, overlap, nest and
  repeat; and generated sets of up to six members on each line.

  What is compared is the members an answer holds, each with the mark of
  the member it is or was cut from, and that they come in the order of
  their starts; not only the time they cover.

  The answers are themselves held to each operation's definition: a cell of
  a line is in a difference when a member of the first holds it and none of
  the second does, and so on, cell by cell.

  A set with no year is on a cycle: the day, the week, the year. The time
  such a set covers, the time at least so many of its members cover, and
  whether a point is covered, are held to arcs of the cycle worked out the
  same way; and so is each operation of two such sets, a member that runs
  through its cycle's end being one member, in the answer as in the set.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Extent
  alias Tempo.Matrix.Sets

  @day 86_400_000_000

  setup_all do
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    :ok
  end

  ## Lines

  # The point of a line a number names. Each is written as text and read,
  # so what is measured is what a caller builds; and each is read once, a
  # test asking for the same few points thousands of times.
  defp point(line, slot) do
    case Process.get({:point, line, slot}) do
      nil ->
        point = read_point(line, slot)
        Process.put({:point, line, slot}, point)
        point

      point ->
        point
    end
  end

  defp read_point(:days, slot),
    do: ~D[2026-06-01] |> Date.add(slot) |> Date.to_iso8601() |> Tempo.from_iso8601!()

  defp read_point(:hours, slot),
    do: slot |> hour() |> Calendar.strftime("%Y-%m-%dT%H") |> Tempo.from_iso8601!()

  defp read_point(:utc_hours, slot),
    do: (Calendar.strftime(hour(slot), "%Y-%m-%dT%H") <> "Z") |> Tempo.from_iso8601!()

  defp read_point(:paris_hours, slot) do
    paris =
      slot |> hour() |> DateTime.from_naive!("Etc/UTC") |> DateTime.shift_zone!("Europe/Paris")

    Tempo.from_iso8601!(Calendar.strftime(paris, "%Y-%m-%dT%H") <> "[Europe/Paris]")
  end

  defp read_point(:hebrew_days, slot), do: day_in(Calendrical.Hebrew, slot)
  defp read_point(:persian_days, slot), do: day_in(Calendrical.Persian, slot)

  # Lines with no year, each a cycle whose points are counted from its start.
  defp read_point(:day_hours, slot), do: Tempo.from_iso8601!("T#{slot}H")
  defp read_point(:weekdays, slot), do: Tempo.from_iso8601!("#{slot + 1}K")
  defp read_point(:months, slot), do: Tempo.from_iso8601!("#{slot + 1}M")

  defp read_point(:year_days, slot),
    do: Tempo.from_iso8601!("#{div(slot, 3) + 1}M#{Enum.at([1, 10, 20], rem(slot, 3))}D")

  defp hour(slot), do: NaiveDateTime.add(~N[2026-06-01 00:00:00], slot, :hour)

  defp day_in(calendar, slot) do
    date = ~D[2026-06-01] |> Date.add(slot) |> Date.convert!(calendar)
    Tempo.from_iso8601!("#{date.year}Y#{date.month}M#{date.day}D", calendar)
  end

  # The points a cycle has, and its length in microseconds: the day, the
  # week, and the longest year, in which every date has a place.
  defp cycle(:day_hours), do: {24, @day}
  defp cycle(:weekdays), do: {7, 7 * @day}
  defp cycle(:months), do: {12, 366 * @day}
  defp cycle(:year_days), do: {36, 366 * @day}

  # How many of a line's points are one day, so that a line of days and one
  # of hours can be generated over the same days.
  defp points_in_a_day(line) when line in [:hours, :utc_hours, :paris_hours], do: 24
  defp points_in_a_day(_days), do: 1

  ## Sets

  # A set of the spans `{from, to}` between a line's points, each member
  # marked with the side it is on and its place in the list.
  defp set(slots, line, side, options) do
    slots
    |> Enum.with_index()
    |> Enum.map(fn {{from, to}, index} ->
      Interval.new!(from: point(line, from), to: point(line, to), metadata: %{id: {side, index}})
    end)
    |> IntervalSet.new!(options)
  end

  # The members of a set as positions on its line, with their marks. A set
  # holds its members in the order of their starts, which is checked of
  # every set read; members that start together have no order of their own.
  defp read(%IntervalSet{} = set) do
    spans =
      set
      |> IntervalSet.members()
      |> Enum.map(fn %Interval{from: from, to: to, metadata: metadata} ->
        {position(from), position(to), Map.get(metadata, :id)}
      end)

    starts = Enum.map(spans, &elem(&1, 0))
    assert starts == Enum.sort(starts), "members not in the order of their starts"

    Sets.ordered(spans)
  end

  defp read({:ok, %IntervalSet{} = set}), do: read(set)

  defp position(%Tempo{} = point) do
    {:ok, _line, position} = Extent.position(point)
    position
  end

  defp stretches(spans), do: Enum.map(spans, fn {from, to, _id} -> {from, to} end)

  ## The answers

  # Every operation of two sets, held to the answer worked out from the
  # positions of their members.
  defp assert_operations(a_slots, a_line, b_slots, b_line, options \\ []) do
    a = set(a_slots, a_line, :a, options)
    b = set(b_slots, b_line, :b, options)
    in_a = read(a)
    in_b = read(b)
    named = "#{inspect(a_slots)} on #{a_line} and #{inspect(b_slots)} on #{b_line}"

    assert read(Tempo.union(a, b)) == Sets.union(in_a, in_b), "union of #{named}"

    assert read(Tempo.difference(a, b)) == Sets.difference(in_a, in_b), "difference of #{named}"

    assert read(Tempo.symmetric_difference(a, b)) == Sets.symmetric_difference(in_a, in_b),
           "symmetric_difference of #{named}"

    assert read(Tempo.complement(a, within: b)) == Sets.difference(in_b, in_a),
           "complement of #{named}"

    assert read(Tempo.members_overlapping(a, b)) == Sets.members_overlapping(in_a, in_b),
           "members_overlapping of #{named}"

    assert read(Tempo.members_outside(a, b)) == Sets.members_outside(in_a, in_b),
           "members_outside of #{named}"

    assert read(Tempo.members_in_exactly_one(a, b)) == Sets.members_in_exactly_one(in_a, in_b),
           "members_in_exactly_one of #{named}"

    assert_intersection(a, b, in_a, in_b, named)
    assert_predicates(a, b, in_a, in_b, named)
    assert_cover(a, in_a, named)
    assert_answers_as_operands(a, b, in_a, in_b, named)
  end

  # An answer is an operand again: the first without what is left of it is
  # each of its members cut to what the second covers, and the complement of
  # a complement within a window is the window cut to what the value covers.
  defp assert_answers_as_operands(a, b, in_a, in_b, named) do
    {:ok, left} = Tempo.difference(a, b)
    {:ok, outside} = Tempo.complement(a, within: b)

    assert read(Tempo.difference(a, left)) ==
             Sets.difference(in_a, Sets.difference(in_a, in_b)),
           "the first without what is left of it, of #{named}"

    assert read(Tempo.complement(outside, within: b)) ==
             Sets.difference(in_b, Sets.difference(in_b, in_a)),
           "the complement of the complement, of #{named}"
  end

  # The time an intersection covers is what both cover, and each part of it
  # is a member of the first cut to a member of the second, with the first's
  # mark. Where no two members of either side overlap each other, there is
  # one part for each pair that overlaps. Where they do, whether there is
  # one for each pair or one for each stretch of time is to be decided
  # (`plans/set-operations.md`).
  defp assert_intersection(a, b, in_a, in_b, named) do
    parts = read(Tempo.intersection(a, b))
    pairs = Sets.pairwise(in_a, in_b)

    assert Sets.cover(parts) == Sets.shared(in_a, in_b),
           "the time intersection covers, of #{named}"

    assert parts -- pairs == [], "intersection of #{named} gives a part no pair of members makes"

    unless Sets.overlap_each_other?(in_a) or Sets.overlap_each_other?(in_b) do
      assert parts == pairs, "intersection of #{named}"
    end
  end

  defp assert_predicates(a, b, in_a, in_b, named) do
    shared? = Sets.shared(in_a, in_b) != []

    assert Tempo.overlaps?(a, b) == shared?, "overlaps? of #{named}"
    assert Tempo.disjoint?(a, b) == not shared?, "disjoint? of #{named}"
    assert Tempo.within?(a, b) == (Sets.difference(in_a, in_b) == []), "within? of #{named}"
    assert Tempo.contains?(a, b) == (Sets.difference(in_b, in_a) == []), "contains? of #{named}"
    assert Tempo.equal?(a, b) == (Sets.cover(in_a) == Sets.cover(in_b)), "equal? of #{named}"
  end

  # One set's own cover: merged, and counted by how many members cover it,
  # each stretch as long as it can be.
  defp assert_cover(a, in_a, named) do
    assert stretches(read(IntervalSet.coalesce(a))) == Sets.cover(in_a), "coalesce of #{named}"

    for at_least <- 1..3 do
      {:ok, regions} = IntervalSet.covered(a, at_least: at_least)

      assert stretches(read(regions)) == Sets.covered(in_a, at_least),
             "covered at least #{at_least} times, of #{named}"
    end
  end

  # The same of a set with no year, as arcs of its cycle: a member, and a
  # stretch, may run through the cycle's end.
  defp assert_cover_on_cycle(slots, line) do
    {_points, length} = cycle(line)
    set = set(slots, line, :a, [])
    arcs = stretches(read(set))
    named = "#{inspect(slots)} on #{line}"

    assert stretches(read(IntervalSet.coalesce(set))) == Sets.covered_on_cycle(arcs, 1, length),
           "coalesce of #{named}"

    for at_least <- 1..3 do
      {:ok, regions} = IntervalSet.covered(set, at_least: at_least)

      assert stretches(read(regions)) == Sets.covered_on_cycle(arcs, at_least, length),
             "covered at least #{at_least} times, of #{named}"
    end
  end

  ## The answers themselves

  # The whole cells `[cell, cell + 1)` some stretches hold, in order.
  defp cells(stretches) do
    stretches
    |> Enum.flat_map(fn stretch -> Enum.to_list(elem(stretch, 0)..(elem(stretch, 1) - 1)//1) end)
    |> Enum.sort()
  end

  defp holders(spans, cell),
    do: Enum.count(spans, fn {from, to, _id} -> from <= cell and cell < to end)

  defp holds?(spans, cell), do: holders(spans, cell) > 0

  # Whether each stretch ends before the next starts, so that none could be
  # longer than it is.
  defp apart?(stretches) do
    stretches
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [{_from, to}, {next_from, _to}] -> to < next_from end)
  end

  # Up to five spans between twelve points, each marked.
  defp marked_spans(side) do
    span =
      gen all(from <- integer(0..10), to <- integer((from + 1)..11)) do
        {from, to}
      end

    gen all(spans <- list_of(span, max_length: 5)) do
      spans
      |> Enum.with_index()
      |> Enum.map(fn {{from, to}, index} -> {from, to, {side, index}} end)
    end
  end

  # What is left of one member of `a`, and which of the two lists of members
  # it is in, by the cells of it that `b` holds.
  defp assert_member_by_cells({from, to, id} = member, a, b) do
    parts = for {part_from, part_to, ^id} <- Sets.difference(a, b), do: {part_from, part_to}
    own = from..(to - 1)//1

    assert cells(parts) == Enum.reject(own, &holds?(b, &1))
    assert apart?(parts)
    assert member in Sets.members_overlapping(a, b) == Enum.any?(own, &holds?(b, &1))
    assert member in Sets.members_outside(a, b) == not Enum.any?(own, &holds?(b, &1))
  end

  # The cells of a cycle an arc holds, by going round from its start to its
  # end: all of them where it ends where it starts.
  defp cells_round({from, from}, length), do: Enum.to_list(0..(length - 1))

  defp cells_round({from, to}, length) do
    from
    |> Stream.iterate(&Integer.mod(&1 + 1, length))
    |> Enum.take_while(&(&1 != to))
  end

  # Whether the cells either side of an arc are not covered, so that it
  # could be no longer.
  defp as_long_as_can_be?({from, from}, _covered, _length), do: true

  defp as_long_as_can_be?({from, to}, covered, length),
    do: Integer.mod(from - 1, length) not in covered and to not in covered

  # Up to five arcs between the points of a cycle: any point to any point.
  defp arcs_between(points) do
    arc =
      gen all(from <- integer(0..(points - 1)), to <- integer(0..(points - 1))) do
        {from, to}
      end

    list_of(arc, max_length: 5)
  end

  defp assert_cycle_by_cells(arcs, at_least, length) do
    regions = Sets.covered_on_cycle(arcs, at_least, length)

    covered =
      Enum.filter(0..(length - 1), fn cell ->
        Enum.count(arcs, &(cell in cells_round(&1, length))) >= at_least
      end)

    assert regions |> Enum.flat_map(&cells_round(&1, length)) |> Enum.sort() == covered
    assert regions == Enum.sort(regions)
    assert Enum.all?(regions, &as_long_as_can_be?(&1, covered, length))
  end

  describe "the answers the operations are held to" do
    property "are the time covered on a cycle, cell by cell" do
      check all(arcs <- arcs_between(12), at_least <- integer(1..3), max_runs: 500) do
        assert_cycle_by_cells(arcs, at_least, 12)
      end
    end

    property "are each operation's definition, cell by cell" do
      check all(a <- marked_spans(:a), b <- marked_spans(:b), max_runs: 300) do
        line = 0..10

        assert cells(Sets.cover(a)) == Enum.filter(line, &holds?(a, &1))
        assert apart?(Sets.cover(a))

        assert cells(Sets.shared(a, b)) == Enum.filter(line, &(holds?(a, &1) and holds?(b, &1)))
        assert apart?(Sets.shared(a, b))

        Enum.each(a, &assert_member_by_cells(&1, a, b))

        for at_least <- 1..3 do
          assert cells(Sets.covered(a, at_least)) ==
                   Enum.filter(line, &(holders(a, &1) >= at_least))

          assert apart?(Sets.covered(a, at_least))
        end

        assert Sets.overlap_each_other?(a) == Enum.any?(line, &(holders(a, &1) >= 2))
      end
    end
  end

  ## Every small pair

  # The spans between five points, and every set of none, one or two of them.
  @spans for from <- 0..3, to <- (from + 1)..4, do: {from, to}

  defp small_sets do
    pairs =
      for {first, index} <- Enum.with_index(@spans),
          second <- Enum.drop(@spans, index),
          do: [first, second]

    [[]] ++ Enum.map(@spans, &[&1]) ++ pairs
  end

  describe "every pair of sets of up to two members between five points" do
    test "of days" do
      sets = small_sets()
      assert length(sets) == 66

      for a_slots <- sets, b_slots <- sets do
        assert_operations(a_slots, :days, b_slots, :days)
      end
    end

    test "is answered alike by a tree and by a list" do
      sets = small_sets()

      for a_slots <- sets, b_slots <- Enum.take_every(sets, 5) do
        assert_operations(a_slots, :days, b_slots, :days, backend: :tree)
      end
    end
  end

  ## Generated sets

  # Up to six spans between the points of some days, counted in a line's
  # own points: a line of hours has twenty-four to the day.
  defp spans_on(line, days) do
    last = days * points_in_a_day(line)

    span =
      gen all(from <- integer(0..(last - 1)), to <- integer((from + 1)..last)) do
        {from, to}
      end

    list_of(span, max_length: 6)
  end

  for {a_line, b_line, what} <- [
        {:days, :days, "days"},
        {:hours, :hours, "hours"},
        {:days, :hours, "days and hours, the coarser extended to the finer"},
        {:hours, :days, "hours and days"},
        {:utc_hours, :paris_hours, "hours in two zones, on the one time line"},
        {:paris_hours, :utc_hours, "hours in a zone and in UTC"},
        {:hebrew_days, :days, "days of the Hebrew calendar and the Gregorian"},
        {:days, :hebrew_days, "days of the Gregorian calendar and the Hebrew"},
        {:hebrew_days, :persian_days, "days of the Hebrew calendar and the Persian"}
      ] do
    property "two sets of #{what}" do
      check all(
              a_slots <- spans_on(unquote(a_line), 4),
              b_slots <- spans_on(unquote(b_line), 4),
              max_runs: 60
            ) do
        assert_operations(a_slots, unquote(a_line), b_slots, unquote(b_line))
      end
    end
  end

  ## A set with no year

  # The members of a set with no year as arcs of its cycle in the line's own
  # points, with their marks: a member is read at the points it is written
  # between, and one that ends where its cycle does ends at point 0.
  defp arcs(%IntervalSet{} = set, line) do
    {points, _length} = cycle(line)
    point_at = Map.new(0..(points - 1), &{position(point(line, &1)), &1})

    for {from, to, id} <- read(set) do
      {Map.fetch!(point_at, from), Map.fetch!(point_at, to), id}
    end
    |> Sets.ordered()
  end

  defp arcs({:ok, %IntervalSet{} = set}, line), do: arcs(set, line)

  # Every operation of two sets with no year, held to the answer worked out
  # from the cells of the cycle their members hold. A member that runs
  # through its cycle's end is one member: it came back from an operation as
  # the two spans it is swept by.
  defp assert_operations_on_cycle(a_slots, b_slots, line) do
    {cells, _length} = cycle(line)
    a = set(a_slots, line, :a, [])
    b = set(b_slots, line, :b, [])
    in_a = arcs(a, line)
    in_b = arcs(b, line)
    named = "#{inspect(a_slots)} and #{inspect(b_slots)} on #{line}"

    assert arcs(Tempo.union(a, b), line) == Sets.union(in_a, in_b), "union of #{named}"

    assert arcs(Tempo.difference(a, b), line) == Sets.difference_on_cycle(in_a, in_b, cells),
           "difference of #{named}"

    assert arcs(Tempo.symmetric_difference(a, b), line) ==
             Sets.ordered(
               Sets.difference_on_cycle(in_a, in_b, cells) ++
                 Sets.difference_on_cycle(in_b, in_a, cells)
             ),
           "symmetric_difference of #{named}"

    assert arcs(Tempo.intersection(a, b), line) == Sets.pairwise_on_cycle(in_a, in_b, cells),
           "intersection of #{named}"

    assert arcs(Tempo.members_overlapping(a, b), line) ==
             Sets.members_on_cycle(in_a, in_b, cells, :overlapping),
           "members_overlapping of #{named}"

    assert arcs(Tempo.members_outside(a, b), line) ==
             Sets.members_on_cycle(in_a, in_b, cells, :outside),
           "members_outside of #{named}"

    assert_predicates_on_cycle(a, b, in_a, in_b, cells, named)
  end

  defp assert_predicates_on_cycle(a, b, in_a, in_b, cells, named) do
    held = fn arcs -> arcs |> Enum.flat_map(&Sets.arc_cells(&1, cells)) |> MapSet.new() end
    {a_cells, b_cells} = {held.(in_a), held.(in_b)}

    assert Tempo.overlaps?(a, b) == not MapSet.disjoint?(a_cells, b_cells),
           "overlaps? of #{named}"

    assert Tempo.within?(a, b) == MapSet.subset?(a_cells, b_cells), "within? of #{named}"
    assert Tempo.contains?(a, b) == MapSet.subset?(b_cells, a_cells), "contains? of #{named}"
    assert Tempo.equal?(a, b) == MapSet.equal?(a_cells, b_cells), "equal? of #{named}"
  end

  describe "two sets with no year, on their cycle" do
    test "every pair of sets of up to two spans between four hours of the day" do
      hours = [0, 1, 22, 23]
      arcs = for from <- hours, to <- hours, do: {from, to}

      pairs =
        for {first, index} <- Enum.with_index(arcs), second <- Enum.drop(arcs, index) do
          [first, second]
        end

      sets = [[]] ++ Enum.map(arcs, &[&1]) ++ pairs
      assert length(sets) == 153

      for a_slots <- sets, b_slots <- Enum.take_every(sets, 5) do
        assert_operations_on_cycle(a_slots, b_slots, :day_hours)
      end
    end

    for {line, what} <- [
          day_hours: "hours of the day",
          weekdays: "days of the week",
          months: "months of the year",
          year_days: "days of the year"
        ] do
      property "generated sets of #{what}" do
        {points, _length} = cycle(unquote(line))

        check all(
                a_slots <- arcs_between(points),
                b_slots <- arcs_between(points),
                max_runs: 80
              ) do
          assert_operations_on_cycle(a_slots, b_slots, unquote(line))
        end
      end
    end
  end

  describe "a set with no year, on its cycle" do
    test "every set of up to two spans between five hours of the day" do
      hours = [0, 1, 12, 22, 23]
      arcs = for from <- hours, to <- hours, do: {from, to}

      pairs =
        for {first, index} <- Enum.with_index(arcs), second <- Enum.drop(arcs, index) do
          [first, second]
        end

      sets = [[]] ++ Enum.map(arcs, &[&1]) ++ pairs
      assert length(sets) == 351

      Enum.each(sets, &assert_cover_on_cycle(&1, :day_hours))
    end

    for {line, what} <- [
          day_hours: "hours of the day",
          weekdays: "days of the week",
          months: "months of the year",
          year_days: "days of the year"
        ] do
      property "generated sets of #{what}" do
        {points, _length} = cycle(unquote(line))

        check all(slots <- arcs_between(points), max_runs: 100) do
          assert_cover_on_cycle(slots, unquote(line))
        end
      end
    end
  end

  ## A point in a set

  describe "covered?/2" do
    # A member with no year may run through its cycle's end, and holds the
    # points either side of it. `covered?/2` asked the member whole, which
    # raised.
    for {line, what} <- [
          day_hours: "hours of the day",
          weekdays: "days of the week",
          months: "months of the year",
          year_days: "days of the year"
        ] do
      property "is whether an arc holds the point, of #{what}" do
        {points, _length} = cycle(unquote(line))

        check all(slots <- arcs_between(points), max_runs: 60) do
          set = set(slots, unquote(line), :a, [])

          for slot <- 0..(points - 1) do
            held? = Enum.any?(slots, &(slot in cells_round(&1, points)))

            assert IntervalSet.covered?(set, point(unquote(line), slot)) == held?,
                   "#{inspect(slots)} at #{slot} of #{unquote(line)}"
          end
        end
      end
    end

    property "is whether a member holds the whole of the point, on a list and on a tree" do
      check all(slots <- spans_on(:days, 8), backend <- member_of([:list, :tree]), max_runs: 60) do
        set = set(slots, :days, :a, backend: backend)

        for slot <- 0..7 do
          held? = Enum.any?(slots, fn {from, to} -> from <= slot and slot + 1 <= to end)

          assert IntervalSet.covered?(set, point(:days, slot)) == held?,
                 "#{inspect(slots)} at #{slot}"
        end
      end
    end
  end
end
