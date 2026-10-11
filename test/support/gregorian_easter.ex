defmodule Tempo.GregorianEasterTest do
  @moduledoc false
  @test_data Path.join(__DIR__, "../support/data/easter500.txt")
             |> Path.expand()

  def data do
    @test_data
    |> File.read!()
    |> String.split("\r\n")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.split/1)
    |> Enum.reject(&(&1 == []))
    |> Enum.map(fn i -> Enum.map(i, &String.to_integer/1) end)
    |> Enum.map(fn [m, d, y] -> [y, m, d] end)
  end
end
