defmodule WandererNotifier.Domains.Killmail.StreamUtils do
  @moduledoc """
  Utility functions for processing killmail streams and aggregating results.

  This module provides common functionality for processing streams of killmail data
  from the WandererKills API, including error handling and result aggregation.
  """

  @doc """
  Aggregates results from a stream of killmail data processing.

  Takes a stream that yields tuples in the format:
  - `{:ok, {:ok, system_data}}` - Successful processing with killmail data
  - `{:ok, {:error, error}}` - Successful processing but API returned error
  - `{:error, reason}` - Task processing failed (timeouts, exits, etc.)

  Returns a map with:
  - `:loaded` - Total count of killmails processed successfully
  - `:errors` - List of errors encountered during processing

  ## Examples

      iex> stream = [{:ok, {:ok, %{"system1" => [1, 2], "system2" => [3]}}}, {:ok, {:error, "API error"}}]
      iex> WandererNotifier.Domains.Killmail.StreamUtils.aggregate_stream_results(stream)
      %{loaded: 3, errors: ["API error"]}
  """
  @spec aggregate_stream_results(Enumerable.t()) :: %{loaded: non_neg_integer(), errors: list()}
  def aggregate_stream_results(stream) do
    stream
    |> Enum.reduce(%{loaded: 0, errors: []}, fn
      {:ok, {:ok, system_data}}, acc ->
        kill_count =
          system_data
          |> Map.values()
          |> Enum.map(&length/1)
          |> Enum.sum()

        %{acc | loaded: acc.loaded + kill_count}

      {:ok, {:error, error}}, acc ->
        %{acc | errors: [error | acc.errors]}

      {:error, reason}, acc ->
        # Handle Task.async_stream timeouts or exits
        %{acc | errors: [{:task_error, reason} | acc.errors]}
    end)
  end

  @doc """
  Calculates killmail count from system data map.

  Takes a map where keys are system IDs and values are lists of killmails,
  returns the total count of killmails across all systems.

  ## Examples

      iex> system_data = %{"system1" => [1, 2, 3], "system2" => [4, 5]}
      iex> WandererNotifier.Domains.Killmail.StreamUtils.count_killmails(system_data)
      5
  """
  @spec count_killmails(map()) :: non_neg_integer()
  def count_killmails(system_data) when is_map(system_data) do
    system_data
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  def count_killmails(_), do: 0
end
