defmodule WandererNotifier.Domains.License.LicenseValidator do
  @moduledoc """
  Pure validation functions for license management.

  This module contains stateless validation logic extracted from LicenseService.
  All functions are pure and do not depend on GenServer state.
  """

  require Logger

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Shared.Utils.StringUtils

  # ══════════════════════════════════════════════════════════════════════════════
  # Response Validation
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Validates that the result from license validation has the expected structure.

  ## Parameters
  - `result`: The result map to validate.

  ## Returns
  - `{:ok, map}` if the result is a map with a :valid key.
  - `{:error, {:unexpected, value}}` if the result is invalid.
  """
  @spec valid_result?(any()) :: {:ok, map()} | {:error, any()}
  def valid_result?(result) do
    case result do
      map when is_map(map) and is_map_key(map, :valid) -> {:ok, map}
      other -> {:error, {:unexpected, other}}
    end
  end

  @doc """
  Processes a successful validation response.

  ## Parameters
  - `decoded`: The decoded response map.

  ## Returns
  - `{:ok, decoded}` if the response is a valid map.
  - `{:error, :invalid_response}` if the response format is unexpected.
  """
  @spec process_successful_validation(any()) :: {:ok, map()} | {:error, :invalid_response}
  def process_successful_validation(decoded) when is_map(decoded) do
    {:ok, decoded}
  end

  def process_successful_validation(decoded) do
    Logger.error("Unexpected license validation response format",
      decoded: decoded,
      type: typeof(decoded),
      category: :api
    )

    {:error, :invalid_response}
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Feature Checking
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Checks if a specific feature is enabled based on license state.

  ## Parameters
  - `feature`: The feature to check (atom or string).
  - `state`: The license state map.

  ## Returns
  - `true` if the feature is enabled.
  - `false` if the feature is disabled or the license is invalid.
  """
  @spec check_feature_enabled(atom() | String.t(), map()) :: boolean()
  def check_feature_enabled(feature, state) do
    case state do
      %{valid: true, details: details}
      when is_map(details) and is_map_key(details, "features") ->
        check_features_list(feature, details["features"])

      _ ->
        Logger.debug("Feature check: #{feature} - disabled (invalid license)", category: :config)
        false
    end
  end

  @doc """
  Checks if a feature is in the features list.

  ## Parameters
  - `feature`: The feature to check (atom or string).
  - `features`: The list of enabled features.

  ## Returns
  - `true` if the feature is in the list.
  - `false` otherwise.
  """
  @spec check_features_list(atom() | String.t(), any()) :: boolean()
  def check_features_list(feature, features) when is_list(features) do
    enabled = Enum.member?(features, to_string(feature))

    Logger.debug(
      "Feature check: #{feature} - #{if enabled, do: "enabled", else: "disabled"}",
      category: :config
    )

    enabled
  end

  def check_features_list(feature, _features) do
    Logger.debug("Feature check: #{feature} - disabled (features not a list)",
      category: :config
    )

    false
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Configuration Validation
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Validates the API token from Config.api_token().
  The token should be a non-empty string.

  ## Returns
  - `true` if the token is valid.
  - `false` if the token is invalid.
  """
  @spec validate_api_token() :: boolean()
  def validate_api_token do
    token = Config.api_token()

    Logger.info(
      "License validation - API token check (redacted): #{if token, do: "[REDACTED]", else: "nil"}",
      category: :config
    )

    Logger.info("License validation - environment: #{Config.environment()}",
      category: :config
    )

    if StringUtils.nil_or_empty?(token) do
      Logger.warning("License validation warning: Invalid API token", category: :config)
      false
    else
      true
    end
  end

  @doc """
  Checks if the license key and bot token are both valid.

  ## Returns
  - `true` if both are valid.
  - `false` otherwise.
  """
  @spec license_and_bot_valid?() :: boolean()
  def license_and_bot_valid? do
    bot_token_assigned?() && license_key_present?()
  end

  @doc """
  Determines if the application should use development mode.
  Returns true in dev/test environments when license key or API token is missing.

  ## Returns
  - `true` if development mode should be used.
  - `false` otherwise.
  """
  @spec should_use_dev_mode?() :: boolean()
  def should_use_dev_mode? do
    env = Config.environment()
    env in [:dev, :test] && (!license_key_present?() || !validate_notifier_api_token?())
  end

  @doc """
  Checks if a Discord bot token is assigned.

  ## Returns
  - `true` if a bot token is present.
  - `false` otherwise.
  """
  @spec bot_token_assigned?() :: boolean()
  def bot_token_assigned? do
    token = Config.discord_bot_token()
    StringUtils.present?(token)
  end

  @doc """
  Checks if a license key is present.

  ## Returns
  - `true` if a license key is present.
  - `false` otherwise.
  """
  @spec license_key_present?() :: boolean()
  def license_key_present? do
    key = Config.license_key()
    StringUtils.present?(key)
  end

  @doc """
  Checks if the notifier API token is valid.

  ## Returns
  - `true` if the notifier API token is present.
  - `false` otherwise.
  """
  @spec validate_notifier_api_token?() :: boolean()
  def validate_notifier_api_token? do
    token = Config.notifier_api_token()
    StringUtils.present?(token)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Response Parsing
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Extracts the license validity status from a response.

  ## Parameters
  - `response`: The response map (with atom or string keys).

  ## Returns
  - `true` or `false` based on the license validity.
  """
  @spec extract_license_valid(map()) :: boolean()
  def extract_license_valid(response) do
    response[:license_valid] || response["license_valid"] || response[:valid] ||
      response["valid"] || false
  end

  @doc """
  Extracts the bot assignment status from a response.

  ## Parameters
  - `response`: The response map (with atom or string keys).

  ## Returns
  - `true` or `false` based on the bot assignment status.
  """
  @spec extract_bot_assigned(map()) :: boolean()
  def extract_bot_assigned(response) do
    response[:bot_associated] || response["bot_associated"] || response[:bot_assigned] ||
      response["bot_assigned"] || false
  end

  @doc """
  Extracts the error message from a response if present.

  ## Parameters
  - `response`: The response map (with atom or string keys).

  ## Returns
  - The error message string or `nil`.
  """
  @spec extract_message(map()) :: String.t() | nil
  def extract_message(response) do
    response[:message] || response["message"]
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Error Formatting
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Formats an error reason into a human-readable message.

  ## Parameters
  - `reason`: The error reason (atom, tuple, or any term).

  ## Returns
  - A human-readable error message string.
  """
  @spec format_error_message(atom() | {atom(), any()} | any()) :: String.t()
  def format_error_message(:rate_limited), do: "License server rate limit exceeded"
  def format_error_message(:timeout), do: "License validation timed out"
  def format_error_message(:invalid_response), do: "Invalid response from license server"
  def format_error_message(:invalid_license_key), do: "Invalid or missing license key"
  def format_error_message(:invalid_api_token), do: "Invalid or missing API token"

  def format_error_message({reason, _detail}) when is_atom(reason),
    do: "License server error: #{reason}"

  def format_error_message(reason) when is_atom(reason), do: "License server error: #{reason}"

  def format_error_message(reason), do: "License server error: #{inspect(reason)}"

  @doc """
  Creates a default error state map.

  ## Parameters
  - `error_type`: The type of error (atom).
  - `error_message`: The error message string.

  ## Returns
  - A map representing the error state.
  """
  @spec default_error_state(atom(), String.t()) :: map()
  def default_error_state(error_type, error_message) do
    %{
      valid: false,
      bot_assigned: false,
      details: nil,
      error: error_type,
      error_message: error_message,
      last_validated: :os.system_time(:second)
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helpers
  # ══════════════════════════════════════════════════════════════════════════════

  defp typeof(data) when is_binary(data), do: "string"
  defp typeof(data) when is_map(data), do: "map"
  defp typeof(data) when is_list(data), do: "list"
  defp typeof(data) when is_atom(data), do: "atom"
  defp typeof(data) when is_integer(data), do: "integer"
  defp typeof(data) when is_float(data), do: "float"
  defp typeof(_), do: "unknown"
end
