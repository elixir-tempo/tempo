defmodule Tempo.MixProject do
  use Mix.Project

  # OTP 26 is not supported. The tokenizer is compiled with the Erlang optimiser
  # disabled (the `@compile` flags in the tokenizer modules roughly halve build
  # time), and OTP 26's compiler miscompiles that unoptimised binary-matching
  # path — it crashes at runtime with a bogus multi-terabyte allocation. Fail
  # fast here with a clear message rather than let a consumer hit the crash.
  if String.to_integer(System.otp_release()) < 27 do
    Mix.raise(
      "ex_tempo requires Erlang/OTP 27 or later — OTP #{System.otp_release()} detected. " <>
        "See the README for details."
    )
  end

  @version "1.5.5"

  def project do
    [
      app: :ex_tempo,
      version: @version,
      name: "Tempo",
      source_url: "https://github.com/elixir-tempo/tempo",
      docs: docs(),
      deps: deps(),
      description: description(),
      package: package(),
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      # Excluded from coverage:
      #  * `~r/Error$/` — exception structs, whose uncovered lines are
      #    `message/1` formatting on rare error paths, not logic.
      #  * the tokenizer grammar modules — their functions are NimbleParsec
      #    combinator builders that run at *compile* time to assemble the
      #    parser, so runtime line-coverage cannot see them execute.
      test_coverage: [
        ignore_modules: [
          ~r/Error$/,
          Tempo.Iso8601.Tokenizer.Numbers,
          Tempo.Iso8601.Tokenizer.Grammar,
          Tempo.Iso8601.Tokenizer.Helpers
        ]
      ],
      dialyzer: [
        flags: [
          :error_handling,
          :unknown,
          :underspecs,
          :extra_return,
          :missing_return
        ]
      ]
    ]
  end

  def description do
    "Time as an interval, not an instant — ISO 8601 / IXDTF date, time, " <>
      "interval, duration, recurrence, set-algebra, scheduling, and " <>
      "constraint-network library for Elixir. Calendar- and timezone-aware."
  end

  def package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*",
        "assets/logo.png"
      ]
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/elixir-tempo/tempo",
      "Readme" => "https://github.com/elixir-tempo/tempo/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/elixir-tempo/tempo/blob/v#{@version}/CHANGELOG.md"
    }
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "assets/logo.png",
      # Copy the project's `assets/` directory into the generated
      # docs' `assets/` subdirectory so images referenced from README
      # (and guides) resolve. Without this, `![…](assets/foo.png)`
      # renders as a broken image in local `mix docs` output and on
      # hexdocs.pm.
      assets: %{"assets" => "assets"},
      extras:
        [
          "README.md",
          "LICENSE.md",
          "CHANGELOG.md"
        ] ++ Path.wildcard("guides/*.md") ++ livebooks(),
      formatters: ["html", "markdown"],
      groups_for_modules: groups_for_modules(),
      groups_for_extras: groups_for_extras(),
      skip_undefined_reference_warnings_on:
        [
          "CHANGELOG.md"
        ] ++ Path.wildcard("guides/*.md") ++ livebooks()
    ]
  end

  # Livebooks published as documentation. The Melbourne deck is a
  # conference talk rather than a guide — it lives here to be run, not
  # read on hexdocs, and its slide markers render as noise there.
  defp livebooks do
    Path.wildcard("livebook/*.livemd") -- ["livebook/tempo_melbourne_september_2026.livemd"]
  end

  def groups_for_modules do
    [
      Core: ~r/^Tempo(?:\.(Interval|IntervalSet|Duration|Set))?$/,
      "Clock and current time": ~r/^Tempo\.Clock(\.|$)/,
      "Set algebra and comparison": ~r/^Tempo\.(Operations|Compare|Math|Select|Territory)$/,
      "Recurrence (RRULE)": ~r/^Tempo\.RRule(\.|$)/,
      "iCalendar integration": ~r/^Tempo\.ICal(\.|$)/,
      # `Tempo.Range` is the ISO 8601-2 set-member range element, not a
      # core algebra type — see its moduledoc.
      "ISO 8601 and IXDTF": ~r/^Tempo\.Iso8601(\.|$)|^Tempo\.Range$/,
      Enumeration: ~r/^Tempo\.Enumeration$|^Enumerable\.Tempo/,
      "Explanation and inspection":
        ~r/^Tempo\.(Explain|Explanation|Inspect|Format|Sigil|Validation)$/,
      Exceptions: ~r/^Tempo\.\w+Error$/
    ]
  end

  defp groups_for_extras do
    [
      Tutorial: [
        "guides/tutorial-booking-availability.md"
      ],
      Livebooks: [
        "livebook/getting-started.livemd",
        "livebook/tempo_tour.livemd",
        "livebook/scheduling-workbook.livemd",
        "livebook/uncertain-dates-workbook.livemd"
      ],
      Cookbooks: [
        "guides/cookbook.md",
        "guides/scheduling.md",
        "guides/workdays-and-weekends.md",
        "guides/holidays.md"
      ],
      Guides: [
        "guides/when-to-use-tempo.md",
        "guides/ai-assistance.md",
        "guides/interop.md",
        "guides/set-operations.md",
        "guides/uncertain-dates.md",
        "guides/enumeration-semantics.md",
        "guides/pattern-matching-with-sigils.md",
        "guides/ical-integration.md",
        "guides/chronological-networks.md",
        "guides/falsehoods.md"
      ],
      Reference: [
        "guides/iso8601-conformance.md",
        "guides/rfc5545_rrule_conformance.md",
        "guides/shared-ast-iso8601-and-rrule.md"
      ],
      Foundations: [
        "guides/temporal-formalisms.md",
        "guides/custom-calendars.md"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :localize]
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.0"},
      {:calendrical, "~> 1.0"},
      {:astro, "~> 2.4"},
      {:localize, "~> 1.0"},
      # 3.2 is the first release carrying VAVAILABILITY (RFC 7953), which
      # `Tempo.ICal.available/2` needs, so the floor cannot go lower.
      {:ical, "~> 3.2", optional: true},
      {:jscalendar, "~> 0.1", optional: true},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :release], optional: true, runtime: false},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test], runtime: false},
      # Tempo is time zone database agnostic: it works against the
      # `Calendar.TimeZoneDatabase` behaviour and consumers configure
      # their own implementation (`:tz`, `:tzdata`, `:time_zone_info`,
      # `:zoneinfo`) — see `Tempo.TimeZoneDatabase`. `tz` is used
      # locally for dev and test.
      {:tz, "~> 0.28", only: [:dev, :test]}
    ] ++ maybe_json_polyfill()
  end

  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0"}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
