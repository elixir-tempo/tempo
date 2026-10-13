defmodule Tempo.MixProject do
  use Mix.Project

  @version "3.0.0-dev"

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
      # Excluded from coverage: exception structs, whose uncovered lines are
      # `message/1` formatting on rare error paths, and the modules of
      # `test/support`, which are the measures the library is held to and
      # are compiled with the tests.
      test_coverage: [
        ignore_modules: [
          ~r/Error$/,
          ~r/^Tempo\.Matrix\./,
          ~r/^Tempo\.Grammar\./,
          Tempo.Golden,
          Tempo.Iso
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
    "Time as an interval, not an instant: ISO 8601 and IXDTF dates, times, " <>
      "intervals, durations, recurrences and sets, with Allen's relations and " <>
      "set algebra over them. Calendar- and time zone-aware."
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
      # The two pages that name what Tempo 1 had and 3.0 does not.
      skip_undefined_reference_warnings_on: ["CHANGELOG.md", "guides/migration.md"]
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
      Core: ~r/^Tempo(?:\.(Interval|IntervalSet|RecurrenceSet|Duration|Sigils))?$/,
      "Relations and selection": ~r/^Tempo\.(Allen|Workdays|Territory|Event|Event\.Resolver)$/,
      "Recurrence rules and calendar formats": ~r/^Tempo\.(RRule|Cron|ICal|JSCalendar)$/,
      "Clock, zones and leap seconds": ~r/^Tempo\.(Clock|Clock\.System|Zone|LeapSeconds)$/,
      "Units and limits": ~r/^Tempo\.(Unit|Scale|Limit|Explain)$/,
      Exceptions: ~r/^Tempo\.\w+Error$/
    ]
  end

  defp groups_for_extras do
    [
      Tutorial: [
        "guides/tutorial-booking-availability.md"
      ],
      Upgrading: [
        "guides/migration.md"
      ],
      Livebooks: [
        "livebook/getting-started.livemd",
        "livebook/tempo_tour.livemd",
        "livebook/scheduling-workbook.livemd",
        "livebook/uncertain-dates-workbook.livemd",
        "livebook/everyday-holidays.livemd"
      ],
      Cookbooks: [
        "guides/cookbook.md",
        "guides/scheduling.md",
        "guides/workdays-and-weekends.md",
        "guides/holidays.md",
        "guides/holiday-cookbook.md"
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
        "guides/falsehoods.md"
      ],
      Reference: [
        "guides/glossary.md",
        "guides/iso8601-conformance.md",
        "guides/iso8601-grammar.md",
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
      {:localize, github: "elixir-localize/localize", branch: "main", override: true},
      {:calendrical, github: "elixir-localize/calendrical", branch: "main", override: true},
      {:astro, "~> 2.7"},
      {:ical, "~> 3.2", optional: true},
      {:jscalendar, "~> 0.1", optional: true},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :release], optional: true, runtime: false},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.1", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test], runtime: false},
      {:tz, "~> 0.28", only: [:dev, :test]}
    ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end
end
