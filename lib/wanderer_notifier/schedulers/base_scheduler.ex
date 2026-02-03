defmodule WandererNotifier.Schedulers.BaseScheduler do
  @moduledoc """
  Base scheduler module that provides common functionality for map-related schedulers.
  These schedulers handle periodic updates of data from the map API.

  ## Usage

  Modules using this base scheduler must implement the required callbacks:
  - `feature_flag/0` - Returns the feature flag atom for enabling/disabling
  - `update_data/1` - Performs the actual data update
  - `cache_key/0` - Returns the cache key for storing data
  - `primed_key/0` - Returns the key for tracking primed state
  - `log_emoji/0` - Returns emoji for log messages
  - `log_label/0` - Returns label for log messages
  - `interval_key/0` - Returns the config key for update interval
  - `stats_type/0` - Returns :systems, :characters, or nil for metrics tracking

  ## Optional Callbacks

  - `polling_disabled_flag/0` - Returns the feature flag that disables polling for SSE.
    When this flag is enabled, the scheduler suppresses "feature disabled" log messages.
    Defaults to returning `nil` (no SSE override).
  """

  use GenServer
  require Logger

  alias WandererNotifier.Shared.Types.Constants
  alias WandererNotifier.Infrastructure.Cache

  # Required callbacks
  @callback feature_flag() :: atom()
  @callback update_data(any()) :: {:ok, any()} | {:error, any()}
  @callback cache_key() :: String.t()
  @callback primed_key() :: atom()
  @callback log_emoji() :: String.t()
  @callback log_label() :: String.t()
  @callback interval_key() :: atom()
  @callback stats_type() :: atom() | nil

  # Optional callback for SSE-based polling disable flag
  @callback polling_disabled_flag() :: atom() | nil
  @optional_callbacks [polling_disabled_flag: 0]

  @impl GenServer
  def init(opts) do
    {:ok, opts}
  end

  # ── Timer Management Helpers ─────────────────────────────────────────────────

  @doc """
  Schedules the next update by creating a timer that sends {:update, ref} message.
  Cancels any existing timer in the state first.
  Uses a unique ref to prevent processing stale timer messages.
  """
  @spec schedule_next_update(map()) :: map()
  def schedule_next_update(state) do
    state = cancel_timer(state)
    ref = make_ref()
    timer = Process.send_after(self(), {:update, ref}, state.interval)
    %{state | timer: timer, timer_ref: ref}
  end

  @doc """
  Cancels an existing timer if present in the state.
  Returns the state unchanged if no timer exists.
  Also clears the timer_ref.
  """
  @spec cancel_timer(map()) :: map()
  def cancel_timer(%{timer: nil} = state), do: %{state | timer_ref: nil}

  def cancel_timer(%{timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | timer: nil, timer_ref: nil}
  end

  @doc """
  Schedules a feature flag check after the configured interval.
  Uses a unique ref to prevent processing stale timer messages.
  """
  @spec schedule_feature_check(map()) :: map()
  def schedule_feature_check(state) do
    state = cancel_timer(state)
    ref = make_ref()
    timer = Process.send_after(self(), {:check_feature, ref}, Constants.feature_check_interval())
    %{state | timer: timer, timer_ref: ref}
  end

  @doc """
  Schedules an immediate update (0ms delay).
  Uses a unique ref to prevent processing stale timer messages.
  """
  @spec schedule_immediate_update(map()) :: map()
  def schedule_immediate_update(state) do
    state = cancel_timer(state)
    ref = make_ref()
    timer = Process.send_after(self(), {:update, ref}, 0)
    %{state | timer: timer, timer_ref: ref}
  end

  # ── Error Classification Helper ──────────────────────────────────────────────

  @doc """
  Classifies an error into a category for logging purposes.
  """
  @spec classify_error(any()) :: atom()
  def classify_error({:http_error, status, _}) when status >= 500, do: :server_error
  def classify_error({:http_error, status, _}) when status >= 400, do: :client_error
  def classify_error(:cache_error), do: :cache_error
  def classify_error(:invalid_data), do: :invalid_data
  def classify_error(_), do: :unknown_error

  # ── Stats Update Helper ──────────────────────────────────────────────────────

  @doc """
  Updates metrics with the tracked count for a scheduler.
  Only updates for :systems or :characters stat types.
  """
  @spec update_stats_count(module(), non_neg_integer()) :: :ok
  def update_stats_count(module, count) do
    case module.stats_type() do
      stat_type when stat_type in [:systems, :characters] ->
        WandererNotifier.Shared.Metrics.set_tracked_count(stat_type, count)

      _ ->
        :ok
    end
  end

  # ── Log Helper ───────────────────────────────────────────────────────────────

  @doc """
  Logs an update with change indicators.
  """
  @spec log_update(module(), list(), list()) :: :ok
  def log_update(module, new_data, old_data) do
    new_count = length(new_data)
    old_count = length(old_data)
    change = new_count - old_count

    change_indicator = format_change_indicator(change)

    emoji = module.log_emoji()
    label = module.log_label()

    Logger.info("#{emoji} #{label} updated | #{old_count} -> #{new_count} | #{change_indicator}")
  end

  defp format_change_indicator(change) when change > 0, do: "+ #{change}"
  defp format_change_indicator(change) when change < 0, do: "#{change}"
  defp format_change_indicator(_change), do: "No change"

  # ── Macro ────────────────────────────────────────────────────────────────────

  defmacro __using__(_opts) do
    quote do
      @behaviour WandererNotifier.Schedulers.BaseScheduler
      use GenServer
      require Logger

      alias WandererNotifier.Schedulers.BaseScheduler
      alias WandererNotifier.Shared.Types.Constants
      alias WandererNotifier.Infrastructure.Cache

      # Default implementation for optional callback
      def polling_disabled_flag, do: nil
      defoverridable polling_disabled_flag: 0

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl GenServer
      def init(opts) do
        primed? = check_primed_status()
        interval = get_scheduler_interval(opts)
        cached_data = get_cached_data()

        state = %{
          interval: interval,
          timer: nil,
          timer_ref: nil,
          primed: primed?,
          cached_data: cached_data
        }

        Logger.info("Scheduler initialized",
          module: __MODULE__,
          interval: state.interval,
          primed: state.primed,
          cached_count: length(cached_data)
        )

        {:ok, state, {:continue, :schedule}}
      end

      defp check_primed_status do
        __MODULE__
        |> Cache.Keys.scheduler_primed()
        |> Cache.get()
        |> Kernel.==({:ok, true})
      end

      defp get_scheduler_interval(opts) do
        default_interval = Keyword.get(opts, :interval, Constants.default_service_interval())
        config_key = interval_key()
        Application.get_env(:wanderer_notifier, config_key, default_interval)
      end

      defp get_cached_data do
        __MODULE__
        |> Cache.Keys.scheduler_data()
        |> Cache.get()
        |> case do
          {:ok, data} when is_list(data) ->
            data

          {:ok, nil} ->
            []

          {:ok, data} ->
            Logger.error("Invalid cached data format",
              key: Cache.Keys.scheduler_data(__MODULE__),
              data: inspect(data)
            )

            []

          {:error, reason} ->
            Logger.error("Failed to get cached data",
              key: Cache.Keys.scheduler_data(__MODULE__),
              error: inspect(reason)
            )

            []
        end
      end

      @impl GenServer
      def handle_continue(:schedule, state) do
        feature_flag_value = feature_flag()
        feature_enabled = WandererNotifier.Shared.Config.feature_enabled?(feature_flag_value)

        Logger.info("Scheduler feature check",
          module: __MODULE__,
          feature_flag: feature_flag_value,
          feature_enabled: feature_enabled
        )

        case feature_enabled do
          true ->
            Logger.info("Scheduling update",
              module: __MODULE__,
              feature: feature_flag(),
              enabled: true
            )

            {:noreply, BaseScheduler.schedule_immediate_update(state)}

          false ->
            maybe_log_feature_disabled(feature_flag_value)
            {:noreply, BaseScheduler.schedule_feature_check(state)}
        end
      end

      # Determine if we should log the feature disabled message.
      # If the scheduler has a polling_disabled_flag and it's enabled,
      # we suppress the log (SSE is handling updates instead).
      defp maybe_log_feature_disabled(feature_flag_value) do
        sse_flag = polling_disabled_flag()

        should_log =
          case sse_flag do
            nil ->
              true

            flag when is_atom(flag) ->
              not WandererNotifier.Shared.Config.feature_enabled?(flag)
          end

        case should_log do
          true ->
            Logger.info("Feature disabled",
              module: __MODULE__,
              feature: feature_flag_value,
              enabled: false
            )

          false ->
            :ok
        end
      end

      @impl GenServer
      def handle_info({:check_feature, ref}, %{timer_ref: ref} = state) do
        handle_continue(:schedule, state)
      end

      # Ignore stale check_feature messages with old refs
      def handle_info({:check_feature, _stale_ref}, state) do
        {:noreply, state}
      end

      @impl GenServer
      def handle_info({:update, ref}, %{timer_ref: ref} = state) do
        case update_data(state.cached_data) do
          {:ok, new_data} ->
            handle_update_success(new_data, state)

          {:error, reason} ->
            handle_update_error(reason, state)
        end
      end

      # Ignore stale update messages with old refs
      def handle_info({:update, _stale_ref}, state) do
        {:noreply, state}
      end

      defp handle_update_success(new_data, state) do
        __MODULE__
        |> Cache.Keys.scheduler_primed()
        |> Cache.put(true)

        __MODULE__
        |> Cache.Keys.scheduler_data()
        |> Cache.put(new_data)

        BaseScheduler.log_update(__MODULE__, new_data, state.cached_data)
        BaseScheduler.update_stats_count(__MODULE__, length(new_data))

        new_state = BaseScheduler.schedule_next_update(%{state | cached_data: new_data})
        {:noreply, new_state}
      end

      defp handle_update_error(reason, state) do
        error_type = BaseScheduler.classify_error(reason)

        Logger.error("Update failed",
          module: __MODULE__,
          error: inspect(reason),
          error_type: error_type
        )

        new_state = BaseScheduler.schedule_next_update(state)
        {:noreply, new_state}
      end

      @doc """
      Runs an update cycle manually.
      """
      def run do
        cached_data = get_cached_data()

        case update_data(cached_data) do
          {:ok, new_data} ->
            __MODULE__
            |> Cache.Keys.scheduler_data()
            |> Cache.put(new_data)

            {:ok, new_data}

          {:error, reason} ->
            Logger.error("Manual update failed", error: inspect(reason))
            {:error, reason}
        end
      end
    end
  end
end
