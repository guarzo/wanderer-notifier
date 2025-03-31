defmodule WandererNotifier.Services.CharacterKillsService do
  @moduledoc """
  Service for fetching and processing character kills from ESI.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Api.Character.KillsService instead.
  """

  alias WandererNotifier.Api.Character.KillsService
  alias WandererNotifier.Core.Logger, as: AppLogger

  @doc """
  Gets kills for a character within a date range.

  ## Options
    * `:from` - Start date for filtering kills (inclusive). If not specified, no lower bound is applied.
    * `:to` - End date for filtering kills (inclusive). If not specified, no upper bound is applied.

  ## Examples
      # Get all kills
      get_kills_for_character(123456)

      # Get kills from a specific date onwards
      get_kills_for_character(123456, from: ~D[2024-03-01])

      # Get kills within a date range
      get_kills_for_character(123456, from: ~D[2024-03-01], to: ~D[2024-03-31])
  """
  @spec get_kills_for_character(integer(), Keyword.t(), map()) ::
          {:ok, list(map())} | {:error, term()}
  def get_kills_for_character(character_id, opts \\ [], deps \\ %{}) do
    AppLogger.api_warn(
      "CharacterKillsService.get_kills_for_character is deprecated, please use WandererNotifier.Api.Character.KillsService.get_kills_for_character instead"
    )

    KillsService.get_kills_for_character(character_id, opts, deps)
  end

  @doc """
  Fetches and persists kills for all tracked characters.
  """
  @spec fetch_and_persist_all_tracked_character_kills(integer(), integer(), map()) ::
          {:ok, %{processed: integer(), persisted: integer(), characters: integer()}}
          | {:error, term()}
  def fetch_and_persist_all_tracked_character_kills(limit \\ 25, page \\ 1, deps \\ %{}) do
    AppLogger.api_warn(
      "CharacterKillsService.fetch_and_persist_all_tracked_character_kills is deprecated, please use WandererNotifier.Api.Character.KillsService.fetch_and_persist_all_tracked_character_kills instead"
    )

    KillsService.fetch_and_persist_all_tracked_character_kills(limit, page, deps)
  end

  @doc """
  Fetches and persists kills for a single character.
  """
  @spec fetch_and_persist_character_kills(integer(), integer(), integer(), map()) ::
          {:ok, %{processed: integer(), persisted: integer()}}
          | {:error, term()}
  def fetch_and_persist_character_kills(
        character_id,
        limit \\ 25,
        page \\ 1,
        deps \\ %{}
      ) do
    AppLogger.api_warn(
      "CharacterKillsService.fetch_and_persist_character_kills is deprecated, please use WandererNotifier.Api.Character.KillsService.fetch_and_persist_character_kills instead"
    )

    KillsService.fetch_and_persist_character_kills(character_id, limit, page, deps)
  end
end
