defmodule Tempo.StartOfManyValuesTest do
  @moduledoc """
  Where a value that names many values starts.

  A value that is no one point starts where the first of the spans
  `Tempo.to_interval/1` gives it does. Every span was converted to find
  that first one: 160 ms for a value of 8,000 values, and a
  `Tempo.ConversionError` past the 10,000 that are converted at once, so
  `Tempo.compare/3` raised for a value it had only to find the start of.
  The first value of the walk says where it starts.

  The measure is the conversion itself, for every value it converts: the
  start found must be the start of its first span. For a value of more
  values than are converted the start is worked out by hand.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Calendrical.Julian.March25
  alias Tempo.Compare
  alias Tempo.ConversionError
  alias Tempo.Interval
  alias Tempo.IntervalSet

  # Values that name several values, in every shape a unit names them.
  @several [
    "2026Y{1..12}M{1..28}D",
    "2026Y{6,3}M{-1,1}D",
    "{2027,2026}Y",
    "{2027,2026}Y{6,3}M",
    "2026Y6M{15,1}D",
    "2026Y6M{28..-1}D",
    "2024Y2M{28,29}D",
    "2024Y{1..3}M{28..-1}D",
    "2026-06-1X",
    "2026-XX-15",
    "2026-XX-XX",
    "202X",
    "2026Y{25,27}W",
    "2026Y{25,27}W{1,3}K",
    "2020Y{100,200}O",
    "2026Y6M15DT{9,14}H",
    "2026Y6M15DT10H{0,30}M",
    "2026Y6M{1,15}DT{9,14}H{0,30}M",
    "2026Y{1,2}G3MU",
    "2026Y5G10DU",
    "{6,7}M15D",
    "T{9,14}H",
    "{-0044,0044}Y3M15D"
  ]

  # A clock that skips an hour, a zone that left a day out, and a change in
  # each of two months. A set or a range in a unit that names a reading the
  # clock skips is refused where it is read, so the readings skipped here
  # are ones a mask passes over.
  @zoned [
    "2024Y3M10DT0XH[America/New_York]",
    "2024Y3M{9,10,11}DT3H[America/New_York]",
    "2011Y12M{28,29}D[Pacific/Apia]",
    "2011Y12M3XD[Pacific/Apia]",
    "2026Y{3,10}M{25..31}DT3H[Europe/Paris]"
  ]

  @other_calendars [
    {"5786Y{1..3}M{1,15}D", Calendrical.Hebrew},
    {"2026Y{1,53}W{1,7}K", Calendrical.ISOWeek},
    {"1750Y{1,12}M{1,5}D", March25},
    {"1750Y3M{24,25}D", March25}
  ]

  ## The measure

  # Where the conversion has a value start: the start of its one span, or of
  # the first of its spans, where that is a point; and its error.
  defp converted(value) do
    case Tempo.to_interval(value) do
      {:ok, %Interval{from: %Tempo{} = start}} -> {:starts, start}
      {:ok, %IntervalSet{} = set} -> first_of(IntervalSet.first(set))
      {:error, error} -> {:error, error.__struct__}
    end
  end

  defp first_of(%Interval{from: %Tempo{} = start}), do: {:starts, start}
  defp first_of(_no_span), do: :no_span

  defp found(value) do
    case Compare.start_point(value) do
      {:ok, %Tempo{} = start} -> {:starts, start}
      {:error, error} -> {:error, error.__struct__}
    end
  end

  # Whether a start is the one the conversion gives: the same point, or an
  # error where the conversion gives none or no point.
  defp agrees?({:starts, found}, {:starts, converted}),
    do: Compare.compare_endpoints(found, converted) == :same

  defp agrees?({:error, _}, {:error, _}), do: true
  defp agrees?({:error, _}, :no_span), do: true
  defp agrees?(_found, _converted), do: false

  describe "the start of a value that names several values" do
    test "is the start of the first span it converts to" do
      for text <- @several ++ @zoned do
        value = Tempo.from_iso8601!(text)

        assert {text, found(value), agrees?(found(value), converted(value))} ==
                 {text, found(value), true}
      end
    end

    test "is so in another calendar, and in a year the walk does not list in the order of time" do
      for {text, calendar} <- @other_calendars do
        value = Tempo.from_iso8601!(text, calendar)

        assert {text, found(value), agrees?(found(value), converted(value))} ==
                 {text, found(value), true}
      end
    end

    test "is the first the zone's clock shows, where it skips the first its digits match" do
      # 30 December 2011 was left out in Samoa, so the thirties of that
      # month start on the 31st.
      thirties = Tempo.from_iso8601!("2011Y12M3XD[Pacific/Apia]")

      assert Compare.start_point(thirties) ==
               {:ok, Tempo.from_iso8601!("2011Y12M31D[Pacific/Apia]")}
    end
  end

  describe "a value of more values than are converted at once" do
    # 12 months of 28 days of 24 hours of 60 minutes: 483,840 values.
    @minutes "2026Y{1..12}M{1..28}DT{0..23}H{0..59}M"

    test "starts at its first value, where finding that was an error" do
      assert {:error, %ConversionError{reason: :too_many_values}} =
               Tempo.to_interval(Tempo.from_iso8601!(@minutes))

      assert Compare.start_point(Tempo.from_iso8601!(@minutes)) == {:ok, ~o"2026Y1M1DT0H0M"}

      assert Compare.start_point(~o"{2030..2032}Y{1..12}M{1..28}DT{0..23}H{30,45}M") ==
               {:ok, ~o"2030Y1M1DT0H30M"}
    end

    test "is compared and sorted by it, where each raised" do
      minutes = Tempo.from_iso8601!(@minutes)

      assert Tempo.compare(minutes, ~o"2026-01-01T00:00") == :eq
      assert Tempo.compare(minutes, ~o"2026-06") == :lt
      assert Tempo.compare(minutes, ~o"2025-12-31T23:59") == :gt

      assert Enum.sort([~o"2026-06", minutes, ~o"2025-12-31"], Tempo) ==
               [~o"2025-12-31", minutes, ~o"2026-06"]
    end

    test "is refused still where its years alone are more than are listed" do
      assert {:error, %ConversionError{reason: :too_many_values}} =
               Compare.start_point(~o"{1..99999999}Y6M")
    end
  end
end
