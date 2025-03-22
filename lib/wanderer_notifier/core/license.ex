defmodule WandererNotifier.Core.License do
  @moduledoc """
  License management for WandererNotifier.
  Handles license validation and feature access control.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Core.Config
  alias WandererNotifier.LicenseManager.Client, as: LicenseClient
  alias WandererNotifier.Core.Config.Timings

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
    try do
      # Safely validate with fallback to a complete default state
      case GenServer.call(__MODULE__, :validate, 5000) do
        result when is_map(result) and is_map_key(result, :valid) ->
          # Proper result received
          result

        unexpected_result ->
          # Create a safe default state
          Logger.error("Unexpected result from license validation: #{inspect(unexpected_result)}")

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
        Logger.error("Error in license validation: #{inspect(e)}")

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
        Logger.error("License validation timed out")

        %{
          valid: false,
          bot_assigned: false,
          details: nil,
          error: :timeout,
          error_message: "License validation timed out",
          last_validated: :os.system_time(:second)
        }

      type, reason ->
        Logger.error("License validation error: #{inspect(type)}, #{inspect(reason)}")

        %{
          valid: false,
          bot_assigned: false,
          details: nil,
          error: type,
          error_message: "License validation error: #{inspect(reason)}",
          last_validated: :os.system_time(:second)
        }
    end
  end

  @doc """
  Returns the current license status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Checks if a specific feature is enabled.
  """
  def feature_enabled?(feature) do
    GenServer.call(__MODULE__, {:feature_enabled, feature})
  end

  @doc """
  Checks if the license is for a premium tier.
  """
  def premium? do
    GenServer.call(__MODULE__, :premium)
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
    try do
      new_state = do_validate()

      if new_state.valid do
        Logger.info("License validated successfully: #{new_state.details["status"] || "valid"}")
      else
        error_msg = new_state.error_message || "No error message provided"
        Logger.warning("License validation warning: #{error_msg}")
      end

      {:noreply, new_state}
    rescue
      e ->
        Logger.error(
          "License validation failed, continuing with invalid license state: #{inspect(e)}"
        )

        # Return invalid license state but don't crash
        invalid_state = %{
          valid: false,
          bot_assigned: false,
          details: nil,
          error: :exception,
          error_message: "Exception during validation: #{inspect(e)}",
          last_validated: :os.system_time(:second)
        }

        {:noreply, invalid_state}
    end
  end

  @impl true
  def handle_call(:validate, _from, _state) do
    Logger.info("Validating license...")

    # Get the license key from configuration
    license_key = Config.license_key()

    # Get the API token from configuration
    notifier_api_token = Config.notifier_api_token()

    # Validate the license with a timeout - use validate_bot for consistency with init/startup
    validation_result =
      try do
        Task.await(
          Task.async(fn ->
            # Use validate_bot for consistency with init/startup validation
            LicenseClient.validate_bot(notifier_api_token, license_key)
          end),
          3000
        )
      catch
        :exit, {:timeout, _} ->
          Logger.error("License validation HTTP request timed out")
          {:error, "License validation timed out"}

        type, reason ->
          Logger.error("License validation HTTP error: #{inspect(type)}, #{inspect(reason)}")
          {:error, "License validation error: #{inspect(reason)}"}
      end

    # Process the validation result
    {valid, bot_assigned, details, error, error_message} =
      case validation_result do
        # Handle validate_bot response format
        {:ok, %{"license_valid" => true} = response} ->
          Logger.info("License is valid and bot is assigned")
          {true, true, response, nil, nil}

        {:ok, %{"license_valid" => false} = response} ->
          error_msg = response["message"] || "License is invalid"
          Logger.error("License is invalid: #{error_msg}")
          {false, false, response, :invalid_license, error_msg}

        {:error, reason} ->
          Logger.error("License validation failed: #{inspect(reason)}")
          {false, false, %{}, :validation_failed, "License validation failed: #{inspect(reason)}"}

        unexpected ->
          Logger.error("Unexpected license validation result: #{inspect(unexpected)}")
          {false, false, %{}, :unexpected_result, "Unexpected validation result"}
      end

    # Create a new state map with all necessary fields
    new_state = %{
      valid: valid,
      bot_assigned: bot_assigned,
      details: details,
      error: error,
      error_message: error_message,
      last_validated: :os.system_time(:second)
    }

    # Schedule the next validation
    schedule_refresh()

    # Return the validation result and the updated state
    {:reply, new_state, new_state}
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
    is_premium =
      case state do
        %{valid: true, details: details} when is_map(details) and is_map_key(details, "tier") ->
          tier = details["tier"]
          premium = tier in ["premium", "enterprise"]

          Logger.debug(
            "Premium check: #{if premium, do: "premium", else: "not premium"} (tier: #{tier})"
          )

          premium

        _ ->
          Logger.debug("Premium check: not premium (invalid license state)")
          false
      end

    {:reply, is_premium, state}
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
        Logger.debug("Feature check: #{feature} - disabled (invalid license)")
        false
    end
  end

  # Helper function to check if a feature is in the features list
  defp check_features_list(feature, features) do
    if is_list(features) do
      enabled = Enum.member?(features, to_string(feature))

      Logger.debug("Feature check: #{feature} - #{if enabled, do: "enabled", else: "disabled"}")

      enabled
    else
      Logger.debug("Feature check: #{feature} - disabled (features not a list)")
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
          Logger.info("License and bot validation successful")
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
          Logger.error("License validation failed - #{error_msg}")

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
        Logger.error("License/bot validation failed: #{error_message}")

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
