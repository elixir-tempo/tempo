defmodule Tempo.Reader.EdtfCorpusTest do
  use ExUnit.Case, async: true

  # The EDTF validation corpus (`Tempo.Iso8601.Edtf.Corpus`): every text of
  # levels 0, 1 and 2 is read and reads back from what the writer writes as
  # the same value; every invalid text is refused.

  alias Tempo.Iso8601.Edtf.Corpus

  for {name, texts} <- [
        level0_dates: Corpus.level0_dates(),
        level1_dates: Corpus.level1_dates(),
        level2_dates: Corpus.level2_dates(),
        level0_intervals: Corpus.level0_intervals(),
        level1_intervals: Corpus.level1_intervals(),
        level2_intervals: Corpus.level2_intervals()
      ] do
    test "every #{name} text is read and round-trips" do
      failures =
        for text <- unquote(texts),
            result = round_trip(text),
            result != :ok,
            do: {text, result}

      assert failures == [],
             "#{length(failures)} texts fail:\n" <>
               inspect(failures, pretty: true, limit: :infinity)
    end
  end

  # Texts EDTF refuses that ISO 8601 reads: an abbreviated end (ISO 8601-1
  # §5.5.1), an interval with a time of day at an end, which EDTF does not
  # have, and an interval of an expanded and a plain year, which ISO 8601-2
  # §4.7 does not forbid.
  # The last four run to the end of a date end, as law 9 of the redesign reads
  # a written interval: the 3rd of January through January is a span.
  @iso8601_not_edtf [
    "2000/12-12",
    "2005-07-25T10:10:10Z/2006-01-01T10:10:10Z",
    "2005-07-25T10:10:10Z/2006-01",
    "2005-07-25/2006-01-01T10:10:10Z",
    "Y-61000/-2000",
    "0000-01-03/0000-01",
    "0000-02/0000",
    "2004-06-11%/2004-%06",
    "2004-06-11%/2004-06~"
  ]

  # RFC 3339 §5.6 lets `T` and `Z` be lower case; EDTF does not.
  @rfc3339_not_edtf ["1985-04-12T23:20:30z", "1985-04-12t23:20:30"]

  for {name, texts} <- [
        invalid_dates: Corpus.invalid_dates() -- @iso8601_not_edtf,
        invalid_intervals: Corpus.invalid_intervals() -- @iso8601_not_edtf,
        invalid_datetimes: Corpus.invalid_datetimes() -- @rfc3339_not_edtf
      ] do
    test "every #{name} text is refused" do
      read =
        for text <- unquote(texts),
            {:ok, value} <- [Tempo.from_iso8601(text)],
            do: {text, Tempo.to_iso8601!(value)}

      assert read == [],
             "#{length(read)} invalid texts are read:\n" <>
               inspect(read, pretty: true, limit: :infinity)
    end
  end

  defp round_trip(text) do
    with {:ok, value} <- Tempo.from_iso8601(text),
         {:ok, written} <- Tempo.to_iso8601(value),
         {:ok, again} <- Tempo.from_iso8601(written) do
      if again == value, do: :ok, else: {:differs, written, again.form, value.form}
    end
  end
end
