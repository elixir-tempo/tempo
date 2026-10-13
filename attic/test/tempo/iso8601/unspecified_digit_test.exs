defmodule Tempo.Iso8601.UnspecifiedDigit.Test do
  use ExUnit.Case, async: true

  # Unspecified digits (`X`) in date components are a core ISO 8601-2
  # / EDTF feature. Archaeologists and historians routinely write
  # `156X` ("sometime in the 1560s"), `1XXX` ("the first millennium"),
  # or `1985-XX-XX` ("sometime in 1985") when full resolution isn't
  # available.

  describe "positive years" do
    test "one unspecified digit (`156X`)" do
      assert {:ok, _} = Tempo.from_iso8601("156X")
    end

    test "two unspecified digits (`15XX`)" do
      assert {:ok, _} = Tempo.from_iso8601("15XX")
    end

    test "three unspecified digits (`1XXX`)" do
      assert {:ok, _} = Tempo.from_iso8601("1XXX")
    end

    test "all four digits unspecified (`XXXX`)" do
      assert {:ok, _} = Tempo.from_iso8601("XXXX")
    end

    test "internal unspecified (`1X99`)" do
      assert {:ok, _} = Tempo.from_iso8601("1X99")
    end
  end

  describe "negative years" do
    # Negative years with unspecified digits used to crash the parser.
    # Fixed by adding a `form_number` clause that tags the mask with
    # a leading `:negative` sentinel.

    test "negative year with trailing unspecified" do
      assert {:ok, _} = Tempo.from_iso8601("-156X")
    end

    test "negative fully-unspecified year" do
      assert {:ok, _} = Tempo.from_iso8601("-XXXX")
    end

    test "negative year with unspecified month-day" do
      assert {:ok, _} = Tempo.from_iso8601("-1XXX-XX")
    end

    test "negative year with all-unspecified month-day" do
      assert {:ok, _} = Tempo.from_iso8601("-XXXX-12-XX")
    end

    test "negative year, month and day all with unspecified digits" do
      assert {:ok, _} = Tempo.from_iso8601("-1X32-X1-X2")
    end
  end

  describe "month and day" do
    test "unspecified month (`2022-XX`)" do
      assert {:ok, _} = Tempo.from_iso8601("2022-XX")
    end

    test "unspecified day (`2022-06-XX`)" do
      assert {:ok, _} = Tempo.from_iso8601("2022-06-XX")
    end

    test "partial month digit (`2022-1X`)" do
      assert {:ok, _} = Tempo.from_iso8601("2022-1X")
    end

    test "everything unspecified below year (`2022-XX-XX`)" do
      assert {:ok, _} = Tempo.from_iso8601("2022-XX-XX")
    end
  end

  describe "intervals with unspecified digits" do
    test "both endpoints partially unspecified" do
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601("198X/199X")
    end

    test "one endpoint fully unspecified" do
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601("2000-XX-XX/2012")
    end

    test "negative endpoint with unspecified" do
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601("-2000-XX-10/2012")
    end
  end

  describe "roundtrip via sigil" do
    # The inspect protocol formats masks back to their EDTF syntax,
    # preserving the leading `-` for negative years.
    test "negative year with unspecified roundtrips" do
      {:ok, tempo} = Tempo.from_iso8601("-1XXX-XX")
      assert inspect(tempo) =~ "-1XXX"
    end
  end

  # In the basic format a unit's digits run straight on into the next unit's.
  # Where that next unit was unspecified digits or a set, the unit before it
  # was held as a mask of its own digits (`202606XX` had the month
  # `{:mask, [0, 6]}`, `2026XX15` the year `{:mask, [2, 0, 2, 6]}`): the
  # value was not the one the extended format writes, did not read back from
  # its own text, had no `Tempo.year/1` or `Tempo.month/1`, and was stepped
  # as an unspecified unit is.
  #
  # The measure is the extended format, whose separators keep each unit to
  # itself.
  describe "a unit of the basic format before unspecified digits or a set" do
    @twins [
      {"202606XX", "2026-06-XX"},
      {"2026XX15", "2026-XX-15"},
      {"2026XXXX", "2026-XX-XX"},
      {"1985XXXX", "1985-XX-XX"},
      {"202606{15,20}", "2026-06-{15,20}"},
      {"2026{06,07}15", "2026-{06,07}-15"},
      {"202606XXT10", "2026-06-XXT10"},
      {"20260615T10XX", "2026-06-15T10:XX"},
      {"20260615T1030XX", "2026-06-15T10:30:XX"},
      {"20260615T10{30,45}", "2026-06-15T10:{30,45}"},
      {"20260615T1030{45,50}", "2026-06-15T10:30:{45,50}"},
      {"T1030XX", "T10:30:XX"},
      {"T1030{45,50}", "T10:30:{45,50}"},
      {"T1030{45,50}.5", "T10:30:{45,50}.5"},
      {"T1030{45,50}Z", "T10:30:{45,50}Z"},
      {"2026W25X", "2026-W25-X"},
      {"20{1,2}606XX", "20{1,2}6-06-XX"},
      {"202606XX/202607XX", "2026-06-XX/2026-07-XX"},
      {"R/202606XX/P1M", "R/2026-06-XX/P1M"}
    ]

    test "is the unit the extended format writes" do
      for {basic, extended} <- @twins do
        assert {basic, Tempo.from_iso8601(basic)} == {basic, Tempo.from_iso8601(extended)}
      end
    end

    test "reads back from its own text" do
      for {basic, _extended} <- @twins do
        value = Tempo.from_iso8601!(basic)
        assert {basic, Tempo.from_iso8601(Tempo.to_iso8601!(value))} == {basic, {:ok, value}}
      end
    end

    test "is a whole number where every digit is written" do
      assert Tempo.from_iso8601!("202606XX").time ==
               [year: 2026, month: 6, day: {:mask, [:X, :X]}]

      assert Tempo.from_iso8601!("2026XX15").time ==
               [year: 2026, month: {:mask, [:X, :X]}, day: 15]

      assert Tempo.from_iso8601!("T1030{45,50}").time == [hour: 10, minute: 30, second: [45, 50]]
    end

    test "has the year and the month it is written with" do
      assert Tempo.year(Tempo.from_iso8601!("2026XX15")) == 2026
      assert Tempo.month(Tempo.from_iso8601!("202606XX")) == 6
    end

    test "is stepped as the unit it is" do
      assert Tempo.shift(Tempo.from_iso8601!("T1030{45,50}"), minute: 1) ==
               Tempo.shift(Tempo.from_iso8601!("T10:30:{45,50}"), minute: 1)

      assert Tempo.shift(Tempo.from_iso8601!("202606XX"), month: 1) ==
               Tempo.shift(Tempo.from_iso8601!("2026-06-XX"), month: 1)
    end

    test "stays a mask where a digit is unspecified or a set" do
      assert Tempo.from_iso8601!("19XX").time == [year: {:mask, [1, 9, :X, :X]}]
      assert Tempo.from_iso8601!("2026Y0XM").time == [year: 2026, month: {:mask, [0, :X]}]
      assert Tempo.from_iso8601!("20{1,2}6").time == [year: {:mask, [2, 0, [1..2], 6]}]
      assert Tempo.from_iso8601!("-20XX").time == [year: {:mask, [:negative, 2, 0, :X, :X]}]
    end
  end
end
