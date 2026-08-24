defmodule Tempo.Iso8601.Tokenizer.Grammar do
  @moduledoc false
  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Numbers
  import Tempo.Iso8601.Tokenizer.Helpers
  import Tempo.Iso8601.Tokenizer.Extended, only: [extended_suffix: 0]

  # NOTES

  # Doesn't not correctly parse negative centuries and decades
  # since elixir does not support the idea of -0.
  # See ISO8601 4.4.1.7 and 4.4.1.8

  def iso8601_tokenizer do
    optional(qualification())
    |> choice([
      interval_or_time_or_duration(),
      parsec({Tempo.Iso8601.Tokenizer, :set})
    ])
    |> optional(qualification())
    |> optional(extended_suffix())
    |> label("ISO8601 interval, duration, date, time or datetime")
  end

  def interval_or_time_or_duration(combinator \\ empty()) do
    combinator
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}),
      parsec({Tempo.Iso8601.Tokenizer, :datetime_or_date_or_time})
    ])
  end

  # Date Time

  def implicit_date_time do
    parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_date_p})
    |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_time_of_day_p}))
  end

  def extended_date_time do
    parsec({Tempo.Iso8601.Tokenizer.Date, :extended_date_p})
    |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :extended_time_of_day_p}))
  end

  def explicit_date_time do
    parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_date_p})
    |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_of_day_p}))
  end

  # Date

  def implicit_date do
    choice([
      implicit_week_date(),
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_month_p}))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_month_p})),
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_month_p}))
      |> lookahead_not(digit()),
      implicit_ordinal_date(),
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p}),
      implicit_decade(),
      implicit_century(),
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_month_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_month_p}))
    ])
    |> label("implicit date")
  end

  def extended_date do
    choice([
      extended_week_date(),

      # Year-Month-Day, with ISO 8601-2 §8 component-level
      # qualification at each hyphen boundary. A qualifier to the
      # right of a component is a *group* qualifier (it + coarser);
      # to the left, an *individual* qualifier (that one only). The
      # trailing qualifier after the day is left for the outer
      # `qualification/0` so it reads as *complete* (§8.2.1).
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> optional(right_qualifier(:year))
      |> ignore(dash())
      |> optional(left_qualifier(:month))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_month_p}))
      |> optional(right_qualifier(:month))
      |> ignore(dash())
      |> optional(left_qualifier(:day))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_month_p})),

      # Year-Month, with qualifiers. The trailing qualifier after the
      # month is the rightmost component, so it too is left for the
      # outer complete qualifier.
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> optional(right_qualifier(:year))
      |> ignore(dash())
      |> optional(left_qualifier(:month))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_month_p}))
      |> lookahead_not(digit()),

      # Month-Day (no year) with qualifiers.
      optional(left_qualifier(:month))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_month_p}))
      |> optional(right_qualifier(:month))
      |> ignore(dash())
      |> optional(left_qualifier(:day))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_month_p})),
      extended_ordinal_date()
    ])
    |> label("extended date")
  end

  def explicit_date do
    choice([
      # Year, month, day
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_century_decade_or_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_month_p}))
      |> concat(explicit_day_of_month()),

      # Year, week, day of week
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_century_decade_or_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_week_p}))
      |> concat(explicit_day_of_week()),

      # Year, month
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_century_decade_or_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_month_p})),

      # Year, day
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_century_decade_or_year_p})
      |> concat(explicit_day_of_month()),

      # Year, week
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_century_decade_or_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_week_p})),

      # Month, day of month
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_month_p})
      |> concat(explicit_day_of_month()),

      # Week, day of week
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_week_p})
      |> concat(explicit_day_of_week()),

      # Ordinal Date (year-day_of_year)
      explicit_ordinal_date(),

      # Year
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_century_decade_or_year_p}),

      # Month
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_month_p})
      |> lookahead_not(explicit_time_of_day()),

      # Can create ambiguity with implicit week dates so care is required
      # This should also cater for looking ahead for interval separators
      # and probably other tokens
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_week_p}) |> lookahead_not(digit()),
      explicit_day_of_year(),
      explicit_day_of_month(),
      explicit_day_of_week()
    ])
    |> label("explicit date")
  end

  def explicit_century_decade_or_year do
    choice([
      explicit_year(),
      explicit_century(),
      explicit_decade()
    ])
    |> label("century, decade or year")
  end

  # Ordinal date

  def implicit_ordinal_date do
    parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
    |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_year_p}))
  end

  def extended_ordinal_date do
    parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
    |> ignore(dash())
    |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_year_p}))
  end

  def explicit_ordinal_date do
    explicit_year()
    |> concat(explicit_day_of_year())
  end

  # Week date

  def implicit_week_date do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_week_p}))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_week_p})),
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_week_p})),
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_week_p})
    ])
  end

  def extended_week_date do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> ignore(dash())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_week_p}))
      |> ignore(dash())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_week_p})),
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> ignore(dash())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_week_p}))
    ])
  end

  def explicit_week_date do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_century_decade_or_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_week_p}))
      |> concat(explicit_day_of_week()),
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_century_decade_or_year_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_week_p})),
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_week_p})
      |> concat(explicit_day_of_week()),
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_week_p})
    ])
  end

  # Time

  def implicit_time_of_day do
    ignore(optional(string("T")))
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p}))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_second_p})),
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p})),
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
    ])
    |> optional(fraction())
  end

  def extended_time_of_day do
    ignore(optional(string("T")))
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> ignore(colon())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p}))
      |> ignore(colon())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_second_p})),
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> ignore(colon())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p})),
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> lookahead_not(digit())
    ])
    |> optional(fraction())
  end

  def explicit_time_of_day do
    ignore(optional(string("T")))
    |> choice([
      explicit_hour()
      |> optional(explicit_minute())
      |> optional(explicit_second()),
      explicit_minute()
      |> optional(explicit_second()),
      explicit_hour(),
      explicit_minute(),
      explicit_second()
    ])
  end

  # Durations

  def duration_elements(combinator \\ empty()) do
    combinator
    |> choice([
      concat(duration_date_elements(), duration_time_elements()),
      duration_date_elements(),
      duration_time_elements(),
      parsec({Tempo.Iso8601.Tokenizer, :datetime_or_date_or_time})
    ])
  end

  def duration_date_elements do
    times(duration_date_element(), min: 1)
  end

  def duration_time_elements(combinator \\ empty()) do
    combinator
    |> ignore(optional(string("T")))
    |> times(duration_time_element(), min: 1)
  end

  def duration_date_element do
    choice([
      maybe_negative_number(min: 1) |> ignore(string("C")) |> unwrap_and_tag(:century),
      maybe_negative_number(min: 1) |> ignore(string("J")) |> unwrap_and_tag(:decade),
      maybe_negative_number(min: 1) |> ignore(string("Y")) |> unwrap_and_tag(:year),
      maybe_negative_number(min: 1) |> ignore(string("M")) |> unwrap_and_tag(:month),
      maybe_negative_number(min: 1) |> ignore(string("W")) |> unwrap_and_tag(:week),
      maybe_negative_number(min: 1) |> ignore(string("D")) |> unwrap_and_tag(:day)
    ])
  end

  def duration_time_element do
    choice([
      maybe_negative_number(min: 1) |> ignore(string("H")) |> unwrap_and_tag(:hour),
      maybe_negative_number(min: 1) |> ignore(string("M")) |> unwrap_and_tag(:minute),
      # The sign, integer, and optional fraction of a duration second
      # reduce together, so `PT-0.2S` keeps its sign (a `-0` integer
      # second cannot carry it alone). The fraction is preserved with
      # its digit count — folding to a float would lose significant
      # trailing zeros (`PT1.250S` vs `PT1.25S`).
      optional(negative())
      |> positive_integer(min: 1)
      |> optional(fraction())
      |> reduce({Tempo.Iso8601.Tokenizer.Numbers, :form_duration_second, []})
      |> unwrap_and_tag(:second)
      |> ignore(string("S"))
    ])
  end

  # Selections

  def selection_elements(combinator \\ empty()) do
    combinator
    |> choice([
      concat(selection_date_elements(), selection_time_elements()),
      selection_date_elements(),
      selection_time_elements()
    ])
  end

  def selection_date_elements do
    times(selection_date_element(), min: 1)
  end

  def selection_time_elements do
    ignore(string("T"))
    |> times(selection_time_element(), min: 1)
  end

  def selection_date_element do
    choice([
      maybe_negative_integer_or_integer_set("Y", :year, min: 1),
      maybe_negative_integer_or_integer_set("M", :month, min: 1),
      maybe_negative_integer_or_integer_set("W", :week, min: 1),
      maybe_negative_integer_or_integer_set("O", :day_of_year, min: 1),
      maybe_negative_integer_or_integer_set("D", :day, min: 1),
      maybe_negative_integer_or_integer_set("K", :day_of_week, min: 1),
      # `V` (BYSETPOS) and `Q` (WKST) are Tempo project-specific designators —
      # RFC 5545 extensions with no ISO 8601 form. See `Tempo.Inspect`.
      maybe_negative_integer_or_integer_set("V", :set_position, min: 1),
      maybe_negative_integer_or_integer_set("Q", :wkst, min: 1),
      selection_instance(),
      ignore(string("L"))
      |> parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser})
      |> ignore(string("N"))
    ])
  end

  def selection_time_element do
    choice([
      maybe_negative_integer_or_integer_set("H", :hour, min: 1),
      maybe_negative_integer_or_integer_set("M", :minute, min: 1),
      maybe_negative_integer_or_integer_set("S", :second, min: 1),
      ignore(string("L"))
      |> parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser})
      |> ignore(string("N"))
    ])
  end

  def selection_instance do
    maybe_negative_integer_or_integer_set("I", :instance, min: 1)
  end

  # Individual date and time components
  # Note that any component can be alternatively a group
  # or set

  def implicit_year do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}) |> unwrap_and_tag(:year),

      # EDTF Level 2 long-year with exponent or significant-digit
      # annotation: `Y17E8` (17 × 10^8) or `Y171010000S3`. Requires
      # an `E` or `S` after the integer so that short-digit years
      # like `Y1` are not accepted as standalone.
      ignore(string("Y"))
      |> optional(negative())
      |> integer(min: 1)
      |> lookahead(choice([string("E"), string("S")]))
      |> optional(exponent())
      |> optional(significant())
      |> reduce({Tempo.Iso8601.Tokenizer.Numbers, :form_number, []})
      |> unwrap_and_tag(:year),

      # EDTF Level 2 long-year without annotation: `Y` followed by
      # a 5+ digit integer (`Y170000002`). Ordered before the
      # 4-digit branch so long years win.
      ignore(string("Y"))
      |> maybe_negative_number(min: 5)
      |> unwrap_and_tag(:year),

      # Short `Y`-prefix form (`Y2022`) — exactly 4 digits.
      ignore(string("Y")) |> maybe_negative_number(4) |> unwrap_and_tag(:year),

      # ISO 8601-2 expanded year: a *mandatory* sign (`+` or `-`)
      # followed by *five or more* digits (`+12022`, `-12022`,
      # `+002022`). The expanded form adds at least one digit beyond
      # the basic four, so a signed 4-digit value like `+2006` is not
      # expanded and is rejected (matching the EDTF corpus); a basic
      # negative year (`-0333`) is still handled by the 4-digit branch
      # below. The mandatory sign disambiguates the expanded form from
      # an unsigned basic-format date (`20220615`). Ordered before the
      # plain 4-digit branch so a long signed year wins.
      choice([negative(), positive()])
      |> positive_integer(min: 5)
      |> reduce(:form_number)
      |> unwrap_and_tag(:year),
      maybe_negative_integer(4) |> unwrap_and_tag(:year)
    ])
    |> label("implicit year")
  end

  def explicit_year do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      explicit_year_bc(),
      explicit_year_with_sign()
    ])
    |> label("explicit year")
  end

  # The year value is tagged here (rather than by the caller) so an
  # optional ISO 8601-2 §8.3 explicit qualifier can be emitted between
  # the value and the `Y` designator (`2018?Y`).
  def explicit_year_with_sign do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      maybe_negative_number(min: 1)
    ])
    |> unwrap_and_tag(:year)
    |> optional(left_qualifier(:year))
    |> ignore(string("Y"))
    |> label("explicit year with sign")
  end

  def explicit_year_bc do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      maybe_negative_number(min: 1)
    ])
    |> optional(left_qualifier(:year))
    |> ignore(string("Y"))
    |> optional(string("B"))
    |> post_traverse({__MODULE__, :build_bc_year, []})
    |> label("explicit year BC")
  end

  # Emit the BC-converted `{:year, _}` token plus, if present, the
  # `:individual_qualification` token from a §8.3 explicit qualifier
  # (`2004~YB`). `post_traverse` is needed (rather than `reduce`)
  # because two sibling tokens must be produced, not one.
  def build_bc_year(rest, acc, context, _line, _offset) do
    {qualifiers, value_tokens} =
      Enum.split_with(acc, &match?({:individual_qualification, _}, &1))

    year = value_tokens |> Enum.reverse() |> convert_bc()
    {rest, qualifiers ++ [{:year, year}], context}
  end

  # Months

  def implicit_month do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      positive_integer_or_integer_set(:month, 2),
      quarter(),
      half()
    ])
  end

  def explicit_month do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      qualified_number_or_integer_set("M", :month, min: 1),
      quarter(),
      half()
    ])
  end

  # Weeks

  def implicit_week do
    ignore(string("W"))
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      positive_integer_or_integer_set(:week, 2)
    ])
  end

  # Explicit month will consume the group
  # if there is one so this doesn't attempt
  # the impossible - no group can be here

  def explicit_week do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      maybe_negative_number_or_integer_set("W", :week, min: 1)
    ])
  end

  # Day of month

  def implicit_day_of_month do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      positive_integer_or_integer_set(:day, 2)
    ])
  end

  def explicit_day_of_month do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      qualified_number_or_integer_set("D", :day, min: 1)
    ])
  end

  # Day of week

  def implicit_day_of_week do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      positive_integer_or_integer_set(:day_of_week, 1)
    ])
  end

  def explicit_day_of_week do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      maybe_negative_number_or_integer_set("K", :day_of_week, 1)
    ])
  end

  # Day of year

  def implicit_day_of_year do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}) |> unwrap_and_tag(:day),
      positive_integer(3) |> unwrap_and_tag(:day)
    ])
  end

  def explicit_day_of_year do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      maybe_negative_number_or_integer_set("O", :day, min: 1)
    ])
  end

  # Decade and century, like week, cannot
  # ever encounter a group because the
  # Year combinator will consume it first since
  # Year has priority order over century and
  # decade

  def implicit_decade do
    maybe_negative_integer(3)
    |> unwrap_and_tag(:decade)
  end

  def explicit_decade do
    maybe_negative_number(min: 1)
    |> ignore(string("J"))
    |> unwrap_and_tag(:decade)
  end

  def implicit_century do
    maybe_negative_integer(2)
    |> lookahead_not(colon())
    |> unwrap_and_tag(:century)
  end

  def explicit_century do
    maybe_negative_number(min: 1)
    |> ignore(string("C"))
    |> unwrap_and_tag(:century)
  end

  # Time

  def implicit_hour do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group}),
      positive_number_or_integer_set(:hour, 2)
    ])
  end

  def explicit_hour do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      maybe_negative_number_or_integer_set("H", :hour, min: 1)
    ])
  end

  def implicit_minute do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group}),
      positive_number_or_integer_set(:minute, 2)
    ])
  end

  def explicit_minute do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      maybe_negative_number_or_integer_set("M", :minute, min: 1)
    ])
  end

  def implicit_second do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group}),
      implicit_second_or_integer_set(2)
    ])
  end

  def explicit_second do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      explicit_second_or_integer_set("S", min: 1)
    ])
  end

  # Time Shift

  def implicit_time_shift do
    shift_indicator()
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> ignore(optional(colon()))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p})),
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p}),
      lookahead_not(digit())
    ])
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  def extended_time_shift do
    shift_indicator()
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> ignore(optional(colon()))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p})),
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> lookahead_not(digit()),
      lookahead_not(digit())
    ])
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  # An explicit time shift must begin with the zulu indicator `Z`.
  # Permitting a bare signed + explicit-designator shift like `-1H`
  # or `-1M` would collide with the ISO 8601-2 "signed calendar
  # component" forms (§4.4.1), which a standalone `-1H` / `-1M`
  # more plausibly means as selectors.
  #
  # Signed shifts like `-05`, `-0530`, `-05:30` use `implicit_time_shift`
  # / `extended_time_shift` — those require a 2-digit implicit hour
  # and are unambiguous.
  #
  # Valid forms handled here:
  #
  #   * `Z`                 — UTC
  #   * `Z0H`, `Z0H0M`      — UTC with explicit-designator components
  #   * `Z+1H`, `Z-05H30M`  — UTC with signed explicit components
  def explicit_time_shift do
    zulu()
    |> optional(
      optional(sign())
      |> concat(explicit_hour())
      |> optional(explicit_minute())
      |> optional(explicit_second())
    )
    |> lookahead_not(digit())
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  # A sign is required if no Z indicator
  # A sign is optional if there is a Z indicator

  def shift_indicator do
    choice([
      ignore(zulu()) |> concat(sign()) |> lookahead(digit()),
      sign() |> lookahead(digit()),
      zulu()
    ])
  end

  ## Helpers

  def recurrence(combinator \\ empty()) do
    combinator
    |> ignore(ascii_char([?r, ?R]))
    |> optional(integer(min: 1))
    |> ignore(string("/"))
    |> reduce(:recur)
    |> unwrap_and_tag(:recurrence)
    |> label("recurrence")
  end

  def list_of_time_or_range(combinator \\ empty()) do
    combinator
    |> time_or_range()
    |> repeat(ignore(string(",")) |> time_or_range())
    |> label("list of times or ranges")
  end

  def time_or_range(combinator \\ empty()) do
    combinator
    |> choice([
      interval_or_time_or_duration()
      |> ignore(string(".."))
      |> interval_or_time_or_duration()
      |> reduce(:range),
      replace(string(".."), :undefined)
      |> interval_or_time_or_duration()
      |> reduce(:range),
      interval_or_time_or_duration()
      |> replace(string(".."), :undefined)
      |> reduce(:range),
      interval_or_time_or_duration()
    ])
    |> label("date, time, interval, duration or range")
  end

  # Ranges here split into two semantics:
  #
  # * **Iterable ranges** (integer set `{5..1}M`, date range
  #   `2024Y..2022Y`): when `last < first`, the user intends a
  #   **descending** sequence — use step `-1`. When `last >= first`,
  #   use step `1`.
  #
  # * **Sentinel ranges** (`first..-last`, e.g. `{1..-5}` meaning
  #   "first to the 5th-from-end"): `.last` carries a negative
  #   sentinel, not an iteration target. Use step `1` so the pair
  #   is preserved verbatim.
  #
  # The explicit step also silences Elixir 1.20's warning about
  # ranges defaulting to step `-1` when `last < first`.
  def range(date: [{element, first}], date: [{element, last}])
      when is_integer(first) and is_integer(last) do
    {element, iterable_range(first, last)}
  end

  def range([[first, "..", last]]) when is_integer(first) and is_integer(last) do
    iterable_range(first, last)
  end

  def range([[first, "..", ?-, last]]) when is_integer(first) and is_integer(last) do
    first..-last//1
  end

  def range([[first, "..", last], step])
      when is_integer(first) and is_integer(last) and is_integer(step) do
    first..last//step
  end

  def range([[first, "..", ?-, last], step])
      when is_integer(first) and is_integer(last) and is_integer(step) do
    first..-last//step
  end

  def range([:undefined, {_type, other}]) do
    {:range, [:undefined, other]}
  end

  def range([{_type, other}, :undefined]) do
    {:range, [other, :undefined]}
  end

  def range([left, right]) do
    {:range, [left, right]}
  end

  # Used by the `range/1` clauses above for forms where the user
  # supplies no step: descending first..last iterates `-1`, ascending
  # iterates `1`. Explicit so Elixir 1.20's `..` default doesn't emit
  # a warning and the step is the one the user would intuitively want.
  defp iterable_range(first, last) when last >= first, do: first..last//1
  defp iterable_range(first, last), do: first..last//-1

  def list_of_integer_or_range(combinator \\ empty()) do
    combinator
    |> integer_or_range()
    |> repeat(ignore(string(",")) |> integer_or_range())
    |> label("list of integers or ranges")
  end

  def integer_or_range(combinator \\ empty()) do
    combinator
    |> choice([
      maybe_negative_integer(min: 1)
      |> string("..")
      |> maybe_negative_integer(min: 1)
      |> optional(ignore(string("//")) |> maybe_negative_integer(min: 1))
      |> reduce(:range),
      maybe_negative_integer(min: 1)
    ])
    |> label("integer or range")
  end

  def resolve_shift([{:sign, ?-}, {component, value} | rest]) do
    [{component, -value} | rest]
  end

  def resolve_shift([{:sign, ?+} | rest]) do
    rest
  end

  def resolve_shift([?Z]) do
    [{:hour, 0}]
  end

  def resolve_shift([?Z | rest]) do
    resolve_shift(rest)
  end

  def resolve_shift(other) do
    other
  end

  def adjust_interval(date: [year: year, month: month], date: [century: century]) do
    [date: [year: year, month: month], date: [month: century]]
  end

  def adjust_interval(other) do
    other
  end
end
