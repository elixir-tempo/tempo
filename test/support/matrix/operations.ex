defmodule Tempo.Matrix.Operations do
  @moduledoc """
  The operations the matrix runs: the public functions of `Tempo` that
  take a value, and the `Enumerable` and `Inspect` protocols.

  Each operation names its group, for the published matrix, and the
  contract its kind implies:

  * `:never` — it returns a value, `{:ok, value}` or `{:error, exception}`,
    and never raises.

  * `:deliberate` — a predicate, an accessor with no error to return, a bang
    function, a walk or the sorter callback may raise an exception written
    on purpose (see `Tempo.Matrix.Runner.passes?/2`).

  """

  import Tempo.Sigils

  alias Calendrical.Gregorian
  alias Calendrical.Hebrew

  @type raises :: :never | :deliberate

  @type of_one :: {String.t(), atom(), raises(), (term() -> term())}
  @type of_two :: {String.t(), atom(), raises(), (term(), term() -> term())}

  @doc """
  The operations of one value.

  ### Returns

  * A list of `{name, group, raises, function}`.

  """
  @spec unary() :: [of_one()]
  def unary do
    convert() ++ walk() ++ measure() ++ arithmetic() ++ select() ++ format() ++ parts()
  end

  @doc """
  The operations of two values.

  ### Returns

  * A list of `{name, group, raises, function}`.

  """
  @spec binary() :: [of_two()]
  def binary do
    [
      {"relation/2", :compare, :never, &Tempo.relation/2},
      {"compare/2", :compare, :deliberate, &Tempo.compare/2},
      {"overlaps?/2", :compare, :deliberate, &Tempo.overlaps?/2},
      {"contains?/2", :compare, :deliberate, &Tempo.contains?/2},
      {"within?/2", :compare, :deliberate, &Tempo.within?/2},
      {"before?/2", :compare, :deliberate, &Tempo.before?/2},
      {"after?/2", :compare, :deliberate, &Tempo.after?/2},
      {"adjacent?/2", :compare, :deliberate, &Tempo.adjacent?/2},
      {"disjoint?/2", :compare, :deliberate, &Tempo.disjoint?/2},
      {"equal?/2", :compare, :deliberate, &Tempo.equal?/2},
      {"overlap_certainty/2", :compare, :never, &Tempo.overlap_certainty/2},
      {"within_certainty/2", :compare, :never, &Tempo.within_certainty/2},
      {"relation_certainty/3", :compare, :never, &Tempo.relation_certainty(&1, &2, :precedes)},
      {"possibly_before?/2", :compare, :deliberate, &Tempo.possibly_before?/2},
      {"possibly_after?/2", :compare, :deliberate, &Tempo.possibly_after?/2},
      {"possibly_overlaps?/2", :compare, :deliberate, &Tempo.possibly_overlaps?/2},
      {"possibly_within?/2", :compare, :deliberate, &Tempo.possibly_within?/2},
      {"certainly_before?/2", :compare, :deliberate, &Tempo.certainly_before?/2},
      {"certainly_after?/2", :compare, :deliberate, &Tempo.certainly_after?/2},
      {"certainly_overlaps?/2", :compare, :deliberate, &Tempo.certainly_overlaps?/2},
      {"certainly_within?/2", :compare, :deliberate, &Tempo.certainly_within?/2},
      {"Enum.member?/2", :walk, :deliberate, &Enum.member?/2},
      {"union/2", :combine, :never, &Tempo.union/2},
      {"intersection/2", :combine, :never, &Tempo.intersection/2},
      {"difference/2", :combine, :never, &Tempo.difference/2},
      {"symmetric_difference/2", :combine, :never, &Tempo.symmetric_difference/2},
      {"complement/2", :combine, :never, &Tempo.complement(&1, within: &2)},
      {"members_overlapping/2", :combine, :never, &Tempo.members_overlapping/2},
      {"members_outside/2", :combine, :never, &Tempo.members_outside/2},
      {"members_in_exactly_one/2", :combine, :never, &Tempo.members_in_exactly_one/2},
      {"duration/2", :measure, :never, &Tempo.duration/2},
      {"duration!/2", :measure, :deliberate, &Tempo.duration!/2},
      {"at/2", :arithmetic, :never, &Tempo.at/2},
      {"on/2", :arithmetic, :never, &Tempo.on/2}
    ]
  end

  defp convert do
    [
      {"to_interval/1", :convert, :never, &Tempo.to_interval/1},
      {"to_interval/2 within", :convert, :never, &Tempo.to_interval(&1, within: ~o"2026")},
      {"to_interval!/1", :convert, :deliberate, &Tempo.to_interval!/1},
      {"to_interval_set/1", :convert, :never, &Tempo.to_interval_set/1},
      {"to_interval_set!/1", :convert, :deliberate, &Tempo.to_interval_set!/1},
      {"to_calendar/2 hebrew", :convert, :never, &Tempo.to_calendar(&1, Hebrew)},
      {"to_calendar/2 gregorian", :convert, :never, &Tempo.to_calendar(&1, Gregorian)},
      {"to_calendar!/2 hebrew", :convert, :deliberate, &Tempo.to_calendar!(&1, Hebrew)},
      {"to_calendar/2 a calendar type", :convert, :never, &Tempo.to_calendar(&1, :hebrew)},
      {"shift_zone/2", :convert, :never, &Tempo.shift_zone(&1, "America/New_York")},
      {"in_zone/2", :convert, :never, &Tempo.in_zone(&1, "Europe/Paris")},
      {"to_date/1", :convert, :never, &Tempo.to_date/1},
      {"to_time/1", :convert, :never, &Tempo.to_time/1},
      {"to_naive_datetime/1", :convert, :never, &Tempo.to_naive_datetime/1},
      {"to_datetime/1", :convert, :never, &Tempo.to_datetime/1},
      {"to_elixir/1", :convert, :never, &Tempo.to_elixir/1}
    ]
  end

  defp walk do
    [
      {"Enum.take/2", :walk, :deliberate, &Enum.take(&1, 3)},
      {"Enum.count/1", :walk, :deliberate, &Enum.count/1},
      {"Enum.at/2", :walk, :deliberate, &Enum.at(&1, 1)}
    ]
  end

  defp measure do
    [
      {"duration/1", :measure, :never, &Tempo.duration/1},
      {"bounded?/1", :measure, :deliberate, &Tempo.bounded?/1},
      {"empty?/1", :measure, :deliberate, &Tempo.empty?/1},
      {"at_least?/2", :measure, :deliberate, &Tempo.at_least?(&1, ~o"P1D")},
      {"at_most?/2", :measure, :deliberate, &Tempo.at_most?(&1, ~o"P1D")},
      {"exactly?/2", :measure, :deliberate, &Tempo.exactly?(&1, ~o"P1D")},
      {"longer_than?/2", :measure, :deliberate, &Tempo.longer_than?(&1, ~o"PT1H")},
      {"shorter_than?/2", :measure, :deliberate, &Tempo.shorter_than?(&1, ~o"PT1H")},
      {"duration/2 to a year on", :measure, :never, &duration_to_a_year_on/1}
    ]
  end

  # The time from a value to the same value a year on, in its own calendar
  # and zone: the corpus's partners are Gregorian, and a duration is counted
  # between two values of one calendar. What cannot be moved a year on is
  # measured to itself, so the outcome is always `duration/2`'s own.
  defp duration_to_a_year_on(value) do
    case Tempo.shift(value, year: 1) do
      %Tempo{} = later -> Tempo.duration(value, later)
      _not_moved -> Tempo.duration(value, value)
    end
  end

  defp arithmetic do
    units(&Tempo.trunc/2, "trunc/2", [:year, :month, :day, :hour]) ++
      units(&Tempo.round/2, "round/2", [:year, :month, :day, :hour]) ++
      units(&Tempo.at_resolution/2, "at_resolution/2", [:year, :day, :second]) ++
      units(&Tempo.extend_resolution/2, "extend_resolution/2", [:day, :second]) ++
      [
        {"shift/2 day", :arithmetic, :never, &Tempo.shift(&1, day: 1)},
        {"shift/2 month", :arithmetic, :never, &Tempo.shift(&1, month: 1)},
        {"shift/2 hour", :arithmetic, :never, &Tempo.shift(&1, hour: -1)},
        {"shift/2 duration", :arithmetic, :never, &Tempo.shift(&1, ~o"P1Y")},
        {"trunc/1", :arithmetic, :never, &Tempo.trunc/1},
        {"round/1", :arithmetic, :never, &Tempo.round/1},
        {"extend/1", :arithmetic, :never, &Tempo.extend/1},
        {"extend!/1", :arithmetic, :deliberate, &Tempo.extend!/1},
        {"split/1", :arithmetic, :deliberate, &Tempo.split/1},
        {"at/2 a time", :arithmetic, :never, &Tempo.at(&1, ~o"T17")},
        {"at/2 on a date", :arithmetic, :never, &Tempo.at(~o"2026-06-15", &1)},
        {"on/2 a date", :arithmetic, :never, &Tempo.on(&1, ~o"2026-06-15")},
        {"on/2 a time", :arithmetic, :never, &Tempo.on(~o"T17", &1)},
        {"at!/2 a time", :arithmetic, :deliberate, &Tempo.at!(&1, ~o"T17")},
        {"on!/2 a date", :arithmetic, :deliberate, &Tempo.on!(&1, ~o"2026-06-15")}
      ]
  end

  defp units(function, name, units) do
    for unit <- units do
      {"#{name} #{unit}", :arithmetic, :never, &function.(&1, unit)}
    end
  end

  defp select do
    [
      {"select/2 weekends", :select, :never, &Tempo.select(&1, Tempo.weekends(:US))},
      {"select/2 indexes", :select, :never, &Tempo.select(&1, [1, 15])},
      {"select/2 a value", :select, :never, &Tempo.select(&1, ~o"12-25")},
      {"select!/2 indexes", :select, :deliberate, &Tempo.select!(&1, [1, 15])},
      {"workday?/2", :select, :deliberate, &Tempo.workday?(&1, :US)},
      {"weekend?/2", :select, :deliberate, &Tempo.weekend?(&1, :US)},
      {"count_workdays/2", :select, :never, &Tempo.count_workdays(&1, :US)},
      {"nearest_workday/2", :select, :never, &Tempo.nearest_workday(&1, :US)},
      {"roll_to_workday/3", :select, :never,
       &Tempo.roll_to_workday(&1, :US, roll: :modified_following)},
      {"next_workday/2", :select, :never, &Tempo.next_workday(&1, :US)},
      {"previous_workday/2", :select, :never, &Tempo.previous_workday(&1, :US)},
      {"add_workdays/3", :select, :never, &Tempo.add_workdays(&1, 2, :US)}
    ]
  end

  defp format do
    [
      {"to_iso8601/1", :format, :never, &Tempo.to_iso8601/1},
      {"to_iso8601!/1", :format, :deliberate, &Tempo.to_iso8601!/1},
      {"to_string/1", :format, :never, &Tempo.to_string/1},
      {"to_string!/1", :format, :deliberate, &Tempo.to_string!/1},
      {"to_relative_string/2", :format, :never,
       &Tempo.to_relative_string(&1, from: ~o"2026-10-03")},
      {"to_relative_string!/2", :format, :deliberate,
       &Tempo.to_relative_string!(&1, from: ~o"2026-10-03")},
      {"to_relative_string/2 from a moment", :format, :never,
       &Tempo.to_relative_string(&1, from: ~o"2026-10-03T12:00:00Z")},
      {"explain/1", :format, :never, &Tempo.explain/1},
      {"Kernel.inspect/1", :format, :never, &inspect/1}
    ]
  end

  defp parts do
    [
      {"year/1", :parts, :deliberate, &Tempo.year/1},
      {"month/1", :parts, :deliberate, &Tempo.month/1},
      {"season/1", :parts, :deliberate, &Tempo.season/1},
      {"week/1", :parts, :deliberate, &Tempo.week/1},
      {"day/1", :parts, :deliberate, &Tempo.day/1},
      {"hour/1", :parts, :deliberate, &Tempo.hour/1},
      {"minute/1", :parts, :deliberate, &Tempo.minute/1},
      {"second/1", :parts, :deliberate, &Tempo.second/1},
      {"day_of_week/1", :parts, :deliberate, &Tempo.day_of_week/1},
      {"day_of_year/1", :parts, :deliberate, &Tempo.day_of_year/1},
      {"quarter_of_year/1", :parts, :deliberate, &Tempo.quarter_of_year/1},
      {"days_in_month/1", :parts, :deliberate, &Tempo.days_in_month/1},
      {"leap_year?/1", :parts, :deliberate, &Tempo.leap_year?/1},
      {"anchored?/1", :parts, :deliberate, &Tempo.anchored?/1},
      {"floating?/1", :parts, :deliberate, &Tempo.floating?/1},
      {"zoned?/1", :parts, :deliberate, &Tempo.zoned?/1},
      {"resolution/1", :parts, :deliberate, &Tempo.resolution/1},
      {"metadata/1", :parts, :never, &Tempo.metadata/1},
      {"put_metadata/2", :parts, :never, &Tempo.put_metadata(&1, %{label: "matrix"})}
    ]
  end
end
