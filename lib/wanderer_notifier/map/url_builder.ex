defmodule WandererNotifier.Map.UrlBuilder do
  @moduledoc """
  Builds URLs and authentication headers for the map API.
  """

  alias WandererNotifier.Config.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Builds a URL for the Wanderer Map API.

  ## Parameters
    - path: The API endpoint path to append to the base URL

  ## Returns
    - {:ok, url} on success
    - {:error, reason} on failure
  """
  @spec build_url(String.t()) :: {:ok, String.t()} | {:error, term()}
  def build_url(path) do
    # Use the configured base URL and append the path
    case map_url() do
      {:ok, base_url} ->
        # Ensure the path doesn't start with a slash
        path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//-1), else: path
        # Ensure the base URL ends with a slash
        url = if String.ends_with?(base_url, "/"), do: base_url, else: base_url <> "/"
        {:ok, url <> path}

      {:error, reason} ->
        AppLogger.api_error("[UrlBuilder] Failed to get map URL", error: reason)
        {:error, {:domain_error, :map, {:config_error, reason}}}
    end
  end

  @doc """
  Returns authentication headers for the map API.

  ## Returns
    - List of headers, including authorization if available
  """
  @spec get_auth_headers() :: [{String.t(), String.t()}]
  def get_auth_headers do
    case map_api_key() do
      {:ok, api_key} ->
        [{"Authorization", "Bearer #{api_key}"}, {"Content-Type", "application/json"}]

      _ ->
        # No authorization header if no API key is available
        AppLogger.api_warn("[UrlBuilder] No map API key available")
        [{"Content-Type", "application/json"}]
    end
  end

  # Private function to get map URL from config
  defp map_url do
    case Config.map_url() do
      nil -> {:error, :missing_map_url}
      url -> {:ok, url}
    end
  end

  # Private function to get map API key from config
  defp map_api_key do
    case Config.map_api_key() do
      nil -> {:error, :missing_api_key}
      key -> {:ok, key}
    end
  end
end
