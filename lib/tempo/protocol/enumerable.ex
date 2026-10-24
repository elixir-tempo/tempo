defimpl Enumerable, for: Tempo do
  @moduledoc false

  # Law 6: `Enum` over an expression yields what it is made of. A singular
  # expression yields its children, the values one unit below its resolution;
  # a plural one yields its members. The walk is lazy and stops with a
  # `Tempo.ConversionError` once `Tempo.Limit.values/0` values have been
  # yielded, so a sequence with no end is read as far as it is asked and no
  # further.

  alias Tempo.Children
  alias Tempo.ConversionError
  alias Tempo.Limit
  alias Tempo.Spans
  alias Tempo.Walk

  @impl Enumerable
  def reduce(%Tempo{} = expression, acc, fun) do
    case Children.children(expression) do
      {:ok, stream} -> Enumerable.reduce(limited(stream, expression), acc, fun)
      {:error, exception} -> raise exception
    end
  end

  # A singular expression walked at a clock unit has a closed count.
  @impl Enumerable
  def count(%Tempo{} = expression) do
    unit = Spans.singular?(expression) and Children.child_unit(expression)

    case {unit in [:hour, :minute, :second], Spans.extent(expression)} do
      {true, {:ok, {start, stop}}} when is_integer(start) and is_integer(stop) ->
        closed_count(Walk.count({start, stop}, unit, Spans.frame_of(expression)))

      _no_closed_form ->
        {:error, __MODULE__}
    end
  end

  defp closed_count({:ok, count}), do: {:ok, count}
  defp closed_count({:error, _}), do: {:error, __MODULE__}

  # A value is a member of an expression when the expression covers it: the
  # 16th of June is in its week, and in the days of June (law 1).
  @impl Enumerable
  def member?(%Tempo{} = expression, %Tempo{} = element) do
    case Tempo.Algebra.aligned(element, expression, []) do
      {:ok, frame, pe, px} ->
        {:ok, match?([_ | _], pe) and Tempo.Algebra.holds?(:within, pe, px, frame)}

      {:error, _} ->
        {:ok, false}
    end
  end

  def member?(_expression, _element), do: {:ok, false}

  @impl Enumerable
  def slice(_expression), do: {:error, __MODULE__}

  defp limited(stream, expression) do
    Stream.transform(stream, 0, fn value, count ->
      if count >= Limit.values(),
        do: raise(ConversionError.exception(value: expression, reason: :too_many_values)),
        else: {[value], count + 1}
    end)
  end
end
