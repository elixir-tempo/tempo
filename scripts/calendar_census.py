"""A census of every place Tempo's implementation touches a calendar.

It reads every `.ex` file under `lib/`, classes each line as code, comment or
documentation, and writes one table for each kind of touch, as the Markdown of
`plans/calendar-surface-census.md`. Nothing is sampled: every file is read and
every match is written. The plan it serves is `plans/calendar-surface.md`.

    python3 scripts/calendar_census.py > plans/calendar-surface-census.md

The tables are mechanical but for two columns, which are a reading of the code:
the class of each line that names a calendar (`NAMED`) and of each line that
holds a calendar number (`NUMBERS`). Each reading is kept by its file, the
function it is in and what the line names or holds, in the order of the file,
so it does not move with the lines. A line of either kind that has no reading
is written as `unread`, so the reading cannot fall behind the code unseen.
"""
import collections
import os
import re

READ_AT = "254923c"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The callbacks of Elixir's `Calendar` behaviour (1.20.4), all required.
CALENDAR = {
    ("date_to_string", 3), ("datetime_to_string", 11), ("day_of_era", 3), ("day_of_week", 4),
    ("day_of_year", 3), ("day_rollover_relative_to_midnight_utc", 0), ("days_in_month", 2),
    ("iso_days_to_beginning_of_day", 1), ("iso_days_to_end_of_day", 1), ("leap_year?", 1),
    ("months_in_year", 1), ("naive_datetime_from_iso_days", 1), ("naive_datetime_to_iso_days", 7),
    ("naive_datetime_to_string", 7), ("parse_date", 1), ("parse_naive_datetime", 1),
    ("parse_time", 1), ("parse_utc_datetime", 1), ("quarter_of_year", 3), ("shift_date", 4),
    ("shift_naive_datetime", 8), ("shift_time", 5), ("time_from_day_fraction", 1),
    ("time_to_day_fraction", 4), ("time_to_string", 4), ("valid_date?", 3), ("valid_time?", 4),
    ("year_of_era", 3),
}

# The callbacks of the `Calendrical` behaviour at Calendrical `43006d7`.
CALENDRICAL_REQUIRED = {
    ("month_of_year", 3), ("cardinal_month", 1), ("week_of_year", 3), ("iso_week_of_year", 3),
    ("week_of_month", 3), ("cldr_calendar_type", 0), ("calendar_base", 0), ("days_in_week", 0),
    ("weeks_in_year", 1), ("days_in_year", 1), ("days_in_month", 1), ("dates_in_gregorian_year", 3),
    ("era_calendar_type", 0), ("parsing_calendar", 0), ("calendar_year", 3), ("extended_year", 3),
    ("related_gregorian_year", 3), ("cyclic_year", 3), ("year", 1), ("quarter", 2), ("month", 2),
    ("week", 2), ("plus", 6), ("diff", 3), ("date_to_iso_days", 3), ("date_from_iso_days", 1),
}
CALENDRICAL_OPTIONAL = {
    ("cardinal_day", 3), ("months_in_year", 0), ("months_in_leap_year", 0),
    ("lunar_month_of_year", 2), ("ordinal_month_from_traditional", 2), ("leap_month", 1),
    ("traditional_leap_month", 1), ("cldr_calendar_type", 3),
    ("calendar_from_cldr_calendar_type", 1), ("parsing_calendars", 0),
}

# The calendar modules a line of code may name.
CALENDARS = {
    "Calendar.ISO": "ISO", "Calendrical.Gregorian": "Gregorian", "Calendrical.ISOWeek": "ISOWeek",
    "Calendrical.Chinese": "Chinese",
}

NAMED_CLASSES = collections.OrderedDict([
    ("D", "Default: no calendar given is the Gregorian."),
    ("I", "`Calendar.ISO` read as the Gregorian, or written back as it, at the boundary."),
    ("F", "Fast path: the Gregorian is answered without asking it, where the general path would give the same answer."),
    ("S", "Special case: the Gregorian, or another named calendar, is given other behaviour than the rest."),
    ("G", "A computation done in the Gregorian by naming it, where any calendar could be asked."),
    ("W", "`Calendrical.ISOWeek` paired with the Gregorian for ISO 8601 week dates."),
    ("X", "The Gregorian as the calendar of something outside Tempo: the zone database, Astro, RFC 5545, cron."),
    ("T", "Text: the calendar's name is left out of what is written for a Gregorian value."),
])

