defmodule Tempo.Iso8601.Parser.Data.Test do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Tokenizer.Time, as: TimeTokenizer

  @data "./test/support/data/iso8601_test_data.txt"
  @interval_data "./test/support/data/iso8601_range_test_data.txt"

  @all_tests @data
             |> File.read!()
             |> String.split("\n")
             |> Enum.with_index()
             |> Enum.reject(&String.starts_with?(elem(&1, 0), "#"))

  @time_tests @data
              |> File.read!()
              |> String.split("# Times")
              |> List.last()
              |> String.split("# Date-Times")
              |> List.first()
              |> String.split("\n")
              |> Enum.with_index()
              |> Enum.reject(&(String.starts_with?(elem(&1, 0), "#") or elem(&1, 0) == ""))

  @interval_tests @interval_data
                  |> File.read!()
                  |> String.split("\n")
                  |> Enum.map(
                    &(String.split(&1, "\t")
                      |> Enum.at(1))
                  )
                  |> Enum.with_index()
                  |> Enum.filter(&is_nil(elem(&1, 1)))

  @time_only_test [126, 136, 146, 159]

  for {test_date, line} <- @all_tests, line not in @time_only_test do
    test "line #{line}: parse #{inspect(test_date)}" do
      assert {:ok, _} = Tempo.from_iso8601(unquote(test_date))
    end
  end

  for {test_time, line} <- @time_tests do
    test "line #{line}: parse as time #{inspect(test_time)}" do
      assert {:ok, _, "", _, _, _} = TimeTokenizer.time_parser(unquote(test_time))
    end
  end

  for {test_interval, line} <- @interval_tests do
    test "line #{line}: parse interval #{inspect(test_interval)}" do
      assert {:ok, _} = Tempo.from_iso8601(unquote(test_interval))
    end
  end
end
