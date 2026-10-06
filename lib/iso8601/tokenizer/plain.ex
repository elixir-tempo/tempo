defmodule Tempo.Iso8601.Tokenizer.Plain do
  @moduledoc false

  # The plain forms of a date and a time of day, read by their bytes: a year
  # of four digits, a year and a month, a calendar date, and a calendar date
  # with a time of day to the hour, the minute, the second or a fraction of
  # one, alone or with `Z` or a shift of hours and minutes (RFC 3339's
  # timestamp, and ISO 8601-1's extended format).
  #
  # The general tokenizer tries an interval, then a duration, then each
  # form of a date before it reaches these, which cost it some four hundred
  # microseconds for `2026-06-15`, where the explicit form `2026Y6M15D`
  # took forty. These are the forms most values are written in, and a scan
  # of their bytes takes under a microsecond.
  #
  # The scan gives the tokens the general tokenizer gives, or `:general`
  # for anything it is not certain of, which the general tokenizer then
  # reads: any other form, and a plain form with a field out of its usual
  # range (a month 13, a second 60, a shift of twenty-four hours), which
  # the general tokenizer has its own answer for. It is held to that answer
  # for every text of these shapes by
  # `Tempo.Iso8601.Tokenizer.PlainTest`.

  defguardp is_digit(byte) when byte in ?0..?9

  defguardp are_digits(a, b) when is_digit(a) and is_digit(b)

  defguardp are_digits(a, b, c, d)
            when is_digit(a) and is_digit(b) and is_digit(c) and is_digit(d)

  @doc false
  @spec tokens(binary()) :: {:ok, keyword()} | :general
  def tokens(<<y1, y2, y3, y4>>) when are_digits(y1, y2, y3, y4),
    do: {:ok, [date: [year: year(y1, y2, y3, y4)]]}

  def tokens(<<y1, y2, y3, y4, ?-, m1, m2>>)
      when are_digits(y1, y2, y3, y4) and are_digits(m1, m2) do
    with {:ok, month} <- within(two(m1, m2), 1, 12) do
      {:ok, [date: [year: year(y1, y2, y3, y4), month: month]]}
    end
  end

  def tokens(<<y1, y2, y3, y4, ?-, m1, m2, ?-, d1, d2, rest::binary>>)
      when are_digits(y1, y2, y3, y4) and are_digits(m1, m2) and are_digits(d1, d2) do
    with {:ok, month} <- within(two(m1, m2), 1, 12),
         {:ok, day} <- within(two(d1, d2), 1, 31) do
      with_time_of_day([year: year(y1, y2, y3, y4), month: month, day: day], rest)
    end
  end

  def tokens(_another_form), do: :general

  defp with_time_of_day(date, ""), do: {:ok, [date: date]}

  defp with_time_of_day(date, <<?T, time::binary>>) do
    with {:ok, time_of_day} <- time_of_day(time) do
      {:ok, [datetime: date ++ time_of_day]}
    end
  end

  defp with_time_of_day(_date, _another_form), do: :general

  # A time of day to the hour, the minute or the second, a second with its
  # fraction, and a shift after a minute or a second.
  defp time_of_day(<<h1, h2>>) when are_digits(h1, h2) do
    with {:ok, hour} <- within(two(h1, h2), 0, 23), do: {:ok, [hour: hour]}
  end

  defp time_of_day(<<h1, h2, ?:, m1, m2, ?:, s1, s2, rest::binary>>)
       when are_digits(h1, h2) and are_digits(m1, m2) and are_digits(s1, s2) do
    with {:ok, hour} <- within(two(h1, h2), 0, 23),
         {:ok, minute} <- within(two(m1, m2), 0, 59),
         {:ok, second} <- within(two(s1, s2), 0, 59),
         {:ok, fraction, after_fraction} <- fraction(rest),
         {:ok, shift} <- shift(after_fraction) do
      {:ok, [hour: hour, minute: minute, second: second] ++ fraction ++ shift}
    end
  end

  defp time_of_day(<<h1, h2, ?:, m1, m2, rest::binary>>)
       when are_digits(h1, h2) and are_digits(m1, m2) do
    with {:ok, hour} <- within(two(h1, h2), 0, 23),
         {:ok, minute} <- within(two(m1, m2), 0, 59),
         {:ok, shift} <- shift(rest) do
      {:ok, [hour: hour, minute: minute] ++ shift}
    end
  end

  defp time_of_day(_another_form), do: :general

  # A fraction of a second of one to six digits, as a number and how many
  # digits it was written to.
  defp fraction(<<?., digit, rest::binary>>) when is_digit(digit),
    do: fraction(rest, digit - ?0, 1)

  defp fraction(<<?., _not_a_digit::binary>>), do: :general
  defp fraction(rest), do: {:ok, [], rest}

  defp fraction(<<digit, rest::binary>>, value, digits) when is_digit(digit) and digits < 6,
    do: fraction(rest, value * 10 + (digit - ?0), digits + 1)

  defp fraction(<<digit, _rest::binary>>, _value, _digits) when is_digit(digit), do: :general
  defp fraction(rest, value, digits), do: {:ok, [fraction: {value, digits}], rest}

  # No shift, `Z`, or hours and minutes east or west of it. A shift of no
  # hours west (`-00:30`) has no hour to hold its sign, and is the general
  # tokenizer's to read.
  defp shift(""), do: {:ok, []}
  defp shift("Z"), do: {:ok, [time_shift: [hour: 0]]}

  defp shift(<<sign, h1, h2, ?:, m1, m2>>)
       when sign in [?+, ?-] and are_digits(h1, h2) and are_digits(m1, m2) do
    with {:ok, hour} <- within(two(h1, h2), first_hour(sign), 23),
         {:ok, minute} <- within(two(m1, m2), 0, 59) do
      {:ok, [time_shift: [hour: signed(sign, hour), minute: minute]]}
    end
  end

  defp shift(_another_form), do: :general

  defp first_hour(?+), do: 0
  defp first_hour(?-), do: 1

  defp signed(?+, hour), do: hour
  defp signed(?-, hour), do: -hour

  defp within(value, first, last) when value >= first and value <= last, do: {:ok, value}
  defp within(_value, _first, _last), do: :general

  defp two(a, b), do: (a - ?0) * 10 + (b - ?0)

  defp year(y1, y2, y3, y4), do: two(y1, y2) * 100 + two(y3, y4)
end
