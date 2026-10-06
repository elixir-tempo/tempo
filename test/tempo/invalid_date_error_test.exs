defmodule Tempo.InvalidDateErrorTest do
  @moduledoc """
  What the error for a value its unit does not take says.

  29 February 2027 was refused as "29 is not valid. The valid values are
  1..28", which names no unit, month, year or calendar, and the error held
  none of them. It carries what the value was read as, and says it.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.InvalidDateError

  defp refused(text, calendar \\ Calendrical.Gregorian) do
    assert {:error, %InvalidDateError{} = error} = Tempo.from_iso8601(text, calendar)
    error
  end

  describe "a day its month does not have" do
    test "is named with its month, its year and the days the month has" do
      error = refused("2027-02-29")

      assert Exception.message(error) ==
               "29 is not valid for a day of 2027-02. The valid values are 1..28"

      assert %InvalidDateError{
               unit: :day,
               value: 29,
               year: 2027,
               month: 2,
               valid_range: 1..28,
               calendar: Calendrical.Gregorian
             } = error
    end

    test "is named so however the date is made" do
      message = "29 is not valid for a day of 2027-02. The valid values are 1..28"

      for {:error, error} <- [
            Tempo.new(year: 2027, month: 2, day: 29),
            Tempo.on(~o"2M29D", ~o"2027"),
            Tempo.at(~o"2027", ~o"2M29D"),
            Tempo.merge(~o"2M29D", ~o"2027Y")
          ] do
        assert Exception.message(error) == message
      end
    end

    test "is named with its calendar in a calendar other than the Gregorian" do
      # Cheshvan, the second month, has 29 days in 5784 and 30 in 5785.
      assert {:ok, _complete} = Tempo.from_iso8601("5785-02-30", Calendrical.Hebrew)

      assert Exception.message(refused("5784-02-30", Calendrical.Hebrew)) ==
               "30 is not valid for a day of 5784-02 in Calendrical.Hebrew. " <>
                 "The valid values are 1..29"
    end

    test "is named with its month alone where there is no year" do
      assert Exception.message(refused("2M30D")) ==
               "30 is not valid for a day of month 2. The valid values are 1..29"
    end

    test "is named in a set and counted from the end" do
      assert Exception.message(refused("2026Y2M{28..30}D")) ==
               "30 is not valid for a day of 2026-02. The valid values are 1..28"

      assert Exception.message(refused("2026Y2M-30D")) =~
               "-30 is not valid for a day of 2026-02."
    end
  end

  describe "a value of another unit that the unit does not take" do
    for {text, message} <- [
          {"2027-13-01", "13 is not valid for a month of 2027. The valid values are 1..12"},
          {"2026-W54-1", "54 is not valid for a week of 2026. The valid values are 1..53"},
          {"2026-W25-8", "8 is not valid for a day of the week. The valid values are 1..7"},
          {"2026-366",
           "366 is not valid for a day of the year 2026. The valid values are 1..365"},
          {"2026-06-15T25", "25 is not valid for an hour. The valid values are 0..23"},
          {"2026-06-15T10:61", "61 is not valid for a minute. The valid values are 0..59"},
          {"2026-06-15T10:30:61", "61 is not valid for a second. The valid values are 0..60"}
        ] do
      test "#{text} says #{message}" do
        error = refused(unquote(text))

        assert Exception.message(error) == unquote(message)
        assert is_atom(error.unit) and not is_nil(error.unit)
      end
    end
  end
end
