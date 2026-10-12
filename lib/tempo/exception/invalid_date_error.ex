defmodule Tempo.InvalidDateError do
  @moduledoc """
  Exception raised when date components do not form a valid date
  under the chosen calendar.

  Reasons include a month outside `1..months_in_year(year)`, a
  day outside `1..days_in_month(year, month)`, and calendar-
  specific rules (Cheshvan-30 is valid only in a Hebrew complete
  year, for example).

  """

  alias Tempo.Calendars

  defexception [:unit, :value, :valid_range, :year, :month, :day, :calendar, :reason]

  @type t :: %__MODULE__{
          unit: atom() | nil,
          value: integer() | nil,
          valid_range: Range.t() | [Range.t()] | nil,
          year: integer() | nil,
          month: integer() | nil,
          day: integer() | nil,
          calendar: module() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    Calendars.outside(struct!(__MODULE__, bindings))
  end

  # A reason that is written out is the whole of what there is to say: it
  # names the value, what it was read as, and the values it could have been
  # (`Tempo.Validation.conform/3`), or why the unit has no place in the
  # calendar. The unit and the value are held beside it for a caller to read.
  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason) do
    reason
  end

  def message(%__MODULE__{unit: unit, value: value, valid_range: range, year: y, month: m})
      when not is_nil(unit) and not is_nil(value) and not is_nil(range) do
    context = date_context(y, m)

    "#{Calendars.inspect(value)} is not valid for #{unit}#{context} (valid range #{Calendars.inspect(range)})"
  end

  def message(%__MODULE__{unit: unit, value: value}) when not is_nil(unit) do
    "Invalid #{unit}: #{Calendars.inspect(value)}"
  end

  def message(%__MODULE__{reason: reason}) when is_atom(reason) and not is_nil(reason) do
    "Invalid date: #{reason}"
  end

  def message(%__MODULE__{}) do
    "Invalid date"
  end

  defp date_context(nil, nil) do
    ""
  end

  defp date_context(y, nil) do
    " in #{y}"
  end

  defp date_context(nil, m) do
    " in month #{m}"
  end

  defp date_context(y, m) do
    " in #{y}-#{pad2(m)}"
  end

  defp pad2(m) when is_integer(m) do
    String.pad_leading(Integer.to_string(m), 2, "0")
  end
end
