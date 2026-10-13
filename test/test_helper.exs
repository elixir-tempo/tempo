# The golden comparison (`test/tempo/golden_test.exs`) runs with
# `mix test --include golden`; `GOLDEN=write` rewrites the files first.
#
# The README and the guides (`test/guides_test.exs`) run with
# `mix test --include guides`.
ExUnit.configure(exclude: [golden: true, guides: true, total: true])

ExUnit.start()
