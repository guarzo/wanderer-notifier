defmodule WandererNotifier.Domains.Killmail.Schema do
  @moduledoc """
  Simple field name constants for killmail processing.
  Provides backward compatibility for legacy data sources.
  """

  def killmail_id, do: "killmail_id"
  def victim, do: "victim"
  def solar_system_id, do: "solar_system_id"
end
