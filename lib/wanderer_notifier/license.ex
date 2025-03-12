defmodule WandererNotifier.License do
  @moduledoc """
  License validation and management for WandererNotifier.
  Handles license validation and bot assignment verification.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.LicenseManager.Client, as: LicenseClient

  # Refresh license validation every 24 hours
  @refresh_interval :timer.hours(24)

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
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp do_validate do
    license_key = Config.license_key()
    bot_id = Config.bot_id()
    
    case LicenseClient.validate_license(license_key) do
      {:ok, response} ->
        Logger.info("License validation successful")
        
        # Check if the license is valid
        license_valid = response["license_valid"] || false
        
        # Check if our bot ID is in the list of assigned bots
        bot_assigned = is_bot_assigned(response, bot_id)
        
        if bot_assigned do
          Logger.info("Bot is properly assigned to the license")
        else
          Logger.error("Bot is not assigned to this license")
        end
        
        %{
          valid: license_valid, 
          bot_assigned: bot_assigned, 
          details: response,
          error: nil,
          error_message: nil
        }
          
      {:error, reason} ->
        error_message = error_reason_to_message(reason)
        Logger.error("License validation failed: #{error_message}")
        %{
          valid: false, 
          bot_assigned: false, 
          error: reason, 
          error_message: error_message,
          details: nil
        }
    end
  end
  
  # Check if the bot ID is in the list of assigned bots
  defp is_bot_assigned(%{"bots" => bots}, bot_id) when is_list(bots) and is_binary(bot_id) do
    Enum.any?(bots, fn bot -> 
      bot["id"] == bot_id && bot["is_active"] == true
    end)
  end
  
  defp is_bot_assigned(_, _), do: false
  
  # Convert error reasons to user-friendly messages
  defp error_reason_to_message(:license_not_found), do: "License not found"
  defp error_reason_to_message(:request_failed), do: "Failed to connect to license server"
  defp error_reason_to_message(:invalid_response), do: "Invalid response from license server"
  defp error_reason_to_message(:api_error), do: "License API error"
  defp error_reason_to_message(_), do: "Unknown error during license validation"
end
