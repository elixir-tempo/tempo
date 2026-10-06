defmodule Tempo.Iso8601.Tokenizer.Memo do
  @moduledoc false

  # What a combinator reads at a place in a text, kept while that text is
  # being read, so that the place is read once however many alternatives of
  # the grammar come to it.
  #
  # The grammar is an ordered choice with no memory. A selection (`L…N`,
  # ISO 8601-2 §12) may hold a window (§12.10), a window is an interval, an
  # interval's start is a date, and some thirty-five alternatives of a date
  # may start with a selection: each of them read the selection again from
  # the same place, and each selection inside it as many times again. Four
  # selections opened one inside the next (`LLLL`) took over a minute to
  # refuse and eight would have taken years, which is a denial of service
  # in eight bytes.
  #
  # A combinator's reading depends on the text from where it starts and on
  # the parser's context, and on nothing else, so what it read at a place is
  # what it will read there: the tokens and the text left, or a refusal. A
  # place is how much of the text is left, which is one place for as long as
  # one text is read: the tokenizer starts the table before it reads a text
  # and drops it after (`reading/1`), and with no table started nothing is
  # kept and the grammar reads as it did.
  #
  # The table lives in the process dictionary because NimbleParsec gives
  # each alternative of a choice the context the choice started with, so
  # nothing learnt in an alternative that fails reaches the next one any
  # other way.
  #
  # Each of the four traversals below stands in a combinator of its own
  # (`Tempo.Iso8601.Tokenizer.Helpers.read_once/2`): a traversal that
  # returns an error is its combinator failing, which the choice that reads
  # it through `parsec` goes on from, where in line it would end the parse.

  @table {__MODULE__, :read}

  @doc false
  # Reads one text with a table of its own: `read` is the reading, a
  # function of no arguments, and what it returns is returned. A reading
  # inside another (none is made today) takes the table over, and the outer
  # one goes on with none.
  @spec reading((-> result)) :: result when result: term()
  def reading(read) when is_function(read, 0) do
    Process.put(@table, %{})
    result = read.()
    Process.delete(@table)
    result
  end

  @doc false
  # What was read here before, when something was.
  def read_before(rest, [], context, _line, _offset, name) do
    case known(name, rest, context) do
      {:read, tokens, rest_after, context_after} -> {rest_after, tokens, context_after}
      _refused_or_not_tried -> {:error, "#{name} was not read here before"}
    end
  end

  @doc false
  # Marks where a reading starts, unless it is known to be refused here.
  def start(rest, [], context, _line, _offset, name) do
    case known(name, rest, context) do
      :refused -> {:error, "expected #{name}"}
      _not_tried -> {rest, [{@table, place(rest), context}], context}
    end
  end

  @doc false
  # Keeps what was read from the place `start/6` marked, and gives the
  # tokens without the mark. Results are in reverse order, so the mark,
  # which was pushed first, is the last of them.
  def keep(rest, results, context, _line, _offset, name) do
    {tokens, [{@table, from, context_at_start}]} = Enum.split(results, -1)
    remember({name, from, context_at_start}, {:read, tokens, rest, context})
    {rest, tokens, context}
  end

  @doc false
  # Notes that the reading is refused here, and refuses it.
  def refused(rest, [], context, _line, _offset, name) do
    remember({name, place(rest), context}, :refused)
    {:error, "expected #{name}"}
  end

  # A place in the text being read: how much of it is left.
  defp place(rest), do: byte_size(rest)

  defp known(name, rest, context) do
    case Process.get(@table) do
      %{} = table -> Map.get(table, {name, place(rest), context})
      nil -> nil
    end
  end

  defp remember(key, read) do
    case Process.get(@table) do
      %{} = table -> Process.put(@table, Map.put(table, key, read))
      nil -> nil
    end
  end
end
