defmodule Tempo.MatrixWrittenTest do
  use ExUnit.Case, async: true

  # The matrix builds its generated values from their parts (decision 48).
  # The reader is held to them by reading back the text Tempo writes for
  # each: what is written is read as the value it was written from.

  alias Tempo.Matrix.Corpus

  test "every value the matrix builds is read back from the text written for it" do
    unread =
      for %{value: value} = entry <- Corpus.generated(),
          {:ok, text} <- [Tempo.to_iso8601(value)],
          Tempo.from_iso8601(text) != {:ok, value},
          do: {entry.class, text}

    assert unread == []
  end

  @tag :exhaustive
  test "every value of the exhaustive run is read back from the text written for it" do
    unread =
      for %{value: value} = entry <- Corpus.exhaustive(),
          {:ok, text} <- [Tempo.to_iso8601(value)],
          Tempo.from_iso8601(text) != {:ok, value},
          do: {entry.class, text}

    assert unread == []
  end
end
