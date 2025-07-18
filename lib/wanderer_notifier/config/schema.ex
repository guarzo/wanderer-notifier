defmodule WandererNotifier.Config.Schema do
  @moduledoc """
  Defines the configuration schema and validation rules for WandererNotifier.

  This module provides a comprehensive schema for all configuration values
  including validation rules, type constraints, and environment-specific
  requirements.
  """

  @type validation_result :: :ok | {:error, [validation_error()]}
  @type validation_error :: %{
          field: atom(),
          value: any(),
          error: atom() | String.t(),
          message: String.t()
        }

  @type field_schema :: %{
          type: :string | :integer | :boolean | :url | :list,
          required: boolean(),
          default: any(),
          validator: (any() -> boolean()) | nil,
          env_var: String.t(),
          description: String.t()
        }

  @doc """
  Returns the complete configuration schema with validation rules.
  """
  @spec schema :: %{atom() => field_schema()}
  def schema do
    Map.merge(
      discord_fields(),
      Map.merge(
        map_fields(),
        Map.merge(
          service_url_fields(),
          Map.merge(
            license_fields(),
            Map.merge(feature_flag_fields(), application_fields())
          )
        )
      )
    )
  end

  defp discord_fields do
    %{
      discord_bot_token:
        field_config(
          :string,
          true,
          nil,
          &valid_bot_token?/1,
          "DISCORD_BOT_TOKEN",
          "Discord bot token for authentication"
        ),
      discord_application_id:
        field_config(
          :string,
          true,
          nil,
          &valid_snowflake?/1,
          "DISCORD_APPLICATION_ID",
          "Discord application ID for slash commands"
        ),
      discord_channel_id:
        field_config(
          :string,
          false,
          nil,
          &valid_snowflake_or_nil?/1,
          "DISCORD_CHANNEL_ID",
          "Default Discord channel ID for notifications"
        ),
      discord_character_channel_id:
        field_config(
          :string,
          false,
          nil,
          &valid_snowflake_or_nil?/1,
          "DISCORD_CHARACTER_CHANNEL_ID",
          "Discord channel ID for character notifications"
        ),
      discord_system_channel_id:
        field_config(
          :string,
          false,
          nil,
          &valid_snowflake_or_nil?/1,
          "DISCORD_SYSTEM_CHANNEL_ID",
          "Discord channel ID for system notifications"
        )
    }
  end

  defp map_fields do
    %{
      map_url:
        field_config(
          :url,
          true,
          nil,
          &valid_url?/1,
          "MAP_URL",
          "Wanderer map API base URL"
        ),
      map_name:
        field_config(
          :string,
          true,
          nil,
          &valid_map_name?/1,
          "MAP_NAME",
          "Map name for API access"
        ),
      map_api_key:
        field_config(
          :string,
          true,
          nil,
          &valid_api_key?/1,
          "MAP_API_KEY",
          "API key for map service authentication"
        )
    }
  end

  defp service_url_fields do
    %{
      websocket_url:
        field_config(
          :url,
          false,
          "ws://host.docker.internal:4004",
          &valid_websocket_url?/1,
          "WEBSOCKET_URL",
          "WebSocket URL for killmail service"
        ),
      wanderer_kills_url:
        field_config(
          :url,
          false,
          "http://host.docker.internal:4004",
          &valid_url?/1,
          "WANDERER_KILLS_URL",
          "WandererKills API base URL"
        ),
      license_manager_url:
        field_config(
          :url,
          false,
          "https://license.wanderer.nz",
          &valid_url?/1,
          "LICENSE_MANAGER_URL",
          "License manager service URL"
        )
    }
  end

  defp license_fields do
    %{
      license_key:
        field_config(
          :string,
          true,
          nil,
          &valid_license_key?/1,
          "LICENSE_KEY",
          "License key for premium features"
        )
    }
  end

  defp feature_flag_fields do
    %{
      notifications_enabled:
        boolean_field("NOTIFICATIONS_ENABLED", true, "Master toggle for all notifications"),
      kill_notifications_enabled:
        boolean_field("KILL_NOTIFICATIONS_ENABLED", true, "Enable/disable kill notifications"),
      system_notifications_enabled:
        boolean_field("SYSTEM_NOTIFICATIONS_ENABLED", true, "Enable/disable system notifications"),
      character_notifications_enabled:
        boolean_field(
          "CHARACTER_NOTIFICATIONS_ENABLED",
          true,
          "Enable/disable character notifications"
        ),
      enable_status_messages:
        boolean_field("ENABLE_STATUS_MESSAGES", false, "Enable/disable startup status messages"),
      track_kspace_enabled:
        boolean_field("TRACK_KSPACE_ENABLED", true, "Enable/disable K-Space system tracking"),
      priority_systems_only:
        boolean_field(
          "PRIORITY_SYSTEMS_ONLY",
          false,
          "Only send notifications for priority systems"
        )
    }
  end

  defp application_fields do
    %{
      port:
        field_config(
          :integer,
          false,
          4000,
          &valid_port?/1,
          "PORT",
          "HTTP server port"
        ),
      host:
        field_config(
          :string,
          false,
          "localhost",
          &valid_host?/1,
          "HOST",
          "HTTP server host"
        ),
      scheme:
        field_config(
          :string,
          false,
          "http",
          &valid_scheme?/1,
          "SCHEME",
          "HTTP scheme (http or https)"
        ),
      public_url:
        field_config(
          :url,
          false,
          nil,
          &valid_url_or_nil?/1,
          "PUBLIC_URL",
          "Public URL for external access"
        )
    }
  end

  defp field_config(type, required, default, validator, env_var, description) do
    %{
      type: type,
      required: required,
      default: default,
      validator: validator,
      env_var: env_var,
      description: description
    }
  end

  defp boolean_field(env_var, default, description) do
    field_config(:boolean, false, default, nil, env_var, description)
  end

  @doc """
  Returns a list of all required configuration fields.
  """
  @spec required_fields :: [atom()]
  def required_fields do
    schema()
    |> Enum.filter(fn {_key, config} -> config.required end)
    |> Enum.map(fn {key, _config} -> key end)
  end

  @doc """
  Returns configuration fields that are environment-specific.
  """
  @spec environment_fields(atom()) :: [atom()]
  def environment_fields(:dev), do: []
  def environment_fields(:test), do: []
  def environment_fields(:prod), do: required_fields()

  @doc """
  Returns the environment variable name for a configuration field.
  """
  @spec env_var_for_field(atom()) :: String.t() | nil
  def env_var_for_field(field) do
    case Map.get(schema(), field) do
      %{env_var: env_var} -> env_var
      _ -> nil
    end
  end

  @doc """
  Returns the default value for a configuration field.
  """
  @spec default_for_field(atom()) :: any()
  def default_for_field(field) do
    case Map.get(schema(), field) do
      %{default: default} -> default
      _ -> nil
    end
  end

  # Validation functions

  defp valid_bot_token?(token) when is_binary(token) do
    String.match?(token, ~r/^[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}$/)
  end

  defp valid_bot_token?(_), do: false

  defp valid_snowflake?(id) when is_binary(id) do
    String.match?(id, ~r/^\d{17,20}$/)
  end

  defp valid_snowflake?(_), do: false

  defp valid_snowflake_or_nil?(nil), do: true
  defp valid_snowflake_or_nil?(id), do: valid_snowflake?(id)

  defp valid_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme != nil and uri.host != nil
  end

  defp valid_url?(_), do: false

  defp valid_url_or_nil?(nil), do: true
  defp valid_url_or_nil?(url), do: valid_url?(url)

  defp valid_websocket_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme in ["ws", "wss"] and uri.host != nil
  end

  defp valid_websocket_url?(_), do: false

  defp valid_map_name?(name) when is_binary(name) do
    String.length(name) > 0 and String.length(name) <= 100
  end

  defp valid_map_name?(_), do: false

  defp valid_api_key?(key) when is_binary(key) do
    String.length(key) >= 8
  end

  defp valid_api_key?(_), do: false

  defp valid_license_key?(key) when is_binary(key) do
    String.length(key) >= 10
  end

  defp valid_license_key?(_), do: false

  defp valid_port?(port) when is_integer(port) do
    port > 0 and port <= 65_535
  end

  defp valid_port?(_), do: false

  defp valid_host?(host) when is_binary(host) do
    String.length(host) > 0
  end

  defp valid_host?(_), do: false

  defp valid_scheme?(scheme) when is_binary(scheme) do
    scheme in ["http", "https"]
  end

  defp valid_scheme?(_), do: false
end
