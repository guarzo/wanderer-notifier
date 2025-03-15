defmodule WandererNotifier.License do
  @moduledoc """
  License validation and management for WandererNotifier.
  Handles license validation and bot assignment verification.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.LicenseManager.Client, as: LicenseClient
  alias WandererNotifier.Config.Timings

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
  Returns true if the license is valid, false otherwise.
  """
  def validate do
    try do
      GenServer.call(__MODULE__, :validate, 5000)
    rescue
      e ->
        Logger.error("Error in license validation: #{inspect(e)}")
        %{valid: false, error_message: "License validation error: #{inspect(e)}"}
    catch
      :exit, {:timeout, _} ->
        Logger.error("License validation timed out")
        %{valid: false, error_message: "License validation timed out"}
      type, reason ->
        Logger.error("License validation error: #{inspect(type)}, #{inspect(reason)}")
        %{valid: false, error_message: "License validation error: #{inspect(reason)}"}
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
    {:ok, %{valid: false, bot_assigned: false}, {:continue, :initial_validation}}
  end

  @impl true
  def handle_continue(:initial_validation, _state) do
    new_state = do_validate()
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:validate, _from, state) do
    Logger.info("Validating license...")

    # Get the license key from configuration
    license_key = Config.license_key()

    # Get the bot API token from configuration
    bot_api_token = Config.bot_api_token()

    # Get the license manager API URL from configuration
    license_manager_url = Config.license_manager_api_url()

    # Log the license manager URL
    Logger.info("License Manager API URL: #{license_manager_url}")

    # Validate the license with a timeout
    validation_result =
      try do
        Task.await(Task.async(fn ->
          LicenseClient.validate_license(license_key, bot_api_token)
        end), 3000)
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
        {:ok, %{"valid" => true, "bot_assigned" => true} = response} ->
          Logger.info("License is valid and bot is assigned")
          {true, true, response, nil, nil}

        {:ok, %{"valid" => true, "bot_assigned" => false} = response} ->
          Logger.warning("License is valid but bot is not assigned")
          {true, false, response, :bot_not_assigned, "Bot is not assigned to this license"}

        {:ok, %{"valid" => false} = response} ->
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

    # Update the state with the validation result
    new_state = %{
      state |
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
    {:reply, state, state}
  end

  @impl true
  def handle_call({:feature_enabled, feature}, _from, state) do
    is_enabled =
      case state do
        %{valid: true, details: %{features: features}} when is_list(features) ->
          enabled = Enum.member?(features, to_string(feature))
          Logger.debug("Feature check: #{feature} - #{if enabled, do: "enabled", else: "disabled"}")
          enabled

        _ ->
          Logger.debug("Feature check: #{feature} - disabled (invalid license)")
          false
      end

    {:reply, is_enabled, state}
  end

  @impl true
  def handle_call(:premium, _from, state) do
    is_premium =
      case state do
        %{valid: true, details: %{tier: tier}} ->
          premium = tier in ["premium", "enterprise"]
          Logger.debug("Premium check: #{if premium, do: "premium", else: "not premium"} (tier: #{tier})")
          premium

        _ ->
          Logger.debug("Premium check: not premium (invalid license)")
          false
      end

    {:reply, is_premium, state}
  end

  @impl true
  def handle_info(:refresh, _state) do
    schedule_refresh()
    new_state = do_validate()
    {:noreply, new_state}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, Timings.license_refresh_interval())
  end

  defp do_validate do
    license_key = Config.license_key()
    bot_api_token = Config.bot_api_token()

    if is_nil(bot_api_token) || bot_api_token == "" do
      Logger.error("No bot API token configured")
      %{
        valid: false,
        bot_assigned: false,
        error: :no_bot_api_token,
        error_message: "No bot API token configured",
        details: nil
      }
    else
      # Validate the bot with the license in a single call
      case LicenseClient.validate_bot(bot_api_token, license_key) do
        {:ok, response} ->
          # Check if the license is valid from the response
          license_valid = response["license_valid"] || false

          if license_valid do
            Logger.info("License and bot validation successful")
          else
            Logger.error("License validation failed - License is not valid")
          end

          %{
            valid: license_valid,
            bot_assigned: true, # If we got a successful response, the bot is assigned
            details: response,
            error: nil,
            error_message: nil
          }

        {:error, reason} ->
          error_message = error_reason_to_message(reason)
          Logger.error("License/bot validation failed: #{error_message}")
          %{
            valid: false,
            bot_assigned: false,
            error: reason,
            error_message: error_message,
            details: nil
          }
      end
    end
  end

  # Convert error reasons to user-friendly messages
  defp error_reason_to_message(:invalid_bot_token), do: "Invalid bot API token"
  defp error_reason_to_message(:bot_not_authorized), do: "Bot is not authorized for this license"
  defp error_reason_to_message(:not_found), do: "Bot or license not found"
  defp error_reason_to_message(:bad_request), do: "Bad request to license server"
  defp error_reason_to_message(:request_failed), do: "Failed to connect to license server"
  defp error_reason_to_message(:invalid_response), do: "Invalid response from license server"
  defp error_reason_to_message(:api_error), do: "License API error"
  defp error_reason_to_message(reason), do: "Unknown error: #{inspect(reason)}"
end
