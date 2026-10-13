defmodule Tempo.Iso8601.SignedUnspecifiedTest do
  @moduledoc """
  A sign before an unspecified number (`-X*D`).

  An unspecified number (`X*`) stands for every value its unit takes, and
  counted from the end those are the same values, so a sign before one
  names nothing of its own. The tokenizer put the sign before the `X*` as
  the head of an improper list, and reading any string that held one raised
  a `FunctionClauseError`. It is a `Tempo.ParseError` that says so.
  """
  use ExUnit.Case, async: true

  alias Tempo.ParseError

  @signed [
    "-X*D",
    "-X*Y",
    "-X*M",
    "T-X*H",
    "2026Y6M-X*D",
    "2026Y-X*M15D",
    "L-X*DN",
    "2026Y6ML-X*DN",
    "R/2026/P1Y/FL-X*DN",
    "{-X*D,5D}",
    "2026-06-15/-X*D",
    "-X*D/2026-06-15"
  ]

  describe "a sign before an unspecified number" do
    test "is a parse error wherever it is written, and never a raise" do
      for text <- @signed do
        assert {^text, {:error, %ParseError{} = error}} = {text, Tempo.from_iso8601(text)}
        assert {text, Exception.message(error) =~ "unspecified number (-X*)"} == {text, true}
      end
    end

    test "is refused by the readers that raise with the same error" do
      assert_raise ParseError, ~r/unspecified number \(-X\*\)/, fn ->
        Tempo.from_iso8601!("-X*D")
      end
    end
  end

  describe "what is written beside it" do
    test "is read as it was: an unspecified number, and a sign before unspecified digits" do
      for text <- ["X*D", "2026Y6MX*D", "LX*DN", "-XXXX", "L-XDN", "2026Y6M-XD"] do
        assert {^text, {:ok, _value}} = {text, Tempo.from_iso8601(text)}
      end
    end
  end
end
