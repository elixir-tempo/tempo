defmodule Tempo.Explain.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Explain
  alias Tempo.ICal
  alias Tempo.IntervalSet

  # Tests for `Tempo.Explain.explain/1` — structured prose
  # descriptions of Tempo values. Three formatters (`to_string`,
  # `to_ansi`, `to_iodata`) are exercised for the same structured
  # output.

  setup_all do
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    :ok
  end

  describe "scalar Tempo" do
    test "a year is classified :anchored with headline, span, enumeration, hint" do
      exp = Explain.explain(~o"2022Y")
      assert exp.kind == :anchored
      tags = exp.parts |> Enum.map(&elem(&1, 0))
      assert :headline in tags
      assert :span in tags
      assert :enumeration in tags
      assert :hint in tags
    end

    test "the year 2022's headline mentions the year" do
      assert Tempo.explain(~o"2022Y") =~ "2022"
    end

    test "a year-month-day's headline reads like prose" do
      assert Tempo.explain(~o"2026-06-15") =~ "June 15, 2026"
    end

    test "a datetime's headline includes the time" do
      assert Tempo.explain(~o"2026-06-15T10:30") =~ "10:30"
    end

    test "a qualified year mentions the qualifier" do
      exp = Explain.explain(~o"2022Y?")
      tags = exp.parts |> Enum.map(&elem(&1, 0))
      assert :qualification in tags

      assert Tempo.explain(~o"2022Y?") =~ "uncertain"
    end
  end

  describe "masked Tempo" do
    test "156X is classified :masked" do
      assert Explain.explain(~o"156X").kind == :masked
    end

    test "156X names the decade" do
      assert Tempo.explain(~o"156X") =~ "1560s"
    end

    test "1XXX names the millennium" do
      assert Tempo.explain(~o"1XXX") =~ ~r/millennium|century|1000s/
    end
  end

  describe "time-of-day" do
    test "T10:30 is classified :time_of_day" do
      assert Explain.explain(~o"T10:30").kind == :time_of_day
    end

    test "mentions the non-anchored nature" do
      assert Tempo.explain(~o"T10:30") =~ "non-anchored"
    end
  end

  describe "IXDTF metadata" do
    test "zoned Tempo mentions the zone" do
      paris = Tempo.from_elixir(DateTime.new!(~D[2026-06-15], ~T[10:00:00], "Europe/Paris"))
      assert Tempo.explain(paris) =~ "Europe/Paris"
    end
  end

  describe "Tempo.Duration" do
    test "classified :duration with no anchor hint" do
      exp = Explain.explain(~o"P1Y2M")
      assert exp.kind == :duration
      assert Tempo.explain(~o"P1Y2M") =~ "no anchor"
    end

    test "reads in human units" do
      assert Tempo.explain(~o"P3M") =~ "3 months"
    end
  end

  describe "Tempo.Interval" do
    test "closed interval is classified :closed_interval" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")
      assert Explain.explain(iv).kind == :closed_interval
    end

    test "open-upper interval is classified :open_upper_interval" do
      {:ok, iv} = Tempo.from_iso8601("1985/..")
      assert Explain.explain(iv).kind == :open_upper_interval
    end

    test "fully open is classified :fully_open_interval" do
      {:ok, iv} = Tempo.from_iso8601("../..")
      assert Explain.explain(iv).kind == :fully_open_interval
    end

    test "interval with metadata mentions the event summary" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")
      iv = %{iv | metadata: %{summary: "Design review", location: "Room 101"}}
      assert Tempo.explain(iv) =~ "Design review"
      assert Tempo.explain(iv) =~ "Room 101"
    end

    test "an unbounded recurrence with a BY-rule selection is explained in prose" do
      # US Election Day — the Tuesday falling on the 2nd–8th of November.
      election = ~o"R/2024Y11M1D/P1Y/FL11M{2..8}D2KN"

      assert Explain.explain(election).kind == :recurring_interval

      prose = Tempo.explain(election)
      assert prose =~ "unbounded recurrence"
      assert prose =~ "in November, on the 2nd–8th, on a Tuesday"
    end

    test "an unanchored recurrence explains its selection and names what is missing" do
      # `R/../…` has no start at all. Two sentinels spell "no endpoint" —
      # `:undefined` from the ISO 8601 parser and `nil` from the RRULE
      # parser — and only the first was recognised, so a fully described
      # rule reported "an unusual shape" and said nothing useful.
      thanksgiving = ~o"R/../P1Y/FL11M4I4KN"

      prose = Tempo.explain(thanksgiving)

      assert prose =~ "unbounded recurrence"
      assert prose =~ "in November, on the 4th Thursday"
      assert prose =~ "1 year"
      assert prose =~ "unanchored"
      refute prose =~ "unusual shape"
    end

    test "an unanchored recurrence says a bound cannot supply the anchor" do
      # The hint has to distinguish the two, because `to_interval/2`
      # accepts a `:bound` and it does not rescue an unanchored rule.
      assert {:error, %Tempo.IntervalEndpointsError{reason: :unanchored}} =
               Tempo.to_interval(~o"R/../P1W/FL1KN", bound: ~o"2026Y")

      assert Tempo.explain(~o"R/../P1W/FL1KN") =~ "not where the series starts"
    end

    test "a counted but unanchored recurrence is explained the same way" do
      prose = Tempo.explain(~o"R5/../P1Y/FL5M-1I1KN")

      assert prose =~ "recurrence of 5 occurrences"
      assert prose =~ "in May, on the last Monday"
      assert prose =~ "unanchored"
    end
  end

  describe "Tempo.IntervalSet" do
    test "empty set is classified :empty_interval_set" do
      {:ok, set} = IntervalSet.new([])
      assert Explain.explain(set).kind == :empty_interval_set
    end

    test "non-empty set previews first 3 intervals" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      X-WR-CALNAME:Work
      BEGIN:VEVENT
      UID:evt-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Standup
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = ICal.from_ical(ics)
      text = Tempo.explain(set)
      assert text =~ "IntervalSet with 1 interval"
      assert text =~ "Standup"
      assert text =~ "Work"
    end
  end

  describe "Tempo.Set" do
    test "one-of set mentions epistemic disjunction" do
      {:ok, s} = Tempo.from_iso8601("[2020Y,2021Y,2022Y]")
      assert Explain.explain(s).kind == :one_of_set
      assert Tempo.explain(s) =~ "one of"
    end
  end

  describe "formatters" do
    test "to_string produces a multi-line string" do
      exp = Explain.explain(~o"2022Y")
      text = Explain.to_string(exp)
      assert is_binary(text)
      assert String.contains?(text, "\n")
    end

    test "to_ansi produces a string with ANSI escape codes" do
      exp = Explain.explain(~o"2022Y")
      text = Explain.to_ansi(exp)
      # ANSI codes start with the escape sequence \e[ (or \x1B[).
      assert String.contains?(text, "\e[")
    end

    test "to_iodata produces tagged {atom, string} pairs" do
      exp = Explain.explain(~o"2022Y")
      parts = Explain.to_iodata(exp)
      assert Enum.all?(parts, fn {tag, text} -> is_atom(tag) and is_binary(text) end)
    end
  end

  describe "± margins" do
    test "a single year margin surfaces the margin and the grounding span" do
      explanation = Tempo.explain(~o"2000±1Y")

      assert explanation =~ "Margin: ±1 year"
      assert explanation =~ "groundings span [1999-01-01, 2002-01-01)"
    end

    test "a plural margin pluralises the unit" do
      assert Tempo.explain(~o"2000±2Y") =~
               "Margin: ±2 years — groundings span [1998-01-01, 2003-01-01)."
    end

    test "the margin is a tagged part" do
      parts = Explain.explain(~o"2000±1Y").parts
      assert Enum.any?(parts, fn {tag, _text} -> tag == :margin end)
    end

    test "a non-anchored margin states the margin without an uncomputable span" do
      non_anchored = %Tempo{
        time: [month: {6, [margin_of_error: 1]}],
        calendar: Calendrical.Gregorian
      }

      explanation = Tempo.explain(non_anchored)

      assert explanation =~ "Margin: ±1 month."
      refute explanation =~ "groundings span"
    end

    test "a value without margins has no margin part" do
      refute Enum.any?(Explain.explain(~o"2022Y").parts, fn {tag, _} -> tag == :margin end)
    end
  end

  describe "Tempo.explain/1 (top-level delegation)" do
    test "returns the string form" do
      assert Tempo.explain(~o"2022Y") == Explain.to_string(Explain.explain(~o"2022Y"))
    end
  end
end
