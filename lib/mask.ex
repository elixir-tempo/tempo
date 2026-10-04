defmodule Tempo.Mask do
  @moduledoc false

  alias Tempo.ConversionError
  alias Tempo.InvalidDateError
  alias Tempo.Iso8601.Unit
  alias Tempo.UnanchoredError
  alias Tempo.Validation

  @doc false
  # The values a masked unit takes when a value is walked, after the concrete
  # units before it. A mask counted from the end (`-X`, the last nine) is read
  # against what the unit holds there, so each candidate is the value it
  # names: the last nine months of a twelve-month year are 4 to 12.
  @spec candidates(atom(), list(), keyword(), module()) ::
          {:ok, [integer()]} | {:error, :unanchored | {:unmaskable, atom()}}
  # The years of a mask below zero (`-1XXX`) are walked from the earliest.
  def candidates(:year, [:negative | _digits] = mask, previous, calendar) do
    with {:ok, years} <- valid_values(:year, mask, previous, calendar) do
      {:ok, Enum.reverse(years)}
    end
  end

  def candidates(:year, mask, previous, calendar),
    do: valid_values(:year, mask, previous, calendar)

  def candidates(unit, [:negative | mask], previous, calendar) do
    with {:ok, %Range{last: last} = range} <- unspecified(unit, previous, calendar) do
      counts = Range.size(range)..1//-1
      {:ok, for(count <- counts, matches_mask?(count, mask), do: last + 1 - count)}
    end
  end

  def candidates(unit, mask, previous, calendar),
    do: valid_values(unit, mask, previous, calendar)

  @doc false
  # Every value an unspecified unit (`X*`) takes after the concrete units
  # before it. A unit whose extent depends on a year the value does not have
  # takes every value it has in some year (`2MX*D` is 1 to 29), where a count
  # from the end is kept as written until the value has a year
  # (`2M{1..-1}D`): the two differ, an open item in `TODO.md`.
  @spec unspecified(atom(), keyword(), module()) ::
          {:ok, Range.t()} | {:error, :unanchored | {:unmaskable, atom()}}
  def unspecified(unit, previous, calendar) do
    case valid_range(unit, previous, calendar) do
      {:ok, range} -> {:ok, range}
      {:ambiguous, %Range{first: first, last: last}} -> {:ok, 1..max(first, last)//1}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  # The exception for a mask that cannot be read, naming the value it is in.
  @spec error(Tempo.t(), :unanchored | {:no_candidates, atom()} | {:unmaskable, atom()}) ::
          Exception.t()
  def error(tempo, :unanchored), do: UnanchoredError.exception(value: tempo)

  def error(tempo, {:no_candidates, unit}) do
    InvalidDateError.exception(
      reason: "#{inspect(tempo)} names no date: no #{unit} matches its mask."
    )
  end

  def error(tempo, {:unmaskable, unit}) do
    ConversionError.exception(
      value: tempo,
      reason: "#{inspect(tempo)} masks its #{unit}, which has no range of values to narrow to."
    )
  end

  @doc """
  Return the list of valid values a mask can take at a given
  unit, constrained by the calendar and the preceding units.

  This is the single, exact, calendar-aware candidate resolver.
  Both the materialisation path (non-contiguous mask expansion in
  `Tempo.to_interval/2`) and the enumeration path
  (`candidates/4`, which delegates here) route through it, so
  the two cannot diverge. For `:month` with no leading constraint,
  the result is `1..months_in_year(year)` filtered by the
  zero-padded digit pattern.

  ### Arguments

  * `unit` is one of `:year`, `:month`, `:week`, `:day`,
    `:day_of_year`, `:day_of_week`, `:hour`, `:minute`, `:second`.

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

  * `{:error, :unanchored}` when the range depends on a
    coarser unit that `previous` does not supply — a month range
    in a calendar whose month count varies by year, a day range
    with no month and no year, or a week with no year.

  * `{:error, {:unmaskable, unit}}` for any other unit, which has
    no range of values to narrow to.

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
        ) :: {:ok, [integer()]} | {:error, :unanchored | {:unmaskable, atom()}}
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
      {:ambiguous, lengths} -> candidates_in_every_length(mask, width, lengths)
      {:error, _reason} = error -> error
    end
  end

  # A range whose length depends on the missing year — February's 28 or 29
  # days, a Hebrew year's 12 or 13 months. The candidates are known when every
  # one fits the shortest length (`1X` days are 10 to 19 in any February).
  defp candidates_in_every_length(mask, width, shortest..longest//_step) do
    candidates = Enum.filter(1..longest, &padded_matches_mask?(&1, mask, width))

    if Enum.all?(candidates, &(&1 <= shortest)),
      do: {:ok, candidates},
      else: {:error, :unanchored}
  end

  # A yearless value (`XX-15`, "the 15th of any month") has no year to
  # ask the calendar about, and `Keyword.fetch!/2` raised a bare
  # `KeyError` from four frames down. The calendars answer the
  # unanchored question too: Gregorian always has 12 months, so the
  # candidates are exact, while Hebrew reports `{:ambiguous, 12..13}`
  # because a leap year adds one — there the answer really does depend
  # on the missing year, and `:unanchored` says so.
  defp valid_range(:month, previous, calendar) do
    case unit_value(previous, :year) do
      year when is_integer(year) -> {:ok, 1..calendar.months_in_year(year)}
      _no_concrete_year -> unanchored_range(calendar.months_in_year())
    end
  end

  # A day follows its month. With a year and no month it counts through the
  # year, as `Tempo.Validation` reads a day written straight after a year.
  defp valid_range(:day, previous, calendar) do
    year = unit_value(previous, :year)
    month = unit_value(previous, :month)

    cond do
      is_integer(year) and counted?(month) -> {:ok, 1..calendar.days_in_month(year, month)}
      counted?(month) -> unanchored_range(calendar.days_in_month(month))
      is_integer(year) and is_nil(month) -> {:ok, 1..calendar.days_in_year(year)}
      true -> {:error, :unanchored}
    end
  end

  defp valid_range(:day_of_year, previous, calendar) do
    case unit_value(previous, :year) do
      year when is_integer(year) -> {:ok, 1..calendar.days_in_year(year)}
      _no_concrete_year -> {:error, :unanchored}
    end
  end

  defp valid_range(:week, previous, calendar) do
    case unit_value(previous, :year) do
      year when is_integer(year) -> {:ok, 1..Validation.iso_weeks_in_year(year, calendar)}
      _no_concrete_year -> {:error, :unanchored}
    end
  end

  # The day of the week and the clock units have the same extent wherever they
  # are, which `Tempo.Iso8601.Unit.value_range/2` gives.
  defp valid_range(unit, _previous, calendar) do
    case Unit.value_range(unit, calendar) do
      {:ok, range} -> {:ok, range}
      :unknown -> {:error, {:unmaskable, unit}}
    end
  end

  # The units before a mask are not always a keyword list: a group of a set
  # (`{1,2}G3MU`) is a three-element entry, which `Keyword.get/2` raises on.
  # It is no one number, and so no unit to count a range in.
  defp unit_value(previous, unit) do
    case List.keyfind(previous, unit, 0) do
      {^unit, value} -> value
      nil -> nil
      _group_of_a_set -> :several
    end
  end

  # A month counted from the first, rather than one still counting from the
  # end of a year the value does not have.
  defp counted?(month), do: is_integer(month) and month > 0

  defp unanchored_range(count) when is_integer(count), do: {:ok, 1..count}
  defp unanchored_range({:ambiguous, %Range{} = lengths}), do: {:ambiguous, lengths}
  defp unanchored_range(_undefined), do: {:error, :unanchored}

  # Pad candidate to the mask's width with leading zeros, then
  # compare digit-by-digit: `:X` matches any digit, a digit set
  # (`{0,2,4,6,8}`) any of its digits; any other element must match
  # exactly.
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

  defp digits_match?([digit | rest_d], [digit_set | rest_m]) when is_list(digit_set) do
    digit in set_digits(digit_set) and digits_match?(rest_d, rest_m)
  end

  defp digits_match?(_, _), do: false

  @doc """
  Return the `{min, max}` numeric range spanned by a digit mask.

  Each `:X` position contributes `0..9` at its digit weight, a digit
  set (`{0,2,4,6,8}`) its smallest to largest digit, and each concrete
  digit itself. Used by `fill_unspecified/4` to bound the candidate
  enumeration, and by `Tempo.to_interval/1` to compute the enclosing
  span of a masked value.

  ### Examples

      iex> Tempo.Mask.mask_bounds([1, 5, 6, :X])
      {1560, 1569}

      iex> Tempo.Mask.mask_bounds([:X, :X, :X, :X])
      {0, 9999}

      iex> Tempo.Mask.mask_bounds([:X, :X, :X, [0, 2, 4, 6, 8]])
      {0, 9998}

  """
  def mask_bounds(mask) when is_list(mask) do
    {min_digits, max_digits} =
      Enum.reduce(mask, {[], []}, fn
        :X, {lo, hi} -> {[0 | lo], [9 | hi]}
        d, {lo, hi} when is_integer(d) -> {[d | lo], [d | hi]}
        digit_set, {lo, hi} when is_list(digit_set) -> set_bounds(digit_set, lo, hi)
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
  # `:X` is a wildcard, a digit set matches any of its digits, and any
  # other element (an integer digit) must match the candidate's digit
  # exactly. Mirrors the `digits_match?/2` helper used by
  # `padded_matches_mask?/3` above.
  defp digits_equal_or_wildcard?([], []), do: true

  defp digits_equal_or_wildcard?([_digit | rest_d], [:X | rest_m]) do
    digits_equal_or_wildcard?(rest_d, rest_m)
  end

  defp digits_equal_or_wildcard?([digit | rest_d], [digit | rest_m]) when is_integer(digit) do
    digits_equal_or_wildcard?(rest_d, rest_m)
  end

  defp digits_equal_or_wildcard?([digit | rest_d], [digit_set | rest_m])
       when is_list(digit_set) do
    digit in set_digits(digit_set) and digits_equal_or_wildcard?(rest_d, rest_m)
  end

  defp digits_equal_or_wildcard?(_, _), do: false

  # The digits a digit set allows: `{0,2,4,6,8}` parses to `[0, 2, 4, 6, 8]`
  # and `{2..3}` to `[2..3]`.
  defp set_digits(digit_set) do
    Enum.flat_map(digit_set, fn
      %Range{} = range -> Enum.to_list(range)
      digit -> [digit]
    end)
  end

  defp set_bounds(digit_set, lo, hi) do
    {min, max} = digit_set |> set_digits() |> Enum.min_max()
    {[min | lo], [max | hi]}
  end
end
