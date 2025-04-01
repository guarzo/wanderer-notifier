defmodule WandererNotifier.Schedulers.KillmailChartScheduler do
  @moduledoc """
  Scheduler for sending weekly killmail charts to Discord.
  """

  use GenServer
  require Logger

  alias WandererNotifier.ChartService.KillmailChartAdapter, as: ChartAdapter
  alias WandererNotifier.Config.Notifications, as: NotificationConfig
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  @behaviour WandererNotifier.Schedulers.Behaviour

  # For dependency injection in tests
  @adapter Application.compile_env(
             :wanderer_notifier,
             :killmail_chart_adapter,
             ChartAdapter
           )

  @config Application.compile_env(
            :wanderer_notifier,
            :config_module,
            NotificationConfig
          )

  @date_module Application.compile_env(
                 :wanderer_notifier,
                 :date_module,
                 Date
               )

  @notifier_factory Application.compile_env(
                      :wanderer_notifier,
                      :notifier_factory,
                      NotifierFactory
                    )

  @impl true
  def init(state) do
    AppLogger.scheduler_info("Initializing KillmailChartScheduler", %{state: inspect(state)})
    {:ok, state}
  end

  @impl true
  def enabled? do
    @config.kill_charts_enabled?()
  end

  @impl true
  def execute(date) do
    cond do
      not @config.kill_charts_enabled?() ->
        AppLogger.scheduler_info("Kill charts are disabled, skipping execution")
        {:ok, :skipped, %{}}

      not sunday?(date) ->
        AppLogger.scheduler_info("Not Sunday, skipping execution")
        {:ok, :skipped, %{}}

      true ->
        AppLogger.scheduler_info("Starting killmail chart scheduler execution")
        handle_chart_execution()
    end
  end

  @impl true
  def handle_info(:execute, state) do
    today = @date_module.utc_today()
    result = execute(today)
    {:noreply, Map.put(state, :last_result, result)}
  end

  defp handle_chart_execution do
    channel_id = @config.discord_channel_id_for(:kill_charts)

    case channel_id do
      nil ->
        AppLogger.scheduler_error("No channel ID configured for kill charts")
        {:error, "No channel ID configured", %{}}

      _ ->
        try do
          case @adapter.generate_weekly_kills_chart() do
            {:ok, chart_url} ->
              # Send chart to Discord
              AppLogger.scheduler_info("Generated weekly kills chart", %{url: chart_url})
              send_chart_to_discord(chart_url)

            {:error, reason} ->
              AppLogger.scheduler_error("Failed to generate weekly kills chart", error: reason)
              {:error, "Failed to generate weekly kills chart: #{reason}", %{}}
          end
        rescue
          e ->
            AppLogger.scheduler_error("Error sending weekly charts", error: Exception.message(e))
            {:error, "Error sending weekly charts: #{Exception.message(e)}", %{}}
        end
    end
  end

  defp send_chart_to_discord(chart_url) do
    embed = %{
      title: "Weekly Kill Charts",
      description: "Here are the weekly kill charts!",
      image: %{url: chart_url},
      color: 0x00FF00
    }

    case @notifier_factory.notify(:send_discord_embed, [embed]) do
      {:ok, result} ->
        {:ok, result, %{chart_url: chart_url}}

      {:error, %Nostrum.Error.ApiError{} = error} ->
        AppLogger.scheduler_error("Failed to send chart", error: inspect(error))
        {:error, "Failed to send chart: Failed to send notification", %{chart_url: chart_url}}

      {:error, reason} when is_binary(reason) ->
        AppLogger.scheduler_error("Failed to send chart", error: reason)
        {:error, "Failed to send chart: #{reason}", %{chart_url: chart_url}}

      {:error, other_error} ->
        AppLogger.scheduler_error("Failed to send chart", error: inspect(other_error))
        {:error, "Failed to send chart: Failed to send notification", %{chart_url: chart_url}}
    end
  end

  defp sunday?(date) do
    @date_module.day_of_week(date) == 7
  end

  @impl true
  def get_config do
    # For consistency with tests, always use 18:00
    %{
      type: :time,
      hour: 18,
      minute: 0,
      description: "Weekly character kill charts"
    }
  end

  # Debug helper
  @doc false
  def __debug_info__ do
    %{
      module: __MODULE__,
      config: get_config(),
      enabled: enabled?(),
      implements_health_check: function_exported?(__MODULE__, :health_check, 0)
    }
  end

  @doc """
  Returns whether kill charts are enabled in the configuration.
  """
  def kill_charts_enabled? do
    @config.kill_charts_enabled?()
  end
end
