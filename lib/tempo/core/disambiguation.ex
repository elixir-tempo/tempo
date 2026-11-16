defmodule Tempo.Disambiguation do
  @moduledoc false

  # A reading with no time shift in a named zone whose clock skips it (02:30
  # as New York springs forward) or shows it twice (01:30 as it falls back),
  # resolved as the caller says (decision 109), as Temporal's
  # `disambiguation` option does:
  #
  # * `:compatible` reads a skipped reading after the change, by its length
  #   (02:30 is 03:30), and a repeated one at its first showing.
  #
  # * `:earlier` reads a skipped reading before the change (02:30 is 01:30),
  #   and a repeated one at its first showing.
  #
  # * `:later` reads a skipped reading after the change, and a repeated one
  #   at its second showing.
  #
  # * `:reject` refuses both.
  #
  # With none given (`nil`) a skipped reading is refused and a repeated one
  # is its first showing, as a reading always was. A value coarser than a
  # day, or one only part of which the clock skips, is a period the clock
  # runs through and is left as it is.

  alias Tempo.Offset
  alias Tempo.Spans
  alias Tempo.Zone
  alias Tempo.ZoneError

  @modes [:compatible, :earlier, :later, :reject]

  @doc "The ways a caller may resolve a reading its zone's clock skips or shows twice."
  @spec modes() :: [atom(), ...]
  def modes do
    @modes
  end

  @doc """
  An expression with each reading its zone's clock skips or shows twice
  resolved as `mode` says. With `nil` it is as it was, for validation to
  refuse a skipped reading.
  """
  @spec resolved(Tempo.t() | term(), atom() | nil) ::
          {:ok, Tempo.t() | term()} | {:error, ZoneError.t()}
  def resolved(expression, nil) do
    {:ok, expression}
  end

  def resolved(%Tempo{form: {:value, units}} = value, mode) do
    resolved_value(value, units, mode)
  end

  def resolved(%Tempo{form: {:span, from, to}} = span, mode) do
    with {:ok, from} <- resolved(from, mode),
         {:ok, to} <- resolved(to, mode) do
      {:ok, %{span | form: {:span, from, to}}}
    end
  end

  def resolved(%Tempo{form: {:every, first, bound, rule}} = recurrence, mode) do
    with {:ok, first} <- resolved(first, mode),
         {:ok, bound} <- resolved(bound, mode) do
      {:ok, %{recurrence | form: {:every, first, bound, rule}}}
    end
  end

  def resolved(%Tempo{form: {kind, members}} = set, mode)
      when kind in [:all, :one] and is_list(members) do
    with {:ok, members} <- resolved_members(members, mode) do
      {:ok, %{set | form: {kind, members}}}
    end
  end

  def resolved(%Tempo{form: {:when, member, conditions}} = expression, mode) do
    with {:ok, member} <- resolved(member, mode) do
      {:ok, %{expression | form: {:when, member, conditions}}}
    end
  end

  def resolved(other, _mode) do
    {:ok, other}
  end

  defp resolved_members(members, mode) do
    Enum.reduce_while(members, {:ok, []}, fn member, {:ok, resolved} ->
      case resolved_member(member, mode) do
        {:ok, member} -> {:cont, {:ok, resolved ++ [member]}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
  end

  defp resolved_member({:except, member}, mode) do
    with {:ok, member} <- resolved(member, mode) do
      {:ok, {:except, member}}
    end
  end

  defp resolved_member(member, mode) do
    resolved(member, mode)
  end

  defp resolved_value(%Tempo{zone: %Zone{name: name} = zone, shift: nil} = value, units, mode)
       when is_binary(name) do
    case Offset.wall(units, value) do
      {:ok, {start, stop}} when is_integer(start) and is_integer(stop) ->
        at_wall(value, zone, {start, stop}, mode)

      _period ->
        {:ok, value}
    end
  end

  defp resolved_value(value, _units, _mode) do
    {:ok, value}
  end

  # A reading the clock skips whole is placed by the offset the mode reads
  # it by; one it shows takes the showing the mode chooses.
  defp at_wall(value, zone, {start, stop}, mode) do
    resolution = Zone.resolved_at_wall(zone, start, mode)

    if Zone.skipped?(zone, start) and Zone.skipped?(zone, stop - 1) do
      placed(resolution, value, zone)
    else
      showing(resolution, value, zone)
    end
  end

  defp placed({:ok, moment}, %Tempo{calendar: calendar} = value, zone) do
    moved = Spans.at_position(moment, value, :start, calendar, zone)
    shown = Zone.at_showing(moved, zone, moment)

    {:ok, %{value | form: shown.form, shift: shown.shift}}
  end

  defp placed(_refused, value, _zone) do
    {:ok, value}
  end

  defp showing({:ok, moment}, value, zone) do
    {:ok, Zone.at_showing(value, zone, moment)}
  end

  defp showing({:fold, first, second}, value, zone) do
    offsets = [Zone.shift_of(first), Zone.shift_of(second)]
    {:error, ZoneError.exception(zone: zone.name, reason: :fold, value: value, offsets: offsets)}
  end

  defp showing(_partly_skipped, value, _zone) do
    {:ok, value}
  end
end
