defmodule Tempo.Grammar.Mutator do
  @moduledoc """
  Texts the reader must refuse, made by breaking a well-formed text in a
  way no production allows, and texts it must survive, made by any change
  at all; for the property tests of section 7 of `guides/iso8601-grammar.md`.

  """

  @doc """
  Breaks a text so that no production matches it.

  ### Arguments

  * `text` is a well-formed text.

  ### Returns

  * A list of `{mutation, text}`, one per kind of break.

  """
  @spec broken(String.t()) :: [{atom(), String.t()}]
  def broken(text) do
    [
      {:letter_q, insert(text, "Q")},
      {:two_slashes, String.replace(text, "/", "//", global: false)},
      {:open_bracket, text <> "["},
      {:open_brace, "{" <> text},
      {:trailing_dash, text <> "-"},
      {:double_t, String.replace(text, "T", "TT", global: false)},
      {:space_inside, insert(text, " ")},
      {:letter_after_designator, text <> "Q"},
      {:empty_set, String.replace(text, ~r/\{[^}]*\}/, "{}", global: false)}
    ]
    |> Enum.reject(fn {_, mutated} -> mutated == text end)
  end

  @doc """
  Changes a text at random: a character dropped, doubled, replaced by another
  of the text, or by a designator. The result may or may not be well formed;
  the reader must answer either way and never raise.

  ### Arguments

  * `text` is any text.

  * `count` is how many variants to make.

  ### Returns

  * A list of texts.

  """
  @spec varied(String.t(), pos_integer()) :: [String.t()]
  def varied(text, count) do
    graphemes = String.graphemes(text)
    designators = ~w(Y M D W K O H S T Z P R L N G U I X - / : . , { } [ ] ? ~ % E C J)

    for _ <- 1..count do
      at = Enum.random(0..max(length(graphemes) - 1, 0))

      case Enum.random(1..4) do
        1 -> List.delete_at(graphemes, at)
        2 -> List.insert_at(graphemes, at, Enum.at(graphemes, at, "1"))
        3 -> List.replace_at(graphemes, at, Enum.random(graphemes ++ ["1"]))
        4 -> List.insert_at(graphemes, at, Enum.random(designators))
      end
      |> Enum.join()
    end
  end

  # A character placed inside the text, after its first character.
  defp insert(text, insertion) do
    at = min(div(byte_size(text), 2), byte_size(text))
    binary_part(text, 0, at) <> insertion <> binary_part(text, at, byte_size(text) - at)
  end
end
