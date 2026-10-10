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

# The callbacks of the `Calendrical` behaviour at Calendrical `06aa274`.
CALENDRICAL_REQUIRED = {
    ("calendar_base", 0), ("calendar_year", 3), ("cardinal_day", 3), ("cardinal_month", 1),
    ("cldr_calendar_type", 0), ("cyclic_year", 3), ("date_from_day_of_year", 2),
    ("date_from_iso_days", 1), ("date_to_iso_days", 3), ("dates_in_gregorian_year", 3),
    ("day_numbers", 2), ("days_in_month", 1), ("days_in_week", 0), ("days_in_year", 1),
    ("diff", 3), ("era_calendar_type", 0), ("extended_year", 3), ("iso_week_of_year", 3),
    ("leap_month", 1), ("lunar_month_of_year", 2), ("month", 2), ("month_numbers", 1),
    ("month_of_year", 3), ("month_week", 3), ("months_in_year", 0), ("named_month", 2),
    ("numeric_month", 3), ("ordinal_month_from_traditional", 2), ("parsing_calendar", 0),
    ("plus", 6), ("quadrimester", 2), ("quarter", 2), ("related_gregorian_year", 3),
    ("semester", 2), ("solar_term", 2), ("traditional_leap_month", 1),
    ("traditional_months", 1), ("week", 2), ("week_of_month", 3), ("week_of_year", 3),
    ("weeks_in_month", 2), ("weeks_in_year", 1), ("year", 1), ("years_in_cycle", 0),
}
CALENDRICAL_OPTIONAL = {
    ("calendar_from_cldr_calendar_type", 1), ("cldr_calendar_type", 3),
    ("months_in_leap_year", 0), ("parsing_calendars", 0),
}

# The one module that may name a calendar (`plans/calendar-surface.md`).
ONE_MODULE = "lib/tempo/calendars.ex"

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
    "lib/enumeration/zone.ex": [
        ('calendar_of_weeks', 'Gregorian, ISOWeek', 'W'),
    ],
    "lib/math.ex": [
        ('weeks_by_the_calendar', 'Gregorian', 'W'),
    ],
    "lib/tempo.ex": [
        ('names_no_date_of_any_year?', 'Gregorian', 'S'),
        ('kind_of_year', 'Gregorian', 'G'),
        ('no_date_in_year?', 'Gregorian', 'G'),
        ('no_date_in_year?', 'Gregorian', 'G'),
    ],
    "lib/tempo/network/normalize.ex": [
        ('axis', 'Gregorian', 'S'),
        ('axis', 'Gregorian', 'S'),
        ('cyclic?', 'Gregorian', 'S'),
        ('cyclic?', 'Gregorian', 'S'),
        ('gregorian_cycle', 'Gregorian', 'G'),
        ('gregorian_cycle', 'Gregorian', 'G'),
    ],
    "lib/tempo/unit_values.ex": [
        ('date_from_iso_week', 'Gregorian', 'W'),
        ('date_from_iso_week', 'ISOWeek', 'W'),
        ('date_from_iso_week', 'Gregorian', 'W'),
        ('iso_weeks_in_year', 'Gregorian', 'W'),
        ('iso_weeks_in_year', 'ISOWeek', 'W'),
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
    ],
    "lib/jscalendar.ex": [
        ('skip', '7', 'standard'),
    ],
    "lib/tempo.ex": [
        ('month_and_day', '12, 31', 'reader'),
        ('walk_too_long_error', '400', 'gregorian'),
        ('walk_too_long_error', '12', 'gregorian'),
        ('moved_by_its_zone', '30', 'zone'),
        ('moved_by_its_zone', '366', 'zone'),
        ('no_date_in_year?', '12, 31', 'gregorian'),
        ('cadence_index', '12', 'gregorian'),
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
        ('push_wkst', '7', 'standard'),
    ],
    "lib/tempo/rrule/selection.ex": [
        ('application_order_key', '7', 'prose'),
        ('nearest_weekday', '7', 'standard'),
        ('snap_back_to_weekday', '7', 'standard'),
    ],
    "lib/tempo/time_zone_database.ex": [
        ('days_of', '365', 'zone'),
        ('clear_in_blocks?', '366', 'zone'),
    ],
    "lib/tempo/workdays.ex": [
        ('', '7', 'standard'),
    ],
}

