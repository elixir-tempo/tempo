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
  # * ISO 8601 writes week dates too, which are dates of the calendar of its
  #   weeks (`weeks/0`): the calendar the sigil's `W` names, and the second
  #   a value is written in with no calendar named beside it.
  #
  # * What lies outside Tempo has a calendar of its own, which is the
  #   Gregorian for each: the zone database keeps its clocks in it
  #   (`zone/0`), and an RRULE, a cron expression and a JSCalendar rule count
  #   their months and years in it (`rule/0`). Elixir's own name for it is
  #   `Calendar.ISO` (`native/0`).
  #
  # Whether a module is a calendar is asked once, where one is given
  # (`validated/1`), and is Calendrical's to say: that the module then keeps
  # the two behaviours is its author's to see to.

  # The calendar of ISO 8601's notation.
  @notation Calendrical.Gregorian

  # The calendar of ISO 8601's week dates.
  @weeks Calendrical.ISOWeek

  # What holds a calendar: a value, an interval's end, a duration, or any
  # other struct or map with a `:calendar` among its keys.
  @typep holder :: %{required(:calendar) => module() | nil, optional(atom()) => any()}

  @doc false
  # The calendar a value is in where none is given: the notation's. ISO
  # 8601-2's seasons are the seasons of its months, and an event of the sky
  # or of the church is dated in it.
  @spec default() :: Calendrical.Gregorian
  def default, do: @notation

  @doc false
  # The calendar the zone database keeps its clocks in. A value of another
  # calendar is read on a zone's clock as the date of the same day in it.
  @spec zone() :: Calendrical.Gregorian
  def zone, do: @notation

  @doc false
  # The calendar a rule of RFC 5545, of cron or of JSCalendar counts its
  # months and its years in.
  @spec rule() :: Calendrical.Gregorian
  def rule, do: @notation

  @doc false
  # Elixir's own module for the notation's calendar, which the dates Astro
  # and Calendrical's events answer with are handed back in.
  @spec native() :: Calendar.ISO
  def native, do: Calendar.ISO

  @doc false
  # The calendar of the notation's week dates (`2026-W10-1`), which a value
  # is in where the sigil's `W` says so.
  @spec weeks() :: Calendrical.ISOWeek
  def weeks, do: @weeks

  @doc false
  # Whether a value's `:calendar` stands for the notation's calendar, for a
  # guard: the calendar itself, `Calendar.ISO`, or `nil` (`effective/1`).
  defguard is_notation(calendar) when calendar in [@notation, Calendar.ISO, nil]

  @doc false
  # Whether a calendar is the calendar of the notation's week dates, for a
  # guard. With `is_notation/1` it says a value is written in a calendar of
  # the notation's own: no calendar is named beside it, and its weeks are
  # ISO 8601's in either.
  defguard is_notation_weeks(calendar) when calendar == @weeks

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
  @spec of(holder()) :: module()
  def of(%{calendar: calendar}), do: effective(calendar)

  @doc false
  # A value with the calendar it is in, where it was written with `nil` or
  # `Calendar.ISO` for one.
  @spec settled(value) :: value when value: holder()
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
      @notation -> native()
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
