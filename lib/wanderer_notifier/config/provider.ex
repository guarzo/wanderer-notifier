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
    config =
      case config do
        nil -> []
        [] -> []
        list when is_list(list) -> list
        map when is_map(map) -> Map.to_list(map)
      end

    config = Keyword.put(config, :wanderer_notifier, [])
    config = put_in(config, [:wanderer_notifier, :features], [])

    # Set core configuration values including the config_module
    config = put_in(config, [:wanderer_notifier, :config], WandererNotifier.Config)

    # Set discord channel ID
    config =
      put_in(
        config,
        [:wanderer_notifier, :discord_channel_id],
        System.get_env("WANDERER_DISCORD_CHANNEL_ID")
      )

    # Set map token and URL
    config =
      put_in(config, [:wanderer_notifier, :map_token], System.get_env("WANDERER_MAP_TOKEN"))

    config =
      put_in(config, [:wanderer_notifier, :map_url_with_name], System.get_env("WANDERER_MAP_URL"))

    # Set API token
    config =
      put_in(
        config,
        [:wanderer_notifier, :api_token],
        System.get_env("WANDERER_NOTIFIER_API_TOKEN")
      )

    # Set license key
    config =
      put_in(config, [:wanderer_notifier, :license_key], System.get_env("WANDERER_LICENSE_KEY"))

    config
    |> put_in([:wanderer_notifier, :port], parse_port())
    |> put_in(
      [:wanderer_notifier, :features],
      notifications_enabled: parse_bool("WANDERER_NOTIFICATIONS_ENABLED", true),
      kill_notifications_enabled: parse_bool("WANDERER_KILL_NOTIFICATIONS_ENABLED", true),
      system_notifications_enabled: parse_bool("WANDERER_SYSTEM_NOTIFICATIONS_ENABLED", true),
      character_notifications_enabled:
        parse_bool("WANDERER_CHARACTER_NOTIFICATIONS_ENABLED", true),
      status_messages_enabled: parse_bool("WANDERER_ENABLE_STATUS_MESSAGES", true),
      track_kspace: parse_bool("WANDERER_FEATURE_TRACK_KSPACE", true)
    )
    |> put_in([:wanderer_notifier, :character_exclude_list], parse_character_exclude_list())
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
    case System.get_env("PORT") do
      nil ->
        4000

      port_str ->
        case Integer.parse(port_str) do
          {port, _} -> port
          :error -> 4000
        end
    end
  end

  defp parse_bool(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> parse_bool_value(String.downcase(String.trim(value)), default)
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
    case System.get_env("WANDERER_CHARACTER_EXCLUDE_LIST") do
      nil ->
        []

      value ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
    end
  end
end
