defimpl Inspect, for: Tempo do
  # An expression is shown as the sigil that reads it, its calendar and zone
  # in the suffix; one no text can hold is shown as its struct.
  def inspect(%Tempo{} = expression, options) do
    case Tempo.to_iso8601(expression) do
      {:ok, text} -> "~o" <> Kernel.inspect(text)
      {:error, _} -> Inspect.Any.inspect(expression, options)
    end
  end
end

defimpl Inspect, for: Tempo.Duration do
  def inspect(%Tempo.Duration{} = duration, options) do
    case Tempo.to_iso8601(duration) do
      {:ok, text} -> "~o" <> Kernel.inspect(text)
      {:error, _} -> Inspect.Any.inspect(duration, options)
    end
  end
end
