defmodule Tempo.Territory do
  @moduledoc """
  Territory resolution — the bridge between the CLDR/BCP 47
  territory world (`:US`, `:SA`, `:GB`) and Tempo's
  locale-dependent constructors (`Tempo.workdays/1`,
  `Tempo.weekends/1`, and future holiday helpers).

  A *territory* is CLDR's key for locale-dependent data —
  weekday arithmetic, first-day-of-week, weekend definition,
  public holidays. `Tempo.Territory.resolve/1` normalises any
  of the following into a canonical uppercase atom:

  * An atom territory like `:US`, `:sa`, `:"sazzzz"`.

  * A string territory like `"US"`, `"sa"`, `"sazzzz"`.

  * A locale string like `"en-US"`, `"ar-SA"`.

  * A `%Localize.LanguageTag{}` value.

  * `nil` — falls back to `Application.get_env(:ex_tempo,
    :default_territory)`, then to
    `Localize.get_locale() |> Localize.Territory.territory_from_locale/1`.

  Territory resolution is deliberately *explicit*. It is **not**
  woven into `Tempo.select/2` — the selector is pure. Callers
  that want locale-aware weekend/workday sets compose them in:

      Tempo.select(~o"2026-06", Tempo.workdays(:US))

  ### Examples

      iex> Tempo.Territory.resolve(:US)
      {:ok, :US}

      iex> Tempo.Territory.resolve("sazzzz")
      {:ok, :SA}

      iex> Tempo.Territory.resolve("en-GB")
      {:ok, :GB}

  """

  alias Localize.Territory
  alias Localize.Validity.U

  @type input ::
          atom()
          | String.t()
          | Localize.LanguageTag.t()
          | nil

  @doc """
  Normalise `value` to a canonical territory atom.

  ### Arguments

  * `value` is one of the input shapes listed in the moduledoc.

  ### Returns

  * `{:ok, territory_atom}` on success.

  * `{:error, reason}` when a locale cannot be validated or a
    territory cannot be derived.

  ### Examples

      iex> Tempo.Territory.resolve(:AU)
      {:ok, :AU}

      iex> Tempo.Territory.resolve("ar-SA")
      {:ok, :SA}

  """
  @spec resolve(input()) :: {:ok, atom()} | {:error, term()}
  def resolve(value)

  def resolve(%Localize.LanguageTag{} = tag) do
    Territory.territory_from_locale(tag)
  end

  def resolve(nil) do
    case Application.get_env(:ex_tempo, :default_territory) do
      nil -> resolve_from_ambient_locale()
      value -> resolve(value)
    end
  end

  def resolve(value) when is_atom(value) do
    value |> Atom.to_string() |> resolve()
  end

  def resolve(value) when is_binary(value) do
    # Delegate all BCP 47 parsing to Localize rather than hand-rolling
    # territory/locale shapes. A bare territory code (`"US"`, `"sa"`)
    # validates directly; a locale (`"en-GB"`, `"en-US-u-rg-sazzzz"`)
    # resolves through `territory_from_locale/1`, which decodes the
    # `-u-` extension — including the `u-rg` region override — via
    # `Localize.LanguageTag.U`; a bare `u-rg` value (`"sazzzz"`) is
    # decoded by the same `-u` key decoder. Every path validates
    # against CLDR data, so no untrusted string reaches
    # `String.to_atom/1`.
    with {:error, _} <- Localize.validate_territory(value),
         {:error, _} <- Territory.territory_from_locale(value),
         {:error, _} <- decode_region_override(value) do
      {:error,
       ArgumentError.exception(
         "Tempo.Territory.resolve/1 does not recognise #{inspect(value)} as a " <>
           "territory, locale, or region override."
       )}
    end
  end

  def resolve(other) do
    {:error,
     ArgumentError.exception(
       "Tempo.Territory.resolve/1 does not recognise #{inspect(other)} — " <>
         "pass a territory atom, territory string, locale string, or " <>
         "%Localize.LanguageTag{}."
     )}
  end

  ## ----------------------------------------------------------
  ## Private helpers
  ## ----------------------------------------------------------

  defp resolve_from_ambient_locale do
    Localize.get_locale()
    |> Territory.territory_from_locale()
  end

  # A bare BCP 47 `u-rg` region-override value (`"sazzzz"` → `:SA`),
  # decoded by Localize's `-u` extension key decoder. It strips the
  # `zzzz` padding and validates the territory against CLDR data, so
  # Tempo never has to recognise the `u-rg` shape itself.
  defp decode_region_override(value) do
    case U.decode("rg", value) do
      {:ok, {:rg, territory}} -> {:ok, territory}
      {:error, _} = error -> error
    end
  end
end
