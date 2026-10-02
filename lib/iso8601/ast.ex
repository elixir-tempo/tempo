defmodule Tempo.Iso8601.AST do
  @moduledoc false

  # Internal builder that converts tokenizer-emitted AST shapes into
  # `%Tempo{}` and `%Tempo.Interval{}` structs. This is NOT the public
  # constructor — see `Tempo.new/1` and `Tempo.Interval.new/1` for
  # the developer-facing keyword-based constructors, which validate
  # their input.
  #
  # `build/1,2` accepts whatever the tokenizer produces: plain keyword
  # lists, tagged-tuple shapes like `{:range, [first, last]}`, the
  # atom `:undefined`, and tokens containing groups / selections /
  # sets as component values. No validation happens here; the parser
  # is the validator of record for these shapes.

  alias Tempo.Duration
  alias Tempo.Interval

  @doc """
  Build a `%Tempo{}` from tokenizer output.

  Accepts:

    * a keyword list (possibly containing `:time_shift`,
      `:qualification`, `:extended`, and `:<unit>_qualification` keys
      that route to specific struct fields);

    * `{:range, [first_tokens, last_tokens]}` — produces a
      `%Tempo.Range{}` (via `Tempo.Range.new/3`);

    * `:undefined` — returned as-is (represents an open endpoint).

  """
  def build(tokens, calendar \\ Calendrical.Gregorian)

  def build({:range, [first, last]}, calendar) do
    Tempo.Range.new(first, last, calendar)
  end

  def build(:undefined, _calendar) do
    :undefined
  end

  # A set member that is itself an interval (`[2020Y/2021Y,…]`).
  def build({:interval, tokens}, _calendar) do
    build_interval(tokens)
  end

  def build(tokens, calendar) when is_list(tokens) do
    {shift, tokens} = Keyword.pop(tokens, :time_shift)
    {qualification, tokens} = Keyword.pop(tokens, :qualification)
    {extended, tokens} = Keyword.pop(tokens, :extended)
    {individual, group, time} = pop_qualifier_tokens(tokens)

    %Tempo{
      time: time,
      shift: shift,
      calendar: calendar,
      extended: extended,
      qualification: qualification,
      qualifications: resolve_qualifications(individual, group, time)
    }
  end

  @doc """
  Build a `%Tempo.Interval{}` from tokenizer output.

  Defers to `Tempo.Interval.build/1` (see that function for the
  clause-by-clause shape coverage). Kept here for symmetry — callers
  inside the parser pipeline go through `Tempo.Iso8601.AST` for both
  the Tempo and Interval construction paths.
  """
  def build_interval(tokens) do
    Interval.build(tokens)
  end

  @doc """
  Build a `%Tempo.Duration{}` from tokenizer output. Tokens are a
  keyword list of `{unit, amount}` pairs.
  """
  def build_duration(tokens) do
    Duration.build(tokens)
  end

  # Date components in resolution order (coarsest → finest). Group
  # qualification (ISO 8601-2 §8.2.2) propagates from a component
  # leftward, i.e. toward coarser units earlier in this list.
  @date_resolution_order [:year, :month, :day]

  # Split the `:individual_qualification` and `:group_qualification`
  # tokens out of the token list, returning `{individual, group, time}`
  # where `individual`/`group` are `[{unit, qualifier}]` lists in
  # source order and `time` is the remaining keyword list.
  defp pop_qualifier_tokens(tokens) do
    {time, individual, group} =
      Enum.reduce(tokens, {[], [], []}, fn
        {:individual_qualification, {unit, qualifier}}, {time, individual, group} ->
          {time, [{unit, qualifier} | individual], group}

        {:group_qualification, {unit, qualifier}}, {time, individual, group} ->
          {time, individual, [{unit, qualifier} | group]}

        other, {time, individual, group} ->
          {[other | time], individual, group}
      end)

    {Enum.reverse(individual), Enum.reverse(group), Enum.reverse(time)}
  end

  # Resolve the per-component qualification map (ISO 8601-2 §8):
  #
  #   * a *group* qualifier applies to its component and every coarser
  #     component present (§8.2.2);
  #   * an *individual* qualifier applies to its component only (§8.2.3).
  #
  # Overlapping qualifiers on one component combine (`?` + `~` → `%`).
  # Returns `nil` when no component-level qualification was present so
  # the struct stays compact.
  defp resolve_qualifications([], [], _time), do: nil

  defp resolve_qualifications(individual, group, time) do
    present = Enum.filter(@date_resolution_order, &Keyword.has_key?(time, &1))

    map =
      Enum.reduce(group, %{}, fn {unit, qualifier}, acc ->
        Enum.reduce(group_target_units(unit, present), acc, fn target, inner ->
          Map.update(inner, target, qualifier, &combine_qualification(&1, qualifier))
        end)
      end)

    map =
      Enum.reduce(individual, map, fn {unit, qualifier}, acc ->
        Map.update(acc, unit, qualifier, &combine_qualification(&1, qualifier))
      end)

    if map_size(map) == 0, do: nil, else: map
  end

  # A group qualifier's targets: its own component plus every coarser
  # component that is actually present in the expression.
  defp group_target_units(unit, present) do
    index = Enum.find_index(@date_resolution_order, &(&1 == unit)) || 0

    @date_resolution_order
    |> Enum.take(index + 1)
    |> Enum.filter(&(&1 in present))
  end

  # `?` (uncertain) and `~` (approximate) on the same component
  # combine to `%` (uncertain and approximate); identical qualifiers
  # are idempotent.
  @doc false
  def combine_qualification(qualifier, qualifier), do: qualifier
  def combine_qualification(_a, _b), do: :uncertain_and_approximate
end
