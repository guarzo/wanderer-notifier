defmodule WandererNotifier.Notifications.LicenseLimiter do
  @moduledoc """
  Limits the number of rich notifications sent when the license is invalid.
  Tracks counts for each notification type using the License.Service GenServer.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @max_rich 5

  # Get the license service implementation - can be mocked in tests
  defp license_service do
    Application.get_env(
      :wanderer_notifier,
      :license_service,
      WandererNotifier.License.Service
    )
  end

  def should_send_rich?(type) when type in [:system, :character, :killmail] do
    case get_license_status_with_timeout() do
      {:ok, license} -> check_license_validity(license, type)
      # Default to allowing rich notifications if license service is unavailable
      {:error, reason} ->
        AppLogger.license_warn("License service unavailable, allowing rich notification",
          type: type,
          reason: inspect(reason)
        )
        true
    end
  end

  def increment(type) when type in [:system, :character, :killmail] do
    case get_license_status_with_timeout() do
      {:ok, license} -> maybe_increment_count(license, type)
      # Log error but don't block notification flow
      {:error, reason} ->
        AppLogger.license_error("Failed to increment notification count",
          type: type,
          reason: inspect(reason)
        )
        :ok
    end
  end

  # Helper function to check license validity and notification count
  defp check_license_validity(license, type) do
    if license.valid do
      true
    else
      check_notification_count(type)
    end
  end

  defp check_notification_count(type) do
    case get_notification_count_with_timeout(type) do
      {:ok, count} -> count < @max_rich
      # Default to allowing rich notifications on error
      {:error, reason} ->
        AppLogger.license_error("Failed to get notification count",
          type: type,
          reason: inspect(reason)
        )
        true
    end
  end

  defp maybe_increment_count(license, type) do
    if !license.valid do
      increment_count_async(type)
    end
  end

  defp increment_count_async(type) do
    # Use Task.start to make this non-blocking
    Task.start(fn ->
      try do
        license_service().increment_notification_count(type)
      rescue
        error ->
          AppLogger.license_error("Failed to increment notification count in background task",
            type: type,
            error: Exception.message(error),
            stacktrace: __STACKTRACE__
          )
          :ok
      end
    end)
  end

  # Helper functions with timeout handling
  defp get_license_status_with_timeout do
    try do
      # Short timeout to prevent blocking
      case GenServer.call(license_service(), :status, 1000) do
        result when is_map(result) -> {:ok, result}
        _ -> {:error, :invalid_response}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, reason}
      type, reason -> {:error, {type, reason}}
    end
  end

  defp get_notification_count_with_timeout(type) do
    try do
      # Short timeout to prevent blocking
      case GenServer.call(license_service(), {:get_notification_count, type}, 1000) do
        count when is_integer(count) -> {:ok, count}
        _ -> {:error, :invalid_response}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, reason}
      type, reason -> {:error, {type, reason}}
    end
  end
end
