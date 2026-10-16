defmodule Tempo.Conformance do
  @moduledoc false

  # The conformance fixtures under test/fixtures/conformance/: the oracles
  # of test/support exported as JSON, which a port of Tempo runs from its
  # own test suite and Tempo's own tests read here, so that the two cannot
  # drift. `scripts/conformance_fixtures.exs` writes them.

  alias Tempo.GuidesRunner
  alias Tempo.Interval
  alias Tempo.Matrix.CalendarCensus
  alias Tempo.Matrix.Selections

  @dir Path.expand("../fixtures/conformance", __DIR__)

  @doc "A fixture by name, decoded: `fixture(\"allen\")` reads `allen.json`."
  @spec fixture(String.t()) :: map()
  # JSON's null is Elixir's nil, which Erlang's decoder would read as :null.
  def fixture(name) do
    {decoded, :ok, rest} =
      @dir |> Path.join(name <> ".json") |> File.read!() |> :json.decode(:ok, %{null: nil})

    "" = String.trim(rest)
    decoded
  end

  @doc "The path of the fixtures, for a message."
  @spec dir() :: String.t()
  def dir, do: @dir

  @doc """
  What a cell of the matrix answered, as the expressions fixture records
  it: `answer` for a value, an error by its name and reason, a raise by its
  name, or unread for text the grammar refuses.
  """
  @spec kind(map()) :: String.t()
  def kind(%{"ok" => _}), do: "answer"
  def kind(%{"value" => _}), do: "answer"
  def kind(%{"error" => module, "reason" => reason}), do: "error #{module} #{reason}"
  def kind(%{"raised" => module}), do: "raised #{module}"
  def kind(%{"unread" => module}), do: "unread #{module}"

  # ── The guides' examples ──────────────────────────────────────────────

  @doc "The pages whose examples the guides fixture records: the README and every guide."
  @spec guide_pages() :: [Path.t()]
  def guide_pages do
    ["README.md" | Enum.sort(Path.wildcard("guides/*.md"))]
  end

  @doc """
  The calls the guides' examples make into Tempo, `Enum` and `Stream`, as
  the guides fixture holds them: each with its page, its example, the
  example's code, the call by name and arity, its arguments and its answer,
  in terms JSON decodes to. The clock is pinned while they run.

  ### Returns

  * A list of maps, one a call, in the order the pages make them.

  """
  @spec guides() :: [map()]
  def guides do
    for page <- guide_pages(), call <- GuidesRunner.calls(page) do
      %{
        "page" => page,
        "example" => call.example,
        "code" => call.code,
        "call" => "#{inspect(call.module)}.#{call.function}/#{length(call.arguments)}",
        "arguments" => Enum.map(call.arguments, &data/1),
        "answer" => data(call.answer)
      }
    end
  end

  @doc """
  A term in the terms JSON decodes to: an expression or a duration by its
  ISO 8601 text, Elixir's dates and times by theirs, an error by its name
  and reason, and every other term tagged by its kind.
  """
  @spec data(term()) :: term()
  def data({:ok, value}) do
    %{"ok" => data(value)}
  end

  def data({:error, error}) do
    %{"error" => data(error)}
  end

  def data(%Tempo{} = expression) do
    case Tempo.to_iso8601(expression) do
      {:ok, text} -> %{"tempo" => text}
      {:error, _no_text} -> %{"tempo" => nil, "inspect" => inspect(expression, limit: :infinity)}
    end
  end

  def data(%Tempo.Duration{} = duration) do
    %{"duration" => Tempo.to_iso8601!(duration)}
  end

  def data(%Date{} = date) do
    %{"date" => Date.to_iso8601(date), "calendar" => inspect(date.calendar)}
  end

  def data(%Time{} = time) do
    %{"time" => Time.to_iso8601(time)}
  end

  def data(%NaiveDateTime{} = naive) do
    %{"naive_datetime" => NaiveDateTime.to_iso8601(naive)}
  end

  def data(%DateTime{} = datetime) do
    %{"datetime" => DateTime.to_iso8601(datetime), "zone" => datetime.time_zone}
  end

  def data(%Date.Range{first: first, last: last, step: step}) do
    %{"date_range" => [data(first), data(last), step]}
  end

  def data(%Range{first: first, last: last, step: step}) do
    %{"range" => [first, last, step]}
  end

  def data(%{__exception__: true, __struct__: module} = error) do
    %{"exception" => inspect(module), "reason" => data(Map.get(error, :reason))}
  end

  def data(%{__struct__: module} = struct) do
    %{"struct" => inspect(module), "fields" => data(Map.from_struct(struct))}
  end

  def data(map) when is_map(map) do
    pairs =
      map
      |> Enum.map(fn {key, value} -> [data(key), data(value)] end)
      |> Enum.sort_by(&inspect/1)

    %{"map" => pairs}
  end

  def data(tuple) when is_tuple(tuple) do
    %{"tuple" => Enum.map(Tuple.to_list(tuple), &data/1)}
  end

  def data([{key, _} | _] = list) when is_atom(key) do
    if Keyword.keyword?(list) do
      %{"keyword" => Enum.map(list, fn {key, value} -> [Atom.to_string(key), data(value)] end)}
    else
      Enum.map(list, &data/1)
    end
  end

  def data(list) when is_list(list) do
    Enum.map(list, &data/1)
  end

  def data(value) when is_boolean(value) or is_nil(value) do
    value
  end

  def data(atom) when is_atom(atom) do
    atom_data(Atom.to_string(atom), atom)
  end

  def data(value) when is_integer(value) or is_float(value) do
    value
  end

  def data(binary) when is_binary(binary) do
    if String.printable?(binary) do
      binary
    else
      %{"bytes" => Base.encode64(binary)}
    end
  end

  def data(function) when is_function(function) do
    %{"opaque" => "function"}
  end

  def data(_pid_reference_or_port) do
    %{"opaque" => "process"}
  end

  defp atom_data("Elixir." <> _name, module) do
    %{"module" => inspect(module)}
  end

  defp atom_data(name, _atom) do
    %{"atom" => name}
  end

  # ── The calendar census ───────────────────────────────────────────────

  @doc """
  The calendar census (`Tempo.Matrix.CalendarCensus`) as the census fixture
  holds it, in the terms JSON decodes to: each calendar's name and IXDTF
  identifier, and each full form, value with no year and shape with its
  parts and what the calendar alone says it covers and yields. The
  observational Islamic calendars are left out, as the census leaves them.

  ### Returns

  * A map of `"calendars"`, `"forms"`, `"no_year"`, `"shapes"` and
    `"selections"` to lists of entries.

  """
  @spec census() :: %{String.t() => [map()]}
  def census do
    calendars = CalendarCensus.calendars() -- CalendarCensus.observed()

    forms =
      for calendar <- calendars, form <- CalendarCensus.forms(calendar) do
        form_entry(form, calendar)
      end

    no_year =
      for calendar <- calendars, value <- CalendarCensus.no_year(calendar) do
        no_year_entry(value, calendar)
      end

    shapes =
      for calendar <- calendars, shape <- CalendarCensus.shapes(calendar) do
        shape_entry(shape, calendar)
      end

    selections =
      for calendar <- calendars, selection <- CalendarCensus.selections(calendar) do
        selection_entry(selection, calendar)
      end

    %{
      "calendars" => Enum.map(calendars, &calendar_entry/1),
      "forms" => forms,
      "no_year" => no_year,
      "shapes" => shapes,
      "selections" => selections
    }
  end

  @doc """
  A census entry's parts, as the fixture writes them, read back into the
  census's own `t:Tempo.Matrix.CalendarCensus.parts/0`.

  ### Arguments

  * `parts` is the `"parts"` of a fixture entry.

  ### Returns

  * `{:value, units}`, `{:span, units, units}` or
    `{:every, count, units, units}`.

  """
  @spec parts(map()) :: CalendarCensus.parts()
  def parts(%{"value" => units}) do
    {:value, units(units)}
  end

  def parts(%{"span" => [from, to]}) do
    {:span, units(from), units(to)}
  end

  def parts(%{"every" => %{"count" => count, "from" => from, "cadence" => cadence}}) do
    {:every, count, units(from), units(cadence)}
  end

  @doc """
  A census entry's parts, built in a calendar.

  ### Arguments

  * `parts` is a `t:Tempo.Matrix.CalendarCensus.parts/0`.

  * `calendar` is a calendar module.

  ### Returns

  * `{:ok, expression}` or `{:error, exception}`.

  """
  @spec built(CalendarCensus.parts(), module()) :: {:ok, Tempo.t()} | {:error, Exception.t()}
  def built({:value, units}, calendar) do
    Tempo.new(units ++ [calendar: calendar])
  end

  def built({:span, from, to}, calendar) do
    with {:ok, from} <- built({:value, from}, calendar),
         {:ok, to} <- built({:value, to}, calendar) do
      Interval.new(from: from, to: to)
    end
  end

  def built({:every, count, start, cadence}, calendar) do
    with {:ok, start} <- built({:value, start}, calendar) do
      Tempo.every(cadence, from: start, count: count)
    end
  end

  @doc """
  A census selection built as the census builds it: its period, its parts
  selected in it with `Tempo.selection/2`, the one placed on the other.

  ### Arguments

  * `period` and `parts` are keyword lists, as `units_of/1` reads them.

  * `calendar` is a calendar module.

  ### Returns

  * `{:ok, value}` or `{:error, exception}`.

  """
  @spec selection_built(keyword(), keyword(), module()) ::
          {:ok, Tempo.t()} | {:error, Exception.t()}
  def selection_built(period, parts, calendar) do
    options = Selections.in_calendar(calendar)

    with {:ok, period} <- Tempo.new(period ++ options),
         {:ok, selection} <- Tempo.selection(parts, options) do
      Tempo.on(selection, period)
    end
  end

  @doc "Units or parts as the fixture writes them, read back into a keyword list."
  @spec units_of([[term()]]) :: keyword()
  def units_of(pairs) do
    units(pairs)
  end

  @doc "A calendar's name in the fixtures: the module, as Elixir writes it."
  @spec calendar_name(module()) :: String.t()
  def calendar_name(calendar) do
    inspect(calendar)
  end

  defp calendar_entry(calendar) do
    %{"calendar" => calendar_name(calendar), "ixdtf" => identifier(calendar)}
  end

  # The calendar's name in an IXDTF suffix, or nil for one with none.
  defp identifier(calendar) do
    case Tempo.Calendar.identifier(calendar) do
      {:ok, name} -> name
      {:error, _no_name} -> nil
    end
  end

  defp form_entry(%{form: form, parts: parts, expect: expect}, calendar) do
    {span, walk} = CalendarCensus.expected(expect, calendar)

    %{
      "calendar" => calendar_name(calendar),
      "form" => form,
      "parts" => encoded(parts),
      "text" => text(parts, calendar),
      "extent" => span_data(span),
      "walk" => spans_data(walk)
    }
  end

  defp no_year_entry(%{parts: parts, covers: covers, walk: walk}, calendar) do
    %{
      "calendar" => calendar_name(calendar),
      "parts" => encoded(parts),
      "text" => text(parts, calendar),
      "covers" => covers_data(covers),
      "walk" => no_year_walk_data(walk)
    }
  end

  defp shape_entry(%{shape: shape, parts: parts, members: members, walk: walk}, calendar) do
    %{
      "calendar" => calendar_name(calendar),
      "shape" => shape,
      "parts" => encoded(parts),
      "text" => text(parts, calendar),
      "members" => Enum.map(members, &spans_data/1),
      "walk" => starts_data(walk)
    }
  end

  defp selection_entry(%{scenario: scenario, datum: datum, selected: selected}, calendar) do
    parts = Selections.parts(datum)

    %{
      "calendar" => calendar_name(calendar),
      "scenario" => scenario,
      "period" => encoded_units(datum.period),
      "selection" => encoded_units(parts),
      "text" => selection_text(datum.period, parts, calendar),
      "selected" => selected_data(selected)
    }
  end

  defp selection_text(period, parts, calendar) do
    with {:ok, value} <- selection_built(period, parts, calendar),
         {:ok, text} <- Tempo.to_iso8601(value) do
      text
    else
      {:error, _no_text} -> nil
    end
  end

  defp selected_data(:no_such_value) do
    "no_such_value"
  end

  defp selected_data(occurrences) do
    Enum.map(occurrences, &spans_data/1)
  end

  # The text Tempo writes for the parts, for a port's reader; nil where the
  # parts build nothing or the value has no text.
  defp text(parts, calendar) do
    with {:ok, value} <- built(parts, calendar),
         {:ok, text} <- Tempo.to_iso8601(value) do
      text
    else
      {:error, _no_text} -> nil
    end
  end

  defp span_data({from, to}) do
    [from, to]
  end

  defp spans_data(:unchecked) do
    nil
  end

  defp spans_data(spans) do
    Enum.map(spans, &span_data/1)
  end

  defp covers_data({:ok, span}) do
    span_data(span)
  end

  defp covers_data(reason) do
    Atom.to_string(reason)
  end

  defp no_year_walk_data({:ok, starts}) do
    %{"starts" => starts}
  end

  defp no_year_walk_data({:count, count}) do
    %{"count" => count}
  end

  defp no_year_walk_data(:unchecked) do
    nil
  end

  defp no_year_walk_data(reason) do
    Atom.to_string(reason)
  end

  defp starts_data({:ok, starts}) do
    starts
  end

  defp starts_data(:unchecked) do
    nil
  end

  # ── Parts, written and read ───────────────────────────────────────────

  # A unit and what it holds, as a pair: a whole number, a set of numbers
  # and ranges, a mask of digits and X, any value, a fraction of a second
  # as its microseconds and the places written, or a zone's name.
  defp encoded({:value, units}) do
    %{"value" => encoded_units(units)}
  end

  defp encoded({:span, from, to}) do
    %{"span" => [encoded_units(from), encoded_units(to)]}
  end

  defp encoded({:every, count, start, cadence}) do
    %{
      "every" => %{
        "count" => count,
        "from" => encoded_units(start),
        "cadence" => encoded_units(cadence)
      }
    }
  end

  defp encoded_units(units) do
    Enum.map(units, fn {unit, held} -> [Atom.to_string(unit), held_data(held)] end)
  end

  defp held_data(held) when is_integer(held) or is_binary(held) do
    held
  end

  defp held_data(held) when is_list(held) do
    %{"set" => Enum.map(held, &member_data/1)}
  end

  defp held_data({:mask, digits}) do
    %{"mask" => Enum.map_join(digits, &digit/1)}
  end

  defp held_data(:any) do
    "any"
  end

  defp held_data({microseconds, places}) do
    %{"fraction" => [microseconds, places]}
  end

  defp member_data(%Range{first: first, last: last, step: 1}) do
    %{"range" => [first, last]}
  end

  defp member_data(value) when is_integer(value) do
    value
  end

  defp digit(:x) do
    "X"
  end

  defp digit(digit) do
    Integer.to_string(digit)
  end

  defp units(pairs) do
    Enum.map(pairs, fn [unit, held] -> unit(String.to_existing_atom(unit), held) end)
  end

  defp unit(:zone, name) do
    {:zone, name}
  end

  defp unit(unit, held) do
    {unit, held(held)}
  end

  defp held(held) when is_integer(held) do
    held
  end

  defp held("any") do
    :any
  end

  defp held(%{"set" => members}) do
    Enum.map(members, &member/1)
  end

  defp held(%{"mask" => digits}) do
    {:mask, Enum.map(String.graphemes(digits), &read_digit/1)}
  end

  defp held(%{"fraction" => [microseconds, places]}) do
    {microseconds, places}
  end

  defp member(%{"range" => [first, last]}) do
    first..last//1
  end

  defp member(value) when is_integer(value) do
    value
  end

  defp read_digit("X") do
    :x
  end

  defp read_digit(digit) do
    String.to_integer(digit)
  end
end
