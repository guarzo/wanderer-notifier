defmodule WandererNotifierWeb.StatusController do
  @moduledoc """
  System status controller providing detailed application status.
  Replaces the existing basic web server functionality.
  """

  use Phoenix.Controller, formats: [:json]

  @doc """
  Detailed system status endpoint.
  Provides comprehensive information about the application state.
  """
  def show(conn, _params) do
    try do
      status = %{
        application: %{
          name: "WandererNotifier",
          version: Application.spec(:wanderer_notifier, :vsn) |> to_string(),
          environment: Application.get_env(:wanderer_notifier, :env, :dev),
          uptime_seconds: get_uptime_seconds()
        },
        services: get_service_status(),
        configuration: get_configuration_status(),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      json(conn, status)
    rescue
      error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: "Failed to retrieve status",
          message: Exception.message(error),
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })
    end
  end

  defp get_uptime_seconds do
    System.monotonic_time(:second) -
      Application.get_env(:wanderer_notifier, :start_time, System.monotonic_time(:second))
  end

  defp get_service_status do
    %{
      discord: get_discord_status(),
      killmail_processing: get_killmail_status(),
      map_integration: get_map_status(),
      cache: get_cache_status()
    }
  end

  defp get_discord_status do
    try do
      # Check if Discord consumer is alive
      case Process.whereis(WandererNotifier.Discord.Consumer) do
        nil ->
          %{status: "stopped", message: "Discord consumer not running"}

        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            %{status: "running", message: "Discord consumer active"}
          else
            %{status: "error", message: "Discord consumer unresponsive"}
          end
      end
    rescue
      _ -> %{status: "unknown", message: "Unable to check Discord status"}
    end
  end

  defp get_killmail_status do
    try do
      case Process.whereis(WandererNotifier.Killmail.Supervisor) do
        nil ->
          %{status: "stopped", message: "Killmail supervisor not running"}

        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            %{status: "running", message: "Killmail processing active"}
          else
            %{status: "error", message: "Killmail supervisor unresponsive"}
          end
      end
    rescue
      _ -> %{status: "unknown", message: "Unable to check killmail status"}
    end
  end

  defp get_map_status do
    try do
      case Process.whereis(WandererNotifier.Map.SSESupervisor) do
        nil ->
          %{status: "stopped", message: "Map SSE supervisor not running"}

        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            %{status: "running", message: "Map integration active"}
          else
            %{status: "error", message: "Map SSE supervisor unresponsive"}
          end
      end
    rescue
      _ -> %{status: "unknown", message: "Unable to check map status"}
    end
  end

  defp get_cache_status do
    try do
      cache_name = WandererNotifier.Cache.Config.cache_name()

      case Cachex.size(cache_name) do
        {:ok, size} -> %{status: "running", entries: size}
        {:error, reason} -> %{status: "error", message: "Cache error: #{inspect(reason)}"}
      end
    rescue
      _ -> %{status: "unknown", message: "Unable to check cache status"}
    end
  end

  defp get_configuration_status do
    %{
      notifications_enabled: WandererNotifier.Config.notifications_enabled?(),
      kill_notifications_enabled: WandererNotifier.Config.kill_notifications_enabled?(),
      system_notifications_enabled: WandererNotifier.Config.system_notifications_enabled?(),
      character_notifications_enabled: WandererNotifier.Config.character_notifications_enabled?()
    }
  end
end
