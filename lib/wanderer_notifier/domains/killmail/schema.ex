defmodule WandererNotifier.Domains.Killmail.Schema do
  @moduledoc """
  Centralized schema definitions for killmail JSON field names.
  Provides a single source of truth for all field names used in killmail processing.
  """

  # Core killmail fields
  @killmail_id "killmail_id"
  @victim "victim"
  @solar_system_id "solar_system_id"
  @package "package"
  @killmail "killmail"

  @doc """
  Core killmail field names
  """
  def killmail_id, do: @killmail_id
  def victim, do: @victim
  def solar_system_id, do: @solar_system_id
  def package, do: @package

  @doc """
  Helper to get nested field path for killmail ID in package.
  This is the only path helper currently used in the codebase.
  """
  def package_killmail_id_path, do: [@package, @killmail, @killmail_id]
end
