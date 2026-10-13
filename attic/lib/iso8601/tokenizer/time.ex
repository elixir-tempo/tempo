defmodule Tempo.Iso8601.Tokenizer.Time do
  @moduledoc false
  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Numbers
  import Tempo.Iso8601.Tokenizer.Grammar

  # Disable the Erlang optimiser for this module. See the comment on the
  # same attribute in `Tempo.Iso8601.Tokenizer` — the NimbleParsec parsers
  # here expand into large binary-matching functions whose optimiser passes
  # dominate compile time. Splitting them across modules lets `mix` compile
  # the modules concurrently; keeping the optimiser off keeps each cheap.
  @compile [:no_ssa_opt, :no_bsm_opt, :no_type_opt, :no_bool_opt, :no_fun_opt]

  # Time-of-day combinators
  defcombinator :implicit_time_of_day_p, implicit_time_of_day(), export_combinator: true
  defcombinator :extended_time_of_day_p, extended_time_of_day(), export_combinator: true
  defcombinator :explicit_time_of_day_p, explicit_time_of_day(), export_combinator: true

  # Time shift combinators
  defcombinator :implicit_time_shift_p, implicit_time_shift(), export_combinator: true
  defcombinator :extended_time_shift_p, extended_time_shift(), export_combinator: true
  defcombinator :explicit_time_shift_p, explicit_time_shift(), export_combinator: true

  # Low-level component combinators
  defcombinator :implicit_hour_p, implicit_hour(), export_combinator: true
  defcombinator :implicit_minute_p, implicit_minute(), export_combinator: true
  defcombinator :implicit_second_p, implicit_second(), export_combinator: true

  # `defparsec` (rather than `defcombinator`) so it keeps a runnable
  # public entry point `time_parser/1` — the ISO 8601 time-only test
  # corpus exercises the time tokenizer through it directly.
  # `export_combinator: true` still makes the combinator referenceable
  # cross-module via `parsec({__MODULE__, :time_parser})`.
  defparsec :time_parser,
            choice([
              parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_of_day_p})
              |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_shift_p})),
              parsec({Tempo.Iso8601.Tokenizer.Time, :extended_time_of_day_p})
              |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :extended_time_shift_p})),
              parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_time_of_day_p})
              |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_time_shift_p})),
              explicit_time_shift()
            ])
            |> tag(:time_of_day)
            |> label("time of day"),
            export_combinator: true
end
