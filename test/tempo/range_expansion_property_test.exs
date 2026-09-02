defmodule Tempo.RangeExpansionPropertyTest do
  @moduledoc """
  Any combination of ranges, in any component position or positions,
  expands to exactly the values a calendar says exist.

  Every time component is covered — year, month, day, hour, minute
  and second on the calendar axis, plus the week axis (week and
  day-of-week) and the ordinal axis (day-of-year) in their own
  properties, since those use different designators and normalise to
  calendar dates on the way out.

  The reference set is computed with plain `Date` arithmetic and the
  clock units' own fixed extents rather than with Tempo's machinery,
  so each property checks the expansion against the calendar rather
  than against itself. Both expansion paths — `Tempo.to_interval/1`
  and the `Enumerable` protocol — are held to that reference, since a
  value that materialises one way must enumerate the same way.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tempo.Interval
  alias Tempo.IntervalSet

  # Keep generated products small enough to expand quickly; these
  # properties are about correctness across shapes, not about volume.
  @max_members 400

  @units [:month, :day, :hour, :minute, :second]
  @designators ["M", "D", "H", "M", "S"]
  @domains [1..12, nil, 0..23, 0..59, 0..59]

  ## Specs are generated as data, then rendered to ISO 8601 *and*
  ## resolved against an independent reference.

  defp spec_for(domain) do
    values = Enum.to_list(domain)
    first = Enum.min(values)

    one_of([
      constant(:all),
      member_of(values) |> map(&{:single, &1}),
      uniq_list_of(member_of(values), min_length: 2, max_length: 3)
      |> map(&{:list, Enum.sort(&1)}),
      integer(first..(first + 1)) |> map(&{:range, &1, &1 + 2}),
      member_of(values) |> map(&{:open_from, &1})
    ])
  end

  # `{n..-1}` runs from `n` to the unit's last value, so "the whole
  # extent" starts at the unit's *own* first value — 1 for a month,
  # 0 for an hour.
  defp render(:all, designator, domain), do: "{#{Enum.min(domain)}..-1}#{designator}"
  defp render({:single, value}, designator, _domain), do: "#{value}#{designator}"

  defp render({:list, values}, designator, _domain),
    do: "{#{Enum.join(values, ",")}}#{designator}"

  defp render({:range, first, last}, designator, _domain),
    do: "{#{first}..#{last}}#{designator}"

  defp render({:open_from, first}, designator, _domain),
    do: "{#{first}..-1}#{designator}"

  defp resolve(:all, domain), do: Enum.to_list(domain)
  defp resolve({:single, value}, domain), do: Enum.filter([value], &(&1 in domain))
  defp resolve({:list, values}, domain), do: Enum.filter(values, &(&1 in domain))

  defp resolve({:range, first, last}, domain),
    do: Enum.filter(first..last//1, &(&1 in domain))

  defp resolve({:open_from, first}, domain),
    do: Enum.filter(first..Enum.max(domain)//1, &(&1 in domain))

  ## The calendar axis: year, month, day, hour, minute, second.

  defp calendar_specs do
    gen all(
          year <- integer(2020..2030),
          depth <- integer(1..5),
          specs <- fixed_list(Enum.map(@domains, &spec_for(&1 || 1..28)))
        ) do
      # Components are contiguous coarse-to-fine: an hour spec only
      # appears when there is a day for it to sit in.
      {year, Enum.take(specs, depth)}
    end
  end

  defp iso(year, specs) do
    rendered =
      [specs, @designators, @domains]
      |> Enum.zip()
      |> Enum.with_index()
      |> Enum.map(fn {{spec, designator, domain}, index} ->
        # `T` separates the date part from the time part, and
        # disambiguates month `M` from minute `M`.
        prefix = if index == 2, do: "T", else: ""
        prefix <> render(spec, designator, domain || 1..28)
      end)

    "#{year}Y" <> Enum.join(rendered)
  end

  # The expected tuples, built by walking the same dependent product
  # the expander must walk — but with `Date` and the clock units'
  # own extents as the authority.
  defp reference(year, specs) do
    specs
    |> Enum.zip(Enum.zip(@units, @domains))
    |> Enum.reduce([[year]], fn {spec, {unit, domain}}, paths ->
      for path <- paths, value <- resolve(spec, domain_for(unit, domain, path)) do
        path ++ [value]
      end
    end)
    |> Enum.map(&List.to_tuple/1)
  end

  defp domain_for(:day, nil, [year, month | _rest]),
    do: 1..Date.days_in_month(Date.new!(year, month, 1))

  defp domain_for(_unit, domain, _path), do: domain

  defp components(time, count) do
    [:year | @units]
    |> Enum.take(count + 1)
    |> Enum.map(&(time |> Keyword.fetch!(&1) |> concrete()))
    |> List.to_tuple()
  end

  # A set that resolves to a single member keeps its set form on the
  # materialised endpoint (`month: [12..12]` rather than `month: 12`);
  # compare on the value it denotes.
  defp concrete([value]), do: concrete(value)
  defp concrete(first..first//_step), do: first
  defp concrete(value), do: value

  # A set that resolves to a single member materialises as one
  # interval rather than a set — deliberate, so accept both shapes.
  defp members(iso) do
    case iso |> Tempo.from_iso8601!() |> Tempo.to_interval() do
      {:ok, %IntervalSet{} = set} -> IntervalSet.to_list(set)
      {:ok, %Interval{} = interval} -> [interval]
    end
  end

  defp materialised(iso, count) do
    iso
    |> members()
    |> Enum.map(&components(Interval.from(&1).time, count))
  end

  defp enumerated(iso, count) do
    iso
    |> Tempo.from_iso8601!()
    |> Enum.map(&components(&1.time, count))
  end

  defp dates_of(iso) do
    iso
    |> members()
    |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_date() |> elem(1)))
  end

  property "ranges in any combination of component positions expand to exactly the real values" do
    check all({year, specs} <- calendar_specs(), max_runs: 80) do
      expected = reference(year, specs)

      # Skip products too large to expand quickly, and those denoting a
      # single value: a spec can be written as a set yet resolve to one
      # member (`{12..-1}M` is December), and such a value is no longer
      # multi — it materialises as one interval and enumerates its
      # sub-points, which is the documented contract for a concrete
      # value rather than an expansion to check here.
      if length(expected) > 1 and length(expected) <= @max_members do
        iso = iso(year, specs)
        count = length(specs)

        assert materialised(iso, count) == expected,
               "materialisation disagreed with the calendar for #{iso}"

        assert enumerated(iso, count) == expected,
               "enumeration disagreed with the calendar for #{iso}"

        assert expected == Enum.sort(expected), "expansion was out of time order for #{iso}"
        assert expected == Enum.uniq(expected), "expansion produced duplicates for #{iso}"
      end
    end
  end

  ## The week axis — members normalise to calendar dates on the way out.

  property "week and day-of-week ranges expand to the right calendar dates" do
    check all(
            year <- integer(2020..2030),
            first_week <- integer(1..40),
            week_count <- integer(1..3),
            max_runs: 30
          ) do
      last_week = first_week + week_count - 1
      iso = "#{year}Y{#{first_week}..#{last_week}}W{1..-1}K"

      # ISO 8601 week 1 is the week containing 4 January; weeks run
      # Monday to Sunday.
      jan_4 = Date.new!(year, 1, 4)
      week_1_monday = Date.add(jan_4, -(Date.day_of_week(jan_4) - 1))

      expected =
        for week <- first_week..last_week//1, weekday <- 1..7//1 do
          Date.add(week_1_monday, (week - 1) * 7 + (weekday - 1))
        end

      assert dates_of(iso) == expected, "week-axis expansion disagreed for #{iso}"
    end
  end

  ## The ordinal axis.

  property "an ordinal day range expands to the days of the year" do
    check all(year <- integer(2020..2030), max_runs: 20) do
      dates = dates_of("#{year}Y{1..-1}O")
      days_in_year = if Date.leap_year?(Date.new!(year, 1, 1)), do: 366, else: 365

      assert length(dates) == days_in_year
      assert hd(dates) == Date.new!(year, 1, 1)
      assert List.last(dates) == Date.new!(year, 12, 31)
    end
  end

  ## Open-ended ranges follow each context's own extent.

  property "an open-ended range follows each context's own length" do
    check all(year <- integer(2020..2030), max_runs: 20) do
      dates = dates_of("#{year}Y{1..-1}M{1..-1}D")

      per_month =
        dates
        |> Enum.group_by(& &1.month)
        |> Map.new(fn {month, days} -> {month, length(days)} end)

      expected =
        Map.new(1..12, fn month -> {month, Date.days_in_month(Date.new!(year, month, 1))} end)

      assert per_month == expected
      assert length(dates) == if(Date.leap_year?(Date.new!(year, 1, 1)), do: 366, else: 365)
    end
  end
end
