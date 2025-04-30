defmodule WandererNotifier.Utilities.Debug do
  @moduledoc """
  Debug utilities for WandererNotifier. Only for development use.
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Map.Client, as: MapClient
  alias WandererNotifier.Config.Config, as: AppConfig
  alias WandererNotifier.Config.Debug, as: DebugConfig
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Logger.Logger, as: AppLogger

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
    core_url = AppConfig.map_url()
    core_name = AppConfig.map_name()
    core_token = AppConfig.map_token()

    # Get map settings from Debug config module
    debug_settings = DebugConfig.map_debug_settings()

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
      debug_config: debug_settings
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
    result = HttpClient.get(url, headers)

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
    alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
    # Updated to new path
    alias WandererNotifier.Config.Config, as: AppConfig

    # Build the URL and headers directly
    base_url = Application.get_env(:wanderer_notifier, :map_url)
    token = Application.get_env(:wanderer_notifier, :map_token)
    url = base_url <> "/api/map/characters"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    # Make direct API call with full debug
    response =
      case url do
        url when is_binary(url) and url != "" ->
          IO.puts("Making request to URL: #{url}")
          IO.puts("With headers: #{inspect(headers)}")
          HttpClient.get(url, headers)

        _ ->
          IO.puts("URL builder error: #{inspect(url)}")
          {:error, :invalid_url}
      end

    # Get map settings from Debug config
    debug_settings = DebugConfig.map_debug_settings()

    # Return complete debug info
    %{
      url_result: url,
      headers: headers,
      response: response,
      config: %{
        map_url: AppConfig.map_url(),
        map_name: AppConfig.map_name(),
        map_token: AppConfig.map_token(),
        debug_settings: debug_settings
      }
    }
  end
end
