defmodule Tempo.SupervisorDocTest do
  use ExUnit.Case, async: true

  doctest Tempo.Supervisor
end

defmodule Tempo.SupervisorTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  # Tempo's application is stopped for each test, as for a host that sets
  # `runtime: false`, and started again after it.

  import Tempo.Sigils

  setup do
    :ok = Application.stop(:ex_tempo)
    on_exit(fn -> {:ok, _apps} = Application.ensure_all_started(:ex_tempo) end)
  end

  test "a host supervises Tempo's processes in its own tree" do
    refute Tempo.Supervisor.running?()

    start_supervised!(Tempo.Supervisor)

    assert Tempo.Supervisor.running?()
    assert {:ok, paris} = Tempo.shift_zone(~o"2026-06-15T10:00Z", "Europe/Paris")
    assert {:ok, ^paris} = Tempo.shift_zone(~o"2026-06-15T10:00Z", "Europe/Paris")
    assert {:ok, _later} = Tempo.shift_zone(~o"2040-06-15T10:00Z", "Europe/Paris")
  end

  test "with no Tempo process running, a zone is still answered, the same" do
    refute Tempo.Supervisor.running?()

    assert {:ok, without} = Tempo.shift_zone(~o"2026-06-15T10:00Z", "Europe/Paris")
    assert {:ok, later_without} = Tempo.shift_zone(~o"2040-06-15T10:00Z", "Europe/Paris")

    start_supervised!(Tempo.Supervisor)

    assert {:ok, ^without} = Tempo.shift_zone(~o"2026-06-15T10:00Z", "Europe/Paris")
    assert {:ok, ^later_without} = Tempo.shift_zone(~o"2040-06-15T10:00Z", "Europe/Paris")
  end
end
