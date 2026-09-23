defmodule Tempo.RecurrenceSet do
  @moduledoc """
  A collection of recurrence rules that materialises as one interval set.

  A `%Tempo.RecurrenceSet{}` bundles many recurrences — a territory's public
  holidays, a calendar's events — so they compose with any other Tempo value
  through set algebra. Its members are ordinary `%Tempo.Interval{}` values, each
  either a recurrence (`~o"R/../P1Y/FL12M25DN"`) or an already-concrete interval,
  and each may carry `:metadata` (a holiday name, say) that materialisation
  preserves on every occurrence it produces.

  It completes the triad `%Tempo.Interval{}` (one rule) →
  `%Tempo.RecurrenceSet{}` (many rules) → `%Tempo.IntervalSet{}` (materialised).
  Materialise it against a window with `Tempo.to_interval_set/2`, or intersect it
  with a concrete set — which supplies the window — and its members' occurrences
  union into one `%Tempo.IntervalSet{}`.

  """

  @type t :: %__MODULE__{
          members: [Tempo.Interval.t()],
          metadata: map()
        }

  defstruct members: [], metadata: %{}

  @doc """
  Builds a recurrence set from a list of members.

  ### Arguments

  * `members` is a list of `t:Tempo.Interval.t/0` values — each a recurrence or
    a concrete interval, optionally carrying its own `:metadata`.

  ### Options

  * `:metadata` is a map of set-level metadata (for example the territory a
    holiday set covers). The default is `%{}`.

  ### Returns

  * A `t:t/0`.

  ### Examples

      iex> xmas = Tempo.from_iso8601!("R/../P1Y/FL12M25DN")
      iex> new_year = Tempo.from_iso8601!("R/../P1Y/FL1M1DN")
      iex> set = Tempo.RecurrenceSet.new([xmas, new_year], metadata: %{territory: :AU})
      iex> {length(set.members), set.metadata}
      {2, %{territory: :AU}}

  """
  @spec new([Tempo.Interval.t()], keyword()) :: t()
  def new(members, options \\ []) when is_list(members) do
    %__MODULE__{members: members, metadata: Keyword.get(options, :metadata, %{})}
  end
end
