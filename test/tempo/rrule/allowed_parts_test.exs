defmodule Tempo.RRule.AllowedPartsTest do
  use ExUnit.Case, async: true

  # RFC 5545 §3.3.10 forbids some parts at some frequencies, and
  # `Tempo.RRule.to_string/1` writes a rule only as the RFC allows it: the
  # allowed equivalent where there is one, and an error that names the part
  # and the frequency for the rest. The table here is the RFC's own text:
  #
  # * "The BYDAY rule part MUST NOT be specified with a numeric value when
  #   the FREQ rule part is not set to MONTHLY or YEARLY. Furthermore, the
  #   BYDAY rule part MUST NOT be specified with a numeric value with the
  #   FREQ rule part set to YEARLY when the BYWEEKNO rule part is specified."
  #
  # * "The BYMONTHDAY rule part MUST NOT be specified when the FREQ rule part
  #   is set to WEEKLY."
  #
  # * "The BYYEARDAY rule part MUST NOT be specified when the FREQ rule part
  #   is set to DAILY, WEEKLY, or MONTHLY."
  #
  # * "The BYWEEKNO rule part MUST NOT be used when the FREQ rule part is set
  #   to anything other than YEARLY."
  #
  # * BYSETPOS "MUST only be used in conjunction with another BYxxx rule
  #   part."

  import Tempo.Sigils

  alias Tempo.ConversionError
  alias Tempo.RRule

  @frequencies [
    {"PT1S", "SECONDLY"},
    {"PT1M", "MINUTELY"},
    {"PT1H", "HOURLY"},
    {"P1D", "DAILY"},
    {"P1W", "WEEKLY"},
    {"P1M", "MONTHLY"},
    {"P1Y", "YEARLY"}
  ]

  # A part as ISO 8601-2 selects it and as an RRULE writes it, and the
  # frequencies RFC 5545 forbids it at.
  @parts [
    {"15D", "BYMONTHDAY", "BYMONTHDAY=15", ["WEEKLY"]},
    {"100O", "BYYEARDAY", "BYYEARDAY=100", ["DAILY", "WEEKLY", "MONTHLY"]},
    {"25W", "BYWEEKNO", "BYWEEKNO=25",
     ["SECONDLY", "MINUTELY", "HOURLY", "DAILY", "WEEKLY", "MONTHLY"]},
    {"3M", "BYMONTH", "BYMONTH=3", []},
    {"5K", "BYDAY", "BYDAY=FR", []},
    {"T9H", "BYHOUR", "BYHOUR=9", []}
  ]

  defp written(text), do: RRule.to_string(Tempo.from_iso8601!(text))

  describe "a part RFC 5545 forbids at a frequency" do
    test "is an error that names the part and the frequency, and is written at every other" do
      for {cadence, frequency} <- @frequencies, {selector, name, part, forbidden} <- @parts do
        answer = written("R/2026-01-01T00:00:00/#{cadence}/FL#{selector}N")

        if frequency in forbidden do
          assert {:error, %ConversionError{target: :rrule, reason: reason}} = answer
          named? = reason =~ "RFC 5545 does not allow #{name} in a #{frequency} rule"
          assert {frequency, name, named?} == {frequency, name, true}
        else
          assert {frequency, name, answer} ==
                   {frequency, name, {:ok, "FREQ=#{frequency};#{part}"}}
        end
      end
    end

    test "is refused for a rule read from an RRULE too" do
      {:ok, rule} = RRule.parse("FREQ=WEEKLY;BYMONTHDAY=15", from: ~o"2026-06-01")
      assert {:error, %ConversionError{target: :rrule, reason: reason}} = RRule.to_string(rule)
      assert reason =~ "BYMONTHDAY in a WEEKLY rule"
    end
  end

  describe "a numbered weekday" do
    test "is a numbered BYDAY in a monthly rule, and in a yearly rule with no BYWEEKNO" do
      assert written("R/2026-06-01/P1M/FL3K2IN") == {:ok, "FREQ=MONTHLY;BYDAY=2WE"}
      assert written("R/2026-06-01/P1Y/FL3K2IN") == {:ok, "FREQ=YEARLY;BYDAY=2WE"}
      assert written("R/2026-06-01/P1Y/FL11M4K4IN") == {:ok, "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH"}
    end

    test "is the weekday and its position where a numbered BYDAY is not allowed" do
      assert written("R/2026-06-01/P1W/FL3K2IN") == {:ok, "FREQ=WEEKLY;BYDAY=WE;BYSETPOS=2"}
      assert written("R/2026-06-01/P1D/FL3K2IN") == {:ok, "FREQ=DAILY;BYDAY=WE;BYSETPOS=2"}

      assert written("R/2026-06-01/P1Y/FL20W3K2IN") ==
               {:ok, "FREQ=YEARLY;BYWEEKNO=20;BYDAY=WE;BYSETPOS=2"}
    end

    test "is the weekday and its position where a number would count something else" do
      # A position counts among the days the rule's other parts leave, and a
      # number among the weekdays of the month: the first of the 15ths that
      # are Mondays is a day, and the 15th that is a first Monday is none.
      assert written("R/2026-06-01/P1M/FL15D1K1IN") ==
               {:ok, "FREQ=MONTHLY;BYMONTHDAY=15;BYDAY=MO;BYSETPOS=1"}

      assert written("R/2026-06-01/P1Y/FL100O1K1IN") ==
               {:ok, "FREQ=YEARLY;BYYEARDAY=100;BYDAY=MO;BYSETPOS=1"}

      # In a yearly rule of several months a number counts in each of them,
      # and a position across them all. A monthly rule's period is one month.
      assert written("R/2026-06-01/P1Y/FL{3,4}M1K1IN") ==
               {:ok, "FREQ=YEARLY;BYMONTH=3,4;BYDAY=MO;BYSETPOS=1"}

      assert written("R/2026-06-01/P1M/FL{3,4}M1K1IN") ==
               {:ok, "FREQ=MONTHLY;BYMONTH=3,4;BYDAY=1MO"}
    end

    test "is written as it was read where a position would count something else" do
      for rrule <- ["FREQ=YEARLY;BYMONTH=3,4;BYDAY=1MO", "FREQ=MONTHLY;BYMONTHDAY=15;BYDAY=1MO"] do
        {:ok, rule} = RRule.parse(rrule, from: ~o"2026-06-01")

        assert {rrule, RRule.to_string(rule)} == {rrule, {:ok, rrule}}
      end
    end

    test "reads as the same rule, a numbered BYDAY or a weekday and its position" do
      for text <- ["R/2026-06-01/P1W/FL3K2IN", "R/2026-06-01/P1M/FL3K2IN"] do
        rule = Tempo.from_iso8601!(text)
        {:ok, rrule} = RRule.to_string(rule)

        assert {text, RRule.parse!(rrule, from: ~o"2026-06-01")} == {text, rule}
      end
    end

    test "on several weekdays has no equivalent outside a monthly or a yearly rule" do
      {:ok, monthly} = RRule.parse("FREQ=MONTHLY;BYDAY=2MO,2WE", from: ~o"2026-06-01")
      assert RRule.to_string(monthly) == {:ok, "FREQ=MONTHLY;BYDAY=2MO,2WE"}

      {:ok, weekly} = RRule.parse("FREQ=WEEKLY;BYDAY=2MO,2WE", from: ~o"2026-06-01")
      assert {:error, %ConversionError{target: :rrule, reason: reason}} = RRule.to_string(weekly)
      assert reason =~ "a numbered BYDAY in a WEEKLY rule"
    end
  end

  describe "a position" do
    test "is written beside another part" do
      assert written("R/2026-06-01/P1M/FL{1..5}K-1IN") ==
               {:ok, "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1"}
    end

    test "with no other part is an error" do
      assert {:error, %ConversionError{target: :rrule, reason: reason}} =
               written("R/2026-06-01/P1M/FL1IN")

      assert reason =~ "BYSETPOS with no other BY part"
    end
  end
end
