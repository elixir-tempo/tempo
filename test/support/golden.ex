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

  @dir "test/golden"

  # The groups the new library answers so far; the rest come with their phases.
  @groups [:read]

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
        recorded = read(Path.join(dir, "#{group}.jsonl.gz")),
        {was, is} <- Enum.zip(recorded, cells(group)),
        was.out != is.out do
      %{was: was, is: is, decision: decision(was, is)}
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

  # A text the old library refused that the new reads, and reads back as the
  # same value: the reader is more permissive, as the writer is not.
  defp decision(%{out: %{"unread" => _}}, %{input: input, calendar: calendar, out: %{"ok" => is}}) do
    read = fn text -> Tempo.from_iso8601(text, calendar_module(calendar)) end
    if match?({:ok, _}, read.(input)) and read.(is) == read.(input), do: :now_read, else: nil
  end

  defp decision(_was, _is), do: nil

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
