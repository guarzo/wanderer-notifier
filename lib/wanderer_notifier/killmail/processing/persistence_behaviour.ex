defmodule WandererNotifier.Killmail.Processing.PersistenceBehaviour do
  @moduledoc """
  Defines the behaviour for persistence modules that store killmail data.
  """

  alias WandererNotifier.Killmail.Core.Data, as: KillmailData
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  @doc """
  Persists a killmail to storage.
  """
  @callback persist(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}

  @doc """
  Persists a killmail to the database if it doesn't already exist, with character tracking.
  """
  @callback persist_killmail(KillmailData.t(), integer() | nil) ::
              {:ok, KillmailData.t(), boolean()} | {:error, any()}

  @doc """
  Checks if a killmail exists in the database.
  """
  @callback check_killmail_exists(integer() | String.t()) :: {:ok, boolean()} | {:error, any()}

  @doc """
  Gets all killmails for a specific character.
  """
  @callback get_killmails_for_character(integer() | String.t()) ::
              {:ok, list(KillmailResource.t())} | {:error, any()}

  @doc """
  Gets all killmails for a specific solar system.
  """
  @callback get_killmails_for_system(integer() | String.t()) ::
              {:ok, list(KillmailResource.t())} | {:error, any()}

  @doc """
  Gets killmails for a specific character within a date range.
  """
  @callback get_character_killmails(
              integer() | String.t(),
              DateTime.t(),
              DateTime.t(),
              integer()
            ) :: {:ok, list(KillmailResource.t())} | {:error, any()}

  @doc """
  Checks if a killmail exists for a character with a specific role.
  """
  @callback exists?(integer() | String.t(), integer() | String.t(), atom()) ::
              {:ok, boolean()} | {:error, any()}

  @doc """
  Gets the total number of killmails in the database.
  """
  @callback count_total_killmails() :: integer()
end
