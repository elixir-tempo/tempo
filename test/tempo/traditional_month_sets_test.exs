defmodule Tempo.TraditionalMonthSetsTest do
  @moduledoc """
  Sets and masks of traditional months (`{5,6}m`, `1Xm`, `X+m`).

  A traditional month is a month as its calendar names it, and its place in
  the year moves where the year holds a leap month before it. One written
  as a number was resolved; a set or a mask of them was a
  `Tempo.ConversionError` from every reading, and a set of months of two
  digits (`{10,11}m`) named none.

  The measure is apart from Tempo. For the Hebrew calendar it is the months'
  own names, as CLDR has them in English: RFC 7529 numbers them from Tishri,
  1, to Elul, 12, with Adar I the leap month after the fifth, and Adar
  called Adar II in a year that has it. For the Chinese calendar it is what
  one traditional month at a time resolves to, which is the calendar's own
  answer for a month and no list of them.
  """
  use ExUnit.Case, async: true

  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.InvalidDateError

  # 5786 is a Hebrew year of twelve months, and 5787 and 5790 years of
  # thirteen. The Chinese year 4660 has a leap month after its second.
  defp hebrew(text), do: Tempo.from_iso8601!(text <> "[u-ca=hebrew]")
  defp chinese(text), do: Tempo.from_iso8601!(text <> "[u-ca=chinese]")

  defp members(value) do
    {:ok, set} = Tempo.to_interval_set(value)
    IntervalSet.members(set)
  end

  # The name of the month each member of a value starts in.
  defp month_names(value), do: value |> members() |> Enum.map(&name_of_month/1)

  defp name_of_month(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    fields = %{year: time[:year], month: time[:month], calendar: calendar}
    {:ok, name} = Localize.Date.to_string(fields, format: "MMMM", locale: :en)
    name
  end

  defp refusal(text) do
    assert {:error, %InvalidDateError{} = error} = Tempo.from_iso8601(text <> "[u-ca=hebrew]")
    Exception.message(error)
  end

  describe "a set of traditional months" do
    test "names each month the calendar numbers so" do
      assert month_names(hebrew("5787Y{5,6}m")) == ["Shevat", "Adar II"]
      assert month_names(hebrew("5786Y{5,6}m")) == ["Shevat", "Adar"]
      assert month_names(hebrew("5787Y{7,12}m")) == ["Nisan", "Elul"]
    end

    test "holds months of two digits" do
      assert month_names(hebrew("5787Y{10,11}m")) == ["Tamuz", "Av"]
      assert month_names(hebrew("5786Y{10..12}m")) == ["Tamuz", "Av", "Elul"]
    end

    test "passes over the leap month between the ends of a range" do
      assert month_names(hebrew("5787Y{5..7}m")) == ["Shevat", "Adar II", "Nisan"]
    end

    test "counts from the end among the months the year numbers" do
      assert month_names(hebrew("5787Y{-1}m")) == ["Elul"]
      assert month_names(hebrew("5786Y{-2,-1}m")) == ["Av", "Elul"]
    end

    test "is the same months as the months counted in order, in a calendar with no leap month" do
      assert Tempo.from_iso8601!("2026Y{1,2}m") == Tempo.from_iso8601!("2026Y{1,2}M")
    end
  end

  describe "a mask of a traditional month" do
    test "names the months whose numbers it matches" do
      assert month_names(hebrew("5787Y1Xm")) == ["Tamuz", "Av", "Elul"]
      assert month_names(hebrew("5786Y1Xm")) == ["Tamuz", "Av", "Elul"]
      assert month_names(hebrew("5787Y1{0,1}m")) == ["Tamuz", "Av"]
    end

    test "names no leap month, which no number names" do
      assert month_names(hebrew("5787YXXm")) ==
               ~w(Tishri Heshvan Kislev Tevet Shevat) ++
                 ["Adar II"] ++ ~w(Nisan Iyar Sivan Tamuz Av Elul)
    end

    test "is the months counted in order, in a calendar with no leap month" do
      assert Tempo.from_iso8601!("2026Y1Xm") == Tempo.from_iso8601!("2026Y{10..12}M")
    end
  end

  describe "a set or a mask with `+` after it" do
    test "names the leap month of a year that has one" do
      assert month_names(hebrew("5787YX+m")) == ["Adar I"]
      assert month_names(hebrew("5787Y{5}+m")) == ["Adar I"]
      assert month_names(hebrew("5787YX*+m")) == ["Adar I"]
    end

    test "is the leap month one number names" do
      assert hebrew("5787YX+m") == hebrew("5787Y5+m")
    end
  end

  describe "each year of several" do
    test "takes the months it has" do
      assert month_names(hebrew("{5786,5787}Y{5,6}m")) == ["Shevat", "Adar", "Shevat", "Adar II"]
      assert month_names(hebrew("{5786,5787}Y1Xm")) == ~w(Tamuz Av Elul Tamuz Av Elul)
    end

    test "has a leap month or has none" do
      assert month_names(hebrew("{5786,5787}YX+m")) == ["Adar I"]
    end

    test "is walked a month at a time, each in its place in its year" do
      walked = Enum.to_list(hebrew("{5786,5787}Y1Xm"))

      # The tenth traditional month is the tenth of a year of twelve and the
      # eleventh of a year with a leap month before it.
      assert walked ==
               Enum.map(~w(5786Y10M 5786Y11M 5786Y12M 5787Y11M 5787Y12M 5787Y13M), &hebrew/1)

      assert Enum.flat_map(walked, &month_names/1) == ~w(Tamuz Av Elul Tamuz Av Elul)
    end

    test "is walked as one traditional month of each year is" do
      assert Enum.to_list(hebrew("{5786,5787}Y6m")) == [hebrew("5786Y6M"), hebrew("5787Y7M")]
      assert Enum.to_list(hebrew("{5786,5787}Y5+m")) == [hebrew("5787Y6M")]

      assert Enum.to_list(hebrew("{5786,5787}Y{5,6}m1D")) ==
               Enum.map(~w(5786Y5M1D 5786Y6M1D 5787Y5M1D 5787Y7M1D), &hebrew/1)
    end

    test "is written as it was read" do
      for text <- ~w({5786..5787}Y{5..6}m {5786..5787}Y1Xm {5786..5787}YX+m {5786..5787}Y{5}+m) do
        value = hebrew(text)
        assert Tempo.to_iso8601!(value) == text <> "[u-ca=hebrew]"
        assert Tempo.from_iso8601!(Tempo.to_iso8601!(value)) == value
      end
    end
  end

  describe "a rule" do
    test "selects in each year the months a mask matches" do
      assert month_names(hebrew("R4/5786-01-01/P1Y/FL1XmN")) == ~w(Tamuz Av Elul Tamuz)
    end

    test "selects the months of a set, of two digits among them" do
      assert month_names(hebrew("R3/5786-01-01/P1Y/FL{10,11}mN")) == ~w(Tamuz Av Tamuz)

      assert month_names(hebrew("R4/5786-01-01/P1Y/FL{5,6}mN")) == [
               "Shevat",
               "Adar",
               "Shevat",
               "Adar II"
             ]
    end

    test "selects a month counted from the year's last" do
      assert month_names(hebrew("R2/5786-01-01/P1Y/FL{-1}mN")) == ["Elul", "Elul"]
    end

    test "selects a leap month in the years that have one" do
      occurrences = members(hebrew("R2/5786-01-01/P1Y/FLX+mN"))

      assert Enum.map(occurrences, &name_of_month/1) == ["Adar I", "Adar I"]
      assert Enum.map(occurrences, & &1.from.time[:year]) == [5787, 5790]
    end
  end

  describe "a traditional month the year has not" do
    test "is refused with those it has" do
      assert refusal("5787Y13m") ==
               "13 is not valid for a traditional month of 5787 in Calendrical.Hebrew. " <>
                 "The valid values are 1..12"

      assert refusal("5787Y{12,13}m") ==
               "13 is not valid for a traditional month of 5787 in Calendrical.Hebrew. " <>
                 "The valid values are 1..12"

      assert refusal("5787Y9Xm") ==
               "9X is not valid for a traditional month of 5787 in Calendrical.Hebrew. " <>
                 "The valid values are 1..12"
    end

    test "is an error of its own kind for one number, where it was a bare atom" do
      assert refusal("5786Y13m") ==
               "13 is not valid for a traditional month of 5786 in Calendrical.Hebrew. " <>
                 "The valid values are 1..12"
    end

    test "is refused for a leap month, with the leap months the year has" do
      assert refusal("5787Y{5..6}+m") ==
               "6 is not valid for a leap month of 5787 in Calendrical.Hebrew. " <>
                 "The valid values are 5..5"

      assert refusal("5787Y1X+m") ==
               "1X is not valid for a leap month of 5787 in Calendrical.Hebrew. " <>
                 "The valid values are 5..5"

      assert refusal("5786YX+m") == "Calendrical.Hebrew year 5786 has no leap month"
      assert refusal("5786Y{5}+m") == "Calendrical.Hebrew year 5786 has no leap month"
    end
  end

  describe "in the Chinese calendar" do
    test "a set is the months each of its numbers resolves to" do
      assert members(chinese("4660Y{2,3}m")) ==
               members(chinese("4660Y2m")) ++ members(chinese("4660Y3m"))
    end

    test "a mask is the months each number it matches resolves to" do
      assert members(chinese("4660Y1Xm")) ==
               Enum.flat_map(10..12, &members(chinese("4660Y#{&1}m")))
    end

    test "a mask with `+` is the leap month" do
      assert chinese("4660YX+m") == chinese("4660Y2+m")
    end
  end

  describe "the reader" do
    test "reads a set alone as a set of months, and one among digits as a set of digits" do
      assert hebrew("{5786,5787}Y{10,11}m").time[:traditional_month] == [10..11]
      assert hebrew("{5786,5787}Y1{0,1}m").time[:traditional_month] == {:mask, [1, [0..1]]}
      assert hebrew("{5786,5787}Y{5,6}+m").time[:traditional_month] == {[5..6], :leap}
    end
  end
end
