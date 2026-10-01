# Interpolation renders a value as `Tempo.to_string/1` does, and shows one
# it cannot render, such as an open interval, in its ISO 8601 form rather
# than raising (`Tempo.Format.string_chars/1`).

defimpl String.Chars, for: Tempo do
  def to_string(tempo), do: Tempo.Format.string_chars(tempo)
end

defimpl String.Chars, for: Tempo.Interval do
  def to_string(interval), do: Tempo.Format.string_chars(interval)
end

defimpl String.Chars, for: Tempo.IntervalSet do
  def to_string(set), do: Tempo.Format.string_chars(set)
end

defimpl String.Chars, for: Tempo.Set do
  def to_string(set), do: Tempo.Format.string_chars(set)
end

defimpl String.Chars, for: Tempo.RecurrenceSet do
  def to_string(set), do: Tempo.Format.string_chars(set)
end

defimpl String.Chars, for: Tempo.Duration do
  def to_string(duration), do: Tempo.Format.string_chars(duration)
end
