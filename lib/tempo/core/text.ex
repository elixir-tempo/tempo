defmodule Tempo.Text do
  @moduledoc false
  # Reading that goes beyond the ISO 8601 grammar: a profile the caller
  # declares for a text, and a locale's own words for a date or a time.

  alias Tempo.{Duration, Interval, ParseError, Reader, Unit}

  @profiles [:date, :time, :datetime, :interval, :duration]

  @doc "Reads an ISO 8601 text, admitting only the profile the caller declares when one is given."
  @spec read(String.t(), keyword()) :: {:ok, Tempo.t() | Duration.t()} | {:error, Exception.t()}
  def read(text, options) do
    {profile, options} = Keyword.pop(options, :profile)

    with {:ok, read} <- Reader.read(text, options), do: of_profile(read, profile, text)
  end

  defp of_profile(read, nil, _text), do: {:ok, read}

  defp of_profile(read, profile, text) when profile in @profiles do
    if profile?(read, profile),
      do: {:ok, read},
      else: {:error, ParseError.exception(text: text, rest: text, reason: "not a #{profile}")}
  end

  defp of_profile(_read, profile, text) do
    {:error,
     ParseError.exception(
       text: text,
       rest: text,
       reason: "#{inspect(profile)} is not a profile; one is of #{inspect(@profiles)}"
     )}
  end

  defp profile?(%Duration{}, :duration), do: true
  defp profile?(%Tempo{form: {kind, _, _}}, :interval) when kind == :span, do: true
  defp profile?(%Tempo{form: {:every, _, _, _}}, :interval), do: true

  defp profile?(%Tempo{form: {:value, units}}, profile)
       when profile in [:date, :time, :datetime] do
    case {Unit.date_units(units), Unit.clock_units(units)} do
      {[_ | _], []} -> profile == :date
      {[], [_ | _]} -> profile == :time
      {[_ | _], [_ | _]} -> profile == :datetime
      _ -> false
    end
  end

  defp profile?(_read, _profile), do: false

  @doc "Reads a text as ISO 8601, and failing that as a locale's words for a date, a time or a range."
  @spec parse(String.t(), keyword()) :: {:ok, Tempo.t() | Duration.t()} | {:error, Exception.t()}
  def parse(text, options) do
    case read(text, Keyword.take(options, [:calendar, :profile])) do
      {:ok, read} -> {:ok, read}
      {:error, %ParseError{} = error} -> words(text, options, error)
      {:error, _} = error -> error
    end
  end

  # The locale's words, through Calendrical, as the units they name.
  defp words(text, options, error) do
    as_fields =
      options |> Keyword.take([:locale, :calendar, :reference_date]) |> Keyword.put(:as, :map)

    case Calendrical.parse(text, Keyword.put_new(as_fields, :calendar, Calendar.ISO)) do
      {:ok, {%{} = from, %{} = to}} -> between(from, to)
      {:ok, %{} = fields} -> Tempo.new(named(fields))
      _not_words -> {:error, error}
    end
  end

  defp between(from, to) do
    with {:ok, from} <- Tempo.new(named(from)),
         {:ok, to} <- Tempo.new(named(to)),
         do: Interval.new(from: from, to: to)
  end

  # Calendrical's fields as Tempo's units: a zone by name, UTC as a zero shift.
  defp named(fields) do
    {zone, fields} = Map.pop(fields, :time_zone)
    fields = Map.drop(fields, [:microsecond, :zone_abbr, :utc_offset, :std_offset])

    case zone do
      nil -> fields
      "Etc/UTC" -> Map.put(fields, :shift, hour: 0)
      name -> Map.put(fields, :zone, name)
    end
  end
end
