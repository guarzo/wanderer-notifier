defmodule WandererNotifier.Contexts.Killmail do
  @moduledoc """
  Backward compatibility adapter for killmail processing functionality.
  
  This module maintains the existing Killmail context API while delegating
  to the new ProcessingContext. This allows existing code to continue working
  without changes while providing a migration path to the consolidated context.
  """

  # Delegate to the new ProcessingContext
  alias WandererNotifier.Contexts.ProcessingContext

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API - delegated to ProcessingContext
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Processes a killmail through the complete pipeline.

  ## Examples

      iex> Killmail.process_killmail(%{"killmail_id" => 123})
      {:ok, %{processed: true}}

      iex> Killmail.process_killmail(%{})
      {:error, :invalid_killmail}
  """
  @spec process_killmail(map()) :: {:ok, String.t() | :skipped} | {:error, term()}
  defdelegate process_killmail(killmail), to: ProcessingContext

  @doc """
  Gets recent kills for a specific system.
  """
  @spec recent_kills_for_system(integer(), integer()) :: String.t()
  defdelegate recent_kills_for_system(system_id, limit \\ 3), to: ProcessingContext, as: :get_recent_system_kills

  # ──────────────────────────────────────────────────────────────────────────────
  # Client Management - delegated to ProcessingContext
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Checks if the killmail stream is connected.
  """
  @spec stream_connected?() :: boolean()
  defdelegate stream_connected?(), to: ProcessingContext
end
