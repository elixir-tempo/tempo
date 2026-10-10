defmodule Tempo.Sigils.Options do
  @moduledoc false

  # Maps the sigil modifier character list to a calendar module, or
  # `nil` when no modifier selects one — in which case the sigil
  # defers to the string's own IXDTF `[u-ca=NAME]` suffix (falling
  # back to Gregorian), so `~o"5786-01-01[u-ca=hebrew]"` resolves to
  # the Hebrew calendar rather than being forced to Gregorian.
  # Kept out of `Tempo.Sigils` so `import Tempo.Sigils` does not
  # bring `calendar_from/1` into the caller's scope.

  alias Tempo.Calendars

  def calendar_from([?W]), do: Calendars.weeks()
  def calendar_from([]), do: nil
end
