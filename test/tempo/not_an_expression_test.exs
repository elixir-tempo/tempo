defmodule Tempo.NotAnExpressionTest do
  use ExUnit.Case, async: true

  # Decision 39: an argument that should be an expression and is not one is
  # a named error, returned by a function that returns its errors and raised
  # by one that answers a bare value. No function fails to match its
  # arguments.

  import Tempo.Sigils

  alias Tempo.{IntervalSet, LeapSeconds, RecurrenceSet}

  # What each argument answers with when it is wrong: a named error,
  # returned by a function that returns errors and raised by one that answers
  # a bare value, never a failure to match.
  @crashes [
    FunctionClauseError,
    CaseClauseError,
    CondClauseError,
    WithClauseError,
    MatchError,
    KeyError,
    BadMapError,
    BadStructError,
    ArithmeticError,
    UndefinedFunctionError,
    Protocol.UndefinedError,
    BadArityError,
    BadFunctionError,
    RuntimeError
  ]

  # Functions that answer anything they are given: `explain/1` describes
  # what it is given, and three integers are a date to `on_date?/3`.
  @answer_anything [
    {Tempo, :explain, 1},
    {Tempo.Explain, :lines, 1},
    {Tempo.LeapSeconds, :on_date?, 3}
  ]

  # A first argument of each kind the public functions take.
  @firsts [~o"2026-06-15", ~o"P1D", "2026-06-15", [~o"2026-06-15"]]

  # Every documented function of every documented module of the library.
  defp functions do
    {:ok, modules} = :application.get_key(:ex_tempo, :modules)

    for module <- modules,
        library?(module),
        {:docs_v1, _, _, _, module_doc, _, docs} <- [Code.fetch_docs(module)],
        module_doc != :hidden,
        {{:function, name, arity}, _, _, doc, _} <- docs,
        doc != :hidden,
        arity > 0,
        {module, name, arity} not in @answer_anything,
        do: {module, name, arity}
  end

  # The test support modules are compiled into the application too.
  defp library?(module) do
    source = module.module_info(:compile) |> Keyword.fetch!(:source) |> List.to_string()
    String.contains?(source, "/lib/tempo")
  end

  defp outcome(module, name, arguments) do
    case apply(module, name, arguments) do
      {:error, %{__exception__: true} = exception} -> {:returned, exception}
      answer -> {:answered, answer}
    end
  rescue
    exception -> {:raised, exception}
  end

  defp named?({:returned, _exception}), do: true
  defp named?({:raised, %module{}}), do: module not in @crashes
  defp named?({:answered, _answer}), do: false

  test "every function given something that is none of what it takes answers with a named error" do
    unnamed =
      for {module, name, arity} <- functions(),
          outcome = outcome(module, name, List.duplicate(42, arity)),
          not named?(outcome),
          do: {module, name, arity, outcome}

    assert unnamed == []
  end

  test "every function given a wrong argument after a right one names it, and does not crash" do
    crashed =
      for {module, name, arity} <- functions(),
          arity > 1,
          first <- @firsts,
          outcome = outcome(module, name, [first | List.duplicate(42, arity - 1)]),
          match?({:raised, %crash{}} when crash in @crashes, outcome),
          do: {module, name, arity, first, outcome}

    assert crashed == []
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

  test "a set of what is no expression is named" do
    assert {:error, %Tempo.ConversionError{value: 1, reason: :not_an_expression}} =
             IntervalSet.new([1, 2])

    assert {:error, %Tempo.ConversionError{value: nil, reason: :not_an_expression}} =
             RecurrenceSet.new([~o"2026", nil])

    assert {:error, %ArgumentError{}} = IntervalSet.new(:members)
  end

  test "text that is no string, and a zone that is no string, are named" do
    assert {:error, %ArgumentError{}} = Tempo.from_iso8601(2026)
    assert {:error, %ArgumentError{}} = Tempo.parse(:tomorrow)
    assert {:error, %ArgumentError{}} = Tempo.parse_duration(3600)
    assert {:error, %Tempo.ZoneError{reason: :unknown}} = Tempo.now(:paris)
    assert {:error, %Tempo.ZoneError{reason: :unknown}} = Tempo.in_zone(~o"2026-06-15T10", 42)
  end

  test "a unit that is none, a week start that is none, and a function that is none are named" do
    assert {:error, %ArgumentError{}} = Tempo.trunc(~o"2026-06-15", :fortnight)
    assert {:error, %ArgumentError{}} = Tempo.round(~o"2026-06-15", :fortnight)
    assert {:error, %ArgumentError{}} = Tempo.at_resolution(~o"2026-06-15", :fortnight)
    assert_raise ArgumentError, fn -> Tempo.day_of_week(~o"2026-06-15", :someday) end
    assert {:error, %ArgumentError{}} = Tempo.try_map(42, &Function.identity/1)
    assert {:error, %ArgumentError{}} = Tempo.try_map([~o"2026"], :identity)
    assert_raise ArgumentError, fn -> Tempo.map(42, &Function.identity/1) end
    assert {:error, %Tempo.ConversionError{}} = LeapSeconds.spanned(42)
  end

  test "a value extended to the microsecond is one the writer writes" do
    assert {:ok, midnight} = Tempo.at_resolution(~o"2026-06-15", :microsecond)
    assert Tempo.to_iso8601(midnight) == {:ok, "2026Y6M15DT0H0M0.000000S"}
    assert Tempo.new(hour: 10, microsecond: 5) == Tempo.new(hour: 10, microsecond: {5, 6})
  end
end
