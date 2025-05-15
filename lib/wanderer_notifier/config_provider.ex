defmodule WandererNotifier.ConfigProvider do
  @moduledoc """
  Configuration provider for WandererNotifier application.
  Loads environment variables from .env file and applies them to the application configuration.
  """
  @behaviour Config.Provider

  @doc """
  Initialize the provider with the given config.
  """
  def init(config), do: config

  @doc """
  Load environment variables and apply them to the application configuration.
  Required by the Config.Provider behaviour.
  """
  def load(config, _opts) do
    # Ensure we received a keyword list
    unless Keyword.keyword?(config) do
      raise ArgumentError, "Config provider expects a keyword list, got: #{inspect(config)}"
    end

    # Ensure config has the basic structure needed
    config = ensure_config_structure(config)

    # Apply environment variables to configuration
    config =
      load_env_file()
      |> Enum.reduce(config, fn {key, value}, config ->
        apply_env(config, key, value)
      end)

    # Handle environment variables directly from System.get_env for tests
    # This ensures system environment variables get correctly processed as well
    system_env_vars = [
      "WANDERER_CHARACTER_EXCLUDE_LIST",
      "WANDERER_NOTIFICATIONS_ENABLED",
      "PORT"
    ]

    Enum.reduce(system_env_vars, config, fn key, config ->
      case System.get_env(key) do
        nil -> config
        value -> apply_env(config, key, value)
      end
    end)
  end

  @doc """
  Legacy load/1 function for backward compatibility.
  Delegates to load/2 with empty options.
  """
  def load(config) do
    load(config, [])
  end

  # Ensure config has required structure to avoid "nil value" errors with put_in
  defp ensure_config_structure(config) when is_map(config) do
    # Initialize base app configs
    config = Map.put_new(config, :nostrum, %{})

    # Initialize main app config with default values
    base_config = Map.get(config, :wanderer_notifier, %{})
    base_config = Map.put_new(base_config, :port, 4000)
    config = Map.put(config, :wanderer_notifier, base_config)

    # Ensure nested configs exist
    config
    |> ensure_nested_config([:wanderer_notifier, :features], %{})
    |> ensure_nested_config([:wanderer_notifier, :websocket], %{})
    |> ensure_nested_config([:wanderer_notifier, :character_exclude_list], [])
  end

  defp ensure_config_structure(config) when is_list(config) do
    # Initialize base app configs
    config = Keyword.put_new(config, :nostrum, %{})

    # Initialize main app config with default values
    base_config = Keyword.get(config, :wanderer_notifier, %{})
    base_config = Map.put_new(base_config, :port, 4000)
    config = Keyword.put(config, :wanderer_notifier, base_config)

    # Ensure nested configs exist
    config
    |> ensure_nested_config([:wanderer_notifier, :features], %{})
    |> ensure_nested_config([:wanderer_notifier, :websocket], %{})
    |> ensure_nested_config([:wanderer_notifier, :character_exclude_list], [])
  end

  # Ensure a nested configuration exists
  defp ensure_nested_config(config, [key | rest], default) when is_map(config) do
    current = Map.get(config, key, %{})
    updated = ensure_nested_config(current, rest, default)
    Map.put(config, key, updated)
  end

  defp ensure_nested_config(config, [key | rest], default) when is_list(config) do
    current = Keyword.get(config, key, %{})
    updated = ensure_nested_config(current, rest, default)
    Keyword.put(config, key, updated)
  end

  defp ensure_nested_config(config, [], default) when is_map(config) do
    if map_size(config) > 0 do
      config
    else
      default
    end
  end

  defp ensure_nested_config(config, [], default) when is_list(config) do
    if length(config) > 0 do
      config
    else
      default
    end
  end

  defp ensure_nested_config(_, [], default), do: default

  # Load environment variables from .env file
  defp load_env_file do
    try do
      case Dotenvy.source(".env") do
        {:ok, env_map} when is_map(env_map) -> env_map
        _ -> %{}
      end
    rescue
      e ->
        require Logger

        Logger.info(
          "No .env file found or error loading it: #{Exception.message(e)}. Using existing environment variables."
        )

        %{}
    end
    |> Enum.map(fn {k, v} ->
      # Only set env vars that aren't already present
      case System.get_env(k) do
        nil ->
          System.put_env(k, v)
          {k, v}

        existing ->
          {k, existing}
      end
    end)
    |> Map.new()
  end

  # Apply environment variables to configuration
  defp apply_env(config, "WANDERER_DISCORD_BOT_TOKEN", val),
    do: put_in(config, [:nostrum, :token], val)

  defp apply_env(config, "WANDERER_MAP_TOKEN", val),
    do: put_in(config, [:wanderer_notifier, :map_token], val)

  defp apply_env(config, "WANDERER_NOTIFIER_API_TOKEN", val),
    do: put_in(config, [:wanderer_notifier, :api_token], val)

  defp apply_env(config, "WANDERER_LICENSE_KEY", val),
    do: put_in(config, [:wanderer_notifier, :license_key], val)

  defp apply_env(config, "WANDERER_MAP_URL", val),
    do: put_in(config, [:wanderer_notifier, :map_url_with_name], val)

  defp apply_env(config, "WANDERER_DISCORD_CHANNEL_ID", val),
    do: put_in(config, [:wanderer_notifier, :discord_channel_id], val)

  defp apply_env(config, "PORT", val),
    do: put_in(config, [:wanderer_notifier, :port], parse_port(val, 4000))

  defp apply_env(config, "WANDERER_DISCORD_SYSTEM_KILL_CHANNEL_ID", val),
    do: put_in(config, [:wanderer_notifier, :discord_system_kill_channel_id], val || "")

  defp apply_env(config, "WANDERER_CHARACTER_KILL_CHANNEL_ID", val),
    do: put_in(config, [:wanderer_notifier, :discord_character_kill_channel_id], val || "")

  defp apply_env(config, "WANDERER_SYSTEM_CHANNEL_ID", val),
    do: put_in(config, [:wanderer_notifier, :discord_system_channel_id], val || "")

  defp apply_env(config, "WANDERER_CHARACTER_CHANNEL_ID", val),
    do: put_in(config, [:wanderer_notifier, :discord_character_channel_id], val || "")

  defp apply_env(config, "WANDERER_DISCORD_KILL_CHANNEL_ID", val),
    do: put_in(config, [:wanderer_notifier, :kill_channel_id], val || "")

  defp apply_env(config, "WANDERER_LICENSE_MANAGER_URL", val),
    do:
      put_in(
        config,
        [:wanderer_notifier, :license_manager_api_url],
        val || "https://lm.wanderer.ltd"
      )

  defp apply_env(config, "WANDERER_NOTIFICATIONS_ENABLED", val),
    do: put_in(config, [:wanderer_notifier, :features, :notifications_enabled], parse_bool(val))

  defp apply_env(config, "WANDERER_CHARACTER_NOTIFICATIONS_ENABLED", val),
    do:
      put_in(
        config,
        [:wanderer_notifier, :features, :character_notifications_enabled],
        parse_bool(val)
      )

  defp apply_env(config, "WANDERER_SYSTEM_NOTIFICATIONS_ENABLED", val),
    do:
      put_in(
        config,
        [:wanderer_notifier, :features, :system_notifications_enabled],
        parse_bool(val)
      )

  defp apply_env(config, "WANDERER_KILL_NOTIFICATIONS_ENABLED", val),
    do:
      put_in(
        config,
        [:wanderer_notifier, :features, :kill_notifications_enabled],
        parse_bool(val)
      )

  defp apply_env(config, "WANDERER_CHARACTER_TRACKING_ENABLED", val),
    do:
      put_in(
        config,
        [:wanderer_notifier, :features, :character_tracking_enabled],
        parse_bool(val)
      )

  defp apply_env(config, "WANDERER_SYSTEM_TRACKING_ENABLED", val),
    do: put_in(config, [:wanderer_notifier, :features, :system_tracking_enabled], parse_bool(val))

  defp apply_env(config, "WANDERER_DISABLE_STATUS_MESSAGES", val),
    do:
      put_in(config, [:wanderer_notifier, :features, :status_messages_disabled], parse_bool(val))

  defp apply_env(config, "WANDERER_FEATURE_TRACK_KSPACE", val),
    do: put_in(config, [:wanderer_notifier, :features, :track_kspace_systems], parse_bool(val))

  defp apply_env(config, "WANDERER_CHARACTER_EXCLUDE_LIST", val),
    do: put_in(config, [:wanderer_notifier, :character_exclude_list], parse_character_list(val))

  defp apply_env(config, "WANDERER_WEBSOCKET_RECONNECT_DELAY", val),
    do: put_in(config, [:wanderer_notifier, :websocket, :reconnect_delay], parse_int(val, 5000))

  defp apply_env(config, "WANDERER_WEBSOCKET_MAX_RECONNECTS", val),
    do: put_in(config, [:wanderer_notifier, :websocket, :max_reconnects], parse_int(val, 20))

  defp apply_env(config, "WANDERER_WEBSOCKET_RECONNECT_WINDOW", val),
    do: put_in(config, [:wanderer_notifier, :websocket, :reconnect_window], parse_int(val, 3600))

  defp apply_env(config, "WANDERER_CACHE_DIR", val),
    do: put_in(config, [:wanderer_notifier, :cache_dir], val || "/app/data/cache")

  defp apply_env(config, "WANDERER_PUBLIC_URL", val),
    do: put_in(config, [:wanderer_notifier, :public_url], val)

  defp apply_env(config, "WANDERER_HOST", val),
    do: put_in(config, [:wanderer_notifier, :host], val || "localhost")

  defp apply_env(config, "WANDERER_SCHEME", val),
    do: put_in(config, [:wanderer_notifier, :scheme], val || "http")

  # Catch-all for any other environment variables
  defp apply_env(config, _, _), do: config

  # Helper functions for parsing values

  # Parse integer with fallback
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  # Parse port number with validation
  defp parse_port(port_str, default) when is_binary(port_str) do
    case Integer.parse(port_str) do
      {port, ""} when port > 0 and port < 65_536 ->
        port

      _ ->
        require Logger
        Logger.warning("Invalid PORT value: '#{port_str}', using default: #{default}")
        default
    end
  end

  defp parse_port(_, default), do: default

  # Parse a comma-separated list of characters
  defp parse_character_list(val) when is_binary(val) do
    val
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp parse_character_list(_), do: []

  # Parse boolean with fallback
  defp parse_bool(val) when is_binary(val) do
    val = String.downcase(val)
    true_values = ["true", "t", "yes", "y", "1", "on"]
    false_values = ["false", "f", "no", "n", "0", "off"]

    cond do
      val in true_values -> true
      val in false_values -> false
      # default to true for any other value
      true -> true
    end
  end

  # default to true for non-string values
  defp parse_bool(_), do: true
end
