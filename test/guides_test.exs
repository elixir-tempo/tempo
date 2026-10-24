defmodule Tempo.GuidesTest do
  @moduledoc """
  Runs the Elixir in the README and every guide, so that an example the
  documentation presents as working cannot rot: each `iex>` example runs
  and answers what the page says, an example whose answer begins `** (`
  raises, and a block with `#=>` comments runs whole.

  Bindings carry down each page. A block is skipped when
  `<!-- guides:skip -->` is written before it (pseudo-code, a file the
  reader supplies), and a block with no result markers is run when
  `<!-- guides:run -->` is written before it (a setup the blocks after it
  use); any other block with no markers is an illustration and is not run.

  Runs with `mix test --only guides`.
  """
  use ExUnit.Case, async: false

  alias Tempo.Conformance
  alias Tempo.GuidesRunner

  @moduletag :guides

  @pages ["README.md" | Path.wildcard("guides/*.md")]

  for page <- @pages do
    test "the code in #{page} runs and answers as written" do
      assert [] = GuidesRunner.failures(unquote(page))
    end
  end

  # The conformance fixture `guides.json` lists every call the examples
  # make, with its answer, for a port to be held to; it is written by
  # `scripts/conformance_fixtures.exs` and must say what the guides answer.
  test "the conformance fixture lists the calls the guides' examples make, with their answers" do
    listed = Conformance.fixture("guides")["calls"]
    made = Conformance.guides()

    assert length(listed) == length(made)

    for {listed_call, made_call} <- Enum.zip(listed, made) do
      assert listed_call == made_call
    end
  end
end
