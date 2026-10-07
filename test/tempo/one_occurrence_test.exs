defmodule Tempo.OneOccurrenceTest do
  @moduledoc """
  A recurrence of one occurrence that has a rule.

  Its occurrence is the first its rule selects, and a `:within` window keeps
  it or does not, as it does the occurrences of a longer rule (decided
  2026-10-08). The occurrence was given whatever the window was:
  `FREQ=DAILY;BYDAY=SU;COUNT=1` from 2019 within 2026 was a Sunday of 2019,
  where `COUNT=2` was nothing.

  A rule of one occurrence was a recurrence only where it was written with
  a start and a duration. With no start, with a start and an end, and with a
  start that has no year it was handed back as it was given, or refused,
  and `Enum` walked the span from its start. A rule with no start and a
  count of two or more was counted afresh in each stretch of an open-ended
  window.

  The measure is Elixir's own `Date`: the first Sunday on or after a day,
  and whether it is a day of the window.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet
  alias Tempo.RRule

  ## The measure

  # The first Sunday on or after a day.
  defp sunday_from(%Date{} = day),
    do: Enum.find(Date.range(day, Date.add(day, 6)), &(Date.day_of_week(&1) == 7))

  # The day as the span `Tempo.to_interval/2` gives an occurrence of a day.
  defp day_span(%Date{} = day) do
    {:ok, span} = Interval.new(from: Tempo.from_date(day), to: Tempo.from_date(Date.add(day, 1)))
    span
  end

  # The spans a conversion gives, whichever of an interval and a set it is.
  defp spans({:ok, %Interval{} = one}), do: [one]
  defp spans({:ok, %IntervalSet{} = set}), do: IntervalSet.members(set)

  defp read(text), do: Tempo.from_iso8601!(text)

  # The Sundays from 1 January 2019, one of them and two.
  @one "R1/2019-01-01/P1D/FL7KN"
  @two "R2/2019-01-01/P1D/FL7KN"

  describe "the one occurrence of a rule, and a window" do
    # A window, and the days of it by which a day is in it or is not.
    @windows [
      {"2019", ~D[2019-01-01], ~D[2019-12-31]},
      {"2026", ~D[2026-01-01], ~D[2026-12-31]},
      {"2019-01", ~D[2019-01-01], ~D[2019-01-31]},
      {"2019-01-06", ~D[2019-01-06], ~D[2019-01-06]},
      {"2019-01-07", ~D[2019-01-07], ~D[2019-01-07]},
      {"2019-01-05", ~D[2019-01-05], ~D[2019-01-05]},
      {"2019-01-06T10", ~D[2019-01-06], ~D[2019-01-06]},
      {"2018-12-25/2019-01-06", ~D[2018-12-25], ~D[2019-01-05]},
      {"2019-01-06/2019-01-08", ~D[2019-01-06], ~D[2019-01-07]}
    ]

    test "is kept where it is a day of the window, and is the empty set where it is not" do
      sunday = sunday_from(~D[2019-01-01])
      assert sunday == ~D[2019-01-06]

      for {window, first, last} <- @windows do
        expected = if sunday in Date.range(first, last), do: [day_span(sunday)], else: []

        assert {window, spans(Tempo.to_interval(read(@one), within: read(window)))} ==
                 {window, expected}
      end
    end

    test "is one interval where it is kept, and with no window" do
      assert Tempo.to_interval(read(@one)) == {:ok, day_span(~D[2019-01-06])}
      assert Tempo.to_interval(read(@one), within: ~o"2019") == {:ok, day_span(~D[2019-01-06])}
      assert Tempo.to_interval(read(@one), within: ~o"2026") == IntervalSet.new([])
    end

    test "is kept or not by a window with no end" do
      assert spans(Tempo.to_interval(read(@one), within: read("2019-01-01/.."))) ==
               [day_span(~D[2019-01-06])]

      assert spans(Tempo.to_interval(read(@one), within: read("2019-01-07/.."))) == []
    end

    test "is what an RRULE with a count of one gives" do
      {:ok, rule} = RRule.parse("FREQ=DAILY;BYDAY=SU;COUNT=1", from: ~o"2019-01-01")

      assert Tempo.to_interval(rule, within: ~o"2026") == IntervalSet.new([])
      assert spans(Tempo.to_interval(rule, within: ~o"2019")) == [day_span(~D[2019-01-06])]
    end

    test "is refused with a window that is no window, as a longer rule's are" do
      assert {:error, refusal} = Tempo.to_interval(read(@two), within: :nonsense)
      assert Tempo.to_interval(read(@one), within: :nonsense) == {:error, refusal}
    end

    test "is the first of the occurrences of the same rule with two" do
      for window <- ["2019", "2026", "2019-01-06", "2019-01-13", "2019-01-01/.."] do
        {:ok, [first | _rest]} =
          with {:ok, both} <- Tempo.to_interval(read(@two)), do: {:ok, IntervalSet.members(both)}

        {:ok, kept} = Tempo.to_interval(read(@two), within: read(window))

        expected = Enum.filter(IntervalSet.members(kept), &(&1 == first))

        assert {window, spans(Tempo.to_interval(read(@one), within: read(window)))} ==
                 {window, expected}
      end
    end
  end

  describe "a recurrence of one occurrence that has no rule" do
    test "is the interval it is, whatever the window, as an interval is" do
      for text <- ["R1/2019-01-01/P1D", "2019-01-01/P1D", "R1/2019-01-01/2019-01-02"] do
        assert {text, Tempo.to_interval(read(text), within: ~o"2026")} ==
                 {text, {:ok, day_span(~D[2019-01-01])}}
      end
    end

    test "is on its cycle where its start has no year" do
      assert Tempo.to_interval(read("R1/T10/PT1H"), within: ~o"2026-01") ==
               Tempo.to_interval(read("T10/T11"))
    end
  end

  describe "the one occurrence of a rule written with a start and an end" do
    test "is the first its rule selects, as one written with a duration is" do
      with_ends = "R1/2019-01-01/2019-01-02/FL7KN"

      assert Tempo.to_interval(read(with_ends)) == {:ok, day_span(~D[2019-01-06])}
      assert Tempo.to_interval(read(with_ends), within: ~o"2026") == IntervalSet.new([])
    end
  end

  describe "the one occurrence of a rule with no start" do
    test "is the first its rule selects from where the window starts" do
      for {window, starts} <- [
            {"2026", ~D[2026-01-01]},
            {"2026-06-15/2026-07-15", ~D[2026-06-15]},
            {"2026-01-01/..", ~D[2026-01-01]},
            {"2026-06-21", ~D[2026-06-21]}
          ] do
        assert {window, spans(Tempo.to_interval(read("R1/../P1D/FL7KN"), within: read(window)))} ==
                 {window, [day_span(sunday_from(starts))]}
      end

      {:ok, rule} = RRule.parse("FREQ=DAILY;BYDAY=SU;COUNT=1")
      assert spans(Tempo.to_interval(rule, within: ~o"2026")) == [day_span(~D[2026-01-04])]
    end

    test "is the day the window starts on where it has no rule" do
      assert Tempo.to_interval(read("R1/../P1D"), within: ~o"2026") ==
               {:ok, day_span(~D[2026-01-01])}

      {:ok, rule} = RRule.parse("FREQ=DAILY;COUNT=1")

      assert Tempo.to_interval(rule, within: read("2026-06-15/..")) ==
               {:ok, day_span(~D[2026-06-15])}
    end

    test "has no start to count from with no window, and says so" do
      for text <- ["R1/../P1D/FL7KN", "R1/../P1D", "R2/../P1D/FL7KN"] do
        assert {^text, {:error, %IntervalEndpointsError{reason: :open_start}}} =
                 {text, Tempo.to_interval(read(text))}
      end
    end
  end

  describe "a rule with a count and no start, in a window with no end" do
    test "has as many occurrences from the window's start as it counts" do
      first = sunday_from(~D[2026-01-01])

      for {count, text} <- [{2, "R2/../P1D/FL7KN"}, {5, "R5/../P1D/FL7KN"}] do
        {:ok, %IntervalSet{} = counted} =
          Tempo.to_interval(read(text), within: read("2026-01-01/.."))

        assert {text, IntervalSet.members(counted)} ==
                 {text, for(week <- 0..(count - 1), do: day_span(Date.add(first, 7 * week)))}
      end

      {:ok, days} = Tempo.to_interval(read("R2/../P1D"), within: read("2026-01-01/.."))
      assert IntervalSet.members(days) == [day_span(~D[2026-01-01]), day_span(~D[2026-01-02])]
    end

    test "is walked without end where it has no count, as it was" do
      {:ok, every_sunday} =
        Tempo.to_interval(read("R/../P1D/FL7KN"), within: read("2026-01-01/.."))

      assert Enum.take(every_sunday, 3) == [~o"2026-01-04", ~o"2026-01-11", ~o"2026-01-18"]
    end
  end

  describe "the one occurrence of a rule whose start has no year" do
    test "is placed on the window, as a longer rule's start is" do
      {:ok, two} = Tempo.to_interval(read("R2/T10/PT1H/FL7KN"), within: ~o"2026-01")
      [first, _second] = IntervalSet.members(two)

      # The first hour of the first Sunday of the window.
      assert first == Tempo.from_iso8601!("2026-01-04T00/2026-01-04T01")
      assert Tempo.to_interval(read("R1/T10/PT1H/FL7KN"), within: ~o"2026-01") == {:ok, first}
    end
  end

  describe "the one occurrence of a rule from each value of a start" do
    test "is kept to the window, each as from one start" do
      text = "R1/2019Y1M{1,15}D/P1D/FL7KN"
      sundays = [sunday_from(~D[2019-01-01]), sunday_from(~D[2019-01-15])]
      assert sundays == [~D[2019-01-06], ~D[2019-01-20]]

      assert spans(Tempo.to_interval(read(text))) == Enum.map(sundays, &day_span/1)
      assert spans(Tempo.to_interval(read(text), within: ~o"2026")) == []

      assert spans(Tempo.to_interval(read(text), within: ~o"2019-01-20")) == [
               day_span(~D[2019-01-20])
             ]
    end
  end

  describe "the walk of one occurrence that has a rule" do
    test "is the occurrence its rule selects, and not the span from its start" do
      assert Enum.to_list(read(@one)) == [~o"2019-01-06"]
      assert Enum.to_list(read(@two)) == [~o"2019-01-06", ~o"2019-01-13"]

      assert Enum.count(read(@one)) == 1
      assert Enum.at(read(@one), 0) == ~o"2019-01-06"
      assert Enum.member?(read(@one), ~o"2019-01-06")
      refute Enum.member?(read(@one), ~o"2019-01-01")

      # A week from its start, kept by its Sunday.
      assert Enum.to_list(read("R1/2019-01-01/P1W/FL7KN")) == [~o"2019-01-06"]
    end

    test "is the span from its start where it has no rule, as it was" do
      assert Enum.to_list(read("R1/2019-01-01/P1D")) == [~o"2019-01-01"]
    end

    test "raises the error of a rule that selects nothing" do
      assert_raise IntervalEndpointsError, fn ->
        Enum.to_list(read("R1/2019-02-01/P1Y/FL2M30DN"))
      end
    end
  end

  describe "the set of one occurrence" do
    test "holds it or is empty" do
      assert {:ok, %IntervalSet{} = held} = Tempo.to_interval_set(read(@one), within: ~o"2019")
      assert IntervalSet.members(held) == [day_span(~D[2019-01-06])]

      assert Tempo.to_interval_set(read(@one), within: ~o"2026") == IntervalSet.new([])
    end
  end
end
