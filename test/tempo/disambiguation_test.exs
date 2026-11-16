defmodule Tempo.DisambiguationTest do
  use ExUnit.Case, async: true

  # A reading a zone's clock skips or shows twice, resolved as the caller
  # says with `:disambiguation` (decision 109). New York's clock goes from
  # 02:00 to 03:00 on 8 March 2026, so 02:30 is skipped, and from 02:00 back
  # to 01:00 on 1 November 2026, so 01:30 is shown twice. Each moment is held
  # to Elixir's `DateTime`, which reads the zone database apart from Tempo.

  import Tempo.Sigils

  @zone "America/New_York"
  @skipped "2026-03-08T02:30[America/New_York]"
  @repeated "2026-11-01T01:30[America/New_York]"

  defp read(text, options \\ []) do
    Tempo.from_iso8601(text, options)
  end

  defp instant({:ok, value}) do
    instant(value)
  end

  defp instant(%Tempo{} = value) do
    {:ok, date_time} = Tempo.to_datetime(value)
    DateTime.to_unix(date_time)
  end

  defp gap do
    {:gap, before, later} = DateTime.new(~D[2026-03-08], ~T[02:30:00], @zone)
    {DateTime.to_unix(before) + 1 - 30 * 60, DateTime.to_unix(later) + 30 * 60}
  end

  defp fold do
    {:ambiguous, first, second} = DateTime.new(~D[2026-11-01], ~T[01:30:00], @zone)
    {DateTime.to_unix(first), DateTime.to_unix(second)}
  end

  describe "with no disambiguation" do
    test "a skipped reading is refused, naming the offsets either side of the change" do
      assert {:error, %Tempo.ZoneError{reason: :gap} = error} = read(@skipped)
      assert error.offsets == [[hour: -5, minute: 0], [hour: -4, minute: 0]]
      assert Exception.message(error) =~ "going from -05:00 to -04:00"
      assert Exception.message(error) =~ "disambiguation: :compatible"
    end

    test "a repeated reading is its first showing" do
      {first, _second} = fold()
      assert instant(read(@repeated)) == first
    end
  end

  describe "reading a skipped reading" do
    test "after the change with :compatible and :later, before it with :earlier" do
      {before_change, after_change} = gap()

      assert read(@skipped, disambiguation: :compatible) ==
               {:ok, ~o"2026-03-08T03:30[America/New_York]"}

      assert instant(read(@skipped, disambiguation: :later)) == after_change

      assert read(@skipped, disambiguation: :earlier) ==
               {:ok, ~o"2026-03-08T01:30[America/New_York]"}

      assert instant(read(@skipped, disambiguation: :earlier)) == before_change
    end

    test "is refused with :reject" do
      assert {:error, %Tempo.ZoneError{reason: :gap}} = read(@skipped, disambiguation: :reject)
    end

    test "places a day the clock leaves out whole, as Samoa left out 30 December 2011" do
      text = "2011-12-30T10:00[Pacific/Apia]"

      assert read(text, disambiguation: :compatible) ==
               {:ok, ~o"2011-12-31T10:00[Pacific/Apia]"}

      assert read(text, disambiguation: :earlier) == {:ok, ~o"2011-12-29T10:00[Pacific/Apia]"}
    end
  end

  describe "reading a repeated reading" do
    test "is its first showing with :compatible and :earlier, its second with :later" do
      {first, second} = fold()

      assert instant(read(@repeated, disambiguation: :compatible)) == first
      assert instant(read(@repeated, disambiguation: :earlier)) == first
      assert instant(read(@repeated, disambiguation: :later)) == second
    end

    test "is refused with :reject, naming both offsets" do
      assert {:error, %Tempo.ZoneError{reason: :fold} = error} =
               read(@repeated, disambiguation: :reject)

      assert error.offsets == [[hour: -4, minute: 0], [hour: -5, minute: 0]]
      assert Exception.message(error) =~ "shows twice, at -04:00 and -05:00"
    end

    test "with a time shift is the showing the shift says, whatever the mode" do
      {_first, second} = fold()
      text = "2026-11-01T01:30-05:00[America/New_York]"

      for mode <- [:compatible, :earlier, :later, :reject] do
        assert instant(read(text, disambiguation: mode)) == second
      end
    end
  end

  describe "what is not a single reading" do
    test "a day, and an hour only part of which the clock skips, are periods" do
      for mode <- [:compatible, :earlier, :later, :reject] do
        assert read("2026-03-08[America/New_York]", disambiguation: mode) ==
                 read("2026-03-08[America/New_York]")

        # Lord Howe's clock goes from 02:00 to 02:30 on 2 October 2011.
        assert read("2011-10-02T02[Australia/Lord_Howe]", disambiguation: mode) ==
                 read("2011-10-02T02[Australia/Lord_Howe]")
      end
    end

    test "an hour the clock skips whole is placed as its minutes are" do
      assert read("2026-03-08T02[America/New_York]", disambiguation: :compatible) ==
               {:ok, ~o"2026-03-08T03[America/New_York]"}
    end
  end

  describe "an expression's parts" do
    test "the ends of an interval, the members of a set and a recurrence's start are each resolved" do
      assert read("2026-03-08T01:00/2026-03-08T02:30[America/New_York]",
               disambiguation: :compatible
             ) == {:ok, ~o"2026-03-08T01:00/2026-03-08T03:30[America/New_York]"}

      assert read("{2026-03-08T02:30,2026-03-09T02:30}[America/New_York]",
               disambiguation: :earlier
             ) == {:ok, ~o"{2026-03-08T01:30,2026-03-09T02:30}[America/New_York]"}

      assert {:ok, _} = read("R3/2026-03-08T02:30/P1D[America/New_York]", disambiguation: :later)

      assert {:error, %Tempo.ZoneError{reason: :fold}} =
               read("{2026-10-31T01:30,2026-11-01T01:30}[America/New_York]",
                 disambiguation: :reject
               )
    end

    test "a reading whose time shift :offset dropped is resolved too" do
      # Brazil dropped daylight saving in 2019; a 2018 text kept its -02:00.
      assert {:ok, _} =
               read("2020-01-15T12:00-02:00[America/Sao_Paulo]",
                 offset: :prefer,
                 disambiguation: :reject
               )
    end
  end

  describe "the builders" do
    test "Tempo.new/1 takes :disambiguation as the reader does" do
      parts = [year: 2026, month: 11, day: 1, hour: 1, minute: 30, zone: @zone]

      assert Tempo.new(parts ++ [disambiguation: :later]) ==
               read(@repeated, disambiguation: :later)

      assert {:error, %Tempo.ZoneError{reason: :fold}} =
               Tempo.new(parts ++ [disambiguation: :reject])
    end

    test "Tempo.in_zone/3 takes :disambiguation, and with none refuses a skipped reading" do
      floating = ~o"2026-03-08T02:30"

      assert {:error, %Tempo.ZoneError{reason: :gap}} = Tempo.in_zone(floating, @zone)

      assert Tempo.in_zone(floating, @zone, disambiguation: :earlier) ==
               read(@skipped, disambiguation: :earlier)
    end
  end

  describe "a shift that lands on a reading the clock skips or shows twice" do
    @before_gap ~o"2026-03-07T02:30[America/New_York]"
    @before_fold ~o"2026-10-31T01:30[America/New_York]"

    test "lands as :compatible by default" do
      {first, _second} = fold()

      assert Tempo.shift(@before_gap, day: 1) == {:ok, ~o"2026-03-08T03:30[America/New_York]"}
      assert instant(Tempo.shift(@before_fold, day: 1)) == first
    end

    test "lands before the change with :earlier, and on the second showing with :later" do
      {before_change, _after_change} = gap()
      {_first, second} = fold()

      assert instant(Tempo.shift(@before_gap, [day: 1], disambiguation: :earlier)) ==
               before_change

      assert instant(Tempo.shift(@before_fold, [day: 1], disambiguation: :later)) == second
    end

    test "is refused with :reject, naming the reading it landed on" do
      assert {:error, %Tempo.ZoneError{reason: :gap, value: value}} =
               Tempo.shift(@before_gap, [day: 1], disambiguation: :reject)

      # The reading cannot be built, being skipped, so its units are compared.
      assert value.form == {:value, [year: 2026, month: 3, day: 8, hour: 2, minute: 30]}
      assert value.zone.name == @zone

      assert {:error, %Tempo.ZoneError{reason: :fold}} =
               Tempo.shift(@before_fold, [day: 1], disambiguation: :reject)
    end

    test "steps the calendar first, then adds the clock's units as time that passes" do
      {before_change, _after_change} = gap()

      assert instant(Tempo.shift(@before_gap, [day: 1, hour: 1], disambiguation: :earlier)) ==
               before_change + 3600
    end
  end

  describe "the option" do
    test "is one of :compatible, :earlier, :later and :reject" do
      assert {:error, %ArgumentError{}} = read(@skipped, disambiguation: :maybe)
      assert {:error, %ArgumentError{}} = Tempo.new(year: 2026, disambiguation: "later")
      assert {:error, %ArgumentError{}} = Tempo.in_zone(~o"2026", @zone, disambiguation: 1)

      assert {:error, %ArgumentError{}} =
               Tempo.shift(~o"2026-03-07T02:30[America/New_York]", [day: 1],
                 disambiguation: :sooner
               )
    end

    test "is not taken by a shift through free time" do
      assert {:error, %ArgumentError{} = error} =
               Tempo.shift(~o"2026-03-07T02:30[America/New_York]", [day: 1],
                 disambiguation: :earlier,
                 skipping: ~o"2026-03-09[America/New_York]"
               )

      assert Exception.message(error) =~ "not both"
    end
  end
end
