defmodule WandererNotifier.Schedulers.KillmailChartScheduler do
  @moduledoc """
  Schedules and processes weekly killmail charts.

  This scheduler is responsible for generating and sending character kill charts
  at the end of each week. It uses the weekly aggregated statistics to generate
  a visual representation of character performance.
  """

  require WandererNotifier.Schedulers.Factory
  require Logger

  alias WandererNotifier.ChartService.KillmailChartAdapter
  alias WandererNotifier.Core.Config

  # Run weekly on Sunday (day 7) at 18:00 UTC
  @default_hour 18
  @default_minute 0

  # Create a time-based scheduler with specific configuration
  WandererNotifier.Schedulers.Factory.create_scheduler(
    type: :time,
    default_hour: @default_hour,
    default_minute: @default_minute,
    hour_env_var: :killmail_chart_schedule_hour,
    minute_env_var: :killmail_chart_schedule_minute,
    enabled_check: &WandererNotifier.Schedulers.KillmailChartScheduler.persistence_enabled?/0
  )

  @impl true
  def execute(state) do
    # Only run on Sunday (day 7 of week)
    today = Date.utc_today()

    if Date.day_of_week(today) == 7 do
      Logger.info("Executing weekly killmail chart generation and sending to Discord")

      # Send the weekly kills chart
      result = send_weekly_kills_chart()
      process_result(result, state)
    else
      Logger.info(
        "Skipping weekly killmail chart - only runs on Sunday (today is day #{Date.day_of_week(today)})"
      )

      {:ok, :skipped, state}
    end
  end

  # Send the weekly kills chart
  defp send_weekly_kills_chart do
    # Only proceed if killmail persistence is enabled
    if Config.killmail_persistence_enabled?() do
      # Generate the chart title with the date range
      title = "Weekly Character Kills"
      description = "Top 20 characters by kills in the past week"

      # Get the appropriate Discord channel ID
      channel_id = Config.discord_channel_id_for(:charts)

      try do
        # Use the adapter to send the chart
        KillmailChartAdapter.send_weekly_kills_chart_to_discord(
          title,
          description,
          channel_id
        )
      rescue
        e ->
          Logger.error("Exception in weekly kills chart: #{Exception.message(e)}")
          Logger.error(Exception.format_stacktrace())
          {:error, Exception.message(e)}
      end
    else
      Logger.info("Killmail persistence is not enabled. Skipping weekly kills chart generation.")
      {:error, "Killmail persistence is not enabled"}
    end
  end

  # Process result and return appropriate response
  defp process_result(result, state) do
    case result do
      {:ok, _} ->
        Logger.info("Successfully sent weekly kills chart to Discord")
        {:ok, result, state}

      {:error, reason} ->
        Logger.error("Failed to send weekly kills chart: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  @doc """
  Checks if the persistence feature is enabled.
  This is used to determine if the scheduler should run.

  ## Returns
    - true if persistence is enabled
    - false otherwise
  """
  def persistence_enabled? do
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:enabled, false)
  end

  @impl true
  def get_config do
    %{
      type: :time,
      hour: @default_hour,
      minute: @default_minute,
      description: "Weekly character kill charts"
    }
  end
end