NAMED = {
    "lib/compare.ex": [
        ('fields_in_day_order?', 'Gregorian, ISO', 'F'),
        ('wall_seconds', 'Gregorian', 'G'),
        ('resolve_ymd', 'Gregorian', 'D'),
        ('gregorian_ymd', 'Gregorian', 'G'),
        ('effective_calendar', 'Gregorian', 'D'),
        ('to_gregorian_ymd', 'Gregorian', 'F'),
        ('gregorian_seconds', 'Gregorian', 'G'),
    ],
    "lib/enumeration/skipped_readings.ex": [
        ('date_named?', 'Gregorian', 'X'),
    ],
    "lib/enumeration/zone.ex": [
        ('status_in', 'Gregorian, ISO', 'X'),
        ('in_gregorian', 'Gregorian', 'X'),
        ('in_gregorian', 'Gregorian, ISO', 'X'),
        ('in_gregorian', 'Gregorian', 'X'),
        ('gregorian_units', 'Gregorian', 'X'),
        ('in_calendar_of', 'Gregorian', 'X'),
        ('in_calendar_of', 'Gregorian, ISO', 'X'),
        ('in_calendar_of', 'Gregorian', 'X'),
        ('calendar_of_weeks', 'Gregorian, ISOWeek', 'W'),
        ('on_one_of?', 'Gregorian, ISO', 'X'),
        ('end_of_gregorian_hour', 'Gregorian, ISO', 'X'),
        ('first_reading', 'Gregorian, ISO', 'X'),
        ('first_reading', 'Gregorian', 'X'),
    ],
    "lib/event.ex": [
        ('date', 'Gregorian', 'D'),
        ('ecclesiastical_date', 'ISO', 'X'),
        ('solar_term_date', 'ISO', 'X'),
        ('solar_term_location', 'Chinese', 'S'),
    ],
    "lib/explain.ex": [
        ('calendar_of', 'Gregorian', 'D'),
        ('calendar_text', 'Gregorian', 'T'),
        ('gregorian_names?', 'Gregorian', 'S'),
        ('rule_naming', 'Gregorian', 'D'),
    ],
    "lib/inspect.ex": [
        ('to_iodata', 'Gregorian', 'D'),
        ('same_start_in_gregorian?', 'Gregorian', 'T'),
        ('gregorian_date?', 'Gregorian', 'T'),
        ('calendar_name', 'Gregorian', 'T'),
        ('calendar_name', 'Gregorian', 'D'),
        ('calendar_name', 'Gregorian', 'T'),
        ('inspect', 'Gregorian', 'D'),
        ('inspect', 'Gregorian', 'T'),
        ('inspect', 'ISOWeek', 'W'),
        ('inspect', 'ISOWeek', 'W'),
        ('encoded', 'Gregorian', 'T'),
        ('repeat_rule_calendar_trailer', 'Gregorian', 'T'),
        ('repeat_rule_calendar_trailer', 'ISOWeek', 'W'),
    ],
    "lib/iso8601/ast.ex": [
        ('build', 'Gregorian', 'D'),
    ],
    "lib/iso8601/group.ex": [
        ('expand_groups', 'Gregorian', 'D'),
        ('expand_groups', 'Gregorian', 'S'),
        ('resolve_seasons', 'Gregorian', 'D'),
        ('season_span', 'Gregorian', 'S'),
        ('season_span', 'Gregorian', 'S'),
        ('nth_day_of_season', 'Gregorian', 'G'),
        ('unspecified_year_season', 'Gregorian', 'S'),
        ('unspecified_year_season', 'Gregorian', 'S'),
        ('gregorian_year_bounds', 'Gregorian', 'X'),
        ('gregorian_year_bounds', 'Gregorian', 'X'),
    ],
    "lib/math.ex": [
        ('fast_add', 'Gregorian, ISO', 'F'),
        ('stepped_by_its_calendar?', 'Gregorian, ISO', 'F'),
        ('weeks_by_the_calendar', 'Gregorian', 'W'),
    ],
    "lib/sigil.ex": [
        ('do_sigil', 'Gregorian', 'D'),
    ],
    "lib/sigils/options.ex": [
        ('calendar_from', 'ISOWeek', 'W'),
    ],
    "lib/tempo.ex": [
        ('', 'Gregorian', 'D'),
        ('calendar_iso_as_gregorian', 'Gregorian, ISO', 'I'),
        ('quarter_to_group', 'Gregorian', 'D'),
        ('day_of_year_to_date', 'Gregorian', 'D'),
        ('build_tempo', 'Gregorian', 'D'),
        ('resolve_calendar', 'Gregorian', 'D'),
        ('resolve_calendar', 'Gregorian', 'D'),
        ('resolve_calendar', 'Gregorian', 'D'),
        ('from_date', 'ISO', 'I'),
        ('from_date', 'Gregorian', 'F'),
        ('date_units', 'Gregorian', 'F'),
        ('with_a_calendar', 'Gregorian', 'D'),
        ('from_naive_datetime', 'ISO', 'I'),
        ('from_naive_datetime', 'Gregorian', 'I'),
        ('placing_calendar', 'Gregorian, ISO', 'I'),
        ('in_calendar', 'Gregorian', 'D'),
        ('in_calendar', 'Gregorian', 'D'),
        ('day_in_calendar', 'Gregorian', 'F'),
        ('day_in_calendar', 'Gregorian', 'F'),
        ('calendar_of', 'Gregorian', 'D'),
        ('native_calendar', 'Gregorian, ISO', 'I'),
        ('start_in_repeat_calendar', 'Gregorian, ISOWeek', 'S'),
        ('names_no_date_of_any_year?', 'Gregorian', 'S'),
        ('kind_of_year', 'Gregorian', 'G'),
        ('no_date_in_year?', 'Gregorian', 'G'),
        ('no_date_in_year?', 'Gregorian', 'G'),
        ('day_of_week_tempo', 'Gregorian', 'D'),
        ('iso_day_of_week', 'ISO', 'G'),
    ],
    "lib/tempo/cron.ex": [
        ('apply_year_limit', 'Gregorian', 'X'),
    ],
    "lib/tempo/format.ex": [
        ('to_locale_map', 'Gregorian', 'D'),
    ],
    "lib/tempo/network/normalize.ex": [
        ('date_at', 'Gregorian', 'S'),
        ('axis', 'Gregorian', 'S'),
        ('axis', 'Gregorian', 'S'),
        ('single_calendar', 'Gregorian', 'D'),
        ('cyclic?', 'Gregorian', 'S'),
        ('cyclic?', 'Gregorian', 'S'),
        ('gregorian_cycle', 'Gregorian', 'G'),
        ('gregorian_cycle', 'Gregorian', 'G'),
    ],
    "lib/tempo/not_built.ex": [
        ('', 'Gregorian, ISO', 'X'),
    ],
    "lib/tempo/rrule.ex": [
        ('carries_its_calendar', 'Gregorian', 'X'),
    ],
    "lib/tempo/rrule/encoder.ex": [
        ('day_left_to_start', 'Gregorian, ISO', 'X'),
        ('with_days', 'Gregorian', 'X'),
        ('encode_until', 'Gregorian, ISO', 'X'),
        ('encode_until', 'Gregorian', 'X'),
    ],
    "lib/tempo/rrule/rule.ex": [
        ('to_selection', 'Gregorian', 'D'),
        ('with_month_of_start', 'Gregorian, ISO', 'S'),
        ('moves_a_day?', 'Gregorian, ISO', 'S'),
        ('calendar_of_start', 'Gregorian', 'D'),
    ],
    "lib/tempo/rrule/selection.ex": [
        ('event_dates_in_year', 'Gregorian', 'F'),
        ('event_dates_in_year', 'Gregorian', 'F'),
        ('gregorian_year_of', 'Gregorian', 'F'),
        ('gregorian_year_of', 'Gregorian', 'X'),
    ],
    "lib/tempo/select.ex": [
        ('day_of_week_selector', 'Gregorian', 'D'),
        ('counted_in_another_calendar', 'Gregorian, ISOWeek', 'W'),
    ],
    "lib/tempo/set.ex": [
        ('new', 'Gregorian', 'D'),
    ],
    "lib/tempo/unit_values.ex": [
        ('composite?', 'Gregorian, ISO', 'F'),
        ('named_date', 'Gregorian, ISO', 'F'),
        ('month_named_once?', 'Gregorian, ISO', 'F'),
        ('year_named_by_its_months?', 'Gregorian, ISO', 'F'),
        ('year_begins_with_first_month?', 'Gregorian, ISO', 'F'),
        ('years_begin_with_first_month?', 'Gregorian, ISO', 'F'),
        ('date_from_iso_week', 'Gregorian', 'W'),
        ('date_from_iso_week', 'ISOWeek', 'W'),
        ('date_from_iso_week', 'Gregorian', 'W'),
        ('iso_weeks_in_year', 'Gregorian', 'W'),
        ('iso_weeks_in_year', 'ISOWeek', 'W'),
    ],
    "lib/validation.ex": [
        ('validate', 'Gregorian', 'D'),
        ('gregorian_for_iso', 'Gregorian, ISO', 'I'),
        ('calendar_text', 'Gregorian, ISO', 'T'),
        ('check_wall_time_in_zone', 'Gregorian, ISO', 'X'),
    ],
}

