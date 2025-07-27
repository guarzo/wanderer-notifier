defmodule WandererNotifier.Contexts.Killmail do
  @moduledoc """
  Context module for killmail processing functionality.
  Provides a clean API boundary for all killmail-related operations.
  """

  alias WandererNotifier.Domains.Killmail.{
    Enrichment,
    Pipeline
  }

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
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
  def process_killmail(killmail) do
    context = WandererNotifier.Domains.Killmail.Processor.Context.new()
    Pipeline.process_killmail(killmail, context)
  end

  @doc """
  Gets recent kills for a specific system.
  """
  @spec recent_kills_for_system(integer(), integer()) :: String.t()
  defdelegate recent_kills_for_system(system_id, limit \\ 3), to: Enrichment

  # ──────────────────────────────────────────────────────────────────────────────
  # Client Management
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Checks if the killmail stream is connected.
  """
  @spec stream_connected?() :: boolean()
  def stream_connected? do
    # Check if PipelineWorker (which manages WebSocket client) is running
    pipeline_pid = Process.whereis(WandererNotifier.Domains.Killmail.PipelineWorker)
    is_pid(pipeline_pid) and Process.alive?(pipeline_pid)
  end
end
