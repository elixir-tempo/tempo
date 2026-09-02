defmodule Tempo.ParseProfileTest do
  @moduledoc """
  `Tempo.parse_date/2`, `parse_datetime/2`, `parse_time/2` and
  `parse_interval/2` — the caller declares the shape its value must
  have, and only that shape is admitted.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  # Each profile paired with the strings that are, and are not, that
  # profile. A string legal under one profile appears as a rejection
  # under the others, so the table is its own cross-check.
  @dates ["2026", "2026-06", "2026-06-15", "2026-W12", "2026-166", "20260615"]
  @datetimes ["2026-06-15T10:30", "2026-06-15T10:30:15", "2026-06-15T10:30Z"]
  @times ["T10:30", "T10:30:15", "T10:30:15.5"]
  @intervals [
    "2026-06-15/2026-06-20",
    "2026-06-15/P5D",
    "P5D/2026-06-20",
    "R5/2026-06-15/P1D",
    "2026-06-15/.."
  ]

  describe "each profile accepts its own shape" do
    test "dates" do
      for iso <- @dates do
        assert {:ok, %Tempo{}} = Tempo.parse_date(iso), "#{iso} did not parse as a date"
      end
    end

    test "datetimes" do
      for iso <- @datetimes do
        assert {:ok, %Tempo{}} = Tempo.parse_datetime(iso), "#{iso} did not parse as a datetime"
      end
    end

    test "times" do
      for iso <- @times do
        assert {:ok, %Tempo{}} = Tempo.parse_time(iso), "#{iso} did not parse as a time"
      end
    end

    test "intervals" do
      for iso <- @intervals do
        assert {:ok, %Tempo.Interval{}} = Tempo.parse_interval(iso),
               "#{iso} did not parse as an interval"
      end
    end
  end

  describe "the result agrees with the general parser" do
    test "every accepted value equals what from_iso8601/1 returns" do
      # The profile narrows what is *admitted*; it must never change
      # what an admitted value means. `@times` is excluded — see the
      # ambiguity test below, which is the documented exception.
      for iso <- @dates ++ @datetimes ++ @intervals do
        parsed =
          cond do
            iso in @dates -> Tempo.parse_date!(iso)
            iso in @datetimes -> Tempo.parse_datetime!(iso)
            iso in @intervals -> Tempo.parse_interval!(iso)
          end

        assert parsed == Tempo.from_iso8601!(iso), "#{iso} disagreed with Tempo.from_iso8601/1"
      end
    end
  end

  describe "the profile is the boundary" do
    test "a datetime is not a date, a time, or an interval" do
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_date("2026-06-15T10:30")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_time("2026-06-15T10:30")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_interval("2026-06-15T10:30")
    end

    test "a date is not a datetime or an interval" do
      # The reason these functions exist: a date, a datetime and a time
      # are all `%Tempo{}`, so `from_iso8601/1` cannot tell a caller
      # that its date field received something else.
      assert {:ok, %Tempo{}} = Tempo.from_iso8601("2026-06-15")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_datetime("2026-06-15")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_interval("2026-06-15")
    end

    test "an interval is not a date or a datetime" do
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_date("2026-06-15/2026-06-20")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_datetime("2026-06-15/2026-06-20")
    end

    test "a duration is none of them" do
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_date("P1D")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_datetime("P1D")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_time("P1D")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_interval("P1D")
    end

    test "a value that merely begins with the profile is not truncated" do
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_date("2026-06-15/2026-06-20")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_datetime("2026-06-15T10:30/P1D")
      assert {:error, %Tempo.ParseError{}} = Tempo.parse_interval("2026-06-15/2026-06-20junk")
    end

    test "junk and empty input are rejected" do
      for parse <- [&Tempo.parse_date/1, &Tempo.parse_datetime/1, &Tempo.parse_interval/1] do
        assert {:error, %Tempo.ParseError{}} = parse.("")
        assert {:error, %Tempo.ParseError{}} = parse.("not a date")
      end
    end

    test "the error names the input and the profile expected" do
      {:error, error} = Tempo.parse_date("2026-06-15T10:30")
      assert Exception.message(error) =~ "as a date"
      assert Exception.message(error) =~ "2026-06-15T10:30"

      {:error, error} = Tempo.parse_interval("2026-06-15")
      assert Exception.message(error) =~ "as an interval"
    end
  end

  describe "ambiguity is resolved in favour of the declared profile" do
    test "a bare four-digit value is a year generally and a time under parse_time/2" do
      # ISO 8601 basic format makes "2026" both the year 2026 and
      # 20:26. The general grammar prefers the date reading; declaring
      # the time profile is what selects the other one.
      assert Tempo.from_iso8601!("2026") == ~o"2026Y"
      assert Tempo.parse_time!("2026") == ~o"T20H26M"
      assert Tempo.parse_date!("2026") == ~o"2026Y"
    end
  end

  describe "qualification, IXDTF suffixes and calendars survive the profile" do
    test "an EDTF qualification is kept, not dropped" do
      assert Tempo.parse_date!("2026-06-15~") == Tempo.from_iso8601!("2026-06-15~")
    end

    test "an IXDTF suffix is kept" do
      assert Tempo.parse_date!("2026-06-15[u-ca=gregory]") ==
               Tempo.from_iso8601!("2026-06-15[u-ca=gregory]")
    end

    test "the :calendar option selects the calendar" do
      assert Tempo.parse_date!("5786-01-15", calendar: Calendrical.Hebrew) ==
               Tempo.from_iso8601!("5786-01-15", Calendrical.Hebrew)
    end

    test "an invalid date is rejected by validation, not admitted by the profile" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.parse_date("2026-02-30")
    end
  end

  describe "bang variants" do
    test "return the value or raise" do
      assert Tempo.parse_date!("2026-06-15") == ~o"2026Y6M15D"
      assert Tempo.parse_datetime!("2026-06-15T10:30") == ~o"2026Y6M15DT10H30M"
      assert Tempo.parse_time!("T10:30") == ~o"T10H30M"
      assert Tempo.parse_interval!("2026-06-15/2026-06-20") == ~o"2026Y6M15D/20D"

      assert_raise Tempo.ParseError, fn -> Tempo.parse_date!("2026-06-15T10:30") end
      assert_raise Tempo.ParseError, fn -> Tempo.parse_datetime!("2026-06-15") end
      assert_raise Tempo.ParseError, fn -> Tempo.parse_time!("2026-06-15T10:30") end
      assert_raise Tempo.ParseError, fn -> Tempo.parse_interval!("2026-06-15") end
    end
  end
end
