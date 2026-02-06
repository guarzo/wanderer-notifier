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
        case Integer.parse(guild_id, 10) do
          {parsed_id, ""} ->
            get_active_voice_mentions(parsed_id)

          _ ->
            Logger.info("Invalid Discord guild ID format", guild_id: guild_id)
            []
        end
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
    afk_channel_id = guild.afk_channel_id
    voice_channel_ids = get_voice_channel_ids(guild, afk_channel_id)

    Logger.info(
      "Voice participant filtering: " <>
        "total_voice_states=#{length(voice_states)}, " <>
        "afk_channel_id=#{inspect(afk_channel_id)}, " <>
        "voice_channel_ids=#{inspect(voice_channel_ids)}"
    )

    after_afk_filter = exclude_afk_users(voice_states, afk_channel_id)

    Logger.info(
      "After AFK exclusion: #{length(after_afk_filter)} users " <>
        "(excluded #{length(voice_states) - length(after_afk_filter)})"
    )

    after_channel_filter = filter_by_voice_channels(after_afk_filter, voice_channel_ids)

    Logger.info(
      "After voice channel filter: #{length(after_channel_filter)} users " <>
        "(filtered #{length(after_afk_filter) - length(after_channel_filter)})"
    )

    if after_afk_filter != [] and after_channel_filter == [] do
      # Log the channel IDs that were rejected to help diagnose mismatches
      rejected_channel_ids =
        after_afk_filter
        |> Enum.map(fn vs ->
          Map.get(vs, :channel_id) || Map.get(vs, "channel_id")
        end)
        |> Enum.uniq()

      Logger.warning(
        "All voice users filtered out! User channel_ids=#{inspect(rejected_channel_ids)} " <>
          "not in voice_channel_ids=#{inspect(voice_channel_ids)}"
      )
    end

    build_user_mentions(after_channel_filter)
  end

  # Directly excludes users in the AFK channel from voice states
  @spec exclude_afk_users(list(), integer() | nil) :: list()
  defp exclude_afk_users(voice_states, nil), do: voice_states

  defp exclude_afk_users(voice_states, afk_channel_id) do
    Enum.reject(voice_states, fn voice_state ->
      channel_id = Map.get(voice_state, :channel_id) || Map.get(voice_state, "channel_id")
      channel_id == afk_channel_id
    end)
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
    all_channels = extract_channels(guild.channels)
    voice_channels = filter_voice_channels(all_channels)

    if voice_channels == [] and all_channels != [] do
      channel_types =
        all_channels
        |> Enum.map(fn ch -> {Map.get(ch, :id), Map.get(ch, :type)} end)

      Logger.warning("No voice channels found! Channel types in guild: #{inspect(channel_types)}")
    end

    voice_channels
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
  # Discord channel types: 2 = GUILD_VOICE, 13 = GUILD_STAGE_VOICE
  @voice_channel_types [2, 13]
  @spec voice_channel?(map()) :: boolean()
  defp voice_channel?(%{type: type}) when type in @voice_channel_types, do: true
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
