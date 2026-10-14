defmodule Tempo.RecurrenceSetTest do
  use ExUnit.Case, async: true

  # A recurrence set: rules whose occurrences form one set, a territory's
  # holidays. The cases the `tempo_holidays` work added: occurrences in time
  # order with each member's metadata, domains and plain values as members,
  # bridge days kept only between holidays, holidays moved off others, and a
  # diary held against a set to find the clashes.

  import Tempo.Sigils

  alias Tempo.{Interval, IntervalSet, RecurrenceSet}

  defp named(text, name), do: Tempo.put_metadata(Tempo.from_iso8601!(text), %{name: name})
  defp typed(text, type), do: Tempo.put_metadata(Tempo.from_iso8601!(text), %{type: type})

  defp days({:ok, set}), do: days(set)
  defp days(set), do: IntervalSet.map(set, &Tempo.to_iso8601!(Interval.from(&1)))

  defp years({:ok, set}),
    do: set |> IntervalSet.map(&Tempo.year(Interval.from(&1))) |> Enum.sort()

  describe "a set's occurrences" do
    test "are its members' occurrences, in time order" do
      holidays =
        RecurrenceSet.new!([
          named("R/../P1Y/FL12M25DN", "Christmas"),
          named("R/../P1Y/FL1M1DN", "New Year")
        ])

      assert days(Tempo.to_interval(holidays, within: ~o"2026")) == ["2026Y1M1D", "2026Y12M25D"]
    end

    test "carry each member's metadata, and the set its own" do
      holidays =
        RecurrenceSet.new!([named("R/../P1Y/FL12M25DN", "Christmas")],
          metadata: %{territory: :AU}
        )

      {:ok, set} = Tempo.to_interval(holidays, within: ~o"2026")

      assert IntervalSet.map(set, &Tempo.metadata/1) == [%{name: "Christmas"}]
      assert Tempo.metadata(set) == %{territory: :AU}
    end

    test "of a member with a domain are those in the window, less what it takes out" do
      holidays =
        RecurrenceSet.new!([
          named("R/{2020Y..2049Y}/P1Y/FL11M1DN", "One-off"),
          named("R/../P1Y/FL12M25DN", "Christmas")
        ])

      assert years(Tempo.to_interval(holidays, within: ~o"2026")) == [2026, 2026]

      excluding = RecurrenceSet.new!([named("R/{2024Y..2027Y,^2026Y}/P1Y/FL12M25DN", "Xmas")])
      assert years(Tempo.to_interval(excluding)) == [2024, 2025, 2027]
    end

    test "of a value or an interval are its own span" do
      independence = Tempo.new!(year: 2026, month: 7, day: 4)
      {:ok, interval} = Tempo.to_interval(independence)

      for member <- [independence, interval] do
        holidays = RecurrenceSet.new!([member, named("R/../P1Y/FL12M25DN", "Christmas")])
        assert days(Tempo.to_interval(holidays, within: ~o"2026")) == ["2026Y7M4D", "2026Y12M25D"]
      end
    end

    test "of a nested set carry its metadata beneath their own" do
      # A holiday and the day it is observed when it falls on a weekend, as
      # one member carrying the holiday's name once.
      christmas =
        RecurrenceSet.new!(
          [
            Tempo.from_iso8601!("R/../P1Y/FL12M25DN"),
            Tempo.put_metadata(Tempo.from_iso8601!("R/../P1Y/FL12M28DN"), %{substitute: true})
          ],
          metadata: %{name: "Christmas Day", type: :public}
        )

      {:ok, set} =
        Tempo.to_interval(RecurrenceSet.new!([christmas], metadata: %{territory: :AU}),
          within: ~o"2026"
        )

      assert IntervalSet.map(set, &{Tempo.to_iso8601!(Interval.from(&1)), Tempo.metadata(&1)}) ==
               [
                 {"2026Y12M25D", %{name: "Christmas Day", type: :public}},
                 {"2026Y12M28D", %{name: "Christmas Day", type: :public, substitute: true}}
               ]

      nested =
        RecurrenceSet.new!([named("R/../P1Y/FL12M28DN", "Boxing Day (observed)")],
          metadata: %{name: "Boxing Day", type: :public}
        )

      {:ok, set} = Tempo.to_interval(RecurrenceSet.new!([nested]), within: ~o"2026")

      assert IntervalSet.map(set, &Tempo.metadata/1) == [
               %{name: "Boxing Day (observed)", type: :public}
             ]
    end
  end

  describe "a member kept between holidays" do
    # Japan's Citizens' Holiday: 22 September where the days either side are
    # public holidays, Respect for the Aged Day (the third Monday) and the
    # September equinox in Tokyo. They meet around it only in 2026 of 2020
    # to 2030.
    test "is kept only in the years both neighbours are holidays" do
      citizens_holiday =
        RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN",
          at: [~o"-P1D", ~o"P1D"],
          falls_on: %{type: :public},
          metadata: %{name: "Citizens' Holiday"}
        )

      holidays =
        RecurrenceSet.new!([
          typed("R/../P1Y/FL9M1K3IN", :public),
          typed("R/../P1Y/FL(september-equinox@+09:00)eN", :public),
          citizens_holiday
        ])

      {:ok, set} = Tempo.to_interval(holidays, within: ~o"2020/2030")

      citizens =
        set
        |> IntervalSet.filter(&(Tempo.metadata(&1)[:name] == "Citizens' Holiday"))
        |> days()

      assert citizens == ["2026Y9M22D"]
    end

    test "is not kept beside a neighbour of another type, or its own span" do
      bridge =
        RecurrenceSet.keep_when(~o"2026-09-22",
          at: [~o"-P1D", ~o"P1D"],
          falls_on: %{type: :public}
        )

      holidays =
        RecurrenceSet.new!([
          typed("2026-09-21", :public),
          typed("2026-09-23", :observance),
          bridge
        ])

      assert days(Tempo.to_interval(holidays)) == ["2026Y9M21D", "2026Y9M23D"]

      # The member runs from the 22nd to the 24th, so the day after its start is its own.
      own = RecurrenceSet.keep_when(~o"2026-09-22/P3D", at: [~o"-P1D", ~o"P1D"], falls_on: %{})

      assert days(Tempo.to_interval(RecurrenceSet.new!([typed("2026-09-21", :public), own]))) == [
               "2026Y9M21D"
             ]
    end

    test "is kept alike wherever the window ends about it" do
      bridge =
        RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN",
          at: [~o"-P1D", ~o"P1D"],
          falls_on: %{type: :public}
        )

      holidays =
        RecurrenceSet.new!([
          typed("R/../P1Y/FL9M21DN", :public),
          typed("R/../P1Y/FL9M23DN", :public),
          bridge
        ])

      for {window, expected} <- [
            {~o"2026", ["2026Y9M21D", "2026Y9M22D", "2026Y9M23D"]},
            {~o"2026-09-22/2026-12-31", ["2026Y9M22D", "2026Y9M23D"]},
            {~o"2026-01-01/2026-09-22", ["2026Y9M21D", "2026Y9M22D"]},
            {~o"2026-09-22/2026-09-22", ["2026Y9M22D"]},
            {~o"2026-09-23/2026-12-31", ["2026Y9M23D"]}
          ] do
        assert {window, days(Tempo.to_interval(holidays, within: window))} == {window, expected}
      end

      one_neighbour = RecurrenceSet.new!([typed("R/../P1Y/FL9M21DN", :public), bridge])

      for window <- [~o"2026", ~o"2026-09-22/2026-12-31", ~o"2026-09-22/2026-09-22"] do
        refute "2026Y9M22D" in days(Tempo.to_interval(one_neighbour, within: window))
      end
    end

    test "reads a set of its own, which is not given" do
      neighbours =
        RecurrenceSet.new!([
          typed("R/../P1Y/FL9M21DN", :public),
          typed("R/../P1Y/FL9M23DN", :public)
        ])

      bridge =
        RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN",
          at: [~o"-P1D", ~o"P1D"],
          falls_on: neighbours
        )

      assert days(
               Tempo.to_interval(RecurrenceSet.new!([bridge]), within: ~o"2026-09-22/2026-09-22")
             ) ==
               ["2026Y9M22D"]
    end
  end

  describe "a member moved off another" do
    # 9 April 2026 is a Thursday, so the next Thursday is a week on.
    test "moves to the next selected day, strictly after" do
      moved =
        RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{type: :observance}, to_next: ~o"4K")

      holidays = RecurrenceSet.new!([typed("2026-04-09", :observance), moved])
      assert days(Tempo.to_interval(holidays)) == ["2026Y4M9D", "2026Y4M16D"]
    end

    test "stays where it falls on nothing it names" do
      stays =
        RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{type: :observance}, to_next: ~o"4K")

      holidays = RecurrenceSet.new!([typed("2026-04-09", :public), stays])
      assert days(Tempo.to_interval(holidays)) == ["2026Y4M9D", "2026Y4M9D"]
    end

    test "is read by the others where it was, never where it moved" do
      moved =
        RecurrenceSet.move_when(Tempo.put_metadata(~o"2026-04-09", %{type: :public}),
          falls_on: %{type: :observance},
          to_next: ~o"4K"
        )

      after_the_move =
        RecurrenceSet.keep_when(~o"2026-04-17", at: [~o"-P1D"], falls_on: %{type: :public})

      after_the_original =
        RecurrenceSet.keep_when(~o"2026-04-10", at: [~o"-P1D"], falls_on: %{type: :public})

      holidays =
        RecurrenceSet.new!([
          typed("2026-04-09", :observance),
          moved,
          after_the_move,
          after_the_original
        ])

      assert days(Tempo.to_interval(holidays)) == ["2026Y4M9D", "2026Y4M10D", "2026Y4M16D"]
    end

    test "is kept where it moves into the window, and not where it moves out" do
      moved =
        RecurrenceSet.move_when(~o"R/../P1Y/FL4M9DN",
          falls_on: %{type: :observance},
          to_next: ~o"4K"
        )

      holidays = RecurrenceSet.new!([typed("R/../P1Y/FL4M9DN", :observance), moved])

      assert days(Tempo.to_interval(holidays, within: ~o"2026-04-16/2026-04-30")) == [
               "2026Y4M16D"
             ]

      assert days(Tempo.to_interval(holidays, within: ~o"2026-04-01/2026-04-12")) == ["2026Y4M9D"]
    end

    test "carries its metadata and its member's" do
      moved =
        RecurrenceSet.move_when(Tempo.put_metadata(~o"2026-04-09", %{type: :public}),
          falls_on: %{type: :observance},
          to_next: ~o"4K",
          metadata: %{name: "Näfelser Fahrt"}
        )

      {:ok, set} =
        Tempo.to_interval(RecurrenceSet.new!([typed("2026-04-09", :observance), moved]))

      assert [_observance, moved_occurrence] = IntervalSet.members(set)
      assert Tempo.metadata(moved_occurrence) == %{name: "Näfelser Fahrt", type: :public}
    end

    test "in a nested set reads that set's other members, or a set it is given" do
      moved =
        RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{type: :observance}, to_next: ~o"4K")

      holidays =
        RecurrenceSet.new!([typed("2026-04-09", :observance), RecurrenceSet.new!([moved])])

      assert days(Tempo.to_interval(holidays)) == ["2026Y4M9D", "2026Y4M9D"]

      observances = RecurrenceSet.new!([typed("2026-04-09", :observance)])
      given = RecurrenceSet.move_when(~o"2026-04-09", falls_on: observances, to_next: ~o"4K")
      assert days(Tempo.to_interval(RecurrenceSet.new!([given]))) == ["2026Y4M16D"]
    end
  end

  describe "a diary held against a set" do
    test "clashes where an appointment is a holiday, with no window" do
      {:ok, diary} =
        IntervalSet.new([
          Tempo.new!(year: 2026, month: 1, day: 1),
          Tempo.new!(year: 2026, month: 6, day: 15),
          Tempo.new!(year: 2026, month: 12, day: 25)
        ])

      holidays =
        RecurrenceSet.new!([
          named("R/../P1Y/FL12M25DN", "Christmas"),
          named("R/../P1Y/FL1M1DN", "New Year")
        ])

      {:ok, clashes} = Tempo.intersection(diary, holidays)
      assert days(clashes) == ["2026Y1M1D", "2026Y12M25D"]

      {:ok, named_clashes} = Tempo.intersection(holidays, diary)

      assert IntervalSet.map(named_clashes, &Tempo.metadata(&1)[:name]) == [
               "New Year",
               "Christmas"
             ]
    end
  end

  describe "filter/2" do
    test "keeps the members the function keeps, in order, with the set's metadata" do
      christmas =
        Tempo.put_metadata(Tempo.every!(~o"P1Y", select: [month: 12, day: 25]), %{
          name: "Christmas Day"
        })

      boxing_day =
        Tempo.put_metadata(Tempo.every!(~o"P1Y", select: [month: 12, day: 26]), %{
          name: "Boxing Day"
        })

      new_year =
        Tempo.put_metadata(Tempo.every!(~o"P1Y", select: [month: 1, day: 1]), %{
          name: "New Year's Day"
        })

      holidays =
        RecurrenceSet.new!([christmas, boxing_day, new_year], metadata: %{territory: :GB})

      kept = RecurrenceSet.filter(holidays, &(Tempo.metadata(&1).name != "Boxing Day"))

      assert RecurrenceSet.members(kept) == [christmas, new_year]
      assert Tempo.metadata(kept) == %{territory: :GB}
      assert RecurrenceSet.members(RecurrenceSet.filter(holidays, fn _member -> false end)) == []
    end

    test "a conditional member is given to the function as it is" do
      bridge =
        RecurrenceSet.keep_when(Tempo.every!(~o"P1Y", select: [month: 9, day: 22]),
          at: [~o"-P1D"],
          falls_on: %{type: :public}
        )

      holidays = RecurrenceSet.new!([Tempo.every!(~o"P1Y", select: [month: 9, day: 21]), bridge])
      conditionals = RecurrenceSet.filter(holidays, &(&1 == bridge))

      assert RecurrenceSet.members(conditionals) == [bridge]
    end
  end

  describe "a set of rules with no start beside rules with a domain" do
    # A territory's holidays: most every year, one in 2022 only. Asked of a
    # day, the rules with no start take the frame of the day.
    test "is asked of a day as one set" do
      holidays =
        RecurrenceSet.new!([
          RecurrenceSet.new!([
            Tempo.every!(~o"P1Y", select: [month: 1, day: 1]),
            Tempo.every!(~o"P1Y", select: [month: 1, day: 2])
          ]),
          Tempo.every!(~o"P1Y",
            from: IntervalSet.new!([Tempo.new!(year: 2022)]),
            select: [month: 9, day: 22]
          ),
          Tempo.every!(~o"P1Y", select: [month: 4, day: 25])
        ])

      for {day, holiday?} <- [
            {~o"2019-01-28", false},
            {~o"2019-01-01", true},
            {~o"2022-09-22", true},
            {~o"2023-09-22", false},
            {~o"2019-04-25", true}
          ] do
        assert Tempo.overlaps?(day, holidays, within: day) == holiday?, inspect(day)
      end
    end
  end
end
