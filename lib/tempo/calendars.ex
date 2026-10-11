defmodule Tempo.Calendars do
  @moduledoc false

  import Kernel, except: [inspect: 1, inspect: 2]

  # The one place Tempo names a calendar.
  #
  # Tempo holds a calendar as a module that implements Elixir's `Calendar`
  # behaviour and Calendrical's, and asks it questions: it knows nothing of
  # how one counts. What it does know is which calendar its notation is
  # written in, and that is here, so that no other module names one:
  #
  # * A value read or built with no calendar is in the calendar of ISO
  #   8601's notation: Elixir's `Calendar.ISO` as a caller holds it, and
  #   inside a call the module that answers Calendrical's behaviour for it
  #   (`default/0`). A public function puts the one in the other's place
  #   in its first clause (`inside/1`) and back in what it answers
  #   (`outside/1`), so nothing else reads `nil` or `Calendar.ISO` for a
  #   calendar.
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

  # The calendar of ISO 8601's notation, as Tempo works with it.
  @notation Localize.Calendar.ISO

  # The calendar of ISO 8601's week dates.
  @weeks Calendrical.ISOWeek

  # The calendar a caller holds for a value that names none. `Calendar.ISO`
  # keeps Elixir's `Calendar` behaviour alone, so a public function works
  # with the module that answers Calendrical's behaviour for it (`@notation`)
  # and hands back `Calendar.ISO`: its first clause takes a value in
  # `Calendar.ISO`, calls itself with `inside/1` of it, and answers with
  # `outside/1` of what that gives.
  @outside Calendar.ISO

  # Elixir's dates and times, which name their calendar once.
  @dated [Date, Time, NaiveDateTime, DateTime]

  @typedoc false
  @type notation :: Localize.Calendar.ISO

  # Whether what names its calendar once names `Calendar.ISO`: a value (or
  # one written by hand with no calendar), a date or a time of Elixir's.
  defguardp is_held_outside(value)
            when is_map(value) and is_map_key(value, :calendar) and
                   (:erlang.map_get(:calendar, value) == @outside or
                      (:erlang.map_get(:calendar, value) == nil and is_struct(value, Tempo)))

  @doc false
  # Whether a value is as a caller holds it, for the first clause of a
  # public function: a value in `Calendar.ISO` (or written by hand with no
  # calendar), a date or a time of Elixir's in it, or an interval either end
  # of which is one. What a function's head cannot see (the members of a
  # set, the values of a list of options) is asked of `outside?/1`. The
  # structs are matched as maps, so that this module does not wait on
  # `Tempo` to compile.
  defguard is_outside(value)
           when is_held_outside(value) or
                  (is_struct(value, Tempo.Interval) and
                     (is_held_outside(:erlang.map_get(:from, value)) or
                        is_held_outside(:erlang.map_get(:to, value))))

  @doc false
  # What a public function was given, as Tempo works with it: `Calendar.ISO`
  # replaced by the module that answers for it wherever the term holds it,
  # and a value written by hand with no calendar read as one in it.
  @spec inside(term()) :: term()
  def inside(term) do
    replaced(term, @outside, @notation)
  end

  @doc false
  # What a public function answers, as a caller holds it: `Calendar.ISO` put
  # back wherever the term holds the module that answered for it.
  @spec outside(term()) :: term()
  def outside(term) do
    replaced(term, @notation, @outside)
  end

  @doc false
  # Whether anything in what a public function was given is as a caller
  # holds it, where that cannot be seen in the function's head: the members
  # of a set, the values of a list of options, a date of Elixir's.
  @spec outside?(term()) :: boolean()
  def outside?(@outside) do
    true
  end

  def outside?(%{__struct__: Tempo, calendar: calendar}) do
    calendar in [@outside, nil]
  end

  def outside?(%{__struct__: Tempo.Duration}) do
    false
  end

  def outside?(%Stream{}) do
    false
  end

  def outside?(%{calendar: @outside}) do
    true
  end

  def outside?([head | tail]) do
    outside?(head) or outside?(tail)
  end

  def outside?(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> outside?()
  end

  def outside?(term) when is_map(term) do
    any_entry?(:maps.next(:maps.iterator(term)))
  end

  def outside?(_term) do
    false
  end

  # A map's keys are read as its values are: the members of a `MapSet` are
  # the keys of the map it keeps.
  defp any_entry?(:none) do
    false
  end

  defp any_entry?({key, held, iterator}) do
    outside?(held) or outside?(key) or any_entry?(:maps.next(iterator))
  end

  # A term with one calendar replaced by the other wherever it holds it.
  defp replaced(from, from, to) do
    to
  end

  defp replaced(%{__struct__: Tempo, calendar: nil} = tempo, @outside, to) do
    replaced(%{tempo | calendar: @outside}, @outside, to)
  end

  # A value names its calendar once, and holds another value only in a unit
  # that is no plain number (a selection may hold an interval) and in its
  # metadata.
  defp replaced(%{__struct__: Tempo, calendar: calendar, time: time} = tempo, from, to) do
    %{
      tempo
      | calendar: replaced(calendar, from, to),
        time: replaced_units(time, from, to),
        metadata: replaced(tempo.metadata, from, to)
    }
  end

  defp replaced(%{__struct__: Tempo.Duration} = duration, _from, _to) do
    duration
  end

  defp replaced(%{__struct__: dated, calendar: calendar} = value, from, to)
       when dated in @dated do
    %{value | calendar: replaced(calendar, from, to)}
  end

  # A stream a value keeps gives its elements when they are read, and they
  # are replaced there.
  defp replaced(%Stream{} = stream, _from, _to) do
    stream
  end

  # A struct's keys are its fields' names, and stay.
  defp replaced(%_{} = struct, from, to) do
    :maps.map(fn _field, held -> replaced(held, from, to) end, struct)
  end

  defp replaced(term, from, to) when is_map(term) do
    Map.new(term, fn {key, held} -> {replaced(key, from, to), replaced(held, from, to)} end)
  end

  defp replaced([head | tail], from, to) do
    [replaced(head, from, to) | replaced(tail, from, to)]
  end

  defp replaced(term, from, to) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> replaced(from, to)
    |> List.to_tuple()
  end

  defp replaced(term, _from, _to) do
    term
  end

  # The units of a value: a plain number holds no calendar.
  defp replaced_units([{unit, held} | units], from, to) when is_integer(held) do
    [{unit, held} | replaced_units(units, from, to)]
  end

  defp replaced_units([{unit, held} | units], from, to) when is_atom(unit) do
    [{unit, replaced(held, from, to)} | replaced_units(units, from, to)]
  end

  defp replaced_units(time, from, to) do
    replaced(time, from, to)
  end

  @doc false
  # A selector as Tempo works with it. One that is a caller's own function
  # is called from inside a call, and is given each period as the caller
  # holds it: what it answers is replaced where it is called.
  @spec inside_selector(term()) :: term()
  def inside_selector(selector) when is_function(selector, 1) do
    fn period -> selector.(outside(period)) end
  end

  def inside_selector(selector) do
    inside(selector)
  end

  @doc false
  # The function an enumeration gives each element to, where that is a
  # caller's own: each element is given to it as the caller holds it.
  @spec outside_reducer((term(), term() -> term())) :: (term(), term() -> term())
  def outside_reducer(function) when is_function(function, 2) do
    fn element, accumulator -> function.(outside(element), accumulator) end
  end

  @doc false
  # What `Enumerable.slice/1` answers a caller with: the function it hands
  # back gives its elements as the caller holds them.
  @spec outside_slice({:ok, non_neg_integer(), function()} | {:error, module()}) ::
          {:ok, non_neg_integer(), function()} | {:error, module()}
  def outside_slice({:ok, size, slicer}) when is_function(slicer, 3) do
    {:ok, size, fn start, length, step -> outside(slicer.(start, length, step)) end}
  end

  def outside_slice({:error, _module} = error) do
    error
  end

  @doc false
  # A term as text a caller is to read. A message is written inside a call,
  # of what Tempo holds there, and says of a term what the caller holds:
  # every message in the library is written with this, and none with
  # `Kernel.inspect/2` (`test/tempo/calendars_test.exs` reads the source for
  # it).
  @spec inspect(term(), keyword()) :: String.t()
  def inspect(term, options \\ []) do
    Kernel.inspect(outside(term), options)
  end

  @doc false
  # A calendar's name in text a caller is to read (a message, a value as it
  # is written): the name the caller knows it by.
  @spec name(module()) :: String.t()
  def name(calendar) do
    Kernel.inspect(outside(calendar))
  end

  @doc false
  # The calendar a value is in where none is given: the notation's. ISO
  # 8601-2's seasons are the seasons of its months, and an event of the sky
  # or of the church is dated in it.
  @spec default() :: notation()
  def default do
    @notation
  end

  @doc false
  # The calendar the zone database keeps its clocks in. A value of another
  # calendar is read on a zone's clock as the date of the same day in it.
  @spec zone() :: notation()
  def zone do
    @notation
  end

  @doc false
  # The calendar a rule of RFC 5545, of cron or of JSCalendar counts its
  # months and its years in.
  @spec rule() :: notation()
  def rule do
    @notation
  end

  @doc false
  # The calendar an identifier written beside a value names (IXDTF's
  # `[u-ca=…]`), by its CLDR calendar type: the one place such a name
  # becomes a module. `iso8601` names the calendar ISO 8601's own text is
  # in, which is the calendar of a value that names none. Any other is
  # Calendrical's to say.
  @spec named(atom() | String.t()) :: {:ok, module()} | {:error, Exception.t()}
  def named(type) when type in [:iso8601, "iso8601"] do
    {:ok, @notation}
  end

  def named(type) do
    Calendrical.calendar_from_cldr_calendar_type(type)
  end

  @doc false
  # A date, or a date and time, that another library read for a rule (the
  # `ical` library, `jscalendar`), as one of the calendar a rule counts in.
  # Such a library reads into Elixir's own calendar, and what it read is
  # made a date of a calendar Tempo holds where it arrives.
  @spec in_rule(value) :: value when value: Date.t() | NaiveDateTime.t() | DateTime.t()
  def in_rule(%DateTime{} = value) do
    converted(value, DateTime.convert(value, @notation))
  end

  def in_rule(%NaiveDateTime{} = value) do
    converted(value, NaiveDateTime.convert(value, @notation))
  end

  def in_rule(%Date{} = value) do
    converted(value, Date.convert(value, @notation))
  end

  defp converted(_value, {:ok, converted}) do
    converted
  end

  defp converted(value, {:error, _not_convertible}) do
    value
  end

  @doc false
  # The calendar of the notation's week dates (`2026-W10-1`), which a value
  # is in where the sigil's `W` says so.
  @spec weeks() :: Calendrical.ISOWeek
  def weeks do
    @weeks
  end

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
  def validated(@notation) do
    {:ok, @notation}
  end

  def validated(calendar) do
    case Calendrical.validate_calendar(calendar) do
      {:ok, calendar} -> {:ok, calendar}
      {:error, _not_a_calendar} -> :error
    end
  end
end
