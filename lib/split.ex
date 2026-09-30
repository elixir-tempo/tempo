defmodule Tempo.Split do
  @moduledoc false

  # Split into date part and time part

  def split([{:year, year}, {:month, month}, {:day, day} | time_of_day]) do
    {[{:year, year}, {:month, month}, {:day, day}], time_of_day}
  end

  def split([{:year, year}, {:week, week}, {:day_of_week, day} | time_of_day]) do
    {[{:year, year}, {:week, week}, {:day_of_week, day}], time_of_day}
  end

  def split([{:year, year}, {:month, month} | time_of_day]) do
    {[{:year, year}, {:month, month}], time_of_day}
  end

  def split([{:year, year}, {:week, week} | time_of_day]) do
    {[{:year, year}, {:week, week}], time_of_day}
  end

  def split([{:year, year}, {:day, day} | time_of_day]) do
    {[{:year, year}, {:day, day}], time_of_day}
  end

  def split([{:month, month}, {:day, day} | time_of_day]) do
    {[{:month, month}, {:day, day}], time_of_day}
  end

  def split([{:week, week}, {:day_of_week, day} | time_of_day]) do
    {[{:week, week}, {:day_of_week, day}], time_of_day}
  end

  def split([{:year, year} | time_of_day]) do
    {[{:year, year}], time_of_day}
  end

  def split([{:month, month} | time_of_day]) do
    {[{:month, month}], time_of_day}
  end

  def split([{:week, week} | time_of_day]) do
    {[{:week, week}], time_of_day}
  end

  def split([{:day, day} | time_of_day]) do
    {[{:day, day}], time_of_day}
  end

  def split(time_of_day) do
    {[], time_of_day}
  end
end
