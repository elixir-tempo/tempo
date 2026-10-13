defimpl String.Chars, for: Tempo do
  # Interpolation writes the ISO 8601 text; words for a reader are `Tempo.to_string/2`.
  def to_string(%Tempo{} = expression), do: Tempo.to_iso8601!(expression)
end

defimpl String.Chars, for: Tempo.Duration do
  def to_string(%Tempo.Duration{} = duration), do: Tempo.to_iso8601!(duration)
end
