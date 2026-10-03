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

  * `{:raised, module}` for a raise or an Erlang error.

  * `:builtin_raise` for an `ArgumentError` a built-in function raised, which
    no code wrote on purpose.

  * `:timeout` for no answer inside the time limit.

  * `:killed` for a cell that outgrew its heap limit.

  * `:consistent`, `:skipped` or `:inconsistent` for a consistency check
    (`Tempo.Matrix.Checks`) that answered `:ok`, `:skip` or `{:fail, detail}`.

  """
  @spec outcome((-> term())) :: outcome()
  def outcome(fun) when is_function(fun, 0), do: fun |> detailed() |> elem(0)

  @doc """
  The time a cell is allowed when its run does not say.

  ### Returns

  * Milliseconds.

  """
  @spec time_limit() :: pos_integer()
  def time_limit, do: @time_limit

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

  defp classify({:check, :ok}), do: {:consistent, nil}
  defp classify({:check, :skip}), do: {:skipped, nil}
  defp classify({:check, {:fail, detail}}), do: {:inconsistent, String.slice(detail, 0, 400)}
  defp classify({:ok, _value}), do: {:ok, nil}

  defp classify({:error, %{__exception__: true, __struct__: module} = exception}),
    do: {{:error, module}, message(exception)}

  defp classify({:error, other}), do: {{:bad_error, describe(other)}, nil}

  defp classify(text) when is_binary(text) do
    if String.contains?(text, "Inspect.Error"),
      do: {:inspect_error, String.slice(text, 0, 160)},
      else: {:value, nil}
  end

  defp classify(_value), do: {:value, nil}

  defp exited({%{__exception__: true} = exception, _stacktrace}), do: raised(exception)

  defp exited({reason, stacktrace}) when is_list(stacktrace),
    do: :error |> Exception.normalize(reason, stacktrace) |> raised()

  defp exited(:killed), do: {:killed, nil}
  defp exited(reason), do: {{:raised, ErlangError}, describe(reason)}

  # An `ArgumentError` whose message is the runtime's own came from a built-in
  # function given what it cannot take, not from a `raise` written on purpose.
  defp raised(%ArgumentError{} = exception) do
    message = message(exception)

    if message =~ ~r/^(errors were found at the given arguments|argument error)/,
      do: {:builtin_raise, message},
      else: {{:raised, ArgumentError}, message}
  end

  defp raised(%{__struct__: module} = exception), do: {{:raised, module}, message(exception)}

  defp message(exception) do
    exception |> Exception.message() |> String.replace(~r/\s+/, " ") |> String.slice(0, 160)
  end

  defp describe(term), do: term |> inspect(limit: 5) |> String.slice(0, 60)

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
  def passes?(:ok, _raises), do: true
  def passes?(:value, _raises), do: true
  def passes?(:consistent, _raises), do: true
  def passes?(:skipped, _raises), do: true
  def passes?({:error, _module}, _raises), do: true
  def passes?({:raised, module}, :deliberate), do: deliberate?(module)
  def passes?(_outcome, _raises), do: false

  defp deliberate?(module) when module in [ArgumentError, Protocol.UndefinedError], do: true

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
  def label(:ok), do: "ok"
  def label(:value), do: "value"
  def label({:error, module}), do: "error #{inspect(module)}"
  def label({:bad_error, description}), do: "bad error #{description}"
  def label(:inspect_error), do: "inspect error"
  def label({:raised, module}), do: "raised #{inspect(module)}"
  def label(:builtin_raise), do: "raised ArgumentError from a built-in"
  def label(:timeout), do: "timeout"
  def label(:killed), do: "killed"
  def label(:consistent), do: "consistent"
  def label(:skipped), do: "skipped"
  def label(:inconsistent), do: "inconsistent"

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

  defp raised_module({%{__exception__: true, __struct__: module}, _stacktrace}), do: module

  defp raised_module({reason, stacktrace}) when is_list(stacktrace),
    do: Exception.normalize(:error, reason, stacktrace).__struct__

  defp raised_module(_reason), do: ErlangError
end
