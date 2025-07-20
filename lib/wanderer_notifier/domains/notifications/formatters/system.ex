defmodule WandererNotifier.Domains.Notifications.Formatters.System do
  @moduledoc """
  System notification formatting utilities for Discord notifications.
  Provides rich formatting for system tracking events.
  """
  require Logger
  alias WandererNotifier.Domains.Killmail.Enrichment
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Domains.SystemTracking.System
  alias WandererNotifier.Domains.Notifications.Formatters.Base

  @doc """
  Creates a standard formatted system notification from a MapSystem struct.
  """
  def format_system_notification(%System{} = system) do
    Base.with_error_handling(__MODULE__, "format system notification", system, fn ->
      validate_system_fields!(system)

      is_wormhole = System.wormhole?(system)
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

      Base.build_notification(%{
        type: :system_notification,
        title: title,
        description: description,
        color: color,
        thumbnail: Base.build_thumbnail(icon_url),
        fields: fields,
        footer: Base.build_footer("System ID: #{system.solar_system_id}")
      })
    end)
  end

  defp validate_system_fields!(system) do
    cond do
      is_nil(system.solar_system_id) ->
        raise ArgumentError, "System must have a solar_system_id"

      is_nil(system.name) ->
        raise ArgumentError, "System must have a name"

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
    if is_wormhole do
      Base.resolve_color(:wormhole)
    else
      type_description
      |> Base.determine_security_color()
      |> Base.resolve_color()
    end
  end

  defp determine_system_icon(is_wormhole, type_description, _sun_type_id) do
    if is_wormhole do
      Base.get_system_icon(:wormhole)
    else
      Base.get_system_icon(type_description)
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
        inspect(other, limit: 100, printable_limit: 100)
    end)
  end

  defp format_statics_list(statics), do: to_string(statics)

  defp create_system_name_link(system, display_name) do
    has_numeric_id =
      is_integer(system.solar_system_id) ||
        (is_binary(system.solar_system_id) && parse_system_id(system.solar_system_id) != nil)

    if has_numeric_id do
      system_id = parse_system_id(system.solar_system_id)

      has_temp_and_original =
        Map.get(system, :temporary_name) && Map.get(system, :temporary_name) != "" &&
          Map.get(system, :original_name) && Map.get(system, :original_name) != ""

      if has_temp_and_original do
        link_text = "#{system.temporary_name} (#{system.original_name})"
        Base.create_system_link(link_text, system_id)
      else
        Base.create_system_link(system.name, system_id)
      end
    else
      display_name
    end
  end

  defp build_rich_system_notification_fields(
         system,
         is_wormhole,
         formatted_statics,
         system_name_with_link
       ) do
    fields = [Base.build_field("System", system_name_with_link, true)]
    fields = add_shattered_field(fields, is_wormhole, Map.get(system, :is_shattered))
    fields = add_statics_field(fields, is_wormhole, formatted_statics)
    fields = add_region_field(fields, Map.get(system, :region_name))
    fields = add_effect_field(fields, is_wormhole, Map.get(system, :effect_name))
    fields = add_zkill_system_kills(fields, Map.get(system, :solar_system_id))

    fields
  end

  defp add_shattered_field(fields, true, true) do
    fields ++ [Base.build_field("Shattered", "Yes", true)]
  end

  defp add_shattered_field(fields, _, _), do: fields

  defp add_statics_field(fields, true, statics) when statics != "N/A" do
    fields ++ [Base.build_field("Statics", statics, true)]
  end

  defp add_statics_field(fields, _, _), do: fields

  defp add_region_field(fields, region_name) when is_binary(region_name) do
    region_link = Base.create_link(region_name, Base.dotlan_region_url(region_name))
    fields ++ [Base.build_field("Region", region_link, true)]
  end

  defp add_region_field(fields, _), do: fields

  defp add_effect_field(fields, true, effect_name) when is_binary(effect_name) do
    fields ++ [Base.build_field("Effect", effect_name, true)]
  end

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
          fields ++ [Base.build_field("Recent Kills", kills, false)]

        _ ->
          fields
      end
    rescue
      e ->
        AppLogger.processor_warn("Error adding kills field",
          error: Exception.message(e),
          system_id: system_id
        )

        fields
    end
  end

  # parse_system_id moved to WandererNotifier.Shared.Config.Utils
  defp parse_system_id(id), do: WandererNotifier.Shared.Config.Utils.parse_system_id(id)
end
