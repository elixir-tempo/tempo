defmodule Tempo.InvalidCalendarError do
  @moduledoc """
  Exception returned (or raised, by the `!` variants) when the calendar
  given to `Tempo.from_iso8601/2`, `Tempo.parse/2` or `Tempo.new/1` is not
  a usable calendar module.

  A calendar is a module, such as `Calendrical.Hebrew`, and never the name
  of one (`:hebrew`, `"hebrew"`). The error is also returned when a
  namespace is passed instead of a concrete calendar — for example
  `Calendrical.Islamic`, whose concrete forms are
  `Calendrical.Islamic.Civil`, `Calendrical.Islamic.UmmAlQura`, and so on.

  """

  defexception [:calendar, :reason]

  @type t :: %__MODULE__{
          calendar: term(),
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{calendar: calendar}) when not is_nil(calendar) do
    "#{inspect(calendar)} is not a usable calendar module. A calendar is a module such " <>
      "as `Calendrical.Hebrew`, never the name of one. If it is a namespace " <>
      "(such as `Calendrical.Islamic`), use a concrete calendar like " <>
      "`Calendrical.Islamic.Civil` instead."
  end

  def message(%__MODULE__{}) do
    "The supplied calendar is not a usable calendar module"
  end
end
