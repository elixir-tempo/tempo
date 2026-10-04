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

  A span of a value with no year that crosses its cycle's end is not here:
  it comes back in two, an open item of `TODO.md`.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Matrix.Extent
  alias Tempo.Matrix.Sets

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

  defp hour(slot), do: NaiveDateTime.add(~N[2026-06-01 00:00:00], slot, :hour)

  defp day_in(calendar, slot) do
    date = ~D[2026-06-01] |> Date.add(slot) |> Date.convert!(calendar)
    Tempo.from_iso8601!("#{date.year}Y#{date.month}M#{date.day}D", calendar)
  end

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

  defp stretches(spans),
    do: spans |> Enum.map(fn {from, to, _id} -> {from, to} end) |> Enum.uniq()

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

  # One set's own cover: merged, and counted by how many members cover it.
  # `covered/2` cuts a stretch where one member ends as another begins (an
  # open item of `TODO.md`), so the time it covers is compared.
  defp assert_cover(a, in_a, named) do
    assert stretches(read(IntervalSet.coalesce(a))) == Sets.cover(in_a), "coalesce of #{named}"

    for at_least <- 1..3 do
      {:ok, regions} = IntervalSet.covered(a, at_least: at_least)

      assert Sets.cover(read(regions)) == Sets.covered(in_a, at_least),
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

  describe "the answers the operations are held to" do
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

  ## A point in a set

  describe "covered?/2" do
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