CONSTANT_CLASSES = collections.OrderedDict([
    ("calendar", "What a calendar would answer, or a calendar named. To go."),
    ("units", "Tempo's own units, their order and the places they are written in."),
    ("clock", "ISO 8601's time of day: the hours of a day, the minutes of an hour, the seconds of a minute and their fractions."),
    ("standard", "A table or a number of a notation or a standard Tempo reads or writes."),
    ("limit", "A bound Tempo sets on its own work: how much it reads, lists or walks before it stops or asks."),
    ("zone", "A bound or a margin on what the zone database is asked, whose dates are Gregorian."),
    ("relations", "Allen's relations and the network's, and the tables that compose them."),
    ("options", "The names of options a function takes."),
    ("names", "The names Tempo selects by: its events, and the words for ISO 8601-2's seasons."),
    ("asked", "Built from what Calendrical answers when Tempo is compiled."),
    ("text", "A string Tempo writes."),
    ("key", "A key Tempo keeps something under."),
    ("the one module", "The calendar of the notation, in the one module that may name it."),
])

# Every constant Tempo defines (a module attribute that is not a doc, a spec
# or a directive), by its file and its name, in the order of the file, with
# the class it was read as.
CONSTANTS = {
    "lib/compare.ex": [
        ('unit_levels', 'units'), ('a_day_or_so', 'zone'), ('gregorian_seconds_year_1', 'zone'),
    ],
    "lib/enumeration.ex": [
        ('significant_digits_limit', 'limit'), ('listed_at_once', 'limit'),
        ('read_ahead', 'limit'), ('fixed_extent_units', 'units'), ('finest_precision', 'clock'),
    ],
    "lib/enumeration/skipped_readings.ex": [
        ('seconds_in', 'clock'), ('years_asked', 'zone'), ('margin', 'zone'),
    ],
    "lib/enumeration/zone.ex": [
        ('seconds_in_an_hour', 'clock'), ('a_day_or_so', 'zone'), ('seconds_in_a_day', 'clock'),
        ('clear_of_a_change', 'zone'),
    ],
    "lib/event.ex": [
        ('solar_terms', 'asked'), ('events', 'names'),
    ],
    "lib/explain.ex": [
        ('times_named', 'limit'), ('half_open', 'text'), ('headline_units', 'units'),
        ('headline_date_units', 'units'), ('precisions', 'units'), ('written_order', 'units'),
        ('date_units', 'units'), ('season_names', 'names'),
    ],
    "lib/ical.ex": [
        ('safety_cap', 'limit'),
    ],
    "lib/inspect.ex": [
        ('from_iso8601', 'text'), ('sigil_o', 'text'),
    ],
    "lib/iso8601/ast.ex": [
        ('date_resolution_order', 'units'),
    ],
    "lib/iso8601/group.ex": [
        ('hours_per_day', 'clock'), ('divisions', 'standard'), ('most_divisions', 'limit'),
    ],
    "lib/iso8601/parser.ex": [
        ('most_durations_in_a_range', 'limit'), ('measured_seconds', 'clock'),
        ('selected_by', 'units'), ('resolution_order', 'units'), ('qualifiers', 'standard'),
    ],
    "lib/iso8601/tokenizer.ex": [
        ('max_input_bytes', 'limit'), ('max_nesting_depth', 'limit'),
        ('max_selection_depth', 'limit'), ('max_digits', 'limit'), ('profiles', 'standard'),
    ],
    "lib/iso8601/tokenizer/extended.ex": [
        ('empty_extended', 'standard'), ('u_ca', 'text'),
    ],
    "lib/iso8601/tokenizer/grammar.ex": [
        ('endpoint_tags', 'standard'), ('endpoint_units', 'units'), ('bare_numbers', 'standard'),
        ('two_digit_units', 'units'), ('time_units', 'units'),
    ],
    "lib/iso8601/tokenizer/helpers.ex": [
        ('qualified_from_the_left', 'units'),
    ],
    "lib/iso8601/tokenizer/memo.ex": [
        ('table', 'key'),
    ],
    "lib/iso8601/tokenizer/plain.ex": [
        ('date_designators', 'standard'), ('time_designators', 'standard'),
        ('most_digits', 'limit'),
    ],
    "lib/iso8601/unit.ex": [
        ('sort_keys', 'units'), ('unit_after', 'units'), ('value_ranges', 'units'),
        ('units', 'units'),
    ],
    "lib/jscalendar.ex": [
        ('weekdays', 'standard'),
    ],
    "lib/math.ex": [
        ('clock_units', 'units'), ('fixed_zones', 'zone'), ('unit_depth', 'units'),
        ('hours_per_day', 'clock'), ('minutes_per_hour', 'clock'), ('seconds_per_minute', 'clock'),
        ('duration_units_coarse_to_fine', 'units'), ('maskable_units', 'units'),
        ('unit_order_coarse_to_fine', 'units'), ('calendar_units', 'units'),
        ('counted_units', 'units'), ('microseconds_per_second', 'clock'),
        ('seconds_in_day', 'clock'),
    ],
    "lib/rounding.ex": [
        ('microseconds', 'clock'), ('day', 'clock'), ('day_units', 'units'),
    ],
    "lib/sigil.ex": [
        ('modifier_to_unit', 'standard'), ('gregorian_axis', 'units'), ('iso_week_axis', 'units'),
        ('ordinal_axis', 'units'), ('season_axis', 'units'),
    ],
    "lib/split.ex": [
        ('clock_units', 'units'), ('positions', 'units'),
    ],
    "lib/tempo.ex": [
        ('canonical_unit_order', 'units'), ('week_axis_units', 'units'),
        ('gregorian_axis_units', 'units'), ('known_options', 'options'),
        ('qualification_values', 'standard'), ('unit_order', 'units'), ('gregorian_only', 'units'),
        ('week_only', 'units'), ('ordinal_only', 'units'), ('day_parts', 'units'),
        ('shift_units', 'units'), ('spans_at_once', 'limit'), ('occurrence_horizon', 'limit'),
        ('most_periods_passed_over', 'limit'), ('most_periods_reaching', 'limit'),
        ('recurrence_safety_cap', 'limit'), ('names_a_date', 'units'), ('names_no_date', 'units'),
        ('time_of_day', 'units'), ('years_of_a_cycle', 'calendar'),
        ('periods_before_asking', 'calendar'), ('months_of_a_cycle', 'calendar'),
        ('places_in_a_week', 'units'), ('places_finer_than', 'units'), ('seconds_in', 'clock'),
        ('years_of_changes_asked', 'zone'), ('seconds_of_changes_asked', 'zone'),
        ('kinds_of_year', 'calendar'), ('longest_run_before_asking', 'limit'),
        ('seconds_in', 'clock'), ('periods_worth_passing_over', 'limit'),
        ('steps_put_right', 'limit'), ('no_step', 'units'), ('rolls', 'standard'),
        ('most_days_off_in_a_row', 'limit'), ('valid_units', 'units'),
    ],
    "lib/tempo/allen.ex": [
        ('inverses', 'relations'), ('relations', 'relations'),
    ],
    "lib/tempo/calendars.ex": [
        ('notation', 'the one module'), ('weeks', 'the one module'),
    ],
    "lib/tempo/clock/test.ex": [
        ('process_key', 'key'),
    ],
    "lib/tempo/cron.ex": [
        ('aliases', 'standard'), ('month_names', 'standard'), ('dow_names', 'standard'),
        ('cascade_order', 'units'),
    ],
    "lib/tempo/duration.ex": [
        ('valid_units', 'units'), ('canonical_unit_order', 'units'),
        ('microsecond_seconds', 'clock'), ('day_seconds', 'clock'), ('fixed_unit_seconds', 'clock'),
        ('fixed_units', 'units'),
    ],
    "lib/tempo/exception/interval_endpoints_error.ex": [
        ('convert', 'text'),
    ],
    "lib/tempo/format.ex": [
        ('time_units', 'units'), ('relative_units', 'units'), ('one_value_units', 'units'),
        ('unit_order_ctf', 'units'),
    ],
    "lib/tempo/interval.ex": [
        ('public_new_options', 'options'), ('iteration_units', 'units'),
        ('hours_per_day', 'clock'), ('seconds_in_a_day', 'clock'), ('calendar_units', 'units'),
        ('clock_units', 'units'), ('before_relations', 'relations'),
        ('after_relations', 'relations'), ('intersecting_relations', 'relations'),
        ('within_relations', 'relations'), ('microseconds_in_a_day', 'clock'), ('microseconds_in_a_week', 'clock'), ('max_placement_pairs', 'limit'),
    ],
    "lib/tempo/interval/composition.ex": [
        ('composition', 'relations'), ('order', 'relations'),
    ],
    "lib/tempo/interval/cycle.ex": [
        ('microseconds', 'clock'), ('seconds_per_day', 'clock'),
    ],
    "lib/tempo/interval/steps.ex": [
        ('seconds_per_minute', 'clock'), ('seconds_per_hour', 'clock'),
        ('seconds_per_day', 'clock'), ('microseconds_per_second', 'clock'),
        ('max_precision', 'clock'), ('a_day_or_so', 'zone'),
    ],
    "lib/tempo/leap_seconds.ex": [
        ('leap_second_dates', 'standard'), ('leap_second_set', 'standard'),
    ],
    "lib/tempo/limit.ex": [
        ('default', 'limit'), ('values_at_once', 'limit'), ('days_off_in_a_row', 'limit'),
    ],
    "lib/tempo/microsecond.ex": [
        ('max_precision', 'clock'), ('microseconds_per_second', 'clock'),
    ],
    "lib/tempo/network/normalize.ex": [
        ('unit_order', 'units'), ('duration_units', 'units'), ('time_units', 'units'),
        ('calendar_units', 'units'), ('gregorian_cycle_start', 'calendar'),
        ('gregorian_cycle_years', 'calendar'),
    ],
    "lib/tempo/network/relation.ex": [
        ('qualitative', 'relations'), ('edges', 'relations'), ('comparisons', 'relations'),
        ('boundary_comparisons', 'relations'), ('allen', 'relations'),
    ],
    "lib/tempo/network/solver.ex": [
        ('allen_relations', 'relations'),
    ],
    "lib/tempo/network/time_period.ex": [
        ('options', 'options'), ('renamed', 'options'),
    ],
    "lib/tempo/not_built.ex": [
        ('stepped_by_rrule_calendar', 'units'),
        ('selected_by_rrule_calendar', 'units'),
    ],
    "lib/tempo/qualification.ex": [
        ('units', 'units'), ('date_units', 'units'),
    ],
    "lib/tempo/rrule.ex": [
        ('weekdays', 'standard'), ('freq_to_unit', 'standard'),
    ],
    "lib/tempo/rrule/encoder.ex": [
        ('freq_for', 'standard'), ('rrule_tokens', 'standard'), ('weekday_code', 'standard'),
        ('names_the_day', 'units'), ('times', 'units'), ('forbidden_at', 'standard'),
        ('by_parts', 'units'),
    ],
    "lib/tempo/rrule/selection.ex": [
        ('monday', 'standard'), ('weekdays_found_by_weeks', 'limit'),
        ('candidates_at_once', 'limit'), ('parts_counted_in_a_date', 'units'),
        ('places_a_day', 'units'), ('application_order', 'units'), ('application_rank', 'units'),
        ('after_every_part', 'units'), ('unit_weight', 'units'), ('held_to', 'units'),
        ('beside_a_week_of_month', 'units'), ('unit_canonical_order', 'units'),
    ],
    "lib/tempo/schedule.ex": [
        ('finish_to_start', 'relations'), ('task_options', 'options'),
    ],
    "lib/tempo/select.ex": [
        ('unit_order_coarse_to_fine', 'units'), ('most_days_off_in_a_row', 'limit'),
        ('horizon', 'limit'), ('coarseness', 'units'), ('numbered_by_calendar', 'units'),
        ('by_month', 'units'), ('gregorian_axis', 'units'),
        ('week_axis', 'units'), ('ordinal_axis', 'units'), ('date_units', 'units'),
    ],
    "lib/tempo/time_zone_database.ex": [
        ('gregorian_seconds_year_1', 'zone'), ('pre_ce_period', 'zone'),
        ('seconds_per_day', 'zone'), ('microseconds_per_day', 'zone'),
        ('microseconds_per_second', 'zone'), ('zone_probe_seconds', 'zone'),
        ('decades_scanned', 'zone'), ('half_a_day', 'zone'), ('span_asked_by_its_days', 'zone'),
        ('questions_to_find_a_block', 'zone'), ('asked_in_its_place', 'zone'),
        ('days_in_a_block', 'zone'), ('seconds_in_a_block', 'zone'),
        ('first_year_of_changes', 'zone'),
    ],
    "lib/tempo/unit_values.ex": [
        ('composite_key', 'key'), ('counted', 'units'), ('year_start_key', 'key'),
        ('any_year', 'calendar'), ('monday', 'standard'),
    ],
    "lib/validation.ex": [
        ('hours_per_day', 'clock'), ('minutes_per_hour', 'clock'), ('rounding_precision', 'limit'),
        ('clock_units', 'units'), ('units_of_days', 'units'), ('counted_from_one', 'units'),
        ('most_fractions_in_a_range', 'limit'), ('most_fraction_digits', 'limit'),
        ('fractions_shown', 'limit'), ('max_offset_minutes', 'clock'), ('shift_units', 'units'),
        ('wall_units', 'units'),
    ],
}

