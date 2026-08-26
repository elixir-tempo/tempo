defmodule Tempo.CalendarWeekdayTest do
  @moduledoc """
  Weekday semantics across calendars on Calendrical ≥ 1.3, which
  numbers days of the week per each calendar's own tradition (Hebrew
  and Islamic weeks run Sunday–Saturday, Persian Saturday–Friday).
  Tempo's weekend/workday classification converts to `Calendar.ISO`
  first, so it is immune to the native numbering; `beginning_of_week/1`
  deliberately follows the value's own calendar.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  # 2026-08-26 is a Wednesday; 2026-08-29 a Saturday; 2026-08-28 a Friday.

  describe "weekend classification is immune to native weekday numbering" do
    test "a Hebrew Wednesday is a workday and a Hebrew Saturday a weekend day" do
      {:ok, wednesday} = Tempo.to_calendar(~o"2026-08-26", Calendrical.Hebrew)
      {:ok, saturday} = Tempo.to_calendar(~o"2026-08-29", Calendrical.Hebrew)

      refute Tempo.weekend?(wednesday)
      assert Tempo.weekend?(saturday)
    end

    test "an Islamic Friday is the Saudi weekend" do
      {:ok, friday} = Tempo.to_calendar(~o"2026-08-28", Calendrical.Islamic.Civil)

      assert Tempo.weekend?(friday, :SA)
      refute Tempo.weekend?(friday, :US)
    end

    test "classification agrees across the calendar conversion" do
      {:ok, hebrew} = Tempo.to_calendar(~o"2026-08-29", Calendrical.Hebrew)
      assert Tempo.weekend?(hebrew) == Tempo.weekend?(~o"2026-08-29")
    end
  end

  describe "beginning_of_week follows the value's own calendar" do
    test "a Hebrew week begins on Sunday, a Gregorian week on Monday" do
      {:ok, hebrew_wednesday} = Tempo.to_calendar(~o"2026-08-26", Calendrical.Hebrew)

      # Gregorian: back to Monday 2026-08-24.
      assert Tempo.day(Tempo.beginning_of_week(~o"2026-08-26")) == 24

      # Hebrew: 13 Elul 5786 rolls back to Sunday 10 Elul.
      hebrew_sunday = Tempo.beginning_of_week(hebrew_wednesday)
      assert Tempo.day(hebrew_sunday) == 10
      assert hebrew_sunday.calendar == Calendrical.Hebrew
    end
  end

  describe "Hebrew calendar weeks parse and materialise" do
    # Enabled by Calendrical 1.3's week_of_year/weeks_in_year for the
    # Hebrew and Islamic calendars.
    test "a Hebrew week is a week-resolution span in its own calendar" do
      {:ok, week} = Tempo.from_iso8601("5786-W03", Calendrical.Hebrew)
      {:ok, interval} = Tempo.to_interval(week)

      assert week.time[:week] == 3
      assert interval.from.calendar == Calendrical.Hebrew
      assert interval.to.time[:week] == 4
    end

    test "a Hebrew week compares with Gregorian values across calendars" do
      {:ok, week} = Tempo.from_iso8601("5786-W03", Calendrical.Hebrew)

      assert Tempo.relation(~o"2026-08-26", week) in [
               :precedes,
               :preceded_by,
               :during,
               :meets,
               :met_by
             ]
    end
  end
end
