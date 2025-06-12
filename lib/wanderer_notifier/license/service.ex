defmodule WandererNotifier.License.Service do
  @moduledoc """
  License management for WandererNotifier.
  Handles license validation and feature access control.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.Config.Utils
  alias WandererNotifier.License.Client, as: LicenseClient
  alias WandererNotifier.License.Validation
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
    with {:ok, result} <- safe_validate_call(),
         true <- valid_result?(result) do
      result
    else
      {:error, :timeout} ->
        AppLogger.config_error("License validation timed out")
        default_error_state(:timeout, "License validation timed out")

      {:error, {:exception, e}} ->
        AppLogger.config_error("Error in license validation: #{inspect(e)}")
        default_error_state(:exception, "License validation error: #{inspect(e)}")

      {:error, {:exit, type, reason}} ->
        AppLogger.config_error("License validation error: #{inspect(type)}, #{inspect(reason)}")
        default_error_state(type, "License validation error: #{inspect(reason)}")

      {:unexpected, result} ->
        AppLogger.config_error("Unexpected result from license validation: #{inspect(result)}")
        default_error_state(:unexpected_result, "Unexpected validation result")
    end
  end

  defp safe_validate_call do
    {:ok, GenServer.call(__MODULE__, :validate, 5000)}
  rescue
    e ->
      {:error, {:exception, e}}
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}

    type, reason ->
      {:error, {:exit, type, reason}}
  end

  defp valid_result?(result) do
    case result do
      map when is_map(map) and is_map_key(map, :valid) -> true
      other -> {:unexpected, other}
    end
  end

  defp default_error_state(error_type, error_message) do
    %{
      valid: false,
      bot_assigned: false,
      details: nil,
      error: error_type,
      error_message: error_message,
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
    is_valid = !Utils.nil_or_empty?(token)

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
    case valid?() do
      true -> {:ok, :valid}
      false -> {:error, :invalid_license}
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
    Validation.license_and_bot_valid?()
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

  defp process_validation_result({:ok, response}, state) do
    # Handle both normalized responses (with atom keys) and raw responses (with string keys)
    license_valid = response[:valid] || response["valid"] || response["license_valid"] || false
    # Check both possible field names for bot assignment
    bot_assigned =
      response[:bot_assigned] || response["bot_assigned"] || response["bot_associated"] || false

    {
      license_valid,
      bot_assigned,
      response,
      nil,
      nil,
      state
    }
  end

  defp process_validation_result({:error, :rate_limited}, state) do
    {
      false,
      false,
      nil,
      :rate_limited,
      "License validation failed: Rate limit exceeded",
      state
    }
  end

  defp process_validation_result({:error, reason}, state) do
    {
      false,
      false,
      nil,
      :validation_error,
      "License validation failed: #{inspect(reason)}",
      state
    }
  end

  defp create_new_state({valid, bot_assigned, details, error, error_message, old_state}, _state) do
    %State{
      valid: valid,
      bot_assigned: bot_assigned,
      details: details,
      error: error,
      error_message: error_message,
      last_validated: :os.system_time(:second),
      notification_counts:
        old_state.notification_counts || %{system: 0, character: 0, killmail: 0}
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

    # Use supervised task for license validation
    task =
      Task.Supervisor.async(WandererNotifier.TaskSupervisor, fn ->
        LicenseClient.validate_bot(notifier_api_token, license_key)
      end)

    validation_result =
      case Task.yield(task, 3000) || Task.shutdown(task) do
        {:ok, result} -> result
        nil -> {:error, :timeout}
      end

    new_state =
      validation_result
      |> process_validation_result(state)
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
    {:reply, state.valid, state}
  end

  @impl true
  def handle_call(:premium, _from, state) do
    AppLogger.config_info("Premium check: not premium (premium tier removed)")
    {:reply, false, state}
  end

  @impl true
  def handle_call({:set_status, status}, _from, state) do
    # Update license status
    {:reply, :ok, Map.put(state, :valid, status)}
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

  defp should_use_dev_mode?(_license_key, _notifier_api_token) do
    Validation.should_use_dev_mode?()
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
      notification_counts: state.notification_counts || %{system: 0, character: 0, killmail: 0}
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
    # Check if the license is valid from the normalized response
    # The response from validate_bot is already normalized and uses "valid" field
    license_valid = response[:valid] || response["valid"] || false
    # Extract error message if provided
    message = response[:message] || response["message"]

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
      notification_counts: state.notification_counts || %{system: 0, character: 0, killmail: 0}
    }

    AppLogger.config_info("⚠️ Error license state", state: inspect(error_state))
    error_state
  end

  defp create_valid_license_state(response, state) do
    # Check if bot is actually assigned from the normalized response
    # The response is already normalized and uses "bot_assigned" field
    bot_assigned = response[:bot_assigned] || response["bot_assigned"] || false

    # If license is valid but bot not assigned, handle it differently
    if !bot_assigned do
      AppLogger.config_debug(
        "License is valid but no bot is assigned. Please assign a bot to your license."
      )
    end

    valid_state = %{
      valid: true,
      bot_assigned: bot_assigned,
      details: response,
      error: nil,
      error_message: if(bot_assigned, do: nil, else: "License valid but bot not assigned"),
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts || %{system: 0, character: 0, killmail: 0}
    }

    log_message =
      if bot_assigned,
        do: "✅  Valid license with bot assigned",
        else: "⚠️  Valid license but bot not assigned"

    AppLogger.config_info(log_message, state: inspect(valid_state))
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
      notification_counts: state.notification_counts || %{system: 0, character: 0, killmail: 0}
    }

    AppLogger.config_info("❌ Invalid license state", state: inspect(invalid_state))
    invalid_state
  end

  # Helper function to convert error reasons to human-readable messages
  defp error_reason_to_message(reason), do: Validation.format_error_message(reason)

  # Helper to ensure the state has all required fields
  defp ensure_complete_state(state) do
    defaults = %{
      valid: false,
      bot_assigned: false,
      details: nil,
      error: nil,
      error_message: nil,
      last_validated: :os.system_time(:second),
      notification_counts: %{system: 0, character: 0, killmail: 0}
    }

    # Merge defaults with existing state, ensuring notification_counts is preserved
    base_state = Map.merge(defaults, Map.take(state || %{}, Map.keys(defaults)))

    # Ensure notification_counts is properly initialized
    if is_map(base_state[:notification_counts]) do
      base_state
    else
      Map.put(base_state, :notification_counts, defaults.notification_counts)
    end
  end
end
