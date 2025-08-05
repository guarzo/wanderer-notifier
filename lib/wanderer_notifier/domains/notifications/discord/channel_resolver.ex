defmodule WandererNotifier.Domains.Notifications.Discord.ChannelResolver do
  @moduledoc """
  Resolves Discord channel IDs with fallback logic.

  Handles channel resolution for different notification types and environments
  with appropriate fallback mechanisms.
  """

  alias WandererNotifier.Shared.Config
  require Logger

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Gets the primary Discord channel ID as an integer.

  Returns the normalized channel ID with fallbacks if the primary is not available.
  """
  def get_primary_channel_id do
    try do
      raw_id = Config.discord_channel_id()
      Logger.debug("Fetching Discord channel ID")

      # First try to normalize the primary channel ID
      normalized_id = normalize_channel_id(raw_id)

      # If we couldn't normalize it, try some fallbacks
      if is_nil(normalized_id) do
        Logger.warning("Could not normalize Discord channel ID, trying fallbacks", category: :api)
        try_fallback_channels()
      else
        normalized_id
      end
    rescue
      e ->
        Logger.error("Error getting Discord channel ID",
          error: Exception.message(e),
          category: :api
        )

        nil
    end
  end

  @doc """
  Resolves the target channel for a specific notification type.

  ## Parameters
  - notification_type: :kill, :character, :system, or :default
  - override_channel_id: Optional channel ID to use instead of type-specific channel

  ## Returns
  Integer channel ID or nil if no valid channel found.
  """
  def resolve_channel(notification_type, override_channel_id \\ nil)

  def resolve_channel(_notification_type, override_channel_id)
      when override_channel_id != nil do
    normalize_channel_id(override_channel_id)
  end

  def resolve_channel(:kill, nil) do
    Config.discord_kill_channel_id()
    |> normalize_channel_id()
    |> fallback_to_primary()
  end

  def resolve_channel(:character, nil) do
    Config.discord_character_channel_id()
    |> normalize_channel_id()
    |> fallback_to_primary()
  end

  def resolve_channel(:system, nil) do
    Config.discord_system_channel_id()
    |> normalize_channel_id()
    |> fallback_to_primary()
  end

  def resolve_channel(_, nil) do
    get_primary_channel_id()
  end

  @doc """
  Determines if running in test environment.
  """
  def test_environment? do
    Application.get_env(:wanderer_notifier, :env, :prod) == :test
  end

  @doc """
  Gets the test channel ID for development/testing.
  """
  def get_test_channel do
    # In test mode, use a placeholder channel
    # Placeholder for tests
    123_456_789
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp try_fallback_channels do
    # Try other channel IDs as fallbacks
    cond do
      fallback = normalize_channel_id(Config.discord_system_channel_id()) ->
        Logger.info("Using system channel ID as fallback", fallback: fallback, category: :api)
        fallback

      fallback = normalize_channel_id(Config.discord_kill_channel_id()) ->
        Logger.info("Using kill channel ID as fallback", fallback: fallback, category: :api)
        fallback

      fallback = normalize_channel_id(Config.discord_character_channel_id()) ->
        Logger.info("Using character channel ID as fallback",
          fallback: fallback,
          category: :api
        )

        fallback

      true ->
        Logger.error("No valid Discord channel ID available, notifications may fail",
          category: :api
        )

        nil
    end
  end

  defp fallback_to_primary(nil), do: get_primary_channel_id()
  defp fallback_to_primary(channel_id), do: channel_id

  defp normalize_channel_id(nil), do: nil
  defp normalize_channel_id(""), do: nil
  defp normalize_channel_id(id) when is_integer(id), do: id

  defp normalize_channel_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, ""} -> parsed_id
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp normalize_channel_id(_), do: nil
end
