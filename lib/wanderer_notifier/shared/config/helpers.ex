# credo:disable-for-this-file Credo.Check.Refactor.ABCSize
# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
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
  Generates configuration accessor functions based on the specified type.

  ## Supported Types

  ### :simple
  Generates simple configuration accessor functions.

      defconfig :simple, [
        :discord_bot_token,
        :map_url,
        :cache_dir
      ]

  ### :with_defaults
  Generates configuration accessors with default values.

      defconfig :with_defaults, [
        {:port, 4000},
        {:timeout, 30_000}
      ]

  ### :features
  Generates boolean feature flag accessors.

      defconfig :features, [
        :notifications_enabled,
        :kill_notifications_enabled
      ]

  ### :env_vars
  Generates environment variable accessors with type conversion.

      defconfig :env_vars, [
        {"PORT", :integer, 4000},
        {"DEBUG", :boolean, false}
      ]

  ### :custom
  Generates configuration accessors with custom transformation functions.

      defconfig :custom, [
        {:character_exclude_list, &Utils.parse_comma_list/1, ""}
      ]

  ### :channels
  Generates channel ID accessors with consistent naming.

      defconfig :channels, [
        :discord_system_kill,
        :discord_character_kill
      ]
  """
  defmacro defconfig(:simple, config_keys) when is_list(config_keys) do
    for key <- config_keys do
      quote do
        def unquote(key)(), do: get(unquote(key))
      end
    end
  end

  defmacro defconfig(:with_defaults, config_tuples) when is_list(config_tuples) do
    for {key, default} <- config_tuples do
      quote do
        def unquote(key)(), do: get(unquote(key), unquote(default))
      end
    end
  end

  defmacro defconfig(:features, feature_keys) when is_list(feature_keys) do
    for key <- feature_keys do
      # Create function name with ? suffix
      func_name = String.to_atom("#{key}?")

      quote do
        def unquote(func_name)(), do: feature_enabled?(unquote(key))
      end
    end
  end

  defmacro defconfig(:env_vars, env_specs) when is_list(env_specs) do
    Enum.map(env_specs, &generate_env_var_function/1)
  end

  defp generate_env_var_function(spec) do
    {env_var, type, default} = parse_env_spec(spec)
    func_name = ("env_" <> String.downcase(env_var)) |> String.to_atom()
    generate_typed_env_function(func_name, env_var, type, default)
  end

  defp parse_env_spec({env_var, type, default}), do: {env_var, type, default}
  defp parse_env_spec(spec), do: raise(ArgumentError, "Invalid env_var spec: #{inspect(spec)}")

  defp generate_typed_env_function(func_name, env_var, :string, :required) do
    quote do
      def unquote(func_name)(), do: fetch_env_string!(unquote(env_var))
    end
  end

  defp generate_typed_env_function(func_name, env_var, :string, default) do
    quote do
      def unquote(func_name)(), do: fetch_env_string(unquote(env_var), unquote(default))
    end
  end

  defp generate_typed_env_function(func_name, env_var, :integer, default) do
    quote do
      def unquote(func_name)(), do: fetch_env_int(unquote(env_var), unquote(default))
    end
  end

  defp generate_typed_env_function(func_name, env_var, :boolean, default) do
    quote do
      def unquote(func_name)(), do: fetch_env_bool(unquote(env_var), unquote(default))
    end
  end

  defmacro defconfig(:custom, config_specs) when is_list(config_specs) do
    for {key, transform_fn, default} <- config_specs do
      quote do
        def unquote(key)() do
          get(unquote(key), unquote(default)) |> unquote(transform_fn).()
        end
      end
    end
  end

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
      nil ->
        raise "Required environment variable '#{key}' is not set. Please set this variable to a valid string value in your environment configuration."

      "" ->
        raise "Required environment variable '#{key}' is set but empty. Please provide a non-empty string value."

      value ->
        value
    end
  end

  def fetch_env_int(key, default) do
    case env_provider().get_env(key) do
      nil ->
        default

      "" ->
        raise "Environment variable '#{key}' is set but empty. Please provide a valid integer value."

      value ->
        case WandererNotifier.Shared.Config.Utils.parse_int(value, nil) do
          nil ->
            raise "Environment variable '#{key}' has invalid integer value '#{value}'. Please provide a valid integer."

          parsed_value ->
            parsed_value
        end
    end
  end

  def fetch_env_bool(key, default) do
    case env_provider().get_env(key) do
      nil ->
        default

      "" ->
        raise "Environment variable '#{key}' is set but empty. Please provide a valid boolean value (true/false, 1/0, yes/no, on/off)."

      value ->
        # Try to parse the boolean - use false as default then validate the string separately
        # First check if it's a valid boolean string
        normalized = value |> String.trim() |> String.downcase()

        cond do
          normalized in ["true", "1", "yes", "on"] ->
            true

          normalized in ["false", "0", "no", "off"] ->
            false

          true ->
            raise "Environment variable '#{key}' has invalid boolean value '#{value}'. Please use true/false, 1/0, yes/no, or on/off."
        end
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
        case Map.get(@feature_schema, feature_key) do
          {:boolean, opts} -> resolve_boolean_feature(feature_key, opts)
          _ -> false
        end
      end

      defp resolve_boolean_feature(feature_key, opts) do
        default = Keyword.get(opts, :default, false)

        case Keyword.get(opts, :env) do
          nil ->
            get(feature_key, default)

          env_var ->
            case fetch_env_bool(env_var, nil) do
              nil -> get(feature_key, default)
              bool_value -> bool_value
            end
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
      @validation_rules unquote(validations)

      def validate_configuration! do
        errors =
          Enum.reduce(@validation_rules, [], fn {key, validation, message}, acc ->
            case validate_config_value(key, validation) do
              :ok -> acc
              {:error, _} -> [message | acc]
            end
          end)

        case errors do
          [] ->
            :ok

          error_list ->
            formatted_errors = error_list |> Enum.reverse() |> Enum.join("\n  - ")
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
