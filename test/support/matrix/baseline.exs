# The cells of the matrix known to fail: the operation, its arguments and
# what it did. Written by `MATRIX_BASELINE=write mix test
# test/tempo/matrix_test.exs`, and never by hand. See
# `plans/validated-core.md`.
[
  {"a selection selects what its parts name", "2026YL-1WN in Calendrical.ISOWeek",
   "inconsistent"},
  {"a selection selects what its parts name", "2026YL25WN in Calendrical.ISOWeek",
   "inconsistent"},
  {"a selection selects what its parts name", "2026YL{1,-1}WN in Calendrical.ISOWeek",
   "inconsistent"},
  {"a selection selects what its parts name", "2026YL{25,27}WN in Calendrical.ISOWeek",
   "inconsistent"},
  {"a selection selects what its parts name", "2026YL{25..27}WN in Calendrical.ISOWeek",
   "inconsistent"},
  {"a selection selects what its parts name", "2026YL{52..-1}WN in Calendrical.ISOWeek",
   "inconsistent"}
]
