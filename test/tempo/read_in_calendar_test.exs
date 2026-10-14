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

      assert unnamed == []
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