NUMBER_CLASSES = collections.OrderedDict([
    ("standard", "A number of a notation or a standard Tempo reads or writes: a cron field, an RRULE weekday, an ISO 8601-2 code, a type."),
    ("prose", "A limit or a turn of phrase, and no fact of a calendar."),
    ("reader", "A bound the reader holds before it knows the value's calendar."),
    ("gregorian", "A fact of the Gregorian calendar, held for the Gregorian alone."),
    ("zone", "A bound on the days of a year of the zone database, which is Gregorian."),
    ("week", "The seven days of a week, which a calendar answers (`days_in_week/0`)."),
    ("leap seconds", "The table of UTC's leap seconds, each a Gregorian date."),
])

NUMBERS = {
    "lib/enumeration/skipped_readings.ex": [
        ('', '400', 'zone'),
    ],
    "lib/explain.ex": [
        ('recurs', '12', 'prose'),
        ('gregorian_month_name', '12', 'gregorian'),
        ('hours_phrase', '12', 'prose'),
        ('times_phrase', '12', 'prose'),
        ('ordinal', '13', 'prose'),
        ('weekday_name', '7', 'week'),
    ],
    "lib/iso8601/group.ex": [
        ('expand_members', '28, 29', 'standard'),
        ('gregorian_season', '12', 'gregorian'),
        ('gregorian_season', '31', 'standard'),
        ('gregorian_season', '29', 'standard'),
        ('gregorian_season', '28, 30', 'standard'),
        ('meteorological_months', '12', 'gregorian'),
    ],
    "lib/iso8601/tokenizer/helpers.ex": [
        ('a_date_and_no_time_of_day', '13', 'reader'),
        ('a_date_and_no_time_of_day', '31', 'reader'),
    ],
    "lib/iso8601/tokenizer/plain.ex": [
        ('tokens', '12', 'reader'),
        ('tokens', '12', 'reader'),
        ('tokens', '31', 'reader'),
    ],
    "lib/iso8601/unit.ex": [
        ('', '30', 'prose'),
        ('', '7', 'week'),
        ('', '7', 'week'),
    ],
    "lib/jscalendar.ex": [
        ('skip', '7', 'standard'),
    ],
    "lib/tempo.ex": [
        ('month_and_day', '12, 31', 'reader'),
        ('put_metadata', '7', 'week'),
        ('walk_too_long_error', '400', 'gregorian'),
        ('walk_too_long_error', '12', 'gregorian'),
        ('moved_by_its_zone', '30', 'zone'),
        ('moved_by_its_zone', '366', 'zone'),
        ('no_date_in_year?', '12, 31', 'gregorian'),
        ('cadence_index', '12', 'gregorian'),
        ('selection_search_span', '7', 'week'),
    ],
    "lib/tempo/cron.ex": [
        ('', '7', 'standard'),
        ('', '12', 'standard'),
        ('every_value', '31', 'standard'),
        ('normalise_month', '12', 'standard'),
        ('normalise_monthday', '31', 'standard'),
        ('normalise_monthday', '31', 'standard'),
        ('parse_dow_part', '7', 'standard'),
        ('dow_range_days', '7', 'standard'),
        ('parse_dow_nth', '53', 'standard'),
        ('dow_step_cron_base', '7', 'standard'),
        ('dow_step_cron_base', '7', 'standard'),
        ('dow_to_cron', '7', 'standard'),
        ('dow_to_rfc', '7', 'standard'),
        ('cron_to_rfc', '7', 'standard'),
        ('cron_to_rfc', '7', 'standard'),
    ],
    "lib/tempo/interval.ex": [
        ('spans_leap_second?', '12, 31', 'standard'),
    ],
    "lib/tempo/network/normalize.ex": [
        ('', '400', 'gregorian'),
        ('date_at', '12', 'gregorian'),
        ('position', '12', 'gregorian'),
        ('gregorian_cycle', '12', 'gregorian'),
        ('gregorian_cycle', '12', 'gregorian'),
        ('length_from', '12', 'gregorian'),
        ('length_from', '12', 'gregorian'),
    ],
    "lib/tempo/rrule.ex": [
        ('', '7', 'standard'),
    ],
    "lib/tempo/rrule/encoder.ex": [
        ('', '7', 'standard'),
    ],
    "lib/tempo/rrule/expander.ex": [
        ('map_weekday', '7', 'standard'),
    ],
    "lib/tempo/rrule/rule.ex": [
        ('', '7', 'standard'),
        ('moves_a_day?', '28', 'gregorian'),
        ('push_wkst', '7', 'standard'),
    ],
    "lib/tempo/rrule/selection.ex": [
        ('application_order_key', '7', 'prose'),
        ('normalise_day_of_week', '7', 'week'),
        ('seven_days_from', '7', 'week'),
        ('nearest_weekday', '7', 'standard'),
        ('snap_back_to_weekday', '7', 'standard'),
    ],
    "lib/tempo/time_zone_database.ex": [
        ('days_of', '365', 'zone'),
        ('clear_in_blocks?', '366', 'zone'),
    ],
    "lib/tempo/unit_values.ex": [
        ('numbers_weeks_of_months?', '7', 'week'),
        ('numbers_weeks_of_months?', '7', 'week'),
        ('iso_weekday_from_day_of_week', '7', 'week'),
        ('day_of_week_from_iso_weekday', '7', 'week'),
        ('day_of_week_from_iso_weekday', '7', 'week'),
        ('date_in_week', '7', 'week'),
        ('weekday_in_week', '7', 'week'),
    ],
    "lib/tempo/workdays.ex": [
        ('', '7', 'standard'),
    ],
}

