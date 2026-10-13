defmodule Tempo.Sigils do
  @moduledoc """
  The `~o` sigil: an ISO 8601 text read at compile time.

  In an expression, `~o"2026-06-15"` is the `%Tempo{}` the text names, read
  once when the module compiles, so a text that cannot be read is a compile
  error. A duration text is a `%Tempo.Duration{}`.

  In a pattern, the sigil is a structural match on the form the text names.
  A value matches every value whose units *begin with* the units written,
  so `~o"2026-06"` matches `~o"2026-06-15"` and `~o"2026-06-15T10"`, and no
  other field is constrained: a Gregorian-looking sigil matches a value of
  another calendar. An interval, a set or a recurrence matches that form
  exactly.

      iex> import Tempo.Sigils
      iex> match?(~o"2026-06", ~o"2026-06-15")
      true
      iex> match?(~o"2026-06", ~o"2026-07-15")
      false

  """

  @doc """
  Reads an ISO 8601 text into an expression at compile time, or into a
  pattern that matches one.

  ### Examples

      iex> ~o"2026-06-15"
      Tempo.from_iso8601!("2026-06-15")

      iex> ~o"P1Y2M"
      Tempo.Duration.new!(year: 1, month: 2)

  """
  defmacro sigil_o({:<<>>, _meta, [text]}, modifiers) when is_binary(text) do
    if modifiers != [] do
      raise ArgumentError,
            "~o takes no modifiers; #{inspect(List.to_string(modifiers))} was given on #{inspect(text)}"
    end

    expression = Tempo.from_iso8601!(text)

    case __CALLER__.context do
      nil -> Macro.escape(expression)
      _match_or_guard -> pattern(expression)
    end
  end

  defmacro sigil_o(_sigil, _modifiers) do
    raise ArgumentError, "~o takes a literal text with no interpolation"
  end

  defp pattern(%Tempo{form: {:value, units}}) do
    quote do
      %Tempo{form: {:value, unquote(prefix(units))}}
    end
  end

  defp pattern(%Tempo{form: form}) do
    quote do
      %Tempo{form: unquote(Macro.escape(form))}
    end
  end

  defp pattern(%Tempo.Duration{units: units}) do
    quote do
      %Tempo.Duration{units: unquote(prefix(units))}
    end
  end

  # The written units, then anything: `[year: 2026, month: 6 | _]`.
  defp prefix(units) do
    units
    |> Enum.reverse()
    |> Enum.reduce(quote(do: _), fn unit, tail ->
      quote do
        [unquote(Macro.escape(unit)) | unquote(tail)]
      end
    end)
  end
end
