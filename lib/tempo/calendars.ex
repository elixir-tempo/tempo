defmodule Tempo.Calendars do
  @moduledoc false

  alias Tempo.Border

  # The one place Tempo names a calendar.
  #
  # Tempo holds a calendar as a module that implements Elixir's `Calendar`
  # behaviour and Calendrical's, and asks it questions: it knows nothing of
  # how one counts. What it does know is which calendar its notation is
  # written in, and that is here, so that no other module names one:
  #
  # * A value read or built with no calendar is in the calendar of ISO
  #   8601's notation (`default/0`): Elixir's `Calendar.ISO` as a caller
  #   holds it, and here the module Tempo works with for it, which
  #   `Tempo.Border` puts in its place as a call comes in. So no module but
  #   that one reads `nil` or `Calendar.ISO` for a calendar.
  #
  # * ISO 8601 writes week dates too, which are dates of the calendar of its
  #   weeks (`weeks/0`): the calendar the sigil's `W` names, and the second
  #   a value is written in with no calendar named beside it.
  #
  # * What lies outside Tempo has a calendar of its own, which is the
  #   notation's for each: the zone database keeps its clocks in it
  #   (`zone/0`), and an RRULE, a cron expression and a JSCalendar rule count
  #   their months and years in it (`rule/0`, and `in_rule/1` for a date
  #   another library read for one). An identifier written beside a value
  #   names a calendar (`named/1`).
  #
  # Whether a module is a calendar is asked once, where one is given
  # (`validated/1`), and is Calendrical's to say: that the module then keeps
  # the two behaviours is its author's to see to.

  # The calendar of ISO 8601's notation.
  @notation Border.inside()

  # The calendar of ISO 8601's week dates.
  @weeks Calendrical.ISOWeek

  # The calendar a caller holds for a value that names none. `Calendar.ISO`
  # keeps Elixir's `Calendar` behaviour alone, so a public function works
  # with the module that answers Calendrical's behaviour for it (`@notation`)
  # and hands back `Calendar.ISO`: its first clause takes a value in
  # `Calendar.ISO`, calls itself with `inside/1` of it, and answers with
  # `outside/1` of what that gives.
  @outside Calendar.ISO

  @doc false
  # Whether a value is as a caller holds it, for the first clause of a
  # public function: a value in `Calendar.ISO` (or written by hand with no
  # calendar), an interval either end of which is one, or a set whose first
  # member is.
  defguard is_outside(value)
           when (is_struct(value, Tempo) and :erlang.map_get(:calendar, value) in [@outside, nil]) or
                  (is_struct(value, Tempo.Interval) and
                     ((is_struct(:erlang.map_get(:from, value), Tempo) and
                         :erlang.map_get(:calendar, :erlang.map_get(:from, value)) in [
                           @outside,
                           nil
                         ]) or
                        (is_struct(:erlang.map_get(:to, value), Tempo) and
                           :erlang.map_get(:calendar, :erlang.map_get(:to, value)) in [
                             @outside,
                             nil
                           ])))

  @doc false
  # A value as Tempo works with it: `Calendar.ISO` replaced by the module
  # that answers for it, in a value, in each end of an interval and in each
  # member of a set. A list or a tuple is one of such (a list of options is
  # a list of pairs), and anything else is as it was.
  @spec inside(term()) :: term()
  def inside(@outside) do
    @notation
  end

  def inside(%{__struct__: Tempo, calendar: calendar} = tempo) when calendar in [@outside, nil] do
    %{tempo | calendar: @notation}
  end

  def inside(%{__struct__: Tempo.Interval, from: from, to: to} = interval) do
    %{interval | from: inside(from), to: inside(to)}
  end

  def inside(%{__struct__: Tempo.IntervalSet, intervals: intervals} = set)
      when is_list(intervals) do
    %{set | intervals: inside(intervals)}
  end

  def inside(values) when is_list(values) do
    Enum.map(values, &inside/1)
  end

  def inside({key, value}) do
    {key, inside(value)}
  end

  def inside(other) do
    other
  end

  @doc false
  # What a public function answers, as a caller holds it: `Calendar.ISO` put
  # back, in a value, an interval, a set, a list of them, or a tuple that
  # holds one (`{:ok, value}`, the two ends of an interval).
  @spec outside(term()) :: term()
  def outside(@notation) do
    @outside
  end

  def outside(%{__struct__: Tempo, calendar: @notation} = tempo) do
    %{tempo | calendar: @outside}
  end

  def outside(%{__struct__: Tempo.Interval, from: from, to: to} = interval) do
    %{interval | from: outside(from), to: outside(to)}
  end

  def outside(%{__struct__: Tempo.IntervalSet, intervals: intervals} = set)
      when is_list(intervals) do
    %{set | intervals: outside(intervals)}
  end

  def outside(values) when is_list(values) do
    Enum.map(values, &outside/1)
  end

  def outside({first, second}) do
    {outside(first), outside(second)}
  end

  def outside(other) do
    other
  end

  @doc false
  # Whether anything in what a public function was given is as a caller
  # holds it, where that cannot be seen in the function's head: a list of
  # options whose values are values.
  @spec outside?(term()) :: boolean()
  def outside?(value) when is_outside(value) do
    true
  end

  def outside?(@outside) do
    true
  end

  def outside?(values) when is_list(values) do
    Enum.any?(values, &outside?/1)
  end

  def outside?({_key, value}) do
    outside?(value)
  end

  def outside?(_other) do
    false
  end

  @doc false
  # The calendar a value is in where none is given: the notation's. ISO
  # 8601-2's seasons are the seasons of its months, and an event of the sky
  # or of the church is dated in it.
  @spec default() :: Border.inside()
  def default, do: @notation

  @doc false
  # The calendar the zone database keeps its clocks in. A value of another
  # calendar is read on a zone's clock as the date of the same day in it.
  @spec zone() :: Border.inside()
  def zone, do: @notation

  @doc false
  # The calendar a rule of RFC 5545, of cron or of JSCalendar counts its
  # months and its years in.
  @spec rule() :: Border.inside()
  def rule, do: @notation

  @doc false
  # The calendar an identifier written beside a value names (IXDTF's
  # `[u-ca=…]`), by its CLDR calendar type: the one place such a name
  # becomes a module. `iso8601` names the calendar ISO 8601's own text is
  # in, which is the calendar of a value that names none. Any other is
  # Calendrical's to say.
  @spec named(atom() | String.t()) :: {:ok, module()} | {:error, Exception.t()}
  def named(type) when type in [:iso8601, "iso8601"], do: {:ok, @notation}
  def named(type), do: Calendrical.calendar_from_cldr_calendar_type(type)

  @doc false
  # A date, or a date and time, that another library read for a rule (the
  # `ical` library, `jscalendar`), as one of the calendar a rule counts in.
  # Such a library reads into Elixir's own calendar, and what it read is
  # made a date of a calendar Tempo holds where it arrives.
  @spec in_rule(value) :: value when value: Date.t() | NaiveDateTime.t() | DateTime.t()
  def in_rule(%DateTime{} = value), do: converted(value, DateTime.convert(value, @notation))

  def in_rule(%NaiveDateTime{} = value),
    do: converted(value, NaiveDateTime.convert(value, @notation))

  def in_rule(%Date{} = value), do: converted(value, Date.convert(value, @notation))

  defp converted(_value, {:ok, converted}), do: converted
  defp converted(value, {:error, _not_convertible}), do: value

  @doc false
  # The calendar of the notation's week dates (`2026-W10-1`), which a value
  # is in where the sigil's `W` says so.
  @spec weeks() :: Calendrical.ISOWeek
  def weeks, do: @weeks

  @doc false
  # Whether a calendar is the notation's, for a guard: the calendar of a
  # value written with no calendar named beside it.
  defguard is_notation(calendar) when calendar == @notation

  @doc false
  # Whether a calendar is the calendar of the notation's week dates, for a
  # guard. With `is_notation/1` it says a value is written in a calendar of
  # the notation's own: no calendar is named beside it, and its weeks are
  # ISO 8601's in either.
  defguard is_notation_weeks(calendar) when calendar == @weeks

  @doc false
  # A calendar given to Tempo, as the module a value holds: Calendrical says
  # whether it is a calendar, and what is none is `:error`. The notation's
  # own is one, and is not asked about: the module that keeps both
  # behaviours for `Calendar.ISO` is Localize's, which cannot declare
  # Calendrical's, and Calendrical knows a calendar by what it declares.
  @spec validated(term()) :: {:ok, module()} | :error
  def validated(@notation), do: {:ok, @notation}

  def validated(calendar) do
    case Calendrical.validate_calendar(calendar) do
      {:ok, calendar} -> {:ok, calendar}
      {:error, _not_a_calendar} -> :error
    end
  end
end
