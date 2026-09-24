defmodule Tempo.Iso8601.Tokenizer.Date do
  @moduledoc false
  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Numbers
  import Tempo.Iso8601.Tokenizer.Grammar
  import Tempo.Iso8601.Tokenizer.Helpers

  # Disable the Erlang optimiser for this module. See the comment on the
  # same attribute in `Tempo.Iso8601.Tokenizer` — the NimbleParsec parsers
  # here expand into large binary-matching functions whose optimiser passes
  # dominate compile time. Splitting them across modules lets `mix` compile
  # the modules concurrently; keeping the optimiser off keeps each cheap.
  @compile [:no_ssa_opt, :no_bsm_opt, :no_type_opt, :no_bool_opt, :no_fun_opt]

  alias Tempo.Iso8601.Tokenizer.Extended

  # A date/datetime/time endpoint with an optional EDTF
  # qualification prefix or suffix (`?`, `~`, `%`) and an optional
  # IXDTF extended-info suffix (`[Europe/Paris][u-ca=hebrew]`). The
  # qualifier, when present, is merged into the tagged date's inner
  # keyword list so each interval endpoint retains its own
  # qualification. The extended-info segments are spliced into the
  # endpoint's inner list as `{:extended, raw_segments}` and later
  # validated by `Extended.split_extended/1`, which bubbles any
  # critical-suffix error back up to the parser's return path.
  # Exported so the interval parser in `Tempo.Iso8601.Tokenizer.Set`
  # can reference it cross-module via `parsec/1`.
  defcombinator :qualified_endpoint,
                optional(qualification())
                |> parsec({Tempo.Iso8601.Tokenizer, :datetime_or_date_or_time})
                |> optional(qualification())
                |> optional(Extended.extended_suffix())
                |> reduce(:merge_endpoint_qualification),
                export_combinator: true

  # Date combinators
  defcombinator :implicit_date_p, implicit_date(), export_combinator: true
  defcombinator :extended_date_p, extended_date(), export_combinator: true
  defcombinator :explicit_date_p, explicit_date(), export_combinator: true

  # Low-level component combinators
  defcombinator :implicit_year_p, implicit_year(), export_combinator: true
  defcombinator :implicit_month_p, implicit_month(), export_combinator: true
  defcombinator :implicit_day_of_month_p, implicit_day_of_month(), export_combinator: true
  defcombinator :implicit_week_p, implicit_week(), export_combinator: true
  defcombinator :implicit_day_of_week_p, implicit_day_of_week(), export_combinator: true
  defcombinator :implicit_day_of_year_p, implicit_day_of_year(), export_combinator: true

  # Explicit composite combinators
  defcombinator :explicit_century_decade_or_year_p,
                explicit_century_decade_or_year(),
                export_combinator: true

  defcombinator :explicit_month_p, explicit_month(), export_combinator: true
  defcombinator :explicit_week_p, explicit_week(), export_combinator: true

  defcombinator :datetime_parser,
                choice([
                  explicit_date_time()
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_shift_p})),
                  extended_date_time()
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :extended_time_shift_p})),
                  implicit_date_time()
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_time_shift_p})),
                  explicit_time_shift()
                ])
                |> tag(:datetime)
                |> label("datetime"),
                export_combinator: true

  # `datetime_parser` without its explicit date-time alternative, for
  # `datetime_or_date_or_time`, which has already tried the explicit date once
  # (with or without a time) before falling through to here — so that
  # alternative could only re-parse the explicit date and fail again.
  defcombinator :non_explicit_datetime_parser,
                choice([
                  extended_date_time()
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :extended_time_shift_p})),
                  implicit_date_time()
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_time_shift_p})),
                  explicit_time_shift()
                ])
                |> tag(:datetime)
                |> label("datetime"),
                export_combinator: true

  defcombinator :date_parser,
                choice([
                  parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_date_p})
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_shift_p})),
                  parsec({Tempo.Iso8601.Tokenizer.Date, :extended_date_p})
                  |> optional(fraction())
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :extended_time_shift_p})),
                  parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_date_p})
                  |> optional(fraction())
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_time_shift_p})),
                  explicit_time_shift()
                ])
                |> reduce(:apply_fraction)
                |> post_traverse({:check_valid_date, []})
                |> unwrap_and_tag(:date)
                |> label("date"),
                export_combinator: true
end
