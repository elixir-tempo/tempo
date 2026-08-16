# Recurrence-expansion benchmark: Tempo vs ical (expothecary/ical).
#
# Mirrors the rule set in ical's own benchmarks/bench_recurrence.exs
# (7 RRULEs, each expanded to its full COUNT of occurrences), and adds
# the cross-library comparison ical's suite does not do. Both libraries
# are RFC 5545 RRULE engines, so this is apples-to-apples.
#
#   mix run bench/recurrence_bench.exs
#
# Parsing is done once in setup (as ical's benchmark does); only the
# expansion of an already-parsed rule is timed.

import Tempo.Sigils
alias Tempo.{RRule, IntervalSet}

# ical resolves DTSTART;TZID against the configured zone database.
Calendar.put_time_zone_database(Tz.TimeZoneDatabase)

chicago = "America/Chicago"
tempo_start = ~o"2023-02-21T23:59:00[America/Chicago]"
tempo_start_h = ~o"2023-01-21T23:59:00[America/Chicago]"
ical_start = DateTime.new!(~D[2023-02-21], ~T[23:59:00], chicago, Tz.TimeZoneDatabase)
ical_start_h = DateTime.new!(~D[2023-01-21], ~T[23:59:00], chicago, Tz.TimeZoneDatabase)

# {label, rrule, tempo_dtstart, ical_dtstart, expected_count}
rules = [
  {"daily·30", "FREQ=DAILY;COUNT=30;INTERVAL=1", tempo_start, ical_start, 30},
  {"daily-weekday·520", "FREQ=DAILY;COUNT=520;INTERVAL=1;BYDAY=MO,TU,WE,TH,FR", tempo_start,
   ical_start, 520},
  {"hourly·720", "FREQ=HOURLY;COUNT=720;INTERVAL=1", tempo_start_h, ical_start_h, 720},
  {"minutely·1440", "FREQ=MINUTELY;COUNT=1440;INTERVAL=1", tempo_start, ical_start, 1440},
  {"weekly-MWF·780", "FREQ=WEEKLY;COUNT=780;INTERVAL=1;BYDAY=MO,WE,FR", tempo_start, ical_start,
   780},
  {"monthly-last-wkdy·240", "FREQ=MONTHLY;COUNT=240;INTERVAL=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1",
   tempo_start, ical_start, 240},
  {"monthly-first+last·480",
   "FREQ=MONTHLY;COUNT=480;INTERVAL=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1", tempo_start,
   ical_start, 480}
]

# ---- expansion closures (parsing hoisted into the input map) --------

tempo_expand = fn interval ->
  {:ok, set} = Tempo.to_interval(interval)
  IntervalSet.to_list(set)
end

ical_expand = fn {rule, dtstart} ->
  rule
  |> ICal.Recurrence.stream(start_date: dtstart)
  |> Enum.to_list()
end

# ---- correctness parity gate ----------------------------------------

IO.puts("\n== correctness parity (occurrence counts) ==")

parity =
  Enum.map(rules, fn {label, rrule, t_start, i_start, want} ->
    t_interval = RRule.parse!(rrule, from: t_start)
    i_rule = ICal.Recurrence.from_ics("RRULE:" <> rrule)

    t_count = tempo_expand.(t_interval) |> length()
    i_count = ical_expand.({i_rule, i_start}) |> length()

    status = if t_count == want and i_count == want, do: "ok", else: "MISMATCH"

    IO.puts(
      "  #{String.pad_trailing(label, 24)} tempo=#{t_count} ical=#{i_count} want=#{want} [#{status}]"
    )

    {label, {t_interval, {i_rule, i_start}}, status}
  end)

# datetime spot-check on the hard rule (last weekday of the month)
spot_rule = "FREQ=MONTHLY;COUNT=6;INTERVAL=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1"

tempo_dates =
  RRule.parse!(spot_rule, from: tempo_start)
  |> tempo_expand.()
  |> Enum.map(fn iv -> {Tempo.year(iv.from), Tempo.month(iv.from), Tempo.day(iv.from)} end)

ical_dates =
  ICal.Recurrence.from_ics("RRULE:" <> spot_rule)
  |> then(&ical_expand.({&1, ical_start}))
  |> Enum.map(fn dt -> {dt.year, dt.month, dt.day} end)

IO.puts("\n== datetime spot-check: last weekday of month, first 6 ==")
IO.puts("  tempo: #{inspect(tempo_dates)}")
IO.puts("  ical : #{inspect(ical_dates)}")
IO.puts("  agree: #{tempo_dates == ical_dates}")

if Enum.any?(parity, fn {_, _, s} -> s == "MISMATCH" end) do
  IO.puts("\n!! parity mismatch — benchmark comparison would be invalid. Aborting.")
  System.halt(1)
end

# ---- benchmark ------------------------------------------------------

inputs =
  Map.new(parity, fn {label, {t_interval, ical_pair}, _} ->
    {label, %{tempo: t_interval, ical: ical_pair}}
  end)

Benchee.run(
  %{
    "tempo" => fn input -> tempo_expand.(input.tempo) end,
    "ical" => fn input -> ical_expand.(input.ical) end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  print: [fast_warning: false]
)
