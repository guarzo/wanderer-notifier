defmodule WandererNotifier.Domains.Killmail.Errors do
  @moduledoc """
  Domain-specific error types for the Killmail domain.

  Provides consistent error handling and formatting for killmail processing,
  pipeline operations, and WebSocket communication.
  """

  @doc """
  Creates a killmail processing error.

  ## Examples
      
      iex> killmail_error(:missing_id)
      {:error, {:killmail, :missing_id}}
      
      iex> killmail_error(:invalid_system_id, 12345)
      {:error, {:killmail, {:invalid_system_id, 12345}}}
  """
  def killmail_error(reason) when is_atom(reason) do
    {:error, {:killmail, reason}}
  end

  def killmail_error(reason, context) do
    {:error, {:killmail, {reason, context}}}
  end

  @doc """
  Creates a pipeline processing error.
  """
  def pipeline_error(reason) when is_atom(reason) do
    {:error, {:pipeline, reason}}
  end

  def pipeline_error(reason, context) do
    {:error, {:pipeline, {reason, context}}}
  end

  @doc """
  Creates a WebSocket communication error.
  """
  def websocket_error(reason) when is_atom(reason) do
    {:error, {:websocket, reason}}
  end

  def websocket_error(reason, context) do
    {:error, {:websocket, {reason, context}}}
  end

  @doc """
  Creates an enrichment error.
  """
  def enrichment_error(reason) when is_atom(reason) do
    {:error, {:enrichment, reason}}
  end

  def enrichment_error(reason, context) do
    {:error, {:enrichment, {reason, context}}}
  end

  @doc """
  Formats killmail domain errors into user-friendly messages.

  ## Examples

      iex> format_error({:killmail, :missing_id})
      "Killmail missing required ID"
      
      iex> format_error({:pipeline, :processing_failed})
      "Pipeline processing failed"
  """
  def format_error({:killmail, :missing_id}), do: "Killmail missing required ID"
  def format_error({:killmail, :missing_system_id}), do: "Killmail missing system ID"
  def format_error({:killmail, {:invalid_system_id, id}}), do: "Invalid system ID: #{id}"
  def format_error({:killmail, :no_recent_kills}), do: "No recent kills found"
  def format_error({:killmail, :duplicate_killmail}), do: "Duplicate killmail detected"
  def format_error({:killmail, reason}), do: "Killmail error: #{inspect(reason)}"

  def format_error({:pipeline, :processing_failed}), do: "Pipeline processing failed"
  def format_error({:pipeline, :worker_unavailable}), do: "Pipeline worker unavailable"
  def format_error({:pipeline, :invalid_data}), do: "Invalid pipeline data"
  def format_error({:pipeline, reason}), do: "Pipeline error: #{inspect(reason)}"

  def format_error({:websocket, :connection_failed}), do: "WebSocket connection failed"
  def format_error({:websocket, :authentication_failed}), do: "WebSocket authentication failed"
  def format_error({:websocket, :subscription_failed}), do: "WebSocket subscription failed"
  def format_error({:websocket, reason}), do: "WebSocket error: #{inspect(reason)}"

  def format_error({:enrichment, :api_unavailable}), do: "Enrichment API unavailable"
  def format_error({:enrichment, :data_not_found}), do: "Enrichment data not found"
  def format_error({:enrichment, :invalid_response}), do: "Invalid enrichment response"
  def format_error({:enrichment, reason}), do: "Enrichment error: #{inspect(reason)}"

  def format_error(reason), do: "Unknown killmail domain error: #{inspect(reason)}"

  @doc """
  Checks if an error is from the killmail domain.
  """
  def killmail_error?({:error, {:killmail, _}}), do: true
  def killmail_error?({:error, {:pipeline, _}}), do: true
  def killmail_error?({:error, {:websocket, _}}), do: true
  def killmail_error?({:error, {:enrichment, _}}), do: true
  def killmail_error?(_), do: false

  @doc """
  Extracts the error reason from a killmail domain error.
  """
  def extract_reason({:error, {:killmail, reason}}), do: reason
  def extract_reason({:error, {:pipeline, reason}}), do: reason
  def extract_reason({:error, {:websocket, reason}}), do: reason
  def extract_reason({:error, {:enrichment, reason}}), do: reason
  def extract_reason({:error, reason}), do: reason
end
