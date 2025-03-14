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
    GenServer.call(__MODULE__, :validate)
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
  def handle_call(:validate, _from, _state) do
    new_state = do_validate()
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
