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
  alias WandererNotifier.Notifiers.NeoClient
  alias WandererNotifier.Notifiers.Formatters.Structured, as: StructuredFormatter
  alias WandererNotifier.Killmail.Killmail

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

  def send_embed(title, description, url \\ nil, color \\ nil, _feature \\ nil) do
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
      "color" => color || Constants.colors().default
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

  def send_image_embed(
        title,
        description,
        image_url,
        color \\ nil,
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
        "color" => color || Constants.colors().default,
        "image" => %{
          "url" => image_url
        }
      }

      AppLogger.processor_info("Discord image embed payload built, sending to Discord API")
      NeoClient.send_embed(embed)
    end
  end

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
        Stats.increment(:character_notifications)

        :ok
      else
        # Skip notification for duplicate character
        AppLogger.processor_debug("Skipping duplicate character notification",
          character_name: character.name,
          character_id: character.character_id
        )

        {:ok, :duplicate}
      end
    end
  end

  def send_new_tracked_system_notification(system) when is_struct(system, MapSystem) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: System ID #{system.system_id}")
    else
      # Check if this system should trigger a notification
      if SystemDeterminer.should_notify?(system) do
        # This is not a duplicate, proceed with notification
        AppLogger.processor_info("Processing new system notification",
          system_name: system.name,
          system_id: system.system_id
        )

        # Create notification with StructuredFormatter
        generic_notification = StructuredFormatter.format_system_notification(system)
        send_to_discord(generic_notification, :system_tracking)

        # Record stats
        Stats.increment(:system_notifications)

        :ok
      else
        # Skip notification for duplicate system
        AppLogger.processor_debug("Skipping duplicate system notification",
          system_name: system.name,
          system_id: system.system_id
        )

        {:ok, :duplicate}
      end
    end
  end

  # -- PRIVATE HELPER FUNCTIONS --

  defp send_to_discord(notification, feature) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{inspect(notification)}")
    else
      case NeoClient.send_embed(notification) do
        :ok ->
          AppLogger.processor_info("Discord notification sent successfully",
            feature: feature
          )

          :ok

        {:error, reason} ->
          AppLogger.processor_error("Failed to send Discord notification",
            feature: feature,
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  end

  defp enrich_with_system_name(killmail) do
    case get_in(killmail, ["solar_system", "system_id"]) do
      nil ->
        killmail

      system_id ->
        case ESI.get_system_name(system_id) do
          {:ok, system_name} ->
            put_in(killmail, ["solar_system", "name"], system_name)

          _ ->
            killmail
        end
    end
  end

  defp typeof(term) when is_nil(term), do: "nil"
  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_number(term), do: "number"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(_term), do: "unknown"
end
