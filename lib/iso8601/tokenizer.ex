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
  alias Tempo.Iso8601.Tokenizer.Memo
  alias Tempo.Iso8601.Tokenizer.Plain
  alias Tempo.ParseError

  # Guard against pathological input. Legitimate ISO 8601 / IXDTF
  # strings are short; a multi-kilobyte string is almost certainly
  # adversarial, and a long digit run costs super-linear time to
  # tokenize. Reject over-long input up front rather than let the
  # parser chew on it.
  @max_input_bytes 8_192

  # What is opened inside what, and how long a number is, are bounded
  # before the grammar is tried, as the length of the text is. Each bound
  # is far past what a value is written with, and the grammar's work within
  # it is small: a set or a selection is read once at each place it is tried
  # (`Tempo.Iso8601.Tokenizer.Memo`), so a level of nesting costs a
  # constant, where it multiplied the alternatives tried.
  #
  # * Sets and groups (`{…}`, `[…]`) are written two or three deep.
  #
  # * Selections (`L…N`) are written three deep for a window (`LLL…N/P5DN…N`,
  #   ISO 8601-2 §12.10) and two more for each window inside one.
  #
  # * A number is a year, a count or a fraction of a second. Each
  #   alternative that reads a number reads all of its digits, so a long
  #   run of them cost time in proportion to its length squared: three
  #   quarters of a second for eight thousand.
  @max_nesting_depth 6
  @max_selection_depth 16
  @max_digits 128

  # The shapes `tokenize/2` can be asked to require. Durations are
  # deliberately absent — see `tokenize_duration/1`.
  @profiles [:date, :datetime, :time, :interval]

  @doc false
  # Whether a text is no longer than any reader of Tempo's is given: `:ok`,
  # or the error of one that is. The reader of a locale's words
  # (`Tempo.parse/2`) asks it too, so that a text the tokenizer refuses for
  # its length is not then read another way.
  @spec within_length(binary()) :: :ok | {:error, ParseError.t()}
  def within_length(string) when byte_size(string) > @max_input_bytes,
    do: {:error, too_long(string)}

  def within_length(_string), do: :ok

  defp too_long(string) do
    ParseError.exception(
      input: binary_part(string, 0, 64) <> "…",
      reason: "Input of #{byte_size(string)} bytes exceeds the #{@max_input_bytes}-byte limit"
    )
  end

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
    {:error, too_long(string)}
  end

  # A plain date or time of day is read by its bytes
  # (`Tempo.Iso8601.Tokenizer.Plain`), alone or before an IXDTF suffix, and
  # every other form by the grammar.
  def tokenize(string) do
    case plain(string) do
      {:ok, _tokens_and_suffix} = read -> read
      :general -> tokenize_by_grammar(string)
    end
  end

  # The suffix (`[Europe/Paris]`, `[u-ca=hebrew]`) is what follows the first
  # `[`, and is read by the grammar's own rule for one, so that a plain
  # value in a zone is not sent through every other form first. Anything
  # the two do not read between them is the whole grammar's to answer.
  defp plain(string) do
    case :binary.match(string, "[") do
      :nomatch -> with {:ok, tokens} <- plain_tokens(string), do: {:ok, {tokens, nil}}
      {at, 1} -> plain_with_suffix(string, at)
    end
  end

  # A value, and where it is none an interval of plain ends or a plain
  # duration.
  defp plain_tokens(string) do
    with :general <- Plain.tokens(string), do: Plain.span(string)
  end

  defp plain_with_suffix(string, at) do
    with {:ok, tokens} <- Plain.tokens(binary_part(string, 0, at)),
         {:ok, suffix, "", %{}, _line, _column} <-
           suffix_only(binary_part(string, at, byte_size(string) - at)),
         {:ok, _tokens_and_suffix} = read <- Extended.split_extended(tokens ++ suffix) do
      read
    else
      _not_read -> :general
    end
  end

  @doc false
  # The grammar's reading of a string, whatever its form: what
  # `tokenize/1` gives for every string, and the measure the scan of the
  # plain forms is held to.
  def tokenize_by_grammar(string) when byte_size(string) > @max_input_bytes,
    do: tokenize(string)

  def tokenize_by_grammar(string) do
    with :ok <- within_limits(string) do
      Memo.reading(fn -> string |> iso8601() |> return(string) end)
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
    {:error, too_long(string)}
  end

  def tokenize_duration(string) do
    with :ok <- within_limits(string), do: tokenize_duration_by_grammar(string)
  end

  defp tokenize_duration_by_grammar(string) do
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
    {:error, too_long(string)}
  end

  def tokenize(string, profile) when profile in @profiles do
    with :ok <- within_limits(string) do
      Memo.reading(fn ->
        string |> parse_profile(profile) |> return_profile(string, profile)
      end)
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

  # Walks the text once and says which bound it is past, if any.
  #
  # What is open is kept innermost first. A bracket closes what was opened
  # inside it with it: the `L` of `[Europe/London]` is no selection, and is
  # gone with its bracket. An `N` closes a selection only where one is the
  # innermost thing open. A closer with nothing to close changes nothing, so
  # a run of openers with none closed keeps climbing and is caught.
  defp within_limits(string) do
    case over_a_limit(string, [], 0) do
      nil -> :ok
      reason -> {:error, ParseError.exception(input: string, reason: reason)}
    end
  end

  defp over_a_limit(<<char, rest::binary>>, open, digits) when char in ?0..?9 or char == ?X do
    if digits < @max_digits,
      do: over_a_limit(rest, open, digits + 1),
      else: "A number exceeds the limit of #{@max_digits} digits"
  end

  defp over_a_limit(<<char, rest::binary>>, open, _digits) when char in [?{, ?[] do
    if opened(open, :bracket) < @max_nesting_depth,
      do: over_a_limit(rest, [:bracket | open], 0),
      else: "Set/group nesting exceeds the depth limit of #{@max_nesting_depth}"
  end

  defp over_a_limit(<<?L, rest::binary>>, open, _digits) do
    if opened(open, :selection) < @max_selection_depth,
      do: over_a_limit(rest, [:selection | open], 0),
      else: "Selection nesting exceeds the depth limit of #{@max_selection_depth}"
  end

  defp over_a_limit(<<char, rest::binary>>, open, _digits) when char in [?}, ?]],
    do: over_a_limit(rest, bracket_closed(open), 0)

  defp over_a_limit(<<?N, rest::binary>>, [:selection | open], _digits),
    do: over_a_limit(rest, open, 0)

  defp over_a_limit(<<_char, rest::binary>>, open, _digits), do: over_a_limit(rest, open, 0)
  defp over_a_limit(<<>>, _open, _digits), do: nil

  defp opened(open, kind), do: Enum.count(open, &(&1 == kind))

  defp bracket_closed(open) do
    case Enum.drop_while(open, &(&1 != :bracket)) do
      [:bracket | outside] -> outside
      [] -> open
    end
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

  # The IXDTF suffix alone, which follows a value the scan of the plain
  # forms has read (`plain_with_suffix/2`).
  defparsec :suffix_only, Extended.extended_suffix() |> eos()

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
end
