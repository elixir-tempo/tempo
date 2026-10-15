defmodule Tempo.Placed do
  @moduledoc false

  # A span with its place: the written span, a `%Tempo{}` of the `:span`
  # form with value ends, and the two positions on its frame it was built
  # from or placed at. It is the one shape the engine hands a span on in
  # (`plans/decisions.md`, 74): `Tempo.Spans.placed/2` makes one for every
  # span an expression denotes, as it makes the span, and `Tempo.Algebra`,
  # `Tempo.Recurrence`, `Tempo.Select`, `Tempo.Children`, `Tempo.Conditions`
  # and `Tempo.Exclusions` read the place from it rather than placing the
  # span again. The written span alone crosses to the public layer, through
  # `Tempo.Spans.spans/2`.
  #
  # An end that is open has no position, `nil`. The positions are what
  # `Tempo.Spans.extent/1` gives the span: a step that builds a span from
  # positions it holds makes the pair from them, and any other asks the
  # extent once (`of/1`).

  alias Tempo.Scale
  alias Tempo.Spans

  @enforce_keys [:start, :stop, :span]
  defstruct [:start, :stop, :span]

  @type t :: %__MODULE__{
          start: Scale.position() | nil,
          stop: Scale.position() | nil,
          span: Tempo.t()
        }

  @doc "A span at the positions it was built from."
  @spec new(Tempo.t(), Spans.extent()) :: t()
  def new(%Tempo{} = span, {start, stop}), do: %__MODULE__{start: start, stop: stop, span: span}

  @doc "A span placed by its extent, asked once."
  @spec of(Tempo.t()) :: {:ok, t()} | {:error, Exception.t()}
  def of(%Tempo{} = span) do
    with {:ok, extent} <- Spans.extent(span), do: {:ok, new(span, extent)}
  end

  @doc "The positions of a placed span, as `Tempo.Spans.extent/1` gives them."
  @spec extent(t()) :: Spans.extent()
  def extent(%__MODULE__{start: start, stop: stop}), do: {start, stop}

  @doc "Whether a placed span has both its positions: neither end is open."
  @spec bounded?(t()) :: boolean()
  def bounded?(%__MODULE__{start: start, stop: stop}), do: is_integer(start) and is_integer(stop)

  @doc "The written span, with its metadata changed by a function."
  @spec update_span(t(), (Tempo.t() -> Tempo.t())) :: t()
  def update_span(%__MODULE__{span: span} = placed, fun), do: %{placed | span: fun.(span)}

  @doc "The written spans of placed ones: a list for a list, a stream for a stream."
  @spec written([t()] | Enumerable.t()) :: [Tempo.t()] | Enumerable.t()
  def written(placed) when is_list(placed), do: Enum.map(placed, & &1.span)
  def written(placed), do: Stream.map(placed, & &1.span)
end
