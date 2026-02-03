defmodule WandererNotifier.Domains.License.LicenseService do
  @moduledoc """
  License management GenServer for WandererNotifier.

  This module manages license state including validation status, bot assignment,
  and notification counts. It delegates validation logic to LicenseValidator
  and HTTP calls to LicenseClient.
  """
  use GenServer
  require Logger

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Shared.Utils.ErrorHandler
  alias WandererNotifier.Domains.License.LicenseValidator
  alias WandererNotifier.Domains.License.LicenseClient

  # Define the behaviour callbacks
  @callback validate() :: map()
  @callback status() :: map()

  # ══════════════════════════════════════════════════════════════════════════════
  # State Structure
  # ══════════════════════════════════════════════════════════════════════════════

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
            notification_counts: notification_counts(),
            backoff_multiplier: pos_integer()
          }

    defstruct valid: false,
              bot_assigned: false,
              details: nil,
              error: nil,
              error_message: nil,
              last_validated: nil,
              notification_counts: %{system: 0, character: 0, killmail: 0},
              backoff_multiplier: 1

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

  # ══════════════════════════════════════════════════════════════════════════════
  # Client API
  # ══════════════════════════════════════════════════════════════════════════════

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
    with {:ok, result} <- safe_validate_call(),
         true <- LicenseValidator.valid_result?(result) do
      result
    else
      {:error, :timeout} ->
        Logger.error("License validation timed out", category: :config)
        LicenseValidator.default_error_state(:timeout, "License validation timed out")

      {:error, {:exception, e}} ->
        Logger.error("Error in license validation: #{inspect(e)}", category: :config)

        LicenseValidator.default_error_state(
          :exception,
          "License validation error: #{inspect(e)}"
        )

      {:unexpected, result} ->
        Logger.error("Unexpected result from license validation: #{inspect(result)}",
          category: :config
        )

        LicenseValidator.default_error_state(:unexpected_result, "Unexpected validation result")
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
  Validates the API token.
  The token should be a non-empty string.
  """
  def validate_token do
    LicenseValidator.validate_token()
  end

  @doc """
  Gets the license key from configuration.
  """
  def get_license_key do
    Config.license_key()
  end

  @doc """
  Gets the license manager URL from configuration.
  """
  def get_license_manager_url do
    Config.license_manager_api_url()
  end

  @doc """
  Checks if the current license is valid.
  """
  def check_license do
    if LicenseValidator.license_and_bot_valid?() do
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

  @doc """
  Validates a bot by calling the license manager API.
  Delegates to LicenseClient.
  """
  def validate_bot(notifier_api_token, license_key) do
    LicenseClient.validate_bot(notifier_api_token, license_key)
  end

  @doc """
  Validates a license key by calling the license manager API.
  Delegates to LicenseClient.
  """
  def validate_license(license_key, notifier_api_token) do
    LicenseClient.validate_license(license_key, notifier_api_token)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Server Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    schedule_refresh()
    Logger.debug("License Service starting up", category: :config)

    {:ok, State.new(), {:continue, :initial_validation}}
  end

  @impl true
  def handle_continue(:initial_validation, state) do
    {:ok, new_state} =
      try do
        Logger.debug("License Service performing initial validation", category: :config)

        _license_key = Config.license_key()
        Logger.debug("License key loaded", category: :config)

        _notifier_api_token = Config.notifier_api_token()
        Logger.debug("API token loaded", category: :config)

        license_manager_url = Config.license_manager_api_url()
        Logger.debug("License manager URL", url: license_manager_url, category: :config)

        new_state = do_validate(state)

        if new_state.valid do
          Logger.debug(
            "License validated successfully: #{new_state.details["status"] || "valid"}",
            category: :config
          )
        else
          error_msg = new_state.error_message || "No error message provided"
          Logger.warning("License validation warning: #{error_msg}", category: :config)
        end

        {:ok, new_state}
      rescue
        error ->
          Logger.error(
            "License validation failed, continuing with invalid license state: #{ErrorHandler.format_error(error)}"
          )

          fallback_state = %State{
            valid: false,
            bot_assigned: false,
            details: nil,
            error: :exception,
            error_message: "License validation error: #{ErrorHandler.format_error(error)}",
            last_validated: :os.system_time(:second),
            notification_counts: state.notification_counts
          }

          {:ok, fallback_state}
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:validate, _from, state) do
    notifier_api_token = Config.notifier_api_token()
    license_key = Config.license_key()

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

    {:reply, new_state, new_state}
  catch
    type, reason ->
      handle_validation_error(type, reason, state)
  end

  @impl true
  def handle_call(:status, _from, state) do
    safe_state = ensure_complete_state(state)
    {:reply, safe_state, safe_state}
  end

  @impl true
  def handle_call({:feature_enabled, feature}, _from, state) do
    is_enabled = LicenseValidator.check_feature_enabled(feature, state)
    {:reply, is_enabled, state}
  end

  @impl true
  def handle_call(:valid, _from, state) do
    {:reply, state.valid, state}
  end

  @impl true
  def handle_call(:premium, _from, state) do
    Logger.debug("Premium check: not premium (premium tier removed)", category: :config)
    {:reply, false, state}
  end

  @impl true
  def handle_call({:set_status, status}, _from, state) do
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

  @impl true
  def handle_info(:refresh, state) do
    new_state = do_validate(state)
    schedule_refresh(new_state.backoff_multiplier)
    {:noreply, new_state}
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helpers - State Management
  # ══════════════════════════════════════════════════════════════════════════════

  defp safe_validate_call do
    ErrorHandler.with_timeout(
      fn -> {:ok, GenServer.call(__MODULE__, :validate)} end,
      5000
    )
  end

  defp schedule_refresh(backoff_multiplier \\ 1) do
    base_interval = Config.license_refresh_interval()
    interval = min(base_interval * backoff_multiplier, base_interval * 10)
    Process.send_after(self(), :refresh, interval)
  end

  defp do_validate(state) do
    license_key = Config.license_key()
    notifier_api_token = Config.notifier_api_token()
    license_manager_url = Config.license_manager_api_url()

    log_validation_parameters(license_manager_url)

    if LicenseValidator.should_use_dev_mode?() do
      create_dev_mode_state(state)
    else
      validate_with_api(state, notifier_api_token, license_key)
    end
  end

  defp log_validation_parameters(license_manager_url) do
    Logger.debug("License validation parameters",
      license_url: license_manager_url,
      env: Application.get_env(:wanderer_notifier, :environment),
      category: :config
    )
  end

  defp create_dev_mode_state(state) do
    Logger.debug("Using development mode license validation", category: :config)

    dev_state = %State{
      valid: true,
      bot_assigned: true,
      details: %{"license_valid" => true, "valid" => true, "message" => "Development mode"},
      error: nil,
      error_message: nil,
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts || %{system: 0, character: 0, killmail: 0},
      backoff_multiplier: 1
    }

    Logger.debug("Development license active")
    dev_state
  end

  defp validate_with_api(state, notifier_api_token, license_key) do
    Logger.debug("Performing license validation with API", category: :config)

    api_result = LicenseClient.validate_bot(notifier_api_token, license_key)
    Logger.debug("License API result")

    process_api_result(api_result, state)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helpers - Response Processing
  # ══════════════════════════════════════════════════════════════════════════════

  defp process_validation_result({:ok, response}, state) do
    license_valid = LicenseValidator.extract_license_valid(response)
    bot_assigned = LicenseValidator.extract_bot_assigned(response)

    {license_valid, bot_assigned, response, nil, nil, state}
  end

  defp process_validation_result({:error, :rate_limited}, state) do
    {false, false, nil, :rate_limited, "License validation failed: Rate limit exceeded", state}
  end

  defp process_validation_result({:error, reason}, state) do
    {false, false, nil, :validation_error, "License validation failed: #{inspect(reason)}", state}
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

  defp handle_validation_error(type, reason, state) do
    Logger.error("License validation HTTP error: #{inspect(type)}, #{inspect(reason)}",
      category: :config
    )

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

  @dialyzer {:nowarn_function, process_api_result: 2}
  defp process_api_result({:ok, response}, state) do
    license_valid = LicenseValidator.extract_license_valid(response)
    message = LicenseValidator.extract_message(response)

    if license_valid do
      create_valid_license_state(response, state)
    else
      create_invalid_license_state(response, message, state)
    end
  end

  defp process_api_result({:error, :rate_limited}, state) do
    error_message = "License server rate limit exceeded"
    Logger.error("License validation rate limited: #{error_message}", category: :config)

    rate_limited_state = %State{
      valid: state.valid,
      bot_assigned: state.bot_assigned,
      error: :rate_limited,
      error_message: error_message,
      details: state.details,
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts,
      backoff_multiplier: min(state.backoff_multiplier * 2, 32)
    }

    Logger.info(
      "Rate limited license state, next retry with #{rate_limited_state.backoff_multiplier}x backoff",
      state: inspect(rate_limited_state),
      category: :config
    )

    rate_limited_state
  end

  defp process_api_result({:error, reason}, state) do
    error_message = LicenseValidator.format_error_message(reason)
    Logger.error("License/bot validation failed: #{error_message}", category: :config)

    error_state = %State{
      valid: false,
      bot_assigned: false,
      error: reason,
      error_message: error_message,
      details: nil,
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts || %{system: 0, character: 0, killmail: 0},
      backoff_multiplier: min(state.backoff_multiplier * 2, 32)
    }

    Logger.info("Error license state")
    error_state
  end

  @dialyzer {:nowarn_function, create_valid_license_state: 2}
  defp create_valid_license_state(response, state) do
    bot_assigned = LicenseValidator.extract_bot_assigned(response)

    if !bot_assigned do
      Logger.debug(
        "License is valid but no bot is assigned. Please assign a bot to your license.",
        category: :config
      )
    end

    valid_state = %State{
      valid: true,
      bot_assigned: bot_assigned,
      details: response,
      error: nil,
      error_message: if(bot_assigned, do: nil, else: "License valid but bot not assigned"),
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts || %{system: 0, character: 0, killmail: 0},
      backoff_multiplier: 1
    }

    if not state.valid or state.bot_assigned != bot_assigned do
      log_message =
        if bot_assigned,
          do: "License validated - bot assigned",
          else: "License validated - awaiting bot assignment"

      Logger.info(log_message)
    else
      Logger.debug("License validation successful (status unchanged)")
    end

    valid_state
  end

  @dialyzer {:nowarn_function, create_invalid_license_state: 3}
  defp create_invalid_license_state(response, message, state) do
    error_msg = message || "License is not valid"
    Logger.error("License validation failed - #{error_msg}", category: :config)

    invalid_state = %State{
      valid: false,
      bot_assigned: false,
      details: response,
      error: :invalid_license,
      error_message: error_msg,
      last_validated: :os.system_time(:second),
      notification_counts: state.notification_counts || %{system: 0, character: 0, killmail: 0},
      backoff_multiplier: min(state.backoff_multiplier * 2, 32)
    }

    Logger.info("Invalid license state")
    invalid_state
  end

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

    base_state = Map.merge(defaults, Map.take(state || %{}, Map.keys(defaults)))

    if is_map(base_state[:notification_counts]) do
      base_state
    else
      Map.put(base_state, :notification_counts, defaults.notification_counts)
    end
  end
end
