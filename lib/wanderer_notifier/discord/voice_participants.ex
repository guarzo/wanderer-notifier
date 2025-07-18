defmodule WandererNotifier.Discord.VoiceParticipants do
  @moduledoc """
  Manages voice participant queries and mentions for Discord notifications.

  This module provides functionality to:
  - Query active voice participants in a Discord guild
  - Filter out bot users and AFK channel participants
  - Generate individual user mentions for notifications
  """

  require Logger

  alias Nostrum.Cache.GuildCache
  alias Nostrum.Struct.Channel
  alias WandererNotifier.Config

  @doc """
  Gets mentions for all active voice participants in the configured guild.

  Returns a list of Discord user mentions (e.g., ["<@123>", "<@456>"]) for users
  currently connected to voice channels, excluding:
  - Bot users
  - Users in the AFK channel
  - Users in non-voice channels

  ## Examples

      iex> get_active_voice_mentions()
      ["<@123456789>", "<@987654321>"]
      
      iex> get_active_voice_mentions()
      []  # No voice participants
  """
  @spec get_active_voice_mentions() :: [String.t()]
  def get_active_voice_mentions do
    case Config.discord_guild_id() do
      nil ->
        Logger.warning("Discord guild ID not configured for voice participant notifications")
        []

      guild_id when is_binary(guild_id) ->
        case Integer.parse(guild_id) do
          {parsed_id, ""} ->
            get_active_voice_mentions(parsed_id)

          _ ->
            Logger.warning("Invalid Discord guild ID format: #{guild_id}")
            []
        end

      guild_id when is_integer(guild_id) ->
        get_active_voice_mentions(guild_id)

      _ ->
        Logger.warning("Invalid Discord guild ID type: #{inspect(Config.discord_guild_id())}")
        []
    end
  end

  @doc """
  Gets mentions for all active voice participants in the specified guild.

  ## Parameters
  - guild_id: The Discord guild ID (integer)

  ## Returns
  A list of Discord user mention strings
  """
  @spec get_active_voice_mentions(integer()) :: [String.t()]
  def get_active_voice_mentions(guild_id) when is_integer(guild_id) do
    try do
      guild = GuildCache.get!(guild_id)

      # Find all voice channel IDs except AFK
      voice_channel_ids = get_voice_channel_ids(guild, guild.afk_channel_id)

      # Gather voice participants and build mentions
      # voice_states is a map of user_id => voice_state_map
      guild.voice_states
      |> Map.values()
      |> Enum.filter(fn voice_state ->
        channel_id = Map.get(voice_state, :channel_id) || Map.get(voice_state, "channel_id")
        user_id = Map.get(voice_state, :user_id) || Map.get(voice_state, "user_id")

        channel_id in voice_channel_ids and not user_is_bot?(user_id)
      end)
      |> Enum.map(fn voice_state ->
        user_id = Map.get(voice_state, :user_id) || Map.get(voice_state, "user_id")
        "<@#{user_id}>"
      end)
      |> Enum.uniq()
    rescue
      error ->
        Logger.error("Failed to get voice participants for guild #{guild_id}: #{inspect(error)}")
        []
    end
  end

  # Gets all voice channel IDs in the guild, excluding the AFK channel.
  @spec get_voice_channel_ids(map(), integer() | nil) :: [integer()]
  defp get_voice_channel_ids(guild, afk_channel_id) do
    case guild.channels do
      nil ->
        []

      channels when is_map(channels) ->
        channels
        |> Map.values()
        |> Enum.filter(&voice_channel?/1)
        |> Enum.reject(&(&1.id == afk_channel_id))
        |> Enum.map(& &1.id)

      channels when is_list(channels) ->
        channels
        |> Enum.filter(&voice_channel?/1)
        |> Enum.reject(&(&1.id == afk_channel_id))
        |> Enum.map(& &1.id)
    end
  end

  # Checks if a channel is a voice channel.
  @spec voice_channel?(Channel.t()) :: boolean()
  defp voice_channel?(%Channel{type: :voice}), do: true
  # Voice channel type ID
  defp voice_channel?(%Channel{type: 2}), do: true
  defp voice_channel?(_), do: false

  # Checks if a user is a bot by querying the Discord API.
  # This function includes caching to avoid repeated API calls for the same user.
  @spec user_is_bot?(integer()) :: boolean()
  defp user_is_bot?(user_id) do
    # Use a simple cache key for bot status
    cache_key = {:bot_status, user_id}

    case :persistent_term.get(cache_key, :not_cached) do
      :not_cached ->
        bot_status = fetch_user_bot_status(user_id)
        # Cache for 5 minutes (bot status doesn't change frequently)
        :persistent_term.put(cache_key, {bot_status, System.system_time(:second) + 300})
        bot_status

      {cached_status, expires_at} ->
        current_time = System.system_time(:second)

        if current_time > expires_at do
          # Cache expired, refresh
          bot_status = fetch_user_bot_status(user_id)
          :persistent_term.put(cache_key, {bot_status, current_time + 300})
          bot_status
        else
          cached_status
        end
    end
  end

  # Fetches bot status from Discord API.
  @spec fetch_user_bot_status(integer()) :: boolean()
  defp fetch_user_bot_status(user_id) do
    case Nostrum.Api.User.get(user_id) do
      {:ok, %{bot: true}} ->
        true

      {:ok, %{"bot" => true}} ->
        true

      {:ok, _user} ->
        false

      {:error, _reason} ->
        # If we can't determine bot status, assume not a bot to be safe
        false
    end
  end

  @doc """
  Builds a notification message with voice participant mentions.

  ## Parameters
  - base_message: The base notification message
  - mentions: List of user mention strings

  ## Returns
  The formatted message with mentions prepended
  """
  @spec build_voice_notification_message(String.t(), [String.t()]) :: String.t()
  def build_voice_notification_message(base_message, []), do: base_message

  def build_voice_notification_message(base_message, mentions) when is_list(mentions) do
    mention_string = Enum.join(mentions, " ")
    "#{mention_string} #{base_message}"
  end

  @doc """
  Clears the bot status cache. Useful for testing or manual cache invalidation.
  """
  @spec clear_bot_cache() :: :ok
  def clear_bot_cache do
    :persistent_term.get()
    |> Enum.each(fn
      {{:bot_status, _user_id}, _value} = key -> :persistent_term.erase(key)
      _ -> :ok
    end)

    :ok
  end
end
