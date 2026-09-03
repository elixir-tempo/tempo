defmodule Tempo.Mask do
  @moduledoc false

  import Tempo.Enumeration, only: [adjusted_range: 4, backtrack: 2, current_units: 1]

  # Fill in the mask when enumerating. The unspecified digits are filled
  # with the known candidate values and then expanded. For `year: :any` we
  # use the current year.

  def fill_unspecified(:year, :any, _calendar, _previous) do
    Date.utc_today()
    |> Map.fetch!(:year)
    |> List.wrap()
  end

  def fill_unspecified(unit, :any, calendar, previous)
      when unit in [:month, :day, :hour, :minute, :second] do
    # The list wrapping is load-bearing: `adjusted_range/4` routes
    # through `Validation.resolve/2`, whose clause matching the
    # `year+month` or `year+month+day` shapes guards on
    # `is_list(value) or is_integer(value)`. Passing the range
    # wrapped in a list lets that clause conform `1..-1//1` to
    # the concrete `1..months_in_year`/`1..days_in_month` range.
    [1..-1//1]
    |> adjusted_range(unit, calendar, backtrack(previous, calendar))
    |> List.wrap()
  end

  # Year masks are bounded entirely by their digit pattern (no calendar
  # context narrows them), so they defer to `valid_values/4` — the single
  # resolver — just like the month/day path below. `valid_values/4` ignores
  # `previous`/`calendar` for years.
  # A year mask never depends on a coarser unit, so `valid_values/4`
  # cannot report a missing anchor here — unwrap it.
  def fill_unspecified(:year, [:negative | _] = mask, calendar, previous) do
    {:ok, values} = valid_values(:year, mask, previous, calendar)
    values
  end

  def fill_unspecified(:year, mask, calendar, previous) when is_list(mask) do
    {:ok, values} = valid_values(:year, mask, previous, calendar)
    values
  end

  # Month and day masks still need calendar context (month-of-year
  # bounds, days-in-month), so they route through `:any` which
  # returns a calendar-adjusted range.
  def fill_unspecified(unit, [:negative | rest_mask], calendar, previous)
      when unit in [:month, :day] do
    [target_range] = fill_unspecified(unit, :any, calendar, previous)
    digit_count = length(rest_mask)
    min = -(integer_pow10(digit_count) - 1)
    max = -integer_pow10(digit_count - 1)

    Enum.reduce(target_range, [], fn candidate, acc ->
      neg = -candidate

      if neg in max..min//-1 and matches_mask?(abs(neg), rest_mask) do
        [neg | acc]
      else
        acc
      end
    end)
  end

  def fill_unspecified(unit, mask, calendar, previous) when unit in [:month, :day] do
    # Unified candidate generation: derive the concrete coarser units from
    # the enumeration state (advance them via `backtrack/2`, then take each
    # unit's current value) and defer to `valid_values/4` — the single,
    # exact, calendar-aware resolver. This is the same range + zero-padded
    # match the old inline `adjusted_range`/`padded_matches_mask?` computed,
    # now shared with the materialisation path so the two cannot diverge.
    concrete = previous |> backtrack(calendar) |> current_units() |> Enum.reverse()

    case valid_values(unit, mask, concrete, calendar) do
      {:ok, values} ->
        values

      # `Enumerable.reduce/3` has no error channel — its contract admits
      # only `{:done, acc}`, `{:halted, acc}` and `{:suspended, …}` — so a
      # value that cannot be enumerated has to signal by raising. This is
      # a documented exception with a message, not a bare `throw`: callers
      # can match on it, and it names the anchor the value is missing.
      {:error, :requires_anchor} ->
        raise Tempo.RequiresAnchorError,
          value: Enum.reverse(concrete),
          reason: :mask_requires_anchor
    end
  end

  @doc """
  Return the list of valid values a mask can take at a given
  unit, constrained by the calendar and the preceding units.

  This is the single, exact, calendar-aware candidate resolver.
  Both the materialisation path (non-contiguous mask expansion in
  `Tempo.to_interval/2`) and the enumeration path
  (`fill_unspecified/4`, which delegates here) route through it, so
  the two cannot diverge. For `:month` with no leading constraint,
  the result is `1..months_in_year(year)` filtered by the
  zero-padded digit pattern.

  ### Arguments

  * `unit` is one of `:year`, `:month`, `:day`, `:hour`,
    `:minute`, `:second`.

  * `mask` is the digit-pattern list (e.g. `[:X, :X]` or
    `[:X, 5]`).

  * `previous` is a keyword list of already-resolved units
    coarser than `unit` (e.g. `[year: 1985]` when matching
    `:month`).

  * `calendar` is the calendar module used to derive valid
    ranges (`months_in_year`, `days_in_month`, etc.).

  ### Returns

  * `{:ok, values}` — a sorted list of integers that are (a) in
    the valid range for the unit given `previous`, and (b) match
    the mask pattern when formatted to the mask's width with
    zero-padding.

  * `{:error, :requires_anchor}` when the range depends on a
    coarser unit that `previous` does not supply — a month range
    in a calendar whose month count varies by year, or a day range
    with no month.

  ### Examples

      iex> Tempo.Mask.valid_values(:month, [:X, :X], [year: 1985], Calendrical.Gregorian)
      {:ok, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]}

      iex> Tempo.Mask.valid_values(:month, [:X, 5], [year: 1985], Calendrical.Gregorian)
      {:ok, [5]}

      iex> Tempo.Mask.valid_values(:day, [:X, :X], [year: 1985, month: 2], Calendrical.Gregorian)
      {:ok, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28]}

  """
  @spec valid_values(
          unit :: atom(),
          mask :: list(),
          previous :: keyword(),
          calendar :: module()
        ) :: {:ok, [integer()]} | {:error, :requires_anchor}
  # Year masks are digit-bounded — there is no calendar range for years —
  # so their candidates come straight from the digit pattern.
  def valid_values(:year, [:negative | rest], _previous, _calendar) do
    {min, max} = mask_bounds(rest)
    {:ok, for(candidate <- min..max, matches_mask?(candidate, rest), do: -candidate)}
  end

  def valid_values(:year, mask, _previous, _calendar) do
    {min, max} = mask_bounds(mask)
    {:ok, Enum.filter(min..max, &matches_mask?(&1, mask))}
  end

  def valid_values(unit, mask, previous, calendar) do
    width = length(mask)

    case valid_range(unit, previous, calendar) do
      {:ok, range} -> {:ok, Enum.filter(range, &padded_matches_mask?(&1, mask, width))}
      {:error, _reason} = error -> error
    end
  end

  # A yearless value (`XX-15`, "the 15th of any month") has no year to
  # ask the calendar about, and `Keyword.fetch!/2` raised a bare
  # `KeyError` from four frames down. The calendars answer the
  # un-anchored question too: Gregorian always has 12 months, so the
  # candidates are exact, while Hebrew reports `{:ambiguous, 12..13}`
  # because a leap year adds one — there the answer really does depend
  # on the missing year, and `:requires_anchor` says so.
  defp valid_range(:month, previous, calendar) do
    case Keyword.get(previous, :year) do
      year when is_integer(year) -> {:ok, 1..calendar.months_in_year(year)}
      _no_concrete_year -> unanchored_range(calendar.months_in_year())
    end
  end

  defp valid_range(:day, previous, calendar) do
    year = Keyword.get(previous, :year)
    month = Keyword.get(previous, :month)

    cond do
      is_integer(year) and is_integer(month) -> {:ok, 1..calendar.days_in_month(year, month)}
      is_integer(month) -> unanchored_range(calendar.days_in_month(month))
      true -> {:error, :requires_anchor}
    end
  end

  defp valid_range(:hour, _previous, _calendar), do: {:ok, 0..23}
  defp valid_range(:minute, _previous, _calendar), do: {:ok, 0..59}
  defp valid_range(:second, _previous, _calendar), do: {:ok, 0..59}

  defp unanchored_range(count) when is_integer(count), do: {:ok, 1..count}
  defp unanchored_range(_ambiguous_or_undefined), do: {:error, :requires_anchor}

  # Pad candidate to the mask's width with leading zeros, then
  # compare digit-by-digit: `:X` matches any digit; any other
  # element must match exactly.
  defp padded_matches_mask?(candidate, mask, width) do
    padded =
      candidate
      |> Integer.to_string()
      |> String.pad_leading(width, "0")

    digits =
      padded
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)

    length(digits) == width and digits_match?(digits, mask)
  end

  defp digits_match?([], []), do: true

  defp digits_match?([_digit | rest_d], [:X | rest_m]) do
    digits_match?(rest_d, rest_m)
  end

  defp digits_match?([digit | rest_d], [digit | rest_m]) when is_integer(digit) do
    digits_match?(rest_d, rest_m)
  end

  defp digits_match?(_, _), do: false

  @doc """
  Return the `{min, max}` numeric range spanned by a digit mask.

  Each `:X` position contributes `0..9` at its digit weight; each
  concrete digit contributes itself. Used by `fill_unspecified/4`
  to bound the candidate enumeration, and by `Tempo.to_interval/1`
  to compute the enclosing span of a masked value.

  ### Examples

      iex> Tempo.Mask.mask_bounds([1, 5, 6, :X])
      {1560, 1569}

      iex> Tempo.Mask.mask_bounds([:X, :X, :X, :X])
      {0, 9999}

  """
  def mask_bounds(mask) when is_list(mask) do
    {min_digits, max_digits} =
      Enum.reduce(mask, {[], []}, fn
        :X, {lo, hi} -> {[0 | lo], [9 | hi]}
        d, {lo, hi} when is_integer(d) -> {[d | lo], [d | hi]}
      end)

    {Integer.undigits(Enum.reverse(min_digits)), Integer.undigits(Enum.reverse(max_digits))}
  end

  def matches_mask?(candidate, [:negative | rest_mask]) when candidate < 0 do
    matches_mask?(abs(candidate), rest_mask)
  end

  def matches_mask?(_candidate, [:negative | _rest_mask]), do: false

  # Years carry no leading zeros — a 2-digit `XX` year mask means 10..99,
  # `XXXX` means 1000..9999 — so the candidate's digit count must equal
  # the mask width exactly. (Months and days *are* zero-padded, but those
  # go through `padded_matches_mask?/3`.)
  def matches_mask?(candidate, mask) do
    digits = Integer.digits(candidate)
    length(digits) == length(mask) and digits_equal_or_wildcard?(digits, mask)
  end

  # Per-position match between candidate digits and mask elements.
  # `:X` is a wildcard; any other element (an integer digit) must
  # match the candidate's digit exactly. Mirrors the `digits_match?/2`
  # helper used by `padded_matches_mask?/3` above.
  defp digits_equal_or_wildcard?([], []), do: true

  defp digits_equal_or_wildcard?([_digit | rest_d], [:X | rest_m]) do
    digits_equal_or_wildcard?(rest_d, rest_m)
  end

  defp digits_equal_or_wildcard?([digit | rest_d], [digit | rest_m]) when is_integer(digit) do
    digits_equal_or_wildcard?(rest_d, rest_m)
  end

  defp digits_equal_or_wildcard?(_, _), do: false

  defp integer_pow10(0), do: 1
  defp integer_pow10(n) when n > 0, do: 10 * integer_pow10(n - 1)
end
