defmodule Tempo.ZoneDatabaseTest do
  # Tempo asks the time zone database the application configures, and `tz`,
  # which comes with it, where none is configured (decision 77). A database
  # configured that knows only UTC gives a named zone no rules to read a
  # time by, and it is refused where it is given. The tests set the database
  # Tempo asks, so they run alone.
  use ExUnit.Case, async: false

  import Tempo.Sigils

  alias Tempo.Event
  alias Tempo.Interval

  describe "with no database configured" do
    setup do
      elixirs = Application.fetch_env(:elixir, :time_zone_database)
      Application.delete_env(:elixir, :time_zone_database)
      Application.delete_env(:ex_tempo, :time_zone_database)

      on_exit(fn ->
        case elixirs do
          {:ok, database} -> Application.put_env(:elixir, :time_zone_database, database)
          :error -> :ok
        end
      end)

      :ok
    end

    test "a named zone is read by tz, which comes with Tempo" do
      assert Tempo.time_zone_database() == Tz.TimeZoneDatabase

      assert Tempo.from_iso8601("2026-06-15T09:00:00[Europe/Paris]") ==
               {:ok, ~o"2026-06-15T09:00:00[Europe/Paris]"}
    end

    test "Elixir's own UTC-only default is not read as a choice" do
      Application.put_env(:elixir, :time_zone_database, Calendar.UTCOnlyTimeZoneDatabase)
      assert Tempo.time_zone_database() == Tz.TimeZoneDatabase
      assert {:ok, _paris} = Tempo.in_zone(~o"2026-06-15T09", "Europe/Paris")
    end

    test "a value in a named zone is the DateTime of its zone, read by tz" do
      Application.put_env(:elixir, :time_zone_database, Calendar.UTCOnlyTimeZoneDatabase)
      paris = DateTime.new!(~D[2026-06-15], ~T[09:00:00], "Europe/Paris", Tz.TimeZoneDatabase)

      assert Tempo.to_elixir(~o"2026-06-15T09:00:00[Europe/Paris]") == {:ok, paris}
      assert Tempo.to_elixir(~o"2026-06-15T09:00:00+02:00[Europe/Paris]") == {:ok, paris}
    end

    test "the instants of an interval in a named zone are read by tz" do
      Application.put_env(:elixir, :time_zone_database, Calendar.UTCOnlyTimeZoneDatabase)

      assert {:ok, {from, to}} =
               Interval.instants(~o"2026-06-15T09:00/2026-06-15T10:00[America/New_York]")

      assert DateTime.to_iso8601(from) == "2026-06-15T09:00:00-04:00"
      assert DateTime.to_iso8601(to) == "2026-06-15T10:00:00-04:00"
    end

    test "the time now and an event's date in a named zone are read by tz" do
      Application.put_env(:elixir, :time_zone_database, Calendar.UTCOnlyTimeZoneDatabase)

      assert {:ok, %Tempo{}} = Tempo.now("Europe/Paris")
      assert Event.date("march-equinox@Asia/Tokyo", 2026) == {:ok, ~D[2026-03-20]}
    end
  end

  setup do
    paris = DateTime.new!(~D[2026-06-15], ~T[09:00:00], "Europe/Paris", Tz.TimeZoneDatabase)
    built = ~o"2026-06-15T09:00:00[Europe/Paris]"

    Application.put_env(:ex_tempo, :time_zone_database, Calendar.UTCOnlyTimeZoneDatabase)
    on_exit(fn -> Application.delete_env(:ex_tempo, :time_zone_database) end)

    %{paris: paris, built: built}
  end

  test "the database Tempo asks is the one configured for it" do
    assert Tempo.time_zone_database() == Calendar.UTCOnlyTimeZoneDatabase
  end

  test "a named zone given with no database is refused, saying what to configure" do
    assert {:error, %Tempo.ZoneError{zone: "Europe/Paris", reason: :no_database} = error} =
             Tempo.from_iso8601("2026-06-15T09:00:00[Europe/Paris]")

    assert Exception.message(error) =~ "needs a time zone database"
  end

  test "every operation that takes a zone's name refuses it" do
    for answer <- [
          Tempo.in_zone(~o"2026-06-15T09", "Europe/Paris"),
          Tempo.shift_zone(~o"2026-06-15T09Z", "Europe/Paris"),
          Tempo.now("Europe/Paris")
        ] do
      assert {:error, %Tempo.ZoneError{reason: :no_database}} = answer
    end
  end

  test "UTC, a fixed offset and a time shift need no database" do
    assert {:ok, _} = Tempo.from_iso8601("2026-06-15T09:00:00[Etc/UTC]")
    assert {:ok, _} = Tempo.from_iso8601("2026-06-15T09:00:00[+02:00]")
    assert {:ok, ~o"2026-06-15T09:00:00+02:00"} = Tempo.from_iso8601("2026-06-15T09:00:00+02:00")
  end

  test "a DateTime in a zone the database cannot answer keeps its own offset", %{paris: paris} do
    assert Tempo.from_elixir(paris) == {:ok, ~o"2026-06-15T09:00:00+02:00"}
  end

  test "a zone made before the database was changed raises the error it would have been",
       %{built: built} do
    assert_raise Tempo.ZoneError, ~r/needs a time zone database/, fn ->
      Tempo.shift(built, year: 30)
    end
  end
end
