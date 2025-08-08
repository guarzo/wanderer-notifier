defmodule WandererNotifier.MixProject do
  use Mix.Project

  def project do
    [
      app: :wanderer_notifier,
      version: "3.3.2",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      validate_compile_env: false,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.json": :test
      ],
      dialyzer: [ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :nostrum],
      mod: {WandererNotifier.Application, []},
      included_applications: [],
      env: [],
      registered: [],
      priv_dir: "priv"
    ]
  end

  defp deps do
    [
      {:dotenvy, "~> 1.1"},
      {:httpoison, "~> 2.2"},
      {:req, "~> 0.4"},
      {:cachex, "~> 4.1"},
      {:nostrum, "~> 0.10"},
      {:websockex, "~> 0.4"},
      {:slipstream, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.2"},
      {:plug, "~> 1.18"},
      {:plug_cowboy, "~> 2.7"},
      {:mime, "~> 2.0"},
      {:decimal, "~> 2.3"},
      {:logger_file_backend, "~> 0.0.14"},
      # Phoenix & Ecto
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto, "~> 3.12"},
      {:mint_web_socket, "~> 1.0"},
      # Rate limiting
      {:hammer, "~> 7.0"},
      # Development & Testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.3", only: [:dev, :test], runtime: false},
      {:bunt, "~> 1.0"},
      {:exsync, "~> 0.4", only: :dev},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:crontab, "~> 1.1"},
      {:excoveralls, "~> 0.18", only: :test},
      {:benchfella, "~> 0.3", only: :dev},
      {:mix_version, "~> 2.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp releases do
    [
      wanderer_notifier: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar],
        validate_compile_env: false,
        overlays: ["rel/overlays"]
      ]
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ],
      "test.coverage": ["coveralls.html"],
      "test.coverage.ci": ["coveralls.json"],
      "release.bump": ["version --bump patch"],
      version: "version"
    ]
  end
end
