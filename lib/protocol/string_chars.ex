# Interpolation renders a value as `Tempo.to_string/1` does, and shows one
# it cannot render, such as an open interval, in its ISO 8601 form rather
# than raising (`Tempo.Format.string_chars/1`). The text is written of the
# value as Tempo works with it, whoever holds it (`Tempo.Calendars.inside/1`).

defimpl String.Chars, for: Tempo do
  def to_string(tempo) do
    tempo
    |> Tempo.Calendars.inside()
    |> Tempo.Format.string_chars()
  end
end

defimpl String.Chars, for: Tempo.Interval do
  def to_string(interval) do
    interval
    |> Tempo.Calendars.inside()
    |> Tempo.Format.string_chars()
  end
end

defimpl String.Chars, for: Tempo.IntervalSet do
  def to_string(set) do
    set
    |> Tempo.Calendars.inside()
    |> Tempo.Format.string_chars()
  end
end

defimpl String.Chars, for: Tempo.Set do
  def to_string(set) do
    set
    |> Tempo.Calendars.inside()
    |> Tempo.Format.string_chars()
  end
end

defimpl String.Chars, for: Tempo.RecurrenceSet do
  def to_string(set) do
    set
    |> Tempo.Calendars.inside()
    |> Tempo.Format.string_chars()
  end
end

defimpl String.Chars, for: Tempo.Duration do
  def to_string(duration) do
    duration
    |> Tempo.Calendars.inside()
    |> Tempo.Format.string_chars()
  end
end
