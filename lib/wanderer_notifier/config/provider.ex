defmodule WandererNotifier.ConfigProvider do
  import Kernel, except: [get_in: 2]

  @moduledoc """
  Provides configuration values for the application.
  """

  @doc """
  Initializes the configuration.
  """
  def init(config), do: config

  @doc """
  Loads configuration from environment variables.
  """
  def load(config), do: load(config, [])

  @doc """
  Loads configuration from environment variables with options.
  """
  def load(config, _opts) do
    config
    |> normalize_config()
    |> add_base_config()
    |> add_nostrum_config()
    |> add_discord_config()
    |> add_map_config()
    |> add_api_config()
    |> add_license_config()
    |> add_port_config()
    |> add_features_config()
    |> add_character_exclude_list()
    |> add_scheduler_config()
    |> add_additional_config()
    |> add_web_endpoint_config()
    |> add_redisq_config()
    |> add_cache_config()
  end

  @doc """
  Checks if notifications are enabled.
  """
  def notifications_enabled? do
    config = Application.get_env(:wanderer_notifier, :features, %{})
    Kernel.get_in(config, [:notifications_enabled])
  end

  @doc """
  Checks if kill notifications are enabled.
  """
  def kill_notifications_enabled? do
    config = Application.get_env(:wanderer_notifier, :features, %{})
    Kernel.get_in(config, [:kill_notifications_enabled])
  end

  @doc """
  Checks if system notifications are enabled.
  """
  def system_notifications_enabled? do
    config = Application.get_env(:wanderer_notifier, :features, %{})
    Kernel.get_in(config, [:system_notifications_enabled])
  end

  @doc """
  Checks if character notifications are enabled.
  """
  def character_notifications_enabled? do
    config = Application.get_env(:wanderer_notifier, :features, %{})
    Kernel.get_in(config, [:character_notifications_enabled])
  end

  @doc """
  Gets a configuration value using a list of keys.
  """
  def get_in(keys) do
    config = Application.get_env(:wanderer_notifier, :features, %{})
    Kernel.get_in(config, keys)
  end

  @doc """
  Gets a configuration value using a list of keys with a default value.
  """
  def get_in(keys, default) do
    config = Application.get_env(:wanderer_notifier, :features, %{})

    case Kernel.get_in(config, keys) do
      nil -> default
      value -> value
    end
  end

  # Private helper functions

  defp parse_port do
    System.get_env("PORT") |> WandererNotifier.Config.Utils.parse_port()
  end

  defp parse_bool(key, default) do
    case System.get_env(key) do
      nil ->
        default

      # Handle empty string explicitly
      "" ->
        default

      value ->
        normalized = value |> String.downcase() |> String.trim()

        if normalized == "" do
          # Handle whitespace-only strings
          default
        else
          parse_bool_value(normalized, default)
        end
    end
  end

  defp parse_bool_value(value, default) do
    boolean_values = %{
      "true" => true,
      "false" => false,
      "1" => true,
      "0" => false,
      "yes" => true,
      "no" => false,
      "y" => true,
      "n" => false,
      "t" => true,
      "f" => false,
      "on" => true,
      "off" => false
    }

    Map.get(boolean_values, value, default)
  end

  defp parse_character_exclude_list do
    System.get_env("CHARACTER_EXCLUDE_LIST")
    |> WandererNotifier.Config.Utils.parse_comma_list()
  end

  # Configuration building functions
  defp normalize_config(config) do
    case config do
      nil -> []
      [] -> []
      list when is_list(list) -> list
      map when is_map(map) -> Map.to_list(map)
    end
  end

  defp add_base_config(config) do
    config
    |> Keyword.put(:wanderer_notifier, [])
    |> put_in([:wanderer_notifier, :features], [])
    |> put_in([:wanderer_notifier, :config], WandererNotifier.Config)
  end

  defp add_discord_config(config) do
    config
    |> put_in([:wanderer_notifier, :discord_channel_id], System.get_env("DISCORD_CHANNEL_ID"))
    |> put_in(
      [:wanderer_notifier, :discord_application_id],
      System.get_env("DISCORD_APPLICATION_ID")
    )
    |> put_in([:wanderer_notifier, :discord_bot_token], System.get_env("DISCORD_BOT_TOKEN"))
    |> put_in(
      [:wanderer_notifier, :discord_system_kill_channel_id],
      System.get_env("DISCORD_SYSTEM_KILL_CHANNEL_ID")
    )
    |> put_in(
      [:wanderer_notifier, :discord_character_kill_channel_id],
      System.get_env("DISCORD_CHARACTER_KILL_CHANNEL_ID")
    )
    |> put_in(
      [:wanderer_notifier, :discord_system_channel_id],
      System.get_env("DISCORD_SYSTEM_CHANNEL_ID")
    )
    |> put_in(
      [:wanderer_notifier, :discord_character_channel_id],
      System.get_env("DISCORD_CHARACTER_CHANNEL_ID")
    )
  end

  defp add_map_config(config) do
    map_url = System.get_env("MAP_URL")
    map_name = System.get_env("MAP_NAME")

    # Build map_url_with_name from required MAP_URL and MAP_NAME
    map_url_with_name =
      if map_url && map_name do
        base_url = String.trim_trailing(map_url, "/")
        "#{base_url}/?name=#{map_name}"
      else
        nil
      end

    config
    |> put_in([:wanderer_notifier, :map_token], System.get_env("MAP_API_KEY"))
    |> put_in([:wanderer_notifier, :map_url_with_name], map_url_with_name)
    |> put_in([:wanderer_notifier, :map_url], map_url)
    |> put_in([:wanderer_notifier, :map_name], map_name)
    |> put_in([:wanderer_notifier, :map_api_key], System.get_env("MAP_API_KEY"))
  end

  defp add_api_config(config) do
    put_in(
      config,
      [:wanderer_notifier, :api_token],
      System.get_env("NOTIFIER_API_TOKEN")
    )
  end

  defp add_license_config(config) do
    put_in(config, [:wanderer_notifier, :license_key], System.get_env("LICENSE_KEY"))
  end

  defp add_port_config(config) do
    put_in(config, [:wanderer_notifier, :port], parse_port())
  end

  defp add_features_config(config) do
    put_in(
      config,
      [:wanderer_notifier, :features],
      notifications_enabled: parse_bool("NOTIFICATIONS_ENABLED", true),
      kill_notifications_enabled: parse_bool("KILL_NOTIFICATIONS_ENABLED", true),
      system_notifications_enabled: parse_bool("SYSTEM_NOTIFICATIONS_ENABLED", true),
      character_notifications_enabled: parse_bool("CHARACTER_NOTIFICATIONS_ENABLED", true),
      status_messages_enabled: parse_bool("ENABLE_STATUS_MESSAGES", false),
      track_kspace: parse_bool("TRACK_KSPACE_ENABLED", true),
      # Tracking is always enabled
      character_tracking_enabled: true,
      system_tracking_enabled: true
    )
  end

  defp add_character_exclude_list(config) do
    put_in(
      config,
      [:wanderer_notifier, :character_exclude_list],
      parse_character_exclude_list()
    )
  end

  defp add_nostrum_config(config) do
    config
    |> Keyword.put(:nostrum,
      token: System.get_env("DISCORD_BOT_TOKEN"),
      gateway_intents: [:guilds, :guild_messages]
    )
  end

  defp add_scheduler_config(config) do
    config
    |> put_in([:wanderer_notifier, :system_update_scheduler_interval], 30_000)
    |> put_in([:wanderer_notifier, :character_update_scheduler_interval], 30_000)
  end

  defp add_additional_config(config) do
    config
    |> put_in(
      [:wanderer_notifier, :priority_systems_only],
      parse_bool("PRIORITY_SYSTEMS_ONLY", false)
    )
    |> put_in(
      [:wanderer_notifier, :license_manager_api_url],
      System.get_env("LICENSE_MANAGER_URL") || "https://lm.wanderer.ltd"
    )
    |> put_in([:wanderer_notifier, :cache_dir], System.get_env("CACHE_DIR") || "/app/data/cache")
    |> put_in([:wanderer_notifier, :public_url], System.get_env("PUBLIC_URL"))
    |> put_in([:wanderer_notifier, :host], System.get_env("HOST") || "localhost")
    |> put_in([:wanderer_notifier, :scheme], System.get_env("SCHEME") || "http")
  end

  defp add_web_endpoint_config(config) do
    port = parse_port()
    host = System.get_env("HOST") || "localhost"

    # Get existing config and ensure it's a keyword list
    wanderer_config = Keyword.get(config, :wanderer_notifier, [])

    # Add endpoint config
    updated_wanderer_config =
      Keyword.put(wanderer_config, WandererNotifierWeb.Endpoint,
        url: [host: host],
        http: [port: port],
        server: true
      )

    # Put it back
    Keyword.put(config, :wanderer_notifier, updated_wanderer_config)
  end

  defp add_redisq_config(config) do
    # Legacy config name kept for backward compatibility
    # Killmail processing is always enabled
    put_in(config, [:wanderer_notifier, :redisq], %{
      enabled: true,
      url: System.get_env("REDISQ_URL") || "https://zkillredisq.stream/listen.php",
      poll_interval: parse_int(System.get_env("REDISQ_POLL_INTERVAL_MS"), 1000)
    })
  end

  defp add_cache_config(config) do
    put_in(config, [:wanderer_notifier, :cache], %{
      directory: System.get_env("CACHE_DIR") || "/app/data/cache"
    })
  end

  defp parse_int(nil, default), do: default

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> default
    end
  end
end
