defmodule Tempo.Test.Booking do
  @moduledoc false

  # A struct of a caller's that stands for the time it covers, for the
  # tests of `Tempo.Intervallic`: it puts itself in the metadata of the
  # interval it gives, to be found again in an answer.

  defstruct [:guest, :check_in, :check_out]
end

defimpl Tempo.Intervallic, for: Tempo.Test.Booking do
  def to_tempo(%Tempo.Test.Booking{check_in: from, check_out: to} = booking) do
    Tempo.Interval.new(from: from, to: to, metadata: %{booking: booking})
  end
end

defmodule Tempo.Test.Nonsense do
  @moduledoc false

  # A struct whose implementation gives something that is no expression.

  defstruct []
end

defimpl Tempo.Intervallic, for: Tempo.Test.Nonsense do
  def to_tempo(_nonsense) do
    :nonsense
  end
end
