defmodule Tempo.Border do
  @moduledoc false

  import Kernel, except: [inspect: 1, inspect: 2]

  # The border between what a caller holds and what Tempo works with.
  #
  # A value that names no calendar is in `Calendar.ISO`, Elixir's own, and
  # that is what a caller sees in it. `Calendar.ISO` keeps Elixir's
  # `Calendar` behaviour alone, and Tempo asks a calendar the questions of
  # Calendrical's behaviour too, so inside a call the calendar is the module
  # that answers both for `Calendar.ISO`. This is the one place that knows
  # the two are one calendar:
  #
  # * `enter/1` replaces `Calendar.ISO` with that module wherever a term a
  #   public function is given holds it, and reads a value written by hand
  #   with `nil` for its calendar as `Calendar.ISO`.
  #
  # * `leave/1` replaces it back in what a public function returns.
  #
  # * `call_out/3` crosses it the other way, where Tempo calls a function of
  #   a caller's own module.
  #
  # The public functions are the documented ones of a module that uses this
  # one: each is made to cross the border (`__before_compile__/1`), and
  # nothing else does. A public function called from inside Tempo is given
  # terms that hold the inside module already, and what it returns is left
  # as it is, so the border is crossed once on the way in and once on the
  # way out, by the call that was made from outside.
  #
  # Everywhere else every calendar is treated alike: a call is
  # `calendar.function(…)`, and nothing asks which calendar it is.

  # The calendar a caller holds for a value that names none.
  @outside Calendar.ISO

  # The module that answers Calendrical's behaviour for it.
  @inside Localize.Calendar.ISO

  @typedoc false
  @type inside :: Localize.Calendar.ISO

  @doc false
  # The calendar of a value that names none, as a caller holds it.
  @spec outside() :: Calendar.ISO
  def outside, do: @outside

  @doc false
  # The calendar of a value that names none, as Tempo works with it: what
  # text with no calendar is read into, inside a call.
  @spec inside() :: inside()
  def inside, do: @inside

  @doc false
  # A term a public function is given, as Tempo works with it.
  @spec enter(term()) :: term()
  def enter(term) do
    if outside?(term), do: entered(term), else: term
  end

  @doc false
  # What a public function returns, as a caller holds it.
  @spec leave(term()) :: term()
  def leave(term) do
    if inside?(term) or lazy?(term), do: left(term), else: term
  end

  @doc false
  # The arguments a public function was given, each as Tempo works with it,
  # and where the call was made from. Arguments that hold the inside module
  # are those of a call made from inside Tempo, and are as they should be.
  # Those of any other call are entered, and what they hold that the caller
  # has still to give is entered as it comes: what a function of the
  # caller's is given leaves and what it answers enters, and the elements
  # of a stream enter as they are read.
  @spec enter_arguments([term()]) :: {[term()], :inside | :outside}
  def enter_arguments(arguments) when is_list(arguments) do
    if inside?(arguments),
      do: {arguments, :inside},
      else: {Enum.map(arguments, &given/1), :outside}
  end

  @doc false
  # What a public function returns, to the caller that made the call: left
  # as it is for a call made from inside Tempo, and as a caller holds it
  # for any other.
  @spec leave(term(), :inside | :outside) :: term()
  def leave(result, :inside), do: result
  def leave(result, :outside), do: leave(result)

  @doc false
  # A calendar's name in text a caller is to read (a message, a value as it
  # is written): text is what it is once it is written, so a name bound for
  # a caller is written as the caller knows it.
  @spec name(module()) :: String.t()
  def name(calendar), do: Kernel.inspect(leave(calendar))

  @doc false
  # A term as text a caller is to read. A message is written inside Tempo of
  # what Tempo holds, and what it says of a term it says as the caller holds
  # it: every message in the library is written with this, and none with
  # `Kernel.inspect/2` (`test/tempo/border_test.exs` reads the source for it).
  @spec inspect(term(), keyword()) :: String.t()
  def inspect(term, options \\ []), do: Kernel.inspect(leave(term), options)

  @doc false
  # A call from inside Tempo to a function of a caller's own module (a
  # clock, a resolver of events): the border crossed the other way. What the
  # function is given leaves, and what it answers enters.
  @spec call_out(module(), atom(), [term()]) :: term()
  def call_out(module, function, arguments) when is_atom(module) and is_atom(function),
    do: enter(apply(module, function, leave(arguments)))

  @doc false
  # Makes the public functions of the module that uses this one cross the
  # border: the arguments of each are entered, and what it returns is left
  # for the caller that made the call from outside.
  #
  # The public functions are the documented ones. An implementation of a
  # protocol has none, and is called by whoever holds a value, so every
  # function of one crosses (`every: true`). An implementation of
  # `Enumerable` says so (`enumerable: true`): what it hands a caller is not
  # what it returns but each element it gives the caller's own function, so
  # those are what is left.
  defmacro __using__(options) do
    quote do
      @tempo_border unquote(crossing_of(options))
      Module.register_attribute(__MODULE__, :tempo_border_documented, accumulate: true)
      @on_definition Tempo.Border
      @before_compile Tempo.Border
    end
  end

  defp crossing_of(options) do
    cond do
      Keyword.get(options, :enumerable, false) -> :enumerable
      Keyword.get(options, :every, false) -> :every
      true -> :documented
    end
  end

  @doc false
  # Notes each documented function as it is defined: its documentation is
  # in hand only then.
  def __on_definition__(env, :def, name, arguments, _guards, _body) do
    case Module.get_attribute(env.module, :doc) do
      {_line, text} when is_binary(text) ->
        Module.put_attribute(env.module, :tempo_border_documented, {name, length(arguments)})

      _hidden_or_a_later_clause ->
        :ok
    end
  end

  def __on_definition__(_env, _kind, _name, _arguments, _guards, _body), do: :ok

  @doc false
  defmacro __before_compile__(env) do
    crossing = Module.get_attribute(env.module, :tempo_border)
    documented = Module.get_attribute(env.module, :tempo_border_documented)

    crossed =
      for {name, arity} <- Module.definitions_in(env.module, :def),
          crosses?(name),
          written_out?(env.module, name, arity),
          crossing != :documented or {name, arity} in documented,
          do: {name, arity}

    crossings = Enum.map(crossed, fn {name, arity} -> crossing(name, arity, crossing) end)

    quote do
      unquote_splicing(crossings)

      @doc false
      # The functions of this module that cross the border.
      def __border__, do: unquote(Enum.sort(crossed))
    end
  end

  # An enumeration gives each element to the caller's function as it goes.
  defp crossing(:reduce, 3, :enumerable) do
    quote do
      defoverridable reduce: 3

      def reduce(enumerable, accumulator, function) do
        {[enumerable], from} = unquote(__MODULE__).enter_arguments([enumerable])
        super(enumerable, accumulator, unquote(__MODULE__).reducer(function, from))
      end
    end
  end

  # A slice hands back a function that gives the elements.
  defp crossing(:slice, 1, :enumerable) do
    quote do
      defoverridable slice: 1

      def slice(enumerable) do
        {[enumerable], from} = unquote(__MODULE__).enter_arguments([enumerable])
        unquote(__MODULE__).slicer(super(enumerable), from)
      end
    end
  end

  defp crossing(name, arity, _crossing) do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    quote do
      defoverridable [{unquote(name), unquote(arity)}]

      def unquote(name)(unquote_splicing(arguments)) do
        {[unquote_splicing(arguments)], from} =
          unquote(__MODULE__).enter_arguments([unquote_splicing(arguments)])

        unquote(__MODULE__).leave(super(unquote_splicing(arguments)), from)
      end
    end
  end

  @doc false
  # The function an enumeration gives each element to, for a call made from
  # outside: the caller's own, given each element as a caller holds it.
  @spec reducer(function(), :inside | :outside) :: function()
  def reducer(function, :inside), do: function

  def reducer(function, :outside) when is_function(function, 2),
    do: fn element, accumulator -> function.(leave(element), accumulator) end

  @doc false
  # What `Enumerable.slice/1` answers, for a call made from outside: the
  # function it hands back gives its elements as a caller holds them.
  @spec slicer(term(), :inside | :outside) :: term()
  def slicer(sliced, :inside), do: sliced

  def slicer({:ok, size, slice}, :outside) when is_function(slice, 3),
    do: {:ok, size, fn start, length, step -> leave(slice.(start, length, step)) end}

  def slicer({:ok, size, slice}, :outside) when is_function(slice, 2),
    do: {:ok, size, fn start, length -> leave(slice.(start, length)) end}

  def slicer({:ok, size, to_list}, :outside) when is_function(to_list, 1),
    do: {:ok, size, fn enumerable -> leave(to_list.(enter(enumerable))) end}

  def slicer(sliced, :outside), do: sliced

  # A function the compiler defines for a module (`__struct__/0`) is no
  # part of what a caller calls.
  defp crosses?(name), do: not String.starts_with?(Atom.to_string(name), "__")

  # A function the compiler makes for an argument's default calls the one
  # that was written out, which crosses the border for it.
  defp written_out?(module, name, arity) do
    {:v1, :def, meta, _clauses} = Module.get_definition(module, {name, arity})
    Keyword.get(meta, :context) != :elixir_def
  end

  # An argument of a call made from outside. A function of the caller's is
  # called from inside, so what it is given leaves and what it answers
  # enters. A stream gives its elements when they are read, so they enter
  # then. Anything else is entered as it stands.
  defp given(function) when is_function(function, 1),
    do: fn argument -> enter(function.(leave(argument))) end

  defp given(stream) when is_function(stream, 2), do: Stream.map(stream, &enter/1)
  defp given(%Stream{} = stream), do: Stream.map(stream, &enter/1)
  defp given(argument), do: enter(argument)

  # A date and a time of Elixir's name their calendar once, in `:calendar`,
  # and a duration names none. A value names its own there too, and holds
  # another value only in a unit that is no plain number (a selection may
  # hold an interval) and in its metadata, which is its caller's to fill.
  # So these are read by the fields that can hold a calendar, and no
  # others: without this a value of any calendar but the two this module
  # knows is read through, field by field, at every crossing, to find
  # nothing. `test/tempo/border_test.exs` holds every shape of value to it.
  @names_its_calendar_once [Date, Time, NaiveDateTime, DateTime, Tempo.Duration]

  # The fields of an interval and of an interval set that may hold a value,
  # in the order they are asked: the others are numbers and names.
  @interval_fields [:from, :to, :repeat_rule, :metadata]
  @interval_set_fields [:intervals, :metadata]

  # Whether a term holds the inside module. The first found answers: a
  # value's calendar is among the first of its fields. A stream a value
  # keeps is not looked into: what it holds is the value's own, and is
  # neither entered nor left.
  defp inside?(@inside), do: true
  defp inside?(%{calendar: @inside}), do: true
  defp inside?(%Stream{}), do: false

  defp inside?(%{__struct__: Tempo, time: time, metadata: metadata}),
    do: inside?(metadata) or any_unit?(time, &inside?/1)

  defp inside?(%{__struct__: named}) when named in @names_its_calendar_once, do: false

  defp inside?(%{__struct__: Tempo.Interval} = interval),
    do: any_field?(interval, @interval_fields, &inside?/1)

  defp inside?(%{__struct__: Tempo.IntervalSet} = set),
    do: any_field?(set, @interval_set_fields, &inside?/1)

  defp inside?([head | tail]), do: inside?(head) or inside?(tail)
  defp inside?(term) when is_tuple(term), do: any_element?(term, tuple_size(term), &inside?/1)
  defp inside?(term) when map_size(term) == 0, do: false
  defp inside?(term) when is_map(term), do: any_entry?(term, &inside?/1)
  defp inside?(_term), do: false

  # Whether a term holds `Calendar.ISO`, or a value written by hand with no
  # calendar. The struct is matched as a map, so that this module does not
  # wait on `Tempo` to compile: `Tempo` waits on this one for its macros.
  defp outside?(@outside), do: true
  defp outside?(%{calendar: @outside}), do: true
  defp outside?(%Stream{}), do: false
  defp outside?(%{__struct__: Tempo, calendar: nil}), do: true

  defp outside?(%{__struct__: Tempo, time: time, metadata: metadata}),
    do: outside?(metadata) or any_unit?(time, &outside?/1)

  defp outside?(%{__struct__: named}) when named in @names_its_calendar_once, do: false

  defp outside?(%{__struct__: Tempo.Interval} = interval),
    do: any_field?(interval, @interval_fields, &outside?/1)

  defp outside?(%{__struct__: Tempo.IntervalSet} = set),
    do: any_field?(set, @interval_set_fields, &outside?/1)

  defp outside?([head | tail]), do: outside?(head) or outside?(tail)
  defp outside?(term) when is_tuple(term), do: any_element?(term, tuple_size(term), &outside?/1)
  defp outside?(term) when map_size(term) == 0, do: false
  defp outside?(term) when is_map(term), do: any_entry?(term, &outside?/1)
  defp outside?(_term), do: false

  # A struct with each of the fields that may hold a value replaced.
  defp with_fields(struct, [], _replace), do: struct

  defp with_fields(struct, [field | fields], replace) do
    held = :erlang.map_get(field, struct)
    with_fields(:maps.put(field, replace.(held), struct), fields, replace)
  end

  # The units of a value, each with what it holds replaced where that is no
  # plain number.
  defp with_units([{unit, held} | units], replace) when is_integer(held),
    do: [{unit, held} | with_units(units, replace)]

  defp with_units([{unit, held} | units], replace) when is_atom(unit),
    do: [{unit, replace.(held)} | with_units(units, replace)]

  defp with_units([], _replace), do: []
  defp with_units(time, replace), do: replace.(time)

  # Whether a unit of a value holds what is asked for: a plain number holds
  # nothing.
  defp any_unit?([{_unit, held} | units], holds?) when is_integer(held),
    do: any_unit?(units, holds?)

  defp any_unit?([{unit, held} | units], holds?) when is_atom(unit),
    do: holds?.(held) or any_unit?(units, holds?)

  defp any_unit?([], _holds?), do: false
  defp any_unit?(time, holds?), do: holds?.(time)

  defp any_field?(_struct, [], _holds?), do: false

  defp any_field?(struct, [field | fields], holds?),
    do: holds?.(:erlang.map_get(field, struct)) or any_field?(struct, fields, holds?)

  defp any_element?(_tuple, 0, _holds?), do: false

  defp any_element?(tuple, index, holds?),
    do: holds?.(:erlang.element(index, tuple)) or any_element?(tuple, index - 1, holds?)

  # A map's keys are read as its values are: the members of a `MapSet` are
  # the keys of the map it keeps.
  defp any_entry?(map, holds?), do: any_next?(:maps.next(:maps.iterator(map)), holds?)

  defp any_next?(:none, _holds?), do: false

  defp any_next?({key, value, iterator}, holds?),
    do: holds?.(value) or holds?.(key) or any_next?(:maps.next(iterator), holds?)

  # A term with `Calendar.ISO` replaced by the inside module.
  defp entered(@outside), do: @inside

  defp entered(%{__struct__: Tempo, calendar: nil} = value),
    do: entered(%{value | calendar: @outside})

  defp entered(%{__struct__: Tempo, calendar: calendar, time: time, metadata: metadata} = value) do
    %{
      value
      | calendar: entered(calendar),
        time: with_units(time, &entered/1),
        metadata: entered(metadata)
    }
  end

  defp entered(%{__struct__: Tempo.Duration} = duration), do: duration

  defp entered(%{__struct__: named, calendar: calendar} = dated)
       when named in @names_its_calendar_once,
       do: %{dated | calendar: entered(calendar)}

  defp entered(%{__struct__: Tempo.Interval} = interval),
    do: with_fields(interval, @interval_fields, &entered/1)

  defp entered(%{__struct__: Tempo.IntervalSet} = set),
    do: with_fields(set, @interval_set_fields, &entered/1)

  defp entered(term), do: replaced(term, &entered/1)

  # A term with the inside module replaced by `Calendar.ISO`. A stream a
  # function answers with has its elements still to give, and they are left
  # as they are read. One a value keeps in a field is the value's own: what
  # it gives is left where the value is enumerated.
  defp left(term), do: left(term, :answered)

  defp left(@inside, _where), do: @outside
  defp left(%Stream{} = stream, :answered), do: Stream.map(stream, &leave/1)
  defp left(%Stream{} = stream, :kept), do: stream

  defp left(
         %{__struct__: Tempo, calendar: calendar, time: time, metadata: metadata} = value,
         _where
       ) do
    %{
      value
      | calendar: left(calendar, :kept),
        time: with_units(time, &left(&1, :kept)),
        metadata: left(metadata, :kept)
    }
  end

  defp left(%{__struct__: Tempo.Duration} = duration, _where), do: duration

  defp left(%{__struct__: named, calendar: calendar} = dated, _where)
       when named in @names_its_calendar_once,
       do: %{dated | calendar: left(calendar, :kept)}

  defp left(%{__struct__: Tempo.Interval} = interval, _where),
    do: with_fields(interval, @interval_fields, &left(&1, :kept))

  defp left(%{__struct__: Tempo.IntervalSet} = set, _where),
    do: with_fields(set, @interval_set_fields, &left(&1, :kept))

  defp left(stream, :answered) when is_function(stream, 2),
    do: Stream.map(stream, &leave/1)

  defp left(%_{} = struct, _where), do: replaced(struct, &left(&1, :kept))
  defp left(term, where), do: replaced(term, &left(&1, where))

  # Whether what a function answers with is a stream, or holds one beside
  # its other answers: its elements are not there to look at.
  defp lazy?(%Stream{}), do: true
  defp lazy?(stream) when is_function(stream, 2), do: true
  defp lazy?([head | tail]), do: lazy?(head) or lazy?(tail)
  defp lazy?(term) when is_tuple(term), do: any_element?(term, tuple_size(term), &lazy?/1)
  defp lazy?(_term), do: false

  defp replaced([head | tail], replace), do: [replace.(head) | replaced_tail(tail, replace)]

  defp replaced(term, replace) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.map(replace) |> List.to_tuple()

  # A struct's keys are its fields' names, and stay.
  defp replaced(%_{} = struct, replace),
    do: :maps.map(fn _field, value -> replace.(value) end, struct)

  defp replaced(term, replace) when is_map(term),
    do: Map.new(term, fn {key, value} -> {replace.(key), replace.(value)} end)

  defp replaced(term, _replace), do: term

  # The rest of a list, or the end of an improper one.
  defp replaced_tail([head | tail], replace), do: [replace.(head) | replaced_tail(tail, replace)]
  defp replaced_tail([], _replace), do: []
  defp replaced_tail(tail, replace), do: replace.(tail)
end
