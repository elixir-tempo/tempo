defmodule Tempo.Reader.OverflowTest do
  use ExUnit.Case, async: true

  # A value written with a part out of its range: refused by default, and
  # carried into range with `overflow: :carry`, as ISO 8601-2's Amendment 1
  # (2025, §14.5 and D.3.1) reads it.

  import Tempo.Sigils

  defp carried(text) do
    Tempo.from_iso8601(text, overflow: :carry)
  end

  describe "by default" do
    test "a part out of range is an error" do
      for text <- ["2018Y13M", "2020Y2M59D", "2026-02-30", "2026-06-15T26:00"] do
        assert {:error, %Tempo.InvalidDateError{}} = Tempo.from_iso8601(text)
      end
    end

    test "a part of zero is an error, never a crash" do
      for text <- ["2020Y3M0D", "2020-03-00", "2020Y0M", "2020Y0O", "2020Y1W0K", "2020Y3M{0,1}D"] do
        assert {:error, %Tempo.InvalidDateError{reason: {:out_of_range, 0, _}}} =
                 Tempo.from_iso8601(text)
      end
    end
  end

  describe "with overflow: :carry" do
    test "the amendment's examples carry to the dates it gives" do
      assert carried("2018Y13M") == {:ok, ~o"2019-01"}
      assert carried("2018Y12M366D") == {:ok, ~o"2019-12-01"}

      for text <- ["2020Y3M30D", "2020Y2M59D", "2019Y3M396D"] do
        assert carried(text) == {:ok, ~o"2020-03-30"}
      end
    end

    test "a value keeps the form it was written in" do
      assert carried("2020Y367O") == {:ok, ~o"2021-001"}
      assert carried("2026Y54W") == {:ok, ~o"2027-W01"}
      assert carried("2026Y25W8K") == {:ok, ~o"2026-W26-1"}
    end

    test "the clock carries into the date, a day zero borrows from the month before" do
      assert carried("2026-06-15T26:00") == {:ok, ~o"2026-06-16T02:00"}
      assert carried("2026-06-15T23:90") == {:ok, ~o"2026-06-16T00:30"}
      assert carried("2026-06-15T26:00+05:00") == {:ok, ~o"2026-06-16T02:00+05:00"}
      assert carried("2020Y3M0D") == {:ok, ~o"2020-02-29"}
    end

    test "every value of an interval, a set and a recurrence is carried" do
      assert carried("2026-02-30/2026-03-35") == {:ok, ~o"2026-03-02/2026-04-04"}
      assert carried("{2026-02-30,2026-04-31}") == {:ok, ~o"{2026-03-02,2026-05-01}"}
      assert carried("R2/2026-01-32/P1D") == {:ok, ~o"R2/2026-02-01/P1D"}
    end

    test "a negative day still counts back from the end of its month" do
      assert carried("2020Y4M-1D") == {:ok, ~o"2020Y4M-1D"}

      assert {:error, %Tempo.InvalidDateError{unit: :day}} = carried("2024Y3M-300D")
    end

    test "a time with no date has no day to carry into" do
      assert {:error, %Tempo.InvalidDateError{unit: :hour}} = carried("T26H")
    end

    test "a value in range is as it was written" do
      assert carried("2026-06-15T10:30") == {:ok, ~o"2026-06-15T10:30"}
    end
  end

  test "overflow takes :refuse or :carry" do
    assert {:error, %ArgumentError{}} = Tempo.from_iso8601("2018Y13M", overflow: :wrap)
  end
end
