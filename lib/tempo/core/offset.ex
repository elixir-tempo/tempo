defmodule Tempo.Offset do
  @moduledoc false

  # A time shift written beside a zone that does not have it at that reading
  # (RFC 9557 section 3.4): `2020-01-15T12:00-02:00[America/Sao_Paulo]`,
  # written before Brazil dropped daylight saving in 2019, where the zone now
  # gives -03:00. The text says two moments, and is refused unless the caller
  # says which to take (decision 108), as Temporal's `offset` option does:
  #
  # * `:reject`, the default, leaves it for validation to refuse.
  #
  # * `:use` takes the moment the shift gives, read on the zone's clock with
  #   the shift the zone has there (`11:00-03:00`).
  #
  # * `:prefer` keeps a shift the zone has, and drops one it does not, so
  #   the reading is read by the zone (`12:00-03:00`).
  #
  # * `:ignore` drops every shift beside a named zone, so every reading is
  #   read by the zone, at its first showing where it is shown twice.
  #
  # `Z` asserts no local time and is never at odds with a zone.

  alias Tempo.Expand
  alias Tempo.Scale
  alias Tempo.Season
  alias Tempo.Spans
  alias Tempo.Unit
  alias Tempo.Zone

  @modes [:reject, :use, :prefer, :ignore]

  @doc "The ways a caller may resolve a shift at odds with its zone."
  @spec modes() :: [:reject | :use | :prefer | :ignore, ...]
  def modes do
    @modes
  end

  @doc """
  An expression with every shift at odds with its zone resolved as `mode`
  says; under `:reject` it is as it was, for validation to refuse.
  """
  @spec resolved(Tempo.t() | term(), atom()) :: Tempo.t() | term()
  def resolved(expression, :reject) do
    expression
  end

  def resolved(%Tempo{form: {:value, units}} = value, mode) do
    resolved_value(value, units, mode, :start)
  end

  def resolved(%Tempo{form: {:span, from, to}} = span, mode) do
    %{span | form: {:span, resolved(from, mode), resolved_end(to, mode)}}
  end

  def resolved(%Tempo{form: {:every, first, bound, rule}} = recurrence, mode) do
    %{recurrence | form: {:every, resolved(first, mode), resolved_end(bound, mode), rule}}
  end

  def resolved(%Tempo{form: {kind, members}} = set, mode)
      when kind in [:all, :one] and is_list(members) do
    %{set | form: {kind, Enum.map(members, &resolved_member(&1, mode))}}
  end

  def resolved(%Tempo{form: {:when, member, conditions}} = expression, mode) do
    %{expression | form: {:when, resolved(member, mode), conditions}}
  end

  def resolved(other, _mode) do
    other
  end

  defp resolved_end(%Tempo{form: {:value, units}} = value, mode) do
    resolved_value(value, units, mode, :end)
  end

  defp resolved_end(other, mode) do
    resolved(other, mode)
  end

  defp resolved_member({:except, member}, mode) do
    {:except, resolved(member, mode)}
  end

  defp resolved_member(member, mode) do
    resolved(member, mode)
  end

  defp resolved_value(%Tempo{zone: %Zone{}, shift: shift} = value, _units, :ignore, _kind) do
    if Zone.asserted?(shift) do
      %{value | shift: nil}
    else
      value
    end
  end

  defp resolved_value(value, units, mode, kind) do
    case conflict(units, value, kind) do
      {:at_odds, wall_start} -> at_odds(value, wall_start, mode)
      :agrees -> value
    end
  end

  # The moment the shift gives, written to the value's resolution on the
  # zone's clock, with the shift the zone has there so that a reading shown
  # twice keeps the showing the moment is at.
  defp at_odds(%Tempo{zone: zone, shift: shift, calendar: calendar} = value, wall_start, :use) do
    moment = wall_start - Zone.shift_ticks(shift)
    moved = Spans.at_position(moment, value, :start, calendar, zone)

    %{value | form: moved.form, shift: Zone.shift_of(Zone.offset_at_utc(zone, moment))}
  end

  defp at_odds(value, _wall_start, :prefer) do
    %{value | shift: nil}
  end

  @doc """
  Whether a value's shift is one its zone does not have at its reading. A
  value coarser than a day, or with no year, is a period and is not checked.
  As the `:end` of a span, a value written to a clock unit is the boundary
  where the span stops, and may carry the shift of the clock that ran up to
  it: `03:00+02:00` ends the summer hour in Paris as its clock goes back.
  """
  @spec disagrees?(Unit.units(), Tempo.t(), :start | :end) :: boolean()
  def disagrees?(units, value, kind) do
    match?({:at_odds, _wall_start}, conflict(units, value, kind))
  end

  defp conflict(units, %Tempo{zone: %Zone{} = zone, shift: shift} = value, kind) do
    if Zone.asserted?(shift) do
      checked =
        if kind == :end and Spans.clock_unit?(Unit.resolution(units)), do: :boundary, else: :span

      conflict_at(wall(units, value), zone, Zone.shift_ticks(shift), checked)
    else
      :agrees
    end
  end

  defp conflict(_units, _value, _kind) do
    :agrees
  end

  defp conflict_at({:ok, {start, stop}}, zone, offset, :span)
       when is_integer(start) and is_integer(stop) do
    agreed(start, [start - offset, stop - 1 - offset], zone, offset)
  end

  # An end is also at one with the clock that ran up to it.
  defp conflict_at({:ok, {start, stop}}, zone, offset, :boundary)
       when is_integer(start) and is_integer(stop) do
    agreed(start, [start - offset - 1, start - offset, stop - 1 - offset], zone, offset)
  end

  defp conflict_at(_no_position, _zone, _offset, _checked) do
    :agrees
  end

  # A shift agrees with its zone where the zone has it at one of the moments.
  defp agreed(wall_start, moments, zone, offset) do
    if Enum.any?(moments, &(Zone.offset_at_utc(zone, &1) == offset)) do
      :agrees
    else
      {:at_odds, wall_start}
    end
  end

  @doc """
  The span a value's reading covers on no zone's clock, what its shift and
  its zone are each held to; `:skip` for a value coarser than a day, or with
  no year, which is a period the clock runs through.
  """
  @spec wall(Unit.units(), Tempo.t()) ::
          {:ok, {Scale.position(), Scale.position()}} | {:error, term()} | :skip
  def wall(units, %Tempo{calendar: calendar}) do
    if checkable?(units) do
      Expand.extent(units, %{calendar: calendar, zone: nil, shift: nil})
    else
      :skip
    end
  end

  defp checkable?(units) do
    Unit.concrete?(units) and Keyword.has_key?(units, :year) and
      not Keyword.has_key?(units, :selection) and
      not Season.abstract?(Keyword.get(units, :season)) and
      Unit.compare(Unit.grain(Unit.resolution(units)), :day) != :lt
  end
end
