defmodule Tempo.Reader.DataFilesTest do
  use ExUnit.Case, async: true

  # The ISO 8601 and RFC 3339 texts of `test/support/data/`, from
  # <https://ijmacd.github.io/rfc3339-iso8601/>: each is read, and reads back
  # from what the writer writes as the same value.

  @data Path.expand("../../support/data", __DIR__)

  defp texts(file) do
    @data
    |> Path.join(file)
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn line -> line |> String.split("\t") |> text_of() end)
    |> Enum.reject(&(&1 == "" or underscored?(&1)))
  end

  # RFC 3339 §5.6 names a space as the separator an application may use in
  # place of `T`; the source lists an underscore too, which Tempo does not read.
  defp underscored?(text), do: String.contains?(text, "_")

  # A line of the range file is a pattern, the text and a verdict; of the others, the text.
  defp text_of([text]), do: String.trim(text)
  defp text_of([_pattern, text | _]), do: String.trim(text)

  for file <- ["iso8601_test_data.txt", "iso8601_range_test_data.txt", "rfc3339_test_data.txt"] do
    test "every text of #{file} is read and round-trips" do
      failures =
        for text <- texts(unquote(file)),
            result = round_trip(text),
            result != :ok,
            do: {text, result}

      assert Enum.empty?(failures),
             "#{length(failures)} texts fail:\n" <>
               inspect(failures, pretty: true, limit: :infinity)
    end
  end

  defp round_trip(text) do
    with {:ok, value} <- Tempo.from_iso8601(text),
         {:ok, written} <- Tempo.to_iso8601(value),
         {:ok, again} <- Tempo.from_iso8601(written) do
      if again == value, do: :ok, else: {:differs, written}
    end
  end
end
