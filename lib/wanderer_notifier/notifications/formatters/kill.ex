defmodule WandererNotifier.Notifications.Formatters.Kill do
  @moduledoc """
  Formats kill notifications for delivery.
  Handles all kill-related notification formatting logic.
  """

  alias WandererNotifier.Notifications.Formatters.{Base, Embed}

  @doc """
  Formats a kill notification into a Discord-compatible format.

  ## Parameters
    - notification_data: Map containing the kill notification data
      Required keys:
        - :killmail - The killmail data
        - :character_id - The character ID that triggered the notification
        - :character_name - The character name that triggered the notification
        - :corporation_id - The corporation ID that triggered the notification
        - :corporation_name - The corporation name that triggered the notification

  ## Returns
    - {:ok, formatted_notification} on success
    - {:error, reason} on failure
  """
  def format(notification_data) do
    try do
      formatted = %{
        content: build_content(notification_data),
        embeds: build_embeds(notification_data),
        components: build_components(notification_data)
      }

      {:ok, formatted}
    rescue
      e ->
        require Logger
        Logger.error("Failed to format kill notification: #{inspect(e)}")
        {:error, "Failed to format kill notification"}
    end
  end

  # Private Functions

  defp build_content(%{character_name: character_name}) do
    "#{character_name} has been involved in a kill!"
  end

  defp build_embeds(%{killmail: killmail} = data) do
    victim = get_in(killmail, ["victim"])
    attacker = get_in(killmail, ["attackers"]) |> List.first()

    embed =
      Embed.create_basic_embed(
        "Killmail Report",
        build_description(killmail),
        determine_color(victim)
      )
      |> add_victim_fields(victim)
      |> add_attacker_fields(attacker)
      |> add_value_fields(killmail)
      |> add_location_fields(killmail)
      |> add_metadata(data)

    [embed]
  end

  defp build_components(_notification_data) do
    # No components needed for kill notifications currently
    []
  end

  defp build_description(killmail) do
    victim_name = get_in(killmail, ["victim", "character_name"]) || "Unknown"
    ship_type = get_in(killmail, ["victim", "ship_type", "name"]) || "Unknown Ship"

    "#{victim_name} lost their #{ship_type}"
  end

  defp determine_color(victim) do
    case get_in(victim, ["position", "security_status"]) do
      sec when is_number(sec) and sec >= 0.5 -> :highsec
      sec when is_number(sec) and sec > 0.0 -> :lowsec
      sec when is_number(sec) and sec <= 0.0 -> :nullsec
      _ -> :default
    end
  end

  defp add_victim_fields(embed, victim) do
    embed
    |> Embed.add_field_if_available("Victim", victim["character_name"])
    |> Embed.add_field_if_available("Corporation", victim["corporation_name"])
    |> Embed.add_field_if_available("Alliance", victim["alliance_name"])
    |> Embed.add_field_if_available("Ship", get_in(victim, ["ship_type", "name"]))
  end

  defp add_attacker_fields(embed, attacker) do
    embed
    |> Embed.add_field_if_available("Final Blow", attacker["character_name"])
    |> Embed.add_field_if_available("Corporation", attacker["corporation_name"])
    |> Embed.add_field_if_available("Alliance", attacker["alliance_name"])
    |> Embed.add_field_if_available("Ship", get_in(attacker, ["ship_type", "name"]))
    |> Embed.add_field_if_available("Weapon", get_in(attacker, ["weapon_type", "name"]))
  end

  defp add_value_fields(embed, killmail) do
    total_value = get_in(killmail, ["zkb", "totalValue"]) || 0

    embed
    |> Embed.add_field_if_available(
      "Total Value",
      Base.format_compact_isk_value(total_value)
    )
  end

  defp add_location_fields(embed, killmail) do
    solar_system = get_in(killmail, ["solar_system", "name"]) || "Unknown"
    security_status = get_in(killmail, ["solar_system", "security_status"]) || 0.0

    formatted_security = Base.format_security_status(security_status)

    embed
    |> Embed.add_field_if_available("System", solar_system)
    |> Embed.add_field_if_available("Security", formatted_security)
  end

  defp add_metadata(embed, %{character_name: name, corporation_name: corp}) do
    embed
    |> Embed.add_author(name)
    |> Embed.add_footer("#{corp} Kill Notification")
  end
end
