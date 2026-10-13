defmodule Tempo.InteropTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  describe "to_datetime/1" do
    test "a zoned value keeps its zone and its reading" do
      assert {:ok, datetime} = Tempo.to_datetime(~o"2030-03-01T08:00:00[Europe/Paris]")
      assert datetime.time_zone == "Europe/Paris"
      assert DateTime.to_naive(datetime) == ~N[2030-03-01 08:00:00]
    end

    test "a shift written beside a zone gives the moment, shown on the zone's clock" do
      assert {:ok, datetime} = Tempo.to_datetime(~o"2030-03-01T08:00:00+03:00[Europe/Paris]")
      assert DateTime.compare(datetime, ~U[2030-03-01 05:00:00Z]) == :eq
      assert DateTime.to_naive(datetime) == ~N[2030-03-01 06:00:00]

      {:ok, utc} = Tempo.shift_zone(~o"2030-03-01T08:00:00+03:00[Europe/Paris]", "Etc/UTC")
      assert Tempo.to_naive_datetime(utc) == {:ok, ~N[2030-03-01 05:00:00]}
    end

    test "a shift chooses between the two readings of an hour shown twice" do
      assert {:ok, first} = Tempo.to_datetime(~o"2026-10-25T02:30:00+02:00[Europe/Paris]")
      assert {:ok, second} = Tempo.to_datetime(~o"2026-10-25T02:30:00+01:00[Europe/Paris]")
      assert DateTime.diff(second, first) == 3600
    end

    test "a shifted value with no zone is its moment in UTC" do
      assert Tempo.to_datetime(~o"2030-03-01T08:00:00+05:30") == {:ok, ~U[2030-03-01 02:30:00Z]}
    end

    test "a floating value has no moment" do
      assert {:error, %Tempo.ConversionError{reason: :floating}} =
               Tempo.to_datetime(~o"2030-03-01T08:00:00")
    end
  end

  describe "in_zone/2 and shift_zone/2" do
    test "each refuses the other's operand and says which to use" do
      assert {:error, %Tempo.FrameError{reason: :zoned} = zoned} =
               Tempo.in_zone(~o"2030-03-01T08:00[Europe/Paris]", "Europe/London")

      assert Exception.message(zoned) =~ "Tempo.shift_zone/2"

      assert {:error, %Tempo.FrameError{reason: :floating} = floating} =
               Tempo.shift_zone(~o"2030-03-01T08:00", "Europe/London")

      assert Exception.message(floating) =~ "Tempo.in_zone/2"
    end
  end

  describe "one set, one calendar, one zone" do
    test "members in several zones are moved to the first named, keeping their metadata" do
      london = ~o"2026-06-01T09/2026-06-01T10[Europe/London]"

      new_york =
        Tempo.put_metadata(~o"2026-06-01T09/2026-06-01T10[America/New_York]", %{who: :ny})

      utc = ~o"2026-06-01T12Z/2026-06-01T13Z"

      assert {:ok, set} = IntervalSet.new([london, new_york, utc])

      assert Tempo.to_iso8601!(set) ==
               "{2026Y6M1DT9H/T10H,2026Y6M1DT14H/T15H,2026Y6M1DT13H/T14H}[Europe/London]"

      assert IntervalSet.map(set, &Tempo.metadata/1) == [%{}, %{who: :ny}, %{}]
    end

    test "a union is in its first operand's zone" do
      london = ~o"2026-06-01T09/2026-06-01T10[Europe/London]"
      new_york = ~o"2026-06-01T09/2026-06-01T10[America/New_York]"

      assert Tempo.union(new_york, london) ==
               {:ok,
                ~o"{2026-06-01T04/2026-06-01T05,2026-06-01T09/2026-06-01T10}[America/New_York]"}
    end

    test "members that carry shifts alone keep them" do
      assert {:ok, set} =
               IntervalSet.new([
                 ~o"2026-06-01T12Z/2026-06-01T13Z",
                 ~o"2026-06-01T12+02:00/2026-06-01T13+02:00"
               ])

      assert IntervalSet.count(set) == 2
      assert set.zone == nil
    end

    test "a member with no zone beside a zoned one is refused" do
      assert {:error, %Tempo.FrameError{reason: :floating_and_zoned}} =
               IntervalSet.new([
                 ~o"2026-06-01T09/2026-06-01T10[Europe/London]",
                 ~o"2026-06-01T12/2026-06-01T13"
               ])
    end

    test "members of another calendar are brought to the first's" do
      assert IntervalSet.new([~o"2026-06-15", ~o"5786-09-30[u-ca=hebrew]"]) ==
               {:ok, ~o"{2026-06-15,2026-06-15}"}
    end
  end

  describe "from_elixir/2 and back" do
    test "a DateTime in a zone returns as itself" do
      datetime = DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris")
      assert {:ok, value} = Tempo.from_elixir(datetime)
      assert Tempo.to_datetime(value) == {:ok, datetime}
    end
  end

  describe "what has no Elixir value" do
    test "is an error that says so, for each conversion" do
      for result <- [
            Tempo.to_date(~o"T10"),
            Tempo.to_date(~o"2026-06"),
            Tempo.to_time(~o"2026-06-15"),
            Tempo.to_naive_datetime(~o"2026-06"),
            Tempo.to_elixir(~o"2026-06"),
            Tempo.to_elixir(~o"2026-06-15/2026-06-20"),
            Tempo.from_elixir(:nonsense)
          ] do
        assert {:error, %Tempo.ConversionError{reason: :not_an_elixir_value}} = result
      end
    end

    test "a floating value is no moment" do
      assert {:error, %Tempo.ConversionError{reason: :floating}} =
               Tempo.to_datetime(~o"2026-06-15T10:00:00")
    end
  end

  describe "a duration" do
    test "goes to Elixir's and comes back" do
      assert Tempo.to_elixir(~o"P1DT2H") == {:ok, Duration.new!(day: 1, hour: 2)}
      assert Tempo.from_elixir(Duration.new!(day: 1, hour: 2)) == {:ok, ~o"P1DT2H"}
    end
  end

  describe "a part of a second" do
    test "keeps its precision both ways" do
      assert Tempo.from_elixir(~T[10:30:00.5]) == {:ok, ~o"T10:30:00.5"}
      assert Tempo.to_elixir(~o"T10:30:00.5") == {:ok, ~T[10:30:00.5]}
      assert Tempo.to_time(~o"T10:30:00") == {:ok, ~T[10:30:00]}
    end
  end

  describe "an hour a clock shows twice" do
    test "is its first showing, as Elixir's own conversion gives" do
      assert {:ok, first} = Tempo.to_datetime(~o"2026-11-01T01:30:00[America/New_York]")
      assert first.zone_abbr == "EDT"
    end
  end

  describe "the raising forms" do
    test "return the value, or raise the error" do
      assert Tempo.from_elixir!(~D[2026-06-15]) == ~o"2026-06-15"
      assert_raise Tempo.ConversionError, fn -> Tempo.from_elixir!(:nonsense) end
    end
  end
end
