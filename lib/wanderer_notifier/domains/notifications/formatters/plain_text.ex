defmodule WandererNotifier.Domains.Notifications.Formatters.PlainText do
  @moduledoc """
  Plain text formatting for Discord notifications.
  Provides fallback text representation when embeds are not available.
  """

  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter

  @doc """
  Format any notification as plain text.
  Delegates to unified formatter for consistency.
  """
  def format_plain_text(notification) do
    NotificationFormatter.format_plain_text(notification)
  end
end
