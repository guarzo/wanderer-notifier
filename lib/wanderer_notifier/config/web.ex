defmodule WandererNotifier.Config.Web do
  @moduledoc """
  Configuration module for web server settings.

  This module centralizes all web-related configuration access,
  providing a standardized interface for retrieving web server settings
  and validating configuration values.
  """

  require Logger

  @default_web_port 4000
  @default_host "localhost"
  @default_scheme "http"
  @default_chart_service_port 3001

  @type url_config :: %{
          host: String.t(),
          port: integer(),
          scheme: String.t()
        }

  @doc """
  Returns the complete web configuration map for use with Phoenix and other web components.
  """
  @spec config() :: map()
  def config do
    %{
      port: port(),
      host: host(),
      scheme: scheme(),
      public_url: public_url(),
      secret_key_base: secret_key_base()
    }
  end

  @doc """
  Returns the web server port from environment configuration.

  Prioritizes WANDERER_PORT over the legacy PORT variable.
  """
  @spec port() :: integer()
  def port do
    get_env(:port, 4000)
  end

  @doc """
  Returns the web server hostname from environment configuration.

  Prioritizes WANDERER_HOST over the legacy HOST variable.
  """
  @spec host() :: String.t()
  def host do
    get_env(:host, "localhost")
  end

  @doc """
  Returns the URL scheme (http/https) from environment configuration.

  Prioritizes WANDERER_SCHEME over the legacy SCHEME variable.
  """
  @spec scheme() :: String.t()
  def scheme do
    get_env(:scheme, "http")
  end

  @doc """
  Returns the public URL from environment configuration.

  This is used for generating external links.
  Prioritizes WANDERER_PUBLIC_URL over the legacy PUBLIC_URL variable.
  """
  @spec public_url() :: String.t() | nil
  def public_url do
    get_env(:public_url, nil)
  end

  @doc """
  Returns the secret key base for the web application.

  This is used for signing and encryption.
  """
  @spec secret_key_base() :: String.t()
  def secret_key_base do
    get_env(:secret_key_base, nil)
  end

  @doc """
  Returns the full URL to the application, constructed from scheme, host, and port.
  """
  @spec url() :: String.t()
  def url do
    "#{scheme()}://#{host()}:#{port()}"
  end

  @doc """
  Validates that all required web configuration values are present and valid.

  Returns :ok if the configuration is valid, or {:error, reason} if not.
  """
  @spec validate() :: :ok | {:error, String.t()}
  def validate do
    # Validate port is a number and within range
    port = port()

    cond do
      !is_integer(port) ->
        {:error, "Web port must be an integer"}

      port < 1 || port > 65_535 ->
        {:error, "Web port must be between 1 and 65535"}

      host() == "" ->
        {:error, "Web host cannot be empty"}

      !(scheme() in ["http", "https"]) ->
        {:error, "Web scheme must be 'http' or 'https'"}

      true ->
        :ok
    end
  end

  @doc """
  Gets the URL configuration.
  """
  @spec get_url_config() :: url_config()
  def get_url_config do
    case get_env(:public_url, nil) do
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
  Alias for port() for backward compatibility.
  """
  def get_web_port do
    port()
  end

  @doc """
  Get the web server port.
  """
  def get_web_server_port do
    get_env(:web_server_port, 4000)
  end

  @doc """
  Get the chart service port.
  """
  def get_chart_service_port do
    get_env(:chart_service_port, @default_chart_service_port)
  end

  # Private helper function to get configuration values
  defp get_env(key, default) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
