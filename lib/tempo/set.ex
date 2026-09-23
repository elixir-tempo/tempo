defmodule Tempo.Set do
  @moduledoc """
  A Tempo-valued set — either **all-of** (`{a, b, c}` in ISO
  8601-2, free/busy semantics) or **one-of** (`[a, b, c]`,
  epistemic disjunction — "it was one of these, I don't know
  which").

  `type` carries that distinction. Set operations flatten an
  all-of `%Tempo.Set{}` into an IntervalSet; a one-of set is
  refused because asserting every member happened contradicts
  the user's intent.

  An all-of set may also carry **exclusion members** — written
  `^x` in the set syntax — in `except`. Materialising the set
  subtracts them from its plain members, so `{2020..2030, ^2026}`
  is the range 2020–2030 with 2026 removed. `except` is empty for
  an ordinary set.
  """

  alias Tempo.Iso8601.AST

  @type t :: %__MODULE__{
          type: :all | :one,
          set: [Tempo.t()],
          except: [Tempo.t()]
        }

  defstruct [:type, :set, except: []]

  # Internal constructor used by the parser; users build sets by
  # parsing (`~o"[…]"` / `~o"{…}"`), so this is not public API.
  @doc false
  def new(tokens, type, calendar \\ Calendrical.Gregorian) do
    {excepts, plains} = Enum.split_with(tokens, &match?({:except, _}, &1))
    set = Enum.map(plains, &AST.build(&1, calendar))
    except = Enum.map(excepts, fn {:except, member} -> AST.build(member, calendar) end)
    %__MODULE__{type: type, set: set, except: except}
  end
end
