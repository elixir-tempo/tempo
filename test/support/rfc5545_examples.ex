defmodule Tempo.Rfc5545Examples do
  @moduledoc """
  The recurrence examples of RFC 5545 section 3.8.5.3, read from the text of
  the standard (`standards/rfc/rfc5545.txt`): for each, what it is called,
  its `DTSTART`, its rules (some are given two ways), and the occurrences
  the standard lists after `==>`.

  An occurrence is `{{year, month, day}, {hour, minute}, zone}`, the zone
  being the abbreviation the standard prints (`"EDT"`, `"EST"`). Where the
  standard elides with `...`, the occurrences before the first elision are
  kept and the example is marked `:partial`.
  """

  @text Path.expand("../../standards/rfc/rfc5545.txt", __DIR__)
  @external_resource @text

  @months ~w(January February March April May June July August September October November December)

  @type occurrence :: {{integer(), 1..12, 1..31}, {0..23, 0..59}, String.t()}

  @type example :: %{
          title: String.t(),
          start: {{integer(), 1..12, 1..31}, {0..23, 0..59, 0..59}},
          rules: [String.t()],
          excluded: [{integer(), 1..12, 1..31}],
          occurrences: [occurrence()],
          complete?: boolean()
        }

  @doc "The examples, in the standard's order."
  @spec all() :: [example()]
  def all do
    @text
    |> File.read!()
    |> String.split("\n")
    |> Enum.drop_while(&(not String.contains?(&1, "Daily for 10 occurrences:")))
    |> Enum.take_while(&(not String.starts_with?(&1, "3.8.6.  Alarm Component Properties")))
    |> Enum.reject(&page_furniture?/1)
    |> examples()
  end

  defp page_furniture?(line) do
    String.trim(line) == "" or String.starts_with?(line, ["Desruisseaux", "RFC 5545", "\f"])
  end

  # A title is at six spaces; the properties and the occurrences are deeper.
  defp examples(lines) do
    lines
    |> Enum.chunk_while([], &chunk/2, &{:cont, Enum.reverse(&1), []})
    |> Enum.reject(&Enum.empty?/1)
    |> Enum.map(&example/1)
  end

  defp chunk(line, acc) do
    if title?(line) and Enum.any?(acc, &String.contains?(&1, "==>")),
      do: {:cont, Enum.reverse(acc), [line]},
      else: {:cont, [line | acc]}
  end

  defp title?(line), do: Regex.match?(~r/\A      [A-Za-z]/, line)

  defp example(lines) do
    {title, rest} = Enum.split_while(lines, &(not String.contains?(&1, "DTSTART")))
    {properties, listed} = Enum.split_while(rest, &(not String.contains?(&1, "==>")))
    listed = Enum.take_while(listed, &(not String.contains?(&1, "Note:")))
    start = start(properties)
    {occurrences, complete?} = occurrences(Enum.join(listed, " "), start)

    %{
      title: title |> Enum.map_join(" ", &String.trim/1) |> String.trim_trailing(":"),
      start: start,
      rules: rules(properties),
      excluded: excluded(properties),
      occurrences: occurrences,
      complete?: complete?
    }
  end

  defp start(properties) do
    [line] = Enum.filter(properties, &String.contains?(&1, "DTSTART"))
    stamp(line)
  end

  defp excluded(properties) do
    for line <- properties, String.contains?(line, "EXDATE"), do: elem(stamp(line), 0)
  end

  defp stamp(line) do
    [_, y, m, d, h, mi, s] = Regex.run(~r/:(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d)/, line)
    {{int(y), int(m), int(d)}, {int(h), int(mi), int(s)}}
  end

  # A rule may run on to a second line, and an example may give two.
  defp rules(properties) do
    properties
    |> Enum.reject(&String.contains?(&1, ["DTSTART", "EXDATE"]))
    |> Enum.map(&String.trim/1)
    |> Enum.chunk_while([], &rule_part/2, &{:cont, Enum.join(Enum.reverse(&1)), []})
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.replace_prefix(&1, "RRULE:", ""))
  end

  defp rule_part("or", acc), do: {:cont, Enum.join(Enum.reverse(acc)), []}
  defp rule_part(part, acc), do: {:cont, [part | acc]}

  # `(1997 9:00 AM EDT) September 2-30;October 1-25 (1997 9:00 AM EST) …`,
  # `(September 2, 1997 EDT) 09:00,12:00`, or `(1997 EDT) August 5,10`.
  defp occurrences(text, start) do
    {before, complete?} =
      case String.split(text, "...", parts: 2) do
        [all] -> {all, true}
        [before, _elided] -> {before, false}
      end

    groups = Regex.scan(~r/\(([^)]*)\)([^(]*)/, String.replace(before, "==>", ""))
    {Enum.flat_map(groups, fn [_, heading, body] -> group(heading, body, start) end), complete?}
  end

  defp group(heading, body, {_date, {hour, minute, _}}) do
    case Regex.run(~r/\A([A-Z][a-z]+) (\d+), (\d{4}) ([A-Z]{3})\z/, heading) do
      [_, month, day, year, zone] ->
        date = {int(year), month(month), int(day)}

        for [_, h, m] <- Regex.scan(~r/(\d{1,2}):(\d\d)/, body),
            do: {date, {int(h), int(m)}, zone}

      nil ->
        [_, year, zone] = Regex.run(~r/\A(\d{4}).*?([A-Z]{3})\z/, heading)
        for {month, day} <- days(body), do: {{int(year), month, day}, {hour, minute}, zone}
    end
  end

  # `September 2,4-6;October 1` as `{month, day}` pairs.
  defp days(body) do
    for [_, month, list] <- Regex.scan(~r/([A-Z][a-z]+)\s*([\d,\-\s]+)/, body),
        item <- String.split(list, ",", trim: true),
        item = String.trim(item),
        item != "",
        day <- run(item),
        do: {month(month), day}
  end

  defp run(item) do
    case String.split(item, "-") do
      [one] -> [int(one)]
      [first, last] -> Enum.to_list(int(first)..int(last))
    end
  end

  defp month(name), do: Enum.find_index(@months, &(&1 == name)) + 1
  defp int(text), do: text |> String.trim() |> String.to_integer()
end
