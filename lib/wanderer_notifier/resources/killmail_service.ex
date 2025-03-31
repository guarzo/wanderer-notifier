defmodule WandererNotifier.Resources.KillmailService do
  @moduledoc """
  Service for accessing killmail persistence functions.
  Provides a clean API for killmail-related database operations.
  """

  alias WandererNotifier.Resources.KillmailPersistence

  @doc """
  Persists a killmail to the database if it's relevant to tracked characters.
  """
  @spec maybe_persist_killmail(map()) :: {:ok, :persisted | :not_persisted} | {:error, String.t()}
  def maybe_persist_killmail(kill) do
    KillmailPersistence.maybe_persist_killmail(kill)
  end

  @doc """
  Persists a killmail to the database if it's relevant to tracked characters.
  More explicit version of maybe_persist_killmail.
  """
  @spec persist_killmail(map()) :: {:ok, :persisted} | :ignored | {:error, String.t()}
  def persist_killmail(kill) do
    KillmailPersistence.persist_killmail(kill)
  end

  @doc """
  Gets statistics about tracked characters and their killmails.
  """
  def get_tracked_kills_stats do
    KillmailPersistence.get_tracked_kills_stats()
  end

  @doc """
  Gets all killmails for a specific character.
  """
  def get_killmails_for_character(character_id) do
    KillmailPersistence.get_killmails_for_character(character_id)
  end

  @doc """
  Gets all killmails for a specific system.
  """
  def get_killmails_for_system(system_id) do
    KillmailPersistence.get_killmails_for_system(system_id)
  end

  @doc """
  Gets killmails for a specific character within a date range.
  """
  def get_character_killmails(character_id, from_date, to_date, limit \\ 100) do
    KillmailPersistence.get_character_killmails(character_id, from_date, to_date, limit)
  end

  @doc """
  Checks if kill charts feature is enabled.
  """
  def kill_charts_enabled? do
    KillmailPersistence.kill_charts_enabled?()
  end

  @doc """
  Explicitly logs the current kill charts feature status.
  """
  def log_kill_charts_status do
    KillmailPersistence.log_kill_charts_status()
  end

  @doc """
  Checks if a killmail exists for a character with a specific role.
  """
  def killmail_exists_for_character?(killmail_id, character_id, role) do
    KillmailPersistence.killmail_exists_for_character?(killmail_id, character_id, role)
  end

  @doc """
  Checks directly in the database if a killmail exists for a specific character and role.
  """
  def check_killmail_exists_in_database(killmail_id, character_id, role) do
    KillmailPersistence.check_killmail_exists_in_database(killmail_id, character_id, role)
  end

  @doc """
  Gets the total number of killmails in the database.
  """
  def count_total_killmails do
    KillmailPersistence.count_total_killmails()
  end
end
