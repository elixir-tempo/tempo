defmodule Tempo.Explain do
  @moduledoc """
  A description of an expression in prose: what it is, the time it covers,
  the frame it is in and what walking it gives.

  `Tempo.explain/1` joins the lines; `lines/1` gives them one by one for a
  caller that styles them.

  """

  alias Tempo.{Duration, Format, Parts, Spans, Unit}

  @weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  @doc """
  The lines that describe an expression.

  ### Arguments

  * `expression` is a `t:Tempo.t/0` or a `t:Tempo.Duration.t/0`; anything
    else is described as a value Tempo does not know.

  ### Returns

  * A list of strings, the first saying what the expression is.

  ### Examples

      iex> Tempo.Explain.lines(~o"2026-06-15")
      [
        "A value written to the day: Jun 15, 2026.",
        "It covers 2026Y6M15D through 2026Y6M15D.",
        "It is floating: a reading of a clock in no zone.",
        "Walking it gives its hours."
      ]

  """
  @spec lines(term()) :: [String.t()]
  def lines(%Duration{} = duration),
    do: ["A duration, a length of time with no place on the time line: #{words(duration)}."]

  def lines(%Tempo{form: {kind, [%Duration{} | _] = members}}) when kind in [:all, :one],
    do: [
      "A set of #{length(members)} durations: lengths of time, with no place on the time line."
    ]

  def lines(%Tempo{} = expression) do
    [
      what(expression),
      covers(expression),
      calendar(expression),
      frame(expression),
      qualified(expression),
      walk(expression)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  def lines(other), do: ["#{inspect(other)} is not a value Tempo knows."]

  # ── What it is ────────────────────────────────────────────────────────

  defp what(%Tempo{form: {:value, units}} = value) do
    cond do
      Keyword.has_key?(units, :selection) ->
        "A selection: the values its rule picks in the period before it#{worded(value)}."

      Unit.concrete?(units) ->
        "A value written to the #{unit_name(Parts.resolution(value))}#{worded(value)}."

      masked?(units) ->
        "A value with unspecified digits, some one of the values they allow, written to the #{unit_name(Parts.resolution(value))}#{worded(value)}."

      true ->
        "A value that names several, written to the #{unit_name(Parts.resolution(value))}#{worded(value)}."
    end
  end

  defp what(%Tempo{form: {:span, :open, :open}}),
    do: "An interval open at both ends: all of time."

  defp what(%Tempo{form: {:span, :open, _}}), do: "An interval with an open start."
  defp what(%Tempo{form: {:span, _, :open}}), do: "An interval with an open end."
  defp what(%Tempo{form: {:span, _, _}} = span), do: "An interval#{worded(span)}."

  defp what(%Tempo{form: {:every, first, bound, rule}}),
    do: "A recurrence#{bound_words(bound)}#{rule_words(rule, first)}."

  defp what(%Tempo{form: {:all, members}}),
    do: "A set of #{length(members)} members, all of which it names."

  defp what(%Tempo{form: {:one, members}}),
    do: "A choice of #{length(members)} alternatives, one of which is meant."

  defp what(%Tempo{form: {:when, _, _}}),
    do: "A member of a set whose occurrences depend on the other members'."

  # What a rule selects in each repeat, part by part as it is written.
  defp rule_words(nil, _first), do: ""

  defp rule_words(rule, first),
    do: ". In each repeat#{cadence_words(first)} it selects #{parts_words(rule)}"

  defp cadence_words(%Tempo{form: {:span, _, %Duration{} = cadence}}), do: " of #{words(cadence)}"
  defp cadence_words(%Tempo{form: {:span, %Duration{} = cadence, _}}), do: " of #{words(cadence)}"
  defp cadence_words(_first), do: ""

  defp parts_words(parts), do: Enum.map_join(parts, ", ", &part_words/1)

  defp part_words({:day_of_week, held}), do: held_words(held, &weekday/1)
  defp part_words({:instance, held}), do: "the #{held_words(held, &nth/1)} of them"
  defp part_words({:event, {name, _}}), do: "the day of #{name}"
  defp part_words({:selection, parts}), do: "(#{parts_words(parts)})"
  defp part_words({:window, %Duration{} = length}), do: "a window of #{Tempo.to_iso8601!(length)}"
  defp part_words({:day_of_year, held}), do: "day #{held_words(held, &counted/1)} of the year"
  defp part_words({unit, n}) when is_integer(n) and n < 0, do: "#{counted(n)} #{unit_name(unit)}"
  defp part_words({unit, held}), do: "#{unit_name(unit)} #{held_words(held, &counted/1)}"

  # What a part holds, in words: one value, or a list of values and ranges.
  defp held_words(held, word) when is_list(held),
    do: held |> Enum.map(&run_words(&1, word)) |> listed()

  defp held_words(held, word), do: run_words(held, word)

  defp run_words(%Range{first: first, last: last}, word), do: "#{word.(first)} to #{word.(last)}"
  defp run_words(value, word), do: word.(value)

  defp listed([one]), do: one

  defp listed(several),
    do: Enum.join(Enum.drop(several, -1), ", ") <> " and " <> List.last(several)

  defp weekday(day) when day in 1..7, do: Enum.at(@weekdays, day - 1)
  defp weekday(day), do: counted(day)

  # A count from the end is said from the end.
  defp counted(-1), do: "the last"
  defp counted(n) when is_integer(n) and n < 0, do: "the #{ordinal(-n)} from the last"
  defp counted(n) when is_integer(n), do: Integer.to_string(n)
  defp counted(other), do: inspect(other)

  defp nth(-1), do: "last"
  defp nth(n) when is_integer(n) and n < 0, do: "#{ordinal(-n)} from the last"
  defp nth(n) when is_integer(n), do: ordinal(n)
  defp nth(other), do: inspect(other)

  defp ordinal(n) when rem(n, 100) in 11..13, do: "#{n}th"
  defp ordinal(n) when rem(n, 10) == 1, do: "#{n}st"
  defp ordinal(n) when rem(n, 10) == 2, do: "#{n}nd"
  defp ordinal(n) when rem(n, 10) == 3, do: "#{n}rd"
  defp ordinal(n), do: "#{n}th"

  defp masked?(units),
    do: Enum.any?(units, fn {_, held} -> held == :any or match?({:mask, _}, held) end)

  defp bound_words(count) when is_integer(count), do: " of #{count} occurrences"
  defp bound_words(:infinity), do: " with no end"
  defp bound_words(%Tempo{} = until), do: " until #{Tempo.to_iso8601!(until)}"

  defp worded(expression) do
    case Format.to_string(expression, []) do
      {:ok, words} -> ": " <> plain(words)
      {:error, _} -> ""
    end
  end

  defp words(%Duration{} = duration) do
    case Format.to_string(duration, []) do
      {:ok, words} -> words
      {:error, _} -> Tempo.to_iso8601!(duration)
    end
  end

  # CLDR's thin and narrow spaces as plain ones, for a terminal.
  defp plain(words), do: String.replace(words, [" ", " "], " ")

  defp plural_name({:microsecond, _precision}), do: "fractions of a second"
  defp plural_name(unit), do: unit_name(unit) <> "s"

  defp unit_name({:microsecond, _precision}), do: "fraction of a second"
  defp unit_name(unit), do: unit |> Atom.to_string() |> String.replace("_", " ")

  # ── What it covers ────────────────────────────────────────────────────

  defp covers(%Tempo{form: {:one, _}}), do: nil

  defp covers(%Tempo{} = expression) do
    cond do
      match?({:cycle, _}, Spans.frame(expression)) ->
        "It has no year, so it names a place in every #{cycle(expression)} and needs a window to be placed."

      not Parts.bounded?(expression) ->
        "It has no end of its own; a `:within` window bounds it."

      true ->
        covered(Tempo.to_interval(expression), expression)
    end
  end

  defp cycle(expression) do
    case Spans.frame(expression) do
      {:cycle, unit} when unit in [:month, :day, :day_of_year, :week] -> "year"
      {:cycle, :day_of_week} -> "week"
      _clock -> "day"
    end
  end

  defp covered({:ok, %Tempo{form: {:span, from, to}}}, _expression),
    do: "It covers #{Tempo.to_iso8601!(from)} #{to_word(to)} #{Tempo.to_iso8601!(to)}."

  defp covered({:ok, %Tempo{form: {:all, members}}}, %Tempo{form: {:value, units}}) do
    if masked?(units),
      do: "It is one of #{length(members)} values.",
      else: "It names #{length(members)} values, each a span of its own."
  end

  defp covered({:ok, %Tempo{form: {:all, members}}}, _expression),
    do: "It covers #{length(members)} spans."

  defp covered(_error, _expression), do: nil

  # A date end is read through, a clock end is a boundary (law 9).
  defp to_word(%Tempo{} = to), do: if(Spans.clock_resolution?(to), do: "to", else: "through")

  # ── Frame ─────────────────────────────────────────────────────────────

  defp calendar(%Tempo{calendar: Calendar.ISO}), do: nil
  defp calendar(%Tempo{calendar: calendar}), do: "It is in the #{inspect(calendar)} calendar."

  defp frame(%Tempo{} = expression) do
    case Spans.frame_of(expression) do
      %{zone: %{name: name}} when is_binary(name) -> "It is in the zone #{name}."
      %{shift: [hour: 0]} -> "It is in UTC (`Z`)."
      %{shift: shift} when is_list(shift) -> "It is at a fixed shift from UTC."
      _floating -> "It is floating: a reading of a clock in no zone."
    end
  end

  defp qualified(%Tempo{qualifications: nil}), do: nil

  defp qualified(%Tempo{qualifications: qualifications}) do
    Enum.map(qualifications, fn {unit, how} -> "Its #{unit_name(unit)} is #{how_word(how)}." end)
  end

  defp how_word(:uncertain), do: "uncertain"
  defp how_word(:approximate), do: "approximate"
  defp how_word(:both), do: "uncertain and approximate"

  # ── Walking ───────────────────────────────────────────────────────────

  defp walk(%Tempo{} = expression) do
    cond do
      not Spans.singular?(expression) -> "Walking it gives its members."
      unit = Spans.child_unit(expression) -> "Walking it gives its #{plural_name(unit)}."
      true -> "It is written to the finest unit and has nothing finer to walk."
    end
  end
end
