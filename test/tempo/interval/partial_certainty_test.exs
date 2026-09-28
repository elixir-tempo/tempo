defmodule Tempo.Interval.PartialCertaintyTest do
  @moduledoc """
  Three-valued certainty (`:certain | :possible | :impossible`) over
  *underspecified* operands: unspecified-digit (masked) values read as their set
  of possible groundings, and un-anchored values compared on a shared axis.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.RequiresAnchorError

  describe "masked (unspecified-digit) operands read as a grounding set" do
    test "a masked year is certainly within the span its mask admits" do
      # ~o"20XXY" is some year in [2000, 2100); every grounding sits inside it.
      assert Interval.within_certainty(~o"20XXY", ~o"2000Y/2100Y") == :certain
    end

    test "a masked year is only possibly within a span one grounding escapes" do
      # 2000 is a legal grounding but falls outside [2001, 2101).
      assert Interval.within_certainty(~o"20XXY", ~o"2001Y/2101Y") == :possible
    end

    test "a masked year certainly precedes a year past its whole span" do
      assert Interval.certainly_before?(~o"20XXY", ~o"2200Y")
    end

    test "a masked year only possibly precedes a year inside its span" do
      # Groundings 2000–2049 precede 2050; 2051–2099 follow it.
      refute Interval.certainly_before?(~o"20XXY", ~o"2050Y")
      assert Interval.possibly_before?(~o"20XXY", ~o"2050Y")
      assert Interval.relation_certainty(~o"20XXY", ~o"2050Y", :precedes) == :possible
    end

    test "a masked year cannot overlap a year outside its span" do
      assert Interval.overlap_certainty(~o"20XXY", ~o"1000Y") == :impossible
      refute Interval.possibly_overlaps?(~o"20XXY", ~o"1000Y")
    end

    test "a masked month is certainly within its enclosing year" do
      # ~o"2020YXXM" is some month of 2020; all twelve sit inside 2020.
      assert Interval.within_certainty(~o"2020YXXM", ~o"2020Y") == :certain
    end

    test "a masked decade digit narrows the span accordingly" do
      # ~o"201XY" is some year in [2010, 2020).
      assert Interval.within_certainty(~o"201XY", ~o"2010Y/2020Y") == :certain
      # 2019 meets 2020 and shares no instant with it, so every grounding is
      # before 2020; Allen's strict :precedes needs the gap 2021 opens.
      assert Interval.certainly_before?(~o"201XY", ~o"2020Y")
      assert Interval.relation_certainty(~o"201XY", ~o"2020Y", :precedes) == :possible
      assert Interval.relation_certainty(~o"201XY", ~o"2021Y", :precedes) == :certain
      refute Interval.certainly_before?(~o"201XY", ~o"2015Y")
    end

    test "two masked years compare over their grounding envelopes" do
      # 20XX (2000–2099) can precede, meet, overlap, … 21XX (2100–2199): the
      # earlier span is at worst adjacent, so it can never follow the later one.
      refute Interval.possibly_after?(~o"20XXY", ~o"21XXY")
      assert Interval.certainly_before?(~o"18XXY", ~o"2000Y")
    end
  end

  describe "non-contiguous masks expand to their candidate groundings" do
    # ~o"1985-XX-15" is the 15th of some unknown month of 1985 — twelve
    # non-adjacent candidate days, not a contiguous span, so certainty reads
    # over the candidate set (regression: was a FunctionClauseError).

    test "possibly precedes a day inside the candidate range" do
      # Jan–Jun 15ths precede June 20; Jul–Dec 15ths follow it.
      assert Interval.relation_certainty(~o"1985-XX-15", ~o"1985-06-20", :precedes) ==
               :possible
    end

    test "certainly precedes a day past every candidate" do
      assert Interval.certainly_before?(~o"1985-XX-15", ~o"1986-01-01")
    end

    test "possibly equals a single candidate" do
      assert Interval.relation_certainty(~o"1985-XX-15", ~o"1985-06-15", :equals) == :possible
    end

    test "certainly within the enclosing year" do
      assert Interval.within_certainty(~o"1985-XX-15", ~o"1985Y") == :certain
    end

    test "cannot overlap a year outside every candidate" do
      assert Interval.overlap_certainty(~o"1985-XX-15", ~o"1984Y") == :impossible
    end
  end

  describe "un-anchored operands" do
    test "same-axis month-days compare positionally and definitely" do
      assert Interval.certainly_before?(~o"1M31D", ~o"3M15D")
      assert Interval.relation_certainty(~o"2M", ~o"5M", :precedes) == :certain
      refute Interval.possibly_after?(~o"1M31D", ~o"3M15D")
    end

    test "comparing across resolution axes requires an anchor" do
      # An un-anchored month against an anchored year depends on the missing
      # year — a clean error, not a guess and not a crash.
      assert {:error, %RequiresAnchorError{}} = Interval.within_certainty(~o"2M", ~o"2050Y")

      assert {:error, %RequiresAnchorError{}} =
               Interval.relation_certainty(~o"2M", ~o"2050Y", :precedes)
    end

    test "the boolean predicates surface an un-anchorable comparison as an error" do
      # A silent `false` would assert "impossible" — a claim the error
      # explicitly could not make. The boolean forms raise the same error
      # the tuple-returning certainty functions report.
      assert_raise RequiresAnchorError, fn ->
        Interval.certainly_before?(~o"2M", ~o"2050Y")
      end

      assert_raise RequiresAnchorError, fn ->
        Interval.possibly_before?(~o"2M", ~o"2050Y")
      end
    end
  end

  describe "non-partial operands are unchanged" do
    test "crisp containment still degrades to the boolean predicate" do
      assert Interval.within_certainty(~o"2000Y6M", ~o"2000Y") == :certain
      assert Interval.overlap_certainty(~o"2000Y", ~o"2000Y") == :certain
    end

    test "± margins still enumerate placements" do
      assert Interval.overlap_certainty(~o"2000±1Y", ~o"2001±1Y") == :possible
      assert Interval.overlap_certainty(~o"2000±1Y", ~o"2010±1Y") == :impossible
      assert Interval.certainly_before?(~o"2000±1Y", ~o"2010±1Y")
    end
  end

  property "masked-year certainty is sound against explicit grounding enumeration" do
    # ~o"20XXY" ranges over each year 2000..2099. A verdict of :certain must hold
    # for every grounding, and :impossible for none — the guarantee a sound
    # over-approximation gives (it may only ever err toward :possible).
    groundings = for year <- 2000..2099, do: Tempo.from_iso8601!("#{year}Y")

    check all(
            target_year <- integer(1900..2200),
            target_relation <-
              member_of([:precedes, :preceded_by, :equals, :during, :contains, :meets])
          ) do
      target = Tempo.from_iso8601!("#{target_year}Y")
      verdict = Interval.relation_certainty(~o"20XXY", target, target_relation)
      grounding_relations = for grounding <- groundings, do: Tempo.relation(grounding, target)

      case verdict do
        :certain -> assert Enum.all?(grounding_relations, &(&1 == target_relation))
        :impossible -> assert Enum.all?(grounding_relations, &(&1 != target_relation))
        _possible_or_error -> assert true
      end
    end
  end
end
