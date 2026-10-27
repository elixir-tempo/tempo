defmodule Tempo.Reader.DateRule do
  @moduledoc false

  # The date-holidays rule grammar (https://github.com/commenthol/date-holidays),
  # read as date-holidays-parser (v3.4.7, `src/Parser.js`) reads it, into its
  # tokens: one reader for each of its token kinds, tried in its order at the
  # start of what is left, and the tokens reordered as it reorders them, the
  # base date first and its weekday steps after it, the one nearest it first.
  # Its own test fixture of 119 rules is the golden test
  # (`test/tempo/reader/date_rule_test.exs`). A token is a map of the parser's
  # fields, snake-cased (`leap_month`), holding the parser's values.
  #
  # A rule is an optional chain of weekday steps (`Friday after`, `2nd Sunday
  # before`, `4 days after`), one base date (a fixed date, a month, Easter, an
  # equinox, a date in the Islamic, Hebrew, Persian, Chinese, Korean,
  # Vietnamese or Bengali calendar), an optional time and duration, then
  # modifiers (`if … then …`, `substitutes`, `and`, a year or weekday filter,
  # a bridge, `if is holiday then …`, `since`, `prior to`).
  #
  # One difference: the parser's `on <weekdays>` pattern is not anchored, so
  # it can match within a rule and then cut the wrong text from its start;
  # here it is read only at the start of what is left, as every other part is.

  @weekdays "[Ss]unday|[Mm]onday|[Tt]uesday|[Ww]ednesday|[Tt]hursday|[Ff]riday|[Ss]aturday|day"
  @months "January|February|March|April|May|June|July|August|September|October|November|December"
  @islamic_months "Muharram|Safar|Rabi al-awwal|Rabi al-thani|Jumada al-awwal|Jumada al-thani|" <>
                    "Rajab|Shaban|Ramadan|Shawwal|Dhu al-Qidah|Dhu al-Hijjah"
  @hebrew_months "Nisan|Iyyar|Sivan|Tamuz|Av|Elul|Tishrei|Cheshvan|Kislev|Tevet|Shvat|AdarII|Adar"
  @jalaali_months "Farvardin|Ordibehesht|Khordad|Tir|Mordad|Shahrivar|Mehr|Aban|Azar|Dey|Bahman|Esfand"
  @days "(#{@weekdays})s?"
  @direction "(before|after|next|previous|in)"
  @counts "(\\d+)(?:st|nd|rd|th)?"
  @weekday_list "((?:(?:#{@weekdays})(?:,\\s?)?)*)"
  @type_names "(public|bank|school|observance|optional)"
  @date "(?:0*(\\d{1,4})-)?0?(\\d{1,2})-0?(\\d{1,2})"

  @patterns %{
    date: ~r/^#{@date}/,
    julian: ~r/^julian #{@date}/,
    easter: ~r/^(easter|orthodox)(?: ([-+]?\d{1,2}) ?(?:days?|d)?)?/,
    equinox:
      ~r/^([Mm]arch|[Jj]une|[Ss]eptember|[Dd]ecember) (?:equinox|solstice)(?: in ([^\s]*|[+-]\d{2}:\d{2}))?/,
    islamic: ~r/^0?(\d{1,2}) (#{@islamic_months})(?: 0*(\d{1,}))?/,
    hebrew: ~r/^0?(\d{1,2}) (#{@hebrew_months})(?: 0*(\d{1,}))?/,
    jalaali: ~r/^0?(\d{1,2}) (#{@jalaali_months})(?: 0*(\d{1,}))?/,
    chinese_solar:
      ~r/^(chinese|korean|vietnamese) (?:(\d+)-(\d{1,2})-)?(\d{1,2})-(\d{1,2}) solarterm/,
    chinese_lunar:
      ~r/^(chinese|korean|vietnamese) (?:(\d+)-(\d{1,2})-)?(\d{1,2})-([01])-(\d{1,2})/,
    bengali_revised: ~r/^(bengali-revised) (?:-?0*(\d{1,4})-)?0?(\d{1,2})-0?(\d{1,2})/,
    date_month: ~r/^(#{@months})/,
    date_if_then: ~r/^if #{@weekday_list} then (?:#{@direction} #{@days})?/,
    weekday: ~r/^(not )?on #{@weekday_list}/,
    year: ~r/^(?:in (even|odd|leap|non-leap) years|every (\d+) years? since 0*(\d{1,4}))/,
    date_dir: ~r/^(?:#{@counts} )?#{@days} #{@direction}/,
    if_holiday:
      ~r/^if is (?:#{@type_names} )?holiday then (?:#{@counts} )?(?:#{@direction} #{@days})?(?: omit #{@weekday_list})?/,
    bridge: ~r/^is (?:#{@type_names} )?holiday/,
    time: ~r/^(?:T?0?(\d{1,2}):0?(\d{1,2})|T0?(\d{1,2}))/,
    duration: ~r/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?/,
    modifier: ~r/^(substitutes|and|if equal|then|if)\b/,
    same_day: ~r/^#\d+/,
    active_from: ~r/^since (0*\d{1,4})(?:-0*(\d{1,2})(?:-0*(\d{1,2})|)|)(?: and|)/,
    active_to: ~r/^prior to (0*\d{1,4})(?:-0*(\d{1,2})(?:-0*(\d{1,2})|)|)/,
    space: ~r/^\s+/
  }

  # The parser's readers, in its order: the first to match at the start of
  # what is left reads it.
  @readers [
    :julian,
    :date,
    :easter,
    :islamic,
    :hebrew,
    :jalaali,
    :equinox,
    :chinese_solar,
    :chinese_lunar,
    :bengali_revised,
    :date_month,
    :date_if_then,
    :weekday,
    :year,
    :date_dir,
    :if_holiday,
    :bridge,
    :time,
    :duration,
    :modifier,
    :same_day,
    :active_from,
    :active_to
  ]

  @month_numbers @months
                 |> String.split("|")
                 |> Enum.with_index(1)
                 |> Map.new()
  @islamic_month_numbers @islamic_months
                         |> String.split("|")
                         |> Enum.with_index(1)
                         |> Map.new()
  @jalaali_month_numbers @jalaali_months
                         |> String.split("|")
                         |> Enum.with_index(1)
                         |> Map.new()

  # The parser numbers the Hebrew months by their place in its list, then
  # gives Adar 12 and AdarII 13 (AdarII is listed first so it is matched
  # before Adar).
  @hebrew_month_numbers @hebrew_months
                        |> String.split("|")
                        |> Enum.with_index(1)
                        |> Map.new()
                        |> Map.merge(%{"Adar" => 12, "AdarII" => 13})

  @capitalised_weekdays ~w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)

  # A token: a map of the parser's fields, snake-cased.
  @type token :: %{optional(atom()) => term()}

  # Reads a rule into its tokens, as date-holidays-parser does.
  @spec tokens(String.t()) :: {:ok, [token()]} | {:error, {:unread, String.t()}}
  def tokens(rule) when is_binary(rule) do
    case tokenize(rule) do
      {tokens, ""} -> {:ok, tokens}
      {_tokens, rest} -> {:error, {:unread, rest}}
    end
  end

  # Reads a rule as far as the grammar goes, as date-holidays-parser does.
  @spec tokenize(String.t()) :: {[token()], String.t()}
  def tokenize(rule) when is_binary(rule) do
    {tokens, rest} = read(rule, @readers, [], nil)
    {reordered(Enum.reverse(tokens)), rest}
  end

  # The parser's loop: a reader, then any space; a pass that reads nothing
  # ends it, leaving the rest unread.
  defp read("", _readers, tokens, _last) do
    {tokens, ""}
  end

  defp read(rest, _readers, tokens, rest) do
    {tokens, rest}
  end

  defp read(text, readers, tokens, _last) do
    {tokens, rest} = read_one(text, readers, tokens)
    read(skip_space(rest), readers, tokens, text)
  end

  defp read_one(text, readers, tokens) do
    Enum.find_value(readers, {tokens, text}, fn reader ->
      case read_part(reader, text) do
        nil -> nil
        {token, rest} -> {push(token, tokens), rest}
      end
    end)
  end

  defp push(nil, tokens) do
    tokens
  end

  defp push(token, tokens) do
    [token | tokens]
  end

  defp skip_space(text) do
    case Regex.run(@patterns.space, text) do
      [space] -> drop(text, space)
      nil -> text
    end
  end

  defp drop(text, matched) do
    binary_part(text, byte_size(matched), byte_size(text) - byte_size(matched))
  end

  # The base date first, each run of weekday steps after the token that
  # follows it, the one nearest that token first; and no modifier before a
  # base date. Steps that no token follows are dropped, as the parser drops
  # them.
  defp reordered(tokens) do
    {result, _steps} =
      Enum.reduce(tokens, {[], []}, fn token, {result, steps} ->
        if date_dir?(token) do
          {result, [token | steps]}
        else
          {modifiers_after_a_date(result ++ [token | steps], token), []}
        end
      end)

    result
  end

  defp date_dir?(%{rule: "dateDir"}) do
    true
  end

  defp date_dir?(_token) do
    false
  end

  defp modifiers_after_a_date([%{modifier: _} | _] = result, %{fn: _}) do
    {modifiers, rest} = Enum.split_while(result, &Map.has_key?(&1, :modifier))
    rest ++ modifiers
  end

  defp modifiers_after_a_date(result, _token) do
    result
  end

  # ── the readers: each the parser's `_<kind>`, giving its token ─────────

  defp read_part(:space, _text) do
    nil
  end

  defp read_part(:date_if_then, text) do
    with [matched | captures] <- Regex.run(@patterns.date_if_then, text) do
      [weekdays, direction, then] = padded(captures, 3)
      {rules, rest} = read(drop(text, matched), [:time, :duration], [], nil)

      token =
        compact(%{
          rule: "dateIfThen",
          if: weekday_list(weekdays),
          direction: blank(direction),
          then: weekday_name(blank(then)),
          rules: non_empty(Enum.reverse(rules))
        })

      {token, " " <> rest}
    end
  end

  defp read_part(reader, text) do
    with [matched | captures] <- Regex.run(Map.fetch!(@patterns, reader), text) do
      {token(reader, captures), drop(text, matched)}
    end
  end

  defp token(:date, captures) do
    [year, month, day] = numbers(captures, 3)
    compact(%{fn: "gregorian", year: year, month: month, day: day})
  end

  defp token(:julian, captures) do
    [year, month, day] = numbers(captures, 3)
    compact(%{fn: "julian", year: year, month: month, day: day})
  end

  defp token(:easter, captures) do
    [type, offset] = padded(captures, 2)
    %{fn: "easter", type: type, offset: number(offset) || 0}
  end

  defp token(:equinox, captures) do
    [season, zone] = padded(captures, 2)
    %{fn: "equinox", season: String.downcase(season), timezone: blank(zone) || "GMT"}
  end

  defp token(:islamic, captures) do
    calendar_date("islamic", captures, @islamic_month_numbers)
  end

  defp token(:hebrew, captures) do
    calendar_date("hebrew", captures, @hebrew_month_numbers)
  end

  defp token(:jalaali, captures) do
    calendar_date("jalaali", captures, @jalaali_month_numbers)
  end

  defp token(:chinese_solar, captures) do
    [calendar | rest] = padded(captures, 5)
    [cycle, year, term, day] = Enum.map(rest, &number/1)
    compact(%{fn: calendar, cycle: cycle, year: year, solarterm: term, day: day})
  end

  defp token(:chinese_lunar, captures) do
    [calendar | rest] = padded(captures, 6)
    [cycle, year, month, leap, day] = Enum.map(rest, &number/1)

    compact(%{
      fn: calendar,
      cycle: cycle,
      year: year,
      month: month,
      leap_month: leap == 1,
      day: day
    })
  end

  defp token(:bengali_revised, captures) do
    [calendar | rest] = padded(captures, 4)
    [year, month, day] = Enum.map(rest, &number/1)
    compact(%{fn: calendar, year: year, month: month, day: day})
  end

  defp token(:date_month, [month]) do
    %{fn: "gregorian", day: 1, month: Map.fetch!(@month_numbers, month)}
  end

  defp token(:weekday, captures) do
    [negated, weekdays] = padded(captures, 2)
    %{rule: "weekday", not: negated != "", if: weekday_list(weekdays)}
  end

  defp token(:year, captures) do
    [cardinality, every, since] = padded(captures, 3)

    compact(%{
      rule: "year",
      cardinality: blank(cardinality),
      every: number(every),
      since: number(since)
    })
  end

  defp token(:date_dir, captures) do
    [count, weekday, direction] = padded(captures, 3)

    %{
      rule: "dateDir",
      count: number(count) || 1,
      weekday: weekday_name(weekday),
      direction: step_direction(direction)
    }
  end

  defp token(:if_holiday, captures) do
    [type, count, direction, weekday, omit] = padded(captures, 5)

    compact(%{
      rule: "ruleIfHoliday",
      type: blank(type),
      count: number(count) || 1,
      direction: blank(direction),
      weekday: weekday_name(blank(weekday)),
      omit: omitted(omit)
    })
  end

  defp token(:bridge, captures) do
    [type] = padded(captures, 1)
    compact(%{rule: "bridge", type: blank(type)})
  end

  defp token(:time, captures) do
    [hour, minute, hour_alone] = numbers(captures, 3)
    %{rule: "time", hour: nonzero(hour) || hour_alone || 0, minute: minute || 0}
  end

  defp token(:duration, captures) do
    [days, hours, minutes] = numbers(captures, 3)
    %{rule: "duration", duration: (days || 0) * 24 + (hours || 0) + (minutes || 0) / 60}
  end

  defp token(:modifier, [modifier]) do
    %{modifier: modifier}
  end

  defp token(:same_day, _captures) do
    nil
  end

  defp token(:active_from, captures) do
    active("activeFrom", captures)
  end

  defp token(:active_to, captures) do
    active("activeTo", captures)
  end

  # A step "in" a month is a step after its first day.
  defp step_direction("in") do
    "after"
  end

  defp step_direction(direction) do
    direction
  end

  # The weekdays an `omit` names, `day` and empty names left out.
  defp omitted(text) do
    text
    |> weekday_list()
    |> Enum.reject(&(&1 in ["", "day"]))
  end

  defp calendar_date(calendar, captures, months) do
    [day, month, year] = padded(captures, 3)

    compact(%{
      fn: calendar,
      day: number(day),
      month: Map.fetch!(months, month),
      year: number(year)
    })
  end

  defp active(rule, captures) do
    [year, month, day] = numbers(captures, 3)
    %{rule: rule, year: year, month: month || 1, day: day || 1}
  end

  # ── values as the parser makes them ────────────────────────────────────

  # A regex's unmatched trailing groups are left out of its captures, and an
  # unmatched group within them is "".
  defp padded(captures, count) do
    captures ++ List.duplicate("", count - length(captures))
  end

  defp numbers(captures, count) do
    captures
    |> padded(count)
    |> Enum.map(&number/1)
  end

  defp number("") do
    nil
  end

  defp number(digits) do
    String.to_integer(digits)
  end

  defp nonzero(0) do
    nil
  end

  defp nonzero(n) do
    n
  end

  defp blank("") do
    nil
  end

  defp blank(text) do
    text
  end

  defp non_empty([]) do
    nil
  end

  defp non_empty(list) do
    list
  end

  # A weekday is lower-cased where it is written capitalised, as the parser
  # does; `day` and an already lower-case name are kept as written.
  defp weekday_name(weekday) when weekday in @capitalised_weekdays do
    String.downcase(weekday)
  end

  defp weekday_name(weekday) do
    weekday
  end

  defp weekday_list(text) do
    text
    |> String.split(~r/,\s?/)
    |> Enum.map(&weekday_name/1)
  end

  # The parser's `undefined`: a field with no value is left out.
  defp compact(token) do
    token
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
