defmodule Tempo.Extend.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

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

      assert Tempo.extend(Tempo.from_iso8601!("5786Y{6,7}M", Calendrical.Hebrew)) ==
               Tempo.from_iso8601("5786Y{6,7}M{1..-1}D", Calendrical.Hebrew)
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
            ~o"2026Y21M",
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
