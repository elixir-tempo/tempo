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

  alias Tempo.{ConversionError, Duration, Options, Shift, Spans, Territory}

  @conventions [:following, :preceding, :modified_following, :modified_preceding]

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

  * `{:error, %ArgumentError{}}` for a value that names no territory.

  ### Examples

      iex> {:ok, workdays} = Tempo.Workdays.new(:SA)
      iex> workdays.weekdays
      [1, 2, 3, 4, 7]

  """
  @spec new(term(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(territory, options \\ [])

  def new(%__MODULE__{} = workdays, options),
    do: {:ok, %{workdays | except: Keyword.get(options, :except, workdays.except)}}

  # What `Tempo.workdays/2` answers may be passed on as it is.
  def new({:ok, %__MODULE__{} = workdays}, options), do: new(workdays, options)
  def new({:error, _} = error, _options), do: error

  def new(territory, options) do
    with :ok <- Options.check(options, [:except], "Tempo.workdays/2"),
         {:ok, territory} <- Territory.resolve(territory) do
      {:ok,
       %__MODULE__{
         territory: territory,
         weekdays: Localize.Calendar.weekdays(territory),
         weekend: Localize.Calendar.weekend(territory),
         except: Keyword.get(options, :except)
       }}
    end
  end

  @doc "Whether a value, a day or finer, falls on a workday: a weekday that is not a day off."
  @spec workday?(Tempo.t(), t()) :: boolean() | {:error, Exception.t()}
  def workday?(%Tempo{} = value, %__MODULE__{} = workdays) do
    case Tempo.day_of_week(value) do
      day when is_integer(day) -> day in workdays.weekdays and not day_off?(value, workdays)
      nil -> {:error, ConversionError.exception(value: value, reason: :several)}
    end
  end

  @doc "Whether a value, a day or finer, falls on the weekend."
  @spec weekend?(Tempo.t(), t()) :: boolean() | {:error, Exception.t()}
  def weekend?(%Tempo{} = value, %__MODULE__{weekend: weekend}) do
    case Tempo.day_of_week(value) do
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

  @doc "The value moved by a number of workdays: forward for a positive count, back for a negative one."
  @spec add(Tempo.t(), integer(), t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def add(%Tempo{} = value, 0, %__MODULE__{}), do: {:ok, value}

  def add(%Tempo{} = value, count, %__MODULE__{} = workdays) when is_integer(count) do
    direction = if count > 0, do: 1, else: -1

    Enum.reduce_while(1..abs(count)//1, {:ok, value}, fn _, {:ok, current} ->
      case step(current, direction, workdays) do
        {:ok, moved} -> {:cont, {:ok, moved}}
        error -> {:halt, error}
      end
    end)
  end

  # The next workday on from a value, a day at a time in one direction.
  @doc false
  @spec step(Tempo.t(), 1 | -1, t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  # Whether a value is a workday, or the error for a set with no end.
  defp whole_workday?(value, workdays) do
    with :ok <- Spans.whole(value), do: workday?(value, workdays)
  end

  def step(value, direction, workdays) do
    with :ok <- Spans.whole(value),
         {:ok, moved} <- Shift.shift(value, Duration.new!(day: direction)) do
      case workday?(moved, workdays) do
        true -> {:ok, moved}
        false -> step(moved, direction, workdays)
        {:error, _} = error -> error
      end
    end
  end

  @doc "The nearest workday: the value when it is one, else the closer of the next and the previous, the next on a tie."
  @spec nearest(Tempo.t(), t()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def nearest(%Tempo{} = value, %__MODULE__{} = workdays) do
    case whole_workday?(value, workdays) do
      true -> {:ok, value}
      false -> nearest_from(value, workdays, 1)
      {:error, _} = error -> error
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

  @doc """
  A value rolled to a workday by a business day convention: itself when it
  is a workday, else the first workday after it (`:following`) or before it
  (`:preceding`); the modified conventions turn back when the roll would
  leave the month.
  """
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

  @doc "How many workdays an expression's days hold."
  @spec count(Tempo.t(), t()) :: {:ok, non_neg_integer()} | {:error, Exception.t()}
  def count(%Tempo{} = expression, %__MODULE__{} = workdays) do
    with :ok <- ended(expression),
         {:ok, days} <- Spans.walk(expression, :day, []) do
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
