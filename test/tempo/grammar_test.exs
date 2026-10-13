defmodule Tempo.GrammarTest do
  use ExUnit.Case, async: true

  # The grammar of guides/iso8601-grammar.md, section 7: texts generated from
  # its productions are read and round-trip through the writer; texts broken
  # so that no production matches are refused; any change to a text is
  # answered with a value or an error, never a raise.

  alias Tempo.Grammar.Generator
  alias Tempo.Grammar.Mutator

  @seed 20_261_013
  @per_production 25

  test "every generated text is read and round-trips" do
    failures =
      for {production, text} <- Generator.texts(@per_production, @seed),
          result = round_trip(text),
          result != :ok,
          do: {production, text, result}

    assert failures == [],
           "#{length(failures)} generated texts fail (seed #{@seed}):\n" <>
             inspect(failures, pretty: true, limit: :infinity)
  end

  test "every broken text is refused" do
    read =
      for {production, text} <- Generator.texts(3, @seed),
          {mutation, broken} <- Mutator.broken(text),
          {:ok, value} <- [Tempo.from_iso8601(broken)],
          do: {production, mutation, text, broken, Tempo.to_iso8601!(value)}

    assert read == [],
           "#{length(read)} broken texts are read (seed #{@seed}):\n" <>
             inspect(read, pretty: true, limit: :infinity)
  end

  test "every varied text is answered, never raised on" do
    :rand.seed(:exsss, {@seed, @seed, @seed})

    raised =
      for {production, text} <- Generator.texts(3, @seed),
          varied <- Mutator.varied(text, 8),
          result = answered(varied),
          result != :ok,
          do: {production, text, varied, result}

    assert raised == [],
           "#{length(raised)} varied texts raise (seed #{@seed}):\n" <>
             inspect(raised, pretty: true, limit: :infinity)
  end

  defp round_trip(text) do
    with {:ok, value} <- Tempo.from_iso8601(text),
         {:ok, written} <- Tempo.to_iso8601(value),
         {:ok, again} <- Tempo.from_iso8601(written) do
      if again == value, do: :ok, else: {:differs, written}
    end
  end

  defp answered(text) do
    case Tempo.from_iso8601(text) do
      {:ok, value} ->
        if match?({:ok, _}, Tempo.to_iso8601(value)), do: :ok, else: {:unwritable, value}

      {:error, %{__struct__: _}} ->
        :ok
    end
  rescue
    exception -> {:raised, Exception.message(exception)}
  end
end
