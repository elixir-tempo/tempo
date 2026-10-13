defmodule Tempo.Writer do
  @moduledoc false

  # An expression as ISO 8601 text, in the explicit form Tempo writes
  # (`2026Y6M15DT10H30M`), the inverse of `Tempo.Reader`.
  #
  # A value is written as it was read: its units with what each holds,
  # a part of a second folded into its second, a selection between `L` and
  # `N`, a group as `nGsizeU`. An interval's end drops the leading units it
  # shares with its start (`2026Y6M1D/7M1D`). A qualifier that every unit
  # carries is written once after the value, others between a value and
  # its designator. The zone, the calendar and any tags are written once,
  # after the whole expression, as RFC 9557 writes them (law 5).

  alias Tempo.Duration
  alias Tempo.Iso8601EncodeError
  alias Tempo.Unit
  alias Tempo.Zone

  @designators %{
    century: "C",
    decade: "J",
    year: "Y",
    month: "M",
    traditional_month: "m",
    week: "W",
    day: "D",
    day_of_year: "O",
    day_of_week: "K",
    hour: "H",
    minute: "M",
    second: "S",
    season: "M"
  }

  @qualifier_marks %{uncertain: "?", approximate: "~", both: "%"}

  @doc "An expression or a duration as ISO 8601 text."
  @spec to_iso8601(Tempo.t() | Duration.t()) ::
          {:ok, String.t()} | {:error, Iso8601EncodeError.t()}
  def to_iso8601(%Duration{} = duration), do: {:ok, IO.iodata_to_binary(duration(duration))}

  def to_iso8601(%Tempo{form: {kind, members}} = expression)
      when kind in [:all, :one] and not is_list(members),
      do: {:error, Iso8601EncodeError.exception(value: expression, reason: :lazy_set)}

  def to_iso8601(%Tempo{} = expression) do
    with :ok <- written_conditions(expression),
         :ok <- one_frame(expression),
         {:ok, identifier} <- calendar_identifier(expression) do
      {:ok, IO.iodata_to_binary([body(expression), suffix(expression, identifier)])}
    end
  end

  # A condition that reads the other members of a set (`keep_when`,
  # `move_when`) has no text; a filter of years has.
  defp written_conditions(expression) do
    if Enum.any?([expression | parts(expression)], &unwritten_condition?/1),
      do: {:error, Iso8601EncodeError.exception(value: expression, reason: :conditions)},
      else: :ok
  end

  defp unwritten_condition?(%Tempo{form: {:when, _member, [years: _filter]}}), do: false
  defp unwritten_condition?(%Tempo{form: {:when, _member, _conditions}}), do: true
  defp unwritten_condition?(_part), do: false

  defp calendar_identifier(%Tempo{calendar: calendar} = expression) do
    case Tempo.Calendar.identifier(calendar) do
      {:ok, identifier} ->
        {:ok, identifier}

      {:error, _} ->
        {:error, Iso8601EncodeError.exception(value: expression, reason: {:calendar, calendar})}
    end
  end

  @doc "The text of an expression with no suffix, as a member of a set or an end of an interval is written."
  @spec body(Tempo.t() | Duration.t() | :open) :: iodata()
  def body(:open), do: ".."
  def body(%Duration{} = duration), do: duration(duration)

  def body(%Tempo{form: {:value, units}} = value) do
    [units(units, value.qualifications), shift(value.shift)]
  end

  def body(%Tempo{form: {:span, from, to}}) do
    [body(from), "/", body(abbreviated(to, from))]
  end

  def body(%Tempo{form: {:every, first, bound, rule}}) do
    ["R", count(bound), "/", body(first), until(bound), rule(rule, bound)]
  end

  def body(%Tempo{form: {:all, members}}), do: ["{", members(members), "}"]
  def body(%Tempo{form: {:one, members}}), do: ["[", members(members), "]"]
  def body(%Tempo{form: {:when, member, years: filter}}), do: [body(member), filter(filter)]

  # ── Units ─────────────────────────────────────────────────────────────

  # Each unit as its value and designator, a `T` before the first clock unit,
  # a part of a second folded into its second.
  defp units(units, qualifications) do
    units
    |> fold_fraction()
    |> Enum.map_join("", fn {unit, held} ->
      unit(unit, held, individual_qualifier(units, qualifications, unit))
    end)
    |> then(&[&1, whole_qualifier(units, qualifications)])
  end

  # A qualifier every unit shares is written once, after the value.
  defp whole_qualifier(units, qualifications)
       when is_map(qualifications) and map_size(qualifications) > 0 do
    marks = units |> Enum.map(fn {unit, _} -> Map.get(qualifications, unit) end) |> Enum.uniq()

    case marks do
      [mark] when not is_nil(mark) -> Map.fetch!(@qualifier_marks, mark)
      _ -> ""
    end
  end

  defp whole_qualifier(_units, _qualifications), do: ""

  # The `T` that precedes the clock, placed by `time_designated/1`.
  defp unit(:time, nil, _qualifier), do: "T"

  defp unit(unit, held, qualifier) do
    [value(held, unit), individual(unit, held, qualifier), designator(unit, held)]
  end

  defp individual(_unit, _held, nil), do: ""
  defp individual(:group, _, _), do: ""
  defp individual(:selection, _, _), do: ""
  defp individual(_unit, _held, qualifier), do: Map.fetch!(@qualifier_marks, qualifier)

  defp designator(:group, _), do: ""
  defp designator(:selection, _), do: ""
  defp designator(:quarter, _), do: "M"
  defp designator(unit, _), do: Map.fetch!(@designators, unit)

  # A unit's own mark, unless every unit carries the same one, which is written once after the value.
  defp individual_qualifier(_units, nil, _unit), do: nil

  defp individual_qualifier(units, qualifications, unit) do
    if whole_qualifier(units, qualifications) == "", do: Map.get(qualifications, unit), else: nil
  end

  defp value(held, :quarter) when is_integer(held), do: Integer.to_string(held + 32)

  defp value({nth, duration}, :group) when is_list(duration),
    do: [value(nth, :group), "G", duration_units(duration), "U"]

  defp value(parts, :selection), do: ["L", selection(parts), "N"]

  # A second and its fraction are one number, with one sign.
  defp value({second, {microseconds, precision}}, :second) when is_integer(second) do
    total = second * 1_000_000 + microseconds
    sign = if total < 0, do: "-", else: ""

    [
      sign,
      Integer.to_string(div(abs(total), 1_000_000)),
      ".",
      fraction(rem(abs(total), 1_000_000), precision)
    ]
  end

  defp value({second, {microseconds, precision}}, :second),
    do: [value(second, :second), ".", fraction(microseconds, precision)]

  defp value({month, :leap}, :traditional_month), do: [value(month, :traditional_month), "+"]

  # A fraction of a unit other than the second (ISO 8601-2 §11.4, `PT1.5H`).
  defp value(float, _unit) when is_float(float),
    do: :erlang.float_to_binary(float, [:compact, decimals: 6])

  defp value(integer, _unit) when is_integer(integer), do: Integer.to_string(integer)

  defp value(list, unit) when is_list(list),
    do: ["{", Enum.map_join(list, ",", &value(&1, unit)), "}"]

  defp value(%Range{first: first, last: last, step: 1}, unit),
    do: [value(first, unit), "..", value(last, unit)]

  defp value(%Range{first: first, last: last, step: step}, unit),
    do: [value(first, unit), "..", value(last, unit), "//", Integer.to_string(step)]

  defp value(:any, _unit), do: "X*"
  defp value({:mask, digits}, _unit), do: Enum.map(digits, &mask_digit/1)

  defp value({number, annotations}, unit) when is_list(annotations),
    do: [value(number, unit), annotations(annotations)]

  defp mask_digit(:x), do: "X"
  defp mask_digit(:negative), do: "-"
  defp mask_digit(digit), do: Integer.to_string(digit)

  defp annotations(annotations) do
    [
      case Keyword.get(annotations, :exponent) do
        nil -> ""
        exponent -> ["E", Integer.to_string(exponent)]
      end,
      case Keyword.get(annotations, :significant) do
        nil -> ""
        digits -> ["S", Integer.to_string(digits)]
      end,
      case Keyword.get(annotations, :margin) do
        nil -> ""
        margin -> ["±", Integer.to_string(margin)]
      end
    ]
  end

  # The first clock unit is written after a `T`; a selection writes its own.
  defp fold_fraction(units) do
    units
    |> Enum.reduce([], fn
      {:microsecond, fraction}, [{:second, second} | rest] ->
        [{:second, {second, fraction}} | rest]

      {:microsecond, fraction}, acc ->
        [{:second, {0, fraction}} | acc]

      {unit, held}, acc ->
        [{unit, held} | acc]
    end)
    |> Enum.reverse()
    |> time_designated()
  end

  defp time_designated(units) do
    {before, clock} =
      Enum.split_while(units, fn {unit, held} -> not clock_component?(unit, held) end)

    case clock do
      [] -> before
      _ -> before ++ [{:time, nil} | clock]
    end
  end

  # A group of clock units (`T2GT6HU`) is a clock component and written after T.
  defp clock_component?(:group, {_nth, duration}), do: Unit.clock?(Unit.resolution(duration))
  defp clock_component?(unit, _held), do: Unit.clock?(unit)

  # ── Selections ────────────────────────────────────────────────────────

  defp selection(parts) do
    parts
    |> Enum.map(fn
      {:selection, inner} -> ["L", selection(inner), "N"]
      {:window, duration} -> ["/", duration(duration)]
      {:instance, held} -> [value(held, :instance), "I"]
      {:skip, direction} -> ["(", Atom.to_string(direction), ")s"]
      {:roll, convention} -> ["(", String.replace(Atom.to_string(convention), "_", "-"), ")r"]
      {:event, {name, nil}} -> ["(", name, ")e"]
      {:event, {name, zone}} -> ["(", name, "@", zone, ")e"]
      {unit, held} -> [value(held, unit), Map.fetch!(@designators, unit)]
    end)
    |> time_designated_parts(parts)
  end

  defp time_designated_parts(texts, parts) do
    case Enum.find_index(parts, fn {unit, _} -> Unit.clock?(unit) end) do
      nil -> texts
      index -> List.insert_at(texts, index, "T")
    end
  end

  # ── Shifts, suffix, trailers ──────────────────────────────────────────

  defp shift(nil), do: ""

  defp shift(shift) do
    if Enum.all?(shift, fn {_, value} -> value == 0 end) do
      "Z"
    else
      sign = if Zone.shift_ticks(shift) < 0, do: "-", else: ""

      [
        "Z",
        sign,
        Enum.map(shift, fn {unit, value} ->
          [Integer.to_string(abs(value)), Map.fetch!(@designators, unit)]
        end)
      ]
    end
  end

  defp suffix(%Tempo{} = expression, identifier) do
    [
      zone_suffix(expression.zone),
      calendar_suffix(identifier),
      week_start_suffix(Tempo.Calendar.week_start(expression.calendar)),
      tags_suffix(expression.metadata)
    ]
  end

  defp zone_suffix(nil), do: ""

  defp zone_suffix(%Zone{name: name, critical: critical}) when is_binary(name),
    do: ["[", flag(critical), name, "]"]

  defp zone_suffix(%Zone{offset: minutes, critical: critical}) when is_integer(minutes) do
    sign = if minutes < 0, do: "-", else: "+"
    ["[", flag(critical), sign, two(div(abs(minutes), 60)), ":", two(rem(abs(minutes), 60)), "]"]
  end

  defp flag(true), do: "!"
  defp flag(false), do: ""

  defp two(number), do: String.pad_leading(Integer.to_string(number), 2, "0")

  defp week_start_suffix(nil), do: ""
  defp week_start_suffix(day), do: ["[u-fw=", Tempo.Calendar.week_start_name(day), "]"]

  defp calendar_suffix(nil), do: ""
  defp calendar_suffix(identifier), do: ["[u-ca=", identifier, "]"]

  defp tags_suffix(%{ixdtf_tags: tags}) when is_map(tags) do
    Enum.map(tags, fn {key, values} -> ["[", key, "=", Enum.join(values, "-"), "]"] end)
  end

  defp tags_suffix(_metadata), do: ""

  # ── Intervals, recurrences, sets, durations ───────────────────────────

  # An end drops the leading units it shares with its start, keeping at least one.
  # An end drops the leading units it shares with the start, when the reader
  # would give exactly those back (`Tempo.Unit.inherited/2`).
  # An end drops the leading units it shares with the start down the chain of
  # years, months, days and the clock (ISO 8601-1 §5.5.1), when the two ends
  # agree on their shift; an end on another axis, or with its own shift, is
  # written whole. The reader gives exactly these back (`Tempo.Unit.inherited/2`).
  defp abbreviated(
         %Tempo{form: {:value, to_units}, shift: shift} = to,
         %Tempo{form: {:value, from_units}, shift: shift} = from
       ) do
    shared = shared_prefix(from_units, to_units, nil)

    case {Enum.drop(from_units, shared), Enum.drop(to_units, shared)} do
      {_, []} ->
        to

      {from_rest, [{first, _} | _] = kept} when shared > 0 ->
        shared_units = Enum.take(to_units, shared)

        if same_axis?(from_rest, first) and
             Unit.inherited(from_units, first) == shared_units and
             same_marks?(from, to, Keyword.keys(shared_units)),
           do: %{to | form: {:value, kept}},
           else: to

      _rests ->
        to
    end
  end

  defp abbreviated(to, _from), do: to

  # The ends go on in the same unit after what they share: a week date and a
  # calendar date of one year are written whole.
  defp same_axis?([], _first), do: true
  defp same_axis?([{unit, _} | _], first), do: unit == first

  # The reader gives the inherited units the start's marks, so an end whose
  # shared units are marked otherwise is written whole.
  defp same_marks?(from, to, units),
    do: Map.take(from.qualifications || %{}, units) == Map.take(to.qualifications || %{}, units)

  # A second is not split from its fraction: `T10H30M45.5S/T45.6S`, not `/T0.6S`.
  defp shared_prefix([{:second, held} | _], [{:second, held} | [{:microsecond, _}]], _previous),
    do: 0

  defp shared_prefix([{unit, held} | from], [{unit, held} | to], previous) do
    if chained?(unit, previous), do: 1 + shared_prefix(from, to, unit), else: 0
  end

  defp shared_prefix(_from, _to, _previous), do: 0

  defp chained?(_unit, nil), do: true
  defp chained?(unit, previous), do: Unit.child(previous) == unit

  defp count(count) when is_integer(count), do: Integer.to_string(count)
  defp count(_bound), do: ""

  defp until(%Tempo{} = until), do: ["/", body(until)]
  defp until(_bound), do: ""

  defp rule(nil, _bound), do: ""
  defp rule(parts, _bound), do: ["/F", "L", selection(parts), "N"]

  defp members(members), do: members |> Enum.map(&member/1) |> Enum.intersperse(",")

  defp member({:except, member}), do: ["^", body(member)]

  # A member whose last unit holds one range is written as a range of values (`2020Y..2022Y`).
  defp member(%Tempo{form: {:value, units}} = member) do
    case List.last(units) do
      {unit, [%Range{first: first, last: last, step: 1}]} ->
        shape = Enum.drop(units, -1)

        [
          body(%{member | form: {:value, shape ++ [{unit, first}]}}),
          "..",
          body(%{member | form: {:value, shape ++ [{unit, last}]}})
        ]

      _ ->
        body(member)
    end
  end

  defp member(member), do: body(member)

  defp filter(:even), do: "e"
  defp filter(:odd), do: "o"
  defp filter(:leap), do: "l"
  defp filter(:common), do: "c"

  defp duration(%Duration{units: []}), do: "PT0S"
  defp duration(%Duration{units: units}), do: ["P", duration_units(units)]

  defp duration_units(units) do
    units
    |> fold_fraction()
    |> Enum.map(fn
      {:time, nil} -> "T"
      {unit, held} -> [value(held, unit), Map.fetch!(@designators, unit)]
    end)
  end

  defp fraction(microseconds, precision) do
    microseconds
    |> div(Integer.pow(10, 6 - precision))
    |> Integer.to_string()
    |> String.pad_leading(precision, "0")
  end

  # ── What cannot be written ────────────────────────────────────────────

  # Every part of an expression is in its calendar and its zone (law 5); a
  # struct built by hand with parts in two has no text.
  defp one_frame(%Tempo{} = expression) do
    parts = parts(expression)

    cond do
      Enum.any?(parts, &(&1.calendar != expression.calendar)) ->
        {:error, Iso8601EncodeError.exception(value: expression, reason: :two_calendars)}

      Enum.any?(parts, &(&1.zone != expression.zone)) ->
        {:error, Iso8601EncodeError.exception(value: expression, reason: :two_zones)}

      true ->
        :ok
    end
  end

  defp parts(%Tempo{form: {:value, _}}), do: []

  defp parts(%Tempo{form: {:span, from, to}}),
    do: Enum.filter([from, to], &match?(%Tempo{}, &1)) |> Enum.flat_map(&[&1 | parts(&1)])

  defp parts(%Tempo{form: {:every, first, _, _}}), do: [first | parts(first)]

  defp parts(%Tempo{form: {kind, members}}) when kind in [:all, :one],
    do: Enum.flat_map(members, &member_parts/1)

  defp parts(%Tempo{form: {:when, member, _}}), do: [member | parts(member)]

  defp member_parts({:except, member}), do: [member | parts(member)]
  defp member_parts(%Duration{}), do: []
  defp member_parts(%Tempo{} = member), do: [member | parts(member)]
end
