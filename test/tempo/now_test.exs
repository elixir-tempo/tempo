defmodule Tempo.NowTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Clock.Test

  # Install `Tempo.Clock.Test` as the clock for this test process
  # only. Using `Process.put` (not `Application.put_env`) keeps the
  # swap process-local so it does not leak into other async tests
  # or doctests running concurrently in the same VM.
  #
  # `Tempo.Clock.clock/0` reads the process-local override first and
  # falls back to the application environment.
  setup do
    Process.put({Tempo.Clock, :clock}, Tempo.Clock.Test)
    :ok
  end

  describe "Tempo.utc_now/0" do
    test "returns a second-resolution Tempo in Etc/UTC" do
      Test.put(~U[2026-06-15 14:30:00Z])

      tempo = Tempo.utc_now()

      assert Tempo.resolution(tempo) == {:second, 1}
      assert tempo.extended.zone_id == "Etc/UTC"

      assert tempo.time ==
               [year: 2026, month: 6, day: 15, hour: 14, minute: 30, second: 0]
    end
  end

  describe "Tempo.now/1" do
    test "defaults to Etc/UTC" do
      Test.put(~U[2026-06-15 14:30:00Z])
      assert Tempo.now().extended.zone_id == "Etc/UTC"
    end

    test "projects the UTC instant into the requested zone" do
      # 14:30 UTC on 2026-06-15 is 16:30 in Paris (UTC+2 during DST).
      Test.put(~U[2026-06-15 14:30:00Z])

      tempo = Tempo.now("Europe/Paris")

      assert tempo.extended.zone_id == "Europe/Paris"
      assert Keyword.take(tempo.time, [:hour, :minute]) == [hour: 16, minute: 30]
    end

    test "crosses the date line when the zone moves the wall date" do
      # 23:30 UTC on 2026-06-15 is 08:30 on the 16th in Tokyo (UTC+9).
      Test.put(~U[2026-06-15 23:30:00Z])

      tempo = Tempo.now("Asia/Tokyo")

      assert Keyword.get(tempo.time, :day) == 16
      assert Keyword.get(tempo.time, :hour) == 8
    end
  end

  describe "Tempo.utc_today/0" do
    test "returns a floating day-resolution Tempo" do
      Test.put(~U[2026-06-15 14:30:00Z])

      assert Tempo.utc_today() |> Tempo.resolution() == {:day, 1}
      assert Tempo.utc_today().time == [year: 2026, month: 6, day: 15]
      assert Tempo.floating?(Tempo.utc_today())
    end
  end

  describe "Tempo.today/1" do
    test "returns the date in the given zone, floating" do
      # 23:30 UTC on 2026-06-15 is already the 16th in Tokyo.
      Test.put(~U[2026-06-15 23:30:00Z])

      tempo = Tempo.today("Asia/Tokyo")

      assert Tempo.resolution(tempo) == {:day, 1}
      assert tempo.time == [year: 2026, month: 6, day: 16]
      assert Tempo.floating?(tempo)
    end

    test "compares with a holiday date written without a zone" do
      Test.put(~U[2026-12-24 20:00:00Z])

      # Already Christmas Day in Sydney.
      assert Tempo.relation(Tempo.today("Australia/Sydney"), ~o"2026-12-25") == :equals
    end
  end
end
