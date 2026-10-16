defmodule Tempo.Workdays do
  @moduledoc """
  A territory's workdays less a set of days off: the days a school or a
  business is open.

  `Tempo.workdays/2` builds one, and it goes wherever a territory does:
  `Tempo.select/3` selects its days, and the workday functions
  (`Tempo.workday?/2`, `Tempo.next_workday/2`, `Tempo.previous_workday/2`,
  `Tempo.nearest_workday/2`, `Tempo.add_workdays/3`,
  `Tempo.roll_to_workday/3`, `Tempo.count_workdays/2`) step over its days
  off as well as its weekend. The weekdays and the weekend are the
  territory's, from CLDR through Localize.

  """

  alias Tempo.Children
  alias Tempo.{ConversionError, Duration, Options, Shift, Spans, Territory}

  @conventions [
    :following,
    :preceding,
    :modified_following,
    :modified_preceding,
    :nearest,
    :modified_nearest
  ]

  @typedoc "ISO days of the week, Monday 1 to Sunday 7."
  @type day_of_week :: 1..7

  @type t :: %__MODULE__{
          territory: atom(),
          weekdays: [day_of_week()],
          weekend: [day_of_week()],
          except: Tempo.t() | nil
        }

  defstruct territory: nil, weekdays: [], weekend: [], except: nil

  @doc """
  The workdays of a territory, less the days off given.

  ### Arguments

  * `territory` is anything `Tempo.Territory.resolve/1` takes (`:US`,
    `"sa"`, a locale such as `"en-GB"`, or `nil` for the configured
    `:default_territory` and then the current locale's), or a `t:t/0`
    already built.

  * `options` is a keyword list of options.

  ### Options

  * `:except` is a `t:Tempo.t/0` with spans, the days off: a set of dates,
    a recurrence, a holiday set.

  ### Returns

  * `{:ok, workdays}`.

  * `{:error, %ArgumentError{}}` for a value that names no territory, an
    option this function does not take, or days off that are not a
    `t:Tempo.t/0`.

  ### Examples

      iex> {:ok, workdays} = Tempo.Workdays.new(:SA)
      iex> workdays.weekdays
      [1, 2, 3, 4, 7]

  """
  @spec new(term(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(territory, options \\ [])

  def new(%__MODULE__{} = workdays, options) do
    with :ok <- Options.check(options, [:except], "Tempo.workdays/2"),
         {:ok, except} <- days_off(Keyword.get(options, :except, workdays.except)) do
      {:ok, %{workdays | except: except}}
    end
  end

  # What `Tempo.workdays/2` answers may be passed on as it is.
  def new({:ok, %__MODULE__{} = workdays}, options), do: new(workdays, options)
  def new({:error, _} = error, _options), do: error

  def new(territory, options) do
    with :ok <- Options.check(options, [:except], "Tempo.workdays/2"),
         {:ok, except} <- days_off(Keyword.get(options, :except)),
         {:ok, territory} <- Territory.resolve(territory) do
      {:ok,
       %__MODULE__{
         territory: territory,
         weekdays: Localize.Calendar.weekdays(territory),
         weekend: Localize.Calendar.weekend(territory),
         except: except
       }}
    end
  end

  @doc """
  `new/2`, returning its answer or raising the error.

  ### Arguments

  * The arguments are those of `new/2`.

  ### Returns

  * What `new/2` returns as `{:ok, answer}`, the answer alone.
    The error it returns as `{:error, exception}` is raised.

  ### Examples

      iex> ~o"2026-06-14/2026-06-20" |> Tempo.select!(Tempo.Workdays.new!(:SA)) |> Tempo.IntervalSet.count()
      5

  """
  @spec new!(term(), keyword()) :: t()
  def new!(territory, options \\ []) do
    case new(territory, options) do
      {:ok, answer} -> answer
      {:error, exception} -> raise exception
    end
  end

  # The days off are an expression with spans, or none.
  defp days_off(nil), do: {:ok, nil}
  defp days_off(%Tempo{} = except), do: {:ok, except}

  defp days_off(other),
    do:
      {:error,
       ArgumentError.exception("the days off (:except) are a Tempo value, not #{inspect(other)}")}

  # Whether a value, a day or finer, falls on a workday: a weekday that is
  # not a day off. CLDR numbers the weekdays and the weekend from Monday, so
  # the value is asked its day so numbered. `Tempo.workday?/2` is the API.
  @doc false
  @spec workday?(Tempo.t(), t()) :: boolean() | {:error, Exception.t()}
  def workday?(%Tempo{} = value, %__MODULE__{} = workdays) do
    case Tempo.day_of_week(value, :monday) do
      day when is_integer(day) -> day in workdays.weekdays and not day_off?(value, workdays)
      nil -> {:error, ConversionError.exception(value: value, reason: :several)}
    end
  end

  # Whether a value, a day or finer, falls on the weekend. `Tempo.weekend?/2`
  # is the API.
  @doc false
  @spec weekend?(Tempo.t(), t()) :: boolean() | {:error, Exception.t()}
  def weekend?(%Tempo{} = value, %__MODULE__{weekend: weekend}) do
    case Tempo.day_of_week(value, :monday) do
      day when is_integer(day) -> day in weekend
      nil -> {:error, ConversionError.exception(value: value, reason: :several)}
    end
  end

  defp day_off?(_value, %__MODULE__{except: nil}), do: false

  defp day_off?(value, %__MODULE__{except: except}) do
    case Tempo.overlaps?(value, except, within: value) do
      true -> true
      _false_or_error -> false
    end
  end

  # The value moved by a number of workdays: forward for a positive count,
  # back for a negative one. `Tempo.add_workdays/3` is the API.
  @doc false
  @spec add(Tempo.t(), integer(), t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def add(%Tempo{} = value, 0, %__MODULE__{}), do: {:ok, value}

  def add(%Tempo{}, count, %__MODULE__{}) when not is_integer(count),
    do:
      {:error,
       ArgumentError.exception("a count of workdays is an integer, not #{inspect(count)}")}

  def add(%Tempo{} = value, count, %__MODULE__{} = workdays) do
    direction = if count > 0, do: 1, else: -1

    Enum.reduce_while(1..abs(count)//1, {:ok, value}, fn _, {:ok, current} ->
      case step(current, direction, workdays) do
        {:ok, moved} -> {:cont, {:ok, moved}}
        error -> {:halt, error}
      end
    end)
  end

  # Whether a value is a workday, or the error for a set with no end.
  defp whole_workday?(value, workdays) do
    with :ok <- Spans.whole(value), do: workday?(value, workdays)
  end

  # The next workday on from a value, a day at a time in one direction.
  @doc false
  @spec step(Tempo.t(), 1 | -1, t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def step(value, direction, workdays) do
    with :ok <- Spans.whole(value),
         {:ok, moved} <- Shift.shift(value, Duration.new!(day: direction)) do
      case workday?(moved, workdays) do
        true -> {:ok, moved}
        false -> step_past(moved, direction, workdays)
        {:error, _} = error -> error
      end
    end
  end

  # A day off within days off that never end in this direction has no
  # workday beyond it, which is an error rather than a walk with no end.
  defp step_past(day, direction, workdays) do
    case off_for_good?(day, direction, workdays) do
      true -> {:error, ConversionError.exception(value: workdays.except, reason: :open)}
      false -> step(day, direction, workdays)
    end
  end

  defp off_for_good?(_day, _direction, %__MODULE__{except: nil}), do: false

  defp off_for_good?(day, direction, %__MODULE__{except: except}) do
    with {:ok, extent} <- Spans.extent(day) do
      except
      |> endless(direction)
      |> Enum.any?(&within_endless?(extent, &1))
    end
  end

  # A day lies in days off open at their end when it begins at or after
  # they do, and in days off open at their start when it ends at or before.
  defp within_endless?({start, _stop}, {from, nil}), do: start >= from
  defp within_endless?({_start, stop}, {nil, to}), do: stop <= to

  @doc false
  # Where the days off leave no workday after them, or nil: the earliest
  # start of days off with no end.
  @spec off_from(t()) :: integer() | nil
  def off_from(%__MODULE__{except: nil}), do: nil

  def off_from(%__MODULE__{except: except}) do
    except |> endless(1) |> Enum.map(&elem(&1, 0)) |> Enum.min(fn -> nil end)
  end

  # The extents of the days off that never end in a direction: a span
  # written with an open end; a recurrence with no rule and no end, whose
  # repetitions follow one another (ISO 8601-1 §3.1.1.11) and so leave no
  # day from its start; or a member of a set that takes nothing out.
  defp endless(%Tempo{form: {:span, _from, :open}} = span, 1), do: extents_of(span)
  defp endless(%Tempo{form: {:span, :open, _to}} = span, -1), do: extents_of(span)

  defp endless(%Tempo{form: {:every, %Tempo{} = first, :infinity, nil}}, 1) do
    case Spans.extent(first) do
      {:ok, {start, _stop}} when is_integer(start) -> [{start, nil}]
      _none -> []
    end
  end

  defp endless(%Tempo{form: {:all, members}} = set, direction) when is_list(members) do
    if Enum.any?(members, &match?({:except, _}, &1)),
      do: [],
      else: Enum.flat_map(members, &endless(%{set | form: &1.form}, direction))
  end

  defp endless(_expression, _direction), do: []

  defp extents_of(span) do
    case Spans.extent(span) do
      {:ok, extent} -> [extent]
      {:error, _} -> []
    end
  end

  # The nearest workday: the value when it is one, else the closer of the
  # next and the previous, the next on a tie. `Tempo.nearest_workday/2` is
  # the API.
  @doc false
  @spec nearest(Tempo.t(), t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def nearest(%Tempo{} = value, %__MODULE__{} = workdays) do
    case whole_workday?(value, workdays) do
      true -> {:ok, value}
      false -> nearest_off(value, workdays)
      {:error, _} = error -> error
    end
  end

  # A day off within days off that never end either way has no workday near it.
  defp nearest_off(value, workdays) do
    case off_for_good?(value, 1, workdays) and off_for_good?(value, -1, workdays) do
      true -> {:error, ConversionError.exception(value: workdays.except, reason: :open)}
      false -> nearest_from(value, workdays, 1)
    end
  end

  defp nearest_from(value, workdays, distance) do
    with {:ok, after_} <- Shift.shift(value, Duration.new!(day: distance)),
         {:ok, before} <- Shift.shift(value, Duration.new!(day: -distance)) do
      cond do
        workday?(after_, workdays) == true -> {:ok, after_}
        workday?(before, workdays) == true -> {:ok, before}
        true -> nearest_from(value, workdays, distance + 1)
      end
    end
  end

  @doc false
  @spec conventions() :: [
          :following
          | :preceding
          | :modified_following
          | :modified_preceding
          | :nearest
          | :modified_nearest,
          ...
        ]
  def conventions, do: @conventions

  # The closer workday of the value's own month: the one after on a tie.
  defp nearest_in_month(value, workdays, distance) do
    with {:ok, after_} <- Shift.shift(value, Duration.new!(day: distance)),
         {:ok, before} <- Shift.shift(value, Duration.new!(day: -distance)) do
      cond do
        workday_of_month?(after_, value, workdays) -> {:ok, after_}
        workday_of_month?(before, value, workdays) -> {:ok, before}
        true -> nearest_in_month(value, workdays, distance + 1)
      end
    end
  end

  defp workday_of_month?(moved, value, workdays),
    do: Tempo.month(moved) == Tempo.month(value) and workday?(moved, workdays) == true

  # A day moved to a workday by a convention. `Tempo.roll_to_workday/3` is
  # the API.
  @doc false
  @spec roll(Tempo.t(), t(), atom()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def roll(%Tempo{} = value, %__MODULE__{} = workdays, convention)
      when convention in @conventions do
    case whole_workday?(value, workdays) do
      true -> {:ok, value}
      false -> rolled(value, workdays, convention)
      {:error, _} = error -> error
    end
  end

  def roll(_value, _workdays, convention) do
    {:error,
     ArgumentError.exception(
       "the :roll convention is one of #{inspect(@conventions)}, not #{inspect(convention)}"
     )}
  end

  defp rolled(value, workdays, :following), do: step(value, 1, workdays)
  defp rolled(value, workdays, :preceding), do: step(value, -1, workdays)

  defp rolled(value, workdays, :nearest), do: nearest_off(value, workdays)
  defp rolled(value, workdays, :modified_nearest), do: nearest_in_month(value, workdays, 1)

  defp rolled(value, workdays, :modified_following) do
    with {:ok, moved} <- step(value, 1, workdays),
         do:
           if(Tempo.month(moved) == Tempo.month(value),
             do: {:ok, moved},
             else: step(value, -1, workdays)
           )
  end

  defp rolled(value, workdays, :modified_preceding) do
    with {:ok, moved} <- step(value, -1, workdays),
         do:
           if(Tempo.month(moved) == Tempo.month(value),
             do: {:ok, moved},
             else: step(value, 1, workdays)
           )
  end

  # How many workdays an expression's days hold. `Tempo.count_workdays/2` is
  # the API.
  @doc false
  @spec count(Tempo.t(), t()) :: {:ok, non_neg_integer()} | {:error, Exception.t()}
  def count(%Tempo{} = expression, %__MODULE__{} = workdays) do
    with :ok <- ended(expression),
         {:ok, days} <- Children.walk(expression, :day, []) do
      {:ok, Enum.count(days, &(workday?(&1, workdays) == true))}
    end
  end

  # Days are counted as they are walked, so any number of them is counted;
  # an expression with no end has no count.
  defp ended(expression) do
    if Tempo.bounded?(expression),
      do: :ok,
      else: {:error, ConversionError.exception(value: expression, reason: :unbounded)}
  end
end
