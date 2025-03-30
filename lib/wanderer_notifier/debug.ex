defmodule WandererNotifier.Debug do
  @moduledoc """
  Debug utilities for WandererNotifier. Only for development use.
  """

  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Map.Client, as: MapClient
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Manually trigger character tracking update.
  """
  def trigger_character_tracking_update do
    AppLogger.processor_warn("DEBUG: Manually triggering character tracking update")
    result = MapClient.update_tracked_characters()
    AppLogger.processor_warn("DEBUG: Character tracking update result: #{inspect(result)}")
    result
  end

  @doc """
  Print current feature flags configuration.
  """
  def print_feature_flags do
    feature_flags = Application.get_env(:wanderer_notifier, :features, %{})
    AppLogger.processor_warn("DEBUG: Current feature flags: #{inspect(feature_flags)}")

    # Check character tracking specifically
    tracking_enabled = Features.character_tracking_enabled?()
    AppLogger.processor_warn("DEBUG: Character tracking enabled? #{tracking_enabled}")

    feature_flags
  end

  @doc """
  Check map URL configuration.
  """
  def check_map_config do
    url_with_name = Application.get_env(:wanderer_notifier, :map_url_with_name)
    url = Application.get_env(:wanderer_notifier, :map_url)
    name = Application.get_env(:wanderer_notifier, :map_name)
    token = Application.get_env(:wanderer_notifier, :map_token)

    # Check Config module access
    core_url = Config.map_url()
    core_name = Config.map_name()
    core_token = Config.map_token()

    %{
      env: %{
        map_url_with_name: url_with_name,
        map_url: url,
        map_name: name,
        map_token: token
      },
      config: %{
        map_url: core_url,
        map_name: core_name,
        map_token: core_token
      },
      vars: %{
        map_url_with_name: System.get_env("MAP_URL_WITH_NAME"),
        map_url: System.get_env("MAP_URL"),
        map_name: System.get_env("MAP_NAME"),
        map_token: System.get_env("MAP_TOKEN")
      }
    }
  end

  @doc """
  Test characters endpoint directly.
  """
  def test_characters_endpoint do
    # Get map URL components
    config = check_map_config()

    # Build URL directly
    uri = URI.parse(config.env.map_url_with_name || "")
    base_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"
    slug = uri.path |> String.trim("/") |> String.split("/") |> List.last() || ""
    url = "#{base_url}/api/map/characters?slug=#{URI.encode_www_form(slug)}"

    # Build headers
    headers = [
      {"Authorization", "Bearer #{config.env.map_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    # Make request
    result = Client.get(url, headers)

    %{
      url: url,
      headers: headers,
      result: result
    }
  end

  @doc """
  Directly test characters API endpoint with full debug information.
  """
  def direct_test_characters_api do
    alias WandererNotifier.Api.Http.Client
    alias WandererNotifier.Api.Map.UrlBuilder
    alias WandererNotifier.Core.Config

    # Get URL directly
    url_result = UrlBuilder.build_url("map/characters")

    # Get headers directly
    headers = UrlBuilder.get_auth_headers()

    # Make direct API call with full debug
    response =
      case url_result do
        {:ok, url} ->
          IO.puts("Making request to URL: #{url}")
          IO.puts("With headers: #{inspect(headers)}")
          Client.get(url, headers)

        {:error, reason} ->
          IO.puts("URL builder error: #{inspect(reason)}")
          {:error, reason}
      end

    # Return complete debug info
    %{
      url_result: url_result,
      headers: headers,
      response: response,
      config: %{
        map_url: Config.map_url(),
        map_name: Config.map_name(),
        map_token: Config.map_token(),
        env_vars: %{
          MAP_URL: System.get_env("MAP_URL"),
          MAP_NAME: System.get_env("MAP_NAME"),
          MAP_TOKEN: System.get_env("MAP_TOKEN")
        }
      }
    }
  end
end
