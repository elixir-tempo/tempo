defmodule Tempo.GeneratedSets do
  @moduledoc false

  # Texts of sets and ranges, generated from members whose reading alone is
  # known, for `Tempo.Iso8601.GeneratedSetsTest`: the pilot of
  # `plans/parser-formal-grammar.md`, scoped to ISO 8601-2 clause 6.
  #
  # A text is built from the texts of its members, so what it should read as
  # is known without reading it: a set of whole values is its members, each
  # as its text is read alone, and a set in one unit of a value is the values
  # with each member written in that unit. Nothing here reads a set to say
  # what a set is.
  #
  # Each text says what it is built to be: read, or refused. The refusals are
  # the forms Tempo does not read, each for a reason given where it is
  # generated, so a form that starts or stops being read is noticed.
  #
  # Not generated, since no reading alone says what they are:
  #
  # * one of several values in a unit of the extended or the basic format
  #   (`2026-[01,03]`), where a bracket is a set of whole values or the suffix
  #   of RFC 9557, so only the explicit format writes it (`2026Y[1,3]M`);
  #
  # * a time shift after a set (`{…}Z`), which each member takes for itself.

  alias Tempo.GeneratedSets.Check

  ## Members

  # Each family of members: three texts in ascending order, of one form and
  # one resolution, so that a range from one to a later one is a range.
  @families [
    year: ["1985", "2026", "2027"],
    year_explicit: ["1985Y", "2026Y", "2027Y"],
    year_before: ["-0044", "-0043", "-0001"],
    year_long: ["Y12026", "Y12027", "Y12030"],
    year_month: ["2026-06", "2026-07", "2026-11"],
    year_month_explicit: ["2026Y6M", "2026Y7M", "2026Y11M"],
    date: ["2026-06-15", "2026-06-16", "2026-07-01"],
    date_basic: ["20260615", "20260616", "20260701"],
    date_explicit: ["2026Y6M15D", "2026Y6M16D", "2026Y7M1D"],
    ordinal: ["2026-166", "2026-167", "2026-200"],
    ordinal_basic: ["2026166", "2026167", "2026200"],
    ordinal_explicit: ["2026Y166O", "2026Y167O", "2026Y200O"],
    week: ["2026-W25", "2026-W26", "2026-W30"],
    week_basic: ["2026W25", "2026W26", "2026W30"],
    week_explicit: ["2026Y25W", "2026Y26W", "2026Y30W"],
    week_date: ["2026-W25-3", "2026-W25-4", "2026-W26-1"],
    week_date_basic: ["2026W253", "2026W254", "2026W261"],
    week_date_explicit: ["2026Y25W3K", "2026Y25W4K", "2026Y26W1K"],
    century: ["19", "20", "21"],
    century_explicit: ["19C", "20C", "21C"],
    decade: ["198", "199", "202"],
    decade_explicit: ["198J", "199J", "202J"],
    season: ["2026-21", "2026-22", "2026-24"],
    quarter: ["2026-33", "2026-34", "2026-36"],
    time_hour: ["T10", "T11", "T15"],
    time_minute: ["T10:30", "T10:45", "T11:00"],
    time_second: ["T10:30:15", "T10:30:45", "T11:00:00"],
    time_basic: ["T1030", "T1045", "T1100"],
    time_basic_second: ["T103015", "T103045", "T110000"],
    time_explicit: ["T10H", "T11H", "T15H"],
    time_explicit_minute: ["T10H30M", "T10H45M", "T11H0M"],
    time_fraction: ["T10:30:15.5", "T10:30:45.5", "T11:00:00.5"],
    time_z: ["T10:30Z", "T10:45Z", "T11:00Z"],
    time_shift: ["T10:30+01:00", "T10:45+01:00", "T11:00+01:00"],
    hour_fraction: ["T10.5", "T11.5", "T15.5"],
    datetime: ["2026-06-15T10:30", "2026-06-15T11:00", "2026-06-16T09:00"],
    datetime_basic: ["20260615T1030", "20260615T1100", "20260616T0900"],
    datetime_explicit: ["2026Y6M15DT10H30M", "2026Y6M15DT11H0M", "2026Y6M16DT9H0M"],
    datetime_z: ["2026-06-15T10:30:00Z", "2026-06-15T11:00:00Z", "2026-06-16T09:00:00Z"],
    datetime_shift: ["2026-06-15T10:30+01:00", "2026-06-15T11:00+01:00", "2026-06-16T09:00+01:00"],
    datetime_fraction: [
      "2026-06-15T10:30:15.5",
      "2026-06-15T10:30:45.5",
      "2026-06-16T09:00:00.5"
    ],
    datetime_zone: [
      "2026-06-15T10:30[Europe/Paris]",
      "2026-06-15T11:00[Europe/Paris]",
      "2026-06-16T09:00[Europe/Paris]"
    ],
    date_zone: [
      "2026-06-15[Europe/Paris]",
      "2026-06-16[Europe/Paris]",
      "2026-07-01[Europe/Paris]"
    ],
    month_day: ["06-15", "06-16", "07-01"],
    month_day_explicit: ["6M15D", "6M16D", "7M1D"],
    qualified_year: ["1985?", "2026~", "2027%"],
    qualified_month: ["2026-06?", "2026-07~", "2026-11%"],
    qualified_date: ["2026-06-15?", "2026-06-16~", "2026-07-01%"],
    qualified_before: ["?2026-06", "~2026-07", "%2026-11"],
    qualified_component: ["2026-?06-15", "2026-~07-01", "2026-%11-01"],
    qualified_group: ["2026?-06-15", "2026~-07-01", "2026%-11-01"],
    unspecified_year: ["198X", "199X", "202X"],
    unspecified_month: ["2026-XX", "2027-XX", "2028-XX"],
    unspecified_day: ["2026-06-XX", "2026-07-XX", "2026-11-XX"],
    unspecified_all: ["XXXX-06", "XXXX-07", "XXXX-11"],
    unspecified_any: ["2026YX*M", "2027YX*M", "2028YX*M"],
    significant: ["1950S2", "1960S2", "1970S2"],
    exponent: ["Y1E3", "Y2E3", "Y3E3"],
    margin: ["1950±2", "1960±2", "1970±2"],
    group: ["2026Y1G3MU", "2026Y2G3MU", "2026Y4G3MU"],
    selection: ["2026YL1KN", "2026YL2KN", "2026YL5KN"],
    interval: ["2026-01/2026-03", "2026-05/2026-07", "2026-09/2026-11"]
  ]

  @braces [{"{", "}"}, {"[", "]"}]

  @doc false
  # Every generated text, as `%{text:, family:, expect:, …}`.
  @spec texts() :: [map()]
  def texts,
    do:
      value_sets() ++
        zoned_sets() ++ mixed_sets() ++ unit_sets() ++ composed_sets() ++ nested_sets()

  @doc false
  # What each text is found to break, as `{property, text, detail}`: none
  # where the parser holds to all of them.
  @spec findings([map()]) :: [{atom(), String.t(), term()}]
  defdelegate findings(texts), to: Check

  ## Sets of whole values

  defp value_sets do
    for {family, [first, second, third]} <- @families,
        {open, close} <- @braces,
        entries <- shapes(first, second, third) do
      entries
      |> as_they_are_read(family)
      |> generated(open <> Enum.map_join(entries, ",", &entry_text/1) <> close, family)
    end
  end

  # The shapes a set of three members takes: members, ranges between two of
  # them, ranges open at one end, and those beside a member.
  defp shapes(first, second, third) do
    [
      [{:member, first}, {:member, second}],
      [{:member, first}, {:member, second}, {:member, third}],
      [{:member, second}, {:member, first}],
      [{:member, first}],
      [{:range, first, second}],
      [{:range, first, third}],
      [{:member, first}, {:range, second, third}],
      [{:range, first, second}, {:member, third}],
      [{:to, second}],
      [{:from, first}],
      [{:to, first}, {:member, third}],
      [{:member, first}, {:from, third}]
    ]
  end

  defp entry_text({:member, text}), do: text
  defp entry_text({:range, first, last}), do: first <> ".." <> last
  defp entry_text({:to, last}), do: ".." <> last
  defp entry_text({:from, first}), do: first <> ".."

  defp generated({:refused, error}, text, family),
    do: %{text: text, family: family, expect: {:refused, error}}

  defp generated({:read, entries}, text, family),
    do: %{text: text, family: family, expect: :read, entries: entries}

  # What a set's entries are read as. A range of intervals is refused: a
  # range runs from one date or time to another. A range from one division
  # of a year to another is each division between them where they are a run
  # in time, and refused where they are none or the range is open at an end.
  defp as_they_are_read(entries, :interval) do
    if Enum.all?(entries, &match?({:member, _text}, &1)),
      do: {:read, entries},
      else: {:refused, Tempo.ParseError}
  end

  defp as_they_are_read(entries, family) when family in [:season, :quarter] do
    entries
    |> Enum.map(&divisions/1)
    |> Enum.reduce_while({:read, []}, fn
      :no_run, _read -> {:halt, {:refused, Tempo.InvalidDateError}}
      members, {:read, read} -> {:cont, {:read, read ++ members}}
    end)
  end

  defp as_they_are_read(entries, _family), do: {:read, entries}

  defp divisions({:member, text}), do: [{:member, text}]

  defp divisions({:range, first, last}) do
    codes = division(first)..division(last)

    if run_in_time?(codes),
      do: for(code <- codes, do: {:member, "2026-#{code}"}),
      else: :no_run
  end

  defp divisions(_open_at_an_end), do: :no_run

  defp division("2026-" <> code), do: String.to_integer(code)

  # The seasons of a year numbered 21 to 23 run on from one another, and the
  # winter numbered 24 begins the December before them. Quarters are a run.
  defp run_in_time?(_first..last//_) when last in 21..23, do: true
  defp run_in_time?(_first..last//_) when last == 24, do: false
  defp run_in_time?(_quarters), do: true

  # A set of whole values with a zone after it, which each member takes.
  defp zoned_sets do
    for family <- [:date, :datetime, :date_explicit, :datetime_explicit],
        [first, second | _third] = @families[family],
        {open, close} <- @braces do
      zone = "[Europe/Paris]"

      %{
        text: open <> first <> "," <> second <> close <> zone,
        family: {:zoned, family},
        expect: :read,
        entries: [{:member, first <> zone}, {:member, second <> zone}]
      }
    end
  end

  # A set of two families: its members may be of different precisions
  # (ISO 8601-2 §6.1).
  @mixed [
    {:year, :date},
    {:year, :year_month},
    {:year_month, :date},
    {:date, :datetime},
    {:date, :week_date},
    {:date, :ordinal},
    {:date, :date_explicit},
    {:date, :date_basic},
    {:year, :year_explicit},
    {:year, :century},
    {:year, :decade},
    {:century, :decade},
    {:time_hour, :time_minute},
    {:date, :time_hour},
    {:year, :qualified_year},
    {:year, :unspecified_year},
    {:year_month, :season},
    {:date, :interval},
    {:date, :date_zone},
    {:datetime_z, :datetime_zone}
  ]

  defp mixed_sets do
    for {one, other} <- @mixed,
        {open, close} <- @braces,
        [first | _rest] = @families[one],
        [second | _others] = @families[other],
        members <- [[first, second], [second, first]] do
      %{
        text: open <> Enum.join(members, ",") <> close,
        family: {one, other},
        expect: :read,
        entries: Enum.map(members, &{:member, &1})
      }
    end
  end

  ## Sets in one unit of a value

  # A set in one unit: what is written before it and after it, and three of
  # the unit's values as they are written there, in ascending order.
  @templates [
    # The explicit format.
    {:explicit_month, "2026Y", "M", ~w(1 3 6)},
    {:explicit_month_day, "2026Y", "M15D", ~w(1 3 6)},
    {:explicit_day, "2026Y6M", "D", ~w(1 15 28)},
    {:explicit_year, "", "Y", ~w(2025 2026 2028)},
    {:explicit_year_month, "", "Y6M", ~w(2025 2026 2028)},
    {:explicit_week, "2026Y", "W", ~w(1 25 52)},
    {:explicit_weekday, "2026Y25W", "K", ~w(1 3 7)},
    {:explicit_ordinal, "2026Y", "O", ~w(1 166 365)},
    {:explicit_hour, "T", "H", ~w(0 9 14)},
    {:explicit_minute, "T10H", "M", ~w(0 30 45)},
    {:explicit_second, "T10H30M", "S", ~w(0 15 45)},
    {:explicit_date_hour, "2026Y6M15DT", "H", ~w(0 9 14)},
    {:explicit_day_hour, "2026Y6M", "DT10H", ~w(1 15 28)},
    # The extended format.
    {:extended_month, "2026-", "", ~w(01 03 06)},
    {:extended_month_day, "2026-", "-15", ~w(01 03 06)},
    {:extended_day, "2026-06-", "", ~w(01 15 28)},
    {:extended_year, "", "-06-15", ~w(2025 2026 2028)},
    {:extended_year_month, "", "-06", ~w(2025 2026 2028)},
    {:extended_week, "2026-W", "", ~w(01 25 52)},
    {:extended_weekday, "2026-W25-", "", ~w(1 3 7)},
    {:extended_ordinal, "2026-", "", ~w(001 166 365)},
    {:extended_hour, "T", "", ~w(00 09 14)},
    {:extended_hour_minute, "T", ":30", ~w(00 09 14)},
    {:extended_minute, "T10:", "", ~w(00 30 45)},
    {:extended_second, "T10:30:", "", ~w(00 15 45)},
    {:extended_date_hour, "2026-06-15T", "", ~w(00 09 14)},
    {:extended_date_hour_minute, "2026-06-15T", ":30", ~w(00 09 14)},
    {:extended_day_time, "2026-06-", "T10:30", ~w(01 15 28)},
    # The basic format.
    {:basic_month_day, "2026", "15", ~w(01 03 06)},
    {:basic_day, "202606", "", ~w(01 15 28)},
    {:basic_year, "", "0615", ~w(2025 2026 2028)},
    {:basic_week, "2026W", "", ~w(01 25 52)},
    {:basic_weekday, "2026W25", "", ~w(1 3 7)},
    {:basic_ordinal, "2026", "", ~w(001 166 365)},
    {:basic_hour_minute, "T", "30", ~w(00 09 14)},
    {:basic_minute, "T10", "", ~w(00 30 45)},
    {:basic_second, "T1030", "", ~w(00 15 45)},
    {:basic_date_hour, "20260615T", "30", ~w(00 09 14)}
  ]

  # The basic format's sets that are not read yet (`TODO.md`, "The basic
  # format with unspecified digits or a set in a time alone and in a week
  # date"). Each is held to being refused, so that reading one is noticed.
  @not_read_yet [:basic_week, :basic_minute]

  defp unit_sets do
    for {family, before, after_it, [first, second, third]} <- @templates,
        {open, close, type} <- brackets(family),
        {slot, values} <- slots(first, second, third) do
      text = before <> open <> slot <> close <> after_it
      unit_set(text, family, type, Enum.map(values, &(before <> &1 <> after_it)))
    end
  end

  defp unit_set(text, family, _type, _members) when family in @not_read_yet,
    do: %{text: text, family: family, expect: {:refused, Tempo.ParseError}}

  defp unit_set(text, family, type, members),
    do: %{text: text, family: family, expect: :read, type: type, members: members}

  # One of several values in a unit is written with a designator after it.
  defp brackets(family) do
    if String.starts_with?(Atom.to_string(family), "explicit"),
      do: [{"{", "}", :all}, {"[", "]", :one}],
      else: [{"{", "}", :all}]
  end

  # What is written in the braces, and the values it names. A range is each
  # whole number between its ends, written to the width of its first.
  defp slots(first, second, third) do
    [
      {first <> "," <> second, [first, second]},
      {first <> "," <> second <> "," <> third, [first, second, third]},
      {second <> "," <> first, [first, second]},
      {first, [first]},
      {first <> ".." <> second, between(first, second)},
      {first <> "," <> second <> ".." <> third, [first | between(second, third)]}
    ]
  end

  defp between(first, last) do
    width = String.length(first)
    padded? = String.starts_with?(first, "0")

    for value <- String.to_integer(first)..String.to_integer(last) do
      text = Integer.to_string(value)
      if padded?, do: String.pad_leading(text, width, "0"), else: text
    end
  end

  # A set with a step or a count from the end, two sets in one value, a set
  # in a value with a zone, a qualifier, a fraction, a group or a selection:
  # each written out with the values it names.
  @composed [
    {:step, "2026Y{1..9//2}M", ~w(2026Y1M 2026Y3M 2026Y5M 2026Y7M 2026Y9M)},
    {:step, "2026Y{1..10//3}M", ~w(2026Y1M 2026Y4M 2026Y7M 2026Y10M)},
    {:step, "2026Y6M{1..30//10}D", ~w(2026Y6M1D 2026Y6M11D 2026Y6M21D)},
    {:step, "T{0..23//6}H", ~w(T0H T6H T12H T18H)},
    {:step, "{2020..2030//5}Y", ~w(2020Y 2025Y 2030Y)},
    {:step, "2026-{01..09//2}", ~w(2026-01 2026-03 2026-05 2026-07 2026-09)},
    {:from_the_end, "2026Y{10..-1}M", ~w(2026Y10M 2026Y11M 2026Y12M)},
    {:from_the_end, "2026Y{-2,-1}M", ~w(2026Y11M 2026Y12M)},
    {:from_the_end, "2026Y6M{28..-1}D", ~w(2026Y6M28D 2026Y6M29D 2026Y6M30D)},
    {:from_the_end, "2026Y2M{-2..-1}D", ~w(2026Y2M27D 2026Y2M28D)},
    {:from_the_end, "2028Y2M{-2..-1}D", ~w(2028Y2M28D 2028Y2M29D)},
    {:from_the_end, "T{22..-1}H", ~w(T22H T23H)},
    {:from_the_end, "2026Y{52..-1}W", ~w(2026Y52W 2026Y53W)},
    {:from_the_end, "2026Y25W{6..-1}K", ~w(2026Y25W6K 2026Y25W7K)},
    {:from_the_end, "2026Y{364..-1}O", ~w(2026Y364O 2026Y365O)},
    {:from_the_end, "2026-06-{28..-1}", ~w(2026-06-28 2026-06-29 2026-06-30)},
    {:two_sets, "2026Y{1,3}M{1,15}D", ~w(2026Y1M1D 2026Y1M15D 2026Y3M1D 2026Y3M15D)},
    {:two_sets, "{2025,2026}Y{6,7}M", ~w(2025Y6M 2025Y7M 2026Y6M 2026Y7M)},
    {:two_sets, "2026-{01,03}-{01,15}", ~w(2026-01-01 2026-01-15 2026-03-01 2026-03-15)},
    {:two_sets, "T{9,14}:{00,30}", ~w(T09:00 T09:30 T14:00 T14:30)},
    {:two_sets, "2026Y6M{1,15}DT{9,14}H",
     ~w(2026Y6M1DT9H 2026Y6M1DT14H 2026Y6M15DT9H 2026Y6M15DT14H)},
    {:zoned, "2026-06-{01,15}[Europe/Paris]",
     ["2026-06-01[Europe/Paris]", "2026-06-15[Europe/Paris]"]},
    {:zoned, "2026Y6M15DT{9,14}H[Europe/Paris]",
     ["2026Y6M15DT9H[Europe/Paris]", "2026Y6M15DT14H[Europe/Paris]"]},
    {:zoned, "2026-06-15T{09,14}:30Z", ["2026-06-15T09:30Z", "2026-06-15T14:30Z"]},
    {:zoned, "2026-06-15T{09,14}:30+01:00", ["2026-06-15T09:30+01:00", "2026-06-15T14:30+01:00"]},
    {:qualified, "2026Y{1,3}M?", ["2026Y1M?", "2026Y3M?"]},
    {:qualified, "2026-{01,03}~", ["2026-01~", "2026-03~"]},
    {:qualified, "2026-06-{01,15}%", ["2026-06-01%", "2026-06-15%"]},
    {:qualified, "?2026-{01,03}", ["?2026-01", "?2026-03"]},
    {:fraction, "T10:30:{15,45}.5", ["T10:30:15.5", "T10:30:45.5"]},
    {:group, "2018-{1,3,5}G2MU", ["2018-1G2MU", "2018-3G2MU", "2018-5G2MU"]},
    {:group, "2018Y{1,3}G3MU", ["2018Y1G3MU", "2018Y3G3MU"]},
    {:selection, "2026YL{1,5}KN", ["2026YL1KN", "2026YL5KN"]},
    {:selection, "2026Y6ML{1,15}DN", ["2026Y6ML1DN", "2026Y6ML15DN"]},
    {:year_before, "{-0044,-0043}Y", ["-0044Y", "-0043Y"]},
    {:year_long, "{12026,12027}Y", ["12026Y", "12027Y"]}
  ]

  # A set in a unit below the year holds whole numbers: one that holds a
  # value with unspecified digits is refused, and says how it is written.
  @unspecified_in_a_unit ["2026-{0X,1X}", "2026Y{0X,1X}M", "2026Y6M{1X,2X}D", "T{0X,1X}H"]

  defp composed_sets do
    read =
      for {family, text, members} <- @composed do
        %{text: text, family: family, expect: :read, type: :all, members: members}
      end

    refused =
      for text <- @unspecified_in_a_unit do
        %{text: text, family: :unspecified_in_a_unit, expect: {:refused, Tempo.InvalidDateError}}
      end

    read ++ refused
  end

  ## Sets in sets

  # A member that holds a set in one of its units, and a set of years, which
  # is one value, are members as any value is. A set of whole values is no
  # member of a set.
  @nested [
    {"{2026Y{1,3}M,2027Y}", ["2026Y{1,3}M", "2027Y"]},
    {"[2026-{01,03},2027]", ["2026-{01,03}", "2027"]},
    {"{2026-06-{01,15},2026-07-01}", ["2026-06-{01,15}", "2026-07-01"]},
    {"{T{9,14}H,T16H}", ["T{9,14}H", "T16H"]},
    {"{{2026,2027},2030}", ["{2026,2027}", "2030"]}
  ]

  @set_in_a_set ["{[2026-06,2026-07],2026-09}", "[{2026-06,2026-07},2026-09]"]

  # A set with a member left out of it is held to reading back alone.
  @with_a_member_left_out ["{2020..2030,^2026}", "{2026-06-01..2026-06-30,^2026-06-15}"]

  defp nested_sets do
    read =
      for {text, members} <- @nested do
        %{text: text, family: :nested, expect: :read, entries: Enum.map(members, &{:member, &1})}
      end

    refused =
      for text <- @set_in_a_set do
        %{text: text, family: :set_in_a_set, expect: {:refused, Tempo.ParseError}}
      end

    left_out =
      for text <- @with_a_member_left_out do
        %{text: text, family: :left_out, expect: :read}
      end

    read ++ refused ++ left_out
  end
end
