defmodule Tempo.IntervalSet do
  @moduledoc """
  Interval sets: all of several expressions, `{2026-06,2026-08}`.

  An interval set is the `{:all, members}` form of a `%Tempo{}`. Its
  members are in one calendar (law 5), and enumerating the set yields them
  (law 6). The set operations of `Tempo` return one.

  """

  alias Tempo.Algebra
  alias Tempo.Allen
  alias Tempo.Duration
  alias Tempo.Limit
  alias Tempo.Options
  alias Tempo.Shift
  alias Tempo.Spans

  @doc """
  Builds a set from its members.

  ### Arguments

  * `members` is a list of expressions, each a `t:Tempo.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:metadata` is a map the caller keeps on the set. The default is `%{}`.

  * `:except` is a list of `t:Tempo.t/0` the set leaves out of its members,
    as `^` writes them: `{2017Y..,^2020Y}` is every year from 2017 but 2020.
    The default is `[]`.

  ### Returns

  * `{:ok, set}`, a `t:Tempo.t/0` of the `:all` form. A set is one
    expression, in one calendar and one zone: a member of another calendar
    than the first's is converted to it, and where a member is in a named
    zone every zoned member is moved to the first such zone.

  * `{:error, %Tempo.FrameError{}}` when one member is zoned and another has
    no zone: place it with `Tempo.in_zone/2`.

  ### Examples

      iex> Tempo.IntervalSet.new([~o"2026-06", ~o"2026-08"])
      {:ok, ~o"{2026-06,2026-08}"}

      iex> {:ok, from_2017} = Tempo.Interval.new(from: Tempo.new!(year: 2017), to: :open)
      iex> Tempo.IntervalSet.new([from_2017], except: [Tempo.new!(year: 2020)])
      {:ok, ~o"{2017Y..,^2020Y}"}

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-06-01/2026-06-15", ~o"2026-07"])
      iex> Tempo.IntervalSet.count(set)
      2

      iex> Tempo.IntervalSet.new([~o"2026-06-01T09/2026-06-01T10[Europe/London]", ~o"2026-06-01T09/2026-06-01T10[America/New_York]"])
      {:ok, ~o"{2026-06-01T09/2026-06-01T10,2026-06-01T14/2026-06-01T15}[Europe/London]"}

  """
  @spec new([Tempo.t()], keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def new(members, options \\ []) when is_list(members) do
    with :ok <- Options.check(options, [:metadata, :except], "Tempo.IntervalSet.new/2"),
         {:ok, excluded} <- excluded(Keyword.get(options, :except, [])),
         {:ok, set} <-
           Algebra.gathered(members ++ excluded, metadata: Keyword.get(options, :metadata, %{})) do
      {kept, out} = Enum.split(elem(set.form, 1), length(members))
      {:ok, %{set | form: {:all, kept ++ Enum.map(out, &{:except, &1})}}}
    end
  end

  defp excluded(excluded) when is_list(excluded) do
    if Enum.all?(excluded, &is_struct(&1, Tempo)),
      do: {:ok, excluded},
      else:
        {:error,
         ArgumentError.exception(":except is a list of Tempo values, not #{inspect(excluded)}")}
  end

  defp excluded(other),
    do:
      {:error,
       ArgumentError.exception(":except is a list of Tempo values, not #{inspect(other)}")}

  @doc """
  Builds a set as `new/2` does, returning it or raising.

  ### Examples

      iex> Tempo.IntervalSet.new!([~o"2026-01", ~o"2026-03"])
      ~o"{2026-01,2026-03}"

  """
  @spec new!([Tempo.t()], keyword()) :: Tempo.t()
  def new!(members, options \\ []) do
    case new(members, options) do
      {:ok, set} -> set
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Cuts each span an expression has into consecutive slots of a fixed length:
  the bookable windows in a region of free time.

  Within each span, slots of the duration are laid from its start, each
  starting one `:every` after the last, and kept when they fit inside the
  span. Each slot carries its span's metadata. The spans stay distinct: the
  result is not coalesced.

  ### Arguments

  * `expression` is a `t:Tempo.t/0` that has spans: an interval, a set, a
    bounded recurrence or a value.

  * `duration` is the slot length, an exact `t:Tempo.Duration.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:every` is the spacing between slot starts, an exact
    `t:Tempo.Duration.t/0`. The default is the slot length, so slots are
    adjacent; a smaller spacing overlaps them, a larger leaves gaps.

  ### Returns

  * `{:ok, set}`, a `t:Tempo.t/0` of the `:all` form holding the slots in
    order.

  * `{:error, %ArgumentError{}}` when a duration has a month or a year, which
    has no fixed length, and `{:error, exception}` when the expression has no
    spans.

  ### Examples

      iex> work = ~o"2026-06-15T09:00/2026-06-15T12:00"
      iex> {:ok, slots} = Tempo.IntervalSet.slots(work, ~o"PT1H")
      iex> Tempo.IntervalSet.count(slots)
      3

      iex> work = ~o"2026-06-15T09:00/2026-06-15T12:00"
      iex> {:ok, slots} = Tempo.IntervalSet.slots(work, ~o"PT1H", every: ~o"PT30M")
      iex> Tempo.IntervalSet.count(slots)
      5

  """
  @spec slots(Tempo.t(), Duration.t(), keyword()) ::
          {:ok, Tempo.t()} | {:error, Exception.t()}
  def slots(%Tempo{} = expression, %Duration{} = duration, options \\ []) do
    with :ok <- Options.check(options, [:every], "Tempo.IntervalSet.slots/3"),
         {:ok, length} <- Duration.to_microseconds(duration),
         {:ok, step} <- Duration.to_microseconds(Keyword.get(options, :every, duration)),
         :ok <- positive(step, duration),
         {:ok, spans} <- Spans.spans(expression),
         {:ok, slots} <-
           spans
           |> Stream.flat_map(&cut(&1, length, step, duration))
           |> Limit.take(expression) do
      {:ok, %Tempo{form: {:all, slots}, calendar: expression.calendar, zone: expression.zone}}
    end
  end

  defp positive(step, _duration) when step > 0, do: :ok

  defp positive(_step, duration),
    do:
      {:error,
       ArgumentError.exception("the spacing of slots must be positive, not #{inspect(duration)}")}

  defp cut(%Tempo{form: {:span, from, _to}} = span, length, step, duration) do
    case Spans.extent(span) do
      {:ok, {start, stop}} when is_integer(stop) ->
        model = %{
          from
          | form: {:value, Shift.extended_to(elem(from.form, 1), finest(duration), from.calendar)}
        }

        start
        |> Stream.iterate(&(&1 + step))
        |> Stream.take_while(&(&1 + length <= stop))
        |> Enum.map(fn at -> slot(at, at + length, model, span) end)

      _open_or_error ->
        []
    end
  end

  defp finest(%Duration{units: units}) do
    case List.last(units) do
      {:week, _} -> :day
      {unit, _} -> unit
    end
  end

  defp slot(start, stop, model, %Tempo{calendar: calendar, zone: zone} = span) do
    %{
      span
      | form:
          {:span, Spans.at_position(start, model, :start, calendar, zone),
           Spans.at_position(stop, model, :end, calendar, zone)}
    }
  end

  @doc """
  The members of a set merged into the time they cover: touching and
  overlapping members become one span, in order; a result is in canonical
  form, sorted and disjoint with no two members meeting.

  ### Arguments

  * `set` is a `t:Tempo.t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:within` is a `t:Tempo.t/0`, the window an expression with no end of its
    own (a recurrence with no count) or no year is placed in.

  ### Returns

  * `{:ok, set}`, a `t:Tempo.t/0` of the `:all` form.

  * `{:error, exception}` as for `Tempo.union/3`.

  ### Examples

      iex> {:ok, both} = Tempo.union(~o"2026-01", ~o"2026-02")
      iex> Tempo.IntervalSet.coalesce(both)
      {:ok, ~o"{2026-01/2026-02}"}

  """
  @spec coalesce(Tempo.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def coalesce(set, options \\ []), do: covered(set, Keyword.put_new(options, :at_least, 1))

  @doc """
  The time covered by at least so many members of a set at once, as spans.

  ### Arguments

  * `set` is a `t:Tempo.t/0` that has spans.

  * `options` is a keyword list of options.

  ### Options

  * `:at_least` is how many members must cover a time for it to be kept. The
    default is 1.

  * `:within` is a `t:Tempo.t/0`, the window an expression with no end of its
    own (a recurrence with no count) or no year is placed in.

  ### Returns

  * `{:ok, set}`, a `t:Tempo.t/0` of the `:all` form.

  ### Examples

      iex> {:ok, busy} = Tempo.IntervalSet.new([~o"T09/T12", ~o"T11/T14", ~o"T13/T17"])
      iex> Tempo.IntervalSet.covered(busy, at_least: 2)
      {:ok, ~o"{T11/T12,T13/T14}"}

  """
  @spec covered(Tempo.t(), keyword()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def covered(set, options \\ []) do
    with :ok <-
           Options.check(options, [:at_least, :within, :metadata], "Tempo.IntervalSet.covered/2"),
         {:ok, frame, positioned} <- Algebra.positioned(set, options) do
      spans =
        positioned
        |> Algebra.covered(Keyword.get(options, :at_least, 1), frame)
        |> Enum.map(&Algebra.written(&1, frame, options))

      {:ok,
       %Tempo{
         form: {:all, spans},
         calendar: frame.calendar,
         zone: frame.zone,
         metadata: set.metadata
       }}
    end
  end

  @doc """
  Whether a set covers every instant of a value.

  ### Examples

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-01", ~o"2026-03"])
      iex> Tempo.IntervalSet.covered?(set, ~o"2026-01-15")
      true
      iex> Tempo.IntervalSet.covered?(set, ~o"2026-02-15")
      false

  """
  @spec covered?(Tempo.t(), Tempo.t()) :: boolean()
  def covered?(set, value), do: Tempo.within?(value, set)

  @doc """
  Allen's relation of every member of one set to every member of another.

  ### Arguments

  * `a` and `b` are each a `t:Tempo.t/0` that has spans.

  ### Returns

  * `{:ok, rows}`, one row per member of `a`, each a list of the relations to
    the members of `b` in order.

  * `{:error, exception}` as for `Tempo.union/3`.

  ### Examples

      iex> Tempo.IntervalSet.relation_matrix(~o"{2026-01,2026-03}", ~o"{2026-02,2026-03}")
      {:ok, [[:meets, :precedes], [:met_by, :equals]]}

  """
  @spec relation_matrix(Tempo.t(), Tempo.t()) ::
          {:ok, [[Allen.relation()]]} | {:error, Exception.t()}
  def relation_matrix(a, b) do
    with {:ok, _frame, pa, pb} <- Algebra.aligned(a, b, []) do
      {:ok,
       for(
         x <- pa,
         do: for(y <- pb, do: Allen.relation({x.start, x.stop}, {y.start, y.stop}))
       )}
    end
  end

  @doc """
  The members a function keeps.

  ### Arguments

  * `set` is a `t:Tempo.t/0`.

  * `fun` is given each member and answers whether to keep it.

  ### Returns

  * A `t:Tempo.t/0` of the `:all` form. A set whose members are read as
    they are asked for (a selection over a span with no end) is filtered as
    they are read, and has no last member either.

  ### Examples

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-01", ~o"2026-03"])
      iex> Tempo.IntervalSet.filter(set, &Tempo.before?(&1, ~o"2026-02"))
      ~o"{2026-01}"

      iex> {:ok, fifteenths} = Tempo.select(~o"2026-06-01/..", ~o"15D")
      iex> fifteenths |> Tempo.IntervalSet.filter(&(Tempo.month(&1) == 12)) |> Enum.take(2)
      [~o"2026-12-15", ~o"2027-12-15"]

  """
  @spec filter(Tempo.t(), (Tempo.t() -> as_boolean(term()))) :: Tempo.t()
  def filter(%Tempo{form: {:all, members}} = set, fun)
      when is_function(fun, 1) and not is_list(members),
      do: %{set | form: {:all, Stream.filter(members, fun)}}

  def filter(%Tempo{} = set, fun) when is_function(fun, 1),
    do: %{set | form: {:all, Enum.filter(members(set), fun)}}

  @doc """
  A function applied to each member, giving its answers.

  ### Arguments

  * `set` is a `t:Tempo.t/0`.

  * `fun` is given each member.

  ### Returns

  * The list of the function's answers, in the members' order.

  * A stream of them for a set whose members are read as they are asked
    for, which may have no last member.

  ### Examples

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-01", ~o"2026-03"])
      iex> Tempo.IntervalSet.map(set, &Tempo.to_iso8601!/1)
      ["2026Y1M", "2026Y3M"]

      iex> {:ok, fifteenths} = Tempo.select(~o"2026-06-01/..", ~o"15D")
      iex> fifteenths |> Tempo.IntervalSet.map(&Tempo.month/1) |> Enum.take(3)
      [6, 7, 8]

  """
  @spec map(Tempo.t(), (Tempo.t() -> term())) :: [term()] | Enumerable.t()
  def map(%Tempo{form: {:all, members}}, fun) when is_function(fun, 1) and not is_list(members),
    do: Stream.map(members, fun)

  def map(%Tempo{} = set, fun) when is_function(fun, 1), do: Enum.map(members(set), fun)

  @doc """
  The spans of a set's members, lazily and in order: what the set covers,
  member by member.

  ### Examples

      iex> {:ok, set} = Tempo.IntervalSet.new([~o"2026-01", ~o"2026-03"])
      iex> set |> Tempo.IntervalSet.walk() |> Enum.map(&Tempo.to_iso8601!/1)
      ["2026Y1M/2026Y1M", "2026Y3M/2026Y3M"]

  """
  @spec walk(Tempo.t()) :: Enumerable.t()
  def walk(%Tempo{} = set) do
    case Spans.spans(set) do
      {:ok, spans} -> spans
      {:error, exception} -> raise exception
    end
  end

  @doc """
  A set whose members are read from an enumerable as they are asked for, so
  a long or endless source is a set.

  ### Arguments

  * `enumerable` is an `Enumerable` of `t:Tempo.t/0`, in order of start.

  * `options` is a keyword list of options.

  ### Options

  * `:metadata` is the set's own metadata. The default is `%{}`.

  ### Returns

  * A `t:Tempo.t/0` of the `:all` form, whose members are read as they are
    asked for.

  ### Examples

      iex> set = Tempo.IntervalSet.from_stream(Stream.map([~o"2026-01", ~o"2026-03"], & &1))
      iex> Enum.count(set)
      2

  """
  @spec from_stream(Enumerable.t(), keyword()) :: Tempo.t()
  def from_stream(enumerable, options \\ []) do
    Options.check!(options, [:metadata], "Tempo.IntervalSet.from_stream/2")
    %Tempo{form: {:all, enumerable}, metadata: Keyword.get(options, :metadata, %{})}
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

  def members(%Tempo{form: {:all, members}} = set) do
    case Limit.take(members, set) do
      {:ok, taken} -> taken
      {:error, exception} -> raise exception
    end
  end

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
  def first(%Tempo{form: {:all, members}}), do: members |> Enum.take(1) |> List.first()
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
