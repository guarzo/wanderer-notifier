defmodule WandererNotifier.Shared.Config.Helpers do
  @moduledoc """
  Configuration helpers and macros to reduce code duplication and provide
  a unified interface for configuration access across the application.

  This module provides:
  - Macro-based config accessor generation
  - Environment variable schema validation
  - Feature flag management
  - Type-safe configuration access
  - Centralized default values
  """

  @doc """
  Generates simple configuration accessor functions.

  ## Usage

      defconfig :simple, [
        :discord_bot_token,
        :map_url,
        :cache_dir
      ]
      
      # Generates:
      # def discord_bot_token, do: get(:discord_bot_token)
      # def map_url, do: get(:map_url)  
      # def cache_dir, do: get(:cache_dir)
  """
  defmacro defconfig(:simple, config_keys) when is_list(config_keys) do
    for key <- config_keys do
      quote do
        def unquote(key)(), do: get(unquote(key))
      end
    end
  end

  @doc """
  Generates configuration accessors with default values.

  ## Usage

      defconfig :with_defaults, [
        {:port, 4000},
        {:timeout, 30_000},
        {:max_retries, 3}
      ]
      
      # Generates:
      # def port, do: get(:port, 4000)
      # def timeout, do: get(:timeout, 30_000)
      # def max_retries, do: get(:max_retries, 3)
  """
  defmacro defconfig(:with_defaults, config_tuples) when is_list(config_tuples) do
    for {key, default} <- config_tuples do
      quote do
        def unquote(key)(), do: get(unquote(key), unquote(default))
      end
    end
  end

  @doc """
  Generates boolean feature flag accessors.

  ## Usage

      defconfig :features, [
        :notifications_enabled,
        :kill_notifications_enabled,
        :system_notifications_enabled
      ]
      
      # Generates:
      # def notifications_enabled?, do: feature_enabled?(:notifications_enabled)
      # def kill_notifications_enabled?, do: feature_enabled?(:kill_notifications_enabled)  
      # def system_notifications_enabled?, do: feature_enabled?(:system_notifications_enabled)
  """
  defmacro defconfig(:features, feature_keys) when is_list(feature_keys) do
    for key <- feature_keys do
      # Create function name with ? suffix
      func_name = String.to_atom("#{key}?")

      quote do
        def unquote(func_name)(), do: feature_enabled?(unquote(key))
      end
    end
  end

  @doc """
  Generates environment variable accessors with type conversion.

  ## Usage

      defconfig :env_vars, [
        {"PORT", :integer, 4000},
        {"DEBUG", :boolean, false},
        {"API_KEY", :string, :required},
        {"TIMEOUT", :integer, 30_000}
      ]
      
      # Generates:
      # def port, do: fetch_env_int("PORT", 4000)
      # def debug, do: fetch_env_bool("DEBUG", false)
      # def api_key, do: fetch_env_string("API_KEY") # required, no default
      # def timeout, do: fetch_env_int("TIMEOUT", 30_000)
  """
  defmacro defconfig(:env_vars, env_specs) when is_list(env_specs) do
    for spec <- env_specs do
      {env_var, type, default} =
        case spec do
          {env_var, type, default} -> {env_var, type, default}
          _ -> raise ArgumentError, "Invalid env_var spec: #{inspect(spec)}"
        end

      func_name = env_var |> String.downcase() |> String.to_atom()

      case {type, default} do
        {:string, :required} ->
          quote do
            def unquote(func_name)(), do: fetch_env_string!(unquote(env_var))
          end

        {:string, default} ->
          quote do
            def unquote(func_name)(), do: fetch_env_string(unquote(env_var), unquote(default))
          end

        {:integer, default} ->
          quote do
            def unquote(func_name)(), do: fetch_env_int(unquote(env_var), unquote(default))
          end

        {:boolean, default} ->
          quote do
            def unquote(func_name)(), do: fetch_env_bool(unquote(env_var), unquote(default))
          end
      end
    end
  end

  @doc """
  Generates configuration accessors with custom transformation functions.

  ## Usage

      defconfig :custom, [
        {:character_exclude_list, &Utils.parse_comma_list/1, ""},
        {:ttl_seconds, &Utils.parse_duration/1, "1h"}
      ]
      
      # Generates:
      # def character_exclude_list, do: get(:character_exclude_list, "") |> Utils.parse_comma_list()
      # def ttl_seconds, do: get(:ttl_seconds, "1h") |> Utils.parse_duration()
  """
  defmacro defconfig(:custom, config_specs) when is_list(config_specs) do
    for {key, transform_fn, default} <- config_specs do
      quote do
        def unquote(key)() do
          get(unquote(key), unquote(default)) |> unquote(transform_fn).()
        end
      end
    end
  end

  @doc """
  Generates channel ID accessors with consistent naming.

  ## Usage

      defconfig :channels, [
        :discord_system_kill,
        :discord_character_kill,
        :discord_system,
        :discord_character
      ]
      
      # Generates:
      # def discord_system_kill_channel_id, do: get(:discord_system_kill_channel_id)
      # def discord_character_kill_channel_id, do: get(:discord_character_kill_channel_id)
      # etc.
  """
  defmacro defconfig(:channels, channel_keys) when is_list(channel_keys) do
    for key <- channel_keys do
      func_name = String.to_atom("#{key}_channel_id")
      config_key = String.to_atom("#{key}_channel_id")

      quote do
        def unquote(func_name)(), do: get(unquote(config_key))
      end
    end
  end

  # Helper functions for the generated code

  @doc """
  Environment variable fetching with type conversion
  """
  def fetch_env_string(key, default \\ nil) do
    env_provider().get_env(key, default)
  end

  def fetch_env_string!(key) do
    case env_provider().get_env(key) do
      nil -> raise "Required environment variable #{key} is not set"
      value -> value
    end
  end

  def fetch_env_int(key, default) do
    case env_provider().get_env(key) do
      nil -> default
      value -> WandererNotifier.Shared.Config.Utils.parse_int(value, default)
    end
  end

  def fetch_env_bool(key, default) do
    case env_provider().get_env(key) do
      nil -> default
      value -> WandererNotifier.Shared.Config.Utils.parse_bool(value, default)
    end
  end

  # Private helper functions

  defp env_provider do
    Application.get_env(
      :wanderer_notifier,
      :env_provider,
      WandererNotifier.Shared.Config.SystemEnvProvider
    )
  end

  # Make common functions available to generated code
  defdelegate get(key), to: WandererNotifier.Shared.Config
  defdelegate get(key, default), to: WandererNotifier.Shared.Config
  defdelegate feature_enabled?(flag), to: WandererNotifier.Shared.Config

  @doc """
  Schema-based feature flag definition with automatic accessor generation.

  ## Usage
      
      deffeatures %{
        notifications_enabled: {:boolean, default: true},
        kill_notifications_enabled: {:boolean, default: true, env: "KILL_NOTIFICATIONS_ENABLED"},
        debug_mode: {:boolean, default: false, env: "DEBUG_MODE"}
      }
      
      # Generates type-safe accessors with environment variable override support
  """
  defmacro deffeatures(feature_schema) do
    features =
      for {feature_key, _spec} <- feature_schema do
        func_name = String.to_atom("#{feature_key}?")

        quote do
          def unquote(func_name)() do
            get_feature_value(unquote(feature_key))
          end
        end
      end

    quote do
      @feature_schema unquote(feature_schema)

      def feature_schema, do: @feature_schema

      # Generate individual feature accessors
      unquote(features)

      defp get_feature_value(feature_key) do
        spec = Map.get(@feature_schema, feature_key)

        case spec do
          {:boolean, opts} ->
            # Check environment variable override first
            case Keyword.get(opts, :env) do
              nil ->
                # Use app config or default
                default = Keyword.get(opts, :default, false)
                get(feature_key, default)

              env_var ->
                # Check env var first, fall back to config
                case fetch_env_bool(env_var, nil) do
                  nil ->
                    default = Keyword.get(opts, :default, false)
                    get(feature_key, default)

                  value ->
                    value
                end
            end

          _ ->
            false
        end
      end
    end
  end

  @doc """
  Centralized configuration validation with helpful error messages.

  ## Usage
      
      validate_config! [
        {:discord_bot_token, :required, "Discord bot token is required for notifications"},
        {:port, :positive_integer, "Port must be a positive integer"},
        {:map_url, :url, "Map URL must be a valid HTTP/HTTPS URL"}
      ]
  """
  defmacro validate_config!(validations) when is_list(validations) do
    quote do
      def validate_configuration! do
        errors = []

        errors =
          unquote(
            for {key, validation, message} <- validations do
              quote do
                case validate_config_value(unquote(key), unquote(validation)) do
                  :ok -> errors
                  {:error, _} -> [unquote(message) | errors]
                end
              end
            end
          )

        case errors do
          [] ->
            :ok

          error_list ->
            formatted_errors = Enum.join(Enum.reverse(error_list), "\n  - ")
            raise "Configuration validation failed:\n  - #{formatted_errors}"
        end
      end

      defp validate_config_value(key, :required) do
        case get(key) do
          nil -> {:error, :required}
          "" -> {:error, :required}
          _ -> :ok
        end
      end

      defp validate_config_value(key, :positive_integer) do
        case get(key) do
          value when is_integer(value) and value > 0 -> :ok
          _ -> {:error, :invalid_positive_integer}
        end
      end

      defp validate_config_value(key, :url) do
        case get(key) do
          url when is_binary(url) ->
            case URI.parse(url) do
              %URI{scheme: scheme} when scheme in ["http", "https"] -> :ok
              _ -> {:error, :invalid_url}
            end

          _ ->
            {:error, :invalid_url}
        end
      end
    end
  end
end
