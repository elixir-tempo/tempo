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

  alias Tempo.Matrix.Corpus
  alias Tempo.Spans

  @dir "test/golden"

  # The groups the new library answers so far; the rest come with their phases.
  @groups [:read, :walk, :convert]
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

  defp key(cell), do: {cell.op, cell.input, cell.calendar}

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
  defp operations(:walk) do
    %{
      "Enum.take/2 24" => &Enum.take(&1, @take),
      "Enum.count/1" => &Enum.count/1
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

  defp data(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value

  defp data(value), do: inspect(value, limit: :infinity)

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
  defp decision(%{group: group} = was, is) when group in [:walk, :convert] do
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
  defp rules do
    walk? = fn was -> was.op in ["Enum.count/1", "Enum.take/2 24"] end

    [
      {:named_error_12, fn was, is, _ -> error?(was.out) and error?(is.out) end},
      {:selection_pending, fn was, _, _ -> Regex.match?(~r/L.*N/, was.input) end},
      {:repeat_rule_pending, fn was, _, _ -> String.contains?(was.input, "/F") end},
      {:season_pending,
       fn was, _, _ ->
         Regex.match?(~r/-(2[1-9]|3[0-9]|4[01])\b|\D(2[1-9]|3[0-9]|4[01])M/, was.input)
       end},
      {:year_annotation_as_range,
       fn was, _, _ ->
         String.contains?(was.input, "\u00B1") or Regex.match?(~r/\dS\d/, was.input)
       end},
      {:members_1,
       fn was, _, _ ->
         walk?.(was) and ("plural" in was.tags or String.starts_with?(was.input, ["R", "["]))
       end},
      {:written_end_14, fn was, _, _ -> "written_end" in was.tags end},
      {:placed_within,
       fn was, _, calendar ->
         String.ends_with?(was.op, "within 2026") and
           (not anchored?(was.input, calendar) or String.contains?(was.input, ".."))
       end},
      {:as_written_span, &as_written_span?/3},
      {:gap_kept, fn was, _, _ -> Regex.match?(~r/(Y|\dM|\dW)T|^\d{4}-\d{2}T/, was.input) end},
      {:member_order, fn was, is, _ -> same_members?(was.out, is.out) end},
      {:day_after_year, fn was, _, _ -> Regex.match?(~r/Y[0-9X]*XD|YX\*D/, was.input) end},
      {:written_end_14, fn was, is, calendar -> same_denotation?(was.out, is.out, calendar) end},
      {:members_not_coalesced,
       fn was, is, calendar -> members_of_one?(was.out, is.out, calendar) end},
      {:members_not_coalesced, fn was, is, _ -> "plural" in was.tags and set?(is.out) end}
    ]
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

  defp as_written_span?(_was, _is, _calendar), do: false

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

  defp same_denotation?(_was, _is, _calendar), do: false

  defp same_texts?(%{"set" => was}, %{"set" => is}, calendar), do: same_texts?(was, is, calendar)

  defp same_texts?(was, is, calendar)
       when is_list(was) and is_list(is) and length(was) == length(is),
       do: Enum.zip(was, is) |> Enum.all?(fn {a, b} -> same_texts?(a, b, calendar) end)

  defp same_texts?(was, is, calendar) when is_binary(was) and is_binary(is) do
    case {old_extent(was, calendar), new_extent(is, calendar)} do
      {{:ok, a}, {:ok, b}} -> a == b
      _ -> false
    end
  end

  defp same_texts?(_was, _is, _calendar), do: false

  # A single old span whose extent the new members tile.
  defp members_of_one?(%{"ok" => was}, %{"ok" => %{"set" => members}}, calendar)
       when is_binary(was) do
    with {:ok, {start, stop}} <- old_extent(was, calendar),
         extents when extents != [] <- Enum.map(members, &new_extent(&1, calendar)),
         true <- Enum.all?(extents, &match?({:ok, _}, &1)) do
      spans = Enum.map(extents, fn {:ok, span} -> span end)
      elem(hd(spans), 0) == start and elem(List.last(spans), 1) == stop and tiled?(spans)
    else
      _ -> false
    end
  end

  defp members_of_one?(_was, _is, _calendar), do: false

  defp tiled?(spans),
    do: spans |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [{_, a}, {b, _}] -> a == b end)

  # The extent an old text denoted: a span's last end was exclusive whatever it was written to.
  defp old_extent(text, calendar) do
    with {:ok, %Tempo{form: {:span, %Tempo{} = from, %Tempo{} = to}}} <-
           Tempo.from_iso8601(text, calendar),
         {:ok, {start, _}} <- Spans.extent(from),
         {:ok, {stop, _}} <- Spans.extent(to) do
      {:ok, {start, stop}}
    else
      {:ok, %Tempo{} = other} -> Spans.extent(other)
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
