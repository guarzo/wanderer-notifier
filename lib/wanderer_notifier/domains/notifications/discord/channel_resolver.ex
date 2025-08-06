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
    Config.discord_channel_id()
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
    # Try channel IDs in priority order as fallbacks
    fallback_channels = [
      {:system, Config.discord_system_channel_id()},
      {:kill, Config.discord_channel_id()},
      {:character, Config.discord_character_channel_id()}
    ]

    case find_valid_fallback_channel(fallback_channels) do
      {type, channel_id} ->
        Logger.info("Using #{type} channel ID as fallback", fallback: channel_id, category: :api)
        channel_id

      nil ->
        Logger.error("No valid Discord channel ID available, notifications may fail",
          category: :api
        )

        nil
    end
  end

  defp find_valid_fallback_channel([]), do: nil

  defp find_valid_fallback_channel([{type, channel_id} | rest]) do
    case normalize_channel_id(channel_id) do
      nil -> find_valid_fallback_channel(rest)
      valid_id -> {type, valid_id}
    end
  end

  defp fallback_to_primary(nil), do: get_primary_channel_id()
  defp fallback_to_primary(channel_id), do: channel_id

  defp normalize_channel_id(nil), do: nil
  defp normalize_channel_id(""), do: nil
  defp normalize_channel_id(id) when is_integer(id), do: id

  defp normalize_channel_id(id) when is_binary(id) do
    if String.trim(id) == "" do
      nil
    else
      case Integer.parse(id, 10) do
        {parsed_id, ""} -> parsed_id
        _ -> nil
      end
    end
  rescue
    _ -> nil
  end

  defp normalize_channel_id(_), do: nil
end
