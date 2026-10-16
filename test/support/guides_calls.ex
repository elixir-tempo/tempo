defmodule Tempo.GuidesCalls do
  @moduledoc false

  # The calls a guide's examples make, recorded as they run: each call the
  # code writes to a Tempo module, to `Enum` or `Stream`, or to a function
  # of `Tempo.Builder` the page imports, is rewritten to go through
  # `call/3`, which makes the call and sends the process what was called
  # and what was answered. A call Tempo makes within itself is not the
  # guide's and is not rewritten. A call that raises is not recorded.

  @recorded_modules [:Tempo, :Enum, :Stream]

  @builder_functions Tempo.Builder.__info__(:functions)

  @doc "Makes a call and sends the process its module, function, arguments and answer."
  @spec call(module(), atom(), [term()]) :: term()
  def call(module, function, arguments) do
    answer = apply(module, function, arguments)
    send(self(), {__MODULE__, module, function, arguments, answer})
    answer
  end

  @doc """
  Evaluates a guide's code with its calls recorded, its output captured,
  and returns the result, the binding and the calls in the order they were
  answered.
  """
  @spec eval(String.t(), keyword(), String.t()) :: {term(), keyword(), [tuple()]}
  def eval(code, binding, preamble) do
    builder? = String.contains?(preamble, "import Tempo.Builder")

    quoted =
      ("import Tempo.Sigils\n" <> preamble <> "\n" <> code)
      |> Code.string_to_quoted!()
      |> unpiped()
      |> recorded(builder?)

    {:ok, io} = StringIO.open("")
    leader = Process.group_leader()
    Process.group_leader(self(), io)
    {result, binding} = Code.eval_quoted(quoted, binding)
    Process.group_leader(self(), leader)
    StringIO.close(io)

    {result, binding, drained([])}
  end

  defp drained(calls) do
    receive do
      {__MODULE__, module, function, arguments, answer} ->
        drained([{module, function, arguments, answer} | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end

  # `a |> f(b)` is `f(a, b)`, so that a call in a pipeline is rewritten as
  # any other is.
  defp unpiped(quoted) do
    Macro.prewalk(quoted, fn
      {:|>, _meta, [left, right]} -> Macro.pipe(left, right, 0)
      other -> other
    end)
  end

  # A function named by name and arity (`&Tempo.Interval.from/1`) is a
  # name, not a call.
  defp recorded({:&, meta, [{:/, _, _} = name_and_arity]}, _builder?) do
    {:&, meta, [name_and_arity]}
  end

  defp recorded(
         {{:., _dot, [{:__aliases__, _, [first | _]} = module, function]}, _meta, arguments},
         builder?
       )
       when first in @recorded_modules and is_atom(function) and is_list(arguments) do
    arguments = Enum.map(arguments, &recorded(&1, builder?))

    quote do
      unquote(__MODULE__).call(unquote(module), unquote(function), unquote(arguments))
    end
  end

  defp recorded({function, meta, arguments}, true)
       when is_atom(function) and is_list(arguments) do
    if {function, length(arguments)} in @builder_functions do
      arguments = Enum.map(arguments, &recorded(&1, true))

      quote do
        unquote(__MODULE__).call(Tempo.Builder, unquote(function), unquote(arguments))
      end
    else
      {function, meta, Enum.map(arguments, &recorded(&1, true))}
    end
  end

  defp recorded({form, meta, arguments}, builder?) when is_list(arguments) do
    {recorded(form, builder?), meta, Enum.map(arguments, &recorded(&1, builder?))}
  end

  defp recorded({left, right}, builder?) do
    {recorded(left, builder?), recorded(right, builder?)}
  end

  defp recorded(list, builder?) when is_list(list) do
    Enum.map(list, &recorded(&1, builder?))
  end

  defp recorded(other, _builder?) do
    other
  end
end
