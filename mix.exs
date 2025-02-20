defmodule ChainKills.MixProject do
  use Mix.Project

  def project do
    [
      app: :chainkills,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ChainKills.Application, []},
      extra_applications: [:logger]
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:exsync, "~> 0.2", only: :dev}
    ]
  end
end
