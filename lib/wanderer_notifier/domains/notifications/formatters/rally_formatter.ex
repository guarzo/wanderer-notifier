defmodule WandererNotifier.Domains.Notifications.Formatters.RallyFormatter do
  @moduledoc """
  Formatter for rally point notifications.
  """

  # Orange color for rally points
  @rally_embed_color 0xFF6B00

  @doc """
  Format a rally point notification as a Discord embed.
  """
  def format_embed(rally_point) do
    %{
      embeds: [
        %{
          title: "⚔️ Rally Point Created",
          description: build_description(rally_point),
          color: @rally_embed_color,
          fields: build_fields(rally_point),
          footer: %{
            text: "Rally ID: #{rally_point.id}"
          },
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]
    }
  end

  @doc """
  Format a rally point notification as plain text.
  """
  def format_plain_text(rally_point) do
    system = get_field(rally_point, :system_name) || "Unknown system"
    character = get_field(rally_point, :character_name) || "Unknown pilot"
    "Rally point created in #{system} by #{character}"
  end

  # Private functions

  defp build_description(rally_point) do
    character = get_field(rally_point, :character_name) || "Unknown pilot"
    system = get_field(rally_point, :system_name) || "Unknown system"
    message = get_field(rally_point, :message)

    base_desc = "**#{character}** has created a rally point in **#{system}**"

    if message && message != "" do
      "#{base_desc}\n\n💬 #{message}"
    else
      base_desc
    end
  end

  defp build_fields(rally_point) do
    fields = [
      %{
        name: "System",
        value: get_field(rally_point, :system_name) || "Unknown",
        inline: true
      },
      %{
        name: "Created By",
        value: get_field(rally_point, :character_name) || "Unknown",
        inline: true
      }
    ]

    # Add corporation field if available
    corp_name = get_field(rally_point, :corporation_name)

    fields =
      if corp_name do
        fields ++
          [
            %{
              name: "Corporation",
              value: corp_name,
              inline: true
            }
          ]
      else
        fields
      end

    # Add alliance field if available
    alliance_name = get_field(rally_point, :alliance_name)

    if alliance_name do
      fields ++
        [
          %{
            name: "Alliance",
            value: alliance_name,
            inline: true
          }
        ]
    else
      fields
    end
  end

  # Helper function to get field from map with both atom and string keys
  defp get_field(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
