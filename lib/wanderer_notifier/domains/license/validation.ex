defmodule WandererNotifier.Domains.License.Validation do
  @moduledoc """
  Legacy license validation module - DEPRECATED.

  This module has been consolidated into WandererNotifier.Shared.Validation.
  Use the new unified validation module instead:

  - `Validation.validate_license_response/1` instead of `normalize_response/1`
  - `Validation.validate_config_present/1` instead of individual validation functions

  This module will be removed in a future release.
  """

  alias WandererNotifier.Shared.Validation
  alias WandererNotifier.Shared.Config
  require Logger
  alias WandererNotifier.Shared.Utils.TimeUtils
  alias WandererNotifier.Shared.Utils.StringUtils

  @doc """
  Normalizes license API response to a consistent format.
  Handles both 'license_valid' and 'valid' response formats.
  """
  @spec normalize_response(map()) :: {:ok, map()} | {:error, :invalid_response}
  def normalize_response(response), do: Validation.validate_license_response(response)

  @doc """
  Validates if a bot token is assigned.
  """
  @spec bot_token_assigned?() :: boolean()
  def bot_token_assigned? do
    token = Config.discord_bot_token()
    StringUtils.present?(token)
  end

  @doc """
  Validates if a license key is present and non-empty.
  """
  @spec license_key_present?() :: boolean()
  def license_key_present? do
    key = Config.license_key()
    StringUtils.present?(key)
  end

  @doc """
  Checks if the API token is valid.
  """
  @spec api_token_valid?() :: boolean()
  def api_token_valid? do
    token = Config.notifier_api_token()
    StringUtils.present?(token)
  end

  @doc """
  Formats error reasons into human-readable messages.
  """
  @spec format_error_message(atom() | binary() | any()) :: binary()
  def format_error_message(:rate_limited), do: "License server rate limit exceeded"
  def format_error_message(:timeout), do: "License validation timed out"
  def format_error_message(:invalid_response), do: "Invalid response from license server"
  def format_error_message(:invalid_license_key), do: "Invalid or missing license key"
  def format_error_message(:invalid_api_token), do: "Invalid or missing API token"
  def format_error_message(reason) when is_atom(reason), do: "License server error: #{reason}"
  def format_error_message(reason) when is_binary(reason), do: reason
  def format_error_message(reason), do: "Unknown error: #{inspect(reason)}"

  @doc """
  Processes license validation result and logs appropriately.
  """
  @spec process_validation_result({:ok, map()} | {:error, term()}) ::
          {:ok, %{valid: boolean(), bot_assigned: boolean(), message: binary() | nil}}
          | {:error, term()}
  def process_validation_result({:ok, response}) do
    case normalize_response(response) do
      {:ok, normalized} ->
        log_validation_result(normalized)
        {:ok, normalized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def process_validation_result({:error, reason}) do
    {:error, reason}
  end

  @doc """
  Checks if both license key and bot token are valid.
  """
  @spec license_and_bot_valid?() :: boolean()
  def license_and_bot_valid? do
    bot_token_assigned?() && license_key_present?()
  end

  @doc """
  Validates configuration for development mode.
  Returns true if in dev/test mode and credentials are missing.
  """
  @spec should_use_dev_mode?() :: boolean()
  def should_use_dev_mode? do
    env = Application.get_env(:wanderer_notifier, :environment)
    env in [:dev, :test] && (!license_key_present?() || !api_token_valid?())
  end

  @doc """
  Creates a validation error response with consistent structure.
  """
  @spec create_error_response(atom(), binary() | nil) :: map()
  def create_error_response(error_type, message \\ nil) do
    %{
      valid: false,
      bot_assigned: false,
      error: error_type,
      error_message: message || format_error_message(error_type),
      timestamp: TimeUtils.now()
    }
  end

  @doc """
  Creates a successful validation response with consistent structure.
  """
  @spec create_success_response(map()) :: map()
  def create_success_response(details \\ %{}) do
    %{
      valid: true,
      bot_assigned: true,
      error: nil,
      error_message: nil,
      details: details,
      timestamp: TimeUtils.now()
    }
  end

  # Private functions

  defp log_validation_result(%{valid: true} = result) do
    Logger.info("License validation successful",
      bot_assigned: result.bot_assigned,
      message: result.message,
      category: :config
    )
  end

  defp log_validation_result(%{valid: false} = result) do
    Logger.warning("License validation failed",
      bot_assigned: result.bot_assigned,
      message: result.message || "No message provided",
      category: :config
    )
  end
end
