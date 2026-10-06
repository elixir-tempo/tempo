defmodule Tempo.FixedOffsetTest do
  @moduledoc """
  A fixed offset is no zone of the time zone database. From its 1.4 Localize
  names the time zone of a date and time written with an offset by the
  offset itself, `"-05:00"`, as RFC 9557 does; before it the name was
  `"Etc/UTC"` beside an offset that is not zero. Tempo holds a fixed offset
  as the shift `from_iso8601/1` reads one, wherever a `DateTime` or a text
  read by the locale gives it.

  Read as a zone, `"-05:00"` is one no database has: `Tempo.parse/2`
  returned a `Tempo.UnknownZoneError` for "2:30 PM EST", and a value built
  from such a `DateTime` was taken for UTC, five hours from the time it
  names.

  The measure is the `DateTime` itself and its instant, by
  `DateTime.to_unix/1`, which reads a `DateTime`'s own offsets.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare

  # A `DateTime` at each offset, as Localize reads one: its time zone is the
  # offset.
  @offsets ["-05:00", "+05:30", "+14:00", "-00:30", "-07:52:58"]

  defp at_offset(offset) do
    {:ok, date_time} =
      DateTime.new(~D[2026-05-23], ~T[14:30:00], offset, Localize.TimeZoneDatabase)

    date_time
  end

  # A `DateTime` whose fields are given, as a caller may build one: a time
  # zone and the offset beside it.
  defp date_time(time_zone, utc_offset) do
    %DateTime{
      year: 2026,
      month: 5,
      day: 23,
      hour: 14,
      minute: 30,
      second: 0,
      microsecond: {0, 0},
      time_zone: time_zone,
      zone_abbr: time_zone,
      utc_offset: utc_offset,
      std_offset: 0,
      calendar: Calendar.ISO
    }
  end

  # The instant of a Tempo value, by the `DateTime` it converts to.
  defp instant(%Tempo{} = value) do
    {:ok, date_time} = Tempo.to_datetime(value)
    DateTime.to_unix(date_time)
  end

  # The value at an instant, written in UTC.
  defp at_instant(unix), do: unix |> DateTime.from_unix!() |> Tempo.from_elixir()

  describe "a DateTime whose time zone is a fixed offset" do
    test "is the time it names, with the offset as its shift and no zone" do
      for offset <- @offsets do
        date_time = at_offset(offset)
        value = Tempo.from_elixir(date_time)

        assert {offset, instant(value)} == {offset, DateTime.to_unix(date_time)}

        assert {offset, Compare.offset_seconds(value.shift)} ==
                 {offset, date_time.utc_offset}

        assert {offset, value.extended} == {offset, nil}
      end
    end

    test "is the value its own text reads as" do
      # `DateTime.to_iso8601/1` writes an offset to the minute, so the one
      # with seconds is held to what Tempo writes for it alone.
      for offset <- @offsets do
        date_time = at_offset(offset)
        value = Tempo.from_elixir(date_time)

        assert {offset, Tempo.from_iso8601(Tempo.to_iso8601!(value))} == {offset, {:ok, value}}
      end

      for offset <- @offsets, rem(at_offset(offset).utc_offset, 60) == 0 do
        date_time = at_offset(offset)
        read = Tempo.from_iso8601!(DateTime.to_iso8601(date_time))

        assert {offset, Tempo.relation(Tempo.from_elixir(date_time), read)} == {offset, :equals}
      end
    end

    test "is stepped and compared at its offset" do
      for offset <- @offsets do
        date_time = at_offset(offset)
        value = Tempo.from_elixir(date_time)
        an_hour_on = Tempo.shift(value, hour: 1)

        assert {offset, Tempo.relation(value, at_instant(DateTime.to_unix(date_time)))} ==
                 {offset, :equals}

        assert {offset, instant(an_hour_on)} == {offset, DateTime.to_unix(date_time) + 3_600}
        assert {offset, an_hour_on.shift} == {offset, value.shift}
      end
    end

    test "is so where the time zone is Etc/UTC beside an offset, as it was named before" do
      date_time = date_time("Etc/UTC", -18_000)
      value = Tempo.from_elixir(date_time)

      assert instant(value) == DateTime.to_unix(date_time)
      assert value == Tempo.from_elixir(at_offset("-05:00"))
    end
  end

  describe "a DateTime in a zone" do
    test "keeps its zone" do
      {:ok, new_york} = DateTime.new(~D[2026-05-23], ~T[14:30:00], "America/New_York")

      assert Tempo.from_elixir(new_york) == ~o"2026Y5M23DT14H30M0SZ-4H[America/New_York]"
      assert Tempo.from_elixir(~U[2026-05-23 14:30:00Z]) == ~o"2026Y5M23DT14H30M0SZ[Etc/UTC]"
    end

    test "that the time zone database does not have is read by its own offset" do
      date_time = date_time("Mars/Olympus", -18_000)
      value = Tempo.from_elixir(date_time)
      unix = DateTime.to_unix(date_time)

      # It was taken for UTC, five hours before the time it names.
      assert Tempo.relation(value, at_instant(unix)) == :equals

      an_hour_on = Tempo.shift(value, hour: 1)

      assert Tempo.relation(an_hour_on, at_instant(unix + 3_600)) == :equals
      assert an_hour_on.shift == value.shift
    end
  end

  describe "a text the locale reads at a fixed offset" do
    test "is the value from_iso8601/1 reads from the offset" do
      for {text, iso8601} <- [
            {"May 23, 2026, 2:30 PM EST", "2026-05-23T14:30-05:00"},
            {"May 23, 2026, 2:30 PM GMT+5", "2026-05-23T14:30+05:00"},
            {"May 23, 2026, 2:30 PM GMT-3:30", "2026-05-23T14:30-03:30"}
          ] do
        assert {text, Tempo.parse(text, locale: :en)} == {text, Tempo.from_iso8601(iso8601)}
      end
    end

    test "is in its zone where it names one" do
      assert Tempo.parse("May 23, 2026, 2:30 PM GMT", locale: :en) ==
               {:ok, ~o"2026Y5M23DT14H30M[Etc/UTC]"}

      assert Tempo.parse("May 23, 2026, 2:30 PM New York Time", locale: :en) ==
               {:ok, ~o"2026Y5M23DT14H30M[America/New_York]"}
    end
  end

  describe "to_datetime/1 of a value whose offset is written as its time zone" do
    test "is the instant at that offset" do
      {:ok, expected, _offset} = DateTime.from_iso8601("2026-05-23T14:30:00-05:00")

      # RFC 9557 writes the zone of a fixed offset in brackets. It was called
      # a floating value, though it is compared as the time it names.
      for text <- ["2026-05-23T14:30:00[-05:00]", "2026-05-23T14:30:00-05:00[-05:00]"] do
        assert {text, Tempo.to_datetime(Tempo.from_iso8601!(text))} == {text, {:ok, expected}}
      end

      assert Tempo.relation(~o"2026-05-23T14:30:00[-05:00]", Tempo.from_elixir(expected)) ==
               :equals
    end

    test "is still an error for a value with no offset at all" do
      assert {:error, %Tempo.ConversionError{}} = Tempo.to_datetime(~o"2026-05-23T14:30:00")
    end
  end
end
