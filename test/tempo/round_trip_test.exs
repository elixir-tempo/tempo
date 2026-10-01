defmodule Tempo.RoundTripTest do
  use ExUnit.Case, async: true

  alias Calendrical.FiscalYear
  alias Tempo.Cron
  alias Tempo.RecurrenceSet
  alias Tempo.RRule

  # Round-trip tests validate that the Tempo AST can be encoded
  # back to either of the two input formats (ISO 8601, RRULE)
  # and re-parsed to an equivalent AST.
  #
  # A successful round-trip confirms that:
  #
  #   * The AST carries all the information the input format
  #     captures (no lossy fields).
  #
  #   * The encoders produce parser-acceptable output (the two
  #     halves of each format are consistent).
  #
  # Where the re-encoded string differs byte-for-byte from the
  # input, the second round (encode → parse → encode → parse) is
  # still expected to produce byte-identical output and an
  # equivalent AST — that is the **fixed-point** property: after
  # one canonicalising round-trip the encoder settles on a stable
  # form.

  describe "ISO 8601 round-trip (parse → encode → parse)" do
    @cases [
      "2022-11-20",
      "2022-11-20T10:30:00Z",
      "2022-W24",
      "2022-W24-3",
      "2022-166",
      "R/2022-01-01/P1D",
      "R5/2022-01-01/P1M",
      "P1D/2022-01-01",
      "R/P1D/2026-12-31/F1DLT9HN",
      "R12/PT2H30M0S/20150929T153000/F2W",
      "R/../P1M/FL5K2INT9H0M",
      "../1985-04-12",
      "1985-04-12/..",
      "../..",
      "1984?/2004~",
      "156X",
      "-1XXX-XX",
      "{1960,1961,1962}",
      "[1984,1986,1988]"
    ]

    for iso <- @cases do
      test "#{iso}" do
        input = unquote(iso)
        {:ok, ast} = Tempo.from_iso8601(input)

        # First encode
        encoded = Tempo.to_iso8601!(ast)
        assert is_binary(encoded)
        assert encoded != ""

        # Fixed-point property: re-parse and re-encode must match
        # the first encode. Any deviation means the AST carries
        # state that the encoder drops.
        {:ok, ast2} = Tempo.from_iso8601(encoded)
        assert ast == ast2, "AST changed after round-trip for #{inspect(input)}"

        encoded2 = Tempo.to_iso8601!(ast2)
        assert encoded == encoded2, "encoder is not a fixed point for #{inspect(input)}"
      end
    end
  end

  describe "RRULE round-trip (parse → encode → parse)" do
    @cases [
      "FREQ=DAILY",
      "FREQ=DAILY;COUNT=10",
      "FREQ=DAILY;INTERVAL=2",
      "FREQ=WEEKLY;UNTIL=20221231",
      "FREQ=MONTHLY;BYMONTHDAY=15",
      "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH",
      "FREQ=MONTHLY;BYDAY=-1FR",
      "FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20221231",
      "FREQ=MONTHLY;BYDAY=1MO,3MO",
      "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1",
      "FREQ=YEARLY;BYMONTH=6,7,8",
      "FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30",
      "FREQ=MONTHLY;BYDAY=2FR;BYHOUR=9,17;BYMINUTE=0",
      "FREQ=MONTHLY;BYDAY=2FR;BYHOUR=9,17;BYSETPOS=-1"
    ]

    for rrule <- @cases do
      test "#{rrule}" do
        input = unquote(rrule)
        {:ok, ast} = RRule.parse(input)
        {:ok, encoded} = RRule.to_string(ast)

        {:ok, ast2} = RRule.parse(encoded)
        assert ast == ast2, "AST changed after round-trip for #{inspect(input)}"

        # Fixed-point: encoding twice should match.
        {:ok, encoded2} = RRule.to_string(ast2)
        assert encoded == encoded2, "encoder is not a fixed point for #{inspect(input)}"
      end
    end

    test "canonical RRULE ordering matches ISO 8601 semantic order" do
      # COUNT/UNTIL appears first (analog to R<count>/<to>), then
      # FREQ+INTERVAL (analog to duration), then BY* (analog to
      # /F<rule>).
      assert {:ok, "COUNT=10;FREQ=DAILY"} =
               RRule.parse!("FREQ=DAILY;COUNT=10") |> RRule.to_string()

      assert {:ok, "UNTIL=20221231;FREQ=WEEKLY"} =
               RRule.parse!("FREQ=WEEKLY;UNTIL=20221231") |> RRule.to_string()

      assert {:ok, "UNTIL=20221231;FREQ=WEEKLY;BYDAY=MO,WE,FR"} =
               RRule.parse!("FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20221231")
               |> RRule.to_string()
    end
  end

  describe "cross-format: ISO recurring interval → RRULE" do
    test "R/2022-01-01/P1D → FREQ=DAILY" do
      {:ok, ast} = Tempo.from_iso8601("R/2022-01-01/P1D")
      assert {:ok, "FREQ=DAILY"} = RRule.to_string(ast)
    end

    test "R10/2022-01-01/P1M → COUNT=10;FREQ=MONTHLY" do
      {:ok, ast} = Tempo.from_iso8601("R10/2022-01-01/P1M")
      assert {:ok, "COUNT=10;FREQ=MONTHLY"} = RRule.to_string(ast)
    end

    test "R5/2022-01-01/P2W → COUNT=5;FREQ=WEEKLY;INTERVAL=2" do
      {:ok, ast} = Tempo.from_iso8601("R5/2022-01-01/P2W")
      assert {:ok, "COUNT=5;FREQ=WEEKLY;INTERVAL=2"} = RRule.to_string(ast)
    end

    test "a start and an end step by the first occurrence's length" do
      assert {:ok, "COUNT=5;FREQ=DAILY;INTERVAL=5"} =
               "R5/2026-06-15/2026-06-20" |> Tempo.from_iso8601!() |> RRule.to_string()

      assert {:ok, "COUNT=3;FREQ=MONTHLY;INTERVAL=2"} =
               "R3/2026-01/2026-03" |> Tempo.from_iso8601!() |> RRule.to_string()

      assert {:ok, "FREQ=DAILY;INTERVAL=5"} =
               "R/2026-06-15/2026-06-20" |> Tempo.from_iso8601!() |> RRule.to_string()
    end

    test "a duration and an end are a count, not an UNTIL" do
      assert {:ok, "COUNT=5;FREQ=DAILY"} =
               "R5/P1D/2026-06-20" |> Tempo.from_iso8601!() |> RRule.to_string()

      assert {:error, %Tempo.ConversionError{target: :rrule}} =
               "R/P1D/2026-06-20" |> Tempo.from_iso8601!() |> RRule.to_string()
    end
  end

  describe "cross-format: RRULE → ISO 8601 interval" do
    test "FREQ=DAILY with DTSTART round-trips through ISO" do
      {:ok, rrule_ast} =
        RRule.parse("FREQ=DAILY;COUNT=5", from: Tempo.from_iso8601!("2022-01-01"))

      # The ISO 8601 serialisation of an RRule-produced Interval
      # should match a hand-written R5/<from>/P1D.
      assert Tempo.to_iso8601!(rrule_ast) == "R5/2022Y1M1D/P1D"
    end
  end

  describe "component qualification round-trips (ISO 8601-2 §8.3)" do
    # The explicit-form encoder emits a per-component qualifier between
    # the value and its designator (`2022Y6?M15D`), which re-parses to
    # the same `:qualifications` map.

    test "an individual qualifier is preserved through encode/decode" do
      {:ok, ast} = Tempo.from_iso8601("2022-?06-15")
      assert ast.qualifications == %{month: :uncertain}

      encoded = Tempo.to_iso8601!(ast)
      assert encoded == "2022Y6?M15D"

      {:ok, ast2} = Tempo.from_iso8601(encoded)
      assert ast2.qualifications == %{month: :uncertain}
      assert ast.time == ast2.time
    end

    test "a group qualifier round-trips as per-component explicit qualifiers" do
      # `2004-06~-11` (group: month and year approximate) encodes as
      # explicit individual qualifiers that carry the same meaning.
      {:ok, ast} = Tempo.from_iso8601("2004-06~-11")
      assert ast.qualifications == %{year: :approximate, month: :approximate}

      encoded = Tempo.to_iso8601!(ast)
      assert encoded == "2004~Y6~M11D"

      {:ok, ast2} = Tempo.from_iso8601(encoded)
      assert ast2.qualifications == %{year: :approximate, month: :approximate}
    end

    test "a complete qualifier still encodes at the rightmost end" do
      {:ok, ast} = Tempo.from_iso8601("2004-06-11%")
      assert ast.qualification == :uncertain_and_approximate

      assert Tempo.to_iso8601!(ast) == "2004Y6M11D%"
    end
  end

  describe "RRule.to_string/1 error cases (ConversionError)" do
    test "non-interval rejected with ConversionError" do
      assert {:error, %Tempo.ConversionError{target: :rrule, reason: message}} =
               RRule.to_string(Tempo.from_iso8601!("2022-06-15"))

      assert message =~ "Interval"
    end

    test "interval without duration rejected" do
      interval = %Tempo.Interval{
        from: Tempo.from_iso8601!("2022-01-01"),
        to: Tempo.from_iso8601!("2022-12-31")
      }

      assert {:error, %Tempo.ConversionError{target: :rrule, reason: message}} =
               RRule.to_string(interval)

      assert message =~ "duration"
    end

    test "interval with multi-unit duration rejected" do
      interval = %Tempo.Interval{duration: %Tempo.Duration{time: [year: 1, month: 6]}}

      assert {:error, %Tempo.ConversionError{target: :rrule, reason: message}} =
               RRule.to_string(interval)

      assert message =~ "single"
    end

    test "interval with unsupported duration unit rejected" do
      interval = %Tempo.Interval{duration: %Tempo.Duration{time: [century: 1]}}

      assert {:error, %Tempo.ConversionError{target: :rrule, reason: message}} =
               RRule.to_string(interval)

      assert message =~ "century"
    end

    test "a selection RRULE cannot express is an error naming it, never dropped" do
      for {iso, named} <- [
            {"R/2026-01-05/P1Y/FL10wN", "a calendar week (w)"},
            {"R/4662Y1M1D[u-ca=chinese]/P1Y/FL6m15DN", "a traditional month (m)"},
            {"R/2026-01-01/P1Y/FL(easter)eN", "a computed event (e)"},
            {"R/2026-01-01/P1Y/FL2027Y1M1DN", "a year (Y)"},
            {"R/2026-01-01/P1Y/FLLL2K2IN/P10DN4K2IN", "a selection window"}
          ] do
        assert {:error, %Tempo.ConversionError{target: :rrule, reason: reason}} =
                 iso |> Tempo.from_iso8601!() |> RRule.to_string()

        assert reason =~ named
      end
    end

    test "a cron rule RRULE cannot express is an error naming it, never dropped" do
      for {expression, named} <- [
            {"0 0 9 15W * *", "a nearest weekday (cron W)"},
            {"0 0 9 1 * MON", "a day of the month or of the week"}
          ] do
        {:ok, rule} = Cron.parse(expression)

        assert {:error, %Tempo.ConversionError{target: :rrule, reason: reason}} =
                 RRule.to_string(rule)

        assert reason =~ named
      end
    end

    test "RRule.to_string!/1 raises on conversion failure" do
      assert_raise Tempo.ConversionError, ~r/Interval/, fn ->
        RRule.to_string!(Tempo.from_iso8601!("2022-06-15"))
      end
    end

    test "RRule.to_string!/1 returns the string on success" do
      {:ok, interval} = Tempo.from_iso8601("R5/2022-01-01/P1D")
      assert "COUNT=5;FREQ=DAILY" = RRule.to_string!(interval)
    end
  end

  describe "to_iso8601/1 error cases (Iso8601EncodeError)" do
    test "a set, a conditional member and a value that is not Tempo's are errors naming them" do
      christmas = Tempo.from_iso8601!("R/../P1Y/FL12M25DN")
      holidays = RecurrenceSet.new!([christmas, Tempo.from_iso8601!("R/../P1Y/FL1M1DN")])
      {:ok, days} = Tempo.to_interval_set(holidays, within: Tempo.from_iso8601!("2026"))

      boxing_day =
        RecurrenceSet.keep_when(christmas,
          at: [Tempo.from_iso8601!("P1D")],
          falls_on: %{type: :public}
        )

      for {value, construct, named} <- [
            {holidays, :recurrence_set, "a set of recurrences"},
            {days, :interval_set, "a set of intervals"},
            {boxing_day, :conditional, "a conditional member"},
            {~D[2026-06-15], :value, "~D[2026-06-15]"},
            {"2026-06-15", :value, ~s("2026-06-15")},
            {"", :value, ~s(Cannot encode "")},
            {:"", :value, ~s(Cannot encode :"")},
            {nil, :value, "Cannot encode nil"}
          ] do
        assert {:error, %Tempo.Iso8601EncodeError{construct: ^construct} = error} =
                 Tempo.to_iso8601(value)

        assert Exception.message(error) =~ named
      end
    end

    test "a recurrence's end (RFC 5545 UNTIL) has no ISO 8601 form" do
      # ISO 8601 bounds a recurrence only by its count, and its start/end
      # form names the first occurrence's end, so the RRULE keeps it.
      start = Tempo.from_iso8601!("2026-01-01")

      for rule <- [
            RRule.parse!("FREQ=DAILY;UNTIL=20261231", from: start),
            RRule.parse!("FREQ=DAILY;UNTIL=20261231"),
            RRule.parse!("FREQ=DAILY;UNTIL=20261231;BYHOUR=9", from: start),
            Cron.parse!("0 0 12 * * * 2027", from: start)
          ] do
        assert {:error, %Tempo.Iso8601EncodeError{construct: :until} = error} =
                 Tempo.to_iso8601(rule)

        assert Exception.message(error) =~ "UNTIL"
        assert inspect(rule) == "#Tempo.Interval<not ISO 8601 expressible>"
      end

      assert {:ok, "UNTIL=20261231;FREQ=DAILY;BYHOUR=9"} =
               RRule.to_string(RRule.parse!("FREQ=DAILY;UNTIL=20261231;BYHOUR=9", from: start))
    end

    test "a construct with no ISO 8601 form is an error naming it, which to_iso8601!/1 raises" do
      {:ok, rule} =
        RRule.parse("FREQ=MONTHLY;BYDAY=2MO,2WE", from: Tempo.from_iso8601!("2026-01-01"))

      assert {:error, %Tempo.Iso8601EncodeError{construct: :byday} = error} =
               Tempo.to_iso8601(rule)

      assert Exception.message(error) =~ "BYDAY=2MO,2WE"

      assert_raise Tempo.Iso8601EncodeError, ~r/BYDAY=2MO,2WE/, fn ->
        Tempo.to_iso8601!(rule)
      end

      assert Tempo.to_iso8601!(Tempo.from_iso8601!("2022-06-15")) == "2022Y6M15D"
    end
  end

  defmodule SundayStart do
    use Calendrical.Base.Month,
      month_of_year: 1,
      min_days_in_first_week: 1,
      day_of_week: Calendrical.sunday()
  end

  describe "a value in another calendar reads back in it, however it was made" do
    defp read_back(value), do: value |> Tempo.to_iso8601!() |> Tempo.from_iso8601!()

    test "converted, built from an Elixir date, built with a calendar and parsed with one" do
      for value <- [
            Tempo.to_calendar!(Tempo.from_iso8601!("2026-06-15"), Calendrical.Hebrew),
            Tempo.from_elixir(Date.new!(5786, 9, 30, Calendrical.Hebrew)),
            Tempo.new!(year: 5786, month: 9, day: 30, calendar: Calendrical.Hebrew),
            Tempo.from_iso8601!("5786-09-30", Calendrical.Hebrew)
          ] do
        assert Tempo.to_iso8601!(value) == "5786Y9M30D[u-ca=hebrew]"

        back = read_back(value)
        assert {back.calendar, back.time} == {Calendrical.Hebrew, value.time}
      end
    end

    test "a calendar sharing its CLDR type with another is written by the name that reads back" do
      julian = Tempo.to_calendar!(Tempo.from_iso8601!("2026-06-15"), Calendrical.Julian)
      assert Tempo.to_iso8601!(julian) == "2026Y6M2D[u-ca=julian]"
      assert read_back(julian).calendar == Calendrical.Julian

      # The Vietnamese calendar's CLDR type is the Chinese calendar's.
      vietnamese = Tempo.to_calendar!(Tempo.from_iso8601!("2026-06-15"), Calendrical.Vietnamese)
      assert read_back(vietnamese).calendar == Calendrical.Vietnamese
    end

    test "a zoned value and an interval" do
      zoned =
        Tempo.new!(
          year: 5786,
          month: 9,
          day: 30,
          hour: 10,
          calendar: Calendrical.Hebrew,
          zone: "Asia/Jerusalem"
        )

      back = read_back(zoned)

      assert {back.calendar, back.time, back.extended.zone_id} ==
               {Calendrical.Hebrew, zoned.time, "Asia/Jerusalem"}

      interval =
        Tempo.to_calendar!(Tempo.from_iso8601!("2026-06-15/2026-06-20"), Calendrical.Hebrew)

      assert Tempo.to_iso8601!(interval) == "5786Y9M30D/10M5D[u-ca=hebrew]"
      assert inspect(interval) == ~s|~o"5786Y9M30D/10M5D[u-ca=hebrew]"|

      back = read_back(interval)
      assert {back.from.calendar, back.to.calendar} == {Calendrical.Hebrew, Calendrical.Hebrew}
    end

    test "an annotation naming another calendar than the value's is not written" do
      # An explicit calendar wins over the parsed `[u-ca=hebrew]`, so the
      # value is the Gregorian year 5786.
      value = Tempo.from_iso8601!("5786-09-30[u-ca=hebrew]", Calendrical.Gregorian)

      assert Tempo.to_iso8601!(value) == "5786Y9M30D"
      assert read_back(value).calendar == Calendrical.Gregorian
    end

    test "a calendar that numbers its days as the Gregorian does needs no name" do
      sunday = Tempo.from_iso8601!("2026-08-16", SundayStart)

      assert Tempo.to_iso8601!(sunday) == "2026Y8M16D"
    end

    test "a calendar ISO 8601 cannot name is an error, and inspect names its module" do
      {:ok, fiscal} = FiscalYear.calendar_for(:AU)
      {:ok, quarter} = Tempo.from_elixir(fiscal.quarter(2027, 1))

      assert {:error, %Tempo.Iso8601EncodeError{construct: :calendar, calendar: ^fiscal} = error} =
               Tempo.to_iso8601(quarter)

      assert Exception.message(error) =~ inspect(fiscal)
      assert_raise Tempo.Iso8601EncodeError, fn -> Tempo.to_iso8601!(quarter) end

      {read_back, _binding} = Code.eval_string(inspect(quarter))
      assert read_back == quarter
    end
  end
end