# Functions that decide by what kind of calendar they are given. Each was
# found by reading every predicate whose head names a calendar, every line
# that names a calendar and every probe; the table lists where each is
# defined and every call of it.
DECIDERS = collections.OrderedDict([
    ("A calendar of weeks, or of months", [
        ("lib/tempo.ex", "week_based_calendar?", "Tempo"),
        ("lib/compare.ex", "week_based?", None),
        ("lib/inspect.ex", "week_based?", None),
        ("lib/tempo/rrule/selection.ex", "week_calendar?", None),
        ("lib/math.ex", "week_axis?", None),
        ("lib/operations.ex", "year_of_weeks?", None),
        ("lib/tempo.ex", "every_week_follows?", None),
        ("lib/compare.ex", "same_axis?", None),
        ("lib/tempo/unit_values.ex", "month_of_year?", None),
        ("lib/enumeration/zone.ex", "calendar_of_weeks", None),
        ("lib/tempo.ex", "date_units", "Tempo"),
        ("lib/iso8601/group.ex", "calendar_week", None),
        ("lib/tempo/unit_values.ex", "calendar_weeks_in_year", None),
        ("lib/tempo/unit_values.ex", "iso_weeks_in_year", "UnitValues"),
        ("lib/tempo/unit_values.ex", "date_from_iso_week", "UnitValues"),
    ]),
    ("A composite calendar, and one that steps its own dates", [
        ("lib/tempo/unit_values.ex", "composite?", None),
        ("lib/tempo/unit_values.ex", "stepped_by_calendar?", "UnitValues"),
        ("lib/math.ex", "stepped_by_its_calendar?", None),
    ]),
    ("A year that begins on another day than the first of its first month", [
        ("lib/tempo/unit_values.ex", "year_begins_with_first_month?", "UnitValues"),
        ("lib/tempo/unit_values.ex", "years_begin_with_first_month?", "UnitValues"),
        ("lib/tempo/unit_values.ex", "year_start", None),
        ("lib/tempo/unit_values.ex", "first_day_of_first_month?", None),
        ("lib/compare.ex", "fields_in_day_order?", None),
        ("lib/tempo/unit_values.ex", "first_date", "UnitValues"),
        ("lib/tempo/unit_values.ex", "start_date", "UnitValues"),
        ("lib/tempo/unit_values.ex", "with_first_month", "UnitValues"),
        ("lib/tempo/unit_values.ex", "with_first_day", "UnitValues"),
        ("lib/validation.ex", "first_day_of_year", None),
    ]),
    ("A month or a day named otherwise than by its field", [
        ("lib/tempo/unit_values.ex", "month_named_once?", "UnitValues"),
        ("lib/tempo/unit_values.ex", "year_named_by_its_months?", "UnitValues"),
        ("lib/tempo/unit_values.ex", "named_date", "UnitValues"),
        ("lib/tempo/unit_values.ex", "named_day", "UnitValues"),
        ("lib/explain.ex", "named_day", None),
        ("lib/explain.ex", "named_once?", None),
    ]),
    ("A calendar with traditional (lunisolar) months", [
        ("lib/math.ex", "traditional_months?", None),
    ]),
    ("The Gregorian calendar, by its name or its CLDR type", [
        ("lib/tempo/format.ex", "worded_as_gregorian?", None),
        ("lib/explain.ex", "gregorian_names?", None),
        ("lib/inspect.ex", "reads_as_gregorian?", None),
        ("lib/inspect.ex", "names?", None),
        ("lib/tempo/rrule/rule.ex", "moves_a_day?", None),
        ("lib/tempo.ex", "kind_of_year", None),
        ("lib/enumeration/zone.ex", "in_gregorian", "Zone"),
        ("lib/enumeration/zone.ex", "in_calendar_of", "Zone"),
        ("lib/tempo.ex", "day_in_calendar", None),
    ]),
    ("A calendar with a year 0", [
        ("lib/tempo/unit_values.ex", "year?", "UnitValues"),
    ]),
    ("No calendar given, and `Calendar.ISO`", [
        ("lib/compare.ex", "effective_calendar", "Compare"),
        ("lib/tempo.ex", "calendar_module?", None),
        ("lib/validation.ex", "reading_calendar", None),
        ("lib/validation.ex", "written_calendar", None),
        ("lib/tempo.ex", "native_calendar", None),
        ("lib/tempo.ex", "calendar_iso_as_gregorian", None),
        ("lib/validation.ex", "gregorian_for_iso", None),
        ("lib/tempo.ex", "placing_calendar", None),
    ]),
    ("What a calendar exports", [
        ("lib/tempo/unit_values.ex", "exported?", None),
    ]),
])

