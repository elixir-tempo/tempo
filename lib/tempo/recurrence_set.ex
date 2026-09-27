defmodule Tempo.RecurrenceSet do
  @moduledoc """
  A collection of recurrence rules that materialises as one interval set.

  A `%Tempo.RecurrenceSet{}` bundles many recurrences — a territory's public
  holidays, a calendar's events — so they compose with any other Tempo value
  through set algebra. Its members are ordinary `%Tempo.Interval{}` values, each
  either a recurrence (`~o"R/../P1Y/FL12M25DN"`) or an already-concrete interval,
  and each may carry `:metadata` (a holiday name, say) that materialisation
  preserves on every occurrence it produces. A plain `%Tempo{}` member is a
  concrete value too, standing for its own span (`~o"2026-06-15"` is that day).
  A member may itself be a `%Tempo.RecurrenceSet{}` — a holiday and its observed
  days as one member — whose metadata tags every occurrence its members produce,
  each occurrence keeping its own keys where the two conflict.

  The set's own `:metadata` (the territory a holiday set covers) becomes the
  metadata of the `%Tempo.IntervalSet{}` it materialises to.

  A member can depend on the others: `keep_when/2` keeps a member's occurrences
  only when the days around them fall on other members' occurrences (a bridge
  day), and `move_when/2` moves an occurrence that falls on one (to the next
  Monday, say). The set resolves such a `Tempo.RecurrenceSet.Conditional` in a
  second pass over its members' occurrences.

  It completes the triad `%Tempo.Interval{}` (one rule) →
  `%Tempo.RecurrenceSet{}` (many rules) → `%Tempo.IntervalSet{}` (materialised).
  Materialise it against a window with `Tempo.to_interval_set/2`, or intersect it
  with a concrete set — which supplies the window — and its members' occurrences
  union into one `%Tempo.IntervalSet{}`.

  """

  alias Tempo.RecurrenceSet.Conditional

  @typedoc "A member: a recurrence or concrete interval, a value, a nested set, or a conditional member."
  @type member :: Tempo.Interval.t() | Tempo.t() | t() | Conditional.t()

  @type t :: %__MODULE__{
          members: [member()],
          metadata: map()
        }

  defstruct members: [], metadata: %{}

  @doc """
  Builds a recurrence set from a list of members.

  ### Arguments

  * `members` is a list of `t:Tempo.Interval.t/0` values — each a recurrence or
    a concrete interval, optionally carrying its own `:metadata` — plain
    `t:Tempo.t/0` values, each standing for its own span, nested `t:t/0`
    sets, each materialising as one member, or conditional members built by
    `keep_when/2` and `move_when/2`.

  ### Options

  * `:metadata` is a map of set-level metadata (for example the territory a
    holiday set covers). The default is `%{}`.

  ### Returns

  * A `t:t/0`.

  ### Examples

      iex> xmas = Tempo.from_iso8601!("R/../P1Y/FL12M25DN")
      iex> new_year = Tempo.from_iso8601!("R/../P1Y/FL1M1DN")
      iex> set = Tempo.RecurrenceSet.new([xmas, new_year], metadata: %{territory: :AU})
      iex> {length(Tempo.RecurrenceSet.members(set)), Tempo.RecurrenceSet.metadata(set)}
      {2, %{territory: :AU}}

  """
  @spec new([member()], keyword()) :: t()
  def new(members, options \\ []) when is_list(members) do
    %__MODULE__{members: members, metadata: Keyword.get(options, :metadata, %{})}
  end

  @doc """
  Returns the set's members, in the order they were given.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * The list of members: recurrences, concrete intervals, `t:Tempo.t/0` values
    and nested sets.

  ### Examples

      iex> christmas = Tempo.from_iso8601!("R/../P1Y/FL12M25DN")
      iex> Tempo.RecurrenceSet.new([christmas]) |> Tempo.RecurrenceSet.members()
      [christmas]

  """
  @spec members(t()) :: [member()]
  def members(%__MODULE__{members: members}), do: members

  @doc """
  Builds a member kept only when days around each occurrence fall on
  occurrences of the set's other members — a bridge day between two holidays.

  ### Arguments

  * `member` is a recurrence, a concrete value or a nested set, as `new/2`
    takes.

  ### Options

  * `:at` is a list of `t:Tempo.Duration.t/0` offsets from an occurrence's
    start (`~o"-P1D"` is the day before). Required.

  * `:falls_on` is a map an occurrence of another member must have in its
    metadata for a day to fall on it (`%{type: :public}`). Required.

  * `:metadata` is a map tagging every occurrence the member produces. The
    default is `%{}`.

  ### Returns

  * A `t:Tempo.RecurrenceSet.Conditional.t/0`. The set it joins checks the
    options when it materialises.

  ### Examples

      iex> citizens_holiday =
      ...>   Tempo.RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN",
      ...>     at: [~o"-P1D", ~o"P1D"],
      ...>     falls_on: %{type: :public}
      ...>   )
      iex> holidays =
      ...>   Tempo.RecurrenceSet.new([
      ...>     Tempo.put_metadata(~o"2026-09-21", %{type: :public}),
      ...>     Tempo.put_metadata(~o"2026-09-23", %{type: :public}),
      ...>     citizens_holiday
      ...>   ])
      iex> {:ok, set} = Tempo.to_interval_set(holidays, bound: ~o"2026Y9M")
      iex> Tempo.IntervalSet.count(set)
      3

  """
  @spec keep_when(member(), keyword()) :: Conditional.t()
  def keep_when(member, options) when is_list(options) do
    %Conditional{
      member: member,
      at: Keyword.get(options, :at),
      falls_on: Keyword.get(options, :falls_on),
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  @doc """
  Builds a member whose occurrences move when they fall on occurrences of the
  set's other members — a holiday moved to the next Monday when it lands on
  another.

  ### Arguments

  * `member` is a recurrence, a concrete value or a nested set, as `new/2`
    takes.

  ### Options

  * `:falls_on` is a map an occurrence of another member must have in its
    metadata for an occurrence to fall on it (`%{type: :public}`). Required.

  * `:to_next` is a selector (`~o"1K"`, Monday): a moved occurrence goes to the
    first span `Tempo.select/2` gives for it after the occurrence. Required.

  * `:metadata` is a map tagging every occurrence the member produces. The
    default is `%{}`.

  ### Returns

  * A `t:Tempo.RecurrenceSet.Conditional.t/0`. The set it joins checks the
    options when it materialises.

  ### Examples

      iex> naefelser_fahrt =
      ...>   Tempo.RecurrenceSet.move_when(~o"2026-04-09",
      ...>     falls_on: %{type: :observance},
      ...>     to_next: ~o"4K"
      ...>   )
      iex> holidays =
      ...>   Tempo.RecurrenceSet.new([
      ...>     Tempo.put_metadata(~o"2026-04-09", %{type: :observance}),
      ...>     naefelser_fahrt
      ...>   ])
      iex> {:ok, set} = Tempo.to_interval_set(holidays)
      iex> Tempo.IntervalSet.map(set, &Tempo.day/1)
      [9, 16]

  """
  @spec move_when(member(), keyword()) :: Conditional.t()
  def move_when(member, options) when is_list(options) do
    %Conditional{
      member: member,
      falls_on: Keyword.get(options, :falls_on),
      to_next: Keyword.get(options, :to_next),
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  @doc """
  Returns the set's own metadata, which the `t:Tempo.IntervalSet.t/0` it
  materialises to carries too.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * The metadata map, `%{}` when none was given.

  ### Examples

      iex> Tempo.RecurrenceSet.new([], metadata: %{territory: :AU}) |> Tempo.RecurrenceSet.metadata()
      %{territory: :AU}

  """
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{metadata: metadata}), do: metadata
end
