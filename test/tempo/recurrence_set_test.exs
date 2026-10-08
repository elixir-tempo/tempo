defmodule Tempo.RecurrenceSetTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet

  doctest Tempo.RecurrenceSet

  defp named(iso, name), do: %{Tempo.from_iso8601!(iso) | metadata: %{name: name}}

  defp isos(set),
    do: set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!(Interval.from(&1)))

  defp years(set),
    do:
      set
      |> IntervalSet.members()
      |> Enum.map(&(&1 |> Interval.from() |> Tempo.year()))
      |> Enum.sort()

  describe "materialisation" do
    test "materialises each member against a bound and unions" do
      rset =
        RecurrenceSet.new!([
          named("R/../P1Y/FL12M25DN", "Christmas"),
          named("R/../P1Y/FL1M1DN", "New Year")
        ])

      {:ok, set} = Tempo.to_interval_set(rset, within: ~o"2026Y")
      assert isos(set) == ["2026Y1M1D", "2026Y12M25D"]
    end

    test "propagates each member's metadata onto its occurrences" do
      rset = RecurrenceSet.new!([named("R/../P1Y/FL12M25DN", "Christmas")])
      {:ok, set} = Tempo.to_interval_set(rset, within: ~o"2026Y")

      assert [interval] = IntervalSet.members(set)
      assert Interval.metadata(interval)[:name] == "Christmas"
    end

    test "a member's span directive shapes its occurrences but is not copied onto them" do
      # A three-day holiday: the member carries its span as `:occurrence_duration`.
      member = %{
        Tempo.from_iso8601!("R/../P1Y/FL12M24DN")
        | metadata: %{name: "Christmas break", occurrence_duration: ~o"P3D"}
      }

      {:ok, set} = Tempo.to_interval_set(RecurrenceSet.new!([member]), within: ~o"2026Y")
      assert [interval] = IntervalSet.members(set)
      assert Tempo.to_iso8601!(interval) == "2026Y12M24D/27D"
      assert Interval.metadata(interval) == %{name: "Christmas break"}
    end

    test "a member with a domain is narrowed to the bound, not materialised whole" do
      rset =
        RecurrenceSet.new!([
          named("R/{2020Y..2049Y}/P1Y/FL11M1DN", "One-off"),
          named("R/../P1Y/FL12M25DN", "Christmas")
        ])

      {:ok, set} = Tempo.to_interval_set(rset, within: ~o"2026Y")
      assert years(set) == [2026, 2026]
    end

    test "a member with a ^ domain drops the excluded year" do
      rset = RecurrenceSet.new!([named("R/{2024Y..2027Y,^2026Y}/P1Y/FL12M25DN", "Xmas")])
      {:ok, set} = Tempo.to_interval_set(rset)
      assert years(set) == [2024, 2025, 2027]
    end

    test "a concrete-interval member passes through" do
      rset =
        RecurrenceSet.new!([
          Tempo.to_interval!(~o"2026Y7M4D"),
          named("R/../P1Y/FL12M25DN", "Christmas")
        ])

      {:ok, set} = Tempo.to_interval_set(rset, within: ~o"2026Y")
      assert "2026Y7M4D" in isos(set)
      assert "2026Y12M25D" in isos(set)
    end

    test "a plain Tempo member stands for its own span" do
      rset = RecurrenceSet.new!([~o"2026Y7M4D", named("R/../P1Y/FL12M25DN", "Christmas")])

      {:ok, set} = Tempo.to_interval_set(rset, within: ~o"2026Y")
      assert isos(set) == ["2026Y7M4D", "2026Y12M25D"]
    end

    test "the set's own metadata is the materialised set's" do
      rset =
        RecurrenceSet.new!([named("R/../P1Y/FL12M25DN", "Christmas")],
          metadata: %{territory: :AU}
        )

      {:ok, set} = Tempo.to_interval_set(rset, within: ~o"2026Y")
      assert IntervalSet.metadata(set) == %{territory: :AU}
    end

    test "a nested set is one member whose metadata tags every occurrence it produces" do
      # A holiday and the day it is observed when it falls on a weekend, as one
      # member carrying the holiday's name once.
      christmas =
        RecurrenceSet.new!(
          [
            Tempo.from_iso8601!("R/../P1Y/FL12M25DN"),
            %{Tempo.from_iso8601!("R/../P1Y/FL12M28DN") | metadata: %{substitute: true}}
          ],
          metadata: %{name: "Christmas Day", type: :public}
        )

      {:ok, set} =
        Tempo.to_interval_set(RecurrenceSet.new!([christmas], metadata: %{territory: :AU}),
          within: ~o"2026Y"
        )

      assert set
             |> IntervalSet.members()
             |> Enum.map(&{Tempo.to_iso8601!(Interval.from(&1)), Interval.metadata(&1)}) == [
               {"2026Y12M25D", %{name: "Christmas Day", type: :public}},
               {"2026Y12M28D", %{name: "Christmas Day", type: :public, substitute: true}}
             ]

      assert IntervalSet.metadata(set) == %{territory: :AU}
    end

    test "an occurrence keeps its own key where it conflicts with a nested set's" do
      nested =
        RecurrenceSet.new!([named("R/../P1Y/FL12M28DN", "Boxing Day (observed)")],
          metadata: %{name: "Boxing Day", type: :public}
        )

      {:ok, set} = Tempo.to_interval_set(RecurrenceSet.new!([nested]), within: ~o"2026Y")

      assert [interval] = IntervalSet.members(set)
      assert Interval.metadata(interval) == %{name: "Boxing Day (observed)", type: :public}
    end

    test "a member that is not a Tempo value is an error from new/2, not a raise" do
      for members <- [
            [named("R/../P1Y/FL12M25DN", "Christmas"), :not_a_member],
            [nil],
            ["R/../P1Y/FL12M25DN"],
            [%{}],
            [RecurrenceSet.keep_when(:not_a_member, at: [~o"-P1D"], falls_on: %{})]
          ] do
        assert {:error, %Tempo.ConversionError{reason: :recurrence_set_member} = error} =
                 RecurrenceSet.new(members)

        assert Exception.message(error) =~ "as a Tempo.RecurrenceSet member"
      end
    end

    test "a set built without new/2 is checked when converted" do
      nested = %RecurrenceSet{members: [:not_a_member]}

      assert {:error, %Tempo.ConversionError{reason: :recurrence_set_member}} =
               Tempo.to_interval_set(RecurrenceSet.new!([nested]), within: ~o"2026Y")

      rset = %RecurrenceSet{members: [named("R/../P1Y/FL12M25DN", "Christmas"), :not_a_member]}

      assert {:error, %Tempo.ConversionError{reason: :recurrence_set_member}} =
               Tempo.to_interval_set(rset, within: ~o"2026Y")
    end

    test "members that are not a list, and options new/2 does not take, are errors" do
      christmas = named("R/../P1Y/FL12M25DN", "Christmas")

      for {members, options} <- [
            {christmas, []},
            {nil, []},
            {"members", []},
            {[christmas], metadata: [:territory]},
            {[christmas], metadata: nil},
            {[christmas], territory: :AU},
            {[christmas], [:metadata]},
            {[christmas], %{metadata: %{}}}
          ] do
        assert {:error, %ArgumentError{}} = RecurrenceSet.new(members, options)
      end
    end

    test "new!/2 raises the error new/2 returns" do
      assert_raise Tempo.ConversionError, ~r/as a Tempo.RecurrenceSet member/, fn ->
        RecurrenceSet.new!([:not_a_member])
      end

      assert_raise ArgumentError, ~r/takes one option, :metadata/, fn ->
        RecurrenceSet.new!([], metadata: nil)
      end
    end
  end

  describe "conditional members" do
    defp typed(iso, type), do: Tempo.put_metadata(Tempo.from_iso8601!(iso), %{type: type})

    defp days(set),
      do: set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!(Interval.from(&1)))

    # Japan's Citizens' Holiday: 22 September when the days either side are
    # public holidays — Respect for the Aged Day (the third Monday) and the
    # September equinox in Tokyo meet around it only in 2026 between 2020 and 2030.
    test "a bridge day is kept only in the years both neighbours are public holidays" do
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

      {:ok, set} = Tempo.to_interval_set(holidays, within: ~o"2020Y/2031Y")

      citizens =
        set
        |> IntervalSet.members()
        |> Enum.filter(&(Interval.metadata(&1)[:name] == "Citizens' Holiday"))
        |> Enum.map(&Tempo.to_iso8601!(Interval.from(&1)))

      assert citizens == ["2026Y9M22D"]
    end

    test "a neighbour of another type does not bridge" do
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

      {:ok, set} = Tempo.to_interval_set(holidays)
      assert days(set) == ["2026Y9M21D", "2026Y9M23D"]
    end

    test "an occurrence never falls on its own member's occurrences" do
      # The member spans the 22nd to the 24th, so the day after its start is its own.
      bridge = RecurrenceSet.keep_when(~o"2026-09-22/P3D", at: [~o"-P1D", ~o"P1D"], falls_on: %{})
      holidays = RecurrenceSet.new!([typed("2026-09-21", :public), bridge])

      {:ok, set} = Tempo.to_interval_set(holidays)
      assert days(set) == ["2026Y9M21D"]
    end

    test "an occurrence that falls on another moves to the next selected day, strictly after" do
      # 9 April 2026 is a Thursday, so the next Thursday is a week on.
      moved =
        RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{type: :observance}, to_next: ~o"4K")

      holidays = RecurrenceSet.new!([typed("2026-04-09", :observance), moved])

      {:ok, set} = Tempo.to_interval_set(holidays)
      assert days(set) == ["2026Y4M9D", "2026Y4M16D"]
    end

    test "an occurrence that falls on nothing it names stays" do
      stays =
        RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{type: :observance}, to_next: ~o"4K")

      holidays = RecurrenceSet.new!([typed("2026-04-09", :public), stays])

      {:ok, set} = Tempo.to_interval_set(holidays)
      assert days(set) == ["2026Y4M9D", "2026Y4M9D"]
    end

    test "conditions read the others' unmoved occurrences, never a moved one" do
      # The move takes the 9th to the 16th. A bridge reading the day before the
      # 17th does not see it there; one reading the day before the 10th sees the
      # occurrence where it started.
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

      {:ok, set} = Tempo.to_interval_set(holidays)
      assert days(set) == ["2026Y4M9D", "2026Y4M10D", "2026Y4M16D"]
    end

    test "a bridge on the bound's first day reads the day before it" do
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

      {:ok, set} = Tempo.to_interval_set(holidays, within: ~o"2026-09-22/2026-09-23")
      assert days(set) == ["2026Y9M22D"]
    end

    test "a bridge is kept alike wherever the bound ends about it" do
      # The conditions are read over the bound itself where none reads a day
      # outside it, and over a wider one where one does: the bridge is the
      # same day with both neighbours in the bound, with one outside it at
      # either end, and with both outside.
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

      for {bound, expected} <- [
            {~o"2026", ["2026Y9M21D", "2026Y9M22D", "2026Y9M23D"]},
            {~o"2026-09-22/2026-12-31", ["2026Y9M22D", "2026Y9M23D"]},
            {~o"2026-01-01/2026-09-23", ["2026Y9M21D", "2026Y9M22D"]},
            {~o"2026-09-22/2026-09-23", ["2026Y9M22D"]},
            {~o"2026-09-23/2026-12-31", ["2026Y9M23D"]}
          ] do
        {:ok, set} = Tempo.to_interval_set(holidays, within: bound)
        assert {bound, days(set)} == {bound, expected}
      end

      # With one neighbour no holiday the bridge is no day, in any bound.
      one_neighbour = RecurrenceSet.new!([typed("R/../P1Y/FL9M21DN", :public), bridge])

      for bound <- [~o"2026", ~o"2026-09-22/2026-12-31", ~o"2026-09-22/2026-09-23"] do
        {:ok, set} = Tempo.to_interval_set(one_neighbour, within: bound)
        refute "2026Y9M22D" in days(set)
      end
    end

    test "an occurrence moved into the bound from before it is kept, one moved out is not" do
      moved =
        RecurrenceSet.move_when(~o"R/../P1Y/FL4M9DN",
          falls_on: %{type: :observance},
          to_next: ~o"4K"
        )

      holidays = RecurrenceSet.new!([typed("R/../P1Y/FL4M9DN", :observance), moved])

      {:ok, into} = Tempo.to_interval_set(holidays, within: ~o"2026-04-16/2026-04-30")
      assert days(into) == ["2026Y4M16D"]

      {:ok, out_of} = Tempo.to_interval_set(holidays, within: ~o"2026-04-01/2026-04-12")
      assert days(out_of) == ["2026Y4M9D"]
    end

    test "a conditional's occurrences carry its metadata and its member's" do
      moved =
        RecurrenceSet.move_when(Tempo.put_metadata(~o"2026-04-09", %{type: :public}),
          falls_on: %{type: :observance},
          to_next: ~o"4K",
          metadata: %{name: "Näfelser Fahrt"}
        )

      {:ok, set} =
        Tempo.to_interval_set(RecurrenceSet.new!([typed("2026-04-09", :observance), moved]))

      assert [_observance, moved_occurrence] = IntervalSet.members(set)
      assert Interval.metadata(moved_occurrence) == %{name: "Näfelser Fahrt", type: :public}
    end

    test "a conditional in a nested set reads that set's other members" do
      moved =
        RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{type: :observance}, to_next: ~o"4K")

      nested = RecurrenceSet.new!([moved])
      holidays = RecurrenceSet.new!([typed("2026-04-09", :observance), nested])

      {:ok, set} = Tempo.to_interval_set(holidays)
      assert days(set) == ["2026Y4M9D", "2026Y4M9D"]
    end

    test "falls_on: a recurrence set reads that set's occurrences, which are not output" do
      # The observance the move depends on is not a member here — as when a set
      # selected by type leaves it out — so the conditional carries it.
      observances = RecurrenceSet.new!([typed("2026-04-09", :observance)])
      moved = RecurrenceSet.move_when(~o"2026-04-09", falls_on: observances, to_next: ~o"4K")

      {:ok, set} = Tempo.to_interval_set(RecurrenceSet.new!([moved]))
      assert days(set) == ["2026Y4M16D"]
    end

    test "falls_on: a recurrence set keeps a bridge, reading past the bound's edge" do
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

      {:ok, set} =
        Tempo.to_interval_set(RecurrenceSet.new!([bridge]), within: ~o"2026-09-22/2026-09-23")

      assert days(set) == ["2026Y9M22D"]
    end

    test "falls_on: another kind of struct is an error" do
      bad = RecurrenceSet.move_when(~o"2026-04-09", falls_on: ~o"2026-04-09", to_next: ~o"4K")

      assert {:error, %Tempo.ConversionError{reason: :conditional_member}} =
               RecurrenceSet.new([bad])

      assert {:error, %Tempo.ConversionError{reason: :conditional_member}} =
               Tempo.to_interval_set(%RecurrenceSet{members: [bad]})
    end

    test "a conditional without what it falls on, or with both :at and :to_next, is an error" do
      for conditional <- [
            RecurrenceSet.keep_when(~o"2026-04-09", at: [~o"-P1D"]),
            RecurrenceSet.keep_when(~o"2026-04-09", at: [], falls_on: %{}),
            RecurrenceSet.keep_when(~o"2026-04-09", at: [~o"2026Y"], falls_on: %{}),
            RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{}),
            %{
              RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{}, to_next: ~o"4K")
              | at: [~o"P1D"]
            }
          ] do
        assert {:error, %Tempo.ConversionError{reason: :conditional_member}} =
                 RecurrenceSet.new([conditional])

        assert {:error, %Tempo.ConversionError{reason: :conditional_member}} =
                 Tempo.to_interval_set(%RecurrenceSet{members: [conditional]})
      end
    end
  end

  describe "set algebra — the motivating query" do
    test "intersecting a diary with a recurrence set finds the clashes, no explicit bound" do
      {:ok, diary} =
        ["2026Y1M1D", "2026Y6M15D", "2026Y12M25D"]
        |> Enum.map(&Tempo.to_interval!(Tempo.from_iso8601!(&1)))
        |> IntervalSet.new()

      holidays =
        RecurrenceSet.new!([
          named("R/../P1Y/FL12M25DN", "Christmas"),
          named("R/../P1Y/FL1M1DN", "New Year")
        ])

      {:ok, clashes} = Tempo.intersection(diary, holidays)
      assert isos(clashes) == ["2026Y1M1D", "2026Y12M25D"]
    end

    test "a meeting during a holiday clashes with it, the holiday starting before the meeting" do
      {:ok, diary} = IntervalSet.new([Tempo.to_interval!(~o"2026-12-25T10/2026-12-25T11")])

      # A three-day break from the 24th reaches the meeting on the 25th too.
      break = %{
        Tempo.from_iso8601!("R/../P1Y/FL12M24DN")
        | metadata: %{name: "Christmas break", occurrence_duration: ~o"P3D"}
      }

      for holidays <- [
            RecurrenceSet.new!([named("R/../P1Y/FL12M25DN", "Christmas")]),
            RecurrenceSet.new!([break])
          ] do
        assert {:ok, clashes} = Tempo.intersection(diary, holidays)
        assert isos(clashes) == ["2026Y12M25DT10H"]
      end
    end

    test "with the recurrence set first, occurrences keep their names" do
      {:ok, diary} = IntervalSet.new([Tempo.to_interval!(~o"2026Y12M25D")])
      holidays = RecurrenceSet.new!([named("R/../P1Y/FL12M25DN", "Christmas")])

      {:ok, clashes} = Tempo.intersection(holidays, diary)
      assert [interval] = IntervalSet.members(clashes)
      assert Interval.metadata(interval)[:name] == "Christmas"
    end
  end

  describe "filter/2" do
    test "keeps the members the function keeps, in order, with the set's metadata" do
      christmas = Tempo.put_metadata(~o"R/../P1Y/FL12M25DN", %{name: "Christmas Day"})
      boxing_day = Tempo.put_metadata(~o"R/../P1Y/FL12M26DN", %{name: "Boxing Day"})
      new_year = Tempo.put_metadata(~o"R/../P1Y/FL1M1DN", %{name: "New Year's Day"})

      holidays =
        RecurrenceSet.new!([christmas, boxing_day, new_year], metadata: %{territory: :GB})

      kept = RecurrenceSet.filter(holidays, &(Tempo.metadata(&1).name != "Boxing Day"))

      assert RecurrenceSet.members(kept) == [christmas, new_year]
      assert RecurrenceSet.metadata(kept) == %{territory: :GB}
      assert RecurrenceSet.members(RecurrenceSet.filter(holidays, fn _member -> false end)) == []
    end

    test "a conditional member is given to the function as it is" do
      bridge =
        RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN", at: [~o"-P1D"], falls_on: %{type: :public})

      holidays = RecurrenceSet.new!([~o"R/../P1Y/FL9M21DN", bridge])

      conditionals = RecurrenceSet.filter(holidays, &match?(%RecurrenceSet.Conditional{}, &1))

      assert RecurrenceSet.members(conditionals) == [bridge]
    end
  end

  describe "the members beside a conditional" do
    # A set that holds a conditional converts every member over a window
    # widened by the condition's reach, and took each of the others a second
    # time over the window itself. One whose occurrences do not depend on
    # where its window starts is taken from the first pass; one that is
    # counted or placed from its window's start is converted in the window
    # still. Either way a member has the occurrences it has in a set with
    # no conditional.
    @windows [
      "2026Y",
      "2026-06-20/2026-12-20",
      "2026-12-31/2027-01-05",
      "2025Y/2028Y"
    ]

    @members [
      "R/../P1Y/FL12M25DN",
      "R/../P1M/FL15DN",
      "R/../P1W/FL1KN",
      "R/../P1Y/FL1WN",
      "R/../P1Y/FL(easter)eN",
      "R/../P1Y/FL1M1DL6KN/P-1DN",
      "R/2020-01-01/P1Y/FL7M4DN",
      "R3/2025-12-30/P1D",
      "R4/2026-12-29/2026-12-30",
      "R2/../P1Y/FL1M1DN",
      "R2/../P1M/FL15DN",
      "R1/../P1D/FL7KN",
      "2026Y7M4D",
      "2026-12-31/2027-01-02"
    ]

    test "have the occurrences they have with no conditional in the set" do
      never =
        RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN",
          at: [~o"-P1D", ~o"P1D"],
          falls_on: %{type: :no_member_is_of_this_type}
        )

      nested =
        RecurrenceSet.new!([named("R/../P1Y/FL5M1DN", "nested"), named("2026Y5M2D", "one")])

      members = Enum.map(@members, &named(&1, &1)) ++ [nested]

      for window <- @windows, member <- members do
        within = Tempo.from_iso8601!(window)

        {:ok, alone} = Tempo.to_interval_set(RecurrenceSet.new!([member]), within: within)
        {:ok, beside} = Tempo.to_interval_set(RecurrenceSet.new!([member, never]), within: within)

        assert {window, member, IntervalSet.members(beside)} ==
                 {window, member, IntervalSet.members(alone)}
      end
    end
  end
end
