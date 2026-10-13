defmodule Tempo.Schedule.ScheduledTask do
  @moduledoc """
  A task in a solved `Tempo.Schedule` — when it runs and how far it can
  move.

  `early` is the task's early schedule, the interval from the earliest
  it can start to the earliest it can finish; `late` is its late
  schedule, from the latest it can start to the latest it can finish
  without making the plan infeasible. A task is on the **critical path**
  when the two start together — it has no slack, so any slip delays the
  whole project (a task with a fixed start counts: it cannot move at
  all).

  The late schedule and `critical?` are known only when something bounds
  how late the task can run — a deadline downstream, or a fixed start on
  the task itself. When nothing does, `late` and `critical?` are `nil`:
  the early schedule is known, but the task's latest position is open.
  A plan with no fixed start or `:not_before` date anywhere has no early
  schedule either, and `early` is `nil` too.

  """

  @type t :: %__MODULE__{
          id: term(),
          early: Tempo.Interval.t() | nil,
          late: Tempo.Interval.t() | nil,
          critical?: boolean() | nil
        }

  defstruct [:id, :early, :late, :critical?]
end
