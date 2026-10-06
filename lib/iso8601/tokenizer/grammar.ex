defmodule Tempo.Iso8601.Tokenizer.Grammar do
  @moduledoc false
  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Numbers
  import Tempo.Iso8601.Tokenizer.Helpers
  import Tempo.Iso8601.Tokenizer.Extended, only: [extended_suffix: 0]

  def iso8601_tokenizer do
    optional(qualification())
    |> choice([
      interval_or_time_or_duration(),
      parsec({Tempo.Iso8601.Tokenizer.Set, :set})
    ])
    |> optional(qualification())
    |> optional(extended_suffix())
    |> label("ISO8601 interval, duration, date, time or datetime")
  end

  # A profile tokenizer admits exactly one of the shapes the standard
  # defines, rather than the full alternation `iso8601_tokenizer/0`
  # offers. The EDTF qualification and IXDTF extended suffix wrappers are
  # kept: they are orthogonal to which shape sits between them, so an
  # approximate date (`2026-06-15~`) and a calendar-tagged one
  # (`2026-06-15[u-ca=hebrew]`) remain dates. The caller of a profile has
  # declared the type its value must have, so `eos/0` is applied by the
  # entry point to reject a value that merely *starts* with that shape.
  def profile_tokenizer(core) do
    optional(qualification())
    |> concat(core)
    |> optional(qualification())
    |> optional(extended_suffix())
  end

  def interval_or_time_or_duration(combinator \\ empty()) do
    combinator
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}),
      parsec({Tempo.Iso8601.Tokenizer.Date, :datetime_or_date_or_time})
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

  # A month alone is a date here, as it is after a year (`2026Y6MT10H`):
  # `explicit_date/0` leaves a month a time follows to this rule.
  def explicit_date_time do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_date_p}),
      parsec({Tempo.Iso8601.Tokenizer.Date, :explicit_month_p}) |> lookahead(string("T"))
    ])
    |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :explicit_time_of_day_p}))
  end

  # Date

  def implicit_date do
    choice([
      implicit_week_date(),
      # A year and a set of days of the year, each of three digits, which a
      # set of months would otherwise take.
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> concat(days_of_year_set()),
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

      # A year and a set of days of the year, each of three digits
      # (`2026-{001,166}`), which a set of months would otherwise take:
      # `2026-{001}` was read as January.
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_year_p})
      |> ignore(dash())
      |> concat(days_of_year_set()),

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

  defp days_of_year_set do
    parsec({Tempo.Iso8601.Tokenizer.Set, :day_of_year_set_all})
    |> unwrap_and_tag(:day_of_year)
  end

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
      # A week and a day of it with no year (`W265`), as `26W5K` is, and as
      # the end of an interval that started in the year (`2026W251/W265`).
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_week_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_week_p})),
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
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_week_p})),
      parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_week_p})
      |> ignore(dash())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Date, :implicit_day_of_week_p}))
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

  # A time of day is written after a `T`, or with none where it is the
  # whole of what is written. With none, a set of whole numbers alone is no
  # time of day: one that is no set of years (`{20260615,20260616}`) would be
  # taken for a set of hours, and is left to be read member by member. A set
  # of hours is written after a `T` (`T{19,20}`).
  def implicit_time_of_day do
    choice([
      ignore(string("T")) |> implicit_clock(empty()),
      implicit_clock(lookahead_not(string("{")))
    ])
    |> optional(time_fraction())
  end

  defp implicit_clock(combinator \\ empty(), before_an_hour_alone) do
    combinator
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p}))
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_second_p})),
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p})),
      before_an_hour_alone
      |> parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
    ])
  end

  def extended_time_of_day do
    choice([
      ignore(string("T")) |> extended_clock(empty()),
      extended_clock(lookahead_not(string("{")))
    ])
    |> optional(time_fraction())
  end

  defp extended_clock(combinator \\ empty(), before_an_hour_alone) do
    combinator
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> ignore(colon())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p}))
      |> ignore(colon())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_second_p})),
      parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> ignore(colon())
      |> concat(parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_minute_p})),
      before_an_hour_alone
      |> parsec({Tempo.Iso8601.Tokenizer.Time, :implicit_hour_p})
      |> lookahead_not(digit())
    ])
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
      duration_elements_with_designators(),
      parsec({Tempo.Iso8601.Tokenizer.Date, :datetime_or_date_or_time})
    ])
  end

  # A duration written with unit designators (`1Y2M`, `T30M`), without the
  # alternative format that writes one as a date (`0002-10-15`). A group's
  # unit (ISO 8601-2 §5.2) is only ever this form: read as a date, `2K`
  # would reach the group as a day of the week rather than a size.
  def duration_elements_with_designators(combinator \\ empty()) do
    combinator
    |> choice([
      concat(duration_date_elements(), duration_time_elements()),
      duration_date_elements(),
      duration_time_elements()
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
      # The sign, integer, and fraction of a duration second reduce
      # together, so `PT-0.2S` keeps its sign (a `-0` integer second
      # cannot carry it alone). The fraction is preserved with its digit
      # count — folding to a float would lose significant trailing zeros
      # (`PT1.250S` vs `PT1.25S`). A fraction follows a whole number only:
      # one given to significant digits, a mask and a set take none.
      optional(negative())
      |> integer(min: 1)
      |> concat(fraction())
      |> reduce({Tempo.Iso8601.Tokenizer.Numbers, :form_duration_second, []})
      |> unwrap_and_tag(:second)
      |> ignore(string("S")),
      optional(negative())
      |> positive_integer(min: 1)
      |> reduce({Tempo.Iso8601.Tokenizer.Numbers, :form_duration_second, []})
      |> unwrap_and_tag(:second)
      |> ignore(string("S"))
    ])
  end

  # Selections

  # Date elements with optional time elements, or time elements alone. The date
  # elements are parsed once: trying date-plus-time and then date-alone as
  # separate alternatives re-parsed them whenever the time part was absent.
  def selection_elements(combinator \\ empty()) do
    combinator
    |> choice([
      selection_date_elements() |> optional(selection_time_elements()),
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
      traditional_month(),
      maybe_negative_integer_or_integer_set("W", :week, min: 1),
      # `w` is Tempo's extension: a week in the calendar's own numbering, where
      # `W` is an ISO 8601 week.
      maybe_negative_integer_or_integer_set("w", :calendar_week, min: 1),
      maybe_negative_integer_or_integer_set("O", :day_of_year, min: 1),
      maybe_negative_integer_or_integer_set("D", :day, min: 1),
      maybe_negative_integer_or_integer_set("K", :day_of_week, min: 1),
      # `q` (WKST) is a Tempo project-specific designator — an RFC 5545 extension
      # with no ISO 8601 form. (BYSETPOS is the ISO 8601-2 §12.9 position `I`.)
      week_start(),
      selection_instance(),
      selection_event(),
      ignore(string("L"))
      |> parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser})
      |> ignore(string("N")),
      # ISO 8601-2 §12.10 bare selection-with-time-interval (`L3K4IN/P5D`): the
      # window is the terminal element, not wrapped in its own `L…N`. Tried after
      # the wrapped form above, so a window that IS followed by more selectors
      # (`LL2K2IN/P10DN4K2I`) still matches the wrapped clause first. Its start
      # is always an `L…N` selection, so it is only attempted at an `L`: trying
      # the whole interval grammar at every other position — every selection's
      # closing `N` included — is what made nested windows exponential to parse.
      lookahead(string("L"))
      |> parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser})
    ])
  end

  def selection_time_element do
    choice([
      maybe_negative_integer_or_integer_set("H", :hour, min: 1),
      maybe_negative_integer_or_integer_set("M", :minute, min: 1),
      # A clock second takes no significant digits, so the `S` after it is its
      # designator whatever follows: in `0S1I` a position does.
      maybe_negative_exact_integer_or_integer_set("S", :second, min: 1),
      ignore(string("L"))
      |> parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser})
      |> ignore(string("N"))
    ])
  end

  # A position is an integer (ISO 8601-2 §12.9), with no significant digits.
  def selection_instance do
    maybe_negative_exact_integer_or_integer_set("I", :instance, min: 1)
  end

  # Week start (RFC 5545 WKST), written `<n>q`. A Tempo extension: lowercase `q`
  # is the canonical, emitted form, following the lowercase-extension convention.
  # The uppercase `Q` shipped in 1.6.x before the convention, so it is still
  # accepted on input (liberal in) and re-emitted as `q` (conservative out).
  def week_start do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_one}),
      maybe_negative_integer(min: 1)
    ])
    |> ignore(ascii_char([?q, ?Q]))
    |> unwrap_and_tag(:wkst)
  end

  # A computed-event selection — the one ISO 8601-2 §12 construct with no
  # standard form: an algorithmically resolved recurrence such as Easter or an
  # astronomical event. The event name is a lowercase identifier delimited by
  # parentheses and closed by the lowercase `e` designator, e.g. `(easter)e`,
  # `(march-equinox)e`: a letter, then letters, digits and hyphens, so a
  # registered name such as `fiscal-q3` is written as any other. Lowercase
  # marks it a Tempo extension (uppercase `E` is the EDTF long-year exponent).
  # An event that happens at an instant may name the zone whose date it takes
  # after an `@` — an IANA zone or a `±HH:MM` offset, `(march-equinox@+09:00)e`
  # — kept as part of the name. It resolves per period via `Tempo.Event`.
  def selection_event do
    ignore(string("("))
    |> ascii_string([?a..?z], 1)
    |> ascii_string([?a..?z, ?0..?9, ?-], min: 0)
    |> optional(
      string("@")
      |> ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?/, ?+, ?-, ?:], min: 1)
    )
    |> ignore(string(")"))
    |> ignore(string("e"))
    |> reduce({Enum, :join, []})
    |> unwrap_and_tag(:event)
  end

  # Individual date and time components
  # Note that any component can be alternatively a group
  # or set. In the explicit form a group may be followed by a value of
  # its own unit, counted within the group (ISO 8601-2 §5.4.2): in
  # `2018Y9M2DT3GT8HU0H30M` the `0H30M` is 30 minutes into the third
  # eight hours.

  def implicit_year do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :year_set_all}) |> unwrap_and_tag(:year),

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

  # The years of a set written with no designator (`{1960,1961}`, ISO 8601-2
  # §6.1), each as a year is written alone: four digits, or five and more
  # after a minus sign (ISO 8601-1 §4.4). Any whole numbers were taken for
  # years, so `{20260615,20260616}` was the years 20260615 and 20260616,
  # where each is a date alone, and `{19,20}` the years 19 and 20, where each
  # is a century alone and in a set of one of (decided 2026-10-06). A set
  # whose members are not years is read member by member
  # (`Tempo.Iso8601.Tokenizer.Set`'s `:set_all`).
  def list_of_year_or_range(combinator \\ empty()) do
    combinator
    |> year_or_range()
    |> repeat(ignore(string(",")) |> year_or_range())
    |> label("list of years or ranges of years")
  end

  defp year_or_range(combinator) do
    combinator
    |> choice([
      set_year()
      |> ignore(string(".."))
      |> concat(set_year())
      |> optional(ignore(string("//")) |> integer(min: 1))
      |> post_traverse({__MODULE__, :year_range, []}),
      set_year()
    ])
  end

  defp set_year do
    choice([
      negative() |> positive_integer(min: 5) |> reduce(:form_number),
      maybe_negative_integer(4)
    ])
    |> lookahead_not(digit())
  end

  # A range of years, from its first up to its last. One written backwards
  # is given the step `-1`, which is how the parser knows it and refuses it,
  # as `range/1` does for any range of whole numbers. A range whose ends are
  # not whole years (`{19XX..20XX}`) is no range of years.
  @doc false
  def year_range(rest, [last, first], context, _line, _offset)
      when is_integer(first) and is_integer(last),
      do: {rest, [iterable_range(first, last)], context}

  def year_range(rest, [step, last, first], context, _line, _offset)
      when is_integer(first) and is_integer(last),
      do: {rest, [first..last//step], context}

  def year_range(_rest, _ends, _context, _line, _offset),
    do: {:error, "a range of years runs from one whole year to another"}

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
      # A group after the year takes this slot whatever its unit, so a
      # value after it may be a month (`2G3MU2M`) or a week (`2G13WU3W`).
      parsec({Tempo.Iso8601.Tokenizer.Set, :group})
      |> optional(
        choice([
          qualified_number_or_integer_set("M", :month, min: 1),
          maybe_negative_number_or_integer_set("W", :week, min: 1)
        ])
      ),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      traditional_month(),
      qualified_number_or_integer_set("M", :month, min: 1),
      quarter(),
      half()
    ])
  end

  # A traditional month, written `<n>m` (and `<n>+m` for the
  # intercalary month following traditional month `n`, 閏n月). Lowercase `m`
  # marks it a Tempo extension — the counterpart to the ordinal ISO 8601 `M`.
  # The tokeniser is calendar-blind, so it tags `:traditional_month`
  # structurally: `Tempo.Validation` resolves it to the ordinal month against a
  # calendar with leap months (Hebrew, lunisolar), and to `n` itself on any other (where the traditional
  # and ordinal numberings coincide). In a selection frame the tag survives
  # unresolved — a recurrence has no year — and materialisation resolves it per
  # year. The same combinator serves both frames.
  def traditional_month do
    choice([
      positive_integer(min: 1)
      |> ignore(string("+"))
      |> ignore(string("m"))
      |> reduce({__MODULE__, :as_leap_month, []}),
      positive_integer(min: 1)
      |> ignore(string("m"))
    ])
    |> unwrap_and_tag(:traditional_month)
  end

  def as_leap_month([month]), do: {month, :leap}

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

  # `W` is an ISO 8601 week and `w`, Tempo's extension, a week in the
  # calendar's own numbering.
  def explicit_week do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group})
      |> optional(maybe_negative_number_or_integer_set("W", :week, min: 1)),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      maybe_negative_number_or_integer_set("W", :week, min: 1),
      maybe_negative_number_or_integer_set("w", :calendar_week, min: 1)
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
      parsec({Tempo.Iso8601.Tokenizer.Set, :group})
      |> optional(qualified_number_or_integer_set("D", :day, min: 1)),
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

  # Day of year (ISO 8601-2 §4.3.4), its own unit: a day of the month is `D`.

  def implicit_day_of_year do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :integer_set_all}) |> unwrap_and_tag(:day_of_year),
      positive_integer(3) |> unwrap_and_tag(:day_of_year)
    ])
  end

  def explicit_day_of_year do
    choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :group}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      maybe_negative_number_or_integer_set("O", :day_of_year, min: 1)
    ])
  end

  # Decade and century, like week, cannot
  # ever encounter a group because the
  # Year combinator will consume it first since
  # Year has priority order over century and
  # decade

  def implicit_decade do
    before_year_one_or_not(positive_integer(3))
    |> unwrap_and_tag(:decade)
  end

  def explicit_decade do
    before_year_one_or_not(positive_number(min: 1))
    |> ignore(string("J"))
    |> unwrap_and_tag(:decade)
  end

  # The number of a decade or a century, with its minus sign kept apart from
  # it. One before year one is the years its digits begin, read with their
  # sign (ISO 8601-2 §4.4.1.7 and §4.4.1.8): `-19` is the years -1999 to
  # -1900, and the negative zero century `-00` the years -99 to 0, which the
  # zero century `00` is not. As a negative number it was the hundred years
  # from -1900 up, and `-00` was `00`.
  defp before_year_one_or_not(number) do
    choice([
      ignore(negative())
      |> concat(number |> reduce(:form_number))
      |> unwrap_and_tag(:before_year_one),
      number |> reduce(:form_number)
    ])
  end

  # A decimal fraction belongs to an hour, a minute or a second alone (ISO
  # 8601-1 §5.3.1.4), so two digits with one (`09,5`, `23.5Z`) are an hour
  # and its fraction, not a century.
  #
  # A fraction is a decimal sign and a digit, and a comma is a decimal sign
  # only outside a set, where it separates the members: the first of
  # `[19,20]` and of `[19..20]` was read as the hour 19, beside the century
  # the second member is.
  def implicit_century do
    before_year_one_or_not(positive_integer(2))
    |> lookahead_not(colon())
    |> lookahead_not(decimal_sign() |> concat(digit()))
    |> unwrap_and_tag(:century)
  end

  def explicit_century do
    before_year_one_or_not(positive_number(min: 1))
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
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group})
      |> optional(maybe_negative_number_or_integer_set("H", :hour, min: 1)),
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
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group})
      |> optional(maybe_negative_number_or_integer_set("M", :minute, min: 1)),
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
      parsec({Tempo.Iso8601.Tokenizer.Set, :time_group})
      |> optional(explicit_second_or_integer_set("S", min: 1)),
      parsec({Tempo.Iso8601.Tokenizer.Set, :selection}),
      explicit_second_or_integer_set("S", min: 1)
    ])
  end

  # Time Shift
  #
  # A time shift is a whole number of hours and of minutes (ISO 8601-1
  # §4.3.13), and of seconds too in the explicit form (ISO 8601-2 §7.4). Its
  # units were read by the combinators that read a time of day's, which take
  # a set, a range, unspecified digits, a group, a selection and a fraction.
  # None of them is a shift, and each raised: where the value was read (a set
  # or a mask), where it was written (a fraction of a second, a group) or
  # where it was compared (a fraction of an hour or a minute).

  def implicit_time_shift do
    shift_indicator()
    |> choice([
      shift_hour()
      |> ignore(optional(colon()))
      |> concat(shift_minute()),
      shift_hour(),
      lookahead_not(digit())
    ])
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  def extended_time_shift do
    shift_indicator()
    |> choice([
      shift_hour()
      |> ignore(optional(colon()))
      |> concat(shift_minute()),
      shift_hour()
      |> lookahead_not(digit()),
      lookahead_not(digit())
    ])
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  defp shift_hour, do: integer(2) |> unwrap_and_tag(:hour)
  defp shift_minute, do: integer(2) |> unwrap_and_tag(:minute)

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
  #   * `Z1H`, `Z-05H30M`, and `Z+1H` — UTC with explicit components, signed
  #     behind UTC (ISO 8601-2 §7.4) and, leniently, ahead of it
  #   * `Z0S`, `Z30M`       — with the units that are zero left out (§7.10,
  #     and §7.4 example 8)
  def explicit_time_shift do
    zulu()
    |> optional(optional(sign()) |> concat(shift_units()))
    |> lookahead_not(digit())
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  # The units of an explicit shift, from the hour down, each a whole number
  # and any of them left out.
  defp shift_units do
    choice([
      shift_unit(:hour, "H")
      |> optional(shift_unit(:minute, "M"))
      |> optional(shift_unit(:second, "S")),
      shift_unit(:minute, "M")
      |> optional(shift_unit(:second, "S")),
      shift_unit(:second, "S")
    ])
  end

  defp shift_unit(unit, designator),
    do: integer(min: 1) |> ignore(string(designator)) |> unwrap_and_tag(unit)

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
    |> members_of_a_set(
      time_or_range_member()
      |> repeat(ignore(string(",")) |> time_or_range_member())
    )
    |> label("list of times or ranges")
  end

  # A recurrence domain may end with a year filter — `e` (even), `o` (odd), `l`
  # (leap) or `c` (common, a year that is not a leap year) — that keeps only the
  # matching years, as in `{2000Y..2020Y}e`.
  # Tokenised as `{:filter, …}`; the parser lifts it onto `%Tempo.Set{}`'s
  # `:filter`. A non-conformant Tempo extension.
  def domain_filter(combinator \\ empty()) do
    combinator
    |> choice([
      replace(string("e"), {:filter, :even}),
      replace(string("o"), {:filter, :odd}),
      replace(string("l"), {:filter, :leap}),
      replace(string("c"), {:filter, :common})
    ])
    |> label("domain year filter")
  end

  # A set member may be prefixed with `^` to mark it excluded — subtracted from
  # the set's plain members when the set materialises, as in
  # `{2020Y..2030Y,^2026Y}`. The tokeniser tags it `{:except, …}`; the parser
  # routes it to `%Tempo.Set{}`'s `:except`. A non-conformant Tempo extension.
  def time_or_range_member(combinator \\ empty()) do
    combinator
    |> choice([
      ignore(string("^")) |> time_or_range() |> tag(:except),
      time_or_range()
    ])
  end

  def time_or_range(combinator \\ empty()) do
    combinator
    |> choice([
      member_value()
      |> ignore(string(".."))
      |> member_value()
      |> reduce(:range),
      replace(string(".."), :undefined)
      |> member_value()
      |> reduce(:range),
      member_value()
      |> replace(string(".."), :undefined)
      |> reduce(:range),
      member_value()
    ])
    |> label("date, time, interval, duration or range")
  end

  # What a member of a set is: an interval, a duration, or a date or a time
  # with its qualifiers.
  defp member_value(combinator \\ empty()) do
    combinator
    |> choice([
      parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser}),
      parsec({Tempo.Iso8601.Tokenizer.Set, :duration_parser}),
      parsec({Tempo.Iso8601.Tokenizer.Date, :qualified_member})
    ])
  end

  # Ranges here split into two kinds:
  #
  # * **Ranges of values** (integer set `{1..5}M`, date range
  #   `2022Y..2024Y`): from the first value up to the last, step `1`.
  #   One written backwards (`{5..1}M`) is given step `-1` here, which
  #   is how the parser knows it and refuses it
  #   (`Tempo.Iso8601.Parser.parse/2`).
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

  # A duration or an interval keeps its tag at the end of a range with one
  # end, as it does in a range with two, so that the parser knows it for
  # what it is: neither is an end of a range
  # (`Tempo.Iso8601.Parser.parse/2`).
  def range([:undefined, {type, _tokens} = no_end]) when type in [:duration, :interval] do
    {:range, [:undefined, no_end]}
  end

  def range([{type, _tokens} = no_end, :undefined]) when type in [:duration, :interval] do
    {:range, [no_end, :undefined]}
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

  # What is written as a range and is none of the above: one between
  # unspecified digits, which `range_of_whole_numbers/5` refuses.
  def range(other), do: {:no_range, other}

  # Used by the `range/1` clauses above for forms where the user
  # supplies no step: ascending first..last counts up by `1`, and one
  # written backwards is marked with `-1` for the parser to refuse.
  defp iterable_range(first, last) when last >= first, do: first..last//1
  defp iterable_range(first, last), do: first..last//-1

  # The days of the year in a set of the extended or the basic format: each
  # is three digits, as a day of the year is written there (`2026-166`), and
  # a range runs from one of them to another. A set of any other width after
  # a year is the year's months.
  def list_of_day_of_year_or_range(combinator \\ empty()) do
    combinator
    |> day_of_year_or_range()
    |> repeat(ignore(string(",")) |> day_of_year_or_range())
    |> label("list of days of the year or ranges of them")
  end

  defp day_of_year_or_range(combinator) do
    combinator
    |> choice([
      wrap(three_digits() |> string("..") |> concat(three_digits()))
      |> reduce(:range)
      |> post_traverse({__MODULE__, :range_of_whole_numbers, []}),
      three_digits()
    ])
  end

  defp three_digits, do: positive_integer(3) |> lookahead_not(digit())

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
      |> reduce(:range)
      |> post_traverse({__MODULE__, :range_of_whole_numbers, []}),
      maybe_negative_integer(min: 1)
    ])
    |> label("integer or range")
  end

  # A range in a set of whole numbers runs from one whole number to another.
  # One between unspecified digits (`{1X..2X}D`, `{19XX..20XX}`) is no range
  # of them, and `range/1` raised for it. It is refused here, in a combinator
  # read through `parsec`, so that it is that combinator failing.
  @doc false
  def range_of_whole_numbers(rest, [%Range{}] = range, context, _line, _offset),
    do: {rest, range, context}

  def range_of_whole_numbers(_rest, _no_range, _context, _line, _offset),
    do: {:error, "a range of whole numbers runs from one whole number to another"}

  # A negative shift carries its sign on its first non-zero component,
  # so `-00:30` stays negative as `[hour: 0, minute: -30]`. It is written
  # with a hyphen or with the minus sign itself (`−`, U+2212), which was
  # read and kept as a unit of the shift.
  def resolve_shift([{:sign, minus} | components]) when minus in [?-, ?−] do
    negate_leading(components)
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

  defp negate_leading([{component, 0} | [_ | _] = rest]),
    do: [{component, 0} | negate_leading(rest)]

  defp negate_leading([{component, value} | rest]), do: [{component, -value} | rest]
  defp negate_leading([]), do: []

  # ISO 8601-1:2019 §5.5.1: "higher order time scale components may be
  # omitted from the 'end of time interval' … the omitted higher order
  # components from the 'start of time interval' expression apply." An end
  # that is one bare number (`Tempo.Iso8601.Tokenizer.Date`'s
  # `:bare_number_endpoint`) is the start's last component when it has as
  # many digits as that component is written with: `2026-06-15/20` ends on
  # the 20th, `2026-06-15T10:30/45` at 10:45, `2026-166/170` on the year's
  # 170th day and `2026-W25-1/5` on the week's fifth. After a start with no
  # such component it is what the number is alone, two digits a century and
  # three a decade, and one digit is nothing.
  @endpoint_tags [:date, :datetime, :time_of_day]
  @endpoint_units [
    :year,
    :month,
    :week,
    :day,
    :day_of_year,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]
  @bare_numbers [:one_digit, :two_digits, :three_digits]
  @two_digit_units [:month, :week, :day, :hour, :minute, :second]
  @time_units [:hour, :minute, :second]

  def adjust_interval(rest, tokens, context, _line, _offset) do
    case abbreviated_end(Enum.reverse(tokens)) do
      {:error, reason} -> {:error, reason}
      tokens -> {rest, [tokens], context}
    end
  end

  defp abbreviated_end([{tag, start} = from, {:date, [{digits, number} | rest]} | tail])
       when tag in @endpoint_tags and is_list(start) and digits in @bare_numbers do
    case abbreviated(digits, number, finest_unit(start)) do
      {:error, reason} -> {:error, reason}
      {unit, number} -> [from, {abbreviated_tag(unit), [{unit, number} | rest]} | tail]
    end
  end

  defp abbreviated_end([token | tail]) do
    case abbreviated_end(tail) do
      {:error, reason} -> {:error, reason}
      tail -> [token | tail]
    end
  end

  defp abbreviated_end([]), do: []

  defp finest_unit(start) do
    Enum.reduce(start, nil, fn
      {unit, _value}, _finest when unit in @endpoint_units -> unit
      _other, finest -> finest
    end)
  end

  defp abbreviated(:two_digits, number, unit) when unit in @two_digit_units, do: {unit, number}
  defp abbreviated(:two_digits, number, _unit), do: {:century, number}
  defp abbreviated(:three_digits, number, :day_of_year), do: {:day_of_year, number}
  defp abbreviated(:three_digits, number, _unit), do: {:decade, number}
  defp abbreviated(:one_digit, number, :day_of_week), do: {:day_of_week, number}

  defp abbreviated(:one_digit, _number, _unit),
    do: {:error, "one digit ends an interval only after a day of the week"}

  defp abbreviated_tag(unit) when unit in @time_units, do: :time_of_day
  defp abbreviated_tag(_unit), do: :date
end
