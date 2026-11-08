defmodule Tempo.Operand do
  @moduledoc false

  # An operand of a comparison or a combination (decision 102): an
  # expression as it is, or any other value read as the expression it
  # stands for by `Tempo.Intervallic`, once, at the API. A duration is
  # passed on, for the function to refuse as it refuses a bare duration;
  # a value that does not implement the protocol is a `Tempo.ConversionError`.

  alias Tempo.{ConversionError, Duration, Intervallic}

  @doc "An operand as an expression: `{:ok, expression}`, or the error reading it gave."
  @spec expression(term()) :: {:ok, term()} | {:error, Exception.t()}
  def expression(%Tempo{} = expression) do
    {:ok, expression}
  end

  def expression(%Duration{} = duration) do
    {:ok, duration}
  end

  def expression(value) do
    case Intervallic.to_tempo(value) do
      {:ok, %Tempo{}} = read -> read
      {:error, %{__exception__: true}} = error -> error
      _other -> {:error, ConversionError.exception(value: value, reason: :not_an_expression)}
    end
  end

  @doc "Two operands as expressions: `{:ok, a, b}`, or the first error."
  @spec expressions(term(), term()) :: {:ok, term(), term()} | {:error, Exception.t()}
  def expressions(a, b) do
    with {:ok, a} <- expression(a),
         {:ok, b} <- expression(b) do
      {:ok, a, b}
    end
  end
end
