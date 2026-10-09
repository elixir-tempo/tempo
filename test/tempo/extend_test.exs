defmodule Tempo.Extend.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Calendrical.Hebrew

  # `Tempo.extend/2` writes a value by the unit below its own. It returns
  # tuples, and raised for a value with no finer unit (a fraction of a second
  # at microsecond precision), for a second already written as its
  # fractions, and for anything that is not one date or time value.

  describe "a value with a finer unit" do
    test "is written as that unit's values" do
      assert Tempo.extend(~o"2026") == {:ok, ~o"2026Y{1..12}M"}
      assert Tempo.extend(~o"2026-06") == {:ok, ~o"2026Y6M{1..30}D"}
      assert Tempo.extend(~o"2026-06-15") == {:ok, ~o"2026Y6M15DT{0..23}H"}
      assert Tempo.extend(~o"2026-06-15T10") == {:ok, ~o"2026Y6M15DT10H{0..59}M"}
      assert Tempo.extend(~o"2026-W25") == {:ok, ~o"2026Y25W{1..7}K"}
      assert Tempo.extend(~o"T10H") == {:ok, ~o"T10H{0..59}M"}
    end

    test "covers the span the value does" do
      {:ok, days} = Tempo.extend(~o"2026-06")

      assert Enum.to_list(days) == Enum.to_list(~o"2026-06")
    end
  end

  # The months of a year and the days of a month depend on which year or
  # month it is, so under a value naming several they are written from the
  # first to the last (`{1..-1}`), the range text is read as.
  describe "a value naming several years or months" do
    test "is written as the finer unit from its first to its last, as text is read" do
      assert Tempo.extend(~o"2026Y{6,7}M") == {:ok, ~o"2026Y{6,7}M{1..-1}D"}
      assert Tempo.extend(~o"{2026,2027}Y") == {:ok, ~o"{2026,2027}Y{1..-1}M"}
      assert Tempo.extend(~o"{2024,2025}Y2M") == {:ok, ~o"{2024,2025}Y2M{1..-1}D"}
      assert Tempo.extend(~o"202X") == {:ok, ~o"202XY{1..-1}M"}
      assert Tempo.extend(~o"2026-1X") == {:ok, ~o"2026Y1XM{1..-1}D"}
      assert Tempo.extend(~o"{6,7}M") == {:ok, ~o"{6,7}M{1..-1}D"}
    end

    test "in a calendar of weeks, and in one of other months" do
      assert Tempo.extend(Tempo.from_iso8601!("{2026,2027}Y", Calendrical.ISOWeek)) ==
               Tempo.from_iso8601("{2026,2027}Y{1..-1}W", Calendrical.ISOWeek)

      assert Tempo.extend(Tempo.from_iso8601!("5786Y{6,7}M", Hebrew)) ==
               Tempo.from_iso8601("5786Y{6,7}M{1..-1}D", Hebrew)
    end

    test "inspects as the text that reads back as it" do
      {:ok, days} = Tempo.extend(~o"2026Y{6,7}M")

      assert inspect(days) == ~s(~o"2026Y{6..7}M{1..-1}D")
    end

    test "covers the span of each" do
      {:ok, days} = Tempo.extend(~o"2024Y{2,3}M")

      assert Enum.count(days) == 29 + 31
      assert hd(Enum.to_list(days)) == ~o"2024-02-01"
      assert List.last(Enum.to_list(days)) == ~o"2024-03-31"
    end
  end

  describe "a second and a fraction of a second" do
    test "are written as their next decimal place" do
      {:ok, tenths} = Tempo.extend(~o"2026-06-15T10:30:45")

      assert Enum.to_list(tenths) == Enum.to_list(~o"2026-06-15T10:30:45")
      assert Enum.count(tenths) == 10

      {:ok, thousandths} = Tempo.extend(~o"2026-06-15T10:30:45.12")

      assert Enum.to_list(thousandths) == Enum.to_list(~o"2026-06-15T10:30:45.12")
      assert hd(Enum.to_list(thousandths)) == ~o"2026-06-15T10:30:45.120"
    end

    test "extend again, a place at a time" do
      {:ok, tenths} = Tempo.extend(~o"2026-06-15T10:30:45")
      {:ok, hundredths} = Tempo.extend(tenths)

      assert Enum.count(hundredths) == 100
      assert hd(Enum.to_list(hundredths)) == ~o"2026-06-15T10:30:45.00"
      assert List.last(Enum.to_list(hundredths)) == ~o"2026-06-15T10:30:45.99"
    end

    test "inspect as a set after the decimal sign" do
      {:ok, tenths} = Tempo.extend(~o"2026-06-15T10:30:45")
      {:ok, hundredths} = Tempo.extend(tenths)
      {:ok, thousandths} = Tempo.extend(~o"2026-06-15T10:30:45.12")

      assert inspect(tenths) == ~s(~o"2026Y6M15DT10H30M45.{0..9}S")
      assert inspect(hundredths) == ~s(~o"2026Y6M15DT10H30M45.{00..99}S")
      assert inspect(thousandths) == ~s(~o"2026Y6M15DT10H30M45.{120..129}S")
    end

    test "that do not run on from one another inspect one by one" do
      scattered = %{~o"2026-06-15T10:30:45" | time: scattered_time()}

      assert inspect(scattered) == ~s(~o"2026Y6M15DT10H30M45.{0,5}S")
    end
  end

  # A group names values of its own unit, the ones its walk yields, and a
  # unit written after a group is counted from the group's start (ISO 8601-2
  # §5.4.2), so an enumeration of the unit below was read as no value of the
  # group is. A group is written as the values it names.
  describe "a value that ends in a group" do
    test "is written as the values the group names" do
      assert Tempo.extend(~o"2026Y2G3MU") == {:ok, ~o"2026Y{4..6}M"}
      assert Tempo.extend(~o"2026Y2Q") == {:ok, ~o"2026Y{4..6}M"}
      assert Tempo.extend(~o"2G5YU") == {:ok, ~o"{5..9}Y"}
      assert Tempo.extend(~o"2026Y3G4WU") == {:ok, ~o"2026Y{9..12}W"}
      assert Tempo.extend(~o"2026Y6M2G10DU") == {:ok, ~o"2026Y6M{11..20}D"}
      assert Tempo.extend(~o"2026Y2G60DU") == {:ok, ~o"2026Y{61..120}D"}
      assert Tempo.extend(~o"2026Y6M15D2GT6HU") == {:ok, ~o"2026Y6M15DT{6..11}H"}
      assert Tempo.extend(~o"2026Y6M15DT10H2G15MU") == {:ok, ~o"2026Y6M15DT10H{15..29}M"}

      assert Tempo.extend(~o"2026Y6M15DT10H30M2G15SU") ==
               {:ok, ~o"2026Y6M15DT10H30M{15..29}S"}

      assert Tempo.extend(~o"2G3MU") == {:ok, ~o"{4..6}M"}
      assert Tempo.extend(~o"T2G6HU") == {:ok, ~o"T{6..11}H"}
    end

    test "walks as the group does and reads back as itself" do
      for text <- [
            "2026Y2G3MU",
            "2026Y2Q",
            "2G5YU",
            "2026Y3G4WU",
            "2026Y6M2G10DU",
            "2026Y2G60DU",
            "2026Y6M15D2GT6HU",
            "2026Y6M15DT10H2G15MU",
            "2026Y6M15DT10H30M2G15SU",
            "2G3MU",
            "T2G6HU",
            "2026Y{1,-1}G3MU",
            "{2026,2027}Y{1,-1}G3MU",
            "2026Y2M3G10DU",
            "2026Y6M{1,3}G10DU"
          ] do
        group = Tempo.from_iso8601!(text)
        {:ok, written} = Tempo.extend(group)
        {:ok, iso8601} = Tempo.to_iso8601(written)

        assert Enum.to_list(written) == Enum.to_list(group)
        assert Tempo.from_iso8601(iso8601) == {:ok, written}
      end
    end

    test "a group of a set is the values of each of its groups" do
      assert Tempo.extend(~o"2026Y{1,2}G3MU") == {:ok, ~o"2026Y{1..6}M"}
      assert Tempo.extend(~o"2026Y{1,-1}G3MU") == {:ok, ~o"2026Y{1..3,10..12}M"}
      assert Tempo.extend(~o"2026Y6M{1,3}G10DU") == {:ok, ~o"2026Y6M{1..10,21..30}D"}
      assert Tempo.extend(~o"2026Y2M{1..-1}G10DU") == {:ok, ~o"2026Y2M{1..28}D"}
    end

    test "stops where its container does" do
      # The third ten days of a February, and a group of thirty-one days of June.
      assert Tempo.extend(~o"2026Y2M3G10DU") == {:ok, ~o"2026Y2M{21..28}D"}
      assert Tempo.extend(~o"2024Y2M3G10DU") == {:ok, ~o"2024Y2M{21..29}D"}
      assert Tempo.extend(~o"2026Y6M1G31DU") == {:ok, ~o"2026Y6M{1..30}D"}
    end

    test "that names one value is that value" do
      assert Tempo.extend(~o"2026Y3G1MU") == {:ok, ~o"2026Y3M"}

      # 2026 has 53 weeks, so the fourteenth group of four holds the last alone.
      assert Tempo.extend(~o"2026Y14G4WU") == {:ok, ~o"2026Y53W"}
    end

    test "under several years or months is written where it names the same values in each" do
      assert Tempo.extend(~o"{2026,2027}Y2G3MU") == {:ok, ~o"{2026,2027}Y{4..6}M"}

      assert Tempo.extend(~o"{2026,2027}Y{1,-1}G3MU") ==
               {:ok, ~o"{2026,2027}Y{1..3,10..12}M"}

      # The third ten days of February are eight days or nine, and of January ten.
      for value <- [~o"{2024,2026}Y2M3G10DU", ~o"2026Y{1,2}M3G10DU"] do
        assert {:error, %Tempo.ConversionError{} = error} = Tempo.extend(value)
        assert Exception.message(error) =~ "the group names other values in each"
        assert_raise Tempo.ConversionError, fn -> Tempo.extend!(value) end
      end
    end

    test "in a calendar of weeks, and in one of other months" do
      assert Tempo.extend(Tempo.from_iso8601!("2026Y2G4WU", Calendrical.ISOWeek)) ==
               Tempo.from_iso8601("2026Y{5..8}W", Calendrical.ISOWeek)

      assert Tempo.extend(Tempo.from_iso8601!("5786Y2G3MU", Hebrew)) ==
               Tempo.from_iso8601("5786Y{4..6}M", Hebrew)

      # 5784 has thirteen months, so its last group of three is the thirteenth alone.
      assert Hebrew.months_in_year(5784) == 13

      assert Tempo.extend(Tempo.from_iso8601!("5784Y{1,-1}G3MU", Hebrew)) ==
               Tempo.from_iso8601("5784Y{1..3,13}M", Hebrew)

      assert {:error, %Tempo.ConversionError{}} =
               Tempo.extend(Tempo.from_iso8601!("{5784,5785}Y{1,-1}G3MU", Hebrew))
    end

    test "keeps its zone and its qualification" do
      assert Tempo.extend(Tempo.from_iso8601!("2026Y2G3MU[Europe/Paris]")) ==
               Tempo.from_iso8601("2026Y{4..6}M[Europe/Paris]")

      {:ok, months} = Tempo.extend(~o"2026?Y2G3MU")
      assert Tempo.qualification(months, :year) == :uncertain
    end

    test "is the walk's error where the group cannot be walked" do
      assert {:error, %Tempo.ConversionError{reason: :counted_in_group}} =
               Tempo.extend(~o"2026Y2G3MU2G10DU")
    end

    test "is extended again by the unit below the group's" do
      {:ok, months} = Tempo.extend(~o"2026Y2G3MU")

      assert Tempo.extend(months) == {:ok, ~o"2026Y{4..6}M{1..-1}D"}
    end

    test "a unit after a group makes it one value, extended as any is" do
      assert Tempo.extend(~o"2026Y2G3MU15D") == {:ok, ~o"2026Y4M15DT{0..23}H"}
    end
  end

  describe "a value with no finer unit" do
    test "at microsecond precision is an error" do
      assert {:error, %Tempo.ResolutionError{operation: :extend, current: :microsecond} = error} =
               Tempo.extend(~o"2026-06-15T10:30:45.123456")

      assert Exception.message(error) =~ ~s(Cannot extend ~o"2026Y6M15DT10H30M45.123456S")
    end

    test "is an error once its fractions reach a microsecond" do
      {:ok, microseconds} = Tempo.extend(~o"2026-06-15T10:30:45.12345")

      assert Enum.count(microseconds) == 10
      assert {:error, %Tempo.ResolutionError{} = error} = Tempo.extend(microseconds)
      assert Exception.message(error) =~ "45.{123450..123459}S"
    end

    test "that ends in a selection's instance is an error" do
      assert {:error, %Tempo.ResolutionError{current: :instance}} =
               Tempo.extend(~o"2026Y4ML1K1IN")
    end

    test "is the exception extend!/2 raises" do
      assert_raise Tempo.ResolutionError, ~r/a microsecond is the finest unit/, fn ->
        Tempo.extend!(~o"2026-06-15T10:30:45.123456")
      end
    end
  end

  describe "what is not one date or time value" do
    test "is an error" do
      for value <- [
            ~o"2026-06-15/2026-06-20",
            ~o"2026Y25M",
            ~o"R3/2026-06-15/P1D",
            ~o"{2026Y,2027Y}",
            ~o"P1M",
            ~D[2026-06-15],
            "2026",
            :year,
            nil,
            %Tempo{}
          ] do
        assert {:error, %ArgumentError{}} = Tempo.extend(value)
        assert_raise ArgumentError, fn -> Tempo.extend!(value) end
      end
    end

    test "a season with no hemisphere has no months to be written by" do
      # It was the interval of the northern season, and no one value.
      assert {:error, %Tempo.AbstractSeasonError{} = error} = Tempo.extend(~o"2026Y21M")
      assert Exception.message(error) =~ "Tempo.in_territory/2"
      assert_raise Tempo.AbstractSeasonError, fn -> Tempo.extend!(~o"2026Y21M") end
    end

    test "names the value" do
      assert {:error, error} = Tempo.extend(~o"2026-06-15/2026-06-20")
      assert Exception.message(error) =~ ~s(~o"2026Y6M15D/20D" is not one)
    end

    test "a unit, which is reserved, is an error" do
      assert {:error, %ArgumentError{} = error} = Tempo.extend(~o"2026", :month)
      assert Exception.message(error) =~ "must be nil, got :month"
    end
  end

  describe "a struct built by hand" do
    test "with no units has none to extend" do
      empty = %Tempo{time: [], calendar: Calendrical.Gregorian}

      assert {:error, %Tempo.ResolutionError{current: :none}} = Tempo.extend(empty)
    end

    test "with no calendar is read in the default one" do
      assert {:ok, months} = Tempo.extend(%Tempo{time: [year: 2026], calendar: nil})
      assert months.time == [year: 2026, month: [1..12]]

      assert Enum.map(Enum.take(%Tempo{time: [year: 2026], calendar: nil}, 2), & &1.time) ==
               [[year: 2026, month: 1], [year: 2026, month: 2]]
    end
  end

  defp scattered_time do
    [year: 2026, month: 6, day: 15, hour: 10, minute: 30, second: 45] ++
      [microsecond: [{0, 1}, {500_000, 1}]]
  end
end
