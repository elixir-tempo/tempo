defmodule Tempo.Schedule.Slot do
  @moduledoc """
  A solved task in a `Tempo.Schedule` — when the task is scheduled and
  how much room it has to move.

  `start`/`finish` are the *early* schedule (the earliest the task can
  begin and end); `latest_start`/`latest_finish` are the *late* schedule
  (the latest it can begin and end without making the plan infeasible).
  A task is on the **critical path** when its early and late starts
  coincide — it has zero slack, so any slip delays the whole project (a
  task with a fixed start counts: it cannot move at all).

  The late schedule and `critical?` are determined only when something
  bounds how late the task can run — a deadline downstream, or a fixed
  start on the task itself. When nothing does, `latest_start`/`latest_finish`
  and `critical?` are `nil`: the early start is known, but the task's
  latest position is open.

  """

  @type t :: %__MODULE__{
          id: term(),
          start: Tempo.t() | nil,
          finish: Tempo.t() | nil,
          latest_start: Tempo.t() | nil,
          latest_finish: Tempo.t() | nil,
          critical?: boolean() | nil
        }

  defstruct [:id, :start, :finish, :latest_start, :latest_finish, :critical?]
end
