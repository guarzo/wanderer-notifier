defmodule WandererNotifier.MixProject do
  use Mix.Project

  def project do
    [
      app: :wanderer_notifier,
      version: get_version(),
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      overrides: overrides(),
      validate_compile_env: false,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.json": :test
      ],
      aliases: [
        "release.bump": ["version --bump patch"],
        version: "version"
      ]
    ]
  end

  # Get version - check for VERSION file first, then try MixVersion
  defp get_version do
    cond do
      # Try to read from VERSION file first
      File.exists?("VERSION") ->
        File.read!("VERSION") |> String.trim()

      # For Docker builds or other environments where mix_version may not be available
      true ->
        # Default version when neither source is available
        System.get_env("APP_VERSION") || "0.1.0"
    end
  end

  # Specifies which paths to compile per environment
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
      {:jason, "~> 1.4"},
      {:plug, "~> 1.17"},
      {:plug_cowboy, "~> 2.7"},
      {:mime, "~> 2.0"},
      {:decimal, "~> 2.3"},
      {:logger_file_backend, "~> 0.0.14"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:bunt, "~> 1.0"},
      {:exsync, "~> 0.4", only: :dev},
      {:mox, "~> 1.2", only: :test},
      {:crontab, "~> 1.1"},
      {:excoveralls, "~> 0.18", only: :test},
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
        overlays: ["rel/overlays"],
        config_providers: [{WandererNotifier.ConfigProvider, []}]
      ]
    ]
  end

  defp overrides do
    [
      {:ranch, "2.1.0", override: true}
    ]
  end
end
