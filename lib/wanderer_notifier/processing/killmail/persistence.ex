defmodule WandererNotifier.Processing.Killmail.Persistence do
  @moduledoc """
  Handles persistence of killmails and their character involvements.

  This module provides a clean interface for persisting killmails to the database,
  including their character involvements. It consolidates persistence logic that
  was previously scattered across multiple modules.

  @deprecated Use WandererNotifier.Killmail.Processing.Persistence instead.
  """

  @behaviour WandererNotifier.Processing.Killmail.PersistenceBehaviour

  require Logger
  import Ecto.Query, only: [from: 2]

  alias WandererNotifier.Data.Repo
  alias WandererNotifier.Killmail.Core.Data, as: NewKillmailData
  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Resources.KillmailCharacterInvolvement
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Processing.Persistence, as: NewPersistence

  @doc """
  Persists a killmail to the database if it doesn't already exist.

  ## Parameters
    - killmail: The KillmailData struct to persist
    - character_id: The character ID that initiated the processing (for tracking)

  ## Returns
    - {:ok, persisted_killmail, created} where created is a boolean indicating
      whether a new record was created (true) or it already existed (false)
    - {:error, reason} if persistence fails

  @deprecated Use WandererNotifier.Killmail.Processing.Persistence.persist_killmail/2 instead.
  """
  @impl true
  @spec persist_killmail(KillmailData.t(), integer() | nil) ::
          {:ok, KillmailData.t(), boolean()} | {:error, any()}
  def persist_killmail(%KillmailData{} = killmail, character_id) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Persistence.persist_killmail/2 instead."
    )

    # Convert to new format
    case convert_to_new_format(killmail) do
      {:ok, new_killmail} ->
        # Delegate to new module
        case NewPersistence.persist_killmail(new_killmail, character_id) do
          {:ok, persisted_new_killmail, created} ->
            # Convert back to old format if needed
            {:ok, persisted_new_killmail, created}

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # For non-KillmailData values, return immediate error
  def persist_killmail(other, _character_id) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Persistence is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Persistence instead."
    )

    AppLogger.kill_error("Cannot persist non-KillmailData: #{inspect(other)}")
    {:error, :invalid_data_type}
  end

  @doc """
  Gets all killmails for a specific character.

  ## Parameters
    - character_id: The character ID to look for

  ## Returns
    - {:ok, killmails} with a list of killmails involving the character
    - {:error, reason} if there's an error

  @deprecated Use WandererNotifier.Killmail.Processing.Persistence.get_killmails_for_character/1 instead.
  """
  @impl true
  @spec get_killmails_for_character(integer() | String.t()) ::
          {:ok, list(KillmailResource.t())} | {:error, any()}
  def get_killmails_for_character(character_id)
      when is_binary(character_id) or is_integer(character_id) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Persistence.get_killmails_for_character/1 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Persistence.get_killmails_for_character/1 instead."
    )

    NewPersistence.get_killmails_for_character(character_id)
  end

  @doc """
  Gets all killmails for a specific solar system.

  ## Parameters
    - system_id: The solar system ID to look for

  ## Returns
    - {:ok, killmails} with a list of killmails in the system
    - {:error, reason} if there's an error

  @deprecated Use WandererNotifier.Killmail.Processing.Persistence.get_killmails_for_system/1 instead.
  """
  @spec get_killmails_for_system(integer() | String.t()) ::
          {:ok, list(KillmailResource.t())} | {:error, any()}
  def get_killmails_for_system(system_id) when is_binary(system_id) or is_integer(system_id) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Persistence.get_killmails_for_system/1 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Persistence.get_killmails_for_system/1 instead."
    )

    NewPersistence.get_killmails_for_system(system_id)
  end

  @doc """
  Gets killmails for a specific character within a date range.

  ## Parameters
    - character_id: The character ID to look for
    - from_date: The start date (inclusive)
    - to_date: The end date (inclusive)
    - limit: Maximum number of killmails to return (default: 100)

  ## Returns
    - {:ok, killmails} with a list of killmails involving the character in the date range
    - {:error, reason} if there's an error

  @deprecated Use WandererNotifier.Killmail.Processing.Persistence.get_character_killmails/4 instead.
  """
  @spec get_character_killmails(
          integer() | String.t(),
          DateTime.t(),
          DateTime.t(),
          integer()
        ) :: {:ok, list(KillmailResource.t())} | {:error, any()}
  def get_character_killmails(character_id, from_date, to_date, limit \\ 100)
      when (is_binary(character_id) or is_integer(character_id)) and is_integer(limit) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Persistence.get_character_killmails/4 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Persistence.get_character_killmails/4 instead."
    )

    NewPersistence.get_character_killmails(character_id, from_date, to_date, limit)
  end

  @doc """
  Checks if a killmail exists for a character with a specific role.

  ## Parameters
    - killmail_id: The killmail ID
    - character_id: The character ID
    - role: The role (:victim or :attacker)

  ## Returns
    - {:ok, true} if the killmail exists with the character in the specified role
    - {:ok, false} if not found
    - {:error, reason} if there's an error

  @deprecated Use WandererNotifier.Killmail.Processing.Persistence.exists?/3 instead.
  """
  @spec exists?(integer() | String.t(), integer() | String.t(), atom()) ::
          {:ok, boolean()} | {:error, any()}
  def exists?(killmail_id, character_id, role) when role in [:victim, :attacker] do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Persistence.exists?/3 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Persistence.exists?/3 instead."
    )

    NewPersistence.exists?(killmail_id, character_id, role)
  end

  @doc """
  Checks directly if a killmail exists in the database with a specific character and role.

  This is a more direct check that bypasses caching.

  ## Parameters
    - killmail_id: The killmail ID
    - character_id: The character ID
    - role: The role (:victim or :attacker)

  ## Returns
    - true if the killmail exists with the character in the specified role
    - false if not found

  @deprecated Use WandererNotifier.Killmail.Processing.Persistence instead.
  """
  @spec check_killmail_exists_in_database(integer() | String.t(), integer() | String.t(), atom()) ::
          boolean()
  def check_killmail_exists_in_database(killmail_id, character_id, role)
      when role in [:victim, :attacker] do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Persistence.check_killmail_exists_in_database/3 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Persistence instead."
    )

    case exists?(killmail_id, character_id, role) do
      {:ok, exists} -> exists
      {:error, _} -> false
    end
  end

  @doc """
  Gets the total number of killmails in the database.

  ## Returns
    - The count of killmails

  @deprecated Use WandererNotifier.Killmail.Processing.Persistence.count_total_killmails/0 instead.
  """
  @spec count_total_killmails() :: integer()
  def count_total_killmails() do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Persistence.count_total_killmails/0 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Persistence.count_total_killmails/0 instead."
    )

    NewPersistence.count_total_killmails()
  end

  # Helper function to convert old KillmailData to new KillmailData format
  defp convert_to_new_format(%KillmailData{} = old_killmail) do
    # Check if it's already the new format
    if Map.has_key?(old_killmail, :__struct__) and old_killmail.__struct__ == NewKillmailData do
      {:ok, old_killmail}
    else
      # Extract all fields from the old format to create a new one
      # This assumes the field names are roughly similar
      attrs = Map.from_struct(old_killmail)

      case NewKillmailData.from_map(attrs) do
        {:ok, new_killmail} -> {:ok, new_killmail}
        error -> error
      end
    end
  rescue
    e ->
      Logger.error("Error converting KillmailData: #{inspect(e)}")
      {:error, :conversion_error}
  end
end