STATIC_FAMILIES = ["Calendrical", "Localize", "Astro", "Calendar", "Date", "NaiveDateTime",
                   "DateTime", "Time"]

DATE_NUMBERS = {"7", "12", "13", "28", "29", "30", "31", "52", "53", "354", "355", "365", "366", "400",
                "146097", "1461", "36524"}
CLOCK_NUMBERS = {"23", "24", "59", "60", "1440", "1_440", "3600", "3_600", "86400", "86_400"}

DOC_OPEN = re.compile(r'^\s*@(doc|moduledoc|typedoc)\s+(~[sS])?"""')
DEFINITION = re.compile(r"^\s*(def|defp|defmacro|defmacrop|defguard|defguardp)\s+([a-z_][A-Za-z0-9_]*[?!]?)")
ALIAS_ONE = re.compile(r"^\s*alias\s+([A-Z][\w.]*)(?:\s*,\s*as:\s*([A-Z]\w*))?\s*$")
ALIAS_MANY = re.compile(r"^\s*alias\s+([A-Z][\w.]*)\.\{([^}]*)\}")
DYNAMIC = re.compile(r"(?<![\w.:@&])([a-z_][A-Za-z0-9_]*)\.([a-z_][A-Za-z0-9_]*[?!]?)\(")
ON_RESULT = re.compile(r"([a-z_][A-Za-z0-9_]*)\(([^()]*)\)\.([a-z_][A-Za-z0-9_]*[?!]?)\(")
CAPTURE = re.compile(r"&([a-z_][A-Za-z0-9_]*)\.([a-z_][A-Za-z0-9_]*[?!]?)/(\d+)")
STATIC = re.compile(r"(?<![\w.])((?:[A-Z][A-Za-z0-9_]*\.)+)([a-z_][A-Za-z0-9_]*[?!]?)\s*\(")
STATIC_CAPTURE = re.compile(r"&((?:[A-Z][A-Za-z0-9_]*\.)+)([a-z_][A-Za-z0-9_]*[?!]?)/(\d+)")
MODULE = re.compile(r"(?<![\w.:])((?:[A-Z][A-Za-z0-9_]*)(?:\.[A-Z][A-Za-z0-9_]*)*)")
ERLANG = re.compile(r"(?<![\w]):calendar\.([a-z_][A-Za-z0-9_]*)\(")
PROBE = re.compile(r"\b(function_exported\?|exported\?)\(\s*([a-z_]\w*)\s*,\s*(:?[a-z_][A-Za-z0-9_]*[?!]?)\s*,\s*(\d+)")
APPLY = re.compile(r"(?<![\w.])apply\(")
NUMBER = re.compile(r"(?<![A-Za-z_@:?&$\d])(\d[\d_]*)(\.\d[\d_]*)?(?![A-Za-z_\d])")


def source_files():
    found = []
    for directory, _dirs, names in os.walk(os.path.join(ROOT, "lib")):
        for name in names:
            if name.endswith(".ex"):
                found.append(os.path.join(directory, name))
    return sorted(found)


def classify(lines):
    """`code`, `comment`, `doc` or `blank` for each line."""
    kinds, in_doc, in_string = [], False, False
    for line in lines:
        stripped = line.strip()
        if in_doc:
            kinds.append("doc")
            in_doc = not stripped.startswith('"""')
        elif in_string:
            kinds.append("code")
            in_string = not stripped.startswith('"""')
        elif DOC_OPEN.match(line):
            kinds.append("doc")
            in_doc = True
        elif stripped == "":
            kinds.append("blank")
        elif stripped.startswith("#"):
            kinds.append("comment")
        elif stripped.startswith(("@doc ", "@moduledoc ", "@typedoc ")):
            kinds.append("doc")
        else:
            kinds.append("code")
            in_string = line.count('"""') % 2 == 1
    return kinds


def aliases(lines, kinds):
    table = {}
    for line, kind in zip(lines, kinds):
        if kind != "code":
            continue
        many = ALIAS_MANY.match(line)
        one = ALIAS_ONE.match(line)
        if many:
            for part in many.group(2).split(","):
                part = part.strip()
                if part:
                    table[part.split(".")[-1]] = many.group(1) + "." + part
        elif one:
            table[one.group(2) or one.group(1).split(".")[-1]] = one.group(1)
    return table


def resolve(module, table):
    head, _, rest = module.partition(".")
    if head in table:
        return table[head] + ("." + rest if rest else "")
    return module


