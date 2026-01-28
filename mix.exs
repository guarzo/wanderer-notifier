defmodule WandererNotifier.MixProject do
  use Mix.Project

  def project do
    [
      app: :wanderer_notifier,
      version: "5.0.8",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      validate_compile_env: false,
      test_coverage: [tool: ExCoveralls],
      dialyzer: [ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  @doc """
  Mix CLI callback for setting preferred environments for specific tasks.
  This is the modern approach (Mix 1.12+) replacing the deprecated preferred_cli_env option.
  """
  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.json": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: extra_applications(Mix.env()),
      mod: {WandererNotifier.Application, []},
      included_applications: [],
      env: [],
      registered: [],
      priv_dir: "priv"
    ]
  end

  # Don't start Nostrum in test mode - it tries to connect to Discord gateway
  defp extra_applications(:test), do: [:logger]
  defp extra_applications(_), do: [:logger, :nostrum]

  defp deps do
    [
      {:dotenvy, "~> 1.1"},
      {:httpoison, "~> 2.3"},
      {:req, "~> 0.5"},
      {:cachex, "~> 4.1"},
      {:nostrum, "~> 0.10", runtime: Mix.env() != :test},
      {:websockex, "~> 0.5"},
      {:slipstream, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.3"},
      {:plug, "~> 1.19"},
      {:plug_cowboy, "~> 2.7"},
      {:mime, "~> 2.0"},
      {:decimal, "~> 2.3"},
      {:logger_file_backend, "~> 0.0.14"},
      {:logger_backends, "~> 1.0"},
      # Phoenix & Ecto
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_pubsub, "~> 2.2"},
      {:ecto, "~> 3.13"},
      {:mint_web_socket, "~> 1.0"},
      # Rate limiting
      {:hammer, "~> 7.1"},
      # Development & Testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:bunt, "~> 1.0"},
      {:exsync, "~> 0.4", only: :dev},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.2", only: [:dev, :test]},
      {:crontab, "~> 1.2"},
      {:excoveralls, "~> 0.18", only: :test},
      {:benchfella, "~> 0.3", only: :dev},
      {:mix_version, "~> 2.5", only: [:dev, :test], runtime: false}
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
