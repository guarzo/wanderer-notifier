defmodule WandererNotifier.Config.Version do
  @moduledoc """
  Configuration module for application version information.

  This module centralizes all version-related configuration,
  providing a standardized interface for retrieving version information.
  Version information is set at compile time rather than through
  environment variables.
  """

  # Read from mix.exs at compile time
  @version (case File.read("mix.exs") do
              {:ok, content} ->
                Regex.run(~r/version: "([^"]+)"/, content)
                |> case do
                  [_, version] -> version
                  _ -> "0.0.0"
                end

              _ ->
                "0.0.0"
            end)

  @doc """
  Returns the application version string.
  This is determined at compile time from mix.exs.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Returns the application version components as a tuple of integers.
  """
  @spec version_tuple() :: {integer(), integer(), integer()}
  def version_tuple do
    @version
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  end

  @doc """
  Returns a map containing version information for use in logs and API responses.
  """
  @spec version_info() :: map()
  def version_info do
    %{
      version: version(),
      major: elem(version_tuple(), 0),
      minor: elem(version_tuple(), 1),
      patch: elem(version_tuple(), 2)
    }
  end

  @doc """
  Checks if the current version is at least the specified minimum version.
  """
  @spec at_least?(String.t()) :: boolean()
  def at_least?(min_version) do
    current = version_tuple()

    min_version
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
    |> then(fn min ->
      compare_versions(current, min) >= 0
    end)
  end

  # Private helper to compare version tuples
  defp compare_versions({major1, minor1, patch1}, {major2, minor2, patch2}) do
    cond do
      major1 > major2 -> 1
      major1 < major2 -> -1
      minor1 > minor2 -> 1
      minor1 < minor2 -> -1
      patch1 > patch2 -> 1
      patch1 < patch2 -> -1
      true -> 0
    end
  end
end
