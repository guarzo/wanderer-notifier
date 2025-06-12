defmodule WandererNotifier.Notifications.Formatters.System do
  @moduledoc """
  System notification formatting utilities for Discord notifications.
  Provides rich formatting for system tracking events.
  """
  require Logger
  alias WandererNotifier.Killmail.Enrichment
  alias WandererNotifier.Logger.Logger
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Utils.TimeUtils

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
    with :ok <- validate_system_fields(system),
         {:ok, formatted} <- safe_format_system(system) do
      formatted
    else
      {:error, :invalid_system_id} ->
        raise ArgumentError, "System must have a solar_system_id"

      {:error, :invalid_system_name} ->
        raise ArgumentError, "System must have a name"

      {:exception, exception, stacktrace} ->
        WandererNotifier.Logger.Logger.processor_error(
          "[SystemFormatter] Error formatting system notification",
          system: system.name,
          error: Exception.message(exception),
          struct: inspect(system),
          fields: inspect(Map.from_struct(system)),
          stacktrace: Exception.format_stacktrace(stacktrace)
        )

        reraise exception, stacktrace
    end
  end

  defp safe_format_system(system) do
    is_wormhole = MapSystem.wormhole?(system)
    # Only use the system name for the title
    display_name = system.name

    formatted_statics =
      format_statics_list(Map.get(system, :static_details) || Map.get(system, :statics))

    system_name_with_link = create_system_name_link(system, display_name)

    {title, description, color, icon_url} =
      generate_notification_elements(system, is_wormhole, display_name)

    fields =
      build_rich_system_notification_fields(
        system,
        is_wormhole,
        formatted_statics,
        system_name_with_link
      )

    {:ok,
     %{
       type: :system_notification,
       title: title,
       description: description,
       color: color,
       timestamp: TimeUtils.log_timestamp(),
       thumbnail: %{url: icon_url},
       fields: fields,
       footer: %{
         text: "System ID: #{system.solar_system_id}"
       }
     }}
  rescue
    exception ->
      {:exception, exception, __STACKTRACE__}
  end

  defp validate_system_fields(system) do
    cond do
      is_nil(system.solar_system_id) ->
        {:error, :invalid_system_id}

      is_nil(system.name) ->
        {:error, :invalid_system_name}

      true ->
        :ok
    end
  end

  defp generate_notification_elements(system, is_wormhole, display_name) do
    title = generate_system_title(display_name)

    description =
      generate_system_description(is_wormhole, system.class_title, system.type_description)

    system_color = determine_system_color(system.type_description, is_wormhole)
    icon_url = determine_system_icon(is_wormhole, system.type_description, system.sun_type_id)
    {title, description, system_color, icon_url}
  end

  defp generate_system_title(display_name), do: "New System Tracked: #{display_name}"

  defp generate_system_description(is_wormhole, class_title, type_description) do
    cond do
      is_wormhole ->
        "A new wormhole system (#{class_title || "Unknown Class"}) has been added to tracking."

      type_description ->
        "A new #{type_description} system has been added to tracking."

      true ->
        "A new system has been added to tracking."
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
    Enum.map_join(statics, ", ", fn
      static when is_binary(static) ->
        static

      static when is_map(static) ->
        name = Map.get(static, "name") || Map.get(static, :name) || "Unknown"

        dest =
          get_in(static, ["destination", "name"]) ||
            get_in(static, [:destination, :name]) ||
            "Unknown"

        "#{name} (#{dest})"

      other ->
        inspect(other)
    end)
  end

  defp format_statics_list(statics), do: to_string(statics)

  defp create_system_name_link(system, display_name) do
    has_numeric_id =
      is_integer(system.solar_system_id) ||
        (is_binary(system.solar_system_id) && parse_system_id(system.solar_system_id) != nil)

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

  # Ensure a value is safely converted to a string
  defp safe_to_string(nil), do: ""
  defp safe_to_string(val) when is_binary(val), do: val
  defp safe_to_string(val), do: inspect(val)

  defp build_rich_system_notification_fields(
         system,
         is_wormhole,
         formatted_statics,
         system_name_with_link
       ) do
    fields = [%{name: "System", value: safe_to_string(system_name_with_link), inline: true}]
    fields = add_shattered_field(fields, is_wormhole, Map.get(system, :is_shattered))
    fields = add_statics_field(fields, is_wormhole, formatted_statics)
    fields = add_region_field(fields, Map.get(system, :region_name))
    fields = add_effect_field(fields, is_wormhole, Map.get(system, :effect_name))
    fields = add_zkill_system_kills(fields, Map.get(system, :solar_system_id))

    # Ensure all field values are valid strings
    Enum.map(fields, fn field ->
      %{field | value: safe_to_string(field.value)}
    end)
  end

  defp add_shattered_field(fields, true, true),
    do: fields ++ [%{name: "Shattered", value: "Yes", inline: true}]

  defp add_shattered_field(fields, _, _), do: fields

  defp add_statics_field(fields, true, statics) when statics != "N/A",
    do: fields ++ [%{name: "Statics", value: statics, inline: true}]

  defp add_statics_field(fields, _, _), do: fields

  defp add_region_field(fields, region_name) when not is_nil(region_name),
    do: fields ++ [%{name: "Region", value: safe_to_string(region_name), inline: true}]

  defp add_region_field(fields, _), do: fields

  defp add_effect_field(fields, true, effect_name) when not is_nil(effect_name),
    do: fields ++ [%{name: "Effect", value: safe_to_string(effect_name), inline: true}]

  defp add_effect_field(fields, _, _), do: fields

  defp add_zkill_system_kills(fields, system_id) do
    case parse_system_id(system_id) do
      nil -> fields
      system_id_int -> add_kills_field(fields, system_id_int)
    end
  end

  defp add_kills_field(fields, system_id) do
    try do
      case Enrichment.recent_kills_for_system(system_id, 3) do
        kills when is_binary(kills) and kills != "" ->
          fields ++ [%{name: "Recent Kills", value: kills, inline: false}]

        _ ->
          fields
      end
    rescue
      e ->
        Logger.processor_warn("Error adding kills field",
          error: Exception.message(e),
          system_id: system_id
        )

        fields
    end
  end

  defp parse_system_id(id) when is_binary(id) do
    WandererNotifier.Config.Utils.parse_int(id, nil)
  end

  defp parse_system_id(id) when is_integer(id), do: id
  defp parse_system_id(_), do: nil
end
