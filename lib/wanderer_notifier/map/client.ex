defmodule WandererNotifier.Map.Client do
  @moduledoc """
  High-level map API client.
  """

  alias WandererNotifier.Map.Systems
  alias WandererNotifier.Map.Characters
  alias WandererNotifier.Map.BackupKills

  # A single function for each major operation:
  def update_systems, do: Systems.update_systems()
  def check_backup_kills, do: BackupKills.check_backup_kills()
  def update_tracked_characters, do: Characters.update_tracked_characters()
end
