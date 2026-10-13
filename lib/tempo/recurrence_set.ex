defmodule Tempo.RecurrenceSet do
  @moduledoc """
  A collection of rules whose occurrences form one set: a territory's
  public holidays, a calendar's events.

  A recurrence set is a `t:Tempo.t/0` of the `:all` form, so it goes where
  any expression goes: `Tempo.to_interval/2` gives its occurrences within a
  window, and the set operations take it as an operand. Its members are
  recurrences (`~o"R/../P1Y/FL12M25DN"`), intervals and values, each with
  the metadata its occurrences carry (a holiday's name), and other sets.

  A member may depend on the others. `keep_when/2` keeps a member's
  occurrences only where the days around them fall on other members'
  occurrences (a bridge day), and `move_when/2` moves an occurrence that
  falls on one (to the next Monday, say).

  """

  alias Tempo.IntervalSet
  alias Tempo.Options

  @doc """
  Builds a recurrence set from its members.

  ### Arguments

  * `members` is a list of `t:Tempo.t/0`: recurrences, intervals, values,
    sets, and the conditional members `keep_when/2` and `move_when/2` build.

  * `options` is a keyword list of options.

  ### Options

  * `:metadata` is a map the set carries.

  ### Returns

  * `{:ok, set}`, a `t:Tempo.t/0` of the `:all` form.

  * `{:error, exception}` when the members are of several calendars.

  ### Examples

      iex> {:ok, holidays} = Tempo.RecurrenceSet.new([~o"R/2026-01-01/P1Y/FL12M25DN", ~o"R/2026-01-01/P1Y/FL1M1DN"])
      iex> {:ok, days} = Tempo.to_interval(holidays, within: ~o"2026")
      iex> Tempo.IntervalSet.map(days, &Tempo.month/1)
      [12, 1]

  """
  @spec new([Tempo.t()], keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def new(members, options \\ []), do: IntervalSet.new(members, options)

  @doc """
  `new/2`, returning the set or raising.

  ### Examples

      iex> Tempo.RecurrenceSet.new!([~o"2026-12-25"]) |> Tempo.RecurrenceSet.members() |> length()
      1

  """
  @spec new!([Tempo.t()], keyword()) :: Tempo.t()
  def new!(members, options \\ []), do: IntervalSet.new!(members, options)

  @doc """
  The members of a recurrence set, as they were given.

  ### Examples

      iex> Tempo.RecurrenceSet.members(Tempo.RecurrenceSet.new!([~o"2026-12-25", ~o"2026-01-01"]))
      [~o"2026-12-25", ~o"2026-01-01"]

  """
  @spec members(Tempo.t()) :: [Tempo.t()]
  def members(set), do: IntervalSet.members(set)

  @doc """
  The set with the members a function is truthy for.

  ### Examples

      iex> set = Tempo.RecurrenceSet.new!([Tempo.put_metadata(~o"2026-12-25", %{type: :public}), ~o"2026-01-01"])
      iex> set |> Tempo.RecurrenceSet.filter(&(Tempo.metadata(&1)[:type] == :public)) |> Tempo.RecurrenceSet.members() |> length()
      1

  """
  @spec filter(Tempo.t(), (Tempo.t() -> as_boolean(term()))) :: Tempo.t()
  def filter(set, fun), do: IntervalSet.filter(set, fun)

  @doc """
  A member whose occurrences are kept only when the spans at given offsets
  from each fall on other members' occurrences: a bridge day between two
  holidays.

  ### Arguments

  * `member` is a `t:Tempo.t/0`: a recurrence, an interval or a value.

  * `options` is a keyword list of options.

  ### Options

  * `:at` is a list of `t:Tempo.Duration.t/0` offsets from an occurrence's
    start (`~o"-P1D"` is the day before); every one must fall on an
    occurrence. Required.

  * `:falls_on` is a map another member's occurrence must hold in its
    metadata (`%{type: :public}`), or a `t:Tempo.t/0` whose spans are read
    instead. Required.

  * `:metadata` is a map every occurrence of the member carries.

  ### Returns

  * A `t:Tempo.t/0` of the `:when` form, for a set to hold.

  ### Examples

      iex> bridge = Tempo.RecurrenceSet.keep_when(~o"2026-09-22", at: [~o"-P1D", ~o"P1D"], falls_on: %{type: :public})
      iex> {:ok, holidays} =
      ...>   Tempo.RecurrenceSet.new([
      ...>     Tempo.put_metadata(~o"2026-09-21", %{type: :public}),
      ...>     Tempo.put_metadata(~o"2026-09-23", %{type: :public}),
      ...>     bridge
      ...>   ])
      iex> {:ok, days} = Tempo.to_interval(holidays)
      iex> Tempo.IntervalSet.map(days, &Tempo.day/1)
      [21, 22, 23]

  """
  @spec keep_when(Tempo.t(), keyword()) :: Tempo.t()
  def keep_when(%Tempo{} = member, options) when is_list(options) do
    Options.check!(options, [:at, :falls_on, :metadata], "Tempo.RecurrenceSet.keep_when/2")
    conditional(member, [keep: Keyword.take(options, [:at, :falls_on])], options)
  end

  @doc """
  A member whose occurrence is moved when it falls on another member's
  occurrence: a holiday that gives way to another and is observed on the
  next Thursday.

  ### Arguments

  * `member` is a `t:Tempo.t/0`: a recurrence, an interval or a value.

  * `options` is a keyword list of options.

  ### Options

  * `:falls_on` is as for `keep_when/2`. Required.

  * `:to_next` is a selector for `Tempo.select/3` (`~o"1K"`, Monday): the
    occurrence moves to the first span it gives after the occurrence.
    Required.

  * `:metadata` is a map every occurrence of the member carries.

  ### Returns

  * A `t:Tempo.t/0` of the `:when` form, for a set to hold.

  ### Examples

      iex> moved = Tempo.RecurrenceSet.move_when(~o"2026-04-09", falls_on: %{type: :observance}, to_next: ~o"4K")
      iex> {:ok, holidays} = Tempo.RecurrenceSet.new([Tempo.put_metadata(~o"2026-04-09", %{type: :observance}), moved])
      iex> {:ok, days} = Tempo.to_interval(holidays)
      iex> Tempo.IntervalSet.map(days, &Tempo.day/1)
      [9, 16]

  """
  @spec move_when(Tempo.t(), keyword()) :: Tempo.t()
  def move_when(%Tempo{} = member, options) when is_list(options) do
    Options.check!(options, [:falls_on, :to_next, :metadata], "Tempo.RecurrenceSet.move_when/2")
    conditional(member, [move: Keyword.take(options, [:falls_on, :to_next])], options)
  end

  defp conditional(member, conditions, options) do
    %Tempo{
      form: {:when, member, conditions},
      calendar: member.calendar,
      zone: member.zone,
      metadata: Keyword.get(options, :metadata, %{})
    }
  end
end
