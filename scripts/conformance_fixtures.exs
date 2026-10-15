# Writes the conformance fixtures under test/fixtures/conformance/ from the
# oracles in test/support, which are written apart from the library: a port
# of Tempo to another language runs the fixtures from its own test suite, and
# Tempo's own tests read the same files, so the two cannot drift.
#
#     MIX_ENV=test mix run scripts/conformance_fixtures.exs
#
# Each file is JSON. Where a file lists many cases, each case is one line, so
# that a diff of the file reads case by case.

defmodule Tempo.ConformanceFixtures do
  alias Tempo.{ChangeOfTheClock, Interval, Rfc5545Examples, RRuleMeasure}
  alias Tempo.Matrix.{Cells, Corpus}

  @dir Path.expand("../test/fixtures/conformance", __DIR__)

  def run do
    File.mkdir_p!(@dir)
    write("allen.json", allen())
    write("set_operations.json", set_operations())
    write("clock_changes.json", clock_changes())
    write("rrule.json", rrule())
    write("expressions.json", expressions())
  end

  defp write(name, iodata) do
    path = Path.join(@dir, name)
    File.write!(path, [iodata, "\n"])
    IO.puts("#{name}: #{File.stat!(path).size} bytes")
  end

  # Elixir's nil is JSON's null; Erlang's encoder would write it as "nil".
  defp json(term), do: term |> :json.encode(&encode/2) |> IO.iodata_to_binary()

  defp encode(nil, _encoder), do: "null"
  defp encode(term, encoder), do: :json.encode_value(term, encoder)

  # A JSON object written one member per line, a member that is a list of
  # cases written one case per line.
  defp object(members) do
    body =
      Enum.map_join(members, ",\n", fn
        {key, {:lines, cases}} when is_atom(key) ->
          ~s(  "#{key}": [\n) <> Enum.map_join(cases, ",\n", &("    " <> json(&1))) <> "\n  ]"

        {key, value} when is_atom(key) ->
          ~s(  "#{key}": ) <> json(value)
      end)

    "{\n" <> body <> "\n}"
  end

  # ── Allen's relations ─────────────────────────────────────────────────

  # The relation of two half-open spans from four comparisons of their ends,
  # written here apart from the library.
  @relations ~w(precedes meets overlaps finished_by contains starts equals started_by during finishes overlapped_by met_by preceded_by)

  defp relation({a_from, a_to}, {b_from, b_to}) do
    cond do
      a_to < b_from -> "precedes"
      a_to == b_from -> "meets"
      a_from > b_to -> "preceded_by"
      a_from == b_to -> "met_by"
      true -> inner(compare(a_from, b_from), compare(a_to, b_to))
    end
  end

  defp compare(a, b) when a < b, do: :lt
  defp compare(a, b) when a > b, do: :gt
  defp compare(_, _), do: :eq

  defp inner(:lt, :lt), do: "overlaps"
  defp inner(:lt, :eq), do: "finished_by"
  defp inner(:lt, :gt), do: "contains"
  defp inner(:eq, :lt), do: "starts"
  defp inner(:eq, :eq), do: "equals"
  defp inner(:eq, :gt), do: "started_by"
  defp inner(:gt, :lt), do: "during"
  defp inner(:gt, :eq), do: "finishes"
  defp inner(:gt, :gt), do: "overlapped_by"

  @examples [
    {"precedes", {1, 2}, {3, 4}},
    {"meets", {1, 3}, {3, 5}},
    {"overlaps", {1, 4}, {3, 6}},
    {"finished_by", {1, 5}, {3, 5}},
    {"contains", {1, 5}, {2, 3}},
    {"starts", {1, 3}, {1, 5}},
    {"equals", {1, 3}, {1, 3}},
    {"started_by", {1, 5}, {1, 3}},
    {"during", {2, 3}, {1, 5}},
    {"finishes", {3, 5}, {1, 5}},
    {"overlapped_by", {3, 6}, {1, 4}},
    {"met_by", {3, 5}, {1, 3}},
    {"preceded_by", {3, 4}, {1, 2}}
  ]

  defp allen do
    spans = for from <- 0..6, to <- (from + 1)..7, do: {from, to}

    # Every placing of three spans on eight points: the relation of the
    # first to the third, given the first's to the second and the second's
    # to the third.
    composed =
      for a <- spans, b <- spans, c <- spans, reduce: %{} do
        table ->
          Map.update(
            table,
            {relation(a, b), relation(b, c)},
            MapSet.new([relation(a, c)]),
            &MapSet.put(&1, relation(a, c))
          )
      end

    relations =
      for {name, {a_from, a_to}, {b_from, b_to}} <- @examples do
        %{"relation" => name, "a" => [a_from, a_to], "b" => [b_from, b_to]}
      end

    composition =
      for first <- @relations, second <- @relations do
        %{
          "first" => first,
          "second" => second,
          "composed" => composed |> Map.fetch!({first, second}) |> Enum.sort_by(&index/1)
        }
      end

    object(
      spans: "half-open [from, to) on a line of integer points; the relation is of a to b",
      relations: {:lines, relations},
      composition: {:lines, composition}
    )
  end

  defp index(relation), do: Enum.find_index(@relations, &(&1 == relation))

  # ── Set operations ────────────────────────────────────────────────────

  @points 0..4
  @spans for from <- @points, to <- @points, from < to, do: {from, to}
  @sets [[]] ++
          for(span <- @spans, do: [span]) ++
          for(first <- @spans, second <- @spans, first <= second, do: [first, second])

  @first_day ~D[2026-06-01]
  @first_hour ~N[2026-06-01 09:00:00]

  defp cells(spans),
    do: for({from, to} <- spans, cell <- from..(to - 1), into: MapSet.new(), do: cell)

  # Cells as the coalesced spans that cover them.
  defp spans_of(cells) do
    cells
    |> Enum.sort()
    |> Enum.chunk_while([], &chunk_run/2, &{:cont, &1, []})
    |> Enum.reject(&(&1 == []))
    |> Enum.map(fn run -> [List.first(run), List.last(run) + 1] end)
  end

  defp chunk_run(cell, []), do: {:cont, [cell]}
  defp chunk_run(cell, [last | _] = run) when cell == last + 1, do: {:cont, run ++ [cell]}
  defp chunk_run(cell, run), do: {:cont, run, [cell]}

  defp expected(:union, a, b), do: MapSet.union(cells(a), cells(b))
  defp expected(:intersection, a, b), do: MapSet.intersection(cells(a), cells(b))
  defp expected(:difference, a, b), do: MapSet.difference(cells(a), cells(b))

  defp expected(:symmetric_difference, a, b),
    do: MapSet.union(MapSet.difference(cells(a), cells(b)), MapSet.difference(cells(b), cells(a)))

  defp day(slot, calendar \\ Calendar.ISO) do
    %Date{year: year, month: month, day: day} =
      Date.convert!(Date.add(@first_day, slot), calendar)

    Tempo.new!(year: year, month: month, day: day, calendar: calendar)
  end

  defp hour(slot, frame \\ []) do
    at = NaiveDateTime.add(@first_hour, slot * 3600)
    Tempo.new!([year: at.year, month: at.month, day: at.day, hour: at.hour] ++ frame)
  end

  defp paris_hour(slot) do
    at =
      @first_hour
      |> NaiveDateTime.add(slot * 3600)
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.shift_zone!("Europe/Paris")

    Tempo.new!(year: at.year, month: at.month, day: at.day, hour: at.hour, zone: "Europe/Paris")
  end

  # A span of days is written through its last day; a span of hours ends as its last hour begins.
  defp span(:days, {from, to}), do: Interval.new!(from: day(from), to: day(to - 1))

  defp span(:hebrew_days, {from, to}),
    do: Interval.new!(from: day(from, Calendrical.Hebrew), to: day(to - 1, Calendrical.Hebrew))

  defp span(:hours, {from, to}), do: Interval.new!(from: hour(from), to: hour(to))

  defp span(:utc_hours, {from, to}),
    do: Interval.new!(from: hour(from, shift: [hour: 0]), to: hour(to, shift: [hour: 0]))

  defp span(:paris_hours, {from, to}),
    do: Interval.new!(from: paris_hour(from), to: paris_hour(to))

  defp line(name, cell) do
    %{
      cell: cell,
      spans:
        Map.new(@spans, fn {from, to} = span ->
          {"#{from}/#{to}", Tempo.to_iso8601!(span(name, span))}
        end)
    }
  end

  @cycle_points [0, 6, 12, 18]
  @cycle_spans for from <- @cycle_points, to <- @cycle_points, from != to, do: {from, to}
  @cycle_sets for(span <- @cycle_spans, do: [span]) ++
                for(
                  first <- @cycle_spans,
                  second <- @cycle_spans,
                  first < second,
                  do: [first, second]
                )

  defp hours_of(from, to) when from < to, do: Enum.to_list(from..(to - 1))
  defp hours_of(from, to), do: Enum.to_list(from..23) ++ Enum.to_list(0..(to - 1)//1)

  defp cycle_cells(spans),
    do: for({from, to} <- spans, cell <- hours_of(from, to), into: MapSet.new(), do: cell)

  defp set_operations do
    cases =
      for a <- @sets, b <- @sets do
        %{
          "a" => Enum.map(a, &Tuple.to_list/1),
          "b" => Enum.map(b, &Tuple.to_list/1),
          "union" => spans_of(expected(:union, a, b)),
          "intersection" => spans_of(expected(:intersection, a, b)),
          "difference" => spans_of(expected(:difference, a, b)),
          "symmetric_difference" => spans_of(expected(:symmetric_difference, a, b))
        }
      end

    cycle_cases =
      for a <- @cycle_sets, b <- @cycle_sets do
        ca = cycle_cells(a)
        cb = cycle_cells(b)

        %{
          "a" => Enum.map(a, &Tuple.to_list/1),
          "b" => Enum.map(b, &Tuple.to_list/1),
          "intersection" => Enum.sort(MapSet.intersection(ca, cb)),
          "difference" => Enum.sort(MapSet.difference(ca, cb))
        }
      end

    object(
      points:
        "a line of five points 0 to 4; a set is spans [from, to) between them; a result is the coalesced spans of the cells its members cover",
      lines: %{
        "days" => line(:days, "a day from 2026-06-01; a span is written through its last day"),
        "hebrew_days" =>
          line(:hebrew_days, "the same days in the Hebrew calendar; written through the last day"),
        "hours" =>
          line(
            :hours,
            "an hour from 2026-06-01T09 on no clock in particular; a span ends as its last hour begins"
          ),
        "utc_hours" => line(:utc_hours, "the same hours at UTC"),
        "paris_hours" => line(:paris_hours, "the same instants on the clock of Europe/Paris")
      },
      pairings: [
        ["days", "days"],
        ["hours", "hours"],
        ["utc_hours", "paris_hours"],
        ["paris_hours", "utc_hours"],
        ["days", "hebrew_days"],
        ["hebrew_days", "days"]
      ],
      cases: {:lines, cases},
      cycle: %{
        "points" =>
          "hours of the day 0, 6, 12 and 18 with no date; a span from a later hour to an earlier runs through midnight; a result is the hours covered",
        "spans" =>
          Map.new(@cycle_spans, fn {from, to} ->
            {"#{from}/#{to}",
             Tempo.to_iso8601!(
               Interval.new!(from: Tempo.new!(hour: from), to: Tempo.new!(hour: to))
             )}
          end)
      },
      cycle_cases: {:lines, cycle_cases}
    )
  end

  # ── Changes of the clock ──────────────────────────────────────────────

  defp clock_changes do
    days =
      for {zone, date, change} <- ChangeOfTheClock.gaps() ++ ChangeOfTheClock.folds() do
        {from, to} = ChangeOfTheClock.day_shown(zone, date)

        %{
          "zone" => zone,
          "date" => Date.to_iso8601(date),
          "change" => change,
          "day_shown" => [from, to],
          "hours" =>
            Enum.map(ChangeOfTheClock.hours_shown(zone, date), fn {hour, from, to} ->
              %{"hour" => hour, "from" => from, "to" => to}
            end)
        }
      end

    object(
      moments:
        "seconds since 1970-01-01T00:00:00Z; a day runs from the moment the clock first shows a reading of it to the moment it first shows one of the day after; an hour is the minutes, one after another, at which the clock reads within it, and a new occurrence of the hour begins where the clock shows its first reading again",
      days: {:lines, days}
    )
  end

  # ── Recurrence rules ──────────────────────────────────────────────────

  @starts [~N[2025-01-31 09:00:00], ~N[2024-02-29 09:00:00], ~N[2026-06-15 10:30:00]]
  @count 12
  @days_tried 366 * 200

  @any [
    [],
    [bymonth: [1, 6]],
    [byday: [{nil, 1}, {nil, 3}, {nil, 5}]],
    [bymonthday: [1, 15, -1]],
    [bymonth: [2], bymonthday: [29]],
    [byhour: [9, 17]],
    [byhour: [9], byminute: [0, 30]],
    [byday: [{nil, 2}], byhour: [8, 12]],
    [bymonth: [3, 9], byday: [{nil, 6}, {nil, 7}]]
  ]

  @parts [
    day: @any,
    week: [
      [],
      [byday: [{nil, 2}, {nil, 4}]],
      [byday: [{nil, 7}, {nil, 1}]],
      [bymonth: [1, 6]],
      [byday: [{nil, 1}, {nil, 3}, {nil, 5}], byhour: [9, 17]],
      [bymonth: [6], byday: [{nil, 5}]]
    ],
    month:
      @any ++
        [
          [byday: [{1, 1}]],
          [byday: [{-1, 5}]],
          [byday: [{2, 2}, {4, 2}]],
          [byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}], bysetpos: [1]],
          [byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}], bysetpos: [-1]],
          [bymonthday: [13], byday: [{nil, 5}]],
          [bymonthday: [-1]],
          [bymonthday: [31]],
          [byday: [{nil, 6}], bymonthday: [7, 8, 9, 10, 11, 12, 13]],
          [byday: [{nil, 2}, {nil, 3}, {nil, 4}], bysetpos: [3]],
          [byday: [{2, 1}, {2, 3}]],
          [byday: [{1, 1}, {-1, 5}]],
          [byday: [{nil, 1}, {1, 2}]],
          [byday: [{1, 1}, {3, 1}], bysetpos: [-1]],
          [byday: [{2, 1}, {2, 3}], byhour: [9, 17], bysetpos: [1, -1]],
          [byday: [{1, 2}, {-1, 4}], bymonth: [2, 8]]
        ],
    year:
      @any ++
        [
          [byyearday: [1, 100, -1]],
          [byweekno: [20], byday: [{nil, 1}]],
          [byweekno: [20]],
          [byday: [{20, 1}]],
          [byday: [{-1, 7}], bymonth: [10]],
          [bymonth: [3], byday: [{nil, 4}]],
          [bymonth: [11], byday: [{nil, 2}], bymonthday: [2, 3, 4, 5, 6, 7, 8]],
          [byday: [{nil, 1}]],
          [bymonth: [1, 7], byday: [{1, 1}]],
          [byday: [{1, 7}, {-1, 7}], bymonth: [4, 10]],
          [bymonth: [6, 7], bymonthday: [1, -1], byhour: [8, 20]],
          [byday: [{1, 7}, {-1, 1}]],
          [byday: [{1, 1}, {1, 2}], bymonth: [6, 7]],
          [byday: [{10, 1}, {-10, 5}]],
          [byday: [{2, 1}, {-1, 6}], bymonth: [3], byhour: [9, 17]]
        ]
  ]

  @frequencies %{day: "DAILY", week: "WEEKLY", month: "MONTHLY", year: "YEARLY"}
  @weekdays %{1 => "MO", 2 => "TU", 3 => "WE", 4 => "TH", 5 => "FR", 6 => "SA", 7 => "SU"}
  @part_keys [
    bymonth: "BYMONTH",
    byweekno: "BYWEEKNO",
    byyearday: "BYYEARDAY",
    bymonthday: "BYMONTHDAY",
    byday: "BYDAY",
    byhour: "BYHOUR",
    byminute: "BYMINUTE",
    bysetpos: "BYSETPOS"
  ]

  # A rule as RFC 5545 writes it, from the parts the test lists.
  defp rule_text(frequency, interval, parts) do
    head = ["FREQ=" <> Map.fetch!(@frequencies, frequency)]
    interval = if interval > 1, do: ["INTERVAL=#{interval}"], else: []

    written =
      for {key, name} <- @part_keys, {^key, values} <- parts do
        name <> "=" <> Enum.map_join(values, ",", &part_value/1)
      end

    Enum.join(head ++ interval ++ ["COUNT=#{@count}"] ++ written, ";")
  end

  defp part_value({nil, weekday}), do: Map.fetch!(@weekdays, weekday)
  defp part_value({nth, weekday}), do: "#{nth}#{Map.fetch!(@weekdays, weekday)}"
  defp part_value(n), do: Integer.to_string(n)

  defp rrule do
    rules =
      for {frequency, parts} <- @parts,
          part <- parts,
          interval <- [1, 2, 3],
          start <- @starts do
        text = rule_text(frequency, interval, part)

        measured =
          RRuleMeasure.occurrences(
            text,
            start,
            Date.add(NaiveDateTime.to_date(start), @days_tried)
          )

        %{
          "rule" => text,
          "start" => NaiveDateTime.to_iso8601(start),
          "occurrences" => Enum.map(measured, &NaiveDateTime.to_iso8601/1),
          "complete" => length(measured) in [0, @count]
        }
      end

    examples =
      for example <- Rfc5545Examples.all() do
        {{year, month, day}, {hour, minute, second}} = example.start

        %{
          "title" => example.title,
          "start" =>
            NaiveDateTime.to_iso8601(NaiveDateTime.new!(year, month, day, hour, minute, second)),
          "zone" => "America/New_York",
          "rules" => example.rules,
          "excluded" =>
            Enum.map(example.excluded, fn {y, m, d} -> Date.to_iso8601(Date.new!(y, m, d)) end),
          "occurrences" =>
            for {{y, m, d}, {h, mi}, zone} <- example.occurrences do
              %{
                "at" => NaiveDateTime.to_iso8601(NaiveDateTime.new!(y, m, d, h, mi, 0)),
                "zone_abbr" => zone
              }
            end,
          "complete" => example.complete?
        }
      end

    object(
      rules:
        "a rule from a start on no clock in particular (its weeks begin on Monday); the occurrences are the first COUNT the rule has within two hundred years of the start, as an expander written to RFC 5545 section 3.3.10 gives them; where complete is false the rule has fewer than COUNT in two hundred years and an implementation gives these first",
      cases: {:lines, rules},
      examples:
        "the examples of RFC 5545 section 3.8.5.3 as the standard lists them; the start is on the clock of the zone, and an UNTIL written at UTC is read on that clock; where complete is false the standard elides and an implementation gives these first",
      example_cases: {:lines, examples}
    )
  end

  # ── Every expression against every operation ──────────────────────────

  # The cells of the expressions written by hand (the levels core, extended
  # and open); the generated expressions are Tempo's own. Most cells answer
  # with a value, so the file lists the operations, the partners and the
  # refusals, and the rule that every other cell answers.
  @written_levels [:core, :extended, :open]

  defp expressions do
    levels =
      Map.new(Corpus.entries(), &{{&1.text, &1.calendar && inspect(&1.calendar)}, &1.level})

    cells = for group <- Cells.groups(), cell <- Cells.cells(group), do: cell
    written = Enum.filter(cells, &(Map.get(levels, {&1.input, &1.calendar}) in @written_levels))

    # The refusals of each expression, by what they answer: each a key of the
    # operation and, for an operation of two expressions, its argument.
    refusals =
      written
      |> Enum.reject(&(Tempo.Conformance.kind(&1.out) == "answer"))
      |> Enum.group_by(&{&1.input, &1.calendar}, &{Tempo.Conformance.kind(&1.out), key(&1)})
      |> Map.new(fn {expression, kinds} ->
        {expression, kinds |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Map.new()}
      end)

    expressions =
      for entry <- Corpus.entries(), entry.level in @written_levels do
        calendar = entry.calendar && inspect(entry.calendar)

        %{
          "input" => entry.text,
          "calendar" => calendar,
          "level" => Atom.to_string(entry.level),
          "refusals" => Map.get(refusals, {entry.text, calendar}, %{})
        }
      end

    object(
      answers:
        "every expression written by hand in the corpus (the levels core, extended and open) against every operation of the library, each read as ISO 8601 text in the calendar given where one is; an operation of two expressions is run with the expression itself (argument self), with each partner (the partner's text) and after each partner (the partner's text and a bar); each expression lists what it refuses, by answer, as the operation's name followed, for an operation of two expressions, by an at sign and the argument; a cell not listed answers with a value; a refusal is an error by its name and reason, a raise by its name, or unread for text the grammar refuses",
      operations:
        cells
        |> Enum.group_by(&Atom.to_string(&1.group), & &1.op)
        |> Map.new(fn {group, operations} ->
          {group, operations |> Enum.uniq() |> Enum.sort()}
        end),
      partners: Enum.map(Corpus.partners(), &elem(&1, 0)),
      expressions: {:lines, expressions}
    )
  end

  defp key(%{op: op, arg: nil}), do: op
  defp key(%{op: op, arg: arg}), do: op <> " @ " <> arg
end

Tempo.ConformanceFixtures.run()
