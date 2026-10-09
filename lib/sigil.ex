defmodule Tempo.Sigils do
  @moduledoc """
  Sigils for constructing and pattern-matching `%Tempo{}` values at
  compile time.

  Provides `~o` (and its verbose alias `~TEMPO`) to turn an ISO 8601
  / ISO 8601-2 / IXDTF / EDTF string into a `%Tempo{}`,
  `%Tempo.Interval{}`, `%Tempo.Duration{}`, `%Tempo.Range{}`, or
  `%Tempo.Set{}` struct — or into a pattern that matches one.

  ```elixir
  import Tempo.Sigils

  ~o"2026-06-15"            #=> %Tempo{…}
  ~o"2026-06-15T10:30:00Z"  #=> zoned datetime
  ~o"1984?/2004~"           #=> qualified interval
  ~o"2026Y"W                #=> ISO week calendar (W modifier)
  ```

  ### Why a module just for sigils

  The module exposes **only** the sigil macros so `import Tempo.Sigils`
  in application code adds exactly `sigil_o/2` and `sigil_TEMPO/2` to
  the caller's scope — no helper functions leak into the caller's
  namespace. Any expansion-time helpers live in a private sibling
  module that isn't part of the public API.

  ### Modifiers in value context

  When `~o"…"` appears as an expression that produces a value (the
  default context), a single modifier letter selects the calendar
  the string is parsed against:

  * No modifier — Gregorian calendar (the common case).

  * `W` — ISO Week calendar (`Calendrical.ISOWeek`). Use when the
    input is in a week-based form you want parsed under ISO week
    semantics explicitly. A whole date written with a month and a
    day is read as the Gregorian day and converted, so
    `~o"2026-06-15"W` is `~o"2026-W25-1"W`.

  ## Match context

  When `~o"…"` is used on the left-hand side of a match —
  `match?/2`, `case` clauses, `=`, or function-head patterns —
  the sigil expands to a **structural pattern** rather than a
  literal value. The generated pattern is deliberately permissive:
  it constrains only what the sigil string actually names.

  ### 1. Prefix matching on `%Tempo{}` and `%Tempo.Duration{}`

  The sigil string is parsed as usual; the resulting `:time`
  keyword list becomes a cons-pattern terminated by a wildcard,
  so the sigil matches any value whose `:time` *starts with* the
  listed `{unit, value}` pairs. Other struct fields
  (`:calendar`, `:shift`, `:extended`, `:qualifications`, …) are
  left unconstrained — a Gregorian-looking sigil matches a
  Hebrew-calendar value just as happily, because the intent of
  the sigil is purely temporal.

  ```elixir
  import Tempo.Sigils

  today = Tempo.new!(year: 2026, month: 4, day: 24)

  match?(~o[2026Y], today)          #=> true  — year prefix
  match?(~o[2026Y4M], today)        #=> true  — year+month prefix
  match?(~o[2026Y4M24D], today)     #=> true  — full prefix
  match?(~o[2026Y1M], today)        #=> false — month disagrees
  match?(~o[2025Y], today)          #=> false — year disagrees

  hebrew = Tempo.new!(year: 2026, month: 4, day: 24,
                      calendar: Calendrical.Hebrew)
  match?(~o[2026Y], hebrew)         #=> true  — :calendar is free

  duration = Tempo.Duration.new!(year: 1, month: 6)
  match?(~o[P1Y6M], duration)       #=> true
  match?(~o[P2Y6M], duration)       #=> false
  match?(~o[1Y6M], duration)        #=> false  — %Tempo{} sigil
                                    #            vs %Duration{}
  ```

  ### 2. Modifier-driven bindings

  Modifier letters after the closing delimiter bind the matched
  value's unit to a same-named variable in the caller's scope.
  Bindings are only meaningful on `%Tempo{}` and
  `%Tempo.Duration{}` values — the only shapes with a
  `:time` keyword list to destructure.

  Letter → unit mapping (deliberately avoids overloading `M`,
  which ISO 8601 uses for both month and minute):

  * `Y` — year
  * `O` — month (`mOnth`)
  * `W` — week
  * `D` — day
  * `I` — day of year
  * `K` — day of week
  * `H` — hour
  * `N` — minute (`miNute`)
  * `S` — second

  The pattern builder lays out the canonical calendar-axis slice
  between the earliest and latest unit requested (either by the
  sigil literal or by a modifier), filling positions not named
  with wildcards. Axis choice — Gregorian, ISO week, or ordinal
  — is inferred from the union of sigil and modifier units.

  ```elixir
  import Tempo.Sigils

  today = Tempo.new!(year: 2026, month: 4, day: 24)

  case today do
    ~o[2026Y]D -> day                 #=> 24
  end

  case today do
    ~o[2026Y]OD -> {month, day}       #=> {4, 24}
  end

  point = Tempo.new!(year: 2026, month: 6, day: 15,
                     hour: 14, minute: 30, second: 45)

  case point do
    ~o[2026Y6M]DN -> {day, minute}    #=> {15, 30}
  end

  case point do
    ~o[2026Y6M15DT14H30M]S -> second  #=> 45
  end

  duration = Tempo.Duration.new!(year: 1, month: 6, day: 15)

  case duration do
    ~o[P1Y]D -> day                   #=> 15
  end
  ```

  A modifier that targets a unit the matched value doesn't carry
  simply fails to match; the `case` falls through to the next
  clause. Modifier order inside the sigil is irrelevant —
  `~o[2026Y]DN` and `~o[2026Y]ND` expand to the same pattern.

  #### Expansion-time errors

  * Unknown modifier letter → `ArgumentError`.
  * Modifier targets a unit already fixed by the sigil (e.g.
    `~o[2026Y]Y`) → `ArgumentError`.
  * Mixing calendar axes (e.g. `~o[2026Y4M]W` — Gregorian
    month plus ISO week) → `ArgumentError`.

  ### 3. Matching containers

  The sigil also expands to a structural pattern when the parsed
  value is a container: `%Tempo.Interval{}`, `%Tempo.Range{}`,
  or `%Tempo.Set{}`. Each endpoint is itself prefix-matched
  using the phase-1 rules, so an endpoint sigil like `~o"2022Y"`
  inside an interval matches any Tempo whose `:time` starts with
  year 2022.

  Container patterns only constrain fields the sigil string
  actually names. For intervals, that means `from` and `to` are
  always constrained, while `duration`, `recurrence`,
  `direction`, and `repeat_rule` are only constrained when they
  differ from their struct defaults — so
  `~o[1984Y/2004Y]` doesn't accidentally require
  `metadata: %{}`.

  ```elixir
  import Tempo.Sigils

  {:ok, closed}   = Tempo.from_iso8601("1984Y/2004Y")
  {:ok, open_up}  = Tempo.from_iso8601("1984/..")
  {:ok, dur_iv}   = Tempo.from_iso8601("P1D/2022-01-01")

  match?(~o[1984Y/2004Y], closed)    #=> true
  match?(~o[1984Y/..], closed)       #=> false — closed vs open
  match?(~o[1984Y/..], open_up)      #=> true
  match?(~o[../..], open_up)         #=> false
  match?(~o[P1D/2022-01-01], dur_iv) #=> true

  {:ok, one_of}   = Tempo.from_iso8601("[1984,1986,1988]")
  {:ok, all_of}   = Tempo.from_iso8601("{1960,1961-12}")

  match?(~o"[1984Y,1986Y,1988Y]", one_of)  #=> true
  match?(~o"{1960Y,1961Y12M}", all_of)     #=> true
  match?(~o"{1984Y,1986Y,1988Y}", one_of)  #=> false — :one ≠ :all
  ```

  Sets whose literal text begins with `[` or `{` collide with
  the `~o[…]` and `~o{…}` delimiters, so use the string-delim
  form `~o"…"` for them.

  Set members are matched in order and by count — a sigil set
  with three members never matches a value with two or four.
  Ranges (`%Tempo.Range{first: …, last: …}`) are matched
  structurally whether they appear at the top level or nested
  inside a `%Tempo.Set{}`.

  #### Modifiers on containers

  Modifier bindings are **not** accepted on `%Tempo.Interval{}`,
  `%Tempo.Range{}`, `%Tempo.Set{}`, or `%Tempo.IntervalSet{}`
  sigils — there is no single keyword-list `:time` to
  destructure. Using one raises `ArgumentError` at expansion
  time. Reach into an interval's endpoint manually:

  ```elixir
  case interval do
    ~o[1984Y/..] ->
      %Tempo.Interval{from: ~o[1984Y]D = from} = interval
      from.time[:day]
  end
  ```

  ### 4. Guards

  Patterns from `~o"…"` cannot appear in a `when` clause. The
  sigil detects the `:guard` context and raises
  `ArgumentError` with a clear message — use a preceding match
  + `==` comparison instead.

  ### 5. What match context does **not** do

  * **No calendar modifier.** `W` in value context selects the
    ISO Week calendar; in match context it always means "bind
    `:week`". Sigils in match context always parse their
    string as Gregorian and leave the matched value's
    `:calendar` field unconstrained.

  * **No stdlib types.** `~o"…"` produces a `%Tempo{}`-family
    pattern, so it cannot match `%Date{}`, `%Time{}`,
    `%NaiveDateTime{}`, or `%DateTime{}`. For those, use
    `~D`/`~T`/`~N`/`~U` directly, or convert the value with
    `Tempo.from_elixir/1` before matching.

  * **No complex time elements.** Groups, selections, ranges,
    margin-of-error tuples, and continuations aren't expressible
    as static Elixir patterns — attempting to use a sigil that
    contains them in match context raises `ArgumentError`.

  """

  alias Tempo.Sigils.Options

  @doc """
  Parse an ISO 8601 / EDTF / IXDTF string at compile time, or expand
  it to a structural pattern in match context.

  The sigil's behaviour depends on where it appears in the source:

  ## Value context (the default)

  When `~o"…"` is used as an expression that produces a value, the
  parser fully resolves the string to its `%Tempo{}` /
  `%Tempo.Interval{}` / `%Tempo.Duration{}` / `%Tempo.Set{}` form
  and escapes it as a compile-time literal — no runtime parse cost
  at the call site.

      ~o"2026-06-15"            #=> %Tempo{…}
      ~o"2026-06-15T10:30:00Z"  #=> zoned datetime
      ~o"1984?/2004~"           #=> qualified interval

  The single modifier letter `w` selects the ISO Week calendar;
  otherwise the calendar is taken from the string's IXDTF
  `[u-ca=NAME]` suffix when present (`~o"5786-01-01[u-ca=hebrew]"`
  is a Hebrew date), falling back to Gregorian.

  ## Match context

  When `~o"…"` appears on the left-hand side of a match —
  `match?/2`, `case` clauses, `=`, or function-head patterns — the
  sigil expands to a structural pattern that matches by `:time`
  prefix.

      today = Tempo.new!(year: 2026, month: 4, day: 24)

      match?(~o[2026Y], today)       #=> true  (year prefix)
      match?(~o[2026Y4M], today)     #=> true  (year+month prefix)
      match?(~o[2025Y], today)       #=> false (year disagrees)

  Modifier letters after the closing delimiter bind matched units
  to same-named variables in scope. The letters are `Y O W D I K
  H N S` — see `Tempo.Sigils` for the full mapping.

      case today do
        ~o[2026Y]OD -> {month, day}  #=> {4, 24}
      end

  Match context also matches `%Tempo.Duration{}`,
  `%Tempo.Interval{}`, `%Tempo.Range{}`, and `%Tempo.Set{}`
  values structurally.

  Using the sigil inside a `when` guard is rejected at expansion
  time — use a preceding match or an `==` comparison instead.

  See the module documentation for the full specification of
  match context, including container patterns, modifier-binding
  rules, and expansion-time errors.

  """
  defmacro sigil_o({:<<>>, _meta, [_string]} = sigil, opts) do
    do_sigil(__CALLER__.context, sigil, opts)
  end

  @doc """
  Verbose alias for `sigil_o`. Use when `~o` might be confused with
  another sigil in scope, or when you want the three-letter form
  for readability in dense code.

  Behaves identically to `sigil_o/2` in both value and match
  contexts — see that function's documentation for the full
  specification.

  """
  defmacro sigil_TEMPO({:<<>>, _meta, [_string]} = sigil, opts) do
    do_sigil(__CALLER__.context, sigil, opts)
  end

  defp do_sigil(nil, {:<<>>, _meta, [string]}, opts) do
    # No calendar modifier → defer to the string's own IXDTF
    # `[u-ca=NAME]` suffix (via `from_iso8601/1`), so
    # `~o"5786-01-01[u-ca=hebrew]"` resolves to the Hebrew calendar
    # instead of being forced to Gregorian. A `W` modifier is an
    # explicit calendar choice that wins, matching `from_iso8601/2`'s
    # "explicit calendar always wins" rule.
    result =
      case Options.calendar_from(opts) do
        nil -> Tempo.from_iso8601(string)
        calendar -> Tempo.from_iso8601(string, calendar)
      end

    case result do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, exception} -> raise exception
    end
  end

  # Modifier letters accepted in match context and the unit they
  # bind. `M` is deliberately absent — ISO 8601 overloads it for
  # both month and minute, so match-context modifiers use `O` for
  # month and `N` for minute to keep the binding unambiguous.
  @modifier_to_unit %{
    ?Y => :year,
    ?O => :month,
    ?W => :week,
    ?D => :day,
    ?I => :day_of_year,
    ?K => :day_of_week,
    ?H => :hour,
    ?N => :minute,
    ?S => :second
  }

  # Canonical unit sequences per calendar axis. A `~o[…]`-bound
  # pattern picks the axis that covers every unit named (sigil or
  # modifier) and lays elements out in that axis's order, with
  # wildcards filling positions not explicitly requested.
  @gregorian_axis [:year, :month, :day, :hour, :minute, :second]
  @iso_week_axis [:year, :week, :day_of_week, :hour, :minute, :second]
  @ordinal_axis [:year, :day_of_year, :hour, :minute, :second]
  @season_axis [:year, :season]

  defp do_sigil(:match, {:<<>>, _meta, [string]}, opts) do
    # Match-context modifiers are always binding letters — a
    # departure from value context, where `W` selects the ISO
    # week calendar. The sigil string is therefore always parsed
    # with `Calendrical.Gregorian`; the generated pattern does
    # not constrain the target's `:calendar` field either, so a
    # Gregorian-looking sigil still matches e.g. a Hebrew value
    # at the same `time` prefix.
    bindings = bindings_from_modifiers(opts)

    case Tempo.from_iso8601(string, Calendrical.Gregorian) do
      {:ok, parsed} -> build_match_pattern(parsed, bindings)
      {:error, exception} -> raise exception
    end
  end

  defp do_sigil(:guard, {:<<>>, _meta, [_string]}, _opts) do
    raise ArgumentError, "invalid expression in guard"
  end

  # Resolve the modifier char list to a list of unit atoms to
  # bind. Order in the sigil is irrelevant — the pattern builder
  # re-sorts by axis position.
  defp bindings_from_modifiers([]), do: []

  defp bindings_from_modifiers(letters) when is_list(letters) do
    Enum.map(letters, fn letter ->
      case Map.fetch(@modifier_to_unit, letter) do
        {:ok, unit} ->
          unit

        :error ->
          raise ArgumentError,
                "~o sigil in a match context does not recognise modifier " <>
                  "#{inspect(<<letter::utf8>>)}; valid modifiers are " <>
                  "Y (year), O (month), W (week), D (day), I (day-of-year), " <>
                  "K (day-of-week), H (hour), N (minute), S (second)"
      end
    end)
  end

  # Dispatch on the struct that the parser produced. `%Tempo{}`
  # and `%Tempo.Duration{}` share a keyword-list `time` field, so
  # modifier bindings work for both; containers (intervals,
  # ranges, sets) match structurally and refuse modifiers.
  defp build_match_pattern(%Tempo{time: time}, bindings) do
    time_pattern = build_time_match_pattern(time, bindings)

    quote do
      %Tempo{time: unquote(time_pattern)}
    end
  end

  defp build_match_pattern(%Tempo.Duration{time: time}, bindings) do
    time_pattern = build_time_match_pattern(time, bindings)

    quote do
      %Tempo.Duration{time: unquote(time_pattern)}
    end
  end

  defp build_match_pattern(%Tempo.Interval{} = interval, bindings) do
    reject_container_bindings!(bindings, Tempo.Interval)
    interval_pattern(interval)
  end

  defp build_match_pattern(%Tempo.Set{} = set, bindings) do
    reject_container_bindings!(bindings, Tempo.Set)
    set_pattern(set)
  end

  # A `%Tempo.Range{}` is a set-member element, never a top-level
  # parse result — ranges in patterns are handled by
  # `set_member_pattern/1` inside `set_pattern/1`. Likewise a
  # `%Tempo.IntervalSet{}` is produced by `Tempo.to_interval/1`,
  # not by `Tempo.from_iso8601/2` — so a sigil string can't
  # materialise to either in practice. The catch-all below raises
  # a clear error if a future grammar extension ever changes that.

  defp build_match_pattern(other, _bindings) do
    raise ArgumentError,
          "~o sigil in a match context does not support matching on " <>
            "#{inspect(other.__struct__)} values"
  end

  defp reject_container_bindings!([], _module), do: :ok

  defp reject_container_bindings!(bindings, module) do
    raise ArgumentError,
          "~o sigil modifier bindings #{inspect(bindings)} are only " <>
            "supported on %Tempo{} and %Tempo.Duration{} values; " <>
            "#{inspect(module)} values match structurally only"
  end

  # Build a cons-pattern AST ending in `| _` for the `time` field
  # of the generated `%Tempo{}` pattern. The pattern lays out the
  # canonical axis slice between the earliest and latest unit
  # requested (whether via the sigil literal or a binding
  # modifier), filling each position with either the literal
  # value, the binding variable, or a wildcard.
  #
  # Only simple integer-valued components from the parsed sigil
  # are supported. Complex AST shapes (groups, selections,
  # ranges, margin-of-error tuples, continuations) raise at
  # macro-expansion time.
  defp build_time_match_pattern([], []) do
    quote do: _
  end

  defp build_time_match_pattern(time, bindings) do
    sigil_units = Keyword.keys(time)
    assert_no_modifier_duplicates!(sigil_units, bindings)

    all_units = sigil_units ++ bindings
    axis = axis_for(all_units)

    indexes = Enum.map(all_units, &index_in_axis!(&1, axis))
    first_index = Enum.min(indexes)
    last_index = Enum.max(indexes)

    axis
    |> Enum.slice(first_index..last_index)
    |> Enum.map(&element_for_unit(&1, time, bindings))
    |> build_cons_pattern()
  end

  # Pick the appropriate element shape for a canonical-axis
  # position: the sigil's literal value wins, a modifier binding
  # comes next, and unrequested positions become `_` wildcards.
  defp element_for_unit(unit, time, bindings) do
    cond do
      Keyword.has_key?(time, unit) ->
        value = Keyword.fetch!(time, unit)
        assert_matchable!(unit, value)
        {:fixed, unit, value}

      unit in bindings ->
        {:bind, unit}

      true ->
        :wildcard
    end
  end

  defp build_cons_pattern([]) do
    quote do: _
  end

  defp build_cons_pattern([elem | rest]) do
    head = element_to_ast(elem)
    tail = build_cons_pattern(rest)

    quote do
      [unquote(head) | unquote(tail)]
    end
  end

  defp element_to_ast({:fixed, unit, value}) do
    quote do: {unquote(unit), unquote(value)}
  end

  # Bind the unit's value to a same-named variable in the
  # caller's context — `D` binds `day`, `N` binds `minute`, etc.
  # `Macro.var(unit, nil)` uses hygienic context `nil`, matching
  # how the standard library's pattern-producing sigils (e.g.
  # `~D`) expose bindings.
  defp element_to_ast({:bind, unit}) do
    var = Macro.var(unit, nil)
    quote do: {unquote(unit), unquote(var)}
  end

  defp element_to_ast(:wildcard) do
    quote do: _
  end

  # Integers (including negatives) are valid literal patterns.
  # Anything else indicates a non-simple Tempo component that we
  # don't yet know how to express as a static Elixir pattern.
  defp assert_matchable!(_unit, value) when is_integer(value), do: :ok

  defp assert_matchable!(unit, value) do
    raise ArgumentError,
          "~o sigil in a match context only supports simple integer components; " <>
            "got #{inspect(unit)}: #{inspect(value)}"
  end

  defp assert_no_modifier_duplicates!(sigil_units, bindings) do
    dupes = for u <- bindings, u in sigil_units, do: u

    if dupes != [] do
      raise ArgumentError,
            "~o sigil modifier binds a unit already present in the sigil literal: " <>
              "#{inspect(dupes)}"
    end
  end

  # Derive the calendar axis (Gregorian / ISO week / ordinal)
  # that every requested unit has to belong to. Axis mixing is
  # an expansion-time error — a user can't meaningfully match
  # `:month` and `:week` on the same value.
  #
  # A season of 21 to 24 (`~o"2026-21"`) is written in the month's place
  # and nothing follows it, so it is an axis of its own: a year and its
  # season.
  defp axis_for(units) do
    week? = Enum.any?(units, &(&1 in [:week, :day_of_week]))
    ordinal? = Enum.any?(units, &(&1 == :day_of_year))
    gregorian? = Enum.any?(units, &(&1 in [:month, :day]))
    season? = Enum.any?(units, &(&1 == :season))

    if Enum.count([week?, ordinal?, gregorian?, season?], & &1) > 1 do
      raise ArgumentError,
            "~o sigil in a match context cannot mix calendar axes: " <>
              "#{inspect(units)}"
    end

    axis_of(week?, ordinal?, season?)
  end

  defp axis_of(true = _week?, _ordinal?, _season?), do: @iso_week_axis
  defp axis_of(_week?, true = _ordinal?, _season?), do: @ordinal_axis
  defp axis_of(_week?, _ordinal?, true = _season?), do: @season_axis
  defp axis_of(_week?, _ordinal?, _season?), do: @gregorian_axis

  defp index_in_axis!(unit, axis) do
    case Enum.find_index(axis, &(&1 == unit)) do
      nil ->
        raise ArgumentError,
              "~o sigil in a match context cannot place unit #{inspect(unit)} " <>
                "on the inferred calendar axis #{inspect(axis)}"

      idx ->
        idx
    end
  end

  # ---- Container patterns -----------------------------------

  # Pattern for a value that appears as an endpoint on an
  # `Interval`, `Range`, or `Set`. `:undefined` is used by the
  # parser for open endpoints; `nil` can appear on intervals
  # constructed without a `from` or `to` (e.g. a bare RRULE).
  # Concrete `%Tempo{}` / `%Tempo.Duration{}` endpoints reuse the
  # prefix-match semantics of phase ①/② so that an endpoint like
  # `~o"2022Y"` matches any Tempo whose `time` starts with year
  # 2022.
  defp endpoint_pattern(:undefined), do: :undefined
  defp endpoint_pattern(nil), do: nil

  defp endpoint_pattern(%Tempo{time: time}) do
    time_pattern = build_time_match_pattern(time, [])

    quote do
      %Tempo{time: unquote(time_pattern)}
    end
  end

  defp endpoint_pattern(%Tempo.Duration{time: time}) do
    time_pattern = build_time_match_pattern(time, [])

    quote do
      %Tempo.Duration{time: unquote(time_pattern)}
    end
  end

  # Intervals carry 7 fields but most are optional metadata. The
  # pattern only constrains fields that differ from their struct
  # defaults (so an interval built from `1984/2004` doesn't
  # accidentally require `metadata: %{}`, `direction: 1`, etc.).
  defp interval_pattern(%Tempo.Interval{
         from: from,
         to: to,
         duration: duration,
         recurrence: recurrence,
         direction: direction,
         repeat_rule: repeat_rule
       }) do
    fields =
      [from: endpoint_pattern(from), to: endpoint_pattern(to)]
      |> maybe_put_field(:duration, duration, &endpoint_pattern/1, &is_nil/1)
      |> maybe_put_field(:recurrence, recurrence, & &1, &(&1 == 1))
      |> maybe_put_field(:direction, direction, & &1, &(&1 == 1))
      |> maybe_put_field(:repeat_rule, repeat_rule, &endpoint_pattern/1, &is_nil/1)

    {:%, [],
     [
       {:__aliases__, [alias: false], [:Tempo, :Interval]},
       {:%{}, [], fields}
     ]}
  end

  defp range_pattern(%Tempo.Range{first: first, last: last}) do
    first_ast = endpoint_pattern(first)
    last_ast = endpoint_pattern(last)

    quote do
      %Tempo.Range{first: unquote(first_ast), last: unquote(last_ast)}
    end
  end

  # Sets either enumerate explicit members (`%Tempo.Set{}` with
  # `:all`/`:one`) or hold ranges. Member order and length are
  # constrained by the pattern — a sigil set only matches a Set
  # whose `:set` list has the same members in the same order.
  defp set_pattern(%Tempo.Set{type: type, set: members}) do
    member_asts = Enum.map(members, &set_member_pattern/1)

    quote do
      %Tempo.Set{type: unquote(type), set: unquote(member_asts)}
    end
  end

  defp set_member_pattern(%Tempo.Range{} = range), do: range_pattern(range)
  defp set_member_pattern(%Tempo{} = tempo), do: endpoint_pattern(tempo)
  defp set_member_pattern(%Tempo.Duration{} = duration), do: endpoint_pattern(duration)

  defp set_member_pattern(other) do
    raise ArgumentError,
          "~o sigil in a match context does not support set members of type " <>
            "#{inspect(other.__struct__)}"
  end

  # Append `{field, transform.(value)}` to `fields` when `value`
  # differs from its default (as reported by `default?`). Keeps
  # container patterns free of spurious constraints on fields the
  # sigil string didn't actually mention.
  defp maybe_put_field(fields, field, value, transform, default?) do
    if default?.(value) do
      fields
    else
      fields ++ [{field, transform.(value)}]
    end
  end
end
