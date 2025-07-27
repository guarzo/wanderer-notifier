defmodule WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord using the Nostrum client.
  """
  require Logger
  alias WandererNotifier.Application.Services.Stats
  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Killmail.Enrichment
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.ComponentBuilder
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.FeatureFlags
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.NeoClient
  alias WandererNotifier.Domains.Notifications.Formatters.System, as: SystemFormatter
  alias WandererNotifier.Domains.Notifications.Formatters.Killmail, as: KillmailFormatter
  alias WandererNotifier.Domains.Notifications.Formatters.Character, as: CharacterFormatter
  alias WandererNotifier.Domains.Notifications.Formatters.Common, as: CommonFormatter
  alias WandererNotifier.Domains.Notifications.Formatters.PlainText, as: PlainTextFormatter
  alias WandererNotifier.Domains.Notifications.LicenseLimiter
  alias WandererNotifier.Shared.Config
  # Default embed colors
  @default_embed_color 0x3498DB

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  defp env, do: Application.get_env(:wanderer_notifier, :env)

  # Helper function to handle test mode logging and response
  defp handle_test_mode(log_message) do
    # Always log in test mode for test assertions
    Logger.info(log_message)
    :ok
  end

  # -- MESSAGE SENDING --

  def send_message(message, _feature \\ nil) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{inspect(message)}")
    else
      case message do
        msg when is_binary(msg) ->
          NeoClient.send_message(msg)

        embed when is_map(embed) ->
          NeoClient.send_embed(embed)

        _ ->
          AppLogger.processor_error("Unknown message type for Discord notification",
            type: inspect(message)
          )

          {:error, :invalid_message_type}
      end
    end
  end

  def send_embed(title, description, url \\ nil, color \\ @default_embed_color, _feature \\ nil) do
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

  def send_file(filename, file_data, title \\ nil, description \\ nil, _feature \\ nil) do
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
        color \\ @default_embed_color,
        _feature \\ nil
      ) do
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

  def send_enriched_kill_embed(killmail, kill_id) when is_struct(killmail, Killmail) do
    # Ensure the killmail has a system name if system_id is present
    enriched_killmail = enrich_with_system_name(killmail)

    # Format the kill notification
    formatted_embed = KillmailFormatter.format_kill_notification(enriched_killmail)

    # Get features as a map
    features = Map.new(Config.features())

    # Only add components if the feature flag is enabled
    enhanced_notification =
      if Map.get(features, :discord_components, false) do
        # Add interactive components based on the killmail
        components = [ComponentBuilder.kill_action_row(kill_id)]

        # Add components to the notification
        Map.put(formatted_embed, :components, components)
      else
        # Use standard format without components
        formatted_embed
      end

    send_to_discord(enhanced_notification, "kill")
  end

  def send_kill_notification(kill_data) do
    try do
      if LicenseLimiter.should_send_rich?(:killmail) do
        # Ensure we have a Killmail struct
        killmail =
          if is_struct(kill_data, Killmail),
            do: kill_data,
            else: struct(Killmail, Map.from_struct(kill_data))

        send_killmail_notification(killmail)
        LicenseLimiter.increment(:killmail)
      else
        # Get the default channel ID
        channel_id = Config.discord_channel_id()
        send_simple_kill_notification(kill_data, channel_id)
      end
    rescue
      e ->
        AppLogger.processor_error("[KILL_NOTIFICATION] Exception in send_kill_notification",
          error: Exception.message(e),
          kill_data: inspect(kill_data),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, e}
    end
  end

  @doc """
  Sends a kill notification to a specific Discord channel.
  """
  def send_kill_notification_to_channel(kill_data, channel_id) do
    case send_rich_kill_notification(kill_data, channel_id) do
      :ok ->
        :ok

      {:error, reason} ->
        AppLogger.api_error("Failed to send kill notification",
          channel_id: channel_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  rescue
    e ->
      AppLogger.api_error("Exception in send_kill_notification_to_channel",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        channel_id: channel_id
      )

      {:error, {:exception, Exception.message(e)}}
  end

  # Send a rich kill notification with embed
  defp send_rich_kill_notification(kill_data, channel_id) do
    # Use the existing Killmail struct
    killmail = kill_data

    # Format the notification
    notification = KillmailFormatter.format_kill_notification(killmail)

    # Send the notification
    case NeoClient.send_embed(notification, channel_id) do
      :ok ->
        :ok

      {:error, reason} ->
        AppLogger.api_error("Failed to send rich kill notification",
          channel_id: channel_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  rescue
    e ->
      AppLogger.api_error("Exception in send_rich_kill_notification",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        channel_id: channel_id
      )

      {:error, {:exception, Exception.message(e)}}
  end

  # Send a simple text-based kill notification
  defp send_simple_kill_notification(kill_data, channel_id) do
    message = PlainTextFormatter.format_plain_text(kill_data)
    NeoClient.send_message(message, channel_id)
  end

  def send_new_tracked_character_notification(character)
      when is_struct(character, WandererNotifier.Domains.Tracking.Entities.Character) do
    try do
      if LicenseLimiter.should_send_rich?(:character) do
        generic_notification = CharacterFormatter.format_character_notification(character)
        send_to_discord(generic_notification, :character_tracking)
        LicenseLimiter.increment(:character)
      else
        message = PlainTextFormatter.format_plain_text(character)
        NeoClient.send_message(message)
      end

      Stats.increment(:characters)

      # Log successful character notification
      character_name = character.name || "Unknown Character"
      character_id = character.character_id || "Unknown ID"
      AppLogger.processor_info("👤 ✅ Character #{character_name} (#{character_id}) notified")
    rescue
      e ->
        Logger.error(
          "[Discord.Notifier] Exception in send_new_tracked_character_notification/1: #{Exception.message(e)}\nStacktrace:\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        {:error, e}
    end
  end

  def send_new_system_notification(system) do
    try do
      if LicenseLimiter.should_send_rich?(:system) do
        enriched_system = system
        generic_notification = SystemFormatter.format_system_notification(enriched_system)
        send_to_discord(generic_notification, :system_tracking)
        LicenseLimiter.increment(:system)
      else
        message = PlainTextFormatter.format_plain_text(system)
        NeoClient.send_message(message)
      end

      Stats.increment(:systems)

      # Log successful system notification
      system_name = system.name || "Unknown System"
      system_id = system.solar_system_id || "Unknown ID"
      AppLogger.processor_info("🗺️ ✅ System #{system_name} (#{system_id}) notified")

      {:ok, :sent}
    rescue
      e ->
        AppLogger.processor_error(
          "[NEW_SYSTEM_NOTIFICATION] Exception in send_new_system_notification (detailed)",
          error: Exception.message(e),
          system: inspect(system, pretty: true, limit: 1000),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, e}
    end
  end

  def send_notification(type, data) do
    case type do
      :send_discord_embed ->
        [embed] = data
        NeoClient.send_embed(embed, nil)
        {:ok, :sent}

      :send_discord_embed_to_channel ->
        [channel_id, embed] = data
        NeoClient.send_embed(embed, channel_id)
        {:ok, :sent}

      :send_message ->
        [message] = data
        send_message(message)
        {:ok, :sent}

      :send_new_tracked_character_notification ->
        [character_struct] = data
        send_new_tracked_character_notification(character_struct)

      _ ->
        AppLogger.processor_warn("Unknown notification type", type: type)
        {:error, :unknown_notification_type}
    end
  end

  # -- PRIVATE HELPERS --

  # Send formatted notification to Discord
  defp send_to_discord(formatted_notification, feature) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{inspect(feature)}")
      {:ok, :sent}
    else
      send_to_discord_production(formatted_notification, feature)
    end
  end

  defp send_to_discord_production(formatted_notification, feature) do
    components = Map.get(formatted_notification, :components, [])
    use_components = components != [] && FeatureFlags.components_enabled?()
    channel_id = determine_channel_id(feature)

    discord_embed = prepare_discord_embed(formatted_notification, feature)

    send_discord_message(discord_embed, components, use_components, channel_id)
    {:ok, :sent}
  end

  defp determine_channel_id(feature) do
    case feature do
      "kill" -> Config.discord_channel_id()
      :killmail -> Config.discord_channel_id()
      :system_tracking -> Config.discord_system_channel_id() || Config.discord_channel_id()
      :character_tracking -> Config.discord_character_channel_id() || Config.discord_channel_id()
      _ -> Config.discord_channel_id()
    end
  end

  defp prepare_discord_embed(formatted_notification, feature) do
    if feature in ["kill", :killmail] do
      extract_killmail_embed_fields(formatted_notification)
    else
      CommonFormatter.to_discord_format(formatted_notification)
    end
  end

  defp extract_killmail_embed_fields(formatted_notification) do
    %{
      title: formatted_notification.title,
      description: formatted_notification.description,
      color: formatted_notification.color,
      url: formatted_notification.url,
      timestamp: formatted_notification.timestamp,
      footer: formatted_notification.footer,
      thumbnail: formatted_notification.thumbnail,
      author: formatted_notification.author,
      fields: formatted_notification.fields,
      image: formatted_notification.image
    }
  end

  defp send_discord_message(discord_embed, components, use_components, channel_id) do
    if use_components do
      NeoClient.send_message_with_components(discord_embed, components, channel_id)
    else
      NeoClient.send_embed(discord_embed, channel_id)
    end
  end

  # Ensure the killmail has a system name if missing
  defp enrich_with_system_name(%Killmail{} = killmail) do
    # Get system_id from the esi_data
    system_id = get_system_id_from_killmail(killmail)

    # Check if we have a valid system_id (must be an integer)
    case system_id do
      id when is_integer(id) ->
        # Get system name using the same approach as in kill_processor
        system_name = get_system_name(id)

        # Add system name to esi_data
        new_esi_data = Map.put(killmail.esi_data || %{}, "solar_system_name", system_name)
        %{killmail | esi_data: new_esi_data}

      _ ->
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
  defp get_system_name(system_id) when is_integer(system_id) do
    # Enrichment.get_system_name always returns a string, never nil
    Enrichment.get_system_name(system_id)
  end

  # Send killmail notification
  defp send_killmail_notification(killmail) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: Killmail ID #{killmail.killmail_id}")
    else
      notification = KillmailFormatter.format_kill_notification(killmail)

      # Send notification
      send_to_discord(notification, :killmail)
    end
  end
end
