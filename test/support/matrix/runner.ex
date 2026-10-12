defmodule Tempo.Matrix.Runner do
  @moduledoc """
  Runs one cell of the matrix and classes what it does.

  A cell is one operation on one value. It runs in a process of its own,
  with a time limit and a heap limit, and the process's exit is read
  rather than rescued: a raise, a hang and a runaway allocation are each
  an outcome like any other.

  """

  # A cell that has not answered in this long is a hang, unless its run
  # allows it longer: the exhaustive corpus holds values of tens of
  # thousands of members, and writing one out takes seconds. The limit tells
  # a hang from an answer, not a slow answer from a quick one: the slowest
  # cells of the default corpus take a third of a second alone and over a
  # second beside fifteen others on sixteen cores, and a CI runner has four
  # slower ones.
  @time_limit 10_000

  # About 400 MB of 64-bit words: a cell that allocates more is killed.
  @heap_limit 50_000_000

  @type outcome ::
          :ok
          | :value
          | {:error, module()}
          | {:bad_error, String.t()}
          | :inspect_error
          | :inside_calendar
          | :mixed_calendars
          | {:raised, module()}
          | :builtin_raise
          | :timeout
          | :killed
          | :consistent
          | :skipped
          | :inconsistent

  @doc """
  Runs `fun` and classes its outcome.

  ### Arguments

  * `fun` is a function of no arguments: the cell.

  ### Returns

  * `:ok` for `{:ok, value}`.

  * `:value` for any other value.

  * `{:error, module}` for `{:error, exception}`.

  * `{:bad_error, description}` for an error that carries no exception.

  * `:inspect_error` for text holding an `#Inspect.Error`.

  * `:inside_calendar` for an answer, an error or a raise that holds or
    names the module Tempo works with in place of `Calendar.ISO` inside a
    call: a public function replaces it in what it answers
    (`Tempo.Calendars.outside/1`), so a caller never sees it.

  * `:mixed_calendars` for an answer that holds an interval whose two ends
    are of different calendars, or a set whose members are: an expression
    is in one calendar.

  * `{:raised, module}` for a raise or an Erlang error.

  * `:builtin_raise` for an `ArgumentError` a built-in function raised, which
    no code wrote on purpose.

  * `:timeout` for no answer inside the time limit.

  * `:killed` for a cell that outgrew its heap limit.

  * `:consistent`, `:skipped` or `:inconsistent` for a consistency check
    (`Tempo.Matrix.Checks`) that answered `:ok`, `:skip` or `{:fail, detail}`.

  """
  @spec outcome((-> term())) :: outcome()
  def outcome(fun) when is_function(fun, 0) do
    fun
    |> detailed()
    |> elem(0)
  end

  @doc """
  The time a cell is allowed when its run does not say.

  ### Returns

  * Milliseconds.

  """
  @spec time_limit() :: pos_integer()
  def time_limit do
    @time_limit
  end

  @doc """
  Runs `fun` and classes its outcome, with the message of what it raised
  or returned as an error.

  ### Arguments

  * `fun` is a function of no arguments: the cell.

  * `time_limit` is the milliseconds the cell is allowed. The default is
    `time_limit/0`.

  ### Returns

  * `{outcome, detail}`, where `detail` is a message or `nil`.

  """
  @spec detailed((-> term()), pos_integer()) :: {outcome(), String.t() | nil}
  def detailed(fun, time_limit \\ @time_limit) when is_function(fun, 0) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:max_heap_size, %{size: @heap_limit, kill: true, error_logger: false})
        Process.put(:matrix_time_limit, time_limit)
        send(parent, {:outcome, self(), classify(fun.())})
      end)

    receive do
      {:outcome, ^pid, outcome} ->
        Process.demonitor(ref, [:flush])
        outcome

      {:DOWN, ^ref, :process, ^pid, reason} ->
        exited(reason)
    after
      time_limit ->
        Process.exit(pid, :kill)
        flush(pid, ref)
        {:timeout, nil}
    end
  end

  # The cell may answer between the time limit and the kill.
  defp flush(pid, ref) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end

    receive do
      {:outcome, ^pid, _outcome} -> :ok
    after
      0 -> :ok
    end
  end

  # The module Tempo works with for `Calendar.ISO` inside a call, and its
  # name as text would write it.
  @inside Tempo.Calendars.default()
  @inside_name inspect(@inside)

  defp classify(answer) do
    cond do
      holds_inside?(answer) -> {:inside_calendar, describe(answer)}
      mixes_calendars?(answer) -> {:mixed_calendars, describe(answer)}
      true -> classified(answer)
    end
  end

  defp classified({:check, :ok}) do
    {:consistent, nil}
  end

  defp classified({:check, :skip}) do
    {:skipped, nil}
  end

  defp classified({:check, {:fail, detail}}) do
    {:inconsistent, String.slice(detail, 0, 400)}
  end

  defp classified({:ok, _value}) do
    {:ok, nil}
  end

  defp classified({:error, %{__exception__: true, __struct__: module} = exception}) do
    {{:error, module}, message(exception)}
  end

  defp classified({:error, other}) do
    {{:bad_error, describe(other)}, nil}
  end

  defp classified(text) when is_binary(text) do
    if String.contains?(text, "Inspect.Error") do
      {:inspect_error, String.slice(text, 0, 160)}
    else
      {:value, nil}
    end
  end

  defp classified(_value) do
    {:value, nil}
  end

  # Whether an answer holds the inside module anywhere in it, read whole:
  # every element of a list and of a tuple, every key and value of a map
  # and of a struct, the text of a string and the message of an exception.
  # A stream is what a value keeps to give later, and is not read.
  defp holds_inside?(@inside) do
    true
  end

  defp holds_inside?(%Stream{}) do
    false
  end

  defp holds_inside?(text) when is_binary(text) do
    String.contains?(text, @inside_name)
  end

  defp holds_inside?(%{__exception__: true, __struct__: _module} = exception) do
    fields =
      exception
      |> Map.from_struct()
      |> Map.delete(:__exception__)

    holds_inside?(fields) or holds_inside?(Exception.message(exception))
  end

  defp holds_inside?([head | tail]) do
    holds_inside?(head) or holds_inside?(tail)
  end

  defp holds_inside?(term) when is_tuple(term) do
    holds_inside?(Tuple.to_list(term))
  end

  defp holds_inside?(term) when is_map(term) do
    holds_inside?(Map.to_list(term))
  end

  defp holds_inside?(_term) do
    false
  end

  defp exited({%{__exception__: true} = exception, _stacktrace}) do
    raised(exception)
  end

  defp exited({reason, stacktrace}) when is_list(stacktrace) do
    :error
    |> Exception.normalize(reason, stacktrace)
    |> raised()
  end

  defp exited(:killed) do
    {:killed, nil}
  end

  defp exited(reason) do
    {{:raised, ErlangError}, describe(reason)}
  end

  # An `ArgumentError` whose message is the runtime's own came from a built-in
  # function given what it cannot take, not from a `raise` written on purpose.
  defp raised(%ArgumentError{} = exception) do
    message = message(exception)

    if message =~ ~r/^(errors were found at the given arguments|argument error)/ do
      {:builtin_raise, message}
    else
      {{:raised, ArgumentError}, message}
    end
  end

  # Whether an answer holds an expression of two calendars anywhere in it:
  # an interval whose ends differ, or a set whose members do. A lazy set's
  # members are still to be given, and are not read.
  defp mixes_calendars?(%Tempo.Interval{
         from: %Tempo{calendar: from_calendar},
         to: %Tempo{calendar: to_calendar}
       })
       when from_calendar != to_calendar do
    true
  end

  defp mixes_calendars?(%Tempo.IntervalSet{} = set) do
    Tempo.bounded?(set) and mixed_members?(Tempo.IntervalSet.members(set))
  end

  defp mixes_calendars?(%Stream{}) do
    false
  end

  defp mixes_calendars?([head | tail]) do
    mixes_calendars?(head) or mixes_calendars?(tail)
  end

  defp mixes_calendars?(term) when is_tuple(term) do
    mixes_calendars?(Tuple.to_list(term))
  end

  defp mixes_calendars?(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.values()
    |> mixes_calendars?()
  end

  defp mixes_calendars?(term) when is_map(term) do
    mixes_calendars?(Map.values(term))
  end

  defp mixes_calendars?(_term) do
    false
  end

  defp mixed_members?(members) do
    calendars =
      for %Tempo.Interval{from: %Tempo{calendar: calendar}} <- members, uniq: true do
        calendar
      end

    length(calendars) > 1 or Enum.any?(members, &mixes_calendars?/1)
  end

  defp raised(%{__struct__: module} = exception) do
    if holds_inside?(exception) do
      {:inside_calendar, message(exception)}
    else
      {{:raised, module}, message(exception)}
    end
  end

  defp message(exception) do
    exception
    |> Exception.message()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 160)
  end

  defp describe(term) do
    term
    |> inspect(limit: 5)
    |> String.slice(0, 60)
  end

  @doc """
  Whether an outcome keeps the contract of an operation that `raises` as
  given.

  ### Arguments

  * `outcome` is a `t:outcome/0`.

  * `raises` is `:never`, or `:deliberate`: an exception written on purpose,
    which is a Tempo exception, one of Localize's, an `ArgumentError` that
    no built-in raised or, from the walk of what is not enumerable, a
    `Protocol.UndefinedError`.

  ### Returns

  * `true` or `false`.

  """
  @spec passes?(outcome(), :never | :deliberate) :: boolean()
  def passes?(:ok, _raises) do
    true
  end

  def passes?(:value, _raises) do
    true
  end

  def passes?(:consistent, _raises) do
    true
  end

  def passes?(:skipped, _raises) do
    true
  end

  def passes?({:error, _module}, _raises) do
    true
  end

  def passes?({:raised, module}, :deliberate) do
    deliberate?(module)
  end

  def passes?(_outcome, _raises) do
    false
  end

  defp deliberate?(module) when module in [ArgumentError, Protocol.UndefinedError] do
    true
  end

  defp deliberate?(module) do
    name = Atom.to_string(module)
    String.starts_with?(name, "Elixir.Tempo.") or String.starts_with?(name, "Elixir.Localize.")
  end

  @doc """
  An outcome as the short text the baseline holds.

  ### Arguments

  * `outcome` is a `t:outcome/0`.

  ### Returns

  * A string.

  """
  @spec label(outcome()) :: String.t()
  def label(:ok) do
    "ok"
  end

  def label(:value) do
    "value"
  end

  def label({:error, module}) do
    "error #{inspect(module)}"
  end

  def label({:bad_error, description}) do
    "bad error #{description}"
  end

  def label(:inspect_error) do
    "inspect error"
  end

  def label(:inside_calendar) do
    "holds the calendar Tempo works with"
  end

  def label(:mixed_calendars) do
    "holds two calendars in one expression"
  end

  def label({:raised, module}) do
    "raised #{inspect(module)}"
  end

  def label(:builtin_raise) do
    "raised ArgumentError from a built-in"
  end

  def label(:timeout) do
    "timeout"
  end

  def label(:killed) do
    "killed"
  end

  def label(:consistent) do
    "consistent"
  end

  def label(:skipped) do
    "skipped"
  end

  def label(:inconsistent) do
    "inconsistent"
  end

  @doc """
  Runs `fun` in a process of its own and says what it did, keeping what it
  returned. A check uses it to see what a function that may raise does.

  ### Arguments

  * `fun` is a function of no arguments.

  ### Returns

  * `{:returned, value}`, `{:raised, module}` for a raise or an Erlang
    error, or `:timeout`.

  """
  @spec attempt((-> term())) :: {:returned, term()} | {:raised, module()} | :timeout
  def attempt(fun) when is_function(fun, 0) do
    parent = self()
    # Inside a cell, the time the cell's run allows; otherwise the default.
    time_limit = Process.get(:matrix_time_limit, @time_limit)
    {pid, ref} = spawn_monitor(fn -> send(parent, {:returned, self(), fun.()}) end)

    receive do
      {:returned, ^pid, value} ->
        Process.demonitor(ref, [:flush])
        {:returned, value}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:raised, raised_module(reason)}
    after
      time_limit ->
        Process.exit(pid, :kill)
        Process.demonitor(ref, [:flush])
        :timeout
    end
  end

  defp raised_module({%{__exception__: true, __struct__: module}, _stacktrace}) do
    module
  end

  defp raised_module({reason, stacktrace}) when is_list(stacktrace) do
    Exception.normalize(:error, reason, stacktrace).__struct__
  end

  defp raised_module(_reason) do
    ErlangError
  end
end
