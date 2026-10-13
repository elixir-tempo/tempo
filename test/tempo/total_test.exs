defmodule Tempo.TotalTest do
  use ExUnit.Case, async: false

  # Every operation on every shape of value answers, or returns or raises a
  # named error. The corpus is every class of value the grammar reads, each
  # shape in each position of each form, and every generated selection
  # (`Tempo.Matrix.Corpus`); the operations are those of `Tempo.Golden`.
  #
  # A function may return a value, `{:ok, value}` or `{:error, exception}`.
  # A predicate, a part, a walk and a bang form may raise one of Tempo's own
  # exceptions. Anything else that is raised (a function clause that does not
  # match, a key that is not there, a protocol not implemented) is a defect,
  # and so is an operation that does not come back.
  #
  # The run takes minutes, so it is excluded by default: `mix test --only total`.

  alias Tempo.Golden

  @moduletag :total
  @moduletag timeout: :infinity

  @groups [:walk, :convert, :compare, :combine, :arithmetic, :measure, :parts, :select, :format]

  # What Elixir raises for a duration, which names no span and is not walked.
  @allowed ["Protocol.UndefinedError"]

  # A duration is no expression: a function of an expression has no clause
  # for one, which is Elixir's own way of saying so.
  defp not_an_expression?(%{input: "P" <> _}, "FunctionClauseError"), do: true
  defp not_an_expression?(%{input: "-P" <> _}, "FunctionClauseError"), do: true
  defp not_an_expression?(_cell, _module), do: false

  for group <- @groups do
    test "#{group}: an answer or a named error, for every value" do
      unnamed =
        for %{out: %{"raised" => module}} = cell <- Golden.cells(unquote(group)),
            not String.starts_with?(module, "Tempo."),
            module not in @allowed,
            not not_an_expression?(cell, module) do
          "#{cell.op} of #{cell.input}#{calendar(cell)}#{arg(cell)} raised #{module}"
        end

      assert unnamed == [],
             "#{length(unnamed)} cells raised an error that is not Tempo's:\n" <>
               Enum.join(Enum.take(unnamed, 40), "\n")
    end
  end

  defp calendar(%{calendar: nil}), do: ""
  defp calendar(%{calendar: calendar}), do: " [#{calendar}]"

  defp arg(%{arg: nil}), do: ""
  defp arg(%{arg: arg}), do: " with #{arg}"
end
