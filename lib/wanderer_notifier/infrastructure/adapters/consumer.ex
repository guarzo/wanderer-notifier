defmodule WandererNotifier.Infrastructure.Adapters.Discord.Consumer do
  @moduledoc """
  Discord event consumer for handling slash command interactions.

  This consumer processes Discord events, specifically INTERACTION_CREATE events
  for the `/notifier` command group. It logs commands and provides appropriate
  responses to users.

  The consumer also handles command registration on startup to ensure slash
  commands are available to users.
  """

  use Nostrum.Consumer
  require Logger

  alias Nostrum.Api
  alias WandererNotifier.CommandLog
  alias WandererNotifier.Infrastructure.Adapters.Discord.CommandRegistrar
  alias WandererNotifier.PersistentValues
  alias WandererNotifier.Shared.Config

  @impl true
  def handle_event({:READY, _data, _ws_state}) do
    Logger.info("Discord consumer ready, registering slash commands")

    case CommandRegistrar.register() do
      :ok ->
        Logger.info("Slash commands registered successfully")

      {:error, :missing_application_id} ->
        Logger.info(
          "Discord slash commands not registered: DISCORD_APPLICATION_ID not configured. " <>
            "Bot will work for notifications but slash commands won't be available."
        )

      {:error, reason} ->
        Logger.error("Failed to register slash commands", error: inspect(reason))
    end

    :noop
  end

  @impl true
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    case CommandRegistrar.extract_command_details(interaction) do
      {:ok, command} ->
        handle_notifier_command(command, interaction)

      {:error, :invalid_interaction} ->
        Logger.warning("Received invalid interaction",
          interaction_id: interaction.id,
          data: inspect(interaction.data)
        )
    end

    :noop
  end

  @impl true
  def handle_event({:GUILD_CREATE, guild, _ws_state}) do
    Logger.info("Bot added to guild: #{guild.name} (#{guild.id})")
    :noop
  end

  @impl true
  def handle_event({:MESSAGE_CREATE, %{author: %{bot: true}}, _ws_state}), do: :noop

  @impl true
  def handle_event(_event), do: :noop

  # Private Functions

  # Handles the `/notifier` command based on subcommand type
  defp handle_notifier_command(command, interaction) do
    # Log the command interaction
    log_command(command)

    case command.type do
      "system" ->
        handle_system_command(command, interaction)

      "status" ->
        handle_status_command(command, interaction)

      unknown ->
        Logger.warning("Unknown notifier subcommand",
          type: unknown,
          user_id: command.user_id
        )

        respond_to_interaction(interaction, "❌ Unknown command type: #{unknown}")
    end
  end

  # Handles `/notifier system` commands
  defp handle_system_command(command, interaction) do
    system_name = command.options["system_name"]
    action = command.options["action"] || "track"

    case action do
      "add_priority" ->
        add_priority_system(system_name, interaction)

      "remove_priority" ->
        remove_priority_system(system_name, interaction)

      "track" ->
        track_system(system_name, interaction)

      "untrack" ->
        untrack_system(system_name, interaction)

      unknown_action ->
        respond_to_interaction(interaction, "❌ Unknown action: #{unknown_action}")
    end
  end

  # Handles `/notifier status` commands
  defp handle_status_command(_command, interaction) do
    status_message = build_status_message()
    respond_to_interaction(interaction, status_message)
  end

  # System command handlers

  defp add_priority_system(system_name, interaction) do
    # For now, just track the system name as a string
    # In a full implementation, you'd resolve this to a system ID
    current_priority_systems = PersistentValues.get(:priority_systems)
    system_hash = :erlang.phash2(system_name)

    if system_hash in current_priority_systems do
      respond_to_interaction(
        interaction,
        "📍 System **#{system_name}** is already a priority system"
      )
    else
      PersistentValues.add(:priority_systems, system_hash)

      respond_to_interaction(
        interaction,
        "✅ Added **#{system_name}** to priority systems (receives @here notifications)"
      )
    end
  end

  defp remove_priority_system(system_name, interaction) do
    system_hash = :erlang.phash2(system_name)
    current_priority_systems = PersistentValues.get(:priority_systems)

    if system_hash in current_priority_systems do
      PersistentValues.remove(:priority_systems, system_hash)
      respond_to_interaction(interaction, "✅ Removed **#{system_name}** from priority systems")
    else
      respond_to_interaction(interaction, "📍 System **#{system_name}** is not a priority system")
    end
  end

  defp track_system(system_name, interaction) do
    # For basic implementation, just acknowledge tracking
    respond_to_interaction(interaction, "✅ Now tracking system: **#{system_name}**")
  end

  defp untrack_system(system_name, interaction) do
    respond_to_interaction(interaction, "✅ Stopped tracking system: **#{system_name}**")
  end

  # Status and utility functions

  defp build_status_message do
    priority_systems = PersistentValues.get(:priority_systems)
    command_stats = CommandLog.stats()

    """
    **🤖 WandererNotifier Status**

    **Priority Systems:** #{length(priority_systems)}
    **Priority Only Mode:** #{Config.priority_systems_only?()}
    **Total Commands:** #{command_stats.total_commands}
    **Unique Users:** #{command_stats.unique_users}

    **Notifications Enabled:**
    • System: #{Config.system_notifications_enabled?()}
    • Character: #{Config.character_notifications_enabled?()}
    • Kill: #{Config.kill_notifications_enabled?()}

    **Features:**
    • System Tracking: #{Config.feature_enabled?(:system_tracking_enabled)}
    • Character Tracking: #{Config.feature_enabled?(:character_tracking_enabled)}
    """
  end

  # Command logging
  defp log_command(command) do
    entry = %{
      type: command.type,
      param: get_primary_param(command),
      user_id: command.user_id,
      username: command.username,
      guild_id: command.guild_id,
      channel_id: command.channel_id,
      timestamp: DateTime.utc_now()
    }

    CommandLog.log(entry)

    Logger.info("Discord command executed",
      type: command.type,
      param: entry.param,
      user: command.username || command.user_id
    )
  end

  # Extracts the primary parameter from command options
  defp get_primary_param(command) do
    case command.type do
      "system" -> command.options["system_name"] || "unknown"
      "status" -> "status"
      _ -> "unknown"
    end
  end

  # Sends a response to a Discord interaction
  defp respond_to_interaction(interaction, content) do
    response = %{
      type: 4,
      # CHANNEL_MESSAGE_WITH_SOURCE
      data: %{
        content: content,
        flags: 64
        # EPHEMERAL - only visible to user who ran command
      }
    }

    case Api.create_interaction_response(interaction, response) do
      {:ok} ->
        Logger.info("Sent interaction response",
          interaction_id: interaction.id,
          content_length: String.length(content)
        )

      {:error, reason} ->
        Logger.error("Failed to send interaction response",
          interaction_id: interaction.id,
          error: inspect(reason)
        )
    end
  end
end
