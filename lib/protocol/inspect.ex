# A value carrying a construct with no ISO 8601 representation (a cron
# nearest-weekday recurrence) cannot be rendered as a `~o"…"` sigil;
# `Tempo.Inspect.inspect/1` shows it as a labelled struct view instead, so
# rendering for humans never crashes. The text is written of the value as
# Tempo works with it, whoever holds it (`Tempo.Calendars.inside/1`).
defimpl Inspect, for: Tempo do
  def inspect(tempo, _opts) do
    tempo |> Tempo.Calendars.inside() |> Tempo.Inspect.inspect()
  end
end

defimpl Inspect, for: Tempo.Set do
  def inspect(set, _opts) do
    set |> Tempo.Calendars.inside() |> Tempo.Inspect.inspect()
  end
end

defimpl Inspect, for: Tempo.Interval do
  def inspect(interval, _opts) do
    interval |> Tempo.Calendars.inside() |> Tempo.Inspect.inspect()
  end
end

defimpl Inspect, for: Tempo.Duration do
  def inspect(duration, _opts) do
    duration |> Tempo.Calendars.inside() |> Tempo.Inspect.inspect()
  end
end

defimpl Inspect, for: Tempo.IntervalSet do
  def inspect(set, opts) do
    set |> Tempo.Calendars.inside() |> Tempo.Inspect.inspect_interval_set(opts)
  end
end
