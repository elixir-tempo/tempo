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
  `^x` in the set syntax — in `except`. Converting the set
  subtracts them from its plain members, so `{2020..2030, ^2026}`
  is the range 2020–2030 with 2026 removed. `except` is empty for
  an ordinary set.

  When the set is a recurrence **domain**, it may carry a year
  `filter` — `:even`, `:odd`, `:leap` or `:common`, written
  `e`/`o`/`l`/`c` after the closing brace — that keeps only the years
  matching it, so `{2000..2020}e` is the even years, `{2000..2020}l`
  the leap years and `{2000..2020}c` the common (non-leap) years of
  the range. `filter` is `nil` for an ordinary set.

  A set may hold durations in place of dates and times (ISO 8601-2
  §6.5): `{P1D,P2D}` is one day and two, `[PT30M,PT1H]` one of half an
  hour and an hour, and a range from one duration to another that
  differs from it in its last unit alone is each duration between them,
  so `{P1M2S..P1M5S}` holds four. Such a set names lengths of time and
  no time, so it has no span and no place on the time line, as one
  duration has none.

  A set has no calendar of its own. Each member, each end of a range
  and each member it excludes is a value in the calendar the set is
  written for — the one given to `Tempo.from_iso8601/2`, or named by a
  `[u-ca=…]` suffix after the set — and is checked as a value on its
  own is, so `{2026-02-30}` is an error. A recurrence's domain is the
  exception: its years are Gregorian whatever calendar the
  recurrence's selection is in.

  """

  alias Tempo.Calendars
  alias Tempo.Iso8601.AST

  @type filter :: :even | :odd | :leap | :common | nil

  @typedoc "A set's member: a value, a range of values or an interval, or in a set of durations a duration."
  @type member :: Tempo.t() | Tempo.Range.t() | Tempo.Interval.t() | Tempo.Duration.t()

  @type t :: %__MODULE__{
          type: :all | :one,
          set: [member()],
          except: [member()],
          filter: filter()
        }

  defstruct [:type, :set, except: [], filter: nil]

  # Internal constructor used by the parser; users build sets by
  # parsing (`~o"[…]"` / `~o"{…}"`), so this is not public API.
  @doc false
  def new(tokens, type, calendar \\ Calendars.default()) do
    {excepts, plains} = Enum.split_with(tokens, &match?({:except, _}, &1))
    set = Enum.map(plains, &member(&1, calendar))
    except = Enum.map(excepts, fn {:except, member} -> AST.build(member, calendar) end)
    %__MODULE__{type: type, set: set, except: except}
  end

  # A member of a set of durations is built where it is read.
  defp member(%Tempo.Duration{} = duration, _calendar), do: duration
  defp member(tokens, calendar), do: AST.build(tokens, calendar)
end
