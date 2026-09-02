defmodule Tempo.RangeExpansionPropertyTest do
  @moduledoc """
  Any combination of ranges, in any component position or positions,
  expands to exactly the dates a calendar says exist.

  The reference set is computed with plain `Date` arithmetic rather
  than Tempo's own machinery, so the property checks the expansion
  against the calendar rather than against itself. Both expansion
  paths — `Tempo.to_interval/1` and the `Enumerable` protocol — are
  held to the same reference, since a value that materialises one way
  must enumerate the same way.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tempo.Interval
  alias Tempo.IntervalSet

  # Component specs are generated as data, rendered to ISO 8601 *and*
  # resolved to a reference list independently. `:all` is the
  # open-ended `{1..-1}` form whose end the calendar decides.

  defp year_spec do
    one_of([
      integer(2020..2030) |> map(&{:single, &1}),
      uniq_list_of(integer(2020..2030), min_length: 2, max_length: 3)
      |> map(&{:list, Enum.sort(&1)}),
      integer(2020..2028) |> map(&{:range, &1, &1 + 2})
    ])
  end

  defp month_spec do
    one_of([
      constant(:all),
      integer(1..12) |> map(&{:single, &1}),
      uniq_list_of(integer(1..12), min_length: 2, max_length: 4) |> map(&{:list, Enum.sort(&1)}),
      integer(1..9) |> map(&{:range, &1, &1 + 3}),
      integer(1..6) |> map(&{:open_from, &1})
    ])
  end

  defp day_spec do
    one_of([
      constant(:all),
      integer(1..28) |> map(&{:single, &1}),
      uniq_list_of(integer(1..28), min_length: 2, max_length: 4) |> map(&{:list, Enum.sort(&1)}),
      integer(1..20) |> map(&{:range, &1, &1 + 8}),
      # Deliberately overflows short months — 28..31 exists in
      # January, not in a non-leap February.
      constant({:range, 28, 31}),
      integer(20..27) |> map(&{:open_from, &1})
    ])
  end

  defp render(:all, designator), do: "{1..-1}#{designator}"
  defp render({:single, value}, designator), do: "#{value}#{designator}"
  defp render({:list, values}, designator), do: "{#{Enum.join(values, ",")}}#{designator}"
  defp render({:range, first, last}, designator), do: "{#{first}..#{last}}#{designator}"
  defp render({:open_from, first}, designator), do: "{#{first}..-1}#{designator}"

  # The values a spec denotes, given the count of units available in
  # this context. Values the context cannot hold simply are not
  # occurrences, matching ISO 8601-2 set semantics.
  defp resolve(:all, available), do: Enum.to_list(1..available)
  defp resolve({:single, value}, available), do: Enum.filter([value], &(&1 <= available))
  defp resolve({:list, values}, available), do: Enum.filter(values, &(&1 <= available))

  defp resolve({:range, first, last}, available),
    do: first..min(last, available)//1 |> Enum.to_list()

  defp resolve({:open_from, first}, available), do: first..available//1 |> Enum.to_list()

  # The property's subject is ranges in one or more positions, so at
  # least one component must be set-valued. A fully concrete value has
  # no expansion to check (it materialises to a single interval) and
  # would enumerate its sub-points instead.
  defp specs do
    {year_spec(), month_spec(), day_spec()}
    |> tuple()
    |> filter(fn {years, months, days} ->
      Enum.any?([years, months, days], &set_valued?/1) and
        not concrete_context_overflow?(years, months, days)
    end)
  end

  # A day range that overflows its month is only an *expansion*
  # question when the month varies across members. A concrete month
  # determines its own maximum length whatever the year, so a literal
  # naming days beyond it cannot exist and the parser rejects it
  # outright — see the unit tests pinning both sides of that rule.
  defp concrete_context_overflow?(_years, {:single, month}, {:range, _first, last}) do
    last > Date.days_in_month(Date.new!(2020, month, 1))
  end

  defp concrete_context_overflow?(_years, _months, _days), do: false

  defp set_valued?({:single, _value}), do: false
  defp set_valued?(_spec), do: true

  defp reference_dates(year_spec, month_spec, day_spec) do
    for year <- resolve(year_spec, 9999),
        month <- resolve(month_spec, 12),
        day <- resolve(day_spec, Date.days_in_month(Date.new!(year, month, 1))) do
      Date.new!(year, month, day)
    end
  end

  defp iso(year_spec, month_spec, day_spec) do
    render(year_spec, "Y") <> render(month_spec, "M") <> render(day_spec, "D")
  end

  defp materialised_dates(iso) do
    {:ok, set} = iso |> Tempo.from_iso8601!() |> Tempo.to_interval()

    set
    |> IntervalSet.to_list()
    |> Enum.map(&(&1 |> Interval.from() |> Tempo.to_date() |> elem(1)))
  end

  defp enumerated_dates(iso) do
    iso
    |> Tempo.from_iso8601!()
    |> Enum.map(&(&1 |> Tempo.to_date() |> elem(1)))
  end

  property "ranges in any positions expand to exactly the dates the calendar holds" do
    check all({years, months, days} <- specs(), max_runs: 60) do
      iso = iso(years, months, days)
      expected = reference_dates(years, months, days)

      assert materialised_dates(iso) == expected,
             "materialisation disagreed with the calendar for #{iso}"

      assert enumerated_dates(iso) == expected,
             "enumeration disagreed with the calendar for #{iso}"
    end
  end

  property "every expanded member is a real date, distinct and in time order" do
    check all({years, months, days} <- specs(), max_runs: 40) do
      dates = materialised_dates(iso(years, months, days))

      assert Enum.all?(dates, &match?(%Date{}, &1)), "expansion produced a non-date"
      assert dates == Enum.uniq(dates), "expansion produced duplicate members"
      assert dates == Enum.sort(dates, Date), "expansion members were out of time order"
    end
  end

  property "an open-ended range follows each context's own length" do
    check all(year <- integer(2020..2030), max_runs: 20) do
      # `{1..-1}D` under every month of the year: the member count for
      # each month must equal that month's real length, so February
      # differs between leap and common years without anything saying
      # so.
      dates = materialised_dates("#{year}Y{1..-1}M{1..-1}D")

      per_month =
        dates
        |> Enum.group_by(& &1.month)
        |> Map.new(fn {month, days} -> {month, length(days)} end)

      expected =
        Map.new(1..12, fn month ->
          {month, Date.days_in_month(Date.new!(year, month, 1))}
        end)

      assert per_month == expected
      assert length(dates) == if(Date.leap_year?(Date.new!(year, 1, 1)), do: 366, else: 365)
    end
  end
end
