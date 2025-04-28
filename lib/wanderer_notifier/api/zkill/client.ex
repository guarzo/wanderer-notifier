defmodule WandererNotifier.Api.ZKill.Client do
  @moduledoc """
  Client for interacting with the ZKillboard API

  ## Deprecation Notice
  This module is deprecated and will be removed in a future version.
  Please use `WandererNotifier.ZKill.Client` instead.
  """

  alias WandererNotifier.ZKill.Client, as: NewZKillClient

  @doc """
  Get a single killmail by ID

  ## Deprecation Notice
  This function is deprecated and will be removed in a future version.
  Please use `WandererNotifier.ZKill.Client.get_single_killmail/1` instead.
  """
  def get_single_killmail(kill_id) when is_integer(kill_id) do
    # Delegate to the new implementation
    NewZKillClient.get_single_killmail(kill_id)
  end

  @doc """
  Gets recent kills with an optional limit.

  ## Deprecation Notice
  This function is deprecated and will be removed in a future version.
  Please use `WandererNotifier.ZKill.Client.get_recent_kills/1` instead.
  """
  def get_recent_kills(limit \\ 10) do
    # Delegate to the new implementation
    NewZKillClient.get_recent_kills(limit)
  end

  @doc """
  Gets kills for a specific system with an optional limit.

  ## Deprecation Notice
  This function is deprecated and will be removed in a future version.
  Please use `WandererNotifier.ZKill.Client.get_system_kills/2` instead.
  """
  def get_system_kills(system_id, limit \\ 5) do
    # Delegate to the new implementation
    NewZKillClient.get_system_kills(system_id, limit)
  end

  @doc """
  Gets kills for a specific character.

  ## Deprecation Notice
  This function is deprecated and will be removed in a future version.
  Please use `WandererNotifier.ZKill.Client.get_character_kills/3` instead.
  """
  def get_character_kills(character_id, date_range \\ nil, limit \\ 100) do
    # Delegate to the new implementation
    NewZKillClient.get_character_kills(character_id, date_range, limit)
  end
end
