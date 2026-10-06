defmodule Tempo.Iso8601.GeneratedSetsTest do
  @moduledoc """
  Sets and ranges (ISO 8601-2 clause 6), held to texts no one wrote by hand.

  The parser's tests are examples someone thought to write, and the defects
  found in its sets and ranges were each found by accident beside other
  work. `Tempo.GeneratedSets` builds about two thousand texts from members
  whose reading alone is known: sets of whole values in every form a value is
  written in, with ranges between two members and ranges open at an end, and
  sets in one unit of a value in the explicit, the extended and the basic
  format. What each should read as is known from its members, without
  reading it.

  Each text is held to three properties:

  * reading it, `inspect/1` and `Tempo.to_iso8601/1` never raise;

  * a member of a set is its own text read alone;

  * what is written reads back as the same value.

  And to its form: a text is read, or refused where its form is one Tempo
  does not read, so a form that starts or stops being read is noticed here.

  This is the pilot of `plans/parser-formal-grammar.md`. Its first two runs
  found a set of one value in a unit read as another value, a set of days of
  the year read as months, one of several years and a member with a zone of
  its own not read, and a range of seasons that nothing walked.
  """
  use ExUnit.Case, async: true

  alias Tempo.GeneratedSets

  setup_all do
    texts = GeneratedSets.texts()
    {:ok, texts: texts, findings: GeneratedSets.findings(texts)}
  end

  defp found(findings, property),
    do: for({^property, text, detail} <- findings, do: {text, detail})

  test "the texts are of every family and form", %{texts: texts} do
    # A generator that makes nothing holds to every property.
    assert Enum.count(texts) > 1_900
    assert Enum.count(texts, &(&1.expect == :read)) > 1_850
    assert Enum.count(texts, &match?({:refused, _error}, &1.expect)) > 50
    assert Enum.uniq_by(texts, & &1.text) == texts
  end

  test "reading a text and writing its value never raise", %{findings: findings} do
    assert found(findings, :raises) == []
  end

  test "a text is read, or refused, as its form is built to be", %{findings: findings} do
    assert found(findings, :form) == []
  end

  test "a member of a set is its own text read alone", %{findings: findings} do
    assert found(findings, :member) == []
  end

  test "what is written reads back as the same value", %{findings: findings} do
    assert found(findings, :written) == []
  end
end
