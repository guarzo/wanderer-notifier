defmodule WandererNotifier.Shared.Config.Validator do
  @moduledoc """
  Validates configuration against the defined schema.

  Provides comprehensive validation of all configuration values including
  type checking, required field validation, and custom business logic validation.
  """

  alias WandererNotifier.Shared.Config.Schema
  alias WandererNotifier.Shared.Utils.ValidationUtils

  require Logger

  @type validation_result :: :ok | {:error, [validation_error()]}
  @type validation_error :: %{
          field: atom(),
          value: any(),
          error: atom() | String.t(),
          message: String.t()
        }

  @doc """
  Validates the complete configuration against the schema.

  Returns `:ok` if all validation passes, or `{:error, errors}` with
  a list of validation errors.
  """
  @spec validate_config(map(), atom()) :: validation_result()
  def validate_config(config, environment \\ :prod) do
    schema = Schema.schema()
    errors = []

    errors =
      errors
      |> validate_required_fields(config, environment)
      |> validate_field_types(config, schema)
      |> validate_field_values(config, schema)
      |> validate_environment_specific(config, environment)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Validates a single configuration field.
  """
  @spec validate_field(atom(), any()) :: validation_result()
  def validate_field(field, value) do
    schema = Schema.schema()

    case Map.get(schema, field) do
      nil ->
        {:error,
         [
           %{
             field: field,
             value: value,
             error: :unknown_field,
             message: "Unknown configuration field: #{field}"
           }
         ]}

      field_schema ->
        errors = validate_single_field(field, value, field_schema)

        case errors do
          [] -> :ok
          errors -> {:error, errors}
        end
    end
  end

  @doc """
  Validates configuration from environment variables.
  """
  @spec validate_from_env(atom()) :: validation_result()
  def validate_from_env(environment \\ :prod) do
    config = build_config_from_env()
    validate_config(config, environment)
  end

  @doc """
  Returns detailed validation error messages suitable for logging or display.
  """
  @spec format_errors([validation_error()]) :: String.t()
  def format_errors(errors) do
    errors
    |> Enum.map(fn error ->
      env_var = Schema.env_var_for_field(error.field)
      env_info = if env_var, do: " (#{env_var})", else: ""
      "  • #{error.field}#{env_info}: #{error.message}"
    end)
    |> Enum.join("\n")
  end

  @doc """
  Logs validation errors with appropriate log levels.
  """
  @spec log_validation_errors([validation_error()]) :: :ok
  def log_validation_errors(errors) do
    critical_errors = Enum.filter(errors, &critical_error?/1)
    warning_errors = Enum.reject(errors, &critical_error?/1)

    if not Enum.empty?(critical_errors) do
      Logger.error("""
      Critical configuration errors found:
      #{format_errors(critical_errors)}
      """)
    end

    if not Enum.empty?(warning_errors) do
      Logger.warning("""
      Configuration warnings:
      #{format_errors(warning_errors)}
      """)
    end

    :ok
  end

  @doc """
  Returns a summary of the validation results.
  """
  @spec validation_summary([validation_error()]) :: %{
          total_errors: non_neg_integer(),
          critical_errors: non_neg_integer(),
          warnings: non_neg_integer(),
          by_category: map()
        }
  def validation_summary(errors) do
    critical_errors = Enum.filter(errors, &critical_error?/1)
    warnings = Enum.reject(errors, &critical_error?/1)

    by_category =
      errors
      |> Enum.group_by(&categorize_error/1)
      |> Map.new(fn {category, errs} -> {category, length(errs)} end)

    %{
      total_errors: length(errors),
      critical_errors: length(critical_errors),
      warnings: length(warnings),
      by_category: by_category
    }
  end

  # Private functions

  defp validate_required_fields(errors, config, environment) do
    required_fields = Schema.environment_fields(environment)

    required_fields
    |> Enum.reduce(errors, fn field, acc ->
      case Map.get(config, field) do
        nil ->
          [
            %{
              field: field,
              value: nil,
              error: :required,
              message: "Required field is missing"
            }
            | acc
          ]

        "" ->
          [
            %{
              field: field,
              value: "",
              error: :required,
              message: "Required field cannot be empty"
            }
            | acc
          ]

        _ ->
          acc
      end
    end)
  end

  defp validate_field_types(errors, config, schema) do
    config
    |> Enum.reduce(errors, fn {field, value}, acc ->
      validate_single_field_type(acc, field, value, schema)
    end)
  end

  defp validate_single_field_type(acc, field, value, schema) do
    case Map.get(schema, field) do
      nil -> acc
      %{type: expected_type} -> check_field_type(acc, field, value, expected_type)
    end
  end

  defp check_field_type(acc, field, value, expected_type) do
    if valid_type?(value, expected_type) do
      acc
    else
      [create_type_error(field, value, expected_type) | acc]
    end
  end

  defp create_type_error(field, value, expected_type) do
    %{
      field: field,
      value: value,
      error: :invalid_type,
      message: "Expected #{expected_type}, got #{type_name(value)}"
    }
  end

  defp validate_field_values(errors, config, schema) do
    config
    |> Enum.reduce(errors, fn {field, value}, acc ->
      validate_field_value(acc, field, value, schema)
    end)
  end

  defp validate_field_value(acc, field, value, schema) do
    case Map.get(schema, field) do
      nil ->
        acc

      field_schema ->
        # Prepend errors for O(1) performance
        case validate_single_field(field, value, field_schema) do
          [] -> acc
          field_errors -> prepend_errors(field_errors, acc)
        end
    end
  end

  defp prepend_errors(field_errors, acc) do
    Enum.reduce(field_errors, acc, fn error, acc2 -> [error | acc2] end)
  end

  defp validate_single_field(field, value, %{validator: validator}) when is_function(validator) do
    if value == nil or validator.(value) do
      []
    else
      [
        %{
          field: field,
          value: value,
          error: :invalid_value,
          message: "Value failed validation"
        }
      ]
    end
  end

  defp validate_single_field(_field, _value, %{validator: nil}), do: []

  defp validate_environment_specific(errors, config, :prod) do
    # Additional production-specific validations
    errors
    |> validate_discord_configuration(config)
    |> validate_map_configuration(config)
    |> validate_service_urls(config)
  end

  defp validate_environment_specific(errors, _config, _env), do: errors

  defp validate_discord_configuration(errors, config) do
    # Ensure at least one Discord channel is configured if notifications are enabled
    notifications_enabled = Map.get(config, :notifications_enabled, true)

    if notifications_enabled do
      has_channels =
        [:discord_channel_id, :discord_character_channel_id, :discord_system_channel_id]
        |> Enum.any?(fn field -> Map.get(config, field) != nil end)

      if has_channels do
        errors
      else
        [
          %{
            field: :discord_channel_id,
            value: nil,
            error: :configuration_incomplete,
            message:
              "At least one Discord channel must be configured when notifications are enabled"
          }
          | errors
        ]
      end
    else
      errors
    end
  end

  defp validate_map_configuration(errors, config) do
    # Validate that map configuration is complete
    required_map_fields = [:map_url, :map_name, :map_api_key]

    missing_fields =
      required_map_fields
      |> Enum.filter(fn field -> Map.get(config, field) in [nil, ""] end)

    missing_count = length(missing_fields)
    total_count = length(required_map_fields)

    if missing_count > 0 and missing_count < total_count do
      # Some but not all map fields are configured - this is likely an error
      missing_fields
      |> Enum.reduce(errors, fn field, acc ->
        [
          %{
            field: field,
            value: Map.get(config, field),
            error: :configuration_incomplete,
            message: "Map configuration is incomplete - all map fields must be provided together"
          }
          | acc
        ]
      end)
    else
      errors
    end
  end

  defp validate_service_urls(errors, config) do
    # Validate that service URLs are accessible (basic format validation)
    url_fields = [:websocket_url, :wanderer_kills_url, :license_manager_url, :map_url]

    url_fields
    |> Enum.reduce(errors, fn field, acc ->
      validate_single_url(acc, field, config)
    end)
  end

  defp validate_single_url(acc, field, config) do
    case Map.get(config, field) do
      nil -> acc
      url when is_binary(url) -> check_url_format(acc, field, url)
      _ -> acc
    end
  end

  defp check_url_format(acc, field, url) do
    if reachable_url_format?(url) do
      acc
    else
      [create_url_error(field, url) | acc]
    end
  end

  defp create_url_error(field, url) do
    %{
      field: field,
      value: url,
      error: :unreachable_url,
      message: "URL format suggests it may not be reachable in production"
    }
  end

  defp build_config_from_env do
    Schema.schema()
    |> Enum.reduce(%{}, fn {field, field_config}, acc ->
      process_env_field(acc, field, field_config)
    end)
  end

  defp process_env_field(acc, field, %{env_var: env_var, type: type, default: default}) do
    case System.get_env(env_var) do
      nil -> apply_default_value(acc, field, default)
      value -> apply_parsed_value(acc, field, value, type)
    end
  end

  defp apply_default_value(acc, _field, nil), do: acc
  defp apply_default_value(acc, field, default), do: Map.put(acc, field, default)

  defp apply_parsed_value(acc, field, value, type) do
    parsed_value = parse_env_value(value, type)
    Map.put(acc, field, parsed_value)
  end

  defp parse_env_value(value, :boolean) do
    value in ["true", "1", "yes", "on"]
  end

  defp parse_env_value(value, :integer) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      {_int, remainder} when remainder != "" ->
        require Logger

        Logger.warning(
          "Environment variable integer parsing found non-empty remainder: #{inspect(remainder)} in value: #{inspect(value)}"
        )

        value

      _ ->
        value
    end
  end

  defp parse_env_value(value, _type), do: value

  # URL is a special case for config validation
  defp valid_type?(value, :url), do: is_binary(value)
  defp valid_type?(value, type), do: ValidationUtils.valid_type?(value, type)

  defp type_name(value), do: ValidationUtils.type_name(value)

  defp critical_error?(%{error: :required}), do: true
  defp critical_error?(%{error: :invalid_type}), do: true
  defp critical_error?(_), do: false

  defp categorize_error(%{error: :required}), do: :required_fields
  defp categorize_error(%{error: :invalid_type}), do: :type_errors
  defp categorize_error(%{error: :invalid_value}), do: :validation_errors
  defp categorize_error(%{error: :configuration_incomplete}), do: :configuration_errors
  defp categorize_error(%{error: :unreachable_url}), do: :connectivity_warnings
  defp categorize_error(_), do: :other

  # Validates URL format for production environments.
  # This function flags localhost, 127.0.0.1, and host.docker.internal URLs as unreachable
  # because they are typically not accessible in production environments.
  # In development, these URLs are valid and expected, but in production they indicate
  # potential misconfiguration where internal/development URLs are being used.
  defp reachable_url_format?(url) do
    # Basic check for localhost/docker internal URLs that might not be reachable
    not String.contains?(url, ["localhost", "127.0.0.1", "host.docker.internal"])
  end
end
