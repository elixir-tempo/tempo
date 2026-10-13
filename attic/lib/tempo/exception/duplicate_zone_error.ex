defmodule Tempo.DuplicateZoneError do
  @moduledoc """
  Exception raised when an IXDTF suffix contains more than one
  time-zone annotation. The standard permits at most one zone
  identifier per value.

  """

  alias Tempo.Calendars

  defexception [:zones, :suffix]

  @type t :: %__MODULE__{
          zones: [String.t()] | nil,
          suffix: String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Calendars.outside(struct!(__MODULE__, bindings))
  end

  @impl true
  def message(%__MODULE__{zones: zones}) when is_list(zones) and zones != [] do
    "Only one time zone may appear in a single IXDTF suffix; got #{Calendars.inspect(zones)}"
  end

  def message(%__MODULE__{}) do
    "Only one time zone may appear in a single IXDTF suffix"
  end
end
