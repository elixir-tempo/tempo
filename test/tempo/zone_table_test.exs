defmodule Tempo.ZoneTableTest do
  # The table of a zone's changes (`Tempo.Zone.Table`) is held to the
  # database it is built from: at every change the database lists, for
  # every zone it has, the offset a tick before the change and at it are
  # what `DateTime` says; where the table is grown past the list by
  # sampling, the changes found are where `DateTime` finds them; and a
  # database that lists nothing gives, by sampling, the table that the list
  # gives. The zone whose list has two changes an hour apart is read as the
  # database reads it, tick by tick and wall reading by wall reading.
  use ExUnit.Case, async: true

  alias Tempo.Zone
  alias Tempo.Zone.Table

  @second 1_000_000
  @hour 3600 * @second
  @day 24 * @hour
  @year_1900 :calendar.datetime_to_gregorian_seconds({{1900, 1, 1}, {0, 0, 0}}) * @second

  # A database that answers at a point and lists nothing: tz's answers,
  # without its list.
  defmodule PointOnly do
    @behaviour Calendar.TimeZoneDatabase

    @impl true
    defdelegate time_zone_period_from_utc_iso_days(days, zone), to: Tz.TimeZoneDatabase

    @impl true
    defdelegate time_zone_periods_from_wall_datetime(naive, zone), to: Tz.TimeZoneDatabase
  end

  defp tick(%NaiveDateTime{} = naive),
    do: naive |> NaiveDateTime.to_gregorian_seconds() |> elem(0) |> Kernel.*(@second)

  defp utc(tick), do: DateTime.from_gregorian_seconds(div(tick, @second))

  # The offset the database has at a tick, in ticks, as `DateTime` reads it.
  defp database_offset(zone, tick) do
    shown = DateTime.shift_zone!(utc(tick), zone, Tz.TimeZoneDatabase)
    (shown.utc_offset + shown.std_offset) * @second
  end

  # Every zone the tz data names on a `Zone` line.
  defp zones do
    dir = :tz |> :code.priv_dir() |> Path.join("tzdata*") |> Path.wildcard() |> List.first()

    for file <- ~w(africa antarctica asia australasia europe northamerica southamerica etcetera),
        path = Path.join(dir, file),
        File.exists?(path),
        line <- File.stream!(path),
        String.starts_with?(line, "Zone"),
        [_zone, name | _] = String.split(line),
        do: name
  end

  describe "the table of every zone the database lists" do
    test "has the database's offset a tick before each change and at it" do
      zones = zones()
      assert Enum.count_until(zones, 301) > 300

      for zone <- zones do
        table = Table.of(zone, Tz.TimeZoneDatabase, 0)

        for change <- Tuple.to_list(table.ticks), change >= @year_1900 do
          assert {zone, change, Table.offset_at(table, change - @second)} ==
                   {zone, change, database_offset(zone, change - @second)}

          assert {zone, change, Table.offset_at(table, change)} ==
                   {zone, change, database_offset(zone, change)}
        end
      end
    end

    test "names every pair of changes within six days of each other, all in the list" do
      close =
        for zone <- zones(),
            table = Table.of(zone, Tz.TimeZoneDatabase, 0),
            [a, b] <- table.ticks |> Tuple.to_list() |> Enum.chunk_every(2, 1, :discard),
            a >= @year_1900 and b - a < 6 * @day,
            do: {zone, utc(a), div(b - a, @hour)}

      # The hour at -02:00 that tz compiles for America/Scoresbysund on
      # 2024-03-31; every other pair of changes is at least 166 hours apart.
      assert close == [{"America/Scoresbysund", ~U[2024-03-31 00:00:00Z], 1}]
    end
  end

  describe "a table grown past the list by sampling" do
    for zone <- [
          "Europe/Paris",
          "America/New_York",
          "Australia/Sydney",
          "Europe/London",
          "Pacific/Chatham"
        ] do
      test "finds the changes of #{zone} where the database makes them" do
        listed = Table.of(unquote(zone), Tz.TimeZoneDatabase, 0)
        grown = Table.of(unquote(zone), Tz.TimeZoneDatabase, listed.known_until + 10 * 366 * @day)

        found = Tuple.to_list(grown.ticks) -- Tuple.to_list(listed.ticks)
        assert Enum.count_until(found, 20) == 20

        for change <- found do
          assert Table.offset_at(grown, change - @second) ==
                   database_offset(unquote(zone), change - @second)

          assert Table.offset_at(grown, change) == database_offset(unquote(zone), change)
        end
      end
    end
  end

  describe "a database that lists nothing" do
    test "gives, by sampling, the offsets the list gives at every change of the offset" do
      listed = Table.of("Europe/Paris", Tz.TimeZoneDatabase, 0)
      sampled = Table.of("Europe/Paris", PointOnly, listed.known_until)

      for change <- Tuple.to_list(listed.ticks), change >= @year_1900 do
        assert Table.offset_at(sampled, change - @second) ==
                 Table.offset_at(listed, change - @second)

        assert Table.offset_at(sampled, change) == Table.offset_at(listed, change)
      end
    end

    test "cannot see two changes within one of its samples, which the list can" do
      in_the_hour = tick(~N[2024-03-31 00:30:00])
      listed = Table.of("America/Scoresbysund", Tz.TimeZoneDatabase, in_the_hour)
      sampled = Table.of("America/Scoresbysund", PointOnly, in_the_hour)

      assert Table.offset_at(listed, in_the_hour) == -2 * @hour
      assert Table.offset_at(sampled, in_the_hour) == -1 * @hour
    end
  end

  describe "a zone whose list has two changes an hour apart" do
    test "is read at each tick as the database reads it" do
      for naive <- [
            ~N[2024-03-30 23:30:00],
            ~N[2024-03-31 00:30:00],
            ~N[2024-03-31 01:30:00],
            ~N[2024-03-31 02:30:00]
          ] do
        {:ok, moment} = DateTime.from_naive(naive, "Etc/UTC")
        {:ok, value} = Tempo.from_elixir(moment)
        {:ok, shifted} = Tempo.shift_zone(value, "America/Scoresbysund")
        {:ok, shown} = Tempo.to_datetime(shifted)

        assert shown == DateTime.shift_zone!(moment, "America/Scoresbysund", Tz.TimeZoneDatabase)
      end
    end

    test "shows the wall readings of the hour twice, skips the next, and places each as the database does" do
      {:ok, zone} = Zone.named("America/Scoresbysund")

      # 22:30 is shown at -01:00 and again at -02:00; 23:30 is skipped.
      assert Zone.offsets_at_wall(zone, tick(~N[2024-03-30 22:30:00])) ==
               [-1 * @hour, -2 * @hour]

      assert Zone.offsets_at_wall(zone, tick(~N[2024-03-30 23:30:00])) ==
               {:gap, -2 * @hour, -1 * @hour}

      assert Zone.first_shown(zone, tick(~N[2024-03-30 23:30:00])) ==
               tick(~N[2024-03-31 01:00:00])

      assert Zone.offsets_at_wall(zone, tick(~N[2024-03-31 00:30:00])) == [-1 * @hour]
    end
  end
end
