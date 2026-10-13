defmodule Tempo.InvalidCalendarError do
  @moduledoc "A module or a name that is no calendar Tempo can ask."

  defexception [:calendar]

  @type t :: %__MODULE__{calendar: term()}

  @impl true
  def exception(bindings) when is_list(bindings), do: struct!(__MODULE__, bindings)

  @impl true
  def message(%__MODULE__{calendar: calendar}),
    do:
      "#{inspect(calendar)} is not a calendar: a calendar is a module that implements the Calendar and Calendrical behaviours"
end
