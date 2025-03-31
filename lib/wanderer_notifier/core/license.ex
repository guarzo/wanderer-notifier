defmodule WandererNotifier.Core.License do
  @moduledoc """
  License management for WandererNotifier.
  Handles license validation and feature access control.
  """
  use GenServer
  alias WandererNotifier.Config.Application
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.LicenseManager.Client, as: LicenseClient

  # Remove hardcoded interval
  # @refresh_interval :timer.hours(24)

  # Define the behaviour callbacks
  @callback validate() :: boolean()
  @callback status() :: map()

  # Client API

  @doc """
  Starts the License GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Validates the license key.
  Returns a map with license status information.
  """
  def validate do
    # Safely validate with fallback to a complete default state
    case GenServer.call(__MODULE__, :validate, 5000) do
      result when is_map(result) and is_map_key(result, :valid) ->
        # Proper result received
        result

      unexpected_result ->
        # Create a safe default state
        AppLogger.config_error(
          "Unexpected result from license validation: #{inspect(unexpected_result)}"
        )

        %{
          valid: false,
          bot_assigned: false,
          details: nil,
          error: :unexpected_result,
          error_message: "Unexpected validation result",
          last_validated: :os.system_time(:second)
        }
    end
  rescue
    e ->
      AppLogger.config_error("Error in license validation: #{inspect(e)}")

      %{
        valid: false,
        bot_assigned: false,
        details: nil,
        error: :exception,
        error_message: "License validation error: #{inspect(e)}",
        last_validated: :os.system_time(:second)
      }
  catch
    :exit, {:timeout, _} ->
      AppLogger.config_error("License validation timed out")

      %{
        valid: false,
        bot_assigned: false,
        details: nil,
        error: :timeout,
        error_message: "License validation timed out",
        last_validated: :os.system_time(:second)
      }

    type, reason ->
      AppLogger.config_error("License validation error: #{inspect(type)}, #{inspect(reason)}")

      %{
        valid: false,
        bot_assigned: false,
        details: nil,
        error: type,
        error_message: "License validation error: #{inspect(reason)}",
        last_validated: :os.system_time(:second)
      }
  end

  @doc """
  Returns the current license status.
  """
  def status do
    %{
      valid: valid?(),
      bot_assigned: bot_assigned?()
    }
  end

  @doc """
  Checks if a specific feature is enabled.
  """
  def feature_enabled?(feature) do
    GenServer.call(__MODULE__, {:feature_enabled, feature})
  end

  @doc """
  Validates the API token.
  The token should be a non-empty string.
  """
  def validate_token do
    token = Config.notifier_api_token()

    # Add detailed debug logging
    AppLogger.config_info(
      "License validation - token check (redacted): #{if token, do: "[REDACTED]", else: "nil"}"
    )

    AppLogger.config_info("License validation - environment: #{Application.get_env()}")

    # Basic validation - ensure token exists and is a non-empty string
    is_valid = is_binary(token) && String.trim(token) != ""

    if !is_valid do
      AppLogger.config_warn("License validation warning: Invalid notifier API token")
    end

    is_valid
  end

  @doc """
  Gets the license key from configuration.
  """
  def get_license_key do
    Application.get_env(:wanderer_notifier, :license_key)
  end

  @doc """
  Gets the license manager URL from configuration.
  """
  def get_license_manager_url do
    Application.get_env(:wanderer_notifier, :license_manager_url)
  end

  @doc """
  Checks if the current license is valid.
  """
  def check_license do
    if valid?() do
      {:ok, :valid}
    else
      {:error, :invalid_license}
    end
  end

  # Private helper to check if license is valid
  defp valid? do
    bot_assigned?() && license_key_valid?()
  end

  # Private helper to check if bot token is assigned
  defp bot_assigned? do
    case Application.get_env(:wanderer_notifier, :bot_token) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  # Private helper to check if license key is valid
  defp license_key_valid? do
    case Application.get_env(:wanderer_notifier, :license_key) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    schedule_refresh()
    # Initialize state with all necessary keys to avoid KeyError
    initial_state = %{
      valid: false,
      bot_assigned: false,
      details: nil,
      error: nil,
      error_message: nil,
      last_validated: :os.system_time(:second)
    }

    {:ok, initial_state, {:continue, :initial_validation}}
  end

  @impl true
  def handle_continue(:initial_validation, _state) do
    # Perform initial license validation at startup
    new_state = do_validate()

    if new_state.valid do
      AppLogger.config_info(
        "License validated successfully: #{new_state.details["status"] || "valid"}"
      )
    else
      error_msg = new_state.error_message || "No error message provided"
      AppLogger.config_warn("License validation warning: #{error_msg}")
    end

    {:noreply, new_state}
  rescue
    e ->
      AppLogger.config_error(
        "License validation failed, continuing with invalid license state: #{inspect(e)}"
      )

      # Return invalid license state but don't crash
      invalid_state = %{
        valid: false,
        bot_assigned: false,
        details: nil,
        error: :exception,
        error_message: "License validation error: #{inspect(e)}",
        last_validated: :os.system_time(:second)
      }

      {:noreply, invalid_state}
  end

  @impl true
  def handle_call(:validate, _from, _state) do
    AppLogger.config_info("Validating license...")

    # Get the license key from configuration
    license_key = Config.license_key()

    # Get the API token from configuration
    notifier_api_token = Config.notifier_api_token()

    # Validate the license with a timeout - use validate_bot for consistency with init/startup
    validation_result =
      Task.await(
        Task.async(fn ->
          # Use validate_bot for consistency with init/startup validation
          LicenseClient.validate_bot(notifier_api_token, license_key)
        end),
        3000
      )

    # Process the validation result
    {valid, bot_assigned, details, error, error_message} =
      case validation_result do
        {:ok, response} ->
          # Extract validation details from response
          {
            response["valid"] || false,
            response["bot_assigned"] || false,
            response,
            nil,
            nil
          }

        {:error, reason} ->
          # Handle validation error
          {
            false,
            false,
            nil,
            :validation_error,
            "License validation failed: #{inspect(reason)}"
          }
      end

    # Update state with validation results
    new_state = %{
      valid: valid,
      bot_assigned: bot_assigned,
      details: details,
      error: error,
      error_message: error_message,
      last_validated: :os.system_time(:second)
    }

    # Return the validation result and new state
    {:reply, new_state, new_state}
  catch
    :exit, {:timeout, _} ->
      AppLogger.config_error("License validation HTTP request timed out")

      error_state = %{
        valid: false,
        bot_assigned: false,
        details: nil,
        error: :timeout,
        error_message: "License validation timed out",
        last_validated: :os.system_time(:second)
      }

      {:reply, error_state, error_state}

    type, reason ->
      AppLogger.config_error(
        "License validation HTTP error: #{inspect(type)}, #{inspect(reason)}"
      )

      error_state = %{
        valid: false,
        bot_assigned: false,
        details: nil,
        error: :http_error,
        error_message: "License validation error: #{inspect(reason)}",
        last_validated: :os.system_time(:second)
      }

      {:reply, error_state, error_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    # Make sure we return a safe and complete state
    safe_state = ensure_complete_state(state)
    {:reply, safe_state, safe_state}
  end

  # Move this helper function to after all handle_call implementations

  @impl true
  def handle_call({:feature_enabled, feature}, _from, state) do
    is_enabled = check_feature_enabled(feature, state)
    {:reply, is_enabled, state}
  end

  @impl true
  def handle_call(:valid, _from, state) do
    # Return if license is valid (has been validated)
    {:reply, state.validated, state}
  end

  @impl true
  def handle_call(:premium, _from, state) do
    # Since we no longer have premium licenses, always return false
    # This is kept for backward compatibility
    AppLogger.config_debug("Premium check: not premium (premium tier removed)")
    {:reply, false, state}
  end

  @impl true
  def handle_call({:set_status, status}, _from, state) do
    # Update license status
    {:reply, :ok, Map.put(state, :validated, status)}
  end

  @impl true
  def handle_info(:refresh, _state) do
    schedule_refresh()
    new_state = do_validate()
    {:noreply, new_state}
  end

  # Helper function to check if a feature is enabled based on state
  defp check_feature_enabled(feature, state) do
    case state do
      %{valid: true, details: details}
      when is_map(details) and is_map_key(details, "features") ->
        check_features_list(feature, details["features"])

      _ ->
        AppLogger.config_debug("Feature check: #{feature} - disabled (invalid license)")
        false
    end
  end

  # Helper function to check if a feature is in the features list
  defp check_features_list(feature, features) do
    if is_list(features) do
      enabled = Enum.member?(features, to_string(feature))

      AppLogger.config_debug(
        "Feature check: #{feature} - #{if enabled, do: "enabled", else: "disabled"}"
      )

      enabled
    else
      AppLogger.config_debug("Feature check: #{feature} - disabled (features not a list)")
      false
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, Timings.license_refresh_interval())
  end

  defp do_validate do
    license_key = Config.license_key()
    notifier_api_token = Config.notifier_api_token()

    # Validate the license with the license manager
    case LicenseClient.validate_bot(notifier_api_token, license_key) do
      {:ok, response} ->
        # Check if the license is valid from the response
        license_valid = response["license_valid"] || false
        # Extract error message if provided
        message = response["message"]

        if license_valid do
          AppLogger.config_info("License and bot validation successful")
          # If valid, return success state
          %{
            valid: true,
            bot_assigned: true,
            details: response,
            error: nil,
            error_message: nil,
            last_validated: :os.system_time(:second)
          }
        else
          # For invalid license, return error state with message
          error_msg = message || "License is not valid"
          AppLogger.config_error("License validation failed - #{error_msg}")

          %{
            valid: false,
            bot_assigned: false,
            details: response,
            error: :invalid_license,
            error_message: error_msg,
            last_validated: :os.system_time(:second)
          }
        end

      {:error, reason} ->
        error_message = error_reason_to_message(reason)
        AppLogger.config_error("License/bot validation failed: #{error_message}")

        %{
          valid: false,
          bot_assigned: false,
          error: reason,
          error_message: error_message,
          details: nil,
          last_validated: :os.system_time(:second)
        }
    end
  end

  # Helper function to convert error reasons to human-readable messages
  defp error_reason_to_message(:api_error), do: "API error from license server"
  defp error_reason_to_message(:not_found), do: "License or bot not found"

  defp error_reason_to_message(:notifier_not_authorized),
    do: "Notifier not authorized for this license"

  defp error_reason_to_message(:invalid_notifier_token), do: "Invalid notifier API token"
  defp error_reason_to_message(:request_failed), do: "Failed to connect to license server"
  defp error_reason_to_message(reason) when is_atom(reason), do: "License server error: #{reason}"
  defp error_reason_to_message(reason) when is_binary(reason), do: reason
  defp error_reason_to_message(reason), do: "Unknown error: #{inspect(reason)}"

  # Helper to ensure the state has all required fields
  defp ensure_complete_state(state) do
    defaults = %{
      valid: false,
      bot_assigned: false,
      details: nil,
      error: nil,
      error_message: nil,
      last_validated: :os.system_time(:second)
    }

    # Merge defaults with existing state, but ensure we have all keys
    Map.merge(defaults, Map.take(state || %{}, Map.keys(defaults)))
  end
end
