# lib/wanderer_notifier/core/application/service.ex
defmodule WandererNotifier.Core.Application.Service do
  @moduledoc """
  Coordinates the RedisQ connection, kill processing, and periodic updates.
  """

  use GenServer

  alias WandererNotifier.Config
  alias WandererNotifier.Killmail.Processor, as: KillmailProcessor
  alias WandererNotifier.Killmail.RedisQClient
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @default_interval 30_000

  @typedoc "Internal state for the Service GenServer"
  @type state :: %__MODULE__.State{
          redisq_pid: pid() | nil,
          service_start_time: integer()
        }

  defmodule State do
    @moduledoc false
    defstruct [
      :redisq_pid,
      service_start_time: nil
    ]
  end

  ## Public API

  @doc "Start the service under its registered name"
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Mark a kill ID as processed (for deduplication)"
  @spec mark_as_processed(integer() | String.t()) :: :ok
  def mark_as_processed(kill_id), do: GenServer.cast(__MODULE__, {:mark_as_processed, kill_id})

  @doc "Get the list of recent kills (for API)"
  defdelegate get_recent_kills(), to: KillmailProcessor

  @doc """
  Checks if a service is running.
  """
  def running?(service_name) do
    case Process.whereis(service_name) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
    end
  end

  @doc """
  Gets the current environment.
  """
  def env, do: Application.get_env(:wanderer_notifier, :env)

  @doc """
  Gets the current version.
  """
  def version, do: Application.spec(:wanderer_notifier)[:vsn]

  @doc """
  Gets the current license status.
  """
  def license_status, do: :ok

  @doc """
  Gets the current license key.
  """
  def license_key, do: Config.license_key()

  @doc """
  Gets the current license manager API URL.
  """
  def license_manager_api_url, do: Config.license_manager_api_url()

  @doc """
  Gets the current license manager API key.
  """
  def license_manager_api_key, do: Config.license_manager_api_key()

  @doc """
  Gets the current API token.
  """
  def api_token, do: Config.api_token()

  @doc """
  Gets the current API key.
  """
  def api_key, do: Config.api_key()

  @doc """
  Gets the current API base URL.
  """
  def api_base_url, do: Config.api_base_url()

  @doc """
  Gets the current notifier API token.
  """
  def notifier_api_token, do: Config.api_token()

  @doc """
  Gets the current test mode status.
  """
  def test_mode_enabled?, do: Config.test_mode_enabled?()

  @doc """
  Gets the current character update scheduler interval.
  """
  def character_update_scheduler_interval, do: Config.character_update_scheduler_interval()

  @doc """
  Gets the current system update scheduler interval.
  """
  def system_update_scheduler_interval, do: Config.system_update_scheduler_interval()

  @doc """
  Gets the current schedulers enabled status.
  """
  def schedulers_enabled?, do: true

  @doc """
  Gets the current feature flags enabled status.
  """
  def feature_flags_enabled?, do: Config.feature_flags_enabled?()

  @doc """
  Gets the current character exclude list.
  """
  def character_exclude_list, do: Config.character_exclude_list()

  @doc """
  Gets the current features.
  """
  def features, do: Config.features()

  @doc """
  Gets the current feature enabled status.
  """
  def feature_enabled?(flag), do: Config.feature_enabled?(flag)

  @doc """
  Gets the current notifications enabled status.
  """
  def notifications_enabled?, do: Config.notifications_enabled?()

  @doc """
  Gets the current kill notifications enabled status.
  """
  def kill_notifications_enabled?, do: Config.kill_notifications_enabled?()

  @doc """
  Gets the current system notifications enabled status.
  """
  def system_notifications_enabled?, do: Config.system_notifications_enabled?()

  @doc """
  Gets the current character notifications enabled status.
  """
  def character_notifications_enabled?, do: Config.character_notifications_enabled?()

  @doc """
  Gets the current status messages enabled status.
  """
  def status_messages_enabled?, do: Config.status_messages_enabled?()

  @doc """
  Gets the current track kspace status.
  """
  def track_kspace?, do: Config.track_kspace?()

  @doc """
  Gets the current tracked systems notifications enabled status.
  """
  def tracked_systems_notifications_enabled?,
    do: Config.tracked_systems_notifications_enabled?()

  @doc """
  Gets the current tracked characters notifications enabled status.
  """
  def tracked_characters_notifications_enabled?,
    do: Config.tracked_characters_notifications_enabled?()

  @doc """
  Gets the current character tracking enabled status.
  """
  def character_tracking_enabled?, do: Config.character_tracking_enabled?()

  @doc """
  Gets the current system tracking enabled status.
  """
  def system_tracking_enabled?, do: Config.system_tracking_enabled?()

  @doc """
  Gets the current status messages disabled status.
  """
  def status_messages_disabled?, do: Config.status_messages_disabled?()

  @doc """
  Gets the current track kspace systems status.
  """
  def track_kspace_systems?, do: Config.track_kspace_systems?()

  @doc """
  Gets the current cache directory.
  """
  def cache_dir, do: Config.cache_dir()

  @doc """
  Gets the current cache name.
  """
  def cache_name, do: Config.cache_name()

  @doc """
  Gets the current port.
  """
  def port, do: Config.port()

  @doc """
  Gets the current host.
  """
  def host, do: Config.host()

  @doc """
  Gets the current scheme.
  """
  def scheme, do: Config.scheme()

  @doc """
  Gets the current public URL.
  """
  def public_url, do: Config.public_url()

  @doc """
  Gets the current environment variable.
  """
  def get_env(key, default \\ nil), do: Config.get_env(key, default)

  @doc """
  Gets all limits.
  """
  def get_all_limits, do: Config.get_all_limits()

  ## Server Implementation

  @impl true
  def init(_opts) do
    require Logger
    Logger.info("DEBUG: Service init called")

    # Initialize state
    state = %State{
      service_start_time: System.system_time(:second)
    }

    # Start the RedisQ client
    state = start_redisq(state)

    # Schedule maintenance
    state = schedule_maintenance(state, @default_interval)

    # Schedule startup notification
    state = schedule_startup_notice(state)

    Logger.info("DEBUG: Service init completed", state: inspect(state))
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    require Logger
    Logger.info("DEBUG: Service terminating", reason: inspect(reason))

    # Stop the RedisQ client if it exists
    if state.redisq_pid && Process.alive?(state.redisq_pid) do
      Logger.info("DEBUG: Stopping RedisQ client")
      GenServer.stop(state.redisq_pid, :normal)
    end

    :ok
  end

  @impl true
  def handle_cast({:mark_as_processed, kill_id}, state) do
    # Store in cache for deduplication
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    key = "killmail:#{kill_id}:processed"
    Cachex.put(cache_name, key, true, ttl: 3600)
    {:noreply, state}
  end

  @impl true
  def handle_info(:send_startup_notification, state) do
    try do
      AppLogger.startup_info("Service started", uptime: 0)
    rescue
      e ->
        AppLogger.startup_error("Startup notification failed", error: Exception.message(e))
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:run_maintenance, state) do
    require Logger

    Logger.info("DEBUG: Service maintenance cycle running", %{
      uptime: System.system_time(:second) - state.service_start_time,
      redisq_pid: inspect(state.redisq_pid)
    })

    try do
      run_maintenance()
    rescue
      e ->
        AppLogger.scheduler_error("Maintenance error", error: Exception.message(e))
    end

    # schedule next tick regardless of success/failure
    state = schedule_maintenance(state, @default_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(:test_alive, state) do
    require Logger

    Logger.info("DEBUG: Service received test_alive message", %{
      uptime: System.system_time(:second) - state.service_start_time,
      redisq_pid: inspect(state.redisq_pid)
    })

    AppLogger.processor_info("[TRACE] Service is alive and responding to messages")
    {:noreply, state}
  end

  @impl true
  def handle_info({:zkill_message, data}, state) do
    require Logger

    Logger.info("DEBUG: Service handle_info :zkill_message called", %{
      kill_id: data["killID"],
      uptime: System.system_time(:second) - state.service_start_time,
      redisq_pid: inspect(state.redisq_pid),
      message_queue_len: Process.info(self(), :message_queue_len) |> elem(1)
    })

    AppLogger.processor_info("[TRACE] Service received :zkill_message", %{
      kill_id: data["killID"],
      data: inspect(data),
      message_queue_len: Process.info(self(), :message_queue_len) |> elem(1)
    })

    try do
      # Transform the data into the expected format
      killmail_data = %{
        "killmail_id" => data["killID"],
        "killmail" => data["killmail"],
        "zkb" => data["zkb"],
        "solar_system_id" => get_in(data, ["killmail", "solar_system_id"]),
        "victim" => get_in(data, ["killmail", "victim"]),
        "attackers" => get_in(data, ["killmail", "attackers"])
      }

      Logger.info("DEBUG: Transformed killmail data", %{
        data: inspect(killmail_data),
        message_queue_len: Process.info(self(), :message_queue_len) |> elem(1)
      })

      # Check if we've already processed this killmail
      cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      key = "killmail:#{data["killID"]}:processed"

      Logger.info("DEBUG: Checking cache for killmail", %{
        cache_name: cache_name,
        key: key,
        message_queue_len: Process.info(self(), :message_queue_len) |> elem(1)
      })

      case Cachex.get(cache_name, key) do
        {:ok, true} ->
          Logger.info("DEBUG: Killmail already processed", kill_id: data["killID"])

          AppLogger.processor_info(
            "[TRACE] Skipping already processed killmail due to deduplication",
            %{kill_id: data["killID"]}
          )

          {:noreply, state}

        {:ok, nil} ->
          Logger.info("DEBUG: Killmail not in cache, proceeding with processing",
            kill_id: data["killID"]
          )

          AppLogger.processor_info("[TRACE] Deduplication check passed, processing killmail", %{
            kill_id: data["killID"]
          })

          # Process through the consolidated API
          Logger.info("DEBUG: Calling KillmailProcessor.process_killmail", %{
            kill_id: data["killID"],
            source: :zkill_redisq
          })

          # Process the killmail asynchronously
          Task.start(fn ->
            case KillmailProcessor.process_killmail(killmail_data,
                   source: :zkill_redisq,
                   state: state
                 ) do
              {:ok, result} ->
                # Mark as processed in cache
                Logger.info("DEBUG: Marking killmail as processed in cache",
                  kill_id: data["killID"]
                )

                Cachex.put(cache_name, key, true, ttl: 3600)

                # Log successful processing
                Logger.info("DEBUG: Successfully processed killmail", %{
                  kill_id: data["killID"],
                  result: inspect(result)
                })

                AppLogger.processor_info("Successfully processed killmail", %{
                  kill_id: data["killID"],
                  result: inspect(result)
                })

              {:error, reason} ->
                # Error occurred, log it but don't crash the process
                Logger.error("DEBUG: Error processing killmail", %{
                  error: inspect(reason),
                  kill_id: data["killID"]
                })

                AppLogger.processor_error("Error processing zkill message", %{
                  error: inspect(reason),
                  kill_id: data["killID"]
                })

              unexpected ->
                # Unexpected return value, log for debugging
                Logger.error("DEBUG: Unexpected return from process_killmail", %{
                  return_value: inspect(unexpected),
                  kill_id: data["killID"]
                })

                AppLogger.processor_error("Unexpected return from process_killmail", %{
                  return_value: inspect(unexpected),
                  kill_id: data["killID"]
                })
            end
          end)

          {:noreply, state}

        {:error, reason} ->
          Logger.error("DEBUG: Error checking cache", %{
            error: inspect(reason),
            kill_id: data["killID"]
          })

          {:noreply, state}
      end
    rescue
      e ->
        Logger.error("DEBUG: Exception in handle_info for :zkill_message", %{
          error: Exception.message(e),
          kill_id: data["killID"],
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })

        AppLogger.processor_error("Exception in handle_info for :zkill_message", %{
          error: Exception.message(e),
          kill_id: data["killID"],
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })

        {:noreply, state}
    end
  end

  @impl true
  # Catch-all to make unhandled messages visible in logs
  def handle_info(other, state) do
    AppLogger.processor_debug("Unhandled message in Service", msg: inspect(other))
    {:noreply, state}
  end

  ## Internal helpers

  # Start the RedisQ client
  defp start_redisq(state) do
    if Config.redisq_enabled?() do
      AppLogger.processor_debug("Starting RedisQ client")

      # Stop any existing RedisQ client
      if state.redisq_pid && Process.alive?(state.redisq_pid) do
        AppLogger.processor_debug("Stopping existing RedisQ client")
        GenServer.stop(state.redisq_pid, :normal)
      end

      case RedisQClient.start_link(
             queue_id: "wanderer_notifier_#{:rand.uniform(1_000_000)}",
             parent: self(),
             poll_interval: Config.redisq_poll_interval(),
             url: Config.redisq_url()
           ) do
        {:ok, pid} ->
          AppLogger.processor_debug("RedisQ client started", pid: inspect(pid))
          %{state | redisq_pid: pid}

        {:error, reason} ->
          AppLogger.processor_error("Failed to start RedisQ client", error: inspect(reason))
          state
      end
    else
      AppLogger.processor_info("RedisQ client disabled by configuration")
      state
    end
  end

  # Schedule the startup notification
  defp schedule_startup_notice(state) do
    Process.send_after(self(), :send_startup_notification, 2_000)
    state
  end

  # Schedule the maintenance loop
  @spec schedule_maintenance(state(), non_neg_integer()) :: state()
  defp schedule_maintenance(state, interval) do
    Process.send_after(self(), :run_maintenance, interval)
    state
  end

  # What runs on each maintenance tick
  defp run_maintenance do
    # Let the scheduler supervisor handle running the schedulers
    KillmailProcessor.schedule_tasks()
    :ok
  end
end
