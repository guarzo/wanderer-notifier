defmodule WandererNotifier.Services.ZKillboardApi do
  @moduledoc """
  Service for interacting with the zKillboard API.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Api.ZKill.Client instead.
  """

  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Core.Logger, as: AppLogger

  @doc """
  Gets kills for a specific character.
  Since startTime/endTime are no longer supported by the API, this gets all recent kills.
  Date filtering should be done in memory after fetching the kills.

  ## Parameters
    - character_id: The character ID to get kills for

  ## Returns
    {:ok, kills} | {:error, reason}
  """
  def get_character_kills(character_id, limit \\ 25, page \\ 1) do
    # Log deprecation warning
    AppLogger.api_warn(
      "ZKillboardApi.get_character_kills is deprecated, please use WandererNotifier.Api.ZKill.Client.get_character_kills instead"
    )

    # Delegate to the proper implementation
    ZKillClient.get_character_kills(character_id, limit, page)
  end

  @doc """
  Gets details for a specific killmail.

  ## Parameters
    - kill_id: The killmail ID to fetch

  ## Returns
    {:ok, kill_data} | {:error, reason}
  """
  def get_killmail(kill_id) do
    # Log deprecation warning
    AppLogger.api_warn(
      "ZKillboardApi.get_killmail is deprecated, please use WandererNotifier.Api.ZKill.Client.get_single_killmail instead"
    )

    # Delegate to the proper implementation
    ZKillClient.get_single_killmail(kill_id)
  end
end
