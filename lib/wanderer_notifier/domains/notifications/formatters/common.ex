defmodule WandererNotifier.Domains.Notifications.Formatters.Common do
  @moduledoc """
  Common notification formatting utilities for Discord notifications.
  Now delegates to the unified formatter for consistency.
  """

  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter

  @doc """
  Format any notification using the unified formatter.
  Handles both character and system notifications.
  """
  def format_notification(notification) do
    NotificationFormatter.format_notification(notification)
  end

  @doc """
  Convert a generic notification structure to Discord's specific format.
  This maintains backward compatibility while using the new unified structure.
  """
  def to_discord_format(notification) do
    components = Map.get(notification, :components, [])

    embed = %{
      "title" => Map.get(notification, :title, ""),
      "description" => Map.get(notification, :description, ""),
      "color" => Map.get(notification, :color, 0x3498DB),
      "url" => Map.get(notification, :url),
      "timestamp" => Map.get(notification, :timestamp),
      "footer" => Map.get(notification, :footer),
      "thumbnail" => Map.get(notification, :thumbnail),
      "image" => Map.get(notification, :image),
      "author" => Map.get(notification, :author),
      "fields" =>
        case Map.get(notification, :fields) do
          fields when is_list(fields) ->
            Enum.map(fields, fn field ->
              %{
                "name" => Map.get(field, :name, ""),
                "value" => Map.get(field, :value, ""),
                "inline" => Map.get(field, :inline, false)
              }
            end)

          _ ->
            []
        end
    }

    if Enum.empty?(components) do
      embed
    else
      Map.put(embed, "components", components)
    end
  end

  @doc """
  Legacy color functions - now delegate to Utilities
  """
  def colors() do
    # Return the legacy color map for backward compatibility
    %{
      default: 0x3498DB,
      success: 0x5CB85C,
      warning: 0xE28A0D,
      error: 0xD9534F,
      info: 0x3498DB,
      wormhole: 0x428BCA,
      highsec: 0x5CB85C,
      lowsec: 0xE28A0D,
      nullsec: 0xD9534F
    }
  end

  defdelegate convert_color(color),
    to: WandererNotifier.Domains.Notifications.Formatters.NotificationUtils,
    as: :get_color
end
