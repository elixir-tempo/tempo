defmodule Tempo.RecurrenceSet do
  @moduledoc """
  A collection of recurrence rules whose occurrences form one interval set.

  A `%Tempo.RecurrenceSet{}` bundles many recurrences — a territory's public
  holidays, a calendar's events — so they compose with any other Tempo value
  through set algebra. Its members are ordinary `%Tempo.Interval{}` values, each
  either a recurrence (`~o"R/../P1Y/FL12M25DN"`) or an already-concrete interval,
  and each may carry `:metadata` (a holiday name, say) that conversion
  preserves on every occurrence it produces. A plain `%Tempo{}` member is a
  concrete value too, standing for its own span (`~o"2026-06-15"` is that day).
  A member may itself be a `%Tempo.RecurrenceSet{}` — a holiday and its observed
  days as one member — whose metadata tags every occurrence its members produce,
  each occurrence keeping its own keys where the two conflict.

  The set's own `:metadata` (the territory a holiday set covers) becomes the
  metadata of the `%Tempo.IntervalSet{}` it converts to.

  A member can depend on the others: `keep_when/2` keeps a member's occurrences
  only when the days around them fall on other members' occurrences (a bridge
  day), and `move_when/2` moves an occurrence that falls on one (to the next
  Monday, say). The set resolves such a `Tempo.RecurrenceSet.Conditional` in a
  second pass over its members' occurrences.

  It completes the triad `%Tempo.Interval{}` (one rule) →
  `%Tempo.RecurrenceSet{}` (many rules) → `%Tempo.IntervalSet{}` (their occurrences).
  Convert it to its occurrences within a window with `Tempo.to_interval_set/2`, or intersect it
  with a concrete set — which supplies the window — and its members' occurrences
  union into one `%Tempo.IntervalSet{}`.

  """

  alias Tempo.ConversionError
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
    sets, each converting to one member, or conditional members built by
    `keep_when/2` and `move_when/2`.

  ### Options

  * `:metadata` is a map of set-level metadata (for example the territory a
    holiday set covers). The default is `%{}`.

  ### Returns

  * `{:ok, set}`.

  * `{:error, reason}` when `members` is not a list of members, a
    conditional member lacks what `keep_when/2` or `move_when/2` needs,
    or an option is not one `new/2` takes.

  ### Examples

      iex> xmas = Tempo.from_iso8601!("R/../P1Y/FL12M25DN")
      iex> new_year = Tempo.from_iso8601!("R/../P1Y/FL1M1DN")
      iex> {:ok, holidays} = Tempo.RecurrenceSet.new([xmas, new_year], metadata: %{territory: :AU})
      iex> {length(Tempo.RecurrenceSet.members(holidays)), Tempo.RecurrenceSet.metadata(holidays)}
      {2, %{territory: :AU}}

      iex> {:error, %Tempo.ConversionError{reason: :recurrence_set_member}} =
      ...>   Tempo.RecurrenceSet.new(["R/../P1Y/FL12M25DN"])

  """
  @spec new([member()], keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(members, options \\ [])

  def new(members, options) when is_list(members) do
    with {:ok, metadata} <- metadata_option(options),
         :ok <- validate_members(members) do
      {:ok, %__MODULE__{members: members, metadata: metadata}}
    end
  end

  def new(members, _options) do
    {:error,
     ArgumentError.exception(
       "Tempo.RecurrenceSet.new/2 takes a list of members, not #{inspect(members)}."
     )}
  end

  @doc """
  Builds a recurrence set from a list of members, raising on an error.

  ### Arguments

  * `members` is a list of members, as for `new/2`.

  ### Options

  * `:metadata` is a map of set-level metadata, as for `new/2`.

  ### Returns

  * A `t:t/0`, or raises the error `new/2` returns.

  ### Examples

      iex> christmas = Tempo.from_iso8601!("R/../P1Y/FL12M25DN")
      iex> Tempo.RecurrenceSet.new!([christmas]) |> Tempo.RecurrenceSet.members()
      [christmas]

  """
  @spec new!([member()], keyword()) :: t()
  def new!(members, options \\ []) do
    case new(members, options) do
      {:ok, set} -> set
      {:error, exception} -> raise exception
    end
  end

  defp metadata_option(options) do
    with true <- Keyword.keyword?(options),
         [] <- Keyword.keys(options) -- [:metadata],
         metadata when is_map(metadata) <- Keyword.get(options, :metadata, %{}) do
      {:ok, metadata}
    else
      _invalid ->
        {:error,
         ArgumentError.exception(
           "Tempo.RecurrenceSet.new/2 takes one option, :metadata, a map, not " <>
             "#{inspect(options)}."
         )}
    end
  end

  defp validate_members(members) do
    case Enum.find_value(members, &member_error/1) do
      nil -> :ok
      error -> {:error, error}
    end
  end

  # The error for a member a set cannot hold, or `nil`: a set holds
  # intervals (recurrences or concrete), values, nested sets and
  # conditional members, and a conditional names what it needs.
  defp member_error(%Tempo.Interval{}), do: nil
  defp member_error(%Tempo{}), do: nil
  defp member_error(%__MODULE__{}), do: nil

  defp member_error(%Conditional{member: member} = conditional) do
    if Conditional.valid?(conditional) do
      member_error(member)
    else
      ConversionError.exception(value: conditional, reason: :conditional_member)
    end
  end

  defp member_error(member),
    do: ConversionError.exception(value: member, reason: :recurrence_set_member)

  @doc """
  Returns the set's members, in the order they were given.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * The list of members: recurrences, concrete intervals, `t:Tempo.t/0` values
    and nested sets.

  ### Examples

      iex> christmas = Tempo.from_iso8601!("R/../P1Y/FL12M25DN")
      iex> {:ok, holidays} = Tempo.RecurrenceSet.new([christmas])
      iex> Tempo.RecurrenceSet.members(holidays)
      [christmas]

  """
  @spec members(t()) :: [member()]
  def members(%__MODULE__{members: members}), do: members

  @doc """
  Keeps only the members for which `fun` returns a truthy value, as
  `Tempo.IntervalSet.filter/2` does for an interval set's members.

  ### Arguments

  * `set` is a `t:t/0`.

  * `fun` is a 1-arity function applied to each member: a recurrence or a
    concrete interval, a `t:Tempo.t/0`, a nested set or a conditional member.

  ### Returns

  * A new `t:t/0` holding the members `fun` keeps, in their order, with the
    set's metadata.

  ### Examples

      iex> christmas = Tempo.put_metadata(~o"R/../P1Y/FL12M25DN", %{name: "Christmas Day"})
      iex> boxing_day = Tempo.put_metadata(~o"R/../P1Y/FL12M26DN", %{name: "Boxing Day"})
      iex> {:ok, holidays} = Tempo.RecurrenceSet.new([christmas, boxing_day])
      iex> holidays
      ...> |> Tempo.RecurrenceSet.filter(&(Tempo.metadata(&1).name == "Boxing Day"))
      ...> |> Tempo.RecurrenceSet.members()
      [boxing_day]

  """
  @spec filter(t(), (member() -> as_boolean(any()))) :: t()
  def filter(%__MODULE__{members: members} = set, fun) when is_function(fun, 1) do
    %{set | members: Enum.filter(members, fun)}
  end

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
    metadata for a day to fall on it (`%{type: :public}`), or a recurrence set
    whose occurrences the condition reads instead. Required.

  * `:metadata` is a map tagging every occurrence the member produces. The
    default is `%{}`.

  ### Returns

  * A `t:Tempo.RecurrenceSet.Conditional.t/0`. The set it joins checks the
    options when it converts to its occurrences.

  ### Examples

      iex> citizens_holiday =
      ...>   Tempo.RecurrenceSet.keep_when(~o"R/../P1Y/FL9M22DN",
      ...>     at: [~o"-P1D", ~o"P1D"],
      ...>     falls_on: %{type: :public}
      ...>   )
      iex> {:ok, holidays} =
      ...>   Tempo.RecurrenceSet.new([
      ...>     Tempo.put_metadata(~o"2026-09-21", %{type: :public}),
      ...>     Tempo.put_metadata(~o"2026-09-23", %{type: :public}),
      ...>     citizens_holiday
      ...>   ])
      iex> {:ok, set} = Tempo.to_interval_set(holidays, within: ~o"2026Y9M")
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
    metadata for an occurrence to fall on it (`%{type: :public}`), or a
    recurrence set whose occurrences the condition reads instead. Required.

  * `:to_next` is a selector (`~o"1K"`, Monday): a moved occurrence goes to the
    first span `Tempo.select/2` gives for it after the occurrence. Required.

  * `:metadata` is a map tagging every occurrence the member produces. The
    default is `%{}`.

  ### Returns

  * A `t:Tempo.RecurrenceSet.Conditional.t/0`. The set it joins checks the
    options when it converts to its occurrences.

  ### Examples

      iex> naefelser_fahrt =
      ...>   Tempo.RecurrenceSet.move_when(~o"2026-04-09",
      ...>     falls_on: %{type: :observance},
      ...>     to_next: ~o"4K"
      ...>   )
      iex> {:ok, holidays} =
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
  converts to carries too.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * The metadata map, `%{}` when none was given.

  ### Examples

      iex> {:ok, holidays} = Tempo.RecurrenceSet.new([], metadata: %{territory: :AU})
      iex> Tempo.RecurrenceSet.metadata(holidays)
      %{territory: :AU}

  """
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{metadata: metadata}), do: metadata
end
