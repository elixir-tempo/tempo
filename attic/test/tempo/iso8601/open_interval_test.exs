defmodule Tempo.Iso8601.OpenInterval.Test do
  use ExUnit.Case, async: true

  # Open-ended intervals are an EDTF / ISO 8601-2 feature central to
  # expressing "from date onwards", "up to date", or "entire timeline"
  # — common in archaeology ("occupied from 1200 BCE onwards"),
  # stratigraphy, and versioning systems.

  describe "open upper endpoint" do
    test "date/.. — from date, open end" do
      assert {:ok, %Tempo.Interval{from: %Tempo{}, to: :undefined}} =
               Tempo.from_iso8601("1985/..")
    end

    test "date/ — trailing slash is equivalent to /.." do
      assert {:ok, %Tempo.Interval{from: %Tempo{}, to: :undefined}} =
               Tempo.from_iso8601("1985/")
    end

    test "year-month-day/" do
      assert {:ok, %Tempo.Interval{from: %Tempo{}, to: :undefined}} =
               Tempo.from_iso8601("1985-04-12/")
    end

    test "negative year/.." do
      assert {:ok, %Tempo.Interval{from: %Tempo{}, to: :undefined}} =
               Tempo.from_iso8601("-1985/..")
    end
  end

  describe "open lower endpoint" do
    test "../date" do
      assert {:ok, %Tempo.Interval{from: :undefined, to: %Tempo{}}} =
               Tempo.from_iso8601("../1985")
    end

    test "/date — leading slash equivalent" do
      assert {:ok, %Tempo.Interval{from: :undefined, to: %Tempo{}}} =
               Tempo.from_iso8601("/1985")
    end

    test "/year-month-day" do
      assert {:ok, %Tempo.Interval{from: :undefined, to: %Tempo{}}} =
               Tempo.from_iso8601("/1985-04-12")
    end
  end

  describe "both endpoints open" do
    test "../.. entire timeline" do
      assert {:ok, %Tempo.Interval{from: :undefined, to: :undefined}} =
               Tempo.from_iso8601("../..")
    end

    test "/.. — open both ways" do
      assert {:ok, %Tempo.Interval{from: :undefined, to: :undefined}} =
               Tempo.from_iso8601("/..")
    end

    test "../ — open both ways" do
      assert {:ok, %Tempo.Interval{from: :undefined, to: :undefined}} =
               Tempo.from_iso8601("../")
    end

    test "/ — bare slash" do
      assert {:ok, %Tempo.Interval{from: :undefined, to: :undefined}} =
               Tempo.from_iso8601("/")
    end
  end

  describe "interaction with qualification" do
    test "qualified endpoint with open upper" do
      assert {:ok, %Tempo.Interval{from: from, to: :undefined}} =
               Tempo.from_iso8601("1984?/..")

      assert Tempo.qualification(from) == :uncertain
    end

    test "open lower with qualified endpoint" do
      assert {:ok, %Tempo.Interval{from: :undefined, to: to}} =
               Tempo.from_iso8601("../1984?")

      assert Tempo.qualification(to) == :uncertain
    end
  end
end
