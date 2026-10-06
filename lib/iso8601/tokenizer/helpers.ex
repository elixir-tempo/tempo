defmodule Tempo.Iso8601.Tokenizer.Helpers do
  @moduledoc false
  @doc false

  import NimbleParsec

  def recur([]), do: :infinity
  def recur([other]), do: other

  def sign do
    utf8_char([?+, ?-, ?−])
    |> unwrap_and_tag(:sign)
  end

  def zulu do
    ascii_char([?Z])
  end

  def colon do
    ascii_char([?:])
  end

  def dash do
    utf8_char([?-, ?‐])
  end

  def decimal_separator do
    ascii_char([?,, ?.])
  end

  # The sign before a fraction's digits: a full stop, or a comma where a
  # comma does not separate the members of a set.
  def decimal_sign do
    choice([
      ignore(ascii_char([?.])),
      decimal_comma()
    ])
  end

  # A comma as a decimal sign. It is read through a combinator of its own
  # (`Tempo.Iso8601.Tokenizer.Set`'s `:decimal_comma`), so that being refused
  # inside a set is an alternative that fails, where an error returned from
  # a traversal in line ends the whole parse.
  def decimal_comma do
    parsec({Tempo.Iso8601.Tokenizer.Set, :decimal_comma})
  end

  # A set's members are separated by commas, so within one a comma is never
  # a decimal sign: `{2023,2020/2021}` is a year and an interval, where
  # reading `2023,2020` as a number made it one interval from the year
  # 2023.2020. A fraction in a member is written with a full stop. How deep
  # in sets the text being read is, is kept in the parser's context, which
  # goes back to what it was when an alternative fails.
  def members_of_a_set(combinator, members) do
    combinator
    |> post_traverse(empty(), {__MODULE__, :enter_set, []})
    |> concat(members)
    |> post_traverse(empty(), {__MODULE__, :leave_set, []})
  end

  @doc false
  def enter_set(rest, args, context, _line, _offset),
    do: {rest, args, Map.update(context, :set_depth, 1, &(&1 + 1))}

  @doc false
  def leave_set(rest, args, context, _line, _offset),
    do: {rest, args, Map.update(context, :set_depth, 0, &(&1 - 1))}

  @doc false
  def outside_a_set(rest, args, context, _line, _offset) do
    if Map.get(context, :set_depth, 0) > 0,
      do: {:error, "a comma separates the members of a set"},
      else: {rest, args, context}
  end

  # A combinator read once at each place it is tried: what it read there, or
  # that it was refused there, is kept while the text is read
  # (`Tempo.Iso8601.Tokenizer.Memo`). `opening` is what its text starts
  # with, so that a place that does not open one costs no more than it did.
  #
  # It is read through three combinators of its own, `name_read_before`,
  # `name_read_now` and `name_refused`, each of which
  # `Tempo.Iso8601.Tokenizer.Set` defines from the three functions below: a
  # traversal that returns an error is its combinator failing, and the next
  # of the three is tried.
  def read_once(name, opening) do
    lookahead(string(opening))
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :"#{name}_read_before"}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :"#{name}_read_now"}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :"#{name}_refused"})
    ])
  end

  def read_before(name),
    do: post_traverse(empty(), {Tempo.Iso8601.Tokenizer.Memo, :read_before, [name]})

  def read_now(name, combinator) do
    post_traverse(
      post_traverse(empty(), {Tempo.Iso8601.Tokenizer.Memo, :start, [name]})
      |> concat(combinator),
      {Tempo.Iso8601.Tokenizer.Memo, :keep, [name]}
    )
  end

  def refused(name),
    do: post_traverse(empty(), {Tempo.Iso8601.Tokenizer.Memo, :refused, [name]})

  def negative do
    ascii_char([?-])
  end

  # The leading `+` of an ISO 8601-2 expanded year (`+12022`). The
  # sign is mandatory for the expanded form, which is what keeps it
  # from clashing with unsigned basic-format dates (`20220615`).
  def positive do
    ascii_char([?+])
  end

  def digit do
    ascii_char([?0..?9])
  end

  def unspecified do
    ascii_char([?X])
  end

  def all_unspecified do
    string("X*")
    |> replace(:"X*")
  end

  def day_of_week do
    ascii_char([?1..?7])
    |> reduce({List, :to_integer, []})
  end

  def quarter do
    ascii_char([?1..?4])
    |> ascii_char([?Q])
    |> reduce(:reduce_quarter)
    |> unwrap_and_tag(:month)
  end

  def half do
    ascii_char([?1..?2])
    |> ascii_char([?H])
    |> reduce(:reduce_half)
    |> unwrap_and_tag(:month)
  end

  # Converts quarters to the ISO Standard quarters
  # which are "months" of 33, 34, 35, 36
  def reduce_quarter([int, ?Q]) do
    int - 16
  end

  # Converts semestral (half) to the ISO Standard semestrals
  # which are "months" of 40 and 41
  def reduce_half([int, ?H]) do
    int - 9
  end

  def convert_bc([int, "B"]) do
    -(int - 1)
  end

  def convert_bc([other]) do
    other
  end

  def extract_repeat_rule([{_type, rule}]) do
    rule
  end

  @doc """
  ISO 8601-2 / EDTF qualification suffix.

  `?` marks a date as **uncertain** (the value is a best guess).
  `~` marks it as **approximate** (the value is approximately correct,
  e.g. "circa 1850").  `%` marks both.

  """
  def qualification(combinator \\ empty()) do
    combinator
    |> choice([
      replace(string("?"), :uncertain),
      replace(string("~"), :approximate),
      replace(string("%"), :uncertain_and_approximate)
    ])
    |> unwrap_and_tag(:qualification)
  end

  @doc """
  ISO 8601-2 §8.2.3 *individual* qualification — a qualifier symbol
  immediately to the **left** of a component (implicit form). It
  qualifies that component **only**.

  Emitted as `{:individual_qualification, {unit, qualifier}}`.

  """
  def left_qualifier(combinator \\ empty(), unit) do
    combinator
    |> concat(
      empty()
      |> qualifier_symbol()
      |> reduce({__MODULE__, :pair_with_unit, [unit]})
      |> unwrap_and_tag(:individual_qualification)
    )
  end

  @doc """
  ISO 8601-2 §8.2.2 *group* qualification — a qualifier symbol
  immediately to the **right** of a component. It qualifies that
  component's value **and all components to its left** (of coarser
  resolution). When the component is the rightmost of the whole
  expression the consumer instead treats it as §8.2.1 *complete*
  qualification.

  Emitted as `{:group_qualification, {unit, qualifier}}`.

  """
  def right_qualifier(combinator \\ empty(), unit) do
    combinator
    |> concat(
      empty()
      |> qualifier_symbol()
      |> reduce({__MODULE__, :pair_with_unit, [unit]})
      |> unwrap_and_tag(:group_qualification)
    )
  end

  @doc false
  def pair_with_unit([qualifier], unit), do: {unit, qualifier}

  defp qualifier_symbol(combinator) do
    combinator
    |> choice([
      replace(string("?"), :uncertain),
      replace(string("~"), :approximate),
      replace(string("%"), :uncertain_and_approximate)
    ])
  end

  @doc """
  Merge a trailing `{:qualification, _}` token into the preceding
  tagged date/datetime/time inner list. Used by the
  `:qualified_endpoint` parsec to keep each interval endpoint and
  its qualification paired.

  Returns a single tuple so that the reduce emits one value into
  the enclosing parser accumulator, matching the shape emitted by
  `parsec(:datetime_or_date_or_time)` when no qualifier is present.

  """

  # Strip out an optional IXDTF extended-info segment from the
  # reducer input first, then delegate to the qualification-only
  # clauses below. When present, the `{:extended, segments}` entry
  # is appended verbatim to the endpoint's inner list; downstream
  # `Extended.split_extended/1` walks interval tokens and swaps the
  # raw segments for a validated extended_info map.

  def merge_endpoint_qualification(tokens) do
    case Enum.split_with(tokens, &match?({:extended, _}, &1)) do
      {[], tokens} -> merge_qualification(tokens)
      {[{:extended, segments}], tokens} -> merge_qualification(tokens, segments)
    end
  end

  defp merge_qualification(tokens, segments \\ nil)

  defp merge_qualification([{tag, inner}], segments)
       when tag in [:date, :datetime, :time_of_day] do
    {tag, inner ++ extended_entry(segments)}
  end

  defp merge_qualification([{tag, inner}, {:qualification, q}], segments)
       when tag in [:date, :datetime, :time_of_day] do
    {tag, inner ++ [qualification: q] ++ extended_entry(segments)}
  end

  defp merge_qualification([{:qualification, q}, {tag, inner}], segments)
       when tag in [:date, :datetime, :time_of_day] do
    {tag, inner ++ [qualification: q] ++ extended_entry(segments)}
  end

  # Both leading and trailing qualifiers present. The leading
  # applies to the whole expression; the trailing applies to the
  # last component. We keep the leading one on the expression-level
  # field and leave the trailing to be handled as a component
  # qualifier by the inner grammar.
  defp merge_qualification(
         [{:qualification, q1}, {tag, inner}, {:qualification, q2}],
         segments
       )
       when tag in [:date, :datetime, :time_of_day] do
    {tag,
     inner ++
       [qualification: q1] ++ [trailing_qualification: q2] ++ extended_entry(segments)}
  end

  # Single-value pass-through (e.g. a duration or interval token that
  # was not wrapped by date/datetime/time_of_day).
  defp merge_qualification(other, _segments), do: other

  defp extended_entry(nil), do: []
  defp extended_entry(segments), do: [extended: segments]

  @doc false
  # A member of a set with its qualifiers, read as a value written alone
  # is (ISO 8601-2 §8.2): a qualifier after the member qualifies the whole
  # of it (§8.2.1), and one before it the first component it is written with
  # (§8.2.3). Each goes into the member's own tokens, where
  # `Tempo.Iso8601.AST.build/2` reads it.
  #
  # A member's own suffix (`[Europe/Paris]`) goes there too, as an end of an
  # interval's does (`merge_endpoint_qualification/1`).
  def merge_member_qualification(tokens) do
    case Enum.split_with(tokens, &match?({:extended, _segments}, &1)) do
      {[], tokens} -> member_with_qualifiers(tokens)
      {[{:extended, segments}], tokens} -> with_suffix(member_with_qualifiers(tokens), segments)
    end
  end

  defp with_suffix({tag, inner}, segments), do: {tag, inner ++ [extended: segments]}

  defp member_with_qualifiers([{tag, inner}]) when tag in [:date, :datetime, :time_of_day],
    do: {tag, inner}

  defp member_with_qualifiers([{tag, inner}, {:qualification, complete}])
       when tag in [:date, :datetime, :time_of_day],
       do: {tag, inner ++ [qualification: complete]}

  defp member_with_qualifiers([{:qualification, leading}, {tag, inner} | trailing])
       when tag in [:date, :datetime, :time_of_day] do
    {tag, qualified} = member_with_qualifiers([{tag, inner} | trailing])
    {tag, qualified ++ first_component_qualification(inner, leading)}
  end

  # The component a qualifier before a value qualifies: the first of them,
  # or the whole value where it is written with none of these.
  @qualified_from_the_left [:year, :month, :week, :day, :day_of_year, :day_of_week] ++
                             [:hour, :minute, :second]

  defp first_component_qualification(inner, qualifier) do
    case Enum.find(inner, &(is_tuple(&1) and elem(&1, 0) in @qualified_from_the_left)) do
      nil -> [qualification: qualifier]
      component -> [individual_qualification: {elem(component, 0), qualifier}]
    end
  end

  # Some calendars have 13 months
  # Seasons are recognised as months 21..32 so we have to allow them
  # Quarters are recognised as months 33..36 so we have to allow them
  # Quadrimesters are recognised as months 36..39 so we have to allow them
  # Semestrals are recognised as momths 40..41 so we have to allow them

  def check_valid_date(
        _rest,
        [[{:year, _year}, {:month, month} | _remaining]],
        _context,
        _line,
        _offset
      )
      when is_number(month) and month > 13 and month not in 21..41 do
    {:error, "invalid month"}
  end

  def check_valid_date(_rest, [[{:month, month}, _remaining]], _context, _line, _offset)
      when is_number(month) and month > 13 and month not in 21..41 do
    {:error, "invalid month"}
  end

  # No supported calendars have more than 31 days in a month
  def check_valid_date(
        _rest,
        [[{:year, _year}, {:month, _month}, {:day, day} | _remaining]],
        _context,
        _line,
        _offset
      )
      when is_number(day) and day > 31 do
    {:error, "invalid day"}
  end

  def check_valid_date(
        _rest,
        [[{:month, _month}, {:day, day} | _remaining]],
        _context,
        _line,
        _offset
      )
      when is_number(day) and day > 31 do
    {:error, "invalid day"}
  end

  def check_valid_date(_rest, [[{:day, day}, _remaining]], _context, _line, _offset)
      when is_number(day) and day > 31 do
    {:error, "invalid day"}
  end

  def check_valid_date(rest, args, context, _line, _offset) do
    {rest, args, context}
  end
end
