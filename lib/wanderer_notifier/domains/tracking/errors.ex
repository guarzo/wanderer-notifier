defmodule WandererNotifier.Domains.Tracking.Errors do
  @moduledoc """
  Domain-specific error types for the Tracking domain.

  Provides consistent error handling and formatting for character tracking,
  system tracking, and map integration operations.
  """

  @doc """
  Creates a character tracking error.

  ## Examples
      
      iex> character_error(:not_found)
      {:error, {:character, :not_found}}
      
      iex> character_error(:invalid_id, 12345)
      {:error, {:character, {:invalid_id, 12345}}}
  """
  def character_error(reason) when is_atom(reason) do
    {:error, {:character, reason}}
  end

  def character_error(reason, context) do
    {:error, {:character, {reason, context}}}
  end

  @doc """
  Creates a system tracking error.
  """
  def system_error(reason) when is_atom(reason) do
    {:error, {:system, reason}}
  end

  def system_error(reason, context) do
    {:error, {:system, {reason, context}}}
  end

  @doc """
  Creates a map integration error.
  """
  def map_error(reason) when is_atom(reason) do
    {:error, {:map, reason}}
  end

  def map_error(reason, context) do
    {:error, {:map, {reason, context}}}
  end

  @doc """
  Creates an SSE (Server-Sent Events) error.
  """
  def sse_error(reason) when is_atom(reason) do
    {:error, {:sse, reason}}
  end

  def sse_error(reason, context) do
    {:error, {:sse, {reason, context}}}
  end

  @doc """
  Formats tracking domain errors into user-friendly messages.

  ## Examples

      iex> format_error({:character, :not_found})
      "Character not found"
      
      iex> format_error({:system, :invalid_id})
      "Invalid system ID"
  """
  def format_error({:character, :not_found}), do: "Character not found"
  def format_error({:character, :invalid_id}), do: "Invalid character ID"
  def format_error({:character, :already_tracked}), do: "Character is already being tracked"
  def format_error({:character, :not_tracked}), do: "Character is not being tracked"
  def format_error({:character, :offline}), do: "Character is offline"
  def format_error({:character, :api_error}), do: "Character API error"
  def format_error({:character, reason}), do: "Character tracking error: #{inspect(reason)}"

  def format_error({:system, :not_found}), do: "System not found"
  def format_error({:system, :invalid_id}), do: "Invalid system ID"
  def format_error({:system, :already_tracked}), do: "System is already being tracked"
  def format_error({:system, :not_tracked}), do: "System is not being tracked"
  def format_error({:system, :access_denied}), do: "System access denied"
  def format_error({:system, reason}), do: "System tracking error: #{inspect(reason)}"

  def format_error({:map, :connection_failed}), do: "Map connection failed"
  def format_error({:map, :authentication_failed}), do: "Map authentication failed"
  def format_error({:map, :invalid_credentials}), do: "Invalid map credentials"
  def format_error({:map, :api_unavailable}), do: "Map API unavailable"
  def format_error({:map, :rate_limited}), do: "Map API rate limited"
  def format_error({:map, reason}), do: "Map integration error: #{inspect(reason)}"

  def format_error({:sse, :connection_failed}), do: "SSE connection failed"
  def format_error({:sse, :stream_interrupted}), do: "SSE stream interrupted"
  def format_error({:sse, :parse_error}), do: "SSE data parse error"
  def format_error({:sse, :authentication_failed}), do: "SSE authentication failed"
  def format_error({:sse, reason}), do: "SSE error: #{inspect(reason)}"

  def format_error(reason), do: "Unknown tracking domain error: #{inspect(reason)}"

  @doc """
  Checks if an error is from the tracking domain.
  """
  def tracking_error?({:error, {:character, _}}), do: true
  def tracking_error?({:error, {:system, _}}), do: true
  def tracking_error?({:error, {:map, _}}), do: true
  def tracking_error?({:error, {:sse, _}}), do: true
  def tracking_error?(_), do: false

  @doc """
  Extracts the error reason from a tracking domain error.
  """
  def extract_reason({:error, {:character, reason}}), do: reason
  def extract_reason({:error, {:system, reason}}), do: reason
  def extract_reason({:error, {:map, reason}}), do: reason
  def extract_reason({:error, {:sse, reason}}), do: reason
  def extract_reason({:error, reason}), do: reason

  @doc """
  Categorizes tracking errors for logging and monitoring.
  """
  def categorize_error({:character, _}), do: :character_tracking
  def categorize_error({:system, _}), do: :system_tracking
  def categorize_error({:map, _}), do: :map_integration
  def categorize_error({:sse, _}), do: :real_time_events
  def categorize_error(_), do: :unknown_tracking
end
