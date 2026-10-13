defmodule Tempo.Golden do
  @moduledoc """
  The answers of the library before the redesign, frozen as data (see
  `plans/architecture-redesign.md`, section 11.1), and the check of the new
  library against them.

  The files under `test/golden/` hold one gzipped JSON Lines file per group
  of operations; each line is a cell: the operation, the input text and its
  calendar, the argument of a two-value operation, the tags, and the answer
  as data. `check/1` runs the cells of the groups the new library answers so
  far and returns the cells whose answers differ, each with the decision of
  section 10 that can account for it, or `nil` when none can.

  The tags on a cell say which decisions may touch it: `written_end` for an
  interval whose last end is written to a date (decision 14) and `plural`
  for a text naming several spans (decision 1).

  """

  alias Tempo.Duration
  alias Tempo.Matrix.Corpus
  alias Tempo.Spans

  @dir "test/golden"

  # The groups the new library answers so far; the rest come with their phases.
  @groups [
    :read,
    :walk,
    :convert,
    :compare,
    :combine,
    :arithmetic,
    :measure,
    :parts,
    :select,
    :format
  ]
  @take 24

  @type cell :: %{
          op: String.t(),
          group: atom(),
          input: String.t(),
          calendar: String.t() | nil,
          arg: String.t() | nil,
          tags: [String.t()],
          out: term()
        }

  @type difference :: %{was: cell(), is: cell(), decision: atom() | nil}

  @doc """
  Runs the golden cells again and compares them with the files.

  ### Arguments

  * `dir` is the directory the files are in. The default is `test/golden`.

  ### Returns

  * A list of `t:difference/0`, one for every cell whose answer differs;
    empty when the library answers as the files record.

  """
  @spec check(String.t()) :: [difference()]
  def check(dir \\ @dir) do
    for group <- @groups,
        recorded = answered(read(Path.join(dir, "#{group}.jsonl.gz")), group),
        now = Map.new(cells(group), fn cell -> {key(cell), cell} end),
        was <- recorded,
        is = Map.fetch!(now, key(was)),
        was.out != is.out do
      %{was: was, is: is, decision: decision(was, is)}
    end
  end

  defp key(cell), do: {cell.op, cell.input, cell.calendar, cell.arg}

  # The recorded cells of the operations the new library answers, with the
  # `units` an interval set once carried (decision 2) left out of the answer.
  defp answered(cells, :read), do: cells

  defp answered(cells, group) do
    for cell <- cells, is_map_key(operations(group), cell.op) do
      %{cell | out: without_units(cell.out)}
    end
  end

  defp without_units(%{"ok" => %{"set" => set}}), do: %{"ok" => %{"set" => set}}
  defp without_units(%{"value" => %{"set" => set}}), do: %{"value" => %{"set" => set}}
  defp without_units(out), do: out

  @doc false
  def read(path) do
    path
    |> File.read!()
    |> :zlib.gunzip()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line -> line |> JSON.decode!() |> as_cell() end)
  end

  # The operations of a group the new library answers, by name as the files record them.
  @doc false
  def operations_of(group), do: operations(group)

  @doc false
  def decision_of(was, is), do: decision(was, is)

  defp operations(:walk) do
    %{
      "Enum.take/2 24" => &Enum.take(&1, @take),
      "Enum.count/1" => &Enum.count/1
    }
  end

  defp operations(:compare) do
    %{
      "relation/2" => &Tempo.relation/2,
      "compare/2" => &Tempo.compare/2,
      "overlaps?/2" => &Tempo.overlaps?/2,
      "contains?/2" => &Tempo.contains?/2,
      "within?/2" => &Tempo.within?/2,
      "before?/2" => &Tempo.before?/2,
      "after?/2" => &Tempo.after?/2,
      "adjacent?/2" => &Tempo.adjacent?/2,
      "disjoint?/2" => &Tempo.disjoint?/2,
      "equal?/2" => &Tempo.equal?/2,
      "overlap_certainty/2" => &Tempo.certainty(:overlaps, &1, &2),
      "within_certainty/2" => &Tempo.certainty(:within, &1, &2),
      "certainly_before?/2" => &Tempo.certainly?(:before, &1, &2),
      "possibly_overlaps?/2" => &Tempo.possibly?(:overlaps, &1, &2),
      "Enum.member?/2" => &Enum.member?/2
    }
  end

  defp operations(:combine) do
    %{
      "union/2" => &Tempo.union/2,
      "intersection/2" => &Tempo.intersection/2,
      "difference/2" => &Tempo.difference/2,
      "symmetric_difference/2" => &Tempo.symmetric_difference/2,
      "complement/2 within" => &Tempo.complement(&1, within: &2),
      "members_overlapping/2" => &Tempo.members_overlapping/2,
      "members_outside/2" => &Tempo.members_outside/2,
      "members_in_exactly_one/2" => &Tempo.members_in_exactly_one/2,
      "at/2" => &Tempo.at/2,
      "on/2" => &Tempo.on/2
    }
  end

  defp operations(:arithmetic) do
    %{
      "shift/2 P1D" => &Tempo.shift(&1, day: 1),
      "shift/2 -P1D" => &Tempo.shift(&1, day: -1),
      "shift/2 P1M" => &Tempo.shift(&1, month: 1),
      "shift/2 P1Y" => &Tempo.shift(&1, year: 1),
      "shift/2 PT1H" => &Tempo.shift(&1, hour: 1),
      "trunc/2 month" => &Tempo.trunc(&1, :month),
      "round/2 day" => &Tempo.round(&1, :day),
      "extend/1" => &Tempo.extend/1,
      "at_resolution/2 hour" => &Tempo.at_resolution(&1, :hour),
      "split/1" => &Tempo.split/1
    }
  end

  defp operations(:measure) do
    %{
      "duration/1" => &Tempo.duration/1,
      "at_least?/2 P1D" => &Tempo.at_least?(&1, Duration.new!(day: 1)),
      "shorter_than?/2 P1M" => &Tempo.shorter_than?(&1, Duration.new!(month: 1)),
      "bounded?/1" => &Tempo.bounded?/1,
      "empty?/1" => &Tempo.empty?/1
    }
  end

  defp operations(:parts) do
    %{
      "year/1" => &Tempo.year/1,
      "month/1" => &Tempo.month/1,
      "day/1" => &Tempo.day/1,
      "hour/1" => &Tempo.hour/1,
      "week/1" => &Tempo.week/1,
      "day_of_week/1" => &Tempo.day_of_week/1,
      "day_of_year/1" => &Tempo.day_of_year/1,
      "quarter_of_year/1" => &Tempo.quarter_of_year/1,
      "leap_year?/1" => &Tempo.leap_year?/1,
      "days_in_month/1" => &Tempo.days_in_month/1,
      "resolution/1" => &Tempo.resolution/1,
      "anchored?/1" => &Tempo.anchored?/1,
      "floating?/1" => &Tempo.floating?/1,
      "zoned?/1" => &Tempo.zoned?/1,
      "metadata/1" => &Tempo.metadata/1
    }
  end

  defp operations(:format) do
    %{
      "to_iso8601/1" => &Tempo.to_iso8601/1,
      "inspect/1" => &inspect/1,
      "to_string/2 en" => &Tempo.to_string(&1, locale: "en"),
      "explain/1" => &Tempo.explain/1
    }
  end

  defp operations(:select) do
    %{
      "select/2 workdays" => &Tempo.select(&1, Tempo.workdays(:US)),
      "select/2 [1, 15]" => &Tempo.select(&1, [1, 15]),
      "select/2 T10:30" => &Tempo.select(&1, Tempo.from_iso8601!("T10:30")),
      "select/2 L5K-1IN" => &Tempo.select(&1, Tempo.from_iso8601!("L5K-1IN")),
      "select/2 L1K1IN" => &Tempo.select(&1, Tempo.from_iso8601!("L1K1IN")),
      "select/2 15D" => &Tempo.select(&1, Tempo.from_iso8601!("15D"))
    }
  end

  defp operations(:convert) do
    %{
      "to_interval/1" => &Tempo.to_interval/1,
      "to_interval/2 within 2026" => &Tempo.to_interval(&1, within: Tempo.from_iso8601!("2026"))
    }
  end

  @doc false
  def cells(:read) do
    for entry <- Corpus.entries() do
      out =
        case Corpus.read(entry) do
          {:ok, value} -> %{"ok" => written(value)}
          {:error, exception} -> %{"unread" => inspect(exception.__struct__)}
        end

      %{
        op: "from_iso8601/2",
        group: :read,
        input: entry.text,
        calendar: entry.calendar && inspect(entry.calendar),
        arg: nil,
        tags: [],
        out: out
      }
    end
  end

  def cells(group) when group in [:compare, :combine] do
    partners = Corpus.partners()

    for entry <- Corpus.entries(),
        {name, fun} <- Enum.sort(operations(group)),
        {arg, partner} <- partners_of(entry, partners),
        {arg, pair} <- orders(entry, arg, partner) do
      %{
        op: name,
        group: group,
        input: entry.text,
        calendar: entry.calendar && inspect(entry.calendar),
        arg: arg,
        tags: [],
        out: cell_out(Corpus.read(entry), pair_fun(fun, pair))
      }
    end
  end

  def cells(group) do
    for entry <- Corpus.entries(), {name, fun} <- Enum.sort(operations(group)) do
      out = cell_out(Corpus.read(entry), fun)

      %{
        op: name,
        group: group,
        input: entry.text,
        calendar: entry.calendar && inspect(entry.calendar),
        arg: nil,
        tags: [],
        out: out
      }
    end
  end

  # The core values meet every partner in both orders and themselves; a
  # generated value meets one partner in its own frame, as the matrix does.
  defp partners_of(%{level: :core}, partners), do: partners

  defp partners_of(entry, partners) do
    zoned? = String.contains?(entry.text, ["Z", "[", "+0", "-0"])

    case Enum.filter(partners, fn {text, _} -> String.contains?(text, ["Z", "["]) == zoned? end) do
      [partner | _] -> [partner]
      [] -> Enum.take(partners, 1)
    end
  end

  defp orders(%{level: :core}, arg, partner),
    do: [{"self", :self}, {arg, {:with, partner}}, {"#{arg} |", {:after, partner}}]

  defp orders(_entry, arg, partner), do: [{arg, {:with, partner}}]

  defp pair_fun(fun, :self), do: fn value -> fun.(value, value) end
  defp pair_fun(fun, {:with, partner}), do: fn value -> fun.(value, partner) end
  defp pair_fun(fun, {:after, partner}), do: fn value -> fun.(partner, value) end

  defp cell_out({:ok, value}, fun), do: protected(fn -> fun.(value) end)
  defp cell_out({:error, exception}, _fun), do: %{"unread" => inspect(exception.__struct__)}

  # A raise is an answer too: the matrix records it as one, and so does this.
  defp protected(fun) do
    answer(fun.())
  rescue
    exception -> %{"raised" => inspect(exception.__struct__)}
  end

  defp answer({:ok, value}), do: %{"ok" => data(value)}

  defp answer({:error, %{__struct__: module} = exception}),
    do: %{"error" => inspect(module), "reason" => inspect(Map.get(exception, :reason))}

  defp answer(value), do: %{"value" => data(value)}

  defp data(%Tempo{form: {:all, members}}), do: %{"set" => Enum.map(members, &data/1)}
  defp data(%Tempo{} = value), do: written(value)
  defp data(%Tempo.Duration{} = duration), do: written(duration)
  defp data(list) when is_list(list), do: Enum.map(list, &data/1)

  defp data(tuple) when is_tuple(tuple),
    do: "{" <> Enum.map_join(Tuple.to_list(tuple), ", ", &sigil_text/1) <> "}"

  defp data(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value

  defp data(value), do: inspect(value, limit: :infinity)

  defp sigil_text(%Tempo{} = value), do: ~s(~o"#{written(value)}")
  defp sigil_text(other), do: inspect(other)

  defp written(value) do
    case Tempo.to_iso8601(value) do
      {:ok, text} -> text
      {:error, _} -> inspect(value, limit: :infinity)
    end
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

  # A changed walk or conversion. The decisions of section 10 that reach these
  # groups: enumeration yields members (1), a date end is read through (14),
  # the merged errors (12), and the forms kept as written (13 and phase 2).
  defp decision(%{group: group} = was, is) when group != :read do
    calendar = calendar_module(was.calendar)

    Enum.find_value(rules(), fn {decision, holds?} ->
      if holds?.(was, is, calendar), do: decision
    end)
  end

  # The decision that accounts for a changed reading. A new text that reads
  # back as the same value as the input is the input kept as written
  # (decision 13 for a week once written with `w`); the kind of form kept is
  # named for the report. A text no longer read, or read as another value, is
  # a defect no decision accounts for.
  defp decision(%{input: input, calendar: calendar, out: %{"ok" => was}}, %{out: %{"ok" => is}}) do
    read = fn text -> Tempo.from_iso8601(text, calendar_module(calendar)) end

    cond do
      not match?({:ok, _}, read.(input)) -> nil
      read.(is) != read.(input) -> nil
      String.contains?(was, "w") -> :weeks_13
      true -> kept(input, was, is)
    end
  end

  defp decision(%{out: %{"unread" => _}}, %{input: input, calendar: calendar, out: %{"ok" => is}}) do
    read = fn text -> Tempo.from_iso8601(text, calendar_module(calendar)) end
    if match?({:ok, _}, read.(input)) and read.(is) == read.(input), do: :now_read, else: nil
  end

  defp decision(_was, _is), do: nil

  # The decisions that reach the walk and convert groups, first that holds:
  # the merged errors (12), the phases not yet built, the forms read as ranges
  # or kept, enumeration by members (1), a date end read through (14), a
  # value placed by its window, a value as its own span, the order and the
  # grouping of a set's members.
  defp rules, do: first_rules() ++ later_rules()

  defp first_rules,
    do:
      error_rules() ++
        result_rules() ++ part_rules() ++ shape_rules() ++ measure_rules() ++ phase_rules()

  # Errors and answers: both erred, the same answer now tagged, an answer where
  # the old library erred, or a text the old library could not write.
  defp error_rules do
    [
      {:named_error_12, fn was, is, _ -> error?(was.out) and error?(is.out) end},
      {:tagged_result,
       fn was, is, _ -> was.out["value"] != nil and was.out["value"] == is.out["ok"] end},
      {:now_written, fn was, _, _ -> inspect(was.out) =~ "not ISO 8601 expressible" end},
      {:now_answered, fn was, is, _ -> error?(was.out) and not error?(is.out) end},
      {:member_is_covered, fn was, _, _ -> was.op == "Enum.member?/2" end}
    ]
  end

  # The comparisons: law 9 ends, ordering by extent, relations of plurals, certainty.
  defp result_rules do
    [
      {:written_end_14, fn was, _, _ -> date_end?(was.arg) end},
      {:compare_by_extent, fn was, _, _ -> was.op == "compare/2" end},
      {:relation_of_plural,
       fn was, _, _ -> was.op == "relation/2" and plural_text?(was.input) end},
      {:certainty_5,
       fn was, _, _ ->
         String.contains?(was.op, "certain") or String.contains?(was.op, "possibly")
       end},
      {:canonical_form, fn was, is, calendar -> same_cover?(was.out, is.out, calendar) end}
    ]
  end

  # The shapes the new library keeps or writes: the unit as written, the axis
  # kept, sets as written, a mask as one of its values, values where 2.0 wrote spans.
  # Parts: a unit read as written, computed through the calendar, or nil.
  defp part_rules do
    [
      {:resolution_is_unit, &resolution_is_unit?/3},
      {:part_computed, &part_computed?/3},
      {:part_within_one_period, &part_within_one_period?/3},
      {:part_as_written, &part_as_written?/3}
    ]
  end

  # Shapes the arithmetic keeps: the axis, sets, masks, counts from the end, groups.
  defp shape_rules do
    [
      {:axis_kept, &axis_kept?/3},
      {:as_written, &as_written_arithmetic?/3},
      {:mask_kept, &mask_kept?/3},
      {:values_not_spans, &values_not_spans?/3},
      {:count_from_end_kept, &count_from_end_kept?/3},
      {:group_kept, fn was, _, _ -> was.group != :read and String.contains?(was.input, "G") end},
      {:duration_end_kept, &duration_end_kept?/3},
      {:century_as_years, &century_as_years?/3},
      {:set_kept, &set_kept?/3},
      {:week_of_month_as_written, &week_of_month_as_written?/3}
    ]
  end

  # Lengths, rounding and splitting, and what is rendered by the harness.
  defp measure_rules do
    [
      {:measured_in_written_unit, &measured_in_written_unit?/3},
      {:finer_than_written, &finer_than_written?/3},
      {:fraction_pending, &fraction_pending?/3},
      {:needs_a_year, &needs_a_year?/3},
      {:span_parts_agree, &span_parts_agree?/3},
      {:rendering, &rendering?/3},
      {:explain_rewritten, &explain_rewritten?/3},
      {:inspect_is_the_sigil, &inspect_is_the_sigil?/3},
      {:written_as_read, &written_as_read?/3},
      {:words_for_what_is_covered, &words_for_what_is_covered?/3},
      {:values_not_spans, &selected_values?/3},
      {:selected_in_each_period, &selected_in_each?/3},
      {:position_in_period, &position_in_period?/3},
      {:integers_are_days, &integers_are_days?/3},
      {:within_period_only, &within_period_only?/3},
      {:split_is_of_a_value, &split_is_of_a_value?/3}
    ]
  end

  defp resolution_is_unit?(was, is, _),
    do: was.op == "resolution/1" and is_binary(text(was)) and is_binary(text(is))

  defp part_computed?(was, is, _),
    do: was.group == :parts and was.out["value"] == nil and is_integer(is.out["value"])

  defp part_within_one_period?(was, is, _),
    do: was.group == :parts and is_integer(was.out["value"]) and is.out["value"] == nil

  defp part_as_written?(was, is, _) do
    was.group == :parts and is_integer(was.out["value"]) and is_integer(is.out["value"]) and
      Regex.match?(~r/[\dX][WG]/, was.input)
  end

  defp axis_kept?(was, is, _) do
    was.group == :arithmetic and
      Regex.match?(~r/[\dX-][WOK]|^\d{4}-?\d{3}$/, was.input) and
      is_binary(text(is)) and Regex.match?(~r/[\dX][WOK]/, text(is))
  end

  defp as_written_arithmetic?(was, is, _) do
    was.group == :arithmetic and is_binary(text(was)) and is_binary(text(is)) and
      (without_sets(text(was)) == without_sets(text(is)) or text(is) == was.input)
  end

  defp mask_kept?(was, is, _) do
    was.group == :arithmetic and String.contains?(was.input, "X") and is_binary(text(is)) and
      (String.contains?(text(is), "X") or String.starts_with?(text(is), "["))
  end

  defp values_not_spans?(was, is, _),
    do: was.group == :arithmetic and is_map(was.out["value"]) and is_binary(text(is))

  defp count_from_end_kept?(was, is, _) do
    Regex.match?(~r/[A-Z]-[\dX]/, was.input) and
      (Regex.match?(~r/[A-Z]-[\dX]/, inspect(is.out["ok"])) or
         (is_integer(is.out["value"]) and is.out["value"] < 0))
  end

  defp duration_end_kept?(was, is, _),
    do: was.group == :arithmetic and is_binary(text(is)) and String.contains?(text(is), "/P")

  defp century_as_years?(was, is, _),
    do:
      was.group == :arithmetic and Regex.match?(~r/^\d+[CJ]$/, was.input) and is_binary(text(is))

  defp set_kept?(was, is, _) do
    was.group == :arithmetic and String.starts_with?(was.input, "{") and
      is_binary(text(is)) and String.starts_with?(text(is), "{")
  end

  defp week_of_month_as_written?(was, is, _),
    do:
      was.group == :arithmetic and Regex.match?(~r/[\dX]M-?\d*W/, was.input) and
        is_binary(text(is))

  defp measured_in_written_unit?(was, is, _),
    do: was.op == "duration/1" and is_binary(text(was)) and is_binary(text(is))

  defp finer_than_written?(was, is, _) do
    was.op =~ "round" and is_binary(is.out["reason"]) and
      (is.out["reason"] =~ "finer_than_written" or is.out["reason"] == ":several")
  end

  defp fraction_pending?(was, is, _),
    do: was.op == "extend/1" and is.out["reason"] == ":no_finer_unit"

  defp needs_a_year?(was, is, calendar),
    do: is.out["reason"] == ":needs_a_year" and not anchored?(was.input, calendar)

  defp span_parts_agree?(was, is, _),
    do: was.group == :parts and String.contains?(was.input, "/") and is.out["value"] == nil

  defp rendering?(was, _, _),
    do: was.op == "split/1" and (was.calendar != nil or String.contains?(was.input, "u-ca"))

  defp split_is_of_a_value?(was, is, _),
    do: was.op == "split/1" and is.out["reason"] == ":several"

  defp explain_rewritten?(was, is, _), do: was.op == "explain/1" and is_binary(is.out["value"])

  # Words show the time covered: a date end through, a clock end as its
  # reading, a mask as the stretch it covers at the unit it is shown in.
  defp words_for_what_is_covered?(was, is, _),
    do: was.op == "to_string/2 en" and is_binary(was.out["ok"]) and is_binary(is.out["ok"])

  defp inspect_is_the_sigil?(was, is, _),
    do: was.op == "inspect/1" and String.starts_with?(to_string(is.out["value"]), "~o")

  # The text written reads back as the value the input reads to.
  defp written_as_read?(%{op: "to_iso8601/1", input: input}, %{out: %{"ok" => text}}, calendar)
       when is_binary(text) do
    case {Tempo.from_iso8601(input, calendar), Tempo.from_iso8601(text, calendar)} do
      {{:ok, a}, {:ok, b}} -> a == b
      _ -> false
    end
  end

  defp written_as_read?(_was, _is, _calendar), do: false

  # The old library selected spans where the new selects values: the same starts.
  defp selected_values?(%{group: :select} = was, is, calendar) do
    case {was.out, is.out} do
      {%{"ok" => %{"set" => old}}, %{"ok" => %{"set" => new}}} when length(old) == length(new) ->
        starts(old, calendar) == starts(new, calendar)

      _ ->
        false
    end
  end

  defp selected_values?(_was, _is, _calendar), do: false

  # The parts are selected in each container of the period, where 2.0 selected once.
  defp selected_in_each?(%{group: :select} = was, is, calendar) do
    case {was.out, is.out} do
      {%{"ok" => %{"set" => [one]}}, %{"ok" => %{"set" => [first | _]}}} ->
        starts([one], calendar) == starts([first], calendar)

      _ ->
        false
    end
  end

  defp selected_in_each?(_was, _is, _calendar), do: false

  # A position counts in the period, where 2.0 listed every candidate.
  defp position_in_period?(%{group: :select, op: op} = was, is, calendar) do
    case {String.contains?(op, "I"), was.out, is.out} do
      {true, %{"ok" => %{"set" => old}}, %{"ok" => %{"set" => [one]}}} ->
        hd(starts([one], calendar)) in starts(old, calendar)

      _ ->
        false
    end
  end

  defp position_in_period?(_was, _is, _calendar), do: false

  # A list of integers selects days of the month, where 2.0 selected the period's next unit.
  defp integers_are_days?(%{group: :select, op: "select/2 [1, 15]"} = was, is, _calendar),
    do: is_map(was.out["ok"]) and is_map(is.out["ok"])

  defp integers_are_days?(_was, _is, _calendar), do: false

  # Only values within the period are selected, where 2.0 cut a partial one or listed every candidate.
  defp within_period_only?(%{group: :select} = was, is, calendar) do
    case {was.out, is.out} do
      {%{"ok" => %{"set" => old}}, %{"ok" => %{"set" => new}}} ->
        old_starts = starts(old, calendar)
        Enum.all?(starts(new, calendar), &(&1 in old_starts))

      _ ->
        false
    end
  end

  defp within_period_only?(_was, _is, _calendar), do: false

  defp starts(texts, calendar) do
    Enum.map(texts, fn text ->
      case Tempo.from_iso8601(text, calendar) do
        {:ok, %Tempo{} = expression} -> start_of(expression, text)
        _ -> text
      end
    end)
  end

  defp start_of(expression, text) do
    case Spans.extent(expression) do
      {:ok, {start, _}} -> start
      _ -> text
    end
  end

  # What later phases read: selections, repeat rules, seasons; and the shapes of phase 3.
  defp phase_rules do
    walk? = fn was -> was.op in ["Enum.count/1", "Enum.take/2 24"] end

    [
      {:selection_pending, fn was, _, _ -> Regex.match?(~r/L.*N/, was.input) end},
      {:repeat_rule_pending, fn was, _, _ -> String.contains?(was.input, "/F") end},
      {:season_pending,
       fn was, _, _ ->
         Regex.match?(~r/-(2[1-9]|3[0-9]|4[01])\b|\D(2[1-9]|3[0-9]|4[01])M/, was.input)
       end},
      {:year_annotation_as_range,
       fn was, _, _ ->
         String.contains?(was.input, "±") or Regex.match?(~r/\dS\d/, was.input)
       end},
      {:members_1,
       fn was, _, _ ->
         walk?.(was) and ("plural" in was.tags or String.starts_with?(was.input, ["R", "["]))
       end},
      {:written_end_14, fn was, _, _ -> "written_end" in was.tags end}
    ]
  end

  # The one text an answer holds, tagged or not.
  defp text(%{out: %{"ok" => text}}) when is_binary(text), do: text
  defp text(%{out: %{"value" => text}}) when is_binary(text), do: text
  defp text(_cell), do: nil

  defp later_rules do
    [
      {:placed_within,
       fn was, _, _ ->
         was.op == "complement/2 within" and String.starts_with?(was.input, "R")
       end},
      {:placed_within,
       fn was, _, calendar ->
         String.ends_with?(was.op, "within 2026") and
           (not anchored?(was.input, calendar) or String.contains?(was.input, ".."))
       end},
      {:as_written_span, &as_written_span?/3},
      {:as_written, &as_written?/3},
      {:selection_pending,
       fn was, is, _ -> was.op in ["at/2", "on/2"] and is.out["reason"] == ":selection" end},
      {:gap_kept, fn was, _, _ -> Regex.match?(~r/(Y|[\d}]M|\dW)T|^\d{4}-\d{2}T/, was.input) end},
      {:member_order, fn was, is, _ -> same_members?(was.out, is.out) end},
      {:day_after_year, fn was, _, _ -> Regex.match?(~r/Y[0-9X]*XD|YX\*D/, was.input) end},
      {:written_end_14, fn was, is, calendar -> same_denotation?(was.out, is.out, calendar) end},
      {:members_not_coalesced,
       fn was, is, calendar -> members_of_one?(was.out, is.out, calendar) end},
      {:members_not_coalesced, fn was, is, _ -> "plural" in was.tags and set?(is.out) end}
    ]
  end

  # A partner written with a date end, which law 9 reads through (decision 14).
  defp date_end?(nil), do: false
  defp date_end?("self"), do: false

  defp date_end?(arg) do
    case arg |> String.trim_trailing(" |") |> String.split("/") do
      [_from, to] -> to != "" and not String.contains?(to, ["T", "H", "P", "."])
      _ -> false
    end
  end

  defp plural_text?(text),
    do: String.contains?(text, ["X", "{", "[", "R", "\u00B1"]) or Regex.match?(~r/\dS\d/, text)

  # A new answer that is the old one's members merged into the time they cover (canonical form).
  defp same_cover?(%{"ok" => %{"set" => was}}, %{"ok" => %{"set" => is}}, calendar) do
    with {:ok, old} <- all_extents(was, &old_extent(&1, calendar)),
         {:ok, new} <- all_extents(is, &new_extent(&1, calendar)) do
      merged(Enum.sort(old)) == Enum.sort(new)
    end
  end

  defp same_cover?(_was, _is, _calendar), do: false

  defp all_extents(texts, read) do
    Enum.reduce_while(texts, {:ok, []}, fn text, {:ok, acc} ->
      case read.(text) do
        {:ok, extent} -> {:cont, {:ok, acc ++ [extent]}}
        _ -> {:halt, false}
      end
    end)
  end

  defp merged([]), do: []

  defp merged([first | rest]) do
    rest
    |> Enum.reduce([first], fn {start, stop}, [{s, e} | acc] ->
      if start <= e, do: [{s, max(e, stop)} | acc], else: [{start, stop}, {s, e} | acc]
    end)
    |> Enum.reverse()
  end

  defp anchored?(input, calendar) do
    case Tempo.from_iso8601(input, calendar) do
      {:ok, %Tempo{} = expression} -> not match?({:cycle, _}, Spans.frame(expression))
      _ -> true
    end
  end

  # The new answer is the input as its own span, as `-1M/-1M` is for `-1M`.
  defp as_written_span?(%{input: input}, %{out: %{"ok" => is}}, calendar) when is_binary(is) do
    case {new_extent(input, calendar), new_extent(is, calendar)} do
      {{:ok, a}, {:ok, b}} -> a == b
      _ -> false
    end
  end

  defp as_written_span?(was, %{out: %{"ok" => %{"set" => [one | same]}}}, calendar) do
    Enum.all?(same, &(&1 == one)) and as_written_span?(was, %{out: %{"ok" => one}}, calendar)
  end

  defp as_written_span?(_was, _is, _calendar), do: false

  # A composition (`at/2`, `on/2`) that keeps the written form of the value
  # placed, where the old library resolved it: `{1..-1}M` stays `{1..-1}M`.
  defp as_written?(%{op: op, input: input}, %{out: %{"ok" => is}}, _calendar)
       when op in ["at/2", "on/2"] and is_binary(is) do
    String.ends_with?(is, Regex.replace(~r/^X\*Y/, input, ""))
  end

  defp as_written?(_was, _is, _calendar), do: false

  defp without_sets(text), do: Regex.replace(~r/\{[^}]*\}/, text, "{}")

  defp same_members?(%{"ok" => %{"set" => was}}, %{"ok" => %{"set" => is}}),
    do: Enum.sort(was) == Enum.sort(is)

  defp same_members?(_was, _is), do: false

  defp set?(%{"ok" => %{"set" => _}}), do: true
  defp set?(_out), do: false

  defp error?(%{"error" => _}), do: true
  defp error?(%{"raised" => _}), do: true
  defp error?(%{"unread" => _}), do: true
  defp error?(_out), do: false

  # Two answers that denote the same extents: the old text read with its
  # exclusive date ends, the new with its ends read through (law 9).
  defp same_denotation?(%{"ok" => was}, %{"ok" => is}, calendar),
    do: same_texts?(was, is, calendar)

  defp same_denotation?(%{"value" => was}, %{"value" => is}, calendar),
    do: same_texts?(was, is, calendar)

  defp same_denotation?(%{"value" => was}, %{"ok" => is}, calendar),
    do: same_texts?(was, is, calendar)

  defp same_denotation?(_was, _is, _calendar), do: false

  defp same_texts?(%{"set" => was}, %{"set" => is}, calendar), do: same_texts?(was, is, calendar)

  defp same_texts?(was, is, calendar)
       when is_list(was) and is_list(is) and length(was) == length(is),
       do: Enum.zip(was, is) |> Enum.all?(fn {a, b} -> same_texts?(a, b, calendar) end)

  # An answer of another calendar is written in Gregorian dates where a month
  # of one calendar is no month of another, so a text is read both ways.
  defp same_texts?(was, is, calendar) when is_binary(was) and is_binary(is) do
    Enum.any?(Enum.uniq([calendar, Calendar.ISO]), fn read_in ->
      case {old_extent(was, read_in), new_extent(is, read_in)} do
        {{:ok, a}, {:ok, b}} -> a == b
        _ -> false
      end
    end)
  end

  defp same_texts?(_was, _is, _calendar), do: false

  # A single old span whose extent the new members tile.
  defp members_of_one?(%{"ok" => was}, %{"ok" => %{"set" => members}}, calendar)
       when is_binary(was) do
    extents = Enum.map(members, &new_extent(&1, calendar))

    case old_extent(was, calendar) do
      {:ok, {start, stop}} when extents != [] ->
        Enum.all?(extents, &match?({:ok, _}, &1)) and tiles?(extents, start, stop)

      _ ->
        false
    end
  end

  defp members_of_one?(_was, _is, _calendar), do: false

  defp tiles?(extents, start, stop) do
    spans = Enum.map(extents, fn {:ok, span} -> span end)
    elem(hd(spans), 0) == start and elem(List.last(spans), 1) == stop and tiled?(spans)
  end

  defp tiled?(spans),
    do: spans |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [{_, a}, {b, _}] -> a == b end)

  # The extent an old text denoted: a span's last end was exclusive whatever it was written to.
  defp old_extent(text, calendar) do
    case Tempo.from_iso8601(text, calendar) do
      {:ok, %Tempo{form: {:span, %Tempo{} = from, %Tempo{} = to}}} -> exclusive_extent(from, to)
      {:ok, %Tempo{} = other} -> Spans.extent(other)
      _ -> :error
    end
  end

  defp exclusive_extent(from, to) do
    case {Spans.extent(from), Spans.extent(to)} do
      {{:ok, {start, _}}, {:ok, {stop, _}}} -> {:ok, {start, stop}}
      _ -> :error
    end
  end

  defp new_extent(text, calendar) do
    with {:ok, %Tempo{} = expression} <- Tempo.from_iso8601(text, calendar) do
      Spans.extent(expression)
    end
  end

  # A text the old library refused that the new reads, and reads back as the
  # same value: the reader is more permissive, as the writer is not.

  defp calendar_module(nil), do: Calendar.ISO
  defp calendar_module("Calendrical." <> _ = name), do: Module.concat([name])
  defp calendar_module(name), do: Module.concat([name])

  # What the old library resolved and the new keeps, by the shape of the texts:
  # the first description whose tests hold names the difference.
  defp kept_table do
    [
      {:century_or_decade_kept, &String.contains?(&1, ["C", "J"]), &String.contains?(&1, "G")},
      {:week_or_ordinal_kept, &String.contains?(&1, ["W", "O", "K"]),
       &(not String.contains?(&1, ["W", "O", "K"]))},
      {:season_or_division_kept, &Regex.match?(~r/(2[1-9]|3[0-9]|4[01])M/, &1),
       &(not Regex.match?(~r/(2[1-9]|3[0-9]|4[01])M/, &1))},
      {:range_of_values_kept, &String.contains?(&1, ".."), &(not String.contains?(&1, ".."))},
      {:set_members_kept, &(not String.contains?(&1, "..")), &String.contains?(&1, "..")},
      {:set_of_values_kept, &String.contains?(&1, "{"), &(not String.contains?(&1, "{"))},
      {:gap_kept, &(not String.contains?(&1, "1D")), &String.contains?(&1, "1D")},
      {:gap_kept, &(not String.contains?(&1, "1M")), &String.contains?(&1, "1M")},
      {:group_kept, &String.contains?(&1, "G"), &(not String.contains?(&1, "G"))},
      {:count_from_end_kept, &String.contains?(&1, "-"), &(not String.contains?(&1, "-"))},
      {:interval_ends_kept, &String.contains?(&1, "/"), fn _ -> true end}
    ]
  end

  defp kept(_input, was, is) do
    Enum.find_value(kept_table(), :as_written, fn {decision, is?, was?} ->
      if is?.(is) and was?.(was), do: decision
    end)
  end
end
