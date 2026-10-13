defmodule Tempo.Core.ZoneTest do
  use ExUnit.Case, async: true

  alias Tempo.Zone

  @second 1_000_000
  @hour 3600 * @second

  defp wall(naive), do: NaiveDateTime.to_gregorian_seconds(naive) |> elem(0) |> Kernel.*(@second)

  test "a named zone is checked against the database and a fixed offset is not" do
    assert {:ok, %Zone{name: "Europe/Paris"}} = Zone.named("Europe/Paris")
    assert {:error, %Tempo.ZoneError{reason: :unknown}} = Zone.named("Mars/Olympus")
    assert %Zone{offset: 330} = Zone.fixed(330)
  end

  test "a written shift carries its sign on its first unit that is not zero" do
    assert Zone.shift_ticks(hour: 2) == 2 * @hour
    assert Zone.shift_ticks(hour: -5, minute: 30) == -(5 * @hour + 30 * 60 * @second)
    assert Zone.shift_ticks(hour: 0, minute: -30) == -30 * 60 * @second
  end

  test "a wall reading has one offset, none in a gap, two in a fold" do
    {:ok, paris} = Zone.named("Europe/Paris")
    assert Zone.offsets_at_wall(paris, wall(~N[2026-06-15 10:00:00])) == [2 * @hour]

    assert Zone.offsets_at_wall(paris, wall(~N[2026-03-29 02:30:00])) ==
             {:gap, 1 * @hour, 2 * @hour}

    assert Zone.offsets_at_wall(paris, wall(~N[2026-10-25 02:30:00])) == [2 * @hour, 1 * @hour]
    assert Zone.offsets_at_wall(Zone.fixed(330), 0) == [330 * 60 * @second]
  end

  test "a value is placed by its shift, else the first offset, else the clock before a change" do
    {:ok, paris} = Zone.named("Europe/Paris")
    fold = wall(~N[2026-10-25 02:30:00])
    gap = wall(~N[2026-03-29 02:30:00])
    assert Zone.offset_at_wall(paris, nil, fold) == 2 * @hour
    assert Zone.offset_at_wall(paris, [hour: 1], fold) == 1 * @hour
    assert Zone.offset_at_wall(paris, nil, gap) == 1 * @hour
    assert Zone.offset_at_wall(nil, nil, gap) == 0

    assert Zone.utc_of_wall(paris, nil, wall(~N[2026-06-15 10:00:00])) ==
             wall(~N[2026-06-15 08:00:00])
  end

  test "a UTC tick is shown as a wall reading with the offset it has there" do
    {:ok, paris} = Zone.named("Europe/Paris")

    assert Zone.wall_of_utc(paris, nil, wall(~N[2026-06-15 08:00:00])) ==
             {wall(~N[2026-06-15 10:00:00]), 2 * @hour}

    assert Zone.offset_at_utc(paris, wall(~N[2026-01-15 08:00:00])) == 1 * @hour
    assert Zone.wall_of_utc(nil, [hour: -5], 0) == {-5 * @hour, -5 * @hour}
  end
end
