defmodule WandererNotifier.Config.Debug do
  @moduledoc """
  Configuration module for debug and logging settings.

  This module centralizes all debug-related configuration access,
  providing a standardized interface for retrieving debug settings
  and controlling debug functionality.
  """

  @doc """
  Returns the complete debug configuration map.
  """
  @spec config() :: map()
  def config do
    %{
      logging_enabled: debug_logging_enabled?(),
      map_settings: map_debug_settings()
    }
  end

  @doc """
  Determines if debug logging is enabled.
  Default: false

  This checks the WANDERER_DEBUG_LOGGING environment variable.
  """
  @spec debug_logging_enabled?() :: boolean()
  def debug_logging_enabled? do
    get_env(:debug_logging_enabled, false)
  end

  @doc """
  Toggles debug logging on or off.
  Returns the new state.
  """
  @spec toggle_debug_logging() :: boolean()
  def toggle_debug_logging do
    new_state = !debug_logging_enabled?()
    set_debug_logging(new_state)
  end

  @doc """
  Sets debug logging to a specific state (on or off).
  Returns the new state.
  """
  @spec set_debug_logging(boolean()) :: boolean()
  def set_debug_logging(state) when is_boolean(state) do
    Application.put_env(:wanderer_notifier, :debug_logging_enabled, state)
    state
  end

  @doc """
  Returns the map debug settings.
  """
  @spec map_debug_settings() :: map()
  def map_debug_settings do
    %{
      map_url_with_name: get_env(:map_url_with_name, nil),
      map_url: get_env(:map_url, nil),
      map_name: get_env(:map_name, nil),
      map_token: get_env(:map_token, nil)
    }
  end

  @doc """
  Validates that all debug configuration values are valid.

  Returns :ok if the configuration is valid, or {:error, reason} if not.
  """
  @spec validate() :: :ok | {:error, String.t()}
  def validate do
    # Debug settings don't require validation
    :ok
  end

  # Private helper function to get configuration values
  defp get_env(key, default) do
    # First check configuration
    config_value = Application.get_env(:wanderer_notifier, key)

    if is_nil(config_value) do
      # If not in application config, try environment variables
      env_value = get_from_env_vars(key)
      format_env_value(env_value, default)
    else
      config_value
    end
  end

  # Checks both new and legacy environment variables
  defp get_from_env_vars(key) do
    # Try the new prefixed environment variable first
    env_key = key_to_env_map(key)
    env_value = get_env_value(env_key)

    # If no value from preferred env var, try legacy env var
    if is_nil(env_value) do
      legacy_key = legacy_key_to_env_map(key)
      get_env_value(legacy_key)
    else
      env_value
    end
  end

  # Gets an environment variable value safely
  defp get_env_value(nil), do: nil
  defp get_env_value(env_var), do: System.get_env(env_var)

  # Formats environment variable values
  defp format_env_value("true", _default), do: true
  defp format_env_value("false", _default), do: false
  defp format_env_value(nil, default), do: default
  defp format_env_value(value, _default), do: value

  # Maps configuration keys to environment variable names (new prefixed vars)
  defp key_to_env_map(:debug_logging_enabled), do: "WANDERER_DEBUG_LOGGING"
  defp key_to_env_map(:map_url_with_name), do: "WANDERER_MAP_URL_WITH_NAME"
  defp key_to_env_map(:map_url), do: "WANDERER_MAP_URL"
  defp key_to_env_map(:map_name), do: "WANDERER_MAP_NAME"
  defp key_to_env_map(:map_token), do: "WANDERER_MAP_TOKEN"
  defp key_to_env_map(_), do: nil

  # Maps configuration keys to legacy environment variable names
  defp legacy_key_to_env_map(:map_url_with_name), do: "MAP_URL_WITH_NAME"
  defp legacy_key_to_env_map(:map_url), do: "MAP_URL"
  defp legacy_key_to_env_map(:map_name), do: "MAP_NAME"
  defp legacy_key_to_env_map(:map_token), do: "MAP_TOKEN"
  defp legacy_key_to_env_map(_), do: nil
end
