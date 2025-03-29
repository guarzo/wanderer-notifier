defmodule WandererNotifier.Config.Web do
  @moduledoc """
  Configuration module for web-related settings.
  Handles web server configuration, ports, and URLs.
  """

  require Logger

  @default_web_port 4000
  @default_host "localhost"
  @default_scheme "http"

  @type url_config :: %{
          host: String.t(),
          port: integer(),
          scheme: String.t()
        }

  @doc """
  Gets the web port configuration.
  Defaults to 4000 if not set.
  """
  @spec get_web_port() :: integer()
  def get_web_port do
    get_env(:web_port, @default_web_port)
  end

  @doc """
  Gets the chart service port configuration.
  """
  @spec get_chart_service_port() :: integer()
  def get_chart_service_port do
    get_env(:chart_service_port, @default_web_port)
  end

  @doc """
  Gets the URL configuration.
  """
  @spec get_url_config() :: url_config()
  def get_url_config do
    case get_env(:public_url) do
      nil ->
        %{
          host: get_env(:host, @default_host),
          port: get_env(:port, @default_web_port),
          scheme: get_env(:scheme, @default_scheme)
        }

      url ->
        uri = URI.parse(url)

        %{
          host: uri.host,
          port: uri.port || @default_web_port,
          scheme: uri.scheme || @default_scheme
        }
    end
  end

  @doc """
  Get the web configuration.
  """
  def get_web_config do
    {:ok, get_env(:web, %{})}
  end

  @doc """
  Get the web server port.
  """
  def get_web_server_port do
    get_env(:web_server_port, 4000)
  end

  # Private helper to get configuration with optional default
  defp get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
