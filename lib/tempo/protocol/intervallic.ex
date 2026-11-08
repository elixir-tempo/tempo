defprotocol Tempo.Intervallic do
  @moduledoc """
  A protocol for a value of the caller's that stands for the time it covers,
  so that it can be related to, compared with and combined with Tempo's
  expressions as it is, without first being copied into a `t:Tempo.t/0`.

  A value that implements it is accepted wherever two expressions are
  compared or combined: `Tempo.relation/2`, the predicates such as
  `Tempo.overlaps?/3` and `Tempo.within?/3`, `Tempo.compare/3` (so that
  `Enum.sort(bookings, Tempo)` sorts by time), the set operations such as
  `Tempo.union/3` and `Tempo.difference/3`, the filters such as
  `Tempo.members_overlapping/3`, `Tempo.Allen`, and the members given to
  `Tempo.IntervalSet.new/2`. Each such function reads the value with
  `to_tempo/1` once, as it is given. Other functions take a `t:Tempo.t/0`,
  which `to_tempo/1` gives.

  The answers are Tempo's expressions. A value that wants to be found again
  in an answer, a booking among the members that overlap a slot, puts itself
  in the metadata of the expression it gives: set operations keep a
  member's metadata, so the booking is in the members they answer with.

      defmodule Booking do
        defstruct [:guest, :check_in, :check_out]
      end

      defimpl Tempo.Intervallic, for: Booking do
        def to_tempo(%Booking{check_in: from, check_out: to} = booking) do
          Tempo.Interval.new(from: from, to: to, metadata: %{booking: booking})
        end
      end

  Elixir's `Date`, `Time`, `NaiveDateTime`, `DateTime` and `Date.Range`
  implement it, each read as `Tempo.from_elixir/2` reads it: a `Date` is the
  day, a `DateTime` the second in its zone. An Elixir `Duration` does not,
  a length being no span of time. Any other value stands for no expression,
  and `to_tempo/1` returns a `Tempo.ConversionError` for it.

  """

  @fallback_to_any true

  @doc """
  The expression a value stands for.

  ### Arguments

  * `value` is a value that implements the protocol.

  ### Returns

  * `{:ok, expression}`, the `t:Tempo.t/0` the value stands for, or

  * `{:error, exception}` where the value stands for no expression: a
    `Tempo.ConversionError` with reason `:not_an_expression` for a value
    that does not implement the protocol.

  ### Examples

      iex> Tempo.Intervallic.to_tempo(~D[2026-06-15])
      {:ok, ~o"2026-06-15"}

      iex> Tempo.Intervallic.to_tempo(Date.range(~D[2026-06-15], ~D[2026-06-20]))
      {:ok, ~o"2026-06-15/2026-06-20"}

  """
  @spec to_tempo(t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def to_tempo(value)
end

defimpl Tempo.Intervallic, for: Any do
  def to_tempo(value) do
    {:error, Tempo.ConversionError.exception(value: value, reason: :not_an_expression)}
  end
end

defimpl Tempo.Intervallic, for: Tempo do
  def to_tempo(expression) do
    {:ok, expression}
  end
end

for struct <- [Date, Time, NaiveDateTime, DateTime, Date.Range] do
  defimpl Tempo.Intervallic, for: struct do
    def to_tempo(value) do
      Tempo.from_elixir(value)
    end
  end
end
