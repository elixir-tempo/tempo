defmodule Tempo.InvalidUnitError do
  @moduledoc """
  Exception raised when an unrecognised time-unit atom is passed
  to a function expecting one of `:year`, `:month`, `:week`,
  `:day`, `:hour`, `:minute`, `:second`, `:day_of_year`, or
  `:day_of_week`.

  """

  alias Tempo.Border

  defexception [:unit, :valid_units]

  @type t :: %__MODULE__{
          unit: any() | nil,
          valid_units: [atom()] | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Border.leave(struct!(__MODULE__, bindings))
  end

  @impl true
  def message(%__MODULE__{unit: unit, valid_units: valid}) when is_list(valid) do
    "Invalid time unit #{Border.inspect(unit)}. Valid units are #{Border.inspect(valid)}"
  end

  def message(%__MODULE__{unit: unit}) do
    "Invalid time unit #{Border.inspect(unit)}"
  end
end
