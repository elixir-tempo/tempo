# Tempo 2.0 against the published 1.6.4, case by case, through the API the
# two share: reading and writing text, walking, relating, the set
# operations and the expansion of recurrence rules.
#
# Run it in a checkout of v1.6.4 first, which saves its results, and then
# here, which reports each case beside 1.6.4's:
#
#     mix run /path/to/bench/against_1_6_bench.exs   # in the v1.6.4 checkout
#     mix run bench/against_1_6_bench.exs            # here
#
# Set TEMPO_BENCH_DIR to where the results are kept (the system's temporary
# directory by default).

version = to_string(Application.spec(:ex_tempo, :vsn))
two? = Version.match?(version, ">= 2.0.0-dev")
results = Path.join(System.get_env("TEMPO_BENCH_DIR", System.tmp_dir!()), "tempo_1_6_4.benchee")

day = fn %Date{} = date ->
  {:ok, value} = Tempo.new(year: date.year, month: date.month, day: date.day)
  value
end

# An interval set of `count` spans of `length` days, one every `every` days from 2026-01-01.
spans = fn count, every, length ->
  intervals =
    for n <- 0..(count - 1) do
      first = Date.add(~D[2026-01-01], n * every)

      {:ok, interval} =
        Tempo.Interval.new(from: day.(first), to: day.(Date.add(first, length - 1)))

      interval
    end

  {:ok, set} = Tempo.IntervalSet.new(intervals)
  set
end

# The occurrences of a rule: 1.6 converted a recurrence to an interval set.
occurrences =
  if two?,
    do: &Enum.to_list/1,
    else: fn rule -> rule |> Tempo.to_interval!() |> Tempo.IntervalSet.members() end

texts = [
  "2026-06-15",
  "2026-06-15T10:30:45",
  "2026-06-15T10:30:45+02:00",
  "2026-06-15T10:30[Europe/Paris]",
  "2026-06-15/2026-06-20",
  "P1Y2M3DT4H5M6S",
  "R/2026-06-01/P1M",
  "{2026-06-15,2026-07-04,2026-12-25}",
  "2026-06-1X",
  "1985-04-12T23:20:30.123456Z"
]

values = Enum.map(texts, &Tempo.from_iso8601!/1)

chicago = Tempo.from_iso8601!("2023-02-21T23:59:00[America/Chicago]")
chicago_january = Tempo.from_iso8601!("2023-01-21T23:59:00[America/Chicago]")

rules = [
  {"daily 30", "FREQ=DAILY;COUNT=30", chicago},
  {"weekdays 520", "FREQ=DAILY;COUNT=520;BYDAY=MO,TU,WE,TH,FR", chicago},
  {"hourly 720", "FREQ=HOURLY;COUNT=720", chicago_january},
  {"weekly MWF 780", "FREQ=WEEKLY;COUNT=780;BYDAY=MO,WE,FR", chicago},
  {"last weekday 240", "FREQ=MONTHLY;COUNT=240;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", chicago},
  {"yearly 4th Thursday of November 50", "FREQ=YEARLY;COUNT=50;BYMONTH=11;BYDAY=4TH", chicago}
]

parsed = for {name, rule, from} <- rules, do: {name, Tempo.RRule.parse!(rule, from: from)}

a = spans.(100, 3, 2)
b = spans.(100, 5, 3)
june = Tempo.from_iso8601!("2026-06")
july_fourth = Tempo.from_iso8601!("2026-07-04")
paris_day = Tempo.from_iso8601!("2026-03-29[Europe/Paris]")
year = Tempo.from_iso8601!("2026")

cases =
  %{
    "read ten texts" => fn -> Enum.each(texts, &Tempo.from_iso8601!/1) end,
    "write ten values" => fn -> Enum.each(values, &Tempo.to_iso8601/1) end,
    "walk the days of a year" => fn -> year |> Enum.flat_map(&Enum.to_list/1) |> length() end,
    "walk the hours of a day a zone springs forward" => fn -> Enum.count(paris_day) end,
    "relate a month and a day" => fn -> Tempo.relation(june, july_fourth) end,
    "compare a month and a day" => fn -> Tempo.compare(june, july_fourth) end,
    "union of two sets of 100" => fn -> Tempo.union(a, b) end,
    "intersection of two sets of 100" => fn -> Tempo.intersection(a, b) end,
    "difference of two sets of 100" => fn -> Tempo.difference(a, b) end
  }
  |> Map.merge(
    Map.new(parsed, fn {name, rule} -> {"expand " <> name, fn -> occurrences.(rule) end} end)
  )

options = [time: 2, warmup: 0.5, memory_time: 0.5, print: [fast_warning: false]]
options = if two?, do: options, else: Keyword.put(options, :save, path: results, tag: "1.6.4")

IO.puts("Tempo #{version}")
suite = Benchee.run(cases, options)

# Each case beside 1.6.4's: the median time and memory of each, and their ratio.
medians = fn %Benchee.Suite{scenarios: scenarios} ->
  Map.new(scenarios, fn scenario ->
    {scenario.job_name,
     {scenario.run_time_data.statistics.median, scenario.memory_usage_data.statistics.median}}
  end)
end

if two? and File.exists?(results) do
  before = results |> File.read!() |> :erlang.binary_to_term() |> medians.()
  now = medians.(suite)
  microseconds = fn nanoseconds -> :erlang.float_to_binary(nanoseconds / 1000, decimals: 1) end
  kilobytes = fn bytes -> :erlang.float_to_binary(bytes / 1024, decimals: 1) end
  ratio = fn a, b -> :erlang.float_to_binary(a / b, decimals: 2) end

  IO.puts(
    "\n| Case | 1.6.4 µs | 2.0 µs | time 2.0 / 1.6.4 | 1.6.4 KB | 2.0 KB | memory 2.0 / 1.6.4 |"
  )

  IO.puts("|---|---:|---:|---:|---:|---:|---:|")

  for {name, {time, memory}} <- Enum.sort(now),
      {old_time, old_memory} = Map.fetch!(before, name) do
    IO.puts(
      "| #{name} | #{microseconds.(old_time)} | #{microseconds.(time)} | #{ratio.(time, old_time)} | " <>
        "#{kilobytes.(old_memory)} | #{kilobytes.(memory)} | #{ratio.(memory, old_memory)} |"
    )
  end
end
