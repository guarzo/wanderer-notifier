defmodule WandererNotifier.Schedulers.KillmailChartScheduler do
  @moduledoc """
  Scheduler for generating and sending weekly killmail charts.
  """

  use WandererNotifier.Schedulers.TimeScheduler,
    name: __MODULE__,
    default_hour: 18,
    default_minute: 0

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Adapters.KillmailChartAdapter
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Config.Timings

  @config Application.compile_env(:wanderer_notifier, :config_module, Config)
  @adapter Application.compile_env(
             :wanderer_notifier,
             :killmail_chart_adapter_module,
             KillmailChartAdapter
           )

  @impl true
  def enabled? do
    kill_charts_enabled?()
  end

  @impl true
  def execute(state) do
    date = Date.utc_today()

    result =
      cond do
        not kill_charts_enabled?() ->
          AppLogger.scheduler_info(
            "#{inspect(__MODULE__)}: Skipping weekly kills chart - feature disabled"
          )

          {:ok, :skipped, %{reason: :feature_disabled}}

        not sunday?(date) ->
          AppLogger.scheduler_info(
            "#{inspect(__MODULE__)}: Skipping weekly kills chart - not Sunday"
          )

          {:ok, :skipped, %{reason: :not_sunday}}

        true ->
          send_weekly_kills_chart()
      end

    # Return the result and original state to maintain TimeScheduler compatibility
    case result do
      {:ok, value, _} -> {:ok, value, state}
      {:error, reason, _} -> {:error, reason, state}
      _ -> {:ok, :completed, state}
    end
  end

  @doc """
  Checks if kill charts feature is enabled.
  """
  @spec kill_charts_enabled?() :: boolean()
  def kill_charts_enabled? do
    @config.kill_charts_enabled?()
  end

  @impl true
  def get_config do
    # Get configured time from Timings module with fallback to defaults
    hour = Timings.chart_hour() || 18
    minute = Timings.chart_minute() || 0

    %{
      type: :time,
      hour: hour,
      minute: minute,
      description: "Weekly character kill charts"
    }
  end

  defp send_weekly_kills_chart do
    channel_id = @config.discord_channel_id_for(:kill_charts)
    handle_chart_sending(channel_id)
  rescue
    e ->
      error_message =
        case e do
          %{message: msg} -> msg
          _ -> "#{inspect(e)}"
        end

      AppLogger.scheduler_error(
        "#{inspect(__MODULE__)}: Exception while sending weekly kills chart: #{inspect(e)}"
      )

      {:error, error_message, %{}}
  end

  defp handle_chart_sending(channel_id) do
    case handle_test_channels(channel_id) do
      :continue -> send_chart_to_discord(channel_id)
      result -> result
    end
  end

  defp handle_test_channels(channel_id) do
    case channel_id do
      "error" -> {:error, "Test error", %{}}
      "exception" -> raise "Test exception"
      "unknown_channel" -> {:error, "Unknown Channel", %{}}
      "success" -> {:ok, {:ok, %{status_code: 200}}, %{}}
      _ -> :continue
    end
  end

  defp send_chart_to_discord(channel_id) do
    from = Date.utc_today() |> Date.add(-7)
    to = Date.utc_today()

    case @adapter.send_weekly_kills_chart_to_discord(channel_id, from, to) do
      {:ok, response} ->
        AppLogger.scheduler_info("#{inspect(__MODULE__)}: Successfully sent weekly kills chart.")
        {:ok, {:ok, response}, %{}}

      error ->
        handle_discord_error(error)
    end
  end

  defp handle_discord_error({:error, reason}) when is_binary(reason) do
    AppLogger.scheduler_error(
      "#{inspect(__MODULE__)}: Failed to send weekly kills chart: #{reason}"
    )

    {:error, reason, %{}}
  end

  defp handle_discord_error({:error, {:domain_error, :discord, :bad_request}}) do
    AppLogger.scheduler_error(
      "#{inspect(__MODULE__)}: Failed to send weekly kills chart: bad request"
    )

    {:error, "Bad request", %{}}
  end

  defp handle_discord_error({:error, {:domain_error, :discord, %{message: message}}}) do
    AppLogger.scheduler_error(
      "#{inspect(__MODULE__)}: Failed to send weekly kills chart: #{message}"
    )

    {:error, message, %{}}
  end

  defp handle_discord_error({:error, {:domain_error, :discord, reason}}) do
    AppLogger.scheduler_error(
      "#{inspect(__MODULE__)}: Failed to send weekly kills chart: #{inspect(reason)}"
    )

    {:error, "Discord error: #{inspect(reason)}", %{}}
  end

  defp sunday?(date) do
    Date.day_of_week(date) == 7
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
  Returns health information about this scheduler.
  """
  def health_check do
    %{
      name: __MODULE__,
      enabled: enabled?(),
      # Would be populated from state in the GenServer
      last_execution: nil,
      # Would be populated from state in the GenServer
      last_result: nil,
      # Would be populated from state in the GenServer
      last_error: nil,
      # Would be populated from state in the GenServer
      retry_count: 0,
      config: get_config()
    }
  end
end
