defmodule WandererNotifier.MixProject do
  use Mix.Project

  def project do
    [
      app: :wanderer_notifier,
      version: "1.0.10",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      overrides: overrides()
    ]
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
      {:cachex, "~> 4.0"},
      {:nostrum, "~> 0.10"},
      {:websockex, "~> 0.4"},
      {:jason, "~> 1.3"},
      {:plug, "~> 1.17"},
      {:plug_cowboy, "~> 2.6"},
      {:mime, "~> 2.0"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:ash, "~> 3.4"},
      {:ash_postgres, "~> 2.5"},
      {:decimal, "~> 2.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:bunt, "~> 0.2.1"},
      {:exsync, "~> 0.2", only: :dev},
      {:mox, "~> 1.0", only: :test}
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

  defp overrides do
    [
      {:ranch, "2.1.0", override: true}
    ]
  end
end
