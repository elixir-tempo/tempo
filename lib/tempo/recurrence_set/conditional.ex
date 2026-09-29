defmodule Tempo.RecurrenceSet.Conditional do
  @moduledoc """
  A recurrence-set member kept or moved by the other members' occurrences.

  Some rules depend on the rest of their set: Japan's Citizens' Holiday is
  22 September only when the days either side are public holidays, and
  Näfelser Fahrt moves to the next Thursday when it falls on an observance. A
  conditional member wraps an ordinary member — a recurrence, a concrete value
  or a nested set — with such a condition, and a `t:Tempo.RecurrenceSet.t/0`
  resolves it when converted, against the occurrences of its other
  members. Build one with `Tempo.RecurrenceSet.keep_when/2` or
  `Tempo.RecurrenceSet.move_when/2`.

  * **Falls on** — a day falls on an occurrence of another member whose
    metadata includes every key and value of `:falls_on`: the day and the
    occurrence overlap. When `:falls_on` is a recurrence set instead, the day
    falls on any of that set's occurrences — the holidays a selection by type
    leaves out of the set, so a kept holiday is still dated by them.

  * **Keep** — an occurrence is kept when every day `:at` away from its start
    falls on such an occurrence, and dropped otherwise.

  * **Move** — an occurrence that falls on such an occurrence moves to the first
    span `Tempo.select/2` gives for `:to_next` after it (searching a week for a
    weekday, a year otherwise); one that does not stays where it is.

  The occurrences a condition reads are every member's own, a conditional's
  unmoved occurrences included and its own never, so an occurrence one
  conditional moves is not seen by another. The member's metadata, and the
  conditional's, tag every occurrence it produces.

  """

  @typedoc "A member a `t:Tempo.RecurrenceSet.t/0` keeps or moves by its other members."
  @type t :: %__MODULE__{
          member: Tempo.Interval.t() | Tempo.t() | Tempo.RecurrenceSet.t(),
          falls_on: map() | Tempo.RecurrenceSet.t(),
          at: [Tempo.Duration.t()] | nil,
          to_next: Tempo.t() | nil,
          metadata: map()
        }

  defstruct [:member, :falls_on, :at, :to_next, metadata: %{}]

  @doc false
  # A conditional names what it falls on and either the offsets it keeps
  # `:at` or the selector it moves `:to_next`, never both.
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{falls_on: falls_on, at: [_ | _] = offsets, to_next: nil}),
    do: falls_on?(falls_on) and Enum.all?(offsets, &match?(%Tempo.Duration{}, &1))

  def valid?(%__MODULE__{falls_on: falls_on, at: nil, to_next: %Tempo{}}), do: falls_on?(falls_on)
  def valid?(_conditional), do: false

  # What a condition falls on: a metadata map the other members' occurrences
  # are matched against, or a recurrence set whose own occurrences it reads.
  defp falls_on?(%Tempo.RecurrenceSet{}), do: true
  defp falls_on?(%_struct{}), do: false
  defp falls_on?(falls_on), do: is_map(falls_on)
end
