defmodule WandererNotifier.MixProject do
  use Mix.Project

  def project do
    [
      app: :wanderer_notifier,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {WandererNotifier.Application, []}
    ]
  end

  defp deps do
    [
      {:dotenvy, "~> 1.0.0"},
      {:httpoison, "~> 1.8"},
      {:cachex, "~> 3.4"},
      {:nostrum, "~> 0.5"},
      {:websockex, "~> 0.4"},
      {:jason, "~> 1.3"},
      {:plug, "~> 1.14"},
      {:plug_cowboy, "~> 2.6"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:exsync, "~> 0.2", only: :dev},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
