defmodule Tempo.Iso8601.Tokenizer.Numbers do
  @moduledoc """
  Numbers aren't just numbers in ISO8601 when considering
  the extension formats. In some situations they may:

  * Have exponents
  * Have significant digits (the `S` suffix)
  * Have unspecified digits

  And how these are formed varies by whether the
  number is being parsed for an implicit form,
  extended form or explicit form.

  ## Implicit form

  * Numbers are always positive with no sign
  except when its the year in which case it may have
  a negative sign.

  * Numbers are always a positive integer, or a the
    "unspecified" symbol `X` in any digit location. Numbers
    are either 2, 3 or 4 digits wide (decades are three
    digits) and this implementation does not currently
    support more than 4 digits for years.

  * Significant digits are not supported.

  ** Extended form

  * Same as the Implicit Form

  ## Explicit form

  * Numbers may be positive of negative

  * The "unspecified" symbol `X` may appear in
    any digit location.

  * The symbol `X*` means the entire
    field is unspecified.

  * Exponent and significant digits are supported,
    but only if the number is an integer (ie does
    not have unspecified digits).

  """
  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Helpers

  alias Tempo.Microsecond

  def positive_number(combinator \\ empty(), opts)

  def positive_number(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      integer(n)
      |> optional(fraction())
      |> optional(exponent())
      |> optional(significant())
      |> optional(error_range())
      |> lookahead_not(unspecified_or_set())
      |> reduce(:form_number),
      all_unspecified()
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask),
      digit_or_unspecified()
      |> times(n)
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask)
    ])
    |> label("positive number")
  end

  def positive_number(combinator, opts) do
    combinator
    |> choice([
      integer(opts)
      |> optional(fraction())
      |> optional(exponent())
      |> optional(significant())
      |> optional(error_range())
      |> lookahead_not(unspecified_or_set())
      |> reduce(:form_number),
      all_unspecified()
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask),
      digit_or_unspecified()
      |> times(opts)
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask)
    ])
    |> reduce(:form_number)
    |> label("positive number")
  end

  def positive_integer(combinator \\ empty(), opts)

  def positive_integer(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      integer(n)
      |> optional(exponent())
      |> optional(significant())
      |> optional(error_range())
      |> lookahead_not(unspecified_or_set())
      |> reduce(:form_number),
      all_unspecified()
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask),
      digit_or_unspecified()
      |> times(n)
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask)
    ])
    |> label("positive integer")
  end

  def positive_integer(combinator, opts) do
    combinator
    |> choice([
      integer(opts)
      |> lookahead_not(unspecified())
      |> optional(exponent())
      |> optional(significant())
      |> optional(error_range())
      |> lookahead_not(unspecified_or_set())
      |> reduce(:form_number),
      all_unspecified()
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask),
      digit_or_unspecified()
      |> times(opts)
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask)
    ])
    |> label("positive integer")
  end

  def maybe_negative_number(combinator \\ empty(), opts) do
    combinator
    |> optional(negative())
    |> positive_number(opts)
    |> reduce(:form_number)
    |> label("maybe negative number")
  end

  def maybe_negative_integer(combinator \\ empty(), opts) do
    combinator
    |> optional(negative())
    |> positive_integer(opts)
    |> reduce(:form_number)
    |> label("maybe negative integer")
  end

  def positive_number_or_integer_set(indicator, tag, opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_one}),
      positive_number(opts)
    ])
    |> ignore(string(indicator))
    |> unwrap_and_tag(tag)
  end

  # No indicator: a bare `[...]` here would be ambiguous with a
  # top-level one-of set (`[1984,1986,1988]`), so only `{...}`
  # (all-of) is accepted in the designator-less position.
  def positive_number_or_integer_set(tag, opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      positive_number(opts)
    ])
    |> unwrap_and_tag(tag)
  end

  def maybe_negative_number_or_integer_set(indicator, tag, opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_one}),
      maybe_negative_number(opts)
    ])
    |> ignore(string(indicator))
    |> unwrap_and_tag(tag)
  end

  # As `maybe_negative_number_or_integer_set/3` but allows an ISO
  # 8601-2 §8.3 explicit qualifier (`?`, `~`, `%`) between the value
  # and its designator (`2018?Y`, `6~M`, `11%D`). In explicit form a
  # qualifier is always *individual* (§8.2.3) — the designator makes
  # each component self-delimiting — so it emits the same
  # `:individual_qualification` token the implicit left-qualifier does.
  def qualified_number_or_integer_set(indicator, tag, opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_one}),
      maybe_negative_number(opts)
    ])
    |> unwrap_and_tag(tag)
    |> optional(left_qualifier(tag))
    |> ignore(string(indicator))
  end

  # Seconds-only variants that keep a fractional second as a *sibling*
  # `{:fraction, {digits, count}}` token rather than folding it into a
  # float (as `positive_number`/`maybe_negative_number` would). The
  # second has no finer integer unit to absorb the fraction, so
  # `Tempo.Validation.resolve/2` lifts the sibling fraction into a
  # `:microsecond {value, precision}` component, preserving the digit
  # count (and therefore the resolution / interval width). Folding to a
  # float would discard significant trailing zeros (`.120` vs `.12`).
  def implicit_second_or_integer_set(opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      positive_integer(opts)
    ])
    |> unwrap_and_tag(:second)
    |> optional(fraction())
  end

  def explicit_second_or_integer_set(indicator, opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_one}),
      maybe_negative_integer(opts)
    ])
    |> unwrap_and_tag(:second)
    |> optional(fraction())
    |> ignore(string(indicator))
  end

  def positive_integer_or_integer_set(tag, opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      positive_integer(opts)
    ])
    |> unwrap_and_tag(tag)
  end

  def positive_integer_or_integer_set(indicator, tag, opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_one}),
      positive_integer(opts)
    ])
    |> ignore(string(indicator))
    |> unwrap_and_tag(tag)
  end

  def maybe_negative_integer_or_integer_set(indicator, tag, opts) do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_one}),
      maybe_negative_integer(opts)
    ])
    |> ignore(string(indicator))
    |> unwrap_and_tag(tag)
  end

  def exponent do
    ignore(string("E"))
    |> integer(min: 1)
    |> unwrap_and_tag(:exponent)
  end

  def significant do
    ignore(string("S"))
    |> integer(min: 1)
    |> unwrap_and_tag(:significant)
  end

  def fraction do
    ignore(decimal_separator())
    |> times(ascii_char([?0..?9]), min: 1)
    |> lookahead_not(number_separator())
    |> reduce(:reduce_fraction)
    |> unwrap_and_tag(:fraction)
  end

  # Capture both the fractional digits as an integer and the count of
  # digits as written. The digit count (not the integer) determines
  # precision, because leading zeros are significant: `.0123` and
  # `.123` differ in resolution even though both reduce to 123.
  def reduce_fraction(digit_chars) do
    {List.to_integer(digit_chars), length(digit_chars)}
  end

  def number_separator do
    choice([
      dash(),
      decimal_separator(),
      ascii_char([?], ?}])
    ])
  end

  def error_range do
    ignore(string("±"))
    |> integer(min: 1)
    |> optional(exponent())
    |> reduce(:form_number)
    |> unwrap_and_tag(:margin_of_error)
  end

  def digit_or_unspecified do
    choice([
      digit(),
      unspecified(),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all})
    ])
  end

  def unspecified_or_set do
    choice([
      unspecified(),
      ascii_char([?{])
    ])
  end

  # Reduction for a duration second: sign, integer, and optional
  # fraction arrive together so `-0.2` keeps its sign (the integer
  # part alone cannot carry a `-0`). A fractional second reduces to a
  # `{:signed_fraction, sign, second, {digits, count}}` tuple that
  # `Tempo.Duration.build/1` lifts into sign-consistent `:second` +
  # `:microsecond` components; a whole second stays an integer.
  def form_duration_second([?-, integer, {:fraction, {digits, count}}])
      when is_integer(integer),
      do: {:signed_fraction, -1, integer, {digits, count}}

  def form_duration_second([integer, {:fraction, {digits, count}}])
      when is_integer(integer),
      do: {:signed_fraction, 1, integer, {digits, count}}

  def form_duration_second([?-, integer]) when is_integer(integer), do: -integer
  def form_duration_second([integer]) when is_integer(integer), do: integer

  def form_number([number]) when is_number(number) do
    number
  end

  def form_number([?-, integer, {:fraction, {fraction, digit_count}} | rest])
      when is_integer(integer) and is_integer(fraction) do
    number = integer + fraction / :math.pow(10, digit_count)
    form_number([-number | rest])
  end

  def form_number([?-, integer | rest]) when is_integer(integer) do
    form_number([-integer | rest])
  end

  # Leading `+` of an ISO 8601-2 expanded year: positive, so drop the
  # sign and keep the integer as-is.
  def form_number([?+, integer | rest]) when is_integer(integer) do
    form_number([integer | rest])
  end

  def form_number([?-, {integer, options} | rest]) when is_integer(integer) do
    form_number([{-integer, options} | rest])
  end

  # A negative year with unspecified digits (e.g. `-1XXX`, `-XXXX-XX`).
  # The mask list is tagged with a leading `:negative` sentinel so
  # downstream consumers (`Tempo.Mask.fill_unspecified/4`,
  # `Tempo.Mask.matches_mask?/2`, enumeration, inspect) can treat
  # the mask as bounded below zero.
  def form_number([?-, {:mask, list} | rest]) do
    form_number([{:mask, [:negative | list]} | rest])
  end

  def form_number([integer, {:fraction, {fraction, digit_count}} | rest])
      when is_integer(integer) and is_integer(fraction) do
    number = integer + fraction / :math.pow(10, digit_count)
    form_number([number | rest])
  end

  def form_number([integer, {:exponent, exponent} | rest]) do
    form_number([(integer * :math.pow(10, exponent)) |> trunc | rest])
  end

  def form_number([integer, {:significant, significant}]) do
    {integer, significant_digits: significant}
  end

  def form_number([integer, {:margin_of_error, error}]) do
    {integer, margin_of_error: error}
  end

  def form_number([integer, {:significant, significant}, {:margin_of_error, error}]) do
    {integer, significant_digits: significant, margin_of_error: error}
  end

  def form_number([tuple]) when is_tuple(tuple) do
    tuple
  end

  def form_number(other) do
    other
  end

  # A fraction on the second is preserved as a `:microsecond`
  # `{value, precision}` component rather than collapsed into a float
  # second. The second has no finer integer unit to absorb the
  # fraction into, so sub-second resolution lives here. `precision`
  # comes from the digit count (leading zeros significant).
  def apply_fraction([{:second, value}, {:fraction, {fraction, digit_count}} | rest])
      when is_integer(value) do
    # The fraction extends the second's magnitude, so it inherits the
    # second's sign: `PT-1.5S` is −1.5 s, i.e. `[second: -1,
    # microsecond: {-500000, 1}]` — component signs stay consistent for
    # arithmetic. Clock seconds are never negative, so this only
    # affects durations.
    {micro_value, precision} = Microsecond.from_fraction(fraction, digit_count)
    microsecond = if value < 0, do: {-micro_value, precision}, else: {micro_value, precision}
    [{:second, value}, {:microsecond, microsecond} | apply_fraction(rest)]
  end

  def apply_fraction([{unit, value}, {:fraction, fraction} | rest]) do
    value = form_number([value, {:fraction, fraction}])
    [{unit, value} | apply_fraction(rest)]
  end

  def apply_fraction([first | rest]) do
    [first | apply_fraction(rest)]
  end

  def apply_fraction(other) do
    other
  end

  def normalize_mask([]) do
    []
  end

  def normalize_mask([{:all_of, list} | t]) do
    [list | normalize_mask(t)]
  end

  def normalize_mask([?X | t]) do
    [:X | normalize_mask(t)]
  end

  def normalize_mask([:"X*"]) do
    :"X*"
  end

  def normalize_mask([digit | t]) when digit in ?0..?9 do
    [digit - ?0 | normalize_mask(t)]
  end
end
