defmodule WandererNotifier.License.Service do
  @moduledoc """
  License management for WandererNotifier.
  Handles license validation and feature access control.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.License.Client, as: LicenseClient
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Define the behaviour callbacks
  @callback validate() :: boolean()
  @callback status() :: map()

  # State struct for the License Service GenServer
  defmodule State do
    @moduledoc """
    State structure for the License Service GenServer.

    Maintains license validation status, bot assignment status,
    error information, and notification counts.
    """

    @type notification_counts :: %{
            system: non_neg_integer(),
            character: non_neg_integer(),
            killmail: non_neg_integer()
          }

    @type t :: %__MODULE__{
            valid: boolean(),
            bot_assigned: boolean(),
            details: map() | nil,
            error: atom() | nil,
            error_message: String.t() | nil,
            last_validated: integer(),
            notification_counts: notification_counts()
          }

    defstruct valid: false,
              bot_assigned: false,
              details: nil,
              error: nil,
              error_message: nil,
              last_validated: nil,
              notification_counts: %{system: 0, character: 0, killmail: 0}

    @doc """
    Creates a new License state with default values.
    """
    @spec new() :: t()
    def new do
      %__MODULE__{
        last_validated: :os.system_time(:second)
      }
    end
  end

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
    GenServer.call(__MODULE__, :status)
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

    AppLogger.config_info("License validation - environment: #{Config.get_env(:environment)}")

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
    Config.get_env(:license_key)
  end

  @doc """
  Gets the license manager URL from configuration.
  """
  def get_license_manager_url do
    Config.get_env(:license_manager_url)
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

  @doc """
  Increments the notification counter for the given type (:system, :character, :killmail).
  Returns the new count.
  """
  def increment_notification_count(type) when type in [:system, :character, :killmail] do
    GenServer.call(__MODULE__, {:increment_notification_count, type})
  end

  @doc """
  Gets the current notification count for the given type.
  """
  def get_notification_count(type) when type in [:system, :character, :killmail] do
    GenServer.call(__MODULE__, {:get_notification_count, type})
  end

  @doc """
  Forces a license revalidation and updates the GenServer state.
  Returns the new state.
  """
  def force_revalidate do
    GenServer.call(__MODULE__, :force_revalidate)
  end

  # Private helper to check if license is valid
  defp valid? do
    bot_assigned?() && license_key_valid?()
  end

  # Private helper to check if bot token is assigned
  defp bot_assigned? do
    case Config.get_env(:bot_token) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  # Private helper to check if license key is valid
  defp license_key_valid? do
    case Config.get_env(:license_key) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    schedule_refresh()
    AppLogger.config_info("License Service starting up")

    {:ok, State.new(), {:continue, :initial_validation}}
  end

  @impl true
  def handle_continue(:initial_validation, state) do
    # Perform initial license validation at startup
    AppLogger.config_info("License Service performing initial validation")

    license_key = Config.license_key()

    AppLogger.config_info("License key presence",
      present: is_binary(license_key) && String.length(license_key) > 0
    )

    notifier_api_token = Config.api_token()

    AppLogger.config_info("API token presence",
      present: is_binary(notifier_api_token) && String.length(notifier_api_token) > 0
    )

    license_manager_url = Config.license_manager_api_url()
    AppLogger.config_info("License manager URL", url: license_manager_url)

    new_state = do_validate(state)

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
      invalid_state = %State{
        valid: false,
        bot_assigned: false,
        details: nil,
        error: :exception,
        error_message: "License validation error: #{inspect(e)}",
        last_validated: :os.system_time(:second),
        notification_counts: state.notification_counts
      }

      {:noreply, invalid_state}
  end

  defp process_validation_result({:ok, response}) do
    {
      response["valid"] || false,
      response["bot_assigned"] || false,
      response,
      nil,
      nil
    }
  end

  defp process_validation_result({:error, :rate_limited}) do
    {
      false,
      false,
      nil,
      :rate_limited,
      "License validation failed: Rate limit exceeded"
    }
  end

  defp process_validation_result({:error, reason}) do
    {
      false,
      false,
      nil,
      :validation_error,
      "License validation failed: #{inspect(reason)}"
    }
  end

  defp create_new_state({valid, bot_assigned, details, error, error_message}, state) do
    %State{
      valid: valid,
      bot_assigned: bot_assigned,
      details: details,
      error: error,
      error_message: error_message,
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts
    }
  end

  defp reply_with_state(new_state) do
    {:reply, new_state, new_state}
  end

  defp handle_validation_error(type, reason, state) do
    AppLogger.config_error("License validation HTTP error: #{inspect(type)}, #{inspect(reason)}")

    error_state = %State{
      valid: false,
      bot_assigned: false,
      error: reason,
      error_message: "License validation error: #{inspect(reason)}",
      details: nil,
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts
    }

    {:reply, error_state, error_state}
  end

  @impl true
  def handle_call(:validate, _from, state) do
    notifier_api_token = Config.api_token()
    license_key = Config.license_key()

    task =
      Task.async(fn ->
        LicenseClient.validate_bot(notifier_api_token, license_key)
      end)

    validation_result =
      case Task.yield(task, 3000) || Task.shutdown(task) do
        {:ok, result} -> result
        nil -> {:error, :timeout}
      end

    new_state =
      validation_result
      |> process_validation_result()
      |> create_new_state(state)

    reply_with_state(new_state)
  catch
    type, reason ->
      handle_validation_error(type, reason, state)
  end

  @impl true
  def handle_call(:status, _from, state) do
    # Make sure we return a safe and complete state
    safe_state = ensure_complete_state(state)
    {:reply, safe_state, safe_state}
  end

  @impl true
  def handle_call({:feature_enabled, feature}, _from, state) do
    is_enabled = check_feature_enabled(feature, state)
    {:reply, is_enabled, state}
  end

  @impl true
  def handle_call(:valid, _from, state) do
    {:reply, state.validated, state}
  end

  @impl true
  def handle_call(:premium, _from, state) do
    AppLogger.config_info("Premium check: not premium (premium tier removed)")
    {:reply, false, state}
  end

  @impl true
  def handle_call({:set_status, status}, _from, state) do
    # Update license status
    {:reply, :ok, Map.put(state, :validated, status)}
  end

  @impl true
  def handle_call({:increment_notification_count, type}, _from, state) do
    counts = state.notification_counts
    new_count = Map.get(counts, type, 0) + 1
    new_counts = Map.put(counts, type, new_count)
    new_state = %{state | notification_counts: new_counts}
    {:reply, new_count, new_state}
  end

  @impl true
  def handle_call({:get_notification_count, type}, _from, state) do
    counts = state.notification_counts
    {:reply, Map.get(counts, type, 0), state}
  end

  @impl true
  def handle_call(:force_revalidate, _from, state) do
    new_state = do_validate(state)
    {:reply, new_state, new_state}
  end

  # Helper function to check if a feature is enabled based on state
  defp check_feature_enabled(feature, state) do
    case state do
      %{valid: true, details: details}
      when is_map(details) and is_map_key(details, "features") ->
        check_features_list(feature, details["features"])

      _ ->
        AppLogger.config_info("Feature check: #{feature} - disabled (invalid license)")
        false
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    new_state = do_validate(state)
    {:noreply, new_state}
  end

  # Helper function to check if a feature is in the features list
  defp check_features_list(feature, features) do
    if is_list(features) do
      enabled = Enum.member?(features, to_string(feature))

      AppLogger.config_info(
        "Feature check: #{feature} - #{if enabled, do: "enabled", else: "disabled"}"
      )

      enabled
    else
      AppLogger.config_info("Feature check: #{feature} - disabled (features not a list)")
      false
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, Config.license_refresh_interval())
  end

  defp do_validate(state) do
    license_key = Config.license_key()
    notifier_api_token = Config.api_token()
    license_manager_url = Config.license_manager_api_url()

    # Log detailed debugging information
    log_validation_parameters(license_key, notifier_api_token, license_manager_url)

    if should_use_dev_mode?(license_key, notifier_api_token) do
      create_dev_mode_state(state)
    else
      validate_with_api(state, notifier_api_token, license_key)
    end
  end

  defp log_validation_parameters(license_key, notifier_api_token, license_manager_url) do
    AppLogger.config_debug("License validation parameters",
      license_key_present: is_binary(license_key) && license_key != "",
      api_token_present: is_binary(notifier_api_token) && notifier_api_token != "",
      license_url: license_manager_url,
      env: Application.get_env(:wanderer_notifier, :environment)
    )
  end

  defp should_use_dev_mode?(license_key, notifier_api_token) do
    Application.get_env(:wanderer_notifier, :environment) in [:dev, :test] &&
      (is_nil(license_key) || license_key == "" || is_nil(notifier_api_token) ||
         notifier_api_token == "")
  end

  defp create_dev_mode_state(state) do
    AppLogger.config_debug("Using development mode license validation")

    dev_state = %{
      valid: true,
      bot_assigned: true,
      details: %{"license_valid" => true, "valid" => true, "message" => "Development mode"},
      error: nil,
      error_message: nil,
      last_validated: :os.system_time(:second),
      notification_counts: state[:notification_counts] || %{system: 0, character: 0, killmail: 0}
    }

    AppLogger.config_info("🧑‍💻 Development license active", state: inspect(dev_state))
    dev_state
  end

  defp validate_with_api(state, notifier_api_token, license_key) do
    AppLogger.config_debug("Performing license validation with API")

    # Validate the license with the license manager
    api_result = LicenseClient.validate_bot(notifier_api_token, license_key)
    AppLogger.config_debug("License API result", result: inspect(api_result))

    process_api_result(api_result, state)
  end

  defp process_api_result({:ok, response}, state) do
    # Check if the license is valid from the response
    license_valid = response["license_valid"] || false
    # Extract error message if provided
    message = response["message"]

    if license_valid do
      create_valid_license_state(response, state)
    else
      create_invalid_license_state(response, message, state)
    end
  end

  defp process_api_result({:error, :rate_limited}, state) do
    error_message = "License server rate limit exceeded"
    AppLogger.config_error("License validation rate limited: #{error_message}")

    # When rate limited, use the previous state but update error info
    rate_limited_state = %{
      # Keep previous validation status
      valid: state.valid,
      bot_assigned: state.bot_assigned,
      error: :rate_limited,
      error_message: error_message,
      # Keep previous details
      details: state.details,
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts
    }

    AppLogger.config_info("🚦 Rate limited license state", state: inspect(rate_limited_state))
    rate_limited_state
  end

  defp process_api_result({:error, reason}, state) do
    error_message = error_reason_to_message(reason)
    AppLogger.config_error("License/bot validation failed: #{error_message}")

    error_state = %{
      valid: false,
      bot_assigned: false,
      error: reason,
      error_message: error_message,
      details: nil,
      last_validated: :os.system_time(:second),
      notification_counts: state[:notification_counts] || %{system: 0, character: 0, killmail: 0}
    }

    AppLogger.config_info("⚠️ Error license state", state: inspect(error_state))
    error_state
  end

  defp create_valid_license_state(response, state) do
    valid_state = %{
      valid: true,
      bot_assigned: true,
      details: response,
      error: nil,
      error_message: nil,
      last_validated: :os.system_time(:second),
      notification_counts: state[:notification_counts] || %{system: 0, character: 0, killmail: 0}
    }

    AppLogger.config_info("✅ Valid license state", state: inspect(valid_state))
    valid_state
  end

  defp create_invalid_license_state(response, message, state) do
    # For invalid license, return error state with message
    error_msg = message || "License is not valid"
    AppLogger.config_error("License validation failed - #{error_msg}")

    invalid_state = %{
      valid: false,
      bot_assigned: false,
      details: response,
      error: :invalid_license,
      error_message: error_msg,
      last_validated: :os.system_time(:second),
      notification_counts: state[:notification_counts] || %{system: 0, character: 0, killmail: 0}
    }

    AppLogger.config_info("❌ Invalid license state", state: inspect(invalid_state))
    invalid_state
  end

  # Helper function to convert error reasons to human-readable messages
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
