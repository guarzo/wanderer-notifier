defmodule WandererNotifier.Notifications.LicenseLimiter do
  @moduledoc """
  Limits the number of rich notifications sent when the license is invalid.
  Tracks counts for each notification type using the License.Service GenServer.
  """

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
    license = license_service().status()
    count = license_service().get_notification_count(type)

    if license.valid do
      true
    else
      count < @max_rich
    end
  end

  def increment(type) when type in [:system, :character, :killmail] do
    license = license_service().status()

    unless license.valid do
      license_service().increment_notification_count(type)
    end
  end
end
