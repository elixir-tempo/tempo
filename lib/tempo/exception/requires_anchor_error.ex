defmodule Tempo.RequiresAnchorError do
  @moduledoc """
  Exception returned when arithmetic on an un-anchored value (one with
  no `:year`) would depend on the missing year, so it cannot be
  resolved.

  Some un-anchored arithmetic *is* answerable — `~o"1M31D"` shifted by
  one day is `~o"2M1D"`, because January always has 31 days. But
  shifting `~o"1M31D"` by one month lands in February, whose length
  depends on the year, so there is no single answer. In that case
  `Tempo.shift/2` (and the arithmetic beneath it) returns
  `{:error, %Tempo.RequiresAnchorError{}}` rather than guessing or
  crashing.

  """

  defexception [:value, :duration, :reason]

  @type t :: %__MODULE__{
          value: Tempo.t() | nil,
          duration: Tempo.Duration.t() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{value: value}) when not is_nil(value) do
    "Cannot resolve this arithmetic on #{inspect(value)} without a year — the " <>
      "result would depend on the missing year (for example a February day count). " <>
      "Anchor the value with a year first."
  end

  def message(%__MODULE__{}) do
    "Arithmetic on an un-anchored value requires a year to resolve"
  end
end
