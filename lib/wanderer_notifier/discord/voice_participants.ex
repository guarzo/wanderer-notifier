defmodule WandererNotifier.Discord.VoiceParticipants do
  @moduledoc """
  Manages voice participant queries and mentions for Discord notifications.

  This module provides functionality to:
  - Query active voice participants in a Discord guild
  - Filter out AFK channel participants
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
        channel_id in voice_channel_ids
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
    guild.channels
    |> extract_channels()
    |> filter_voice_channels()
    |> exclude_afk_channel(afk_channel_id)
    |> extract_channel_ids()
  end

  # Extracts channels from guild, handling nil case
  @spec extract_channels(map() | nil) :: [Channel.t()]
  defp extract_channels(nil), do: []
  defp extract_channels(channels) when is_map(channels), do: Map.values(channels)

  # Filters channels to only include voice channels
  @spec filter_voice_channels([Channel.t()]) :: [Channel.t()]
  defp filter_voice_channels(channels), do: Enum.filter(channels, &voice_channel?/1)

  # Excludes the AFK channel from the list
  @spec exclude_afk_channel([Channel.t()], integer() | nil) :: [Channel.t()]
  defp exclude_afk_channel(channels, afk_channel_id) do
    Enum.reject(channels, &(&1.id == afk_channel_id))
  end

  # Extracts channel IDs from channel structs
  @spec extract_channel_ids([Channel.t()]) :: [integer()]
  defp extract_channel_ids(channels), do: Enum.map(channels, & &1.id)

  # Checks if a channel is a voice channel.
  @spec voice_channel?(Channel.t()) :: boolean()
  defp voice_channel?(%Channel{type: :voice}), do: true
  # Voice channel type ID
  defp voice_channel?(%Channel{type: 2}), do: true
  defp voice_channel?(_), do: false

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
end
