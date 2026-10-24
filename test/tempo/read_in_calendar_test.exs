defmodule Tempo.ReadInCalendarTest do
  use ExUnit.Case, async: true

  # Decision 40: a rule with no end converted to another calendar is selected
  # in its own and read in the other, so one set holds rules of several
  # calendars, each read in the set's.

  import Tempo.Sigils

  alias Tempo.{Interval, IntervalSet, RecurrenceSet}

  # Eid al-Fitr, 1 Shawwal in the Umm al-Qura calendar, and Saudi National
  # Day, 23 September.
  defp eid,
    do:
      Tempo.every!(~o"P1Y",
        select: [month: 10, day: 1],
        calendar: Calendrical.Islamic.UmmAlQura,
        metadata: %{name: "Eid al-Fitr"}
      )

  defp national_day,
    do: Tempo.every!(~o"P1Y", select: [month: 9, day: 23], metadata: %{name: "National Day"})

  defp gregorian_dates(set) do
    IntervalSet.map(set, fn span ->
      {:ok, date} = span |> Interval.from() |> Tempo.to_date()
      {:ok, gregorian} = Date.convert(date, Calendar.ISO)
      gregorian
    end)
  end

  describe "a set of rules in two calendars" do
    test "gives each rule's occurrences in the set's calendar, with their metadata" do
      {:ok, holidays} = RecurrenceSet.new([national_day(), eid()])
      {:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")

      # 1 Shawwal 1447 is 20 March 2026.
      assert Tempo.to_iso8601!(this_year) == "{2026Y3M20D/2026Y3M20D,2026Y9M23D/2026Y9M23D}"

      assert IntervalSet.map(this_year, &Tempo.metadata(&1).name) == [
               "Eid al-Fitr",
               "National Day"
             ]
    end

    test "is read in its first member's calendar, whichever that is" do
      {:ok, holidays} = RecurrenceSet.new([eid(), national_day()])
      {:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")

      assert this_year.calendar == Calendrical.Islamic.UmmAlQura
      assert gregorian_dates(this_year) == [~D[2026-03-20], ~D[2026-09-23]]
    end

    test "is asked of a day and stepped over as days off" do
      {:ok, holidays} = RecurrenceSet.new([national_day(), eid()])

      assert Tempo.overlaps?(~o"2026-03-20", holidays, within: ~o"2026-03-20")
      refute Tempo.overlaps?(~o"2026-03-19", holidays, within: ~o"2026-03-19")

      # Thursday 19 March 2026; Friday and Saturday are the weekend in Saudi
      # Arabia, and Eid falls on the Friday.
      assert Tempo.next_workday(~o"2026-03-19", Tempo.workdays!(:SA, except: holidays)) ==
               {:ok, ~o"2026-03-22"}
    end
  end

  # An expression with no year is on a cycle, which is a cycle of another
  # calendar only where it names no date (law 4). The Hebrew calendar's
  # weeks begin on Sunday, so its Wednesday is day 4 (decision 80).
  describe "to_calendar/2 of an expression with no year" do
    test "keeps a time of day and its form" do
      for text <- ["T10H", "T09/T17", "T22H/T2H", "{T09,T17}", "R3/T22H/PT1H", "LT10HN"] do
        value = Tempo.from_iso8601!(text)
        {:ok, converted} = Tempo.to_calendar(value, Calendrical.Hebrew)

        assert Tempo.to_iso8601!(converted) == Tempo.to_iso8601!(value) <> "[u-ca=hebrew]"
      end
    end

    test "numbers a day of the week as the other calendar numbers it" do
      assert Tempo.to_calendar(~o"3K", Calendrical.Hebrew) == {:ok, ~o"4K[u-ca=hebrew]"}
      assert Tempo.to_calendar(~o"1K/5K", Calendrical.Hebrew) == {:ok, ~o"2K/6K[u-ca=hebrew]"}
      assert Tempo.to_calendar(~o"{1K,3K}", Calendrical.Hebrew) == {:ok, ~o"{2K,4K}[u-ca=hebrew]"}

      assert Tempo.to_calendar(~o"R3/3K/P1W", Calendrical.Hebrew) ==
               {:ok, ~o"R3/4K/P1W[u-ca=hebrew]"}

      assert Tempo.to_calendar(~o"L1K2IN", Calendrical.Hebrew) == {:ok, ~o"L2K2IN[u-ca=hebrew]"}
      assert Tempo.to_week_start(~o"1K", 7) == {:ok, ~o"2K[u-fw=sun]"}
      assert Tempo.to_calendar(~o"4K[u-ca=hebrew]", Calendar.ISO) == {:ok, ~o"3K"}
    end

    test "that names a date needs a year" do
      for text <- [
            "6M15D",
            "15D",
            "6M",
            "25W",
            "200O",
            "6M15DT10H",
            "X*Y6M",
            "L6M15DN",
            "L(easter)eN"
          ] do
        assert {:error, %Tempo.ConversionError{reason: :needs_a_year}} =
                 Tempo.to_calendar(Tempo.from_iso8601!(text), Calendrical.Hebrew),
               text
      end
    end
  end

  describe "to_calendar/2 of a rule with no end" do
    test "converts it as a rule, and back to its own calendar is the rule" do
      {:ok, in_gregorian} = Tempo.to_calendar(eid(), Calendar.ISO)

      assert in_gregorian.calendar == Calendar.ISO
      assert Tempo.to_calendar(in_gregorian, Calendrical.Islamic.UmmAlQura) == {:ok, eid()}

      assert gregorian_dates(Tempo.to_interval!(in_gregorian, within: ~o"2025/2027")) ==
               [~D[2025-03-30], ~D[2026-03-20], ~D[2027-03-09]]
    end

    test "has no ISO 8601 text" do
      {:ok, in_gregorian} = Tempo.to_calendar(eid(), Calendar.ISO)

      assert {:error, %Tempo.Iso8601EncodeError{reason: :read_in_another_calendar}} =
               Tempo.to_iso8601(in_gregorian)

      {:ok, holidays} = RecurrenceSet.new([national_day(), eid()])

      assert {:error, %Tempo.Iso8601EncodeError{reason: :read_in_another_calendar}} =
               Tempo.to_iso8601(holidays)
    end

    test "is answered by every function, or refused by name" do
      {:ok, in_gregorian} = Tempo.to_calendar(eid(), Calendar.ISO)

      unnamed =
        for {name, arity} <- Tempo.__info__(:functions),
            arity in 1..2,
            name not in [:new, :every, :selection, :one_of, :from_elixir, :from_iso8601, :parse],
            name not in [:parse_duration, :now, :today, :workdays, :weekends, :map, :try_map],
            name not in [:sigil_o, :sigil_TEMPO, :__struct__],
            not String.ends_with?(Atom.to_string(name), "!"),
            arguments = if(arity == 1, do: [in_gregorian], else: [in_gregorian, ~o"2026"]),
            outcome = outcome(name, arguments),
            not named?(outcome),
            do: {name, arity, outcome}

      assert [] = unnamed
    end
  end

  defp outcome(name, arguments) do
    {:returned, apply(Tempo, name, arguments)}
  rescue
    exception -> {:raised, exception}
  end

  defp named?({:raised, %module{}}),
    do: module == ArgumentError or String.starts_with?(inspect(module), "Tempo.")

  defp named?({:returned, _answer}), do: true
end
