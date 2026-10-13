defmodule Tempo.Grammar.Generator do
  @moduledoc """
  Texts generated from the grammar of `guides/iso8601-grammar.md`, one
  generator per production family, for the property tests of section 7 of
  that guide.

  Every text a generator produces is well formed by its production and holds
  values the validator accepts, so `Tempo.from_iso8601/2` must read it and
  `Tempo.to_iso8601/1` must write a text that reads to the same value.
  `texts/2` draws a number of texts from a seed, so a failing text can be
  drawn again.

  """

  @zones ["Europe/Paris", "America/New_York", "Asia/Tokyo", "Australia/Sydney", "UTC"]

  @productions [
    :date_basic,
    :date_extended,
    :year_month,
    :year_only,
    :decade,
    :century,
    :ordinal_date,
    :week_date,
    :week_only,
    :time_basic,
    :time_extended,
    :time_fraction,
    :datetime_basic,
    :datetime_extended,
    :datetime_shift,
    :duration,
    :duration_fraction,
    :interval_start_end,
    :interval_start_duration,
    :interval_duration_end,
    :interval_abbreviated_end,
    :interval_open,
    :recurrence,
    :explicit_date,
    :explicit_datetime,
    :explicit_shift,
    :qualified,
    :masked,
    :year_prefixed,
    :year_annotated,
    :season,
    :group,
    :set_in_unit,
    :set_of_values,
    :selection,
    :repeat_rule,
    :suffixed
  ]

  @doc "The production families a text is drawn from."
  @spec productions() :: [atom(), ...]
  def productions, do: @productions

  @doc """
  Draws texts from every production.

  ### Arguments

  * `count` is the number of texts per production.

  * `seed` is the seed of the random draw, so a run can be repeated.

  ### Returns

  * A list of `{production, text}`.

  """
  @spec texts(pos_integer(), integer()) :: [{atom(), String.t()}]
  def texts(count, seed) do
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    for production <- @productions, _ <- 1..count, do: {production, text(production)}
  end

  @doc "One text of a production."
  @spec text(atom()) :: String.t()
  def text(:date_basic), do: "#{year()}#{two(month())}#{two(day())}"
  def text(:date_extended), do: "#{year()}-#{two(month())}-#{two(day())}"
  def text(:year_month), do: "#{year()}-#{two(month())}"
  def text(:year_only), do: year()
  def text(:decade), do: "#{pad(pick(0..999), 3)}"
  def text(:century), do: "#{pad(pick(0..99), 2)}"
  def text(:ordinal_date), do: "#{year()}#{sep()}#{pad(pick(1..365), 3)}"
  # One format throughout: `1985W155` or `1985-W15-5` (ISO 8601-1 §5.2.4.1).
  def text(:week_date) do
    case sep() do
      "" -> "#{year()}W#{two(pick(1..52))}#{pick(1..7)}"
      "-" -> "#{year()}-W#{two(pick(1..52))}-#{pick(1..7)}"
    end
  end

  def text(:week_only), do: "#{year()}#{sep()}W#{two(pick(1..52))}"

  def text(:time_basic),
    do: "T" <> Enum.join(Enum.take([two(hour()), two(minute()), two(second())], pick(1..3)))

  def text(:time_extended),
    do:
      maybe("T") <>
        Enum.join(Enum.take([two(hour()), two(minute()), two(second())], pick(2..3)), ":")

  def text(:time_fraction) do
    case pick(1..3) do
      1 -> "T#{two(hour())}#{fraction()}"
      2 -> "T#{two(hour())}:#{two(minute())}#{fraction()}"
      3 -> "T#{two(hour())}:#{two(minute())}:#{two(second())}#{fraction()}"
    end
  end

  def text(:datetime_basic), do: text(:date_basic) <> text(:time_basic)

  def text(:datetime_extended),
    do: text(:date_extended) <> "T" <> String.trim_leading(text(:time_extended), "T")

  def text(:datetime_shift), do: text(:datetime_extended) <> shift()

  def text(:duration) do
    date = Enum.filter([{"Y", 0..5}, {"M", 0..11}, {"D", 0..30}], fn _ -> pick(0..1) == 1 end)
    clock = Enum.filter([{"H", 0..23}, {"M", 0..59}, {"S", 0..59}], fn _ -> pick(0..1) == 1 end)

    units = fn parts ->
      Enum.map_join(parts, fn {designator, range} -> "#{pick(range)}#{designator}" end)
    end

    case {date, clock} do
      {[], []} -> "P#{pick(1..10)}D"
      {date, []} -> "P" <> units.(date)
      {date, clock} -> "P" <> units.(date) <> "T" <> units.(clock)
    end
  end

  def text(:duration_fraction), do: "PT#{pick(0..23)}H#{pick(0..59)}M#{pick(0..59)}#{fraction()}S"

  def text(:interval_start_end) do
    year = pick(1900..2100)
    month = month()
    day = day()
    "#{year}-#{two(month)}-#{two(day)}/#{year + pick(0..2)}-#{two(pick(month..12))}-#{two(day)}"
  end

  def text(:interval_start_duration), do: text(:date_extended) <> "/" <> length_of_a_span()
  def text(:interval_duration_end), do: length_of_a_span() <> "/" <> text(:date_extended)

  def text(:interval_abbreviated_end) do
    year = year()
    month = month()
    day = pick(1..14)
    "#{year}-#{two(month)}-#{two(day)}/#{two(day + pick(1..14))}"
  end

  def text(:interval_open) do
    case pick(1..2) do
      1 -> text(:date_extended) <> "/.."
      2 -> "../" <> text(:date_extended)
    end
  end

  def text(:recurrence), do: "R#{pick(["", pick(1..12)])}/" <> text(:interval_start_duration)

  def text(:explicit_date) do
    case pick(1..4) do
      1 -> "#{year()}Y#{month()}M#{day()}D"
      2 -> "#{year()}Y#{month()}M"
      3 -> "#{year()}Y#{pick(1..52)}W#{pick(1..7)}K"
      4 -> "#{year()}Y#{pick(1..365)}O"
    end
  end

  def text(:explicit_datetime),
    do: "#{year()}Y#{month()}M#{day()}DT#{hour()}H#{minute()}M#{second()}S"

  def text(:explicit_shift) do
    case pick(1..3) do
      1 -> text(:explicit_datetime) <> "Z"
      2 -> text(:explicit_datetime) <> "Z#{pick(1..12)}H"
      3 -> text(:explicit_datetime) <> "Z-#{pick(1..12)}H#{pick([0, 30])}M"
    end
  end

  def text(:qualified) do
    mark = pick(["?", "~", "%"])

    case pick(1..4) do
      1 -> text(:date_extended) <> mark
      2 -> "#{year()}-#{two(month())}#{mark}-#{two(day())}"
      3 -> "#{year()}-#{mark}#{two(month())}-#{two(day())}"
      4 -> "#{year()}Y#{month()}#{mark}M#{day()}D"
    end
  end

  def text(:masked) do
    case pick(1..4) do
      1 -> "#{String.slice(year(), 0, 3)}X"
      2 -> "#{year()}-XX"
      3 -> "#{year()}-#{two(month())}-XX"
      4 -> "#{year()}Y#{month()}MX*D"
    end
  end

  def text(:year_prefixed), do: "Y#{pick(["", "-"])}#{pick(10_000..9_999_999)}"

  def text(:year_annotated) do
    case pick(1..3) do
      1 -> "#{year()}S#{pick(1..3)}"
      2 -> "#{pick(1..99)}E#{pick(2..6)}Y"
      3 -> "#{year()}S#{pick(1..3)}Y"
    end
  end

  def text(:season), do: "#{year()}-#{pick(21..24)}"

  def text(:group) do
    case pick(1..3) do
      1 -> "#{year()}Y#{pick(1..4)}G3MU"
      2 -> "#{year()}Y#{month()}M#{pick(1..3)}G10DU"
      3 -> "#{year()}Y#{month()}M#{day()}DT#{pick(1..4)}GT6HU"
    end
  end

  def text(:set_in_unit) do
    members =
      Enum.map_join(
        Enum.uniq([month(), month(), month()]) |> Enum.sort(),
        ",",
        &Integer.to_string/1
      )

    case pick(1..3) do
      1 -> "#{year()}Y{#{members}}M"
      2 -> "#{year()}Y#{month()}M{1,#{pick(2..10)}..#{pick(11..28)}}D"
      3 -> "{#{members}}M#{day()}D"
    end
  end

  def text(:set_of_values) do
    years = Enum.sort(Enum.uniq([year(), year(), year()]))

    case pick(1..3) do
      1 -> "{" <> Enum.join(years, ",") <> "}"
      2 -> "[" <> Enum.join(years, ",") <> "]"
      3 -> "{" <> text(:year_month) <> "," <> text(:date_extended) <> "}"
    end
  end

  def text(:selection) do
    case pick(1..4) do
      1 -> "#{year()}Y#{month()}ML#{pick(1..7)}K#{pick(1..4)}IN"
      2 -> "#{year()}YL#{month()}M#{day()}DN"
      3 -> "#{year()}Y#{month()}ML-1DN"
      4 -> "#{year()}Y#{month()}ML#{pick(1..7)}K-1IN"
    end
  end

  def text(:repeat_rule) do
    case pick(1..3) do
      1 -> "R/#{year()}-01-01/P1Y/FL#{month()}M#{day()}DN"
      2 -> "R#{pick(1..10)}/#{year()}-#{two(month())}-01/P1M/FL#{pick(1..7)}K#{pick(1..4)}IN"
      3 -> "R/#{year()}-01-01/P1Y/F1YL#{month()}M#{day()}DN"
    end
  end

  def text(:suffixed) do
    case pick(1..4) do
      1 -> text(:datetime_extended) <> "[#{pick(@zones)}]"
      2 -> text(:date_extended) <> "[u-ca=hebrew]"
      3 -> text(:datetime_shift) <> "[#{pick(@zones)}][u-ca=hebrew]"
      4 -> text(:interval_start_end) <> "[#{pick(@zones)}]"
    end
  end

  # ── Components ────────────────────────────────────────────────────────

  defp year, do: pick(1600..2400) |> Integer.to_string()
  defp month, do: pick(1..12)
  # A day every month of every calendar generated here has.
  defp day, do: pick(1..28)
  # A duration that is an end of an interval is of some length: `P0D` is a
  # duration, and an interval of no length is none (law 2).
  defp length_of_a_span do
    duration = text(:duration)
    if Regex.match?(~r/[1-9]/, duration), do: duration, else: "P1D"
  end

  defp hour, do: pick(0..23)
  defp minute, do: pick(0..59)
  defp second, do: pick(0..59)
  defp fraction, do: pick([".", ","]) <> Integer.to_string(pick(1..999_999))

  defp shift do
    case pick(1..4) do
      1 -> "Z"
      2 -> "#{pick(["+", "-"])}#{two(pick(0..12))}:#{pick(["00", "30"])}"
      3 -> "#{pick(["+", "-"])}#{two(pick(0..12))}#{pick(["00", "30"])}"
      4 -> "#{pick(["+", "-"])}#{two(pick(1..12))}"
    end
  end

  defp sep, do: pick(["", "-"])
  defp maybe(text), do: pick(["", text])
  defp two(n), do: pad(n, 2)
  defp pad(n, width), do: n |> Integer.to_string() |> String.pad_leading(width, "0")
  defp pick(%Range{} = range), do: Enum.random(range)
  defp pick(list) when is_list(list), do: Enum.random(list)
end
