defmodule WandererNotifier.Infrastructure.ProcessInspection do
  @moduledoc """
  Utilities for inspecting process types and states.

  This module provides shared helpers for detecting specific process types
  (e.g., Gun connection processes) used by multiple modules for diagnostics.
  """

  require Logger

  @doc """
  Detects if a process is a Gun connection process.

  Checks the process in two ways:
  1. First checks `:registered_name` - if it contains "gun" (case-insensitive), returns true
  2. Falls back to checking the process dictionary for `:"$initial_call"` matching `{:gun, _, _}`

  Returns `{:ok, true}` if the process is a Gun process, `{:ok, false}` otherwise.
  Returns `{:error, reason}` if an exception occurs during inspection.

  Note: Dead or missing PIDs return `{:ok, false}` since we cannot determine their type.

  ## Examples

      iex> ProcessInspection.detect_gun_process(some_pid)
      {:ok, true}

      iex> ProcessInspection.detect_gun_process(non_gun_pid)
      {:ok, false}

      iex> ProcessInspection.detect_gun_process(dead_pid)
      {:ok, false}
  """
  @spec detect_gun_process(pid()) :: {:ok, boolean()} | {:error, term()}
  def detect_gun_process(pid) when is_pid(pid) do
    result =
      case check_registered_name(pid) do
        {:found, true} -> true
        {:found, false} -> check_initial_call(pid)
        :not_found -> check_initial_call(pid)
      end

    {:ok, result}
  catch
    kind, reason ->
      Logger.error(
        "[ProcessInspection] Error detecting Gun process",
        pid: inspect(pid),
        kind: kind,
        reason: inspect(reason)
      )

      {:error, reason}
  end

  # Check if the registered name contains "gun"
  defp check_registered_name(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when is_atom(name) ->
        is_gun =
          name
          |> Atom.to_string()
          |> String.downcase()
          |> String.contains?("gun")

        {:found, is_gun}

      {:registered_name, []} ->
        # Process has no registered name
        :not_found

      nil ->
        # Process no longer exists
        :not_found

      _ ->
        :not_found
    end
  end

  # Check if the process dictionary indicates a Gun process
  defp check_initial_call(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} when is_list(dict) ->
        case Keyword.get(dict, :"$initial_call") do
          {:gun, _, _} -> true
          _ -> false
        end

      nil ->
        # Process no longer exists
        false

      _ ->
        false
    end
  end
end