def without_strings(line):
    """The line with the insides of its strings blanked and a trailing comment
    cut, so a name in a message is not taken for code. Interpolations stay."""
    result, i, in_string, depth = [], 0, False, 0
    while i < len(line):
        ch = line[i]
        if not in_string:
            if ch == "#" and (i == 0 or line[i - 1] in " \t"):
                break
            in_string = ch == '"'
            result.append(ch)
        elif depth == 0:
            if ch == "\\":
                result.append("  ")
                i += 1
            elif ch == '"':
                in_string = False
                result.append(ch)
            elif line[i:i + 2] == "#{":
                depth = 1
                result.append("#{")
                i += 1
            else:
                result.append(" ")
        else:
            depth += {"{": 1, "}": -1}.get(ch, 0)
            result.append(ch)
        i += 1
    return "".join(result)


def arity(text):
    """The count of the arguments of a call, from the text after its `(`."""
    depth, count, seen = 0, 0, False
    for ch in text:
        if ch in "([{":
            depth += 1
            seen = True
        elif ch in ")]}":
            if depth == 0:
                return count + 1 if seen else 0
            depth -= 1
        elif ch == "," and depth == 0:
            count += 1
        elif not ch.isspace():
            seen = True
    return count + 1 if seen else 0


def status(name, count):
    if (name, count) in CALENDAR:
        return "`Calendar`, required"
    if (name, count) in CALENDRICAL_REQUIRED:
        return "`Calendrical`, required"
    if (name, count) in CALENDRICAL_OPTIONAL:
        return "`Calendrical`, optional"
    return "declared by neither"


def site(relative, number):
    return f"`{relative[4:]}:{number}`"


def sites(rows):
    return ", ".join(site(relative, number) for relative, number in rows)


def read():
    census = collections.defaultdict(list)
    lines_of = collections.Counter()
    for path in source_files():
        relative = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        lines = text.split("\n")
        kinds = classify(lines)
        table = aliases(lines, kinds)
        offsets, total = [], 0
        for line in lines:
            offsets.append(total)
            total += len(line) + 1
        current = None
        for number, (line, kind) in enumerate(zip(lines, kinds), start=1):
            lines_of[kind] += 1
            if kind != "code":
                continue
            definition = DEFINITION.match(line)
            if definition:
                current = definition.group(2)
            code = without_strings(line)
            rest = lambda match: text[offsets[number - 1] + match.end():offsets[number - 1] + match.end() + 2000]
            for match in DYNAMIC.finditer(code):
                if match.group(1) == "calendar":
                    census["dynamic"].append((relative, number, current, match.group(2), arity(rest(match))))
                else:
                    census["other receivers"].append((relative, number, match.group(1), match.group(2)))
            for match in ON_RESULT.finditer(code):
                if "calendar" in match.group(1):
                    census["dynamic"].append((relative, number, current, match.group(3), arity(rest(match))))
            for match in CAPTURE.finditer(code):
                if match.group(1) == "calendar":
                    census["dynamic"].append((relative, number, current, match.group(2), int(match.group(3))))
            for match in list(STATIC.finditer(code)) + list(STATIC_CAPTURE.finditer(code)):
                module = resolve(match.group(1).rstrip("."), table)
                name = match.group(2)
                if match.re is STATIC and name == "t":
                    continue
                census["static"].append((relative, number, current, module, name))
            for match in ERLANG.finditer(code):
                census["erlang"].append((relative, number, current, match.group(1)))
            for match in PROBE.finditer(code):
                census["probes"].append((relative, number, current, match.group(2), match.group(3), int(match.group(4))))
            if APPLY.search(code) and not re.match(r"^\s*(def|defp|@spec)\s", line):
                census["apply"].append((relative, number, current))
            if not re.match(r"^\s*(alias|import|require|use)\s", line):
                named = sorted({CALENDARS[resolve(m.group(1), table)] for m in MODULE.finditer(code)
                                if resolve(m.group(1), table) in CALENDARS})
                if named:
                    census["named"].append((relative, number, current, named))
            numbers = []
            for match in NUMBER.finditer(code):
                start = match.start()
                tuple_index = start > 0 and code[start - 1] == "." and (start < 2 or code[start - 2] != ".")
                if not match.group(2) and not tuple_index:
                    numbers.append(match.group(1))
            if set(numbers) & DATE_NUMBERS:
                census["numbers"].append((relative, number, current, sorted(set(numbers) & DATE_NUMBERS, key=int)))
            elif set(numbers) & CLOCK_NUMBERS:
                census["clock numbers"].append((relative, number))
            if not re.match(r"^\s*@spec\s", line):
                for deciders in DECIDERS.values():
                    for home, name, qualifier in deciders:
                        key = (home, name)
                        bare = re.search(r"(?<![\w?!.])" + re.escape(name) + r"(?=\(|/\d)", code)
                        if relative == home and bare:
                            defined = definition is not None and definition.group(2) == name
                            census["defined" if defined else "called"].append((relative, number, key))
                        elif qualifier and re.search(r"(?<![\w.])" + qualifier + r"\." + re.escape(name) + r"(?=\(|/\d)", code):
                            census["called"].append((relative, number, key))
    census["lines"] = lines_of
    census["files"] = len(source_files())
    return census


def read_classes(read, rows):
    """The class of each row: the first entry read for its file, not yet
    taken, whose function and content are the row's."""
    remaining = {file: list(entries) for file, entries in read.items()}
    classes = {}
    for relative, number, function, found in rows:
        key = (function or "", ", ".join(found))
        entries = remaining.get(relative, [])
        match = next((entry for entry in entries if (entry[0], entry[1]) == key), None)
        if match:
            entries.remove(match)
        classes[(relative, number)] = match[2] if match else "unread"
    return classes


def table(header, rows):
    out = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    out += ["| " + " | ".join(str(cell) for cell in row) + " |" for row in rows]
    return "\n".join(out)


