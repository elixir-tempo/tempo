defmodule Tempo.IntervalSet do
  @moduledoc """
  Interval sets: all of several expressions, `{2026-06,2026-08}`.

  An interval set is the `{:all, members}` form of a `%Tempo{}`. Its
  members are in one calendar (law 5), and enumerating the set yields them
  (law 6). The set operations of `Tempo` return one.

  """

  alias Tempo.IntervalEndpointsError

  @doc """
  Builds a set from its members.

  ### Arguments

  * `members` is a list of expressions, each a `t:Tempo.t/0`, in one calendar.

  * `options` is a keyword list of options.

  ### Options

  * `:metadata` is a map the caller keeps on the set. The default is `%{}`.

  ### Returns

  * `{:ok, set}`, a `t:Tempo.t/0` of the `:all` form.

  * `{:error, %Tempo.IntervalEndpointsError{reason: :calendars}}` when the
    members are in two calendars.

  ### Examples

      iex> Tempo.IntervalSet.new([~o"2026-06", ~o"2026-08"])
      {:ok, ~o"{2026-06,2026-08}"}

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-06-01/2026-06-15", ~o"2026-07"])
      iex> Tempo.IntervalSet.count(set)
      2

  """
  @spec new([Tempo.t()], keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def new(members, options \\ []) when is_list(members) do
    case Enum.uniq(Enum.map(members, & &1.calendar)) do
      [] ->
        {:ok, %Tempo{form: {:all, []}, metadata: Keyword.get(options, :metadata, %{})}}

      [calendar] ->
        {:ok,
         %Tempo{
           form: {:all, members},
           calendar: calendar,
           zone: members |> hd() |> Map.get(:zone),
           metadata: Keyword.get(options, :metadata, %{})
         }}

      _calendars ->
        {:error,
         IntervalEndpointsError.exception(
           from: hd(members),
           to: List.last(members),
           reason: :calendars
         )}
    end
  end

  @doc """
  The members of a set, or of any expression: a singular expression is its
  own one member.

  ### Examples

      iex> Tempo.IntervalSet.members(~o"{2026-06,2026-08}")
      [~o"2026-06", ~o"2026-08"]

      iex> Tempo.IntervalSet.members(~o"2026-06")
      [~o"2026-06"]

  """
  @spec members(Tempo.t()) :: [Tempo.t()]
  def members(%Tempo{form: {:all, members}}) when is_list(members), do: members
  def members(%Tempo{form: {:all, members}}), do: Enum.to_list(members)
  def members(%Tempo{} = expression), do: [expression]

  @doc """
  How many members a set has.

  ### Examples

      iex> Tempo.IntervalSet.count(~o"{2026-06,2026-08}")
      2

  """
  @spec count(Tempo.t()) :: non_neg_integer()
  def count(expression), do: expression |> members() |> length()

  @doc """
  The first member of a set.

  ### Examples

      iex> Tempo.IntervalSet.first(~o"{2026-06,2026-08}")
      ~o"2026-06"

  """
  @spec first(Tempo.t()) :: Tempo.t() | nil
  def first(expression), do: expression |> members() |> List.first()

  @doc """
  The last member of a set.

  ### Examples

      iex> Tempo.IntervalSet.last(~o"{2026-06,2026-08}")
      ~o"2026-08"

  """
  @spec last(Tempo.t()) :: Tempo.t() | nil
  def last(expression), do: expression |> members() |> List.last()
end
