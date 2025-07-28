defmodule WandererNotifier.Infrastructure.Adapters.Discord.VoiceParticipants do
  require Logger

  @moduledoc """
  Manages voice participant queries and mentions for Discord notifications.

  This module provides functionality to:
  - Query active voice participants in a Discord guild
  - Filter out AFK channel participants
  - Generate individual user mentions for notifications
  """

  alias Nostrum.Cache.GuildCache
  alias WandererNotifier.Shared.Config

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
        Logger.info("Discord guild ID not configured for voice participant notifications")

        []

      guild_id when is_binary(guild_id) ->
        case Integer.parse(guild_id) do
          {parsed_id, ""} ->
            get_active_voice_mentions(parsed_id)

          _ ->
            Logger.info("Invalid Discord guild ID format", guild_id: guild_id)
            []
        end

      guild_id when is_integer(guild_id) ->
        get_active_voice_mentions(guild_id)

      _ ->
        Logger.info("Invalid Discord guild ID type",
          guild_id: inspect(Config.discord_guild_id())
        )

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
  @spec get_active_voice_mentions(integer() | any()) :: [String.t()]
  def get_active_voice_mentions(guild_id) when is_integer(guild_id) and guild_id > 0 do
    try do
      guild_id
      |> get_guild_safely()
      |> extract_voice_participants()
    rescue
      error ->
        Logger.info("Failed to get voice participants for guild",
          guild_id: guild_id,
          error: inspect(error)
        )

        []
    end
  end

  # Handle zero or negative integers
  def get_active_voice_mentions(guild_id) when is_integer(guild_id) and guild_id <= 0 do
    Logger.info("Invalid guild ID (must be positive)", guild_id: guild_id)
    []
  end

  # Handle non-integer guild_id inputs
  def get_active_voice_mentions(invalid_guild_id) do
    Logger.info(
      "Invalid guild ID type provided to get_active_voice_mentions. Expected positive integer",
      guild_id: inspect(invalid_guild_id)
    )

    []
  end

  # Gets guild safely and logs debug info
  @spec get_guild_safely(integer()) :: map()
  defp get_guild_safely(guild_id) do
    GuildCache.get!(guild_id)
  end

  # Extracts voice participants from guild
  @spec extract_voice_participants(map()) :: [String.t()]
  defp extract_voice_participants(guild) do
    case guild.voice_states do
      nil ->
        Logger.info("No voice states available for guild", guild_id: guild.id)
        []

      voice_states when is_list(voice_states) ->
        process_voice_states_list(voice_states, guild)
    end
  end

  # Processes voice states when they're in list format
  @spec process_voice_states_list(list(), map()) :: [String.t()]
  defp process_voice_states_list(voice_states, guild) do
    voice_channel_ids = get_voice_channel_ids(guild, guild.afk_channel_id)

    voice_states
    |> filter_by_voice_channels(voice_channel_ids)
    |> build_user_mentions()
  end

  # Filters voice states to only include those in voice channels
  @spec filter_by_voice_channels(list(), [integer()]) :: list()
  defp filter_by_voice_channels(voice_states, voice_channel_ids) do
    Enum.filter(voice_states, fn voice_state ->
      channel_id = Map.get(voice_state, :channel_id) || Map.get(voice_state, "channel_id")
      channel_id in voice_channel_ids
    end)
  end

  # Builds user mentions from voice states
  @spec build_user_mentions(list()) :: [String.t()]
  defp build_user_mentions(voice_states) do
    voice_states
    |> Enum.map(fn voice_state ->
      user_id = Map.get(voice_state, :user_id) || Map.get(voice_state, "user_id")
      "<@#{user_id}>"
    end)
    |> Enum.uniq()
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
  @spec extract_channels(map() | nil) :: [map()]
  defp extract_channels(nil), do: []
  defp extract_channels(channels) when is_map(channels), do: Map.values(channels)

  # Filters channels to only include voice channels
  @spec filter_voice_channels([map()]) :: [map()]
  defp filter_voice_channels(channels), do: Enum.filter(channels, &voice_channel?/1)

  # Excludes the AFK channel from the list
  @spec exclude_afk_channel([map()], integer() | nil) :: [map()]
  defp exclude_afk_channel(channels, afk_channel_id) do
    Enum.reject(channels, &(&1.id == afk_channel_id))
  end

  # Extracts channel IDs from channel structs
  @spec extract_channel_ids([map()]) :: [integer()]
  defp extract_channel_ids(channels), do: Enum.map(channels, & &1.id)

  # Checks if a channel is a voice channel.
  @spec voice_channel?(map()) :: boolean()
  defp voice_channel?(%{type: :voice}), do: true
  # Voice channel type ID
  defp voice_channel?(%{type: 2}), do: true
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