def write(census):
    lines_of = census["lines"]
    dynamic, named, probes = census["dynamic"], census["named"], census["probes"]
    static = [row for row in census["static"] if row[3].split(".")[0] in STATIC_FAMILIES]
    out = []
    emit = out.append

    emit("# Calendar surface census")
    emit("")
    emit(f"**Status:** reference, 2026-10-10")
    emit("")
    emit("Every place Tempo's implementation touches a calendar, in the tree this file is committed with, written by `scripts/calendar_census.py`. It is the evidence for [calendar-surface.md](calendar-surface.md), which is the plan and holds the counts of the first census, at `254923c`; this file tracks no work. Nothing here is sampled: the script reads every file of `lib/` and writes every match, and a table is regenerated by running it again.")
    emit("")
    emit("## What was read, and how")
    emit("")
    emit(f"* **{census['files']} files of `lib/`** — {sum(lines_of.values()):,} lines: {lines_of['code']:,} of code, {lines_of['doc']:,} of documentation (`@doc`, `@moduledoc` and `@typedoc`, doctests among them), {lines_of['comment']:,} of comment and {lines_of['blank']:,} blank. Only code is counted below: a calendar named in a doctest or a comment is no code path.")
    emit("")
    emit("* **A call on a calendar** — every `receiver.function(` whose receiver is a variable, every `&receiver.function/arity` and every call on the result of a call. The receiver of every one is `calendar`, `backend`, `resolver`, `clock()` or `database()`; the first is a calendar, and the others are not.")
    emit("")
    emit("* **A calendar named** — every module name in a line of code, with the file's aliases resolved, that is one of `Calendar.ISO`, `Calendrical.Gregorian`, `Calendrical.ISOWeek` and `Calendrical.Chinese`. No other calendar module is named in code.")
    emit("")
    emit("* **A probe** — every `function_exported?/3`, and every call of `Tempo.UnitValues`' private `exported?/3`, which is the same question.")
    emit("")
    emit("* **A decider** — a function that answers by what kind of calendar it is given. They were found by reading every predicate whose head names a calendar (64), every line that names a calendar and every probe, and each is listed with where it is defined and every call of it.")
    emit("")
    emit(f"* **Two columns are a reading** — the class of a line that names a calendar and of a line that holds a calendar number were read a line at a time, first at `{READ_AT}`. One the script finds with no reading is written `unread`.")
    emit("")

    named_class = read_classes(NAMED, named)
    number_class = read_classes(NUMBERS, [row for row in census["numbers"] if row[0] != "lib/tempo/leap_seconds.ex"])
    by_class = collections.Counter(named_class.values())
    mentions = sum(len(c) for _r, _n, _f, c in named)
    by_calendar = collections.Counter(c for _r, _n, _f, cs in named for c in cs)
    functions = collections.Counter((name, count) for _r, _n, _f, name, count in dynamic)
    neither = sorted(f"`{n}/{a}`" for (n, a) in functions if status(n, a) == "declared by neither")
    optional = sorted(f"`{n}/{a}`" for (n, a) in functions if status(n, a) == "`Calendrical`, optional")
    probed = collections.Counter((name.lstrip(":"), count) for _r, _n, _f, receiver, name, count in probes if receiver == "calendar")
    called = collections.Counter(key for _r, _n, key in census["called"])
    defined = collections.Counter(key for _r, _n, key in census["defined"])

    emit("## The counts")
    emit("")
    emit(table(["What", "Count"], [
        ["Calls on a calendar", f"{len(dynamic)} calls of {len(functions)} functions"],
        ["Of those functions, declared by neither behaviour", f"{len(neither)}: {', '.join(neither)}"],
        ["Of those functions, optional in `Calendrical`", f"{len(optional)}: {', '.join(optional)}"],
        ["Probes of what a calendar exports", f"{sum(probed.values())} probes of {len(probed)} functions"],
        ["Lines of code that name a calendar", f"{len(named)} lines, {mentions} names"],
        ["Calendars named", ", ".join(f"{name} {count}" for name, count in by_calendar.most_common())],
        ["Deciders by a calendar's kind", f"{len(defined)} functions defined, called at {sum(called.values())} places"],
        ["Calls into Calendrical's own modules", str(sum(1 for row in static if row[3].startswith("Calendrical")))],
        ["Calls into Elixir's `Date`, `NaiveDateTime`, `DateTime` and `Time`", str(sum(1 for row in static if row[3].split(".")[0] in ("Date", "NaiveDateTime", "DateTime", "Time")))],
        ["Calls into Erlang's `:calendar`", str(len(census["erlang"]))],
        ["Lines that hold a number a calendar would be asked for", str(len(census["numbers"]))],
        ["Lines that hold only a number of the clock (24, 60, 3,600, 86,400)", str(len(census["clock numbers"]))],
    ]))
    emit("")

    emit("## 1. Calendars named in code")
    emit("")
    emit(f"{len(named)} lines name a calendar module, and {mentions} names are on them, a line that names two calendars counting two. Each line has one class:")
    emit("")
    for code, meaning in NAMED_CLASSES.items():
        emit(f"* **{code}** ({by_class[code]}) — {meaning}")
        emit("")
    if by_class["unread"]:
        emit(f"* **unread** ({by_class['unread']}) — found since the reading at `{READ_AT}`.")
        emit("")
    emit(table(["Line", "In", "Names", "Class"], [
        [site(r, n), f"`{f}`" if f else "the module", ", ".join(cs), named_class[(r, n)]]
        for r, n, f, cs in named]))
    emit("")

    emit("## 2. Probes of what a calendar exports")
    emit("")
    emit(f"{sum(probed.values())} places ask whether a calendar exports a function before calling it, for {len(probed)} functions. A probe of a required callback answers `true` for every calendar that keeps the behaviour, and a probe of a function neither behaviour declares is the only contract that function has.")
    emit("")
    emit(table(["Function", "Declared", "Probes", "Lines"], [
        [f"`{name}/{count}`", status(name, count) if name != "division" else "the name is a variable: a division of a year",
         total, sites([(r, n) for r, n, _f, receiver, probe, c in probes if receiver == "calendar" and probe.lstrip(":") == name and c == count])]
        for (name, count), total in sorted(probed.items(), key=lambda item: (status(*item[0]), item[0]))]))
    emit("")
    others = [(r, n) for r, n, _f, receiver, _p, _c in probes if receiver != "calendar"]
    emit(f"One more probe is of no calendar: {sites(others)}, of a set-operation backend. One call is made by `apply/3` on a calendar, with the function in a variable: {sites([(r, n) for r, n, _f in census['apply']])}.")
    emit("")

    emit("## 3. Calls on a calendar")
    emit("")
    emit(f"{len(dynamic)} calls, of {len(functions)} functions at the arities shown. \"Declared\" is where the function is a callback: of Elixir's `Calendar` behaviour (1.20.4, 28 callbacks, all required) or of the `Calendrical` behaviour at Calendrical `43006d7` (36 callbacks, 10 of them optional).")
    emit("")
    emit(table(["Function", "Declared", "Calls", "Lines"], [
        [f"`{name}/{count}`", status(name, count), total,
         sites([(r, n) for r, n, _f, called_name, c in dynamic if called_name == name and c == count])]
        for (name, count), total in sorted(functions.items(), key=lambda item: (-item[1], item[0]))]))
    emit("")

    emit("## 4. Functions that decide by a calendar's kind")
    emit("")
    emit(f"{len(defined)} functions, defined in {sum(defined.values())} clauses and called at {sum(called.values())} places. A call of one is a place where what Tempo does depends on which calendar it holds.")
    emit("")
    for heading, deciders in DECIDERS.items():
        emit(f"### {heading}")
        emit("")
        emit(table(["Function", "Defined", "Calls", "Called at"], [
            [f"`{name}`", sites(sorted({(r, n) for r, n, d in census["defined"] if d == (home, name)})) or "not found",
             called[(home, name)], sites([(r, n) for r, n, c in census["called"] if c == (home, name)]) or "none"]
            for home, name, _qualifier in deciders]))
        emit("")
    base = [(r, n, f) for r, n, f, name, _c in dynamic if name == "calendar_base"]
    emit("### `calendar_base/0`, asked directly")
    emit("")
    emit(f"The {len(base)} calls of `calendar.calendar_base()` are in section 3. Each is a branch between a calendar of weeks and one of months, in: {', '.join(sorted({f'`{f}`' for _r, _n, f in base}))}.")
    emit("")

    emit("## 5. Calls into Calendrical, Localize and Astro")
    emit("")
    emit("Calls of a function of a named module, which take the calendar as an argument or need none. A call on `Calendrical.Gregorian`, `Calendrical.ISOWeek` or `Calendrical.Chinese` is a call on a calendar by its name, and is in section 1 as well.")
    emit("")
    for family in ["Calendrical", "Localize", "Astro"]:
        rows = collections.defaultdict(list)
        for r, n, _f, module, name in static:
            if module.split(".")[0] == family:
                rows[(module, name)].append((r, n))
        emit(f"### {family}")
        emit("")
        emit(table(["Function", "Calls", "Lines"], [
            [f"`{module}.{name}`", len(where), sites(where)] for (module, name), where in sorted(rows.items())]))
        emit("")

    emit("## 6. Calls into Elixir's and Erlang's own calendar types")
    emit("")
    emit("A `Date` is of the calendar it is given, so `Date.new/4`, `Date.convert/2` and `Date.diff/2` are calls on a calendar through Elixir. Erlang's `:calendar` is Gregorian, and counts no year before 0.")
    emit("")
    rows = collections.defaultdict(list)
    for r, n, _f, module, name in static:
        if module.split(".")[0] in ("Calendar", "Date", "NaiveDateTime", "DateTime", "Time"):
            rows[(module, name)].append((r, n))
    for r, n, _f, name in census["erlang"]:
        rows[(":calendar", name)].append((r, n))
    emit(table(["Function", "Calls", "Lines"], [
        [f"`{module}.{name}`", len(where), sites(where)] for (module, name), where in sorted(rows.items())]))
    emit("")

    emit("## 7. Numbers a calendar would be asked for")
    emit("")
    numbers = census["numbers"]
    by_number_class = collections.Counter(
        "leap seconds" if r == "lib/tempo/leap_seconds.ex" else number_class[(r, n)]
        for r, n, _f, _found in numbers)
    emit(f"{len(numbers)} lines of code hold one of 7, 12, 13, 28 to 31, 52, 53, 354, 355, 365, 366, 400, 1,461, 36,524 or 146,097. {len(census['clock numbers'])} more hold only a number of the clock, which no calendar Tempo is given counts otherwise, and are not listed. Each line has one class:")
    emit("")
    for name, meaning in NUMBER_CLASSES.items():
        emit(f"* **{name}** ({by_number_class[name]}) — {meaning}")
        emit("")
    if by_number_class["unread"]:
        emit(f"* **unread** ({by_number_class['unread']}) — found since the reading at `{READ_AT}`.")
        emit("")
    emit(table(["Line", "In", "Holds", "Class"], [
        [site(r, n), f"`{f}`" if f else "the module", ", ".join(found), number_class[(r, n)]]
        for r, n, f, found in numbers if r != "lib/tempo/leap_seconds.ex"]))
    emit("")
    leap = [(r, n) for r, n, _f, _found in numbers if r == "lib/tempo/leap_seconds.ex"]
    emit(f"The {len(leap)} lines of `lib/tempo/leap_seconds.ex` are its table, lines {leap[0][1]} to {leap[-1][1]}.")
    emit("")
    return "\n".join(out)


if __name__ == "__main__":
    print(write(read()))
