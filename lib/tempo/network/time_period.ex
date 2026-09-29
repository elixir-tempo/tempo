defmodule Tempo.Network.TimePeriod do
  @moduledoc """
  A single time-period in a chronological network — a reign, era, or
  the time-span of a stratum.

  Following the ChronoLog data model (Levy et al. 2020), a period
  carries **independent** bounds on three quantities, each of which may
  be unknown (`nil`), known, lower-bounded, upper-bounded, or known
  within a range:

  * its **start** — `earliest_start`..`latest_start`;

  * its **end** — `earliest_end`..`latest_end`;

  * its **duration** — `min_duration`..`max_duration`.

  Duration is modelled separately from the start/end pair (it is not
  forced to equal `end - start` at construction time); the solver
  reconciles all three through the constraint `end - start ∈
  [min_duration, max_duration]`.

  Start/end bounds are `t:Tempo.t/0` values (so they carry their own
  calendar and resolution); duration bounds are `t:Tempo.Duration.t/0`.
  An EDTF/ISO 8601 string or a bare integer year is accepted by the
  constructor and normalised to the corresponding Tempo value.

  """

  alias Tempo.Network.TimePeriod

  @typedoc "A start/end bound: a Tempo value, or `nil` when unknown."
  @type date_bound :: Tempo.t() | nil

  @typedoc "A duration bound: a Tempo duration, or `nil` when unknown."
  @type duration_bound :: Tempo.Duration.t() | nil

  @type t :: %__MODULE__{
          id: term(),
          name: String.t() | nil,
          earliest_start: date_bound(),
          latest_start: date_bound(),
          earliest_end: date_bound(),
          latest_end: date_bound(),
          min_duration: duration_bound(),
          max_duration: duration_bound(),
          metadata: map()
        }

  defstruct id: nil,
            name: nil,
            earliest_start: nil,
            latest_start: nil,
            earliest_end: nil,
            latest_end: nil,
            min_duration: nil,
            max_duration: nil,
            metadata: %{}

  @doc """
  Build a time-period.

  ### Arguments

  * `id` is any term uniquely identifying the period within its
    network (commonly an atom such as `:k1` or a string).

  * `options` is a keyword list of options.

  ### Options

  * `:name` is a human-readable label.

  * `:from` constrains when the period starts. It accepts an exact
    value, a `{lower, upper}` range, `{:not_before, value}`, or
    `{:not_after, value}` (see "Bound specifications").

  * `:to` constrains when the period ends, with the same shapes as
    `:from`.

  * `:duration` constrains the duration. It accepts an exact duration,
    a `{min, max}` range, `{:at_least, duration}`, or
    `{:at_most, duration}`.

  * `:metadata` is an arbitrary map carried with the period (EDTF
    qualifiers, provenance, notes). It does not affect the solver.

  ### Bound specifications

  A date value is a `t:Tempo.t/0` — idiomatically a sigil literal such
  as `~o"1200Y"`, `~o"-664Y"`, or `~o"1200-06-15"`. As a year-grained
  convenience an EDTF/ISO 8601 string (`"1200Y"`) or a bare integer year
  (`1200`, `-664` for BCE) is also accepted and normalised to the
  corresponding Tempo value.

  A duration value is a `t:Tempo.Duration.t/0` (`~o"P20Y"`); an ISO 8601
  duration string (`"P20Y"`) or a bare integer number of years is
  likewise accepted.

  All bounds are stored, and returned, as Tempo values.

  ### Returns

  * `{:ok, period}`.

  * `{:error, reason}` for an option `new/2` does not take — 1.x's
    `:start` and `:end` included, now `:from` and `:to` — or a bound
    that is not a date or a duration.

  ### Examples

      iex> {:ok, period} = Tempo.Network.TimePeriod.new(:k1, name: "King 1", from: {:not_before, ~o"1200Y"})
      iex> {period.id, period.name, period.earliest_start}
      {:k1, "King 1", ~o"1200Y"}

      iex> {:ok, period} = Tempo.Network.TimePeriod.new(:s1, duration: {:at_least, ~o"P20Y"})
      iex> period.min_duration
      ~o"P20Y"

      iex> {:error, %ArgumentError{} = error} = Tempo.Network.TimePeriod.new(:k1, start: ~o"1200Y")
      iex> Exception.message(error)
      "Tempo.Network.TimePeriod.new/2 takes :from where 1.x took :start."

  """
  @spec new(term(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(id, options \\ []) do
    with :ok <- known_options(options),
         {:ok, {start_lower, start_upper}} <- date_bounds(Keyword.get(options, :from)),
         {:ok, {end_lower, end_upper}} <- date_bounds(Keyword.get(options, :to)),
         {:ok, {min_duration, max_duration}} <- duration_bounds(Keyword.get(options, :duration)),
         {:ok, name} <- name_option(Keyword.get(options, :name)),
         {:ok, metadata} <- metadata_option(Keyword.get(options, :metadata, %{})) do
      {:ok,
       %TimePeriod{
         id: id,
         name: name,
         earliest_start: start_lower,
         latest_start: start_upper,
         earliest_end: end_lower,
         latest_end: end_upper,
         min_duration: min_duration,
         max_duration: max_duration,
         metadata: metadata
       }}
    end
  end

  @doc """
  Build a time-period, raising on an error.

  ### Arguments

  * `id` is any term uniquely identifying the period.

  * `options` is a keyword list of options, as for `new/2`.

  ### Options

  * The options of `new/2`.

  ### Returns

  * A `t:t/0`, or raises the error `new/2` returns.

  ### Examples

      iex> Tempo.Network.TimePeriod.new!(:k1, to: {:not_after, 1300}).latest_end
      ~o"1300Y"

  """
  @spec new!(term(), keyword()) :: t()
  def new!(id, options \\ []) do
    case new(id, options) do
      {:ok, period} -> period
      {:error, exception} -> raise exception
    end
  end

  @doc """
  The integer year of a date bound, or `nil`.

  A convenience for tests and traces; the solver works at the network's
  finest unit rather than always in years.

  ### Examples

      iex> Tempo.Network.TimePeriod.year(~o"1200Y")
      1200

      iex> Tempo.Network.TimePeriod.year(nil)
      nil

  """
  @spec year(date_bound()) :: integer() | nil
  def year(nil), do: nil
  def year(%Tempo{time: time}), do: Keyword.get(time, :year)

  # --- options ---------------------------------------------------

  @options [:name, :from, :to, :duration, :metadata]
  @renamed %{start: :from, end: :to}

  defp known_options(options) do
    if Keyword.keyword?(options) do
      options |> Keyword.keys() |> Enum.find(&(&1 not in @options)) |> unknown_option()
    else
      {:error, invalid("takes a keyword list of options, not #{inspect(options)}")}
    end
  end

  defp unknown_option(nil), do: :ok

  defp unknown_option(key) when is_map_key(@renamed, key),
    do: {:error, invalid("takes #{inspect(@renamed[key])} where 1.x took #{inspect(key)}")}

  defp unknown_option(key),
    do: {:error, invalid("does not take #{inspect(key)}; its options are #{inspect(@options)}")}

  defp name_option(name) when is_binary(name) or is_nil(name), do: {:ok, name}
  defp name_option(name), do: {:error, invalid("takes a string :name, not #{inspect(name)}")}

  defp metadata_option(metadata) when is_map(metadata), do: {:ok, metadata}

  defp metadata_option(metadata),
    do: {:error, invalid("takes a map as :metadata, not #{inspect(metadata)}")}

  defp invalid(phrase), do: ArgumentError.exception("Tempo.Network.TimePeriod.new/2 #{phrase}.")

  # --- bound normalisation ---------------------------------------

  # No constraint supplied.
  defp date_bounds(nil), do: {:ok, {nil, nil}}
  defp date_bounds({:not_before, value}), do: bounds(to_tempo(value), {:ok, nil})
  defp date_bounds({:not_after, value}), do: bounds({:ok, nil}, to_tempo(value))
  defp date_bounds({lower, upper}), do: bounds(to_tempo(lower), to_tempo(upper))
  defp date_bounds(exact), do: bounds(to_tempo(exact), to_tempo(exact))

  defp duration_bounds(nil), do: {:ok, {nil, nil}}
  defp duration_bounds({:at_least, value}), do: bounds(to_duration(value), {:ok, nil})
  defp duration_bounds({:at_most, value}), do: bounds({:ok, nil}, to_duration(value))
  defp duration_bounds({min, max}), do: bounds(to_duration(min), to_duration(max))
  defp duration_bounds(exact), do: bounds(to_duration(exact), to_duration(exact))

  defp bounds({:ok, lower}, {:ok, upper}), do: {:ok, {lower, upper}}
  defp bounds({:error, _reason} = error, _upper), do: error
  defp bounds(_lower, {:error, _reason} = error), do: error

  defp to_tempo(nil), do: {:ok, nil}
  defp to_tempo(%Tempo{} = value), do: {:ok, value}
  defp to_tempo(year) when is_integer(year), do: parsed("#{year}Y", Tempo, year)
  defp to_tempo(string) when is_binary(string), do: parsed(string, Tempo, string)
  defp to_tempo(other), do: {:error, invalid("takes a date as a bound, not #{inspect(other)}")}

  defp to_duration(nil), do: {:ok, nil}
  defp to_duration(%Tempo.Duration{} = value), do: {:ok, value}
  defp to_duration(years) when is_integer(years), do: parsed("P#{years}Y", Tempo.Duration, years)
  defp to_duration(string) when is_binary(string), do: parsed(string, Tempo.Duration, string)

  defp to_duration(other),
    do: {:error, invalid("takes a duration as a bound, not #{inspect(other)}")}

  # A string or a number read as a date or a duration, which must parse
  # to the kind of value the bound needs.
  defp parsed(string, kind, given) do
    case Tempo.from_iso8601(string) do
      {:ok, %^kind{} = value} -> {:ok, value}
      _other -> {:error, invalid("cannot read #{inspect(given)} as a #{describe(kind)}")}
    end
  end

  defp describe(Tempo), do: "date"
  defp describe(Tempo.Duration), do: "duration"
end
