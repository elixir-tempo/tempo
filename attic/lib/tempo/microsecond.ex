defmodule Tempo.Microsecond do
  @moduledoc false

  # Conversions for Tempo's sub-second component.
  #
  # Tempo represents sub-second resolution with a `:microsecond` time
  # component carrying the same `{value, precision}` shape used by
  # Elixir's `Time`, `NaiveDateTime`, and `DateTime` structs:
  #
  # * `value` is an absolute microsecond count in the range `0..999_999`.
  #
  # * `precision` is the number of significant fractional digits, in the
  #   range `0..6`. It records the declared resolution and therefore the
  #   width of the implied interval — `{120_000, 2}` is the centisecond
  #   interval `[.12, .13)` whereas `{120_000, 3}` is the millisecond
  #   interval `[.120, .121)`.
  #
  # Because `value` is always normalised to microseconds, ordering two
  # sub-second parts is a direct integer comparison of their values;
  # `precision` plays no role in comparison, only in interval width and
  # formatting.
  #
  # The maximum precision is 6 (microsecond), matching Elixir. Fractional
  # input carrying more than 6 digits is truncated to microsecond
  # resolution.

  @max_precision 6
  @microseconds_per_second 1_000_000

  @typedoc """
  A sub-second component: `{microsecond_value, precision}` where
  `microsecond_value` is `0..999_999` and `precision` is `0..6`.
  """
  @type t :: Tempo.microsecond()

  @doc """
  Convert parsed fractional-second digits into a `{value, precision}`
  microsecond component.

  ### Arguments

  * `fraction_integer` is the fractional digits parsed as an integer
    (for example the digits after the decimal separator in `45.0123`
    parse to `123`).

  * `digit_count` is the number of fractional digits as written,
    including leading zeros (for `45.0123` it is `4`). The digit count,
    not the integer, determines precision — leading zeros are
    significant.

  ### Returns

  * A `t:t/0` tuple `{microsecond_value, precision}`. When `digit_count`
    exceeds 6, the value is truncated to microsecond resolution and
    `precision` is capped at 6.

  ### Examples

      iex> Tempo.Microsecond.from_fraction(123, 3)
      {123000, 3}

      iex> Tempo.Microsecond.from_fraction(123, 4)
      {12300, 4}

      iex> Tempo.Microsecond.from_fraction(123456, 6)
      {123456, 6}

      iex> Tempo.Microsecond.from_fraction(1234567, 7)
      {123456, 6}

  """
  @spec from_fraction(non_neg_integer(), non_neg_integer()) :: t()
  def from_fraction(fraction_integer, digit_count)
      when is_integer(fraction_integer) and fraction_integer >= 0 and
             is_integer(digit_count) and digit_count >= 0 do
    cond do
      digit_count == 0 ->
        {0, 0}

      digit_count <= @max_precision ->
        {fraction_integer * pow10(@max_precision - digit_count), digit_count}

      true ->
        # More than 6 digits: truncate to microsecond resolution.
        # Truncation (rather than rounding) avoids a second-carry at
        # the all-nines boundary and matches the common convention of
        # dropping excess sub-microsecond precision.
        {div(fraction_integer, pow10(digit_count - @max_precision)), @max_precision}
    end
  end

  @doc """
  Return `true` when `value` is a well-formed microsecond component.

  ### Arguments

  * `value` is any term.

  ### Returns

  * `true` if `value` is a `{microsecond_value, precision}` tuple with
    `microsecond_value` in `0..999_999` and `precision` in `0..6`;
    `false` otherwise.

  ### Examples

      iex> Tempo.Microsecond.valid?({123000, 3})
      true

      iex> Tempo.Microsecond.valid?({1_000_000, 6})
      false

      iex> Tempo.Microsecond.valid?({100, 7})
      false

  """
  @spec valid?(term()) :: boolean()
  def valid?({value, precision})
      when is_integer(value) and value >= 0 and value < @microseconds_per_second and
             is_integer(precision) and precision >= 0 and precision <= @max_precision do
    true
  end

  def valid?(_other) do
    false
  end

  @doc """
  Render a microsecond component as its fractional-digit string,
  zero-padded to `precision` digits (no leading decimal separator).

  ### Arguments

  * `microsecond` is a `t:t/0` tuple `{value, precision}`.

  ### Returns

  * A string of exactly `precision` digits, or the empty string when
    `precision` is `0`.

  ### Examples

      iex> Tempo.Microsecond.to_digits_string({123000, 3})
      "123"

      iex> Tempo.Microsecond.to_digits_string({120000, 3})
      "120"

      iex> Tempo.Microsecond.to_digits_string({123, 6})
      "000123"

      iex> Tempo.Microsecond.to_digits_string({0, 0})
      ""

  """
  @spec to_digits_string(t()) :: String.t()
  def to_digits_string({_value, 0}) do
    ""
  end

  def to_digits_string({value, precision})
      when is_integer(value) and is_integer(precision) and precision > 0 do
    value
    |> div(pow10(@max_precision - precision))
    |> Integer.to_string()
    |> String.pad_leading(precision, "0")
  end

  @compile {:inline, pow10: 1}
  defp pow10(0) do
    1
  end

  defp pow10(1) do
    10
  end

  defp pow10(2) do
    100
  end

  defp pow10(3) do
    1_000
  end

  defp pow10(4) do
    10_000
  end

  defp pow10(5) do
    100_000
  end

  defp pow10(6) do
    1_000_000
  end

  defp pow10(n) when n > 6 do
    1_000_000 * pow10(n - 6)
  end
end
