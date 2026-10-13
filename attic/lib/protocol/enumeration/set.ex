defimpl Enumerable, for: Tempo.Set do
  @impl Enumerable
  def count(_array) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def member?(_array, _element) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def slice(_array) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def reduce(%Tempo.Set{set: set, type: _type}, {:cont, acc}, fun) do
    reduce_set(set, {:cont, acc}, fun)
  end

  defp reduce_set([], {:cont, acc}, _fun) do
    {:halted, acc}
  end

  defp reduce_set([next | rest], {:cont, acc}, fun) do
    reduce_set(rest, fun.(next, acc), fun)
  end

  defp reduce_set(_enum, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp reduce_set(enum, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce_set(enum, &1, fun)}
  end
end
