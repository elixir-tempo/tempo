# Compares IntervalSet backends on a query-heavy workload:
# stabbing (`covered?/2`) a large set of anchored day-intervals.
#
#     mix run bench/interval_set_backend_bench.exs
#
# The tree backend's target is order-of-magnitude wins on stabbing
# once sets reach the thousands of members; construction pays a
# one-time O(n) projection cost.

import Tempo.Sigils

alias Tempo.IntervalSet

base = ~o"2000-01-01"
day = fn offset -> Tempo.shift(base, day: offset) end

:rand.seed(:exsss, {101, 102, 103})

members = 10_000

intervals =
  for _ <- 1..members do
    offset = :rand.uniform(10_000)
    span = :rand.uniform(5)
    %Tempo.Interval{from: day.(offset), to: day.(offset + span)}
  end

{:ok, list_set} = IntervalSet.new(intervals)
{:ok, tree_set} = IntervalSet.new(intervals, backend: :tree)

probes = for _ <- 1..100, do: day.(:rand.uniform(10_500))

Benchee.run(
  %{
    "covered?/2 list backend (#{members} members, 100 probes)" => fn ->
      Enum.each(probes, &IntervalSet.covered?(list_set, &1))
    end,
    "covered?/2 tree backend (#{members} members, 100 probes)" => fn ->
      Enum.each(probes, &IntervalSet.covered?(tree_set, &1))
    end,
    "construction list backend" => fn -> IntervalSet.new(intervals) end,
    "construction tree backend" => fn -> IntervalSet.new(intervals, backend: :tree) end
  },
  time: 3,
  warmup: 1,
  memory_time: 0
)
