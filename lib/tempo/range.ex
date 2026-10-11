defmodule Tempo.Range do
  @moduledoc """
  A pair of Tempo values denoting an inclusive range, produced by the
  ISO 8601-2 range operator (`..`) **inside a set** — `[1667,1670..1672]`
  (one of 1667, 1670, 1671, or 1672) or `{1M2S..1M5S}` (ISO 8601-2 §6.4).
  Both bounds are inclusive — contrast with `%Tempo.Interval{}`, which
  uses the half-open `[from, to)` convention.

  A range is a *member-level* element: it appears inside a
  `t:Tempo.Set.t/0` (and in `~o` sigil match patterns), never as a
  top-level parsed value, and it is not an operand of the interval
  algebra — the enclosing set's own expansion and certainty machinery
  interpret it. Open-ended ranges are represented by `:undefined` on
  either endpoint (`[1760-12..]` — December 1760 or later).

  """

  alias Tempo.Iso8601.AST

  @type endpoint :: Tempo.t() | :undefined

  @type t :: %__MODULE__{
          first: endpoint(),
          last: endpoint()
        }

  defstruct [:first, :last]

  @doc false
  def new(first, last, calendar) do
    first = AST.build(first, calendar)
    last = AST.build(last, calendar)
    %__MODULE__{first: first, last: last}
  end
end
