defmodule Tempo.Iso8601.Qualification.Test do
  use ExUnit.Case, async: true

  # ISO 8601-2:2019 §8 — qualification of date and time expressions.
  #
  # `?` marks a value uncertain (best guess), `~` approximate
  # ("circa 1850"), `%` both. §8 defines three scopes by position:
  #
  #   * §8.2.1 Complete — a qualifier at the rightmost end qualifies
  #     the entire expression, which is each of its components.
  #   * §8.2.2 Group — a qualifier immediately to the right of a
  #     component qualifies that component and every coarser component
  #     to its left.
  #   * §8.2.3 Individual — a qualifier immediately to the left of a
  #     component (implicit form) qualifies that component only.
  #
  # Each is held one way, per component in the `:qualifications` map, so
  # that two texts of one meaning (§8.2.4) are one value, and
  # `Tempo.qualification/1` reads the qualifier every component carries.

  describe "complete qualification (§8.2.1)" do
    test "a trailing qualifier on a year is complete" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022?")
      assert Tempo.qualification(tempo) == :uncertain
      assert tempo.qualifications == %{year: :uncertain}
      assert Keyword.get(tempo.time, :year) == 2022
    end

    test "approximate (~) and both (%) on a year" do
      assert {:ok, approx} = Tempo.from_iso8601("1850~")
      assert Tempo.qualification(approx) == :approximate

      assert {:ok, both} = Tempo.from_iso8601("2022%")
      assert Tempo.qualification(both) == :uncertain_and_approximate
    end

    test "a trailing qualifier on a full date is complete, not day-only" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004-06-11%")
      assert Tempo.qualification(tempo) == :uncertain_and_approximate

      assert tempo.qualifications == %{
               year: :uncertain_and_approximate,
               month: :uncertain_and_approximate,
               day: :uncertain_and_approximate
             }
    end

    test "a trailing qualifier on a year-month is complete" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06?")
      assert Tempo.qualification(tempo) == :uncertain
      assert tempo.qualifications == %{year: :uncertain, month: :uncertain}
      assert Keyword.get(tempo.time, :month) == 6
    end
  end

  describe "group qualification (§8.2.2)" do
    # A qualifier to the right of a component applies to it and every
    # coarser component to its left.

    test "~ right of the month qualifies the month and the year" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004-06~-11")
      assert Tempo.qualification(tempo) == nil
      assert tempo.qualifications == %{year: :approximate, month: :approximate}
      # The day, to the right, is untouched.
      refute Map.has_key?(tempo.qualifications, :day)
    end

    test "? right of the year qualifies the year only (nothing to its left)" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004?-06-11")
      assert tempo.qualifications == %{year: :uncertain}
    end
  end

  describe "individual qualification (§8.2.3)" do
    # An implicit-form qualifier to the left of a component qualifies
    # that component only.

    test "left of the month qualifies the month only" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004-?06-11")
      assert tempo.qualifications == %{month: :uncertain}
    end

    test "left of the day qualifies the day only" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004-06-?11")
      assert tempo.qualifications == %{day: :uncertain}
    end

    test "a leading qualifier qualifies the leftmost component (the year)" do
      assert {:ok, tempo} = Tempo.from_iso8601("?2004-06-11")
      assert Tempo.qualification(tempo) == nil
      assert tempo.qualifications == %{year: :uncertain}
    end

    test "a leading qualifier on a bare year qualifies the year" do
      assert {:ok, tempo} = Tempo.from_iso8601("?1985")
      assert tempo.qualifications == %{year: :uncertain}
    end
  end

  describe "explicit (designator) form (§8.3)" do
    # In explicit form a qualifier sits between a component's value and
    # its designator, and is always individual (§8.2.3) — the
    # designator makes each component self-delimiting.

    test "qualifier before the year designator" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004~Y6M11D")
      assert tempo.qualifications == %{year: :approximate}
    end

    test "qualifier before the month designator" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004Y6?M11D")
      assert tempo.qualifications == %{month: :uncertain}
    end

    test "qualifier before the day designator" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004Y6M11%D")
      assert tempo.qualifications == %{day: :uncertain_and_approximate}
    end

    test "each component qualified independently" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004~Y6?M11%D")

      assert tempo.qualifications == %{
               year: :approximate,
               month: :uncertain,
               day: :uncertain_and_approximate
             }
    end

    test "a trailing qualifier after the last designator is still complete" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004Y6M11D%")
      assert Tempo.qualification(tempo) == :uncertain_and_approximate
      assert tempo == Tempo.from_iso8601!("2004%Y6%M11%D")
    end
  end

  describe "combinations" do
    test "each component qualified independently" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022?-?06-%15")

      assert tempo.qualifications == %{
               year: :uncertain,
               month: :uncertain,
               day: :uncertain_and_approximate
             }
    end

    test "leading individual plus trailing complete combine on the year" do
      assert {:ok, tempo} = Tempo.from_iso8601("?2022-06-15~")
      # Trailing ~ is complete, and so each component's; leading ? is
      # individual on the year, which is then both.
      assert Tempo.qualification(tempo) == nil

      assert tempo.qualifications == %{
               year: :uncertain_and_approximate,
               month: :approximate,
               day: :approximate
             }
    end

    test "? and ~ on the same component combine to %" do
      # Group ~ on the month (and year) plus individual ? on the month.
      assert {:ok, tempo} = Tempo.from_iso8601("2004-?06~-11")
      assert tempo.qualifications == %{year: :approximate, month: :uncertain_and_approximate}
    end
  end

  describe "canonical output (§8.2.4)" do
    # When every present component shares one qualifier, the compact
    # complete form is preferred over per-component qualifiers. (The
    # explicit output form has no group representation, so complete is
    # the only available collapse.)

    test "all components with the same qualifier collapse to complete" do
      {:ok, tempo} = Tempo.from_iso8601("2004%Y6%M11%D")

      assert tempo.qualifications == %{
               year: :uncertain_and_approximate,
               month: :uncertain_and_approximate,
               day: :uncertain_and_approximate
             }

      assert Tempo.to_iso8601!(tempo) == "2004Y6M11D%"
    end

    test "a partially-qualified date keeps per-component qualifiers" do
      {:ok, tempo} = Tempo.from_iso8601("2004-06~-11")
      # year + month approximate, day unqualified → no collapse.
      assert Tempo.to_iso8601!(tempo) == "2004~Y6~M11D"
    end

    test "mixed qualifiers stay per-component" do
      {:ok, tempo} = Tempo.from_iso8601("2022?-?06-%15")
      assert Tempo.to_iso8601!(tempo) == "2022?Y6?M15%D"
    end
  end

  describe "explicit BC year qualification (§8.3)" do
    test "a qualifier on an explicit BC year parses" do
      {:ok, tempo} = Tempo.from_iso8601("2004~YB")
      assert Keyword.get(tempo.time, :year) == -2003
      assert tempo.qualifications == %{year: :approximate}
    end

    test "an unqualified explicit BC year is unchanged" do
      {:ok, tempo} = Tempo.from_iso8601("2004YB")
      assert Keyword.get(tempo.time, :year) == -2003
      assert tempo.qualifications == nil
    end
  end

  describe "interaction with other features" do
    test "no qualifier leaves the value unqualified" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15")
      assert Tempo.qualification(tempo) == nil
      assert tempo.qualifications == nil
    end

    test "complete qualification followed by an IXDTF suffix" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15?[u-ca=hebrew]")
      assert Tempo.qualification(tempo) == :uncertain
      assert tempo.calendar == Calendrical.Hebrew
    end

    test "per-endpoint qualification in an interval" do
      # A qualifier immediately after an endpoint applies to that
      # endpoint only. The two endpoints may carry different scopes.
      assert {:ok, interval} = Tempo.from_iso8601("2022/2023?")
      assert interval.__struct__ == Tempo.Interval
      assert Tempo.qualification(interval.from) == nil
      assert Tempo.qualification(interval.to) == :uncertain

      assert {:ok, interval2} = Tempo.from_iso8601("1984?/2004-06~")
      assert Tempo.qualification(interval2.from) == :uncertain
      # `2004-06~` — ~ right of the rightmost component → complete.
      assert Tempo.qualification(interval2.to) == :approximate
    end
  end

  # ISO 8601-2 §8.2.4 names texts that "convey the same meaning". Each was a
  # value of its own, the complete form held on the value and the others per
  # component, so two of one meaning were not equal and were walked two ways
  # (decided 2026-10-04: a qualification is held per component alone).
  describe "one meaning is one value (§8.2.4)" do
    test "the standard's own pairs read as one value" do
      for {preferred, other} <- [
            {"2015-02-28?", "2015-02?-?28"},
            {"2015-02?-28", "?2015-?02-28"},
            {"2015-02?-28", "2015-?02?-28"},
            {"2015-02%-28", "%2015-%02-28"},
            {"2026?", "?2026"},
            {"2026?", "2026?Y"},
            {"2004Y6M11D%", "2004%Y6%M11%D"}
          ] do
        assert Tempo.from_iso8601!(preferred) == Tempo.from_iso8601!(other), preferred
      end
    end

    test "is written in the preferred form and read back as itself" do
      for text <- ["2026?", "?2026", "2026-06?", "2026-06-15~", "2004-06~-11", "2004-?06-11"] do
        value = Tempo.from_iso8601!(text)
        assert Tempo.from_iso8601!(Tempo.to_iso8601!(value)) == value, text
      end

      assert Tempo.to_iso8601!(Tempo.from_iso8601!("?2026")) == "2026Y?"
      assert Tempo.to_iso8601!(Tempo.from_iso8601!("2015-02?-?28")) == "2015Y2M28D?"
    end

    test "a unit a walk adds is not qualified" do
      uncertain_year = Tempo.from_iso8601!("2026?")

      for value <- [uncertain_year, Tempo.from_iso8601!("?2026")] do
        assert [january | _rest] = Enum.to_list(value)
        assert Tempo.qualification(january, :year) == :uncertain
        assert Tempo.qualification(january, :month) == nil
        assert Tempo.to_iso8601!(january) == "2026?Y1M"
      end
    end

    test "an operation that drops a unit drops its qualifier" do
      uncertain_month = Tempo.from_iso8601!("2015-?02-28")
      assert Tempo.trunc(uncertain_month, :year) == Tempo.from_iso8601!("2015")

      uncertain_day = Tempo.from_iso8601!("2015-02-28?")
      assert Tempo.trunc(uncertain_day, :month) == Tempo.from_iso8601!("2015-02?")
      assert Tempo.round(uncertain_day, :month) == Tempo.from_iso8601!("2015-03?")

      {date, time} = Tempo.split(Tempo.from_iso8601!("2015-02-28T10:30?"))
      assert date == Tempo.from_iso8601!("2015-02-28?")
      assert time == Tempo.from_iso8601!("T10:30?")
    end

    test "a value placed on another brings its own qualifiers" do
      {:ok, placed} = Tempo.at(Tempo.from_iso8601!("2026-06-15?"), Tempo.from_iso8601!("T10"))

      assert Tempo.qualification(placed, :day) == :uncertain
      assert Tempo.qualification(placed, :hour) == nil

      {:ok, at_about_ten} =
        Tempo.at(Tempo.from_iso8601!("2026-06-15"), Tempo.from_iso8601!("T10~"))

      assert at_about_ten.qualifications == %{hour: :approximate}
    end

    test "a date written again in other units is qualified in each of them" do
      assert Tempo.from_iso8601!("2026-W25-1?") == Tempo.from_iso8601!("2026-06-15?")
      assert Tempo.from_iso8601!("2026-166?") == Tempo.from_iso8601!("2026-06-15?")
    end

    test "an interval's end is qualified as it is written in full" do
      {:ok, june} = Tempo.to_interval(Tempo.from_iso8601!("2026-06?"))

      assert Tempo.to_iso8601!(june) == "2026Y6M?/7M?"
      assert Tempo.from_iso8601!("2026Y6M?/7M?") == Tempo.from_iso8601!("2026-06?/2026-07?")
      assert Tempo.from_iso8601!("2026?Y6M/7M") == Tempo.from_iso8601!("2026?Y6M/2026?Y7M")
      assert Tempo.from_iso8601!("2026-06/07?") == Tempo.from_iso8601!("2026-06/2026-07?")
    end
  end

  describe "qualification/1 and qualification/2" do
    test "read the qualifier of a whole value and of one component" do
      whole = Tempo.from_iso8601!("2004-06-11~")
      group = Tempo.from_iso8601!("2004-06~-11")

      assert Tempo.qualification(whole) == :approximate
      assert Tempo.qualification(group) == nil
      assert Tempo.qualification(group, :year) == :approximate
      assert Tempo.qualification(group, :month) == :approximate
      assert Tempo.qualification(group, :day) == nil
      assert Tempo.qualification(Tempo.from_iso8601!("2004-06-11"), :day) == nil
      assert Tempo.qualification(group, :hour) == nil
    end

    test "new/1 qualifies each component it is given" do
      {:ok, about_june} = Tempo.new(year: 2026, month: 6, qualification: :approximate)

      assert Tempo.qualification(about_june) == :approximate
      assert about_june == Tempo.from_iso8601!("2026-06~")
    end
  end

  describe "bounded interval semantics are unchanged" do
    # Qualification is metadata; it does not shift the interval bounds.
    test "uncertain year still spans the whole year" do
      {:ok, plain} = Tempo.from_iso8601("2022")
      {:ok, uncertain} = Tempo.from_iso8601("2022?")
      assert plain.time == uncertain.time
    end
  end
end
