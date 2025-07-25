defmodule WandererNotifier.Domains.Notifications.Formatters.System do
  @moduledoc """
  System notification formatting utilities.
  Now delegates to the unified formatter for consistency.
  """

  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Domains.Notifications.Formatters.Unified

  @doc """
  Format a system notification using the unified formatter.
  Maintains backward compatibility for existing callers.
  """
  def format_system_notification(%System{} = system) do
    Unified.format_notification(system)
  end
end
