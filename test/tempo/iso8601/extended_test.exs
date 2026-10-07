defmodule Tempo.Iso8601.Extended.Test do
  use ExUnit.Case, async: true

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.Iso8601.Tokenizer

  doctest Tempo.Iso8601.Tokenizer.Extended

  ## Backward compatibility — no suffix

  describe "no extended suffix" do
    test "bare RFC 3339 datetime returns nil extended info" do
      assert {:ok, {tokens, nil}} = Tokenizer.tokenize("2022-11-20T10:30:00Z")

      assert tokens == [
               datetime: [
                 year: 2022,
                 month: 11,
                 day: 20,
                 hour: 10,
                 minute: 30,
                 second: 0,
                 time_shift: [hour: 0]
               ]
             ]
    end

    test "bare date returns nil extended info" do
      assert {:ok, {_tokens, nil}} = Tokenizer.tokenize("2022-11-20")
    end

    test "from_iso8601 leaves :extended field nil when no suffix" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-11-20")
      assert tempo.extended == nil
    end
  end

  ## Time zone name

  describe "time zone name" do
    test "parses a valid IANA zone name" do
      assert {:ok, {_tokens, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[Europe/Paris]")

      assert extended.zone_id == "Europe/Paris"
      assert extended.zone_offset == nil
      assert extended.calendar == nil
      assert extended.tags == %{}
    end

    test "parses zone names with dots and underscores" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[America/Indiana/Indianapolis]")

      assert extended.zone_id == "America/Indiana/Indianapolis"

      assert {:ok, {_, extended2}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[America/North_Dakota/Center]")

      assert extended2.zone_id == "America/North_Dakota/Center"
    end

    test "parses UTC zone" do
      assert {:ok, {_, extended}} = Tokenizer.tokenize("2022-11-20T10:30:00Z[UTC]")
      assert extended.zone_id == "UTC"
    end

    test "critical flag on known zone is accepted" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[!Europe/Paris]")

      assert extended.zone_id == "Europe/Paris"
    end

    test "critical flag on unknown zone is rejected" do
      assert {:error, msg} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[!America/Not_A_Place]")

      assert Exception.message(msg) =~ "Unknown IANA time zone"
    end

    test "elective (non-critical) unknown zone retains tag but no zone_id" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[Made/Up_Zone]")

      assert extended.zone_id == nil
      assert extended.tags["unknown_zone"] == ["Made/Up_Zone"]
    end

    test "a zone that is not known is written as it was written, and reads back" do
      # It was written `[unknown_zone=Made/Up_Zone]`, which no suffix reads.
      for text <- [
            "2022-11-20T10:30:00Z[Made/Up_Zone]",
            "2022-11-20[Made/Up_Zone]",
            "2022-11-20[Made/Up_Zone][u-ca=hebrew]",
            "2022-11-20[Made/Up_Zone][foo=bar]",
            "2022-11-20[Made/Up_Zone]/2022-11-21",
            "{2022-11-20[Made/Up_Zone],2022-11-21}",
            "2022-11-20[Europe/Paris][u-nu-latn]",
            "2022-11-20[u-nu-latn]"
          ] do
        {:ok, value} = Tempo.from_iso8601(text)
        written = Tempo.to_iso8601!(value)

        refute written =~ "unknown_zone"
        assert {text, Tempo.from_iso8601(written)} == {text, {:ok, value}}
      end

      assert Tempo.to_iso8601!(Tempo.from_iso8601!("2022-11-20[Made/Up_Zone][u-ca=hebrew]")) ==
               "2022Y11M20D[Made/Up_Zone][u-ca=hebrew]"
    end
  end

  ## Numeric offset

  describe "numeric offset in brackets" do
    test "positive offset in minutes" do
      assert {:ok, {_, extended}} = Tokenizer.tokenize("2022-11-20T10:30:00Z[+08:45]")
      assert extended.zone_offset == 8 * 60 + 45
    end

    test "negative offset in minutes" do
      assert {:ok, {_, extended}} = Tokenizer.tokenize("2022-11-20T10:30:00Z[-03:30]")
      assert extended.zone_offset == -(3 * 60 + 30)
    end

    test "offset without colon" do
      assert {:ok, {_, extended}} = Tokenizer.tokenize("2022-11-20T10:30:00Z[+0530]")
      assert extended.zone_offset == 5 * 60 + 30
    end

    test "hours only" do
      assert {:ok, {_, extended}} = Tokenizer.tokenize("2022-11-20T10:30:00Z[+08]")
      assert extended.zone_offset == 8 * 60
    end
  end

  ## Calendar (u-ca)

  describe "u-ca calendar tag" do
    test "recognised calendar name" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[u-ca=hebrew]")

      assert extended.calendar == :hebrew
    end

    test "\"gregory\" maps to :gregorian" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[u-ca=gregory]")

      assert extended.calendar == :gregorian
    end

    test "persian calendar" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[u-ca=persian]")

      assert extended.calendar == :persian
    end

    test "critical unknown calendar is rejected" do
      assert {:error, msg} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[!u-ca=nonesuch]")

      assert Exception.message(msg) =~ "Unknown calendar identifier"
    end

    test "elective unknown calendar is silently ignored" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[u-ca=nonesuch]")

      assert extended.calendar == nil
    end
  end

  ## Combined suffix

  describe "combined suffix" do
    test "zone + calendar" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[Europe/Paris][u-ca=hebrew]")

      assert extended.zone_id == "Europe/Paris"
      assert extended.calendar == :hebrew
    end

    test "offset + calendar" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[+05:30][u-ca=hebrew]")

      assert extended.zone_offset == 330
      assert extended.calendar == :hebrew
    end

    test "multiple elective tags" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[_foo=bar][_baz=qux]")

      assert extended.tags == %{"_foo" => ["bar"], "_baz" => ["qux"]}
    end

    test "hyphen-separated values in a tag" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[_foo=bar-baz-qux]")

      assert extended.tags == %{"_foo" => ["bar", "baz", "qux"]}
    end

    test "zone + critical unknown tag rejects" do
      assert {:error, _} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[Europe/Paris][!unknown=x]")
    end

    test "zone + elective unknown tag is kept in :tags" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[Europe/Paris][unknown=x]")

      assert extended.zone_id == "Europe/Paris"
      assert extended.tags == %{"unknown" => ["x"]}
    end
  end

  ## Critical flag (!) behaviour

  describe "critical flag" do
    test "critical tag with u-ca gregory is accepted" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[!u-ca=gregory]")

      assert extended.calendar == :gregorian
    end

    test "duplicate zone is rejected when critical" do
      assert {:error, _} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[Europe/Paris][!Europe/London]")
    end

    test "duplicate zone is ignored when elective" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-11-20T10:30:00Z[Europe/Paris][Europe/London]")

      # First wins, second is ignored
      assert extended.zone_id == "Europe/Paris"
    end

    # A time zone given as an offset after the first position is no second
    # zone either: ignored, or an error where it is critical.
    test "an offset after a zone is ignored when elective, and rejected when critical" do
      with_one = Tempo.from_iso8601("2022-11-20T10:30:00[Europe/Paris]")

      assert Tempo.from_iso8601("2022-11-20T10:30:00[Europe/Paris][+08:45]") == with_one

      assert {:error, %Tempo.DuplicateZoneError{}} =
               Tempo.from_iso8601("2022-11-20T10:30:00[Europe/Paris][!+08:45]")
    end
  end

  # RFC 9557 §3.3: "An application that encounters duplicate use of a suffix
  # key in elective suffixes ... MUST choose the first suffix that has that
  # key", and a string with a critical one among them that names another
  # value is erroneous. The texts are the RFC's own. The last suffix was the
  # one read, critical or not.
  describe "a suffix key written twice" do
    test "is read the first time" do
      assert Tempo.from_iso8601("2022-07-08T00:14:07Z[u-ca=chinese][u-ca=japanese]") ==
               Tempo.from_iso8601("2022-07-08T00:14:07Z[u-ca=chinese]")

      assert Tempo.from_iso8601("2022-07-08T00:14:07Z[foo=a][bar=b][foo=c]") ==
               Tempo.from_iso8601("2022-07-08T00:14:07Z[foo=a][bar=b]")

      # A calendar of several parts, and one written in the hyphen form.
      assert Tempo.from_iso8601("2022-07-08[u-ca=islamic-civil][u-ca=islamic-umalqura]") ==
               Tempo.from_iso8601("2022-07-08[u-ca=islamic-civil]")

      assert Tempo.from_iso8601("2022-07-08[u-ca-hebrew][u-ca=gregory]") ==
               Tempo.from_iso8601("2022-07-08[u-ca-hebrew]")
    end

    test "is an error where one of the two is critical and they differ" do
      for text <- [
            "2022-07-08T00:14:07Z[!u-ca=chinese][u-ca=japanese]",
            "2022-07-08T00:14:07Z[u-ca=chinese][!u-ca=japanese]",
            "2022-07-08[u-ca=islamic-civil][!u-ca=islamic-umalqura]",
            "2022-07-08[u-ca=hebrew][!u-ca-gregory]"
          ] do
        assert {:error, %Tempo.ParseError{} = error} = Tempo.from_iso8601(text)
        assert {text, Exception.message(error) =~ "is written twice"} == {text, true}
      end
    end

    test "is no error where the two are one value" do
      assert Tempo.from_iso8601("2022-07-08[!u-ca=hebrew][u-ca=hebrew]") ==
               Tempo.from_iso8601("2022-07-08[!u-ca=hebrew]")
    end
  end

  # An extension of BCP 47 in the hyphen form that is no extension is kept
  # as written where it is elective, and is an error where it is critical.
  describe "a u extension that is not one" do
    test "is an error when critical, and kept when elective" do
      for extension <- ["u-zz", "u-ca-", "u-ca-nosuchcalendar"] do
        assert {:error, %Tempo.ParseError{} = error} =
                 Tempo.from_iso8601("2026-06-15T10:30[!#{extension}]")

        assert {extension, Exception.message(error) =~ "Invalid u extension"} == {extension, true}

        assert {:ok, kept} = Tempo.from_iso8601("2026-06-15T10:30[#{extension}]")

        assert {extension, Tempo.to_iso8601(kept)} ==
                 {extension, {:ok, "2026Y6M15DT10H30M[#{extension}]"}}
      end
    end
  end

  ## Tempo.from_iso8601 integration

  describe "from_iso8601 integration" do
    test "the zone is kept on the Tempo struct, and the calendar a suffix names is its calendar" do
      assert {:ok, tempo} =
               Tempo.from_iso8601("2022-11-20T10:30:00Z[Europe/Paris][u-ca=hebrew]")

      assert tempo.extended.zone_id == "Europe/Paris"
      assert tempo.calendar == Calendrical.Hebrew
      refute Map.has_key?(tempo.extended, :calendar)
    end

    test "a suffix that names a calendar alone leaves no extended info" do
      assert {:ok, tempo} = Tempo.from_iso8601("5786-09-30[u-ca=hebrew]")
      assert tempo.extended == nil

      assert {:ok, unknown} = Tempo.from_iso8601("2022-11-20[u-ca=klingon]")
      assert unknown.extended == nil
    end

    test "error propagates for unknown critical zone" do
      assert {:error, _} =
               Tempo.from_iso8601("2022-11-20T10:30:00Z[!Continent/Imaginary]")
    end

    test "extended info is nil for plain ISO 8601" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-11-20")
      assert tempo.extended == nil
    end
  end

  ## RFC 9557 §3.4 — a critical `!` zone makes offset consistency mandatory.
  ## New York is -05:00 in January, so `+05:00` disagrees with the zone.

  describe "critical zone offset consistency (RFC 9557 §3.4)" do
    test "critical zone retains its flag on the extended map" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-01-01T00:00:00-05:00[!America/New_York]")
      assert tempo.extended.zone_critical == true
    end

    test "an elective zone is not critical" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-01-01T00:00:00-05:00[America/New_York]")
      assert tempo.extended.zone_critical == false
    end

    test "critical zone with an agreeing offset is accepted" do
      assert {:ok, _tempo} =
               Tempo.from_iso8601("2022-01-01T00:00:00-05:00[!America/New_York]")
    end

    test "critical zone with a disagreeing offset is rejected unconditionally" do
      assert {:error, %Tempo.ZoneOffsetMismatchError{}} =
               Tempo.from_iso8601("2022-01-01T00:00:00+05:00[!America/New_York]")
    end

    test "critical zone with no explicit offset has nothing to check" do
      assert {:ok, _tempo} = Tempo.from_iso8601("2022-01-01T00:00:00[!America/New_York]")
    end

    test "elective zone with a disagreeing offset is read at its offset, on the zone's clock" do
      # Midnight at five hours ahead of UTC is 19:00 UTC the evening before,
      # which New York's clock shows as 14:00. It was read as midnight on
      # that clock, ten hours later (decided 2026-10-07).
      assert {:ok, tempo} =
               Tempo.from_iso8601("2022-01-01T00:00:00+05:00[America/New_York]")

      shown =
        ~D[2022-01-01]
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")
        |> DateTime.add(-5, :hour)
        |> DateTime.shift_zone!("America/New_York")

      assert {shown.day, shown.hour} == {31, 14}

      assert Tempo.relation(tempo, Tempo.from_iso8601!("2021-12-31T14:00:00[America/New_York]")) ==
               :equals

      assert Tempo.to_iso8601!(tempo) == "2021Y12M31DT14H0M0SZ-5H0M[America/New_York]"
    end

    test "strict: true is a superset — it rejects an elective disagreement too" do
      assert {:error, %Tempo.ZoneOffsetMismatchError{}} =
               Tempo.from_iso8601("2022-01-01T00:00:00+05:00[America/New_York]", strict: true)
    end

    test "the critical flag round-trips through to_iso8601/1" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-01-01T00:00:00-05:00[!America/New_York]")
      assert Tempo.to_iso8601!(tempo) =~ "[!America/New_York]"
    end
  end

  ## Invalid / malformed

  describe "malformed suffix" do
    test "unclosed bracket rejects the whole input" do
      assert {:error, _} = Tokenizer.tokenize("2022-11-20T10:30:00Z[Europe/Paris")
    end

    test "empty brackets rejects the whole input" do
      assert {:error, _} = Tokenizer.tokenize("2022-11-20T10:30:00Z[]")
    end

    test "invalid key character rejects the whole input" do
      # key must start with lowercase or underscore
      assert {:error, _} = Tokenizer.tokenize("2022-11-20T10:30:00Z[U-CA=gregory]")
    end

    test "invalid value character rejects the whole input" do
      # values must be alphanumeric
      assert {:error, _} = Tokenizer.tokenize("2022-11-20T10:30:00Z[u-ca=hello!]")
    end
  end

  ## Examples taken verbatim from draft-ietf-sedate-datetime-extended-09

  describe "draft examples" do
    test "1996-12-19T16:39:57-08:00[America/Los_Angeles]" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("1996-12-19T16:39:57-08:00[America/Los_Angeles]")

      assert extended.zone_id == "America/Los_Angeles"
    end

    test "1996-12-19T16:39:57-08:00[America/Los_Angeles][u-ca=hebrew]" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("1996-12-19T16:39:57-08:00[America/Los_Angeles][u-ca=hebrew]")

      assert extended.zone_id == "America/Los_Angeles"
      assert extended.calendar == :hebrew
    end

    test "2022-07-08T00:14:07Z[Europe/London]" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("2022-07-08T00:14:07Z[Europe/London]")

      assert extended.zone_id == "Europe/London"
    end

    test "1996-12-19T16:39:57-08:00[_foo=bar][_baz=bat]" do
      assert {:ok, {_, extended}} =
               Tokenizer.tokenize("1996-12-19T16:39:57-08:00[_foo=bar][_baz=bat]")

      assert extended.tags == %{"_foo" => ["bar"], "_baz" => ["bat"]}
    end
  end

  ## Per-endpoint IXDTF on intervals.
  ##
  ## Prior to this round, any interval where an endpoint carried an
  ## IXDTF suffix failed to parse — the grammar attached the suffix
  ## only at the top level, so the first `/` inside the string ended
  ## up unmatched. The fix adds an optional `extended_suffix()` to
  ## `qualified_endpoint` and validates the embedded segments in
  ## post-processing. These tests pin the new behaviour.

  describe "IXDTF on interval endpoints" do
    test "both endpoints carry their own zone" do
      assert {:ok, interval} =
               Tempo.from_iso8601("2022-06-15T10:00[Europe/Paris]/2022-06-15T12:00[Europe/Paris]")

      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.to.extended.zone_id == "Europe/Paris"
    end

    test "endpoints may carry different zones" do
      assert {:ok, interval} =
               Tempo.from_iso8601(
                 "2022-06-15T10:00[Europe/Paris]/2022-06-15T12:00[Europe/London]"
               )

      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.to.extended.zone_id == "Europe/London"
    end

    test "a zone on the upper endpoint propagates backward to a floating lower" do
      assert {:ok, interval} =
               Tempo.from_iso8601("2022-06-15T10:00/2022-06-15T12:00[Europe/Paris]")

      # IXDTF writes the zone once, at the end of the interval, binding it
      # to the upper endpoint; it applies to the whole span, so the
      # floating lower endpoint is placed in the same zone.
      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.to.extended.zone_id == "Europe/Paris"
    end

    test "an offset on the upper endpoint propagates backward to a floating lower" do
      assert {:ok, interval} =
               Tempo.from_iso8601("2022-06-15T10:00/2022-06-15T12:00Z")

      assert interval.from.shift == [hour: 0]
      assert interval.to.shift == [hour: 0]
    end

    test "a zone on the lower endpoint applies to the upper (ISO 8601-1 §5.5.1)" do
      assert {:ok, interval} =
               Tempo.from_iso8601("2022-06-15T10:00[Europe/Paris]/2022-06-15T12:00")

      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.to.extended.zone_id == "Europe/Paris"
    end

    test "an offset on the lower endpoint applies to the upper (ISO 8601-1 §5.5.1)" do
      # The standard's own example: `2018-01-15+05:00/2018-02-20` is
      # `2018-01-15+05:00/2018-02-20+05:00`.
      assert {:ok, interval} = Tempo.from_iso8601("2018-01-15T10:00+05:00/2018-02-20T10:00")

      refute Tempo.floating?(interval.to)
      assert interval.to.shift == interval.from.shift

      assert {:ok, reparsed} = interval |> Tempo.to_iso8601!() |> Tempo.from_iso8601()
      assert reparsed == interval
    end

    test "endpoints with different zones are left as written" do
      assert {:ok, interval} =
               Tempo.from_iso8601(
                 "2022-06-15T10:00[Europe/Paris]/2022-06-15T12:00[Europe/London]"
               )

      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.to.extended.zone_id == "Europe/London"
    end

    test "Interval.new/1 applies the same propagation as the parser" do
      # The constructor and the parser share the propagation rule, so a
      # constructed interval and the re-parse of its own ISO 8601 string
      # agree about their endpoint frames.
      {:ok, from} = Tempo.from_iso8601("2022-06-15")
      {:ok, to} = Tempo.from_iso8601("2022-06-20[Europe/Paris]")
      {:ok, built} = Interval.new(from: from, to: to)

      assert built.from.extended.zone_id == "Europe/Paris"

      {:ok, reparsed} = Tempo.from_iso8601(Tempo.to_iso8601!(built))
      assert reparsed.from.extended == built.from.extended
      assert reparsed.to.extended == built.to.extended
    end

    test "Interval.new/1 flows a :from frame forward and never overwrites" do
      {:ok, paris} = Tempo.from_iso8601("2022-06-15[Europe/Paris]")
      {:ok, floating} = Tempo.from_iso8601("2022-06-20")
      {:ok, forward} = Interval.new(from: paris, to: floating)
      assert forward.to.extended.zone_id == "Europe/Paris"

      {:ok, london} = Tempo.from_iso8601("2022-06-20[Europe/London]")
      {:ok, both} = Interval.new(from: paris, to: london)
      assert both.from.extended.zone_id == "Europe/Paris"
      assert both.to.extended.zone_id == "Europe/London"
    end

    test "a fully floating interval stays floating" do
      assert {:ok, interval} = Tempo.from_iso8601("2022-06-15T10:00/2022-06-15T12:00")

      assert interval.from.extended == nil
      assert interval.to.extended == nil
    end

    test "open-upper interval with IXDTF on the lower endpoint" do
      assert {:ok, interval} = Tempo.from_iso8601("2022-06-15T10:00[Europe/Paris]/..")

      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.to == :undefined
    end

    test "open-lower interval with IXDTF on the upper endpoint" do
      assert {:ok, interval} = Tempo.from_iso8601("../2022-06-15T10:00[Europe/Paris]")

      assert interval.from == :undefined
      assert interval.to.extended.zone_id == "Europe/Paris"
    end

    test "endpoint qualifier and IXDTF suffix may coexist" do
      assert {:ok, interval} =
               Tempo.from_iso8601("2022?[Europe/Paris]/2023~[Europe/London]")

      assert Tempo.qualification(interval.from) == :uncertain
      assert interval.from.extended.zone_id == "Europe/Paris"
      assert Tempo.qualification(interval.to) == :approximate
      assert interval.to.extended.zone_id == "Europe/London"
    end

    test "endpoint-local IXDTF supports `u-ca` calendar identifiers" do
      assert {:ok, interval} =
               Tempo.from_iso8601(
                 "2022-06-15T10:00[Europe/Paris][u-ca=hebrew]/2022-06-15T12:00[Europe/Paris]"
               )

      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.from.calendar == Calendrical.Hebrew
      assert interval.to.extended.zone_id == "Europe/Paris"
      assert interval.to.calendar == Calendrical.Gregorian

      # Regression (OTP ≤ 28): the Hebrew-read units resolve to a
      # pre-common-era Gregorian instant (year −1738), which used to
      # crash the `:calendar`-based conversions inside endpoint-order
      # validation and UTC projection on OTP 27/28. Parsing above and
      # both projections below must work on every supported OTP.
      assert Tempo.relation(interval.from, interval.to) == :precedes
      assert Compare.to_utc_seconds(interval.from) < 0
    end

    test "critical unknown zone on an endpoint bubbles up to the error result" do
      # Prior behaviour (before the interval grammar change) would
      # report a generic "could not parse" because the grammar never
      # reached the endpoint suffix. With per-endpoint extended-info
      # validation in place, the specific `Unknown IANA time zone`
      # error is surfaced.
      assert {:error, msg} =
               Tempo.from_iso8601("2022-06-15T10:00[!Continent/Imaginary]/2022-06-15T12:00")

      assert Exception.message(msg) =~ "Unknown IANA time zone"
      assert Exception.message(msg) =~ "Continent/Imaginary"
    end
  end
end
