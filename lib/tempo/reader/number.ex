defmodule Tempo.Reader.Number do
  @moduledoc false

  # The numbers of the grammar (guides/iso8601-grammar.md, section 1 and 3.2
  # to 3.4): a whole number, a signed one, digits with some unspecified
  # (`19X`), a wholly unspecified value (`X*`), a number with an exponent,
  # significant digits or a margin of error (`17E7`, `1950S2`, `2018±2`), and
  # a set or a range of them in braces or brackets (`{1,3..5//2}`).
  #
  # Each reader takes the text and returns `{:ok, held, rest}` or `:error`,
  # where `held` is the `t:Tempo.Unit.held/0` the number stands for. Nothing
  # here knows what unit the number is for.

  @type result :: {:ok, Tempo.Unit.held(), String.t()} | :error

  @doc "One or more digits, as an integer."
  @spec digits(String.t()) :: {:ok, non_neg_integer(), String.t()} | :error
  def digits(text) do
    case Integer.parse(text) do
      {integer, rest}
      when integer >= 0 and binary_part(text, 0, 1) != "-" and binary_part(text, 0, 1) != "+" ->
        {:ok, integer, rest}

      _ ->
        :error
    end
  end

  @doc "Exactly `count` digits, as an integer."
  @spec fixed_digits(String.t(), pos_integer()) :: {:ok, non_neg_integer(), String.t()} | :error
  def fixed_digits(text, count) do
    case text do
      <<digits::binary-size(^count), rest::binary>> ->
        if digits?(digits), do: {:ok, String.to_integer(digits), rest}, else: :error

      _ ->
        :error
    end
  end

  @doc "Exactly `count` digits of which some may be `X`: an integer, or a mask."
  @spec fixed_masked(String.t(), pos_integer()) :: result()
  def fixed_masked(text, count) do
    case text do
      <<digits::binary-size(^count), rest::binary>> ->
        if masked_digits?(digits), do: {:ok, mask_or_integer(digits), rest}, else: :error

      _ ->
        :error
    end
  end

  @doc """
  A value as the explicit form holds one: a whole number, signed; digits with
  some unspecified; `X*`; a number with an exponent, significant digits or a
  margin; or a set or range of whole numbers. `negative?` says whether a
  leading `-` is read (a count from the end, a year before zero).
  """
  @spec value(String.t(), keyword()) :: result()
  def value(text, options \\ [])
  def value(<<"X*", rest::binary>>, _options), do: {:ok, :any, rest}
  def value(<<"{", _::binary>> = text, _options), do: set(text)

  def value(text, options) do
    with {:ok, run, rest} <- masked_run(text) do
      held(mask_or_integer(run), rest, Keyword.get(options, :annotations, false))
    end
  end

  defp held(integer, rest, true) when is_integer(integer), do: annotated(integer, rest)
  defp held(held, rest, _annotations?), do: {:ok, held, rest}

  # A run of digits and `X`s, with a leading `-`.
  defp masked_run(<<"-", rest::binary>>) do
    with {:ok, run, rest} <- masked_run(rest), do: {:ok, "-" <> run, rest}
  end

  defp masked_run(text) do
    {run, rest} = split_while(text, fn char -> char in ?0..?9 or char == ?X end)
    if run == "", do: :error, else: {:ok, run, rest}
  end

  @doc "`E`, `S` and `±` after a whole number: `271828E5S6`, `2018±2`."
  @spec annotated(integer(), String.t()) :: {:ok, Tempo.Unit.held(), String.t()}
  def annotated(integer, rest) do
    with {:ok, exponent, rest} <- optional(rest, "E"),
         {:ok, significant, rest} <- optional(rest, "S"),
         {:ok, margin, rest} <- optional(rest, "±") do
      annotations =
        [exponent: exponent, significant: significant, margin: margin]
        |> Enum.reject(fn {_, value} -> is_nil(value) end)

      case annotations do
        [] -> {:ok, integer, rest}
        _ -> {:ok, {integer, annotations}, rest}
      end
    end
  end

  # A significant-digits `S` is read only when digits follow it, so that the
  # `S` of a second is left for the designator.
  defp optional(text, marker) do
    size = byte_size(marker)

    case text do
      <<^marker::binary-size(^size), rest::binary>> ->
        case digits(rest) do
          {:ok, number, rest} -> {:ok, number, rest}
          :error -> {:ok, nil, text}
        end

      _ ->
        {:ok, nil, text}
    end
  end

  # A set of whole numbers and ranges in braces: `{1,3..5,7..-1//2}`.
  defp set(<<"{", rest::binary>>) do
    case members(rest, []) do
      {:ok, members, <<"}", rest::binary>>} -> {:ok, members, rest}
      _ -> :error
    end
  end

  defp members(text, acc) do
    with {:ok, member, rest} <- member(text) do
      case rest do
        <<",", rest::binary>> -> members(rest, [member | acc])
        _ -> {:ok, Enum.reverse([member | acc]), rest}
      end
    end
  end

  defp member(text) do
    with {:ok, first, rest} <- signed(text) do
      range(first, rest)
    end
  end

  defp range(first, <<"..", rest::binary>>) do
    with {:ok, last, rest} <- signed(rest),
         {:ok, step, rest} <- step(rest) do
      {:ok, Range.new(first, last, step), rest}
    end
  end

  defp range(first, rest), do: {:ok, first, rest}

  defp step(<<"//", rest::binary>>), do: digits(rest)
  defp step(rest), do: {:ok, 1, rest}

  @doc "A whole number with an optional leading `-`."
  @spec signed(String.t()) :: {:ok, integer(), String.t()} | :error
  def signed(<<"-", rest::binary>>) do
    with {:ok, integer, rest} <- digits(rest), do: {:ok, -integer, rest}
  end

  def signed(text), do: digits(text)

  @doc "A decimal fraction after a decimal sign: `.5` is `{500_000, 1}`."
  @spec fraction(String.t()) :: {:ok, {non_neg_integer(), 1..6}, String.t()} | :error
  def fraction(<<sign, rest::binary>>) when sign in [?., ?,] do
    {run, rest} = split_while(rest, fn char -> char in ?0..?9 end)

    case byte_size(run) do
      0 ->
        :error

      precision when precision <= 6 ->
        {:ok, {String.to_integer(run) * Integer.pow(10, 6 - precision), precision}, rest}

      _ ->
        {:ok, {run |> binary_part(0, 6) |> String.to_integer(), 6}, rest}
    end
  end

  def fraction(_text), do: :error

  @doc "Whether a text is digits alone."
  @spec digits?(String.t()) :: boolean()
  def digits?(text), do: text != "" and String.match?(text, ~r/\A[0-9]+\z/)

  defp masked_digits?(text), do: text != "" and String.match?(text, ~r/\A[0-9X]+\z/)

  # Digits alone are a number; with an `X` among them, a mask of digits with
  # `:x` for each; a leading `-` is kept as `:negative`.
  defp mask_or_integer("-" <> run) do
    case mask_or_integer(run) do
      integer when is_integer(integer) -> -integer
      {:mask, digits} -> {:mask, [:negative | digits]}
    end
  end

  defp mask_or_integer(run) do
    if String.contains?(run, "X") do
      {:mask,
       run
       |> String.graphemes()
       |> Enum.map(fn
         "X" -> :x
         digit -> String.to_integer(digit)
       end)}
    else
      String.to_integer(run)
    end
  end

  @doc "Splits a text at the first character the function refuses."
  @spec split_while(String.t(), (char() -> boolean())) :: {String.t(), String.t()}
  def split_while(text, keep?) do
    size = count_while(text, keep?, 0)
    <<taken::binary-size(^size), rest::binary>> = text
    {taken, rest}
  end

  defp count_while(<<char, rest::binary>>, keep?, count) do
    if keep?.(char), do: count_while(rest, keep?, count + 1), else: count
  end

  defp count_while(<<>>, _keep?, count), do: count
end
