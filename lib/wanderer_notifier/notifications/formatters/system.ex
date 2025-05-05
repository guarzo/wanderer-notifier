defmodule WandererNotifier.Notifications.Formatters.System do
  @moduledoc """
  System notification formatting utilities for Discord notifications.
  Provides rich formatting for system tracking events.
  """
  require Logger
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Color and icon constants (can be refactored to a shared place if needed)
  @default_color 0x3498DB
  @wormhole_color 0x428BCA
  @highsec_color 0x5CB85C
  @lowsec_color 0xE28A0D
  @nullsec_color 0xD9534F
  @wormhole_icon "https://images.evetech.net/types/45041/icon"
  @highsec_icon "https://images.evetech.net/types/3802/icon"
  @lowsec_icon "https://images.evetech.net/types/3796/icon"
  @nullsec_icon "https://images.evetech.net/types/3799/icon"
  @default_icon "https://images.evetech.net/types/3802/icon"

  @doc """
  Creates a standard formatted system notification from a MapSystem struct.
  """
  def format_system_notification(%MapSystem{} = system) do
    validate_system_fields(system)

    is_wormhole = MapSystem.is_wormhole?(system)
    display_name = system.name # Only use the system name for the title

    formatted_statics = format_statics_list(Map.get(system, :static_details) || Map.get(system, :statics))
    system_name_with_link = create_system_name_link(system, display_name)

    {title, description, _color, icon_url} =
      generate_notification_elements(system, is_wormhole, display_name)

    fields =
      build_rich_system_notification_fields(
        system,
        is_wormhole,
        formatted_statics,
        system_name_with_link
      )

    %{
      type: :system_notification,
      title: title,
      description: description,
      color: determine_system_color_from_security(system),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{url: icon_url},
      fields: fields,
      footer: %{
        text: "System ID: #{system.solar_system_id}"
      }
    }
  rescue
    e ->
      Logger.error("[SystemFormatter] Exception formatting system notification: #{Exception.message(e)}\nStruct: #{inspect(system)}\nFields: #{inspect(Map.from_struct(system))}")
      AppLogger.processor_error("[SystemFormatter] Error formatting system notification",
        system: system.name,
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )
      reraise e, __STACKTRACE__
  end

  defp validate_system_fields(system) do
    if is_nil(system.solar_system_id) do
      raise "Cannot format system notification: solar_system_id is missing in MapSystem struct"
    end
    if is_nil(system.name) do
      raise "Cannot format system notification: name is missing in MapSystem struct"
    end
  end

  defp generate_notification_elements(system, is_wormhole, display_name) do
    title = generate_system_title(display_name)
    description = generate_system_description(is_wormhole, system.class_title, system.type_description)
    system_color = determine_system_color(system.type_description, is_wormhole)
    icon_url = determine_system_icon(is_wormhole, system.type_description, system.sun_type_id)
    {title, description, system_color, icon_url}
  end

  defp generate_system_title(display_name), do: "New System Tracked: #{display_name}"

  defp generate_system_description(is_wormhole, class_title, type_description) do
    cond do
      is_wormhole -> "A new wormhole system (#{class_title || "Unknown Class"}) has been added to tracking."
      type_description -> "A new #{type_description} system has been added to tracking."
      true -> "A new system has been added to tracking."
    end
  end

  defp determine_system_color(type_description, is_wormhole) do
    cond do
      is_wormhole -> @wormhole_color
      type_description == "Highsec" -> @highsec_color
      type_description == "Lowsec" -> @lowsec_color
      type_description == "Nullsec" -> @nullsec_color
      true -> @default_color
    end
  end

  defp determine_system_icon(is_wormhole, type_description, _sun_type_id) do
    cond do
      is_wormhole -> @wormhole_icon
      type_description == "Highsec" -> @highsec_icon
      type_description == "Lowsec" -> @lowsec_icon
      type_description == "Nullsec" -> @nullsec_icon
      true -> @default_icon
    end
  end

  defp format_statics_list(nil), do: "N/A"
  defp format_statics_list([]), do: "N/A"
  defp format_statics_list(statics) when is_list(statics) do
    Enum.map(statics, fn
      m when is_map(m) -> m["name"] || m[:name] || inspect(m)
      s -> to_string(s)
    end)
    |> Enum.join(", ")
  end
  defp format_statics_list(statics), do: to_string(statics)

  defp create_system_name_link(system, display_name) do
    has_numeric_id =
      is_integer(system.solar_system_id) ||
        (is_binary(system.solar_system_id) && Integer.parse(system.solar_system_id) != :error)
    if has_numeric_id do
      system_id_str = to_string(system.solar_system_id)
      has_temp_and_original =
        Map.get(system, :temporary_name) && Map.get(system, :temporary_name) != "" &&
          Map.get(system, :original_name) && Map.get(system, :original_name) != ""
      if has_temp_and_original do
        "[#{system.temporary_name} (#{system.original_name})](https://zkillboard.com/system/#{system_id_str}/)"
      else
        "[#{system.name}](https://zkillboard.com/system/#{system_id_str}/)"
      end
    else
      display_name
    end
  end

  defp build_rich_system_notification_fields(system, is_wormhole, formatted_statics, system_name_with_link) do
    fields = [%{name: "System", value: to_string(system_name_with_link), inline: true}]
    fields = add_shattered_field(fields, is_wormhole, Map.get(system, :is_shattered))
    fields = add_statics_field(fields, is_wormhole, formatted_statics)
    fields = add_region_field(fields, Map.get(system, :region_name))
    fields = add_effect_field(fields, is_wormhole, Map.get(system, :effect_name))
    fields = add_zkill_system_kills(fields, Map.get(system, :solar_system_id))
    # Ensure all field values are strings
    Enum.map(fields, fn field ->
      %{field | value: if(is_binary(field.value), do: field.value, else: inspect(field.value))}
    end)
  end

  defp add_shattered_field(fields, true, true), do: fields ++ [%{name: "Shattered", value: "Yes", inline: true}]
  defp add_shattered_field(fields, _, _), do: fields

  defp add_statics_field(fields, true, statics) when statics != "N/A", do: fields ++ [%{name: "Statics", value: to_string(statics), inline: true}]
  defp add_statics_field(fields, _, _), do: fields

  defp add_region_field(fields, region_name) when not is_nil(region_name), do: fields ++ [%{name: "Region", value: to_string(region_name), inline: true}]
  defp add_region_field(fields, _), do: fields

  defp add_effect_field(fields, true, effect_name) when not is_nil(effect_name), do: fields ++ [%{name: "Effect", value: to_string(effect_name), inline: true}]
  defp add_effect_field(fields, _, _), do: fields

  defp add_zkill_system_kills(fields, system_id) do
    system_id_int = parse_system_id(system_id)
    if is_nil(system_id_int) do
      fields
    else
      recent_kills = WandererNotifier.Killmail.Enrichment.recent_kills_for_system(system_id_int, 3)
      if recent_kills != [] do
        fields ++ [%{name: "Recent Kills", value: Enum.join(recent_kills, "\n"), inline: false}]
      else
        fields
      end
    end
  end

  defp parse_system_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_val, _} -> int_val
      :error -> nil
    end
  end
  defp parse_system_id(id) when is_integer(id), do: id
  defp parse_system_id(_), do: nil

  defp determine_system_color_from_security(_), do: @default_color
end
