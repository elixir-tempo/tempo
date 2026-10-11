# A value carrying a construct with no ISO 8601 representation (a cron
# nearest-weekday recurrence) cannot be rendered as a `~o"…"` sigil;
# `Tempo.Inspect.inspect/1` shows it as a labelled struct view instead, so
# rendering for humans never crashes.
defimpl Inspect, for: Tempo do
  use Tempo.Border, every: true

  def inspect(tempo, _opts), do: Tempo.Inspect.inspect(tempo)
end

defimpl Inspect, for: Tempo.Set do
  use Tempo.Border, every: true

  def inspect(set, _opts), do: Tempo.Inspect.inspect(set)
end

defimpl Inspect, for: Tempo.Interval do
  use Tempo.Border, every: true

  def inspect(interval, _opts), do: Tempo.Inspect.inspect(interval)
end

defimpl Inspect, for: Tempo.Duration do
  use Tempo.Border, every: true

  def inspect(duration, _opts), do: Tempo.Inspect.inspect(duration)
end

defimpl Inspect, for: Tempo.IntervalSet do
  use Tempo.Border, every: true

  def inspect(set, opts) do
    Tempo.Inspect.inspect_interval_set(set, opts)
  end
end
