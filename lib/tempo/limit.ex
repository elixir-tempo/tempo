defmodule Tempo.Limit do
  @moduledoc false

  # The most values Tempo gives at once: the values of one that are listed,
  # the spans one is converted to, the occurrences of a recurrence and the
  # periods its walk takes, and the candidates a position picks among. A
  # value that names more is refused, so that a short string cannot ask for
  # work without end: `2026Y{1..12}M{1..28}DT{0..23}H{0..59}M{0..59}S` names
  # 29 million seconds.
  #
  # It is the application's `:max_values_at_once`, 10,000 unless it is set,
  # and is read when Tempo is compiled, so that each module that refuses
  # holds it in an attribute, where a guard and a pattern can use it:
  #
  #     config :ex_tempo, max_values_at_once: 100_000
  #
  # This module depends on no other of Tempo's, so that any of them can ask
  # it as it is compiled.
  @default 10_000
  @values_at_once Application.compile_env(:ex_tempo, :max_values_at_once, @default)

  if not is_integer(@values_at_once) or @values_at_once < 1 do
    raise ArgumentError,
          "The :max_values_at_once of :ex_tempo is the most values Tempo gives at once, a whole " <>
            "number of 1 or more (#{@default} unless it is set). Found: " <>
            inspect(@values_at_once)
  end

  # The function returns the number it was compiled with, so its contract
  # is that number: a wider one (`pos_integer()`) is more than Dialyzer
  # finds it to return.
  @doc false
  @spec values_at_once() :: unquote(@values_at_once)
  def values_at_once, do: @values_at_once
end
