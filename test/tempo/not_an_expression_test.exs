defmodule Tempo.NotAnExpressionTest do
  use ExUnit.Case, async: true

  # Decision 39: an argument that should be an expression and is not one is
  # a named error, returned by a function that returns its errors and raised
  # by one that answers a bare value. No function fails to match its
  # arguments.

  import Tempo.Sigils

  # Functions whose first argument is not an expression: a builder's parts,
  # an Elixir value, text, a zone, a territory, or any enumerable.
  @not_expressions [
    :new,
    :every,
    :selection,
    :one_of,
    :from_elixir,
    :from_iso8601,
    :parse,
    :parse_duration,
    :now,
    :today,
    :workdays,
    :weekends,
    :map,
    :try_map,
    :explain,
    :sigil_o,
    :sigil_TEMPO,
    :__struct__
  ]

  @named [
    Tempo.ConversionError,
    Tempo.FrameError,
    Tempo.IntervalEndpointsError,
    ArgumentError
  ]

  defp functions do
    for {name, arity} <- Tempo.__info__(:functions),
        arity in 1..3,
        name not in @not_expressions,
        not String.ends_with?(Atom.to_string(name), "!"),
        do: {name, arity}
  end

  # The other arguments are ones the function takes: an expression, then options.
  defp arguments(1), do: [42]
  defp arguments(2), do: [42, ~o"2027"]
  defp arguments(3), do: [42, ~o"2027", []]

  defp outcome(name, arity) do
    {:returned, apply(Tempo, name, arguments(arity))}
  rescue
    exception -> {:raised, exception}
  end

  test "every function given something that is no expression answers with a named error" do
    unnamed =
      for {name, arity} <- functions(),
          outcome = outcome(name, arity),
          not named?(outcome),
          do: {name, arity, outcome}

    assert unnamed == []
  end

  test "the error is :not_an_expression where the argument is the one wrong" do
    assert Tempo.trunc(nil) ==
             {:error, %Tempo.ConversionError{value: nil, reason: :not_an_expression}}

    assert Tempo.to_interval("2026-06") ==
             {:error, %Tempo.ConversionError{value: "2026-06", reason: :not_an_expression}}

    assert {:error, %Tempo.ConversionError{reason: :not_an_expression}} =
             Tempo.shift(~D[2026-06-15], ~o"P1D")

    assert_raise Tempo.ConversionError, ~r/is not a Tempo expression/, fn ->
      Tempo.year(~D[2026-06-15])
    end

    assert_raise Tempo.ConversionError, fn -> Tempo.anchored?(nil) end
  end

  test "text that is no string, and a zone that is no string, are named" do
    assert {:error, %ArgumentError{}} = Tempo.from_iso8601(2026)
    assert {:error, %ArgumentError{}} = Tempo.parse(:tomorrow)
    assert {:error, %ArgumentError{}} = Tempo.parse_duration(3600)
    assert {:error, %Tempo.ZoneError{reason: :unknown}} = Tempo.now(:paris)
    assert {:error, %Tempo.ZoneError{reason: :unknown}} = Tempo.in_zone(~o"2026-06-15T10", 42)
  end

  defp named?({:returned, {:error, %module{}}}), do: module in @named
  defp named?({:raised, %module{}}), do: module in @named
  defp named?({:returned, _answer}), do: false
end
