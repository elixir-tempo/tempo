# The README and the guides (`test/guides_test.exs`) run with
# `mix test --only guides`, and the totality check
# (`test/tempo/total_test.exs`) with `mix test --only total`.
ExUnit.configure(exclude: [guides: true, total: true])

ExUnit.start()
