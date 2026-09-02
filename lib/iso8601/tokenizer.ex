defmodule Tempo.Iso8601.Tokenizer do
  @moduledoc """
  Tokenizes an ISO 8601 (parts 1 and 2) or IXDTF string into a
  list of tagged tokens that the internal parser then converts
  into a `t:Tempo.t/0` struct.

  `tokenize/1` returns a 2-tuple `{tokens, extended_info}` where
  `extended_info` is either `nil` or a map of parsed
  [IXDTF](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html)
  suffix information.  See `Tempo.Iso8601.Tokenizer.Extended` for
  the shape of the extended map.

  """

  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Grammar

  alias Tempo.Iso8601.Tokenizer.Extended
  alias Tempo.ParseError

  # Guard against pathological input. Legitimate ISO 8601 / IXDTF
  # strings are short; a multi-kilobyte string is almost certainly
  # adversarial, and a long digit run costs super-linear time to
  # tokenize. Reject over-long input up front rather than let the
  # parser chew on it.
  @max_input_bytes 8_192

  # Bracket-nesting (`{…}` / `[…]`) is the parser's one exponential
  # axis: each level multiplies the combinator alternatives tried,
  # so deep nesting (or an unbalanced run of openers) costs
  # exponential time. Legitimate ISO 8601-2 sets and groups nest at
  # most two or three deep, so a small cap rejects the pathological
  # cases up front while leaving every real value untouched.
  @max_nesting_depth 6

  # The shapes `tokenize/2` can be asked to require. Durations are
  # deliberately absent — see `tokenize_duration/1`.
  @profiles [:date, :datetime, :time, :interval]

  @doc """
  Tokenize an ISO 8601 or IXDTF string.

  ### Arguments

  * `string` is any ISO 8601 formatted string, optionally with an
    [IXDTF](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html)
    suffix (such as `[Europe/Paris][u-ca=hebrew]`).

  ### Returns

  * `{:ok, {tokens, extended_info}}` where `tokens` is the list of
    ISO 8601 tokens produced by the parser and `extended_info` is
    either `nil` (when no IXDTF suffix was present) or a map with
    keys `:calendar`, `:zone_id`, `:zone_offset` and `:tags`.

  * `{:error, reason}` when the string cannot be parsed or a
    critical IXDTF suffix is unrecognised.

  """
  def tokenize(string) when byte_size(string) > @max_input_bytes do
    {:error,
     ParseError.exception(
       input: binary_part(string, 0, 64) <> "…",
       reason: "Input of #{byte_size(string)} bytes exceeds the #{@max_input_bytes}-byte limit"
     )}
  end

  def tokenize(string) do
    if nesting_exceeds_limit?(string) do
      {:error,
       ParseError.exception(
         input: string,
         reason: "Set/group nesting exceeds the depth limit of #{@max_nesting_depth}"
       )}
    else
      string
      |> iso8601()
      |> return(string)
    end
  end

  @doc """
  Tokenise a string that must be an ISO 8601 duration.

  Unlike `tokenize/1`, which admits every shape the standard defines,
  this recognises only a duration and requires the whole input to be
  one — the caller has declared the profile its value belongs to.

  ### Arguments

  * `string` is the candidate duration.

  ### Returns

  * `{:ok, tokens}` where `tokens` is `[duration: components]`, the
    same shape `tokenize/1` produces for a duration.

  * `{:error, %Tempo.ParseError{}}` when the string is not a duration,
    or is a duration followed by anything else.

  """
  def tokenize_duration(string) when byte_size(string) > @max_input_bytes do
    {:error,
     ParseError.exception(
       input: binary_part(string, 0, 64) <> "…",
       reason: "Input of #{byte_size(string)} bytes exceeds the #{@max_input_bytes}-byte limit"
     )}
  end

  def tokenize_duration(string) do
    case duration_only(string) do
      {:ok, tokens, "", _context, _line, _column} ->
        {:ok, tokens}

      {:ok, _tokens, remaining, _context, _line, _column} ->
        {:error,
         ParseError.exception(
           input: string,
           reason:
             "Could not parse #{inspect(string)} as a duration. " <>
               "Error detected at #{inspect(remaining)}"
         )}

      {:error, message, detected_at, _context, _line, _column} ->
        {:error,
         ParseError.exception(
           input: string,
           reason:
             "Could not parse #{inspect(string)} as a duration. " <>
               String.capitalize(message) <> ". Error detected at #{inspect(detected_at)}"
         )}
    end
  end

  @doc """
  Tokenise a string that must match a single ISO 8601 profile.

  Where `tokenize/1` admits every shape the standard defines and
  reports which one it found, this requires the whole input to be the
  named shape — the caller has declared the profile its value belongs
  to. A value that merely *begins* with that shape is rejected rather
  than silently truncated.

  Durations have their own entry point, `tokenize_duration/1`, because
  a duration carries neither an EDTF qualification nor an IXDTF suffix
  and so returns tokens alone rather than a `{tokens, extended}` pair.

  ### Arguments

  * `string` is the candidate ISO 8601 value.

  * `profile` is one of `:date`, `:datetime`, `:time` or `:interval`.

  ### Returns

  * `{:ok, {tokens, extended_info}}` in the same shape `tokenize/1`
    returns.

  * `{:error, %Tempo.ParseError{}}` when the string is not the named
    profile, or is that profile followed by anything else.

  """
  def tokenize(string, profile)
      when profile in @profiles and byte_size(string) > @max_input_bytes do
    {:error,
     ParseError.exception(
       input: binary_part(string, 0, 64) <> "…",
       reason: "Input of #{byte_size(string)} bytes exceeds the #{@max_input_bytes}-byte limit"
     )}
  end

  def tokenize(string, profile) when profile in @profiles do
    if nesting_exceeds_limit?(string) do
      {:error,
       ParseError.exception(
         input: string,
         reason: "Set/group nesting exceeds the depth limit of #{@max_nesting_depth}"
       )}
    else
      string
      |> parse_profile(profile)
      |> return_profile(string, profile)
    end
  end

  defp parse_profile(string, :date), do: date_only(string)
  defp parse_profile(string, :datetime), do: datetime_only(string)
  defp parse_profile(string, :time), do: time_only(string)
  defp parse_profile(string, :interval), do: interval_only(string)

  # Mirrors `return/2` but names the profile in the failure, so the
  # error says what the value was required to be rather than only that
  # it could not be parsed.
  defp return_profile({:ok, tokens, "", %{}, {_line, _}, _column}, _string, _profile) do
    Extended.split_extended(tokens)
  end

  defp return_profile({:ok, _tokens, remaining, _, {_line, _}, _column}, string, profile) do
    {:error,
     ParseError.exception(
       input: string,
       reason:
         "Could not parse #{inspect(string)} as #{article(profile)}. " <>
           "Error detected at #{inspect(remaining)}"
     )}
  end

  defp return_profile({:error, message, detected_at, _, _, _}, string, profile) do
    {:error,
     ParseError.exception(
       input: string,
       reason:
         "Could not parse #{inspect(string)} as #{article(profile)}. " <>
           String.capitalize(message) <> ". Error detected at #{inspect(detected_at)}"
     )}
  end

  defp article(:date), do: "a date"
  defp article(:datetime), do: "a datetime"
  defp article(:time), do: "a time"
  defp article(:interval), do: "an interval"

  # Walk the string once, tracking `{`/`[` open-bracket depth, and
  # report whether it ever exceeds the limit (an unbalanced run of
  # openers keeps climbing and is caught the same way).
  defp nesting_exceeds_limit?(string) do
    string
    |> :binary.bin_to_list()
    |> Enum.reduce_while(0, fn
      char, depth when char in [?{, ?[] ->
        if depth + 1 > @max_nesting_depth, do: {:halt, :exceeded}, else: {:cont, depth + 1}

      char, depth when char in [?}, ?]] ->
        {:cont, max(depth - 1, 0)}

      _char, depth ->
        {:cont, depth}
    end) == :exceeded
  end

  defp return(result, string) do
    case result do
      {:ok, tokens, "", %{}, {_, _}, _} ->
        Extended.split_extended(tokens)

      {:ok, _tokens, remaining, _, {_line, _}, _char} ->
        {:error,
         ParseError.exception(
           input: string,
           reason: "Could not parse #{inspect(string)}. Error detected at #{inspect(remaining)}"
         )}

      {:error, message, detected_at, _, _, _} ->
        {:error,
         ParseError.exception(
           input: string,
           reason: String.capitalize(message) <> ". Error detected at #{inspect(detected_at)}"
         )}
    end
  end

  # The single true entry point, called directly by `tokenize/1`. Every
  # other parser is internal — referenced only via `parsec/1` — and lives
  # in one of the sibling tokenizer modules (`.Date`, `.Time`, `.Set`) so
  # `mix` compiles them concurrently. NimbleParsec resolves a
  # `parsec({Module, :name})` reference against that module's exported
  # combinator, so the grammar is split across modules without changing
  # behaviour.
  defparsec :iso8601, iso8601_tokenizer()

  # A second entry point admitting *only* a duration. `duration_parser`
  # already tags its result `:duration`, so the token shape matches what
  # the general entry produces for a duration and the parser stage is
  # shared. Requiring `eos/0` is what makes the profile a profile: a
  # value that merely *starts* with a duration (`P1D/2026-06-15`, or a
  # duration carrying a qualifier) is rejected rather than silently
  # truncated.
  defparsec :duration_only,
            parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}) |> eos()

  # Profile entry points, one per shape a caller may want to *require*.
  # Each wraps its core parser in `profile_tokenizer/1` (so EDTF
  # qualification and the IXDTF suffix still apply) and terminates with
  # `eos/0`, which is what turns a shape into a profile: `2026-06-15` is
  # not a datetime, and `2026-06-15/2026-06-20` is not a date, even
  # though the general grammar can begin parsing both as one.
  defparsec :date_only,
            profile_tokenizer(parsec({Tempo.Iso8601.Tokenizer.Date, :date_parser})) |> eos()

  defparsec :datetime_only,
            profile_tokenizer(parsec({Tempo.Iso8601.Tokenizer.Date, :datetime_parser})) |> eos()

  defparsec :time_only,
            profile_tokenizer(parsec({Tempo.Iso8601.Tokenizer.Time, :time_parser})) |> eos()

  defparsec :interval_only,
            profile_tokenizer(parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser})) |> eos()

  # `set` and `datetime_or_date_or_time` stay here but are now referenced
  # from the sibling modules, so they are exported combinators. Their inner
  # `parsec/1` references are qualified to each parser's home module.
  defcombinator :set,
                choice([
                  parsec({Tempo.Iso8601.Tokenizer.Set, :set_all}),
                  parsec({Tempo.Iso8601.Tokenizer.Set, :set_one}),
                  parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser}),
                  parsec({Tempo.Iso8601.Tokenizer, :datetime_or_date_or_time})
                ]),
                export_combinator: true

  defcombinator :datetime_or_date_or_time,
                choice([
                  parsec({Tempo.Iso8601.Tokenizer.Date, :datetime_parser}),
                  parsec({Tempo.Iso8601.Tokenizer.Date, :date_parser}),
                  parsec({Tempo.Iso8601.Tokenizer.Time, :time_parser})
                ])
                |> label("datetime_or_date_or_time"),
                export_combinator: true
end
