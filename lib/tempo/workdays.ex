defmodule Tempo.Workdays do
  @moduledoc """
  A territory's workdays less a set of holidays: the days a school or a
  business is open.

  `Tempo.workdays/2` builds one with its `:except` option, and it goes
  wherever a territory does. `Tempo.select/2` selects its days, and the
  workday functions — `Tempo.add_workdays/3`, `Tempo.next_workday/2`,
  `Tempo.previous_workday/2`, `Tempo.nearest_workday/2`,
  `Tempo.count_workdays/2` and `Tempo.workday?/2` — step over its holidays
  as well as its weekend.

  ```elixir
  school_days = Tempo.workdays(:AU, except: nsw_public_holidays)

  Tempo.next_workday(~o"2027-04-23", school_days)
  Tempo.count_workdays(term, school_days)
  ```

  > *"School days are the Australian workdays except New South Wales' public
  > holidays. The next school day after Friday 23 April, and the school days
  > in a term."*

  The territory is resolved when the value is built, so it is safe to keep
  and pass around. The holidays are converted to their occurrences only
  around the days asked about, so a `t:Tempo.RecurrenceSet.t/0` of
  recurring holidays needs no window of its own.

  """

  @typedoc "ISO days of the week, Monday 1 to Sunday 7."
  @type iso_day_of_week :: 1..7

  @type t :: %__MODULE__{
          weekdays: [iso_day_of_week()],
          weekend: [iso_day_of_week()],
          except: Tempo.t() | Tempo.Interval.t() | Tempo.IntervalSet.t() | Tempo.RecurrenceSet.t()
        }

  defstruct weekdays: [], weekend: [], except: nil
end
