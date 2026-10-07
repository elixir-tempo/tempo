defmodule Tempo.Iso8601.IntervalEndOrderTest do
  @moduledoc """
  An interval's ends, ordered by where each starts.

  An interval runs from where its start starts to where its end starts, so
  an end that starts before its start does is no interval, and is refused
  (decided 2026-10-08). The ends were ordered by where the end's own span
  ends, which read an end coarser than its start that holds it
  (`2004-06-11/2004-06`, a day of June to June) as an interval that ends
  ten days before it starts and holds nothing. EDTF's corpus lists four
  such as invalid.

  The measure is where each end starts, written by hand as Elixir's own
  `NaiveDateTime` or `DateTime`: an interval is read where its end does not
  start before its start.
  """
  use ExUnit.Case, async: true

  alias Tempo.Interval
  alias Tempo.IntervalEndpointsError

  # An end as it is written, and where it starts.
  @ends [
    {"2003-12-31", ~N[2003-12-31 00:00:00]},
    {"2004", ~N[2004-01-01 00:00:00]},
    {"2004-01-01", ~N[2004-01-01 00:00:00]},
    {"2004-06", ~N[2004-06-01 00:00:00]},
    {"2004-06-01", ~N[2004-06-01 00:00:00]},
    {"2004-W24", ~N[2004-06-07 00:00:00]},
    {"2004-06-11", ~N[2004-06-11 00:00:00]},
    {"2004-163", ~N[2004-06-11 00:00:00]},
    {"2004-06-11T00:00", ~N[2004-06-11 00:00:00]},
    {"2004-06-11T10", ~N[2004-06-11 10:00:00]},
    {"2004-06-11T10:30", ~N[2004-06-11 10:30:00]},
    {"2004-06-11T10:30:15", ~N[2004-06-11 10:30:15]},
    {"2004-07", ~N[2004-07-01 00:00:00]},
    {"2005", ~N[2005-01-01 00:00:00]}
  ]

  ## The measure

  defp to_say(from_starts, to_starts, compare) do
    if compare.(to_starts, from_starts) == :lt, do: :refused, else: :read
  end

  defp said({:ok, %Interval{}}), do: :read
  defp said({:ok, %Tempo.Set{}}), do: :read
  defp said({:error, %IntervalEndpointsError{operation: :validate}}), do: :refused

  describe "an interval written with a year at each end" do
    test "is read where its end does not start before its start, and refused where it does" do
      # Where a week and a day of the year start, by Elixir's own calendar.
      assert :calendar.iso_week_number({2004, 6, 7}) == {2004, 24}
      assert Date.day_of_week(~D[2004-06-07]) == 1
      assert Date.day_of_year(~D[2004-06-11]) == 163

      verdicts =
        for {from, from_starts} <- @ends, {to, to_starts} <- @ends do
          text = from <> "/" <> to
          expected = to_say(from_starts, to_starts, &NaiveDateTime.compare/2)

          assert {text, said(Tempo.from_iso8601(text))} == {text, expected}

          expected
        end

      # Each pair of ends that start apart is refused one way round: the
      # ninety-one pairs of fourteen ends, less the five that start together
      # (two on 1 January, two on 1 June, and three on 11 June, which are
      # three pairs).
      assert Enum.frequencies(verdicts) == %{refused: 86, read: 14 * 14 - 86}
    end

    test "is refused where its end is coarser than its start and holds it, as EDTF has it" do
      for text <- [
            "2004-06-11/2004-06",
            "0000-01-03/0000-01",
            "0000-02/0000",
            "2004-06-11%/2004-%06",
            "2004-06-11%/2004-06~",
            "-0044-03-15/-0044",
            "2004-06-11T10:30/2004-06-11"
          ] do
        assert {text, said(Tempo.from_iso8601(text))} == {text, :refused}
      end

      # An end that starts where its start does is read, whatever it is
      # written to.
      for text <- ["1111-01-01/1111", "0000/0000", "-0044-01-01/-0044", "2004-01-01T00:00/2004"] do
        assert {text, said(Tempo.from_iso8601(text))} == {text, :read}
      end
    end

    test "says that the end starts before the start, and names the interval" do
      assert {:error, %IntervalEndpointsError{interval: %Interval{} = interval} = error} =
               Tempo.from_iso8601("2004-06-11/2004-06")

      assert Exception.message(error) == "interval :to endpoint starts before its :from endpoint"
      assert inspect(interval) == ~s|~o"2004Y6M11D/2004Y6M"|
    end
  end

  describe "ends on clocks that are apart" do
    # An interval as it is written, and where each end starts.
    @placed [
      # 10:30 two hours ahead of UTC is 08:30 there.
      {"2026-06-15T10:30+02:00/2026-06-15T09:00Z", ~U[2026-06-15 08:30:00Z],
       ~U[2026-06-15 09:00:00Z]},
      {"2026-06-15T10:30+02:00/2026-06-15T08:30Z", ~U[2026-06-15 08:30:00Z],
       ~U[2026-06-15 08:30:00Z]},
      {"2026-06-15T10:30+02:00/2026-06-15T08:00Z", ~U[2026-06-15 08:30:00Z],
       ~U[2026-06-15 08:00:00Z]},
      {"2026-06-15T10:30+02:00/2026-06-15T08Z", ~U[2026-06-15 08:30:00Z],
       ~U[2026-06-15 08:00:00Z]},
      {"2026-06-15T10:30+02:00/2026-06-15T09Z", ~U[2026-06-15 08:30:00Z],
       ~U[2026-06-15 09:00:00Z]}
    ]

    # A time of day in Paris to the day in New York, which starts six hours
    # after Paris's does.
    @paris_times [~T[05:30:00], ~T[06:00:00], ~T[06:30:00], ~T[10:30:00]]

    test "are ordered on the one time line" do
      for {text, from_starts, to_starts} <- @placed do
        assert {text, said(Tempo.from_iso8601(text))} ==
                 {text, to_say(from_starts, to_starts, &DateTime.compare/2)}
      end

      new_york = DateTime.new!(~D[2026-06-15], ~T[00:00:00], "America/New_York")

      for time <- @paris_times do
        text =
          "2026-06-15T#{Calendar.strftime(time, "%H:%M")}[Europe/Paris]/2026-06-15[America/New_York]"

        paris = DateTime.new!(~D[2026-06-15], time, "Europe/Paris")

        assert {text, said(Tempo.from_iso8601(text))} ==
                 {text, to_say(paris, new_york, &DateTime.compare/2)}
      end

      # Two of the four are refused: half past six and half past ten.
      assert Enum.map(
               @paris_times,
               &DateTime.compare(new_york, DateTime.new!(~D[2026-06-15], &1, "Europe/Paris"))
             ) ==
               [:gt, :eq, :lt, :lt]
    end
  end

  describe "an interval in another calendar, in a set and in a recurrence" do
    test "is held to the same order" do
      assert said(Tempo.from_iso8601("5786-06-11/5786-06[u-ca=hebrew]")) == :refused
      assert said(Tempo.from_iso8601("5786-06-01/5786-06[u-ca=hebrew]")) == :read

      for text <- ["{2004-06-11/2004-06}", "[2004-06-11/2004-06]", "R3/2004-06-11/2004-06"] do
        assert {text, said(Tempo.from_iso8601(text))} == {text, :refused}
      end

      for text <- ["{2004-06-01/2004-06}", "[2004-06-11/2004-07]", "R3/2004-06-11/2004-07"] do
        assert {text, said(Tempo.from_iso8601(text))} == {text, :read}
      end
    end
  end

  describe "an end that names several values, or no year" do
    test "has no one place to start, and is read as it was" do
      for text <- [
            "2004-06-11/2004-06-XX",
            "2004-06-11/2004-{05,06}",
            "2004Y6M11D/2004Y2Q",
            "1919-XX-02/1919-XX-01",
            "T22/T02",
            "T10:30/T10"
          ] do
        assert {text, said(Tempo.from_iso8601(text))} == {text, :read}
      end
    end
  end
end
