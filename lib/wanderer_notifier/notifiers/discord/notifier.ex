defmodule WandererNotifier.Notifiers.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord using the Nostrum client.
  """
  require Logger
  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Discord.ComponentBuilder
  alias WandererNotifier.Notifiers.Discord.FeatureFlags
  alias WandererNotifier.Notifiers.Discord.NeoClient
  alias WandererNotifier.Notifications.Formatters.System, as: SystemFormatter
  alias WandererNotifier.Notifications.Formatters.Killmail, as: KillmailFormatter
  alias WandererNotifier.Notifications.Formatters.Character, as: CharacterFormatter
  alias WandererNotifier.Notifications.Formatters.Common, as: CommonFormatter
  alias WandererNotifier.Notifications.Formatters.PlainText, as: PlainTextFormatter
  alias WandererNotifier.Config
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
    AppLogger.processor_debug("Preparing to format killmail for Discord", kill_id: kill_id)

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
    try do
      if WandererNotifier.Notifications.LicenseLimiter.should_send_rich?(:killmail) do
        # Log the received kill data for debugging
        AppLogger.processor_debug("Kill notification received",
          data_type: typeof(kill_data)
        )

        # Ensure we have a Killmail struct
        killmail =
          if is_struct(kill_data, Killmail),
            do: kill_data,
            else: struct(Killmail, Map.from_struct(kill_data))

        send_killmail_notification(killmail)
        WandererNotifier.Notifications.LicenseLimiter.increment(:killmail)
      else
        message = PlainTextFormatter.plain_killmail_notification(kill_data)
        NeoClient.send_message(message)
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
    if WandererNotifier.Config.rich_notifications_enabled?() do
      # Send rich notification
      send_rich_kill_notification(kill_data, channel_id)
    else
      # Send simple notification
      send_simple_kill_notification(kill_data, channel_id)
    end

    # Handle feature flags
    if WandererNotifier.Config.feature_flags_enabled?() do
      # Additional feature flag handling
      handle_feature_flags(kill_data, channel_id)
    end
  end

  # Send a rich kill notification with embed
  defp send_rich_kill_notification(kill_data, channel_id) do
    killmail = ensure_killmail_struct(kill_data)
    notification = KillmailFormatter.format_kill_notification(killmail)
    NeoClient.send_embed(notification, channel_id)
  end

  # Send a simple text-based kill notification
  defp send_simple_kill_notification(kill_data, channel_id) do
    message = PlainTextFormatter.plain_killmail_notification(kill_data)
    NeoClient.send_message(message, channel_id)
  end

  # Handle feature flags for kill notifications
  defp handle_feature_flags(kill_data, channel_id) do
    if FeatureFlags.components_enabled?() do
      killmail = ensure_killmail_struct(kill_data)
      components = [ComponentBuilder.kill_action_row(killmail.killmail_id)]
      NeoClient.send_message_with_components(killmail.killmail_id, components, channel_id)
    end
  end

  def send_new_tracked_character_notification(character)
      when is_struct(character, WandererNotifier.Map.MapCharacter) do
    try do
      if WandererNotifier.Notifications.LicenseLimiter.should_send_rich?(:character) do
        generic_notification = CharacterFormatter.format_character_notification(character)
        send_to_discord(generic_notification, :character_tracking)
        WandererNotifier.Notifications.LicenseLimiter.increment(:character)
      else
        message = PlainTextFormatter.plain_character_notification(character)
        NeoClient.send_message(message)
      end

      Stats.increment(:characters)
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
      if WandererNotifier.Notifications.LicenseLimiter.should_send_rich?(:system) do
        enriched_system = system
        generic_notification = SystemFormatter.format_system_notification(enriched_system)
        send_to_discord(generic_notification, :system_tracking)
        WandererNotifier.Notifications.LicenseLimiter.increment(:system)
      else
        message = PlainTextFormatter.plain_system_notification(system)
        NeoClient.send_message(message)
      end

      Stats.increment(:systems)
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
    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{inspect(feature)}")
      {:ok, :sent}
    else
      discord_embed = CommonFormatter.to_discord_format(formatted_notification)
      components = Map.get(formatted_notification, :components, [])
      use_components = components != [] && FeatureFlags.components_enabled?()
      # Use kill_channel_id for kill notifications
      channel_id =
        if feature in ["kill", :killmail],
          do: WandererNotifier.Config.discord_kill_channel_id(),
          else: nil

      if use_components do
        NeoClient.send_message_with_components(discord_embed, components, channel_id)
      else
        NeoClient.send_embed(discord_embed, channel_id)
      end

      {:ok, :sent}
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
    case ESIService.get_system_info(system_id) do
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
      notification = KillmailFormatter.format_kill_notification(killmail)

      # Send notification
      send_to_discord(notification, :killmail)
    end
  end

  # Ensure the input is a Killmail struct
  defp ensure_killmail_struct(kill_data) do
    if is_struct(kill_data, Killmail) do
      kill_data
    else
      struct(Killmail, Map.from_struct(kill_data))
    end
  end
end
