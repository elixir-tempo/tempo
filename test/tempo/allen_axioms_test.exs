defmodule Tempo.AllenAxiomsTest do
  use ExUnit.Case, async: true

  # What `allen_test.exs` leaves out of Allen's algebra: that the
  # composition table is sound (the relation of the first span to the third
  # is one the table gives for the two between), and, over spans built
  # through the API, the axioms of Allen and Hayes (1987) that Grüninger and
  # Li (TIME 2017) number 14 and 15: meeting is one way, and spans that meet
  # in a chain are one span. The spans are of hours and of microseconds,
  # whose written ends are boundaries (law 9), so two meet where one ends as
  # the next begins.

  alias Tempo.Allen
  alias Tempo.{Interval, IntervalSet}

  @spans for from <- 0..5, to <- (from + 1)..6, do: {from, to}

  test "the composition table gives the relation of the first of three spans to the third" do
    for a <- @spans, b <- @spans, c <- @spans do
      composed = Allen.compose(Allen.relation(a, b), Allen.relation(b, c))

      assert Allen.relation(a, c) in composed,
             "#{inspect(a)} #{inspect(b)} #{inspect(c)}: #{Allen.relation(a, c)} is not in #{inspect(composed)}"
    end
  end

  test "every relation the composition table gives is one some three spans have" do
    held =
      for a <- @spans, b <- @spans, c <- @spans, reduce: %{} do
        seen ->
          key = {Allen.relation(a, b), Allen.relation(b, c)}

          Map.update(
            seen,
            key,
            MapSet.new([Allen.relation(a, c)]),
            &MapSet.put(&1, Allen.relation(a, c))
          )
      end

    for first <- Allen.relations(), second <- Allen.relations() do
      assert MapSet.new(Allen.compose(first, second)) == Map.fetch!(held, {first, second}),
             "#{first} then #{second}"
    end
  end

  describe "spans of hours" do
    defp hour(n), do: Tempo.new!(year: 2026, month: 6, day: 15, hour: n)
    defp hours(from, to), do: Interval.new!(from: hour(from), to: hour(to))

    @hour_spans for from <- 0..5, to <- (from + 1)..6, do: {from, to}

    test "have the relation their ends give, and its inverse the other way" do
      for {a_from, a_to} = a <- @hour_spans, {b_from, b_to} = b <- @hour_spans do
        relation = Tempo.relation(hours(a_from, a_to), hours(b_from, b_to))

        assert relation == Allen.relation(a, b)
        assert Tempo.relation(hours(b_from, b_to), hours(a_from, a_to)) == Allen.inverse(relation)
      end
    end

    test "meet one way: what meets is met by, and does not meet back" do
      assert Tempo.relation(hours(9, 10), hours(10, 12)) == :meets
      assert Tempo.relation(hours(10, 12), hours(9, 10)) == :met_by
    end

    test "that meet in a chain are one span" do
      chain = [hours(9, 10), hours(10, 12), hours(12, 13), hours(13, 17)]

      for [earlier, later] <- Enum.chunk_every(chain, 2, 1, :discard) do
        assert Tempo.relation(earlier, later) == :meets
      end

      {:ok, set} = IntervalSet.new(chain)
      {:ok, one} = IntervalSet.coalesce(set)

      assert IntervalSet.count(one) == 1
      assert Tempo.equal?(one, hours(9, 17))
    end
  end

  describe "spans of microseconds" do
    defp instant(microseconds) do
      Tempo.new!(
        year: 2026,
        month: 6,
        day: 15,
        hour: 10,
        minute: 30,
        second: div(microseconds, 1_000_000),
        microsecond: {rem(microseconds, 1_000_000), 6}
      )
    end

    defp instants(from, to), do: Interval.new!(from: instant(from), to: instant(to))

    # Ends a microsecond apart, a second apart and most of a minute apart.
    @instants [0, 1, 2, 999_999, 1_000_000, 1_000_001, 59_999_998, 59_999_999]
    @instant_spans for from <- @instants, to <- @instants, from < to, do: {from, to}

    test "have the relation their ends give, to the microsecond" do
      for {a_from, a_to} = a <- @instant_spans, {b_from, b_to} = b <- @instant_spans do
        assert Tempo.relation(instants(a_from, a_to), instants(b_from, b_to)) ==
                 Allen.relation(a, b)
      end
    end
  end
end
