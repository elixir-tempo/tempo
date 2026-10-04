defmodule Tempo.SigilMatchTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Duration

  # Phase ① behaviour of `~o[…]` used on the LHS of a match —
  # `match?/2`, `case`, function-head patterns. The sigil expands
  # to a `%Tempo{time: [{u1, v1}, …, {un, vn} | _]}` pattern,
  # leaving `calendar`, `shift`, `extended` and `qualifications`
  # unconstrained.

  describe "match?/2 with ~o[...]" do
    test "year-only sigil matches any Tempo starting with that year" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      assert match?(~o[2026Y], today)
    end

    test "year-only sigil does not match a different year" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      refute match?(~o[2025Y], today)
    end

    test "year+month sigil rejects a Tempo with a different month" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      refute match?(~o[2026Y01M], today)
    end

    test "year+month sigil accepts a Tempo with the same month (extra units allowed)" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      assert match?(~o[2026Y4M], today)
    end

    test "full date sigil matches an exact value" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      assert match?(~o[2026Y4M24D], today)
    end

    test "full date sigil rejects a later finer value" do
      today = Tempo.new!(year: 2026, month: 4, day: 25)
      refute match?(~o[2026Y4M24D], today)
    end

    test "datetime sigil matches a Tempo with the same head" do
      point = Tempo.new!(year: 2026, month: 6, day: 15, hour: 14, minute: 30, second: 45)
      assert match?(~o[2026Y6M15DT14H], point)
      assert match?(~o[2026Y6M15DT14H30M], point)
      assert match?(~o[2026Y6M15DT14H30M45S], point)
    end

    test "sigil with a unit the target Tempo lacks does not match" do
      bare_year = Tempo.new!(year: 2026)
      refute match?(~o[2026Y4M], bare_year)
    end

    test "calendar of target is irrelevant — only `time` is constrained" do
      hebrew = Tempo.new!(year: 2026, month: 4, day: 24, calendar: Calendrical.Hebrew)
      assert match?(~o[2026Y], hebrew)
      assert match?(~o[2026Y4M], hebrew)
    end

    test "shift / zone metadata on the target does not prevent a match" do
      zoned = Tempo.new!(year: 2026, month: 4, day: 24, hour: 10, shift: [hour: 5])
      assert match?(~o[2026Y4M24D], zoned)
    end
  end

  describe "~o[...] inside a case expression" do
    test "dispatches to the first matching branch" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      result =
        case today do
          ~o[2025Y] -> :last_year
          ~o[2026Y01M] -> :january
          ~o[2026Y] -> :this_year
          _ -> :other
        end

      assert result == :this_year
    end

    test "falls through to the default branch when nothing matches" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      result =
        case today do
          ~o[2025Y] -> :nope
          ~o[2027Y] -> :still_nope
          _ -> :default
        end

      assert result == :default
    end
  end

  describe "expansion-time errors" do
    test "raises ArgumentError when used in a guard" do
      # Guards are a stricter context than matches — the existing
      # guard clause rejects them outright, and phase ① leaves
      # that behaviour unchanged.
      assert_raise ArgumentError, ~r/invalid expression in guard/, fn ->
        Code.eval_string(
          """
          import Tempo.Sigils

          fn t when t == ~o[2026Y] -> :ok end
          """,
          []
        )
      end
    end
  end

  # Phase ② — modifier letters bind the matched value's unit to a
  # same-named variable. Wildcards fill canonical positions
  # between the sigil's last explicit unit and the modifier's
  # target.

  describe "modifier bindings — single binding" do
    test "D binds day even when month sits between year and day" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      assert (case today do
                ~o[2026Y]D -> day
              end) == 24
    end

    test "D binds day when month is also fixed in the sigil" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      assert (case today do
                ~o[2026Y4M]D -> day
              end) == 24
    end

    test "O binds month" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      assert (case today do
                ~o[2026Y]O -> month
              end) == 4
    end

    test "H binds hour on a full datetime" do
      point = Tempo.new!(year: 2026, month: 6, day: 15, hour: 14, minute: 30)

      assert (case point do
                ~o[2026Y6M15D]H -> hour
              end) == 14
    end

    test "N binds minute on a full datetime" do
      point = Tempo.new!(year: 2026, month: 6, day: 15, hour: 14, minute: 30)

      assert (case point do
                ~o[2026Y6M15DT14H]N -> minute
              end) == 30
    end

    test "S binds second" do
      point = Tempo.new!(year: 2026, month: 6, day: 15, hour: 14, minute: 30, second: 45)

      assert (case point do
                ~o[2026Y6M15DT14H30M]S -> second
              end) == 45
    end

    test "binding on a time-of-day value does not require date components" do
      tod = Tempo.new!(hour: 10, minute: 30)

      assert (case tod do
                ~o[T10H]N -> minute
              end) == 30
    end
  end

  describe "modifier bindings — multiple" do
    test "DN binds both day and minute" do
      point = Tempo.new!(year: 2026, month: 6, day: 15, hour: 14, minute: 30)

      assert (case point do
                ~o[2026Y6M]DN -> {day, minute}
              end) == {15, 30}
    end

    test "modifier order within the sigil does not matter" do
      point = Tempo.new!(year: 2026, month: 6, day: 15, hour: 14, minute: 30)

      assert (case point do
                ~o[2026Y6M]ND -> {day, minute}
              end) == {15, 30}
    end

    test "O and D compose with a fixed year" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      assert (case today do
                ~o[2026Y]OD -> {month, day}
              end) == {4, 24}
    end
  end

  describe "modifier bindings — match failures" do
    test "fails when the bound unit is absent from the target" do
      bare_year = Tempo.new!(year: 2026)

      # Use `case` + fall-through rather than `refute match?/2` so
      # the unused binding variable doesn't provoke a compile
      # warning.
      result =
        case bare_year do
          ~o[2026Y]D -> {:matched, day}
          _ -> :no_match
        end

      assert result == :no_match
    end

    test "fails when the sigil's fixed unit disagrees, even with bindings" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      result =
        case today do
          ~o[2026Y01M]D -> {:matched, day}
          _ -> :no_match
        end

      assert result == :no_match
    end
  end

  describe "modifier bindings — expansion-time errors" do
    test "unknown modifier letter raises ArgumentError" do
      assert_raise ArgumentError, ~r/does not recognise modifier/, fn ->
        Code.eval_string(
          """
          import Tempo.Sigils

          fn t ->
            case t do
              ~o[2026Y]X -> :ok
            end
          end
          """,
          []
        )
      end
    end

    test "duplicate unit between sigil and modifier raises ArgumentError" do
      assert_raise ArgumentError, ~r/already present in the sigil/, fn ->
        Code.eval_string(
          """
          import Tempo.Sigils

          fn t ->
            case t do
              ~o[2026Y]Y -> :ok
            end
          end
          """,
          []
        )
      end
    end

    test "mixing Gregorian axis with ISO week axis raises ArgumentError" do
      assert_raise ArgumentError, ~r/cannot mix calendar axes/, fn ->
        Code.eval_string(
          """
          import Tempo.Sigils

          fn t ->
            case t do
              ~o[2026Y4M]W -> :ok
            end
          end
          """,
          []
        )
      end
    end
  end

  # Phase ③ — matching on the non-`%Tempo{}` structs that the ISO
  # parser can produce: Duration, Interval, Range (embedded), and
  # Set.

  describe "matching %Tempo.Duration{}" do
    test "prefix match on the duration's time list" do
      duration = Duration.new!(year: 1, month: 6)
      assert match?(~o[P1Y6M], duration)
    end

    test "prefix allows extra finer components" do
      duration = Duration.new!(year: 1, month: 6, day: 15)
      assert match?(~o[P1Y6M], duration)
    end

    test "fails when values disagree" do
      duration = Duration.new!(year: 1, month: 6)
      refute match?(~o[P2Y6M], duration)
    end

    test "does not cross-match a Tempo against a Duration sigil" do
      tempo = Tempo.new!(year: 1, month: 6)
      refute match?(~o[P1Y6M], tempo)
    end

    test "does not cross-match a Duration against a Tempo sigil" do
      duration = Duration.new!(year: 1, month: 6)
      refute match?(~o[1Y6M], duration)
    end

    test "modifier bindings work on Duration (same `time` shape as Tempo)" do
      duration = Duration.new!(year: 1, month: 6, day: 15)

      assert (case duration do
                ~o[P1Y]D -> day
              end) == 15
    end
  end

  describe "matching %Tempo.Interval{}" do
    test "closed interval with two Tempo endpoints" do
      {:ok, interval} = Tempo.from_iso8601("1984Y/2004Y")
      assert match?(~o[1984Y/2004Y], interval)
    end

    test "sigil endpoints are prefix-matched against the interval's endpoints" do
      {:ok, interval} = Tempo.from_iso8601("1984Y6M/2004Y6M")
      assert match?(~o[1984Y/2004Y], interval)
    end

    test "open upper endpoint" do
      {:ok, interval} = Tempo.from_iso8601("1984/..")
      assert match?(~o[1984Y/..], interval)
    end

    test "open lower endpoint" do
      {:ok, interval} = Tempo.from_iso8601("../2004")
      assert match?(~o[../2004Y], interval)
    end

    test "both endpoints open" do
      {:ok, interval} = Tempo.from_iso8601("../..")
      assert match?(~o[../..], interval)
    end

    test "interval with a duration" do
      {:ok, interval} = Tempo.from_iso8601("P1D/2022-01-01")
      assert match?(~o[P1D/2022-01-01], interval)
    end

    test "a closed interval does not match an open-upper sigil" do
      {:ok, interval} = Tempo.from_iso8601("1984Y/2004Y")
      refute match?(~o[1984Y/..], interval)
    end

    test "an open-upper sigil does not match a closed interval" do
      {:ok, interval} = Tempo.from_iso8601("1984Y/..")
      refute match?(~o[1984Y/2004Y], interval)
    end
  end

  describe "matching %Tempo.Set{}" do
    # Set sigils whose literal text starts with `[` or `{`
    # collide with the `~o[…]` and `~o{…}` delimiters, so use
    # the string-delimiter form `~o"…"` instead.

    test "one-of set" do
      {:ok, set} = Tempo.from_iso8601("[1984,1986,1988]")
      assert match?(~o"[1984Y,1986Y,1988Y]", set)
    end

    test "all-of set" do
      {:ok, set} = Tempo.from_iso8601("{1960,1961-12}")
      assert match?(~o"{1960Y,1961Y12M}", set)
    end

    test "set types do not cross" do
      {:ok, one_of} = Tempo.from_iso8601("[1984,1986,1988]")
      refute match?(~o"{1984Y,1986Y,1988Y}", one_of)
    end

    test "set with an embedded Range member" do
      {:ok, set} = Tempo.from_iso8601("[1760-01,1760-12..]")
      assert match?(~o"[1760Y1M,1760Y12M..]", set)
    end

    test "member count must match" do
      {:ok, set} = Tempo.from_iso8601("[1984,1986,1988]")
      refute match?(~o"[1984Y,1986Y]", set)
    end
  end

  describe "container expansion-time errors" do
    test "modifier bindings on an Interval sigil raise" do
      assert_raise ArgumentError, ~r/only supported on %Tempo\{\}/, fn ->
        Code.eval_string(
          """
          import Tempo.Sigils

          fn t ->
            case t do
              ~o[1984Y/2004Y]D -> :ok
            end
          end
          """,
          []
        )
      end
    end

    test "modifier bindings on a Set sigil raise" do
      assert_raise ArgumentError, ~r/only supported on %Tempo\{\}/, fn ->
        Code.eval_string(
          """
          import Tempo.Sigils

          fn t ->
            case t do
              ~o"[1984Y,1986Y]"Y -> :ok
            end
          end
          """,
          []
        )
      end
    end
  end
end
