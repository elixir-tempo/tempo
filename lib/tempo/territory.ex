defmodule Tempo.Territory do
  @moduledoc """
  Which territory a caller means: the CLDR territory (`:US`, `:SA`, `:GB`)
  whose weekend, workdays and conventions Tempo asks Localize for.

  A territory may be named directly, taken from a locale, or left to the
  application: `nil` is the configured `:default_territory`, and failing
  that the territory of the current locale.

      config :ex_tempo, default_territory: :AU

  """

  alias Localize.Territory

  @doc """
  The territory a value names.

  ### Arguments

  * `value` is a territory as an atom or a string (`:US`, `"sa"`), a locale
    (`"en-GB"`, a `t:Localize.LanguageTag.t/0`) whose territory is taken, or
    `nil` for the application's `:default_territory` and then the current
    locale's.

  ### Returns

  * `{:ok, territory}`, an atom.

  * `{:error, %ArgumentError{}}` for a value that names none.

  ### Examples

      iex> Tempo.Territory.resolve(:US)
      {:ok, :US}

      iex> Tempo.Territory.resolve("sa")
      {:ok, :SA}

      iex> Tempo.Territory.resolve("en-GB")
      {:ok, :GB}

      iex> {:error, %ArgumentError{}} = Tempo.Territory.resolve("nowhere at all")

  """
  @spec resolve(atom() | String.t() | Localize.LanguageTag.t() | nil) ::
          {:ok, atom()} | {:error, Exception.t()}
  def resolve(nil) do
    case Application.get_env(:ex_tempo, :default_territory) do
      nil -> Territory.territory_from_locale(Localize.get_locale())
      configured -> resolve(configured)
    end
  end

  def resolve(%Localize.LanguageTag{} = tag), do: Territory.territory_from_locale(tag)
  def resolve(value) when is_atom(value), do: resolve(Atom.to_string(value))

  def resolve(value) when is_binary(value) do
    with {:error, _} <- Localize.validate_territory(value),
         {:error, _} <- Territory.territory_from_locale(value) do
      {:error, not_a_territory(value)}
    end
  end

  def resolve(other), do: {:error, not_a_territory(other)}

  defp not_a_territory(value) do
    ArgumentError.exception(
      "#{inspect(value)} names no territory: give a territory (:US, \"SA\"), a locale (\"en-GB\") or nil"
    )
  end
end
