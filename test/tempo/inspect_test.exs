defmodule Tempo.Iso8601.InspectTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  test "Inspect" do
    assert inspect(Tempo.from_iso8601!("2022Y12M31D")) == "~o\"2022Y12M31D\""
    assert inspect(Tempo.from_iso8601!("2022Y12M31D1H10M59S")) == "~o\"2022Y12M31DT1H10M59S\""
  end

  test "Inspect with groups" do
    assert inspect(Tempo.from_iso8601!("2022Y3G4DU")) == "~o\"2022Y3G4DU\""
  end

  test "Inspect with other calendars" do
    assert inspect(Tempo.from_iso8601!("2022Y3G4WU", Calendrical.ISOWeek)) ==
             "~o\"2022Y3G4WU\"W"
  end

  test "Inspect interval" do
    assert inspect(Tempo.from_iso8601!("2022Y2M/4M")) == "~o\"2022Y2M/4M\""
  end

  test "Inspect interval whose end omits higher order components" do
    # ISO 8601-1 §5.5.1 — the omitted components are taken from the
    # start, so the end is a fully anchored value and inspects as one.
    assert inspect(Tempo.from_iso8601!("2022Y2M/4M")) == "~o\"2022Y2M/4M\""
  end

  test "Inspect duration" do
    assert inspect(Tempo.from_iso8601!("P2022Y2M1Y")) == "~o\"P2022Y2M1Y\""
    assert inspect(Tempo.from_iso8601!("P2022Y")) == "~o\"P2022Y\""
  end

  test "Inspect set" do
    assert inspect(Tempo.from_iso8601!("{2022Y,2021Y,2021Y12M}")) ==
             "~o\"{2022Y,2021Y,2021Y12M}\""
  end

  test "Groups with sets" do
    assert inspect(~o"{1,4,7..9}G1YU") == "~o\"{1,4,7..9}G1YU\""
    assert inspect(~o"{1,4,7..9}G2YU3M1D") == "~o\"{1,4,7..9}G2YU3M1D\""
  end

  test "Repeat rule" do
    assert inspect(~o"R12/2015Y9M29DT14H0M0S/PT1H30M0S/F2W") ==
             "~o\"R12/2015Y9M29DT14H0M0S/PT1H30M0S/F2W\""

    assert inspect(~o"R/2018-08-08/P1D/F1YL{3,8}M8DN") ==
             "~o\"R/2018Y8M8D/P1D/F1YL{3,8}M8DN\""

    assert inspect(~o"R/2018-09-05/P1D/F1YL9M3K1IN") ==
             "~o\"R/2018Y9M5D/P1D/F1YL9M3K1IN\""

    assert inspect(~o"R/2018Y1M/P1M/F3M") ==
             "~o\"R/2018Y1M/P1M/F3M\""

    assert inspect(~o"R/2018Y1M1D/P1D/F3M") ==
             "~o\"R/2018Y1M1D/P1D/F3M\""

    assert inspect(~o"R/2018Y1M1DT0M/PT10M/F1M") ==
             "~o\"R/2018Y1M1DT0H0M/PT10M/F1M\""

    assert inspect(~o"R/2018-08-01T01:02:03/PT5M/F1D") ==
             "~o\"R/2018Y8M1DT1H2M3S/PT5M/F1D\""

    assert inspect(~o"R/2018Y8M1DT1H/P1D/F2ML{1,3}DN") ==
             "~o\"R/2018Y8M1DT1H/P1D/F2ML{1,3}DN\""
  end

  test "Repeat rule with time after selector" do
    assert inspect(~o"R/2018-08-01T10:20:00/PT10M/F1ML{1,10}DT10H20M0SN") ==
             "~o\"R/2018Y8M1DT10H20M0S/PT10M/F1ML{1,10}DT10H20M0SN\""

    assert inspect(~o"R/20150104T083000/PT15M00S/F2YL1M1KT{8,9}H30MN") ==
             "~o\"R/2015Y1M4DT8H30M0S/PT15M0S/F2YL1M1KT{8..9}H30MN\""
  end

  test "Dates with masks" do
    assert inspect(~o"2023-WX{2,4,6,8,0}") == "~o\"2023YX{0,2,4,6,8}W\""
    assert inspect(~o"2023YX{2,4,6,8,0}W") == "~o\"2023YX{0,2,4,6,8}W\""
  end

  test "Dates with stepped ranges" do
    # 2023 has 52 ISO 8601 weeks.
    assert inspect(~o"2023Y{1..-1//2}W") ==
             "~o\"2023Y{1..52//2}W\""

    assert inspect(~o"R/2018-08-01T10:20:00/PT10M/F1ML{1..10//2}DT10H20M0SN") ==
             "~o\"R/2018Y8M1DT10H20M0S/PT10M/F1ML{1..10//2}DT10H20M0SN\""
  end

  test "Unspecified digits" do
    assert inspect(~o"2052Y1MXD") ==
             "~o\"2052Y1MXD\""

    assert inspect(~o"195XY") ==
             "~o\"195XY\""

    assert inspect(~o"1390YXXM") ==
             "~o\"1390YXXM\""

    assert inspect(~o"2052Y1MX*D") ==
             "~o\"2052Y1MX*D\""

    assert inspect(~o"XXXYX*MXD") ==
             "~o\"XXXYX*MXD\""

    assert inspect(~o"X*Y12M28D") ==
             "~o\"X*Y12M28D\""
  end

  describe "Inspect preserves IXDTF zones per endpoint" do
    # The interval sigil must round-trip with zone info on each
    # endpoint. Previously, `%Tempo.Interval{}` inspect stripped
    # `[zone]` suffixes because `inspect_value/1` for `%Tempo{}`
    # ignored `:extended`.

    test "standalone Tempo with a zone preserves [zone]" do
      {:ok, t} = Tempo.from_iso8601("2011-12-29T12:00:00[Pacific/Apia]")
      assert inspect(t) == "~o\"2011Y12M29DT12H0M0S[Pacific/Apia]\""
    end

    test "Interval with one shared zone writes it once, at the end" do
      # IXDTF binds the suffix to the interval's end and
      # `propagate_endpoint_frame/2` flows it back onto a floating
      # `from`, so repeating it on both endpoints says nothing extra.
      {:ok, from} = Tempo.from_iso8601("2011-12-29T12:00:00[Pacific/Apia]")
      {:ok, to} = Tempo.from_iso8601("2011-12-31T12:00:00[Pacific/Apia]")
      iv = %Tempo.Interval{from: from, to: to}

      assert inspect(iv) == "~o\"2011Y12M29DT12H0M0S/31DT12H0M0S[Pacific/Apia]\""
    end

    test "the single-suffix form re-parses to the same value" do
      both =
        Tempo.from_iso8601!("2011-12-29T12:00:00[Pacific/Apia]/2011-12-31T12:00:00[Pacific/Apia]")

      once = Tempo.from_iso8601!("2011-12-29T12:00:00/2011-12-31T12:00:00[Pacific/Apia]")

      assert both == once
      assert Tempo.from_iso8601!(Tempo.to_iso8601!(both)) == both
    end

    test "Interval with mixed zones shows each endpoint's zone" do
      {:ok, from} = Tempo.from_iso8601("2026-06-15T10:00:00[Europe/Paris]")
      {:ok, to} = Tempo.from_iso8601("2026-06-15T17:00:00[America/New_York]")
      iv = %Tempo.Interval{from: from, to: to}

      assert inspect(iv) ==
               "~o\"2026Y6M15DT10H0M0S[Europe/Paris]/T17H0M0S[America/New_York]\""
    end

    test "Interval with one shared calendar writes [u-ca=…] once, at the end" do
      {:ok, from} = Tempo.from_iso8601("5786-09-30[u-ca=hebrew]")
      {:ok, to} = Tempo.from_iso8601("5786-10-01[u-ca=hebrew]")
      iv = %Tempo.Interval{from: from, to: to}

      assert inspect(iv) == "~o\"5786Y9M30D/10M1D[u-ca=hebrew]\""
    end

    test "a calendar written once applies to both endpoints on re-parse" do
      # Before the calendar propagated, this parsed as a *mixed*
      # Gregorian/Hebrew pair — which the abbreviated `11M1D` cannot mean,
      # since it is only readable against `from`'s own year.
      iv = Tempo.from_iso8601!("5786Y9M30D/10M1D[u-ca=hebrew]")

      assert iv.from.calendar == Calendrical.Hebrew
      assert iv.to.calendar == Calendrical.Hebrew
      assert iv == Tempo.from_iso8601!("5786Y9M30D[u-ca=hebrew]/10M1D[u-ca=hebrew]")
    end

    test "a deliberately mixed pair keeps both calendars" do
      # Propagation only fills an endpoint carrying no tag of its own, and
      # only backward, so a `from` that names its calendar keeps it.
      iv = Tempo.from_iso8601!("1447Y9M1D[u-ca=islamic-civil]/2026Y6M1D")

      assert iv.from.calendar == Calendrical.Islamic.Civil
      assert iv.to.calendar == Calendrical.Gregorian
      assert Tempo.to_iso8601!(iv) =~ "[u-ca=islamic-civil]/"
    end

    test "Interval with no extended info renders cleanly (no empty brackets)" do
      iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      assert inspect(iv) == "~o\"2026Y6M15D/20D\""
    end

    test "round-trip: inspect then parse restores the same zoned value" do
      {:ok, original} = Tempo.from_iso8601("2011-12-29T12:00:00[Pacific/Apia]")

      # Strip the sigil wrapper, reparse, and compare.
      "~o\"" <> rest = inspect(original)
      iso = String.trim_trailing(rest, "\"")
      {:ok, reparsed} = Tempo.from_iso8601(iso)

      assert reparsed.time == original.time
      assert reparsed.extended.zone_id == original.extended.zone_id
    end
  end

  # A time of day was written by clauses for one, two and three of its
  # units, each taking what followed the first as a unit. A selection after
  # an hour or a minute is no unit, so `inspect/1` and `Tempo.to_iso8601/1`
  # raised a `FunctionClauseError` for a value that reads and converts.
  describe "a selection within a time of day" do
    @selected_within_a_time [
      "2026Y6M15DT10HLT30MN",
      "2026Y6M15DT10HLT-1MN",
      "2026Y6M15DT10HLT{0,30}MN",
      "2026Y6M15DT10HLT{0..2}MN",
      "2026Y6M15DT10HLT{58..-1}MN",
      "2026Y6M15DT10HLT30M15SN",
      "2026Y6M15DT10H30MLT15SN",
      "T10HLT30MN",
      "T10H30MLT{0,30}SN"
    ]

    test "is written as it is read" do
      for text <- @selected_within_a_time do
        value = Tempo.from_iso8601!(text)

        assert Tempo.to_iso8601(value) == {:ok, text}
        assert Tempo.to_iso8601!(value) == text
        assert inspect(value) == ~s(~o"#{text}")
      end
    end

    test "leaves a time of day with nothing after it as it was written" do
      assert Tempo.to_iso8601(~o"2026Y6M15DT10H30M15S") == {:ok, "2026Y6M15DT10H30M15S"}
      assert Tempo.to_iso8601(~o"T10H30M") == {:ok, "T10H30M"}
      assert Tempo.to_iso8601(~o"T10H30M15.5S") == {:ok, "T10H30M15.5S"}
      assert Tempo.to_iso8601(~o"2026Y6M15DLT10H30MN") == {:ok, "2026Y6M15DLT10H30MN"}
    end
  end
end
