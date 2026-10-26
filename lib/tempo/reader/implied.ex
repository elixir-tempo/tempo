defmodule Tempo.Reader.Implied do
  @moduledoc false

  # A value in ISO 8601-1's implied formats, basic and extended
  # (guides/iso8601-grammar.md, sections 2.2 to 2.7, 3.4 to 3.7): a calendar
  # date, an ordinal date, a week date, a decade, a century, an expanded or
  # prefixed year, a time of day, a shift, with unspecified digits and
  # qualifiers. The result is the same units the explicit form gives.
  #
  # The basic format is read by the length of its digit run, as ISO 8601-1
  # §5.2 tells its forms apart: two digits a century, three a decade, four a
  # year, seven an ordinal date, eight a calendar date; six is not a date.

  alias Tempo.Reader.Duration
  alias Tempo.Reader.Number
  alias Tempo.Reader.Value
  alias Tempo.Zone

  @type read :: Value.read()

  @doc "A value in an implied format, and what follows it."
  @spec read(String.t()) :: {:ok, read(), String.t()} | :error
  def read(<<"T", _::binary>> = text), do: time_only(text)

  def read(text) do
    case dated(text) do
      {:ok, read, ""} -> {:ok, read, ""}
      {:ok, read, rest} -> furthest({:ok, read, rest}, time_only(text))
      :error -> time_only(text)
    end
  end

  # `09.5` and `093455+10` are times, not a century and a year with text after
  # them (ISO 8601-1 §5.3.1.3: `T` may be omitted where no ambiguity arises).
  defp furthest(_dated, {:ok, read, ""}), do: {:ok, read, ""}
  defp furthest(dated, _time), do: dated

  defp dated(text) do
    case date(text) do
      {:ok, date, rest} -> dated(date, rest)
      :error -> :error
    end
  end

  # A colon after a run of digits is a time of day with no `T`, not a century.
  defp dated(_date, <<":", _::binary>>), do: :error

  # A shift follows a time of day; a date alone takes none in the implied form.
  defp dated(date, rest) do
    case time(rest, :after_date) do
      {:ok, [], rest} -> finish(date, nil, rest)
      {:ok, clock, rest} -> shifted(date ++ clock, shift(rest))
      :error -> :error
    end
  end

  # An abbreviated end of an interval (ISO 8601-1 §5.5.1): the units it names
  # are the finest of the start's, read by the units the start has.
  @spec read_abbreviated(String.t(), Tempo.Unit.units()) :: {:ok, read(), String.t()} | :error
  def read_abbreviated(text, start_units) do
    case abbreviated_date(text, Keyword.keys(start_units)) do
      {:ok, date, rest} -> dated(date, rest)
      :error -> :error
    end
  end

  defp finish(components, shift, rest) do
    {whole, rest} = Value.qualifier(rest)

    components =
      if whole,
        do: List.update_at(components, -1, fn {u, h, i, _} -> {u, h, i, whole} end),
        else: components

    units = Enum.map(components, fn {unit, held, _, _} -> {unit, held} end)

    case units do
      [] ->
        :error

      [_ | _] ->
        {:ok, %{units: units, qualifications: qualifications(components), shift: shift}, rest}
    end
  end

  defp time_only(text) do
    case time(text, :alone) do
      {:ok, [], _rest} -> :error
      {:ok, clock, rest} -> shifted(clock, shift(rest))
      :error -> :error
    end
  end

  defp shifted(components, {:ok, shift, rest}), do: finish(components, shift, rest)
  defp shifted(_components, :error), do: :error

  # ── The date ──────────────────────────────────────────────────────────

  # A leading qualifier is the first component's (ISO 8601-2 §8.2.3); one after
  # a component is a group's (§8.2.2), carried as that component's mark.
  defp date(text) do
    {mark, text} = Value.qualifier(text)

    with {:ok, year, rest} <- year(text) do
      {group, rest} = Value.qualifier(rest)
      year = {elem(year, 0), elem(year, 1), mark, group}

      case year do
        {unit, _, _, _} when unit in [:decade, :century] -> {:ok, [year], rest}
        _ -> after_year(rest, [year])
      end
    end
  end

  # Y-prefixed years (ISO 8601-2 §4.7); signed expanded years (§5.2.2.3); a
  # run of digits and `X` read by its length.
  # `Y` prefixes a year of more than four digits (ISO 8601-2 §4.7, EDTF level 1).
  defp year(<<"Y", rest::binary>>) do
    {sign, digits} = split_sign(rest)
    {run, _} = Number.split_while(digits, &(&1 in ?0..?9))

    expanded? = byte_size(run) > 4 or annotated?(digits, run)

    case {expanded?, Number.signed(rest)} do
      {true, {:ok, signed, rest}} when sign != ?+ ->
        case Number.annotated(signed, rest) do
          {:ok, held, rest} -> {:ok, {:year, held}, rest}
        end

      _ ->
        :error
    end
  end

  defp year(<<sign, rest::binary>>) when sign in [?+, ?-] do
    {run, rest} = masked_run(rest)

    case signed_run(run, sign, rest) do
      {:ok, {:year, held}} -> annotated_year(:year, held, rest)
      {:ok, {unit, held}} -> {:ok, {unit, held}, rest}
      :error -> :error
    end
  end

  defp year(text) do
    case masked_run(text) do
      {"", _rest} -> :error
      {run, rest} -> year_of_run(run, rest)
    end
  end

  defp year_of_run(run, rest) do
    case byte_size(run) do
      2 ->
        annotated_year(:century, mask_or_integer(run), rest)

      3 ->
        annotated_year(:decade, mask_or_integer(run), rest)

      4 ->
        annotated_year(:year, mask_or_integer(run), rest)

      7 ->
        {:ok, {:year, mask_or_integer(binary_part(run, 0, 4))},
         binary_part(run, 4, 3) <> "!" <> rest}

      8 ->
        {:ok, {:year, mask_or_integer(binary_part(run, 0, 4))},
         binary_part(run, 4, 4) <> "!" <> rest}

      _ ->
        :error
    end
  end

  # A year's significant digits or exponent (ISO 8601-2 §4.6): `1950S2`,
  # `17E2`. A run of any length with an annotation is a year.
  defp annotated_year(unit, held, rest) when is_integer(held) do
    case Number.annotated(held, rest) do
      {:ok, {_, _} = annotated, rest} -> {:ok, {:year, annotated}, rest}
      {:ok, _held, rest} -> {:ok, {unit, held}, rest}
    end
  end

  defp annotated_year(unit, held, rest), do: {:ok, {unit, held}, rest}

  defp split_sign(<<sign, rest::binary>>) when sign in [?+, ?-], do: {sign, rest}
  defp split_sign(rest), do: {nil, rest}

  # `Y17E8`: an exponent or significant digits make a year of any run.
  defp annotated?(digits, run) do
    case binary_part(digits, byte_size(run), byte_size(digits) - byte_size(run)) do
      <<mark, _::binary>> when mark in [?E, ?S] -> true
      _ -> false
    end
  end

  # A signed run: four digits a year, six an expanded year; `+` is for an
  # expanded year alone (ISO 8601-1 §5.2.2.3), and `-0000` is no year. How
  # many digits an expanded year has is the parties' to agree (Amendment 1,
  # §4.3.2): a run of five or more with a `-` after it is a year whatever
  # its length, where a run alone of five is a decade by the six-digit
  # agreement of the standard's own example (`+00198`), and is not read.
  defp signed_run("0000", ?-, _rest), do: :error
  defp signed_run(run, ?+, _rest) when byte_size(run) <= 4, do: :error

  defp signed_run(run, sign, <<"-", _::binary>>) when byte_size(run) >= 5 do
    {:ok, {:year, signed_held(mask_or_integer(run), sign)}}
  end

  defp signed_run(run, sign, _rest) do
    held = signed_held(mask_or_integer(run), sign)

    case byte_size(run) do
      2 -> {:ok, {:century, held}}
      3 -> {:ok, {:decade, held}}
      4 -> {:ok, {:year, held}}
      6 -> {:ok, {:year, held}}
      _ -> :error
    end
  end

  defp signed_held({:mask, digits}, ?-) do
    {:mask, [:negative | digits]}
  end

  defp signed_held(integer, ?-) when is_integer(integer) do
    -integer
  end

  defp signed_held(held, _sign) do
    held
  end

  # After the year: the extended format's `-`, the basic format's run (marked
  # with `!` by `year/1`, which split it off), or a week.
  defp after_year(<<"-W", rest::binary>>, acc), do: week(rest, acc, :extended)
  defp after_year(<<"W", rest::binary>>, acc), do: week(rest, acc, :basic)

  defp after_year(<<"-", rest::binary>>, acc) do
    {mark, rest} = Value.qualifier(rest)

    case masked_run(rest) do
      {run, rest} when byte_size(run) == 3 ->
        {group, rest} = Value.qualifier(rest)
        {:ok, Enum.reverse([{:day_of_year, mask_or_integer(run), mark, group} | acc]), rest}

      {run, rest} when byte_size(run) == 2 ->
        {group, rest} = Value.qualifier(rest)
        {unit, held} = month_slot(mask_or_integer(run))
        after_month(rest, [{unit, held, mark, group} | acc])

      _ ->
        :error
    end
  end

  defp after_year(<<run::binary-size(3), "!", rest::binary>>, acc),
    do: {:ok, Enum.reverse([{:day_of_year, mask_or_integer(run), nil, nil} | acc]), rest}

  defp after_year(<<month::binary-size(2), day::binary-size(2), "!", rest::binary>>, acc) do
    {unit, held} = month_slot(mask_or_integer(month))

    {:ok, Enum.reverse([{:day, mask_or_integer(day), nil, nil}, {unit, held, nil, nil} | acc]),
     rest}
  end

  defp after_year(rest, acc), do: {:ok, Enum.reverse(acc), rest}

  defp after_month(<<"-", rest::binary>>, acc) do
    {mark, rest} = Value.qualifier(rest)

    case masked_run(rest) do
      {run, rest} when byte_size(run) == 2 ->
        {group, rest} = Value.qualifier(rest)

        {:ok, Enum.reverse([{:day, mask_or_integer(run), mark, group} | acc]), rest}

      {run, <<"G", _::binary>> = rest} when run != "" ->
        group(run, rest, acc)

      _ ->
        :error
    end
  end

  defp after_month(rest, acc), do: {:ok, Enum.reverse(acc), rest}

  # `2018-02-2G14DU`: a group in the day's place.
  defp group(run, <<"G", rest::binary>>, acc) do
    case Duration.units(rest, :date) do
      {:ok, [_ | _] = duration, <<"U", rest::binary>>} ->
        {:ok, Enum.reverse([{:group, {mask_or_integer(run), duration}, nil, nil} | acc]), rest}

      _ ->
        :error
    end
  end

  # A season or a division of the year in the month's place (ISO 8601-2 §4.8.3).
  defp month_slot(n) when is_integer(n) and n in 21..32, do: {:season, n}
  defp month_slot(n) when is_integer(n) and n in 33..36, do: {:quarter, n - 32}
  defp month_slot(n) when is_integer(n) and n in 37..39, do: {:group, {n - 36, [month: 4]}}
  defp month_slot(n) when is_integer(n) and n in 40..41, do: {:group, {n - 39, [month: 6]}}
  defp month_slot(held), do: {:month, held}

  defp week(rest, acc, format) do
    {mark, rest} = Value.qualifier(rest)

    case {format, masked_run(rest)} do
      {_, {run, rest}} when byte_size(run) == 2 ->
        {group, rest} = Value.qualifier(rest)
        acc = [{:week, mask_or_integer(run), mark, group} | acc]

        case {format, rest} do
          {:extended, <<"-", rest::binary>>} -> weekday(rest, acc)
          _ -> {:ok, Enum.reverse(acc), rest}
        end

      {:basic, {<<week::binary-size(2), day::binary-size(1)>>, rest}} ->
        {group, rest} = Value.qualifier(rest)

        {:ok,
         Enum.reverse([
           {:day_of_week, mask_or_integer(day), nil, group},
           {:week, mask_or_integer(week), mark, nil} | acc
         ]), rest}

      _ ->
        :error
    end
  end

  defp weekday(rest, acc) do
    {mark, rest} = Value.qualifier(rest)

    case masked_run(rest) do
      {run, rest} when byte_size(run) == 1 ->
        {group, rest} = Value.qualifier(rest)
        {:ok, Enum.reverse([{:day_of_week, mask_or_integer(run), mark, group} | acc]), rest}

      _ ->
        :error
    end
  end

  # An abbreviated end: `02-20` a month and day, `20` a day, `W15-5` a week date, `T…` a time.
  defp abbreviated_date(<<"W", rest::binary>>, _start),
    do:
      week(rest, [], :extended)
      |> then(fn
        {:ok, c, r} -> {:ok, c, r}
        e -> e
      end)

  defp abbreviated_date(text, start) do
    has_day = :day in start

    case masked_run(text) do
      {run, <<"-", rest::binary>>} when byte_size(run) == 2 ->
        month_and_day(mask_or_integer(run), masked_run(rest))

      {run, rest} when byte_size(run) == 2 and has_day ->
        {:ok, [{:day, mask_or_integer(run), nil, nil}], rest}

      {run, rest} when byte_size(run) == 2 ->
        {:ok, [{:month, mask_or_integer(run), nil, nil}], rest}

      {"", <<"T", _::binary>> = rest} ->
        {:ok, [], rest}

      _ ->
        :error
    end
  end

  # ── The time ──────────────────────────────────────────────────────────

  # `T` then `hh[mm[ss]]` or `hh:mm[:ss]`, a fraction on the last; a time with
  # no `T` is read alone where it has a `:`.
  defp time(<<"T", rest::binary>>, _context), do: clock(rest, true)
  defp time(text, :alone), do: clock(text, false)
  defp time(rest, :after_date), do: {:ok, [], rest}

  defp clock(text, _designated?) do
    {mark, text} = Value.qualifier(text)

    {run, rest} = masked_run(text)

    case {byte_size(run), rest} do
      {2, <<":", rest::binary>>} ->
        extended_clock(rest, [{:hour, mask_or_integer(run), mark, nil}])

      {2, rest} ->
        fractioned([{:hour, mask_or_integer(run), mark, nil}], rest)

      {4, rest} ->
        fractioned(
          [
            {:minute, mask_or_integer(binary_part(run, 2, 2)), nil, nil},
            {:hour, mask_or_integer(binary_part(run, 0, 2)), mark, nil}
          ],
          rest
        )

      {6, rest} ->
        fractioned(
          [
            {:second, mask_or_integer(binary_part(run, 4, 2)), nil, nil},
            {:minute, mask_or_integer(binary_part(run, 2, 2)), nil, nil},
            {:hour, mask_or_integer(binary_part(run, 0, 2)), mark, nil}
          ],
          rest
        )

      _ ->
        :error
    end
  end

  defp extended_clock(text, acc) do
    {mark, text} = Value.qualifier(text)

    case masked_run(text) do
      {run, rest} when byte_size(run) == 2 ->
        unit = if match?([_], acc), do: :minute, else: :second
        acc = [{unit, mask_or_integer(run), mark, nil} | acc]
        extended_clock(unit, acc, rest)

      _ ->
        :error
    end
  end

  defp extended_clock(:minute, acc, <<":", rest::binary>>), do: extended_clock(rest, acc)
  defp extended_clock(_unit, acc, rest), do: fractioned(acc, rest)

  defp month_and_day(month, {run, rest}) when byte_size(run) == 2 do
    {:ok, [{:month, month, nil, nil}, {:day, mask_or_integer(run), nil, nil}], rest}
  end

  defp month_and_day(_month, _run), do: :error

  # A fraction belongs to the last unit written, and nothing follows it.
  defp fractioned([{unit, whole, mark, _} | acc], rest) when is_integer(whole) do
    case Number.fraction(rest) do
      {:ok, fraction, rest} -> lifted(unit, whole, fraction, mark, acc, rest)
      :error -> finish_clock([{unit, whole, mark, nil} | acc], rest)
    end
  end

  defp fractioned(acc, rest), do: finish_clock(acc, rest)

  defp lifted(:second, whole, fraction, mark, acc, rest),
    do:
      finish_clock([{:microsecond, fraction, nil, nil}, {:second, whole, mark, nil} | acc], rest)

  defp lifted(:minute, whole, {microseconds, _}, mark, acc, rest) do
    finish_clock(
      [{:second, div(microseconds * 60, 1_000_000), nil, nil}, {:minute, whole, mark, nil} | acc],
      rest
    )
  end

  defp lifted(:hour, whole, {microseconds, _}, mark, acc, rest) do
    total = div(microseconds * 3600, 1_000_000)
    seconds = if rem(total, 60) == 0, do: [], else: [{:second, rem(total, 60), nil, nil}]

    finish_clock(
      seconds ++ [{:minute, div(total, 60), nil, nil}, {:hour, whole, mark, nil} | acc],
      rest
    )
  end

  defp finish_clock(acc, rest) do
    {group, rest} = Value.qualifier(rest)
    [last | others] = acc
    last = put_elem(last, 3, group)
    {:ok, Enum.reverse([last | others]), rest}
  end

  # ── The shift ─────────────────────────────────────────────────────────

  defp shift(<<"Z", rest::binary>>), do: {:ok, [hour: 0], rest}

  defp shift(<<sign, rest::binary>>) when sign in [?+, ?-] do
    behind? = sign == ?-

    case Number.split_while(rest, &(&1 in ?0..?9)) do
      {<<h::binary-size(2)>>, <<":", m::binary-size(2), rest::binary>>} when m != "" ->
        {:ok, Zone.numeric([hour: String.to_integer(h), minute: String.to_integer(m)], behind?),
         rest}

      {<<h::binary-size(2), m::binary-size(2)>>, rest} ->
        {:ok, Zone.numeric([hour: String.to_integer(h), minute: String.to_integer(m)], behind?),
         rest}

      {<<h::binary-size(2)>>, rest} ->
        {:ok, Zone.numeric([hour: String.to_integer(h)], behind?), rest}

      _ ->
        :error
    end
  end

  defp shift(rest), do: {:ok, nil, rest}

  # ── Helpers ───────────────────────────────────────────────────────────

  # The qualifications of the components: a unit's own mark, else the mark of
  # the first group written at or after it.
  defp qualifications(components) do
    groups = Enum.map(components, fn {_, _, _, group} -> group end)

    components
    |> Enum.with_index()
    |> Enum.flat_map(fn {{unit, _, individual, _}, index} ->
      case individual || groups |> Enum.drop(index) |> Enum.find(&(not is_nil(&1))) do
        nil -> []
        mark -> [{unit, mark}]
      end
    end)
    |> Map.new()
    |> then(fn map -> if map == %{}, do: nil, else: map end)
  end

  defp masked_run(text), do: Number.split_while(text, fn char -> char in ?0..?9 or char == ?X end)

  defp mask_or_integer(run) do
    if String.contains?(run, "X") do
      {:mask,
       run
       |> String.graphemes()
       |> Enum.map(fn
         "X" -> :x
         digit -> String.to_integer(digit)
       end)}
    else
      String.to_integer(run)
    end
  end
end
