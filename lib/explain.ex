defmodule Tempo.Explanation do
  @moduledoc """
  A structured explanation of a Tempo value.

  Produced by `Tempo.Explain.explain/1`. Consists of a `:kind`
  classifier and an ordered list of `{tag, text}` parts. The tag
  lets renderers (plain terminal, ANSI colour, HTML) style each
  part semantically without re-parsing the
  prose.

  ### Fields

  * `:kind` — a classifier atom (e.g. `:scalar_year`,
    `:masked_year`, `:duration`, `:interval_set`).

  * `:parts` — a list of `{tag :: atom(), text :: String.t()}`
    tuples. Common tags:

    * `:headline` — one-line description of what this value is.
    * `:span` — bounded interval in `[from, to)` form.
    * `:margin` — `±` uncertainty margin and the span its groundings cover.
    * `:qualification` — EDTF qualifier description.
    * `:extended` — IXDTF metadata (zone, calendar, tags).
    * `:calendar` — non-default calendar.
    * `:enumeration` — iteration granularity.
    * `:hint` — pointer to relevant function.
    * `:metadata` — user metadata on an interval.
    * `:member` — list-of-members preview for sets.

  """

  @type t :: %__MODULE__{
          kind: atom(),
          parts: [{atom(), String.t()}]
        }

  defstruct [:kind, parts: []]
end

