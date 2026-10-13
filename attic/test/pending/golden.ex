defmodule Tempo.Golden do
  @moduledoc """
  The library's answers, frozen as data for the redesign (see
  `plans/architecture-redesign.md`, section 11.1).

  `write/1` runs every golden operation on every entry of the matrix's corpus
  (`Tempo.Matrix.Corpus`) and writes one gzipped JSON Lines file per group of
  operations under `test/golden/`. `check/1` reads the files back, runs the
  same cells on the library as it now stands, and returns the cells whose
  answers differ. A difference is a defect in the new code or a change
  decided in section 10 of the plan, and the tags on each cell say which
  decisions can touch it:

  * `written_end` — the text is an interval whose last end is written to a
    calendar unit, which decision 14 reads through its end.

  * `plural` — the text names several spans, whose enumeration decision 1
    changes to its members.

  Each cell is one line: the operation, its group, the input text and its
  calendar, the argument of a two-value operation, the tags, and the answer
  as data. An answer is the ISO 8601 text of a value, a list of them for a
  set or a walk, a plain value, or `{"error": module, "reason": text}`,
  `{"raised": module}` or `{"timeout": true}`.

  """

  import Tempo.Sigils

  alias Tempo.IntervalSet
  alias Tempo.Matrix.Corpus
  alias Tempo.RecurrenceSet

  @dir "test/golden"
  @time_limit 10_000
  @take 24

  @groups [
    :read,
    :convert,
    :walk,
    :measure,
    :parts,
    :arithmetic,
    :format,
    :select,
    :compare,
    :combine
  ]

  @type cell :: %{
          op: String.t(),
          group: atom(),
          input: String.t(),
          calendar: String.t() | nil,
          arg: String.t() | nil,
          tags: [String.t()],
          out: term()
        }

  @doc """
  Writes the golden files.

  ### Arguments

  * `dir` is the directory to write into. The default is `test/golden`.

  ### Returns

  * A map from group to the count of cells written.

  """
  @spec write(String.t()) :: %{atom() => non_neg_integer()}
  def write(dir \\ @dir) do
    File.mkdir_p!(dir)

    for group <- @groups, into: %{} do
      cells = cells(group)
      lines = Enum.map(cells, &(JSON.encode!(&1) <> "\n"))
      File.write!(Path.join(dir, "#{group}.jsonl.gz"), :zlib.gzip(IO.iodata_to_binary(lines)))
      {group, length(cells)}
    end
  end

  @doc """
  Runs every golden cell again and compares it with the files.

  ### Arguments

  * `dir` is the directory the files are in. The default is `test/golden`.

  ### Returns

  * A list of `{recorded, now}` for every cell whose answer differs, each a
    `t:cell/0`; empty when the library answers as the files record.

  """
  @spec check(String.t()) :: [{cell(), cell()}]
  def check(dir \\ @dir) do
    for group <- @groups,
        recorded = read(Path.join(dir, "#{group}.jsonl.gz")),
        now = cells(group),
        {was, is} <- Enum.zip(recorded, now),
        was != is do
      {was, is}
    end
  end

  @doc false
  def read(path) do
    path
    |> File.read!()
    |> :zlib.gunzip()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line -> line |> JSON.decode!() |> as_cell() end)
  end

  @doc false
  # The cells of one group, run in isolation and in order.
  def cells(group) do
    group
    |> jobs()
    |> Task.async_stream(&run/1,
      max_concurrency: System.schedulers_online(),
      ordered: true,
      timeout: @time_limit,
      on_timeout: :kill_task
    )
    |> Enum.zip(jobs(group))
    |> Enum.map(fn
      {{:ok, cell}, _job} -> cell
      {{:exit, _reason}, job} -> cell_of(job, %{"timeout" => true})
    end)
  end

  # A job is a cell before it is run: what to call and on what.
  defp jobs(:read),
    do: for(entry <- entries(), do: {"from_iso8601/2", :read, entry, nil, &{:ok, &1}})

  defp jobs(group) when group in [:convert, :walk, :measure, :parts, :arithmetic, :format] do
    for {name, fun} <- unary(group), entry <- entries(), do: {name, group, entry, nil, fun}
  end

  defp jobs(:select) do
    for {name, fun} <- selectors(),
        entry <- entries(),
        entry.level == :core,
        do: {name, :select, entry, nil, fun}
  end

  defp jobs(group) when group in [:compare, :combine] do
    partners = Corpus.partners()

    for {name, fun} <- binary(group),
        entry <- entries(),
        {arg, partner} <- partners_of(entry, partners),
        {arg, pair} <- orders(entry, arg, partner) do
      {name, group, entry, arg, pair_fun(fun, pair)}
    end
  end

  # The core values meet every partner in both orders and themselves; a
  # generated value meets one partner in its own frame, as the matrix does.
  defp partners_of(%{level: :core}, partners), do: partners

  defp partners_of(entry, partners) do
    zoned? = entry.text |> String.contains?(["Z", "[", "+0", "-0"])

    case Enum.filter(partners, fn {text, _} -> String.contains?(text, ["Z", "["]) == zoned? end) do
      [partner | _] -> [partner]
      [] -> Enum.take(partners, 1)
    end
  end

  defp orders(%{level: :core}, arg, partner) do
    [{"self", :self}, {arg, {:with, partner}}, {"#{arg} |", {:after, partner}}]
  end

  defp orders(_entry, arg, partner), do: [{arg, {:with, partner}}]

  defp pair_fun(fun, :self), do: fn value -> fun.(value, value) end
  defp pair_fun(fun, {:with, partner}), do: fn value -> fun.(value, partner) end
  defp pair_fun(fun, {:after, partner}), do: fn value -> fun.(partner, value) end

  defp entries, do: Corpus.entries()

  # One cell: read the entry, apply the function, record what happened.
  defp run({_name, _group, entry, _arg, fun} = job) do
    out =
      case Corpus.read(entry) do
        {:ok, value} -> protected(fn -> fun.(value) end)
        {:error, exception} -> %{"unread" => inspect(exception.__struct__)}
      end

    cell_of(job, out)
  end

  # A raise is an answer too: the matrix records it as one, and so does this.
  defp protected(fun) do
    answer(fun.())
  rescue
    exception -> %{"raised" => inspect(exception.__struct__)}
  catch
    kind, value -> %{"raised" => inspect({kind, value})}
  end

  defp cell_of({name, group, entry, arg, _fun}, out) do
    %{
      op: name,
      group: group,
      input: entry.text,
      calendar: entry.calendar && inspect(entry.calendar),
      arg: arg,
      tags: tags(entry.text),
      out: out
    }
  end

  defp as_cell(map) do
    %{
      op: map["op"],
      group: String.to_existing_atom(map["group"]),
      input: map["input"],
      calendar: map["calendar"],
      arg: map["arg"],
      tags: map["tags"],
      out: map["out"]
    }
  end

  # The answer as data.
  defp answer({:ok, value}), do: %{"ok" => data(value)}

  defp answer({:error, %{__struct__: module} = exception}) do
    %{"error" => inspect(module), "reason" => inspect(Map.get(exception, :reason))}
  end

  defp answer({:error, other}), do: %{"error" => inspect(other)}
  defp answer(value), do: %{"value" => data(value)}

  defp data(%IntervalSet{} = set) do
    members = IntervalSet.members(set)
    %{"set" => Enum.map(members, &data/1), "units" => Enum.map(members, &inspect(&1.unit))}
  end

  defp data(%RecurrenceSet{} = set),
    do: %{"recurrence_set" => inspect(set, limit: :infinity)}

  defp data(%struct{} = value)
       when struct in [Tempo, Tempo.Interval, Tempo.Duration, Tempo.Set] do
    case Tempo.to_iso8601(value) do
      {:ok, text} -> text
      {:error, _} -> inspect(value, limit: :infinity)
    end
  end

  defp data(%struct{} = value) when struct in [Date, Time, NaiveDateTime, DateTime, Duration] do
    inspect(value)
  end

  defp data(list) when is_list(list), do: Enum.map(list, &data/1)

  defp data(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value

  defp data(value), do: inspect(value, limit: :infinity)

  defp tags(text) do
    body = String.replace(text, ~r/(\[[^\]]*\])+$/, "")

    [
      if(written_end?(body), do: "written_end"),
      if(plural?(body), do: "plural")
    ]
    |> Enum.reject(&is_nil/1)
  end

  # An interval whose last end is a date, a week, a month or a year.
  defp written_end?(body) do
    case String.split(body, "/") do
      [_single] -> false
      parts -> parts |> List.last() |> calendar_end?()
    end
  end

  defp calendar_end?(""), do: false
  defp calendar_end?(".."), do: false
  defp calendar_end?(<<"P", _::binary>>), do: false
  defp calendar_end?(<<"F", _::binary>>), do: false
  defp calendar_end?(last), do: not String.contains?(last, ["T", "H", "N"])

  defp plural?(body), do: String.contains?(body, ["{", "[", "X", "R/", "L", ".."])

  # The operations of one value, by group.
  defp unary(:convert) do
    [
      {"to_interval/1", &Tempo.to_interval/1},
      {"to_interval/2 within 2026", &Tempo.to_interval(&1, within: ~o"2026")},
      {"to_interval_set/1", &Tempo.to_interval_set/1},
      {"to_calendar/2 hebrew", &Tempo.to_calendar(&1, Calendrical.Hebrew)},
      {"in_zone/2 Europe/Paris", &Tempo.in_zone(&1, "Europe/Paris")},
      {"shift_zone/2 America/New_York", &Tempo.shift_zone(&1, "America/New_York")},
      {"to_date/1", &Tempo.to_date/1},
      {"to_time/1", &Tempo.to_time/1},
      {"to_naive_datetime/1", &Tempo.to_naive_datetime/1},
      {"to_datetime/1", &Tempo.to_datetime/1},
      {"to_elixir/1", &Tempo.to_elixir/1}
    ]
  end

  defp unary(:walk) do
    [
      {"Enum.take/2 #{@take}", &Enum.take(&1, @take)},
      {"Enum.count/1", &Enum.count/1}
    ]
  end

  defp unary(:measure) do
    [
      {"duration/1", &Tempo.duration/1},
      {"bounded?/1", &Tempo.bounded?/1},
      {"empty?/1", &Tempo.empty?/1},
      {"at_least?/2 P1D", &Tempo.at_least?(&1, ~o"P1D")},
      {"shorter_than?/2 P1M", &Tempo.shorter_than?(&1, ~o"P1M")}
    ]
  end

  defp unary(:parts) do
    [
      {"resolution/1", &Tempo.resolution/1},
      {"anchored?/1", &Tempo.anchored?/1},
      {"floating?/1", &Tempo.floating?/1},
      {"zoned?/1", &Tempo.zoned?/1},
      {"year/1", &Tempo.year/1},
      {"month/1", &Tempo.month/1},
      {"day/1", &Tempo.day/1},
      {"hour/1", &Tempo.hour/1},
      {"week/1", &Tempo.week/1},
      {"day_of_week/1", &Tempo.day_of_week/1},
      {"day_of_year/1", &Tempo.day_of_year/1},
      {"quarter_of_year/1", &Tempo.quarter_of_year/1},
      {"leap_year?/1", &Tempo.leap_year?/1},
      {"days_in_month/1", &Tempo.days_in_month/1},
      {"metadata/1", &Tempo.metadata/1}
    ]
  end

  defp unary(:arithmetic) do
    [
      {"shift/2 P1D", &Tempo.shift(&1, ~o"P1D")},
      {"shift/2 P1M", &Tempo.shift(&1, ~o"P1M")},
      {"shift/2 P1Y", &Tempo.shift(&1, ~o"P1Y")},
      {"shift/2 PT1H", &Tempo.shift(&1, ~o"PT1H")},
      {"shift/2 -P1D", &Tempo.shift(&1, ~o"-P1D")},
      {"trunc/2 month", &Tempo.trunc(&1, :month)},
      {"round/2 day", &Tempo.round(&1, :day)},
      {"extend/1", &Tempo.extend/1},
      {"extend_resolution/2 day", &Tempo.extend_resolution(&1, :day)},
      {"at_resolution/2 hour", &Tempo.at_resolution(&1, :hour)},
      {"split/1", &Tempo.split/1}
    ]
  end

  defp unary(:format) do
    [
      {"to_iso8601/1", &Tempo.to_iso8601/1},
      {"to_string/2 en", &Tempo.to_string(&1, locale: :en)},
      {"explain/1", &Tempo.explain/1},
      {"inspect/1", &inspect(&1, limit: :infinity)}
    ]
  end

  # Selectors applied to the core periods.
  defp selectors do
    [
      {"select/2 L1K1IN", &Tempo.select(&1, ~o"L1K1IN")},
      {"select/2 L5K-1IN", &Tempo.select(&1, ~o"L5K-1IN")},
      {"select/2 T10:30", &Tempo.select(&1, ~o"T10:30")},
      {"select/2 15D", &Tempo.select(&1, ~o"15D")},
      {"select/2 workdays", &Tempo.select(&1, Tempo.workdays())},
      {"select/2 [1, 15]", &Tempo.select(&1, [1, 15])}
    ]
  end

  # The operations of two values, by group.
  defp binary(:compare) do
    [
      {"relation/2", &Tempo.relation/2},
      {"compare/2", &Tempo.compare/2},
      {"overlaps?/2", &Tempo.overlaps?/2},
      {"contains?/2", &Tempo.contains?/2},
      {"within?/2", &Tempo.within?/2},
      {"before?/2", &Tempo.before?/2},
      {"after?/2", &Tempo.after?/2},
      {"adjacent?/2", &Tempo.adjacent?/2},
      {"disjoint?/2", &Tempo.disjoint?/2},
      {"equal?/2", &Tempo.equal?/2},
      {"overlap_certainty/2", &Tempo.overlap_certainty/2},
      {"within_certainty/2", &Tempo.within_certainty/2},
      {"certainly_before?/2", &Tempo.certainly_before?/2},
      {"possibly_overlaps?/2", &Tempo.possibly_overlaps?/2},
      {"duration/2", &Tempo.duration/2},
      {"Enum.member?/2", &Enum.member?/2}
    ]
  end

  defp binary(:combine) do
    [
      {"union/2", &Tempo.union/2},
      {"intersection/2", &Tempo.intersection/2},
      {"difference/2", &Tempo.difference/2},
      {"symmetric_difference/2", &Tempo.symmetric_difference/2},
      {"complement/2 within", &Tempo.complement(&1, within: &2)},
      {"members_overlapping/2", &Tempo.members_overlapping/2},
      {"members_outside/2", &Tempo.members_outside/2},
      {"members_in_exactly_one/2", &Tempo.members_in_exactly_one/2},
      {"at/2", &Tempo.at/2},
      {"on/2", &Tempo.on/2}
    ]
  end
end
