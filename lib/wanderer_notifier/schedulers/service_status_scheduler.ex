defmodule WandererNotifier.Schedulers.ServiceStatusScheduler do
  @moduledoc """
  Scheduler responsible for generating periodic service status reports.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Shared.Types.Constants
  alias WandererNotifier.Shared.Utils.{TimeUtils, ErrorHandler}

  @behaviour WandererNotifier.Schedulers.Scheduler

  defmodule State do
    @moduledoc """
    State for the service status scheduler.
    """
    defstruct last_run: nil,
              run_count: 0,
              timer_ref: nil

    @type t :: %__MODULE__{
            last_run: DateTime.t() | nil,
            run_count: non_neg_integer(),
            timer_ref: reference() | nil
          }

    @spec new() :: t()
    def new, do: %__MODULE__{}
  end

  @impl true
  def config, do: %{type: :interval, spec: Constants.service_status_interval()}

  @impl true
  def run do
    generate_service_status_report()
    :ok
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    Logger.info("ServiceStatusScheduler starting", opts: opts)
    state = State.new()
    timer_ref = schedule_next_run()
    {:ok, %{state | timer_ref: timer_ref}}
  end

  @impl GenServer
  def handle_info(:run_status_report, state) do
    ErrorHandler.safe_execute(
      fn -> run() end,
      fallback: fn error ->
        Logger.error("Error in scheduled status report",
          error: ErrorHandler.format_error(error)
        )
      end
    )

    timer_ref = schedule_next_run()

    new_state = %{
      state
      | last_run: TimeUtils.now(),
        run_count: state.run_count + 1,
        timer_ref: timer_ref
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_next_run do
    %{spec: interval} = config()
    Process.send_after(self(), :run_status_report, interval)
  end

  defp generate_service_status_report do
    ErrorHandler.safe_execute(
      fn -> maybe_send_status_report() end,
      fallback: fn error ->
        Logger.error("📊 Status report failed",
          error: ErrorHandler.format_error(error)
        )
      end
    )
  end

  defp maybe_send_status_report do
    if WandererNotifier.Shared.Config.status_messages_enabled?() do
      send_status_report_if_new()
    else
      Logger.info("📊 Status report skipped - disabled by config")
    end
  end

  defp send_status_report_if_new do
    alias WandererNotifier.Infrastructure.Cache.Deduplication

    formatted_uptime = calculate_formatted_uptime()
    current_minute = div(:os.system_time(:second), 60)
    dedup_key = "#{current_minute}"

    case Deduplication.check_and_mark(:status_report, dedup_key) do
      {:ok, :new} ->
        Logger.info("📊 Status report sent | #{formatted_uptime} uptime")
        send_discord_status_message(formatted_uptime)
        {:ok, :sent}

      {:ok, :duplicate} ->
        Logger.info("📊 Status report skipped - duplicate")
        {:ok, :skipped}

      {:error, reason} ->
        Logger.warning("📊 Status report skipped - deduplication error",
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp calculate_formatted_uptime do
    uptime_seconds = calculate_uptime()
    days = div(uptime_seconds, 86_400)
    hours = div(rem(uptime_seconds, 86_400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)
    "#{days}d #{hours}h #{minutes}m #{seconds}s"
  end

  defp send_discord_status_message(formatted_uptime) do
    status_message = """
    **WandererNotifier Service Status**

    ✅ System is operational
    ⏱️ Uptime: #{formatted_uptime}
    📅 Report generated at: #{DateTime.utc_now() |> DateTime.to_string()}

    _Automated periodic status report_
    """

    WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier.send_message(status_message)
  end

  defp calculate_uptime do
    case :erlang.statistics(:wall_clock) do
      {total_wall_clock, _} ->
        div(total_wall_clock, 1000)
    end
  end
end
