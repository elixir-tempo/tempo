import Config

# `Tz.TimeZoneDatabase` is installed as the process-wide
# `Calendar` time-zone database in dev and test so:
#
#   * iCal 2.0's DTSTART/DTEND parsing resolves TZID parameters
#     (otherwise the event's datetime fields come through as `nil`);
#
#   * `DateTime.shift_zone/2` and friends work against named IANA
#     zones in iex sessions without the caller having to pass a
#     database explicitly.
#
# An application needs no such line for Tempo itself, which asks `tz`
# where nothing is configured (decision 77); it may configure any
# `Calendar.TimeZoneDatabase` implementation (`:tz`, `:tzdata`,
# `:time_zone_info`, `:zoneinfo`) here or under `:ex_tempo`.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
