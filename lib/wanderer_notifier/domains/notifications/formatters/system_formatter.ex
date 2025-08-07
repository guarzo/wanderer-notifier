defmodule WandererNotifier.Domains.Notifications.Formatters.SystemFormatter do
  @moduledoc """
  Formats system notifications for Discord.

  Handles system tracking notifications including wormhole information,
  static connections, effects, and recent kill data.
  """

  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Domains.Notifications.Formatters.NotificationUtils, as: Utils
  require Logger

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Formats a system embed for Discord.
  """
  def format_embed(%System{} = system, opts \\ []) do
    format_system_notification(system, opts)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Main Formatting Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp format_system_notification(%System{} = system, _opts) do
    is_wormhole = System.wormhole?(system)

    # Log system data for debugging
    Logger.debug("[Formatter] Formatting system notification",
      system_name: system.name,
      system_type: system.system_type,
      is_wormhole: is_wormhole,
      statics: inspect(system.statics),
      class_title: system.class_title,
      category: :notification
    )

    # Helper functions to handle potentially nil values
    system_id = Map.get(system, :solar_system_id, "Unknown")

    %{
      type: :system_notification,
      title: build_system_title(system),
      description: build_system_description(system, is_wormhole),
      color: determine_system_color(system, is_wormhole) |> Utils.get_color(),
      thumbnail:
        determine_system_icon(system, is_wormhole)
        |> Utils.get_system_icon()
        |> Utils.build_thumbnail(),
      fields: build_system_fields(system, is_wormhole),
      footer: Utils.build_footer("System ID: #{system_id}")
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Title and Description Building
  # ══════════════════════════════════════════════════════════════════════════════

  defp build_system_title(%System{} = system) do
    system_name = Map.get(system, :name, "Unknown")

    cond do
      system.tracked == true -> "New System Tracked: #{system_name}"
      system.tracked == false -> "System Removed: #{system_name}"
      true -> "System Update: #{system_name}"
    end
  end

  defp build_system_description(%System{} = system, is_wormhole) do
    base_description = get_tracking_action(system)
    system_type = get_system_type_description(system, is_wormhole)

    "A new #{system_type} has been #{base_description}."
  end

  defp get_tracking_action(%System{tracked: true}), do: "added to tracking"
  defp get_tracking_action(%System{tracked: false}), do: "removed from tracking"

  defp get_system_type_description(%System{class_title: class_title}, true)
       when class_title != nil do
    "wormhole system (#{class_title})"
  end

  defp get_system_type_description(%System{type_description: type_desc}, true)
       when type_desc != nil do
    "#{type_desc} wormhole system"
  end

  defp get_system_type_description(_, true), do: "wormhole system"

  defp get_system_type_description(%System{type_description: type_desc}, false)
       when type_desc != nil do
    "#{type_desc} system"
  end

  defp get_system_type_description(_, false), do: "system"

  # ══════════════════════════════════════════════════════════════════════════════
  # Field Building
  # ══════════════════════════════════════════════════════════════════════════════

  defp build_system_fields(%System{} = system, is_wormhole) do
    fields =
      []
      |> add_system_field(system)
      |> add_class_field(system, is_wormhole)
      |> add_security_field(system, is_wormhole)
      |> add_shattered_field(system, is_wormhole)
      |> add_statics_field(system, is_wormhole)
      |> add_region_field(system)
      |> add_effect_field(system, is_wormhole)
      |> add_recent_kills_field(system)
      |> Enum.reverse()

    # Log fields for debugging
    Logger.debug("System fields built",
      fields_count: length(fields),
      fields: inspect(fields),
      statics: inspect(system.statics),
      category: :notification
    )

    fields
  end

  defp add_system_field(fields, system) do
    system_link = Utils.create_system_link(system.name, system.solar_system_id)
    [Utils.build_field("System", system_link, true) | fields]
  end

  defp add_class_field(fields, system, is_wormhole) do
    if is_wormhole && system.class_title do
      [Utils.build_field("Class", system.class_title, true) | fields]
    else
      fields
    end
  end

  defp add_security_field(fields, system, is_wormhole) do
    cond do
      is_wormhole ->
        # For wormholes, show class information instead of security
        fields

      system.security_status ->
        security_text = format_security_status(system.security_status)
        [Utils.build_field("Security", security_text, true) | fields]

      system.type_description ->
        [Utils.build_field("Type", system.type_description, true) | fields]

      true ->
        fields
    end
  end

  defp add_shattered_field(fields, system, is_wormhole) do
    if is_wormhole && system.is_shattered do
      [Utils.build_field("Shattered", "Yes", true) | fields]
    else
      fields
    end
  end

  defp add_statics_field(fields, system, is_wormhole) do
    Logger.info(
      "[Formatter] add_statics_field - is_wormhole: #{is_wormhole}, statics: #{inspect(system.statics)}"
    )

    if is_wormhole && system.statics && length(system.statics) > 0 do
      statics_text = format_statics(system.statics)
      [Utils.build_field("Static Wormholes", statics_text, true) | fields]
    else
      fields
    end
  end

  defp add_region_field(fields, system) do
    if system.region_name do
      region_link =
        Utils.create_link(system.region_name, Utils.dotlan_region_url(system.region_name))

      [Utils.build_field("Region", region_link, true) | fields]
    else
      fields
    end
  end

  defp add_effect_field(fields, system, is_wormhole) do
    if is_wormhole && system.effect_name do
      [Utils.build_field("Effect", system.effect_name, true) | fields]
    else
      fields
    end
  end

  defp add_recent_kills_field(fields, system) do
    # Try to get recent kills for the system
    case WandererNotifier.Domains.Killmail.Enrichment.recent_kills_for_system(
           system.solar_system_id,
           3
         ) do
      kills when is_binary(kills) and kills != "" and kills != "No recent kills found" ->
        [Utils.build_field("Recent Kills", kills, false) | fields]

      _ ->
        fields
    end
  rescue
    error ->
      Logger.warning(
        "Failed to get recent kills for system #{system.solar_system_id}: #{inspect(error)}"
      )

      fields
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp format_statics(statics) when is_list(statics) do
    # If we have enriched static data with destinations, format it nicely
    statics
    |> Enum.map(fn
      %{"name" => name, "destination" => %{"short_name" => dest}} ->
        "#{name} → #{dest}"

      %{"name" => name} ->
        name

      static when is_binary(static) ->
        static

      _ ->
        "Unknown"
    end)
    |> Enum.join(", ")
  end

  defp format_statics(_), do: "N/A"

  defp format_security_status(security) when is_number(security) do
    formatted = Float.round(security, 1)

    cond do
      formatted >= 0.5 -> "#{formatted} (High-sec)"
      formatted > 0.0 -> "#{formatted} (Low-sec)"
      formatted == 0.0 -> "#{formatted} (Null-sec)"
      true -> "#{formatted} (Unknown)"
    end
  end

  defp format_security_status(_), do: "Unknown"

  defp determine_system_color(system, is_wormhole) do
    cond do
      is_wormhole -> :wormhole
      is_nil(system.security_status) -> :default
      system.security_status >= 0.5 -> :highsec
      system.security_status > 0.0 -> :lowsec
      system.security_status == 0.0 -> :nullsec
      true -> :default
    end
  end

  defp determine_system_icon(system, is_wormhole) do
    cond do
      is_wormhole -> :wormhole
      system.type_description -> icon_from_type_description(system.type_description)
      is_nil(system.security_status) -> :wormhole
      true -> icon_from_security_status(system.security_status)
    end
  end

  defp icon_from_type_description("High-sec"), do: :highsec
  defp icon_from_type_description("Low-sec"), do: :lowsec
  defp icon_from_type_description("Null-sec"), do: :nullsec
  defp icon_from_type_description(_), do: :wormhole

  defp icon_from_security_status(security) when security >= 0.5, do: :highsec
  defp icon_from_security_status(security) when security > 0.0, do: :lowsec
  defp icon_from_security_status(+0.0), do: :nullsec
  defp icon_from_security_status(_), do: :wormhole
end
