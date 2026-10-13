defmodule Tempo.Reader.Suffix do
  @moduledoc false

  # The IXDTF suffix of RFC 9557 §4.1 (guides/iso8601-grammar.md, section 4):
  # at most one time zone, a name or a numeric offset, then tags of
  # `key=value-value`, each in brackets, a `!` after the bracket marking it
  # critical. The suffix is written once, after the whole expression, so it
  # is split off the end of the text before anything else is read.

  alias Tempo.Reader.Number
  alias Tempo.Zone

  @type suffix :: %{
          zone: Tempo.Zone.t() | nil,
          calendar: atom() | nil,
          tags: %{optional(String.t()) => [String.t()]}
        }

  @doc "Splits a text into its body and its suffix."
  @spec split(String.t()) :: {:ok, String.t(), suffix()} | {:error, term()}
  def split(text) do
    with {:ok, body, brackets} <- brackets(text, []),
         {:ok, suffix} <- interpret(brackets) do
      {:ok, body, suffix}
    end
  end

  # Trailing bracketed groups, innermost last; a group that is not a suffix
  # (a one-of set) is left on the body.
  defp brackets(text, acc) do
    case last_bracket(text) do
      {body, content} ->
        if suffix?(content), do: brackets(body, [content | acc]), else: {:ok, text, acc}

      :none ->
        {:ok, text, acc}
    end
  end

  defp last_bracket(text) do
    if String.ends_with?(text, "]") and String.contains?(text, "[") do
      {start, _} = text |> :binary.matches("[") |> List.last()
      {binary_part(text, 0, start), binary_part(text, start + 1, byte_size(text) - start - 2)}
    else
      :none
    end
  end

  # A suffix is a zone name, an offset, or a key=values; a set's members are none of these.
  defp suffix?(""), do: false

  defp suffix?(content) do
    content = String.trim_leading(content, "!")
    zone_name?(content) or offset?(content) or tag?(content)
  end

  defp zone_name?(content),
    do:
      String.match?(content, ~r/\A[A-Za-z._][A-Za-z0-9._+-]*(\/[A-Za-z._][A-Za-z0-9._+-]*)*\z/) and
        not String.contains?(content, "=")

  defp offset?(content), do: String.match?(content, ~r/\A[+-][0-9]{2}:[0-9]{2}\z/)

  defp tag?(content),
    do: String.match?(content, ~r/\A[a-z_][a-z0-9_-]*=[A-Za-z0-9]+(-[A-Za-z0-9]+)*\z/)

  defp interpret(brackets) do
    Enum.reduce_while(brackets, {:ok, %{zone: nil, calendar: nil, tags: %{}}}, fn content,
                                                                                  {:ok, suffix} ->
      {critical, content} =
        case content do
          "!" <> rest -> {true, rest}
          rest -> {false, rest}
        end

      case tag(content, critical, suffix) do
        {:ok, suffix} -> {:cont, {:ok, suffix}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # The zone comes first and at most once; `u-ca` names the calendar; other tags are kept.
  defp tag(content, critical, %{zone: nil, tags: tags} = suffix)
       when map_size(tags) == 0 and suffix.calendar == nil do
    cond do
      offset?(content) ->
        {:ok, %{suffix | zone: %Tempo.Zone{offset: offset_minutes(content), critical: critical}}}

      tag?(content) ->
        keyed(content, critical, suffix)

      zone_name?(content) ->
        named_zone(content, critical, suffix)

      true ->
        {:error, {:suffix, content}}
    end
  end

  defp tag(content, critical, suffix) do
    cond do
      tag?(content) -> keyed(content, critical, suffix)
      zone_name?(content) or offset?(content) -> {:error, {:zone_after_tags, content}}
      true -> {:error, {:suffix, content}}
    end
  end

  defp named_zone(name, critical, suffix) do
    case Zone.named(name, critical: critical) do
      {:ok, zone} -> {:ok, %{suffix | zone: zone}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp keyed(content, critical, suffix) do
    [key, values] = String.split(content, "=", parts: 2)
    values = String.split(values, "-")

    case key do
      "u-ca" ->
        # The identifier is resolved to a calendar by the reader
        # (`Tempo.Calendar.from_type/1`), which knows CLDR's names and
        # Calendrical's own.
        {:ok, %{suffix | calendar: Enum.join(values, "-")}}

      _ ->
        if critical,
          do: {:error, {:critical, content}},
          else: {:ok, %{suffix | tags: Map.put_new(suffix.tags, key, values)}}
    end
  end

  defp offset_minutes(<<sign, h::binary-size(2), ":", m::binary-size(2)>>) do
    {:ok, hours, ""} = Number.digits(h)
    {:ok, minutes, ""} = Number.digits(m)
    factor = if sign == ?-, do: -1, else: 1
    factor * (hours * 60 + minutes)
  end
end
