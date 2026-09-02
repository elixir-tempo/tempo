defimpl Enumerable, for: Tempo do
  @moduledoc false

  alias Tempo.Enumeration
  alias Tempo.Enumeration.Zone
  alias Tempo.Validation

  # Implicit enumeration of a resolved `%Tempo{}` walks the same
  # sequence as forward-stepping its materialised interval (see
  # `to_interval/1`), so `count/1`, `member?/2`, and `slice/1` reuse
  # the interval's O(1) `Tempo.Interval.Steps`-backed implementations.
  # Those are DST-aware in the same way as `reduce/3` here — a
  # spring-forward gap hour is not counted/sliced, a fall-back hour is
  # counted twice — so the fast paths agree with the walk.
  #
  # Values that don't materialise to a single interval — groups,
  # selections, ranges, sets, masks — return `{:error, __MODULE__}`,
  # so `Enum` falls back to the reduce-based traversal that handles
  # them.

  @impl Enumerable
  def count(%Tempo{} = tempo) do
    case single_interval(tempo) do
      {:ok, interval} -> Enumerable.count(interval)
      :error -> {:error, __MODULE__}
    end
  end

  @impl Enumerable
  def member?(%Tempo{} = tempo, %Tempo{} = element) do
    case single_interval(tempo) do
      {:ok, interval} -> Enumerable.member?(interval, element)
      :error -> {:error, __MODULE__}
    end
  end

  def member?(_tempo, _element) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def slice(%Tempo{} = tempo) do
    case single_interval(tempo) do
      {:ok, interval} -> Enumerable.slice(interval)
      :error -> {:error, __MODULE__}
    end
  end

  defp single_interval(%Tempo{} = tempo) do
    # Any value that enumerates *candidates* (masks, `:any`, ranges,
    # groups, continuations) materialises to a single block interval whose
    # `count`/`slice` would disagree with the candidate walk — e.g.
    # `2020-06-XX` is 30 day-candidates, not one month-long span. Route
    # exactly those through the reduce fallback, using the canonical
    # `explicitly_enumerable?/1` predicate rather than an ad-hoc mask check
    # (which missed `:any`, ranges, and groups).
    if Enumeration.explicitly_enumerable?(tempo) do
      :error
    else
      case Tempo.to_interval(tempo) do
        {:ok, %Tempo.Interval{} = interval} -> {:ok, interval}
        _ -> :error
      end
    end
  end

  @impl Enumerable
  def reduce(%Tempo{} = tempo, {:cont, _acc} = acc, fun) do
    # Any combination of ranges in any positions expands as a
    # cartesian product whose components resolve against their
    # concrete ancestors — the odometer's backtracking cannot
    # converge on several nested open ranges. Shapes the expander
    # does not cover (masks, groups, `:any`, selections) keep the
    # odometer walk below.
    case Enumeration.expand(tempo) do
      {:ok, members} -> reduce_members(members, acc, fun)
      :not_expandable -> reduce_odometer(tempo, acc, fun)
    end
  end

  def reduce(enum, acc, fun), do: reduce_odometer(enum, acc, fun)

  # Emit pre-expanded members in time order, applying the same
  # DST zone reading each odometer value gets.
  defp reduce_members(_members, {:halt, acc}, _fun), do: {:halted, acc}

  defp reduce_members(members, {:suspend, acc}, fun),
    do: {:suspended, acc, &reduce_members(members, &1, fun)}

  defp reduce_members([], {:cont, acc}, _fun), do: {:done, acc}

  defp reduce_members([member | rest], {:cont, acc}, fun) do
    case Zone.zone_status(member) do
      :gap ->
        reduce_members(rest, {:cont, acc}, fun)

      {:ambiguous, first_shift, second_shift} ->
        emit_members(
          [%{member | shift: first_shift}, %{member | shift: second_shift}],
          rest,
          acc,
          fun
        )

      :ok ->
        reduce_members(rest, fun.(member, acc), fun)
    end
  end

  defp emit_members([], rest, acc, fun), do: reduce_members(rest, {:cont, acc}, fun)

  defp emit_members([value | values], rest, acc, fun) do
    case fun.(value, acc) do
      {:cont, acc2} -> emit_members(values, rest, acc2, fun)
      {:halt, acc2} -> {:halted, acc2}
      {:suspend, acc2} -> {:suspended, acc2, &emit_members(values, rest, &1, fun)}
    end
  end

  defp reduce_odometer(enum, {:cont, acc}, fun) do
    enum = make_enum(enum)

    case Enumeration.next(enum) do
      nil ->
        {:done, acc}

      next ->
        tempo = Enumeration.collect(next)

        case Zone.zone_status(tempo) do
          # Wall clock never shows this moment (DST spring-forward):
          # skip and advance.
          :gap ->
            reduce_odometer(next, {:cont, acc}, fun)

          # Wall clock shows this moment twice (DST fall-back): emit
          # both occurrences, distinguished by their `:shift` — first
          # with the pre-transition offset (e.g. AEDT +11), second
          # with the post-transition offset (AEST +10). RFC 9557
          # IXDTF treats the explicit numeric offset as the fold
          # disambiguator, so the two emitted Tempos round-trip as
          # distinct values and compare as distinct UTC instants.
          {:ambiguous, first_shift, second_shift} ->
            emit_values(
              [%{tempo | shift: first_shift}, %{tempo | shift: second_shift}],
              next,
              acc,
              fun
            )

          :ok ->
            reduce_odometer(next, fun.(tempo, acc), fun)
        end
    end
  end

  defp reduce_odometer(_enum, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp reduce_odometer(enum, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce_odometer(enum, &1, fun)}
  end

  # Apply `fun` to each pending value (typically the two occurrences
  # of a DST fold), threading the accumulator, then continue normal
  # iteration from `next`.
  defp emit_values([], next, acc, fun), do: reduce_odometer(next, {:cont, acc}, fun)

  defp emit_values([value | rest], next, acc, fun) do
    case fun.(value, acc) do
      {:cont, acc2} ->
        emit_values(rest, next, acc2, fun)

      {:halt, acc2} ->
        {:halted, acc2}

      {:suspend, acc2} ->
        {:suspended, acc2, &emit_values_after_suspend(rest, next, fun, &1)}
    end
  end

  defp emit_values_after_suspend(rest, next, fun, {:cont, acc}),
    do: emit_values(rest, next, acc, fun)

  defp emit_values_after_suspend(_rest, _next, _fun, {:halt, acc}),
    do: {:halted, acc}

  defp emit_values_after_suspend(rest, next, fun, {:suspend, acc}),
    do: {:suspended, acc, &emit_values_after_suspend(rest, next, fun, &1)}

  defp make_enum(%Tempo{calendar: calendar} = tempo) do
    # Resolve the implicit `1..-1` enumeration range against the
    # value's *own* calendar. Without the explicit calendar,
    # `Validation.validate/1` defaults to Gregorian, so a Coptic
    # month would enumerate 31 days (January) and a 13-month calendar
    # year only 12 months. `Enumeration.next/1` already threads the
    # calendar; this lines the range resolution up with it.
    {:ok, tempo} =
      tempo
      |> Enumeration.maybe_add_implicit_enumeration()
      |> Validation.validate(calendar)

    tempo
  end
end