defmodule Tempo.Explain do
  import Kernel, except: [to_string: 1]

  @moduledoc """
  Plain-English explanations of Tempo values, in a form renderers
  can style.

  `Tempo.Explain.explain/1` returns a `t:Tempo.Explanation.t/0`
  with semantic part tags. Three formatters produce output for
  different surfaces:

  * `to_string/1` — plain multi-line text. Default for iex.
  * `to_ansi/1` — ANSI-coloured for terminals.
  * `to_iodata/1` — tagged iodata for HTML renderers.

  `Tempo.explain/1` delegates here with a `to_string/1` formatter —
  the most common case for interactive use.

  ## Example

      iex> Tempo.Explain.explain(~o"156X").kind
      :masked_year

      iex> Tempo.Explain.explain(~o"156X").parts
      ...> |> Enum.map(&elem(&1, 0))
      [:headline, :span, :enumeration, :hint]

  """

  alias Tempo.Explanation
  alias Tempo.IntervalSet
  alias Tempo.Iso8601.Unit
  alias Tempo.Mask

  @doc """
  Return a structured `t:Tempo.Explanation.t/0` for any Tempo
  value. Unknown shapes produce a generic fallback rather than
  raising.
  """
  @spec explain(term()) :: Explanation.t()
  def explain(value) do
    %Explanation{kind: classify(value), parts: explain_parts(value)}
  end

  @doc """
  Render an explanation as plain multi-line text.

  ### Examples

      iex> Tempo.Explain.explain(~o"2022Y") |> Tempo.Explain.to_string()
      "The year 2022.\\nSpan: [2022-01-01, 2023-01-01).\\nIterates at :month granularity.\\nMaterialise as an interval with `Tempo.to_interval/1`."

  """
  @spec to_string(Explanation.t()) :: String.t()
  def to_string(%Explanation{parts: parts}) do
    Enum.map_join(parts, "\n", fn {_tag, text} -> text end)
  end

  @doc """
  Render an explanation with ANSI colour codes, suitable for a
  terminal that supports them.

  The colour mapping is deliberate: headlines are bright, spans
  are cyan (technical detail), qualifications and metadata are
  yellow (notable), hints are dim.
  """
  @spec to_ansi(Explanation.t()) :: String.t()
  def to_ansi(%Explanation{parts: parts}) do
    # `emit?` forced to true — callers that want unconditional
    # ANSI get it. For terminal-aware emission the caller should
    # gate on `IO.ANSI.enabled?/0` themselves.
    parts
    |> Enum.map(&ansi_for/1)
    |> Enum.intersperse("\n")
    |> IO.ANSI.format(true)
    |> IO.iodata_to_binary()
  end

  defp ansi_for({:headline, text}), do: [:bright, text, :reset]
  defp ansi_for({:span, text}), do: [:cyan, text, :reset]
  defp ansi_for({:margin, text}), do: [:yellow, text, :reset]
  defp ansi_for({:qualification, text}), do: [:yellow, text, :reset]
  defp ansi_for({:extended, text}), do: [:yellow, text, :reset]
  defp ansi_for({:calendar, text}), do: [:magenta, text, :reset]
  defp ansi_for({:enumeration, text}), do: [:green, text, :reset]
  defp ansi_for({:hint, text}), do: [:faint, text, :reset]
  defp ansi_for({:metadata, text}), do: [:yellow, text, :reset]
  defp ansi_for({:member, text}), do: [:cyan, text, :reset]
  defp ansi_for({_tag, text}), do: [text]

  @doc """
  Render as tagged iodata `[{tag, text}, ...]`, ready for an HTML
  renderer to style each part by its tag.

  Each element is a 2-tuple; no string concatenation happens here.
  Callers decide how to separate parts (newlines, `<div>`s, etc.).
  """
  @spec to_iodata(Explanation.t()) :: [{atom(), String.t()}]
  def to_iodata(%Explanation{parts: parts}), do: parts

  ## ------------------------------------------------------------
  ## Classification
  ## ------------------------------------------------------------

  defp classify(%Tempo{time: time}) do
    cond do
      has_mask?(time) -> :masked
      only_time_of_day?(time) -> :time_of_day
      Keyword.has_key?(time, :year) -> :anchored
      true -> :scalar_other
    end
  end

  defp classify(%Tempo.Interval{from: :undefined, to: :undefined}), do: :fully_open_interval
  defp classify(%Tempo.Interval{from: :undefined}), do: :open_lower_interval
  defp classify(%Tempo.Interval{to: :undefined}), do: :open_upper_interval

  defp classify(%Tempo.Interval{recurrence: recurrence})
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1),
       do: :recurring_interval

  defp classify(%Tempo.Interval{}), do: :closed_interval

  defp classify(%Tempo.IntervalSet{} = set) do
    if IntervalSet.empty?(set), do: :empty_interval_set, else: :interval_set
  end

  defp classify(%Tempo.Set{type: :all}), do: :all_of_set
  defp classify(%Tempo.Set{type: :one}), do: :one_of_set
  defp classify(%Tempo.Duration{}), do: :duration
  defp classify(_), do: :unknown

  ## ------------------------------------------------------------
  ## explain_parts — one clause per input shape
  ## ------------------------------------------------------------

  defp explain_parts(%Tempo{} = tempo), do: scalar_parts(tempo)
  defp explain_parts(%Tempo.Interval{} = iv), do: interval_parts(iv)
  defp explain_parts(%Tempo.IntervalSet{} = set), do: interval_set_parts(set)
  defp explain_parts(%Tempo.Set{} = set), do: set_parts(set)
  defp explain_parts(%Tempo.Duration{} = d), do: duration_parts(d)

  defp explain_parts(other) do
    [{:headline, "A value Tempo doesn't know how to describe: #{inspect(other)}."}]
  end

  ## ------------------------------------------------------------
  ## Scalar Tempo
  ## ------------------------------------------------------------

  # A bare selection (`2018YL1K1IN`, "in 2018, the first Monday") is a
  # rule rather than a span: it names which occurrences are wanted, not an
  # extent. `selection_prose/1` already renders exactly this for
  # recurrences, so reuse it rather than asking for a span that does not
  # exist.
  defp scalar_parts(%Tempo{time: time} = tempo) do
    case find_unit(time, :selection) do
      nil -> scalar_value_parts(tempo)
      selection -> selection_parts(tempo, time, selection)
    end
  end

  # A grouped component is a 3-tuple, so the time list is not always a
  # valid keyword list and `Keyword.get/3` raises on it.
  defp find_unit(time, key) do
    Enum.find_value(time, fn
      {^key, value} -> value
      _entry -> nil
    end)
  end

  defp selection_parts(%Tempo{} = tempo, time, selection) do
    scope =
      case find_unit(time, :year) do
        year when is_integer(year) -> "In #{year}, selects"
        _no_year -> "Selects"
      end

    [
      {:headline, "A selection — a rule naming which occurrences are wanted."},
      {:span, "#{scope} #{selection_prose(selection)}."},
      {:calendar, calendar_text(tempo)},
      {:hint, "Pair it with a recurrence (`R/../P1Y/FL…N`) to materialise occurrences."}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp scalar_value_parts(%Tempo{} = tempo) do
    [
      {:headline, scalar_headline(tempo)},
      {:span, scalar_span(tempo)},
      {:margin, margin_text(tempo)},
      {:qualification, qualification_text(tempo)},
      {:extended, extended_text(tempo)},
      {:calendar, calendar_text(tempo)},
      {:enumeration, enumeration_text(tempo)},
      {:hint, "Materialise as an interval with `Tempo.to_interval/1`."}
    ]
    |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
  end

  defp scalar_headline(%Tempo{time: time} = tempo) do
    cond do
      has_mask?(time) -> mask_headline(tempo)
      only_time_of_day?(time) -> time_of_day_headline(time)
      true -> anchored_headline(time)
    end
  end

  defp anchored_headline(time) do
    y = find_unit(time, :year)
    m = find_unit(time, :month)
    d = find_unit(time, :day)

    case anchored_precision(time) do
      :datetime -> datetime_headline(time, y, m, d)
      :date -> "#{month_name(m)} #{d}, #{y}."
      :month -> "#{month_name(m)} #{y}."
      :year -> "The year #{y}."
      other -> yearless_headline(other, m, d, time)
    end
  end

  defp datetime_headline(time, y, m, d) do
    h = find_unit(time, :hour)
    mi = find_unit(time, :minute)
    "#{month_name(m)} #{d}, #{y} at #{two_digit(h)}:#{two_digit(mi || 0)}."
  end

  # No year at all: a recurring day-and-month (a birthday), a month, or a
  # bare day — values in their own right, not partial anchored ones.
  defp yearless_headline(:yearless_date, m, d, _time),
    do: "#{month_name(m)} #{d}, in any year (no year — it recurs)."

  defp yearless_headline(:yearless_month, m, _d, _time),
    do: "#{month_name(m)}, in any year (no year — it recurs)."

  defp yearless_headline(:day_only, _m, d, _time),
    do: "Day #{d} of any month (no year or month — it recurs)."

  defp yearless_headline(:none, _m, _d, time) do
    {unit, _scale} = Tempo.resolution(%Tempo{time: time})
    "A Tempo value at #{inspect(unit)} resolution."
  end

  defp anchored_precision(time) do
    cond do
      all_present?(time, [:year, :month, :day, :hour]) -> :datetime
      all_present?(time, [:year, :month, :day]) -> :date
      all_present?(time, [:year, :month]) -> :month
      all_present?(time, [:year]) -> :year
      # No year at all: a recurring day-and-month (a birthday), a month,
      # or a bare day. These are values in their own right, not partial
      # anchored ones.
      all_present?(time, [:month, :day]) -> :yearless_date
      all_present?(time, [:month]) -> :yearless_month
      all_present?(time, [:day]) -> :day_only
      true -> :none
    end
  end

  defp all_present?(time, keys), do: Enum.all?(keys, &is_integer(find_unit(time, &1)))

  defp time_of_day_headline(time) do
    h = Keyword.get(time, :hour, 0)
    m = Keyword.get(time, :minute, 0)
    "The time-of-day #{two_digit(h)}:#{two_digit(m)} (non-anchored — recurs every day)."
  end

  defp mask_headline(%Tempo{time: time}) do
    case find_first_mask(time) do
      {:year, mask} ->
        {min, max} = mask_range(mask)
        sign_note = if :negative in mask, do: " BCE", else: ""
        "A masked year spanning #{decade_label(min, max)}#{sign_note}."

      {unit, _mask} ->
        "A Tempo with a masked #{unit} component."

      nil ->
        "A Tempo value."
    end
  end

  defp decade_label(min, max) when max - min == 9, do: "the #{min}s"
  defp decade_label(min, max) when max - min == 99, do: "the #{div(min, 100)}00s (century)"
  defp decade_label(min, max) when max - min == 999, do: "the #{div(min, 1000)}000s (millennium)"
  defp decade_label(min, max) when max - min == 9999, do: "all 4-digit years (#{min}–#{max})"
  defp decade_label(min, max), do: "#{min} through #{max} (#{max - min + 1} years)"

  defp scalar_span(%Tempo{} = tempo) do
    case Tempo.to_interval(tempo) do
      {:ok, %Tempo.Interval{from: from, to: to}} ->
        "Span: [#{render_endpoint(from)}, #{render_endpoint(to)})."

      {:ok, %Tempo.IntervalSet{} = set} ->
        "Materialises to #{IntervalSet.count(set)} disjoint intervals."

      {:error, _} ->
        nil
    end
  end

  # A `±` margin means the value may ground anywhere within its
  # margin of error: `2000±1Y` is some year in 1999–2001. Surface the
  # margin and, for the single-margin case, the full span the
  # groundings cover (the same widening the certainty API applies).
  defp margin_text(%Tempo{time: time} = tempo) do
    case margin_entries(time) do
      [] -> nil
      entries -> describe_margins(entries, tempo)
    end
  end

  defp margin_entries(time) do
    Enum.flat_map(time, fn
      {unit, {_value, options}} when is_list(options) ->
        case Keyword.get(options, :margin_of_error) do
          nil -> []
          margin -> [{unit, margin}]
        end

      _other ->
        []
    end)
  end

  defp describe_margins([{unit, margin}] = entries, tempo) do
    nominal = strip_margins(tempo)

    with %Tempo{} = low <- Tempo.shift(nominal, [{unit, -margin}]),
         true <- Tempo.anchored?(low),
         %Tempo{} = high <- Tempo.shift(nominal, [{unit, margin}]),
         {:ok, %Tempo.Interval{from: from}} <- Tempo.to_interval(low),
         {:ok, %Tempo.Interval{to: to}} <- Tempo.to_interval(high) do
      "Margin: ±#{margin} #{unit_word(unit, margin)} — groundings span " <>
        "[#{render_endpoint(from)}, #{render_endpoint(to)})."
    else
      _other -> margin_list_text(entries)
    end
  end

  defp describe_margins(entries, _tempo), do: margin_list_text(entries)

  defp margin_list_text(entries) do
    rendered =
      Enum.map_join(entries, ", ", fn {unit, margin} ->
        "±#{margin} #{unit_word(unit, margin)}"
      end)

    "Margin: #{rendered}."
  end

  defp strip_margins(%Tempo{time: time} = tempo) do
    stripped =
      Enum.map(time, fn
        {unit, {value, options}} when is_list(options) ->
          case Keyword.delete(options, :margin_of_error) do
            [] -> {unit, value}
            rest -> {unit, {value, rest}}
          end

        other ->
          other
      end)

    %{tempo | time: stripped}
  end

  defp unit_word(unit, 1), do: "#{unit}"
  defp unit_word(unit, _margin), do: "#{unit}s"

  defp qualification_text(%Tempo{qualification: nil, qualifications: nil}), do: nil

  defp qualification_text(%Tempo{qualification: q, qualifications: qs}) do
    parts =
      [
        q &&
          "Expression-level qualification: #{qualification_word(q)} (EDTF #{qualification_symbol(q)}).",
        qs && map_size(qs) > 0 && "Per-component qualifications: #{inspect(qs)}."
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    case parts do
      [] -> nil
      _ -> Enum.join(parts, " ")
    end
  end

  defp extended_text(%Tempo{extended: nil}), do: nil

  defp extended_text(%Tempo{extended: extended}) do
    parts =
      [
        extended[:zone_id] && "Timezone: #{extended.zone_id}.",
        extended[:zone_offset] && "UTC offset: #{extended.zone_offset} minutes.",
        extended[:calendar] && "IXDTF calendar hint: #{extended.calendar}."
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    case parts do
      [] -> nil
      _ -> Enum.join(parts, " ")
    end
  end

  defp calendar_text(%Tempo{calendar: Calendrical.Gregorian}), do: nil
  defp calendar_text(%Tempo{calendar: Calendar.ISO}), do: nil
  defp calendar_text(%Tempo{calendar: cal}), do: "Calendar: #{inspect(cal)}."

  # A value with no components has no resolution to report — `resolution/1`
  # takes the last unit and there is none.
  defp enumeration_text(%Tempo{time: []}), do: nil

  defp enumeration_text(%Tempo{} = tempo) do
    {unit, _count} = Tempo.resolution(tempo)
    enumerator_text(unit, tempo.calendar)
  end

  # `Unit.implicit_enumerator/2` is defined only over the known time
  # units, so ask whether this is one rather than rescue the
  # `FunctionClauseError` for those that are not. `fetch_sort_key/1`
  # answers exactly that question: its map's keys *are* `@units`.
  defp enumerator_text(unit, calendar) do
    case Unit.fetch_sort_key(unit) do
      {:ok, _key} -> describe_enumerator(Unit.implicit_enumerator(unit, calendar))
      :error -> nil
    end
  end

  defp describe_enumerator(nil),
    do: "At finest supported resolution — cannot be enumerated further."

  defp describe_enumerator({next_unit, _range}),
    do: "Iterates at #{inspect(next_unit)} granularity."

  ## ------------------------------------------------------------
  ## Tempo.Interval
  ## ------------------------------------------------------------

  defp interval_parts(%Tempo.Interval{from: :undefined, to: :undefined}) do
    [
      {:headline, "A fully open interval (`../..`)."},
      {:hint, "No anchor on either side — not enumerable, not usable in set operations."}
    ]
  end

  # `P1D/2026-06-15` — a duration and an end. The lower bound is implied
  # by the duration, not absent, so this must be matched before the
  # open-lower clause below: that clause would call a bounded one-day
  # interval "open-lower", which is not merely vague but wrong.
  defp interval_parts(%Tempo.Interval{
         from: :undefined,
         to: %Tempo{} = to,
         duration: %Tempo.Duration{time: duration_time}
       }) do
    [
      {:headline, "An interval given as a duration and an end."},
      {:span, "Ends: #{render_endpoint(to)} (exclusive — half-open `[from, to)`)."},
      {:span, "Duration: #{duration_prose(duration_time)}."},
      {:hint, "Resolve the implied start with `Tempo.to_interval/1`."}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: :undefined, to: %Tempo{} = to}) do
    [
      {:headline, "An open-lower interval (`../#{render_endpoint(to)}`)."},
      {:span, "Upper bound: #{render_endpoint(to)}."},
      {:hint, "Enumeration requires a lower bound; set operations need a `:bound` option."}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: %Tempo{} = from, to: :undefined}) do
    [
      {:headline, "An open-upper interval (`#{render_endpoint(from)}/..`)."},
      {:span, "Lower bound: #{render_endpoint(from)}."},
      {:hint, "Enumerates forward forever — use `Enum.take/2` to halt."}
    ]
  end

  defp interval_parts(
         %Tempo.Interval{
           recurrence: recurrence,
           from: %Tempo{} = from,
           duration: %Tempo.Duration{time: dt}
         } = interval
       )
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    selection = selection_of(interval.repeat_rule)

    [
      {:headline, recurrence_headline(recurrence)},
      {:span, "Starting: #{render_endpoint(from)}."},
      selection && {:span, "Selects: #{selection_prose(selection)}."},
      {:span, "Cadence: #{duration_prose(dt)}."},
      {:hint, recurrence_hint(recurrence, from)}
    ]
    |> Enum.reject(&is_nil/1)
  end

  # An unanchored recurrence — `R/../P1Y/FL11M4I4KN`, "every year, the
  # fourth Thursday of November", beginning nowhere. Two sentinels spell
  # "no endpoint": `:undefined` from the ISO 8601 parser and `nil` from
  # the RRULE parser, and the clauses above match only the first. The
  # rule itself is fully described, so explain the selection and name
  # what is missing rather than falling through to the generic shape.
  defp interval_parts(
         %Tempo.Interval{
           recurrence: recurrence,
           from: nil,
           duration: %Tempo.Duration{time: duration_time}
         } = interval
       )
       when recurrence == :infinity or (is_integer(recurrence) and recurrence > 1) do
    selection = selection_of(interval.repeat_rule)

    [
      {:headline, recurrence_headline(recurrence)},
      {:span, "Starting: unanchored — the rule names no start."},
      selection && {:span, "Selects: #{selection_prose(selection)}."},
      {:span, "Cadence: #{duration_prose(duration_time)}."},
      {:hint, unanchored_hint()}
    ]
    |> Enum.reject(&is_nil/1)
  end

  # `2026-06-15/P1D`, `2026-06-15T09:00/PT8H` — a start and a duration,
  # the ordinary ISO 8601 spelling of "an 8-hour shift from 09:00". It
  # carries no `to`, so every clause above missed it and it reported an
  # unusual shape. Sits below the recurrence clause so a real recurrence
  # still matches there; what reaches here repeats once or not at all.
  defp interval_parts(%Tempo.Interval{
         from: %Tempo{} = from,
         to: nil,
         duration: %Tempo.Duration{time: duration_time}
       }) do
    [
      {:headline, "An interval given as a start and a duration."},
      {:span, "Starts: #{render_endpoint(from)}."},
      {:span, "Duration: #{duration_prose(duration_time)}."},
      {:hint, "Resolve the implied end with `Tempo.to_interval/1`."}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    [
      {:headline, "A closed interval."},
      {:span, "From: #{render_endpoint(from)}."},
      {:span, "To:   #{render_endpoint(to)} (exclusive — half-open `[from, to)`)."},
      metadata_part(interval.metadata)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp interval_parts(%Tempo.Interval{}) do
    [{:headline, "A Tempo.Interval with an unusual shape."}]
  end

  defp metadata_part(m) when m == %{} or is_nil(m), do: nil

  defp metadata_part(m) do
    text =
      case m[:summary] do
        nil ->
          "Metadata: #{map_size(m)} key(s)."

        s ->
          loc = m[:location]
          if is_binary(loc), do: "Event: #{s} @ #{loc}.", else: "Event: #{s}."
      end

    {:metadata, text}
  end

  ## ------------------------------------------------------------
  ## Tempo.IntervalSet
  ## ------------------------------------------------------------

  defp interval_set_parts(%Tempo.IntervalSet{metadata: metadata} = set) do
    if IntervalSet.empty?(set) do
      [
        {:headline, "An empty IntervalSet."},
        set_metadata_part(metadata)
      ]
      |> Enum.reject(&is_nil/1)
    else
      interval_set_member_parts(IntervalSet.to_list(set), metadata)
    end
  end

  defp interval_set_member_parts(intervals, metadata) do
    count = length(intervals)

    preview_parts =
      intervals
      |> Enum.take(3)
      |> Enum.with_index(1)
      |> Enum.map(fn {iv, i} ->
        summary = (iv.metadata || %{})[:summary] || "(no summary)"
        {:member, "#{i}. #{render_endpoint(iv.from)} → #{render_endpoint(iv.to)}  · #{summary}"}
      end)

    more =
      if count > 3, do: [{:member, "… and #{count - 3} more."}], else: []

    [
      {:headline, "An IntervalSet with #{count} interval#{if count == 1, do: "", else: "s"}."}
    ] ++ preview_parts ++ more ++ List.wrap(set_metadata_part(metadata))
  end

  defp set_metadata_part(nil), do: nil
  defp set_metadata_part(m) when m == %{}, do: nil

  defp set_metadata_part(%{name: name}) when is_binary(name),
    do: {:metadata, "Calendar name: #{name}."}

  defp set_metadata_part(%{prodid: prodid}) when is_binary(prodid),
    do: {:metadata, "Producer: #{prodid}."}

  defp set_metadata_part(m),
    do: {:metadata, "Set-level metadata: #{map_size(m)} key(s)."}

  ## ------------------------------------------------------------
  ## Tempo.Set
  ## ------------------------------------------------------------

  defp set_parts(%Tempo.Set{type: :all, set: members}) do
    [
      {:headline, "An all-of set: every member happened."},
      {:member, "#{length(members)} member(s): #{Enum.map_join(members, ", ", &inspect/1)}."},
      {:hint, "Materialise as an IntervalSet with `Tempo.to_interval/1`."}
    ]
  end

  defp set_parts(%Tempo.Set{type: :one, set: members}) do
    [
      {:headline,
       "A one-of set: exactly one of the members happened — we don't know which (epistemic disjunction)."},
      {:member, "#{length(members)} candidate(s): #{Enum.map_join(members, ", ", &inspect/1)}."},
      {:hint, "Cannot be materialised to an IntervalSet; pick a specific member first."}
    ]
  end

  ## ------------------------------------------------------------
  ## Tempo.Duration
  ## ------------------------------------------------------------

  defp duration_parts(%Tempo.Duration{time: time}) do
    [
      {:headline, "A duration of #{duration_prose(time)}."},
      {:hint,
       "Has no anchor on the time line — add to or subtract from a Tempo via `Tempo.Math.add/2` / `Tempo.Math.subtract/2`."},
      {:hint, "Not directly usable in set operations."}
    ]
  end

  ## ------------------------------------------------------------
  ## Shared helpers
  ## ------------------------------------------------------------

  defp has_mask?(time) do
    Enum.any?(time, fn
      {_, {:mask, _}} -> true
      _ -> false
    end)
  end

  @date_units [:year, :month, :day, :week, :day_of_week, :day_of_year]

  defp only_time_of_day?(time) do
    units = Enum.map(time, &elem(&1, 0))

    not Enum.any?(units, &(&1 in @date_units)) and
      Enum.any?(units, &(&1 in [:hour, :minute, :second]))
  end

  defp find_first_mask(time) do
    Enum.find_value(time, fn
      {unit, {:mask, mask}} -> {unit, mask}
      _ -> nil
    end)
  end

  defp mask_range(mask) do
    mask
    |> Enum.reject(&(&1 == :negative))
    |> Mask.mask_bounds()
  end

  defp qualification_word(:uncertain), do: "uncertain"
  defp qualification_word(:approximate), do: "approximate"
  defp qualification_word(:uncertain_and_approximate), do: "both uncertain and approximate"
  defp qualification_word(other), do: to_string(other)

  defp qualification_symbol(:uncertain), do: "?"
  defp qualification_symbol(:approximate), do: "~"
  defp qualification_symbol(:uncertain_and_approximate), do: "%"
  defp qualification_symbol(_), do: "?"

  # Render an endpoint in a consistent `YYYY-MM-DDTHH:MM` shape,
  # padding missing trailing units with their minimum so the
  # output reads as a concrete moment rather than a span.
  defp render_endpoint(%Tempo{time: time} = tempo) do
    case {render_date_part(time), render_time_part(time)} do
      # A mask (`198X`), a margin of error (`2018±2Y`) or a grouped
      # component has no plain calendar spelling, so show the value's own
      # rendering rather than `?`. `Inspect` is total — it falls back to a
      # labelled struct view for anything it cannot encode.
      {nil, nil} -> inspect(tempo)
      {date, nil} -> date
      {nil, time} -> "T#{time}"
      {date, time} -> "#{date}T#{time}"
    end
  end

  defp render_endpoint(other), do: inspect(other)

  defp render_date_part(time) do
    y = find_unit(time, :year)
    m = find_unit(time, :month)
    d = find_unit(time, :day)

    cond do
      is_integer(y) and is_integer(m) and is_integer(d) -> "#{y}-#{two_digit(m)}-#{two_digit(d)}"
      is_integer(y) and is_integer(m) -> "#{y}-#{two_digit(m)}-01"
      is_integer(y) -> "#{y}-01-01"
      true -> render_yearless_date(time)
    end
  end

  # ISO 8601 writes a yearless date `--MM-DD`, a yearless month `--MM`,
  # and a bare day `---DD`. Use the standard's own spelling so a span
  # reads as a date rather than as `?`.
  defp render_yearless_date(time) do
    m = find_unit(time, :month)
    d = find_unit(time, :day)

    cond do
      is_integer(m) and is_integer(d) -> "--#{two_digit(m)}-#{two_digit(d)}"
      is_integer(m) -> "--#{two_digit(m)}"
      is_integer(d) -> "---#{two_digit(d)}"
      true -> render_alternate_axis(time)
    end
  end

  # The week and ordinal axes have their own ISO spellings.
  defp render_alternate_axis(time) do
    y = find_unit(time, :year)
    w = find_unit(time, :week)
    dw = find_unit(time, :day_of_week)
    dy = find_unit(time, :day_of_year)

    cond do
      is_integer(y) and is_integer(dy) -> "#{y}-#{dy}"
      is_integer(dy) -> "day #{dy} of the year"
      true -> render_week_axis(y, w, dw)
    end
  end

  # ISO 8601 week spellings, by which parts the value actually carries.
  defp render_week_axis(y, w, dw) when is_integer(y) and is_integer(w) and is_integer(dw),
    do: "#{y}-W#{two_digit(w)}-#{dw}"

  defp render_week_axis(y, w, _dw) when is_integer(y) and is_integer(w),
    do: "#{y}-W#{two_digit(w)}"

  defp render_week_axis(_y, w, dw) when is_integer(w) and is_integer(dw),
    do: "-W#{two_digit(w)}-#{dw}"

  defp render_week_axis(_y, w, _dw) when is_integer(w), do: "-W#{two_digit(w)}"
  defp render_week_axis(_y, _w, dw) when is_integer(dw), do: "day #{dw} of the week"
  defp render_week_axis(_y, _w, _dw), do: nil

  defp render_time_part(time) do
    h = Keyword.get(time, :hour)
    mi = Keyword.get(time, :minute)

    cond do
      is_integer(h) and is_integer(mi) -> "#{two_digit(h)}:#{two_digit(mi)}"
      is_integer(h) -> "#{two_digit(h)}:00"
      is_integer(mi) -> "00:#{two_digit(mi)}"
      true -> nil
    end
  end

  defp duration_prose(time) do
    Enum.map_join(time, ", ", &duration_component/1)
  end

  # A sub-second component is stored as `{value, precision}` — `PT1.5S`
  # is `[second: 1, microsecond: {500_000, 1}]` — so it cannot be
  # interpolated directly. Render it at its own precision: 500000 µs at
  # precision 1 is "0.5 seconds".
  defp duration_component({:microsecond, {value, precision}}) do
    seconds = value / 1_000_000
    "#{:erlang.float_to_binary(seconds, decimals: max(precision, 1))} seconds"
  end

  defp duration_component({unit, n}), do: "#{n} #{pluralise(unit, n)}"

  defp pluralise(unit, 1), do: Atom.to_string(unit)
  defp pluralise(unit, _), do: Atom.to_string(unit) <> "s"

  @months ~w(January February March April May June July August September October November December)

  defp month_name(n) when is_integer(n) and n in 1..12, do: Enum.at(@months, n - 1)
  defp month_name(other), do: "month #{inspect(other)}"

  defp two_digit(n) when is_integer(n) and n >= 0 and n < 10, do: "0#{n}"
  defp two_digit(n) when is_integer(n), do: Integer.to_string(n)
  defp two_digit(_), do: "??"

  # ── Recurrence + selection prose ───────────────────────────────

  defp selection_of(%Tempo{time: [selection: selection]}), do: selection
  defp selection_of(_), do: nil

  defp recurrence_headline(:infinity), do: "An unbounded recurrence."
  defp recurrence_headline(n) when is_integer(n), do: "A recurrence of #{n} occurrences."

  defp unanchored_hint do
    "Not enumerable until anchored — a bound says where to stop looking, " <>
      "not where the series starts. Give the literal a start " <>
      "(`R/2026-01-01/…`) or re-parse with one " <>
      "(`Tempo.RRule.parse(rule, from: ~o\"2026-01-01\")`)."
  end

  defp recurrence_hint(:infinity, from),
    do:
      "List a window of occurrences: `Tempo.to_interval(interval, bound: #{bound_example(from)})`."

  defp recurrence_hint(n, _from) when is_integer(n),
    do: "Materialise the #{n} occurrences: `Tempo.to_interval(interval)`."

  defp bound_example(%Tempo{time: time}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> "~o\"#{year}\""
      _year -> "~o\"2026\""
    end
  end

  # Render a BY-rule selection as an English phrase — e.g.
  # `[month: 11, day: [2..8], day_of_week: 2]` becomes "in November, on
  # the 2nd–8th, on a Tuesday" (US Election Day).
  defp selection_prose(selection) do
    selection
    |> Enum.reject(fn {key, _value} -> key == :wkst end)
    |> Enum.flat_map(fn entry -> List.wrap(selection_clause(entry)) end)
    |> Enum.join(", ")
  end

  defp selection_clause({:month, m}), do: "in #{names_phrase(m, &month_name/1)}"
  defp selection_clause({:day, d}), do: "on #{ordinals_phrase(d)}"
  defp selection_clause({:day_of_week, wd}), do: "on a #{weekday_name(wd)}"
  defp selection_clause({:byday, pairs}), do: "on #{byday_phrase(pairs)}"
  defp selection_clause({:hour, h}), do: "at #{names_phrase(h, fn n -> "#{two_digit(n)}:00" end)}"
  defp selection_clause({:week, w}), do: "in #{ordinals_phrase(w)} week"
  defp selection_clause({:day_of_year, d}), do: "on #{ordinals_phrase(d)} day of the year"
  defp selection_clause({:set_position, p}), do: "keeping #{ordinals_phrase(p)} occurrence"
  defp selection_clause({_other, _value}), do: []

  defp byday_phrase(pairs) do
    pairs
    |> Enum.map(fn
      {nil, wd} -> "a #{weekday_name(wd)}"
      {ord, wd} -> "the #{ordinal(ord)} #{weekday_name(wd)}"
    end)
    |> or_join()
  end

  # Ordinal-list phrase — a contiguous run collapses to a range:
  # `[2..8]` → "the 2nd–8th"; `[1, 15]` → "the 1st and 15th".
  defp ordinals_phrase(value) do
    ints = value |> List.wrap() |> Enum.flat_map(&expand_int/1) |> Enum.sort()

    case ints do
      [n] ->
        "the #{ordinal(n)}"

      [lo | _] = list ->
        hi = List.last(list)

        if length(list) > 2 and hi - lo + 1 == length(list) do
          "the #{ordinal(lo)}–#{ordinal(hi)}"
        else
          "the " <> and_join(Enum.map(list, &ordinal/1))
        end
    end
  end

  defp names_phrase(value, name_fun) do
    value |> List.wrap() |> Enum.flat_map(&expand_int/1) |> Enum.map(name_fun) |> or_join()
  end

  defp expand_int(%Range{} = range), do: Enum.to_list(range)
  defp expand_int(n) when is_integer(n), do: [n]

  defp ordinal(-1), do: "last"
  defp ordinal(n) when is_integer(n) and n < 0, do: "#{ordinal(-n)}-to-last"

  defp ordinal(n) when is_integer(n) do
    suffix =
      cond do
        rem(n, 100) in 11..13 -> "th"
        rem(n, 10) == 1 -> "st"
        rem(n, 10) == 2 -> "nd"
        rem(n, 10) == 3 -> "rd"
        true -> "th"
      end

    "#{n}#{suffix}"
  end

  @weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  defp weekday_name(n) when is_integer(n) and n in 1..7, do: Enum.at(@weekdays, n - 1)
  defp weekday_name(other), do: "weekday #{inspect(other)}"

  defp or_join([one]), do: one

  defp or_join(list) do
    {init, [last]} = Enum.split(list, -1)
    Enum.join(init, ", ") <> " or " <> last
  end

  defp and_join([one]), do: one
  defp and_join([first, second]), do: "#{first} and #{second}"

  defp and_join(list) do
    {init, [last]} = Enum.split(list, -1)
    Enum.join(init, ", ") <> ", and " <> last
  end
end
