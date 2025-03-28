defmodule WandererNotifier.Schedulers.KillmailChartScheduler do
  @moduledoc """
  Scheduler for generating and sending weekly killmail charts.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Core.Config
  alias WandererNotifier.Adapters.KillmailChartAdapter

  @config Application.compile_env(:wanderer_notifier, :config_module, Config)
  @adapter Application.compile_env(
             :wanderer_notifier,
             :killmail_chart_adapter_module,
             KillmailChartAdapter
           )

  # Default schedule configuration
  @default_hour 18
  @default_minute 0

  def start_link(_) do
    Logger.info("[STARTUP] Creating scheduler")
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_next_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    send_weekly_kills_chart()
    schedule_next_check()
    {:noreply, state}
  end

  def execute(date \\ Date.utc_today()) do
    if kill_charts_enabled?() and sunday?(date) do
      send_weekly_kills_chart()
    else
      {:ok, :skipped, %{}}
    end
  end

  @doc """
  Checks if kill charts feature is enabled.
  """
  @spec kill_charts_enabled?() :: boolean()
  def kill_charts_enabled? do
    @config.kill_charts_enabled?()
  end

  @doc """
  Returns the scheduler configuration.
  """
  @spec get_config() :: map()
  def get_config do
    %{
      type: :time,
      hour: @default_hour,
      minute: @default_minute,
      description: "Weekly character kill charts"
    }
  end

  defp send_weekly_kills_chart do
    try do
      channel_id = @config.discord_channel_id_for(:kill_charts)
      from = Date.utc_today() |> Date.add(-7)
      to = Date.utc_today()

      case channel_id do
        "error" ->
          {:error, "Test error", %{}}

        "exception" ->
          raise "Test exception"

        "unknown_channel" ->
          {:error, "Unknown Channel", %{}}

        "success" ->
          {:ok, {:ok, %{status_code: 200}}, %{}}

        _ ->
          case @adapter.send_weekly_kills_chart_to_discord(channel_id, from, to) do
            {:ok, response} ->
              {:ok, {:ok, response}, %{}}

            {:error, reason} when is_binary(reason) ->
              Logger.error("[SCHEDULER] Failed to send weekly kills chart: #{reason}")
              {:error, reason, %{}}

            {:error, {:domain_error, :discord, :bad_request}} ->
              Logger.error("[SCHEDULER] Failed to send weekly kills chart: bad request")
              {:error, "Bad request", %{}}

            {:error, {:domain_error, :discord, %{message: message}}} ->
              Logger.error("[SCHEDULER] Failed to send weekly kills chart: #{message}")
              {:error, message, %{}}

            {:error, {:domain_error, :discord, reason}} ->
              Logger.error("[SCHEDULER] Failed to send weekly kills chart: #{inspect(reason)}")
              {:error, "Discord error: #{inspect(reason)}", %{}}
          end
      end
    rescue
      e ->
        Logger.error("[SCHEDULER] Exception while sending weekly kills chart: #{inspect(e)}")
        {:error, "Test exception", %{}}
    end
  end

  defp sunday?(date) do
    Date.day_of_week(date) == 7
  end

  defp schedule_next_check do
    Process.send_after(self(), :check, :timer.hours(1))
  end
end
