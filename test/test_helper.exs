# The golden comparison (`test/tempo/golden_test.exs`) runs with
# `mix test --include golden`; `GOLDEN=write` rewrites the files first.
ExUnit.configure(exclude: [golden: true])

ExUnit.start()