NOT_CONSTANTS = {
    "spec", "type", "typep", "opaque", "callback", "macrocallback", "optional_callbacks", "impl",
    "behaviour", "dialyzer", "compile", "moduledoc", "doc", "typedoc", "derive", "enforce_keys",
    "external_resource", "before_compile", "after_compile", "on_load", "on_definition",
    "deprecated", "since", "vsn", "nifs",
}
CONSTANT = re.compile(r"^\s*@([a-z_][A-Za-z0-9_]*)\s+(?!->)\S")

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
        ("lib/explain.ex", "calendar_of_months", None),
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
    ("A calendar that numbers its months by the year (a year of twelve or of thirteen)", [
        ("lib/math.ex", "months_numbered_by_the_year?", None),
    ]),
    ("The Gregorian calendar, by its name or its CLDR type", [
        ("lib/tempo/format.ex", "worded_as_gregorian?", None),
        ("lib/inspect.ex", "reads_as_gregorian?", None),
        ("lib/inspect.ex", "names?", None),
        ("lib/tempo.ex", "kind_of_year", None),
        ("lib/enumeration/zone.ex", "in_gregorian", "Zone"),
        ("lib/enumeration/zone.ex", "in_calendar_of", "Zone"),
    ]),
    ("A calendar with a year 0", [
        ("lib/tempo/unit_values.ex", "year?", "UnitValues"),
    ]),
    ("No calendar given, and `Calendar.ISO`: the one accessor and what still asks beside it", [
        ("lib/tempo/calendars.ex", "effective", "Calendars"),
        ("lib/tempo/calendars.ex", "of", "Calendars"),
        ("lib/tempo/calendars.ex", "settled", "Calendars"),
        ("lib/tempo/calendars.ex", "default", "Calendars"),
        ("lib/tempo/calendars.ex", "native", "Calendars"),
        ("lib/tempo/calendars.ex", "validated", "Calendars"),
        ("lib/tempo/calendars.ex", "is_notation", "*"),
        ("lib/tempo.ex", "with_a_calendar", "Tempo"),
        ("lib/tempo.ex", "calendar_of", None),
        ("lib/explain.ex", "calendar_of", None),
        ("lib/validation.ex", "reading_calendar", None),
        ("lib/validation.ex", "written_calendar", None),
        ("lib/tempo.ex", "native_calendar", None),
        ("lib/tempo.ex", "placing_calendar", None),
    ]),
    ("ISO 8601's week dates: the notation's calendar of weeks, in the one module", [
        ("lib/tempo/calendars.ex", "weeks", "Calendars"),
        ("lib/tempo/calendars.ex", "is_notation_weeks", "*"),
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
ON_RESULT = re.compile(r"((?:[A-Z][A-Za-z0-9_]*\.)*[a-z_][A-Za-z0-9_]*)\(([^()]*)\)\.([a-z_][A-Za-z0-9_]*[?!]?)\(")
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
            piped = lambda match: 1 if code[:match.start()].rstrip().endswith("|>") else 0
            for match in DYNAMIC.finditer(code):
                if match.group(1) == "calendar":
                    census["dynamic"].append((relative, number, current, match.group(2), arity(rest(match)) + piped(match)))
                else:
                    census["other receivers"].append((relative, number, match.group(1), match.group(2)))
            for match in ON_RESULT.finditer(code):
                if "calendar" in match.group(1) or match.group(1).startswith("Calendars."):
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
            constant = CONSTANT.match(line)
            if constant and constant.group(1) not in NOT_CONSTANTS:
                census["constants"].append((relative, number, current, [constant.group(1)]))
            if not re.match(r"^\s*(alias|import|require|use)\s", line):
                named = sorted({CALENDARS[resolve(m.group(1), table)] for m in MODULE.finditer(code)
                                if resolve(m.group(1), table) in CALENDARS})
                if named:
                    kind = "named in the one module" if relative == ONE_MODULE else "named"
                    census[kind].append((relative, number, current, named))
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
                        defined = relative == home and definition is not None and definition.group(2) == name
                        if defined:
                            census["defined"].append((relative, number, key))
                        elif (relative == home or qualifier == "*") and bare:
                            census["called"].append((relative, number, key))
                        elif qualifier and qualifier != "*" and re.search(r"(?<![\w.])" + qualifier + r"\." + re.escape(name) + r"(?=\(|/\d)", code):
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


def constant_classes(rows):
    """The class of each constant: the first reading for its file and name not yet taken."""
    remaining = {file: list(entries) for file, entries in CONSTANTS.items()}
    classes = {}
    for relative, number, _function, (name,) in rows:
        entries = remaining.get(relative, [])
        match = next((entry for entry in entries if entry[0] == name), None)
        if match:
            entries.remove(match)
        classes[(relative, number)] = match[1] if match else "unread"
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
    emit("* **A call on a calendar** — every `receiver.function(` whose receiver is a variable, every `&receiver.function/arity` and every call on the result of a call. The receiver of every one is `calendar`, a call of `Tempo.Calendars` or of a function named for a calendar, `backend`, `resolver`, `clock()` or `database()`; the first three are a calendar, and the others are not.")
    emit("")
    emit("* **A calendar named** — every module name in a line of code, with the file's aliases resolved, that is one of `Calendar.ISO`, `Calendrical.Gregorian`, `Calendrical.ISOWeek` and `Calendrical.Chinese`. No other calendar module is named in code.")
    emit("")
    emit("* **A probe** — every `function_exported?/3`, and every call of a private `exported?/3`, which is the same question (`Tempo.UnitValues` had one until its last call became a callback).")
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
        ["Constants Tempo defines", f"{len(census['constants'])}, of which {sum(1 for value in constant_classes(census['constants']).values() if value == 'calendar')} are a calendar's to answer"],
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
    one = census["named in the one module"]
    emit(f"`{ONE_MODULE[4:]}` is the one module that may name a calendar, and is not counted above. It does so on {len(one)} lines: {sites([(r, n) for r, n, _f, _c in one]) or 'none'}.")
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
    emit(f"{len(dynamic)} calls, of {len(functions)} functions at the arities shown. \"Declared\" is where the function is a callback: of Elixir's `Calendar` behaviour (1.20.4, 28 callbacks, all required) or of the `Calendrical` behaviour at Calendrical `06aa274` (48 callbacks, 4 of them optional).")
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
    emit(f"`calendar_base/0` is asked at {len(base)} place, in section 3: {', '.join(sorted({f'`{f}`' for _r, _n, f in base}))}. Every other branch between a calendar of weeks and one of months asks that function.")
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
    constants = census["constants"]
    constant_class = constant_classes(constants)
    by_constant_class = collections.Counter(constant_class.values())
    emit("## 8. Every constant Tempo defines")
    emit("")
    emit(f"{len(constants)} module attributes are constants: every one that is not a doc, a spec or a directive. Each was read, with its whole value, and has one class. A constant is a sign that Tempo holds what it could ask, so each class says why its constants are Tempo's own to hold, but for the first, whose constants are not.")
    emit("")
    for name, meaning in CONSTANT_CLASSES.items():
        emit(f"* **{name}** ({by_constant_class[name]}) — {meaning}")
        emit("")
    if by_constant_class["unread"]:
        emit(f"* **unread** ({by_constant_class['unread']}) — defined since the last reading.")
        emit("")
    flagged = [(r, n, name) for r, n, _f, (name,) in constants if constant_class[(r, n)] in ("calendar", "unread")]
    emit("### What a calendar would answer")
    emit("")
    emit(table(["Line", "Constant", "Class"], [[site(r, n), f"`@{name}`", constant_class[(r, n)]] for r, n, name in flagged]))
    emit("")
    emit("### The rest, by file")
    emit("")
    by_file = collections.OrderedDict()
    for r, n, _f, (name,) in constants:
        if constant_class[(r, n)] not in ("calendar", "unread"):
            by_file.setdefault(r, []).append(f"`@{name}` {constant_class[(r, n)]}")
    emit(table(["File", "Constants"], [[f"`{r[4:]}`", ", ".join(names)] for r, names in by_file.items()]))
    emit("")
    return "\n".join(out)


if __name__ == "__main__":
    print(write(read()))
