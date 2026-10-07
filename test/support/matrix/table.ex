defmodule Tempo.Matrix.Table do
  @moduledoc """
  The matrix as the table a guide publishes: what each kind of operation
  gives each class of value (see `plans/validated-core.md`).

  A row is a class of the hand-written corpus, shown by its first value,
  and a column a kind of operation. A cell counts functions, not the cells
  of a run: it is `all` when every function of the kind answers for the
  value, and otherwise how many do. The row's last column names the errors
  of those that do not.

  A function answers for a value when it answers with some argument and,
  where it takes two values, with some other value in either place:
  `Tempo.round/2` answers for a date since a date rounds to a month,
  though not to an hour. A bang form is the function it is the bang form
  of. A walk is asked of the value itself, so `Enum.member?/2` counts only
  where the value is what is walked.

  The table is text, generated from the cells of a run, and
  `guides/operation-matrix.md` holds it between two markers. The matrix
  test fails when the guide's text is not what the code gives.

  """

  alias Tempo.Matrix.Census
  alias Tempo.Matrix.Corpus
  alias Tempo.Matrix.Operations

  @kinds [
    convert: "Convert",
    walk: "Walk",
    measure: "Measure",
    compare: "Compare",
    combine: "Combine",
    arithmetic: "Shift and round",
    select: "Select",
    format: "Format",
    parts: "Read parts"
  ]

  @levels [core: "Core", extended: "Extended", open: "Open"]

  @start "<!-- matrix: generated, do not edit by hand -->"
  @finish "<!-- matrix: end -->"

  @doc """
  The kinds of operation the table has a column for, with their headings.

  ### Returns

  * A keyword list of the operation group and its heading.

  """
  @spec kinds() :: keyword(String.t())
  def kinds, do: @kinds

  @doc """
  The functions of each kind of operation, as the table counts them: a
  bang form with its function, and each function once however many
  arguments the matrix gives it.

  ### Returns

  * A keyword list of the operation group and its functions' names, in the
    order the matrix runs them.

  """
  @spec functions() :: keyword([String.t()])
  def functions do
    operations = Operations.unary() ++ Operations.binary()

    for {kind, _heading} <- @kinds do
      names = for {name, ^kind, _raises, _function} <- operations, do: function_name(name)
      {kind, Enum.uniq(names)}
    end
  end

  @doc """
  The table of a run, as Markdown: the functions of each column, and one
  table for each level of guarantee.

  ### Arguments

  * `cells` is what `Tempo.Matrix.Census.run/2` returned.

  ### Returns

  * The Markdown text, from the start marker to the end marker.

  """
  @spec render([Census.cell()]) :: String.t()
  def render(cells) do
    functions = functions()
    answers = answers(cells)

    tables =
      for {level, heading} <- @levels do
        rows = for example <- examples(level), do: row(example, functions, answers)

        "### #{heading}\n\n" <> header() <> Enum.join(rows, "\n")
      end

    Enum.join([@start, key(functions)] ++ tables ++ [@finish], "\n\n")
  end

  @doc """
  The table a guide's text holds, or `nil` when it has none.

  ### Arguments

  * `guide` is the guide's Markdown.

  ### Returns

  * The text from the start marker to the end marker, or `nil`.

  """
  @spec published(String.t()) :: String.t() | nil
  def published(guide) do
    with [_before, rest] <- String.split(guide, @start, parts: 2),
         [table, _after] <- String.split(rest, @finish, parts: 2) do
      @start <> table <> @finish
    else
      _no_table -> nil
    end
  end

  @doc """
  A guide's text with its table replaced.

  ### Arguments

  * `guide` is the guide's Markdown, holding the two markers.

  * `table` is what `render/1` returned.

  ### Returns

  * The guide's text with `table` between its markers.

  """
  @spec replace(String.t(), String.t()) :: String.t()
  def replace(guide, table) do
    [before, rest] = String.split(guide, @start, parts: 2)
    [_old, rest] = String.split(rest, @finish, parts: 2)
    before <> table <> rest
  end

  @doc """
  The errors a table names, each once.

  ### Arguments

  * `table` is what `render/1` or `published/1` returned.

  ### Returns

  * A sorted list of the exception modules' names.

  """
  @spec errors_named(String.t()) :: [String.t()]
  def errors_named(table) do
    table
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "| "))
    |> Enum.flat_map(&(&1 |> String.split(" | ") |> List.last() |> code_spans()))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp code_spans(text) do
    for [_whole, name] <- Regex.scan(~r/`([^`]+)`/, text), do: name
  end

  # What each function gave each value: the outcomes of the cells that ask
  # the function of the value, by class, value and function.
  defp answers(cells) do
    cells
    |> Enum.filter(&asked_of_value?/1)
    |> Enum.group_by(&{&1.class, &1.value, function_name(&1.operation)}, & &1.outcome)
  end

  # Reading a text and the consistency checks are not operations a class is
  # asked, and a walk is asked of the value itself: membership in another
  # value's walk says nothing of the class.
  defp asked_of_value?(%{group: group}) when group in [:parse, :consistent], do: false

  defp asked_of_value?(%{group: :walk, value: value, arguments: arguments}) do
    arguments == value or String.starts_with?(arguments, value <> " | ")
  end

  defp asked_of_value?(_cell), do: true

  # An operation's name is its function and, after a space, the argument
  # the matrix gives it. A bang form is its function.
  defp function_name(operation) do
    operation |> String.split(" ", parts: 2) |> hd() |> String.replace("!", "")
  end

  # Each class of a level in the corpus's order, with the value that stands
  # for it: its first, as the text it is written as and the label the run's
  # cells carry.
  defp examples(level) do
    Corpus.written()
    |> Enum.filter(&(&1.level == level))
    |> Enum.uniq_by(& &1.class)
    |> Enum.map(&{&1.class, &1.text, Census.label(&1)})
  end

  defp key(functions) do
    items =
      for {kind, heading} <- @kinds do
        names = Enum.map_join(functions[kind], ", ", &"`#{qualified(&1)}`")
        "* **#{heading}** — #{names}."
      end

    "### The functions of each column\n\n" <> Enum.join(items, "\n\n")
  end

  # A name with no module is a function of `Tempo`.
  defp qualified(name) do
    if String.contains?(name, "."), do: name, else: "Tempo." <> name
  end

  defp header do
    headings = Enum.map_join(@kinds, " | ", fn {_kind, heading} -> heading end)
    separator = String.duplicate("---|", length(@kinds) + 2)

    "| Class | #{headings} | Errors |\n|#{separator}\n"
  end

  # A row is one line of its table, with no line end of its own.

  defp row({class, text, label}, functions, answers) do
    given = fn function -> Map.get(answers, {class, label, function}, []) end

    columns =
      Enum.map_join(@kinds, " | ", fn {kind, _heading} ->
        cell(Enum.count(functions[kind], &answers?(given.(&1))), length(functions[kind]))
      end)

    refused =
      for {_kind, names} <- functions, name <- names, not answers?(given.(name)) do
        given.(name)
      end

    "| #{name(class)} `#{text}` | #{columns} | #{errors(refused)} |"
  end

  # A function answers for a value when one of the cells that ask it does.
  defp answers?(outcomes), do: Enum.any?(outcomes, &(&1 in [:ok, :value]))

  # What a class is called in the table, where its name in the corpus does
  # not read as one.
  @names %{
    date_hour: "Date and hour",
    date_minute: "Date and minute",
    date_second: "Date and second",
    date_fraction: "Date and fraction",
    date_microsecond: "Date and microsecond",
    utc: "UTC",
    cycle_end: "Last of its cycle",
    interval_closed: "Interval",
    interval_start_duration: "Interval, start and duration",
    interval_duration_end: "Interval, duration and end",
    interval_open_end: "Interval, open end",
    interval_open_start: "Interval, open start",
    interval_open: "Interval, open both ends",
    interval_no_year: "Interval, no year",
    interval_no_year_open: "Interval, no year, open end",
    interval_two_resolutions: "Interval, two resolutions",
    interval_two_axes: "Interval, week to date",
    interval_zoned: "Interval, zoned",
    interval_two_zones: "Interval, two zones",
    recurrence_count: "Recurrence, counted",
    recurrence_unending: "Recurrence, unending",
    recurrence_selection: "Recurrence, selecting",
    duration_set: "Set of durations",
    component_set: "Set in a unit",
    component_range: "Range in a unit",
    value_set_all: "Set of values",
    value_set_one: "One of a set",
    set_range: "Range of values",
    calendar_hebrew: "Hebrew calendar",
    calendar_weeks: "Week calendar",
    year_mask: "Masked year",
    mask_partial: "Partly masked unit",
    mask_full: "Masked unit",
    mask_tail: "Mask before a unit",
    unspecified: "Unspecified unit",
    margin: "Margin of error",
    count_from_end: "Count from the end",
    value_selection: "Selection",
    week_of_month: "Week of a month",
    mask_from_end: "Mask from the end",
    mask_narrow: "Mask of fewer digits",
    date_gap: "Time on a year or month",
    recurrence_exotic_start: "Recurrence from a masked day",
    set_exotic: "Set with a day a month lacks",
    group_of_set: "Group of a set",
    interval_exotic_end: "Interval from a masked day",
    no_year_masked: "Masked day, no year"
  }

  defp name(class) when is_map_key(@names, class), do: @names[class]

  defp name(class) do
    class |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp cell(count, count), do: "all"
  defp cell(0, _of), do: "none"
  defp cell(count, of), do: "#{count} of #{of}"

  # The errors of the functions that have no answer for a value.
  defp errors(refused) do
    case refused |> List.flatten() |> Enum.flat_map(&error/1) |> Enum.uniq() |> Enum.sort() do
      [] -> "none"
      errors -> Enum.map_join(errors, ", ", &"`#{&1}`")
    end
  end

  defp error({:error, module}), do: [inspect(module)]
  defp error({:raised, module}), do: [inspect(module)]
  defp error(_outcome), do: []
end
