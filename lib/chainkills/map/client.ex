defmodule ChainKills.Map.Client do
  @moduledoc """
  Main entry point for map-related functionality.
  Delegates to submodules for systems, backup kills, and characters.
  """

  alias ChainKills.Map.Systems
  alias ChainKills.Map.Characters
  alias ChainKills.Map.BackupKills

  # A single function for each major operation:
  def update_systems,             do: Systems.update_systems()
  def check_backup_kills,         do: BackupKills.check_backup_kills()
  def update_tracked_characters,  do: Characters.update_tracked_characters()
end
