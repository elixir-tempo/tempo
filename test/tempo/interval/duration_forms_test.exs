defmodule Tempo.Interval.DurationFormsTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.MaterialisationError

  # One bounded interval written three ways — both endpoints, a start and a
  # duration, a duration and an end — against the span that follows it. Every
  # function that reads one interval gives the same answer for each spelling.
  @spellings [
    day:
      {[~o"2026-01-01/2026-01-02", ~o"2026-01-01/P1D", ~o"P1D/2026-01-02"], ~o"2026-01-02/P1D"},
    hour:
      {[~o"2026-01-01T10/2026-01-01T11", ~o"2026-01-01T10/PT1H", ~o"PT1H/2026-01-01T11"],
       ~o"2026-01-01T10:30/PT1H"},
    zoned:
      {[
         ~o"2026-01-01T10:00:00Z/2026-01-01T11:00:00Z",
         ~o"2026-01-01T10:00:00Z/PT1H",
         ~o"PT1H/2026-01-01T11:00:00Z"
       ], ~o"2026-01-01T09:00:00Z/PT3H"},
    year: {[~o"2026/2027", ~o"2026/P1Y", ~o"P1Y/2027"], ~o"2026-06/P1M"}
  ]

  @pair_functions [
    :relation,
    :before?,
    :after?,
    :meets?,
    :during?,
    :within?,
    :adjacent?,
    :possibly_before?,
    :possibly_after?,
    :possibly_overlaps?,
    :possibly_within?,
    :certainly_before?,
    :certainly_after?,
    :certainly_overlaps?,
    :certainly_within?
  ]

  @duration_functions [:at_least?, :at_most?, :exactly?, :longer_than?, :shorter_than?]

  for {label, {[explicit | _] = spellings, other}} <- @spellings do
    describe "#{label}: every spelling answers as the explicit form" do
      @spelled spellings
      @explicit explicit
      @other other

      test "relation predicates, the spelling on either side" do
        for function <- @pair_functions, spelling <- @spelled do
          assert apply(Interval, function, [spelling, @other]) ==
                   apply(Interval, function, [@explicit, @other]),
                 "#{function}(#{inspect(spelling)}, other)"

          assert apply(Interval, function, [@other, spelling]) ==
                   apply(Interval, function, [@other, @explicit]),
                 "#{function}(other, #{inspect(spelling)})"
        end
      end

      test "duration predicates" do
        length = Interval.duration(@explicit)

        for function <- @duration_functions, spelling <- @spelled do
          assert apply(Interval, function, [spelling, length]) ==
                   apply(Interval, function, [@explicit, length]),
                 "#{function}(#{inspect(spelling)}, #{inspect(length)})"
        end
      end

      test "endpoints, duration and boundedness" do
        for spelling <- @spelled do
          assert Interval.endpoints(spelling) == Interval.endpoints(@explicit)
          assert Interval.from(spelling) == Interval.from(@explicit)
          assert Interval.to(spelling) == Interval.to(@explicit)
          assert Interval.duration(spelling) == Interval.duration(@explicit)
          assert Interval.bounded?(spelling)
        end
      end

      test "an interval set member" do
        {:ok, expected} = IntervalSet.new([@explicit])

        for spelling <- @spelled do
          {:ok, set} = IntervalSet.new([spelling])

          assert IntervalSet.to_list(set) |> Enum.map(&Interval.endpoints/1) ==
                   IntervalSet.to_list(expected) |> Enum.map(&Interval.endpoints/1)
        end
      end
    end
  end

  describe "the answers themselves" do
    test "a start and a duration meets the next day" do
      assert Tempo.relation(~o"2026-01-01/P1D", ~o"2026-01-02/P1D") == :meets
      assert Tempo.meets?(~o"2026-01-01/P1D", ~o"2026-01-02/P1D")
    end

    test "a duration and an end is exactly its duration long, not open-ended" do
      assert Tempo.duration(~o"P1D/2026-01-02") == ~o"PT86400S"
      assert Tempo.exactly?(~o"P1D/2026-01-02", ~o"P1D")
      refute Tempo.longer_than?(~o"P1D/2026-01-02", ~o"P1D")
      assert Interval.from(~o"P1D/2026-01-02") == ~o"2026-01-01"
    end

    test "a month from the 31st of January ends on the 28th of February" do
      assert Interval.endpoints(~o"2026-01-31/P1M") == {~o"2026-01-31", ~o"2026-02-28"}
    end
  end

  describe "what resolution leaves alone" do
    test "a resolved member keeps its metadata and unit" do
      interval =
        Interval.new!(
          from: ~o"2026-12-25",
          duration: ~o"P1D",
          unit: :hour,
          metadata: %{name: "Christmas Day"}
        )

      {:ok, set} = IntervalSet.new([interval])
      [member] = IntervalSet.to_list(set)

      assert Interval.endpoints(member) == {~o"2026-12-25", ~o"2026-12-26"}
      assert Interval.metadata(member) == %{name: "Christmas Day"}
      assert member.unit == :hour
    end

    test "a recurrence is still refused as a single interval" do
      assert {:error, %MaterialisationError{reason: :recurring_interval}} =
               Tempo.relation(~o"R3/2026-01-01/P1D", ~o"2026-01-02")
    end

    test "an open interval stays unbounded" do
      refute Interval.bounded?(~o"2026-01-01/..")
      assert Interval.duration(~o"2026-01-01/..") == :infinity
      assert Interval.from(~o"../2026-01-02") == :undefined
    end
  end
end
