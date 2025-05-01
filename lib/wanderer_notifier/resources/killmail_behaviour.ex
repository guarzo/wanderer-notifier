defmodule WandererNotifier.Resources.KillmailBehaviour do
  @moduledoc """
  Behaviour module for database-aware killmail operations.
  Ensures consistent handling of database operations across the application.
  """

  @doc """
  Checks if database operations are enabled based on feature flags.
  Returns true if either map_charts or kill_charts is enabled.
  """
  @callback database_enabled?() :: boolean()

  @doc """
  Safely reads killmails from the database, with a fallback when database is disabled.
  """
  @callback read_safely(query :: term()) :: {:ok, list()} | {:error, term()}
end
