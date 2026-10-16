defmodule Tempo.Build do
  @moduledoc false

  # Expressions built from parts: a selection, a recurrence, a one-of set.
  #
  # Each builds the form the reader builds for the text that writes it, and
  # is checked by the same pass (`Tempo.Validate`), so that a program holds
  # the parts of an expression as data and never writes text to be read
  # back. What `Tempo.new/1`, `Tempo.Interval.new/1`, `Tempo.Duration.new/1`
  # and `Tempo.IntervalSet.new/2` build are the parts these take.

  alias Tempo.{ConversionError, Duration, FrameError, InvalidCalendarError, Options, Spans}
  alias Tempo.{Select, Unit, Validate, Workdays}

  # The units a selection names, coarsest first, as a rule's parts are held.
  @units [
    :year,
    :month,
    :traditional_month,
    :week,
    :day_of_year,
    :day,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]
  @clock [:hour, :minute, :second]
  @parts @units ++ [:instance, :event, :roll, :skip, :selection, :window, :all]

  @every_options [:from, :to, :count, :until, :select, :calendar, :years, :metadata]

  # The years a domain may be filtered to, as `e`, `o`, `l` and `c` write them.
  @year_filters [:even, :odd, :leap, :common]

  # ── A selection ───────────────────────────────────────────────────────

  @doc "A selection (`L…N`) from its parts, as a value with no year, in a calendar."
  @spec selection(keyword(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def selection(parts, options \\ []) do
    with :ok <- Options.check(options, [:calendar], "Tempo.selection/2"),
         {:ok, calendar} <- a_calendar(Keyword.get(options, :calendar, Tempo.Calendar.default())),
         {:ok, parts} <- parts(parts, calendar) do
      Validate.run(%Tempo{form: {:value, [selection: parts]}, calendar: calendar})
    end
  end

  defp a_calendar(calendar) do
    if Tempo.Calendar.calendar?(calendar) do
      {:ok, calendar}
    else
      {:error, InvalidCalendarError.exception(calendar: calendar)}
    end
  end

  @doc """
  A selection's parts in the form a rule holds them, the units coarsest
  first and a position last, with a day of the week given by its name
  numbered in the calendar (decision 80), and a selection of another
  calendar's days of the week numbered in this one.
  """
  @spec parts(term(), module()) :: {:ok, Tempo.selection()} | {:error, Exception.t()}
  def parts(parts, calendar \\ Tempo.Calendar.default())

  def parts(%Tempo{form: {:value, [selection: parts]}, calendar: own}, calendar),
    do: {:ok, Select.weekdays_in(parts, own, calendar)}

  def parts(parts, calendar) when is_list(parts) do
    with :ok <- known(parts),
         {:ok, held} <- each_part(Select.weekdays_named(parts, calendar), calendar) do
      {:ok, ordered(held)}
    end
  end

  def parts(other, _calendar),
    do: {:error, argument("a selection is a keyword list of parts, not #{inspect(other)}")}

  defp known(parts) do
    cond do
      not Keyword.keyword?(parts) or parts == [] ->
        {:error, argument("a selection is a keyword list of parts, not #{inspect(parts)}")}

      unknown = Enum.find(Keyword.keys(parts), &(&1 not in @parts)) ->
        {:error, argument("#{inspect(unknown)} is not a part of a selection: it has #{listed()}")}

      Keyword.has_key?(parts, :window) and not Keyword.has_key?(parts, :selection) ->
        {:error, argument("a :window is the length of what a nested :selection selects")}

      true ->
        :ok
    end
  end

  defp listed, do: Enum.map_join(@parts, ", ", &inspect/1)

  defp each_part(parts, calendar) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, held} ->
      case part(part, calendar) do
        {:ok, part} -> {:cont, {:ok, held ++ [part]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp part({:event, name}, _calendar) when is_binary(name), do: {:ok, {:event, {name, nil}}}

  defp part({:event, {name, _} = event}, _calendar) when is_binary(name),
    do: {:ok, {:event, event}}

  defp part({:window, %Duration{} = length}, _calendar), do: {:ok, {:window, length}}

  defp part({:skip, direction}, _calendar) when direction in [:forward, :backward],
    do: {:ok, {:skip, direction}}

  defp part({:skip, other}, _calendar),
    do: {:error, argument(":skip of a selection is :forward or :backward, not #{inspect(other)}")}

  # A lunisolar calendar's month as it is named: its number, or its leap month.
  defp part({:traditional_month, {month, :leap}}, _calendar) when is_integer(month),
    do: {:ok, {:traditional_month, {month, :leap}}}

  defp part({:roll, convention}, _calendar) do
    if convention in Workdays.conventions(),
      do: {:ok, {:roll, convention}},
      else:
        {:error,
         argument(
           ":roll of a selection is one of #{inspect(Workdays.conventions())}, not #{inspect(convention)}"
         )}
  end

  defp part({:selection, nested}, calendar) do
    with {:ok, parts} <- parts(nested, calendar), do: {:ok, {:selection, parts}}
  end

  # Several selections whose values are taken together: the second Monday
  # and the second Wednesday, `[all: [[day_of_week: 1, instance: 2],
  # [day_of_week: 3, instance: 2]]]`.
  defp part({:all, [_ | _] = each}, calendar) do
    with {:ok, each} <- each_selection(each, calendar), do: {:ok, {:all, each}}
  end

  defp part({:all, other}, _calendar),
    do: {:error, argument(":all of a selection is a list of selections, not #{inspect(other)}")}

  defp part({unit, %Range{} = range}, _calendar) when unit in @units or unit == :instance,
    do: {:ok, {unit, [range]}}

  defp part({unit, held}, _calendar)
       when (unit in @units or unit == :instance) and is_integer(held),
       do: {:ok, {unit, held}}

  defp part({unit, held}, _calendar)
       when (unit in @units or unit == :instance) and is_list(held) do
    if Enum.all?(held, &(is_integer(&1) or is_struct(&1, Range))),
      do: {:ok, {unit, held}},
      else:
        {:error,
         argument("#{inspect(unit)} takes whole numbers and ranges, not #{inspect(held)}")}
  end

  defp part({key, held}, _calendar),
    do: {:error, argument("#{inspect(key)} of a selection does not take #{inspect(held)}")}

  defp each_selection(each, calendar) do
    Enum.reduce_while(each, {:ok, []}, fn selection, {:ok, held} ->
      case parts(selection, calendar) do
        {:ok, parts} -> {:cont, {:ok, held ++ [parts]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # A nested selection and its window stand first, where they are made, and
  # a set of selections after the months it is made in; the units follow
  # coarsest first, and a position counts among them all.
  defp ordered(parts) do
    {nested, rest} = Keyword.split(parts, [:selection, :window])
    {all, rest} = Keyword.split(rest, [:all])
    {last, units} = Keyword.split(rest, [:instance])
    {events, units} = Keyword.split(units, [:event])
    {rolls, units} = Keyword.split(units, [:skip, :roll])

    {before, later} =
      Enum.split_with(units, fn {unit, _} -> unit in [:year, :month, :traditional_month] end)

    {times, days} = Enum.split_with(later, fn {unit, _} -> unit in @clock end)

    # A skip and a roll stand after the days they move and before a time of day on them.
    by_order(before) ++
      nested ++ all ++ events ++ by_order(days) ++ rolls ++ by_order(times) ++ last
  end

  defp by_order(units),
    do: Enum.sort_by(units, fn {unit, _} -> Enum.find_index(@units, &(&1 == unit)) end)

  # ── A recurrence ──────────────────────────────────────────────────────

  @doc "A recurrence from its cadence, its start, its end and what it selects in each repeat."
  @spec every(Duration.t() | keyword(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def every(cadence, options) do
    with :ok <- Options.check(options, @every_options, "Tempo.every/2"),
         {:ok, cadence} <- cadence(cadence),
         {:ok, first} <- first(Keyword.get(options, :from), Keyword.get(options, :to), cadence),
         {:ok, first} <- in_calendar(first, Keyword.get(options, :calendar)),
         {:ok, first} <- in_years(first, Keyword.get(options, :years)),
         {:ok, bound} <- bound(Keyword.get(options, :count), Keyword.get(options, :until)),
         {:ok, bound} <- bound_in_frame(bound, first),
         {:ok, rule} <- rule(Keyword.get(options, :select), first.calendar) do
      Validate.run(%Tempo{
        form: {:every, first, bound, rule},
        calendar: first.calendar,
        zone: first.zone,
        metadata: Keyword.get(options, :metadata, %{})
      })
    end
  end

  defp cadence(%Duration{units: [_ | _]} = cadence), do: {:ok, cadence}
  defp cadence(units) when is_list(units) and units != [], do: Duration.new(units)

  defp cadence(other),
    do: {:error, argument("a cadence is a duration or its units, not #{inspect(other)}")}

  # The first repeat: from a value, from each member of a set (a domain), or with no start.
  defp first(nil, nil, cadence),
    do: {:ok, %Tempo{form: {:span, :open, cadence}}}

  # A recurrence counted back from where it ends (`R5/P1M/2026-06-01`).
  defp first(nil, %Tempo{form: {:value, _}} = to, cadence),
    do: {:ok, %Tempo{form: {:span, cadence, to}, calendar: to.calendar, zone: to.zone}}

  defp first(nil, other, _cadence),
    do: {:error, argument(":to is the value a recurrence ends with, not #{inspect(other)}")}

  defp first(%Tempo{form: {kind, _}} = from, nil, cadence) when kind in [:value, :all, :one],
    do: {:ok, %Tempo{form: {:span, from, cadence}, calendar: from.calendar, zone: from.zone}}

  defp first(%Tempo{form: {:when, _, _}} = from, nil, cadence),
    do: {:ok, %Tempo{form: {:span, from, cadence}, calendar: from.calendar, zone: from.zone}}

  defp first(_from, %Tempo{}, _cadence),
    do: {:error, argument("a recurrence starts at :from or ends at :to, not both")}

  defp first(other, nil, _cadence),
    do: {:error, argument(":from is a value, or a set as a domain, not #{inspect(other)}")}

  # A recurrence with no start is in the calendar given; one with a start
  # is in its start's, which a calendar given must be.
  defp in_calendar(first, nil), do: {:ok, first}
  defp in_calendar(%Tempo{calendar: calendar} = first, calendar), do: {:ok, first}

  defp in_calendar(%Tempo{form: {:span, :open, _cadence}} = first, calendar) do
    if Tempo.Calendar.calendar?(calendar),
      do: {:ok, %{first | calendar: calendar}},
      else: {:error, InvalidCalendarError.exception(calendar: calendar)}
  end

  defp in_calendar(_first, calendar),
    do:
      {:error,
       argument(
         ":calendar is the calendar of a recurrence with no :from, or that of its :from, not #{inspect(calendar)}"
       )}

  # A domain filtered to some of its years (`R/..e`, `R/{2017Y..}l`): every
  # year where the recurrence has no start, or those of the set it starts in.
  defp in_years(first, nil), do: {:ok, first}

  defp in_years(%Tempo{form: {:span, :open, cadence}} = first, filter)
       when filter in @year_filters do
    every_year = %Tempo{form: {:span, :open, :open}, calendar: first.calendar}
    {:ok, %{first | form: {:span, filtered(every_year, filter), cadence}}}
  end

  defp in_years(%Tempo{form: {:span, %Tempo{form: {:all, _}} = domain, cadence}} = first, filter)
       when filter in @year_filters,
       do: {:ok, %{first | form: {:span, filtered(domain, filter), cadence}}}

  defp in_years(_first, filter) when filter in @year_filters,
    do:
      {:error, argument(":years filters a domain, a set given as :from, or every year with none")}

  defp in_years(_first, filter),
    do: {:error, argument(":years is one of #{inspect(@year_filters)}, not #{inspect(filter)}")}

  defp filtered(domain, filter),
    do: %Tempo{form: {:when, domain, years: filter}, calendar: domain.calendar, zone: domain.zone}

  defp bound(nil, nil), do: {:ok, :infinity}
  defp bound(count, nil) when is_integer(count) and count > 0, do: {:ok, count}
  defp bound(nil, %Tempo{form: {:value, _}} = until), do: {:ok, until}

  defp bound(count, until) when count != nil and until != nil,
    do: {:error, argument("a recurrence ends by :count or by :until, not by both")}

  defp bound(count, nil),
    do: {:error, argument(":count is a whole number above zero, not #{inspect(count)}")}

  defp bound(nil, until), do: {:error, argument(":until is a value, not #{inspect(until)}")}

  @doc """
  The bound of a recurrence in the frame of its first repeat, as the reader
  gives a suffix's calendar and zone to every value before it: an until of
  a calendar of the same days (the Gregorian, its weeks begun on another
  day) is in the first repeat's, and one with no zone is in its zone, a
  value written at a shift the same instant read there. An until of another
  calendar is refused, as an interval's two ends of two calendars are.
  """
  @spec bound_in_frame(term(), Tempo.t()) :: {:ok, term()} | {:error, Exception.t()}
  def bound_in_frame(%Tempo{} = until, %Tempo{calendar: calendar, zone: zone}) do
    with {:ok, until} <- until_in(until, calendar), do: until_zoned(until, zone)
  end

  def bound_in_frame(bound, _first), do: {:ok, bound}

  defp until_in(%Tempo{calendar: calendar} = until, calendar), do: {:ok, until}

  defp until_in(%Tempo{} = until, calendar) do
    if Tempo.Calendar.gregorian?(until.calendar) and Tempo.Calendar.gregorian?(calendar),
      do: {:ok, %{until | calendar: calendar}},
      else:
        {:error,
         argument(
           ":until is in #{inspect(until.calendar)} and the recurrence in #{inspect(calendar)}; " <>
             "convert it with Tempo.to_calendar/2"
         )}
  end

  defp until_zoned(%Tempo{zone: nil} = until, %Tempo.Zone{} = zone),
    do: Validate.run(%{until | zone: zone})

  defp until_zoned(until, _zone), do: Validate.run(until)

  # A day of the week a rule names is numbered in the recurrence's calendar.
  defp rule(nil, _calendar) do
    {:ok, nil}
  end

  defp rule(select, calendar) do
    parts(select, calendar)
  end

  # ── A step of a pipeline ──────────────────────────────────────────────

  @doc "The expression a step is given: an expression, or the result of the step before, whose error passes through."
  @spec expression(term()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def expression(%Tempo{} = expression), do: {:ok, expression}
  def expression({:ok, %Tempo{} = expression}), do: {:ok, expression}
  def expression({:error, %_{__exception__: true}} = error), do: error

  def expression(other),
    do: {:error, ConversionError.exception(value: other, reason: :not_an_expression)}

  @doc """
  An expression with more selected in it: a recurrence's rule, or a value's
  selection, with the parts added. A unit the expression already selects is
  refused, as two values for one unit say neither.
  """
  @spec selecting(Tempo.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def selecting(%Tempo{form: {:every, first, bound, rule}} = recurrence, parts) do
    with {:ok, rule} <- merged(rule || [], parts, recurrence.calendar),
         do: Validate.run(%{recurrence | form: {:every, first, bound, rule}})
  end

  def selecting(%Tempo{form: {:value, units}} = value, parts) do
    {held, coarser} = Keyword.pop(units, :selection, [])

    with {:ok, selection} <- merged(held, parts, value.calendar),
         do: Validate.run(%{value | form: {:value, coarser ++ [selection: selection]}})
  end

  def selecting(%Tempo{form: {kind, members}} = set, parts)
      when kind in [:all, :one] and is_list(members) do
    with {:ok, members} <- each_member(members, &selecting(&1, parts)),
         do: Validate.run(%{set | form: {kind, members}})
  end

  def selecting(%Tempo{} = other, _parts),
    do:
      {:error,
       argument(
         "a selection refines a value, a recurrence or a set of them, not #{inspect(other)}; " <>
           "select in an interval with Tempo.select/3"
       )}

  @doc """
  An expression whose selection becomes the start of a window: what it
  selects is nested (`L…N`), the window is its length, and what is selected
  after it is selected in the window (`LL12M25D7KN/P8D1K-1IN`, the last
  Monday in the eight days from a Sunday the 25th of December).
  """
  @spec nesting(Tempo.t(), Duration.t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def nesting(%Tempo{form: {:every, _first, _bound, nil}} = recurrence, _window),
    do: {:error, nothing_selected(recurrence)}

  def nesting(%Tempo{form: {:every, first, bound, rule}} = recurrence, %Duration{} = window),
    do:
      Validate.run(%{
        recurrence
        | form: {:every, first, bound, [selection: rule, window: window]}
      })

  def nesting(%Tempo{form: {:value, units}} = value, %Duration{} = window) do
    case Keyword.pop(units, :selection) do
      {nil, _units} ->
        {:error, nothing_selected(value)}

      {held, coarser} ->
        Validate.run(%{
          value
          | form: {:value, coarser ++ [selection: [selection: held, window: window]]}
        })
    end
  end

  def nesting(%Tempo{form: {kind, members}} = set, %Duration{} = window)
      when kind in [:all, :one] and is_list(members) do
    with {:ok, members} <- each_member(members, &nesting(&1, window)),
         do: Validate.run(%{set | form: {kind, members}})
  end

  def nesting(%Tempo{} = other, %Duration{}), do: {:error, nothing_selected(other)}

  defp nothing_selected(expression),
    do:
      argument(
        "a window is counted from what an expression selects, and #{inspect(expression)} selects nothing yet"
      )

  # A time of day given to a selection with a position is a time on each day
  # it selects: the selection is closed (`LL{1..5}K-1INT9HN`, nine o'clock of
  # the last weekday), where merged the position would count among the times.
  defp merged(held, parts, calendar) do
    if Keyword.has_key?(held, :instance) and Enum.all?(Keyword.keys(parts), &(&1 in @clock)),
      do: merged_parts([selection: held], parts, calendar),
      else: merged_parts(held, parts, calendar)
  end

  defp merged_parts(held, parts, calendar) do
    case Enum.find(Keyword.keys(parts), &Keyword.has_key?(held, &1)) do
      nil ->
        parts(held ++ parts, calendar)

      unit ->
        {:error,
         argument("#{inspect(unit)} is already selected (#{inspect(Keyword.get(held, unit))})")}
    end
  end

  # A set's exclusions are kept as they are; its members are refined.
  defp each_member(members, fun) do
    Enum.reduce_while(members, {:ok, []}, fn
      {:except, _} = out, {:ok, acc} ->
        {:cont, {:ok, acc ++ [out]}}

      member, {:ok, acc} ->
        case fun.(member) do
          {:ok, refined} -> {:cont, {:ok, acc ++ [refined]}}
          {:error, _} = error -> {:halt, error}
        end
    end)
  end

  @doc """
  A recurrence as the cadence and the options `every/2` builds it from, so a
  step that changes its start, its end or its count builds it again.
  """
  @spec every_options(Tempo.t()) :: {Duration.t(), keyword()}
  def every_options(%Tempo{form: {:every, first, bound, rule}} = recurrence) do
    {cadence, start} = start_options(first, recurrence)

    {cadence,
     start ++ bound_options(bound) ++ rule_options(rule) ++ [metadata: recurrence.metadata]}
  end

  defp start_options(%Tempo{form: {:span, %Duration{} = cadence, to}}, _r),
    do: {cadence, [to: to]}

  defp start_options(%Tempo{form: {:span, :open, cadence}}, r),
    do: {cadence, [calendar: r.calendar]}

  defp start_options(
         %Tempo{form: {:span, %Tempo{form: {:when, every_year, years: filter}}, cadence}},
         r
       )
       when every_year.form == {:span, :open, :open},
       do: {cadence, [calendar: r.calendar, years: filter]}

  defp start_options(
         %Tempo{form: {:span, %Tempo{form: {:when, domain, years: filter}}, cadence}},
         _r
       ),
       do: {cadence, [from: domain, years: filter]}

  defp start_options(%Tempo{form: {:span, from, cadence}}, _r), do: {cadence, [from: from]}

  defp bound_options(:infinity), do: []
  defp bound_options(count) when is_integer(count), do: [count: count]
  defp bound_options(%Tempo{} = until), do: [until: until]

  defp rule_options(nil), do: []
  defp rule_options(rule), do: [select: rule]

  # ── A value's shapes ──────────────────────────────────────────────────

  @doc """
  A value marked as ISO 8601-2's `?` and `~` mark one: every unit it has
  where `units` is `:all`, as a mark after the value does, or the units
  named, as a mark on each does. A unit marked both ways is `:both` (`%`).
  A set's members are each marked; an interval's ends are marked before
  they are joined.
  """
  @spec qualifying(Tempo.t(), :uncertain | :approximate, :all | [Tempo.unit()]) ::
          {:ok, Tempo.t()} | {:error, Exception.t()}
  def qualifying(%Tempo{form: {:value, units}} = value, mark, :all),
    do: qualifying(value, mark, for({unit, _} <- units, unit != :selection, do: unit))

  def qualifying(%Tempo{form: {:value, units}} = value, mark, named) when is_list(named) do
    case Enum.reject(named, &Keyword.has_key?(units, &1)) do
      [] ->
        marks =
          Enum.reduce(
            named,
            value.qualifications || %{},
            &Map.update(&2, &1, mark, fn held -> both(held, mark) end)
          )

        Validate.run(%{value | qualifications: marks})

      missing ->
        {:error, argument("#{inspect(value)} has no #{inspect(missing)} to mark")}
    end
  end

  def qualifying(%Tempo{form: {kind, members}} = set, mark, units)
      when kind in [:all, :one] and is_list(members) do
    with {:ok, members} <- each_member(members, &qualifying(&1, mark, units)),
         do: Validate.run(%{set | form: {kind, members}})
  end

  def qualifying(%Tempo{form: {:span, _from, _to}} = interval, _mark, _units),
    do:
      {:error,
       argument(
         "an interval's marks are on its ends: mark each value before joining them, not #{inspect(interval)}"
       )}

  def qualifying(%Tempo{} = other, _mark, _units),
    do: {:error, argument("a value or a set of them is marked, not #{inspect(other)}")}

  defp both(mark, mark), do: mark
  defp both(_held, _mark), do: :both

  @doc """
  A value with a group in it, as `nGkUU` writes one: the nth group of a
  length of a unit, counted in the units before it (`2026Y2G3MU`, the
  second three months of 2026).
  """
  @spec grouping(Tempo.t(), term(), [{Tempo.unit(), pos_integer()}]) ::
          {:ok, Tempo.t()} | {:error, Exception.t()}
  def grouping(%Tempo{form: {:value, units}} = value, nth, [{unit, size}])
      when is_integer(size) and size > 0 do
    with {:ok, nth} <- nth_held(nth),
         {:ok, units} <- Unit.ordered(units ++ [group: {nth, [{unit, size}]}]),
         do: Validate.run(%{value | form: {:value, units}})
  end

  def grouping(%Tempo{form: {kind, members}} = set, nth, length)
      when kind in [:all, :one] and is_list(members) do
    with {:ok, members} <- each_member(members, &grouping(&1, nth, length)),
         do: Validate.run(%{set | form: {kind, members}})
  end

  def grouping(%Tempo{form: {:value, _}}, _nth, length),
    do: {:error, argument("a group's length is one unit and its count, not #{inspect(length)}")}

  def grouping(%Tempo{} = other, _nth, _length),
    do: {:error, argument("a value or a set of them has groups, not #{inspect(other)}")}

  defp nth_held(nth) when is_integer(nth) and nth > 0, do: {:ok, nth}
  defp nth_held(%Range{} = nth), do: {:ok, [nth]}

  defp nth_held([_ | _] = nth) do
    if Enum.all?(nth, &((is_integer(&1) and &1 > 0) or is_struct(&1, Range))),
      do: {:ok, nth},
      else: {:error, argument("a group is counted from 1, not #{inspect(nth)}")}
  end

  defp nth_held(other), do: {:error, argument("a group is counted from 1, not #{inspect(other)}")}

  @doc """
  A value with a unit it leaves unspecified, as `X*` writes one: some day
  of June 2026 is `2026Y6MX*D`.
  """
  @spec unspecifying(Tempo.t(), Tempo.unit()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def unspecifying(%Tempo{form: {:value, units}} = value, unit) when is_atom(unit) do
    with {:ok, units} <- Unit.ordered(units ++ [{unit, :any}]),
         do: Validate.run(%{value | form: {:value, units}})
  end

  def unspecifying(%Tempo{form: {kind, members}} = set, unit)
      when kind in [:all, :one] and is_list(members) do
    with {:ok, members} <- each_member(members, &unspecifying(&1, unit)),
         do: Validate.run(%{set | form: {kind, members}})
  end

  def unspecifying(%Tempo{} = other, unit),
    do:
      {:error,
       argument("a value or a set of them has some #{inspect(unit)}, not #{inspect(other)}")}

  # ── A domain's calendar ───────────────────────────────────────────────

  @doc """
  A domain of years read in another calendar: the same year numbers, each a
  year of `calendar`, as the years of a rule are those of the calendar
  written after it.
  """
  @spec years_in(Tempo.t(), Calendar.calendar()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def years_in(%Tempo{form: {:all, members}} = domain, calendar) when is_list(members) do
    with {:ok, members} <- each_member(members, &years_in(&1, calendar)) do
      members =
        Enum.map(members, fn
          {:except, value} -> {:except, %{value | calendar: calendar}}
          member -> member
        end)

      Validate.run(%{domain | form: {:all, members}, calendar: calendar})
    end
  end

  def years_in(%Tempo{form: {:value, _}} = year, calendar),
    do: Validate.run(%{year | calendar: calendar})

  def years_in(%Tempo{form: {:span, from, to}} = span, calendar) do
    with {:ok, from} <- an_end_in(from, calendar),
         {:ok, to} <- an_end_in(to, calendar),
         do: Validate.run(%{span | form: {:span, from, to}, calendar: calendar})
  end

  def years_in(%Tempo{} = other, _calendar),
    do: {:error, argument("a domain is of years, not #{inspect(other)}")}

  defp an_end_in(%Tempo{} = value, calendar), do: years_in(value, calendar)
  defp an_end_in(open, _calendar), do: {:ok, open}

  # ── A zone ────────────────────────────────────────────────────────────

  @doc """
  A floating expression placed in a zone, its readings unchanged: every value
  in it carries the zone, as the reader gives a suffix's zone to each.
  """
  @spec in_zone(Tempo.t(), Tempo.Zone.t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def in_zone(%Tempo{} = expression, %Tempo.Zone{} = zone) do
    with :ok <- Spans.whole(expression),
         :ok <- floating(expression),
         do: Validate.run(rezoned(expression, zone))
  end

  defp floating(%Tempo{} = expression) do
    if Spans.frame(expression) == :utc,
      do: {:error, FrameError.exception(a: expression, b: nil, reason: :zoned)},
      else: :ok
  end

  defp rezoned(%Tempo{form: form} = expression, zone) do
    %{expression | zone: zone, form: rezoned_form(form, zone)}
  end

  defp rezoned_form({:value, _} = form, _zone), do: form

  defp rezoned_form({:span, from, to}, zone),
    do: {:span, rezoned_end(from, zone), rezoned_end(to, zone)}

  defp rezoned_form({:every, first, bound, rule}, zone),
    do: {:every, rezoned(first, zone), rezoned_end(bound, zone), rule}

  defp rezoned_form({kind, members}, zone) when kind in [:all, :one] and is_list(members),
    do: {kind, Enum.map(members, &rezoned_end(&1, zone))}

  defp rezoned_form(form, _zone), do: form

  defp rezoned_end(%Tempo{} = value, zone), do: rezoned(value, zone)
  defp rezoned_end(other, _zone), do: other

  # ── A one-of set ──────────────────────────────────────────────────────

  @doc "A set one of whose members is meant."
  @spec one_of([Tempo.t()]) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def one_of([%Tempo{} = first | _] = members) do
    cond do
      not Enum.all?(members, &is_struct(&1, Tempo)) ->
        {:error, argument("the members of a set are Tempo expressions, not #{inspect(members)}")}

      Enum.any?(members, &(&1.calendar != first.calendar or &1.zone != first.zone)) ->
        {:error, argument("the members of a set are in one calendar and one zone")}

      true ->
        Validate.run(%Tempo{form: {:one, members}, calendar: first.calendar, zone: first.zone})
    end
  end

  def one_of(other),
    do:
      {:error,
       argument("a one-of set has members, each a Tempo expression, not #{inspect(other)}")}

  defp argument(message), do: ArgumentError.exception(message)
end
