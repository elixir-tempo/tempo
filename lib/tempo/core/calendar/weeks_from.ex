# The Gregorian calendar with its weeks begun on another day than Monday:
# what an expression written with `[u-fw=sun]` is in (`plans/decisions.md`,
# 14 and 24). The dates are the Gregorian calendar's and only the weeks
# differ: a week begins on the day named, and week 1 of a year is the first
# with four of its days in it, ISO 8601's rule over another first day and
# the weeks RFC 5545 counts for a `WKST`. Calendrical builds each from the
# day; `Tempo.Calendar` names them and no other module does.

defmodule Tempo.Calendar.WeeksFrom.Tuesday do
  @moduledoc false

  use Calendrical.Base.Month, month_of_year: 1, day_of_week: 2, min_days_in_first_week: 4
end

defmodule Tempo.Calendar.WeeksFrom.Wednesday do
  @moduledoc false

  use Calendrical.Base.Month, month_of_year: 1, day_of_week: 3, min_days_in_first_week: 4
end

defmodule Tempo.Calendar.WeeksFrom.Thursday do
  @moduledoc false

  use Calendrical.Base.Month, month_of_year: 1, day_of_week: 4, min_days_in_first_week: 4
end

defmodule Tempo.Calendar.WeeksFrom.Friday do
  @moduledoc false

  use Calendrical.Base.Month, month_of_year: 1, day_of_week: 5, min_days_in_first_week: 4
end

defmodule Tempo.Calendar.WeeksFrom.Saturday do
  @moduledoc false

  use Calendrical.Base.Month, month_of_year: 1, day_of_week: 6, min_days_in_first_week: 4
end

defmodule Tempo.Calendar.WeeksFrom.Sunday do
  @moduledoc false

  use Calendrical.Base.Month, month_of_year: 1, day_of_week: 7, min_days_in_first_week: 4
end
