defmodule Tempo.Options do
  @moduledoc false

  # The options a function takes, checked where it is called (law 7): an
  # option it does not read is refused, where passing it over would answer
  # another question than the one asked. A window misspelt, or given under
  # the name it had in Tempo 1, is no window at all.

  # The names an option had in Tempo 1, and what each is now.
  @renamed [bound: :within]

  @doc """
  Whether every option given is one the function takes: `:ok`, or an
  `ArgumentError` that names the first that is not and what the function
  does take.
  """
  @spec check(term(), [atom()], String.t()) :: :ok | {:error, Exception.t()}
  def check(options, allowed, function) do
    if Keyword.keyword?(options),
      do:
        options |> Keyword.keys() |> Enum.find(&(&1 not in allowed)) |> checked(allowed, function),
      else: {:error, ArgumentError.exception("#{function} takes its options as a keyword list")}
  end

  @doc "`check/3`, returning the options or raising."
  @spec check!(term(), [atom()], String.t()) :: keyword()
  def check!(options, allowed, function) do
    case check(options, allowed, function) do
      :ok -> options
      {:error, exception} -> raise exception
    end
  end

  defp checked(nil, _allowed, _function), do: :ok

  defp checked(unknown, allowed, function) do
    message = "#{inspect(unknown)} is not an option of #{function}: " <> takes(unknown, allowed)
    {:error, ArgumentError.exception(message)}
  end

  defp takes(unknown, allowed) do
    case Keyword.fetch(@renamed, unknown) do
      {:ok, now} -> if now in allowed, do: "it is #{inspect(now)}", else: listed(allowed)
      :error -> listed(allowed)
    end
  end

  defp listed([]), do: "it takes none"
  defp listed([one]), do: "it takes #{inspect(one)}"
  defp listed(allowed), do: "it takes " <> Enum.map_join(allowed, ", ", &inspect/1)
end
