defmodule Tempo.Reader do
  @moduledoc false

  # ISO 8601-1, ISO 8601-2 and RFC 9557 text to an expression: the grammar of
  # guides/iso8601-grammar.md, one function per production. The text is split
  # first at the places the grammar makes structural (the suffix, a leading
  # `R`, the `/` of an interval outside braces, the braces of a set), and each
  # piece is read by its form. The result is a `%Tempo{}` or a `%Tempo.Duration{}`
  # before validation: `Tempo.Validate` runs once over what is built.

  alias Tempo.Duration
  alias Tempo.InvalidCalendarError
  alias Tempo.ParseError
  alias Tempo.Reader.Implied
  alias Tempo.Reader.Number
  alias Tempo.Reader.Selection
  alias Tempo.Reader.Suffix
  alias Tempo.Reader.Value
  alias Tempo.Season
  alias Tempo.Unit
  alias Tempo.Validate

  @suffix_inside "a zone, a calendar or a tag is written once, after the whole expression"

  @doc """
  Reads a text. Options: `:calendar`, the calendar a text that names none is
  in (the default is `Calendar.ISO`).
  """
  @spec read(String.t(), keyword()) ::
          {:ok, Tempo.t() | Duration.t()} | {:error, ParseError.t() | Exception.t()}
  def read(text, options \\ []) when is_binary(text) do
    with {:ok, body, suffix} <- split_suffix(text),
         {:ok, calendar} <- calendar(suffix, options, text),
         {:ok, calendar} <- week_start(suffix, calendar, text),
         {:ok, expression} <- body |> normalised() |> expression(text) |> suffix_inside() do
      expression
      |> in_frame(calendar, suffix)
      |> seasons_placed(options[:territory])
      |> validated()
    end
  end

  # With a territory named, a season of 21 to 24 is given its months there
  # as it is read, before the order of an interval's ends is held to: the
  # autumn of a year comes before its spring south of the equator.
  defp seasons_placed(expression, nil), do: {:ok, expression}

  defp seasons_placed(%Tempo{} = expression, territory),
    do: Season.in_territory(expression, territory)

  defp seasons_placed(duration, _territory), do: {:ok, duration}

  defp validated({:ok, expression}), do: Validate.run(expression)
  defp validated({:error, _exception} = error), do: error

  # A zone, a calendar or a tag written on an end of an interval, on a member
  # of a set or on a recurrence's start: the reader stops at it, and says
  # where it belongs (law 5) rather than only that it could not go on. What
  # the reader stops at where the text ends is a suffix it could not read,
  # in its place.
  defp suffix_inside({:error, %ParseError{text: text, rest: rest} = error})
       when is_binary(rest) do
    inside? =
      not String.ends_with?(text, rest) and
        Regex.match?(~r/\[!?(?:[A-Za-z_][^\[\]{},]*|[+-]\d\d(?::?\d\d)?)\]/, rest)

    if inside?, do: {:error, %{error | reason: @suffix_inside}}, else: {:error, error}
  end

  defp suffix_inside(read), do: read

  # ISO 8601-1 §3.4.2 writes the hyphen as U+2010 and the minus as U+2212 where
  # the character set has them; RFC 3339 §5.6 lets `T` and `Z` be lower case
  # and a date and a time be separated by a space. All are read as the ASCII
  # forms, which is the one way the writer writes them.
  defp normalised(body) do
    body
    |> String.replace(["\u2010", "\u2212"], "-")
    |> String.replace(~r/(?<=\d)[t ](?=\d\d:)/, "T")
    |> String.replace(~r/(?<=\d)z(?=\z|[\/,\]}])/, "Z")
  end

  defp split_suffix(text) do
    case Suffix.split(text) do
      {:ok, body, suffix} -> {:ok, body, suffix}
      {:error, %{__struct__: _} = exception} -> {:error, exception}
      {:error, reason} -> {:error, ParseError.exception(text: text, reason: reason)}
    end
  end

  defp calendar(%{calendar: nil}, options, _text) do
    calendar = Keyword.get(options, :calendar, Tempo.Calendar.default())

    if Tempo.Calendar.calendar?(calendar),
      do: {:ok, calendar},
      else: {:error, InvalidCalendarError.exception(calendar: calendar)}
  end

  defp calendar(%{calendar: type}, _options, text) do
    case Tempo.Calendar.from_type(type) do
      {:ok, calendar} -> {:ok, calendar}
      {:error, _} -> {:error, ParseError.exception(text: text, reason: {:calendar, type})}
    end
  end

  # `[u-fw=sun]`: the calendar's weeks begin on the day named.
  defp week_start(%{week_start: nil}, calendar, _text), do: {:ok, calendar}

  defp week_start(%{week_start: name}, calendar, text) do
    case Tempo.Calendar.week_start_named(name) do
      {:ok, day} -> calendar |> Tempo.Calendar.with_week_start(day) |> week_start_read(name, text)
      :error -> week_start_read(:error, name, text)
    end
  end

  defp week_start_read({:ok, calendar}, _name, _text), do: {:ok, calendar}

  defp week_start_read(:error, name, text),
    do:
      {:error,
       ParseError.exception(
         text: text,
         reason:
           "[u-fw=#{name}] names no day a week begins on: it is one of mon, tue, wed, thu, fri, sat and sun"
       )}

  defp week_start_read({:error, %ArgumentError{}}, name, text),
    do:
      {:error,
       ParseError.exception(
         text: text,
         reason:
           "[u-fw=#{name}] is written for the Gregorian calendar only: another calendar has its own weeks"
       )}

  # The expression's calendar, zone and tags are every part's (law 5).
  defp in_frame(%Duration{} = duration, _calendar, _suffix), do: duration

  defp in_frame(%Tempo{} = expression, calendar, suffix) do
    metadata = if suffix.tags == %{}, do: %{}, else: %{ixdtf_tags: suffix.tags}
    framed(expression, calendar, suffix.zone) |> Map.put(:metadata, metadata)
  end

  defp framed(%Duration{} = duration, _calendar, _zone), do: duration

  defp framed(%Tempo{form: form} = expression, calendar, zone) do
    %{expression | calendar: calendar, zone: zone, form: framed_form(form, calendar, zone)}
  end

  defp framed_form({:value, _} = form, _, _), do: form

  defp framed_form({:span, from, to}, calendar, zone),
    do: {:span, framed_end(from, calendar, zone), framed_end(to, calendar, zone)}

  defp framed_form({:every, first, bound, rule}, calendar, zone),
    do: {:every, framed(first, calendar, zone), framed_end(bound, calendar, zone), rule}

  defp framed_form({kind, members}, calendar, zone) when kind in [:all, :one],
    do: {kind, Enum.map(members, &framed_member(&1, calendar, zone))}

  defp framed_form({:when, member, conditions}, calendar, zone),
    do: {:when, framed(member, calendar, zone), conditions}

  defp framed_end(%Tempo{} = value, calendar, zone), do: framed(value, calendar, zone)
  defp framed_end(other, _calendar, _zone), do: other

  defp framed_member({:except, member}, calendar, zone),
    do: {:except, framed(member, calendar, zone)}

  defp framed_member(member, calendar, zone), do: framed(member, calendar, zone)

  # ── expression = recurrence / set / interval / duration / value ───────

  defp expression(<<"R", rest::binary>> = body, text) do
    case count(rest, text) do
      {:ok, count, <<"/", rest::binary>>} ->
        recurrence(count, rest, text)

      _ ->
        {:error,
         ParseError.exception(
           text: text,
           rest: body,
           reason: "a recurrence is R, a count, a slash and an interval"
         )}
    end
  end

  defp expression(<<open, _::binary>> = body, text) when open in [?{, ?[] do
    if set?(body), do: set(body, text), else: interval_or_single(body, text)
  end

  defp expression(body, text), do: interval_or_single(body, text)

  # A set is braces or brackets closed with nothing after them but a filter letter;
  # a brace followed by a designator is a set in a unit of a value (`{1,3}M`).
  defp set?(<<open, rest::binary>>) do
    close = if open == ?{, do: "}", else: "]"

    case split_top(rest, close) do
      [_inside, after_close] -> after_close in ["", "e", "o", "l", "c"]
      _ -> false
    end
  end

  defp interval_or_single(body, text) do
    case split_top(body, "/") do
      [_single] ->
        single(body, text)

      [from, to] ->
        interval(from, to, text)

      _ ->
        {:error, ParseError.exception(text: text, rest: body, reason: "an interval has two ends")}
    end
  end

  # A duration, else a value in either form, which must use up the text.
  defp single(body, text) do
    case duration(body) do
      {:ok, duration} -> {:ok, duration}
      :error -> value(body, text)
    end
  end

  defp duration(<<"P", _::binary>> = body), do: whole_duration(body)
  defp duration(<<"-P", _::binary>> = body), do: whole_duration(body)
  defp duration(_body), do: :error

  defp whole_duration(body) do
    case Tempo.Reader.Duration.read(body) do
      {:ok, duration, ""} -> {:ok, duration}
      _ -> :error
    end
  end

  @doc false
  # A value in the explicit or an implied form.
  def value(body, text) do
    case read_value(body) do
      {:ok, read, ""} ->
        {:ok, build(read)}

      {:ok, _read, rest} ->
        {:error, ParseError.exception(text: text, rest: rest, reason: "text after the value")}

      :error ->
        {:error,
         ParseError.exception(
           text: text,
           rest: body,
           reason: "not a date, a time, an interval, a duration or a set"
         )}
    end
  end

  # The explicit form first; a text it does not use up is tried in the implied
  # form (`2026W25` is a year and a week, not the week 2026), and the reading
  # that got furthest is the one reported.
  defp read_value(body) do
    case Value.read(body) do
      {:ok, read, ""} -> {:ok, read, ""}
      {:ok, read, rest} -> furthest({:ok, read, rest}, Implied.read(body))
      :error -> Implied.read(body)
    end
  end

  defp furthest(_explicit, {:ok, read, ""}), do: {:ok, read, ""}

  defp furthest({:ok, _, rest} = explicit, {:ok, _, implied_rest} = implied),
    do: if(byte_size(implied_rest) < byte_size(rest), do: implied, else: explicit)

  defp furthest(explicit, :error), do: explicit

  defp build(%{units: units, qualifications: qualifications, shift: shift}) do
    %Tempo{form: {:value, units}, qualifications: qualifications, shift: shift}
  end

  # ── intervals ─────────────────────────────────────────────────────────

  defp interval(from, to, text) do
    with {:ok, from} <- interval_end(from, nil, text),
         {:ok, to} <- interval_end(to, from, text),
         :ok <- one_duration(from, to, text) do
      {:ok, %Tempo{form: {:span, from, to}}}
    end
  end

  defp interval_end("..", _start, _text), do: {:ok, :open}
  defp interval_end("", _start, _text), do: {:ok, :open}

  defp interval_end(body, start, text) do
    case duration(body) do
      {:ok, duration} -> {:ok, duration}
      :error -> value_end(body, start, text)
    end
  end

  # An end is read in the explicit form, else as an abbreviation of its start
  # (`02-20`, `20`, `T17`), else as a value of its own (ISO 8601-1 §5.5.1).
  defp value_end(body, %Tempo{form: {:value, start_units}} = start, text) do
    case {Value.read(body), Implied.read_abbreviated(body, start_units), Implied.read(body)} do
      {{:ok, read, ""}, _, _} ->
        {:ok, inherit(build(read), start)}

      {_, {:ok, read, ""}, _} ->
        {:ok, inherit(build(read), start)}

      {_, _, {:ok, read, ""}} ->
        {:ok, inherit(build(read), start)}

      _ ->
        {:error,
         ParseError.exception(text: text, rest: body, reason: "not an end of an interval")}
    end
  end

  defp value_end(body, _start, text) do
    case read_value(body) do
      {:ok, read, ""} ->
        {:ok, build(read)}

      _ ->
        {:error,
         ParseError.exception(text: text, rest: body, reason: "not an end of an interval")}
    end
  end

  # An end written to fewer units than its start inherits the start's coarser
  # units (ISO 8601-1 §5.5.1): `2026Y6M1D/7M1D`, `2026-06-15T09/T17`.
  defp inherit(%Tempo{form: {:value, [{first, _} | _] = units}} = to, start) do
    inherited = Unit.inherited(start_units(start), first)
    qualifications = inherited_qualifications(start.qualifications, inherited, to.qualifications)
    %{to | form: {:value, inherited ++ units}, qualifications: qualifications}
  end

  defp inherit(to, _start), do: to

  defp start_units(%Tempo{form: {:value, units}}), do: units

  # The inherited units carry the start's marks; the end's own marks stay.
  defp inherited_qualifications(nil, _inherited, own), do: own

  defp inherited_qualifications(marks, inherited, own) do
    case Map.take(marks, Keyword.keys(inherited)) do
      taken when map_size(taken) == 0 -> own
      taken -> Map.merge(taken, own || %{})
    end
  end

  defp one_duration(%Duration{}, %Duration{}, text),
    do:
      {:error,
       ParseError.exception(text: text, reason: "an interval has a duration at one end at most")}

  defp one_duration(_from, _to, _text), do: :ok

  # ── recurrences ───────────────────────────────────────────────────────

  defp count(<<"/", _::binary>> = rest, _text), do: {:ok, :infinity, rest}

  defp count(rest, _text), do: Number.digits(rest)

  # `R[n]/first/second[/F…]`: the first two pieces are the interval of the
  # first occurrence (a domain set, a value, a duration or `..` as the start),
  # the third the repeat rule.
  defp recurrence(count, rest, text) do
    case split_top(rest, "/") do
      [from, to] ->
        recurrence(count, from, to, nil, text)

      [from, to, <<"F", rule::binary>>] ->
        recurrence(count, from, to, rule, text)

      [from, to, until] when from != "" ->
        recurrence(count, from, to, nil, until, text)

      [from, to, until, <<"F", rule::binary>>] when from != "" ->
        recurrence(count, from, to, rule, until, text)

      _ ->
        {:error,
         ParseError.exception(
           text: text,
           rest: rest,
           reason: "a recurrence is an interval and, after a slash, an F rule"
         )}
    end
  end

  defp recurrence(count, from, to, rule, text) do
    with {:ok, from} <- recurrence_start(from, text),
         {:ok, to} <- interval_end(to, from, text),
         {:ok, parts} <- rule(rule, text) do
      {:ok, %Tempo{form: {:every, %Tempo{form: {:span, from, to}}, count, parts}}}
    end
  end

  # An until (Tempo's own, RFC 5545's UNTIL): a value after the interval the
  # occurrences run up to, in place of a count.
  defp recurrence(:infinity, from, to, rule, until, text) do
    with {:ok, %Tempo{form: {:every, first, _, parts}}} <-
           recurrence(:infinity, from, to, rule, text),
         {:ok, %Tempo{form: {:value, _}} = until} <- interval_end(until, nil, text) do
      {:ok, %Tempo{form: {:every, first, until, parts}}}
    end
  end

  defp recurrence(_count, _from, _to, _rule, until, text) do
    {:error,
     ParseError.exception(
       text: text,
       rest: until,
       reason: "a recurrence has a count or an until, not both"
     )}
  end

  # A start may be a domain: a set of years with exclusions and a filter,
  # or every year a filter keeps (`..e`), the years a window gives.
  # A set as the start is a domain (`R/{2026Y..2030Y}/P1Y`), with a filter
  # of its years or none after it; a set followed by units is one unit of a
  # value (`R3/{2026,2028}Y6M15D/P1D`), which starts the recurrence.
  defp recurrence_start(<<"{", rest::binary>> = body, text) do
    case split_top(rest, "}") do
      [_inside, filter] when filter in ["", "e", "o", "l", "c"] -> set(body, text)
      _a_value -> interval_end(body, nil, text)
    end
  end

  defp recurrence_start(<<"^", _::binary>> = body, text), do: set(body, text)

  defp recurrence_start(<<"..", filter::binary-size(1)>>, text) when filter in ~w(e o l c),
    do: filtered(%Tempo{form: {:span, :open, :open}}, filter, text)

  defp recurrence_start(body, text), do: interval_end(body, nil, text)

  defp rule(nil, _text), do: {:ok, nil}

  defp rule(rule, text) do
    case eligibility(rule) do
      {:ok, _eligibility, rest} -> rule_parts(selection_or_none(rest), rule, text)
      :error -> rule_error(rule, text)
    end
  end

  defp rule_parts({:ok, parts, ""}, _rule, _text), do: {:ok, parts}
  defp rule_parts(_read, rule, text), do: rule_error(rule, text)

  defp rule_error(rule, text) do
    {:error,
     ParseError.exception(
       text: text,
       rest: rule,
       reason: "a repeat rule is F, a cadence and a selection between L and N"
     )}
  end

  # `F2W`: the eligible intervals. Tempo reads the cadence from the interval,
  # so the count and the unit are accepted and set aside.
  defp eligibility(<<"L", _::binary>> = rest), do: {:ok, nil, rest}

  defp eligibility(rest) do
    case Number.digits(rest) do
      {:ok, count, <<designator::binary-size(1), rest::binary>>}
      when designator in ["Y", "M", "W", "D", "H", "S"] ->
        {:ok, {count, designator}, rest}

      _ ->
        :error
    end
  end

  defp selection_or_none(""), do: {:ok, nil, ""}
  defp selection_or_none(rest), do: Selection.read(rest)

  # ── sets ──────────────────────────────────────────────────────────────

  # `{a,b}` is all of its members, `[a,b]` one of them; a member is any
  # expression, a range of two (`a..b`), an open range (`..a`, `a..`) or an
  # exclusion (`^a`); a filter letter after the braces keeps the even, odd,
  # leap or common years.
  # An exclusion with no braces about it (`^2026Y`) is a set of it alone.
  defp set(<<"^", _::binary>> = body, text) do
    with {:ok, members} <- members(body, text), do: {:ok, %Tempo{form: {:all, members}}}
  end

  defp set(<<open, rest::binary>>, text) when open in [?{, ?[] do
    close = if open == ?{, do: "}", else: "]"
    kind = if open == ?{, do: :all, else: :one

    case split_top(rest, close) do
      [inside, filter] ->
        with {:ok, members} <- members(inside, text) do
          filtered(%Tempo{form: {kind, members}}, filter, text)
        end

      _ ->
        {:error, ParseError.exception(text: text, rest: rest, reason: "a set is not closed")}
    end
  end

  # An empty set, `{}`, is what a set operation leaves when nothing is shared.
  defp members("", _text), do: {:ok, []}

  defp members(inside, text) do
    inside
    |> split_top(",")
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case member(member, text) do
        {:ok, members} -> {:cont, {:ok, acc ++ members}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp member(<<"^", rest::binary>>, text) do
    with {:ok, [member]} <- member(rest, text), do: {:ok, [{:except, member}]}
  end

  # A member that is a recurrence is read whole: a `..` in it is its open
  # start (`R/../P1Y/FL12M25DN`) or its domain's, and no range of the set's.
  defp member(<<"R", _::binary>> = body, text) do
    if String.match?(body, ~r/\AR[0-9]*\//),
      do: with({:ok, expression} <- expression(body, text), do: {:ok, [expression]}),
      else: ranged_member(body, text)
  end

  defp member(body, text), do: ranged_member(body, text)

  # A member that is an interval with an open end, `2026-06-03/..` and
  # `../2026-06-03`, is that interval: its `..` is the end's, and no range's.
  # It is what "and later" (`2026-06-03..`) is written back as.
  defp ranged_member(body, text) do
    case split_top(body, "..") do
      [_single] ->
        with {:ok, expression} <- expression(body, text), do: {:ok, [expression]}

      [<<_, _::binary>> = lower, ""] when binary_part(lower, byte_size(lower), -1) == "/" ->
        with {:ok, expression} <- expression(body, text), do: {:ok, [expression]}

      ["", <<"/", _::binary>>] ->
        with {:ok, expression} <- expression(body, text), do: {:ok, [expression]}

      ["", "/", ""] ->
        with {:ok, expression} <- expression(body, text), do: {:ok, [expression]}

      ["", upper] ->
        with {:ok, upper} <- expression(upper, text),
             do: {:ok, [%Tempo{form: {:span, :open, upper}}]}

      [lower, ""] ->
        with {:ok, lower} <- expression(lower, text),
             do: {:ok, [%Tempo{form: {:span, lower, :open}}]}

      [lower, upper] ->
        range(lower, upper, text)

      _several_ranges ->
        range_error(body, text)
    end
  end

  # A range of two expressions is every value from the first to the last
  # (ISO 8601-2 §6.3): two values of one shape whose finest units are whole
  # numbers, kept as a set in that unit; or two durations alike, listed.
  defp range(lower, upper, text) do
    with {:ok, first} <- expression(lower, text),
         {:ok, last} <- expression(upper, text) do
      ranged(first, last, lower <> ".." <> upper, text)
    end
  end

  defp ranged(
         %Tempo{form: {:value, lower_units}} = first,
         %Tempo{form: {:value, upper_units}},
         written,
         text
       ) do
    case {Enum.drop(lower_units, -1), Enum.drop(upper_units, -1), List.last(lower_units),
          List.last(upper_units)} do
      {shape, shape, {unit, from}, {unit, to}} when is_integer(from) and is_integer(to) ->
        {:ok, [%{first | form: {:value, shape ++ [{unit, [from..to]}]}}]}

      _ ->
        range_error(written, text)
    end
  end

  defp ranged(%Duration{units: lower_units}, %Duration{units: upper_units}, written, text) do
    case {Enum.drop(lower_units, -1), Enum.drop(upper_units, -1), List.last(lower_units),
          List.last(upper_units)} do
      {shape, shape, {unit, from}, {unit, to}} when is_integer(from) and is_integer(to) ->
        {:ok, Enum.map(from..to, fn n -> %Duration{units: shape ++ [{unit, n}]} end)}

      _ ->
        range_error(written, text)
    end
  end

  defp ranged(_first, _last, written, text), do: range_error(written, text)

  defp range_error(written, text) do
    {:error,
     ParseError.exception(
       text: text,
       rest: written,
       reason: "a range runs between two values of one shape"
     )}
  end

  defp filtered(set, "", _text), do: {:ok, set}
  defp filtered(set, "e", _text), do: {:ok, %Tempo{form: {:when, set, years: :even}}}
  defp filtered(set, "o", _text), do: {:ok, %Tempo{form: {:when, set, years: :odd}}}
  defp filtered(set, "l", _text), do: {:ok, %Tempo{form: {:when, set, years: :leap}}}
  defp filtered(set, "c", _text), do: {:ok, %Tempo{form: {:when, set, years: :common}}}

  defp filtered(_set, rest, text),
    do: {:error, ParseError.exception(text: text, rest: rest, reason: "text after the set")}

  # ── splitting ─────────────────────────────────────────────────────────

  # Splits at a separator outside braces, brackets and parentheses. A `/`
  # inside a selection (`L…/P5DN`) is inside its `L…N` and is not split.
  @doc false
  def split_top(text, separator) do
    split_top(text, separator, 0, "", [])
  end

  defp split_top("", _separator, _depth, current, acc), do: Enum.reverse([current | acc])

  defp split_top(text, separator, depth, current, acc) do
    size = byte_size(separator)

    case text do
      <<^separator::binary-size(^size), rest::binary>> when depth == 0 ->
        split_top(rest, separator, depth, "", [current | acc])

      <<"L", rest::binary>> when separator == "/" ->
        {inside, rest} = selection_text(rest)
        split_top(rest, separator, depth, current <> "L" <> inside, acc)

      <<char::utf8, rest::binary>> ->
        depth = depth + opening(char) - closing(char)
        split_top(rest, separator, depth, current <> <<char::utf8>>, acc)
    end
  end

  # The text of a selection up to and including its closing `N`, nested pairs counted.
  defp selection_text(text), do: selection_text(text, 1, "")
  defp selection_text("", _depth, acc), do: {acc, ""}

  defp selection_text(<<"L", rest::binary>>, depth, acc),
    do: selection_text(rest, depth + 1, acc <> "L")

  defp selection_text(<<"N", rest::binary>>, 1, acc), do: {acc <> "N", rest}

  defp selection_text(<<"N", rest::binary>>, depth, acc),
    do: selection_text(rest, depth - 1, acc <> "N")

  defp selection_text(<<char::utf8, rest::binary>>, depth, acc),
    do: selection_text(rest, depth, acc <> <<char::utf8>>)

  # The code points of `{`, `[` and `(`, and of `}`, `]` and `)`.
  defp opening(char) when char in [123, 91, 40], do: 1
  defp opening(_char), do: 0
  defp closing(char) when char in [125, 93, 41], do: 1
  defp closing(_char), do: 0
end
