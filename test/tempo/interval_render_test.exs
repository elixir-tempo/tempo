defmodule Tempo.IntervalRenderTest do
  @moduledoc """
  Every interval shape the tokenizer accepts must render back, and
  every value `IntervalSet.new/2` refuses must come back as a tagged
  tuple rather than a raise. Both were gaps: a duration-first
  recurring interval parsed and then raised on render, and a set
  member that was not an interval crashed a function documented to
  return `{:error, reason}`.
  """

  use ExUnit.Case, async: true

  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError
  alias Tempo.IntervalSet

  describe "duration-first intervals render" do
    test "a single duration-first interval" do
      {:ok, interval} = Tempo.from_iso8601("P1D/2022-01-01")

      assert Tempo.to_iso8601!(interval) == "P1D/2022Y1M1D"
    end

    test "a counted recurrence of one" do
      {:ok, interval} = Tempo.from_iso8601("R3/P1D/2022-01-01")

      assert Tempo.to_iso8601!(interval) == "R3/P1D/2022Y1M1D"
    end

    test "an unbounded recurrence" do
      {:ok, interval} = Tempo.from_iso8601("R/P1D/2022-01-01")

      assert Tempo.to_iso8601!(interval) == "R/P1D/2022Y1M1D"
    end

    test "inspecting one does not raise" do
      {:ok, interval} = Tempo.from_iso8601("R3/P1D/2022-01-01")

      assert inspect(interval) =~ "R3/P1D/2022Y1M1D"
    end
  end

  describe "an interval whose extent comes from its duration" do
    test "an explicitly open end renders like an absent one" do
      # A recurring interval takes each occurrence's extent from its
      # duration, so `to: :undefined` and `to: nil` say the same thing.
      {:ok, recurring} = Tempo.from_iso8601("R5/2022-01-01/P1M")

      assert Tempo.to_iso8601!(%{recurring | to: :undefined}) ==
               Tempo.to_iso8601!(recurring)
    end

    test "the same holds without a recurrence" do
      {:ok, single} = Tempo.from_iso8601("2022-01-01/P1M")

      assert Tempo.to_iso8601!(%{single | to: :undefined}) == Tempo.to_iso8601!(single)
    end
  end

  describe "parse and render round-trip" do
    test "rendering a parsed interval reproduces a parseable string" do
      for iso <- [
            "P1D/2022-01-01",
            "R3/P1D/2022-01-01",
            "R/P1D/2022-01-01",
            "R5/2022-01-01/P1M",
            "R5/2022-01-01/2022-02-01",
            "2022-01-01/2022-02-01"
          ] do
        {:ok, parsed} = Tempo.from_iso8601(iso)
        rendered = Tempo.to_iso8601!(parsed)

        assert {:ok, reparsed} = Tempo.from_iso8601(rendered)
        assert Tempo.to_iso8601!(reparsed) == rendered
      end
    end
  end

  describe "IntervalSet.new/2 reports bad members" do
    defp bounded do
      Interval.new!(
        from: Tempo.from_iso8601!("2027-06-15"),
        to: Tempo.from_iso8601!("2027-06-16")
      )
    end

    test "a member that is not an interval at all" do
      assert {:error, %ConversionError{}} = IntervalSet.new([:not_an_interval])
    end

    test "the error says what a member has to be" do
      {:error, exception} = IntervalSet.new([:not_an_interval])

      assert Exception.message(exception) =~ "must be Tempo.Interval structs"
      assert Exception.message(exception) =~ ":not_an_interval"
    end

    test "a bad member alongside good ones is still caught" do
      assert {:error, %ConversionError{}} = IntervalSet.new([bounded(), "junk"])
    end

    test "an open-ended member keeps its own error" do
      {:ok, open} = Interval.new(from: Tempo.from_iso8601!("2027-06-15"), to: :undefined)

      assert {:error, %IntervalEndpointsError{}} = IntervalSet.new([open])
    end

    test "well-formed members still construct a set" do
      assert {:ok, set} = IntervalSet.new([bounded()])
      assert IntervalSet.count(set) == 1
    end

    test "an empty list is still a valid empty set" do
      assert {:ok, set} = IntervalSet.new([])
      assert IntervalSet.count(set) == 0
    end
  end
end
