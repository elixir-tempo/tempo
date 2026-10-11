defmodule Tempo.LeapSeconds do
  @moduledoc """
  The canonical list of positive leap seconds announced by the
  International Earth Rotation and Reference Systems Service
  (IERS) since the UTC–TAI framework began in 1972.

  A leap second is inserted as `23:59:60` at the end of either
  June 30 or December 31 UTC. The values below are the official
  IERS Bulletin C insertion dates; there have been 27 positive
  leap seconds to date and no negative ones.

  This module is the reference used by
  `Tempo.Interval.spans_leap_second?/1` and
  `Tempo.Interval.leap_seconds_spanned/1` to detect whether a
  half-open interval contains a real IERS insertion.

  The data is static; IERS publishes new bulletins twice a year,
  and when a new leap second is announced (or negative ones
  adopted — the CGPM agreed in 2022 to phase leap seconds out by
  2035) the list should be extended and a new Tempo release cut.

  """

  # Dates on which a positive leap second was inserted (the
  # second after 23:59:59 UTC was labelled 23:59:60).
  @leap_second_dates [
    {1972, 6, 30},
    {1972, 12, 31},
    {1973, 12, 31},
    {1974, 12, 31},
    {1975, 12, 31},
    {1976, 12, 31},
    {1977, 12, 31},
    {1978, 12, 31},
    {1979, 12, 31},
    {1981, 6, 30},
    {1982, 6, 30},
    {1983, 6, 30},
    {1985, 6, 30},
    {1987, 12, 31},
    {1989, 12, 31},
    {1990, 12, 31},
    {1992, 6, 30},
    {1993, 6, 30},
    {1994, 6, 30},
    {1995, 12, 31},
    {1997, 6, 30},
    {1998, 12, 31},
    {2005, 12, 31},
    {2008, 12, 31},
    {2012, 6, 30},
    {2015, 6, 30},
    {2016, 12, 31}
  ]

  @leap_second_set MapSet.new(@leap_second_dates)

  @doc """
  Return the list of `{year, month, day}` tuples on which a
  positive leap second has been inserted.

  ### Examples

      iex> {2016, 12, 31} in Tempo.LeapSeconds.dates()
      true

      iex> length(Tempo.LeapSeconds.dates())
      27

  """
  # Dialyzer narrows the inferred type to the specific year
  # literals in the data, which is a strict subtype of our
  # published spec. `integer()` is the humanly-correct API type;
  # suppress the supertype warning rather than pin callers to
  # whatever year we happen to list today.
  @dialyzer {:nowarn_function, dates: 0}

  @spec dates() :: [{integer(), 1..12, 1..31}, ...]
  def dates, do: @leap_second_dates

  @doc """
  Return `true` when a positive leap second was inserted at the
  end of the given UTC date (i.e. `23:59:60 UTC` exists on that
  day).

  ### Arguments

  * `year`, `month`, `day` are integers. Month must be 6 or 12
    and day must be 30 or 31 respectively for any leap second to
    have been possible — other inputs return `false`.

  ### Examples

      iex> Tempo.LeapSeconds.on_date?(2016, 12, 31)
      true

      iex> Tempo.LeapSeconds.on_date?(2026, 12, 31)
      false

      iex> Tempo.LeapSeconds.on_date?(2016, 6, 30)
      false

  """
  @spec on_date?(integer(), integer(), integer()) :: boolean()
  def on_date?(year, month, day) do
    MapSet.member?(@leap_second_set, {year, month, day})
  end

  @doc """
  Return the most recent `{year, month, day}` on which a leap
  second was inserted.

  Useful for documentation, UI, and "are we likely to hit a leap
  second soon?" reasoning. Not used by the validator.

  ### Examples

      iex> Tempo.LeapSeconds.latest()
      {2016, 12, 31}

  """
  @spec latest() :: {integer(), 1..12, 1..31}
  def latest do
    @leap_second_dates
    |> Enum.max_by(fn {y, m, d} -> {y, m, d} end)
  end

  @doc """
  Return the list of `{year, month, day}` tuples on which a
  **negative** leap second has been announced.

  A negative leap second *removes* the final second of a UTC
  day — the second numbered 58 is followed directly by 00 of
  the next minute, with no 59. No negative leap second has ever
  been used since UTC–TAI began in 1972, but the CGPM agreed
  in 2022 that they may become necessary from roughly 2035
  onwards (and that the leap-second mechanism will be replaced
  entirely by around 2035–2040).

  The list is empty today. When IERS announces one, it will be
  added here, and interval-level detection via
  `Tempo.Interval.spans_leap_second?/1` will cover both positive
  and negative insertions. Negative leap seconds will contribute
  a `-1` second to `Tempo.Interval.duration(iv, leap_seconds: true)`
  rather than `+1`.

  ### Examples

      iex> Tempo.LeapSeconds.removals()
      []

  """
  # Dialyzer narrows `removals/0` to the empty-list literal; the
  # spec is the humanly-correct API type so callers can plan for
  # a non-empty future without the nowarn suppression flipping.
  @dialyzer {:nowarn_function, removals: 0}
  @spec removals() :: [{integer(), 1..12, 1..31}]
  def removals, do: []
end
