# `:exhaustive` is the matrix's long run (`plans/validated-core.md`): a shaped
# value at each end of an interval, and two shapes in one value. It takes
# minutes, and runs with `mix test --include exhaustive`.
ExUnit.configure(exclude: [all: true, exhaustive: true])

# Ensure the CLDR locales used by Tempo.FormatTest are present.
# Localize lazily downloads on miss, but a few formatting tests
# assert specific locale strings ("de", "en-GB"), so pre-fetching
# them here keeps the test suite hermetic and fast.
_ =
  Mix.Task.run("localize.download_locales", ~w(en en-GB de fr he))

ExUnit.start()
