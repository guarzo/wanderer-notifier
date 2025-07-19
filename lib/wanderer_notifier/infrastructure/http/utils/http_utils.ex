defmodule WandererNotifier.Infrastructure.Http.Utils.HttpUtils do
  @moduledoc """
  Shared HTTP utility functions used across middleware components.
  """

  @doc """
  Extracts the host from a URL.

  Returns the hostname from a URL string, or "unknown" if the URL is invalid
  or doesn't contain a host.

  ## Examples

      iex> HttpUtils.extract_host("https://api.example.com/path")
      "api.example.com"
      
      iex> HttpUtils.extract_host("invalid-url")
      "unknown"
  """
  @spec extract_host(String.t()) :: String.t()
  def extract_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> "unknown"
    end
  end
end
