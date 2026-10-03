defmodule Tempo.Matrix.Census do
  @moduledoc """
  Runs every operation of `Tempo.Matrix.Operations` against every value of
  `Tempo.Matrix.Corpus` and records what each cell does.

  A one-value operation makes one cell for each value. A two-value
  operation makes a cell for the value with itself, and one in each order
  with each of the corpus's partners.

  The consistency checks of `Tempo.Matrix.Checks` are cells too, in the
  group `:consistent`: a check of one value for each value, and a check of
  two for the same pairs the two-value operations run on.

  """

  alias Tempo.Matrix.Checks
  alias Tempo.Matrix.Corpus
  alias Tempo.Matrix.Operations
  alias Tempo.Matrix.Runner

  @type cell :: %{
          operation: String.t(),
          group: atom(),
          raises: Operations.raises(),
          class: atom() | String.t(),
          level: Corpus.level(),
          value: String.t(),
          arguments: String.t(),
          outcome: Runner.outcome(),
          detail: String.t() | nil,
          passes?: boolean()
        }

  @doc """
  Runs the matrix.

  ### Arguments

  * `entries` is the corpus entries to run it on. The default is
    `Tempo.Matrix.Corpus.entries/0`, those of every test run.

  ### Options

  * `:time_limit` is the milliseconds a cell is allowed before it is a
    hang. The default is `Tempo.Matrix.Runner.time_limit/0`.

  ### Returns

  * A list of `t:cell/0`, one for each cell, in no particular order.

  """
  @spec run([Corpus.entry()], keyword()) :: [cell()]
  def run(entries \\ Corpus.entries(), options \\ []) do
    time_limit = Keyword.get(options, :time_limit, Runner.time_limit())
    read = read(entries)
    values = for {entry, {:value, value}} <- read, do: {entry, value}

    cells =
      (unary_cells(values) ++ binary_cells(values) ++ check_cells(values))
      |> Task.async_stream(&run_cell(&1, time_limit),
        max_concurrency: System.schedulers_online(),
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, cell} -> cell end)

    Enum.map(read, &read_cell/1) ++ cells
  end

  # Reading a text is the matrix's first operation, and is held to the
  # contract of the others: a value, or a named error, and no raise. Each is
  # read in a process of its own, so a text the parser raises on is a failing
  # cell and not the end of the run.
  defp read(entries) do
    entries
    |> Task.async_stream(&{&1, read_entry(&1)},
      max_concurrency: System.schedulers_online(),
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, read} -> read end)
  end

  defp read_entry(entry) do
    case Runner.attempt(fn -> Corpus.read(entry) end) do
      {:returned, {:ok, value}} -> {:value, value}
      {:returned, {:error, %{__struct__: module}}} -> {:error, module}
      {:returned, other} -> {:bad_error, inspect(other, limit: 5)}
      {:raised, module} -> {:raised, module}
      :timeout -> :timeout
    end
  end

  defp read_cell({entry, read}) do
    outcome =
      case read do
        {:value, _value} -> :ok
        other -> other
      end

    %{
      operation: "from_iso8601/1",
      group: :parse,
      raises: :never,
      class: entry.class,
      level: entry.level,
      value: label(entry),
      arguments: label(entry),
      outcome: outcome,
      detail: nil,
      passes?: Runner.passes?(outcome, :never)
    }
  end

  @doc """
  The corpus's entries with the values they read as. An entry whose text
  does not parse is left out, and `unread/0` lists it.

  ### Returns

  * A list of `{entry, value}`.

  """
  @spec values([Corpus.entry()]) :: [{Corpus.entry(), term()}]
  def values(entries \\ Corpus.entries()) do
    for {entry, {:value, value}} <- read(entries), do: {entry, value}
  end

  @doc """
  The corpus's hand-written entries whose text does not parse. A generated
  text that does not parse is no value, and is not a failure.

  ### Returns

  * A list of `{entry, read}`, where `read` is what reading the text did:
    `{:error, module}`, `{:raised, module}` or `:timeout`.

  """
  @spec unread() :: [{Corpus.entry(), term()}]
  def unread do
    for {entry, read} <- read(Corpus.written()), not match?({:value, _value}, read) do
      {entry, read}
    end
  end

  @doc """
  The cells that break their operation's contract, as the baseline holds
  them.

  ### Arguments

  * `cells` is what `run/0` returned.

  ### Returns

  * A sorted list of `{operation, arguments, outcome}` strings.

  """
  @spec failures([cell()]) :: [{String.t(), String.t(), String.t()}]
  def failures(cells) do
    cells
    |> Enum.reject(& &1.passes?)
    |> Enum.map(&{&1.operation, &1.arguments, Runner.label(&1.outcome)})
    |> Enum.sort()
  end

  @doc """
  An entry's text, with its calendar when the text does not name it.

  ### Arguments

  * `entry` is a `t:Tempo.Matrix.Corpus.entry/0`.

  ### Returns

  * A string.

  """
  @spec label(Corpus.entry()) :: String.t()
  def label(%{text: text, calendar: nil}), do: text
  def label(%{text: text, calendar: calendar}), do: "#{text} in #{inspect(calendar)}"

  defp unary_cells(values) do
    for {name, group, raises, function} <- Operations.unary(), {entry, value} <- values do
      cell(name, group, raises, entry, label(entry), fn -> function.(value) end)
    end
  end

  defp binary_cells(values) do
    partners = Corpus.partners()

    for {name, group, raises, function} <- Operations.binary(),
        {entry, value} <- values,
        {arguments, cell_function} <-
          pairings(function, label(entry), value, partners_of(entry, value, partners)) do
      cell(name, group, raises, entry, arguments, cell_function)
    end
  end

  # A generated value meets one partner, which keeps the matrix a size that
  # runs with every test run: the first in the value's own frame, since a
  # value with no zone and a zoned one are refused before anything is asked
  # of them.
  defp partners_of(%{level: level}, value, partners) when level in [:generated, :exhaustive] do
    zoned? = zoned?(value)

    case Enum.filter(partners, fn {_text, partner} -> zoned?(partner) == zoned? end) do
      [partner | _rest] -> [partner]
      [] -> Enum.take(partners, 1)
    end
  end

  defp partners_of(_entry, _value, partners), do: partners

  defp zoned?(%Tempo{} = value), do: Tempo.zoned?(value)
  defp zoned?(%Tempo.Interval{from: %Tempo{} = from}), do: Tempo.zoned?(from)
  defp zoned?(_other), do: false

  defp pairings(function, label, value, partners) do
    with_partners =
      Enum.flat_map(partners, fn {partner_text, partner} ->
        [
          {"#{label} | #{partner_text}", fn -> function.(value, partner) end},
          {"#{partner_text} | #{label}", fn -> function.(partner, value) end}
        ]
      end)

    [{"#{label} | #{label}", fn -> function.(value, value) end} | with_partners]
  end

  # A check may end in a raise an operation is allowed, which is the
  # question not arising.
  defp check_cells(values) do
    partners = Corpus.partners()

    unary =
      for {name, check} <- Checks.unary(), {entry, value} <- values do
        cell(name, :consistent, :deliberate, entry, label(entry), fn ->
          {:check, check.(entry, value)}
        end)
      end

    binary =
      for {name, check} <- Checks.binary(),
          {entry, value} <- values,
          {arguments, cell_function} <-
            pairings(check, label(entry), value, partners_of(entry, value, partners)) do
        cell(name, :consistent, :deliberate, entry, arguments, fn ->
          {:check, cell_function.()}
        end)
      end

    unary ++ binary
  end

  defp cell(name, group, raises, entry, arguments, function) do
    %{
      operation: name,
      group: group,
      raises: raises,
      class: entry.class,
      level: entry.level,
      value: label(entry),
      arguments: arguments,
      function: function
    }
  end

  defp run_cell(%{function: function, raises: raises} = cell, time_limit) do
    {outcome, detail} = Runner.detailed(function, time_limit)

    cell
    |> Map.delete(:function)
    |> Map.merge(%{outcome: outcome, detail: detail, passes?: Runner.passes?(outcome, raises)})
  end
end
