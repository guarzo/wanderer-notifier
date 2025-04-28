defmodule WandererNotifier.Notifiers.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord using the Nostrum client.
  """
  require Logger
  alias WandererNotifier.ESI.Service, as: ESI
  alias WandererNotifier.Config.Application
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifications.Determiner.System, as: SystemDeterminer
  alias WandererNotifier.Notifiers.Discord.ComponentBuilder
  alias WandererNotifier.Notifiers.Discord.FeatureFlags
  alias WandererNotifier.Notifiers.Discord.NeoClient
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Killmail.Killmail

  @behaviour WandererNotifier.Notifiers.Behaviour

  # Default embed colors
  @default_embed_color 0x3498DB

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  defp env, do: Application.get_env()

  # Helper function to handle test mode logging and response
  defp handle_test_mode(log_message) do
    # Always log in test mode for test assertions
    Logger.info(log_message)
    :ok
  end

  # -- MESSAGE SENDING --

  @impl WandererNotifier.Notifiers.Behaviour
  def send_message(message, _feature \\ nil) do
    AppLogger.processor_info("Discord message requested")

    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{message}")
    else
      AppLogger.processor_info("Sending Discord message",
        client: "Nostrum",
        message_length: String.length(message)
      )

      NeoClient.send_message(message)
    end
  end

  @impl WandererNotifier.Notifiers.Behaviour
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color, _feature \\ nil) do
    AppLogger.processor_info("Discord embed requested",
      title: title,
      url: url || "nil"
    )

    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{title} - #{description}")
    else
      # Build embed payload
      embed = build_embed_payload(title, description, url, color)

      # For Nostrum, we just need the embed object from the payload
      discord_embed = embed["embeds"] |> List.first()
      NeoClient.send_embed(discord_embed)
    end
  end

  defp build_embed_payload(title, description, url, color) do
    embed = %{
      "title" => title,
      "description" => description,
      "color" => color
    }

    # Add URL if provided
    embed =
      if url do
        Map.put(embed, "url", url)
      else
        embed
      end

    # Return final payload with embed
    %{"embeds" => [embed]}
  end

  @impl WandererNotifier.Notifiers.Behaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil, _feature \\ nil) do
    AppLogger.processor_info("Sending file to Discord",
      filename: filename,
      title: title
    )

    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{filename} - #{title || "No title"}")
    else
      NeoClient.send_file(filename, file_data, title, description)
    end
  end

  @impl WandererNotifier.Notifiers.Behaviour
  def send_image_embed(
        title,
        description,
        image_url,
        color \\ @default_embed_color,
        _feature \\ nil
      ) do
    AppLogger.processor_info("Sending image embed to Discord",
      title: title,
      image_url: image_url || "nil"
    )

    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{title} - #{description} with image: #{image_url}")
    else
      embed = %{
        "title" => title,
        "description" => description,
        "color" => color,
        "image" => %{
          "url" => image_url
        }
      }

      AppLogger.processor_info("Discord image embed payload built, sending to Discord API")
      NeoClient.send_embed(embed)
    end
  end

  @impl WandererNotifier.Notifiers.Behaviour
  def send_enriched_kill_embed(killmail, kill_id) when is_struct(killmail, Killmail) do
    AppLogger.processor_debug("Preparing to format killmail for Discord", kill_id: kill_id)

    # Ensure the killmail has a system name if system_id is present
    enriched_killmail = enrich_with_system_name(killmail)

    # Format the kill notification
    formatted_embed = StructuredFormatter.format_kill_notification(enriched_killmail)

    # Only add components if the feature flag is enabled
    enhanced_notification =
      if FeatureFlags.components_enabled?() do
        # Add interactive components based on the killmail
        components = [ComponentBuilder.kill_action_row(kill_id)]

        AppLogger.processor_debug("Adding interactive components to kill notification",
          kill_id: kill_id
        )

        # Add components to the notification
        Map.put(formatted_embed, :components, components)
      else
        # Use standard format without components
        AppLogger.processor_debug(
          "Using standard embed format for kill notification (components disabled)",
          kill_id: kill_id
        )

        formatted_embed
      end

    send_to_discord(enhanced_notification, "kill")
  end

  @impl WandererNotifier.Notifiers.Behaviour
  def send_kill_notification(kill_data) do
    # Log the received kill data for debugging
    AppLogger.processor_debug("Kill notification received",
      data_type: typeof(kill_data)
    )

    # Ensure we have a Killmail struct
    killmail =
      if is_struct(kill_data, Killmail),
        do: kill_data,
        else: struct(Killmail, Map.from_struct(kill_data))

    # Delegate to the enriched killmail notification function
    send_killmail_notification(killmail)
  end

  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_tracked_character_notification(character)
      when is_struct(character, WandererNotifier.Character.Character) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: Character ID #{character.character_id}")
    else
      # Extract character ID for deduplication check
      character_id = character.character_id

      # Check if this character should trigger a notification
      if CharacterDeterminer.should_notify?(character_id, character) do
        # This is not a duplicate, proceed with notification
        AppLogger.processor_info("Processing new character notification",
          character_name: character.name,
          character_id: character.character_id
        )

        # Create notification with StructuredFormatter
        generic_notification = StructuredFormatter.format_character_notification(character)
        send_to_discord(generic_notification, :character_tracking)

        # Record stats
        Stats.increment(:characters)
      else
        # This is a duplicate or doesn't meet criteria, skip notification
        AppLogger.processor_info("Skipping character notification",
          character_name: character.name,
          character_id: character.character_id
        )

        :ok
      end
    end
  end

  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_system_notification(system) do
    # Log system details before processing to diagnose cache issues
    AppLogger.processor_info(
      "[NEW_SYSTEM_NOTIFICATION] Processing system notification request",
      system_type: typeof(system),
      system_preview: inspect(system, limit: 200)
    )

    if env() == :test do
      # Get system ID safely regardless of structure
      system_id = extract_system_id(system)
      handle_test_mode("DISCORD MOCK: System ID #{system_id}")
    else
      # Extract system data safely with fallbacks
      system_id = extract_system_id(system)
      system_name = extract_system_name(system)

      # Log extracted details for debugging
      AppLogger.processor_info(
        "[NEW_SYSTEM_NOTIFICATION] Extracted system details",
        system_id: system_id,
        system_name: system_name
      )

      # Convert to MapSystem struct if needed for formatter
      map_system = ensure_map_system(system)

      # Check if this system should trigger a notification
      if SystemDeterminer.should_notify?(system_id, map_system) do
        # This is not a duplicate, proceed with notification
        AppLogger.processor_info("Processing new system notification",
          system_id: system_id,
          system_name: system_name
        )

        # Create notification with StructuredFormatter
        AppLogger.processor_info("Using StructuredFormatter for system notification")
        generic_notification = StructuredFormatter.format_system_notification(map_system)

        # Send using the standard send_to_discord helper
        send_to_discord(generic_notification, :system_tracking)

        # Record stats
        Stats.increment(:systems)

        :ok
      else
        # This is a duplicate or doesn't meet criteria, skip notification
        AppLogger.processor_info("Skipping system notification",
          system_id: system_id,
          system_name: system_name
        )

        :ok
      end
    end
  end

  def send_notification(type, data) do
    case type do
      :send_discord_embed ->
        [embed] = data
        NeoClient.send_embed(embed)

      :send_discord_embed_to_channel ->
        [channel_id, embed] = data
        NeoClient.send_embed(embed, channel_id)

      :send_message ->
        [message] = data
        send_message(message)

      _ ->
        AppLogger.processor_warn("Unknown notification type", type: type)
        {:error, :unknown_notification_type}
    end
  end

  # -- PRIVATE HELPERS --

  # Helper to determine type of value for logging
  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_integer(term), do: "integer"
  defp typeof(term) when is_float(term), do: "float"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(term) when is_function(term), do: "function"
  defp typeof(term) when is_pid(term), do: "pid"
  defp typeof(term) when is_reference(term), do: "reference"
  defp typeof(term) when is_struct(term), do: "struct:#{term.__struct__}"
  defp typeof(_), do: "unknown"

  # Send formatted notification to Discord
  defp send_to_discord(formatted_notification, feature) do
    # Skip actual sending in test mode
    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{inspect(feature)}")
    else
      # Convert to Discord format
      discord_embed = StructuredFormatter.to_discord_format(formatted_notification)

      # Check if components are available
      components = Map.get(formatted_notification, :components, [])
      use_components = components != [] && FeatureFlags.components_enabled?()

      if use_components do
        # If components are enabled, use enhanced format
        AppLogger.processor_info("Using Discord components for #{feature} notification")
        NeoClient.send_message_with_components(discord_embed, components)
      else
        # Otherwise use standard embed
        AppLogger.processor_info("Using standard embeds for #{feature} notification")
        NeoClient.send_embed(discord_embed)
      end
    end
  end

  # Ensure the killmail has a system name if missing
  defp enrich_with_system_name(%Killmail{} = killmail) do
    # Get system_id from the esi_data
    system_id = get_system_id_from_killmail(killmail)

    # Check if we need to get the system name
    if system_id do
      # Get system name using the same approach as in kill_processor
      system_name = get_system_name(system_id)

      AppLogger.processor_debug("Enriching killmail with system name",
        system_id: system_id,
        system_name: system_name
      )

      # Add system name to esi_data
      new_esi_data = Map.put(killmail.esi_data || %{}, "solar_system_name", system_name)
      %{killmail | esi_data: new_esi_data}
    else
      killmail
    end
  end

  # Get system ID from killmail
  defp get_system_id_from_killmail(%Killmail{} = killmail) do
    if killmail.esi_data do
      Map.get(killmail.esi_data, "solar_system_id")
    else
      nil
    end
  end

  # Helper function to get system name with caching
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    case ESI.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      {:error, :not_found} -> "Unknown-#{system_id}"
      _ -> nil
    end
  end

  # Send killmail notification
  defp send_killmail_notification(killmail) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: Killmail ID #{killmail.killmail_id}")
    else
      # Create notification with StructuredFormatter
      AppLogger.processor_info("Formatting killmail notification")
      notification = StructuredFormatter.format_kill_notification(killmail)

      # Send notification
      send_to_discord(notification, :killmail)
    end
  end

  # Helper to convert to MapSystem struct if needed
  defp ensure_map_system(system) do
    if is_struct(system, MapSystem) do
      # Already a MapSystem, just return it
      system
    else
      # Try to create MapSystem from a map or other structure
      try do
        # Check if we need to convert it
        if is_map(system) do
          MapSystem.new(system)
        else
          # Log error and return original
          AppLogger.processor_error(
            "[Discord.Notifier] Cannot convert to MapSystem: #{inspect(system)}"
          )

          system
        end
      rescue
        e ->
          # Log error and return original on conversion failure
          AppLogger.processor_error(
            "[Discord.Notifier] Failed to convert to MapSystem: #{Exception.message(e)}"
          )

          system
      end
    end
  end

  # Extract system ID from killmail
  defp extract_system_id(killmail) do
    cond do
      is_binary(killmail) ->
        killmail

      is_map(killmail) ->
        system_id =
          Map.get(killmail, "solar_system_id") ||
            Map.get(killmail, "esi_data", %{})["solar_system_id"]

        system_name =
          Map.get(killmail, "solar_system_name") ||
            Map.get(killmail, "esi_data", %{})["solar_system_name"]

        # Return system_id, but log it with the name if available
        AppLogger.processor_debug(
          "Extracted system",
          %{
            system_id: system_id,
            system_name: system_name
          }
        )

        system_id

      true ->
        nil
    end
  end

  # Extract system name from system data
  defp extract_system_name(system) do
    extract_field_value(system, [:name, "name"], "Unknown System")
  end

  # Helper to extract a field with a default value
  defp extract_field_value(system, field_names, default) do
    Enum.find_value(field_names, default, fn field ->
      cond do
        is_struct(system) && Map.has_key?(system, field) -> Map.get(system, field)
        is_map(system) && Map.has_key?(system, field) -> Map.get(system, field)
        true -> nil
      end
    end)
  end
end
