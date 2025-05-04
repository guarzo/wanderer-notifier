defmodule WandererNotifier.Notifications.LicenseLimiter do
  @moduledoc """
  Limits the number of rich notifications sent when the license is invalid.
  Tracks counts for each notification type using the License.Service GenServer.
  """

  @max_rich 5

  def should_send_rich?(type) when type in [:system, :character, :killmail] do
    license = WandererNotifier.License.Service.status()
    if license.valid do
      true
    else
      WandererNotifier.License.Service.get_notification_count(type) < @max_rich
    end
  end

  def increment(type) when type in [:system, :character, :killmail] do
    license = WandererNotifier.License.Service.status()
    unless license.valid do
      WandererNotifier.License.Service.increment_notification_count(type)
    end
  end
end
