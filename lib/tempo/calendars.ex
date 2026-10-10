defmodule Tempo.Calendars do
  @moduledoc false

  # The one place Tempo names a calendar.
  #
  # Tempo holds a calendar as a module that implements Elixir's `Calendar`
  # behaviour and Calendrical's, and asks it questions: it knows nothing of
  # how one counts. What it does know is which calendar its notation is
  # written in, and that is here, so that no other module names one:
  #
  # * ISO 8601 writes dates of the Gregorian calendar, so a value read or
  #   built with no calendar is in it (`default/0`), and so is one given
  #   `nil` or Elixir's `Calendar.ISO` for its calendar (`effective/1`).
  #
  # Whether a module is a calendar is asked once, where one is given
  # (`validated/1`), and is Calendrical's to say: that the module then keeps
  # the two behaviours is its author's to see to.

  # The calendar of ISO 8601's notation.
  @notation Calendrical.Gregorian

  @doc false
  # The calendar a value is in where none is given: the notation's.
  @spec default() :: module()
  def default, do: @notation

  @doc false
  # The calendar a value's `:calendar` stands for, as a module that keeps
  # Calendrical's behaviour: itself, the notation's where it is `nil`, and
  # the notation's for `Calendar.ISO`, which is the same calendar under
  # Elixir's behaviour alone.
  #
  # A value made by Tempo holds such a module already. One written as a
  # struct may hold `nil` or `Calendar.ISO`, and is read as the notation's
  # calendar: this is the one function that says so, and a value's calendar
  # is asked nothing before it has passed through it.
  @spec effective(module() | nil) :: module()
  def effective(nil), do: @notation
  def effective(Calendar.ISO), do: @notation
  def effective(calendar), do: calendar

  @doc false
  # The calendar a value is in (`effective/1` of its `:calendar`).
  @spec of(%{required(:calendar) => module() | nil}) :: module()
  def of(%{calendar: calendar}), do: effective(calendar)

  @doc false
  # A value with the calendar it is in, where it was written with `nil` or
  # `Calendar.ISO` for one.
  @spec settled(value) :: value when value: %{required(:calendar) => module() | nil}
  def settled(%{calendar: calendar} = value) do
    case effective(calendar) do
      ^calendar -> value
      effective -> %{value | calendar: effective}
    end
  end

  @doc false
  # Elixir's own module for a calendar, for a value handed back as a `Date`
  # or its kin: `Calendar.ISO` for the notation's calendar, and the calendar
  # itself for any other.
  @spec native(module() | nil) :: module()
  def native(calendar) do
    case effective(calendar) do
      @notation -> Calendar.ISO
      calendar -> calendar
    end
  end

  @doc false
  # A calendar given to Tempo, as the module a value holds: Calendrical says
  # whether it is a calendar, and reads `Calendar.ISO` as its own Gregorian
  # calendar. What is no calendar is `:error`.
  @spec validated(term()) :: {:ok, module()} | :error
  def validated(calendar) do
    case Calendrical.validate_calendar(calendar) do
      {:ok, calendar} -> {:ok, calendar}
      {:error, _not_a_calendar} -> :error
    end
  end
end
