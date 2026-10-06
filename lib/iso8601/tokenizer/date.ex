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
                |> parsec({Tempo.Iso8601.Tokenizer.Date, :datetime_or_date_or_time})
                |> optional(qualification())
                |> optional(Extended.extended_suffix())
                |> reduce(:merge_endpoint_qualification),
                export_combinator: true

  # A member of a set: a date, a date and time or a time, with the qualifiers
  # a value written alone takes (`{2026-06-15?,2026-06~}`). A member was read
  # with none, so a set held no qualified value but through a qualifier of
  # one of its components.
  #
  # And with the suffix of RFC 9557 a value written alone takes, as an end of
  # an interval has: a member in a zone of its own
  # (`{2026-06-15T10:30[Europe/Paris],2026-06-15T10:30[America/New_York]}`),
  # which is how a set of values in two zones is written and was not read.
  defcombinator :qualified_member,
                optional(qualification())
                |> parsec({Tempo.Iso8601.Tokenizer.Date, :datetime_or_date_or_time})
                |> optional(qualification())
                |> optional(Extended.extended_suffix())
                |> reduce(:merge_member_qualification),
                export_combinator: true

  # The end of an interval written as a day and a time of day, the year and
  # the month left out: `2007-11-13T09:00/15T17:00` ends on the 15th at
  # 17:00 (ISO 8601-1:2019 §5.5.1). No value is written so on its own, where
  # two digits are a century, so this is an end's form only, and the
  # interval parser tries it where two digits and a `T` follow the solidus.
  defcombinator :day_and_time_endpoint,
                optional(qualification())
                |> concat(
                  integer(2)
                  |> unwrap_and_tag(:day)
                  |> lookahead(string("T"))
                  |> choice([
                    parsec({Tempo.Iso8601.Tokenizer.Time, :extended_time_of_day_p})
                    |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :extended_time_shift_p})),
                    parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_time_of_day_p})
                    |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_time_shift_p}))
                  ])
                  |> tag(:datetime)
                )
                |> optional(qualification())
                |> optional(Extended.extended_suffix())
                |> reduce(:merge_endpoint_qualification),
                export_combinator: true

  # The end of an interval written as one bare number of one, two or three
  # digits, with nothing after it that makes it more: `2026-06-15/20`,
  # `2026-166/170`, `2026-W25-1/5`. What the number is depends on the start
  # (`Tempo.Iso8601.Tokenizer.Grammar.adjust_interval/5`), so it is tagged
  # with the digits it was written with. A decimal sign and a digit after
  # it make it a number with a fraction, which this is not.
  defcombinator :bare_number_endpoint,
                optional(qualification())
                |> concat(
                  choice([
                    integer(3) |> unwrap_and_tag(:three_digits),
                    integer(2) |> unwrap_and_tag(:two_digits),
                    integer(1) |> unwrap_and_tag(:one_digit)
                  ])
                  |> lookahead(
                    choice([
                      eos(),
                      ascii_char([?[, ?/, ?}, ?], ??, ?~, ?%]),
                      ascii_char([?,]) |> lookahead_not(digit())
                    ])
                  )
                  |> tag(:date)
                )
                |> optional(qualification())
                |> optional(Extended.extended_suffix())
                |> reduce(:merge_endpoint_qualification),
                export_combinator: true

  # The explicit date — the form selections and §12.10 windows take — is parsed
  # once and then classified by what follows it: an explicit time of day makes
  # it a datetime; otherwise it is a date, with the date path's fraction folding
  # and validation. Trying `datetime_parser` and then `date_parser` parsed every
  # explicit date twice (as a datetime prefix, then again as a date), which
  # doubled at each level a selection or window nests. Hoisting it chooses what
  # the original order did: an explicit date carries designator letters, which
  # no extended or implicit datetime can continue into, and an explicit time
  # shift starts with `Z`. Anything else falls through to the remaining
  # alternatives in their original order, less the explicit date-time one, which
  # could only re-parse the explicit date and fail again. `date_parser`'s
  # explicit date stays, so an explicit date failing validation still fails
  # exactly as it did. Exported for the grammar and the set parser; this module
  # is hidden, so NimbleParsec's generated clauses stay out of the docs.
  defcombinator :datetime_or_date_or_time,
                choice([
                  parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_date_p})
                  |> choice([
                    parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_of_day_p})
                    |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_shift_p}))
                    |> replace(empty(), :__explicit_datetime__),
                    optional(parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_shift_p}))
                    |> replace(empty(), :__explicit_date__)
                  ])
                  |> post_traverse({:classify_explicit_date, []}),
                  # A month alone with a time after it (`6MT10H`), which the
                  # explicit date leaves to a date-time, as `2026Y6MT10H` is.
                  # The time is written with its `T`: without one, `1M2S` is
                  # a minute and a second.
                  parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_month_p})
                  |> lookahead(string("T"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_of_day_p})
                  |> optional(parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_shift_p}))
                  |> tag(:datetime),
                  parsec({Tempo.Iso8601.Tokenizer.Date, :non_explicit_datetime_parser}),
                  parsec({Tempo.Iso8601.Tokenizer.Date, :date_parser}),
                  parsec({Tempo.Iso8601.Tokenizer.Time, :time_parser})
                ])
                |> label("datetime_or_date_or_time"),
                export_combinator: true

  # Finish an explicit date parsed once by `datetime_or_date_or_time`: with a time
  # of day it is tagged `:datetime` exactly as `datetime_parser` does; without,
  # it takes `date_parser`'s path — fold any fraction, validate the month and
  # day, tag `:date`. The accumulator arrives reversed, the marker first.
  @doc false
  def classify_explicit_date(rest, [:__explicit_datetime__ | tokens], context, _line, _offset) do
    {rest, [{:datetime, Enum.reverse(tokens)}], context}
  end

  def classify_explicit_date(rest, [:__explicit_date__ | tokens], context, line, offset) do
    date = tokens |> Enum.reverse() |> apply_fraction()

    case check_valid_date(rest, [date], context, line, offset) do
      {rest, [date], context} -> {rest, [{:date, date}], context}
      {:error, _reason} = error -> error
    end
  end

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
