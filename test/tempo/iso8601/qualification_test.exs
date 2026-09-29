defmodule Tempo.Iso8601.Qualification.Test do
  use ExUnit.Case, async: true

  # ISO 8601-2:2019 §8 — qualification of date and time expressions.
  #
  # `?` marks a value uncertain (best guess), `~` approximate
  # ("circa 1850"), `%` both. §8 defines three scopes by position:
  #
  #   * §8.2.1 Complete — a qualifier at the rightmost end qualifies
  #     the entire expression (stored on `:qualification`).
  #   * §8.2.2 Group — a qualifier immediately to the right of a
  #     component qualifies that component and every coarser component
  #     to its left (stored on the `:qualifications` map).
  #   * §8.2.3 Individual — a qualifier immediately to the left of a
  #     component (implicit form) qualifies that component only.

  describe "complete qualification (§8.2.1)" do
    test "a trailing qualifier on a year is complete" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022?")
      assert tempo.qualification == :uncertain
      assert tempo.qualifications == nil
      assert Keyword.get(tempo.time, :year) == 2022
    end

    test "approximate (~) and both (%) on a year" do
      assert {:ok, approx} = Tempo.from_iso8601("1850~")
      assert approx.qualification == :approximate

      assert {:ok, both} = Tempo.from_iso8601("2022%")
      assert both.qualification == :uncertain_and_approximate
    end

    test "a trailing qualifier on a full date is complete, not day-only" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004-06-11%")
      assert tempo.qualification == :uncertain_and_approximate
      assert tempo.qualifications == nil
    end

    test "a trailing qualifier on a year-month is complete" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06?")
      assert tempo.qualification == :uncertain
      assert tempo.qualifications == nil
      assert Keyword.get(tempo.time, :month) == 6
    end
  end

  describe "group qualification (§8.2.2)" do
    # A qualifier to the right of a component applies to it and every
    # coarser component to its left.

    test "~ right of the month qualifies the month and the year" do
      assert {:ok, tempo} = Tempo.from_iso8601("2004-06~-11")
      assert tempo.qualification == nil
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
      assert tempo.qualification == nil
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
      assert tempo.qualification == :uncertain_and_approximate
      assert tempo.qualifications == nil
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

    test "leading individual plus trailing complete coexist" do
      assert {:ok, tempo} = Tempo.from_iso8601("?2022-06-15~")
      # Trailing ~ is complete; leading ? is individual on the year.
      assert tempo.qualification == :approximate
      assert tempo.qualifications == %{year: :uncertain}
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
    test "no qualification leaves both fields nil" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15")
      assert tempo.qualification == nil
      assert tempo.qualifications == nil
    end

    test "complete qualification followed by an IXDTF suffix" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15?[u-ca=hebrew]")
      assert tempo.qualification == :uncertain
      assert tempo.extended.calendar == :hebrew
    end

    test "per-endpoint qualification in an interval" do
      # A qualifier immediately after an endpoint applies to that
      # endpoint only. The two endpoints may carry different scopes.
      assert {:ok, interval} = Tempo.from_iso8601("2022/2023?")
      assert interval.__struct__ == Tempo.Interval
      assert interval.from.qualification == nil
      assert interval.to.qualification == :uncertain

      assert {:ok, interval2} = Tempo.from_iso8601("1984?/2004-06~")
      assert interval2.from.qualification == :uncertain
      # `2004-06~` — ~ right of the rightmost component → complete.
      assert interval2.to.qualification == :approximate
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
