defmodule Tempo.Iso8601.Tokenizer.Set do
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

  defcombinator :integer_or_integer_set,
                choice([
                  integer(min: 1) |> unwrap_and_tag(:nth),
                  parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
                  parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_one})
                ])
                |> label("integer or integer set"),
                export_combinator: true

  defcombinator :set_all,
                ignore(string("{"))
                |> list_of_time_or_range()
                |> ignore(string("}"))
                |> tag(:all_of),
                export_combinator: true

  defcombinator :set_one,
                ignore(string("["))
                |> list_of_time_or_range()
                |> ignore(string("]"))
                |> tag(:one_of),
                export_combinator: true

  defcombinator :integer_set_all,
                ignore(string("{"))
                |> list_of_integer_or_range()
                |> ignore(string("}"))
                |> tag(:all_of),
                export_combinator: true

  defcombinator :integer_set_one,
                ignore(string("["))
                |> list_of_integer_or_range()
                |> ignore(string("]"))
                |> tag(:one_of),
                export_combinator: true

  defcombinator :interval_parser,
                optional(recurrence())
                |> choice([
                  # domain-set/duration — a recurrence over a domain of values
                  # (years, with `^` exclusions), e.g. R/{2020Y..2030Y,^2026Y}/P1Y.
                  # Tagged `:domain_set` (distinct from an `:all_of` group/set) so
                  # the parser builds it as the recurrence's window in `:from`.
                  ignore(string("{"))
                  |> list_of_time_or_range()
                  |> ignore(string("}"))
                  |> optional(domain_filter())
                  |> tag(:domain_set)
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}),

                  # ^value/duration — a recurrence excluding a single value, e.g.
                  # R/^2026Y/P1Y (no braces — the "single value needs no set"
                  # form). Sugar for a domain with one `^` exclusion and no
                  # included members.
                  ignore(string("^"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint})
                  |> tag(:except)
                  |> tag(:domain_set)
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}),

                  # date/date — each endpoint may carry an EDTF qualification
                  parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint})
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint}),

                  # date/duration
                  parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint})
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}),

                  # duration/date
                  parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser})
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint}),

                  # date/..
                  parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint})
                  |> ignore(string("/"))
                  |> replace(string(".."), :undefined),

                  # ../date
                  replace(string(".."), :undefined)
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint}),

                  # ..<filter>/duration — an open, filtered domain (all even/odd/
                  # leap years), e.g. R/..e/P1Y. Like an exclusions-only domain it
                  # has no window of its own, so it needs a `:bound` to materialise.
                  ignore(string(".."))
                  |> domain_filter()
                  |> tag(:domain_set)
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}),

                  # ../duration — an unanchored recurrence (no start), e.g. a cron
                  # schedule with no `:from`, which inspects as `R/../P1W/…`
                  replace(string(".."), :undefined)
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}),

                  # date/ (trailing slash — open upper endpoint)
                  parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint})
                  |> ignore(string("/"))
                  |> replace(empty(), :undefined),

                  # /date (leading slash — open lower endpoint)
                  replace(empty(), :undefined)
                  |> ignore(string("/"))
                  |> parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_endpoint}),

                  # ../.. or /.. or ../ or / (both endpoints open)
                  replace(choice([string(".."), empty()]), :undefined)
                  |> ignore(string("/"))
                  |> replace(choice([string(".."), empty()]), :undefined)
                ])
                |> optional(parsec({Tempo.Iso8601.Tokenizer.Set, :repeat_rule}))
                |> reduce(:adjust_interval)
                |> unwrap_and_tag(:interval)
                |> label("interval"),
                export_combinator: true

  defcombinator :group,
                parsec({Tempo.Iso8601.Tokenizer.Set, :integer_or_integer_set})
                |> ignore(string("G"))
                |> parsec({Tempo.Iso8601.Tokenizer.Set, :duration_elements_p})
                |> ignore(string("U"))
                |> tag(:group)
                |> label("group"),
                export_combinator: true

  defcombinator :time_group,
                parsec({Tempo.Iso8601.Tokenizer.Set, :integer_or_integer_set})
                |> ignore(string("G"))
                |> parsec({Tempo.Iso8601.Tokenizer.Set, :duration_time_elements_p})
                |> ignore(string("U"))
                |> tag(:group)
                |> label("time group"),
                export_combinator: true

  defcombinator :selection,
                ignore(string("L"))
                |> selection_elements()
                |> optional(selection_instance())
                |> ignore(string("N"))
                |> tag(:selection)
                |> label("selection"),
                export_combinator: true

  defcombinator :duration_parser,
                optional(negative() |> replace({:direction, :negative}))
                |> ignore(string("P"))
                |> concat(parsec({Tempo.Iso8601.Tokenizer.Set, :duration_elements_p}))
                |> tag(:duration)
                |> label("duration"),
                export_combinator: true

  defcombinator :repeat_rule,
                ignore(string("/F"))
                |> parsec({Tempo.Iso8601.Tokenizer, :datetime_or_date_or_time})
                |> reduce(:extract_repeat_rule)
                |> label("repeat_rule")
                |> unwrap_and_tag(:repeat_rule),
                export_combinator: true

  # Duration element combinators
  defcombinator :duration_elements_p, duration_elements(), export_combinator: true
  defcombinator :duration_time_elements_p, duration_time_elements(), export_combinator: true
end
